# Phase Gmenu-textures — main-menu icon/texture sprites bunch to center — fix the user-hvdf matrix being 0 on arm64

## The defect (owner) + the CONVERGED diagnosis (do NOT re-derive — go fix it)
Owner: "main menu still has ALL the textures garbled towards center." Three diagnostic attempts
already nailed the cause deterministically — your job is to FIX it, not re-investigate:

- The menu **TEXT options are a centered column BY ORIGINAL DESIGN** (relative-x-scale / font-matrix
  = 0.6 proportional-2D at 20:9; our-x86 == original-x86, byte-identical). **That is correct — do NOT
  touch it.**
- The owner's bunched **"textures" are the menu PARTICLE/ICON sprites**, positioned via a per-particle
  **user-hvdf matrix**. In `progress.gc`:
  - `:663` allocates it: `(if (= (-> self particles gp-0 part matrix) -1) (set! ... (sprite-allocate-user-hvdf)))`
  - `:522-523` uses it: `(if (> (-> this particles s5-0 part matrix) 0) (set-vector! (sprite-get-user-hvdf (-> ... part matrix)) ...))`
- **On device, `GMENU-DBG` proved `lc_matrix(s1+28) = 0`** — the particle's `part matrix` field is **0**
  (not the proper positive user-hvdf index, not -1). So the `(> matrix 0)` guard at :522 is FALSE →
  the `set-vector!` that positions each sprite is **SKIPPED** → the icon/texture sprites fall back to a
  0/default position = **bunched to center**. (A prior `bne s6,s7` 64-bit-compare patch in
  `sparticle_launcher.cpp` was confirmed IRRELEVANT — the field is already 0 in EE memory.)

## Mandate — find WHY the matrix field is 0 on arm64 and fix it (translation layer, 1-to-1 source)
`progress.gc`/`font.gc` are byte-identical to the original (1-to-1) — **do NOT edit goal_src.** The
GOAL logic is correct; the field is 0 because of an arm64-specific execution bug. Find which:
- `sprite-allocate-user-hvdf` returns 0 (should return a positive index) on arm64 — check its mips2c/
  C++ path and `*sprite-hvdf-control*` alloc-count state;
- OR the `part matrix` field allocation/store at :663 doesn't land on arm64 (a mips2c store /
  base-pointer / #f-guard / index bug);
- OR the field is stomped to 0 after allocation.
Fix at the source in the translation layer (`game/mips2c/**`, `game/graphics/**`, `goalc/**`,
`android/**`) so the menu particle `part matrix` becomes a valid positive user-hvdf index on device,
the `set-vector!` runs, and the icon/texture sprites are positioned correctly (matching the original).
x86 unaffected (our-x86 == original).

## Methodology (deterministic, x86-first, NO pixels)
Dump `lc_matrix` / `part matrix` (per menu particle) + the resulting sprite on-screen X positions on
**original-x86 (.autoport/gold)**, **our-x86 (HEAD)**, **device** at 2400x1080. BEFORE: device
`part matrix`=0 / sprites at center. AFTER: device `part matrix` = a valid index (>0, == x86) / the
icon sprites spread to their proper positions matching the original.

## Validator (`phase-Gmenu-textures.sh`) PASS requires
1. `.autoport/reports/Gmenu-textures/menu.txt`: device `part matrix`/`lc_matrix` BEFORE=0 → AFTER>0
   (== x86), and the menu icon/texture sprite X positions now match the original spread (not center),
   3-way (original-x86 / our-x86 / device). With `RESULT: ALL MENU ELEMENTS PLACED CORRECTLY (device, full draw list matches original)`.
   Name the arm64 root cause (why the matrix was 0).
2. **ZERO `goal_src/**` edits** (the fix is in the translation layer; menu source stays 1-to-1);
   our-x86 == original-x86.
3. Fix-summary `.autoport/reports/Gmenu-textures-fix-summary.md` ≥60 lines naming the arm64 cause +
   fix; temp instrumentation removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free to the menu; `deploy_verify.sh eae4df44`
   PASS; if a CGO-data fix is needed, the consolidated known-good backup is refreshed.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
Keep the device awake/unlocked. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
