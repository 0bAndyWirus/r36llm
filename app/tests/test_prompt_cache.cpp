#include "llm.h"
#include "test.h"
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <thread>

namespace {

using namespace r36;

LlmState wait_for_completion(Llm &llm, bool *observed_stream = nullptr) {
    LlmState state;
    do {
        state = llm.state();
        if (observed_stream && state.busy && state.generated_tokens > 0 && !state.text.empty())
            *observed_stream = true;
        if (state.busy)
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
    } while (state.busy);
    CHECK(state.error.empty());
    return state;
}

LlmState generate(Llm &llm, const std::string &prompt, const Config &config,
                  bool &observed_stream) {
    CHECK(llm.generate(prompt, config));
    auto state = wait_for_completion(llm, &observed_stream);
    CHECK(std::isfinite(state.tokenize_seconds) && state.tokenize_seconds >= 0);
    CHECK(std::isfinite(state.prompt_seconds) && state.prompt_seconds >= 0);
    CHECK(std::isfinite(state.first_decode_seconds) && state.first_decode_seconds >= 0);
    CHECK(state.generated_tokens > 0);
    CHECK(state.first_token_seconds > 0);
    return state;
}

void check_same_reply(const LlmState &a, const LlmState &b) {
    CHECK(a.text == b.text);
    CHECK(a.generated_tokens == b.generated_tokens);
}

void test_real_model(const char *model) {
    Config config;
    config.threads = 4;
    config.ctx = 2048;
    config.max_tokens = 8;
    Llm cached(true, 42);
    Llm uncached(false, 42);
    CHECK(cached.load(model, config));
    CHECK(wait_for_completion(cached).loaded);
    CHECK(uncached.load(model, config));
    CHECK(wait_for_completion(uncached).loaded);

    bool observed_stream = false;
    for (float temperature : {0.6f, 0.0f}) {
        config.temp = temperature;
        for (const char *prompt : {"Count from 1 to 100, separated by spaces.",
                                   "Name several colors, separated by commas.",
                                   "\nList some animals.",
                                   "  List some fruits.",
                                   "<|im_end|>List some cities."}) {
            // Contaminate both contexts before starting a new chat, exercising
            // the snapshot restore and the uncached full reset independently.
            generate(cached, "Write a short story about a dragon.", config, observed_stream);
            generate(uncached, "Give a list of musical instruments.", config, observed_stream);
            cached.clear();
            uncached.clear();
            const auto first = generate(cached, prompt, config, observed_stream);
            check_same_reply(first, generate(uncached, prompt, config, observed_stream));

            const char *next = "Continue with more examples.";
            const auto continued = generate(cached, next, config, observed_stream);
            check_same_reply(continued, generate(uncached, next, config, observed_stream));

            // Replay the equivalent conversation from a fresh reset, then
            // compare the next turn rather than only the first response.
            uncached.clear();
            check_same_reply(first, generate(uncached, prompt, config, observed_stream));
            check_same_reply(continued, generate(uncached, next, config, observed_stream));
        }
    }
    CHECK(observed_stream);
}

} // namespace

void test_prompt_cache() {
    using namespace r36;
    const auto key = prompt_cache_key("/models/a.gguf", 4096, 100, "Be brief.", 2048, false, "engine-1");
    CHECK(key == prompt_cache_key("/models/a.gguf", 4096, 100, "Be brief.", 2048, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/b.gguf", 4096, 100, "Be brief.", 2048, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4097, 100, "Be brief.", 2048, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4096, 101, "Be brief.", 2048, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4096, 100, "Be helpful.", 2048, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4096, 100, "Be brief.", 1024, false, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4096, 100, "Be brief.", 2048, true, "engine-1"));
    CHECK(key != prompt_cache_key("/models/a.gguf", 4096, 100, "Be brief.", 2048, false, "engine-2"));
    CHECK(prompt_cache_key("a1", 2, 3, "4", 128, false, "v") !=
          prompt_cache_key("a", 12, 3, "4", 128, false, "v"));
    CHECK(prompt_cache_filename(key) == "/data/r36llm/cache/" + key + ".kv");
    CHECK(prompt_cache_filename("../bad").empty());
    CHECK(prompt_cache_filename("0123456789abcdeg").empty());
    CHECK(prompt_cache_filename("0123456789ABCDEF").empty());
    CHECK(prompt_cache_filename("").empty());
    std::vector<uint8_t> data{0, 1, 2, 0, 255};
    const auto header = prompt_cache_header(key, 32, data);
    CHECK(validate_prompt_cache(header, key, 32, data));
    CHECK(!validate_prompt_cache(header, key, 33, data));
    CHECK(!validate_prompt_cache(header, "0123456789abcdef", 32, data));
    CHECK(!validate_prompt_cache(header.substr(1), key, 32, data));
    CHECK(!validate_prompt_cache(header + "garbage", key, 32, data));
    CHECK(!validate_prompt_cache(header, key, 32, {}));
    auto damaged_header = header;
    damaged_header[0] ^= 1;
    CHECK(!validate_prompt_cache(damaged_header, key, 32, data));
    data[2] ^= 1;
    CHECK(!validate_prompt_cache(header, key, 32, data));
    data.push_back(0);
    CHECK(!validate_prompt_cache(header, key, 32, data));
    const char *model = std::getenv("R36LLM_TEST_MODEL");
    if (model && *model)
        test_real_model(model);
}
