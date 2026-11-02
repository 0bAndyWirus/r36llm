// Driver-to-action mappings, independent of evdev discovery and repeat timing.
#include "keymap.h"

#include <charconv>
#include <linux/input.h>

namespace r36 {
namespace {
// Source: original r36llm app/src/input.h (vendor 4.4 GO-Super Gamepad and
// rk8xx_pwrkey). Every value is unchanged; unknown codes also pass through.
constexpr std::array<KeyBinding, 18> Vendor44{{
    {544, keys::Up}, {545, keys::Down}, {546, keys::Left}, {547, keys::Right},
    {305, keys::A}, {304, keys::B}, {307, keys::X}, {308, keys::Y},
    {310, keys::L1}, {311, keys::R1}, {312, keys::L2}, {313, keys::R2},
    {704, keys::Select}, {705, keys::Start}, {706, keys::L3}, {707, keys::R3},
    {708, keys::F}, {116, keys::Power},
}};

// Sources (the DTS's linux,code symbols, NOT its sometimes stale hex comments):
// https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/linux/dts/rockchip/rk3326-gameconsole-eeclone.dts
// Its archr-joypad/package.mk pins driver 4a8392c1a15a9cf2cab43750c3246d53d6410301:
// https://github.com/archr-linux/archr-joypad/blob/4a8392c1a15a9cf2cab43750c3246d53d6410301/archr-singleadc-joypad.c
// joypad_gpio_setup()/joypad_gpio_check() report linux,code unchanged as EV_KEY;
// joypad_input_setup() takes the device name from joypad-name (r36s_Gamepad).
constexpr std::array<KeyBinding, 18> Mainline{{
    {BTN_DPAD_UP, keys::Up},       // joypad/sw1
    {BTN_DPAD_DOWN, keys::Down},   // joypad/sw2
    {BTN_DPAD_LEFT, keys::Left},   // joypad/sw3
    {BTN_DPAD_RIGHT, keys::Right}, // joypad/sw4
    {BTN_EAST, keys::A},           // joypad/sw5, physical A
    {BTN_SOUTH, keys::B},          // joypad/sw6, physical B
    {BTN_NORTH, keys::X},          // joypad/sw8, physical X
    {BTN_WEST, keys::Y},           // joypad/sw7, physical Y
    {BTN_TL, keys::L1},            // joypad/sw15
    {BTN_TR, keys::R1},            // joypad/sw16
    {BTN_TL2, keys::L2},           // joypad/sw21
    {BTN_TR2, keys::R2},           // joypad/sw20
    {BTN_SELECT, keys::Select},    // joypad/sw19
    {BTN_START, keys::Start},      // joypad/sw22
    {BTN_THUMBL, keys::L3},        // joypad/sw11
    {BTN_THUMBR, keys::R3},        // joypad/sw12
    {BTN_MODE, keys::F},           // joypad/sw13; F + D-pad adjusts brightness
    {KEY_POWER, keys::Power},     // Separate PMIC input, not a joypad GPIO:
    // https://github.com/torvalds/linux/blob/v6.12/drivers/input/misc/rk805-pwrkey.c
}};
} // namespace

const std::array<KeyBinding, 18> &keymap_bindings(Keymap map) {
    return map == Keymap::Mainline ? Mainline : Vendor44;
}

bool is_gamepad(std::string_view name) {
    return name == "GO-Super Gamepad" || name == "r36s_Gamepad";
}

bool is_power_key(std::string_view name) {
    return name == "rk8xx_pwrkey" || name == "rk805 pwrkey";
}

int kernel_major(std::string_view release) {
    if (release.empty())
        return 0;
    int major = 0;
    const auto end = release.find('.');
    const auto part = release.substr(0, end);
    const auto parsed = std::from_chars(part.data(), part.data() + part.size(), major);
    return parsed.ec == std::errc{} && parsed.ptr == part.data() + part.size() && major > 0
               ? major
               : 0;
}

Keymap select_keymap(std::string_view setting, int major, std::string_view name) {
    if (setting == "vendor44")
        return Keymap::Vendor44;
    if (setting == "mainline")
        return Keymap::Mainline;
    if (name == "GO-Super Gamepad")
        return Keymap::Vendor44;
    if (name == "r36s_Gamepad")
        return Keymap::Mainline;
    return major >= 6 ? Keymap::Mainline : Keymap::Vendor44;
}

int map_key(Keymap map, int code) {
    for (const auto &binding : keymap_bindings(map))
        if (binding.code == code)
            return binding.action;
    return map == Keymap::Vendor44 ? code : -1;
}
} // namespace r36
