#include "GrassRenderer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <string>
#include <unordered_map>

#include "common/log/log.h"

#include "game/graphics/opengl_renderer/loader/Loader.h"

namespace {

// deterministic integer hash -> float in [0,1). Stable frame-to-frame so the
// grass field never shimmers, and (crucially) independent of the camera so the
// same ground always gets the same instances no matter where the player stands.
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

// ---------------------------------------------------------------------------
// CULLING FIX (owner feedback #2, 2026-07-10) — the real root cause.
// ---------------------------------------------------------------------------
// The previous build placed grass only within MAX_PLACE_DIST (64 m) of the
// *build-time* camera, rebuilt the whole field every REBUILD_MOVE_DIST (20 m) of
// movement, and graded the per-triangle instance count by the build-time camera
// distance (density_at()). While walking this produced EXACTLY the owner's bugs:
//   * ground beyond 64 m had zero grass and stayed empty until a rebuild fired
//     -> "des zones qui chargent pas" (zones that don't load),
//   * the 20 m rebuild snapped in a whole new field at once -> pop-in while moving,
//   * each rebuild re-graded density by the NEW camera distance, so a chunk that
//     was now farther lost its instances -> "des zones entières qui disparaissent
//     en dépit du fait qu'on soit à proximité" (whole zones de-instance).
// FIX: placement is now WHOLE-LEVEL and CAMERA-INDEPENDENT. Every qualifying
// training-ground triangle is scattered ONCE at level load at a UNIFORM density
// (auto-scaled to a budget so it stays bounded on any level size) into a static
// buffer. Walking never rebuilds and never re-grades, so no chunk can pop/vanish.
// All LOD (near blade / mid card / far nothing) is done per-instance in the
// shader from the live camera — the GPU decides visibility every frame over the
// complete field. This is the standard robust grass approach.
constexpr float U = 4096.0f;              // GOAL world units per meter
constexpr float BASE_H = 1550.0f;         // ~0.38 m nominal blade height (owner asked TWICE for longer grass)
// OWNER POLISH#3: relaxed 0.7 -> 0.40 so SLOPED / bumpy grass-textured platforms
// qualify. Placement already samples the ACTUAL per-triangle surface (barycentric
// on the real tri plane, gi.py below), so this is NOT a flat/min-Y reference; the
// old 0.7 gate simply REJECTED the non-flat tris of bumpy platforms, leaving grass
// only on their flattest (often lowest) tris -> looked like grass sunk under the
// surface / whole platforms skipped. 0.40 keeps near-vertical walls (>66°) out.
constexpr float GROUND_UPNESS = 0.40f;    // face-normal.y threshold for "walkable ground"
constexpr float MAX_TRI_AREA = 300.0f;    // m^2; reject implausibly huge (spurious) triangles
constexpr float D_TARGET = 150.0f;        // tufts/m^2 uniform (dense lawn); auto-reduced to fit budget
// OWNER POLISH#3: density++ (owner's #1 ask, 3rd time). The uniform field is budget-
// clamped, so raising the ceiling directly raises density (near blades AND mid cards).
constexpr int MAX_INSTANCES = 640000;     // total instance ceiling for the whole-level static field
constexpr float BUDGET_SAFETY = 0.9f;     // keep expected count under the ceiling so NO triangle is
                                          // ever starved (a mid-list cap hit would re-create the bug)

// culling-instrumentation constants (must mirror the shader LOD bands in grass.vert)
constexpr float CHUNK_M = 8.0f;           // instrumentation chunk size (m)
constexpr float LOD_BLADE_END_M = 28.0f;  // grass.vert B_END  — blades fully gone beyond this
constexpr float LOD_CARD_OUT_M = 62.0f;   // grass.vert C_OUT1 — cards fully gone beyond this
constexpr float OLD_WINDOW_M = 64.0f;     // the REMOVED camera window (for the fix diagnostic)

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
  m_chunks.clear();
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

  int considered_draws = 0;  // grass-ground draws matched
  int tris_kept = 0;         // qualifying walkable-ground triangles
  int giant_tris = 0;        // rejected as implausibly large (spurious reconstruction)
  float total_area_m2 = 0.0f;
  float max_area = 0.0f;

  // A qualifying walkable-ground triangle anywhere in the level. Collected in
  // PHASE 1 (no camera filter), then scattered at a uniform density in PHASE 2.
  struct TriRec {
    float p0x, p0y, p0z;   // base vertex
    float e1x, e1y, e1z;   // edge to v1
    float e2x, e2y, e2z;   // edge to v2
    float area_m2;
    u32 seed;              // deterministic per-triangle seed (triangle identity, camera-independent)
  };
  std::vector<TriRec> tris;

  // ---- PHASE 1: collect ALL qualifying ground triangles (WHOLE LEVEL). ----
  // No camera window — the field must be complete so nothing can fail to load or
  // de-instance while moving. Highest-detail tfrag geometry only (geo 0).
  // Vertices are world-space, 4096 = 1 m.
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

      // record one triangle (vertex indices a,b,ci) if it is walkable ground and
      // not an implausibly large (spurious) triangle.
      auto consider_tri = [&](u32 a, u32 b, u32 ci) {
        if (a == UINT32_MAX || b == UINT32_MAX || ci == UINT32_MAX) return;
        if (a == b || b == ci || a == ci) return;
        const auto& p0 = verts[a];
        const auto& p1 = verts[b];
        const auto& p2 = verts[ci];
        float e1x = p1.x - p0.x, e1y = p1.y - p0.y, e1z = p1.z - p0.z;
        float e2x = p2.x - p0.x, e2y = p2.y - p0.y, e2z = p2.z - p0.z;
        float nx = e1y * e2z - e1z * e2y;
        float ny = e1z * e2x - e1x * e2z;
        float nz = e1x * e2y - e1y * e2x;
        float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (nlen <= 1e-3f) return;
        float area_m2 = (0.5f * nlen) / (U * U);
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
        r.seed = (begin ^ (a * 2654435761u) ^ (ci * 40503u));
        tris.push_back(r);
        tris_kept++;
        total_area_m2 += area_m2;
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

  // ---- PHASE 2: scatter at a UNIFORM density over the whole level. ----
  // Density is a single world-space constant (no camera grading), auto-reduced so
  // the expected instance total stays safely under the ceiling — that way the cap
  // is NEVER hit mid-list, so no triangle/chunk is ever starved (a mid-list cap
  // hit is what de-instances distant chunks). Placement is a pure function of
  // triangle identity, so it is identical every level load and stable forever.
  float density = D_TARGET;
  if (total_area_m2 > 1.0f && total_area_m2 * D_TARGET > BUDGET_SAFETY * (float)MAX_INSTANCES) {
    density = BUDGET_SAFETY * (float)MAX_INSTANCES / total_area_m2;
  }

  m_instances.reserve(std::min<size_t>(MAX_INSTANCES, (size_t)(total_area_m2 * density) + 64));
  for (const auto& r : tris) {
    if ((int)m_instances.size() >= MAX_INSTANCES) break;
    float fn = r.area_m2 * density;
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
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      m_instances.push_back(gi);
    }
  }

  m_instance_count = (int)m_instances.size();

  // Build the chunk grid (culling instrumentation only — proves completeness).
  {
    std::unordered_map<s64, ChunkInfo> grid;
    grid.reserve(4096);
    const float inv = 1.0f / (CHUNK_M * U);
    for (const auto& gi : m_instances) {
      s64 gx = (s64)std::floor(gi.px * inv);
      s64 gz = (s64)std::floor(gi.pz * inv);
      s64 key = (gx << 32) ^ (gz & 0xffffffffLL);
      auto& c = grid[key];
      c.cx += gi.px;
      c.cz += gi.pz;
      c.count += 1;
    }
    m_chunks.reserve(grid.size());
    for (auto& kv : grid) {
      ChunkInfo c = kv.second;
      c.cx /= (float)c.count;  // chunk centroid
      c.cz /= (float)c.count;
      m_chunks.push_back(c);
    }
  }

  // Only commit the cache once the level is actually loaded (grass draws found),
  // so a transient (level still streaming) placement is not frozen incomplete —
  // if no draws matched we leave the cache invalid and retry next frame.
  if (considered_draws > 0) {
    m_cached_level = (const void*)lev;
    m_cached_load_id = ld->load_id;
  }

  ensure_gl();
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(m_instance_count * sizeof(GrassInstance)),
               m_instances.empty() ? nullptr : m_instances.data(), GL_STATIC_DRAW);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  lg::info(
      "[recharged-grass] training STATIC place (whole-level, camera-independent): {} grass-ground "
      "draws, {} tris kept (giant {}, maxArea {:.0f}m2), area {:.0f} m2, density {:.0f}/m2 -> {} "
      "instances in {} chunks. No camera window, no move-rebuild -> nothing de-instances while moving.",
      considered_draws, tris_kept, giant_tris, max_area, total_area_m2, density, m_instance_count,
      (int)m_chunks.size());
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
  // Rebuild ONLY on level change / reload. Placement is camera-independent
  // (whole-level, uniform), so walking NEVER triggers a rebuild — that is the
  // culling fix: no pop-in, no de-instancing, no hitch while moving.
  if (m_cached_level != (const void*)ld->level.get() || m_cached_load_id != ld->load_id) {
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

  // ---- CULLING INSTRUMENTATION (owner feedback #2): prove that every in-range
  // chunk stays DRAWN while MOVING. Throttled to ~1 log / 30 frames. With the
  // static whole-level field, chunks_drawn == chunks_in_range every frame
  // (dropped == 0) — exactly the property the old camera-windowed / 20 m-rebuild
  // path violated. `beyond_old_window` counts chunks the OLD code would have
  // dropped (past its 64 m camera window) that are STILL placed now.
  m_frame++;
  if ((m_frame % 30) == 0 && !m_chunks.empty()) {
    float cx = rs->camera_pos.x(), cy = rs->camera_pos.y(), cz = rs->camera_pos.z();
    float mvx = cx - m_last_log_cam[0], mvz = cz - m_last_log_cam[2];
    bool moving = (mvx * mvx + mvz * mvz) > (0.5f * U) * (0.5f * U);
    int in_lod = 0, drawn = 0, in_blade = 0, beyond_old_window = 0;
    for (const auto& ch : m_chunks) {
      float dx = ch.cx - cx, dz = ch.cz - cz;
      float dm = std::sqrt(dx * dx + dz * dz) / U;
      if (dm < LOD_CARD_OUT_M) {
        in_lod++;
        drawn++;  // static complete field: an in-range chunk is ALWAYS drawn
      }
      if (dm < LOD_BLADE_END_M) {
        in_blade++;
      }
      if (dm > OLD_WINDOW_M) {
        beyond_old_window++;
      }
    }
    lg::info(
        "[recharged-grass] frame {} cam=({:.0f},{:.0f}) moving={} chunks={} in_lod(<62m)={} "
        "drawn={} DROPPED={} blade(<28m)={} | {} chunks beyond the OLD 64m window are STILL "
        "placed (they de-instanced in the old build)",
        m_frame, cx / U, cz / U, moving ? 1 : 0, (int)m_chunks.size(), in_lod, drawn,
        in_lod - drawn, in_blade, beyond_old_window);
    m_last_log_cam[0] = cx;
    m_last_log_cam[1] = cy;
    m_last_log_cam[2] = cz;
  }
}
