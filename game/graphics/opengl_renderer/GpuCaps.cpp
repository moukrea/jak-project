#include "GpuCaps.h"

#include <cstring>

#include "common/log/log.h"

#include "game/graphics/pipelines/opengl.h"

namespace gpu_caps {

namespace {
Caps g_caps;
bool g_done = false;

bool has_extension(const char* name) {
  GLint n = 0;
  glGetIntegerv(GL_NUM_EXTENSIONS, &n);
  for (GLint i = 0; i < n; i++) {
    const auto* e = (const char*)glGetStringi(GL_EXTENSIONS, i);
    if (e && strcmp(e, name) == 0) {
      return true;
    }
  }
  return false;
}
}  // namespace

const Caps& detect() {
  if (g_done) {
    return g_caps;
  }
  g_done = true;

  const auto* ver = (const char*)glGetString(GL_VERSION);
  const std::string vs = ver ? ver : "";
  g_caps.gles = vs.find("OpenGL ES") != std::string::npos;
  // Both desktop ("4.3.0 ...") and ES ("OpenGL ES 3.2 v@...") report the
  // numbers first in their respective slice, so scan for the first digit.
  for (size_t i = 0; i + 2 < vs.size(); i++) {
    if (isdigit((unsigned char)vs[i]) && vs[i + 1] == '.' && isdigit((unsigned char)vs[i + 2])) {
      g_caps.gl_major = vs[i] - '0';
      g_caps.gl_minor = vs[i + 2] - '0';
      break;
    }
  }

  if (g_caps.gles) {
    // ETC2/EAC is core in GLES 3.0 — guaranteed on every target this port
    // supports (it asks for a 3.2 context).
    g_caps.etc2 = g_caps.gl_major >= 3;
    g_caps.astc_ldr = has_extension("GL_KHR_texture_compression_astc_ldr");
  } else {
    // RGTC is core since GL 3.0, BPTC since 4.2 — but macOS caps out at 4.1,
    // so the extension strings decide when the version does not.
    const bool v42 = g_caps.gl_major > 4 || (g_caps.gl_major == 4 && g_caps.gl_minor >= 2);
    const bool v30 = g_caps.gl_major >= 3;
    g_caps.bptc = v42 || has_extension("GL_ARB_texture_compression_bptc");
    g_caps.rgtc = v30 || has_extension("GL_EXT_texture_compression_rgtc") ||
                  has_extension("GL_ARB_texture_compression_rgtc");
    g_caps.s3tc = has_extension("GL_EXT_texture_compression_s3tc");
    g_caps.astc_ldr = has_extension("GL_KHR_texture_compression_astc_ldr");
    g_caps.etc2 = has_extension("GL_ARB_ES3_compatibility");
  }

  lg::info(
      "gpu caps: {} {}.{} bptc={} rgtc={} s3tc={} etc2={} astc={} -> asset profile '{}'",
      g_caps.gles ? "GLES" : "GL", g_caps.gl_major, g_caps.gl_minor, g_caps.bptc, g_caps.rgtc,
      g_caps.s3tc, g_caps.etc2, g_caps.astc_ldr, preferred_profile());
  return g_caps;
}

std::string preferred_profile() {
  const auto& c = g_done ? g_caps : detect();
  if (c.gles) {
    if (c.astc_ldr) {
      return "android-astc";
    }
    if (c.etc2) {
      return "android-etc2";
    }
    return "";  // below the GLES 3.0 baseline: stock textures
  }
  if (c.bptc && c.rgtc) {
    return "pc-bc";
  }
  if (c.s3tc && c.rgtc) {
    return "pc-bc-legacy";
  }
  // Deliberately NOT android-etc2 on desktop: that would be software
  // decompression on most desktop drivers (spec §4.1).
  return "";
}

}  // namespace gpu_caps
