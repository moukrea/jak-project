# Gffi-xmm-validate — arm64 FFI xmm8-15 (q24-q31) preservation fix: validation & ship

## TL;DR
The arm64 GOAL→C++ call trampolines in `game/kernel/asm_funcs_arm64.s` now save/restore
**q24-q31** (= arm64 **V24-V31** = goalc **xmm8-15**) around the C++ `blr`, instead of the wrong
**q8-q15**. This is the **root of the `f30-0` GOAL-float corruption class** (the spooled-anim
frame-rate scale in `loader.gc::ja-play-spooled-anim`, which manifests as the Gd1/Gcine cutscene
"slow-mo" / command-collapse and the title-spool anim rate). The fix is **provably correct by
construction**, the **load-bearing** trampoline is `_mips2c_call_arm64`, and a **wide device
regression soak** (boot → title → village flythrough → new-game intro cinematic → gameplay)
confirms the broad FFI change introduces **no regression**. x86 is **byte-unaffected** (the file is
arm64-only; SysV already caller-saves all xmm). This phase added **no game-source edits** (1-to-1)
and **no temporary instrumentation**.

This phase did NOT re-derive the fix (it was found+calibrated by Gfix-title-rays). It VALIDATES
correctness deductively, audits completeness, soaks for regression, and ships.

---

## 1. The bug (mechanism)
goalc's GOAL calling convention maps the GOAL float registers **xmm8-15** onto arm64 **V24-V31**
and treats them as **callee-saved** — i.e. the register allocator parks live GOAL floats there and
does **not** spill them before a call (mirroring x86's GOAL ABI). Under **AAPCS64**, however,
**V16-V31 are caller-saved** (clobberable) and only **V8-V15 (low 64 = d8-d15) are callee-saved**.
So any C++ / mips2c FFI callee may freely clobber V24-V31 — exactly the GOAL caller's live xmm8-15.

The old trampolines bracketed the C++ `blr` with a save of **q8-q15 (V8-V15)** — registers goalc
**never** uses for floats, and whose low halves AAPCS already preserves. The actually-live bank
(V24-V31) was left exposed, so a GOAL float held across a GOAL→C++ FFI call came back **garbage**.
The corrected trampolines save **q24-q31** with **exact ldp/stp pairing** (the old q8-q15 restore
used a register-pair swap — `ldp q10,q11` against `stp q11,q10` — harmless on the unused bank, but
corrupting on the real one; this is why a transient mis-pairing froze the title-spool fnum at 1.63).

## 2. Correctness — PROVEN deductively (verified against goalc source)
1. **xmm8-15 → V24-V31.** `goalc/emitter/Register.h:47-62` (enum `X86_REG`) numbers `XMM0..XMM15`
   as register ids **16..31** (`static_assert(N_REGS - 1 == XMM15)`, Register.h:215). The AArch64
   emitter encodes a vector reg as `arm64_reg5(r) = r.id() & 0x1f` with **no remap**
   (`goalc/emitter/IGenARM64.cpp:37-39`), placed directly in the Vd/Vn/Vm field of scalar/vector
   ops (IGenARM64.cpp:208-219, 287-308). Hence **xmm8 = id 24 → V24/Q24** and **xmm15 = id 31 →
   V31/Q31**.
2. **xmm8-15 are callee-saved in the GOAL CC.** `goalc/emitter/Register.cpp:35-42` sets
   `saved=true` for `XMM8..XMM15` (`m_saved_xmms`, Register.cpp:49-50). A call clobbers only
   `temp()` registers (`temp() = !saved && !special`, Register.h:224), enforced at
   `goalc/compiler/IR.cpp:798-803` — so live floats stay in V24-V31 **unspilled across calls**.
3. **x86 cross-check / x86 unaffected.** The same global `gRegInfo` (Register.cpp:75) drives both
   backends, so xmm8-15 are callee-saved on x86 too. x86 GOAL→C is safe because System V makes all
   xmm **caller-saved** (the C++ callee saves them), so no x86 asm change is needed. The fix is
   **arm64-only** and `asm_funcs_arm64.s` is not compiled into the x86 target — **our-x86 ==
   original-x86**.
4. **AAPCS64 clobber set.** V16-V31 are caller-saved; only d8-d15 (low-64 of V8-V15) are
   callee-saved. So V24-V31 (= xmm8-15) **are** clobbered by a C++ callee → the q24-q31 save is
   **necessary**; the old q8-q15 save protected registers goalc never uses.

Every one of these four points is VERIFIED with no contradiction. The fix is correct by
construction, independent of any device measurement.

## 3. Completeness audit — which trampoline is load-bearing
- The live general GOAL→C path on arm64 is the **inline thunk** emitted by
  `make_function_from_c_arm64` / `make_stack_arg_function_from_c_arm64`
  (`game/kernel/jak1/kscheme.cpp`), selected by the `__aarch64__` dispatch at kscheme.cpp:896-922.
  The `*_systemv` variants that reference `_arg_call_arm64`/`_stack_call_arm64` emit **x86 machine
  code** and are **not compiled for arm64**. Therefore **`_arg_call_arm64` and `_stack_call_arm64`
  are dead code on arm64** — their q24-q31 edits are correct but inert on this target.
- **`_mips2c_call_arm64` is the load-bearing fix.** It is BRanched-to by the dynamically generated
  mips2c trampolines (`game/mips2c/mips2c_table_jak1_arm64.cpp`) and is the path every mips2c body
  (the FP-heavy MIPS/VU re-implementations, incl. the joint-anim code in
  `game/mips2c/jak1_functions/joint.cpp`) returns through. The q24-q31 save here is what actually
  protects the GOAL caller's xmm8-15.
- **f30-0 routes through `_mips2c_call_arm64`.** In the spool loop (`loader.gc:683-738`), f30-0 is
  held across calls to `spool-push`, `current-str-pos`, `current-time`, `current-str-id`,
  `str-play-async`, `execute-commands-up-to` — all **pure GOAL** (field reads / RPC-queue writes,
  no C FFI) — and the joint-anim update (`ja-no-eval :frame-num` / `seek!`), which is **mips2c**
  (→ `_mips2c_call_arm64`, fixed). The clobber that "stomps the v8-15 callee-saved bank across the
  deep loader calls" (loader.gc:703 comment) is the FP-heavy mips2c joint body. **The fix is
  therefore sufficient to kill the f30-0 class.**

## 4. A real but LATENT gap (documented for a future hardening phase — NOT fixed here)
`make_function_from_c_arm64` (kscheme.cpp:644-649/736-741) and
`make_stack_arg_function_from_c_arm64` (kscheme.cpp:857-859) save only x29/x30 + x13/x14/x15 around
their `blr x16` and save **no V/Q registers**. A C FFI leaf that clobbers V24-V31 on these paths
would corrupt a GOAL caller's xmm8-15. This gap is **latent**: it is NOT reached by the f30-0
spool loop (whose FFI is mips2c, not make_function_from_c, and whose remaining leaf calls are pure
GOAL). It is out of scope for this phase (which is restricted to `asm_funcs_arm64.s`) and is
recorded here as a recommended future hardening: add the same q24-q31 save/restore to the two
inline thunks (and/or route them through `_arg_call_arm64`/`_stack_call_arm64`, which are already
correct). No known current symptom depends on it.

## 5. f30-0 corruption class — impact and the established probe
The `f30-0` class is the GOAL-float-across-FFI corruption. Its known manifestations: the title
spool anim rate, and the **Gd1/Gcine cutscene "slow-mo" / discrete-cut collapse** (the spool
coroutine's float state collapsing so `ja-aframe-num` spikes toward the raw stream position and
`execute-commands-up-to` fires every remaining command at once). Two pre-existing translation-layer
**workarounds** compensated for this at the symptom level and are now **redundant at the root**
(record for a future cleanup phase; per the phase mandate they are **left in place here**):
- the `og:autoport Gcine-cut` recovery branch in `loader.gc:697-726`, whose `spike?` test is
  **dead on x86 by design** and goes dead on device once f30-0 is preserved; and
- the Gd1 wall-clock 60Hz IOP-vblank pacer thread (`android_gfx.cpp`).

**Established device probe (cited, with honest caveat).** Gfix-title-rays calibrated on device that
the saved SIMD bank provably controls the title-spool fnum at a fixed render frame:
`q8-q15 (clobbered) → 63.66`, a transient register-pair SWAP → `1.63` (frozen — proving f30-0
literally lives in that bank), corrected `q24-q31 → 61.67` (stable). HONEST CAVEAT: the title spool
was coincidentally tolerant — 61.67 is within sampling jitter of 63.66 — so the **deterministic**
win is the **cutscene** class, not the title number. The strongest evidence for this validation is
therefore the **deductive correctness proof (§2)** plus the **routing analysis (§3)** plus the
**wide regression soak (§6)** that exercises the mips2c-routed cutscene crash-free into gameplay.

## 6. Device regression soak (the critical check)
Driver: `.autoport/lib/f1_run.sh` (builds current-HEAD libgk, slim-APK deploy, `deploy_verify`,
arms the prop-gated F1-STATE census, injects START → NEW GAME → CONTINUE WITHOUT SAVING, captures
`.autoport/reports/F1-boot.log`). Window covers boot → title → village flythrough → new-game intro
**cinematic** → Geyser Rock **gameplay**. Frame metric = the 60 Hz `A42-STRCLK vblank` counter
(`game/overlord/jak1/srpc.cpp:488`). Full numeric results are in
`.autoport/reports/Gffi-xmm-validate/soak.txt`.

<!-- SOAK-RESULTS -->
**Result (HEAD 563e11b13, device eae4df44): PASS — no regression, f30-0 preserved.**
- `deploy_verify` PASS (sha256 chain build==APK==device `7831e82059c7a2a7`; arm64 FFI asm
  recompiled this build).
- Run 1 (f1_run.sh): clean boot → title → ndi-intro cinematic → village1 flythrough → injected
  NEW GAME → settled Geyser Rock gameplay (master-mode=game; F1-STATE matched the x86 oracle
  field); **0 crashes**; DET=pass. (f1_run.sh stops logging at settled-spawn ~frame 1770, so Run 2
  extends it.)
- Run 2 (extended_soak.sh): sustained gameplay to **max A35-RENDER frame = 10620 (≥10500)**,
  max game frame `target-pos f= 10635`, ~60 fps over ~9 min, monotonic 35→10620.
- **Crash assertion across the whole boot→flythrough→cutscene→gameplay window:**
  `Fatal signal / signal(4/6/11) / GK-DIAG sig=(4|6|11) = 0`, jak1 tombstones `= 0` →
  **sig(4/6/11)=0, crash-free**.
- Coverage markers: `engine: state=in-game`=1, cinematic markers (ndi-intro/logo-intro-2/
  title-obs/scene-player)=73, village1 flythrough (A42-TFTREE lvl=village1)=846 (127 tfrag draws),
  master-mode=game=709. Foreground at end = `org.opengoal.gk.jak1`.
- 8× `GD3 TARGET-TRANS-REPAIR` fired — expected protective arm64 NaN-trsqv repair-and-resume
  fixups (restore *target* root trsqv from last-finite), **not** crashes; the run continued cleanly.
- The f30-0-sensitive paths (the ndi-intro AND the new-game intro cinematics, both mips2c-routed)
  completed crash-free at full rate → empirically consistent with f30-0 preserved across the
  mips2c FFI (`_mips2c_call_arm64`, the load-bearing fix).

Full raw harvest: `.autoport/reports/Gffi-xmm-validate/soak.txt`.
<!-- /SOAK-RESULTS -->

## 7. Instrumentation / cleanliness
- **No temporary instrumentation was added in this phase.** The only code change is comment text in
  `game/kernel/asm_funcs_arm64.s` (re-attributing the fix from the falsified "title-ray linger" to
  the real f30-0 class, and recording the verified register-id derivation); it is **binary-neutral**.
- The F1-STATE census used during the soak is **permanent, prop-gated HEAD code**
  (`Merc2.cpp`, `debug.opengoal.f1.census`, OFF by default) — not a dump added or left by this
  phase. The prior phase's RAYGEOM / OG_RAY_DUMP / fnum probes were **already removed**; **no
  leftover dump code remains** in libgk for this fix.
- `.autoport/gold` is **pristine / untouched** (read-only; `git status --porcelain .autoport/gold`
  is empty).

## 8. Gates
- **x86 smoke:** `build-x86/game/gk` rebuilt clean and reaches **`link finish: logo`** (continues
  into logo-intro/logo-loop until the 90 s timeout — no fault). arm64-only change, x86 intact.
- **deploy_verify eae4df44:** device provably runs the freshly built HEAD libgk (sha256
  build == APK == device, built-after-source).
- **1-to-1 source:** zero `goal_src/**` edits in this phase (`git diff <supervisor-anchor> HEAD`
  and the working tree are clean of goal_src).

## 9. Files changed (this phase)
- `game/kernel/asm_funcs_arm64.s` — comment correction owning the validated q24-q31 fix
  (binary-neutral; the q24-q31 instructions themselves were landed by Gfix-title-rays at a467cfd82).
- Reports under `.autoport/reports/Gffi-xmm-validate/` (soak.txt, F1-boot.log copy) and this
  fix-summary. No `goal_src`, no `goalc/emitter/IGenX86_64.*`, no `.autoport/gold`.

## 10. What this fix does NOT claim
- It is **not** a visual fix of the title-ray "linger" (that is GLES additive-blend / framebuffer
  composition — pixel/oracle territory, explicitly out of scope and already reverted as a
  source-hack).
- It does **not** remove the Gcine-cut goal_src workaround or the Gd1 vblank pacer (both now
  redundant at the root, but left in place per the phase mandate; flagged for a future phase).
- It does **not** close the latent `make_function_from_c_arm64` V24-V31 gap (§4) — a separate
  future hardening item with no known current symptom.
