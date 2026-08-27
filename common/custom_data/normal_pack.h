#pragma once

// Gprecompute-deterministic-bake (owner 2026-08-26) — the 2-10-10-10 packing used for the per-vertex
// NORMAL (`PreloadedVertex::nor`) and, since this phase, for the per-vertex TANGENT baked into the fr3.
//
// These three helpers used to be file-static duplicates inside TFrag3Data.cpp. They are shared now
// because the tangent DERIVATION moved out of the load path into its own translation unit
// (TangentDerive.cpp, run offline by the fr3 extractor and by the PBR consolidation), while the load
// path in TFrag3Data.cpp only has to EXPAND what the fr3 already carries. Both sides must agree on the
// bits, so there is exactly one definition.

#include <algorithm>
#include <cmath>

#include "common/common_types.h"
#include "common/math/Vector.h"

namespace tfrag3 {

// Unpack a 2-10-10-10 GL normal (as written by pack_to_gl_normal: stored int = component * 511)
// back to a unit vector.
inline math::Vector3f unpack_gl_normal_2_10_10_10(u32 packed) {
  auto sext10 = [](u32 v) -> int {
    v &= 0x3ffu;
    return (v & 0x200u) ? (int)v - 1024 : (int)v;
  };
  math::Vector3f n((float)sext10(packed), (float)sext10(packed >> 10), (float)sext10(packed >> 20));
  float l = n.length();
  return l > 1e-6f ? n * (1.f / l) : math::Vector3f(0.f, 0.f, 0.f);
}

// The exact inverse of unpack_gl_normal_2_10_10_10 above, and bit-identical to
// MeshConsolidate.cpp's pack_nor(): stored int = round(component * 511), saturated to the signed
// 10-bit range.
inline u32 pack_gl_normal_2_10_10_10(const math::Vector3f& n) {
  auto sat = [](float f) -> u32 {
    int v = (int)std::lround(f * 511.f);
    v = std::max(-511, std::min(511, v));
    return (u32)v & 0x3ffu;
  };
  return sat(n.x()) | (sat(n.y()) << 10) | (sat(n.z()) << 20);
}

// Grecharged-pbr-realtime-fusion REOPEN#9 — Duff et al. 2017 branchless orthonormal basis: a CONTINUOUS
// tangent built purely from a unit normal, used to BACKFILL vertices whose UV-derived tangent is
// degenerate (degenerate/mirrored UV islands, or a missing smooth normal). The denominator magnitude
// stays in [1,2] so it is numerically stable for every normal. A continuous per-vertex tangent — even an
// arbitrary one — keeps the shader OFF the screen-space-derivative fallback, which is the proven source
// of the owner's hard triangular facets (per-triangle-constant, jumps at every edge).
inline math::Vector3f duff_tangent_from_normal(const math::Vector3f& n) {
  float s = n.z() >= 0.f ? 1.f : -1.f;
  float a = -1.f / (s + n.z());
  math::Vector3f t(1.f + s * n.x() * n.x() * a, s * n.x() * n.y() * a, -s * n.x());
  float l = t.length();
  return l > 1e-6f ? t * (1.f / l) : math::Vector3f(1.f, 0.f, 0.f);
}

// ------------------------------------------------------------------------------------------------
// THE BAKED TANGENT WORD — 2 BYTES, AND FINER THAN 4 WOULD HAVE BEEN.
//
// A tangent is not a free 3-vector. reconstruct_tfrag_tangents() Gram-Schmidts it against the vertex
// normal, so T is ALWAYS perpendicular to N, and its handedness is always exactly +1 or -1. The
// normal is already in the fr3 (PreloadedVertex::nor). So the only thing a tangent adds over the
// normal is ONE ANGLE in the plane perpendicular to N, plus one sign bit.
//
// Storing that angle instead of the vector is what keeps the bake affordable: 2 bytes per vertex
// instead of 4 (and instead of the 16 a math::Vector4f takes in RAM). On village1 that is the
// difference between +13 MB and +6.6 MB of fr3, and TIE is 91% of it — TIE tangents are per-INSTANCE
// (the derivation runs on world-space vertices) while TIE positions are per-PROTOTYPE, so the
// tangent stream is over three times the size of the tie vertex data it belongs to.
//
// 15 bits of angle is 0.011 deg — TEN TIMES FINER than the 0.11 deg a 10-10-10 packed vector would
// have given, because none of the bits are spent re-encoding a direction the normal already fixes.
//
// The basis is Duff's, built from the QUANTISED normal, so both sides (the offline bake and the
// load) derive it from the same 32-bit `nor` word and land on the same e1/e2. A vertex whose normal
// is degenerate (nor unpacks to the zero vector) is the one case the derivation answers without
// reference to N — it writes duff(0,1,0) with w=+1 — and both sides detect it from the same word.
constexpr u16 kTangentHandedNegBit16 = 0x8000u;
constexpr float kTangentAngleScale = 32768.f / 6.283185307179586f;  // 2^15 / 2pi

// The (e1, e2) frame the angle is measured in. Returns false when the normal is degenerate, which is
// the derivation's own "no usable smooth normal" case.
inline bool tangent_basis_from_packed_normal(u32 nor, math::Vector3f* e1, math::Vector3f* e2) {
  const math::Vector3f n = unpack_gl_normal_2_10_10_10(nor);
  if (n.length() < 0.5f) {
    return false;
  }
  *e1 = duff_tangent_from_normal(n);
  *e2 = n.cross(*e1);
  return true;
}

inline u16 pack_tangent_angle16(u32 nor, const math::Vector4f& t) {
  u16 out = (t.w() < 0.f) ? kTangentHandedNegBit16 : 0u;
  math::Vector3f e1, e2;
  if (!tangent_basis_from_packed_normal(nor, &e1, &e2)) {
    return out;  // degenerate normal: the tangent is a constant on both sides, no angle to store
  }
  const math::Vector3f T(t.x(), t.y(), t.z());
  float a = std::atan2(T.dot(e2), T.dot(e1));  // (-pi, pi]
  if (a < 0.f) {
    a += 6.283185307179586f;
  }
  int q = (int)std::lround(a * kTangentAngleScale) & 0x7fff;
  return (u16)(out | (u16)q);
}

inline math::Vector4f unpack_tangent_angle16(u32 nor, u16 p) {
  const float w = (p & kTangentHandedNegBit16) ? -1.f : 1.f;
  math::Vector3f e1, e2;
  if (!tangent_basis_from_packed_normal(nor, &e1, &e2)) {
    const math::Vector3f tb = duff_tangent_from_normal(math::Vector3f(0.f, 1.f, 0.f));
    return math::Vector4f(tb.x(), tb.y(), tb.z(), w);
  }
  const float a = (float)(p & 0x7fff) / kTangentAngleScale;
  const float c = std::cos(a), s = std::sin(a);
  const math::Vector3f T = e1 * c + e2 * s;
  return math::Vector4f(T.x(), T.y(), T.z(), w);
}

}  // namespace tfrag3
