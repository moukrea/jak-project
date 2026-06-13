# Phase Gref — Pristine upstream x86 GOLD STANDARD + 3-tier comparison harness

## Purpose
We modified the compiler (`goalc`) to add an arm64 backend for the Android port.
Our *own* x86 build is therefore NOT a trustworthy reference: a bug our compiler
mods introduced into x86 codegen would live in BOTH our x86 and our Android
output, and a 2-way "our-x86 vs our-Android" diff would never see it. This phase
builds a **gold standard** from *pristine, unmodified upstream* and establishes
the comparison chain:

    Original (pristine upstream x86, 704972dd6)  ->  Our x86  ->  Our Android
                          \____ Tier A ____/        \____ Tier B ____/

- **Tier A (gold vs our-x86):** the insidious tier — catches compiler-mod leaks
  into x86. This is the key deliverable's verdict.
- **Tier B (our-x86 vs our-arm64):** the legitimate arm64 porting surface.

This is a REFERENCE-ONLY phase: it adds files under `.autoport/gold/` and
`.autoport/reports/`, and creates an out-of-tree build worktree. It does NOT
modify `goalc/`, `game/`, `goal_src/`, or `android/` (verified clean).

## Build provenance
- **Pristine commit:** `704972dd6a91616d1ce9964b5e7226df77a1fe27` — the exact
  merge-base where our fork diverges from `upstream/master`
  (`git merge-base HEAD upstream/master`). Building IT (not upstream HEAD) gives
  an apples-to-apples gold reference with zero upstream drift.
- **Worktree:** `/home/emeric/code/gold-jak-project` (detached HEAD @ 704972dd6).
  NOTE: it had to live at a path containing the substring `jak-project` —
  pristine `common/util/FileUtil.cpp` resolves the project root by
  `rfind("jak-project")` on `/proc/self/exe`, so `/home/emeric/code/jak-gold`
  failed project-path init; the worktree was `git worktree move`d to
  `gold-jak-project` (a name that resolves to ITSELF, not the main repo).
- **Toolchain/config:** plain `cmake ..` + `make` (Unix Makefiles, gcc 15.2.1),
  matching our `build-x86` (also empty `CMAKE_BUILD_TYPE`). goalc output is
  deterministic w.r.t. its own optimization level, so build-type does not affect
  the CGO/DGO bytes being compared.
- **Build flow** (the documented offline path):
  `cmake .. && make -j8 gk goalc decompiler` -> `scripts/shell/decomp.sh`
  (iso_data -> decompiler_out, "finished successfully in 5.50s") ->
  `scripts/shell/gc.sh --cmd '(make-group "iso")'`
  ("Successfully built all 1317 targets in 19.834s").
- **Artifacts produced & stashed under `.autoport/gold/`:**
  - `gk` — pristine runtime, 145,802,304 bytes (ELF; our build-x86 gk is
    146,257,368 bytes — `cmp` differs at byte 25, so genuinely distinct, NOT a
    copy).
  - `goalc` — pristine compiler, 9,004,664 bytes (ELF).
  - `cgo/` — KERNEL.CGO (92160), ENGINE.CGO (5321488), GAME.CGO (8758112).
  - `dgo/` — 25 DGOs (BEA…VI3).
  - logs: `cmake.log`, `build-cpp.log`, `decomp.log`, `make-iso.log`.
  - `pristine-boot-raw.log` — the raw 120s boot capture (1368 lines).
- **Safety:** our `out/jak1/iso/*.CGO` and `build-x86/game/gk` mtimes+sizes are
  byte-for-byte unchanged before/after the gold build (the worktree wrote only
  to its own tree). Verified.
- **RPATH caveat:** the stashed `gk`/`goalc` carry RUNPATH baked to the original
  `/home/emeric/code/jak-gold/build/...`. To RUN them, set `LD_LIBRARY_PATH` to
  the worktree's lib dirs (the remapped RUNPATH), e.g.
  `LD_LIBRARY_PATH=$(readelf -d .autoport/gold/gk | sed -nE 's/.*\[(.*)\].*/\1/p' | sed 's#/jak-gold/#/gold-jak-project/#g')`.
  The validator only `file`/size/`cmp`-checks the binary, so this does not gate
  the phase; it is documented for later phases that boot the gold gk.

## TIER-A VERDICT  (the central result)

> **Our x86 codegen is PRISTINE-IDENTICAL.** All 28 game objects (3 CGOs +
> 25 DGOs) are byte-for-byte identical (size AND md5) between the pristine
> upstream `704972dd6` build and our x86 build. **0 objects diverge.**

This proves our 46 goalc commits are **100 % arm64-gated** — they leak nothing
into the x86 backend. Consequences:
- Our x86 build is a trustworthy intermediate reference.
- Any Android divergence in later phases is the arm64 backend/runtime (Tier B),
  not a hidden corruption shared by x86 and Android.
Why this is expected: `goal_src` is unchanged across the fork
(`git diff 704972dd6 HEAD -- goal_src/` = 0 files); the arm64 work lives in a
separate gated backend (`goalc/emitter/IGen*arm64*`, `GOALC_BACKEND=arm64`
branches); the lone `common/` change (`dma_chain_read.h::base()`) is runtime-only
and never touches goalc output; the decompiler delta (2 files/18 lines) left all
jak1 extracted asset bytes identical (the DGOs match too). Full per-object table:
`.autoport/gold/tierA-cgo-diff.md`.

Fork delta for context (704972dd6 -> HEAD): goalc 27 files / +5495-473;
game/ 125 files / +10444-363 (runtime: arm64+android); common/ 1 file / +1;
decompiler/ 2 files / +18-6; **goal_src/ 0 files.**

## Pristine boot SEQUENCE (chronological ground truth)
`.autoport/gold/pristine-boot-sequence.log` captures the perfect pre-cinematic
order, two ways: SECTION A is the source-canonical state chain (from `goal_src`,
with file:line); SECTION B is the pristine RUNTIME-observed chronology (real
timestamps, "Compiled Version: 704972dd6") confirming A ran in order.

Key facts established:
- `*master-mode*` DEFAULTS to `'game` (gkernel.gc:270). **There is no
  `set-master-mode 'title`** — the SCE screen + ND logo + Jak&Daxter title-logo
  flythrough + press-start attract ALL run under master-mode `'game`.
- Chain: kernel boot -> `(play)` picks startup-level `'title` -> continue
  `"title-start"` -> target `(go target-title)` -> `target-title` shows the SCE
  static screen (texture, not a string) and spawns `logo 'ndi` (ND logo) +
  `logo 'logo` (title logo) -> `target-title-play` <-> `target-title-wait`
  (press-start attract) -> START opens the `progress` title menu (master-mode
  `'progress`) -> New Game does `(set-master-mode 'game)` + continue
  `"intro-start"` -> target `(start-sequence-a)` -> `sequenceA-village1` (the
  village1 / Geyser-Rock intro cinematic).
- The runtime confirmed it precisely: `link finish: logo` (03:10:664), then the
  spool-anims `ndi-intro` (ND logo, looping 03:10–03:22), then `logo-intro` /
  `logo-intro-2` (Jak&Daxter flythrough, 03:26+), looping `logo-loop` as the
  attract demo through the end of the run — and `sequence-a-village1` pre-linked,
  ready for New Game. With no controller input the run correctly HELD in the
  title attract (the desired "perfect pre-cinematic sequence").

## The 3-tier harness
`.autoport/gold/compare-3tier.sh` (executable). Usage:
- `compare-3tier.sh <OBJECT>` — one object (e.g. `KERNEL.CGO`, `TIT.DGO`):
  Tier-A (gold vs our-x86) + Tier-B (our-x86 vs our-arm64), with first-diff byte
  offset, sizes, and (for CGOs) per-tier structural metrics (object/function
  counts, x86-vs-arm64 RET opcode density via `.autoport/lib/cgo_structure_check.py`).
- `compare-3tier.sh --cgo` — the 3 code CGOs with structural dumps.
- `compare-3tier.sh --all` — every CGO + DGO present in gold.
- `compare-3tier.sh --boot GOLD_LOG OTHER_LOG` — diffs two boot logs by the
  canonical state-marker chain (logo / ndi-intro / logo-intro / logo-loop /
  target-title / set-master-mode / sequence-a …); reports any GOLD marker MISSING
  in OTHER = a chronological regression. Tier A if OTHER is our-x86 log; Tier B if
  OTHER is an Android logcat.

## How later (chronological-fix) phases use this
1. Boot Android, capture its logcat to a file.
2. `compare-3tier.sh --boot .autoport/gold/pristine-boot-sequence.log <android.log>`
   to see which intro/title/cinematic states are missing or out of order vs the
   pristine ground truth ("title over-spawns interactables", "SCE/ND skipped",
   etc.) — a precise diff instead of device guesswork.
3. For any object that misbehaves on Android, `compare-3tier.sh <OBJECT>` shows
   whether x86 already diverges from gold (a goalc bug to fix FIRST — Tier A) or
   only arm64 diverges (the expected porting surface — Tier B).

## Validator
`bash .autoport/validators/phase-Gref-pristine-x86-gold-standard.sh` checks:
reference-only (no engine edits), this summary (>=80 lines, Tier-A verdict), a
real distinct pristine `gk` ELF, `tierA-cgo-diff.md`, the non-trivial
`pristine-boot-sequence.log`, the executable harness, and that our x86 still
boots to `link finish: logo`.
