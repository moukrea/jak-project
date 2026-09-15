// DIRECTIVES vaff5c1afea -- laboratory frontier comparison, not full-function parity.
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include "game/mips2c/mips2c_private.h"

using namespace Mips2C;
u8* g_ee_main_mem;
extern "C" {
u64 full_before_execute(void*);
u64 full_after_execute(void*);
struct FullCache { void* frame; void* quaternion; void* free_particle; void* relaunch; };
extern FullCache full_before_cache;
extern FullCache full_after_cache;
}

struct Boundary {
  std::uintptr_t goal;
  std::array<u64, 8> args;
  u64 zero, pp, st;
  bool offset_matches_memory;
};
// Fail closed at the first external call: capture only, never execute a callback
// or fabricate its return. Host memory bases differ, so record the GOAL offset.
extern "C" u64 _call_goal8_asm_systemv(void* func, u64* args, u64 zero,
                                      u64 pp, u64 st, void* off) {
  Boundary b{};
  b.goal = reinterpret_cast<std::uintptr_t>(func) -
           reinterpret_cast<std::uintptr_t>(g_ee_main_mem);
  std::copy(args, args + 8, b.args.begin());
  b.zero = zero; b.pp = pp; b.st = st;
  b.offset_matches_memory = off == g_ee_main_mem;
  throw b;
}

struct Outcome {
  Boundary call{};
  u64 result = 0;
  bool returned = false;
  bool other_exception = false;
};
static Outcome run(u64 (*execute)(void*), ExecutionContext& context,
                   std::array<u8, 4096>& memory) {
  g_ee_main_mem = memory.data();
  Outcome out{};
  try { out.result = execute(&context); out.returned = true; }
  catch (const Boundary& b) { out.call = b; }
  catch (...) { out.other_exception = true; }
  return out;
}
static unsigned route(const Outcome& o) {
  if (o.returned) return 3;
  if (!o.other_exception && o.call.offset_matches_memory) {
    if (o.call.goal == 2048) return 0;
    if (o.call.goal == 2064) return 1;
  }
  return 2;
}
static const char* route_name(unsigned r) {
  static const char* names[] = {"quaternion", "free", "other", "return"};
  return names[r];
}
static bool same_call(const Outcome& a, const Outcome& b) {
  if (a.returned != b.returned || a.other_exception != b.other_exception) return false;
  if (a.returned) return a.result == b.result;
  return a.call.goal == b.call.goal && a.call.args == b.call.args &&
         a.call.zero == b.call.zero && a.call.pp == b.call.pp &&
         a.call.st == b.call.st &&
         a.call.offset_matches_memory == b.call.offset_matches_memory;
}
static std::size_t first_byte(const void* a, const void* b, std::size_t size) {
  auto* x = static_cast<const u8*>(a); auto* y = static_cast<const u8*>(b);
  std::size_t i = 0;
  while (i < size && x[i] == y[i]) ++i;
  return i;
}
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

int main(int argc, char** argv) {
  const char* csv_path = argc > 1 ? argv[1] : "frontier-parity.csv";
  FILE* csv = std::fopen(csv_path, "w");
  if (!csv) { std::perror(csv_path); return 2; }
  std::fprintf(csv, "case,sample,s4,s5,fade,before_frontier,after_frontier,context_defect,memory_defect,call_defect,unexpected,before_goal,after_goal,before_vf11z,after_vf11z,before_return,after_return\n");
  u32 frame = 512, quaternion = 2048, free_particle = 2064, relaunch = 2080;
  full_before_cache = {&frame, &quaternion, &free_particle, &relaunch};
  full_after_cache = full_before_cache;
  constexpr u32 fades[] = {0, 0x80000000u, 0x3f000000u, 0x3f800000u,
                           0x7fc12345u, 0xff854321u};
  constexpr u32 positions[][2] = {{64,256}, {64,64}, {64,48},
                                 {64,80}, {128,64}, {64,128}};
  unsigned cases=0, failures=0, unexpected=0, finite_cases=0;
  unsigned context_defects=0, memory_defects=0, call_defects=0;
  std::array<unsigned,4> before_routes{}, after_routes{};
  for (unsigned sample=0; sample<168; ++sample)
    for (const auto& pos: positions)
      for (u32 fade: fades) {
        ExecutionContext initial{}; seed(initial, sample);
        for (unsigned r=0; r<32; ++r)
          for (unsigned lane=0; lane<4; ++lane)
            initial.gprs[r].du32[lane]=0x9e3779b9u*(1+r*4+lane+sample);
        initial.gprs[s4].du32[0]=pos[0]; initial.gprs[s5].du32[0]=pos[1];
        std::array<u8,4096> memory{};
        // The first 512 bytes exactly follow attempt7, including aliasing inputs.
        for (unsigned offset=0; offset<512; offset+=4) {
          u32 bits=initial.vfs[(offset/16)%32].du32[(offset/4)%4];
          if (sample>=104) {
            float value=(int((offset*17+sample*31)%2049)-1024)*0.125f;
            std::memcpy(&bits,&value,4);
          }
          std::memcpy(memory.data()+offset,&bits,4);
        }
        if (sample>=104) {
          initial.vfs[16].f[0]=0.f;
          initial.vfs[16].f[1]=(sample%4)*0.25f;
          initial.vfs[16].f[2]=(sample%7)*0.0625f;
          initial.vfs[16].f[3]=(sample%9)*0.125f;
          ++finite_cases;
        }
        // Friction at +96 retains the historical CSV identifier "fade".
        std::memcpy(memory.data()+pos[1]+96,&fade,4);
        // Full-function ABI/prologue adapters touch only specified low 64 bits.
        // Preserve life+100, flags+104, nexttime+116 and cache-alpha+124,
        // including fields that alias colors.
        initial.gprs[a1].du64[0]=pos[1]; initial.gprs[a2].du64[0]=pos[0];
        initial.gprs[a0].du64[0]=1024; initial.gprs[a3].du64[0]=0;
        initial.gprs[t0].du64[0]=1; initial.gprs[t1].du64[0]=768;
        initial.gprs[s7].du64[0]=768; initial.gprs[sp].du64[0]=4096;
        initial.gprs[s6].du64[0]=0;
        std::memcpy(memory.data()+512,&initial.vfs[16],16);
        const u32 zero=0, valid=772;
        std::memcpy(memory.data()+pos[1]+112,&zero,4);
        std::memcpy(memory.data()+pos[1]+120,&zero,4);
        std::memcpy(memory.data()+pos[1]+128,&valid,4);
        ExecutionContext expected, actual;
        std::memcpy(&expected,&initial,sizeof(initial));
        std::memcpy(&actual,&initial,sizeof(initial));
        auto reference_memory=memory, actual_memory=memory;
        const Outcome before=run(full_before_execute,expected,reference_memory);
        const Outcome after=run(full_after_execute,actual,actual_memory);
        const unsigned br=route(before), ar=route(after);
        ++before_routes[br]; ++after_routes[ar];
        const bool cd=std::memcmp(&expected,&actual,sizeof(actual))!=0;
        const bool md=std::memcmp(reference_memory.data(),actual_memory.data(),4096)!=0;
        const bool ad=!same_call(before,after);
        const bool un=br>=2 || ar>=2;
        context_defects+=cd; memory_defects+=md; call_defects+=ad; unexpected+=un;
        const bool mismatch=cd || md || ad;
        const bool special=sample==13 && pos[0]==64 && pos[1]==256 && fade==0x7fc12345u;
        if (((mismatch || un) && failures<12) || special) {
          std::printf("CASE id=%u sample=%u s4=%u s5=%u fade=%08x before=%s after=%s context=%u memory=%u call=%u unexpected=%u\n",
                      cases,sample,pos[0],pos[1],fade,route_name(br),route_name(ar),cd,md,ad,un);
          auto cb=first_byte(&expected,&actual,sizeof(actual));
          auto mb=first_byte(reference_memory.data(),actual_memory.data(),4096);
          std::printf("first_context_byte=%zu context_size=%zu first_memory_byte=%zu memory_size=4096\n",cb,sizeof(actual),mb);
          if (cb<sizeof(actual)) std::printf("context_byte before=%02x after=%02x\n",reinterpret_cast<const u8*>(&expected)[cb],reinterpret_cast<const u8*>(&actual)[cb]);
          if (mb<4096) std::printf("memory_byte before=%02x after=%02x\n",reference_memory[mb],actual_memory[mb]);
          for (unsigned r=0;r<32;++r) for(unsigned l=0;l<4;++l)
            if(special || expected.vfs[r].du32[l]!=actual.vfs[r].du32[l])
              std::printf("vf%u.%u before=%08x after=%08x\n",r,l,expected.vfs[r].du32[l],actual.vfs[r].du32[l]);
          std::printf("call_goal before=%llu after=%llu zero=%llu/%llu pp=%llu/%llu st=%llu/%llu offset_ok=%u/%u return=%llu/%llu\n",
                      (unsigned long long)before.call.goal,(unsigned long long)after.call.goal,
                      (unsigned long long)before.call.zero,(unsigned long long)after.call.zero,
                      (unsigned long long)before.call.pp,(unsigned long long)after.call.pp,
                      (unsigned long long)before.call.st,(unsigned long long)after.call.st,
                      before.call.offset_matches_memory,after.call.offset_matches_memory,
                      (unsigned long long)before.result,(unsigned long long)after.result);
          for(unsigned i=0;i<8;++i) std::printf("arg%u before=%016llx after=%016llx\n",i,(unsigned long long)before.call.args[i],(unsigned long long)after.call.args[i]);
        }
        failures+=mismatch || un;
        std::fprintf(csv,"%u,%u,%u,%u,%08x,%s,%s,%u,%u,%u,%u,%llu,%llu,%08x,%08x,%llu,%llu\n",
                     cases,sample,pos[0],pos[1],fade,route_name(br),route_name(ar),cd,md,ad,un,
                     (unsigned long long)before.call.goal,(unsigned long long)after.call.goal,
                     expected.vfs[11].du32[2],actual.vfs[11].du32[2],
                     (unsigned long long)before.result,(unsigned long long)after.result);
        ++cases;
      }
  bool io_error=std::ferror(csv)!=0;
  if (std::fclose(csv)!=0) io_error=true;
  for(unsigned variant=0;variant<2;++variant) {
    const auto& counts=variant ? after_routes : before_routes;
    std::printf("LAB variant=%s quaternion=%u free=%u other=%u return=%u\n",
                variant ? "after" : "before",counts[0],counts[1],counts[2],counts[3]);
  }
  std::printf("LAB cases=%u finite_memory_cases=%u failures=%u context_defects=%u memory_defects=%u call_defects=%u unexpected=%u csv_io_error=%u\n",
              cases,finite_cases,failures,context_defects,memory_defects,call_defects,unexpected,io_error);
  std::printf("RESULT_SCOPE frontier_only RESULT %s\n",
              unexpected || io_error ? "UNEXPECTED_FRONTIER_OR_IO_FAILURE" : failures ? "DIFFERENCES" : "NO_DIFFERENCES");
  return unexpected || io_error ? 2 : failures ? 1 : 0;
}
