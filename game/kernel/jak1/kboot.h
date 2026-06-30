#pragma once

/*!
 * @file kboot.h
 * GOAL Boot.  Contains the "main" function to launch GOAL runtime.
 */

#include "common/common_types.h"

#include "game/kernel/common/kboot.h"

namespace jak1 {

// Video Mode that's set based on display refresh rate on boot
extern VideoMode BootVideoMode;

/*!
 * Initialize global variables for kboot
 */
void kboot_init_globals();

/*!
 * Launch the GOAL Kernel (EE).
 * See InitParms for launch argument details.
 * @param argc : argument count
 * @param argv : argument list
 * @return 0 on success, otherwise failure.
 */
s32 goal_main(int argc, const char* const* argv);

/*!
 * Run the GOAL Kernel.
 */
void KernelCheckAndDispatch();

/*!
 * Stop running the GOAL Kernel.
 */
void KernelShutdown();

/*!
 * F1 (Geyser Rock) deterministic warp — env OG_F1_WARP / Android prop
 * debug.opengoal.f1.warp, OFF by default. Fires once on the GOAL kernel thread
 * from the dispatch loop; see kmachine.cpp for the full rationale.
 */
void f1_maybe_warp_to_geyser();

/*!
 * GENERIC LEVEL WARP (debug-only zone-sweep tool) — env OG_LEVEL_WARP=<continue-name>
 * / Android prop debug.opengoal.level.warp=<name>, OFF by default. Generalizes the F1
 * warp: warps directly into ANY jak1 level by its continue-point name via the same
 * in-context *listener-function* trampoline, so a device build can confirm each zone
 * loads + runs crash-free on real arm64 + GL. Never armed in the shipped APK.
 */
void level_warp_maybe();

/*!
 * ECHO-INTRO (new-game intro cinematic) deterministic warp — env OG_ECHO_INTRO /
 * Android prop debug.opengoal.echo.intro, OFF by default. Fires once on the GOAL
 * kernel thread from the dispatch loop, replaying
 * (initialize! *game-info* 'game (the-as game-save #f) "intro-start") to reach the
 * new-game intro cinematic directly; see kmachine.cpp for the full rationale.
 */
void echo_intro_warp_maybe();

/*!
 * Gcrash-mouche — buzzer scout-fly pickup HUD-FX repro/verify. Env OG_MOUCHE_FX /
 * Android prop debug.opengoal.mouche.fx, OFF by default. Spawns the manipy
 * fly-to-HUD effect (the buzzer-collect crash path) repeatedly from the dispatch
 * loop; see kmachine.cpp for the full rationale.
 */
void mouche_maybe_fire();

/*!
 * Gdeath-crash — deterministic death/respawn repro+verify. Env OG_DIE / Android
 * prop debug.opengoal.die, OFF by default. Forces Jak to die N times (mode via
 * OG_DIE_MODE / debug.opengoal.die.mode: respawn | endlessfall | drown-death |
 * movie | <attack-mode-symbol>) from the dispatch loop, so the arm64 death crash
 * can be reproduced and ">=5 crash-free deaths" proven; see kmachine.cpp.
 */
void die_maybe_fire();

}  // namespace jak1
