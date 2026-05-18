# Phase 07 — SIMD: SSE/AVX → NEON

## Goal

Translate SSE/AVX intrinsics throughout `game/graphics/` and `goalc/emitter/` SIMD codegen to ARM NEON. Validator: `simd` diff-tests pass; renderer cross-compiles cleanly.

## Scope and key constraint

**NEON is 128-bit only.** Any 256-bit AVX op must be split into two NEON ops with paired registers. There is no AVX2 equivalent in baseline AArch64; SVE/SVE2 are not in scope for this port (broad device support requires NEON-only).

Per-area work:

1. **Auto-translatable patterns** (do these first, mechanically):
   - `_mm_add_ps` → `vaddq_f32`
   - `_mm_mul_ps` → `vmulq_f32`
   - `_mm_load_ps` → `vld1q_f32`
   - `_mm_store_ps` → `vst1q_f32`
   - `_mm_shuffle_ps` → `vextq_f32` + permutations (no direct equivalent; case-by-case)
   - SSE comparison ops → NEON `vceqq_*`, `vcgtq_*`, etc., **but** SSE returns -1 / 0 lanes for true/false matching x86; NEON does the same — verify.

2. **AVX 256-bit** (in renderer's PS2 VU emulator most likely):
   - Each `__m256` becomes a `float32x4x2_t` (pair of NEON regs) or two separate `float32x4_t`
   - Loop unroll across the pair

3. **goalc SIMD codegen** (in IGen_arm64.cpp): mirror the SSE intrinsics IGen.cpp exposes.

## Approach

1. Read every file under `game/graphics/` and grep for `_mm_` and `_mm256_`.
2. Read `goalc/emitter/IGen.cpp` for the SIMD section (vector add, mul, shuffle, dot product, etc.).
3. Build a translation table as `goalc/emitter/sse_to_neon.md` documenting every mapping you used.
4. Wrap the SSE intrinsics in a header `common/util/simd_compat.h` that `#ifdef`s between x86 SSE and a NEON polyfill. This is cleaner than scattering `#ifdef`s through call sites.

## Pitfalls

- Float-int reinterpret bit patterns: NEON's `vreinterpretq_*` macros do the same as `_mm_castps_si128`. Use them.
- Saturating arithmetic: NEON has `vqaddq_*` etc. that the renderer may not use; verify before assuming.
- Horizontal ops (`_mm_hadd_ps`): NEON has `vpaddq_f32` (pairwise add) which is similar but different. Read the docs carefully.
- Memory alignment: NEON loads have alignment hints but don't fault on misalignment by default. Match x86 semantics.

## Success

```bash
cmake --build build-arm64
ctest -L simd --output-on-failure
ctest --output-on-failure  # full regression
```

The validator additionally greps the codebase for stray `_mm_`/`_mm256_` outside the simd_compat.h header — those are unported and must not exist.
