#pragma once

/*!
 * @file gfx.h
 * Graphics component for the runtime. Abstraction layer for the main graphics routines.
 */

#include <array>
#include <atomic>
#include <functional>
#include <memory>
#include <vector>

#include "common/common_types.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

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

  // Grecharged-grass-poc: optional procedural 3D grass on the jak1 training level.
  // Set from GOAL (-> *pc-settings* recharged-grass?) via pc-set-recharged-grass!.
  // OFF (default) == byte-identical stock rendering (the renderer hook is skipped).
  bool recharged_grass = false;
  // External-asset-root: when true, the loader looks up user PNG texture
  // replacements under <root>/custom_assets/texture_replacements at runtime.
  // Set from GOAL via pc-set-load-custom-assets!. OFF (default) == stock.
  bool load_custom_assets = false;
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
  int recharged_rt_ambient_model = 0;
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
