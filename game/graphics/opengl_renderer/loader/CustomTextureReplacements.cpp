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
#include "game/runtime.h"

#include "third-party/json.hpp"
#include "third-party/stb_image/stb_image.h"

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
// Grecharged-materials-modern-parity — materials.txt, the AUTHORED half of a material.
//
// Every per-material number this pipeline had before today is MEASURED from the PNGs at load
// (normal DC, height mean/range, feature wavelength, UV density). That works because each of them is
// a statistic of an image. A scattering colour is not: whether a straw roof glows amber or a leaf
// glows green when the sun is behind it is an artistic decision about the SURFACE, and no amount of
// staring at its albedo will produce it. So the modern stack needs the one thing the pipeline never
// had — a place to author per-material parameters — and it must be a place the owner can edit
// without a rebuild.
//
// That place is recharged_assets/materials.txt in the EXTERNAL asset pack, with the same precedence
// rule physics_chains.txt established: an external copy beats the packaged one, so tuning costs a
// kilobyte push instead of a 581 MB APK. Parsing is deliberately the same shape as the physics file
// (# comments, whitespace tokens, unknown keys skipped and reported) so there is one file format to
// learn in this fork, not two.
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

std::vector<std::string> mm_tokens(const std::string& line) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < line.size()) {
    while (i < line.size() && std::isspace((unsigned char)line[i])) {
      i++;
    }
    size_t start = i;
    while (i < line.size() && !std::isspace((unsigned char)line[i])) {
      i++;
    }
    if (i > start) {
      out.push_back(line.substr(start, i - start));
    }
  }
  return out;
}

float mm_to_float(const std::string& s, float def) {
  try {
    return std::stof(s);
  } catch (...) {
    return def;
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

  // Same source precedence as physics_chains.txt: an external-pack copy beats the packaged one, so
  // the owner tunes a text file on the device instead of re-downloading the APK.
  const char* src_kind = "package";
  auto path = file_util::get_recharged_assets_dir() / "materials.txt";
  auto ext_dir = file_util::get_external_recharged_assets_dir();
  if (ext_dir) {
    auto ext_path = *ext_dir / "materials.txt";
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
      src_kind = "external-override";
    }
  }
  if (!file_util::file_exists(path.string())) {
    lg::info("[mm] PARAMSRC=none path={} (modern material stack has no authored materials)",
             path.string());
    return;
  }
  lg::info("[mm] PARAMSRC={} path={}", src_kind, path.string());

  std::string txt;
  try {
    txt = file_util::read_text_file(path.string());
  } catch (...) {
    lg::warn("[mm] materials.txt unreadable at {} — modern stack stays inert", path.string());
    return;
  }

  MmParamSet cur;
  // Gpbr-per-texture-materials: the second half of the block being parsed.
  PbrMatParams pcur;
  std::string cur_name;
  bool cur_is_defaults = false;
  bool have_block = false;
  // energy/spec-occlusion default ON inside any block: they are strict quality wins with no artistic
  // choice attached (they only make the existing specular obey energy conservation and stop it
  // leaking through the surface), so a minimal three-line block still gets them. `energy 0` /
  // `specocc 0` turn them back off for an A/B.
  bool energy_on = true, specocc_on = true, filmic_on = false;
  int line_no = 0, n_mat = 0, n_unknown = 0;

  auto flush = [&]() {
    if (!have_block) {
      return;
    }
    mm_recompute_flags(&cur, energy_on, specocc_on, filmic_on);
    if (cur_is_defaults) {
      g_mm_defaults = cur;
      g_mm_has_defaults = true;
      // Gpbr-per-texture-materials: the same block also carries the PBR-path knobs.
      g_pbrmat_defaults = pcur;
      g_pbrmat_has_defaults = true;
    } else {
      g_mm_params[cur_name] = cur;
      g_pbrmat_params[cur_name] = pcur;
      n_mat++;
    }
  };

  size_t pos = 0;
  while (pos <= txt.size()) {
    size_t nl = txt.find('\n', pos);
    std::string line = txt.substr(pos, (nl == std::string::npos) ? std::string::npos : nl - pos);
    pos = (nl == std::string::npos) ? txt.size() + 1 : nl + 1;
    line_no++;
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    auto hash = line.find('#');
    if (hash != std::string::npos) {
      line = line.substr(0, hash);
    }
    auto tok = mm_tokens(line);
    if (tok.empty()) {
      continue;
    }

    if (tok[0] == "material" || tok[0] == "[defaults]") {
      flush();
      cur = MmParamSet();
      pcur = PbrMatParams();
      energy_on = true;
      specocc_on = true;
      filmic_on = false;
      cur_is_defaults = (tok[0] == "[defaults]");
      cur_name = cur_is_defaults ? std::string() : (tok.size() > 1 ? tok[1] : std::string());
      have_block = cur_is_defaults || !cur_name.empty();
      if (!have_block) {
        lg::warn("[mm] materials.txt:{}: `material` with no name — block ignored", line_no);
      }
      continue;
    }
    if (!have_block) {
      lg::warn("[mm] materials.txt:{}: `{}` outside any material block — ignored", line_no, tok[0]);
      continue;
    }

    const std::string& k = tok[0];
    const size_t nv = tok.size() - 1;
    auto v = [&](size_t i, float def) { return (nv > i) ? mm_to_float(tok[i + 1], def) : def; };
    if (k == "sss" && nv >= 3) {
      cur.sss_color[0] = v(0, 1.f);
      cur.sss_color[1] = v(1, 1.f);
      cur.sss_color[2] = v(2, 1.f);
    } else if (k == "sss_strength") {
      cur.sss_strength = v(0, 0.f);
    } else if (k == "sss_thickness") {
      cur.sss_thickness = v(0, 0.5f);
    } else if (k == "sss_power") {
      cur.sss_power = v(0, 6.f);
    } else if (k == "sss_distort") {
      cur.sss_distort = v(0, 0.2f);
    } else if (k == "sss_wrap") {
      cur.sss_wrap = v(0, 0.f);
    } else if (k == "sss_ambient") {
      cur.sss_ambient = v(0, 0.25f);
    } else if (k == "clearcoat") {
      cur.coat_weight = v(0, 0.f);
    } else if (k == "clearcoat_rough") {
      cur.coat_rough = v(0, 0.10f);
    } else if (k == "aniso") {
      cur.aniso = v(0, 0.f);
    } else if (k == "aniso_angle") {
      cur.aniso_angle = v(0, 0.f);
    } else if (k == "energy") {
      energy_on = v(0, 1.f) != 0.f;
    } else if (k == "specocc") {
      specocc_on = v(0, 1.f) != 0.f;
    } else if (k == "filmic") {
      filmic_on = v(0, 0.f) != 0.f;
      // ---- Gpbr-per-texture-materials: the PBR-PATH knobs. Same blocks, same parser, but these
      // land in pcur and are NOT behind the MODERN MATERIALS row (see PbrMatParams).
    } else if (k == "relief") {
      pcur.relief = v(0, 1.f);
    } else if (k == "relief_depth") {
      pcur.relief_depth = v(0, 1.f);
    } else if (k == "relief_lambda") {
      pcur.relief_lambda = v(0, 0.f);
    } else if (k == "spec") {
      pcur.spec = v(0, 1.f);
    } else if (k == "roughness") {
      pcur.rough_nomap = v(0, 0.9f);
    } else if (k == "roughness_scale") {
      pcur.rough_scale = v(0, 1.f);
    } else if (k == "metallic") {
      pcur.metal_nomap = v(0, 0.f);
    } else if (k == "metallic_scale") {
      pcur.metal_scale = v(0, 1.f);
    } else if (k == "reflectance") {
      pcur.reflectance = v(0, 0.04f);
    } else if (k == "normal_y") {
      // Only the two handedness conventions exist (+1 = OpenGL green-up, -1 = DirectX green-down).
      // Anything else would be a silent partial flip, so it is refused and reported, not clamped.
      const float ny = v(0, 1.f);
      if (ny == 1.f || ny == -1.f) {
        pcur.normal_y = ny;
      } else {
        lg::warn("[mm] materials.txt:{}: normal_y `{}` is neither 1 nor -1 — using 1", line_no,
                 tok.size() > 1 ? tok[1] : std::string());
        pcur.normal_y = 1.f;
      }
    } else {
      n_unknown++;
      lg::warn("[mm] materials.txt:{}: unknown key `{}` — skipped", line_no, k);
    }
  }
  flush();
  lg::info("[mm] materials.txt parsed: {} material blocks, defaults={}, {} unknown keys", n_mat,
           g_mm_has_defaults ? 1 : 0, n_unknown);

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
      lg::info(
          "[pbrmat] {} relief={:.3f} depth={:.3f} lambda={:.3f} spec={:.3f} rough={:.3f}x{:.3f} "
          "metal={:.3f}x{:.3f} F0={:.3f} ny={:+.0f}",
          kv.first, p.relief, p.relief_depth, p.relief_lambda, p.spec, p.rough_nomap, p.rough_scale,
          p.metal_nomap, p.metal_scale, p.reflectance, p.normal_y);
    }
  }

  // Re-stamp everything already registered so a menu toggle applies without a level reload. Texture-
  // derived bits survive; authored ones are recomputed from the freshly parsed file (or cleared, if
  // the master went off).
  for (auto& kv : g_pbr_materials) {
    mm_apply_params(kv.first, &kv.second);
    // Gpbr-per-texture-materials: the PBR-path knobs are re-stamped on the SAME walk, so an edit to
    // materials.txt reaches them through the same menu toggle that reloads the modern half.
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
  auto it = g_mm_params.find(tex_debug_name);
  // MERGE 2026-08-26. The PBR registry is now keyed "<tpage>/<name>" (branch fix: a bare
  // name let one tpage's registration delete another's maps). materials.txt, however, names
  // materials by their BARE debug name — and mm_params_reload() re-stamps by walking the
  // registry, so it hands us the composite key. Without this fallback every authored block
  // would stop matching on the FIRST reload (menu toggle), silently emptying the modern
  // stack while the first stamp from the loader still worked: the worst kind of regression,
  // one that only appears after an interaction.
  if (it == g_mm_params.end()) {
    const auto slash = tex_debug_name.rfind('/');
    if (slash != std::string::npos) {
      it = g_mm_params.find(tex_debug_name.substr(slash + 1));
    }
  }
  if (it != g_mm_params.end()) {
    p = &it->second;
  } else if (g_mm_has_defaults) {
    p = &g_mm_defaults;
  }
  if (!p) {
    // Not named, no [defaults] block: this material stays exactly as the accepted PBR path built it.
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
  // would make every preset in materials.txt inert while still LOOKING wired.
  if (!g_mm_loaded) {
    mm_params_reload();
  }
  const PbrMatParams* p = nullptr;
  auto it = g_pbrmat_params.find(tex_debug_name);
  // Same two-step key resolution as mm_apply_params: the registry is keyed "<tpage>/<name>" while
  // materials.txt names materials by their BARE debug name, and the re-stamp walk hands us the
  // composite key. Without the fallback every block would stop matching on the FIRST reload.
  if (it == g_pbrmat_params.end()) {
    const auto slash = tex_debug_name.rfind('/');
    if (slash != std::string::npos) {
      it = g_pbrmat_params.find(tex_debug_name.substr(slash + 1));
    }
  }
  if (it != g_pbrmat_params.end()) {
    p = &it->second;
  } else if (g_pbrmat_has_defaults) {
    p = &g_pbrmat_defaults;
  }
  if (!p) {
    // Nobody named this material and there is no [defaults] block: leave every pm_* field at its
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
// Per-channel active-draw counters. Written from the GL thread only, read by the diag writer, so
// relaxed atomics are enough and cost nothing on the hot path.
std::atomic<u64> g_mm_draws_total{0};
std::atomic<u64> g_mm_draws_sss{0};
std::atomic<u64> g_mm_draws_coat{0};
std::atomic<u64> g_mm_draws_aniso{0};
std::atomic<u64> g_mm_draws_energy{0};
std::atomic<u64> g_mm_draws_specocc{0};
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

std::string mm_params_diag_section() {
  std::string out;
  int n = 0;
  for (const auto& kv : g_pbr_materials) {
    if (kv.second.mm_flags == 0) {
      continue;
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
  if (n || tot) {
    out += fmt::format(
        "[mm] {} material(s) carry the modern stack; ACTIVE DRAWS total={} sss={} coat={} "
        "aniso={} energy={} specocc={}\n",
        n, tot, g_mm_draws_sss.load(std::memory_order_relaxed),
        g_mm_draws_coat.load(std::memory_order_relaxed),
        g_mm_draws_aniso.load(std::memory_order_relaxed),
        g_mm_draws_energy.load(std::memory_order_relaxed),
        g_mm_draws_specocc.load(std::memory_order_relaxed));
  }
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
