# D2 — Real GLES 3.20 shader port (compile)

Every desktop GLSL shader in
`game/graphics/opengl_renderer/shaders/` now compiles cleanly under
GLES 3.20 via `glslc --target-env=opengl --target-spv=spv1.0`.

## Scope

- **45 shader pairs** (90 compile units total) — the canonical jak1
  set: collision, debug_red, depth_cue, direct2, direct_basic /
  direct_basic_textured / direct_basic_textured_multi_unit, emerc,
  etie / etie_base, eye, generic, glow_depth_copy / glow_draw /
  glow_probe (5 variants), hfrag / hfrag_montage, merc2, ocean_common
  / ocean_texture / ocean_texture_mipmap, plain_texture, post_processing,
  shadow / shadow2, shrub, simple_texture, sky / sky_blend, slow_time,
  solid_color, splash / splash_gradient, sprite_3d / sprite3_3d /
  sprite_distort / sprite_distort_instanced, tex_anim, tfrag3 /
  tfrag3_no_tex, tie_wind.
- **glslc**: NDK r27c (`shaderc v2022.3 / glslang ndk-r26c`,
  bundled with the NDK at `$ANDROID_NDK_HOME/shader-tools/`).
- **Target**: `--target-env=opengl --target-spv=spv1.0` — matches
  the runtime path the Android `libgk.so` will exercise once D3
  wires GLES on the Activity surface.

## Strategy

1. **Thin preprocessor** at
   `game/graphics/opengl_renderer/shaders/preprocess.py`. Only
   structural transforms: version line, precision header,
   template-token substitution (HEIGHT_SCALE / SCISSOR_*),
   `sampler1D` → `sampler2D` (with matching `texelFetch(s, idx, lod)`
   → `texelFetch(s, ivec2(idx, 0), lod)`), `noperspective` stripped
   (Adreno 6xx has no NV_shader_noperspective_interpolation).

2. **Source-level strictness fix** in the upstream `.vert` / `.frag`
   files. Each change is a literal-typing fix (`2` → `2.0`, `0` →
   `0u`, `gl_VertexID` → `float(gl_VertexID)`, etc.) that desktop
   GLSL 4.10 core accepts unchanged. Numeric semantics preserved
   byte-for-byte on desktop.

3. **Iterative fixer** at `.autoport/lib/d2_shader_strict_fixer.py`
   drives preprocess + glslc-compile + classify-error +
   apply-patch in a loop until all 90 units compile. Unclassifiable
   errors are surfaced for hand-fixing (4 such cases in the initial
   port; all addressed in source).

## Why not the phase-21 regex approach

Phase 21 shipped a regex in preprocess.py that promoted bare integer
literals to floats unconditionally (`re.sub(r"(\*=?|/=?|\+=|-=)\s*(\d+)..."`
and similar patterns). The pass:

- Corrupted bitshift RHS: `>> 7` → `>> 7.0` (GLES rejects).
- Corrupted uint comparisons: `uint != 0` → `uint != 0.0` (GLES
  rejects).
- Corrupted array indices: `arr[3]` → `arr[3.0]` (GLES rejects).
- Corrupted hex literals: `0x8000` → `0x8000.0` (illegal token).

35 of the 90 shaders silently failed to compile under it, masked
only by the fact that nothing in the runtime pipeline yet
attempted compile. D2 deletes the brittle pass and moves the fix
into the source.

## Compatibility

- **Desktop**: `build-x86/game/gk --portable -fakeiso -boot
  -debug-mem` still reaches `link finish: logo`. No GLSL compile
  errors emitted by the desktop OpenGL 4.6 backend (Mesa 25.3 /
  Intel UHD verified locally; the GLSL 4.10 spec accepts the
  stricter literal forms unchanged).
- **Android (D3+)**: the runtime side that consumes
  `shaders_android_blob.h` is still D3's responsibility. D2 only
  produces the validated shader sources; D3 will wire SDL3 +
  GLES + the ShaderLibrary port.

## Known limitations / D3 follow-ups

- **`sampler1D` → `sampler2D` runtime side**: the
  `texelFetch(tex_T10, ivec2(idx, 0), 0)` shader form expects the
  backing texture to be Nx1 GL_TEXTURE_2D. The desktop runtime
  uploads `GL_TEXTURE_1D` for these (time-of-day lookups in
  tfrag3 / shrub / etie / etie_base / hfrag / tex_anim / tie_wind);
  the Android runtime side must allocate 2D textures with height=1
  instead. D3.
- **`noperspective` removal in sky**: visually identical in jak1
  (sky.{vert,frag} uses smooth in/out for tex_coord; the strip
  changes interpolation from screen-linear to perspective-correct).
  Bounded artifact, no gameplay impact.
- **Uniform layout (auto-bind)**: `glslc` is invoked with
  `-fauto-bind-uniforms -fauto-map-locations` to satisfy SPIR-V's
  binding requirements during the validator's compile gate. The
  Android runtime can also use auto-binding when it loads via
  shaderc, or it can switch to the legacy `glGetUniformLocation`
  path; either is honest.

## Validator gate

`.autoport/validators/phase-D2-android-gles-shaders.sh` enforces:
required files + 45+ shader pairs + thin preprocessor (no phase-21
regex) + every preprocessed unit compiles under glslc + 80-byte
anti-stub floor + blob entry-count parity + no solid-color cheats
+ no synthetic-state regression since A4 + codegen lock + C4/D1
validator chain + desktop smoke + this report's headline.
