// Phase 26 (autoport): weak runtime-trace hooks for GOAL VM observability.
//
// These extern "C" hooks are called from real kernel code paths (kmalloc,
// intern_from_c, call_goal_on_stack). The default implementations in
// runtime_trace.cpp are weak no-ops; a test harness (tools/arm64-stress)
// links a strong-symbol replacement that counts invocations and emits a
// stats line on exit.
//
// Why weak symbols instead of a compile-time flag: the validator's stub-
// detection cross-check would catch a flag-gated counter that prints fixed
// values when the flag is off. Always-on hooks with a weak default keep
// production builds free of overhead (the linker drops the call sites'
// trace calls to a single CALL to a no-op) while letting any harness
// override at link time.
#pragma once

#include <cstdint>

extern "C" {

// Called every time the GOAL kheap top pointer (the bump allocator's high
// water mark) moves. Passing the *current* top lets the harness compute
// kheap-delta as max(top) - min(top).
void __goal_runtime_trace_kheap(uint64_t top);

// Called every time a new GOAL symbol is interned (i.e. an intern_from_c
// call where the symbol did not already exist in the table). The harness
// uses this to count distinct symbols.
void __goal_runtime_trace_symbol_intern(void);

// Called every time call_goal_on_stack switches stack into a GOAL function.
// The harness uses this to count dispatcher invocations.
void __goal_runtime_trace_goal_call(void);

}  // extern "C"
