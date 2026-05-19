# Phase 14 — Jak 1: compile game data and produce app-jak1-debug.apk

## Goal

Cross-compile Jak 1 GOAL source to AArch64-targeted CGO on the host,
stage the output under the jak1 product flavor's assets, rebuild the
APK, and verify the resulting `app-jak1-debug.apk` ships the data.

This is the first phase that actually exercises the AArch64 emitter
(phases 1-7) on real GOAL source instead of synthetic diff-test corpora.
Real GOAL code (kernel.gc, vector.gc, transformq.gc) hits much higher
register pressure than the toy tests.

## Inputs the user must provide

The PS2 ISO is not redistributable. The user puts their extracted Jak &
Daxter disc contents under:

```
iso_data/jak1/
```

This is the same path the desktop build uses. The validator fails fast
if it's empty.

## Pipeline this phase must wire up

1. `cmake -B build -G Ninja -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=Release`
   configures the host build with the AArch64 codegen path active.
   Important: this is a host x86_64 build of `goalc` and `decompiler`
   that *targets* AArch64 in the CGO output. Cross-compilation in the
   "host-binary emits target-native-code" sense, not a cross-toolchain
   sense.
2. `cmake --build build --target goalc --target decompiler` produces the
   two host binaries.
3. `./build/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc
      ./iso_data ./decompiler_out`
   extracts and preprocesses the ISO contents (slow on first run, cached
   thereafter under `decompiler_out/jak1/`).
4. `./build/goalc/goalc --auto-lt --startup-cmd "(mi)(:exit)" --game jak1`
   compiles `goal_src/jak1/` into `out/jak1/iso/*.CGO` (and STR files).
5. Mirror `out/jak1/iso/` into the jak1 product flavor's assets:
   `android/app/src/jak1/assets/iso_data/jak1/`.
6. `./gradlew assembleJak1Debug` rebuilds the APK with the data bundled.
7. (Optional, if an emulator is running) `adb install -r` the APK,
   launch with `am start`, inspect logcat for an engine-init line.

## Constraints

- Do NOT change desktop x86 behavior. The arm64 backend must not regress
  the x86 backend. CI verifies both.
- Do NOT pre-compress or repack the CGO output. The runtime reads the
  exact bytes goalc emits.
- If `goalc` segfaults on a specific file, treat it as an emitter bug
  and fix the emitter — do not skip the file.
- Per-flavor assets must land under `src/jak1/assets/iso_data/jak1/`,
  NOT under `src/main/assets/`. This way the jak2 and jak3 APKs in
  phases 15-16 don't accidentally ship Jak 1 data.

## Pitfalls

- `goalc` is a long-running interactive REPL by default. The flag
  combination `--auto-lt --startup-cmd "(mi)(:exit)"` runs a one-shot
  "make iso" then exits.
- Decompilation is slow on first run (~10-30 min). Cached output under
  `decompiler_out/jak1/` should be reused on subsequent attempts —
  the validator doesn't blow it away.
- The arm64 backend's register allocator may differ from x86 in spill
  decisions. Real GOAL files exercise these paths in ways the synthetic
  corpora don't.
- The compiled APK may exceed 100 MB. Sideload-style debug APKs have
  no hard cap, but Play Store does. If `assembleJak1Debug` rejects the
  size, switch to `bundleJak1Debug` (AAB with asset packs) per phase
  13's instructions.

## Validator

```
.autoport/validators/phase-14-jak1.sh
```

Pass conditions enforced:
- iso_data/jak1/ non-empty (user input)
- host goalc + decompiler build with GOALC_BACKEND=arm64
- decompiler_out/jak1/ produced
- out/jak1/iso/ contains > 0 CGO files
- android/app/src/jak1/assets/iso_data/jak1/ populated
- `assembleJak1Debug` produces a debug-signed APK containing those assets

## Success

`app-jak1-debug.apk` at
`android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk` contains
`assets/iso_data/jak1/kernel.cgo` (or equivalent canonical file).
