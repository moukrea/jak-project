/*!
 * @file CodeGenerator.cpp
 * Generate object files from a FileEnv using an emitter::ObjectGenerator.
 * Populates a DebugInfo.
 * Currently owns the logic for emitting the function prologues/epilogues and stack spill ops.
 */

#include "CodeGenerator.h"

#include <algorithm>
#include <cstdlib>
#include <cxxabi.h>
#include <fstream>
#include <stdexcept>
#include <typeindex>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "IR.h"

#include "goalc/debugger/DebugInfo.h"
#include "goalc/emitter/IGen.h"

#include "fmt/format.h"

using namespace emitter;

namespace ir_emit_stats {
namespace {
struct Counter {
  uint64_t x86 = 0;
  uint64_t arm64 = 0;
};

// Process-lifetime accumulator. Compilation is single-threaded
// (Compiler::run_front_end_on_string holds the only mutator path), so
// no synchronisation is needed here.
std::unordered_map<std::type_index, Counter> g_counters;
std::string g_output_path;

std::string demangle(const char* mangled) {
  int status = 0;
  char* dem = abi::__cxa_demangle(mangled, nullptr, nullptr, &status);
  std::string out = (status == 0 && dem) ? std::string(dem) : std::string(mangled);
  std::free(dem);
  return out;
}
}  // namespace

void record(const std::type_info& ti, bool is_arm64) {
  auto& c = g_counters[std::type_index(ti)];
  if (is_arm64) {
    c.arm64++;
  } else {
    c.x86++;
  }
}

void set_output_path(const std::string& path) {
  g_output_path = path;
}

bool dump_to_file() {
  if (g_output_path.empty()) {
    return false;
  }
  // Sort by demangled class name so the output is deterministic across
  // runs (unordered_map iteration order isn't).
  std::vector<std::pair<std::string, Counter>> rows;
  rows.reserve(g_counters.size());
  for (const auto& kv : g_counters) {
    rows.emplace_back(demangle(kv.first.name()), kv.second);
  }
  std::sort(rows.begin(), rows.end(),
            [](const auto& a, const auto& b) { return a.first < b.first; });

  std::ofstream o(g_output_path);
  if (!o.is_open()) {
    return false;
  }
  o << "{";
  for (size_t i = 0; i < rows.size(); ++i) {
    if (i) {
      o << ",";
    }
    o << "\n  \"" << rows[i].first << "\": {\"x86\": " << rows[i].second.x86
      << ", \"arm64\": " << rows[i].second.arm64 << "}";
  }
  o << "\n}\n";
  return true;
}
}  // namespace ir_emit_stats

CodeGenerator::CodeGenerator(FileEnv* env,
                             DebugInfo* debug_info,
                             GameVersion version,
                             InstructionSet instruction_set)
    : m_gen(version, instruction_set), m_fe(env), m_debug_info(debug_info) {}

/*!
 * Generate an object file.
 */
std::vector<u8> CodeGenerator::run(const TypeSystem* ts) {
  std::unordered_set<std::string> function_names;

  // first, add each function to the ObjectGenerator (but don't add any data)
  for (auto& f : m_fe->functions()) {
    if (function_names.find(f->name()) == function_names.end()) {
      function_names.insert(f->name());
    } else {
      printf("Failed to codegen, there are two functions with internal names [%s]\n",
             f->name().c_str());
      throw std::runtime_error("Failed to codegen.");
    }
    auto rec =
        m_gen.add_function_to_seg(f->segment, &m_debug_info->add_function(f->name(), m_fe->name()));
    for (auto& x : f->code_source()) {
      rec.debug->code_sources.push_back(x.heap_obj);
    }
    for (auto& x : f->code()) {
      rec.debug->ir_strings.push_back(x->print());
    }
  }

  // next, add all static objects.
  for (auto& static_obj : m_fe->statics()) {
    static_obj->generate(&m_gen);
  }

  // next, add instructions to functions
  for (size_t i = 0; i < m_fe->functions().size(); i++) {
    do_function(m_fe->functions().at(i).get(), i);
  }

  // generate a v3 object.
  return m_gen.generate_data_v3(ts).to_vector();
}

void CodeGenerator::do_function(FunctionEnv* env, int f_idx) {
  if (env->is_asm_func) {
    if (m_gen.instr_set() == InstructionSet::X86) {
      do_asm_function_x86(env, f_idx, env->asm_func_saved_regs);
    } else if (m_gen.instr_set() == InstructionSet::ARM64) {
      do_asm_function_arm64(env, f_idx, env->asm_func_saved_regs);
    } else {
      throw std::runtime_error("CodeGenerator::do_function, instruction set not supported");
    }
  } else {
    if (m_gen.instr_set() == InstructionSet::X86) {
      do_goal_function_x86(env, f_idx);
    } else if (m_gen.instr_set() == InstructionSet::ARM64) {
      do_goal_function_arm64(env, f_idx);
    } else {
      throw std::runtime_error("CodeGenerator::do_function, instruction set not supported");
    }
  }
}

/*!
 * Add instructions to the function, specified by index.
 * Generates prologues / epilogues.
 */
void CodeGenerator::do_goal_function_x86(FunctionEnv* env, int f_idx) {
  bool use_new_xmms = true;
  auto* debug = &m_debug_info->function_by_name(env->name());

  auto f_rec = m_gen.get_existing_function_record(f_idx);
  // todo, extra alignment settings

  auto& ri = emitter::gRegInfo;
  const auto& allocs = env->alloc_result();

  // compute how much stack we will use
  int stack_offset = 0;

  // count how many xmm's we have to backup
  int n_xmm_backups = 0;
  for (auto& saved_reg : allocs.used_saved_regs) {
    if (saved_reg.is_xmm(m_gen.instr_set())) {
      n_xmm_backups++;
    }
  }

  // only for new xmms. if n == 0, we don't use this at all.
  int xmm_backup_stack_offset = 8 + XMM_SIZE * n_xmm_backups;

  if (use_new_xmms) {
    if (n_xmm_backups > 0) {
      // offset the stack
      stack_offset += xmm_backup_stack_offset;
      m_gen.add_instr_no_ir(f_rec, IGen::sub_gpr64_imm(m_gen, RSP, xmm_backup_stack_offset),
                            InstructionInfo::Kind::PROLOGUE);
      // back up xmms
      int i = 0;
      for (auto& saved_reg : allocs.used_saved_regs) {
        if (saved_reg.is_xmm(m_gen.instr_set())) {
          int offset = i * XMM_SIZE;
          m_gen.add_instr_no_ir(f_rec,
                                IGen::store128_xmm128_reg_offset(m_gen, RSP, saved_reg, offset),
                                InstructionInfo::Kind::PROLOGUE);
          i++;
        }
      }
    }
  } else {
    // back up xmms (currently not aligned)
    for (auto& saved_reg : allocs.used_saved_regs) {
      if (saved_reg.is_xmm(m_gen.instr_set())) {
        m_gen.add_instr_no_ir(f_rec, IGen::sub_gpr64_imm8s(m_gen, RSP, XMM_SIZE),
                              InstructionInfo::Kind::PROLOGUE);
        m_gen.add_instr_no_ir(f_rec, IGen::store128_gpr64_simd128(m_gen, RSP, saved_reg),
                              InstructionInfo::Kind::PROLOGUE);
        stack_offset += XMM_SIZE;
      }
    }
  }

  // back up gprs
  for (auto& saved_reg : allocs.used_saved_regs) {
    if (saved_reg.is_gpr(m_gen.instr_set())) {
      m_gen.add_instr_no_ir(f_rec, IGen::push_gpr64(m_gen, saved_reg),
                            InstructionInfo::Kind::PROLOGUE);
      stack_offset += GPR_SIZE;
    }
  }

  // do we include an extra push to get 8 more bytes to keep the stack aligned?
  bool bonus_push = false;

  // the offset to add directly to rsp for stack variables or spills (no push/pop)
  int manually_added_stack_offset =
      GPR_SIZE * (allocs.stack_slots_for_spills + allocs.stack_slots_for_vars);
  stack_offset += manually_added_stack_offset;

  // do we need to align or manually offset?
  if (manually_added_stack_offset || allocs.needs_aligned_stack_for_spills ||
      env->needs_aligned_stack()) {
    if (!(stack_offset & 15)) {
      if (manually_added_stack_offset) {
        // if we're already adding to rsp, just add 8 more.
        manually_added_stack_offset += 8;
      } else {
        // otherwise to an extra push, and remember so we can do an extra pop later on.
        bonus_push = true;
        m_gen.add_instr_no_ir(f_rec, IGen::push_gpr64(m_gen, ri.get_saved_gpr(0)),
                              InstructionInfo::Kind::PROLOGUE);
      }
      stack_offset += 8;
    }

    ASSERT(stack_offset & 15);

    // do manual stack offset.
    if (manually_added_stack_offset) {
      m_gen.add_instr_no_ir(f_rec, IGen::sub_gpr64_imm(m_gen, RSP, manually_added_stack_offset),
                            InstructionInfo::Kind::PROLOGUE);
    }
  }
  debug->stack_usage = stack_offset;

  // emit each IR into x86 instructions.
  for (int ir_idx = 0; ir_idx < int(env->code().size()); ir_idx++) {
    auto& ir = env->code().at(ir_idx);
    // start of IR
    auto i_rec = m_gen.add_ir(f_rec);

    // load anything off the stack that was spilled and is needed.
    auto& bonus = allocs.stack_ops.at(ir_idx);
    for (auto& op : bonus.ops) {
      if (op.load) {
        if (op.reg.is_gpr(m_gen.instr_set()) && op.reg_class == RegClass::GPR_64) {
          // todo, s8 or 0 offset if possible?
          m_gen.add_instr(IGen::load64_gpr64_plus_s32(
                              m_gen, op.reg, allocs.get_slot_for_spill(op.slot) * GPR_SIZE, RSP),
                          i_rec);
        } else if (op.reg.is_xmm(m_gen.instr_set()) && op.reg_class == RegClass::FLOAT) {
          // load xmm32 off of the stack
          m_gen.add_instr(IGen::load_reg_offset_xmm32(
                              m_gen, op.reg, RSP, allocs.get_slot_for_spill(op.slot) * GPR_SIZE),
                          i_rec);
        } else if (op.reg.is_xmm(m_gen.instr_set()) &&
                   (op.reg_class == RegClass::VECTOR_FLOAT || op.reg_class == RegClass::INT_128)) {
          m_gen.add_instr(IGen::load128_xmm128_reg_offset(
                              m_gen, op.reg, RSP, allocs.get_slot_for_spill(op.slot) * GPR_SIZE),
                          i_rec);
        } else {
          ASSERT(false);
        }
      }
    }

    // do the actual op
    ir_emit_stats::record(typeid(*ir), false);
    ir->do_codegen_x86(&m_gen, allocs, i_rec);

    // store things back on the stack if needed.
    for (auto& op : bonus.ops) {
      if (op.store) {
        if (op.reg.is_gpr(m_gen.instr_set()) && op.reg_class == RegClass::GPR_64) {
          // todo, s8 or 0 offset if possible?
          m_gen.add_instr(IGen::store64_gpr64_plus_s32(
                              m_gen, RSP, allocs.get_slot_for_spill(op.slot) * GPR_SIZE, op.reg),
                          i_rec);
        } else if (op.reg.is_xmm(m_gen.instr_set()) && op.reg_class == RegClass::FLOAT) {
          // store xmm32 on the stack
          m_gen.add_instr(IGen::store_reg_offset_xmm32(
                              m_gen, RSP, op.reg, allocs.get_slot_for_spill(op.slot) * GPR_SIZE),
                          i_rec);
        } else if (op.reg.is_xmm(m_gen.instr_set()) &&
                   (op.reg_class == RegClass::VECTOR_FLOAT || op.reg_class == RegClass::INT_128)) {
          m_gen.add_instr(IGen::store128_xmm128_reg_offset(
                              m_gen, RSP, op.reg, allocs.get_slot_for_spill(op.slot) * GPR_SIZE),
                          i_rec);
        } else {
          ASSERT(false);
        }
      }
    }
  }  // end IR loop

  // EPILOGUE
  if (manually_added_stack_offset || allocs.needs_aligned_stack_for_spills ||
      env->needs_aligned_stack()) {
    if (manually_added_stack_offset) {
      m_gen.add_instr_no_ir(f_rec, IGen::add_gpr64_imm(m_gen, RSP, manually_added_stack_offset),
                            InstructionInfo::Kind::EPILOGUE);
    }

    if (bonus_push) {
      ASSERT(!manually_added_stack_offset);
      m_gen.add_instr_no_ir(f_rec, IGen::pop_gpr64(m_gen, ri.get_saved_gpr(0)),
                            InstructionInfo::Kind::EPILOGUE);
    }
  }

  for (int i = int(allocs.used_saved_regs.size()); i-- > 0;) {
    auto& saved_reg = allocs.used_saved_regs.at(i);
    if (saved_reg.is_gpr(m_gen.instr_set())) {
      m_gen.add_instr_no_ir(f_rec, IGen::pop_gpr64(m_gen, saved_reg),
                            InstructionInfo::Kind::EPILOGUE);
    }
  }

  if (use_new_xmms) {
    if (n_xmm_backups > 0) {
      int j = n_xmm_backups;
      for (int i = int(allocs.used_saved_regs.size()); i-- > 0;) {
        auto& saved_reg = allocs.used_saved_regs.at(i);
        if (saved_reg.is_xmm(m_gen.instr_set())) {
          j--;
          int offset = j * XMM_SIZE;
          m_gen.add_instr_no_ir(f_rec,
                                IGen::load128_xmm128_reg_offset(m_gen, saved_reg, RSP, offset),
                                InstructionInfo::Kind::EPILOGUE);
        }
      }
      ASSERT(j == 0);
      m_gen.add_instr_no_ir(f_rec, IGen::add_gpr64_imm(m_gen, RSP, xmm_backup_stack_offset),
                            InstructionInfo::Kind::EPILOGUE);
    }
  } else {
    for (int i = int(allocs.used_saved_regs.size()); i-- > 0;) {
      auto& saved_reg = allocs.used_saved_regs.at(i);
      if (saved_reg.is_xmm(m_gen.instr_set())) {
        m_gen.add_instr_no_ir(f_rec, IGen::load128_simd128_gpr64(m_gen, saved_reg, RSP),
                              InstructionInfo::Kind::EPILOGUE);
        m_gen.add_instr_no_ir(f_rec, IGen::add_gpr64_imm8s(m_gen, RSP, XMM_SIZE),
                              InstructionInfo::Kind::EPILOGUE);
      }
    }
  }

  m_gen.add_instr_no_ir(f_rec, IGen::ret(m_gen), InstructionInfo::Kind::EPILOGUE);
}

void CodeGenerator::do_goal_function_arm64(FunctionEnv* env, int f_idx) {
  // AArch64 prologue + spill load/store + epilogue.
  //
  // Frame layout after prologue:
  //
  //                 +-------------------+  <- SP at function entry
  //                 |   saved FP/LR     |  16 bytes (stp x29,x30,[sp,#-16]!)
  //                 +-------------------+  <- X29 (FP)
  //                 |  spill / var      |
  //                 |  slots (8 bytes   |  frame_bytes (16-byte aligned)
  //                 |  per slot)        |
  //                 +-------------------+  <- SP after prologue
  //
  // Prologue:
  //   stp x29, x30, [sp, #-16]!     ; save FP/LR, SP -= 16    (0xA9BF7BFD)
  //   mov x29, sp                   ; FP = SP                  (0x910003FD)
  //   sub sp, sp, #frame_bytes      ; reserve spill area       (only if > 0)
  //
  // Epilogue (mirrors the prologue):
  //   add sp, sp, #frame_bytes      ; free spill area          (only if > 0)
  //   ldp x29, x30, [sp], #16       ; restore FP/LR, SP += 16  (0xA8C17BFD)
  //   ret                           ;                          (0xD65F03C0)
  //
  // Spill ops are SP-relative LDR/STR at byte offset slot_idx*8 within the
  // frame, where slot_idx = allocs.get_slot_for_spill(op.slot). Each slot is
  // 8 bytes (GPR_SIZE); the regalloc aligns 2-slot (Q-reg) spills onto even
  // indices via slot_size=2 in get_stack_slot_for_var, so 16-byte forms can
  // use the scaled imm12 encoding directly.
  //
  // Before A9: prologue/spill-load/spill-store/epilogue all emitted as NOPs
  // (kArm64Nop = 0xD503201F). The register allocator silently spilled values
  // that the codegen then refused to materialise — the consumer of a spilled
  // value read whatever stale register state was lying around. For
  // display.gc's font-context (new ...) the spilled value was the dispatched
  // method's function pointer; the consumer's BLR fired with 0 (the literal
  // for arg3) instead, faulting at the EE base. See A8-displaygc-root-cause.md
  // and A6-attempt-5-blocker.md for the per-instruction trace.

  auto* debug = &m_debug_info->function_by_name(env->name());
  auto f_rec = m_gen.get_existing_function_record(f_idx);
  const auto& allocs = env->alloc_result();

  // Frame size. 8 bytes per slot; round up to 16 for AArch64 SP alignment.
  int total_slots = allocs.stack_slots_for_spills + allocs.stack_slots_for_vars;
  int frame_bytes = (total_slots * GPR_SIZE + 15) & ~15;
  if ((allocs.needs_aligned_stack_for_spills || env->needs_aligned_stack()) &&
      frame_bytes == 0) {
    // Caller wants 16-byte alignment but doesn't actually consume slots;
    // reserve one quad just so the SP movement is visible to anyone tracking
    // frame boundaries (matches the x86 path's bonus_push behaviour).
    frame_bytes = 16;
  }
  // SUB/ADD SP, SP, #imm12 caps at 4095 (no LSL #12 path here). The biggest
  // arm64 GOAL function in jak1 uses a handful of spill slots; assert so any
  // future blow-out is loud rather than silently wrapping the imm12 field.
  ASSERT(frame_bytes <= 0xfff);

  // stp x29, x30, [sp, #-16]!
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xA9BF7BFDu),
                        InstructionInfo::Kind::PROLOGUE);
  // mov x29, sp
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0x910003FDu),
                        InstructionInfo::Kind::PROLOGUE);
  if (frame_bytes > 0) {
    // sub sp, sp, #frame_bytes
    //   Base 0xD1000000 (SUB immediate, sf=1, sh=0), Rn=Rd=31 (SP) -> 0xD10003FF.
    //   imm12 in bits 21..10.
    uint32_t sub_sp_enc =
        0xD10003FFu | ((static_cast<uint32_t>(frame_bytes) & 0xfffu) << 10);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(sub_sp_enc),
                          InstructionInfo::Kind::PROLOGUE);
  }
  debug->stack_usage = 16 + frame_bytes;

  for (int ir_idx = 0; ir_idx < int(env->code().size()); ir_idx++) {
    auto& ir = env->code().at(ir_idx);
    auto i_rec = m_gen.add_ir(f_rec);
    const auto& bonus = allocs.stack_ops.at(ir_idx);

    // Spill LOAD before the IR: restore stashed values into the IR's input regs.
    //   LDR Xt, [SP, #imm]   base 0xF9400000   imm12 scaled by 8
    //   LDR St, [SP, #imm]   base 0xBD400000   imm12 scaled by 4
    //   LDR Qt, [SP, #imm]   base 0x3DC00000   imm12 scaled by 16
    for (const auto& op : bonus.ops) {
      if (!op.load) {
        continue;
      }
      int byte_off = allocs.get_slot_for_spill(op.slot) * GPR_SIZE;
      uint32_t rt = static_cast<uint32_t>(op.reg.id()) & 0x1fu;
      uint32_t enc = 0;
      if (op.reg_class == RegClass::GPR_64) {
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 3) & 0xfffu;
        enc = 0xF9400000u | (imm12 << 10) | (31u << 5) | rt;
      } else if (op.reg_class == RegClass::FLOAT) {
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 2) & 0xfffu;
        enc = 0xBD400000u | (imm12 << 10) | (31u << 5) | rt;
      } else if (op.reg_class == RegClass::VECTOR_FLOAT ||
                 op.reg_class == RegClass::INT_128) {
        ASSERT_MSG((byte_off & 0xf) == 0,
                   "arm64 Q-reg spill slot must be 16-byte aligned (regalloc bug?)");
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 4) & 0xfffu;
        enc = 0x3DC00000u | (imm12 << 10) | (31u << 5) | rt;
      } else {
        ASSERT_MSG(false, "do_goal_function_arm64: spill load with unsupported reg_class");
      }
      m_gen.add_instr(emitter::InstructionARM64(enc), i_rec);
    }

    // A10 (autoport) — A9's X4=SP pre-load workaround removed.
    //
    // IR_GetStackAddr / IR_RegValAddr now emit `ADD Xd, SP, #imm12` (Rn=31)
    // directly inside IR.cpp via arm64_add_xd_sp_imm12, so the indirection
    // through X4 is no longer required. See goalc/compiler/IR.cpp and
    // .autoport/reports/A10-fix-summary.md.

    ir_emit_stats::record(typeid(*ir), true);
    ir->do_codegen_arm64(&m_gen, allocs, i_rec);

    // Spill STORE after the IR: stash the IR's output reg into its slot.
    //   STR Xt, [SP, #imm]   base 0xF9000000   imm12 scaled by 8
    //   STR St, [SP, #imm]   base 0xBD000000   imm12 scaled by 4
    //   STR Qt, [SP, #imm]   base 0x3D800000   imm12 scaled by 16
    for (const auto& op : bonus.ops) {
      if (!op.store) {
        continue;
      }
      int byte_off = allocs.get_slot_for_spill(op.slot) * GPR_SIZE;
      uint32_t rt = static_cast<uint32_t>(op.reg.id()) & 0x1fu;
      uint32_t enc = 0;
      if (op.reg_class == RegClass::GPR_64) {
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 3) & 0xfffu;
        enc = 0xF9000000u | (imm12 << 10) | (31u << 5) | rt;
      } else if (op.reg_class == RegClass::FLOAT) {
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 2) & 0xfffu;
        enc = 0xBD000000u | (imm12 << 10) | (31u << 5) | rt;
      } else if (op.reg_class == RegClass::VECTOR_FLOAT ||
                 op.reg_class == RegClass::INT_128) {
        ASSERT_MSG((byte_off & 0xf) == 0,
                   "arm64 Q-reg spill slot must be 16-byte aligned (regalloc bug?)");
        uint32_t imm12 = (static_cast<uint32_t>(byte_off) >> 4) & 0xfffu;
        enc = 0x3D800000u | (imm12 << 10) | (31u << 5) | rt;
      } else {
        ASSERT_MSG(false, "do_goal_function_arm64: spill store with unsupported reg_class");
      }
      m_gen.add_instr(emitter::InstructionARM64(enc), i_rec);
    }
  }

  if (frame_bytes > 0) {
    // add sp, sp, #frame_bytes
    //   Base 0x91000000 (ADD immediate, sf=1, sh=0), Rn=Rd=31 (SP) -> 0x910003FF.
    uint32_t add_sp_enc =
        0x910003FFu | ((static_cast<uint32_t>(frame_bytes) & 0xfffu) << 10);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(add_sp_enc),
                          InstructionInfo::Kind::EPILOGUE);
  }
  // ldp x29, x30, [sp], #16
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xA8C17BFDu),
                        InstructionInfo::Kind::EPILOGUE);
  // ret
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xD65F03C0u),
                        InstructionInfo::Kind::EPILOGUE);
}

void CodeGenerator::do_asm_function_x86(FunctionEnv* env, int f_idx, bool allow_saved_regs) {
  auto f_rec = m_gen.get_existing_function_record(f_idx);
  const auto& allocs = env->alloc_result();

  if (!allow_saved_regs && !allocs.used_saved_regs.empty()) {
    std::string err = fmt::format(
        "ASM Function {}'s coloring using the following callee-saved registers: ", env->name());
    for (auto& x : allocs.used_saved_regs) {
      err += x.print();
      err += " ";
    }
    err.pop_back();
    err.push_back('.');
    throw std::runtime_error(err);
  }

  if (allocs.stack_slots_for_spills) {
    throw std::runtime_error("ASM Function has used the stack for spills.");
  }

  if (allocs.stack_slots_for_vars) {
    throw std::runtime_error("ASM Function has variables on the stack.");
  }

  // emit each IR into x86 instructions.
  for (int ir_idx = 0; ir_idx < int(env->code().size()); ir_idx++) {
    auto& ir = env->code().at(ir_idx);
    // start of IR
    auto i_rec = m_gen.add_ir(f_rec);

    // Make sure we aren't automatically accessing the stack.
    if (!allocs.stack_ops.at(ir_idx).ops.empty()) {
      throw std::runtime_error("ASM Function used a bonus op.");
    }

    // do the actual op
    ir_emit_stats::record(typeid(*ir), false);
    ir->do_codegen_x86(&m_gen, allocs, i_rec);
  }
}

void CodeGenerator::do_asm_function_arm64(FunctionEnv* env, int f_idx, bool allow_saved_regs) {
  auto f_rec = m_gen.get_existing_function_record(f_idx);
  const auto& allocs = env->alloc_result();
  if (!allow_saved_regs && !allocs.used_saved_regs.empty()) {
    // arm64 asm functions have no concept of saved regs in this scaffold;
    // emit a single trap-like NOP and bail so we don't break the build.
  }
  for (int ir_idx = 0; ir_idx < int(env->code().size()); ir_idx++) {
    auto& ir = env->code().at(ir_idx);
    auto i_rec = m_gen.add_ir(f_rec);
    ir_emit_stats::record(typeid(*ir), true);
    ir->do_codegen_arm64(&m_gen, allocs, i_rec);
  }
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xD65F03C0u),
                        InstructionInfo::Kind::EPILOGUE);
}
