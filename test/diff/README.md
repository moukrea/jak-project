# Differential test harness (`test/diff`)

This is the keystone of the OpenGOAL → AArch64 port. Every later phase
gates on it. The premise: for each tiny `.gc` input under `inputs/`, the
existing x86-64 backend and the new AArch64 backend must produce
semantically equivalent execution traces.

## Layout

```
test/diff/
├── CMakeLists.txt        # ctest registration
├── inputs/               # .gc source files (the test corpus)
├── expected/             # captured expected output, used as golden-file fallback
├── runner/               # the goalc-diff-runner CLI
│   ├── runner.cpp
│   └── CMakeLists.txt
└── README.md
```

## Conventions for `.gc` inputs

Each input is a self-contained GOAL program with two directives in
leading comments:

```
;; tags: <comma-separated tags>
;; expect: <exactly one line of expected stdout>
```

Every input ends by printing a single line — typically
`(format #t "~D~%" <result>)` — and that line is what `expect:`
records. The runner extracts the last non-empty stdout line as the
"final state" so the diff harness can compare results without needing
to capture the entire program image.

Tags are surfaced as ctest labels (`backend-x86`, `backend-arm64`, plus
whatever the input declares), so a subset can be run with
`ctest -L int-arith` etc.

## The runner

```
goalc-diff-runner --input <path.gc> --backend x86|arm64 --capture <output-dir>
```

The runner writes four artifacts into the capture directory:

| File          | Meaning                                      |
| ------------- | -------------------------------------------- |
| `exit_code`   | exit status of the executed program          |
| `stdout`      | complete stdout of the executed program      |
| `stderr`      | complete stderr of the executed program      |
| `final_state` | last non-empty line of stdout (the "answer") |

Exit codes from the runner itself:

| Code | Meaning                                                    |
| ---- | ---------------------------------------------------------- |
| 0    | run succeeded, capture written                             |
| 1    | CLI / IO error                                             |
| 2    | input file unreadable or missing required directive        |
| 77   | backend not implemented — treated as SKIP by ctest         |

## Phase 00 scope

Right now only the scaffolding ships:

- `--backend x86` reads the input's `;; expect:` directive and writes
  it as captured stdout. **It does not yet invoke `goalc`.** The whole
  point of phase 00 is to nail down the CLI surface, the capture
  layout, and the ctest wiring so later phases can plug in real
  compilation.
- `--backend arm64` prints "not implemented" and exits 77.

Later phases will replace the body of `run_x86()` with a real call to
the existing `goalc` entry point, and `run_arm64()` with a real call to
the new AArch64 emitter (executed under `qemu-aarch64-static`).

## Running the suite

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --target goalc-diff-runner
cd build && ctest -R goalc-diff --output-on-failure
```

The arm64 tests will report as `Skipped` until phase 01 lands.
