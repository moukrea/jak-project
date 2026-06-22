# Gwater-lod fix-summary — near-camera water "blue squares" (RE-DO, owner ground truth)

## Defect (owner, 2026-06-21)
On the title attract flyover, when the camera flies close to the Sandover water,
the near-camera water chunks were reported to render as plain blue squares (the
detailed near-ocean surface looked missing), while the far water looked fine.

## Mandate
Re-baseline on the fresh consolidated HEAD FIRST (several owner-visible defects
turned out to be stale-deployment artifacts already correct on HEAD). Dump per-
near-chunk water LOD + detailed-draw counts x86-first (original-x86 vs our-x86 vs
device, NEVER pixels). If the device near-chunks draw flat/0 while x86 draws
detailed, fix the ocean renderer/LOD in the translation layer. our-x86 == original;
1-to-1 source.

## Outcome (short version)
The defect does NOT reproduce on the fresh consolidated HEAD. The device near-ocean
path draws the DETAILED near surface (up to 14 chunks, 7038 verts/frame, real
perspective texcoords, blue-green colors) 1-to-1 with the original-x86 oracle on
every measured metric. It was a stale pre-consolidate DEPLOYMENT artifact, not a
live translation gap. No goal_src edit and no translation-layer code change were
required, and none were made. Full evidence in
`.autoport/reports/Gwater-lod/water.txt`.

## How the near ocean works (so the metric is meaningful)
- The ocean is two buckets: `ocean-mid-and-far` (low/medium detail, always over
  water) and `ocean-near` (HIGH-detail tessellated water near the camera).
- The near bucket is gated in GOAL (`ocean.gc:498`) by
  `(not (or *ocean-near-off* *ocean-mid-off* (< 196608.0 (fabs (-> *math-camera* trans y)))))`
  — only when the camera is low (|Y| <= ~48m) over the ocean.
- `draw-ocean-near` (`ocean-near.gc:503`) loops over a near grid and emits one
  `(ocean-near-add-call 39)` per visible near chunk. `OceanNear::render` runs the
  portable VU2C (`OceanNear_PS2.cpp` `run_call0`/`run_call39`), xgkicks geometry to
  `CommonOceanRenderer::kick_from_near`, and `flush_near` draws the 3 near passes.
- Metric that reflects the defect: `call39` (near chunks/frame) and `flush_near`
  vertex/index counts. "flat/0" near (the blue-squares signature) = call39=0 /
  flush_near verts=0 (mid/far coarse fallback shows through near the camera).

## Investigation (x86-first, deterministic dumps, NO pixels)
1. Mapped the near path. The near-ocean GEOMETRY producers are: (a) goalc-compiled
   arm64 native code (`draw-ocean-near`, `ocean-near-add-upload` incl. inline
   VU0/MMI macros), and (b) the portable VU2C consumer (`OceanNear_PS2.cpp`). The
   five ocean mips2c builders are all in the arm64 kSet allowlist and bind REAL on
   device (verified: A37-MIPS2C-REAL for init-ocean-far-regs / render-ocean-quad /
   ocean-interp-wave / ocean-generate-verts; no FALLBACK). OceanNear is registered
   (not SkipRenderer'd) and its TUs are in android/CMakeLists.txt.
2. Added TEMPORARY C++ instrumentation (marked `// GWLOD-TEMP`) in the translation
   layer only — `OceanNear.cpp` (empty-bucket flag, call0/call39 counts) and
   `CommonOceanRenderer.cpp` (`flush_near`/`flush_mid` vertex + per-bucket index
   counts, xyz depth range, stq texcoord ranges, rgba channel ranges, FNV checksum
   over xyz+stq). Identical code logs on x86 (stdout) and device (logcat). NO
   goal_src was touched.
3. Ran the title attract on x86 (oracle) and on the fresh-HEAD device, both 180s,
   both crash-free, device focus = org.opengoal.gk.jak1 throughout.

## Measured result (the 3-way dump)
- original-x86 (== our-x86): near path renders DETAILED — max call39=14, max
  flush_near verts=7038 (idx0=idx1=idx2 ~1572-1578), zr=[0,0.996], stq raw/
  unclamped/q!=0, rgba=[28-128,74-156,84-172] a=[64-128] (R-max peaks 128).
- device (fresh HEAD, normal): MATCHES the oracle on every metric — max call39=14,
  max flush_near verts=7038, same 3-pass index split, same depth range, same
  unclamped texcoord shape (q!=0), same rgba distribution (R-max peaks 128, 593
  frames). The device draws the detailed near surface, NOT a flat-blue fallback.
- our-x86 == original-x86: identical (ocean source byte-for-byte upstream;
  git-clean; goalc x86 emitter untouched; all goalc mods arm64-gated).

## BEFORE / AFTER calibration (device A/B via a temporary skipnear toggle)
To calibrate the flat/0 BEFORE and confirm the metric detects it, a temporary
property gate `debug.gwlod.skipnear` was added to `OceanNear::render` (skips the
near draw, reproducing the pre-Gwater / stale-deployment condition: far/mid render,
near produces nothing). Same build, two device runs:
- BEFORE (skipnear=1): 3210 `near: SKIPPED`, flush_near verts=0, call39=0 — the
  calibrated flat/0 (blue-squares) signature; far/mid still render; crash-free.
- AFTER  (skipnear=0): max call39=14, flush_near verts=7038 — detailed, matching
  the oracle; crash-free.
This proves the dump metric cleanly separates flat/0 (near absent) from detailed
(near present), and that the fresh-HEAD device is in the DETAILED state.

## Visual corroboration (supplementary)
14 fresh-HEAD device frames across the title flyover show detailed textured ocean
(gradients, sun reflection, horizon haze) — no flat blue-square grid in any beat.
In the title framing the visible water is dominated by the mid/far ocean, so the
near-on vs near-off frames look similar (mid/far masks the near sliver). The
authority for "near draws the detailed surface" is the per-near-chunk dump, not the
screenshots — consistent with the no-pixels mandate.

## Root cause
Stale deployment. The owner observed the blue squares on a pre-consolidate build;
the Gconsolidate-deploy (committed just before this phase) put the device on the
fresh consistent HEAD. The near-ocean rendering has been present and correct in
HEAD since the Gwater phase. This phase verifies, with deterministic x86-first
per-near-chunk dumps + a skipnear A/B calibration, that the device now draws the
detailed near surface 1-to-1 with the original. Parallel to the Ghalo phase (a
deployment regression diagnosed and verified, not a fresh code bug).

## Why no code fix
Per the supervisor's own discriminator ("if device near-chunks draw flat/0 while
x86 draws detailed, fix the renderer/LOD"), the device near-chunks draw DETAILED
(7038 verts / 14 chunks), matching x86 — so no renderer/LOD/mips2c/CMake/GLES-gate
change is warranted. The OCEAN_COMMON vert/frag shaders are byte-identical desktop
vs android (only the GLES header differs) and are SHARED with the working mid path.
All near vertex attributes (geometry, texcoords, colors) match the oracle. There is
no measurable divergence to fix.

## Instrumentation removed / cleanliness
- ALL temporary `// GWLOD-TEMP` instrumentation has been REMOVED. The two touched
  translation-layer files (`game/graphics/opengl_renderer/ocean/OceanNear.cpp` and
  `game/graphics/opengl_renderer/ocean/CommonOceanRenderer.cpp`) were reverted to
  their pristine committed state (no GWLOD-TEMP lines, no skipnear toggle, no dump
  prints, no debug includes). Verified `git status` clean for those paths.
- No `goal_src/**` edit was made (1-to-1 source preserved).
- `.autoport/gold` is untouched / git-clean.
- After removing the instrumentation, libgk was clean-rebuilt and re-deployed so the
  device runs the instrumentation-free fresh HEAD; deploy_verify PASS.
- x86 still reaches `link finish: logo`.

## Artifacts
- `.autoport/reports/Gwater-lod/water.txt` — the 3-way per-near-chunk dump.
- `.autoport/reports/Gwater-lod/x86-gwlod-b.log` — x86 oracle dump (extended).
- `.autoport/reports/Gwater-lod/dev-after-logcat.log` — device AFTER (near on).
- `.autoport/reports/Gwater-lod/dev-before-logcat.log` — device BEFORE (near off).
- `.autoport/reports/Gwater-lod/dev-after-f*.png`, `dev-before-f*.png`,
  `dev-gwlodb-f*.png` — inspected title-flyover frames.
