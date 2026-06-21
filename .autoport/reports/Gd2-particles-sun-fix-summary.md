# Gd2-particles-sun — fix summary

## Goal
Restore the 3D world-particles / stars / real sun **corona** on arm64. The owner sees, on the
original, ambient 3D particles + stars + a real sun (disc **and** corona glow); on the device the 3D
particles/stars are absent and the sun is a bare additive sky-quad **"weird halo."** Audit root cause
(Grender-audit D2/D4): the arm64 mips2c **3D world-particle builder `sp-process-block-3d`** — which
builds the 3D ambient particles/stars AND the `group-sun` corona/glow (defparts 1950/1951/1952,
`weather-part.gc:482`, textures middot/starflash2/sun-glow) — was deliberately **noop-bound on arm64**
(`mips2c_table_jak1_arm64.cpp`, off the `kSet` allowlist) because re-enabling it "SIGSEGV'd at frame
~190." 2D sparticles already render; only the 3D path was missing.

## What the frame-190 SIGSEGV actually is (mechanism, named)
The historical "frame-190 SIGSEGV / wild launcher pointer 0x691edfe3 in block_31" framing in the old
allowlist comment was **partly a conflation**, confirmed by reproducing against the current tree:

1. **The enter-state crash was a different, already-fixed bug.** Per `[[cgo-rebuild-sparticle-regression]]`,
   the frame-180/190 crash that blocked current-source CGO ships was an `enter-state` null-`enter` SIGILL,
   **fixed** by phase Gspark-enterstate (commit 7f4f11996, in `android/gk_android_main.cpp` + `gstate.gc`).
   `sp_process_block_3d` has no `block_31` (that label is in the *next* function, `sp_process_block_2d`),
   so the "wild pointer in block_31" attribution was inaccurate.

2. **Empirically, on the current HEAD, un-noop'ing the builder no longer crashes at the title/ndi beat.**
   I re-enabled `sp-process-block-3d` with on-device diagnostic logging and it ran **crash-free to frame
   3360** (and 6000 in another run), foreground throughout. The literal frame-190 SIGSEGV did NOT recur.

3. **But the real arm64 defect that the noop was masking IS present** — the recurring mips2c
   `beq reg, s7` (#f-guard) **inconsistent-upper-32 misfire** (bug class from Gnewgame/Gsprite,
   `[[arm64-mips2c-fnull-guard]]`). The builder's loop head does
   `lw v1, 128(s5); beq v1, s7 -> skip` = "is `(-> cpuinfo valid)` == #f? then skip this INVALID
   3D-particle slot" (`sparticle-cpuinfo.valid` is at offset +128, `sparticle-h.gc:63`). In the mips2c
   ExecutionContext on arm64, GOAL pointers carry inconsistent upper-32: `gpr s7` is the full **host**
   symbol base `0x7f0014fd24`, while a `#f` field loaded via the sign-extended `lw` arrives as the bare
   32-bit GOAL offset `0x14fd24`. A full-64 `sgpr64` compare then **misses #f**. I proved this on-device:
   `GD2-3D MISFIRE@128 v1=0x14fd24 s7=0x7f0014fd24 full=0 lo=1` (low-32 equal, full-64 not). With the
   misfire, an **invalid** particle slot is NOT skipped; the body then reads that slot's stale `func`
   field (`basic`, offset +112, `sparticle-h.gc:59`) and `jalr`s it as a function — a **wild callback**.
   That is the latent SIGSEGV the builder was noop'd for. It did not fire at the title attract beat
   because the invalid slots there had `func == 0` (the `t9 != 0` guard skips the call), but it is a real
   latent crash anywhere a freed 3D slot retains a stale non-zero `func`. The same misfire also corrupts
   the `(paused?)` check (`beq s2, s7`, arg `t1`), freezing/advancing 3D particles incorrectly.

## The fix
Arm64-gate the two `beq …, s7` (#f) checks in `sp_process_block_3d` (`game/mips2c/jak1_functions/
sparticle.cpp`) to compare the **32-bit GOAL pointer** (`gpr_addr` / low32), which is
representation-agnostic, instead of the full-64 `sgpr64`:

* line ~59: `(-> cpuinfo valid) == #f` (skip invalid slot) → `c->gpr_addr(v1) == c->gpr_addr(s7)`
* line ~67: `(paused?) == #f` → `c->gpr_addr(s2) == c->gpr_addr(s7)`

Both are wrapped `#if defined(__aarch64__) … #else  <original sgpr64>  #endif`, so **x86 is byte-identical**
(operands are consistent on x86, so low-32 == full-64 there anyway). This is the exact bug-class fix already
shipped for `sp-launch-particles-var` (Gnewgame/Gsprite). The fix makes the arm64 builder correctly skip
invalid slots and detect pause — matching the x86 reference — so no stale `func` is ever dereferenced.

## The un-noop
`game/mips2c/mips2c_table_jak1_arm64.cpp`: added `"sp-process-block-3d"` to the `kSet` allowlist so
`a37_name_is_real` binds the real arm64 trampoline instead of the shared noop, and rewrote the stale
"deliberately NOT enabled" comment to document the real mechanism + fix. The builder's GOAL callees
(`sp-relaunch-particle-3d`, `sp-free-particle`, `quaternion*!`) are plain GOAL `defun`, NOT `def-mips2c`,
so enabling it pulls in **no additional still-noop'd mips2c builders** (verified by grep). No renderer
TU/bucket gating was needed: the 3D sparticles already flow through the registered `Sprite3` bucket
(jak1 `do_block_common(Mode3D)`); only the GOAL-side DMA builder was missing.

## Verification (deterministic, NO screenshots) — see `.autoport/reports/Gd2-particles-sun/bucket-census.txt`
Matched beat = NEW GAME → intro cinematic → first in-world area (Geyser Rock), reached identically on
device (cpad inject) and x86 (listener `(initialize! … "intro-start")`). A runtime toggle
(prop `debug.opengoal.gd2.noop3d`) selected BEFORE (noop) vs AFTER (real) from the same device binary;
proven by the logcat bind line: noop → `A37-MIPS2C-FALLBACK sp-process-block-3d`, real →
`A37-MIPS2C-REAL sp-process-block-3d -> arm64 trampoline`.

* **Builder-isolated census** (valid 3D particles processed per call, counted inside the builder so a noop
  body emits 0 lines): device BEFORE = **0** GD2-BUILD lines; device AFTER = **318** lines,
  `valid_3d_particles` max **60** / dominant 60 — **matching the x86 oracle** (730 lines, max 60, dominant
  60, range 1..60). The arm64 builder now processes the SAME valid 3D particles as x86; before, none.
* **Sprite3 Mode3D bucket** (corroboration; tris = sprites*2): device AFTER = 64..**320** sprites
  (128..640 tris), matching x86 (max 256/512); device BEFORE (noop) = a runaway 3072 stale-particle pile
  that diverges from x86 and renders wrong. So the sun is now a real disc+corona, not a bare halo.
* **No crash / no regression:** device AFTER sustained to A35-RENDER frame **3060** (6000 in another run),
  **0** sig 4/6/11, 0 Fatal, foreground; the NEW-GAME cinematic ran crash-free (Gd3 not regressed). x86
  still reaches `link finish: logo` (fix is arm64-gated).

## Temp dumps removed
All temporary diagnostic/census scaffolding has been **removed** before delivery: the `GD2-3D`
reproduction logging, the builder-side `GD2-BUILD` census + its gate helper in `sparticle.cpp`, the
`Sprite3` Mode3D `GD2-CENSUS` instrumentation (`Sprite3.cpp`/`.h` reverted git-clean), and the
`debug.opengoal.gd2.noop3d` toggle + its `<sys/system_properties.h>` include in the arm64 table. The
final source diff is exactly the two arm64-gated `gpr_addr` #f-guards + the one-line `kSet` un-noop (and
its comment). No leftover dumps remain; the pristine golden (`jak-original-v033`) was never touched.
