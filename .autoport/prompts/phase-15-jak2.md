# Phase 15 — Jak 2: compile game data and produce app-jak2-debug.apk

## Goal

Same pipeline as phase 14, but for Jak II.

```
iso_data/jak2/                              ← user puts Jak II disc contents here
goal_src/jak2/                              ← decompiled GOAL source (upstream)
out/jak2/iso/                               ← goalc output
android/app/src/jak2/assets/iso_data/jak2/  ← jak2 flavor assets staging
app/build/outputs/apk/jak2/debug/app-jak2-debug.apk   ← output
```

## Why this gets its own phase

Jak 2's decompilation coverage in OpenGOAL upstream is less mature than
Jak 1's. Different GOAL source files exercise different codegen paths
and tend to surface emitter bugs the Jak 1 build didn't hit.

When you hit a failure, fix the **emitter or runtime**, not the GOAL
source. The decompiled GOAL source is the contract.

## Pipeline

Identical to phase 14, swap `jak1` → `jak2`. Reuse the host goalc /
decompiler built in phase 14.

## Constraints

- Reuse the host goalc binary built in phase 14 if it's still on disk
  (the validator does).
- Do not regress phases 12-14. Specifically: `assembleJak1Debug` must
  still succeed after this phase.
- The jak1 flavor's assets must not leak into the jak2 APK. Keep
  per-flavor assets strictly under `src/jakN/assets/`.

## Validator

```
.autoport/validators/phase-15-jak2.sh
```

Same checks as phase 14, scoped to `jak2`.

## Success

`out/jak2/iso/*.CGO` produced, staged into the jak2 flavor, and
`assembleJak2Debug` produces a signed APK containing the assets.
