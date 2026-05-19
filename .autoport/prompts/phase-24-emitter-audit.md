# Phase 24 — AArch64 emitter byte-pattern audit on real GOAL source

## Goal

Phases 01-08 produced an "AArch64 emitter". Phase 09 booted Jak 1 under
`qemu-aarch64`. Phase 14 was supposed to use that emitter to compile jak1
into arm64 CGOs. Phase 19 was supposed to stress-test the emitter on
those CGOs. **All four claimed success, yet `out/jak1/iso/KERNEL.CGO`
contains x86_64 native code** (admitted in
`android/android_goal_main.cpp:135-138`). Something in this chain
silently failed and the validators didn't catch it.

This phase audits the AArch64 emitter directly with synthetic GOAL source
and a byte-level disassembly check. If the emitter is genuinely
non-functional, this phase fails with that diagnosis and the orchestrator
must fix `goalc/emitter/IGen_arm64.cpp` until the audit passes.

## Anti-stub rules (read these first)

The previous phases were defeated by stubs emitting log strings the
validators grep'd for. This phase's validator cannot be satisfied by log
strings. It demands **physical bytes that disassemble as aarch64**.

Specifically forbidden moves:
- Editing the validator to be more lenient when the emitter is broken.
- Emitting `printf("emitter: ok")` and calling that proof of correctness.
- Filling object code sections with hand-written aarch64 bytes (a literal
  `ret` blob, etc.) to pass the disassembly check. The bytes must come
  from `goalc-arm64` compiling the synthetic test program below.
- Claiming "the emitter passes synthetic tests, but jak1 source is too
  complex" and moving on. If jak1 source breaks the emitter, that IS the
  bug to fix here.

If the emitter is fundamentally broken (e.g., phases 01-08 were also
stub-passing), declare it via `device_fail` with a clear root cause and
let the user pivot. Do not paper over it.

## Concrete deliverables

1. **A minimal test GOAL file** at `test/arm64/emitter_smoke.gc`:

   ```lisp
   (defun fortytwo () 42)
   (defun add1 ((x int)) (+ x 1))
   (defun ifelse ((cond int)) (if (zero? cond) 10 20))
   (defun loop10 ()
     (let ((acc 0))
       (dotimes (i 10) (set! acc (+ acc i)))
       acc))
   ```

2. **A build invocation** that compiles `emitter_smoke.gc` with the
   AArch64 backend:

   ```
   cmake -B build-arm64 -G Ninja -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=Release
   cmake --build build-arm64 --target goalc
   ./build-arm64/goalc/goalc --auto-lt \
       --startup-cmd '(asm-file "test/arm64/emitter_smoke.gc")(:exit)'
   ```

   Output: a CGO file or raw object output at a path the validator can read.

3. **A CGO inspection helper** at `.autoport/lib/cgo_inspect.py`:

   - Parses the OpenGOAL CGO container format (see
     `decompiler/data/dir_types.cpp` and `goalc/data_compiler/` for the
     existing parser to crib from; do NOT reinvent the format).
   - Lists object entries: name, code-section offset and length.
   - Dumps the code section of a named function as raw bytes to stdout.

4. **Validator outputs**:

   - For each of `fortytwo`, `add1`, `ifelse`, `loop10`:
     - Extract its code section via `cgo_inspect.py`.
     - Run `aarch64-linux-gnu-objdump -D -b binary -m aarch64
       --adjust-vma=0` on it.
     - Assert: at least one canonical aarch64 ret (`ret  // d65f03c0`) in
       the disassembly.
     - Assert: standard prologue `stp x29, x30, [sp, ...]` OR a `sub sp,
       sp, #imm` opening.
     - Assert: zero occurrences of `(bad)` mnemonics in the first half of
       the disassembly. Arm64 has fixed 4-byte instructions; if objdump
       reports "(bad)" repeatedly, the bytes are not arm64.
   - Differential: for the same `fortytwo`, also run the x86 disassembler
     (`objdump -D -b binary -m i386:x86-64`) on the same bytes. Assert
     that the x86 decode produces a **higher** rate of `(bad)` than the
     arm64 decode. (If x86 decodes cleanly and arm64 produces `(bad)`s,
     the bytes are x86 not arm64.)

5. **No log-string check.** This phase's validator does NOT grep for any
   `__android_log_print` output. The proof is in the disassembled bytes.

## Don't

- Do not use `clang -target aarch64` to assemble hand-written assembly
  and pass that off as goalc output. The test must exercise the
  **goalc-arm64 emitter**, not a clang front-end.
- Do not skip building goalc with `-DGOALC_BACKEND=arm64`. If the cmake
  cache has a stale value, `rm -rf build-arm64/CMakeCache.txt` and
  reconfigure.
- Do not change the synthetic test program to make it easier to compile.
  If the emitter chokes on `dotimes`, that's a real emitter bug — fix
  it in `goalc/emitter/IGen_arm64.cpp`.

## Pitfalls

- The CGO format header bytes confuse naive disassemblers. Use the
  `cgo_inspect.py` parser to extract the code section precisely, then
  pass raw bytes to objdump with `-b binary --adjust-vma=0`.
- aarch64 NOP is `0x1f 0x20 0x03 0xd5` — emitter MAY or MAY NOT emit them
  for padding. Their absence is fine.
- `aarch64-linux-gnu-objdump` exits 0 even on bad input. Always inspect
  the output ratio, not the exit code.
- Some emitter test paths in the existing repo are wired to differential
  test mode (compare x86 output to a golden). Don't touch those — they're
  for phases 01-08. Phase 24 is a separate fresh path.

## Validator

```
.autoport/validators/phase-24-emitter-audit.sh
```

## Success

The four functions from `emitter_smoke.gc` compile via `goalc-arm64`,
their code sections disassemble cleanly as aarch64 with canonical
prologue/ret, and the same bytes do NOT disassemble cleanly as x86. No
log-string checks involved. If the emitter is fundamentally broken, the
phase fails honestly and the orchestrator can iterate on the emitter
source.
