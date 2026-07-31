#pragma once

// Grecharged-mesh-browser V2: freecam NORMAL GIZMOS — per-face normal arrows over the targeted
// mesh (Circle in the freecam). The one debug tool for the orientation hunt: an INWARD-pointing
// normal visibly dives into its own surface. Faces are unpacked from the CPU-side tfrag3::Level
// EXACTLY the way tools/tess_sign/main.cpp does (same strip walk, same cross-product winding
// order), so an arrow that points inward here is the same "inward" the offline A_sign grader
// means. Filtered per-face by the target row's AABB (mb_target_bbox, expanded by 2048 GOAL
// units). Called at the END of TFragment::render (system 0) and Tie3::render (system 1); both
// call sites early-out on one compare when the target/gizmo toggles are off.

#include "common/custom_data/Tfrag3Data.h"

#include "game/graphics/opengl_renderer/background/background_common.h"

namespace mb_gizmos {

// Build (cached on (level, system, tex, bbox)) + draw the arrow overlay. `system` is the
// caller's own system (0 = TFRAG, 1 = TIE) and `level_name` its own m_level_name; a call whose
// system/level does not match the target is a no-op. GL thread only.
void render(const tfrag3::Level* lev,
            int system,
            const char* level_name,
            SharedRenderState* render_state,
            ScopedProfilerNode& prof);

// V2.4 persistent MARKED-polygon highlight (owner: "on devrait voir ce qui est marqué d'une
// façon différente"): draws every active mark of the store (gfx.h mb_marks_store, world-space
// vertices — no level data needed) as a filled orange triangle, once per frame no matter how
// many bucket renderers call in (mb_frame_no stamp). Independent of the Circle gizmo toggle;
// call sites gate on (mb_pbr_override && mb_marks_active > 0). GL thread only.
void render_marks(SharedRenderState* render_state, ScopedProfilerNode& prof);

}  // namespace mb_gizmos

namespace mb_pick {

// V2.1 TRIANGLE-ACCURATE reticle pick (see the channel doc at gfx.h mb_pick_*). Cheap standing
// check for the render() hooks: true only while a pick request is awaiting triangle results.
inline bool pending() {
  const auto& s = Gfx::g_global_settings;
  return s.mb_pick_serial.load(std::memory_order_relaxed) !=
         s.mb_pick_done.load(std::memory_order_relaxed);
}

// V2.3: sweep EVERY draw of THIS system+level against the pending pick ray (same face walk +
// winding as the gizmos above) and insert the ray-triangle hits into mb_pick_hits_out (ascending
// t, deduped by (sys, texid, lvl)). GL thread only; called from TFragment::render / Tie3::render
// behind pending(); internally no-ops until the request is ARMED and sweeps each
// (serial, lev, system) once.
void raytest(const tfrag3::Level* lev, int system, const char* level_name);

}  // namespace mb_pick
