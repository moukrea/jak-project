#pragma once

/*!
 * @file gfx.h
 * Graphics component for the runtime. Abstraction layer for the main graphics routines.
 */

#include <array>
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>
#include <chrono>
#include <cstdlib>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "game/kernel/common/kboot.h"
#include "game/settings/settings.h"
#include "game/system/hid/display_manager.h"
#include "game/system/hid/input_manager.h"

// forward declarations
struct GfxGlobalSettings;
class GfxDisplay;

// enum for rendering pipeline
// Gvulkan-option: Vulkan is a selectable backend. OpenGL stays the default; Vulkan is chosen only when
// the persisted renderer setting (DisplaySettings::renderer, from the in-game Graphics Options menu)
// selects it. See GetRenderer() in gfx.cpp.
enum class GfxPipeline { Invalid = 0, OpenGL, Vulkan };

// module for the different rendering pipelines
struct GfxRendererModule {
  std::function<int(GfxGlobalSettings&)> init;
  std::function<std::shared_ptr<GfxDisplay>(int width,
                                            int height,
                                            const char* title,
                                            GfxGlobalSettings& settings,
                                            GameVersion version,
                                            bool is_main)>
      make_display;
  std::function<void()> exit;
  std::function<u32()> vsync;
  std::function<u32()> sync_path;
  std::function<void(const void*, u32)> send_chain;
  std::function<void(const u8*, int, u32)> texture_upload_now;
  std::function<void(u32, u32, u32)> texture_relocate;
  std::function<void(const std::vector<std::string>&)> set_levels;
  std::function<void(const std::vector<std::string>&)> set_active_levels;
  std::function<void(float)> set_pmode_alp;
  GfxPipeline pipeline;
  const char* name;
};

// runtime settings
static constexpr int PAT_MOD_COUNT = 4;
static constexpr int PAT_EVT_COUNT = 20;
static constexpr int PAT_MAT_COUNT = 34;
struct GfxGlobalSettings {
  bool debug = true;  // graphics debugging

  // note: this is actually the size of the display that ISN'T letterboxed
  // the excess space is what will be letterboxed away.
  int lbox_w = 640;
  int lbox_h = 480;

  // actual game resolution
  int game_res_w = 640;
  int game_res_h = 480;

  // multi-sampled anti-aliasing sample count. 1 = disabled.
  int msaa_samples = 1;

  // brightness and contrast values set from GOAL (see jak 3)
  int brightness_contrast_color = 0;
  int brightness_contrast_alpha = 128;

  // current renderer
  const GfxRendererModule* renderer;

  // lod settings, used by bucket renderers
  int lod_tfrag = 0;
  int lod_tie = 0;

  // vsync enable
  bool vsync = true;
  bool old_vsync = false;
  // target frame rate
  float target_fps = 60;
  // use custom frame limiter
  bool framelimiter = true;

  // frame timing things
  bool experimental_accurate_lag = false;
  bool sleep_in_frame_limiter = true;

  // fancy effect things
  bool hack_no_tex = false;

  // show an on-screen FPS counter overlay (set from GOAL pc-settings)
  bool display_fps = false;
  // real measured frames-per-second, smoothed, published by the renderer present
  // path (desktop opengl.cpp + Android android_renderer). Read by GOAL via
  // pc-get-fps for the portable on-screen counter. Reflects the TRUE render rate
  // (e.g. ~30 at Geyser), not the engine target.
  float measured_fps = 0.f;
  // Gdynamic-renderscale: smoothed per-frame render WORK time in milliseconds — the
  // CPU wall-clock of the renderer's render() call, EXCLUDING the framelimiter sleep
  // and the vsync/swap wait. Published by both present paths (desktop opengl.cpp +
  // Android android_gfx.cpp). Read by GOAL via pc-get-frame-busy-us as the adaptive
  // render-scale controller's FRAME-TIME headroom signal: unlike measured_fps it does
  // NOT saturate at the vsync cap, so the controller can detect headroom and raise the
  // scale back toward 100% even when fps is pinned at a capped target (e.g. 60).
  float measured_frame_busy_ms = 1000.f / 60.f;

  // collision renderer settings
  bool collision_enable = false;
  bool collision_wireframe = true;

  // matching enum in kernel-defs.gc !!
  enum CollisionRendererMode { None, Mode, Event, Material, Skip, SkipHide } collision_mode = Mode;
  std::array<u32, (PAT_MOD_COUNT + 31) / 32> collision_mode_mask = {UINT32_MAX};
  std::array<u32, (PAT_EVT_COUNT + 31) / 32> collision_event_mask = {UINT32_MAX};
  std::array<u32, (PAT_MAT_COUNT + 31) / 32> collision_material_mask = {UINT32_MAX, UINT32_MAX};
  u32 collision_skip_mask = 0;
  u32 collision_skip_hide_mask = 0;
  bool collision_skip_nomask_allowed = true;

  // Grecharged-master-toggle (owner 2026-07-21): GLOBAL Recharged ON/OFF. OFF forces the
  // stock state of EVERY recharged feature at runtime; the individual flags below keep the
  // user's values (they are simply not consulted while the master is off), so flipping the
  // master back ON restores the configuration exactly. Pushed per-frame from GOAL
  // (-> *pc-settings* recharged-master?) via pc-set-recharged-master!. Feature gates must
  // NEVER read their flag directly — only through Gfx::recharged_active() /
  // recharged_active_mode() below (single-helper rule; no per-feature drift copies).
  bool recharged_master = true;

  // Grecharged-grass-poc: optional procedural 3D grass on the jak1 training level.
  // Set from GOAL (-> *pc-settings* recharged-grass?) via pc-set-recharged-grass!.
  // OFF (default) == byte-identical stock rendering (the renderer hook is skipped).
  bool recharged_grass = false;
  // External-asset-root: when true, the loader looks up user PNG texture
  // replacements under <root>/custom_assets/texture_replacements at runtime.
  // Set from GOAL via pc-set-load-custom-assets!. OFF (default) == stock.
  bool load_custom_assets = false;
  // Grecharged-bundled-textures: use the package-BUNDLED first-party replacement textures
  // (the owner's Recharged set, extracted from the APK custom pack). Set from GOAL via
  // pc-set-recharged-textures!. OFF == stock base textures (user custom_assets replacements
  // keep their own load_custom_assets gate and always win over the bundle; the bundle's
  // _height/_normal/_roughness PBR maps follow the PBR path, not this flag). Default ON so a
  // plain install shows the Recharged look; the MASTER still forces stock when OFF.
  bool recharged_textures = true;
  // Grecharged-mesh-browser: the debug MESH BROWSER's real-texture <-> checker toggle, settable
  // from the menu without adb (the owner has none). pbr_testpattern::mode() falls back to this
  // when no debug.opengoal.pbr.testpattern prop / OG_PBR_TESTPATTERN env is set, so the headless
  // A/B path is unchanged (the prop still overrides in either direction) while the on-device
  // browser can flip the checker on/off. Applied at the NEXT level load (the checker is baked into
  // the texture upload), so the browser re-warps the current mesh after a flip. 0 = off (real
  // textures), 1 = checker where PBR maps exist (the owner's verification pattern). Default 0.
  int recharged_mesh_browser_checker = 0;
  // Grecharged-mesh-browser V2 (owner 2026-07-30): the FREECAM reticle TARGET channel. The GOAL
  // freecam writes a single targeted mesh here (via the pc-mb-* bridges in kmachine.cpp); the
  // TFRAG/TIE draw loops consult it per draw. A "mesh" is one row of the offline index; the only
  // runtime linkage an index row has to draws is its tex_id, so hide/checker act on every draw of
  // the targeted system whose tree_tex_id matches, within the named level. The gizmo builder is
  // finer: it filters per FACE by the row's AABB. When mb_target_active is false every check below
  // short-circuits on the first compare — the normal path is unchanged.
  bool mb_target_active = false;
  int mb_target_system = 0;              // 0 = TFRAG, 1 = TIE (mesh_index system column)
  u32 mb_target_tex = 0;                 // tfrag3 StripDraw::tree_tex_id of the targeted mesh
  char mb_target_level[16] = {0};        // fr3/level name the target lives in
  float mb_target_bbox[6] = {0.f, 0.f, 0.f, 0.f, 0.f, 0.f};  // lo xyz / hi xyz, GOAL UNITS
  bool mb_hide_target = false;           // L1/L2: skip the targeted draws outright
  bool mb_checker_target = false;        // Square: bind the checker base texture for them
  bool mb_gizmos_target = false;         // Circle: per-face normal arrows over the target AABB
  // V2.6-bis isolation (START pad / ISOL overlay pill): while a target is active, render ONLY
  // the targeted mesh — consumed by the TFragment/Tie3 per-draw checks and by the world
  // renderers' early-outs (Shrub/Merc2/Generic2/ocean/shadow). Persists across target changes
  // (the new target is re-isolated); cleared on defocus and browser close.
  bool mb_isolate = false;
  bool mb_isolation_on() const { return mb_target_active && mb_isolate; }
  // Monotonic PROOF counters, bumped on the render thread, read back by GOAL (pc-mb-rt-geti)
  // into files/mesh_browser_state.txt. Monotonic on purpose: a harness proves a toggle is LIVE
  // by sampling twice — the counter moves while the toggle is on and stops when it is off —
  // with no per-frame reset to place. Benign torn reads are fine for evidence counters.
  u32 mb_ctr_hidden_draws = 0;           // draws skipped because hide is on
  u32 mb_ctr_checker_draws = 0;          // draws submitted with the checker override
  u32 mb_ctr_gizmo_draws = 0;            // gizmo render passes submitted
  u32 mb_ctr_gizmo_faces = 0;            // faces in the current gizmo build (set, not summed)
  // V2.1 PER-FRAME proof counters (owner: every toggle dead — a monotonic counter proves a code
  // path ran, but only a per-frame count can show the target's submitted draws hitting ZERO while
  // hidden). The render thread accumulates into mb_cur_* during the frame; both frame loops
  // (OpenGLRenderer::render and AndroidOpenGLRenderer::render — the SEPARATE android file, easy to
  // miss) call mb_flip_frame_counters() once per frame to publish mb_cur_* into mb_frame_* and
  // zero the accumulators. GOAL reads the published side via pc-mb-rt-geti 4..7; benign torn
  // reads are fine for evidence counters.
  u32 mb_cur_target_draws = 0;   // draws SUBMITTED this frame for the targeted mesh (hide -> 0)
  u32 mb_cur_checker_binds = 0;  // checker-texture binds on the target's draws this frame
  u32 mb_cur_gizmo_prims = 0;    // gizmo line primitives actually drawn this frame
  u32 mb_cur_relief_x100 = 0;    // relief factor the shader uniforms were pushed with (x100)
  // V2.2 (owner: Square swapped only the ALBEDO; gizmos emitted but nothing showed):
  u32 mb_cur_checker_full = 0;  // FULL checker set binds (normal+rough+height) on target draws
  u32 mb_cur_target_tess = 0;   // target draws submitted on the TESS program (displacement TAKEN)
  u32 mb_cur_gizmo_px = 0;      // framebuffer pixels the gizmo pass actually CHANGED this frame
  u32 mb_frame_target_draws = 0;
  u32 mb_frame_checker_binds = 0;
  u32 mb_frame_gizmo_prims = 0;
  u32 mb_frame_relief_x100 = 0;
  u32 mb_frame_checker_full = 0;
  u32 mb_frame_target_tess = 0;
  u32 mb_frame_gizmo_px = 0;
  // V2.6-bis isolation proof pair: TFRAG+TIE color draws SUBMITTED for NON-target meshes while
  // a target is active — isolation ON must drive the published value to 0.
  u32 mb_cur_nontarget_draws = 0;
  u32 mb_frame_nontarget_draws = 0;
  // V2.6-bis: render work suppressed by isolation this frame (per-draw skips in TFRAG/TIE plus
  // one per world-renderer early-out).
  u32 mb_cur_isolated_skips = 0;
  u32 mb_frame_isolated_skips = 0;
  // V2.2: browser-open PBR override — armed by pc_mb_set_active(!=0), consulted by
  // recharged_master_active() (lowest precedence, see there). False whenever the browser is
  // closed, so the normal path is byte-identical with the tool off.
  bool mb_pbr_override = false;
  // V2.3 EXACT reticle pick (owner: a clearly visible mesh could rank >16 in AABB order and
  // never get triangle-tested — something else nearby won). The candidate pre-filter is GONE:
  // the render thread now sweeps ALL rendered geometry and the pick is the globally nearest
  // ray-triangle intersection. Protocol:
  //   1. the GOAL thread (kmachine pc_mb_pick) publishes only the ray here and bumps
  //      mb_pick_serial (release);
  //   2. mb_flip_frame_counters() ARMS the request one flip later (a request landing mid-frame
  //      would miss the buckets already drawn) and resets mb_pick_hit_n;
  //   3. during the armed frame, TFragment::render / Tie3::render call mb_pick::raytest — each
  //      renderer sweeps EVERY draw of its system+level (MeshBrowserGizmos.cpp walk,
  //      Moller-Trumbore) and inserts hits below, ascending t, deduped by (sys, texid, lvl);
  //   4. the next flip publishes mb_pick_done; GOAL polls pc-mb-pick-ready? and resolves each
  //      hit's triangle back to an index row.
  // The ray is written by the GOAL thread BEFORE the serial release-store and read by the
  // render thread AFTER an acquire-load — no torn reads. The hit array goes the other way,
  // sequenced by the mb_pick_done release-store at flip.
  static constexpr int MB_PICK_MAX = 16;
  struct MbRayHit {
    float t = -1.f;  // GOAL units along the unit ray
    int sys = 0;     // 0 TFRAG, 1 TIE
    u32 texid = 0;
    char lvl[16] = {0};
    int tri = -1;  // triangle ordinal within (sys, lvl, texid) — see the enumeration rule in
                   // MeshBrowserGizmos.cpp (reproducible by an offline tool)
    float hit[3] = {0.f, 0.f, 0.f};  // GOAL units
    float v0[3] = {0.f, 0.f, 0.f}, v1[3] = {0.f, 0.f, 0.f},
          v2[3] = {0.f, 0.f, 0.f};    // emitted winding
    float nrm[3] = {0.f, 0.f, 0.f};  // unit normal of emitted winding
  };
  std::atomic<u32> mb_pick_serial{0};  // GOAL bumps after publishing a request
  std::atomic<u32> mb_pick_done{0};    // render thread: serial whose hit results are complete
  u32 mb_pick_arm = 0;                 // render-thread-only: serial armed last flip
  float mb_pick_ray_o[3] = {0.f, 0.f, 0.f};  // GOAL units
  float mb_pick_ray_d[3] = {0.f, 0.f, 1.f};  // unit dir
  // browsable-texid filter per pick level+system: the sweep may only test draws whose
  // tree_tex_id has at least one index row (the index holds only displaceable materials — a
  // non-indexed nearest triangle would be unresolvable AND its dedupe slot could evict every
  // browsable hit). Published by the GOAL thread BEFORE the serial release-store, read by the
  // render thread after the acquire, same protocol as the ray.
  static constexpr int MB_PICK_FLT_MAX = 1024;
  char mb_pick_flt_lvl[2][16] = {{0}};
  int mb_pick_flt_n[2][2] = {{0}};             // [slot][sys]
  u32 mb_pick_flt_tex[2][2][MB_PICK_FLT_MAX];  // sorted ascending
  int mb_pick_hit_n = 0;  // render-thread writes between arm and done
  MbRayHit mb_pick_hits_out[MB_PICK_MAX];
  // V2.3 hover channel (GOAL thread writes the ray; render thread answers via seqlock — it is
  // the only writer of the seq-guarded block below).
  std::atomic<int> mb_hover_on{0};
  float mb_hover_ray_o[3] = {0.f, 0.f, 0.f};  // GOAL units
  float mb_hover_ray_d[3] = {0.f, 0.f, 1.f};  // unit
  std::atomic<u32> mb_hover_seq{0};           // even = stable; writer makes it odd during write
  int mb_hover_tri = -1;
  u32 mb_hover_texid = 0;
  float mb_hover_v[3][3] = {{0.f}};  // GOAL units, emitted winding
  float mb_hover_nrm[3] = {0.f, 0.f, 0.f};
  u32 mb_cur_wire = 0, mb_frame_wire = 0;  // wireframe edges drawn (flip like the other mb_cur_*)
  // V2.4 (owner: "on devrait voir ce qui est marqué" / gizmos drawn as if nothing stood in
  // front): the ACTIVE-mark store. The GOAL thread (kmachine pc_mb_mark_poly) toggles entries
  // under mb_marks_mu — marking an already-marked triangle now UNMARKS it and removes its JSONL
  // line — and the render thread copies the store under the same lock once per frame to draw a
  // persistent filled highlight per mark (mb_gizmos::render_marks), visually distinct from the
  // yellow hover. mb_marks_active mirrors the count lock-free so the per-frame call sites in
  // TFragment/Tie3 stay one relaxed load when the browser is closed or nothing is marked.
  // V2.6 (owner hit the old fixed 256-slot cap and marks were refused SILENTLY): the store is a
  // std::vector — no perceptible ceiling. MB_MARKS_SANITY (1M, ten times the owner's 100k floor)
  // exists only so a corrupt or runaway JSONL cannot eat unbounded RAM; reaching it is ANNOUNCED
  // on screen (kmachine bumps the skipped counter -> the HUD's STORE FULL line), never silent.
  // mb_marks_gen bumps under mb_marks_mu on EVERY store mutation (mark/unmark/reload) so the
  // renderer rebuilds its batched highlight VBO only on change, not per frame.
  static constexpr int MB_MARKS_SANITY = 1000000;
  struct MbMark {
    char lvl[16] = {0};
    int sys = 0;
    int row = -1;
    int tri = -1;                      // triangle ordinal (same enumeration as hover/pick)
    float v[3][3] = {{0.f}};           // GOAL units, emitted winding
    float nrm[3] = {0.f, 0.f, 0.f};    // unit face normal (lift direction for the highlight)
  };
  std::mutex mb_marks_mu;
  std::vector<MbMark> mb_marks_store;  // guarded by mb_marks_mu
  u32 mb_marks_gen = 0;                // guarded by mb_marks_mu; renderer's rebuild-on-change key
  std::atomic<int> mb_marks_active{0};  // == store size, published for lock-free gating
  // Frame stamp for once-per-frame passes (several bucket renderers can call render_marks in one
  // frame; the first call after a flip draws, the rest no-op). Render thread only.
  u32 mb_frame_no = 0;
  u32 mb_cur_marked = 0, mb_frame_marked = 0;  // marked triangles DRAWN last frame (== active
                                               // marks while the browser is open — the V2.4 proof)
  u32 mb_cur_gizmo_occ = 0, mb_frame_gizmo_occ = 0;  // samples that PASSED the depth test in the
                                                     // gizmo pass (GL_SAMPLES_PASSED occlusion
                                                     // query; GLES fallback ANY_SAMPLES -> 0/1)
  void mb_flip_frame_counters() {
    mb_frame_target_draws = mb_cur_target_draws;
    mb_frame_checker_binds = mb_cur_checker_binds;
    mb_frame_gizmo_prims = mb_cur_gizmo_prims;
    mb_frame_relief_x100 = mb_cur_relief_x100;
    mb_frame_checker_full = mb_cur_checker_full;
    mb_frame_target_tess = mb_cur_target_tess;
    mb_frame_gizmo_px = mb_cur_gizmo_px;
    mb_frame_nontarget_draws = mb_cur_nontarget_draws;
    mb_frame_isolated_skips = mb_cur_isolated_skips;
    mb_frame_wire = mb_cur_wire;
    mb_frame_marked = mb_cur_marked;
    mb_frame_gizmo_occ = mb_cur_gizmo_occ;
    mb_cur_marked = 0;
    mb_cur_gizmo_occ = 0;
    mb_frame_no++;
    mb_cur_target_draws = 0;
    mb_cur_checker_binds = 0;
    mb_cur_gizmo_prims = 0;
    mb_cur_relief_x100 = 0;
    mb_cur_checker_full = 0;
    mb_cur_target_tess = 0;
    mb_cur_gizmo_px = 0;
    mb_cur_nontarget_draws = 0;
    mb_cur_isolated_skips = 0;
    mb_cur_wire = 0;
    // triangle-pick completion: arm on the first flip after a request, publish on the second —
    // by then every renderer had one WHOLE frame to contribute (see the channel doc above).
    const u32 s = mb_pick_serial.load(std::memory_order_relaxed);
    if (mb_pick_arm != 0 && mb_pick_arm == s) {
      mb_pick_done.store(s, std::memory_order_release);
      mb_pick_arm = 0;
    } else if (s != mb_pick_done.load(std::memory_order_relaxed)) {
      mb_pick_arm = s;  // render thread — safe to reset the hit list with the arm
      mb_pick_hit_n = 0;
    }
  }
  // Jak's world position (GOAL units) pushed every frame via pc-set-jak-pos! for
  // the grass trample effect. w = 1.0 when valid, 0.0 before the player spawns.
  float recharged_jak_pos[4] = {0.f, 0.f, 0.f, 0.f};
  // POLISH#4 (owner 2026-07-10): adjustable LOD view distances (meters), fed from the
  // two "Recharged Settings" sliders via pc-set-grass-dists!. near = near-blade fade-out,
  // card = grass-card fade-out (pushed further out than the old fixed 62 m).
  float recharged_grass_near_dist = 30.f;
  float recharged_grass_card_dist = 95.f;
  // POLISH#5 (owner 2026-07-10): adjustable grass DENSITY, a percent scale (100 = the
  // baseline instance budget) fed from the third "Recharged Settings" slider via
  // pc-set-grass-dists! (z component). Scales the whole-level instance budget in the
  // renderer; a change re-scatters the static field. Clamped renderer-side for memory safety.
  float recharged_grass_density = 150.f;
  // Grecharged-grass-precompute-mode: PRECOMPUTED (baked day-cycle tables from <level>.grassbake,
  // cheap load) vs LIVE (full at-load scan). Same expand() path -> identical placement; falls back
  // to LIVE when no valid bake exists or a placement debug prop overrides.
  bool recharged_grass_precomputed = true;
  // Grecharged-grass-overhang: 3D drooping grass over platform edges (near LOD only; far keeps the
  // stock alpha overhang texture). Set from GOAL via pc-set-grass-overhang!. Only draws when
  // recharged_grass is also on; the droop tail of the instance buffer is simply not drawn when off.
  bool recharged_grass_overhang = true;
  // Grecharged-foliage-wind: light wind sway for jak1 palms (TIE) + shrubs. Set from GOAL via
  // pc-set-foliage-wind!. Default OFF => byte-identical stock render (no displacement / mult ×1).
  bool recharged_foliage_wind = false;
  // POLISH#4: Jak's ledge-grab point (GOAL units) pushed via pc-set-jak-ledge! while he
  // hangs on a ledge, so the ledge-top grass parts around his hands. w = 1.0 while hanging,
  // 0.0 otherwise (GOAL pushes a null vector to clear it when he lets go).
  float recharged_jak_ledge[4] = {0.f, 0.f, 0.f, 0.f};
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: runtime toggle + per-frame mood/TOD sun state (raw GOAL vectors)
  bool recharged_pbr_enable = true;
  float recharged_pbr_shadow[3] = {0.f, -1.f, 0.f};     // *time-of-day-context* current-shadow (light travel dir)
  float recharged_pbr_sun_color[3] = {1.f, 1.f, 1.f};   // mood-sun sun-color
  float recharged_pbr_ambient[3] = {0.25f, 0.25f, 0.3f}; // mood-sun env-color
  float recharged_pbr_exposure = 1.0f;
  // REOPEN #2 menu sliders: TEXTURE RELIEF (multiplier on normal-strength + POM height;
  // 1.0 = pre-slider look, shipped default 1.5) and SPECULAR INTENSITY (fused spec scale).
  // REOPEN #6 (owner playtest #4: matte is the norm): SPECULAR INTENSITY shipped default is now
  // LOW (0.15) — rough dielectrics are matte by construction (the shader matte_gate); the slider
  // only trims the residual highlight on genuinely smooth/metal texels. Owner dials up for shiny.
  float recharged_pbr_texture_relief = 1.5f;
  float recharged_pbr_spec_intensity = 0.15f;
  // REOPEN #3 DISPLACEMENT menu carousel: 0 = Off, 1 = Parallax (steep POM, default),
  // 2 = Tessellation (GLES3.2/GL4.x tess displacement, near ground/walls).
  int recharged_pbr_displacement = 1;
  // REOPEN #10 PBR ISOLATE menu carousel (DEBUG, removable): the owner's IN-MENU term
  // bisection so he can isolate the residual grass-facet source at his own vantage with no
  // adb. Stored here as the resolved u_pbr_bisect MASK (not the carousel index): 0 = BOTH
  // (nm+POM), 128 = NORMAL-MAP ONLY (POM off), 64 = PARALLAX ONLY (normal-map off),
  // 192 = NEITHER. Seeds pbr_bisect in the fused path; the debug prop/env still override.
  int recharged_pbr_isolate = 0;
  // Round-4 multi-light: *time-of-day-context* light-group 0 (soleil + lune verte + fill).
  // Pushed raw from GOAL via pc-set-pbr-lights!; scaled/normalized at the GL boundary.
  bool recharged_pbr_lg_valid = false;
  float recharged_pbr_lg_dir[3][3];    // light-travel dirs, dir0/1/2 raw from GOAL
  float recharged_pbr_lg_color[3][3];  // rgb 0..255 raw
  float recharged_pbr_lg_level[3];     // levels.x morph weight per light
  float recharged_pbr_lg_ambi[3];      // ambi color rgb 0..255 raw
  // Round-5 addendum suspect (c): the VISIBLE sun's dome direction — *sky-parms*
  // upload-data sun 0 pos (camera->sun offset, the vector sparticle-track-sun places the
  // sun sprite with). Unlike current-shadow (hard-clamped to a constant ~65 deg by
  // update-mood-shadow-direction) this tracks the real sun elevation, so shadows extend
  // opposite the on-screen sun. Zero until the first GOAL push (renderer falls back).
  float recharged_pbr_sky_sun[3] = {0.f, 0.f, 0.f};
  // Grecharged-directional-ambient (owner playtest #3, 2026-07-20): the GREEN SUN is Jak's
  // 2ND SUN (sky upload-data sun index 1, colour 0xc2,0xfe,0x78 = 194,254,120). Its REAL sky
  // position (camera->green-sun, magnitude ~ orbit dist) pushed from GOAL via
  // pc-set-pbr-green-sun! every frame. Drives the realtime green directional light + (when it
  // is the dominant/only sun above the horizon, i.e. night) the cast-shadow direction. Zero
  // until the first push (renderer treats a below-horizon / zero green sun as no contribution).
  float recharged_pbr_green_sun[3] = {0.f, 0.f, 0.f};
  // Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY realtime lighting, a clean
  // rewrite separate from the pbr-materials toggle above. recharged_rt_light_enable = master
  // (the tfrag3 sun-only path is taken only when this is on). Set from GOAL via pc-set-rt-light!.
  // Default OFF => a --pbr build with the toggle off is the existing owner-accepted
  // pbr-materials behavior; a non-pbr build has none of this (stock).
  bool recharged_rt_light_enable = false;
  // Grecharged-realtime-lighting ROUND 2: sun shadow-map QUALITY (resolution) + DISTANCE.
  // recharged_rt_shadow_res = depth-texture edge in texels (1024 Low / 2048 Med / 4096 High
  // on mobile); recharged_rt_shadow_dist = the realtime shadow range = the ortho box HALF-
  // extent in meters (box = 2x). Defaults reproduce round-1 (1024, 40 m half = 80 m box).
  // Driven from GOAL via pc-set-rt-shadow-res! / pc-set-rt-shadow-dist!, overridable by the
  // debug props debug.opengoal.rt.shadowres / .shadowdist (env OG_RT_SHADOWRES/DIST) for A/B.
  int recharged_rt_shadow_res = 2048;
  float recharged_rt_shadow_dist = 150.0f;
  float recharged_rt_shadow_strength = 0.8f;  // ROUND-5: cast-shadow darkening (0..1); shader residual = 1 - this
  // Grecharged-directional-ambient: hemisphere ambient (replaces the flat ~0.2 floor).
  bool recharged_rt_ambient_enable = true;     // ON by default (the improvement over the flat floor)
  float recharged_rt_ambient_strength = 0.2f;  // ambient base level (== the old ~0.2 flat floor)
  // Grecharged-directional-ambient ROUND 2: ambient MODEL (0 = HEMISPHERE, 1 = SH, 2 = IBL). Selectable
  // in Recharged Settings (a quality tier). Only read on the rt path; OFF==stock unaffected.
  // Default SH (1): the shipped/out-of-box directional model (supervisor 2026-07-20 — hemisphere is
  // N.y-only so it must not be the download default; SH varies over the full normal + carries the
  // daytime sky sun-glow lobe for shadowed-area form). Hemisphere stays available via the selector.
  int recharged_rt_ambient_model = 1;
  float recharged_rt_ambient_contrast = 1.0f;  // Grecharged-directional-ambient: azimuthal ambient spread (0..~1.5); owner-validated shipped default (playtest 2026-07-20: SH + strength 0.2 + contrast 1.0)
  // Grecharged-pbr-realtime-fusion DYNAMIC FOLLOW-PROBE (owner 2026-07-23): the PBR env source is
  // now ONE amortized camera-centered cubemap re-rendered from the live world (replaces the deleted
  // baked probe grid). Tier = user setting, SAME features mobile+PC (owner: no platform gating):
  // 0 = OFF (lowest = corrected procedural IBL, no capture), 1 = LOW (32px), 2 = MID (64px),
  // 3 = HIGH (128px). Amortized 1 face/frame at every tier. Driven from GOAL via
  // pc-set-follow-probe!; debug.opengoal.rt.followprobe / env OG_RT_FOLLOWPROBE force it for A/B.
  int recharged_follow_probe = 1;
#endif
  // Grecharged-hd-models: load jak2 detailed character models (Jak/Daxter/Samos/Keira, jak1-look)
  // in place of stock low-poly meshes, by reading an enhanced FR3 variant from fr3/enhanced/. Seeded
  // in C++ from persisted pc-settings before the common FR3 loads, then kept live by the GOAL push.
  // false = stock (byte-identical). Only meaningful when the build ships the enhanced FR3 set.
  bool recharged_enhanced_models = false;
  // Grecharged-ambient-occlusion: screen-space AO post-pass over the OPAQUE scene only
  // (sampled/composited at the bucket-30 hook, before any alpha bucket — alpha-cut foliage
  // and grass cards never enter the AO depth nor get darkened). Set from GOAL via
  // pc-set-ambient-occlusion!. mode 0 = OFF => byte-identical stock (renderbuffer depth,
  // zero AO GL calls). 1 = SSAO, 2 = HBAO, 3 = GTAO.
  int recharged_ao_mode = 0;
  // AO quality: 0 = low (quarter-res, few samples), 1 = medium (half-res), 2 = high
  // (full-res, full samples). Only read when recharged_ao_mode != 0.
  int recharged_ao_quality = 1;
  int recharged_ao_strength = 1;  // Grecharged-ambient-occlusion closing round: 0 weaker, 1 default, 2 stronger
};

namespace Gfx {

extern GfxGlobalSettings g_global_settings;
extern game_settings::DebugSettings g_debug_settings;

const GfxRendererModule* GetCurrentRenderer();

// Grecharged-master-toggle: the SINGLE effective-flag helper family. Every recharged
// feature gate consults its flag THROUGH these (recharged_active for bools,
// recharged_active_mode for 0==off int modes like the AO mode) so the global master —
// and the headless vanilla override — compose with every feature exactly once.
//
// Headless override (probe captures / tooling): Android system property
// debug.opengoal.recharged (desktop env OG_RECHARGED). Unset/empty = follow the
// persisted master setting; "0" = force VANILLA (master effectively OFF); any other
// integer = force recharged ON. The override never touches the saved settings.
// Cached with a 0.25 s wall-time throttle (the AmbientOcclusion AoOverride pattern).
// Header-inline on purpose: g_global_settings is defined per-platform (gfx.cpp /
// linux_arm64_runtime_compat.cpp / android_arm64_runtime_compat.cpp), so an out-of-line
// home TU shared by all three does not exist. Callers span the GL + loader threads;
// the int cache race is benign (same as AoOverride).
inline bool recharged_master_active() {
  static int s_override = -1;  // -1 = no override; 0 = force vanilla; 1 = force recharged
  static double s_last_read_s = -1.0;
  const double now =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  if (s_last_read_s < 0.0 || now - s_last_read_s >= 0.25) {
    s_last_read_s = now;
    int ov = -1;
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.recharged", buf) > 0 && buf[0]) {
      ov = (std::atoi(buf) != 0) ? 1 : 0;
    }
#else
    const char* e = std::getenv("OG_RECHARGED");
    if (e && e[0]) {
      ov = (std::atoi(e) != 0) ? 1 : 0;
    }
#endif
    if (ov != s_override) {
      lg::info("[recharged-master] override -> {} (setting {})", ov,
               g_global_settings.recharged_master ? "ON" : "OFF");
      s_override = ov;
    }
  }
  // Grecharged-mesh-browser V2.2: while the debug mesh browser is OPEN it forces the Recharged
  // path ON — its whole purpose is previewing PBR/tessellation "si existant", and with the
  // master perf-toggle saved OFF every tess/PBR preview silently reads stock (device run 10:
  // rtf_tess=0 on 15 tess-capable candidates because settings.ini had recharged-master? #f).
  // Lowest precedence: the explicit headless A/B override (prop/env) still wins both ways; the
  // flag is armed/disarmed by pc_mb_set_active, so a CLOSED browser changes nothing.
  return (s_override >= 0) ? (s_override != 0)
                           : (g_global_settings.mb_pbr_override || g_global_settings.recharged_master);
}

inline bool recharged_active(bool feature_flag) {
  return feature_flag && recharged_master_active();
}

inline int recharged_active_mode(int feature_mode) {
  return recharged_master_active() ? feature_mode : 0;
}

u32 Init(GameVersion version);
void Loop(std::function<bool()> f);
u32 Exit();

u32 vsync();
void register_vsync_callback(std::function<void()> f);
void clear_vsync_callback();
u32 sync_path();

// matching enum in kernel-defs.gc !!
enum class RendererTreeType { NONE = 0, TFRAG3 = 1, TIE3 = 2, INVALID };
bool CollisionRendererGetMask(GfxGlobalSettings::CollisionRendererMode mode, s64 mask_id);
void CollisionRendererSetMask(GfxGlobalSettings::CollisionRendererMode mode, s64 mask_id);
void CollisionRendererClearMask(GfxGlobalSettings::CollisionRendererMode mode, s64 mask_id);
void CollisionRendererSetMode(GfxGlobalSettings::CollisionRendererMode mode);

struct SplashScreen {
  std::vector<u8> data;
  int width = 0;
  int height = 0;
  std::atomic<bool> ready{false};
};
extern SplashScreen g_splash;

}  // namespace Gfx
