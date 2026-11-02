// Translate driver keycodes into stable application actions.
#pragma once

#include <array>
#include <string_view>

namespace r36 {
namespace keys {
// Stable action IDs retain the vendor44 values, not the selected driver's codes.
inline constexpr int Up = 544, Down = 545, Left = 546, Right = 547;
inline constexpr int A = 305, B = 304, X = 307, Y = 308;
inline constexpr int L1 = 310, R1 = 311, L2 = 312, R2 = 313;
inline constexpr int Select = 704, Start = 705, L3 = 706, R3 = 707, F = 708;
inline constexpr int Power = 116;
} // namespace keys

enum class Keymap { Vendor44, Mainline };
struct KeyBinding {
    int code;
    int action;
};

const std::array<KeyBinding, 18> &keymap_bindings(Keymap map);
// Explicit configuration wins; known gamepad names win over the kernel fallback.
Keymap select_keymap(std::string_view setting, int kernel_major, std::string_view device_name);
int kernel_major(std::string_view release);
bool is_gamepad(std::string_view name);
bool is_power_key(std::string_view name);
// Vendor44 passes every code through, preserving the original input interface.
// Mainline ignores unmapped codes (-1).
int map_key(Keymap map, int code);
} // namespace r36
