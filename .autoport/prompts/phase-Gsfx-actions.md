# Phase Gsfx-actions
ACTION SFX AUDIBLE (crate/orb/blue-eco/green-eco)

## Method (mandatory) — x86-first, fix the ARM divergence in the TRANSLATION layer, goal_src 1-to-1
This is an arm64-vs-x86 divergence (float/codegen/variable/state/renderer-family or merc/DMA stomp).
x86-first: confirm the original x86 does NOT have the bug. Dump the relevant deterministic state on
x86 vs device, name the first value that diverges, fix it in the translation layer (goalc arm64 /
mips2c / game/graphics / android) so arm64 == x86. NO game-logic rewrite ([[porting-1to1-fix-in-translation-layers]]).
Owner eye/ear = final.

## Validator PASS requires
1. `.autoport/reports/Gsfx-actions/report.txt`: x86-first BEFORE(device diverges)->AFTER(device == x86) with
   `RESULT: crate|orb|eco; rms|sound|snd-?play|silent`. Name the arm64 divergence/cause.
2. goal_src 1-to-1; real translation-layer change; fix-summary `.autoport/reports/Gsfx-actions-fix-summary.md`
   >=60 lines; temp instrumentation removed; golden pristine; x86 `link finish: logo`; device boots
   crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1500, max_retries 4.
