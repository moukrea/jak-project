# village-water — ocean specular/reflection investigation (DIAGNOSIS ONLY)

Outcome: **DIAGNOSIS ONLY — no fix shipped, by design.** All four ranked
GLES-specific ocean hypotheses are **FALSIFIED with hard on-device runtime
evidence**. The Android GLES ocean render path (envmap pass, FBO format,
shaders, GL calls) is correct and bit-for-bit faithful to the shared desktop
renderer. The residual "flatter than the original" look traces to the VU /
time-of-day surface-shading INPUTS (the ocean-texture reflection-alpha caps low
and the color variation is subtle teal-on-teal) — that is upstream of the
renderer (shared C++ VU emulation + GOAL light data), not a GLES degradation.
Per the mandate ("pin first, no guess-fix; if it needs goalc/codegen STOP and
report"), nothing was shipped. The tree is left at clean HEAD and the device APK
was rebuilt clean.

## Method
Read the full ocean renderer family + how `android/android_opengl_renderer.cpp`
wires the OCEAN buckets, diffed the effective Android path vs the shared desktop
code, then added TEMPORARY `__ANDROID__`-gated diagnostics (envmap tex resolve,
FBO dst-alpha readback, ocean-texture color/alpha range, VU constants), captured
on device (`ANDROID_SERIAL=eae4df44`), and REVERTED all diagnostics before the
final clean build. Logs: `villwater-routed-logcat-oceandiag{,2,3,4}.log`.

## The four ranked hypotheses — each FALSIFIED on device

### H1 — CommonOceanRenderer envmap/reflection pass missing/placeholder. FALSE.
`flush_mid` bucket 1 (the title-flythrough distant ocean reflection) runs every
frame with a REAL envmap texture and real geometry:
```
OCEANDIAG-MID envmap_tbp=10026 lookup_hit=1 placeholder=1 idx0=2121 idx1=841 ...
```
`lookup_hit=1` (envmap tbp 10026 resolves to a real loaded texture, NOT the
placeholder id=1); `idx1=841` envmap-pass indices are drawn. The reflection pass
is active and textured.

### H2 — Ocean render-to-texture FBO wrong/incomplete/no-alpha on GLES. FALSE.
`opengl_utils.cpp` already substitutes `GL_UNSIGNED_INT_8_8_8_8_REV ->
GL_UNSIGNED_BYTE` on Android (A35/A36 fix) and the FBO is `GL_RGBA` /
framebuffer-complete. The dst-alpha that gates the `GL_DST_ALPHA` envmap blend is
present and high, and the produced ocean texture carries real, varying alpha:
```
OCEANDIAG-MID ... dst_alpha_max=255 center=91afcc30   (FBO has dst alpha; center px = teal 0x91afcc, a=0x30)
OCEANDIAG-TEX mipmaps=0/1 R[94-126] G[186-246] B[180-234] A[4-62]   (ocean tex: shaded color variation + reflection-alpha present)
```

### H3 — Ocean shaders dropped specular/envmap under GLES preprocess. FALSE.
The GLES blob (`build-android/shaders/shaders_android_blob.h`, entries
`ocean_common` / `ocean_texture` / `ocean_texture_mipmap`) is byte-faithful to
the desktop `shaders/ocean_*.{vert,frag}`: bucket 2/4 (`color = fragment_color *
T0`) reflection path, the `bucket==4` alpha-zero trick, and the mipmap
`tex.w *= alpha_intensity` all survive intact. All shaders compile
(`A35-RENDER all ... shaders compiled`), no ocean shader in the failed list.

### H4 — Ocean-specific desktop-GL call NULL/no-op in the Android glad loader. FALSE.
The only ocean GL hazard (settable `glPrimitiveRestartIndex`, NULL on GLES) was
already fixed in commit `abb7c1237` with the
`GL_PRIMITIVE_RESTART_FIXED_INDEX` gate in `flush_near`/`flush_mid`/`OceanTexture::flush`.
No `A35-RENDER skip bucket=ocean*`, no SIGILL, no crash; all four ocean mips2c
builders bind `A37-MIPS2C-REAL`.

## What the evidence positively shows
The VU emulation that bakes the ocean surface (specular reflect term `vf27`,
color-out `cout*`) runs identical portable float C++ (`OceanTexture_PC.cpp`,
`run_L3_PC`) on x86 and arm64, fed identical canonical constants on device:
```
OCEANDIAG-CONST cam_nrm=(0.000 0.000 1.000 0.000) constants=(0.500 0.500 0.000 0.000) offsets=(4.000 8.000 12.000 16.000)
```
These are the stock ocean texture constants — no arm64 corruption of the
reflection/lighting inputs. So the ocean texture the engine produces on the
device (color R94-126/G186-246/B180-234, reflection-alpha A4-62) is the FAITHFUL
engine output, and it is composited through a verified-correct envmap+blend path.

## Why it still looks "flatter" than the original (honest residual)
- The reflection-intensity alpha baked into the ocean texture caps around
  ~62/255 (~24%), and the surface color variation is subtle teal-on-teal — so
  the additive envmap sky/sun glint is genuinely faint here. This is the engine's
  own output, not a GLES bug; desktop renders the identical data the same way.
- The title attract camera is HIGH and always moving, and the attract cycles
  day->dusk; several reference frames are dusk (muted water). A true side-by-side
  needs a frame-matched day moment between device and a freshly-run x86/pristine
  oracle — which is X-auth-walled (skipped per mandate).
- If the owner still wants brighter glint, the lever is UPSTREAM and SHARED, not
  the GLES renderer: the time-of-day light group / specular scale fed to the
  ocean surface (the `cam_nrm`/`constants` source in GOAL `ocean*.gc` and the
  TOD context), or a deliberate non-faithful renderer boost. Both are out of
  scope for "fix the GLES degradation" (there is none) and the latter would
  diverge from desktop, so neither was done.

## What I changed / did NOT change
- Source tree: **unchanged** (clean HEAD). Only temporary `__ANDROID__`-gated
  `fprintf(stderr, "OCEANDIAG-*")` probes in `CommonOceanRenderer.cpp`,
  `OceanTexture_PC.cpp`, `OceanTexture.cpp` — all `git checkout`-reverted. The
  `#else`/desktop path was never touched. libgk.so + the jak1 debug APK were
  rebuilt clean afterward; device matches HEAD.
- Did NOT touch: `goalc/emitter/IGenX86_64.*`, any CGO/DGO, `goal_src/`,
  `jak-original-v033`, `.autoport/gold/**`. No codegen edits.

## Regression posture (device-verified, clean build)
Final capture `villwater_run.sh cleanverify` (ANDROID_SERIAL=eae4df44, full
attract, no input): **sig11=0**, **frame_max=2340** (>=300), tris_max=617003,
focus held on `org.opengoal.gk.jak1` for all 25 samples, intro/title/PRESS-START
plays, ocean buckets drawn (no skip), village terrain+shrub+TIE detail render.
Zero `OCEANDIAG` lines in the clean log (diagnostics fully removed). No regression.

## Artifacts (open these)
- Before (flat-looking day ocean): `BEFORE-ocean-day-t070.png`,
  `BEFORE-ocean-wide-burst-f08.png`.
- After / clean (unchanged, day ocean): `AFTER-ocean-day-cleanverify-t052.png`,
  `AFTER-ocean-day-cleanverify-t070.png` (identical look — no fix shipped).
- Evidence logs: `villwater-routed-logcat-oceandiag{,2,3,4}.log`
  (`OCEANDIAG-MID` / `OCEANDIAG-TEX` / `OCEANDIAG-CONST` lines).
- References: `.autoport/reports/3tier/our-pc-01-attract-flythrough.png` (x86,
  day), `.autoport/gold/TRUE-original-v033/01-attract-flythrough.png` (pristine,
  dusk).

## Recommendation for next phase
The GLES ocean renderer is exonerated. If the water glint must be pushed closer
to the owner's memory of the original, the next phase should be an UPSTREAM /
oracle-diff phase on the ocean's time-of-day light group + specular scale
(GOAL/VU input side), captured at a frame-matched DAY moment against a freshly
run x86 oracle — NOT a GLES renderer change.
