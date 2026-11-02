// Provide a 640x480 drawing surface and framebuffer presentation.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <linux/fb.h>
#include <string>
#include <vector>

namespace r36 {

class Framebuffer {
  public:
    explicit Framebuffer(bool offscreen = false);
    ~Framebuffer();
    Framebuffer(const Framebuffer &) = delete;
    Framebuffer &operator=(const Framebuffer &) = delete;

    void clear(uint32_t rgb = 0);
    void rect(int x, int y, int w, int h, uint32_t rgb);
    void text(int col, int row, const std::string &, uint32_t rgb = 0xffffff);
    void present();
    void ppm(const std::string &path) const;

  private:
    std::vector<uint32_t> pixels_;
    int fd_ = -1;
    uint8_t *mapping_ = nullptr;
    std::size_t mapping_size_ = 0;
    fb_fix_screeninfo fixed_{};
    fb_var_screeninfo var_{};
    std::array<uint32_t, 256> red_{}, green_{}, blue_{};
    uint32_t alpha_ = 0;
    bool graphics_ = false;
};

} // namespace r36
