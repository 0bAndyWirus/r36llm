// Read handheld telemetry and apply backlight and CPU governor settings.
#include "device.h"
#include "config.h"

#include <algorithm>
#include <arpa/inet.h>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <ifaddrs.h>
#include <limits>

namespace r36 {
namespace fs = std::filesystem;

namespace {

std::string read_text(const fs::path &path) {
    std::ifstream input(path);
    std::string text;
    std::getline(input, text);
    return text;
}

int64_t read_number(const fs::path &path, int64_t missing = -1) {
    std::ifstream input(path);
    int64_t value = 0;
    return input >> value ? value : missing;
}

bool write_number(const fs::path &path, int value) {
    std::ofstream output(path);
    output << value << '\n';
    output.close();
    return !output.fail();
}

std::string interface_address(const std::string &name) {
    ifaddrs *addresses = nullptr;
    if (getifaddrs(&addresses) != 0)
        return {};
    std::string result;
    for (const ifaddrs *address = addresses; address; address = address->ifa_next) {
        if (!address->ifa_addr || address->ifa_addr->sa_family != AF_INET ||
            name != address->ifa_name)
            continue;
        char buffer[INET_ADDRSTRLEN];
        const auto *ipv4 = reinterpret_cast<const sockaddr_in *>(address->ifa_addr);
        if (inet_ntop(AF_INET, &ipv4->sin_addr, buffer, sizeof(buffer))) {
            result = buffer;
            break;
        }
    }
    freeifaddrs(addresses);
    return result;
}

} // namespace

DeviceInfo read_device_info() {
    DeviceInfo info;
    const fs::path battery = "/sys/class/power_supply/battery";
    const int64_t capacity = read_number(battery / "capacity");
    if (capacity >= 0 && capacity <= 100)
        info.battery_percent = static_cast<int>(capacity);
    const std::string status = read_text(battery / "status");
    if (!status.empty())
        info.battery_status = status;
    info.charging = status == "Charging" || status == "Full";
    info.voltage_uv = read_number(battery / "voltage_now");
    info.current_ua = read_number(battery / "current_now", 0);
    info.ac_online = read_number("/sys/class/power_supply/ac/online") == 1;
    info.usb_online = read_number("/sys/class/power_supply/usb/online") == 1;

    std::error_code error;
    std::vector<fs::path> zones;
    for (fs::directory_iterator it("/sys/class/thermal", error), end; !error && it != end;
         it.increment(error)) {
        if (it->path().filename().string().find("thermal_zone") == 0)
            zones.push_back(it->path());
    }
    std::sort(zones.begin(), zones.end());
    for (const auto &zone : zones) {
        const int64_t temperature = read_number(zone / "temp");
        if (temperature < 0 || temperature > std::numeric_limits<int>::max())
            continue;
        std::string type = read_text(zone / "type");
        if (type.empty())
            type = zone.filename().string();
        info.thermal_zones.push_back({type, static_cast<int>(temperature)});
        info.temperature_millic = std::max(info.temperature_millic, static_cast<int>(temperature));
    }
    info.available_kb = memory_kb("MemAvailable");
    const uint64_t swap_total = memory_kb("SwapTotal");
    info.swap_used_kb = swap_total - std::min(swap_total, memory_kb("SwapFree"));
    info.eth0_ip = interface_address("eth0");
    const fs::path cpu = "/sys/devices/system/cpu/cpu0/cpufreq";
    info.cpu_frequency_khz = static_cast<int>(read_number(cpu / "scaling_cur_freq"));
    info.cpu_max_frequency_khz = static_cast<int>(read_number(cpu / "cpuinfo_max_freq"));
    info.cpu_governor = read_text(cpu / "scaling_governor");
    return info;
}

bool apply_brightness(int percent, bool screen_off) {
    const fs::path backlight = "/sys/class/backlight/backlight";
    const int64_t maximum = read_number(backlight / "max_brightness");
    if (maximum <= 0 || maximum > std::numeric_limits<int>::max())
        return false;
    const int value =
        screen_off ? 0 : static_cast<int>((maximum * std::clamp(percent, 10, 100) + 50) / 100);
    return write_number(backlight / "brightness", value);
}

bool apply_cpu_mode(const std::string &mode) {
    const char *governor = nullptr;
    if (mode == "performance")
        governor = "performance";
    else if (mode == "balanced")
        governor = "ondemand";
    else if (mode == "saver")
        governor = "powersave";
    else
        return false;
    std::error_code error;
    bool found = false;
    bool success = true;
    for (fs::directory_iterator it("/sys/devices/system/cpu", error), end; !error && it != end;
         it.increment(error)) {
        const std::string name = it->path().filename().string();
        if (name.size() <= 3 || name.compare(0, 3, "cpu") != 0 ||
            name.find_first_not_of("0123456789", 3) != std::string::npos)
            continue;
        const fs::path path = it->path() / "cpufreq/scaling_governor";
        if (!fs::exists(path, error)) {
            error.clear();
            continue;
        }
        found = true;
        std::ofstream output(path);
        output << governor << '\n';
        output.close();
        success = !output.fail() && success;
    }
    return found && success && !error;
}

} // namespace r36
