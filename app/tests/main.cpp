// No test framework or build-time downloads: failures remain active in Release builds.
#include "test.h"

#include <iostream>
#include <string>

int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "Usage: r36llm-tests config|chat_text|keymap|prompt_cache\n";
        return 2;
    }
    const std::string suite = argv[1];
    try {
        if (suite == "config")
            test_config();
        else if (suite == "chat_text")
            test_chat_text();
        else if (suite == "keymap")
            test_keymap();
        else if (suite == "prompt_cache")
            test_prompt_cache();
        else {
            std::cerr << "Unknown test suite: " << suite << '\n';
            return 2;
        }
        std::cout << suite << ": PASS\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << suite << ": " << error.what() << '\n';
        return 1;
    }
}
