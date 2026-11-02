// Expose device mode and offscreen render-test entry points.
#pragma once
#include <string>

namespace r36 {
int run_device();
int render_tests(const std::string &directory);
} // namespace r36
