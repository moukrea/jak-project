#ifndef CGSC_MODEL_H
#define CGSC_MODEL_H
/*
 * perf-codegen-arm64-scalar test — reference models shared between the
 * host-side generator (gen.cpp, checks float->int against the real x86
 * cvttss2si) and the arm64 runner (runner.c, checks the emitted sequences
 * against these models on the device / under qemu). Plain C so both TUs can
 * include it verbatim.
 */
#include <stdint.h>
#include <string.h>

/* float -> int32, x86 cvttss2si semantics, sign-extended to int64.
 * NaN, +overflow/+Inf, -overflow/-Inf all saturate to INT32_MIN, matching
 * the x86 CVTTSS2SI oracle (see IGenARM64.cpp's float_to_int32_x86 comment). */
static inline int64_t model_f2i_bits(uint32_t bits) {
  float f;
  memcpy(&f, &bits, sizeof(f));
  if (f != f) {
    return (int64_t)(int32_t)0x80000000;
  }
  if (f >= 2147483648.0f || f < -2147483648.0f) {
    return (int64_t)(int32_t)0x80000000;
  }
  int32_t r = (int32_t)f;
  return (int64_t)r;
}

/* out[i] = in[(imm >> 2i) & 3], x86 SHUFPS dst,src,src,imm semantics. */
static inline void model_swizzle(const uint32_t in[4], uint8_t imm, uint32_t out[4]) {
  int i;
  for (i = 0; i < 4; i++) {
    out[i] = in[(imm >> (2 * i)) & 3];
  }
}

/* PSHUFLW (half=0, halfwords 0..3) / PSHUFHW (half=1, halfwords 4..7).
 * The other half of the 8 halfwords is copied unchanged. */
static inline void model_pshuf(const uint16_t in[8], uint8_t imm, int half, uint16_t out[8]) {
  int base = half * 4;
  int i;
  for (i = 0; i < 8; i++) {
    out[i] = in[i];
  }
  for (i = 0; i < 4; i++) {
    int sel = (imm >> (2 * i)) & 3;
    out[base + i] = in[base + sel];
  }
}

/* signed/unsigned 32-bit division and modulo: real x86 32-bit idiv/div
 * semantics, but applied to the low 32 bits of int64 inputs (a, b taken
 * modulo 2^32) and sign/zero-extended back to int64 on the way out, exactly
 * as int_div_w's SXTW does. INT32_MIN / -1 overflows on real x86 hardware
 * (#DE); the PS2 (and this emulation) instead renders INT32_MIN for the
 * quotient and 0 for the remainder, so those are the values these models
 * report for that case. */
static inline int64_t model_idiv32(int64_t a, int64_t b) {
  int32_t a32 = (int32_t)a;
  int32_t b32 = (int32_t)b;
  if (a32 == (int32_t)0x80000000 && b32 == -1) {
    return (int64_t)(int32_t)0x80000000;
  }
  return (int64_t)(int32_t)(a32 / b32);
}
static inline int64_t model_imod32(int64_t a, int64_t b) {
  int32_t a32 = (int32_t)a;
  int32_t b32 = (int32_t)b;
  if (a32 == (int32_t)0x80000000 && b32 == -1) {
    return 0;
  }
  return (int64_t)(int32_t)(a32 % b32);
}
static inline int64_t model_udiv32(int64_t a, int64_t b) {
  uint32_t a32 = (uint32_t)a;
  uint32_t b32 = (uint32_t)b;
  return (int64_t)(int32_t)(a32 / b32);
}
static inline int64_t model_umod32(int64_t a, int64_t b) {
  uint32_t a32 = (uint32_t)a;
  uint32_t b32 = (uint32_t)b;
  return (int64_t)(int32_t)(a32 % b32);
}

#endif /* CGSC_MODEL_H */
