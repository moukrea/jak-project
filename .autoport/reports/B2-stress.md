# Phase B2 — arm64 CGO decode-stress under qemu

> Decode-stressed 8241 functions across 3 CGOs. SIGILL=0, prologue-SIGSEGV=0, body-SIGSEGV=5694 (tolerated), timeout=1034, clean=1513, unknown-opcode=0.

## Per-CGO breakdown

| CGO | fns | disasm-clean | exit-clean | body-segv | sigill | timeout | other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| KERNEL.CGO | 197 | 197 | 34 | 163 | 0 | 0 | 0 |
| ENGINE.CGO | 3845 | 3845 | 725 | 2643 | 0 | 477 | 0 |
| GAME.CGO | 4199 | 4199 | 754 | 2888 | 0 | 557 | 0 |

## Method

- Disasm: `aarch64-linux-gnu-objdump -D -b binary -m aarch64` on each function's raw bytes; `.inst` pseudo-ops (undefined encodings) are counted as bad disasm.
- Execute: a static aarch64 ELF per CGO (built by `b2_wrap_fn.py`) hosts all functions; the harness (`test/arm64/b2_harness.S`) is parameterised by `argv[1]` = function index, sets x30 to a safe-exit trampoline that does `exit_group(x0 & 0xff)`, mmap's a 64 KB scratch page at `0x40000000`, points x15/x22 there, zeroes x0..x7, and `br`s into the function.
- `sigsegv_in_prologue` is 0 by construction: the kernel-provided process stack at `_start` is mapped, writable, and 16-aligned, so the universal GOAL prologue `stp x29, x30, [sp, #-16]!` cannot fault.
