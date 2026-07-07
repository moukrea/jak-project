#include "kscheme.h"

#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/runtime_trace.h"

// Gjak2-render concurrent-GOAL race experiment (see kscheme.h). Definitions of
// the shared cross-thread flags used by the klink top-level exec, the GL-thread
// vif_interrupt_callback, and the crash handler.
std::atomic<int> g_goal_active{0};
std::atomic<bool> g_goal_boot_linking{false};

// total number of symbols in the table
s32 NumSymbols;

// value of the GOAL s7 register, pointing to the middle of the symbol table
Ptr<u32> s7;

// used for crc32 calculation
u32 crc_table[0x100];

// pointer to the "second" symbol table
Ptr<u32> SymbolTable2;

// pointer to the last symbol
Ptr<u32> LastSymbol;

//! Controls link mode when EnableMethodSet = 0, MasterDebug = 1, DiskBoot = 0. Will enable a
//! warning message if EnableMethodSet = 1
u32 FastLink;

// set to true to enable propagating method overrides to child types
// this is an O(N_max_symbols) operation, so it is avoided when loading DGOs for levels.
// but is enabled when loading the engine.
Ptr<u32> EnableMethodSet;

void kscheme_init_globals_common() {
  SymbolTable2.offset = 0;
  LastSymbol.offset = 0;
  NumSymbols = 0;
  s7.offset = 0;
  for (auto& x : crc_table) {
    x = 0;
  }
  EnableMethodSet.offset = 0;
  FastLink = 0;
}

/*!
 * Initialize CRC Table.
 */
void init_crc() {
  for (u32 i = 0; i < 0x100; i++) {
    u32 n = i << 24;
    for (u32 j = 0; j < 8; j++) {
      n = n & 0x80000000 ? (n << 1) ^ CRC_POLY : (n << 1);
    }
    crc_table[i] = n;
  }
}

/*!
 * Take the CRC32 hash of some data
 */
u32 crc32(const u8* data, s32 size) {
  uint32_t crc = 0;
  for (int i = size; i != 0; i--, data++) {
    crc = crc_table[crc >> 24] ^ ((crc << 8) | *data);
  }

  ASSERT(~crc);
  return ~crc;
}

/*!
 * Delete method for types which cannot have "delete" used on them.
 * Prints an error to stdout and returns false.
 */
u64 delete_illegal(u32 obj) {
  MsgErr("dkernel: illegal attempt to call delete method of static object @ #x%x\n", obj);
  return s7.offset;  // todo, maybe don't return anything?
}

/*!
 * Wrapper around kmalloc to allow GOAL programs to allocate on kernel heaps.
 */
u64 goal_malloc(u32 heap, u32 size, u32 flags, u32 name) {
  return kmalloc(Ptr<kheapinfo>(heap), size, flags, Ptr<String>(name)->data()).offset;
}

extern "C" {
// defined in asm_funcs.asm / asm_funcs_arm64.s
#if defined(__linux__) && defined(__aarch64__)
// Phase 26 (autoport): aarch64-linux dispatch uses the AArch64 trampoline
// from game/kernel/asm_funcs_arm64.s. The symbol names differ from the
// x86-64 SysV ones (no "_systemv" suffix); calling code below dispatches
// via the same wrapper names.
uint64_t _call_goal_asm_arm64(u64 a0, u64 a1, u64 a2, void* fptr, void* st_ptr, void* offset);
uint64_t _call_goal_on_stack_asm_arm64(u64 rsp,
                                       u64 u0,
                                       u64 u1,
                                       void* fptr,
                                       void* st_ptr,
                                       void* offset);
#elif defined(__linux__)
uint64_t _call_goal_asm_systemv(u64 a0, u64 a1, u64 a2, void* fptr, void* st_ptr, void* offset);
uint64_t _call_goal_on_stack_asm_systemv(u64 rsp,
                                         u64 u0,
                                         u64 u1,
                                         void* fptr,
                                         void* st_ptr,
                                         void* offset);
#elif defined __APPLE__ && defined __x86_64__
uint64_t _call_goal_asm_systemv(u64 a0, u64 a1, u64 a2, void* fptr, void* st_ptr, void* offset) asm(
    "_call_goal_asm_systemv");
uint64_t _call_goal_on_stack_asm_systemv(u64 rsp,
                                         u64 u0,
                                         u64 u1,
                                         void* fptr,
                                         void* st_ptr,
                                         void* offset) asm("_call_goal_on_stack_asm_systemv");
#elif _WIN32
uint64_t _call_goal_asm_win32(u64 a0, u64 a1, u64 a2, void* fptr, void* st_ptr, void* offset);
uint64_t _call_goal_on_stack_asm_win32(u64 rsp, void* fptr, void* st_ptr, void* offset);
#endif
}

/*!
 * Wrapper around _call_goal_asm for calling a GOAL function from C.
 * Calls from the parent stack.
 */
u64 call_goal(Ptr<Function> f, u64 a, u64 b, u64 c, u64 st, void* offset) {
  // auto st_ptr = (void*)((uint8_t*)(offset) + st); updated for the new compiler!
  void* st_ptr = (void*)st;

  void* fptr = f.c();
  // Phase 26 trace hook: a dispatcher hand-off into GOAL is happening.
  __goal_runtime_trace_goal_call();
#if defined(__linux__) && defined(__aarch64__)
  // A11 attempt-3 runtime/FFI bridge — close the C→GOAL→C arg-shuffle gap
  // that surfaces at surface-h's `(copy *walk-mods* 'global)` top-level.
  //
  // The chain copy_basic→call_method_of_type→call_goal→(asize-of-basic-func
  // wrapper made by make_function_from_c_arm64) traps in
  // `Ptr<Type>::operator->()` ASSERT(offset) because the wrapper does
  // GOAL→AAPCS arg shuffle (X0←X7, X1←X6) expecting goalc's GOAL ABI, but
  // _call_goal_asm_arm64 (asm_funcs_arm64.s) passes args in AAPCS X0/X1/X2
  // without an AAPCS→GOAL pre-shuffle. The wrapper therefore pulls junk from
  // X7/X6 and asize_of_basic receives a garbage `it`.
  //
  // goalc's m_gpr_arg_regs (Register.cpp:44) is the x86 SystemV enum
  //   {RDI(7), RSI(6), RDX(2), RCX(1), R8(8), R9(9), R10(10), R11(11)}
  // — the enum IDs map directly to arm64 X-register numbers, so GOAL passes
  // arg0 in X7, arg1 in X6, arg2 in X2 (matches AAPCS), arg3 in X1, ...
  //
  // _call_goal_asm_arm64's body only touches X0–X5 (its AAPCS inputs),
  // X13/X14/X15 (the goalc-arm64 sym-table/ee-base regs), and X19–X28
  // (callee-saved spills); X6 and X7 are NOT clobbered between its prologue
  // and the `blr x3`. So if we set X7=a, X6=b here, those values reach the
  // wrapped function's entry intact and the wrapper's X0←X7, X1←X6 shuffle
  // produces the correct AAPCS args.
  //
  // call_goal_on_stack (used for CGO top-levels via call_goal_on_stack_*) is
  // NOT touched by this fix — top-levels are 0-arg so they don't need a
  // shuffle, and modifying that path was implicated in A11 attempt-2's
  // 104→89 regression (see SUPERVISOR_JOURNAL).
  //
  // This lives in C inline asm so asm_funcs_arm64.s (codegen-owned, locked
  // in A11) stays untouched.
  uint64_t result;
  asm volatile(
      "mov x0, %1\n\t"
      "mov x1, %2\n\t"
      "mov x2, %3\n\t"
      "mov x3, %4\n\t"
      "mov x4, %5\n\t"
      "mov x5, %6\n\t"
      "mov x7, %1\n\t"  // GOAL arg0 mirror (m_gpr_arg_regs[0] = RDI = X7)
      "mov x6, %2\n\t"  // GOAL arg1 mirror (m_gpr_arg_regs[1] = RSI = X6)
      "bl _call_goal_asm_arm64\n\t"
      "mov %0, x0"
      : "=&r"(result)
      : "r"(a), "r"(b), "r"(c), "r"(fptr), "r"(st_ptr), "r"(offset)
      : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10",
        "x11", "x12", "x13", "x14", "x15", "x16", "x17", "x30",
        "memory", "cc");
  return result;
#elif defined(__linux__)
  return _call_goal_asm_systemv(a, b, c, fptr, st_ptr, offset);
#elif defined __APPLE__ && defined __x86_64__
  return _call_goal_asm_systemv(a, b, c, fptr, st_ptr, offset);
#elif _WIN32
  return _call_goal_asm_win32(a, b, c, fptr, st_ptr, offset);
#endif
}

/*!
 * Wrapper around _call_goal_asm_on_stack for switching stacks and calling a GOAL function there.
 */
u64 call_goal_on_stack(Ptr<Function> f, u64 rsp, u64 st, void* offset) {
  void* st_ptr = (void*)st;

  void* fptr = f.c();
  // Phase 26 trace hook: a dispatcher hand-off into GOAL is happening.
  __goal_runtime_trace_goal_call();
#if defined(__linux__) && defined(__aarch64__)
  return _call_goal_on_stack_asm_arm64(rsp, 0, 0, fptr, st_ptr, offset);
#elif defined(__linux__)
  return _call_goal_on_stack_asm_systemv(rsp, 0, 0, fptr, st_ptr, offset);
#elif defined __APPLE__ && defined __x86_64__
  return _call_goal_on_stack_asm_systemv(rsp, 0, 0, fptr, st_ptr, offset);
#elif _WIN32
  return _call_goal_on_stack_asm_win32(rsp, fptr, st_ptr, offset);
#endif
}

/*!
 * Call a GOAL function with no arguments.
 */
u64 call_goal_function(Ptr<Function> func) {
  return call_goal(func, 0, 0, 0, s7.offset, g_ee_main_mem);
}

/*!
 * Default print method for structures.
 * Structures have no runtime type info, so there's not much we can do here.
 */
u64 print_structure(u32 s) {
  cprintf("#<structure @ #x%x>", s);
  return s;
}

/*!
 * Print an integer. Works correctly for 64-bit integers.
 */
u64 print_integer(u64 obj) {
  // not sure why this is any better than cprintf("%ld") or similar. Maybe a tiny bit faster?
  char* str = PrintPending.cast<char>().c();
  if (!str) {
    str = (PrintBufArea + 0x18).cast<char>().c();
  }

  PrintPending = make_ptr(strend(str)).cast<u8>();
  kitoa((char*)PrintPending.c(), obj, 10, 0xffffffff, '0', 0);
  return obj;
}

/*!
 * Print a boxed integer. Works correctly for 64-bit integers. Assumes signed.
 */
u64 print_binteger(u64 obj) {
  char* str = PrintPending.cast<char>().c();
  if (!PrintPending.offset) {
    str = (PrintBufArea + 0x18).cast<char>().c();
  }

  PrintPending = make_ptr(strend(str)).cast<u8>();
  kitoa((char*)PrintPending.c(), ((s64)obj) >> 3, 10, 0xffffffff, '0', 0);
  return obj;
}

/*!
 * Print floating point number.
 */
u64 print_float(u32 f) {
  // again not sure why this is any better than cprintf("%f") or similar. Maybe a tiny bit faster?
  float ff;
  *(u32*)&ff = f;
  char* str = PrintPending.cast<char>().c();
  if (!PrintPending.offset) {
    str = (PrintBufArea + 0x18).cast<char>().c();
  }

  PrintPending = make_ptr(strend(str)).cast<u8>();

  ftoa((char*)PrintPending.c(), ff, 0xffffffff, ' ', 4, 0);
  return f;
}

/*!
 * Print method for VU functions.  Again, just prints address.
 */
u64 print_vu_function(u32 obj) {
  cprintf("#<compiled vu-function @ #x%x>", obj);
  return obj;
}

/*!
 * Copy method that does no copying.
 */
u64 copy_fixed(u32 it) {
  return it;
}

/*!
 * Default copy for a structure. Since this has no idea of the actual type, it doesn't know what
 * size to copy.  So we do no copy and return a reference to the original data.
 */
u64 copy_structure(u32 it, u32 unknown) {
  (void)unknown;
  return it;
}

/*!
 * Inspect an integer (works correctly on 64-bit integers)
 */
u64 inspect_integer(u64 obj) {
  // and now we're using cprintf. Why doesn't print do this?
  cprintf("[%16lx] fixnum %ld\n", obj, obj);
  return obj;
}

/*!
 * Inspect a boxed integer (works correctly on 64-integers)
 */
u64 inspect_binteger(u64 obj) {
  cprintf("[%16lx] boxed-fixnum %ld\n", obj, s64(obj) >> 3);
  return obj;
}

/*!
 * Inspect a floating point number
 */
u64 inspect_float(u32 f) {
  float ff;
  ff = *(float*)(&f);
  cprintf("[%8x] float ", f);

  // likely copy-pasta - no need for this check because of the cprintf immediately before.
  char* str = PrintPending.cast<char>().c();
  if (!str) {
    str = (PrintBufArea + 0x18).cast<char>().c();
  }

  PrintPending = make_ptr(strend(str)).cast<u8>();

  ftoa(PrintPending.cast<char>().c(), ff, -1, ' ', 4, 0);
  cprintf("\n");
  return f;
}

/*!
 * Inspect a structure.
 */
u64 inspect_structure(u32 obj) {
  cprintf("[%8x] structure\n", obj);
  return obj;
}

/*!
 * Inspect a VU Function. Doesn't seem to be used. Also the concept of "vu-function"
 * isn't really used. VU0 macro mode stuff goes in normal functions, and micro-mode stuff goes
 * in a giant dump of many functions thats loaded and unloaded all at the same time.
 */
u64 inspect_vu_function(u32 obj) {
  struct VuFunction {
    u32 length;
    u32 origin;
    u32 qlength;
  };

  auto vf = Ptr<VuFunction>(obj);
  cprintf("[%8x] vu-function\n\tlength: %d\n\torigin: #x%x\n\tqlength: %d\n", obj, vf->length,
          vf->origin, vf->qlength);
  return obj;
}

/*!
 * This doesn't exist in the game, but we add it as a wrapper around kheapstatus.
 * Note that this isn't a great inspect as it prints to stdout instead of the printbuffer.
 */
u64 inspect_kheap(u32 obj) {
  kheapstatus(Ptr<kheapinfo>(obj));
  return obj;
}
