# Phase Gffi-xmm-validate — validate & ship the arm64 FFI xmm8-15 preservation fix (root of the f30-0 float-corruption class)

## What was found (by Gfix-title-rays) — the fix is ALREADY in the working tree
`game/kernel/asm_funcs_arm64.s` (uncommitted in the tree) fixes the three GOAL→C++ arm64 call
trampolines — `_arg_call_arm64`, `_stack_call_arm64`, `_mips2c_call_arm64`. They previously saved
**q8-q15 (V8-V15)** around the C++ call; goalc actually maps **GOAL xmm8-15 → arm64 V24-V31** and
treats them as **callee-saved** (never spilled before a call, mirroring x86's GOAL ABI). An AAPCS
C++/mips2c callee clobbers V16-V31 (caller-saved), so any GOAL float parked in V24-V31 came back
garbage. The old q8-q15 save protected registers goalc never uses; the fix saves/restores
**q24-q31** (matching pairs, no swap). x86 is unaffected — `asm_funcs_arm64.s` is arm64-only and
SysV already spills all xmm; **our-x86 == original-x86**.

This is the **complementary half of the known A40 xmm8-15/V24-V31 ABI hole** (A40 fixed the
callee-side q-saves; this is the caller/trampoline side) and is **the root of the `f30-0`
float-corruption class** — the title spool anim-rate float AND the Gcine-cut/Gd1 cutscene
"slow-mo" f30-0 stomp. CALIBRATED on device: the saved-bank choice provably moves the title spool
fnum (buggy q8-15 → 63.66; corrected q24-31 → 61.67, stable, crash-free).

## Your job: VALIDATE it is correct and regression-free, then it ships. Do NOT re-derive.
This is a BROAD change (every GOAL→C++ FFI call). The risk is a regression somewhere else, so the
soak must be wide. NO game-source edits (`goal_src/**` stays 1-to-1). If you must touch code, it is
ONLY `game/kernel/asm_funcs_arm64.s` (e.g. to correct a register-pairing/stack-balance error you
find) — never goal_src.

### Required validation (deterministic, device + x86; no pixels)
1. **x86 unchanged:** `link finish: logo` (trivially true — file is arm64-only, but prove it).
2. **Device REGRESSION soak (the critical check):** clean boot → title → village flythrough →
   the NEW-GAME intro cinematic → gameplay reach, **0 crashes** (`GK-DIAG sig=(4|6|11)`, `Fatal
   signal`) across the whole window, app foreground=jak1 at end, reaches frame ≥ 10500. Changing
   the FFI register-save must not break ANY path. Run it through a long window (cutscene + gameplay).
3. **Confirm it KILLS the f30-0 corruption deterministically:** dump a GOAL float that lives in
   xmm8-15 across a GOAL→C++ FFI call (the spool/anim-rate f30-0 in loader.gc::ja-play-spooled-anim
   is the proven one) on device — show it is **preserved across the call (matches x86)** with the
   fix, vs corrupted without it. The title spool fnum (61.67 vs 63.66) is the established probe;
   if feasible, also sample the **cutscene** f30-0 (the Gd1 slow-mo path) to show that class is fixed.
4. **Note (don't act):** if this real root-cause fix makes the Gd1 cutscene-clock **vblank-pacer
   workaround redundant**, record that for a future phase — do NOT remove the pacer here.

## Validator (`phase-Gffi-xmm-validate.sh`) PASS requires
1. ZERO `goal_src/**` edits. The only code change is `game/kernel/asm_funcs_arm64.s` (the q24-q31
   save/restore in all three trampolines).
2. `.autoport/reports/Gffi-xmm-validate/soak.txt`: device boot→flythrough→cutscene→gameplay,
   **0 sig(4/6/11)/Fatal**, foreground=jak1, frame ≥ 10500 — with `RESULT: FFI XMM8-15 FIX VALIDATED
   (no regression, f30-0 preserved)`. Plus the f30-0/xmm8-15-float dump showing preserved-on-device.
3. Fix-summary `.autoport/reports/Gffi-xmm-validate-fix-summary.md` ≥60 lines (mechanism + the soak
   result + the f30-0-class impact); temp instrumentation removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1200`, `max_retries: 3`.
