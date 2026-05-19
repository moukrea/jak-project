// Phase 27 (autoport): minimal graphics stubs for code that references the
// Gfx:: namespace's global state. The full OpenGL renderer (game/graphics/
// gfx.cpp + opengl_renderer/*) doesn't cross-compile on Bionic yet because
// the desktop renderer depends on dozens of GL_EXT extensions GLES doesn't
// have. We only need `Gfx::g_global_settings` to satisfy the VBlank handler
// in game/overlord/jak1/srpc.cpp — everything else in gfx.cpp is unused on
// our boot path.
//
// gfx.h declares the GfxGlobalSettings struct in full; we just instantiate
// it with its default initializers (which exist for every field). The
// resulting layout matches every TU that includes gfx.h, so srpc.cpp's
// `g_global_settings.target_fps` read produces the upstream default
// (60.0f) — sensible behavior for the VBlank pacing calculation.

#include "game/graphics/gfx.h"

namespace Gfx {
GfxGlobalSettings g_global_settings;
}  // namespace Gfx
