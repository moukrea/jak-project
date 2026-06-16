# OWNER-PINPOINTED CRASH LOCATION (2026-06-16) — read this

The owner watched the new-game intro cinematic on the device and pinpointed EXACTLY where it crashes (it has crashed here persistently "for a while"):

- A big **pinkish light halo** scene with **two villains in front of a portal** (this is the **Gol & Maia at the precursor silo/portal** intro scene).
- The **portal keeps opening and closing IN A LOOP** — this is itself a GLITCH (an animation/state machine stuck looping instead of progressing; may be related to the crash).
- The cinematic then **cuts to a closer shot of ONE villain** (a camera-plan transition to a Gol or Maia close-up).
- **On that cut to the villain close-up, it CRASHES** (app dies → Android home).

So the crashing scene = the Gol/Maia portal intro → the camera cut to the villain close-up. Map the captured fault/backtrace to THIS scene's code: the scene-player / camera-channel transition for that cut, the merc/joint animation of the villain model at the close-up, and any mips2c/GOAL-ptr path it newly exercises. The looping portal suggests a state/anim loop just before the fatal cut — check whether the loop and the crash share a cause. Find the GOAL function/process for that specific cut + close-up and correlate with the fault address.
