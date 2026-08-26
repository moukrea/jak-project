#include "kmalloc.h"

#include <cstdio>
#include <cstring>

#if defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#endif

#include "common/goal_constants.h"

#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/common/runtime_trace.h"

// global and debug kernel heaps
Ptr<kheapinfo> kglobalheap;
Ptr<kheapinfo> kdebugheap;
// if we should count the number of strings and types allocated on the global heap.
bool kheaplogging = false;

// [autoport temporary forensic probe] jak2 ctywide "no entities" break.
// Records the GOAL array-basic pointer of the "entity-links-array" allocation
// so the crash handler (gk_sigsegv_diag) can dump its raw words. Defined here
// (compiled into android + linux-arm64 + x86), extern'd from the handler side.
// The global is kept unconditional (tiny); the capture is arm64-gated below.
extern "C" u32 g_gjak2_entlinks_addr = 0;
enum MemItemsCategory {
  STRING = 0,
  TYPE = 1,
  NUM_CATEGORIES = 2,
};
int MemItemsCount[NUM_CATEGORIES] = {0, 0};
int MemItemsSize[NUM_CATEGORIES] = {0, 0};

void kmalloc_init_globals_common() {
  // _globalheap and _debugheap
  kglobalheap.offset = GLOBAL_HEAP_INFO_ADDR;
  kdebugheap.offset = DEBUG_HEAP_INFO_ADDR;
  kheaplogging = false;
  for (auto& x : MemItemsCount)
    x = 0;
  for (auto& x : MemItemsSize)
    x = 0;
}

/*!
 * In the game, this wraps PS2's libc's malloc/calloc.
 * These don't work with GOAL's custom memory management, and this function
 * is unused.
 * DONE, malloc/calloc calls commented out because memory allocated with calloc/malloc
 * cannot trivially be accessed from within GOAL.
 */
Ptr<u8> ksmalloc(Ptr<kheapinfo> heap, s32 size, u32 flags, char const* name) {
  (void)heap;
  (void)size;
  (void)name;
  printf("[ERROR] ksmalloc : cannot be used!\n");
  u32 align = flags & 0xfff;
  Ptr<u8> mem;

  if ((flags & KMALLOC_MEMSET) == 0) {
    // mem = malloc(size + align);
  } else {
    // mem = calloc(1, size + align);
  }

  if (align == KMALLOC_ALIGN_64) {
    mem.offset = (mem.offset + 0x3f) & 0xffffffc0;
  } else if (align == KMALLOC_ALIGN_256) {
    mem.offset = (mem.offset + 0xff) & 0xffffff00;
  }

  return mem;
}

/*!
 * Print the status of a kheap.  This prints to stdout on the runtime,
 * which will not be sent to the Listener.
 * DONE, EXACT
 */
Ptr<kheapinfo> kheapstatus(Ptr<kheapinfo> heap) {
  Msg(6,
      "[%8x] kheap\n"
      "\tbase: #x%x\n"
      "\ttop-base: #x%x\n"
      "\tcur: #x%x\n"
      "\ttop: #x%x\n",
      heap.offset, heap->base.offset, heap->top_base.offset, heap->current.offset,
      heap->top.offset);
  // note: max symbols here is game-version dependent
  Msg(6,
      "\t used bot: %d of %d bytes\n"
      "\t used top: %d of %d bytes\n"
      "\t symbols: %d of %d\n",
      heap->current - heap->base, heap->top_base - heap->base, heap->top_base - heap->top,
      heap->top_base - heap->base, NumSymbols, max_symbols(g_game_version));

  if (heap == kglobalheap) {
    Msg(6, "\t %d bytes before stack\n", GLOBAL_HEAP_END - heap->current.offset);
  }

  for (int i = 0; i < NUM_CATEGORIES; i++) {
    printf("  %d: %d %d\n", i, MemItemsCount[i], MemItemsSize[i]);
  }

  // might not have returned heap in jak 1
  return heap;
}

/*!
 * Initialize a kheapinfo structure, and clear the kheap's memory to 0.
 * DONE, EXACT
 */
// Gmemory-ceiling-and-crash (2026-08-26) — METTRE A ZERO SANS RENDRE LES PAGES RESIDENTES.
//
// `kinitheap` remet a zero TOUT le tas qu'il initialise, et GOAL en depend : `kmalloc` ne
// zero-initialise pas ses allocations (c'est le role du drapeau KMALLOC_MEMSET), donc le code
// GOAL lit des champs qui n'ont jamais ete ecrits et attend zero. La remise a zero n'est donc
// PAS retirable. Mais un `memset` de 100 Mo TOUCHE 25 000 pages, ce qui force le noyau a leur
// donner une page physique tout de suite et pour toujours.
// Mesure sur le Redmi (A55-RSS, famille `ee`) : 117 Mo RESIDENTS sur les 128 Mo de l'image EE,
// des le demarrage — alors que la PS2 tenait dans 32 Mo.
//
// `madvise(MADV_DONTNEED)` donne EXACTEMENT la meme semantique sur un mapping ANONYME PRIVE
// (madvise(2) : « subsequent accesses of pages in the range will succeed, but will result in
// [...] zero-fill-on-demand pages for anonymous private mappings ») et il REND les pages au
// systeme au lieu de les prendre. La memoire EE est mappee `MAP_ANONYMOUS | MAP_PRIVATE` par
// les trois proprietaires possibles du tampon (android/android_runtime_compat.cpp,
// game/runtime.cpp, game/linux-arm64/linux_arm64_main.cpp), donc la condition est remplie.
//
// Prudence : seulement au-dela de 4 Mo (en dessous, `memset` est plus rapide qu'un appel
// systeme), seulement sur la partie ALIGNEE SUR LA PAGE (les bords sont mis a zero a la main),
// et avec un repli `memset` si l'appel echoue. Le contenu vu par GOAL est identique dans tous
// les cas : que du zero.
static void zero_without_faulting(u8* p, size_t n) {
#if defined(__linux__)
  const long pgl = sysconf(_SC_PAGESIZE);
  if (pgl > 0 && n >= (4u << 20)) {
    const uintptr_t pg = (uintptr_t)pgl;
    const uintptr_t a = (uintptr_t)p;
    const uintptr_t b = a + n;
    const uintptr_t a_up = (a + pg - 1) & ~(pg - 1);
    const uintptr_t b_dn = b & ~(pg - 1);
    if (b_dn > a_up) {
      std::memset(p, 0, (size_t)(a_up - a));
      std::memset((u8*)b_dn, 0, (size_t)(b - b_dn));
      if (madvise((void*)a_up, (size_t)(b_dn - a_up), MADV_DONTNEED) == 0) {
        return;
      }
      std::memset((u8*)a_up, 0, (size_t)(b_dn - a_up));
      return;
    }
  }
#endif
  std::memset(p, 0, n);
}

Ptr<kheapinfo> kinitheap(Ptr<kheapinfo> heap, Ptr<u8> mem, s32 size) {
  heap->base = mem;
  heap->current = mem;
  heap->top = mem + size;
  heap->top_base = heap->top;
  zero_without_faulting(mem.c(), (size_t)size);
  // Phase 26 trace hook: report the high-water mark right after init so
  // the harness can establish a baseline for kheap-delta.
  __goal_runtime_trace_kheap(reinterpret_cast<uint64_t>(heap->current.c()));
  return heap;
}

/*!
 * Return how much of the bottom (non-temp) allocator is used.
 * DONE, EXACT
 */
u32 kheapused(Ptr<kheapinfo> heap) {
  return heap->current - heap->base;
}

/*!
 * Allocate memory using bump allocation strategy.
 * @param heapPtr : heap to allocate on. If null heap, use global but print a warning
 * @param size    : size of memory needed
 * @param flags   : flags for alignment, top/bottom allocation, set to zero
 * @param name    : name of allocation (printed if things go wrong)
 * @return        : memory.  0 if we run out of room
 * DONE, PRINT ADDED
 */
Ptr<u8> kmalloc(Ptr<kheapinfo> heap, s32 size, u32 flags, char const* name) {
  uint32_t alignment_flag = flags & 0xfff;

  // if we got a null heap, put it on the global heap, but warn about it
  if (!heap.offset) {
    // the 0 is uninitialized in jak1, set to zero in jak 2. might just be compiler differences.
    Msg(6, "-----------> kmalloc: alloc %s,  mem %s #x%x (a:%d  %dbytes)\n", "DEBUG", name, 0,
        alignment_flag, size);
    heap = kglobalheap;
  }

  uint32_t memstart;

  if (!(flags & KMALLOC_TOP)) {
    // allocate from bottom
    if (alignment_flag == KMALLOC_ALIGN_64)
      memstart = (0xffffffc0 & (heap->current.offset + 0x40 - 1));
    else if (alignment_flag == KMALLOC_ALIGN_256)
      memstart = (0xffffff00 & (heap->current.offset + 0x100 - 1));
    else  // includes 0x10!
      memstart = (0xfffffff0 & (heap->current.offset + 0x10 - 1));

    if (size == 0) {
      Msg(6, "[WARNING] kmalloc : size 0 allocation from bottom.\n");
      return Ptr<u8>(memstart);
    }

    uint32_t memend = memstart + size;

    if (heap->top.offset < memend) {
      kheapstatus(heap);
      Msg(6, "kmalloc: !alloc mem %s (%d bytes) heap %x\n", name, size, heap.offset);
      return Ptr<u8>(0);
    }

    heap->current.offset = memend;
    if (flags & KMALLOC_MEMSET)
      std::memset(Ptr<u8>(memstart).c(), 0, (size_t)size);
    // Phase 26: bottom-allocator high-water mark moved.
    __goal_runtime_trace_kheap(reinterpret_cast<uint64_t>(heap->current.c()));
#ifdef __aarch64__
    // [autoport temporary forensic probe] Record the GOAL array-basic pointer.
    // kmalloc returns the raw aligned offset (memstart); the GOAL `new` caller
    // adds BASIC_OFFSET (+4) to form the pointer GOAL code holds. Store that.
    if (name && strcmp(name, "entity-links-array") == 0) {
      g_gjak2_entlinks_addr = memstart + BASIC_OFFSET;
    }
#endif
    return Ptr<u8>(memstart);
  } else {
    // allocate from top
    if (alignment_flag == 0) {
      alignment_flag = KMALLOC_ALIGN_16;
    }

    memstart = (heap->top.offset - size) & (-alignment_flag);

    if (size == 0) {
      Msg(6, "[WARNING] kmalloc : size 0 allocation from top\n");
      return Ptr<u8>(memstart);
    }

    if (heap->current.offset >= memstart) {
      Msg(6, "kmalloc: !alloc mem from top %s (%d bytes) heap %x\n", name, size, heap.offset);
      kheapstatus(heap);
      return Ptr<u8>(0);
    }

    heap->top.offset = memstart;

    if (flags & KMALLOC_MEMSET)
      std::memset(Ptr<u8>(memstart).c(), 0, (size_t)size);

    // Phase 26: top-allocator low-water mark moved. We report top so the
    // harness can derive the symmetric "delta" from base.
    __goal_runtime_trace_kheap(reinterpret_cast<uint64_t>(Ptr<u8>(memstart).c()));

    // this logging was added in Jak 3, but we port it back to all games:
    if ((heap == kglobalheap) && (kheaplogging != 0)) {
      if (strcmp(name, "string") == 0) {
        MemItemsCount[STRING]++;
        MemItemsSize[STRING] += size;
      } else if (strcmp(name, "type") == 0) {
        MemItemsCount[TYPE]++;
        MemItemsSize[TYPE] += size;
      }
    }
    return Ptr<u8>(memstart);
  }
}

/*!
 * GOAL does not support automatic freeing of memory. This function does nothing.
 * Programmers wishing to free memory must do it themselves.
 * DONE, PRINT ADDED
 */
void kfree(Ptr<u8> a) {
  (void)a;
  Msg(6, "[ERROR] kmalloc: kfree called\n");
}
