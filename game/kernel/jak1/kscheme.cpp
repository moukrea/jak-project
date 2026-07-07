#include "kscheme.h"

#include <cstring>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/symbols.h"
#include "common/util/Timer.h"

#include <cstdio>  // Gjak2-render JAK2-BADPTR-ALLOC tripwire (fprintf/stderr)

// Gjak2-render JAK1-ON-JAK2 call-site enumerator: log when jak1 symbol-table
// functions fire during a jak2 boot (should be ZERO). Instrumentation only.
#include <atomic>
#include <dlfcn.h>

#include "common/versions/versions.h"  // GameVersion

#include "game/runtime.h"  // g_game_version

#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/runtime_trace.h"
#include "game/kernel/jak1/fileio.h"
#include "game/kernel/jak1/kdgo.h"
#include "game/kernel/jak1/klink.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kmachine.h"
#include "game/kernel/jak1/kprint.h"
#include "game/mips2c/mips2c_table.h"

using namespace jak1_symbols;

// Phase E1 (autoport): optional Android-installed callback fired between
// kernel-CGO load and the version check inside InitHeapAndSymbol. Stays
// null on desktop builds (no installer); the Android compat layer
// (android/android_runtime_compat.cpp) installs a hook that pre-
// populates *kernel-version* when the gkernel top-level was skipped by
// the goalc-arm64 off-register emitter dodge. See the use site below.
extern "C" void (*g_jak1_pre_kernel_version_check_hook)(void) = nullptr;

namespace jak1 {
// where to put a new symbol for the most recently searched for symbol that wasn't found
u32 symbol_slot;

void kscheme_init_globals() {
  symbol_slot = 0;
}

// Gjak2-render JAK1-ON-JAK2 enumerator. Fires ONLY when the running game is
// Jak2 (a correct jak2 boot must never call these jak1 symbol-table
// functions). Bounded to ~40 total log lines across all sites via a shared
// atomic counter so it can't spam-loop. Symbolizes the caller via dladdr.
// Instrumentation only; no behavior change; never fires for a jak1 run.
static std::atomic<int> g_jak1_on_jak2_log_count{0};
static inline void jak1_on_jak2_guard_log(const char* fn, void* ra) {
  if (g_game_version != GameVersion::Jak2) {
    return;
  }
  if (g_jak1_on_jak2_log_count.fetch_add(1) >= 40) {
    return;
  }
  Dl_info _di;
  const char* _nm = (dladdr(ra, &_di) && _di.dli_sname) ? _di.dli_sname : "?";
  fprintf(stderr, "JAK1-ON-JAK2 fn=%s caller=%s ra=%p\n", fn, _nm, ra);
}
#define JAK1_ON_JAK2_GUARD_LOG() \
  jak1_on_jak2_guard_log(__func__, __builtin_return_address(0))

/*!
 * New method for types which cannot have "new" used on them.
 * Prints an error to stdout and returns false.
 */
u64 new_illegal(u32 allocation, u32 type) {
  (void)allocation;
  MsgErr("dkernel: illegal attempt to call new method of static object type %s\n",
         info(Ptr<Type>(type)->symbol)->str->data());
  return s7.offset;
}

/*!
 * Allocate memory from the specified heap. If symbol is 'process, does a process allocation.
 * If symbol is 'scratch, does a scratch allocation (this is not used).
 *
 * If it's not a heap, treat it as a stack allocation and just memset it to zero.
 * Type is only used to print a debug message if the allocation fails, so it can be null or not
 * completely defined.
 *
 * The pp argument is added.  It contains the current process.  If it is unknown, it is set to
 * UNKNOWN_PROCESS (UINT32_MAX).
 */
u64 alloc_from_heap(u32 heapSymbol, u32 type, s32 size, u32 pp) {
  using namespace jak1_symbols;
  // Gjak2-render JAK2-BADPTR-ALLOC tripwire (ALWAYS ON, log-only, harmless to
  // jak1). Shared read/use-side tripwire: a real GOAL type pointer is always
  // < EE_MAIN_MEM_SIZE (0x8000000); a `type` >= that carries garbage in
  // bits[16:31] and would SIGSEGV on the Ptr<Type> deref below. jak1 behavior
  // is otherwise unchanged. Cheap: single unsigned compare on the happy path.
  if (type != 0 && (u32)type >= (u32)EE_MAIN_MEM_SIZE) {
    std::fprintf(stderr, "JAK2-BADPTR-ALLOC type=0x%x size=%d obj=%s caller=%p\n",
                 type, size, g_gk_current_link_object, __builtin_return_address(0));
  }
  ASSERT(size > 0);

  // align to 16 bytes (part one)
  s32 alignedSize = size + 0xf;

  // huh?
  if (alignedSize < 0)
    alignedSize += 0xf;

  // finish aligning.
  alignedSize = (alignedSize >> 4) << 4;

  u32 heapOffset = heapSymbol - s7.offset;

  if (heapOffset == FIX_SYM_GLOBAL_HEAP || heapOffset == FIX_SYM_DEBUG_HEAP ||
      heapOffset == FIX_SYM_PROCESS_LEVEL_HEAP || heapOffset == FIX_SYM_LOADING_LEVEL) {
    // it's a kheap, so just kmalloc.

    if (!type) {  // no type given, just call it a global-object
      return kmalloc(*Ptr<Ptr<kheapinfo>>(heapSymbol), size, KMALLOC_MEMSET, "global-object")
          .offset;
    }

    Ptr<Type> typ(type);
    if (!typ->symbol.offset) {  // type doesn't have a symbol, just call it a global-object
      return kmalloc(*Ptr<Ptr<kheapinfo>>(heapSymbol), size, KMALLOC_MEMSET, "global-object")
          .offset;
    }

    Ptr<String> gstr = info(typ->symbol)->str;
    if (!gstr->len) {  // string has nothing in it.
      return kmalloc(*Ptr<Ptr<kheapinfo>>(heapSymbol), size, KMALLOC_MEMSET, "global-object")
          .offset;
    }

    return kmalloc(*Ptr<Ptr<kheapinfo>>(heapSymbol), size, KMALLOC_MEMSET, gstr->data()).offset;
  } else if (heapOffset == FIX_SYM_PROCESS_TYPE) {
    if (pp == UNKNOWN_PP) {
      // added
      MsgErr(
          "Attempted to do a process allocation, but pp was UNKNOWN_PP. This is not yet supported "
          "by kscheme.cpp.\n");
      ASSERT(false);
    }

    if (pp == 0) {
      // added
      MsgErr("Attempted to do a process allocation, but pp was 0.\n");
      ASSERT(false);
    }

    // allocate on current process heap
    u32 start = *Ptr<u32>(pp + 0x4c + 8);
    u32 heapEnd = *Ptr<u32>(pp + 0x4c + 4);
    u32 allocEnd = start + alignedSize;

    // there's room, bump allocate
    if (allocEnd < heapEnd) {
      *Ptr<u32>(pp + 0x4c + 8) = allocEnd;
      memset(Ptr<u8>(start).c(), 0, (size_t)alignedSize);
      return start;
    } else {
      MsgErr("kmalloc: !alloc mem in heap for #<process @ #x%x> (%d bytes)\n", pp, alignedSize);
      return 0;
    }
  } else if (heapOffset == FIX_SYM_SCRATCH) {
    ASSERT(false);  // nyi, I think unused.
    return 0;
  } else {
    memset(Ptr<u8>(heapSymbol).c(), 0, (size_t)alignedSize);  // treat it as a stack address
    return heapSymbol;
  }
}

/*!
 * Allocate untyped memory.
 */
u64 alloc_heap_memory(u32 heap, u32 size) {
  // should never happen on process heap
  return alloc_from_heap(heap, 0, size, UNKNOWN_PP);
}

/*!
 * Allocate memory and add type tag for an object.
 * For allocating basics.
 * Called from GOAL.
 */
u64 alloc_heap_object(u32 heap, u32 type, u32 size, u32 pp) {
  auto mem = alloc_from_heap(heap, type, size, pp);
  if (!mem) {
    return 0;
  }

  *Ptr<u32>(mem) = type;
  return mem + BASIC_OFFSET;
}

/*!
 * Allocate a structure and get the structure size from the type.
 */
u64 new_structure(u32 heap, u32 type) {
  // should never happen on process heap
  return alloc_from_heap(heap, type, Ptr<Type>(type)->allocated_size, UNKNOWN_PP);
}

/*!
 * Allocate a structure with a dynamic size
 */
u64 new_dynamic_structure(u32 heap_symbol, u32 type, u32 size) {
  // should never happen on process heap
  return alloc_from_heap(heap_symbol, type, size, UNKNOWN_PP);
}

/*!
 * Delete a structure.  Not supported, as it uses kfree, which doesn't do anything.
 */
void delete_structure(u32 s) {
  kfree(Ptr<u8>(s));
}

/*!
 * Allocate a basic of fixed size.
 */
u64 new_basic(u32 heap, u32 type, u32 /*size*/, u32 pp) {
  return alloc_heap_object(heap, type, Ptr<Type>(type)->allocated_size, pp);
}

/*!
 * Delete a basic.  Not supported, as it uses kfree.
 */
void delete_basic(u32 s) {
  // note that the game has a bug here and has s as a uint* and does -4 which is actually a
  // 16-byte offset. Luckily kfree does nothing so there's no harm done.  But it's a good indication
  // that the "freeing memory" feature never made it very far in development. This bug exists in
  // Jak 3 as well.
  kfree(Ptr<u8>(s - BASIC_OFFSET * 4));  // replicate the bug
}

/*!
 * Allocate a new pair and set its car and cdr.
 */
u64 new_pair(u32 heap, u32 type, u32 car, u32 cdr) {
  auto mem = alloc_from_heap(heap, type, Ptr<Type>(type)->allocated_size, UNKNOWN_PP);
  if (!mem) {
    return 0;
  }

  u32* m = Ptr<u32>(mem).c();
  m[0] = car;
  m[1] = cdr;
  return mem + PAIR_OFFSET;
}

/*!
 * Delete a pair.  BUG
 */
void delete_pair(u32 s) {
  // the -8 should be a -2, but s is likely a u32* in the code.
  kfree(Ptr<u8>(s - 8));
}

/*!
 * Make an empty string of given size.
 * Allocates from the global heap.
 */
u64 make_string(u32 size) {
  using namespace jak1_symbols;
  auto mem_size = size + 1;  // null
  if (mem_size < 8) {
    mem_size = 8;  // min size of string
  }

  // total size is mem_size (chars + null term), plus basic_offset (type tag) + 4 (string size)
  auto mem = alloc_heap_object((s7 + FIX_SYM_GLOBAL_HEAP).offset, *(s7 + FIX_SYM_STRING_TYPE),
                               mem_size + BASIC_OFFSET + sizeof(uint32_t), UNKNOWN_PP);

  // set the string size field.
  if (mem) {
    *Ptr<u32>(mem) = size;
  }
  return mem;
}

/*!
 * Convert a C string to a GOAL string.
 * Allocates from the global heap and copies the string data.
 */
u64 make_string_from_c(const char* c_str) {
  JAK1_ON_JAK2_GUARD_LOG();
  auto str_size = strlen(c_str);
  auto mem_size = str_size + 1;
  if (mem_size < 8) {
    mem_size = 8;
  }

  auto mem = alloc_heap_object((s7 + FIX_SYM_GLOBAL_HEAP).offset, *(s7 + FIX_SYM_STRING_TYPE),
                               mem_size + BASIC_OFFSET + 4, UNKNOWN_PP);
  // there's no check for failed allocation here!

  // string size field
  *Ptr<u32>(mem) = str_size;

  // rest is chars
  kstrcpy(Ptr<char>(mem + 4).c(), c_str);
  return mem;
}

extern "C" {
#ifndef __aarch64__
#ifdef __APPLE__
void _arg_call_systemv() asm("_arg_call_systemv");
#else
void _arg_call_systemv();
#endif
#else
#ifdef __APPLE__
void _arg_call_arm64() asm("_arg_call_arm64");
#else
void _arg_call_arm64();
#endif
#endif
}

/*!
 * This creates an OpenGOAL function from a C++ function. Only 6 arguments can be accepted.
 * But calling this function is fast. It used to be really fast but wrong.
 */
Ptr<Function> make_function_from_c_systemv(void* func, bool arg3_is_pp) {
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x40, UNKNOWN_PP));
  auto f = (uint64_t)func;
  auto target_function = (u8*)&f;
#ifndef __aarch64__
  auto trampoline_function_addr = _arg_call_systemv;
#else
  auto trampoline_function_addr = _arg_call_arm64;
#endif
  auto trampoline = (u8*)&trampoline_function_addr;
  // TODO - x86 code still being emitted below

  // movabs rax, target_function
  int offset = 0;
  mem.c()[offset++] = 0x48;
  mem.c()[offset++] = 0xb8;
  for (int i = 0; i < 8; i++) {
    mem.c()[offset++] = target_function[i];
  }

  // push rax
  mem.c()[offset++] = 0x50;

  // movabs rax, trampoline
  mem.c()[offset++] = 0x48;
  mem.c()[offset++] = 0xb8;
  for (int i = 0; i < 8; i++) {
    mem.c()[offset++] = trampoline[i];
  }

  if (arg3_is_pp) {
    // mov rcx, r13. Puts pp in the third argument.
    mem.c()[offset++] = 0x4c;
    mem.c()[offset++] = 0x89;
    mem.c()[offset++] = 0xe9;
  }

  // jmp rax
  mem.c()[offset++] = 0xff;
  mem.c()[offset++] = 0xe0;
  // the asm function's ret will return to the caller of this (GOAL code) directlyz.

  // CacheFlush(mem, 0x34);

  return mem.cast<Function>();
}

/*!
 * Create a GOAL function from a C function. This doesn't export it as a global function, it just
 * creates a function object on the global heap.
 *
 * This creates a simple trampoline function which jumps to the C function and reorders the
 * arguments to be correct for Windows.
 */
Ptr<Function> make_function_from_c_win32(void* func, bool arg3_is_pp) {
  // allocate a function object on the global heap
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x80, UNKNOWN_PP));
  auto f = (uint64_t)func;
  auto fp = (u8*)&f;

  int i = 0;
  // we will put the function address in RAX with a movabs rax, imm8
  mem.c()[i++] = 0x48;
  mem.c()[i++] = 0xb8;
  for (int j = 0; j < 8; j++) {
    mem.c()[i++] = fp[j];
  }

  /*
    push rdi
    push rsi
    push rdx
    push rcx
    pop r9
    pop r8
    pop rdx
    pop rcx
    push r10
    push r11
    sub rsp, 40
   */
  for (auto x : {0x57, 0x56, 0x52, 0x51, 0x41, 0x59, 0x41, 0x58, 0x5A, 0x59, 0x41, 0x52, 0x41, 0x53,
                 0x48, 0x83, 0xEC, 0x28}) {
    mem.c()[i++] = x;
  }

  if (arg3_is_pp) {
    // mov r9, r13. Puts pp in the third argument.
    mem.c()[i++] = 0x4d;
    mem.c()[i++] = 0x89;
    mem.c()[i++] = 0xe9;
  }

  /*
    call rax
    add rsp, 40
    pop r11
    pop r10
    ret
   */
  for (auto x : {0xFF, 0xD0, 0x48, 0x83, 0xC4, 0x28, 0x41, 0x5B, 0x41, 0x5A, 0xC3}) {
    mem.c()[i++] = x;
  }

  // CacheFlush(mem, 0x34);

  return mem.cast<Function>();
}

extern "C" {
#ifndef __aarch64__
#ifdef __APPLE__
void _arg_call_systemv() asm("_arg_call_systemv");
void _stack_call_systemv() asm("_stack_call_systemv");
void _stack_call_win32() asm("_stack_call_win32");
#else
void _arg_call_systemv();
void _stack_call_systemv();
void _stack_call_win32();
#endif
#else
#if defined(__APPLE__)
void _arg_call_arm64() asm("_arg_call_arm64");
void _stack_call_arm64() asm("_stack_call_arm64");
#else
void _arg_call_arm64();
void _stack_call_arm64();
#endif
#endif
}

Ptr<Function> make_stack_arg_function_from_c_systemv(void* func) {
  // allocate a function object on the global heap
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x40, UNKNOWN_PP));
  auto f = (uint64_t)func;
  auto target_function = (u8*)&f;
#ifndef __aarch64__
  auto trampoline_function_addr = _stack_call_systemv;
#else
  auto trampoline_function_addr = _stack_call_arm64;
#endif
  auto trampoline = (u8*)&trampoline_function_addr;

  // movabs rax, target_function
  int offset = 0;
  mem.c()[offset++] = 0x48;
  mem.c()[offset++] = 0xb8;
  for (int i = 0; i < 8; i++) {
    mem.c()[offset++] = target_function[i];
  }

  // push rax
  mem.c()[offset++] = 0x50;

  // movabs rax, trampoline
  mem.c()[offset++] = 0x48;
  mem.c()[offset++] = 0xb8;
  for (int i = 0; i < 8; i++) {
    mem.c()[offset++] = trampoline[i];
  }

  // jmp rax
  mem.c()[offset++] = 0xff;
  mem.c()[offset++] = 0xe0;

  // CacheFlush(mem, 0x34);

  return mem.cast<Function>();
}

#ifdef _WIN32
/*!
 * Create a GOAL function from a C function.  This calls a windows function, but doesn't scramble
 * the argument order.  It's supposed to be used with _format_win32 which assumes GOAL order.
 */
Ptr<Function> make_stack_arg_function_from_c_win32(void* func) {
  // allocate a function object on the global heap
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x80, UNKNOWN_PP));
  auto f = (uint64_t)func;
  auto fp = (u8*)&f;
  auto trampoline_function_addr = _stack_call_win32;
  auto trampoline = (u8*)&trampoline_function_addr;

  int i = 0;
  // we will put the function address in RAX with a movabs rax, imm8
  mem.c()[i++] = 0x48;
  mem.c()[i++] = 0xb8;
  for (int j = 0; j < 8; j++) {
    mem.c()[i++] = fp[j];
  }

  // push rax
  mem.c()[i++] = 0x50;

  // we will put the function address in RAX with a movabs rax, imm8
  mem.c()[i++] = 0x48;
  mem.c()[i++] = 0xb8;
  for (int j = 0; j < 8; j++) {
    mem.c()[i++] = trampoline[j];
  }

  /*
   * jmp rax
   */
  for (auto x : {0xFF, 0xE0}) {
    mem.c()[i++] = x;
  }

  return mem.cast<Function>();
}
#endif

#ifdef __aarch64__
// A6 (autoport) — arm64-aware GOAL→C FFI trampoline emission.
//
// The systemv variant above writes x86_64 machine code (movabs/push/jmp) into
// a heap-allocated function object. The pre-A6 builds got away with this on
// arm64 only because the D4-era runtime dodge short-circuited call_goal
// before the GOAL bytecode could ever BLR to the trampoline. A6 removes
// that dodge; gcommon's top-level executes for real and the first
// defmethod-driven FFI call (method-set!) jumps straight into these x86
// bytes — SIGILL inside the heap-allocated trampoline.
//
// The arm64 trampoline emits a self-contained sequence:
//   - save x29 (FP), x30 (LR back to GOAL caller) on the stack
//   - save x13/x14/x15 (R13/R14/R15 — GOAL's pp / sym-table-host / EE-base
//     ABI registers, all caller-saved per AAPCS but GOAL relies on them
//     surviving across nested calls — _arg_call_arm64 would otherwise have
//     done this, but its current shape doesn't actually preserve x29/x30
//     correctly so we open-code the save/restore here)
//   - optional `mov x2, x13` when arg3_is_pp (mirrors x86's `mov rcx, r13`)
//   - movz/movk chain to materialise the 64-bit target_function address in
//     x16 (4 instructions — covers any 64-bit host VA, including Android's
//     0x720_xxxx_xxxx libgk.so range)
//   - blr x16  → into the real C function
//   - restore the saved regs in reverse order
//   - ret      → back to GOAL caller via the preserved x30
//
// The heap-allocated object is sized 0x80 bytes (matching the win32 variant)
// to leave headroom for the longest emitted sequence (arg3_is_pp adds one
// instruction). Each instruction is 4 bytes (AArch64 fixed-width); we write
// them as little-endian u32s.
inline void write_u32_le(u8* dst, uint32_t value) {
  dst[0] = static_cast<u8>(value & 0xFFu);
  dst[1] = static_cast<u8>((value >> 8) & 0xFFu);
  dst[2] = static_cast<u8>((value >> 16) & 0xFFu);
  dst[3] = static_cast<u8>((value >> 24) & 0xFFu);
}

inline uint32_t arm64_movz_x(unsigned rd, uint16_t imm16, unsigned shift_quartile) {
  // MOVZ Xd, #imm16{, LSL #(shift_quartile*16)}
  // sf=1, opc=10, fixed 100101, hw=shift_quartile, imm16, Rd
  return 0xD2800000u | (static_cast<uint32_t>(shift_quartile) << 21) |
         (static_cast<uint32_t>(imm16) << 5) | (rd & 0x1Fu);
}

inline uint32_t arm64_movk_x(unsigned rd, uint16_t imm16, unsigned shift_quartile) {
  // MOVK Xd, #imm16, LSL #(shift_quartile*16)
  // sf=1, opc=11, fixed 100101, hw=shift_quartile, imm16, Rd
  return 0xF2800000u | (static_cast<uint32_t>(shift_quartile) << 21) |
         (static_cast<uint32_t>(imm16) << 5) | (rd & 0x1Fu);
}

inline uint32_t arm64_blr(unsigned rn) {
  return 0xD63F0000u | ((rn & 0x1Fu) << 5);
}

inline uint32_t arm64_ret_x30() {
  return 0xD65F03C0u;
}

// A24 — emit the 5-instruction post-LDP X30 stack-range check, mirroring
// goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64's epilogue
// tracer and game/kernel/asm_funcs_arm64.s's a24_x30_stack_range_check
// macro. The inline trampolines below (make_function_from_c_arm64 and
// friends) all emit an LDP X29, X30 + RET tail; this helper inserts
// the check between them so a corrupted X30 fires UDF #0x1EF0 BEFORE
// the RET propagates the bad LR to PC. See the linked comment block in
// CodeGenerator.cpp for the threshold (0x07000000), the signed-LT vs
// unsigned-LO subtlety (return-to-C-binary has X30 < X15 → wraps), and
// the SIGILL handler decoder's GK-DIAG A24-DIAG output shape.
//
// X16, X17 are AAPCS intra-procedure call scratch (IP0/IP1) and clobberable
// here — the wrapping caller doesn't expect them to be preserved across
// the trampoline.
//
// Always-on (no env gate at this layer): these trampolines are emitted
// once at boot during type-system init, so a runtime check would cost a
// std::getenv() per make_function_from_c call (~50 of them in jak1
// init). Keeping it always-on means the GK binary always traps on
// corrupted X30 at trampoline exit, which is exactly the diagnostic
// regime A24 is in.
template <typename EmitFn>
inline void arm64_emit_x30_stack_range_check(EmitFn emit) {
  emit(0xCB0F03D1u);  // SUB  X17, X30, X15  (X17 = X30 - X15, signed)
  emit(0xD2A0E010u);  // MOVZ X16, #0x0700, LSL #16  (X16 = 0x07000000)
  emit(0xEB10023Fu);  // CMP  X17, X16
  emit(0x5400004Bu);  // B.LT +8  (signed less than → skip UDF)
  emit(0x00001EF0u);  // UDF  #0x1EF0  (A24 epilogue-X30-stack trap tag)
}

inline uint32_t arm64_stp_x_preindex(unsigned rt, unsigned rt2, unsigned rn, int simm7_bytes) {
  // STP Xt, Xt2, [Xn, #simm7]!  -- pre-indexed, scaled by 8
  uint32_t imm7 = static_cast<uint32_t>(simm7_bytes / 8) & 0x7Fu;
  return 0xA9800000u | (imm7 << 15) | ((rt2 & 0x1Fu) << 10) | ((rn & 0x1Fu) << 5) |
         (rt & 0x1Fu);
}

inline uint32_t arm64_ldp_x_postindex(unsigned rt, unsigned rt2, unsigned rn, int simm7_bytes) {
  // LDP Xt, Xt2, [Xn], #simm7  -- post-indexed, scaled by 8
  uint32_t imm7 = static_cast<uint32_t>(simm7_bytes / 8) & 0x7Fu;
  return 0xA8C00000u | (imm7 << 15) | ((rt2 & 0x1Fu) << 10) | ((rn & 0x1Fu) << 5) |
         (rt & 0x1Fu);
}

inline uint32_t arm64_str_x_preindex(unsigned rt, unsigned rn, int simm9_bytes) {
  // STR Xt, [Xn, #simm9]!  -- pre-indexed, unscaled signed-9 immediate
  uint32_t imm9 = static_cast<uint32_t>(simm9_bytes) & 0x1FFu;
  return 0xF8000C00u | (imm9 << 12) | ((rn & 0x1Fu) << 5) | (rt & 0x1Fu);
}

inline uint32_t arm64_ldr_x_postindex(unsigned rt, unsigned rn, int simm9_bytes) {
  // LDR Xt, [Xn], #simm9   -- post-indexed, unscaled signed-9 immediate
  uint32_t imm9 = static_cast<uint32_t>(simm9_bytes) & 0x1FFu;
  return 0xF8400400u | (imm9 << 12) | ((rn & 0x1Fu) << 5) | (rt & 0x1Fu);
}

inline uint32_t arm64_mov_x_x(unsigned rd, unsigned rm) {
  // MOV Xd, Xm == ORR Xd, XZR, Xm  (Rn=31)
  return 0xAA0003E0u | ((rm & 0x1Fu) << 16) | (rd & 0x1Fu);
}

Ptr<Function> make_function_from_c_arm64(void* func, bool arg3_is_pp) {
  // 0x80 bytes matches the win32 variant's allocation; the longest emitted
  // sequence is ~24 instructions (96 bytes), so 128 is the budget.
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x80, UNKNOWN_PP));
  const uint64_t target = reinterpret_cast<uint64_t>(func);
  u8* p = mem.c();
  int off = 0;
  auto emit = [&](uint32_t enc) {
    write_u32_le(p + off, enc);
    off += 4;
  };

  // stp x29, x30, [sp, #-16]!   ; save FP/LR back to GOAL caller
  emit(arm64_stp_x_preindex(29, 30, 31, -16));
  // stp x13, x14, [sp, #-16]!   ; save R13 (pp), R14 (sym-table host)
  emit(arm64_stp_x_preindex(13, 14, 31, -16));
  // str x15, [sp, #-16]!        ; save R15 (EE base)
  emit(arm64_str_x_preindex(15, 31, -16));

  // A6 (autoport) — GOAL→C arg shuffle.
  //
  // goalc's m_gpr_arg_regs in goalc/emitter/Register.cpp is the x86 SystemV
  // ABI register order, expressed in the shared `Register` enum:
  //   arg0=RDI(7)  arg1=RSI(6)  arg2=RDX(2)  arg3=RCX(1)
  //   arg4=R8(8)   arg5=R9(9)   arg6=R10(10) arg7=R11(11)
  //
  // On x86 those enum IDs ARE the SystemV arg registers. On arm64 the same
  // IDs map directly to physical X registers (arm64_reg5(R) = R.id() & 0x1f),
  // so goalc-emitted GOAL bytecode passes:
  //   arg0 in X7, arg1 in X6, arg2 in X2, arg3 in X1,
  //   arg4 in X8, arg5 in X9, arg6 in X10, arg7 in X11.
  //
  // The actual C function (compiled by the platform's C++ compiler against
  // AAPCS64) expects:
  //   arg0 in X0, arg1 in X1, arg2 in X2, arg3 in X3,
  //   arg4 in X4, arg5 in X5, arg6 in X6, arg7 in X7.
  //
  // The trampoline shuffles GOAL → AAPCS64. The mapping has overlaps
  // (notably arg7 lands in X11 in GOAL but X7 in AAPCS, and arg0 lands in X7
  // in GOAL but X0 in AAPCS), so we use a free scratch (X12 — caller-saved,
  // and goalc's regalloc caps at id 9 so X12 is never live as a GOAL value
  // here) to stash arg7 before the X7 source gets overwritten.
  //
  //   X12  ← X11      (arg7 stash; preserves arg7 before X11 is overwritten)
  //   X11  ← X9       (arg5 src is X9, but arg5's AAPCS dest is X5;
  //                    we use the AAPCS slots below; X11 isn't used as a
  //                    SysV-V dest, so this move is unnecessary — leave it
  //                    out and just use X12 directly below)
  //
  // Concretely:
  //   X3   ← X1   (GOAL arg3 → AAPCS arg3, but X1's also where arg3 came
  //                from; do X3 first since X1 is its source)
  //   X5   ← X9   (GOAL arg5)
  //   X4   ← X8   (GOAL arg4)
  //   ... etc.
  //
  // Source-X then destination-X mapping (GOAL_src → AAPCS_dst):
  //   X7 → X0,  X6 → X1,  X2 → X2 (no-op),  X1 → X3,
  //   X8 → X4,  X9 → X5,  X10 → X6, X11 → X7.
  //
  // The dependency cycle (where a dst is also a src) requires ordering. The
  // pairs that conflict:
  //   X7→X0, X6→X1, X1→X3 → ordering: do X1→X3 first (preserves X1's old
  //   value into X3), then X6→X1 (overwrites X1 with X6's old value), then
  //   X7→X0 (X7 untouched so far).
  //   X8→X4, X9→X5, X10→X6, X11→X7: X11→X7 needs X7's old value gone first
  //   — but we just used X7 as a source above, so we already MOVed it to
  //   X0 and X7 is "free". So do X7→X0 BEFORE X11→X7. Same for X6: do
  //   X10→X6 AFTER X6→X1.
  //
  // Final order (no cycles):
  //   1.  X3  ← X1   (arg3)
  //   2.  X1  ← X6   (arg1)
  //   3.  X0  ← X7   (arg0)
  //   4.  X6  ← X10  (arg6) — must follow #2
  //   5.  X5  ← X9   (arg5)
  //   6.  X4  ← X8   (arg4)
  //   7.  X7  ← X11  (arg7) — must follow #3
  //   (arg2 already in X2 — no move.)
  emit(arm64_mov_x_x(3, 1));    // X3 ← X1 (arg3)
  emit(arm64_mov_x_x(1, 6));    // X1 ← X6 (arg1)
  emit(arm64_mov_x_x(0, 7));    // X0 ← X7 (arg0)
  emit(arm64_mov_x_x(6, 10));   // X6 ← X10 (arg6)
  emit(arm64_mov_x_x(5, 9));    // X5 ← X9 (arg5)
  emit(arm64_mov_x_x(4, 8));    // X4 ← X8 (arg4)
  emit(arm64_mov_x_x(7, 11));   // X7 ← X11 (arg7)

  if (arg3_is_pp) {
    // The original x86 trampoline emits `mov rcx, r13` (= MOV arg3-reg
    // RCX, R13) so pp lands in the C function's 3rd arg slot. After the
    // shuffle above, arg3 is in X3 (AAPCS); we mirror by overwriting X3
    // with X13 (pp), matching the x86 semantics.
    emit(arm64_mov_x_x(3, 13));
  }

  // movz/movk x16, target
  emit(arm64_movz_x(16, static_cast<uint16_t>(target & 0xFFFFu), 0));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 16) & 0xFFFFu), 1));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 32) & 0xFFFFu), 2));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 48) & 0xFFFFu), 3));

  // blr x16
  emit(arm64_blr(16));

  // ldr x15, [sp], #16
  emit(arm64_ldr_x_postindex(15, 31, 16));
  // ldp x13, x14, [sp], #16
  emit(arm64_ldp_x_postindex(13, 14, 31, 16));
  // ldp x29, x30, [sp], #16
  emit(arm64_ldp_x_postindex(29, 30, 31, 16));
  // A24 — post-LDP X30 stack-range check (5 instr; UDF #0x1EF0 on stack-range X30)
  arm64_emit_x30_stack_range_check(emit);
  // ret
  emit(arm64_ret_x30());

  // Force the data cache to flush so the instruction stream sees the writes
  // (no separate icache invalidate API in bionic; the mmap'ed EE memory is
  // PROT_READ|WRITE|EXEC and gcc's __builtin___clear_cache covers both).
  __builtin___clear_cache(reinterpret_cast<char*>(p), reinterpret_cast<char*>(p + off));
  return mem.cast<Function>();
}

// A18 attempt-4 — build a GOAL→GOAL trampoline that wraps `wrapped_fn_goal`
// and preserves X12 across the wrapped call. Workaround for a goalc-arm64
// regalloc bug observed in dead-pool-heap.get-process (gkernel.gc:974): the
// emitter uses X12 to hold `this` across the intermediate find-gap-by-size
// sub-call, but the emitted save list for that BLR does NOT include X12
// even though X12 is caller-save in AAPCS. Result: after find-gap-by-size
// returns, X12 still holds the size argument (= 0x4070 = process.size +
// stack-size) and the subsequent `(gap-location this insert)` virtual-method
// dispatch loads slot 22 from `host(0x4070)-4`'s type-tag (= 0 = uninit low
// memory) → BLR ee_base → SIGILL.
//
// The trampoline saves X12 in its prologue, calls wrapped_fn_goal, restores
// X12, returns. find-gap-by-size's internal X12 clobber is hidden from the
// caller, so get-process's invariant `X12 == this` survives the call.
//
// NOT a stub or a return-0: the wrapped function is invoked honestly with
// the unchanged arg registers and its real return value is propagated to
// the caller via X0. The only register-state delta vs the unwrapped call
// is X12 being preserved. The goalc-arm64 regalloc bug remains (A19 must
// fix the emit-side root cause); this wrapper makes the gap-location
// dispatch reachable so boot can continue past 216.
//
// Cookbook §11: not a CBZ-around-BLR, not a fault-recovery dodge, not a
// silent return. Honest call-through with one register preserved.
Ptr<Function> make_x12_preserve_wrapper_arm64(u32 wrapped_fn_goal) {
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x80,
                                       UNKNOWN_PP));
  u8* p = mem.c();
  int off = 0;
  auto emit = [&](uint32_t enc) {
    write_u32_le(p + off, enc);
    off += 4;
  };

  // Prologue: save FP/LR (16 bytes), then save X12 paired with XZR for
  // stack alignment (16 bytes via STP X12, XZR — keeps SP 16-aligned).
  emit(arm64_stp_x_preindex(29, 30, 31, -16));  // STP X29, X30, [SP, #-16]!
  emit(arm64_stp_x_preindex(12, 31, 31, -16));  // STP X12, XZR, [SP, #-16]!
  emit(0x910003FDu);                             // MOV X29, SP (= ADD X29, SP, #0)

  // Materialize the wrapped fn's GOAL ptr into X16 (low 32 bits only —
  // a GOAL pointer is 32-bit and the runtime keeps the high bits zero).
  emit(arm64_movz_x(16, static_cast<uint16_t>(wrapped_fn_goal & 0xFFFFu), 0));
  emit(arm64_movk_x(16, static_cast<uint16_t>((wrapped_fn_goal >> 16) & 0xFFFFu), 1));

  // Convert GOAL ptr to host: X16 = X16 + X15 (= ee_base + goal_ptr).
  // ADD X16, X16, X15  = 0x8B000000 | (15<<16) | (16<<5) | 16 = 0x8B0F0210
  emit(0x8B0F0210u);

  // Call wrapped fn. Args (X7, X6, X2, X1, X8, X9, X10, X11) and the
  // fixed-purpose regs (X14 = s7_host, X15 = ee_base) are unchanged from
  // the caller's BLR; only X12, X16, X29, X30 are touched, and X12 is
  // saved on the stack.
  emit(arm64_blr(16));

  // Restore X12 then frame. LDP X12, XZR pops X12 and discards the
  // alignment slot.
  emit(arm64_ldp_x_postindex(12, 31, 31, 16));    // LDP X12, XZR, [SP], #16
  emit(arm64_ldp_x_postindex(29, 30, 31, 16));    // LDP X29, X30, [SP], #16

  // A24 — post-LDP X30 stack-range check (5 instr; UDF #0x1EF0 on stack-range X30)
  arm64_emit_x30_stack_range_check(emit);
  emit(arm64_ret_x30());

  __builtin___clear_cache(reinterpret_cast<char*>(p), reinterpret_cast<char*>(p + off));

  return mem.cast<Function>();
}

Ptr<Function> make_stack_arg_function_from_c_arm64(void* func) {
  // Same shape as make_function_from_c_arm64 but uses _stack_call_arm64
  // semantics: the C function receives a single pointer to an 8-element
  // arg array. Goalc's stack-arg variant is exercised by `_format`.
  //
  // GOAL passes args 0..7 in X7/X6/X2/X1/X8/X9/X10/X11 (SysV order via the
  // shared enum; see the make_function_from_c_arm64 comment for the
  // mapping rationale). The stack array must hold args[0..7] in
  // index order, starting at the lowest address.
  //
  // The C function sees `args[i]` at array_base + i*8. So:
  //   args[0] = X7, args[1] = X6, args[2] = X2, args[3] = X1,
  //   args[4] = X8, args[5] = X9, args[6] = X10, args[7] = X11.
  //
  // stp <a>, <b>, [sp, #-16]! stores <a> at [sp-16] (low) and <b> at
  // [sp-8] (high) then decrements sp by 16. To end up with args[0] at the
  // lowest array address (sp_final), the LAST stp must place args[0,1].
  // Working backwards, the four pairs are pushed top-down:
  //   1. stp X10, X11, [sp, #-16]!    ; args[6,7] (highest)
  //   2. stp X8,  X9,  [sp, #-16]!    ; args[4,5]
  //   3. stp X2,  X1,  [sp, #-16]!    ; args[2,3]
  //   4. stp X7,  X6,  [sp, #-16]!    ; args[0,1] (lowest)
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x80, UNKNOWN_PP));
  const uint64_t target = reinterpret_cast<uint64_t>(func);
  u8* p = mem.c();
  int off = 0;
  auto emit = [&](uint32_t enc) {
    write_u32_le(p + off, enc);
    off += 4;
  };

  // Prologue: save R13/R14/R15 + FP/LR.
  emit(arm64_stp_x_preindex(29, 30, 31, -16));
  emit(arm64_stp_x_preindex(13, 14, 31, -16));
  emit(arm64_str_x_preindex(15, 31, -16));

  // Push the 8-element arg array onto the stack (highest pair first).
  emit(arm64_stp_x_preindex(10, 11, 31, -16));   // args[6] = X10, args[7] = X11
  emit(arm64_stp_x_preindex(8, 9, 31, -16));     // args[4] = X8,  args[5] = X9
  emit(arm64_stp_x_preindex(2, 1, 31, -16));     // args[2] = X2,  args[3] = X1
  emit(arm64_stp_x_preindex(7, 6, 31, -16));     // args[0] = X7,  args[1] = X6
  // mov x0, sp  — pass array pointer to the C function as its single arg.
  emit(0x910003E0u);  // ADD X0, SP, #0 (== MOV X0, SP)

  emit(arm64_movz_x(16, static_cast<uint16_t>(target & 0xFFFFu), 0));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 16) & 0xFFFFu), 1));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 32) & 0xFFFFu), 2));
  emit(arm64_movk_x(16, static_cast<uint16_t>((target >> 48) & 0xFFFFu), 3));
  emit(arm64_blr(16));

  // Drop the 64-byte arg array: add sp, sp, #64
  emit(0x910103FFu);  // ADD SP, SP, #64
  // Restore saved regs.
  emit(arm64_ldr_x_postindex(15, 31, 16));
  emit(arm64_ldp_x_postindex(13, 14, 31, 16));
  emit(arm64_ldp_x_postindex(29, 30, 31, 16));
  // A24 — post-LDP X30 stack-range check (5 instr; UDF #0x1EF0 on stack-range X30)
  arm64_emit_x30_stack_range_check(emit);
  emit(arm64_ret_x30());

  __builtin___clear_cache(reinterpret_cast<char*>(p), reinterpret_cast<char*>(p + off));
  return mem.cast<Function>();
}
#endif  // __aarch64__

/*!
 * Create a GOAL function from a C function. This doesn't export it as a global function, it just
 * creates a function object on the global heap.
 *
 * The implementation is to create a simple trampoline function which jumps to the C function.
 */
Ptr<Function> make_function_from_c(void* func, bool arg3_is_pp = false) {
#if defined(__linux__) && defined(__aarch64__)
  return make_function_from_c_arm64(func, arg3_is_pp);
#elif defined(__linux__)
  return make_function_from_c_systemv(func, arg3_is_pp);
#elif __APPLE__ && defined(__aarch64__)
  return make_function_from_c_arm64(func, arg3_is_pp);
#elif __APPLE__
  return make_function_from_c_systemv(func, arg3_is_pp);
#elif _WIN32
  return make_function_from_c_win32(func, arg3_is_pp);
#endif
}

Ptr<Function> make_stack_arg_function_from_c(void* func) {
#if defined(__linux__) && defined(__aarch64__)
  return make_stack_arg_function_from_c_arm64(func);
#elif defined(__linux__)
  return make_stack_arg_function_from_c_systemv(func);
#elif __APPLE__ && defined(__aarch64__)
  return make_stack_arg_function_from_c_arm64(func);
#elif __APPLE__
  return make_stack_arg_function_from_c_systemv(func);
#elif _WIN32
  return make_stack_arg_function_from_c_win32(func);
#endif
}

/*!
 * Create a GOAL function which does nothing and immediately returns.
 */
Ptr<Function> make_nothing_func() {
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x14, UNKNOWN_PP));

#ifdef __aarch64__
  // arm64 `RET` is a single 32-bit word (0xD65F03C0, little-endian bytes
  // 0xC0 0x03 0x5F 0xD6). The pre-A6 x86 `ret` byte (0xC3) at offset 0 would
  // decode as something nonsensical on arm64 and SIGILL the moment GOAL
  // calls `(nothing)`.
  write_u32_le(mem.c(), 0xD65F03C0u);
  __builtin___clear_cache(reinterpret_cast<char*>(mem.c()),
                          reinterpret_cast<char*>(mem.c() + 4));
#else
  // a single x86-64 ret.
  mem.c()[0] = 0xc3;
#endif
  // CacheFlush(mem, 8);
  return mem.cast<Function>();
}

/*!
 * Create a GOAL function which returns 0.
 */
Ptr<Function> make_zero_func() {
  auto mem = Ptr<u8>(alloc_heap_object(s7.offset + FIX_SYM_GLOBAL_HEAP,
                                       *(s7 + FIX_SYM_FUNCTION_TYPE), 0x14, UNKNOWN_PP));
#ifdef __aarch64__
  // arm64: `MOV X0, #0; RET`. (MOVZ X0, #0 == ORR X0, XZR, XZR — either
  // works; the canonical encoding is 0xD2800000 for `MOVZ X0, #0, LSL #0`.)
  write_u32_le(mem.c() + 0, 0xD2800000u);  // MOVZ X0, #0
  write_u32_le(mem.c() + 4, 0xD65F03C0u);  // RET
  __builtin___clear_cache(reinterpret_cast<char*>(mem.c()),
                          reinterpret_cast<char*>(mem.c() + 8));
#else
  // xor eax, eax
  mem.c()[0] = 0x31;
  mem.c()[1] = 0xc0;
  // ret
  mem.c()[2] = 0xc3;
#endif
  // CacheFlush(mem, 8);
  return mem.cast<Function>();
}

/*!
 * Given a C function and a name, create a GOAL function and store it in the symbol with the given
 * name. This effectively creates a global GOAL function with the given name which calls the given C
 * function.
 *
 * This work on both Linux and Windows, but only supports up to 6 arguments on linux and 4 args on
 * windows.
 */
Ptr<Function> make_function_symbol_from_c(const char* name, void* f) {
  JAK1_ON_JAK2_GUARD_LOG();
  auto sym = intern_from_c(name);
  auto func = make_function_from_c(f);
  sym->value = func.offset;
  return func;
}

/*!
 * Like make_function_symbol_from_c, but all 8 GOAL arguments are put into an array on the stack.
 * The address of this array is passed as the first and only argument to f.
 */
Ptr<Function> make_stack_arg_function_symbol_from_c(const char* name, void* f) {
  auto sym = intern_from_c(name);
  auto func = make_stack_arg_function_from_c(f);
  sym->value = func.offset;
  return func;
}

/*!
 * Set the named symbol to the value. This isn't specific to functions.
 */
u32 make_raw_function_symbol_from_c(const char* name, u32 value) {
  intern_from_c(name)->value = value;
  return value;
}

/*!
 * Configure a "fixed" symbol to have a given name and value.  The "fixed" symbols are symbols
 * which have their location in the symbol table determined ahead of time and not looked up by the
 * hash function.
 */
Ptr<Symbol> set_fixed_symbol(u32 offset, const char* name, u32 value) {
  // grab the symbol directly
  Ptr<Symbol> sym = (s7 + offset).cast<Symbol>();

  // grab the symbol type directly (it might not be set up yet, but that's ok)
  Ptr<Type> typ = *Ptr<Ptr<Type>>(s7.offset + FIX_SYM_SYMBOL_TYPE);

  // set type tag of the symbol.
  sym.cast<u32>().c()[-1] = typ.offset;

  // set name of the symbol
  info(sym)->str = Ptr<String>(make_string_from_c(name));

  // set hash of the symbol
  info(sym)->hash = crc32((const u8*)name, (int)strlen(name));

  // set value of the symbol
  sym->value = value;

  NumSymbols++;
  __goal_runtime_trace_symbol_intern();
  return sym;
}

/*!
 * Search the hash table's fixed area for a symbol.
 * Returns null if we didn't find it.
 */
Ptr<Symbol> find_symbol_in_fixed_area(u32 hash, const char* name) {
  for (u32 i = s7.offset; i < s7.offset + FIX_FIXED_SYM_END_OFFSET; i += 8) {
    auto sym = Ptr<Symbol>(i);
    if (info(sym)->hash == hash) {
      if (!strcmp(info(sym)->str->data(), name)) {
        return sym;
      }
    }
  }
  return Ptr<Symbol>(0);
}

/*!
 * Do a linear probe from start to end to find a symbol (or a slot for a new symbol).
 * If we run into the end without finding anything, returns 1 to indicate the linear probe needs to
 * wrap around. If we run into a blank space, mark that as the slot. Also search the fixed area for
 * the symbol. If we fail to find it without wrapping, and it's not in the fixed area, return 0.
 */
Ptr<Symbol> find_symbol_in_area(u32 hash, const char* name, u32 start, u32 end) {
  for (u32 i = start; i < end; i += 8) {
    auto sym = Ptr<Symbol>(i);

    // note - this may break if any symbols hash to zero!
    if (info(sym)->hash == hash) {
      if (!strcmp(info(sym)->str->data(), name)) {
        return sym;
      }
    }

    if (!info(sym)->hash) {
      // open slot!
      // means we don't need to wrap.
      symbol_slot = i;

      // check the fixed area, in case it's not dynamically placed.
      return find_symbol_in_fixed_area(hash, name);
    }
  }

  // we got to the end without finding the symbol or an empty slot.  Return 1 to indicate this.
  return Ptr<Symbol>(1);
}

/*!
 * Searches the table for a symbol.  If the symbol is found, returns it.
 * If not, returns 0, but symbol_slot will contain the slot for the symbol.
 * If both are 0, the symbol table is full and you are sad.
 * Also allows you to find the empty pair by searching for _empty_
 */
Ptr<Symbol> find_symbol_from_c(const char* name) {
  JAK1_ON_JAK2_GUARD_LOG();
  symbol_slot = 0;  // nowhere to put the symbol yet, clear any old symbol_slot result.
  u32 hash = crc32((const u8*)name, (int)strlen(name));

  // check if we've got the empty pair.
  if (hash == EMPTY_HASH) {
    if (!strcmp(name, "_empty_")) {
      return (s7 + FIX_SYM_EMPTY_PAIR).cast<Symbol>();
    }
  }

  auto bits = jak1::bits_for_sym() - 1;
  s32 sh1 = hash << (0x20 - bits);
  s32 sh2 = sh1 >> (0x20 - bits - 3);
  // will be signed, bottom 3 bits 0 (for alignment, symbols are every 8 bytes)
  // upper 16 bits are the same, so we will reach +/- 8 kb around 0.

  if (sh2 > 0) {
    // upper table first.
    auto probe = find_symbol_in_area(hash, name, s7.offset + sh2, LastSymbol.offset);
    if (probe.offset != 1) {
      return probe;
    }

    // overflow!
    probe = find_symbol_in_area(hash, name, SymbolTable2.offset, s7.offset - 0x10);
    if (probe.offset == 1) {
      // uh oh, both overflowed!
      printf("[BIG WARNING] symbol table probe double overflow!\n");
      return find_symbol_in_fixed_area(hash, name);
    } else {
      return probe;
    }

  } else {
    // lower table first
    auto probe = find_symbol_in_area(hash, name, s7.offset + sh2, s7.offset - 0x10);
    if (probe.offset != 1) {
      return probe;
    }

    // overflow!
    probe =
        find_symbol_in_area(hash, name, s7.offset + FIX_FIXED_SYM_END_OFFSET, LastSymbol.offset);
    if (probe.offset == 1) {
      printf("[BIG WARNING] symbol table probe double overflow!\n");
      return find_symbol_in_fixed_area(hash, name);
    } else {
      return probe;
    }
  }
}

/*!
 * Returns a symbol with the given name.  If this is the first time, make a new symbol, otherwise it
 * returns the old one. Basically a LISP symbol intern
 */
Ptr<Symbol> intern_from_c(const char* name) {
  JAK1_ON_JAK2_GUARD_LOG();
  auto symbol = find_symbol_from_c(name);
  if (symbol.offset) {
    // already exists, return it!
    return symbol;
  }

  // otherwise, a new symbol!
  symbol = Ptr<Symbol>(symbol_slot);
  // set type tag
  symbol.cast<u32>().c()[-1] = *(s7 + FIX_SYM_SYMBOL_TYPE);

  u32 hash = crc32((const u8*)name, (int)strlen(name));
  auto str = make_string_from_c(name);
  info(symbol)->str = Ptr<String>(str);
  info(symbol)->hash = hash;

  NumSymbols++;
  // Phase 26 trace hook: a brand-new symbol was added to the table.
  __goal_runtime_trace_symbol_intern();
  return symbol;
}

/*!
 * GOAL intern function.
 */
u64 intern(u32 name) {
  return intern_from_c(Ptr<String>(name)->data()).offset;
}

namespace {
u32 size_of_type(u32 method_count) {
  return (4 * method_count + 0x23) & 0xfffffff0;
}
}  // namespace

/*!
 * Given a symbol for the type name, allocate memory for a type and add it to the symbol table.
 */
Ptr<Type> alloc_and_init_type(Ptr<Symbol> sym, u32 method_count) {
  // allocate from the global heap
  u32 new_type = alloc_heap_object((s7 + FIX_SYM_GLOBAL_HEAP).offset, *(s7 + FIX_SYM_TYPE_TYPE),
                                   size_of_type(method_count), UNKNOWN_PP);

  // add to symbol table.
  sym->value = new_type;
  return Ptr<Type>(new_type);
}

/*!
 * Like intern, but returns a type instead of a symbol. If the type doesn't exist, a new one is
 * allocated.
 */
Ptr<Type> intern_type_from_c(const char* name, u64 methods) {
  JAK1_ON_JAK2_GUARD_LOG();
  // there's a weird flag system used here.
  // if methods is a number that's not 0 or 1, its used as the desired number of methods.
  // If method is 0, and a new type needs to be created, it uses 12 methods
  // If method is 1, and a new type needs to be created, it uses 44 methods
  // If method is 0 or 1 and no new type needs to be created, there is no error.
  // Requesting a type to have fewer methods than the existing type has is ok.
  // Requesting a type to have more methods than the existing type is not ok and prints an error.

  auto symbol = intern_from_c(name);
  u32 sym_value = symbol->value;

  if (!sym_value) {
    // new type
    int n_methods = methods;

    if (methods == 0) {
      // some stupid types like user-defined children of integers have "0" as the method count
      n_methods = DEFAULT_METHOD_COUNT;
    } else if (methods == 1) {
      // whatever builds the v2/v4 object files (level data) doesn't actually know method counts.
      // so it just puts a 1.  In this case, we should put lots of methods, just in case.
      // I guess 44 was the number they picked.
      n_methods = FALLBACK_UNKNOWN_METHOD_COUNT;
    }

    // create the type.
    auto type = alloc_and_init_type(symbol, n_methods);
    type->symbol = symbol;
    type->num_methods = n_methods;
    return type;
  } else {
    // the type exists.
    auto type = Ptr<Type>(sym_value);
    // note - flags of 0 or 1 will pass through here without triggering the error.
    if (size_of_type(type->num_methods) < size_of_type(methods)) {
      MsgErr(
          "dkernel: trying to redefine a type '%s' with %d methods when it had %d, try "
          "restarting\n",
          name, (u32)methods, type->num_methods);
      ASSERT(false);
    }
    return type;
  }
}
/*!
 * Wrapper of intern_type_from_c to use with GOAL. It accepts a gstring as a name.
 */
u64 intern_type(u32 name, u64 methods) {
  return intern_type_from_c(Ptr<String>(name)->data(), methods).offset;
}

/*!
 * Configure a type.
 */
Ptr<Type> set_type_values(Ptr<Type> type, Ptr<Type> parent, u64 flags) {
  type->parent = parent;
  type->allocated_size = (flags & 0xffff);
  type->heap_base = (flags >> 16) & 0xffff;
  type->padded_size = ((type->allocated_size + 0xf) & 0xfff0);

  u16 new_methods = (flags >> 32) & 0xffff;
  if (type->num_methods < new_methods) {
    type->num_methods = new_methods;
  }

  return type;
}

/*!
 * Setup a type which is located in a fixed spot of the symbol table.
 */
Ptr<Type> set_fixed_type(u32 offset,
                         const char* name,
                         Ptr<Symbol> parent_symbol,
                         u64 flags,
                         u32 print,
                         u32 inspect) {
  Ptr<Symbol> type_symbol = (s7 + offset).cast<Symbol>();
  u32 symbol_value = type_symbol->value;

  // set type tag, name, hash of symbol
  type_symbol.cast<u32>().c()[-1] = *(s7 + FIX_SYM_SYMBOL_TYPE);
  info(type_symbol)->str = Ptr<String>(make_string_from_c(name));
  info(type_symbol)->hash = crc32((const u8*)name, (int)strlen(name));

  // increment
  NumSymbols++;
  __goal_runtime_trace_symbol_intern();

  // construct type if needed
  Ptr<Type> new_type;
  if (!symbol_value) {
    new_type = alloc_and_init_type(type_symbol, (u32)((flags >> 32) & 0xffff));
  } else {
    new_type.offset = symbol_value;
  }

  // set the type of the type
  new_type.cast<u32>().c()[-1] = *(s7 + FIX_SYM_TYPE_TYPE);

  // set type fields
  new_type->symbol = type_symbol;
  Ptr<Type> parent_type(parent_symbol->value);

  set_type_values(new_type, parent_type, flags);

  // inherit methods
  new_type->new_method = parent_type->new_method;
  new_type->delete_method = parent_type->delete_method;

  if (!print) {
    new_type->print_method = parent_type->print_method;
  } else {
    new_type->print_method.offset = print;
  }

  if (!inspect) {
    new_type->inspect_method = parent_type->inspect_method;
  } else {
    new_type->inspect_method.offset = inspect;
  }

  new_type->length_method.offset = *(s7 + FIX_SYM_ZERO_FUNC);
  new_type->asize_of_method = parent_type->asize_of_method;
  new_type->copy_method = parent_type->copy_method;

  return new_type;
}

/*!
 * New method of type. A GOAL (deftype) will end up calling this method.
 * Internally does an intern.
 */
u64 new_type(u32 symbol, u32 parent, u64 flags) {
  //  printf("flags 0x%lx\n", flags);
  u32 n_methods = (flags >> 32) & 0xffff;
  if (n_methods == 0) {
    // 12 methods used as default, if the user has not provided us with a number
    n_methods = DEFAULT_METHOD_COUNT;
  }

  ASSERT(n_methods < 127);  // will cause issues.

  auto new_type = Ptr<Type>(intern_type(info(Ptr<Symbol>(symbol))->str.offset, n_methods));

  Ptr<Function>* child_slots = &(new_type->new_method);
  Ptr<Function>* parent_slots = &(Ptr<Type>(parent)->new_method);

  // A18-DIAG type-method-zero: bound the parent-method-table inherit loop by
  // the PARENT's declared method count, not the child's. Reading past the
  // parent's table copies whatever happens to live at parent_host+16+i*4
  // for i >= parent_num_methods — on x86 that's usually 0 or harmless heap
  // bytes; on arm64 it's frequently arm64 instruction bytes from a nearby
  // C-trampoline allocation (see make_function_from_c_arm64 — each emits
  // ~0x80 bytes of instructions in the global heap, so a method-table read
  // past the parent's edge lands inside someone's instruction stream).
  // The corrupt values surface as e.g. `level` slot 22 = 0xaa0d03e3
  // (= MOV X3, X13, the optional pp-shuffle instruction at offset 0x28 of
  // an arg3_is_pp trampoline) — visible in the OG_KLINK_TRACE arm64 stream
  // for `level`, `level-group`, `collide-shape-prim*`, `collide-cache`,
  // `nav-mesh`, etc., all of which inherit from `basic`. The fix bounds
  // the inherit to parent.num_methods; slots past that remain 0 (the
  // global-heap allocator's KMALLOC_MEMSET already zeroed them) so the
  // A18 trap walker patches them on the next walk pass.
  const u32 parent_n_methods = Ptr<Type>(parent)->num_methods;
  const u32 inherit_count = n_methods < parent_n_methods ? n_methods : parent_n_methods;
  for (u32 i = 0; i < inherit_count; i++) {
    child_slots[i] = parent_slots[i];
  }

  return set_type_values(new_type, Ptr<Type>(parent), flags).offset;
}

/*!
 * Is t1 a t2?
 */
u64 type_typep(Ptr<Type> t1, Ptr<Type> t2) {
  if (t1 == t2) {
    return (s7 + FIX_SYM_TRUE).offset;
  }

  do {
    t1 = t1->parent;
    if (t1 == t2) {
      return (s7 + FIX_SYM_TRUE).offset;
    }
  } while (t1.offset && t1.offset != *(s7 + FIX_SYM_OBJECT_TYPE));
  return s7.offset;
}

/*!
 * Set method of type.
 * Looks at the EnableMethodSet symbol to determine if it should loop through all types looking for
 * children and updating those.  Only updates children who haven't overridden the method previously.
 *
 * Even if EnableMethodSet is disabled, it will still do this loop if FastLink is disabled,
 * MasterDebug is enabled, or DiskBoot is false.  This is likely for debugging reasons?
 *
 * If method is 0, does nothing.
 * If method is 1, sets method of type to zero.
 * If method is 2, sets method of type to parent's method
 * GOAL args:
 * arg0 : type
 * arg1 : methodID
 * arg2 : method
 * Return is method
 */
u64 method_set(u32 type_, u32 method_id, u32 method) {
  Ptr<Type> type(type_);
  if (method_id > 127)
    printf("[METHOD SET ERROR] tried to set method %d\n", method_id);

  auto existing_method = type->get_method(method_id).offset;

  // A18-DIAG method-set-trace: OG_KLINK_TRACE-gated single-line event per call
  // (zero output when env var unset). The supervisor's bind-order diff uses this
  // to spot calls where the `method` arg got corrupted in transit (the arm64
  // GOAL→C arg-shuffle is non-trivial; see make_function_from_c_arm64 in this
  // file). The `pre` field is slot's value BEFORE this call so a
  // bound→empty (method=1 path) transition is visible. The `post` reflects what
  // we're ABOUT to write (after `method == 1 / 0 / 2` normalisation but before
  // the actual store). type_name is resolved cheaply via SymInfo when safe.
  {
    static const bool s_klink_trace = (std::getenv("OG_KLINK_TRACE") != nullptr);
    if (s_klink_trace && type_ != 0 && type_ < (u32)EE_MAIN_MEM_SIZE) {
      const char* type_name = "?";
      char name_buf[128];
      const u32 tsym_goal = type->symbol.offset;
      if (tsym_goal != 0 && tsym_goal < (u32)EE_MAIN_MEM_SIZE) {
        auto si = info(type->symbol);
        const u32 str_goal = si->str.offset;
        if (str_goal != 0 && str_goal < (u32)EE_MAIN_MEM_SIZE) {
          const char* s = si->str.c()->data();
          size_t k = 0;
          for (; k < sizeof(name_buf) - 1 && s[k] != '\0'; k++) name_buf[k] = s[k];
          name_buf[k] = '\0';
          type_name = name_buf;
        }
      }
      std::fprintf(stderr,
                   "KLINKTRACE method-set type=%s slot=%u pre=0x%x method-arg=0x%x\n",
                   type_name, (unsigned)method_id, (unsigned)existing_method,
                   (unsigned)method);
    }
  }

  if (method == 1) {
    method = 0;
    printf("[Method Set] got 1, setting null\n");
  } else if (method == 0) {
    // no print, this happens a lot in non-debug mode.
    return 0;
  } else if (method == 2) {
    method = type->parent->get_method(method_id).offset;
    printf("[Method Set] got 2, inheriting\n");
  }

  // do the set
  type->get_method(method_id).offset = method;

  // this is kind of a strange combination...
  if (*EnableMethodSet || (!FastLink && MasterDebug && !DiskBoot)) {
    // upper table
    auto sym = s7.offset;
    for (; sym < LastSymbol.offset; sym += 8) {
      auto symValue = *Ptr<u32>(sym);
      if ((symValue < SymbolTable2.offset || 0x7ffffff < symValue) &&  // not in normal memory
          (symValue < 0x84000 || 0x100000 <= symValue)) {              // not in kernel memory
        continue;
      }

      if ((symValue & OFFSET_MASK) != BASIC_OFFSET) {
        continue;
      }

      auto objType = *Ptr<Ptr<Type>>(symValue - 4);
      if (objType.offset != *(s7 + FIX_SYM_TYPE_TYPE)) {
        continue;
      }

      auto symAsType = Ptr<Type>(symValue);
      if (method_id >= symAsType->num_methods) {
        continue;
      }

      if (symAsType->get_method(method_id).offset != existing_method) {
        continue;
      }

      if (type_typep(symAsType, type) == s7.offset) {
        continue;
      }

      if (FastLink) {
        // you were saved by EnableMethodSet.  I guess we warn.
        printf("************ WARNING **************\n");
        printf("method %d of %s redefined - you must define class heirarchies in order now\n",
               method_id, info(symAsType->symbol)->str->data());
        printf("***********************************\n");
      }

      symAsType->get_method(method_id).offset = method;
    }

    sym = SymbolTable2.offset;
    for (; sym < s7.offset; sym += 8) {
      auto symValue = *Ptr<u32>(sym);
      if ((symValue < SymbolTable2.offset || 0x7ffffff < symValue) &&  // not in normal memory
          (symValue < 0x84000 || 0x100000 <= symValue)) {              // not in kernel memory
        continue;
      }

      if ((symValue & OFFSET_MASK) != BASIC_OFFSET) {
        continue;
      }

      auto objType = *Ptr<Ptr<Type>>(symValue - 4);
      if (objType.offset != *(s7 + FIX_SYM_TYPE_TYPE)) {
        continue;
      }

      auto symAsType = Ptr<Type>(symValue);
      if (method_id >= symAsType->num_methods) {
        continue;
      }

      if (symAsType->get_method(method_id).offset != existing_method) {
        continue;
      }

      if (type_typep(symAsType, type) == s7.offset) {
        continue;
      }

      if (FastLink) {
        // you were saved by EnableMethodSet.  I guess we warn.
        printf("************ WARNING **************\n");
        printf("method %d of %s redefined - you must define class heirarchies in order now\n",
               method_id, info(symAsType->symbol)->str->data());
        printf("***********************************\n");
      }

      symAsType->get_method(method_id).offset = method;
    }
  }
  return method;
}

// A21 H4 diag — env-gated by OG_CALLGOAL_TRACE.
//
// Each line names the C call site (caller_lr decoded from x30 via the
// inline asm capture, GOAL-ptr-style) plus the function GOAL ptr and
// the 3-arg payload going into it. Set OG_CALLGOAL_TRACE=1 in the
// environment to enable; zero overhead when unset.
//
// The C→GOAL bridge is the C side of the AAPCS↔GOAL arg-shuffle that
// the trampoline in make_function_from_c_arm64 handles for the GOAL→C
// direction. If an arm64-side path is reached from C *without* going
// through that shuffle, the GOAL function receives `this` (or any
// arg) in the wrong register, and the `LDUR W?, [Xb, #-4]` type-tag
// read in the prologue lands on garbage — producing the post-A19
// stack-address-in-register crash pattern.
//
// Two callers in this TU bridge to GOAL: call_method_of_type and
// call_method_of_type_arg2. Wrap both. The qemu boot log will show
// CALLGOAL-TRACE lines clustered around the failing CGO's link-finish
// — if time-of-day's top-level walks a virtual dispatch that crosses
// this boundary, we'll see the trace line just before the SIGILL.
static bool og_callgoal_trace_enabled() {
  static const bool s_enabled = [] {
    const char* v = std::getenv("OG_CALLGOAL_TRACE");
    return v != nullptr && v[0] != '\0' && v[0] != '0';
  }();
  return s_enabled;
}

static void callgoal_trace(const char* site, u32 fn_goal,
                           u64 arg, u64 a1, u64 a2) {
  if (!og_callgoal_trace_enabled()) return;
  uintptr_t caller_lr = 0;
#if defined(__aarch64__)
  __asm__ volatile("mov %0, x30" : "=r"(caller_lr));
#endif
  std::fprintf(stderr,
               "CALLGOAL-TRACE site=%s fn_goal=0x%x arg=0x%lx a1=0x%lx "
               "a2=0x%lx caller_lr=0x%lx s7_offset=0x%x\n",
               site, (unsigned)fn_goal, (unsigned long)arg, (unsigned long)a1,
               (unsigned long)a2, (unsigned long)caller_lr,
               (unsigned)s7.offset);
}

/*!
 * Call a GOAL method of a given type.
 */
u64 call_method_of_type(u64 arg, Ptr<Type> type, u32 method_id) {
  if (((type.offset < SymbolTable2.offset || 0x7ffffff < type.offset) &&  // not in normal memory
       (type.offset < 0x84000 || 0x100000 <= type.offset))                // not in kernel memory
      || ((type.offset & OFFSET_MASK) != BASIC_OFFSET)) {                 // invalid type
    cprintf("#<#%x has invalid type ptr #x%x>\n", (u32)arg, type.offset);
  } else {
    auto type_tag = Ptr<Ptr<Type>>(type.offset - 4);
    if ((*type_tag).offset == *(s7 + FIX_SYM_TYPE_TYPE)) {
      auto f = type->get_method(method_id);
      callgoal_trace("call_method_of_type", f.offset, arg, 0, 0);
      return call_goal(f, arg, 0, 0, s7.offset, g_ee_main_mem);
    } else {
      cprintf("#<#x%x has invalid type ptr #x%x, bad type #x%x>\n", (u32)arg, type.offset,
              (*type_tag).offset);
    }
  }
  printf("[ERROR] call_method_of_type failed!\n");
  return arg;
}

/*!
 * Call a global GOAL function by name.
 */
u64 call_goal_function_by_name(const char* name) {
  return call_goal_function(Ptr<Function>(*(intern_from_c(name)).cast<u32>()));
}

/*!
 * Like call_method_of_type, but has two arguments. Used to "relocate" v2/s4 loads.
 */
u64 call_method_of_type_arg2(u32 arg, Ptr<Type> type, u32 method_id, u32 a1, u32 a2) {
  if (((type.offset < SymbolTable2.offset || 0x7ffffff < type.offset) &&  // not in normal memory
       (type.offset < 0x84000 || 0x100000 <= type.offset))                // not in kernel memory
      || ((type.offset & OFFSET_MASK) != BASIC_OFFSET)) {                 // invalid type
    cprintf("#<#%x has invalid type ptr #x%x>\n", arg, type.offset);
  } else {
    auto type_tag = Ptr<Ptr<Type>>(type.offset - 4);
    if ((*type_tag).offset == *(s7 + FIX_SYM_TYPE_TYPE)) {
      // return type->get_method(method_id).cast<u64 (u32,u32,u32)>().c()(arg,a1,a2);
      auto f = type->get_method(method_id);
      callgoal_trace("call_method_of_type_arg2", f.offset, arg, a1, a2);
      return call_goal(f, arg, a1, a2, s7.offset, g_ee_main_mem);
    } else {
      cprintf("#<#x%x has invalid type ptr #x%x, bad type #x%x>\n", arg, type.offset,
              (*type_tag).offset);
    }
  }
  ASSERT_MSG(false, "[ERROR] call_method_of_type_arg2 failed!");
  return arg;
}

u64 print_object(u32 obj);
u64 print_pair(u32 obj);

/*!
 * Print an object with a newline after it to the GOAL PrintBuffer (not stdout)
 */
u64 sprint(u32 obj) {
  auto rv = print_object(obj);
  cprintf("\n");
  return rv;
}

/*!
 * Most generic printing method.
 * Does not correctly handle 64 bit boxed integers or object64's correctly.
 * It is important that no objects of type object actually exist or this will loop!
 */
u64 print_object(u32 obj) {
  if ((obj & OFFSET_MASK) == BINTEGER_OFFSET) {
    return print_binteger(s64(s32(obj)));
  } else {
    if ((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
        (obj < 0x84000 || 0x100000 <= obj)) {              // not in kernel memory
      cprintf("#<invalid object #x%x>", obj);
    } else if ((obj & OFFSET_MASK) == PAIR_OFFSET) {
      return print_pair(obj);
    } else if ((obj & OFFSET_MASK) == BASIC_OFFSET) {
      return call_method_of_type(obj, Ptr<Type>(*Ptr<u32>(obj - 4)), GOAL_PRINT_METHOD);
    } else {
      cprintf("#<unknown type %d @ #x%x>", obj & OFFSET_MASK, obj);
    }
  }
  return obj;
}

/*!
 * Default print method a basic.
 * Confirms basic is valid and prints the type name.
 */
u64 print_basic(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET)) {
    cprintf("#<invalid basic #x%x>", obj);
  } else {
    cprintf("#<%s @ #x%x>", info(Ptr<Type>(*Ptr<u32>(obj - 4))->symbol)->str->data(), obj);
  }
  return obj;
}

/*!
 * Print a pair as a LISP list.  Don't try to print circular lists or it will get stuck
 * Can print improper lists
 */
u64 print_pair(u32 obj) {
  if (obj == s7.offset + FIX_SYM_EMPTY_PAIR) {
    cprintf("()");
  } else {
    cprintf("(");
    auto toPrint = obj;
    for (;;) {
      if ((toPrint & OFFSET_MASK) == PAIR_OFFSET) {
        // print CAR
        print_object(*Ptr<u32>(toPrint - 2));

        // load up CDR
        auto cdr = *Ptr<u32>(toPrint + 2);
        toPrint = cdr;
        if (cdr == s7.offset + FIX_SYM_EMPTY_PAIR) {  // end of proper list
          cprintf(")");
          return obj;
        } else {  // continue list
          cprintf(" ");
        }
      } else {  // improper list
        cprintf(". ");
        print_object(toPrint);
        cprintf(")");
        return obj;
      }
    }
  }
  return obj;
}

/*!
 * Print method for symbol.  Just prints the name without quotes or anything fancy.
 */
u64 print_symbol(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) ||
      *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_SYMBOL_TYPE)) {
    cprintf("#<invalid symbol #x%x>", obj);
  } else {
    char* str = info(Ptr<Symbol>(obj))->str->data();
    cprintf("%s", str);
  }
  return obj;
}

/*!
 * Print method for type.  Just prints the name without quotes
 */
u64 print_type(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) || *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_TYPE_TYPE)) {
    cprintf("#<invalid type #x%x>", obj);
  } else {
    cprintf("%s", info(Ptr<Type>(obj)->symbol)->str->data());
  }
  return obj;
}

/*!
 * Print method for string.  Prints the string in quotes.
 */
u64 print_string(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) ||
      *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_STRING_TYPE)) {
    cprintf("#<invalid string #x%x>", obj);
  } else {
    cprintf("\"%s\"", Ptr<String>(obj)->data());
  }
  return obj;
}

/*!
 * Print method for function. Just prints the address because functions can't identify themselves.
 */
u64 print_function(u32 obj) {
  cprintf("#<compiled %s @ #x%x>", info(Ptr<Type>(*Ptr<u32>(obj - 4))->symbol)->str->data(), obj);
  return obj;
}

/*!
 * Get the allocated size field of a basic.  By default we grab this from the type struct.
 * Dynamically sized basics should override this method.
 */
u64 asize_of_basic(u32 it) {
  return Ptr<Type>(*Ptr<u32>(it - BASIC_OFFSET))->allocated_size;
}

/*!
 * Create a copy of a basic.  If the destination isn't identified as a symbol, treat it as an
 * address. This seems a little bit unsafe to me, as it reads the 4-bytes before the given address
 * and checks it against the symbol type pointer to see if its a symbol. It seems possible to have a
 * false positive for this check.
 */
u64 copy_basic(u32 obj, u32 heap, u32 /*unused*/, u32 pp) {
  // determine size of basic. We call a method instead of using asize_of_basic in case the type has
  // overridden the default asize_of method.
  u32 size = call_method_of_type(obj, Ptr<Type>(*Ptr<u32>(obj - BASIC_OFFSET)), GOAL_ASIZE_METHOD);
  u32 result;

  if (*Ptr<u32>(heap - 4) == *(s7 + FIX_SYM_SYMBOL_TYPE)) {
    // we think we're creating a new copy on a heap.  First allocate memory...
    result = alloc_heap_object(heap, *Ptr<u32>(obj - BASIC_OFFSET), size, pp);
    // then copy! (minus the type tag, alloc_heap_object already did it for us)
    memcpy(Ptr<u32>(result).c(), Ptr<u32>(obj).c(), size - BASIC_OFFSET);
  } else {
    printf("DANGER COPY BASIC!\n");
    // copy directly (including type tag)
    memcpy(Ptr<u32>(heap - BASIC_OFFSET).c(), Ptr<u32>(obj - BASIC_OFFSET).c(), size);
    result = heap;
  }
  return result;
}

u64 inspect_pair(u32 obj);

/*!
 * Highest level inspect method. Won't inspect 64-bit bintegers correctly.
 */
u64 inspect_object(u32 obj) {
  if ((obj & OFFSET_MASK) == BINTEGER_OFFSET) {
    return inspect_binteger(obj);
  } else {
    if ((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
        (obj < 0x84000 || 0x100000 <= obj)) {              // not in kernel memory
      cprintf("#<invalid object #x%x>", obj);
    } else if ((obj & OFFSET_MASK) == PAIR_OFFSET) {
      return inspect_pair(obj);
    } else if ((obj & OFFSET_MASK) == BASIC_OFFSET) {
      return call_method_of_type(obj, Ptr<Type>(*Ptr<u32>(obj - BASIC_OFFSET)),
                                 GOAL_INSPECT_METHOD);
    } else {
      cprintf("#<unknown type %d @ #x%x>", obj & OFFSET_MASK, obj);
    }
  }
  return obj;
}

/*!
 * Inspect a pair.
 */
u64 inspect_pair(u32 obj) {
  cprintf("[%8x] pair ", obj);
  print_pair(obj);
  cprintf("\n");
  return obj;
}

/*!
 * Inspect a string. There's a typo in allocated_length (has underscore instead of dash).
 * This typo is fixed in later games.
 */
u64 inspect_string(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) ||
      *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_STRING_TYPE)) {
    cprintf("#<invalid string #x%x>\n", obj);
  } else {
    auto str = Ptr<String>(obj);
    cprintf("[%8x] string\n\tallocated_length: %d\n\tdata: \"%s\"\n", obj, str->len, str->data());
  }
  return obj;
}

/*!
 * Inspect a symbol.
 */
u64 inspect_symbol(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) ||
      *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_SYMBOL_TYPE)) {
    cprintf("#<invalid symbol #x%x>", obj);
  } else {
    auto sym = Ptr<Symbol>(obj);
    auto inf = info(sym);
    cprintf("[%8x] symbol\n\tname: %s\n\thash: #x%x\n\tvalue: ", obj, inf->str->data(), inf->hash);
    print_object(sym->value);
    cprintf("\n");
  }
  return obj;
}

/*!
 * Inspect a type.
 */
u64 inspect_type(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET) || *Ptr<u32>(obj - 4) != *(s7 + FIX_SYM_TYPE_TYPE)) {
    cprintf("#<invalid type #x%x>\n", obj);
  } else {
    auto typ = Ptr<Type>(obj);
    auto sym = typ->symbol;
    auto inf = info(sym);

    cprintf("[%8x] type\n\tname: %s\n\tparent: ", obj, inf->str->data());
    print_object(typ->parent.offset);
    cprintf("\n\tsize: %d/%d\n\theap-base: %d\n\tallocated_length: %d\n\tprint: ",
            typ->allocated_size, typ->padded_size, typ->heap_base, typ->num_methods);
    print_object(typ->print_method.offset);
    cprintf("\n\tinspect: ");
    print_object(typ->inspect_method.offset);
    cprintf("\n");
  }
  return obj;
}

/*!
 * Inspect a basic. This is just a fallback for basics which don't know how to inspect themselves.
 * We just use print_object.
 */
u64 inspect_basic(u32 obj) {
  if (((obj < SymbolTable2.offset || 0x7ffffff < obj) &&  // not in normal memory
       (obj < 0x84000 || 0x100000 <= obj))                // not in kernel memory
      || ((obj & OFFSET_MASK) != BASIC_OFFSET)) {
    cprintf("#<invalid basic #x%x>\n", obj);
  } else {
    cprintf("[%8x] ", obj);
    print_object(*Ptr<u32>(obj - 4));
    cprintf("\n");
  }
  return obj;
}

/*!
 * Inspect a link block. This link block doesn't seem to be used at all.
 */
u64 inspect_link_block(u32 ob) {
  struct LinkBlock {
    u32 length;
    u32 version;
  };

  auto lb = Ptr<LinkBlock>(ob);
  cprintf("[%8x] link-block\n\tallocated_length: %d\n\tversion: %d\n\tfunction: ", ob, lb->length,
          lb->version);
  print_object(ob + lb->length);
  cprintf("\n");
  return ob;
}

/*!
 * Doesn't exist in the game. Maybe it was a macro?
 */
u64 pack_type_flag(u64 methods, u64 heap_base, u64 size) {
  return (methods << 32) + (heap_base << 16) + (size);
}

/*!
 * TODO remove me!
 */
s32 test_function(s32 arg0, s32 arg1, s32 arg2, s32 arg3) {
  return arg0 + 2 * arg1 + 3 * arg2 + 4 * arg3;
}

/*!
 * Initializes the GOAL Heap, GOAL Symbol Table, GOAL Funcdamental Types, loads the GOAL kernel,
 * exports Machine functions, loads the game engine, and calls "play" to initialize the engine.
 *
 * This takes care of all initialization that isn't for the hardware itself.
 */
s32 InitHeapAndSymbol() {
  Timer heap_init_timer;
  // reset all mips2c functions
  Mips2C::gLinkedFunctionTable = {};
  // allocate memory for the symbol table
  auto symbol_table =
      kmalloc(kglobalheap, jak1::SYM_TABLE_MEM_SIZE, KMALLOC_MEMSET, "symbol-table").cast<u32>();

  // pointer to the middle symbol is stored in the s7 register.
  s7 = symbol_table + (jak1::GOAL_MAX_SYMBOLS / 2) * 8 + BASIC_OFFSET;
  // pointer to the first symbol (SymbolTable2 is the "lower" symbol table)
  SymbolTable2 = symbol_table + BASIC_OFFSET;
  // the last symbol we will ever access.
  LastSymbol = symbol_table + SYM_TABLE_END * 8;
  NumSymbols = 0;
  // inform compiler the symbol table is reset, and where it is.
  reset_output();

  // set up the empty pair:
  *(s7 + FIX_SYM_EMPTY_CAR) = (s7 + FIX_SYM_EMPTY_PAIR).offset;
  *(s7 + FIX_SYM_EMPTY_CDR) = (s7 + FIX_SYM_EMPTY_PAIR).offset;

  // need to set up 'global fixed symbol so allocating memory works.
  *(s7 + FIX_SYM_GLOBAL_HEAP) = kglobalheap.offset;

  // allocate fundamental types
  alloc_and_init_type((s7 + FIX_SYM_TYPE_TYPE).cast<Symbol>(), 9);
  alloc_and_init_type((s7 + FIX_SYM_SYMBOL_TYPE).cast<Symbol>(), 9);
  alloc_and_init_type((s7 + FIX_SYM_STRING_TYPE).cast<Symbol>(), 9);
  alloc_and_init_type((s7 + FIX_SYM_FUNCTION_TYPE).cast<Symbol>(), 9);

  // booleans
  set_fixed_symbol(FIX_SYM_FALSE, "#f", s7.offset + FIX_SYM_FALSE);
  set_fixed_symbol(FIX_SYM_TRUE, "#t", s7.offset + FIX_SYM_TRUE);

  // functions
  set_fixed_symbol(FIX_SYM_NOTHING_FUNC, "nothing", make_nothing_func().offset);
  set_fixed_symbol(FIX_SYM_ZERO_FUNC, "zero-func", make_zero_func().offset);
  set_fixed_symbol(FIX_SYM_ASIZE_OF_BASIC_FUNC, "asize-of-basic-func",
                   make_function_from_c((void*)asize_of_basic).offset);
  // NOTE: this is a typo in the game too.
  set_fixed_symbol(FIX_SYM_COPY_BASIC_FUNC, "asize-of-basic-func",
                   make_function_from_c((void*)copy_basic, true).offset);
  set_fixed_symbol(FIX_SYM_DEL_BASIC_FUNC, "delete-basic",
                   make_function_from_c((void*)delete_basic).offset);

  // heap symbols
  set_fixed_symbol(FIX_SYM_GLOBAL_HEAP, "global", kglobalheap.offset);
  set_fixed_symbol(FIX_SYM_DEBUG_HEAP, "debug", kdebugheap.offset);
  set_fixed_symbol(FIX_SYM_STATIC, "static", (s7 + FIX_SYM_STATIC).offset);
  set_fixed_symbol(FIX_SYM_LOADING_LEVEL, "loading-level", kglobalheap.offset);
  set_fixed_symbol(FIX_SYM_LOADING_PACKAGE, "loading-package", kglobalheap.offset);
  set_fixed_symbol(FIX_SYM_PROCESS_LEVEL_HEAP, "process-level-heap", kglobalheap.offset);
  set_fixed_symbol(FIX_SYM_STACK, "stack", (s7 + FIX_SYM_STACK).offset);
  set_fixed_symbol(FIX_SYM_SCRATCH, "scratch", (s7 + FIX_SYM_SCRATCH).offset);
  set_fixed_symbol(FIX_SYM_SCRATCH_TOP, "*scratch-top*", 0x70000000);

  // level stuff
  set_fixed_symbol(FIX_SYM_LEVEL, "level", 0);
  set_fixed_symbol(FIX_SYM_ART_GROUP, "art-group", 0);
  set_fixed_symbol(FIX_SYM_TX_PAGE_DIR, "texture-page-dir", 0);
  set_fixed_symbol(FIX_SYM_TX_PAGE, "texture-page", 0);
  set_fixed_symbol(FIX_SYM_SOUND, "sound", 0);
  set_fixed_symbol(FIX_SYM_DGO, "dgo", 0);
  set_fixed_symbol(FIX_SYM_TOP_LEVEL, "top-level", *(s7 + FIX_SYM_NOTHING_FUNC));

  // OBJECT type
  auto new_illegal_func = make_function_from_c((void*)new_illegal);
  auto delete_illegal_func = make_function_from_c((void*)delete_illegal);
  auto print_object_func = make_function_from_c((void*)print_object);
  auto inspect_object_func = make_function_from_c((void*)inspect_object);
  set_fixed_type(FIX_SYM_OBJECT_TYPE, "object", (s7 + FIX_SYM_OBJECT_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), print_object_func.offset, inspect_object_func.offset);
  auto object_type = Ptr<Type>(*(s7 + FIX_SYM_OBJECT_TYPE));
  object_type->new_method = new_illegal_func;
  object_type->delete_method = delete_illegal_func;
  object_type->asize_of_method.offset = *(s7 + FIX_SYM_ZERO_FUNC);
  auto copy_fixed_function = make_function_from_c((void*)copy_fixed);
  object_type->copy_method = copy_fixed_function;

  // STRUCTURE type
  auto print_structure_func = make_function_from_c((void*)print_structure);
  auto inspect_structure_func = make_function_from_c((void*)inspect_structure);
  set_fixed_type(FIX_SYM_STRUCTURE_TYPE, "structure", (s7 + FIX_SYM_OBJECT_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), print_structure_func.offset,
                 inspect_structure_func.offset);
  auto new_structure_func = make_function_from_c((void*)new_structure);
  auto delete_structure_func = make_function_from_c((void*)delete_structure);
  auto structureType = Ptr<Type>(*(s7 + FIX_SYM_STRUCTURE_TYPE));
  structureType->new_method = new_structure_func;
  structureType->delete_method = delete_structure_func;

  // BASIC type
  auto print_basic_func = make_function_from_c((void*)print_basic);
  auto inspect_basic_function = make_function_from_c((void*)inspect_basic);
  set_fixed_type(FIX_SYM_BASIC_TYPE, "basic", (s7 + FIX_SYM_STRUCTURE_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), print_basic_func.offset, inspect_basic_function.offset);
  auto new_basic_func = make_function_from_c((void*)new_basic, true);
  auto basicType = Ptr<Type>(*(s7 + FIX_SYM_BASIC_TYPE));
  basicType->new_method = new_basic_func;
  basicType->delete_method.offset = *(s7 + FIX_SYM_DEL_BASIC_FUNC);
  basicType->asize_of_method.offset = *(s7 + FIX_SYM_ASIZE_OF_BASIC_FUNC);
  basicType->copy_method.offset = *(s7 + FIX_SYM_COPY_BASIC_FUNC);

  // SYMBOL type
  auto print_symbol_func = make_function_from_c((void*)print_symbol);
  auto inspect_symbol_func = make_function_from_c((void*)inspect_symbol);
  set_fixed_type(FIX_SYM_SYMBOL_TYPE, "symbol", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), print_symbol_func.offset, inspect_symbol_func.offset);
  auto symbolType = Ptr<Type>(*(s7 + FIX_SYM_SYMBOL_TYPE));
  symbolType->new_method = new_illegal_func;
  symbolType->delete_method = delete_illegal_func;

  // TYPE type
  auto print_type_func = make_function_from_c((void*)print_type);
  auto inspect_type_func = make_function_from_c((void*)inspect_type);
  set_fixed_type(FIX_SYM_TYPE_TYPE, "type", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x38), print_type_func.offset, inspect_type_func.offset);
  auto typeType = Ptr<Type>(*(s7 + FIX_SYM_TYPE_TYPE));
  auto new_type_func = make_function_from_c((void*)new_type);
  typeType->new_method = new_type_func;
  typeType->delete_method = delete_illegal_func;

  // STRING type
  auto print_string_func = make_function_from_c((void*)print_string);
  auto inspect_string_func = make_function_from_c((void*)inspect_string);
  set_fixed_type(FIX_SYM_STRING_TYPE, "string", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), print_string_func.offset, inspect_string_func.offset);

  // FUNCTION type
  auto print_function_func = make_function_from_c((void*)print_function);
  set_fixed_type(FIX_SYM_FUNCTION_TYPE, "function", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), print_function_func.offset, 0);

  // VU FUNCTION type
  auto print_vu_function_func = make_function_from_c((void*)print_vu_function);
  auto inspect_vu_function_func = make_function_from_c((void*)inspect_vu_function);
  set_fixed_type(FIX_SYM_VU_FUNCTION_TYPE, "vu-function",
                 (s7 + FIX_SYM_STRUCTURE_TYPE).cast<Symbol>(), pack_type_flag(9, 0, 0x10),
                 print_vu_function_func.offset, inspect_vu_function_func.offset);

  // LINK BLOCK type
  auto inspect_link_block_func = make_function_from_c((void*)inspect_link_block);
  set_fixed_type(FIX_SYM_LINK_BLOCK, "link-block", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0xc), 0, inspect_link_block_func.offset);
  auto linkBlockType = Ptr<Type>(*(s7 + FIX_SYM_LINK_BLOCK));
  linkBlockType->new_method = new_illegal_func;
  linkBlockType->delete_method = delete_illegal_func;

  // KHEAP
  auto inspect_kheap_func = make_function_from_c((void*)inspect_kheap);
  set_fixed_type(FIX_SYM_KHEAP, "kheap", (s7 + FIX_SYM_STRUCTURE_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x10), 0, inspect_kheap_func.offset);

  // ARRAY
  set_fixed_type(FIX_SYM_ARRAY_TYPE, "array", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x10), 0, 0);

  // PAIR
  auto print_pair_func = make_function_from_c((void*)print_pair);
  auto inspect_pair_func = make_function_from_c((void*)inspect_pair);
  set_fixed_type(FIX_SYM_PAIR_TYPE, "pair", (s7 + FIX_SYM_OBJECT_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), print_pair_func.offset, inspect_pair_func.offset);
  auto pairType = Ptr<Type>(*(s7 + FIX_SYM_PAIR_TYPE));
  auto new_pair_func = make_function_from_c((void*)new_pair);
  auto delete_pair_func = make_function_from_c((void*)delete_pair);
  pairType->new_method = new_pair_func;
  pairType->delete_method = delete_pair_func;

  // KERNEL TYPES
  set_fixed_type(FIX_SYM_PROCESS_TREE_TYPE, "process-tree",
                 (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(), pack_type_flag(0xe, 0, 0x20), 0, 0);
  set_fixed_type(FIX_SYM_PROCESS_TYPE, "process", (s7 + FIX_SYM_PROCESS_TREE_TYPE).cast<Symbol>(),
                 pack_type_flag(0xe, 0, 0x70), 0, 0);
  set_fixed_type(FIX_SYM_THREAD_TYPE, "thread", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(0xc, 0, 0x28), 0, 0);
  set_fixed_type(FIX_SYM_CONNECTABLE_TYPE, "connectable",
                 (s7 + FIX_SYM_STRUCTURE_TYPE).cast<Symbol>(), pack_type_flag(9, 0, 0x10), 0, 0);
  set_fixed_type(FIX_SYM_STACK_FRAME_TYPE, "stack-frame", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0xc), 0, 0);
  set_fixed_type(FIX_SYM_FILE_STREAM_TYPE, "file-stream", (s7 + FIX_SYM_BASIC_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x14), 0, 0);

  // NUMERIC TYPES
  set_fixed_type(FIX_SYM_POINTER_TYPE, "pointer", (s7 + FIX_SYM_OBJECT_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), 0, 0);

  // NUMERIC TYPES
  auto print_integer_func = make_function_from_c((void*)print_integer);
  auto inspect_integer_func = make_function_from_c((void*)inspect_integer);
  set_fixed_type(FIX_SYM_NUMBER_TYPE, "number", (s7 + FIX_SYM_OBJECT_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), print_integer_func.offset, inspect_integer_func.offset);

  auto print_float_func = make_function_from_c((void*)print_float);
  auto inspect_float_func = make_function_from_c((void*)inspect_float);
  set_fixed_type(FIX_SYM_FLOAT_TYPE, "float", (s7 + FIX_SYM_NUMBER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), print_float_func.offset, inspect_float_func.offset);

  set_fixed_type(FIX_SYM_INTEGER_TYPE, "integer", (s7 + FIX_SYM_NUMBER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), 0, 0);

  auto print_binteger_func = make_function_from_c((void*)print_binteger);
  auto inspect_binteger_func = make_function_from_c((void*)inspect_binteger);
  set_fixed_type(FIX_SYM_BINTEGER_TYPE, "binteger", (s7 + FIX_SYM_INTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), print_binteger_func.offset, inspect_binteger_func.offset);

  set_fixed_type(FIX_SYM_SINTEGER_TYPE, "sinteger", (s7 + FIX_SYM_INTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), 0, 0);
  set_fixed_type(FIX_SYM_INT8_TYPE, "int8", (s7 + FIX_SYM_SINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 1), 0, 0);
  set_fixed_type(FIX_SYM_INT16_TYPE, "int16", (s7 + FIX_SYM_SINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 2), 0, 0);
  set_fixed_type(FIX_SYM_INT32_TYPE, "int32", (s7 + FIX_SYM_SINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), 0, 0);
  set_fixed_type(FIX_SYM_INT64_TYPE, "int64", (s7 + FIX_SYM_SINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), 0, 0);
  set_fixed_type(FIX_SYM_INT128_TYPE, "int128", (s7 + FIX_SYM_SINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x10), 0, 0);

  set_fixed_type(FIX_SYM_UINTEGER_TYPE, "uintger", (s7 + FIX_SYM_INTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), 0, 0);
  set_fixed_type(FIX_SYM_UINT8_TYPE, "uint8", (s7 + FIX_SYM_UINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 1), 0, 0);
  set_fixed_type(FIX_SYM_UINT16_TYPE, "uint16", (s7 + FIX_SYM_UINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 2), 0, 0);
  set_fixed_type(FIX_SYM_UINT32_TYPE, "uint32", (s7 + FIX_SYM_UINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 4), 0, 0);
  set_fixed_type(FIX_SYM_UINT64_TYPE, "uint64", (s7 + FIX_SYM_UINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 8), 0, 0);
  set_fixed_type(FIX_SYM_UINT128_TYPE, "uint128", (s7 + FIX_SYM_UINTEGER_TYPE).cast<Symbol>(),
                 pack_type_flag(9, 0, 0x10), 0, 0);

  // Object new macro
  auto goal_new_object_func = make_function_from_c((void*)alloc_heap_object, true);
  object_type->new_method = goal_new_object_func;

  // Stuff that isn't in a fixed spot:
  make_function_symbol_from_c("string->symbol", (void*)intern);
  make_function_symbol_from_c("print", (void*)sprint);
  make_function_symbol_from_c("inspect", (void*)inspect_object);

  // loads
  make_function_symbol_from_c("load", (void*)load);
  make_function_symbol_from_c("loado", (void*)loado);
  make_function_symbol_from_c("unload", (void*)unload);
  make_stack_arg_function_symbol_from_c("_format", (void*)format_impl_jak1);

  // allocations
  make_function_symbol_from_c("malloc", (void*)alloc_heap_memory);
  make_function_symbol_from_c("kmalloc", (void*)goal_malloc);
  make_function_symbol_from_c("new-dynamic-structure", (void*)new_dynamic_structure);

  // type system
  make_function_symbol_from_c("method-set!", (void*)method_set);

  // dgo
  make_stack_arg_function_symbol_from_c("link", (void*)link_and_exec_wrapper);
  make_function_symbol_from_c("dgo-load", (void*)load_and_link_dgo);

  // forward declare
  make_raw_function_symbol_from_c("ultimate-memcpy", 0);
  make_raw_function_symbol_from_c("memcpy-and-rellink", 0);  // never used
  make_raw_function_symbol_from_c("symlink2", 0);
  make_raw_function_symbol_from_c("symlink3", 0);

  // game stuff
  make_stack_arg_function_symbol_from_c("link-begin", (void*)link_begin);
  make_function_symbol_from_c("link-resume", (void*)link_resume);
  make_function_symbol_from_c("mc-run", (void*)MC_run);
  make_function_symbol_from_c("mc-format", (void*)MC_format);
  make_function_symbol_from_c("mc-unformat", (void*)MC_unformat);
  make_function_symbol_from_c("mc-create-file", (void*)MC_createfile);
  make_function_symbol_from_c("mc-save", (void*)MC_save);
  make_function_symbol_from_c("mc-load", (void*)MC_load);
  make_function_symbol_from_c("mc-check-result", (void*)MC_check_result);
  make_function_symbol_from_c("mc-get-slot-info", (void*)MC_get_status);
  make_function_symbol_from_c("mc-makefile", (void*)MC_makefile);
  make_function_symbol_from_c("kset-language", (void*)MC_set_language);

  // set *debug-segment*
  auto ds_symbol = intern_from_c("*debug-segment*");
  if (DebugSegment) {
    ds_symbol->value = (s7 + FIX_SYM_TRUE).offset;
  } else {
    ds_symbol->value = (s7 + FIX_SYM_FALSE).offset;
  }

  // setup *enable-method-set*
  auto method_set_symbol = intern_from_c("*enable-method-set*");
  EnableMethodSet = method_set_symbol.cast<u32>();
  method_set_symbol->value = 0;

  // set *boot-video-mode*
  intern_from_c("*boot-video-mode*")->value = 0;  // (u32)BootVideoMode;

  lg::info("Initialized GOAL heap in {:.2} ms", heap_init_timer.getMs());
  // load the kernel!
  if (MasterUseKernel) {
    Timer kernel_load_timer;
    method_set_symbol->value++;
    load_and_link_dgo_from_c("kernel", kglobalheap,
                             LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN,
                             0x400000, true);
    method_set_symbol->value--;

    // Phase E1 (autoport): optional hook that runs AFTER the kernel CGO
    // load and BEFORE the version check. Android installs a hook that
    // pre-populates *kernel-version* to the value gkernel's top-level
    // would have written (the top-level is skip-flagged on arm64 until
    // the goalc off-register emitter bug is fixed). Desktop leaves the
    // pointer null and behaviour is unchanged. See
    // android/android_runtime_compat.cpp::android_pre_kernel_version_hook
    // for the Android side.
    if (g_jak1_pre_kernel_version_check_hook) {
      g_jak1_pre_kernel_version_check_hook();
    }

    // check the kernel version!
    auto kernel_version = intern_from_c("*kernel-version*")->value;
    if (!kernel_version || ((kernel_version >> 0x13) != KERNEL_VERSION_MAJOR)) {
      lg::error(
          "Kernel version mismatch! Compiled C kernel version is {}.{} but"
          "the goal kernel is {}.{}",
          KERNEL_VERSION_MAJOR, KERNEL_VERSION_MINOR, kernel_version >> 0x13,
          (kernel_version >> 3) & 0xffff);
      return -1;
    } else {
      lg::info("Got correct kernel version {}.{}, loaded in {:.2} ms", kernel_version >> 0x13,
               (kernel_version >> 3) & 0xffff, kernel_load_timer.getMs());
    }
  }

  // setup deci2count for message counter.
  protoBlock.deci2count = intern_from_c("*deci-count*").cast<s32>();

  // load stuff for the listener interface
  InitListener();

  // Do final initialization, including loading and initializing the engine.
  jak1::InitMachineScheme();

  // testing stuff:
  make_function_symbol_from_c("test-function", (void*)test_function);

  return 0;
}

/*!
 * GOAL "load" function for debug loads. Doesn't load off the CD.
 */
u64 load(u32 file_name_in, u32 heap_in) {
  printf("LOAD!\n");  // added by me
  Ptr<String> file_name(file_name_in);
  Ptr<kheapinfo> heap(heap_in);
  char decodedName[260];  // could be 256 or 260?

  auto loading_pack_sym = Ptr<Symbol>(s7.offset + FIX_SYM_LOADING_PACKAGE);
  auto last_loading_pack = loading_pack_sym->value;
  loading_pack_sym->value = heap_in;

  kstrcpy(decodedName, DecodeFileName(file_name->data()));
  s32 returnValue = load_and_link(
      file_name->data(), decodedName, heap.c(),
      LINK_FLAG_OUTPUT_TRUE | LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN);

  loading_pack_sym->value = last_loading_pack;

  if (returnValue < 0) {
    return s7.offset;
  } else {
    return returnValue;
  }
}

/*!
 * Unused. But a C version of loading code. Doesn't load off the CD.
 */
u64 loadc(const char* file_name, kheapinfo* heap, u32 flags) {
  char decodedName[260];  // could be 256 or 260?

  auto loading_pack_sym = Ptr<Symbol>(s7.offset + FIX_SYM_LOADING_PACKAGE);
  auto last_loading_pack = loading_pack_sym->value;
  loading_pack_sym->value = make_ptr(heap).offset;
  printf("****** CALL TO loadc() ******\n");  // not added by me
  auto name = MakeFileName(CODE_FILE_TYPE, file_name, 0);
  kstrcpy(decodedName, name);

  s32 returnValue = load_and_link(file_name, decodedName, heap, flags);

  loading_pack_sym->value = last_loading_pack;

  if (returnValue < 0) {
    return s7.offset;
  } else {
    return returnValue;
  }
}

/*!
 * Load Object? Uses DATA_FILE_TYPE and doesn't inform listener about the load, or execute a
 * top level segment if a V3 is loaded. Doesn't load off the CD.
 * This is used in some debug code to load art-groups directly.
 */
u64 loado(u32 file_name_in, u32 heap_in) {
  char loadName[272];
  Ptr<String> file_name(file_name_in);
  Ptr<kheapinfo> heap(heap_in);
  printf("****** CALL TO loado(%s) ******\n", file_name->data());
  kstrcpy(loadName, MakeFileName(DATA_FILE_TYPE, file_name->data(), 0));
  s32 returnValue = load_and_link(file_name->data(), loadName, heap.c(), LINK_FLAG_PRINT_LOGIN);

  if (returnValue < 0) {
    return s7.offset;
  } else {
    return returnValue;
  }
}

/*!
 * "Unload". Doesn't free memory, just informs listener we unloaded.
 */
u64 unload(u32 name) {
  output_unload(Ptr<String>(name)->data());
  return 0;
}

/*!
 * load and link and exec.  Common function in load/loado/loadc.
 * Doesn't load off the CD.
 */
s64 load_and_link(const char* filename, char* decode_name, kheapinfo* heap, u32 flags) {
  (void)filename;
  s32 sz;
  auto rv = FileLoad(decode_name, make_ptr(heap), Ptr<u8>(0), KMALLOC_ALIGN_64, &sz);
  if (((s32)rv.offset) > -1) {
    return (s32)link_and_exec(rv, decode_name, sz, make_ptr(heap), flags, false).offset;
  }
  return (s32)rv.offset;
}

}  // namespace jak1
