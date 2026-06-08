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

## Phase A2 scope (real compile + execute)

The runner now compiles and executes for real, build-once / run-many:

- `--all-inputs <dir> --backend x86 --capture-root <dir>`: compiles each
  input with the x86 `goalc` backend and **executes it on an in-process
  `gk` runtime** (kernel + engine loaded, headless), capturing the printed
  line. Run once as a ctest *setup fixture*.
- `--all-inputs <dir> --backend arm64 ...`: compiles each input with the
  **ARM64 `goalc` backend** (real color + codegen) and then attempts
  execution via the aarch64-linux cross runtime under
  `qemu-aarch64-static`. That cross runtime currently boots but crashes
  mid-boot (no Deci2 listener), so arm64 inputs cannot yet be executed —
  recorded as **honest failures** with a captured boot probe
  (`captures/arm64/_boot_probe.txt`), never stubbed green.
- `--check --input <f> --backend <b> --capture <dir>`: cheap comparison of
  the captured `final_state` against the input's `;; expect:` directive.
  One such ctest per (input, backend), gated on the setup fixture.

`final_state` is the **first** non-empty captured line: the program's
`(format ...)` output precedes the listener's echo of the `(main)` return.

Honest outcomes: x86 inputs that don't compile standalone (e.g. self
recursive functions not forward-declared, or `new 'stack-no-clear`
arrays) fail with the real captured compiler error; output mismatches are
reported as captured diffs. arm64 inputs fail pending a listener-capable
cross runtime.

## Running the suite

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --target goalc-diff-runner
cd build && ctest -R goalc-diff --output-on-failure
```

ARM64 tests now **run** (no longer `Skipped`); they currently fail
honestly until the cross runtime can host a listener.
