// Parse command-line options and launch device, headless, or render-test mode.
#include "config.h"
#include "llm.h"
#include "ui.h"
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
volatile std::sig_atomic_t interrupted = 0;

void interrupt(int) {
    interrupted = 1;
}

int number(const std::string &text, int low, int high) {
    size_t used = 0;
    int value = std::stoi(text, &used);
    if (used != text.size() || value < low || value > high)
        throw std::runtime_error("Argument out of range: " + text);
    return value;
}
} // namespace

int main(int argc, char **argv) {
    std::fprintf(stderr, "r36llm start %s %s\n", __DATE__, __TIME__);
    try {
        r36::Config config;
        config.load();
        bool headless = false;
        std::string model, prompt, render;
        bool prompt_set = false;
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            auto value = [&]() {
                if (i + 1 >= argc)
                    throw std::runtime_error("Missing value for " + arg);
                return std::string(argv[++i]);
            };
            if (arg == "--headless")
                headless = true;
            else if (arg == "--model")
                model = value();
            else if (arg == "--prompt") {
                prompt = value();
                prompt_set = true;
            } else if (arg == "--threads")
                config.threads = number(value(), 1, 256);
            else if (arg == "--ctx")
                config.ctx = number(value(), 128, 1048576);
            else if (arg == "--max-tokens")
                config.max_tokens = number(value(), 1, 1048576);
            else if (arg == "--render-test")
                render = value();
            else if (arg == "--help") {
                std::cout << "r36llm\nr36llm --headless --model <gguf> --prompt <text> [--threads "
                             "N] [--ctx N] [--max-tokens N]\nr36llm --render-test <dir>\n";
                return 0;
            } else
                throw std::runtime_error("Unknown argument: " + arg);
        }
        if (!render.empty())
            return r36::render_tests(render);
        if (!headless) {
            if (!model.empty() || prompt_set)
                throw std::runtime_error("--model and --prompt require --headless");
            return r36::run_device();
        }
        if (model.empty() || !prompt_set)
            throw std::runtime_error("Headless mode requires --model and --prompt");
        std::signal(SIGINT, interrupt);
        std::signal(SIGTERM, interrupt);
        r36::Llm engine;
        engine.load(model, config);
        while (engine.state().busy) {
            if (interrupted)
                engine.stop();
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
        auto state = engine.state();
        if (!state.loaded)
            throw std::runtime_error(state.error);
        engine.generate(prompt, config);
        size_t printed = 0;
        do {
            if (interrupted)
                engine.stop();
            state = engine.state();
            if (state.text.size() > printed) {
                std::cout << state.text.substr(printed) << std::flush;
                printed = state.text.size();
            }
            if (state.busy)
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
        } while (state.busy);
        std::printf("\n[tok/s: %.2f prompt: %.2f]\n", state.generation_tps, state.prompt_tps);
        if (!state.error.empty())
            throw std::runtime_error(state.error);
        return interrupted ? 130 : 0;
    } catch (const std::exception &error) {
        std::cerr << "r36llm: " << error.what() << '\n';
        return 1;
    }
}
