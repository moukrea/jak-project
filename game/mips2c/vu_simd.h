#pragma once

#include <cstring>

#include "game/mips2c/mips2c_private.h"
#include "game/mips2c/vu_simd_state.h"

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#elif defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#endif

#if defined(_MSC_VER)
#define OG_VU_SIMD_INLINE __forceinline
#define OG_VU_SIMD_COLD __declspec(noinline)
#elif defined(__GNUC__) || defined(__clang__)
#define OG_VU_SIMD_INLINE inline __attribute__((always_inline))
#define OG_VU_SIMD_COLD __attribute__((noinline, cold))
#else
#define OG_VU_SIMD_INLINE inline
#define OG_VU_SIMD_COLD
#endif

namespace Mips2C::vu_simd {

// Register storage remains entirely in ExecutionContext.
class VuSimd {
 public:
  VuSimd(ExecutionContext* context, Kernel kernel)
      : VuSimd(context, kernel, settings(kernel)) {}

  OG_VU_SIMD_INLINE void vmul(DEST mask, int dest, int src0, int src1) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmul(mask, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vadd(DEST mask, int dest, int src0, int src1) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vadd(mask, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vsub(DEST mask, int dest, int src0, int src1) {
    apply<Op::Sub>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vsub(mask, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmul_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmul_bc(mask, bc, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vadd_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vadd_bc(mask, bc, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vsub_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Sub>(mask, c_->vfs[dest].f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vsub_bc(mask, bc, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmula(DEST mask, int src0, int src1) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmula(mask, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmula_bc(DEST mask, BC bc, int src0, int src1) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src0), broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmula_bc(mask, bc, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmula_q(DEST mask, int src) {
    apply<Op::Mul>(mask, c_->acc.f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vmula_q(mask, src); });
  }

  OG_VU_SIMD_INLINE void vmulq(DEST mask, int dest, int src) {
    apply<Op::Mul>(mask, c_->vfs[dest].f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vmulq(mask, dest, src); });
  }

  OG_VU_SIMD_INLINE void vaddq(DEST mask, int dest, int src) {
    apply<Op::Add>(mask, c_->vfs[dest].f, c_->vf_src(src), broadcast(c_->Q),
                   [&] { c_->vaddq(mask, dest, src); });
  }

  OG_VU_SIMD_INLINE void vmove(DEST mask, int dest, int src) {
    apply<Op::Move>(mask, c_->vfs[dest].f, c_->vf_src(src), Mips2c_vf{},
                   [&] { c_->vmove(mask, dest, src); });
  }

  OG_VU_SIMD_INLINE void vabs(DEST mask, int dest, int src) {
    apply<Op::Abs>(mask, c_->vfs[dest].f, c_->vf_src(src), Mips2c_vf{},
                   [&] { c_->vabs(mask, dest, src); });
  }

  // ── LA FAMILLE MULTIPLY-ADD ────────────────────────────────────────────────────────────
  // C'est l'operation VU dominante du produit matrice x vecteur (`vmulax / vmadday /
  // vmaddaz / vmaddw`), donc de `cspace<-parented-transformq-joint!`, la fonction mips2c la
  // plus appelee du jeu. Sans elle le comparateur ne voyait qu'une minorite des operations.
  //
  // DEUX ARRONDIS, PAS UN. L'oracle scalaire (`mips2c_private.h`) ecrit
  // `acc.f[i] += s0.f[i] * s1.f[bc]` : une multiplication ARRONDIE, puis une addition
  // ARRONDIE. Un `vfmaq_f32` n'en ferait qu'un seul et serait bit-different. Le bras
  // vectoriel garde donc `vmulq_f32` PUIS `vaddq_f32`, separes. La garantie ne tient que si
  // la TU qui inclut cet en-tete est compilee `-ffp-contract=off` (sinon clang refusionne les
  // deux intrinseques) : les cinq TU raccordees y sont, et l'objet arm64 livre le prouve par
  // un comptage `fmla|fmls|fmadd|fmsub|fnmadd|fnmsub` a zero. Si la garantie sautait, la
  // verification bit a bit de cet en-tete le dirait par `mips2c_bit_defects > 0` — jamais en
  // silence.
  OG_VU_SIMD_INLINE void vmadda_bc(DEST mask, BC bc, int src0, int src1) {
    apply<Op::Madd>(mask, c_->acc.f, c_->vf_src(src0),
                    broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                    [&] { c_->vmadda_bc(mask, bc, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmadda(DEST mask, int src0, int src1) {
    apply<Op::Madd>(mask, c_->acc.f, c_->vf_src(src0), c_->vf_src(src1),
                    [&] { c_->vmadda(mask, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmadd_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Madd>(mask, c_->vfs[dest].f, c_->vf_src(src0),
                    broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                    [&] { c_->vmadd_bc(mask, bc, dest, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmadd(DEST mask, int dest, int src0, int src1) {
    apply<Op::Madd>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                    [&] { c_->vmadd(mask, dest, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmsuba_bc(DEST mask, BC bc, int src0, int src1) {
    apply<Op::Msub>(mask, c_->acc.f, c_->vf_src(src0),
                    broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                    [&] { c_->vmsuba_bc(mask, bc, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmsuba(DEST mask, int src0, int src1) {
    apply<Op::Msub>(mask, c_->acc.f, c_->vf_src(src0), c_->vf_src(src1),
                    [&] { c_->vmsuba(mask, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmsub_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Msub>(mask, c_->vfs[dest].f, c_->vf_src(src0),
                    broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                    [&] { c_->vmsub_bc(mask, bc, dest, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmsub(DEST mask, int dest, int src0, int src1) {
    apply<Op::Msub>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                    [&] { c_->vmsub(mask, dest, src0, src1); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vmsubq(DEST mask, int dest, int src) {
    apply<Op::Msub>(mask, c_->vfs[dest].f, c_->vf_src(src), broadcast(c_->Q),
                    [&] { c_->vmsubq(mask, dest, src); }, acc_in());
  }

  OG_VU_SIMD_INLINE void vadda_bc(DEST mask, BC bc, int src0, int src1) {
    apply<Op::Add>(mask, c_->acc.f, c_->vf_src(src0),
                   broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vadda_bc(mask, bc, src0, src1); });
  }

  // ── MIN / MAX : COMPARER-PUIS-CHOISIR, JAMAIS `fmin`/`fmax` ───────────────────────────
  // L'oracle scalaire est `std::min(a, b)` = `b < a ? b : a`, et `std::max(a, b)` =
  // `a < b ? b : a`. `vminq_f32` (FMIN) ordonne les zeros signes : sur (+0, -0) il rend -0
  // la ou `std::min` rend +0 — bit-different, donc un defaut. On reproduit donc la selection
  // EXACTE du ternaire. Les entrees non finies partent au repli scalaire en amont.
  OG_VU_SIMD_INLINE void vmini(DEST mask, int dest, int src0, int src1) {
    apply<Op::Min>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmini(mask, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmax(DEST mask, int dest, int src0, int src1) {
    apply<Op::Max>(mask, c_->vfs[dest].f, c_->vf_src(src0), c_->vf_src(src1),
                   [&] { c_->vmax(mask, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmini_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Min>(mask, c_->vfs[dest].f, c_->vf_src(src0),
                   broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmini_bc(mask, bc, dest, src0, src1); });
  }

  OG_VU_SIMD_INLINE void vmax_bc(DEST mask, BC bc, int dest, int src0, int src1) {
    apply<Op::Max>(mask, c_->vfs[dest].f, c_->vf_src(src0),
                   broadcast(c_->vf_src(src1).f[static_cast<int>(bc)]),
                   [&] { c_->vmax_bc(mask, bc, dest, src0, src1); });
  }

 private:
  enum class Op { Mul, Add, Sub, Move, Abs, Madd, Msub, Min, Max };

  VuSimd(ExecutionContext* context, Kernel kernel, Settings config)
      : c_(context), kernel_(kernel), vector_enabled_(config.vector_enabled), verify_(config.verify) {}

  // L'accumulateur LU AVANT l'operation. `apply()` prend ses trois operandes par valeur :
  // l'oracle scalaire ecrit dans `c_->acc`, il ne doit pas pouvoir changer l'entree du bras
  // vectoriel sous lui.
  OG_VU_SIMD_INLINE Mips2c_vf acc_in() const {
    Mips2c_vf result;
    std::memcpy(&result, c_->acc.f, sizeof(result));
    return result;
  }

  static Mips2c_vf broadcast(float value) {
    Mips2c_vf result;
    for (auto& lane : result.f) {
      lane = value;
    }
    return result;
  }

  // `cc` est le troisieme operande : l'accumulateur d'entree des multiply-add. Il est en
  // dernier, avec une valeur par defaut, pour que les treize operations a deux operandes
  // gardent leur site d'appel inchange.
  template <Op op, typename Scalar>
  OG_VU_SIMD_INLINE void apply(DEST mask, float* destination, Mips2c_vf a, Mips2c_vf b,
                               Scalar scalar, Mips2c_vf cc = Mips2c_vf{}) {
    constexpr bool uses_acc = (op == Op::Madd || op == Op::Msub);
    constexpr bool checks_finite = (op != Op::Move && op != Op::Abs);
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
      if constexpr (uses_acc) {
        cc.du32[lane] &= lane_mask.du32[lane];
      }
    }

    Mips2c_vf initial;
    std::memcpy(&initial, destination, sizeof(initial));
    Mips2c_vf result;
#if defined(__aarch64__) || defined(_M_ARM64)
    const auto av = vld1q_f32(a.f);
    const auto bv = vld1q_f32(b.f);
    const auto cv = vld1q_f32(cc.f);
    if constexpr (checks_finite) {
      // Masked lanes are zero; only active non-finite operands trigger fallback.
      const auto exponent = vdupq_n_u32(0x7f800000u);
      auto nonfinite = vorrq_u32(
          vceqq_u32(vandq_u32(vreinterpretq_u32_f32(av), exponent), exponent),
          vceqq_u32(vandq_u32(vreinterpretq_u32_f32(bv), exponent), exponent));
      if constexpr (uses_acc) {
        // L'accumulateur est un operande LU : un acc non fini doit partir au repli comme
        // les deux autres, sinon la population comparee contiendrait un cas non couvert.
        nonfinite = vorrq_u32(
            nonfinite, vceqq_u32(vandq_u32(vreinterpretq_u32_f32(cv), exponent), exponent));
      }
      // PAS DE REDUCTION INTER-VOIES. `vmaxvq_u32` compile en `umaxv .4s`, une reduction
      // horizontale que le Cortex-A55 de l'appareil de preuve execute en plusieurs micro-ops
      // avant le transfert SIMD->GPR. Les voies de `nonfinite` valent 0 ou 0xFFFFFFFF : un OR
      // des deux moities 64 bits est non nul EXACTEMENT quand une voie est mise. Meme
      // predicat, meme repli, pas un flottant touche — un `orr` 64 bits (pleine cadence sur
      // A55) et UN SEUL `fmov` au lieu de la reduction.
      const uint32x2_t folded = vorr_u32(vget_low_u32(nonfinite), vget_high_u32(nonfinite));
      if (vget_lane_u64(vreinterpret_u64_u32(folded), 0) != 0) {
        if (verify_) {
          record_nonfinite(kernel_, 1);
        }
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
    } else if constexpr (op == Op::Madd) {
      value = vaddq_f32(cv, vmulq_f32(av, bv));
    } else if constexpr (op == Op::Msub) {
      value = vsubq_f32(cv, vmulq_f32(av, bv));
    } else if constexpr (op == Op::Min) {
      value = vbslq_f32(vcltq_f32(bv, av), bv, av);
    } else if constexpr (op == Op::Max) {
      value = vbslq_f32(vcltq_f32(av, bv), bv, av);
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
    const auto cv = _mm_loadu_ps(cc.f);
    if constexpr (checks_finite) {
      const auto exponent = _mm_set1_epi32(0x7f800000);
      auto nonfinite = _mm_or_si128(
          _mm_cmpeq_epi32(_mm_and_si128(_mm_castps_si128(av), exponent), exponent),
          _mm_cmpeq_epi32(_mm_and_si128(_mm_castps_si128(bv), exponent), exponent));
      if constexpr (uses_acc) {
        nonfinite = _mm_or_si128(
            nonfinite, _mm_cmpeq_epi32(_mm_and_si128(_mm_castps_si128(cv), exponent), exponent));
      }
      if (_mm_movemask_ps(_mm_castsi128_ps(nonfinite)) != 0) {
        if (verify_) {
          record_nonfinite(kernel_, 1);
        }
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
    } else if constexpr (op == Op::Madd) {
      value = _mm_add_ps(cv, _mm_mul_ps(av, bv));
    } else if constexpr (op == Op::Msub) {
      value = _mm_sub_ps(cv, _mm_mul_ps(av, bv));
    } else if constexpr (op == Op::Min) {
      // `b < a ? b : a`, comme `std::min` — pas `_mm_min_ps`, qui rend `b` sur une egalite
      // de zeros signes.
      const auto lt = _mm_cmplt_ps(bv, av);
      value = _mm_or_ps(_mm_and_ps(lt, bv), _mm_andnot_ps(lt, av));
    } else if constexpr (op == Op::Max) {
      const auto lt = _mm_cmplt_ps(av, bv);
      value = _mm_or_ps(_mm_and_ps(lt, bv), _mm_andnot_ps(lt, av));
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
      verify_result(destination, result, scalar);
    }
    std::memcpy(destination, &result, sizeof(result));
#else
    scalar();
#endif
  }

  // Keep the scalar oracle and accounting out of the delivered vector path.
  template <typename Scalar>
  OG_VU_SIMD_COLD void verify_result(float* destination, const Mips2c_vf& result, Scalar scalar) {
    scalar();
    Mips2c_vf reference;
    std::memcpy(&reference, destination, sizeof(reference));
    uint64_t defects = 0;
    for (int lane = 0; lane < 4; ++lane) {
      defects += reference.du32[lane] != result.du32[lane];
    }
    record(kernel_, 1, defects);
  }

  ExecutionContext* const c_;
  const Kernel kernel_;
  const bool vector_enabled_;
  const bool verify_;
};

}  // namespace Mips2C::vu_simd

#undef OG_VU_SIMD_INLINE
#undef OG_VU_SIMD_COLD
