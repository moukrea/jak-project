# Phase 00 — Differential test harness

## Goal

Build the infrastructure that will let us validate every later phase by comparing the output of the existing x86-64 GOAL compiler backend against the future AArch64 backend.

**This phase is the keystone of the entire port.** Spend time on it. Get it right.

## Why this matters

Compiler bugs don't cause unit-test failures — they cause "the game runs for 30 minutes then crashes mysteriously." A diff-test harness gives us a deterministic oracle: for each tiny .gc input, both backends must produce semantically equivalent execution traces. Every later phase will gate on this harness.

## Concrete deliverables

1. **Directory structure** under `test/diff/`:
   ```
   test/diff/
   ├── CMakeLists.txt
   ├── inputs/          # .gc source files
   ├── expected/        # captured expected output per input (for golden-file fallback)
   ├── runner/
   │   ├── runner.cpp   # the actual harness
   │   └── CMakeLists.txt
   └── README.md
   ```

2. **A CMake target `goalc-diff-runner`** that:
   - Accepts CLI args: `--input <path.gc> --backend x86|arm64 --capture <output-dir>`
   - Invokes `goalc` with the appropriate backend (right now, only x86 works; arm64 is a stub that exits with a clear "not implemented" message)
   - Executes the compiled output. Native run on x86 host. Under `qemu-aarch64-static` for arm64.
   - Captures: exit code, complete stdout, complete stderr, and (where feasible) a final-state snapshot (e.g., a printout of a designated debug variable that the test programs end with).
   - Writes capture artifacts to `<output-dir>/{exit_code,stdout,stderr,final_state}`.

3. **A ctest harness `goalc-diff`** that:
   - Globs `test/diff/inputs/*.gc`.
   - For each input, runs both backends.
   - Tags each test with labels from a frontmatter comment in the .gc file (e.g., `;; tags: int-arith, basic`).
   - At this phase, arm64 runs are EXPECTED to fail; the test should be skipped (not failed) when arm64 returns "not implemented". This will flip later.

4. **Five baseline `.gc` test inputs** under `test/diff/inputs/`:
   - `00-hello.gc` — print a constant integer, exit
   - `01-add.gc` — `(+ 2 3)`, print result
   - `02-loop.gc` — sum 1..10 with a recursive function
   - `03-func.gc` — define a helper function, call it from main
   - `04-cond.gc` — `(if (> x 0) ...)` with two paths

   Each begins with a tag comment, e.g.:
   ```
   ;; tags: basic, int-arith
   ```

5. **Top-level integration**: append the new test/diff directory to the repo's top-level CMakeLists.txt so `cmake --build build` builds it.

## Constraints

- Do **NOT** modify any file under `goalc/emitter/`. The arm64 backend doesn't exist yet.
- Do **NOT** modify anything under `goal_src/`.
- All new code lives under `test/diff/` plus the one-line CMake addition.
- The runner must work both when invoked from CMake (ctest) and standalone from the shell.
- The runner must NOT require root, network, or anything outside the build tree.

## Approach hints (think hard about these before coding)

- The existing goalc CLI: study `goalc/main.cpp` to understand how to invoke compilation programmatically. You may be able to call a C++ entry point directly from the runner rather than fork+exec.
- For "final state capture", the simplest approach is: each test .gc ends with `(format #t "~D~%" <result>)` and the runner just compares the last line of stdout. Document this convention in `test/diff/README.md`.
- Use `qemu-aarch64-static` (statically-linked binfmt handler is registered on the host). Invocation: `qemu-aarch64-static -L /usr/aarch64-linux-gnu ./binary`.
- Make ctest output verbose enough that the orchestrator can grep for `Passed`/`Failed` per test.

## Success criteria

Validator runs the following sequence and all must succeed:

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --target goalc-diff-runner
test -x build/test/diff/runner/goalc-diff-runner
ls test/diff/inputs/*.gc | wc -l  # must be >= 5
cd build && ctest -R goalc-diff --output-on-failure
# At least 1 PASS on the x86 side per input
```

## Validation feedback loop

After your changes:
1. Run `bash .autoport/validators/phase-00-harness.sh` yourself.
2. Read its output carefully.
3. Fix anything it complains about.
4. Re-run until it exits 0.

Only then is the phase done.
