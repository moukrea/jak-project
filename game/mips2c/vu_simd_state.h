#pragma once

#include <cstdint>

namespace Mips2C::vu_simd {
enum class Kernel { Bones, Joints, Particles };
struct Settings {
  bool vector_enabled;
  bool verify;
};
Settings settings(Kernel kernel);
void record(Kernel kernel, uint64_t compared, uint64_t defects);
// Called on the GOAL thread, once per simulated frame.
void frame_boundary();
}  // namespace Mips2C::vu_simd
