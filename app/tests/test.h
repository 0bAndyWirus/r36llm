#pragma once

#include <stdexcept>
#include <string>

inline void check(bool condition, const char *expression, const char *file, int line) {
    if (!condition)
        throw std::runtime_error(std::string(file) + ":" + std::to_string(line) +
                                 ": check failed: " + expression);
}

#define CHECK(expr) check(static_cast<bool>(expr), #expr, __FILE__, __LINE__)

void test_config();
void test_chat_text();
void test_keymap();
