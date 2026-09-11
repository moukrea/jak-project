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
#include <string>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"
#include "game/graphics/grass_density_presets.h"
#include "game/graphics/origin_ablate.h"

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
// lighting-legacy-purge (2026-09-11) — LES VALEURS DE L'ANCIEN MONDE, FIGEES.
// L'owner a fait retirer dix reglages d'eclairage anterieurs a la refonte. Ils ne sont pas
// « eteints » : le champ, le pont GOAL, la rangee de menu et l'option de `recharged_gating`
// n'existent plus. Ce qu'ils portaient est desormais UNE CONSTANTE, celle que le jeu livrait.
// Toute evolution de ces valeurs appartient a l'item de la refonte nomme en regard.
namespace RechargedFixed {
constexpr float kPbrTextureRelief = 1.5f;      // ex `pbr-texture-relief`  -> pbr-per-material
constexpr float kPbrSpecIntensity = 0.15f;     // ex `pbr-specular-intensity` -> pbr-per-material
constexpr int kPbrDisplacement = 1;            // ex `pbr-displacement` : PARALLAX. Le mode 2
                                               // TESSELLATION n'a jamais ete livre.
constexpr int kRtShadowRes = 2048;             // ex `realtime-shadow-quality` -> lighting-shadows
constexpr float kRtShadowDist = 150.0f;        // ex `realtime-shadow-dist`    -> lighting-shadows
constexpr float kRtShadowStrength = 0.8f;      // ex `realtime-shadow-strength`-> lighting-shadows
constexpr float kRtAmbientStrength = 0.2f;     // ex `realtime-ambient-strength` -> lighting-bake
constexpr int kRtAmbientModel = 1;             // ex `realtime-ambient-model` : SH -> lighting-interiors
}  // namespace RechargedFixed

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
  // framerate-uncap : PLAFOND DE LA CADENCE D'AFFICHAGE, en images/s, et lui seul. Distinct
  // de `target_fps`, qui reste la REFERENCE DE TEMPS du moteur (60) : `*ticks-per-frame*`
  // (video.gc), `time-factor` / `DISPLAY_FPS_RATIO` (display.gc) et l'increment de l'horloge
  // de scene de l'overlord (srpc.cpp) en dependent, et les faire suivre la cadence AFFICHEE
  // est precisement ce qui verrouillait le jeu a 60.
  //    0 = aucun plafond configure -> le limiteur reprend `target_fps` (comportement d'origine)
  //   >0 = ce plafond, en images/s
  //   <0 = illimite
  // Pose par GOAL (`pc-set-frame-rate`), lu par `uncap::cap_fps` (game/graphics/uncap.h).
  float display_fps_cap = 0;
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

  // lighting-hdr (SPEC-refonte-lumiere §1.1 regle 1, §6.2) : LE MAITRE DE LA REFONTE LUMIERE,
  // et ce n'est PAS le master. Trois gestes d'extinction distincts et tous legitimes :
  //   recharged_master OFF   => tout le projet Recharged s'eteint (ORIGINE-TOTAL).
  //   recharged_lighting OFF => toute la refonte lumiere s'eteint, et RIEN d'autre : les
  //                             modeles HD, l'herbe, les textures, le HUD et les polices
  //                             restent (ORIGINE-LUMIERE). C'est le retour a l'eclairage
  //                             d'origine qu'un JOUEUR veut, sans payer le reste.
  //   un sous-drapeau OFF    => cette couche seule.
  // Defaut ON. Pourquoi ce drapeau existe (owner 2026-09-06) : il avait eteint « Realtime
  // Lighting » et voyait toujours les blancs brules. C'est mecanique — `recharged_rt_light_enable`
  // ne voulait pas dire « notre eclairage », il voulait dire « prendre le composite A/B plutot
  // que C/E » : l'eteindre ACTIVE le composite C (shade.glsl, `u_rt_light_on == 0 &&
  // u_pbr_mode != 0`). Il n'existait aucun interrupteur pour l'eclairage lui-meme.
  // AUCUN consommateur d'eclairage ne lit ce drapeau ni son sous-drapeau directement : ils
  // passent tous par Gfx::lighting_active(), qui compose les TROIS niveaux en un seul endroit.
  bool recharged_lighting = true;

  // water-ocean-mesh (SPEC-refonte-eau §1.2 regle 1, §7) : LE MAITRE DE LA REFONTE EAU, a cote
  // de `recharged_lighting` et sous le master. Meme contrat, meme hierarchie a trois niveaux :
  //   recharged_master OFF => tout le projet Recharged s'eteint (ORIGINE-TOTAL).
  //   recharged_water OFF  => toute la refonte eau s'eteint, et RIEN d'autre : on garde
  //                           l'eclairage Rechargé et on retrouve l'eau de Naughty Dog, bit
  //                           pour bit. C'est le mot de l'owner du 2026-09-09 : « la refonte de
  //                           l'eau doit pouvoir être toggled off individuellement aussi, ou on
  //                           retrouve l'eau vanilla. »
  //   un sous-reglage OFF  => cette couche d'eau seule (items 2 a 10 de la SPEC).
  // Defaut ON. AUCUN consommateur d'eau ne lit ce drapeau directement : ils passent tous par
  // Gfx::water_active(), qui compose les trois niveaux en un seul endroit.
  bool recharged_water = true;

  // lighting-hdr (SPEC-refonte-lumiere §4.5) : la chaine HDR. ON => le tampon de scene est
  // RGBA16F (repli R11F_G11F_B10F puis RGBA8) et la compression de plage est appliquee UNE
  // seule fois, au resolve, par le programme `tonemap`. OFF => la chaine d'origine, RGBA8 et
  // blit direct, a l'octet pres. Le mode ORIGINE (master OFF) ne consulte jamais ce drapeau.
  // Defaut ON : une correction livree derriere un drapeau eteint n'existe pas pour l'owner.
  // La rangee de menu qui l'expose est livree par l'item `lighting-presets` (SPEC §6.2).
  bool recharged_hdr = true;
  // Le genou de la courbe « Fidelite » : identite STRICTE en dessous, epaule C1 au-dessus,
  // quadratique a blanc fini. Le genou a 0,96 conserve davantage de contraste dans les
  // valeurs SDR proches du blanc ; l'epaule atteint 1,0 a l'entree 2-genou.
  float recharged_hdr_knee = 0.96f;
  // 0 = Fidelite (epaule C1, defaut), 1 = Filmique (Khronos PBR Neutral). SPEC §6.2 « Image ».
  int recharged_hdr_curve = 0;
  // Exposition du site de tone map. 1,0 = identite : « direct = 0 reproduit l'original ».
  float recharged_hdr_exposure = 1.0f;

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
  // Grecharged-managed-assets: use the DOWNLOADED texture pack (managed_assets/
  // <game>/, installed by the asset manager) when one is present. Default ON —
  // a user who downloaded a pack wants to see it. OFF falls straight back to
  // the bundled/stock textures with no re-download, so it is a real A/B switch.
  // The user drop dir still wins over it (owner's precedence rule).
  bool recharged_managed_assets = true;
  // Jak's world position (GOAL units) pushed every frame via pc-set-jak-pos! for
  // the grass trample effect. w = 1.0 when valid, 0.0 before the player spawns.
  float recharged_jak_pos[4] = {0.f, 0.f, 0.f, 0.f};
  // POLISH#4 (owner 2026-07-10): adjustable LOD view distances (meters), fed from the
  // two "Recharged Settings" sliders via pc-set-grass-dists!. near = near-blade fade-out,
  // card = grass-card fade-out (pushed further out than the old fixed 62 m).
  float recharged_grass_near_dist = 30.f;
  float recharged_grass_card_dist = 95.f;
  // Ggrass-density-presets (owner 2026-08-30): la densite n'est plus un POURCENTAGE CONTINU, c'est
  // l'INDICE d'un des cinq paliers de `grass_density_presets.h` (0 = VERY LOW .. 4 = VERY HIGH,
  // defaut 2 = MEDIUM = les 150 % livres jusqu'ici). Pousse par pc-set-grass-dists! (composante z).
  // POURQUOI CE N'EST PLUS UN FLOTTANT : le curseur pouvait demander une densite SUPERIEURE a celle
  // du bake, et cette comparaison (`density > bake_density_pct`) basculait le placement sur le
  // chemin EN DIRECT — 1 207 Mo de pointe contre 735, et la population ou les plantages ont ete
  // reproduits. Chaque palier a desormais SON bake : la densite demandee EST celle du bake charge,
  // et la comparaison n'existe plus.
  int recharged_grass_density_preset = grass_bake::kDensityPresetDefault;
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
  // Grecharged-title-logo-fullres: draw the title-screen JAK AND DAXTER logo (and the ND boot logo)
  // at NATIVE resolution while the 3D world stays at RENDER SCALE. Set from GOAL via
  // pc-set-crisp-title-logo!. Default OFF => stock pipeline.
  bool recharged_crisp_title_logo = false;
  // POLISH#4: Jak's ledge-grab point (GOAL units) pushed via pc-set-jak-ledge! while he
  // hangs on a ledge, so the ledge-top grass parts around his hands. w = 1.0 while hanging,
  // 0.0 otherwise (GOAL pushes a null vector to clear it when he lets go).
  float recharged_jak_ledge[4] = {0.f, 0.f, 0.f, 0.f};
  // lighting-legacy-purge (2026-09-11) : `recharged_mesh_subdiv_rounds` est RETIRE. La
  // pre-subdivision n'etait atteignable que sous DISPLACEMENT = 2 (TESSELLATION), un mode qui
  // n'a jamais ete livre et qui disparait avec cet item : le reglage ne pouvait plus rien
  // changer a l'image.

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: per-frame mood/TOD sun state (raw GOAL vectors). Le rendu PBR
  // n'est plus une option (lighting-legacy-purge) : il est INCONDITIONNEL sous « lighting ».
  float recharged_pbr_shadow[3] = {0.f, -1.f, 0.f};     // *time-of-day-context* current-shadow (light travel dir)
  float recharged_pbr_sun_color[3] = {1.f, 1.f, 1.f};   // mood-sun sun-color
  float recharged_pbr_ambient[3] = {0.25f, 0.25f, 0.3f}; // mood-sun env-color
  float recharged_pbr_exposure = 1.0f;
  // lighting-legacy-purge (2026-09-11) : TEXTURE RELIEF et SPECULAR INTENSITY sont figes dans
  // RechargedFixed::kPbrTextureRelief / kPbrSpecIntensity — les valeurs livrees, telles quelles.
  // lighting-legacy-purge (2026-09-11) : DISPLACEMENT est fige a RechargedFixed::kPbrDisplacement
  // (1 = PARALLAX, le POM). Le mode 2 TESSELLATION n'a jamais ete livre : il est SUPPRIME.
  // lighting-legacy-purge (2026-09-11) : PBR ISOLATE (la bissection de debug du fused path)
  // est SUPPRIME. Le masque livre valait 0 = chemin complet.
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
  // lighting-legacy-purge (2026-09-11) : MODERN MATERIALS est SUPPRIME. La rangee livrait OFF,
  // donc `u_mm_flags` valait 0 a chaque draw et la pile moderne n'a jamais touche un pixel :
  // son absence EST la valeur livree. Les shaders pbr_modern*.glsl partent avec elle.
  // Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY realtime lighting, a clean
  // rewrite separate from the pbr-materials toggle above. recharged_rt_light_enable = master
  // (the tfrag3 sun-only path is taken only when this is on). Set from GOAL via pc-set-rt-light!.
  // Default OFF => a --pbr build with the toggle off is the existing owner-accepted
  // pbr-materials behavior; a non-pbr build has none of this (stock).
  bool recharged_rt_light_enable = false;
  // lighting-legacy-purge (2026-09-11) : la QUALITE / la DISTANCE / la FORCE de l'ombre portee,
  // l'interrupteur d'ambiante, sa FORCE, son MODELE et son CONTRASTE sont RETIRES. Les cinq
  // premiers sont figes dans RechargedFixed (kRtShadowRes/Dist/Strength, kRtAmbientStrength,
  // kRtAmbientModel) ; l'ambiante est desormais inconditionnelle sous l'eclairage (elle livrait
  // deja ON) et le CONTRASTE etait un knob mort — uniform declare, aucun lecteur GLSL.
  // dead-follow-probe (2026-09-10) : `recharged_follow_probe` est SUPPRIME. Son unique
  // consommateur, FollowProbe.cpp, a disparu avec SPEC-refonte-lumiere §2.4 et sa rangee de menu
  // ENV PROBE le 2026-09-02 : le champ etait ecrit par `pc_set_follow_probe` et lu par PERSONNE
  // dans tout l'arbre. Aucun changement de comportement, personne ne le lisait. Le recensement
  // qui le prouve vit dans kmachine.cpp (`dead_probe_census`).
#endif
  // Grecharged-hd-models: load jak2 detailed character models (Jak/Daxter/Samos/Keira, jak1-look)
  // in place of stock low-poly meshes, by reading an enhanced FR3 variant from fr3/enhanced/. Seeded
  // in C++ from persisted pc-settings before the common FR3 loads, then kept live by the GOAL push.
  // false = stock (byte-identical). Only meaningful when the build ships the enhanced FR3 set.
  bool recharged_enhanced_models = false;
  // L'occlusion ambiante. Posee depuis GOAL par `pc-set-ambient-occlusion!`, SOUS l'eclairage
  // recharge (`kAoMode` a pour parent `kLighting`, recharged_gating.cpp) : sa rangee de menu vit
  // dans le sous-menu « Recharged Lighting » avec sa qualite et son intensite.
  // mode 0 = OFF => stock octet pour octet (aucune prepasse, aucun appel GL d'AO).
  // 1 = SSAO, 2 = HBAO, 3 = GTAO.
  //
  // CE N'EST PLUS UN POST-TRAITEMENT SUR L'IMAGE (lighting-ao-indirect, SPEC §4.7). L'ancien
  // chemin composait sur l'image opaque FINALE au crochet du bucket 30, apres l'encodage gamma,
  // et assombrissait donc aussi la lumiere directe — d'ou son masque de luminance. Il est
  // SUPPRIME. Aujourd'hui l'estimateur ecrit une texture R8 (AmbientOcclusion.cpp) que `shade()`
  // applique au SEUL terme indirect, en lineaire, avant le tone map.
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
// LE JEU DE REFERENCES NE PEUT PAS DEPENDRE DE LA MONTRE MURALE (item `refset-replay-stable`).
// Le cache de 0,25 s ci-dessous est une entree de temps REEL dans une decision qui atteint le
// pixel : le plan de `refset` bascule le master a chaque etape, et pendant la fenetre de cache
// deux lecteurs de la MEME image lisent deux valeurs differentes — celui qui estampille le
// regime d'un niveau (`Loader.cpp`) et celui qui resout chaque texture. Le niveau reste alors
// fige sur un melange stock/recharged, et LEQUEL depend de la charge de la machine.
// Sous `OG_REFSET` on relit donc a chaque appel. Lecteur SANS EFFET DE BORD, sur le modele de
// `Loader.cpp` `refset_deterministic()` : `refset::enabled()` construit tout son etat au premier
// appel derriere une garde non atomique, et ce fichier est inline dans 51 unites de compilation
// des deux fils. Le jeu de references est un instrument x86 (refset.h, « portee honnete »).
inline bool refset_pins_master() {
#ifdef __ANDROID__
  // lighting-hdr : ce bras rendait `false` tant que le jeu de references etait un instrument
  // x86. Il tourne desormais aussi sur l'appareil, et sans ce bypass le cache de 0,25 s
  // ramenerait EXACTEMENT la cause n°2 fermee par refset-replay-stable : deux lecteurs de la
  // meme image lisent deux valeurs du master, le niveau reste fige sur un melange
  // stock/recharged, et LEQUEL depend de la charge de la machine.
  static const bool s_on = [] {
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.refset", buf) <= 0 || !buf[0]) {
      return false;
    }
    return std::string(buf) == "capture" || std::string(buf) == "replay";
  }();
  return s_on;
#else
  static const bool s_on = [] {
    const char* e = std::getenv("OG_REFSET");
    return e && (e[0] == 'c' || e[0] == 'r') &&
           (std::string(e) == "capture" || std::string(e) == "replay");
  }();
  return s_on;
#endif
}

// lighting-hdr : lit une surcharge -1 (absente) / 0 / 1. La PROPRIETE Android d'abord, puis la
// variable d'environnement — et la variable est lue sur les DEUX plateformes, pas seulement sur
// le bureau. Pourquoi : le jeu de references bascule la configuration EN COURS DE PROCESSUS par
// `setenv` (refset.cpp `put_env`). Un lecteur Android qui ne verrait que la propriete resterait
// fige sur la valeur posee au lancement, et le plan ne changerait jamais de phase — le port du
// rejeu sur l'appareil rendrait 16 fois la meme image sans que rien ne le signale.
// La propriete garde la priorite : c'est le geste explicite du harnais, il doit pouvoir epingler.
inline int read_override(const char* prop, const char* env) {
#ifdef __ANDROID__
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    return (std::atoi(buf) != 0) ? 1 : 0;
  }
#else
  (void)prop;
#endif
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      return (std::atoi(e) != 0) ? 1 : 0;
    }
  }
  return -1;
}

namespace detail {
struct RechargedFrameState {
  bool active = false;
  bool master = false;
  bool lighting = false;
  bool water = false;
};
inline thread_local RechargedFrameState recharged_frame_state;
}  // namespace detail

inline bool read_recharged_master_active() {
#if AUTOPORT_ORIGIN_ABLATE
  // BINAIRE-TEMOIN DE `lighting-origin-bitexact` (game/graphics/origin_ablate.h). La couche
  // Recharged n'est pas ETEINTE ici, elle est ABSENTE : ce `return` constant supprime a la
  // COMPILATION les ~50 sites qui passent par ce maitre. C'est ce qui fait de la reference
  // « un build sans la couche » et non « le meme build avec le drapeau a zero ».
  return false;
#else
  static int s_override = -1;  // -1 = no override; 0 = force vanilla; 1 = force recharged
  static double s_last_read_s = -1.0;
  const double now =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  if (s_last_read_s < 0.0 || refset_pins_master() || now - s_last_read_s >= 0.25) {
    s_last_read_s = now;
    const int ov = read_override("debug.opengoal.recharged", "OG_RECHARGED");
    if (ov != s_override) {
      lg::info("[recharged-master] override -> {} (setting {})", ov,
               g_global_settings.recharged_master ? "ON" : "OFF");
      s_override = ov;
    }
  }
  // mesh-browser-removal (2026-09-11) : le terme `mb_pbr_override ||` du navigateur de maillages
  // supprime ici valait TOUJOURS false hors du navigateur — le comportement livre est inchange.
  return (s_override >= 0) ? (s_override != 0) : g_global_settings.recharged_master;
#endif
}

inline bool recharged_master_active() {
#if AUTOPORT_ORIGIN_ABLATE
  return false;
#else
  return detail::recharged_frame_state.active ? detail::recharged_frame_state.master
                                            : read_recharged_master_active();
#endif
}

inline bool recharged_active(bool feature_flag) {
  return feature_flag && recharged_master_active();
}

inline int recharged_active_mode(int feature_mode) {
  return recharged_master_active() ? feature_mode : 0;
}

// lighting-hdr (SPEC §1.1 regle 1, §4.5, §4.15) : le NIVEAU INTERMEDIAIRE de la hierarchie.
// Meme patron d'override que le master, meme bypass de cache sous OG_REFSET, pour la meme
// raison : le jeu de references bascule ce drapeau a chaque etape et deux lecteurs de la meme
// image doivent lire la meme valeur. La propriete/variable epingle LE DRAPEAU, jamais la
// composition : le master garde son droit de veto au-dessus.
inline bool read_recharged_lighting_active() {
#if AUTOPORT_ORIGIN_ABLATE
  return false;  // voir recharged_master_active() ci-dessus
#else
  static int s_override = -1;  // -1 = pas d'override ; 0 = force l'eclairage d'origine ; 1 = force la refonte
  static double s_last_read_s = -1.0;
  const double now =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  if (s_last_read_s < 0.0 || refset_pins_master() || now - s_last_read_s >= 0.25) {
    s_last_read_s = now;
    const int ov = read_override("debug.opengoal.lighting", "OG_LIGHTING");
    if (ov != s_override) {
      lg::info("[recharged-lighting] override -> {} (setting {})", ov,
               g_global_settings.recharged_lighting ? "ON" : "OFF");
      s_override = ov;
    }
  }
  const bool on = (s_override >= 0) ? (s_override != 0) : g_global_settings.recharged_lighting;
  return on && recharged_master_active();
#endif
}

inline bool recharged_lighting_active() {
#if AUTOPORT_ORIGIN_ABLATE
  return false;
#else
  return detail::recharged_frame_state.active ? detail::recharged_frame_state.lighting
                                            : read_recharged_lighting_active();
#endif
}

// water-ocean-mesh (SPEC-refonte-eau §1.2 regle 1, §7) : le NIVEAU INTERMEDIAIRE de l'eau, jumeau
// exact de `read_recharged_lighting_active()`. Meme patron d'override (propriete
// `debug.opengoal.water` puis env `OG_WATER`), meme bypass de cache sous OG_REFSET, meme veto du
// master au-dessus. Une preuve d'eau EPINGLE son regime avec ces deux boutons : un drapeau non
// epingle, c'est le reglage laisse par un autre item qui decide.
inline bool read_recharged_water_active() {
#if AUTOPORT_ORIGIN_ABLATE
  return false;  // voir recharged_master_active() ci-dessus
#else
  static int s_override = -1;  // -1 = pas d'override ; 0 = force l'eau d'origine ; 1 = force la refonte
  static double s_last_read_s = -1.0;
  const double now =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  if (s_last_read_s < 0.0 || refset_pins_master() || now - s_last_read_s >= 0.25) {
    s_last_read_s = now;
    const int ov = read_override("debug.opengoal.water", "OG_WATER");
    if (ov != s_override) {
      lg::info("[recharged-water] override -> {} (setting {})", ov,
               g_global_settings.recharged_water ? "ON" : "OFF");
      s_override = ov;
    }
  }
  const bool on = (s_override >= 0) ? (s_override != 0) : g_global_settings.recharged_water;
  return on && recharged_master_active();
#endif
}

inline bool recharged_water_active() {
#if AUTOPORT_ORIGIN_ABLATE
  return false;
#else
  return detail::recharged_frame_state.active ? detail::recharged_frame_state.water
                                              : read_recharged_water_active();
#endif
}

// Chaque render conserve les memes maitres jusqu'a son retour, y compris au recensement HDR.
class RechargedFrameScope {
 public:
  RechargedFrameScope() : m_previous(detail::recharged_frame_state) {
    const bool master = read_recharged_master_active();
    detail::recharged_frame_state = {true, master, false, false};
    detail::recharged_frame_state.lighting = read_recharged_lighting_active();
    detail::recharged_frame_state.water = read_recharged_water_active();
  }
  ~RechargedFrameScope() { detail::recharged_frame_state = m_previous; }

  RechargedFrameScope(const RechargedFrameScope&) = delete;
  RechargedFrameScope& operator=(const RechargedFrameScope&) = delete;

 private:
  detail::RechargedFrameState m_previous;
};

// LE seul composeur des trois niveaux (master > eclairage > sous-drapeau). Tout consommateur
// d'une couche d'ECLAIRAGE passe par ici. Un sous-reglage d'eclairage qui ne consulterait que
// `recharged_active()` laisserait la refonte tourner alors que le joueur l'a eteinte : c'est
// exactement le defaut que l'owner a trouve le 2026-09-06 (SPEC §4.15 point 1).
inline bool lighting_active(bool feature_flag) {
  return feature_flag && recharged_lighting_active();
}

inline int lighting_active_mode(int feature_mode) {
  return recharged_lighting_active() ? feature_mode : 0;
}

// water-ocean-mesh : LE seul composeur des trois niveaux pour l'EAU (master > eau > sous-reglage).
// Tout consommateur d'une couche d'eau passe par ici, jamais par `g_global_settings.recharged_water`
// ni par `recharged_active()` : ce dernier laisserait la refonte d'eau tourner alors que le joueur
// vient de l'eteindre. Tant qu'un item n'a pas de sous-reglage, il appelle `water_active(true)`.
inline bool water_active(bool feature_flag) {
  return feature_flag && recharged_water_active();
}

inline int water_active_mode(int feature_mode) {
  return recharged_water_active() ? feature_mode : 0;
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
