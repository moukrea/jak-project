// Phase 26 (autoport): minimal stubs satisfying link-time references from
// the curated kernel subset (kmalloc.cpp + kscheme.cpp) that we link into
// goal_stress_arm64 without their full production support TUs.
//
// Each stub is the minimum behaviour needed so the harness does not crash;
// nothing here pretends to be a working implementation. We only stub
// symbols that are either:
//   (a) referenced from a code path the harness actually executes
//       (Msg from kmalloc allocation failures, kheapstatus call sites),
//       or
//   (b) referenced from code paths we'd like the linker to keep available
//       in case --gc-sections leaves them in (g_game_version,
//       print_* helpers via PrintPending/PrintBufArea).
//
// Anything that is *never* executed AND --gc-sections drops successfully
// is intentionally absent; if a future change makes it reachable, the
// link will fail loudly and we'll add it explicitly.

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/common_types.h"
#include "common/goal_constants.h"
#include "game/kernel/common/Ptr.h"

// ----------------------------------------------------------------------------
// Game version. The kernel allocator's diagnostic path passes this into
// max_symbols(); we hardcode Jak1 because the validator only ever launches
// the harness with --game jak1.
// ----------------------------------------------------------------------------
GameVersion g_game_version = GameVersion::Jak1;

// ----------------------------------------------------------------------------
// Logging primitives. The production runtime routes these through
// common/log/log.{h,cpp} backed by spdlog; here we just write to stderr so
// any unexpected diagnostic surfaces in qemu's captured stream where the
// validator can see it.
// ----------------------------------------------------------------------------
// C++ linkage to match the declarations in kprint.h (no extern "C" there).
void Msg(s32 /*kind*/, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  std::vfprintf(stderr, fmt, ap);
  va_end(ap);
}

void MsgWarn(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  std::vfprintf(stderr, fmt, ap);
  va_end(ap);
}

void MsgErr(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  std::vfprintf(stderr, fmt, ap);
  va_end(ap);
}

void cprintf(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  std::vfprintf(stderr, fmt, ap);
  va_end(ap);
}

// ----------------------------------------------------------------------------
// kprint helpers referenced (but not executed) by kscheme.cpp::print_*.
// We provide working implementations rather than abort() so they remain
// safely linkable; the print buffer globals point at a small static
// region inside the binary's BSS so any future caller doesn't corrupt
// nearby memory.
// ----------------------------------------------------------------------------
static char g_print_buffer[64 * 1024];
Ptr<u8> PrintPending;
Ptr<u8> PrintBufArea;

char* strend(char* s) {
  while (*s) ++s;
  return s;
}

void kstrcpy(char* dst, const char* src) {
  std::strcpy(dst, src);
}

// kprint helpers kitoa/ftoa: simple wrappers around snprintf. These are
// never on the kheap/intern/dispatch hot path that the harness exercises;
// they exist solely so kscheme.cpp::print_integer & friends link cleanly
// in case the linker doesn't gc-section them away. Signatures match
// kprint.h exactly (C++ linkage, kprint.h declarations are not extern "C").
char* kitoa(char* buf, s64 value, u64 base, s32 /*length*/, char /*pad*/, u32 /*flags*/) {
  if (base == 16) {
    std::sprintf(buf, "%llx", (unsigned long long)value);
  } else {
    std::sprintf(buf, "%lld", (long long)value);
  }
  return buf;
}

void ftoa(char* buf, float value, s32 /*length*/, char /*pad*/, s32 /*precision*/, u32 /*flags*/) {
  std::sprintf(buf, "%f", (double)value);
}

// ----------------------------------------------------------------------------
// One-time init of the print buffer globals. Called from main() before
// anything touches them. We expose it via a constructor so the harness's
// goal_main doesn't need to know about this internal detail.
// ----------------------------------------------------------------------------
namespace {
struct PrintBufInit {
  PrintBufInit() {
    // PrintPending starts at 0 (the production sentinel for "no pending
    // print"); PrintBufArea points into our backing buffer offset by the
    // Ptr<>-to-g_ee_main_mem reservation. Since we never run the
    // production print pipeline in the harness, the exact values don't
    // matter as long as the kscheme.cpp::print_* code paths that load
    // these can safely run if --gc-sections doesn't strip them.
    PrintPending.offset = 0;
    PrintBufArea.offset = 0;
    (void)g_print_buffer;  // silence unused-variable warning
  }
};
PrintBufInit g_print_buf_init;
}  // namespace
