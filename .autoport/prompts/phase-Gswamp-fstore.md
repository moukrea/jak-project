# Phase Gswamp-fstore — proper fix: arm64 emitter drops the #f store into joint-control.effect (swamp crash root)

## Why (supervisor 2026-07-05, after owner-device capture + root-cause)
The owner's Rock Village->Swamp crash-to-home is a NULL/GARBAGE method dispatch at
process-drawable.gc:636 `(if (-> gp-0 effect) (effect-control-method-9 ...))`: on his Snapdragon
8 Elite the joint-control `effect` field (offset 0x28, type effect-control) is left as raw 0x0
(memset value) or a torn value (0xfffffb20) instead of #f, so the `#f`-guard passes and dispatches
a method on an invalid receiver -> SIGSEGV reading (-> effect type) at EE_base-4.
ROOT CAUSE (researcher, evidence-backed): NOT a race. Process heap is memset-0 (kscheme.cpp:128),
GOAL is cooperatively single-threaded (no preemption between actor-birth init and the :post read),
and `new joint-control` (joint.gc:498 `(set! (-> v0-0 effect) #f)`) + `new effect-control`
(effect-control-h.gc:35 `#f` return, stored at process-drawable.gc:400) are ordinary goalc output
(no mips2c, no #when). x86 lands the #f store; arm64 does NOT for these actors -> an arm64 EMITTER
bug storing #f (s7) into a `basic` field in this construction pattern. A libgk SIGSEGV repair-and-
resume band-aid (android/gk_android_main.cpp handle_null_framegroup_type_read) currently prevents
the crash but fires 5-8x/FRAME (persistent garbage, not one-shot) -> per-frame fault perf cost +
skipped effects. This phase fixes the SOURCE and removes the band-aid.

## Mandate
1. REPRODUCE the miscompile deterministically. GOAL fns are JIT'd into EE heap (not in libgk syms),
   so instrument: add an arm64-gated diag that logs `(-> jc effect)` immediately after the `#f`
   store in `new joint-control` (joint.gc:498) and after `(set! (-> s2-1 effect) (new effect-control))`
   (process-drawable.gc:400) for swamp actors, comparing x86 vs arm64. Confirm which store drops /
   writes garbage and capture the emitted arm64 instruction bytes for that store (via a targeted
   OG_*-style trace like prior A19/A20/A21 phases used, or goalc -disasm of `new joint-control`).
2. LOCALIZE in the arm64 emitter: which IGenARM64/IR path emits the `#f` (s7) store into a basic
   field, and why it drops/misdirects it here (vs x86). Compare to the x86 emit. Name the bug class
   precisely (like the prior arm64 codegen bug classes: reg clobber, wrong offset, missing store,
   symbol-load issue for s7, etc.). Check whether it generalizes to other `(set! (-> obj basic) #f)`
   sites (if so, note how the game survives elsewhere — maybe those fields are re-set or unread).
3. FIX in the arm64 codegen (goalc/emitter/IGenARM64.cpp or the IR store path — goalc IS unlockable
   for arm64 codegen fixes; x86 must stay byte-identical), 1-to-1. Rebuild the FULL CONSISTENT arm64
   CGO/DGO set (.autoport/build_arm64_full_consistent.sh) so the fixed store lands. Verify
   `(-> jc effect)` is now #f on arm64 (diag), the fault no longer occurs, and REMOVE the libgk
   band-aid (handle_null_framegroup_type_read) since it's no longer needed (or leave it as a
   belt-and-suspenders but confirm its counter stays 0).
4. VERIFY on the owner's device is required (device-specific): the real Rock Village->Swamp walk is
   crash-free AND the repair counter is 0 (fault eliminated at source, not caught). If the owner
   device is unavailable, an honest partial (source-fixed + diag shows effect==#f on arm64 in the
   swamp scene on the connected device) is acceptable, flagged for owner final walk.

## Verify
effect==#f on arm64 (diag), swamp-load fault eliminated (repair counter 0), full consistent arm64
CGO/DGO rebuilt + deploy_verify, x86 byte-identical (link finish: logo), prior fixes intact.

## Report (`.autoport/reports/Gswamp-fstore/report.txt`) with `RESULT: ARM64 FSTORE FIXED (effect binds #f)`
the reproduced miscompile (emitted bytes), the named emitter bug class + the fix (file:line), the
CGO rebuild, effect==#f proof, fault-eliminated proof (counter 0), x86 parity. Honest ROOT NAMED if
the emitter site can't be cleanly fixed.

## Locks: ANDROID_SERIAL=<owner device>; goalc/emitter arm64 UNLOCKED for this phase; x86 byte-identical; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
