# codegen_scalar — perf-codegen-arm64-scalar parity test

Proves, on real arm64 (qemu-user or device), that the NEW scalar sequences
goalc emits for float->int, integer divide, swizzle and pshuflw/hw give the
SAME results as the model in `model.h` and, where applicable, as the LEGACY
sequences reproduced in `legacy.h` from commit ff7b7ba1e0. Also proves the
`inspect_scalar` detector (`game/system/codegen_arm64_scalar.h`) correctly
tells new from legacy sequences apart.

`gen` (host x86-64) links the real `goalc/emitter/IGenARM64.cpp`, checks the
float->int model against the x86 CVTTSS2SI instruction over all 2^32 bit
patterns, checks the detector, and writes `build/cases.bin`: standalone arm64
machine code for every kernel. `runner` (arm64, built with the NDK) mmaps that
file executable and runs every kernel, printing `key=value` lines.

Run: `bash run.sh qemu` or `bash run.sh device <serial>` (no network serials).
