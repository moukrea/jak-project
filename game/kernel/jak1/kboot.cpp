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
  // Aspect DATA marker. masterConfig.aspect feeds DecodeAspect -> (scf-get-aspect),
  // which settings.gc maps to the aspect ENUM. Emitted once at boot so the resolved
  // enum is readable from logcat (stderr is piped to logcat on Android).
  //
  // Gandroid-window-size CORRECTION (2026-08-28): the note that used to sit here said
  // "on Android sceScfGetAspect() is forced to SCE_ASPECT_169 ... because the PC
  // window-size aspect derivation is stubbed". BOTH halves are now false, and leaving
  // the claim here would send the next reader hunting a workaround that no longer
  // exists:
  //   * game/sce/libscf.cpp returns SCE_ASPECT_43 on EVERY platform since
  //     Gmenu-ui-placement — the 16:9 ENUM squeezes *video-parms* relative-x-scale to
  //     0.75 and bunched the progress menu on an ultrawide panel;
  //   * the window-size derivation is NOT stubbed on Android: pc-get-window-size is
  //     bound to a35_pc_get_window_size (android/gk_android_main.cpp), which writes the
  //     real surface, and update-from-os now publishes it as a `GAWIN win=...` line.
  // What actually drives widescreen on the device is the FLOAT (-> *pc-settings*
  // aspect-ratio), not this enum. Read the GAWIN line, not this marker, to know the
  // aspect the frame was composed at.
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

    // GENERIC LEVEL WARP (debug-only zone-sweep) — gated (env OG_LEVEL_WARP=<name>
    // / prop debug.opengoal.level.warp=<continue-name>), OFF by default. Warps
    // directly into any jak1 level by its continue-point name to confirm it loads +
    // runs crash-free on the real device. Same in-context dispatch point as F1.
    level_warp_maybe();

    // TASK CLOSE (Gcrash-rockvillage debug-only repro) — gated (env OG_TASK_CLOSE /
    // prop debug.opengoal.task.close), OFF by default. Closes task-gated progress
    // (e.g. the village2-warrior-money pontoon payment) so a device repro can walk
    // gated routes. Same in-context dispatch point as the warps.
    task_close_maybe();

    // CINE KICK (Gcutscene-npc-flicker-2 debug-only cutscene launcher) — gated (env
    // OG_CINE_KICK / prop debug.opengoal.cine.kick = "<type>[,<type>...]"), OFF by
    // default. Sends the game's own 'play-anim event to the taskable NPC of each named
    // TYPE, so an NPC cutscene the player would have to walk up to and trigger (the
    // mayor's first one) plays with nobody at the pad. Same in-context dispatch point.
    cine_kick_maybe();

    // WANT-LEVELS / WANT-DISPLAY (Gcrash-rockvillage debug-only repro) — gated
    // (env OG_WANT_LEVELS / OG_WANT_DISPLAY, props debug.opengoal.want.*), OFF by
    // default. Deterministically replay the village2->swamp load-boundary commands.
    want_levels_maybe();
    want_display_maybe();
    want_vis_maybe();

    // PHYS-ROOM (Grecharged-secondary-motion, SPEC §6 étape 1) — gated (env
    // OG_PHYS_ROOM / prop debug.opengoal.phys.room), OFF by default. Calls the GOAL
    // `phys-room-start` to open the player-less physics test room (subject spawned
    // alone, Jak absent). Same in-context dispatch point as the want-* hooks.
    phys_room_maybe();

    // TARGET-DRIVE (Gcrash-swamp-load debug-only) — march *target* across the swamp
    // load boundary from its real position; gated debug.opengoal.target.drive, OFF
    // by default.
    target_drive_maybe();

    // DIAG FLAGS (Gcrash-swamp-load debug-only) — arm the signal-handler repair
    // bypass so the TRUE first swamp-load crash reaches the fatal dump; gated
    // debug.opengoal.diag.norepair, OFF by default.
    diag_flags_maybe();

    // GRV-CANARY (Gcrash-rockvillage debug-only forensic) — gated
    // (env OG_GRV_CANARY / prop debug.opengoal.grv.canary), OFF by default.
    // Watches the target-stack return-trampoline band for the stomp writer.
    grv_canary_maybe();

    // ECO SPHERE SPAWN (Geco-spheres oracle-diff) — gated (env OG_ECO_SPAWN / prop
    // debug.opengoal.eco.spawn), OFF by default. Births an eco pickup next to
    // *target* via *listener-function*, replaying the x86 oracle's
    // birth-pickup-at-point form so eco spheres can be framed on-device per color.
    eco_spawn_maybe();

    // TOD-PIN (night A/B test lever) — gated (env OG_TOD_HOUR / prop
    // debug.opengoal.tod.hour), OFF by default, fires once. Pins the in-game
    // clock so the night pose is deterministic for the Gperf-particles A/B.
    tod_pin_maybe();

    // TOD-FAST (Gperf-particles2 capture lever) — gated (env OG_TOD_FAST / prop
    // debug.opengoal.tod.fast), OFF by default. ADVANCES the clock ~60x (a full
    // day->night in ~24s) WITHOUT pinning, for the real-moving-gameplay natural-TOD
    // correctness capture. Mutually exclusive with tod.hour (pin wins).
    tod_fast_maybe();

    // Geco-spheres TEMPORARY diagnostic — gated (env OG_ECO_TRACE / prop
    // debug.opengoal.eco.trace), OFF by default. Dumps the last spawned eco's physics.
    eco_trace_maybe();

    // ECHO-INTRO (new-game intro cinematic) deterministic warp — gated (env
    // OG_ECHO_INTRO / prop debug.opengoal.echo.intro), OFF by default, fires once.
    // Reaches the new-game intro cinematic directly, bypassing the title menu.
    echo_intro_warp_maybe();

    // Gcrash-mouche (Geyser Rock buzzer scout-fly pickup HUD-FX) repro/verify —
    // gated (env OG_MOUCHE_FX / prop debug.opengoal.mouche.fx), OFF by default.
    // Drives the manipy fly-to-HUD effect (the deterministic buzzer-collect crash)
    // via *listener-function*, the same dispatch-loop point the desktop oracle uses.
    mouche_maybe_fire();

    // Gdeath-crash — deterministic death/respawn repro+verify. Gated (env OG_DIE /
    // prop debug.opengoal.die), OFF by default. Forces Jak to die repeatedly via
    // *listener-function*, the same in-context dispatch point the desktop oracle
    // uses; see kmachine.cpp for the full rationale.
    die_maybe_fire();

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
