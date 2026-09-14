// Standalone laboratory test; never writes harness proof counters/files.
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "game/mips2c/vu_simd.h"

using namespace Mips2C;
namespace Mips2C::vu_simd {
static Settings config{true, false};
static uint64_t comparisons[3]{}, defects[3]{};
Settings settings(Kernel) { return config; }
void record(Kernel k, uint64_t n, uint64_t d) {
  comparisons[static_cast<int>(k)] += n;
  defects[static_cast<int>(k)] += d;
}
}

template<class Context>
void invoke(Context& c, int op, DEST m, BC bc, int d, int a, int b) {
  switch (op) {
    case 0: c.vmul(m,d,a,b); break;
    case 1: c.vadd(m,d,a,b); break;
    case 2: c.vsub(m,d,a,b); break;
    case 3: c.vmul_bc(m,bc,d,a,b); break;
    case 4: c.vadd_bc(m,bc,d,a,b); break;
    case 5: c.vsub_bc(m,bc,d,a,b); break;
    case 6: c.vmula(m,a,b); break;
    case 7: c.vmula_bc(m,bc,a,b); break;
    case 8: c.vmula_q(m,a); break;
    case 9: c.vmulq(m,d,a); break;
    case 10: c.vaddq(m,d,a); break;
    case 11: c.vmove(m,d,a); break;
    case 12: c.vabs(m,d,a); break;
    default: std::abort();
  }
}

static constexpr const char* names[] = {"vmul", "vadd", "vsub", "vmul_bc",
  "vadd_bc", "vsub_bc", "vmula", "vmula_bc", "vmula_q", "vmulq", "vaddq",
  "vmove", "vabs"};

static void seed(ExecutionContext& c, unsigned sample) {
  // ±zero, min/max subnormal, min normal, finite extrema, infinities,
  // quiet/signaling NaNs with signs and payloads, plus deterministic bit patterns.
  constexpr uint32_t edge[] = {0, 0x80000000u, 1, 0x80000001u,
    0x007fffffu, 0x807fffffu, 0x00800000u, 0x80800000u,
    0x3f800000u, 0xbf800000u, 0x7f7fffffu, 0xff7fffffu,
    0x7f800000u, 0xff800000u, 0x7fc12345u, 0xffc54321u,
    0x7f812345u, 0xff854321u, 0x3f000001u, 0xbf000001u};
  uint32_t state = 0x9e3779b9u ^ sample;
  auto bits = [&](unsigned index) {
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return sample < 40 ? edge[(sample + index * (sample < 20 ? 0 : 7)) % 20] : state;
  };
  for (unsigned r=0; r<32; ++r)
    for (unsigned lane=0; lane<4; ++lane) c.vfs[r].du32[lane]=bits(r*4+lane);
  for (unsigned lane=0; lane<4; ++lane) c.acc.du32[lane]=bits(128+lane);
  auto q=bits(132); std::memcpy(&c.Q,&q,4);
  c.I=1.25f;
}

int main() {
  using namespace Mips2C::vu_simd;
  constexpr int aliases[][3] = {{3,1,2},{1,1,2},{2,1,2},{1,1,1},
    {3,0,2},{3,1,0},{3,0,0},{0,1,2},{0,0,0},{0,0,2},{0,1,0}};
  const char* modes[]={"delivered", "verify", "off"};
  uint64_t failures=0;
  for (int mode=0; mode<3; ++mode) {
    config={mode!=2, mode==1};
    std::memset(comparisons,0,sizeof(comparisons));
    std::memset(defects,0,sizeof(defects));
    uint64_t cases=0, recorded_per_op[13]{};
    for (unsigned sample=0; sample<104; ++sample) {
      ExecutionContext initial{}; seed(initial,sample);
      for (int mask=0; mask<16; ++mask)
        for (int bc=0; bc<4; ++bc)
          for (const auto& ids:aliases)
            for (int op=0; op<13; ++op) {
              ExecutionContext expected=initial, actual=initial;
              const int kernel=cases%3;
              VuSimd simd(&actual,static_cast<Kernel>(kernel));
              invoke(expected,op,static_cast<DEST>(mask),static_cast<BC>(bc),ids[0],ids[1],ids[2]);
              const auto before=comparisons[kernel];
              invoke(simd,op,static_cast<DEST>(mask),static_cast<BC>(bc),ids[0],ids[1],ids[2]);
              recorded_per_op[op]+=comparisons[kernel]-before;
              // Entire context detects both result defects and unexpected collateral writes.
              if (std::memcmp(&actual,&expected,sizeof(actual))) {
                if (failures<12) {
                  std::printf("FAIL mode=%s op=%s sample=%u mask=%d bc=%d d/a/b=%d/%d/%d\n",
                    modes[mode],names[op],sample,mask,bc,ids[0],ids[1],ids[2]);
                  for (int r=0;r<32;++r) for(int l=0;l<4;++l)
                    if (actual.vfs[r].du32[l]!=expected.vfs[r].du32[l])
                      std::printf(" vf%d.%d actual=%08x expected=%08x\n",r,l,actual.vfs[r].du32[l],expected.vfs[r].du32[l]);
                }
                ++failures;
              }
              ++cases;
            }
    }
    for (int op=0;op<13;++op) {
      if ((mode==1 && !recorded_per_op[op]) || (mode!=1 && recorded_per_op[op])) ++failures;
      std::printf("mode=%s op=%s recorded_comparisons=%llu\n",modes[mode],names[op],
                  static_cast<unsigned long long>(recorded_per_op[op]));
    }
    for (int k=0;k<3;++k) {
      if (defects[k] || (mode==1 && !comparisons[k]) || (mode!=1 && comparisons[k])) ++failures;
      std::printf("mode=%s kernel=%d recorded_comparisons=%llu recorded_defects=%llu\n",
        modes[mode],k,static_cast<unsigned long long>(comparisons[k]),static_cast<unsigned long long>(defects[k]));
    }
    std::printf("mode=%s external_bitwise_cases=%llu cumulative_failures=%llu\n",modes[mode],
      static_cast<unsigned long long>(cases),static_cast<unsigned long long>(failures));
  }
  std::printf("RESULT %s\n",failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
