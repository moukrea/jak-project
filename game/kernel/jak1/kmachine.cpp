#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#elif defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#include "kmachine.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <limits>
#include <array>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <unordered_set>
#include <vector>

#include "common/log/log.h"
#include "common/symbols.h"
#include "common/util/FileUtil.h"
#include "common/util/string_util.h"

#include "game/external/discord_jak1.h"
#include "game/graphics/display.h"
#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"
// [pom] device diagnostic: pbr_pom_diag_section() renders the per-material parallax block appended
// to pbr_tan_diag.txt below, and [cover] pbr_coverage_section() the per-frame displacement coverage
// tally (which PBR-bound draws actually get displaced). Header is GL-free (PBR material registry
// only), so the kernel can include it without dragging in the GL loader.
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/sceGraphicsInterface.h"
#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/kernel_types.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmachine.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/kernel/common/ksound.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/jak1/kboot.h"
#include "game/kernel/jak1/kdgo.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/kernel/jak1/ksound.h"
#include "game/sce/deci2.h"
#include "game/system/pad_replay.h"
#include "game/sce/libcdvd_ee.h"
#include "game/sce/libdma.h"
#include "game/sce/libgraph.h"
#include "game/sce/sif_ee.h"
#include "game/sce/stubs.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>

#include "common/util/font/font_utils.h"
#if defined(__ANDROID__) || defined(__linux__)
#include <unistd.h>  // fsync (Gcollision-glitchcapture dump durability)
#endif
#if defined(__ANDROID__)
#include <android/log.h>  // [CC] trigger line -> GK_STDOUT logcat (live supervisor monitoring)
#include <sys/system_properties.h>
// Gcrash-swamp-load (debug-only): arm the signal-handler repair bypass, defined
// in android/gk_android_main.cpp. Called from diag_flags_maybe(); OFF by default.
extern "C" void gk_set_diag_norepair(bool on);
#endif

using namespace ee;

#ifdef OG_FEAT_HD_MODELS
// Grecharged-hd-models4: per-actor coverage registry, DEFINED at GLOBAL scope in Merc2.cpp
// (prototypes here rather than including the GL renderer headers in this kernel TU). Declared
// BEFORE namespace jak1 — an in-namespace declaration makes the calls below reference
// jak1::merc2_hd_* and the link fails (attempt-1 failure of this phase).
void merc2_hd_cover(u32 companion_pid, u32 driver_pid);
void merc2_hd_uncover(u32 companion_pid);
#endif

namespace jak1 {

/*!
 * Initialize global variables based on command line parameters. Not called in retail versions,
 * but it is present in the ELF.
 * DONE
 * Modified to use std::string, and removed call to fflush.
 */
void InitParms(int argc, const char* const* argv) {
  // Modified default settings:
  if (argc == 1) {
    DiskBoot = 1;
    isodrv = fakeiso;
    modsrc = 0;
    reboot_iop = 0;
    DebugSegment = 0;
    MasterDebug = 0;
  }

  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    // DVD Settings
    // ----------------------------

    // the "cd" mode uses the DVD drive for everything. This is how the game runs in retail
    if (arg == "-cd") {
      Msg(6, "dkernel: cd mode\n");
      isodrv = iso_cd;  // use the actual DVD drive for data files
      modsrc = 1;       // use the DVD drive data for IOP modules
      reboot_iop = 1;   // Reboot the IOP (load new IOP runtime)
    }

    // the "cddata" uses the DVD drive for everything but IOP modules.
    if (arg == "-cddata") {
      Msg(6, "dkernel: cddata mode\n");
      isodrv = iso_cd;  // tell IOP to use actual DVD drive for data files
      modsrc = 0;       // don't use DVD drive for IOP modules
      reboot_iop = 0;   // no need to reboot the IOP
    }

    // the "deviso" mode is one of two modes for testing without the need for DVDs
    if (arg == "-deviso") {
      Msg(6, "dkernel: deviso mode\n");
      isodrv = deviso;  // IOP deviso mode
      modsrc = 0;       // no IOP module loading (there's no DVD to load from!)
      reboot_iop = 0;
    }

    // the "fakeiso" mode is the other of two modes for testing without the need for DVDs
    if (arg == "-fakeiso") {
      Msg(6, "dkernel: fakeiso mode\n");
      isodrv = fakeiso;  // IOP fakeeiso mode
      modsrc = 0;        // no IOP module loading (there's no DVD to load from!)
      reboot_iop = 0;
    }

    // an added mode to allow booting without a KERNEL.CGO for testing
    if (arg == "-nokernel") {
      Msg(6, "dkernel: no kernel mode\n");
      MasterUseKernel = false;
    }

    // an added mode to allow booting without sound for testing
    if (arg == "-nosound") {
      Msg(6, "dkernel: no sound mode\n");
      masterConfig.disable_sound = true;
    }

    // added in pc port to skip the splash screen
    if (arg == "-nosplash") {
      Msg(6, "dkernel: skipping splash screen\n");
      SplashScreen = false;
    }

    // GOAL Settings
    // ----------------------------

    // the "demo" mode is used to pass the message "demo" to the gkernel in the DebugBootMessage
    // (instead of play)
    if (arg == "-demo") {
      Msg(6, "dkernel: demo mode\n");
      kstrcpy(DebugBootMessage, "demo");
    }

    // the "boot" mode is used to set GOAL up for running the game in retail mode
    if (arg == "-boot") {
      Msg(6, "dkernel: boot mode\n");
      MasterDebug = 0;
      DiskBoot = 1;
      DebugSegment = 0;
    }

    // the "debug" mode is used to set GOAL up for debugging/development
    if (arg == "-debug") {
      Msg(6, "dkernel: debug mode\n");
      MasterDebug = 1;
      DebugSegment = 1;
      // disable splash in debug
      SplashScreen = 0;
    }

    // the "debug-mem" mode is used to set up GOAL in debug mode, but not to load debug-segments
    if (arg == "-debug-mem") {
      Msg(6, "dkernel: debug-mem mode\n");
      MasterDebug = 1;
      DebugSegment = 0;
    }

    // the "-level [level-name]" mode is used to inform the game to boot a specific level
    // the default level is "#f".
    if (arg == "-level") {
      i++;
      std::string levelName = argv[i];
      Msg(6, "dkernel: level %s\n", levelName.c_str());
      kstrcpy(DebugBootLevel, levelName.c_str());
    }
  }
}

/*!
 * Initialize the I/O Processor
 * Removed calls to exit(0) if loading modules fails.
 */
void InitIOP() {
  // before doing anything with the I/O Processor, we need to set up SIF RPC
  sceSifInitRpc(0);

  if ((isodrv == iso_cd) || modsrc || reboot_iop) {
    // we will need the DVD drive to bring up the IOP
    InitCD();
  }

  if (!reboot_iop) {
    // reboot with development IOP kernel
    lg::debug("Rebooting IOP...");
    while (!sceSifRebootIop("host0:/usr/local/sce/iop/modules/ioprp221.img")) {
      lg::debug("Failed, retrying");
    }
    while (!sceSifSyncIop()) {
      lg::debug("Syncing...");
    }
  } else {
    // reboot with IOP kernel off of the disk
    // reboot with development IOP kernel
    lg::debug("Rebooting IOP...");
    while (!sceSifRebootIop("cdrom0:\\DRIVERS\\IOPRP221.IMG;1")) {
      lg::debug("Failed, retrying");
    }
    while (!sceSifSyncIop()) {
      lg::debug("Syncing...");
    }
  }

  // now that the IOP is booted with the correct kernel, we need to connect SIF RPC again
  sceSifInitRpc(0);

  // if we plan to get files off of the DVD drive, we get ready to load files again.
  // resetting the file system may not be needed here, but it does not hurt.
  if ((isodrv == iso_cd) || modsrc) {
    InitCD();
    sceFsReset();
  }

  // we begin putting together a boot command for OVERLORD, the IOP driver, which must know the data
  // source and the name of the boot splash screen of the game.
  char overlord_boot_command[256];
  char* cmd = overlord_boot_command;
  kstrcpy(cmd, init_types[(int)isodrv]);
  cmd = cmd + strlen(cmd) + 1;
  kstrcpy(cmd, "SCREEN1.USA");
  cmd = cmd + strlen(cmd) + 1;
  if (masterConfig.disable_sound) {
    kstrcpy(cmd, "-nosound");
    cmd = cmd + strlen(cmd) + 1;
  }

  int total_len = cmd - overlord_boot_command;

  if (modsrc == fakeiso) {
    // load from network

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/sio2man.irx", 0, nullptr) < 0) {
      MsgErr("loading sio2man.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/padman.irx", 0, nullptr) < 0) {
      MsgErr("loading padman.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/libsd.irx", 0, nullptr) < 0) {
      MsgErr("loading libsd.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/mcman.irx", 0, nullptr) < 0) {
      MsgErr("loading mcman.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/local/sce/iop/modules/mcserv.irx", 0, nullptr) < 0) {
      MsgErr("loading mcserv.irx failed\n");
    }

    if (sceSifLoadModule("host0:/usr/home/src/989snd10/iop/989snd.irx", 0, nullptr) < 0) {
      MsgErr("loading 989snd.irx failed\n");
    }

    sceSifLoadModule("host0:/usr/home/src/989snd10/iop/989ERR.IRX", 0, nullptr);

    lg::debug("Initializing CD library...");
    auto rv = sceSifLoadModule("host0:binee/overlord.irx", total_len, overlord_boot_command);
    if (rv < 0) {
      MsgErr("loading overlord.irx failed\n");
    }
  } else {
    // load from DVD drive
    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\SIO2MAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading sio2man.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\PADMAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading padman.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\LIBSD.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading libsd.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\MCMAN.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading mcman.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\MCSERV.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading mcserv.irx failed\n");
    }

    if (sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\989SND.IRX;1", 0, nullptr) < 0) {
      MsgErr("loading 989snd.irx failed\n");
    }

    lg::debug("Initializing CD library in ISO_CD mode...");
    auto rv =
        sceSifLoadModule("cdrom0:\\\\DRIVERS\\\\OVERLORD.IRX;1", total_len, overlord_boot_command);
    if (rv < 0) {
      MsgErr("loading overlord.irx failed\n");
    }
  }
  auto rv = sceMcInit();
  if (rv < 0) {
    MsgErr("MC driver init failed %d\n", rv);
  } else {
    lg::info("InitIOP OK");
  }
}

AutoSplitterBlock g_auto_splitter_block_jak1;

// GENERAL crash-loop guard: a persisted setting must NEVER brick the game. A sentinel file
// ("recharged-boot-guard") next to settings.ini holds a consecutive-unhealthy-boot count. At
// boot we bump it; if it already reached 2 (two boots that died before reaching healthy
// gameplay) we defensively reset the two risky settings in settings.ini (pbr-displacement ->
// Off, pbr-test-preset -> default) and clamp them for this session. After 60s of healthy
// running the sentinel is deleted so a normal session never trips it. Mirrors the AO-specific
// ao-boot-guard style (fs::* via ghc + file_util text IO) but is a distinct GENERAL guard.
namespace {
constexpr double kRechargedGuardHealthySecs = 60.0;
fs::path recharged_boot_guard_path() {
  return file_util::get_user_settings_dir(g_game_version) / "recharged-boot-guard";
}
fs::path recharged_settings_ini_path() {
  return file_util::get_user_settings_dir(g_game_version) / "settings.ini";
}
bool s_recharged_guard_tripped = false;      // this boot resets/clamps the risky settings
double s_recharged_boot_t = -1.0;            // steady_clock boot time (for the healthy clear)
// Rewrite the VALUE on `pbr-displacement = <n>` -> 0 and `pbr-test-preset = <n>` -> default (1),
// preserving every other line byte-for-byte. Missing file / missing key is skipped gracefully.
void recharged_reset_risky_ini() {
  const auto ini = recharged_settings_ini_path();
  if (!file_util::file_exists(ini.string())) {
    return;  // no settings.ini yet — nothing to reset
  }
  std::string text;
  try {
    text = file_util::read_text_file(ini);
  } catch (...) {
    return;  // unreadable — skip gracefully
  }
  // Line-by-line rewrite. Only lines whose trimmed key matches get their value replaced; all
  // other bytes (including line endings) are preserved.
  auto rewrite_line = [](const std::string& line) -> std::string {
    // find the key portion before '='
    auto eq = line.find('=');
    if (eq == std::string::npos) {
      return line;
    }
    std::string key = line.substr(0, eq);
    // trim whitespace around the key
    size_t ks = key.find_first_not_of(" \t");
    size_t ke = key.find_last_not_of(" \t");
    if (ks == std::string::npos) {
      return line;
    }
    std::string trimmed = key.substr(ks, ke - ks + 1);
    if (trimmed == "pbr-displacement") {
      return line.substr(0, eq) + "= 0";
    }
    if (trimmed == "pbr-test-preset") {
      return line.substr(0, eq) + "= 1";
    }
    return line;
  };
  std::string out;
  out.reserve(text.size());
  size_t start = 0;
  while (start <= text.size()) {
    size_t nl = text.find('\n', start);
    if (nl == std::string::npos) {
      if (start < text.size()) {
        out += rewrite_line(text.substr(start));
      }
      break;
    }
    // include any trailing '\r' in the line body so the '\n' stays the only separator we re-add
    out += rewrite_line(text.substr(start, nl - start));
    out += '\n';
    start = nl + 1;
  }
  try {
    file_util::write_text_file(ini, out);
  } catch (...) {
    // best-effort — a failed rewrite still leaves the session clamp in place
  }
}
// Boot-time crash-loop check. Runs from InitMachine (after the Android external game-root is set
// by goal_main, before GOAL boots and loads settings.ini).
void recharged_crash_loop_guard_boot() {
  s_recharged_boot_t =
      std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  const auto guard = recharged_boot_guard_path();
  int c = 0;
  if (file_util::file_exists(guard.string())) {
    try {
      c = std::stoi(file_util::read_text_file(guard));
    } catch (...) {
      c = 0;  // unparseable -> treat as fresh
    }
  }
  if (c >= 2) {
    recharged_reset_risky_ini();
    lg::warn(
        "[recharged] crash-loop guard: settings reset (2 consecutive boots died before "
        "gameplay) — pbr-displacement -> Off, pbr-test-preset -> default");
    s_recharged_guard_tripped = true;
    try {
      file_util::write_text_file(guard, "1");  // count this boot as unhealthy until it survives
    } catch (...) {
    }
  } else {
    try {
      file_util::write_text_file(guard, std::to_string(c + 1));
    } catch (...) {
    }
  }
}
}  // namespace

/*!
 * Initialize GOAL Runtime. This is the main initialization which is called before entering
 * the GOAL kernel dispatch loop (KernelCheckAndDispatch).
 * TODO finish up things which are commented.
 */
int InitMachine() {
  // GENERAL crash-loop guard: bump/inspect the boot sentinel BEFORE GOAL boots and loads
  // settings.ini. On Android the external game-root (which decides where the settings dir is)
  // is already set by goal_main before InitMachine runs, so the path is final here.
  recharged_crash_loop_guard_boot();

  u32 debug_heap_end = (0xffffffff - DEBUG_HEAP_SPACE_FOR_STACK + 1) & 0x7ffffff;

  // initialize the global heap
  u32 global_heap_size = GLOBAL_HEAP_END - HEAP_START;
  float size_mb = ((float)global_heap_size) / (float)(1 << 20);
  lg::info("gkernel: global heap 0x{:08x} to 0x{:08x} (size {:.3f} MB)", HEAP_START,
           GLOBAL_HEAP_END, size_mb);
  kinitheap(kglobalheap, Ptr<u8>(HEAP_START), global_heap_size);

  // initialize the debug heap, if appropriate
  if (MasterDebug) {
    u32 debug_heap_size = debug_heap_end - DEBUG_HEAP_START;
    kinitheap(kdebugheap, Ptr<u8>(DEBUG_HEAP_START), debug_heap_size);
    float debug_size_mb = ((float)debug_heap_size) / (float)(1 << 20);
    float gap_size_mb = ((float)DEBUG_HEAP_START - GLOBAL_HEAP_END) / (float)(1 << 20);
    lg::info("gkernel: debug heap 0x{:08x} to 0x{:08x} (size {:.3f} MB, gap {:.3f} MB)",
             DEBUG_HEAP_START, debug_heap_end, debug_size_mb, gap_size_mb);
  } else {
    // if no debug, we make the kheapinfo structure NULL so GOAL knows not to use it.
    kdebugheap.offset = 0;
  }

  init_output();    // GOAL input/output buffer setup
  jak1::InitIOP();  // start IOP/OVERLORD, loading our legal splash screen

  // sceGsResetPath(); // reset VIF1, VU1, GIF

  InitVideo();  // display legal splash screen

  // FlushCache(WRITEBACK_DCACHE);
  // FlushCache(INVALIDATE_ICACHE);
  // sceGsSyncV(0);   // wait for it to show up on the screen
  //
  // if(scePadInit(0) != 1) { // init controllers
  //   MsgErr("dkernel: !init pad\n");
  // }

  if (MasterDebug) {  // connect to GOAL compiler
    InitGoalProto();
  } else {
    // shut down the deci2 stuff, we don't need it.
    ee::sceDeci2Disable();
  }

  lg::info("InitSound");
  InitSound();  // do nothing!
  lg::info("InitRPC");
  InitRPC();       // connect to IOP
  reset_output();  // reset output buffers
  clear_print();

  s32 goal_status = InitHeapAndSymbol();  // init GOAL runtime, load kernel and engine
  if (goal_status < 0) {
    return goal_status;
  }

  // TODO - better place to put this?
  // TODO - yes, see jak2's code!
  g_auto_splitter_block_jak1.pointer_to_symbol =
      (u64)g_ee_main_mem + intern_from_c("*autosplit-info-jak1*")->value;

  lg::info("InitListenerConnect");
  InitListenerConnect();
  lg::info("InitCheckListener");
  InitCheckListener();
  Msg(6, "kernel: machine started\n");
  return 0;
}

/*!
 * Shutdown the runtime.
 */
int ShutdownMachine() {
  StopIOP();
  CloseListener();
  ShutdownSound();
  ShutdownGoalProto();

  Msg(6, "kernel: machine shutdown\n");
  return 0;
}

/*!
 * Open a file-stream.  Name is a GOAL string. Mode is a GOAL symbol.  Use 'read for readonly
 * and anything else for write only.
 */
u64 kopen(u64 fs, u64 name, u64 mode) {
  auto file_stream = Ptr<FileStream>(fs).c();
  file_stream->mode = mode;
  file_stream->name = name;
  file_stream->flags = 0;
  lg::print("****** CALL TO kopen() ******\n");
  // sprintf(buffer, "host:%s", Ptr<String>(name)->data());
  if (!strcmp(info(Ptr<Symbol>(mode))->str->data(), "read")) {
    file_stream->file = sceOpen(Ptr<String>(name)->data(), SCE_RDONLY);
  } else {
    // 0x602
    file_stream->file = sceOpen(Ptr<String>(name)->data(), SCE_TRUNC | SCE_CREAT | SCE_WRONLY);
  }

  return fs;
}

void PutDisplayEnv(u32 ptr) {
  // we can mostly ignore this, except for one value that sets the 'blackout' amount.
  u8 alp = Ptr<u8>(ptr).c()[1];
  auto* renderer = Gfx::GetCurrentRenderer();
  if (renderer) {
    renderer->set_pmode_alp(alp / 255.f);
  }
}

void update_discord_rpc(u32 discord_info) {
  if (gDiscordRpcEnabled) {
    DiscordRichPresence rpc;
    char state[128];
    char large_image_key[128];
    char large_image_text[128];
    char small_image_key[128];
    char small_image_text[128];
    auto info = discord_info ? Ptr<DiscordInfo>(discord_info).c() : NULL;
    if (info) {
      int cells = (int)*Ptr<float>(info->fuel).c();
      int orbs = (int)*Ptr<float>(info->money_total).c();
      int scout_flies = (int)*Ptr<float>(info->buzzer_total).c();
      int deaths = *Ptr<int>(info->deaths).c();
      float time = *Ptr<float>(info->time_of_day).c();
      auto cutscene = Ptr<Symbol>(info->cutscene)->value;
      auto ogreboss = Ptr<Symbol>(info->ogreboss)->value;
      auto plantboss = Ptr<Symbol>(info->plantboss)->value;
      auto racer = Ptr<Symbol>(info->racer)->value;
      auto flutflut = Ptr<Symbol>(info->flutflut)->value;
      char* status = Ptr<String>(info->status).c()->data();
      char* level = Ptr<String>(info->level).c()->data();
      const char* full_level_name =
          get_full_level_name(level_names, level_name_remap, Ptr<String>(info->level).c()->data());
      memset(&rpc, 0, sizeof(rpc));
      if (!indoors(indoor_levels, level)) {
        char level_with_tod[128];
        strcpy(level_with_tod, level);
        strcat(level_with_tod, "-");
        strcat(level_with_tod, time_of_day_str(time));
        strcpy(large_image_key, level_with_tod);
      } else {
        strcpy(large_image_key, level);
      }
      strcpy(large_image_text, full_level_name);
      if (!strcmp(full_level_name, "unknown")) {
        strcpy(large_image_key, full_level_name);
        strcpy(large_image_text, level);
      }
      rpc.largeImageKey = large_image_key;
      if (!strcmp(level, "finalboss")) {
        strcpy(state, "Fighting Final Boss");
      } else if (plantboss != offset_of_s7()) {
        strcpy(state, "Fighting Dark Eco Plant");
        rpc.largeImageKey = "plant-boss";
        strcpy(large_image_text, "Dark Eco Plant");
      } else if (ogreboss != offset_of_s7()) {
        strcpy(state, "Fighting Klaww");
        rpc.largeImageKey = "ogreboss";
        strcpy(large_image_text, "Klaww");
      } else if (!strcmp(level, "title")) {
        strcpy(state, "On title screen");
        rpc.largeImageKey = "title";
        strcpy(large_image_text, "Title screen");
      } else if (!strcmp(level, "intro")) {
        strcpy(state, "Intro");
      } else if (cutscene != offset_of_s7()) {
        strcpy(state, "Watching a cutscene");
        strcpy(large_image_text, fmt::format("Cells: {} | Orbs: {} | Flies: {} | Deaths: {}",
                                             std::to_string(cells), std::to_string(orbs),
                                             std::to_string(scout_flies), std::to_string(deaths))
                                     .c_str());
      } else {
        strcpy(state, fmt::format("Cells: {} | Orbs: {} | Flies: {}", std::to_string(cells),
                                  std::to_string(orbs), std::to_string(scout_flies))
                          .c_str());

        strcat(large_image_text, fmt::format(" | Deaths: {}", std::to_string(deaths)).c_str());
      }
      rpc.largeImageText = large_image_text;
      rpc.state = state;
      if (racer != offset_of_s7()) {
        strcpy(small_image_key, "target-racer");
        strcpy(small_image_text, "Driving A-Grav Zoomer");
      } else if (flutflut != offset_of_s7()) {
        strcpy(small_image_key, "flutflut");
        strcpy(small_image_text, "Riding on Flut Flut");
      } else {
        if (!indoors(indoor_levels, level)) {
          strcpy(small_image_key, time_of_day_str(time));
          strcpy(small_image_text, "Time of day: ");
          strcat(small_image_text, get_time_of_day(time).c_str());
        } else {
          strcpy(small_image_key, "");
          strcpy(small_image_text, "");
        }
      }
      rpc.smallImageKey = small_image_key;
      rpc.smallImageText = small_image_text;
      rpc.startTimestamp = gStartTime;
      rpc.details = status;
      rpc.partySize = 0;
      rpc.partyMax = 0;
      Discord_UpdatePresence(&rpc);
    }
  } else {
    Discord_ClearPresence();
  }
}

void pc_set_levels(u32 l0, u32 l1) {
  if (!Gfx::GetCurrentRenderer()) {
    return;
  }
  std::string l0s = Ptr<String>(l0).c()->data();
  std::string l1s = Ptr<String>(l1).c()->data();

  std::vector<std::string> levels;
  if (l0s != "none" && l0s != "#f") {
    levels.push_back(l0s);
  }

  if (l1s != "none" && l1s != "#f") {
    levels.push_back(l1s);
  }

  Gfx::GetCurrentRenderer()->set_levels(levels);
}

// Grecharged-grass-poc: push the "recharged grass" on/off toggle from GOAL
// (-> *pc-settings* recharged-grass?) down to the renderer. 0 = off (stock).
void pc_set_recharged_grass(u32 on) {
  Gfx::g_global_settings.recharged_grass = (on != 0);
}

// External-asset-root: toggle runtime custom texture replacements (user PNGs
// under <root>/custom_assets/texture_replacements). 0 = off (stock).
void pc_set_load_custom_assets(u32 on) {
  Gfx::g_global_settings.load_custom_assets = (on != 0);
}

// Grecharged-bundled-textures: 0/1 toggle for the package-bundled first-party replacement
// textures (base albedo swaps only; the bundle's PBR maps follow the PBR path instead).
void pc_set_recharged_textures(u32 on) {
  Gfx::g_global_settings.recharged_textures = (on != 0);
}

// Grecharged-master-toggle: push the GLOBAL Recharged master from GOAL
// (-> *pc-settings* recharged-master?). 0 = every recharged feature forced to its stock
// state via Gfx::recharged_active() (the individual flags keep the user's values, so the
// configuration comes back exactly when the master returns ON). Logs on CHANGE only
// (pushed every frame by update-to-os), so a device log proves the GOAL->C++ link.
void pc_set_recharged_master(u32 on) {
  bool v = (on != 0);
  if (v != Gfx::g_global_settings.recharged_master) {
    lg::info("[recharged-master] toggle -> {}", v ? "ON" : "OFF");
  }
  Gfx::g_global_settings.recharged_master = v;
}

// Grecharged-grass-overhang: push the "grass overhang" on/off toggle from GOAL
// (-> *pc-settings* recharged-grass-overhang?). 0 = off (walkable-top grass only, stock
// alpha overhang texture at every distance).
#ifdef OG_FEAT_GRASS_OVERHANG
void pc_set_grass_overhang(u32 on) {
  Gfx::g_global_settings.recharged_grass_overhang = (on != 0);
}
#endif

// Grecharged-ambient-occlusion defect #6 resilience (safe-boot fallback): a crashy
// persisted AO mode must never brick boot. A sentinel file is armed next to pc-settings
// when AO becomes active and cleared after 60s of healthy pushes (or on a clean AO-off).
// If a session dies inside that window the sentinel survives, and the NEXT boot pins AO
// off (one boot only, loudly logged). The latch clears the moment the user picks a
// DIFFERENT mode in the menu, so the setting stays user-controllable.
namespace {
constexpr double kAoGuardHealthySecs = 60.0;
fs::path ao_boot_guard_path() {
  return file_util::get_user_settings_dir(g_game_version) / "ao-boot-guard";
}
double ao_now_s() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
bool s_ao_safeboot_latched = false;  // this boot runs with AO pinned off
int s_ao_safeboot_mode = -1;         // the refused persisted mode (a different pick clears)
double s_ao_enable_t = -1.0;         // when AO became active this session (-1 = inactive)
bool s_ao_guard_armed = false;       // sentinel currently on disk for this session
}  // namespace

// Grecharged-ambient-occlusion: push the AO algorithm selector + quality + strength from GOAL
// (-> *pc-settings* ambient-occlusion / ao-quality / ao-strength). mode: 0 off / 1 SSAO / 2 HBAO
// / 3 GTAO; quality: 0 low / 1 medium / 2 high; strength: 0 weaker / 1 default / 2 stronger. Logs
// on CHANGE only (pushed every frame by update-to-os), so a device log proves the GOAL->C++ link.
void pc_set_ambient_occlusion(u32 mode, u32 quality, u32 strength) {
  int m = (int)mode;
  int q = (int)quality;
  if (m < 0 || m > 3) {
    m = 0;
  }
  if (q < 0 || q > 2) {
    q = 1;
  }
  int s = (int)strength;
  if (s < 0 || s > 2) {
    s = 1;
  }
  if (s_ao_safeboot_latched) {
    if (m == 0 || m == s_ao_safeboot_mode) {
      m = 0;  // pinned off for this boot
    } else {
      lg::info("[recharged-ao] SAFE-BOOT latch cleared by user mode change -> {}", m);
      s_ao_safeboot_latched = false;
    }
  }
  if (m > 0 && s_ao_enable_t < 0.0 && !s_ao_safeboot_latched) {
    const auto guard = ao_boot_guard_path();
    if (file_util::file_exists(guard.string())) {
      lg::warn(
          "[recharged-ao] SAFE-BOOT: previous session died within {}s of AO enable — "
          "forcing AO OFF for this boot (persisted mode {} quality {})",
          (int)kAoGuardHealthySecs, m, q);
      std::error_code ec;
      fs::remove(guard, ec);  // one forced-off boot per incident
      s_ao_safeboot_latched = true;
      s_ao_safeboot_mode = m;
      m = 0;
    } else {
      file_util::write_text_file(guard, "ao-enable\n");
      s_ao_guard_armed = true;
      s_ao_enable_t = ao_now_s();
    }
  }
  if (s_ao_guard_armed) {
    if (m == 0) {  // clean disable: disarm and allow a later re-enable to re-arm
      std::error_code ec;
      fs::remove(ao_boot_guard_path(), ec);
      s_ao_guard_armed = false;
      s_ao_enable_t = -1.0;
    } else if (ao_now_s() - s_ao_enable_t > kAoGuardHealthySecs) {
      std::error_code ec;
      fs::remove(ao_boot_guard_path(), ec);
      s_ao_guard_armed = false;  // healthy: sentinel gone, s_ao_enable_t stays (no re-arm)
    }
  }
  if (m != Gfx::g_global_settings.recharged_ao_mode ||
      q != Gfx::g_global_settings.recharged_ao_quality ||
      s != Gfx::g_global_settings.recharged_ao_strength) {
    lg::info("[recharged-ao] mode -> {} quality -> {} strength -> {}", m, q, s);
    Gfx::g_global_settings.recharged_ao_mode = m;
    Gfx::g_global_settings.recharged_ao_quality = q;
    Gfx::g_global_settings.recharged_ao_strength = s;
  }
}

// Grecharged-foliage-wind: push the light-wind sway toggle from GOAL (pc-set-foliage-wind!).
// 0 = off => byte-identical stock render (no palm/shrub displacement). Logs on CHANGE only
// (update-to-os pushes this every frame), so a device log proves the GOAL->C++ link.
void pc_set_foliage_wind(u32 on) {
  bool v = (on != 0);
  if (v != Gfx::g_global_settings.recharged_foliage_wind) {
    lg::info("[foliage-wind] toggle -> {}", v ? "ON" : "OFF");
  }
  Gfx::g_global_settings.recharged_foliage_wind = v;
}

// Grecharged-title-logo-fullres: push the CRISP TITLE LOGO toggle from GOAL
// (pc-set-crisp-title-logo!). ON draws the title-screen JAK AND DAXTER logo (and the ND boot logo)
// at NATIVE resolution while the 3D world stays at RENDER SCALE. 0 = stock pipeline. Logs on
// CHANGE only (update-to-os pushes this every frame), so a device log proves the GOAL->C++ link.
void pc_set_crisp_title_logo(u32 on) {
  bool v = (on != 0);
  if (v != Gfx::g_global_settings.recharged_crisp_title_logo) {
    lg::info("[crisp-logo] toggle -> {}", v ? "ON" : "OFF");
  }
  Gfx::g_global_settings.recharged_crisp_title_logo = v;
}

// Grecharged-hd-models: push the "enhanced models" on/off toggle from GOAL
// (-> *pc-settings* recharged-enhanced-models?). 0 = off (stock low-poly). Applies live to
// village FR3 (Samos/Keira); the common FR3 (Jak/Daxter) is seeded from persisted settings at
// renderer init, so toggling those takes effect on relaunch.
#ifdef OG_FEAT_HD_MODELS
void pc_set_recharged_enhanced_models(u32 on) {
  // Grecharged-hd-models2 discriminator: the GOAL side pushes this EVERY frame from *pc-settings*
  // (update-to-os), so a push of the pre-settings-load default silently flips the renderer-ctor
  // seed and later level loads read STOCK fr3. Log transitions so runs carry the flip evidence.
  bool v = (on != 0);
  if (v != Gfx::g_global_settings.recharged_enhanced_models) {
    // lg (not raw stdout): on Android only lg::* routes to logcat.
    lg::info("HD-MODELS toggle push: {} -> {}", Gfx::g_global_settings.recharged_enhanced_models,
             v);
  }
  Gfx::g_global_settings.recharged_enhanced_models = v;
}

// Grecharged-hd-models4: per-actor coverage registry (global-scope prototypes above, before
// namespace jak1). An HD companion process registers which driver actor (pid) its merc
// submissions replace; Merc2 only suppresses a stock draw whose OWN pid is covered by an
// actively-found companion, so uncovered same-model actors (the ND-logo eichar) always keep
// their stock draw.
void pc_hd_cover(u32 companion_pid, u32 driver_pid) {
  ::merc2_hd_cover(companion_pid, driver_pid);
}
void pc_hd_uncover(u32 companion_pid) {
  ::merc2_hd_uncover(companion_pid);
}
#endif

// Grecharged-secondary-motion: data-driven secondary-motion (chain physics) parameter store + FFI.
// The GOAL side owns no floats across the FFI boundary here: EVERY value-returning entry point below
// returns MILLI-units (llround(value * 1000.0)) as an s64, and the caller divides by 1000. That keeps
// the whole surface int-FFI (the pc-set-rt-ambient-strength! convention) with 3 decimals of headroom,
// which is more than the authored data carries.
#ifdef OG_FEAT_PHYSICS
// Pushed every frame from (update-to-os) via pc-set-physics!, exactly like the HD-MODELS toggle.
static bool s_physics_on = false;
static int s_physics_level = 1;

// Defined further down with the parameter store; forward-declared so the toggle push below can
// trigger a re-parse without moving the store above its own dependencies.
static int pc_physics_parse_file();

void pc_set_physics(u32 on, u32 level) {
  bool v = (on != 0);
  int lv = (int)level;
  if (v != s_physics_on || lv != s_physics_level) {
    // lg (not raw stdout): on Android only lg::* routes to logcat.
    lg::info("[hd-phys] toggle push: {} lvl {} -> {} lvl {}", s_physics_on, s_physics_level, v, lv);
    // Owner iteration loop: flipping the physics toggle (or the precision level) in the menu is the
    // documented way to re-read a hot-pushed physics_chains.txt. Re-parsing here bumps the
    // generation, and every live sim slot re-binds its chains on its next step. (The parse marks
    // the store loaded itself, so a toggle arriving before the first ensure_loaded() does not get
    // followed by a second, redundant parse. Generation is an opaque change token, never a count.)
    pc_physics_parse_file();
  }
  s_physics_on = v;
  s_physics_level = lv;
}

// ---- recharged_assets/physics_chains.txt parameter store -------------------------------------
// class bits: primary=1 secondary=2 accessory=4
enum PhysClassBits { kPhysClassPrimary = 1, kPhysClassSecondary = 2, kPhysClassAccessory = 4 };
// chain param ids (pc_physics_chain_param_mi):
//   0 stiffness(Hz) 1 damping 2 gravity 3 maxangle(deg) 4 inertia 5 stretch 6 radius(units)
//   7 rootlock(links pinned rigidly at the root) 8 gradient(root->tip freedom exponent)
//   9 animmode(0 keep / 1 replace / 2 excite) 10 excite(scale) 11 friction(0..1 contact)
// CYCLE 3 (owner 2026-08-06) — authored-animation priority, freedom floor, descendant policy:
//   12 authored(engage threshold: authored offset as a FRACTION of the chain's own length; 0 = off)
//   13 authrise(blend-in rate /s) 14 authfall(blend-out rate /s) 15 authstiff(stiffness x at w=1)
//   16 rootfree(floor of the root->tip freedom ramp, 0..1 — a SHORT chain must still bend)
//   17 nodesc(1 = do NOT rigid-re-glue this chain's descendants: they carry their own animation)
//   18 colskip(leading links exempt from BODY COLLISION — the chain's ATTACHMENT to the body sits
//      inside the body volume by construction. Until cycle 3 that exemption was implied by
//      rootlock=, so freeing a hair root to move would also have started colliding it with the
//      skull it is glued to: a permanent penetration no tuning could clear. The two ideas are
//      separated here — `rootlock` is "does this link move?", `colskip` is "is this link inside
//      the body on purpose?". Effective value is max(rootlock, colskip), so 0 = exactly the
//      pre-cycle-3 behaviour.)
//   19 mass(cycle 3b, owner K: "on ne sent pas la masse... trop leger et JELLY". Amplitude was not
//      the defect — the RESPONSE was. A heavier chain resists starting and keeps going once it has:
//      omega_eff = omega / sqrt(mass), so the natural frequency drops with real mass while the
//      swing envelope (cone + stretch) is untouched. 1.0 = the pre-cycle-3b spring.)
// CYCLE 4 (owner 2026-08-06 14:45, "as-tu defini un HAUT et un BAS, une MASSE ?"):
//   20 hang(0..1 — HOW MUCH OF THIS CHAIN'S REST DIRECTION IS GRAVITY'S rather than the animator's.
//      Gravity was already applied in WORLD space, but the chain's whole equilibrium was pinned to
//      the AUTHORED bone direction: the spring pulls to the authored pose and the swing cone is
//      centred on the authored direction, so a cuff modelled sticking out along a horizontal forearm
//      can only ever wobble around "forward" — which is exactly what the owner sees on Gol's sleeve.
//      hang= rebuilds the chain's rest pose each frame from world DOWN instead: rest_dir =
//      normalize(mix(authored_dir, (0,-1,0), hang)), link lengths preserved. 0 = the authored pose is
//      the rest pose (every pre-cycle-4 chain, unchanged); 1 = pure cloth, hangs straight down from
//      its anchor whatever the bone underneath is doing.)
//   21 swing(0..1 — how much of the chain's ROTATION reaches the bone. The write-back turns a bone by
//      swing(rest-direction -> simulated-direction) about its own origin, which for a one-link chain
//      pivots the whole mesh about the bone's root: the tip travels, the base does not. On a cloth
//      flap that is right; on a BREAST it is exactly the owner's "seuls les bouts de ses seins
//      bougent". Lowering swing keeps the full simulated TRANSLATION — so every vertex weighted to
//      the bone moves together, as a volume — while damping the pivot. 1.0 = pre-cycle-4 write-back.)
// CYCLE 5 (owner 2026-08-06) — MANDATORY per-chain FAMILY, and the geometry a chain needs to be
// judged against the model instead of against itself:
//   22 family(0 = UNDECLARED / not classified, 1 = A, 2 = B. Declared in the data as a LETTER.
//      A = BODY: hair, chest, ears. Simulated at all times, but its equilibrium target is the
//      MODEL POSE — no lower (droop) and no higher. B = HANGS: straps, accessories, hanging
//      cloth. Gravity dictates its rest; it must NEVER be pulled back to the model pose. One
//      setting shared by both families is the defect this id exists to make detectable.)
//   23 side(0 = none/centred, 1 = L, 2 = R. Declared as a LETTER. Lets cross-side penetration be
//      accounted for by name — a left jacket flap crossing through the RIGHT leg is a different
//      failure from the same flap grazing its own leg.)
//   24 extent(UNITS of rigidly-skinned geometry hanging BELOW this chain's last bone. Jak's two
//      jacket pendants are one joint each with all the cloth underneath: colliding the bone point
//      proved nothing, the bone stayed outside the thigh while the cloth swept through the other
//      leg. Non-zero moves the collision test to the middle of that continuation and inflates the
//      radius to circumscribe it. 0 = the bone is the whole chain, i.e. every pre-cycle-5 line.)
//   25 compress(FRACTION of its authored length a link may lose, 0..0.9. 0 IS THE DEFAULT and it
//      is a deliberate behaviour change: `stretch=` used to bound the distance constraint in BOTH
//      directions, so a chest link could legally lose 22% of its length and Jak's collar could
//      simply shorten until a contact solved itself. Owner X: "rien ne doit se TASSER".)
// CYCLE 6 (owner 2026-08-07) — the audit's OWN positive control:
//   26 inject(UNITS by which this chain is DELIBERATELY displaced into the body, so the
//      penetration audit can be shown to FIRE before any zero it reports is believed. Three
//      vacuous zeros in a single day (resid/push, idledrift/idlewin, restdevA/restwin) are what
//      this id exists to make impossible: arm it, watch the counter rise, disarm it, watch it fall
//      back. Default 0 = OFF, and it MUST default off — a control left armed is a defect shipped.)
// CYCLE 7 (owner AB/AG, supervisor gate AH) — amplitude that does not cost firmness:
//   27 couple(ANCHOR COUPLING GAIN. A chain's only excitation until now was the lag it develops
//      behind its own moving target, and that lag is g/omega^2 — inversely proportional to the
//      SQUARE of the stiffness. So "plus de jiggle ET un poil plus de fermete" was literally
//      unreachable: every notch of firmness bought was paid for out of the travel, which is how
//      cycle 6 ended up "beaucoup plus FLASQUE" and still "ne bouge PAS ASSEZ". This adds the
//      pseudo-force of the accelerating anchor frame explicitly, scaled by this gain, so the
//      deviation equation becomes d'' + 2*zeta*w*d' + w^2*d = -(1 + couple)*a_anchor. Amplitude
//      is then set by `couple` and firmness by `stiffness`, independently. 0 = OFF and it MUST
//      default off: every chain that shipped before this cycle keeps its exact behaviour.)
// CYCLE 8 (owner, 11e passe 2026-08-11: « le bas de son pantacourt clipe toujours a l'interieur de
// ses mollets au lieu d'etre visible, comme si son pantacourt s'arretait aux genoux »):
//   28 shell(INNER RADIUS, in units, of the SLEEVE this link forms AROUND a limb — the distance
//      from that limb's axis out to the cloth. A pant flap is a CLOSED shell wrapped around the
//      calf, so its fitted radius (429 left / 443 right) is the radius of that sleeve, yet the
//      solver spends it as the radius of a PUSH-OUT SPHERE centred on the link: the flap's centroid
//      sits 95u from the calf axis — i.e. essentially ON it — so the contact test reads a ~700u
//      penetration and ejects the flap sideways every frame, burying half the cloth inside the leg.
//      Pushing a sleeve OUT of the limb it encircles is geometrically meaningless; what such a link
//      owes is CONCENTRICITY, and this id is how the engine is told which links are sleeves and how
//      wide. 0 = this link is not a sleeve, and 0 is the default of every chain that shipped before
//      this cycle, so adding the key moves nothing that does not declare it.)
static constexpr int kPhysNumChainParams = 30;
// level param ids (pc_physics_level_param_mi):
//   0 substeps 1 iters 2 collide 3 classmask 4 fixedhz  -- ALSO returned in milli.
static constexpr int kPhysNumLevelParams = 5;
static constexpr int kPhysMaxLevels = 8;

struct PhysChain {
  std::string name;
  int class_bits = 0;
  //                                   0  1  2  3    4  5  6  7  8    9 10    11
  float params[kPhysNumChainParams] = {0, 0, 0, 0, 1.f, 0, 0, 0, 0, 1.f, 0, 0.5f,
                                       // 12 authored 13 authrise 14 authfall 15 authstiff
                                       // authored DEFAULTS OFF (0) ON PURPOSE. Cycle 2 removed jak1's
                                       // hand-keyed pseudo-WIND from physics-owned bones and the owner
                                       // re-confirmed at cycle 3 that it stays removed. A nonzero
                                       // default would let that same wind cross the engage threshold
                                       // and take the chain back — re-introducing the exact
                                       // double-writer the owner rejected. So authored priority is
                                       // OPT-IN, declared only on bones ND genuinely ACTS with.
                                       0.f, 8.f, 3.f, 4.f,
                                       // 16 rootfree 17 nodesc 18 colskip 19 mass
                                       // rootfree DEFAULTS to 0.3 — cast-wide by construction (owner
                                       // cycle-3 I). Without a floor the stiffest free link only ever
                                       // keeps 1/nfree of the swing cone, which is what left Jak's
                                       // 2-joint coiffe and Keira's short back hair reading as stiff.
                                       // It can only ever RAISE a link's freedom, never lower it, so
                                       // no already-accepted chain (Jak's straps at 0.75, Keira's
                                       // bangs at 0.5) is touched by the default.
                                       0.3f, 0.f, 0.f, 1.f,
                                       // 20 hang 21 swing — both default to the pre-cycle-4
                                       // behaviour EXACTLY (rest pose = the authored pose, full
                                       // rotation written back), so adding them cannot move a single
                                       // chain the owner has already accepted. They only do
                                       // something where the data asks for it.
                                       0.f, 1.f,
                                       // 22 family 23 side 24 extent 25 compress — all default to
                                       // 0 = UNDECLARED. family/side are letters in the data (A/B,
                                       // L/R) and 0 means the chain has not been classified at all;
                                       // extent/compress are units and 0 means "no allowance", so a
                                       // chain that never declares compress= may not compress.
                                       0.f, 0.f, 0.f, 0.f,
                                       // 26 inject — the penetration audit's POSITIVE CONTROL, and
                                       // the one param whose default is a safety property rather
                                       // than a behaviour: a control left armed ships a chain
                                       // buried in the body. 0 = disarmed.
                                       0.f,
                                       // 27 couple — anchor-coupling gain. 0 = the pre-cycle-7
                                       // excitation exactly (lag behind the moving target and
                                       // nothing else), so adding this key moves no chain that
                                       // does not ask for it.
                                       0.f,
                                       // 28 shell — sleeve inner radius in units. 0 = "this link
                                       // is not a sleeve", which is what every chain written
                                       // before cycle 8 says by omission, so the concentricity
                                       // constraint can only ever engage where the data asks.
                                       0.f,
                                       // 29 b0 — SPEC 6's B0: the ROOT-TO-APEX length of the FLESH,
                                       // in units, measured on the mesh. NOT the bone length: on
                                       // Keira the bone chest->lBoob is 977 u while the tissue runs
                                       // 602 u, so a bound expressed "in B0" against the bone is
                                       // 1.62x too loose and SPEC 22's apex ceiling cannot fire.
                                       // 0 = UNDECLARED, and the engine then falls back to the bone
                                       // length exactly as before — so adding this key moves no
                                       // chain that does not carry it.
                                       0.f};
  std::vector<std::string> joints;   // ordered root -> tip
  std::vector<float> link_radius;    // radii= : per-LINK collision radius, mesh-derived
  // comw= : per-LINK share of the organ's skin mass, mesh-derived, ONE PER LINK root -> tip.
  // SPEC 6 defines `P0` as the breast CENTER-OF-MASS position and SPEC 22 bounds "Breast COM";
  // a centre of mass is a MASS-WEIGHTED MEAN, so the reader of a per-link excursion needs the
  // per-link mass to form it. Under linear blend skinning the identity is exact:
  //   d_COM = (1/N) * SUM_j W_j * (M_j^sim - M_j^auth) * c_j,   comw[l] = W_l / N.
  // The anchored flesh (chest, shoulder) is NOT listed: it is not simulated, its excursion is
  // zero by construction, and it is accounted for by the weights summing to LESS than 1.
  // 0/absent = UNDECLARED, and the engine then publishes no COM at all rather than a wrong one,
  // so adding this key moves no chain that does not carry it.
  std::vector<float> link_comw;
  // `pk <Key> <value>` : the CHARACTER PRESET, copied VERBATIM from SPEC-breast-softbody.md
  // section 38 by .autoport/preset_apply.py — key name and number, never re-typed by hand.
  // The owner, 2026-08-22: « les memes proprietes des presets ont des valeurs differentes, on
  // pourrait donc imaginer que ces knobs influencent proprement le tout ». A preset that gives
  // the SAME keys with DIFFERENT numbers for two characters writes INPUTS, not observations —
  // so every key here is a channel the engine READS, and a key the engine does not read is
  // reported as CANAL ABSENT rather than silently ignored.
  // Parallel vectors, insertion order preserved; lookup is BY NAME (see kPhysPresetKeys).
  std::vector<std::string> pkey;
  std::vector<float> pval;
  // (C51) ax= : the APEX region representative, per LINK — `w` is the share of the distal
  // region's skin mass this link carries, `p` the mass-weighted centroid of that region in THIS
  // link's bone-local bind space (game units). Comes from recharged_assets/physics_mesh.txt
  // (.autoport/physics_c14_meshsamples.py), derived data, never hand-tuned. Same algebra as
  // link_comw, applied to a SUB-POPULATION instead of the whole cloud:
  //   d_apex = SUM_l w_l * (M_l^sim - M_l^auth) * p_l
  // exact under linear blend skinning. The ANCHORED share (chest carries 41-43% of this region)
  // is not simulated, does not move, and is accounted for by the weights summing to LESS than 1
  // — which is also why an apex ceiling can be out of reach with no tuning able to change it.
  // Empty = no ax= record; GOAL then publishes no apex at all rather than an apex of zero.
  std::vector<float> link_apexw;                 // outer index = link
  std::vector<std::array<float, 3>> link_apexp;  // outer index = link
  std::vector<std::string> xchains;  // xchain= : chains this chain must be collided against
  // (C14) per-link EXTREMAL skinned-vertex offsets, bone-local bind space, game units, <=5 per
  // link. This is the geometry the mesh-surface penetration audit samples: the owner's eyes live
  // on the mesh, and every bone-level counter before this one produced a zero he could refute by
  // looking. Comes from recharged_assets/physics_mesh.txt (derived data, physics_c14_meshsamples.py),
  // never hand-tuned. Outer index = link; empty = no sample reaches beyond the link radius.
  std::vector<std::vector<std::array<float, 3>>> mesh_samples;
};

// A body collision volume: a SPHERE on `joint`, or — when `joint2` is set — a CAPSULE (swept
// sphere) spanning `joint` -> `joint2`, so it follows two animated bones. `chains` restricts which
// chains of the model the volume pushes out; an EMPTY list means it applies to every chain (legacy
// behavior). `tier` selects how aggressively it is kept at lower precision levels. Several
// colliders may sit on the same joint with different filters/radii.
struct PhysCollider {
  std::string joint;
  float radius = 0.f;
  // CYCLE 3 (owner C): a constant-radius capsule cannot model a FLARED trouser leg or a shoulder,
  // and Jak's jacket hem clipped straight through because of it. `radius2` gives the far end its own
  // radius, so the volume is a CONE; <= 0 means "same as radius" (a plain cylinder, as before).
  float radius2 = 0.f;
  std::vector<std::string> chains;  // empty = applies to ALL chains
  std::string joint2;               // empty = sphere; non-empty = CAPSULE from `joint` to `joint2`
  int tier = 1;  // 1 = core (on at every precision level with collisions), 2 = extended
  int side = 0;             // 0 = none, 1 = L, 2 = R (cross-side penetration accounting)
  std::string chainref;     // non-empty: centre this sphere on the SIMULATED TIP of that chain
  // CYCLE 7 (owner, 6e passe 2026-08-11): « lBoob et rBoob sont des spheres nues posees sur le
  // joint-racine, alors que tout le reste du corps est en capsules derivees. Une sphere au joint
  // ne peut pas epouser un sein. » Le centre d'une sphere n'a aucune raison d'etre le joint : la
  // geometrie qu'elle represente a un CENTRE, mesure sur le mesh (centroide des sommets skinnes du
  // joint, exprime dans l'espace bind du joint, en unites de jeu). Le moteur le transforme par la
  // matrice de l'os, donc le volume suit l'animation comme le joint lui-meme.
  // Absent des donnees = 0,0,0 = le comportement d'avant, au bit pres.
  float ox = 0.f, oy = 0.f, oz = 0.f;
};

struct PhysModel {
  std::vector<PhysChain> chains;
  std::vector<PhysCollider> colliders;
  // bone-local body SURFACE samples with outward normals — the real skinned surface the
  // chains are tested against (SPEC 18). Capsules stay as broad phase only.
  // Comes from the `bs` records of recharged_assets/physics_mesh.txt, the same derived file the
  // per-link `ms` samples above live in, with the same hot-reload and external-override
  // lifecycle. The two vectors are strictly parallel (one entry each per set); a pack with no
  // `bs` lines simply leaves them empty, which the FFI reports as zero sets.
  std::vector<std::string> bsurf_joint;                  // per set: the bone it sits on
  std::vector<std::vector<std::array<float, 6>>> bsurf;  // per set: {x,y,z,nx,ny,nz}
};

static std::map<std::string, PhysModel> s_phys_models;
static float s_phys_levels[kPhysMaxLevels][kPhysNumLevelParams] = {};
static int s_phys_level_count = 0;
static bool s_phys_loaded_once = false;
// Bumped on every (re)parse. GOAL slots compare it and re-bind their chains when it changes, so a
// hot-pushed physics_chains.txt takes effect on companions AND stock riders without a respawn.
static int s_phys_generation = 0;

static std::vector<std::string> phys_tokens(const std::string& line) {
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

// "key=value" -> true + the two halves. Anything without '=' is not a kv token.
static bool phys_kv(const std::string& tok, std::string& key, std::string& val) {
  auto eq = tok.find('=');
  if (eq == std::string::npos) {
    return false;
  }
  key = tok.substr(0, eq);
  val = tok.substr(eq + 1);
  return true;
}

static float phys_to_float(const std::string& s) {
  try {
    return std::stof(s);
  } catch (...) {
    return 0.f;
  }
}

// Shared key=value handling for the `collider` (sphere) and `capsule` lines — the two differ only
// in how many leading joint tokens they consume. Returns false for an unrecognized key so the
// caller can emit the usual one-shot "unknown key" warning.
// CYCLE 5 adds two keys:
//   side=L|R   which side of the body this volume belongs to, so a chain declaring side= can be
//              accounted for when it penetrates the OPPOSITE side (query field 5).
//   at=<chain> centre this sphere on the SIMULATED TIP of that chain instead of on a bone: the way
//              two chains (Keira's chests) are made to collide with each other (query field 6).
static bool phys_collider_kv(PhysCollider& col, const std::string& k, const std::string& v) {
  if (k == "radius") {
    col.radius = phys_to_float(v);
  } else if (k == "radius2") {
    col.radius2 = phys_to_float(v);
  } else if (k == "chains") {
    // comma-separated chain names, no spaces.
    size_t p = 0;
    while (p <= v.size()) {
      size_t comma = v.find(',', p);
      std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
      if (!one.empty()) {
        col.chains.push_back(one);
      }
      if (comma == std::string::npos) {
        break;
      }
      p = comma + 1;
    }
  } else if (k == "tier") {
    col.tier = (int)phys_to_float(v);
    if (col.tier < 1) {
      col.tier = 1;
    }
  } else if (k == "side") {
    // A LETTER, case-insensitive, like the chain's own side=. Anything else stays 0 (none) — the
    // chain-side warning already tells the owner the letter set, no need for a second one here.
    if (v == "L" || v == "l") {
      col.side = 1;
    } else if (v == "R" || v == "r") {
      col.side = 2;
    }
  } else if (k == "at") {
    col.chainref = v;
  } else if (k == "offset") {
    // offset=x,y,z — centre de la geometrie du joint dans SON espace bind, en unites de jeu.
    // Trois nombres exactement ; toute autre forme laisse l'offset a zero et sera signalee par le
    // "unknown key" du dessus si la cle elle-meme est fausse.
    float xyz[3] = {0.f, 0.f, 0.f};
    size_t p = 0;
    int n = 0;
    while (p <= v.size() && n < 3) {
      size_t comma = v.find(',', p);
      std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
      if (!one.empty()) {
        xyz[n++] = phys_to_float(one);
      }
      if (comma == std::string::npos) {
        break;
      }
      p = comma + 1;
    }
    if (n == 3) {
      col.ox = xyz[0];
      col.oy = xyz[1];
      col.oz = xyz[2];
    } else {
      lg::warn("[hd-phys] collider {} offset= wants three numbers 'x,y,z' (got '{}', ignored)",
               col.joint, v);
    }
  } else {
    return false;
  }
  return true;
}

// Parse recharged_assets/physics_chains.txt. Missing file is NOT an error (0 models = feature inert).
// Returns the number of [model ...] sections parsed.
static int pc_physics_parse_file() {
  // Bumped unconditionally, including on the failure paths below: any (re)parse invalidates the
  // chain bindings the GOAL side cached from the previous contents.
  s_phys_generation++;
  // Whoever got here HAS loaded the store — including pc_set_physics's menu-driven re-read, which
  // runs before any ensure_loaded() the first time the owner touches the toggle. Setting the flag
  // here (rather than only in the two ensure/reload wrappers) keeps that path from being followed
  // by a second, redundant parse and a second generation bump.
  s_phys_loaded_once = true;
  s_phys_models.clear();
  s_phys_level_count = 0;
  for (int i = 0; i < kPhysMaxLevels; i++) {
    for (int j = 0; j < kPhysNumLevelParams; j++) {
      s_phys_levels[i][j] = 0.f;
    }
  }

  // OWNER TUNING PATH (2026-08-06): physics_chains.txt is data the owner retunes by hand. The
  // package copy inside the APK would otherwise win over the external pack (see
  // get_recharged_assets_dir), turning a stiffness tweak into a 581 MB re-download. An EXTERNAL
  // copy therefore OVERRIDES the packaged one, and the chosen source is logged so a device gate
  // can prove which file is live.
  const char* phys_src = "package";
  auto path = file_util::get_recharged_assets_dir() / "physics_chains.txt";
  auto ext_dir = file_util::get_external_recharged_assets_dir();
  if (ext_dir) {
    auto ext_path = *ext_dir / "physics_chains.txt";
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
      phys_src = "external-override";
    }
  }
  if (!file_util::file_exists(path.string())) {
    lg::info("[hd-phys] PARAMSRC=none path={} (physics inert)", path.string());
    return 0;
  }
  lg::info("[hd-phys] PARAMSRC={} path={}", phys_src, path.string());

  std::string text;
  try {
    text = file_util::read_text_file(path);
  } catch (...) {
    lg::warn("[hd-phys] could not read {}", path.string());
    return 0;
  }

  PhysModel* cur_model = nullptr;
  PhysChain* cur_chain = nullptr;
  bool in_levels = false;
  // physics_chains.txt is the shared HD tuning file: sections we do not own (Grecharged-hd-eye-scale
  // parses [eyescale] in EyeRenderer.cpp) are skipped whole instead of warning line by line.
  bool skip_section = false;
  bool warned_unknown = false;
  int n_chains = 0;
  int n_sections = 0;
  // One entry per parsed [model ...] section: the full list of names it declared. Resolved into
  // s_phys_models after the loop, once each section's contents are complete.
  std::vector<std::vector<std::string>> alias_groups;

  size_t pos = 0;
  while (pos <= text.size()) {
    size_t eol = text.find('\n', pos);
    std::string raw = text.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
    pos = (eol == std::string::npos) ? text.size() + 1 : eol + 1;

    // strip CR + trailing comment
    if (!raw.empty() && raw.back() == '\r') {
      raw.pop_back();
    }
    auto hash = raw.find('#');
    if (hash != std::string::npos) {
      raw = raw.substr(0, hash);
    }
    auto toks = phys_tokens(raw);
    if (toks.empty()) {
      continue;
    }

    // A foreign section header ends whatever we were parsing and mutes us until the next one we
    // own; a header we DO own always clears the mute, so section order in the file is free.
    if (!toks[0].empty() && toks[0][0] == '[' && toks[0] != "[levels]" && toks[0] != "[model") {
      in_levels = false;
      cur_model = nullptr;
      cur_chain = nullptr;
      skip_section = true;
      lg::info("[hd-phys] section {} is not ours (skipped)", toks[0]);
      continue;
    }
    if (!toks[0].empty() && toks[0][0] == '[') {
      skip_section = false;
    }
    if (skip_section) {
      continue;
    }

    if (toks[0] == "[levels]") {
      in_levels = true;
      cur_model = nullptr;
      cur_chain = nullptr;
      continue;
    }
    // A section header may declare SEVERAL names: `[model a b c]`. jak1 ships the same rig under
    // many art-group names (assistant, assistant-village2, assistant-firecanyon, ...), and
    // duplicating the whole block once per name is unmaintainable, so every listed name aliases
    // ONE PhysModel. The contents only exist once the section has been fully parsed, so the copy
    // to the extra names is deferred to after the parse loop (see alias_groups).
    if (toks[0] == "[model" && toks.size() >= 2) {
      std::vector<std::string> names;
      for (size_t t = 1; t < toks.size(); t++) {
        std::string name = toks[t];
        if (!name.empty() && name.back() == ']') {
          name.pop_back();
        }
        if (!name.empty()) {
          names.push_back(name);
        }
      }
      in_levels = false;
      cur_chain = nullptr;
      if (names.empty()) {
        lg::warn("[hd-phys] [model] section with no name (skipped)");
        cur_model = nullptr;
        continue;
      }
      cur_model = &s_phys_models[names[0]];
      n_sections++;
      if (names.size() > 1) {
        lg::info("[hd-phys] model {} aliased to {} more name(s)", names[0], names.size() - 1);
      }
      alias_groups.push_back(std::move(names));
      continue;
    }

    if (in_levels && toks[0] == "level" && toks.size() >= 2) {
      int idx = 0;
      try {
        idx = std::stoi(toks[1]);
      } catch (...) {
        idx = -1;
      }
      if (idx < 0 || idx >= kPhysMaxLevels) {
        lg::warn("[hd-phys] level index out of range: {}", raw);
        continue;
      }
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (k == "substeps") {
          s_phys_levels[idx][0] = phys_to_float(v);
        } else if (k == "iters") {
          s_phys_levels[idx][1] = phys_to_float(v);
        } else if (k == "collide") {
          s_phys_levels[idx][2] = phys_to_float(v);
        } else if (k == "classmask") {
          s_phys_levels[idx][3] = phys_to_float(v);
        } else if (k == "fixedhz") {
          s_phys_levels[idx][4] = phys_to_float(v);
        } else if (!warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      if (idx + 1 > s_phys_level_count) {
        s_phys_level_count = idx + 1;
      }
      continue;
    }

    if (toks[0] == "chain" && toks.size() >= 2) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'chain' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysChain ch;
      ch.name = toks[1];
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (k == "class") {
          if (v == "primary") {
            ch.class_bits = kPhysClassPrimary;
          } else if (v == "secondary") {
            ch.class_bits = kPhysClassSecondary;
          } else if (v == "accessory") {
            ch.class_bits = kPhysClassAccessory;
          } else {
            lg::warn("[hd-phys] unknown chain class '{}' (0 bits)", v);
          }
        } else if (k == "stiffness") {
          ch.params[0] = phys_to_float(v);
        } else if (k == "damping") {
          ch.params[1] = phys_to_float(v);
        } else if (k == "gravity") {
          ch.params[2] = phys_to_float(v);
        } else if (k == "maxangle") {
          ch.params[3] = phys_to_float(v);
        } else if (k == "inertia") {
          ch.params[4] = phys_to_float(v);
        } else if (k == "stretch") {
          ch.params[5] = phys_to_float(v);
        } else if (k == "radius") {
          ch.params[6] = phys_to_float(v);
        } else if (k == "rootlock") {
          ch.params[7] = phys_to_float(v);
        } else if (k == "gradient") {
          ch.params[8] = phys_to_float(v);
        } else if (k == "anim") {
          if (v == "keep") {
            ch.params[9] = 0.f;
          } else if (v == "replace") {
            ch.params[9] = 1.f;
          } else if (v == "excite") {
            ch.params[9] = 2.f;
          } else {
            lg::warn("[hd-phys] unknown chain anim mode '{}' (keeping replace)", v);
          }
        } else if (k == "excite") {
          ch.params[10] = phys_to_float(v);
        } else if (k == "friction") {
          ch.params[11] = phys_to_float(v);
        } else if (k == "authored") {
          ch.params[12] = phys_to_float(v);
        } else if (k == "authrise") {
          ch.params[13] = phys_to_float(v);
        } else if (k == "authfall") {
          ch.params[14] = phys_to_float(v);
        } else if (k == "authstiff") {
          ch.params[15] = phys_to_float(v);
        } else if (k == "rootfree") {
          ch.params[16] = phys_to_float(v);
        } else if (k == "nodesc") {
          ch.params[17] = phys_to_float(v);
        } else if (k == "colskip") {
          ch.params[18] = phys_to_float(v);
        } else if (k == "mass") {
          ch.params[19] = phys_to_float(v);
        } else if (k == "hang") {
          ch.params[20] = phys_to_float(v);
        } else if (k == "swing") {
          ch.params[21] = phys_to_float(v);
        } else if (k == "family") {
          // A LETTER, not a number, and case-insensitive: the data reads as a classification.
          if (v == "A" || v == "a") {
            ch.params[22] = 1.f;  // body: hair / chest / ears — returns to the model pose
          } else if (v == "B" || v == "b") {
            ch.params[22] = 2.f;  // hangs: straps / accessories / cloth — gravity rules its rest
          } else {
            // Its OWN warning, deliberately NOT gated by warned_unknown: a mistyped family is a
            // chain silently left UNCLASSIFIED, which is exactly what cycle 5 exists to catch.
            lg::warn("[hd-phys] chain '{}': family must be A or B, got '{}'", ch.name, v);
          }
        } else if (k == "side") {
          if (v == "L" || v == "l") {
            ch.params[23] = 1.f;
          } else if (v == "R" || v == "r") {
            ch.params[23] = 2.f;
          } else {
            lg::warn("[hd-phys] chain '{}': side must be L or R, got '{}'", ch.name, v);
          }
        } else if (k == "extent") {
          ch.params[24] = phys_to_float(v);
        } else if (k == "radii") {
          // Comma-separated, ONE PER LINK, root -> tip. A single whole-chain radius= is the same
          // number at a shoulder and at a fingertip, which is precisely how a mesh vertex ends up
          // outside its own collision volume; these come measured off the skinned geometry.
          // Cleared first so a repeated radii= on one line replaces rather than appends.
          ch.link_radius.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.link_radius.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "comw") {
          // Same shape as radii= : comma-separated, ONE PER LINK, root -> tip. Measured on the
          // SHIPPED mesh (.autoport/probe_c48_com_identity.py), never hand-tuned.
          ch.link_comw.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.link_comw.push_back(phys_to_float(one));
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "xchain") {
          // Comma-separated chain NAMES of this same model. Two chains have never been able to see
          // each other — which is why Jak's back buckle swings through his own strap — and naming
          // the partner here is what makes the pair collide.
          ch.xchains.clear();
          size_t p = 0;
          while (p <= v.size()) {
            size_t comma = v.find(',', p);
            std::string one = (comma == std::string::npos) ? v.substr(p) : v.substr(p, comma - p);
            if (!one.empty()) {
              ch.xchains.push_back(one);
            }
            if (comma == std::string::npos) {
              break;
            }
            p = comma + 1;
          }
        } else if (k == "inject") {
          ch.params[26] = phys_to_float(v);
        } else if (k == "couple") {
          ch.params[27] = phys_to_float(v);
        } else if (k == "shell") {
          // Inner radius of the sleeve this link wraps around a limb, in units. Written by the
          // generator only for links measured to be closed shells around a FOREIGN volume; a chain
          // that is not a sleeve carries no `shell=` at all, not `shell=0`.
          ch.params[28] = phys_to_float(v);
        } else if (k == "b0") {
          // SPEC 6's characteristic root-to-apex length of the FLESH, in units, measured on the
          // mesh — the yardstick SPEC 22 expresses its apex ceiling in. See the default above.
          ch.params[29] = phys_to_float(v);
        } else if (!warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->chains.push_back(ch);
      cur_chain = &cur_model->chains.back();
      n_chains++;
      continue;
    }

    // `pk <Key> <value>` — one preset line of SPEC-breast-softbody section 38, verbatim.
    // Kept as a NAME->value pair rather than a positional list: a positional list makes the key
    // order a convention living in two files at once, and it cannot express "this key has no
    // reader" — which is exactly the state the audit has to publish.
    if (toks[0] == "pk" && toks.size() >= 3) {
      if (!cur_chain) {
        lg::warn("[hd-phys] 'pk' with no current chain (skipped): {}", raw);
        continue;
      }
      cur_chain->pkey.push_back(toks[1]);
      cur_chain->pval.push_back(phys_to_float(toks[2]));
      continue;
    }

    if (toks[0] == "j" && toks.size() >= 2) {
      if (!cur_chain) {
        lg::warn("[hd-phys] 'j' with no current chain (skipped): {}", raw);
        continue;
      }
      cur_chain->joints.push_back(toks[1]);
      continue;
    }

    if (toks[0] == "collider" && toks.size() >= 2) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'collider' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysCollider col;
      col.joint = toks[1];
      for (size_t t = 2; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (!phys_collider_kv(col, k, v) && !warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->colliders.push_back(col);
      continue;
    }

    // `capsule <jointA> <jointB> radius=R [chains=a,b] [tier=N]` — a swept-sphere body volume that
    // follows two animated bones. Same filter/tier semantics as `collider`.
    if (toks[0] == "capsule" && toks.size() >= 3) {
      if (!cur_model) {
        lg::warn("[hd-phys] 'capsule' outside a [model ...] section (skipped): {}", raw);
        continue;
      }
      PhysCollider col;
      col.joint = toks[1];
      col.joint2 = toks[2];
      for (size_t t = 3; t < toks.size(); t++) {
        std::string k, v;
        if (!phys_kv(toks[t], k, v)) {
          continue;
        }
        if (!phys_collider_kv(col, k, v) && !warned_unknown) {
          warned_unknown = true;
          lg::warn("[hd-phys] unknown key '{}' in physics_chains.txt (skipped)", k);
        }
      }
      cur_model->colliders.push_back(col);
      continue;
    }

    if (!warned_unknown) {
      warned_unknown = true;
      lg::warn("[hd-phys] unknown line in physics_chains.txt (skipped): {}", raw);
    }
  }

  // Publish the variant aliases: every extra name of a section gets a copy of the first name's
  // fully-parsed PhysModel. std::map references are stable, but the source is copied out first so
  // the inserts below cannot be read as self-assignment.
  for (const auto& group : alias_groups) {
    if (group.size() < 2) {
      continue;
    }
    const PhysModel src = s_phys_models[group[0]];
    for (size_t i = 1; i < group.size(); i++) {
      s_phys_models[group[i]] = src;
    }
  }

  // ---- (C14) physics_mesh.txt: per-link extremal skinned-vertex offsets ------------------------
  // Parsed AFTER the alias publication so a `model` line can name any alias and still land, and
  // applied to EVERY name it lists (aliases are value copies by then, not references). Derived
  // data, same external-override precedence as the tuning file: a re-derivation the owner pulls
  // down is a few hundred KB, never an APK.
  {
    const char* mesh_src = "package";
    auto mesh_path = file_util::get_recharged_assets_dir() / "physics_mesh.txt";
    if (ext_dir) {
      auto ext_mesh = *ext_dir / "physics_mesh.txt";
      if (file_util::file_exists(ext_mesh.string())) {
        mesh_path = ext_mesh;
        mesh_src = "external-override";
      }
    }
    if (!file_util::file_exists(mesh_path.string())) {
      // Not an error: without samples the mesh audit reports meshtested=0, which the device gate
      // reads as "not measured" — never as a clean zero. That is the honest failure mode.
      lg::info("[hd-phys] MESHSRC=none path={} (mesh audit unarmed)", mesh_path.string());
    } else {
      std::string mtext;
      try {
        mtext = file_util::read_text_file(mesh_path);
      } catch (...) {
        mtext.clear();
        lg::warn("[hd-phys] could not read {}", mesh_path.string());
      }
      std::vector<std::string> cur_names;
      int n_ms = 0, n_ms_dropped = 0;
      int n_ax = 0, n_ax_dropped = 0;
      int n_bs = 0, n_bs_dropped = 0;
      size_t mpos = 0;
      while (mpos <= mtext.size()) {
        size_t eol = mtext.find('\n', mpos);
        std::string raw =
            mtext.substr(mpos, eol == std::string::npos ? std::string::npos : eol - mpos);
        mpos = (eol == std::string::npos) ? mtext.size() + 1 : eol + 1;
        if (!raw.empty() && raw.back() == '\r') {
          raw.pop_back();
        }
        auto hash = raw.find('#');
        if (hash != std::string::npos) {
          raw = raw.substr(0, hash);
        }
        auto toks = phys_tokens(raw);
        if (toks.empty()) {
          continue;
        }
        if (toks[0] == "model") {
          cur_names.assign(toks.begin() + 1, toks.end());
          continue;
        }
        // ms <chainName> <linkIdx> <n> x y z [* n]
        if (toks[0] == "ms" && toks.size() >= 4) {
          const std::string& cname = toks[1];
          int link = atoi(toks[2].c_str());
          int n = atoi(toks[3].c_str());
          if (n < 0 || n > 5 || (int)toks.size() < 4 + 3 * n) {
            n_ms_dropped++;
            continue;
          }
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            for (auto& ch : mit->second.chains) {
              if (ch.name != cname) {
                continue;
              }
              if (link < 0 || link >= (int)ch.joints.size()) {
                n_ms_dropped++;
                break;
              }
              if (ch.mesh_samples.size() < ch.joints.size()) {
                ch.mesh_samples.resize(ch.joints.size());
              }
              auto& dst = ch.mesh_samples[link];
              dst.clear();
              for (int s = 0; s < n; s++) {
                dst.push_back({(float)atof(toks[4 + 3 * s].c_str()),
                               (float)atof(toks[5 + 3 * s].c_str()),
                               (float)atof(toks[6 + 3 * s].c_str())});
              }
              n_ms++;
              break;
            }
          }
          continue;
        }
        // (C51) ax <chainName> <linkIdx> <w> <x> <y> <z> — the APEX region representative for
        // this link. One record per link; a link with no record keeps w = 0 and contributes
        // nothing, which is the same "missing weight never reads as zero motion" rule comw= uses.
        if (toks[0] == "ax" && toks.size() >= 7) {
          const std::string& cname = toks[1];
          int link = atoi(toks[2].c_str());
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            for (auto& ch : mit->second.chains) {
              if (ch.name != cname) {
                continue;
              }
              if (link < 0 || link >= (int)ch.joints.size()) {
                n_ax_dropped++;
                break;
              }
              if (ch.link_apexw.size() < ch.joints.size()) {
                ch.link_apexw.resize(ch.joints.size(), 0.f);
                ch.link_apexp.resize(ch.joints.size(), {0.f, 0.f, 0.f});
              }
              ch.link_apexw[link] = (float)atof(toks[3].c_str());
              ch.link_apexp[link] = {(float)atof(toks[4].c_str()),
                                     (float)atof(toks[5].c_str()),
                                     (float)atof(toks[6].c_str())};
              n_ax++;
              break;
            }
          }
          continue;
        }
        // (SPEC 18) bs <boneName> <n> x y z nx ny nz [* n] — per BODY bone, the skinned SURFACE
        // the chains are collided against, bone-local bind space, game units. Sits inside the same
        // `model` sections as the ms lines above, after them, and lands on every name that section
        // declares (aliases are value copies by now, exactly as for ms).
        if (toks[0] == "bs" && toks.size() >= 3) {
          const std::string& bname = toks[1];
          int n = atoi(toks[2].c_str());
          // Same malformed-line tolerance as the ms parser: a negative count or a line too short
          // for the count it declares is DROPPED and counted, never warned per line. Widened to
          // 64-bit only so a garbage count in a file the owner can edit on device cannot overflow
          // the comparison itself; there is no invented upper cap on n — the token count is the
          // cap, so the allocation below is bounded by the length of the line.
          if (n < 0 || (s64)toks.size() < (s64)3 + 6ll * (s64)n) {
            n_bs_dropped++;
            continue;
          }
          for (const auto& mn : cur_names) {
            auto mit = s_phys_models.find(mn);
            if (mit == s_phys_models.end()) {
              continue;
            }
            auto& pm = mit->second;
            std::vector<std::array<float, 6>> set;
            set.reserve((size_t)n);
            for (int s = 0; s < n; s++) {
              set.push_back({(float)atof(toks[3 + 6 * s].c_str()),
                             (float)atof(toks[4 + 6 * s].c_str()),
                             (float)atof(toks[5 + 6 * s].c_str()),
                             (float)atof(toks[6 + 6 * s].c_str()),
                             (float)atof(toks[7 + 6 * s].c_str()),
                             (float)atof(toks[8 + 6 * s].c_str())});
            }
            // Pushed in lockstep so bsurf_joint[i] always describes bsurf[i].
            pm.bsurf_joint.push_back(bname);
            pm.bsurf.push_back(std::move(set));
            n_bs++;
          }
          continue;
        }
      }
      lg::info("[hd-phys] MESHSRC={} path={} links-with-samples={} dropped={}"
               " apex-links={} apex-dropped={}",
               mesh_src, mesh_path.string(), n_ms, n_ms_dropped, n_ax, n_ax_dropped);
      // Separate line, once per parse, and INFO even at zero: a pack predating the `bs` records
      // is a legacy pack, not an error, and it must not warn-spam. sets=0 is the honest report
      // that the body surface was never delivered — the GOAL side counts that as "not measured".
      lg::info("[hd-phys] BSURFSRC={} bsets={} dropped={}", mesh_src, n_bs, n_bs_dropped);
    }
  }

  lg::info("[hd-phys] params loaded: {} models, {} chains", (int)s_phys_models.size(), n_chains);
  return n_sections;
}

// Lazy first-parse so there is no init-order dependency on the assets dir being resolved.
static void pc_physics_ensure_loaded() {
  if (!s_phys_loaded_once) {
    s_phys_loaded_once = true;
    pc_physics_parse_file();
  }
}

static const PhysModel* pc_physics_find_model(u32 ag_name) {
  std::string name = Ptr<String>(ag_name).c()->data();
  auto it = s_phys_models.find(name);
  return (it == s_phys_models.end()) ? nullptr : &it->second;
}

static s64 phys_mi(float v) {
  return (s64)llround((double)v * 1000.0);
}

// (Re)parse the params file. Hot-editable: adb push a new physics_chains.txt + call this.
s64 pc_physics_reload() {
  s_phys_loaded_once = true;
  return (s64)pc_physics_parse_file();
}

s64 pc_physics_generation() {
  pc_physics_ensure_loaded();
  return s_phys_generation;
}

// (chain_index << 8) | link_index for a joint's place in its model's chains; -1 if not a chain joint.
s64 pc_physics_joint_role(u32 ag_name, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model) {
    return -1;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  for (size_t ci = 0; ci < model->chains.size(); ci++) {
    const auto& ch = model->chains[ci];
    for (size_t li = 0; li < ch.joints.size(); li++) {
      if (ch.joints[li] == joint) {
        return (s64)((ci << 8) | li);
      }
    }
  }
  return -1;
}

// milli chain param. unknown model/chain/param -> 0.
s64 pc_physics_chain_param_mi(u32 ag_name, s64 chain_index, s64 param_id) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain_index < 0 || chain_index >= (s64)model->chains.size()) {
    return 0;
  }
  if (param_id < 0 || param_id >= kPhysNumChainParams) {
    return 0;
  }
  return phys_mi(model->chains[chain_index].params[param_id]);
}

// per-LINK collision radius in milli; 0 when this chain declares no radii= (GOAL then falls back
// to the whole-chain radius=), so a data file without the key behaves exactly as before.
s64 pc_physics_chain_link_radius_mi(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& radii = model->chains[chain].link_radius;
  if (link < 0 || link >= (s64)radii.size()) {
    return 0;
  }
  return phys_mi(radii[link]);
}

// per-LINK share of the organ's skin mass in milli; 0 when this chain declares no comw= (GOAL then
// publishes no COM excursion at all — a missing weight can never read as a COM of zero).
s64 pc_physics_chain_link_comw_mi(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& comw = model->chains[chain].link_comw;
  if (link < 0 || link >= (s64)comw.size()) {
    return 0;
  }
  return phys_mi(comw[link]);
}

// ---- the character PRESET, read as a CHANNEL (2026-08-22) -------------------------------------
// These are the preset keys the engine actually CONSUMES, in the order GOAL indexes them. The
// table lives here and not in GOAL so that "wired" is a property of one list: a key absent from
// this array has NO channel, and `pc_physics_chain_preset_absent` counts exactly those keys the
// delivered file carries and this list does not name. That count is what the report publishes as
// CANAL ABSENT — a named implementation gap, never a section reported as "not held".
static const char* kPhysPresetKeys[] = {
    "SupineProjectionScale",   // 0  section 10 — projection lost against the thorax, lying face-up
    "SupineWidthScale",        // 1  section 10
    "SupineHeightScale",       // 2  section 10
    "HangingLengthScale",      // 3  section 11 — torso horizontal, breast hanging free
    "HangingWidthScale",       // 4  section 11
    "HangingThicknessScale",   // 5  section 11
    "LowerBreastCompression",  // 6  section 12 — side gravity, lower breast squashed
    "SecondaryFrequency",      // 7  section 36 — secondary soft-tissue mode
    "SecondaryDampingRatio",   // 8  section 36
    "SecondaryJiggleHardMax",  // 9  section 36
    "APCompliance",            // 10 section 29 — anisotropie avant/arriere
    "LateralCompliance",       // 11 section 29
    "TorsionalCompliance",     // 12 section 29
    "AbsoluteStretchClamp",    // 13 section 22 — plafond dur d'elongation locale
    "BreastBreastRestitution", // 14 section 33
    "BreastChestRestitution",  // 15 section 34
    "NormalMaxApexDisplacement",  // 16 section 22 — le GENOU de la borne d'apex
    "DerivedApexSoftBand",        // 17 = HardMaxApex - NormalMaxApex, calcule par preset_apply.py
    "NormalMaxCOMDisplacement",   // 18 section 22 — le genou de la borne de COM
    "DerivedCOMSoftBand",         // 19 = HardMaxCOM - NormalMaxCOM, calcule par preset_apply.py
    "HardMaxCOMDisplacement",     // 20 section 22 — le plafond du canal radial
    "DerivedSupineProjectionYield",  // 21 = 1 - SupineProjectionScale ; la SECONDE copie de la
                                     //    cle 0, celle de `phys-vol-floor`. Une cle lue a un
                                     //    endroit et gardee en dur a l'autre rend une reponse
                                     //    partielle qu'on lit comme complete.
    "HardMaxApexDisplacement",       // 22 section 22 — le PLAFOND DUR de l'apex. Le cycle 109b
                                     //    l'a classee « CANAL ABSENT, aucun lecteur » alors que
                                     //    DEUX sites du moteur la portaient en dur (0.50 B0 dans
                                     //    `phys-apex-scale` et dans le plafond de torsion de la
                                     //    38), et que la NOTE-160 le DISAIT. L'audit cherchait le
                                     //    SITE au lieu de la VALEUR : il ne pouvait pas la voir.
    "VerticalCompliance",            // 23 section 29 — la TROISIEME ligne du tenseur d'anisotropie.
                                     //    Ses deux soeurs (10, 11) lisaient le fichier et elle
                                     //    restait le litteral `1.0`, entre les deux. Inerte sur
                                     //    les deux presets (1.00 partout) : c'est un bouton, pas
                                     //    un changement de comportement.
    "HardImpactSubstepsHi",          // 24 section 37 — sous-pas sur impact (4)
    "MinimumSubstepsAt60FPS",        // 25 section 37 — sous-pas nominal (2). `HardImpactSubstepsLo`
                                     //    (3) n'a AUCUN site : le moteur ne choisit qu'entre 4 et
                                     //    2, donc ce barreau de sa spec reste CANAL ABSENT et on
                                     //    le dit au lieu de l'arrondir.
};
static const int kPhysNumPresetKeys = (int)(sizeof(kPhysPresetKeys) / sizeof(kPhysPresetKeys[0]));

// milli value of wired preset key `key_id` for this chain, or -1 when the delivered file does not
// carry that key. -1 and not 0: `AdditionalStandingSag = 0.00` is a legitimate preset value, so a
// zero can never be allowed to mean "absent". GOAL turns -1 into the neutral element AND counts
// it, so a missing channel shows up in the trace instead of quietly restoring an old constant.
s64 pc_physics_chain_preset_mi(u32 ag_name, s64 chain, s64 key_id) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return -1;
  }
  if (key_id < 0 || key_id >= (s64)kPhysNumPresetKeys) {
    return -1;
  }
  const auto& ch = model->chains[chain];
  for (size_t i = 0; i < ch.pkey.size(); i++) {
    if (ch.pkey[i] == kPhysPresetKeys[key_id]) {
      return phys_mi(ch.pval[i]);
    }
  }
  return -1;
}

// how many `pk` keys this chain carries in the delivered file (the preset's own size).
s64 pc_physics_chain_preset_count(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  return (s64)model->chains[chain].pkey.size();
}

// how many of those keys have NO reader in this engine — the CANAL ABSENT count, measured on the
// delivered file rather than asserted in a report.
s64 pc_physics_chain_preset_absent(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ch = model->chains[chain];
  s64 n = 0;
  for (size_t i = 0; i < ch.pkey.size(); i++) {
    bool wired = false;
    for (int k = 0; k < kPhysNumPresetKeys; k++) {
      if (ch.pkey[i] == kPhysPresetKeys[k]) {
        wired = true;
        break;
      }
    }
    if (!wired) {
      n++;
    }
  }
  return n;
}

// (C51) the APEX region representative for one link, in milli. `axis` selects: 0 = w, the share
// of the distal region's skin mass this link carries; 1/2/3 = x/y/z of that region's centroid in
// this link's bone-local bind space, game units. 0 when this chain declares no ax= record — GOAL
// then publishes no apex at all, exactly as comw= does for the COM.
s64 pc_physics_chain_link_apex_mi(u32 ag_name, s64 chain, s64 link, s64 axis) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& aw = model->chains[chain].link_apexw;
  if (link < 0 || link >= (s64)aw.size()) {
    return 0;
  }
  if (axis == 0) {
    return phys_mi(aw[link]);
  }
  if (axis < 1 || axis > 3) {
    return 0;
  }
  return phys_mi(model->chains[chain].link_apexp[link][axis - 1]);
}

// (C14) how many mesh samples this link carries (0..5). 0 = the mesh never reaches beyond the
// link's own radius test, or physics_mesh.txt is absent — either way the GOAL side counts that
// link out of meshtested=, so a missing file can never read as a clean mesh audit.
s64 pc_physics_chain_msample_count(u32 ag_name, s64 chain, s64 link) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ms = model->chains[chain].mesh_samples;
  if (link < 0 || link >= (s64)ms.size()) {
    return 0;
  }
  return (s64)ms[link].size();
}

// (C14) one coordinate of one mesh sample, milli game units, bone-local bind space.
// link_si packs (link << 3) | sample_index; coord 0/1/2 = x/y/z. Packed because the GOAL FFI here
// carries at most four parameters, same convention as pc-physics-joint-role's (chain<<8)|link.
s64 pc_physics_chain_msample_mi(u32 ag_name, s64 chain, s64 link_si, s64 coord) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  const auto& ms = model->chains[chain].mesh_samples;
  s64 link = link_si >> 3;
  s64 si = link_si & 7;
  if (link < 0 || link >= (s64)ms.size() || si >= (s64)ms[link].size() || coord < 0 || coord > 2) {
    return 0;
  }
  return phys_mi(ms[link][si][(size_t)coord]);
}

// bitmask of the chain indices named by xchain=, resolved in this same model — the identical
// lookup pc_physics_collider_param_mi field 1 does for chains=. 0 = no chain-vs-chain partner,
// which is every pre-cycle-6 line, so silence in the data keeps the old behaviour.
s64 pc_physics_chain_xmask(u32 ag_name, s64 chain) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain < 0 || chain >= (s64)model->chains.size()) {
    return 0;
  }
  s64 mask = 0;
  for (const auto& want : model->chains[chain].xchains) {
    bool found = false;
    for (size_t ci = 0; ci < model->chains.size(); ci++) {
      if (model->chains[ci].name == want) {
        mask |= ((s64)1 << (s64)ci);
        found = true;
      }
    }
    if (!found) {
      // Once per (art-group, unresolved name): the sim reads this every frame, and an xchain= that
      // resolves to nothing is a PAIR THAT NEVER COLLIDES — a data typo the owner must see, but
      // once per typo, not once per frame.
      static std::set<std::string> s_warned_xchain;
      std::string ag = Ptr<String>(ag_name).c()->data();
      if (s_warned_xchain.insert(ag + "|" + want).second) {
        lg::warn("[hd-phys] {}: chain xchain= references unknown chain '{}' (ignored)", ag, want);
      }
    }
  }
  return mask;
}

// class bits (primary=1 secondary=2 accessory=4); 0 if unknown.
s64 pc_physics_chain_flags(u32 ag_name, s64 chain_index) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || chain_index < 0 || chain_index >= (s64)model->chains.size()) {
    return 0;
  }
  return (s64)model->chains[chain_index].class_bits;
}

s64 pc_physics_num_chains(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->chains.size() : 0;
}

// Level params, EVERYTHING milli (substeps/iters/collide/classmask included — the caller divides by
// 1000 uniformly). Level is clamped to the configured range.
s64 pc_physics_level_param_mi(s64 level, s64 param_id) {
  pc_physics_ensure_loaded();
  if (s_phys_level_count <= 0) {
    return 0;
  }
  if (param_id < 0 || param_id >= kPhysNumLevelParams) {
    return 0;
  }
  s64 lv = level;
  if (lv < 0) {
    lv = 0;
  }
  if (lv > s_phys_level_count - 1) {
    lv = s_phys_level_count - 1;
  }
  return phys_mi(s_phys_levels[lv][param_id]);
}

// milli collider radius attached to a named joint; 0 = no collider there.
// LEGACY accessor: only sees filterless (applies-to-all) colliders, first match wins.
s64 pc_physics_joint_collider_mi(u32 ag_name, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  for (const auto& col : model->colliders) {
    if (col.joint == joint && col.chains.empty()) {
      return phys_mi(col.radius);
    }
  }
  return 0;
}

// number of colliders declared for the model; 0 if the model is unknown.
s64 pc_physics_num_colliders(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->colliders.size() : 0;
}

// field 0 = radius in milli. field 1 = chain-applicability bitmask, RAW (not milli): bit c set if
// this collider applies to chain index c. An empty chains= filter -> -1 (all chains).
// field 2 = tier, RAW (1 = core, 2 = extended). field 3 = shape, RAW: 1 if this is a CAPSULE
// (joint2 set), 0 if it is a plain sphere. field 4 = FAR-END radius in milli for a TAPERED capsule
// (cycle 3, owner C: flared trousers / shoulders); falls back to `radius` when radius2 is unset, so
// every existing line keeps its cylinder shape.
// field 5 = side=, RAW (0 none, 1 L, 2 R) — cross-side penetration accounting.
// field 6 = the at= chain, RESOLVED to a 0-based chain index of this same model (the identical
// lookup field 1 does for chains=): the sphere is then centred on that chain's SIMULATED TIP rather
// than on a bone. -1 when no at= was declared, and -1 (plus a one-shot warning naming the
// art-group and the unresolved name) when at= names a chain this model does not have.
s64 pc_physics_collider_param_mi(u32 ag_name, s64 idx, s64 field) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  const auto& col = model->colliders[idx];
  if (field == 0) {
    return phys_mi(col.radius);
  }
  if (field == 1) {
    if (col.chains.empty()) {
      return -1;
    }
    s64 mask = 0;
    for (const auto& want : col.chains) {
      bool found = false;
      for (size_t ci = 0; ci < model->chains.size(); ci++) {
        if (model->chains[ci].name == want) {
          mask |= ((s64)1 << (s64)ci);
          found = true;
        }
      }
      if (!found) {
        lg::warn("[hd-phys] collider {} chains= references unknown chain '{}' (ignored)", col.joint,
                 want);
      }
    }
    if (mask == 0) {
      lg::warn("[hd-phys] collider {} chains= resolved to zero chains (collider inert)", col.joint);
    }
    return mask;
  }
  if (field == 2) {
    return (s64)col.tier;
  }
  if (field == 4) {
    return phys_mi(col.radius2 > 0.f ? col.radius2 : col.radius);
  }
  if (field == 3) {
    return col.joint2.empty() ? 0 : 1;
  }
  if (field == 5) {
    return (s64)col.side;
  }
  if (field == 6) {
    if (col.chainref.empty()) {
      return -1;
    }
    for (size_t ci = 0; ci < model->chains.size(); ci++) {
      if (model->chains[ci].name == col.chainref) {
        return (s64)ci;
      }
    }
    // Once per (art-group, unresolved name): this is read every frame by the sim, and an
    // unresolvable at= is a data typo the owner must SEE — but only once per typo, not per frame.
    static std::set<std::string> s_warned_chainref;
    std::string ag = Ptr<String>(ag_name).c()->data();
    if (s_warned_chainref.insert(ag + "|" + col.chainref).second) {
      lg::warn("[hd-phys] {}: collider at= references unknown chain '{}' (no attach)", ag,
               col.chainref);
    }
    return -1;
  }
  // 7/8/9 — le CENTRE de la sphere dans l'espace bind de son joint (offset=), en milli-unites
  // comme tout ce qui traverse la frontiere. Zero = centre sur le joint, l'ancien comportement.
  if (field == 7) {
    return phys_mi(col.ox);
  }
  if (field == 8) {
    return phys_mi(col.oy);
  }
  if (field == 9) {
    return phys_mi(col.oz);
  }
  return 0;
}

// 1 if collider idx of the model sits on joint_name (exact match), else 0.
s64 pc_physics_collider_is_joint(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->colliders[idx].joint == joint ? 1 : 0;
}

// 1 if collider idx of the model is a CAPSULE whose second joint is joint_name (exact match),
// else 0 (a plain sphere has no joint2 and always answers 0).
s64 pc_physics_collider_is_joint2(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->colliders.size()) {
    return 0;
  }
  if (model->colliders[idx].joint2.empty()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->colliders[idx].joint2 == joint ? 1 : 0;
}

// ---- (SPEC 18) body SURFACE sets: the real skinned surface, not a proxy volume ----------------
// Same milli convention as everything else on this boundary: no float ever crosses it (the
// float-return-register trap on this port), so positions AND normals come back as x1000 ints.
// Every index is bounds-checked and answers 0 out of range: these are read from a hot GOAL loop
// with indices derived from a file the owner can edit on device.

// number of body-surface sets for this art-group; 0 if none/unknown (a legacy physics_mesh.txt
// with no `bs` records answers 0 here, and the audit reads that as "not measured").
s64 pc_physics_num_bsurf(u32 ag_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  return model ? (s64)model->bsurf.size() : 0;
}

// 1 if body-surface set idx sits on joint_name (exact match, same comparison
// pc_physics_collider_is_joint makes), else 0.
s64 pc_physics_bsurf_is_joint(u32 ag_name, s64 idx, u32 joint_name) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf_joint.size()) {
    return 0;
  }
  std::string joint = Ptr<String>(joint_name).c()->data();
  return model->bsurf_joint[idx] == joint ? 1 : 0;
}

// how many surface samples set idx carries; 0 if the set index is out of range.
s64 pc_physics_bsurf_count(u32 ag_name, s64 idx) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf.size()) {
    return 0;
  }
  return (s64)model->bsurf[idx].size();
}

// component `comp` of sample `s` of set `idx`, MILLI-units: comp 0..2 = position xyz,
// comp 3..5 = outward normal xyz. 0 if any index is out of range.
s64 pc_physics_bsurf_mi(u32 ag_name, s64 idx, s64 s, s64 comp) {
  pc_physics_ensure_loaded();
  const auto* model = pc_physics_find_model(ag_name);
  if (!model || idx < 0 || idx >= (s64)model->bsurf.size()) {
    return 0;
  }
  const auto& set = model->bsurf[idx];
  if (s < 0 || s >= (s64)set.size() || comp < 0 || comp > 5) {
    return 0;
  }
  return phys_mi(set[s][(size_t)comp]);
}

// 0 = off (toggle off, or no params loaded); else level + 1.
s64 pc_physics_enabled() {
  pc_physics_ensure_loaded();
  if (!s_physics_on || s_phys_models.empty()) {
    return 0;
  }
  return (s64)(s_physics_level + 1);
}
#endif

// Gpbrf owner workflow (2026-07-24): POSITION DUMP for deterministic weld-ON/OFF daytime A/B.
// The owner stands on a seam; the supervisor must read his EXACT world position to warp there for
// A/B captures. The Honor obscures logcat (HKS encryption), so lg::info is unreadable there =>
// write to a FILE instead. On debug.opengoal.dump.pos = "1" (Android) / env OG_DUMP_POS (desktop),
// write Jak's CURRENT world position as "X Y Z" IN METERS (÷4096 — the exact units
// debug.opengoal.level.warp.pos consumes, so the string is directly pasteable) to
// files/pos_dump.txt in the app files dir. Pull it with:
//   run-as org.opengoal.gk.jak1 cat files/pos_dump.txt
// pc_set_jak_pos runs every logic frame while *target* exists, so throttle the disk write to ~4 Hz.
static void maybe_dump_jak_pos(float gx, float gy, float gz) {
  bool enabled = false;
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.dump.pos", buf) > 0 && buf[0] && buf[0] != '0') {
    enabled = true;
  }
#else
  if (const char* e = std::getenv("OG_DUMP_POS")) {
    enabled = (e[0] && e[0] != '0');
  }
#endif
  if (!enabled) {
    return;
  }
  static std::chrono::steady_clock::time_point s_last{};
  auto now = std::chrono::steady_clock::now();
  if (s_last.time_since_epoch().count() != 0 &&
      std::chrono::duration_cast<std::chrono::milliseconds>(now - s_last).count() < 250) {
    return;
  }
  s_last = now;
  const float mx = gx / 4096.f, my = gy / 4096.f, mz = gz / 4096.f;
  try {
    // Line 1 = the bare "X Y Z" meters (directly pasteable into debug.opengoal.level.warp.pos).
    // Line 2 = a human comment (level.warp.pos' sscanf reads only the first %f %f %f, so the
    // comment is harmless). Raw GOAL units kept for cross-checking against the warp patch.
    std::string body = fmt::format("{:.2f} {:.2f} {:.2f}\n; jak world pos (meters, level.warp.pos units); raw goal=({:.0f} {:.0f} {:.0f})\n",
                                   mx, my, mz, gx, gy, gz);
    file_util::write_text_file(file_util::get_jak_project_dir() / "pos_dump.txt", body);
  } catch (...) {
    // best-effort debug channel; never let a file error affect the game loop
  }
}

// Grecharged-grass-poc: push Jak's world position (a GOAL vector, xyzw) each frame
// so the grass renderer can flatten blades where the player walks. w := 1.0 marks
// the value valid (GOAL only calls this while *target* exists).
void pc_set_jak_pos(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  Gfx::g_global_settings.recharged_jak_pos[0] = p[0];
  Gfx::g_global_settings.recharged_jak_pos[1] = p[1];
  Gfx::g_global_settings.recharged_jak_pos[2] = p[2];
  Gfx::g_global_settings.recharged_jak_pos[3] = 1.0f;
  maybe_dump_jak_pos(p[0], p[1], p[2]);  // Gpbrf owner workflow: gated pos_dump.txt for A/B warps
}

// Grecharged-grass-poc POLISH#4/#5: push the adjustable grass view distances + density (a GOAL
// vector, x = near-blade fade-out (m), y = grass-card fade-out (m), z = density percent (100 = base)).
void pc_set_grass_dists(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  Gfx::g_global_settings.recharged_grass_near_dist = p[0];
  Gfx::g_global_settings.recharged_grass_card_dist = p[1];
  Gfx::g_global_settings.recharged_grass_density = p[2];  // POLISH#5 density slider
  // Grecharged-grass-precompute-mode: w channel = GRASS MODE toggle (1.0 = PRECOMPUTED baked
  // day-cycle tables / 0.0 = LIVE full at-load scan). GOAL now writes w in the scratch vector.
  Gfx::g_global_settings.recharged_grass_precomputed = p[3] > 0.5f;
}

// Grecharged-grass-precompute-mode verification aid: fixed time-of-day for A/B captures.
// Android: prop debug.opengoal.tod.hour ("9.5" = 09:30). Desktop: env GRASS_TOD. Returns
// hour*100 as int (950), or -1 when unset/invalid. Read at most once per second.
u64 pc_get_tod_hour() {
  static s64 s_cached = -1;
  static std::chrono::steady_clock::time_point s_last{};
  auto now = std::chrono::steady_clock::now();
  if (s_last.time_since_epoch().count() != 0 &&
      std::chrono::duration_cast<std::chrono::milliseconds>(now - s_last).count() < 1000) {
    return (u64)s_cached;
  }
  s_last = now;
  const char* val = nullptr;
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.tod.hour", buf) > 0 && buf[0]) {
    val = buf;
  }
#else
  val = std::getenv("GRASS_TOD");
#endif
  if (val && val[0]) {
    double h = std::atof(val);
    if (h >= 0.0 && h < 24.0) {
      s_cached = (s64)(h * 100.0);
    } else {
      s_cached = -1;
    }
  } else {
    s_cached = -1;
  }
  return (u64)s_cached;
}

// Grecharged-hd-models: 1 if the build carries the enhanced HD-model FR3 set (fr3/enhanced/GAME.fr3
// present), else 0. Drives the ENHANCED MODELS menu-row visibility so the toggle only appears when
// jak2 assets were available at build time. Works on x86 and Android (get_fr3_dir already resolves the
// unpacked external asset root on device).
#ifdef OG_FEAT_HD_MODELS
u64 pc_get_enhanced_models_available() {
  auto p = file_util::get_fr3_dir(GameVersion::Jak1) / "enhanced" / "GAME.fr3";
  return file_util::file_exists(p.string()) ? 1 : 0;
}
#endif

// Grecharged-grass-poc ROUND#21d: ground-actor positions from GOAL (the pc-set-jak-pos! pattern —
// exact world coords from each actor's root trans; the Merc2 camera-space recovery is dead). The pc
// glue calls clear!, then add! per actor, then publish! every ~30 frames. kind: 0 = CULL (static
// unbreakable: warp-gate button, eco vent, speaker), 1 = TRAMPLE (breakable: crates, scarecrows — a
// broken crate stops being pushed, so the renderer's eased spring-back plays). The radius arrives as
// a GOAL-units integer (meters * 4096) because GOAL passes args in GPRs (no float ABI).
void pc_grass_occ_clear() {
  grass_occ::goal_clear();
}
void pc_grass_occ_add(u32 kind, u32 vec, u32 r_units) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  grass_occ::goal_add((int)kind, p[0], p[1], p[2], (float)r_units);
}
void pc_grass_occ_publish() {
  grass_occ::goal_publish();
}

// R28: called from the scarecrow break path at the exact clear-collide frame — instantly cancels the
// trample at that spot (ghost erased + 8 s tombstone). No-op when grass is off (empty ghost lists).
void pc_grass_tramp_break(u32 vec) {
  if (!vec) {
    return;
  }
  float* p = Ptr<float>(vec).c();
  grass_occ::goal_break_at(p[0], p[1], p[2]);
}

// Grecharged-grass-poc POLISH#4: push Jak's ledge-grab point (a GOAL vector, xyz) while he hangs on
// a ledge, so the grass on that ledge parts around his hands. GOAL passes a null vector (0) to clear
// it the moment he lets go, so a stale grab point never keeps parting the grass.
void pc_set_jak_ledge(u32 vec) {
  if (!vec) {
    Gfx::g_global_settings.recharged_jak_ledge[3] = 0.0f;
    return;
  }
  float* p = Ptr<float>(vec).c();
  Gfx::g_global_settings.recharged_jak_ledge[0] = p[0];
  Gfx::g_global_settings.recharged_jak_ledge[1] = p[1];
  Gfx::g_global_settings.recharged_jak_ledge[2] = p[2];
  Gfx::g_global_settings.recharged_jak_ledge[3] = 1.0f;
}

// Grecharged-materials-modern-parity: MODERN MATERIALS master pushed from GOAL every frame
// (menu row "MODERN MATERIALS", Recharged Settings, default OFF == stock).
void pc_set_modern_materials(u32 sym) {
#ifdef OG_FEAT_PBR
  const bool on = (sym != 0);
  const bool changed = (Gfx::g_global_settings.recharged_modern_materials != on);
  Gfx::g_global_settings.recharged_modern_materials = on;
  if (changed) {
    // Same idiom as pc_set_physics: flipping the row RE-READS the tuning file, so the owner can
    // edit recharged_assets/materials.txt on the device and toggle the row to apply it with no
    // rebuild and no relaunch.
    custom_tex::mm_request_params_reload();
  }
#else
  (void)sym;
#endif
}

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: runtime PBR toggle pushed from GOAL.
void pc_set_pbr(u32 sym) {
  Gfx::g_global_settings.recharged_pbr_enable = (sym != 0);
}

// Grecharged-directional-ambient ITEM B (owner playtest #2, 2026-07-20): the mood COLOR values the
// realtime-lighting path consumes — current-sun sun-color/env-color, light-group 0 colors, and
// current-shadow — are the OUTPUT of a 2-snapshot lerp (update-mood-sky-texture / update-mood-palette
// over *default-interp-table*) that HARD-SWITCHES which two of the 8 moods it lerps between at the
// hour boundaries ~04:00 / 07:00 / 08-09:00 (snapshot1 defaults to 0). Each basis switch is a 1-frame
// DISCONTINUITY in the value => the owner's "2 brutal light steps at night + 1 at sunrise". The stock
// BAKED path is smooth because it crossfades all 8 palette slots per-vertex; there is no single
// continuous sun/ambient COLOR to read instead. So we TEMPORALLY LOW-PASS the stepped color inputs
// here (translation-layer fix, once per frame at the FFI push): a 1-frame step becomes a smooth ~0.7s
// ramp => continuous like the baked path. Smoothing runs UNCONDITIONALLY (seeded on the first frame):
// OFF==stock is preserved by the SHADER gate — with realtime-lighting AND pbr-materials off the world
// shaders take the stock baked path and never read these fields, so a smoothed value is invisible
// (byte-identical). Running it always also means a later menu-enable sees an already-tracked value (no
// enable ramp). It is NOT gated on the pc-setting because the on-device A/B forces the realtime path via
// the debug.opengoal.rt.light PROP, which the FFI push cannot see. Tunable / A-B-defeatable via
// debug.opengoal.rt.todsmooth ("0" => raw stepped = the before; a float in (0,1] => that per-frame EMA
// weight; empty => the shipped default below).
static float rt_tod_smooth_alpha() {
  float a = 0.10f;  // per-frame EMA weight toward the new raw value (~0.7 s ramp @30 fps)
#ifdef __ANDROID__
  char b[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.rt.todsmooth", b) > 0 && b[0]) {
    a = (float)atof(b);
  }
#else
  if (const char* e = std::getenv("OG_RT_TODSMOOTH")) {
    a = (float)atof(e);
  }
#endif
  if (!(a >= 0.0f && a <= 1.0f)) {
    a = 0.10f;
  }
  return a;
}
// Exponential moving average of an n-float array in place toward `raw`. When `seed` (first frame,
// realtime lighting off, or smoothing disabled) it SNAPS to raw so a later enable starts from the
// true value (no boot ramp / stale-value flash).
static void rt_ema(float* dst, const float* raw, int n, float alpha, bool seed) {
  if (seed || alpha <= 0.0f) {
    for (int i = 0; i < n; i++) {
      dst[i] = raw[i];
    }
    return;
  }
  for (int i = 0; i < n; i++) {
    dst[i] += alpha * (raw[i] - dst[i]);
  }
}

// Grecharged-pbr-materials: per-frame mood/TOD sun state (three GOAL vectors, xyz each):
// shadow = current-shadow light-travel dir, sun_color = mood-sun sun-color, env = env-color.
// ITEM B: the three colors are EMA-smoothed (see rt_ema above) so the day/night snapshot steps ramp
// smoothly. The visible-sun DIRECTION is taken elsewhere from the already-continuous *sky-parms* sun
// position, so current-shadow is smoothed only for the night-time azimuthal ambient key.
void pc_set_pbr_sun(u32 shadow_vec, u32 sun_color_vec, u32 env_color_vec) {
  auto& gs = Gfx::g_global_settings;
  float* s = Ptr<float>(shadow_vec).c();
  float* c = Ptr<float>(sun_color_vec).c();
  float* e = Ptr<float>(env_color_vec).c();
  float raw_s[3] = {s[0], s[1], s[2]};
  float raw_c[3] = {c[0], c[1], c[2]};
  float raw_e[3] = {e[0], e[1], e[2]};
  static bool s_seed_sun = true;
  float alpha = rt_tod_smooth_alpha();
  bool seed = s_seed_sun || alpha <= 0.0f;
  rt_ema(gs.recharged_pbr_shadow, raw_s, 3, alpha, seed);
  rt_ema(gs.recharged_pbr_sun_color, raw_c, 3, alpha, seed);
  rt_ema(gs.recharged_pbr_ambient, raw_e, 3, alpha, seed);
  s_seed_sun = false;
}

// Round-5 addendum suspect (c): the VISIBLE sun's dome direction — *sky-parms* upload-data
// sun 0 pos, the exact vector the sun sprite is placed with (sparticle-track-sun:
// sun_world = camera + pos*4096). Camera->sun; magnitude ~ orbit dist (not unit).
void pc_set_pbr_sky_sun(u32 pos_vec) {
  float* p = Ptr<float>(pos_vec).c();
  Gfx::g_global_settings.recharged_pbr_sky_sun[0] = p[0];
  Gfx::g_global_settings.recharged_pbr_sky_sun[1] = p[1];
  Gfx::g_global_settings.recharged_pbr_sky_sun[2] = p[2];
}

// Grecharged-directional-ambient (owner playtest #3): the GREEN SUN's REAL sky position —
// *sky-parms* upload-data sun 1 pos (sun index 1 = the precursor green sun, computed every
// frame by sky-make-sun-data 1). Same camera->sun convention as the yellow sun above. Feeds
// the realtime green directional light (day AND night when it is above the horizon) + the
// night cast-shadow direction.
void pc_set_pbr_green_sun(u32 pos_vec) {
  float* p = Ptr<float>(pos_vec).c();
  Gfx::g_global_settings.recharged_pbr_green_sun[0] = p[0];
  Gfx::g_global_settings.recharged_pbr_green_sun[1] = p[1];
  Gfx::g_global_settings.recharged_pbr_green_sun[2] = p[2];
}

// Round-4 multi-light: GOAL passes (-> *time-of-day-context* light-group 0) — a light-group,
// four inline `light`s (dir0/dir1/dir2/ambi), each 48 bytes: direction vec16 @+0, color rgbaf16
// @+16, levels vec16 @+32 (levels.x = morph weight). Raw 0..255 colors; scaled at the GL boundary.
void pc_set_pbr_lights(u32 lg) {
  auto* base = Ptr<float>(lg).c();
  auto& gs = Gfx::g_global_settings;
  // Gather the raw light-group into flat arrays first, then EMA-smooth the DIRECTIONS + COLORS + ambi
  // (ITEM B: the light-group colors snapshot-step across TOD exactly like current-sun). The morph
  // LEVEL is a per-light blend weight, left raw.
  float raw_dir[9], raw_col[9], raw_ambi[3], raw_lvl[3];
  for (int i = 0; i < 3; i++) {
    const float* l = base + i * 12;  // 48 bytes = 12 floats
    for (int j = 0; j < 3; j++) {
      raw_dir[i * 3 + j] = l[j];
      raw_col[i * 3 + j] = l[4 + j];
    }
    raw_lvl[i] = l[8];
  }
  const float* ambi = base + 3 * 12;
  for (int j = 0; j < 3; j++) raw_ambi[j] = ambi[4 + j];
  static bool s_seed_lights = true;
  float alpha = rt_tod_smooth_alpha();
  bool seed = s_seed_lights || alpha <= 0.0f;
  rt_ema(&gs.recharged_pbr_lg_dir[0][0], raw_dir, 9, alpha, seed);
  rt_ema(&gs.recharged_pbr_lg_color[0][0], raw_col, 9, alpha, seed);
  rt_ema(gs.recharged_pbr_lg_ambi, raw_ambi, 3, alpha, seed);
  for (int i = 0; i < 3; i++) gs.recharged_pbr_lg_level[i] = raw_lvl[i];
  gs.recharged_pbr_lg_valid = true;
  s_seed_lights = false;
}

// Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY realtime lighting toggles,
// pushed from GOAL each frame. rt-light! = master.
void pc_set_rt_light(u32 sym) {
  Gfx::g_global_settings.recharged_rt_light_enable = (sym != 0);
}
// Grecharged-directional-ambient: hemisphere ambient enable + base strength. rt-ambient! =
// enable (mirrors rt-light!); rt-ambient-strength! = base level (mirrors pc-set-rt-shadow-dist!:
// takes a plain u32 from GOAL, stored as a float; the GL side clamps out-of-range back to 0.2).
void pc_set_rt_ambient(u32 sym) {
  Gfx::g_global_settings.recharged_rt_ambient_enable = (sym != 0);
}
void pc_set_rt_ambient_strength(u32 pct) {
  // GOAL sends an int PERCENT 0..50 (0.2 -> 20); mirror pc_set_rt_shadow_strength's *0.01 convention.
  Gfx::g_global_settings.recharged_rt_ambient_strength = (float)pct * 0.01f;
}
// REOPEN #2 menu sliders: TEXTURE RELIEF (percent 0..300) + SPECULAR INTENSITY (percent 0..200),
// same *0.01 int-percent convention as the ambient-strength setter above.
void pc_set_pbr_texture_relief(u32 pct) {
  // [mb-diag] change-only trace: v2.1 measured the GOAL variable moving ~6-7 s before this
  // bridge saw the new value; this line names WHEN the push actually lands (logcat GK_*).
  static u32 s_last_pct = 0xffffffff;
  if (pct != s_last_pct) {
    s_last_pct = pct;
    lg::info("[mb-diag] relief push pct={}", pct);
  }
  Gfx::g_global_settings.recharged_pbr_texture_relief = (float)pct * 0.01f;
}
void pc_set_pbr_specular_intensity(u32 pct) {
  Gfx::g_global_settings.recharged_pbr_spec_intensity = (float)pct * 0.01f;
}
// REOPEN #3 DISPLACEMENT carousel: raw mode int (0 Off / 1 Parallax / 2 Tessellation).
void pc_set_pbr_displacement(u32 mode) {
  int m = (int)std::min(mode, 2u);
  // GENERAL crash-loop guard, session clamp (defense in depth): if the boot guard tripped this
  // session, refuse the risky displacement value regardless of what GOAL pushes.
  if (s_recharged_guard_tripped) {
    m = 0;
  }
  Gfx::g_global_settings.recharged_pbr_displacement = m;
  // Healthy clear: this is pushed every frame by GOAL update-to-os. Once we've survived 60s past
  // boot, delete the boot sentinel once so a normal session never trips the guard next launch.
  static bool did_clear = false;
  if (!did_clear && s_recharged_boot_t >= 0.0) {
    double now =
        std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
    if (now - s_recharged_boot_t > kRechargedGuardHealthySecs) {
      std::error_code ec;
      fs::remove(recharged_boot_guard_path(), ec);
      did_clear = true;
      lg::info("[recharged] crash-loop guard: healthy boot, sentinel cleared");
    }
  }
}
// REOPEN #10 PBR ISOLATE carousel (DEBUG, removable): the owner's IN-MENU term bisection.
// GOAL pushes the raw carousel INDEX; map it to the u_pbr_bisect MASK the fused shader reads
// (128 = POM/parallax off @ tfrag3.frag L587, 64 = normal-map off @ L634). This lets the owner
// flip Both / Normal-map-only / Parallax-only / Neither at his own grass vantage with no adb,
// so his bisection — not another headless guess — names the residual facet term.
void pc_set_pbr_isolate(u32 idx) {
  int mask = 0;
  const char* label = "BOTH";
  switch (idx) {
    case 1:
      mask = 128;  // NORMAL-MAP ONLY: parallax/POM off
      label = "NORMAL-MAP ONLY";
      break;
    case 2:
      mask = 64;  // PARALLAX ONLY: normal-map perturbation off
      label = "PARALLAX ONLY";
      break;
    case 3:
      mask = 192;  // NEITHER: both off (128 | 64)
      label = "NEITHER";
      break;
    default:
      mask = 0;  // BOTH (default): full fused path
      label = "BOTH";
      break;
  }
  Gfx::g_global_settings.recharged_pbr_isolate = mask;
  // REOPEN #11 (owner: the PBR-ISOLATE carousel "flip does nothing"): PROVE the menu value
  // actually reaches the fused shader's u_pbr_bisect mask by writing the ACTIVE carousel index +
  // resolved bisect mask to a device-pullable diag file EACH TIME IT CHANGES. The Honor obscures
  // logcat, so a FILE is the only reliable channel: the supervisor pulls it with
  //   run-as org.opengoal.gk.jak1 cat files/pbr_tan_diag.txt
  // and confirms flipping the menu changes index/mask on device. This is called every frame with
  // the current index, so gate the write on an ACTUAL change to avoid per-frame disk churn.
  static int s_last_isolate_mask = -1;
#ifdef OG_FEAT_PBR
  // 2026-07-26: the file now also carries the [pom] block, which only fills in once a level's
  // materials are resolved — long after the carousel settles on its boot value. Re-emit whenever
  // the material set changes too, or the block would forever read "materials=0".
  static u32 s_last_pom_gen = 0;
  const u32 pom_gen = custom_tex::pbr_pom_diag_generation();
  bool pom_changed = pom_gen != s_last_pom_gen;
  s_last_pom_gen = pom_gen;
  // ROUND 21: the [cover] block's numbers change every frame, so its generation advances only once
  // every ~300 completed frames (~5 s) — enough to keep the pulled file live without per-frame disk
  // churn, and it never advances at all while nothing is being counted (PBR off).
  static u32 s_last_cover_gen = 0;
  const u32 cover_gen = custom_tex::pbr_coverage_generation();
  if (cover_gen != s_last_cover_gen) {
    s_last_cover_gen = cover_gen;
    pom_changed = true;
  }
#else
  const bool pom_changed = false;
#endif
  if (mask != s_last_isolate_mask || pom_changed) {
    s_last_isolate_mask = mask;
    try {
      std::string body = fmt::format(
          "[pbr-isolate] active: index={} mask={} label=\"{}\"\n"
          "  resolved bits: normal-map-off(bit64)={} parallax/POM-off(bit128)={}\n"
          "  wiring: GOAL carousel -> pc-set-pbr-isolate! -> pc_set_pbr_isolate(idx) ->\n"
          "          Gfx::g_global_settings.recharged_pbr_isolate -> background_common u_pbr_bisect\n"
          "  (fused path only: realtime-lighting ON + pbr-materials ON. Flip the menu to change this.)\n",
          idx, mask, label, (mask & 64) ? 1 : 0, (mask & 128) ? 1 : 0);
#ifdef OG_FEAT_PBR
      body += custom_tex::pbr_pom_diag_section();
      body += custom_tex::pbr_coverage_section();
      // Grecharged-materials-modern-parity: the modern stack's per-material parameters as the
      // renderer actually resolved them, plus the per-channel ACTIVE-DRAW counters. The Honor
      // obscures logcat and the owner has no adb, so a pullable file is the only proof channel
      // that survives both — and a counter answers "did the code path run" without a screenshot.
      body += custom_tex::mm_params_diag_section();
#endif
      file_util::write_text_file(file_util::get_jak_project_dir() / "pbr_tan_diag.txt", body);
    } catch (...) {
      // best-effort diag; never let a file error affect the render path
    }
  }
}
void pc_set_rt_ambient_contrast(u32 pct) {
  // GOAL sends an int PERCENT 0..150 (0.9 -> 90); mirror the *0.01 convention above.
  Gfx::g_global_settings.recharged_rt_ambient_contrast = (float)pct * 0.01f;
}
// Grecharged-directional-ambient ROUND 2: ambient MODEL selector (0 hemisphere / 1 SH / 2 IBL).
void pc_set_rt_ambient_model(u32 model) {
  Gfx::g_global_settings.recharged_rt_ambient_model = (int)model;
}
// Grecharged-pbr-realtime-fusion DYNAMIC FOLLOW-PROBE tier (0 Off/procedural-IBL .. 3 High). The
// PBR env source is now a camera-centered amortized cubemap (replaces the deleted probe grid).
void pc_set_follow_probe(u32 tier) {
  Gfx::g_global_settings.recharged_follow_probe = (int)std::min(tier, 3u);
}
// ROUND 2: sun shadow-map Quality (resolution, texels) + Distance (range, meters). Both
// take a plain u32 from GOAL (res e.g. 2048; dist e.g. 100) — no float-ABI concern.
void pc_set_rt_shadow_res(u32 res) {
  Gfx::g_global_settings.recharged_rt_shadow_res = (int)res;
}
void pc_set_rt_shadow_dist(u32 dist_m) {
  Gfx::g_global_settings.recharged_rt_shadow_dist = (float)dist_m;
}
// ROUND 5: cast-shadow Strength (how much a shadow darkens). GOAL passes call args in GPRs,
// so a C float parameter would read an unset FP register (garbage) — every pc-set setter
// therefore takes an integer. Strength arrives as an INT PERCENT 0..100 (0.8 -> 80); store
// it back as a float 0..1. The shader residual is computed 1 - this.
void pc_set_rt_shadow_strength(u32 pct) {
  Gfx::g_global_settings.recharged_rt_shadow_strength = (float)pct * 0.01f;
}
#endif

// ===============================================================================================
// Grecharged-mesh-browser: the debug MESH BROWSER back end (owner's direct request).
//
// The browser lists every displaceable mesh of a level worst-grade-first, lets the owner warp to
// any one, auto-frames the camera on its bounding box, and toggles the checker / displacement /
// relief / time-of-day while he judges it. GOAL owns the UI, the warp, the camera orbit and the
// input; C++ owns the on-disk catalogue (parsing thousands of rows in GOAL would be painful) and
// the checker toggle. This block is the bridge:
//   * pc-mesh-index-load!    parse the bundled mesh_index_<level>.txt for a level -> in-memory rows
//   * pc-mesh-index-count    how many meshes the loaded level has
//   * pc-mesh-index-*        per-row scalar getters (system/grade/centroid/bbox) keyed by row idx
//   * pc-mesh-index-name!    copy a row's material name into a GOAL string (font-encoded)
//   * pc-mesh-index-level!   copy the loaded level's name into a GOAL string
//   * pc-set-mesh-browser-checker!  drive the real-texture<->checker global (no adb needed)
//   * pc-mesh-browser-export!  write the selected mesh identifier to files/mesh_select.txt
// Read-only w.r.t. the render path: nothing here changes a shader; the checker global only
// re-points an EXISTING debug material, applied at the next level load.
// ===============================================================================================
namespace {
struct MeshIndexRow {
  int system = 0;  // 0 TFRAG, 1 TIE
  int tex_id = 0;
  int shell = 0;
  int graded = 0;       // 1 if the offline sign test produced a grade
  int a_sign_x100 = -1;  // percent x100, -1 when ungraded
  int b_disp_x100 = -1;
  float cx = 0, cy = 0, cz = 0;
  float lox = 0, loy = 0, loz = 0;
  float hix = 0, hiy = 0, hiz = 0;
  std::string material;
};
// V2: indices are CACHED per level (the ray pick below hits up to two levels every frame, so
// re-parsing thousands of rows per pick would be absurd). std::map nodes never move, so the
// pointers handed out below stay valid for the process lifetime.
static std::map<std::string, std::vector<MeshIndexRow>> g_mesh_index_cache;
std::string g_mesh_index_level;
// The level the list UI currently reads; all the row getters go through this.
static const std::vector<MeshIndexRow>* g_mesh_index_cur = nullptr;

// GOAL strings arrive font-encoded uppercase; on-disk index names are lowercase [a-z0-9-].
std::string mb_clean_level_name(const std::string& level) {
  std::string lvl_lower = str_util::to_lower(level);
  std::string clean;
  for (char c : lvl_lower) {
    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
      clean.push_back(c);
    }
  }
  return clean;
}

// Parse-on-first-request cache lookup. `name` is already cleaned. nullptr = no usable index
// (missing file / bad header) — failures are NOT cached so a late-pushed index still loads.
static const std::vector<MeshIndexRow>* mb_load_level_index(const std::string& name) {
  auto it = g_mesh_index_cache.find(name);
  if (it != g_mesh_index_cache.end()) {
    return &it->second;
  }
  const auto path =
      file_util::get_bundled_mesh_index_dir(g_game_version) / ("mesh_index_" + name + ".txt");
  std::ifstream in(path.string());
  if (!in) {
    lg::warn("[mesh-browser] no index for level '{}' at {}", name, path.string());
    return nullptr;
  }
  std::string header;
  if (!std::getline(in, header)) {
    return nullptr;
  }
  {
    std::istringstream hs(header);
    std::string magic;
    int ver = 0;
    std::string lname;
    long count = 0;
    hs >> magic >> ver >> lname >> count;
    if (magic != "MESHIDX") {
      lg::warn("[mesh-browser] bad index header for '{}'", name);
      return nullptr;
    }
    (void)ver;
    (void)count;
  }
  std::vector<MeshIndexRow> rows;
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    std::istringstream ls(line);
    MeshIndexRow r;
    int idx = 0;
    if (!(ls >> idx >> r.system >> r.tex_id >> r.shell >> r.graded >> r.a_sign_x100 >>
          r.b_disp_x100 >> r.cx >> r.cy >> r.cz >> r.lox >> r.loy >> r.loz >> r.hix >> r.hiy >>
          r.hiz)) {
      continue;
    }
    std::getline(ls, r.material);  // rest of line (leading space + spaceless material tail)
    while (!r.material.empty() && (r.material.front() == ' ' || r.material.front() == '\t')) {
      r.material.erase(r.material.begin());
    }
    if (r.material.empty()) {
      r.material = "?";
    }
    rows.push_back(std::move(r));
  }
  auto ins = g_mesh_index_cache.emplace(name, std::move(rows));
  lg::info("[mesh-browser] loaded {} meshes for level '{}'", ins.first->second.size(), name);
  return &ins.first->second;
}

// jak1/kmachine.cpp has no kmachine_extras helper (unlike jak2/3), and the common file's
// bool_to_symbol is file-local — so provide the same #t/#f GOAL-symbol return here.
inline u64 mb_bool_to_symbol(bool val) {
  return val ? static_cast<u64>(s7.offset) + true_symbol_offset(g_game_version) : s7.offset;
}

// Copy a std::string into a GOAL string buffer (font-encoded, uppercased for the jak1 font), the
// same pattern as pc_get_display_name. Truncates to the GOAL string's declared allocated length.
void copy_to_goal_string(u32 str_dest_ptr, const std::string& s) {
  if (!str_dest_ptr) {
    return;
  }
  std::string up = s;
  if (g_game_version == GameVersion::Jak1) {
    up = str_util::to_upper(up);
  }
  const auto encoded =
      get_font_bank_from_game_version(g_game_version)->convert_utf8_to_game(up.c_str());
  auto* gs = Ptr<String>(str_dest_ptr).c();
  // String::len is the allocated capacity; keep one byte for the NUL.
  int cap = (int)gs->len;
  std::string clipped = (cap > 1 && (int)encoded.size() >= cap) ? encoded.substr(0, cap - 1)
                                                                : encoded;
  strcpy(gs->data(), clipped.c_str());
}
}  // namespace

// Load and parse the bundled per-level index. Returns the mesh count (0 on any failure — a level
// without an index simply lists empty, never crashes). `level_name_ptr` is a GOAL string.
u64 pc_mesh_index_load(u32 level_name_ptr) {
  g_mesh_index_cur = nullptr;
  g_mesh_index_level.clear();
  if (!level_name_ptr) {
    return 0;
  }
  std::string level = Ptr<String>(level_name_ptr).c()->data();
  std::string clean = mb_clean_level_name(level);
  if (clean.empty()) {
    return 0;
  }
  g_mesh_index_cur = mb_load_level_index(clean);
  if (!g_mesh_index_cur) {
    return 0;
  }
  g_mesh_index_level = clean;
  return (u64)g_mesh_index_cur->size();
}

u64 pc_mesh_index_count() {
  return g_mesh_index_cur ? (u64)g_mesh_index_cur->size() : 0;
}

// One scalar getter, keyed by (row, field). Keeping it a single entry point avoids a dozen tiny
// externs. field ids: 0 system, 1 graded, 2 a_sign_x100, 3 b_disp_x100, 4 tex_id, 5 shell.
s64 pc_mesh_index_geti(u32 row, u32 field) {
  if (!g_mesh_index_cur || row >= g_mesh_index_cur->size()) {
    return -1;
  }
  const auto& r = (*g_mesh_index_cur)[row];
  switch (field) {
    case 0:
      return r.system;
    case 1:
      return r.graded;
    case 2:
      return r.a_sign_x100;
    case 3:
      return r.b_disp_x100;
    case 4:
      return r.tex_id;
    case 5:
      return r.shell;
    default:
      return -1;
  }
}

// Geometry getter (world metres, GOAL float). field ids: 0 cx 1 cy 2 cz, 3 lox 4 loy 5 loz,
// 6 hix 7 hiy 8 hiz. The caller multiplies by 4096 to reach GOAL units.
// Returns the FLOAT BIT PATTERN in the integer return register, NOT a C float: GOAL reads every
// builtin return from the integer register (x86 RAX / arm64 X0), while a C `float` travels in
// XMM0/S0 — so a real float return reads back as 0.0 in GOAL on both backends. This exact hole made
// every centroid/bbox read 0 on device: the browser "warped to the same spot every time" (the
// owner's report) because that spot was the world origin. Same convention as
// common/kmachine.cpp::pc_get_axis_scale.
u64 pc_mesh_index_getf(u32 row, u32 field) {
  float out = 0.f;
  const auto bits = [&out]() -> u64 {
    u32 b;
    memcpy(&b, &out, sizeof(b));
    return b;
  };
  if (!g_mesh_index_cur || row >= g_mesh_index_cur->size()) {
    return bits();
  }
  const auto& r = (*g_mesh_index_cur)[row];
  switch (field) {
    case 0:
      out = r.cx;
      break;
    case 1:
      out = r.cy;
      break;
    case 2:
      out = r.cz;
      break;
    case 3:
      out = r.lox;
      break;
    case 4:
      out = r.loy;
      break;
    case 5:
      out = r.loz;
      break;
    case 6:
      out = r.hix;
      break;
    case 7:
      out = r.hiy;
      break;
    case 8:
      out = r.hiz;
      break;
    default:
      out = 0.f;
      break;
  }
  return bits();
}

// Copy a row's material name into a GOAL string; returns #t/#f.
u64 pc_mesh_index_name(u32 row, u32 str_dest_ptr) {
  if (!g_mesh_index_cur || row >= g_mesh_index_cur->size()) {
    return mb_bool_to_symbol(false);
  }
  copy_to_goal_string(str_dest_ptr, (*g_mesh_index_cur)[row].material);
  return mb_bool_to_symbol(true);
}

// Copy the loaded level's name into a GOAL string.
u64 pc_mesh_index_levelname(u32 str_dest_ptr) {
  if (g_mesh_index_level.empty()) {
    return mb_bool_to_symbol(false);
  }
  copy_to_goal_string(str_dest_ptr, g_mesh_index_level);
  return mb_bool_to_symbol(true);
}

// The real-texture <-> checker toggle (settable without adb; see gfx.h field comment).
void pc_set_mesh_browser_checker(u32 mode) {
  Gfx::g_global_settings.recharged_mesh_browser_checker = (int)std::min(mode, 4u);
}

// Write the selected mesh identifier to files/mesh_select.txt so the owner can quote it back to us
// without adb (mirrors pos_dump.txt). Called on selection, not per frame — no throttle needed.
void pc_mesh_browser_export(u32 row) {
  if (!g_mesh_index_cur || row >= g_mesh_index_cur->size()) {
    return;
  }
  const auto& r = (*g_mesh_index_cur)[row];
  const char* sysname = r.system == 1 ? "TIE" : "TFRAG";
  std::string grade = r.graded ? fmt::format("{:.2f}%", r.a_sign_x100 / 100.0) : "n/a";
  try {
    std::string body = fmt::format(
        "MESH SELECT\n"
        "level      {}\n"
        "material   {}\n"
        "system     {}\n"
        "tex_id     {}\n"
        "shell      {}\n"
        "row        {}\n"
        "A_sign     {}\n"
        "centroid_m {:.3f} {:.3f} {:.3f}\n"
        "warp.pos   {:.2f} {:.2f} {:.2f}\n",
        g_mesh_index_level, r.material, sysname, r.tex_id, r.shell, row, grade, r.cx, r.cy, r.cz,
        r.cx, r.cy, r.cz);
    file_util::write_text_file(file_util::get_jak_project_dir() / "mesh_select.txt", body);
  } catch (...) {
    // best-effort; never let a disk error touch the game loop
  }
}

// ===============================================================================================
// Grecharged-mesh-browser V2: reticle-first FREECAM. The list UI is out; the primary flow is now
// "fly, point the crosshair at a mesh, R1/R2 to target it". That needs three things the V1 bridge
// did not have:
//   * a RAY PICK over the index AABBs (up to TWO levels — the freecam can straddle a border),
//   * a TARGET CHANNEL into Gfx::g_global_settings so the renderer can hide / checker / gizmo the
//     one targeted mesh (per-draw, gated by the row's tex_id + AABB),
//   * runtime PROOF counters read back from the render thread, because two V1 toggles shipped
//     dead — every toggle must now demonstrate on->off->on via observable draw counts.
// ===============================================================================================
namespace {
// The freecam's pick scope: up to two level indices (empty string = slot unused).
std::string g_mb_pick_lvl[2];

struct MbPickHit {
  int slot = 0;
  int row = 0;
  float t = 0.f;     // metres along the (normalized) ray to the SURFACE the reticle sees
  float ttri = -1.f; // nearest REAL triangle hit (GOAL units), from the render-thread sweep
};
// serial whose triangle results have already been folded+sorted into g_mb_pick_hits.
u32 g_mb_pick_sorted_serial = 0;
std::vector<MbPickHit> g_mb_pick_hits;
// V2.3: the last pick ray (o = raw GOAL units, d = unit), kept for the PICKTRACE forensics line.
float g_mb_last_ray_o[3] = {0.f, 0.f, 0.f};
float g_mb_last_ray_d[3] = {0.f, 0.f, 1.f};
// V2.3: the CURRENT target's identity (row + pick-level slot), for the polygon-mark export.
int g_mb_target_row = -1;
int g_mb_target_slot = -1;
// V2.3: polygon marks appended this session + the resolved export path (see mb_marks_path()).
u64 g_mb_marks = 0;
std::string g_mb_marks_path;
// V2.5 (owner: "en réouvrant ce mode, les marques précédentes devraient subsister"): the mark
// store is rebuilt from mesh_marks.jsonl on browser open / whenever the published pick-level set
// changes. GOAL-thread only. g_mb_marks_skipped = file marks for the CURRENT levels that did not
// fit the store (store full -> oldest lines in the file win); surfaced to the HUD via rt-geti 16.
bool g_mb_marks_reload_pending = false;
std::string g_mb_marks_loaded_set;
u64 g_mb_marks_skipped = 0;
void mb_marks_reload_maybe();
}  // namespace

// Set the (up to two) levels the ray pick searches. GOAL strings, same idiom as
// pc-mesh-index-load!; pass the empty string to leave a slot unused.
void pc_mb_pick_levels(u32 lvl0, u32 lvl1) {
  const u32 ptrs[2] = {lvl0, lvl1};
  for (int i = 0; i < 2; i++) {
    g_mb_pick_lvl[i].clear();
    if (ptrs[i]) {
      g_mb_pick_lvl[i] = mb_clean_level_name(Ptr<String>(ptrs[i]).c()->data());
    }
  }
  // V2.5: the pick levels ARE the "current level" of the mark store — restore this level's
  // saved marks whenever the set changes (or a browser open left a reload pending).
  mb_marks_reload_maybe();
}

// V2.3 EXACT pick: no more AABB candidate pre-filter (a clearly visible mesh could rank >16 in
// AABB order and never get triangle-tested). This side now only publishes the RAY; the render
// thread sweeps ALL rendered geometry (mb_pick::raytest) and pc_mb_pick_ready resolves the
// globally-nearest ray-triangle hits back to index rows. origin/dir are GOAL vectors (origin in
// raw GOAL units — the camera trans; dir need not be unit). Returns 1 on a published request.
u64 pc_mb_pick(u32 origin, u32 dir) {
  g_mb_pick_hits.clear();
  if (!origin || !dir) {
    return 0;
  }
  const float* o = Ptr<float>(origin).c();
  const float* d = Ptr<float>(dir).c();
  float dx = d[0], dy = d[1], dz = d[2];
  const float len = std::sqrt(dx * dx + dy * dy + dz * dz);
  if (len < 1e-6f) {
    return 0;
  }
  dx /= len;
  dy /= len;
  dz /= len;
  g_mb_last_ray_o[0] = o[0];
  g_mb_last_ray_o[1] = o[1];
  g_mb_last_ray_o[2] = o[2];
  g_mb_last_ray_d[0] = dx;
  g_mb_last_ray_d[1] = dy;
  g_mb_last_ray_d[2] = dz;
  auto& gs = Gfx::g_global_settings;
  for (int a = 0; a < 3; a++) {
    gs.mb_pick_ray_o[a] = o[a];  // GOAL units — triangles are tested in GOAL units
  }
  gs.mb_pick_ray_d[0] = dx;
  gs.mb_pick_ray_d[1] = dy;
  gs.mb_pick_ray_d[2] = dz;
  // Browsable-texid filter: the sweep may only test draws whose tree_tex_id is INDEXED (the
  // mesh_index holds only displaceable materials; the offline reference sweep is scoped the
  // same way — the runtime must match or the equivalence proof fails by construction).
  for (int slot = 0; slot < 2; slot++) {
    gs.mb_pick_flt_n[slot][0] = 0;
    gs.mb_pick_flt_n[slot][1] = 0;
    gs.mb_pick_flt_lvl[slot][0] = '\0';
    if (g_mb_pick_lvl[slot].empty()) {
      continue;
    }
    const auto* rows = mb_load_level_index(g_mb_pick_lvl[slot]);
    if (!rows) {
      continue;
    }
    strncpy(gs.mb_pick_flt_lvl[slot], g_mb_pick_lvl[slot].c_str(),
            sizeof(gs.mb_pick_flt_lvl[slot]) - 1);
    gs.mb_pick_flt_lvl[slot][sizeof(gs.mb_pick_flt_lvl[slot]) - 1] = '\0';
    for (int sys = 0; sys < 2; sys++) {
      std::set<u32> texs;
      for (const auto& r : *rows) {
        if (r.system == sys) {
          texs.insert((u32)r.tex_id);
        }
      }
      if ((int)texs.size() > GfxGlobalSettings::MB_PICK_FLT_MAX) {
        lg::warn("[mb-diag] pick filter overflow: {} indexed texids (cap {}) lvl={} sys={}",
                 texs.size(), GfxGlobalSettings::MB_PICK_FLT_MAX, g_mb_pick_lvl[slot], sys);
      }
      int fn = 0;
      for (const u32 t : texs) {  // std::set iterates ascending -> array stays sorted
        if (fn >= GfxGlobalSettings::MB_PICK_FLT_MAX) {
          break;
        }
        gs.mb_pick_flt_tex[slot][sys][fn++] = t;
      }
      gs.mb_pick_flt_n[slot][sys] = fn;
    }
  }
  // release pairs with the render thread's acquire: the ray + filter above are visible before
  // the new serial is.
  const u32 new_serial = gs.mb_pick_serial.load(std::memory_order_relaxed) + 1;
  gs.mb_pick_serial.store(new_serial, std::memory_order_release);
  lg::info("[mb-diag] pick request serial={} (full sweep, flt {}+{}/{}+{})", new_serial,
           gs.mb_pick_flt_n[0][0], gs.mb_pick_flt_n[0][1], gs.mb_pick_flt_n[1][0],
           gs.mb_pick_flt_n[1][1]);
  return 1;
}

// V2.3: poll the full-sweep ray-test. 0 = still pending (results not published). On the first
// ready call for a request, resolve each render-thread hit (already sorted ascending t, deduped
// by (sys, texid, lvl)) back to the index row OWNING the hit triangle: among the rows of the
// hit's system+texid, the one whose AABB CONTAINS the hit point (0.5 m slack) with the smallest
// volume wins (tie -> lowest row index); if none contain, the nearest centroid of the
// system+texid rows; if the level has no such rows at all, the hit is skipped. Appends one
// PICKTRACE line to mb_pick_trace.txt for offline forensics. Returns 1 + the kept row count.
// Idempotent after the first ready call.
u64 pc_mb_pick_ready() {
  auto& gs = Gfx::g_global_settings;
  const u32 s = gs.mb_pick_serial.load(std::memory_order_relaxed);
  if (gs.mb_pick_done.load(std::memory_order_acquire) != s) {
    return 0;
  }
  if (g_mb_pick_sorted_serial != s) {
    g_mb_pick_sorted_serial = s;
    g_mb_pick_hits.clear();
    const int n = std::min(gs.mb_pick_hit_n, GfxGlobalSettings::MB_PICK_MAX);
    // the hits_out entry whose resolution produced the FIRST kept row (for the trace line)
    const GfxGlobalSettings::MbRayHit* first_hit = nullptr;
    for (int i = 0; i < n; i++) {
      const auto& h = gs.mb_pick_hits_out[i];
      // which pick-level slot does this hit's level belong to?
      const std::string hl = mb_clean_level_name(h.lvl);
      int slot = -1;
      for (int sl = 0; sl < 2; sl++) {
        if (!g_mb_pick_lvl[sl].empty() &&
            strncmp(g_mb_pick_lvl[sl].c_str(), hl.c_str(), sizeof(h.lvl)) == 0) {
          slot = sl;
          break;
        }
      }
      if (slot < 0) {
        continue;
      }
      const auto* rows = mb_load_level_index(g_mb_pick_lvl[slot]);
      if (!rows) {
        continue;
      }
      const float hm[3] = {h.hit[0] / 4096.f, h.hit[1] / 4096.f, h.hit[2] / 4096.f};  // metres
      // pass 1: containing rows (0.5 m slack), smallest AABB volume wins, tie -> lowest index
      int best = -1;
      float best_vol = std::numeric_limits<float>::max();
      // pass-2 fallback bookkeeping: nearest centroid among system+texid rows
      int near_row = -1;
      float near_d2 = std::numeric_limits<float>::max();
      for (int row = 0; row < (int)rows->size(); row++) {
        const auto& r = (*rows)[(size_t)row];
        if (r.system != h.sys || (u32)r.tex_id != h.texid) {
          continue;
        }
        const float dx = r.cx - hm[0], dy = r.cy - hm[1], dz = r.cz - hm[2];
        const float d2 = dx * dx + dy * dy + dz * dz;
        if (d2 < near_d2) {
          near_d2 = d2;
          near_row = row;
        }
        if (hm[0] >= r.lox - 0.5f && hm[0] <= r.hix + 0.5f &&  //
            hm[1] >= r.loy - 0.5f && hm[1] <= r.hiy + 0.5f &&  //
            hm[2] >= r.loz - 0.5f && hm[2] <= r.hiz + 0.5f) {
          const float vol = (r.hix - r.lox) * (r.hiy - r.loy) * (r.hiz - r.loz);
          if (vol < best_vol) {  // strict: an earlier row keeps a tie
            best_vol = vol;
            best = row;
          }
        }
      }
      if (best < 0) {
        best = near_row;  // no containing row: nearest centroid of the system+texid rows
      }
      if (best < 0) {
        continue;  // level has no rows of this system+texid at all
      }
      bool dup = false;
      for (const auto& kept : g_mb_pick_hits) {
        if (kept.slot == slot && kept.row == best) {
          dup = true;  // keep the first = nearest resolution of this row
          break;
        }
      }
      if (dup) {
        continue;
      }
      MbPickHit ph;
      ph.slot = slot;
      ph.row = best;
      ph.ttri = h.t;           // GOAL units, as before
      ph.t = h.t / 4096.f;     // metres
      g_mb_pick_hits.push_back(ph);
      if (!first_hit) {
        first_hit = &h;
      }
    }
    // PICKTRACE: one line per pick, enough for an offline tool to replay the exact ray and
    // re-find the exact triangle (same enumeration rule as the sweep).
    try {
      std::ofstream tf((file_util::get_jak_project_dir() / "mb_pick_trace.txt").string(),
                       std::ios::app);
      const int frow = g_mb_pick_hits.empty() ? -1 : g_mb_pick_hits.front().row;
      const int fslot = g_mb_pick_hits.empty() ? -1 : g_mb_pick_hits.front().slot;
      tf << fmt::format(
          "PICKTRACE serial={} lvl0={} lvl1={} o={:.9g},{:.9g},{:.9g} d={:.9g},{:.9g},{:.9g} "
          "n={} row={} slot={} t={:.9g} tex={} tri={} hit={:.9g},{:.9g},{:.9g}\n",
          s, g_mb_pick_lvl[0].empty() ? "-" : g_mb_pick_lvl[0],
          g_mb_pick_lvl[1].empty() ? "-" : g_mb_pick_lvl[1], g_mb_last_ray_o[0],
          g_mb_last_ray_o[1], g_mb_last_ray_o[2], g_mb_last_ray_d[0], g_mb_last_ray_d[1],
          g_mb_last_ray_d[2], (int)g_mb_pick_hits.size(), frow, fslot,
          first_hit ? first_hit->t : -1.f, first_hit ? first_hit->texid : 0,
          first_hit ? first_hit->tri : -1, first_hit ? first_hit->hit[0] : 0.f,
          first_hit ? first_hit->hit[1] : 0.f, first_hit ? first_hit->hit[2] : 0.f);
    } catch (...) {
      // best-effort; never let a disk error touch the game loop
    }
    lg::info("[mb-diag] pick ready serial={} raw_hits={} kept={}", s, n,
             (int)g_mb_pick_hits.size());
  }
  return 1 + (u64)g_mb_pick_hits.size();
}

// Hit getter over the last pick. field: 0 row, 1 slot, 2 t in centimetres. -1 out of range.
u64 pc_mb_pick_geti(s32 idx, s32 field) {
  if (idx < 0 || idx >= (int)g_mb_pick_hits.size()) {
    return (u64)-1;
  }
  const auto& h = g_mb_pick_hits[(size_t)idx];
  switch (field) {
    case 0:
      return (u64)h.row;
    case 1:
      return (u64)h.slot;
    case 2:
      // V2.2: after the triangle fold, ttri (GOAL units) is the REAL surface distance the sort
      // used — report that (converted to metres->cm) so the state export shows the same order the
      // pick ranked by. Before the fold (or box-only fallback) it is the AABB slab distance.
      if (h.ttri >= 0.f) {
        return (u64)(s64)std::lround((h.ttri / 4096.f) * 100.0f);
      }
      return (u64)(s64)std::lround(h.t * 100.0f);
    default:
      return (u64)-1;
  }
}

// Target a picked mesh: publish its identity (system + tex_id + level + GOAL-unit AABB) to the
// render thread. The three toggle flags are ALWAYS cleared here AND on clear — the single
// enforcement point that guarantees a hidden mesh can never become un-targetable by a target
// switch (hide must die with the target it applied to).
void pc_mb_target_set(s32 row, s32 slot) {
  if (slot < 0 || slot > 1 || g_mb_pick_lvl[slot].empty()) {
    return;
  }
  const auto* rows = mb_load_level_index(g_mb_pick_lvl[slot]);
  if (!rows || row < 0 || row >= (int)rows->size()) {
    return;
  }
  const auto& r = (*rows)[(size_t)row];
  auto& gs = Gfx::g_global_settings;
  gs.mb_target_system = r.system;
  gs.mb_target_tex = (u32)r.tex_id;
  strncpy(gs.mb_target_level, g_mb_pick_lvl[slot].c_str(), sizeof(gs.mb_target_level) - 1);
  gs.mb_target_level[sizeof(gs.mb_target_level) - 1] = '\0';
  // index AABB is metres; the renderer compares in GOAL units
  gs.mb_target_bbox[0] = r.lox * 4096.f;
  gs.mb_target_bbox[1] = r.loy * 4096.f;
  gs.mb_target_bbox[2] = r.loz * 4096.f;
  gs.mb_target_bbox[3] = r.hix * 4096.f;
  gs.mb_target_bbox[4] = r.hiy * 4096.f;
  gs.mb_target_bbox[5] = r.hiz * 4096.f;
  gs.mb_hide_target = false;
  gs.mb_checker_target = false;
  gs.mb_gizmos_target = false;
  // mb_isolate deliberately survives target changes — the new target is re-isolated (owner spec).
  gs.mb_target_active = true;
  // V2.3: the target's identity, for the polygon-mark export (pc_mb_mark_poly).
  g_mb_target_row = row;
  g_mb_target_slot = slot;
}

void pc_mb_target_clear() {
  auto& gs = Gfx::g_global_settings;
  gs.mb_target_active = false;
  gs.mb_hide_target = false;
  gs.mb_checker_target = false;
  gs.mb_gizmos_target = false;
  gs.mb_isolate = false;
  g_mb_target_row = -1;
  g_mb_target_slot = -1;
}

// The three per-target toggles (L1/L2 hide, Square checker, Circle normal gizmos).
void pc_mb_hide_set(s32 v) {
  Gfx::g_global_settings.mb_hide_target = (v != 0);
}

void pc_mb_checker_set(s32 v) {
  Gfx::g_global_settings.mb_checker_target = (v != 0);
}

void pc_mb_gizmos_set(s32 v) {
  Gfx::g_global_settings.mb_gizmos_target = (v != 0);
}

// V2.6-bis (START pad / ISOL overlay pill): render ONLY the targeted mesh while a target is
// active. Consumed via mb_isolation_on() by the TFRAG/TIE per-draw checks and the world
// renderers' early-outs.
void pc_mb_isolate_set(s32 v) {
  Gfx::g_global_settings.mb_isolate = (v != 0);
}

// ---- V2.3 hover + polygon mark ----------------------------------------------------------------
namespace {
// Seqlock read of the render thread's hover answer (gfx.h mb_hover_*). Retries up to 4 times;
// false when no stable even-seq snapshot could be taken.
struct MbHoverSnap {
  int tri = -1;
  u32 texid = 0;
  float v[3][3] = {{0.f}};
  float nrm[3] = {0.f, 0.f, 0.f};
};
bool mb_hover_read(MbHoverSnap* out) {
  auto& gs = Gfx::g_global_settings;
  for (int attempt = 0; attempt < 4; attempt++) {
    const u32 s1 = gs.mb_hover_seq.load(std::memory_order_acquire);
    if (s1 & 1) {
      continue;  // writer mid-update
    }
    out->tri = gs.mb_hover_tri;
    out->texid = gs.mb_hover_texid;
    memcpy(out->v, gs.mb_hover_v, sizeof(out->v));
    memcpy(out->nrm, gs.mb_hover_nrm, sizeof(out->nrm));
    const u32 s2 = gs.mb_hover_seq.load(std::memory_order_acquire);
    if (s1 == s2) {
      return true;
    }
  }
  return false;
}

// The polygon-mark JSONL export path: the EXTERNAL game root when one is set (Android — the
// owner pulls files from there without adb into the app sandbox), else the project dir
// (desktop). Mirrors how settings.ini resolves (FileUtil.cpp get_user_settings_dir).
const std::string& mb_marks_path() {
  if (g_mb_marks_path.empty()) {
    const auto root = file_util::get_external_game_root();
    g_mb_marks_path = root ? (*root / "mesh_marks.jsonl").string()
                           : (file_util::get_jak_project_dir() / "mesh_marks.jsonl").string();
  }
  return g_mb_marks_path;
}
}  // namespace

// GOAL pushes the freecam reticle ray every frame while hovering (on != 0); the render thread's
// gizmo pass answers with the nearest cached face via the seqlock. on == 0 stops the hover.
void pc_mb_hover_ray(u32 origin, u32 dir, u32 on) {
  auto& gs = Gfx::g_global_settings;
  if (!on || !origin || !dir) {
    gs.mb_hover_on.store(0, std::memory_order_release);
    return;
  }
  const float* o = Ptr<float>(origin).c();
  const float* d = Ptr<float>(dir).c();
  float dx = d[0], dy = d[1], dz = d[2];
  const float len = std::sqrt(dx * dx + dy * dy + dz * dz);
  if (len < 1e-6f) {
    gs.mb_hover_on.store(0, std::memory_order_release);
    return;
  }
  for (int a = 0; a < 3; a++) {
    gs.mb_hover_ray_o[a] = o[a];  // raw GOAL units, like the pick ray
  }
  gs.mb_hover_ray_d[0] = dx / len;
  gs.mb_hover_ray_d[1] = dy / len;
  gs.mb_hover_ray_d[2] = dz / len;
  gs.mb_hover_on.store(1, std::memory_order_release);
}

// V2.4 helper: remove the JSONL line(s) of an unmarked polygon. The key (level, row, tri)
// uniquely identifies a mark's line — the writer below emits these three fields verbatim, so a
// substring match on all three is exact (no JSON parser needed for a file we ourselves write).
// Rewrites the file without the matching line(s); on any IO error the file is left as it was.
void mb_marks_remove_line(const std::string& lvl, int row, int tri) {
  const std::string k_lvl = fmt::format("\"level\":\"{}\"", lvl);
  const std::string k_row = fmt::format("\"row\":{},", row);
  const std::string k_tri = fmt::format("\"tri\":{},", tri);
  try {
    std::ifstream in(mb_marks_path());
    if (!in) {
      return;
    }
    std::vector<std::string> keep;
    std::string line;
    while (std::getline(in, line)) {
      if (line.find(k_lvl) != std::string::npos && line.find(k_row) != std::string::npos &&
          line.find(k_tri) != std::string::npos) {
        continue;  // the unmarked polygon's record
      }
      if (!line.empty()) {
        keep.push_back(line);
      }
    }
    in.close();
    std::ofstream out(mb_marks_path(), std::ios::trunc);
    for (const auto& l : keep) {
      out << l << "\n";
    }
  } catch (...) {
    // best-effort; never let a disk error touch the game loop
  }
}

// ---- V2.5: resume a marking session -----------------------------------------------------------
// The owner marks polygons across app runs; mesh_marks.jsonl survives but the store used to start
// empty, so old marks neither highlighted nor unmarked. Reload rebuilds the ACTIVE store from the
// file, restricted to the published pick levels (other levels' lines stay in the file, untouched
// and unloaded). We parse only the file we ourselves write, so a string scan per key is exact;
// any line that fails a field is skipped without crashing (owner robustness requirement).
namespace {
bool mb_json_num(const std::string& s, const char* key, double* out) {
  const auto p = s.find(key);
  if (p == std::string::npos) {
    return false;
  }
  const char* c = s.c_str() + p + std::strlen(key);
  char* end = nullptr;
  const double v = std::strtod(c, &end);
  if (end == c) {
    return false;
  }
  *out = v;
  return true;
}
bool mb_json_vec3(const std::string& s, const char* key, float* out, float scale) {
  const auto p = s.find(key);
  if (p == std::string::npos) {
    return false;
  }
  const char* c = s.c_str() + p + std::strlen(key);
  for (int i = 0; i < 3; i++) {
    while (*c == '[' || *c == ',' || *c == ' ') {
      c++;
    }
    char* end = nullptr;
    const double v = std::strtod(c, &end);
    if (end == c) {
      return false;
    }
    out[i] = (float)(v * scale);
    c = end;
  }
  return true;
}

void mb_marks_reload_maybe() {
  const std::string set = g_mb_pick_lvl[0] + "|" + g_mb_pick_lvl[1];
  if (!g_mb_marks_reload_pending && set == g_mb_marks_loaded_set) {
    return;
  }
  if (g_mb_pick_lvl[0].empty() && g_mb_pick_lvl[1].empty()) {
    return;  // no level names yet — stay pending until pc_mb_pick_levels publishes them
  }
  auto& gs = Gfx::g_global_settings;
  std::vector<GfxGlobalSettings::MbMark> loaded;
  // V2.6: the store is dynamic and the file can carry thousands of marks — dedupe must be O(1)
  // per line (the old per-line linear scan was quadratic and would stall the GOAL thread).
  std::unordered_set<std::string> seen;
  u64 skipped_full = 0;
  try {
    std::ifstream in(mb_marks_path());
    std::string line;
    while (in && std::getline(in, line)) {
      auto lp = line.find("\"level\":\"");
      if (lp == std::string::npos) {
        continue;
      }
      lp += 9;
      const auto le = line.find('"', lp);
      if (le == std::string::npos) {
        continue;
      }
      const std::string lvl = line.substr(lp, le - lp);
      if (lvl.empty() || lvl.size() >= sizeof(GfxGlobalSettings::MbMark{}.lvl)) {
        continue;
      }
      if (lvl != g_mb_pick_lvl[0] && lvl != g_mb_pick_lvl[1]) {
        continue;  // another level's mark: keep its line, never load or touch it
      }
      GfxGlobalSettings::MbMark m;
      double row = 0.0, tri = 0.0;
      // the vertices are stored in metres (4 decimals); the store wants GOAL units
      if (!mb_json_num(line, "\"row\":", &row) || !mb_json_num(line, "\"tri\":", &tri) ||
          !mb_json_vec3(line, "\"v0_m\":", m.v[0], 4096.f) ||
          !mb_json_vec3(line, "\"v1_m\":", m.v[1], 4096.f) ||
          !mb_json_vec3(line, "\"v2_m\":", m.v[2], 4096.f) ||
          !mb_json_vec3(line, "\"face_normal\":", m.nrm, 1.f)) {
        continue;  // corrupt line: ignored without crash
      }
      std::memset(m.lvl, 0, sizeof(m.lvl));
      std::strncpy(m.lvl, lvl.c_str(), sizeof(m.lvl) - 1);
      m.sys = line.find("\"system\":\"TIE\"") != std::string::npos ? 1 : 0;
      m.row = (int)row;
      m.tri = (int)tri;
      if (!seen.insert(lvl + "|" + std::to_string(m.row) + "|" + std::to_string(m.tri)).second) {
        continue;  // duplicate (level, row, tri): first file line wins, same as before
      }
      if ((int)loaded.size() >= GfxGlobalSettings::MB_MARKS_SANITY) {
        skipped_full++;  // sanity bound only (1M): the oldest lines in the file win, HUD says so
        continue;
      }
      loaded.push_back(m);
    }
  } catch (...) {
    return;  // disk error: leave the store as it was, try again on the next trigger
  }
  const u64 n_loaded = (u64)loaded.size();
  {
    std::lock_guard<std::mutex> lk(gs.mb_marks_mu);
    gs.mb_marks_store = std::move(loaded);
    gs.mb_marks_gen++;
    gs.mb_marks_active.store((int)gs.mb_marks_store.size(), std::memory_order_relaxed);
  }
  g_mb_marks = n_loaded;
  g_mb_marks_skipped = skipped_full;
  g_mb_marks_loaded_set = set;
  g_mb_marks_reload_pending = false;
}
}  // namespace

// Mark the hovered polygon — or, V2.4, UNMARK it when it is already marked (the owner re-aims
// and presses the same button; the mark leaves the persistent-highlight store AND its line
// leaves mesh_marks.jsonl). Marks are appended as one JSON line (identity + geometry + the
// row's offline verdict) for offline orientation forensics. Returns the ACTIVE mark count after
// the toggle, or (u64)-1 when there is no stable hover hit / no target.
u64 pc_mb_mark_poly() {
  MbHoverSnap hs;
  if (!mb_hover_read(&hs) || hs.tri < 0 || g_mb_target_row < 0 || g_mb_target_slot < 0 ||
      g_mb_pick_lvl[g_mb_target_slot].empty()) {
    return (u64)-1;
  }
  const auto* rows = mb_load_level_index(g_mb_pick_lvl[g_mb_target_slot]);
  if (!rows || g_mb_target_row >= (int)rows->size()) {
    return (u64)-1;
  }
  const auto& r = (*rows)[(size_t)g_mb_target_row];
  auto& gs = Gfx::g_global_settings;
  const std::string& lvl = g_mb_pick_lvl[g_mb_target_slot];

  // UNMARK: same (level, row, tri) already in the store -> remove it there and in the JSONL.
  {
    bool removed = false;
    {
      std::lock_guard<std::mutex> lk(gs.mb_marks_mu);
      for (size_t i = 0; i < gs.mb_marks_store.size(); i++) {
        const auto& m = gs.mb_marks_store[i];
        if (m.tri == hs.tri && m.row == g_mb_target_row &&
            std::strncmp(lvl.c_str(), m.lvl, sizeof(m.lvl)) == 0) {
          gs.mb_marks_store.erase(gs.mb_marks_store.begin() + (ptrdiff_t)i);
          gs.mb_marks_gen++;
          gs.mb_marks_active.store((int)gs.mb_marks_store.size(), std::memory_order_relaxed);
          removed = true;
          break;
        }
      }
    }
    if (removed) {
      mb_marks_remove_line(lvl, g_mb_target_row, hs.tri);  // file IO outside the lock
      g_mb_marks = (u64)gs.mb_marks_active.load(std::memory_order_relaxed);
      return g_mb_marks;
    }
  }

  // V2.6: the store is dynamic (std::vector, no 256 cap). Only the 1M sanity bound can refuse a
  // mark, and it must NEVER do so silently (owner rule): bump the skipped counter the HUD's
  // "STORE FULL" line displays, and skip the JSONL append too so file and store stay in step.
  if (gs.mb_marks_active.load(std::memory_order_relaxed) >= GfxGlobalSettings::MB_MARKS_SANITY) {
    g_mb_marks_skipped++;
    return g_mb_marks;
  }
  try {
    std::ofstream f(mb_marks_path(), std::ios::app);
    f << fmt::format(
        "{{\"game\":\"jak1\",\"level\":\"{}\",\"system\":\"{}\",\"row\":{},\"shell\":{},"
        "\"material\":\"{}\",\"tex_id\":{},\"tri\":{},"
        "\"v0_m\":[{:.4f},{:.4f},{:.4f}],\"v1_m\":[{:.4f},{:.4f},{:.4f}],"
        "\"v2_m\":[{:.4f},{:.4f},{:.4f}],\"face_normal\":[{:.6f},{:.6f},{:.6f}],"
        "\"offline_verdict\":{{\"graded\":{},\"a_sign_x100\":{},\"b_disp_x100\":{}}},"
        "\"centroid_m\":[{:.4f},{:.4f},{:.4f}],"
        "\"aabb_m\":[[{:.4f},{:.4f},{:.4f}],[{:.4f},{:.4f},{:.4f}]]}}\n",
        g_mb_pick_lvl[g_mb_target_slot], r.system == 1 ? "TIE" : "TFRAG", g_mb_target_row,
        r.shell, r.material, r.tex_id, hs.tri,  //
        hs.v[0][0] / 4096.f, hs.v[0][1] / 4096.f, hs.v[0][2] / 4096.f,  //
        hs.v[1][0] / 4096.f, hs.v[1][1] / 4096.f, hs.v[1][2] / 4096.f,  //
        hs.v[2][0] / 4096.f, hs.v[2][1] / 4096.f, hs.v[2][2] / 4096.f,  //
        hs.nrm[0], hs.nrm[1], hs.nrm[2],  //
        r.graded, r.a_sign_x100, r.b_disp_x100,  //
        r.cx, r.cy, r.cz, r.lox, r.loy, r.loz, r.hix, r.hiy, r.hiz);
  } catch (...) {
    // best-effort; never let a disk error touch the game loop
  }
  // V2.4: enter the persistent-highlight store (the renderer draws every entry each frame).
  {
    GfxGlobalSettings::MbMark m;
    std::memset(m.lvl, 0, sizeof(m.lvl));
    std::strncpy(m.lvl, lvl.c_str(), sizeof(m.lvl) - 1);
    m.sys = r.system;
    m.row = g_mb_target_row;
    m.tri = hs.tri;
    std::memcpy(m.v, hs.v, sizeof(m.v));
    std::memcpy(m.nrm, hs.nrm, sizeof(m.nrm));
    std::lock_guard<std::mutex> lk(gs.mb_marks_mu);
    gs.mb_marks_store.push_back(m);
    gs.mb_marks_gen++;
    gs.mb_marks_active.store((int)gs.mb_marks_store.size(), std::memory_order_relaxed);
  }
  g_mb_marks = (u64)gs.mb_marks_active.load(std::memory_order_relaxed);
  return g_mb_marks;
}

// Runtime proof counters, written by the render thread. This is how a toggle DEMONSTRATES
// on->off->on instead of merely claiming it (two V1 toggles shipped dead; never again).
// field: 0 hidden draws, 1 checker draws, 2 gizmo passes, 3 gizmo faces (all monotonic).
// V2.1 adds the PER-FRAME published counters (owner: every toggle dead — only a per-frame count
// can show the target's submitted draws hitting ZERO while hidden):
// 4 target draws submitted last frame, 5 checker binds last frame, 6 gizmo line prims last frame,
// 7 the relief factor (x100) the PBR uniforms were pushed with last frame.
u64 pc_mb_rt_geti(s32 field) {
  const auto& gs = Gfx::g_global_settings;
  switch (field) {
    case 0:
      return gs.mb_ctr_hidden_draws;
    case 1:
      return gs.mb_ctr_checker_draws;
    case 2:
      return gs.mb_ctr_gizmo_draws;
    case 3:
      return gs.mb_ctr_gizmo_faces;
    case 4:
      return gs.mb_frame_target_draws;
    case 5:
      return gs.mb_frame_checker_binds;
    case 6:
      return gs.mb_frame_gizmo_prims;
    case 7:
      return gs.mb_frame_relief_x100;
    // V2.2 (owner: Square must engage the FULL checker material; gizmos must be ON SCREEN):
    // 8 full checker-set binds (normal+rough+height) on the target's draws last frame,
    // 9 target draws submitted on the TESS program last frame (displacement path TAKEN),
    // 10 framebuffer pixels the gizmo pass actually changed last frame (readback proof).
    case 8:
      return gs.mb_frame_checker_full;
    case 9:
      return gs.mb_frame_target_tess;
    case 10:
      return gs.mb_frame_gizmo_px;
    // V2.3: 11 wireframe edges drawn last frame, 12 hovered triangle ordinal (-1 = none),
    // 13 ACTIVE polygon marks (V2.4: unmarking decrements — no longer a session total).
    case 11:
      return gs.mb_frame_wire;
    case 12: {
      MbHoverSnap hs;
      return mb_hover_read(&hs) ? hs.tri : -1;
    }
    case 13:
      return (s64)g_mb_marks;
    // V2.4: 14 marked triangles DRAWN last frame by the persistent-highlight pass (the proof is
    // 14 == 13 while the browser is open), 15 depth-test samples that PASSED in the gizmo
    // visible sub-pass last frame (GL_SAMPLES_PASSED occlusion query; falls with occlusion).
    case 14:
      return gs.mb_frame_marked;
    case 15:
      return gs.mb_frame_gizmo_occ;
    // V2.5: 16 = file marks for the CURRENT levels skipped at the last reload because the store
    // was full (oldest lines in the file win). >0 makes the HUD say so (owner feedback rule).
    // V2.6: the store is dynamic; only the 1M sanity bound can fill it, and live marks refused
    // at that bound also land here so the refusal is announced on screen, never silent.
    case 16:
      return (s64)g_mb_marks_skipped;
    // V2.6-bis isolation proof: 17 TFRAG+TIE color draws submitted for NON-target meshes last
    // frame (isolation ON must drive it to 0), 18 render work suppressed by isolation last frame
    // (per-draw skips + one per world-renderer early-out).
    case 17:
      return gs.mb_frame_nontarget_draws;
    case 18:
      return gs.mb_frame_isolated_skips;
    default:
      return 0;
  }
}

// ===============================================================================================
// Grecharged-mesh-browser REOPEN (owner, 2026-07-29: "C'est impossible a parcourir via le tactile")
//
// WHY THIS EXISTS. The browser shipped "touch-capable" and was unusable on the only device the
// owner has. The cause is structural, not a tuning miss: the ONLY touch signal that reached GOAL
// was pc-get-touch-tap, which carries a single TAP EDGE and nothing else — no finger-down/up state,
// no motion, no second finger (android/gk_android_main.cpp: g_menu_tap_{x,y,seq}). With taps alone a
// 3613-row list cannot be scrolled at all and the 3D view cannot be orbited or zoomed. Worse, the
// overlay only forwards those taps while NativeGk.isInMenu() is true, and the browser runs in
// master-mode 'game — so in practice NO touch reached the browser whatsoever.
//
// This block is the missing channel: a small gesture recogniser fed with RAW multi-touch from the
// Android overlay (TouchOverlayView -> NativeGk.onBrowserTouch -> pc_mb_touch_event) and read once
// per frame by GOAL. It recognises finger-drag (with velocity for inertia), two-finger pinch,
// two-finger drag, and taps, and it counts every event so a device run can PROVE the chain.
//
// WHY IT LIVES HERE. jak1/kmachine.cpp is compiled into BOTH the desktop and the Android builds and
// its make_function_symbol_from_c registrations execute on both (InitMachine_PCPort <-
// InitMachineScheme <- InitHeapAndSymbol, reached on Android via android_runtime_full.cpp). One
// registration site therefore binds these builtins everywhere. Putting them in common/kmachine.cpp
// instead would bind them on desktop ONLY — android_runtime_compat.cpp deliberately skips that
// file's registrations, which is the trap pc-get-touch-tap has to work around with a second
// hand-written binding.
//
// COSTS NOTHING WHEN CLOSED: Java only calls pc_mb_touch_event while GOAL has raised the active
// flag (pc-mb-set-active!), which only the browser sets, and which it clears on close.
// ===============================================================================================
namespace {
// A tap is a press that stayed still and short. Anything else is a drag (and may fling).
constexpr double kMbTapMaxMove = 0.03;   // fraction of the screen, summed |dx|+|dy|
constexpr int64_t kMbTapMaxMs = 500;
constexpr double kMbFlingMinVel = 0.20;  // screen-fractions/second below which we don't fling

int64_t mb_now_ms() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

struct MbTouch {
  std::mutex m;
  std::atomic<int> active{0};  // GOAL raised the browser flag (read by JNI, no lock)

  int fingers = 0;
  // previous sample, per gesture kind (invalidated when the finger count changes so a
  // finger going down or up never injects a bogus jump delta)
  bool have_prev1 = false;
  double prev_x = 0, prev_y = 0;
  bool have_prev2 = false;
  double prev_dist = 0, prev_cx = 0, prev_cy = 0;

  // accumulated since the last GOAL poll (consumed by pc_mb_touch_poll)
  double acc_dx = 0, acc_dy = 0, acc_pinch = 0, acc_2dx = 0, acc_2dy = 0;

  // press bookkeeping, for the tap / fling decision at release
  double down_x = 0, down_y = 0, moved = 0;
  int64_t down_ms = 0, last_ms = 0;
  double vel_y = 0;  // low-passed vertical velocity, screen-fractions/second

  // monotonic edges GOAL watches (it never has to see the event, only that one happened)
  uint32_t down_seq = 0, up_seq = 0, tap_seq = 0;
  double tap_x = 0, tap_y = 0;
  double fling_v = 0;  // latched at the release that ended a drag

  // evidence counters — these are what a device run reads back to prove gestures arrived
  uint64_t n_events = 0, n_taps = 0, n_drags = 0, n_pinches = 0, n_flings = 0;
};
MbTouch g_mb;

// The per-frame snapshot. GOAL latches once (pc-mb-touch-poll!) then reads fields freely, so the
// deltas can be consumed exactly once and every getter in a frame sees a consistent gesture.
struct MbTouchFrame {
  int fingers = 0, x = 0, y = 0, dx = 0, dy = 0, pinch = 0, d2x = 0, d2y = 0;
  int tap_x = 0, tap_y = 0, down_x = 0, down_y = 0, fling = 0;
  uint32_t tap_seq = 0, down_seq = 0, up_seq = 0;
  uint64_t n_events = 0, n_taps = 0, n_drags = 0, n_pinches = 0, n_flings = 0;
};
MbTouchFrame g_mb_frame;

inline int mb_q(double normalized) {
  // normalized screen fraction -> the 0..10000 fixed-point GOAL already uses for touch
  return (int)std::lround(normalized * 10000.0);
}
}  // namespace

// Raw multi-touch in, from the Android UI thread. `action`: 0 DOWN, 1 MOVE, 2 UP, 3 CANCEL.
// `n` is the number of pointers still down AFTER this event (so the final UP reports 0).
// Coordinates are normalized [0,1] over the view. Called from JNI only; a no-op everywhere else,
// which is why the desktop build links and runs unchanged with an all-zero gesture state.
extern "C" void pc_mb_touch_event(int action, int n, float x0, float y0, float x1, float y1) {
  std::lock_guard<std::mutex> lk(g_mb.m);
  const int64_t now = mb_now_ms();
  g_mb.n_events++;

  switch (action) {
    case 0: {  // DOWN
      if (n <= 1) {
        g_mb.down_x = x0;
        g_mb.down_y = y0;
        g_mb.down_ms = now;
        g_mb.moved = 0;
        g_mb.vel_y = 0;
        g_mb.down_seq++;
        g_mb.prev_x = x0;
        g_mb.prev_y = y0;
        g_mb.have_prev1 = true;
      } else {
        // a second finger landed: end the one-finger drag cleanly, start the pinch fresh
        g_mb.have_prev1 = false;
      }
      g_mb.have_prev2 = false;
      g_mb.last_ms = now;
      g_mb.fingers = n;
      break;
    }
    case 1: {  // MOVE
      g_mb.fingers = n;
      if (n >= 2) {
        const double dist = std::hypot((double)x1 - x0, (double)y1 - y0);
        const double cx = 0.5 * ((double)x0 + x1), cy = 0.5 * ((double)y0 + y1);
        if (g_mb.have_prev2) {
          const double dd = dist - g_mb.prev_dist;
          g_mb.acc_pinch += dd;
          g_mb.acc_2dx += cx - g_mb.prev_cx;
          g_mb.acc_2dy += cy - g_mb.prev_cy;
          if (std::fabs(dd) > 0.002) {
            g_mb.n_pinches++;
          }
        }
        g_mb.prev_dist = dist;
        g_mb.prev_cx = cx;
        g_mb.prev_cy = cy;
        g_mb.have_prev2 = true;
        g_mb.have_prev1 = false;  // one-finger drag is suppressed while two are down
      } else if (n == 1) {
        if (g_mb.have_prev1) {
          const double ddx = (double)x0 - g_mb.prev_x, ddy = (double)y0 - g_mb.prev_y;
          g_mb.acc_dx += ddx;
          g_mb.acc_dy += ddy;
          g_mb.moved += std::fabs(ddx) + std::fabs(ddy);
          const double dt = (double)(now - g_mb.last_ms) / 1000.0;
          if (dt > 0.001) {
            // low-pass so one jittery sample can't launch a wild fling
            g_mb.vel_y = 0.5 * g_mb.vel_y + 0.5 * (ddy / dt);
          }
          if (std::fabs(ddx) + std::fabs(ddy) > 0.0005) {
            g_mb.n_drags++;
          }
        }
        g_mb.prev_x = x0;
        g_mb.prev_y = y0;
        g_mb.have_prev1 = true;
        g_mb.have_prev2 = false;
      }
      g_mb.last_ms = now;
      break;
    }
    case 2:    // UP
    case 3: {  // CANCEL
      if (n <= 0) {
        // the gesture ended: it was either a tap (still + short) or a drag that may fling
        if (action == 2 && g_mb.moved < kMbTapMaxMove && (now - g_mb.down_ms) < kMbTapMaxMs) {
          g_mb.tap_x = g_mb.down_x;
          g_mb.tap_y = g_mb.down_y;
          g_mb.tap_seq++;
          g_mb.n_taps++;
        } else if (action == 2 && std::fabs(g_mb.vel_y) > kMbFlingMinVel) {
          g_mb.fling_v = g_mb.vel_y;
          g_mb.n_flings++;
        }
        g_mb.vel_y = 0;
      }
      // Only a gesture that ENDED raises the up edge. ACTION_POINTER_UP fires with fingers still
      // down (lifting one of two during a pinch); raising the edge there made GOAL end the drag
      // mid-pinch, which felt like the zoom "letting go" halfway.
      if (n <= 0) {
        g_mb.up_seq++;
      }
      g_mb.fingers = n < 0 ? 0 : n;
      g_mb.have_prev1 = false;
      g_mb.have_prev2 = false;
      g_mb.last_ms = now;
      break;
    }
    default:
      break;
  }
}

// What mode is the browser in? Read by the Android overlay (JNI) to decide touch routing.
// V2: the raw MODE, no longer a bool — 0 closed, 1 list-UI (raw touch to the gesture channel),
// 2 FREECAM (touch stays on the virtual gamepad + look area). Existing Java treats nonzero as
// "browser active", which remains correct until the overlay learns mode 2.
extern "C" int pc_mb_is_active() {
  return g_mb.active.load(std::memory_order_acquire);
}

// GOAL sets the mode. 0 restores the normal virtual-gamepad routing exactly.
void pc_mb_set_active(u32 on) {
  g_mb.active.store((int)on, std::memory_order_release);
  // V2.2: an OPEN browser forces the Recharged path on (recharged_master_active, gfx.h) — the
  // owner previews PBR/tess in the browser even when the master perf-toggle is saved OFF.
  // Closed -> false: the normal path is untouched by the tool.
  Gfx::g_global_settings.mb_pbr_override = (on != 0);
  // V2.6-bis: closing the browser restores the world (isolation must never outlive the tool).
  if (on == 0) {
    Gfx::g_global_settings.mb_isolate = false;
  }
  // V2.5: every browser open resumes the previous marking session. If the pick levels are
  // already published this reloads now; otherwise it stays pending for pc_mb_pick_levels
  // (the GOAL open/freecam-entry paths publish the active levels right after this call).
  if (on != 0) {
    g_mb_marks_reload_pending = true;
    mb_marks_reload_maybe();
  }
}

// Latch one frame of gesture state and CONSUME the accumulated deltas. Returns the finger count.
s64 pc_mb_touch_poll() {
  std::lock_guard<std::mutex> lk(g_mb.m);
  g_mb_frame.fingers = g_mb.fingers;
  g_mb_frame.x = mb_q(g_mb.prev_x);
  g_mb_frame.y = mb_q(g_mb.prev_y);
  g_mb_frame.dx = mb_q(g_mb.acc_dx);
  g_mb_frame.dy = mb_q(g_mb.acc_dy);
  g_mb_frame.pinch = mb_q(g_mb.acc_pinch);
  g_mb_frame.d2x = mb_q(g_mb.acc_2dx);
  g_mb_frame.d2y = mb_q(g_mb.acc_2dy);
  g_mb_frame.tap_seq = g_mb.tap_seq;
  g_mb_frame.down_seq = g_mb.down_seq;
  g_mb_frame.up_seq = g_mb.up_seq;
  g_mb_frame.tap_x = mb_q(g_mb.tap_x);
  g_mb_frame.tap_y = mb_q(g_mb.tap_y);
  g_mb_frame.down_x = mb_q(g_mb.down_x);
  g_mb_frame.down_y = mb_q(g_mb.down_y);
  g_mb_frame.fling = mb_q(g_mb.fling_v);
  g_mb_frame.n_events = g_mb.n_events;
  g_mb_frame.n_taps = g_mb.n_taps;
  g_mb_frame.n_drags = g_mb.n_drags;
  g_mb_frame.n_pinches = g_mb.n_pinches;
  g_mb_frame.n_flings = g_mb.n_flings;
  // consumed exactly once
  g_mb.acc_dx = g_mb.acc_dy = g_mb.acc_pinch = g_mb.acc_2dx = g_mb.acc_2dy = 0;
  g_mb.fling_v = 0;
  return g_mb_frame.fingers;
}

// Field getter over the latched frame. Field ids mirror the MB_T_* constants in mesh-browser-pc.gc.
s64 pc_mb_touch_geti(u32 field) {
  switch (field) {
    case 0: return g_mb_frame.fingers;
    case 1: return g_mb_frame.x;
    case 2: return g_mb_frame.y;
    case 3: return g_mb_frame.dx;
    case 4: return g_mb_frame.dy;
    case 5: return g_mb_frame.pinch;
    case 6: return g_mb_frame.d2x;
    case 7: return g_mb_frame.d2y;
    case 8: return (s64)g_mb_frame.tap_seq;
    case 9: return g_mb_frame.tap_x;
    case 10: return g_mb_frame.tap_y;
    case 11: return (s64)g_mb_frame.up_seq;
    case 12: return g_mb_frame.fling;
    case 13: return (s64)g_mb_frame.down_seq;
    case 14: return g_mb_frame.down_x;
    case 15: return g_mb_frame.down_y;
    case 16: return (s64)g_mb_frame.n_events;
    case 17: return (s64)g_mb_frame.n_taps;
    case 18: return (s64)g_mb_frame.n_drags;
    case 19: return (s64)g_mb_frame.n_pinches;
    case 20: return (s64)g_mb_frame.n_flings;
    default: return 0;
  }
}

// ---- browser state dump ------------------------------------------------------------------------
// files/mesh_browser_state.txt: the browser's OBSERVABLE state, written only while it is open and
// only when something changed. This is what makes the touch claim falsifiable — inject a gesture,
// read the file, and the state either moved or it did not. It doubles as the owner's copy-out
// (he has no adb, but the supervisor can read it back for him).
namespace {
std::string g_mb_state_body;
}

void pc_mb_state_begin() {
  g_mb_state_body.clear();
}

void pc_mb_state_line(u32 str_ptr) {
  if (!str_ptr) {
    return;
  }
  auto* gs = Ptr<String>(str_ptr).c();
  g_mb_state_body += gs->data();
  g_mb_state_body += '\n';
}

void pc_mb_state_end() {
  try {
    uint64_t ev, tp, dr, pn, fl;
    {
      std::lock_guard<std::mutex> lk(g_mb.m);
      ev = g_mb.n_events;
      tp = g_mb.n_taps;
      dr = g_mb.n_drags;
      pn = g_mb.n_pinches;
      fl = g_mb.n_flings;
    }
    g_mb_state_body += fmt::format(
        "touch_events={} taps={} drags={} pinches={} flings={} marks={} marks_file={}\n", ev, tp,
        dr, pn, fl, g_mb_marks, g_mb_marks_path.empty() ? "-" : g_mb_marks_path);
    file_util::write_text_file(file_util::get_jak_project_dir() / "mesh_browser_state.txt",
                               g_mb_state_body);
  } catch (...) {
    // best-effort; a disk error must never touch the game loop
  }
}

void InitMachine_PCPort() {
  // PC Port added functions
  init_common_pc_port_functions(
      make_function_symbol_from_c,
      [](const char* name) {
        const auto result = intern_from_c(name);
        InternFromCInfo info{};
        info.offset = result.offset;
        return info;
      },
      make_string_from_c);

  // Game specific functions
  // Called from the game thread at each frame to tell the PC rendering code which levels to start
  // loading. The loader internally handles locking.
  make_function_symbol_from_c("__pc-set-levels", (void*)pc_set_levels);

  // Grecharged-grass-poc bridges (jak1 only)
  make_function_symbol_from_c("pc-set-recharged-grass!", (void*)pc_set_recharged_grass);
  // Grecharged-master-toggle: GLOBAL Recharged ON/OFF master (single effective-flag helper
  // Gfx::recharged_active composes it at every feature gate)
  make_function_symbol_from_c("pc-set-recharged-master!", (void*)pc_set_recharged_master);
  // External-asset-root: runtime custom texture replacements toggle
  make_function_symbol_from_c("pc-set-load-custom-assets!", (void*)pc_set_load_custom_assets);
  make_function_symbol_from_c("pc-set-recharged-textures!", (void*)pc_set_recharged_textures);
#ifdef OG_FEAT_GRASS_OVERHANG
  // Grecharged-grass-overhang: 3D drooping edge-grass toggle
  make_function_symbol_from_c("pc-set-grass-overhang!", (void*)pc_set_grass_overhang);
#endif
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: runtime toggle + mood/TOD sun push
  make_function_symbol_from_c("pc-set-pbr!", (void*)pc_set_pbr);
  // Grecharged-materials-modern-parity: MODERN MATERIALS master (default OFF == stock)
  make_function_symbol_from_c("pc-set-modern-materials!", (void*)pc_set_modern_materials);
  make_function_symbol_from_c("pc-set-pbr-sun!", (void*)pc_set_pbr_sun);
  make_function_symbol_from_c("pc-set-pbr-sky-sun!", (void*)pc_set_pbr_sky_sun);
  make_function_symbol_from_c("pc-set-pbr-green-sun!", (void*)pc_set_pbr_green_sun);
  make_function_symbol_from_c("pc-set-pbr-lights!", (void*)pc_set_pbr_lights);
  // Grecharged-realtime-lighting: SUN-ONLY realtime lighting master
  make_function_symbol_from_c("pc-set-rt-light!", (void*)pc_set_rt_light);
  make_function_symbol_from_c("pc-set-rt-shadow-res!", (void*)pc_set_rt_shadow_res);
  make_function_symbol_from_c("pc-set-rt-shadow-dist!", (void*)pc_set_rt_shadow_dist);
  make_function_symbol_from_c("pc-set-rt-shadow-strength!", (void*)pc_set_rt_shadow_strength);
  // Grecharged-directional-ambient: hemisphere ambient enable + base strength
  make_function_symbol_from_c("pc-set-rt-ambient!", (void*)pc_set_rt_ambient);
  make_function_symbol_from_c("pc-set-rt-ambient-strength!", (void*)pc_set_rt_ambient_strength);
  // REOPEN #2 menu sliders: PBR TEXTURE RELIEF + SPECULAR INTENSITY
  make_function_symbol_from_c("pc-set-pbr-texture-relief!", (void*)pc_set_pbr_texture_relief);
  make_function_symbol_from_c("pc-set-pbr-specular-intensity!",
                              (void*)pc_set_pbr_specular_intensity);
  // REOPEN #3: DISPLACEMENT carousel (Off/Parallax/Tessellation)
  make_function_symbol_from_c("pc-set-pbr-displacement!", (void*)pc_set_pbr_displacement);
  // REOPEN #10: PBR ISOLATE carousel (in-menu term bisection: Both/NM-only/Parallax-only/Neither)
  make_function_symbol_from_c("pc-set-pbr-isolate!", (void*)pc_set_pbr_isolate);
  make_function_symbol_from_c("pc-set-rt-ambient-contrast!", (void*)pc_set_rt_ambient_contrast);
  make_function_symbol_from_c("pc-set-rt-ambient-model!", (void*)pc_set_rt_ambient_model);
  make_function_symbol_from_c("pc-set-follow-probe!", (void*)pc_set_follow_probe);
#endif
  // Grecharged-foliage-wind: light-wind sway toggle (palms via TIE + shrubs)
  make_function_symbol_from_c("pc-set-foliage-wind!", (void*)pc_set_foliage_wind);
  // Grecharged-title-logo-fullres: CRISP TITLE LOGO toggle (native-res title/boot logo draw)
  make_function_symbol_from_c("pc-set-crisp-title-logo!", (void*)pc_set_crisp_title_logo);
  // Grecharged-mesh-browser: the debug mesh-browser back end (index load + row getters + checker
  // toggle + identifier export). See the block above InitMachine_PCPort.
  make_function_symbol_from_c("pc-mesh-index-load!", (void*)pc_mesh_index_load);
  make_function_symbol_from_c("pc-mesh-index-count", (void*)pc_mesh_index_count);
  make_function_symbol_from_c("pc-mesh-index-geti", (void*)pc_mesh_index_geti);
  make_function_symbol_from_c("pc-mesh-index-getf", (void*)pc_mesh_index_getf);
  make_function_symbol_from_c("pc-mesh-index-name!", (void*)pc_mesh_index_name);
  make_function_symbol_from_c("pc-mesh-index-level!", (void*)pc_mesh_index_levelname);
  make_function_symbol_from_c("pc-set-mesh-browser-checker!", (void*)pc_set_mesh_browser_checker);
  make_function_symbol_from_c("pc-mesh-browser-export!", (void*)pc_mesh_browser_export);
  // REOPEN (owner 2026-07-29 "impossible a parcourir via le tactile"): the real gesture channel.
  // pc-get-touch-tap carries a tap edge and nothing else, so swipe/drag/pinch/fling were not
  // merely unbound, they had no data source at all. These bind on desktop AND Android from here.
  make_function_symbol_from_c("pc-mb-set-active!", (void*)pc_mb_set_active);
  make_function_symbol_from_c("pc-mb-touch-poll!", (void*)pc_mb_touch_poll);
  make_function_symbol_from_c("pc-mb-touch-geti", (void*)pc_mb_touch_geti);
  make_function_symbol_from_c("pc-mb-state-begin!", (void*)pc_mb_state_begin);
  make_function_symbol_from_c("pc-mb-state-line!", (void*)pc_mb_state_line);
  make_function_symbol_from_c("pc-mb-state-end!", (void*)pc_mb_state_end);
  // V2 freecam: reticle ray pick over up to two levels' index AABBs + the target channel into
  // g_global_settings (hide/checker/gizmos per targeted mesh) + the runtime proof counters.
  make_function_symbol_from_c("pc-mb-pick-levels!", (void*)pc_mb_pick_levels);
  make_function_symbol_from_c("pc-mb-pick!", (void*)pc_mb_pick);
  make_function_symbol_from_c("pc-mb-pick-ready?", (void*)pc_mb_pick_ready);
  make_function_symbol_from_c("pc-mb-pick-geti", (void*)pc_mb_pick_geti);
  make_function_symbol_from_c("pc-mb-target-set!", (void*)pc_mb_target_set);
  make_function_symbol_from_c("pc-mb-target-clear!", (void*)pc_mb_target_clear);
  make_function_symbol_from_c("pc-mb-hide-set!", (void*)pc_mb_hide_set);
  make_function_symbol_from_c("pc-mb-checker-set!", (void*)pc_mb_checker_set);
  make_function_symbol_from_c("pc-mb-gizmos-set!", (void*)pc_mb_gizmos_set);
  make_function_symbol_from_c("pc-mb-isolate-set!", (void*)pc_mb_isolate_set);
  make_function_symbol_from_c("pc-mb-rt-geti", (void*)pc_mb_rt_geti);
  // V2.3: hover ray (render thread answers with the exact polygon under the reticle) + the
  // polygon-mark JSONL export for offline orientation forensics.
  make_function_symbol_from_c("pc-mb-hover-ray!", (void*)pc_mb_hover_ray);
  make_function_symbol_from_c("pc-mb-mark-poly!", (void*)pc_mb_mark_poly);
  // Grecharged-ambient-occlusion: AO algorithm (off/SSAO/HBAO/GTAO) + quality selector
  make_function_symbol_from_c("pc-set-ambient-occlusion!", (void*)pc_set_ambient_occlusion);
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models: enhanced (jak2 HD) character-models toggle + availability query
  make_function_symbol_from_c("pc-set-recharged-enhanced-models!", (void*)pc_set_recharged_enhanced_models);
  make_function_symbol_from_c("pc-enhanced-models-available?", (void*)pc_get_enhanced_models_available);
  // Grecharged-hd-models4: per-actor coverage — companion pid -> driver pid registry in Merc2
  make_function_symbol_from_c("pc-hd-cover!", (void*)pc_hd_cover);
  make_function_symbol_from_c("pc-hd-uncover!", (void*)pc_hd_uncover);
#endif
#ifdef OG_FEAT_PHYSICS
  // Grecharged-secondary-motion: chain-physics toggle + the data-driven parameter queries.
  // Every value query returns MILLI-units (x1000) as an s64 — no floats cross this boundary.
  make_function_symbol_from_c("pc-set-physics!", (void*)pc_set_physics);
  make_function_symbol_from_c("pc-physics-reload", (void*)pc_physics_reload);
  make_function_symbol_from_c("pc-physics-generation", (void*)pc_physics_generation);
  make_function_symbol_from_c("pc-physics-joint-role", (void*)pc_physics_joint_role);
  make_function_symbol_from_c("pc-physics-chain-param-mi", (void*)pc_physics_chain_param_mi);
  make_function_symbol_from_c("pc-physics-chain-link-radius-mi",
                              (void*)pc_physics_chain_link_radius_mi);
  make_function_symbol_from_c("pc-physics-chain-link-comw-mi",
                              (void*)pc_physics_chain_link_comw_mi);
  make_function_symbol_from_c("pc-physics-chain-link-apex-mi",
                              (void*)pc_physics_chain_link_apex_mi);
  make_function_symbol_from_c("pc-physics-chain-preset-mi",
                              (void*)pc_physics_chain_preset_mi);
  make_function_symbol_from_c("pc-physics-chain-preset-count",
                              (void*)pc_physics_chain_preset_count);
  make_function_symbol_from_c("pc-physics-chain-preset-absent",
                              (void*)pc_physics_chain_preset_absent);
  // (C14) mesh-surface audit inputs: per-link extremal skinned-vertex offsets
  make_function_symbol_from_c("pc-physics-chain-msample-count",
                              (void*)pc_physics_chain_msample_count);
  make_function_symbol_from_c("pc-physics-chain-msample-mi", (void*)pc_physics_chain_msample_mi);
  make_function_symbol_from_c("pc-physics-chain-xmask", (void*)pc_physics_chain_xmask);
  make_function_symbol_from_c("pc-physics-chain-flags", (void*)pc_physics_chain_flags);
  make_function_symbol_from_c("pc-physics-num-chains", (void*)pc_physics_num_chains);
  make_function_symbol_from_c("pc-physics-level-param-mi", (void*)pc_physics_level_param_mi);
  make_function_symbol_from_c("pc-physics-joint-collider-mi", (void*)pc_physics_joint_collider_mi);
  make_function_symbol_from_c("pc-physics-num-colliders", (void*)pc_physics_num_colliders);
  make_function_symbol_from_c("pc-physics-collider-param-mi", (void*)pc_physics_collider_param_mi);
  make_function_symbol_from_c("pc-physics-collider-is-joint", (void*)pc_physics_collider_is_joint);
  make_function_symbol_from_c("pc-physics-collider-is-joint2", (void*)pc_physics_collider_is_joint2);
  // (SPEC 18) body SURFACE sets — the real skinned surface the chains are tested against
  make_function_symbol_from_c("pc-physics-num-bsurf", (void*)pc_physics_num_bsurf);
  make_function_symbol_from_c("pc-physics-bsurf-is-joint", (void*)pc_physics_bsurf_is_joint);
  make_function_symbol_from_c("pc-physics-bsurf-count", (void*)pc_physics_bsurf_count);
  make_function_symbol_from_c("pc-physics-bsurf-mi", (void*)pc_physics_bsurf_mi);
  make_function_symbol_from_c("pc-physics-enabled", (void*)pc_physics_enabled);
#endif
  make_function_symbol_from_c("pc-set-jak-pos!", (void*)pc_set_jak_pos);
  // POLISH#4: adjustable grass view-distances + ledge-grab trample point
  make_function_symbol_from_c("pc-set-grass-dists!", (void*)pc_set_grass_dists);
  make_function_symbol_from_c("pc-get-tod-hour", (void*)pc_get_tod_hour);
  make_function_symbol_from_c("pc-set-jak-ledge!", (void*)pc_set_jak_ledge);
  // ROUND#21d: exact ground-actor world positions for the grass object-clip/trample
  make_function_symbol_from_c("pc-grass-occ-clear!", (void*)pc_grass_occ_clear);
  make_function_symbol_from_c("pc-grass-occ-add!", (void*)pc_grass_occ_add);
  make_function_symbol_from_c("pc-grass-occ-publish!", (void*)pc_grass_occ_publish);
  make_function_symbol_from_c("pc-grass-tramp-break!", (void*)pc_grass_tramp_break);

  make_function_symbol_from_c("pc-discord-rpc-update", (void*)update_discord_rpc);

  // setup string constants
  // TODO - these may be able to be moved into `init_common_pc_port_functions` but it's trickier
  // since they are accessing the Ptr's value
  auto user_dir_path = file_util::get_user_config_dir();
  intern_from_c("*pc-user-dir-base-path*")->value =
      make_string_from_c(user_dir_path.string().c_str());
  auto settings_path = file_util::get_user_settings_dir(g_game_version);
  intern_from_c("*pc-settings-folder*")->value = make_string_from_c(settings_path.string().c_str());
  intern_from_c("*pc-settings-built-sha*")->value = make_string_from_c(build_revision().c_str());
}

// ─── Ginput-replay-determinism (autoport): jak1 providers for the deterministic
//     record/replay harness ────────────────────────────────────────────────────
// The harness indexes records by the game-LOGIC frame (*display*
// actual-frame-counter) RELATIVE to a gameplay ANCHOR (*target* spawned), and
// forces every RNG stream to a fixed seed at the anchor. These reads use the same
// intern_from_c + g_ee_main_mem + s7 #f-guard pattern as the F1 warp / Merc2
// probes; field offsets are the deftype :offset-assert MINUS 4 (the GOAL basic
// type-tag adjustment) — e.g. *display* actual-frame-counter :offset-assert 816 ->
// C++ raw 812 (matches the A38-verified display on-screen 560 -> 556).

// Forward decls: the F1 warp (defined later in this TU) is the deterministic
// gameplay entry for the determinism proof / collision diff. When it is armed, the
// gameplay anchor defers until the warp has actually spawned Jak at Geyser (post
// title + post level-load), so the variable boot/title/load is fully absorbed and
// no title-phase input pollutes the recorded clip.
static bool f1_warp_requested();
static bool s_pad_replay_warp_gameplay = false;  // set true by f1_warp_run after spawn

// Deterministic game-logic frame = *display* actual-frame-counter (int64): +1 per
// UNPAUSED simulated frame, pacing-independent — NOT the render/read counter.
static int64_t pad_replay_logic_frame() {
  u32 disp = intern_from_c("*display*")->value;
  if (disp == 0 || disp == (u32)s7.offset || disp >= (u32)(EE_MAIN_MEM_SIZE - 820)) {
    return 0;
  }
  int64_t fc = 0;
  std::memcpy(&fc, g_ee_main_mem + disp + 812, 8);  // actual-frame-counter (816 - 4)
  return fc;
}

// Gameplay anchor = *target* (Jak) is a live process (non-#f, in EE memory). When
// the F1 warp is the gameplay entry, defer until the warp has spawned Jak at
// Geyser (post title + level-load): *target* is ALSO valid during the title
// (the title-state Jak), so anchoring on bare validity would latch at the title,
// leaving the variable level-load between the anchor and gameplay un-absorbed.
static bool pad_replay_anchor_reached() {
  u32 tgt = intern_from_c("*target*")->value;
  bool tgt_valid = (tgt != 0 && tgt != (u32)s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4));
  if (!tgt_valid) {
    return false;
  }
  if (f1_warp_requested() && !s_pad_replay_warp_gameplay) {
    return false;
  }
  return true;
}

// Force the GOAL-side RNG to a fixed, known state at the anchor (record & replay):
//   *_vu-reg-R_*       — rand-vu's R register (a symbol holding an int); set to a
//                        valid [1.0,2.0) float bit pattern exactly as rand-vu-init.
//   *random-generator* — basic with a uint32 `seed` at obj+0 (:offset-assert 4 -4).
static void pad_replay_force_goal_rng(u32 seed) {
  intern_from_c("*_vu-reg-R_*")->value = (u32)(0x3F800000u | (seed & 0x007FFFFFu));
  u32 rg = intern_from_c("*random-generator*")->value;
  if (rg != 0 && rg != (u32)s7.offset && rg < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 derived = seed ^ 0x9E3779B9u;
    std::memcpy(g_ee_main_mem + rg, &derived, 4);  // seed @ obj+0 (4 - 4)
  }
}

// Force a FIXED game-logic timestep while the harness is armed. *ticks-per-frame*
// (the symbol's int value) only feeds the engine's time-ratio (drawable.gc:979,982)
// and the cosmetic perf bar. Setting it very high makes float-time-ratio
// (= timer-count / *ticks-per-frame*) ~0 < 1.3, so the PC-port clamp pins
// time-ratio to 1.0 EVERY frame: each drawn frame is exactly one 1/60s logic step,
// so the simulation no longer depends on the (variable) real frame duration. Set
// every frame so a mid-run video-mode reset (video.gc) cannot undo it. Default OFF
// — only ever called while the input-replay harness is recording/replaying.
// Gcamera-interp diagnostic: allow replaying recorded INPUT at the REAL device
// timestep (skip the forced constant timestep) so an injected pan plays out under
// the device's actual variable frame pacing (k dithers). This lets us capture the
// per-RENDER-frame camera yaw DURING an active injected pan and show it juders in
// lockstep with the integer time-ratio k (the owner's "jitter only while rotating").
// Enabled by env OG_PAD_REPLAY_REALTIME (x86) or android prop
// debug.opengoal.pad_replay_realtime=1. Default OFF => normal deterministic replay.
static bool pad_replay_realtime_requested() {
  static int cached = -1;
  if (cached < 0) {
    cached = 0;
    const char* e = getenv("OG_PAD_REPLAY_REALTIME");
    if (e && e[0] && e[0] != '0') {
      cached = 1;
    }
#ifdef __ANDROID__
    char pv[8] = {0};
    if (__system_property_get("debug.opengoal.pad_replay_realtime", pv) > 0 && pv[0] != '0') {
      cached = 1;
    }
#endif
  }
  return cached != 0;
}

static void pad_replay_force_timestep() {
  if (pad_replay_realtime_requested()) {
    return;  // real-timestep diagnostic: let the device's variable pacing drive the clock
  }
  intern_from_c("*ticks-per-frame*")->value = 0x40000000;
}

// Gcamera-interp (autoport, owner 2026-07-01): per-logic-frame CAMERA-MATRIX dump
// for the x86-vs-arm64 numerical-divergence localizer. Owner evidence: at a STABLE
// framerate the gameplay camera juders while the world/Jak stay smooth — a suspected
// arm64-specific per-frame numerical divergence in the camera pose. Under the replay
// harness the timestep is forced to 1.0 (one 1/60s logic step per drawn frame), so
// ALL frame-pacing variance is removed and any x86-vs-device delta in this dump is a
// PURE numerical divergence. Dumps *math-camera*'s render pose (trans + camera-rot,
// the exact view matrix the renderer consumes) AND *target*'s control trans as the
// SMOOTH-object reference, so a camera-only divergence is visible in one trace.
// Layout (little-endian floats, backend-agnostic, byte-comparable across x86/arm64):
//   [ 0..15] *math-camera* trans      (4 floats @ mc+844,  deftype offset 848)
//   [16..79] *math-camera* camera-rot (4x4 matrix @ mc+364, deftype offset 368)
//   [80..91] *target* control trans   (3 floats @ ctrl+12), zero if no live target
static void pad_replay_dump_camera() {
  u8 buf[92];
  std::memset(buf, 0, sizeof(buf));
  u32 mc = intern_from_c("*math-camera*")->value;
  if (mc != 0 && mc != (u32)s7.offset && mc < (u32)(EE_MAIN_MEM_SIZE - 0x424)) {
    std::memcpy(buf + 0, g_ee_main_mem + mc + 844, 16);   // trans (position)
    std::memcpy(buf + 16, g_ee_main_mem + mc + 364, 64);  // camera-rot (view rotation)
  }
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt != 0 && tgt != (u32)s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 ctrl = 0;
    std::memcpy(&ctrl, g_ee_main_mem + tgt + 108, 4);  // control (offset 108)
    if (ctrl != 0 && ctrl != (u32)s7.offset && ctrl < (u32)(EE_MAIN_MEM_SIZE - 24)) {
      std::memcpy(buf + 80, g_ee_main_mem + ctrl + 12, 12);  // Jak trans (control offset 12)
    }
  }
  pad_replay::dump_state("CAM", buf, sizeof(buf));
}


/*!
 * Final initialization of the system after the kernel is loaded.
 * This is called from InitHeapAndSymbol at the very end.
 * Exports the last of the functions written in C to the GOAL symbol table
 * If DiskBooting, will load the GAME CGO, containing the engine, and calls "play", the function
 * which should prepare the game engine.
 */
void InitMachineScheme() {
  make_function_symbol_from_c("put-display-env", (void*)PutDisplayEnv);       // used in drawable
  make_function_symbol_from_c("syncv", (void*)sceGsSyncV);                    // used in drawable
  make_function_symbol_from_c("sync-path", (void*)sceGsSyncPath);             // used
  make_function_symbol_from_c("reset-path", (void*)sceGsResetPath);           // used in dma
  make_function_symbol_from_c("reset-graph", (void*)sceGsResetGraph);         // used
  make_function_symbol_from_c("dma-sync", (void*)sceDmaSync);                 // used
  make_function_symbol_from_c("gs-put-imr", (void*)sceGsPutIMR);              // unused
  make_function_symbol_from_c("gs-get-imr", (void*)sceGsGetIMR);              // unused
  make_function_symbol_from_c("gs-store-image", (void*)sceGsExecStoreImage);  // used
  make_function_symbol_from_c("flush-cache", (void*)FlushCache);              // used
  make_function_symbol_from_c("cpad-open", (void*)CPadOpen);                  // used
  make_function_symbol_from_c("cpad-get-data", (void*)CPadGetData);           // used
  // Ginput-replay-determinism (autoport): wire the deterministic record/replay
  // harness to jak1 game state — index by the game-logic frame (*display*
  // actual-frame-counter), anchor on *target* spawn, and force the GOAL RNG
  // (*_vu-reg-R_*, *random-generator*) at the anchor. Backend-agnostic: this runs
  // on x86 and on the arm64 device. No-op unless the harness is armed.
  pad_replay::set_logic_frame_provider(&pad_replay_logic_frame);
  pad_replay::set_anchor_provider(&pad_replay_anchor_reached);
  pad_replay::add_rng_reseed_callback(&pad_replay_force_goal_rng);
  pad_replay::set_timestep_force_callback(&pad_replay_force_timestep);
  // Gcamera-interp (autoport): dump *math-camera* pose per logic frame so a state
  // trace localizes any x86-vs-arm64 camera numerical divergence (no-op unless a
  // trace file is open via OG_PAD_REPLAY_TRACE / debug.opengoal.pad_trace).
  pad_replay::set_state_dump_callback(&pad_replay_dump_camera);
  make_function_symbol_from_c("install-handler", (void*)InstallHandler);      // used
  make_function_symbol_from_c("install-debug-handler", (void*)InstallDebugHandler);       // used
  make_function_symbol_from_c("file-stream-open", (void*)kopen);                          // used
  make_function_symbol_from_c("file-stream-close", (void*)kclose);                        // used
  make_function_symbol_from_c("file-stream-length", (void*)klength);                      // used
  make_function_symbol_from_c("file-stream-seek", (void*)kseek);                          // unused
  make_function_symbol_from_c("file-stream-read", (void*)kread);                          // used
  make_function_symbol_from_c("file-stream-write", (void*)kwrite);                        // used
  make_function_symbol_from_c("scf-get-language", (void*)DecodeLanguage);                 // used
  make_function_symbol_from_c("scf-get-time", (void*)DecodeTime);                         // used
  make_function_symbol_from_c("scf-get-aspect", (void*)DecodeAspect);                     // used
  make_function_symbol_from_c("scf-get-volume", (void*)DecodeVolume);                     // used
  make_function_symbol_from_c("scf-get-territory", (void*)DecodeTerritory);               // used
  make_function_symbol_from_c("scf-get-timeout", (void*)DecodeTimeout);                   // used
  make_function_symbol_from_c("scf-get-inactive-timeout", (void*)DecodeInactiveTimeout);  // used
  make_function_symbol_from_c("dma-to-iop", (void*)dma_to_iop);                           // unused
  make_function_symbol_from_c("kernel-shutdown", (void*)jak1::KernelShutdown);  // used TODO jak1
  make_function_symbol_from_c("aybabtu", (void*)sceCdMmode);                    // used

  InitMachine_PCPort();
  InitSoundScheme();
  intern_from_c("*stack-top*")->value = 0x07ffc000;
  intern_from_c("*stack-base*")->value = 0x07ffffff;
  intern_from_c("*stack-size*")->value = 0x4000;

  if (DiskBoot) {
    intern_from_c("*kernel-boot-message*")->value = intern_from_c(DebugBootMessage).offset;
    intern_from_c("*kernel-boot-mode*")->value = intern_from_c("boot").offset;  // or debug-boot
    intern_from_c("*kernel-boot-level*")->value = intern_from_c(DebugBootLevel).offset;
  }

  // todo remove MasterUseKernel
  if (DiskBoot && MasterUseKernel) {
    *EnableMethodSet = (*EnableMethodSet) + 1;
    load_and_link_dgo_from_c("game", kglobalheap,
                             LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN,
                             0x400000, true);
    *EnableMethodSet = (*EnableMethodSet) - 1;
    using namespace jak1_symbols;
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("engine"), kernel_packages->value);
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("art"), kernel_packages->value);
    kernel_packages->value =
        new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                 make_string_from_c("common"), kernel_packages->value);

    lg::info("calling play");
    call_goal_function_by_name("play");
  }
}

// ─── F1 (Geyser Rock gameplay) deterministic warp ──────────────────────────────
// Env OG_F1_WARP / Android prop debug.opengoal.f1.warp — OFF by default.
//
// Replicates, ONCE on the GOAL kernel thread, the desktop F1 oracle's listener
// command  (start 'play (get-continue-by-name *game-info* "game-start")) .
// The Android build registers Deci2Server with NO socket (android_runtime_full.cpp),
// so the device cannot be driven by the goalc listener the way f1_x86_dump.sh
// drives the desktop oracle. This hook lets the device reach the SAME Geyser Rock
// ('training) "game-start" spawn the x86 oracle measures, so the F1 device-vs-desktop
// position match is a true apples-to-apples physics-settle determinism test — both
// sides bypass the intro cinematic (whose arm64 control-transfer is a separate,
// independently-tracked blocker). Verified on desktop x86 FIRST: with OG_F1_WARP=1
// it must reproduce the listener oracle's settle (-5393129 / 28317 / 4362849).
//
// The explicit-pp C->GOAL trampoline (same one mips2c's jalr uses): runs a GOAL
// function with a caller-chosen process pointer (GOAL reg R13). Needed because
// the plain call_goal hardcodes pp = symbol-table base, which makes `start`'s
// process-spawn deref a garbage parent and SIGSEGV. On arm64 the systemv name is
// a thin wrapper to _call_goal8_asm_arm64 (linux_arm64_runtime_compat.cpp).
extern "C" u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp, u64 st,
                                       void* off);
#if defined(__APPLE__) && defined(__aarch64__)
// macOS has no linux_arm64_runtime_compat.cpp; bind the wrapper here. The
// asm-name declaration matches the .s label exactly (Mach-O would otherwise
// prepend an extra underscore to the C reference).
extern "C" u64 _call_goal8_asm_arm64(void* func,
                                     u64* arg_array,
                                     u64 zero,
                                     u64 pp,
                                     u64 st,
                                     void* off) asm("_call_goal8_asm_arm64");
extern "C" u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp, u64 st,
                                       void* off) {
  return _call_goal8_asm_arm64(func, arg_array, zero, pp, st, off);
}
#endif

// Builds a GOAL-callable trampoline around a C function (jak1/kscheme.cpp). Not
// declared in any header, so forward-declare it here.
Ptr<Function> make_function_from_c(void* func, bool arg3_is_pp);

static bool f1_warp_requested() {
  if (std::getenv("OG_F1_WARP")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.f1.warp", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL (kernel-dispatcher -> reset-and-call) as
// *listener-function*, so it runs with a live current process (pp) on a real
// process stack: the context `start`/`process-spawn` require. GOAL registers are
// NOT preserved across the make_function_from_c trampoline, so re-read everything
// and pass pp explicitly to the _call_goal8 trampoline (plain call_goal would
// reset pp to the symbol-table base, which crashes process-spawn).
static u64 f1_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[F1-WARP] run: *game-info* not ready");
    return 0;
  }
  // Gwarp-dpad (autoport): the continue-point name is overridable (env
  // OG_F1_WARP_CONT / prop debug.opengoal.f1.warp.cont) so device validators
  // can spawn at other continue points — e.g. "training-warp" puts Jak right
  // at the Geyser Rock warp gate to exercise the warp selection UI. Default
  // stays "game-start" (the F1 oracle-match spawn).
  const char* cont_name = "game-start";
  char cont_buf[128] = {0};
#if defined(__ANDROID__)
  // A blank/whitespace prop value (props can't be set truly empty) means
  // "unset" — keep the default.
  if (__system_property_get("debug.opengoal.f1.warp.cont", cont_buf) > 0 &&
      cont_buf[strspn(cont_buf, " \t")] != '\0') {
    cont_name = cont_buf + strspn(cont_buf, " \t");
  }
#endif
  if (const char* e = std::getenv("OG_F1_WARP_CONT")) {
    cont_name = e;
  }
  u64 name = make_string_from_c(cont_name);
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u64 cont = call_method_of_type_arg2(gi, gi_type, 18 /*get-continue-by-name*/, (u32)name, 0);
  lg::info("[F1-WARP] get-continue-by-name(\"{}\") -> #x{:x}", cont_name, (u32)cont);
  if (cont == 0 || cont == (u32)s7.offset) {
    lg::warn("[F1-WARP] continue '{}' not found; warp aborted", cont_name);
    return 0;
  }
  u32 start_fn = intern_from_c("start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {intern_from_c("play").offset, cont, 0, 0, 0, 0, 0, 0};
  u64 tgt = _call_goal8_asm_systemv((void*)(g_ee_main_mem + start_fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
  lg::info("[F1-WARP] (start 'play game-start) -> *target* #x{:x}", (u32)tgt);

  // Deterministic spawn datum. `start`->init-target ran synchronously and set
  // *target*'s position to the game-start continue point; the slide-to-rest that
  // follows over the next ~20 kernel frames carries an arm64 frame-timing variance
  // (the heavy training-level load jitters the game loop), so the SETTLE position
  // is NOT bit-reproducible — but the SPAWN (read here, before any physics frame)
  // is the continue datum, identical on desktop and device. Emit it the same way
  // the Merc2 F1 probe emits F1-STATE (control offset 108 -> trans offset 12), so
  // f1_run.sh can capture this deterministic game-state for the device-vs-desktop
  // match.
  u32 tgt32 = (u32)tgt;
  if (tgt32 != 0 && tgt32 != (u32)s7.offset && tgt32 < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    u32 ctrl = 0;
    std::memcpy(&ctrl, g_ee_main_mem + tgt32 + 108, 4);
    if (ctrl != 0 && ctrl != (u32)s7.offset && ctrl < (u32)(EE_MAIN_MEM_SIZE - 24)) {
      float sx = 0.f, sy = 0.f, sz = 0.f;
      std::memcpy(&sx, g_ee_main_mem + ctrl + 12 + 0, 4);
      std::memcpy(&sy, g_ee_main_mem + ctrl + 12 + 4, 4);
      std::memcpy(&sz, g_ee_main_mem + ctrl + 12 + 8, 4);
      printf("F1-SPAWN tx=%f ty=%f tz=%f\n", sx, sy, sz);
      fflush(stdout);
    }
  }
  // The input-replay harness anchors its recorded clip here: Jak has spawned at
  // Geyser, the title and the variable level-load are behind us.
  s_pad_replay_warp_gameplay = true;
  return tgt;
}

void f1_maybe_warp_to_geyser() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!f1_warp_requested()) {
    return;
  }
  // Readiness: *game-info* bound to a real boxed basic, and `start` bound to a fn.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 start_fn = intern_from_c("start")->value;
  if (start_fn == 0 || start_fn == (u32)s7.offset) {
    return;
  }
  // The spawn machinery `start` -> process-spawn draws from must exist, else the
  // warp derefs uninitialized engine state and crashes. *target-dead-pool* (the
  // :from pool of `start`'s process-spawn) is bound only after engine init, so it
  // is a precise "engine ready for target spawn" gate.
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  // Settle margin: tick count AFTER the engine is ready (the checks above all
  // pass), letting the title attract fully come up before `(start 'play ...)`
  // fires — mirroring the desktop oracle's wait past `link finish: logo`. Tunable
  // via OG_F1_WARP_DELAY (kernel-dispatch ticks); default ~10s @ 60Hz.
  int delay = 600;
  if (const char* d = std::getenv("OG_F1_WARP_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  s_done = true;

  // Hand the warp to the kernel's *listener-function* slot. kernel-dispatcher
  // runs it via `reset-and-call` INSIDE the dispatch frame, on the listener
  // process's own stack and with pp (GOAL reg R13) set to a real process — the
  // exact context `start` -> `process-spawn` requires. A raw C-side call (even
  // _call_goal8 with an explicit pp) runs `start` off the dispatch stack with no
  // live process context and SIGSEGVs in process-spawn. This mirrors the desktop
  // F1 oracle, which warps by sending `(start 'play game-start)` to the same
  // listener-function slot over the goalc socket (unavailable on Android).
  Ptr<Function> warp_fn = make_function_from_c((void*)f1_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[F1-WARP] armed *listener-function* = #x{:x}; kernel will run the warp in-context",
           warp_fn.offset);
}

// ─── GENERIC LEVEL WARP (debug-only zone-sweep tool) ───────────────────────────
// Env OG_LEVEL_WARP=<continue-name> / Android prop debug.opengoal.level.warp=<name>
// — OFF by default (empty/unset). A generalization of f1_maybe_warp_to_geyser: the
// F1 warp hardcodes the "game-start" continue; this reads the continue-point NAME
// from the prop/env so a device build can be warped DIRECTLY into ANY jak1 level by
// its continue name (e.g. "jungle-start", "beach-start", "village2-start", ...) to
// confirm that level LOADS + RUNS crash-free on the real arm64 + GL device — a check
// the qemu link-only sweep structurally cannot make.
//
// Mechanism is byte-for-byte the F1 warp's: on the GOAL kernel thread, via the
// kernel's *listener-function* slot (so it runs with a live process context),
//   (start 'play (get-continue-by-name *game-info* "<name>"))
// the exact listener form the desktop oracle uses. DEBUG-ONLY: the prop is never set
// in the shipped APK, so this body never runs in production. x86 is unaffected unless
// OG_LEVEL_WARP is explicitly exported. goal_src / x86 emitter / gold are untouched.
// Sized independently of PROP_VALUE_MAX (Android-only macro) so the x86 desktop build
// compiles; PROP_VALUE_MAX is 92, 128 covers it and any env value comfortably.
static char s_level_warp_name[128] = {0};

static bool level_warp_requested() {
  if (const char* e = std::getenv("OG_LEVEL_WARP")) {
    if (e[0]) {
      std::strncpy(s_level_warp_name, e, sizeof(s_level_warp_name) - 1);
      s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.level.warp", buf) > 0 && buf[0]) {
    std::strncpy(s_level_warp_name, buf, sizeof(s_level_warp_name) - 1);
    s_level_warp_name[sizeof(s_level_warp_name) - 1] = 0;
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline f1_warp_run uses). Re-reads every symbol and passes pp explicitly.
static u64 level_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[LEVEL-WARP] run: *game-info* not ready");
    return 0;
  }
  u64 name = make_string_from_c(s_level_warp_name);
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u64 cont = call_method_of_type_arg2(gi, gi_type, 18 /*get-continue-by-name*/, (u32)name, 0);
  lg::info("[LEVEL-WARP] get-continue-by-name(\"{}\") -> #x{:x}", s_level_warp_name, (u32)cont);
  if (cont == 0 || cont == (u32)s7.offset) {
    lg::warn("[LEVEL-WARP] continue '{}' not found; warp aborted", s_level_warp_name);
    printf("LEVEL-WARP-FAIL name=%s reason=continue-not-found\n", s_level_warp_name);
    fflush(stdout);
    return 0;
  }
  // Optional spawn-position override — env OG_LEVEL_WARP_POS / prop
  // debug.opengoal.level.warp.pos = "x y z" in METERS. Patches the continue point's
  // trans (and camera-trans by the same delta) in EE memory BEFORE (start 'play ...),
  // so a debug run can spawn Jak at an exact world point (e.g. next to the jungle
  // blue-eco vent) instead of a long blind cpad drive from the continue. DEBUG-ONLY:
  // never set in production; continue-point layout per all-types.gc (trans @16,
  // camera-trans @48; C++ addr = basic ptr + deftype offset - 4).
  {
    char posbuf[128] = {0};
    if (const char* e = std::getenv("OG_LEVEL_WARP_POS")) {
      std::strncpy(posbuf, e, sizeof(posbuf) - 1);
    }
#if defined(__ANDROID__)
    if (!posbuf[0]) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.level.warp.pos", pbuf) > 0 && pbuf[0]) {
        std::strncpy(posbuf, pbuf, sizeof(posbuf) - 1);
      }
    }
#endif
    float mx, my, mz;
    if (posbuf[0] && std::sscanf(posbuf, "%f %f %f", &mx, &my, &mz) == 3) {
      float* trans = (float*)(g_ee_main_mem + (u32)cont + 16 - 4);
      float* cam = (float*)(g_ee_main_mem + (u32)cont + 48 - 4);
      float nx = mx * 4096.f, ny = my * 4096.f, nz = mz * 4096.f;
      float dx = nx - trans[0], dy = ny - trans[1], dz = nz - trans[2];
      lg::info("[LEVEL-WARP] pos override ({} {} {})m: trans ({} {} {}) -> ({} {} {})", mx, my,
               mz, trans[0], trans[1], trans[2], nx, ny, nz);
      trans[0] = nx;
      trans[1] = ny;
      trans[2] = nz;
      cam[0] += dx;
      cam[1] += dy;
      cam[2] += dz;
      printf("LEVEL-WARP-POS name=%s x=%.1f y=%.1f z=%.1f\n", s_level_warp_name, mx, my, mz);
      fflush(stdout);
    }
  }
  u32 start_fn = intern_from_c("start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {intern_from_c("play").offset, cont, 0, 0, 0, 0, 0, 0};
  u64 tgt = _call_goal8_asm_systemv((void*)(g_ee_main_mem + start_fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
  lg::info("[LEVEL-WARP] (start 'play {}) -> *target* #x{:x}", s_level_warp_name, (u32)tgt);
  printf("LEVEL-WARP-SPAWN name=%s target=#x%x\n", s_level_warp_name, (u32)tgt);
  fflush(stdout);
  return tgt;
}

void level_warp_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!level_warp_requested()) {
    return;
  }
  // Readiness: same gate as f1_maybe_warp_to_geyser — *game-info* boxed-basic,
  // `start` bound, and *target-dead-pool* (engine-ready-for-spawn) bound.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 start_fn = intern_from_c("start")->value;
  if (start_fn == 0 || start_fn == (u32)s7.offset) {
    return;
  }
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  // Settle margin after readiness — let the title attract fully come up before the
  // warp fires. Tunable via OG_LEVEL_WARP_DELAY (kernel-dispatch ticks); default ~10s.
  int delay = 600;
  if (const char* d = std::getenv("OG_LEVEL_WARP_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  s_done = true;

  Ptr<Function> warp_fn = make_function_from_c((void*)level_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[LEVEL-WARP] armed *listener-function* = #x{:x} for continue '{}'",
           warp_fn.offset, s_level_warp_name);
}

// ─── TASK CLOSE (Gcrash-rockvillage debug-only repro tool) ──────────────────────
// Closes specific game-task cstages at runtime so a device repro can cross
// task-gated content (e.g. village2-warrior-money=33 restores the swamp pontoons)
// without a listener connection. Gated by env OG_TASK_CLOSE / Android prop
// debug.opengoal.task.close = "<task>[:<status>][,<task>[:<status>]...]"; status
// defaults to 7 = (task-status need-resolution). Fires ONCE on the GOAL kernel
// thread via *listener-function* — same dispatch context as the level warp — with
// a shorter default delay (300 ticks, OG_TASK_CLOSE_DELAY) so a same-boot
// level.warp (default 600) spawns with the task already closed. DEBUG-ONLY:
// never armed in production; goal_src / x86 emitter / gold untouched.
static char s_task_close_spec[128];

#if defined(JAK_SWAMP_CAPTURE)
// Owner swamp-crash capture build (INSTRUMENTATION ONLY). Returns true once
// village2 is loaded AND active — the same 'active status load-boundary.gc:1275
// waits on. Calling level-status (method 25 of level-group) on *level* is safe
// here: task_close_maybe runs on the GOAL kernel thread between dispatch frames
// (kboot.cpp), the identical GOAL-call context the level-warp / task-close
// listener-function hooks already use.
static bool swamp_capture_village2_active() {
  u32 lg_sym = intern_from_c("*level*")->value;  // the level-group object
  if (lg_sym == 0 || lg_sym == (u32)s7.offset) {
    return false;  // *level* not bound yet
  }
  // Gate on close-specific-task! being bound: it is a real function symbol (unlike
  // level-status, which exists only as a level-group METHOD, not a symbol) and it
  // is defined in the same engine load band as the level system + level.gc's
  // level-status method — so its binding proves *level*'s vtable is linked and
  // method 25 is safe to call. It is also exactly the function the task-close hook
  // will invoke, so this readiness check and the runner stay consistent.
  u32 close_fn = intern_from_c("close-specific-task!")->value;
  if (close_fn == 0 || close_fn == (u32)s7.offset) {
    return false;
  }
  Ptr<Type> lg_type(*Ptr<u32>(lg_sym - 4));  // basic type-tag is the word before field-0
  u32 vi2 = intern_from_c("village2").offset;  // 'village2 symbol object
  u64 st = call_method_of_type_arg2(lg_sym, lg_type, 25 /*level-status*/, vi2, 0);
  return st == (u64)intern_from_c("active").offset;
}
#endif

static bool task_close_requested() {
  s_task_close_spec[0] = 0;
  if (const char* e = std::getenv("OG_TASK_CLOSE")) {
    std::strncpy(s_task_close_spec, e, sizeof(s_task_close_spec) - 1);
  }
#if defined(__ANDROID__)
  if (!s_task_close_spec[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.task.close", pbuf) > 0 && pbuf[0]) {
      std::strncpy(s_task_close_spec, pbuf, sizeof(s_task_close_spec) - 1);
    }
  }
#endif
#if defined(JAK_SWAMP_CAPTURE)
  // No env/prop set: auto-close task 33 (village2-warrior-money = 90-orb pontoon
  // restore) so the owner reaches the Rock Village -> Boggy Swamp transition
  // WITHOUT adb and WITHOUT 90 orbs. Only once village2 is active; task_close_maybe
  // latches on its static s_done so this fires exactly once (idempotent — no
  // spam-close every frame).
  if (!s_task_close_spec[0] && swamp_capture_village2_active()) {
    std::strncpy(s_task_close_spec, "33", sizeof(s_task_close_spec) - 1);
  }
#endif
  for (const char* p = s_task_close_spec; *p; ++p) {
    if (*p >= '1' && *p <= '9') {
      return true;  // needs at least one nonzero digit ("", "0", "''" disable)
    }
  }
  return false;
}

static u64 task_close_run() {
  u32 fn = intern_from_c("close-specific-task!")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("TASK-CLOSE-FAIL reason=close-specific-task!-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[128];
  std::strncpy(buf, s_task_close_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  char* save = nullptr;
#ifdef _WIN32
  // no strtok_r on Windows; strtok_s has the same (str, delim, ctx) contract.
#define OG_STRTOK_R strtok_s
#else
#define OG_STRTOK_R strtok_r
#endif
  for (char* tok = OG_STRTOK_R(buf, ",", &save); tok; tok = OG_STRTOK_R(nullptr, ",", &save)) {
    int task = 0;
    int status = 7;  // (task-status need-resolution)
    if (std::sscanf(tok, "%d:%d", &task, &status) < 1 || task <= 0) {
      continue;
    }
    u64 args[8] = {(u64)task, (u64)status, 0, 0, 0, 0, 0, 0};
    u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                    (u64)s7.offset, g_ee_main_mem);
    printf("TASK-CLOSE task=%d status=%d -> #x%x\n", task, status, (u32)r);
    fflush(stdout);
  }
  return 0;
}

void task_close_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!task_close_requested()) {
    return;
  }
  // Readiness: same gate as level_warp_maybe, plus close-specific-task! bound.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 fn = intern_from_c("close-specific-task!")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    return;
  }
  u32 dead_pool = intern_from_c("*target-dead-pool*")->value;
  if (dead_pool == 0 || dead_pool == (u32)s7.offset) {
    return;
  }
  int delay = 300;
  if (const char* d = std::getenv("OG_TASK_CLOSE_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  // don't clobber a pending listener function armed by another hook this tick
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  s_done = true;
  Ptr<Function> f = make_function_from_c((void*)task_close_run, false);
  ListenerFunction->value = f.offset;
  lg::info("[TASK-CLOSE] armed *listener-function* = #x{:x} for spec '{}'", f.offset,
           s_task_close_spec);
}

// ─── WANT-LEVELS / WANT-DISPLAY (Gcrash-rockvillage debug-only repro tool) ──────
// Replays the exact GOAL forms a load-boundary crossing executes, without needing
// Jak to physically cross the polyline: `(load village2 swamp)` boundaries call
// load-state-want-levels, `(display swamp display)` boundaries call
// load-state-want-display-level (load-boundary.gc:1095-1102, check-boundary
// :1364-1378). This reproduces the owner's village2->swamp streaming transition
// (rolling evicted, SWA.DGO streamed mid-play, then displayed) deterministically.
//   env OG_WANT_LEVELS / prop debug.opengoal.want.levels = "lev1,lev2"
//     (fires once at OG_WANT_LEVELS_DELAY ticks, default 900)
//   env OG_WANT_DISPLAY / prop debug.opengoal.want.display = "lev[,sym]"
//     (sym default 'display'; fires once at OG_WANT_DISPLAY_DELAY, default 1800 —
//      after the streaming load has had time to finish, like the owner's walk)
// DEBUG-ONLY: never armed in production; goal_src / x86 emitter / gold untouched.
static char s_want_levels_spec[96];
static char s_want_display_spec[96];

static bool want_prop_requested(const char* env, const char* prop, char* out, size_t out_sz) {
  out[0] = 0;
  if (const char* e = std::getenv(env)) {
    std::strncpy(out, e, out_sz - 1);
    out[out_sz - 1] = 0;
  }
#if defined(__ANDROID__)
  if (!out[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(prop, pbuf) > 0 && pbuf[0]) {
      std::strncpy(out, pbuf, out_sz - 1);
      out[out_sz - 1] = 0;
    }
  }
#endif
  for (const char* p = out; *p; ++p) {
    if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')) {
      return true;  // needs at least one letter ("", "0", "''" disable)
    }
  }
  return false;
}

static u64 want_levels_run() {
  u32 fn = intern_from_c("load-state-want-levels")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-LEVELS-FAIL reason=load-state-want-levels-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[96];
  std::strncpy(buf, s_want_levels_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  char* comma = std::strchr(buf, ',');
  if (!comma) {
    printf("WANT-LEVELS-FAIL reason=need-two-levels spec=%s\n", buf);
    fflush(stdout);
    return 0;
  }
  *comma = 0;
  u32 lev1 = intern_from_c(buf).offset;
  u32 lev2 = intern_from_c(comma + 1).offset;
  u64 args[8] = {lev1, lev2, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-LEVELS lev1=%s lev2=%s -> #x%x\n", buf, comma + 1, (u32)r);
  fflush(stdout);
  return 0;
}

static u64 want_display_run() {
  u32 fn = intern_from_c("load-state-want-display-level")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-DISPLAY-FAIL reason=load-state-want-display-level-unbound\n");
    fflush(stdout);
    return 0;
  }
  char buf[96];
  std::strncpy(buf, s_want_display_spec, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = 0;
  const char* sym = "display";
  char* comma = std::strchr(buf, ',');
  if (comma) {
    *comma = 0;
    sym = comma + 1;
  }
  u32 lev = intern_from_c(buf).offset;
  u32 disp = (std::strcmp(sym, "#f") == 0) ? (u32)s7.offset : intern_from_c(sym).offset;
  u64 args[8] = {lev, disp, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-DISPLAY lev=%s sym=%s -> #x%x\n", buf, sym, (u32)r);
  fflush(stdout);
  return 0;
}

static void want_hook_maybe(const char* env,
                            const char* prop,
                            char* spec,
                            size_t spec_sz,
                            const char* delay_env,
                            int default_delay,
                            u64 (*runner)(),
                            bool* done,
                            int* ticks,
                            const char* tag) {
  if (*done) {
    return;
  }
  if (!want_prop_requested(env, prop, spec, spec_sz)) {
    return;
  }
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 ls = intern_from_c("*load-state*")->value;
  if (ls == 0 || ls == (u32)s7.offset) {
    return;
  }
  int delay = default_delay;
  if (const char* d = std::getenv(delay_env)) {
    delay = atoi(d);
  }
#if defined(__ANDROID__)
  {
    // prop-settable delay: "<prop>.delay" (e.g. debug.opengoal.want.levels.delay)
    char dprop[96];
    snprintf(dprop, sizeof(dprop), "%s.delay", prop);
    char dbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(dprop, dbuf) > 0 && dbuf[0] && atoi(dbuf) > 0) {
      delay = atoi(dbuf);
    }
  }
#endif
  if ((*ticks)++ < delay) {
    return;
  }
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  *done = true;
  Ptr<Function> f = make_function_from_c((void*)runner, false);
  ListenerFunction->value = f.offset;
  lg::info("[{}] armed *listener-function* for spec '{}'", tag, spec);
}

void want_levels_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_LEVELS", "debug.opengoal.want.levels", s_want_levels_spec,
                  sizeof(s_want_levels_spec), "OG_WANT_LEVELS_DELAY", 900, want_levels_run,
                  &s_done, &s_ticks, "WANT-LEVELS");
}

void want_display_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_DISPLAY", "debug.opengoal.want.display", s_want_display_spec,
                  sizeof(s_want_display_spec), "OG_WANT_DISPLAY_DELAY", 1800, want_display_run,
                  &s_done, &s_ticks, "WANT-DISPLAY");
}

// (vis <nick>) boundaries — e.g. (vis vi2 #f) then (vis swa #f) on the crate->swamp
// walk — call load-state-want-vis(nick), switching the active visibility octree.
static char s_want_vis_spec[96];

static u64 want_vis_run() {
  u32 fn = intern_from_c("load-state-want-vis")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    printf("WANT-VIS-FAIL reason=load-state-want-vis-unbound\n");
    fflush(stdout);
    return 0;
  }
  u32 nick = intern_from_c(s_want_vis_spec).offset;
  u64 args[8] = {nick, 0, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  printf("WANT-VIS nick=%s -> #x%x\n", s_want_vis_spec, (u32)r);
  fflush(stdout);
  return 0;
}

void want_vis_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  want_hook_maybe("OG_WANT_VIS", "debug.opengoal.want.vis", s_want_vis_spec,
                  sizeof(s_want_vis_spec), "OG_WANT_VIS_DELAY", 2400, want_vis_run, &s_done,
                  &s_ticks, "WANT-VIS");
}

// ─── PHYS-ROOM (Grecharged-secondary-motion — SPEC §6, étape 1) ─────────────────
// Arms the GOAL entry point `phys-room-start`: the player-less physics test room in
// which the subject (Keira) is spawned alone and driven, so her secondary motion can
// be measured in a zone where Jak is NOT spawned. DEBUG-ONLY: with no env var and no
// Android prop set this code does nothing at all, so it is never armed in production.
static char s_phys_room_spec[96];

// Deliberately NOT want_prop_requested(): that helper requires at least one LETTER in
// the value, so the obvious `OG_PHYS_ROOM=1` would silently never arm (the trap that
// would cost a whole run). Here any non-empty value other than "0" arms the hook.
static bool phys_room_requested(const char* env, const char* prop, char* out, size_t out_sz) {
  out[0] = 0;
  if (const char* e = std::getenv(env)) {
    std::strncpy(out, e, out_sz - 1);
    out[out_sz - 1] = 0;
  }
#if defined(__ANDROID__)
  if (!out[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(prop, pbuf) > 0 && pbuf[0]) {
      std::strncpy(out, pbuf, out_sz - 1);
      out[out_sz - 1] = 0;
    }
  }
#endif
  return out[0] != 0 && std::strcmp(out, "0") != 0;
}

static u64 phys_room_run() {
  u32 fn = intern_from_c("phys-room-start")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    // The GOAL side may not be linked yet: fail loudly, never crash.
    printf("PHYS-ROOM-FAIL reason=phys-room-start-unbound\n");
    fflush(stdout);
    return 0;
  }
  u64 args[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp, (u64)s7.offset,
                                  g_ee_main_mem);
  printf("PHYS-ROOM started -> #x%x\n", (u32)r);
  fflush(stdout);
  return 0;
}

void phys_room_maybe() {
  static bool s_done = false;
  static int s_ticks = 0;
  if (s_done) {
    return;
  }
  if (!phys_room_requested("OG_PHYS_ROOM", "debug.opengoal.phys.room", s_phys_room_spec,
                           sizeof(s_phys_room_spec))) {
    return;
  }
  // Same guards as want_hook_maybe() EXCEPT the *game-info* / *load-state* readiness
  // gate: the room must start from the TITLE SCREEN, with no game session running.
  int delay = 600;
  if (const char* d = std::getenv("OG_PHYS_ROOM_DELAY")) {
    delay = atoi(d);
  }
#if defined(__ANDROID__)
  {
    // prop-settable delay, like want_hook_maybe(): debug.opengoal.phys.room.delay
    char dbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.phys.room.delay", dbuf) > 0 && dbuf[0] &&
        atoi(dbuf) > 0) {
      delay = atoi(dbuf);
    }
  }
#endif
  if (s_ticks++ < delay) {
    return;
  }
  // don't clobber a pending listener function armed by another hook this tick
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  s_done = true;
  Ptr<Function> f = make_function_from_c((void*)phys_room_run, false);
  ListenerFunction->value = f.offset;
  lg::info("[PHYS-ROOM] armed *listener-function* = #x{:x} spec '{}' delay {}", f.offset,
           s_phys_room_spec, delay);
}

// ─── GRV-CANARY (Gcrash-rockvillage debug-only forensic) ────────────────────────
// Watches the TOP 64 bytes of *target*'s main-thread stack (*kernel-dram-stack*
// band) once per kernel dispatch. enter-state branch-3 (gstate.gc:373-380) resets
// SP to stack-top and pushes the return-from-thread-dead HOST address there; the
// repro12 crash RET'd into a bare GOAL offset restored from exactly this band, so
// any write that is NOT the expected trampoline push is the stomp — logged with
// the dispatch tick for frame-resolution bracketing of the writer. Enabled by
// env OG_GRV_CANARY / prop debug.opengoal.grv.canary=1. Read-only observer.
void grv_canary_maybe() {
  static int s_enabled = -1;
  if (s_enabled < 0) {
    s_enabled = 0;
    if (const char* e = std::getenv("OG_GRV_CANARY")) {
      if (e[0] && e[0] != '0') {
        s_enabled = 1;
      }
    }
#if defined(__ANDROID__)
    if (!s_enabled) {
      char pbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.grv.canary", pbuf) > 0 && pbuf[0] == '1') {
        s_enabled = 1;
      }
    }
#endif
  }
  if (!s_enabled) {
    return;
  }
  static bool s_armed = false;
  static u64 s_prev[8];
  static u32 s_band = 0;
  static u64 s_tick = 0;
  static int s_scan_episode = 0;
  s_tick++;
  u32 tgt_sym = intern_from_c("*target*")->value;
  if (tgt_sym == 0 || tgt_sym == (u32)s7.offset || (tgt_sym & OFFSET_MASK) != 4) {
    s_armed = false;
    return;
  }
  u32 mt = *(u32*)(g_ee_main_mem + tgt_sym + 40);       // (-> process main-thread), C off
  if (mt < 0x1000 || mt >= EE_MAIN_MEM_SIZE) {
    s_armed = false;
    return;
  }
  u32 stack_top = *(u32*)(g_ee_main_mem + mt + 28);     // (-> thread stack-top), C off
  if (stack_top < 0x1040 || stack_top >= EE_MAIN_MEM_SIZE) {
    s_armed = false;
    return;
  }
  // Thread-field watch: (-> thread sp) is a 32-bit HEAP field restored into SP by
  // thread-resume; a heap stomp of it resumes target on top of global DATA (the
  // suspected repro12 mechanism: SP=0x1a7ed0 outside the dram arena). Flag any
  // sp/stack-top outside the dram arena band.
  {
    u32 mt_sp = *(u32*)(g_ee_main_mem + mt + 24);
    u32 tt = *(u32*)(g_ee_main_mem + tgt_sym + 44);
    static u32 s_last_bad = 0;
    if (mt_sp && (mt_sp < stack_top - 0x8000 || mt_sp > stack_top) && mt_sp != s_last_bad) {
      s_last_bad = mt_sp;
      printf("GRV-CANARY MT-SP-ANOMALY mt-sp=0x%x stack-top=0x%x tick=%llu\n", mt_sp, stack_top,
             (unsigned long long)s_tick);
      fflush(stdout);
    }
    if (tt >= 0x1000 && tt < EE_MAIN_MEM_SIZE && tt != mt) {
      u32 tt_sp = *(u32*)(g_ee_main_mem + tt + 24);
      u32 tt_top = *(u32*)(g_ee_main_mem + tt + 28);
      static u32 s_last_bad_tt = 0;
      if (tt_sp && tt_top && (tt_sp < tt_top - 0x8000 || tt_sp > tt_top) &&
          tt_sp != s_last_bad_tt) {
        s_last_bad_tt = tt_sp;
        printf("GRV-CANARY TT-SP-ANOMALY tt-sp=0x%x tt-top=0x%x tick=%llu\n", tt_sp, tt_top,
               (unsigned long long)s_tick);
        fflush(stdout);
      }
    }
  }
  u32 band = stack_top - 64;
  u64 cur[8];
  memcpy(cur, g_ee_main_mem + band, 64);
  if (!s_armed || band != s_band) {
    memcpy(s_prev, cur, 64);
    s_armed = true;
    s_band = band;
    u32 rftd = intern_from_c("return-from-thread-dead")->value;
    u32 rft = intern_from_c("return-from-thread")->value;
    printf("GRV-CANARY armed band=0x%x stack-top=0x%x rftd=0x%x rft=0x%x base=%p\n", band,
           stack_top, rftd, rft, (void*)g_ee_main_mem);
    fflush(stdout);
    return;
  }
  // Hot slots (band = stack_top - 64): the state fn's STP frame {X29@top-32=idx4,
  // X30@top-24=idx5} and the enter-state trampoline cell @top-16=idx6. Everything
  // else only matters when a BARE GOAL value (upper32==0) lands in it — host-based
  // fp/ra saves churn constantly and are legit.
  for (int i = 0; i < 8; i++) {
    if (cur[i] != s_prev[i]) {
      bool bare = (cur[i] >> 32) == 0 && cur[i] != 0;
      bool hot = (i >= 4 && i <= 6);
      // Only the host-RA -> bare transition is suspicious: the dram arena is
      // SHARED by post threads, so bare float/GOAL spill churn is legitimate.
      bool was_host = (s_prev[i] >> 32) == 0x7f;
      if ((bare && was_host) || (hot && cur[i] == 0 && was_host)) {
        printf("GRV-CANARY %s off=%d(0x%x) old=%016llx new=%016llx tick=%llu\n",
               hot ? "HOT-ANOMALY" : "BARE-WRITE", i * 8, band + i * 8,
               (unsigned long long)s_prev[i], (unsigned long long)cur[i],
               (unsigned long long)s_tick);
        fflush(stdout);
        s_scan_episode = 10;  // correlate for the next 10 ticks too
        // Seeker correlation: if the intruding value looks like a blend float
        // (~0.9..1.1), scan the camera processes' object spans for the SAME u32 —
        // present = duplicated/misdirected heap write (names the seeker field);
        // absent = the arena slot is the value's only home (pointer fully wrong).
        u32 f32 = (u32)cur[i];
        if (f32 >= 0x3f660000u && f32 <= 0x3f8ccccdu) {
          const char* cams[3] = {"*camera*", "*camera-combiner*", "*camera-base-group*"};
          for (int c = 0; c < 3; c++) {
            u32 cp = intern_from_c(cams[c])->value;
            if (cp < 0x1000 || cp >= EE_MAIN_MEM_SIZE || cp == (u32)s7.offset) {
              continue;
            }
            u32 alloc_len = *(u32*)(g_ee_main_mem + cp + 68);
            u32 span = 116 + (alloc_len < 0x8000 ? alloc_len : 0x2000);
            int hits = 0;
            for (u32 o = 0; o + 4 <= span && hits < 4; o += 4) {
              if (*(u32*)(g_ee_main_mem + cp + o) == f32) {
                printf("GRV-CANARY SEEKER-MATCH %s+0x%x (=0x%x) val=%08x tick=%llu\n", cams[c],
                       o, cp + o, f32, (unsigned long long)s_tick);
                hits++;
              }
            }
            if (hits) {
              fflush(stdout);
            }
          }
        }
      }
      s_prev[i] = cur[i];
    }
  }
  // Episode mode: after an anomaly, keep correlating the live [top-24] float against
  // the camera process spans for a few ticks (single-shot scans race the writer).
  if (s_scan_episode > 0) {
    s_scan_episode--;
    u32 f32 = (u32)cur[5];  // [top-24] = band idx 5
    if (f32 >= 0x3f660000u && f32 <= 0x3f8ccccdu) {
      const char* cams[3] = {"*camera*", "*camera-combiner*", "*camera-base-group*"};
      for (int c = 0; c < 3; c++) {
        u32 cp = intern_from_c(cams[c])->value;
        if (cp < 0x1000 || cp >= EE_MAIN_MEM_SIZE || cp == (u32)s7.offset) {
          continue;
        }
        u32 alloc_len = *(u32*)(g_ee_main_mem + cp + 68);
        u32 span = 116 + (alloc_len < 0x8000 ? alloc_len : 0x2000);
        for (u32 o = 0; o + 4 <= span; o += 4) {
          if (*(u32*)(g_ee_main_mem + cp + o) == f32) {
            printf("GRV-CANARY EPISODE-MATCH %s+0x%x val=%08x tick=%llu\n", cams[c], o, f32,
                   (unsigned long long)s_tick);
            fflush(stdout);
          }
        }
      }
    }
  }
}

// ─── ECO SPHERE SPAWN (Geco-spheres debug-only oracle-diff tool) ────────────────
// Env OG_ECO_SPAWN / Android prop debug.opengoal.eco.spawn =
//   "<pickup-type-int> [period-ticks [dx dy dz]]"  — OFF by default.
// Repeatedly births an eco pickup next to *target* on the GOAL kernel thread,
// replaying the x86 oracle capture's listener form byte-for-byte:
//   (birth-pickup-at-point <vec near target> (pickup-type N) 5.0 #t *entity-pool*
//                          (the-as fact-info #f))
// pickup-type (fact-h.gc): 1=eco-yellow 2=eco-red 3=eco-blue 4=eco-green.
// The device build has no goalc listener, no continue point spawns near a live
// eco, and green eco is tutorial-gated — so this is the only lever that puts an
// eco sphere in-frame on BOTH platforms via the identical mechanism, which the
// per-color device-vs-golden screencap gate requires. Re-fires every period
// ticks (default 300) because an eco birthed outside its level context fades
// after a few seconds. DEBUG-ONLY: the prop is never set in the shipped APK;
// x86 is unaffected unless OG_ECO_SPAWN is explicitly exported.
static int s_eco_spawn_type = 0;
static int s_eco_spawn_period = 300;
static float s_eco_dx = 2.0f, s_eco_dy = 1.0f, s_eco_dz = 2.0f;
// Geco-spheres TEMPORARY diagnostic: last hook-spawned eco pickup's ppointer
// (raw pointer, NOT a basic — a u32 into EE memory), captured in eco_spawn_run
// and consumed by eco_trace_maybe() below. 0 = none yet.
static u32 s_eco_trace_pp = 0;

static bool eco_spawn_requested() {
  char buf[128] = {0};
  if (const char* e = std::getenv("OG_ECO_SPAWN")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.eco.spawn", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  int type = 0, period = 0;
  float dx = 0.f, dy = 0.f, dz = 0.f;
  int n = std::sscanf(buf, "%d %d %f %f %f", &type, &period, &dx, &dy, &dz);
  if (n < 1 || type < 1 || type > 9) {
    return false;
  }
  s_eco_spawn_type = type;
  if (n >= 2 && period > 30) {
    s_eco_spawn_period = period;
  }
  if (n >= 5) {
    s_eco_dx = dx;
    s_eco_dy = dy;
    s_eco_dz = dz;
  }
  return true;
}

// The spawn body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline the warp hooks use): birth-pickup-at-point is a defbehavior, so it
// needs a live process context (pp), which the dispatcher provides.
static u64 eco_spawn_run() {
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || (tgt & OFFSET_MASK) != 4 /*BASIC_OFFSET*/ ||
      tgt >= (u32)(EE_MAIN_MEM_SIZE - 112)) {
    return 0;
  }
  u32 ctrl = 0;
  std::memcpy(&ctrl, g_ee_main_mem + tgt + 108, 4);  // target control (F1-SPAWN layout)
  if (ctrl == 0 || ctrl == (u32)s7.offset || ctrl >= (u32)(EE_MAIN_MEM_SIZE - 24)) {
    return 0;
  }
  float t[3];
  std::memcpy(t, g_ee_main_mem + ctrl + 12, 12);  // control trans
  u32 fn = intern_from_c("birth-pickup-at-point")->value;
  u32 pool = intern_from_c("*entity-pool*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (fn == 0 || fn == (u32)s7.offset || pool == 0 || pool == (u32)s7.offset) {
    return 0;
  }
  static Ptr<u8> s_vec;  // one 16B GOAL vector, allocated once on the global heap
  if (s_vec.offset == 0) {
    s_vec = kmalloc(kglobalheap, 16, KMALLOC_ALIGN_16, "eco-spawn-vec");
    if (s_vec.offset == 0) {
      return 0;
    }
  }
  float* v = (float*)(g_ee_main_mem + s_vec.offset);
  v[0] = t[0] + s_eco_dx * 4096.f;
  v[1] = t[1] + s_eco_dy * 4096.f;
  v[2] = t[2] + s_eco_dz * 4096.f;
  v[3] = 1.0f;
  // GOAL passes float args as raw 32-bit bits in GPRs.
  float amount = 5.0f;
  u32 amount_bits = 0;
  std::memcpy(&amount_bits, &amount, 4);
  u64 args[8] = {s_vec.offset,
                 (u64)s_eco_spawn_type,
                 amount_bits,
                 (u64)(s7.offset + jak1_symbols::FIX_SYM_TRUE),
                 pool,
                 (u64)s7.offset,  // (the-as fact-info #f)
                 0,
                 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + fn), args, 0, (u64)lp, (u64)s7.offset,
                                  g_ee_main_mem);
  // Geco-spheres TEMPORARY diagnostic: remember the ppointer of the just-birthed
  // pickup so eco_trace_maybe() can dump its physics each dispatch. r is the
  // (pointer process) return of birth-pickup-at-point (a raw pointer, not a basic).
  if ((u32)r != 0 && (u32)r != (u32)s7.offset) {
    s_eco_trace_pp = (u32)r;
  }
  printf("ECO-SPAWN type=%d at=%.1f,%.1f,%.1f -> #x%x\n", s_eco_spawn_type, v[0], v[1], v[2],
         (u32)r);
  fflush(stdout);
  return r;
}

void eco_spawn_maybe() {
  if (!eco_spawn_requested()) {
    return;
  }
  // Readiness: *target* alive (a real boxed basic) and birth-pickup-at-point bound.
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || (tgt & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  u32 fn = intern_from_c("birth-pickup-at-point")->value;
  if (fn == 0 || fn == (u32)s7.offset) {
    return;
  }
  // Settle ~2s after target exists (camera lands), then re-fire every period.
  static int s_ticks = 0;
  s_ticks++;
  if (s_ticks < 120 || (s_ticks - 120) % s_eco_spawn_period != 0) {
    return;
  }
  // Never stomp a pending listener form (the kernel resets the slot to #f after
  // running it — kboot.cpp dispatch loop).
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)eco_spawn_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  lg::info("[ECO-SPAWN] armed type={} period={} ticks={}", s_eco_spawn_type, s_eco_spawn_period,
           s_ticks);
}

// ─── TOD-PIN (night A/B test lever) ──────────────────────────────────────────
// Env OG_TOD_HOUR / Android prop debug.opengoal.tod.hour = "<0-23>" — OFF by
// default. Pins the in-game clock: sets *time-of-day-proc*'s hour to the value,
// minute/second/frame to 0, and time-ratio to 0.0 (freezing the clock) so the
// night pose is deterministic for the Gperf-particles night A/B. Latched once
// (parsed on first read like eco_spawn), fires ONCE when the proc is ready.
// GOAL field offsets from decompiler/config/jak1/all-types.gc:8153 (deftype
// time-of-day-proc): hour :offset-assert 128, minute 132, second 136,
// frame 140, time-ratio :offset-assert 148. *time-of-day-proc* is a boxed basic
// (process), so a field write is g_ee_main_mem + proc + (goal_offset - 4),
// exactly like eco_spawn_run's +108 (=112-4 root) / +12 (=16-4 trans) writes.
static int s_tod_hour = -1;

static bool tod_pin_requested() {
  static bool s_parsed = false;
  static bool s_result = false;
  if (s_parsed) {
    return s_result;
  }
  s_parsed = true;
  char buf[16] = {0};
  if (const char* e = std::getenv("OG_TOD_HOUR")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.tod.hour", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  int hour = -1;
  int n = std::sscanf(buf, "%d", &hour);
  if (n < 1 || hour < 0 || hour > 23) {
    return false;
  }
  s_tod_hour = hour;
  s_result = true;
  return true;
}

// The pin body — invoked BY THE KERNEL as *listener-function* (same in-context
// trampoline the eco/warp hooks use). Writes the clock fields of
// *time-of-day-proc* directly in GOAL memory.
static u64 tod_pin_run() {
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod == 0 || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 64)) {
    return 0;
  }
  // *time-of-day-proc* is a ppointer: deref once to get the process basic ptr,
  // then fields live at proc + (deftype_offset - 4). Confirmed by the diagnostic
  // dump: deref+124 held a valid hour and deref+140 the matching time-of-day
  // float; deref is a real basic pointer (& 7 == 4).
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return 0;
  }
  s32 hour = (s32)s_tod_hour;
  s32 zero = 0;
  float ratio = 0.0f;  // freeze the clock (time-ratio 0), like the boundary cmd
  std::memcpy(g_ee_main_mem + proc + 124, &hour, 4);   // hour       (goal 128 - 4)
  std::memcpy(g_ee_main_mem + proc + 128, &zero, 4);   // minute     (goal 132 - 4)
  std::memcpy(g_ee_main_mem + proc + 132, &zero, 4);   // second     (goal 136 - 4)
  std::memcpy(g_ee_main_mem + proc + 136, &zero, 4);   // frame      (goal 140 - 4)
  std::memcpy(g_ee_main_mem + proc + 144, &ratio, 4);  // time-ratio (goal 148 - 4)
  s32 rb = 0;
  std::memcpy(&rb, g_ee_main_mem + proc + 124, 4);
  printf("TOD-PIN hour=%d proc=%x (ppointer=%x) readback_hour=%d\n", s_tod_hour, proc, tod, rb);
  fflush(stdout);
  return 0;
}

void tod_pin_maybe() {
  if (!tod_pin_requested()) {
    return;
  }
  // Re-pin PERIODICALLY (not one-shot): the game's time-of-day tick drifts the
  // clock back to daylight within ~2 min even with time-ratio 0, so re-write the
  // night hour every ~45 dispatch passes to HOLD the pinned night for the A/B.
  static int s_ctr = 0;
  if ((s_ctr++ % 45) != 0) {
    return;
  }
  // Readiness: *time-of-day-proc* is a ppointer (raw pointer); deref it and
  // require the process to be a live basic (& 7 == 4) before arming, so the pin
  // never writes a half-spawned proc.
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod < 0x10000u || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 8)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return;
  }
  // Never stomp a pending listener form (the kernel resets the slot to #f after
  // running it — kboot.cpp dispatch loop).
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)tod_pin_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  static bool s_logged = false;
  if (!s_logged) {
    s_logged = true;
    lg::info("[TOD-PIN] armed hour={} (re-pinning periodically)", s_tod_hour);
  }
}

// ─── TOD FAST-FORWARD (Gperf-particles2 capture lever, NOT a pin) ───────────────
// Env OG_TOD_FAST / Android prop debug.opengoal.tod.fast — OFF by default. UNLIKE
// tod.hour (which FREEZES the clock at time-ratio 0 for a static night pose), this
// makes the clock ADVANCE FAST but continuously: it writes *time-of-day-proc*'s
// time-ratio to 18000.0 (the game's own *time-of-day-fast* rate, ~60x the normal
// 300), so a full day->night->day cycle takes ~24s instead of ~24min. The clock is
// never pinned — every palette state is visited in ORDER, just quickly — which is
// exactly what the Gperf-particles2 correctness proof needs: a NATURAL day->night
// traversal short enough to record on video, and a stress test that makes the
// dropped tod-pingpong's flicker (and any residual TOD bug) unmissable frame-to-
// frame. Value: "1" => the 18000 preset; any float >= 2 => that literal ratio.
// The time-of-day-tick loop reads time-ratio each pass and never rewrites it, so a
// direct write to proc+144 sticks; re-applied periodically because level load /
// time-of-day-setup resets it. Field offset proc+144 = goal 148-4 (time-ratio),
// identical to tod_pin_run. Mutually exclusive with tod.hour (pin wins).
static float s_tod_fast_ratio = 0.0f;

static bool tod_fast_requested() {
  static bool s_parsed = false;
  static bool s_result = false;
  if (s_parsed) {
    return s_result;
  }
  s_parsed = true;
  if (tod_pin_requested()) {
    return false;  // a freeze pin and a fast-forward are contradictory — pin wins.
  }
  char buf[32] = {0};
  if (const char* e = std::getenv("OG_TOD_FAST")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.tod.fast", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  if (!buf[0]) {
    return false;
  }
  float r = 0.0f;
  if (std::sscanf(buf, "%f", &r) < 1) {
    return false;
  }
  if (r == 1.0f) {
    s_tod_fast_ratio = 18000.0f;  // preset: the game's *time-of-day-fast* rate.
  } else if (r >= 2.0f) {
    s_tod_fast_ratio = r;  // explicit ratio (e.g. 36000 = 2x-fast, for tuning).
  } else {
    return false;  // < 2 and != 1 would stall/near-freeze the clock — reject.
  }
  s_result = true;
  return true;
}

static u64 tod_fast_run() {
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod == 0 || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 64)) {
    return 0;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return 0;
  }
  float ratio = s_tod_fast_ratio;
  std::memcpy(g_ee_main_mem + proc + 144, &ratio, 4);  // time-ratio (goal 148 - 4)
  static bool s_first = true;
  if (s_first) {
    s_first = false;
    float rb = 0.0f;
    std::memcpy(&rb, g_ee_main_mem + proc + 144, 4);
    printf("TOD-FAST ratio=%.0f proc=%x (ppointer=%x) readback=%.0f\n", ratio, proc, tod, rb);
    fflush(stdout);
  }
  return 0;
}

void tod_fast_maybe() {
  if (!tod_fast_requested()) {
    return;
  }
  // Re-apply periodically (not one-shot): level load / time-of-day-setup resets
  // time-ratio back to the slow 300 rate, so re-write the fast ratio every ~45
  // dispatch passes to HOLD the fast clock through the capture.
  static int s_ctr = 0;
  if ((s_ctr++ % 45) != 0) {
    return;
  }
  u32 tod = intern_from_c("*time-of-day-proc*")->value;
  if (tod < 0x10000u || tod == (u32)s7.offset || tod >= (u32)(EE_MAIN_MEM_SIZE - 8)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + tod, 4);
  if (proc < 0x10000u || proc == (u32)s7.offset || (proc & OFFSET_MASK) != 4 ||
      proc >= (u32)(EE_MAIN_MEM_SIZE - 256)) {
    return;
  }
  if (ListenerFunction->value != (u32)s7.offset && ListenerFunction->value != 0) {
    return;
  }
  static Ptr<Function> s_fn;  // trampoline allocated once
  if (s_fn.offset == 0) {
    s_fn = make_function_from_c((void*)tod_fast_run, false);
  }
  ListenerFunction->value = s_fn.offset;
  static bool s_logged = false;
  if (!s_logged) {
    s_logged = true;
    lg::info("[TOD-FAST] armed ratio={} (re-applying periodically; clock ADVANCES, not pinned)",
             s_tod_fast_ratio);
  }
}

// ─── ECO PHYSICS TRACER (Geco-spheres TEMPORARY arm64-NaN diagnostic) ────────────
// Env OG_ECO_TRACE / Android prop debug.opengoal.eco.trace = "1" — OFF by default.
// Per-dispatch dump of the LAST eco pickup spawned by the eco-spawn hook (its
// ppointer stashed in s_eco_trace_pp). Prints one line of physics state so we can
// see which field first becomes NaN on arm64. Plain printf, like the SPART probes.
// Field offsets are quoted from decompiler/config/jak1/all-types.gc :offset-assert:
//   process-drawable.root         :offset-assert 112   (collide-shape-moving)
//   collectable.base              :offset-assert 208   (vector :inline)
//   collectable.flags             :offset-assert 256   (collectable-flags = uint32)
//   trs.trans (via trsqv<-trsq<-trs) :offset-assert 16  (vector :inline)
//   trsqv.transv                  :offset-assert 64    (vector :inline)
//   collide-shape.root-prim       :offset-assert 160   (collide-shape-prim)
//   collide-shape-moving.local-normal :offset-assert 320 (vector :inline)
//   collide-shape-moving.dynam    :offset-assert 436   (dynamics)
//   collide-shape-prim.prim-core  :offset-assert 16 + collide-prim-core.world-sphere :offset-assert 0
//   dynamics.gravity              :offset-assert 16    (vector :inline)
// Reading a GOAL field from a boxed basic = g_ee_main_mem + basic + (offset - 4).
static bool eco_trace_requested() {
  char buf[16] = {0};
  if (const char* e = std::getenv("OG_ECO_TRACE")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
#if defined(__ANDROID__)
  if (!buf[0]) {
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.eco.trace", pbuf) > 0) {
      std::strncpy(buf, pbuf, sizeof(buf) - 1);
    }
  }
#endif
  return buf[0] == '1';
}

void eco_trace_maybe() {
  // Gate read once and cache (same pattern as eco_spawn_requested).
  static int s_on = -1;
  if (s_on < 0) {
    s_on = eco_trace_requested() ? 1 : 0;
  }
  if (s_on == 0) {
    return;
  }
  if (s_eco_trace_pp == 0) {
    return;
  }
  static int s_count = 0;
  if (s_count >= 20000) {
    return;
  }

  // s_eco_trace_pp is a RAW (pointer process): load the process basic at it (no -4).
  u32 pp = s_eco_trace_pp;
  if (pp >= (u32)(EE_MAIN_MEM_SIZE - 4)) {
    return;
  }
  u32 proc = 0;
  std::memcpy(&proc, g_ee_main_mem + pp, 4);
  if (proc == 0 || proc == (u32)s7.offset || proc >= (u32)(EE_MAIN_MEM_SIZE - 320)) {
    return;
  }

  // root = collide-shape-moving basic (process-drawable.root @ 112).
  u32 root = 0;
  std::memcpy(&root, g_ee_main_mem + proc + (112 - 4), 4);
  if (root == 0 || root == (u32)s7.offset || root >= (u32)(EE_MAIN_MEM_SIZE - 440)) {
    return;
  }

  // trans @ 16, transv @ 64, local-normal @ 320 (all vector :inline in root).
  float trans[4], transv[4], lnorm[4];
  std::memcpy(trans, g_ee_main_mem + root + (16 - 4), 16);
  std::memcpy(transv, g_ee_main_mem + root + (64 - 4), 16);
  std::memcpy(lnorm, g_ee_main_mem + root + (320 - 4), 16);

  // root-prim @ 160 (collide-shape-prim basic) -> prim-core @ 16 -> world-sphere @ 0.
  u32 rprim = 0;
  std::memcpy(&rprim, g_ee_main_mem + root + (160 - 4), 4);
  if (rprim == 0 || rprim == (u32)s7.offset || rprim >= (u32)(EE_MAIN_MEM_SIZE - 32)) {
    return;
  }
  float ws[4];
  // world-sphere = prim + (16 - 4) + 16 = prim + (16 + 16 - 4).
  std::memcpy(ws, g_ee_main_mem + rprim + (16 + 16 - 4), 16);

  // dynam @ 436 (dynamics basic) -> gravity @ 16 (vector :inline).
  u32 dynam = 0;
  std::memcpy(&dynam, g_ee_main_mem + root + (436 - 4), 4);
  if (dynam == 0 || dynam == (u32)s7.offset || dynam >= (u32)(EE_MAIN_MEM_SIZE - 32)) {
    return;
  }
  float grav[4];
  std::memcpy(grav, g_ee_main_mem + dynam + (16 - 4), 16);

  // collectable.flags @ 256 (uint32), collectable.base @ 208 (vector :inline), y = +4.
  u32 flags = 0;
  std::memcpy(&flags, g_ee_main_mem + proc + (256 - 4), 4);
  float base_y = 0.f;
  std::memcpy(&base_y, g_ee_main_mem + proc + (208 - 4) + 4, 4);

  s_count++;
  printf(
      "ECO-TRACE pp=%x proc=%x trans=%g,%g,%g transv=%g,%g,%g ws=%g,%g,%g,%g lnorm=%g,%g,%g "
      "grav=%g,%g,%g base_y=%g flags=%x\n",
      pp, proc, trans[0], trans[1], trans[2], transv[0], transv[1], transv[2], ws[0], ws[1], ws[2],
      ws[3], lnorm[0], lnorm[1], lnorm[2], grav[0], grav[1], grav[2], base_y, flags);
  fflush(stdout);
}

// ─── ECHO-INTRO (new-game intro cinematic) deterministic warp ───────────────────
// Env OG_ECHO_INTRO / Android prop debug.opengoal.echo.intro — OFF by default.
// TEMPORARY arm64/Android diagnostic. Reaches the NEW-GAME intro cinematic
// DIRECTLY (bypassing title-menu navigation) by replaying the GOAL form that the
// menu's "New Game" / progress.gc fire:
//   (initialize! *game-info* 'game (the-as game-save #f) "intro-start")
// Modeled EXACTLY on f1_maybe_warp_to_geyser above (same gate/readiness/tick-delay
// /listener-function trampoline pattern); kept fully INDEPENDENT of F1-WARP (own
// prop/env, own s_done). x86 is unaffected: the body only runs when armed.
static bool echo_intro_warp_requested() {
  if (std::getenv("OG_ECHO_INTRO")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.echo.intro", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// The warp body — invoked BY THE KERNEL as *listener-function* (same context
// f1_warp_run runs in), so it executes with a live current process on a real
// process stack: the context `initialize!` -> process-spawn require. GOAL regs are
// NOT preserved across the make_function_from_c trampoline, so re-read everything
// and pass pp explicitly to the _call_goal8 trampoline.
static u64 echo_intro_warp_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[ECHO-INTRO-WARP] run: *game-info* not ready");
    return 0;
  }
  // Resolve initialize! (method id 9 of game-info) the same way call_method_of_type
  // does: gi_type = type tag word before field-0; the method table starts at
  // type+16 (Type::new_method) with 4-byte Ptr<Function> entries, so
  // get_method(9) = *(u32*)(type + 16 + 9*4). (game-info-h.gc:168-169 — basic
  // methods 0-8, initialize! is the first custom method = id 9.)
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u32 init_fn = gi_type->get_method(9 /*initialize!*/).offset;
  if (init_fn == 0 || init_fn == (u32)s7.offset) {
    lg::warn("[ECHO-INTRO-WARP] initialize! (method 9) not bound; warp aborted");
    return 0;
  }
  u32 lp = intern_from_c("*listener-process*")->value;
  // (initialize! *game-info* 'game (the-as game-save #f) "intro-start")
  u64 args[8] = {gi,
                 intern_from_c("game").offset,    // the 'game symbol
                 (u64)s7.offset,                  // (the-as game-save #f)
                 make_string_from_c("intro-start"),
                 0, 0, 0, 0};
  u64 r = _call_goal8_asm_systemv((void*)(g_ee_main_mem + init_fn), args, 0, (u64)lp,
                                  (u64)s7.offset, g_ee_main_mem);
  lg::info("[ECHO-INTRO-WARP] initialize! 'game intro-start -> #x{:x}", (u32)r);
  return r;
}

void echo_intro_warp_maybe() {
  static bool s_done = false;
  if (s_done) {
    return;
  }
  if (!echo_intro_warp_requested()) {
    return;
  }
  // Readiness: *game-info* bound to a real boxed basic (engine far enough along
  // that initialize! can spawn). Same gate shape as f1_maybe_warp_to_geyser.
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    return;
  }
  // Settle margin after readiness — let the title attract fully come up before the
  // intro warp fires. Tunable via OG_ECHO_INTRO_DELAY (kernel-dispatch ticks).
  int delay = 600;
  if (const char* d = std::getenv("OG_ECHO_INTRO_DELAY")) {
    delay = atoi(d);
  }
  static int s_ticks = 0;
  if (s_ticks++ < delay) {
    return;
  }
  s_done = true;

  // Hand the warp to the kernel's *listener-function* slot — kernel-dispatcher runs
  // it via reset-and-call INSIDE the dispatch frame with a live process context,
  // exactly as f1_maybe_warp_to_geyser does.
  Ptr<Function> warp_fn = make_function_from_c((void*)echo_intro_warp_run, false);
  ListenerFunction->value = warp_fn.offset;
  lg::info("[ECHO-INTRO-WARP] armed *listener-function* = #x{:x}; kernel will run the warp in-context",
           warp_fn.offset);
}

// ─── Gcrash-mouche: buzzer scout-fly pickup HUD-FX repro ────────────────────────
// Env OG_MOUCHE_FX / Android prop debug.opengoal.mouche.fx — OFF by default.
//
// Reproduces, on the GOAL kernel thread via *listener-function*, the buzzer
// scout-fly pickup "fly-to-HUD" effect (collectables.gc:1273-1274, the buzzer
// `pickup` state):
//   (let ((v1-18 (manipy-spawn (-> self root trans) #f *buzzer-sg* #f :to *entity-pool*)))
//     (send-event (ppointer->process v1-18) 'become-hud-object
//                 (ppointer->process (-> *hud-parts* buzzers))))
// On desktop x86 this does NOT crash (gmouche_x86.sh oracle, 3 spawns, kernel keeps
// ticking). On Android the become-hud-object path forces use-mercneric=1 ->
// draw-bones-generic-merc, whose generic-merc family is noop-bound on arm64
// (mips2c_table_jak1_arm64.cpp kSet) -> the DMA `base` cursor collapses -> the
// owner's deterministic buzzer-collect crash. The device has no goalc listener
// socket (android_runtime_full.cpp registers Deci2Server with NO listener), and
// the flies need platforming cpad_inject cannot do, so this hook drives the EXACT
// FX the x86 oracle measures so the crash can be reproduced + a fix verified.
//
// manipy-spawn expands to: get-process (dead-pool method 14) -> activate
// (process-tree method 9) -> run-function-in-process(manipy-init,...) ->
// (-> new-proc ppointer). become-hud-object's handler (generic-obs.gc:162) just
// calls convert-to-hud-object(self, hud); we call that directly with pp=manipy
// (enter-state's `(!= current-process pp)` branch sets-to-run + returns — no
// non-local exit, identical to the real event delivery). All runs with a live pp
// because the kernel runs this as *listener-function* via reset-and-call.
static u32 mouche_read32(u32 goal_addr) {
  u32 v = 0;
  if (goal_addr != 0 && goal_addr < (u32)(EE_MAIN_MEM_SIZE - 4)) {
    std::memcpy(&v, g_ee_main_mem + goal_addr, 4);
  }
  return v;
}

static int s_mouche_fire_n = 0;

static u64 mouche_fx_run() {
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) { printf("MOUCHE-SKIP reason=target-#f\n"); fflush(stdout); return 0; }
  u32 buzzer_sg = intern_from_c("*buzzer-sg*")->value;
  if (buzzer_sg == 0 || buzzer_sg == fnull) { printf("MOUCHE-SKIP reason=buzzer-sg-#f\n"); fflush(stdout); return 0; }
  u32 entity_pool = intern_from_c("*entity-pool*")->value;
  u32 dead_pool = intern_from_c("*default-dead-pool*")->value;
  u32 manipy_type = intern_from_c("manipy")->value;
  u32 manipy_init = intern_from_c("manipy-init")->value;
  u32 hud_parts = intern_from_c("*hud-parts*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (entity_pool == 0 || entity_pool == fnull || dead_pool == 0 || dead_pool == fnull ||
      manipy_type == 0 || manipy_type == fnull || manipy_init == 0 || manipy_init == fnull ||
      hud_parts == 0 || hud_parts == fnull) {
    printf("MOUCHE-SKIP reason=env-not-ready ep=#x%x dp=#x%x mt=#x%x mi=#x%x hp=#x%x\n",
           entity_pool, dead_pool, manipy_type, manipy_init, hud_parts);
    fflush(stdout);
    return 0;
  }

  // The crash only fires when (-> *hud-parts* buzzers) is non-#f (else
  // convert-to-hud-object no-ops and the manipy draws as a normal WORLD merc,
  // which is real on arm64). init-target -> activate-hud spawns the buzzers HUD
  // during the warp; force it once if it is somehow absent.
  u32 buzzers_pp = mouche_read32(hud_parts + 16);  // hud-parts buzzers @ +16
  if (buzzers_pp == 0 || buzzers_pp == fnull) {
    u32 ah = intern_from_c("activate-hud")->value;
    if (ah != 0 && ah != fnull) {
      u64 ah_args[8] = {tgt, 0, 0, 0, 0, 0, 0, 0};
      _call_goal8_asm_systemv((void*)(g_ee_main_mem + ah), ah_args, 0, (u64)lp, (u64)s7.offset,
                              g_ee_main_mem);
      buzzers_pp = mouche_read32(hud_parts + 16);
      printf("MOUCHE-HUD forced activate-hud -> buzzers=#x%x\n", buzzers_pp);
      fflush(stdout);
    }
  }
  // (ppointer->process (-> *hud-parts* buzzers)) : deref ppointer[0] then .self (@28)
  u32 hud_proc = fnull;
  if (buzzers_pp != 0 && buzzers_pp != fnull) {
    u32 hud_obj = mouche_read32(buzzers_pp);
    if (hud_obj != 0 && hud_obj != fnull) {
      hud_proc = mouche_read32(hud_obj + 28);
    }
  }

  // (-> *target* root trans): target root(control) @ +108, trans @ +12 (proven by F1-WARP).
  u32 root_ptr = mouche_read32(tgt + 108);
  u32 trans_vec = (root_ptr != 0 && root_ptr != fnull) ? (root_ptr + 12) : 0;
  if (trans_vec == 0) { printf("MOUCHE-SKIP reason=no-trans\n"); fflush(stdout); return 0; }

  // get-process(*default-dead-pool*, manipy, #x4000) — dead-pool method 14
  u32 dp_type = mouche_read32(dead_pool - 4);
  u64 npr = call_method_of_type_arg2(dead_pool, Ptr<Type>(dp_type), 14, manipy_type, 0x4000);
  u32 new_proc = (u32)npr;
  if (new_proc == 0 || new_proc == fnull) { printf("MOUCHE-SKIP reason=get-process-fail\n"); fflush(stdout); return 0; }

  // activate(new_proc, *entity-pool*, 'manipy, *scratch-memory-top*) — process-tree method 9
  Ptr<Type> mt(manipy_type);
  u32 activate_fn = mt->get_method(9).offset;
  u32 manipy_sym = intern_from_c("manipy").offset;  // the SYMBOL object 'manipy
  u64 act_args[8] = {new_proc, entity_pool, manipy_sym, 0x70004000u /*scratch-memory-top*/, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + activate_fn), act_args, 0, (u64)lp,
                          (u64)s7.offset, g_ee_main_mem);

  // run-function-in-process(new_proc, manipy-init, trans, #f, *buzzer-sg*, #f)
  u32 run_fn = intern_from_c("run-function-in-process")->value;
  u64 run_args[8] = {new_proc, manipy_init, trans_vec, (u64)fnull, buzzer_sg, (u64)fnull, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + run_fn), run_args, 0, (u64)lp,
                          (u64)s7.offset, g_ee_main_mem);

  // become-hud-object: convert-to-hud-object(manipy, hud) with pp=manipy. This is
  // verbatim what the manipy-idle 'become-hud-object event handler does. It sets
  // dma-add-func=dma-add-process-drawable-hud and (go hud-collecting), so the next
  // render draws the manipy through draw-bones-hud -> generic-merc (the crash).
  u32 cvt_fn = intern_from_c("convert-to-hud-object")->value;
  s_mouche_fire_n++;
  if (cvt_fn != 0 && cvt_fn != fnull && hud_proc != fnull) {
    u64 cvt_args[8] = {new_proc, hud_proc, 0, 0, 0, 0, 0, 0};
    _call_goal8_asm_systemv((void*)(g_ee_main_mem + cvt_fn), cvt_args, 0, (u64)new_proc,
                            (u64)s7.offset, g_ee_main_mem);
    printf("MOUCHE-FIRE #%d proc=#x%x hud=#x%x trans=#x%x (HUD-merc path armed)\n",
           s_mouche_fire_n, new_proc, hud_proc, trans_vec);
  } else {
    printf("MOUCHE-FIRE #%d proc=#x%x hud=#f (NO hud -> world-merc, NOT the crash path)\n",
           s_mouche_fire_n, new_proc);
  }
  fflush(stdout);
  return new_proc;
}

// ── REAL buzzer collect (full lifecycle, not just the FX) ──────────────────────
// Spawns a real `buzzer` at Jak's position the EXACT way a crate's drop-pickup ->
// birth-pickup-at-point does (get-process *default-dead-pool* buzzer #x4000 ->
// activate (method 9) -> run-now-in-process buzzer-init-by-other(trans, vel, fact,
// entity)). The buzzer lands in `wait` at Jak, runs its `animate` (group-buzzer-effect
// 3D sparticle wings + optional victory-anim spool), and — because Jak is right on it
// — the collide-shape touch fires -> (go-virtual pickup #f ...) -> the FULL pickup
// :code (level-hint-spawn voice/STR, manipy fly-to-HUD FX, task bookkeeping). This
// exercises everything a real scout-fly collect does, which the FX-only path did not.
static u64 mouche_buzzer_run() {
  using namespace jak1_symbols;  // FIX_SYM_GLOBAL_HEAP
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) { printf("MOUCHE-BUZZ-SKIP reason=target-#f\n"); fflush(stdout); return 0; }
  u32 buzzer_type = intern_from_c("buzzer")->value;
  u32 buzzer_init = intern_from_c("buzzer-init-by-other")->value;
  u32 entity_pool = intern_from_c("*entity-pool*")->value;
  u32 dead_pool = intern_from_c("*default-dead-pool*")->value;
  u32 fact_type = intern_from_c("fact-info")->value;
  u32 null_vec = intern_from_c("*null-vector*")->value;
  u32 lp = intern_from_c("*listener-process*")->value;
  if (buzzer_type == 0 || buzzer_type == fnull || buzzer_init == 0 || buzzer_init == fnull ||
      entity_pool == 0 || entity_pool == fnull || dead_pool == 0 || dead_pool == fnull ||
      fact_type == 0 || fact_type == fnull || null_vec == 0 || null_vec == fnull) {
    printf("MOUCHE-BUZZ-SKIP reason=env-not-ready bt=#x%x bi=#x%x dp=#x%x ft=#x%x nv=#x%x\n",
           buzzer_type, buzzer_init, dead_pool, fact_type, null_vec);
    fflush(stdout);
    return 0;
  }

  // fact-info (basic, size 0x28): pickup-type@8, pickup-amount@12, pickup-spawn-amount@16,
  // options@24. C++ addr = obj + (deftype_offset - 4).
  u32 fact = (u32)alloc_heap_object((s7 + FIX_SYM_GLOBAL_HEAP).offset, fact_type, 0x2c, UNKNOWN_PP);
  if (fact == 0 || fact == fnull) { printf("MOUCHE-BUZZ-SKIP reason=fact-alloc-fail\n"); fflush(stdout); return 0; }
  // pickup-amount encodes the scout-fly task: (game-task training-buzzer) = 95 is the
  // real Geyser Rock ('training) scout-fly task, so the pickup :code's get-task-control /
  // close-specific-task! bookkeeping resolves a VALID task (a fresh #x4000 fact would
  // otherwise read task 1 -> "get-task-control received invalid task 1/#f" and hang —
  // a harness artifact, not the buzzer bug). buzzer-init-by-other copies arg2's
  // pickup-spawn-amount into the buzzer's fact pickup-amount.
  { int32_t v = 8;       std::memcpy(g_ee_main_mem + fact + 4, &v, 4); }   // pickup-type = buzzer
  { float v = 95.0f;     std::memcpy(g_ee_main_mem + fact + 8, &v, 4); }   // pickup-amount = training-buzzer
  { float v = 95.0f;     std::memcpy(g_ee_main_mem + fact + 12, &v, 4); }  // pickup-spawn-amount = training-buzzer
  { u32 v = 0;           std::memcpy(g_ee_main_mem + fact + 20, &v, 4); }  // options

  u32 root_ptr = mouche_read32(tgt + 108);
  u32 jak_pos = (root_ptr != 0 && root_ptr != fnull) ? (root_ptr + 12) : 0;
  if (jak_pos == 0) { printf("MOUCHE-BUZZ-SKIP reason=no-trans\n"); fflush(stdout); return 0; }

  u32 dp_type = mouche_read32(dead_pool - 4);
  u64 bpr = call_method_of_type_arg2(dead_pool, Ptr<Type>(dp_type), 14, buzzer_type, 0x4000);
  u32 buzzer_proc = (u32)bpr;
  if (buzzer_proc == 0 || buzzer_proc == fnull) { printf("MOUCHE-BUZZ-SKIP reason=get-process-fail\n"); fflush(stdout); return 0; }

  Ptr<Type> bt(buzzer_type);
  u32 activate_fn = bt->get_method(9).offset;
  u32 buzzer_sym = intern_from_c("buzzer").offset;
  u64 act_args[8] = {buzzer_proc, entity_pool, buzzer_sym, 0x70004000u, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + activate_fn), act_args, 0, (u64)lp, (u64)s7.offset, g_ee_main_mem);

  // run-now-in-process(buzzer, buzzer-init-by-other, jak_pos, *null-vector*, fact, #f)
  u32 run_fn = intern_from_c("run-function-in-process")->value;
  u64 run_args[8] = {buzzer_proc, buzzer_init, jak_pos, null_vec, fact, (u64)fnull, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + run_fn), run_args, 0, (u64)lp, (u64)s7.offset, g_ee_main_mem);

  s_mouche_fire_n++;
  u32 b_status = mouche_read32(buzzer_proc + 36);  // process status @ +36
  u32 b_name = mouche_read32(buzzer_proc + 4);     // process-tree name @ +4
  printf("MOUCHE-BUZZ #%d proc=#x%x fact=#x%x pos=#x%x status=#x%x name=#x%x (real buzzer spawned at Jak)\n",
         s_mouche_fire_n, buzzer_proc, fact, jak_pos, b_status, b_name);
  fflush(stdout);
  return buzzer_proc;
}

void mouche_maybe_fire() {
  static bool s_checked = false, s_enabled = false, s_buzz = false;
  if (!s_checked) {
    s_checked = true;
    if (std::getenv("OG_MOUCHE_FX")) {
      s_enabled = true;
    }
    if (std::getenv("OG_MOUCHE_BUZZ")) {
      s_enabled = true;
      s_buzz = true;
    }
#if defined(__ANDROID__)
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.mouche.fx", buf) > 0 && buf[0] == '1') {
      s_enabled = true;
    }
    char bz[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.mouche.buzz", bz) > 0 && bz[0] == '1') {
      s_enabled = true;
      s_buzz = true;
    }
#endif
  }
  if (!s_enabled) {
    return;
  }

  int count = 2, gap = 240, settle = 300;
  if (const char* c = std::getenv("OG_MOUCHE_COUNT")) count = atoi(c);
  if (const char* g = std::getenv("OG_MOUCHE_GAP")) gap = atoi(g);
  if (const char* s = std::getenv("OG_MOUCHE_SETTLE")) settle = atoi(s);

  static int s_fires = 0;
  if (s_fires >= count) {
    return;
  }
  // readiness: *target* alive + buzzer art loaded
  u32 tgt = intern_from_c("*target*")->value;
  u32 bsg = intern_from_c("*buzzer-sg*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset || bsg == 0 || bsg == (u32)s7.offset) {
    return;
  }
  static int s_settle_ticks = 0;
  if (s_settle_ticks++ < settle) {
    return;
  }
  // only re-arm once the kernel has consumed the previous *listener-function*
  if (ListenerFunction->value != s7.offset) {
    return;
  }
  static int s_gap_ticks = 0;
  if (s_gap_ticks++ < gap) {
    return;
  }
  s_gap_ticks = 0;

  static u32 s_fx_fn = 0;
  if (s_fx_fn == 0) {
    s_fx_fn = make_function_from_c(s_buzz ? (void*)mouche_buzzer_run : (void*)mouche_fx_run, false)
                  .offset;
  }
  ListenerFunction->value = s_fx_fn;
  s_fires++;
  printf("MOUCHE-ARM fire %d/%d mode=%s (settle=%d gap=%d)\n", s_fires, count,
         s_buzz ? "buzzer" : "fx", settle, gap);
  fflush(stdout);
}

// ─── Gdeath-crash: deterministic death/respawn repro + verify ───────────────────
// Env OG_DIE / Android prop debug.opengoal.die — OFF by default. Forces Jak to die
// N times so the arm64 death/respawn crash can be reproduced and ">=5 crash-free
// deaths" proven. Modeled EXACTLY on mouche_maybe_fire / echo_intro_warp (same
// listener-function trampoline + readiness gate + tick cadence). x86 is unaffected
// unless armed. Mode (env OG_DIE_MODE / prop debug.opengoal.die.mode):
//   "respawn"      -> (initialize! *game-info* 'die #f #f): respawn/loader path only.
//   "endlessfall"  -> send-event 'attack-invinc mode='endlessfall (fall death; DEFAULT).
//   "drown-death"  -> send-event 'attack-invinc mode='drown-death (drown death).
//   <other symbol> -> send-event 'attack-invinc with that attack-mode symbol.
// The death :code (target-death.gc:911-914) always ends in
//   (initialize! game 'dead) -> kill+respawn target -> init-target -> target-continue,
// so EVERY mode exercises the common respawn/loader path; the mode selects only the
// preceding animation branch (endlessfall/drown vs. respawn-only).
static char s_die_event_mode[64] = "endlessfall";

static bool die_requested() {
  if (std::getenv("OG_DIE")) {
    return true;
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.die", buf) > 0 && buf[0] == '1') {
    return true;
  }
#endif
  return false;
}

// TRIGGER 1 — respawn-only. Replays the debug "New Life" menu form
// (default-menu.gc:2271) (initialize! *game-info* 'die #f #f), which falls through
// to the mode='play respawn reload. Same get_method(9)+_call_goal8 pattern as the
// echo-intro hook's initialize! call. Runs as *listener-function* (live pp).
static u64 die_respawn_run() {
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4 /*BASIC_OFFSET*/) {
    lg::warn("[GDEATH] respawn: *game-info* not ready");
    return 0;
  }
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u32 init_fn = gi_type->get_method(9).offset;  // initialize!
  u32 lp = intern_from_c("*listener-process*")->value;
  u64 args[8] = {gi, intern_from_c("die").offset, (u64)s7.offset, (u64)s7.offset, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + init_fn), args, 0, (u64)lp, (u64)s7.offset,
                          g_ee_main_mem);
  printf("GDEATH-FIRE mode=respawn (initialize! *game-info* 'die)\n");
  fflush(stdout);
  return 0;
}

// TRIGGER 2 — full death state via the engine's own force-death event
// (logic-target.gc:674): (send-event *target* 'attack-invinc #f
// (static-attack-info ((mode <mode>)))). attack-info + event-message-block are
// `structure`s (NO type tag) -> raw kmalloc + RAW field offsets (NOT the basic -4
// rule). Routes target-hit -> (go target-death <mode>); endlessfall/drown-death are
// handled death branches. Runs as *listener-function* (live pp).
static u64 die_event_run() {
  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) {
    printf("GDEATH-SKIP reason=target-#f\n");
    fflush(stdout);
    return 0;
  }
  u32 lp = intern_from_c("*listener-process*")->value;
  u32 sef = intern_from_c("send-event-function")->value;
  // "movie" -> the generic death-MOVIE (else) branch in target-death.gc:872-910
  // (blerc 'blend-shape + pov-camera death spool — the prime arm64 merc suspect).
  // That branch is reached only when health<=0 forces (go target-death <mode>) for a
  // mode NOT explicitly handled in the :code case; 'tar lands in the else branch
  // (case at target-death.gc:873-874). So for "movie" we zero Jak's health first
  // (target.fact @ proc-drawable off 144 -> fact-info-target.health @ off 64; both
  // basic, so C++ addr = field_off - 4) and send the attack with mode='tar, which
  // target-hit's health<=0 guard (target-death.gc:613) routes to (go target-death 'tar).
  bool movie = (std::strcmp(s_die_event_mode, "movie") == 0);
  const char* mode_name = movie ? "tar" : s_die_event_mode;
  u32 mode_sym = intern_from_c(mode_name).offset;
  if (sef == 0 || sef == fnull || mode_sym == 0) {
    printf("GDEATH-SKIP reason=env sef=#x%x mode=#x%x\n", sef, mode_sym);
    fflush(stdout);
    return 0;
  }
  if (movie) {
    u32 fact_ptr = 0;
    std::memcpy(&fact_ptr, g_ee_main_mem + tgt + 140, 4);  // (-> target fact)
    if (fact_ptr != 0 && fact_ptr != fnull && fact_ptr < (u32)(EE_MAIN_MEM_SIZE - 64)) {
      float z = 0.0f;
      std::memcpy(g_ee_main_mem + fact_ptr + 60, &z, 4);  // (-> target fact health) = 0.0
      printf("GDEATH-MOVIE zeroed health fact=#x%x\n", fact_ptr);
    }
  }
  // attack-info (structure, size 0x68): mask@64, mode@68 (RAW offsets).
  u32 atk = (u32)kmalloc(kglobalheap, 0x68, KMALLOC_MEMSET, "die-atk").offset;
  if (atk == 0) {
    printf("GDEATH-SKIP reason=atk-alloc\n");
    fflush(stdout);
    return 0;
  }
  { u32 v = 0x20; std::memcpy(g_ee_main_mem + atk + 64, &v, 4); }       // mask = (attack-mask mode)
  { u32 v = mode_sym; std::memcpy(g_ee_main_mem + atk + 68, &v, 4); }   // mode = <mode-sym>
  // event-message-block (structure, size 0x48): from@4, num-params@8, message@12,
  // param[i]@16+8*i (RAW offsets).
  u32 blk = (u32)kmalloc(kglobalheap, 0x48, KMALLOC_MEMSET, "die-evt").offset;
  if (blk == 0) {
    printf("GDEATH-SKIP reason=blk-alloc\n");
    fflush(stdout);
    return 0;
  }
  { u32 v = tgt; std::memcpy(g_ee_main_mem + blk + 4, &v, 4); }         // from = *target*
  { s32 v = 2; std::memcpy(g_ee_main_mem + blk + 8, &v, 4); }          // num-params = 2
  { u32 v = intern_from_c("attack-invinc").offset;
    std::memcpy(g_ee_main_mem + blk + 12, &v, 4); }                     // message = 'attack-invinc
  { u64 v = (u64)fnull; std::memcpy(g_ee_main_mem + blk + 16, &v, 8); } // param0 = #f (touching-shapes)
  { u64 v = (u64)atk; std::memcpy(g_ee_main_mem + blk + 24, &v, 8); }   // param1 = attack-info
  u64 args[8] = {tgt, blk, 0, 0, 0, 0, 0, 0};
  _call_goal8_asm_systemv((void*)(g_ee_main_mem + sef), args, 0, (u64)lp, (u64)s7.offset,
                          g_ee_main_mem);
  printf("GDEATH-FIRE mode=%s (send-event *target* 'attack-invinc) atk=#x%x blk=#x%x\n",
         s_die_event_mode, atk, blk);
  fflush(stdout);
  return 0;
}

void die_maybe_fire() {
  static bool s_checked = false, s_enabled = false, s_respawn = false;
  static int s_count = 6;
  if (!s_checked) {
    s_checked = true;
    if (die_requested()) {
      s_enabled = true;
    }
    const char* m = std::getenv("OG_DIE_MODE");
#if defined(__ANDROID__)
    char pbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.die.mode", pbuf) > 0 && pbuf[0]) {
      m = pbuf;
    }
#endif
    if (m && m[0]) {
      std::strncpy(s_die_event_mode, m, sizeof(s_die_event_mode) - 1);
      s_die_event_mode[sizeof(s_die_event_mode) - 1] = 0;
    }
    if (std::strcmp(s_die_event_mode, "respawn") == 0) {
      s_respawn = true;
    }
    if (const char* c = std::getenv("OG_DIE_COUNT")) {
      s_count = atoi(c);
    }
#if defined(__ANDROID__)
    char cbuf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.die.count", cbuf) > 0 && cbuf[0]) {
      s_count = atoi(cbuf);
    }
#endif
    if (s_count < 1) {
      s_count = 1;
    }
  }
  if (!s_enabled) {
    return;
  }

  int settle = 600, gap = 480;
  if (const char* s = std::getenv("OG_DIE_SETTLE")) settle = atoi(s);
  if (const char* g = std::getenv("OG_DIE_GAP")) gap = atoi(g);

  static int s_fires = 0;
  if (s_fires >= s_count) {
    return;
  }
  // readiness: *target* alive AND game in 'play, so the respawn branch runs and we
  // never fire during a cutscene/menu/respawn transition (when *target* is #f).
  // game-info `mode` is at deftype offset 4 -> C++ addr gi+0 (basic -4 rule).
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == (u32)s7.offset) {
    return;
  }
  u32 gi = intern_from_c("*game-info*")->value;
  if (gi == 0 || gi == (u32)s7.offset || (gi & OFFSET_MASK) != 4) {
    return;
  }
  u32 gi_mode = 0;
  std::memcpy(&gi_mode, g_ee_main_mem + gi + 0, 4);
  if (gi_mode != intern_from_c("play").offset) {
    return;
  }
  static int s_settle_ticks = 0;
  if (s_settle_ticks++ < settle) {
    return;
  }
  // only re-arm once the kernel consumed the previous *listener-function*
  if (ListenerFunction->value != s7.offset) {
    return;
  }
  static int s_gap_ticks = 0;
  if (s_gap_ticks++ < gap) {
    return;
  }
  s_gap_ticks = 0;

  static u32 s_fn = 0;
  if (s_fn == 0) {
    s_fn = make_function_from_c(s_respawn ? (void*)die_respawn_run : (void*)die_event_run, false)
               .offset;
  }
  ListenerFunction->value = s_fn;
  s_fires++;
  printf("GDEATH-ARM fire %d/%d mode=%s (settle=%d gap=%d)\n", s_fires, s_count,
         s_respawn ? "respawn" : s_die_event_mode, settle, gap);
  fflush(stdout);
}

// ─── TARGET-DRIVE (Gcrash-swamp-load debug-only) ────────────────────────────────
// Env-free / Android prop debug.opengoal.target.drive = "<dx> <dz> <pin_y> <stop_z>"
// (RAW EE units, floats OK), OFF by default. Each kernel dispatch, marches *target*
// (Jak) by (dx,dz) in world space (optionally pinning y), stopping at stop_z — so
// SWA.DGO streams in from Jak's REAL position (a position-triggered load, not a
// want-levels replay). Reads/writes *target*'s world trans via the SAME guarded
// EE-memcpy pattern the mouche_/eco_ hooks use: (-> *target* root) @ tgt+108,
// trans @ root+12 (x@+0 y@+4 z@+8, 4-byte floats). Runs on the GOAL kernel thread
// in the dispatch loop (safe to touch EE, like the eco hook). Never armed in the
// shipped APK.
void target_drive_maybe() {
  // Gate: read the prop once per call; disarmed if empty/unset. Sized 128 (not
  // PROP_VALUE_MAX, an Android-only macro) so the x86 desktop build compiles.
  char buf[128] = {0};
#if defined(__ANDROID__)
  if (!(__system_property_get("debug.opengoal.target.drive", buf) > 0 && buf[0])) {
    return;
  }
#else
  if (const char* e = std::getenv("OG_TARGET_DRIVE")) {
    std::strncpy(buf, e, sizeof(buf) - 1);
  }
  if (!buf[0]) {
    return;
  }
#endif

  const u32 fnull = (u32)s7.offset;
  u32 tgt = intern_from_c("*target*")->value;
  if (tgt == 0 || tgt == fnull) {
    return;
  }
  // (-> *target* root) : control/root ptr @ tgt+108 (same read as kmachine.cpp:2002-2004).
  if (tgt >= (u32)(EE_MAIN_MEM_SIZE - 112)) {
    return;
  }
  u32 root_ptr = 0;
  std::memcpy(&root_ptr, g_ee_main_mem + tgt + 108, 4);
  if (root_ptr == 0 || root_ptr == fnull) {
    return;
  }
  // trans vector @ root+12 (world position); guard the whole [x..z+4) span.
  u32 trans_vec = root_ptr + 12;
  if (trans_vec < 0x1000 || trans_vec >= (u32)(EE_MAIN_MEM_SIZE - 16)) {
    return;
  }

  // Parse "<dx> <dz> <pin_y> <stop_z>" (atof, floats OK).
  float dx = 0.f, dz = 0.f, pin_y = 0.f, stop_z = 0.f;
  int n = std::sscanf(buf, "%f %f %f %f", &dx, &dz, &pin_y, &stop_z);
  if (n < 4) {
    return;  // need all four
  }

  // Read current x,y,z floats from trans_vec.
  float x = 0.f, y = 0.f, z = 0.f;
  std::memcpy(&x, g_ee_main_mem + trans_vec + 0, 4);
  std::memcpy(&y, g_ee_main_mem + trans_vec + 4, 4);
  std::memcpy(&z, g_ee_main_mem + trans_vec + 8, 4);

  // Determine "past the stop" for the drive direction, then step (or hold).
  bool past = (dz < 0 && z <= stop_z) || (dz > 0 && z >= stop_z);
  if (past) {
    // Hold Jak at the stop: x unchanged, z pinned to stop_z, y optionally pinned.
    z = stop_z;
  } else {
    x = x + dx;
    z = z + dz;
  }
  std::memcpy(g_ee_main_mem + trans_vec + 0, &x, 4);
  std::memcpy(g_ee_main_mem + trans_vec + 8, &z, 4);
  if (pin_y != 0.f) {
    y = pin_y;
    std::memcpy(g_ee_main_mem + trans_vec + 4, &y, 4);
  }

  // Progress trace every 15th call so the harness can track Jak's position.
  static int s_drive_n = 0;
  if ((s_drive_n++ % 15) == 0) {
    printf("TARGET-DRIVE pos=(%.1f %.1f %.1f)\n", x, y, z);
    fflush(stdout);
  }
}

// ─── DIAG FLAGS (Gcrash-swamp-load debug-only) ──────────────────────────────────
// Env-free / Android prop debug.opengoal.diag.norepair, OFF by default. When
// value[0]=='1', arms the gk_android_main signal-handler bypass (via the extern
// "C" setter gk_set_diag_norepair) so the three "repair-and-resume" control
// transfer handlers bail out and the TRUE first swamp-load crash reaches the fatal
// forensic dump instead of being silently masked. On desktop this is a no-op.
void diag_flags_maybe() {
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  bool on = (__system_property_get("debug.opengoal.diag.norepair", buf) > 0 && buf[0] == '1');
  gk_set_diag_norepair(on);
#endif
}

// Gcrash-swamp-load fix: clear *part-group-id-table* slots whose sparticle-launch-group
// object lies in [dst_goal, dst_goal+size) — the level-heap region jak1_work_v3 is about
// to overwrite. Race-free (called synchronously right before the segment memcpy). Prevents
// the arm64 level-thrash dangling-slot crash where lookup-part-group-pointer-by-name
// derefs a name pointer that was overwritten with code.
#if defined(__ANDROID__)
void invalidate_part_groups_in_range(u32 dst_goal, u32 size) {
  if (size == 0) return;
  // A/B toggle: the fix is ON by default; debug.opengoal.partgroup.inval=0 disables it
  // (to reproduce the pre-fix swamp-load crash on the same build). OFF-switch only.
  {
    char ib[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.partgroup.inval", ib) > 0 && ib[0] == '0') {
      return;
    }
  }
  const u32 fnull = (u32)s7.offset;
  u32 tbl = intern_from_c("*part-group-id-table*")->value;
  if (tbl == 0 || tbl == fnull || tbl < 0x1000 || tbl >= (u32)(EE_MAIN_MEM_SIZE - 32)) return;
  u32 len = 0; std::memcpy(&len, g_ee_main_mem + tbl + 4, 4);
  if (len > 1024) len = 1024;
  const u64 lo = dst_goal, hi = (u64)dst_goal + size;
  static int s_inval_logged = 0;
  for (u32 i = 0; i < len; i++) {
    u32 slot_addr = tbl + 16 + i * 4;
    if (slot_addr >= (u32)(EE_MAIN_MEM_SIZE - 4)) break;
    u32 group = 0; std::memcpy(&group, g_ee_main_mem + slot_addr, 4);
    if (group == 0 || group == fnull) continue;
    if ((u64)group >= lo && (u64)group < hi) {
      if (s_inval_logged < 16) { s_inval_logged++;
        printf("PARTGROUP-INVAL slot=%u group=0x%x in [0x%x,0x%llx) -> cleared\n",
               i, group, dst_goal, (unsigned long long)hi); fflush(stdout); }
      u32 zero = 0; std::memcpy(g_ee_main_mem + slot_addr, &zero, 4);
    }
  }
}
#endif

}  // namespace jak1

#if defined(__GNUC__)
#pragma GCC diagnostic pop
#elif defined(__clang__)
#pragma clang diagnostic pop
#endif
