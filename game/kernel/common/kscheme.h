#pragma once

#include <atomic>

#include "common/common_types.h"

#include "game/kernel/common/Ptr.h"

extern s32 NumSymbols;
extern Ptr<u32> s7;
extern Ptr<u32> SymbolTable2;
extern Ptr<u32> LastSymbol;
extern u32 FastLink;
extern Ptr<u32> EnableMethodSet;

// Gjak2-render concurrent-GOAL race experiment (translation-layer only):
//  - g_goal_active: incremented on entry / decremented on exit around every
//    known C++ -> GOAL entry site (klink jak2_finish top-level exec + the
//    GL/render-thread vif_interrupt_callback). If it is > 1 at a crash, two
//    threads were inside GOAL on the single shared GOAL stack concurrently.
//  - g_goal_boot_linking: TRUE while the jak2 boot CGO-link sequence runs
//    (goal_main around InitMachine). The GL-thread GOAL call is skipped while
//    this is set (jak2 only) so the render thread never touches the shared
//    GOAL stack during boot-linking.
extern std::atomic<int> g_goal_active;
extern std::atomic<bool> g_goal_boot_linking;

// RAII guard: bump g_goal_active for the lifetime of a C++ -> GOAL call.
struct GoalActiveGuard {
  GoalActiveGuard() { g_goal_active.fetch_add(1, std::memory_order_seq_cst); }
  ~GoalActiveGuard() { g_goal_active.fetch_sub(1, std::memory_order_seq_cst); }
  GoalActiveGuard(const GoalActiveGuard&) = delete;
  GoalActiveGuard& operator=(const GoalActiveGuard&) = delete;
};

void kscheme_init_globals_common();

constexpr u32 CRC_POLY = 0x04c11db7;
constexpr u32 EMPTY_HASH = 0x8454B6E6;
constexpr u32 OFFSET_MASK = 7;

constexpr uint32_t UNKNOWN_PP = UINT32_MAX;

struct String {
  u32 len;
  char* data() { return ((char*)this) + sizeof(String); }
};

struct Function {};

void init_crc();
u32 crc32(const u8* data, s32 size);
u64 delete_illegal(u32 obj);
u64 goal_malloc(u32 heap, u32 size, u32 flags, u32 name);

u64 call_goal(Ptr<Function> f, u64 a, u64 b, u64 c, u64 st, void* offset);
u64 call_goal_on_stack(Ptr<Function> f, u64 rsp, u64 st, void* offset);
u64 call_goal_function(Ptr<Function> func);
u64 print_structure(u32 s);
u64 print_integer(u64 obj);
u64 print_binteger(u64 obj);
u64 print_float(u32 f);
u64 print_vu_function(u32 obj);
u64 copy_fixed(u32 it);
u64 copy_structure(u32 it, u32 unknown);
u64 inspect_integer(u64 obj);
u64 inspect_binteger(u64 obj);
u64 inspect_float(u32 f);
u64 inspect_structure(u32 obj);
u64 inspect_vu_function(u32 obj);
u64 inspect_kheap(u32 obj);