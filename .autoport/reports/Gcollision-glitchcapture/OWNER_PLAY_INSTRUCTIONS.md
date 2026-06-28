# Owner play-test — capture the REAL collision glitch (no warp, no replay)

The instrumented capture build is **already installed and verified** on the device
(`eae4df44`, `org.opengoal.gk.jak1`). The game logic is **byte-identical** to the build you
have been play-testing — the only change is an extra C++ diagnostic in `libgk` that **watches
the collision math every frame and automatically writes a dump the instant a collision glitch
happens**. No record button, no warp, no special input. Touch controls or a gamepad — both work,
the capture doesn't care how you move Jak.

## What you do

1. **Just launch the game and play your real session** the way you normally do.
2. **Go to the spots where the collision glitches happen** — the places where Jak gets
   *projected/ejected*, *clips through* a wall/floor, gets stuck on an invisible wall, or drops
   *under the map*. Steps, ledges, wall corners, the blue-eco jumps, the under-map jumps — your
   usual problem areas. Trigger the glitch a few times if you can; each occurrence appends a dump.
3. That's it. When a glitch fires, the build silently records the collision math of that frame
   plus the 8 frames leading up to it. Play as long as you like; it keeps appending (up to 400
   captures, so there is no rush).

## How we know it worked

Each capture also prints a line to the device log, e.g.:

```
W/GK_STDOUT: [CC] GLITCH #1 frame=51234 reason=TRANSV_SPIKE dpos=2.1m vmag=78.3m/s snlen=1.00 ...
```

`reason` is the glitch signature that fired:
- `TRANSV_SPIKE` — Jak's velocity jumped (eject/projection)
- `TRANS_JUMP` — Jak teleported in one frame (clip / under-map)
- `NONFINITE` — a NaN/Inf reached the collision math
- `DEGEN_NORMAL` — a collision surface normal came out non-unit (a divergent normalize/length)

The supervisor watches the log live and confirms captures as you play.

## After the session — the supervisor pulls the dump

```
bash .autoport/reports/Gcollision-glitchcapture/cc_pull_dump.sh
```

This copies `files/collision_glitch.txt` off the device and prints how many glitches were
captured and a breakdown by signature. Then the x86 oracle runs on those exact operands:

```
bash .autoport/reports/Gcollision-glitchcapture/cc_oracle_run.sh
```

which names the first collision-reaction op whose x86 result differs from the arm64 dump on the
real operands (or, if the reaction ops are consistent, localizes the divergence to detection and
the next capture stage). The fix goes in the arm64 translation layer (goal_src stays 1-to-1) and
**you play-test the fixed build — your eye is the final gate.**

## Optional threshold tuning (only if a known glitch is NOT being captured)

Defaults catch the obvious glitches. If a milder glitch slips through, make the detector more
sensitive without a rebuild (then relaunch the game):

```
# lower the velocity-spike threshold to 25 m/s (default 50)
adb -s eae4df44 shell setprop debug.opengoal.cc_vel 25
# lower the one-frame teleport threshold to 8 m (default 20)
adb -s eae4df44 shell setprop debug.opengoal.cc_jump 8
# loosen the non-unit-normal tolerance (default 0.03)
adb -s eae4df44 shell setprop debug.opengoal.cc_normeps 0.01
# (disable capture entirely if ever needed: setprop debug.opengoal.cc_disable 1)
```

The dump file persists across launches (append mode), so several short sessions are fine. To
start a clean dump, delete it first:
`adb -s eae4df44 shell run-as org.opengoal.gk.jak1 rm -f files/collision_glitch.txt`
