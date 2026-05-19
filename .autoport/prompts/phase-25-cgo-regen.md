# Phase 25 — Re-emit jak1 CGOs with strict aarch64 verification

## Goal

Phase 14's CGOs are x86_64 (admitted in `android/android_goal_main.cpp:135`).
Phase 24 just proved the AArch64 emitter is real (or, if it's not, halted
honestly). This phase wipes `out/jak1/iso/` and `decompiler_out/jak1/`,
re-runs the phase-14 pipeline using the verified arm64 backend, and
**proves each produced CGO contains aarch64 code** via byte-level
disassembly — not by greping file names.

## Anti-stub rules

- Phase 14's existing CGOs MUST be discarded. The validator checks the
  modification time of each CGO and refuses to pass if any predates the
  start of this phase attempt.
- The validator uses `anti_stub_check_aarch64_bytes` on each CGO's code
  section. There's no way to satisfy this with a hand-edited byte blob —
  the bytes must come from `goalc-arm64` emitting real code.
- Don't shrink the synthetic check to a single tiny CGO. The validator
  checks **KERNEL.CGO**, **ENGINE.CGO**, **GAME.CGO** at minimum.
- Don't symlink the new CGOs to the old ones. The mtime check catches it.

## Concrete deliverables

1. **Wipe stale outputs:**
   ```
   rm -rf out/jak1/iso/ decompiler_out/jak1/
   ```
   (The decompiler cache invalidation is required because phase 14's old
   intermediates may reference x86 layouts.)

2. **Re-run the pipeline:**
   ```
   cmake --build build-arm64 --target goalc decompiler -j
   ./build-arm64/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc \
       ./iso_data ./decompiler_out
   ./build-arm64/goalc/goalc --auto-lt \
       --startup-cmd '(mi)(:exit)' --game jak1
   ```

3. **Stage into the per-flavor assets directory** (same as phase 14):
   ```
   rsync -a --delete out/jak1/iso/ android/app/src/jak1/assets/iso_data/jak1/
   ```

4. **Rebuild the APK** so the device tests in later phases pick up the
   new CGOs:
   ```
   ( cd android && ./gradlew assembleJak1Debug )
   ```

5. **Log a manifest** to `.autoport/logs/phase-25-cgos.tsv`:

   For each `*.CGO` in `out/jak1/iso/`:
   ```
   <name>\t<bytes>\t<mtime_epoch>\t<aarch64_ret_count>\t<x86_ret_count>
   ```

   The validator parses this manifest to assert real arm64 content.

## Don't

- Don't run goalc from `build/` (x86). Use `build-arm64/`.
- Don't `cp` x86 CGOs from a prior build as a "quick test". The mtime
  predicate is per-attempt and the byte predicate is global.
- Don't reuse phase 14's validator. This phase has its own validator
  with stricter byte checks.

## Pitfalls

- The decompiler is slow on first run (~10-30 min). The pipeline cache
  under `decompiler_out/jak1/` is rebuilt here because the schema must
  match what goalc-arm64 expects.
- `goalc --auto-lt --startup-cmd '(mi)(:exit)'` runs "make iso" then
  exits cleanly. If it segfaults mid-compile, that's an emitter bug for
  the specific GOAL source pattern that file uses — fix the emitter, do
  not skip the file.
- AGP may complain if the assets exceed its size limits; use
  `--debug-only` or accept the larger debug APK.

## Validator

```
.autoport/validators/phase-25-cgo-regen.sh
```

## Success

- Every `*.CGO` in `out/jak1/iso/` has `mtime ≥ phase_start_time`.
- KERNEL.CGO, ENGINE.CGO, GAME.CGO pass `anti_stub_check_aarch64_bytes`
  on their largest code section.
- Manifest at `.autoport/logs/phase-25-cgos.tsv` is non-empty and the
  aarch64-ret column dominates the x86-ret column for every entry.
- APK rebuild succeeds and `unzip -p $APK assets/iso_data/jak1/KERNEL.CGO`
  matches the bytes on disk (no stale APK).
