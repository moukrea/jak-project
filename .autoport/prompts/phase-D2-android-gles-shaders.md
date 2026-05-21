# Phase D2 — Real GLES shader port: every upstream shader translated and compiles

## What this phase delivers

Every desktop GLSL shader under
`game/graphics/opengl_renderer/shaders/` is translated into a GLES
3.20 variant that:

1. **Compiles cleanly** under `glslc --target-env=opengl
   --target-spv=spv1.0` (NDK r27c — the same shader compiler the
   Android build pipeline will invoke at runtime).
2. **Preserves the numeric behavior** of the desktop original. The
   transformations are limited to (a) version line + precision
   qualifiers, (b) `sampler1D` → `sampler2D` with adjusted
   `texelFetch` call sites, (c) `noperspective` qualifier removed
   (Adreno 6xx does not expose the corresponding extension on GLES
   3.20). Everything else is a literal-typing fix in the upstream
   source — `pow(x, 2)` → `pow(x, 2.0)`, `uint == 0` → `uint == 0u`,
   etc. — that GLSL 4.10 core also accepts unchanged, so the desktop
   build is byte-identical in behavior.
3. **Lives in the upstream sources** — there is no parallel
   `gles/` tree. The desktop `.vert` / `.frag` files are the single
   source of truth, both for the desktop renderer (`build-x86/game/gk`)
   and for the Android preprocessing pipeline.

After D2: `python3 game/graphics/opengl_renderer/shaders/preprocess.py
<src> <out>` produces 45 shader pairs + a `shaders_android_blob.h`
header, and every one of the 90 output files compiles under the NDK's
GLES 3.20 shader compiler. The Android runtime still doesn't load
them — that's D3's job (SDL3 surface bring-up + ShaderLibrary port).
D2 is the shader *production* side; D3 is the consumption side.

## Why this matters

Phase 21 (`21-gles-shaders`) attempted this work earlier and shipped
a regex-based int→float promotion pass inside `preprocess.py`. The
phase 21 pass was unsound: it promoted bare integer literals to
floats unconditionally, which corrupted the RHS of bitshift operators
(`>> 7` became `>> 7.0`), uint comparison literals (`uint != 0`
became `uint != 0.0`), and array-index expressions. At least 35 of
the 90 shaders silently failed to compile, masked only by the fact
that no runtime code yet attempted to compile them. The supervisor
audit on 2026-05-20 listed "phase 21 cheat: synthetic shader stand-in"
as one of the unresolved tech-debt items rolled forward into bucket D.

D2 fixes phase 21 honestly:

1. The preprocessor is reduced to structural transforms only
   (version line, precision header, sampler1D rewrite, noperspective
   strip, template token substitution). No type-coercion regexes.
2. The upstream shaders are edited to be GLES-clean at the source
   level. Every change is a literal-suffix change (`2` → `2.0`, `0`
   → `0u`, `gl_VertexID` → `float(gl_VertexID)`, etc.) that desktop
   GLSL 4.10 accepts unchanged.
3. A host-side strict fixer at `.autoport/lib/d2_shader_strict_fixer.py`
   drives the workflow: it preprocesses, compiles, classifies
   glslc's errors, and applies minimal patches to the upstream
   sources. Anything it can't classify is left for hand-fixing.
4. The D2 validator demands that **every shader pair compiles
   under glslc**, that the **shader count matches the expected 45
   pairs**, that the **desktop gk still reaches `link finish:
   logo`** (no desktop-side regression), and that the **C4 + D1
   bucket-C/D invariants** still hold.

## Engineering background (from C4/D1 tail state)

D1 produced a Bionic-linked `gk` executable at
`build-arm64-android/game/android-arm64/gk` (21 MB, all required
GOAL kernel symbols defined, no `__attribute__((weak))`, dynamic
interpreter `/system/bin/linker64`). That binary doesn't yet wire
SDL3 / GLES / Activity / audio — D1's `main()` is a banner-and-exit
at exit code 2.

D2 does NOT touch:

- The Bionic shim layer in `game/android-arm64/`.
- The aarch64 codegen / classifier files (locked since A4).
- The runtime linker `klink.cpp` (locked since C4).
- The `android/` Activity build's libgk.so plumbing — D2 only
  modifies the *shader source* side. The CMakeLists hook that runs
  `preprocess.py` and generates `shaders_android_blob.h` already
  exists from phase 21 and is preserved unchanged.

What D2 *does* touch:

- `game/graphics/opengl_renderer/shaders/preprocess.py` — rewritten
  to do only structural transforms.
- The 45 upstream `.vert` / `.frag` files under
  `game/graphics/opengl_renderer/shaders/` — each one edited to be
  GLES-clean at the source. Every edit is a literal-typing change
  that desktop GLSL 4.10 accepts unchanged.
- `.autoport/lib/d2_shader_strict_fixer.py` — the host-side
  iterative fixer that drives the patching workflow. New helper.
- `.autoport/reports/D2-shaders.md` — the headline report.

## Concrete deliverables

### 1. Rewritten preprocess.py

Replace `game/graphics/opengl_renderer/shaders/preprocess.py` with a
version that does only structural transforms:

1. Strip leading content before `#version` (GLES requires `#version`
   to be the literal first non-whitespace content; desktop GLSL is
   permissive). This is needed for `debug_red.vert` and any future
   shader that gains a header comment.
2. Replace the `#version 410 core` line with the GLES 3.20 header
   (`#version 320 es` + the seven `precision highp ...` qualifiers).
3. Substitute jak1's `HEIGHT_SCALE` / `SCISSOR_HEIGHT` /
   `SCISSOR_ADJUST` template tokens (mirroring Shader.cpp's runtime
   regex_replace path).
4. Rewrite `uniform sampler1D <name>;` to
   `uniform sampler2D <name>;` and adjust every matching
   `texelFetch(<name>, idx, lod)` call to
   `texelFetch(<name>, ivec2(idx, 0), lod)`. This is the only honest
   GLES port for the time-of-day 1D lookup textures (`tex_T10`):
   GLES has no `GL_TEXTURE_1D`, so the runtime side (D3) will need
   to upload the texture as an Nx1 GL_TEXTURE_2D; in the shader
   side, indexing by `ivec2(idx, 0)` is the standard portable form.
5. Strip `noperspective` qualifier — required by GLES core (Adreno
   6xx does not expose `NV_shader_noperspective_interpolation`).
   Falls back to smooth perspective-correct interpolation, which is
   visually identical for everything except sky.{vert,frag}'s
   tex_coord and even there is bounded by the sky UV range.

**Anti-cheat**: the preprocessor must NOT contain ANY regex that
promotes bare integer literals to floats or appends `u` to integer
literals. Phase 21's such pass corrupted ~35 shaders; the fix lives
in the upstream sources, not in a brittle pass over them.

### 2. Source edits to the 45 shader pairs

Every desktop `.vert` / `.frag` under
`game/graphics/opengl_renderer/shaders/` is edited as needed to be
GLES-clean. Examples (incomplete — see git diff for the full set):

- `pow(cam_dot, 2)` → `pow(cam_dot, 2.0)` (collision.vert and
  several others)
- `uint != 0` → `uint != 0u` (logtest implementations,
  direct2.frag's mode-bit comparisons, etc.)
- `1 << uint_expr` → `1u << uint_expr` (collision.vert's pat-mask
  checks)
- `(8388608)` divisor → `(8388608.0)` (collision.vert,
  sprite3_3d.vert)
- `255 - clamp(...)` (float context) → `255.0 - clamp(...)`
  (tfrag3.vert, hfrag.vert, etie.vert, etc.)
- `mod(gl_VertexID, 5.0)` → `mod(float(gl_VertexID), 5.0)`
  (sprite_distort_instanced.vert)
- `fog = 255u - byte_info.z;` (float = uint) →
  `fog = float(255u - byte_info.z);` (direct2.vert,
  ocean_common.vert)
- `(position_in.x - 0x8000) / 0x1000` → `(position_in.x -
  float(0x8000)) / float(0x1000)` (direct2.vert — hex int
  literals in float math)
- `32768.f * vx` where vx is int → `32768.f * float(vx)`
  (hfrag.vert)

Every change is a literal-typing fix; numeric semantics are
preserved. Desktop GLSL 4.10 accepts all of these forms unchanged,
so the desktop `gk` binary still compiles every shader.

### 3. .autoport/lib/d2_shader_strict_fixer.py

A host-side iterative fixer:

1. Run preprocess.py on every shader pair.
2. Compile each preprocessed shader with `glslc --target-env=opengl
   --target-spv=spv1.0`.
3. For each compile error, classify it (`int_to_float`,
   `uint_op_int`, `int_to_float` via pow/mod/clamp overload misses)
   and apply a minimal patch to the *upstream* `.vert` / `.frag`.
4. Iterate until no errors or no progress is made.

The fixer's patch functions are pinned to a narrow set of
transforms; anything it can't classify is surfaced in the output
for hand-fixing. The bitwise / array-index / declaration contexts
are explicitly excluded via skip-spans to prevent phase 21's
overshoot.

This file is committed so the build process is reproducible if a
future shader edit reintroduces a strictness regression.

### 4. .autoport/reports/D2-shaders.md

A short headline file describing what was wired:

- Total shader pairs (45) + total compile units (90)
- Strategy: upstream source clean + thin preprocessor + iterative
  fixer
- Compatibility: desktop GL 4.6 (build-x86/game/gk) unchanged;
  GLES 3.20 clean
- Known limitations: D2 produces the shader source variants; D3
  must wire the runtime side (1D texture upload as 2D, ShaderLibrary
  port to use GLES blob).

The validator greps the report for "GLES 3.20" + "compile" in the
first non-blank lines.

## Anti-cheats (validator enforces these)

1. **Required files exist** — `preprocess.py` (the simplified one),
   `.autoport/lib/d2_shader_strict_fixer.py`,
   `.autoport/reports/D2-shaders.md`.
2. **The shader source directory has at least 45 pairs** —
   anti-empty-dir cheat (a "no shaders to compile" pass is not a
   pass).
3. **preprocess.py contains no int→float regex** — anti-phase-21
   cheat. The validator greps preprocess.py for known phase-21
   patterns and rejects them.
4. **Every shader pair compiles under glslc** — the strict
   compile gate. `glslc --target-env=opengl --target-spv=spv1.0`
   on every `.android.vert` / `.android.frag` from the preprocessor
   output. Anti-stub: a shader pair where the .vert or .frag file
   is < 80 bytes (the minimum honest GLES 3.20 boilerplate) is
   rejected as a solid-color stub.
5. **The blob header has the expected count** — `kShaderCount`
   must equal the number of pairs discovered by the preprocessor.
6. **No solid-color cheat shaders** — anti-phase-29 cheat. The
   validator greps every desktop `.frag` for the exact pattern
   `gl_FragColor = vec4(<R>, <G>, <B>, <A>);` with constant
   literals (i.e., a shader that ignores its inputs and emits a
   single color). If a .frag matches this pattern AND its size is
   below 200 bytes, it's flagged as a solid-color cheat.
7. **No `__attribute__((weak))` or kStateSeq introduced since A4** —
   bucket-D inherited forbidden-pattern set, applied to the diff
   since A4. (D2 shouldn't touch any C++ code, but the
   defense-in-depth grep stays on.)
8. **Codegen + classifier files byte-identical to A4** — same
   lock as D1.
9. **C4 + D1 bucket invariants still hold** — re-run C4 and D1
   validators; both must exit 0.
10. **Desktop gk smoke test still passes** — `build-x86/game/gk
    --portable -fakeiso -boot -debug-mem` must reach `link
    finish: logo` within 60s. This is the existing smoke gate
    inherited verbatim from C1/D1.
11. **D2-shaders.md headline present** — first 20 non-blank lines
    of the report mention "GLES 3.20" and "compile".

## Don't

- **Do NOT reintroduce the phase-21 int→float regex** in
  preprocess.py. The validator greps for it.
- **Do NOT touch the codegen or classifier files** (locked since
  A4).
- **Do NOT modify `klink.cpp`** or any runtime linker code (locked
  since C4).
- **Do NOT modify `game/android-arm64/`** (locked since D1).
- **Do NOT introduce a parallel `gles/` shader tree** — single
  source of truth in the desktop `.vert` / `.frag` files.
- **Do NOT write solid-color stand-in shaders** to make the
  compile gate pass — phase 29's cheat, explicitly forbidden by
  anti-cheat 6.
- **Do NOT modify the validator to loosen any check.** The C2/D1
  pattern of strict floors stays.

## Success

`bash .autoport/validators/phase-D2-android-gles-shaders.sh` exits
0. All 90 shader compile units (45 pairs) translate cleanly under
glslc --target-env=opengl, the blob header reflects the count, the
desktop renderer still works, and the bucket-C/D chain is intact.
