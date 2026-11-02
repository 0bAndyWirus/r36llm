#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace r36::chat_text {

std::vector<std::string> wrap(const std::string &text, std::size_t width = 53);
std::vector<std::string> load_prompts(const std::string &path);

struct VisibleWindow {
    int scroll;
    int first;
    int end;
};

VisibleWindow visible_window(int line_count, int scroll, int height = 16);

} // namespace r36::chat_text
