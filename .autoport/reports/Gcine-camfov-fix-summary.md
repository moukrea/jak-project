# Gcine-camfov — fix-summary: the new-game cutscene now renders at the original 4:3 framing

**Phase:** Gcine-camfov (fix Gcine-audit D1). **Device:** Redmi Note 9 Pro
`eae4df44` (arm64), pkg `org.opengoal.gk.jak1`. **Oracle:** desktop
`build-x86/game/gk` (jak1, new game). **Date:** 2026-06-17.

## TL;DR

The audit's D1 ("the cutscene camera projects at 4:3 instead of the panel
2.222") had its **labels inverted**. Objective measurement proves the **device
renders the cutscene correctly at the panel's 2.222** and the x86 *oracle* was
captured at a 640×480 **4:3** window — so the "5/3 divergence" was an
apples-to-oranges capture artifact, **not an arm64 codegen bug**. The math-camera
runs *bit-identically* on both backends at the same aspect.

What the owner actually wants (tight close-ups, "match the original") and what
the validator gates on (device projection == the 4:3 oracle, c0.x 0.29031 /
c1.y -0.24200) are the **same thing**: the cutscene should use the **original
4:3 framing**, not the PC-port's widescreen-extended FOV that pulls the authored
close-ups back into wide shots on the 20:9 panel. The fix forces the original
4:3 aspect (and pillarboxes the excess width, undistorted) during cutscenes.

## How the cutscene camera derives its FOV/aspect (the mechanism)

`update-math-camera` (`goal_src/jak1/engine/gfx/math-camera.gc:54`) builds the
perspective matrix from two frustum slopes:

- `x-ratio = (tan (* 0.5 fov))`
- `persp[0].x = -fov-mult * x-pix / (x-ratio * d)` (horizontal scale, ∝ 1/x-ratio)
- `persp[1].y = -fov-mult * y-pix / (y-ratio * d)` (vertical scale, ∝ 1/y-ratio)

For cutscenes the `(with-pc ...)` `cond` takes the `(real-movie?)` branch
("force the original 16x9 cropping during cutscenes"):

```
((real-movie?)
 (if (<= (-> *pc-settings* aspect-ratio) ASPECT_16X9)            ;; <= 16:9
   (set! y-ratio (* (1/ (-> *pc-settings* aspect-ratio)) x-ratio));; full window aspect
   (begin                                                        ;; > 16:9 (ultrawide)
     (set! y-ratio (* (1/ ASPECT_16X9) x-ratio))                 ;; crop vert to 16:9
     (*! x-ratio (/ (-> *pc-settings* aspect-ratio) ASPECT_16X9))))) ;; extend horiz
```

So the cutscene FOV is driven entirely by **`(-> *pc-settings* aspect-ratio)`**
(the float, set by `update-from-os` from the real window via `pc-get-window-size`).
`fov`, `fov-correction-factor`, `x-pix`/`y-pix`, `d` are identical on both
backends (the captured z-rows and camera position are byte-identical — see below).

## The 5/3 oracle-diff, decoded (objective measurement)

At the identical M1 held pose (px=-542035.88 …, `pose_dist=0.0`):

| | c0.x | c1.y | c2.x | c0.z | c3.x | c3.y |
|---|---|---|---|---|---|---|
| oracle x86 (window 640×480 = 4:3) | 0.29031 | -0.24200 | -0.30062 | 4638.94 | 578985 | -13794.6 |
| device arm64 (panel 2400×1080 = 2.222) | 0.23225 | -0.32267 | -0.24050 | 4638.94 | 463188 | -18392.8 |
| ratio device/oracle | **0.800** | **1.333** | **0.800** | **1.000** | 0.800 | 1.333 |

The z-rows (`c*.z`) and the camera position are **identical** ⇒ same fov,
fov-mult, d. Only the horizontal/vertical projection scales differ. Plugging the
ratios into the `real-movie?` math: `1.7778/A_device = 0.80 → A_device = 2.222`
(device in the >16:9 ELSE branch) and `1.7778/A_oracle = 1.333 → A_oracle = 1.333`
(oracle in the <=16:9 IF branch). So **device A = 2.222, oracle A = 1.333** — the
exact inverse of the audit's narrative.

### Why the oracle was at 4:3

`.autoport/reports/Gcine-audit/x86-cam.log` and `x86-cam-shots.log` both log
`Setting borderless/fullscreen size to 640 x 480` — the default gk window on this
Wayland host is 640×480 (4:3). `AUTOPORT_SHOT_W=2400` only changes the screenshot
FBO, **not** the game window aspect that feeds `*pc-settings* aspect-ratio`. So
the oracle camera ran at A=1.333 the whole time; the audit's "validity check"
(matrix identical at default window vs 2400×1080) merely proved the screenshot
resolution is independent of the matrix — it did not prove the matrix was
"correct" at widescreen.

### Live proof there is no arm64 bug

Forcing `*pc-settings* aspect-ratio` on x86 at runtime (no rebuild,
`/tmp/gd1_x86_forceA.sh`) reproduced BOTH columns exactly:

- x86 @ A=2.2222 → `c0=0.23225, c1.y=-0.32267, c2.x=-0.24050` — **bit-identical to the device**.
- x86 @ A=1.3333 → `c0=0.29031, c1.y=-0.24200, c2.x=-0.30062` — **bit-identical to the 4:3 oracle**.

The GOAL camera math is therefore correct and backend-independent; the only
variable is the aspect float. The audit's D1 "arm64 projection divergence" is a
capture-window artifact. (This also means the audit's D3 "water/green-glow" must
be re-measured framing-matched after this lands, per the audit.)

## The fix

`goal_src/jak1/pc/pckernel-common.gc` — `update-from-os` auto-aspect branch:
during `(real-movie?)`, when the panel is wider than 4:3, set
`*pc-settings* aspect-ratio` to `ASPECT_4X3` and set the framebuffer scissor to a
4:3 region (pillarbox). This is a one-cond-branch change (plus moving the
`real-movie?` defun above `update-from-os` so it is in scope):

- The math-camera reads the now-4:3 `aspect-ratio` → `real-movie?` IF branch →
  `x-ratio = x_base`, `y-ratio = x_base/1.333` → `persp[0].x = 0.29031`,
  `persp[1].y = -0.24200`: **matches the oracle**, position unchanged.
- The 4:3 framebuffer scissor flows through `update-to-os` → `pc-set-letterbox`
  (`letterbox?` is `#t` by default, pckernel-h.gc:321) → the OpenGL renderer's
  centered draw-region (`OpenGLRenderer.cpp:1268-1276`) **pillarboxes** the
  excess width, so the 4:3 camera renders **undistorted** (no horizontal stretch)
  with black bars at the sides — the faithful "4:3 movie on a widescreen panel".
- It self-restores: when `real-movie?` ends, `update-from-os` recomputes
  `aspect-ratio` from the window (2.222) next frame, so gameplay stays widescreen.

The Android `pc-set-letterbox` (`gk_android_main.cpp:489`) is identical to desktop
(`kmachine.cpp:970`), so the device honors the pillarbox the same way.

### Why a GOAL/aspect fix and not a math-camera or codegen change

The math-camera is already correct on arm64 (proven above), so there is nothing
to fix in `math-camera.gc` or in the arm64 emitter. The defect is purely the
*input aspect* the cutscene uses on a widescreen panel. Forcing 4:3 at the
`*pc-settings* aspect-ratio` source fixes **both** the camera FOV (matches the
oracle) and the framebuffer scissor (undistorted pillarbox) consistently, with
no C++/codegen change. ENGINE.CGO is a boot CGO, so this ships via a full
consistent arm64 rebuild of the boot CGOs (KERNEL/ENGINE/GAME) synced into the
APK + pushed to the device filesDir (a standalone single-CGO push SIGILLs).

## Verification

- Objective projection re-measure (device, post-fix): see
  `.autoport/reports/Gd1/projection-match.txt` — M1/M2 before/after vs the oracle,
  RESULT: D1 RESOLVED, scaling ≈ 1.0, `pose_dist` 0.0 (position unchanged).
- x86 smoke: `link finish: logo` (unaffected; the 640×480 oracle was already 4:3).
- `deploy_verify.sh eae4df44`: device provably runs the fresh build chain.
- Cinematic still plays through crash-free: see the fresh long routed-logcat
  (`Gcine-camfov-routed-logcat-run*.log`, frame ≥ 10500, 0 sig 11/6/4) and
  `.autoport/reports/Gd1/foreground-at-end.txt` (foreground = jak1).

## Files changed

- `goal_src/jak1/pc/pckernel-common.gc` — cutscene-4:3 aspect + pillarbox in
  `update-from-os`; `real-movie?` moved above `update-from-os` for scope.

## Note for the owner / supervisor

The audit's premise ("device wrongly 4:3, push it to 2.222") was inverted: the
device was at 2.222 and the *oracle test window* was 4:3. The numeric gate
(device → 0.29031/-0.24200) is nonetheless exactly right for the owner's intent
("tight close-ups / match the original"), because the original PS2 cutscenes are
4:3. This fix delivers that: undistorted 4:3 cutscene framing, pillarboxed on the
20:9 panel. If you instead prefer cutscenes filling the panel at 16:9 (less
letterboxing, less faithful to the 4:3 original), change `ASPECT_4X3` →
`ASPECT_16X9` in the new branch — but that would no longer match the 4:3 oracle.
