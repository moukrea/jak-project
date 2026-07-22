#include "CustomTextureReplacements.h"

#include <fstream>
#include <map>
#include <set>
#ifdef OG_FEAT_PBR
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
  out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(out.rgba.data(), data, out.rgba.size());
  stbi_image_free(data);

  lg::info("custom texture replacement ({}): {} <- {}", src, exact_key, path->string());
  return out;
}

#ifdef OG_FEAT_PBR
const ReplacementImage* lookup_suffixed(const std::string& tpage_name,
                                        const std::string& tex_name,
                                        const char* suffix) {
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
  // PRECEDENCE (owner): user custom_assets > bundled recharged > stock.
  const fs::path* path =
      user_on ? find_key(g_state.user_index, exact_key, suffixed_name) : nullptr;
  const char* src = "user";
  if (!path && bundled_on) {
    path = find_key(g_state.bundled_index, exact_key, suffixed_name);
    src = "bundled";
  }
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
  s_out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(s_out.rgba.data(), data, s_out.rgba.size());
  stbi_image_free(data);

  lg::info("custom pbr map ({}): {} <- {}", src, exact_key, path->string());
  return &s_out;
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
  lg::info("custom pbr material registered: {} (N={} R={} M={} AO={} H={})", tex_debug_name,
           maps.normal_tex ? 1 : 0, maps.rough_tex ? 1 : 0, maps.metal_tex ? 1 : 0,
           maps.ao_tex ? 1 : 0, maps.height_tex ? 1 : 0);
  return prev;
}

const PbrMaterialMaps* find_pbr_material(const std::string& tex_debug_name) {
  auto it = g_pbr_materials.find(tex_debug_name);
  return it == g_pbr_materials.end() ? nullptr : &it->second;
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
