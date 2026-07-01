# Phase Gcamera-smooth — the camera jitters/steps when panning, while everything else is fluid

## Why (owner 2026-06-30/07-01, flagged twice)
Everything else is perfectly fluid (Jak's movement, world, dynamic render scale), but the CAMERA feels
"not in sync" — a bit jittery/"jumps" when panning around Jak (right-stick camera), even when the fps
is fine. The owner first noticed this at the variable-fps phase ("la vue saute, ne suit pas le
framerate") and again now. It is a SEPARATE residual from game-speed (which is fixed) — a camera-
smoothness bug specifically.

## Prime lead (from the variable-fps fix, f4828f9f2)
The variable-fps fix's own report noted: the INTEGER time-ratio `k` (drawable.gc:978) can still flicker
1↔2 when the device fps swings across a vblank boundary, and that this "does NOT affect Jak's movement
(which rides the smooth fractional seconds-per-frame/time-adjust-ratio)". HYPOTHESIS: the CAMERA advance/
interpolation rides a quantity coupled to the flickery INTEGER time-ratio (or is updated at a cadence
tied to it), instead of the smooth fractional `time-adjust-ratio`/`seconds-per-frame` that Jak uses — so
the camera steps 1↔2 while Jak stays smooth. Investigate this FIRST. Other candidates: camera updated
only on logic ticks but rendered (at the higher/variable display rate) with NO interpolation → visible
stepping when panning; a 1-frame render-vs-camera latency; or the camera reading a quantized value.

## Mandate — state-anchored diagnosis, then fix in the translation/runtime layer
1. STATE-ANCHORED (owner's rule): dump the CAMERA transform (position, orientation/matrix, and the
   camera-target) per RENDER frame AND per logic frame on the device while panning, and compare to the
   pristine golden x86 (.autoport/gold) under the same anchored input. Find WHY the camera transform
   steps/jitters frame-to-frame on arm64/Android while Jak's transform is smooth — name the exact
   quantity/cadence (esp. check whether camera advance uses the integer time-ratio vs the fractional
   time-adjust-ratio / whether it's rendered without interpolation).
2. FIX in the arm64/Android runtime glue / mips2c / pc layer (NOT engine goal_src if avoidable; gold
   oracle stays clean). Make the camera advance/interpolation ride the SAME smooth fractional timing
   Jak uses (or add render-time camera interpolation if that is the correct PS2-faithful-at-variable-fps
   behavior) so panning is smooth. Do NOT reintroduce game-speed variation or the 30/60 lock.
3. If the jitter is inherent and needs an engine (goal_src) change, report that honestly with the exact
   mechanism rather than hacking.

## Verify (state-anchored + owner)
On device: the per-render-frame camera transform is SMOOTH when panning (no 1↔2 step / no jump beyond a
small threshold), matching the golden x86 pattern; quantify the before/after camera-delta jitter.
Everything else stays fluid; game speed still constant; no flicker. x86 builds + boots. Full CONSISTENT
build, deploy_verify PASS. The owner play-tests: panning around Jak is smooth (no camera jump).

## Report (`.autoport/reports/Gcamera-smooth/report.txt`) with `RESULT: CAMERA PAN SMOOTH`
the named cause (camera timing/interpolation quantity, device-vs-golden, with the per-frame camera-delta
numbers), the fix, before/after camera-jitter measurement, game-speed unaffected, x86 link finish: logo.
If it needs an engine change, RESULT: CAMERA JITTER ROOT NAMED + the mechanism (honest).

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched if avoidable; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.

## OWNER TEST TIP (2026-07-01) — pan in an OBSTACLE-FREE spot, not at spawn
The camera cannot do a full 360 around Jak AT the spawn point (Geyser) — obstacles block/collide the
camera and would CONFOUND the jitter measurement (camera collision != timing jitter). Before measuring
the pan-jitter, MOVE Jak to an open, obstacle-free area (walk/drive him out, or pick an open beat) so
the camera can orbit freely; measure the pan-smoothness there. A camera that stutters because it's
hitting geometry is NOT the timing bug — isolate the free-orbit case.
