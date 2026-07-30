#include "MeshBrowserGizmos.h"

#include <algorithm>
#include <cstring>
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

  glBindVertexArray(g_cache.vao);
  glDrawArrays(GL_LINES, 0, (GLsizei)g_cache.verts.size());
  prof.add_draw_call();
  glBindVertexArray(0);
  s.mb_ctr_gizmo_draws++;
  // V2.1 per-frame proof: line primitives ACTUALLY submitted this frame (2 verts per line).
  s.mb_cur_gizmo_prims += (u32)(g_cache.verts.size() / 2);

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
  if (prev_depth_test) {
    glEnable(GL_DEPTH_TEST);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  glDepthMask(prev_depth_mask);
}

}  // namespace mb_gizmos

namespace mb_pick {

namespace {

// Watertight-enough Moller-Trumbore, GOAL units. Returns t >= 0 along the (unit) ray or a
// negative value on miss. Backfaces DO count: the reticle must pick a wall whose winding is
// wrong — inverted-normal hunting is this browser's whole purpose.
float ray_tri(const float* o, const float* d, const math::Vector3f& p0,
              const math::Vector3f& p1, const math::Vector3f& p2) {
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

// Per-candidate face budget: a level-spanning tex population must not hitch the GL thread
// unboundedly. 120k faces tested per candidate per frame is ~1 ms class on the Redmi and far
// above any single mesh row's real face count.
constexpr u32 kMaxTestFaces = 120000;

}  // namespace

void raytest(const tfrag3::Level* lev, int system, const char* level_name) {
  auto& s = Gfx::g_global_settings;
  if (!lev || !pending()) {
    return;
  }
  // acquire pairs with the GOAL thread's release store of mb_pick_serial: candidate arrays are
  // fully visible from here on.
  s.mb_pick_serial.load(std::memory_order_acquire);
  // which candidates belong to THIS renderer?
  int mine[GfxGlobalSettings::MB_PICK_MAX];
  int n_mine = 0;
  for (int i = 0; i < s.mb_pick_n && i < GfxGlobalSettings::MB_PICK_MAX; i++) {
    if (s.mb_pick_sys[i] == system &&
        std::strncmp(level_name, s.mb_pick_lvl[i], sizeof(s.mb_pick_lvl[i])) == 0) {
      mine[n_mine++] = i;
    }
  }
  if (n_mine == 0) {
    return;
  }
  const float* o = s.mb_pick_ray_o;
  const float* d = s.mb_pick_ray_d;
  for (int m = 0; m < n_mine; m++) {
    const int ci = mine[m];
    const u32 want_tex = s.mb_pick_texid[ci];
    const float* bb = s.mb_pick_bbox[ci];
    u32 faces = 0;
    auto test_face = [&](const std::vector<tfrag3::PreloadedVertex>& verts, u32 a, u32 b,
                         u32 c) {
      if (faces >= kMaxTestFaces) {
        return;
      }
      faces++;
      const auto& v0 = verts[a];
      const auto& v1 = verts[b];
      const auto& v2 = verts[c];
      // same per-face AABB filter as the gizmo build: all 3 verts inside the row's box (+slack),
      // so two rows sharing a tex id stay separable.
      for (const auto* v : {&v0, &v1, &v2}) {
        if (v->x < bb[0] - 2048.f || v->x > bb[3] + 2048.f ||  //
            v->y < bb[1] - 2048.f || v->y > bb[4] + 2048.f ||  //
            v->z < bb[2] - 2048.f || v->z > bb[5] + 2048.f) {
          return;
        }
      }
      const float t = ray_tri(o, d, math::Vector3f(v0.x, v0.y, v0.z),
                              math::Vector3f(v1.x, v1.y, v1.z), math::Vector3f(v2.x, v2.y, v2.z));
      if (t >= 0.f && (s.mb_pick_ttri[ci] < 0.f || t < s.mb_pick_ttri[ci])) {
        s.mb_pick_ttri[ci] = t;
      }
    };
    if (system == 0) {
      for (const auto& tree : lev->tfrag_trees[0]) {
        if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
          continue;
        }
        const auto& verts = tree.unpacked.vertices;
        for (const auto& draw : tree.draws) {
          if (draw.tree_tex_id < 0 || (u32)draw.tree_tex_id != want_tex) {
            continue;
          }
          u64 count = 0;
          for (const auto& g : draw.vis_groups) {
            count += g.num_inds;
          }
          walk_tris(tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                    tree.use_strips, verts.size(),
                    [&](u32 a, u32 b, u32 c) { test_face(verts, a, b, c); });
        }
      }
    } else {
      for (const auto& tree : lev->tie_trees[0]) {
        const auto& verts = tree.unpacked.vertices;
        // static_draws only — wind draws live in prototype-local space (see the gizmo build).
        for (const auto& draw : tree.static_draws) {
          if (draw.tree_tex_id < 0 || (u32)draw.tree_tex_id != want_tex) {
            continue;
          }
          u64 count = 0;
          for (const auto& g : draw.vis_groups) {
            count += g.num_inds;
          }
          walk_tris(tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                    tree.use_strips, verts.size(),
                    [&](u32 a, u32 b, u32 c) { test_face(verts, a, b, c); });
        }
      }
    }
  }
}

}  // namespace mb_pick
