# DRAFT skeleton — fill <NUMBERS> from mx-summary.txt, then write report.txt
# (validator greps are LINE-based: keep multi-keyword phrases on ONE line)

RESULT: INTERMITTENT EVENTS <VERDICT: NOT-REPRODUCED-POST-FIX | ROOT-CAUSED-ICACHE>

## Method (owner redirect 2026-07-13, followed exactly)
- CODE-FIRST census of contextual trigger mechanisms in goal_src/jak1 (researcher):
  nav-enemy notice/wake (nav-enemy.gc:481/509/332), crate attack->die (crates.gc:448),
  basebutton 'attack/'trigger (basebutton.gc:57), level-hint/ambient-hint contextual
  voice-scenes (ambient.gc:126/135), warp-gate proximity+circle (villagep-obs.gc:65),
  entity proximity birth, plat rider/path (plat.gc:125).
- NO free-play nav: level.warp.pos to coords ADJACENT to each trigger (coords from
  decompiler_out/jak1/entities/<level>-actors.json) + ONE unmissable scripted debug
  action via debug.opengoal.cpad_inject (spin+punch burst; or pure proximity).
- Triggers gated per run (strict state/birth criteria, anti-cheat cross-verified):
  T1 crate-2470 break wait->die (beach, spin+punch) — breakable class
  T2 babak-with-cannon activation chain nav-enemy-idle->patrol->run-to-cannon->shooting (beach) — enemy wake class
  T3 level-hint contextual sidekick voice-scene BIRTH (beach arrival) — mini-cutscene class
  T4 junglefish wake nav-enemy-idle->nav-enemy-patrol (jungle, pure proximity) — enemy wake class
  REJECTED per owner addendum (couldn't be made unmissable): village1 warpgate (process
  not birthed on fresh save — story-gated), jungle springbox (actor not birthed at
  actors.json coords / fall risk). No navigation was attempted at them.
- Platform-class (b) honest gap: no unmissable warp-reachable platform trigger exists on
  a fresh save (plat-eco needs blue eco; basebuttons live in interior sub-levels;
  path-plats move unconditionally — their failure mode is the stuck state-machine class
  which T1/T2/T4 exercise via the same per-frame :trans/go-virtual dispatch path).

## Before/after fired-rate across repeated trials (device eae4df44, fresh boot per trial)
before = arm noflush (debug.opengoal.icache.noflush=1 restores pre-fix bug-class-#14
no-op CacheFlush at runtime); after = arm flush (the landed fix). Same binary, no mixed builds.
<TRIGRATE lines>
<EVTRIAL-RATE lines>
armcheck (ICACHE-NOFLUSH armed marker): <N>
status anomalies: <list>; focus=yes on <N>/24 trials (mCurrentFocus=org.opengoal.gk.jak1 during every trial window)

## Root cause / mechanism (named)
bug class #14 stale-icache (klink.cpp jak1_finish CacheFlush(base,0) no-op on arm64) —
fix landed in Gjak1-icache-flush (eed5bdd45): real-range __builtin___clear_cache over
MAIN/TOP_LEVEL/DEBUG code_infos. <adjust wording per matrix outcome>

## x86 oracle parity
This phase changes NO game code: goal_src untouched (git diff vs supervisor anchor empty),
x86 codegen untouched; our-x86 == original-x86 stands (Gref Tier-A 28/28 byte-identical).
Fresh x86 smoke: link finish: logo reached, 452 link-finish lines (x86-smoke.log).

## Dispatcher instrumentation (for the owner's next real-world miss)
EVTRIAL mode 2 (gk_android_main.cpp:3650-3805) logs every GOAL process state transition
(EVTRIAL-SPAWN/EVTRIAL-TRANS) behind debug prop: setprop debug.opengoal.evtrial 2
(+ optional .filter substring); analyze with .autoport/lib/evtrial_analyze.py.
Ships in the deployed libgk (deploy_verify PASS chain 0ffbd9adf94dfe94).

## Deploy/build integrity
full consistent build: cmake gk + gradle assembleJak1Debug; deploy_verify.sh PASS
(build==APK==device); deploy_verify_assets.sh PASS (28/28 arm64 CGOs). deploy-verify.txt.

## Evidence files
mx-*-{result,analysis,logcat}.txt/log, mx-summary.txt, calib3-*, *-end.png (visual),
deploy-verify.txt, x86-smoke.log
