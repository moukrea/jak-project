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
 * TASK CLOSE (Gcrash-rockvillage debug-only repro tool) — env OG_TASK_CLOSE / Android
 * prop debug.opengoal.task.close = "<task>[:<status>][,...]" (status default 7 =
 * need-resolution), OFF by default. Closes game-task cstages on the GOAL kernel thread
 * via the same *listener-function* trampoline, so a device repro can cross task-gated
 * content (e.g. village2-warrior-money=33 pontoons). Never armed in the shipped APK.
 */
void task_close_maybe();

/*!
 * WANT-LEVELS / WANT-DISPLAY (Gcrash-rockvillage debug-only repro tools) — env
 * OG_WANT_LEVELS / prop debug.opengoal.want.levels = "lev1,lev2" and env
 * OG_WANT_DISPLAY / prop debug.opengoal.want.display = "lev[,sym]", OFF by default.
 * Replay the exact load-boundary commands (load-state-want-levels /
 * load-state-want-display-level) on the GOAL kernel thread, so the village2->swamp
 * streaming transition can be triggered deterministically without a physical
 * polyline crossing. Never armed in the shipped APK.
 */
void want_levels_maybe();
void want_display_maybe();
void want_vis_maybe();

/*!
 * GRV-CANARY (Gcrash-rockvillage debug-only forensic) — env OG_GRV_CANARY / prop
 * debug.opengoal.grv.canary=1, OFF by default. Per-dispatch watch of the top 64
 * bytes of *target*'s main-thread stack (the enter-state return-trampoline band);
 * logs every change, tagging non-trampoline values as ANOMALY (the stomp writer).
 */
void grv_canary_maybe();

/*!
 * TARGET-DRIVE (Gcrash-swamp-load debug-only) — Android prop
 * debug.opengoal.target.drive = "<dx> <dz> <pin_y> <stop_z>" (RAW EE units, floats
 * OK), OFF by default. Each kernel dispatch, marches *target* (Jak) by (dx,dz) in
 * world space (optionally pinning y), holding at stop_z — so SWA.DGO streams in
 * from Jak's REAL position (a position-triggered load, not a want-levels replay).
 * Reads/writes *target*'s world trans via the guarded EE-memcpy pattern the
 * mouche_/eco_ hooks use. Never armed in the shipped APK.
 */
void target_drive_maybe();

/*!
 * DIAG FLAGS (Gcrash-swamp-load debug-only) — Android prop
 * debug.opengoal.diag.norepair, OFF by default. When "1", arms the gk_android_main
 * signal-handler bypass (gk_set_diag_norepair) so the three "repair-and-resume"
 * control-transfer handlers bail out and the TRUE first swamp-load crash reaches
 * the fatal forensic dump instead of being silently masked. No-op on desktop.
 */
void diag_flags_maybe();

/*!
 * INVALIDATE-PART-GROUPS-IN-RANGE (Gcrash-swamp-load fix) — called from
 * link_control::jak1_work_v3 immediately before each level-heap segment memcpy.
 * Clears every *part-group-id-table* slot whose sparticle-launch-group object lies
 * in the destination range about to be overwritten, so a straddled level
 * discard/re-register can't leave a dangling slot whose static `name` pointer has
 * been overwritten with an arm64 code word (which lookup-part-group-pointer-by-name
 * would then `string=` and SIGSEGV). Race-free: runs synchronously on the linking
 * thread right before the copy. Android-only; no-op on desktop.
 */
#if defined(__ANDROID__)
void invalidate_part_groups_in_range(u32 dst_goal, u32 size);
#endif

/*!
 * ECO SPHERE SPAWN (Geco-spheres debug-only oracle-diff tool) — env OG_ECO_SPAWN /
 * Android prop debug.opengoal.eco.spawn = "<pickup-type-int> [period [dx dy dz]]",
 * OFF by default. Repeatedly births an eco pickup next to *target* via the same
 * in-context *listener-function* trampoline, replaying the x86 oracle's
 * birth-pickup-at-point listener form so eco spheres can be framed on-device for
 * the per-color device-vs-golden screencap gate. Never armed in the shipped APK.
 */
void eco_spawn_maybe();

/*!
 * ECO PHYSICS TRACER (Geco-spheres TEMPORARY arm64-NaN diagnostic) — env
 * OG_ECO_TRACE / Android prop debug.opengoal.eco.trace = "1", OFF by default.
 * Per-dispatch dumps the physics state (trans / transv / world-sphere /
 * local-normal / gravity / base.y / flags) of the LAST eco pickup spawned by the
 * eco-spawn hook, so we can see which field first becomes NaN on arm64. Plain
 * printf like the SPART probes. Never armed in the shipped APK.
 */
void eco_trace_maybe();

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
