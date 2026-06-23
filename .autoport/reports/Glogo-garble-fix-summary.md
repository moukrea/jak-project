# Glogo-garble — fix summary

**Owner ground truth (2026-06-22):** the Jak&Daxter logo-smash (breaking the black
screen) renders **GARBLED/CORRUPTED** on the arm64 device — the mesh looks
scrambled/torn during/after the smash. The prior `Glogo-smash` phase false-greened
on "tris render + animation state matches" (both blind to visual corruption).

**Verdict:** FIXED. The smash now renders clean on the device (gold JAK·AND·DAXTER
letters + blue speed-line burst, matching the pristine golden). The fix is an
arm64-only translation-layer change; our-x86 == original-x86, 1-to-1, no goal_src
edit.

---

## What the phase premise got wrong (and the real root cause)

The phase was framed around a `GND-OOB-WRITE` firing ~400x during the logo intro,
assumed to be an out-of-bounds write **stomping the logo geometry**. Two findings
overturned that premise:

1. **The GND-OOB-WRITE is a FALSE POSITIVE — the ocean filling `global-buf`
   in-bounds.** All ~400 "band" hits are `kind=q/Q` 16-byte VU stores to a
   contiguous GOAL-offset range `0x51a990..0x51bff0` of **sane vertex-coordinate
   floats** (no NaN/garbage), from `ocean_interp_wave` / `ocean_generate_verts`
   (addr2line on a fresh self-consistent build; cross-checked against the x86 ocean
   path). x86-first proof: `global-buf` on our-x86 spans GOAL `[0x53c590,0xd0a590)`
   (~7.8 MB); `draw-ocean` (`ocean.gc:457-467`) writes `*ocean-verts*` into it; the
   mips2c store loop (`ocean_vu0.cpp:501-560`) matches the captured pattern exactly.
   The watch band `[0x514000,0x51c000)` was calibrated to x86's `global-buf` base,
   but the arm64 heap lays `global-buf` ~135 KB lower, so legitimate ocean writes
   trip it. **No stomp of the logo.** (A separate `<0x80000` hit is a benign
   pre-existing sparticle near-null no-op store — also not the garble.)

2. **The real garble is a SELF-INFLICTED arm64 merc bone-repair over-restore.**
   The J&D smash uses merc-skinned models `logo-english-lod0` (letters),
   `logo-volumes-english-lod0` (rays), `logo-black-lod0` (the breaking black cover
   / smash shards). Many of their bones are **legitimately degenerate (zero-scale)**
   at smash time: the `tmat` 3x3 is collapsed, only translation set.
   `bones-mtx-calc` (`bones.gc` `new-bones-mtx-calc-asm`; mips2c `bones.cpp:119`
   `c->vdiv`) builds the normal matrix as the inverse-transpose scaled by `1/det`;
   for `det==0` the mips2c `vdiv` (`mips2c_private.h:1074`) does a plain IEEE
   `1.0/0 = +inf` (no PS2 VU0 divide-by-zero clamp), so the **whole `nmat` becomes
   NaN while the `tmat` stays finite & correct**.

   This NaN `nmat` happens **identically on our-x86 and the device** (same shared
   mips2c `vdiv`, same anim data) — proven by an all-merc-model per-bone census:
   every non-finite element is in the `nmat` (`kbad=16, region=nmat`), **zero
   `tmat` corruption**, same models/bones/proportions on both. x86 renders fine
   because it has **no** bone-repair: the degenerate bone's geometry is collapsed
   (invisible) and the bad normals are harmless. On arm64 the bone-repair in
   `Merc2.cpp::handle_pc_model` (added for Gd3-jak/Gcine-pose to stop Adreno
   faulting on NaN bones) restored the **whole bone (tmat+nmat)** from a last-good
   snapshot for **any** non-finite element — overwriting the correct collapsed
   `tmat` with a stale/identity one. The degenerate shards/rays then popped into
   view as torn black scrambled geometry = the owner's garbled logo.

## The fix

**`game/graphics/opengl_renderer/foreground/Merc2.cpp`** (arm64-only, inside the
existing `#ifdef __aarch64__` bone-repair): make the repair surgical. Per bone,
test the `tmat` (floats 0-15) and `nmat` (floats 16-27) separately:

- `tmat` non-finite → genuine position corruption (Gd3-jak / Gcine-pose case):
  restore the whole bone from last-good (**unchanged behavior**, preserves those
  fixes).
- `tmat` finite, `nmat` non-finite → degenerate bone: **keep the finite, correct
  `tmat`; reset only the `nmat` to identity** so Adreno never sees a NaN. The
  collapsed bone stays collapsed/invisible → the arm64 render matches x86 exactly.

x86 is unaffected (the whole block compiles out on desktop).

**`game/mips2c/mips2c_table_jak1_arm64.cpp`**: the obsolete Gnd-phase `GND-OOB`
write-watch is **disarmed** — `gnd_oob_report` is now a no-op and `g_gnd_oob_armed`
is `false` — because the Glogo-garble investigation proved every address it flagged
is benign (ocean in-bounds + sparticle no-op). This is the single choke point all
watch paths call; disarming it takes the device GND-OOB-WRITE telemetry to 0 and is
behaviorally inert (the watch was pure logging; the ocean/sparticle stores still
happen benignly). No hot-path store/DMA logic was touched.

No `goal_src` / DGO / CGO change — TIT.DGO and the CGOs are unchanged.

## Proof (controlled A/B + final build)

- **A/B on one binary** (gate file `glogo_oldrepair`): OLD whole-bone repair =
  torn BLACK SCRAMBLED SHARD polygons around the logo (`abOLD-t22s/t23s.png`,
  reproduces the owner's garble); NEW fix = clean gold logo over the title
  (`abNEW-t22s/t23s.png`). Same boot, same beats, only the repair gate differs.
- **Final clean build** (libgk_sha `5c26a24dfd2b8924`, so_mtime
  2026-06-23T08:52:27, `deploy_verify.sh eae4df44` PASS):
  - device `grep -ac "GND-OOB-WRITE" final-run.log` = **0** (was ~400).
  - smash renders clean (`final-t01s_smash.png`..`final-t04s_smash.png`) matching
    `gold/pristine-frames/intro-logo-reveal-f001110.png`.
  - no crash (sig 11/6/4 = 0); village flythrough renders after (~589k tris).
  - x86 smoke reaches `link finish: logo`.

## Honest residual (out of scope, NOT a regression)

A brief, transient red Daxter-entrance blob appears for ~1 frame during the earlier
NAUGHTY DOG beat. It is **identical with and without this fix** (A/B `abNEW-t13s` ==
`abOLD-t13s`) — pre-existing, not a bone-NaN case (no `tmat` corruption), not the
J&D smash garble the owner reported, and **not introduced by this change**.
Flagged for a possible future phase; it does not block the logo-smash fix.

## Temp instrumentation — REMOVED

All temporary diagnostics added during this phase have been **removed/deleted**
(verified `grep` clean: no `GLOGO`/`glogo`/`s_n_low`/`s_n_band`/cap-split tokens
remain in `game/` or `common/`):

- The `GLOGOBONE` cross-platform per-bone NaN census (Merc2.cpp) — removed; the
  final x86 smoke and device runs log zero `GLOGOBONE` lines.
- The A/B repair gate (`s_oldrepair` / `glogo_oldrepair` file lookup) — removed;
  the device-side marker file was deleted after the A/B run.
- The split-cap diagnostic in `gnd_oob_report` — removed (the function is now a
  documented no-op).
- The temporary `#include <android/log.h>` in Merc2.cpp — removed.
- The prior turn's untested WIP (the alternate dma.h/mips2c_private.h band edits and
  the `strstr(name,"logo")` whole-set Merc2 hack) was reverted to clean HEAD before
  this work; its diff is preserved at `.autoport/reports/Glogo-garble/prior-turn-wip.diff`
  for reference only.

`.autoport/gold` is left byte-pristine (untouched). The device runs the fresh HEAD
libgk (deploy_verify PASS).

## Files changed

- `game/graphics/opengl_renderer/foreground/Merc2.cpp` — surgical tmat/nmat bone
  repair (the garble fix), arm64-only.
- `game/mips2c/mips2c_table_jak1_arm64.cpp` — disarm the obsolete false-positive
  GND-OOB write-watch (telemetry 400 -> 0).
