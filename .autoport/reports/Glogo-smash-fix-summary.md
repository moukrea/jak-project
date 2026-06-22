# Glogo-smash — fix summary

**Owner ground truth (2026-06-22):** "the Jak&Daxter logo-smash (breaking the black
screen) is now BROKEN — a regression from Gconsolidate-deploy swapping in a fresh
TIT.DGO built from current source."

**Verdict: the logo smash is NOT broken on the current consolidated HEAD build — it
MATCHES the original.** Proven by the phase's mandated method (x86-first deterministic
smash-SEQUENCE state dumps, NEVER pixels) plus objective device render-tris on the
owner's exact deployed artifact. The reported break was a STALE pre-consolidate
deployment artifact (same class as Ghalo's "device ran the wrong TIT.DGO" and
Gwater-lod's "stale pre-consolidate artifact, not a live translation gap"). No 1-to-1
source regression exists; no source revert was warranted.

## Method (x86-first, no pixels)

Reused the GFXRAY rig from the (reverted) Gfix-title-rays phase, recovered from git
and extended to dump the full smash SEQUENCE state. Temporary `(format ...)` lines in
the `logo` startup `:post` (+ a startup-entry marker) emit per frame:

- `GLOGO st=<state> an=<spool anim> fn=<anim frame-num> blk=<logo-black alive>
  vol=<logo-volumes alive> bga=<bg-a>`
- `GLOGM mjtx,mjty=<main-joint trans> mjsx=<main-joint scale> asp=<aspect enum>`

Captured three ways:
1. **our-x86** (HEAD, `build-x86/game/gk`) — `(format 0 ...)` -> stdout.
2. **original-x86** (`/home/emeric/code/jak-original-v033` @ c4bc4d3ff, its own
   toolchain) — `(format #t ...)` -> goalc listener; v033 source temp-instrumented
   then `git checkout`-restored to byte-pristine.
3. **device** (eae4df44, arm64) — instrumented arm64 TIT.DGO on the consolidated
   HEAD CGOs; `(format 0 ...)` -> logcat.

Plus an instrumentation-free objective render check on the owner's EXACT deployed
artifact (consolidated TIT.DGO sha d67028b8 restored via restore_knowngood): the
A35-RENDER tris curve through the smash window.

## What the dumps show (logo.txt has the full data)

The smash sequence is byte-equivalent across all three targets:

- `startup-entry next-anim="logo-intro"` on all three.
- anim progression `logo-intro` (Naughty Dog beat, black cover alive) -> REVEAL
  (logo-black + logo-volumes deactivate, blk/vol 1->0 at logo-intro fn~65) ->
  `logo-intro-2` (the JAK&DAXTER SMASH, fn advances) -> `logo-loop` (title loop).
- identical bg-a fade curve (1.0 -> 0.0), identical fn advance, identical reveal
  frame, identical main-joint placement (2048.0, -1228.8, scale 0.87).
- the device reaches `st=idle an="logo-loop"` — the smash COMPLETES into the title
  loop — and never crashes (0x sig=4/6/11 across the run).

Device render proof (owner's artifact d67028b8, no instrumentation): tris=8161 ->
15703 while the logo renders, then 577522 for the village flythrough. The black
screen DOES break and the logo geometry DRAWS. Not black, not frozen, not crashing.

## Why there is no source regression

`title-obs.gc` is **byte-identical** between the working pre-consolidate Ghalo
TIT.DGO (built at 39222b554, the device's prior known-good) and HEAD. The only
title-obs commits in between were `Gfix-title-rays` (0d9db1fd5) and its **full
revert** (97b502f67), which net to zero. So there is no source delta that could have
regressed the smash between the owner's "worked" and "broke" observations. Both
TIT.DGOs compile the same title-obs logic; the smash plays the same.

The owner's observation is best explained by a transient device state at observation
time (a prior phase's experimental TIT.DGO left on the device), since overwritten by
`restore_knowngood_device.sh` -> the consolidated set. The current device runs the
consolidated HEAD set whose smash matches the original.

## Regressing-edit analysis: the Gtitle-pixelmatch 16x9 main-joint (named + cleared)

The phase named the 16x9 main-joint hardcode as prime suspect. Pristine branches the
logo main-joint on the aspect ENUM (`'aspect16x9` -> scale 0.87 / offset 2048,-1228.8;
else centered 1.0). Gtitle-pixelmatch hardcoded the 16x9 branch because the Android
boot aspect enum is `aspect4x3` (the pc-get-window-size override is stubbed), which
would otherwise mis-center the logo on the widescreen device.

Cleared as the smash break:
- Both pristine and our build force-set the main-joint EVERY frame; only the values
  differ. The smash anim is skeleton/spool-driven, not main-joint-driven — fn
  advances identically with the hardcode in place.
- The numeric main-joint is IDENTICAL on original-x86 (which runs aspect16x9 -> the
  pristine branch yields 2048,-1228.8,0.87) and on our build. So for the smash the
  placement matches the original 1-to-1.
- It is a latent x86-only 1-to-1 imperfection (an x86 window that is not 16:9 would
  diverge), but it does NOT affect the device (correct, pixel-matched) or the smash.
  A bare revert would REGRESS the proven Gtitle-pixelmatch device placement; the
  methodology-correct alternative (drive the Android aspect enum from the real
  window) has Gmenu blast radius and is out of scope here. The hardcode also predates
  this phase's supervisor anchor.

## Changes / state

- **No goal_src changes.** Temporary instrumentation was added to our title-obs.gc
  (startup `:post` dump + startup-entry marker) and to v033's title-obs.gc, and has
  been **completely removed**: `grep GLOGO/GLOGM goal_src` returns nothing, our
  `title-obs.gc` is byte-identical to committed HEAD (`git status` clean), and v033
  is restored to pristine (`git status` clean). The four recovered temporary
  `gfxray_*.sh` capture scripts were also deleted (no leftover dump tooling).
- `.autoport/gold` left byte-pristine (git status clean; never modified).
- out/jak1/iso rebuilt clean to x86 after the arm64 device build (obj cache wiped to
  avoid x86/arm64 .o mixing).
- Device left on the consolidated HEAD known-good set (TIT.DGO d67028b8); known-good
  backup unchanged (already the correct, smash-rendering consolidated set).

## Gates

- x86 smoke: `link finish: logo` (validator re-checks).
- device: boots crash-free to the title; logo smash renders + completes into the
  title loop; `deploy_verify.sh eae4df44` PASS (device runs fresh HEAD libgk).
- evidence: `.autoport/reports/Glogo-smash/logo.txt` (3 dumps + render tris +
  BEFORE/AFTER + named/cleared regressing edit), raw captures `orig-x86.txt`,
  `ours-x86.txt`, `device-before.txt`, `device-consolidated-clean.log`.
