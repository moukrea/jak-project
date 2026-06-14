# Gsprite — un-noop the arm64 sparticle sprite-DMA builders (SCE "presents" renders)

## Goal

Gsce restored the boot "Sony Computer Entertainment presents" static-screen
SPAWN, but it rendered BLACK on arm64. The SCE screen (and screen-space sprites
generally) are built each frame by the jak1 sparticle sprite-DMA functions,
which are `def-mips2c`. On arm64 a mips2c function only runs if it is on the
allowlist (`kSet` / `a37_name_is_real`) in
`game/mips2c/mips2c_table_jak1_arm64.cpp`; otherwise it is bound to the shared
NOOP. The sparticle builders were NOT on the allowlist, so the screen-space
sprite bucket stayed empty (A35-RENDER draws=1-2 tris=2-4 in the SCE window)
and the screen was black. x86 has no noop allowlist, binds the real bodies, and
renders — i.e. this was an arm64-only divergence, the same class as the A37
camera fix ("mips2c was noop-bound, not codegen").

## What was un-noop'd (the allowlist change)

Added to the arm64 mips2c allowlist (`kSet` in
`game/mips2c/mips2c_table_jak1_arm64.cpp`), bound by the committed history of
this branch:

- `sp-launch-particles-var` — the per-frame launcher (sparticle-launcher.cpp).
- `sp-process-block-2d`     — the 2D screen-space sprite-DMA block builder.
- `particle-adgif`          — the adgif-shader builder for the sprite blits.

These three are the complete 2D screen-space launch path that the SCE
static-screen (defpart 2966/2967/2968 -> `group-part-screen1`) depends on. The
only mips2c->mips2c edge among them (`sp-launch-particles-var` ->
`particle-adgif`) stays inside the set, so there is no half-enabled inner-noop.
`sp-process-block-3d` (the 3D world-particle processor) is intentionally left
on the shared noop fallback: it is off the SCE 2D path and is deferred to its
own oracle-diff phase. With the three 2D builders real, the SCE sprite bucket
now builds: SCE-window tris jump 4 -> 354 and the `GSCE-SCE-RENDER ... blitting
SCE presents` marker fires.

## The crash that attempt 1 left (frame ~185 SIGSEGV) and its real cause

Un-noop'ing alone exposed a SIGSEGV at frame ~185 (`fault=0x7f691edfe3`),
INSIDE `Mips2C::jak1::sp_launch_particles_var::execute` — at the launch-control
search loop (`block_31`, `c->lw(v1, 0, v1)`, the second load that dereferences
`[a3]` as a launcher pointer). Attempt 1 mis-diagnosed this as a 3D-builder
issue and narrowed the allowlist; the crash persisted unchanged (same fault
address), so that theory was falsified.

Root-causing it (this phase):

- The loop scans the launch-control's `data[]` array of `sparticle-launch-state`
  (base `s1+60`, stride 32, count `[s1+0]`) and dereferences each slot's
  `group-item` pointer. It is only reachable for an "armed" launch
  (launch-state arg3 != #f).
- The mips2c body is the SAME shared C++ compiled for x86 and arm64. An x86
  build running the identical body through the title flythrough NEVER crashes:
  instrumentation showed launch-control there is always a valid pointer and the
  per-call counts are small (<= 0x16d). So the divergence is environmental
  (the inputs), not the translated body.
- The launch-state (arg3) and launch-control (arg4) are passed as a PAIR by the
  only jak1 callers that arm this loop — `sparticle-launch-control::spawn`
  (`goal_src/jak1/.../sparticle-launcher.gc:728` and `:773`), which pass
  `:launch-state a3-0 :launch-control this`. There is NO jak1 call site that
  passes a valid launch-state with a #f launch-control. So the crashing
  combination (valid state, #f control) cannot occur legitimately.
- In the mips2c body, `s1` (launch-control) is assigned exactly once, at entry
  (`c->mov64(s1, t0)`, the arg4 register), and never rewritten before the loop.
  The crash shows `s1` low-32 == `#f` (0x14fd24). Therefore arg4
  (launch-control) was already #f AT ENTRY — the GOAL caller delivered #f.
- The bad arg4 arrives with GARBAGE HIGH bits (low-32 == #f, high-32 != 0): a
  full-width compare (`sgpr64`) against #f misses it, which is why an earlier
  64-bit guard did not catch it; a 32-bit (`du32`) compare does. Garbage high
  bits indicate the arg-register was not cleanly written by a 64-bit move from
  `this` — it retained a stale value while the regalloc believed `this` still
  lived in that register.

### Conclusion on root cause

This is an arm64 GOAL-**caller** codegen defect: the launch-control argument
(GOAL R8 / the 5th GPR arg, arg index 4) is intermittently lost — most armed
launches deliver it correctly, but some (e.g. the title sky 3D-particle path)
deliver #f. The prime suspect is the arm64 integer divide/mod, which is
hardcoded to physical X8 (= GOAL R8 = arg4) in
`goalc/emitter/IGenARM64.cpp` (`idiv_gpr32`/`unsigned_div_gpr32` emit
`sdiv/udiv X8, X8, Xn`); the regalloc models IDIV as clobbering RAX, NOT R8, so
a live arg destined for R8 is invisible to it. `sparticle-launch-control::spawn`
performs per-frame integer `(mod ...)` operations (sparticle-launcher.gc:752-753)
immediately before its launch call, exactly the pattern that can leave R8
clobbered when the arg move is coalesced away. This is the SAME x8/R8 hazard
class already known on arm64. It is NOT a flaw in the sparticle builders' own
translation — those build the SCE sprites correctly.

## The fix (this phase)

The sparticle BUILDERS are correctly translated (the SCE sprites build and
render — see evidence). The crash is bad input from a separate arm64 caller
codegen bug. The honest, in-scope fix hardens the search loop against the #f
launch-control rather than masking the builders, in
`game/mips2c/jak1_functions/sparticle_launcher.cpp`:

1. Pre-loop bail (the primary fix): when the launch-control low-32 == #f, skip
   straight to building the sprite (`goto block_37`). Registering a launched
   particle into a non-existent launch-control is meaningless; the particle is
   still built and rendered by the rest of the function (`sp-adjust-launch`,
   `sp-euler-convert`, `sp-rotate-system`, `particle-adgif`). The compare uses
   `du32` because the bad arg can arrive with garbage high bits.
2. In-loop defense-in-depth: never dereference a slot whose `group-item` is
   neither #f nor a plausible GOAL heap pointer (< 256 MB); treat it as a
   non-match and keep scanning. With the pre-loop guard this never fires in
   practice, and x86 never hits it (its `data[]` is intact).

This matches the game invariant (an armed launch should have a valid control)
and degrades gracefully on arm64 when the arg bug produces #f: the affected
particle still renders, it merely is not registered in the launch-control's
re-launch tracking. No noop is left pretending to work; no painted/hardcoded
SCE image; the real translated builders run and emit sprite DMA.

## Evidence (device run 7, arm64, Redmi eae4df44)

- CRASH-FREE: `GK-DIAG sig=11` / `Fatal signal 11` / `exited due to signal 11`
  count = 0. The frame-185 SIGSEGV is gone.
- SCE sprite bucket builds: SCE-window (frames <= 120) tris = 354 (well above
  the ~4 empty-bucket baseline); `GSCE-SCE-SPAWN` and `GSCE-SCE-RENDER`
  ("blitting SCE presents") markers both present.
- Boot sustained: max frame = 1500; max tris = 113426.
- SCE screen RENDERS (no longer black): `Gsprite-device-run7-t05s.png` shows the
  readable SCE/ND intro text "Created and Developed by Naughty Dog, Inc.
  (c) 2001 Sony Computer Entertainment America Inc." in the SCE window. Gsce had
  this window black; the un-noop'd sparticle 2D builders now fill it.
- No title regression (G1 gate): `Gsprite-device-run7-t10s.png` shows the
  textured 3D village/title flythrough rendering normally.
- Broad 2D payoff confirmed: the same frame shows the 2D HUD/overlay sprites
  ("PRESS O TO USE") and a flame sparticle effect rendering — exactly the
  screen-space-sprite payoff predicted (menu/HUD/2D light up with the builders).
- Focus held on `org.opengoal.gk.jak1` for the whole run (Gsprite-focus-run7.txt).

## What else lights up

Un-noop'ing the 2D sparticle launch path lights up screen-space sprites
generally, not just the SCE screen: the in-world 2D overlay text and prompt
sprites (e.g. "PRESS O TO USE"), HUD-style overlays, and flame/eco sparticle
effects now render. This is the broad payoff the phase anticipated and helps the
later menu-overlay (Gmenu) work.

## Residual / hand-off

The underlying arm64 GOAL-caller codegen defect — the 5th GPR argument (GOAL R8
/ arg index 4) intermittently lost across an integer divide/mod because the
arm64 IDIV/UDIV emit hardcodes physical X8 (= R8), invisible to the regalloc —
remains and warrants its own dedicated codegen phase (fix: make arm64
IDIV/UDIV use the dest register + a true scratch such as X16/X17 instead of X8,
removing the X8/R8 hazard and the A17 spill mitigation entirely). That fix is
broad-blast-radius (every divide/mod on arm64) and out of scope for this
sparticle-rendering phase; the defensive guard above is the safe, targeted fix
that delivers the SCE render without that risk.

## Files changed (this phase)

- `game/mips2c/jak1_functions/sparticle_launcher.cpp` — pre-loop #f launch-control
  bail + in-loop group-item bound check in `sp_launch_particles_var` (the real
  translated builder runs and emits sprite DMA; no noop left pretending).
- `game/mips2c/mips2c_table_jak1_arm64.cpp` — sparticle 2D builders on the arm64
  allowlist (committed earlier on this branch).
