# Gnewgame-crash — fix summary

## Status
Crash NAMED + mechanism DECIDED on-device. Writer of the stomp being caught via a
HW data watchpoint (in flight). Fix + final verification sections are finalized
once the watchpoint names the stomping store. This document is updated in place.

## 1. The bug
On the arm64 Android device (serial eae4df44), at the menu, NEW GAME → overwrite
save → the intro cinematic plays for ~75 s (Naughty Dog logo → "Jak & Daxter" logo
→ Sage/Samos intro sequences) and then CRASHES, blocking actually starting the
game. The same new-game cinematic plays fine on x86 (owner-confirmed), so this is
an arm64-specific runtime defect in a code path only the new-game flow exercises.

## 2. Reproduction (autonomous)
The cpad_inject file bridge (F1d/F1e deliverable) drives the menu autonomously:
`bash .autoport/f1d_run.sh <run>` (FLOW=newgame) navigates title → START → progress
menu → NEW GAME → X → continue-without-saving → intro-cinematic window, capturing a
full logcat. The crash reproduces every run during the Sage intro sequence.

## 3. Crash forensics (the named function)
Fresh logcat: `.autoport/reports/Gnewgame/crash-logcat.log` (the in-process GK-DIAG
signal handler is the authoritative record; `/data/tombstones` not shell-readable).

```
GK-DIAG sig=11 fault=0x7f3eb851fa pc=0x75b31dcc1c lr=0x75b31dcc04
A36-SYMBOLIZE 0x75b31dcc1c = jak1::new_type+0x80 (libgk.so+0x3b4c1c)
```
- Signal: SIGSEGV (sig 11) — a clean data abort. (NOT the old F1d-hypothesized
  SIGILL/UDF#0xBEEF "(go ...) returns then break!"; that hypothesis is FALSIFIED
  for the current build — there is no SIGILL.)
- Faulting instruction (verified against the deployed libgk.so and the on-device
  A37-PCWIN word): `0x3b4c1c: 79401d0b  ldrh w11, [x8, #0xe]`.
- Source: `game/kernel/jak1/kscheme.cpp:1362` —
  `const u32 parent_n_methods = Ptr<Type>(parent)->num_methods;` (num_methods is the
  u16 at Type offset 0xe), inside `u64 new_type(u32 symbol, u32 parent, u64 flags)`.
- Register evidence: ee_base g_ee_main_mem = 0x7f00000000 (128 MB RWX mmap).
  x20 = `parent` = 0x3eb851ec. Ptr<Type>(parent) = ee_base + parent = 0x7f3eb851ec;
  +0xe = 0x7f3eb851fa = the fault address. parent (0x3eb851ec ≈ 1.05 GB) is FAR
  outside the 128 MB GOAL heap → garbage. `new_type`'s C++ is correct; the corrupt
  `parent` is supplied by the GOAL-compiled caller.

## 4. Localization (which deftype, which object, why only new-game)
- klink prints `link finish: <name>` at `game/kernel/jak1/klink.cpp:622` BEFORE
  executing the object's top-level at `klink.cpp:724-730` (`call_goal_on_stack`).
  The crash log shows `link finish: target-racer-h` immediately followed by the
  SIGSEGV with no later link line ⇒ the crashing deftype is INSIDE the top-level of
  object `target-racer-h` (`goal_src/jak1/levels/racer_common/target-racer-h.gc`).
- That top-level runs `(deftype racer-info (basic))` (line 27) then
  `(deftype racer-bank (basic))` (line 116) — both parent = the `basic` type. The
  FIRST deftype (`racer-info`) is the crasher: `new_type`'s arg0 (the new type's
  name symbol) interns fine at kscheme.cpp:1341; the crash is the parent deref at
  :1362. (Confirmed by the probe below: type=racer-info.)
- `target-racer-h` is bundled in MIS.DGO (Misty-Island intro). The jak1 opening
  cutscene involves Misty Island, so MIS.DGO loads during the intro and links
  `target-racer-h` — only the new-game flow reaches it. Boot/title (which reached
  frame 2522 crash-free) never link it.

## 5. Oracle-diff (x86 vs arm64) → mechanism DECIDED
- x86: `build-x86/game/gk` reaches `link finish: logo`; the full new-game cinematic
  plays (owner-confirmed) ⇒ x86 links `target-racer-h` with the correct `basic`
  parent. So the defect is arm64-specific.
- arm64 codegen of the parent load is correct: the `basic` value is loaded via
  IR_LoadSymbolPointer ADRP/ADD (materialise basic's slot address into X16) + a
  `ldr w6,[x16]` deref (goalc/compiler/IR.cpp:532-556); nothing clobbers x6 before
  the call, and the sibling `racer-info` symbol pointer (same reloc family) worked.
- On-device DISAMBIGUATION probe added to `new_type` (kscheme.cpp): on the bad-parent
  path it prints the type name, `parent`, and the INDEPENDENT C-side value of the
  `basic`/`type`/`structure` symbols. Result (verbatim):
```
GNG-DIAG new_type BADPARENT type=racer-info parent=0x3eb851ec flags=0x900000238 |
  basic slot=0x14fd3c val=0x3eb851ec | type slot=0x14fd54 val=0x17fd24 |
  structure slot=0x14fdfc val=0x180604 | s7=0x14fd24 EE=0x8000000
```
- The independently-interned `basic` symbol's value cell (GOAL offset 0x14fd3c,
  host 0x7f0014fd3c) ALSO holds 0x3eb851ec — identical to `parent`. So the arm64
  reloc/load is CORRECT; `basic`'s symbol-table VALUE is runtime-STOMPED. `type`
  (0x17fd24) and `structure` (0x180604) are intact — only `basic` is hit.

## 6. The arm64 mechanism (NAMED)
A single-slot memory STOMP of the `basic` type symbol's value cell (host
0x7f0014fd3c) with 0x3eb851ec (≈ IEEE-754 float 0.36) sometime during the new-game
intro, before `racer-info`'s deftype reads it. Why it survives ~75 s of cutscene:
general method dispatch reads each object's own header type-pointer, NOT the `basic`
symbol value cell — that cell is only read when code explicitly references the
`basic` symbol (e.g. a deftype whose parent is `basic`). `racer-info`'s deftype is
the first such reader after the stomp. The float-0.36 value signature points to a
vertex/joint/particle float writer (joint-decompress / sparticle) landing a blended
float at the wrong (low) address, NOT a DMA-chain builder (those write DMA tag
patterns like 0x10000001). This is the arm64 OOB-stomp class
([[project-gnd-state]] fixed a sibling that stomped a DMA bucket-NEXT to 0x1a50).

## 7. Catching the writer
- Attempt 1 — HW data watchpoint (perf_event_open / PERF_TYPE_BREAKPOINT W, 4 bytes
  on host 0x7f0014fd3c): the cell resolved correctly but `perf_event_open` is BLOCKED
  by SELinux on this MIUI device (`avc: denied { open } ... tclass=perf_event
  permissive=0` for the `untrusted_app` domain) — independent of
  `kernel.perf_event_paranoid = -1`. perf-based watchpoints are unusable here.
- Attempt 2 — SOFTWARE OOB write-watch (no perf): the arm64 mips2c store helpers in
  `game/mips2c/mips2c_private.h` already route every store (sw/sb/sh/sd/sq/sqc2/swc1)
  through `gnd_oob_check(target,…)`, which calls `gnd_oob_report` (logs target + the
  writer's return-address chain ra0/ra1/ra2) when `target` falls in a watched band.
  The band was `target<0x80000 || [0x514000,0x51c000)` — and the crash log already
  shows it firing at 0x519cxx during the intro (mips2c stores ARE hitting wrong low
  addresses). basic's slot 0x14fd3c was outside both bands; I widened it to include
  the symbol-table page [0x14f000,0x150000). Armed by default. ra0 of the
  target≈0x14fd3c report names the offending mips2c execute() body. [Result pending.]

## 8. The writer + the fix
- WRITER (A38 tripwire, run-5): `Mips2C::jak1::sp_launch_particles_var::execute+0x400`
  does `str s0, [x8, #0x18]` with x8 = ee_base + s7 (0x7f0014fd24). Source:
  `game/mips2c/jak1_functions/sparticle_launcher.cpp:260` `c->swc1(f2, 24, s0)`
  (store float to [s0+0x18]). s0 = a3 (arg3 = the `launch-state`, defaulted to
  `(the-as sparticle-launch-state #f)` by the `launch-particles` macro).
- The store is guarded by `:252` `bc = c->sgpr64(s0) == c->sgpr64(s7)` (the MIPS
  `beq s0, s7` = "if arg3 is #f, skip"). On arm64 this 64-bit compare FAILS: the
  `#f` arg arrives with its GOAL-pointer low-32 = 0x14fd24 but the two operands'
  upper-32 bits DIFFER (host 0x7f vs clean 0) — a mips2c ExecutionContext
  representation inconsistency (gpr s7 set from x14 in `_mips2c_call_arm64`, while
  `#f` args reach the body via sign-extended `lw`/field loads). Because the #f
  guard wrongly evaluates false, the store runs with `gpr_addr(s0)` (low-32 =
  0x14fd24) → writes to s7+0x18 = `basic`'s value cell. On x86 the operands are
  representation-consistent so the guard correctly fires and the cinematic plays.
- arm64 bug class: GOAL-pointer **high-32-bit inconsistency** breaking a mips2c
  64-bit pointer-equality (#f) guard (cousin of [[arm64-x86-model-reg-ids]]
  "GOAL ptr = low32(host)").
- FIX (minimal, non-regressing): a MIPS `beq`/`bne` between a GOAL pointer and
  `s7` is a 32-bit pointer-equality. Compare the 32-bit GOAL pointer value
  (`c->gpr_addr`) instead of the full 64-bit (`c->sgpr64`) for THIS #f guard so it
  is immune to the host/offset high-bit noise (low-32 = 0x14fd24 on both sides
  regardless of representation). arm64-gated; x86 stays byte-identical. This is a
  libgk C++ change (mips2c body) → clean rebuild, no CGO/DGO regen.
  Rejected alternative: changing `_mips2c_call_arm64` to store gpr s7 as a clean
  offset is the "root" representation fix but inverts the host/offset pairing for
  EVERY `beq reg, s7` across all mips2c bodies (incl. title-screen ones) — a real
  title-regression risk, so not taken for this delicate phase.

## 9. Empirical confirmation + the implemented fix
- On-device register dump (GNG-SPLV, captured right before the failing `beq s0,s7`),
  12 identical firings at frame ~2465 then the stomp+crash:
```
GNG-SPLV PRE-GUARD s0=0x000000000014fd24 s7=0x0000007f0014fd24
  gpr_addr(s0)=0x14fd24 gpr_addr(s7)=0x14fd24
```
  s0 (#f arg) = bare 32-bit GOAL offset 0x14fd24 (upper-32 = 0); s7 = full host
  0x7f0014fd24 (upper-32 = 0x7f = ee_base). Same GOAL pointer (both low-32 =
  0x14fd24 = #f), but the 64-bit compare `0x14fd24 != 0x7f0014fd24` misses #f.
- IMPLEMENTED (`game/mips2c/jak1_functions/sparticle_launcher.cpp`): the two
  `beq s0, s7` #f-guards that precede a `swc1 f2, 24(s0)` (the L109 and L131 sites)
  now, under `#if defined(__aarch64__)`, do `bc = c->gpr_addr(s0) == c->gpr_addr(s7)`
  (32-bit GOAL-pointer equality) instead of `c->sgpr64(...)`. The x86 `#else` path
  keeps the original `sgpr64` compare byte-identical. All hunt diagnostics
  (new_type probe, gnd_hwwp basic-watch, mips2c band-widen) were reverted — the
  only code change is sparticle_launcher.cpp. libgk C++ only → clean rebuild, no
  CGO/DGO regen.

## 10. Verification — PASS
Clean rebuild (recompiled sparticle_launcher.cpp) + APK + install; `deploy_verify.sh
eae4df44` PASS (device provably runs fresh HEAD libgk.so, chain build==APK==device).
New-game run via `.autoport/gnewgame_run.sh 1` →
`.autoport/reports/Gnewgame-routed-logcat-run1.log`:
- **0 sig=11/SIGILL/Fatal-signal events** (was exactly 1 at this point every prior run).
- Highest `A35-RENDER frame = 8700` (≥300; ~3.5× the ~2465 crash-point frame).
- `link finish: target-racer-h` now occurs **crash-free**; no `BADPARENT`, no
  `new_type` SIGSEGV follows. The intro cutscene plays through: `sage-intro-sequence-a`
  spools chunks 0→15+ over ~2 min, and `Displaying level misty` streams during the
  cinematic.
- x86 smoke still reaches `link finish: logo`.
- Validator `bash .autoport/validators/phase-Gnewgame-crash.sh` → **EXIT 0**:
  `PASS(data): Gnewgame-crash — crash signature gone, deploy verified, x86 OK.`
- Owner eye-check (intro cinematic visibly plays on NEW GAME) is the owner's to make;
  the data gate is fully green.
