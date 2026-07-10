#include "GrassRenderer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <string>

#include "common/log/log.h"

#include "game/graphics/opengl_renderer/loader/Loader.h"

namespace {

// deterministic integer hash -> float in [0,1). Stable frame-to-frame so the
// grass field never shimmers.
inline u32 hash_u32(u32 x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  x ^= x >> 16;
  return x;
}
inline float hash_f(u32 seed) {
  return static_cast<float>(hash_u32(seed) >> 8) * (1.0f / 16777216.0f);  // 24-bit -> [0,1)
}

// OWNER POLISH 2026-07-10: density is the #1 ask ("surtout pas assez dense") and the
// player must stand IN the near blades. Density is now GRADED by camera distance —
// very dense where the player stands (the near-blade LOD band), thinning to a light
// scatter of cards far away. Triangles are placed NEAREST-FIRST (see rebuild), so if
// the instance cap is hit it drops the distant CARDS, never the near blades. Together
// with a cap well above the real instance total this also kills the earlier "pop-in"
// (which came from the 120k cap being consumed in draw order, so which ground got
// grass shifted as the player moved).
constexpr float D_NEAR = 160.0f;   // tufts/m^2 within NEAR_DENSE_R of the camera (a thick lawn)
constexpr float D_FAR = 14.0f;     // tufts/m^2 at/after FAR_DENSE_R (sparse distant cards)
constexpr float NEAR_DENSE_R = 20.0f;  // m; full dense within this radius (covers the blade band)
constexpr float FAR_DENSE_R = 36.0f;   // m; density ramps down to D_FAR by here
constexpr int MAX_INSTANCES = 220000;  // hard cap; sits above the real total so the near lawn is stable
constexpr float U = 4096.0f;              // GOAL world units per meter
constexpr float BASE_H = 820.0f;          // ~0.20 m nominal blade height (world units)
constexpr float GROUND_UPNESS = 0.7f;     // face-normal.y threshold for "walkable ground"
constexpr float MAX_TRI_AREA = 300.0f;    // m^2; reject implausibly huge (spurious) triangles
constexpr float MAX_PLACE_DIST = 64.0f * U;   // only place grass within 64 m of the camera
constexpr float REBUILD_MOVE_DIST = 20.0f * U;  // rebuild when the player moves 20 m

// density (tufts/m^2) as a function of the triangle's distance from the camera (m):
// full D_NEAR out to NEAR_DENSE_R, linearly down to D_FAR by FAR_DENSE_R, then flat.
inline float density_at(float dist_m) {
  if (dist_m <= NEAR_DENSE_R) {
    return D_NEAR;
  }
  if (dist_m >= FAR_DENSE_R) {
    return D_FAR;
  }
  float t = (dist_m - NEAR_DENSE_R) / (FAR_DENSE_R - NEAR_DENSE_R);
  return D_NEAR + (D_FAR - D_NEAR) * t;
}

// Training-level grassy-ground textures (curated, texture-driven — no hand
// authoring). tra-grass is the elevated grassy terrain; tra-beachrock is the
// green, mossy walkable ground the player actually stands on at the Geyser Rock
// spawn (confirmed on-device as the nearest walkable draw under the camera —
// tra-grass alone sits ~100m away up the slopes and never reaches the player);
// the *-grassfringe / leafyground fringes blend the two. All read as the green
// grass ground the owner wants covered.
inline bool is_grass_ground(const std::string& n) {
  return n == "tra-grass" || n == "tra-beachrock" || n == "bch-grassfringe" ||
         n == "bch-leafyground-hang-2x1";
}

}  // namespace

GrassRenderer::GrassRenderer() = default;

GrassRenderer::~GrassRenderer() {
  if (m_gl_ready) {
    glDeleteVertexArrays(1, &m_vao);
    glDeleteBuffers(1, &m_instance_vbo);
  }
}

void GrassRenderer::ensure_gl() {
  if (m_gl_ready) {
    return;
  }
  glGenVertexArrays(1, &m_vao);
  glGenBuffers(1, &m_instance_vbo);
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  // per-instance: vec4 pos+height, vec4 yaw/tint/curve/phase (both advance once per instance)
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance), (void*)0);
  glVertexAttribDivisor(0, 1);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                        (void*)(4 * sizeof(float)));
  glVertexAttribDivisor(1, 1);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  m_gl_ready = true;
}

void GrassRenderer::rebuild(SharedRenderState* rs) {
  m_instances.clear();
  m_instance_count = 0;
  m_cached_level = nullptr;
  m_cached_load_id = UINT64_MAX;

  if (!rs->loader) {
    return;
  }
  const LevelData* ld = rs->loader->get_tfrag3_level("training");
  if (!ld || !ld->level) {
    return;
  }
  const tfrag3::Level* lev = ld->level.get();

  // Focus the instance budget near the player: only place grass on triangles
  // within MAX_PLACE_DIST of the camera (far grass is past the LOD bands anyway).
  // Record the build camera so render() can rebuild when the player moves.
  float cam_x = rs->camera_pos.x(), cam_y = rs->camera_pos.y(), cam_z = rs->camera_pos.z();
  m_build_cam[0] = cam_x;
  m_build_cam[1] = cam_y;
  m_build_cam[2] = cam_z;

  int considered_draws = 0;  // grass-ground draws matched
  int tris_seen = 0;         // qualifying-draw triangles processed (near the player)
  int giant_tris = 0;        // rejected as implausibly large (spurious reconstruction)
  int far_tris = 0;          // skipped: beyond MAX_PLACE_DIST from the camera
  float max_area = 0.0f;     // largest accepted triangle area (m^2)

  // A qualifying walkable-ground triangle near the player. Collected in PHASE 1,
  // sorted NEAREST-FIRST, then scattered in PHASE 2 so a cap hit drops distant
  // cards, never the near blades the player stands in.
  struct TriRec {
    float p0x, p0y, p0z;   // base vertex
    float e1x, e1y, e1z;   // edge to v1
    float e2x, e2y, e2z;   // edge to v2
    float area_m2;
    float dist2;           // squared camera distance to the centroid (for sort + grading)
    u32 seed;              // deterministic per-triangle seed (triangle identity)
  };
  std::vector<TriRec> tris;

  // ---- PHASE 1: collect qualifying ground triangles within MAX_PLACE_DIST. ----
  // Highest-detail tfrag geometry only (geo 0). Vertices are world-space, 4096 = 1 m.
  for (const auto& tree : lev->tfrag_trees[0]) {
    const auto& verts = tree.unpacked.vertices;
    const auto& idx = tree.unpacked.indices;
    if (verts.empty() || idx.empty()) {
      continue;
    }

    for (const auto& draw : tree.draws) {
      if (draw.tree_tex_id < 0 || (size_t)draw.tree_tex_id >= lev->textures.size()) {
        continue;
      }
      if (!is_grass_ground(lev->textures[draw.tree_tex_id].debug_name)) {
        continue;
      }
      considered_draws++;

      // This draw's slice of the shared index buffer. The AUTHORITATIVE length is
      // the sum of the draw's vis_groups' num_inds — the EXACT slice the scene
      // renderer uploads (see make_all_visible_index_list in background_common.cpp).
      u32 begin = draw.unpacked.idx_of_first_idx_in_full_buffer;
      u32 len = 0;
      for (const auto& g : draw.vis_groups) {
        len += g.num_inds;
      }
      if (len == 0 || begin >= idx.size()) {
        continue;
      }
      if (begin + len > idx.size()) {
        len = (u32)(idx.size() - begin);
      }

      // record one triangle (vertex indices a,b,ci) if it is walkable ground near
      // the player and not an implausibly large (spurious) triangle.
      auto consider_tri = [&](u32 a, u32 b, u32 ci) {
        if (a == UINT32_MAX || b == UINT32_MAX || ci == UINT32_MAX) return;
        if (a == b || b == ci || a == ci) return;
        const auto& p0 = verts[a];
        const auto& p1 = verts[b];
        const auto& p2 = verts[ci];
        // focus the budget near the player: skip triangles far from the camera.
        float ccx = (p0.x + p1.x + p2.x) * (1.0f / 3.0f) - cam_x;
        float ccy = (p0.y + p1.y + p2.y) * (1.0f / 3.0f) - cam_y;
        float ccz = (p0.z + p1.z + p2.z) * (1.0f / 3.0f) - cam_z;
        float d2 = ccx * ccx + ccy * ccy + ccz * ccz;
        if (d2 > MAX_PLACE_DIST * MAX_PLACE_DIST) {
          far_tris++;
          return;
        }
        float e1x = p1.x - p0.x, e1y = p1.y - p0.y, e1z = p1.z - p0.z;
        float e2x = p2.x - p0.x, e2y = p2.y - p0.y, e2z = p2.z - p0.z;
        float nx = e1y * e2z - e1z * e2y;
        float ny = e1z * e2x - e1x * e2z;
        float nz = e1x * e2y - e1y * e2x;
        float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (nlen <= 1e-3f) return;
        float area_m2 = (0.5f * nlen) / (U * U);
        tris_seen++;
        max_area = std::max(max_area, area_m2);
        if (area_m2 > MAX_TRI_AREA) {  // spurious level-spanning triangle
          giant_tris++;
          return;
        }
        float upness = std::fabs(ny) / nlen;  // 1.0 = perfectly flat ground
        if (upness <= GROUND_UPNESS || area_m2 <= 1e-4f) return;
        TriRec r;
        r.p0x = p0.x; r.p0y = p0.y; r.p0z = p0.z;
        r.e1x = e1x; r.e1y = e1y; r.e1z = e1z;
        r.e2x = e2x; r.e2y = e2y; r.e2z = e2z;
        r.area_m2 = area_m2;
        r.dist2 = d2;
        r.seed = (begin ^ (a * 2654435761u) ^ (ci * 40503u));
        tris.push_back(r);
      };

      if (tree.use_strips) {
        // one restart-delimited triangle strip: each new vertex closes a triangle
        // with the previous two.
        u32 a = UINT32_MAX, b = UINT32_MAX;
        for (u32 k = begin; k < begin + len; ++k) {
          u32 ci = idx[k];
          if (ci == UINT32_MAX) {  // strip restart
            a = UINT32_MAX;
            b = UINT32_MAX;
            continue;
          }
          consider_tri(a, b, ci);
          a = b;
          b = ci;
        }
      } else {
        // plain triangle list: discrete triples.
        for (u32 k = begin; k + 2 < begin + len; k += 3) {
          consider_tri(idx[k], idx[k + 1], idx[k + 2]);
        }
      }
    }
  }

  // ---- PHASE 2: nearest-first, density GRADED by distance. ----
  std::sort(tris.begin(), tris.end(),
            [](const TriRec& a, const TriRec& b) { return a.dist2 < b.dist2; });
  m_instances.reserve(std::min<size_t>(MAX_INSTANCES, tris.size() * 4));
  for (const auto& r : tris) {
    if ((int)m_instances.size() >= MAX_INSTANCES) break;
    float dist_m = std::sqrt(r.dist2) / U;
    float fn = r.area_m2 * density_at(dist_m);
    int n = (int)fn;
    if (hash_f(r.seed + 99u) < (fn - (float)n)) {
      n += 1;
    }
    for (int i = 0; i < n; ++i) {
      if ((int)m_instances.size() >= MAX_INSTANCES) break;
      u32 sd = r.seed + (u32)i * 3266489917u;
      float r1 = hash_f(sd + 1u);
      float r2 = hash_f(sd + 2u);
      if (r1 + r2 > 1.0f) {
        r1 = 1.0f - r1;
        r2 = 1.0f - r2;
      }
      GrassInstance gi;
      gi.px = r.p0x + r1 * r.e1x + r2 * r.e2x;
      gi.py = r.p0y + r1 * r.e1y + r2 * r.e2y;
      gi.pz = r.p0z + r1 * r.e1z + r2 * r.e2z;
      gi.h = BASE_H * (0.55f + 1.15f * hash_f(sd + 3u));   // wider SIZE variation
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      m_instances.push_back(gi);
    }
  }

  m_instance_count = (int)m_instances.size();
  m_cached_level = (const void*)lev;
  m_cached_load_id = ld->load_id;

  ensure_gl();
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(m_instance_count * sizeof(GrassInstance)),
               m_instances.empty() ? nullptr : m_instances.data(), GL_STATIC_DRAW);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  // Diagnostic: is the player standing IN the dense blade band? Count instances
  // within the blade band and very close, and log the camera->Jak distance.
  const auto& jp = Gfx::g_global_settings.recharged_jak_pos;
  float cam_to_jak = -1.0f;
  if (jp[3] > 0.5f) {
    float dx = jp[0] - cam_x, dy = jp[1] - cam_y, dz = jp[2] - cam_z;
    cam_to_jak = std::sqrt(dx * dx + dy * dy + dz * dz) / U;
  }
  int in_blade_band = 0, within_8m = 0;
  for (const auto& gi : m_instances) {
    float dx = gi.px - cam_x, dy = gi.py - cam_y, dz = gi.pz - cam_z;
    float dm = std::sqrt(dx * dx + dy * dy + dz * dz) / U;
    if (dm <= 28.0f) in_blade_band++;
    if (dm <= 8.0f) within_8m++;
  }
  lg::info(
      "[recharged-grass] training: {} grass-ground draws, {} tris (giant {}, far {}, maxArea "
      "{:.0f}m2) -> {} instances | cam->jak {:.1f}m, {} in blade-band(28m), {} within 8m",
      considered_draws, tris_seen, giant_tris, far_tris, max_area, m_instance_count, cam_to_jak,
      in_blade_band, within_8m);
}

void GrassRenderer::render(SharedRenderState* rs, ScopedProfilerNode& prof) {
  if (!rs->has_pc_data) {
    return;
  }
  // Hard-scope to the training level: get_tfrag3_level returns null anywhere else.
  const LevelData* ld = rs->loader ? rs->loader->get_tfrag3_level("training") : nullptr;
  if (!ld || !ld->level) {
    return;
  }
  // Rebuild on level change/reload, or once the player has walked far enough that
  // the near-focused field should follow them.
  float mdx = rs->camera_pos.x() - m_build_cam[0];
  float mdy = rs->camera_pos.y() - m_build_cam[1];
  float mdz = rs->camera_pos.z() - m_build_cam[2];
  bool moved = (mdx * mdx + mdy * mdy + mdz * mdz) > (REBUILD_MOVE_DIST * REBUILD_MOVE_DIST);
  if (m_cached_level != (const void*)ld->level.get() || m_cached_load_id != ld->load_id || moved) {
    rebuild(rs);
  }
  if (m_instance_count <= 0) {
    return;
  }

  // monotonic seconds for the breeze
  static const auto t0 = std::chrono::steady_clock::now();
  float u_time =
      std::chrono::duration<float>(std::chrono::steady_clock::now() - t0).count();

  auto& shader = rs->shaders[ShaderId::GRASS];
  shader.activate();
  GLuint id = shader.id();

  glUniformMatrix4fv(glGetUniformLocation(id, "camera"), 1, GL_FALSE,
                     rs->camera_matrix[0].data());
  glUniform4f(glGetUniformLocation(id, "hvdf_offset"), rs->camera_hvdf_off[0],
              rs->camera_hvdf_off[1], rs->camera_hvdf_off[2], rs->camera_hvdf_off[3]);
  glUniform4f(glGetUniformLocation(id, "camera_position"), rs->camera_pos[0], rs->camera_pos[1],
              rs->camera_pos[2], rs->camera_pos[3]);
  glUniform1f(glGetUniformLocation(id, "fog_constant"), rs->camera_fog.x());
  glUniform1f(glGetUniformLocation(id, "u_time"), u_time);
  const auto& jp = Gfx::g_global_settings.recharged_jak_pos;
  glUniform4f(glGetUniformLocation(id, "u_jak_pos"), jp[0], jp[1], jp[2], jp[3]);

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_TRUE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glBindVertexArray(m_vao);
  GLint mode_loc = glGetUniformLocation(id, "u_mode");

  // NEAR: individual blades (10-vert triangle strip)
  glUniform1i(mode_loc, 0);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 10, m_instance_count);
  prof.add_draw_call();
  prof.add_tri(m_instance_count * 8);

  // MID: X-cross cards (12-vert, 4 triangles)
  glUniform1i(mode_loc, 1);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 12, m_instance_count);
  prof.add_draw_call();
  prof.add_tri(m_instance_count * 4);

  glBindVertexArray(0);
}
