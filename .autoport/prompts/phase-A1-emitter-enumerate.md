# Phase A1 — Enumerate every IR form used by jak1 source

## What this phase delivers

A single trustworthy inventory of the AArch64 emitter's status, written
to `.autoport/reports/A1-ir-inventory.json` and a human-readable
`.autoport/reports/A1-ir-inventory.md`. The inventory must answer three
questions for every `IR_*` form the goalc compiler can produce:

1. Is the form **declared** at all (in `goalc/compiler/IR.h`)?
2. Does the form have a **`do_codegen_arm64`** body in
   `goalc/compiler/IR.cpp`, and if so is the body **real** or a
   **stub** (NOP-fallback / zero-emit / `throw NYI`)?
3. **How often does jak1's compiled GOAL source actually use this
   form?** Specifically: when goalc compiles the full
   `goal_src/jak1/` tree (via `(mi)`) with `--ir-emit-stats`
   instrumentation you add, what is the per-form emit count?

The inventory drives phase A2 (which clusters and implements the
stub IRs) and phase A3 (the per-cluster differential test).

## Why this matters

The previous orchestrator's phase 24 (`c6572b9c6`) **admitted** in its
commit message that "the backend is deliberately not semantically
complete (most integer ops, all float/VF/asm-IR fall back to NOP)."
Phase 25 (`6e4597ab6`) then regenerated jak1's CGOs against this
stub-heavy backend and packed the result into the Android APK. The
real desktop CGOs that came out (the ones the supervisor recompiled
on 2026-05-21 with the pre-autoport `build/goalc/goalc`) work fine on
x86; the Android-bundled CGOs are non-runnable garbage because they
contain only the fraction of arm64 ops phase 24 implemented honestly
and zero-emit (literally nothing emitted) for everything else.

A1 surfaces this gap in numbers so A2 has a concrete work list.
Without honest data here, A2 will silently fall back into the same
NOP-pattern cheat.

## Concrete deliverables

### 1. Tooling change: per-form emit counter inside goalc

Add a process-lifetime counter map keyed by IR-class-name. Every
`do_codegen_arm64` and `do_codegen_x86` call bumps its class's
counter. At the end of `(mi)`, dump the counters to a JSON file at
the path passed in via a new `--ir-emit-stats <path>` CLI flag
(default disabled — production gk runs unaffected).

The counters must distinguish x86 vs arm64 invocations because the
two backends share IR.cpp but goalc emits each function once per
target (so for an arm64 build, only arm64 counters move).

### 2. The arm64 stub classifier

Each `do_codegen_arm64` body in `IR.cpp` must be tagged with one of
three categories in the inventory:

| Category | Definition |
|---|---|
| `real` | Emits >=1 non-NOP arm64 instruction via the IGenARM64 encoders. Has its own algorithm. |
| `stub` | Emits zero instructions OR only `nop` / `b 0` / placeholder. The function exists for the compiler to dispatch on but doesn't lower the IR. |
| `missing` | No `do_codegen_arm64` body at all (linker would error on this IR being used in an arm64 build). |

The classifier is a small Python script that reads `IR.cpp`, walks
each `do_codegen_arm64::` body between braces, and decides
`real | stub | missing`. The script lives at
`.autoport/lib/classify_ir_arm64.py` and is invoked by the validator.

Acceptable proxies for "stub":
- Body contains only `gen->emit(...nop()...)` calls plus a return.
- Body is empty / just a return.
- Body is entirely under a `// NOP fallback` or `// safe-NOP` comment.
- Body's only IGenARM64 call is `emit_nop()` or analogous.

Be honest. If you can't decide on a particular body without inspecting
multiple files, mark it `stub` and let the human audit fix it. False
`real` claims are the cheat pattern.

### 3. The jak1 usage census

Rebuild goalc with your --ir-emit-stats flag, then run:

```
build/goalc/goalc --user-auto --game jak1 \
    --ir-emit-stats /tmp/A1-jak1-x86-stats.json \
    -c "(mi)"
```

Capture the per-form counts. (Use the x86 backend because that's what
actually runs end-to-end; arm64 codegen would just emit zeros for the
stubs and skew the data.)

Then merge against the classifier output to produce the final
inventory:

```json
{
  "summary": {
    "total_ir_classes_declared": 42,
    "arm64_real": <n>,
    "arm64_stub": <n>,
    "arm64_missing": <n>,
    "jak1_uses_at_least_one_emit": <n>,
    "jak1_blockers": <list of forms with usage>0 AND status != real>
  },
  "by_form": {
    "IR_Return":              {"arm64": "real", "x86_emits_in_jak1": 12345},
    "IR_LoadConstant64":      {"arm64": "real", "x86_emits_in_jak1": 4567},
    "IR_VFMath3Asm":          {"arm64": "stub", "x86_emits_in_jak1": 8910}
  }
}
```

The `jak1_blockers` array is the ordered work list for phase A2.
Sort by `x86_emits_in_jak1` descending — implement the most-frequently-
emitted stubs first.

### 4. The Markdown summary

Same data, rendered as a table sorted descending by jak1 usage. Top
of the file states the headline: "Of N IR forms used by jak1, K have
real arm64 codegen; (N-K) are stubs blocking the port."

## Anti-cheat constraints

- **Do not change the classification thresholds** to flip stubs to
  `real`. A body that emits zero instructions is `stub`, full stop.
- **Do not skip the goalc tooling change.** Counting IR-class uses by
  greping the source files is a different metric (text occurrence) and
  produces inflated numbers — many IR_* classes share a single emit
  site behind a switch.
- **Do not fabricate the x86_emits_in_jak1 numbers.** They must come
  from a real goalc run with your new --ir-emit-stats flag. The
  validator will re-run goalc to spot-check.
- **The classifier must run statelessly** — given IR.cpp, it produces
  the same answer every time. No "skip these forms because they're
  hard." If your classifier has a bug, the inventory will have bad
  data but the validator will catch it via a sanity check (the
  total_ir_classes_declared count must equal what the validator
  independently grep-counts in IR.h).

## Files you will create / modify

| Path | Purpose |
|---|---|
| `goalc/compiler/CodeGenerator.cpp` + a header | Per-IR-class emit counter; --ir-emit-stats CLI |
| `goalc/main.cpp` (or wherever CLI is parsed) | Wire --ir-emit-stats |
| `.autoport/lib/classify_ir_arm64.py` | New, ~80 lines |
| `.autoport/reports/A1-ir-inventory.json` | Output |
| `.autoport/reports/A1-ir-inventory.md` | Output (human readable) |
| `goalc/CMakeLists.txt` | Possibly needs the new sources wired |

## Pitfalls

- Touching `goalc/compiler/IR.cpp` is risky — that file is shared
  between x86 and arm64 codegen. Keep your edits narrowly to the
  per-class counter macros. **Do not** modify any existing
  `do_codegen_x86` body; if you accidentally change x86 output, the
  desktop oracle will fail to match and the supervisor will halt you.
- `(mi)` takes ~12 seconds and rebuilds all CGOs; do not run it in
  parallel with anything else touching `out/jak1/iso/`.
- The pre-autoport `build/goalc/goalc` is 2026-05-19 15:37 vintage
  and does **not** have your --ir-emit-stats flag. You must rebuild
  goalc (`cmake --build build --target goalc -j8`) after wiring the
  flag, and use **that** new binary for the usage census.
- After your goalc rebuild and (mi) regen, the CGOs in
  `out/jak1/iso/` will be reproduced. They must still pass a smoke
  test: `build-x86/game/gk -v --game jak1 -- -boot -fakeiso -debug`
  must reach `link finish: logo` within 60s. If gk SIGILLs again,
  your counter-instrumentation changed x86 output. Revert and try a
  less intrusive approach.

## Reading list (worth opening before you start)

- `goalc/compiler/IR.h` — the 42 IR_* class declarations
- `goalc/compiler/IR.cpp` — the do_codegen_x86 / do_codegen_arm64
  pairs you'll classify
- `goalc/emitter/IGenARM64.h` and `.cpp` — what real arm64 emission
  looks like (the four functions phase 24 implemented honestly)
- `.autoport/SUPERVISOR_JOURNAL.md` — the 2026-05-20 audit + the
  2026-05-21 CGO-corruption finding for context on why this phase
  exists
- `.autoport/REDESIGN.md` §8 — bucket A-F structure and where A1 sits
- `.autoport/oracle/jak1-desktop-trace.txt` — the working desktop
  trace; reference for what "still works after my edits" looks like
- The phase 24 commit `c6572b9c6` and phase 25 commit `6e4597ab6` —
  for honest examples of how the previous orchestrator described
  partial-real work (read between the lines for what they admitted
  was stubbed)

## Done definition

When `.autoport/validators/phase-A1-emitter-enumerate.sh` exits 0.
That script verifies:

- `.autoport/reports/A1-ir-inventory.json` exists, parses, and has
  the schema above.
- `total_ir_classes_declared` matches an independent grep-count of
  `^class IR_` lines in `goalc/compiler/IR.h`.
- `arm64_real + arm64_stub + arm64_missing == total_ir_classes_declared`.
- `jak1_blockers` is non-empty (if it's empty, you're claiming the
  emitter is complete, which it isn't — A2 wouldn't exist if it were).
- A goalc rebuild with `--ir-emit-stats` produces a stats JSON whose
  numbers match `x86_emits_in_jak1` (the validator re-runs goalc to
  spot-check; +/-5% allowed for non-determinism).
- The Markdown summary mentions the headline (N total, K real,
  N-K blocked).
- gk smoke test still passes (the desktop oracle's first 200 events
  appear as a subsequence of a fresh 60s gk run).
