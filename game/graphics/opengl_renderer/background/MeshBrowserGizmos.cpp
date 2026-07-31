#include "MeshBrowserGizmos.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <unordered_map>
#include <vector>

#include "common/log/log.h"

namespace {

// Walk one draw's index range and hand every non-degenerate triangle to `emit(i0, i1, i2)`,
// EXACTLY like tools/tess_sign/main.cpp walk_tris (:1100-1163): UINT32_MAX restarts a strip, and
// within a strip the winding flips on odd steps as (b, a, vi) — the SAME order whose
// cross(p1-p0, p2-p0) the offline A_sign grader calls the stored winding's geometric normal.
// File-scope: shared by the mb_gizmos arrow build AND the mb_pick triangle ray-test below.
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

// Watertight-enough Moller-Trumbore, GOAL units. Returns t >= 0 along the (unit) ray or a
// negative value on miss. Backfaces DO count: the reticle must pick a wall whose winding is
// wrong — inverted-normal hunting is this browser's whole purpose. File-scope: ONE copy shared
// by the mb_pick sweep and the mb_gizmos hover test (they must agree exactly).
float ray_tri(const float* o,
              const float* d,
              const math::Vector3f& p0,
              const math::Vector3f& p1,
              const math::Vector3f& p2) {
  const math::Vector3f e1 = p1 - p0;
  const math::Vector3f e2 = p2 - p0;
  const math::Vector3f dv(d[0], d[1], d[2]);
  const math::Vector3f pv = dv.cross(e2);
  const float det = e1.dot(pv);
  if (std::fabs(det) < 1e-12f) {
    return -1.f;
  }
  const float inv = 1.f / det;
  const math::Vector3f tv(o[0] - p0.x(), o[1] - p0.y(), o[2] - p0.z());
  const float u = tv.dot(pv) * inv;
  if (u < -1e-4f || u > 1.0001f) {
    return -1.f;
  }
  const math::Vector3f qv = tv.cross(e1);
  const float v = dv.dot(qv) * inv;
  if (v < -1e-4f || u + v > 1.0001f) {
    return -1.f;
  }
  const float t = e2.dot(qv) * inv;
  return t >= 0.f ? t : -1.f;
}

}  // namespace

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
// V2.4 depth-tested pass: overlay geometry that lies EXACTLY on a surface (wireframe edges,
// hover/mark triangles, arrow bases) would z-fight its own mesh once the pass depth-tests
// against the scene. Lift it off the surface along the face normal by ~8 mm (GOAL units,
// 4096 = 1 m) — enough to clear depth-buffer precision at browse distances, far too small to
// misplace anything visually. The lift is DRAW-ONLY: Face records, hover identity and the JSONL
// export keep the exact vertices.
constexpr float kLift = 32.f;
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
  // V2.3 wireframe overlay + hover: 3 cyan edges per kept face, plus a Face record carrying the
  // triangle ordinal (SAME enumeration rule as the mb_pick sweep — count every emitted triangle
  // of the target texid's walk, fixed tree->draw order, 0-based) so a hover hit names the exact
  // polygon an offline tool can re-find.
  struct Face {
    float v[3][3];
    float nrm[3];
    int tri;
  };
  std::vector<GizmoVertex> edge_verts;
  std::vector<Face> faces;
  u32 face_count = 0;
  GLuint vao = 0;
  GLuint vbo = 0;
  size_t vbo_size = 0;  // bytes currently allocated in the VBO
  GLuint edge_vao = 0;
  GLuint edge_vbo = 0;
  GLuint hover_vao = 0;
  GLuint hover_vbo = 0;  // 3 verts, re-uploaded per frame while a hover hit exists
};
Cache g_cache;

// One face -> 2 GL_LINES segments (4 vertices): base -> base + 0.8*len*n in GREEN, then the tip
// -> base + len*n in RED, plus the 3 cyan wireframe edges + the Face record. `tri` is the
// triangle's ordinal (counted for EVERY emitted triangle of the texid walk, kept or not).
// Returns false when the face fails the bbox filter or the cap is hit.
bool try_emit_face(const std::vector<tfrag3::PreloadedVertex>& verts,
                   u32 i0,
                   u32 i1,
                   u32 i2,
                   const float* bb,
                   int tri) {
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
  // V2.4: lift draw-only geometry off the surface along n so the depth-tested pass does not
  // z-fight the mesh the overlay annotates (see kLift).
  const math::Vector3f lift = n * kLift;
  const math::Vector3f base = (p0 + p1 + p2) / 3.f + lift;
  const math::Vector3f knee = base + n * (0.8f * kArrowLen);
  const math::Vector3f tip = base + n * kArrowLen;
  const math::Vector4f green(0.f, 1.f, 0.f, 1.f);
  const math::Vector4f red(1.f, 0.f, 0.f, 1.f);
  g_cache.verts.push_back({base, green});
  g_cache.verts.push_back({knee, green});
  g_cache.verts.push_back({knee, red});
  g_cache.verts.push_back({tip, red});
  // V2.3 wireframe: the face's 3 edges in cyan (p0->p1, p1->p2, p2->p0), lifted like the arrows.
  const math::Vector4f cyan(0.f, 1.f, 1.f, 1.f);
  g_cache.edge_verts.push_back({p0 + lift, cyan});
  g_cache.edge_verts.push_back({p1 + lift, cyan});
  g_cache.edge_verts.push_back({p1 + lift, cyan});
  g_cache.edge_verts.push_back({p2 + lift, cyan});
  g_cache.edge_verts.push_back({p2 + lift, cyan});
  g_cache.edge_verts.push_back({p0 + lift, cyan});
  Cache::Face f;
  const math::Vector3f* ps[3] = {&p0, &p1, &p2};
  for (int i = 0; i < 3; i++) {
    for (int k = 0; k < 3; k++) {
      f.v[i][k] = (*ps[i])[k];
    }
    f.nrm[i] = n[i];
  }
  f.tri = tri;
  g_cache.faces.push_back(f);
  g_cache.face_count++;
  return true;
}

// Rebuild the arrow list for the current key. Walks geom 0 ONLY — one LOD, matching the offline
// mesh_index truth (walking every geo re-collects the same surface up to 3x — the exact duplicate
// trap the orient-authority pipeline hit).
void build(const tfrag3::Level* lev, int system, u32 tex, const float* bb) {
  g_cache.verts.clear();
  g_cache.edge_verts.clear();
  g_cache.faces.clear();
  g_cache.face_count = 0;
  // V2.3: the triangle ORDINAL of this texid — the count of triangles EMITTED so far by
  // walk_tris over the fixed tree->draw order, incremented for EVERY emitted triangle (kept by
  // the bbox filter or not). Identical to the mb_pick sweep's per-texid counter (no pruning
  // here, so a plain running counter matches exactly).
  int ordinal = 0;
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
                  [&](u32 a, u32 b, u32 c) { try_emit_face(verts, a, b, c, bb, ordinal++); });
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
                  [&](u32 a, u32 b, u32 c) { try_emit_face(verts, a, b, c, bb, ordinal++); });
      }
    }
  }
  lg::info("[mb-gizmos] built {} normal arrows (system={} tex={} level={})", g_cache.face_count,
           system, tex, lev->level_name);
}

// Lazily create a (vao, vbo) pair with the GizmoVertex layout (positions/rgba at locations 0/1
// of TFRAG3_NO_TEX — same as the arrow pass).
void ensure_vao(GLuint* vao, GLuint* vbo) {
  if (*vao != 0) {
    return;
  }
  glGenVertexArrays(1, vao);
  glBindVertexArray(*vao);
  glGenBuffers(1, vbo);
  glBindBuffer(GL_ARRAY_BUFFER, *vbo);
  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(GizmoVertex),
                        (void*)offsetof(GizmoVertex, position));
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GizmoVertex),
                        (void*)offsetof(GizmoVertex, rgba));
  glBindVertexArray(0);
}

}  // namespace

void render(const tfrag3::Level* lev,
            int system,
            const char* level_name,
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

    // own VAO/VBO pairs, uploaded on rebuild only (arrows + wireframe edges).
    ensure_vao(&g_cache.vao, &g_cache.vbo);
    ensure_vao(&g_cache.edge_vao, &g_cache.edge_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, g_cache.vbo);
    g_cache.vbo_size = g_cache.verts.size() * sizeof(GizmoVertex);
    glBufferData(GL_ARRAY_BUFFER, g_cache.vbo_size,
                 g_cache.verts.empty() ? nullptr : g_cache.verts.data(), GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, g_cache.edge_vbo);
    glBufferData(GL_ARRAY_BUFFER, g_cache.edge_verts.size() * sizeof(GizmoVertex),
                 g_cache.edge_verts.empty() ? nullptr : g_cache.edge_verts.data(), GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
  }

  if (g_cache.verts.empty()) {
    return;  // nothing in the bbox — no pass drawn, counter untouched
  }

  // RENDER: TFRAG3_NO_TEX (PS2-style Q = fog/w transform). The camera uniforms come from
  // render_state->camera_matrix/camera_hvdf_off/camera_fog — the canonical trio every WORKING
  // PS2-style debug renderer uses (CollideMeshRenderer.cpp:255-265, GrassRenderer.cpp:1033).
  // v2.2 root cause of "gizmos invisible with prims>0": this pass (like the never-ported
  // render_tree_cull_debug idiom it copied) read GoalBackgroundCameraData::fog, which the modern
  // draw path leaves ~0 (it bakes fog into pc_camera instead, background_common.cpp:410-453) —
  // Q = fog/w ~ 0 collapsed every arrow vertex off-screen. Desktop-reproduced: NDC (13.2,-3.2)
  // w<0 from the exact uniform values; render_state trio projects the same vertex on-screen.
  const auto& sh = render_state->shaders[ShaderId::TFRAG3_NO_TEX];
  sh.activate();
  // SIGN CONVENTION (v2.2 root cause of "gizmos invisible with prims>0"): this project's
  // camera_matrix feeds the Q pipeline NEGATED — grass.vert world_to_clip computes
  // -(M3 + M0*x + M1*y + M2*z) and is the working PS2-style path; tfrag3_no_tex.vert (stock,
  // never exercised since the port) computes +(M...). With +M every in-front vertex gets
  // clip w < 0 and GL rejects 100% of the primitives: emitted, no GL error, zero pixels —
  // measured on desktop by full-vertex census: +M = 0 of 33216 in-frustum, -M = 7037.
  // Upload the negated matrix so the unchanged stock shader computes the grass convention.
  math::Vector4f neg_cam[4];
  for (int i = 0; i < 4; i++) {
    neg_cam[i] = render_state->camera_matrix[i] * -1.f;
  }
  glUniformMatrix4fv(glGetUniformLocation(sh.id(), "camera"), 1, GL_FALSE, neg_cam[0].data());
  glUniform4f(glGetUniformLocation(sh.id(), "hvdf_offset"), render_state->camera_hvdf_off[0],
              render_state->camera_hvdf_off[1], render_state->camera_hvdf_off[2],
              render_state->camera_hvdf_off[3]);
  glUniform1f(glGetUniformLocation(sh.id(), "fog_constant"), render_state->camera_fog.x());

  // V2.4 (owner: "affichés comme s'il n'y avait pas de mesh devant... on sait pas de quel côté
  // ils sortent"): the pass now DEPTH-TESTS against the scene depth buffer — the one already
  // bound to the current draw FBO, filled by every bucket drawn before this point (the gizmo
  // pass runs at the END of the target system's own renderer, so the target level's background
  // geometry is always in it). Two sub-passes:
  //   1. VISIBLE (GL_GEQUAL — this project's Q pipeline writes PS2-style REVERSED Z, larger =
  //      closer; every scene renderer tests GEQUAL: TFragment.cpp:1685, Merc2.cpp:1697,
  //      Shadow2.cpp:469. LEQUAL here would invert the whole feature — measured on desktop:
  //      wall-occluded fireplace arrows "passed" 8016 samples under LEQUAL): full-brightness
  //      arrows/wireframe — the unoccluded parts;
  //   2. OCCLUDED (GL_LESS, the exact complement + constant-alpha 25% blend): the same VBOs
  //      redrawn dim, so the part of a normal that dives BEHIND geometry stays readable but is
  //      unmistakably "behind".
  // Depth writes stay off (the overlay must never occlude the scene or itself). Sub-pass 1 runs
  // inside a GL_SAMPLES_PASSED occlusion query (GLES: ANY_SAMPLES -> 0/1) whose result feeds
  // mb_cur_gizmo_occ — the code-level proof that occlusion actually culls samples.
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  GLint prev_depth_func = GL_LESS;
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDisable(GL_BLEND);
  glDepthMask(GL_FALSE);
  // glLineWidth(2) guarded for GLES limits (ALIASED_LINE_WIDTH_RANGE may cap at 1 on some
  // drivers; clamping keeps the call GL-error free everywhere).
  float line_range[2] = {1.f, 1.f};
  glGetFloatv(GL_ALIASED_LINE_WIDTH_RANGE, line_range);
  const float line_w = 2.f < line_range[1] ? 2.f : line_range[1];
  glLineWidth(line_w < line_range[0] ? line_range[0] : line_w);

  // V2.2 (owner: "les gizmos ne s'affichent pas" while the prim counter read >0 — an emission
  // counter cannot tell a draw that LANDED from one that vanished into a bad GL state). Proof at
  // the framebuffer: read back a centre band of the CURRENT draw framebuffer before and after the
  // gizmo draw and count the pixels that changed — mb_cur_gizmo_px. The freecam reticle centres
  // the target, so the arrows project into this band. Debug-only cost, paid solely while the
  // gizmo toggle is ON. The Android game FBO is single-sampled (android_opengl_renderer.cpp
  // make_fbo, "msaa stripped"), so glReadPixels is legal there; on an MSAA desktop FBO the read
  // errors out and the counter just stays 0 (the state dump below still reports the draw state).
  GLint vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_VIEWPORT, vp);
  const int band_w = std::min(vp[2], 256), band_h = std::min(vp[3], 256);
  const int band_x = vp[0] + (vp[2] - band_w) / 2, band_y = vp[1] + (vp[3] - band_h) / 2;
  static std::vector<u8> s_pre, s_post;
  bool band_ok = band_w > 0 && band_h > 0;
  if (band_ok) {
    s_pre.resize((size_t)band_w * band_h * 4);
    s_post.resize((size_t)band_w * band_h * 4);
    while (glGetError() != GL_NO_ERROR) {
    }
    glReadPixels(band_x, band_y, band_w, band_h, GL_RGBA, GL_UNSIGNED_BYTE, s_pre.data());
    band_ok = glGetError() == GL_NO_ERROR;
  }

  // V2.4 occlusion query around the VISIBLE sub-pass: ping-pong two query objects so the result
  // read never blocks the pipeline (we read the OTHER query's result, one gizmo pass late —
  // plenty for evidence counters).
#ifdef GL_SAMPLES_PASSED
  constexpr GLenum kOccTarget = GL_SAMPLES_PASSED;  // desktop GL: a real sample count
#else
  constexpr GLenum kOccTarget = GL_ANY_SAMPLES_PASSED;  // GLES: boolean 0/1
#endif
  static GLuint s_occ_q[2] = {0, 0};
  static bool s_occ_inflight[2] = {false, false};
  static int s_occ_i = 0;
  if (s_occ_q[0] == 0) {
    glGenQueries(2, s_occ_q);
  }
  const int prev_q = 1 - s_occ_i;
  if (s_occ_inflight[prev_q]) {
    GLuint avail = 0;
    glGetQueryObjectuiv(s_occ_q[prev_q], GL_QUERY_RESULT_AVAILABLE, &avail);
    if (avail) {
      GLuint samples = 0;
      glGetQueryObjectuiv(s_occ_q[prev_q], GL_QUERY_RESULT, &samples);
      s.mb_cur_gizmo_occ += samples;
      s_occ_inflight[prev_q] = false;
    }
  }
  const bool occ_this_pass = !s_occ_inflight[s_occ_i];
  if (occ_this_pass) {
    glBeginQuery(kOccTarget, s_occ_q[s_occ_i]);
  }

  glBindVertexArray(g_cache.vao);
  glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.verts.size());
  prof.add_draw_call();
  glBindVertexArray(0);
  s.mb_ctr_gizmo_draws++;
  // V2.1 per-frame proof: line primitives ACTUALLY submitted this frame (2 verts per line).
  s.mb_cur_gizmo_prims += (u32)(g_cache.verts.size() / 2);

  // V2.3 WIREFRAME overlay: the kept faces' edges in cyan, same program/uniforms/depth state
  // as the arrows.
  if (!g_cache.edge_verts.empty()) {
    glBindVertexArray(g_cache.edge_vao);
    glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.edge_verts.size());
    prof.add_draw_call();
    glBindVertexArray(0);
    s.mb_cur_wire += (u32)(g_cache.edge_verts.size() / 2);
  }

  if (occ_this_pass) {
    glEndQuery(kOccTarget);
    s_occ_inflight[s_occ_i] = true;
    s_occ_i = 1 - s_occ_i;
  }

  // V2.4 OCCLUDED sub-pass: redraw arrows + wireframe where they FAILED the scene depth test
  // (GL_LESS on the same lifted vertices selects exactly the fragments pass 1 rejected under
  // the reversed-Z GEQUAL convention), dimmed to 25% by constant-alpha blending — the vertex
  // colors and VBOs are untouched, only the blend stage attenuates. Not counted in the
  // prim/wire counters (same primitives, second style pass).
  glDepthFunc(GL_LESS);
  glEnable(GL_BLEND);
  glBlendColor(0.f, 0.f, 0.f, 0.25f);
  glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
  glBindVertexArray(g_cache.vao);
  glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.verts.size());
  prof.add_draw_call();
  glBindVertexArray(0);
  if (!g_cache.edge_verts.empty()) {
    glBindVertexArray(g_cache.edge_vao);
    glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.edge_verts.size());
    prof.add_draw_call();
    glBindVertexArray(0);
  }
  glDisable(GL_BLEND);
  glDepthFunc(GL_GEQUAL);  // back to the visible convention for the hover highlight below

  // V2.3 HOVER highlight: ray-test the GOAL-pushed hover ray against the cached faces (the SAME
  // ray_tri the pick sweep uses); the nearest face is drawn as a filled yellow triangle so the
  // owner SEES the targeted polygon, and its identity is published through the seqlock (this
  // render thread is the only writer).
  if (s.mb_hover_on.load(std::memory_order_acquire) == 1) {
    const Cache::Face* best = nullptr;
    float best_t = -1.f;
    for (const auto& f : g_cache.faces) {
      const math::Vector3f p0(f.v[0][0], f.v[0][1], f.v[0][2]);
      const math::Vector3f p1(f.v[1][0], f.v[1][1], f.v[1][2]);
      const math::Vector3f p2(f.v[2][0], f.v[2][1], f.v[2][2]);
      const float t = ray_tri(s.mb_hover_ray_o, s.mb_hover_ray_d, p0, p1, p2);
      if (t >= 0.f && (best_t < 0.f || t < best_t)) {
        best_t = t;
        best = &f;
      }
    }
    if (best) {
      ensure_vao(&g_cache.hover_vao, &g_cache.hover_vbo);
      const math::Vector4f yellow(1.f, 1.f, 0.f, 1.f);
      const math::Vector3f hlift =
          math::Vector3f(best->nrm[0], best->nrm[1], best->nrm[2]) * kLift;
      GizmoVertex tri_verts[3];
      for (int i = 0; i < 3; i++) {
        tri_verts[i] = {math::Vector3f(best->v[i][0], best->v[i][1], best->v[i][2]) + hlift,
                        yellow};
      }
      glBindBuffer(GL_ARRAY_BUFFER, g_cache.hover_vbo);
      glBufferData(GL_ARRAY_BUFFER, sizeof(tri_verts), tri_verts, GL_DYNAMIC_DRAW);
      glBindBuffer(GL_ARRAY_BUFFER, 0);
      glBindVertexArray(g_cache.hover_vao);
      glDrawArrays(GL_TRIANGLES, 0, 3);
      prof.add_draw_call();
      glBindVertexArray(0);
    }
    // publish (seqlock: odd while writing, back to even after — GOAL retries on odd/mismatch)
    const u32 sq = s.mb_hover_seq.load(std::memory_order_relaxed);
    s.mb_hover_seq.store(sq + 1, std::memory_order_release);
    if (best) {
      s.mb_hover_tri = best->tri;
      s.mb_hover_texid = g_cache.tex;
      std::memcpy(s.mb_hover_v, best->v, sizeof(s.mb_hover_v));
      std::memcpy(s.mb_hover_nrm, best->nrm, sizeof(s.mb_hover_nrm));
    } else {
      s.mb_hover_tri = -1;
    }
    s.mb_hover_seq.store(sq + 2, std::memory_order_release);
  }

  const GLenum post_draw_err = glGetError();
  if (band_ok) {
    glReadPixels(band_x, band_y, band_w, band_h, GL_RGBA, GL_UNSIGNED_BYTE, s_post.data());
    if (glGetError() == GL_NO_ERROR) {
      u32 changed = 0;
      for (size_t i = 0; i < s_pre.size(); i += 4) {
        if (s_pre[i] != s_post[i] || s_pre[i + 1] != s_post[i + 1] ||
            s_pre[i + 2] != s_post[i + 2]) {
          changed++;
        }
      }
      s.mb_cur_gizmo_px += changed;
    }
  }

  // V2.2 one-shot GL-state dump per gizmo build (supervisor: if prims > 0 with nothing on screen,
  // name the state of the draw — program/FBO/viewport/scissor/colormask/depth — not its emission).
  {
    static u64 s_last_dump_build = ~0ull;
    static u32 s_dump_countdown = 0;
    const u64 build_key = ((u64)g_cache.face_count << 32) ^ (u64)(uintptr_t)g_cache.lev;
    bool do_dump = false;
    if (s_last_dump_build != build_key) {
      s_last_dump_build = build_key;
      s_dump_countdown = 150;  // re-dump ~2.5 s later: names the steady-state values too (the
                               // first draw after a build can precede this frame's pc-data fill)
      do_dump = true;
    } else if (s_dump_countdown > 0 && --s_dump_countdown == 0) {
      do_dump = true;
    }
    if (do_dump) {
      GLint prog = 0, fbo = 0, scis = 0;
      GLboolean cmask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
      GLint scis_box[4] = {0, 0, 0, 0};
      glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
      glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
      scis = glIsEnabled(GL_SCISSOR_TEST);
      glGetIntegerv(GL_SCISSOR_BOX, scis_box);
      glGetBooleanv(GL_COLOR_WRITEMASK, cmask);
      GLint linked = 0;
      if (prog) {
        glGetProgramiv(prog, GL_LINK_STATUS, &linked);
      }
      lg::info(
          "[mb-gizmos] draw state: prog={} linked={} fbo={} vp={},{},{}x{} scissor={} "
          "box={},{},{}x{} colormask={}{}{}{} err={} verts={} band_ok={}",
          prog, linked, fbo, vp[0], vp[1], vp[2], vp[3], scis, scis_box[0], scis_box[1],
          scis_box[2], scis_box[3], (int)cmask[0], (int)cmask[1], (int)cmask[2], (int)cmask[3],
          (u32)post_draw_err, g_cache.verts.size(), (int)band_ok);
      // v2.2 px=0 forensics: replicate tfrag3_no_tex.vert's EXACT transform on the CPU for the
      // first arrow vertex with the EXACT uniform values just uploaded, and log the resulting
      // NDC. Inside [-1,1] with w>0 => the vertex reaches the raster stage and the failure is
      // state-side; outside => the transform/uniform path is the failure. jak1 tokens:
      // HEIGHT_SCALE=1.0, SCISSOR_ADJUST=512/448 (Shader.cpp:357-359).
      if (!g_cache.verts.empty()) {
        const auto& cm = render_state->camera_matrix;
        const auto& hv = render_state->camera_hvdf_off;
        const auto& fg = render_state->camera_fog;
        // Full-vertex frustum census under the two PS2-style conventions (+M = stock
        // tfrag3_no_tex.vert, -M = grass.vert world_to_clip, the working Q-pipeline user).
        // If NEITHER puts a meaningful vertex count in-frustum while the camera stands ON the
        // 460 m beach the arrows cover, the failure is the transform inputs; if -M does, the
        // failure is the shader-side sign.
        auto census = [&](float sgn) {
          int in = 0;
          for (const auto& v : g_cache.verts) {
            const auto& p = v.position;
            math::Vector4f t =
                (cm[3] + cm[0] * p.x() + cm[1] * p.y() + cm[2] * p.z()) * sgn;
            const float w = t.w();
            if (w <= 0.f) {
              continue;  // OpenGL clips w<=0 outright
            }
            const float q = fg.x() / w;
            float x = ((t.x() * q + hv[0] - 2048.f) / 256.f) * w;
            float y = ((t.y() * q + hv[1] - 2048.f) / -128.f) * w * (512.f / 448.f);
            float z = ((t.z() * q + hv[2]) / 8388608.f - 1.f) * w;
            if (x >= -w && x <= w && y >= -w && y <= w && z >= -w && z <= w) {
              in++;
            }
          }
          return in;
        };
        // actual uniform values as the GL program holds them right now (delivery check)
        float u_cam[16] = {0}, u_fog = -1.f, u_hvdf[4] = {0};
        const GLint lc = glGetUniformLocation(sh.id(), "camera");
        const GLint lf = glGetUniformLocation(sh.id(), "fog_constant");
        const GLint lh = glGetUniformLocation(sh.id(), "hvdf_offset");
        if (lc >= 0) {
          glGetUniformfv(sh.id(), lc, u_cam);
        }
        if (lf >= 0) {
          glGetUniformfv(sh.id(), lf, &u_fog);
        }
        if (lh >= 0) {
          glGetUniformfv(sh.id(), lh, u_hvdf);
        }
        lg::info("[mb-gizmos] census in-frustum: +M={} -M={} of {} | uniforms: loc(c/f/h)={}/{}/{} "
                 "fog={:.6f} hvdf=({:.1f},{:.1f},{:.1f},{:.1f}) cam_col3=({:.6f},{:.6f},{:.6f},"
                 "{:.6f}) rs_fog=({:.6f},{:.3f},{:.3f},{:.3f}) campos=({:.1f},{:.1f},{:.1f})",
                 census(1.f), census(-1.f), (int)g_cache.verts.size(), lc, lf, lh, u_fog,
                 u_hvdf[0], u_hvdf[1], u_hvdf[2], u_hvdf[3], u_cam[12], u_cam[13], u_cam[14],
                 u_cam[15], fg.x(), fg.y(), fg.z(), fg.w(), render_state->camera_pos[0] / 4096.f,
                 render_state->camera_pos[1] / 4096.f, render_state->camera_pos[2] / 4096.f);
      }
    }
  }

  // restore
  glLineWidth(1.f);
  glDepthFunc((GLenum)prev_depth_func);
  if (!prev_depth_test) {
    glDisable(GL_DEPTH_TEST);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }
  glDepthMask(prev_depth_mask);
}

void render_marks(SharedRenderState* render_state, ScopedProfilerNode& prof) {
  auto& s = Gfx::g_global_settings;
  if (s.mb_marks_active.load(std::memory_order_relaxed) <= 0) {
    return;
  }
  // once per frame: several bucket renderers (tfrag l0/l1, tie l0/l1, trans variants) reach this
  // call site; the first one after a counter flip draws ALL active marks (they carry world-space
  // vertices, so no level data is needed), the rest no-op. This is what makes the V2.4 proof
  // exact: mb_frame_marked == active marks, drawn exactly once each.
  static u32 s_last_frame = 0xffffffffu;
  if (s_last_frame == s.mb_frame_no) {
    return;
  }
  s_last_frame = s.mb_frame_no;

  static std::vector<GizmoVertex> verts;
  verts.clear();
  // MARKED style: filled semi-transparent ORANGE-RED — deliberately distinct from the yellow
  // hover fill and from the green/red arrows.
  const math::Vector4f orange(1.f, 0.30f, 0.f, 0.55f);
  int n = 0;
  {
    std::lock_guard<std::mutex> lk(s.mb_marks_mu);
    n = s.mb_marks_n;
    for (int i = 0; i < n; i++) {
      const auto& m = s.mb_marks_store[i];
      const math::Vector3f lift = math::Vector3f(m.nrm[0], m.nrm[1], m.nrm[2]) * kLift;
      for (int k = 0; k < 3; k++) {
        verts.push_back({math::Vector3f(m.v[k][0], m.v[k][1], m.v[k][2]) + lift, orange});
      }
    }
  }
  if (verts.empty()) {
    return;
  }

  // same program + camera trio + negated-matrix convention as the gizmo pass above.
  const auto& sh = render_state->shaders[ShaderId::TFRAG3_NO_TEX];
  sh.activate();
  math::Vector4f neg_cam[4];
  for (int i = 0; i < 4; i++) {
    neg_cam[i] = render_state->camera_matrix[i] * -1.f;
  }
  glUniformMatrix4fv(glGetUniformLocation(sh.id(), "camera"), 1, GL_FALSE, neg_cam[0].data());
  glUniform4f(glGetUniformLocation(sh.id(), "hvdf_offset"), render_state->camera_hvdf_off[0],
              render_state->camera_hvdf_off[1], render_state->camera_hvdf_off[2],
              render_state->camera_hvdf_off[3]);
  glUniform1f(glGetUniformLocation(sh.id(), "fog_constant"), render_state->camera_fog.x());

  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  GLint prev_depth_func = GL_LESS;
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);  // reversed-Z scene convention (see the gizmo pass above)
  glDepthMask(GL_FALSE);
  glEnable(GL_BLEND);

  static GLuint s_vao = 0, s_vbo = 0;
  ensure_vao(&s_vao, &s_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, s_vbo);
  glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(GizmoVertex), verts.data(),
               GL_DYNAMIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(s_vao);
  // VISIBLE sub-pass: vertex alpha (0.55) over the scene.
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArrays(GL_TRIANGLES, 0, (GLsizei)verts.size());
  prof.add_draw_call();
  // OCCLUDED sub-pass: like the gizmos, a mark behind geometry stays readable but clearly
  // attenuated (constant-alpha 20%).
  glDepthFunc(GL_LESS);
  glBlendColor(0.f, 0.f, 0.f, 0.20f);
  glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
  glDrawArrays(GL_TRIANGLES, 0, (GLsizei)verts.size());
  prof.add_draw_call();
  glBindVertexArray(0);

  // per-frame proof counter: marked triangles DRAWN == active marks.
  s.mb_cur_marked += (u32)n;

  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDepthFunc((GLenum)prev_depth_func);
  if (!prev_depth_test) {
    glDisable(GL_DEPTH_TEST);
  }
  if (!prev_blend) {
    glDisable(GL_BLEND);
  }
  glDepthMask(prev_depth_mask);
}

}  // namespace mb_gizmos

namespace mb_pick {

namespace {

// Whole-sweep face budget: sweeping ALL rendered geometry of a level must not hitch the GL
// thread unboundedly. 8M faces is far above any jak1 level's real triangle count; hitting it
// means something is wrong, so warn (once per sweep) instead of silently truncating quietly.
constexpr u64 kMaxSweepFaces = 8000000;

// V2.3 render-thread-only sweep guard: multiple bucket-renderer instances can call raytest for
// the same (serial, lev, system) in one frame — sweep each combination once.
struct SweepDone {
  u32 serial = 0;
  const void* lev = nullptr;
  int sys = -1;
};
SweepDone g_done_set[8];
int g_done_n = 0;
u32 g_done_serial = 0;

// PER-DRAW AABB PRUNE CACHE, keyed by (lev pointer, system): one box + DECODED triangle count
// per draw, in the same draw-encounter order as the sweep. Built on the first sweep of that
// (lev, system); later sweeps slab-test each draw's box and skip misses — adding the cached
// triangle count to the ordinal counter so the enumeration stays EXACT (see the rule below).
struct DrawBox {
  float bb[6];  // lo xyz / hi xyz, GOAL units
  u32 tris;     // triangles walk_tris EMITS for this draw
};
struct PruneEntry {
  const tfrag3::Level* lev = nullptr;
  int sys = -1;
  char name[16] = {0};  // level name too: a reloaded level can reuse a freed Level pointer
  std::vector<DrawBox> boxes;
};
std::vector<PruneEntry> g_prune;

// Standard per-axis slab test against a GOAL-unit AABB; rejects boxes entirely behind the ray
// (tmax < 0). Same idiom the old kmachine candidate pass used.
bool slab_hit(const float* o, const float* d, const float* bb) {
  float tmin = -std::numeric_limits<float>::max();
  float tmax = std::numeric_limits<float>::max();
  for (int a = 0; a < 3; a++) {
    if (std::fabs(d[a]) < 1e-9f) {
      if (o[a] < bb[a] || o[a] > bb[a + 3]) {
        return false;
      }
    } else {
      float t1 = (bb[a] - o[a]) / d[a];
      float t2 = (bb[a + 3] - o[a]) / d[a];
      if (t1 > t2) {
        std::swap(t1, t2);
      }
      tmin = std::max(tmin, t1);
      tmax = std::min(tmax, t2);
    }
  }
  return tmax >= std::max(tmin, 0.f);
}

// Insert a hit into the shared output array: ascending t, DEDUPED by (sys, texid, lvl) — a key
// match is replaced only by a strictly smaller t; overflow beyond MB_PICK_MAX is dropped.
void insert_hit(GfxGlobalSettings& s, const GfxGlobalSettings::MbRayHit& h) {
  auto* arr = s.mb_pick_hits_out;
  int n = s.mb_pick_hit_n;
  for (int i = 0; i < n; i++) {
    if (arr[i].sys == h.sys && arr[i].texid == h.texid &&
        std::strncmp(arr[i].lvl, h.lvl, sizeof(arr[i].lvl)) == 0) {
      if (h.t >= arr[i].t) {
        return;  // existing hit for this key is nearer (or equal)
      }
      // replace: remove the old slot, then re-insert in t order below
      std::memmove(&arr[i], &arr[i + 1],
                   (size_t)(n - 1 - i) * sizeof(GfxGlobalSettings::MbRayHit));
      n--;
      break;
    }
  }
  if (n >= GfxGlobalSettings::MB_PICK_MAX && h.t >= arr[n - 1].t) {
    s.mb_pick_hit_n = n;
    return;  // full and farther than everything kept
  }
  int pos = n;
  while (pos > 0 && arr[pos - 1].t > h.t) {
    pos--;
  }
  const int keep = std::min(n, GfxGlobalSettings::MB_PICK_MAX - 1);
  if (pos < keep) {
    std::memmove(&arr[pos + 1], &arr[pos],
                 (size_t)(keep - pos) * sizeof(GfxGlobalSettings::MbRayHit));
  }
  if (pos < GfxGlobalSettings::MB_PICK_MAX) {
    arr[pos] = h;
  }
  s.mb_pick_hit_n = std::min(n + 1, (int)GfxGlobalSettings::MB_PICK_MAX);
}

}  // namespace

// V2.3 EXACT pick sweep: EVERY draw of an INDEXED texid is triangle-tested (no more top-16 AABB
// candidate cap — the owner-reported defect was a visible mesh ranking >16 in AABB order and
// never getting tested; the indexed-texid scope matches the offline reference sweep, which only
// knows displaceable materials). TRIANGLE ENUMERATION RULE (reproducible offline): for each (system, level,
// texid), the ordinal is the 0-based count of triangles EMITTED so far by walk_tris across the
// fixed tree->draw iteration order over draws with that tree_tex_id — every emitted triangle
// increments its texid's counter, including ones that miss the ray. A draw pruned by the AABB
// cache still advances the counter by its cached DECODED triangle count, so ordinals never
// shift.
void raytest(const tfrag3::Level* lev, int system, const char* level_name) {
  auto& s = Gfx::g_global_settings;
  if (!lev || !pending()) {
    return;
  }
  // acquire pairs with the GOAL thread's release store of mb_pick_serial: the ray is fully
  // visible from here on.
  const u32 serial = s.mb_pick_serial.load(std::memory_order_acquire);
  // Sweep only while ARMED: the flip that arms also resets mb_pick_hit_n, so contributing in
  // the request's first (partial) frame would be wiped — the armed frame is the one COMPLETE
  // frame whose results get published (see gfx.h mb_flip_frame_counters).
  if (s.mb_pick_arm != serial) {
    return;
  }
  if (serial != g_done_serial) {
    g_done_serial = serial;
    g_done_n = 0;
  }
  for (int i = 0; i < g_done_n; i++) {
    if (g_done_set[i].lev == lev && g_done_set[i].sys == system) {
      return;  // another bucket instance already swept this (serial, lev, system)
    }
  }
  if (g_done_n < (int)(sizeof(g_done_set) / sizeof(g_done_set[0]))) {
    g_done_set[g_done_n++] = {serial, lev, system};
  }

  // Browsable-texid filter (published with the ray): only draws whose tree_tex_id is INDEXED for
  // this level+system may be tested — the mesh_index holds only displaceable materials, and a
  // non-indexed nearest hit would be unresolvable (and could evict every browsable hit from the
  // 16 dedupe slots). No matching filter slot = level not in the pick scope: nothing to sweep.
  int flt_slot = -1;
  for (int sl = 0; sl < 2; sl++) {
    if (s.mb_pick_flt_lvl[sl][0] != '\0' &&
        std::strncmp(level_name, s.mb_pick_flt_lvl[sl], sizeof(s.mb_pick_flt_lvl[sl])) == 0) {
      flt_slot = sl;
      break;
    }
  }
  if (flt_slot < 0) {
    return;
  }
  const u32* flt_tex = s.mb_pick_flt_tex[flt_slot][system];
  const int flt_n = s.mb_pick_flt_n[flt_slot][system];

  // find (or start building) the prune cache for this (lev, name, system) — the name is part of
  // the key because a reloaded level can reuse a freed Level pointer
  PruneEntry* pe = nullptr;
  bool building = false;
  for (auto& e : g_prune) {
    if (e.lev == lev && e.sys == system) {
      if (std::strncmp(e.name, level_name, sizeof(e.name)) != 0) {
        e.boxes.clear();  // pointer reuse across a reload: rebuild this entry
        std::strncpy(e.name, level_name, sizeof(e.name) - 1);
        e.name[sizeof(e.name) - 1] = '\0';
        building = true;
      }
      pe = &e;
      break;
    }
  }
  if (!pe) {
    if (g_prune.size() >= 8) {
      g_prune.erase(g_prune.begin());  // oldest out; a stale lev pointer must never be reused
    }
    g_prune.emplace_back();
    pe = &g_prune.back();
    pe->lev = lev;
    pe->sys = system;
    std::strncpy(pe->name, level_name, sizeof(pe->name) - 1);
    pe->name[sizeof(pe->name) - 1] = '\0';
    building = true;
  }

  const float* o = s.mb_pick_ray_o;
  const float* d = s.mb_pick_ray_d;
  std::unordered_map<u32, int> ord;  // per-texid emitted-triangle ordinal counters (0-based)
  u64 faces = 0;
  int draws_tested = 0;
  size_t draw_i = 0;  // draw-encounter index into the prune cache
  bool warned = false;

  auto sweep_draw = [&](const std::vector<tfrag3::PreloadedVertex>& verts,
                        const std::vector<u32>& idx, u32 first, u64 count, bool strips,
                        s32 tree_tex) {
    // only INDEXED texids are testable; a filtered draw never advances an ordinal counter
    // (its texid is never reported) but DOES keep its prune-cache slot.
    const bool allowed =
        tree_tex >= 0 && std::binary_search(flt_tex, flt_tex + flt_n, (u32)tree_tex);
    if (!building) {
      if (draw_i >= pe->boxes.size()) {
        return;  // defensive: cache/draw-list mismatch — never index out of bounds
      }
      const DrawBox& db = pe->boxes[draw_i++];  // draw_i advances for EVERY draw
      if (!allowed) {
        return;
      }
      if (db.tris == 0 || !slab_hit(o, d, db.bb)) {
        ord[(u32)tree_tex] += (int)db.tris;  // pruned: ordinals still advance, DECODED count
        return;
      }
    }
    // building: EVERY draw (filtered or not) falls through here so its cache slot gets built —
    // the cache is indexed by draw-encounter order and must stay aligned with the sweep.
    DrawBox nb;
    for (int a = 0; a < 3; a++) {
      nb.bb[a] = std::numeric_limits<float>::max();
      nb.bb[a + 3] = -std::numeric_limits<float>::max();
    }
    nb.tris = 0;
    if (allowed) {
      draws_tested++;
    }
    int* ordp = allowed ? &ord[(u32)tree_tex] : nullptr;
    walk_tris(idx, first, count, strips, verts.size(), [&](u32 a, u32 b, u32 c) {
      const auto& v0 = verts[a];
      const auto& v1 = verts[b];
      const auto& v2 = verts[c];
      if (building) {
        for (const auto* v : {&v0, &v1, &v2}) {
          nb.bb[0] = std::min(nb.bb[0], v->x);
          nb.bb[1] = std::min(nb.bb[1], v->y);
          nb.bb[2] = std::min(nb.bb[2], v->z);
          nb.bb[3] = std::max(nb.bb[3], v->x);
          nb.bb[4] = std::max(nb.bb[4], v->y);
          nb.bb[5] = std::max(nb.bb[5], v->z);
        }
        nb.tris++;
      }
      if (!allowed) {
        return;  // cache-build walk only: filtered draws are never tested
      }
      const int tri = (*ordp)++;  // EVERY emitted triangle counts, hit or miss, budget or not
      if (faces >= kMaxSweepFaces) {
        if (!warned) {
          lg::warn("[mb-diag] raytest sweep exceeded {} faces (sys={} lvl={}) — truncating",
                   kMaxSweepFaces, system, level_name);
          warned = true;
        }
        return;
      }
      faces++;
      const math::Vector3f p0(v0.x, v0.y, v0.z);
      const math::Vector3f p1(v1.x, v1.y, v1.z);
      const math::Vector3f p2(v2.x, v2.y, v2.z);
      const float t = ray_tri(o, d, p0, p1, p2);
      if (t < 0.f) {
        return;
      }
      GfxGlobalSettings::MbRayHit h;
      h.t = t;
      h.sys = system;
      h.texid = (u32)tree_tex;
      std::strncpy(h.lvl, level_name, sizeof(h.lvl) - 1);
      h.lvl[sizeof(h.lvl) - 1] = '\0';
      h.tri = tri;
      math::Vector3f n = (p1 - p0).cross(p2 - p0);
      const float nl = n.length();
      if (nl > 0.f) {
        n /= nl;
      }
      for (int k = 0; k < 3; k++) {
        h.hit[k] = o[k] + t * d[k];
        h.v0[k] = p0[k];
        h.v1[k] = p1[k];
        h.v2[k] = p2[k];
        h.nrm[k] = n[k];
      }
      insert_hit(s, h);
    });
    if (building) {
      pe->boxes.push_back(nb);
    }
  };

  // fixed iteration order — the SAME order every sweep and the same one the gizmo build walks.
  if (system == 0) {
    for (const auto& tree : lev->tfrag_trees[0]) {
      if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
        continue;
      }
      const auto& verts = tree.unpacked.vertices;
      for (const auto& draw : tree.draws) {
        u64 count = 0;
        for (const auto& g : draw.vis_groups) {
          count += g.num_inds;
        }
        sweep_draw(verts, tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer,
                   count, tree.use_strips, draw.tree_tex_id);
      }
    }
  } else {
    for (const auto& tree : lev->tie_trees[0]) {
      const auto& verts = tree.unpacked.vertices;
      // static_draws only — wind draws live in prototype-local space (see the gizmo build).
      for (const auto& draw : tree.static_draws) {
        u64 count = 0;
        for (const auto& g : draw.vis_groups) {
          count += g.num_inds;
        }
        sweep_draw(verts, tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer,
                   count, tree.use_strips, draw.tree_tex_id);
      }
    }
  }
  lg::info("[mb-diag] raytest sys={} lvl={} draws_tested={} faces={} hits_now={}", system,
           level_name, draws_tested, faces, s.mb_pick_hit_n);
}

}  // namespace mb_pick
