#!/usr/bin/env python3
"""Adapt the existing vu_simd_parity seed/context comparator to real 3D blocks.
Laboratory inputs only; never writes harness proof or runs a device.
"""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[5]
notes = Path(__file__).resolve().parent
old = notes / 'before-sparticle.cpp'
new = notes / 'candidate-sparticle.cpp'
seed_source = (notes.parent / 'vu_simd_parity.cpp').read_text()
seed = seed_source[seed_source.index('static void seed('):seed_source.index('\nint main()')]

def block(path):
    source = path.read_text().split('namespace sp_process_block_3d {', 1)[1]
    return source.split('  block_18:\n', 1)[1].split('  c->mov64(v1, s1);', 1)[0]

code = '''// Generated from exact before/after engine blocks; laboratory only.
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include "game/mips2c/mips2c_private.h"
u8* g_ee_main_mem;
using namespace Mips2C;
'''
for name, path in [('before', old), ('after', new)]:
    code += f'// {name} source sha256={hashlib.sha256(path.read_bytes()).hexdigest()}\n'
    code += f'__attribute__((noinline)) bool {name}(ExecutionContext* c) {{\n bool bc = false;\n'
    code += block(path) + '\n return bc;\n}\n'
code += seed
code += r'''
int main() {
  // Finite particle-like ranges plus existing raw IEEE edges/random bit patterns.
  constexpr u32 fades[] = {0, 0x80000000u, 0x3f000000u, 0x3f800000u,
                           0x7fc12345u, 0xff854321u};
  constexpr u32 positions[][2] = {{64,256}, {64,64}, {64,48},
                                 {64,80}, {128,64}, {64,128}};
  unsigned cases=0, failures=0, damped=0, bypass=0, finite_cases=0;
  for (unsigned sample=0; sample<168; ++sample)
    for (const auto& pos: positions)
      for (u32 fade: fades) {
        ExecutionContext initial{}; seed(initial, sample);
        // Initialize all GPR bytes too, particularly untouched upper v1 lanes.
        for (unsigned r=0; r<32; ++r)
          for (unsigned lane=0; lane<4; ++lane)
            initial.gprs[r].du32[lane]=0x9e3779b9u*(1+r*4+lane+sample);
        initial.gprs[s4].du32[0]=pos[0]; initial.gprs[s5].du32[0]=pos[1];
        std::array<u8,512> memory{};
        for (unsigned offset=0; offset<memory.size(); offset+=4) {
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
        std::memcpy(memory.data()+pos[1]+96,&fade,4);
        ExecutionContext expected=initial, actual=initial;
        auto reference_memory=memory, actual_memory=memory;
        g_ee_main_mem=reference_memory.data(); bool ref_bc=before(&expected);
        g_ee_main_mem=actual_memory.data(); bool actual_bc=after(&actual);
        if (ref_bc) ++bypass; else ++damped;
        bool mismatch=ref_bc!=actual_bc ||
          std::memcmp(&expected,&actual,sizeof(actual)) || reference_memory!=actual_memory;
        if (mismatch) {
          if (failures<12) {
            std::printf("FAIL sample=%u s4=%u s5=%u fade=%08x\n",sample,pos[0],pos[1],fade);
            for (unsigned r=0;r<32;++r) for(unsigned l=0;l<4;++l)
              if(expected.vfs[r].du32[l]!=actual.vfs[r].du32[l])
                std::printf("vf%u.%u before=%08x after=%08x\n",r,l,expected.vfs[r].du32[l],actual.vfs[r].du32[l]);
          }
          ++failures;
        }
        ++cases;
      }
  std::printf("LAB cases=%u finite_memory_cases=%u damped=%u bypass=%u context_and_memory_defects=%u\n",
              cases,finite_cases,damped,bypass,failures);
  std::printf("RESULT %s\n",failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
'''
(notes / 'block-parity.cpp').write_text(code)
print('generated', notes / 'block-parity.cpp')
