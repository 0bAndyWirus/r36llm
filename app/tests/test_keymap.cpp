#include "test.h"
#include "keymap.h"

#include <array>
#include <linux/input.h>

void test_keymap() {
    using namespace r36;
    // Literal original app/src/input.h values: a separate regression oracle.
    const std::array<KeyBinding, 18> vendor{{
        {544, keys::Up}, {545, keys::Down}, {546, keys::Left}, {547, keys::Right},
        {305, keys::A}, {304, keys::B}, {307, keys::X}, {308, keys::Y},
        {310, keys::L1}, {311, keys::R1}, {312, keys::L2}, {313, keys::R2},
        {704, keys::Select}, {705, keys::Start}, {706, keys::L3}, {707, keys::R3},
        {708, keys::F}, {116, keys::Power},
    }};
    for (const auto &binding : vendor) {
        CHECK(binding.action == binding.code);
        CHECK(map_key(Keymap::Vendor44, binding.code) == binding.action);
    }
    // Unknown events also retain their original value, including wake-up events.
    for (int code = 0; code <= KEY_MAX; ++code)
        CHECK(map_key(Keymap::Vendor44, code) == code);

    // Actual Linux UAPI numbers, rather than the DTS's stale hex annotations.
    const std::array<int, 18> mainline{{
        544, 545, 546, 547, 305, 304, 307, 308, 310, 311, 312, 313,
        314, 315, 317, 318, 316, 116,
    }};
    const auto &table = keymap_bindings(Keymap::Mainline);
    CHECK(table.size() == vendor.size());
    for (std::size_t i = 0; i < table.size(); ++i) {
        CHECK(table[i].code == mainline[i]);
        CHECK(table[i].action == vendor[i].action);
        CHECK(map_key(Keymap::Mainline, mainline[i]) == vendor[i].action);
        for (std::size_t j = i + 1; j < table.size(); ++j) {
            CHECK(table[i].code != table[j].code);
            CHECK(table[i].action != table[j].action);
        }
    }
    // Both keys in the brightness chord, new-chat chord and power remain distinct.
    CHECK(map_key(Keymap::Mainline, BTN_MODE) == keys::F);
    CHECK(map_key(Keymap::Mainline, BTN_DPAD_UP) == keys::Up);
    CHECK(map_key(Keymap::Mainline, BTN_DPAD_DOWN) == keys::Down);
    CHECK(map_key(Keymap::Mainline, BTN_SELECT) == keys::Select);
    CHECK(map_key(Keymap::Mainline, BTN_START) == keys::Start);
    CHECK(map_key(Keymap::Mainline, KEY_POWER) == keys::Power);
    CHECK(map_key(Keymap::Mainline, KEY_RESERVED) == -1);
    CHECK(map_key(Keymap::Mainline, 708) == -1);

    CHECK(kernel_major("4.4.189") == 4);
    CHECK(kernel_major("6.12.114-ArchR") == 6);
    CHECK(kernel_major("7.0-rc1") == 7);
    CHECK(kernel_major("6") == 6);
    CHECK(kernel_major("") == 0);
    CHECK(kernel_major("invalid") == 0);
    CHECK(kernel_major("6x.12") == 0);
    CHECK(kernel_major("-1.2") == 0);
    CHECK(kernel_major("999999999999999.0") == 0);
    CHECK(select_keymap("auto", 4, "") == Keymap::Vendor44);
    CHECK(select_keymap("auto", 6, "") == Keymap::Mainline);
    CHECK(select_keymap("auto", 0, "") == Keymap::Vendor44);
    CHECK(select_keymap("auto", 6, "GO-Super Gamepad") == Keymap::Vendor44);
    CHECK(select_keymap("auto", 4, "r36s_Gamepad") == Keymap::Mainline);
    CHECK(select_keymap("vendor44", 6, "r36s_Gamepad") == Keymap::Vendor44);
    CHECK(select_keymap("mainline", 4, "GO-Super Gamepad") == Keymap::Mainline);
    CHECK(is_gamepad("GO-Super Gamepad"));
    CHECK(is_gamepad("r36s_Gamepad"));
    CHECK(!is_gamepad("keyboard"));
    CHECK(is_power_key("rk8xx_pwrkey"));
    CHECK(is_power_key("rk805 pwrkey"));
    CHECK(!is_power_key("r36s_Gamepad"));
}
