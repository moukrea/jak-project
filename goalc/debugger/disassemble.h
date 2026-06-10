#pragma once

#include <memory>
#include <string>
#include <variant>
#include <vector>

#include "common/common_types.h"

#include "goalc/emitter/Instruction.h"

class FunctionEnv;

namespace goos {
class Reader;
class Object;
class HeapObject;
}  // namespace goos

struct InstructionInfo {
  emitter::Instruction instruction;
  enum class Kind { PROLOGUE, IR, EPILOGUE } kind;
  int ir_idx = -1;
  int offset = -1;

  InstructionInfo(const emitter::Instruction& _instruction, Kind _kind)
      : instruction(_instruction), kind(_kind) {}
  InstructionInfo(const emitter::Instruction& _instruction, Kind _kind, int _ir_idx)
      : instruction(_instruction), kind(_kind), ir_idx(_ir_idx) {}
};

std::string disassemble_x86(u8* data, int len, u64 base_addr);
std::string disassemble_x86(u8* data, int len, u64 base_addr, u64 highlight_addr);

std::string disassemble_x86_function(
    u8* data,
    int len,
    const goos::Reader* reader,
    u64 base_addr,
    u64 highlight_addr,
    const std::vector<InstructionInfo>& x86_instructions,
    const std::vector<std::shared_ptr<goos::HeapObject>>& code_sources,
    const std::vector<std::string>& ir_strings,
    bool* had_failure,
    bool print_whole_function,
    bool omit_ir);

// ARM64 disassembly via Capstone. Decodes the actual emitted bytes (canonical),
// so it also surfaces encoding bugs. Used by goalc-codegen-diff.
std::string disassemble_arm64(u8* data, int len, u64 base_addr);

// IR-annotated ARM64 function disassembly (Capstone), mirroring
// disassemble_x86_function so :disassemble works in the arm64-backend goalc.
std::string disassemble_arm64_function(
    u8* data,
    int len,
    const goos::Reader* reader,
    u64 base_addr,
    const std::vector<InstructionInfo>& instructions,
    const std::vector<std::shared_ptr<goos::HeapObject>>& code_sources,
    const std::vector<std::string>& ir_strings,
    bool* had_failure,
    bool omit_ir);

// Structured single-instruction decode used by goalc-codegen-diff to build a
// per-IR-node side-by-side x86/arm64 view and to analyze register clobbers.
struct DecodedInstr {
  u64 addr = 0;
  int offset = 0;    // byte offset from the start of the decoded buffer
  int length = 0;    // length of this instruction in bytes
  std::string text;  // formatted mnemonic + operands
  std::vector<std::string> regs_written;     // normalized hw registers written (e.g. "x8")
  std::vector<std::string> stack_xfer_regs;  // regs moved to/from [sp] by this str/ldr/stp/ldp
  bool touches_sp = false;                   // reads or writes the stack pointer
  bool is_store_to_stack = false;            // str/stp to [sp]
  bool is_load_from_stack = false;           // ldr/ldp from [sp]
  int sp_delta = 0;                          // immediate add/sub applied to sp (signed bytes)
  bool valid = true;                         // false if the bytes failed to decode
};

std::vector<DecodedInstr> decode_x86(u8* data, int len, u64 base_addr);
std::vector<DecodedInstr> decode_arm64(u8* data, int len, u64 base_addr);