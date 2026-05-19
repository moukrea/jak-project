# Phase 19 — AArch64 emitter stress against real jak1 CGOs

## Goal

Phase 09's qemu-aarch64 boot only ran `gk --boot --headless` (no CGOs,
minimal harness). It proved the cross-built `gk` starts but did **not**
exercise the AArch64 emitter against real GOAL kernel code. This phase
closes that gap: run the cross-built `gk` under `qemu-aarch64-static`
**with** phase-14's CGOs (`out/jak1/iso/*.CGO`) and let it idle for 90
seconds. Any SIGILL, SIGSEGV in the runtime, or `qemu: uncaught …`
during the run is an emitter bug to fix in
`goalc/emitter/IGen_arm64.cpp` — *not* a runtime-wiring issue.

This phase is host-only (no Android device involved). It isolates
"is the AArch64 codegen correct for jak1?" from "is the Android runtime
wired correctly?" so phase 20's on-device failures don't get conflated
with latent emitter bugs.

## Constraints

- **Host-only.** No `adb`. No APK. No device required. Validator
  short-circuits if `qemu-aarch64-static` is missing with a clear hint
  to install `qemu-user-static`.
- **Do not regenerate CGOs unless an emitter bug is fixed.** Just run
  the stress test first; only if it fails AND you've fixed the emitter
  do you re-run `bash .autoport/validators/phase-14-jak1.sh` to
  regenerate.
- **Do not weaken phase 09 retroactively** to consolidate. They check
  different things (phase 09 = bring-up; phase 19 = real-CGO execution).

## Concrete deliverables

1. **A stress driver** at `.autoport/lib/emitter_stress.sh`:
   - Ensures `build-arm64/` has a current `gk` binary (rebuilds with
     `cmake --build build-arm64 --target gk` if stale).
   - Ensures `out/jak1/iso/` is populated with `*.CGO` files.
   - Launches `qemu-aarch64-static -L /usr/aarch64-linux-gnu build-arm64/.../gk`
     with arguments `--game jak1 --portable -fakeiso -iso-data
     $REPO/out/jak1/iso/ --headless` (the `--headless` flag in jak1
     suppresses SDL/GL init, so the runtime can run on a host without
     a display). If `--headless` doesn't exist yet on the runtime,
     you may need to add it under `#ifdef __ANDROID__`-less guard
     (it's a CLI flag, not platform-specific).
   - Tails the qemu stdout+stderr to a log file.
   - Watches for the boot sequence markers (within 60s):
     - `kheap_alloc: OK`
     - `KERNEL.CGO: loaded` (any byte count > 0)
     - `gkernel: dispatcher started`
   - Then **idles 90 seconds**, watching for any of:
     - `SIGILL` / `Illegal instruction`
     - `SIGSEGV` / `Segmentation fault`
     - `qemu: uncaught target signal`
     - `qemu: fatal:`
     - Process exit (unexpected — should still be idling)
   - On any of those: capture the faulting PC from qemu's diagnostic
     output (qemu prints `pc=0x...` and a register dump on SIGILL with
     `-d cpu_reset` or `-d in_asm`), then exit non-zero with that PC
     dumped to stderr.
   - On clean 90s idle: SIGTERM the gk process, print
     `emitter-stress: PASS (90s idle, 0 faults)`, exit 0.

2. **Diagnostic-mapping helper** at `.autoport/lib/cgo_lookup.sh`:
   - Given a faulting PC, identify which CGO + which GOAL function
     contains that code.
   - Pseudocode: `objdump -d build-arm64/.../gk | grep around PC` for
     runtime-side faults; for CGO-loaded code the PC is in mmap'd
     memory — use qemu's `-d in_asm` to dump the surrounding bytes,
     then grep those bytes in the CGOs to identify the source CGO.
   - This is a best-effort tool; doesn't need to be perfect.

3. **If the stress reports a fault**:
   - Use `cgo_lookup.sh` to identify the offending CGO function.
   - Inspect `goalc/emitter/IGen_arm64.cpp` for the encoding family
     that emitted that code. Common patterns to audit:
     - Branch encodings — wrong bit-field widths.
     - Load/store offset scaling — AArch64 imm12 is bytes for 8-bit
       loads, scaled by 4/8 for 32/64-bit. Easy off-by-3-bits bug.
     - Multi-register prologues — `stp x29, x30, [sp, #N]!` with
       wrong N.
     - NEON immediate encodings — `movi`, `mvni` have very specific
       form constraints.
   - Fix the emitter, then run **both** of these in order:
     ```
     bash .autoport/validators/phase-14-jak1.sh   # regenerate CGOs
     bash .autoport/validators/phase-19-emitter-stress.sh   # re-test
     ```
   - The phase-14 validator already exists from autoport's earlier
     run; it has its own pre-conditions but should mostly just rerun
     goalc against the existing GOAL sources.

## Don't

- Do **not** add x86-equivalent shims to make the emitter "work" by
  routing around a bug. If the bug is in NEON encoding, fix the NEON
  encoder.
- Do **not** disable `-Werror` in goalc to suppress diagnostics that
  point at the emitter site.
- Do **not** vendor a different AArch64 assembler library. The emitter
  is hand-rolled by design (phases 01-08); the path to correctness is
  fixing it.

## Pitfalls

- **qemu-aarch64-static** needs `-L /usr/aarch64-linux-gnu` (Fedora
  package `glibc-aarch64-linux-gnu`) so the dynamic linker can resolve
  arm64 libc. Same as phase 09.
- **`--headless`** in the jak1 runtime: check the actual flag name with
  `./build-arm64/.../gk --help` — it may be `-nohead`, `--no-display`,
  or similar. Whatever it is, use it so the qemu run doesn't try to
  open a display.
- **qemu user-mode is slow.** Don't be alarmed if 90s of stress runs in
  ~10x wall-clock (~15 minutes). That's normal.
- **PC reported by qemu is the AArch64 PC**, not a host x86 PC. To map
  to source: find the CGO whose code section was mmap'd at that
  address. The runtime should log
  `kdgo: mapping <FILE.CGO> code at 0x...` somewhere — if not, add it.

## Validator

```
.autoport/validators/phase-19-emitter-stress.sh
```

Runs `emitter_stress.sh`. Passes only if the stress reports
`emitter-stress: PASS`. Faults = fail with the captured PC + context
dumped.

## Success

`bash .autoport/validators/phase-19-emitter-stress.sh` exits 0 with
`emitter-stress: PASS (90s idle, 0 faults)` in the output. The
AArch64 emitter is now verified against real jak1 GOAL code, not just
synthetic test corpora.
