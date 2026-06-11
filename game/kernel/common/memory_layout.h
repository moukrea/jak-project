#pragma once

#include "common/common_types.h"

//! Toggle to use more memory. To simulate the original game's memory layout, set this to false.
// Make sure this matches the const in gcommon.gc.
constexpr bool BIG_MEMORY = true;

//! How much space to leave for the stack when creating the debug heap
// In the game, it's 16 kB, but we increase it to 64 kB.
// ASAN builds + fmt stuff uses a _ton_ of stack when no optimizations are on and we
// need more.
constexpr u32 DEBUG_HEAP_SPACE_FOR_STACK = 0x10000;

//! First free address for the GOAL heap
constexpr u32 HEAP_START = 0x13fd20;

//! Where to end the global heap so it doesn't overlap with the stack.
// A40: +8 MB on top of the doubled BIG_MEMORY size. The arm64 call bracket
// now banks q24-q31 (GOAL's callee-saved xmm8-15) around every BLR, which
// grows every call site by 32 bytes (~2 MB across jak1's CGOs); the global
// heap was already within ~600 KB of full at boot ("1883 bytes before
// stack"), so linking died in orb-cache. The [GLOBAL_HEAP_END,
// DEBUG_HEAP_START) gap is unused margin on the PC port (jak1 kmachine
// prints it as "gap"); 0x46b82e0 still leaves >9 MB below the debug heap
// at 0x5000000. GOAL code never reads this constant.
constexpr u32 GLOBAL_HEAP_END =
    0x1ffc000 + (BIG_MEMORY ? (0x1ffc000 - HEAP_START) : 0) + 0x800000;

//! Location of kglobalheap, kdebugheap kheapinfo structures.
constexpr u32 GLOBAL_HEAP_INFO_ADDR = 0x13AD00;
constexpr u32 DEBUG_HEAP_INFO_ADDR = 0x13AD10;
constexpr u32 LINK_CONTROL_NAME_ADDR = 0x13AD80;

//! Where to place the debug heap
constexpr u32 DEBUG_HEAP_START = 0x5000000;

namespace jak2 {
constexpr u32 DEBUG_HEAP_SIZE = 0x2f00000;
}

namespace jak3 {
constexpr u32 DEBUG_HEAP_SIZE = 0x2f00000;
}

namespace jakx {
constexpr u32 DEBUG_HEAP_SIZE = 0x2f00000;
}
