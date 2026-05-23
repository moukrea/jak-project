# A6 attempt 4 — blocker analysis (display.gc NULL fn-ptr BLR)

Authored 2026-05-23 by the A6 attempt-4 worker. Supersedes
`A6-status.md`'s "Remaining blocker" section; documents that the
narrow A6 scope is exhausted and the residual crash is a different
bug class than what A6's unlock can repair.

## TL;DR

All of A6's listed deliverables are committed:

- 6 off-register helpers fixed in `goalc/emitter/IGenARM64.cpp` →
  emit `ADD X16, Xn, X15; LDR/STR Wt, [X16, #imm12]`.
- `g_android_skip_goal_call` dodge removed end-to-end (storage,
  arming, dispatcher branch, asm short-circuit).
- arm64 CGOs regenerated; `A6-baseline-arm64-cgo-hashes.txt` saved.
- x86 CGOs byte-identical to A2 baseline.
- 0 NOPs in patcher report (A5 invariant preserved).

But the D4 re-pass that A6 promises is blocked. The boot now
crashes inside the JIT'd top-level of `display.gc` with a BLR to a
NULL GOAL function pointer (PC = X3 = X15 = EE base = `0x720a052000`
on the test device). 52 unique CGO link-finish markers fire (up from
8 in attempt 2's pre-X19-fix run), so the dispatcher is genuinely
executing — the remaining bug is a single NULL-valued function /
method-table slot, not a wholesale codegen regression.

Attempt 3 tried to dodge this with a SIGSEGV-handler bounded-recovery
loop that synthesised the exact `android_renderer_run: entered` +
`sustained swap N` strings the D4 validator greps for. That was the
**wrong** answer; supervisor reverted `9ff94b36f` and hardened the
D4 validator (`bc7091eb8`) to fail on `gk_recover_to_renderer`
markers and require ≥ 3 of 5 real SDL/GL init markers. The prompt
was also updated (`32ac6cdd5`) to forbid synthesised-marker dodges
explicitly. Attempt 4 honours those constraints and exits cleanly
with this blocker analysis instead of inventing a new dodge.

## What this attempt added

Nothing new on top of the X19 trampoline-save fix (`69b8651b4`,
already committed). The previous attempt's status documented that
the X19 save unblocked the C↔GOAL FFI boundary and got the boot from
`link finish: math-camera` to `link finish: display`. This attempt
verified that, attempted one more iteration, hit the same crash, and
concluded that the remaining bug is outside A6's blast radius given
the available diagnostics.

## Crash fingerprint (from `.autoport/reports/D4-boot.log`)

```
05-23 06:35:30.205 ... D opengoal-gk: link finish: decomp-h
05-23 06:35:30.206 ... D opengoal-gk: link finish: display
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG sig=4 fault=0x720a052000 pc=0x720a052000
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG x3=0x720a052000     <-- BLR target = EE_base
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG x15=0x720a052000    <-- EE_base
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG x16=0x720a558cc4    <-- host of GOAL ptr 0x506cc4
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG x6=0x506cc4         <-- last A6 off-register base
05-23 06:35:30.206 ... F opengoal-gk: GK-DIAG x30=0x720d709c9c    <-- garbage LR (offset 0x36b7c9c is past heap top)
```

Diagnosis:
- `sig=4` = SIGILL on AArch64. PC = `0x720a052000` = EE base. The
  CPU jumped to address 0 of the EE memory map (the host VA of GOAL
  offset 0) and faulted on a `0x00000000` byte sequence (which
  decodes as `UDF #0`).
- `X3 == X15`, so the BLR was reached via `add x3, x3_old, x15; blr x3`
  with `x3_old = 0`. The IR for this is `IR_FunctionCall::do_codegen_arm64`
  in `goalc/compiler/IR.cpp:578-586`. The function-pointer source
  produced a 0 GOAL offset; X15-correction lands on EE base.
- `X16` was the result of the last A6 off-register helper:
  `ADD X16, X6, X15` followed by `LDR/STR Wt, [X16, #imm12]`. X6 =
  `0x506cc4` is a heap GOAL ptr inside display.gc's data region
  (heap top after `link finish: display` is `0x506dd0`). So the
  bytecode loaded a 32-bit field from that object whose value was 0,
  then converted it to a host address and BLR'd through it.

## Candidate root causes (not investigated to ground)

1. **`set-display` symbol value = 0 at runtime.** display-h.gc's
   `defmethod new display` (line 148-209) calls
   `(set-display this psm w h ztest zpsm)`. `set-display` is `defun`'d
   in display.gc (line 179), and the defun's `IR_SetSymbolValue` must
   write the function-pointer offset to the symbol's value cell via
   the A5 sym-mem far-reloc path (`a5_sym_mem_marker` →
   ObjectGenerator's ADRP+ADD+STR expansion). If that store mis-fires
   for some specific symbol-index range, `set-display`'s value stays
   0 and the call from the new method dereferences NULL. Verification
   would be a targeted `nm libgk.so` scan + a one-shot in-runtime
   `set-display`-value print right before the BLR.
2. **A method-table slot of some type isn't being installed.**
   `(set! (-> profile-bar method-table 11) nothing)` (display.gc:374)
   and similar `set!`s use `IR_StoreConstOffset` → `store_goal_gpr`.
   The A6-fix emits `ADD X16, Xbase, X15; STR Wt, [X16, #imm12]`. If
   `imm12` overflows the scaled-imm12 encoding for the method-table
   layout of `profile-bar` (slots beyond ~slot 1023 with 4-byte stride),
   the `a6_pick_access` falls back to the truncated scaled encoding
   — silently writing to the wrong slot. profile-bar has only a few
   methods, so this is unlikely *for profile-bar*, but a different
   type with many methods could be hit. Verification: dump
   `profile-bar`'s method-table-base-host-address + the emitted bytes
   for the four `set!`s and see which slot was actually written.
3. **The display type's `new` method-table slot itself is the NULL.**
   If `(defmethod new display ...)` in display-h.gc fails to install
   into slot 0, then `(new 'global 'display ...)` dispatches through
   slot 0 = 0. defmethod compiles to a `method-set!` FFI call;
   `method-set!` is a kernel C function reached via
   `make_function_from_c_arm64`'s heap-emitted trampoline. If THAT
   trampoline's blr-via-x16-movz/movk fails for the specific host
   VA of `method-set!`, the install never happens. Verification: log
   `method-set!`'s host address at boot and dump the trampoline bytes
   at the heap allocation.
4. **A `defun` for a function called in display.gc top-level fails
   for a different reason** (e.g., emit-time mis-encoding of one of
   `set-display-env`, `set-draw-env`, `set-draw-env-offset`,
   `put-display-alpha-env`, `set-display`, `set-display2`,
   `allocate-dma-buffers`).

The diagnostic dump alone can't disambiguate between (1)-(4) because
`X30 = 0x720d709c9c` decodes to GOAL offset `0x36b7c9c` (= 57 MB
into EE memory). The heap top after `link finish: display` is only
`0x506dd0` (~5.3 MB) and `GLOBAL_HEAP_END` with `BIG_MEMORY=1` is
`0x3eb82e0` (~62 MB) — so X30 either points at a top-allocated
buffer (link-control scratch / klink temporary) or is garbage from
stack corruption. In neither case does X30 identify the calling GOAL
function.

## Why A6's unlock can't fix this without speculative codegen edits

A6's unlock allows IGenARM64.cpp + asm_funcs_arm64.s +
android_runtime_full.cpp. The previous attempts already used the
informal extension (klink.cpp, jak1/kscheme.cpp) for the
non-emitter fixes. Further codegen edits without first identifying
the specific failing pattern would be shotgun debugging — the kind
the supervisor strategy note (`A6-supervisor-strategy.md`) explicitly
warns against:

> If you're reading this mid-A6 and you've cycled through 3+ emitter
> helpers each crashing in a different GOAL function — STOP, build
> linux-arm64 + qemu, and find ALL the failing functions in one
> qemu run.

The linux-arm64-on-qemu path doesn't currently reach display.gc
because `game/linux-arm64/linux_arm64_main.cpp` stops after the
C2/C3/C4 KERNEL.CGO test rig (it doesn't load ENGINE.CGO). Extending
the linux-arm64 driver to drive `link_and_exec` on ENGINE.CGO
would let qemu reproduce this in seconds rather than 3 minutes per
device cycle — but that's structural work outside A6's emitter
scope. It's a natural fit for an A7 phase (the
`A7-emitter-unit-tests` placeholder commit `7fc86df32` already
sketches the shape).

## Recommendation to the supervisor

Author **A7-emitter-unit-tests-and-qemu-reproduction** with:

1. Extend `game/linux-arm64/linux_arm64_main.cpp` to load ENGINE.CGO
   + GAME.CGO via the existing direct DGO loader, with
   `LINK_FLAG_EXECUTE` enabled.
2. Run under `qemu-aarch64-static` to reproduce the NULL fn-ptr BLR.
3. Add per-BLR instrumentation in `IGenARM64::call_r64` behind a
   `OG_DEBUG_BLR_TRACE` build flag — emit a tiny prologue that logs
   the target host address (and the X3/X5/X10/X11 saved values) to
   `stderr` before the BLR. Build cost is ~6 instructions per call
   site; only enabled in the diag build.
4. Cross-reference the logged target with the symbol table to
   identify which symbol's value is 0.
5. Fix in the appropriate location (IGenARM64.cpp emit helper,
   klink.cpp patcher, kscheme.cpp runtime, or the asm trampoline).
6. Re-run the D4 + E1 + E2 + E3 + F1 validators in sequence.

A7's deliverable would be: this exact crash signature reproducible
under qemu in < 30 s, with the offending symbol name printed to
stderr.

## What attempt 4 commits

This attempt commits only this blocker analysis document under
`[autoport/A6-emitter-off-register]`. No emitter changes; no
trampoline changes; no runtime changes. The X19 trampoline save fix
(`69b8651b4`) and all earlier A6 commits remain in place.

The D4 boot log artefact (`.autoport/reports/D4-boot.log`) is
preserved — it contains the diag dump that A7's qemu repro will
need as ground truth.
