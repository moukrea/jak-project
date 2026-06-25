# Phase Gportal-crash
BLUE-ECO PORTAL REACHED CRASH-FREE

## Reproduction (PREFERRED) — use the Ginput-replay harness (owner records once → infinite replay)
This crash is navigation-gated (Jak must charge the blue-eco portal/gate). Do NOT burn the attempt
trying to drive there programmatically. Use the `Ginput-replay` harness:
1. Supervisor boots the device build with recording armed; the OWNER plays from idle to the portal
   crash ONCE; the demo `.autoport/demos/portal-crash.inputs` is pulled from the device.
2. Replay the demo **deterministically on arm64** (reproduces the crash every time, no owner) and on
   **x86** (does NOT crash). Capture sig/pc/lr/fp-walk + content canary at the arm64 crash frame.
3. Compare the **state x86 vs arm64 anchored on the deterministic LOGICAL state** (process/control
   state, game event, logic tick — NOT render frames, which are framerate-dependent): variables/floats
   must be bit-identical; the **first divergent state/value** names the arm64 bug. Fix it in the
   translation layer; **replay-verify** ≥5× crash-free with arm64 state == x86 state.
If the harness is unavailable, fall back to the x86-first method below.

## Method (mandatory) — x86-first, fix the ARM divergence in the TRANSLATION layer, goal_src 1-to-1
This is an arm64-vs-x86 divergence (float/codegen/variable/state/renderer-family or merc/DMA stomp).
x86-first: confirm the original x86 does NOT have the bug. Dump the relevant deterministic state on
x86 vs device, name the first value that diverges, fix it in the translation layer (goalc arm64 /
mips2c / game/graphics / android) so arm64 == x86. NO game-logic rewrite ([[porting-1to1-fix-in-translation-layers]]).
Owner eye/ear = final.

## Validator PASS requires
1. `.autoport/reports/Gportal-crash/report.txt`: x86-first BEFORE(device diverges)->AFTER(device == x86) with
   `RESULT: portal|gate|blue.?eco|eco-?vent; sig|crash|reach`. Name the arm64 divergence/cause.
2. goal_src 1-to-1; real translation-layer change; fix-summary `.autoport/reports/Gportal-crash-fix-summary.md`
   >=60 lines; temp instrumentation removed; golden pristine; x86 `link finish: logo`; device boots
   crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1500, max_retries 4.
