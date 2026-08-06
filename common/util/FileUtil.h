#pragma once

/*!
 * @file FileUtil.h
 * Utility functions for reading and writing files.
 */

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#endif

#include "third-party/filesystem.hpp"

#ifdef _WIN32
#undef FALSE
#endif

#include <optional>
#include <regex>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/versions/versions.h"

namespace fs = ghc::filesystem;

namespace file_util {
fs::path get_user_home_dir();
fs::path get_user_config_dir();
fs::path get_user_settings_dir(GameVersion game_version);
fs::path get_user_memcard_dir(GameVersion game_version);
fs::path get_user_screenshots_dir(GameVersion game_version);
fs::path get_user_misc_dir(GameVersion game_version);
fs::path get_user_features_dir(GameVersion game_version);
fs::path get_jak_project_dir();
fs::path get_iso_dir_for_game(GameVersion game_version);
void set_iso_data_dir(const fs::path& directory);

// External per-game "game root" support. When set, arch-independent assets and
// saves resolve under this root instead of the legacy jak-project/out + config
// directories. When unset, behavior is EXACTLY the legacy behavior.
void set_external_game_root(const fs::path& root);
std::optional<fs::path> get_external_game_root();
void set_iso_overlay_dir(const fs::path& p);
std::optional<fs::path> get_iso_overlay_dir();
// Custom-assets root: port-custom assets (recharged PNGs, .grassbake, enhanced
// fr3) shipped inside the package (APK-internal / desktop archive), distinct
// from the external/vanilla data tree. When set, takes precedence.
void set_custom_assets_root(const fs::path& p);
std::optional<fs::path> get_custom_assets_root();
std::optional<fs::path> get_custom_fr3_dir();
// ---------------------------------------------------------------------------------------------
// Round 30 (delivery): ONE resolver for every per-file asset that can be shipped BOTH inside the
// package (the APK custom pack, extracted to <custom root>/fr3) and in the external vanilla tree
// (<external root>/assets/fr3). The PACKAGE copy wins, file by file — the same precedence the owner
// already validated for textures (user custom_assets > bundled recharged > stock).
// Before this there were three hand-rolled existence probes (fr3 sidecar, grassbake, enhanced fr3)
// and not one of them logged its decision, so which copy a build actually opened was unprovable.
// The base pack is 1.44 GB and cannot fit in an APK, so the package copy is the ONLY route a data
// fix has to a device with no adb: it has to win, and the win has to be checkable.
struct Fr3AssetRoute {
  fs::path path;       // the file the caller must open
  std::string source;  // "custom-pack" | "base-pack" | "missing"
  bool custom_exists = false;
  bool base_exists = false;
  u64 custom_bytes = 0;
  u64 base_bytes = 0;
  // File-clock seconds. Only ever compared against each other, never rendered as wall-clock, so no
  // clock cast is needed (and none is portable before C++20).
  s64 custom_mtime = 0;
  s64 base_mtime = 0;
  // Both copies exist AND the external one is strictly newer. Precedence still stands (the package
  // copy is served) but this means the packaging freshness guard was bypassed, so it is logged loudly
  // instead of being silently absorbed.
  bool bundle_stale = false;
};

Fr3AssetRoute resolve_fr3_asset(const fs::path& base_dir, const std::string& file_name);
Fr3AssetRoute resolve_fr3_asset(GameVersion game_version, const std::string& file_name);

// Appends a line to <project dir>/asset_route.txt (files/asset_route.txt on Android, where logcat is
// obscured on the owner's phone) and mirrors it to the log. resolve_fr3_asset() journals every
// decision through this; callers use it directly to add a fingerprint of what they opened.
void asset_route_journal(const std::string& line);
fs::path get_iso_out_dir(GameVersion game_version);
fs::path get_fr3_dir(GameVersion game_version);
fs::path get_recharged_assets_dir();
// Grecharged-secondary-motion: the EXTERNAL pack's recharged_assets dir, if an external game root
// is configured. Used for files that must be user-overridable without repacking the APK.
std::optional<fs::path> get_external_recharged_assets_dir();
fs::path get_custom_assets_replacements_dir(GameVersion game_version);
fs::path get_bundled_recharged_textures_dir(GameVersion game_version);
// Grecharged-mesh-browser: the per-level mesh catalogue distilled from tess_sign, shipped inside
// the game package next to the bundled recharged textures (same custom-pack root on Android, same
// checked-out tree on desktop). Read on demand by the debug mesh browser.
fs::path get_bundled_mesh_index_dir(GameVersion game_version);

bool create_dir_if_needed(const fs::path& path);
bool create_dir_if_needed_for_file(const std::string& path);
bool create_dir_if_needed_for_file(const fs::path& path);
std::string get_current_executable_path();
std::optional<std::string> try_get_project_path_from_path(const std::string& path);
bool setup_project_path(std::optional<fs::path> project_path_override, bool skip_logs = false);
void override_user_config_dir(fs::path user_config_dir_override,
                              bool use_overridden_config_dir_for_saves);
std::string get_file_path(const std::vector<std::string>& path);
void write_binary_file(const std::string& name, const void* data, size_t size);
void write_binary_file(const fs::path& name, const void* data, size_t size);
void write_rgba_png(const fs::path& name, void* data, int w, int h);
void write_text_file(const std::string& file_name, const std::string& text);
void write_text_file(const fs::path& file_name, const std::string& text);
std::vector<uint8_t> read_binary_file(const std::string& filename);
std::vector<uint8_t> read_binary_file(const fs::path& filename);
std::string read_text_file(const std::string& path);
std::string read_text_file(const fs::path& path);
bool is_printable_char(char c);
std::string combine_path(const std::string& parent, const std::string& child);
bool file_exists(const std::string& path);
std::string base_name(const std::string& filename);
std::string base_name_no_ext(const std::string& filename);
std::string split_path_at(const fs::path& path, const std::vector<std::string>& folders);
std::string convert_to_unix_path_separators(const std::string& path);
void MakeISOName(char* dst, const char* src);
void ISONameFromAnimationName(char* dst, const char* src);
void assert_file_exists(const char* path, const char* error_message);
bool dgo_header_is_compressed(const std::vector<u8>& data);
std::vector<u8> decompress_dgo(const std::vector<u8>& data_in);
FILE* open_file(const fs::path& path, const std::string& mode);
std::vector<fs::path> find_files_in_dir(const fs::path& dir, const std::regex& pattern);
std::vector<fs::path> find_files_recursively(const fs::path& base_dir, const std::regex& pattern);
std::vector<fs::path> find_directories_in_dir(const fs::path& base_dir);
std::vector<fs::path> sort_filepaths(const std::vector<fs::path>& paths, const bool aescending);
/// Will overwrite the destination if it exists
void copy_file(const fs::path& src, const fs::path& dst);
std::string make_screenshot_filepath(const GameVersion game_version, const std::string& name = "");
std::string get_majority_file_line_endings(const std::string& file_contents);
std::pair<int, std::string> get_majority_file_line_endings_and_count(
    const std::string& file_contents);
bool is_dir_in_dir(const fs::path& parent, const fs::path& child);
}  // namespace file_util
