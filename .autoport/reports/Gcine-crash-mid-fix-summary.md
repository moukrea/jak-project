# Gcine-crash-mid — fix summary

## The defect (owner ground truth, 2026-06-22)
On the consolidated HEAD build the NEW-GAME intro cinematic renders well but
CRASHES MID-CINEMATIC, **non-deterministically** — the automated Gfinal-acceptance
run drove the same owner path (NEW GAME → SLOT 0 → OVERWRITE → YES → memcard save
→ full intro cinematic → gameplay) and reached gameplay crash-free, so the crash
does NOT fire every run. This is the deferred "merc/DMA blend-shape stomp" class:
a villain/merc draw corrupts a low GOAL address and the result lands on EE kernel
code, producing a scattered SIGILL/SIGSEGV at a non-fixed point in the cinematic.

This is SEPARATE from the already-fixed Gfix-cinematic-crash defect (the
deterministic frame-2340 `auto-save` process RET-to-NULL via a zeroed *kernel-
dram-stack* fake-stack RA at 0x19abb0, fixed by `handle_rftd_null_return`). The
residual here is DEEPER (render frame ~9400-9900, the misty-villain merc shots)
and intermittent.

## Reproduction + characterization (the BEFORE)
Repro harness `.autoport/gfix_cine_run.sh` drives the owner-exact path and watches
a 480s window through to gameplay (A35-RENDER frame ≥ 10500, foreground == jak1)
with robust crash detection (`GK-DIAG sig=(4|6|11)`, `Fatal signal`).

Soaking the owner cinematic many times on fresh HEAD established that **the stomp
reproduces every single run, deterministically**, and is currently CAUGHT by the
existing repair-and-resume defenses (so most runs survive — the owner's crash is
the rare race-loss escape of that catch):

  GMATCH-RFTD-STOMP frame=9911 first=goal:0x18aee4 was=0xf81f0ffe now=0x00000000
    (merc blend-shape draw stomped return-from-thread-dead; repaired)

(stomp frame varies run-to-run: 9911 / 9411 / 9703 — the source of the
non-determinism.) Victim = `return-from-thread-dead` (gkernel.gc:451), the
per-process RETURN TRAMPOLINE at GOAL 0x18aee4, plus its next word 0x18aee8.

### Naming the WRITER — three-stage forensic narrowing
1. **mips2c CPU-store telemetry (falsified).** A temporary widening of the
   `GND-OOB-WRITE` band (gnd_oob_check) to the kernel region [0x180000,0x1a0000)
   showed `target=0x18aee4` count = 0 across all runs while GMATCH-RFTD-STOMP
   still fired — so the zeroing does NOT go through any instrumented arm64 mips2c
   store (sw/sq/sqc2/spad_from_dma). The only kernel-region stores seen were
   legitimate data writes ~46 KB away (0x199xxx/0x19axxx). (This temp diagnostic
   has been removed — see Cleanup.)
2. **mprotect tripwire (decisive negative).** Arming the in-build A38 page
   tripwire (`debug.opengoal.a38.tripwire=1`, band 0x188000-0x190000) read-only
   on the page containing 0x18aee4 produced **hits=0** AND the app **died
   silently at the stomp frame** (no signal delivered to the in-process handler).
   A normal CPU store to the RO page would deliver SIGSEGV to the handler; the
   silent death with hits=0 proves the stomping write is performed **inside a
   signal handler** (a write to the RO page from within a handler faults
   recursively → SIGKILL), not by ordinary user code.
3. **DBLEE handler = the proximate writer (proven).** The build's double-EE-base
   fault handler `handle_double_ee_base_fault` (gk_android_main.cpp) repairs arm64
   stores whose address was mis-based with EE_base twice (faulting in the
   [2*EE_base, 2*EE_base+EE_SIZE) window) by writing the value to the corrected
   single-based address `corrected = fault - EE_base`. Its DBLEE-REPAIR logs show
   the corrected store targets are **ONLY 0x7f0018aee4 and 0x7f0018aee8** — i.e.
   the handler itself writes the merc draw's (zeroed) vector register onto the
   trampoline. The faulting GOAL pc/lr resolve to `vector-float*!` / `keg-post`
   (the merc blend-shape draw). DBLEE-REPAIR fired ~8×/run, all onto 0x18aee4/+8.

So the mechanism is: the cinematic merc/keg blend-shape draw computes a vector
store through a CORRUPT low base pointer; on arm64 the address is mis-based as
`2*EE_base + 0x18aee4`; the CPU store faults in the double-base window; the DBLEE
fault handler "completes" the store by writing the (garbage, zero) value onto
`EE_base + 0x18aee4` = the kernel trampoline. The completing write is what zeroes
`return-from-thread-dead`. Because the original store faults at a *different*
address (2*EE_base+...) and the corrupting write happens inside the signal
handler, it is invisible to every store-side telemetry and to the page tripwire —
exactly the A38-blind-to-DMA class, here pinned to the DBLEE completion path.

The owner's rare uncaught crash is the same-tick race: the DBLEE handler zeroes
the 16-byte trampoline word on the render/GOAL thread while the kernel-dispatch
thread RETs into `return-from-thread-dead`; if it fetches a partially-written
instruction that decodes to a valid-but-wrong branch/load (instead of the
all-zero `udf` that the in-band SIGILL repair reliably catches), control escapes
the guarded band and dies at a wild address — non-deterministic by construction.

## The fix (libgk-side, arm64/Android-only; x86 + goal_src + boot CGOs untouched)
`android/gk_android_main.cpp`, in `handle_double_ee_base_fault`, before completing
a STORE: if the corrected destination intersects the GOAL kernel asm-func code
band [0x18ae84, 0x1912b4) — the exact band the content canary already protects,
pure executable kernel code that is NEVER a legitimate GOAL store target — **DROP
the store** (do not write; skip the faulting instruction with pc+=4 and resume)
and log a bounded `GK-DIAG DBLEE-DROP-KERNELCODE` line. The source value is
garbage (a double-EE-based corrupt-base merc store), so dropping it loses nothing
real; the draw continues exactly as before, minus the garbage kernel-code write.

This kills the stomp **at its source, race-free**: the trampoline is never
corrupted (not even partially), so the per-frame canary and the in-band SIGILL
repair-and-resume never need to fire, and the same-tick cross-thread RET-into-
corruption escape (the owner's crash) cannot occur. Unlike a post-hoc repair, it
is deterministic and measurable: `GMATCH-RFTD-STOMP` and `RFTD-STOMP-REPAIR` go
to 0, replaced by `DBLEE-DROP-KERNELCODE`.

Why not a source/CGO fix: the writer is the deferred arm64 mips2c "global-buf.base
goes low / double-EE-base" codegen class, and the trampoline lives in KERNEL.CGO,
a boot CGO that cannot be safely standalone-rebuilt/pushed on this device
([[feedback-game-cgo-rebuild-unsafe]]). Intercepting the corrupt completion in the
already-existing arm64 fault handler is the durable, race-free libgk fix, in the
same repair-and-resume family the project established for this class
([[feedback-cross-thread-stomp-repair-resume]]).

## Verification (AFTER) — owner exact path, fix deployed (deploy_verify PASS)
The full owner cinematic was driven 10 times on the deployed fix. **10/10
gameplay-reaching runs completed crash-free** (frame ≥ 10500, foreground jak1, 0
real sig 4/6/11 / Fatal). Per run, every reaching run:

  - `GMATCH-RFTD-STOMP` = **0** (was 1/run) — the trampoline is never stomped.
  - `RFTD-STOMP-REPAIR` = **0** (was 8/run) — no in-band SIGILL to repair, because
    the corrupting store is dropped before it can touch the code.
  - `DBLEE-DROP-KERNELCODE` = **8/run** — the fix path fires; sample (run 10):
    `GK-DIAG DBLEE-DROP-KERNELCODE #1 corrected=goal:0x18aee4 sz=16 pc=goal:0x502ae0
     lr=goal:0x23ea9ac (merc blend-shape draw store onto kernel asm-func code
     [return-from-thread-dead band]; dropped, not completed)`.
  - `RFTD-NULLRET-REDIRECT` = 1/run — the pre-existing benign auto-save NULL-RA
    redirect (Gfix-cinematic-crash), expected and unrelated to this fix.

So the stomp is eliminated DETERMINISTICALLY and MEASURABLY (1→0 and 8→0 every
run), not merely "did not crash in N runs". One additional attempt aborted at boot
before frame 0 — the documented separate pre-existing ~1-in-several link-time boot
flake, NOT the cinematic crash — and was re-run to a clean REACH; excluded from the
cinematic verdict. `deploy_verify.sh eae4df44` = PASS (chain build==APK==device
f68b2bdfec3a28ed; libgk newer than source; device provably runs fresh HEAD). Full
per-run data: `.autoport/reports/Gcine-crash-mid/runs.txt`.

## x86 unbroken
The change is confined to `android/gk_android_main.cpp` (an Android-only TU, never
compiled into the x86 `gk` binary) inside an arm64 fault handler. x86 still links
to `link finish: logo`. No `goal_src/**` edits — the game source stays 1-to-1.

## Temp instrumentation / cleanup
The temporary writer-hunt diagnostics were REMOVED and the files restored to
pristine: the widened `gnd_oob_check` band and the two `spad_from_dma` band
widenings in `game/mips2c/mips2c_private.h`, and the raised log cap in
`game/mips2c/mips2c_table_jak1_arm64.cpp` — `git diff` on both files is now empty
and no `GCINE-MID-DIAG` markers remain anywhere. The A38 page tripwire used to
falsify the CPU-store hypothesis is an existing property-gated facility (left off,
`debug.opengoal.a38.tripwire=0`); no throwaway code was added for it. The only
permanent code change is the narrowly-gated, bounded-logging DBLEE drop guard
above (an extension of the existing always-on arm64 fault handler, logged exactly
like the sibling DBLEE-REPAIR / RFTD-STOMP-REPAIR lines, not a temporary dump).
The golden `.autoport/gold` remains pristine and git-clean.
