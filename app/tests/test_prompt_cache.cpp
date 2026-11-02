#include "llm.h"
#include "test.h"

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
}
