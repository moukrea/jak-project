# Phase Gcamera-interp — the camera still steps/jumps; a real interpolation gap vs the PC/original build

## Why (owner 2026-07-01, camera jumps again)
Gcamera-smooth (the present-interval FrameLimiter busy-spin) HELPED but did NOT fully fix it — the camera
"recommence à sauter". The owner is explicit: there is a real INTERPOLATION issue "qu'on a pas sur PC,
le build original". So the arm64/Android build renders the camera in a way that steps, which the PC/
original build does not exhibit. This is separate from the FrameLimiter jitter (already improved) — it
is a per-frame camera-transform interpolation gap, most visible at ~30fps and under variable frame
timing (e.g. while dynamic render scale changes load).

## Mandate — find what the PC/original does that keeps the camera smooth, and replicate it
1. INVESTIGATE the ORIGINAL/PC OpenGOAL render path (compare our-x86 desktop / .autoport/gold behavior
   to the Android path): does the PC build render the camera/world with per-frame INTERPOLATION between
   logic-frame states, or does it simply render at a high enough / consistent rate that stepping isn't
   visible? Find the exact mechanism that makes the PC camera smooth. Check how the camera transform
   used FOR RENDERING is derived vs when the camera logic updates (per logic tick) — is there a
   fractional-time interpolation the Android port dropped or never had?
2. STATE-ANCHORED: dump the per-RENDER-frame camera transform on device vs the PC/original under the
   same anchored motion (pan in an OPEN area — the camera cannot 360 at spawn, obstacles confound it).
   Quantify the residual step/jump the owner sees (frame-to-frame camera-delta discontinuity) and show
   the PC/original does NOT have it.
3. FIX in the arm64/Android runtime/render layer: render the camera at the correct fractional time —
   i.e. interpolate the camera (and, if that's how the original stays smooth, the relevant transforms)
   between the last two logic-frame states based on the sub-frame time, so panning is smooth at any fps/
   variable frame timing, MATCHING the PC/original. Do NOT reintroduce game-speed variation, the 30/60
   lock, or break the FrameLimiter fix. If the correct fix is engine-level, name it honestly.
4. Must hold under DYNAMIC RENDER SCALE too (variable frame timing must not reintroduce the step).

## Verify (state-anchored + owner)
Device: per-render-frame camera-delta is smooth/continuous when panning in an open area (no step/jump),
matching the PC/original pattern; quantify before/after. Holds with dynamic render scale on. Game speed
still constant; FrameLimiter fix intact. x86 builds + boots. Full CONSISTENT build, deploy_verify PASS.
Owner play-tests: panning around Jak (open area) is smooth like the PC/original.

## Report (`.autoport/reports/Gcamera-interp/report.txt`) with `RESULT: CAMERA INTERPOLATED LIKE ORIGINAL`
what the PC/original does to stay smooth; the state-anchored device-vs-original camera-delta before->
after; the interpolation fix; holds under dynamic scale; speed unaffected; x86 link finish: logo.
If engine-level, RESULT: CAMERA INTERP ROOT NAMED + the mechanism (honest).

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched if avoidable; .autoport/gold READ-ONLY.
## Max: max_turns 2200, max_retries 5. device: true, owner_verify: true.

## OWNER REJECT (2026-07-01, attempt 1) — WRONG LEVER: it's CAMERA-SPECIFIC, not the global timestep
Attempt 1 (making motion proportional to fractional real-frame time / the global time-ratio) FAILED:
the camera is still choppy — SAME or WORSE — and the FRAMERATE regressed (possibly aggravated by device
thermal throttling, but treat the change as a likely fps regressor). DECISIVE new signal from the owner:
"Action fluide à l'écran, caméra choppy as heck." The world/objects/Jak move SMOOTHLY; ONLY the CAMERA
juders. Therefore the problem is NOT a global timestep / integer-time-ratio issue (that would judder
EVERYTHING together) — it is CAMERA-SPECIFIC.

REDO:
1. REVERT attempt-1's global fractional-timestep change. A/B MEASURE fps with vs without it to confirm
   whether it regressed fps (if yes, it stays reverted); the world already moves smoothly, so a global
   change is the wrong tool.
2. ISOLATE THE CAMERA. State-anchored, per-render-frame, compare ONLY the camera transform (position and
   especially ROTATION / the right-stick pan yaw-pitch) device vs the PC/original during a pan in an OPEN
   area, WHILE confirming a nearby world object's on-screen motion is smooth in the same frames. Find why
   the CAMERA specifically steps while object motion does not: is the camera's view matrix / pan angle
   updated or sampled at a different cadence, quantized, or not interpolated for render the way object
   motion is? Check the right-stick camera-control input sampling and the camera's own smoothing/update
   path (not the global clock).
3. FIX only the camera path so panning is as smooth as the surrounding object motion, WITHOUT a global
   timestep change and WITHOUT an fps regression. Name the camera-specific mechanism honestly.

## OWNER REJECT #2 (2026-07-01, attempt 2) — REVERT + WRONG CLASS: it's NOT timing/interpolation
Attempt 2 (camera-only render-time sub-frame interpolation in cam-update.gc) FAILED AND REGRESSED:
 - The gameplay camera is STILL jittery — owner: "toujours jittery MÊME QUAND C'EST PARFAITEMENT FLUIDE"
   (i.e. at a STABLE framerate). Jitter at a stable fps means it is NOT a frame-pacing / sub-frame-
   interpolation / timestep problem — the whole interpolation angle (attempts 1 AND 2) is the WRONG CLASS.
 - REGRESSION: the TITLE-SCREEN LOGO, which was PERFECT, is now "super jittery" — the sub-frame camera
   interpolation injects instability into the view matrix. This must NOT ship.
MANDATE:
1. REVERT the attempt-2 camera-interp change (cam-update.gc / camera-interp-retime) ENTIRELY. Confirm on
   device the TITLE-SCREEN LOGO is PERFECTLY SMOOTH again (no jitter) — this is a hard gate.
2. STOP the interpolation/timing angle. The camera juders at a STABLE fps while world objects are smooth
   → suspect an arm64-SPECIFIC per-render-frame NUMERICAL noise/oscillation in the CAMERA MATRIX/pose
   (float precision divergence from x86, a mips2c camera function, matrix build/orthonormalization,
   quaternion→matrix, or a camera-control smoothing that oscillates on arm64). 
3. STATE-ANCHORED: dump the camera transform/matrix PER RENDER FRAME on device vs the golden x86 with the
   camera CONTROLLED (held still, then a slow steady pan) in an OPEN area, and diff the actual matrix
   VALUES frame-to-frame. Find the arm64-specific per-frame delta/oscillation that x86 does not have
   (the smoking gun). Object motion is smooth in the same frames — so the divergence is camera-only.
4. Fix ONLY that numerical/camera-matrix divergence in the arm64 translation layer (mips2c/codegen/
   runtime), 1-to-1 vs original. No interpolation, no timestep change. The title logo must stay perfect
   and the gameplay camera must match golden per-frame. If you cannot find a per-frame numerical
   divergence, report honestly what you measured (maybe it IS timing after all — but the stable-fps +
   title-regression evidence says otherwise).

## OWNER TEST-METHOD CORRECTION (2026-07-01) — the jitter ONLY shows while ROTATING the camera
Critical: the camera jitter does NOT appear on a static/held camera — it happens ONLY when you ROTATE
the camera AROUND Jak (right-stick pan). A static capture illustrates NOTHING and will falsely read as
"no divergence". The per-render-frame camera-matrix dump MUST be captured WHILE the camera is ACTIVELY
PANNING around Jak:
 - Drive a steady right-stick camera rotation via the input harness (cpad_inject / the right-stick pad
   injection built earlier) — a continuous yaw sweep around Jak in an OPEN area.
 - Capture the camera matrix PER RENDER FRAME during that active pan on BOTH the device and the golden
   x86, driven by the SAME injected right-stick input, and diff the values frame-to-frame.
 - The jitter is IN the rotating case — so the smoking gun (arm64 per-frame camera-matrix oscillation)
   only appears while panning. Measure there, not at rest.
