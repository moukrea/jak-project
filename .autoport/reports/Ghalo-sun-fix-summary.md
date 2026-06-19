# Ghalo-sun — fix-summary: the title sun-halo "re-arm bug", diagnosed by deterministic state dumps

## TL;DR

The hypothesis for this phase was that the title-screen sun **glow/light STATE is not reset /
re-armed across the day/night cycle** ("big glow at sun-UP, fades at sun-DOWN, does NOT return
at the next sunrise"). I verified this the way the owner mandated — with **deterministic
sun-cycle STATE dumps, x86-FIRST, against the pristine v0.3.3 original** — instead of the
prior timing-flawed screenshot halo metric. The data **FALSIFIES the re-arm-bug hypothesis**:
the title sun glow **re-arms correctly on arm64 on every sunrise** and **matches the original**.
No sun-state field is stale or un-re-armed. The prior screenshot metric (which read 0.002 at a
sun-DOWN instant) was indeed measuring a timing artifact, not a real un-re-armed state.

## What the sun glow actually is (so the dump targets the right state)

- The title sun glow is the **`group-sun`** additive billboard (`weather-part.gc:482`,
  parts 1950/1951/1952), spawned/killed by **`time-of-day-update`** (`time-of-day.gc:44-49`):
  spawn when `6.25 <= time-of-day < 18.75` AND `sun-fade != 0` AND `sun-count == 0`; killed
  (sun-count reset to 0) otherwise.
- Its on-screen SIZE is set every render frame by `sparticle-track-sun`
  (`weather-part.gc:469`) as `glow-scale = 128 * (-> *time-of-day-context* sun-fade)`.
- Its COLOUR comes from `current-sun sun-color` (`weather-part.gc:472-478`).
- The launch-control (`(-> *time-of-day-proc* 0 sun)`, a `sparticle-launch-control`) re-arms
  via the per-emitter `particles-active` flag: `kill-and-free-particles`
  (`sparticle-launcher.gc:635-647`) CLEARS it; the next `spawn` (`:679-787`) re-sets it and
  re-launches. There is **no persistent latch** in source that could block a second spawn.

## The state I dumped (4 logcat/stdout lines per sample, across 6 day/night cycles)

- `tod`, `day`         — sun phase + day counter
- `sun-count` (c)      — the spawn GATE (1=spawned, 0=killed)
- `sun-fade` (sf)      — the GLOW SIZE driver (scale = 128*sf)
- `current-interp` (cint) — the level-mood blend that produces sf
- `PRT f0/f1/f2`       — the sun launch-control flags (1=launcher-active, **3=+particles-active**
                          => the particle is actually LAUNCHED/re-armed), `lc`=local-clock
- `scol`, `ecol`       — current-sun sun-color / env-color (the LIGHT state)
- `L0/L1`              — the two active level slots: name/status/`info sun-fade`

Captured on: OUR x86 (HEAD, natural attract, temporary `format 0` dump), the pristine
ORIGINAL x86 (v0.3.3 c4bc4d3ff, read non-invasively over the goalc listener — repo stayed
git-clean), and the DEVICE (arm64, fresh instrumented TIT.DGO on the f1c boot set, dumped to
logcat). Full raw data: `.autoport/reports/Ghalo-sun/{our-x86-natural-cycle,orig-x86-cycle,
device-cycle-comprehensive}.txt`.

## The numbers (per-day DAYTIME sun-fade; re-arm flags)

```
            day0          day1          day2          day3   day4   day5   day6
our-x86 sf  0.5065-1.0    0.6435-1.0    0.5000        0.5    0.5    0.5-1.0 0.92-1.0   <- RE-BLOOMS
device  sf  0.5065-1.0    1.0000        0.5-0.7425    0.5    0.5    0.5    (cap@day5)
original    sun-count + PRT flags re-arm every sunrise; sf tracks the same camera blend
```

- **sun-count** re-arms `0->1` at EVERY sunrise and `1->0` at EVERY sunset on x86, device AND
  original. No exception across all observed days.
- **PRT particles-active**: device = `3` on all 131 daytime samples, `1` on all 75 night
  samples — the particle re-launches on **every** sunrise. (This kills the "the counter
  re-arms but the particle never re-launches on arm64" hypothesis outright.)
- **sun-color** `scol` = `255,225,96` constant at midday on all three, dipping to ~`255,140,15`
  at sunset and recovering at sunrise — identical.
- **sun-fade == current-interp EXACTLY** on every build. The glow SIZE is the mood blend
  `interp(L0='title' sun-fade 0.0 , L1='village1' sun-fade 1.0) = cint`, i.e. it is driven by
  the **attract CAMERA** (level distances), NOT by sun elevation. It oscillates 0.5<->1.0 and
  periodically floors at 0.5 (camera at the equidistant vista) then **RE-BLOOMS** (x86 captured
  this at days 5-6). The "big glow doesn't come back at sunrise" perception is this: the big
  glow (sf=1.0) returns when the looping flythrough re-enters the bloom, which does not always
  coincide with a sunrise — and this is **identical upstream behaviour on the original**.

## Mechanism / root-cause finding

There is **no stale/un-re-armed sun-state field**. Every gate that controls "the sun comes
back each day" re-arms correctly on arm64: the spawn counter, the launch-control
`particles-active` flag, and the sun colour. The single arm64-vs-x86 difference observed —
the slow Android loader holding the camera/level interp in the bloom (`cint=1.0`) about one
day-cycle longer at boot, so the double-size glow lingers a little before settling to the
steady 0.5 — is a **camera/level-distance timing artifact** (the same Gndlogo slow-loader
class), NOT a reset/re-arm failure, and it is confounded by capture density. Source proof: the
ENTIRE sun/light/sky/mood/sparticle code path is **byte-identical** between our HEAD and the
original, so our-x86 == original-x86 by construction.

Independent cross-check: the standing graphics detector on the clean current device reports
`halo_present=FALSE` on every beat (`halo_excess_frac` 0.0005-0.0027 vs the 0.02 gate) — no
excess sun-halo blob. This agrees with the state dump.

## The "fix"

No sun-state code change is warranted — the deterministic dumps prove the title sun re-arms
correctly and matches the original, so adding a suppression/clamp would only make our build
DIVERGE from the original (breaking x86-MATCHES-ORIGINAL) for a non-existent bug. The existing
title-obs.gc sun handling (the Gndlogo ndi sun-fade suppression + the Ghalo SCE re-gate,
already on HEAD) is **confirmed correct** by this proper methodology. The deliverable of this
phase is therefore the **trustworthy deterministic state-dump verification that REPLACES the
prior timing-flawed screenshot halo metric**, plus the reusable harness
`.autoport/ghalo_sun_x86_dump.sh`, and the rigorous falsification recorded in the two
state-dump files.

## Cleanup / hygiene

- All temporary `ghalo-sun-dump` instrumentation has been **REMOVED** from
  `goal_src/jak1/levels/title/title-obs.gc` (the defun + both attract :trans call-sites);
  `git diff` of title-obs.gc vs HEAD is empty (no leftover dump code).
- The pristine original golden (`jak-original-v033`, c4bc4d3ff) was **never source-edited** —
  it was read only over the listener — and its `git status --porcelain` is empty.
- x86 `out/jak1/iso` was rebuilt clean (no `GHALO` strings in TIT.DGO); x86 still reaches
  `link finish: logo`.
- Device restored to the known-good clean set; deploy_verify PASS; fresh device run crash-free
  (0 sig 4/6/11), reaches gameplay.
