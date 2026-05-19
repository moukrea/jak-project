# Phase 16 — Jak 3: compile game data and produce app-jak3-debug.apk

## Goal

Same pipeline as phases 14 / 15, but for Jak 3.

```
iso_data/jak3/                              ← user puts Jak 3 disc contents here
goal_src/jak3/                              ← decompiled GOAL source
out/jak3/iso/                               ← goalc output
android/app/src/jak3/assets/iso_data/jak3/  ← jak3 flavor assets staging
app/build/outputs/apk/jak3/debug/app-jak3-debug.apk   ← output
```

## Risk note

Jak 3's upstream coverage is the least mature of the three. If this
phase fails for reasons that are clearly upstream desktop bugs (not
arm64 emitter bugs), **stop and surface it** rather than burning turns
patching upstream issues.

A "clean" failure mode here is the validator reporting that goalc
crashed on a specific source file — that's an arm64 backend bug worth
fixing. A "muddy" failure mode is desktop x86 also failing on the same
file — that's upstream's problem and should be documented under
`.autoport/logs/jak3-known-issues.md`.

## Constraints

- Same as phase 15.
- The jak1 and jak2 flavors' APKs must still build cleanly after this
  phase.

## Validator

```
.autoport/validators/phase-16-jak3.sh
```

Same checks, scoped to `jak3`.

## Success

`out/jak3/iso/*.CGO` produced, staged into the jak3 flavor, and
`assembleJak3Debug` produces a signed APK containing the assets.
