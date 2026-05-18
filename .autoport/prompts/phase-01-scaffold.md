# Phase 01 — AArch64 emitter scaffold

## Goal

Create a stub AArch64 backend that mirrors the public interface of the existing x86-64 emitter. No real codegen yet — every function is a stub that emits a `brk #0` (AArch64 break instruction) or returns a "not implemented" marker. This phase is about establishing the skeleton CMake can compile and link.

## Why this is a distinct phase from real codegen

If we try to implement real codegen at the same time as wiring up the backend selection, debugging is impossible — you can't tell whether a failure is "the backend isn't selected" vs "the backend's add instruction is broken." Split scaffold from implementation.

## Concrete deliverables

1. **New files**, mirroring the structure of `goalc/emitter/`:
   - `goalc/emitter/IGen_arm64.h` — declares the same public surface as IGen.h but for the arm64 namespace.
   - `goalc/emitter/IGen_arm64.cpp` — every function is a stub that:
     - logs "TODO arm64: <function name>" to stderr
     - emits a `brk #0` instruction (encoding `0xD4200000`) into the instruction stream
     - returns whatever the x86 version returns (usually an Instruction or void)
   - `goalc/emitter/CodeTester_arm64.h` / `.cpp` — analogous to the x86 CodeTester, but for arm64 execution under qemu.

2. **A CMake option** `-DGOALC_BACKEND=x86|arm64` (default `x86`).
   - When `arm64`, the build:
     - Adds the new IGen_arm64.cpp to the goalc target
     - Defines a preprocessor macro `GOALC_BACKEND_ARM64`
     - Conditionally selects the arm64 implementations in the few `#ifdef`s you'll need to add at the call sites in `goalc/compiler/` and `goalc/regalloc/`.
   - When `x86`, build is byte-identical to today.

3. **Backend selection plumbing**: identify the small number of places where the emitter is actually dispatched and add the `#ifdef GOALC_BACKEND_ARM64` switch. There should be only 3-5 such sites. Use grep to find them; do NOT modify regalloc logic in this phase (we'll deal with the different register file in phase 05).

4. **Verification target**: A new CMake test `goalc-arm64-scaffold-smoke` that:
   - Builds with `-DGOALC_BACKEND=arm64`
   - Runs `goalc --version` and confirms exit 0 and that it advertises "backend: arm64" in its output (add this to the version string)
   - Runs `nm` on the goalc binary and confirms the IGen_arm64 symbols are present

## Constraints

- Do NOT touch the regalloc.
- Do NOT implement any real arm64 encoding logic. `brk #0` for everything.
- Preserve the x86 build path: `cmake -B build && cmake --build build` (no flag) must produce a functioning x86 goalc.
- All new code under `goalc/emitter/` and at most a tiny CMake/dispatch addition elsewhere.

## Approach hints

- Read `goalc/emitter/IGen.h` end-to-end before you start writing IGen_arm64.h. The function signatures are extensive; mirror them exactly.
- The `CodeTester` is what actually executes the generated machine code. For arm64, executing on an x86 host requires either (a) qemu-aarch64-static via fork+exec, or (b) skipping arm64 codegen execution in tests for now. Pick (b) for this phase — make CodeTester_arm64 throw a "not implemented" exception on `execute()`. We'll fix this in phase 02.
- The CMakeLists.txt under goalc/emitter/ probably uses a glob or explicit list. Use the same convention.

## Success criteria

```bash
cmake -B build-x86 -G Ninja
cmake --build build-x86 --target goalc
cmake -B build-arm64 -G Ninja -DGOALC_BACKEND=arm64
cmake --build build-arm64 --target goalc
nm build-arm64/goalc/goalc | grep IGen_arm64   # must find symbols
./build-arm64/goalc/goalc --version | grep -i "arm64"  # must say arm64
```
