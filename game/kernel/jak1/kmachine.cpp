#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#elif defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#include "kmachine.h"

#include <string>

#include "common/log/log.h"
#include "common/symbols.h"
#include "common/util/FileUtil.h"
#include "common/util/string_util.h"

#include "game/external/discord_jak1.h"
#include "game/graphics/display.h"
#include "game/graphics/gfx.h"
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

#include <cstdint>
#include <cstdio>
#include <cmath>
#include <cstdlib>
#include <cstring>
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

/*!
 * Initialize GOAL Runtime. This is the main initialization which is called before entering
 * the GOAL kernel dispatch loop (KernelCheckAndDispatch).
 * TODO finish up things which are commented.
 */
int InitMachine() {
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
  for (char* tok = strtok_r(buf, ",", &save); tok; tok = strtok_r(nullptr, ",", &save)) {
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
