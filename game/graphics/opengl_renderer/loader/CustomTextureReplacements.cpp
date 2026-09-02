#include "CustomTextureReplacements.h"

#include <atomic>
#include <cctype>
#include <cstring>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#ifdef OG_FEAT_PBR
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <unordered_map>
#include <vector>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
#endif

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/Ktx2Subset.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/GpuCaps.h"
#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"
#include "game/runtime.h"

#include "third-party/json.hpp"
#include "third-party/stb_image/stb_image.h"

#ifdef OG_FEAT_PBR
// Grecharged-materials-modern-parity: the modern shader chunk is gated on `u_pbr_debug == 0`
// (pbr_modern.glsl:40), so a debug visualisation being armed SKIPS the whole chunk while our
// counters keep rising. The diag section publishes the mode so that hole is never silent.
// Declared here at GLOBAL scope rather than included: background_common.h (which declares it at
// :376) includes THIS header at its :15, so including it back would close an include cycle.
int pbr_debug_mode();
#endif

namespace custom_tex {

namespace {
// Lazily-built index of replacement PNGs. Two keys map to each file: the
// relative path without extension (e.g. "village1-tpage-2/sand-01") and the
// bare filename without extension ("sand-01").
struct ScanState {
  bool scanned = false;
  bool last_user_enable = false;
  bool last_bundled_enable = false;
  // USER drop dir (get_custom_assets_replacements_dir) — always wins over bundled.
  std::map<std::string, fs::path> user_index;
  // Package-BUNDLED first-party set (get_bundled_recharged_textures_dir).
  std::map<std::string, fs::path> bundled_index;
} g_state;

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: registry of created PBR material GL textures, keyed by
// the texture debug-name. Populated by the loader (add_texture), read per-level by
// the tfrag renderer.
std::unordered_map<std::string, PbrMaterialMaps> g_pbr_materials;

// [pom] DEVICE DIAGNOSTIC state. Only the three inputs the parallax law consumes are kept (the GL
// ids would be meaningless in a text dump), keyed by name in a std::map so the emitted block is in
// a stable, diffable order across boots.
struct PomDiagEntry {
  float uv_per_m = 0.5f;
  float lambda_tiles = 0.25f;
  int mode = 0;  // the u_pbr_mode bitmask this material resolves to
};
std::map<std::string, PomDiagEntry> g_pom_diag;
u32 g_pom_diag_generation = 0;

// EXACTLY PbrDrawBinder::set()'s `want` bitmask — the value that reaches u_pbr_mode, so the dump
// reports the branch condition the shader actually tests rather than a paraphrase of it.
int pom_mode_bits(const PbrMaterialMaps& m) {
  return (m.normal_tex ? 1 : 0) | (m.rough_tex ? 2 : 0) | (m.metal_tex ? 4 : 0) |
         (m.ao_tex ? 8 : 0) | (m.height_tex ? 16 : 0) | (m.specular_tex ? 32 : 0) |
         (m.emissive_tex ? 64 : 0);
}

// ---------------------------------------------------------------------------------------------
// CPU MIRROR of the shipped parallax amplitude law, one material at one slider position. It is
// pom_depth_uv() from shaders/pbr_helpers.glsl transcribed constant for constant and in the SAME
// ORDER, plus the two offset rails pbr_fused.glsl builds pom_cap from. THIS MUST BE CHANGED IN
// LOCKSTEP WITH pom_depth_uv() (and with the pom_cap min() in pbr_fused.glsl): the [pom] and [amp]
// blocks below are only worth reading while the two agree, and a stale mirror is exactly what made
// the round-20/21 numbers describe a render that no longer existed.
// Every intermediate is kept, not just the result, because the question the owner and the
// supervisor actually ask is "WHICH term bounds the amplitude?" — the argmins answer it.
struct PomLaw {
  float rel = 0.f;    // the relief slider, 0..3 (height_scale * 20)
  float drive = 0.f;  // pow(rel, PBR_DRIVE_EXP), PBR_DRIVE_EXP = 1.4 => drive(1) == 1 exactly
  float hs = 0.f;     // 0.05 * drive: the effective height scale (== u_pbr_height_scale at rel 1)
  float amp_base = 0.f;             // hs * POM_DEPTH_K * lambda_world_m, before any cap
  float cap_ratio = 0.f;            // POM_DEPTH_MAX_RATIO * lambda_world_m ("never a spike field")
  float cap_abs = 0.f;              // POM_DEPTH_MAX_M * drive ("never deeper than a step")
  float amp_floor = 0.f;            // 0.005 * rel
  float amp_m = 0.f;                // the amplitude that survives all four terms, in metres
  const char* amp_argmin = "base";  // which of base/ratio/abs/floor produced amp_m
  float depth_uv = 0.f;             // amp_m * uv_per_m: what the shader marches
  float cap_tan = 0.f;              // POM_MAX_TAN * depth_uv
  float cap_feat = 0.f;             // POM_MAX_FEATURE_FRAC * drive * lambda_world_m * uv_per_m
  float cap = 0.f;                  // min of the two rails: the marched offset's ceiling, in UV
  const char* cap_argmin = "tan";   // "tan" or "feat", whichever rail is the smaller
};

PomLaw pom_law_eval(float rel, float lam_m, float upm) {
  PomLaw r;
  r.rel = rel;
  r.drive = std::pow(std::max(rel, 0.0f), 1.4f);  // PBR_DRIVE_EXP
  r.hs = 0.05f * r.drive;
  r.amp_base = r.hs * 5.0f * lam_m;  // POM_DEPTH_K = 5
  r.cap_ratio = 1.25f * lam_m;       // POM_DEPTH_MAX_RATIO = 1.25
  r.cap_abs = 0.15f * r.drive;       // POM_DEPTH_MAX_M = 0.15, ROUND 22: * drive
  r.amp_floor = 0.005f * rel;
  // The min/min/max chain of pom_depth_uv(), evaluated in order so the winner is the term the
  // shader's own arithmetic would settle on.
  r.amp_m = r.amp_base;
  r.amp_argmin = "base";
  if (r.cap_ratio < r.amp_m) {
    r.amp_m = r.cap_ratio;
    r.amp_argmin = "ratio";
  }
  if (r.cap_abs < r.amp_m) {
    r.amp_m = r.cap_abs;
    r.amp_argmin = "abs";
  }
  if (r.amp_floor > r.amp_m) {
    r.amp_m = r.amp_floor;
    r.amp_argmin = "floor";
  }
  r.depth_uv = r.amp_m * upm;
  // pbr_fused.glsl's pom_cap. ROUND 23: the feature rail is multiplied by the same drive as the
  // tan rail, so neither of them is drive-independent any more and the ratio between two slider
  // positions is the drive ratio at BOTH — that is what the [amp] block measures.
  r.cap_tan = 2.0f * r.depth_uv;              // POM_MAX_TAN = 2
  r.cap_feat = 1.5f * r.drive * lam_m * upm;  // POM_MAX_FEATURE_FRAC = 1.5, ROUND 23: * drive
  r.cap = std::min(r.cap_tan, r.cap_feat);
  r.cap_argmin = (r.cap_tan <= r.cap_feat) ? "tan" : "feat";
  return r;
}

// ---------------------------------------------------------------------------------------------
// [cover] ROUND 21 DISPLACEMENT COVERAGE state (owner bug B: "des chunks entiers (LA PLUPART) sont
// juste PLATS"). Fixed storage, plain relaxed atomics, no allocation: written by the GL thread from
// inside the per-PBR-draw bind (so it is never touched when PBR is off) and read by the kernel
// thread's diag writer. Two frames are kept: the one being accumulated and the last COMPLETED one,
// which is what the dump reports — a mid-frame snapshot would under-count by construction.
enum CoverCounter { kCovDraws = 0, kCovHeight, kCovTess, kCovPom, kCovNone, kCovN };
constexpr int kCoverSlots = 8;
// One small text write every ~5 s at 60 fps (see pbr_coverage_generation) instead of one per frame.
constexpr u32 kCoverPublishEveryFrames = 300;

struct CoverSlot {
  // String LITERAL supplied by the renderer (static storage duration), so storing the pointer is
  // safe and the common case compares by pointer. nullptr = free slot.
  std::atomic<const char*> name{nullptr};
  std::atomic<u32> c[kCovN] = {};
};
struct CoverFrame {
  CoverSlot renderers[kCoverSlots];  // "tfrag" / "tie" / any future PBR-capable renderer
  CoverSlot kinds[kCoverSlots];      // tfrag tree kind names ("normal", "trans", "water", ...)
  std::atomic<u32> total[kCovN] = {};
};
CoverFrame g_cover_cur;   // frame being accumulated
CoverFrame g_cover_last;  // last COMPLETED frame — the one the dump reports
std::atomic<u64> g_cover_cur_frame{~0ull};
std::atomic<u64> g_cover_last_frame{0};
std::atomic<u32> g_cover_generation{0};
std::atomic<u32> g_cover_rolls{0};
std::atomic<bool> g_cover_any{false};

// Find (or claim) the slot for a label. GL thread only, so no CAS is needed; a full table drops the
// extra label rather than mis-attributing its draws to someone else's row.
CoverSlot* cover_slot(CoverSlot* table, const char* name) {
  if (!name) {
    return nullptr;
  }
  for (int i = 0; i < kCoverSlots; i++) {
    const char* n = table[i].name.load(std::memory_order_relaxed);
    if (n == name || (n && strcmp(n, name) == 0)) {
      return &table[i];
    }
    if (!n) {
      table[i].name.store(name, std::memory_order_relaxed);
      return &table[i];
    }
  }
  return nullptr;
}

// Publish the frame that just ended and zero the accumulator. Labels are KEPT in the accumulator so
// a renderer that happens to draw nothing next frame still reports its (zero) row.
void cover_roll(u64 new_frame) {
  const u64 done = g_cover_cur_frame.exchange(new_frame, std::memory_order_relaxed);
  if (done == ~0ull) {
    return;  // first draw ever: nothing accumulated yet, so there is no completed frame to publish
  }
  for (int i = 0; i < kCovN; i++) {
    g_cover_last.total[i].store(g_cover_cur.total[i].exchange(0, std::memory_order_relaxed),
                                std::memory_order_relaxed);
  }
  for (int t = 0; t < 2; t++) {
    CoverSlot* src = t ? g_cover_cur.kinds : g_cover_cur.renderers;
    CoverSlot* dst = t ? g_cover_last.kinds : g_cover_last.renderers;
    for (int i = 0; i < kCoverSlots; i++) {
      dst[i].name.store(src[i].name.load(std::memory_order_relaxed), std::memory_order_relaxed);
      for (int j = 0; j < kCovN; j++) {
        dst[i].c[j].store(src[i].c[j].exchange(0, std::memory_order_relaxed),
                          std::memory_order_relaxed);
      }
    }
  }
  g_cover_last_frame.store(done, std::memory_order_relaxed);
  g_cover_any.store(true, std::memory_order_relaxed);
  if ((g_cover_rolls.fetch_add(1, std::memory_order_relaxed) + 1) % kCoverPublishEveryFrames == 0) {
    g_cover_generation.fetch_add(1, std::memory_order_relaxed);
  }
}

void cover_bump(CoverSlot* s, bool has_height, int bucket) {
  if (!s) {
    return;
  }
  s->c[kCovDraws].fetch_add(1, std::memory_order_relaxed);
  if (has_height) {
    s->c[kCovHeight].fetch_add(1, std::memory_order_relaxed);
    s->c[bucket].fetch_add(1, std::memory_order_relaxed);
  }
}

u32 cover_read(const std::atomic<u32>* c, int i) {
  return c[i].load(std::memory_order_relaxed);
}

// One "[cover] renderer=<name>" row of the LAST COMPLETED frame. `pad` reproduces the requested
// column alignment; a missing renderer prints its zero row so the block always answers for both.
std::string cover_renderer_line(const char* name, const char* pad) {
  u32 c[kCovN] = {0, 0, 0, 0, 0};
  for (int i = 0; i < kCoverSlots; i++) {
    const char* n = g_cover_last.renderers[i].name.load(std::memory_order_relaxed);
    if (n && strcmp(n, name) == 0) {
      for (int j = 0; j < kCovN; j++) {
        c[j] = cover_read(g_cover_last.renderers[i].c, j);
      }
      break;
    }
  }
  return fmt::format("[cover] renderer={}{}pbr_height={} disp_tess={} disp_pom={} disp_none={}\n",
                     name, pad, c[kCovHeight], c[kCovTess], c[kCovPom], c[kCovNone]);
}
#endif

std::string normalize_key(std::string key) {
  // filesystem separators may differ across platforms; the debug tpage/name
  // keys use forward slashes.
  for (auto& c : key) {
    if (c == '\\') {
      c = '/';
    }
  }
  return key;
}

// Scan one replacements root into an index. Keys per file: the relative path without
// extension ("village1-tpage-2/sand-01"), the bare stem ("sand-01"), and — for nested
// per-texture layouts like <tpage>/<tex>/<tex>.png (the committed first-party set) —
// "<top-level-dir>/<stem>" so the exact tpage/name lookup still hits without relying on
// the bare-name fallback. A leading "texture_replacements/" wrapper (how internet packs
// ship: texture_replacements/<tpage>/<name>.png) is stripped before key derivation, so
// wrapped and unwrapped layouts produce the same keys on both the user and bundled sides.
// Gshield-load-and-crash: `ext` (lowercase, with the dot) selects the tier's file type. The
// PNG tiers pass the default and are therefore untouched: ".png"/".PNG" are exactly the two
// spellings accepted before. The PRE-BAKED tier passes ".ktx2" and gets the SAME key
// derivation — which is the point, since it indexes the same tree under different extensions.
int scan_dir(const fs::path& dir,
             std::map<std::string, fs::path>& index,
             const char* ext = ".png") {
  if (!fs::exists(dir)) {
    return 0;
  }
  std::string ext_upper(ext);
  for (auto& c : ext_upper) {
    c = (char)std::toupper((unsigned char)c);
  }
  int file_count = 0;
  for (const auto& entry : fs::recursive_directory_iterator(dir)) {
    if (!entry.is_regular_file()) {
      continue;
    }
    const auto& p = entry.path();
    if (p.extension() != ext && p.extension() != ext_upper) {
      continue;
    }
    file_count++;
    auto rel = fs::relative(p, dir);
    rel.replace_extension();
    std::string rel_key = normalize_key(rel.string());
    index[rel_key] = p;
    // Internet texture packs ship wrapped as texture_replacements/<tpage>/... (the upstream
    // OpenGOAL convention). Strip the wrapper so the same <tpage>/<name> keys come out as for
    // an unwrapped layout — the user and bundled sides share this exact derivation.
    std::string sub_key = rel_key;
    constexpr const char* kWrapper = "texture_replacements/";
    if (sub_key.rfind(kWrapper, 0) == 0) {
      sub_key = sub_key.substr(std::string(kWrapper).size());
      if (!sub_key.empty() && index.find(sub_key) == index.end()) {
        index[sub_key] = p;
      }
    }
    std::string bare_key = p.stem().string();
    // "<tpage>/<stem>" for nested layouts (first path component + stem).
    auto slash = sub_key.find('/');
    if (slash != std::string::npos) {
      std::string tpage_key = sub_key.substr(0, slash) + "/" + bare_key;
      if (tpage_key != sub_key && index.find(tpage_key) == index.end()) {
        index[tpage_key] = p;
      }
    }
    // don't clobber a more-specific relative key with a bare-name collision
    if (index.find(bare_key) == index.end()) {
      index[bare_key] = p;
    }
  }
  return file_count;
}

// Exact tpage/name key first, then the bare-name fallback. Returns nullptr on miss.
const fs::path* find_key(const std::map<std::string, fs::path>& index,
                         const std::string& exact_key,
                         const std::string& bare_key) {
  auto it = index.find(exact_key);
  if (it == index.end()) {
    it = index.find(bare_key);
    if (it == index.end()) {
      return nullptr;
    }
  }
  return &it->second;
}

void ensure_scanned() {
  const bool user_on = Gfx::recharged_active(Gfx::g_global_settings.load_custom_assets);
  // The bundled set serves two consumers (base swaps gated by recharged_textures, PBR maps
  // gated by the PBR path) — scan it whenever the master is up; per-lookup gates pick sources.
  const bool bundled_on = Gfx::recharged_master_active();
  // Rescan on any gate transition so a freshly-dropped directory is picked up.
  if (g_state.scanned && g_state.last_user_enable == user_on &&
      g_state.last_bundled_enable == bundled_on) {
    return;
  }
  g_state.last_user_enable = user_on;
  g_state.last_bundled_enable = bundled_on;
  g_state.scanned = true;
  g_state.user_index.clear();
  g_state.bundled_index.clear();

  const auto user_dir = file_util::get_custom_assets_replacements_dir(g_game_version);
  const int user_count = scan_dir(user_dir, g_state.user_index);
  const auto bundled_dir = file_util::get_bundled_recharged_textures_dir(g_game_version);
  const int bundled_count = scan_dir(bundled_dir, g_state.bundled_index);

  lg::info("custom texture replacements: {} user files in {}, {} bundled files in {}",
           user_count, user_dir.string(), bundled_count, bundled_dir.string());
}
}  // namespace

std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name) {
  const bool user_on = Gfx::recharged_active(Gfx::g_global_settings.load_custom_assets);
  const bool bundled_on = Gfx::recharged_active(Gfx::g_global_settings.recharged_textures);
  if (!user_on && !bundled_on) {
    return std::nullopt;
  }
  ensure_scanned();

  const std::string exact_key = normalize_key(tpage_name + "/" + tex_name);
  // PRECEDENCE (owner): user custom_assets > bundled recharged > stock.
  const fs::path* path = user_on ? find_key(g_state.user_index, exact_key, tex_name) : nullptr;
  const char* src = "user";
  if (!path && bundled_on) {
    path = find_key(g_state.bundled_index, exact_key, tex_name);
    src = "bundled";
  }
  if (!path) {
    return std::nullopt;
  }

  int w = 0, h = 0;
  auto* data = stbi_load(path->string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
  if (!data) {
    lg::warn("custom texture replacement: failed to load {}", path->string());
    return std::nullopt;
  }

  ReplacementImage out;
  out.w = w;
  out.h = h;
  out.src = src;
  out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(out.rgba.data(), data, out.rgba.size());
  stbi_image_free(data);

  lg::info("custom texture replacement ({}): {} <- {}", src, exact_key, path->string());
  return out;
}

// Deterministic mirror of lookup()'s winning source — no pixel load.
BaseSource base_source(const std::string& tpage_name, const std::string& tex_name) {
  const bool user_on = Gfx::recharged_active(Gfx::g_global_settings.load_custom_assets);
  const bool bundled_on = Gfx::recharged_active(Gfx::g_global_settings.recharged_textures);
  if (!user_on && !bundled_on) {
    return BaseSource::Stock;
  }
  ensure_scanned();
  const std::string exact_key = normalize_key(tpage_name + "/" + tex_name);
  if (user_on && find_key(g_state.user_index, exact_key, tex_name)) {
    return BaseSource::User;
  }
  if (bundled_on && find_key(g_state.bundled_index, exact_key, tex_name)) {
    return BaseSource::Bundled;
  }
  return BaseSource::Stock;
}

// ===============================================================================================
// Gshield-load-and-crash — THE PRE-BAKED (ASTC KTX2) TIER
//
// Same images as the bundled PNG tier, already GPU-compressed and already mipmapped offline by
// tools/bake_recharged_textures.py. Nothing here decodes: no stbi_load, no glGenerateMipmap, and
// no CPU measurement pass — the statistics the PNG path used to compute from decoded pixels are
// read from the <material>.stats.json the bake wrote next to the textures.
//
// MEASURED reason (SHIELD, 2026-08-26): `stage texture took 1799 ms` is ONE add_texture. The mass
// is inside the atom — a 2048x2048 PNG decode per map (151-330 ms), each map decoded TWICE (probe
// pass + re-fetch), then glGenerateMipmap (68-235 ms). The KTX2 path already in this build serves
// the same material in 87 ms, and keeps a compressed image on the GPU instead of 16 MiB of RGBA8.
// ===============================================================================================
namespace {

// One subdirectory per GPU profile under <...>_baked/. Only "astc" is produced today; the name
// is also what the two hit lines print, so a logcat can be counted per profile.
constexpr const char* kBakedProfile = "astc";

struct BakedState {
  // The PNG scan above is lock-free because it predates the managed tier; this one is not.
  // add_texture runs on whichever thread owns the GL context at the time (main thread at boot,
  // loader thread during streaming), which is exactly the race ManagedAssets.cpp locks for.
  std::mutex mutex;
  bool scanned = false;
  bool last_enable = false;
  std::map<std::string, fs::path> index;  // same key shapes as scan_dir()
  // Parsed <material>.stats.json documents, keyed by absolute sidecar path. A null value is a
  // NEGATIVE cache entry (missing or unreadable), so the warning is printed once per material
  // instead of once per map.
  std::map<std::string, nlohmann::json> sidecars;
} g_baked;

// The capability this tier hangs on. gpu_caps::detect() queries the live context ONCE (the
// renderer's init does it: opengl.cpp / android_gfx.cpp, which is where the
// "gpu caps: GLES 3.2 ... astc=true -> asset profile 'android-astc'" line comes from) and caches
// the result, so this is a struct field read, not a GL call.
bool baked_gpu_reads_astc() {
  // MESURE, 2026-08-26 (Gmemory-ceiling-and-crash), course de non-regression x86 : le pilote
  // de bureau annonce `astc=true` (GL 4.6), donc ce niveau pre-cuit N'ETAIT PAS inerte sur le
  // bureau — 28 lignes `custom texture BAKED` dans une course x86, alors que le commentaire de
  // ce fichier ET celui de LoaderStages.cpp affirmaient le contraire. Un commentaire n'est pas
  // une preuve : c'est la course qui a tranche.
  //
  // La capacite ne suffit donc pas comme garde, il faut le PROFIL. `preferred_profile()`
  // (GpuCaps.cpp:72-92) applique deja exactement cette regle a l'ETC2, avec la meme raison
  // ecrite : « Deliberately NOT android-etc2 on desktop: that would be software decompression
  // on most desktop drivers ». Un bureau qui a du BC doit lire du BC ; le seul niveau pre-cuit
  // qui existe est en ASTC, donc il ne s'applique qu'aux GPU dont le profil EST l'ASTC.
  // Effet : le chemin PNG du bureau redevient ce que la conception disait qu'il etait.
  return gpu_caps::detect().astc_ldr && gpu_caps::preferred_profile() == "android-astc";
}

// Scan gate: the MASTER, exactly like the bundled PNG index (ensure_scanned's `bundled_on`).
// The per-lookup gates below are the finer ones (base = recharged_textures, maps = master).
void ensure_baked_scanned_locked() {
  const bool on = Gfx::recharged_master_active() && baked_gpu_reads_astc();
  if (g_baked.scanned && g_baked.last_enable == on) {
    return;
  }
  g_baked.scanned = true;
  g_baked.last_enable = on;
  g_baked.index.clear();
  g_baked.sidecars.clear();
  if (!on) {
    return;
  }
  const auto dir = file_util::get_bundled_recharged_textures_baked_dir(g_game_version,
                                                                       kBakedProfile);
  const int count = scan_dir(dir, g_baked.index, ".ktx2");
  lg::info("baked recharged textures ({}): {} files ({} keys) in {}", kBakedProfile, count,
           (int)g_baked.index.size(), dir.string());
}

// The sidecar of a baked map is <its own directory>/<that directory's name>.stats.json — the
// layout the bake tool writes (<tpage>/<material>/<material>.stats.json). Returns nullptr when
// it is missing or unreadable; the caller then declines the whole material.
const nlohmann::json* baked_sidecar_locked(const fs::path& ktx2_path) {
  const auto dir = ktx2_path.parent_path();
  const auto sidecar = dir / (dir.filename().string() + ".stats.json");
  const auto key = sidecar.string();
  auto it = g_baked.sidecars.find(key);
  if (it == g_baked.sidecars.end()) {
    nlohmann::json doc;  // null on any failure => negative cache entry
    if (!fs::exists(sidecar)) {
      lg::warn(
          "baked recharged textures: no sidecar {} — the PBR statistics have nowhere to come "
          "from without a decode, so this material falls back to PNG",
          sidecar.string());
    } else {
      try {
        doc = nlohmann::json::parse(file_util::read_text_file(sidecar));
      } catch (const std::exception& e) {
        doc = nlohmann::json();
        lg::warn("baked recharged textures: unreadable sidecar {}: {} — falling back to PNG",
                 sidecar.string(), e.what());
      }
    }
    it = g_baked.sidecars.emplace(key, std::move(doc)).first;
  }
  return it->second.is_null() ? nullptr : &it->second;
}

// What the shader must be told about the payload's channels. NEVER "rg": the bake stores full
// RGB normals, and "rg" would make the shader reconstruct Z and change the render.
const char* baked_channels(const std::string& suffix) {
  if (suffix.empty()) {
    return "rgba";  // base colour
  }
  if (suffix == "_normal" || suffix == "_specular" || suffix == "_emissive") {
    return "rgb";
  }
  return "r";  // _roughness / _height / _metallic / _ao — sampled as .r and nothing else
}

// Load one baked file. `suffix` is "" for the base and "_<kind>" for a companion map; it is also
// the key the sidecar files its entry under ("base" for the empty one).
std::optional<managed_assets::CompressedTex> baked_load(const std::string& tpage_name,
                                                        const std::string& tex_name,
                                                        const std::string& suffix,
                                                        const char* log_what) {
  if (!baked_gpu_reads_astc()) {
    return std::nullopt;
  }
  const std::string name = tex_name + suffix;
  const std::string exact_key = normalize_key(tpage_name + "/" + name);

  std::lock_guard<std::mutex> lock(g_baked.mutex);
  ensure_baked_scanned_locked();
  const fs::path* found = find_key(g_baked.index, exact_key, name);
  if (!found) {
    return std::nullopt;
  }
  const fs::path path = *found;

  // STATISTICS FIRST. Without the sidecar the POM relief would be silently wrong and nobody
  // would see it, so a material with no readable sidecar is declined outright — PNG, which
  // measures them, is the better answer.
  const nlohmann::json* doc = baked_sidecar_locked(path);
  if (!doc) {
    return std::nullopt;
  }
  const auto maps_it = doc->find("maps");
  if (maps_it == doc->end() || !maps_it->is_object()) {
    lg::warn("baked recharged textures: sidecar for {} has no \"maps\" object — falling back",
             path.string());
    return std::nullopt;
  }
  const auto entry_it = maps_it->find(suffix.empty() ? std::string("base") : suffix);
  if (entry_it == maps_it->end() || !entry_it->is_object()) {
    // The file exists but the bake never described it: treat it as a MISS, not as a texture
    // with default statistics.
    lg::warn("baked recharged textures: {} is not described by its sidecar — falling back",
             path.string());
    return std::nullopt;
  }

  managed_assets::CompressedTex out;
  {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
      lg::warn("baked recharged textures: cannot open {} — falling back to PNG", path.string());
      return std::nullopt;
    }
    f.seekg(0, std::ios::end);
    const std::streamoff len = f.tellg();
    f.seekg(0, std::ios::beg);
    if (len <= 0) {
      lg::warn("baked recharged textures: empty file {} — falling back to PNG", path.string());
      return std::nullopt;
    }
    out.payload.resize((size_t)len);
    f.read((char*)out.payload.data(), len);
    if (!f) {
      lg::warn("baked recharged textures: short read on {} — falling back to PNG", path.string());
      return std::nullopt;
    }
  }
  std::string err;
  if (!ktx2::parse(out.payload.data(), out.payload.size(), &out.info, &err)) {
    // A broken baked file must never produce a black texture: decline and let the PNG tier win.
    lg::error("baked recharged textures: bad ktx2 {}: {} — falling back to PNG", path.string(),
              err);
    return std::nullopt;
  }
  out.wrap_mode = "repeat";
  out.channels = baked_channels(suffix);

  const auto& e = *entry_it;
  if (e.contains("normal_dc_x") && e.contains("normal_dc_y")) {
    out.stats.has_normal_dc = true;
    out.stats.normal_dc_x = e.value("normal_dc_x", 0.f);
    out.stats.normal_dc_y = e.value("normal_dc_y", 0.f);
  }
  if (e.contains("height_mean") && e.contains("height_norm") &&
      e.contains("height_lambda_tiles")) {
    out.stats.has_height = true;
    out.stats.height_mean = e.value("height_mean", 0.5f);
    out.stats.height_norm = e.value("height_norm", 1.0f);
    out.stats.height_lambda_tiles = e.value("height_lambda_tiles", 0.25f);
  }

  lg::info("{} ({}): {} <- {}", log_what, kBakedProfile, exact_key, path.string());
  return out;
}

}  // namespace

std::optional<managed_assets::CompressedTex> lookup_baked_base(const std::string& tpage_name,
                                                               const std::string& tex_name) {
  // Same gate as the BUNDLED PNG base swap (lookup()): this tier replaces it.
  if (!Gfx::recharged_active(Gfx::g_global_settings.recharged_textures)) {
    return std::nullopt;
  }
  return baked_load(tpage_name, tex_name, "", "custom texture BAKED");
}

std::optional<managed_assets::CompressedTex> lookup_baked_map(const std::string& tpage_name,
                                                              const std::string& tex_name,
                                                              const char* map_kind) {
  // Same gate as the BUNDLED PNG maps (resolve_suffixed): the MASTER, deliberately NOT the
  // base-swap toggle — PBR maps apply whenever PBR is on.
  if (!Gfx::recharged_master_active() || !map_kind || !*map_kind) {
    return std::nullopt;
  }
  return baked_load(tpage_name, tex_name, std::string("_") + map_kind, "custom pbr map BAKED");
}

bool baked_available() {
  if (!Gfx::recharged_master_active() || !baked_gpu_reads_astc()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_baked.mutex);
  ensure_baked_scanned_locked();
  return !g_baked.index.empty();
}

#ifdef OG_FEAT_PBR
namespace {
// Grecharged-pbr-materials: INDEX-ONLY resolution of a suffixed map. Everything up to — but
// not including — the file read lives here: the source gates, the suffixed key construction
// and the same-source pairing rule. Shared by lookup_suffixed() (which then decodes the PNG)
// and has_suffixed() (which stops at the index), so a decode-free probe can never disagree
// with what the renderer actually loads. Returns the winning index entry, nullptr on miss;
// out_src / out_exact_key are optional (logging only).
const fs::path* resolve_suffixed(const std::string& tpage_name,
                                 const std::string& tex_name,
                                 const char* suffix,
                                 BaseSource base_src,
                                 const char** out_src,
                                 std::string* out_exact_key) {
  const bool user_on = Gfx::recharged_active(Gfx::g_global_settings.load_custom_assets);
  // Bundled PBR maps apply whenever the PBR pipeline asks (the caller sits in the PBR path);
  // only the MASTER gates them — deliberately NOT the base-swap toggle (owner: PBR maps
  // whenever PBR is ON, base replacement only when RECHARGED TEXTURES is ON).
  const bool bundled_on = Gfx::recharged_master_active();
  if (!user_on && !bundled_on) {
    return nullptr;
  }
  ensure_scanned();

  // Same key logic as lookup(), but the suffix is appended to the NAME part of
  // both candidate keys (exact "tpage/name<suffix>" first, bare "name<suffix>").
  const std::string suffixed_name = tex_name + suffix;
  const std::string exact_key = normalize_key(tpage_name + "/" + suffixed_name);
  if (out_exact_key) {
    *out_exact_key = exact_key;
  }
  // SAME-SOURCE PAIRING (owner REOPEN #2 2026-07-23): PBR maps apply ONLY when they come
  // from the same source as the BASE texture that won — user base + user maps, or bundled
  // base + bundled maps, NEVER mixed provenance (an internet-pack base is a different
  // image; bundled maps describe the bundled base). A STOCK base (no replacement won)
  // still accepts user > bundled maps: both are authored against the stock look.
  const fs::path* path = nullptr;
  const char* src = "user";
  switch (base_src) {
    case BaseSource::User:
      path = user_on ? find_key(g_state.user_index, exact_key, suffixed_name) : nullptr;
      break;
    case BaseSource::Bundled:
      path = bundled_on ? find_key(g_state.bundled_index, exact_key, suffixed_name) : nullptr;
      src = "bundled";
      break;
    case BaseSource::Stock:
      path = user_on ? find_key(g_state.user_index, exact_key, suffixed_name) : nullptr;
      if (!path && bundled_on) {
        path = find_key(g_state.bundled_index, exact_key, suffixed_name);
        src = "bundled";
      }
      break;
  }
  if (out_src) {
    *out_src = src;
  }
  return path;
}
}  // namespace

const ReplacementImage* lookup_suffixed(const std::string& tpage_name,
                                        const std::string& tex_name,
                                        const char* suffix,
                                        BaseSource base_src) {
  // Gates, keys and the same-source pairing rule all live in resolve_suffixed(); only the
  // decode below is ours.
  const char* src = "user";
  std::string exact_key;
  const fs::path* path =
      resolve_suffixed(tpage_name, tex_name, suffix, base_src, &src, &exact_key);
  if (!path) {
    return nullptr;
  }

  int w = 0, h = 0;
  auto* data = stbi_load(path->string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
  if (!data) {
    lg::warn("custom pbr map: failed to load {}", path->string());
    return nullptr;
  }

  // Per-call thread-local storage: the loader consumes the pixels immediately
  // (creates a GL texture) before the next lookup_suffixed() call.
  static thread_local ReplacementImage s_out;
  s_out.w = w;
  s_out.h = h;
  s_out.src = src;
  s_out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(s_out.rgba.data(), data, s_out.rgba.size());
  stbi_image_free(data);

  lg::info("custom pbr map ({}): {} <- {}", src, exact_key, path->string());
  return &s_out;
}

// Existence-only twin of lookup_suffixed(): same resolve_suffixed() call, so the same gates
// and the same same-source pairing, but it stops at the index — no stbi_load, no decode. Same
// (lock-free) shared-scan path as lookup_suffixed; ensure_scanned() is the only shared state
// either of them touches.
bool has_suffixed(const std::string& tpage_name,
                  const std::string& tex_name,
                  const char* suffix,
                  BaseSource base_src) {
  return resolve_suffixed(tpage_name, tex_name, suffix, base_src, nullptr, nullptr) != nullptr;
}

PbrMaterialMaps register_pbr_material(const std::string& tex_key, const PbrMaterialMaps& maps) {
  PbrMaterialMaps prev;  // all-zero if none
  auto it = g_pbr_materials.find(tex_key);
  if (it != g_pbr_materials.end()) {
    prev = it->second;
    it->second = maps;
  } else {
    g_pbr_materials.emplace(tex_key, maps);
  }
  lg::info("custom pbr material registered: {} (N={} R={} M={} AO={} H={} S={} E={})", tex_key,
           maps.normal_tex ? 1 : 0, maps.rough_tex ? 1 : 0, maps.metal_tex ? 1 : 0,
           maps.ao_tex ? 1 : 0, maps.height_tex ? 1 : 0, maps.specular_tex ? 1 : 0,
           maps.emissive_tex ? 1 : 0);
  return prev;
}

const PbrMaterialMaps* find_pbr_material(const std::string& tex_key) {
  auto it = g_pbr_materials.find(tex_key);
  return it == g_pbr_materials.end() ? nullptr : &it->second;
}

// ===================================================================================================
// Gpbr-material-props — surfaces.json, the AUTHORED half of a material.
//
// Every per-material number this pipeline had before today is MEASURED from the PNGs at load
// (normal DC, height mean/range, feature wavelength, UV density). That works because each of them is
// a statistic of an image. A scattering colour is not: whether a straw roof glows amber or a leaf
// glows green when the sun is behind it is an artistic decision about the SURFACE, and no amount of
// staring at its albedo will produce it. Neither is relief depth: a cut-stone wall and a patch of
// grass carry the same KIND of height map and must not be pushed to the same depth. So the modern
// stack needs a place to author per-material parameters — and the owner decided WHERE that place
// is (2026-08-29): "ces props doivent faire partie du repo Recharged assets, pas dans l'APK".
//
// So the table is authored in the ASSET repository, one record per material, collapsed by its
// publishing step into a single surfaces.json shipped as a release EXTRA beside the RPACK shards,
// and installed by the asset manager into managed_assets/<game>/. Nothing is read from the GAME
// repo any more: the APK carries no authored material at all, which is the whole point of the rule.
//
// Two locations, FIRST HIT WINS:
//   1. <external recharged assets dir>/surfaces.json — the owner's kilobyte-push override, so
//      re-tuning a material costs an adb push instead of a release round-trip (same precedence
//      rule physics_chains.txt established);
//   2. managed_assets/<game>/surfaces.json           — what the asset manager installed.
// Neither present: every field stays at its struct default, and every struct default IS the
// identity, so the engine behaves exactly as it did before this phase.
// ===================================================================================================
namespace {

struct MmParamSet {
  u32 authored_flags = 0;  // bits 1/2/4/8/16/64 only — 32 and 128 are texture-derived
  float sss_color[3] = {1.f, 1.f, 1.f};
  float sss_strength = 0.f;
  float sss_thickness = 0.5f;
  float sss_power = 6.f;
  float sss_distort = 0.2f;
  float sss_wrap = 0.f;
  float sss_ambient = 0.25f;
  float coat_weight = 0.f;
  float coat_rough = 0.10f;
  float aniso = 0.f;
  float aniso_angle = 0.f;
};

std::unordered_map<std::string, MmParamSet> g_mm_params;
MmParamSet g_mm_defaults;
bool g_mm_has_defaults = false;
bool g_mm_loaded = false;

// Gpbr-per-texture-materials — the SECOND parameter set the same blocks fill. Kept separate from
// MmParamSet on purpose: MmParamSet feeds u_mm_flags, which is gated on the MODERN MATERIALS menu
// row and is therefore CLEARED whenever the row is off. These knobs drive the PBR path itself
// (relief, roughness, metallicity, reflectance, normal-map handedness), which is on by default —
// sharing the struct would drag them behind that gate and make every preset inert.
// EVERY DEFAULT HERE IS THE IDENTITY: an un-named material comes out of the parser exactly as the
// accepted PBR path built it.
struct PbrMatParams {
  float relief = 1.f;
  float relief_depth = 1.f;
  float relief_lambda = 0.f;
  float spec = 1.f;
  float rough_nomap = 0.9f;
  float rough_scale = 1.f;
  float metal_nomap = 0.f;
  float metal_scale = 1.f;
  float reflectance = 0.04f;
  float normal_y = 1.f;
};

std::unordered_map<std::string, PbrMatParams> g_pbrmat_params;
PbrMatParams g_pbrmat_defaults;
bool g_pbrmat_has_defaults = false;
// Gpbr-material-props: the authored FAMILY name ("sand", "cut-stone", ...) per material.
// The engine derives nothing from it — it exists so the load trace says WHICH material class
// produced the numbers on the same line as the numbers, which is what makes "stone and grass
// get different relief depths" checkable from a log instead of from an opinion.
std::unordered_map<std::string, std::string> g_pbrmat_family;
// Gpbr-material-props — BARE-NAME ALIASES, and this is not a convenience.
// The table is keyed "<tpage>/<name>" by the ASSET repository, whose tpage is the one the material
// was authored under. The ENGINE registers the same texture under the tpage it is actually LOADED
// from, and the two differ for real: measured on one village1 run, 5 of 30 registered materials
// missed the exact key, and 2 of those 5 are the SAME material under another tpage
// (village1-vis-alpha/vil-beach-01 against village1-vis-tfrag/vil-beach-01 — the owner's own sand).
// Without this index they take the identity in SILENCE, which reads exactly like "the file was
// never loaded".
// The alias is only created when the bare name is UNIQUE across the whole table: 170 of the 172
// names are, and the two that are not (vil3-lava-floor, mis-boatwall live under two tpages each)
// must keep requiring the exact key, or one level's material would bleed into another's. Same rule
// managed_assets uses for its own bare-name fallback, on purpose — one rule, not two.
std::unordered_map<std::string, std::string> g_surf_bare;

// Texture-derived capability bits. The loader owns these (a map is either bound or it is not); the
// file owns everything else. Keeping them in one named constant is what makes the re-stamp on reload
// safe: authored bits are recomputed, these are carried over.
// The texture-derived capability bits, RECOMPUTED from the maps every time rather than carried in
// mm_flags. See PbrMaterialMaps::orm_packed for why: mm_flags is rebuilt (and zeroed when the master
// is off) on every re-stamp, so a bit that only lived there would not survive a menu toggle.
u32 mm_texture_bits(const PbrMaterialMaps& m) {
  return (m.thickness_tex ? 32u : 0u) | (m.orm_packed ? 128u : 0u);
}

}  // namespace

bool mm_master_active() {
  // The OWNER's switch is the menu row; this override exists for the headless harness, which has no
  // menu to navigate (and for a supervisor A/B on device with one setprop). -1 = no override.
  //   android: debug.opengoal.mm.on      desktop: OG_MM_ON
  int ov = -1;
#ifdef __ANDROID__
  char v[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.mm.on", v) > 0) {
    ov = atoi(v);
  }
#else
  if (const char* e = getenv("OG_MM_ON")) {
    ov = atoi(e);
  }
#endif
  if (ov >= 0) {
    return ov != 0;
  }
  return Gfx::recharged_active(Gfx::g_global_settings.recharged_modern_materials);
}

namespace {

// Gpbr-material-props — KEY RESOLUTION, in ONE place, because the two callers do not agree on what
// they pass and that disagreement was silent.
//   LoaderStages.cpp:710/716 (LEVEL LOAD) passes `tex.debug_name`         -> a BARE name
//   mm_params_reload's re-stamp walk passes the registry key              -> "<tpage>/<name>"
// surfaces.json keys its records "<tpage>/<name>" (the asset repo's tpage). So the level-load path
// matched NOTHING at all, and the only materials that ever got their properties were the ones that
// happened to be registered BEFORE a reload — measured: 1 material out of 25 with maps bound in a
// village1 run. The old text file keyed its blocks by bare name, which is why the same call site
// used to work; changing the key shape moved the bug into a path with no error.
// Four steps, in this order:
//   1. the name as given (a composite key from the re-stamp walk, or a hand-written bare record)
//   2. its bare part, through the UNIQUE-bare-name index -> the full key the asset repo authored
//   3. that bare part as a literal key (an external override authored by hand)
// An ambiguous bare name has no alias, so it can only ever be reached by its exact key.
std::string surf_resolve_key(const std::string& tex_debug_name, bool* via_alias) {
  *via_alias = false;
  if (g_pbrmat_params.find(tex_debug_name) != g_pbrmat_params.end()) {
    return tex_debug_name;
  }
  const auto slash = tex_debug_name.rfind('/');
  const std::string bare =
      (slash == std::string::npos) ? tex_debug_name : tex_debug_name.substr(slash + 1);
  const auto alias = g_surf_bare.find(bare);
  if (alias != g_surf_bare.end()) {
    *via_alias = (alias->second != tex_debug_name);
    return alias->second;
  }
  return bare;
}

// Logged ONCE per texture name, and it logs the MISSES too — that is the whole point. A material
// that receives no record renders the identity, which is byte-for-byte what a correctly-working
// engine renders for a material nobody authored. The two are indistinguishable in the image and in
// every counter, so the only way to tell "no properties were written for this surface" from "the
// properties never reached it" is to say so at the moment of resolution.
void surf_note_apply(const std::string& from, const std::string& key, bool found, bool via_alias) {
  static std::set<std::string> reported;
  if (!reported.insert(from).second) {
    return;
  }
  if (found) {
    const auto fam = g_pbrmat_family.find(key);
    lg::info("[surfaces] apply {} -> {}{} family={}", from, key, via_alias ? " (via bare-name index)" : "",
             fam == g_pbrmat_family.end() ? "-" : fam->second);
  } else {
    lg::info("[surfaces] apply {} -> NO RECORD, stays at the identity", from);
  }
}

// Recompute the authored capability bits from the values. A channel is ON exactly when its own
// parameter says it does something, so a block can never claim a capability it does not use — and
// an all-zero block is indistinguishable from no block at all, which is the behaviour we want.
void mm_recompute_flags(MmParamSet* p, bool energy_on, bool specocc_on, bool filmic_on) {
  u32 f = 0;
  if (p->sss_strength > 1e-4f) {
    f |= 1u;
  }
  if (p->coat_weight > 1e-4f) {
    f |= 2u;
  }
  if (std::fabs(p->aniso) > 1e-3f) {
    f |= 4u;
  }
  if (energy_on) {
    f |= 8u;
  }
  if (specocc_on) {
    f |= 16u;
  }
  if (filmic_on) {
    f |= 64u;
  }
  p->authored_flags = f;
}

}  // namespace

namespace {
std::atomic<bool> g_mm_reload_req{false};
}  // namespace

void mm_request_params_reload() {
  g_mm_reload_req.store(true, std::memory_order_release);
}

void mm_service_reload() {
  if (g_mm_reload_req.exchange(false, std::memory_order_acq_rel)) {
    mm_params_reload();
  }
}

void mm_params_reload() {
  g_mm_params.clear();
  g_mm_defaults = MmParamSet();
  g_mm_has_defaults = false;
  g_mm_loaded = true;
  // Gpbr-per-texture-materials: the PBR-path knobs come out of the SAME blocks, so they are cleared
  // and refilled by the SAME pass. One file, one parser, two destinations.
  g_pbrmat_params.clear();
  g_pbrmat_defaults = PbrMatParams();
  g_pbrmat_has_defaults = false;
  // Cleared HERE and not only in the catch: a reload that succeeds but no longer names a material
  // would otherwise keep the family it had last time and print it beside the NEW numbers. A
  // diagnostic that pairs a stale label with a fresh value is worse than no label, because it is
  // the line this phase is read from.
  g_pbrmat_family.clear();
  g_surf_bare.clear();

  // Gpbr-material-props: the table comes from the ASSET side, never from the game repo. Two
  // locations, FIRST HIT WINS — see the block comment above for why the override exists.
  const char* src_kind = "managed";
  fs::path path;
  const fs::path managed_path = managed_assets::install_dir() / "surfaces.json";
  std::string ext_str = "(no external dir)";
  bool found = false;
  if (auto ext_dir = file_util::get_external_recharged_assets_dir()) {
    const fs::path ext_path = *ext_dir / "surfaces.json";
    ext_str = ext_path.string();
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
      src_kind = "external-override";
      found = true;
    }
  }
  if (!found && file_util::file_exists(managed_path.string())) {
    path = managed_path;
    src_kind = "managed";
    found = true;
  }
  if (!found) {
    // BOTH paths are printed. "Not found" is only actionable when it says WHERE it looked, and the
    // two tiers are absent for different reasons (no override pushed vs. no asset pack installed) —
    // a single path in this line would send the reader to fix the wrong tier.
    lg::info("[mm] PARAMSRC=none tried={} and {} (modern material stack has no authored materials)",
             ext_str, managed_path.string());
    return;
  }
  lg::info("[mm] PARAMSRC={} path={}", src_kind, path.string());

  int n_mat = 0, n_unknown = 0;
  try {
    const nlohmann::json root = nlohmann::json::parse(file_util::read_text_file(path.string()));
    if (!root.is_object()) {
      lg::warn("[mm] surfaces.json at {} is not a JSON object — nothing loaded", path.string());
      return;
    }

    // A version we do not know is refused outright rather than read key-by-key: a future schema is
    // free to give an existing key a new meaning, and silently applying it under the old meaning
    // would be a wrong material rather than a missing one.
    const int schema_version =
        (root.contains("schema_version") && root["schema_version"].is_number_integer())
            ? root["schema_version"].get<int>()
            : 0;
    if (schema_version != 1) {
      lg::warn("[mm] surfaces.json at {}: schema_version={} is not 1 — nothing loaded",
               path.string(), schema_version);
      return;
    }

    // Header echo, emitted straight after the parse and BEFORE any record is installed. The counts
    // on this line are what the FILE DECLARES; the "[mm] surfaces.json parsed" line below prints
    // what was actually installed. Side by side they are the free control on a truncated or
    // half-published table — one number against the other, no extra tooling.
    const std::string game_name =
        (root.contains("game") && root["game"].is_string()) ? root["game"].get<std::string>()
                                                            : std::string("?");
    const int decl_families =
        (root.contains("family_count") && root["family_count"].is_number_integer())
            ? root["family_count"].get<int>()
            : -1;
    const int decl_materials =
        (root.contains("material_count") && root["material_count"].is_number_integer())
            ? root["material_count"].get<int>()
            : -1;
    const bool has_defaults_block = root.contains("defaults") && root["defaults"].is_object();
    lg::info("[surfaces] schema_version={} game={} families={} materials={} defaults={}",
             schema_version, game_name, decl_families, decl_materials, has_defaults_block ? 1 : 0);

    // Numbers only. A key holding the wrong JSON type leaves the field at the value it already
    // holds, which (records start from a fresh struct) is the documented default for that key.
    auto num = [](const nlohmann::json& v, float def) {
      return v.is_number() ? v.get<float>() : def;
    };

    // ONE record -> one MmParamSet + one PbrMatParams + its family name. EVERY key is optional,
    // and every field is seeded from a default-constructed struct, so a record carrying NONE of
    // the keys below leaves both structs untouched: the identity. `who` only names the offender
    // in the warnings.
    auto read_record = [&](const std::string& who, const nlohmann::json& rec, MmParamSet* out_mm,
                           PbrMatParams* out_pm, std::string* out_family) {
      // energy / spec-occlusion default ON inside ANY record: they are strict quality wins with no
      // artistic choice attached (they only make the existing specular obey energy conservation and
      // stop it leaking through the surface), so a three-key record still gets them. "energy": 0
      // and "specocc": 0 turn them off for an A/B. This is the rule the text parser had, unchanged.
      bool energy_on = true, specocc_on = true, filmic_on = false;
      for (auto it = rec.begin(); it != rec.end(); ++it) {
        const std::string& k = it.key();
        const nlohmann::json& v = it.value();
        if (k == "family") {
          // Authoring/tooling metadata. The engine derives NOTHING from it; it is carried only so
          // the per-material trace can print it (see g_pbrmat_family).
          if (v.is_string()) {
            *out_family = v.get<std::string>();
          }
        } else if (k == "sss") {
          if (v.is_array() && v.size() >= 3) {
            for (int i = 0; i < 3; i++) {
              out_mm->sss_color[i] = num(v[i], out_mm->sss_color[i]);
            }
          }
        } else if (k == "sss_strength") {
          out_mm->sss_strength = num(v, out_mm->sss_strength);
        } else if (k == "sss_thickness") {
          out_mm->sss_thickness = num(v, out_mm->sss_thickness);
        } else if (k == "sss_power") {
          out_mm->sss_power = num(v, out_mm->sss_power);
        } else if (k == "sss_distort") {
          out_mm->sss_distort = num(v, out_mm->sss_distort);
        } else if (k == "sss_wrap") {
          out_mm->sss_wrap = num(v, out_mm->sss_wrap);
        } else if (k == "sss_ambient") {
          out_mm->sss_ambient = num(v, out_mm->sss_ambient);
        } else if (k == "clearcoat") {
          out_mm->coat_weight = num(v, out_mm->coat_weight);
        } else if (k == "clearcoat_rough") {
          out_mm->coat_rough = num(v, out_mm->coat_rough);
        } else if (k == "aniso") {
          out_mm->aniso = num(v, out_mm->aniso);
        } else if (k == "aniso_angle") {
          out_mm->aniso_angle = num(v, out_mm->aniso_angle);
        } else if (k == "energy") {
          energy_on = num(v, 1.f) != 0.f;
        } else if (k == "specocc") {
          specocc_on = num(v, 1.f) != 0.f;
        } else if (k == "filmic") {
          filmic_on = num(v, 0.f) != 0.f;
          // ---- the PBR-PATH knobs. Same record, but these land in out_pm and are NOT behind the
          // MODERN MATERIALS menu row (see PbrMatParams).
        } else if (k == "relief") {
          out_pm->relief = num(v, out_pm->relief);
        } else if (k == "relief_depth") {
          out_pm->relief_depth = num(v, out_pm->relief_depth);
        } else if (k == "relief_lambda") {
          out_pm->relief_lambda = num(v, out_pm->relief_lambda);
        } else if (k == "spec") {
          out_pm->spec = num(v, out_pm->spec);
        } else if (k == "roughness") {
          out_pm->rough_nomap = num(v, out_pm->rough_nomap);
        } else if (k == "roughness_scale") {
          out_pm->rough_scale = num(v, out_pm->rough_scale);
        } else if (k == "metallic") {
          out_pm->metal_nomap = num(v, out_pm->metal_nomap);
        } else if (k == "metallic_scale") {
          out_pm->metal_scale = num(v, out_pm->metal_scale);
        } else if (k == "reflectance") {
          out_pm->reflectance = num(v, out_pm->reflectance);
        } else if (k == "normal_y") {
          // Only the two handedness conventions exist (+1 = OpenGL green-up, -1 = DirectX
          // green-down). Anything else would be a silent partial flip, so it is refused and
          // reported, not clamped.
          const float ny = num(v, 1.f);
          if (ny == 1.f || ny == -1.f) {
            out_pm->normal_y = ny;
          } else {
            lg::warn("[mm] surfaces.json: {}: normal_y `{}` is neither 1 nor -1 — using 1", who,
                     v.dump());
            out_pm->normal_y = 1.f;
          }
        } else {
          n_unknown++;
          lg::warn("[mm] surfaces.json: {}: unknown key `{}` — skipped", who, k);
        }
      }
      mm_recompute_flags(out_mm, energy_on, specocc_on, filmic_on);
    };

    // Optional top-level "defaults", same shape as a material record: what a texture nobody named
    // falls back to (mm_apply_params / pbrmat_apply_params). Absent => un-named stays the identity.
    if (has_defaults_block) {
      MmParamSet cur;
      PbrMatParams pcur;
      std::string fam;
      read_record("defaults", root["defaults"], &cur, &pcur, &fam);
      g_mm_defaults = cur;
      g_mm_has_defaults = true;
      g_pbrmat_defaults = pcur;
      g_pbrmat_has_defaults = true;
    }

    if (root.contains("materials") && root["materials"].is_object()) {
      const nlohmann::json& mats = root["materials"];
      for (auto it = mats.begin(); it != mats.end(); ++it) {
        if (!it.value().is_object()) {
          lg::warn("[mm] surfaces.json: material `{}` is not an object — skipped", it.key());
          continue;
        }
        MmParamSet cur;
        PbrMatParams pcur;
        std::string fam;
        read_record(it.key(), it.value(), &cur, &pcur, &fam);
        // The JSON key IS the engine replacement key "<tpage>/<name>", so it is stored VERBATIM.
        // The bare-name fallback already lives downstream in mm_apply_params/pbrmat_apply_params;
        // normalising here as well would give one material two ways to be found and hide which one
        // matched.
        g_mm_params[it.key()] = cur;
        g_pbrmat_params[it.key()] = pcur;
        if (!fam.empty()) {
          g_pbrmat_family[it.key()] = fam;
        }
        n_mat++;
      }
    }
  } catch (const std::exception& e) {
    // A throw anywhere above would leave a HALF-LOADED table, which is worse than an empty one: the
    // materials past the bad record would silently keep whatever the previous reload installed. So
    // everything this function fills is wiped, and the engine goes back to the identity.
    g_mm_params.clear();
    g_mm_defaults = MmParamSet();
    g_mm_has_defaults = false;
    g_pbrmat_params.clear();
    g_pbrmat_defaults = PbrMatParams();
    g_pbrmat_has_defaults = false;
    g_pbrmat_family.clear();
    g_surf_bare.clear();
    lg::warn("[mm] surfaces.json at {} could not be read ({}) — nothing loaded, modern stack inert",
             path.string(), e.what());
    return;
  }
  lg::info("[mm] surfaces.json parsed: {} material records, defaults={}, {} unknown keys", n_mat,
           g_mm_has_defaults ? 1 : 0, n_unknown);

  // Build the bare-name index. Two passes because a name is only an alias if it is UNIQUE: count
  // first, then keep the singletons. The ambiguous ones are NAMED in the log rather than dropped
  // silently — they are the materials that will need an exact tpage match, and a reader chasing a
  // material that "does not apply" has to be able to see that from here.
  {
    std::map<std::string, int> seen;
    for (const auto& kv : g_pbrmat_params) {
      const auto slash = kv.first.rfind('/');
      if (slash != std::string::npos) {
        seen[kv.first.substr(slash + 1)]++;
      }
    }
    std::vector<std::string> ambiguous;
    for (const auto& kv : g_pbrmat_params) {
      const auto slash = kv.first.rfind('/');
      if (slash == std::string::npos) {
        continue;
      }
      const auto bare = kv.first.substr(slash + 1);
      if (seen[bare] == 1) {
        g_surf_bare[bare] = kv.first;
      }
    }
    for (const auto& kv : seen) {
      if (kv.second > 1) {
        ambiguous.push_back(kv.first);
      }
    }
    std::string amb_list;
    for (const auto& a : ambiguous) {
      amb_list += (amb_list.empty() ? "" : ", ") + a;
    }
    lg::info("[surfaces] bare-name index: {} unique aliases, {} ambiguous ({})",
             (int)g_surf_bare.size(), (int)ambiguous.size(),
             amb_list.empty() ? std::string("-") : amb_list);
  }

  // Gpbr-per-texture-materials — EXECUTION TRACE, not a comment. This block is the only proof that
  // the file was actually FOUND, READ and turned into numbers on this machine: the values below are
  // read back out of the parsed map, so a preset that never reached the parser cannot print here.
  // Sorted through a std::map so two runs of the same file emit byte-identical lines (the storage is
  // an unordered_map, whose iteration order is not a promise).
  lg::info("[pbrmat] PARAMSRC={} path={} blocks={} defaults={}", src_kind, path.string(),
           (int)g_pbrmat_params.size(), g_pbrmat_has_defaults ? 1 : 0);
  {
    std::map<std::string, const PbrMatParams*> sorted;
    for (const auto& kv : g_pbrmat_params) {
      sorted[kv.first] = &kv.second;
    }
    for (const auto& kv : sorted) {
      const PbrMatParams& p = *kv.second;
      // The family sits next to the numbers on purpose: "sand and cut stone do not get the same
      // relief depth" is then one grep on this line, not a cross-reference to the asset repo.
      const auto fam = g_pbrmat_family.find(kv.first);
      lg::info(
          "[pbrmat] {} family={} relief={:.3f} depth={:.3f} lambda={:.3f} spec={:.3f} "
          "rough={:.3f}x{:.3f} metal={:.3f}x{:.3f} F0={:.3f} ny={:+.0f}",
          kv.first, fam == g_pbrmat_family.end() ? "-" : fam->second.c_str(), p.relief,
          p.relief_depth, p.relief_lambda, p.spec, p.rough_nomap, p.rough_scale, p.metal_nomap,
          p.metal_scale, p.reflectance, p.normal_y);
    }
  }

  // Re-stamp everything already registered so a menu toggle applies without a level reload. Texture-
  // derived bits survive; authored ones are recomputed from the freshly parsed file (or cleared, if
  // the master went off).
  for (auto& kv : g_pbr_materials) {
    mm_apply_params(kv.first, &kv.second);
    // Gpbr-material-props: the PBR-path knobs are re-stamped on the SAME walk, so a freshly
    // installed (or pushed) surfaces.json reaches them through the same menu toggle that
    // reloads the modern half.
    pbrmat_apply_params(kv.first, &kv.second);
  }
}

void mm_apply_params(const std::string& tex_debug_name, PbrMaterialMaps* maps) {
  if (!maps) {
    return;
  }
  // Master off => every authored bit is dropped and the texture-derived ones carry no meaning, so
  // the draw pushes u_mm_flags = 0 and the shader chunk returns before writing a pixel. This single
  // line is the whole of "modern OFF == stock".
  if (!mm_master_active()) {
    maps->mm_flags = 0;
    return;
  }
  if (!g_mm_loaded) {
    mm_params_reload();
  }
  const MmParamSet* p = nullptr;
  // Same resolution as the PBR half — see surf_resolve_key. The two callers hand us two different
  // shapes of name (bare at level load, "<tpage>/<name>" on the re-stamp walk) and both must land
  // on the same record, or the modern layer would apply to a material whose PBR knobs did not.
  bool via_alias = false;
  const std::string key = surf_resolve_key(tex_debug_name, &via_alias);
  (void)via_alias;  // reported once from the PBR half; both halves resolve identically
  auto it = g_mm_params.find(key);
  if (it != g_mm_params.end()) {
    p = &it->second;
  } else if (g_mm_has_defaults) {
    p = &g_mm_defaults;
  }
  if (!p) {
    // Not named, and no "defaults" record: this material stays exactly as the accepted PBR path
    // built it.
    // Per-material opt-in means the un-named case has to be the identity, and it is.
    maps->mm_flags = 0;
    return;
  }
  maps->sss_color[0] = p->sss_color[0];
  maps->sss_color[1] = p->sss_color[1];
  maps->sss_color[2] = p->sss_color[2];
  maps->sss_strength = p->sss_strength;
  maps->sss_thickness = p->sss_thickness;
  maps->sss_power = p->sss_power;
  maps->sss_distort = p->sss_distort;
  maps->sss_wrap = p->sss_wrap;
  maps->sss_ambient = p->sss_ambient;
  maps->coat_weight = p->coat_weight;
  maps->coat_rough = p->coat_rough;
  maps->aniso = p->aniso;
  maps->aniso_angle = p->aniso_angle;
  maps->mm_flags = mm_texture_bits(*maps) | p->authored_flags;
  // A thickness map is only meaningful to the SSS channel.
  if ((maps->mm_flags & 1u) == 0) {
    maps->mm_flags &= ~32u;
  }
  // NORMALISATION, and it is load-bearing: the shader gates the whole modern chunk on
  // `u_mm_flags != 0`. Bits 32 and 128 describe how the material was AUTHORED (a thickness map is
  // bound; the channels came out of a packed _orm) and change no arithmetic on their own. If one of
  // them could survive alone, the gate would open on a material with no active channel and the
  // recomposition would rewrite `color` with an arithmetically-equal but not bit-guaranteed value —
  // "OFF == stock" would become "OFF ~= stock". So: no functional bit, no flags at all.
  constexpr u32 kMmFunctionalBits = 1u | 2u | 4u | 8u | 16u | 64u;
  if ((maps->mm_flags & kMmFunctionalBits) == 0) {
    maps->mm_flags = 0;
  }
}

void pbrmat_apply_params(const std::string& tex_debug_name, PbrMaterialMaps* maps) {
  if (!maps) {
    return;
  }
  // NO GATE, and that is the point. mm_apply_params() returns here when the MODERN MATERIALS menu
  // row is off, because everything it stamps only reaches the shader through u_mm_flags. These
  // knobs drive the PBR path itself, which is on by default — gating them on a row that ships OFF
  // would make every record of surfaces.json inert while still LOOKING wired.
  if (!g_mm_loaded) {
    mm_params_reload();
  }
  const PbrMatParams* p = nullptr;
  bool via_alias = false;
  const std::string key = surf_resolve_key(tex_debug_name, &via_alias);
  auto it = g_pbrmat_params.find(key);
  surf_note_apply(tex_debug_name, key, it != g_pbrmat_params.end(), via_alias);
  // Same two-step key resolution as mm_apply_params: surfaces.json keys its records the way the
  // registry does ("<tpage>/<name>"), and this fallback catches a record authored with a bare
  // debug name, which the re-stamp walk (composite key) could never match otherwise.
  if (it != g_pbrmat_params.end()) {
    p = &it->second;
  } else if (g_pbrmat_has_defaults) {
    p = &g_pbrmat_defaults;
  }
  if (!p) {
    // Nobody named this material and there is no "defaults" record: leave every pm_* field at its
    // default, which IS the pre-phase behaviour, and say so.
    maps->pm_authored = false;
    return;
  }
  maps->pm_relief = p->relief;
  maps->pm_relief_depth = p->relief_depth;
  maps->pm_relief_lambda = p->relief_lambda;
  maps->pm_spec = p->spec;
  maps->pm_rough_nomap = p->rough_nomap;
  maps->pm_rough_scale = p->rough_scale;
  maps->pm_metal_nomap = p->metal_nomap;
  maps->pm_metal_scale = p->metal_scale;
  maps->pm_reflectance = p->reflectance;
  maps->pm_normal_y = p->normal_y;
  maps->pm_authored = true;
}

namespace {
// Gpbr-props-reach-draw — COUVERTURE DE LA TABLE SUR CE QU'UN NIVEAU CHARGE REELLEMENT.
// Le recensement du binder ne peut voir que des matieres INSCRITES : une texture que personne
// n'authore et qui ne porte aucune carte n'y apparait jamais, donc « combien de surfaces la table
// ignore-t-elle » y est structurellement invisible. Ces deux compteurs sont pris au SEUL endroit
// qui voit les deux faits en meme temps — la decision d'inscription, une fois par texture et par
// chargement. Dedupliques par cle, sinon un rechargement de niveau les doublerait et le rapport
// publierait une couverture fausse dans le sens flatteur.
std::set<std::string> g_surf_seen_tex;
std::set<std::string> g_surf_named_tex;
}  // namespace

bool pbrmat_has_record(const std::string& tex_debug_name) {
  if (!g_mm_loaded) {
    mm_params_reload();
  }
  bool via_alias = false;
  const std::string key = surf_resolve_key(tex_debug_name, &via_alias);
  const bool found = g_pbrmat_params.find(key) != g_pbrmat_params.end();
  g_surf_seen_tex.insert(tex_debug_name);
  if (found) {
    g_surf_named_tex.insert(tex_debug_name);
  }
  return found;
}

namespace {
// Per-channel active-draw counters. Written from the GL thread only, read by the diag writer, so
// relaxed atomics are enough and cost nothing on the hot path.
std::atomic<u64> g_mm_draws_total{0};
std::atomic<u64> g_mm_draws_sss{0};
std::atomic<u64> g_mm_draws_coat{0};
std::atomic<u64> g_mm_draws_aniso{0};
std::atomic<u64> g_mm_draws_energy{0};
std::atomic<u64> g_mm_draws_specocc{0};
// BIND counters, ticked OUTSIDE the state-change guard by mm_note_bind(). g_mm_binds_total counts
// every PbrDrawBinder::set() bind; g_mm_binds_flagged only those carrying a non-zero mm_flags. The
// counters above are re-pushes of the uniform block, these are binds — publishing both is what
// makes the state-reuse rate readable instead of guessed.
std::atomic<u64> g_mm_binds_total{0};
std::atomic<u64> g_mm_binds_flagged{0};
}  // namespace

void mm_note_active_draw(int flags) {
  if (flags == 0) {
    return;
  }
  g_mm_draws_total.fetch_add(1, std::memory_order_relaxed);
  if (flags & 1) {
    g_mm_draws_sss.fetch_add(1, std::memory_order_relaxed);
  }
  if (flags & 2) {
    g_mm_draws_coat.fetch_add(1, std::memory_order_relaxed);
  }
  if (flags & 4) {
    g_mm_draws_aniso.fetch_add(1, std::memory_order_relaxed);
  }
  if (flags & 8) {
    g_mm_draws_energy.fetch_add(1, std::memory_order_relaxed);
  }
  if (flags & 16) {
    g_mm_draws_specocc.fetch_add(1, std::memory_order_relaxed);
  }
}

void mm_note_bind(int flags) {
  g_mm_binds_total.fetch_add(1, std::memory_order_relaxed);
  if (flags != 0) {
    g_mm_binds_flagged.fetch_add(1, std::memory_order_relaxed);
  }
}

std::string mm_params_diag_section() {
  std::string out;
  int n = 0;
  // MEASURED, NOT ASSUMED. The NOTE line below says energy/specocc equal the push total "by
  // construction". That is true of the SHIPPED surfaces.json (0 of 172 records overrides them) —
  // but the parser prefers an EXTERNAL recharged-assets surfaces.json over the installed one, and
  // an override carrying "energy": 0 would falsify the sentence while the sentence kept printing.
  // So we count the counter-examples on the same walk and publish them: 0/0 proves the claim FOR
  // THIS RUN, non-zero refutes it in place.
  int n_no_energy = 0, n_no_specocc = 0;
  for (const auto& kv : g_pbr_materials) {
    if (kv.second.mm_flags == 0) {
      continue;
    }
    if ((kv.second.mm_flags & 8u) == 0) {
      n_no_energy++;
    }
    if ((kv.second.mm_flags & 16u) == 0) {
      n_no_specocc++;
    }
    const auto& m = kv.second;
    out += fmt::format(
        "[mm] {} flags=0x{:x} sss=({:.3f},{:.3f},{:.3f})x{:.2f} th={:.2f}{} pow={:.1f} "
        "wrap={:.2f} amb={:.2f} coat={:.2f}/{:.2f} aniso={:.2f}@{:.2f}\n",
        kv.first, m.mm_flags, m.sss_color[0], m.sss_color[1], m.sss_color[2], m.sss_strength,
        m.sss_thickness, (m.mm_flags & 32u) ? "(map)" : "", m.sss_power, m.sss_wrap, m.sss_ambient,
        m.coat_weight, m.coat_rough, m.aniso, m.aniso_angle);
    n++;
  }
  const u64 tot = g_mm_draws_total.load(std::memory_order_relaxed);
  const u64 energy = g_mm_draws_energy.load(std::memory_order_relaxed);
  const u64 specocc = g_mm_draws_specocc.load(std::memory_order_relaxed);
  // NO GUARD. The old `if (n || tot)` made an OFF leg SILENT, and a missing line reads the same as
  // an uncompiled block or a stale file. Zeros are a measurement; absence is not.
  out += fmt::format(
      "[mm] {} material(s) carry the modern stack; PBR BINDS total={} flagged={}; "
      "STATE-PUSHES total={} sss={} coat={} aniso={}\n",
      n, g_mm_binds_total.load(std::memory_order_relaxed),
      g_mm_binds_flagged.load(std::memory_order_relaxed), tot,
      g_mm_draws_sss.load(std::memory_order_relaxed),
      g_mm_draws_coat.load(std::memory_order_relaxed),
      g_mm_draws_aniso.load(std::memory_order_relaxed));
  // And the line that stops the numbers above from being read as something they are not.
  out += fmt::format(
      "[mm] NOTE energy={} specocc={} == STATE-PUSHES total; counter-examples this run: "
      "materials WITHOUT bit8={} WITHOUT bit16={} (0/0 => the equality is a property of the loaded "
      "surfaces.json, measured here, not assumed) -> these two carry no information. "
      "STATE-PUSHES counts uniform re-pushes (material transitions), NOT draws and NOT fragment "
      "executions. Modern chunk gate: u_pbr_debug={} (pbr_modern.glsl:40 requires ==0; non-zero "
      "SKIPS the whole chunk while these counters still rise).\n",
      energy, specocc, n_no_energy, n_no_specocc, ::pbr_debug_mode());
  return out;
}

PbrMaterialMaps release_pbr_material(const std::string& tex_key) {
  PbrMaterialMaps prev;
  auto it = g_pbr_materials.find(tex_key);
  if (it != g_pbr_materials.end()) {
    prev = it->second;
    g_pbr_materials.erase(it);
  }
  return prev;
}

void pbr_pom_diag_note(const std::string& tex_debug_name,
                       const PbrMaterialMaps& maps,
                       float uv_per_m) {
  auto it = g_pom_diag.find(tex_debug_name);
  // A FIRST sighting always counts as a change, even when its values happen to equal the struct
  // defaults — otherwise a level whose materials all measure at identity would never re-emit the
  // file and the block would keep reading "materials=0".
  const bool is_new = it == g_pom_diag.end();
  if (is_new) {
    it = g_pom_diag.emplace(tex_debug_name, PomDiagEntry{}).first;
  }
  auto& e = it->second;
  const int mode = pom_mode_bits(maps);
  const bool changed = is_new || e.uv_per_m != uv_per_m ||
                       e.lambda_tiles != maps.height_lambda_tiles || e.mode != mode;
  e.uv_per_m = uv_per_m;
  e.lambda_tiles = maps.height_lambda_tiles;
  e.mode = mode;
  if (changed) {
    g_pom_diag_generation++;
  }
}

u32 pbr_pom_diag_generation() {
  return g_pom_diag_generation;
}

std::string pbr_pom_diag_section() {
  if (g_pom_diag.empty()) {
    return {};
  }
  const auto& gs = Gfx::g_global_settings;
  // The SAME value background_common.cpp pushes to u_pbr_height_scale: a 0.05 base folded with the
  // menu's TEXTURE RELIEF slider, clamped to 0..3 there. Recomputed (not read back) because the GL
  // side owns no persistent copy — if these two ever drift, the [pom] numbers are the ones to
  // distrust, not the render.
  const float relief = std::max(0.0f, std::min(gs.recharged_pbr_texture_relief, 3.0f));
  const float height_scale = 0.05f * relief;
  std::string out;
  // Header: what question this block answers. The owner and the supervisor both asked for the
  // FINAL offset, in UV *and* in world centimetres, after every cap the shader applies — plus the
  // branch gates, because a zero-looking parallax is just as likely to be a branch that never ran.
  out +=
      "[pom] # CPU mirror of the shader parallax law: is the POM branch executed on this draw,\n";
  out += "[pom] # and what is the FINAL offset (UV and world cm) after every cap?\n";
  out +=
      "[pom] # gates: has_height = (mode & 16) -> no height map means the POM samples nothing;\n";
  out +=
      "[pom] #        bisect & 128 = the menu's PBR-ISOLATE forcing parallax/POM off entirely;\n";
  out += "[pom] #        displacement = the DISPLACEMENT carousel (0 Off / 1 Parallax / 2 Tess).\n";
  out += "[pom] # off45 = the offset a 45 deg view direction produces (tan(45) = 1), i.e. the\n";
  out += "[pom] #         full depth: off45_uv = amp_m * uv_per_m, off45_cm = amp_m * 100.\n";
  u32 with_height = 0;
  for (const auto& [name, e] : g_pom_diag) {
    const bool has_height = (e.mode & 16) != 0;
    if (has_height) {
      with_height++;
    }
    // EXACTLY the amplitude law the shaders run, cap for cap and in the same order — see
    // pom_law_eval(), which IS pom_depth_uv() transcribed, and must move with it.
    const float upm = std::max(e.uv_per_m, 0.02f);
    const float tile_m = 1.0f / upm;
    const float lam_m = std::clamp(e.lambda_tiles, 0.002f, 1.0f) * tile_m;
    const float rel = height_scale * 20.0f;  // height_scale = 0.05 * texture-relief
    const PomLaw L = pom_law_eval(rel, lam_m, upm);
    out += fmt::format(
        "[pom] mat={} uv_per_m={:.4f} tile_m={:.3f} height_lambda_tiles={:.4f} "
        "lambda_world_m={:.4f} amp_m={:.5f} depth_uv={:.5f} off45_uv={:.5f} off45_cm={:.2f} "
        "mode={} has_height={} displacement={} bisect={} drive={:.4f} amp_base={:.5f} "
        "cap_ratio={:.5f} cap_abs={:.5f} amp_argmin={} pom_cap_tan={:.5f} pom_cap_feat={:.5f} "
        "pom_cap_argmin={}\n",
        name, e.uv_per_m, tile_m, e.lambda_tiles, lam_m, L.amp_m, L.depth_uv, L.depth_uv,
        L.amp_m * 100.f, e.mode, has_height ? 1 : 0, gs.recharged_pbr_displacement,
        gs.recharged_pbr_isolate, L.drive, L.amp_base, L.cap_ratio, L.cap_abs, L.amp_argmin,
        L.cap_tan, L.cap_feat, L.cap_argmin);
  }
  out += fmt::format("[pom] materials={} with_height={}\n", g_pom_diag.size(), with_height);

  // ---------------------------------------------------------------------------------------------
  // [amp] ROUND 23 SLIDER-HEADROOM PROOF (owner defect B: "le curseur au maximum 3.0, c'est pas si
  // obvious"). The [pom] block above reports the LIVE slider only, so it cannot answer the gate
  // question "does any cap bite at slider max?" — a cap that binds only at 3.0 is invisible there.
  // So the identical law is evaluated TWICE per material at two FIXED slider positions, 1.0 and
  // 3.0, and the quotients are printed. This is the round-20 POM_MAX_WORLD_M trap, and the round-22
  // POM_MAX_FEATURE_FRAC one, expressed as a number the supervisor can gate on.
  out += "[amp] # drive = pow(rel, 1.4) => drive(3.0)/drive(1.0) = 4.6555 is the IDEAL: with no\n";
  out += "[amp] # cap biting, amp_ratio / depth_ratio / cap_ratio_1to3 ALL land on 4.6555.\n";
  out += "[amp] # Materially below it = a cap clips slider max; relN_argmin names which term.\n";
  float min_amp_ratio = 0.f;
  float min_cap_ratio = 0.f;
  bool any_amp = false;
  for (const auto& [name, e] : g_pom_diag) {
    const float upm = std::max(e.uv_per_m, 0.02f);
    const float tile_m = 1.0f / upm;
    const float lam_m = std::clamp(e.lambda_tiles, 0.002f, 1.0f) * tile_m;
    const PomLaw a1 = pom_law_eval(1.0f, lam_m, upm);
    const PomLaw a3 = pom_law_eval(3.0f, lam_m, upm);
    const float amp_ratio = a1.amp_m > 0.f ? a3.amp_m / a1.amp_m : 0.f;
    const float depth_ratio = a1.depth_uv > 0.f ? a3.depth_uv / a1.depth_uv : 0.f;
    const float cap_ratio_1to3 = a1.cap > 0.f ? a3.cap / a1.cap : 0.f;
    out += fmt::format(
        "[amp] mat={} rel1_amp_m={:.5f} rel1_depth_uv={:.5f} rel1_cap={:.5f} rel1_argmin={} "
        "rel3_amp_m={:.5f} rel3_depth_uv={:.5f} rel3_cap={:.5f} rel3_argmin={} amp_ratio={:.4f} "
        "depth_ratio={:.4f} cap_ratio_1to3={:.4f}\n",
        name, a1.amp_m, a1.depth_uv, a1.cap, a1.amp_argmin, a3.amp_m, a3.depth_uv, a3.cap,
        a3.amp_argmin, amp_ratio, depth_ratio, cap_ratio_1to3);
    if (!any_amp) {
      min_amp_ratio = amp_ratio;
      min_cap_ratio = cap_ratio_1to3;
      any_amp = true;
    } else {
      min_amp_ratio = std::min(min_amp_ratio, amp_ratio);
      min_cap_ratio = std::min(min_cap_ratio, cap_ratio_1to3);
    }
  }
  out += fmt::format(
      "[amp] materials={} min_amp_ratio={:.4f} min_cap_ratio={:.4f} "
      "drive_ratio_ideal=4.6555\n",
      g_pom_diag.size(), min_amp_ratio, min_cap_ratio);
  return out;
}

void pbr_coverage_note_draw(u64 frame_idx,
                            const char* renderer,
                            const char* tree_kind,
                            bool has_height,
                            bool disp_tess,
                            bool disp_pom) {
  if (frame_idx != g_cover_cur_frame.load(std::memory_order_relaxed)) {
    cover_roll(frame_idx);
  }
  // Exactly one bucket per height-mapped draw. Tessellation wins when both are somehow reported:
  // the tess-eval displaces the vertices and the fragment POM stands down on that program, so a
  // tess draw can never also be a POM draw.
  const int bucket = disp_tess ? kCovTess : (disp_pom ? kCovPom : kCovNone);
  g_cover_cur.total[kCovDraws].fetch_add(1, std::memory_order_relaxed);
  if (has_height) {
    g_cover_cur.total[kCovHeight].fetch_add(1, std::memory_order_relaxed);
    g_cover_cur.total[bucket].fetch_add(1, std::memory_order_relaxed);
  }
  cover_bump(cover_slot(g_cover_cur.renderers, renderer), has_height, bucket);
  cover_bump(cover_slot(g_cover_cur.kinds, tree_kind), has_height, bucket);
}

u32 pbr_coverage_generation() {
  return g_cover_generation.load(std::memory_order_relaxed);
}

std::string pbr_coverage_section() {
  if (!g_cover_any.load(std::memory_order_relaxed)) {
    return {};
  }
  u32 t[kCovN];
  for (int i = 0; i < kCovN; i++) {
    t[i] = cover_read(g_cover_last.total, i);
  }
  // 100.0 with no height-mapped draw at all: nothing was asked to displace, so nothing is missing.
  const double cov_pct =
      t[kCovHeight] ? 100.0 * (double)(t[kCovTess] + t[kCovPom]) / (double)t[kCovHeight] : 100.0;
  std::string out;
  out += "[cover] # OWNER BUG B (\"des chunks entiers (LA PLUPART) sont juste PLATS\"): WHICH\n";
  out += "[cover] # PBR-bound draws actually RECEIVE displacement, counted at the bind site.\n";
  out += "[cover] #   pbr_draws  = draws that bound a PBR material this frame (height or not)\n";
  out += "[cover] #   pbr_height = of those, the ones with a height map (u_pbr_mode bit 16)\n";
  out += "[cover] #   disp_tess  = displaced for real by the TFRAG3_TESS program (vertex)\n";
  out += "[cover] #   disp_pom   = non-tess program, so the fragment POM runs on it\n";
  out += "[cover] #   disp_none  = NEITHER -> the FLAT CHUNK count; must be ~0 unless the\n";
  out += "[cover] #                DISPLACEMENT setting is Off (u_pbr_height_scale == 0).\n";
  out += "[cover] # Numbers are the LAST COMPLETED frame.\n";
  out += fmt::format(
      "[cover] frame={} pbr_draws={} pbr_height={} disp_tess={} disp_pom={} disp_none={} "
      "coverage_pct={:.1f}\n",
      g_cover_last_frame.load(std::memory_order_relaxed), t[kCovDraws], t[kCovHeight], t[kCovTess],
      t[kCovPom], t[kCovNone], cov_pct);
  out += cover_renderer_line("tfrag", " ");
  out += cover_renderer_line("tie", "   ");
  // Any other PBR-capable renderer that started reporting (none today, but the rows must not be
  // silently dropped if one is added).
  for (int i = 0; i < kCoverSlots; i++) {
    const char* n = g_cover_last.renderers[i].name.load(std::memory_order_relaxed);
    if (!n || !strcmp(n, "tfrag") || !strcmp(n, "tie")) {
      continue;
    }
    out += cover_renderer_line(n, " ");
  }
  // Per-draw-kind detail: the tfrag tree kind that owns the draw (cheap — the renderer already has
  // the tree). TIE contributes no kind label.
  for (int i = 0; i < kCoverSlots; i++) {
    const char* n = g_cover_last.kinds[i].name.load(std::memory_order_relaxed);
    if (!n) {
      continue;
    }
    const auto& s = g_cover_last.kinds[i];
    out +=
        fmt::format("[cover] tfrag_kind={} pbr_height={} disp_tess={} disp_pom={} disp_none={}\n",
                    n, cover_read(s.c, kCovHeight), cover_read(s.c, kCovTess),
                    cover_read(s.c, kCovPom), cover_read(s.c, kCovNone));
  }
  return out;
}

namespace {
// Gpbr-props-reach-draw. Un enregistrement par MATIERE rencontree a un draw. Ecrit depuis le seul
// thread GL (PbrDrawBinder::set), lu par l'ecrivain de diag sur le meme thread.
struct ReachRec {
  std::string family;
  bool authored = false;      // surfaces.json nomme cette matiere
  bool pushed = false;        // ses parametres ont ete RELUS dans l'objet programme
  bool from_readback = false; // reflectance/metallic viennent du programme, pas de nos variables
  bool mm_from_readback = false;  // clearcoat/aniso idem, mais depuis u_mm_coat / u_mm_aniso
  int mode = 0;               // u_pbr_mode au moment du push
  int mm_flags = 0;           // u_mm_flags au moment du push
  float clearcoat = 0.f;
  float aniso = 0.f;
  float reflectance = 0.f;
  float metallic = 0.f;
  float rough = 0.f;
};
std::unordered_map<std::string, ReachRec> g_reach;
u64 g_reach_draws = 0;
u32 g_reach_gen = 0;
}  // namespace

bool pbr_reach_needs_probe(const std::string& key) {
  const auto it = g_reach.find(key);
  return it == g_reach.end() || !it->second.pushed;
}

void pbr_reach_note_seen(const std::string& key, const PbrMaterialMaps& maps) {
  auto& r = g_reach[key];
  if (r.family.empty()) {
    g_reach_gen++;  // premiere apparition de cette matiere
    bool via_alias = false;
    const auto fam = g_pbrmat_family.find(surf_resolve_key(key, &via_alias));
    r.family = (fam == g_pbrmat_family.end()) ? "-" : fam->second;
  }
  r.authored = maps.pm_authored;
  if (!r.mm_from_readback) {
    r.clearcoat = maps.coat_weight;
    r.aniso = maps.aniso;
  }
  if (!r.from_readback) {
    // Repli CPU tant qu'aucune relecture n'a eu lieu. Marque comme tel dans la ligne publiee.
    r.reflectance = maps.pm_reflectance;
    r.metallic = maps.pm_metal_nomap;
    r.rough = maps.pm_rough_nomap;
  }
}

void pbr_reach_note_pushed(const std::string& key,
                           const float* mat_readback,
                           const float* mat2_readback,
                           int mode) {
  auto it = g_reach.find(key);
  if (it == g_reach.end()) {
    return;  // note_seen court toujours d'abord ; rien a inventer ici
  }
  ReachRec& r = it->second;
  if (!r.pushed) {
    g_reach_gen++;
  }
  r.pushed = true;
  r.mode = mode;
  if (mat_readback) {
    // u_pbr_mat = (rough_nomap, metal_nomap, reflectance, normal_y) — voir
    // pbr_push_material_uniforms(). Ces quatre nombres sortent de l'objet programme, pas de nous.
    r.rough = mat_readback[0];
    r.metallic = mat_readback[1];
    r.reflectance = mat_readback[2];
    r.from_readback = true;
  }
  (void)mat2_readback;
}

void pbr_reach_note_mm(const std::string& key,
                       const float* coat_readback,
                       const float* aniso_readback,
                       int mm_flags) {
  auto it = g_reach.find(key);
  if (it == g_reach.end()) {
    return;
  }
  ReachRec& r = it->second;
  r.mm_flags = mm_flags;
  // u_mm_coat = (coat_weight, coat_rough, sss_ambient, 0) et u_mm_aniso = (aniso, aniso_angle) —
  // voir PbrDrawBinder::set. Les deux sortent de l'objet programme.
  if (coat_readback) {
    r.clearcoat = coat_readback[0];
    r.mm_from_readback = true;
  }
  if (aniso_readback) {
    r.aniso = aniso_readback[0];
    r.mm_from_readback = true;
  }
}

void pbr_reach_note_draw() {
  g_reach_draws++;
}

u32 pbr_reach_generation() {
  return g_reach_gen;
}

std::string pbr_reach_section() {
  if (g_reach.empty()) {
    return {};
  }
  // Trie a travers un std::map pour que deux courses du meme etat emettent des lignes identiques
  // au bit (le stockage est un unordered_map, dont l'ordre n'est pas une promesse).
  std::map<std::string, const ReachRec*> sorted;
  for (const auto& kv : g_reach) {
    sorted[kv.first] = &kv.second;
  }
  int with_record = 0, pushed = 0, non_identity = 0;
  for (const auto& kv : sorted) {
    if (kv.second->authored) {
      with_record++;
    }
    if (kv.second->pushed) {
      pushed++;
      if (kv.second->authored &&
          (kv.second->clearcoat > 0.f || std::fabs(kv.second->aniso) > 0.f ||
           std::fabs(kv.second->reflectance - 0.04f) > 1e-6f ||
           kv.second->metallic > 0.f || std::fabs(kv.second->rough - 0.9f) > 1e-6f)) {
        non_identity++;
      }
    }
  }
  std::string out = "\n";
  out += fmt::format(
      "PBRREACH plateforme={} matieres_dans_table={} matieres_rencontrees={} avec_record={} "
      "params_deposes={} draws_consommes={} hors_identite={} modern_master={} "
      "textures_chargees={} textures_nommees={}\n",
#ifdef __ANDROID__
      "redmi",
#else
      "x86",
#endif
      (int)g_pbrmat_params.size(), (int)sorted.size(), with_record, pushed, g_reach_draws,
      non_identity, mm_master_active() ? 1 : 0, (int)g_surf_seen_tex.size(),
      (int)g_surf_named_tex.size());
  for (const auto& kv : sorted) {
    const ReachRec& r = *kv.second;
    out += fmt::format(
        "PBRVAL matiere={} famille={} clearcoat={:.4f} aniso={:.4f} reflectance={:.4f} "
        "metallic={:.4f} rugosite={:.4f} atteint_draw={} record={} source={} source_mm={} "
        "mode=0x{:x} mm_flags=0x{:x}\n",
        kv.first, r.family.empty() ? "-" : r.family, r.clearcoat, r.aniso, r.reflectance,
        r.metallic, r.rough, r.pushed ? 1 : 0, r.authored ? "oui" : "NO_RECORD",
        r.from_readback ? "readback" : "cpu", r.mm_from_readback ? "readback" : "cpu", r.mode,
        r.mm_flags);
  }
  out += fmt::format(
      "PBRNOTE draws_consommes est un compte CPU pris au bind, juste avant que l'appelant emette "
      "son draw : il ne prouve PAS qu'un fragment a tourne. `source=readback` veut dire que "
      "reflectance/metallic/rugosite ont ete RELUS par glGetUniformfv dans u_pbr_mat de l'objet "
      "programme que ce draw utilise, pas recopies depuis nos variables ; `source_mm=readback` dit "
      "la meme chose de clearcoat/aniso, relus de u_mm_coat / u_mm_aniso. clearcoat et aniso ne franchissent "
      "u_mm_flags que si la ligne de menu MODERN MATERIALS est active (elle est ici a {}) ; hors de "
      "ca ils valent 0 QUELLE QUE SOIT la valeur authoree. textures_chargees / textures_nommees "
      "sont prises a la DECISION D'INSCRIPTION, une par texture et par chargement : elles disent "
      "quelle part des surfaces que le jeu charge la table nomme, ce que le recensement du binder "
      "ne peut pas voir puisqu'il ne rencontre que des matieres inscrites.\n",
      mm_master_active() ? "1" : "0");
  return out;
}
#endif

void invalidate() {
  g_state.scanned = false;
  g_state.user_index.clear();
  g_state.bundled_index.clear();
}

void dump_key(const std::string& tpage_name, const std::string& tex_name) {
  static std::set<std::string> s_seen;
  const auto dir = file_util::get_custom_assets_replacements_dir(g_game_version);
  const auto marker = dir.parent_path() / "dump_keys";
  if (!fs::exists(marker)) {
    return;
  }
  const std::string key = tpage_name + "/" + tex_name;
  if (!s_seen.insert(key).second) {
    return;
  }
  const auto out_path = dir.parent_path() / "texture_keys_dump.txt";
  std::ofstream ofs(out_path.string(), std::ios::app);
  if (ofs) {
    ofs << key << "\n";
  }
}

}  // namespace custom_tex
