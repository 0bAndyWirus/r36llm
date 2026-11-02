// Render text and graphics to the Linux framebuffer or an offscreen image.
#include "fb.h"
#include "font.h"

#include <algorithm>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <linux/kd.h>
#include <stdexcept>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <system_error>
#include <unistd.h>

namespace r36 {
namespace {
constexpr int width = 640, height = 480;
int console_fd = -1;
int console_mode = KD_TEXT;
unsigned console_users = 0;

struct sigaction old_int {};

struct sigaction old_term {};

void restore_console() {
    if (console_fd >= 0) {
        ioctl(console_fd, KDSETMODE, console_mode);
        close(console_fd);
        console_fd = -1;
    }
}

void on_signal(int sig) {
    if (console_fd >= 0)
        ioctl(console_fd, KDSETMODE, console_mode);
    _exit(128 + sig);
}

bool enter_graphics() {
    if (console_users) {
        ++console_users;
        return true;
    }
    int fd = dup(STDIN_FILENO);
    if (fd < 0 || !isatty(fd)) {
        if (fd >= 0)
            close(fd);
        fd = open("/dev/tty1", O_RDWR | O_CLOEXEC);
    }
    if (fd < 0)
        return false;
    int mode;
    if (ioctl(fd, KDGETMODE, &mode) < 0 || ioctl(fd, KDSETMODE, KD_GRAPHICS) < 0) {
        close(fd);
        return false;
    }
    console_fd = fd;
    console_mode = mode;
    console_users = 1;
    static bool registered = false;
    if (!registered) {
        std::atexit(restore_console);
        registered = true;
    }

    struct sigaction action {};

    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, &old_int);
    sigaction(SIGTERM, &action, &old_term);
    return true;
}

void leave_graphics() {
    if (--console_users == 0) {
        restore_console();
        sigaction(SIGINT, &old_int, nullptr);
        sigaction(SIGTERM, &old_term, nullptr);
    }
}

uint32_t channel(uint32_t value, const fb_bitfield &field) {
    if (!field.length || field.offset >= 32 || field.length > 32 - field.offset)
        return 0;
    const uint64_t maximum = (uint64_t{1} << field.length) - 1;
    uint32_t scaled = static_cast<uint32_t>((value * maximum + 127) / 255);
    if (field.msb_right) {
        uint32_t reversed = 0;
        for (unsigned i = 0; i < field.length; ++i) {
            reversed = (reversed << 1) | (scaled & 1);
            scaled >>= 1;
        }
        scaled = reversed;
    }
    return scaled << field.offset;
}

uint32_t utf8_next(const std::string &s, std::size_t &pos) {
    const auto first = static_cast<unsigned char>(s[pos++]);
    if (first < 0x80)
        return first;
    unsigned count = 0;
    uint32_t cp = 0, min = 0;
    if (first >= 0xc2 && first <= 0xdf) {
        count = 1;
        cp = first & 0x1f;
        min = 0x80;
    } else if (first >= 0xe0 && first <= 0xef) {
        count = 2;
        cp = first & 0x0f;
        min = 0x800;
    } else if (first >= 0xf0 && first <= 0xf4) {
        count = 3;
        cp = first & 7;
        min = 0x10000;
    } else
        return '?';
    if (s.size() - pos < count)
        return '?';
    for (unsigned i = 0; i < count; ++i) {
        auto c = static_cast<unsigned char>(s[pos + i]);
        if ((c & 0xc0) != 0x80)
            return '?';
        cp = (cp << 6) | (c & 0x3f);
    }
    pos += count;
    return cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) ? '?' : cp;
}
} // namespace

Framebuffer::Framebuffer(bool offscreen) : pixels_(width * height, 0) {
    if (offscreen)
        return;
    fd_ = open("/dev/fb0", O_RDWR | O_CLOEXEC);
    if (fd_ < 0)
        throw std::system_error(errno, std::generic_category(), "open /dev/fb0");
    if (ioctl(fd_, FBIOGET_FSCREENINFO, &fixed_) < 0 ||
        ioctl(fd_, FBIOGET_VSCREENINFO, &var_) < 0) {
        int error = errno;
        close(fd_);
        fd_ = -1;
        throw std::system_error(error, std::generic_category(), "framebuffer info");
    }
    if ((var_.bits_per_pixel != 16 && var_.bits_per_pixel != 32) || !fixed_.smem_len ||
        !fixed_.line_length) {
        close(fd_);
        fd_ = -1;
        throw std::runtime_error("unsupported framebuffer format");
    }
    for (unsigned value = 0; value < 256; ++value) {
        red_[value] = channel(value, var_.red);
        green_[value] = channel(value, var_.green);
        blue_[value] = channel(value, var_.blue);
    }
    alpha_ = channel(255, var_.transp);
    mapping_size_ = fixed_.smem_len;
    void *p = mmap(nullptr, mapping_size_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0);
    if (p == MAP_FAILED) {
        int error = errno;
        close(fd_);
        fd_ = -1;
        throw std::system_error(error, std::generic_category(), "mmap framebuffer");
    }
    mapping_ = static_cast<uint8_t *>(p);
    graphics_ = enter_graphics();
}

Framebuffer::~Framebuffer() {
    if (graphics_)
        leave_graphics();
    if (mapping_)
        munmap(mapping_, mapping_size_);
    if (fd_ >= 0)
        close(fd_);
}

void Framebuffer::clear(uint32_t rgb) {
    std::fill(pixels_.begin(), pixels_.end(), rgb & 0xffffff);
}

void Framebuffer::rect(int x, int y, int w, int h, uint32_t rgb) {
    if (w <= 0 || h <= 0)
        return;
    const int left = std::max<int64_t>(0, x), top = std::max<int64_t>(0, y);
    const int right = std::min<int64_t>(width, int64_t(x) + w);
    const int bottom = std::min<int64_t>(height, int64_t(y) + h);
    if (left >= right || top >= bottom)
        return;
    for (int py = top; py < bottom; ++py)
        std::fill(pixels_.begin() + py * width + left, pixels_.begin() + py * width + right,
                  rgb & 0xffffff);
}

void Framebuffer::text(int col, int row, const std::string &s, uint32_t rgb) {
    if (row < 0 || row >= height / 24 || col >= 53)
        return;
    std::size_t pos = 0;
    int64_t xcol = col;
    while (pos < s.size() && xcol < 53) {
        uint32_t cp = utf8_next(s, pos);
        if (cp < 32 || cp > 255)
            cp = '?';
        if (xcol >= 0) {
            for (int y = 0; y < 24; ++y) {
                uint16_t bits = font[cp - 32][y];
                for (int x = 0; x < 12; ++x)
                    if (bits & (0x8000u >> x))
                        pixels_[(row * 24 + y) * width + xcol * 12 + x] = rgb & 0xffffff;
            }
        }
        ++xcol;
    }
}

void Framebuffer::present() {
    if (!mapping_)
        return;
    const unsigned bytes = var_.bits_per_pixel / 8;
    const uint32_t rows = std::min<uint32_t>(height, var_.yres);
    const uint32_t cols = std::min<uint32_t>(width, var_.xres);
    for (uint32_t y = 0; y < rows; ++y) {
        const uint64_t line = (uint64_t(y) + var_.yoffset) * fixed_.line_length;
        for (uint32_t x = 0; x < cols; ++x) {
            const uint64_t in_line = (uint64_t(x) + var_.xoffset) * bytes;
            const uint64_t offset = line + in_line;
            if (in_line + bytes > fixed_.line_length || offset + bytes > mapping_size_)
                continue;
            uint32_t rgb = pixels_[y * width + x];
            uint32_t pixel =
                alpha_ | red_[(rgb >> 16) & 255] | green_[(rgb >> 8) & 255] | blue_[rgb & 255];
            if (bytes == 2) {
                uint16_t value = static_cast<uint16_t>(pixel);
                std::memcpy(mapping_ + offset, &value, sizeof(value));
            } else
                std::memcpy(mapping_ + offset, &pixel, sizeof(pixel));
        }
    }
}

void Framebuffer::ppm(const std::string &path) const {
    std::ofstream out(path, std::ios::binary);
    if (!out)
        throw std::runtime_error("cannot open PPM: " + path);
    out << "P6\n" << width << ' ' << height << "\n255\n";
    for (uint32_t pixel : pixels_) {
        const char rgb[] = {static_cast<char>(pixel >> 16), static_cast<char>(pixel >> 8),
                            static_cast<char>(pixel)};
        out.write(rgb, sizeof(rgb));
    }
    if (!out)
        throw std::runtime_error("cannot write PPM: " + path);
}
} // namespace r36
