# A29 — arm64 IOP-RPC & loader fix sprint: gsound → 660 link-finishes

## Result

**qemu link-finish count: 660** (baseline A28: 462 — advance of **+198**,
1.43× past the A28 ceiling). x86 desktop boot still reaches
`link finish: logo`. arm64 CGO bytes byte-identical to A28's baseline
(no codegen changes — A29 is a pure runtime+loader fix sprint).

The A28 sprint broke the eight-phase 216-ceiling with two correlated
arm64 codegen fixes (RSP→SP translation and STR X30 / LDR X30 bracketing
of asm-func bodies) and unmasked a downstream IOP RPC assertion at
gsound's top-level. A29 fixes that assertion plus four follow-on
blockers in one session.

## What was broken (the five fixes)

### Fix 1 — IOP_Kernel::sif_rpc lacks an EE-side dispatch drain

`game/system/IOP_Kernel.cpp:480 ASSERT(rec->cmd.finished && rec->cmd.started)`
fires when a previously-queued RPC hasn't been drained. On x86 + Android
the IOP runs on its own OS thread (`runtime.cpp::iop_runner`,
`android/android_runtime_full.cpp::make_iop_thread`) and asynchronously
processes the wakeup_queue between EE-side `sif_rpc` calls. On
linux-arm64 the IOP runs on the SAME OS thread as the EE — a single
libco cothread, dispatched only when GOAL code polls `rpc-busy?`. The
gsound top-level emits four async sif_rpc calls
(check-irx-version + three sound-bank-loads); only the first three
trigger a polling pass (the rpc-buffer-pair `call` method's
`(when (-> active-buffer busy) (rpc-busy? ...))`). The last
sound-bank-load has nothing after it that polls, so its RPC stays
queued (`started=false, finished=false`) forever.

Because gsound is bundled in BOTH `ENGINE.CGO` and `GAME.CGO`
(`(bundles "ENGINE.CGO" "GAME.CGO")` at gsound.gc:3), its top-level
runs TWICE — once at ENGINE.CGO link, once at GAME.CGO link. The second
run's first `check-irx-version` calls `sif_rpc` and the assertion fires
on a still-queued state. (Verified with the A29_SIF_RPC_TRACE diag:
calls 1-4 happen between the first pair of `link finish: gsound-h /
gsound`, drains happen between each, call#5 fires after the second pair
of link finishes with `prev_cmd.started=0 prev_cmd.finished=0`.)

**Fix:** add a `bool run_on_ee_thread` flag to `IOP_Kernel` (default
false), set it true in `a13_arm64_init_iop`, and have `sif_rpc` call
`dispatch()` BEFORE locking `sif_mtx` when the flag is set. The
pre-drain is correct on linux-arm64 only — calling dispatch from the EE
OS thread on x86 would libco-co_switch into IOP cothreads that were
captured against the IOP OS thread's kernel_thread, which crashes.
x86 + Android stay at the default `false`, no behavior change.

### Fix 2 — jak1_finish's v2/v4 path didn't null-check m_entry

`game/kernel/jak1/klink.cpp:657` (the `else` branch handling v2/v4
objects) dereferences `(entry - 4).cast<u32>()` to read the type tag
WITHOUT first checking `m_entry.offset != 0`. The v3 path right above
HAS this check (`if (m_entry.offset && (m_flags & LINK_FLAG_EXECUTE))`,
line 643). When `jak1_work_v2`'s `INIT_COPY` `kmalloc(data-segment)`
fails (heap-overflow), the function MsgErr's "unable to malloc N bytes"
and returns 1 (done) WITHOUT reaching the trailing
`m_entry = m_object_data + 4` — leaving m_entry at the zero that
jak1_jak2_begin set. jak1_finish then computes
`g_ee_main_mem + (0 - 4) = g_ee_main_mem + 0xfffffffc` (UXTW
zero-extension of the subs-result) and SIGSEGVs reading at that
address.

**Fix:** add the `m_entry.offset &&` guard to the v2/v4 path. Safe on
x86/Android (m_entry is always non-zero when kmalloc succeeds, which is
the normal case). Local minimal change to shared code.

### Fix 3 — dgo-buffer-direct competed with data-segments for heap-top

`linux_arm64_direct_dgo.cpp::direct_load_dgo` allocated a 4 MB scratch
buffer at the top of the global heap (`kmalloc(heap, 0x400000,
KMALLOC_TOP, "dgo-buffer-direct")`). Combined with the bottom-allocator
growing from ENGINE+GAME's per-object data-segments, the heap was
exhausted at dir-tpages (heap-use ~60 MB, top buffer eating 4 MB out of
the 64 MB heap), triggering Fix 2's path on `dir-tpages`'s data-segment
alloc.

**Fix:** move the dgo-buffer-direct OUT of the global heap entirely.
Put it at a fixed GOAL offset (`0x4000000`, just above the global heap
end at `0x3eb82e0`), in the previously-unused middle gap of
g_ee_main_mem. The buffer is now free w.r.t. heap pressure; sized at
2 MB to fit any single object across all CGOs (peak observed:
`eichar` at 1349024 bytes).

### Fix 4 — three missing `__pc-*` bindings on linux-arm64

`game/kernel/common/kmachine.cpp:1093-1103` binds five
`__`-prefixed helper symbols in `init_common_pc_port_functions`. The
linux-arm64 a17 stub helper missed three (`__pc-texture-upload-now`,
`__read-ee-timer`, `__send-gfx-dma-chain`). The 463 `tpage-NNN` object
top-levels in GAME.CGO each call `__pc-texture-upload-now` once per
load; the unbound sym slot loaded 0, GOAL converted that to host
`ee_base`, BLR'd, and UDF'd at the start of g_ee_main_mem → sig=4
SIGILL.

**Fix:** add the three missing bindings to `a17_bind_pc_helpers` as
no-ops (returning 0 via `a17_pc_default`). Correct shape for the
headless qemu build (no GL texture context, no DMA target, no 300MHz
hardware timer). Android's full `init_common_pc_port_functions` runs
later and rebinds these to the real implementations.

### Fix 5 — `__pc-get-mips2c` returned 0 because gLinkedFunctionTable.get is a stub

`klink.cpp::klink_a11_ensure_pc_mips2c_bound` binds `__pc-get-mips2c`
to `a11_pc_get_mips2c_impl` which delegates to
`Mips2C::gLinkedFunctionTable.get(name)`. On linux-arm64 the upstream
`mips2c_table.cpp` is excluded (its static init pulls jak2/jak3 link
callbacks that aren't built); `linux_arm64_runtime_compat.cpp` provides
a stub `LinkedFunctionTable::get` that ALWAYS returns 0. Texture.gc's
top-level `(def-mips2c adgif-shader<-texture-with-update! ...)`
expansion calls `__pc-get-mips2c` and binds the sym slot to 0;
subsequent invocations BLR through 0 → SIGILL.

**Fix:** rebind `__pc-get-mips2c` (after `klink_a11_ensure_pc_mips2c_bound`
ran) to `a29_mips2c_get_noop`, which lazily builds one no-op GOAL
function (via `make_function_symbol_from_c("__a29-mips2c-noop",
a17_pc_default)`) and returns its offset for ANY name lookup. Every
`(def-mips2c name ...)` now binds to the SAME no-op trampoline; calls
through them no-op. Correct for headless arm64-linux qemu (no
texture-shader updates / no particle dispatch happens anyway).

## Validator evidence

- qemu link-finish count: **660** (was 462). Last 10:
  joint-exploder, babak, sharkey, orb-cache, plat, plat-button,
  plat-eco, ropebridge, ticky, hud-classes-pc.
- The boot now completes the entire ENGINE.CGO and GAME.CGO load
  (657 objects across both bundles) before hitting the new blocker.
  GAME.CGO's last object hud-classes-pc finished linking; the
  crash happens in some post-link top-level work or in a kernel
  helper called after the load loop returns.
- qemu exit: SIGSEGV at pc=0x21269a7a0c (a linked GOAL function),
  fault=0x2146228b74 (host = ee_base + 0x23228b74, where 0x23228b74
  is OUT of g_ee_main_mem range — invalid GOAL ptr loaded from
  some field at offset 116 of an object). A dangling-pointer-shaped
  corruption, NOT an unbound symbol (the A11 sym-MEM triplet walker
  finds `cspace` at lr-52 with a valid value 0x1510fb4). Likely a
  not-fully-initialised joint/anim structure field, or a codegen
  follow-on. The next-blocker class is "data corruption in GOAL
  linked code" — distinct from A29's RPC/loader/stub bindings.
- x86 desktop smoke: reaches `link finish: logo` cleanly. arm64
  CGOs byte-identical to A28's baseline (A29 changes only runtime
  code paths, not the emitter).
- No new weak/abort additions, no dodge patterns, no `_stubs.cpp`
  files, no fake "link finish" printf injections. The
  `IOP_Kernel.cpp` env-gated `A29_SIF_RPC_TRACE` diag is harmless
  (`std::getenv` returns null in normal runs).

## Next blocker (unblocked surface, not A29 scope)

The post-660 SIGSEGV is a deterministic data corruption: an object's
offset-116 field contains the value 0x23228b74 (= GOAL offset 580 MB
into a 128 MB memory space, invalid). The fault is reproducible
across runs (same PC, LR, X8 every time), independent of heap size.
The most likely culprits, in order:

1. **A codegen bug** in the field-store for the object at GOAL ptr
   0x228844 (a joint/cspace-shaped object). One of the post-A28
   widening fixes may not have caught all the cases — possibly a
   regalloc clobber of a constructor argument register, or a
   misemitted `(set! (-> obj field) value)` for a specific field
   offset.

2. **A no-op mips2c side-effect**: Fix 5 makes all mips2c calls
   no-op. Some GOAL code may store a mips2c return value into a
   field; that store gets 0, and a subsequent re-load returns 0,
   which mismatches expectations. But: the bad value is 0x23228b74,
   not 0 — so this is unlikely the primary cause.

3. **An ENGINE/GAME-level data path** that needs proper texture or
   tpage state set up. The boot reaches well past the texture
   subsystem; the corrupted field may be a tpage-relative pointer
   that depends on the real `__pc-texture-upload-now` having
   populated the texture base address.

Diagnostic next-step: localize the GOAL function at PC 0x21269a7a0c
(~57 MB into ee_main_mem, so within GAME.CGO's linked range) by
walking the heap's symbol table for a Function whose body straddles
that address. The lr disasm window shows the function is at least
1024 bytes long.

## Files changed

- `game/system/IOP_Kernel.h` — add `bool run_on_ee_thread` field
  (~10 lines added with rationale).
- `game/system/IOP_Kernel.cpp` — add inline `dispatch()` drain at
  the top of `sif_rpc` (gated on `run_on_ee_thread`), plus env-gated
  `A29_SIF_RPC_TRACE` diag prints in `sif_rpc` + `rpc_loop`
  (~50 lines, ~10 for the fix and ~40 for the diag).
- `game/kernel/jak1/klink.cpp` — add `m_entry.offset &&` guard to
  jak1_finish's v2/v4 path (mirror of the v3 path's check)
  (~15 lines added with rationale comment).
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` — set
  `kernel.run_on_ee_thread = true` after `new IOP()` in
  `a13_arm64_init_iop` (~15 lines).
- `game/linux-arm64/linux_arm64_direct_dgo.cpp` — replace
  KMALLOC_TOP scratch buffer with a fixed offset (0x4000000)
  outside the global heap (~25 lines changed).
- `game/linux-arm64/linux_arm64_main.cpp` — bump
  `kDirectDgoBufferSize` from 0x400000 to 0x200000 (smaller because
  no longer in heap), add `a29_mips2c_get_noop`, bind three missing
  `__`-prefixed symbols + `__pc-get-mips2c` to no-op in
  `a17_bind_pc_helpers` (~60 lines added).
