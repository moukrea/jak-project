#include "CustomTextureReplacements.h"

#include <fstream>
#include <map>
#include <set>

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
  bool last_enable = false;
  fs::path scanned_dir;
  std::map<std::string, fs::path> index;
} g_state;

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

void ensure_scanned() {
  const bool enabled = Gfx::g_global_settings.load_custom_assets;
  // Rescan on an off->on transition so a freshly-dropped directory is picked up.
  if (g_state.scanned && g_state.last_enable == enabled) {
    return;
  }
  g_state.last_enable = enabled;
  g_state.scanned = true;
  g_state.index.clear();

  const auto dir = file_util::get_custom_assets_replacements_dir(g_game_version);
  g_state.scanned_dir = dir;
  if (!fs::exists(dir)) {
    return;
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
    // relative path key, without extension
    auto rel = fs::relative(p, dir);
    rel.replace_extension();
    std::string rel_key = normalize_key(rel.string());
    g_state.index[rel_key] = p;
    // bare filename key, without extension (fallback)
    std::string bare_key = p.stem().string();
    // don't clobber a more-specific relative key with a bare-name collision
    if (g_state.index.find(bare_key) == g_state.index.end()) {
      g_state.index[bare_key] = p;
    }
  }

  lg::info("custom texture replacements: {} files found in {}", file_count, dir.string());
}
}  // namespace

std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name) {
  if (!Gfx::g_global_settings.load_custom_assets) {
    return std::nullopt;
  }
  ensure_scanned();
  if (g_state.index.empty()) {
    return std::nullopt;
  }

  const std::string exact_key = normalize_key(tpage_name + "/" + tex_name);
  auto it = g_state.index.find(exact_key);
  if (it == g_state.index.end()) {
    // bare-name fallback
    it = g_state.index.find(tex_name);
    if (it == g_state.index.end()) {
      return std::nullopt;
    }
  }

  int w = 0, h = 0;
  auto* data = stbi_load(it->second.string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
  if (!data) {
    lg::warn("custom texture replacement: failed to load {}", it->second.string());
    return std::nullopt;
  }

  ReplacementImage out;
  out.w = w;
  out.h = h;
  out.rgba.resize((size_t)w * (size_t)h * 4);
  memcpy(out.rgba.data(), data, out.rgba.size());
  stbi_image_free(data);

  lg::info("custom texture replacement: {} <- {}", exact_key, it->second.string());
  return out;
}

void invalidate() {
  g_state.scanned = false;
  g_state.index.clear();
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
