// Discover gamepad input devices and synthesize directional key repeats.
#include "input.h"

#include <algorithm>
#include <climits>
#include <cstdint>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <string>
#include <sys/ioctl.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <utility>

namespace r36 {
namespace {
using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;

bool repeats(int code) {
    return (code >= keys::Up && code <= keys::Right) || code == keys::L1 || code == keys::R1;
}

bool has_keys(int fd) {
    constexpr unsigned bits = sizeof(unsigned long) * CHAR_BIT;
    unsigned long flags[(EV_MAX + bits) / bits]{};
    return ioctl(fd, EVIOCGBIT(0, sizeof(flags)), flags) >= 0 &&
           (flags[EV_KEY / bits] & (1UL << (EV_KEY % bits)));
}
} // namespace

Input::Input() {
    utsname kernel{};
    const int major = uname(&kernel) == 0 ? kernel_major(kernel.release) : 0;
    DIR *dir = opendir("/dev/input");
    if (!dir)
        return;
    std::vector<Device> fallback;
    std::vector<Device> preferred;
    std::vector<Device> power_keys;
    while (auto *entry = readdir(dir)) {
        if (std::strncmp(entry->d_name, "event", 5) != 0)
            continue;
        std::string path = std::string("/dev/input/") + entry->d_name;
        int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        if (!has_keys(fd)) {
            close(fd);
            continue;
        }
        char name[256]{};
        const bool named = ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0;
        const Keymap map = select_keymap("auto", major, named ? name : "");
        if (named && is_gamepad(name))
            preferred.push_back(Device{fd, map, map, {}});
        else if (named && is_power_key(name))
            power_keys.push_back(Device{fd, map, map, {}});
        else
            fallback.push_back(Device{fd, map, map, {}});
    }
    closedir(dir);
    if (!preferred.empty()) {
        for (auto &device : fallback)
            close(device.fd);
        devices_ = std::move(preferred);
    } else {
        devices_ = std::move(fallback);
    }
    for (auto &device : power_keys)
        devices_.push_back(std::move(device));
}

void Input::set_keymap(const std::string &setting) {
    for (auto &device : devices_)
        device.keymap = setting == "vendor44"   ? Keymap::Vendor44
                        : setting == "mainline" ? Keymap::Mainline
                                               : device.detected_keymap;
}

Input::~Input() {
    for (auto &device : devices_)
        if (device.fd >= 0)
            close(device.fd);
}

bool Input::down(int code) const {
    return code >= 0 && code <= KEY_MAX && counts_[code] != 0;
}

std::vector<KeyEvent> Input::poll(int timeout_ms) {
    std::vector<KeyEvent> events;
    std::vector<pollfd> descriptors;
    descriptors.reserve(devices_.size());
    for (const auto &device : devices_)
        descriptors.push_back({device.fd, POLLIN, 0});
    int wait = std::max(0, timeout_ms);
    auto now = Clock::now();
    for (int code : {keys::Up, keys::Down, keys::Left, keys::Right, keys::L1, keys::R1}) {
        if (!counts_[code])
            continue;
        auto remaining = repeat_[code] - now;
        int ms = remaining <= Clock::duration::zero()
                     ? 0
                     : static_cast<int>(std::min<int64_t>(
                           INT_MAX, std::chrono::duration_cast<std::chrono::milliseconds>(
                                        remaining + 1ms - Clock::duration(1))
                                        .count()));
        wait = std::min(wait, ms);
    }
    int result = ::poll(descriptors.data(), descriptors.size(), wait);
    if (result > 0) {
        for (std::size_t i = 0; i < devices_.size(); ++i) {
            auto &device = devices_[i];
            if (descriptors[i].revents & POLLIN) {
                input_event buffer[32];
                ssize_t size;
                while ((size = read(device.fd, buffer, sizeof(buffer))) > 0) {
                    for (std::size_t j = 0;
                         j < static_cast<std::size_t>(size) / sizeof(input_event); ++j) {
                        const auto &event = buffer[j];
                        if (event.type != EV_KEY || event.code > KEY_MAX ||
                            (event.value != 0 && event.value != 1))
                            continue;
                        const int code = map_key(device.keymap, event.code);
                        if (code < 0)
                            continue;
                        bool pressed = event.value == 1;
                        if (device.down[code] == pressed)
                            continue;
                        device.down[code] = pressed;
                        if (pressed) {
                            if (counts_[code]++ == 0) {
                                events.push_back({code, true});
                                if (repeats(code))
                                    repeat_[code] = Clock::now() + 400ms;
                            }
                        } else if (--counts_[code] == 0) {
                            events.push_back({code, false});
                        }
                    }
                }
            }
            if (descriptors[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                for (int code = 0; code <= KEY_MAX; ++code) {
                    if (device.down[code]) {
                        device.down[code] = false;
                        if (--counts_[code] == 0)
                            events.push_back({code, false});
                    }
                }
                close(device.fd);
                device.fd = -1;
            }
        }
    }
    now = Clock::now();
    for (int code : {keys::Up, keys::Down, keys::Left, keys::Right, keys::L1, keys::R1}) {
        if (counts_[code] && now >= repeat_[code]) {
            events.push_back({code, true});
            repeat_[code] += ((now - repeat_[code]) / 80ms + 1) * 80ms;
        }
    }
    return events;
}
} // namespace r36
