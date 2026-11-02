// Load models and generate incremental ChatML replies on a worker thread.
#include "llm.h"
#include "llama.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <stdexcept>
#include <iomanip>
#include <sstream>
#include <sys/stat.h>
#include <cerrno>
#include <cstring>
#include <unistd.h>
#include <vector>

namespace r36 {
using Clock = std::chrono::steady_clock;

static double seconds(Clock::time_point start) {
    return std::chrono::duration<double>(Clock::now() - start).count();
}

namespace {
constexpr size_t MaxSnapshot = 256 * 1024 * 1024;
constexpr const char *CacheDir = "/data/r36llm/cache";

// FNV-1a is an integrity checksum, not an authentication boundary. Cache files
// are local application data; every byte is checked before entering llama.
uint64_t checksum(const uint8_t *data, size_t size) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < size; ++i) {
        hash ^= data[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

std::string hex(uint64_t value) {
    std::ostringstream out;
    out << std::hex << std::setfill('0') << std::setw(16) << value;
    return out.str();
}

std::string system_history(const Config &config) {
    return "<|im_start|>system\n" + config.system + "<|im_end|>\n";
}
} // namespace

std::string prompt_cache_key(const std::string &path, uint64_t size, int64_t mtime,
                             const std::string &system, int ctx, bool think,
                             const std::string &engine) {
    std::string identity = "r36llm-system-cache-1";
    for (const auto &field : {path, std::to_string(size), std::to_string(mtime), system,
                              std::to_string(ctx), std::to_string(think), engine})
        identity += std::to_string(field.size()) + ":" + field;
    return hex(checksum(reinterpret_cast<const uint8_t *>(identity.data()), identity.size()));
}

std::string prompt_cache_filename(const std::string &key) {
    if (key.size() != 16 || key.find_first_not_of("0123456789abcdef") != std::string::npos)
        return {};
    return std::string(CacheDir) + "/" + key + ".kv";
}

std::string prompt_cache_header(const std::string &key, uint64_t tokens,
                                const std::vector<uint8_t> &payload) {
    return "R36KV001\n" + key + "\n" + std::to_string(tokens) + "\n" +
           std::to_string(payload.size()) + "\n" + hex(checksum(payload.data(), payload.size())) +
           "\n";
}

bool validate_prompt_cache(const std::string &header, const std::string &key, uint64_t tokens,
                           const std::vector<uint8_t> &payload) {
    return !prompt_cache_filename(key).empty() && tokens > 0 && !payload.empty() &&
           payload.size() <= MaxSnapshot && header == prompt_cache_header(key, tokens, payload);
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

Llm::Llm(bool prompt_cache, uint32_t seed) : cache_enabled_(prompt_cache), seed_(seed) {
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
    system_history_.clear();
    system_snapshot_.clear();
    cache_key_.clear();
    system_tokens_ = 0;
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
        restore_system();
    if (sampler_)
        llama_sampler_reset(sampler_);
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
            cp.abort_callback = [](void *opaque) {
                return static_cast<Llm *>(opaque)->stop_.load();
            };
            cp.abort_callback_data = this;
            context_ = llama_init_from_model(model_, cp);
            if (!context_)
                throw std::runtime_error("Load failed: context allocation");
            batch_ = llama_batch_ext_init(context_);
            if (!batch_)
                throw std::runtime_error("Load failed: batch allocation");
            const char *tmpl = llama_model_chat_template(model_, nullptr);
            think_ = tmpl && std::string(tmpl).find("<think>") != std::string::npos;
            struct stat info {};
            if (stat(path.c_str(), &info) == 0)
                cache_key_ = prompt_cache_key(
                    path, static_cast<uint64_t>(info.st_size),
                    static_cast<int64_t>(info.st_mtim.tv_sec) * 1000000000 + info.st_mtim.tv_nsec,
                    config.system, config.ctx, think_,
                    R36LLM_ENGINE_VERSION ":" + std::to_string(LLAMA_STATE_SEQ_VERSION));
            if (cache_enabled_)
                prepare_system(config);
            if (stop_)
                throw std::runtime_error("Load cancelled");
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
        state_.first_token_seconds = 0;
        state_.generated_tokens = 0;
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

std::vector<int32_t> Llm::tokenize(const std::string &text, bool first) const {
    const auto *vocab = llama_model_get_vocab(model_);
    int count = llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), nullptr,
                               0, first, true);
    if (count >= 0)
        throw std::runtime_error("Prompt tokenization failed");
    std::vector<int32_t> tokens(static_cast<size_t>(-count));
    count = llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), tokens.data(),
                           static_cast<int32_t>(tokens.size()), first, true);
    if (count < 0)
        throw std::runtime_error("Prompt tokenization failed");
    tokens.resize(static_cast<size_t>(count));
    return tokens;
}

void Llm::evaluate(const int32_t *tokens, int count) {
    if (stop_)
        throw std::runtime_error("Cancelled");
    const int used = llama_memory_seq_pos_max(llama_get_memory(context_), 0) + 1;
    if (count <= 0 || used + count > static_cast<int>(llama_n_ctx(context_)))
        throw std::runtime_error("Context full - SELECT+START for new chat");
    llama_batch_ext_clear(batch_);
    for (int i = 0; i < count; ++i) {
        int index = llama_batch_ext_add_token(batch_, 0, tokens[i]);
        llama_pos position = used + i;
        if (index < 0 || !llama_batch_ext_set_pos(batch_, index, &position))
            throw std::runtime_error("Batch setup failed");
    }
    llama_batch_ext_set_output_logits(batch_, count - 1, true);
    if (llama_process(context_, LLAMA_PROCESS_TYPE_DECODE, batch_) != 0)
        throw std::runtime_error(stop_ ? "Cancelled" : "Model processing failed - start a new chat");
}

bool Llm::restore_system() {
    llama_memory_clear(llama_get_memory(context_), true);
    history_.clear();
    evaluated_ = 0;
    if (system_snapshot_.empty())
        return false;
    if (llama_state_seq_set_data(context_, system_snapshot_.data(), system_snapshot_.size(), 0) !=
            system_snapshot_.size() ||
        llama_memory_seq_pos_max(llama_get_memory(context_), 0) + 1 !=
            static_cast<int>(system_tokens_)) {
        llama_memory_clear(llama_get_memory(context_), true);
        system_snapshot_.clear();
        return false;
    }
    history_ = system_history_;
    evaluated_ = history_.size();
    return true;
}

void Llm::prepare_system(const Config &config) {
    system_history_ = system_history(config);
    auto tokens = tokenize(system_history_, true);
    system_tokens_ = tokens.size();
    const auto filename = prompt_cache_filename(cache_key_);
    if (!filename.empty()) {
        std::ifstream file(filename, std::ios::binary | std::ios::ate);
        const auto file_size = file.tellg();
        if (file && file_size > 0 &&
            file_size <= static_cast<std::streamoff>(MaxSnapshot + 256)) {
            file.seekg(0);
            std::string header;
            int lines = 0;
            char byte;
            while (header.size() < 256 && lines < 5 && file.get(byte)) {
                header += byte;
                if (byte == '\n')
                    ++lines;
            }
            if (lines == 5 && file_size > static_cast<std::streamoff>(header.size())) {
                const size_t bytes = static_cast<size_t>(file_size) - header.size();
                if (bytes <= MaxSnapshot) {
                    system_snapshot_.resize(bytes);
                    file.read(reinterpret_cast<char *>(system_snapshot_.data()),
                              static_cast<std::streamsize>(bytes));
                    if (file && validate_prompt_cache(header, cache_key_, system_tokens_,
                                                       system_snapshot_) &&
                        !stop_ && restore_system()) {
                        std::fprintf(stderr, "system cache: disk hit (%zu tokens)\n", system_tokens_);
                        return;
                    }
                }
            }
        }
    }
    system_snapshot_.clear();
    llama_memory_clear(llama_get_memory(context_), true);
    history_.clear();
    evaluated_ = 0;
    evaluate(tokens.data(), static_cast<int>(tokens.size()));
    history_ = system_history_;
    evaluated_ = history_.size();
    const size_t bytes = llama_state_seq_get_size(context_, 0);
    if (!bytes || bytes > MaxSnapshot)
        return;
    system_snapshot_.resize(bytes);
    if (llama_state_seq_get_data(context_, system_snapshot_.data(), bytes, 0) != bytes) {
        system_snapshot_.clear();
        return;
    }
    std::fprintf(stderr, "system cache: prepared (%zu tokens, %zu bytes)\n", system_tokens_, bytes);
    if (stop_ || filename.empty() || (mkdir(CacheDir, 0755) != 0 && errno != EEXIST))
        return;
    const std::string temporary = filename + ".tmp." + std::to_string(getpid());
    FILE *file = std::fopen(temporary.c_str(), "wb");
    if (!file)
        return;
    const auto header = prompt_cache_header(cache_key_, system_tokens_, system_snapshot_);
    bool written = std::fwrite(header.data(), 1, header.size(), file) == header.size() &&
                   std::fwrite(system_snapshot_.data(), 1, bytes, file) == bytes &&
                   std::fflush(file) == 0 && fsync(fileno(file)) == 0;
    if (std::fclose(file) != 0)
        written = false;
    if (written && !stop_) {
        if (std::rename(temporary.c_str(), filename.c_str()) != 0 &&
            (errno == EEXIST || errno == EACCES || errno == ENOTEMPTY)) {
            // FAT cannot rename over an existing file. A crash in this gap
            // causes a cache miss, never a partially published snapshot.
            if (unlink(filename.c_str()) == 0)
                std::rename(temporary.c_str(), filename.c_str());
        }
    }
    unlink(temporary.c_str());
}

void Llm::run_generation(const std::string &user, const Config &config) {
    const auto request_start = Clock::now();
    if (system_history_ != system_history(config) && cache_enabled_) {
        // A changed prompt invalidates the loaded prefix. The normal UI reloads
        // settings while idle; do not apply an old snapshot to the new prompt.
        system_snapshot_.clear();
        cache_key_.clear();
        prepare_system(config);
    }
    if (history_.empty())
        history_ = system_history(config);
    history_ += "<|im_start|>user\n" + user + "<|im_end|>\n<|im_start|>assistant\n";
    if (think_)
        history_ += "<think>\n\n</think>\n\n";
    const std::string suffix = history_.substr(evaluated_);
    const auto *vocab = llama_model_get_vocab(model_);
    const bool first = llama_memory_seq_pos_max(llama_get_memory(context_), 0) == -1;
    auto tokens = tokenize(suffix, first);
    const int count = static_cast<int>(tokens.size());
    if (sampler_)
        llama_sampler_free(sampler_);
    sampler_ = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler_, llama_sampler_init_top_k(config.top_k));
    llama_sampler_chain_add(sampler_, llama_sampler_init_top_p(config.top_p, 1));
    llama_sampler_chain_add(sampler_, llama_sampler_init_temp(config.temp));
    llama_sampler_chain_add(sampler_, llama_sampler_init_dist(seed_));
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
            if (generated == 1)
                state_.first_token_seconds = seconds(request_start);
            state_.generated_tokens = generated;
            state_.generation_tps = generated / std::max(seconds(generation_start), 0.000001);
        }
    }
    history_ += "<|im_end|>\n";
}
} // namespace r36
