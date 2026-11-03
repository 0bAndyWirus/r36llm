// Read and save application settings and query device status.
#include "config.h"

#include <arpa/inet.h>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <ifaddrs.h>
#include <iomanip>
#include <limits>
#include <sstream>
#include <sys/stat.h>
#include <unordered_set>
#include <vector>

namespace r36 {
namespace {

std::string trim(const std::string &text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return {};
    return text.substr(first, text.find_last_not_of(" \t\r\n") - first + 1);
}

bool split_line(const std::string &line, std::string &key, std::string &value) {
    const auto comment = line.find('#');
    const auto end = comment == std::string::npos ? line.size() : comment;
    const auto equals = line.find('=');
    if (equals == std::string::npos || equals >= end)
        return false;
    key = trim(line.substr(0, equals));
    value = trim(line.substr(equals + 1, end - equals - 1));
    return !key.empty();
}

bool parse_int(const std::string &value, int min, int max, int &result) {
    int parsed = 0;
    const auto parsed_end = std::from_chars(value.data(), value.data() + value.size(), parsed);
    if (parsed_end.ec != std::errc{} || parsed_end.ptr != value.data() + value.size() ||
        parsed < min || parsed > max)
        return false;
    result = parsed;
    return true;
}

bool parse_float(const std::string &value, float min, float max, float &result) {
    if (value.empty())
        return false;
    char *end = nullptr;
    errno = 0;
    const float parsed = std::strtof(value.c_str(), &end);
    if (errno == ERANGE || end != value.c_str() + value.size() || !std::isfinite(parsed) ||
        parsed < min || parsed > max)
        return false;
    result = parsed;
    return true;
}

bool known_key(const std::string &key) {
    static const std::unordered_set<std::string> keys = {
        "model",      "system",     "usb_gadget_fn",  "threads", "ctx",
        "max_tokens", "top_k",      "swap_p2",        "link",    "temp",
        "top_p",      "brightness", "screen_timeout", "cpu_mode", "keymap", "output_keep"};
    return keys.find(key) != keys.end();
}

void apply(Config &config, const std::string &key, const std::string &value) {
    if (key == "model") {
        if (!value.empty())
            config.model = value;
    } else if (key == "output_keep")
        config.output_keep = value;
    else if (key == "system")
        config.system = value;
    else if (key == "usb_gadget_fn") {
        if (!value.empty())
            config.usb_gadget_fn = value;
    } else if (key == "threads")
        parse_int(value, 1, 256, config.threads);
    else if (key == "ctx")
        parse_int(value, 1, 1048576, config.ctx);
    else if (key == "max_tokens")
        parse_int(value, 1, 1048576, config.max_tokens);
    else if (key == "top_k")
        parse_int(value, 0, 1048576, config.top_k);
    else if (key == "swap_p2")
        parse_int(value, 0, 1, config.swap_p2);
    else if (key == "link") {
        if (value == "ethernet" || value == "gadget" || value == "off")
            config.link = value;
    } else if (key == "brightness") {
        int brightness = 0;
        if (parse_int(value, 10, 100, brightness) && brightness % 10 == 0)
            config.brightness = brightness;
    } else if (key == "screen_timeout") {
        int timeout = 0;
        if (parse_int(value, 0, 10, timeout) &&
            (timeout == 0 || timeout == 1 || timeout == 2 || timeout == 5 || timeout == 10))
            config.screen_timeout = timeout;
    } else if (key == "cpu_mode") {
        if (value == "performance" || value == "balanced" || value == "saver")
            config.cpu_mode = value;
    } else if (key == "keymap") {
        if (value == "auto" || value == "vendor44" || value == "mainline")
            config.keymap = value;
    } else if (key == "temp")
        parse_float(value, 0.0f, 100.0f, config.temp);
    else if (key == "top_p")
        parse_float(value, 0.0f, 1.0f, config.top_p);
}

} // namespace

void Config::load(const std::string &path) {
    *this = Config{};
    const uint64_t total = memory_kb("MemTotal");
    if (total != 0 && total < 600000)
        ctx = 1024;

    std::ifstream input(path);
    std::string line, key, value;
    while (std::getline(input, line)) {
        if (split_line(line, key, value))
            apply(*this, key, value);
    }
}

std::string Config::output_keep_for_model(const std::string &path) const {
    const auto slash = path.find_last_of("/\\");
    const auto start = slash == std::string::npos ? 0 : slash + 1;
    return path.compare(start, std::string::npos, "Ternary-Bonsai-2-2B-PTQ1_0.gguf") == 0
               ? output_keep
               : std::string{};
}

bool Config::save(const std::string &path) const {
    std::vector<std::string> preserved;
    {
        std::ifstream input(path);
        std::string line, key, value;
        while (std::getline(input, line)) {
            if (!split_line(line, key, value) || !known_key(key))
                preserved.push_back(line);
        }
        if (input.bad())
            return false;
    }

    std::ofstream output(path, std::ios::trunc);
    if (!output)
        return false;
    for (const auto &line : preserved)
        output << line << '\n';
    output << "model=" << model << '\n'
           << "output_keep=" << output_keep << '\n'
           << "threads=" << threads << '\n'
           << "ctx=" << ctx << '\n'
           << "max_tokens=" << max_tokens << '\n'
           << std::setprecision(std::numeric_limits<float>::max_digits10) << "temp=" << temp << '\n'
           << "top_p=" << top_p << '\n'
           << "top_k=" << top_k << '\n'
           << "system=" << system << '\n'
           << "swap_p2=" << swap_p2 << '\n'
           << "link=" << link << '\n'
           << "usb_gadget_fn=" << usb_gadget_fn << '\n'
           << "brightness=" << brightness << '\n'
           << "screen_timeout=" << screen_timeout << '\n'
           << "cpu_mode=" << cpu_mode << '\n'
           << "keymap=" << keymap << '\n';
    output.close();
    return !output.fail();
}

uint64_t memory_kb(const std::string &field) {
    std::ifstream input("/proc/meminfo");
    std::string line;
    const std::string prefix = field + ':';
    while (std::getline(input, line)) {
        if (line.compare(0, prefix.size(), prefix) == 0) {
            std::istringstream values(line.substr(prefix.size()));
            uint64_t amount = 0;
            if (values >> amount)
                return amount;
            break;
        }
    }
    return 0;
}

bool data_mounted() {
    std::ifstream input("/proc/mounts");
    std::string line;
    while (std::getline(input, line)) {
        std::istringstream fields(line);
        std::string device, mountpoint;
        if (fields >> device >> mountpoint && mountpoint == "/data")
            return true;
    }
    return false;
}

std::string link_status() {
    std::string interface;
    ifaddrs *addresses = nullptr;
    DIR *network = opendir("/sys/class/net");
    if (network && getifaddrs(&addresses) == 0) {
        in_addr expected{};
        inet_pton(AF_INET, "10.36.0.1", &expected);
        while (const dirent *entry = readdir(network)) {
            if (entry->d_name[0] == '.' || std::strcmp(entry->d_name, "lo") == 0)
                continue;
            const std::string path = std::string("/sys/class/net/") + entry->d_name;

            struct stat device {};

            if (lstat((path + "/device").c_str(), &device) != 0 || !S_ISLNK(device.st_mode))
                continue;
            std::ifstream carrier(path + "/carrier");
            int connected = 0;
            if (!(carrier >> connected) || connected != 1)
                continue;
            for (const ifaddrs *address = addresses; address; address = address->ifa_next) {
                if (!address->ifa_addr || address->ifa_addr->sa_family != AF_INET ||
                    std::strcmp(address->ifa_name, entry->d_name) != 0)
                    continue;
                const auto *ipv4 = reinterpret_cast<const sockaddr_in *>(address->ifa_addr);
                if (ipv4->sin_addr.s_addr == expected.s_addr) {
                    interface = entry->d_name;
                    break;
                }
            }
            if (!interface.empty())
                break;
        }
        freeifaddrs(addresses);
    }
    if (network)
        closedir(network);
    if (!interface.empty())
        return "Link: up (" + interface + ") - ssh root@10.36.0.1";

    DIR *directory = opendir("/sys/class/udc");
    if (!directory)
        return "Link: down";
    bool configured = false;
    while (const dirent *entry = readdir(directory)) {
        if (entry->d_name[0] == '.')
            continue;
        std::ifstream state(std::string("/sys/class/udc/") + entry->d_name + "/state");
        std::string value;
        if (std::getline(state, value) && trim(value) == "configured") {
            configured = true;
            break;
        }
    }
    closedir(directory);
    return configured ? "Link: up (usb gadget) - ssh root@10.36.0.1" : "Link: down";
}

} // namespace r36
