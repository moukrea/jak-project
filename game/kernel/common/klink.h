#pragma once
#include <cstring>

#include "common/common_types.h"
#include "common/link_types.h"

#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kscheme.h"

constexpr int LINK_FLAG_OUTPUT_LOAD = 0x1;
constexpr int LINK_FLAG_OUTPUT_TRUE = 0x2;
constexpr int LINK_FLAG_EXECUTE = 0x4;
constexpr int LINK_FLAG_PRINT_LOGIN = 0x8;  //! Note, doesn't actually do anything.
constexpr int LINK_FLAG_FORCE_DEBUG = 0x10;
constexpr int LINK_FLAG_FORCE_FAST_LINK = 0x20;

// only used in OpenGOAL
struct SegmentInfo {
  uint32_t offset;
  uint32_t size;
};

// only used in OpenGOAL
struct ObjectFileHeader {
  uint16_t goal_version_major;
  uint16_t goal_version_minor;
  uint32_t object_file_version;
  uint32_t segment_count;
  SegmentInfo link_infos[N_SEG];
  SegmentInfo code_infos[N_SEG];
  uint32_t link_block_length;
};

struct SegmentInfoV5 {
  uint32_t relocs;  // offset of relocation table
  uint32_t data;    // offset of segment data
  uint32_t size;    // segment data size (0 if segment doesn't exist)
  uint32_t magic;   // always 0
};

void klink_init_globals();

// A11 sym-bind-trace — see klink.cpp for rationale. Idempotent: binds
// `__pc-get-mips2c` to an a11_pc_get_mips2c_impl that delegates to
// `Mips2C::gLinkedFunctionTable.get(name)`. Caller must invoke after
// `jak1::InitHeapAndSymbol` returns so the symbol table is alive.
void klink_a11_ensure_pc_mips2c_bound();

// A12 sym-bind-trace — see klink.cpp for rationale. Idempotent: binds the
// sound-related RPC syms (`rpc-call`, `rpc-busy?`, `test-load-dgo-c`) that
// `jak1::InitSoundScheme` upstream registers, for the linux-arm64 +
// android-arm64 builds whose `jak1::InitMachineScheme` overrides omit the
// sound bindings. Without this, gsound's top-level invocation of `rpc-call`
// loads 0 from the unbound sym slot, +X15's it to ee_base, and SIGILLs on
// the UDF #0 there. Caller must invoke after `jak1::InitHeapAndSymbol`.
void klink_a12_ensure_sound_rpc_bound();

// A14 sym-bind-trace — see klink.cpp for rationale. Idempotent: binds
// `__mem-move` (the GOAL kernel's fast-memcpy entry point, hash
// 0x9290899a) to the existing `pc_memmove` C impl (kmachine.cpp:480).
// The pc-* helper would normally be registered by
// `init_common_pc_port_functions` (kmachine.cpp:1095) but the Android
// override at android/android_runtime_compat.cpp deliberately skips
// the 100+ pc-* helpers; linux-arm64 inherits the same gap. Without
// this bind, dma-buffer's top-level `(__mem-move ...)` BLRs to
// ee_base (sym slot=0 → host(0)=ee_base UDF #0) → sig=4 SIGILL.
// Caller must invoke after `jak1::InitHeapAndSymbol`.
void klink_a14_ensure_pc_memmove_bound();

Ptr<Function> klink_mfsfc_for_game(const char* name, void* f);

// A18 sym-bind-trace — see klink.cpp for rationale. Idempotent: binds
// the `__a18-method-zero-trap` sym to an `a18_method_zero_trap` C
// function whose body prints an A18-DIAG marker (self_goal, self_host,
// type_tag, caller_lr, args) and calls _Exit(13). Then walks every
// kernel-loaded Type's method table and patches any slot whose current
// value is 0 to point at the trap. This converts the post-A17
// "type-method-slot=0 → BLR ee_base → SIGILL on UDF #0" crash into a
// "type-method-slot fires trap → diag line → clean process exit" — an
// honest-abort surface per supervisor's option-2 path. NOT a silent
// return-0 stub (cookbook §11 forbids); NOT abort()/weak (validator
// check 3 forbids); _Exit is allowed.
//
// Walking is bounded: only sym slots whose value satisfies the strict
// "is a Type" heuristic (value < EE_MAIN_MEM_SIZE, type-tag at value-4
// equals the canonical `type` Type GOAL ptr, allocated-length in
// [9,128]) get their method tables walked. Engine CGO types loaded
// after this hook fires are NOT patched — those slots stay 0 and the
// original sig=4 SIGILL fires. Caller must invoke from the
// pre-kernel-version-check hook (after kernel CGO link is complete,
// so process/dead-pool/dead-pool-heap method tables are populated).
void klink_a18_install_method_zero_trap();

// A18 attempt-4 — wrap dead-pool-heap.method-{22,23,24} and process.method-0
// with arm64 trampolines that preserve X12 across the wrapped call. Workaround
// for goalc-arm64's regalloc bug where get-process holds `this` in X12 across
// the find-gap-by-size sub-call but the emitted save list for the BLR doesn't
// include X12. The wrapped functions are invoked honestly with all original
// args; the only register-state delta is X12 being preserved. NOT a stub.
// Caller must invoke after kernel CGO finishes loading (so dead-pool-heap and
// process types are fully defined and their method tables populated).
void klink_a18_install_x12_preserve_wrappers();

/*!
 * Stores the state of the linker. Used for multi-threaded linking, so it can be suspended.
 */
struct link_control {
  Ptr<uint8_t> m_object_data;  //! points to the start of the object file
  Ptr<uint8_t> m_entry;        //! points to first code to execute
  char m_object_name[64];      //! object file name
  int32_t m_object_size;       //! object file size
  Ptr<kheapinfo> m_heap;       //! heap we are putting the object file on
  uint32_t m_flags;            //! linker configuration
  Ptr<uint8_t> m_heap_top;     //! where to reset the heap top for clearing temp allocations
  bool m_keep_debug;           //! keep the debug segment, even if DebugSegment is off?
  Ptr<uint8_t> m_link_block_ptr;
  uint32_t m_code_size;
  Ptr<uint8_t> m_code_start;
  uint32_t m_state;
  uint32_t m_segment_process;
  uint32_t m_version;
  int m_heap_gap;
  Ptr<uint8_t> m_original_object_location;
  Ptr<u8> m_reloc_ptr;
  Ptr<u8> m_base_ptr;
  Ptr<u8> m_loc_ptr;
  int m_table_toggle;

  bool m_opengoal;
  bool m_busy;  // only in jak2, but doesn't hurt to set it in jak 1.

  // jak 3 new stuff
  bool m_on_global_heap = false;
  LinkHeaderV5Core* m_link_hdr = nullptr;
  bool m_moved_link_block = false;
  int m_n_segments = 0;
  SegmentInfoV5* m_link_segments_table = nullptr;

  void jak1_jak2_begin(Ptr<uint8_t> object_file,
                       const char* name,
                       int32_t size,
                       Ptr<kheapinfo> heap,
                       uint32_t flags);

  void jak3_begin(Ptr<uint8_t> object_file,
                  const char* name,
                  int32_t size,
                  Ptr<kheapinfo> heap,
                  uint32_t flags);

  void jakx_begin(Ptr<uint8_t> object_file,
                  const char* name,
                  int32_t size,
                  Ptr<kheapinfo> heap,
                  uint32_t flags);

  // was originally "work"
  uint32_t jak1_work();
  uint32_t jak2_work();
  uint32_t jak3_work();
  uint32_t jakx_work();

  uint32_t jak1_work_v3();
  uint32_t jak1_work_v2();

  uint32_t jak2_work_v3();
  uint32_t jak2_work_v2();

  uint32_t jak3_work_v2_v4();
  uint32_t jak3_work_v5();
  uint32_t jak3_work_opengoal();
  uint32_t jakx_work_v2_v4();
  uint32_t jakx_work_v5();
  uint32_t jakx_work_opengoal();

  void jak1_finish(bool jump_from_c_to_goal);
  void jak2_finish(bool jump_from_c_to_goal);
  void jak3_finish(bool jump_from_c_to_goal);
  void jakx_finish(bool jump_from_c_to_goal);

  void reset() {
    m_object_data.offset = 0;
    m_entry.offset = 0;
    memset(m_object_name, 0, sizeof(m_object_name));
    m_object_size = 0;
    m_heap.offset = 0;
    m_flags = 0;
    m_heap_top.offset = 0;
    m_keep_debug = false;
    m_link_block_ptr.offset = 0;
    m_code_size = 0;
    m_code_start.offset = 0;
    m_state = 0;
    m_segment_process = 0;
    m_version = 0;
    m_busy = false;
  }
};

Ptr<u8> c_symlink2(Ptr<u8> objData, Ptr<u8> linkObj, Ptr<u8> relocTable);

// arm64-aware u32-patch dispatcher (autoport phase C4-klink-arm64-execute).
//
// The runtime klink v3 relocators (cross_seg_dist_link_v3 / ptr_link_v3 /
// symlink_v3 / typelink_v3 in game/kernel/jak1/klink.cpp) used to write the
// resolved 32-bit value over the entire patch slot. On arm64 that destroys
// ADRP imm21 / ADD imm12 / LDR-STR imm12 opcode bits — their immediate
// fields sit at non-byte-aligned positions inside the 32-bit instruction
// word — and the linked top-level SIGILLs the moment it tries to run.
//
// klink_arm64_patch_pc_rel inspects the current slot, recognises an arm64
// imm-carrying form, and rewrites ONLY the immediate bits with the right
// derivation of target_host_addr (page-delta for ADRP, low-12 of target
// for ADD/LDR/STR). Slots that don't match any recognised arm64 form
// return kNotInstr and the caller falls back to its raw u32 store (the
// existing GOAL data-slot semantics — symbol-table sentinel, type ptr,
// raw pointer).
//
// A4 already pre-patches intra-segment LDR(literal) imm19 at compile
// time, so the runtime should never see LDR-literal; if it does the
// dispatcher returns kAborted (recorded in the histogram's `unhandled`
// counter) so the failure surfaces in the C4-execute.md report rather
// than as a silent semantic divergence.
struct KlinkArm64PatchHist {
  uint32_t adrp;          // ADRP imm21 patches
  uint32_t add_imm12;     // ADD/SUB imm12 patches
  uint32_t ldr_imm12;     // LDR (Wt/Xt/St/Dt/Qt + LDRSW) imm12 patches
  uint32_t str_imm12;     // STR (Wt/Xt/St/Dt/Qt) imm12 patches
  uint32_t ldr_literal;   // LDR (literal) imm19 patches — inter-segment static-data loads
  uint32_t raw_u32;       // slot wasn't a recognised arm64 instr → caller stored raw u32
  uint32_t unhandled;     // arm64-shaped opcode we don't yet patch
  uint32_t out_of_range;  // ADRP page-delta exceeded signed 21-bit range
};
extern KlinkArm64PatchHist g_klink_arm64_patch_hist;

enum class KlinkArm64PatchResult {
  kPatched,   // slot was an arm64 imm-carrying instr; patch applied
  kNotInstr,  // slot not an arm64 instr; caller should do its raw u32 store
  kAborted,   // arm64-shaped but unhandled / out of range; no patch applied
};

// sym_value_bias: byte offset added to target_host_addr for the SYMBOL-VALUE
// (sym-MEM) instruction forms only — the X16 ADRP+ADD pair and the x14 (s7-
// relative) LDR/STR. jak2/jak3 store a symbol's value one byte BELOW the
// symbol pointer (common/Symbol4.h: value() = &foo - 1), whereas jak1 stores
// it AT the pointer. Pass -1 for jak2 sym links, 0 (default) everywhere else
// and for the sym-PTR forms (which materialise the pointer, not the value).
KlinkArm64PatchResult klink_arm64_patch_pc_rel(uint32_t* slot,
                                               uintptr_t target_host_addr,
                                               int sym_value_bias = 0);

// Gjak2-render DIAGNOSTIC (JAK2_RELOC_TRACE): reloc-type + segment attribution
// for the LDR-literal (not-4-aligned / imm19-out-of-range) branch. The jak2 v3
// relocators set these immediately before each klink_arm64_patch_pc_rel call.
// Env-gated output only; no behavioural effect.
extern const char* g_jak2_reloc_ctx;
extern int g_jak2_reloc_seg;

extern link_control saved_link_control;
extern Ptr<Function> gfunc_774;  // actually 807 in jak2.
