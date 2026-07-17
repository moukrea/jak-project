/*!
 * @file main.cpp
 * Main for the game. Launches the runtime.
 */

#define STBI_WINDOWS_UTF8

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>

#ifdef _WIN32
#include <io.h>
#include <objbase.h>
#include <shobjidl.h>
#else
#include <unistd.h>
#endif

#include "runtime.h"

#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/dialogs.h"
#include "common/util/os.h"
#include "common/util/term_util.h"
#include "common/util/unicode_util.h"
#include "common/versions/versions.h"

#include "game/common/game_common_types.h"
#include "game/kernel/common/kmemcard.h"
#include "game/system/pad_replay.h"
#include "graphics/gfx_test.h"

#include "third-party/CLI11.hpp"

#ifdef _WIN32
extern "C" {
__declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
#endif

/*!
 * Set up logging system to log to file.
 * @param verbose : should we print debug-level messages to stdout?
 */
void setup_logging(const std::string& game_name, bool verbose, bool disable_ansi_colors) {
  lg::set_file(game_name);
  if (verbose) {
    lg::set_file_level(lg::level::debug);
    lg::set_stdout_level(lg::level::debug);
    lg::set_flush_level(lg::level::debug);
  } else {
    lg::set_file_level(lg::level::debug);
    lg::set_stdout_level(lg::level::info);
    lg::set_flush_level(lg::level::warn);
  }
  if (disable_ansi_colors) {
    lg::disable_ansi_colors();
  }
  lg::initialize();
}

std::string game_arg_documentation() {
  // clang-format off
  std::string output = fmt::format(fmt::emphasis::bold, "Game Args (passed through to the game runtime after '--')\n");
  output += fmt::format(fmt::fg(fmt::color::gray), "Order matters, some args will negate others (see kmachine.cpp for details)\n");
  output += fmt::format(fmt::fg(fmt::color::gray), "Args with `*` are not well supported\n\n");
  // Common args
  output += fmt::format(fmt::emphasis::bold, "Common:\n");
  output += "  -cd          * Use the DVD drive for everything. This is how the game runs in retail\n";
  output += "  -cddata      * Use the DVD drive for everything but IOP modules\n";
  output += "  -deviso      * One of two modes for testing without the need for DVDs\n";
  output += "  -fakeiso       The other of two modes for testing without the need for DVDs\n";
  output += "  -boot          Used to set GOAL up for running the game in retail mode\n";
  output += "  -debug         Used to set GOAL up for debugging/development\n";
  output += "  -debug-mem     Used to set up GOAL in debug mode, but not to load debug-segments\n";
  output += "  -nokernel      An added mode to allow booting without a KERNEL.CGO for testing\n";
  output += "  -nosound       An added mode to allow booting without sound for testing\n";
  output += "  -level [name]  Used to inform the game to boot a specific level the default level is `#f`\n";
  // Jak 1 Related
  output += fmt::format(fmt::emphasis::bold | fmt::fg(fmt::color::orange), "Jak 1:\n");
  output += "  -demo          Boot the game in demo mode\n";
  // Jak 2 only
  output += fmt::format(fmt::emphasis::bold | fmt::fg(fmt::color::purple), "Jak 2:\n");
  output += "  -demo          Boot the game in demo mode\n";
  output += "  -kiosk         Boot the game in kiosk demo mode\n";
  output += "  -preview       Boot the game in preview demo mode\n";
  output += "  -debug-boot    Used to boot the game in retail mode, but with debug segments\n";
  output += "  -user [name]   Specify the debugging username, the default is `unknown`\n";
  output += "  -art [name]    Specify the art-group name to set `DebugBootArtGroup`, there is no default\n";
  // clang-format on
  return output;
}

// Returns a user-picked directory via the platform's native dialog, or nullopt.
static std::optional<std::string> native_pick_directory(const std::string& title) {
#if defined(_WIN32)
  std::optional<std::string> result;
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  bool did_init = SUCCEEDED(hr);
  // RPC_E_CHANGED_MODE means COM is already initialized in another mode; we can
  // still use the dialog but must not call CoUninitialize for our (failed) init.
  if (SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE) {
    IFileOpenDialog* dialog = nullptr;
    hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&dialog));
    if (SUCCEEDED(hr) && dialog) {
      DWORD opts = 0;
      if (SUCCEEDED(dialog->GetOptions(&opts))) {
        dialog->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
      } else {
        dialog->SetOptions(FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
      }
      std::wstring wtitle(title.begin(), title.end());
      dialog->SetTitle(wtitle.c_str());
      if (SUCCEEDED(dialog->Show(nullptr))) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item)) && item) {
          PWSTR path = nullptr;
          if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
            int len = WideCharToMultiByte(CP_UTF8, 0, path, -1, nullptr, 0, nullptr, nullptr);
            if (len > 0) {
              std::string utf8(len - 1, '\0');
              WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8.data(), len, nullptr, nullptr);
              if (!utf8.empty()) {
                result = utf8;
              }
            }
            CoTaskMemFree(path);
          }
          item->Release();
        }
      }
      dialog->Release();
    }
    if (did_init) {
      CoUninitialize();
    }
  }
  return result;
#elif defined(__APPLE__)
  std::string cmd =
      "osascript -e 'POSIX path of (choose folder with prompt \"" + title + "\")' 2>/dev/null";
  FILE* p = popen(cmd.c_str(), "r");
  if (!p) {
    return std::nullopt;
  }
  char buf[4096] = {0};
  std::string line;
  if (fgets(buf, sizeof(buf), p)) {
    line = buf;
  }
  int status = pclose(p);
  while (!line.empty() && (line.back() == '\n' || line.back() == '\r' || line.back() == ' ' ||
                           line.back() == '\t')) {
    line.pop_back();
  }
  if (status == 0 && !line.empty()) {
    return line;
  }
  return std::nullopt;
#else
  // Linux: only attempt a GUI dialog when a display is available.
  if (std::getenv("DISPLAY") == nullptr && std::getenv("WAYLAND_DISPLAY") == nullptr) {
    return std::nullopt;
  }
  auto run = [](const std::string& cmd) -> std::optional<std::string> {
    FILE* p = popen(cmd.c_str(), "r");
    if (!p) {
      return std::nullopt;
    }
    char buf[4096] = {0};
    std::string line;
    if (fgets(buf, sizeof(buf), p)) {
      line = buf;
    }
    int status = pclose(p);
    while (!line.empty() && (line.back() == '\n' || line.back() == '\r' || line.back() == ' ' ||
                             line.back() == '\t')) {
      line.pop_back();
    }
    if (status == 0 && !line.empty()) {
      return line;
    }
    return std::nullopt;
  };
  // Use a fixed, single-quote-free title to avoid shell escaping issues.
  (void)title;
  const char* safe_title = "Select the game folder";
  auto z = run(std::string("zenity --file-selection --directory --title='") + safe_title +
               "' 2>/dev/null");
  if (z) {
    return z;
  }
  auto k = run(std::string("kdialog --getexistingdirectory ~ --title '") + safe_title +
               "' 2>/dev/null");
  if (k) {
    return k;
  }
  return std::nullopt;
#endif
}

/*!
 * External-asset-root resolution (desktop). Runs when --game-root was NOT
 * given. Tries, in order:
 *   a. a saved pointer file (config/asset-root.txt) pointing at a chosen dir
 *      that contains jak<n>/assets/iso;
 *   b. the legacy dev iso dir (out/<name>/iso) with at least one file — leave
 *      behavior unchanged;
 *   c. a native directory picker (3 attempts), then a stdin prompt (3 attempts)
 *      as last fallback, persisting the chosen dir. On first boot, if the
 *      chosen tree doesn't yet hold assets, create the skeleton and instruct
 *      the user to extract the assets archive.
 * Returns false only on an unrecoverable non-TTY / give-up path (caller exits).
 */
static bool resolve_game_root(GameVersion game_version) {
  const std::string name = game_version_names[game_version];
  // jak<n> subdir (jak1 / jak2 / jak3).
  std::string game_subdir = "jak1";
  if (game_version == GameVersion::Jak2) {
    game_subdir = "jak2";
  } else if (game_version == GameVersion::Jak3) {
    game_subdir = "jak3";
  }

  const fs::path legacy_iso_dir = file_util::get_jak_project_dir() / "out" / name / "iso";

  // The legacy dir only satisfies the "no external root needed" case when it
  // holds actual game DATA. A release binary pack ships ONLY the compiled
  // *.CGO/*.DGO there (data comes from the external assets archive), so a
  // CGO/DGO-only dir must fall through to the pointer-file/prompt flow — where
  // try_accept then binds this same dir as the fake_iso overlay.
  auto legacy_dir_has_data_files = [&]() -> bool {
    if (!fs::exists(legacy_iso_dir)) {
      return false;
    }
    for (const auto& f : fs::directory_iterator(legacy_iso_dir)) {
      if (!f.is_regular_file() && !f.is_symlink()) {
        continue;
      }
      auto ext = f.path().extension().string();
      if (ext != ".CGO" && ext != ".DGO") {
        return true;
      }
    }
    return false;
  };

  // Accept a chosen base dir: <chosen>/jak<n>/assets/iso must exist.
  auto try_accept = [&](const fs::path& chosen) -> bool {
    const fs::path root = chosen / game_subdir;
    if (fs::exists(root / "assets" / "iso")) {
      file_util::set_external_game_root(root);
      // Bind the legacy compiled-iso dir as the overlay (binary pack CGOs) when
      // the user didn't provide one explicitly.
      if (!file_util::get_iso_overlay_dir() && fs::exists(legacy_iso_dir)) {
        file_util::set_iso_overlay_dir(legacy_iso_dir);
      }
      return true;
    }
    return false;
  };

  const fs::path pointer_file = file_util::get_user_config_dir() / "asset-root.txt";

  // a. pointer file
  if (fs::exists(pointer_file)) {
    try {
      std::string chosen = file_util::read_text_file(pointer_file);
      // single line
      while (!chosen.empty() && (chosen.back() == '\n' || chosen.back() == '\r' ||
                                 chosen.back() == ' ' || chosen.back() == '\t')) {
        chosen.pop_back();
      }
      if (!chosen.empty() && try_accept(fs::path(chosen))) {
        lg::info("Using external game root from {}: {}", pointer_file.string(), chosen);
        return true;
      }
    } catch (const std::exception& e) {
      lg::warn("Failed to read asset-root pointer file {}: {}", pointer_file.string(), e.what());
    }
  }

  // b. legacy dev flow
  if (legacy_dir_has_data_files()) {
    return true;
  }

  // Persist the chosen base dir to the pointer file.
  auto persist_pointer = [&](const std::string& chosen) {
    try {
      file_util::create_dir_if_needed(pointer_file.parent_path());
      file_util::write_text_file(pointer_file, chosen);
    } catch (const std::exception& e) {
      lg::warn("Failed to persist asset-root pointer file: {}", e.what());
    }
  };

  // First-boot skeleton: <chosen>/<game_subdir>/{assets, custom_assets, saves}.
  // Persist the pointer so the next launch reuses the same tree, but return
  // false because the game cannot run until the user extracts the assets.
  auto create_skeleton_and_bail = [&](const std::string& chosen) -> bool {
    const fs::path base(chosen);
    if (!fs::exists(base) || !fs::is_directory(base)) {
      return false;
    }
    const fs::path root = base / game_subdir;
    try {
      fs::create_directories(root / "assets");
      fs::create_directories(root / "custom_assets");
      fs::create_directories(root / "saves");
    } catch (const std::exception& e) {
      lg::error("Failed to create game-root skeleton under '{}': {}", root.string(), e.what());
      return false;
    }
    persist_pointer(chosen);
    lg::error(
        "OpenGOAL created a game folder at '{}' but no assets are present yet.\n"
        "Extract '{}_assets.zip' into '{}' (so that '{}' exists) and relaunch.",
        root.string(), name, root.string(), (root / "assets" / "iso").string());
    return false;
  };

  // c. native directory picker (preferred), then stdin (fallback).
  const std::string picker_title =
      "Select the folder that contains (or should contain) " + game_subdir + "/assets";
  for (int attempt = 0; attempt < 3; attempt++) {
    auto picked = native_pick_directory(picker_title);
    if (!picked) {
      break;
    }
    std::string chosen = *picked;
    while (!chosen.empty() && (chosen.back() == '\n' || chosen.back() == '\r' ||
                              chosen.back() == ' ' || chosen.back() == '\t')) {
      chosen.pop_back();
    }
    if (chosen.empty()) {
      continue;
    }
    if (try_accept(fs::path(chosen))) {
      persist_pointer(chosen);
      lg::info("Using external game root: {}/{}", chosen, game_subdir);
      return true;
    }
    // Tree doesn't hold assets yet -> first-boot skeleton create + bail.
    return create_skeleton_and_bail(chosen);
  }

#ifdef _WIN32
  const bool stdin_is_tty = _isatty(_fileno(stdin)) != 0;
#else
  const bool stdin_is_tty = isatty(fileno(stdin)) != 0;
#endif
  if (!stdin_is_tty) {
    lg::error(
        "OpenGOAL could not find game assets. Re-run with --game-root <path> pointing at the "
        "per-game root directory (the folder that contains {}/assets).",
        game_subdir);
    return false;
  }

  for (int attempt = 0; attempt < 3; attempt++) {
    lg::print(
        "\nOpenGOAL could not find game assets.\n"
        "Enter the folder that contains (or should contain) {}/assets\n"
        "(absolute path expected): ",
        game_subdir);
    std::string input;
    if (!std::getline(std::cin, input)) {
      break;
    }
    while (!input.empty() &&
           (input.back() == '\n' || input.back() == '\r' || input.back() == ' ' ||
            input.back() == '\t')) {
      input.pop_back();
    }
    if (input.empty()) {
      continue;
    }
    if (try_accept(fs::path(input))) {
      persist_pointer(input);
      lg::info("Using external game root: {}/{}", input, game_subdir);
      return true;
    }
    // Tree doesn't hold assets yet -> first-boot skeleton create + bail.
    return create_skeleton_and_bail(input);
  }
  lg::error("No valid game root provided.");
  return false;
}

/*!
 * Entry point for the game on desktop. On Android the GOAL runtime is
 * driven through gk_sdl_main → goal_main (see android/android_goal_main.cpp);
 * main.cpp's CLI / cpu_info / discord / gfx dependency chain is desktop-only,
 * so the body below is gated behind #ifndef __ANDROID__. The Android port
 * provides its own implementation of `goal_main` to satisfy this declaration.
 */
int goal_main(int argc, char** argv);

#ifndef __ANDROID__
int goal_main(int argc, char** argv) {
  ArgumentGuard u8_guard(argc, argv);

  // Phase Ginput-replay (autoport): self-test entry. `--pad-replay-selftest
  // <out>` runs the record->replay byte-identity proof through the REAL
  // pad_replay tap and exits, before any runtime/gfx init (no game boot needed).
  // This is what the validator runs to prove all-input capture + determinism.
  for (int i = 1; i < argc; ++i) {
    if (argv[i] && std::string(argv[i]) == "--pad-replay-selftest") {
      std::string out = (i + 1 < argc && argv[i + 1]) ? std::string(argv[i + 1])
                                                       : std::string("selftest.inputs");
      return pad_replay::run_selftest(out, 120);
    }
  }
  // Arm live record/replay from the environment (OG_PAD_REPLAY_RECORD /
  // OG_PAD_REPLAY_REPLAY). No-op unless set — used by the crash phases to record
  // a real playthrough and replay it deterministically.
  pad_replay::init_from_env();

  // Phase E3 (autoport): scan argv for the save-portability flags BEFORE
  // CLI11 parsing. CLI11 reserves single-dash for short options, so
  // `-save-then-exit` and `-load-save` (single-dash long names matching
  // the existing kmachine-arg convention used by `-fakeiso`, `-boot`,
  // `-debug-mem`) can't be registered as CLI11 options directly. They
  // would otherwise land in `app.remaining()` and their associated path
  // would leak into `game_args` as an unbound positional. Hand-scanning
  // here keeps the runtime layer unaware of the flag and lets us act on
  // it before any exec_runtime side-effects.
  std::string save_then_exit_path;
  std::string load_save_path;
  for (int i = 1; i + 1 < argc; ++i) {
    if (!argv[i]) {
      continue;
    }
    const std::string arg = argv[i];
    if (arg == "-save-then-exit" && argv[i + 1]) {
      save_then_exit_path = argv[i + 1];
    } else if (arg == "-load-save" && argv[i + 1]) {
      load_save_path = argv[i + 1];
    }
  }

  // CLI flags
  bool show_version = false;
  std::string game_name = "jak1";
  bool verbose_logging = false;
  bool disable_avx2 = false;
  bool disable_display = false;
  bool enable_profiling = false;
  bool enable_portable = false;
  bool disable_save_location_override = false;
  std::string profile_until_event = "";
  std::string gpu_test = "";
  std::string gpu_test_out_path = "";
  int port_number = -1;
  // Phase 26 (autoport): wall-clock cap (in GOAL kernel frames) for stress
  // / smoke runs under qemu. A value of -1 disables the cap (default).
  // The desktop runtime does not enforce it directly here — it's exposed
  // for cross-build harnesses (tools/arm64-stress) that pass the same
  // argv shape and consume the value themselves.
  int max_frames = -1;
  fs::path project_path_override;
  fs::path user_config_dir_override;
  fs::path game_root_override;
  fs::path iso_overlay_override;
  fs::path custom_assets_override;
  std::vector<std::string> game_args;
  CLI::App app{"OpenGOAL Game Runtime"};
  app.add_flag("--version", show_version, "Display the built revision");
  app.add_option("-g,--game", game_name, "The game name: 'jak1' or 'jak2'");
  app.add_flag("-v,--verbose", verbose_logging, "Enable verbose logging on stdout");
  app.add_flag(
      "--port", port_number,
      "Specify port number for listener connection (default is 8112 for Jak 1 and 8113 for Jak 2)");
  app.add_flag("--no-avx2", disable_avx2, "Disable AVX2 for testing");
  app.add_flag("--no-display", disable_display, "Disable video display");
  app.add_flag("--profile", enable_profiling, "Enables profiling immediately from startup");
  app.add_flag("--portable", enable_portable,
               "Save settings and saves relative to the game's executable, takes precedence over "
               "--config-path");
  app.add_flag("--disable_save_location_override", disable_save_location_override,
               "If --config-path is provided along with this flag, saves will still be loaded and "
               "stored to the default location");
  app.add_option("--profile-until-event", profile_until_event,
                 "Stops recording profile events once an event with this name is seen");
  app.add_option("--gpu-test", gpu_test,
                 "Tests for minimum graphics requirements.  Valid Options are: [opengl]");
  app.add_option("--gpu-test-out-path", gpu_test_out_path,
                 "Where to store the gpu test result file");
  app.add_option("--max-frames", max_frames,
                 "Cap the run at N GOAL kernel frames (-1 = unbounded). "
                 "Used by qemu cross-build stress harnesses.");
  app.add_option("--proj-path", project_path_override,
                 "Specify the location of the 'data/' folder");
  app.add_option("--config-path", user_config_dir_override,
                 "Override the location where all user configuration and saves are saved");
  app.add_option("--game-root", game_root_override,
                 "The per-game root directory holding arch-independent assets and saves "
                 "(e.g. /sdcard/OpenGOAL/jak1)");
  app.add_option("--iso-overlay", iso_overlay_override,
                 "Directory holding the per-arch compiled *.CGO/*.DGO iso overlay");
  app.add_option("--custom-assets", custom_assets_override,
                 "Directory holding port-custom assets (recharged_assets/, fr3/) shipped in the "
                 "package, taking precedence over the vanilla data tree");
  app.footer(game_arg_documentation());
  app.add_option("Game Args", game_args,
                 "Remaining arguments (after '--') that are passed-through to the game itself");
  define_common_cli_arguments(app);
  app.allow_extras();
  CLI11_PARSE(app, argc, argv);

  // Log the version the game is compiled against so we don't have to guess
  lg::info("Compiled Version: {}", build_revision());

  // Override the user's config dir, potentially (either because it was explicitly provided
  // or because it's portable mode)
  if (enable_portable) {
    lg::info("Portable mod enabled");
    user_config_dir_override = fs::path(file_util::get_current_executable_path()).parent_path();
  }
  if (!user_config_dir_override.empty()) {
    lg::info("Overriding config directory with: {}", user_config_dir_override.string());
    file_util::override_user_config_dir(user_config_dir_override, !disable_save_location_override);
  }

  // External-asset-root: apply explicit --game-root / --iso-overlay flags. The
  // pointer-file / prompt resolution below only runs when --game-root is absent.
  if (!game_root_override.empty()) {
    lg::info("Using external game root: {}", game_root_override.string());
    file_util::set_external_game_root(game_root_override);
  }
  if (!iso_overlay_override.empty()) {
    lg::info("Using iso overlay dir: {}", iso_overlay_override.string());
    file_util::set_iso_overlay_dir(iso_overlay_override);
  }
  if (!custom_assets_override.empty()) {
    lg::info("Using custom assets root: {}", custom_assets_override.string());
    file_util::set_custom_assets_root(custom_assets_override);
  }

  if (show_version) {
    lg::print("{}", build_revision());
    return 0;
  }

  // Phase E3 (autoport): write the deterministic test save and exit before
  // any of the gfx/IOP/EE machinery spins up. write_test_save_to_path keys
  // on g_game_version, which exec_runtime would otherwise be responsible
  // for setting; we set it here from --game so the BANK_SIZE pulled from
  // the PerGameVersion table matches what the rest of kmemcard would see.
  if (!save_then_exit_path.empty()) {
    g_game_version = game_name_to_version(game_name);
    kmemcard_init_globals();
    if (!write_test_save_to_path(save_then_exit_path)) {
      lg::error("write_test_save_to_path failed for {}", save_then_exit_path);
      return 1;
    }
    return 0;
  }

  // Phase E3 (autoport): validate the supplied save bank format so the
  // round-trip step fails fast on a corrupt file rather than mid-boot. If
  // it's well-formed we leave it where it sits and continue the normal
  // boot — the runtime doesn't auto-load a save into running state; the
  // file is staged for the in-game load menu to pick up.
  if (!load_save_path.empty()) {
    g_game_version = game_name_to_version(game_name);
    kmemcard_init_globals();
    if (!validate_save_file(load_save_path)) {
      lg::error("load_save: {} is not a valid save bank", load_save_path);
      return 1;
    }
  }

  if (!gpu_test.empty() && !gpu_test_out_path.empty()) {
    const auto output = tests::run_gpu_test(gpu_test);
    json data = output;
    try {
      file_util::write_text_file(gpu_test_out_path, data.dump(2));
    } catch (std::exception& e) {
      return 1;
    }
    return 0;
  }

  prof().set_enable(enable_profiling);
  prof().set_waiting_for_event(profile_until_event);

  // Create struct with all non-kmachine handled args to pass to the runtime
  GameLaunchOptions game_options;
  game_options.disable_display = disable_display;
  game_options.game_version = game_name_to_version(game_name);
  game_options.server_port =
      port_number == -1 ? DECI2_PORT - 1 + (int)game_options.game_version : port_number;

  // Figure out if the CPU has AVX2 to enable higher performance AVX2 versions of functions.
  setup_cpu_info();
  // If the CPU doesn't have AVX, GOAL code won't work and we exit.
  if (!get_cpu_info().has_avx) {
// Check if we are on a modern enough version of macOS so that AVX can be
// emulated via rosetta
#ifdef __APPLE__
    auto macos_major_version = get_macos_major_version();
    if (macos_major_version < 15.0) {
      lg::info(
          "Your CPU does not support AVX. But the newer version of Rosetta supports it, update to "
          "atleast Sequoia to run OpenGOAL!");
      dialogs::create_error_message_dialog(
          "Unmet Requirements",
          "Your CPU does not support AVX. But the newer version of Rosetta supports it, update to "
          "atleast Sequoia to run OpenGOAL!");
      return -1;
    }
#else
    lg::info("Your CPU does not support AVX, which is required for OpenGOAL.");
    dialogs::create_error_message_dialog(
        "Unmet Requirements", "Your CPU does not support AVX, which is required for OpenGOAL.");
    return -1;
#endif
  }

  // set up file paths for resources. This is the full repository when developing, and the data
  // directory (a subset of the full repo) in release versions
  if (project_path_override.empty()) {
    lg::info("No project path provided, looking for data/ folder in current directory");
    if (!file_util::setup_project_path({})) {
      return 1;
    }
  } else if (!file_util::setup_project_path(project_path_override)) {
    return 1;
  }

  // External-asset-root: when --game-root was not explicitly provided, resolve
  // a game root from the pointer file / legacy dir / interactive prompt. This
  // must run before the runtime starts. When --game-root WAS given we skip this
  // entirely (explicit wins). No game root set == legacy behavior.
  if (game_root_override.empty() && !file_util::get_external_game_root()) {
    if (!resolve_game_root(game_options.game_version)) {
      return 1;
    }
  }

  if (disable_avx2) {
    // for debugging the non-avx2 code paths, there's a flag to manually disable.
    lg::info("Note: AVX2 code has been manually disabled.");
    get_cpu_info().has_avx2 = false;
  }

#ifndef __AVX2__
  if (get_cpu_info().has_avx2) {
    // printf("Note: your CPU supports AVX2, but this build was not compiled with AVX2 support\n");
    get_cpu_info().has_avx2 = false;
  }
#endif

  if (get_cpu_info().has_avx2) {
    lg::info("AVX2 mode enabled");
  } else {
    lg::info("AVX2 mode disabled");
  }

  try {
    setup_logging(game_name, verbose_logging, _cli_flag_disable_ansi);
  } catch (const std::exception& e) {
    lg::error("Failed to setup logging: {}", e.what());
    return 1;
  }

  bool force_debug_next_time = false;
  // always start with an empty arg, as internally kmachine starts at `1` not `0`
  std::vector<const char*> arg_ptrs = {""};
  for (auto& str : game_args) {
    arg_ptrs.push_back(str.data());
  }

  while (true) {
    if (force_debug_next_time) {
      // I'd like to check and not add duplicates, unfortunately since the game
      // cares about ordering...that's likely error prone if the user passed args in the wrong order
      // ie. -debug -boot (we'd skip adding things, but the order would be wrong).
      game_args.push_back("-boot");
      game_args.push_back("-debug");
      force_debug_next_time = false;
      arg_ptrs = {""};  // see above for rationale
      for (auto& str : game_args) {
        arg_ptrs.push_back(str.data());
      }
    }

    // run the runtime in a loop so we can reset the game and have it restart cleanly
    lg::info("OpenGOAL Runtime {}.{}", versions::GOAL_VERSION_MAJOR, versions::GOAL_VERSION_MINOR);
    try {
      MasterExit = RuntimeExitStatus::RUNNING;
      auto exit_status = exec_runtime(game_options, arg_ptrs.size(), arg_ptrs.data());
      switch (exit_status) {
        case RuntimeExitStatus::EXIT:
          return 0;
        case RuntimeExitStatus::RESTART_RUNTIME:
        case RuntimeExitStatus::RUNNING:
          break;
        case RuntimeExitStatus::RESTART_IN_DEBUG:
          force_debug_next_time = true;
          break;
      }
    } catch (std::exception& ex) {
      lg::error("Unexpected exception occurred - {}", ex.what());
      throw ex;
    }
  }
  return 0;
}

int main(int argc, char** argv) {
  return goal_main(argc, argv);
}
#endif  // !__ANDROID__
