// Define handheld keycodes and the nonblocking input interface.
#pragma once

#include <array>
#include <chrono>
#include <linux/input.h>
#include <vector>

namespace r36 {
namespace keys {
inline constexpr int Up = 544, Down = 545, Left = 546, Right = 547;
inline constexpr int A = 305, B = 304, X = 307, Y = 308;
inline constexpr int L1 = 310, R1 = 311, L2 = 312, R2 = 313;
inline constexpr int Select = 704, Start = 705, L3 = 706, R3 = 707, F = 708;
inline constexpr int Power = 116;
} // namespace keys

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

  private:
    struct Device {
        int fd;
        std::array<bool, KEY_MAX + 1> down{};
    };

    std::vector<Device> devices_;
    std::array<unsigned, KEY_MAX + 1> counts_{};
    std::array<std::chrono::steady_clock::time_point, KEY_MAX + 1> repeat_{};
};
} // namespace r36
