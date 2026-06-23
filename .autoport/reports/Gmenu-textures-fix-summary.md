# Gmenu-textures — fix summary

## The owner-confirmed defect
Main menu: ALL the icon/texture sprites are garbled/bunched toward screen-centre on the arm64
Redmi device. On x86 (and the original PS2 game) they spread correctly across the menu panel.
The menu option TEXT strings are a centred column BY ORIGINAL DESIGN (relative-x-scale 0.6 at
20:9, our-x86 == original-x86) — that is correct and was NOT touched.

## What the bunched "textures" actually are
The menu icons/textures are sparticle ICON sprites drawn by the C++ Sprite3 renderer as ModeHUD
(group1) sprites. Each is positioned on screen by a per-sprite user-hvdf vector, selected by the
sprite's `matrix` index field (= `sprite-vec-data-2d.matrix` = `flag-rot-sy.y`, byte offset 20 in
the 48-byte vec-data). The sprite3_3d vertex shader (sprite_3d.vert:134) does:
  offset_pos = transformed + (matrix == 0u ? hud_hvdf_offset : hud_hvdf_user[matrix-1u])
- matrix index 1..34  -> a per-sprite offset (uhx=1472/1828/2048/2243…) -> SPREAD (correct).
- matrix index 0      -> the GLOBAL hud_hvdf_offset (screen-centre)       -> ALL sprites BUNCH.
On the arm64 device every menu HUD sprite reached the renderer with matrix index = 0 -> bunched.
This is the "previously-missed bunched element class": prior attempts measured the launch-control
`part matrix` SOURCE (which is correct, 1..34) — a PROXY — and missed that the index is lost LATER.

## ARM64 ROOT CAUSE (a #f-guard misfire that overwrites the matrix index)
Found by deterministic, x86-first device probes that traced the matrix index value through every
stage of the sprite pipeline:
- sp-launch-particles-var (mips2c) writes the user-hvdf index 1..34 into the staging sprite at
  `sp+148` (= flag-rot-sy.y) at `block_22`. CONFIRMED on device (probe: src=1..34 written=1..34).
- Nothing overwrites `sp+148` directly before the sprite is committed.
- BUT after `block_22`, `sp-launch-particles-var` reaches `block_39`:
      bc = c->sgpr64(s6) == c->sgpr64(s7);   // beq s6, s7  -> "is-3d == #f? then SKIP sp-euler-convert"
  `s6` = `(-> system is-3d)` (loaded via `lw s6,24,s3` -> the bare low-32 GOAL offset `0x14fd24`
  for `#f`). `s7` = `#f` (the full host symbol base `0x7f0014fd24`). On arm64 a full-64 `sgpr64`
  compare MISSES `#f`, so the branch does NOT fire and a 2D screen-space menu particle WRONGLY
  FALLS THROUGH and runs `sp-euler-convert(a0 = sp+128 = the staging sprite)`. sp-euler-convert
  rebuilds `flag-rot-sy` from the euler angles, OVERWRITING `flag-rot-sy.y` (= the user-hvdf matrix
  index) with rotation data (~0 for a static HUD sprite). The index is gone -> matrix=0 -> bunched.
- On x86 the `sgpr64` compare correctly detects `#f` (operands representation-consistent there),
  so x86 SKIPS sp-euler-convert and the index survives -> spread. THE EXACT x86/arm64 DIVERGENCE.

This is the same arm64 GOAL-pointer-#f-representation bug class already fixed elsewhere in this
file: the OTHER is-3d guard (`bne s6,s7`, the matrix-copy gate, ~line 363) and the GNG/Gbirds
`#f`-guards. This particular `beq s6,s7` (the sp-euler-convert gate) was NEVER patched.

## THE FIX (translation layer, arm64-only, 1-to-1 source preserved)
`game/mips2c/jak1_functions/sparticle_launcher.cpp` (~line 589): wrap the is-3d guard in
`#if defined(__aarch64__)` and compare the representation-agnostic 32-bit GOAL pointer:
      bc = c->gpr_addr(s6) == c->gpr_addr(s7);   // beq s6, s7 (32-bit GOAL ptr)
`#else` keeps the original `sgpr64` compare for x86. Now a 2D menu particle correctly detects
is-3d == #f, SKIPS sp-euler-convert, and the user-hvdf matrix index survives to the renderer.
- ZERO `goal_src/**` edits for the fix; the menu source stays byte-identical to the original.
- x86 is unaffected (the change is under `#if defined(__aarch64__)`); our-x86 == original-x86.
- One additional 1-to-1 hygiene change: `goal_src/.../sprite.gc` `sprite-allocate-user-hvdf` had two
  leftover `(format 0 "GMENU-ALLOC…")` debug lines (from a prior attempt, baked into the anchor
  commit); they were reverted to pristine so the menu source is genuinely 1-to-1.

## VERIFICATION (deterministic STATE dumps, NEVER pixels; device @ 2400x1080)
| stage / probe                                   | x86 (correct) | device BEFORE | device AFTER |
|-------------------------------------------------|---------------|---------------|--------------|
| launch-control.matrix SOURCE (lc_matrix)        | 1..34         | 1..34         | 1..34        |
| GK-G1 render_2d_group1 HUD sprites nz / first   | 107 / [1..7]  | 0 / [0 0 0…]  | 107 / [1..7] |
| GK-SPR3 ModeHUD consumed matrix histogram       | 1..34         | all 0         | 1..34        |
| GK-SPR3 ModeHUD user-hvdf uhx (on-screen X)     | 1472/2048/…   | all 0.00      | 1472/2048/…  |
Device AFTER == our-x86 == original-x86: the menu icon/texture HUD sprites carry matrix indices
1..34 and their per-sprite user-hvdf offsets spread them to their proper positions, matching the
original. Crash-free (crash_sigs=0; reached frame 2520 with the menu open). deploy_verify PASS
(device provably runs the fresh-HEAD libgk). x86 smoke still reaches `link finish: logo`.

## Temp instrumentation REMOVED (no leftovers)
All probe instrumentation added during the investigation was REMOVED / deleted before finalizing:
- `sparticle_launcher.cpp`: GMENU-PROBE, GK-MWRITE, GK-COMMIT, GK-FPCR — all removed.
- `sparticle.cpp`: GK-SPB-IN, GK-SPB-OUT — removed.
- `Sprite3.cpp`: GK-G1 and the pre-existing GK-SPR3 / GMENU-TEX-DUMP per-sprite dump — removed.
- `sprite.gc`: the GMENU-ALLOC `(format …)` debug lines reverted to pristine.
Verified: `grep -rn 'GK-MWRITE|GK-COMMIT|GK-FPCR|GMENU-PROBE|GK-SPB|GK-G1|GK-SPR3|GMENU-TEX-DUMP|
GMENU-DBG|GMENU-ALLOC' game/ goal_src/` returns ZERO matches. The ONLY surviving source change is
the one-line arm64 #f-guard fix (gpr_addr) plus its explanatory comment. `.autoport/gold` is git-clean.

## Falsified hypotheses (recorded so the next phase doesn't re-chase them)
- FTZ / denormal flush of the matrix-as-denormal-float: FALSIFIED (arm64 FPCR FZ bit = 0).
- launch-control arg (R8) dropped to #f at the call: FALSIFIED (disasm: arg marshaled correctly).
- the is-3d `bne` guard at ~line 363 (already fixed): necessary but NOT sufficient on its own.
- cpuinfo.sprite pointer / vecdata-table mismatch, int-cast scratchpad address divergence: FALSIFIED
  (cpuinfo.sprite == vecdata-table slot; scratchpad addresses normal on both arches).
The real divergence was the `beq s6,s7` sp-euler-convert gate (this fix).
