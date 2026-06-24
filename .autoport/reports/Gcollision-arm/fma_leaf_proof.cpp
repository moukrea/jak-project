// Gcollision-arm — DEFINITIVE proof using the REAL collision leaf.
// Includes mips2c_private.h (the exact ExecutionContext + VU0 op implementations the
// game uses) and runs the verbatim body of
//   game/mips2c/jak1_functions/collide_func.cpp : moving_sphere_triangle_intersect
// (the swept-sphere/triangle test that both the wall push-out AND the can-exit-duck?
// head-probe bottom out in). We sweep a sphere toward a vertical wall and print the
// RETURN value per step: a hit returns the swept fraction u in [0,1]; a miss returns
// the sentinel -100000000.0 (0xCCCEBC20). Compile FMA-on (device default) vs
// -ffp-contract=off (the fix == x86) and diff: the band of sphere positions where
// FMA-on says MISS while FMA-off/x86 says HIT is exactly "Jak clips through the wall".
#include "game/mips2c/mips2c_private.h"
#include <cstdio>
#include <cstring>

using namespace Mips2C;
u8* g_ee_main_mem = nullptr;  // provide the EE memory the loads/stores use
// stubs for the mips2c ld/st OOB tripwire (not relevant to the arithmetic under test)
#include <atomic>
std::atomic<bool> g_gnd_oob_armed{false};
void gnd_oob_report(char, unsigned int, unsigned long long, unsigned long long, int) {}

namespace { struct CacheT { void* collide_do_primitives; } cache; }
static unsigned DBG[8];  // localization probes (raw float bits)
static inline unsigned fb(float f){ unsigned u; std::memcpy(&u,&f,4); return u; }

// ---- verbatim body of moving_sphere_triangle_intersect::execute --------------
static u64 leaf_execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 call_addr = 0;
  c->daddiu(sp, sp, -16);
  c->sd(ra, 0, sp);
  c->lqc2(vf14, 0, a0);
  c->lqc2(vf15, 0, a1);
  c->lqc2(vf11, 0, a3);
  c->lqc2(vf12, 16, a3);
  c->lqc2(vf13, 32, a3);
  c->mov128_vf_gpr(vf1, a2);
  c->vadd(DEST::xyzw, vf6, vf14, vf15);
  c->vsub(DEST::xyzw, vf11, vf11, vf12);
  c->vsub(DEST::xyzw, vf13, vf13, vf12);
  c->vsub(DEST::xyzw, vf14, vf14, vf12);
  c->vsub(DEST::xyzw, vf6, vf6, vf12);
  c->vmini(DEST::xyzw, vf2, vf11, vf0);
  c->vopmula(vf13, vf11);
  c->vopmsub(vf16, vf11, vf13);
  DBG[0]=fb(c->vfs[vf16].f[0]); DBG[1]=fb(c->vfs[vf16].f[1]); DBG[2]=fb(c->vfs[vf16].f[2]); // raw cross-product normal
  c->vmax(DEST::xyzw, vf3, vf11, vf0);
  c->vmini(DEST::xyzw, vf4, vf14, vf6);
  c->vmax(DEST::xyzw, vf5, vf14, vf6);
  c->vmul(DEST::xyzw, vf7, vf16, vf16);
  c->vmini(DEST::xyzw, vf2, vf2, vf13);
  c->vmax(DEST::xyzw, vf3, vf3, vf13);
  c->vsub_bc(DEST::xyzw, BC::x, vf4, vf4, vf1);
  c->vadd_bc(DEST::x, BC::y, vf7, vf7, vf7);
  c->vadd_bc(DEST::xyzw, BC::x, vf5, vf5, vf1);
  c->vsub(DEST::xyzw, vf3, vf3, vf4);
  c->vadd_bc(DEST::x, BC::z, vf7, vf7, vf7);
  c->vsub(DEST::xyzw, vf5, vf5, vf2);
  c->mov128_gpr_vf(t2, vf3);
  c->mov128_gpr_vf(v1, vf5);
  c->vrsqrt(vf0, BC::w, vf7, BC::x);
  DBG[3]=fb(c->Q); DBG[4]=fb(c->vfs[vf7].f[0]);  // 1/|normal| and |normal|^2
  c->or_(v1, t2, v1);
  c->pcgtw(v1, r0, v1);
  c->ppach(v1, r0, v1);
  c->dsll(v1, v1, 16);
  bc = c->sgpr64(v1) != 0;
  if (bc) {goto block_14;}
  c->vmul(DEST::xyzw, vf2, vf16, vf15);
  c->vmul(DEST::xyzw, vf3, vf16, vf14);
  c->vadd_bc(DEST::x, BC::y, vf2, vf2, vf2);
  c->vsub_bc(DEST::y, BC::y, vf3, vf0, vf3);
  c->vadd_bc(DEST::x, BC::z, vf2, vf2, vf2);
  c->vsub_bc(DEST::y, BC::x, vf3, vf3, vf3);
  c->vsub_bc(DEST::y, BC::z, vf3, vf3, vf3);
  c->vadd_bc(DEST::x, BC::x, vf3, vf0, vf0);
  c->vadd_bc(DEST::x, BC::x, vf4, vf0, vf0);
  c->vwaitq();
  c->vmulq(DEST::xyzw, vf16, vf16);
  c->vmove(DEST::w, vf16, vf0);
  c->vmulq(DEST::xyzw, vf2, vf2);
  c->vmulq(DEST::xyzw, vf4, vf3);
  c->vmulq(DEST::xyzw, vf3, vf3);
  c->sqc2(vf16, 0, t1);
  c->vdiv(vf0, BC::w, vf2, BC::x);
  c->vadd_bc(DEST::y, BC::x, vf3, vf3, vf1);
  c->vsub_bc(DEST::y, BC::x, vf4, vf4, vf1);
  c->vwaitq();
  c->vmulq(DEST::xyzw, vf3, vf3);
  c->vmulq(DEST::xyzw, vf4, vf4);
  c->mov128_gpr_vf(v1, vf3);
  c->mov128_gpr_vf(t1, vf4);
  bc = ((s64)c->sgpr64(v1)) < 0;
  if (bc) {goto block_11;}
  bc = ((s64)c->sgpr64(t1)) < 0;
  if (bc) {goto block_12;}
  c->dsubu(v1, v1, t1);
  bc = ((s64)c->sgpr64(v1)) < 0;
  if (bc) {goto block_6;}
  c->vsub_bc(DEST::xyzw, BC::w, vf2, vf4, vf0);
  c->mov128_gpr_vf(v1, vf2);
  bc = ((s64)c->sgpr64(v1)) >= 0;
  if (bc) {goto block_14;}
  c->mov128_gpr_vf(v0, vf4);
  c->vmula_bc(DEST::xyzw, BC::w, vf14, vf0);
  c->vmadd_bc(DEST::xyzw, BC::y, vf8, vf15, vf4);
  goto block_8;
block_6:
  c->vsub_bc(DEST::xyzw, BC::w, vf2, vf3, vf0);
  c->mov128_gpr_vf(v1, vf2);
  bc = ((s64)c->sgpr64(v1)) >= 0;
  if (bc) {goto block_14;}
  c->vmula_bc(DEST::xyzw, BC::w, vf14, vf0);
  c->vmadd_bc(DEST::xyzw, BC::y, vf8, vf15, vf3);
  c->mov128_gpr_vf(v0, vf3);
block_8:
  c->dsra32(v0, v0, 0);
  c->vsub(DEST::xyzw, vf9, vf8, vf13);
  c->vsub(DEST::xyzw, vf10, vf8, vf11);
  c->vopmula(vf13, vf8);
  c->vopmsub(vf5, vf8, vf13);
  c->vopmula(vf8, vf11);
  c->vopmsub(vf6, vf11, vf8);
  c->vopmula(vf9, vf10);
  c->vopmsub(vf7, vf10, vf9);
  c->vmul(DEST::xyzw, vf5, vf5, vf16);
  c->vmul(DEST::xyzw, vf6, vf6, vf16);
  c->vmul(DEST::xyzw, vf7, vf7, vf16);
  c->vadd_bc(DEST::y, BC::x, vf5, vf5, vf5);
  c->vadd_bc(DEST::y, BC::x, vf6, vf6, vf6);
  c->vadd_bc(DEST::y, BC::x, vf7, vf7, vf7);
  c->vadd_bc(DEST::y, BC::z, vf5, vf5, vf5);
  c->vadd_bc(DEST::y, BC::z, vf6, vf6, vf6);
  c->vadd_bc(DEST::y, BC::z, vf7, vf7, vf7);
  c->mov128_gpr_vf(t1, vf5);
  c->mov128_gpr_vf(t2, vf6);
  c->mov128_gpr_vf(v1, vf7);
  c->or_(t1, t1, t2);
  c->or_(v1, t1, v1);
  bc = ((s64)c->sgpr64(v1)) < 0;
  if (bc) {goto block_10;}
  c->vopmula(vf8, vf16);
  c->vopmsub(vf5, vf16, vf8);
  c->vopmula(vf16, vf5);
  c->vopmsub(vf5, vf5, vf16);
  c->vadd(DEST::xyzw, vf5, vf5, vf12);
  c->sqc2(vf5, 0, t0);
  goto block_15;
block_10:
  // collide-do-primitives recursion (back/edge fallthrough): treat as MISS here.
  c->gprs[v0].du64[0] = 0;
  c->lui(v0, -13122); c->ori(v0, v0, 48160);
  goto block_15;
block_11:
  bc = ((s64)c->sgpr64(t1)) < 0;
  if (bc) {goto block_14;}
block_12:
  c->vsub(DEST::xyzw, vf9, vf14, vf13);
  c->vsub(DEST::xyzw, vf10, vf14, vf11);
  c->vopmula(vf13, vf14);
  c->vopmsub(vf5, vf14, vf13);
  c->vopmula(vf14, vf11);
  c->vopmsub(vf6, vf11, vf14);
  c->vopmula(vf9, vf10);
  c->vopmsub(vf7, vf10, vf9);
  c->vmul(DEST::xyzw, vf5, vf5, vf16);
  c->vmul(DEST::xyzw, vf6, vf6, vf16);
  c->vmul(DEST::xyzw, vf7, vf7, vf16);
  c->vadd_bc(DEST::y, BC::x, vf5, vf5, vf5);
  c->vadd_bc(DEST::y, BC::x, vf6, vf6, vf6);
  c->vadd_bc(DEST::y, BC::x, vf7, vf7, vf7);
  c->vadd_bc(DEST::y, BC::z, vf5, vf5, vf5);
  c->vadd_bc(DEST::y, BC::z, vf6, vf6, vf6);
  c->vadd_bc(DEST::y, BC::z, vf7, vf7, vf7);
  c->mov128_gpr_vf(t1, vf5);
  c->mov128_gpr_vf(t2, vf6);
  c->mov128_gpr_vf(v1, vf7);
  c->or_(t1, t1, t2);
  c->or_(v1, t1, v1);
  bc = ((s64)c->sgpr64(v1)) < 0;
  if (bc) {goto block_10;}
  c->vopmula(vf14, vf16);
  c->vopmsub(vf5, vf16, vf14);
  c->vopmula(vf16, vf5);
  c->vopmsub(vf5, vf5, vf16);
  c->vadd(DEST::xyzw, vf5, vf5, vf12);
  c->sqc2(vf5, 0, t0);
  c->addiu(v0, r0, 0);
  goto block_15;
block_14:
  c->lui(v0, -13122);
  c->ori(v0, v0, 48160);
block_15:
  c->ld(ra, 0, sp);
  c->daddiu(sp, sp, 16);
  return c->gprs[v0].du64[0];
}
// ------------------------------------------------------------------------------

static void put_vec(u32 addr, float x, float y, float z, float w){
  float v[4]={x,y,z,w}; std::memcpy(g_ee_main_mem+addr, v, 16);
}
// Deterministic LCG so FMA-on, FMA-off and x86 builds use byte-identical inputs.
static uint64_t st = 0xD1B54A32D192ED03ull;
static uint32_t rr(){ st = st*6364136223846793005ull + 1442695040888963407ull; return (uint32_t)(st>>32); }
static float fr(float lo, float hi){ return lo + (hi-lo)*(rr()/4294967296.0f); }

int main(){
  g_ee_main_mem = (u8*)calloc(1u<<20, 1);          // 1 MB EE scratch
  const u32 CEN=0x1000, MOV=0x1010, TRI=0x1020, OUTC=0x1100, OUTN=0x1110, STK=0x8000;
  // Randomized TILTED wall triangles at Jak-scale coords with a MOVING sphere
  // grazing near an edge/face — the regime where the leaf's cross-product sign
  // tests are near zero and FMA contraction flips hit<->miss. Same seed => the
  // three builds see identical inputs; diff the per-idx return to find flips.
  int N = 60000;
  printf("# idx   verdict   return_u(hex)\n");
  for (int i=0;i<N;i++){
    // NOTE: every fr() is drawn into a NAMED LOCAL in a fixed sequence. Drawing
    // multiple fr() inside one function-argument list would be unsequenced (C++
    // leaves arg eval order unspecified) -> clang and gcc would draw DIFFERENT
    // inputs, faking a divergence. Sequence the RNG explicitly.
    float bx=fr(-3e5f,3e5f), by=fr(-3e5f,3e5f), bz=fr(-3e5f,3e5f);
    float d1x=fr(2e4f,2e5f), d1y=fr(-2e5f,2e5f), d1z=fr(2e4f,2e5f);
    float d2x=fr(-2e5f,2e5f), d2y=fr(2e4f,2e5f), d2z=fr(-2e5f,2e5f);
    float a=fr(-0.2f,1.1f), b=fr(-0.2f,1.1f);
    float ox=fr(-6e3f,6e3f), oy=fr(-6e3f,6e3f), oz=fr(-6e3f,6e3f);
    float mvx=fr(-9e4f,9e4f), mvy=fr(-9e4f,9e4f), mvz=fr(-9e4f,9e4f);
    float radius=fr(2e3f,6e3f);
    put_vec(TRI+0,  bx,      by,      bz,      0);
    put_vec(TRI+16, bx+d1x,  by+d1y,  bz+d1z,  0);
    put_vec(TRI+32, bx+d2x,  by+d2y,  bz+d2z,  0);
    float p0[3],p1[3],p2[3]; std::memcpy(p0,g_ee_main_mem+TRI+0,12);
    std::memcpy(p1,g_ee_main_mem+TRI+16,12); std::memcpy(p2,g_ee_main_mem+TRI+32,12);
    float cx=p0[0]+a*(p1[0]-p0[0])+b*(p2[0]-p0[0])+ox;
    float cy=p0[1]+a*(p1[1]-p0[1])+b*(p2[1]-p0[1])+oy;
    float cz=p0[2]+a*(p1[2]-p0[2])+b*(p2[2]-p0[2])+oz;
    put_vec(CEN, cx,cy,cz,0);
    put_vec(MOV, mvx,mvy,mvz,0);  // moving sphere
    ExecutionContext c; std::memset(&c,0,sizeof(c));
    c.gprs[sp].du64[0]=STK;
    c.gprs[a0].du32[0]=CEN; c.gprs[a1].du32[0]=MOV;
    c.gprs[a3].du32[0]=TRI; c.gprs[t0].du32[0]=OUTC; c.gprs[t1].du32[0]=OUTN;
    u32 rb; std::memcpy(&rb,&radius,4); c.gprs[a2].du32[0]=rb;
    // validity: non-degenerate triangle (real area) and sphere near the plane.
    float e1[3]={p1[0]-p0[0],p1[1]-p0[1],p1[2]-p0[2]};
    float e2[3]={p2[0]-p0[0],p2[1]-p0[1],p2[2]-p0[2]};
    float nx=e1[1]*e2[2]-e1[2]*e2[1], ny=e1[2]*e2[0]-e1[0]*e2[2], nz=e1[0]*e2[1]-e1[1]*e2[0];
    float area2=std::sqrt(nx*nx+ny*ny+nz*nz);
    bool valid = area2 > 1e9f && std::isfinite(cx) && std::isfinite(cy) && std::isfinite(cz);
    u64 r = leaf_execute(&c);
    u32 lo=(u32)r; float u; std::memcpy(&u,&lo,4);
    bool miss = (lo==0xCCCEBC20u) || (u < -1e7f);
    bool nan_out = !std::isfinite(u) && !miss;
    printf("%-7d %s 0x%08x V=%d N=%d cross=%08x,%08x,%08x Q=%08x nn2=%08x\n",
           i, miss?"MISS":"HIT ", lo, valid?1:0, nan_out?1:0,
           DBG[0],DBG[1],DBG[2],DBG[3],DBG[4]);
  }
  return 0;
}
