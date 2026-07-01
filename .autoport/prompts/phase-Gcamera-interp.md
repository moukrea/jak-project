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
