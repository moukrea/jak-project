/*!
 * @file FileUtil.cpp
 * Utility functions for reading and writing files.
 */

#include "FileUtil.h"

#include <algorithm>
#include <chrono>
#include <cstdio> /* defines FILENAME_MAX */
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <mutex>
#include <sstream>

#include "BinaryWriter.h"

#include "common/common_types.h"
#include "common/util/BinaryReader.h"
#include "common/util/string_util.h"
#include "common/util/unicode_util.h"

// This disables the use of PCLMULQDQ which is probably ok, but let's just be safe and disable it
// because nobody will care if png compression is 10% slower.
#define FPNG_NO_SSE 1
#include "fmt/format.h"
#include "third-party/fpng/fpng.cpp"
#include "third-party/fpng/fpng.h"
#include "third-party/lzokay/lzokay.hpp"

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#else
#include <cstring>
#include <unistd.h>
#endif
#include "common/log/log.h"
#include "common/util/Assert.h"

#ifdef __APPLE__
#include <crt_externs.h>
#include <limits.h>

#include "mach-o/dyld.h"
#endif

namespace file_util {
fs::path get_user_home_dir() {
#ifdef _WIN32
  // NOTE - on older systems, this may case issues if it cannot be found!
  std::string home_dir = get_env("USERPROFILE");
  return fs::path(home_dir);
#else
  std::string home_dir = get_env("HOME");
  return fs::path(home_dir);
#endif
}

struct {
  bool initialized = false;
  fs::path path_to_data_folder;
  fs::path user_config_dir_override = "";
  // by default - if the config dir is overridden, we don't use the default save location
  bool use_overridden_config_dir_for_saves = true;
} g_file_path_info;

// External per-game "game root" directory (e.g. /sdcard/OpenGOAL/jak1). When
// set, arch-independent assets and saves resolve under this root. The tree
// shape is:
//   <root>/assets/          (unaltered source-derived vanilla data)
//   <root>/custom_assets/   (user-dropped texture replacements)
//   <root>/saves/           (memory cards / save games)
//   <root>/settings.ini     (persisted user settings, at the root)
// Unset == legacy behavior.
std::optional<fs::path> g_external_game_root;
// Separate iso overlay dir holding per-arch compiled *.CGO/*.DGO (+ platform
// COMMON.TXT overrides) shipped with the binary.
std::optional<fs::path> g_iso_overlay_dir;
// Port-custom assets (recharged PNGs, .grassbake, enhanced fr3) shipped inside
// the package (APK-internal / desktop archive), distinct from the external
// vanilla data tree. When set, takes precedence over external/project roots.
std::optional<fs::path> g_custom_assets_root;

void set_external_game_root(const fs::path& root) {
  g_external_game_root = root;
}

std::optional<fs::path> get_external_game_root() {
  return g_external_game_root;
}

void set_iso_overlay_dir(const fs::path& p) {
  g_iso_overlay_dir = p;
}

std::optional<fs::path> get_iso_overlay_dir() {
  return g_iso_overlay_dir;
}

void set_custom_assets_root(const fs::path& p) {
  g_custom_assets_root = p;
}

std::optional<fs::path> get_custom_assets_root() {
  return g_custom_assets_root;
}

std::optional<fs::path> get_custom_fr3_dir() {
  if (g_custom_assets_root) {
    return *g_custom_assets_root / "fr3";
  }
  return {};
}

fs::path get_user_config_dir() {
  fs::path config_base_path;
#ifdef _WIN32
  auto config_base_dir = get_env("APPDATA");
  config_base_path = fs::path(config_base_dir);
#elif __linux
  // Docs - https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
  // Prefer XDG_CONFIG_HOME if available
  auto config_base_dir = get_env("XDG_CONFIG_HOME");
  if (config_base_dir.empty()) {
    config_base_path = get_user_home_dir() / ".config";
  } else {
    config_base_path = fs::path(config_base_dir);
  }
#elif __APPLE__
  auto config_base_dir = get_env("HOME");
  config_base_path = fs::path(config_base_dir) / "Library" / "Application Support";
#endif
  return config_base_path / "OpenGOAL";
}

fs::path get_user_settings_dir(GameVersion game_version) {
  // External game root takes precedence over the --portable/--config-path override.
  if (g_external_game_root) {
    // settings.ini lives at the game root itself (<root>/settings.ini).
    return *g_external_game_root;
  }
  auto game_version_name = game_version_names[game_version];
  auto config_dir = get_user_config_dir();
  if (!g_file_path_info.user_config_dir_override.empty()) {
    config_dir = g_file_path_info.user_config_dir_override / "OpenGOAL";
  }
  return config_dir / game_version_name / "settings";
}

fs::path get_user_memcard_dir(GameVersion game_version) {
  // External game root takes precedence over the --portable/--config-path override.
  if (g_external_game_root) {
    return *g_external_game_root / "saves";
  }
  auto game_version_name = game_version_names[game_version];
  auto config_dir = get_user_config_dir();
  if (!g_file_path_info.user_config_dir_override.empty() &&
      g_file_path_info.use_overridden_config_dir_for_saves) {
    config_dir = g_file_path_info.user_config_dir_override / "OpenGOAL";
  }
  return config_dir / game_version_name / "saves";
}

fs::path get_user_screenshots_dir(GameVersion game_version) {
  // External game root takes precedence over the --portable/--config-path override.
  if (g_external_game_root) {
    return *g_external_game_root / "saves" / "screenshots";
  }
  auto game_version_name = game_version_names[game_version];
  auto config_dir = get_user_config_dir();
  if (!g_file_path_info.user_config_dir_override.empty()) {
    config_dir = g_file_path_info.user_config_dir_override / "OpenGOAL";
  }
  return config_dir / game_version_name / "screenshots";
}

fs::path get_user_misc_dir(GameVersion game_version) {
  // External game root takes precedence over the --portable/--config-path override.
  if (g_external_game_root) {
    return *g_external_game_root / "saves" / "misc";
  }
  auto game_version_name = game_version_names[game_version];
  auto config_dir = get_user_config_dir();
  if (!g_file_path_info.user_config_dir_override.empty()) {
    config_dir = g_file_path_info.user_config_dir_override / "OpenGOAL";
  }
  return config_dir / game_version_name / "misc";
}

fs::path get_user_features_dir(GameVersion game_version) {
  // External game root takes precedence over the --portable/--config-path override.
  if (g_external_game_root) {
    auto path = *g_external_game_root / "saves" / "features";
    file_util::create_dir_if_needed(path);
    return path;
  }
  auto game_version_name = game_version_names[game_version];
  auto config_dir = get_user_config_dir();
  if (!g_file_path_info.user_config_dir_override.empty()) {
    config_dir = g_file_path_info.user_config_dir_override / "OpenGOAL";
  }
  auto path = config_dir / game_version_name / "features";
  file_util::create_dir_if_needed(path);
  return path;
}

fs::path g_iso_data_directory = "";

/*!
 * Get the path to the current executable.
 */
std::string get_current_executable_path() {
#ifdef _WIN32
  // NOTE - MAX_PATH is kinda wrong here as you can have a path longer than 260 in windows
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(NULL, path, MAX_PATH);
  std::string file_path = wide_string_to_utf8_string(path);
  if (file_path.rfind("\\\\?\\", 0) == 0) {
    return file_path.substr(4);
  }
  return file_path;
#elif __linux
  char buffer[FILENAME_MAX + 1];
  auto len = readlink("/proc/self/exe", buffer,
                      FILENAME_MAX);  // /proc/self acts like a "virtual folder" containing
  // information about the current process
  buffer[len] = '\0';
  return std::string(buffer);
#elif __APPLE__
  char buffer[PATH_MAX];
  uint32_t bufsize = sizeof(buffer);
  if (_NSGetExecutablePath(buffer, &bufsize) != 0) {
    lg::warn("Could not get executable path, trying with _NSGetArgv()[0] instead.");
    auto argv = *_NSGetArgv();
    return std::string(argv[0]);
  }
  return std::string(buffer);
#endif
}

std::optional<std::string> try_get_project_path_from_path(const std::string& path) {
  std::string::size_type pos =
      std::string(path).rfind("jak-project");  // Strip file path down to /jak-project/ directory
  if (pos == std::string::npos) {
    return {};
  }
  return std::string(path).substr(
      0, pos + 11);  // + 12 to include "/jak-project" in the returned filepath
}

/*!
 * See if the current executable is somewhere in jak-project/. If so, return the path to jak-project
 */
std::optional<std::string> try_get_jak_project_path() {
  return try_get_project_path_from_path(get_current_executable_path());
}

std::optional<fs::path> try_get_data_dir(bool skip_logs) {
  fs::path my_path = get_current_executable_path();
  if (!skip_logs) {
    lg::debug("Current executable directory - {}", my_path.string());
  }
  auto data_dir = my_path.parent_path() / "data";
  if (fs::exists(data_dir) && fs::is_directory(data_dir)) {
    return std::make_optional(data_dir);
  } else {
    return {};
  }
}

bool setup_project_path(std::optional<fs::path> project_path_override, bool skip_logs) {
  if (g_file_path_info.initialized) {
    return true;
  }

  if (project_path_override) {
    g_file_path_info.path_to_data_folder = fs::absolute(project_path_override.value());
    g_file_path_info.initialized = true;
    if (!skip_logs) {
      lg::debug("Using explicitly set project path: {}",
                g_file_path_info.path_to_data_folder.string());
    }
    return true;
  }

  auto data_path = try_get_data_dir(skip_logs);
  if (data_path) {
    g_file_path_info.path_to_data_folder = *data_path;
    g_file_path_info.initialized = true;
    if (!skip_logs) {
      lg::debug("Using data path: {}", data_path->string());
    }
    return true;
  }

  auto development_repo_path = try_get_jak_project_path();
  if (development_repo_path) {
    g_file_path_info.path_to_data_folder = *development_repo_path;
    g_file_path_info.initialized = true;
    if (!skip_logs) {
      lg::debug("Using development repo path: {}", *development_repo_path);
    }
    return true;
  }

  lg::error("Failed to initialize project path.");
  return false;
}

void override_user_config_dir(fs::path user_config_dir_override,
                              bool use_overridden_config_dir_for_saves) {
  g_file_path_info.user_config_dir_override = user_config_dir_override;
  g_file_path_info.use_overridden_config_dir_for_saves = use_overridden_config_dir_for_saves;
}

fs::path get_jak_project_dir() {
  ASSERT(g_file_path_info.initialized);
  return g_file_path_info.path_to_data_folder;
}

fs::path get_iso_dir_for_game(GameVersion game_version) {
  if (!g_iso_data_directory.empty()) {
    return g_iso_data_directory;
  }
  // Find the location based on the game version
  std::string expected_subdir = "jak1";
  if (game_version == GameVersion::Jak2) {
    expected_subdir = "jak2";
  } else if (game_version == GameVersion::Jak3) {
    expected_subdir = "jak3";
  }
  const auto temp_dir = get_jak_project_dir() / "iso_data" / expected_subdir;
  if (fs::exists(temp_dir)) {
    g_iso_data_directory = temp_dir;
  }
  return g_iso_data_directory;
}

void set_iso_data_dir(const fs::path& directory) {
  g_iso_data_directory = directory;
}

fs::path get_iso_out_dir(GameVersion game_version) {
  if (g_external_game_root) {
    return *g_external_game_root / "assets" / "iso";
  }
  return get_jak_project_dir() / "out" / game_version_names[game_version] / "iso";
}

fs::path get_fr3_dir(GameVersion game_version) {
  if (g_external_game_root) {
    return *g_external_game_root / "assets" / "fr3";
  }
  return get_jak_project_dir() / "out" / game_version_names[game_version] / "fr3";
}

namespace {
// Whole seconds, 0 when unavailable. Whole seconds deliberately: the device filesystem stores
// second granularity, so a finer comparison would invent skew between a host file and its pushed copy.
s64 file_mtime_seconds(const fs::path& p) {
  std::error_code ec;
  const auto t = fs::last_write_time(p, ec);
  if (ec) {
    return 0;
  }
  return (s64)std::chrono::duration_cast<std::chrono::seconds>(t.time_since_epoch()).count();
}

u64 file_size_or_zero(const fs::path& p) {
  std::error_code ec;
  const auto s = fs::file_size(p, ec);
  return ec ? 0u : (u64)s;
}
}  // namespace

void asset_route_journal(const std::string& line) {
  static std::mutex mtx;
  std::lock_guard<std::mutex> lock(mtx);
  try {
    const auto path = get_jak_project_dir() / "asset_route.txt";
    std::string existing;
    try {
      existing = read_text_file(path);
    } catch (...) {
      existing.clear();
    }
    if (existing.size() > 512u * 1024u) {
      existing.clear();  // a long session must not fill the device
    }
    write_text_file(path, existing + line);
  } catch (const std::exception& e) {
    lg::warn("[asset-route] could not write asset_route.txt: {}", e.what());
  }
}

Fr3AssetRoute resolve_fr3_asset(const fs::path& base_dir, const std::string& file_name) {
  Fr3AssetRoute r;
  const fs::path base = base_dir / file_name;
  std::error_code ec;
  r.base_exists = fs::is_regular_file(base, ec);
  if (r.base_exists) {
    r.base_bytes = file_size_or_zero(base);
    r.base_mtime = file_mtime_seconds(base);
  }
  fs::path custom;
  if (auto custom_dir = get_custom_fr3_dir()) {
    custom = *custom_dir / file_name;
    r.custom_exists = fs::is_regular_file(custom, ec);
    if (r.custom_exists) {
      r.custom_bytes = file_size_or_zero(custom);
      r.custom_mtime = file_mtime_seconds(custom);
    }
  }
  if (r.custom_exists) {
    r.path = custom;
    r.source = "custom-pack";
  } else if (r.base_exists) {
    r.path = base;
    r.source = "base-pack";
  } else {
    r.path = base;  // let the caller's open fail against the conventional path
    r.source = "missing";
  }
  // FRESHNESS IS MEASURED, NOT ASSUMED. Precedence alone would happily serve a packaged file older
  // than the external one; saying so out loud is what turns "the fix didn't land" into one grep.
  r.bundle_stale = r.custom_exists && r.base_exists && r.base_mtime > r.custom_mtime;
  const std::string line = fmt::format(
      "[asset-route] {} -> {} ({}) custom={}{}B/t{} base={}{}B/t{}{}\n", file_name, r.path.string(),
      r.source, r.custom_exists ? "yes " : "no ", r.custom_bytes, r.custom_mtime,
      r.base_exists ? "yes " : "no ", r.base_bytes, r.base_mtime,
      r.bundle_stale ? " STALE-BUNDLE(external copy is NEWER than the packaged one — the packaging"
                       " freshness guard was bypassed)"
                     : "");
  asset_route_journal(line);
  if (r.bundle_stale) {
    lg::warn("{}", line);
  } else {
    lg::info("{}", line);
  }
  return r;
}

Fr3AssetRoute resolve_fr3_asset(GameVersion game_version, const std::string& file_name) {
  return resolve_fr3_asset(get_fr3_dir(game_version), file_name);
}

fs::path get_recharged_assets_dir() {
  // Precedence: package-shipped custom assets > external vanilla tree > project.
  if (g_custom_assets_root) {
    return *g_custom_assets_root / "recharged_assets";
  }
  if (g_external_game_root) {
    return *g_external_game_root / "assets" / "recharged_assets";
  }
  return get_jak_project_dir() / "recharged_assets";
}

std::optional<fs::path> get_external_recharged_assets_dir() {
  if (g_external_game_root) {
    return *g_external_game_root / "assets" / "recharged_assets";
  }
  return {};
}

fs::path get_custom_assets_replacements_dir(GameVersion game_version) {
  if (g_external_game_root) {
    // Flat user drop dir: <root>/custom_assets.
    return *g_external_game_root / "custom_assets";
  }
  return get_jak_project_dir() / "custom_assets" / game_version_names[game_version] /
         "texture_replacements";
}

// Grecharged-bundled-textures: first-party replacement textures shipped INSIDE the game
// package (owner-made Recharged set, committed at custom_assets/<game>/recharged_textures/).
// On Android the custom pack extracts them under <custom root>/recharged_textures; on desktop
// the checked-out repo tree is read directly. Distinct from the USER drop dir above —
// the user > bundled precedence is applied by the texture-replacement scanner, not here.
fs::path get_bundled_recharged_textures_dir(GameVersion game_version) {
  if (g_custom_assets_root) {
    return *g_custom_assets_root / "recharged_textures";
  }
  return get_jak_project_dir() / "custom_assets" / game_version_names[game_version] /
         "recharged_textures";
}

// Gshield-load-and-crash: the PRE-BAKED twin of the directory above. EXACTLY the same root
// resolution (extracted custom-pack root on Android, checked-out tree on desktop) — only the
// last two components differ: "<...>_baked/<profile>". Keeping the resolution identical is the
// point: a baked material is the same material, shipped through the same pack, and must never
// resolve against a different root than the PNG it replaces.
fs::path get_bundled_recharged_textures_baked_dir(GameVersion game_version, const char* profile) {
  const std::string sub = std::string("recharged_textures_baked");
  if (g_custom_assets_root) {
    return *g_custom_assets_root / sub / profile;
  }
  return get_jak_project_dir() / "custom_assets" / game_version_names[game_version] / sub / profile;
}

// Grecharged-mesh-browser: same ship path as the bundled recharged textures above (extracted
// custom-pack root on Android, checked-out tree on desktop), one subdir over. Holds one
// mesh_index_<level>.txt per level, produced offline by tools/mesh_index from the tess_sign CSV.
fs::path get_bundled_mesh_index_dir(GameVersion game_version) {
  if (g_custom_assets_root) {
    return *g_custom_assets_root / "mesh_index";
  }
  return get_jak_project_dir() / "custom_assets" / game_version_names[game_version] / "mesh_index";
}

std::string get_file_path(const std::vector<std::string>& input) {
  // TODO - clean this behaviour up, it causes unexpected behaviour when working with files
  // the project path should be explicitly provided by whatever if needed
  // TEMP HACK
  // - if the provided path is absolute, don't add the project path
  if (input.size() == 1 && fs::path(input.at(0)).is_absolute()) {
    return input.at(0);
  }

  auto current_path = file_util::get_jak_project_dir();
  for (auto& str : input) {
    current_path /= str;
  }

  return current_path.string();
}

bool create_dir_if_needed(const fs::path& path) {
  if (!fs::is_directory(path)) {
    fs::create_directories(path);
    return true;
  }
  return false;
}

// TODO - explodes if the file path is invalid
bool create_dir_if_needed_for_file(const std::string& path) {
  return create_dir_if_needed_for_file(fs::path(path));
}

// TODO - explodes if the file path is invalid
bool create_dir_if_needed_for_file(const fs::path& path) {
  return fs::create_directories(path.parent_path());
}

void write_binary_file(const fs::path& name, const void* data, size_t size) {
  FILE* fp = file_util::open_file(name.string().c_str(), "wb");
  if (!fp) {
    throw std::runtime_error("couldn't open file " + name.string());
  }

  if (size == 0) {
    // nothing to write, just 'touch' the file
    fclose(fp);
    return;
  }

  if (fwrite(data, size, 1, fp) != 1) {
    fclose(fp);
    throw std::runtime_error("couldn't write file " + name.string());
  }

  fclose(fp);
}

void write_binary_file(const std::string& name, const void* data, size_t size) {
  write_binary_file(fs::path(name), data, size);
}

void write_rgba_png(const fs::path& name, void* data, int w, int h) {
  auto flags = 0;

  auto ok = fpng::fpng_encode_image_to_file(name.string().c_str(), data, w, h, 4, flags);

  if (!ok) {
    throw std::runtime_error("couldn't save png file " + name.string());
  }
}

void write_text_file(const std::string& file_name, const std::string& text) {
  write_text_file(fs::path(file_name), text);
}

void write_text_file(const fs::path& file_name, const std::string& text) {
  FILE* fp = file_util::open_file(file_name.string().c_str(), "w");
  if (!fp) {
    lg::error("Failed to fopen {}\n", file_name.string());
    throw std::runtime_error("Failed to open file");
  }
  fprintf(fp, "%s\n", text.c_str());
  fclose(fp);
}
std::vector<uint8_t> read_binary_file(const std::string& filename) {
  return read_binary_file(fs::path(filename));
}

std::vector<uint8_t> read_binary_file(const fs::path& path) {
  // make sure file exists and isn't a directory

  auto status = fs::status(path);

  if (!fs::exists(status)) {
    throw std::runtime_error(
        fmt::format("File {} cannot be opened: does not exist.", path.string()));
  }

  if (status.type() != fs::file_type::regular && status.type() != fs::file_type::symlink) {
    throw std::runtime_error(
        fmt::format("File {} cannot be opened: not a regular file or symlink.", path.string()));
  }

  auto fp = file_util::open_file(path.string().c_str(), "rb");
  if (!fp)
    throw std::runtime_error("File " + path.string() +
                             " cannot be opened: " + std::string(strerror(errno)));
  fseek(fp, 0, SEEK_END);
  auto len = ftell(fp);
  if (len == 0) {
    fclose(fp);
    return {};
  }
  rewind(fp);

  std::vector<uint8_t> data;
  data.resize(len);

  if (fread(data.data(), len, 1, fp) != 1) {
    fclose(fp);
    throw std::runtime_error("File " + path.string() + " cannot be read");
  }
  fclose(fp);

  return data;
}

std::string read_text_file(const fs::path& path) {
  fs::ifstream file(path);
  if (!file.good()) {
    throw std::runtime_error("couldn't open " + path.string());
  }
  std::stringstream ss;
  ss << file.rdbuf();
  return ss.str();
}

std::string read_text_file(const std::string& path) {
  return read_text_file(fs::path(path));
}

bool is_printable_char(char c) {
  return c >= ' ' && c <= '~';
}

std::string combine_path(const std::string& parent, const std::string& child) {
  return parent + "/" + child;
}

bool file_exists(const std::string& path) {
  return fs::exists(path);
}

std::string base_name(const std::string& filename) {
  size_t pos = 0;
  ASSERT(!filename.empty());
  for (size_t i = filename.size() - 1; i-- > 0;) {
    if (filename.at(i) == '/' || filename.at(i) == '\\') {
      pos = (i + 1);
      break;
    }
  }
  return filename.substr(pos);
}

std::string base_name_no_ext(const std::string& filename) {
  size_t pos = 0;
  ASSERT(!filename.empty());
  for (size_t i = filename.size() - 1; i-- > 0;) {
    if (filename.at(i) == '/' || filename.at(i) == '\\') {
      pos = (i + 1);
      break;
    }
  }
  std::string file_name = filename.substr(pos);
  return file_name.substr(0, file_name.find_last_of('.'));
  ;
}

std::string split_path_at(const fs::path& path, const std::vector<std::string>& folders) {
  std::string split_str = "";
  for (const auto& folder : folders) {
#ifdef _WIN32
    split_str += folder + "\\";
#else
    split_str += folder + "/";
#endif
  }
  const auto& path_str = path.string();
  return path_str.substr(path_str.find(split_str) + split_str.length());
}

std::string convert_to_unix_path_separators(const std::string& path) {
#ifdef _WIN32
  std::string copy = path;
  std::replace(copy.begin(), copy.end(), '\\', '/');
  return copy;
#else
  return path;
#endif
}

/*!
 * Convert an animation name to ISO name.
 * The animation name is a bunch of dash separated words.
 * The resulting ISO name has the same first two chars as the animation name, and one char from each
 * remaining word. Once there are no more words but remaining chars in the ISO name, the ith extra
 * char is the i+1 th char of the last word. A word ending in a number (or just a number) is turned
 * into the number. The word "resolution" becomes z. The word "accept" becomes y. The word "reject"
 * becomes n. Other words become the first char of the word. The result is uppercased and the file
 * extension is STR Examples (animation name and disc file name, not ISO name):
 *  green-sagecage-outro-beat-boss-enough-cells -> GRSOBBEC.STR
 *  swamp-tetherrock-swamprockexplode-4 -> SWTS4.STR
 *  minershort-resolution-1-orbs -> MIZ1ORBS.STR
 */
void ISONameFromAnimationName(char* dst, const char* src) {
  // The Animation Name is a bunch of words separated by dashes

  // copy first two chars of the first word exactly
  dst[0] = src[0];
  dst[1] = src[1];
  s32 i = 2;  // 2 chars added to dst.

  // skip ahead to the first dash (or \0 if there's no dashes)
  const char* src_ptr = src;
  while (*src_ptr && *src_ptr != '-') {
    src_ptr++;
  }

  // the points to the next dash (or \0 if there's none).
  const char* next_ptr = src_ptr;
  if (*src_ptr) {
    // loop over words (next_ptr points to dash before word, i counts chars in dest)
    while (src_ptr = next_ptr + 1, i < 8) {
      // scan next_ptr forward to next dash
      next_ptr = src_ptr;
      while (*next_ptr && *next_ptr != '-') {
        next_ptr++;
      }

      // there's no next word, so break (the current word will be handled there)
      if (!*next_ptr)
        break;

      // add a char for the current word:
      char char_to_add;
      if (next_ptr[-1] < '0' || next_ptr[-1] > '9') {
        // word doesn't end in a number.

        // some special case words map to special letters (likely to avoid animation name conflicts)
        if (next_ptr - src_ptr == 10 && !memcmp(src_ptr, "resolution", 10)) {
          // NOTE : jak 2 also allows "res" here but that doesn't work properly.
          char_to_add = 'z';
        } else if (next_ptr - src_ptr == 6 && !memcmp(src_ptr, "accept", 6)) {
          char_to_add = 'y';
        } else if (next_ptr - src_ptr == 6 && !memcmp(src_ptr, "reject", 6)) {
          char_to_add = 'n';
        } else if (next_ptr - src_ptr == 5 && !memcmp(src_ptr, "keira", 5)) {
          // NOTE : this was added in jak 2. it's safe to use in jak 1 since she was referred to as
          // "assistant" there
          char_to_add = 'i';
        } else {
          // not a special case, just take the first letter.
          char_to_add = *src_ptr;
        }
      } else {
        // the current word ends in a number, just use this number (I think usually the whole word
        // is just a number)
        char_to_add = next_ptr[-1];
      }

      dst[i++] = char_to_add;
    }

    // here we ran out of room in dest, or words in source.
    // if there's still room in dest and chars in source, just add them
    while (*src_ptr && (i < 8)) {
      dst[i] = *src_ptr;
      src_ptr++;
      i++;
    }
  }

  // pad with spaces (for ISO Name)
  while (i < 8) {
    dst[i++] = ' ';
  }

  // upper case
  for (i = 0; i < 8; i++) {
    if (dst[i] >= 'a' && dst[i] <= 'z') {
      dst[i] -= 0x20;
    }
  }

  // append file extension
  strcpy(dst + 8, "STR");
}

/*!
 * Convert file name to "ISO Name"
 * ISO names are upper case and 12 bytes long.
 * xxxxxxxxyyy0
 *
 * x - uppercase letter of file name, or space
 * y - uppercase letter of file extension, or space
 * 0 - null terminator (\0, not the character zero)
 */
void MakeISOName(char* dst, const char* src) {
  int i = 0;
  const char* src_ptr = src;
  char* dst_ptr = dst;

  // copy name and upper case
  while ((i < 8) && (*src_ptr) && (*src_ptr != '.')) {
    char c = *src_ptr;
    src_ptr++;
    if (('`' < c) && (c < '{')) {  // lower case
      c -= 0x20;
    }
    *dst_ptr = c;
    dst_ptr++;
    i++;
  }

  // pad out name with spaces
  while (i < 8) {
    *dst_ptr = ' ';
    dst_ptr++;
    i++;
  }

  // increment past period
  if (*src_ptr == '.')
    src_ptr++;

  // same for extension
  while (i < 11 && (*src_ptr)) {
    char c = *src_ptr;
    src_ptr++;
    if (('`' < c) && (c < '{')) {  // lower case
      c -= 0x20;
    }
    *dst_ptr = c;
    dst_ptr++;
    i++;
  }

  while (i < 11) {
    *dst_ptr = ' ';
    dst_ptr++;
    i++;
  }
  *dst_ptr = 0;
}

void assert_file_exists(const char* path, const char* error_message) {
  if (!fs::exists(path)) {
    ASSERT_MSG(false, fmt::format("File {} was not found: {}", path, error_message));
  }
}

/*!
 * Check if the given DGO header (or entire file) is compressed.
 */
bool dgo_header_is_compressed(const std::vector<u8>& data) {
  const char compressed_header[] = "oZlB";
  bool is_compressed = true;
  for (int i = 0; i < 4; i++) {
    if (compressed_header[i] != data.at(i)) {
      is_compressed = false;
    }
  }
  return is_compressed;
}

/*!
 * Decompress a DGO. Resulting data will start at the DGO header.
 */
std::vector<u8> decompress_dgo(const std::vector<u8>& data_in) {
  constexpr int MAX_CHUNK_SIZE = 0x8000;
  BinaryReader compressed_reader(data_in);
  // seek past oZlB
  compressed_reader.ffwd(4);
  std::size_t decompressed_size = compressed_reader.read<uint32_t>();
  std::vector<uint8_t> decompressed_data;
  decompressed_data.resize(decompressed_size);
  size_t output_offset = 0;
  while (true) {
    // seek past alignment bytes and read the next chunk size
    uint32_t chunk_size = 0;
    while (!chunk_size) {
      chunk_size = compressed_reader.read<uint32_t>();
    }

    if (chunk_size < MAX_CHUNK_SIZE) {
      std::size_t bytes_written = 0;
      lzokay::EResult ok = lzokay::decompress(
          compressed_reader.here(), chunk_size, decompressed_data.data() + output_offset,
          decompressed_data.size() - output_offset, bytes_written);
      ASSERT(ok == lzokay::EResult::Success);
      compressed_reader.ffwd(chunk_size);
      output_offset += bytes_written;
    } else {
      // nope - sometimes chunk_size is bigger than MAX, but we should still use max.
      //        ASSERT(chunk_size == MAX_CHUNK_SIZE);
      memcpy(decompressed_data.data() + output_offset, compressed_reader.here(), MAX_CHUNK_SIZE);
      compressed_reader.ffwd(MAX_CHUNK_SIZE);
      output_offset += MAX_CHUNK_SIZE;
    }

    if (output_offset >= decompressed_size)
      break;
    while (compressed_reader.get_seek() % 4) {
      compressed_reader.ffwd(1);
    }
  }

  return decompressed_data;
}

FILE* open_file(const fs::path& path, const std::string& mode) {
#ifdef _WIN32
  return _wfopen(path.wstring().c_str(), std::wstring(mode.begin(), mode.end()).c_str());
#else
  return fopen(path.string().c_str(), mode.c_str());
#endif
}

std::vector<fs::path> find_files_in_dir(const fs::path& dir, const std::regex& pattern) {
  std::vector<fs::path> files = {};
  for (auto& p : fs::directory_iterator(dir)) {
    if (p.is_regular_file()) {
      if (std::regex_match(p.path().filename().string(), pattern)) {
        files.push_back(p.path());
      }
    }
  }
  return files;
}

std::vector<fs::path> find_files_recursively(const fs::path& base_dir, const std::regex& pattern) {
  std::vector<fs::path> files = {};
  if (!fs::exists(base_dir)) {
    return files;
  }
  for (auto& p : fs::recursive_directory_iterator(base_dir)) {
    if (p.is_regular_file()) {
      if (std::regex_match(p.path().filename().string(), pattern)) {
        files.push_back(p.path());
      }
    }
  }
  return files;
}

std::vector<fs::path> find_directories_in_dir(const fs::path& base_dir) {
  std::vector<fs::path> dirs = {};
  for (auto& p : fs::recursive_directory_iterator(base_dir)) {
    if (p.is_directory()) {
      dirs.push_back(p.path());
    }
  }
  return dirs;
}

std::vector<fs::path> sort_filepaths(const std::vector<fs::path>& paths, const bool aescending) {
  std::vector<std::string> paths_as_strings = {};
  for (const auto& path : paths) {
    paths_as_strings.push_back(path.string());
  }
  std::sort(paths_as_strings.begin(), paths_as_strings.end(),
            [aescending](const std::string& a, const std::string& b) {
              if (aescending) {
                return a < b;
              } else {
                return a > b;
              }
            });
  std::vector<fs::path> sorted_paths = {};
  for (const auto& path : paths_as_strings) {
    sorted_paths.push_back(fs::path(path));
  }
  return sorted_paths;
}

void copy_file(const fs::path& src, const fs::path& dst) {
  // Check that the src path exists
  if (!fs::exists(src)) {
    throw std::runtime_error(fmt::format("Cannot copy '{}', path does not exist", src.string()));
  }
  // Ensure the directory can be copied into
  if (!fs::exists(dst.parent_path()) && !create_dir_if_needed_for_file(dst)) {
    throw std::runtime_error(fmt::format(
        "Cannot copy '{}', couldn't make directory to copy into '{}'", src.string(), dst.string()));
  }
  fs::copy_file(src, dst, fs::copy_options::overwrite_existing);
}

std::string make_screenshot_filepath(const GameVersion game_version, const std::string& name) {
  std::string file_name;
  if (name.empty()) {
    file_name = fmt::format("{}.png", str_util::current_local_timestamp_no_colons());
  } else {
    file_name = fmt::format("{}.png", name);
  }
  const auto file_path = get_user_screenshots_dir(game_version) / file_name;
  file_util::create_dir_if_needed_for_file(file_path);
  return file_path.string();
}

std::string get_majority_file_line_endings(const std::string& file_contents) {
  size_t lf_count = 0;
  size_t crlf_count = 0;

  for (size_t i = 0; i < file_contents.size(); ++i) {
    if (file_contents[i] == '\n') {
      if (i > 0 && file_contents[i - 1] == '\r') {
        crlf_count++;
      } else {
        lf_count++;
      }
    }
  }

  if (crlf_count > lf_count) {
    return "\r\n";
  }
  return "\n";
}

std::pair<int, std::string> get_majority_file_line_endings_and_count(
    const std::string& file_contents) {
  size_t lf_count = 0;
  size_t crlf_count = 0;

  for (size_t i = 0; i < file_contents.size(); ++i) {
    if (file_contents[i] == '\n') {
      if (i > 0 && file_contents[i - 1] == '\r') {
        crlf_count++;
      } else {
        lf_count++;
      }
    }
  }

  if (crlf_count > lf_count) {
    return {lf_count + crlf_count, "\r\n"};
  }
  return {lf_count + crlf_count, "\n"};
}

bool is_dir_in_dir(const fs::path& parent, const fs::path& child) {
  // Check if the parent path is a prefix of the child path
  return child.has_parent_path() && child.parent_path().lexically_relative(parent) == fs::path(".");
}

}  // namespace file_util
