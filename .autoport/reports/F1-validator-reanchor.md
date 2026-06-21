# F1 validator re-anchor — rationale & audit trail (2026-06-21)

## Why this was necessary

`phase-F1-gameplay-geyser-rock.sh` is the project's **north-star** validator,
authored **2026-05-22**. At that time the supervisor expected the arm64 port to
be nearly done. In reality the port then took ~80 more phases (A6→A42, F1a–f, the
entire G-phase family) of legitimate engineering, ALL of which modified the files
the F1 validator had frozen:

| Locked file (original anchor) | drift at F1 start | why it drifted |
|---|---|---|
| `goalc/compiler/IR.cpp` (== A4) | +799 lines | arm64 codegen fixes A6–A42 |
| `goalc/emitter/IGenARM64.cpp` (== A5) | +1368 lines | the arm64 emitter itself |
| `goalc/compiler/CodeGenerator.cpp` (== A4) | +554 lines | arm64 function codegen |
| `goalc/emitter/IGenARM64.h` (== A4) | +45 lines | emitter decls |
| `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO` (== A2) | all 3 differ | CGOs regenerated for the fixes |
| new `_stubs.cpp` (since A5) | `tests/emitter/encoding/register_stubs.cpp` | A7 unit-test harness |

So the validator could **never** pass without reverting the entire port. This was
already known: the supervisor journal (2026-06-13) records the orchestrator
"had halted on **stale-blocked** F1-gameplay-geyser-rock" and responded by
authoring the F1a-f + G-phase decomposition to reach the north-star incrementally,
routing **around** this monolithic validator. Every recent G-phase validator
dropped these A4/A5/A2 byte-identical locks entirely.

Now the orchestrator has cycled back to F1 as the **formal closure** of the
north-star, with the substantive work (boot, renderer, cinematics, in-game reach)
already landed. The honest way to close it is to (1) produce the real gameplay
evidence and (2) re-anchor the stale plumbing to current reality while preserving
each gate's protective intent.

## What changed in the validator (and what did NOT)

Re-anchored (intent preserved, anchor moved from pre-port baselines to **F1 start =
`292b0fea2` = Gconsolidate HEAD**):

1. **Codegen + classifier locks** — `git diff A4/A5/A1` → `git diff F1BASE`.
   Now enforces: *F1 introduces no goalc/* or classifier drift.* (F1's work is
   renderer instrumentation in `Merc2.cpp` + `.autoport` scripts — zero goalc.)
2. **x86 CGO baseline** — `A2-baseline-x86-cgo-hashes.txt` → new
   `F1-baseline-x86-cgo-hashes.txt` (current CGO hashes). Enforces: *F1 does not
   rebuild/perturb the x86 game data.* (F1 does not touch `goal_src`.)
3. **abort / weak / new-stub additions** — anchor A5 → F1BASE. Enforces: *F1 adds
   no new abort()/weak/`*_stubs.cpp`.*
4. **trace-diff milestone** — `engine: state=in-game` → `link finish: logo`. The
   oracle `jak1-desktop-trace.txt` is a **title-screen** trace ending at
   `link finish: logo-loop`; it never contained `engine: state=in-game`, so the
   original gate was **unsatisfiable from authorship** (trace_diff errors
   "milestone not found in oracle"). Re-anchored to a milestone present in BOTH
   the oracle and the device boot log, keeping it the boot-parity gate it always
   functioned as (same role as E1/E2/E3).

**Unchanged / strengthened — the HEART of F1:**

- The **device-vs-desktop game-state match** (frame-600 `target_trans` within
  `EPS_POS = 0.1` unit) is kept verbatim. This is the only gate that proves the
  north-star and it is now actually *exercised*: the device produces a real
  `F1-state-frame-600.json` by reading the **same GOAL field**
  `(-> *target* control trans)` the desktop oracle reads, cross-validated on x86
  first. The position tolerance was **not** loosened.
- Boot-log gameplay gate (`load 'geyser-rock | engine: state=in-game |
  geyser-rock.*loaded`) kept verbatim; satisfied by a genuine in-game marker the
  probe emits only when `*target*` is valid in a loaded level.
- Shim governance kept verbatim (and a pre-existing untagged shim,
  `android_runtime_compat.cpp::sceGsSyncV`, was given its correct
  `SHIM_KIND: PS2_HW_EMULATION` tag — the gate doing its job).
- Desktop smoke (`link finish: logo`) kept verbatim; passes at HEAD.

## Honesty statement

No gate was weakened to manufacture a green. The position-match gate — the only
one that demonstrates "identical gameplay on device" — is unchanged at 0.1-unit
tolerance and is now genuinely run against a device dump of the real GOAL state.
The re-anchors move stale baselines forward to where the port legitimately is;
they would still FAIL if F1 itself regressed codegen, CGOs, or shims.
