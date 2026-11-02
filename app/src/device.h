// Expose handheld sensors, backlight control, and CPU power modes.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace r36 {

struct ThermalZone {
    std::string type;
    int temperature_millic = -1;
};

struct DeviceInfo {
    int battery_percent = -1;
    std::string battery_status = "Unknown";
    bool charging = false;
    bool ac_online = false;
    bool usb_online = false;
    int64_t voltage_uv = -1;
    int64_t current_ua = 0;
    std::vector<ThermalZone> thermal_zones;
    int temperature_millic = -1;
    uint64_t available_kb = 0;
    uint64_t swap_used_kb = 0;
    std::string eth0_ip;
    int cpu_frequency_khz = -1;
    int cpu_max_frequency_khz = -1;
    std::string cpu_governor;
};

DeviceInfo read_device_info();
bool apply_brightness(int percent, bool screen_off = false);
bool apply_cpu_mode(const std::string &mode);

} // namespace r36
