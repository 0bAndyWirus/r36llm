#include "llama.h"
#include "ggml.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;
using Seconds = std::chrono::duration<double>;
constexpr int generated_tokens = 128;

struct Profile {
    Clock::time_point start;
    double head_seconds = 0;
    uint64_t head_nodes = 0;
    bool enabled = false;
};

// Request every node, so the interval between ask and observation covers only
// that node rather than all preceding nodes in the scheduler's graph slice.
static bool profile_node(ggml_tensor * tensor, bool ask, void * data) {
    auto & p = *static_cast<Profile *>(data);
    if (!p.enabled) return false;
    if (ask) {
        p.start = Clock::now();
        return true;
    }
    const double elapsed = Seconds(Clock::now() - p.start).count();
    const char * name = ggml_get_name(tensor);
    if (std::strcmp(name, "result_output") == 0 ||
        std::strcmp(name, "output_keep_gemv") == 0 ||
        std::strcmp(name, "output_keep_quantize") == 0 ||
        std::strcmp(name, "output_keep_scatter") == 0) {
        p.head_seconds += elapsed;
        ++p.head_nodes;
    }
    return true;
}

using Model = std::unique_ptr<llama_model, decltype(&llama_model_free)>;
using Context = std::unique_ptr<llama_context, decltype(&llama_free)>;

static Context context(llama_model * model, Profile * profile = nullptr) {
    auto params = llama_context_default_params();
    params.n_ctx = 2048;
    params.n_batch = 512;
    params.n_ubatch = 512;
    params.n_threads = 4;
    params.n_threads_batch = 4;
    if (profile) {
        params.cb_eval = profile_node;
        params.cb_eval_user_data = profile;
    }
    Context result(llama_init_from_model(model, params), llama_free);
    if (!result) throw std::runtime_error("could not create context");
    return result;
}

static std::string read_file(const char * path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error(std::string("cannot open ") + path);
    std::ostringstream contents;
    contents << file.rdbuf();
    if (file.bad()) throw std::runtime_error(std::string("cannot read ") + path);
    return contents.str();
}

static std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & text, bool special) {
    if (text.size() > static_cast<size_t>(std::numeric_limits<int32_t>::max())) throw std::runtime_error("input too large");
    int32_t n = llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), nullptr, 0, special, special);
    if (n == std::numeric_limits<int32_t>::min()) throw std::runtime_error("tokenization overflow");
    if (n > 0) throw std::runtime_error("unexpected tokenizer size result");
    std::vector<llama_token> tokens(static_cast<size_t>(-n));
    if (!tokens.empty()) {
        n = llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), tokens.data(), static_cast<int32_t>(tokens.size()), special, special);
        if (n < 0 || static_cast<size_t>(n) != tokens.size()) throw std::runtime_error("tokenization failed");
    }
    return tokens;
}

static std::string chat_prompt(const llama_model * model, const char * text) {
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (!tmpl || !*tmpl) return std::string("User: ") + text + "\nAssistant:";
    llama_chat_message msg = {"user", text};
    int32_t n = llama_chat_apply_template(tmpl, &msg, 1, true, nullptr, 0);
    if (n < 0) throw std::runtime_error("model chat template is unsupported");
    std::vector<char> buf(static_cast<size_t>(n) + 1);
    int32_t written = llama_chat_apply_template(tmpl, &msg, 1, true, buf.data(), static_cast<int32_t>(buf.size()));
    if (written != n) throw std::runtime_error("chat template failed");
    return std::string(buf.data(), static_cast<size_t>(n));
}

static std::vector<bool> load_keep(const char * path, int vocab_size) {
    std::ifstream file(path);
    if (!file) throw std::runtime_error(std::string("cannot open ") + path);
    std::vector<bool> keep(vocab_size, false);
    std::string line;
    int previous = -1;
    while (std::getline(file, line)) {
        const auto comment = line.find('#');
        if (comment != std::string::npos) line.resize(comment);
        std::istringstream input(line);
        input >> std::ws;
        if (input.eof()) continue;
        int id;
        if (!(input >> id) || id <= previous || id >= vocab_size) throw std::runtime_error("invalid or unsorted keep list");
        input >> std::ws;
        if (!input.eof()) throw std::runtime_error("invalid keep list line");
        keep[id] = true;
        previous = id;
    }
    if (file.bad() || previous < 0) throw std::runtime_error("empty or unreadable keep list");
    return keep;
}

static void decode(llama_context * ctx, const std::vector<llama_token> & tokens) {
    if (tokens.empty() || tokens.size() > 512) throw std::runtime_error("prompt must have 1..512 tokens");
    // llama_batch_get_one does not modify the token array.
    auto batch = llama_batch_get_one(const_cast<llama_token *>(tokens.data()), static_cast<int32_t>(tokens.size()));
    if (llama_decode(ctx, batch) != 0) throw std::runtime_error("prompt decode failed");
}

static double step(llama_context * ctx, llama_token token) {
    auto batch = llama_batch_get_one(&token, 1);
    auto start = Clock::now();
    if (llama_decode(ctx, batch) != 0) throw std::runtime_error("token decode failed");
    return Seconds(Clock::now() - start).count();
}

static const float * logits(llama_context * ctx) {
    const float * result = llama_get_logits_ith(ctx, -1);
    if (!result) throw std::runtime_error("missing logits");
    return result;
}

static llama_token greedy(const float * values, int n) {
    return static_cast<llama_token>(std::max_element(values, values + n) - values);
}

static std::string token_piece(const llama_vocab * vocab, llama_token token) {
    std::vector<char> buf(32);
    int32_t n = llama_token_to_piece(vocab, token, buf.data(), static_cast<int32_t>(buf.size()), 0, true);
    if (n == std::numeric_limits<int32_t>::min()) throw std::runtime_error("token piece overflow");
    if (n < 0) {
        buf.resize(static_cast<size_t>(-n));
        n = llama_token_to_piece(vocab, token, buf.data(), static_cast<int32_t>(buf.size()), 0, true);
    }
    if (n < 0 || static_cast<size_t>(n) > buf.size()) throw std::runtime_error("token piece conversion failed");
    return std::string(buf.data(), static_cast<size_t>(n));
}

static std::string trajectory_text(const llama_vocab * vocab, const std::vector<llama_token> & tokens) {
    std::string text;
    for (llama_token token : tokens) text += token_piece(vocab, token);
    return text;
}

static void json_string(std::ostream & out, const std::string & text) {
    out << '"';
    for (size_t i = 0; i < text.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(text[i]);
        if (c >= 0x80) {
            size_t len = c >= 0xc2 && c <= 0xdf ? 2 : c >= 0xe0 && c <= 0xef ? 3 : c >= 0xf0 && c <= 0xf4 ? 4 : 0;
            bool valid = len && i + len <= text.size();
            for (size_t j = 1; valid && j < len; ++j) {
                unsigned char next = static_cast<unsigned char>(text[i + j]);
                valid = next >= 0x80 && next <= 0xbf;
            }
            if (valid && len >= 3) {
                unsigned char next = static_cast<unsigned char>(text[i + 1]);
                valid = !(c == 0xe0 && next < 0xa0) && !(c == 0xed && next >= 0xa0) &&
                        !(c == 0xf0 && next < 0x90) && !(c == 0xf4 && next >= 0x90);
            }
            if (valid) { out.write(text.data() + i, static_cast<std::streamsize>(len)); i += len - 1; }
            else out << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << int(c) << std::dec << std::setfill(' ');
            continue;
        }
        switch (c) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (c < 0x20) out << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << int(c) << std::dec << std::setfill(' ');
                else out << static_cast<char>(c);
        }
    }
    out << '"';
}

struct PromptResult {
    std::string prompt;
    std::string full_text, restricted_text, full_piece, restricted_piece;
    int prompt_tokens = 0;
    uint64_t kept_mismatches = 0, dropped_mismatches = 0;
    int first_kept_step = -1, first_kept_token = -1;
    int first_dropped_step = -1, first_dropped_token = -1;
    int divergence_step = -1, full_token = -1, restricted_token = -1;
    double full_seconds = 0, restricted_seconds = 0;
    double full_profile_seconds = 0, restricted_profile_seconds = 0;
    Profile full_profile, restricted_profile;
};

static void profile_trajectory(llama_model * model, const std::vector<llama_token> & prompt, int vocab_size,
                               Profile & profile, double & elapsed) {
    auto ctx = context(model, &profile);
    decode(ctx.get(), prompt);
    profile.enabled = true;
    for (int i = 1; i < generated_tokens; ++i) {
        llama_token token = greedy(logits(ctx.get()), vocab_size);
        elapsed += step(ctx.get(), token);
    }
    profile.enabled = false;
}

int main(int argc, char ** argv) {
    if (argc != 4) {
        std::cerr << "usage: compare MODEL KEEP_LIST CORPUS\n";
        return 2;
    }
    try {
        llama_backend_init();
        auto params = llama_model_default_params();
        params.n_gpu_layers = 0;
        if (unsetenv("LLAMA_OUTPUT_KEEP") != 0) throw std::runtime_error("unsetenv failed");
        Model full(llama_model_load_from_file(argv[1], params), llama_model_free);
        if (!full) throw std::runtime_error("full model load failed");
        if (setenv("LLAMA_OUTPUT_KEEP", argv[2], 1) != 0) throw std::runtime_error("setenv failed");
        Model restricted(llama_model_load_from_file(argv[1], params), llama_model_free);
        if (!restricted) throw std::runtime_error("restricted model load failed");
        const auto * vocab = llama_model_get_vocab(full.get());
        const auto * restricted_vocab = llama_model_get_vocab(restricted.get());
        const int n = llama_vocab_n_tokens(vocab);
        if (n <= 0 || n != llama_vocab_n_tokens(restricted_vocab)) throw std::runtime_error("vocabulary sizes differ");
        auto keep = load_keep(argv[2], n);
        const auto corpus = read_file(argv[3]);
        const auto corpus_tokens = tokenize(vocab, corpus, false);
        if (corpus_tokens != tokenize(restricted_vocab, corpus, false)) throw std::runtime_error("corpus tokenizers differ");
        std::set<int> misses;
        for (auto token : corpus_tokens) {
            if (token < 0 || token >= n) throw std::runtime_error("invalid corpus token");
            if (!keep[token]) misses.insert(token);
        }
        const char * prompts[] = {
            "Explain why the sky is blue in simple terms.",
            "Write a short dialogue between two friends planning a train trip.",
            "Explique pourquoi le ciel est bleu avec des mots simples.",
            "Écris une courte conversation entre deux amis qui préparent un voyage en train."
        };
        std::vector<PromptResult> results;
        auto full_ctx = context(full.get());
        auto restricted_ctx = context(restricted.get());
        for (const char * text : prompts) {
            PromptResult r;
            r.prompt = text;
            const auto formatted = chat_prompt(full.get(), text);
            if (formatted != chat_prompt(restricted.get(), text)) throw std::runtime_error("chat templates differ");
            const auto tokens = tokenize(vocab, formatted, true);
            if (tokens != tokenize(restricted_vocab, formatted, true)) throw std::runtime_error("prompt tokenizers differ");
            r.prompt_tokens = static_cast<int>(tokens.size());
            llama_memory_clear(llama_get_memory(full_ctx.get()), true);
            llama_memory_clear(llama_get_memory(restricted_ctx.get()), true);
            decode(full_ctx.get(), tokens);
            decode(restricted_ctx.get(), tokens);
            std::vector<llama_token> full_trajectory;
            for (int i = 0; i < generated_tokens; ++i) {
                const auto * a = logits(full_ctx.get());
                const auto * b = logits(restricted_ctx.get());
                for (int id = 0; id < n; ++id) {
                    if (keep[id]) {
                        if (std::memcmp(a + id, b + id, sizeof(float)) != 0) {
                            ++r.kept_mismatches;
                            if (r.first_kept_step < 0) { r.first_kept_step = i; r.first_kept_token = id; }
                        }
                    } else if (!std::isinf(b[id]) || b[id] > 0) {
                        ++r.dropped_mismatches;
                        if (r.first_dropped_step < 0) { r.first_dropped_step = i; r.first_dropped_token = id; }
                    }
                }
                const llama_token next = greedy(a, n);
                full_trajectory.push_back(next);
                if (i + 1 < generated_tokens) {
                    r.full_seconds += step(full_ctx.get(), next);
                    step(restricted_ctx.get(), next);
                }
            }
            // Replay independently: after divergence this no longer follows the full trajectory.
            llama_memory_clear(llama_get_memory(restricted_ctx.get()), true);
            decode(restricted_ctx.get(), tokens);
            std::vector<llama_token> restricted_trajectory;
            for (int i = 0; i < generated_tokens; ++i) {
                llama_token next = greedy(logits(restricted_ctx.get()), n);
                restricted_trajectory.push_back(next);
                if (r.divergence_step < 0 && next != full_trajectory[i]) {
                    r.divergence_step = i; r.full_token = full_trajectory[i]; r.restricted_token = next;
                }
                if (i + 1 < generated_tokens) r.restricted_seconds += step(restricted_ctx.get(), next);
            }
            r.full_text = trajectory_text(vocab, full_trajectory);
            r.restricted_text = trajectory_text(restricted_vocab, restricted_trajectory);
            if (r.divergence_step >= 0) {
                r.full_piece = token_piece(vocab, r.full_token);
                r.restricted_piece = token_piece(restricted_vocab, r.restricted_token);
            }
            profile_trajectory(full.get(), tokens, n, r.full_profile, r.full_profile_seconds);
            profile_trajectory(restricted.get(), tokens, n, r.restricted_profile, r.restricted_profile_seconds);
            results.push_back(r);
        }
        std::cout << std::setprecision(10);
        std::cout << "{\"threads\":4,\"generation_tokens\":" << generated_tokens
                  << ",\"generation_policy\":\"greedy, fixed length; EOG tokens do not stop generation\""
                  << ",\"timed_decode_tokens_per_prompt\":" << generated_tokens - 1
                  << ",\"vocab_size\":" << n << ",\"kept_count\":" << std::count(keep.begin(), keep.end(), true)
                  << ",\"corpus_token_count\":" << corpus_tokens.size() << ",\"corpus_unique_misses\":[";
        bool first = true;
        for (int id : misses) { if (!first) std::cout << ','; first = false; std::cout << id; }
        std::cout << "],\"profile_method\":\"scheduler callback isolates every node; profile timing is instrumented and separate from throughput\",\"prompts\":[";
        bool ok = true;
        for (size_t i = 0; i < results.size(); ++i) {
            const auto & r = results[i];
            if (i) std::cout << ',';
            std::cout << "{\"prompt\":"; json_string(std::cout, r.prompt);
            std::cout << ",\"prompt_tokens\":" << r.prompt_tokens
                      << ",\"kept_logit_mismatches\":" << r.kept_mismatches
                      << ",\"first_kept_mismatch_step\":" << r.first_kept_step << ",\"first_kept_mismatch_token\":" << r.first_kept_token
                      << ",\"dropped_logit_mismatches\":" << r.dropped_mismatches
                      << ",\"first_dropped_mismatch_step\":" << r.first_dropped_step << ",\"first_dropped_mismatch_token\":" << r.first_dropped_token
                      << ",\"first_divergence_step\":" << r.divergence_step << ",\"full_token_at_divergence\":" << r.full_token
                      << ",\"restricted_token_at_divergence\":" << r.restricted_token;
            std::cout << ",\"full_piece_at_divergence\":"; json_string(std::cout, r.full_piece);
            std::cout << ",\"restricted_piece_at_divergence\":"; json_string(std::cout, r.restricted_piece);
            std::cout << ",\"full_generated_text\":"; json_string(std::cout, r.full_text);
            std::cout << ",\"restricted_generated_text\":"; json_string(std::cout, r.restricted_text);
            std::cout << ",\"full_decode_seconds\":" << r.full_seconds << ",\"restricted_decode_seconds\":" << r.restricted_seconds
                      << ",\"full_tokens_per_second\":" << (generated_tokens - 1) / r.full_seconds
                      << ",\"restricted_tokens_per_second\":" << (generated_tokens - 1) / r.restricted_seconds
                      << ",\"full_profile_decode_seconds\":" << r.full_profile_seconds << ",\"restricted_profile_decode_seconds\":" << r.restricted_profile_seconds
                      << ",\"full_profile_head_seconds\":" << r.full_profile.head_seconds << ",\"restricted_profile_head_seconds\":" << r.restricted_profile.head_seconds
                      << ",\"full_profile_head_share\":" << r.full_profile.head_seconds / r.full_profile_seconds
                      << ",\"restricted_profile_head_share\":" << r.restricted_profile.head_seconds / r.restricted_profile_seconds
                      << ",\"full_profile_head_nodes\":" << r.full_profile.head_nodes << ",\"restricted_profile_head_nodes\":" << r.restricted_profile.head_nodes << '}';
            ok = ok && !r.kept_mismatches && !r.dropped_mismatches && r.full_profile.head_nodes && r.restricted_profile.head_nodes;
        }
        std::cout << "],\"correct\":" << (ok ? "true" : "false") << "}\n";
        return ok ? 0 : 1;
    } catch (const std::exception & e) {
        std::cerr << "compare: " << e.what() << '\n';
        return 2;
    }
}
