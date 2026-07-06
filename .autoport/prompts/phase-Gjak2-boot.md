## WORK ECONOMY (manager/worker delegation)
You are the MANAGER (claude-opus-4-8[1m], effort=xhigh): plan, decide, judge, verify. Delegate bulk
execution to subagents (autoport-researcher = read-only scans/oracle diffs; autoport-implementer =
mechanical edits to your exact spec; autoport-tester = builds/qemu/device runs/logcat/screencaps).
VERIFY every subagent claim yourself (read their diffs/logs). Parallelize independent runs.

# Phase Gjak2-boot — bring up JAK 2 on Android arm64: build + boot to render on device

## Context (2026-07-06 — new chapter after jak1 shipped complete)
The full jak1 Android arm64 port is DONE (184 phases, playable, owner-confirmed). Owner chose to
start jak2 next. jak2 is fully supported on x86 (OpenGOAL upstream): `goal_src/jak2/` (849 .gc),
`iso_data/jak2/` + `out/jak2/iso/` (151 CGO/DGO already compiled on x86). What's MISSING is the
Android arm64 bring-up: the Android build currently EXCLUDES jak2 (android/CMakeLists.txt ~266-269:
"jak2/jak3 kboot.cpp excluded — they call jak{2,3}::InitMachine"; android_runtime_full.cpp ~335:
"jak2/jak3 globals not init'd because we don't ship their subsets"). Android runs jak1 only.

## HUGE HEAD START — jak1's arm64 work is GAME-AGNOSTIC
Every arm64 codegen fix from jak1 (13+ named bug classes: mips2c gpr-s7/x14 double-EE-base, FFI
v24-v31 SIMD bank, 128-bit cc, LDP/RET epilogue, integer modulo msub, NaN float-compare, asm-func
x86 stack-RA contract, etc.), the GL->GLES translation, and the runtime glue are all in the shared
backend and libgk — jak2 inherits them for free. Expect jak2 to surface NEW emitter/mips2c paths
jak1 never exercised (jak2 is bigger + different systems), but the machinery is proven.

## Mandate — jak2 builds for Android arm64 AND boots to render on the device
1. WIRE the Android build for jak2: un-exclude jak2 kboot/InitMachine, ship the jak2 kernel subset +
   globals, add the jak2 game flavor/assets path (mirror the jak1 wiring), produce app-jak2-debug.apk
   (or a jak2-selectable build) with the jak2 arm64 CGO/DGO set.
2. Regenerate the jak2 CGO/DGO with the arm64 goalc (full consistent set) — same pipeline as jak1;
   restore the x86 oracle after (arm64 goalc must not leave x86 CGOs stale — see the known trap).
3. BOOT jak2 on device eae4df44: reach the boot/link milestone (`link finish` / kernel up /
   master-mode set) and get to RENDER (a frame on screen, app foreground). First render beat is the
   goal — full gameplay is later phases.
4. Fix any jak2-specific arm64 failures in the TRANSLATION LAYERS ONLY (arm64 codegen / mips2c /
   GLES / runtime glue / goal_src/jak2/pc/) — NEVER engine goal_src. Our-x86 jak2 MUST == original-x86
   jak2 (the decompiled GOAL source is the contract). If a jak2 emitter path breaks, fix the emitter.

## Verify (device eae4df44 = Redmi Note 9 Pro, arm64)
- x86 jak2 still builds + boots to its normal boot milestone (oracle intact; no goal_src/jak2 engine diff).
- Android jak2 build links clean (jak2 kernel/InitMachine compiled in; no unresolved jak2 globals).
- app-jak2-debug.apk produced, bundles the arm64 jak2 CGO/DGO + jak2 assets; deploy_verify PASS
  (build==APK==device libgk) for the jak2 build.
- Device boots jak2: logcat reaches the boot/link milestone + a render frame; mCurrentFocus =
  the jak2 activity/package; no native sig 11/6/4/7 on the app pid across the boot window.
- Report the arm64 bug classes hit + how each was fixed in the translation layer.

## Report (`.autoport/reports/Gjak2-boot/report.txt`) with `RESULT: JAK2 ANDROID BOOT <milestone>`
the Android-wiring diff, the arm64 CGO/DGO regen (byte-consistency vs x86 where expected), each
jak2-specific arm64 fix (file:line + which bug class), the device boot evidence (logcat milestone +
foreground + render frame + crash-free window), x86 jak2 oracle intact.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.* semantic changes for x86 (arm64
codegen only); engine goal_src (jak1 AND jak2, non-pc) UNTOUCHED — our-x86==original-x86; .autoport/gold
READ-ONLY; full CONSISTENT builds only (no mixed CGO/libgk); grep -a on routed logcat.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
