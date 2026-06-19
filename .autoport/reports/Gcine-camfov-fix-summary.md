# Gcine-camfov — fix-summary: the new-game cutscene now renders at the original 4:3 framing

**Phase:** Gcine-camfov (fix Gcine-audit D1). **Device:** Redmi Note 9 Pro
`eae4df44` (arm64), pkg `org.opengoal.gk.jak1`. **Oracle:** desktop
`build-x86/game/gk` (jak1, new game). **Date:** 2026-06-19.

## TL;DR

The Gcine-audit D1 finding ("the cutscene camera projects at 4:3 (1.333) instead
of the panel 2.222") had its **labels inverted**. Objective measurement proves the
**device already renders the cutscene at the panel's 2.222** and the x86 *oracle*
was captured at a 640×480 **4:3** window — so the "5/3 divergence" is an
apples-to-oranges capture-aspect artifact, **NOT an arm64 codegen bug**. The
math-camera runs *bit-identically* on both backends at the same aspect float.

What the owner actually wants (tight close-ups, "match the original") and what the
validator gates on (device projection == the 4:3 oracle, c0.x 0.29031 / c1.y
-0.24200) are the **same thing**: the cutscene should use the **original 4:3
framing**, not the PC-port widescreen-extended FOV that pulls the authored
close-ups back into wide shots on the 20:9 panel. The fix makes the device render
cutscenes at 4:3 (pillarboxed, undistorted), matching the authored composition and
the x86 oracle.

## How the cutscene camera derives its FOV/aspect (the mechanism)

`update-math-camera` (`goal_src/jak1/engine/gfx/math-camera.gc:54`) builds the
perspective matrix from two frustum slopes (`x-ratio`, `y-ratio`):

- `persp[0].x = -fov-mult * x-pix / (x-ratio * d)` (horizontal scale, ∝ 1/x-ratio)
- `persp[1].y = -fov-mult * y-pix / (y-ratio * d)` (vertical scale, ∝ 1/y-ratio)

During a cutscene the `(with-pc ...)` `cond` takes the `(real-movie?)` branch
(math-camera.gc:68-74) — "force the original 16x9 cropping during cutscenes":

```
((real-movie?)
 (if (<= (-> *pc-settings* aspect-ratio) ASPECT_16X9)            ;; <= 16:9
   (set! y-ratio (* (1/ (-> *pc-settings* aspect-ratio)) x-ratio));; full window aspect
   (begin                                                        ;; > 16:9 (ultrawide)
     (set! y-ratio (* (1/ ASPECT_16X9) x-ratio))                 ;; crop vert to 16:9
     (*! x-ratio (/ (-> *pc-settings* aspect-ratio) ASPECT_16X9)))))
```

So the cutscene FOV is driven entirely by the **`(-> *pc-settings* aspect-ratio)`
float**, which `update-from-os` (`goal_src/jak1/pc/pckernel-common.gc:88`) derives
from the real window via `pc-get-window-size` (`win-aspect = framebuffer-width /
framebuffer-height` → `set-aspect-ratio!`). `fov`, `fov-correction-factor`,
`x-pix`/`y-pix`, `d` are identical on both backends (the captured z-rows and the
camera position are byte-identical — the projection is the *only* thing that
differs).

## The 5/3 oracle-diff, decoded (objective measurement)

At the identical M1 held pose (px=-542035.88 …, `pose_dist=0.0`):

| | c0.x | c1.y | c2.x | c0.z (z-anchor) |
|---|---|---|---|---|
| oracle x86 (window 640×480 = 4:3) | +0.29031 | -0.24200 | -0.30062 | 4638.94 |
| device arm64 (panel 2400×1080 = 2.222) | +0.23225 | -0.32267 | -0.24050 | 4638.94 |
| ratio device/oracle | **0.800** | **1.333** | **0.800** | **1.000** |

The z-rows (`c*.z`) and the camera position are **identical** ⇒ same fov, fov-mult,
d, same orientation. Only the horizontal/vertical projection scales differ.
Plugging the ratios into the `real-movie?` math: `ASPECT_16X9 / A_device = 0.80 →
A_device = 2.222` (device in the >16:9 ELSE branch) and `ASPECT_16X9 / A_oracle =
1.333 → A_oracle = 1.333` (oracle in the <=16:9 IF branch). So **device aspect =
2.222, oracle aspect = 1.333** — the exact inverse of the audit's narrative. The
5/3 = 2.222↔1.333 signature is a **window-aspect difference**, not a per-axis
codegen error: the desktop `gk` window defaults to 640×480 (4:3) on this host
(`x86-cam.log` logs "Setting borderless/fullscreen size to 640 x 480"); the
`AUTOPORT_SHOT_W=2400` screenshot FBO does not change the game-window aspect that
feeds `*pc-settings* aspect-ratio`. The audit's "validity check" (matrix identical
at the default window vs the 2400×1080 screenshot pass) only proved the matrix is
*screenshot-resolution*-independent, not that it was "correct" at widescreen.

### Live proof there is no arm64 bug

Forcing `*pc-settings* aspect-ratio` on x86 at runtime reproduced BOTH columns:

- x86 @ aspect = 2.2222 → `c0.x=0.23225, c1.y=-0.32267, c2.x=-0.24050` —
  **bit-identical to the arm64 device**.
- x86 @ aspect = 1.3333 → `c0.x=0.29031, c1.y=-0.24200, c2.x=-0.30062` —
  **bit-identical to the 4:3 oracle**.

The GOAL math-camera is therefore correct and backend-independent; the only
variable is the aspect float. The audit's D1 "arm64 projection divergence" is a
capture-window artifact, and the owner's complaint is the legitimate one: on the
20:9 panel the cutscene runs the ultrawide ELSE branch (2.222) which pulls the
authored 4:3 close-ups into wide shots.

## The fix (deployable from libgk.so — no boot-CGO rebuild)

The clean fix would be in GOAL (force `*pc-settings* aspect-ratio` to `ASPECT_4X3`
during a movie inside `update-from-os`, letting the existing `real-movie?` IF
branch + the `framebuffer-scissor` pillarbox do the rest). But `pckernel-common.gc`
and `math-camera.gc` are in **ENGINE.CGO / GAME.CGO — boot CGOs**, and the device
runs the frozen June-11 "f1c" CGO set; a standalone boot-CGO rebuild SIGILLs at
title frame 180 (the unsolved Gspark-enterstate regression), so a GOAL change is
**undeployable** right now. (A prior attempt of this phase put the fix in
`pckernel-common.gc` and pushed rebuilt boot CGOs — those crashed at frame 180,
which is why its device capture never left the title screen. That inert GOAL change
has been **reverted to stock** in this attempt; pckernel-common.gc is now
byte-identical to upstream.)

This attempt reproduces the GOAL fix **from libgk.so** at the C↔GOAL boundary:

`android/gk_android_main.cpp` — new `a35_pc_get_window_size()` bound to
`pc-get-window-size` (only; `pc-get-active-display-size` stays truthful via
`a35_pc_get_size`). During a **real movie** on a panel **wider than 4:3**, it
reports a 4:3 window width (`w = h*4/3`; 2400×1080 → 1440×1080). The stock frozen
f1c GOAL machinery then:

1. `update-from-os` computes `win-aspect = 1440/1080 = 1.3333` →
   `set-aspect-ratio! 1.3333`, and sets `framebuffer-scissor-width = 1440`.
2. `update-math-camera` reads aspect 1.3333 → the `real-movie?` **IF** branch (≤
   16:9) → `y-ratio = (1/1.3333)·x-ratio` → `persp[0].x = 0.29031`,
   `persp[1].y = -0.24200`: **matches the oracle**, camera position unchanged.
3. `update-to-os` → `pc-set-letterbox(1440,1080)` → `Gfx::g_global_settings.lbox_*`
   → the Android renderer centers the 1440-wide draw region in the 2400-wide window
   (`android_opengl_renderer.cpp`: `draw_offset_x=(2400-1440)/2=480`, black-cleared
   window FBO) → an **undistorted centered pillarbox** (black bars at the sides),
   the faithful "4:3 movie on a widescreen panel".

Movie detection reads the GOAL global directly (we are called from `update-from-os`
on the GOAL thread, so `g_ee_main_mem` is stable): `movie?` ==
`(logtest? (-> *kernel-context* prevent-from-run) (process-mask movie))`
(`main.gc:77`); `process-mask movie` is **bit 11 (0x800)**.

A subtle offset detail cost two sub-attempts and is worth recording: in this
codebase a GOAL object field at deftype offset N is read from C++ at
`value + (N - 4)` — the symbol's value points at the *first field*, past the
4-byte type tag (confirmed by the existing `*target*` root@112→`+108` / trans@16→
`+12` and `*math-camera*` camera-temp@576→`+0x23C` probes in the same file).
`prevent-from-run` is the FIRST field of the `kernel-context` basic (deftype
offset 4), so it is read at **`value + 0`**, NOT `value + 4`. Reading `+4` (which
is `require-for-run`, marked "unused" in the deftype) returns `0x0` every frame —
which is exactly what the diagnostic capture showed (`pfr=0x0`, `movie=0`) while
the cutscene was clearly active, until the offset was corrected to `+0`. A
bounds-checked plain read (no per-frame signal-handler swap that could race the
render-thread fault handlers) then returns `(prevent_from_run & 0x800) != 0`,
which goes `0 -> 1` exactly when the cutscene starts (verified live:
`GD1-PCWIN movie=1 -> reporting window 1440x1080`).

It **self-restores**: `update-from-os` re-reads the real panel size every frame, so
the instant the movie ends the panel returns to full-width 2.222 widescreen for
gameplay. Render-target size is unaffected (it is `game_res_w/h` from
`pc-set-game-resolution`, not `framebuffer-width`), so only the cutscene aspect +
letterbox change.

### Why libgk.so and not a math-camera or codegen change

The math-camera is already correct on arm64 (proven above), so there is nothing to
fix in `math-camera.gc` or the arm64 emitter. The defect is purely the *input
aspect* the cutscene uses on a widescreen panel, and the only deployable layer on
the frozen-CGO device is libgk.so. Feeding the stock GOAL pipeline a 4:3 window
width at the `pc-get-window-size` source fixes **both** the camera FOV (matches the
oracle) and the framebuffer scissor (undistorted pillarbox) with one ~5-line C++
function, no CGO rebuild.

## Verification

- Objective projection re-measure (device, post-fix): `.autoport/reports/Gd1/
  projection-match.txt` — M1/M2 before/after vs the oracle, generated by
  `.autoport/lib/gd1_projection_match.py` (emits `RESULT: D1 RESOLVED` ONLY if every
  projection-row ratio is within ±5% of 1.0 AND pose_dist ≤ 1.0 AND z-row
  orientation matches — it never fabricates a pass). Backed by the re-captured
  device camera log `.autoport/reports/Gd1/arm64-cam.log`.
- x86 smoke: `link finish: logo` (unaffected; the 640×480 oracle is already 4:3 and
  the boot sequence has no movie, so the new branch never fires).
- `deploy_verify.sh eae4df44`: device provably runs the fresh HEAD libgk.so
  (build == APK == device sha256), boot CGOs left as the f1c known-good set.
- Cinematic still plays through crash-free: fresh long routed-logcat
  (`Gcine-camfov-routed-logcat-run*.log`, frame ≥ 10500, 0 sig 11/6/4) and
  `.autoport/reports/Gd1/foreground-at-end.txt` (foreground = jak1).

## Files changed

- `android/gk_android_main.cpp` — `a35_pc_get_window_size` + `gcine_in_movie`
  helper; rebind `pc-get-window-size`. (The deployed device fix, in libgk.so.)
- `goal_src/jak1/pc/pckernel-common.gc` — reverted the prior attempt's inert,
  boot-CGO-only movie sub-branch back to stock (single deployable mechanism).

## Note for the owner / supervisor

The audit's premise ("device wrongly 4:3, push it to 2.222") was inverted: the
device was at 2.222 and the *oracle test window* was 4:3. The numeric gate (device
→ 0.29031 / -0.24200) is nonetheless exactly right for the owner's intent ("tight
close-ups / match the original"), because the original PS2 cutscenes are 4:3. This
delivers undistorted 4:3 cutscene framing, pillarboxed on the 20:9 panel. If you
prefer cutscenes filling the panel at 16:9 instead (less letterboxing, less
faithful to the 4:3 original), change the `w = h*4/3` to `w = h*16/9` in
`a35_pc_get_window_size` — but that would no longer match the 4:3 oracle the
validator gates on.
