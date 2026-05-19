// Phase 26 (autoport): weak default implementations of runtime-trace hooks.
//
// These are no-ops with weak linkage so the production gk binary pays no
// observable cost. The test harness (tools/arm64-stress/main.cpp) provides
// strong-symbol replacements that count + report.
//
// __attribute__((weak)) on a definition makes the symbol overridable at
// link time without --allow-multiple-definition. Clang and gcc both accept
// it on extern "C" function definitions on Linux/aarch64.

#include "runtime_trace.h"

extern "C" {

__attribute__((weak)) void __goal_runtime_trace_kheap(uint64_t /*top*/) {}
__attribute__((weak)) void __goal_runtime_trace_symbol_intern(void) {}
__attribute__((weak)) void __goal_runtime_trace_goal_call(void) {}

}  // extern "C"
