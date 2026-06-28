# Phase Gcollision-glitchcapture — capture the collision math AT the glitch during the owner's REAL play, diff vs x86

## Why (owner, 2026-06-28, firm)
The fmin/fmax fix was PROVEN op-level (576/576) but did NOT fix the in-game glitch — the owner still has
collision glitches. The real divergence only fires at degenerate/grazing contacts the headless cpad_inject
drive never reaches. The input record→replay approach FAILED 3× (neutral captures, replay desync). Owner:
"make it so I can record a REAL session so you can actually fix it, or the game is never playable." So we
MUST observe the real glitch — but robustly, without the fragile replay/input-capture machinery.

## Approach — GLITCH-TRIGGERED collision-math dump (no warp, no input-replay, input-source-agnostic)
Instrument the device build to DETECT a collision glitch as it happens during NORMAL owner play and DUMP
the exact collision-reaction math of that frame (+ a few prior). The owner just plays their real session
(their save / new game, their glitch spots, touch OR gamepad — irrelevant). When Jak projects/clips/under-
maps, the dump fires and captures the divergence's raw operands. Then feed those EXACT operands to the x86
collision math (oracle) — no gameplay replay needed — to find the op that diverges. This sidesteps every
prior failure (determinism, input capture under warp, replay desync).

## Method (mandatory)
1. **Glitch detector (device, arm64):** in the collision-reaction path (collide-reaction-target.gc area,
   accessed C++-side via libgk, NO CGO rebuild) watch for a glitch signature per frame — control `transv`
   magnitude spike (eject/projection), a one-frame Jak `trans` jump beyond a sane step (clip/under-map),
   or a non-finite/denormal in the reaction. On trigger, DUMP to a file (flush-per-hit): the frame's
   collision-math operands + results — separation vector, `vector-normalize!` in/out, every `fmin/fmax`
   in/out, surface/poly/ground/local normals, touch/surface/poly angles, ground-touch-point, the input
   velocity and the resulting `transv`, Jak `trans`. Keep a small ring buffer of the prior ~8 frames so the
   onset is captured, not just the blown-up frame.
2. **Owner plays a REAL session** (supervisor coordinates): natural play (no warp), reach the glitch spots
   (steps/walls, blue-eco, ledges, the under-map jumps). Each glitch appends a dump. Pull the dump file.
3. **x86 oracle on the captured operands — use the PRISTINE ORIGINAL, not our ARM-compat x86 (owner
   requirement 2026-06-28):** the oracle MUST be the unaltered original OpenGOAL x86 (`.autoport/gold` /
   `/home/emeric/code/jak-original-v033`), NOT our build (which carries arm64-gated changes). Either build
   the leaf differential from the pristine original source, OR prove our-x86 leaf path is byte-identical to
   the original — note: `collide_func.cpp` IS byte-identical to original and the arm64 changes are all
   `#if __aarch64__`-gated in mips2c_private.h, so the x86 path == original (verify the specific helpers
   used: vrsqrt/vdiv/vmini/vmax). Temporary debug instrumentation is fine; it must NOT alter the golden
   semantics. Feed the dumped operands into the pristine-x86 ops; the FIRST op whose pristine-x86 result
   differs from the arm64 dump = the real divergence (the actual in-game bug, on real inputs).
4. **Fix** that op in the translation layer (mips2c / goalc arm64), goal_src 1-to-1. Re-examine whether
   fmin/fmax (kept) is involved or if it's a different op.
5. Deploy the fix; the OWNER play-tests (final gate).

## Validator (`phase-Gcollision-glitchcapture.sh`) PASS requires
1. `.autoport/reports/Gcollision-glitchcapture/report.txt` with `RESULT: REAL GLITCH COLLISION DIVERGENCE NAMED + FIXED`:
   a real owner-play glitch DUMP captured (the operands at the glitch, with the glitch signature that
   triggered it); the x86-oracle-on-the-dumped-operands diff naming the FIRST divergent op (arm64 value vs
   x86 value on those exact inputs); the fix; AFTER, that op on the dumped operands gives arm64 == x86.
2. goal_src 1-to-1; real translation-layer change; fix-summary
   `.autoport/reports/Gcollision-glitchcapture-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.
3. NOT done on the validator alone — the OWNER play-tests the fixed build (their eye = final gate).

## Note
First sub-goal = the instrumented capture build deployed + owner-play instructions written; then supervisor
coordinates the owner's real-session capture; then the diff + fix. The capture build must be deployed
before the owner plays.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1800, max_retries 5.
