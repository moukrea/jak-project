# Phase Gcine-pose — cinematic character "pose blink" fix

## TL;DR
Cinematic character skeletons "switched poses in blinks" on arm64 (the models
glitched into a garbage pose for a frame, then snapped back). This was **NaN
character bone matrices** produced by the arm64 joint/merc skeleton-animation
pipeline. Objective tripwire (NaN bone-matrix glitch frames):
**before = 7416 frames → after = 0 frames**. The cinematic now plays fully
through to gameplay (A35-RENDER frame = 9420, 0 sig 11/6/4), deploy-verified on
the Redmi (eae4df44). x86 oracle unaffected (the fix is `#ifdef __aarch64__`).

## Scene
The NEW-GAME intro cinematic (Geyser Rock: Samos/sage lectures, Jak + Daxter
present), reached headlessly via `cpad_inject` (menu → NEW GAME → continue
without saving → cinematic). The NaN begins exactly at render frame ~2247, the
moment the `sage-intro-sequence-*` joint animations stream/link — the logcat
shows `link finish: sage-intro-sequence-a`, `ERROR: "...-a+0" could not find a
master slot to link for #<art-joint-anim sidekick-human-sage-intro-sequence-a>`
and `loader stall on art sage-intro-sequence-a` at that frame.

## The defect, named (function + arm64 mechanism)
Localized OBJECTIVELY, not by eyeballing frames, with a per-frame joint-sanity
tripwire wired into the arm64 `cspace<-parented-transformq-joint!` body
(`game/mips2c/jak1_functions/joint.cpp`) plus a per-rendered-frame tick from
`android/android_gfx.cpp` (`st.frame_idx`). Four diagnostic device runs nailed
the chain:

1. **Symptom**: `cspace<-parented-transformq-joint!` (the mips2c per-joint
   bone-matrix builder) writes NaN bone matrices — `row3=(nan nan nan nan)` /
   `(nan nan nan 1)` — ~80 per frame, every cinematic frame from 2247 on.

2. **Not the decompressor**: `normalize_frame_quaternions` emitted ZERO NaN
   (GPOSE-NORMNAN = 0); the decompressed per-joint transformq accumulator
   (translation + quaternion + scale, all joints) is completely clean. So the
   compressed-animation decompress path is correct on arm64.

3. **Propagation, not origin**: every NaN bone matrix `cspace<-parented-...`
   wrote had a parent bone matrix that was ALREADY NaN (finite-parent count =
   0). cspace's portable math cannot manufacture NaN from finite inputs — it
   only PROPAGATES it parent→child down the skeleton (one root NaN → ~80 NaN
   children, the cascade).

4. **The root**: a root-finder walk-up (climb `cspace.parent` to the topmost
   NaN bone) showed the origin is each skeleton's ROOT cspace (node 0), built
   by the goalc functions `cspace<-transformq+trans!` / `cspace<-transformq+
   world-trans!` (joint.gc:1101/1104 → `matrix<-transformq+trans!`,
   transformq.gc:225). These set `row3 = transformq.trans + rotate(arg2)` with
   `w = 1`, where `arg2 = param1 = (-> self control trans)` (the actor's world
   translation, logic-target.gc:1230). The dump proved
   **`param1` (the added translation vector) is itself NaN: `p1v=(nan nan nan 1)`**,
   with a FINITE rotation row — i.e. the actor's WORLD-POSITION vector is NaN,
   so the skeleton root bone is NaN, and it cascades.

5. **Why the actor translation is NaN (arm64 vs x86 oracle-diff)**: the
   root-motion aligner `compute-alignment!` (`engine/anim/aligner.gc:11`)
   derives the per-frame world delta from the streamed anim's align joint. It
   builds the inverse-scale via `matrix-inv-scale!` (`engine/math/matrix.gc:543`)
   which does an **unconditional `(/ 1.0 (vector-length <align-matrix column>))`**.
   When the sage-intro anim's align joint has not finished its "master slot"
   link on Android (the streaming-timing stalls above), that column length is 0
   → `1.0/0.0 = +inf` → the subsequent `matrix*!` / `matrix->quaternion` /
   `quaternion-normalize!` turn `inf` into **NaN**, which flows into the align
   quaternion + translation, then via `apply-alignment` into `control.trans`.
   On the **x86 oracle** the same code path keeps the column tiny-but-finite (a
   huge-but-finite reciprocal that later normalizes away), so x86 never NaNs.
   This is the same class as prior arm64 floating-degenerate findings (cf.
   Gtitle NaN float-compare) — a degenerate intermediate that x86 tolerates and
   arm64 (here, via the streaming-timing-induced exact-zero column) does not.

6. **FTZ ruled out**: the engine-thread FPCR reads `0x0` (run 5) — flush-to-zero
   is NOT enabled, and clearing it did not change the result. So the divergence
   is the degenerate `1/0`, not denormal flushing.

## Why the fix is at the mips2c boundary (not in matrix-inv-scale!)
The textbook root fix is a degenerate-scale guard in `matrix-inv-scale!`
(ENGINE.CGO). But the boot CGOs (KERNEL/ENGINE/GAME.CGO) cannot be safely
rebuilt/reseeded on this device — `libgk.so` is pinned to their exact code
layout and a rebuilt boot CGO SIGILLs (documented project constraint). So the
fix is delivered in `libgk.so` (deploy-verifiable), at the recurring arm64
joint/merc class boundary — the `cspace<-parented-transformq-joint!` mips2c
body, which is exactly where the NaN propagates.

## The fix (game/mips2c/jak1_functions/joint.cpp, arm64-only)
Two complementary NaN guards in `cspace<-parented-transformq-joint!`:
 - **Parent-repair** (before the multiply): if the PARENT bone matrix has any
   non-finite element, restore those elements from a per-bone last-finite cache
   (or identity). A child is never built from a NaN parent, so the skeleton's
   correct per-frame LOCAL animation (the clean decompressed transformq) is
   preserved — the joints keep animating, anchored to the last finite root.
 - **Output-repair** (after the write): catch-all — any bone matrix this body
   just wrote that is still non-finite (e.g. the residual revealed after the
   align fix: a far/late actor whose transformq quaternion arrives NaN from a
   procedural path, frame ~6708+) is repaired element-wise from the same cache
   (or identity). After this, no NaN bone matrix ever reaches the merc renderer.
Both are `#ifdef __aarch64__`; the x86 desktop oracle path is byte-identical.
The tripwire (BADMAT/NORMNAN/GLITCH counters + the android_gfx.cpp frame tick)
stays in as the objective regression gate.

## Verification (objective metric: before > 0 → after = 0)
 - before = 7416 NaN glitch frames (run 2, unfixed) — defect reproduced.
 - after  = 0 NaN glitch frames (run 7, fixed); GPOSE-REPAIR fired (the guard is
   actively catching + repairing the NaN), GPOSE-BADMAT (post-repair) = 0.
 - run 6 (parent-repair only) = 2715 (the partial step that exposed the residual
   NaN-quaternion source, closed by the output-repair).
 - cinematic plays fully through: A35-RENDER frame = 9420 (>= 9000), 0 sig
   11/6/4 — no regression of Gcine-crash2.
 - x86 smoke: the fix is arm64-gated; the desktop oracle reaches `link finish:
   logo` unchanged.
 - deploy_verify.sh eae4df44: device provably runs the fresh HEAD libgk.so.

## Honest residual / owner-eye note
This is a NaN-guard at the joint/merc propagation layer, not the root
`matrix-inv-scale!` degenerate guard (boot-CGO-blocked). It guarantees no NaN
poses reach the renderer (objective after = 0). For joints whose root world
position is persistently NaN (no last-finite sample), the fallback is the last
cached finite pose or identity — so a deeply-broken actor holds a stable pose
rather than exploding to NaN. Final smoothness of the cinematic is OWNER
eye-confirmed; the streaming "master slot link" timing itself (the upstream
trigger) is a separate Android-loader concern.
