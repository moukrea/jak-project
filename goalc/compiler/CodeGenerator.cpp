/*!
 * @file CodeGenerator.cpp
 * Generate object files from a FileEnv using an emitter::ObjectGenerator.
 * Populates a DebugInfo.
 * Currently owns the logic for emitting the function prologues/epilogues and stack spill ops.
 */

#include "CodeGenerator.h"

#include <algorithm>
#include <cstdlib>
#if __has_include(<cxxabi.h>)
#include <cxxabi.h>
#define OG_HAVE_CXXABI 1
#endif
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
#ifdef OG_HAVE_CXXABI
  int status = 0;
  char* dem = abi::__cxa_demangle(mangled, nullptr, nullptr, &status);
  std::string out = (status == 0 && dem) ? std::string(dem) : std::string(mangled);
  std::free(dem);
  return out;
#else
  // MSVC's runtime has no cxxabi.h; the raw type_info name (used for the
  // IR-op census printout only) is good enough there.
  return std::string(mangled);
#endif
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

// A24 — OG_X30_TRACE_EMIT: env-gated AT GOALC COMPILE TIME post-LDP X30
// stack-range tracer. A23's call_r64 BLR-target tracer fired ZERO times
// across 61204 instrumented sites + a complete 216-link-finish boot run,
// falsifying the H2-via-call_r64 hypothesis ("an IR_FunctionCall's
// m_func holds a stack-form GOAL ptr and call_r64's BLR jumps to a
// stack address"). The remaining mechanism is RET-to-corrupted-LR: some
// STR/STP inside a function body corrupts the function's X29/X30 save
// slot, and the function's epilogue `LDP X29, X30, [SP], #16; RET`
// loads the corrupted X30 and propagates the stack address to PC. The
// observed bytes at the crash window (A23 REG-BYTE-DUMP @ X12) decode
// as the canonical aarch64 goalc function epilogue
// (`A8C17BFD = LDP X29, X30, [SP], #16`; `D65F03C0 = RET`).
//
// When OG_X30_TRACE_EMIT is set in goalc's environment at compile time,
// the arm64 function-epilogue emit inserts a 5-instruction check
// sequence between the LDP and the RET:
//
//   LDP X29, X30, [SP], #16        ; restore FP/LR (potentially corrupted)
//   SUB X17, X30, X15              ; X17 = X30's GOAL-form (host - ee_base)
//   MOVZ X16, #0x0700, LSL #16     ; X16 = 0x07000000 (stack-range floor,
//                                  ;        identical to A23's threshold)
//   CMP X17, X16                   ; flags from (X30_GOAL - threshold)
//   B.LO ret_ok                    ; X30_GOAL < threshold → normal RET
//   UDF #0x1EF0                    ; SIGILL: A24 epilogue trap tag
//   ret_ok:
//   RET                            ; PC := X30
//
// X16/X17 are AAPCS intra-procedure call scratch registers; the caller
// has no surviving live values in them across a RET boundary. The
// threshold 0x07000000 matches A23's choice — any legitimate GOAL fn-ptr
// at the boot ceiling has GOAL offset < ~0x02000000, so any X30 with
// offset >= 0x07000000 is in the GOAL stack range and signals an
// epilogue restoring a corrupted save-slot value.
//
// SIGILL handler decode (linux_arm64_main.cpp):
//   - Read u32 at uc->uc_mcontext.pc → must be UDF (top 16 bits 0).
//   - imm16 = low 16 bits. If imm16 == 0x1EF0, this is our tag (distinct
//     from A23's 0x1EE0..0x1EFF range, which reserved the low 5 bits
//     for the BLR target reg; A24 uses X30 unconditionally so the tag
//     is a single value).
//   - X30 = uc->uc_mcontext.regs[30], X15 = uc->uc_mcontext.regs[15].
//   - Print EPILOGUE-X30-STACK: emit_pc=<pc> x30=<host>
//                               goal_off=<host - X15> x15=<X15>
//                               caller_lr=<lr>
//
// The PC at SIGILL is the address of the UDF itself, which is one
// instruction past the corrupted LDP. Cross-referencing emit_pc to a
// GOAL function uses the klink symbol table (link blocks recorded at
// CGO load time) or offline disasm of the loaded CGOs.
//
// CGO drift:
//   - OG_X30_TRACE_EMIT unset (default): byte-identical to A23 baseline.
//   - OG_X30_TRACE_EMIT=1: each goalc-emitted GOAL function gains 5×4 =
//     20 B of epilogue check. A fresh A24-baseline-arm64-cgo-hashes.txt
//     captures the new CGO shape.
//
// The gate uses a function-local static (evaluated once per goalc
// process), so the env var only needs to be set at goalc-launch time.
static bool epilogue_x30_trace_emit_enabled() {
  static const bool enabled = []() {
    const char* env = std::getenv("OG_X30_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}

// F1f — x86 "push RA; jmp func" → arm64 "pop RA into X30; BR" marking
// (the A34 contract). Scans the IR list for IR_JumpReg preceded by an
// IR_AsmPush with only value-preserving register ops in between, and
// marks the jump so IR_JumpReg::do_codegen_arm64 pops the freshly-pushed
// return address into X30 before the BR.
//
// A34 wired this scan into do_asm_function_arm64 only; its site inventory
// listed gstate.gc:372 (enter-state's `.push return-from-thread-dead;
// .jr func`) as covered, but enter-state is a NORMAL defun — compiled by
// do_goal_function_arm64, which never ran the scan. Consequence on arm64:
// a state `code` function entered through a direct `(go ...)` (enter-state
// branch 3: main thread of the current process) kept a stale X30, so when
// that state code RETURNED (process death path: the pushed
// return-from-thread-dead trampoline must run deactivate) it instead
// RET'd into the middle of enter-state's body, executed enter-state's
// epilogue against the freshly-reset (zero-filled) process stack, and
// LDP'd X29=0/X30=0 → RET → pc=0/fp=0/lr=0 — the F1d §7b load-game
// restore crash signature (2/2 deterministic).
static void mark_push_jr_pop_ra_arm64(FunctionEnv* env, bool no_sp_adjust = false) {
  for (int jr_idx = 0; jr_idx < int(env->code().size()); jr_idx++) {
    auto* jr = dynamic_cast<IR_JumpReg*>(env->code().at(jr_idx).get());
    if (!jr) {
      continue;
    }
    for (int k = jr_idx - 1; k >= 0; k--) {
      IR* prev = env->code().at(k).get();
      if (dynamic_cast<IR_RegSetAsm*>(prev) || dynamic_cast<IR_AsmAdd*>(prev)) {
        // Plain `.mov reg, reg` / `.add reg, off` — value-preserving
        // w.r.t. [SP] in all frozen jak1 sites (none of them target SP
        // between the RA push and the .jr; SP-targeting moves only occur
        // BEFORE the push, e.g. enter-state's stack reset).
        continue;
      }
      if (dynamic_cast<IR_AsmPush*>(prev)) {
        // no_sp_adjust: deliver the RA into X30 with LDR X30,[SP] (no SP move),
        // for enter-state's fall-off-the-end RETURN path — see the call site
        // in do_goal_function_arm64 and IR_JumpReg::mark_arm64_pop_ra_no_sp.
        if (no_sp_adjust) {
          jr->mark_arm64_pop_ra_no_sp();
        } else {
          jr->mark_arm64_pop_ra();
        }
      }
      break;
    }
  }
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
  //   [A24 X30 stack-range check, only when OG_X30_TRACE_EMIT is set]
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
  // A40: bank the GOAL-callee-saved XMMs this function actually uses,
  // mirroring do_goal_function_x86's xmm backup. GOAL's ABI promises
  // xmm8-15 survive calls; they map to V24-V31 on arm64, which AAPCS
  // treats as caller-saved — without these saves, any caller's float
  // parked in xmm8-15 across a call to this function came back
  // clobbered (the print-game-text origin.y freeze that swept 12 MB of
  // GOAL memory and smashed draw-string at boot frame ~522). Callee-side
  // is the cheap shape: only users pay, once per invocation — the
  // call-site bracket variant cost 128 B of stack per call depth and
  // blew small process suspend backups (thread-suspend's (break) at
  // title-vis) plus ~2 MB of global heap.
  //   str qN, [sp, #-16]!  = 0x3C9F0FE0 | rt   (NDK-clang verified)
  //   ldr qN, [sp], #16    = 0x3CC107E0 | rt
  // Note: Register::is_xmm(ARM64) is hardwired false (the arm64 encoders
  // key off raw ids), so classify by the x86-model id range the
  // allocator itself uses: XMM0..XMM15 = ids 16..31 → V16..V31.
  std::vector<uint32_t> a40_saved_xmm_rt;
  for (auto& saved_reg : allocs.used_saved_regs) {
    if (saved_reg.id() >= emitter::XMM0 && saved_reg.id() <= emitter::XMM15) {
      uint32_t rt = static_cast<uint32_t>(saved_reg.id()) & 0x1fu;
      a40_saved_xmm_rt.push_back(rt);
      m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0x3C9F0FE0u | rt),
                            InstructionInfo::Kind::PROLOGUE);
    }
  }
  if (frame_bytes > 0) {
    // sub sp, sp, #frame_bytes
    //   Base 0xD1000000 (SUB immediate, sf=1, sh=0), Rn=Rd=31 (SP) -> 0xD10003FF.
    //   imm12 in bits 21..10.
    uint32_t sub_sp_enc =
        0xD10003FFu | ((static_cast<uint32_t>(frame_bytes) & 0xfffu) << 10);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(sub_sp_enc),
                          InstructionInfo::Kind::PROLOGUE);
  }
  debug->stack_usage = 16 + frame_bytes + 16 * static_cast<int>(a40_saved_xmm_rt.size());

  // G1 — REVERTED the F1f broadening of the pop-RA scan into normal defuns.
  //
  // F1f ran mark_push_jr_pop_ra_arm64() here so enter-state (gstate.gc:372,
  // the lone `.push RA; .jr` in a non-asm-func) would pop the pushed
  // return-from-thread-dead trampoline into X30 at the direct-(go) transfer.
  // That fixed the new-game-cinematic process-death RETURN, but it REGRESSED
  // the title: with pop-RA, `LDR X30,[SP],#16` advances SP by 16 past the
  // pushed RA, so the state `code` enters its suspend/resume loop on a stack
  // 16 bytes higher than the x86 contract. For the title's attract states
  // (which suspend forever instead of returning) the shifted layout
  // propagates through thread-suspend/thread-resume and a later kernel
  // dispatch reads a null function-pointer slot — `BLR X9` with X9 = EE+0
  // (GOAL null) at kernel code ~0x18eed8 → pc=0x7f00000000 (EE base) →
  // SIGSEGV (run F1f-25: stable to frame 252, then crash; the reported
  // fault=0x7effffffec is a SECONDARY fault inside gk_sigsegv_diag's
  // A37-PCWIN read of [pc&~15]-32 .. when the original pc≈EE base).
  //
  // e1f35fc0c (no pop-RA on enter-state) flies the title indefinitely, so the
  // PRIORITY-FLOOR fix is to restore that: enter-state keeps a stale X30 on
  // the direct-(go) path (correct for suspend-looping states; the new-game
  // RETURN path stays the documented G2 residual — see G1-fix-summary.md).
  // The asm-func sites (reset-and-call, set-to-run-bootstrap) still run the
  // scan via do_asm_function_arm64 — their A34 contract is unchanged.
  //
  // Gcollectible-state — re-enable the pop-RA for enter-state ONLY, using the
  // NO-SP-ADJUST encoding (LDR X30,[SP], not LDR X30,[SP],#16). enter-state is
  // the lone non-asm-func with a `.push return-from-thread-dead; .jr code`
  // trampoline (gstate.gc:376-381; the other `.push;.jr` sites are asm-funcs).
  // Without this, a state :code that FALLS OFF THE END (e.g. crate `die`, which
  // ends with `(suspend-for (seconds 5))` and returns) RETs to a stale X30
  // instead of the deactivate trampoline, so the process is never deactivated:
  // the broken crate re-runs its `die` state every ~4s forever, re-dropping its
  // pickup ("infinite green eco") and re-spawning its debris ("debris flicker").
  // The no-SP-adjust form leaves SP byte-identical to the current stale-X30 path
  // for suspend-LOOPING states (which never return), so it cannot reproduce the
  // F1f +16 title regression that forced the G1 revert above — it only changes
  // the RETURN target of fall-off-the-end :code, which is exactly the bug.
  if (env->name() == "enter-state") {
    mark_push_jr_pop_ra_arm64(env, /*no_sp_adjust=*/true);
  }

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
  // A40: restore the banked callee-saved XMMs (reverse push order).
  for (auto it = a40_saved_xmm_rt.rbegin(); it != a40_saved_xmm_rt.rend(); ++it) {
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0x3CC107E0u | *it),
                          InstructionInfo::Kind::EPILOGUE);
  }
  // ldp x29, x30, [sp], #16
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xA8C17BFDu),
                        InstructionInfo::Kind::EPILOGUE);
  if (epilogue_x30_trace_emit_enabled()) {
    // A24 OG_X30_TRACE — emit-time post-LDP stack-range check before RET.
    // Uses SIGNED comparison (B.LT) so the "return-to-C++ binary" case
    // (X30 < X15 → SUB wraps to a large unsigned value with the sign bit
    // set, i.e. a signed-negative X17) skips the UDF correctly. The
    // "return-to-GOAL heap" case (X30 - X15 < 0x07000000) also skips via
    // signed less-than. Only the "return-to-stack-range" case
    // (0x07000000 <= X30 - X15 < ~64 GB) fires the UDF — exactly the
    // corruption shape A21/A23 observed (X30 = 0x212afffe84, GOAL form
    // = 0x07fffe84).
    //
    // The unsigned-LO path used in A23's call_r64 tracer works there
    // because the BLR target is always materialised as `ADD freg, freg,
    // X15`, i.e. freg >= X15 by construction. At a function epilogue,
    // X30 is whatever the prologue saved — which is the LR of the
    // caller, and the caller may be C++ (e.g. _call_goal_asm_arm64) at
    // an address < X15. Empirically (first qemu_repro under
    // OG_X30_TRACE_EMIT=1), the very first GOAL-from-C++ return at
    // emit_pc=0x2126ab82b8 had X30=0x2bb3e8 (a gk binary text address)
    // and the unsigned-LO check false-fired. B.LT eliminates this.
    //
    // SUB X17, X30, X15:
    //   0xCB000000 | (Rm<<16) | (Rn<<5) | Rd, Rm=15, Rn=30, Rd=17
    //   = 0xCB000000 | 0x000F0000 | 0x000003C0 | 0x11 = 0xCB0F03D1
    //   → X17 = X30 - X15 (signed: GOAL-form offset; wraps to negative
    //                       when X30 < X15)
    constexpr uint32_t kSubX17X30X15 = 0xCB0F03D1u;
    // MOVZ X16, #0x0700, LSL #16:
    //   0xD2800000 | (hw<<21) | (imm16<<5) | Rd, hw=1, imm16=0x0700, Rd=16
    //   = 0xD2800000 | 0x200000 | 0xE000 | 16 = 0xD2A0E010
    //   → X16 = 0x0000_0000_0700_0000 (GOAL-offset stack-range floor,
    //     identical to A23's threshold for tracer comparability)
    constexpr uint32_t kMovzX16Floor = 0xD2A0E010u;
    // CMP X17, X16 = SUBS XZR, X17, X16:
    //   0xEB000000 | (Rm<<16) | (Rn<<5) | Rd, Rm=16, Rn=17, Rd=31
    //   = 0xEB100000 | 0x220 | 0x1F = 0xEB10023F
    constexpr uint32_t kCmpX17X16 = 0xEB10023Fu;
    // B.LT +8 (= imm19 = +2 instructions, skip the UDF):
    //   0x54000000 | (imm19<<5) | cond, cond=LT=11(0xB), imm19=2
    //   = 0x54000000 | 0x40 | 0xB = 0x5400004B
    //   Signed-less-than: branches when X17 is signed-less-than X16
    //   (covers both small-positive heap returns AND
    //    wrapped-negative-from-C-binary returns).
    constexpr uint32_t kBltSkipUdf = 0x5400004Bu;
    // UDF #0x1EF0: 32-bit encoding = imm16 (low 16 bits).
    //   Distinct from A23's 0x1EE0..0x1EFF range. The handler matches on
    //   the exact constant; X30's reg id is implicit (always X30).
    constexpr uint32_t kUdfEpilogueX30 = 0x00001EF0u;
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kSubX17X30X15),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kMovzX16Floor),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kCmpX17X16),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kBltSkipUdf),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kUdfEpilogueX30),
                          InstructionInfo::Kind::EPILOGUE);
  }
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

  // A28 — Emulate x86 call/ret semantics on arm64.
  //
  // GOAL asm-funcs (catch-frame ctor, throw-dispatch, reset-and-call,
  // return-from-thread, thread-suspend, thread-resume, enter-state's RA
  // overwrite path) assume x86 semantics:
  //   - the caller's `call` pushed the return address onto the stack
  //   - the body can `.pop temp` to read it (or `.push temp` to install a
  //     custom RA)
  //   - `(.ret)` pops the top-of-stack and jumps to it
  //
  // arm64 differs: BL/BLR write LR (X30) instead of pushing RA, and RET uses
  // X30 instead of popping. Without compensation:
  //   - `(.pop temp)` at the head of an asm-func reads garbage instead of the
  //     return address (thread-suspend stores garbage as this.pc → next
  //     resume jumps to it)
  //   - `(.ret)` in throw-dispatch ignores the catch-frame's saved RA pushed
  //     by `(.push temp)` and returns to the throw function instead → the
  //     throw never unwinds, the catch-frame chain pop runs but the protected
  //     code never resumes, and the kernel hangs
  //
  // The compensation is a STR X30 prologue + a matching LDR X30 in
  // IR_AsmRet::do_codegen_arm64. Together they reproduce the x86 contract:
  //   - entry: save X30 (= caller's RA from BLR) at [SP-16]; SP -= 16. Now
  //     [SP] holds the RA, exactly as if `call` had pushed it.
  //   - `(.pop temp)` (`ldr Xt, [SP], #16`) reads that RA — same as x86 pop.
  //   - `(.push temp)` (`str Xt, [SP, #-16]!`) overwrites it with a custom
  //     target — same as x86 push.
  //   - `(.ret)` (now `ldr X30, [SP], #16; ret`) pops top-of-stack into X30
  //     and RETs — semantically the same as x86 `ret`.
  //
  // The catch-frame ctor's `.pop temp; .push temp` round-trip at gkernel.gc
  // lines 1475-1480 is the canonical case: it READS the saved RA into a
  // GOAL register, then puts it back so the stack stays balanced for the
  // eventual `(.ret)`. Throw-dispatch's `.pop; set! temp this.ra; .push;
  // .ret` at lines 1586-1592 OVERWRITES the saved RA with the catch-frame's
  // captured RA, so the `(.ret)` jumps back to the catch protectee instead
  // of to throw.
  //
  // Asm-funcs that don't actually return (e.g. reset-and-call ends with
  // `(.jr func)`) leak 16 bytes of stack via the prepend — harmless for the
  // one-shot trampoline kernel paths. The fall-through RET emitted below
  // (after the body loop) also leaks if reached, but no kernel asm-func
  // falls through.
  //
  // STR X30, [SP, #-16]! encoding (pre-index, 64-bit store):
  //   size=11 | 111 | V=0 | 00 | opc=00 | 0 | imm9=-16 | option=11 | Rn=31 | Rt=30
  //   = 0xF8000C00 | ((imm9 & 0x1FF) << 12) | (Rn << 5) | Rt
  //   imm9 = -16 = 0x1F0 in 9-bit two's complement
  //   = 0xF8000C00 | (0x1F0 << 12) | (31 << 5) | 30
  //   = 0xF81F0FFE
  constexpr uint32_t kStrX30PrependSP = 0xF81F0FFEu;
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kStrX30PrependSP),
                        InstructionInfo::Kind::PROLOGUE);

  // A34 — x86 "push RA; jmp func" pattern (the missing half of the A28
  // contract above). set-to-run-bootstrap / reset-and-call / enter-state
  // install a custom return address with `.push temp` and then tail-jump
  // into a GOAL function with `.jr func`. On x86 that function's final
  // `ret` pops the pushed word. arm64 GOAL functions return through the
  // register-RA contract (paired STP/LDP of X29/X30), so the pushed word
  // is NEVER consumed: the function returns to a stale X30 — the
  // return-from-thread-dead trampoline never runs, deactivate is skipped,
  // and the leaked stack word is popped later by an unrelated epilogue
  // with pp clobbered (on-device A34 crash: pc landed in
  // return-from-thread-dead with X13/pp = 0, SP = thread stack-top - 32 =
  // exactly the leaked trampoline slot; fault = EE-4 from (-> 0 type)).
  //
  // Faithful translation: when [SP] still holds the freshly-pushed RA at
  // the `.jr` (i.e. between the LAST `.push` and the `.jr` there are only
  // plain register moves / `.add reg, off` — no pops, rets, SP writes,
  // calls, or labels), pop it into X30 before the BR. The BR'd-to
  // function's prologue then saves the trampoline as its LR and its
  // epilogue returns there — byte-for-byte the x86 behavior.
  //
  // Site inventory (goal_src/jak1, frozen): 4 `.jr` sites total.
  //   gkernel.gc:535  reset-and-call        — .push RA; .add func off; .jr  → POP
  //   gkernel.gc:1858 set-to-run-bootstrap  — .push RA; 4×.mov; .add; .jr   → POP
  //   gstate.gc:372   enter-state           — .push RA; .jr                 → POP
  //   gkernel.gc:735  thread-resume         — pushes are kernel-context
  //     saves; symbol stores / field loads / SP writes intervene           → no match
  //
  // NOTE (F1f): enter-state at gstate.gc:372 is listed above but is NOT an
  // asm-func — it never reached this scan. The scan now lives in
  // mark_push_jr_pop_ra_arm64 and runs for BOTH function kinds (see
  // do_goal_function_arm64).
  mark_push_jr_pop_ra_arm64(env);

  for (int ir_idx = 0; ir_idx < int(env->code().size()); ir_idx++) {
    auto& ir = env->code().at(ir_idx);
    auto i_rec = m_gen.add_ir(f_rec);
    ir_emit_stats::record(typeid(*ir), true);
    ir->do_codegen_arm64(&m_gen, allocs, i_rec);
  }
  // A24 — env-gated post-asm-func-body X30 stack-range check, mirroring
  // do_goal_function_arm64's epilogue tracer. The fall-through RET below
  // is reached when an asm-func body doesn't itself end with a control-
  // flow instruction (the typical pattern is a `(.jr ...)` or `(.ret)`
  // body — see jak1/kernel/gkernel.gc — but a body that falls through
  // would use this RET). The same OG_X30_TRACE_EMIT env var controls all
  // four A24 surfaces (goalc epilogue, asm trampoline, inline trampoline,
  // and BR-target in jmp_r64).
  if (epilogue_x30_trace_emit_enabled()) {
    constexpr uint32_t kSubX17X30X15 = 0xCB0F03D1u;
    constexpr uint32_t kMovzX16Floor = 0xD2A0E010u;
    constexpr uint32_t kCmpX17X16 = 0xEB10023Fu;
    constexpr uint32_t kBltSkipUdf = 0x5400004Bu;
    constexpr uint32_t kUdfEpilogueX30 = 0x00001EF0u;
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kSubX17X30X15),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kMovzX16Floor),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kCmpX17X16),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kBltSkipUdf),
                          InstructionInfo::Kind::EPILOGUE);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kUdfEpilogueX30),
                          InstructionInfo::Kind::EPILOGUE);
  }
  m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xD65F03C0u),
                        InstructionInfo::Kind::EPILOGUE);
}
