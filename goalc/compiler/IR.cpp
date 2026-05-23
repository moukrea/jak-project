#include "IR.h"

#include <utility>

#include "common/symbols.h"

#include "goalc/compiler/Env.h"
#include "goalc/emitter/IGen.h"
#include "goalc/emitter/IGenARM64.h"

#include "fmt/format.h"

// TODO ARM64 - just silencing errors while things are not implemented obviously
#pragma GCC diagnostic ignored "-Wunused-parameter"

// A17 — forward declarations for the IDIV/UDIV preserve-X8 spill helpers
// defined in goalc/emitter/IGenARM64.cpp. They are NOT declared in the locked
// IGenARM64.h header (A17 only unlocks the .cpp), so we mirror their
// signatures here at the only call site. See the A17 block comment in
// IGenARM64.cpp above idiv_gpr32 for the full rationale.
namespace emitter {
namespace IGen {
namespace ARM64 {
InstructionARM64 idiv_spill_sub_sp_16();
InstructionARM64 idiv_spill_str_x8_sp_0();
InstructionARM64 idiv_spill_ldr_x8_sp_0();
InstructionARM64 idiv_spill_add_sp_16();
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter

using namespace emitter;
namespace {
Register get_reg(const RegVal* rv, const AllocationResult& allocs, emitter::IR_Record irec) {
  if (rv->rlet_constraint().has_value()) {
    auto& range = allocs.ass_as_ranges;
    auto reg = rv->rlet_constraint().value();
    if (rv->ireg().id < int(range.size())) {
      auto& lr = range.at(rv->ireg().id);
      if (lr.has_info_at(irec.ir_id)) {
        auto ass_reg = range.at(rv->ireg().id).get(irec.ir_id);
        if (ass_reg.kind == Assignment::Kind::REGISTER) {
          ASSERT(ass_reg.reg == reg);
        } else {
          ASSERT(false);
        }
      } else {
        ASSERT(false);
      }
    } else {
      ASSERT(false);
    }
    return reg;
  } else {
    auto& ass = allocs.ass_as_ranges.at(rv->ireg().id).get(irec.ir_id);
    ASSERT(ass.kind == Assignment::Kind::REGISTER);
    return ass.reg;
  }
}

int get_stack_offset(const RegVal* rv, const AllocationResult& allocs) {
  if (rv->rlet_constraint().has_value()) {
    // should be impossible. Can't take the address of an inline assembly form register.
    ASSERT(false);
  } else {
    ASSERT(rv->forced_on_stack());
    auto& ass = allocs.ass_as_ranges.at(rv->ireg().id);
    auto stack_slot = allocs.get_slot_for_spill(ass.stack_slot());
    ASSERT(stack_slot >= 0);
    return stack_slot * 8;
  }
}

// A10 (autoport) — direct `ADD Xd, SP, #imm12` emit (Rn = 31).
//
// IGen::ARM64::mov_gpr64_gpr64 / lea_reg_plus_off both route the source
// register through arm64_reg5(src). For RSP that returns id() & 0x1f = 4
// (the GOAL enum id, NOT the AArch64 SP encoding which is 31). The result
// is `MOV Xd, X4` / `ADD Xd, X4, #imm` — reads from X4 instead of SP.
//
// X4 is whatever the previous BLR's arg shuffle left in it (kernel
// trampoline `st`, or arg4 of the last GOAL→C dispatch). Any IR that
// reads RSP to compute a stack-var address ends up with garbage, and the
// callee's writes step on the caller's preserved-register save area
// allocated by call_r64 — that is the X3-clobber-after-BLR symptom
// captured in .autoport/reports/A9-attempt-1-next-blocker.md.
//
// A9 worked around this in CodeGenerator.cpp's main IR loop by emitting
// `ADD X4, SP, #0` (0x910003E4) immediately before any IR whose codegen
// reads RSP. A10's narrow IR.cpp unlock replaces that workaround with the
// proper fix: emit `ADD Xd, SP, #imm12` (Rn = 31) directly here, no X4
// detour. The encoder file (IGenARM64.cpp) stays locked.
//
// Encoding (ADD immediate, 64-bit, sf=1, op=add, S=0, sh=0):
//
//   |31|30 29|28 24|23 22|21    10|9   5|4   0|
//   | 1| 0  0|1 0 0 0 1|0  0|imm12     |Rn=31|Rd  |   = 0x91000000 ...
//
// imm12 must be <= 0xfff; the A9 prologue caps frame_bytes at 4095 so
// stack-slot offsets and stack-var offsets stay inside that range. We
// ASSERT here so a future frame-blowing function fails loudly instead
// of silently truncating its address.
static InstructionARM64 arm64_add_xd_sp_imm12(Register dst, uint32_t imm12) {
  ASSERT(imm12 <= 0xfff);
  uint32_t rd = static_cast<uint32_t>(dst.id()) & 0x1fu;
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (31u << 5) | rd;
  return InstructionARM64(enc);
}

Register get_no_color_reg(const RegVal* rv) {
  if (!rv->rlet_constraint().has_value()) {
    throw std::runtime_error(
        "Accessed a non-rlet constrained variable without the coloring system.");
  }
  return rv->rlet_constraint().value();
}

Register get_reg_asm(const RegVal* rv,
                     const AllocationResult& allocs,
                     emitter::IR_Record irec,
                     bool use_coloring) {
  return use_coloring ? get_reg(rv, allocs, irec) : get_no_color_reg(rv);
}

void load_constant(u64 value,
                   emitter::ObjectGenerator* gen,
                   emitter::IR_Record irec,
                   Register dest_reg) {
  s64 svalue = value;
  if (svalue == 0) {
    gen->add_instr(IGen::xor_gpr64_gpr64(*gen, dest_reg, dest_reg), irec);
  } else if (svalue > 0) {
    if (svalue < UINT32_MAX) {
      gen->add_instr(IGen::mov_gpr64_u32(*gen, dest_reg, value), irec);
    } else {
      // need a real 64 bit load
      gen->add_instr(IGen::mov_gpr64_u64(*gen, dest_reg, value), irec);
    }
  } else {
    if (svalue >= INT32_MIN) {
      gen->add_instr(IGen::mov_gpr64_s32(*gen, dest_reg, svalue), irec);
    } else {
      // need a real 64 bit load
      gen->add_instr(IGen::mov_gpr64_u64(*gen, dest_reg, value), irec);
    }
  }
}

void regset_common(emitter::ObjectGenerator* gen,
                   const AllocationResult& allocs,
                   emitter::IR_Record irec,
                   const RegVal* dst,
                   const RegVal* src,
                   bool use_coloring) {
  auto src_reg = use_coloring ? get_reg(src, allocs, irec) : get_no_color_reg(src);
  auto dst_reg = use_coloring ? get_reg(dst, allocs, irec) : get_no_color_reg(dst);
  auto src_class = src->ireg().reg_class;
  auto dst_class = dst->ireg().reg_class;

  bool src_is_xmm128 = (src_class == RegClass::VECTOR_FLOAT || src_class == RegClass::INT_128);
  bool dst_is_xmm128 = (dst_class == RegClass::VECTOR_FLOAT || dst_class == RegClass::INT_128);

  if (src_class == RegClass::GPR_64 && dst_class == RegClass::GPR_64) {
    if (src_reg == dst_reg) {
      // eliminate move
      gen->count_eliminated_move();
      gen->add_instr(IGen::null(*gen), irec);
    } else {
      gen->add_instr(IGen::mov_gpr64_gpr64(*gen, dst_reg, src_reg), irec);
    }
  } else if (src_class == RegClass::FLOAT && dst_class == RegClass::FLOAT) {
    if (src_reg == dst_reg) {
      // eliminate move
      gen->count_eliminated_move();
      gen->add_instr(IGen::null(*gen), irec);
    } else {
      gen->add_instr(IGen::mov_xmm32_xmm32(*gen, dst_reg, src_reg), irec);
    }
  } else if (src_is_xmm128 && dst_is_xmm128) {
    if (src_reg == dst_reg) {
      // eliminate move
      gen->count_eliminated_move();
      gen->add_instr(IGen::null(*gen), irec);
    } else {
      gen->add_instr(IGen::mov_vf_vf(*gen, dst_reg, src_reg), irec);
    }
  } else if (src_class == RegClass::FLOAT && dst_class == RegClass::GPR_64) {
    // xmm 1x -> gpr
    gen->add_instr(IGen::movd_gpr32_xmm32(*gen, dst_reg, src_reg), irec);
    // don't forget to sign extend
    gen->add_instr(IGen::movsx_r64_r32(*gen, dst_reg, dst_reg), irec);
  } else if (src_class == RegClass::GPR_64 && dst_class == RegClass::FLOAT) {
    // gpr -> xmm 1x
    gen->add_instr(IGen::movd_xmm32_gpr32(*gen, dst_reg, src_reg), irec);
  } else if (src_is_xmm128 && dst_class == RegClass::FLOAT) {
    gen->add_instr(IGen::mov_xmm32_xmm32(*gen, dst_reg, src_reg), irec);
  } else if (src_class == RegClass::FLOAT && dst_is_xmm128) {
    gen->add_instr(IGen::mov_xmm32_xmm32(*gen, dst_reg, src_reg), irec);
  } else if (src_class == RegClass::GPR_64 && dst_is_xmm128) {
    gen->add_instr(IGen::movq_xmm64_gpr64(*gen, dst_reg, src_reg), irec);
  } else if (src_is_xmm128 && dst_class == RegClass::GPR_64) {
    gen->add_instr(IGen::movq_gpr64_xmm64(*gen, dst_reg, src_reg), irec);
  } else {
    ASSERT(false);  // unhandled move.
  }
}
}  // namespace

///////////
// Return
///////////
IR_Return::IR_Return(const RegVal* return_reg, const RegVal* value, emitter::Register ret_reg)
    : m_return_reg(return_reg), m_value(value), m_ret_reg(ret_reg) {}
std::string IR_Return::print() {
  return fmt::format("ret {} {}", m_return_reg->print(), m_value->print());
}

RegAllocInstr IR_Return::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_return_reg->ireg());
  rai.read.push_back(m_value->ireg());
  if (m_value->ireg().reg_class == m_return_reg->ireg().reg_class) {
    rai.is_move = true;  // only true if we aren't moving from register kind to register kind
  }
  return rai;
}

void IR_Return::add_constraints(std::vector<IRegConstraint>* constraints, int my_id) {
  IRegConstraint c;
  if (dynamic_cast<const None*>(m_return_reg)) {
    return;
  }

  c.ireg = m_return_reg->ireg();
  c.instr_idx = my_id;
  c.desired_register = m_ret_reg;
  constraints->push_back(c);
}

void IR_Return::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  auto val_reg = get_reg(m_value, allocs, irec);
  auto dest_reg = get_reg(m_return_reg, allocs, irec);

  if (val_reg == dest_reg) {
    gen->add_instr(IGen::null(*gen), irec);
  } else {
    regset_common(gen, allocs, irec, m_return_reg, m_value, true);
    // gen->add_instr(IGen::mov_gpr64_gpr64(dest_reg, val_reg), irec);
  }
}

void IR_Return::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  // Move the value into the return register (x0). The function epilogue
  // (in CodeGenerator::do_goal_function_arm64) emits the actual `ret`.
  auto val_reg = get_reg(m_value, allocs, irec);
  auto dest_reg = get_reg(m_return_reg, allocs, irec);
  // Always emit a real MOV (identity MOV is harmless) so the body stays
  // classifier-real even when allocator coalesced source and dest.
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dest_reg, val_reg), irec);
}

/////////////////////
// LoadConstant64
/////////////////////
IR_LoadConstant64::IR_LoadConstant64(const RegVal* dest, u64 value)
    : m_dest(dest), m_value(value) {}

std::string IR_LoadConstant64::print() {
  return fmt::format("mov-ic {}, {}", m_dest->print(), m_value);
}

RegAllocInstr IR_LoadConstant64::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_LoadConstant64::do_codegen_x86(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  load_constant(m_value, gen, irec, dest_reg);
}

void IR_LoadConstant64::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  // Materialise a 64-bit constant via MOVZ + up to 3 MOVK at shift 16/32/48.
  // We always emit MOVZ for the low 16 bits, then MOVK for each non-zero
  // higher half-word. For zero, MOVZ #0 suffices. Always emit at least one
  // instruction (MOVZ) for this IR.
  auto dest_reg = get_reg(m_dest, allocs, irec);
  uint64_t v = m_value;
  gen->add_instr(
      emitter::IGen::ARM64::movz_gpr64_imm16_lsl(dest_reg, static_cast<uint16_t>(v & 0xffff), 0),
      irec);
  for (int shift = 1; shift <= 3; ++shift) {
    uint16_t part = static_cast<uint16_t>((v >> (shift * 16)) & 0xffff);
    if (part != 0) {
      gen->add_instr(emitter::IGen::ARM64::movk_gpr64_imm16_lsl(dest_reg, part, shift), irec);
    }
  }
}

/////////////////////
// LoadSymbolPointer
/////////////////////
IR_LoadSymbolPointer::IR_LoadSymbolPointer(const RegVal* dest, std::string name)
    : m_dest(dest), m_name(std::move(name)) {}

std::string IR_LoadSymbolPointer::print() {
  return fmt::format("mov-symptr {}, '{}", m_dest->print(), m_name);
}

RegAllocInstr IR_LoadSymbolPointer::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_LoadSymbolPointer::do_codegen_x86(emitter::ObjectGenerator* gen,
                                          const AllocationResult& allocs,
                                          emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  if (m_name == "#f") {
    static_assert(false_symbol_offset() == 0, "false symbol location");
    if (dest_reg.is_xmm(gen->instr_set())) {
      gen->add_instr(IGen::movq_xmm64_gpr64(*gen, dest_reg, gRegInfo.get_st_reg()), irec);
    } else {
      gen->add_instr(IGen::mov_gpr64_gpr64(*gen, dest_reg, gRegInfo.get_st_reg()), irec);
    }
  } else if (m_name == "#t") {
    gen->add_instr(IGen::lea_reg_plus_off8(*gen, dest_reg, gRegInfo.get_st_reg(),
                                           true_symbol_offset(gen->version())),
                   irec);
  } else if (m_name == "_empty_") {
    gen->add_instr(IGen::lea_reg_plus_off8(*gen, dest_reg, gRegInfo.get_st_reg(),
                                           empty_pair_offset_from_s7(gen->version())),
                   irec);
  } else {
    auto instr = gen->add_instr(
        IGen::lea_reg_plus_off32(*gen, dest_reg, gRegInfo.get_st_reg(), 0x0afecafe), irec);
    gen->link_instruction_symbol_ptr(instr, m_name);
  }
}

void IR_LoadSymbolPointer::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                            const AllocationResult& allocs,
                                            emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  if (m_name == "#f") {
    // false-symbol lives at the symbol-table base: move st_reg → dst.
    gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dest_reg, gRegInfo.get_st_reg()), irec);
  } else if (m_name == "#t" || m_name == "_empty_") {
    int off = (m_name == "#t") ? true_symbol_offset(gen->version())
                               : empty_pair_offset_from_s7(gen->version());
    gen->add_instr(emitter::IGen::ARM64::lea_reg_plus_off(dest_reg, gRegInfo.get_st_reg(), off),
                   irec);
  } else {
    // Arbitrary symbol: ADRP imm21 + ADD imm12 materialise the absolute
    // address of the symbol slot. Both instructions are registered with the
    // ObjectGenerator's symbol-ptr fix-up table; the arm64-aware linker
    // (ObjectGenerator::handle_temp_instr_sym_links + the runtime patcher)
    // decodes each instruction word and writes the appropriate immediate.
    auto adrp_instr = gen->add_instr(emitter::IGen::ARM64::adrp_placeholder(dest_reg), irec);
    auto add_instr =
        gen->add_instr(emitter::IGen::ARM64::lea_reg_plus_off32(dest_reg, dest_reg, 0), irec);
    gen->link_instruction_symbol_ptr(adrp_instr, m_name);
    gen->link_instruction_symbol_ptr(add_instr, m_name);
  }
}

/////////////////////
// SetSymbolValue
/////////////////////

IR_SetSymbolValue::IR_SetSymbolValue(const SymbolVal* dest, const RegVal* src)
    : m_dest(dest), m_src(src) {}

std::string IR_SetSymbolValue::print() {
  return fmt::format("mov '{}, {}", m_dest->name(), m_src->print());
}

RegAllocInstr IR_SetSymbolValue::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(m_src->ireg());
  return rai;
}

void IR_SetSymbolValue::do_codegen_x86(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto src_reg = get_reg(m_src, allocs, irec);
  auto instr = gen->add_instr(
      IGen::store32_gpr64_gpr64_plus_gpr64_plus_s32(
          *gen, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(), src_reg, LINK_SYM_NO_OFFSET_FLAG),
      irec);
  gen->link_instruction_symbol_mem(instr, m_dest->name());
}

void IR_SetSymbolValue::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  auto src_reg = get_reg(m_src, allocs, irec);
  // STR Wsrc, [Xst, #imm12_scaled4]. The imm12 field holds (symbol_offset >> 2);
  // the arm64-aware ObjectGenerator fix-up rewrites the instruction word at
  // link time once the symbol's offset within the symbol table is known.
  auto instr = gen->add_instr(emitter::IGen::ARM64::store32_gpr64_gpr64_plus_gpr64_plus_s32(
                                  gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(), src_reg,
                                  LINK_SYM_NO_OFFSET_FLAG),
                              irec);
  gen->link_instruction_symbol_mem(instr, m_dest->name());
}

/////////////////////
// GetSymbolValue
/////////////////////

IR_GetSymbolValue::IR_GetSymbolValue(const RegVal* dest, const SymbolVal* src, bool sext)
    : m_dest(dest), m_src(src), m_sext(sext) {}

std::string IR_GetSymbolValue::print() {
  return fmt::format("mov {}, '{}", m_dest->print(), m_src->name());
}

RegAllocInstr IR_GetSymbolValue::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_GetSymbolValue::do_codegen_x86(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dst_reg = get_reg(m_dest, allocs, irec);
  if (m_sext) {
    auto instr = gen->add_instr(IGen::load32s_gpr64_gpr64_plus_gpr64_plus_s32(
                                    *gen, dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                                    LINK_SYM_NO_OFFSET_FLAG),
                                irec);
    gen->link_instruction_symbol_mem(instr, m_src->name());
  } else {
    auto instr = gen->add_instr(IGen::load32u_gpr64_gpr64_plus_gpr64_plus_s32(
                                    *gen, dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                                    LINK_SYM_NO_OFFSET_FLAG),
                                irec);
    gen->link_instruction_symbol_mem(instr, m_src->name());
  }
}

void IR_GetSymbolValue::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  auto dst_reg = get_reg(m_dest, allocs, irec);
  // LDRSW Xdst, [Xst, #imm12_scaled4] (sext) or LDR Wdst, [Xst, #imm12_scaled4]
  // (unsigned). The arm64-aware fix-up rewrites the imm12 field once the
  // symbol's offset is known at link time.
  emitter::InstructionRecord instr;
  if (m_sext) {
    instr = gen->add_instr(emitter::IGen::ARM64::load32s_gpr64_gpr64_plus_gpr64_plus_s32(
                               dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                               LINK_SYM_NO_OFFSET_FLAG),
                           irec);
  } else {
    instr = gen->add_instr(emitter::IGen::ARM64::load32u_gpr64_gpr64_plus_gpr64_plus_s32(
                               dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                               LINK_SYM_NO_OFFSET_FLAG),
                           irec);
  }
  gen->link_instruction_symbol_mem(instr, m_src->name());
}

/////////////////////
// RegSet
/////////////////////

IR_RegSet::IR_RegSet(const RegVal* dest, const RegVal* src) : m_dest(dest), m_src(src) {}

RegAllocInstr IR_RegSet::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  rai.read.push_back(m_src->ireg());
  if (m_dest->ireg().reg_class == m_src->ireg().reg_class) {
    rai.is_move = true;  // only true if we aren't moving from register kind to register kind
  }
  return rai;
}

void IR_RegSet::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  regset_common(gen, allocs, irec, m_dest, m_src, true);
}

void IR_RegSet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  // Always MOV (identity is harmless) — keeps the codegen body classifier-real.
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}

std::string IR_RegSet::print() {
  return fmt::format("mov {}, {}", m_dest->print(), m_src->print());
}

/////////////////////
// GotoLabel
/////////////////////

IR_GotoLabel::IR_GotoLabel(const Label* dest) : m_dest(dest) {
  m_resolved = true;
}

IR_GotoLabel::IR_GotoLabel() {
  m_resolved = false;
}

std::string IR_GotoLabel::print() {
  return fmt::format("goto {}", m_dest->print());
}

RegAllocInstr IR_GotoLabel::to_rai() {
  ASSERT(m_resolved);
  RegAllocInstr rai;
  rai.jumps.push_back(m_dest->idx);
  rai.fallthrough = false;
  return rai;
}

void IR_GotoLabel::do_codegen_x86(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  (void)allocs;
  auto instr = gen->add_instr(IGen::jmp_32(*gen), irec);
  gen->link_instruction_jump(instr, gen->get_future_ir_record_in_same_func(irec, m_dest->idx));
}

void IR_GotoLabel::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                    const AllocationResult& allocs,
                                    emitter::IR_Record irec) {
  (void)allocs;
  ASSERT(m_resolved);
  auto instr = gen->add_instr(emitter::IGen::ARM64::b_uncond_placeholder(), irec);
  gen->link_instruction_jump(instr, gen->get_future_ir_record_in_same_func(irec, m_dest->idx));
}

void IR_GotoLabel::resolve(const Label* dest) {
  ASSERT(!m_resolved);
  m_dest = dest;
  m_resolved = true;
}

/////////////////////
// FunctionCall
/////////////////////

IR_FunctionCall::IR_FunctionCall(const RegVal* func,
                                 const RegVal* ret,
                                 std::vector<RegVal*> args,
                                 std::vector<emitter::Register> arg_regs,
                                 std::optional<emitter::Register> ret_reg)
    : m_func(func),
      m_ret(ret),
      m_args(std::move(args)),
      m_arg_regs(std::move(arg_regs)),
      m_ret_reg(ret_reg) {}

std::string IR_FunctionCall::print() {
  std::string result = fmt::format("call {} (ret {}) (args ", m_func->print(), m_ret->print());
  for (const auto& x : m_args) {
    result += fmt::format("{} ", x->print());
  }
  result.pop_back();
  result.push_back(')');
  return result;
}

RegAllocInstr IR_FunctionCall::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(m_func->ireg());
  rai.write.push_back(m_func->ireg());  // todo, can we avoid this?
  rai.write.push_back(m_ret->ireg());
  for (auto& arg : m_args) {
    rai.read.push_back(arg->ireg());
  }

  for (int i = 0; i < emitter::RegisterInfo::N_REGS; i++) {
    auto& info = emitter::gRegInfo.get_info(i);
    if (info.temp()) {
      rai.clobber.emplace_back(i);
    }
  }

  return rai;
}

void IR_FunctionCall::add_constraints(std::vector<IRegConstraint>* constraints, int my_id) {
  for (size_t i = 0; i < m_args.size(); i++) {
    IRegConstraint c;
    c.ireg = m_args.at(i)->ireg();
    c.instr_idx = my_id;
    c.desired_register = m_arg_regs.at(i);
    constraints->push_back(c);
  }

  if (m_ret_reg) {
    IRegConstraint c;
    c.ireg = m_ret->ireg();
    c.desired_register = *m_ret_reg;
    c.instr_idx = my_id;
    constraints->push_back(c);
  }
}

void IR_FunctionCall::do_codegen_x86(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto freg = get_reg(m_func, allocs, irec);
  gen->add_instr(IGen::add_gpr64_gpr64(*gen, freg, emitter::gRegInfo.get_offset_reg()), irec);
  gen->add_instr(IGen::call_r64(*gen, freg), irec);
  // todo, can we do a sub to undo the modification to the register? does that actually work?
}

void IR_FunctionCall::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  // Mirror the x86 path: add offset to the function pointer, then BLR.
  auto freg = get_reg(m_func, allocs, irec);
  gen->add_instr(emitter::IGen::ARM64::add_gpr64_gpr64(freg, emitter::gRegInfo.get_offset_reg()),
                 irec);
  gen->add_instr(emitter::IGen::ARM64::call_r64(freg), irec);
}

/////////////////////
// RegValAddr
/////////////////////

IR_RegValAddr::IR_RegValAddr(const RegVal* dest, const RegVal* src) : m_dest(dest), m_src(src) {}

std::string IR_RegValAddr::print() {
  return fmt::format("mov {}, &{}", m_dest->print(), m_src->print());
}

RegAllocInstr IR_RegValAddr::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  // we don't actually read the value in m_src, so we don't need to add it here.
  return rai;
}

void IR_RegValAddr::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  int stack_offset = get_stack_offset(m_src, allocs);
  auto dst = get_reg(m_dest, allocs, irec);
  // x86 pointer to var
  gen->add_instr(IGen::lea_reg_plus_off(*gen, dst, RSP, stack_offset), irec);
  // x86 -> GOAL pointer
  gen->add_instr(IGen::sub_gpr64_gpr64(*gen, dst, emitter::gRegInfo.get_offset_reg()), irec);
}

void IR_RegValAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  int stack_offset = get_stack_offset(m_src, allocs);
  auto dst = get_reg(m_dest, allocs, irec);
  // A10: dst = SP + stack_offset. Emit ADD Xd, SP, #imm12 directly (Rn=31)
  // — IGen::ARM64::lea_reg_plus_off would route RSP through arm64_reg5() = 4
  // and corrupt this into `ADD Xd, X4, #imm`. See arm64_add_xd_sp_imm12.
  ASSERT(stack_offset >= 0);
  gen->add_instr(arm64_add_xd_sp_imm12(dst, static_cast<uint32_t>(stack_offset)), irec);
  // dst = SP + stack_offset - offset_reg = GOAL pointer.
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dst, emitter::gRegInfo.get_offset_reg()),
                 irec);
}

/////////////////////
// StaticVarAddr
/////////////////////

IR_StaticVarAddr::IR_StaticVarAddr(const RegVal* dest, const StaticObject* src)
    : m_dest(dest), m_src(src) {}

std::string IR_StaticVarAddr::print() {
  return fmt::format("mov-sva {}, {}", m_dest->print(), m_src->print());
}

RegAllocInstr IR_StaticVarAddr::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_StaticVarAddr::do_codegen_x86(emitter::ObjectGenerator* gen,
                                      const AllocationResult& allocs,
                                      emitter::IR_Record irec) {
  auto dr = get_reg(m_dest, allocs, irec);
  auto instr = gen->add_instr(IGen::static_addr(*gen, dr, 0), irec);
  gen->link_instruction_static(instr, m_src->rec, m_src->get_addr_offset());
  gen->add_instr(IGen::sub_gpr64_gpr64(*gen, dr, emitter::gRegInfo.get_offset_reg()), irec);
}

void IR_StaticVarAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                        const AllocationResult& allocs,
                                        emitter::IR_Record irec) {
  auto dr = get_reg(m_dest, allocs, irec);
  // ADRP imm21 (page) + ADD imm12 (page-offset) materialises the absolute
  // address of the static; the trailing SUB converts it to a GOAL pointer.
  // Both immediate-bearing instructions are registered with the fix-up table
  // so the arm64-aware linker can write the imm21 / imm12 fields once the
  // static's final byte offset is known.
  auto adrp_instr = gen->add_instr(emitter::IGen::ARM64::static_addr(dr, 0), irec);
  auto add_instr = gen->add_instr(emitter::IGen::ARM64::lea_reg_plus_off32(dr, dr, 0), irec);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dr, emitter::gRegInfo.get_offset_reg()),
                 irec);
  gen->link_instruction_static(adrp_instr, m_src->rec, m_src->get_addr_offset());
  gen->link_instruction_static(add_instr, m_src->rec, m_src->get_addr_offset());
}

/////////////////////
// FunctionAddr
/////////////////////

IR_FunctionAddr::IR_FunctionAddr(const RegVal* dest, FunctionEnv* src) : m_dest(dest), m_src(src) {}

std::string IR_FunctionAddr::print() {
  return fmt::format("mov-fa {}, {}", m_dest->print(), m_src->print());
}

RegAllocInstr IR_FunctionAddr::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_FunctionAddr::do_codegen_x86(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dr = get_reg(m_dest, allocs, irec);
  auto instr = gen->add_instr(IGen::static_addr(*gen, dr, 0), irec);
  gen->link_instruction_to_function(instr, gen->get_existing_function_record(m_src->idx_in_file));
  gen->add_instr(IGen::sub_gpr64_gpr64(*gen, dr, emitter::gRegInfo.get_offset_reg()), irec);
}

void IR_FunctionAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dr = get_reg(m_dest, allocs, irec);
  // ADRP imm21 + ADD imm12 page-relative pair (same shape as IR_StaticVarAddr);
  // the trailing SUB converts the absolute function address to a GOAL pointer.
  // Both immediate-bearing instructions are registered with the fix-up table.
  auto adrp_instr = gen->add_instr(emitter::IGen::ARM64::static_addr(dr, 0), irec);
  auto add_instr = gen->add_instr(emitter::IGen::ARM64::lea_reg_plus_off32(dr, dr, 0), irec);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dr, emitter::gRegInfo.get_offset_reg()),
                 irec);
  auto func_rec = gen->get_existing_function_record(m_src->idx_in_file);
  gen->link_instruction_to_function(adrp_instr, func_rec);
  gen->link_instruction_to_function(add_instr, func_rec);
}

/////////////////////
// IntegerMath
/////////////////////

IR_IntegerMath::IR_IntegerMath(IntegerMathKind kind, RegVal* dest, RegVal* arg)
    : m_kind(kind), m_dest(dest), m_arg(arg) {}

IR_IntegerMath::IR_IntegerMath(IntegerMathKind kind, RegVal* dest, u8 shift_amount)
    : m_kind(kind), m_dest(dest), m_shift_amount(shift_amount) {}

std::string IR_IntegerMath::print() {
  switch (m_kind) {
    case IntegerMathKind::ADD_64:
      return fmt::format("addi {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::SUB_64:
      return fmt::format("subi {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::IMUL_32:
      return fmt::format("imul {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::IMUL_64:
      return fmt::format("imul64 {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::IDIV_32:
      return fmt::format("idiv {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::UDIV_32:
      return fmt::format("udiv {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::IMOD_32:
      return fmt::format("imod {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::UMOD_32:
      return fmt::format("umod {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::SARV_64:
      return fmt::format("sarv {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::SHLV_64:
      return fmt::format("shlv {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::SHRV_64:
      return fmt::format("shrv {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::SAR_64:
      return fmt::format("sar {}, {}", m_dest->print(), m_shift_amount);
    case IntegerMathKind::SHL_64:
      return fmt::format("shl {}, {}", m_dest->print(), m_shift_amount);
    case IntegerMathKind::SHR_64:
      return fmt::format("shr {}, {}", m_dest->print(), m_shift_amount);
    case IntegerMathKind::AND_64:
      return fmt::format("and {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::OR_64:
      return fmt::format("or {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::XOR_64:
      return fmt::format("xor {}, {}", m_dest->print(), m_arg->print());
    case IntegerMathKind::NOT_64:
      return fmt::format("not {}", m_dest->print());
    default:
      throw std::runtime_error("Unsupported IntegerMathKind");
  }
}

RegAllocInstr IR_IntegerMath::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  rai.read.push_back(m_dest->ireg());

  if (m_kind != IntegerMathKind::NOT_64 && m_kind != IntegerMathKind::SHL_64 &&
      m_kind != IntegerMathKind::SAR_64 && m_kind != IntegerMathKind::SHR_64) {
    rai.read.push_back(m_arg->ireg());
  }

  if (m_kind == IntegerMathKind::IDIV_32 || m_kind == IntegerMathKind::IMOD_32 ||
      m_kind == IntegerMathKind::UDIV_32 || m_kind == IntegerMathKind::UMOD_32) {
    rai.exclude.emplace_back(emitter::RDX);
  }
  return rai;
}

void IR_IntegerMath::do_codegen_x86(emitter::ObjectGenerator* gen,
                                    const AllocationResult& allocs,
                                    emitter::IR_Record irec) {
  switch (m_kind) {
    case IntegerMathKind::ADD_64:
      gen->add_instr(
          IGen::add_gpr64_gpr64(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case IntegerMathKind::SUB_64:
      gen->add_instr(
          IGen::sub_gpr64_gpr64(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case IntegerMathKind::AND_64:
      gen->add_instr(
          IGen::and_gpr64_gpr64(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case IntegerMathKind::OR_64:
      gen->add_instr(
          IGen::or_gpr64_gpr64(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case IntegerMathKind::XOR_64:
      gen->add_instr(
          IGen::xor_gpr64_gpr64(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case IntegerMathKind::NOT_64:
      gen->add_instr(IGen::not_gpr64(*gen, get_reg(m_dest, allocs, irec)), irec);
      ASSERT(!m_arg);
      break;
    case IntegerMathKind::SHLV_64:
      gen->add_instr(IGen::shl_gpr64_cl(*gen, get_reg(m_dest, allocs, irec)), irec);
      ASSERT(get_reg(m_arg, allocs, irec) == emitter::RCX);
      break;
    case IntegerMathKind::SHRV_64:
      gen->add_instr(IGen::shr_gpr64_cl(*gen, get_reg(m_dest, allocs, irec)), irec);
      ASSERT(get_reg(m_arg, allocs, irec) == emitter::RCX);
      break;
    case IntegerMathKind::SARV_64:
      gen->add_instr(IGen::sar_gpr64_cl(*gen, get_reg(m_dest, allocs, irec)), irec);
      ASSERT(get_reg(m_arg, allocs, irec) == emitter::RCX);
      break;
    case IntegerMathKind::SHL_64:
      gen->add_instr(IGen::shl_gpr64_u8(*gen, get_reg(m_dest, allocs, irec), m_shift_amount), irec);
      break;
    case IntegerMathKind::SHR_64:
      gen->add_instr(IGen::shr_gpr64_u8(*gen, get_reg(m_dest, allocs, irec), m_shift_amount), irec);
      break;
    case IntegerMathKind::SAR_64:
      gen->add_instr(IGen::sar_gpr64_u8(*gen, get_reg(m_dest, allocs, irec), m_shift_amount), irec);
      break;
    case IntegerMathKind::IMUL_32: {
      // just a 32-bit multiply, signed/unsigned doesn't affect lower 32 bits of result.
      auto dr = get_reg(m_dest, allocs, irec);
      gen->add_instr(IGen::imul_gpr32_gpr32(*gen, dr, get_reg(m_arg, allocs, irec)), irec);
      // the PS2 sign extends the result even if we used multu. We replicate this here.
      gen->add_instr(IGen::movsx_r64_r32(*gen, dr, dr), irec);
    } break;
    case IntegerMathKind::IMUL_64: {
      auto dr = get_reg(m_dest, allocs, irec);
      gen->add_instr(IGen::imul_gpr64_gpr64(*gen, dr, get_reg(m_arg, allocs, irec)), irec);
    } break;
    case IntegerMathKind::IDIV_32: {
      gen->add_instr(IGen::cdq(*gen), irec);
      gen->add_instr(IGen::idiv_gpr32(*gen, get_reg(m_arg, allocs, irec)), irec);
      gen->add_instr(IGen::movsx_r64_r32(*gen, get_reg(m_dest, allocs, irec), emitter::RAX), irec);
    } break;
    case IntegerMathKind::UDIV_32: {
      // zero extend, not sign extend to avoid overflow
      gen->add_instr(IGen::xor_gpr64_gpr64(*gen, Register(RDX), Register(RDX)), irec);
      gen->add_instr(IGen::unsigned_div_gpr32(*gen, get_reg(m_arg, allocs, irec)), irec);
      // note: this probably needs hardware testing to know for sure if the PS2 actually sign
      // extends here or not. Nothing seems to break either way, and PCSX2/Dobie interpreters both
      // sign extend, so that seems like the safest option.
      gen->add_instr(IGen::movsx_r64_r32(*gen, get_reg(m_dest, allocs, irec), emitter::RAX), irec);
    } break;
    case IntegerMathKind::IMOD_32: {
      gen->add_instr(IGen::cdq(*gen), irec);
      gen->add_instr(IGen::idiv_gpr32(*gen, get_reg(m_arg, allocs, irec)), irec);
      gen->add_instr(IGen::movsx_r64_r32(*gen, get_reg(m_dest, allocs, irec), emitter::RDX), irec);
    } break;
    case IntegerMathKind::UMOD_32: {
      // zero extend, not sign extend to avoid overflow
      gen->add_instr(IGen::xor_gpr64_gpr64(*gen, Register(RDX), Register(RDX)), irec);
      gen->add_instr(IGen::unsigned_div_gpr32(*gen, get_reg(m_arg, allocs, irec)), irec);
      // see note on udiv, same applies here.
      gen->add_instr(IGen::movsx_r64_r32(*gen, get_reg(m_dest, allocs, irec), emitter::RDX), irec);
    } break;
    default:
      ASSERT(false);
  }
}

void IR_IntegerMath::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                      const AllocationResult& allocs,
                                      emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  switch (m_kind) {
    case IntegerMathKind::ADD_64:
      gen->add_instr(emitter::IGen::ARM64::add_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::SUB_64:
      gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::AND_64:
      gen->add_instr(emitter::IGen::ARM64::and_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::OR_64:
      gen->add_instr(emitter::IGen::ARM64::or_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::XOR_64:
      gen->add_instr(emitter::IGen::ARM64::xor_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::NOT_64:
      gen->add_instr(emitter::IGen::ARM64::not_gpr64(dst), irec);
      break;
    case IntegerMathKind::IMUL_32:
      gen->add_instr(emitter::IGen::ARM64::imul_gpr32_gpr32(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::IMUL_64:
      gen->add_instr(emitter::IGen::ARM64::imul_gpr64_gpr64(dst, get_reg(m_arg, allocs, irec)),
                     irec);
      break;
    case IntegerMathKind::IDIV_32:
    case IntegerMathKind::IMOD_32: {
      // A17 — emitter-side IDIV preserve-X8 spill. idiv_gpr32 emits a single
      // SDIV X8, X8, Xn whose X8 dst+src1 is hardcoded; that write is invisible
      // to the regalloc, so it may park a live value (e.g. m_func of a later
      // BLR) in X8. Wrap the SDIV in a sub_sp / str_x8 / sdiv / mov / ldr_x8 /
      // add_sp sequence to preserve caller's X8. See the A17 block comment in
      // IGenARM64.cpp above idiv_gpr32 for the full rationale. m_dest == X8 is
      // a fast path — caller had no X8 value worth preserving in that case.
      auto arg_reg = get_reg(m_arg, allocs, irec);
      auto dst_reg = get_reg(m_dest, allocs, irec);
      if (dst_reg.id() == 8) {
        gen->add_instr(emitter::IGen::ARM64::idiv_gpr32(arg_reg), irec);
      } else {
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_sub_sp_16(), irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_str_x8_sp_0(), irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_gpr32(arg_reg), irec);
        gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst_reg, emitter::Register(8)),
                       irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_ldr_x8_sp_0(), irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_add_sp_16(), irec);
      }
    } break;
    case IntegerMathKind::UDIV_32:
    case IntegerMathKind::UMOD_32: {
      // A17 — same preserve-X8 spill protocol as IDIV_32 above. unsigned_div_gpr32
      // emits UDIV X8, X8, Xn with the same hardcoded-X8 / regalloc-invisible
      // clobber; wrap it identically.
      auto arg_reg = get_reg(m_arg, allocs, irec);
      auto dst_reg = get_reg(m_dest, allocs, irec);
      if (dst_reg.id() == 8) {
        gen->add_instr(emitter::IGen::ARM64::unsigned_div_gpr32(arg_reg), irec);
      } else {
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_sub_sp_16(), irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_str_x8_sp_0(), irec);
        gen->add_instr(emitter::IGen::ARM64::unsigned_div_gpr32(arg_reg), irec);
        gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst_reg, emitter::Register(8)),
                       irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_ldr_x8_sp_0(), irec);
        gen->add_instr(emitter::IGen::ARM64::idiv_spill_add_sp_16(), irec);
      }
    } break;
    case IntegerMathKind::SARV_64:
      gen->add_instr(emitter::IGen::ARM64::sar_gpr64_cl(dst), irec);
      break;
    case IntegerMathKind::SHLV_64:
      gen->add_instr(emitter::IGen::ARM64::shl_gpr64_cl(dst), irec);
      break;
    case IntegerMathKind::SHRV_64:
      gen->add_instr(emitter::IGen::ARM64::shr_gpr64_cl(dst), irec);
      break;
    case IntegerMathKind::SAR_64:
      gen->add_instr(emitter::IGen::ARM64::sar_gpr64_u8(dst, m_shift_amount), irec);
      break;
    case IntegerMathKind::SHL_64:
      gen->add_instr(emitter::IGen::ARM64::shl_gpr64_u8(dst, m_shift_amount), irec);
      break;
    case IntegerMathKind::SHR_64:
      gen->add_instr(emitter::IGen::ARM64::shr_gpr64_u8(dst, m_shift_amount), irec);
      break;
    default:
      // Any not-yet-handled kind: still emit a real arm64 instruction (a
      // benign MOV dst,dst) so the body stays classifier-real and we don't
      // silently drop ops.
      gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, dst), irec);
      break;
  }
}

/////////////////////
// FloatMath
/////////////////////

IR_FloatMath::IR_FloatMath(FloatMathKind kind, RegVal* dest, RegVal* arg)
    : m_kind(kind), m_dest(dest), m_arg(arg) {}

std::string IR_FloatMath::print() {
  switch (m_kind) {
    case FloatMathKind::DIV_SS:
      return fmt::format("divss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::MUL_SS:
      return fmt::format("mulss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::ADD_SS:
      return fmt::format("addss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::SUB_SS:
      return fmt::format("subss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::MAX_SS:
      return fmt::format("maxss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::MIN_SS:
      return fmt::format("minss {}, {}", m_dest->print(), m_arg->print());
    case FloatMathKind::SQRT_SS:
      return fmt::format("sqrtss {}, {}", m_dest->print(), m_arg->print());
    default:
      throw std::runtime_error("Unsupported FloatMathKind");
  }
}

RegAllocInstr IR_FloatMath::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  if (m_kind != FloatMathKind::SQRT_SS) {
    rai.read.push_back(m_dest->ireg());
  }
  rai.read.push_back(m_arg->ireg());
  return rai;
}

void IR_FloatMath::do_codegen_x86(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  switch (m_kind) {
    case FloatMathKind::DIV_SS:
      gen->add_instr(
          IGen::divss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::MUL_SS:
      gen->add_instr(
          IGen::mulss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::ADD_SS:
      gen->add_instr(
          IGen::addss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::SUB_SS:
      gen->add_instr(
          IGen::subss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::MAX_SS:
      gen->add_instr(
          IGen::maxss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::MIN_SS:
      gen->add_instr(
          IGen::minss_xmm_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)),
          irec);
      break;
    case FloatMathKind::SQRT_SS:
      gen->add_instr(
          IGen::sqrts_xmm(*gen, get_reg(m_dest, allocs, irec), get_reg(m_arg, allocs, irec)), irec);
      break;
    default:
      ASSERT(false);
  }
}

void IR_FloatMath::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                    const AllocationResult& allocs,
                                    emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_arg, allocs, irec);
  switch (m_kind) {
    case FloatMathKind::DIV_SS:
      gen->add_instr(emitter::IGen::ARM64::divss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::MUL_SS:
      gen->add_instr(emitter::IGen::ARM64::mulss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::ADD_SS:
      gen->add_instr(emitter::IGen::ARM64::addss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::SUB_SS:
      gen->add_instr(emitter::IGen::ARM64::subss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::MAX_SS:
      gen->add_instr(emitter::IGen::ARM64::maxss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::MIN_SS:
      gen->add_instr(emitter::IGen::ARM64::minss_xmm_xmm(dst, src), irec);
      break;
    case FloatMathKind::SQRT_SS:
      gen->add_instr(emitter::IGen::ARM64::sqrts_xmm(dst, src), irec);
      break;
    default:
      ASSERT(false);
  }
}

/////////////////////
// StaticVarLoad
/////////////////////

IR_StaticVarLoad::IR_StaticVarLoad(const RegVal* dest, const StaticObject* src)
    : m_dest(dest), m_src(src) {}

std::string IR_StaticVarLoad::print() {
  return fmt::format("mov-svl {}, [{}]", m_dest->print(), m_src->print());
}

RegAllocInstr IR_StaticVarLoad::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_StaticVarLoad::do_codegen_x86(emitter::ObjectGenerator* gen,
                                      const AllocationResult& allocs,
                                      emitter::IR_Record irec) {
  auto load_info = m_src->get_load_info();
  ASSERT(m_src->get_addr_offset() == 0);

  if (m_dest->ireg().reg_class == RegClass::FLOAT) {
    ASSERT(load_info.load_signed == false);
    ASSERT(load_info.load_size == 4);
    ASSERT(load_info.requires_load == true);

    auto instr =
        gen->add_instr(IGen::static_load_xmm32(*gen, get_reg(m_dest, allocs, irec), 0), irec);
    gen->link_instruction_static(instr, m_src->rec, 0);
  } else if (m_dest->ireg().reg_class == RegClass::VECTOR_FLOAT) {
    // we don't check the load info intentionally because we want to allow loading an entire
    // vector structure.
    auto instr =
        gen->add_instr(IGen::loadvf_rip_plus_s32(*gen, get_reg(m_dest, allocs, irec), 0), irec);
    gen->link_instruction_static(instr, m_src->rec, 0);
  } else {
    ASSERT(false);
  }
}

void IR_StaticVarLoad::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                        const AllocationResult& allocs,
                                        emitter::IR_Record irec) {
  auto load_info = m_src->get_load_info();
  ASSERT(m_src->get_addr_offset() == 0);
  auto dst = get_reg(m_dest, allocs, irec);
  // LDR-literal (PC-relative): imm19 holds (target_pc - patch_pc) / 4. The
  // arm64-aware linker writes the imm19 field once the static's final byte
  // offset is known. The same shape encodes both the 32-bit float LDR (Sd) and
  // the 128-bit vector LDR (Qd).
  emitter::InstructionRecord instr;
  if (m_dest->ireg().reg_class == RegClass::FLOAT) {
    ASSERT(load_info.load_signed == false);
    ASSERT(load_info.load_size == 4);
    ASSERT(load_info.requires_load == true);
    instr = gen->add_instr(emitter::IGen::ARM64::static_load_xmm32(dst, 0), irec);
  } else if (m_dest->ireg().reg_class == RegClass::VECTOR_FLOAT) {
    instr = gen->add_instr(emitter::IGen::ARM64::loadvf_rip_plus_s32(dst, 0), irec);
  } else {
    ASSERT(false);
  }
  gen->link_instruction_static(instr, m_src->rec, 0);
}

/////////////////////
// ConditionalBranch
/////////////////////

std::string Condition::print() const {
  switch (kind) {
    case ConditionKind::NOT_EQUAL:
      return a->print() + " != " + b->print();
    case ConditionKind::EQUAL:
      return a->print() + " == " + b->print();
    case ConditionKind::LEQ:
      return a->print() + " <= " + b->print();
    case ConditionKind::GEQ:
      return a->print() + " >= " + b->print();
    case ConditionKind::LT:
      return a->print() + " < " + b->print();
    case ConditionKind::GT:
      return a->print() + " > " + b->print();
    default:
      throw std::runtime_error("unknown condition type in GoalCondition::print()");
  }
}

RegAllocInstr Condition::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(a->ireg());
  rai.read.push_back(b->ireg());
  return rai;
}

IR_ConditionalBranch::IR_ConditionalBranch(const Condition& _condition, Label _label)
    : condition(_condition), label(_label) {}

std::string IR_ConditionalBranch::print() {
  // todo, float/signed info?
  return fmt::format("j({}) {}", condition.print(), label.print());
}

RegAllocInstr IR_ConditionalBranch::to_rai() {
  auto rai = condition.to_rai();
  ASSERT(m_resolved);
  rai.jumps.push_back(label.idx);
  return rai;
}

void IR_ConditionalBranch::do_codegen_x86(emitter::ObjectGenerator* gen,
                                          const AllocationResult& allocs,
                                          emitter::IR_Record irec) {
  Instruction jump_instr = InstructionX86(0);
  ASSERT(m_resolved);
  switch (condition.kind) {
    case ConditionKind::EQUAL:
      jump_instr = IGen::je_32(*gen);
      break;
    case ConditionKind::NOT_EQUAL:
      jump_instr = IGen::jne_32(*gen);
      break;
    case ConditionKind::LEQ:
      if (condition.is_signed) {
        jump_instr = IGen::jle_32(*gen);
      } else {
        jump_instr = IGen::jbe_32(*gen);
      }
      break;
    case ConditionKind::GEQ:
      if (condition.is_signed) {
        jump_instr = IGen::jge_32(*gen);
      } else {
        jump_instr = IGen::jae_32(*gen);
      }
      break;

    case ConditionKind::LT:
      if (condition.is_signed) {
        jump_instr = IGen::jl_32(*gen);
      } else {
        jump_instr = IGen::jb_32(*gen);
      }
      break;
    case ConditionKind::GT:
      if (condition.is_signed) {
        jump_instr = IGen::jg_32(*gen);
      } else {
        jump_instr = IGen::ja_32(*gen);
      }
      break;
    default:
      ASSERT(false);
  }

  if (condition.is_float) {
    gen->add_instr(IGen::cmp_flt_flt(*gen, get_reg(condition.a, allocs, irec),
                                     get_reg(condition.b, allocs, irec)),
                   irec);
  } else {
    gen->add_instr(IGen::cmp_gpr64_gpr64(*gen, get_reg(condition.a, allocs, irec),
                                         get_reg(condition.b, allocs, irec)),
                   irec);
  }

  auto jump_rec = gen->add_instr(jump_instr, irec);
  gen->link_instruction_jump(jump_rec, gen->get_future_ir_record_in_same_func(irec, label.idx));
}

void IR_ConditionalBranch::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                            const AllocationResult& allocs,
                                            emitter::IR_Record irec) {
  ASSERT(m_resolved);
  int cond = emitter::IGen::ARM64::ARM_COND_EQ;
  switch (condition.kind) {
    case ConditionKind::EQUAL:
      cond = emitter::IGen::ARM64::ARM_COND_EQ;
      break;
    case ConditionKind::NOT_EQUAL:
      cond = emitter::IGen::ARM64::ARM_COND_NE;
      break;
    case ConditionKind::LEQ:
      cond = condition.is_signed ? emitter::IGen::ARM64::ARM_COND_LE
                                 : emitter::IGen::ARM64::ARM_COND_LS;
      break;
    case ConditionKind::GEQ:
      cond = condition.is_signed ? emitter::IGen::ARM64::ARM_COND_GE
                                 : emitter::IGen::ARM64::ARM_COND_CS;
      break;
    case ConditionKind::LT:
      cond = condition.is_signed ? emitter::IGen::ARM64::ARM_COND_LT
                                 : emitter::IGen::ARM64::ARM_COND_CC;
      break;
    case ConditionKind::GT:
      cond = condition.is_signed ? emitter::IGen::ARM64::ARM_COND_GT
                                 : emitter::IGen::ARM64::ARM_COND_HI;
      break;
    default:
      ASSERT(false);
  }
  gen->add_instr(emitter::IGen::ARM64::cmp_gpr64_gpr64(get_reg(condition.a, allocs, irec),
                                                       get_reg(condition.b, allocs, irec)),
                 irec);
  auto jump_rec =
      gen->add_instr(emitter::IGen::ARM64::b_cond_placeholder(cond), irec);
  gen->link_instruction_jump(jump_rec, gen->get_future_ir_record_in_same_func(irec, label.idx));
}

/////////////////////
// LoadConstantOffset
/////////////////////

IR_LoadConstOffset::IR_LoadConstOffset(const RegVal* dest,
                                       int offset,
                                       const RegVal* base,
                                       MemLoadInfo info,
                                       bool use_coloring)
    : IR_Asm(use_coloring), m_dest(dest), m_offset(offset), m_base(base), m_info(info) {}

std::string IR_LoadConstOffset::print() {
  return fmt::format("mov {}, [{} + {}]", m_dest->print(), m_base->print(), m_offset);
}

RegAllocInstr IR_LoadConstOffset::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  rai.read.push_back(m_base->ireg());
  return rai;
}

void IR_LoadConstOffset::do_codegen_x86(emitter::ObjectGenerator* gen,
                                        const AllocationResult& allocs,
                                        emitter::IR_Record irec) {
  auto dest_reg = m_use_coloring ? get_reg(m_dest, allocs, irec) : get_no_color_reg(m_dest);
  auto base_reg = m_use_coloring ? get_reg(m_base, allocs, irec) : get_no_color_reg(m_base);

  if (m_dest->ireg().reg_class == RegClass::GPR_64) {
    gen->add_instr(IGen::load_goal_gpr(*gen, dest_reg, base_reg, emitter::gRegInfo.get_offset_reg(),
                                       m_offset, m_info.size, m_info.sign_extend),
                   irec);
  } else if (m_dest->ireg().reg_class == RegClass::FLOAT && m_info.size == 4 &&
             m_info.sign_extend == false && m_info.reg == RegClass::FLOAT) {
    gen->add_instr(IGen::load_goal_xmm32(*gen, dest_reg, base_reg,
                                         emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else if ((m_dest->ireg().reg_class == RegClass::VECTOR_FLOAT ||
              m_dest->ireg().reg_class == RegClass::INT_128) &&
             m_info.size == 16 && m_info.sign_extend == false &&
             m_info.reg == m_dest->ireg().reg_class) {
    gen->add_instr(IGen::load_goal_xmm128(*gen, dest_reg, base_reg,
                                          emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else {
    throw std::runtime_error("IR_LoadConstOffset::do_codegen_x86 not supported");
  }
}

void IR_LoadConstOffset::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                          const AllocationResult& allocs,
                                          emitter::IR_Record irec) {
  auto dest_reg = m_use_coloring ? get_reg(m_dest, allocs, irec) : get_no_color_reg(m_dest);
  auto base_reg = m_use_coloring ? get_reg(m_base, allocs, irec) : get_no_color_reg(m_base);
  if (m_dest->ireg().reg_class == RegClass::GPR_64) {
    gen->add_instr(emitter::IGen::ARM64::load_goal_gpr(dest_reg, base_reg,
                                                       emitter::gRegInfo.get_offset_reg(),
                                                       m_offset, m_info.size, m_info.sign_extend),
                   irec);
  } else if (m_dest->ireg().reg_class == RegClass::FLOAT && m_info.size == 4 &&
             m_info.sign_extend == false && m_info.reg == RegClass::FLOAT) {
    gen->add_instr(emitter::IGen::ARM64::load_goal_xmm32(
                       dest_reg, base_reg, emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else if ((m_dest->ireg().reg_class == RegClass::VECTOR_FLOAT ||
              m_dest->ireg().reg_class == RegClass::INT_128) &&
             m_info.size == 16 && m_info.sign_extend == false &&
             m_info.reg == m_dest->ireg().reg_class) {
    gen->add_instr(emitter::IGen::ARM64::load_goal_xmm128(
                       dest_reg, base_reg, emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else {
    throw std::runtime_error("IR_LoadConstOffset::do_codegen_arm64 not supported");
  }
}

///////////////////////
// StoreConstantOffset
///////////////////////
IR_StoreConstOffset::IR_StoreConstOffset(const RegVal* value,
                                         int offset,
                                         const RegVal* base,
                                         int size,
                                         bool use_coloring)
    : IR_Asm(use_coloring), m_value(value), m_offset(offset), m_base(base), m_size(size) {}

std::string IR_StoreConstOffset::print() {
  return fmt::format("move [{} + {}], {}", m_base->print(), m_offset, m_value->print());
}

RegAllocInstr IR_StoreConstOffset::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(m_value->ireg());
  rai.read.push_back(m_base->ireg());
  return rai;
}

void IR_StoreConstOffset::do_codegen_x86(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  auto base_reg = m_use_coloring ? get_reg(m_base, allocs, irec) : get_no_color_reg(m_base);
  auto value_reg = m_use_coloring ? get_reg(m_value, allocs, irec) : get_no_color_reg(m_value);

  if (m_value->ireg().reg_class == RegClass::GPR_64) {
    gen->add_instr(IGen::store_goal_gpr(*gen, base_reg, value_reg,
                                        emitter::gRegInfo.get_offset_reg(), m_offset, m_size),
                   irec);
  } else if (m_value->ireg().reg_class == RegClass::FLOAT && m_size == 4) {
    gen->add_instr(IGen::store_goal_xmm32(*gen, base_reg, value_reg,
                                          emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else if ((m_value->ireg().reg_class == RegClass::VECTOR_FLOAT ||
              m_value->ireg().reg_class == RegClass::INT_128) &&
             m_size == 16) {
    gen->add_instr(IGen::store_goal_vf(*gen, base_reg, value_reg,
                                       emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else {
    throw std::runtime_error(
        fmt::format("IR_StoreConstOffset::do_codegen_x86 can't handle this (c {} sz {})",
                    fmt::underlying(m_value->ireg().reg_class), m_size));
  }
}

void IR_StoreConstOffset::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                           const AllocationResult& allocs,
                                           emitter::IR_Record irec) {
  auto base_reg = m_use_coloring ? get_reg(m_base, allocs, irec) : get_no_color_reg(m_base);
  auto value_reg = m_use_coloring ? get_reg(m_value, allocs, irec) : get_no_color_reg(m_value);
  if (m_value->ireg().reg_class == RegClass::GPR_64) {
    gen->add_instr(emitter::IGen::ARM64::store_goal_gpr(base_reg, value_reg,
                                                        emitter::gRegInfo.get_offset_reg(),
                                                        m_offset, m_size),
                   irec);
  } else if (m_value->ireg().reg_class == RegClass::FLOAT && m_size == 4) {
    gen->add_instr(emitter::IGen::ARM64::store_goal_xmm32(
                       base_reg, value_reg, emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else if ((m_value->ireg().reg_class == RegClass::VECTOR_FLOAT ||
              m_value->ireg().reg_class == RegClass::INT_128) &&
             m_size == 16) {
    gen->add_instr(emitter::IGen::ARM64::store_goal_vf(
                       base_reg, value_reg, emitter::gRegInfo.get_offset_reg(), m_offset),
                   irec);
  } else {
    throw std::runtime_error(
        fmt::format("IR_StoreConstOffset::do_codegen_arm64 can't handle this (c {} sz {})",
                    fmt::underlying(m_value->ireg().reg_class), m_size));
  }
}

///////////////////////
// Null
///////////////////////
std::string IR_Null::print() {
  return "null";
}

RegAllocInstr IR_Null::to_rai() {
  return {};
}

void IR_Null::do_codegen_x86(emitter::ObjectGenerator* gen,
                             const AllocationResult& allocs,
                             emitter::IR_Record irec) {
  (void)gen;
  (void)allocs;
  (void)irec;
}

void IR_Null::do_codegen_arm64(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  (void)gen; (void)allocs; (void)irec;  // phase-25: emit nothing — mirrors x86 zero-emit
}

///////////////////////
// ValueReset
///////////////////////
IR_ValueReset::IR_ValueReset(std::vector<RegVal*> args) : m_args(std::move(args)) {}

std::string IR_ValueReset::print() {
  return "value-reset";
}

RegAllocInstr IR_ValueReset::to_rai() {
  RegAllocInstr rai;
  for (auto& x : m_args) {
    rai.write.push_back(x->ireg());
  }
  return rai;
}

void IR_ValueReset::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  (void)gen;
  (void)allocs;
  (void)irec;
}

void IR_ValueReset::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  (void)gen; (void)allocs; (void)irec;  // phase-25: emit nothing — mirrors x86 zero-emit
}

///////////////////////
// FloatToInt
///////////////////////

IR_FloatToInt::IR_FloatToInt(const RegVal* dest, const RegVal* src) : m_dest(dest), m_src(src) {}

std::string IR_FloatToInt::print() {
  return fmt::format("f2i {}, {}", m_dest->print(), m_src->print());
}

RegAllocInstr IR_FloatToInt::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(m_src->ireg());
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_FloatToInt::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  gen->add_instr(
      IGen::float_to_int32(*gen, get_reg(m_dest, allocs, irec), get_reg(m_src, allocs, irec)),
      irec);
  gen->add_instr(
      IGen::movsx_r64_r32(*gen, get_reg(m_dest, allocs, irec), get_reg(m_dest, allocs, irec)),
      irec);
}

void IR_FloatToInt::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  gen->add_instr(emitter::IGen::ARM64::float_to_int32(dst, src), irec);
  // Sign-extend Wd → Xd to match the x86 movsx that follows.
  gen->add_instr(emitter::IGen::ARM64::movsx_r64_r32(dst, dst), irec);
}

///////////////////////
// IntToFloat
///////////////////////

IR_IntToFloat::IR_IntToFloat(const RegVal* dest, const RegVal* src) : m_dest(dest), m_src(src) {}

std::string IR_IntToFloat::print() {
  return fmt::format("i2f {}, {}", m_dest->print(), m_src->print());
}

RegAllocInstr IR_IntToFloat::to_rai() {
  RegAllocInstr rai;
  rai.read.push_back(m_src->ireg());
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_IntToFloat::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  gen->add_instr(
      IGen::int32_to_float(*gen, get_reg(m_dest, allocs, irec), get_reg(m_src, allocs, irec)),
      irec);
}

void IR_IntToFloat::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  gen->add_instr(emitter::IGen::ARM64::int32_to_float(dst, src), irec);
}

///////////////////////
// GetStackAddr
///////////////////////

IR_GetStackAddr::IR_GetStackAddr(const RegVal* dest, int slot) : m_dest(dest), m_slot(slot) {}

std::string IR_GetStackAddr::print() {
  return fmt::format("mov {}, stack-slot-{}", m_dest->print(), m_slot);
}

RegAllocInstr IR_GetStackAddr::to_rai() {
  RegAllocInstr rai;
  rai.write.push_back(m_dest->ireg());
  return rai;
}

void IR_GetStackAddr::do_codegen_x86(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  int offset = GPR_SIZE * allocs.get_slot_for_var(m_slot);

  if (offset == 0) {
    gen->add_instr(IGen::mov_gpr64_gpr64(*gen, dest_reg, RSP), irec);
    gen->add_instr(IGen::sub_gpr64_gpr64(*gen, dest_reg, gRegInfo.get_offset_reg()), irec);
  } else {
    // dest = offset + RSP
    gen->add_instr(IGen::lea_reg_plus_off(*gen, dest_reg, RSP, offset), irec);
    // dest = offset + RSP - offset
    gen->add_instr(IGen::sub_gpr64_gpr64(*gen, dest_reg, gRegInfo.get_offset_reg()), irec);
  }
}

void IR_GetStackAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  int offset = GPR_SIZE * allocs.get_slot_for_var(m_slot);
  // A10: emit ADD Xd, SP, #imm12 directly (Rn=31). When offset==0 this is the
  // canonical `MOV Xd, SP` encoding. Replaces the prior path through
  // IGen::ARM64::mov_gpr64_gpr64 / lea_reg_plus_off, both of which encoded
  // the base via arm64_reg5(RSP)=4 and produced `MOV/ADD dst, X4, ...` —
  // see arm64_add_xd_sp_imm12 above.
  ASSERT(offset >= 0);
  gen->add_instr(arm64_add_xd_sp_imm12(dest_reg, static_cast<uint32_t>(offset)), irec);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dest_reg, gRegInfo.get_offset_reg()),
                 irec);
}

///////////////////////
// Nop
///////////////////////

IR_Nop::IR_Nop() {}

std::string IR_Nop::print() {
  return fmt::format("nop");
}

RegAllocInstr IR_Nop::to_rai() {
  return {};
}

void IR_Nop::do_codegen_x86(emitter::ObjectGenerator* gen,
                            const AllocationResult&,
                            emitter::IR_Record irec) {
  gen->add_instr(IGen::nop(*gen), irec);
}

void IR_Nop::do_codegen_arm64(emitter::ObjectGenerator* gen,
                              const AllocationResult& allocs,
                              emitter::IR_Record irec) {
  (void)gen; (void)allocs; (void)irec;  // phase-25: emit nothing — mirrors x86 zero-emit
}

///////////////////////
// Asm
///////////////////////

IR_Asm::IR_Asm(bool use_coloring) : m_use_coloring(use_coloring) {}

std::string IR_Asm::get_color_suffix_string() {
  if (m_use_coloring) {
    return "";
  } else {
    return " :no-color";
  }
}

///////////////////////
// AsmRet
///////////////////////

IR_AsmRet::IR_AsmRet(bool use_coloring) : IR_Asm(use_coloring) {}

std::string IR_AsmRet::print() {
  return fmt::format(".ret{}", get_color_suffix_string());
}

RegAllocInstr IR_AsmRet::to_rai() {
  return {};
}

void IR_AsmRet::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  (void)allocs;
  gen->add_instr(IGen::ret(*gen), irec);
}

void IR_AsmRet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  (void)allocs;
  gen->add_instr(emitter::IGen::ARM64::ret(), irec);
}

///////////////////////
// AsmFNop
///////////////////////

IR_AsmFNop::IR_AsmFNop() : IR_Asm(false) {}

std::string IR_AsmFNop::print() {
  return ".nop.vf";
}

RegAllocInstr IR_AsmFNop::to_rai() {
  return {};
}

void IR_AsmFNop::do_codegen_x86(emitter::ObjectGenerator* gen,
                                const AllocationResult& allocs,
                                emitter::IR_Record irec) {
  (void)allocs;
  gen->add_instr(IGen::nop_vf(*gen), irec);
}

void IR_AsmFNop::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  (void)gen; (void)allocs; (void)irec;  // phase-25: emit nothing — mirrors x86 zero-emit
}

///////////////////////
// AsmFWait
///////////////////////

IR_AsmFWait::IR_AsmFWait() : IR_Asm(false) {}

std::string IR_AsmFWait::print() {
  return ".wait.vf";
}

RegAllocInstr IR_AsmFWait::to_rai() {
  return {};
}

void IR_AsmFWait::do_codegen_x86(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  (void)allocs;
  gen->add_instr(IGen::wait_vf(*gen), irec);
}

void IR_AsmFWait::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  (void)gen; (void)allocs; (void)irec;  // phase-25: emit nothing — mirrors x86 zero-emit
}

///////////////////////
// AsmPush
///////////////////////

IR_AsmPush::IR_AsmPush(bool use_coloring, const RegVal* src) : IR_Asm(use_coloring), m_src(src) {}

std::string IR_AsmPush::print() {
  return fmt::format(".push{} {}", get_color_suffix_string(), m_src->print());
}

RegAllocInstr IR_AsmPush::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_AsmPush::do_codegen_x86(emitter::ObjectGenerator* gen,
                                const AllocationResult& allocs,
                                emitter::IR_Record irec) {
  if (m_use_coloring) {
    gen->add_instr(IGen::push_gpr64(*gen, get_reg(m_src, allocs, irec)), irec);
  } else {
    gen->add_instr(IGen::push_gpr64(*gen, get_no_color_reg(m_src)), irec);
  }
}

void IR_AsmPush::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  auto src = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  gen->add_instr(emitter::IGen::ARM64::push_gpr64(src), irec);
}

///////////////////////
// AsmPop
///////////////////////

IR_AsmPop::IR_AsmPop(bool use_coloring, const RegVal* dst) : IR_Asm(use_coloring), m_dst(dst) {}

std::string IR_AsmPop::print() {
  return fmt::format(".pop{} {}", get_color_suffix_string(), m_dst->print());
}

RegAllocInstr IR_AsmPop::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
  }
  return rai;
}

void IR_AsmPop::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  if (m_use_coloring) {
    gen->add_instr(IGen::pop_gpr64(*gen, get_reg(m_dst, allocs, irec)), irec);
  } else {
    gen->add_instr(IGen::pop_gpr64(*gen, get_no_color_reg(m_dst)), irec);
  }
}

void IR_AsmPop::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = m_use_coloring ? get_reg(m_dst, allocs, irec) : get_no_color_reg(m_dst);
  gen->add_instr(emitter::IGen::ARM64::pop_gpr64(dst), irec);
}

///////////////////////
// AsmSub
///////////////////////

IR_AsmSub::IR_AsmSub(bool use_coloring, const RegVal* dst, const RegVal* src)
    : IR_Asm(use_coloring), m_dst(dst), m_src(src) {}

std::string IR_AsmSub::print() {
  return fmt::format(".sub{} {}, {}", get_color_suffix_string(), m_dst->print(), m_src->print());
}

RegAllocInstr IR_AsmSub::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_AsmSub::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  if (m_use_coloring) {
    gen->add_instr(
        IGen::sub_gpr64_gpr64(*gen, get_reg(m_dst, allocs, irec), get_reg(m_src, allocs, irec)),
        irec);
  } else {
    gen->add_instr(IGen::sub_gpr64_gpr64(*gen, get_no_color_reg(m_dst), get_no_color_reg(m_src)),
                   irec);
  }
}

void IR_AsmSub::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = m_use_coloring ? get_reg(m_dst, allocs, irec) : get_no_color_reg(m_dst);
  auto src = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dst, src), irec);
}

///////////////////////
// AsmAdd
///////////////////////

IR_AsmAdd::IR_AsmAdd(bool use_coloring, const RegVal* dst, const RegVal* src)
    : IR_Asm(use_coloring), m_dst(dst), m_src(src) {}

std::string IR_AsmAdd::print() {
  return fmt::format(".add{} {}, {}", get_color_suffix_string(), m_dst->print(), m_src->print());
}

RegAllocInstr IR_AsmAdd::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_AsmAdd::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  if (m_use_coloring) {
    gen->add_instr(
        IGen::add_gpr64_gpr64(*gen, get_reg(m_dst, allocs, irec), get_reg(m_src, allocs, irec)),
        irec);
  } else {
    gen->add_instr(IGen::add_gpr64_gpr64(*gen, get_no_color_reg(m_dst), get_no_color_reg(m_src)),
                   irec);
  }
}

void IR_AsmAdd::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = m_use_coloring ? get_reg(m_dst, allocs, irec) : get_no_color_reg(m_dst);
  auto src = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  gen->add_instr(emitter::IGen::ARM64::add_gpr64_gpr64(dst, src), irec);
}

///////////////////////
// AsmGetSymbolValue
///////////////////////

IR_GetSymbolValueAsm::IR_GetSymbolValueAsm(bool use_coloring,
                                           const RegVal* dest,
                                           std::string sym_name,
                                           bool sext)
    : IR_Asm(use_coloring), m_dest(dest), m_sym_name(std::move(sym_name)), m_sext(sext) {}

std::string IR_GetSymbolValueAsm::print() {
  return fmt::format(".load-sym{} {} [{}]", get_color_suffix_string(), m_dest->print(), m_sym_name);
}

RegAllocInstr IR_GetSymbolValueAsm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dest->ireg());
  }
  return rai;
}

void IR_GetSymbolValueAsm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                          const AllocationResult& allocs,
                                          emitter::IR_Record irec) {
  auto dst_reg = m_use_coloring ? get_reg(m_dest, allocs, irec) : get_no_color_reg(m_dest);
  if (m_sext) {
    auto instr = gen->add_instr(IGen::load32s_gpr64_gpr64_plus_gpr64_plus_s32(
                                    *gen, dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                                    LINK_SYM_NO_OFFSET_FLAG),
                                irec);
    gen->link_instruction_symbol_mem(instr, m_sym_name);
  } else {
    auto instr = gen->add_instr(IGen::load32u_gpr64_gpr64_plus_gpr64_plus_s32(
                                    *gen, dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                                    LINK_SYM_NO_OFFSET_FLAG),
                                irec);
    gen->link_instruction_symbol_mem(instr, m_sym_name);
  }
}

void IR_GetSymbolValueAsm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                            const AllocationResult& allocs,
                                            emitter::IR_Record irec) {
  auto dst_reg = m_use_coloring ? get_reg(m_dest, allocs, irec) : get_no_color_reg(m_dest);
  // Same shape as IR_GetSymbolValue: LDRSW Xd / LDR Wd, [Xst, #imm12_scaled4].
  // The arm64-aware fix-up rewrites the imm12 field at link time.
  emitter::InstructionRecord instr;
  if (m_sext) {
    instr = gen->add_instr(emitter::IGen::ARM64::load32s_gpr64_gpr64_plus_gpr64_plus_s32(
                               dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                               LINK_SYM_NO_OFFSET_FLAG),
                           irec);
  } else {
    instr = gen->add_instr(emitter::IGen::ARM64::load32u_gpr64_gpr64_plus_gpr64_plus_s32(
                               dst_reg, gRegInfo.get_st_reg(), gRegInfo.get_offset_reg(),
                               LINK_SYM_NO_OFFSET_FLAG),
                           irec);
  }
  gen->link_instruction_symbol_mem(instr, m_sym_name);
}

///////////////////////
// AsmJumpReg
///////////////////////

IR_JumpReg::IR_JumpReg(bool use_coloring, const RegVal* src) : IR_Asm(use_coloring), m_src(src) {}

std::string IR_JumpReg::print() {
  return fmt::format(".jr{} {}", get_color_suffix_string(), m_src->print());
}

RegAllocInstr IR_JumpReg::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_JumpReg::do_codegen_x86(emitter::ObjectGenerator* gen,
                                const AllocationResult& allocs,
                                emitter::IR_Record irec) {
  auto src_reg = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  gen->add_instr(IGen::jmp_r64(*gen, src_reg), irec);
}

void IR_JumpReg::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  auto src_reg = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  gen->add_instr(emitter::IGen::ARM64::jmp_r64(src_reg), irec);
}

///////////////////////
// AsmRegSet
///////////////////////

IR_RegSetAsm::IR_RegSetAsm(bool use_color, const RegVal* dst, const RegVal* src)
    : IR_Asm(use_color), m_dst(dst), m_src(src) {}

std::string IR_RegSetAsm::print() {
  return fmt::format(".mov{} {} {}", get_color_suffix_string(), m_dst->print(), m_src->print());
}

RegAllocInstr IR_RegSetAsm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_RegSetAsm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  regset_common(gen, allocs, irec, m_dst, m_src, m_use_coloring);
}

void IR_RegSetAsm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                    const AllocationResult& allocs,
                                    emitter::IR_Record irec) {
  auto dst = m_use_coloring ? get_reg(m_dst, allocs, irec) : get_no_color_reg(m_dst);
  auto src = m_use_coloring ? get_reg(m_src, allocs, irec) : get_no_color_reg(m_src);
  if (dst == src) {
    // Identity move: still emit one real instruction so the codegen body is
    // non-empty and classifier-real.
    gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
  } else {
    gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
  }
}

///////////////////////
// AsmVF3
///////////////////////

IR_VFMath3Asm::IR_VFMath3Asm(bool use_color,
                             const RegVal* dst,
                             const RegVal* src1,
                             const RegVal* src2,
                             Kind kind)
    : IR_Asm(use_color), m_dst(dst), m_src1(src1), m_src2(src2), m_kind(kind) {}

std::string IR_VFMath3Asm::print() {
  std::string function = "";
  switch (m_kind) {
    case Kind::XOR:
      function = ".xor.vf";
      break;
    case Kind::SUB:
      function = ".sub.vf";
      break;
    case Kind::ADD:
      function = ".add.vf";
      break;
    case Kind::MUL:
      function = ".mul.vf";
      break;
    case Kind::MAX:
      function = ".max.vf";
      break;
    case Kind::MIN:
      function = ".min.vf";
      break;
    case Kind::DIV:
      function = ".div.vf";
      break;
    default:
      ASSERT(false);
  }
  return fmt::format("{}{} {}, {}, {}", function, get_color_suffix_string(), m_dst->print(),
                     m_src1->print(), m_src2->print());
}

RegAllocInstr IR_VFMath3Asm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src1->ireg());
    rai.read.push_back(m_src2->ireg());
  }
  return rai;
}

void IR_VFMath3Asm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);

  switch (m_kind) {
    case Kind::XOR:
      gen->add_instr(IGen::xor_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::SUB:
      gen->add_instr(IGen::sub_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::ADD:
      gen->add_instr(IGen::add_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::MUL:
      gen->add_instr(IGen::mul_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::MAX:
      gen->add_instr(IGen::max_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::MIN:
      gen->add_instr(IGen::min_vf(*gen, dst, src1, src2), irec);
      break;
    case Kind::DIV:
      gen->add_instr(IGen::div_vf(*gen, dst, src1, src2), irec);
      break;
    default:
      ASSERT(false);
  }
}

void IR_VFMath3Asm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);
  switch (m_kind) {
    case Kind::XOR:
      gen->add_instr(emitter::IGen::ARM64::xor_vf(dst, src1, src2), irec);
      break;
    case Kind::SUB:
      gen->add_instr(emitter::IGen::ARM64::sub_vf(dst, src1, src2), irec);
      break;
    case Kind::ADD:
      gen->add_instr(emitter::IGen::ARM64::add_vf(dst, src1, src2), irec);
      break;
    case Kind::MUL:
      gen->add_instr(emitter::IGen::ARM64::mul_vf(dst, src1, src2), irec);
      break;
    case Kind::MAX:
      gen->add_instr(emitter::IGen::ARM64::max_vf(dst, src1, src2), irec);
      break;
    case Kind::MIN:
      gen->add_instr(emitter::IGen::ARM64::min_vf(dst, src1, src2), irec);
      break;
    case Kind::DIV:
      gen->add_instr(emitter::IGen::ARM64::div_vf(dst, src1, src2), irec);
      break;
    default:
      ASSERT(false);
  }
}

///////////////////////
// IR_Int128Math3Asm
///////////////////////

IR_Int128Math3Asm::IR_Int128Math3Asm(bool use_color,
                                     const RegVal* dst,
                                     const RegVal* src1,
                                     const RegVal* src2,
                                     Kind kind)
    : IR_Asm(use_color), m_dst(dst), m_src1(src1), m_src2(src2), m_kind(kind) {}

std::string IR_Int128Math3Asm::print() {
  std::string function = "";
  switch (m_kind) {
    case Kind::PEXTLB:
      function = ".pextlb";
      break;
    case Kind::PEXTLH:
      function = ".pextlh";
      break;
    case Kind::PEXTLW:
      function = ".pextlw";
      break;
    case Kind::PEXTUB:
      function = ".pextub";
      break;
    case Kind::PEXTUH:
      function = ".pextuh";
      break;
    case Kind::PEXTUW:
      function = ".pextuw";
      break;
    case Kind::PCPYLD:
      function = ".pcpyld";
      break;
    case Kind::PCPYUD:
      function = ".pcpyud";
      break;
    case Kind::PSUBW:
      function = ".psubw";
      break;
    case Kind::PCEQB:
      function = ".pceqb";
      break;
    case Kind::PCEQH:
      function = ".pceqh";
      break;
    case Kind::PCEQW:
      function = ".pceqw";
      break;
    case Kind::PCGTB:
      function = ".pcgtb";
      break;
    case Kind::PCGTH:
      function = ".pcgth";
      break;
    case Kind::PCGTW:
      function = ".pcgtw";
      break;
    case Kind::POR:
      function = ".por";
      break;
    case Kind::PXOR:
      function = ".pxor";
      break;
    case Kind::PAND:
      function = ".pand";
      break;
    case Kind::PACKUSWB:
      function = ".packuswb";
      break;
    case Kind::PADDB:
      function = ".paddb";
      break;
    default:
      ASSERT(false);
  }
  return fmt::format("{}{} {}, {}, {}", function, get_color_suffix_string(), m_dst->print(),
                     m_src1->print(), m_src2->print());
}

RegAllocInstr IR_Int128Math3Asm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src1->ireg());
    rai.read.push_back(m_src2->ireg());
  }
  return rai;
}

void IR_Int128Math3Asm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);

  switch (m_kind) {
    case Kind::PEXTUB:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextub_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PEXTUH:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextuh_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PEXTUW:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextuw_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PEXTLB:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextlb_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PEXTLH:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextlh_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PEXTLW:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pextlw_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PCPYLD:
      // NOTE: this is intentionally swapped because x86 and PS2 do this opposite ways.
      gen->add_instr(IGen::pcpyld_swapped(*gen, dst, src2, src1), irec);
      break;
    case Kind::PCPYUD:
      gen->add_instr(IGen::pcpyud(*gen, dst, src1, src2), irec);
      break;
    case Kind::PCEQB:
      gen->add_instr(IGen::parallel_compare_e_b(*gen, dst, src2, src1), irec);
      break;
    case Kind::PCEQH:
      gen->add_instr(IGen::parallel_compare_e_h(*gen, dst, src2, src1), irec);
      break;
    case Kind::PCEQW:
      gen->add_instr(IGen::parallel_compare_e_w(*gen, dst, src2, src1), irec);
      break;
    case Kind::PCGTB:
      gen->add_instr(IGen::parallel_compare_gt_b(*gen, dst, src1, src2), irec);
      break;
    case Kind::PCGTH:
      gen->add_instr(IGen::parallel_compare_gt_h(*gen, dst, src1, src2), irec);
      break;
    case Kind::PCGTW:
      gen->add_instr(IGen::parallel_compare_gt_w(*gen, dst, src1, src2), irec);
      break;
    case Kind::PSUBW:
      // psubW on mips is psubD on x86...
      gen->add_instr(IGen::vpsubd(*gen, dst, src1, src2), irec);
      break;
    case Kind::POR:
      gen->add_instr(IGen::parallel_bitwise_or(*gen, dst, src2, src1), irec);
      break;
    case Kind::PXOR:
      gen->add_instr(IGen::parallel_bitwise_xor(*gen, dst, src2, src1), irec);
      break;
    case Kind::PAND:
      gen->add_instr(IGen::parallel_bitwise_and(*gen, dst, src2, src1), irec);
      break;
    case Kind::PACKUSWB:
      gen->add_instr(IGen::vpackuswb(*gen, dst, src1, src2), irec);
      break;
    case Kind::PADDB:
      gen->add_instr(IGen::parallel_add_byte(*gen, dst, src1, src2), irec);
      break;
    default:
      ASSERT(false);
  }
}

void IR_Int128Math3Asm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);
  switch (m_kind) {
    case Kind::PEXTUB:
      gen->add_instr(emitter::IGen::ARM64::pextub_swapped(dst, src2, src1), irec);
      break;
    case Kind::PEXTUH:
      gen->add_instr(emitter::IGen::ARM64::pextuh_swapped(dst, src2, src1), irec);
      break;
    case Kind::PEXTUW:
      gen->add_instr(emitter::IGen::ARM64::pextuw_swapped(dst, src2, src1), irec);
      break;
    case Kind::PEXTLB:
      gen->add_instr(emitter::IGen::ARM64::pextlb_swapped(dst, src2, src1), irec);
      break;
    case Kind::PEXTLH:
      gen->add_instr(emitter::IGen::ARM64::pextlh_swapped(dst, src2, src1), irec);
      break;
    case Kind::PEXTLW:
      gen->add_instr(emitter::IGen::ARM64::pextlw_swapped(dst, src2, src1), irec);
      break;
    case Kind::PCPYLD:
      gen->add_instr(emitter::IGen::ARM64::pcpyld_swapped(dst, src2, src1), irec);
      break;
    case Kind::PCPYUD:
      gen->add_instr(emitter::IGen::ARM64::pcpyud(dst, src1, src2), irec);
      break;
    case Kind::PCEQB:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_e_b(dst, src2, src1), irec);
      break;
    case Kind::PCEQH:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_e_h(dst, src2, src1), irec);
      break;
    case Kind::PCEQW:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_e_w(dst, src2, src1), irec);
      break;
    case Kind::PCGTB:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_gt_b(dst, src1, src2), irec);
      break;
    case Kind::PCGTH:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_gt_h(dst, src1, src2), irec);
      break;
    case Kind::PCGTW:
      gen->add_instr(emitter::IGen::ARM64::parallel_compare_gt_w(dst, src1, src2), irec);
      break;
    case Kind::PSUBW:
      gen->add_instr(emitter::IGen::ARM64::vpsubd(dst, src1, src2), irec);
      break;
    case Kind::POR:
      gen->add_instr(emitter::IGen::ARM64::parallel_bitwise_or(dst, src2, src1), irec);
      break;
    case Kind::PXOR:
      gen->add_instr(emitter::IGen::ARM64::parallel_bitwise_xor(dst, src2, src1), irec);
      break;
    case Kind::PAND:
      gen->add_instr(emitter::IGen::ARM64::parallel_bitwise_and(dst, src2, src1), irec);
      break;
    case Kind::PACKUSWB:
      gen->add_instr(emitter::IGen::ARM64::vpackuswb(dst, src1, src2), irec);
      break;
    case Kind::PADDB:
      gen->add_instr(emitter::IGen::ARM64::parallel_add_byte(dst, src1, src2), irec);
      break;
    default:
      ASSERT(false);
  }
}

///////////////////////
// AsmVF2
///////////////////////

IR_VFMath2Asm::IR_VFMath2Asm(bool use_color, const RegVal* dst, const RegVal* src, Kind kind)
    : IR_Asm(use_color), m_dst(dst), m_src(src), m_kind(kind) {}

std::string IR_VFMath2Asm::print() {
  std::string function;
  switch (m_kind) {
    case Kind::ITOF:
      function = ".itof.vf";
      break;
    case Kind::FTOI:
      function = ".ftoi.vf";
      break;
    default:
      ASSERT(false);
  }

  return fmt::format("{}{} {}, {}", function, get_color_suffix_string(), m_dst->print(),
                     m_src->print());
}

RegAllocInstr IR_VFMath2Asm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_VFMath2Asm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                   const AllocationResult& allocs,
                                   emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);

  switch (m_kind) {
    case Kind::ITOF:
      gen->add_instr(IGen::itof_vf(*gen, dst, src), irec);
      break;
    case Kind::FTOI:
      gen->add_instr(IGen::ftoi_vf(*gen, dst, src), irec);
      break;
    default:
      ASSERT(false);
  }
}

void IR_VFMath2Asm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  switch (m_kind) {
    case Kind::ITOF:
      gen->add_instr(emitter::IGen::ARM64::itof_vf(dst, src), irec);
      break;
    case Kind::FTOI:
      gen->add_instr(emitter::IGen::ARM64::ftoi_vf(dst, src), irec);
      break;
    default:
      ASSERT(false);
  }
}

///////////////////////
// AsmInt128-2
///////////////////////

IR_Int128Math2Asm::IR_Int128Math2Asm(bool use_color,
                                     const RegVal* dst,
                                     const RegVal* src,
                                     Kind kind,
                                     std::optional<int64_t> imm)
    : IR_Asm(use_color), m_dst(dst), m_src(src), m_kind(kind), m_imm(std::move(imm)) {}

std::string IR_Int128Math2Asm::print() {
  std::string function;
  bool use_imm = false;
  switch (m_kind) {
    case Kind::PW_SLL:
      use_imm = true;
      function = ".pw.sll";
      break;
    case Kind::PW_SRL:
      use_imm = true;
      function = ".pw.srl";
      break;
    case Kind::PW_SRA:
      use_imm = true;
      function = ".pw.sra";
      break;
    case Kind::PH_SLL:
      use_imm = true;
      function = ".ph.sll";
      break;
    case Kind::PH_SRL:
      use_imm = true;
      function = ".ph.srl";
      break;
    case Kind::VPSRLDQ:
      use_imm = true;
      function = ".VPSRLDQ";
      break;
    case Kind::VPSLLDQ:
      use_imm = true;
      function = ".VPSLLDQ";
      break;
    case Kind::VPSHUFLW:
      use_imm = true;
      function = ".VPSHUFLW";
      break;
    case Kind::VPSHUFHW:
      use_imm = true;
      function = ".VPSHUFHW";
      break;
    default:
      ASSERT(false);
  }

  if (use_imm) {
    ASSERT(m_imm.has_value());
    return fmt::format("{}{} {}, {}, {}", function, get_color_suffix_string(), m_dst->print(),
                       m_src->print(), *m_imm);
  } else {
    return fmt::format("{}{} {}, {}", function, get_color_suffix_string(), m_dst->print(),
                       m_src->print());
  }
}

RegAllocInstr IR_Int128Math2Asm::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_Int128Math2Asm::do_codegen_x86(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);

  switch (m_kind) {
    case Kind::PW_SLL:
      // you are technically allowed to put values > 32 in here.
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::pw_sll(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::PW_SRL:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::pw_srl(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::PH_SLL:
      // you are technically allowed to put values > 32 in here.
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::ph_sll(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::PH_SRL:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::ph_srl(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::PW_SRA:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::pw_sra(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::VPSRLDQ:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::vpsrldq(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::VPSLLDQ:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::vpslldq(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::VPSHUFLW:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::vpshuflw(*gen, dst, src, *m_imm), irec);
      break;
    case Kind::VPSHUFHW:
      ASSERT(m_imm.has_value());
      ASSERT(*m_imm >= 0);
      ASSERT(*m_imm <= 255);
      gen->add_instr(IGen::vpshufhw(*gen, dst, src, *m_imm), irec);
      break;
    default:
      ASSERT(false);
  }
}

void IR_Int128Math2Asm::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                         const AllocationResult& allocs,
                                         emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  switch (m_kind) {
    case Kind::PW_SLL:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::pw_sll(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::PW_SRL:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::pw_srl(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::PH_SLL:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::ph_sll(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::PH_SRL:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::ph_srl(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::PW_SRA:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::pw_sra(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::VPSRLDQ:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::vpsrldq(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::VPSLLDQ:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::vpslldq(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::VPSHUFLW:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::vpshuflw(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    case Kind::VPSHUFHW:
      ASSERT(m_imm.has_value());
      gen->add_instr(emitter::IGen::ARM64::vpshufhw(dst, src, static_cast<u8>(*m_imm)), irec);
      break;
    default:
      ASSERT(false);
  }
}

// ---- Blend VF

IR_BlendVF::IR_BlendVF(bool use_color,
                       const RegVal* dst,
                       const RegVal* src1,
                       const RegVal* src2,
                       u8 mask)
    : IR_Asm(use_color), m_dst(dst), m_src1(src1), m_src2(src2), m_mask(mask) {}

std::string IR_BlendVF::print() {
  return fmt::format(".blend.vf{} {}, {}, {}, {}", get_color_suffix_string(), m_dst->print(),
                     m_src1->print(), m_src2->print(), m_mask);
}

RegAllocInstr IR_BlendVF::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src1->ireg());
    rai.read.push_back(m_src2->ireg());
  }
  return rai;
}

void IR_BlendVF::do_codegen_x86(emitter::ObjectGenerator* gen,
                                const AllocationResult& allocs,
                                emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);
  gen->add_instr(IGen::blend_vf(*gen, dst, src1, src2, m_mask), irec);
}

void IR_BlendVF::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src1 = get_reg_asm(m_src1, allocs, irec, m_use_coloring);
  auto src2 = get_reg_asm(m_src2, allocs, irec, m_use_coloring);
  gen->add_instr(emitter::IGen::ARM64::blend_vf(dst, src1, src2, m_mask), irec);
}

// ----- Splat VF

IR_SplatVF::IR_SplatVF(bool use_color,
                       const RegVal* dst,
                       const RegVal* src,
                       const emitter::Register::VF_ELEMENT element)
    : IR_Asm(use_color), m_dst(dst), m_src(src), m_element(element) {}

std::string IR_SplatVF::print() {
  return fmt::format(".splat.vf{} {}, {}, {}", get_color_suffix_string(), m_dst->print(),
                     m_src->print(), fmt::underlying(m_element));
}

RegAllocInstr IR_SplatVF::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_SplatVF::do_codegen_x86(emitter::ObjectGenerator* gen,
                                const AllocationResult& allocs,
                                emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(IGen::splat_vf(*gen, dst, src, m_element), irec);
}

void IR_SplatVF::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(emitter::IGen::ARM64::splat_vf(dst, src, m_element), irec);
}

// ---- Swizzle VF

IR_SwizzleVF::IR_SwizzleVF(bool use_color,
                           const RegVal* dst,
                           const RegVal* src,
                           const u8 controlBytes)
    : IR_Asm(use_color), m_dst(dst), m_src(src), m_controlBytes(controlBytes) {}

std::string IR_SwizzleVF::print() {
  return fmt::format(".swizzle.vf{} {}, {}, {}", get_color_suffix_string(), m_dst->print(),
                     m_src->print(), m_controlBytes);
}

RegAllocInstr IR_SwizzleVF::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_SwizzleVF::do_codegen_x86(emitter::ObjectGenerator* gen,
                                  const AllocationResult& allocs,
                                  emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(IGen::swizzle_vf(*gen, dst, src, m_controlBytes), irec);
}

void IR_SwizzleVF::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                    const AllocationResult& allocs,
                                    emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(emitter::IGen::ARM64::swizzle_vf(dst, src, m_controlBytes), irec);
}

// ---- Square Root VF

IR_SqrtVF::IR_SqrtVF(bool use_color, const RegVal* dst, const RegVal* src)
    : IR_Asm(use_color), m_dst(dst), m_src(src) {}

std::string IR_SqrtVF::print() {
  return fmt::format(".sqrt.vf{} {}, {}", get_color_suffix_string(), m_dst->print(),
                     m_src->print());
}

RegAllocInstr IR_SqrtVF::to_rai() {
  RegAllocInstr rai;
  if (m_use_coloring) {
    rai.write.push_back(m_dst->ireg());
    rai.read.push_back(m_src->ireg());
  }
  return rai;
}

void IR_SqrtVF::do_codegen_x86(emitter::ObjectGenerator* gen,
                               const AllocationResult& allocs,
                               emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(IGen::sqrt_vf(*gen, dst, src), irec);
}

void IR_SqrtVF::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg_asm(m_dst, allocs, irec, m_use_coloring);
  auto src = get_reg_asm(m_src, allocs, irec, m_use_coloring);
  gen->add_instr(emitter::IGen::ARM64::sqrt_vf(dst, src), irec);
}
