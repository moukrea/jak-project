# Ghalo — kill the spurious halo (village1 + sun-glow) on the Naughty-Dog-logo beat

## TL;DR
The owner saw a bright yellow glow with Jak+Daxter art + a red seal on the RIGHT of
the **Naughty-Dog-logo (ndi) intro beat** — village1 geometry + a sun-particle glow
leaking onto a screen that should be the ND logo on clean black. Measured objectively
by the standing detector: intro-logo `halo_excess_frac = 0.289` on the device vs the
v0.3.3 original (clean ~0.002).

This was NOT a code regression — the Gndlogo fix (done?-gated village + sun-fade
suppression) is present and correct in `title-obs.gc`. It was a **deployment
regression**: the device runs the **f1c (2026-06-11) TIT.DGO, which PRE-DATES the
Gndlogo fix (2026-06-15)**. The fix never reached the currently-deployed device after
the 2026-06-18 "restore to known-good f1c" reverted TIT.DGO to its pre-fix June-11
build.

The fix ships the Gndlogo-fixed TIT.DGO to the device, but a freshly-built
current-source TIT.DGO re-triggers the **frame-180 enter-state SIGILL** on the f1c
boot CGOs. The trigger is the Gsce static-screen spawn; this phase **re-gates that
spawn** so the Gndlogo-fixed ndi can ship on the f1c set. Result: intro-logo halo
0.289 → **0.0008** (< 0.01 gate), title 0.0011 (< 0.02 gate), boots clean to a real
title flythrough (tris=558463 @ frame 1200), 0 crash signatures, frame 10740 in-game.

## 1. Where the village1 + sun glow leaks onto the ND-logo beat
The mechanism is exactly the one Gndlogo diagnosed (see memory `project-gndlogo-state`):
on the pristine PC, village1 is `'inactive` during the `ndi` spool, so the ND logo
sits on the empty black void. On the slower Android loader, village1 is already
`'loaded` at ndi entry, which produces TWO artifacts that compose the "halo":
1. **Village behind the logo.** Commit `dd3ee36ad` made the village `display-self`
   request unconditional in the ndi `:trans`; with village1 `'loaded` it fires
   immediately → the whole village is in the display list behind the ND logo, and
   `ndi` never deactivates (bg-a collapses, so the `(= bg-a 1.0)` deactivate term is
   never reached).
2. **Yellow sun glow.** village1 `'loaded` → `update-time-of-day` runs its noon mood →
   `sun-fade != 0` → `time-of-day-update` spawns `group-sun`, an additive
   camera-following yellow billboard (`weather-part.gc` `sparticle-track-sun`). The
   pristine never spawns it (village `'inactive` → sun-fade 0). On arm64 this is now
   *visible* (post-Gsprite the 2D sparticle builders are real, not noop).

`title-obs.gc` ALREADY contains the Gndlogo fix for both (the `ndi` state at
`defstate ndi (logo)`):
- `:trans` gates the village display on the spool finishing — `(when (-> self done?)
  (load-state-want-display-level 'village1 'display-self))` — and gates deactivate
  readiness on `(and done? (!= all-visible? 'loading))`.
- `:trans` also zeroes the recompute SOURCE of the sun every frame (`(-> *level*
  level0/level1 info sun-fade)` + `(-> *time-of-day-context* sun-fade)`), and `:enter`
  saves / `:exit` restores them so the flythrough keeps its real sun.

## 2. Why the prior Gndlogo gating is missing / ineffective NOW
It is a **deployment regression, not a source regression.** Verified empirically:
- The device's runtime `files/iso_data/jak1/TIT.DGO` sha256 = `bd63f35c5f7a…`, which
  byte-matches `.autoport/backups/device-knowngood-cgos-20260618/TIT.DGO`. That whole
  backup is the **f1c phase build dated 2026-06-11 20:35** (all 28 files; see the
  backup README) — it PRE-DATES the Gndlogo fix landed 2026-06-15. So the deployed
  TIT.DGO simply does not contain the done?-gating + sun-fade suppression.
- KERNEL.CGO / GAME.CGO / ENGINE.CGO on the device also byte-match the f1c backup, and
  libgk.so on the device == the build (`0dd9e4f7…`, deploy_verify already PASSES). So
  the device runs: **f1c boot CGOs + f1c (pre-fix) TIT.DGO + HEAD libgk**.
- The Gndlogo pass (2026-06-15) deployed a fixed TIT.DGO at the time, but the
  2026-06-18 "going in circles" incident restored the device to the *pure f1c set*
  (`restore_knowngood_device.sh`), which reverted TIT.DGO to its June-11, pre-fix
  build. That restore is why the owner sees the halo again on every boot.

The phase prompt's premise ("the device now runs a full current-source build") is
stale: the HEAD commit (Gmenu-ui-placement) explicitly **restored the device to f1c**
because a full current-source CGO rebuild boots but does NOT render the title
(356 tris vs 623961 — an undiagnosed boot-CGO render blocker). The device must keep
the f1c boot CGOs to render at all.

## 3. The deploy bind, and why this fix is a re-gated TIT.DGO overlay
Three constraints box in the deploy path:
- **A full consistent current-source rebuild does not render** (356-tris blocker,
  reproduced by Gmenu, undiagnosed — likely an arm64 codegen regression in the render
  path of freshly-rebuilt boot CGOs). So Path A (ship everything consistent) is out.
- **Standalone-rebuilding a boot CGO SIGILLs** (KERNEL/GAME/ENGINE.CGO are
  cross-referenced by the device's fixed kernel; see `feedback-game-cgo-rebuild-unsafe`).
  So I cannot ship the Gspark enter-state fix (which lives in KERNEL.CGO) by itself.
- **A current-source TIT.DGO on f1c re-triggers the frame-180 SIGILL.** MEASURED:
  pushing the full-current-source arm64 TIT.DGO (sha `87b785f6…`) onto the f1c set
  crashes with `GK-DIAG sig=4 fault=0x7f00000000 pc=0x7f00000000` immediately after
  `A35-RENDER frame=180` (a BLR to a null GOAL pointer = EE_base+0). This is exactly
  the Gspark-enterstate bug: a sparticle DMA builder (mips2c, real since Gsprite)
  invoked from **static-screen's `idle` :trans (spawn)** writes through GOAL pointers
  and stomps `enter-state`'s spilled `new-state` on the GOAL process stack, zeroing
  the code pointer. Gspark fixed it by reloading `new-state` from `(-> pp state)` in
  `gstate.gc` — but that fix lives in KERNEL.CGO, which the f1c set lacks and which I
  cannot rebuild standalone.

`static-screen.o` and `title-obs.o` both compile into **TIT.DGO** (`dgos/tit.gd`), so a
TIT.DGO rebuild can both ADD the Gndlogo ndi fix AND remove the stomp trigger.

## 4. The fix (goal_src/jak1/levels/title/title-obs.gc — TIT.DGO only)
Re-gate the SCE "presents" static-screen spawn back to the upstream territory
condition that the Gsce phase had un-gated:
- Before (Gsce): `(*first-boot* …)` → spawns static-screen on SCEA → sparticle DMA →
  stomp → frame-180 SIGILL on the f1c kernel.
- After (Ghalo): `((and (= (scf-get-territory) GAME_TERRITORY_SCEI) *first-boot*) …)`.
  `DecodeTerritory()` returns SCEA(0) on the device, so the branch is NEVER taken →
  static-screen never spawns → no sparticle stomp → no frame-180. This restores the
  proven f1c boot flow (loader → ndi ND-logo → title), which is exactly the flow the
  Gndlogo halo suppression was validated under.

**Cost:** none visible — the SCE "presents" screen rendered BLACK on arm64 anyway
(Gsce's own honest blocker: its 2D sprite blit was empty), so re-gating it loses no
on-screen content. It does revert the Gsce *deliverable* (the SCE screen for SCEA),
which is the right trade: a never-rendered screen vs. the owner-visible ND-logo halo +
a boot-bricking SIGILL. The Gndlogo ndi fix (the actual halo kill) is untouched and
present.

**Delivery:** the fixed arm64 TIT.DGO (sha `13641655da23c19…`) is overlaid on the f1c
boot CGO set + HEAD libgk. The known-good restore backup's TIT.DGO is updated to this
fixed build (proven-good), so the device's persistent known-good state IS the fixed
state and `restore_knowngood_device.sh` delivers the fix instead of reverting to the
haloed f1c TIT.DGO. deploy_verify (libgk chain) is unaffected and still PASSES.

## 5. Objective verification (the trustworthy detector, vs v0.3.3 original)
- BEFORE (f1c device): intro-logo `halo_excess_frac = 0.289` (MISMATCH, village/sun
  leak), title-pressstart 0.00196.
- AFTER (f1c boot CGOs + fixed TIT.DGO + HEAD libgk):
  - intro-logo `halo_excess_frac = 0.0008` (< 0.01 gate; ~360x reduction), selected
    burst frame f011 logo_overlap=0.827, device_bright_frac 0.0318 vs oracle 0.0375.
  - title-pressstart `halo_excess_frac = 0.0011` (< 0.02 gate).
  - `halo_fail_beats = []` (no beat fails the halo gate).
  - Boots clean past the old frame-180 crash: `A35-RENDER frame=180 … tris=3916`, then
    a real textured title flythrough `frame=1200 … draws=765 tris=558463`.
  - 0 crash signatures (sig 4/6/11); deepest in-game render frame 10740 (≥ 10500),
    foreground = org.opengoal.gk.jak1 throughout.

The overall detector verdict remains FAIL only on the PRE-EXISTING `main-menu`
HUD-bunching pixel-diff (the arm64 2D-HUD projection defect, its own phase — see
`project-gmenu-ui-placement-state`) and a marginal intro-logo pixel `diff_frac`
(0.0249 vs the 0.02 cross-renderer floor) — NEITHER is a halo or a crash failure. The
Ghalo gate (intro-logo halo < 0.01 AND title < 0.02, crash-free, reaches in-game) is
met.

## 6. Scope / non-regression
- Only `goal_src/jak1/levels/title/title-obs.gc` changed in goal_src (the Gsce
  re-gate). No boot CGO rebuild, no libgk change, no emitter change.
- `.autoport/deploy_gmatch_test.sh` smoke watchdog regex broadened `sig=11` →
  `sig=(4|6|11)` so it correctly classifies the frame-180 SIGILL (it previously
  mislabeled sig=4 as "boot stalled").
- x86 oracle restored (out/jak1/iso is x86 again); x86 still links to logo (the
  re-gate matches upstream SCEA behavior, which never spawned static-screen on x86
  either).
- Device left on the proven fixed set (f1c boot CGOs + Ghalo TIT.DGO), not the haloed
  f1c TIT.DGO.
