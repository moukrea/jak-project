#include "MeshBrowserGizmos.h"

#include <cstring>
#include <vector>

#include "common/log/log.h"

namespace mb_gizmos {

namespace {

// Same layout as TFragment::DebugVertex (TFragment.h:81) — position + rgba, locations 0/1 of the
// TFRAG3_NO_TEX program (the same shader render_tree_cull_debug draws with).
struct GizmoVertex {
  math::Vector3f position;
  math::Vector4f rgba;
};

// Arrow sizing, GOAL units: shaft (green) = 80% of the arrow, tip (red) = the last 20%, so the
// direction is readable at a glance — an inward normal visibly dives into the surface.
constexpr float kArrowLen = 1638.f;
// Per-face AABB filter slack around mb_target_bbox, GOAL units.
constexpr float kBboxExpand = 2048.f;
// Build cap — a jak1 tex-id population can span a whole level's worth of faces.
constexpr u32 kMaxFaces = 30000;

// The cached build. ONE cache is enough: there is a single target, so only one (level, system)
// pair ever passes the filters at a time. Static vectors are reused across rebuilds (no per-frame
// heap traffic when the key is unchanged, none at all when the tool is inactive — the caller
// early-outs before reaching this file).
struct Cache {
  bool valid = false;
  const tfrag3::Level* lev = nullptr;  // also guards against an fr3 reload under the same name
  int system = -1;
  u32 tex = 0;
  float bbox[6] = {0.f, 0.f, 0.f, 0.f, 0.f, 0.f};
  char level[16] = {0};
  std::vector<GizmoVertex> verts;
  u32 face_count = 0;
  GLuint vao = 0;
  GLuint vbo = 0;
  size_t vbo_size = 0;  // bytes currently allocated in the VBO
};
Cache g_cache;

// Walk one draw's index range and hand every non-degenerate triangle to `emit(i0, i1, i2)`,
// EXACTLY like tools/tess_sign/main.cpp walk_tris (:1100-1163): UINT32_MAX restarts a strip, and
// within a strip the winding flips on odd steps as (b, a, vi) — the SAME order whose
// cross(p1-p0, p2-p0) the offline A_sign grader calls the stored winding's geometric normal.
template <typename F>
void walk_tris(const std::vector<u32>& idx, u32 first, u64 count, bool strips, size_t vcount,
               F&& emit_cb) {
  auto emit = [&](u32 a, u32 b, u32 c) {
    if (a == b || b == c || a == c) {
      return;  // degenerate (strip stitch)
    }
    if (a >= vcount || b >= vcount || c >= vcount) {
      return;  // out of bounds — defensive, like tess_sign's n_oob
    }
    emit_cb(a, b, c);
  };
  if ((u64)first + count > (u64)idx.size()) {
    return;
  }
  if (strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u64 j = 0; j < count; j++) {
      const u32 vi = idx[first + j];
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        if ((k & 1) != 0) {
          emit(b, a, vi);
        } else {
          emit(a, b, vi);
        }
      }
      a = b;
      b = vi;
      k++;
    }
  } else {
    for (u64 j = 0; j + 2 < count; j += 3) {
      const u32 t0 = idx[first + j], t1 = idx[first + j + 1], t2 = idx[first + j + 2];
      if (t0 == UINT32_MAX || t1 == UINT32_MAX || t2 == UINT32_MAX) {
        continue;
      }
      emit(t0, t1, t2);
    }
  }
}

// One face -> 2 GL_LINES segments (4 vertices): base -> base + 0.8*len*n in GREEN, then the tip
// -> base + len*n in RED. Returns false when the face fails the bbox filter or the cap is hit.
bool try_emit_face(const std::vector<tfrag3::PreloadedVertex>& verts,
                   u32 i0,
                   u32 i1,
                   u32 i2,
                   const float* bb) {
  if (g_cache.face_count >= kMaxFaces) {
    return false;
  }
  const auto& v0 = verts[i0];
  const auto& v1 = verts[i1];
  const auto& v2 = verts[i2];
  // keep faces whose 3 vertices ALL lie inside the expanded target AABB.
  for (const auto* v : {&v0, &v1, &v2}) {
    if (v->x < bb[0] - kBboxExpand || v->x > bb[3] + kBboxExpand ||  //
        v->y < bb[1] - kBboxExpand || v->y > bb[4] + kBboxExpand ||  //
        v->z < bb[2] - kBboxExpand || v->z > bb[5] + kBboxExpand) {
      return false;
    }
  }
  const math::Vector3f p0(v0.x, v0.y, v0.z);
  const math::Vector3f p1(v1.x, v1.y, v1.z);
  const math::Vector3f p2(v2.x, v2.y, v2.z);
  // tess_sign winding order: cross(p1-p0, p2-p0) IS the stored winding's geometric normal.
  math::Vector3f n = (p1 - p0).cross(p2 - p0);
  const float nl = n.length();
  if (nl <= 0.f) {
    return false;  // zero-area face — no direction to show
  }
  n /= nl;
  const math::Vector3f base = (p0 + p1 + p2) / 3.f;
  const math::Vector3f knee = base + n * (0.8f * kArrowLen);
  const math::Vector3f tip = base + n * kArrowLen;
  const math::Vector4f green(0.f, 1.f, 0.f, 1.f);
  const math::Vector4f red(1.f, 0.f, 0.f, 1.f);
  g_cache.verts.push_back({base, green});
  g_cache.verts.push_back({knee, green});
  g_cache.verts.push_back({knee, red});
  g_cache.verts.push_back({tip, red});
  g_cache.face_count++;
  return true;
}

// Rebuild the arrow list for the current key. Walks geom 0 ONLY — one LOD, matching the offline
// mesh_index truth (walking every geo re-collects the same surface up to 3x — the exact duplicate
// trap the orient-authority pipeline hit).
void build(const tfrag3::Level* lev, int system, u32 tex, const float* bb) {
  g_cache.verts.clear();
  g_cache.face_count = 0;
  if (system == 0) {
    for (const auto& tree : lev->tfrag_trees[0]) {
      if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
        continue;
      }
      const auto& verts = tree.unpacked.vertices;
      for (const auto& draw : tree.draws) {
        if (draw.tree_tex_id < 0 || (u32)draw.tree_tex_id != tex) {
          continue;
        }
        u64 count = 0;
        for (const auto& g : draw.vis_groups) {
          count += g.num_inds;
        }
        walk_tris(tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                  tree.use_strips, verts.size(),
                  [&](u32 a, u32 b, u32 c) { try_emit_face(verts, a, b, c, bb); });
      }
    }
  } else {
    for (const auto& tree : lev->tie_trees[0]) {
      const auto& verts = tree.unpacked.vertices;
      // static_draws only — instanced_wind_draws live in prototype-local space (their positions
      // are not world coordinates), exactly why tess_sign drops them from its face universe too.
      for (const auto& draw : tree.static_draws) {
        if (draw.tree_tex_id < 0 || (u32)draw.tree_tex_id != tex) {
          continue;
        }
        u64 count = 0;
        for (const auto& g : draw.vis_groups) {
          count += g.num_inds;
        }
        walk_tris(tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                  tree.use_strips, verts.size(),
                  [&](u32 a, u32 b, u32 c) { try_emit_face(verts, a, b, c, bb); });
      }
    }
  }
  lg::info("[mb-gizmos] built {} normal arrows (system={} tex={} level={})", g_cache.face_count,
           system, tex, lev->level_name);
}

}  // namespace

void render(const tfrag3::Level* lev,
            int system,
            const char* level_name,
            const GoalBackgroundCameraData& camera,
            SharedRenderState* render_state,
            ScopedProfilerNode& prof) {
  auto& s = Gfx::g_global_settings;
  // Callers already gate on (mb_target_active && mb_gizmos_target); re-check here so the module
  // is safe standalone, then filter to the targeted system + level.
  if (!s.mb_target_active || !s.mb_gizmos_target) {
    return;
  }
  if (!lev || system != s.mb_target_system ||
      std::strncmp(level_name, s.mb_target_level, sizeof(s.mb_target_level)) != 0) {
    return;
  }

  // BUILD (cached): key = (level, system, tex, bbox). The Level pointer is part of the key so an
  // fr3 reload under the same name rebuilds against the fresh unpacked arrays.
  if (!g_cache.valid || g_cache.lev != lev || g_cache.system != system ||
      g_cache.tex != s.mb_target_tex ||
      std::memcmp(g_cache.bbox, s.mb_target_bbox, sizeof(g_cache.bbox)) != 0 ||
      std::strncmp(g_cache.level, s.mb_target_level, sizeof(g_cache.level)) != 0) {
    build(lev, system, s.mb_target_tex, s.mb_target_bbox);
    g_cache.lev = lev;
    g_cache.system = system;
    g_cache.tex = s.mb_target_tex;
    std::memcpy(g_cache.bbox, s.mb_target_bbox, sizeof(g_cache.bbox));
    std::memcpy(g_cache.level, s.mb_target_level, sizeof(g_cache.level));
    g_cache.valid = true;
    s.mb_ctr_gizmo_faces = g_cache.face_count;  // BUILT count (set, not summed)

    // own VAO/VBO, uploaded on rebuild only.
    if (g_cache.vao == 0) {
      glGenVertexArrays(1, &g_cache.vao);
      glBindVertexArray(g_cache.vao);
      glGenBuffers(1, &g_cache.vbo);
      glBindBuffer(GL_ARRAY_BUFFER, g_cache.vbo);
      glEnableVertexAttribArray(0);
      glEnableVertexAttribArray(1);
      glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(GizmoVertex),
                            (void*)offsetof(GizmoVertex, position));
      glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GizmoVertex),
                            (void*)offsetof(GizmoVertex, rgba));
      glBindVertexArray(0);
    }
    glBindBuffer(GL_ARRAY_BUFFER, g_cache.vbo);
    g_cache.vbo_size = g_cache.verts.size() * sizeof(GizmoVertex);
    glBufferData(GL_ARRAY_BUFFER, g_cache.vbo_size,
                 g_cache.verts.empty() ? nullptr : g_cache.verts.data(), GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
  }

  if (g_cache.verts.empty()) {
    return;  // nothing in the bbox — no pass drawn, counter untouched
  }

  // RENDER: TFRAG3_NO_TEX with the exact uniform/camera setup render_tree_cull_debug uses.
  const auto& sh = render_state->shaders[ShaderId::TFRAG3_NO_TEX];
  sh.activate();
  glUniformMatrix4fv(glGetUniformLocation(sh.id(), "camera"), 1, GL_FALSE,
                     camera.camera[0].data());
  glUniform4f(glGetUniformLocation(sh.id(), "hvdf_offset"), camera.hvdf_off[0],
              camera.hvdf_off[1], camera.hvdf_off[2], camera.hvdf_off[3]);
  glUniform1f(glGetUniformLocation(sh.id(), "fog_constant"), camera.fog.x());

  // depth test DISABLED for the pass (arrows must read through the surface they pierce); no depth
  // writes, no blending (opaque 2px lines). Save + restore what we touch.
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDepthMask(GL_FALSE);
  // glLineWidth(2) guarded for GLES limits (ALIASED_LINE_WIDTH_RANGE may cap at 1 on some
  // drivers; clamping keeps the call GL-error free everywhere).
  float line_range[2] = {1.f, 1.f};
  glGetFloatv(GL_ALIASED_LINE_WIDTH_RANGE, line_range);
  const float line_w = 2.f < line_range[1] ? 2.f : line_range[1];
  glLineWidth(line_w < line_range[0] ? line_range[0] : line_w);

  glBindVertexArray(g_cache.vao);
  glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.verts.size());
  prof.add_draw_call();
  glBindVertexArray(0);
  s.mb_ctr_gizmo_draws++;

  // restore
  glLineWidth(1.f);
  if (prev_depth_test) {
    glEnable(GL_DEPTH_TEST);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  glDepthMask(prev_depth_mask);
}

}  // namespace mb_gizmos
