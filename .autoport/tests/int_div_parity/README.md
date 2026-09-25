# int_div_parity

Differential bench for `arm64-integer-division-matches-x86`: builds the real
x86 32-bit idiv/udiv/imod/umod machine code with goalc's own emitter
(IGenX86.cpp), executes it natively on the host to get ground truth for a
large set of (a, b) int64 pairs (including divide-by-zero and INT_MIN/-1
overflow), then builds and executes the real arm64 `int_div_w` sequence
(IGenARM64.cpp) — plus the previous, replaced 64-bit `int_div_x` sequence,
reproduced locally as a witness that this bench can actually see the defect
it is meant to catch — under qemu-user or on a USB device, comparing every
result.

Run: `bash run.sh qemu` or `bash run.sh device <serial>`.

Consumed by `.autoport/lib/census/arm64-integer-division-matches-x86.sh`,
which publishes `int_div_arm64_x86_mismatch` as the gate value.
