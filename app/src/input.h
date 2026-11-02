// Discover handheld input devices and synthesize application-action events.
#pragma once

#include "keymap.h"
#include <array>
#include <chrono>
#include <string>
#include <linux/input.h>
#include <vector>

namespace r36 {

struct KeyEvent {
    int code;
    bool pressed;
};

class Input {
  public:
    Input();
    ~Input();
    Input(const Input &) = delete;
    Input &operator=(const Input &) = delete;
    std::vector<KeyEvent> poll(int timeout_ms = 0);
    bool down(int code) const;
    // Select once after loading startup configuration, before polling input.
    void set_keymap(const std::string &setting);

  private:
    struct Device {
        int fd;
        Keymap keymap;
        Keymap detected_keymap;
        std::array<bool, KEY_MAX + 1> down{};
    };

    std::vector<Device> devices_;
    std::array<unsigned, KEY_MAX + 1> counts_{};
    std::array<std::chrono::steady_clock::time_point, KEY_MAX + 1> repeat_{};
};
} // namespace r36
