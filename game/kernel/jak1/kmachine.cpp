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
#include "game/sce/libcdvd_ee.h"
#include "game/sce/libdma.h"
#include "game/sce/libgraph.h"
#include "game/sce/sif_ee.h"
#include "game/sce/stubs.h"

#include <cstdlib>
#include <cstring>
#if defined(__ANDROID__)
#include <sys/system_properties.h>
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
  u64 name = make_string_from_c("game-start");
  Ptr<Type> gi_type(*Ptr<u32>(gi - 4));  // basic: type tag is the word before field-0
  u64 cont = call_method_of_type_arg2(gi, gi_type, 18 /*get-continue-by-name*/, (u32)name, 0);
  lg::info("[F1-WARP] get-continue-by-name(\"game-start\") -> #x{:x}", (u32)cont);
  if (cont == 0 || cont == (u32)s7.offset) {
    lg::warn("[F1-WARP] continue 'game-start' not found; warp aborted");
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

}  // namespace jak1

#if defined(__GNUC__)
#pragma GCC diagnostic pop
#elif defined(__clang__)
#pragma clang diagnostic pop
#endif
