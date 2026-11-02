// Load models and generate incremental ChatML replies on a worker thread.
#include "llm.h"
#include "llama.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <stdexcept>
#include <unistd.h>
#include <vector>

namespace r36 {
using Clock = std::chrono::steady_clock;

static double seconds(Clock::time_point start) {
    return std::chrono::duration<double>(Clock::now() - start).count();
}

std::string strip_thinking(const std::string &raw) {
    std::string out;
    bool hidden = false;
    for (size_t i = 0; i < raw.size();) {
        const std::string tag = hidden ? "</think>" : "<think>";
        if (raw.compare(i, tag.size(), tag) == 0) {
            hidden = !hidden;
            i += tag.size();
            continue;
        }
        // Withhold an incomplete tag until the following token resolves it.
        if (raw.size() - i < tag.size() &&
            tag.compare(0, raw.size() - i, raw, i, raw.size() - i) == 0)
            break;
        if (!hidden)
            out += raw[i];
        ++i;
    }
    return out;
}

Llm::Llm() {
    llama_log_set(
        [](ggml_log_level level, const char *text, void *) {
            if (level >= GGML_LOG_LEVEL_ERROR)
                std::fputs(text, stderr);
        },
        nullptr);
    llama_backend_init();
}

Llm::~Llm() {
    stop();
    if (worker_.joinable())
        worker_.join();
    release();
    llama_backend_free();
}

LlmState Llm::state() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return state_;
}

bool Llm::begin() {
    if (state().busy)
        return false;
    if (worker_.joinable())
        worker_.join();
    stop_ = false;
    std::lock_guard<std::mutex> lock(mutex_);
    state_.busy = true;
    state_.error.clear();
    return true;
}

void Llm::stop() {
    stop_ = true;
}

void Llm::finish(const std::string &error) {
    std::lock_guard<std::mutex> lock(mutex_);
    state_.error = error;
    state_.busy = false;
    state_.loading = false;
    ++state_.completed;
}

void Llm::release() {
    if (batch_)
        llama_batch_ext_free(batch_);
    if (sampler_)
        llama_sampler_free(sampler_);
    if (context_)
        llama_free(context_);
    if (model_)
        llama_model_free(model_);
    batch_ = nullptr;
    sampler_ = nullptr;
    context_ = nullptr;
    model_ = nullptr;
    history_.clear();
    evaluated_ = 0;
}

void Llm::unload() {
    stop();
    if (worker_.joinable())
        worker_.join();
    release();
    std::lock_guard<std::mutex> lock(mutex_);
    state_.loaded = false;
    state_.model.clear();
    state_.text.clear();
}

void Llm::clear() {
    stop();
    if (worker_.joinable())
        worker_.join();
    if (context_)
        llama_memory_clear(llama_get_memory(context_), true);
    if (sampler_)
        llama_sampler_reset(sampler_);
    history_.clear();
    evaluated_ = 0;
    std::lock_guard<std::mutex> lock(mutex_);
    state_.text.clear();
    state_.error.clear();
}

bool Llm::load(const std::string &path, const Config &config) {
    if (!begin())
        return false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        state_.loading = true;
        state_.loaded = false;
        state_.progress = 0;
        state_.model = path;
        state_.text.clear();
    }
    worker_ = std::thread([this, path, config] {
        release();
        // Keep the marker on failure too: a failed or killed load must not loop on respawn.
        std::ofstream marker("/tmp/r36llm.loading");
        marker << path << '\n';
        marker.close();
        try {
            auto mp = llama_model_default_params();
            mp.n_gpu_layers = 0;
            // At this pin mmap is an enum, not the old use_mmap boolean.
            mp.load_mode = LLAMA_LOAD_MODE_MMAP;
            mp.progress_callback = [](float progress, void *opaque) {
                auto *self = static_cast<Llm *>(opaque);
                {
                    std::lock_guard<std::mutex> lock(self->mutex_);
                    self->state_.progress = progress;
                }
                return !self->stop_.load();
            };
            mp.progress_callback_user_data = this;
            model_ = llama_model_load_from_file(path.c_str(), mp);
            if (!model_)
                throw std::runtime_error("Load failed: " + path);
            auto cp = llama_context_default_params();
            cp.n_ctx = config.ctx;
            cp.n_batch = config.ctx;
            cp.n_threads = config.threads;
            cp.n_threads_batch = config.threads;
            context_ = llama_init_from_model(model_, cp);
            if (!context_)
                throw std::runtime_error("Load failed: context allocation");
            batch_ = llama_batch_ext_init(context_);
            if (!batch_)
                throw std::runtime_error("Load failed: batch allocation");
            const char *tmpl = llama_model_chat_template(model_, nullptr);
            think_ = tmpl && std::string(tmpl).find("<think>") != std::string::npos;
            unlink("/tmp/r36llm.loading");
            {
                std::lock_guard<std::mutex> lock(mutex_);
                state_.loaded = true;
                state_.progress = 1;
            }
            finish();
        } catch (const std::exception &e) {
            release();
            finish(e.what());
        }
    });
    return true;
}

bool Llm::generate(const std::string &user, const Config &config) {
    if (!state().loaded || !begin())
        return false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        state_.text.clear();
        state_.generation_tps = 0;
        state_.prompt_tps = 0;
    }
    worker_ = std::thread([this, user, config] {
        try {
            run_generation(user, config);
            finish();
        } catch (const std::exception &e) {
            finish(e.what());
        }
    });
    return true;
}

void Llm::run_generation(const std::string &user, const Config &config) {
    if (history_.empty())
        history_ = "<|im_start|>system\n" + config.system + "<|im_end|>\n";
    history_ += "<|im_start|>user\n" + user + "<|im_end|>\n<|im_start|>assistant\n";
    if (think_)
        history_ += "<think>\n\n</think>\n\n";
    const std::string suffix = history_.substr(evaluated_);
    const auto *vocab = llama_model_get_vocab(model_);
    const bool first = llama_memory_seq_pos_max(llama_get_memory(context_), 0) == -1;
    int needed = llama_tokenize(vocab, suffix.data(), static_cast<int32_t>(suffix.size()), nullptr,
                                0, first, true);
    if (needed >= 0)
        throw std::runtime_error("Prompt tokenization failed");
    std::vector<llama_token> tokens(static_cast<size_t>(-needed));
    int count = llama_tokenize(vocab, suffix.data(), static_cast<int32_t>(suffix.size()),
                               tokens.data(), static_cast<int32_t>(tokens.size()), first, true);
    if (count < 0)
        throw std::runtime_error("Prompt tokenization failed");
    auto evaluate = [&](const llama_token *input, int n) {
        const int used = llama_memory_seq_pos_max(llama_get_memory(context_), 0) + 1;
        if (used + n > static_cast<int>(llama_n_ctx(context_)))
            throw std::runtime_error("Context full - SELECT+START for new chat");
        llama_batch_ext_clear(batch_);
        for (int i = 0; i < n; ++i) {
            int index = llama_batch_ext_add_token(batch_, 0, input[i]);
            llama_pos position = used + i;
            if (index < 0 || !llama_batch_ext_set_pos(batch_, index, &position))
                throw std::runtime_error("Batch setup failed");
        }
        llama_batch_ext_set_output_logits(batch_, n - 1, true);
        if (llama_process(context_, LLAMA_PROCESS_TYPE_DECODE, batch_) != 0)
            throw std::runtime_error("Model processing failed - start a new chat");
    };
    if (sampler_)
        llama_sampler_free(sampler_);
    sampler_ = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(config.top_k));
    llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(config.top_p, 1));
    llama_sampler_chain_add(sampler_, llama_sampler_init_temp(config.temp));
    llama_sampler_chain_add(sampler_, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    auto prompt_start = Clock::now();
    evaluate(tokens.data(), count);
    evaluated_ = history_.size();
    {
        std::lock_guard<std::mutex> lock(mutex_);
        state_.prompt_tps = count / std::max(seconds(prompt_start), 0.000001);
    }
    std::string reply;
    auto generation_start = Clock::now();
    int generated = 0;
    for (int i = 0; i < config.max_tokens && !stop_; ++i) {
        llama_token token = llama_sampler_sample(sampler_, context_, -1);
        if (llama_vocab_is_eog(vocab, token))
            break;
        char buffer[256];
        int n = llama_token_to_piece(vocab, token, buffer, sizeof(buffer), 0, true);
        std::string piece;
        if (n < 0) {
            std::vector<char> large(static_cast<size_t>(-n));
            n = llama_token_to_piece(vocab, token, large.data(), static_cast<int32_t>(large.size()),
                                     0, true);
            if (n < 0)
                throw std::runtime_error("Token conversion failed");
            piece.assign(large.data(), static_cast<size_t>(n));
        } else
            piece.assign(buffer, static_cast<size_t>(n));
        // Evaluate even the final displayed token, so only the true new suffix is tokenized next
        // turn.
        evaluate(&token, 1);
        reply += piece;
        history_ += piece;
        evaluated_ = history_.size();
        ++generated;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            state_.text = strip_thinking(reply);
            state_.generation_tps = generated / std::max(seconds(generation_start), 0.000001);
        }
    }
    history_ += "<|im_end|>\n";
}
} // namespace r36
