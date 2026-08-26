#pragma once

// Grecharged-managed-assets: which compressed-texture families this GPU
// actually supports, and therefore which asset profile to install.
// Queried ONCE after the GL context exists (the extension string and the
// version are both context state).
//
// Order (spec §15): Android ASTC > ETC2/EAC; PC BC7/BC5/BC4 > BC3/BC1 >
// uncompressed. The uncompressed fallback is explicit and logged — never a
// silent software-decompression path.

#include <string>

namespace gpu_caps {

struct Caps {
  bool bptc = false;   // BC7  (GL 4.2 core / ARB_texture_compression_bptc)
  bool rgtc = false;   // BC4/BC5 (GL 3.0 core / EXT_texture_compression_rgtc)
  bool s3tc = false;   // BC1/BC3 (EXT_texture_compression_s3tc)
  bool etc2 = false;   // ETC2/EAC (GLES 3.0 core; desktop drivers may expose it)
  bool astc_ldr = false;  // KHR_texture_compression_astc_ldr
  bool gles = false;
  int gl_major = 0;
  int gl_minor = 0;
};

// Detect from the current context. Safe to call more than once; the result
// is cached and logged on the first call.
const Caps& detect();

// The asset profile to request from the manifest, or "" when this GPU can
// use no shipped profile (the caller then stays on stock textures).
std::string preferred_profile();

}  // namespace gpu_caps
