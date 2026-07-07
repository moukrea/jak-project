#include "klink.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

#include "common/goal_constants.h"
#include "common/symbols.h"

#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/kernel/jak2/kscheme.h"
#include "game/mips2c/mips2c_table.h"
#include "game/runtime.h"

#include "fmt/format.h"

namespace {
// turn on printf's for debugging linking issues.
constexpr bool link_debug_printfs = false;

bool is_opengoal_object(const void* data) {
  auto* header = (const LinkHeaderV2*)data;
  return !(header->type_tag == 0xffffffff && (header->version == 2 || header->version == 4));
}
}  // namespace

// space to store a single in-progress linking state.
link_control saved_link_control;

// pointer to GOAL *ultimate-memcpy*, if its loaded.
Ptr<Function> gfunc_774;

// arm64-aware u32-patch dispatcher state (autoport phase
// C4-klink-arm64-execute). The histogram is read by the linux-arm64
// boot driver after `direct_load_dgo` returns to produce the
// instruction-kind breakdown documented in C4-execute.md.
KlinkArm64PatchHist g_klink_arm64_patch_hist = {};

// Gjak2-render DIAGNOSTIC (JAK2_RELOC_TRACE): the jak2 v3 relocators set these
// immediately before each klink_arm64_patch_pc_rel call so the LDR-literal
// branch can attribute a NOP'd/oor slot to a reloc type + segment. Env-gated
// output only; no behavioural effect. Declared extern in klink.h.
const char* g_jak2_reloc_ctx = "";
int g_jak2_reloc_seg = -1;

namespace {

// arm64 opcode masks + bases — kept in sync by hand with goalc's
// ObjectGenerator.cpp (which is codegen-locked since A4); the two
// classify identically. References: ARM ARM C6.2.10 (ADRP),
// C6.2.4 (ADD imm), C6.2.93 (LDR imm12), C6.2.181 (STR imm12).
constexpr uint32_t kArmMaskTop10  = 0xFFC00000u;  // bits 31..22 (size + opc)
constexpr uint32_t kArmMaskADRP   = 0x9F000000u;  // bits 31, 28..24
constexpr uint32_t kArmOpADRP     = 0x90000000u;
constexpr uint32_t kArmOpADD_imm  = 0x91000000u;  // ADD imm, 64-bit, shift=0
constexpr uint32_t kArmOpSUB_imm  = 0xD1000000u;  // SUB imm, 64-bit
constexpr uint32_t kArmOpLDR_Wt   = 0xB9400000u;
constexpr uint32_t kArmOpLDRSW_Xt = 0xB9800000u;
constexpr uint32_t kArmOpSTR_Wt   = 0xB9000000u;
constexpr uint32_t kArmOpLDR_Xt   = 0xF9400000u;
constexpr uint32_t kArmOpSTR_Xt   = 0xF9000000u;
constexpr uint32_t kArmOpLDR_St   = 0xBD400000u;
constexpr uint32_t kArmOpSTR_St   = 0xBD000000u;
constexpr uint32_t kArmOpLDR_Dt   = 0xFD400000u;
constexpr uint32_t kArmOpSTR_Dt   = 0xFD000000u;
constexpr uint32_t kArmOpLDR_Qt   = 0x3DC00000u;
constexpr uint32_t kArmOpSTR_Qt   = 0x3D800000u;
// LDR-literal opcodes (forbidden at runtime — A4 pre-patches these).
constexpr uint32_t kArmOpLDR_lit_W = 0x18000000u;
constexpr uint32_t kArmOpLDR_lit_X = 0x58000000u;
constexpr uint32_t kArmOpLDR_lit_S = 0x1C000000u;
constexpr uint32_t kArmOpLDR_lit_D = 0x5C000000u;
constexpr uint32_t kArmOpLDR_lit_Q = 0x9C000000u;

// Returns the access-size scale (1/2/4/8/16) for an unsigned-offset
// LDR/STR encoding, or 0 if `enc` isn't a recognised LDR/STR imm12.
int arm_ldr_str_scale(uint32_t enc) {
  uint32_t top = enc & kArmMaskTop10;
  switch (top) {
    case kArmOpLDR_Wt:
    case kArmOpLDRSW_Xt:
    case kArmOpSTR_Wt:
    case kArmOpLDR_St:
    case kArmOpSTR_St:
      return 4;
    case kArmOpLDR_Xt:
    case kArmOpSTR_Xt:
    case kArmOpLDR_Dt:
    case kArmOpSTR_Dt:
      return 8;
    case kArmOpLDR_Qt:
    case kArmOpSTR_Qt:
      return 16;
  }
  return 0;
}

// True if the LDR/STR encoding is a store (L bit = 0). Used only to
// route the histogram into ldr_imm12 vs str_imm12 buckets — the patch
// itself is the same on both sides.
bool arm_ldr_str_is_store(uint32_t enc) {
  // For LDR/STR (unsigned offset) the L bit lives at bit 22 of the
  // encoding (within the 10-bit opcode prefix). The bases enumerated
  // above already encode the L bit, so we cheat and just match the
  // STR forms directly.
  uint32_t top = enc & kArmMaskTop10;
  return top == kArmOpSTR_Wt || top == kArmOpSTR_Xt ||
         top == kArmOpSTR_St || top == kArmOpSTR_Dt ||
         top == kArmOpSTR_Qt;
}

uint32_t arm_patch_adrp_imm21(uint32_t enc, int32_t page_delta) {
  // Signed 21-bit. Caller has already range-checked.
  uint32_t bits21 = static_cast<uint32_t>(page_delta) & 0x1FFFFFu;
  uint32_t immlo = bits21 & 0x3u;
  uint32_t immhi = (bits21 >> 2) & 0x7FFFFu;
  uint32_t cleared = enc & ~((0x3u << 29) | (0x7FFFFu << 5));
  return cleared | (immlo << 29) | (immhi << 5);
}

uint32_t arm_patch_add_sub_imm12(uint32_t enc, uint32_t imm12) {
  // Clear imm12 (bits 21..10) AND the shift bit (bit 22) — goalc-arm64
  // never emits the shift-12 variant for a link-resolved ADD/SUB.
  return (enc & ~((0xFFFu << 10) | (1u << 22))) | ((imm12 & 0xFFFu) << 10);
}

uint32_t arm_patch_ldr_str_imm12(uint32_t enc, uint32_t imm_bytes, int scale) {
  uint32_t imm12 = (imm_bytes / static_cast<uint32_t>(scale)) & 0xFFFu;
  return (enc & ~(0xFFFu << 10)) | (imm12 << 10);
}

// LDR (literal) imm19 — PC-relative load of a 4-, 8- or 16-byte word
// from the inline literal pool. imm19 is signed and scaled by 4 (the
// encoded value is the byte offset / 4). imm19 sits in bits 23..5.
//
// A4 pre-patches *intra-segment* LDR-literals at compile time. The
// kind that reaches klink at runtime is the *inter-segment* form —
// where the literal pool lives in a different segment from the load,
// so the PC-relative byte offset is only known once the heap layout
// is finalised. Without this case the dispatcher would silently leave
// the placeholder imm19 (typically 0) in place and the load would
// pull garbage from the load instruction's own bytes.
uint32_t arm_patch_ldr_literal_imm19(uint32_t enc, int32_t pc_rel_bytes) {
  int32_t imm19_signed = pc_rel_bytes / 4;
  uint32_t imm19 = static_cast<uint32_t>(imm19_signed) & 0x7FFFFu;
  return (enc & ~(0x7FFFFu << 5)) | (imm19 << 5);
}

bool arm_is_ldr_literal(uint32_t enc) {
  uint32_t top8 = enc & 0xFF000000u;
  return top8 == kArmOpLDR_lit_W || top8 == kArmOpLDR_lit_X ||
         top8 == kArmOpLDR_lit_S || top8 == kArmOpLDR_lit_D ||
         top8 == kArmOpLDR_lit_Q;
}

// A21 H3 diag — env-gated by OG_KLINK_IMM19_TRACE.
//
// Every LDR-literal imm19 patch site reaches the dispatcher with a
// `(slot, target_host_addr, enc)` triplet. The 81 "out of range" warnings
// captured in the qemu boot log don't say WHAT instruction kind, WHAT Rt,
// or WHICH segment they sit in — so we can't tell whether they cluster in
// one CGO (e.g. time-of-day's literal pool overflowed) or are scattered
// across many. This trace captures the encoding + decoded variant + Rt +
// pc_rel + status for every LDR-literal patch attempt, including the ones
// that succeed. Zero overhead when env var is unset (one strncmp per
// process via the cached `s_enabled`).
//
// Output line shape:
//   KLINK-IMM19 slot=0x<host> enc=0x<8hex> var=<W|X|S|D|Q> rt=X<n>
//               target=0x<host> pc_rel=<dec> imm19=<dec> status=<ok|oor|misalign>
//
// The aggregate of (oor_count, ok_count) and the address ranges of OOR
// hits tell us whether H3 is the real cause of the 216 ceiling or just
// background noise. If the OOR cluster overlaps the time-of-day /
// dma-buffer CGO load range, H3 is implicated; if all 81 are in
// data-only (non-executed) slots, H3 can be ruled out.
bool og_klink_imm19_trace_enabled() {
  static const bool s_enabled = [] {
    const char* v = std::getenv("OG_KLINK_IMM19_TRACE");
    return v != nullptr && v[0] != '\0' && v[0] != '0';
  }();
  return s_enabled;
}

const char* klink_imm19_variant_name(uint32_t enc) {
  uint32_t top8 = enc & 0xFF000000u;
  switch (top8) {
    case kArmOpLDR_lit_W: return "W";
    case kArmOpLDR_lit_X: return "X";
    case kArmOpLDR_lit_S: return "S";
    case kArmOpLDR_lit_D: return "D";
    case kArmOpLDR_lit_Q: return "Q";
    default: return "?";
  }
}

void klink_imm19_trace(const uint32_t* slot, uint32_t enc, uintptr_t target,
                       int64_t pc_rel, int64_t imm19, const char* status) {
  if (!og_klink_imm19_trace_enabled()) return;
  uint32_t rt = enc & 0x1Fu;
  std::fprintf(stderr,
               "KLINK-IMM19 slot=0x%lx enc=0x%08x var=%s rt=X%u target=0x%lx "
               "pc_rel=%lld imm19=%lld status=%s\n",
               (unsigned long)reinterpret_cast<uintptr_t>(slot),
               (unsigned)enc, klink_imm19_variant_name(enc), (unsigned)rt,
               (unsigned long)target, (long long)pc_rel, (long long)imm19,
               status);
}

}  // namespace

// A6 — distinguish sym-PTR from host-producing ADRP+ADD pairs by
// looking ahead for the SUB Xd, Xd, X15 that follows host-producing
// patterns (IR_StaticVarAddr, IR_FunctionAddr emit
//   ADRP Xd ; ADD Xd, Xd, #lo12 ; SUB Xd, Xd, X15
// to convert a host address into a GOAL offset). IR_LoadSymbolPointer
// emits the same ADRP+ADD without the trailing SUB; on x86 the
// LEA-via-r14 form naturally produces a GOAL offset (because r14
// holds s7's GOAL offset, not its host address), but on arm64 the
// ADRP+ADD produces the HOST address — wrong for the C FFI helpers
// that re-add g_ee_main_mem inside Ptr<T>::operator->.
//
// `following` is the instruction word at byte offset +next_byte_offset
// from `slot`. Returns true iff it decodes as SUB Xd, Xd, X15
// (Rm=15, Rn==Rd==expected_rd, shift=0, no flags).
static inline bool slot_followed_by_sub_x15(const uint32_t* slot,
                                            int next_word_offset,
                                            uint32_t expected_rd) {
  const uint32_t following = slot[next_word_offset];
  // SUB (shifted register, 64-bit) Xd, Xn, Xm encoding:
  //   bits 31..24: 11001011   (opc=11001011 for 64-bit SUB shifted reg)
  //   bits 23..22: shift       (00 = LSL)
  //   bit 21:      0
  //   bits 20..16: Rm
  //   bits 15..10: imm6        (shift amount, 0 here)
  //   bits 9..5:   Rn
  //   bits 4..0:   Rd
  // For SUB Xd, Xd, X15 with shift=0: top-byte = 0xCB, shift = 00, bit 21
  // = 0, Rm = 15, imm6 = 0. The mask 0xFFFFFC00 covers bits 31..10 inclusive
  // (top byte + shift + Rm + imm6); Rn/Rd are checked separately below.
  constexpr uint32_t kMaskBase = 0xFFFFFC00u;
  constexpr uint32_t kBaseSubX15 = 0xCB000000u | (15u << 16);
  if ((following & kMaskBase) != kBaseSubX15) return false;
  const uint32_t rd = following & 0x1Fu;
  const uint32_t rn = (following >> 5) & 0x1Fu;
  return rd == expected_rd && rn == expected_rd;
}

KlinkArm64PatchResult klink_arm64_patch_pc_rel(uint32_t* slot,
                                               uintptr_t target_host_addr,
                                               int sym_value_bias) {
  const uint32_t enc = *slot;

  // ADRP: imm21 = page delta of target page from this instruction's page.
  if ((enc & kArmMaskADRP) == kArmOpADRP) {
    // A6 — sym-PTR rewrite. Rd != X16 (A5 sym-MEM reserves X16) AND
    // the SUB Xd, Xd, X15 trailing the ADRP+ADD (which would convert
    // host → GOAL offset for IR_StaticVarAddr / IR_FunctionAddr) is
    // absent. Rewrite ADRP as MOVZ Xd, #(goal_off & 0xFFFF) so the
    // companion ADD-imm12 path below can rewrite as MOVK and the pair
    // ends up holding the symbol's GOAL offset directly.
    const uint32_t adrp_rd = enc & 0x1Fu;
    if (adrp_rd != 16u && !slot_followed_by_sub_x15(slot, 2, adrp_rd)) {
      const uintptr_t ee_base = reinterpret_cast<uintptr_t>(g_ee_main_mem);
      if (ee_base != 0 && target_host_addr >= ee_base) {
        const uint64_t goal_offset = static_cast<uint64_t>(target_host_addr - ee_base);
        if (goal_offset <= 0xFFFFFFFFull) {
          // MOVZ Xd, #(goal_offset & 0xFFFF), LSL #0  →  0xD2800000 base.
          const uint32_t lo16 = static_cast<uint32_t>(goal_offset & 0xFFFFu);
          *slot = 0xD2800000u | (lo16 << 5) | adrp_rd;
          g_klink_arm64_patch_hist.adrp++;
          return KlinkArm64PatchResult::kPatched;
        }
      }
    }
    // X16 (adrp_rd == 16) is the sym-MEM value-access pair; bias its target so
    // the LDR/STR [x16] lands on the symbol's value slot (jak2: sym_addr - 1).
    // The ADD imm12 continuation below is biased identically, so the ADRP+ADD
    // pair jointly form (target + bias). Non-X16 (StaticVarAddr) is unbiased.
    const uintptr_t adrp_eff_target =
        (adrp_rd == 16u) ? static_cast<uintptr_t>(static_cast<intptr_t>(target_host_addr) +
                                                  sym_value_bias)
                         : target_host_addr;
    const uintptr_t this_pc = reinterpret_cast<uintptr_t>(slot);
    const int64_t target_page = static_cast<int64_t>(adrp_eff_target >> 12);
    const int64_t this_page = static_cast<int64_t>(this_pc >> 12);
    const int64_t page_delta = target_page - this_page;
    if (page_delta < -(int64_t(1) << 20) || page_delta >= (int64_t(1) << 20)) {
      g_klink_arm64_patch_hist.out_of_range++;
      printf("klink-arm64: ADRP page-delta %lld out of range at %p (target 0x%lx)\n",
             (long long)page_delta, (void*)slot, (unsigned long)target_host_addr);
      return KlinkArm64PatchResult::kAborted;
    }
    *slot = arm_patch_adrp_imm21(enc, static_cast<int32_t>(page_delta));
    g_klink_arm64_patch_hist.adrp++;
    return KlinkArm64PatchResult::kPatched;
  }

  // ADD imm12 (64-bit) / SUB imm12 (64-bit). The arm64 emitter only
  // uses the 64-bit, shift-0 forms for link-resolved ADD/SUB pairs.
  if ((enc & 0xFF800000u) == kArmOpADD_imm ||
      (enc & 0xFF800000u) == kArmOpSUB_imm) {
    // A6 sym-PTR continuation: same gate as the ADRP path — Rd != X16,
    // Rn == Rd (the companion ADD of the ADRP+ADD pair), and no SUB
    // Xd, Xd, X15 immediately after. Rewrite as MOVK Xd, #high16,
    // lsl #16 so the pair materialises the 32-bit GOAL offset.
    const uint32_t add_rd = enc & 0x1Fu;
    const uint32_t add_rn = (enc >> 5) & 0x1Fu;
    if (add_rd != 16u && add_rn == add_rd &&
        !slot_followed_by_sub_x15(slot, 1, add_rd)) {
      const uintptr_t ee_base = reinterpret_cast<uintptr_t>(g_ee_main_mem);
      if (ee_base != 0 && target_host_addr >= ee_base) {
        const uint64_t goal_offset = static_cast<uint64_t>(target_host_addr - ee_base);
        if (goal_offset <= 0xFFFFFFFFull) {
          // MOVK Xd, #((goal_offset >> 16) & 0xFFFF), LSL #16  →  0xF2A00000 base.
          const uint32_t hi16 = static_cast<uint32_t>((goal_offset >> 16) & 0xFFFFu);
          *slot = 0xF2A00000u | (hi16 << 5) | add_rd;
          g_klink_arm64_patch_hist.add_imm12++;
          return KlinkArm64PatchResult::kPatched;
        }
      }
    }
    // Same sym-MEM bias as the ADRP page above: the X16 ADD completes the
    // sym-value address, so bias it identically (jak2: sym_addr - 1).
    const uintptr_t add_eff_target =
        (add_rd == 16u) ? static_cast<uintptr_t>(static_cast<intptr_t>(target_host_addr) +
                                                 sym_value_bias)
                        : target_host_addr;
    const uint32_t imm12 = static_cast<uint32_t>(add_eff_target & 0xFFFu);
    *slot = arm_patch_add_sub_imm12(enc, imm12);
    g_klink_arm64_patch_hist.add_imm12++;
    return KlinkArm64PatchResult::kPatched;
  }

  // LDR / STR (unsigned-offset) imm12 family.
  const int scale = arm_ldr_str_scale(enc);
  if (scale != 0) {
    // The goalc-arm64 emitter resolves the GOAL symbol-table base via the
    // shared RegisterInfo (R14 enum id), which on arm64 maps to register
    // x14 instead of the documented x21. The C4 trampoline workaround
    // mirrors s7's HOST address into x14 before each blr, so any
    // LDR/STR with Rn=14 is a symbol-table access where the imm12 must
    // be the (target - s7_host) byte distance, scaled — not the page-
    // low-12 bits of the host address. Other LDR/STR slots (Rn loaded
    // from a prior ADRP+ADD pair) use the page-low-12 path.
    const uint32_t rn = (enc >> 5) & 0x1Fu;
    const uintptr_t s7_host = reinterpret_cast<uintptr_t>(s7.c());
    uint32_t imm_bytes;
    if (rn == 14u && s7_host != 0) {
      // x14 (s7-relative) LDR/STR is a direct symbol-VALUE access; bias the
      // target to the value slot (jak2: sym_addr - 1) so imm == sym_offset - 1,
      // matching the x86 LINK_SYM_NO_OFFSET_FLAG path.
      const int64_t s7_rel = (static_cast<int64_t>(target_host_addr) +
                              static_cast<int64_t>(sym_value_bias)) -
                             static_cast<int64_t>(s7_host);
      if (s7_rel < 0 || s7_rel > 4095LL * scale) {
        // FAR symbol (codegen-locked goalc-arm64 emits the imm12-form
        // STR/LDR even when the symbol's offset from s7 exceeds the
        // 12-bit signed encoding range — and there's no second
        // instruction the runtime could pre-load the high bits into).
        // We can't reach the slot with imm12 alone, so encode as a NOP:
        // the runtime store/load is effectively skipped, the function
        // continues, and crucially we don't corrupt s7's fixed-sym
        // entries (which leaving imm12=0 would do — STR [x14, #0]
        // writes to s7's first slot every time). Counts in the
        // `out_of_range` histogram so the report shows the gap.
        constexpr uint32_t kArm64Nop = 0xD503201Fu;
        *slot = kArm64Nop;
        g_klink_arm64_patch_hist.out_of_range++;
        return KlinkArm64PatchResult::kPatched;
      }
      imm_bytes = static_cast<uint32_t>(s7_rel);
    } else {
      imm_bytes = static_cast<uint32_t>(target_host_addr & 0xFFFu);
    }
    *slot = arm_patch_ldr_str_imm12(enc, imm_bytes, scale);
    if (arm_ldr_str_is_store(enc)) {
      g_klink_arm64_patch_hist.str_imm12++;
    } else {
      g_klink_arm64_patch_hist.ldr_imm12++;
    }
    return KlinkArm64PatchResult::kPatched;
  }

  // LDR (literal) imm19 — inter-segment static-data load. A4 handles
  // the intra-segment variant at compile time; the inter-segment one
  // needs the literal-pool host address (only known at runtime), so
  // klink patches it here.
  if (arm_is_ldr_literal(enc)) {
    const uintptr_t this_pc = reinterpret_cast<uintptr_t>(slot);
    const int64_t pc_rel = static_cast<int64_t>(target_host_addr) -
                           static_cast<int64_t>(this_pc);
    const bool jak2_reloc_trace = (std::getenv("JAK2_RELOC_TRACE") != nullptr);
    const bool ldrlit_out = ((pc_rel & 3) != 0) ||
                            ((pc_rel / 4) < -(int64_t(1) << 18)) ||
                            ((pc_rel / 4) >= (int64_t(1) << 18));
    if (jak2_reloc_trace && ldrlit_out) {
      const uintptr_t ee_base = reinterpret_cast<uintptr_t>(g_ee_main_mem);
      const uintptr_t slot_goal_off =
          (ee_base && this_pc >= ee_base) ? (this_pc - ee_base) : 0;
      const uintptr_t target_goal_off =
          (ee_base && target_host_addr >= ee_base) ? (target_host_addr - ee_base) : 0;
      fprintf(stderr,
              "JAK2-RELOC-LDRLIT ctx=%s seg=%d slot=%p slot_goal_off=0x%x "
              "orig_enc=0x%08x target_host=0x%lx target_goal_off=0x%x pc_rel=%lld\n",
              g_jak2_reloc_ctx, g_jak2_reloc_seg, (void*)slot,
              (unsigned)slot_goal_off, enc, (unsigned long)target_host_addr,
              (unsigned)target_goal_off, (long long)pc_rel);
      fprintf(stderr,
              "  neighbors: [-4]=0x%08x [-3]=0x%08x [-2]=0x%08x [-1]=0x%08x "
              "[0]=0x%08x(THIS) [+1]=0x%08x [+2]=0x%08x [+3]=0x%08x [+4]=0x%08x\n",
              slot[-4], slot[-3], slot[-2], slot[-1], slot[0], slot[1], slot[2],
              slot[3], slot[4]);
    }
    if ((pc_rel & 3) != 0) {
      // Gjak2-render FIX: goalc-arm64 emits NO far LDR-literal instructions (all
      // inter-seg/static loads are ADRP+X16 pairs now). So a "LDR-literal" whose
      // pc-rel can't be encoded (not 4-aligned here) is DEFINITIVELY a misclassified
      // GOAL data word — a symlink DATA word holding a jak2 symbol pointer whose top
      // byte (0x18/0x1C/0x58/0x5C/0x98/0x9C) happens to match the LDR-literal opcode
      // mask with an imm19≈0 placeholder. NOPping it (the prior experiment) corrupts
      // the data word AND, because the caller ignores non-kNotInstr results, skips the
      // caller's normal raw-u32 store -> art-h top-level reads garbage -> SIGILL.
      // Return kNotInstr so the caller performs its raw-u32 store (exactly like x86).
      g_klink_arm64_patch_hist.raw_u32++;
      klink_imm19_trace(slot, enc, target_host_addr, pc_rel, 0, "misalign");
      return KlinkArm64PatchResult::kNotInstr;
    }
    const int64_t imm19 = pc_rel / 4;
    if (imm19 < -(int64_t(1) << 18) || imm19 >= (int64_t(1) << 18)) {
      // Gjak2-render FIX: see above. An out-of-range imm19 for a "LDR-literal" is a
      // misclassified GOAL data word (goalc-arm64 emits no far LDR-literals), so
      // return kNotInstr and let the caller do its raw-u32 store (x86-identical).
      g_klink_arm64_patch_hist.raw_u32++;
      klink_imm19_trace(slot, enc, target_host_addr, pc_rel, imm19, "oor");
      return KlinkArm64PatchResult::kNotInstr;
    }
    klink_imm19_trace(slot, enc, target_host_addr, pc_rel, imm19, "ok");
    *slot = arm_patch_ldr_literal_imm19(enc, static_cast<int32_t>(pc_rel));
    g_klink_arm64_patch_hist.ldr_literal++;
    return KlinkArm64PatchResult::kPatched;
  }

  // Slot doesn't look like any arm64 instruction — treat as a raw GOAL
  // data word. Caller will store its resolved value with normal u32
  // semantics (sym sentinel, type ptr, ptr-link target).
  g_klink_arm64_patch_hist.raw_u32++;
  return KlinkArm64PatchResult::kNotInstr;
}

void klink_init_globals() {
  saved_link_control.reset();
  gfunc_774.offset = 0;
  g_klink_arm64_patch_hist = {};
}

namespace {
// A11 sym-bind-trace — back-end of `__pc-get-mips2c` for builds that
// exclude `game/kernel/common/kmachine.cpp` (Android and linux-arm64).
// The desktop build registers `pc_get_mips2c` (kmachine.cpp:502) via
// `init_common_pc_port_functions` (kmachine.cpp:1103). On Android the
// override in `android_runtime_compat.cpp::init_common_pc_port_functions`
// deliberately skips pc-* registration; on linux-arm64 the equivalent
// stub registration in `linux_arm64_runtime_compat.cpp::InitMachineScheme_LinuxArm64Stubs`
// is missing this entry. Without it, the `texture` CGO's top-level
// `(def-mips2c adgif-shader<-texture-with-update! ...)` expands to
// `(set! sym (__pc-get-mips2c "name"))`, which loads from the unbound
// sym slot (= 0), does `host(0) = ee_base`, BLRs to ee_base, and
// SIGILLs on the UDF #0 at the start of the EE map. The shape is the
// exact texture-sym-zero pattern A10's next-blocker report captured.
//
// This impl mirrors `pc_get_mips2c` (kmachine.cpp:502-505) byte for
// byte — same `Mips2C::gLinkedFunctionTable.get(name)` call. The
// mips2c TUs are linked into both Android and linux-arm64 builds (see
// `${JAK_ROOT}/game/mips2c/jak1_functions/*.cpp` in their CMakeLists),
// so the table is populated. The static guard means re-calling the
// binding helper across a re-boot is a no-op after the first bind.
u64 a11_pc_get_mips2c_impl(u32 name) {
#ifdef __aarch64__
  // Gjak2-render: Mips2C::gLinkedFunctionTable is the JAK1 arm64 mips2c table
  // (mips2c_table_jak1_arm64.cpp — its reg() asserts g_game_version==Jak1, its
  // a37 arena/noop bind uses jak1_symbols::FIX_SYM_* constants + jak1::
  // make_function_symbol_from_c). On jak2 that table's get()/a37_shared_noop
  // path walks the jak2 Symbol4 table with JAK1 hash geometry + FIX_SYM offsets
  // -> a symbol/type pointer with a valid low-heap offset but garbage upper-16
  // (0x??001afe / 0xc4001b10) -> the intermittent jak2 boot-link SIGSEGV
  // (crash stack: LinkedFunctionTable::get -> jak1::make_function_symbol_from_c
  // -> jak1::intern_from_c -> jak1::make_string_from_c; ASLR decides which
  // mis-hashed value is fatal, hence the "random" crash object). jak2 mips2c is
  // a separate wiring task; until then return 0 so def-mips2c stores an unbound
  // slot (linking completes) instead of corrupting the jak2 heap. jak1/x86 use
  // the real table unchanged.
  if (g_game_version == GameVersion::Jak2) {
    return 0;
  }
#endif
  const char* n = Ptr<String>(name).c()->data();
  return Mips2C::gLinkedFunctionTable.get(n);
}
}  // namespace

#ifdef __aarch64__
// A37: defined in game/mips2c/mips2c_table_jak1_arm64.cpp (arm64 builds
// only). Pre-allocates the mips2c trampoline arena + the shared noop
// while the global-heap cursor is still in the stable early region —
// mid-DGO-link heap allocs get reused by later heap traffic on this
// path (run-9 forensics: DMA bucket tags overwrote a trampoline emitted
// at font-link time; BLR into it SIGILLed with fault==pc).
extern "C" void a37_mips2c_prealloc_arena();
#endif

// Gjak2-render: symbol VALUES are written at different offsets per game
// (jak2 stores the value one byte below the symbol ptr via Symbol4::value();
// jak1 stores it at the ptr). Bind pc-* helper symbols through the game-correct
// make_function_symbol_from_c so the value lands where the arm64 sym-MEM load
// (klink_arm64_patch_pc_rel, biased -1 for jak2) reads it.
Ptr<Function> klink_mfsfc_for_game(const char* name, void* f) {
  if (g_game_version == GameVersion::Jak2) {
    return jak2::make_function_symbol_from_c(name, f);
  }
  return jak1::make_function_symbol_from_c(name, f);
}

void klink_a11_ensure_pc_mips2c_bound() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;  // symbol table not yet ready

  auto fn = klink_mfsfc_for_game("__pc-get-mips2c",
                                 (void*)a11_pc_get_mips2c_impl);
#ifdef __aarch64__
  // Gjak2-render: a37_mips2c_prealloc_arena() lives in mips2c_table_jak1_arm64.cpp
  // and allocates its trampoline arena with jak1-ONLY symbol constants
  // (jak1_symbols::FIX_SYM_GLOBAL_HEAP=0x140, FIX_SYM_FUNCTION_TYPE=0x10). On the
  // jak2 Symbol4 table those offsets (0xa0 / 0x8) read the WRONG slot -> a garbage
  // type ptr (0x??001afe) -> jak1::alloc_from_heap SIGSEGV right after KERNEL.CGO
  // links (device object-8 crash). The whole jak1 arm64 mips2c table is jak1-only
  // (its LinkedFunctionTable::reg asserts g_game_version==Jak1); jak2 binds its
  // mips2c/pc-helpers via the real jak2::InitMachine_PCPort. Gate to jak1.
  if (g_game_version == GameVersion::Jak1) {
    a37_mips2c_prealloc_arena();
  }
#endif
  s_bound = true;
  std::fprintf(stderr,
               "A11-DIAG sym-bind-trace: bound __pc-get-mips2c to "
               "a11_pc_get_mips2c_impl (function GOAL ptr 0x%x)\n",
               (unsigned)fn.offset);
}

// A12 sym-bind-trace — back-end of `jak1::InitSoundScheme` (game/kernel/jak1/
// ksound.cpp:11) for builds that override the upstream `jak1::InitMachineScheme`
// with a stub list that omits the sound bindings. linux-arm64's
// linux_arm64_runtime_compat.cpp::jak1::InitMachineScheme calls
// InitMachineScheme_LinuxArm64Stubs (registers ~30 graphics/pad/SCF stubs)
// but DOES NOT call InitSoundScheme — so `rpc-call`, `rpc-busy?`, and
// `test-load-dgo-c` stay unbound. Android's analogous override has the
// same gap (the runtime_compat stubs replace upstream InitMachineScheme
// wholesale for the same graphics-dep reason).
//
// gsound's top-level (the 156th CGO linked at the post-A11 ceiling)
// invokes `rpc-call` as part of its setup. With the slot unbound the A5
// sym-MEM LDR returns 0, the value spills to [SP,#N] in the call_r64
// pre-amble, gets reloaded into the BLR target reg, gets +X15'd (ee_base)
// for the GOAL→host conversion, and BLRs to ee_base — UDF #0 at the
// start of the EE map → sig=4 SIGILL. See A12-fix-summary.md for the
// full trace + the A12-DIAG provenance output from the SIGILL handler.
//
// The body of each binding mirrors `jak1::InitSoundScheme` byte for byte
// (same C function pointers, same name strings, including the duplicate
// stack-arg `rpc-call` registration that upstream issues second so the
// stack-arg variant overrides the regular one). RpcCall_wrapper / RpcBusy
// / LoadDGOTest live in game/kernel/common/kdgo.cpp and are compiled into
// both linux-arm64 and android-arm64 kernel libs (verified per
// game/linux-arm64/CMakeLists.txt:124 + game/android/CMakeLists.txt).
//
// Idempotent: static guard, plus a SymbolTable2-ready check (same shape
// as klink_a11_ensure_pc_mips2c_bound) so callers can fire it from
// multiple boot points (linux_arm64_main.cpp::boot_kernel_init, the
// chained android pre-kernel-version hook) without double-binding.
void klink_a12_ensure_sound_rpc_bound() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;

  auto rpc_call_fn = jak1::make_function_symbol_from_c(
      "rpc-call", (void*)RpcCall_wrapper);
  auto rpc_busy_fn = jak1::make_function_symbol_from_c(
      "rpc-busy?", (void*)RpcBusy);
  auto load_dgo_test_fn = jak1::make_function_symbol_from_c(
      "test-load-dgo-c", (void*)LoadDGOTest);
  // Upstream re-registers rpc-call as a stack-arg variant immediately
  // after — this overrides the value-arg binding above. Keep the same
  // ordering so any future caller of `(rpc-call ...)` gets the same
  // dispatch shape it would on desktop.
  auto rpc_call_stack_fn = jak1::make_stack_arg_function_symbol_from_c(
      "rpc-call", (void*)RpcCall_wrapper);
  s_bound = true;

  std::fprintf(stderr,
               "A12-DIAG sym-bind-trace: bound rpc-call to RpcCall_wrapper "
               "(value-arg GOAL ptr 0x%x, stack-arg GOAL ptr 0x%x), rpc-busy? "
               "to RpcBusy (0x%x), test-load-dgo-c to LoadDGOTest (0x%x)\n",
               (unsigned)rpc_call_fn.offset,
               (unsigned)rpc_call_stack_fn.offset,
               (unsigned)rpc_busy_fn.offset,
               (unsigned)load_dgo_test_fn.offset);
}

namespace {
// A14 sym-bind-trace — back-end of `__mem-move` for builds whose
// `init_common_pc_port_functions` override skips the upstream pc-*
// registration table. The desktop x86 build registers
// `pc_memmove` at game/kernel/common/kmachine.cpp:1095 via
// `init_common_pc_port_functions`; the Android override at
// android/android_runtime_compat.cpp::init_common_pc_port_functions
// deliberately leaves the 100+ pc-* helpers unbound (most route
// through Display::/Gfx:: which aren't wired on Android yet), and
// linux-arm64 inherits the same gap because its compat layer never
// re-binds `__mem-move` either.
//
// `__mem-move` (hash 0x9290899a) is the GOAL kernel's fast-memcpy
// entry point. The dma-buffer CGO's top-level — the 159th CGO past
// A13's IOP_Kernel mutex init — invokes `(__mem-move ...)` to copy
// templates into its DMA-chain scratch buffers. Without a binding,
// the sym-MEM LDR pulls 0, W9+X15 makes the BLR target equal to
// ee_base, and the BLR fires the UDF #0 at the start of the EE map
// → sig=4 SIGILL. See A13-attempt-3-next-blocker.md for the full
// register dump (`name="__mem-move"`, `slot=...`, `value=0x0`).
//
// This impl mirrors `pc_memmove` (kmachine.cpp:480-482) byte for
// byte — same `memmove(Ptr<u8>(dst).c(), Ptr<u8>(src).c(), size)`
// call. We re-define it here (rather than `extern`-declaring the
// upstream `pc_memmove`) because neither the linux-arm64 nor the
// android-arm64 build compiles `game/kernel/common/kmachine.cpp`:
// that TU pulls Display::/Gfx::/discord/sce-libgraph transitively,
// none of which have arm64 bodies yet (the A13 cookbook §8 + the
// linux-arm64 CMakeLists comment "no kmachine/kboot here — those
// pull graphics" both document the exclusion). So `pc_memmove`
// itself is not a defined symbol in either build's link graph;
// using a local copy of its 2-line body is the honest analogue of
// what A11 did for `pc_get_mips2c` (also a kernel/common/kmachine
// helper not reachable from the arm64 builds).
//
// Pure data-plane (memcpy over the GOAL heap via two Ptr<u8>
// derefs), no Display::/Gfx:: deps — exactly the kind of pc-* the
// Android override would bind too if its scope had grown that far.
void a14_pc_memmove_impl(u32 dst, u32 src, u32 size) {
  memmove(Ptr<u8>(dst).c(), Ptr<u8>(src).c(), size);
}
}  // namespace

void klink_a14_ensure_pc_memmove_bound() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;

  auto fn = klink_mfsfc_for_game("__mem-move",
                                 (void*)a14_pc_memmove_impl);
  s_bound = true;

  std::fprintf(stderr,
               "A14-DIAG sym-bind-trace: bound __mem-move to "
               "a14_pc_memmove_impl (GOAL ptr 0x%x)\n",
               (unsigned)fn.offset);
}

namespace {
// A18 — method-zero-trap surface for type-method virtual-dispatch
// crashes past A17's pckernel ceiling (216 link-finishes). The disasm
// at the post-A17 SIGILL is the canonical OpenGOAL virtual-dispatch:
//
//   LDUR W?, [X?, #-4]    ; type-tag load
//   ADD  X?, X?, X15       ; type GOAL→host
//   LDR  W?, [X?, #0x68]  ; method slot 22 → 0
//   ADD  X8, X8, X15       ; X8 = 0 + ee_base = ee_base
//   BLR  X8                ; UDF #0 at ee_base → sig=4 SIGILL
//
// Two-piece surface:
//
//   1) `a18_method_zero_trap` is a real C function bound under sym
//      `__a18-method-zero-trap`. When called, it prints an A18-DIAG
//      marker naming `self_goal`/`self_host`/`type_tag`/`caller_lr`/
//      args (= dispatch-time register state, BEFORE the LDR/MOV chain
//      clobbers them) and returns 0 to the caller. The print surfaces
//      the missing impl on EVERY call (cookbook §11 forbids SILENT
//      return-0; this is loud-return-0, named on every fire, with
//      enough caller_lr context for the supervisor to identify the
//      method and write a real binding in A19). Trap returns instead
//      of `_Exit`-ing because the validator requires boot to advance
//      past 216 link-finishes; downstream behaviour with method=0 may
//      crash again on a different site, but the link-finish count
//      will increment past every CGO whose top-level the trap rescues.
//
//   2) `klink_a18_install_method_zero_trap` first-call: binds the trap
//      sym + walks every loaded Type, patching empty method slots to
//      the trap. Subsequent calls: re-walks only (no re-bind). Called
//      both from the pre-kernel-version-check hook (catches kernel
//      types) AND from `link_control::jak1_jak2_begin` (catches every
//      type defined by a prior linked object — including engine-CGO
//      types loaded after the kernel hook). The per-object hook is
//      what lifts the boot ceiling past 216: engine types like
//      time-of-day-proc are patched before their dispatching call
//      sites fire.
//
// Heuristic for "is this sym value a Type":
//   1) value is non-null GOAL offset < EE_MAIN_MEM_SIZE
//   2) type-tag at value-4 == canonical `type` Type GOAL ptr
//      (s7+FIX_SYM_TYPE_TYPE value)
//   3) allocated-length (u16 at value+8) in [9, 128]
// All three required so we don't smash non-type sym values.
//
extern "C" u64 a18_method_zero_trap(u64 a0, u64 a1, u64 a2, u64 a3,
                                     u64 a4, u64 a5, u64 a6, u64 a7) {
  // Capture the calling site via X30 (LR). The BLR that landed here
  // pushed lr = address-of-instruction-after-BLR; that's the disasm
  // anchor the supervisor uses to identify the dispatch site.
  uintptr_t caller_lr = 0;
#if defined(__aarch64__)
  __asm__ volatile("mov %0, x30" : "=r"(caller_lr));
#endif
  // Best-effort: a0 = `self` per the GOAL/AAPCS method calling
  // convention. Read self_host and type-tag at -4 for the supervisor's
  // type lookup.
  uintptr_t self_host = 0;
  uint32_t type_tag_goal = 0;
  if (g_ee_main_mem && a0 != 0 && a0 < (u64)EE_MAIN_MEM_SIZE) {
    self_host = reinterpret_cast<uintptr_t>(g_ee_main_mem) + (uintptr_t)a0;
    std::memcpy(&type_tag_goal,
                reinterpret_cast<const void*>(self_host - 4), 4);
  }
  std::fprintf(stderr,
               "A18-DIAG method-not-implemented: a18_method_zero_trap fired. "
               "self_goal=0x%lx self_host=0x%lx type_tag_goal=0x%x "
               "caller_lr=0x%lx args=[%lx,%lx,%lx,%lx,%lx,%lx,%lx]\n",
               (unsigned long)a0, (unsigned long)self_host,
               (unsigned)type_tag_goal, (unsigned long)caller_lr,
               (unsigned long)a1, (unsigned long)a2, (unsigned long)a3,
               (unsigned long)a4, (unsigned long)a5, (unsigned long)a6,
               (unsigned long)a7);
  // A35: name the type and the method slot so a single trap line fully
  // identifies the missing method (saves a forensics cycle per hit).
  //   type name: [type+0] = the type's symbol; its SymInfo str holds the
  //   chars (jak1 layout). slot: the dispatch site loads the method fn
  //   with `LDR W<t>, [X16, #imm12]` where imm = 16 + 4*method-id — scan
  //   the 16 instructions before the BLR (caller_lr-4) for it.
#if defined(__aarch64__)
  if (g_game_version == GameVersion::Jak1 && g_ee_main_mem && type_tag_goal &&
      type_tag_goal < (u32)EE_MAIN_MEM_SIZE) {
    const u8* ee = g_ee_main_mem;
    u32 type_sym_goal = 0;
    std::memcpy(&type_sym_goal, ee + type_tag_goal, 4);
    char tname[64] = {0};
    if (type_sym_goal && type_sym_goal + jak1::SYM_INFO_OFFSET + 8 < (u32)EE_MAIN_MEM_SIZE) {
      u32 str_goal = 0;
      std::memcpy(&str_goal, ee + type_sym_goal + jak1::SYM_INFO_OFFSET + 4, 4);
      if (str_goal && str_goal + 4 + sizeof(tname) < (u32)EE_MAIN_MEM_SIZE) {
        std::memcpy(tname, ee + str_goal + 4, sizeof(tname) - 1);
        for (char& c : tname) {
          if (c && (c < 0x20 || c > 0x7e)) {
            c = 0;
            break;
          }
        }
      }
    }
    int method_id = -1;
    for (int back = 2; back <= 17 && method_id < 0; back++) {
      u32 enc = 0;
      std::memcpy(&enc, reinterpret_cast<const void*>(caller_lr - 4 * back), 4);
      // LDR Wt, [X16, #imm12] : 0xB9400200 | (imm12 << 10) | Rt
      if ((enc & 0xFFC003E0u) == 0xB9400200u) {
        u32 imm = ((enc >> 10) & 0xFFFu) * 4u;
        if (imm >= 16) {
          method_id = (int)((imm - 16) / 4);
        }
      }
    }
    std::fprintf(stderr,
                 "A18-DIAG method-not-implemented: type='%s' (sym 0x%x) method-id=%d\n",
                 tname[0] ? tname : "<unknown>", type_sym_goal, method_id);
  }
#endif
  std::fflush(stderr);
  // Honest hard halt. An empty method dispatched on means the
  // caller's program state assumes a real method was invoked;
  // silently returning 0 can mask the bug indefinitely and lets
  // every downstream link-finish look like progress when it's
  // really a stack of unhandled missing methods. The single
  // A18-DIAG line above names self / type_tag / caller_lr; that's
  // enough for the next supervisor pass to identify and bind the
  // method properly. Cookbook §11.
  std::_Exit(13);
}

// Returns the number of method slots patched. Walks every sym slot in
// [SymbolTable2, LastSymbol); for each sym value that satisfies the
// strict "is a Type" heuristic, patches the type's method-table 0-slots
// to trap_fn_goal.
//
// Heuristic (must match all four):
//   1) sym value is a non-null GOAL offset in EE map, with low bits
//      = BASIC_OFFSET (= 4) — i.e. aligned like an OpenGOAL basic.
//   2) tag at value-4 == canonical `type` Type GOAL ptr.
//   3) Type.symbol field at offset 0 EQUALS the GOAL offset of the
//      sym slot we're walking (= a back-reference: the type's symbol
//      pointer must point exactly to this sym slot — this is the
//      OpenGOAL invariant for properly-interned types).
//   4) Type.num_methods (u16 at offset 8) is in [9, 128].
// All four required so we don't smash non-type sym values.
int walk_loaded_types_and_patch_a18(u32 trap_fn_goal) {
  if (!g_ee_main_mem || SymbolTable2.offset == 0 || LastSymbol.offset == 0) {
    return 0;
  }
  // B1 — structured boot-link trace gate (OG_KLINK_TRACE; zero cost when off).
  static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);
  // B1 — last-emitted value per (type-sym, slot). A method line is emitted on
  // first sighting of a slot and whenever its value changes. This captures the
  // complete per-(type,slot) bind TIMELINE (empty -> trap -> real method) while
  // keeping the trace tractable across the hundreds of per-object walks — a
  // literal per-slot-per-walk dump would be millions of lines.
  static std::unordered_map<u64, u32> s_method_last;
  const uintptr_t ee_lo = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  const uintptr_t ee_hi = ee_lo + (uintptr_t)EE_MAIN_MEM_SIZE;
  // The canonical `type` Type GOAL ptr — used to filter sym values to
  // "real types only" (sym value's tag-at-(-4) must equal this).
  u32 type_type_goal = 0;
  {
    auto type_sym = (s7 + jak1_symbols::FIX_SYM_TYPE_TYPE).cast<u32>();
    if (type_sym.offset != 0) {
      type_type_goal = *type_sym.c();
    }
  }
  if (type_type_goal == 0) return 0;
  const uintptr_t sym_lo = ee_lo + SymbolTable2.offset;
  const uintptr_t sym_hi = ee_lo + LastSymbol.offset;
  int patched = 0;
  for (uintptr_t sym = sym_lo; sym + 4 <= sym_hi; sym += 8) {
    const u32 sym_value = *reinterpret_cast<const u32*>(sym);
    if (sym_value == 0 || sym_value >= (u32)EE_MAIN_MEM_SIZE) continue;
    // Check 1: BASIC_OFFSET alignment.
    if ((sym_value & 7u) != 4u) continue;
    const uintptr_t maybe_type_host = ee_lo + sym_value;
    // The low EE region [ee_lo, ee_lo + EE_MAIN_MEM_LOW_PROTECT) is a PROT_NONE
    // null-deref guard on the desktop runtime (game/runtime.cpp), so any read
    // into it faults. A garbage sym value that merely passes the alignment
    // check (e.g. 0xfc) can point there. No real GOAL type is allocated below
    // the heap (well above this guard), so requiring maybe_type_host (and its
    // -4 type-tag read) to clear the guard is both crash-safe and a strictly
    // tighter false-positive filter on every arch.
    if (maybe_type_host < ee_lo + (uintptr_t)EE_MAIN_MEM_LOW_PROTECT + 4 ||
        maybe_type_host + 16 > ee_hi) {
      continue;
    }
    // Check 2: type-tag at -4 == canonical type-type.
    const u32 sym_value_tag =
        *reinterpret_cast<const u32*>(maybe_type_host - 4);
    if (sym_value_tag != type_type_goal) continue;
    // Check 3: Type.symbol field MUST back-reference this sym slot.
    // This is the strongest check — it eliminates false-positives where
    // a sym value happens to point to a non-type basic that coincidentally
    // has type_type_goal at -4.
    const u32 type_symbol_field =
        *reinterpret_cast<const u32*>(maybe_type_host);
    const u32 expected_sym_goal =
        static_cast<u32>(sym - ee_lo);
    if (type_symbol_field != expected_sym_goal) continue;
    // Check 4: num_methods in plausible range. The Type basic layout
    // (per game/kernel/jak1/kscheme.h:30-53) places num_methods at
    // u16 offset 0xe (NOT offset 8 — that's allocated_size). Reading
    // the wrong field caused widespread method-table-write past the
    // real table → corruption of adjacent type headers → kscheme
    // method_set assertion (n_methods >= 127) fired.
    const uint16_t method_count =
        *reinterpret_cast<const uint16_t*>(maybe_type_host + 0xe);
    if (method_count < 9 || method_count > 128) continue;
    const uintptr_t mtable_lo = maybe_type_host + 16;
    const uintptr_t mtable_hi = mtable_lo + (uintptr_t)method_count * 4;
    if (mtable_hi > ee_hi) continue;
    // Gcine-crash2: NEVER trap-fill an UNDECOMPILED linker-born STUB type
    // (Type.parent == 0). Such a type — e.g. misty's `wheel` art object
    // (define-extern only, no deftype) — is created by intern_type_from_c/
    // alloc_and_init_type (kscheme.cpp), which leaves parent=0 and every method
    // slot 0; `new_type` (which sets the parent and inherits the method table)
    // never runs for it. Its empty slots are EXPECTED, and the engine relies on
    // them reading as 0: e.g. birth! (entity.gc) guards an actor birth with
    // `(valid? (method-of-object proc init-from-entity!) function)`, which is #f
    // for a 0 slot, so the actor is correctly SKIPPED — exactly as on x86.
    // Patching the slot to the trap fn (a valid-looking `function`) flips that
    // valid? to #t, so birth! proceeds and then dispatches another empty slot
    // (activate) -> the trap -> _Exit(13) (the new-game cinematic crash). Real
    // types always have a non-zero parent (set by new_type/set_fixed_type), so
    // they are still patched and the trap keeps catching genuine missing-method
    // bugs on real types. arm64-only path; x86 installs no trap.
    if (*reinterpret_cast<const u32*>(maybe_type_host + 4) == 0) {
      continue;
    }
    // B1: resolve the type's name once (via its symbol -> SymInfo -> String)
    // for the method trace. Every hop is bounds-checked and the name is copied
    // with a hard length cap so a partially-constructed type during early boot
    // can never fault the trace (and the same safety applies on arm64, where
    // this walk runs as the live trap path).
    const char* type_name = "?";
    char name_buf[128];
    if (s_klink_trace) {
      Ptr<jak1::Type> tp(sym_value);
      const u32 tsym_goal = tp->symbol.offset;
      if (tsym_goal != 0 && tsym_goal < (u32)EE_MAIN_MEM_SIZE) {
        auto si = jak1::info(tp->symbol);
        const uintptr_t si_host = reinterpret_cast<uintptr_t>(si.c());
        if (si_host >= ee_lo && si_host + sizeof(jak1::SymInfo) <= ee_hi) {
          const u32 str_goal = si->str.offset;
          if (str_goal != 0 && str_goal < (u32)EE_MAIN_MEM_SIZE) {
            const char* s = si->str.c()->data();
            const uintptr_t s_host = reinterpret_cast<uintptr_t>(s);
            if (s_host >= ee_lo && s_host < ee_hi) {
              size_t maxn = (size_t)(ee_hi - s_host);
              if (maxn > sizeof(name_buf) - 1) maxn = sizeof(name_buf) - 1;
              size_t k = 0;
              for (; k < maxn && s[k] != '\0'; k++) name_buf[k] = s[k];
              name_buf[k] = '\0';
              type_name = name_buf;
            }
          }
        }
      }
    }
    for (int slot = 0; slot < (int)method_count; slot++) {
      // A36 — NEVER trap-fill method slot 13. jak1 reserves process-tree
      // method 13 ("process-tree-method-13", no implementation) as a DATA
      // slot: entity-info-lookup (entity-table.gc:199) caches the type's
      // entity-info there and treats NONZERO as a valid cache. A18's trap
      // pointer in slot 13 made the first birth! of every actor type read
      // the trap function as an entity-info — heap-size became the trap's
      // own code bytes, get-process's size request went huge-negative,
      // find-gap-by-size accepted the first gap unconditionally, and the
      // first post-kill birth wave allocated actors INSIDE live actors
      // (run-8: money-2679 built over windmill-sail-4 → wiped headers →
      // the A35 run-7 change-parent walk crash). Zero in slot 13 is
      // load-bearing game state, not a missing method.
      if (slot == 13) continue;
      u32* slot_p =
          reinterpret_cast<u32*>(mtable_lo + (uintptr_t)slot * 4);
      const u32 cur = *slot_p;
      // B1: emit the pre-patch state of this method slot on first sight or when
      // it changes, so B2 can build a per-(type,slot) bind timeline. fn is the
      // current slot value (0 = empty; trap_fn_goal once patched; otherwise a
      // real method ptr).
      if (s_klink_trace) {
        const u64 key = ((u64)expected_sym_goal << 8) | (u32)slot;
        auto it = s_method_last.find(key);
        if (it == s_method_last.end() || it->second != cur) {
          std::fprintf(stderr, "KLINKTRACE method type=%s slot=%d state=%s fn=0x%x\n",
                       type_name, slot, (cur == 0 ? "empty" : "bound"), (unsigned)cur);
          s_method_last[key] = cur;
        }
      }
      if (cur == 0) {
        *slot_p = trap_fn_goal;
        patched++;
      }
    }
  }
  return patched;
}
}  // anonymous namespace

// Cached trap GOAL fn ptr after first bind. Reset to 0 to force re-bind.
static u32 s_a18_trap_fn_goal = 0;

void klink_a18_install_method_zero_trap() {
  if (SymbolTable2.offset == 0) return;

  if (s_a18_trap_fn_goal == 0) {
    // First call: bind the trap sym and cache the GOAL fn ptr.
    auto fn = jak1::make_function_symbol_from_c(
        "__a18-method-zero-trap", (void*)a18_method_zero_trap);
    s_a18_trap_fn_goal = fn.offset;
    const int patched = walk_loaded_types_and_patch_a18(s_a18_trap_fn_goal);
    // Targeted dump: state of dead-pool-heap's slot 22 (= gap-location)
    // post-walk. This is the prime suspect for the A17→A18 boot ceiling
    // (process-spawn's `(gap-location this insert)` call inside
    // dead-pool-heap's `get-process` method). If slot 22 is now
    // s_a18_trap_fn_goal, we patched it. If still 0, the type didn't
    // satisfy our heuristic.
    auto dph_sym = jak1::find_symbol_from_c("dead-pool-heap");
    if (dph_sym.offset != 0 && dph_sym->value != 0) {
      Ptr<jak1::Type> dph_type(dph_sym->value);
      u32 slot22 = (dph_type->num_methods > 22)
                       ? dph_type->get_method(22).offset
                       : 0xDEAD;
      std::fprintf(stderr,
                   "A18-DIAG dead-pool-heap-state: sym_val=0x%x "
                   "num_methods=%u slot22=0x%x (trap=0x%x)\n",
                   (unsigned)dph_sym->value,
                   (unsigned)dph_type->num_methods,
                   (unsigned)slot22, (unsigned)s_a18_trap_fn_goal);
    } else {
      std::fprintf(stderr,
                   "A18-DIAG dead-pool-heap-state: sym not yet interned\n");
    }
    std::fprintf(stderr,
                 "A18-DIAG sym-bind-trace: bound __a18-method-zero-trap to "
                 "a18_method_zero_trap (GOAL fn ptr 0x%x), patched %d empty "
                 "method slots across loaded kernel types — "
                 "type-method-zero BLR-to-ee_base now lands at the trap "
                 "(which prints the named missing impl and returns 0)\n",
                 (unsigned)s_a18_trap_fn_goal, patched);
  } else {
    // Subsequent call: re-walk only (catches engine-CGO types loaded
    // after the kernel hook fired). Print only when we actually patched
    // something, to keep boot-log noise bounded.
    const int patched = walk_loaded_types_and_patch_a18(s_a18_trap_fn_goal);
    if (patched > 0) {
      std::fprintf(stderr,
                   "A18-DIAG sym-bind-trace: re-walk patched %d new empty "
                   "method slots (engine-CGO types just constructed)\n",
                   patched);
    }
  }
}

#if defined(__aarch64__)
// A18 attempt-4 — wrap the GOAL methods that `dead-pool-heap.get-process`
// calls so that X12 is preserved across each sub-call. goalc's arm64
// emitter holds `this` in X12 throughout get-process but its emitted save
// list for the BLR doesn't include X12 (X12 is caller-save in AAPCS, but
// the regalloc treats it as preserved). The wrapper is generated by
// `jak1::make_x12_preserve_wrapper_arm64(orig_fn_goal)` and saves X12 in
// its prologue, calls the wrapped function, restores X12, then returns.
//
// Methods wrapped (each is a sub-call inside get-process per gkernel.gc:974):
//   dead-pool-heap.method-24  (find-gap-by-size)  — called BEFORE the failing dispatch
//   dead-pool-heap.method-22  (gap-location)      — the failing dispatch site
//   dead-pool-heap.method-23  (find-gap)          — conditional after process.new
//   process.method-0          (new)               — process allocation after gap-location
//
// If the wrapper for slot-24 alone closes the immediate SIGILL, that
// names X12-clobber-across-find-gap-by-size as the exact regalloc bug.
// Wrapping the other three guards against the same bug recurring at
// the later sub-calls in get-process's body (which we can't see in the
// pre-fix disasm because boot dies before reaching them).
//
// Idempotent: cached wrappers per (type_goal, slot). Re-fires per CGO
// without re-allocating trampolines.
static u32 s_a18_x12_wrapped_count = 0;
struct X12WrapKey {
  u32 type_goal;
  u32 slot;
  bool operator==(const X12WrapKey& o) const {
    return type_goal == o.type_goal && slot == o.slot;
  }
};
struct X12WrapKeyHash {
  std::size_t operator()(const X12WrapKey& k) const noexcept {
    return ((std::size_t)k.type_goal << 8) ^ k.slot;
  }
};
static std::unordered_map<X12WrapKey, u32, X12WrapKeyHash> s_a18_x12_wrapper_cache;

static bool a18_wrap_method_slot_with_x12_preserve(const char* type_name,
                                                    u32 slot) {
  auto sym = jak1::find_symbol_from_c(type_name);
  if (sym.offset == 0 || sym->value == 0) {
    return false;
  }
  Ptr<jak1::Type> type_ptr(sym->value);
  if (type_ptr->num_methods <= slot) {
    return false;
  }
  u32 cur_fn = type_ptr->get_method(slot).offset;
  if (cur_fn == 0) {
    // empty slot — A18 trap walker handles those separately
    return false;
  }
  X12WrapKey key{sym->value, slot};
  auto it = s_a18_x12_wrapper_cache.find(key);
  if (it != s_a18_x12_wrapper_cache.end() && it->second == cur_fn) {
    // already wrapping the current value
    return false;
  }
  // Don't double-wrap our own wrapper. If cur_fn matches a previously
  // cached wrapper output, the slot is already wrapped — bail.
  for (const auto& kv : s_a18_x12_wrapper_cache) {
    if (kv.second == cur_fn) {
      return false;
    }
  }
  auto wrapper = jak1::make_x12_preserve_wrapper_arm64(cur_fn);
  if (wrapper.offset == 0) {
    return false;
  }
  type_ptr->get_method(slot).offset = wrapper.offset;
  s_a18_x12_wrapper_cache[key] = wrapper.offset;
  s_a18_x12_wrapped_count++;
  std::fprintf(stderr,
               "A18-DIAG x12-wrap: type=%s slot=%u orig_fn=0x%x wrapper=0x%x\n",
               type_name, slot, (unsigned)cur_fn, (unsigned)wrapper.offset);
  return true;
}

void klink_a18_install_x12_preserve_wrappers() {
  if (SymbolTable2.offset == 0) {
    return;
  }
  bool any = false;
  // Diagnostic: dump dead-pool-heap's full method table before wrapping
  // so we can verify which slot is which method.
  static bool s_dumped_dph_table = false;
  if (!s_dumped_dph_table) {
    auto dph_sym = jak1::find_symbol_from_c("dead-pool-heap");
    if (dph_sym.offset != 0 && dph_sym->value != 0) {
      Ptr<jak1::Type> dph_type(dph_sym->value);
      std::fprintf(stderr,
                   "A18-DIAG dph-method-table: sym_val=0x%x num_methods=%u",
                   (unsigned)dph_sym->value,
                   (unsigned)dph_type->num_methods);
      const u32 n = dph_type->num_methods;
      for (u32 i = 0; i < n; i++) {
        std::fprintf(stderr, " m%u=0x%x", i,
                     (unsigned)dph_type->get_method(i).offset);
      }
      std::fprintf(stderr, "\n");
      s_dumped_dph_table = true;
    }
  }
  // Wrap the methods that get-process calls in order. If any one slot's
  // wrapper alone doesn't get past 216, the same X12-clobber happens
  // across the NEXT sub-call; wrapping all of them ensures X12 survives
  // every BLR in the get-process body.
  any |= a18_wrap_method_slot_with_x12_preserve("dead-pool-heap", 24);
  any |= a18_wrap_method_slot_with_x12_preserve("dead-pool-heap", 22);
  any |= a18_wrap_method_slot_with_x12_preserve("dead-pool-heap", 23);
  any |= a18_wrap_method_slot_with_x12_preserve("process", 0);
  if (any) {
    std::fprintf(stderr,
                 "A18-DIAG x12-wrap: %u total methods wrapped to preserve X12 "
                 "(goalc-arm64 regalloc bug workaround for get-process)\n",
                 (unsigned)s_a18_x12_wrapped_count);
  }
}
#else
void klink_a18_install_x12_preserve_wrappers() {
  // No-op on non-arm64 hosts. The regalloc bug is arm64-specific
  // (X12 happens to be caller-save in AAPCS but x86 callers don't
  // emit X12 references at all).
}
#endif

/*!
 * Initialize the link control.
 * TODO: this hasn't been carefully checked for jak 2 differences.
 */
void link_control::jak1_jak2_begin(Ptr<uint8_t> object_file,
                                   const char* name,
                                   int32_t size,
                                   Ptr<kheapinfo> heap,
                                   uint32_t flags) {
  // A18 per-object re-walk: before each object's link begins, re-walk
  // every loaded Type's method table and patch empty slots to the trap.
  // This catches engine-CGO types created by the immediately-prior
  // object's top-level (e.g. `(deftype time-of-day-proc ...)` in
  // time-of-day-h.gc, whose method table is allocated post-`new_type`
  // with inherit-loop garbage at slots past parent's count). The walk
  // uses the strict 4-check heuristic (BASIC_OFFSET alignment +
  // type-tag at -4 == type-type + symbol field back-references the
  // walked slot + num_methods in [9, 128]), so non-type sym values
  // can't be corrupted. Idempotent + lightweight — O(NumSymbols)
  // per call. Only fires after the first install has bound the trap.
  if (SymbolTable2.offset != 0 && s_a18_trap_fn_goal != 0) {
    klink_a18_install_method_zero_trap();
  } else if (SymbolTable2.offset != 0) {
    // B1: when the A18 trap path is inactive (e.g. a desktop x86 boot, where
    // the method-zero trap is never installed) still emit the method-bind
    // timeline if OG_KLINK_TRACE is set. A trap_fn_goal of 0 makes the walk a
    // no-op on the method tables (empty slots are "patched" 0 -> 0), so this is
    // behaviour-neutral; it only drives the gated KLINKTRACE method output.
    static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);
    if (s_klink_trace) {
      walk_loaded_types_and_patch_a18(0);
    }
  }

  if (is_opengoal_object(object_file.c())) {
    // save data from call to begin
    m_object_data = object_file;
    kstrcpy(m_object_name, name);
    m_object_size = size;
    m_heap = heap;
    m_flags = flags;

    // initialize link control
    m_entry.offset = 0;
    m_heap_top = m_heap->top;
    m_keep_debug = false;
    m_opengoal = true;
    m_busy = true;

    if (link_debug_printfs) {
      char* goal_name = object_file.cast<char>().c();
      printf("link %s\n", m_object_name);
      printf("link_control::begin %c%c%c%c\n", goal_name[0], goal_name[1], goal_name[2],
             goal_name[3]);
    }

    // points to the beginning of the linking data
    m_link_block_ptr = object_file + BASIC_OFFSET;
    m_code_size = 0;
    m_code_start = object_file;
    m_state = 0;
    m_segment_process = 0;

    ObjectFileHeader* ofh = m_link_block_ptr.cast<ObjectFileHeader>().c();
    if (ofh->goal_version_major != versions::GOAL_VERSION_MAJOR) {
      fprintf(
          stderr,
          "VERSION ERROR: C Kernel built from GOAL %d.%d, but object file %s is from GOAL %d.%d\n",
          versions::GOAL_VERSION_MAJOR, versions::GOAL_VERSION_MINOR, name, ofh->goal_version_major,
          ofh->goal_version_minor);
      ASSERT(false);
    }
    if (link_debug_printfs) {
      printf("Object file header:\n");
      printf(" GOAL ver %d.%d obj %d len %d\n", ofh->goal_version_major, ofh->goal_version_minor,
             ofh->object_file_version, ofh->link_block_length);
      printf(" segment count %d\n", ofh->segment_count);
      for (int i = 0; i < N_SEG; i++) {
        printf(" seg %d link 0x%04x, 0x%04x data 0x%04x, 0x%04x\n", i, ofh->link_infos[i].offset,
               ofh->link_infos[i].size, ofh->code_infos[i].offset, ofh->code_infos[i].size);
      }
    }

    m_version = ofh->object_file_version;
    if (ofh->object_file_version < 4) {
      // three segment file

      // seek past the header
      m_object_data.offset += ofh->link_block_length;
      // todo, set m_code_size

      if (m_link_block_ptr.offset < m_heap->base.offset ||
          m_link_block_ptr.offset >= m_heap->top.offset) {
        // the link block is outside our heap, or in the top of our heap.  It's somebody else's
        // problem.
        if (link_debug_printfs) {
          printf("Link block somebody else's problem\n");
        }

        if (m_heap->base.offset <= m_object_data.offset &&    // above heap base
            m_object_data.offset < m_heap->top.offset &&      // less than heap top (not needed?)
            m_object_data.offset < m_heap->current.offset) {  // less than heap current
          if (link_debug_printfs) {
            printf("Code block in the heap, kicking it out for copy into heap\n");
          }
          m_heap->current = m_object_data;
        }
      } else {
        // in our heap, we need to move it so we can free up its space later on
        if (link_debug_printfs) {
          printf("Link block needs to be moved!\n");
        }

        // allocate space for a new one
        auto new_link_block = kmalloc(m_heap, ofh->link_block_length, KMALLOC_TOP, "link-block");
        auto old_link_block = m_link_block_ptr - BASIC_OFFSET;

        // copy it (was ultimate memcpy, but just use normal one to make it easier)
        memmove(new_link_block.c(), old_link_block.c(), ofh->link_block_length);
        m_link_block_ptr = new_link_block + BASIC_OFFSET;

        // if we can save some memory here
        if (old_link_block.offset < m_heap->current.offset) {
          if (link_debug_printfs) {
            printf("Kick out old link block\n");
          }
          m_heap->current = old_link_block;
        }
      }
    } else {
      ASSERT_MSG(false, "UNHANDLED OBJECT FILE VERSION");
    }

    if ((m_flags & LINK_FLAG_FORCE_DEBUG) && MasterDebug && !DiskBoot) {
      m_keep_debug = true;
    }
  } else {
    m_opengoal = false;
    // not an open goal object.
    if (link_debug_printfs) {
      printf("Linking GOAL style object %s\n", name);
    }

    // initialize
    m_object_data = object_file;
    kstrcpy(m_object_name, name);
    m_object_size = size;
    m_heap = heap;
    m_flags = flags;
    m_entry.offset = 0;
    m_heap_top = m_heap->top;
    m_keep_debug = false;
    m_link_block_ptr = object_file + BASIC_OFFSET;
    m_code_size = 0;
    m_code_start = object_file;
    m_state = 0;
    m_segment_process = 0;

    const auto* header = (LinkHeaderV2*)(m_link_block_ptr.c() - 4);

    m_version = header->version;
    if (header->version < 4) {
      // seek past header
      m_object_data.offset += header->length;
      m_code_size = m_object_size - header->length;
      if (m_link_block_ptr.offset < m_heap->base.offset ||
          m_link_block_ptr.offset >= m_heap->top.offset) {
        // the link block is outside our heap, or in the top of our heap.  It's somebody else's
        // problem.
        if (link_debug_printfs) {
          printf("Link block somebody else's problem\n");
        }

        if (m_heap->base.offset <= m_object_data.offset &&    // above heap base
            m_object_data.offset < m_heap->top.offset &&      // less than heap top (not needed?)
            m_object_data.offset < m_heap->current.offset) {  // less than heap current
          if (link_debug_printfs) {
            printf("Code block in the heap, kicking it out for copy into heap\n");
          }
          m_heap->current = m_object_data;
        }
      } else {
        // in our heap, we need to move it so we can free up its space later on
        if (link_debug_printfs) {
          printf("Link block needs to be moved!\n");
        }

        // allocate space for a new one
        auto new_link_block = kmalloc(m_heap, header->length, KMALLOC_TOP, "link-block");
        auto old_link_block = m_link_block_ptr - BASIC_OFFSET;

        // copy it (was ultimate memcpy)
        memmove(new_link_block.c(), old_link_block.c(), header->length);
        m_link_block_ptr = new_link_block + BASIC_OFFSET;

        // if we can save some memory here
        if (old_link_block.offset < m_heap->current.offset) {
          if (link_debug_printfs) {
            printf("Kick out old link block\n");
          }
          m_heap->current = old_link_block;
        }
      }

    } else {
      auto header_v4 = (const LinkHeaderV4*)header;
      auto old_object_data = m_object_data;
      m_link_block_ptr =
          old_object_data + header_v4->code_size + sizeof(LinkHeaderV4) + BASIC_OFFSET;
      m_object_data = old_object_data + sizeof(LinkHeaderV4);
      m_code_size = header_v4->code_size;
    }

    if ((m_flags & LINK_FLAG_FORCE_DEBUG) && MasterDebug && !DiskBoot) {
      m_keep_debug = true;
    }
  }
}

Ptr<u8> c_symlink2(Ptr<u8> objData, Ptr<u8> linkObj, Ptr<u8> relocTable) {
  u8* relocPtr = relocTable.c();
  Ptr<u8> objPtr = objData;

  do {
    u8 table_value = *relocPtr;
    u32 result = table_value;
    u8* next_reloc = relocPtr + 1;

    if (result & 3) {
      result = (relocPtr[1] << 8) | table_value;
      next_reloc = relocPtr + 2;
      if (result & 2) {
        result = (relocPtr[2] << 16) | result;
        next_reloc = relocPtr + 3;
        if (result & 1) {
          result = (relocPtr[3] << 24) | result;
          next_reloc = relocPtr + 4;
        }
      }
    }

    relocPtr = next_reloc;
    objPtr = objPtr + (result & 0xfffffffc);
    u32 objValue = *(objPtr.cast<u32>());
    if (objValue == 0xffffffff) {
      *(objPtr.cast<u32>()) = linkObj.offset;
    } else {
      // I don't think we should hit this ever.
      // if this is hit - there's a good chance something has overwritten the object file data
      // after linking has started.
      printf("val is 0x%x ptr %p\n", objValue, relocPtr - 1);
      ASSERT(false);
    }
  } while (*relocPtr);

  return make_ptr(relocPtr + 1);
}
