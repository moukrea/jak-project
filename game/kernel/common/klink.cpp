#include "klink.h"

#include <cstdio>

#include "common/goal_constants.h"
#include "common/symbols.h"

#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/mips2c/mips2c_table.h"

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
                                               uintptr_t target_host_addr) {
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
    const uintptr_t this_pc = reinterpret_cast<uintptr_t>(slot);
    const int64_t target_page = static_cast<int64_t>(target_host_addr >> 12);
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
    const uint32_t imm12 = static_cast<uint32_t>(target_host_addr & 0xFFFu);
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
      const int64_t s7_rel = static_cast<int64_t>(target_host_addr) -
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
    if ((pc_rel & 3) != 0) {
      g_klink_arm64_patch_hist.out_of_range++;
      printf("klink-arm64: LDR-literal pc-rel %lld not 4-aligned at %p\n",
             (long long)pc_rel, (void*)slot);
      return KlinkArm64PatchResult::kAborted;
    }
    const int64_t imm19 = pc_rel / 4;
    if (imm19 < -(int64_t(1) << 18) || imm19 >= (int64_t(1) << 18)) {
      g_klink_arm64_patch_hist.out_of_range++;
      printf("klink-arm64: LDR-literal imm19 %lld out of range at %p\n",
             (long long)imm19, (void*)slot);
      return KlinkArm64PatchResult::kAborted;
    }
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
  const char* n = Ptr<String>(name).c()->data();
  return Mips2C::gLinkedFunctionTable.get(n);
}
}  // namespace

void klink_a11_ensure_pc_mips2c_bound() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;  // symbol table not yet ready

  auto fn = jak1::make_function_symbol_from_c("__pc-get-mips2c",
                                              (void*)a11_pc_get_mips2c_impl);
  s_bound = true;
  std::fprintf(stderr,
               "A11-DIAG sym-bind-trace: bound __pc-get-mips2c to "
               "a11_pc_get_mips2c_impl (function GOAL ptr 0x%x)\n",
               (unsigned)fn.offset);
}

/*!
 * Initialize the link control.
 * TODO: this hasn't been carefully checked for jak 2 differences.
 */
void link_control::jak1_jak2_begin(Ptr<uint8_t> object_file,
                                   const char* name,
                                   int32_t size,
                                   Ptr<kheapinfo> heap,
                                   uint32_t flags) {
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
