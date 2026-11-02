#include "chat_text.h"

#include <algorithm>
#include <fstream>

namespace r36::chat_text {

// Split only at UTF-8 boundaries; the renderer substitutes unsupported codepoints.
std::vector<std::string> wrap(const std::string &text, std::size_t width) {
    std::vector<std::string> result;
    std::string line;
    std::size_t columns = 0, last_space = std::string::npos;
    for (std::size_t i = 0; i < text.size();) {
        unsigned char c = static_cast<unsigned char>(text[i]);
        if (c == '\n') {
            result.push_back(line);
            line.clear();
            columns = 0;
            last_space = std::string::npos;
            ++i;
            continue;
        }
        std::size_t n = c < 0x80 ? 1 : (c < 0xe0 ? 2 : (c < 0xf0 ? 3 : 4));
        n = std::min(n, text.size() - i);
        if (columns == width) {
            if (last_space != std::string::npos) {
                result.push_back(line.substr(0, last_space));
                line.erase(0, last_space + 1);
                columns = 0;
                for (unsigned char b : line)
                    if ((b & 0xc0) != 0x80)
                        ++columns;
            } else {
                result.push_back(line);
                line.clear();
                columns = 0;
            }
            last_space = line.find_last_of(' ');
        }
        if (c == ' ')
            last_space = line.size();
        line.append(text, i, n);
        ++columns;
        i += n;
    }
    if (!line.empty() || result.empty())
        result.push_back(line);
    return result;
}

std::vector<std::string> load_prompts(const std::string &path) {
    std::vector<std::string> presets;
    std::ifstream prompts(path);
    std::string line;
    while (std::getline(prompts, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (!line.empty())
            presets.push_back(line);
    }
    return presets;
}

VisibleWindow visible_window(int line_count, int scroll, int height) {
    const int max_scroll = std::max(0, line_count - height);
    scroll = std::clamp(scroll, 0, max_scroll);
    const int first = std::max(0, line_count - height - scroll);
    return {scroll, first, std::min(line_count, first + height)};
}

} // namespace r36::chat_text
