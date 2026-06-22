# Gbirds-anim — fix summary

## Owner ground truth
On the Jak1 title screen the birds over the tower **render but are STATIC** — no
flight bob, no wing animation. This phase re-baselined on the fresh consolidated
HEAD, proved with deterministic per-game-frame anim-advance dumps (NEVER pixels)
that the device birds were genuinely frozen, found the arm64 translation defect,
fixed it in the translation layer, and re-measured the device birds advancing
1-to-1 with the original.

## Verdict
**REAL arm64 bug — fixed.** Unlike the recent stale-deployment re-dos
(Gwater-lod / Ghalo / Gparticles-stars, which already worked on fresh HEAD), the
title birds were genuinely frozen on the fresh consolidated HEAD device build.
Deterministic measurement: `bird-bob-func` dispatched **5168×** on our-x86 but
**0×** on the device — the bird animation callback never ran on arm64.

## What the birds are (so the metric reflects the defect, not a proxy)
The title flyover renders village1 behind the logo. The birds over the sage-hut
tower are the sparticle group `group-village1-sagehut-seagulls` (defpartgroup id
132, `goal_src/jak1/levels/village1/village1-part.gc:699`). They are NOT a skeletal
`ja`-animated process. The flight "animation" is the per-frame sparticle `:func`
callback `bird-bob-func` (`village1-part.gc:754`, defpart 415), which sets the
bird's bob:
`y = root.y + (* -2048.0 (sin (* 218.45334 (mod (current-time) 300))))`.
So the bob is a deterministic function of `current-time` (= `(-> *display*
base-frame-counter)`, the per-game-frame anim clock). Callback runs each frame with
an advancing clock => bob-y oscillates => bird flies. Callback never dispatches =>
bob-y never changes => bird static. THE METRIC dumped is exactly this: per game
frame, the bird's current-time + the bob-y that bird-bob-func writes (one latched
bird, ci=0x1a0130). This is the actual defect signal, not a builder-count proxy.

## Root cause (x86-first localization, then device-confirmed)
The `:func` callback is dispatched inside the mips2c `sp-process-block-2d`
(`game/mips2c/jak1_functions/sparticle.cpp`) at block_13: it loads the per-particle
func field (cpuinfo +112) and `jalr`s it. That dispatch is reached only via block_8,
which block_1 routes to when the `(paused?)` arg `s2` equals `#f`. block_1's two
`beq reg, s7` (#f) checks — `(-> cpuinfo valid)` at +128, and `s2` — used the
full-64 `sgpr64` compare and **LACKED** the arm64 low-32 `gpr_addr` guard that the
sibling `sp-process-block-3d` block_1 already had.

On arm64 a GOAL pointer loaded via sign-extended `lw` arrives as the bare low-32
offset, while gpr `s7` holds the full host symbol base (0x7f…). A full-64 compare
therefore MISSES `#f`. The `s2`(paused?)==#f branch that routes a LIVE 2D particle
to block_8 (the func-dispatch path) was never taken on arm64, so the bird fell
through to the skip path and `bird-bob-func` was never dispatched. x86 is unaffected
(operands consistent there) — which is exactly why x86 dispatched 5168× and the
device 0×. The 2D block was simply never given the fix the 3D block received
(same documented arm64 mips2c #f-guard bug class as Gd2/Gsprite/Gnewgame).

## The fix (translation layer only; NOT goal_src)
`game/mips2c/jak1_functions/sparticle.cpp`, `sp_process_block_2d` block_1: add the
`#if defined(__aarch64__)` low-32 `c->gpr_addr(...)` guard to BOTH `beq v1,s7`
(valid +128) and `beq s2,s7` (paused?) #f-checks, mirroring `sp_process_block_3d`
block_1 verbatim. The change is arm64-gated; the x86 `#else` branch keeps the
original `sgpr64` compares byte-for-byte. No `goal_src` edit; `.autoport/gold`
pristine. `restore_knowngood_device.sh` only swaps CGO/DGO files (not libgk), so
this libgk fix persists across a restore — no owner regression.

## Evidence (deterministic, x86-first, no pixels)
- our-x86: 5168 samples; current-time advances (constant dt); bob-y oscillates over
  envelope **384582.2812 .. 388678.2812**.
- original-x86 == our-x86 (1-to-1) by source identity: bird path git-clean, only
  change arm64-gated, x86 codegen untouched; gold ships no instrumentable full
  source, so source-identity is the strongest gold comparison (same pattern as
  Gwater-lod).
- device BEFORE (no guard): **0** bird dispatches → bob Δ=0 → FROZEN (owner defect
  reproduced).
- device AFTER (guard): **4338** bird dispatches → bob-y oscillates over the
  **identical** envelope 384582.2812 .. 388678.2812 (same min/max, same latched
  bird) → ANIMATES, crash-free, app foreground.
Full data in `.autoport/reports/Gbirds-anim/birds.txt` and the
`our-x86-gbirds.txt` / `device-before-gbirds.txt` / `device-fixed-gbirds.txt`
captures.

## Temporary instrumentation — REMOVED
The GBIRDS2D dump (a C++ logging hook + freeze toggle + a `bird-bob-func`/`*display*`
symbol cache + helper functions + the cstdio/cstdlib/system_properties includes,
all in `sparticle.cpp`) was used to capture the 3-way anim-advance data. It has been
fully **removed**: `git diff` of `sparticle.cpp` now shows ONLY the permanent
`#if defined(__aarch64__)` block_1 guard; a repo-wide grep for `GBIRDS`, `gbirds_`,
`bird_bob_func`, `debug.gbirds` returns no leftover matches in `game/` or
`android/`. No dump code remains in the build.

## Verification of the clean build (post-removal)
- x86: rebuilt clean; reaches `link finish: logo` (no regression).
- android: rebuilt clean libgk; assembled slim APK; installed; `deploy_verify.sh
  eae4df44` PASS (build==APK==device, device provably runs fresh HEAD).
- device boot sanity on the clean build: reaches title, crash_lines=0, focus
  org.opengoal.gk.jak1 (the empty `device-clean-gbirds.txt` is expected — the dump
  was removed).

## Files
- Fixed: `game/mips2c/jak1_functions/sparticle.cpp` (sp_process_block_2d block_1
  arm64 #f-guard).
- Report: `.autoport/reports/Gbirds-anim/birds.txt`.
- Captures: `.autoport/reports/Gbirds-anim/{our-x86,device-before,device-fixed,
  device-clean}-gbirds.txt` and matching logs.
- Harness (reusable): `.autoport/gbirds_device_dump.sh`.
- No `goal_src/**` change; `.autoport/gold` untouched/pristine.
