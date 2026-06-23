# Phase Gtouch-rightstick — fix the right camera control: floating INVISIBLE virtual stick, not a mouse-drag

## The defect (owner, 2026-06-23, testing the deployed touch overlay)
The right-side camera control currently behaves like a **mouse/trackpad**: it pans from the frame-to-
frame **drag delta** (`TouchOverlayView.java` uses `lastX/lastY` → delta → RIGHTX/RIGHTY) with very low
sensitivity — the owner calls it "horrible." Everything else in the overlay is good (buttons, the
fixed visible left stick, fade, icons) — ONLY the right camera control is wrong.

## What the owner wants — a FLOATING invisible virtual stick (like the left stick, but invisible + dynamic)
On the **right 3/4 of the screen**, any touch that is **not on a button**:
1. **Anchors an INVISIBLE virtual stick at the touch-down point** (no glyph drawn — invisible).
2. The camera axis = the **DEFLECTION** = the offset of the current finger position from the anchor,
   clamped to a max radius and normalized to [-1,1] → injected as **RIGHTX/RIGHTY** (continuous).
   Holding the finger deflected = **sustained camera pan** (like holding a real stick), NOT a per-frame
   delta. This is the standard modern-mobile floating right stick (Genshin/CoD-Mobile style).
3. On release, the invisible stick disappears and RIGHTX/RIGHTY return to 0.
The LEFT stick stays as-is (fixed position, VISIBLE). The right stick is the opposite: invisible,
spawns wherever the finger lands in the right 3/4 zone, deflection-based.

## Mandate (android-only; goal_src 1-to-1)
Rework ONLY the right-camera handling in `TouchOverlayView.java` (+ any axis glue): replace the
delta-based RIGHTX/RIGHTY with the anchor+deflection model above. Keep the right-3/4 zone exclusion of
button hit-zones (a touch on a button still actuates the button). Tune the max-radius + sensitivity so
it feels like a stick (a comfortable deflection gives a brisk-but-controllable pan). Do not regress the
rest of the overlay.

## Validator (`phase-Gtouch-rightstick.sh`) PASS requires
1. `.autoport/reports/Gtouch-rightstick/cam.txt`: shows the right camera is now **anchor+deflection**
   (an anchor point captured at touch-down; RIGHTX/RIGHTY computed from `cur - anchor` normalized, NOT
   from `cur - last` delta) — cite the code path. An **actuation test**: a synthetic touch-down at a
   right-zone point then a HELD offset produces a SUSTAINED non-zero RIGHTX/RIGHTY (proportional to the
   offset), and the SAME held offset keeps injecting (not decaying to 0 like a delta would). Release →
   RIGHTX/RIGHTY = 0. With `RESULT: RIGHT CAMERA IS A FLOATING DEFLECTION STICK (sustained, not delta)`.
2. The code no longer derives the camera axis from a frame-delta (`lastX/lastY` delta) — grep-proven.
3. android-only change; goal_src 1-to-1. Fix-summary `.autoport/reports/Gtouch-rightstick-fix-summary.md`
   ≥60 lines; temp instrumentation removed. Builds + installs + boots to gameplay; `deploy_verify.sh
   eae4df44` PASS; x86 `link finish: logo`.
4. Feel/sensitivity is owner-eye-final.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. `.autoport/gold` READ-ONLY. Keep device awake. After any failing device
run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1200`, `max_retries: 3`.
