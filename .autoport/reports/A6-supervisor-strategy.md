# A6 supervisor strategy note (2026-05-22 23:00)

Written by the supervisor in parallel to claude's tactical work. Read
this if you're a future A6/A7 worker iterating on emitter-correctness
bugs after the dispatcher started actually running.

## Pattern observed across A5+A6 attempts

The "fix-one, find-next" cascade is real but slow because each
iteration requires a full ~3-min device boot cycle. Bugs found so far,
in fix order:

1. A5: LDR/STR W-form imm12 overflow (16KB s7-reach cap → patcher
   substituted 691 NOPs)
2. A5/A6: skip-flag dodge that hid the dispatcher's bytecode crashes
3. A6: 6 off-register helpers in IGenARM64.cpp dropped EE-base reg
4. A6: `make_function_from_c` emitted x86_64 unconditionally
5. A6: klink sym-PTR ADRP+ADD needed MOVZ+MOVK rewrite with GOAL offset
6. A6: FFI trampoline shuffle GOAL arg regs → AAPCS slots
7. A6: stack-arg trampoline shuffle
8. A6 (in flight): `call_r64` BLR caller-save register clobber

## Underexploited tools that would speed up A6/A7

### qemu-aarch64-static — function-level testing without device

`/usr/bin/qemu-aarch64-static` is installed. Running the regenerated
arm64 CGOs under qemu (via the existing linux-arm64 build target —
see `game/linux-arm64/CMakeLists.txt`) would let you:

- Test ONE bytecode crash in seconds instead of 3 min per device
  cycle
- Iterate on emitter fixes 10-30x faster
- Catch arm64-specific bugs without Bionic-vs-glibc noise

Suggested setup:
```bash
# Build linux-arm64 native (under qemu user-mode)
cmake -S . -B build-arm64-linux \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build-arm64-linux --target gk -- -j$(nproc)

# Run gk on the arm64 CGOs under qemu
qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    build-arm64-linux/game/gk \
    --game jak1 --portable -fakeiso -iso-data out/jak1-arm64/iso \
    -- -boot -debug-mem
```

If linux-arm64 gk boots through `link finish: gstate` + `engine:
state=` under qemu but Android doesn't, the bug is Bionic-only. If
linux-arm64 also crashes at the same offset, the bug is purely
arm64-emitter — fix in goalc and the desktop arm64 trace will fix
itself.

### Arm64 oracle trace

We currently only have `.autoport/oracle/jak1-desktop-trace.txt` (x86
desktop). Once linux-arm64 boots cleanly under qemu, capture its
trace as `.autoport/oracle/jak1-arm64-trace.txt`. Then trace-diff the
Android run against the arm64 oracle — divergence points reveal
exactly which GOAL function executes differently on Android.

### Decode the crash PC offset against the regenerated CGO

Repeated SIGSEGV at `<anonymous>+0x36b7a84` (and earlier
`+0x36b7c14`) is in the GOAL bytecode heap. Concretely:

- Read the arm64 KERNEL.CGO file table to find which GOAL function's
  code section spans heap-offset 0x36b7a84
- Disassemble that function's first ~50 bytes with
  `aarch64-linux-gnu-objdump -D -b binary -m aarch64`
- The function name will tell us which GOAL source file's `(defun
  ...)` is broken

If `+0x36b7c14` and `+0x36b7a84` are in the same GOAL function (480
bytes apart), they're likely two crash sites in the same function's
prologue/epilogue mismatch.

### Fast cycle: edit → rebuild goalc → emit one CGO → qemu test

```bash
cmake --build build --target goalc -- -j$(nproc)
build/goalc/goalc -c "(mi kernel)" -fno-color
qemu-aarch64-static -L /usr/aarch64-linux-gnu build-arm64-linux/game/gk ...
```

~30 seconds per cycle vs 3 minutes via device.

## Strategic suggestion to claude

If you're reading this mid-A6 and you've cycled through 3+ emitter
helpers each crashing in a different GOAL function — STOP, build
linux-arm64 + qemu, and find ALL the failing functions in one
qemu run. Fix them as a batch. The device cycle is too slow for the
shotgun approach the current iteration pattern uses.

## What I'd want the next A6/A7 validator to enforce

(For future-supervisor-me reauthoring validators):

1. Image entropy > N at frame 60 (aspect-blind; catches blue-screen
   false-pass)
2. Trace-diff against a real **arm64** oracle (not x86), through
   `engine: state=in-game` milestone
3. Run BOTH qemu-linux-arm64 AND device, require both pass with the
   same trace
4. Require `(format ...)` test functions in test suite produce
   identical output between desktop x86, qemu-linux-arm64, and
   Android — catches register-allocator + ABI bugs cheaply

— supervisor
