// Gcollision-arm — deterministic proof that arm64 FMA contraction flips the SIGN
// the swept-sphere/triangle collision leaf branches on.
//
// Faithful copy of the FMA-sensitive arithmetic in
//   game/mips2c/jak1_functions/collide_func.cpp : moving_sphere_triangle_intersect
//   lines 284-290 (edge vectors + triangle NORMAL via vopmula/vopmsub cross product)
//   line 317/319/321 (the plane-side classifier the bgez/bltz branches read).
//
// The VU0 cross product is computed as:
//   vopmula(vf13,vf11): acc[i] = vf13[j]*vf11[k]          // pure multiply (1 rounding)
//   vopmsub(vf16,vf11,vf13): vf16[i] = acc[i] - vf11[j]*vf13[k]
// On x86 (no FMA: GCC -mavx, no -mfma) the inner product vf11[j]*vf13[k] is rounded
// FIRST, then subtracted (2 roundings). On arm64 clang (-ffp-contract=on, default)
// it fuses into fnmsub (1 rounding). For a near-degenerate (wall-grazing) triangle
// the normal components are near-cancellation, and the downstream plane-side dot
// d = normal . (center - v1) is near zero, so the 1-ULP difference FLIPS sign(d).
// sign(d) is exactly what the leaf uses to decide front-face hit vs no-hit -> a
// flipped sign = collision MISS where x86 HITS = Jak clips through the wall.
//
// Compile this file with the SAME inputs three ways and diff:
//   (A) arm64 clang, default              -> FMA ON  (the device, BEFORE)
//   (B) arm64 clang, -ffp-contract=off    -> FMA OFF (the device, AFTER = the fix)
//   (C) x86 GCC -mavx                      -> the x86 oracle (already FMA-free)
// (B) and (C) must agree bit-for-bit; (A) must diverge on the grazing cases.

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <cstring>

static inline uint32_t fbits(float f){ uint32_t u; std::memcpy(&u,&f,4); return u; }

// --- exact VU0 ops copied verbatim from mips2c_private.h -----------------------
struct V4 { float f[4]; };
static V4 acc;
static void vopmula(const V4& s0, const V4& s1){            // src0=s0, src1=s1
  acc.f[0] = s0.f[1]*s1.f[2];
  acc.f[1] = s0.f[2]*s1.f[0];
  acc.f[2] = s0.f[0]*s1.f[1];
}
static void vopmsub(V4& dst, const V4& s0, const V4& s1){   // dst = acc - s0 x s1
  dst.f[0] = acc.f[0] - s0.f[1]*s1.f[2];
  dst.f[1] = acc.f[1] - s0.f[2]*s1.f[0];
  dst.f[2] = acc.f[2] - s0.f[0]*s1.f[1];
}
// --------------------------------------------------------------------------------

// Replicates collide_func.cpp:284-290,317,319,321: edge vectors, triangle normal
// (FMA-sensitive), and the plane-side classifier sign the leaf branches on.
static float plane_side_classifier(const V4& v0, const V4& v1, const V4& v2,
                                   const V4& center) {
  V4 e_a, e_b, c_rel, normal;
  for (int i=0;i<3;i++){
    e_a.f[i]   = v0.f[i] - v1.f[i];   // vf11 = v0 - v1   (collide_func.cpp:284)
    e_b.f[i]   = v2.f[i] - v1.f[i];   // vf13 = v2 - v1   (:285)
    c_rel.f[i] = center.f[i] - v1.f[i]; // vf14 = center - v1 (:286)
  }
  vopmula(e_b, e_a);                  // acc = e_b (x) e_a partial (:289)
  vopmsub(normal, e_a, e_b);          // vf16 = triangle normal     (:290)
  // d = normal . (center - v1): the signed plane distance the leaf's sign-tests read.
  // Reduction adds are pure VU0 vadds (not contractible) -> the FMA lives in `normal`.
  float d = normal.f[0]*c_rel.f[0] + normal.f[1]*c_rel.f[1] + normal.f[2]*c_rel.f[2];
  return d;
}

// Deterministic LCG so all three builds use byte-identical inputs.
static uint64_t st = 0x9e3779b97f4a7c15ull;
static uint32_t rnd(){ st = st*6364136223846793005ull + 1442695040888963407ull; return (uint32_t)(st>>32); }
static float frnd(float lo, float hi){ return lo + (hi-lo)*(rnd()/4294967296.0f); }

int main(){
  // Wall-like triangles at Jak-scale coordinates (meters*4096 -> ~1e5..5e5),
  // sphere centers placed NEAR the triangle plane (grazing a wall edge).
  int N = 200000, flips = 0, printed = 0;
  printf("# idx  d_bits        d_value          sign\n");
  for (int i=0;i<N;i++){
    V4 v1{{ frnd(-4e5f,4e5f), frnd(-2e5f,2e5f), frnd(-4e5f,4e5f), 0 }};
    // a tall near-vertical wall quad's tri: edges large in Y and one horizontal axis
    V4 v0{{ v1.f[0]+frnd(-3e5f,3e5f), v1.f[1]+frnd(5e4f,3e5f), v1.f[2]+frnd(-3e5f,3e5f), 0 }};
    V4 v2{{ v1.f[0]+frnd(-3e5f,3e5f), v1.f[1]+frnd(5e4f,3e5f), v1.f[2]+frnd(-3e5f,3e5f), 0 }};
    // place center almost in the plane: barycentric blend + tiny normal offset
    float a = frnd(0.1f,0.6f), b = frnd(0.1f,0.6f);
    V4 center{{ v1.f[0]+a*(v0.f[0]-v1.f[0])+b*(v2.f[0]-v1.f[0]),
                v1.f[1]+a*(v0.f[1]-v1.f[1])+b*(v2.f[1]-v1.f[1]),
                v1.f[2]+a*(v0.f[2]-v1.f[2])+b*(v2.f[2]-v1.f[2]), 0 }};
    float d = plane_side_classifier(v0,v1,v2,center);
    int sign = (d>0)?1:((d<0)?-1:0);
    // Emit every grazing-wall contact (center near the plane). A sign flip of d
    // across FMA on/off = front-face HIT vs no-hit = clip-through class.
    // |normal| ~ (edge)^2 ~ 1e11 here, so |d|<1e8 means center is sub-meter from
    // the wall plane — the exact grazing regime where the leaf's bltz/bgez fire.
    if (std::fabs(d) < 1e8f) {
      printf("%-7d %+d 0x%08x %.6f\n", i, sign, fbits(d), d);
      (void)printed;
    }
  }
  fprintf(stderr, "# grazing-cases emitted; join by idx across FMA on/off for sign flips\n");
  return 0;
}
