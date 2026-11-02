#include "test.h"
#include "chat_text.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

void test_chat_text() {
    using r36::chat_text::visible_window;
    using r36::chat_text::wrap;
    using Strings = std::vector<std::string>;

    CHECK(wrap("") == Strings({""}));
    CHECK(wrap("hello world", 8) == Strings({"hello", "world"}));
    CHECK(wrap("abc\ndef\n", 5) == Strings({"abc", "def"}));
    CHECK(wrap("\n\n", 5) == Strings({"", ""}));
    CHECK(wrap("abcdefgh", 3) == Strings({"abc", "def", "gh"}));
    CHECK(wrap(u8"é中🙂x", 2) == Strings({u8"é中", u8"🙂x"}));
    CHECK(wrap(u8"é 中 x", 3) == Strings({u8"é", u8"中 x"}));

    namespace fs = std::filesystem;
    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const fs::path dir = fs::temp_directory_path() / ("r36llm-chat-text-" + std::to_string(suffix));
    fs::create_directory(dir);
    const fs::path prompts = dir / "prompts.txt";
    CHECK(r36::chat_text::load_prompts(prompts.string()).empty());
    {
        std::ofstream out(prompts, std::ios::binary);
        out << u8"first\r\n\r\n  \r\né中🙂\nlast\r";
    }
    CHECK(r36::chat_text::load_prompts(prompts.string()) ==
          Strings({"first", "  ", u8"é中🙂", "last"}));
    fs::remove_all(dir);

    auto window = visible_window(5, 50);
    CHECK(window.scroll == 0 && window.first == 0 && window.end == 5);
    window = visible_window(20, -1);
    CHECK(window.scroll == 0 && window.first == 4 && window.end == 20);
    window = visible_window(20, 100);
    CHECK(window.scroll == 4 && window.first == 0 && window.end == 16);
    window = visible_window(20, 2);
    CHECK(window.scroll == 2 && window.first == 2 && window.end == 18);
    // New streamed lines keep the same distance from the bottom, including when scrolled up.
    window = visible_window(23, window.scroll);
    CHECK(window.scroll == 2 && window.first == 5 && window.end == 21);
    window = visible_window(23, 0);
    CHECK(window.scroll == 0 && window.first == 7 && window.end == 23);
}
