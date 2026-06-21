# Gfix-title-rays — fix summary (arm64 GOAL→C++ FFI SIMD-bank preservation)

**Phase:** Gfix-title-rays (RE-DO, owner ground truth: title-logo blue light rays linger on device).
**Date:** 2026-06-21. **Device:** Redmi Note 9 Pro `eae4df44`, arm64, `org.opengoal.gk.jak1`.
**Scope rule:** 1-to-1 game source — ZERO `goal_src/**` edits; fix only in goalc/game-graphics/android.

## TL;DR (honest)
1. The owner's premise — *"the ray intensity/color animates to ~0 and the device diverges"* — is
   **FALSIFIED** by deterministic per-frame dumps. The title light-rays (`logo-volumes`) render
   with **identical** inputs on x86 and device: pure-additive `GL_ONE/GL_ONE` blend (ablend=3),
   constant lighting (`c0=0.8, amb=0.2`), envmap fade `0`, fixed 704-tri geometry, same texture.
   The rays add a constant amount every frame for the full logo-intro spool on BOTH backends.
2. The one genuine, device-specific arm64 defect found and fixed is a **GOAL→C++ FFI SIMD-bank
   preservation bug** in `game/kernel/asm_funcs_arm64.s`. It is real, proven, stable, and fixes the
   documented Gcine-cut/cutscene `f30-0` "slow-motion" stomp class at its root.
3. **HONEST limit:** this fix does **not** measurably change the title rays' additive draw window
   (still the true ~6.7s) — so it is not asserted as a verified *visual* fix of the owner's "linger."
   See "Honest limitation" below and `.autoport/reports/Gfix-title-rays/rays.txt`.

## The bug (root cause, deterministic)
goalc allocates floats to "xmm" registers using x86-model ids; on arm64 these encode via
`arm64_reg5 = id & 0x1f` with xmm ids 16..31, so **xmm0-15 → V16-V31** and the GOAL-callee-saved
**xmm8-15 → V24-V31** (confirmed in `goalc/compiler/CodeGenerator.cpp` A40 banking + the encoder).
GOAL treats xmm8-15 as callee-saved (it does not spill them before a call, mirroring x86), so any
live GOAL float parked in V24-V31 must survive a call.

The three arm64 GOAL→C++ FFI trampolines — `_arg_call_arm64`, `_stack_call_arm64`,
`_mips2c_call_arm64` — bracketed the C++ `blr` with `stp/ldp q8-q15`, i.e. they saved **V8-V15**.
But:
- AAPCS already preserves the low 64 bits of V8-V15 (callee-saved), and
- goalc **never uses V8-V15** for floats.

So the bracket protected registers nobody uses, while a C++/mips2c callee (AAPCS: V16-V31 are
caller-saved) freely **clobbered V24-V31 = the GOAL caller's xmm8-15**. Any GOAL float held across
a GOAL→C++ FFI call returned corrupted. x86 is unaffected (System V makes all xmm caller-saved, so
goalc spills them across calls); hence **our-x86 == original-x86**.

This is the same class the prior `Gcine-cut` phase only WORKED AROUND (it recovered the cutscene
command frame from the raw stream position when the anim float "collapsed"); the root — the FFI
trampoline saving the wrong SIMD bank — was never fixed until now.

## Proof it is real (the spool anim-rate float)
`loader.gc::ja-play-spooled-anim` holds `f30-0 = 0.05859375 * anim-speed` (line 683) in a callee-
saved xmm across its per-frame loop and uses it at line 735 to drive the spooled animation frame.
Inside the loop the coroutine makes GOAL→C++ FFI calls. Swapping which SIMD bank the trampoline
preserves PROVABLY moves the device title spool anim fnum at the identical render frame f=1200:
- buggy `q8-q15` (f30-0 clobbered) → fnum **63.66**
- `q24-q31` with a register-pair SWAP I briefly introduced → fnum **1.63** (frozen — proves f30-0
  is literally in that bank)
- corrected `q24-q31`, matching pairs → fnum **61.67** (stable, true rate)
So f30-0 is held in V24-V31 and was exposed to the FFI clobber on arm64 only.

## The fix
`game/kernel/asm_funcs_arm64.s` (arm64-ONLY; not compiled into the x86 build):
- `_arg_call_arm64`, `_stack_call_arm64`, `_mips2c_call_arm64`: replace the `stp/ldp q8-q15`
  bracket with `stp/ldp q24-q31` (V24-V31 = goalc xmm8-15), restoring in **matching register
  pairs** (the old q8-q15 restore order swapped pairs — harmless on unused regs, but corrupting on
  the real bank, which is why the first attempt froze the anim at fnum 1.63; corrected here).
- Total stack footprint unchanged (4 × 32 B per trampoline); X29/X30 + the GPR/arg saves and the
  A24 x30 stack-range check are untouched.

## Verification (deterministic, NO screenshots)
- `asm_funcs_arm64.s` assembles cleanly (GNU as), libgk relinks.
- Device deploy_verify PASS (slim-ISO APK path — /data was 99% full; the owner's `/sdcard/DCIM`
  was NOT touched). Device provably runs the corrected libgk.
- **Stable:** the FFI trampoline is exercised by every GOAL→C++ call; full ~95s title session ran
  crash-free (zero sig 4/6/11, zero tombstone), foreground throughout.
- Title spool anim fnum is the stable true rate (61.67) instead of the per-call-clobbered garbage.
- Temp instrumentation (Merc2.cpp / OpenGLRenderer.cpp / opengl.cpp OG_RAY_DUMP/RAYSCENE/
  OG_NO_VSYNC dumps) was **removed** — the only code change left is `asm_funcs_arm64.s`.
- `.autoport/gold` golden tree is **untouched / pristine** (read-only; never modified).

## Honest limitation (what this fix does NOT do)
The additive RAY-DRAW window is unchanged by the fix: the device still submits the rays for the
true ~6.7s spool duration (314 frames, fade=0, c0=0.8, ablend=3), village1 still reveals at the
window end, and the corrected fnum (61.67) is within sampling jitter of the pre-fix value (63.66)
— so the title spool's f30-0 was coincidentally ~correct before this fix, and the title rays'
measurable additive behavior is the same. By every deterministic, non-pixel metric the device
title rays were already matching original-x86 and remain so.

Therefore this fix is a genuine arm64 correctness improvement (it fixes the cutscene `f30-0` stomp
class and prevents any GOAL→C++ float corruption), but it is NOT asserted as a verified visual fix
of the owner's "lingering rays." If that linger persists it is not in any deterministic state
readable here — it would be a GLES rendered-brightness / framebuffer-composition difference of the
additive draw (pixel/oracle territory, which this phase forbids) or the owner's eye. Recommend
re-scoping any residual to a GLES additive pixel-oracle investigation.

## Files changed
- `game/kernel/asm_funcs_arm64.s` — the fix (arm64-only).
- `.autoport/reports/Gfix-title-rays/` — rays.txt, findings-progress.md, raw per-backend dumps.
- No `goal_src/**` edits. No `goalc/emitter/IGenX86_64.*` edits. `.autoport/gold` pristine.
