# Phase F1c — unfreeze the title camera (joint-1 channel), then press START → Geyser Rock, controllable Jak

## Supervisor note (read this first — F1b was a false green)

F1b's validator passed on STALE render evidence (the village renders from A42, satisfying frame≥300+tris>0 on an earlier attempt's logcat) while its real deliverable went unmet. F1b landed **zero code** (its close commit changed only reports + PNGs). What F1b DID deliver is a precise, oracle-confirmed **re-localization** — use it; do NOT repeat the disproven op-census hunt. This phase only PASSES with a real **`F1c-fix-summary.md`** backed by NEW on-device evidence the supervisor verifies by eye. An honest next-blocker is fine — it will block the phase (not pass it), and the supervisor will carry it forward. No false greens.

## Where we are (read these)

- `.autoport/reports/F1b-attempt-1-progress.md` — the re-localization. The title-camera freeze is **NOT another arm64 SIMD stand-in** (falsified 3 ways: quaternion interpolation works on arm64; the decompressor op-census is clean; F1a proved the camera matrix bit-identical). The master skeleton decompresses fine — **Jak/Daxter models animate**. The freeze is SPECIFIC to the `logo-cam-logo-loop` (and `-intro-2`) camera animation: `cb=0xb8 nj=2`; joint 0 `ctrl=0x8` (static), **joint 1 `ctrl=0xb` (dynamic big-trans + dynamic quat) = the frozen camera-look joint.** On device its decompressed output equals a single static pose; on desktop it flies. Time advances, frame-num cycles, skel is valid, `draw-status=0x3010080` (has-joint-channels), `othercam` (watcher) alive.
- F1a context: merc/generic/sprite ported (title merc draws execute live; the residual Adreno fault is village-data-specific, knob-isolatable via `f1a_merc_*` run-as files); bug classes #11 (.ppach/PSHUF) and #12 (swizzle_vf) fixed.

## Mandate (in order)

1. **Root-cause the joint-1 camera-channel freeze** along F1b's scripted §6 probe (NOT the op-census): dump, on BOTH backends at matched frames, the loop-camera channel's `joint-control` `active-channels`, per-channel `command` / `frame-num` / blend-weight, and determine whether joint-1 is **self-animated** (its own keyframe decompression) **vs fed by a copy** (`flatten-joint-control-to-spr` / `clone-anim` / the `*camera*` othercam copy path). The leading hypotheses, in order: (a) a **copy/clone path** that on Android copies a stale/zero source (the A42 chain-copy or a pointer-base divergence like the Merc2 EE-base bug F1a fixed — a GOAL-address read landing outside a copy buffer); (b) a **blend-weight** that resolves to 0 for the dynamic channel on Android (interp_time_of_day-style alpha=0, the bug-class-11 family but in the blend path, not the decompressor); (c) a control-bit / `ctrl=0xb` decode branch taken differently. Falsify each with evidence (matched-frame dumps), the way F1a/A42 did.
2. **Fix at the mechanism** — no hardcoded camera pose, no forced flight. Regen ALL 28 DGOs + sync APK if CGOs change; x86 CGOs byte-identical; x86 boots to logo; qemu ≥ 675. **Verify the camera FLIES**: A37-CAM pose CHANGES after f≈1200, and device frames at different ticks (≥30s apart) show DIFFERENT locales (not the same hut). Verify the J&D logo-slaves reactivate (logo visible) — or, if the logo stays absent for a separate reason, name it with evidence.
3. **Press START** — inject on-device (overlay-map coords are in the boot logcat: `overlay-map: ... start=X,Y,...`; `adb shell input tap X Y`, or gamepad keyevent). Verify the title reacts and drive to **Geyser Rock / "training"** level: watch the routed logcat for its DGO links (`training`, `geyser`, level-fr3 streams).
4. **Controllable Jak** — inject movement (overlay D-pad coords / gamepad axis), verify **Jak's position changes**: evidence = device frames at different times showing different viewpoints/positions IN the level + any position/state telemetry in the SAME logcat timeline as the injected events (no fake input evidence — the injected event and its reaction must co-occur in one capture).
5. **Captures**: title (camera flying) → START → level load → movement; screencaps at the meaningful moments (after each injected input, not just fixed ticks) + `mCurrentFocus` brackets (`F1c-focus-runN.txt`). Reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed RE-ENABLE.

## Rules

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; no hardcoded poses/transforms; no fake input evidence; preserve ALL prior fixes (xmm banking, mips2c table, vsync parity, chain copy-mode, PSHUF/swizzle semantics, merc port). `export ANDROID_SERIAL=eae4df44` only; keyguard check; slim APK + run-as seeding.

## Validator (`phase-F1c-android-camera-channel-start-geyser.sh`) — STRICT

The phase PASSES only with a real **`F1c-fix-summary.md`** (≥ 80 lines) — a progress/next-blocker report does NOT satisfy the report gate (it triggers retry, then an honest block). Plus: no forbidden edits; x86 smoke to `link finish: logo`; qemu ≥ 675; gk_log_pipe; nm renderer syms (DirectRenderer + MercRenderer ≥ 5); ≥ 1 `F1c-device-*.png`; the NEWEST `F1c-routed-logcat-*.log` shows frame ≥ 300 AND tris > 0 **AND a camera-flight marker** (A37-CAM pose delta after f≈1200, or a `training`/`geyser` level link). Camera-flight / START / control correctness is judged by the supervisor's own eyes + the log timeline.

## Max settings

`max_turns: 2000`, `max_retries: 3`.

## Strategic note

Twelve bug classes down; the thirteenth is NOT a codegen stand-in (opus proved it) — it's a narrow defect in the loop-camera joint-1 channel, almost certainly a copy/blend-weight path. Find which, fix it honestly, watch the camera lift off the hut floor, press START, and step into Geyser Rock. The owner is on opus-4-8 and watching the device live.
