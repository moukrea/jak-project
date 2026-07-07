// Phase C3 (autoport, bucket C): direct-from-disk DGO loader.
//
// Wraps the real upstream `jak1::link_and_exec` over each object in a
// DGO file read straight from local disk — no IOP, no Overlord, no
// RPC. This bypasses the fakeiso → overlord → DGO_RPC pipeline that
// the desktop / Android runtimes use, but the link engine itself is
// the unmodified upstream code that executes real arm64-compiled
// GOAL bytecode through the asm_funcs_arm64.s trampoline.
//
// Intended use: C3's boot driver calls this after C2's
// `InitHeapAndSymbol()` returns. The kernel-CGO load path normally
// invoked by `InitHeapAndSymbol()` (guarded by `MasterUseKernel`)
// requires the IOP/Overlord, which is C-bucket follow-up work; the
// direct loader here is the smallest honest step that demonstrates
// real GOAL code executes on aarch64.

#pragma once

#include "common/common_types.h"
#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kmalloc.h"

namespace linux_arm64 {

// Signature of the per-game link engine (jak1::link_and_exec /
// jak2::link_and_exec — identical signatures). The direct loader calls
// through this pointer so a jak2 boot can drive the jak2 relocator while
// the default preserves the existing jak1 behavior for 4-arg callers.
typedef Ptr<uint8_t> (*DirectDgoLinkFn)(Ptr<uint8_t>,
                                        const char*,
                                        int32_t,
                                        Ptr<kheapinfo>,
                                        uint32_t,
                                        bool);

// Load and link a DGO file by reading its bytes directly from `dgo_path`
// and feeding each contained object into `link_fn` (defaults to
// `jak1::link_and_exec` when null).
//
// Returns 0 on success, negative on error:
//   -1  fopen failed
//   -2  short read of DGO file header
//   -3  buffer allocation failed
//   -4  short read of an object header
//   -5  object size exceeds buffer
//   -6  short read of object data
//   -7  ftell failed (need file position to skip 16-byte object padding)
//   -8  fseek over object padding failed
//
// On success, the heap top has been restored to its pre-call value and
// the file descriptor has been closed. On any failure mode 1..6, the
// heap top is still restored and the file is closed before return.
int direct_load_dgo(const char* dgo_path,
                    Ptr<kheapinfo> heap,
                    u32 link_flags,
                    s32 buffer_size,
                    DirectDgoLinkFn link_fn = nullptr);

}  // namespace linux_arm64
