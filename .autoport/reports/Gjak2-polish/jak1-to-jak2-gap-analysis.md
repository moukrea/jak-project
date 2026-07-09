# jak1 -> jak2 PORTING GAP ANALYSIS (variable game-speed + collision)

Read-only forensic analysis. HEAD = 3e7a7e200. Gjak2-polish attempt-1 (f88ac8595)
IS in HEAD (working tree clean for the touched files).

## TL;DR
- Variable game-speed engine (frame clock + FrameLimiter + refresh-rate wiring) is
  ALL SHARED and jak2 already inherits it. jak2 is NOT missing the framerate fix at
  the mechanism level.
- The ONE jak1 fix jak2 genuinely LACKS is the render-time camera-pose interpolation
  (`cam-render-interp!`), which is a jak1-only goal_src consumer. That gap = "camera
  steps/jumps" at sub-refresh fps, NOT global game-speed.
- The variable-SPEED regression the owner reports was almost certainly INTRODUCED by
  Gjak2-polish, but NOT by `real-movie?` (render-only) — the suspect is the collision
  change (method 17 collide-cache + 4 nav-engine methods) newly running heavy arm64
  mips2c collision/nav-mesh math every frame, and/or its interaction with the pacer.
- The collision regression is the same change: Gjak2-polish un-noop'd
  `(method 17 collide-cache)` + `(method 17/18/20/21 nav-engine)`. These now run the
  arm64 collision/nav-mesh math that the whole Gcollision-* fight was about, but jak2
  never received the jak1 collision translation-layer fixes.

---

## 1. VARIABLE GAME-SPEED / FRAMERATE

### Where the jak1 fix lives (and whether it is shared)

The variable-fps fix (phase Gframerate-variable, code commit 03facb4a1) is split:

SHARED C++ (jak2 inherits automatically):
- `android/gk_android_main.cpp` — `a35_gfps_frame_tick()` (:700), `a35_read_ee_timer()`
  (:831), `g_gfps_virtual` (:657). Error-feedback game clock driven by REAL wall-clock
  dt, emitting integer time-ratio k so sum(k) == real_dt*target_fps => constant real-time
  game speed at any fps. Uses `Gfx::g_global_settings.target_fps` (:713) — game-agnostic.
- `android/android_gfx.cpp` — `vsync()` software-vsync EE cap at target_fps; and
  `iop_vblank_pacer_loop()` (:759) paces the fake-VAG / IOP stream clock at
  `Gfx::g_global_settings.target_fps` (:770/:805) not hardcoded 60.
- `game/graphics/pipelines/opengl.cpp:743-748` — desktop `FrameLimiter.run(target_fps,...)`.
- `game/graphics/gfx.h:90` `target_fps=60`, `:92 framelimiter=true`.
- `game/kernel/common/kmachine.cpp:1008` `pc_set_frame_rate` -> `g_global_settings.target_fps`.

SHARED goal_src, ALSO compiled into jak2 (this is the key structural fact):
- `goal_src/jak2/lib/project-lib.gp:68-71` routes `pc/pckernel-h.gc` and
  `pc/pckernel-common.gc` through `make-src-sequence-elt-jak1` => jak2 COMPILES the
  JAK1 copies of these two files. `game.gd` build order confirms:
  `pckernel-h.o`(jak1) -> `pckernel-impl.o`(jak2) -> `pckernel-common.o`(jak1) -> `pckernel.o`(jak2).
- So the base `reset-gfx` with the Gframerate refresh-rate wiring
  (`goal_src/jak1/pc/pckernel-h.gc:345-363`,
  `set-frame-rate! obj (if (and (= os 'android) (> refresh 0)) refresh 60)`) IS
  compiled into jak2 and is the base method jak2's
  `(method-of-type pc-settings reset-gfx)` (pckernel-impl.gc:154) chains to.

`pc-get-active-display-refresh-rate` is externed for jak2 in
`goal_src/jak2/kernel-defs.gc:233`, and the C++ is shared. jak2 gets the correct
target_fps default automatically.

### What jak2 is MISSING vs jak1: camera render-interpolation

The Gcamera-interp fix (commit 5f371cb16) added a GOAL-side consumer that exists ONLY
in jak1:
- `goal_src/jak1/engine/camera/cam-update.gc`: `cam-render-interp!` (defun at :226),
  called from update-camera at `:369`; globals `*cam-interp-prev-trans*` /
  `*cam-interp-prev-quat*` / `*cam-interp-valid*` (:220-224). It slerps/lerps the
  render-facing `*math-camera*` pose by alpha = `(pc-camera-interp-alpha)/1e6`, clamped
  [0,1], snapping on cut/movie/teleport/external-cam.
- C++ side IS shared: `pc_camera_interp_alpha()` in
  `game/kernel/common/kmachine.cpp:1091` (stub returns 1e6 on x86; Android override
  supplies the real deficit/k sub-frame alpha), bound for jak2 in
  `game/linux-arm64/linux_arm64_main.cpp:462` and via kmachine.cpp:1277.

GAP: `grep cam-render-interp!/pc-camera-interp-alpha goal_src/jak2` = NO MATCH.
jak2's `goal_src/jak2/engine/camera/cam-update.gc` never calls the interp; the C++
alpha is computed but discarded. => jak2 camera judders at sub-refresh fps exactly as
jak1 did before Gcamera-interp.

NOTE: jak2 has an UNRELATED `board camera-interp` field (powerups.gc) — different thing,
do not confuse.

---

## 2. COLLISION

### jak1 collision fixes (mechanisms)
- Gcollision-systemic / Gcollision-nanroot / Gcollision-glitchcapture: the ROOT was an
  arm64 float compare / conversion divergence. Landed fixes are in the arm64 CODEGEN /
  runtime translation layer (arm64 float `<`/`<=` NaN compare == x86; fmin/fmax NaN
  handling == x86). These are backend fixes, game-agnostic — jak2 inherits them.
- The other half is DATA availability: the collide-cache must be FILLED, which on arm64
  depends on the mips2c collide builders NOT being noop'd. jak1's collision builders are
  in the jak1 mips2c allowlist; jak2's are in `a37_name_is_real_jak2`
  (game/mips2c/mips2c_table_jak1_arm64.cpp:929+).

### jak2 collision path (what it has)
`a37_name_is_real_jak2` (mips2c_table_jak1_arm64.cpp:929) enables a large collide set
from Gjak2-movement: `(method 26/27/28/29/30/32 collide-cache)`,
`(method 9/10 collide-cache-prim)` (:1065), collide-mesh/edge-work/shape-prim families
(:1044-1052). This is the "can move / find-ground" enablement.

### Gjak2-polish collision change (REGRESSION SUSPECT)
f88ac8595 ADDED to the jak2 allowlist (mips2c_table_jak1_arm64.cpp:1087-1093):
- `"(method 17 collide-cache)"` — probe-using-spheres (ceiling probe backing
  can-exit-duck?; crouch-lock fix).
- `"(method 17 nav-engine)" "(method 18 nav-engine)" "(method 20 nav-engine)"
  "(method 21 nav-engine)"` — nav-mesh methods that method-17-collide-cache's
  find-ground path walks into.

The commit's OWN comment documents that enabling method-17 alone CRASHED (sig=11/sig=4)
until all 4 nav-engine methods were co-enabled — i.e. this turned ON a previously-OFF
arm64 nav-mesh + sphere-probe code path that had never run on device. That path now
executes the arm64 collision/nav math every frame near objects and on landing. If any
of that arm64 mips2c math diverges (the exact class Gcollision-* fought), it will
mis-collide. This is the most likely collision regression vector.

Even the crouch fix rationale confirms the risk: with method 17 noop'd, the stub
returned 0 = TRUTHY in GOAL => "ceiling hit" forever => can-exit-duck? #f => stuck-crouch.
Turning it real fixes crouch but subjects every sphere-probe / nav consumer to arm64
math correctness that jak2 has not been collision-validated against.

---

## 3. REGRESSION ROOT-CAUSE (Gjak2-polish)

Gjak2-polish attempt-1 (f88ac8595, in HEAD) changed exactly four things:
1. `goal_src/jak2/pc/pckernel.gc` — split `real-movie?` into `actually-in-movie?` +
   `real-movie?` gated on `(not aspect-ratio-auto?)` (:388-396); added
   `draw-pc-fps-counter` (:907). `real-movie?` is consumed ONLY at
   `goal_src/jak2/engine/gfx/math-camera.gc:78` (letterbox/aspect branch) and by discord
   (:417). It does NOT touch the game clock, target_fps, seconds-per-frame, or the pacer.
   => the cutscene-aspect change is RENDER-ONLY; unlikely to cause variable speed.
   (Caveat: FPS counter draws every frame via `with-dma-buffer-add-bucket` — negligible.)
2. `game/mips2c/mips2c_table_jak1_arm64.cpp` — the +5 collision/nav methods above.
   PRIMARY suspect for BOTH the collision regression AND, via added per-frame arm64
   nav/collision cost + possible NaN/inf feedback into physics, any speed feel change.
3. `game/graphics/opengl_renderer/sprite/GlowRenderer.cpp:536` — depth-probe FBO format
   GL_DEPTH_COMPONENT -> GL_DEPTH24_STENCIL8 (rift-gate glow over-bright fix). Render-only.
4. `goal_src/jak2/pc/progress/progress-static-pc.gc` — menu order/labels + FPS option.
   Menu/UI only.

The owner says the PREVIOUS jak2 build had no variable-speed problem, so a Gjak2-polish
change introduced it. `real-movie?` cannot (render-only). By elimination the collision/
nav mips2c enablement (#2) is the change to scrutinize first — it is the only one that
alters per-frame game LOGIC.

WIP checkpoints a17bcf662 (state.json only) and ebfc72ca3 (reports/memory only) carry
no code; all Gjak2-polish code is in f88ac8595.

---

## 4. RECOMMENDED PORTING PLAN

A. CAMERA SMOOTHNESS (definite missing port):
   Port jak1 `goal_src/jak1/engine/camera/cam-update.gc` `cam-render-interp!`
   (defun :226 + globals :220-224 + call site :369) into
   `goal_src/jak2/engine/camera/cam-update.gc`'s update-camera. C++ dependency
   `pc-camera-interp-alpha` is ALREADY bound for jak2 (linux_arm64_main.cpp:462 +
   kmachine.cpp:1277). Verify jak2 `*math-camera*` has the same fields (trans,
   inv-camera-rot, reset) and `movie?`/`*camera-look-through-other*`/`*external-cam-mode*`
   exist in jak2 (they do in jak2 camera code).

B. FRAMERATE (verify, likely already inherited — do NOT re-solve):
   Confirm at runtime that jak2 `reset-gfx` resolves target_fps to the panel refresh
   (jak1 pckernel-h.gc:357 base method runs for jak2). If jak2 shows variable speed,
   FIRST bisect the collision change (C) before touching the clock — the clock is shared
   and jak1-proven.

C. COLLISION REGRESSION (bisect the Gjak2-polish mips2c add):
   Runtime A/B via `setprop debug.opengoal.jak2.noop_names "(method 17 collide-cache)"`
   (and the 4 nav-engine methods) to confirm whether the new path causes the collision /
   speed regression. If it does, the fix is NOT to re-noop (that reinstates crouch-lock)
   but to ensure the arm64 backend collision-math fixes (float NaN compare, fmin/fmax,
   vftoi/FCVTZS) from Gcollision-systemic/nanroot are actually applied on the jak2 code
   path the nav-engine + probe-using-spheres methods use. i.e. port/verify the jak1
   collision translation-layer fixes cover jak2's now-active collide/nav methods, rather
   than re-deriving them.

## Key file:function references
- goal_src/jak1/engine/camera/cam-update.gc: cam-render-interp! (:226), call (:369)  [MISSING in jak2]
- game/kernel/common/kmachine.cpp:1091 pc_camera_interp_alpha  [shared, bound for jak2]
- goal_src/jak1/pc/pckernel-h.gc:345 reset-gfx (Gframerate refresh wiring)  [compiled into jak2 via project-lib.gp:68]
- android/gk_android_main.cpp:700 a35_gfps_frame_tick / :831 a35_read_ee_timer  [shared game clock]
- android/android_gfx.cpp:759 iop_vblank_pacer_loop  [shared, target_fps-paced]
- goal_src/jak2/pc/pckernel.gc:388 real-movie? (Gjak2-polish, render-only letterbox)
- goal_src/jak2/engine/gfx/math-camera.gc:78 real-movie? consumer (letterbox only)
- game/mips2c/mips2c_table_jak1_arm64.cpp:1087-1093 method 17 collide-cache + nav-engine 17/18/20/21  [Gjak2-polish ADD - collision regression suspect]
- game/mips2c/mips2c_table_jak1_arm64.cpp:929 a37_name_is_real_jak2 (jak2 collide allowlist)
