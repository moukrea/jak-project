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
            const GoalBackgroundCameraData& camera,
            SharedRenderState* render_state,
            ScopedProfilerNode& prof);

}  // namespace mb_gizmos
