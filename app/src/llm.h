// Expose asynchronous model operations and synchronized inference state.
#pragma once
#include "config.h"
#include <atomic>
#include <mutex>
#include <string>
#include <cstdint>
#include <vector>
#include <thread>
struct llama_model;
struct llama_context;
struct llama_sampler;
struct llama_batch_ext;

namespace r36 {
struct LlmState {
    bool busy = false, loading = false, loaded = false;
    float progress = 0;
    double generation_tps = 0, prompt_tps = 0;
    double first_token_seconds = 0;
    double tokenize_seconds = 0, prompt_seconds = 0, first_decode_seconds = 0;
    int generated_tokens = 0;
    std::string text, error, model;
    unsigned completed = 0;
};

// Stable, length-delimited identity and a checked on-disk envelope.
std::string prompt_cache_key(const std::string &path, uint64_t size, int64_t mtime,
                             const std::string &system, int ctx, bool think,
                             const std::string &engine);
std::string prompt_cache_filename(const std::string &key);
std::string prompt_cache_header(const std::string &key, uint64_t tokens,
                                const std::vector<uint8_t> &payload);
bool validate_prompt_cache(const std::string &header, const std::string &key, uint64_t tokens,
                           const std::vector<uint8_t> &payload);

class Llm {
  public:
    explicit Llm(bool prompt_cache = true, uint32_t seed = UINT32_MAX);
    ~Llm();
    bool load(const std::string &path, const Config &config);
    bool generate(const std::string &user, const Config &config);
    void stop();
    void clear();
    void unload();
    LlmState state() const;

  private:
    mutable std::mutex mutex_;
    LlmState state_;
    std::thread worker_;
    std::atomic<bool> stop_{false};
    llama_model *model_ = nullptr;
    llama_context *context_ = nullptr;
    llama_sampler *sampler_ = nullptr;
    llama_batch_ext *batch_ = nullptr;
    std::string history_;
    size_t evaluated_ = 0;
    bool think_ = false;
    bool cache_enabled_ = true;
    uint32_t seed_ = UINT32_MAX;
    std::string system_history_, cache_key_;
    std::vector<uint8_t> system_snapshot_;
    size_t system_tokens_ = 0;
    void prepare_system(const Config &config);
    bool restore_system();
    void evaluate(const int32_t *tokens, int count);
    std::vector<int32_t> tokenize(const std::string &text, bool first) const;
    bool begin();
    void release();
    void finish(const std::string &error = {});
    void run_generation(const std::string &user, const Config &config);
};

std::string strip_thinking(const std::string &raw);
} // namespace r36
