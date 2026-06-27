# Gledge-glitch — fix summary

## One-line
arm64 `vftoi0` (mips2c float→int) diverged from the x86 oracle on NaN/overflow inputs
(`FCVTZS` saturates: NaN→0, +ovf→0x7fffffff; `cvttss2si` gives 0x80000000 for all of
those). NaN collision coordinates reach `vftoi0` in the collision broad-phase/bbox
quantization, so arm64 landed triangles in different grid cells / AABBs than x86 →
different collision triangles selected → wrong push-out at edges/borders → Jak "projected".
Fixed by re-emulating `cvttss2si` on arm64. goal_src untouched; x86 byte-for-byte unchanged.

## The owner defect
At ledges/borders Jak can grab or fall off, the collision glitches and seems to
project/launch Jak ("ça projette"). arm64-only; x86 fine. Reported after the recent
collision fixes landed.

## Regression check (mandated first step) — concluded NOT a regression of the named fixes
The three recent collision fixes are all the same arm64 `#f`-guard bug class
(`beq reg,s7` full-64 compare → `gpr_addr(reg)==gpr_addr(s7)` low-32 compare):
- `collide_edge_grab.cpp` (ef3b4f0f9, Gcrash-geyser): 11 conversions — verified all are
  genuine `== #f` symbol checks (JALR returns are `symbol`; lwu'd links are null?-tests).
  None compares a value whose low-32 collides with s7's offset (0x14fd24). Safe.
- `collide_cache.cpp` collide-puss-work m9/m10 (b45ec8230, Gcollision-wallslide): truncated
  return is declared `symbol`, only `#f`-tested in probe-using-spheres. Safe.
- `-ffp-contract=off` on the 5 jak1 collide TUs (49cc24b58): deploy-proven (fused=0 in the
  device libgk collide objects); leaf bit-identical (0/60000). Not the cause.
The `#f`-guard fix *enabled* the arm64 edge-grab search path (it previously mis-fired),
which is why a latent downstream float→int divergence only became visible afterward.

## Investigation method (x86-first, deterministic)
The owner input-demo replay desyncs from boot (record skips leading boot-neutral ticks via
idle-until-first-input, replay applies from cpad-read 0 → game stuck in logo-loop; a
Ginput-replay harness limitation, out of scope here), and blind cpad_inject drives at
Geyser reach the edge-grab states unreliably. So I localized the divergence with
DETERMINISTIC function-level differentials: a temporary C++ harness called the
GOALC/mips2c collision math with fixed inputs through the `_call_goal8` trampoline on x86
AND on the arm64 device, comparing bit-exact outputs; plus on-device per-lane firing
counters. This is framerate-independent and avoids the flaky replay.

## Ruled out (all bit-identical x86 == arm64-device)
- `vector-reflect-flat!`, `vector-cross!`, `vector-flatten!` (push-out reflect + edge-tangent
  cross) — identical even for grazing/denormal inputs.
- `forward-up-nopitch->quaternion`, `forward-up->quaternion`, `quaternion-normalize!`
  (edge-grab facing → target-edge-grab-jump launch direction) — identical.
- `vector-!`, `vector+!`, `vector-negate!` — identical.
- FP control: device FPCR=0x0 (FZ=0) == x86 MXCSR (FZ=0, DAZ=0); denormals preserved
  identically on both (FTZ/denorm hypothesis falsified).
- arm64 float compares are NaN-correct post-A34 (the wall/ground `sv-160` decision matches).

## Root cause (the named diverging value)
`mips2c_private.h` `vftoi0` is a bare `(s32)float` cast:
- x86 → `cvttss2si`: out-of-range / ±Inf / NaN → 0x80000000 (INT32_MIN).
- arm64 → `FCVTZS`: saturating — +ovf/+Inf → 0x7fffffff, NaN → 0, −ovf/−Inf → INT32_MIN.
Independently device-verified by cross-compiling the exact cast with the project NDK and
running it on eae4df44 vs x86 (BEFORE table in report.txt). `vftoi0` is used by the
collision path: `collide_edge_grab.cpp:72,74` (triangle bbox→int AABB rejection) and the
`collide_cache`/`collide_mesh`/`collide_probe` spatial-hash / bbox quantization (169 call
sites). It is the single arithmetic op in the collide delta that prior differentials never
covered — the proven-identical leaf (`collide_func.cpp`) has no float→int.

## Live-firing evidence (device, BEFORE)
On-device per-lane counter over one Geyser collision drive: `vftoi0` diverged 74948×, with
per-lane `[x=15886, y=20977, z=36493, w=1592]` — 97.9% on the meaningful x/y/z geometry
lanes, only 2.1% on the benign `.w` lane. Every captured diverging input is NaN (exp=0xFF).
The firing rate scaled with collision activity (203 at idle title → sustained ~6000–7600
per interval while colliding), proving the divergence is live in the collision path. So NaN
collision coordinates reach `vftoi0`; arm64 (NaN→0) vs x86 (NaN→INT_MIN) lands the triangle
or Jak's query box in a different grid cell / AABB → arm64 selects different collision
triangles than the validated x86 oracle → wrong/absent push-out at edges → projection.

## The fix (translation layer; goal_src 1-to-1)
`game/mips2c/mips2c_private.h` — arm64-only, `vftoi0` re-emulates `cvttss2si`:
```cpp
#if defined(__aarch64__)
  static inline s32 mips2c_vftoi_x86(float f) {
    if (!(f >= -2147483648.0f && f < 2147483648.0f)) return (s32)0x80000000;
    return (s32)f;
  }
#endif
  // in vftoi0's loop, on arm64: vfs[dst].ds32[i] = mips2c_vftoi_x86(s.f[i]);
```
NaN fails both comparisons → 0x80000000 (matches cvttss2si); in-range → `(s32)f`
(== FCVTZS == cvttss2si). The x86 path (`s.f[i]`) is byte-for-byte unchanged. `vftoi4`,
`vftoi12`, and the `_sat` variants are NOT used by collision and are left untouched.
Rationale: PS2 VU `ftoi0` actually saturates like ARM, but the autoport 1-to-1 contract
binds arm64 to the x86 OpenGOAL oracle the GOAL collision logic was decompiled/validated
against, so we match x86, not the raw PS2 hardware.

## Verification (AFTER — arm64 == x86)
- Re-ran the same cross-compiled differential with the fixed conversion on x86 and on
  eae4df44: ALL values identical on both (NaN→0x80000000, +Inf→0x80000000, +ovf→0x80000000,
  2^31→0x80000000, in-range unchanged). device == x86, 1-to-1.
- Clean rebuild deployed; `deploy_verify.sh eae4df44` PASS (build==APK==device).
- Device boots to gameplay via the F1 warp and survives a collision-stress drive crash-free
  (no boot or collision regression from changing the shared float→int op).
- x86 desktop still reaches `link finish: logo`.

## Temporary instrumentation — REMOVED
All temporary diagnostics added during the investigation were REMOVED before finalizing
(verified: `grep -rn 'GLEDGE|g_gledge|g_vftoi|g_eg_|gledge_dump|gledge_vecdiff'` over
`game/` and `android/` returns nothing). Files reverted to pristine HEAD: the per-tick
collision state dump + trace arming (`game/kernel/jak1/kmachine.cpp`,
`game/kernel/jak1/kboot.cpp/.h`, `game/system/pad_replay.cpp`, `android/gk_android_main.cpp`),
the GOALC vector/quaternion differential harness, the edge-grab bbox EGPROBE, and the
vftoi0 firing/per-lane counters (`game/mips2c/jak1_functions/collide_edge_grab.cpp`,
`game/mips2c/mips2c_private.h`). The ONLY remaining code change is the clean `vftoi0` arm64
fix in `game/mips2c/mips2c_private.h`. `git status --porcelain goal_src/` is empty (goal_src
1-to-1). `.autoport/gold` is pristine.

## Honesty / scope
The exact in-game projection (the edge-grab-OFF/-JUMP launch) was not directly reproduced
headless. The fix is validated at the level of the named divergence: a real, device-proven
arm64-vs-x86 collision float→int divergence that fires heavily on the meaningful x/y/z
collision-geometry lanes during collision, corrected so arm64 == x86. Owner visual
confirmation of the exact ledge is the final gate, per the phase.
