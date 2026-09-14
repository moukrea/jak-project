#pragma once

#include <cstring>

#include "game/mips2c/mips2c_private.h"
#include "game/mips2c/vu_simd_state.h"

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#elif defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#endif

namespace Mips2C::vu_simd {

// Register storage remains entirely in ExecutionContext.
class VuSimd {
 public:
  VuSimd(ExecutionContext* context, Kernel kernel)
      : VuSimd(context, kernel, settings(kernel)) {}

  void vmul(DEST mask, int dest, int src0, int src1) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmul(mask, dest, src0, src1); });
  }

  void vadd(DEST mask, int dest, int src0, int src1) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vadd(mask, dest, src0, src1); });
  }

  void vsub(DEST mask, int dest, int src0, int src1) {
    apply<Op::Sub>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vsub(mask, dest, src0, src1); });
  }

  void vmul_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmul_bc(mask, bc, dest, src0, src1); });
  }

  void vadd_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vadd_bc(mask, bc, dest, src0, src1); });
  }

  void vsub_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Sub>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vsub_bc(mask, bc, dest, src0, src1); });
  }

  void vmula(DEST mask, int src0, int src1) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmula(mask, src0, src1); });
  }

  void vmula_bc(DEST mask, BC bc, int src0, int src1) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmula_bc(mask, bc, src0, src1); });
  }

  void vmula_q(DEST mask, int src) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vmula_q(mask, src); });
  }

  void vmulq(DEST mask, int dest, int src) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vmulq(mask, dest, src); });
  }

  void vaddq(DEST mask, int dest, int src) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vaddq(mask, dest, src); });
  }

  void vmove(DEST mask, int dest, int src) {
    apply<Op::Move>(mask, c_->vfs[dest].f, c_->vf_src(src), Mips2c_vf{},
                   [&] { c_->vmove(mask, dest, src); });
  }

  void vabs(DEST mask, int dest, int src) {
    apply<Op::Abs>(mask, c_->vfs[dest].f, c_->vf_src(src), Mips2c_vf{},
                   [&] { c_->vabs(mask, dest, src); });
  }

 private:
  enum class Op { Mul, Add, Sub, Move, Abs };

  VuSimd(ExecutionContext* context, Kernel kernel, Settings config)
      : c_(context), kernel_(kernel), vector_enabled_(config.vector_enabled), verify_(config.verify) {}

  static Mips2c_vf broadcast(float value) {
    Mips2c_vf result;
    for (auto& lane : result.f) {
      lane = value;
    }
    return result;
  }

  template <Op op, typename Scalar>
  void apply(DEST mask, float* destination, Mips2c_vf a, Mips2c_vf b, Scalar scalar) {
#if defined(__aarch64__) || defined(_M_ARM64) || defined(__SSE2__) || defined(_M_X64) || \
    (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
    if (!vector_enabled_) {
      scalar();
      return;
    }

    Mips2c_vf lane_mask;
    for (int lane = 0; lane < 4; ++lane) {
      const bool active = (static_cast<unsigned>(mask) & (1u << lane)) != 0;
      lane_mask.du32[lane] = active ? UINT32_MAX : 0;
      // Inactive lanes must not add FP exceptions (for example zero times infinity).
      a.du32[lane] &= lane_mask.du32[lane];
      b.du32[lane] &= lane_mask.du32[lane];
    }

    Mips2c_vf initial;
    std::memcpy(&initial, destination, sizeof(initial));
    Mips2c_vf result;
#if defined(__aarch64__) || defined(_M_ARM64)
    const auto av = vld1q_f32(a.f);
    const auto bv = vld1q_f32(b.f);
    if constexpr (op != Op::Move && op != Op::Abs) {
      // Masked lanes are zero; only active non-finite operands trigger fallback.
      const auto exponent = vdupq_n_u32(0x7f800000u);
      const auto nonfinite = vorrq_u32(
          vceqq_u32(vandq_u32(vreinterpretq_u32_f32(av), exponent), exponent),
          vceqq_u32(vandq_u32(vreinterpretq_u32_f32(bv), exponent), exponent));
      if (vmaxvq_u32(nonfinite) != 0) {
        scalar();
        return;
      }
    }
    float32x4_t value;
    if constexpr (op == Op::Mul) {
      value = vmulq_f32(av, bv);
    } else if constexpr (op == Op::Add) {
      value = vaddq_f32(av, bv);
    } else if constexpr (op == Op::Sub) {
      value = vsubq_f32(av, bv);
    } else if constexpr (op == Op::Abs) {
      value = vreinterpretq_f32_u32(vandq_u32(vreinterpretq_u32_f32(av), vdupq_n_u32(0x7fffffffu)));
    } else {
      value = av;
    }
    const auto merged = vbslq_u32(vld1q_u32(lane_mask.du32), vreinterpretq_u32_f32(value),
                                  vld1q_u32(initial.du32));
    vst1q_u32(result.du32, merged);
#else
    const auto av = _mm_loadu_ps(a.f);
    const auto bv = _mm_loadu_ps(b.f);
    if constexpr (op != Op::Move && op != Op::Abs) {
      const auto exponent = _mm_set1_epi32(0x7f800000);
      const auto nonfinite = _mm_or_si128(
          _mm_cmpeq_epi32(_mm_and_si128(_mm_castps_si128(av), exponent), exponent),
          _mm_cmpeq_epi32(_mm_and_si128(_mm_castps_si128(bv), exponent), exponent));
      if (_mm_movemask_ps(_mm_castsi128_ps(nonfinite)) != 0) {
        scalar();
        return;
      }
    }
    __m128 value;
    if constexpr (op == Op::Mul) {
      value = _mm_mul_ps(av, bv);
    } else if constexpr (op == Op::Add) {
      value = _mm_add_ps(av, bv);
    } else if constexpr (op == Op::Sub) {
      value = _mm_sub_ps(av, bv);
    } else if constexpr (op == Op::Abs) {
      value = _mm_and_ps(av, _mm_castsi128_ps(_mm_set1_epi32(0x7fffffff)));
    } else {
      value = av;
    }
    const auto maskv = _mm_loadu_ps(lane_mask.f);
    const auto merged = _mm_or_ps(_mm_and_ps(maskv, value),
                                  _mm_andnot_ps(maskv, _mm_loadu_ps(initial.f)));
    _mm_storeu_ps(result.f, merged);
#endif
    // No state has changed: aliases and vf0 still see the original sources.
    if (verify_) {
      scalar();
      Mips2c_vf reference;
      std::memcpy(&reference, destination, sizeof(reference));
      uint64_t defects = 0;
      for (int lane = 0; lane < 4; ++lane) {
        defects += reference.du32[lane] != result.du32[lane];
      }
      record(kernel_, 1, defects);
    }
    std::memcpy(destination, &result, sizeof(result));
#else
    scalar();
#endif
  }

  ExecutionContext* const c_;
  const Kernel kernel_;
  const bool vector_enabled_;
  const bool verify_;
};

}  // namespace Mips2C::vu_simd
