#include "CustomTextureReplacements.h"

#include <atomic>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#ifdef OG_FEAT_PBR
#include <algorithm>
#include <unordered_map>
#endif

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/gfx.h"
#include "game/runtime.h"

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
int scan_dir(const fs::path& dir, std::map<std::string, fs::path>& index) {
  if (!fs::exists(dir)) {
    return 0;
  }
  int file_count = 0;
  for (const auto& entry : fs::recursive_directory_iterator(dir)) {
    if (!entry.is_regular_file()) {
      continue;
    }
    const auto& p = entry.path();
    if (p.extension() != ".png" && p.extension() != ".PNG") {
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

PbrMaterialMaps register_pbr_material(const std::string& tex_debug_name,
                                      const PbrMaterialMaps& maps) {
  PbrMaterialMaps prev;  // all-zero if none
  auto it = g_pbr_materials.find(tex_debug_name);
  if (it != g_pbr_materials.end()) {
    prev = it->second;
    it->second = maps;
  } else {
    g_pbr_materials.emplace(tex_debug_name, maps);
  }
  lg::info("custom pbr material registered: {} (N={} R={} M={} AO={} H={} S={} E={})",
           tex_debug_name, maps.normal_tex ? 1 : 0, maps.rough_tex ? 1 : 0,
           maps.metal_tex ? 1 : 0, maps.ao_tex ? 1 : 0, maps.height_tex ? 1 : 0,
           maps.specular_tex ? 1 : 0, maps.emissive_tex ? 1 : 0);
  return prev;
}

const PbrMaterialMaps* find_pbr_material(const std::string& tex_debug_name) {
  auto it = g_pbr_materials.find(tex_debug_name);
  return it == g_pbr_materials.end() ? nullptr : &it->second;
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
    // EXACTLY the amplitude law the shaders run, cap for cap and in the same order.
    const float upm = std::max(e.uv_per_m, 0.02f);
    const float tile_m = 1.0f / upm;
    const float lam_m = std::clamp(e.lambda_tiles, 0.002f, 1.0f) * tile_m;
    const float rel = height_scale * 20.0f;                // height_scale = 0.05 * texture-relief
    float amp_m = height_scale * 5.0f * lam_m;             // POM_DEPTH_K = 5
    amp_m = std::min(amp_m, 0.5f * lam_m);                 // MAX_RATIO
    amp_m = std::min(amp_m, 0.15f * (0.5f + 0.5f * rel));  // MAX_M
    amp_m = std::max(amp_m, 0.005f * rel);
    const float depth_uv = amp_m * upm;
    out += fmt::format(
        "[pom] mat={} uv_per_m={:.4f} tile_m={:.3f} height_lambda_tiles={:.4f} "
        "lambda_world_m={:.4f} amp_m={:.5f} depth_uv={:.5f} off45_uv={:.5f} off45_cm={:.2f} "
        "mode={} has_height={} displacement={} bisect={}\n",
        name, e.uv_per_m, tile_m, e.lambda_tiles, lam_m, amp_m, depth_uv, depth_uv, amp_m * 100.f,
        e.mode, has_height ? 1 : 0, gs.recharged_pbr_displacement, gs.recharged_pbr_isolate);
  }
  out += fmt::format("[pom] materials={} with_height={}\n", g_pom_diag.size(), with_height);
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
