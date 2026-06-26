/*!
 * @file kboot.cpp
 * GOAL Boot.  Contains the "main" function to launch GOAL runtime
 * DONE!
 */

#include "kboot.h"

#include <chrono>
#include <cstring>
#include <stdio.h>
#include <stdlib.h>
#include <thread>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/util/Timer.h"

#include "game/common/game_common_types.h"
#include "game/kernel/common/klisten.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kmachine.h"
#include "game/sce/libscf.h"

using namespace ee;

namespace jak1 {
VideoMode BootVideoMode;

void kboot_init_globals() {}

/*!
 * Launch the GOAL Kernel (EE).
 * DONE!
 * See InitParms for launch argument details.
 * @param argc : argument count
 * @param argv : argument list
 * @return 0 on success, otherwise failure.
 *
 * CHANGES:
 * Added InitParms call to handle command line arguments
 * Removed hard-coded debug mode disable
 * Renamed from `main` to `goal_main`
 * Add call to sceDeci2Reset when GOAL shuts down.
 */
s32 goal_main(int argc, const char* const* argv) {
  // Initialize global variables based on command line parameters
  // This call is not present in the retail version of the game
  // but the function is, and it likely goes here.
  InitParms(argc, argv);

  // Initialize CRC32 table for string hashing
  init_crc();

  // NTSC V1, NTSC v2, PAL CD Demo, PAL Retail
  // Set up game configurations
  masterConfig.aspect = (u16)sceScfGetAspect();
  masterConfig.language = (u16)sceScfGetLanguage();
  masterConfig.inactive_timeout = 0;  // demo thing
  masterConfig.timeout = 0;           // demo thing
  masterConfig.volume = 100;

  // Set up language configuration
  if (masterConfig.language == SCE_SPANISH_LANGUAGE) {
    masterConfig.language = (u16)Language::Spanish;
  } else if (masterConfig.language == SCE_FRENCH_LANGUAGE) {
    masterConfig.language = (u16)Language::French;
  } else if (masterConfig.language == SCE_GERMAN_LANGUAGE) {
    masterConfig.language = (u16)Language::German;
  } else if (masterConfig.language == SCE_ITALIAN_LANGUAGE) {
    masterConfig.language = (u16)Language::Italian;
  } else if (masterConfig.language == SCE_JAPANESE_LANGUAGE) {
    // Note: this case was added so it is easier to test Japanese fonts.
    masterConfig.language = (u16)Language::Japanese;
  } else {
    // pick english by default, if language is not supported.
    masterConfig.language = (u16)Language::English;
  }

  // Set up aspect ratio override in demo
  if (!strcmp(DebugBootMessage, "demo") || !strcmp(DebugBootMessage, "demo-shared")) {
    masterConfig.aspect = SCE_ASPECT_FULL;
  }

#ifdef __ANDROID__
  // Gaspect-unstub DATA marker. On Android sceScfGetAspect() is forced to
  // SCE_ASPECT_169 (game/sce/libscf.cpp) because the PC window-size aspect
  // derivation (update-from-os/pc-get-window-size) is stubbed, which would
  // otherwise leave the game at the 4:3 boot default and lay out the 2D menu/HUD
  // for 4:3 on the widescreen device. masterConfig.aspect feeds DecodeAspect ->
  // (scf-get-aspect), which settings.gc maps (2 => 'aspect16x9). Emit the resolved
  // enum once so the phase validator can DATA-confirm widescreen from logcat
  // (stderr is piped to logcat on Android).
  fprintf(stderr, "GASPECT-DIAG aspect=%s raw=%d\n",
          masterConfig.aspect == SCE_ASPECT_169    ? "16x9"
          : masterConfig.aspect == SCE_ASPECT_FULL ? "full"
                                                   : "4x3",
          (int)masterConfig.aspect);
  fflush(stderr);
#endif

  // In retail game, disable debugging modes, and force on DiskBoot
  // MasterDebug = 0;
  // DiskBoot = 1;
  // DebugSegment = 0;

  // Launch GOAL!
  if (InitMachine() >= 0) {    // init kernel
    KernelCheckAndDispatch();  // run kernel
    ShutdownMachine();         // kernel died, we should too.
  } else {
    fprintf(stderr, "InitMachine failed\n");
    exit(1);
  }

  return 0;
}

/*!
 * Main loop to dispatch the GOAL kernel.
 */
void KernelCheckAndDispatch() {
  u64 goal_stack = u64(g_ee_main_mem) + EE_MAIN_MEM_SIZE - 8;

  while (MasterExit == RuntimeExitStatus::RUNNING) {
    // try to get a message from the listener, and process it if needed
    Ptr<char> new_message = WaitForMessageAndAck();
    if (new_message.offset) {
      ProcessListenerMessage(new_message);
    }

    // remember the old listener function
    auto old_listener = ListenerFunction->value;
    // dispatch the kernel
    //(**kernel_dispatcher)();

    Timer kernel_dispatch_timer;
    if (MasterUseKernel) {
      // use the GOAL kernel.
      call_goal_on_stack(Ptr<Function>(kernel_dispatcher->value), goal_stack, s7.offset,
                         g_ee_main_mem);
    } else {
      // use a hack to just run the listener function if there's no GOAL kernel.
      if (ListenerFunction->value != s7.offset) {
        auto result = call_goal_on_stack(Ptr<Function>(ListenerFunction->value), goal_stack,
                                         s7.offset, g_ee_main_mem);
#ifdef __linux__
        cprintf("%ld\n", result);
#else
        cprintf("%lld\n", result);
#endif
        ListenerFunction->value = s7.offset;
      }
    }

    auto time_ms = kernel_dispatch_timer.getMs();
    if (time_ms > 50) {
      lg::print("Kernel dispatch time: {:.3f} ms\n", time_ms);
    }

    ClearPending();

    // F1 (Geyser Rock) deterministic warp — gated (env OG_F1_WARP / prop
    // debug.opengoal.f1.warp), OFF by default, fires once. Runs here on the GOAL
    // kernel thread, between dispatch frames — the same point a listener-injected
    // form would run on the desktop oracle.
    f1_maybe_warp_to_geyser();

    // ECHO-INTRO (new-game intro cinematic) deterministic warp — gated (env
    // OG_ECHO_INTRO / prop debug.opengoal.echo.intro), OFF by default, fires once.
    // Reaches the new-game intro cinematic directly, bypassing the title menu.
    echo_intro_warp_maybe();

    // Gcrash-mouche (Geyser Rock buzzer scout-fly pickup HUD-FX) repro/verify —
    // gated (env OG_MOUCHE_FX / prop debug.opengoal.mouche.fx), OFF by default.
    // Drives the manipy fly-to-HUD effect (the deterministic buzzer-collect crash)
    // via *listener-function*, the same dispatch-loop point the desktop oracle uses.
    mouche_maybe_fire();

    // if the listener function changed, it means the kernel ran it, so we should notify compiler.
    if (MasterDebug && ListenerFunction->value != old_listener) {
      SendAck();
    }

    if (time_ms < 4) {
      std::this_thread::sleep_for(std::chrono::microseconds(1000));
    }
  }
}

/*!
 * Stop running the GOAL Kernel.
 * DONE, EXACT
 */
void KernelShutdown() {
  MasterExit = RuntimeExitStatus::EXIT;  // GOAL Kernel Dispatch loop will stop now.
}
}  // namespace jak1
