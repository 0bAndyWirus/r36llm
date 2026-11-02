// Define persistent settings and device-status queries.
#pragma once

#include <cstdint>
#include <string>

namespace r36 {

struct Config {
    std::string model = "Ternary-Bonsai-2-2B-PTQ1_0.gguf";
    std::string system =
        "You are a tiny AI living inside an R36S handheld game console. Answer briefly.";
    std::string usb_gadget_fn = "ncm";
    std::string link = "ethernet";
    std::string cpu_mode = "performance";
    int brightness = 80;
    int screen_timeout = 2;
    int threads = 4;
    int ctx = 2048;
    int max_tokens = 256;
    int top_k = 20;
    int swap_p2 = 1;
    float temp = 0.5f;
    float top_p = 0.9f;

    void load(const std::string &path = "/data/r36llm/config.ini");
    bool save(const std::string &path = "/data/r36llm/config.ini") const;
};

uint64_t memory_kb(const std::string &field);
bool data_mounted();
std::string link_status();

} // namespace r36
