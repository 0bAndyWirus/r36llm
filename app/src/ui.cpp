// Implement the gamepad-driven screens and deterministic render fixtures.
#include "ui.h"
#include "chat_text.h"
#include "config.h"
#include "device.h"
#include "fb.h"
#include "input.h"
#include "llm.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <unistd.h>
#include <vector>

namespace r36 {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;

namespace {
using chat_text::wrap;
constexpr uint32_t White = 0xffffff, Cyan = 0x50e5f0, Red = 0xff6868, Yellow = 0xffda65,
                   Gray = 0x25282e;
const std::string Root = "/data/r36llm/";

struct Line {
    std::string text;
    uint32_t color = White;
};

struct Model {
    std::string name;
    uint64_t bytes;
};
enum class Screen { Home, Chat, Keyboard, Presets, Models, Benchmark, Settings, About, Power };

std::string timestamp(const char *format = "%Y%m%d-%H%M%S") {
    std::time_t now = std::time(nullptr);
    std::tm tm{};
    localtime_r(&now, &tm);
    char out[64];
    std::strftime(out, sizeof(out), format, &tm);
    return out;
}

std::string decimal(double value, int precision = 1) {
    std::ostringstream s;
    s << std::fixed << std::setprecision(precision) << value;
    return s.str();
}

std::string shell_quote(const std::string &s) {
    std::string out = "'";
    for (char c : s)
        out += c == '\'' ? "'\\''" : std::string(1, c);
    return out + "'";
}


void add_wrapped(std::vector<Line> &out, const std::string &text, uint32_t color = White) {
    for (auto &line : wrap(text))
        out.push_back({std::move(line), color});
}

std::string temperature_text(int millic) {
    return millic < 0 ? "--C" : std::to_string(millic / 1000) + "C";
}

std::string reply_stats(const LlmState &state, int peak_temperature) {
    return "[" + decimal(state.generation_tps, 2) + " t/s | peak " +
           temperature_text(peak_temperature) + " | prompt " + decimal(state.prompt_tps, 1) +
           " t/s]";
}

std::vector<std::string> settings_items(const Config &config) {
    return {"threads: " + std::to_string(config.threads),
            "ctx: " + std::to_string(config.ctx),
            "max_tokens: " + std::to_string(config.max_tokens),
            "temp: " + decimal(config.temp),
            "brightness: " + std::to_string(config.brightness) + "%",
            "screen timeout: " + (config.screen_timeout == 0
                                      ? std::string("never")
                                      : std::to_string(config.screen_timeout) + " min"),
            "cpu mode: " + config.cpu_mode,
            "link: " + config.link + " (next boot)"};
}

std::vector<Line> device_lines(const DeviceInfo &info) {
    std::vector<Line> lines;
    const std::string battery =
        info.battery_percent < 0 ? "unavailable" : std::to_string(info.battery_percent) + "%";
    add_wrapped(lines, "Battery: " + battery + " - " + info.battery_status, Cyan);
    add_wrapped(lines, "Voltage: " +
                           (info.voltage_uv < 0 ? std::string("unavailable")
                                                : decimal(info.voltage_uv / 1000000.0, 3) + " V") +
                           " | current: " + decimal(info.current_ua / 1000.0, 0) + " mA");
    add_wrapped(lines, std::string("Power: AC ") + (info.ac_online ? "online" : "offline") +
                           " | USB " + (info.usb_online ? "online" : "offline"));
    if (info.thermal_zones.empty())
        add_wrapped(lines, "Thermal sensors: unavailable");
    for (const auto &zone : info.thermal_zones)
        add_wrapped(lines, zone.type + ": " + decimal(zone.temperature_millic / 1000.0) + "C");
    std::string frequency = "CPU: unavailable";
    if (info.cpu_frequency_khz >= 0 && info.cpu_max_frequency_khz > 0) {
        frequency = "CPU: " + std::to_string(info.cpu_frequency_khz / 1000) + "/" +
                    std::to_string(info.cpu_max_frequency_khz / 1000) + " MHz";
        if (info.cpu_governor == "performance" &&
            info.cpu_frequency_khz < info.cpu_max_frequency_khz)
            frequency += " (throttled)";
    }
    add_wrapped(lines, frequency);
    add_wrapped(lines,
                "Governor: " + (info.cpu_governor.empty() ? "unavailable" : info.cpu_governor));
    add_wrapped(lines, "Free RAM: " + std::to_string(info.available_kb / 1024) +
                           " MB | swap used: " + std::to_string(info.swap_used_kb / 1024) + " MB");
    add_wrapped(lines, "eth0: " + (info.eth0_ip.empty() ? "no IPv4 address" : info.eth0_ip));
    add_wrapped(lines, "Build: " + std::string(__DATE__) + " " + __TIME__);
    return lines;
}

void bars(Framebuffer &fb, const std::string &model, double rate, const DeviceInfo &info,
          const std::string &hint) {
    fb.clear();
    fb.rect(0, 0, 640, 24, Gray);
    fb.rect(0, 456, 640, 24, Gray);
    std::string name = fs::path(model).stem().string();
    if (name.empty())
        name = "No model";
    const std::string battery =
        (info.battery_percent < 0 ? std::string("--") : std::to_string(info.battery_percent)) +
        "%" + (info.charging ? "+" : "");
    const std::string temperature = temperature_text(info.temperature_millic);
    const std::string metrics =
        " | " + decimal(rate) + "t/s | " + std::to_string(info.available_kb / 1024) + "M | ";
    const size_t maximum_name =
        53 - std::min<size_t>(53, metrics.size() + battery.size() + temperature.size() + 1);
    if (name.size() > maximum_name)
        name = maximum_name > 3 ? name.substr(0, maximum_name - 3) + "..."
                                : name.substr(0, maximum_name);
    const std::string prefix = name + metrics;
    fb.text(0, 0, prefix);
    const bool low_battery =
        info.battery_percent >= 0 && info.battery_percent <= 15 && !info.charging;
    fb.text(static_cast<int>(prefix.size()), 0, battery, low_battery ? Red : White);
    const uint32_t thermal_color = info.temperature_millic >= 80000   ? Red
                                   : info.temperature_millic >= 70000 ? Yellow
                                                                      : White;
    fb.text(static_cast<int>(prefix.size() + battery.size()) + 1, 0, temperature, thermal_color);
    fb.text(0, 19, hint, 0xbfc6d0);
}

void menu(Framebuffer &fb, const std::vector<std::string> &items, int selected, int row = 3,
          int start = 0, int count = 13) {
    for (int i = start; i < static_cast<int>(items.size()) && i < start + count; ++i) {
        int y = row + i - start;
        if (i == selected)
            fb.rect(0, y * 24, 640, 24, 0x17434b);
        fb.text(1, y, (i == selected ? "> " : "  ") + items[i], i == selected ? Cyan : White);
    }
}

void draw_keyboard(Framebuffer &fb, const std::string &draft, int row, int col, bool shift) {
    fb.text(1, 2, "Compose a message", Cyan);
    auto input = wrap(draft, 49);
    int first = std::max(0, static_cast<int>(input.size()) - 3);
    for (int i = first; i < static_cast<int>(input.size()); ++i)
        fb.text(2, 4 + i - first, input[i], Cyan);
    const std::vector<std::string> letters =
        shift ? std::vector<std::string>{"-'\x3a;()\"@/*", "QWERTYUIOP", "ASDFGHJKL?", "ZXCVBNM,.!"}
              : std::vector<std::string>{"1234567890", "qwertyuiop", "asdfghjkl?", "zxcvbnm,.!"};
    for (int y = 0; y < 4; ++y)
        for (int x = 0; x < static_cast<int>(letters[y].size()); ++x) {
            if (y == row && x == col)
                fb.rect((5 + x * 4) * 12, (10 + y) * 24, 36, 24, 0x17616c);
            fb.text(6 + x * 4, 10 + y, std::string(1, letters[y][x]));
        }
    const std::vector<std::string> commands = {"[SHIFT]", "[SPACE]", "[DEL]", "[SEND]"};
    for (int x = 0; x < 4; ++x) {
        if (row == 4 && x == col)
            fb.rect((5 + x * 11) * 12, 14 * 24, 120, 24, 0x17616c);
        fb.text(5 + x * 11, 14, commands[x], x == 0 && shift ? Yellow : White);
    }
    fb.text(2, 16, shift ? "SHIFT on" : "SHIFT off", 0xa6adb8);
}

void erase_character(std::string &text) {
    if (text.empty())
        return;
    size_t pos = text.size() - 1;
    while (pos > 0 && (static_cast<unsigned char>(text[pos]) & 0xc0) == 0x80)
        --pos;
    text.erase(pos);
}

class DeviceUi {
    Framebuffer fb_;
    Input input_;
    Llm llm_;
    Config config_, saved_settings_;
    Screen screen_ = Screen::Home;
    bool mounted_ = data_mounted();
    std::string link_status_ = "Link: down";
    std::vector<Model> models_;
    std::vector<std::string> presets_;
    std::vector<Line> transcript_;
    int selected_ = 0, scroll_ = 0, krow_ = 0, kcol_ = 0;
    bool shift_ = false, exchange_ = false;
    std::string draft_, notice_, pending_user_, pending_model_;
    std::string session_ = timestamp();
    std::thread benchmark_;
    std::mutex bench_mutex_;
    std::string bench_output_;
    std::atomic<bool> bench_done_{false};
    std::atomic<bool> bench_stop_{false};
    Clock::time_point last_info_{};
    Clock::time_point last_activity_ = Clock::now();
    Clock::time_point power_pressed_at_{};
    Clock::time_point brightness_changed_at_{};
    std::optional<Clock::time_point> critical_battery_since_;
    std::optional<int> pending_brightness_;
    std::array<bool, KEY_MAX + 1> held_{}, swallowed_{};
    DeviceInfo info_;
    int peak_temperature_ = -1;
    bool screen_off_ = false;
    bool power_pressed_ = false;
    bool power_long_press_ = false;
    bool critical_shutdown_attempted_ = false;
    unsigned completed_ = 0;

  public:
    DeviceUi() {
        config_.load();
        input_.set_keymap(config_.keymap);
        if (!apply_brightness(config_.brightness))
            std::fputs("r36llm: could not apply startup brightness\n", stderr);
        if (!apply_cpu_mode(config_.cpu_mode))
            std::fputs("r36llm: could not apply startup CPU mode\n", stderr);
        if (mounted_) {
            fs::create_directories(Root + "logs");
            std::error_code error;
            for (fs::directory_iterator it(Root + "models", error), end; !error && it != end;
                 it.increment(error)) {
                if (it->is_regular_file(error) && it->path().extension() == ".gguf")
                    models_.push_back({it->path().filename().string(), it->file_size(error)});
            }
            std::sort(models_.begin(), models_.end(),
                      [](const Model &a, const Model &b) { return a.name < b.name; });
            presets_ = chat_text::load_prompts(Root + "prompts.txt");
            if (fs::exists("/tmp/r36llm.loading"))
                notice_ = "Previous load crashed (out of memory?) - pick a smaller model";
            else if (!fs::exists("/tmp/r36llm.noautoload") && !models_.empty())
                load(config_.model);
        } else
            notice_ = "Data partition not mounted - see logs on card";
    }

    ~DeviceUi() {
        bench_stop_ = true;
        if (benchmark_.joinable())
            benchmark_.join();
    }

    void run() {
        while (true) {
            update();
            for (const auto &event : input_.poll(30))
                handle_event(event);
            draw();
            fb_.present();
        }
    }

  private:
    void flush_brightness_save() {
        if (!pending_brightness_)
            return;
        Config saved = screen_ == Screen::Settings ? saved_settings_ : config_;
        saved.brightness = *pending_brightness_;
        if (!saved.save()) {
            notice_ = "Could not save brightness";
            std::fputs("r36llm: could not save brightness\n", stderr);
        } else if (screen_ == Screen::Settings) {
            saved_settings_.brightness = *pending_brightness_;
        }
        pending_brightness_.reset();
    }

    void set_screen_off(bool off) {
        if (apply_brightness(config_.brightness, off))
            screen_off_ = off;
        else {
            notice_ = "Could not change the backlight";
            std::fputs("r36llm: could not change the backlight\n", stderr);
        }
        last_activity_ = Clock::now();
    }

    void change_brightness(int value, bool persist) {
        config_.brightness = std::clamp(value, 10, 100);
        if (!apply_brightness(config_.brightness, screen_off_))
            notice_ = "Could not apply brightness";
        if (persist) {
            pending_brightness_ = config_.brightness;
            brightness_changed_at_ = Clock::now();
        }
    }

    void discard_settings() {
        flush_brightness_save();
        const bool brightness_changed = config_.brightness != saved_settings_.brightness;
        const bool cpu_changed = config_.cpu_mode != saved_settings_.cpu_mode;
        config_ = saved_settings_;
        if (brightness_changed && !apply_brightness(config_.brightness, screen_off_))
            notice_ = "Could not restore brightness";
        if (cpu_changed && !apply_cpu_mode(config_.cpu_mode))
            notice_ = "Could not restore CPU mode";
    }

    void confirm_power_off() {
        if (screen_ == Screen::Settings)
            discard_settings();
        if (screen_off_)
            set_screen_off(false);
        screen_ = Screen::Power;
        selected_ = 0;
    }

    void power_off() {
        if (!config_.save())
            std::fputs("r36llm: could not save settings before power off\n", stderr);
        pending_brightness_.reset();
        sync();
        execl("/sbin/poweroff", "poweroff", static_cast<char *>(nullptr));
        notice_ = "Power off failed";
        std::perror("r36llm: power off");
    }

    void handle_event(const KeyEvent &event) {
        if (event.code < 0 || event.code > KEY_MAX)
            return;
        const auto now = Clock::now();
        held_[event.code] = event.pressed;
        last_activity_ = now;
        if (event.code == keys::Power) {
            if (event.pressed && !power_pressed_) {
                power_pressed_ = true;
                power_long_press_ = false;
                power_pressed_at_ = now;
            } else if (!event.pressed && power_pressed_) {
                if (!power_long_press_) {
                    if (now - power_pressed_at_ >= std::chrono::milliseconds(1500))
                        confirm_power_off();
                    else
                        set_screen_off(!screen_off_);
                }
                power_pressed_ = false;
            }
            return;
        }
        if (swallowed_[event.code]) {
            if (!event.pressed)
                swallowed_[event.code] = false;
            return;
        }
        if (!event.pressed)
            return;
        if (screen_off_) {
            swallowed_[event.code] = true;
            set_screen_off(false);
            return;
        }
        if (held_[keys::F] && (event.code == keys::Up || event.code == keys::Down)) {
            change_brightness(config_.brightness + (event.code == keys::Up ? 10 : -10), true);
            return;
        }
        key(event.code);
    }

    void load(const std::string &name) {
        notice_.clear();
        if (llm_.load(Root + "models/" + name, config_))
            pending_model_ = name;
    }

    void new_chat() {
        llm_.clear();
        transcript_.clear();
        exchange_ = false;
        scroll_ = 0;
        session_ = timestamp();
        notice_.clear();
    }

    void send(const std::string &text) {
        if (text.empty())
            return;
        if (llm_.state().busy) {
            notice_ = "Model is busy";
            return;
        }
        if (!llm_.state().loaded) {
            notice_ = "Pick a model before chatting";
            screen_ = Screen::Home;
            return;
        }
        if (llm_.generate(text, config_)) {
            pending_user_ = text;
            add_wrapped(transcript_, "You: " + text, Cyan);
            transcript_.push_back({"", White});
            exchange_ = true;
            peak_temperature_ = info_.temperature_millic;
            draft_.clear();
            notice_.clear();
            scroll_ = 0;
            screen_ = Screen::Chat;
        }
    }

    void update() {
        const auto now = Clock::now();
        auto state = llm_.state();
        if (now - last_info_ >= std::chrono::seconds(1)) {
            link_status_ = link_status();
            info_ = read_device_info();
            if (exchange_)
                peak_temperature_ = std::max(peak_temperature_, info_.temperature_millic);
            const bool critical =
                !info_.charging && info_.battery_percent >= 0 && info_.battery_percent <= 2;
            if (critical && !critical_battery_since_)
                critical_battery_since_ = now;
            if (!critical) {
                critical_battery_since_.reset();
                critical_shutdown_attempted_ = false;
            }
            last_info_ = now;
        }
        if (pending_brightness_ && now - brightness_changed_at_ >= std::chrono::milliseconds(750))
            flush_brightness_save();
        if (power_pressed_ && !power_long_press_ &&
            now - power_pressed_at_ >= std::chrono::milliseconds(1500)) {
            power_long_press_ = true;
            confirm_power_off();
        }
        if (!screen_off_ && !power_pressed_ && config_.screen_timeout > 0 &&
            now - last_activity_ >= std::chrono::minutes(config_.screen_timeout))
            set_screen_off(true);
        if (critical_battery_since_ && !critical_shutdown_attempted_ &&
            now - *critical_battery_since_ >= std::chrono::seconds(30)) {
            critical_shutdown_attempted_ = true;
            std::fprintf(stderr, "r36llm: battery at %d%% for 30 seconds; powering off\n",
                         info_.battery_percent);
            power_off();
        }
        if (state.completed != completed_) {
            completed_ = state.completed;
            if (!state.error.empty())
                notice_ = state.error;
            if (!pending_model_.empty()) {
                if (state.loaded) {
                    config_.model = pending_model_;
                    if (!config_.save())
                        notice_ = "Could not save config.ini";
                    transcript_.clear();
                    session_ = timestamp();
                }
                pending_model_.clear();
            }
            if (exchange_) {
                add_wrapped(transcript_, state.text);
                add_wrapped(transcript_, reply_stats(state, peak_temperature_), 0xa6adb8);
                transcript_.push_back({"", White});
                std::ofstream log(Root + "logs/chat-" + session_ + ".txt", std::ios::app);
                log << "You: " << pending_user_ << "\nAssistant: " << state.text << "\n";
                if (!state.error.empty())
                    log << "Error: " << state.error << '\n';
                if (!log)
                    notice_ = "Could not append chat log";
                exchange_ = false;
            }
        }
        if (bench_done_.exchange(false)) {
            if (benchmark_.joinable())
                benchmark_.join();
            load(config_.model);
        }
    }

    std::vector<std::string> home_items() const {
        if (!mounted_)
            return {"Power off"};
        return {"Chat",
                "Model: " + config_.model,
                "Benchmark all models",
                "Settings",
                "Device info",
                "Power off"};
    }

    void start_benchmark() {
        if (llm_.state().busy) {
            notice_ = "Wait for the current operation to finish";
            return;
        }
        llm_.unload();
        screen_ = Screen::Benchmark;
        scroll_ = 0;
        {
            std::lock_guard<std::mutex> lock(bench_mutex_);
            bench_output_.clear();
        }
        bench_stop_ = false;
        auto models = models_;
        int threads = config_.threads;
        benchmark_ = std::thread([this, models, threads] {
            std::ofstream log(Root + "logs/bench.md", std::ios::app);
            for (const auto &model : models) {
                if (bench_stop_)
                    break;
                std::string heading =
                    "\n## " + model.name + " (" + timestamp("%Y-%m-%d %H:%M:%S") + ")\n";
                log << heading;
                log.flush();
                {
                    std::lock_guard<std::mutex> lock(bench_mutex_);
                    bench_output_ += heading;
                }
                std::string command = "llama-bench -m " +
                                      shell_quote(Root + "models/" + model.name) + " -t " +
                                      std::to_string(threads) + " -p 64 -n 32 -r 2 -o md 2>&1";
                FILE *pipe = popen(command.c_str(), "r");
                if (!pipe) {
                    log << "Could not start llama-bench\n";
                    std::lock_guard<std::mutex> lock(bench_mutex_);
                    bench_output_ += "Could not start llama-bench\n";
                    continue;
                }
                char buffer[1024];
                while (fgets(buffer, sizeof(buffer), pipe)) {
                    log << buffer;
                    log.flush();
                    std::lock_guard<std::mutex> lock(bench_mutex_);
                    bench_output_ += buffer;
                }
                int result = pclose(pipe);
                if (result != 0) {
                    std::string message =
                        "llama-bench failed (status " + std::to_string(result) + ")\n";
                    log << message;
                    std::lock_guard<std::mutex> lock(bench_mutex_);
                    bench_output_ += message;
                }
            }
            {
                std::lock_guard<std::mutex> lock(bench_mutex_);
                bench_output_ += "\nBenchmark complete; reloading configured model.\n";
                if (!log)
                    bench_output_ += "Error writing bench.md\n";
            }
            bench_done_ = true;
        });
    }

    void adjust(int direction) {
        auto cycle = [direction](int value, const std::vector<int> &values) {
            auto found = std::find(values.begin(), values.end(), value);
            int index = found == values.end() ? 0 : static_cast<int>(found - values.begin());
            return values[(index + direction + static_cast<int>(values.size())) % values.size()];
        };
        switch (selected_) {
        case 0:
            config_.threads = std::clamp(config_.threads + direction, 1, 4);
            break;
        case 1:
            config_.ctx = cycle(config_.ctx, {512, 1024, 2048, 4096});
            break;
        case 2:
            config_.max_tokens = cycle(config_.max_tokens, {64, 128, 256, 512});
            break;
        case 3:
            config_.temp =
                std::clamp(std::round((config_.temp + direction * 0.1f) * 10) / 10, 0.1f, 1.5f);
            break;
        case 4:
            change_brightness(config_.brightness + direction * 10, false);
            break;
        case 5:
            config_.screen_timeout = cycle(config_.screen_timeout, {0, 1, 2, 5, 10});
            break;
        case 6: {
            static constexpr std::array<const char *, 3> modes = {"performance", "balanced",
                                                                  "saver"};
            const auto found = std::find(modes.begin(), modes.end(), config_.cpu_mode);
            const int index = found == modes.end() ? 0 : static_cast<int>(found - modes.begin());
            config_.cpu_mode =
                modes[(index + direction + static_cast<int>(modes.size())) % modes.size()];
            if (!apply_cpu_mode(config_.cpu_mode))
                notice_ = "Could not apply CPU mode";
            break;
        }
        case 7: {
            static constexpr std::array<const char *, 3> links = {"ethernet", "gadget", "off"};
            const auto found = std::find(links.begin(), links.end(), config_.link);
            const int index = found == links.end() ? 0 : static_cast<int>(found - links.begin());
            config_.link =
                links[(index + direction + static_cast<int>(links.size())) % links.size()];
            break;
        }
        }
    }

    void keyboard_key(int code) {
        if (code == keys::Select) {
            screen_ = Screen::Chat;
            return;
        }
        if (code == keys::Start) {
            send(draft_);
            return;
        }
        if (code == keys::B) {
            erase_character(draft_);
            return;
        }
        if (code == keys::X) {
            draft_ += ' ';
            return;
        }
        if (code == keys::Y) {
            shift_ = !shift_;
            return;
        }
        if (code == keys::Up || code == keys::Down) {
            krow_ = (krow_ + (code == keys::Up ? 4 : 1)) % 5;
            kcol_ = std::min(kcol_, krow_ == 4 ? 3 : 9);
        }
        int length = krow_ == 4 ? 4 : 10;
        if (code == keys::Left)
            kcol_ = (kcol_ + length - 1) % length;
        if (code == keys::Right)
            kcol_ = (kcol_ + 1) % length;
        if (code != keys::A)
            return;
        if (krow_ == 4) {
            if (kcol_ == 0)
                shift_ = !shift_;
            else if (kcol_ == 1)
                draft_ += ' ';
            else if (kcol_ == 2)
                erase_character(draft_);
            else
                send(draft_);
        } else {
            const std::vector<std::string> normal = {"1234567890", "qwertyuiop", "asdfghjkl?",
                                                     "zxcvbnm,.!"};
            const std::vector<std::string> shifted = {"-'\x3a;()\"@/*", "QWERTYUIOP", "ASDFGHJKL?",
                                                      "ZXCVBNM,.!"};
            draft_ += (shift_ ? shifted : normal)[krow_][kcol_];
        }
    }

    void key(int code) {
        if (screen_ == Screen::Keyboard) {
            keyboard_key(code);
            return;
        }
        if (screen_ == Screen::Chat) {
            if ((code == keys::Select || code == keys::Start) && held_[keys::Select] &&
                held_[keys::Start]) {
                new_chat();
                return;
            }
            if (code == keys::B) {
                if (llm_.state().busy)
                    llm_.stop();
                else {
                    screen_ = Screen::Home;
                    selected_ = 0;
                }
            }
            if (code == keys::A && !llm_.state().busy)
                screen_ = Screen::Keyboard;
            if (code == keys::Y && !llm_.state().busy) {
                screen_ = Screen::Presets;
                selected_ = 0;
            }
            if (code == keys::Up)
                ++scroll_;
            if (code == keys::Down)
                scroll_ = std::max(0, scroll_ - 1);
            if (code == keys::L1)
                scroll_ += 15;
            if (code == keys::R1)
                scroll_ = std::max(0, scroll_ - 15);
            return;
        }
        if (screen_ == Screen::Benchmark) {
            if (code == keys::B && !benchmark_.joinable()) {
                screen_ = Screen::Home;
                selected_ = 0;
            }
            if (code == keys::Up)
                ++scroll_;
            if (code == keys::Down)
                scroll_ = std::max(0, scroll_ - 1);
            if (code == keys::L1)
                scroll_ += 15;
            if (code == keys::R1)
                scroll_ = std::max(0, scroll_ - 15);
            return;
        }
        if (screen_ == Screen::About && code != keys::B) {
            if (code == keys::Up)
                ++scroll_;
            if (code == keys::Down)
                scroll_ = std::max(0, scroll_ - 1);
            if (code == keys::L1)
                scroll_ += 15;
            if (code == keys::R1)
                scroll_ = std::max(0, scroll_ - 15);
            return;
        }
        if (code == keys::B) {
            if (screen_ == Screen::Settings)
                discard_settings();
            screen_ = screen_ == Screen::Presets ? Screen::Chat : Screen::Home;
            selected_ = 0;
            return;
        }
        int size = 0;
        if (screen_ == Screen::Home)
            size = home_items().size();
        if (screen_ == Screen::Models)
            size = models_.size();
        if (screen_ == Screen::Presets)
            size = presets_.size();
        if (screen_ == Screen::Settings)
            size = 8;
        if (code == keys::Up && size)
            selected_ = (selected_ + size - 1) % size;
        if (code == keys::Down && size)
            selected_ = (selected_ + 1) % size;
        if (screen_ == Screen::Settings && (code == keys::Left || code == keys::Right))
            adjust(code == keys::Left ? -1 : 1);
        if (code != keys::A)
            return;
        if (screen_ == Screen::Power) {
            power_off();
            return;
        }
        if (screen_ == Screen::Home) {
            if (!mounted_) {
                screen_ = Screen::Power;
                return;
            }
            switch (selected_) {
            case 0:
                if (!models_.empty())
                    screen_ = Screen::Chat;
                break;
            case 1:
                screen_ = Screen::Models;
                selected_ = 0;
                break;
            case 2:
                if (!models_.empty())
                    start_benchmark();
                break;
            case 3:
                saved_settings_ = config_;
                screen_ = Screen::Settings;
                selected_ = 0;
                break;
            case 4:
                screen_ = Screen::About;
                scroll_ = 0;
                break;
            case 5:
                confirm_power_off();
                break;
            }
        } else if (screen_ == Screen::Models && !models_.empty()) {
            if (llm_.state().busy)
                notice_ = "Wait for the current operation to finish";
            else
                load(models_[selected_].name);
        } else if (screen_ == Screen::Presets && !presets_.empty())
            send(presets_[selected_]);
        else if (screen_ == Screen::Settings) {
            if (llm_.state().busy) {
                notice_ = "Wait for the current operation to finish";
                return;
            }
            if (config_.save()) {
                const bool reload = config_.threads != saved_settings_.threads ||
                                    config_.ctx != saved_settings_.ctx;
                saved_settings_ = config_;
                pending_brightness_.reset();
                if (reload && llm_.state().loaded)
                    load(config_.model);
                notice_ = "Settings saved. Link changes apply next boot";
            } else
                notice_ = "Could not save config.ini";
        }
    }

    void draw_lines(const std::vector<Line> &lines) {
        const auto window = chat_text::visible_window(static_cast<int>(lines.size()), scroll_);
        scroll_ = window.scroll;
        const int first = window.first;
        for (int i = first; i < window.end; ++i)
            fb_.text(0, 1 + i - first, lines[i].text, lines[i].color);
    }

    void draw() {
        auto state = llm_.state();
        std::string hint = "UP/DOWN choose  A select";
        if (screen_ == Screen::Chat)
            hint = "A type Y presets B stop/back L/R page SEL+START new";
        if (screen_ == Screen::Keyboard)
            hint = "A key B del X space Y shift START send SELECT back";
        if (screen_ == Screen::Models || screen_ == Screen::Presets)
            hint = "UP/DOWN choose  A select  B back";
        if (screen_ == Screen::Settings)
            hint = "UP/DOWN choose LEFT/RIGHT adjust A save B back";
        if (screen_ == Screen::Power)
            hint = "A confirm power off  B cancel";
        if (screen_ == Screen::Benchmark)
            hint = "UP/DOWN scroll L/R page B back after completion";
        if (screen_ == Screen::About)
            hint = "UP/DOWN scroll L/R page B back";
        bars(fb_, state.loaded ? state.model : config_.model, state.generation_tps, info_, hint);
        if (screen_ == Screen::Home) {
            fb_.text(1, 1, "R36LLM - pocket-sized conversations", Cyan);
            menu(fb_, home_items(), selected_);
            fb_.text(1, 10, link_status_, link_status_ == "Link: down" ? White : Cyan);
            if (models_.empty() && mounted_)
                fb_.text(0, 12, "No .gguf files in /data/r36llm/models", Yellow);
            fb_.text(1, 14, "F+UP/DOWN brightness | POWER screen off", 0xa6adb8);
            fb_.text(1, 15, "Hold POWER for shutdown confirmation", 0xa6adb8);
        } else if (screen_ == Screen::Chat) {
            auto lines = transcript_;
            if (exchange_) {
                add_wrapped(lines, state.text);
                add_wrapped(lines, reply_stats(state, peak_temperature_), 0xa6adb8);
            }
            if (lines.empty())
                add_wrapped(lines, "A: type a message  Y: choose a preset", Cyan);
            draw_lines(lines);
        } else if (screen_ == Screen::Keyboard)
            draw_keyboard(fb_, draft_, krow_, kcol_, shift_);
        else if (screen_ == Screen::Presets) {
            fb_.text(1, 1, "Prompt presets", Cyan);
            menu(fb_, presets_, selected_, 3, std::max(0, selected_ - 11), 12);
            if (presets_.empty())
                fb_.text(1, 4, "No prompts in prompts.txt", Yellow);
        } else if (screen_ == Screen::Models) {
            fb_.text(1, 1, "Choose a GGUF model", Cyan);
            int start = std::max(0, selected_ - 11);
            const uint64_t threshold = memory_kb("MemTotal") * 1024 * 60 / 100;
            for (int i = start; i < static_cast<int>(models_.size()) && i < start + 12; ++i) {
                int row = 3 + i - start;
                const auto &model = models_[i];
                if (i == selected_)
                    fb_.rect(0, row * 24, 640, 24, 0x17434b);
                std::string name = model.name;
                if (name.size() > 35)
                    name = name.substr(0, 32) + "...";
                fb_.text(0, row,
                         (i == selected_ ? "> " : "  ") + name + " " +
                             std::to_string(model.bytes / 1048576) + " MB",
                         i == selected_ ? Cyan : White);
                if (model.bytes > threshold)
                    fb_.text(47, row, "(big)", Yellow);
            }
            if (models_.empty())
                fb_.text(0, 4, "No .gguf files in /data/r36llm/models", Yellow);
        } else if (screen_ == Screen::Benchmark) {
            std::string output;
            {
                std::lock_guard<std::mutex> lock(bench_mutex_);
                output = bench_output_;
            }
            std::vector<Line> lines;
            add_wrapped(lines, output);
            draw_lines(lines);
        } else if (screen_ == Screen::Settings) {
            fb_.text(1, 1, "Settings", Cyan);
            menu(fb_, settings_items(config_), selected_);
            fb_.text(1, 13, "Brightness and CPU mode apply immediately", 0xa6adb8);
            fb_.text(1, 14, "F+UP/DOWN adjusts and saves brightness", 0xa6adb8);
        } else if (screen_ == Screen::About) {
            fb_.text(1, 1, "Device info", Cyan);
            const auto lines = device_lines(info_);
            const int maximum_scroll = std::max(0, static_cast<int>(lines.size()) - 13);
            scroll_ = std::clamp(scroll_, 0, maximum_scroll);
            for (int i = scroll_; i < static_cast<int>(lines.size()) && i < scroll_ + 13; ++i)
                fb_.text(1, 3 + i - scroll_, lines[i].text, lines[i].color);
        } else if (screen_ == Screen::Power) {
            fb_.text(2, 7, "Power off the handheld?", Yellow);
            fb_.text(2, 9, "Press A to confirm, B to cancel.");
        }
        if (state.loading) {
            fb_.rect(0, 17 * 24, 640, 48, 0x17434b);
            fb_.text(1, 17,
                     "Loading " + std::to_string(static_cast<int>(state.progress * 100)) + "%",
                     Cyan);
        } else if (!notice_.empty()) {
            auto lines = wrap(notice_);
            fb_.rect(0, 17 * 24, 640, 48, 0);
            for (size_t i = 0; i < lines.size() && i < 2; ++i)
                fb_.text(0, 17 + i, lines[i], Red);
        }
        if (!info_.charging && info_.battery_percent >= 0 && info_.battery_percent <= 5) {
            fb_.rect(0, 18 * 24, 640, 24, 0x400000);
            fb_.text(0, 18, "Battery low - charge now", Red);
        }
    }
};
} // namespace

int run_device() {
    DeviceUi ui;
    ui.run();
    return 0;
}

int render_tests(const std::string &directory) {
    fs::create_directories(directory);
    Framebuffer fb(true);
    const Config config;
    const std::string model = config.model;
    DeviceInfo info;
    info.battery_percent = 82;
    info.battery_status = "Charging";
    info.charging = true;
    info.voltage_uv = 4100000;
    info.current_ua = 300000;
    info.usb_online = true;
    info.available_kb = 430080;
    info.swap_used_kb = 16384;
    info.thermal_zones = {{"soc-thermal", 71000}, {"gpu-thermal", 68000}};
    info.temperature_millic = 71000;
    info.cpu_frequency_khz = 1200000;
    info.cpu_max_frequency_khz = 1512000;
    info.cpu_governor = "performance";
    info.eth0_ip = "10.36.0.1";
    bars(fb, model, 3.21, info, "UP/DOWN choose  A select");
    fb.text(1, 1, "R36LLM - pocket-sized conversations", Cyan);
    menu(
        fb,
        {"Chat", "Model: " + model, "Benchmark all models", "Settings", "Device info", "Power off"},
        0);
    fb.text(1, 10, "Link: up (eth0) - ssh root@10.36.0.1", Cyan);
    fb.text(1, 14, "F+UP/DOWN brightness | POWER screen off", 0xa6adb8);
    fb.text(1, 15, "Hold POWER for shutdown confirmation", 0xa6adb8);
    fb.ppm(directory + "/home.ppm");

    bars(fb, model, 3.21, info, "A type Y presets B stop/back L/R page SEL+START new");
    fb.text(0, 2, "You: Tell me a joke about handheld consoles.", Cyan);
    std::vector<Line> chat;
    add_wrapped(
        chat, "Why did the handheld bring a tiny umbrella? Because it was expecting a cloud save!");
    for (size_t i = 0; i < chat.size(); ++i)
        fb.text(0, 4 + i, chat[i].text);
    LlmState reply;
    reply.generation_tps = 3.21;
    reply.prompt_tps = 18.4;
    fb.text(0, 8, reply_stats(reply, 74000), 0xa6adb8);
    fb.ppm(directory + "/chat.ppm");

    bars(fb, model, 3.21, info, "A key B del X space Y shift START send SELECT back");
    draw_keyboard(fb, "hi", 1, 4, false);
    fb.ppm(directory + "/keyboard.ppm");

    bars(fb, model, 3.21, info, "UP/DOWN scroll L/R page B back");
    fb.text(1, 1, "Device info", Cyan);
    const auto lines = device_lines(info);
    for (size_t i = 0; i < lines.size() && i < 13; ++i)
        fb.text(1, 3 + i, lines[i].text, lines[i].color);
    fb.ppm(directory + "/about.ppm");

    info.battery_percent = 5;
    info.battery_status = "Discharging";
    info.charging = false;
    info.temperature_millic = 81000;
    bars(fb, model, 3.21, info, "UP/DOWN choose LEFT/RIGHT adjust A save B back");
    fb.text(1, 1, "Settings", Cyan);
    menu(fb, settings_items(config), 4);
    fb.text(1, 13, "Brightness and CPU mode apply immediately", 0xa6adb8);
    fb.text(1, 14, "F+UP/DOWN adjusts and saves brightness", 0xa6adb8);
    fb.rect(0, 18 * 24, 640, 24, 0x400000);
    fb.text(0, 18, "Battery low - charge now", Red);
    fb.ppm(directory + "/settings.ppm");
    return 0;
}
} // namespace r36
