# Gcine-audit — New-game intro cinematic: objective arm64-vs-x86 divergence map

**Phase:** Gcine-audit (DIAGNOSTIC — no code fix). **Device:** Redmi Note 9 Pro
`eae4df44` (arm64), pkg `org.opengoal.gk.jak1`, running deploy-verified HEAD
`ee94c8418` libgk.so. **Oracle:** desktop `build-x86/game/gk` (jak1, new game).
**Date:** 2026-06-17.

The owner's directive was: *"check yourself for issues, there must be a proper
way without me."* This map is produced OBJECTIVELY by diffing the device
cinematic against the x86 ORIGINAL — a per-frame camera/scene DATA diff plus a
pair of matched-beat pixel diffs — NOT by eyeballing. Every divergence below
cites an artifact that exists under `.autoport/reports/Gcine-audit/`.

## TL;DR (ranked)

| # | Category | Verdict | Magnitude | Confidence |
|---|----------|---------|-----------|------------|
| **D1** | **Camera projection / FOV** | **DIVERGENT** | cutscene proj. scaled h×0.80, v×1.333 vs oracle (aspect 2.222→1.333) | HIGH |
| **D2** | Cadence / transition-between-camera-plans | DIVERGENT | misty scene +564 frames (5.6%) longer; 3 early-misty hard cuts absent on device | MEDIUM |
| **D3** | Lighting / green-glow (render) | CANDIDATE | M2 blown-out white glow orb + missing warm-pink halo; **confounded by D1** | MEDIUM-LOW |
| C1 | Camera position / trajectory | **MATCHES oracle** | pose_dist 0.0 at both held beats; NaN/Inf = 0 | — |
| C2 | fog params / hvdf projection offset | **MATCHES oracle** | fog median Δ0.20, hvdf median Δ0.00 | — |
| C3 | Crash / native signal | **none in-window** | 0 Fatal-signal lines; run-end is a logging artifact (see Limitations) | — |
| C4 | "Water is garbage" | **NOT reproduced as a separate defect** | device M1 ocean renders plausibly; apparent badness is the D1 framing | — |

---

## Method

**Instrumentation (shared, both backends).** `game/graphics/opengl_renderer/
background/background_common.cpp` emits one `GCINE-CAM` line per rendered frame
from the *same* translation unit compiled into both `gk` (x86) and `libgk.so`
(arm64), so the x86 capture is a valid oracle for the device capture. It is
OFF by default and armed by `OG_GCINE_CAM=1` (x86) / `setprop
debug.opengoal.gcine.cam 1` (Android); no cinematic behavior change. Each line
logs the **frame counter** (`f=` = renderer `frame_idx`), level, the
math-camera **position** (`px,py,pz`), the full 4×4 **camera matrix** (`c0..c3`,
the value actually handed to the renderer), the **hvdf** projection offset and
the **fog** params.

**Drive.** x86: boot to title, then trigger the NEW-GAME continue point
`(initialize! *game-info* game #f "intro-start")` via the goalc listener
(`.autoport/gcine_audit_x86.sh`). Device: boot, then NEW GAME → CONTINUE WITHOUT
SAVING via `cpad_inject` menu navigation (`.autoport/gcine_audit_device.sh`),
foreground verified `mCurrentFocus=org.opengoal.gk.jak1` before any capture.

**Alignment (frame counter, not wall-clock).** `f=` is the global renderer
frame counter and is NOT comparable in absolute terms across boots. Both streams
are re-indexed to a **cinematic-relative frame** = `f - f@(first misty frame)`.
`misty` only appears inside the cinematic, so its onset is a robust t=0 anchor
(x86 misty onset abs 3319; device 4634). The pre-anchor `village1`/`title` is the
free-running, non-deterministic **title attract** and is EXCLUDED (`--min-rel 0`).
Tool: `.autoport/lib/gcine_diff.py diff`.

**Pixel beats (water / green-glow).** Two FULLY-STATIC held-camera windows on
Misty Island (the "destination island") chosen from the oracle because the
camera position is invariant for >200 frames there, so frame-exact alignment is
unnecessary: **M1** misty-rel ≈900 (pos −542036,14013,1402530) and **M2**
misty-rel ≈4200 (pos −902937,117739,4154412). Device stills snapped live when
the frame counter entered each window; matched to the nearest-pose oracle still
by camera position, then `frame_compare.py`. Tool: `.autoport/lib/
gcine_beat_match.py`.

**Tolerances.** Camera position: game units (typical coords are millions; <~1%
of magnitude ≈ matched). Camera matrix rows: unitless. Pixel metric:
`frame_compare.py` diff_frac at per-channel threshold 56 (cross-renderer GLES-vs-
GL floor is ~2% per the Pcompare gate); diff_frac ≫ a few % = real render
divergence. Hard-cut detection: |Δpos| between consecutive frames > 200000 units.

**Validity check.** The oracle camera matrix is IDENTICAL whether `gk` renders
at the default window or at 2400×1080 (`c0.x=0.29031` in both `x86-cam.log` and
`x86-cam-shots.log` at the M1 pose), proving the camera matrix is *game-computed*
and resolution-independent — so the device divergence below is a real arm64
computation difference, not an output-resolution artifact.

---

## D1 — Camera projection / FOV divergence (HIGH)

At BOTH matched-pose held beats the device camera is at the **exact same world
position** as the oracle (`pose_dist=0.0`) yet the **projection matrix rows
differ by a consistent scale**, changing the on-screen framing from the intended
tight close-up to a pulled-back wide shot.

```
beat M1 (misty-rel ~900, dev f5506 vs x86 f4140)   beat M2 (misty-rel ~4200, dev f8801 vs x86 f6900)
  c0.x  0.29031 -> 0.23225   (×0.80)                 c0.x -0.36038 -> -0.28831  (×0.80)
  c1.y -0.24200 -> -0.32267  (×1.333)                c1.y -0.23967 -> -0.31955  (×1.333)
  c2.x -0.30062 -> -0.24050  (×0.80)                 c2.x  0.22171 ->  0.17736  (×0.80)
  (all c0.z/c1.z/c2.z and px,py,pz IDENTICAL)         (all z-components and position IDENTICAL)
```

- **What:** horizontal projection scale ×0.80 (=4/5), vertical ×1.333 (=4/3),
  z-depth and position untouched — i.e. a different effective **FOV/aspect** in
  the cutscene camera. The encoded aspect ratio shifts by **5/3**, exactly the
  ratio between widescreen **2.222** (x86) and **4:3 = 1.333** (device).
- **Where:** every cutscene camera plan sampled; identical factors at two
  unrelated beats ⇒ systematic, not per-shot.
- **Metric/Evidence:** `beat-diffs/beat-compare.txt` (pose_dist 0.0, diff_frac
  0.637 / 0.307); raw camera lines in `arm64-cam.log` (f5506,f8801) and
  `x86-cam-shots.log` (f4140,f6900); side-by-side stills
  `device-shots/mistyrel900_f5506.png` vs `x86-shots/autoport_f004140.png`
  (oracle = Jak face close-up; device = wide shoreline) and
  `device-shots/mistyrel4200_f8801.png` vs `x86-shots/autoport_f006900.png`
  (oracle = tight pink-halo villain; device = wide Lurker battlefield).
- **Likely cause / fix direction:** the cutscene/`math-camera` FOV-aspect
  derivation on arm64. The 5/3 = 2.222↔1.333 signature strongly implicates the
  known arm64 aspect class (cf. Gtitle / Gaspect). NB: the menu analysis
  concluded the *global* `*video-parms*` aspect float is correct (2.222), so the
  cutscene camera likely reads a different/stale aspect (or applies it to the
  wrong projection axis). A single-defect fix phase should localize where the
  cutscene math-camera computes its horizontal vs vertical FOV on arm64.
- **Priority:** #1 — it is the dominant visible divergence AND a prerequisite to
  cleanly re-measure D3 (the framing confound).

## D2 — Cadence / transition-between-camera-plans (MEDIUM)

- **What:** the device plays the misty (Gol/Maia portal) scene **+564 frames
  longer** than the oracle — x86 leaves misty for `village1` at cinematic-rel
  **10001**, device at **10565** (`data-diff.txt`, "scene onset alignment",
  onset_delta=+564, +5.6%). Additionally, three oracle hard cuts in early misty
  (cinematic-rel **1866, 2124, 2555**) have **no device counterpart**; the later
  cuts line up (device 2749/3143/5336 ≈ oracle 2733/3127/5300, within ~16
  frames of cadence drift). So some early camera-plan transitions either don't
  fire or don't move the camera on arm64.
- **Where/metric:** `data-diff.txt` "ordered scene SEGMENTS" and "hard cuts"
  sections; `diffout/camdelta.csv` (per-rel-frame deltas).
- **Confidence:** MEDIUM — a longer frame count can be device load-hitching
  (vsync frames repeated during a load) rather than a scene-player logic
  divergence, and "missing cut" is inferred from camera-position jumps (a proxy;
  the scene-player STAGE index was not instrumented). The missing *early-misty*
  cuts are the more interesting signal and match the owner's "transitions
  between camera plans" complaint.
- **Fix direction:** instrument the scene-player stage/active-camera index next
  to disambiguate load-hitch vs real cut-skip before any fix.

## D3 — Lighting / green-glow (render) — CANDIDATE, confounded by D1

- **What:** at beat M2 the device frame shows a **blown-out pure-white glow orb**
  on the right and **lacks the oracle's warm pink-halo lighting** over the
  Gol/Maia portal scene. This is the closest objective match to the owner's
  "weird green-glow lighting on the destination island."
- **Where/metric:** `device-shots/mistyrel4200_f8801.png` vs `x86-shots/
  autoport_f006900.png`; diff image `beat-diffs/mistyrel4200_f8801.diff.png`;
  diff_frac 0.307 / rmse 46.9 (`beat-compare.txt`).
- **Confidence:** MEDIUM-LOW — the M2/M1 pixel diffs are **dominated by the D1
  framing difference** (different content on screen) plus the phone touch
  overlay, so a separate lighting/bloom defect cannot be cleanly isolated until
  D1 is fixed. Re-run this beat AFTER D1 lands (framing-matched) to confirm.

---

## Categories that MATCH the oracle (objective determinations)

- **C1 Camera position / trajectory — MATCHES.** Both held beats land at
  `pose_dist=0.0`; over the first 50 misty frames the per-frame position delta is
  median **33 units** (`data-diff.txt` partial); across all of misty the
  local-aligned median is ~3.9k units out of million-scale coords (<0.4%), and
  the large tail is the D2 cadence drift, not a path error. The camera FOLLOWS
  the correct path; only its projection (D1) is wrong.
- **C1b NaN/degenerate camera math — none.** `NaN/Inf camera records: x86=0
  arm=0`. The Gcine-pose NaN-bone fix holds; no pose-blink in the captured
  window.
- **C2 fog / hvdf — MATCH.** Over the misty window fog params diverge by median
  **0.20** and hvdf (projection offset) by median **0.00** (`data-diff.txt`);
  the only large fog values are uninitialized garbage in the oracle's
  cadence-misaligned `village1` frames, not a device defect.
- **C3 Crash / native signal — none in-window.** `0` Fatal-signal/backtrace
  lines (`arm64-cam.log`, `arm64-foreground.txt`, `device-run.out`). The
  cinematic is already supervisor+owner-verified crash-free to gameplay
  (Gcine-crash3). The capture's early end at frame ~15200 is a **diagnostic-
  logging artifact** (see Limitations), not a cinematic defect.
- **C4 "Water is garbage" — NOT reproduced as a separate defect.** At beat M1 the
  device Misty ocean renders as a plausible dark night ocean with mountains; its
  apparent wrongness is the D1 pulled-back framing, not a broken water shader.

---

## Recommended fix order

1. **D1 — cutscene camera FOV/aspect (arm64).** Highest impact, clearest, fully
   reproducible; fixing it restores correct framing and is a prerequisite to
   honestly re-measure D3. Start at the arm64 cutscene/`math-camera`
   horizontal-vs-vertical FOV derivation; check the 2.222↔1.333 aspect path.
2. **D2 — cadence/transitions.** First add scene-player STAGE instrumentation to
   separate load-hitch from real early-misty cut-skips, THEN fix only if a real
   cut is skipped.
3. **D3 — lighting/glow.** Re-capture beats M1/M2 AFTER D1 lands (framing-
   matched) and re-diff; fix only the residual that survives the D1 fix.

## Method limitations / recommended follow-up

- Only the **math-camera** was instrumented, not the scene-player stage / active
  camera index — D2 "missing cut" is inferred from camera-position jumps.
- The per-frame `GCINE-CAM` log plus a mis-gated pre-existing `GINTRO-CHAINWALK`
  flood (android_gfx.cpp, ~14 logcat lines/frame) make the device run ANR/return
  to launcher around frame ~15200, so the capture covers **title→attract→misty
  (full)→entry into post-misty village1** but NOT the later `beach`/`village1`/
  `training` scenes. To complete the cadence fingerprint, re-capture with the
  GINTRO-CHAINWALK flood quieted and/or GCINE-CAM throttled to every Nth frame.

## Artifact index (all under .autoport/reports/Gcine-audit/)

- `x86-cam.log` — oracle per-frame camera log (default window, 30168 recs).
- `x86-cam-shots.log` — oracle camera log for the 2400×1080 still pass.
- `arm64-cam.log` — device per-frame camera log (13802 recs, misty complete).
- `arm64-cam-run0.log` — earlier device partial (regex-bug run, kept for audit).
- `arm64-foreground.txt`, `device-run.out` — device end-of-run focus/scoreboard.
- `data-diff.txt` — full DATA-diff output (alignment, cadence, cuts, fog/hvdf).
- `diffout/camdelta.csv` — per-cinematic-relative-frame camera deltas.
- `device-shots/mistyrel900_f5506.png`, `device-shots/mistyrel4200_f8801.png` —
  device held-beat stills (M1, M2).
- `x86-shots/autoport_f004140.png`, `x86-shots/autoport_f006900.png` — matched
  oracle stills (M1, M2).
- `beat-diffs/*.diff.png`, `beat-diffs/beat-compare.txt` — pixel-diff images +
  metrics.
- Tools: `.autoport/lib/gcine_diff.py`, `.autoport/lib/gcine_beat_match.py`,
  `.autoport/gcine_audit_x86.sh`, `.autoport/gcine_audit_device.sh`.
