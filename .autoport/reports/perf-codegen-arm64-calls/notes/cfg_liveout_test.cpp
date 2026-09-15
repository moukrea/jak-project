#include "goalc/regalloc/Allocator.h"
#include "goalc/regalloc/Allocator_v2.h"
#include <iostream>
#define CHECK(expr) do { ++checks; if (!(expr)) { std::cerr << "failed=" << #expr << "\n"; return 1; } } while (0)
int main() {
int checks=0;

  // v0 survives the call only on one branch; the other branch redefines it.
  // v1 is the branch condition, v2 is the dead call target, v3 is the result.
  const IRegister v0{RegClass::GPR_64, 0}, v1{RegClass::GPR_64, 1},
      v2{RegClass::GPR_64, 2}, v3{RegClass::GPR_64, 3};
  AllocationInput input;
  input.max_vars = 4;
  input.function_name = "test-arm64-call-liveout";
  input.instructions.resize(6);
  input.instructions[0].write = {v0, v1, v2};
  input.instructions[1].read = {v2};
  input.instructions[1].write = {v2, v3};
  for (int reg = 0; reg < emitter::RegisterInfo::N_REGS; ++reg) {
    if (emitter::gRegInfo.get_info(reg).temp()) {
      input.instructions[1].clobber.emplace_back(reg);
    }
  }
  input.instructions[2].read = {v1};
  input.instructions[2].jumps = {4};
  input.instructions[3].write = {v0};
  input.instructions[3].jumps = {5};
  input.instructions[3].fallthrough = false;
  input.instructions[4].read = {v0};
  input.instructions[4].fallthrough = false;
  input.instructions[5].read = {v3};
  input.instructions[5].fallthrough = false;

  for (int version : {1, 2}) {
    std::cout << "allocator_version=" << version << "\n";
    input.allocator_version = version;
    const auto result = version == 1 ? allocate_registers(input) : allocate_registers_v2(input);
    CHECK(result.ok);
    CHECK(result.live_out.size() == input.instructions.size());
    CHECK((result.live_out[1] == std::vector<int>{0, 1, 3}));
    CHECK((result.live_out[2] == std::vector<int>{0, 3}));
    CHECK((result.live_out[3] == std::vector<int>{3}));
    CHECK(result.live_out[4].empty());
    CHECK(result.live_out[5].empty());
  }
std::cout << "cfg_assertions=" << checks << "\ncfg_failures=0\n";
return 0;
}
