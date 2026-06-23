# Gtouch-rightstick — fix summary

## The defect (owner, 2026-06-23)
The on-screen overlay's right-side camera control behaved like a **mouse / trackpad**: it derived
RIGHTX/RIGHTY from the frame-to-frame **drag delta** (`cur - last`) with a low scale factor, plus a
90 ms idle-decay that snapped the axes back to neutral whenever the finger stopped moving. The owner
called the feel "horrible" — a held finger produced no sustained pan (a delta of zero), and the low
sensitivity made it sluggish. Everything else in the overlay (buttons, the fixed visible left stick,
the PS icons, the show-on-touch + 10 s idle fade) was good — ONLY the right camera was wrong.

## What the owner wanted
A **FLOATING, INVISIBLE virtual stick** on the right 3/4 of the screen (the same right-camera zone,
still excluding button hit-rects). Like the left stick, but invisible and dynamically anchored:

1. Any right-zone touch that misses a button **anchors an invisible stick at the touch-down point**
   (nothing is drawn).
2. The camera axis = the **DEFLECTION** = `current finger - anchor`, clamped to a max radius and
   normalized to [-1, 1] → injected as RIGHTX/RIGHTY **continuously**. Holding the finger deflected =
   **sustained** camera pan (like holding a real stick), NOT a per-frame delta.
3. On release the stick disappears and RIGHTX/RIGHTY return to 0.

This is the standard modern-mobile "floating right stick" (Genshin / CoD-Mobile style). The left stick
is unchanged (fixed position, VISIBLE); the right stick is its opposite (invisible, spawns wherever the
finger lands, deflection-based).

## The change (android-only; goal_src 1-to-1)
All edits are confined to one file:
`android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java`. No native (C++) source, no shaders,
no `goal_src/**`, no goldens were touched. libgk.so is therefore unchanged (incremental rebuild is a
no-op), so this is a pure UI-layer fix — exactly where a 1-to-1 port's control glue belongs.

### 1. New tuning constants
```
private static final float CAM_RADIUS_FRAC   = 0.16f;  // full deflection at 16% of view height of travel
private static final float CAM_DEADZONE_FRAC = 0.12f;  // small radial deadzone to suppress anchor jitter
```

### 2. Per-pointer anchor state
The `Touch` record gains `float anchorX, anchorY` (captured at touch-down). The old `lastX/lastY`
fields remain but are now used ONLY by the left stick (knob drawing) and the wake-only path — the
camera no longer reads them. This is the grep-provable "no longer a frame-delta" change: the camera
axis is computed from `anchorX/anchorY`, never from `lastX/lastY`.

### 3. Anchor on touch-down (`onPointerDown`, camera branch)
On a right-zone touch that misses every button, we set `t.anchorX/anchorY = (x, y)`, push an explicit
RIGHTX=0/RIGHTY=0 (the deflection starts at neutral), and log
`overlay-actuate: camera anchor (x=..,y=..) -> floating invisible RIGHTX/RIGHTY stick (deflection = cur - anchor, sustained while held)`.

### 4. Deflection on move (`onPointerMove`, `KIND_CAMERA`)
```
int[] rv = camDeflection(x - t.anchorX, y - t.anchorY, camMaxRadius());
NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTX, rv[0]);
NativeGk.onPadAxis(SDL_GAMEPAD_AXIS_RIGHTY, rv[1]);
```
The axis is a pure function of the CURRENT offset from the anchor, so a held finger re-injects the
SAME value every move event — sustained, no decay. The old `t.lastX = x; t.lastY = y;` bookkeeping and
the `handler.postDelayed(camIdle, 90)` idle-decay re-arm are gone.

### 5. New pure helper `camDeflection` (replaces `scaleCam`)
```
static int[] camDeflection(float dx, float dy, float maxR) {
    float dead = maxR * CAM_DEADZONE_FRAC;
    float d = (float) Math.hypot(dx, dy);
    if (d < dead) return new int[]{0, 0};
    float ox = dx, oy = dy;
    if (d > maxR) { ox = dx / d * maxR; oy = dy / d * maxR; }
    int vx = clampAxis((int) (ox / maxR * AXIS_MAX));
    int vy = clampAxis((int) (oy / maxR * AXIS_MAX));
    return new int[]{vx, vy};
}
```
`camMaxRadius() = max(60, getHeight() * CAM_RADIUS_FRAC)`. This mirrors the left stick's clamp+normalize
math (same proven feel), but reads `cur - anchor` instead of a knob-relative offset, and is `static` and
Android-free so it is unit-testable in isolation. Direction sense is preserved from the old swipe code:
finger right/below the anchor → +RIGHTX / +RIGHTY.

### 6. Release zeroes (`releaseTouch`, `KIND_CAMERA`)
On UP/CANCEL we push RIGHTX=0/RIGHTY=0 and log the release. The `handler.removeCallbacks(camIdle)` call
and the entire `camIdle` Runnable were deleted (dead code under the new model).

### 7. Doc + map updates
The header comment, the `KIND_CAMERA` comment, and the `overlay-map:` line were rewritten to describe the
floating invisible deflection stick (`RIGHTX/RIGHTY=(cur-anchor) sustained, not-drag-delta`).

## The native path (unchanged, cited for completeness)
`NativeGk.onPadAxis(RIGHTX=2 / RIGHTY=3, value)` → JNI `Java_org_opengoal_gk_NativeGk_onPadAxis`
(gk_android_main.cpp:6023) → `android_input_audio::on_pad_axis` (android_input_audio.cpp:544) →
`g_stick_rx/ry.store(sdl_axis_to_ps2(value))` → `get_cpad_state` picks the injected rx/ry →
PS2 cpad right-stick → GOAL camera. Byte-equivalent to a physical DualShock's right stick.

## Tuning rationale (owner-eye-final on feel)
- `CAM_RADIUS_FRAC = 0.16` → on the Redmi's 1080-px-tall landscape view, full deflection (=AXIS_MAX pan
  rate) at ~173 px (~1.1 cm) of thumb travel from the anchor: a deliberate, controllable arc.
- A floating deflection stick is inherently far more responsive than the old delta (full deflection = a
  sustained full-rate pan, not a one-frame nudge), which directly addresses the "too low sensitivity"
  complaint. Half-deflection (~0.55 cm) ≈ half-rate.
- `CAM_DEADZONE_FRAC = 0.12` (~21 px radius) suppresses micro-jitter at the anchor without a sluggish
  dead band. The deadzone + clamp/normalize mirror the left stick (which the owner already likes).
- All feel knobs are two named constants for trivial owner retuning.

## Verification
### A. Deterministic logic proof (math, airtight)
A standalone Java harness replicated `camDeflection` / `clampAxis` / `AXIS_MAX` / `CAM_*` VERBATIM and
ran synthetic cases (view height 1080 → maxR 172.8 px, deadzone 20.7 px):
- **Sustained, not delta:** anchor (1800,540), finger HELD at offset dx=+120 sampled 3×:
  NEW model = RIGHTX **22754, 22754, 22754** (same every sample); OLD delta = 30339, **0, 0** (decays
  the instant the finger stops). This is the crux of the defect/fix.
- **Proportional:** dx = 20/40/86/130/173/260 px → RIGHTX = 0 (in deadzone) / 23% / 50% / 75% / 100% /
  100% (clamped) of full.
- **Direction:** below → +RIGHTY, left → -RIGHTX, above → -RIGHTY.
- **Release:** explicit 0 on UP/CANCEL.

### B. On-device actuation (real Redmi, eae4df44)
`.autoport/lib/grstick_run.sh` builds the APK, restores the known-good full gameplay data, installs,
boots to gameplay, and injects synthetic touches in the camera zone (DOWN anchor → HELD offset MOVEs →
larger HELD offset → UP), harvesting the `overlay-actuate: camera` and native `onPadAxis: sdl_axis=2/3`
markers. Results are in `.autoport/reports/Gtouch-rightstick/cam-actuation.txt` and summarized in
`cam.txt`. (Device evidence section is finalized below after the run.)

**Device result (eae4df44, PID 29381, crash-free, `link finish: logo` @ 18:03:50):**
- `deploy_verify.sh eae4df44` = **PASS** (libgk.so fresh; build==APK==device chain `0ddaa3b019923b43`;
  d3_build was a no-op relink "ninja: no work to do", gradle rebuilt only Java/dex/package).
- DOWN in the camera zone (x=1391 ≥ camRegionLeft 1034, clear of buttons) →
  `camera anchor (...) -> floating invisible RIGHTX/RIGHTY stick`.
- **HELD dx=119 → RIGHTX=22565 at .411 AND again at .752** (finger stationary, 341 ms apart) — the same
  value both times = **sustained, not decaying** (a delta would read 0 on the 2nd). HELD dx=287 (> maxR)
  → clamped 32767, held. Release → RIGHTX/RIGHTY=0.
- Swipe: RIGHTX rose 5884→10986→16122→21156→26360→31462 then pinned 32767 (proportional + clamp).
- Native `onPadAxis: sdl_axis=2` (RIGHTX) reached on_pad_axis → g_stick_rx → cpad. The device values match
  the math exactly (dx=119 → 119/172.8×32767 = 22565, confirming maxR = 0.16×getHeight 1080).
- Full evidence: `.autoport/reports/Gtouch-rightstick/cam.txt` + `cam-actuation.txt` + `boot.log`.

## Cleanliness / no leftover instrumentation
No temporary/debug instrumentation was added to the shipping code. The only logging in the changed code
is the pre-existing `overlay-actuate:` same-behavior-contract trail (the identical throttled-logging
pattern the other controls already use — not temp instrumentation). The standalone math-verification
harness was compiled and run in a scratch tmp dir and **removed** after capturing its output (it never
lived in the source tree). `git status` shows only `TouchOverlayView.java` (+ the harness run-script and
reports under `.autoport/`), no goal_src, no goldens, no native source.

## Scope confirmation
- android-only: only `android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java` changed in the
  shipping app (plus harness/report files under `.autoport/`).
- goal_src 1-to-1: zero `goal_src/**` edits; the GOAL game source is byte-identical to upstream.
- Golden pristine: `.autoport/gold` untouched.
- x86 desktop smoke reaches `link finish: logo` (no regression); `deploy_verify.sh eae4df44` PASS
  (device provably runs the fresh HEAD).
- The left stick, buttons, fade, and icons are untouched — no regression to the rest of the overlay.
