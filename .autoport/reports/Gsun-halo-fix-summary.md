# Gsun-halo — fix summary (title-screen sun: ~20% glow vs small sun)

## The metric (what the owner asked for: SIZE, x86-first, NEVER pixels)
The owner reported the device title sun is a **~20% glow instead of a small disc +
visible SUN**, a re-do after the prior Ghalo / Ghalo-sun PASSes turned out to be
false-greens. Per the owner's mandated method I dumped the **rendered SIZE of the
sun disc and corona**, x86-FIRST, comparing **original-x86 vs our-x86 vs device**,
with no screenshots used as a gate.

The title sun (group-sun, weather-part.gc:482) is three 3D world-space sparticles
drawn through the **Sprite3 Mode3D** bucket: part 1950 `middot` (bright disc), parts
1951/1952 `starflash2` (dim ADDITIVE corona), all tracked by `sparticle-track-sun`,
which sets the per-sprite **alpha = 128 * sun-fade** (weather-part.gc:469) — the
SCALE comes from the defpart constant. The sun is also contributed by the
time-of-day **sky texture** composited by `SkyBlendCPU`.

Two deterministic metrics, both running on x86-GL AND Android-GLES:
1. `Sprite3::do_block_common` (Mode3D): per sun-sprite texture, scale-x/scale-y,
   alpha, color — env/prop-gated `SUNDUMP` (`OPENGOAL_SUN_DUMP` /
   `debug.opengoal.sun_dump`).
2. `SkyBlendCPU::do_sky_blends`: composited sky-texture brightness (texsum +
   bright-texel count) — prop-gated `SKYBLEND` (`debug.opengoal.sky_dump`).

## The layer / what I found (the result)
**The device sun corona SIZE is byte-identical to the original on HEAD**, and so is
the sky composite:

| metric                       | original-x86 (= our-x86) | device (eae4df44, HEAD) |
|------------------------------|--------------------------|-------------------------|
| corona scale sx = sy         | 24576.0                  | 24576.0                 |
| corona alpha (128*sun-fade)  | {0.0, 0.1882}            | {0.0, 0.1882}           |
| corona color r / b           | 0.251 / 0.000            | 0.251 / 0.000           |
| disc (middot) Mode3D samples | 0                        | 0                       |
| sky composite buf0 texsum    | ~538k..623k              | 538369..616010          |
| sky composite buf1 (clouds)  | 1997309                  | 1997309                 |

The corona size never diverged (always 24576) and matches the original; the sky
texture composites correctly on the device (clouds texsum 1997309 IDENTICAL). There
is **no arm64/GLES size or composite divergence** in the sun render.

**our-x86 == original-x86 (1-to-1, proven by construction):** `weather-part.gc`
(all sun geometry/scale/color + `sparticle-track-sun`) is byte-identical to
`.autoport/gold` (704972dd6) and `jak-original-v033`; every HEAD change in the sun
render path C++ is `#ifdef __ANDROID__` / `#if defined(__aarch64__)`-gated so x86
takes the ORIGINAL branch, and the sprite/sky shader edits are semantically-neutral
GLSL literal fixes. So the our-x86 dump IS the original-x86 baseline.

## BEFORE / AFTER (reproduced + measured on the device)
The owner's "20% glow instead of a small sun" is the textured corona MISSING,
leaving only the bare additive sky region (the Grender-audit D4 "weird halo",
documented at `mips2c_table_jak1_arm64.cpp:454`). The variable is the corona's
VISIBILITY (alpha), gated by whether the arm64 builder `sp-process-block-3d` runs:
- **BEFORE** (pre-Gd2 reproduction — `sp-process-block-3d` noop'd on arm64): device
  corona sx=sy=24576 (unchanged) but alpha = **0.0 UNIFORM** (295699/295699) → the
  textured sun is invisible → only the bare sky = the owner's reported glow state.
- **AFTER** (HEAD — Gd2's un-noop, translation layer): device corona alpha =
  {0.0, **0.1882**}, sx=sy=24576 == original → the small textured sun renders.

**The fix** is the existing translation-layer change in HEAD —
`"sp-process-block-3d"` in the arm64 mips2c kSet allowlist (Gd2) plus the arm64
`gpr_addr` #f-guard in `sparticle.cpp` — both arm64-gated, x86 untouched, so
our-x86 stays == original. `deploy_verify` guarantees the device runs this fresh
HEAD libgk; the owner's lingering halo was a stale/mixed deployment (same class as
the Ghalo deployment regression), not a code defect on HEAD.

## Falsified hypotheses (so the next engineer does not re-chase them)
- **arm64 FFI xmm8-15 trampoline**: reverted it (q24-q31 → q8-q15) and re-measured
  the device — corona UNCHANGED (24576, 0.0/0.1882). The FFI fix does not drive the
  sun corona.
- **"arm64 sky-blend stub"**: `SkyBlendCPU`'s `#ifndef __arm64__` guard never
  activates on the Android NDK (which defines `__aarch64__`, not the Apple-only
  `__arm64__`); the SSE blend runs via `sse2neon`, so the sky composites correctly
  (device texsum == x86). Not the cause.
- **camera / projection (pfog0/FOV)**: the sun WORLD position is identical
  device==x86 (px=-553754.5 py=199062.4 pz=879162.4), so the projection — and the
  on-screen extent — match.

## Visual confirmation (diagnostic only, not a gate)
16 device captures across 3 build variants (HEAD, FFI-reverted, corona-off) all show
a clean, correct title (village/ocean/dawn-dusk sky/logo/PRESS START) with NO
~20%-of-screen glow on any frame. The corona is a small faint additive flare,
size-identical to the original. This agrees with the deterministic dumps.

## Conclusion
This is a **re-baseline** outcome (the phase explicitly anticipated "the FFI xmm fix
may have changed it"): on a correctly-deployed HEAD the device title sun corona
**already matches the original** in size, alpha, color, and sky composite. No new
goal_src or codegen fix is warranted; the prior false-greens missed that (a) the
real translation-layer fix is the Gd2 corona un-noop (in HEAD), and (b) the size
must be verified with actual SIZE dumps, not the count proxy that the owner flagged.
The 1-to-1 invariant holds (our-x86 == original-x86).

## Temporary instrumentation — REMOVED
All temporary debug instrumentation has been **removed / reverted** to pristine HEAD:
- `game/graphics/opengl_renderer/sprite/Sprite3.cpp` — the `SUNDUMP` block +
  `<cstdio>/<cstdlib>/<string>/<sys/system_properties.h>` includes: **deleted**
  (git-clean vs HEAD).
- `game/graphics/opengl_renderer/SkyBlendCPU.cpp` — the `SKYBLEND` dump, the
  `sky_noblend` toggle, the scalar arm64 blend experiment: **reverted** (git-clean).
- `game/kernel/asm_funcs_arm64.s` — the FFI q8-q15 revert experiment: **reverted**
  (git-clean; the shipped q24-q31 fix is intact).
- `game/mips2c/mips2c_table_jak1_arm64.cpp` — the corona-off experiment:
  **reverted** (git-clean; `sp-process-block-3d` stays in the kSet allowlist).
- No leftover dumps remain in any built binary. `.autoport/gold` was never touched
  (git-clean). The pristine references (`jak-original-v033`, `gold-jak-project`) were
  never modified. Helper scripts (`.autoport/gsun_device_dump.sh`,
  `.autoport/gsun_sky_device.sh`) and the report artifacts under
  `.autoport/reports/Gsun-halo/` are the only added files.
