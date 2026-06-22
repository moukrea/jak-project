# Phase Glogo-smash — the Jak&Daxter logo-smash (breaking the black screen) is now broken — find what regressed it (x86-first, no pixels)

## The defect (owner, 2026-06-22, CURRENT consolidated build)
"Jak and Daxter logo breaking in the black screen is now broken." At session start the logo DID
smash (with the now-irrelevant lingering rays); after `Gconsolidate-deploy` swapped the device's
f1c+Ghalo `TIT.DGO` for a FRESH `TIT.DGO` built from CURRENT source, the **smash itself broke**.
So this is a REGRESSION introduced this session — almost certainly a divergence between the current
`title-obs.gc` (carrying accumulated autoport edits: Gtitle-pixelmatch 16x9 logo main-joint, Ghalo
done?-gating + sun-fade, Gsce un-gating, the rays-hack revert) and the pristine original, now baked
into the fresh TIT.DGO. Less likely but possible: a libgk change (FFI xmm / particle) affecting the
logo-black smash anim.

## Methodology — x86-FIRST deterministic state dumps, NEVER pixels ([[porting-1to1-fix-in-translation-layers]])
The logo-smash is the `logo-black` process (the black cover) breaking/animating away to reveal the
`logo` + `logo-volumes`. Dump the **smash SEQUENCE state** — `logo-black`/`logo` process state,
state transitions, anim `frame-num`/joint-mod advance, and the smash trigger — across the title
intro, on **original-x86 (.autoport/gold)**, **our-x86 (HEAD)**, **device**.
1. **our-x86 vs original-x86 FIRST** — if our-x86's logo-smash sequence DIVERGES from the original
   (e.g. the smash state never fires, the logo-black doesn't animate away, a joint is frozen/NaN),
   the regression is in our `title-obs.gc` SOURCE. Bisect which autoport edit broke it (compare the
   logo/logo-black/main-joint defs vs the pristine upstream title-obs.gc; the Gtitle-pixelmatch 16x9
   forced logo main-joint is the prime suspect — forcing the main-joint can break the smash anim).
2. **Fix 1-to-1:** revert the breaking edit to the pristine original so the smash matches; if that
   edit's INTENT was a real platform need (e.g. widescreen logo placement), re-implement it in the
   translation layer (runtime window-size/aspect glue feeding the EXISTING logo code), NOT by forcing
   geometry in source. If instead our-x86 == original-x86 but the DEVICE smash diverges, it's an
   arm64/GLES translation defect — fix there.
3. Rebuild TIT.DGO (level DGO, safe) + (if the known-good set changes) refresh the consolidated
   backup so the device persistently shows the fixed smash.

## Validator (`phase-Glogo-smash.sh`) PASS requires
1. `.autoport/reports/Glogo-smash/logo.txt`: the logo-smash sequence state (logo-black/logo state +
   anim advance + smash trigger) for original-x86, our-x86, device — a calibrated BEFORE where the
   device (and/or our-x86) smash is broken vs the original, and an AFTER where the device smash
   sequence matches the original (logo-black animates away, logo revealed). With
   `RESULT: LOGO SMASH MATCHES ORIGINAL (device)`. Name the regressing edit.
2. If the fix touched `goal_src/**` it must be a REVERT toward the pristine original (documented;
   our-x86 ends == original-x86 for the logo sequence); a new divergence FAILS.
3. Fix-summary `.autoport/reports/Glogo-smash-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free to title; `deploy_verify.sh eae4df44` PASS;
   if the TIT.DGO/known-good set changed, the consolidated backup is refreshed consistently.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
