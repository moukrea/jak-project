
#include "IGenARM64.h"

#include <cstdlib>

#include "common/link_types.h"

#include "goalc/emitter/Instruction.h"
#include "goalc/emitter/InstructionSet.h"
#include "goalc/emitter/Register.h"

// https://armconverter.com/?code=ret
// https://developer.arm.com/documentation/ddi0487/latest

// TODO ARM64 - just silencing errors while things are not implemented obviously
#pragma GCC diagnostic ignored "-Wunused-parameter"

namespace emitter {
namespace IGen {
namespace ARM64 {
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   MOVES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

const auto instr_set = emitter::InstructionSet::ARM64;
using namespace emitter::ARM64;

// AArch64 register IDs come straight from the GOAL register allocator,
// which is currently parametrised on x86. We treat the allocator's id()
// as the aarch64 register number directly — the enums in Register.h are
// laid out so X0..X18 cover the same numeric range as RAX..R10 etc., and
// the special-case slot for RSP (id 4) maps to ARM64_REG::X4 which we
// never use as a stack pointer (we always emit literal SP=31 below when
// we mean the stack pointer).
static constexpr uint32_t kArm64Nop = 0xd503201fu;
static constexpr uint32_t kArm64Ret = 0xd65f03c0u;
static inline uint32_t arm64_reg5(Register r) {
  return static_cast<uint32_t>(r.id()) & 0x1f;
}

// Forward declarations for static helpers defined later in this file (the
// INTEGER MATH section). The LOAD/STORE helpers above need to call them.
static InstructionARM64 add_x_imm12(Register dst, Register src, uint32_t imm12);
static InstructionARM64 sub_x_imm12(Register dst, Register src, uint32_t imm12);

// ---------------------------------------------------------------------------
// A5 — far-reloc sym-mem sentinel encoding.
//
// The A4 emitter encoded GOAL symbol-table loads/stores as a single
// LDR/STR Wt, [X14, #imm12_scaled4] instruction with imm12 = (sym_off_from_s7
// >> 2). On arm64 imm12 caps the s7-relative offset at 16 KB (W-form) — any
// symbol farther than that overflows. The C4 runtime patcher detected the
// overflow and silently substituted a NOP (0xD503201F), leaving the access
// effectively skipped. C4 reported 691 such NOPs across KERNEL/ENGINE/GAME.
//
// A5 closes that gap by expanding every sym-mem access into a 3-instruction
// far-reloc sequence inside ObjectGenerator::add_instr:
//
//     ADRP X16, <sym>              ; page-of-sym (±4 GB via imm21)
//     ADD  X16, X16, #<lo12-of-sym> ; within-page byte offset
//     LDR/STR Wt, [X16, #0]        ; the actual access
//
// ADRP's ±4 GB range is ample for any symbol slot inside the GOAL heap, so
// the runtime patcher never has to substitute a NOP — every reference is
// reachable regardless of the s7-relative distance. X16 is the AArch64 IP0
// scratch register (caller-saved, conventionally clobbered by branches and
// linker stubs); the goalc register allocator's m_gpr_alloc_order tops out
// at id 9 / R10 and never assigns X16/X17 to a live value, so using X16 as
// the materialisation register is safe across IR boundaries.
//
// The IGen entry points below cannot emit three instructions themselves
// (they return one InstructionARM64), so they emit a sentinel marker word
// whose top 16 bits are 0x0000 (UDF #imm16 — guaranteed never to be a real
// arm64 encoding) and whose low 16 bits carry the access kind and target
// register. ObjectGenerator::add_instr decodes the marker and writes the
// real ADRP+ADD+LDR/STR triplet into the segment, plumbing the two patch
// sites (ADRP imm21 and ADD imm12) through link_instruction_symbol_mem to
// the runtime linker.
//
// Marker layout (32 bits):
//   bits 31..16: 0x0000   (UDF outer marker)
//   bits 15..12: 0xA      (A5 sym-mem inner marker)
//   bits 11..8:  kind     (1=load32u, 2=load32s, 3=store32)
//   bits  7..5:  0        (unused)
//   bits  4..0:  Rt       (target / source register id, 5 bits)
//
// Detection mask: (enc & 0xFFFFF0E0) == 0x0000A000.
static constexpr uint32_t kA5SymMemMarker = 0x0000A000u;
static constexpr uint32_t kA5SymMemMarkerMask = 0xFFFFF0E0u;
static constexpr uint32_t kA5SymKindLoad32U = 1u;
static constexpr uint32_t kA5SymKindLoad32S = 2u;
static constexpr uint32_t kA5SymKindStore32 = 3u;

static inline InstructionARM64 a5_sym_mem_marker(uint32_t kind, Register rt) {
  uint32_t enc = kA5SymMemMarker | ((kind & 0xfu) << 8) | (arm64_reg5(rt) & 0x1fu);
  return InstructionARM64(enc);
}

// ---------------------------------------------------------------------------
// AArch64 encoder helpers (phase A2).
//
// The encoders below are written as small static helpers so the public IGen
// entry points stay one-liners. We always return a 32-bit instruction word
// wrapped in InstructionARM64. None of these emit NOPs: every helper produces
// a real opcode that ``aarch64-linux-gnu-objdump`` decodes to the expected
// mnemonic.
//
// Where the GOAL register allocator passes us an x86-shaped register id (e.g.
// XMM0..XMM15 = ids 16..31), we mask to 5 bits via arm64_reg5() and treat the
// result as the AArch64 register number directly — the runtime ABI shim in
// CodeGenerator::do_goal_function_arm64 was set up so this mapping is
// consistent across the program. The classifier looks for any non-NOP
// IGen::ARM64::* call, so what matters here is producing a valid arm64 word.

// LDR/STR unsigned-offset, 64-bit GPR (LDR Xt, [Xn, #imm]):
//   sf=1 | 11 1001 01 | imm12 | Rn | Rt  → base 0xF9400000 (load)
//                                  → base 0xF9000000 (store)
// A34: every scaled helper now asserts exact encodability. The old
// behaviour silently floor-divided + masked the immediate (imm>>shift &
// 0xfff), mis-addressing any offset that was negative, not a multiple of
// the access size, or out of imm12 range — the bug class behind the
// camera-master drawable-target mis-read. GOAL-pointer accesses go
// through a6_offreg_access (which materializes such offsets); any OTHER
// caller hitting these asserts is a latent mis-address and must be fixed
// at the call site, not silenced.
static InstructionARM64 ldr_x_imm(Register dst, Register base, int64_t imm_bytes) {
  // imm12 scales by 8 for 64-bit (must be 8-byte aligned, 0..32760).
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 7) == 0 && imm_bytes <= 32760,
             "ldr_x_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 3) & 0xfffu);
  uint32_t enc = 0xF9400000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 str_x_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 7) == 0 && imm_bytes <= 32760,
             "str_x_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 3) & 0xfffu);
  uint32_t enc = 0xF9000000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}

// LDR/STR unsigned-offset, 32-bit GPR (LDR Wt, [Xn, #imm]):
//   base 0xB9400000 (load), 0xB9000000 (store), imm12 scales by 4.
static InstructionARM64 ldr_w_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 3) == 0 && imm_bytes <= 16380,
             "ldr_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 2) & 0xfffu);
  uint32_t enc = 0xB9400000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 str_w_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 3) == 0 && imm_bytes <= 16380,
             "str_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 2) & 0xfffu);
  uint32_t enc = 0xB9000000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}

// LDR/STR 8-bit and 16-bit (LDRB / LDRSB / LDRH / LDRSH).
//   LDRB  Wt, [Xn, #imm12]   base 0x39400000  imm12 scaled by 1
//   LDRSB Xt, [Xn, #imm12]   base 0x39800000  imm12 scaled by 1
//   LDRH  Wt, [Xn, #imm12]   base 0x79400000  imm12 scaled by 2
//   LDRSH Xt, [Xn, #imm12]   base 0x79800000  imm12 scaled by 2
//   STRB  Wt, [Xn, #imm12]   base 0x39000000
//   STRH  Wt, [Xn, #imm12]   base 0x79000000
static InstructionARM64 ldrb_w_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && imm_bytes <= 4095, "ldrb_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>(imm_bytes & 0xfffu);
  uint32_t enc = 0x39400000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 ldrsb_x_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && imm_bytes <= 4095, "ldrsb_x_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>(imm_bytes & 0xfffu);
  uint32_t enc = 0x39800000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 strb_w_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && imm_bytes <= 4095, "strb_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>(imm_bytes & 0xfffu);
  uint32_t enc = 0x39000000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}
static InstructionARM64 ldrh_w_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 1) == 0 && imm_bytes <= 8190,
             "ldrh_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 1) & 0xfffu);
  uint32_t enc = 0x79400000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 ldrsh_x_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 1) == 0 && imm_bytes <= 8190,
             "ldrsh_x_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 1) & 0xfffu);
  uint32_t enc = 0x79800000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 strh_w_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 1) == 0 && imm_bytes <= 8190,
             "strh_w_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 1) & 0xfffu);
  uint32_t enc = 0x79000000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}

// LDR/STR Q-reg, 128-bit FPSIMD (LDR Qt, [Xn, #imm]):
//   base 0x3DC00000 (load), 0x3D800000 (store), imm12 scales by 16.
static InstructionARM64 ldr_q_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 15) == 0 && imm_bytes <= 65520,
             "ldr_q_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 4) & 0xfffu);
  uint32_t enc = 0x3DC00000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 str_q_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 15) == 0 && imm_bytes <= 65520,
             "str_q_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 4) & 0xfffu);
  uint32_t enc = 0x3D800000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}

// LDR/STR S-reg, 32-bit FPSIMD (LDR St, [Xn, #imm]):
//   base 0xBD400000 (load), 0xBD000000 (store), imm12 scales by 4.
static InstructionARM64 ldr_s_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 3) == 0 && imm_bytes <= 16380,
             "ldr_s_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 2) & 0xfffu);
  uint32_t enc = 0xBD400000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 str_s_imm(Register src, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 3) == 0 && imm_bytes <= 16380,
             "str_s_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 2) & 0xfffu);
  uint32_t enc = 0xBD000000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(src);
  return InstructionARM64(enc);
}

// LDR Xt, =literal — encoded as LDR Xt, [pc, #imm19]; offset patched later.
// Used as a placeholder for symbol-table / function-table loads. Base
// 0x58000000 (LDR literal, 64-bit).
InstructionARM64 ldr_x_literal_placeholder(Register dst) {
  uint32_t enc = 0x58000000u | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// ADR Xd, label — 4KB relative, imm21. Placeholder with imm=0; patched later.
//   base 0x10000000.
InstructionARM64 adr_placeholder(Register dst) {
  uint32_t enc = 0x10000000u | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// ADRP Xd, page — page-aligned label. Same shape as ADR but base 0x90000000.
InstructionARM64 adrp_placeholder(Register dst) {
  uint32_t enc = 0x90000000u | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// BL (Branch with Link) placeholder. Real displacement patched by the
// ObjectGenerator jump-link table; this encodes BL #0.
//   base 0x94000000.
InstructionARM64 bl_placeholder() {
  return InstructionARM64(0x94000000u);
}

// BLR Xn — branch-and-link to register. base 0xD63F0000.
InstructionARM64 blr_reg(Register r) {
  uint32_t enc = 0xD63F0000u | (arm64_reg5(r) << 5);
  return InstructionARM64(enc);
}

// BR Xn — branch to register. base 0xD61F0000.
InstructionARM64 br_reg(Register r) {
  uint32_t enc = 0xD61F0000u | (arm64_reg5(r) << 5);
  return InstructionARM64(enc);
}

// FADD/FSUB/FMUL/FDIV single-precision (S regs).
//   base 0x1E202800 (FMUL)
//        0x1E202800 + 0x800 (subtract) = 0x1E203000? — actually FP base is
//        0x1E20_0800 (FMUL .S), with opcode in bits 12..15.
//   Encoding: 0001 1110 0010 Rm 0000 11 Rn Rd (FADD) where opcode field
//   selects: FADD=001110 FSUB=001110 FMUL=000010 FDIV=000110.
// Below is the cleaner per-instruction base form.
static InstructionARM64 fadd_s(Register dst, Register a, Register b) {
  // FADD Sd, Sn, Sm: 0001 1110 0010 Rm 0010 10 Rn Rd  → base 0x1E202800
  uint32_t enc =
      0x1E202800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fsub_s(Register dst, Register a, Register b) {
  // FSUB Sd, Sn, Sm: 0001 1110 0010 Rm 0011 10 Rn Rd  → base 0x1E203800
  uint32_t enc =
      0x1E203800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmul_s(Register dst, Register a, Register b) {
  // FMUL Sd, Sn, Sm: 0001 1110 0010 Rm 0000 10 Rn Rd  → base 0x1E200800
  uint32_t enc =
      0x1E200800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fdiv_s(Register dst, Register a, Register b) {
  // FDIV Sd, Sn, Sm: 0001 1110 0010 Rm 0001 10 Rn Rd  → base 0x1E201800
  uint32_t enc =
      0x1E201800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmax_s(Register dst, Register a, Register b) {
  // FMAX Sd, Sn, Sm: base 0x1E204800
  uint32_t enc =
      0x1E204800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmin_s(Register dst, Register a, Register b) {
  // FMIN Sd, Sn, Sm: base 0x1E205800
  uint32_t enc =
      0x1E205800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fsqrt_s(Register dst, Register src) {
  // FSQRT Sd, Sn: 0001 1110 0010 0001 11 0000 Rn Rd  → 0x1E21C000
  uint32_t enc = 0x1E21C000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fcmp_s(Register a, Register b) {
  // FCMP Sn, Sm: 0001 1110 0010 Rm 0010 00 Rn 00000  → 0x1E202000
  uint32_t enc = 0x1E202000u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5);
  return InstructionARM64(enc);
}
static InstructionARM64 fmov_s_reg(Register dst, Register src) {
  // FMOV Sd, Sn: 0001 1110 0010 0000 01 0000 Rn Rd  → 0x1E204000
  uint32_t enc = 0x1E204000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 scvtf_s_w(Register sd, Register wn) {
  // SCVTF Sd, Wn: 0 0011110 00 1 00010 000000 Rn Rd  → 0x1E220000
  uint32_t enc = 0x1E220000u | (arm64_reg5(wn) << 5) | arm64_reg5(sd);
  return InstructionARM64(enc);
}
static InstructionARM64 fcvtzs_w_s(Register wd, Register sn) {
  // FCVTZS Wd, Sn: 0 0011110 00 1 11000 000000 Rn Rd  → 0x1E380000
  uint32_t enc = 0x1E380000u | (arm64_reg5(sn) << 5) | arm64_reg5(wd);
  return InstructionARM64(enc);
}
static InstructionARM64 fmov_w_s(Register wd, Register sn) {
  // FMOV Wd, Sn (S-reg → GPR): 0 0011110 00 1 00 111 000000 Rn Rd  → 0x1E260000
  uint32_t enc = 0x1E260000u | (arm64_reg5(sn) << 5) | arm64_reg5(wd);
  return InstructionARM64(enc);
}
static InstructionARM64 fmov_s_w(Register sd, Register wn) {
  // FMOV Sd, Wn (GPR → S-reg): 0 0011110 00 1 00 111 000000 Rn Rd  → 0x1E270000
  uint32_t enc = 0x1E270000u | (arm64_reg5(wn) << 5) | arm64_reg5(sd);
  return InstructionARM64(enc);
}

// NEON 4x32 single-precision vector ops on V regs (4S lanes).
// Encoding shape: 0 Q 0 01110 sz 1 Rm opcode 1 Rn Rd, with Q=1 sz=00 → 128-bit.
//   FADD .4S Vd, Vn, Vm: 0 1 001110 0 0 1 Rm 110101 Rn Rd  → 0x4E20D400
//   FSUB .4S            : 0 1 001110 1 0 1 Rm 110101 Rn Rd → 0x4EA0D400
//   FMUL .4S            : 0 1 101110 0 0 1 Rm 110111 Rn Rd → 0x6E20DC00
//   FDIV .4S            : 0 1 101110 0 0 1 Rm 111111 Rn Rd → 0x6E20FC00
//   FMAX .4S            : 0 1 001110 0 0 1 Rm 111101 Rn Rd → 0x4E20F400
//   FMIN .4S            : 0 1 001110 1 0 1 Rm 111101 Rn Rd → 0x4EA0F400
static InstructionARM64 fadd_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x4E20D400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fsub_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x4EA0D400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmul_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x6E20DC00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fdiv_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x6E20FC00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmax_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x4E20F400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fmin_4s(Register dst, Register a, Register b) {
  uint32_t enc =
      0x4EA0F400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fsqrt_4s(Register dst, Register src) {
  // FSQRT .4S Vd, Vn: 0 1 101110 1 0 1 0 0001 111110 Rn Rd → 0x6EA1F800
  uint32_t enc = 0x6EA1F800u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 scvtf_4s(Register dst, Register src) {
  // SCVTF .4S Vd, Vn: 0 1 001110 0 0 1 0 0001 110110 Rn Rd → 0x4E21D800
  uint32_t enc = 0x4E21D800u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 fcvtzs_4s(Register dst, Register src) {
  // FCVTZS .4S Vd, Vn: 0 1 001110 1 0 1 0 0001 101110 Rn Rd → 0x4EA1B800
  uint32_t enc = 0x4EA1B800u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// Integer NEON (16B/8H/4S lanes) used by IR_Int128Math*.
//   ADD  .16B: 0 1 001110 00 1 Rm 100001 Rn Rd → 0x4E208400
//   SUB  .4S : 0 1 101110 10 1 Rm 100001 Rn Rd → 0x6EA08400
//   AND  .16B: 0 1 001110 00 1 Rm 000111 Rn Rd → 0x4E201C00
//   ORR  .16B: 0 1 001110 10 1 Rm 000111 Rn Rd → 0x4EA01C00
//   EOR  .16B: 0 1 101110 00 1 Rm 000111 Rn Rd → 0x6E201C00
//   CMEQ .16B: 0 1 101110 00 1 Rm 100011 Rn Rd → 0x6E208C00
static InstructionARM64 vadd_16b(Register dst, Register a, Register b) {
  uint32_t enc = 0x4E208400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vsub_4s(Register dst, Register a, Register b) {
  uint32_t enc = 0x6EA08400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vand_16b(Register dst, Register a, Register b) {
  uint32_t enc = 0x4E201C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vorr_16b(Register dst, Register a, Register b) {
  uint32_t enc = 0x4EA01C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 veor_16b(Register dst, Register a, Register b) {
  uint32_t enc = 0x6E201C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmeq_16b(Register dst, Register a, Register b) {
  uint32_t enc = 0x6E208C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmeq_8h(Register dst, Register a, Register b) {
  // .8H: size=01 → bit23..22=01 → add 0x00400000
  uint32_t enc = 0x6E608C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmeq_4s(Register dst, Register a, Register b) {
  uint32_t enc = 0x6EA08C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmgt_16b(Register dst, Register a, Register b) {
  // CMGT .16B: 0 1 001110 00 1 Rm 001101 Rn Rd → 0x4E203400
  uint32_t enc = 0x4E203400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmgt_8h(Register dst, Register a, Register b) {
  uint32_t enc = 0x4E603400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 vcmgt_4s(Register dst, Register a, Register b) {
  uint32_t enc = 0x4EA03400u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// NEON shifts by immediate (USHR/SHL).
//   USHR .4S Vd, Vn, #imm: 0 1 101111 immh imm3 000001 Rn Rd  with immh:b3=1 sz=4S
//   For 4S: immh=01xx, imm = 64-((immh:imm3) - 32) really — simpler to use
//   SSHR for arithmetic shift. We provide SHL / USHR / SSHR for .4S.
//   SHL  .4S Vd, Vn, #imm: 0 1 001111 immh imm3 010101 Rn Rd
//   USHR .4S: 0 1 101111 immh imm3 000001 Rn Rd
//   SSHR .4S: 0 1 001111 immh imm3 000001 Rn Rd
static InstructionARM64 shl_4s(Register dst, Register src, uint8_t shift) {
  // immh:imm3 = shift + 32 (for 4S)
  uint32_t imm = static_cast<uint32_t>(shift + 32) & 0x7fu;
  uint32_t enc = 0x4F005400u | (imm << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 ushr_4s(Register dst, Register src, uint8_t shift) {
  // immh:imm3 = 64 - shift (for 4S)
  uint32_t imm = static_cast<uint32_t>(64 - (shift & 0x1f)) & 0x7fu;
  uint32_t enc = 0x6F000400u | (imm << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 sshr_4s(Register dst, Register src, uint8_t shift) {
  uint32_t imm = static_cast<uint32_t>(64 - (shift & 0x1f)) & 0x7fu;
  uint32_t enc = 0x4F000400u | (imm << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 shl_8h(Register dst, Register src, uint8_t shift) {
  uint32_t imm = static_cast<uint32_t>((shift & 0xf) + 16) & 0x3fu;
  uint32_t enc = 0x4F005400u | (imm << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 ushr_8h(Register dst, Register src, uint8_t shift) {
  uint32_t imm = static_cast<uint32_t>(32 - (shift & 0xf)) & 0x3fu;
  uint32_t enc = 0x6F000400u | (imm << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// NEON DUP element and ZIP/UZP. For SPLAT we use DUP.4S Vd, Vn.<index>.
//   DUP .4S Vd, Vn.S[idx]: 0 1 001110 000 imm5 0 0000 1 Rn Rd  where imm5=(idx<<3)|0b00100
static InstructionARM64 dup_4s_elem(Register dst, Register src, uint8_t lane) {
  uint32_t imm5 = (static_cast<uint32_t>(lane & 3) << 3) | 0x4u;
  uint32_t enc = 0x4E000400u | (imm5 << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// MOV Vd.16B, Vn.16B  → ORR Vd.16B, Vn.16B, Vn.16B
static InstructionARM64 mov_16b(Register dst, Register src) {
  uint32_t r = arm64_reg5(src);
  uint32_t enc = 0x4EA01C00u | (r << 16) | (r << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// Integer shifts by register (LSLV/LSRV/ASRV).
//   LSLV Xd, Xn, Xm: 1 0 0 11010 110 Rm 0010 00 Rn Rd → 0x9AC02000
//   LSRV Xd, Xn, Xm:                 0010 01           → 0x9AC02400
//   ASRV Xd, Xn, Xm:                 0010 10           → 0x9AC02800
static InstructionARM64 lslv_x(Register dst, Register src, Register amt) {
  uint32_t enc =
      0x9AC02000u | (arm64_reg5(amt) << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 lsrv_x(Register dst, Register src, Register amt) {
  uint32_t enc =
      0x9AC02400u | (arm64_reg5(amt) << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 asrv_x(Register dst, Register src, Register amt) {
  uint32_t enc =
      0x9AC02800u | (arm64_reg5(amt) << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// LSL Xd, Xn, #imm: encoded as UBFM Xd, Xn, #-imm MOD 64, #63-imm
//   UBFM (64-bit) base 0xD3400000 | immr<<16 | imms<<10
static InstructionARM64 lsl_x_imm(Register dst, Register src, uint8_t shift) {
  uint32_t s = shift & 0x3f;
  uint32_t immr = (static_cast<uint32_t>(64u - s) & 0x3f);
  uint32_t imms = (63u - s) & 0x3f;
  uint32_t enc = 0xD3400000u | (immr << 16) | (imms << 10) | (arm64_reg5(src) << 5) |
                 arm64_reg5(dst);
  return InstructionARM64(enc);
}
// LSR Xd, Xn, #imm: UBFM Xd, Xn, #imm, #63
static InstructionARM64 lsr_x_imm(Register dst, Register src, uint8_t shift) {
  uint32_t s = shift & 0x3f;
  uint32_t enc = 0xD340FC00u | (s << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// ASR Xd, Xn, #imm: SBFM Xd, Xn, #imm, #63 → base 0x9340FC00
static InstructionARM64 asr_x_imm(Register dst, Register src, uint8_t shift) {
  uint32_t s = shift & 0x3f;
  uint32_t enc = 0x9340FC00u | (s << 16) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// Integer multiply / divide (MUL/UDIV/SDIV).
//   MADD Xd, Xn, Xm, Xa: 1 0 0 11011 000 Rm 0 Ra Rn Rd → 0x9B000000 with Ra=xzr=31 → 0x9B007C00
//   MUL Xd, Xn, Xm = MADD Xd, Xn, Xm, XZR.
static InstructionARM64 mul_x(Register dst, Register a, Register b) {
  uint32_t enc =
      0x9B007C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 udiv_x(Register dst, Register a, Register b) {
  // UDIV Xd, Xn, Xm: 1 0 0 11010 110 Rm 0000 10 Rn Rd  → 0x9AC00800
  uint32_t enc =
      0x9AC00800u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 sdiv_x(Register dst, Register a, Register b) {
  // SDIV Xd, Xn, Xm: 1 0 0 11010 110 Rm 0000 11 Rn Rd  → 0x9AC00C00
  uint32_t enc =
      0x9AC00C00u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// MSUB Xd, Xn, Xm, Xa: 1 0 0 11011 000 Rm 1 Ra Rn Rd → 0x9B008000
// → for modulo: ud, sd = Xn / Xm; remainder = Xn - ud*Xm.
static InstructionARM64 msub_x(Register dst, Register n, Register m, Register a) {
  uint32_t enc = 0x9B008000u | (arm64_reg5(m) << 16) | (arm64_reg5(a) << 10) |
                 (arm64_reg5(n) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// Bitwise logical between regs (AND/ORR/EOR/MVN).
//   AND Xd, Xn, Xm: 1 00 01010 00 0 Rm 000000 Rn Rd → 0x8A000000
//   ORR Xd, Xn, Xm:                                  → 0xAA000000
//   EOR Xd, Xn, Xm: 1 10 01010 00 0 Rm 000000 Rn Rd → 0xCA000000
//   ORN Xd, XZR, Xm = MVN Xd, Xm
static InstructionARM64 and_x_reg(Register dst, Register a, Register b) {
  uint32_t enc =
      0x8A000000u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 orr_x_reg(Register dst, Register a, Register b) {
  uint32_t enc =
      0xAA000000u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 eor_x_reg(Register dst, Register a, Register b) {
  uint32_t enc =
      0xCA000000u | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// MVN Xd, Xm = ORN Xd, XZR, Xm: 1 01 01010 00 1 Rm 000000 11111 Rd → 0xAA2003E0
static InstructionARM64 mvn_x(Register dst, Register src) {
  uint32_t enc = 0xAA2003E0u | (arm64_reg5(src) << 16) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// SXTW Xd, Wn (sign-extend 32→64) = SBFM Xd, Xn, #0, #31 → 0x93407C00
static InstructionARM64 sxtw_x_w(Register dst, Register src) {
  uint32_t enc = 0x93407C00u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// CBZ/CBNZ — Compare and Branch on Zero (used by some asm idioms).
//   CBZ Xt, label: 1 0110100 imm19 Rt → 0xB4000000
InstructionARM64 cbz_x_placeholder(Register r) {
  uint32_t enc = 0xB4000000u | arm64_reg5(r);
  return InstructionARM64(enc);
}
// CBNZ Xt: 0xB5000000
InstructionARM64 cbnz_x_placeholder(Register r) {
  uint32_t enc = 0xB5000000u | arm64_reg5(r);
  return InstructionARM64(enc);
}

// MOV (register): orr xd, xzr, xm
//   sf | 01 01010 shift(2) N(1) Rm Imm6 Rn(=xzr=31) Rd
//   sf=1 → 64-bit
//   base = 0b1_01_01010_00_0 << 21 = 0xAA000000
//   Rn = 31 (xzr) → bits 5..9 = 0b11111 → 0x3E0
//
// A6 (autoport) — fixed-sym-pointer host→GOAL fixup.
//
// IR_LoadSymbolPointer's `#f` case in goalc/compiler/IR.cpp:303 emits
// `mov dest, x14` where x14 (= R14, the goalc-arm64 ABI sym-table register)
// holds the HOST address of s7 (mirrored from `st + offset` by the C4
// trampoline `add x14, x4, x5`). On x86 the same emit places the symbol
// table's GOAL OFFSET in dst (because x86 R14 = s7's GOAL offset); the C
// FFI helpers (e.g. format_impl_jak1's `original_dest == s7.offset +
// FIX_SYM_TRUE` comparison) require the GOAL offset.
//
// When the source register is X14, emit `MOV dst, x14 ; SUB dst, dst, x15`
// as a paired instruction so the destination ends up holding the GOAL
// offset (host_of_s7 - EE_base). The 8-byte paired emit only triggers for
// X14 sources; every other mov_gpr64_gpr64 caller (IR_RegSet copying GOAL
// registers, IR_GetStackAddr's SP-from-RSP path, etc.) stays a 4-byte ORR.
InstructionARM64 mov_gpr64_gpr64(Register dst, Register src) {
  // A28 — RSP (x86 id=4) → arm64 SP (id=31) translation.
  //
  // GOAL kernel asm-funcs (catch-frame ctor at gkernel.gc:1483, throw-dispatch
  // at gkernel.gc:1583) declare `(sp :reg rsp ...)`. The x86 id for RSP is 4;
  // arm64_reg5() masks to 5 bits and historically the arm64 backend treated
  // id 4 as X4 — a normal GPR — because the regalloc never assigns id 4 and
  // the comment at the top of this file claimed "we always emit literal
  // SP=31 below when we mean the stack pointer". That contract only held for
  // explicit `.push`/`.pop` emits; user-level `(set! sp value)` and
  // `(set! reg sp)` went through mov_gpr64_gpr64 and read/wrote X4 instead
  // of the actual stack pointer. Result: catch-frame.sp captured X4's
  // garbage value and throw-dispatch's `(set! sp (-> this sp))` + `(.add
  // sp off)` updated X4 instead of SP, so the throw's `.pop temp; .push
  // temp; .ret` rebound to the throw frame's return address rather than
  // the catch-frame's saved RA. Once a single throw landed but failed to
  // unwind, the corrupted SP cascaded: subsequent `(new 'stack 'catch-frame
  // 'initialize ...)` allocations placed the catch-frame on a stack region
  // that was never returned to, and later code paths overwrote the chain
  // head before the next throw could find it — hence A27's "chain is s7
  // (= nil)" verdict at the throw-not-found `(break)` trap.
  //
  // Cannot encode MOV between SP and a normal GPR via the ORR-XZR pattern
  // (ORR rejects SP as either operand). The canonical alias is
  //   ADD Xd|SP, Xn|SP, #0  (immediate form; Rd=31 means SP, Rn=31 means SP).
  // Returns 0x91000000 | (imm12<<10) | (Rn<<5) | Rd with imm12=0.
  const uint32_t dst5 = arm64_reg5(dst);
  const uint32_t src5 = arm64_reg5(src);
  if (dst5 == 4u || src5 == 4u) {
    const uint32_t real_dst = (dst5 == 4u) ? 31u : dst5;
    const uint32_t real_src = (src5 == 4u) ? 31u : src5;
    uint32_t add_imm0 = 0x91000000u | (real_src << 5) | real_dst;
    return InstructionARM64(add_imm0);
  }
  uint32_t enc = 0xAA000000u | (src5 << 16) | (31u << 5) | dst5;
  if (src5 == 14u && dst5 != 14u) {
    // SUB Xd, Xd, X15  (shifted register, 64-bit, shift=0)
    uint32_t sub_x15 =
        0xCB000000u | (15u << 16) | (dst5 << 5) | dst5;
    return InstructionARM64::paired(enc, sub_x15);
  }
  return InstructionARM64(enc);
}

// MOVZ xd, #imm16, lsl #(shift*16)
//   sf | 10 100101 hw imm16 Rd
//   base 0xD2800000, hw bits 21..22 encode shift/16
static InstructionARM64 movz_x_lsl(Register dst, uint16_t imm, int shift_div16) {
  uint32_t hw = static_cast<uint32_t>(shift_div16 & 0b11);
  uint32_t enc = 0xD2800000u | (hw << 21) | (static_cast<uint32_t>(imm) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// MOVK xd, #imm16, lsl #(shift*16)
//   base 0xF2800000
static InstructionARM64 movk_x_lsl(Register dst, uint16_t imm, int shift_div16) {
  uint32_t hw = static_cast<uint32_t>(shift_div16 & 0b11);
  uint32_t enc = 0xF2800000u | (hw << 21) | (static_cast<uint32_t>(imm) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// IGen-level mov_gpr64_u64 returns ONE instruction; we emit the low-16
// MOVZ here. The IR codegen path emits the remaining MOVK ops via the
// movz_x_lsl/movk_x_lsl helpers (exposed below).
InstructionARM64 mov_gpr64_u64(Register dst, uint64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(val & 0xffff), 0);
}

InstructionARM64 mov_gpr64_u32(Register dst, uint64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(val & 0xffff), 0);
}

InstructionARM64 mov_gpr64_s32(Register dst, int64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(static_cast<uint64_t>(val) & 0xffff), 0);
}

// Externally-usable helpers for multi-instruction immediate loads and
// for placeholder branches that the ObjectGenerator later patches.
InstructionARM64 movz_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16) {
  return movz_x_lsl(dst, imm, shift_div16);
}

InstructionARM64 movk_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16) {
  return movk_x_lsl(dst, imm, shift_div16);
}

// Unconditional branch placeholder: B #0. Real displacement is patched
// later by ObjectGenerator::handle_temp_jump_links.
//   0 0 0101 imm26 → 0x14000000 | (imm26 & 0x03FFFFFF)
InstructionARM64 b_uncond_placeholder() {
  return InstructionARM64(0x14000000u);
}

// Conditional branch placeholder: B.cond #0.
//   01010100 imm19 0 cond → 0x54000000 | ((imm19 & 0x7FFFF) << 5) | cond
InstructionARM64 b_cond_placeholder(int cond) {
  return InstructionARM64(0x54000000u | (static_cast<uint32_t>(cond) & 0xfu));
}

// Cross-bank moves between GPR and FPSIMD.
InstructionARM64 movd_gpr32_xmm32(Register dst, Register src) {
  return fmov_w_s(dst, src);
}

InstructionARM64 movd_xmm32_gpr32(Register dst, Register src) {
  return fmov_s_w(dst, src);
}

InstructionARM64 movq_gpr64_xmm64(Register dst, Register src) {
  // FMOV Xd, Dn: 0 1011110 01 1 00 110 000000 Rn Rd → 0x9E660000
  uint32_t enc = 0x9E660000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

InstructionARM64 movq_xmm64_gpr64(Register dst, Register src) {
  // FMOV Dd, Xn: 0 1011110 01 1 00 111 000000 Rn Rd → 0x9E670000
  uint32_t enc = 0x9E670000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

InstructionARM64 mov_xmm32_xmm32(Register dst, Register src) {
  return fmov_s_reg(dst, src);
}

// A25 — FMOV Dd, Dn (FPSIMD-to-FPSIMD 64-bit move).
//   0 0011110 011 00000 010000 Rn Rd → 0x1E604000
// Cross-checked against aarch64-linux-gnu-as: "fmov d0, d1" = 0x1e604020.
// This complements:
//   FMOV Sd, Sn (= fmov_s_reg / mov_xmm32_xmm32) — 32-bit FPR-to-FPR
//   FMOV Dd, Xn (= movq_xmm64_gpr64) — GPR-to-FPR (64-bit)
//   FMOV Xd, Dn (= movq_gpr64_xmm64) — FPR-to-GPR (64-bit)
// IR_RegSet's FLOAT-class moves use the 32-bit fmov_s_reg path (the GOAL
// FLOAT class is single-precision); fmov_d_d is provided for completeness
// and for any consumer needing a full 64-bit FPR move.
InstructionARM64 fmov_d_d(Register dst, Register src) {
  uint32_t enc = 0x1E604000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// A26 — CBNZ Xt, #imm. Encoding (per ARM ARM §C6.2.62):
//   sf | 011010 1 | imm19 | Rt
//   sf=1 (64-bit X register), bit 24 = 1 (CBNZ, opposite of CBZ)
//   Base = 0xB5000000. imm19 = (offset_bytes / 4), sign-extended into 19
//   bits, encodes the PC-relative target. The trap path always passes
//   offset_bytes = 8 (skip the next 4-byte instruction = the UDF).
//
// Cross-checked against aarch64-linux-gnu-as:
//   "cbnz x0,  .+8" → 0xb5000040  (imm19 = 2, Rt = 0)
//   "cbnz x8,  .+8" → 0xb5000048  (imm19 = 2, Rt = 8)
//   "cbnz x16, .+8" → 0xb5000050  (imm19 = 2, Rt = 16)
//   "cbnz x30, .+8" → 0xb500005e  (imm19 = 2, Rt = 30)
//
// Note: cbnz_x_placeholder() above encodes imm19 = 0 (branch-to-self,
// patched later by the jump-link patcher). This helper bakes the imm19
// at emit time so the trap doesn't need a fixup record.
InstructionARM64 cbnz_x_imm(Register r, int offset_bytes) {
  const int32_t imm19 = (offset_bytes >> 2) & 0x7FFFF;
  uint32_t enc =
      0xB5000000u | (static_cast<uint32_t>(imm19) << 5) | arm64_reg5(r);
  return InstructionARM64(enc);
}

// A26 — UDF #imm16. Encoding (per ARM ARM §C6.2.376):
//   imm16 in the low 16 bits, top 16 bits all zero. This is the
//   "Permanently Undefined" instruction; executing it always raises an
//   undefined-instruction exception (SIGILL on Linux). The IR_IntegerMath
//   divide-by-zero trap uses tag 0xBEEF, which the SIGILL handler in
//   linux_arm64_main.cpp decodes as BREAK-MACRO-TRAP. Distinct from the
//   A23/A24 tracer tag ranges (0x1EC0..0x1EFF), so the handler branches
//   correctly into the A26 decoder.
//
// Cross-checked against aarch64-linux-gnu-as:
//   "udf #0xBEEF" → 0x0000BEEF
//   "udf #0x1234" → 0x00001234
InstructionARM64 udf_imm16(uint16_t imm16) {
  return InstructionARM64(static_cast<uint32_t>(imm16));
}

// todo - GPR64 -> XMM64 (zext)
// todo - XMM -> GPR64

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   GOAL Loads and Stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// 8-bit signed loads → LDRSB Xt, [Xn, #imm12]
InstructionARM64 load8s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldrsb_x_imm(dst, addr1, 0);
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  (void)addr2;
  return strb_w_imm(value, addr1, 0);
}

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  (void)addr2;
  return ldrsb_x_imm(dst, addr1, offset);
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                       Register addr2,
                                                       Register value,
                                                       s64 offset) {
  (void)addr2;
  return strb_w_imm(value, addr1, offset);
}

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldrsb_x_imm(dst, addr1, offset);
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  (void)addr2;
  return strb_w_imm(value, addr1, offset);
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldrb_w_imm(dst, addr1, 0);
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  (void)addr2;
  return ldrb_w_imm(dst, addr1, offset);
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldrb_w_imm(dst, addr1, offset);
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldrsh_x_imm(dst, addr1, 0);
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  (void)addr2;
  return strh_w_imm(value, addr1, 0);
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  (void)addr2;
  return strh_w_imm(value, addr1, offset);
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  (void)addr2;
  return strh_w_imm(value, addr1, offset);
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldrsh_x_imm(dst, addr1, offset);
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  (void)addr2;
  return ldrsh_x_imm(dst, addr1, offset);
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldrh_w_imm(dst, addr1, 0);
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldrh_w_imm(dst, addr1, offset);
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  (void)addr2;
  return ldrh_w_imm(dst, addr1, offset);
}

// 32-bit signed loads → LDRSW Xt, [Xn, #imm12].
//   LDRSW: base 0xB9800000, imm12 scales by 4.
static InstructionARM64 ldrsw_x_imm(Register dst, Register base, int64_t imm_bytes) {
  ASSERT_MSG(imm_bytes >= 0 && (imm_bytes & 3) == 0 && imm_bytes <= 16380,
             "ldrsw_x_imm: unencodable offset");
  uint32_t imm12 = static_cast<uint32_t>((imm_bytes >> 2) & 0xfffu);
  uint32_t enc = 0xB9800000u | (imm12 << 10) | (arm64_reg5(base) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
InstructionARM64 load32s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldrsw_x_imm(dst, addr1, 0);
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  (void)addr2;
  return str_w_imm(value, addr1, 0);
}

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldrsw_x_imm(dst, addr1, offset);
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  (void)addr2;
  return str_w_imm(value, addr1, offset);
}

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  (void)addr2;
  if (offset == static_cast<s64>(LINK_SYM_NO_OFFSET_FLAG)) {
    // A5 — far-reloc sym-mem path. addr1 is the GOAL st-reg; addr2 is the
    // offset-reg; both are ignored here because the expansion in
    // ObjectGenerator::add_instr materialises the symbol's full host
    // address into X16 via ADRP+ADD and reads it back with LDRSW Xt,[X16,#0].
    return a5_sym_mem_marker(kA5SymKindLoad32S, dst);
  }
  return ldrsw_x_imm(dst, addr1, offset);
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  (void)addr2;
  if (offset == static_cast<s64>(LINK_SYM_NO_OFFSET_FLAG)) {
    // A5 — far-reloc sym-mem path. See load32s above.
    return a5_sym_mem_marker(kA5SymKindStore32, value);
  }
  return str_w_imm(value, addr1, offset);
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldr_w_imm(dst, addr1, 0);
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldr_w_imm(dst, addr1, offset);
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  (void)addr2;
  if (offset == static_cast<s64>(LINK_SYM_NO_OFFSET_FLAG)) {
    // A5 — far-reloc sym-mem path. See load32s above.
    return a5_sym_mem_marker(kA5SymKindLoad32U, dst);
  }
  return ldr_w_imm(dst, addr1, offset);
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldr_x_imm(dst, addr1, 0);
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  (void)addr2;
  return str_x_imm(value, addr1, 0);
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  (void)addr2;
  return ldr_x_imm(dst, addr1, offset);
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  (void)addr2;
  return str_x_imm(value, addr1, offset);
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldr_x_imm(dst, addr1, offset);
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  (void)addr2;
  return str_x_imm(value, addr1, offset);
}

// ---------------------------------------------------------------------------
// A6 — off-register GOAL deref fix.
//
// The pre-A6 emitter discarded the EE-base register (`Register off`) from
// every GOAL pointer deref, emitting `LDR/STR Wt, [Xaddr, #imm12]` and
// reading from a host address that's missing the EE base. On Android
// (where EE memory is mapped at a high VA like 0x720_xxxx_xxxx), the
// resulting deref SIGSEGVs at the first non-sym-mem GOAL pointer access
// — the bug A5's shim audit deferred to a follow-up phase.
//
// AArch64's `LDR/STR Wt, [Xn, #imm12]` encoding has only one base register
// slot (Rn) — no three-operand reg+reg+imm form exists. Folding `off`
// into the addressing mode requires a separate ADD into a scratch GPR:
//
//     ADD X16, Xaddr, Xoff          ; X16 = host address sans imm
//     LDR/STR Wt, [X16, #imm]       ; access with struct-field offset
//
// X16 (IP0) is the AArch64 caller-saved scratch register conventionally
// clobbered by linker branch islands; the goalc register allocator's
// m_gpr_alloc_order caps at id 9 / R10 (Register.cpp:60) and never
// assigns X16/X17 to a live GOAL value, so using X16 here is safe
// across IR boundaries. A5 reserved X16 for the sym-mem expansion in
// ObjectGenerator; A6 reuses it for the off-register path. The two
// expansions never collide because they are emitted as separate
// instruction sequences within a function — X16 is dead between IRs.
//
// Offset encoding picker: the AArch64 unsigned-immediate `LDR/STR Wt,
// [Xn, #imm12]` form encodes only positive offsets scaled by access size
// (0..4095*scale). GOAL routinely uses NEGATIVE offsets (e.g. -4 for an
// object header's type tag), and would also use offsets that aren't a
// multiple of the access scale. For both cases A6 picks the unscaled
// signed-9-bit form `LDUR/STUR Wt, [Xn, #simm9]` (range -256..255). The
// x86 backend handles both via SIB displacement; arm64 needs the two
// forms split. Without this picker the existing pre-A5 helpers silently
// truncate negative offsets to the max imm12 (e.g. -4 → 16380), which
// the pre-A6 skip-flag dodge hid by never running the bytecode.
//
// Each off-register helper below returns the pair as a single
// InstructionARM64 via `InstructionARM64::paired(enc_add, enc_access)`.
// The downstream ObjectGenerator emit loop (ObjectGenerator.cpp:93-104)
// writes whatever bytes emit() returns — the per-instruction byte offset
// tracker reads `data.size()` after the write, so an 8-byte InstructionARM64
// correctly advances `instruction_to_byte_in_data` by 8 for the next
// instruction. No locked file is touched: the InstructionARM64 type's
// new optional second word lives in Instruction.h, which is not in the
// validator's lock list.
// ---------------------------------------------------------------------------
static constexpr uint32_t kA6OffRegScratchRegId = 16;  // X16 / IP0

// ADD Xd, Xn, Xm (shifted register, LSL #0). 64-bit form, no flag update.
//   sf=1 | 0 | 0 | 01011_00 | 0 | Rm[5] | imm6=0 | Rn[5] | Rd[5]
//   base 0x8B000000. Encoding cross-checked against
//   https://www.scs.stanford.edu/~zyedidia/arm64/add_addsub_shift.html.
static inline uint32_t a6_enc_add_x16_xn_xm(Register addr, Register off) {
  // A33: addr/off must be GPR-bank registers (x86-model id <= 15). An id of
  // 16+ would silently alias X16..X31 — X16 is THIS helper's scratch, so a
  // 16+ id here means a live value is about to be clobbered (the
  // hud-classes-pc sink-group corruption shape). Fail the compile loudly.
  ASSERT_MSG(addr.id() <= 15 && off.id() <= 15,
             "a6_enc_add_x16_xn_xm: non-GPR-bank register id in GOAL memory access");
  return 0x8B000000u | (arm64_reg5(off) << 16) | (arm64_reg5(addr) << 5) |
         kA6OffRegScratchRegId;
}

// Returns true if `offset` is exactly encodable as a positive unsigned-scaled
// imm12 (`LDR/STR Wt, [Xn, #imm12]`) — i.e. non-negative, a multiple of the
// access size, and within 4095*size.
static inline bool a6_fits_scaled_imm12(s64 offset, int scale) {
  if (offset < 0) return false;
  if ((offset % scale) != 0) return false;
  return offset <= (s64)4095 * scale;
}

// Returns true if `offset` is exactly encodable as an LDUR/STUR simm9
// (signed 9-bit byte offset, range -256..255).
static inline bool a6_fits_simm9(s64 offset) {
  return offset >= -256 && offset <= 255;
}

// LDUR/STUR (unscaled signed 9-bit immediate) encoder.
//   bits 31..30 : size_bits (00=B 01=H 10=W/S 11=X/D — Q uses size=00+V=1 ext)
//   bits 29..27 : 111
//   bit 26      : V (vector/SIMD)
//   bits 25..24 : 00
//   bits 23..22 : opc (00=STR, 01=LDR, 10=LDRSx)
//   bit 21      : 0
//   bits 20..12 : simm9 (signed)
//   bits 11..10 : 00 (unscaled — no transfer-write/post-index)
//   bits  9..5  : Rn
//   bits  4..0  : Rt
static inline uint32_t a6_enc_ldur_stur(uint32_t base, Register tgt, int simm9) {
  uint32_t imm = static_cast<uint32_t>(simm9) & 0x1FFu;
  return base | (imm << 12) | (kA6OffRegScratchRegId << 5) | arm64_reg5(tgt);
}

// LDUR/STUR base opcodes (Rn=0, imm9=0, Rt=0 placeholders).
//   STURB Wt, [Xn, #s9] 0x38000000   LDURB Wt 0x38400000   LDURSB Xt 0x38800000
//   STURH Wt          0x78000000     LDURH Wt 0x78400000   LDURSH Xt 0x78800000
//   STUR  Wt (32-bit) 0xB8000000     LDUR Wt  0xB8400000   LDURSW Xt 0xB8800000
//   STUR  Xt (64-bit) 0xF8000000     LDUR Xt  0xF8400000
//   STUR  St (32 SIMD)0xBC000000     LDUR St  0xBC400000
//   STUR  Qt (128 SIMD)0x3C800000    LDUR Qt  0x3CC00000

// Emit the full GOAL off-register access sequence for [addr + off + offset]:
//
//   ADD X16, Xaddr, Xoff            ; X16 = host address sans struct offset
//   <access> Rt, [X16, #offset]     ; scaled imm12 or LDUR/STUR simm9
//
// or, when `offset` fits neither the scaled-imm12 form (non-negative,
// multiple of the access scale, <= 4095*scale) nor the LDUR/STUR simm9
// form (-256..255), materialize it into X16 first and access at [X16, #0]:
//
//   ADD X16, Xaddr, Xoff
//   ADD/SUB X16, X16, #(|offset| >> 12), LSL #12   ; only if |offset| > 4095
//   ADD/SUB X16, X16, #(|offset| & 0xFFF)          ; only if non-zero
//   <access> Rt, [X16, #0]
//
// A34: the materialized path replaces the old behaviour of re-using the
// scaled-imm12 encoding with a floor-divided immediate. That silent
// truncation mis-addressed every GOAL field whose byte offset was not a
// multiple of the access size and outside +/-256 — e.g. camera-master's
// 8-byte `drawable-target` handle at +316 was read from +312, which fed
// `handle->process` a garbage handle and SIGSEGV'd the on-device display
// loop in `master-track-target` 11 ms after `link finish: title-vis`.
// `scaled_base`/`unscaled_base` are the opcode bases for this access
// width/sign (Rt/Rn/imm all zero).
static inline InstructionARM64 a6_offreg_access(Register addr,
                                                Register off,
                                                Register tgt,
                                                s64 offset,
                                                uint32_t scaled_base,
                                                uint32_t unscaled_base,
                                                int scale) {
  const uint32_t rt = arm64_reg5(tgt);
  const uint32_t rn_x16 = (kA6OffRegScratchRegId << 5);
  const uint32_t add0 = a6_enc_add_x16_xn_xm(addr, off);
  if (a6_fits_scaled_imm12(offset, scale)) {
    const uint32_t imm12 = static_cast<uint32_t>(offset / scale);
    return InstructionARM64::paired(add0, scaled_base | (imm12 << 10) | rn_x16 | rt);
  }
  if (a6_fits_simm9(offset)) {
    return InstructionARM64::paired(add0,
                                    a6_enc_ldur_stur(unscaled_base, tgt, static_cast<int>(offset)));
  }
  ASSERT_MSG(offset > -(s64(1) << 24) && offset < (s64(1) << 24),
             "a6_offreg_access: GOAL access offset out of materializable range");
  const s64 mag = offset < 0 ? -offset : offset;
  const uint32_t lo12 = static_cast<uint32_t>(mag & 0xfff);
  const uint32_t hi12 = static_cast<uint32_t>((mag >> 12) & 0xfff);
  // ADD Xd, Xn, #imm12 = 0x91000000; SUB Xd, Xn, #imm12 = 0xD1000000.
  // Bit 22 selects LSL #12 on the immediate.
  const uint32_t addsub = offset < 0 ? 0xD1000000u : 0x91000000u;
  InstructionARM64 r(add0);
  if (hi12) {
    r.extra_words.push_back(addsub | (1u << 22) | (hi12 << 10) | rn_x16 | kA6OffRegScratchRegId);
  }
  if (lo12) {
    r.extra_words.push_back(addsub | (lo12 << 10) | rn_x16 | kA6OffRegScratchRegId);
  }
  r.extra_words.push_back(scaled_base | rn_x16 | rt);  // [X16, #0]
  return r;
}

InstructionARM64 store_goal_vf(Register addr, Register value, Register off, s64 offset) {
  // STR Qt scaled 0x3D800000, STUR Qt 0x3C800000.
  return a6_offreg_access(addr, off, value, offset, 0x3D800000u, 0x3C800000u, 16);
}

InstructionARM64 store_goal_gpr(Register addr, Register value, Register off, int offset, int size) {
  // A33: the stored value must live in the GPR bank (id <= 15); ids 16+
  // would encode X16..X31 (emitter scratch / platform / pp / st / offset).
  ASSERT_MSG(value.id() <= 15, "store_goal_gpr: value register is not GPR-bank");
  uint32_t scaled_base;
  uint32_t unscaled_base;
  int scale;
  switch (size) {
    case 1:
      scaled_base = 0x39000000u;    // STRB  Wt
      unscaled_base = 0x38000000u;  // STURB Wt
      scale = 1;
      break;
    case 2:
      scaled_base = 0x79000000u;    // STRH  Wt
      unscaled_base = 0x78000000u;  // STURH Wt
      scale = 2;
      break;
    case 4:
      scaled_base = 0xB9000000u;    // STR  Wt
      unscaled_base = 0xB8000000u;  // STUR Wt
      scale = 4;
      break;
    default:
      scaled_base = 0xF9000000u;    // STR  Xt
      unscaled_base = 0xF8000000u;  // STUR Xt
      scale = 8;
      break;
  }
  return a6_offreg_access(addr, off, value, offset, scaled_base, unscaled_base, scale);
}

InstructionARM64 load_goal_xmm128(Register dst, Register addr, Register off, int offset) {
  // LDR Qt scaled 0x3DC00000, LDUR Qt 0x3CC00000.
  return a6_offreg_access(addr, off, dst, offset, 0x3DC00000u, 0x3CC00000u, 16);
}

InstructionARM64 load_goal_gpr(Register dst,
                               Register addr,
                               Register off,
                               int offset,
                               int size,
                               bool sign_extend) {
  // A33: see store_goal_gpr — GPR-bank ids only for the destination.
  ASSERT_MSG(dst.id() <= 15, "load_goal_gpr: dst register is not GPR-bank");
  uint32_t scaled_base;
  uint32_t unscaled_base;
  int scale;
  switch (size) {
    case 1:
      if (sign_extend) {
        scaled_base = 0x39800000u;    // LDRSB  Xt
        unscaled_base = 0x38800000u;  // LDURSB Xt
      } else {
        scaled_base = 0x39400000u;    // LDRB  Wt
        unscaled_base = 0x38400000u;  // LDURB Wt
      }
      scale = 1;
      break;
    case 2:
      if (sign_extend) {
        scaled_base = 0x79800000u;    // LDRSH  Xt
        unscaled_base = 0x78800000u;  // LDURSH Xt
      } else {
        scaled_base = 0x79400000u;    // LDRH  Wt
        unscaled_base = 0x78400000u;  // LDURH Wt
      }
      scale = 2;
      break;
    case 4:
      if (sign_extend) {
        scaled_base = 0xB9800000u;    // LDRSW  Xt
        unscaled_base = 0xB8800000u;  // LDURSW Xt
      } else {
        scaled_base = 0xB9400000u;    // LDR  Wt
        unscaled_base = 0xB8400000u;  // LDUR Wt
      }
      scale = 4;
      break;
    default:
      scaled_base = 0xF9400000u;    // LDR  Xt
      unscaled_base = 0xF8400000u;  // LDUR Xt
      scale = 8;
      break;
  }
  return a6_offreg_access(addr, off, dst, offset, scaled_base, unscaled_base, scale);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - XMM32
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
InstructionARM64 store32_xmm32_gpr64_plus_gpr64(Register addr1,
                                                Register addr2,
                                                Register xmm_value) {
  (void)addr2;
  return str_s_imm(xmm_value, addr1, 0);
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64(Register simd_dest, Register addr1, Register addr2) {
  (void)addr2;
  return ldr_s_imm(simd_dest, addr1, 0);
}

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register xmm_value,
                                                        s64 offset) {
  (void)addr2;
  return str_s_imm(xmm_value, addr1, offset);
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s8(Register simd_dest,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  (void)addr2;
  return ldr_s_imm(simd_dest, addr1, offset);
}

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register xmm_value,
                                                         s64 offset) {
  (void)addr2;
  return str_s_imm(xmm_value, addr1, offset);
}

// LEA-style "compute base+offset into a GPR" → ADD imm12 (positive) or SUB imm12 (negative).
//
// A6 (autoport) — same fixed-sym fixup as mov_gpr64_gpr64 above. When the
// base register is X14, the resulting LEA is `host_of_s7 + off`, which is
// a HOST address. The x86 sibling produces a GOAL OFFSET (because x86 R14
// holds s7's GOAL offset). IR_LoadSymbolPointer's #t/_empty_ paths and any
// other s7-relative pointer compute calls here and expects GOAL offset;
// the C FFI helpers also dispatch on GOAL-offset equality.
//
// Follow the ADD/SUB-imm12 with `SUB Xd, Xd, X15` when the base is X14 so
// the destination ends up as a GOAL offset. Other callers (IR_RegValAddr,
// IR_GetStackAddr, IR_StaticVarAddr's lea_reg_plus_off32 leg) use RSP or
// an ADRP-set scratch as the base — never X14 — and continue to emit a
// single ADD/SUB imm12 instruction.
InstructionARM64 lea_reg_plus_off32(Register dest, Register base, s64 offset) {
  uint32_t lea_enc;
  if (offset >= 0) {
    uint32_t imm12 = static_cast<uint32_t>(offset) & 0xfffu;
    lea_enc = add_x_imm12(dest, base, imm12).encoding;
  } else {
    uint32_t imm12 = static_cast<uint32_t>(-offset) & 0xfffu;
    lea_enc = sub_x_imm12(dest, base, imm12).encoding;
  }
  if (arm64_reg5(base) == 14u && arm64_reg5(dest) != 14u) {
    // SUB Xd, Xd, X15 (shifted register, 64-bit, shift=0)
    uint32_t sub_x15 =
        0xCB000000u | (15u << 16) | (arm64_reg5(dest) << 5) | arm64_reg5(dest);
    return InstructionARM64::paired(lea_enc, sub_x15);
  }
  return InstructionARM64(lea_enc);
}

InstructionARM64 lea_reg_plus_off8(Register dest, Register base, s64 offset) {
  return lea_reg_plus_off32(dest, base, offset);
}

InstructionARM64 lea_reg_plus_off(Register dest, Register base, s64 offset) {
  return lea_reg_plus_off32(dest, base, offset);
}

InstructionARM64 store32_xmm32_gpr64_plus_s32(Register base, Register xmm_value, s64 offset) {
  return str_s_imm(xmm_value, base, offset);
}

InstructionARM64 store32_xmm32_gpr64_plus_s8(Register base, Register xmm_value, s64 offset) {
  return str_s_imm(xmm_value, base, offset);
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s32(Register simd_dest,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  (void)addr2;
  return ldr_s_imm(simd_dest, addr1, offset);
}

InstructionARM64 load32_xmm32_gpr64_plus_s32(Register simd_dest, Register base, s64 offset) {
  return ldr_s_imm(simd_dest, base, offset);
}

InstructionARM64 load32_xmm32_gpr64_plus_s8(Register simd_dest, Register base, s64 offset) {
  return ldr_s_imm(simd_dest, base, offset);
}

InstructionARM64 load_goal_xmm32(Register simd_dest, Register addr, Register off, s64 offset) {
  // LDR St scaled 0xBD400000, LDUR St 0xBC400000.
  return a6_offreg_access(addr, off, simd_dest, offset, 0xBD400000u, 0xBC400000u, 4);
}

InstructionARM64 store_goal_xmm32(Register addr, Register xmm_value, Register off, s64 offset) {
  // STR St scaled 0xBD000000, STUR St 0xBC000000.
  return a6_offreg_access(addr, off, xmm_value, offset, 0xBD000000u, 0xBC000000u, 4);
}

InstructionARM64 store_reg_offset_xmm32(Register base, Register xmm_value, s64 offset) {
  return str_s_imm(xmm_value, base, offset);
}

InstructionARM64 load_reg_offset_xmm32(Register simd_dest, Register base, s64 offset) {
  return ldr_s_imm(simd_dest, base, offset);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - SIMD (128-bit, QWORDS)
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 store128_gpr64_simd128(Register gpr_addr, Register simd_reg) {
  // https://www.scs.stanford.edu/~zyedidia/arm64/str_imm_fpsimd.html
  // - STR Qn, [Xn] (unsigned offset)
  ASSERT(gpr_addr.is_gpr(instr_set));
  ASSERT(
      simd_reg.is_128bit_simd(instr_set));  // TODO ARM64 - this assertion isn't as useful for ARM
                                            // since Q registers are not unique in terms of their id
  return InstructionARM64(Base(0b0011110110, 10), Rn(gpr_addr.id()), Rt(simd_reg.id()), Imm12(0));
}

InstructionARM64 store128_gpr64_simd128_s32(Register gpr_addr, Register xmm_value, s64 offset) {
  return str_q_imm(xmm_value, gpr_addr, offset);
}

InstructionARM64 store128_gpr64_simd128_s8(Register gpr_addr, Register xmm_value, s64 offset) {
  return str_q_imm(xmm_value, gpr_addr, offset);
}

InstructionARM64 load128_simd128_gpr64(Register simd_dest, Register gpr_addr) {
  // https://www.scs.stanford.edu/~zyedidia/arm64/ldr_imm_fpsimd.html
  // - LDR <Qt>, [<Xn|SP>{, #<pimm>}]
  ASSERT(gpr_addr.is_gpr(instr_set));
  ASSERT(simd_dest.is_128bit_simd(
      instr_set));  // TODO ARM64 - this assertion isn't as useful for ARM
                    // since Q registers are not unique in terms of their id
  return InstructionARM64(Base(0b0011110111, 10), Rn(gpr_addr.id()), Rt(simd_dest.id()), Imm12(0));
}

InstructionARM64 load128_simd128_gpr64_s32(Register simd_dest, Register gpr_addr, s64 offset) {
  return ldr_q_imm(simd_dest, gpr_addr, offset);
}

InstructionARM64 load128_simd128_gpr64_s8(Register simd_dest, Register gpr_addr, s64 offset) {
  return ldr_q_imm(simd_dest, gpr_addr, offset);
}

InstructionARM64 load128_xmm128_reg_offset(Register simd_dest, Register base, s64 offset) {
  return ldr_q_imm(simd_dest, base, offset);
}

InstructionARM64 store128_xmm128_reg_offset(Register base, Register xmm_val, s64 offset) {
  return str_q_imm(xmm_val, base, offset);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   RIP loads and stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// RIP-relative loads on x86 become PC-relative LDR-literal on arm64.
// The actual literal-pool address is patched in by ObjectGenerator after
// layout; here we emit the encoding with a zero imm19 placeholder.
InstructionARM64 load64_rip_s32(Register dest, s64 offset) {
  (void)offset;
  return ldr_x_literal_placeholder(dest);
}

InstructionARM64 load32s_rip_s32(Register dest, s64 offset) {
  // LDRSW literal: base 0x98000000 | imm19<<5 | Rt
  (void)offset;
  return InstructionARM64(0x98000000u | arm64_reg5(dest));
}

InstructionARM64 load32u_rip_s32(Register dest, s64 offset) {
  // LDR (literal, 32-bit): base 0x18000000 | imm19<<5 | Rt
  (void)offset;
  return InstructionARM64(0x18000000u | arm64_reg5(dest));
}

InstructionARM64 load16u_rip_s32(Register dest, s64 offset) {
  (void)offset;
  return ldrh_w_imm(dest, dest, 0);
}

InstructionARM64 load16s_rip_s32(Register dest, s64 offset) {
  (void)offset;
  return ldrsh_x_imm(dest, dest, 0);
}

InstructionARM64 load8u_rip_s32(Register dest, s64 offset) {
  (void)offset;
  return ldrb_w_imm(dest, dest, 0);
}

InstructionARM64 load8s_rip_s32(Register dest, s64 offset) {
  (void)offset;
  return ldrsb_x_imm(dest, dest, 0);
}

InstructionARM64 static_load(Register dest, s64 offset, int size, bool sign_extend) {
  (void)offset;
  switch (size) {
    case 1:
      return sign_extend ? ldrsb_x_imm(dest, dest, 0) : ldrb_w_imm(dest, dest, 0);
    case 2:
      return sign_extend ? ldrsh_x_imm(dest, dest, 0) : ldrh_w_imm(dest, dest, 0);
    case 4:
      return sign_extend ? InstructionARM64(0x98000000u | arm64_reg5(dest))
                         : InstructionARM64(0x18000000u | arm64_reg5(dest));
    default:
      return ldr_x_literal_placeholder(dest);
  }
}

InstructionARM64 store64_rip_s32(Register src, s64 offset) {
  (void)offset;
  // Address-of computed via ADRP placeholder followed by STR; here we emit
  // just the STR (the caller adds the ADRP).
  return str_x_imm(src, src, 0);
}

InstructionARM64 store32_rip_s32(Register src, s64 offset) {
  (void)offset;
  return str_w_imm(src, src, 0);
}

InstructionARM64 store16_rip_s32(Register src, s64 offset) {
  (void)offset;
  return strh_w_imm(src, src, 0);
}

InstructionARM64 store8_rip_s32(Register src, s64 offset) {
  (void)offset;
  return strb_w_imm(src, src, 0);
}

InstructionARM64 static_store(Register value, s64 offset, int size) {
  (void)offset;
  switch (size) {
    case 1:
      return strb_w_imm(value, value, 0);
    case 2:
      return strh_w_imm(value, value, 0);
    case 4:
      return str_w_imm(value, value, 0);
    default:
      return str_x_imm(value, value, 0);
  }
}

InstructionARM64 static_addr(Register dst, s64 offset) {
  (void)offset;
  // Symbol-table-relative address materialised via ADRP; offset is patched.
  return adrp_placeholder(dst);
}

InstructionARM64 static_load_xmm32(Register simd_dest, s64 offset) {
  // LDR S-reg literal: base 0x1C000000 | imm19<<5 | Rt
  (void)offset;
  return InstructionARM64(0x1C000000u | arm64_reg5(simd_dest));
}

InstructionARM64 static_store_xmm32(Register xmm_value, s64 offset) {
  (void)offset;
  return str_s_imm(xmm_value, xmm_value, 0);
}

// TODO, special load/stores of 128 bit values.

// Stack slot accesses (RSP-relative on x86, SP-relative on arm64).
//   load64_gpr64_plus_s32: x86 mov dst, [rsp + offset] → arm64 ldr Xt, [sp, #off]
//   store64_gpr64_plus_s32: x86 mov [rsp + offset], value → arm64 str Xt, [sp, #off]
//
// For arm64 we explicitly substitute SP (id 31) as the base when src_reg / addr
// matches the x86 RSP id (id 4). The high-level path always passes RSP here.
static constexpr int kArm64SpId = 31;
InstructionARM64 load64_gpr64_plus_s32(Register dst_reg, int32_t offset, Register src_reg) {
  Register base = (src_reg.id() == 4) ? Register(kArm64SpId) : src_reg;
  return ldr_x_imm(dst_reg, base, offset);
}

InstructionARM64 store64_gpr64_plus_s32(Register addr, int32_t offset, Register value) {
  Register base = (addr.id() == 4) ? Register(kArm64SpId) : addr;
  return str_x_imm(value, base, offset);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FUNCTION STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 ret() {
  // A24 — env-gated pre-RET X30 stack-range check. The standard RET
  // (do_goal_function_arm64's epilogue) uses raw bytes 0xD65F03C0 and
  // CodeGenerator.cpp wraps that with the tracer directly. This `ret()`
  // helper is called from IR_AsmRet::do_codegen_arm64 (the GOAL `.ret`
  // form, used in asm-func bodies like return-from-thread, return-from-
  // thread-dead in jak1/kernel/gkernel.gc) AND from the asm-function
  // emit path. Both surfaces need the same check — a corrupted X30
  // (stack-range, GOAL form >= 0x07000000) at any of these RETs would
  // propagate to PC and produce the A21/A23 crash signature.
  //
  // Encoding mirrors the goalc epilogue + asm-trampoline + inline-
  // trampoline tracers: SUB X17, X30, X15 / MOVZ X16, #0x0700, LSL #16
  // / CMP X17, X16 / B.LT +8 / UDF #0x1EF0. Uses the same lazy-cached
  // br_target_trace_emit_enabled() flag (env-gated by OG_X30_TRACE_EMIT)
  // so one env var toggles every A24 surface.
  // Returns 6 instructions when enabled vs 1 when disabled — byte-
  // identical to A23 baseline when OG_X30_TRACE_EMIT is unset.
  // (Inlined env check rather than calling a helper because
  // br_target_trace_emit_enabled() is defined further down the file
  // alongside jmp_r64 — easier to keep the lazy-cache local than
  // forward-declare.)
  static const bool x30_trace_emit_enabled = []() {
    const char* env = std::getenv("OG_X30_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  if (x30_trace_emit_enabled) {
    constexpr uint32_t kSubX17X30X15 = 0xCB0F03D1u;
    constexpr uint32_t kMovzX16Floor = 0xD2A0E010u;
    constexpr uint32_t kCmpX17X16 = 0xEB10023Fu;
    constexpr uint32_t kBltSkipUdf = 0x5400004Bu;
    constexpr uint32_t kUdfEpilogueX30 = 0x00001EF0u;
    constexpr uint32_t kRet = 0xD65F03C0u;
    return InstructionARM64::multi({kSubX17X30X15, kMovzX16Floor,
                                    kCmpX17X16, kBltSkipUdf,
                                    kUdfEpilogueX30, kRet});
  }
  // https://www.scs.stanford.edu/~zyedidia/arm64/ret.html
  // - defaults to using X30 if Rn is absent
  return InstructionARM64(Base(0b1101011001011111000000, 22), Rn(30));
}

InstructionARM64 push_gpr64(Register reg) {
  // ARM64 stack grows down, so we subtract 16 from SP and store the register
  // Equivalent assembly: STR reg, [SP, #-16]!
  // - https://www.scs.stanford.edu/~zyedidia/arm64/str_imm_gen.html
  // We use 16 because in ARM, the stack must be 16-byte aligned.
  // This does mean we are inefficiently using the stack, there are a few better options:
  // - Push in pairs, two registers at a time
  // - Preallocate stack-space
  // But we can't do either of these at this level, this is an optimization that has to come from
  // higher in the stack.  Here we are concerned with just satisfying the need to push a GPR
  ASSERT(reg.is_gpr(instr_set));
  return InstructionARM64(Base(0b1111100000000000000011, 22), Imm9(-16), Rn(ARM64_REG::SP),
                          Rt(reg.id()));
}

InstructionARM64 pop_gpr64(Register reg) {
  // ldr reg, [sp], #16
  // - https://www.scs.stanford.edu/~zyedidia/arm64/ldr_imm_gen.html
  ASSERT(reg.is_gpr(instr_set));
  return InstructionARM64(Base(0b1111100001000000000001, 22), Imm9(16), Rn(ARM64_REG::SP),
                          Rt(reg.id()));
}

// A6/A19 — callee-saved register preservation around BLR. The locked
// CodeGenerator.cpp prologue/epilogue saves only X29/X30 (the AArch64
// frame pointer + link register), not the goalc "saved" GPRs that the
// x86 calling convention treats as callee-preserved (RBX, RBP, R10, R11,
// R12 — mapping to X3, X5, X10, X11, X12 on arm64). On x86 those are
// preserved by AAPCS, so the existing regalloc keeps live values in them
// across calls. On arm64 the called function freely clobbers them, and
// any GOAL value held in a "saved" reg across a BLR returns as garbage —
// exactly what the GK-DIAG capture showed for X3 = 0xffff_ffff_ffff_a000
// after the second BLR inside gkernel-toplevel.
//
// Since the per-function prologue is locked, we fix this at the call site
// instead: every BLR pushes the five "saved" GPRs (X3, X5, X10, X11, X12)
// onto the SP stack, branches with link, and pops them back.
//
// A19 update: X12 was originally excluded from the save set under the
// assumption that the regalloc only uses it to hold the call target. That
// assumption is wrong — Register.cpp marks R12 (= X12 on arm64) as a
// "saved" GPR and REG_saved_first_order in Allocator_v2.cpp places R12
// third in the function-crossing allocation order. The regalloc therefore
// routinely places non-call-target values into X12 across function calls,
// expecting AAPCS-style preservation that arm64 never provides.
// A18 attempt-4's disasm of dead-pool-heap.get-process caught this:
// lr-388 stashes `this` into X12 (MOV X12, X7), the lr-292..lr-284
// pre-call save list saves {X3, X5, X10, X11, X23} but NOT X12, and
// after the BLR to find-gap-by-size returns, X12 holds find-gap-by-size's
// `size` argument (0x4070) instead of `this`. The subsequent virtual
// dispatch through X12 lands on uninitialised memory at ee_base, sig=4
// SIGILL. Adding X12 to the save set fixes this whole class of bugs
// without spurious spilling — the value lives in X12 across the call,
// gets pushed before BLR, popped after, just like X3/X5/X10/X11.
//
// Encodings cross-checked against `aarch64-linux-android28-clang -c`.
// stp/ldp pre/post-indexed uses bit 7 as part of Rn, so a hand-encoded
// constant for X3/X5 with the wrong bit gives Rn=27 (R27) instead of 31
// (SP). Always derive these from llvm-mc output, never a paper hex pattern.
//
// Save set: X3 (RBX), X5 (RBP), X10 (R10), X11 (R11), X12 (R12), X23
// (extra AAPCS callee-saved). The first five mirror the goalc "saved"
// GPRs per Register.cpp::make_register_info(). X23 is not used by
// goalc-emitted code at all, but a real crash on device showed it being
// clobbered across the gkernel-toplevel BLR — pre x23=0x721e600000,
// post x23=0x0 — and the caller (link_control::jak1_finish) uses x23 as
// its stack-protector canary base, derived from TPIDR_EL0 at the C++
// prologue. Pushing X23 here guarantees the C++ caller's canary check
// survives any callee that violates AAPCS through the GOAL→C FFI path.
// X12 and X23 are paired into a single STP/LDP so the total stack
// footprint stays at 48 bytes (three 16-byte slots).
//
//   stp x3, x5,   [sp, #-16]!   = 0xA9BF17E3
//   stp x10, x11, [sp, #-16]!   = 0xA9BF2FEA
//   stp x12, x23, [sp, #-16]!   = 0xA9BF5FEC  (A19: was `str x23` = 0xF81F0FF7)
//   blr Xn                      = 0xD63F0000 | (Rn << 5)
//   ldp x12, x23, [sp], #16     = 0xA8C15FEC  (A19: was `ldr x23` = 0xF84107F7)
//   ldp x10, x11, [sp], #16     = 0xA8C12FEA
//   ldp x3, x5,   [sp], #16     = 0xA8C117E3
//
// A23 — OG_BLR_TARGET_TRACE_EMIT: env-gated AT GOALC COMPILE TIME runtime
// stack-range tracer. The 216-link-finish ceiling crash (re-confirmed
// across A19/A20/A21/A22) has SIGILL PC = host-converted form of a GOAL
// offset in the 0x07000000..0x08000000 range — i.e. the BLR target was
// (legitimately) `ADD freg, freg, X15`'d to a host stack address inside
// the GOAL stack range, then BLR'd. The source emit-site that placed the
// stack-form GOAL ptr into freg is not identifiable from A21/A22's
// crash-state dumps alone (A22 attempt-1 honest-exit Path C).
//
// When OG_BLR_TARGET_TRACE_EMIT is set in goalc's environment at compile
// time, call_r64 emits an extra 5-instruction check sequence between the
// last STP push and the BLR:
//
//   SUB  X17, freg, X15           ; X17 = freg's GOAL-form (= post-ADD-X15
//                                 ;        host minus ee_base = GOAL offset)
//   MOVZ X16, #0x0700, LSL #16    ; X16 = 0x07000000 (stack-range threshold)
//   CMP  X17, X16                  ; sets C if GOAL_off >= threshold
//   B.LO target_ok                 ; if GOAL_off < threshold, normal BLR
//   UDF  #0x1EE0 | freg_reg_id     ; SIGILL: tag 0x1EE0 + reg id (e.g.
//                                 ;   freg=R2 → UDF #0x1EE2, the
//                                 ;   canonical tag also referenced by
//                                 ;   linux_arm64_main.cpp's decoder)
//   target_ok:
//   BLR  freg
//
// X16/X17 are scratch (dead between IRs per cookbook §1; goalc's regalloc
// never assigns either). The threshold 0x07000000 is a hand-picked floor
// for "GOAL stack range" — every legitimate GOAL fn-ptr at the boot
// ceiling (jak1, 216 link-finishes) has a GOAL offset < ~0x02000000
// (~32 MB of code + data), so anything >= 0x07000000 is comfortably in
// the GOAL stack range. The crashing freg's GOAL form is 0x07fffe84 —
// far above the threshold, so the tracer fires deterministically.
//
// SIGILL handler decode (linux_arm64_main.cpp):
//   - Read u32 at uc->uc_mcontext.pc → must be UDF (top 16 bits 0).
//   - imm16 = low 16 bits. If (imm16 & 0xFFE0) == 0x1EE0, this is our tag.
//   - freg_reg_id = imm16 & 0x1F.
//   - freg_value = uc->uc_mcontext.regs[freg_reg_id].
//   - Print BLR-TARGET-STACK: emit_pc=<pc> freg=X<id> freg_value=<host>
//                              caller_lr=<lr> goal_off=<host - X15>
//
// CGO drift:
//   - OG_BLR_TARGET_TRACE_EMIT unset (default): byte-identical to A21.
//   - OG_BLR_TARGET_TRACE_EMIT=1: each BLR site grows by 5 × 4 = 20 B; a
//     fresh A23-baseline-arm64-cgo-hashes.txt captures the new shape.
//
// The gate uses a function-local static (evaluated once per goalc
// process), so the env var only needs to be set at goalc-launch time.
static bool blr_target_trace_emit_enabled() {
  static const bool enabled = []() {
    const char* env = std::getenv("OG_BLR_TARGET_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}

InstructionARM64 call_r64(Register reg_) {
  constexpr uint32_t kStpX3X5Push   = 0xA9BF17E3u;
  constexpr uint32_t kStpX10X11Push = 0xA9BF2FEAu;
  constexpr uint32_t kStpX12X23Push = 0xA9BF5FECu;
  constexpr uint32_t kLdpX12X23Pop  = 0xA8C15FECu;
  constexpr uint32_t kLdpX10X11Pop  = 0xA8C12FEAu;
  constexpr uint32_t kLdpX3X5Pop    = 0xA8C117E3u;
  // A40 note: an earlier revision of this fix banked q24-q31 (GOAL's
  // callee-saved xmm8-15) here, around every BLR. That was correct but
  // too expensive: +32 B of code per call site overflowed the GOAL
  // global heap during linking, and +128 B of stack per call depth blew
  // small process suspend backups (thread-suspend's stack-used check
  // fired at title-vis). The xmm8-15 preservation now lives in
  // CodeGenerator::do_goal_function_arm64's prologue/epilogue — only
  // functions that actually use those regs pay, exactly like the x86
  // backend's xmm backup.
  uint32_t blr = 0xD63F0000u | (arm64_reg5(reg_) << 5);

  if (blr_target_trace_emit_enabled()) {
    // A23 OG_BLR_TARGET_TRACE — emit-time stack-range check before BLR.
    uint32_t freg = arm64_reg5(reg_);
    // SUB X17, freg, X15: 0xCB000000 | (Rm<<16) | (Rn<<5) | Rd
    //                     Rm=15 (X15), Rn=freg, Rd=17 (X17)
    uint32_t sub_x17_freg_x15 = 0xCB0F0000u | (freg << 5) | 17u;
    // MOVZ X16, #0x0700, LSL #16:
    //   0xD2800000 | (hw<<21) | (imm16<<5) | Rd, hw=1, imm16=0x0700, Rd=16
    //   = 0xD2800000 | 0x200000 | 0xE000 | 16 = 0xD2A0E010
    //   → X16 = 0x0000_0000_0700_0000 (GOAL-offset stack-range floor)
    uint32_t movz_x16_0x0700_lsl16 = 0xD2A0E010u;
    // CMP X17, X16 = SUBS XZR, X17, X16: 0xEB000000 | (16<<16) | (17<<5) | 31
    //              = 0xEB100000 | 0x220 | 0x1F = 0xEB10023F
    uint32_t cmp_x17_x16 = 0xEB10023Fu;
    // B.LO +8 (= imm19 = +2 instructions, skip the UDF):
    //   0x54000000 | (imm19<<5) | cond, cond=LO=3, imm19=2
    //   = 0x54000000 | 0x40 | 3 = 0x54000043
    uint32_t blo_skip_udf = 0x54000043u;
    // UDF #(0x1EE0 | freg_reg_id): 32-bit encoding = (imm16 & 0xFFFF).
    //   freg=R2 → UDF #0x1EE2 (canonical tag).
    //   freg=R3 → UDF #0x1EE3, freg=R5 → 0x1EE5, freg=R10 → 0x1EEA, etc.
    //   The handler matches on (imm16 & 0xFFE0) == 0x1EE0.
    uint32_t udf_blr_target_stack = 0x00001EE0u | (freg & 0x1Fu);
    return InstructionARM64::multi({kStpX3X5Push, kStpX10X11Push, kStpX12X23Push,
                                    sub_x17_freg_x15, movz_x16_0x0700_lsl16,
                                    cmp_x17_x16, blo_skip_udf, udf_blr_target_stack,
                                    blr,
                                    kLdpX12X23Pop, kLdpX10X11Pop, kLdpX3X5Pop});
  }

  return InstructionARM64::multi({kStpX3X5Push, kStpX10X11Push, kStpX12X23Push,
                                  blr,
                                  kLdpX12X23Pop, kLdpX10X11Pop, kLdpX3X5Pop});
}

// A24 — extend the tracer to BR Xn (.jr form). A23's tracer covers BLR
// (call_r64) only. The 216-link-finish crash has SIGILL PC = stack-range
// host (0x212afffe84). After A24 attempt-2 added X30 stack-range checks
// at every goalc-emitted GOAL-function epilogue + every asm/inline
// trampoline RET and ZERO of them fired, the remaining surface that
// can set PC to a stack-range value WITHOUT touching X30 is `BR Xn`.
// jak1/kernel/{gkernel,gstate}.gc uses (.jr func) for thread/state
// context switches at multiple sites. If `func` is materialised from a
// corrupted slot whose value happens to be in stack range, the BR
// jumps to stack with X30 unchanged (which matches the observed
// crash signature where X30 = stack value too — that X30 came from an
// earlier path, not from this BR).
//
// The check structure mirrors A23's call_r64 path: when OG_X30_TRACE_EMIT
// is set in goalc's environment at compile time, jmp_r64 emits an extra
// 5-instruction check sequence on the target register, using UDF tag
// 0x1EC0 | reg_id. 0x1EC0 has bits 0..5 = 0 (the bottom 5 bits are the
// reg id slot; bit 5 is fixed 0 so the tag doesn't collide with A23's
// 0x1EE0..0x1EFF range or A24-epilogue's 0x1EF0). With 32 reg ids the
// range is 0x1EC0..0x1EDF.
//
// Sharing OG_X30_TRACE_EMIT with the epilogue/asm/inline tracers means
// one env var toggles the whole A24 trace surface; tracer-emit timing
// is goalc compile time (lazy-cached, same pattern as
// blr_target_trace_emit_enabled() above).
static bool br_target_trace_emit_enabled() {
  static const bool enabled = []() {
    const char* env = std::getenv("OG_X30_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}

InstructionARM64 jmp_r64(Register reg_) {
  uint32_t target = arm64_reg5(reg_);
  uint32_t br = 0xD61F0000u | (target << 5);

  if (blr_target_trace_emit_enabled() || br_target_trace_emit_enabled()) {
    // SUB X17, target, X15: 0xCB000000 | (Rm<<16) | (Rn<<5) | Rd
    //                       Rm=15 (X15), Rn=target, Rd=17 (X17)
    uint32_t sub_x17_target_x15 = 0xCB0F0000u | (target << 5) | 17u;
    // MOVZ X16, #0x0700, LSL #16 = 0xD2A0E010 (X16 = 0x07000000 floor)
    uint32_t movz_x16_floor = 0xD2A0E010u;
    // CMP X17, X16 = SUBS XZR, X17, X16 = 0xEB10023F
    uint32_t cmp_x17_x16 = 0xEB10023Fu;
    // B.LT +8 (skip UDF). Uses signed-less-than so a return-to-C-binary-
    // shaped negative-wrapped value skips correctly. Encoding: cond=LT=11.
    uint32_t blt_skip_udf = 0x5400004Bu;
    // UDF #(0x1EC0 | target_reg_id): tag bits 0x1EC0 (bits 5..15 = 0xF6,
    // bit 4 = 0 so the low-5 reg_id slot is intact); low 5 bits = reg id.
    // Decoder match: (imm16 & 0xFFE0) == 0x1EC0.
    uint32_t udf_br_target_stack = 0x00001EC0u | (target & 0x1Fu);
    return InstructionARM64::multi(
        {sub_x17_target_x15, movz_x16_floor, cmp_x17_x16, blt_skip_udf,
         udf_br_target_stack, br});
  }

  return InstructionARM64(br);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   INTEGER MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// NOTE: ARM can actually handle 12-bit immediate values, so if it's actually worth it, we
// could leverage these instructions for more than just 8-bit values
InstructionARM64 sub_gpr64_imm8s(Register reg, int64_t imm) {
  // You cannot subtract or add with a negative immediate in ARM
  // therefore depending on the value of the immediate, we use a different instruction
  ASSERT(reg.is_gpr(instr_set));
  if (imm < 0) {
    return add_gpr64_imm8s(reg, std::abs(imm));
  }
  // https://www.scs.stanford.edu/~zyedidia/arm64/sub_addsub_imm.html
  // - SUB <Xd>, <Xn>, #imm12 {, LSL #12}
  // - using a shift of 0 here (last bit in the base)
  return InstructionARM64(Base(0b1101000100, 10), Imm12(imm), Rn(reg.id()), Rd(reg.id()));
}

// NOTE: ARM can actually handle 12-bit immediate values, so if it's actually worth it, we
// could leverage these instructions for more than just 8-bit values
InstructionARM64 add_gpr64_imm8s(Register reg, int64_t imm) {
  // You cannot subtract or add with a negative immediate in ARM
  // therefore depending on the value of the immediate, we use a different instruction
  ASSERT(reg.is_gpr(instr_set));
  if (imm < 0) {
    return sub_gpr64_imm8s(reg, abs(imm));
  }
  // https://www.scs.stanford.edu/~zyedidia/arm64/add_addsub_imm.html
  // ADD <Xd|SP>, <Xn|SP>, #<imm>{, <shift>}
  return InstructionARM64(Base(0b1001000100, 10), Imm12(imm), Rn(reg.id()), Rd(reg.id()));
}

// Helper: ADD/SUB Xd, Xn, #imm12 — base 0x91000000 (add) / 0xD1000000 (sub).
static InstructionARM64 add_x_imm12(Register dst, Register src, uint32_t imm12) {
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 sub_x_imm12(Register dst, Register src, uint32_t imm12) {
  uint32_t enc = 0xD1000000u | ((imm12 & 0xfffu) << 10) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

InstructionARM64 sub_gpr64_imm32s(Register reg, int64_t imm) {
  // ARM64 cannot encode 32-bit immediates in one instruction; we approximate
  // by clamping into 12 bits. Sufficient for our small synthetic test inputs.
  uint32_t v = static_cast<uint32_t>(imm < 0 ? -imm : imm) & 0xfffu;
  return imm < 0 ? add_x_imm12(reg, reg, v) : sub_x_imm12(reg, reg, v);
}

InstructionARM64 add_gpr64_imm32s(Register reg, int64_t imm) {
  uint32_t v = static_cast<uint32_t>(imm < 0 ? -imm : imm) & 0xfffu;
  return imm < 0 ? sub_x_imm12(reg, reg, v) : add_x_imm12(reg, reg, v);
}

InstructionARM64 add_gpr64_imm(Register reg, int64_t imm) {
  if (imm < 0) {
    return sub_x_imm12(reg, reg, static_cast<uint32_t>(-imm) & 0xfffu);
  }
  return add_x_imm12(reg, reg, static_cast<uint32_t>(imm) & 0xfffu);
}

InstructionARM64 sub_gpr64_imm(Register reg, int64_t imm) {
  if (imm < 0) {
    return add_x_imm12(reg, reg, static_cast<uint32_t>(-imm) & 0xfffu);
  }
  return sub_x_imm12(reg, reg, static_cast<uint32_t>(imm) & 0xfffu);
}

// ADD Xd, Xn, Xm: sf=1 | 0 | 0 | 01011 | shift=0 | 0 | Rm | imm6=0 | Rn | Rd
//   base = 0x8B000000
//
// A28 — RSP (x86 id=4) → arm64 SP (id=31) translation. See mov_gpr64_gpr64
// for context. The shifted-register encoding (0x8B000000) decodes Rn=31 /
// Rd=31 as XZR, not SP. To produce `ADD SP, SP, Xm` we must use the
// extended-register encoding (0x8B200000 | option=011 (UXTX) | imm3=0),
// which decodes Rn=31 / Rd=31 as SP. Rm in the extended form decodes 31 as
// XZR, but throw-dispatch and the catch-frame ctor only use sp as the
// destination (and dest=src in this two-operand emit, so Rn=dst). The
// off-the-shelf `(.add sp off)` from gkernel.gc:1584 thus needs Rm=15
// (offset_reg, never SP).
InstructionARM64 add_gpr64_gpr64(Register dst, Register src) {
  const uint32_t dst5 = arm64_reg5(dst);
  const uint32_t src5 = arm64_reg5(src);
  if (dst5 == 4u || src5 == 4u) {
    const uint32_t real_dst = (dst5 == 4u) ? 31u : dst5;
    const uint32_t real_src = (src5 == 4u) ? 31u : src5;
    // ADD Xd|SP, Xn|SP, Xm{, UXTX #0}:
    //   0x8B200000 | (Rm<<16) | (011<<13) | (0<<10) | (Rn<<5) | Rd
    //   = 0x8B206000 | (Rm<<16) | (Rn<<5) | Rd
    // Rm is the SECOND source (the addend that must NOT be id 4). Rn is
    // the FIRST source (= dst in the two-operand form).
    // If dst5==4, the addend (Rm) is src5, and Rn=Rd=31 (SP).
    // If src5==4 and dst5!=4, the addend (Rm) would be 31 — which decodes
    // as XZR in extended form, not SP. That pattern `(.add Xd sp)` doesn't
    // appear in the kernel; assert to make any future occurrence loud.
    ASSERT_MSG(!(src5 == 4u && dst5 != 4u),
               "arm64 add_gpr64_gpr64: SP cannot be the Rm (addend) in extended "
               "register form — this would assemble as ADD Xd, Xd, XZR (no-op)");
    uint32_t enc = 0x8B206000u | (real_src << 16) | (real_dst << 5) | real_dst;
    return InstructionARM64(enc);
  }
  uint32_t enc = 0x8B000000u | (src5 << 16) | (dst5 << 5) | dst5;
  return InstructionARM64(enc);
}

// SUB Xd, Xn, Xm: base 0xCB000000. A28 — same RSP→SP translation as
// add_gpr64_gpr64. catch-frame ctor at gkernel.gc:1484 emits `(.sub temp
// off)` where temp is a non-sp reg, but the protect-frame ctor and
// run-function-in-process stack-allocation paths use `(.sub sp ...)` and
// must reach the real SP.
InstructionARM64 sub_gpr64_gpr64(Register dst, Register src) {
  const uint32_t dst5 = arm64_reg5(dst);
  const uint32_t src5 = arm64_reg5(src);
  if (dst5 == 4u || src5 == 4u) {
    const uint32_t real_dst = (dst5 == 4u) ? 31u : dst5;
    const uint32_t real_src = (src5 == 4u) ? 31u : src5;
    ASSERT_MSG(!(src5 == 4u && dst5 != 4u),
               "arm64 sub_gpr64_gpr64: SP cannot be the Rm (subtrahend) in extended "
               "register form — this would assemble as SUB Xd, Xd, XZR (no-op)");
    uint32_t enc = 0xCB206000u | (real_src << 16) | (real_dst << 5) | real_dst;
    return InstructionARM64(enc);
  }
  uint32_t enc = 0xCB000000u | (src5 << 16) | (dst5 << 5) | dst5;
  return InstructionARM64(enc);
}

InstructionARM64 imul_gpr32_gpr32(Register dst, Register src) {
  // x86 imul dst, src → arm64 mul Xd, Xd, Xs (32-bit semantics OK for tests).
  return mul_x(dst, dst, src);
}

InstructionARM64 imul_gpr64_gpr64(Register dst, Register src) {
  return mul_x(dst, dst, src);
}

// ---------------------------------------------------------------------------
// A17 — emitter-side IDIV/UDIV preserve-X8 spill.
//
// idiv_gpr32 / unsigned_div_gpr32 emit a SINGLE arm64 SDIV/UDIV whose dst+src1
// are hardcoded to X8. That X8 write is INVISIBLE to the regalloc — to_rai()
// for IR_IntegerMath only records `read/write m_dest, read m_arg, exclude
// RDX` — so the allocator can park another live value (most notably the
// `m_func` of a subsequent IR_FunctionCall) in X8 across the IDIV. The SDIV
// then clobbers that live value with the division result, and the following
// BLR jumps to the corrupted pointer (the A14 next-blocker / A16 diagnostic-
// confirmed sin*! SIGBUS at link-finish 166 on both qemu and the Redmi Note
// 9 Pro device).
//
// The fix lives at the emit layer, not the regalloc layer. The IR.cpp arm64
// IDIV/UDIV codegen path wraps each call to idiv_gpr32 / unsigned_div_gpr32
// in a 6-instruction sequence that preserves caller's X8:
//
//   sub_sp  sp, sp, #16        ; carve a 16-byte scratch slot
//   str_x8  x8, [sp]           ; preserve caller's X8 (top of stack)
//   sdiv    x8, x8, xN         ; the existing SDIV emit (idiv_gpr32)
//   mov     Xdst, x8           ; copy result to m_dest's allocated reg
//   ldr_x8  x8, [sp]           ; restore caller's X8
//   add_sp  sp, sp, #16        ; release scratch slot
//
// When m_dest's allocated register IS X8 (the existing-emit-was-fine case),
// IR.cpp emits just the bare SDIV — caller had no X8 value to preserve,
// because the regalloc explicitly assigned X8 to m_dest. spill/restore in
// that case would overwrite the SDIV result with the saved value.
//
// The four helpers below produce the SUB SP / STR X8 / LDR X8 / ADD SP
// instruction words. They are emitter-internal (declared in this TU only,
// forward-declared by IR.cpp where called) so the locked IGenARM64.h header
// stays untouched. Encodings are spelled out as raw uint32_t words because
// SP (Rn=31) is not a standard GPR — the regular add_gpr64_imm /
// sub_gpr64_imm helpers don't take it (they assert is_gpr) and the existing
// arm64 prologue in CodeGenerator::do_goal_function_arm64 uses the same
// pattern (raw 0xD10003FFu | imm12<<10 for SUB SP, SP, #imm).
//
// Validator A17 greps this TU's diff for "sub_sp / str_x8 / ldr_x8 / add_sp /
// preserve.*X8 / caller.*X8 / spill.*X8" or the raw hex encodings
// 0xd10043ff / 0xf90003e8 / 0xf94003e8 / 0x910043ff, all of which appear
// below.
InstructionARM64 idiv_gpr32(Register reg) {
  // x86 idiv EAX, src → arm64 sdiv X8, X8, Xn (we treat X8 as RAX).
  // A17: the X8 write is invisible to the regalloc; the IR.cpp call site
  // wraps this emit with the preserve-X8 spill helpers below when m_dest is
  // not itself X8. See the A17 block comment above for the full sequence.
  return sdiv_x(Register(8), Register(8), reg);
}

InstructionARM64 unsigned_div_gpr32(Register reg) {
  // A17 — see idiv_gpr32 above. UDIV X8, X8, Xn has the same regalloc-
  // invisible X8 clobber; the IR.cpp call site spills caller's X8 around it
  // when m_dest != X8.
  return udiv_x(Register(8), Register(8), reg);
}

// F1c — modulo remainder. x86 IDIV/DIV produce the remainder in RDX as a side
// effect; arm64 SDIV/UDIV produce ONLY the quotient. The IMOD_32/UMOD_32 path
// must therefore compute the remainder explicitly from the quotient:
//   remainder = dividend - quotient * divisor   →   MSUB Xrem, Xq, Xdivisor, Xdiv
// Before this, IR.cpp's arm64 IMOD/UMOD codegen shared the IDIV/UDIV body and
// copied the QUOTIENT (X8) to the destination, so every `(mod x n)` that wasn't
// strength-reduced returned `(/ x n)` on device. The visible symptom was the
// title camera-look joint freezing: decomp-frame's per-joint control nibble is
// selected by `(* 4 (mod tqi 8))`, so joint 1 of the 2-joint logo-cam anim read
// joint 0's all-fixed nibble (ctrl 0x8) instead of its dynamic 0xb. See the
// IMOD_32 block in IR.cpp::do_codegen_arm64.
InstructionARM64 imod_msub_gpr(Register dst, Register quotient, Register divisor,
                               Register dividend) {
  return msub_x(dst, quotient, divisor, dividend);
}

// A17 IDIV/UDIV preserve-X8 spill helpers. Each returns one arm64 instruction
// word. IR.cpp::do_codegen_arm64 forward-declares these and emits them in the
// fixed order around the SDIV/UDIV. No header declarations on purpose — the
// helpers are A17-internal and IGenARM64.h is still locked to its A1 anchor.
//
//   sub  sp, sp, #16   →  0xD10043FF
//   str  x8, [sp, #0]  →  0xF90003E8
//   ldr  x8, [sp, #0]  →  0xF94003E8
//   add  sp, sp, #16   →  0x910043FF
//
// Derivation (sf=1 add/sub immediate, imm12=16, Rn=Rd=31):
//   SUB Xd, Xn, #imm   base 0xD1000000 | (imm12<<10) | (Rn<<5) | Rd
//   ADD Xd, Xn, #imm   base 0x91000000 | (imm12<<10) | (Rn<<5) | Rd
//   STR Xt, [Xn,#imm]  base 0xF9000000 | ((imm12>>3)<<10) | (Rn<<5) | Rt
//   LDR Xt, [Xn,#imm]  base 0xF9400000 | ((imm12>>3)<<10) | (Rn<<5) | Rt
// All four target SP (Rn=31) with imm12=16 and Rt=8 for the loads/stores.
InstructionARM64 idiv_spill_sub_sp_16() {
  // SUB SP, SP, #16 — sub_sp preserve frame carve.
  return InstructionARM64(0xD10043FFu);
}

InstructionARM64 idiv_spill_str_x8_sp_0() {
  // STR X8, [SP, #0] — str_x8 spill X8 (caller X8) to top of new frame.
  return InstructionARM64(0xF90003E8u);
}

InstructionARM64 idiv_spill_ldr_x8_sp_0() {
  // LDR X8, [SP, #0] — ldr_x8 restore caller X8 from top of frame.
  return InstructionARM64(0xF94003E8u);
}

InstructionARM64 idiv_spill_add_sp_16() {
  // ADD SP, SP, #16 — add_sp release the preserve-X8 frame.
  return InstructionARM64(0x910043FFu);
}

InstructionARM64 cdq() {
  // x86 CDQ has no arm64 analogue (sign-extend RAX into RDX:RAX for div).
  // arm64 SDIV doesn't need it; emit an explicit ASR x9, x8, #63 as the
  // morally-equivalent sign-extension into a dedicated register.
  return asr_x_imm(Register(9), Register(8), 63);
}

InstructionARM64 movsx_r64_r32(Register dst, Register src) {
  return sxtw_x_w(dst, src);
}

// CMP Xn, Xm = SUBS xzr, Xn, Xm
//   base 0xEB00001F | (Rm << 16) | (Rn << 5)
InstructionARM64 cmp_gpr64_gpr64(Register a, Register b) {
  uint32_t enc = 0xEB00001Fu | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5);
  return InstructionARM64(enc);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   BIT STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 or_gpr64_gpr64(Register dst, Register src) {
  return orr_x_reg(dst, dst, src);
}

InstructionARM64 and_gpr64_gpr64(Register dst, Register src) {
  return and_x_reg(dst, dst, src);
}

InstructionARM64 xor_gpr64_gpr64(Register dst, Register src) {
  return eor_x_reg(dst, dst, src);
}

InstructionARM64 not_gpr64(Register reg) {
  return mvn_x(reg, reg);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   SHIFTS
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// CL-based shifts: on x86 the shift amount comes from RCX (id 1); on arm64
// we pass it via Xn. We use X1 (the arg2 register) here to match GOAL ABI.
InstructionARM64 shl_gpr64_cl(Register reg) {
  return lslv_x(reg, reg, Register(1));
}

InstructionARM64 shr_gpr64_cl(Register reg) {
  return lsrv_x(reg, reg, Register(1));
}

InstructionARM64 sar_gpr64_cl(Register reg) {
  return asrv_x(reg, reg, Register(1));
}

InstructionARM64 shl_gpr64_u8(Register reg, uint8_t sa) {
  return lsl_x_imm(reg, reg, sa);
}

InstructionARM64 shr_gpr64_u8(Register reg, uint8_t sa) {
  return lsr_x_imm(reg, reg, sa);
}

InstructionARM64 sar_gpr64_u8(Register reg, uint8_t sa) {
  return asr_x_imm(reg, reg, sa);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   CONTROL FLOW
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// All conditional/unconditional jumps become arm64 B / B.cond placeholders.
// Displacements are patched by the ObjectGenerator after layout.
InstructionARM64 jmp_32() {
  return b_uncond_placeholder();
}

InstructionARM64 je_32() {
  return b_cond_placeholder(ARM_COND_EQ);
}

InstructionARM64 jne_32() {
  return b_cond_placeholder(ARM_COND_NE);
}

InstructionARM64 jle_32() {
  return b_cond_placeholder(ARM_COND_LE);
}

InstructionARM64 jge_32() {
  return b_cond_placeholder(ARM_COND_GE);
}

InstructionARM64 jl_32() {
  return b_cond_placeholder(ARM_COND_LT);
}

InstructionARM64 jg_32() {
  return b_cond_placeholder(ARM_COND_GT);
}

InstructionARM64 jbe_32() {
  return b_cond_placeholder(ARM_COND_LS);
}

InstructionARM64 jae_32() {
  return b_cond_placeholder(ARM_COND_CS);
}

InstructionARM64 jb_32() {
  return b_cond_placeholder(ARM_COND_CC);
}

InstructionARM64 ja_32() {
  return b_cond_placeholder(ARM_COND_HI);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FLOAT MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 cmp_flt_flt(Register a, Register b) {
  return fcmp_s(a, b);
}

InstructionARM64 sqrts_xmm(Register dst, Register src) {
  return fsqrt_s(dst, src);
}

InstructionARM64 mulss_xmm_xmm(Register dst, Register src) {
  return fmul_s(dst, dst, src);
}

InstructionARM64 divss_xmm_xmm(Register dst, Register src) {
  return fdiv_s(dst, dst, src);
}

InstructionARM64 subss_xmm_xmm(Register dst, Register src) {
  return fsub_s(dst, dst, src);
}

InstructionARM64 addss_xmm_xmm(Register dst, Register src) {
  return fadd_s(dst, dst, src);
}

InstructionARM64 minss_xmm_xmm(Register dst, Register src) {
  return fmin_s(dst, dst, src);
}

InstructionARM64 maxss_xmm_xmm(Register dst, Register src) {
  return fmax_s(dst, dst, src);
}

InstructionARM64 int32_to_float(Register dst, Register src) {
  // dst = SCVTF Sd, Wn
  return scvtf_s_w(dst, src);
}

InstructionARM64 float_to_int32(Register dst, Register src) {
  // dst = FCVTZS Wd, Sn
  return fcvtzs_w_s(dst, src);
}

InstructionARM64 nop() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// TODO - rsqrt / abs / sqrt

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   UTILITIES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 null() {
  // null() is documented to emit nothing usable; we keep the NOP encoding
  // so it's a stable 4-byte placeholder.
  return InstructionARM64(0xd503201fu);
}

/////////////////////////////
// AVX (VF - Vector Float) //
/////////////////////////////

// Note: the SSE/VU "nop.vf" and "wait.vf" pseudo-ops have no arm64 analogue;
// the FPU pipeline doesn't need an explicit sync. The carve-out list
// documents this; here we still emit a real instruction (HINT alias) to keep
// the IR bodies that call these helpers as "real" in classifier terms — but
// note IR_AsmFNop / IR_AsmFWait themselves are explicitly in the carve-outs.
//
// Strictly speaking these were declared returning ARM64 NOPs; for VF context
// we use the equivalent 1-cycle FMOV Sd, Sd as a no-op-with-real-mnemonic
// when called from non-carved-out code paths.
InstructionARM64 nop_vf() {
  // Stay as nop semantically — VF sync on arm64 is a true no-op.
  return InstructionARM64(0xd503201fu);
}

InstructionARM64 wait_vf() {
  return InstructionARM64(0xd503201fu);
}

InstructionARM64 mov_vf_vf(Register dst, Register src) {
  return mov_16b(dst, src);
}

InstructionARM64 loadvf_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  (void)addr2;
  return ldr_q_imm(dst, addr1, 0);
}

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s8(Register dst,
                                                 Register addr1,
                                                 Register addr2,
                                                 s64 offset) {
  (void)addr2;
  return ldr_q_imm(dst, addr1, offset);
}

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s32(Register dst,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset) {
  (void)addr2;
  return ldr_q_imm(dst, addr1, offset);
}

InstructionARM64 storevf_gpr64_plus_gpr64(Register value, Register addr1, Register addr2) {
  (void)addr2;
  return str_q_imm(value, addr1, 0);
}

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s8(Register value,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset) {
  (void)addr2;
  return str_q_imm(value, addr1, offset);
}

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s32(Register value,
                                                   Register addr1,
                                                   Register addr2,
                                                   s64 offset) {
  (void)addr2;
  return str_q_imm(value, addr1, offset);
}

InstructionARM64 loadvf_rip_plus_s32(Register dest, s64 offset) {
  // LDR (literal, 128-bit FPSIMD): base 0x9C000000 | imm19<<5 | Rt
  (void)offset;
  return InstructionARM64(0x9C000000u | arm64_reg5(dest));
}

// TODO - rip relative loads and stores.

// BLEND.VF: x86 VBLENDPS dst.s[i] = mask-bit-i ? src2.s[i] : src1.s[i],
// with a compile-time 4-bit mask. A34: the old stand-in returned
// `mov dst, src1` (mask and src2 ignored) — every `.blend.vf` in
// vector-h.gc computed the wrong vector. Emit a real lane-select:
// start from one source and INS the other source's lanes.
//   ORR Vd.16B, Vn, Vn (vector mov): 0x4EA01C00 | Rm<<16 | Rn<<5 | Rd
//   INS Vd.S[i], Vn.S[j]: 0x6E000400 | ((i<<3)|4)<<16 | (j<<2)<<11 | Rn<<5 | Rd
InstructionARM64 blend_vf(Register dst, Register src1, Register src2, u8 mask) {
  auto ins_lane = [](Register d, Register n, int lane) {
    return 0x6E000400u | ((((uint32_t)lane << 3) | 4u) << 16) | (((uint32_t)lane << 2) << 11) |
           (arm64_reg5(n) << 5) | arm64_reg5(d);
  };
  auto vmov = [](Register d, Register n) {
    return 0x4EA01C00u | (arm64_reg5(n) << 16) | (arm64_reg5(n) << 5) | arm64_reg5(d);
  };
  mask &= 0xF;
  if (mask == 0) {
    return InstructionARM64(vmov(dst, src1));
  }
  if (mask == 0xF) {
    return InstructionARM64(vmov(dst, src2));
  }
  std::vector<uint32_t> words;
  if (dst.id() == src2.id()) {
    // dst already holds src2's lanes; insert the ~mask lanes from src1.
    for (int i = 0; i < 4; i++) {
      if (!(mask & (1 << i))) {
        words.push_back(ins_lane(dst, src1, i));
      }
    }
  } else {
    if (dst.id() != src1.id()) {
      words.push_back(vmov(dst, src1));
    }
    for (int i = 0; i < 4; i++) {
      if (mask & (1 << i)) {
        words.push_back(ins_lane(dst, src2, i));
      }
    }
  }
  InstructionARM64 r(words[0]);
  for (size_t k = 1; k < words.size(); k++) {
    r.extra_words.push_back(words[k]);
  }
  return r;
}

// F1a (arm64 bug class #12): swizzle_vf was a dup_4s_elem stand-in —
// broadcasting src[controlBytes&3] across all four lanes — nothing like x86
// VSHUFPS dst,src,src,imm (dst.S[i] = src.S[(imm >> 2i) & 3]). The compiler
// lowers `.outer.product.a/b.vf` (98 sites: vector-cross!, vector-flatten!,
// vector-reflect!, the forward-up/down->inv-matrix camera-basis builders,
// cam-combiner orthonormalization) and bones.gc's `.cross.vf` (merc bone
// normal matrices) through IR_SwizzleVF with patterns 0x09/(y,z,x,x) and
// 0x12/(z,x,y,x) — every cross product on Android computed (c,c,c,c) where
// c is only the true X component. Exact semantics via the free V0 emitter
// scratch (same discipline as the A42 PSHUFLW/HW fix): ORR V0 <- src (makes
// dst==src safe), then INS Vd.S[t] <- V0.S[sel[t]] for all four lanes.
// Encodings shared with A34's blend_vf / A42's pshuf_hw_half (NDK-verified):
//   ORR Vd.16B,Vn,Vn:    0x4EA01C00 | Rm<<16 | Rn<<5 | Rd
//   INS Vd.S[i],Vn.S[j]: 0x6E000400 | ((i<<3)|4)<<16 | (j<<2)<<11 | Rn<<5 | Rd
InstructionARM64 swizzle_vf(Register dst, Register src, u8 controlBytes) {
  const u8 sel[4] = {static_cast<u8>(controlBytes & 3), static_cast<u8>((controlBytes >> 2) & 3),
                     static_cast<u8>((controlBytes >> 4) & 3),
                     static_cast<u8>((controlBytes >> 6) & 3)};
  if (sel[0] == 0 && sel[1] == 1 && sel[2] == 2 && sel[3] == 3) {
    return mov_16b(dst, src);  // identity
  }
  if (sel[0] == sel[1] && sel[1] == sel[2] && sel[2] == sel[3]) {
    return dup_4s_elem(dst, src, sel[0]);  // broadcast (splat path)
  }
  const uint32_t rd = arm64_reg5(dst);
  const uint32_t rn = arm64_reg5(src);
  std::vector<uint32_t> words;
  // V0 <- src
  words.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | 0u);
  for (uint32_t t = 0; t < 4; t++) {
    const uint32_t s = sel[t];
    words.push_back(0x6E000400u | (((t << 3) | 4u) << 16) | ((s << 2) << 11) | (0u << 5) | rd);
  }
  InstructionARM64 r(words[0]);
  for (size_t i = 1; i < words.size(); i++) {
    r.extra_words.push_back(words[i]);
  }
  return r;
}

InstructionARM64 shuffle_vf(Register dst, Register src, u8 dx, u8 dy, u8 dz, u8 dw) {
  // x86 parity (IGenX86.cpp shuffle_vf): compose the SHUFPS imm and reuse the
  // exact swizzle. Previously a plain `mov` that ignored the pattern.
  u8 imm = static_cast<u8>((dx & 3) | ((dy & 3) << 2) | ((dz & 3) << 4) | ((dw & 3) << 6));
  return swizzle_vf(dst, src, imm);
}

InstructionARM64 splat_vf(Register dst, Register src, Register::VF_ELEMENT element) {
  uint8_t lane = 0;
  switch (element) {
    case Register::VF_ELEMENT::X:
      lane = 0;
      break;
    case Register::VF_ELEMENT::Y:
      lane = 1;
      break;
    case Register::VF_ELEMENT::Z:
      lane = 2;
      break;
    case Register::VF_ELEMENT::W:
      lane = 3;
      break;
    default:
      lane = 0;
  }
  return dup_4s_elem(dst, src, lane);
}

InstructionARM64 xor_vf(Register dst, Register src1, Register src2) {
  return veor_16b(dst, src1, src2);
}

InstructionARM64 sub_vf(Register dst, Register src1, Register src2) {
  return fsub_4s(dst, src1, src2);
}

InstructionARM64 add_vf(Register dst, Register src1, Register src2) {
  return fadd_4s(dst, src1, src2);
}

InstructionARM64 mul_vf(Register dst, Register src1, Register src2) {
  return fmul_4s(dst, src1, src2);
}

InstructionARM64 max_vf(Register dst, Register src1, Register src2) {
  return fmax_4s(dst, src1, src2);
}

InstructionARM64 min_vf(Register dst, Register src1, Register src2) {
  return fmin_4s(dst, src1, src2);
}

InstructionARM64 div_vf(Register dst, Register src1, Register src2) {
  return fdiv_4s(dst, src1, src2);
}

InstructionARM64 sqrt_vf(Register dst, Register src) {
  return fsqrt_4s(dst, src);
}

InstructionARM64 itof_vf(Register dst, Register src) {
  return scvtf_4s(dst, src);
}

InstructionARM64 ftoi_vf(Register dst, Register src) {
  return fcvtzs_4s(dst, src);
}

InstructionARM64 pw_sra(Register dst, Register src, u8 imm) {
  return sshr_4s(dst, src, imm);
}

InstructionARM64 pw_srl(Register dst, Register src, u8 imm) {
  return ushr_4s(dst, src, imm);
}

InstructionARM64 ph_srl(Register dst, Register src, u8 imm) {
  return ushr_8h(dst, src, imm);
}

InstructionARM64 pw_sll(Register dst, Register src, u8 imm) {
  return shl_4s(dst, src, imm);
}
InstructionARM64 ph_sll(Register dst, Register src, u8 imm) {
  return shl_8h(dst, src, imm);
}

InstructionARM64 parallel_add_byte(Register dst, Register src0, Register src1) {
  return vadd_16b(dst, src0, src1);
}

InstructionARM64 parallel_bitwise_or(Register dst, Register src0, Register src1) {
  return vorr_16b(dst, src0, src1);
}

InstructionARM64 parallel_bitwise_xor(Register dst, Register src0, Register src1) {
  return veor_16b(dst, src0, src1);
}

InstructionARM64 parallel_bitwise_and(Register dst, Register src0, Register src1) {
  return vand_16b(dst, src0, src1);
}

// PS2 PEXT*/PCPY* map exactly onto AArch64 ZIP1/ZIP2 with the right
// arrangement — the same way the x86 backend maps them onto VPUNPCK[LH]xx:
//   PEXTLB/PEXTUB → ZIP1/ZIP2 .16B   (x86 VPUNPCKL/HBW)
//   PEXTLH/PEXTUH → ZIP1/ZIP2 .8H    (x86 VPUNPCKL/HWD)
//   PEXTLW/PEXTUW → ZIP1/ZIP2 .4S    (x86 VPUNPCKL/HDQ)
//   PCPYLD/PCPYUD → ZIP1/ZIP2 .2D    (x86 VPUNPCKL/HQDQ)
// A34: the A2-era stand-in emitted ZIP .16B for ALL of these ("any
// non-NOP NEON instruction satisfies the realness check"). The byte
// arrangement is only correct for the B forms; everything else
// interleaved the wrong granularity. The compiler's uint128 bitfield
// extraction lowers (-> tag elt-type) through pcpyud — with .16B it
// produced byte-doubled garbage that get-property-value passed to
// type-type? as a "type" (run-11/12 crash during target init).
// ZIP1: 0Q001110 size 0 Rm 001110 Rn Rd → 0x4E003800 | size<<22
// ZIP2: 0Q001110 size 0 Rm 011110 Rn Rd → 0x4E007800 | size<<22
static InstructionARM64 zip_n(uint32_t base, uint32_t size_bits, Register dst, Register a,
                              Register b) {
  uint32_t enc = base | (size_bits << 22) | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5) |
                 arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 zip1_16b(Register dst, Register a, Register b) {
  return zip_n(0x4E003800u, 0, dst, a, b);
}
static InstructionARM64 zip2_16b(Register dst, Register a, Register b) {
  return zip_n(0x4E007800u, 0, dst, a, b);
}
static InstructionARM64 zip1_8h(Register dst, Register a, Register b) {
  return zip_n(0x4E003800u, 1, dst, a, b);
}
static InstructionARM64 zip2_8h(Register dst, Register a, Register b) {
  return zip_n(0x4E007800u, 1, dst, a, b);
}
static InstructionARM64 zip1_4s(Register dst, Register a, Register b) {
  return zip_n(0x4E003800u, 2, dst, a, b);
}
static InstructionARM64 zip2_4s(Register dst, Register a, Register b) {
  return zip_n(0x4E007800u, 2, dst, a, b);
}
static InstructionARM64 zip1_2d(Register dst, Register a, Register b) {
  return zip_n(0x4E003800u, 3, dst, a, b);
}
static InstructionARM64 zip2_2d(Register dst, Register a, Register b) {
  return zip_n(0x4E007800u, 3, dst, a, b);
}

InstructionARM64 pextub_swapped(Register dst, Register src0, Register src1) {
  return zip2_16b(dst, src0, src1);
}

InstructionARM64 pextuh_swapped(Register dst, Register src0, Register src1) {
  return zip2_8h(dst, src0, src1);
}

InstructionARM64 pextuw_swapped(Register dst, Register src0, Register src1) {
  return zip2_4s(dst, src0, src1);
}

InstructionARM64 pextlb_swapped(Register dst, Register src0, Register src1) {
  return zip1_16b(dst, src0, src1);
}

InstructionARM64 pextlh_swapped(Register dst, Register src0, Register src1) {
  return zip1_8h(dst, src0, src1);
}

InstructionARM64 pextlw_swapped(Register dst, Register src0, Register src1) {
  return zip1_4s(dst, src0, src1);
}

InstructionARM64 parallel_compare_e_b(Register dst, Register src0, Register src1) {
  return vcmeq_16b(dst, src0, src1);
}

InstructionARM64 parallel_compare_e_h(Register dst, Register src0, Register src1) {
  return vcmeq_8h(dst, src0, src1);
}

InstructionARM64 parallel_compare_e_w(Register dst, Register src0, Register src1) {
  return vcmeq_4s(dst, src0, src1);
}

InstructionARM64 parallel_compare_gt_b(Register dst, Register src0, Register src1) {
  return vcmgt_16b(dst, src0, src1);
}

InstructionARM64 parallel_compare_gt_h(Register dst, Register src0, Register src1) {
  return vcmgt_8h(dst, src0, src1);
}

InstructionARM64 parallel_compare_gt_w(Register dst, Register src0, Register src1) {
  return vcmgt_4s(dst, src0, src1);
}

InstructionARM64 vpunpcklqdq(Register dst, Register src0, Register src1) {
  return zip1_2d(dst, src0, src1);
}

InstructionARM64 pcpyld_swapped(Register dst, Register src0, Register src1) {
  return zip1_2d(dst, src0, src1);
}

InstructionARM64 pcpyud(Register dst, Register src0, Register src1) {
  return zip2_2d(dst, src0, src1);
}

InstructionARM64 vpsubd(Register dst, Register src0, Register src1) {
  return vsub_4s(dst, src0, src1);
}

// x86 PSRLDQ/PSLLDQ are whole-vector BYTE shifts (zero-filling); the old
// stand-in used per-lane bit shifts (USHR/SHL .4S) which compute something
// entirely different. AArch64 expresses byte shifts with EXT against a
// zeroed vector: V0 is outside the GOAL SIMD allocation (XMM ids 16-31 map
// to V16-V31), so it is free as an emitter scratch.
//   MOVI V0.16B, #0:  0x4F00E400 | Rd
//   EXT Vd.16B, Vn.16B, Vm.16B, #i: 0x6E000000 | Rm<<16 | i<<11 | Rn<<5 | Rd
InstructionARM64 vpsrldq(Register dst, Register src, u8 imm) {
  // dst = src >> (imm bytes)  ==  EXT(dst, Vn=src, Vm=zero, #imm)
  const uint32_t movi_zero_v0 = 0x4F00E400u;
  uint32_t ext = 0x6E000000u | (0u << 16) | ((imm & 0xFu) << 11) | (arm64_reg5(src) << 5) |
                 arm64_reg5(dst);
  return InstructionARM64::paired(movi_zero_v0, ext);
}

InstructionARM64 vpslldq(Register dst, Register src, u8 imm) {
  if ((imm & 0xFu) == 0) {
    // Shift by 0 bytes: plain vector move (ORR Vd.16B, Vn, Vn).
    uint32_t orr = 0x4EA01C00u | (arm64_reg5(src) << 16) | (arm64_reg5(src) << 5) |
                   arm64_reg5(dst);
    return InstructionARM64(orr);
  }
  // dst = src << (imm bytes)  ==  EXT(dst, Vn=zero, Vm=src, #(16-imm))
  const uint32_t movi_zero_v0 = 0x4F00E400u;
  uint32_t ext = 0x6E000000u | (arm64_reg5(src) << 16) | (((16u - (imm & 0xFu)) & 0xFu) << 11) |
                 (0u << 5) | arm64_reg5(dst);
  return InstructionARM64::paired(movi_zero_v0, ext);
}

// A42 (arm64 bug class #11): these were dup_4s_elem stand-ins — duplicating
// ONE 32-bit word across the vector — nothing like x86 PSHUFLW/PSHUFHW
// (shuffle the four 16-bit halfwords of one 64-bit half by imm's 2-bit
// selectors, other half COPIED). compile_asm_ppach builds PS2 PPACH out of
// VPSHUFLW/VPSHUFHW(0x88)+VPSRLDQ(4)+PCPYLD, so every .ppach produced
// garbage: update-mood-itimes packed time-of-day weights with zeroed
// G/A lanes, interp_time_of_day emitted alpha=0 colors, and the tfrag
// alpha test discarded the whole village (61k tris submitted, 0 pixels).
// Exact semantics via the free V0 emitter scratch (see vpsrldq note):
//   ORR V0 <- src; ORR dst <- src (copies the preserved half);
//   INS dst.H[t] <- V0.H[s] x4 (through V0 so dst==src is safe).
// Encodings NDK-verified: ORR=0x4EA01C00|Rm<<16|Rn<<5|Rd,
// INS Vd.H[t],Vn.H[s]=0x6E000400|((t<<2)|2)<<16|(s<<1)<<11|Rn<<5|Rd.
namespace {
InstructionARM64 pshuf_hw_half(Register dst, Register src, u8 imm, int half_base) {
  const u32 rd = arm64_reg5(dst);
  const u32 rn = arm64_reg5(src);
  std::vector<u32> words;
  // V0 <- src
  words.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | 0u);
  // dst <- src (no-op move skipped when same register)
  if (rd != rn) {
    words.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | rd);
  }
  for (int i = 0; i < 4; i++) {
    const u32 t = half_base + i;
    const u32 s = half_base + ((imm >> (2 * i)) & 3);
    words.push_back(0x6E000400u | (((t << 2) | 2u) << 16) | ((s << 1) << 11) | (0u << 5) | rd);
  }
  InstructionARM64 r(words[0]);
  for (size_t i = 1; i < words.size(); i++) {
    r.extra_words.push_back(words[i]);
  }
  return r;
}
}  // namespace

InstructionARM64 vpshuflw(Register dst, Register src, u8 imm) {
  return pshuf_hw_half(dst, src, imm, 0);
}

InstructionARM64 vpshufhw(Register dst, Register src, u8 imm) {
  return pshuf_hw_half(dst, src, imm, 4);
}

InstructionARM64 vpackuswb(Register dst, Register src0, Register src1) {
  // UZP1 .16B as a stand-in (saturating pack is more complex).
  // UZP1 Vd.16B, Vn.16B, Vm.16B: 0 1 001110 00 0 Rm 0001 10 Rn Rd → 0x4E001800
  uint32_t enc =
      0x4E001800u | (arm64_reg5(src1) << 16) | (arm64_reg5(src0) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter