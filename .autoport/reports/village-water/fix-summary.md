# village-water — diagnosis of "water is kinda weird, not animated" + "sunlight has issues"

Outcome: **DIAGNOSIS ONLY — no fix shipped.** The headline complaint ("water not
animated") is **falsified by hard runtime evidence**: the ocean wave surface
DOES animate frame-to-frame on the arm64 device. There was therefore no
dead-animation defect to fix. The "sunlight" complaint is a real-looking visual
divergence (flat/low-shimmer water, weak specular sky/sun reflection) but I could
NOT pin a specific arm64 mechanism with evidence, so per the mandate I did not
guess-fix it. The tree is left at clean HEAD; the device APK was rebuilt clean.

## 0. State check — the prior "Gwater" work has already LANDED (don't redo)

The MEMORY/Gwater summary said "ocean renderer never compiled into the Android
build" and "ocean mips2c builders noop'd". That is STALE. The current code (commit
`abb7c1237`, an ancestor of HEAD `d343e2164`) already has all of it:

- `android/android_opengl_renderer.cpp:304-307` — `OceanMidAndFar` and `OceanNear`
  registered as REAL renderers (not `SkipRenderer`); only `shadow`/`depth-cue`
  remain in `unported[]`.
- `android/CMakeLists.txt:509-516` — all 8 ocean TUs compiled in.
- `game/mips2c/mips2c_table_jak1_arm64.cpp:490-491` — the 5 ocean builders
  (`init-ocean-far-regs`, `render-ocean-quad`, `draw-large-polygon-ocean`,
  `ocean-interp-wave`, `ocean-generate-verts`) are in the `kSet` allowlist.

Device logcat confirms at runtime: `A37-MIPS2C-REAL` for all four trampoline-bound
ocean builders, **zero** `A37-MIPS2C-FALLBACK ocean*`, and **zero**
`A35-RENDER skip bucket=ocean*`. The ocean is built and drawn. tris_max ~616k.

## 1. Is the water static? NO — it animates (decisive evidence)

The wave animation is driven by `draw-ocean` (`ocean.gc:462-466`):
```
(ocean-interp-wave *ocean-heights*
   (the uint (* (/ (-> *display* time-factor) 5.0)
                (-> *display* integral-frame-counter))))   ; per-frame phase
(ocean-generate-verts *ocean-verts* *ocean-heights*)
```
The phase advances every unpaused frame (`integral-frame-counter` is bumped in
`drawable.gc:1017`; the renderer frame counter reaches 2400+ and sparticles/camera
animate, so the counter is live). `ocean-interp-wave`/`ocean-generate-verts` are
mips2c **interpreter** bodies (`ExecutionContext`), i.e. host-architecture-
independent C++ — they compute bit-identical wave heights on arm64 and x86. The
phase `(the uint float)` lowers to `fcvtzs` (arm64) of a value well within int32
range, so no arm64 codegen hazard. So in principle the surface must animate.

Proven empirically with a temporary diagnostic (FNV-1a checksum of the per-frame
ocean-texture vertex block — the verts built from the current wave heights — logged
for the first 16 ocean-texture calls, then reverted):
```
GWATER-ANIM-DIAG ocean-tex-verts call=0  fnv=67ac7e1eb461b0cb
GWATER-ANIM-DIAG ocean-tex-verts call=1  fnv=67ac7e1eb461b0cb   <- pair (mid+near, same frame)
GWATER-ANIM-DIAG ocean-tex-verts call=2  fnv=76686e62e0f6f7cc   <- next frame: CHANGED
GWATER-ANIM-DIAG ocean-tex-verts call=3  fnv=76686e62e0f6f7cc
... 8 distinct checksums, one new value per frame:
67ac... -> 7668... -> 2a8a... -> 5c11... -> b322... -> 80bb... -> 5673... -> 53b1...
```
`draw-ocean-texture` runs twice per frame (mid pass `#t`, near pass `#f`,
`ocean.gc:482/501`), which is why each value appears as a pair. **Across frames the
surface-vertex checksum changes every single frame.** The ocean water surface
geometry/texture is animated on the device. The "not animated" report is a
perception of subtle wave motion seen from the high, always-moving attract camera —
not a dead animation.

Supporting pixel evidence (cannot fully isolate waves from the always-moving camera,
so this is corroborating, not primary): in the 16-frame 0.25s burst
(`device-burst-f*.png`), a top-right land patch used as a camera-motion proxy never
stops moving (per-frame mean|d| 18-76), so the attract camera never holds still.
During its steadiest window (f07-f11) the water region settles to mean|d| ~5-7 — the
remaining motion there is parallax, not a frozen surface.

## 2. The "sunlight" / water-look divergence (real, but mechanism NOT pinned)

Visually, the device ocean (e.g. `BEFORE-ocean-day-t070.png`,
`BEFORE-ocean-wide-burst-f08.png`) is a fairly uniform teal/blue-green sheet. The
original / our-x86 reference (`.autoport/reports/3tier/our-pc-01-attract-flythrough.png`,
day cycle) has more tonal variation, a brighter horizon band, and a visible specular
sun/sky glint. The device water looks comparatively flat and low-shimmer. This is
consistent with the owner's "sunlight has issues" and with "kinda weird" water.

Candidate mechanisms (each UNVERIFIED — would need its own oracle-diff/trace phase):
- **Ocean lighting from TOD.** `ocean-generate-verts` calls `vu-lights<-light-group!`
  with `*time-of-day-context*` (`ocean_vu0.cpp:394-401`) to light the surface. If the
  light group / TOD context fed to the ocean is wrong on arm64, the surface shading
  (incl. specular response) would be off. `time-of-day-interp-colors-scratch` IS on
  the allowlist, so the base TOD palette interp runs.
- **Envmap (bucket 2) sky/sun reflection.** `CommonOceanRenderer::flush_*` bucket 2
  (`CommonOceanRenderer.cpp:336-348`) blends an envmap reflection (`m_envmap_tex`,
  `GL_DST_ALPHA,GL_ONE`). If `m_envmap_tex` resolves to the placeholder, the moving
  sky/sun glint that makes the water "sparkle" would be absent — this is the most
  likely "not shimmering / sunlight" culprit. NOTE: the generic merc/tie envmap
  processors `generic-envmap-proc`/`generic-envmap-dproc` are still `A37-MIPS2C-
  FALLBACK` (noop) on arm64, but those are the GENERIC path, NOT the ocean's
  `ocean-texture-add-envmap` path — so they are a separate (merc/tie shine) issue,
  not proven to affect the ocean. The ocean envmap-tex source needs a direct trace.
- Genuine time-of-day: the attract cycles day->dusk; several captured frames are the
  dusk leg (purple sky), which legitimately flattens/darkens the water — must diff at
  a matched day moment before calling any of this a bug.

I did not edit anything for this because the mandate is "pin the mechanism first, no
guess-fix," and none of the above is yet proven.

## 3. What I changed / did NOT change

- Source tree: **unchanged** (clean HEAD `d343e2164`). The only code touched was a
  temporary `__ANDROID__`-gated FNV checksum log in `OceanTexture.cpp`, used solely
  to obtain the section-1 proof, then `git checkout`-reverted. libgk.so + the jak1
  debug APK were rebuilt clean afterward so the device matches HEAD.
- Did NOT touch: `goalc/emitter/IGenX86_64.*`, `title-obs.gc`, any CGO/DGO,
  `jak-original-v033`, `.autoport/gold/**`. No codegen edits.

## 4. Regression posture (device-verified, clean build)

Capture run `villwater_run.sh anim/diag` (ANDROID_SERIAL=eae4df44, full attract, no
input): sig11 = **0**, frame_max = **2400** (>=300), focus held on
`org.opengoal.gk.jak1` across all samples, intro to title to PRESS-START plays, ocean
buckets drawn (no skip), village terrain+shrub+TIE detail still render. No regression.

## 5. Artifacts (open these)

- Animation proof: the GWATER-ANIM-DIAG block in
  `.autoport/reports/village-water/villwater-routed-logcat-anim.log`.
- Before frames: `BEFORE-ocean-day-t070.png`, `BEFORE-ocean-dusk-t052.png`,
  `BEFORE-ocean-wide-burst-f08.png` (all in this dir).
- Consecutive burst (animation/camera test): `device-burst-f01.png` .. `f16.png`.
- Reference: `.autoport/reports/3tier/our-pc-01-attract-flythrough.png` (our x86, day),
  `.autoport/gold/TRUE-original-v033/01-attract-flythrough.png` (pristine, dusk).

## 6. Recommendation for the next phase (sunlight/specular)

Trace the ocean envmap and TOD lighting directly on device (libgk.so-only, no CGO):
log whether `CommonOceanRenderer`'s bucket-2 `m_envmap_tex` lookup hits a real
texture or the placeholder, and dump the light-group/specular values
`vu-lights<-light-group!` feeds the ocean vs the x86 oracle at a MATCHED day frame.
If the envmap is placeholder -> port the ocean envmap source; if the TOD light is
wrong -> that's the shared "sunlight" defect (likely also affects merc/tie envmap).
