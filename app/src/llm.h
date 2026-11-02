// Expose asynchronous model operations and synchronized inference state.
#pragma once
#include "config.h"
#include <atomic>
#include <mutex>
#include <string>
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
    std::string text, error, model;
    unsigned completed = 0;
};

class Llm {
  public:
    Llm();
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
    bool begin();
    void release();
    void finish(const std::string &error = {});
    void run_generation(const std::string &user, const Config &config);
};

std::string strip_thinking(const std::string &raw);
} // namespace r36
