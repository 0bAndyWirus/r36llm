#include "test.h"
#include "../src/config.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {

class TempDir {
public:
    TempDir() {
        std::string pattern = (std::filesystem::temp_directory_path() / "r36-config-XXXXXX").string();
        std::vector<char> buffer(pattern.begin(), pattern.end());
        buffer.push_back('\0');
        char *created = mkdtemp(buffer.data());
        CHECK(created != nullptr);
        path_ = created;
    }
    ~TempDir() {
        std::error_code ignored;
        std::filesystem::remove_all(path_, ignored);
    }
    std::string file() const { return (path_ / "config.ini").string(); }

private:
    std::filesystem::path path_;
};

void write_file(const std::string &path, const std::string &content) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    CHECK(static_cast<bool>(file));
    file << content;
    file.close();
    CHECK(!file.fail());
}

std::string read_file(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    CHECK(static_cast<bool>(file));
    return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

void check_equal(const r36::Config &a, const r36::Config &b) {
    CHECK(a.model == b.model);
    CHECK(a.output_keep == b.output_keep);
    CHECK(a.system == b.system);
    CHECK(a.usb_gadget_fn == b.usb_gadget_fn);
    CHECK(a.link == b.link);
    CHECK(a.cpu_mode == b.cpu_mode);
    CHECK(a.keymap == b.keymap);
    CHECK(a.brightness == b.brightness);
    CHECK(a.screen_timeout == b.screen_timeout);
    CHECK(a.threads == b.threads);
    CHECK(a.ctx == b.ctx);
    CHECK(a.max_tokens == b.max_tokens);
    CHECK(a.top_k == b.top_k);
    CHECK(a.swap_p2 == b.swap_p2);
    CHECK(a.temp == b.temp);
    CHECK(a.top_p == b.top_p);
}

} // namespace

void test_config() {
    TempDir dir;
    const std::string path = dir.file();
    r36::Config config;
    config.model = "previous";
    config.keymap = "mainline";
    config.load(path); // Missing files reset settings just like an empty file.
    r36::Config defaults;
    const uint64_t total = r36::memory_kb("MemTotal");
    if (total != 0 && total < 600000)
        defaults.ctx = 1024;
    check_equal(config, defaults);
    CHECK(config.keymap == "auto");
    CHECK(config.output_keep.empty());
    CHECK(config.output_keep_for_model("/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf").empty());

    write_file(path, "output_keep = /data/r36llm/output-keep-en-fr.txt # opt in\n");
    config.load(path);
    CHECK(config.output_keep == "/data/r36llm/output-keep-en-fr.txt");
    CHECK(config.output_keep_for_model("/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf") == config.output_keep);
    CHECK(config.output_keep_for_model("Ternary-Bonsai-2-2B-PTQ1_0.gguf") == config.output_keep);
    CHECK(config.output_keep_for_model("/data/r36llm/models/SmolLM2-135M-Instruct-Q4_0.gguf").empty());
    CHECK(config.output_keep_for_model("/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf.other").empty());
    write_file(path, "output_keep=/old/list.txt\noutput_keep=\n");
    config.load(path);
    CHECK(config.output_keep.empty());

    write_file(path,
        " # comment with threads=99\r\n"
        "unknown = ignored\r\n"
        "model = custom.gguf # comment\r\n"
        "output_keep = /data/r36llm/output-keep-en-fr.txt\r\n"
        "system = hello = world # trailing comment\r\n"
        "usb_gadget_fn = ecm\r\n"
        "link = gadget\r\n"
        "cpu_mode = balanced\r\n"
        "keymap = vendor44\r\n"
        "threads = 256\r\nctx = 1048576\r\nmax_tokens = 1048576\r\n"
        "top_k = 1048576\r\nswap_p2 = 1\r\n"
        "brightness = 100\r\nscreen_timeout = 10\r\n"
        "temp = 100\r\ntop_p = 1\r\n");
    config.load(path);
    CHECK(config.model == "custom.gguf");
    CHECK(config.output_keep == "/data/r36llm/output-keep-en-fr.txt");
    CHECK(config.system == "hello = world");
    CHECK(config.usb_gadget_fn == "ecm");
    CHECK(config.link == "gadget");
    CHECK(config.cpu_mode == "balanced");
    CHECK(config.keymap == "vendor44");
    CHECK(config.threads == 256);
    CHECK(config.ctx == 1048576);
    CHECK(config.max_tokens == 1048576);
    CHECK(config.top_k == 1048576);
    CHECK(config.swap_p2 == 1);
    CHECK(config.brightness == 100);
    CHECK(config.screen_timeout == 10);
    CHECK(config.temp == 100.0f);
    CHECK(config.top_p == 1.0f);

    // Rejected values leave the last accepted value, rather than being clamped.
    write_file(path,
        "threads=1\nthreads=0\nthreads=257\nthreads=3x\nthreads=999999999999999999\n"
        "ctx=1\nctx=0\nctx=1048577\n"
        "max_tokens=1\nmax_tokens=0\nmax_tokens=1048577\n"
        "top_k=0\ntop_k=-1\ntop_k=1048577\n"
        "swap_p2=0\nswap_p2=-1\nswap_p2=2\n"
        "brightness=10\nbrightness=9\nbrightness=101\nbrightness=15\n"
        "screen_timeout=0\nscreen_timeout=-1\nscreen_timeout=11\nscreen_timeout=3\n"
        "temp=0\ntemp=-0.1\ntemp=100.1\ntemp=nan\ntemp=inf\ntemp=1x\n"
        "top_p=0\ntop_p=-0.1\ntop_p=1.1\ntop_p=nan\n"
        "model=valid.gguf\nmodel=\nusb_gadget_fn=rndis\nusb_gadget_fn=\n"
        "system=nonempty\nsystem=\nlink=off\nlink=invalid\n"
        "cpu_mode=saver\ncpu_mode=invalid\nkeymap=mainline\nkeymap=invalid\n");
    config.load(path);
    CHECK(config.threads == 1);
    CHECK(config.ctx == 1);
    CHECK(config.max_tokens == 1);
    CHECK(config.top_k == 0);
    CHECK(config.swap_p2 == 0);
    CHECK(config.brightness == 10);
    CHECK(config.screen_timeout == 0);
    CHECK(config.temp == 0.0f);
    CHECK(config.top_p == 0.0f);
    CHECK(config.model == "valid.gguf");
    CHECK(config.usb_gadget_fn == "rndis");
    CHECK(config.system.empty());
    CHECK(config.link == "off");
    CHECK(config.cpu_mode == "saver");
    CHECK(config.keymap == "mainline");

    write_file(path, "keymap=invalid\n");
    config.load(path);
    CHECK(config.keymap == "auto");
    CHECK(config.output_keep.empty()); // Missing keys also reset a previous opt-in.
    write_file(path, "keymap=vendor44\nkeymap=auto\n");
    config.load(path);
    CHECK(config.keymap == "auto");

    write_file(path, "# preserved comment\nunknown = keep me\nnot an assignment\n\n"
                     "keymap=vendor44 # replaced\nkeymap=auto\nthreads=2\n"
                     "output_keep=/old/list.txt\noutput_keep=/duplicate/list.txt\n");
    config.model = "roundtrip.gguf";
    config.output_keep = "/data/r36llm/output-keep-en-fr.txt";
    config.system = "roundtrip system";
    config.usb_gadget_fn = "rndis";
    config.link = "gadget";
    config.cpu_mode = "balanced";
    config.keymap = "mainline";
    config.brightness = 70;
    config.screen_timeout = 5;
    config.threads = 3;
    config.ctx = 4096;
    config.max_tokens = 512;
    config.top_k = 42;
    config.swap_p2 = 0;
    config.temp = 0.1234567f;
    config.top_p = 0.7654321f;
    CHECK(config.save(path));
    const std::string saved = read_file(path);
    CHECK(saved.find("# preserved comment\nunknown = keep me\nnot an assignment\n\n") != std::string::npos);
    CHECK(saved.find("keymap=mainline\n") != std::string::npos);
    CHECK(saved.find("output_keep=/data/r36llm/output-keep-en-fr.txt\n") != std::string::npos);
    CHECK(saved.find("output_keep=/old/list.txt") == std::string::npos);
    CHECK(saved.find("output_keep=/duplicate/list.txt") == std::string::npos);
    CHECK(saved.find("keymap=vendor44") == std::string::npos);
    CHECK(saved.find("keymap=auto") == std::string::npos);
    r36::Config loaded;
    loaded.load(path);
    check_equal(loaded, config);
    CHECK(!config.save(path + "/missing/config.ini"));
}
