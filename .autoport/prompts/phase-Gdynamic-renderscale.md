# Phase Gdynamic-renderscale — adaptive render scale to hold a target framerate

## Why (owner 2026-06-30, PRIORITY — before the launcher)
The static RENDER SCALE % (Grender-split shipped) trades sharpness for fps manually. The owner wants
an AUTOMATIC mode: keep the framerate at/above a chosen target by dynamically lowering the 3D render
scale (within an allowed range) when a zone gets heavy, and raising it back (toward 100%) when there's
headroom. UI/HUD stay native (the Grender-split layer is unchanged). Must be SMART — no thrashing.

## Menu changes (pc/ menu + pc-settings; both builds)
1. New toggle **"Dynamic Render Scale"** ON/OFF (default OFF — keeps current manual behavior).
2. When ON, the existing "RENDER SCALE" entry becomes **"Minimum Render Scale"** = the floor the
   auto-scaler won't go below (default 40%). When OFF, it stays the manual fixed "RENDER SCALE".
3. New entry **"Minimum target framerate"**: 25/30/35/40/45/50/55/60 (default e.g. 30).
4. Persist all three (commit-to-file). Range the auto-scaler may use = [Minimum Render Scale, 100%].

## The adaptive algorithm (renderer/runtime; engine goal_src untouched → gold oracle clean)
Drive the existing render-scale lever (game_res FBO; the Grender-split split keeps UI native) from a
controller that reads the real measured fps (the `measured_fps` EMA already added for the FPS counter).
Goal: hold fps >= target by adjusting the 3D scale inside [min,100].
INTELLIGENCE (anti-thrash — mandatory, the owner stressed this):
 - Act on a SMOOTHED fps (EMA over ~0.5-1s), not single frames.
 - DEAD-BAND around the target (e.g. don't change while target-ε <= fps <= target+headroom).
 - Adjust in SMALL steps (e.g. ±5-10% scale) with a COOLDOWN between changes (e.g. >=0.5-1s), so it
   eases toward equilibrium instead of oscillating.
 - Lower scale quickly-ish when persistently below target; raise SLOWLY/conservatively when there's
   sustained headroom (asymmetric, to avoid hunting). Clamp to [min,100]. Avoid limit-cycle hunting
   at the boundary. Skip adjustment during loads/cutscene transitions if they cause false dips.
 - When OFF: scale = the manual RENDER SCALE %, controller idle (zero overhead).

## Verify (both builds, actual screen — state/behaviour, not eyes only)
On device eae4df44: with Dynamic ON + a target (e.g. 45): in a light scene fps sits near 100% scale;
entering a heavy zone that would drop below target, the scale auto-LOWERS (logged) until fps recovers
to ~target; returning to a light zone, scale eases back UP toward 100%. Demonstrate fps CONVERGES to
~target and the scale changes are SMOOTH (bounded rate, no rapid oscillation — quantify the
adjustment cadence). Respect the floor (never below Minimum Render Scale). OFF = unchanged manual
behavior. x86 builds + boots. Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gdynamic-renderscale/report.txt`) with `RESULT: DYNAMIC RENDER SCALE HOLDS TARGET FPS`
the three menu settings; a heavy-vs-light trace showing scale auto-adjusting + fps converging to
target; the anti-thrash measures + an adjustment-cadence number proving no oscillation; floor
respected; OFF=manual; x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; pc/ only goal_src; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
