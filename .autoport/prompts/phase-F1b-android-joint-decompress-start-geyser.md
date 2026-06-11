# Phase F1b — fix the joint-decompress chain (camera flies, Jak animates) → press START → Geyser Rock, controllable

## Where we are (read these first)

- `.autoport/reports/F1a-attempt-1-progress.md` / `F1a-fix-summary.md` + commits 0688d2c7f, bb8f27164, 4d64159f9, f5ea1f07a — F1a delivered: **arm64 bug class #12** (swizzle_vf dup stand-in → cross products (cx,cx,cx); exact VSHUFPS now), the **merc/generic/sprite port** (Merc2 8 buckets + Generic2 10 + Sprite3; title merc draws verified bit-perfect AND executing live on-device — the remaining Adreno fault is village-data-specific, knob-isolatable via f1a_merc_* run-as files), the glad ES version-gate fixup, the Merc2 EE-base-under-chain-copy fix, and the camera verdict instruments.
- **THE blocker (named, method scripted)**: the title-course camera pose **freezes at the logo-loop respawn** while channels play and clone succeeds — `calc-animation-from-spr` is NOT the path (zero calls on both backends, honestly eliminated). The freeze lives in the **GOAL channel-eval decompress chain** (joint decompression). F1a's report scripts the opening moves: **TRS-per-joint dump (compare per-frame joint translation/rotation/scale against the x86 oracle) + a `joint.gc` op census against IGenARM64** — the exact method that found bug classes #11 (PSHUF/.ppach) and #12 (swizzle_vf): enumerate every SIMD op the joint decompressor emits, find the remaining stand-ins, fix with exact semantics. Secondary thread of the same event: the volumes/logo-slaves deactivate at the logo-loop respawn (the missing J&D logo).
- **This one fix feeds two mouths**: the same joint-decompress chain drives the title camera (via the camera-anim joint) AND every character skeleton — Jak cannot walk without it.

## Mandate (in order)

1. **Fix the joint-decompress divergence.** TRS-per-joint dump on both backends at matched frames → first divergent component → disassemble the decompress fn (joint.gc/bones.gc family) → op census vs IGenARM64 → fix the class with exact NDK-verified semantics (the #11/#12 pattern). Regen ALL 28 DGOs + sync APK; x86 CGOs must stay byte-identical; qemu ≥ 675. Verify: camera FLIES the title course (pose changes after f≈1200, locales change across late ticks), and the J&D logo returns if the logo-slaves reactivate with the un-frozen course (verify honestly; if the logo stays absent, name why).
2. **Press START.** Inject input on-device (the touch overlay maps START; `adb shell input tap` on the START overlay coordinates, or `input keyevent` through the virtual gamepad — the overlay-map line in the boot log gives exact coordinates). Verify the title reacts (menu/new-game flow) and drive to **Geyser Rock (the "training" level) loading**: watch for its DGO links in the routed logcat.
3. **Controllable Jak**: with the level in, inject movement (overlay D-pad taps/swipes or gamepad axis events) and verify **Jak's position changes** — evidence = (a) frames at different times show different viewpoints/positions in Geyser Rock, (b) any position/state telemetry in logs. If Jak renders but T-poses (anim residual) or the camera misbehaves in-level, capture + name it precisely.
4. **Captures**: boot → title → START → level load → movement; screencaps at meaningful moments (not just fixed ticks — after each injected input) + focus brackets. Reversible disables (xiaoji ×2, sshxmobile, ghplus), RE-ENABLE after.
5. **F1b-fix-summary.md** (≥ 80 lines, frames + focus proof + input-evidence timeline) or honest progress/next-blocker (≥ 80).

## Rules (unchanged)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; no hardcoded poses/transforms; no fake input evidence (injected events must appear in the same logcat timeline as the reactions); preserve ALL prior fixes. `export ANDROID_SERIAL=eae4df44` only; keyguard check; slim APK + run-as seeding; the f1a_merc_* knobs exist if the village-data Adreno fault needs isolating (fix it properly if it blocks Geyser Rock — Geyser has its own level data).

## Validator (`phase-F1b-android-joint-decompress-start-geyser.sh`)

F1a's gates with F1b names (report ≥ 80, ≥1 F1b-device-*.png, frame ≥ 300 AND tris > 0 in newest F1b logcat, nm renderer syms incl MercRenderer ≥ 5, gk_log_pipe, x86 smoke, qemu ≥ 675, no forbidden edits). Camera flight / START / control correctness judged by supervisor vision + log evidence.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

Twelve bug classes down; the thirteenth is cornered with its method already scripted. Fix the decompressor and two things happen at once: the camera finally flies the title course, and Jak's skeleton comes alive for the first press of START. The user is watching the device live. Go.
