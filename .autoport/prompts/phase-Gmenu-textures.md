# Phase Gmenu-textures — main-menu TEXTURES still bunched toward center — measure EVERY menu draw (x86-first, no pixels)

## The defect (owner, 2026-06-22, CURRENT consolidated build)
"main menu still has ALL the textures garbled towards center." The prior `Gmenu-placement` PASS was
a FALSE GREEN: it measured the option panels `PART0/PART1/PART2` (which DO spread: 0/-220/+195 @
2400x1080) + the tint backdrop, and called it fixed — but those are NOT the TEXTURE assets the owner
sees bunched. The actual menu texture layer is still clustering toward screen-center on the device.

## CRITICAL — no pixels, and do NOT repeat the wrong-element mistake
The menu is a transparent overlay over a moving island, so pixel diffs are invalid
([[proxy-dumps-false-green]]). The lesson from the false green: I measured a SUBSET (PART panels)
that happened to be fine while the actual defect lived in a DIFFERENT element. This time **enumerate
EVERY menu 2D draw** — every sprite / `draw-string` / icon / texture-quad the progress/main menu
submits (not just PART/tint) — and dump each one's computed on-screen X/Y (+scale). Find the layer
that clusters toward center on device vs the original.

## Methodology — x86-FIRST per-element position dump of the WHOLE menu draw list
1. Open the main menu and enumerate ALL its 2D draws (walk the menu's draw/`add-icon`/`draw-string`/
   sprite-submit path in `progress.gc` + the 2D/HUD draw list). For EACH element dump its final
   on-screen X/Y (+scale) at **2400x1080**, on **original-x86 (.autoport/gold)**, **our-x86 (HEAD)**,
   **device**.
2. **our-x86 vs original-x86 FIRST** (1-to-1; if our-x86 diverges, a source hack did it → revert to
   pristine). **device vs original**: find the element(s) whose X/Y cluster toward center (≈ 0 / the
   midpoint) on device while the original spreads them — THAT is the owner's bunched texture layer.
3. Localize the cause (an arm64 2D-HUD projection / `adjust-ratios` / #f-guard misfire for THAT
   element class, or a wrong aspect fed to it) and fix in the translation layer; if a source hack
   diverged it, revert to pristine. End state: every menu element's device X/Y matches the intended
   (original) spread.

## Validator (`phase-Gmenu-textures.sh`) PASS requires
1. `.autoport/reports/Gmenu-textures/menu.txt`: the FULL menu draw list (every element, not just
   PART) with each element's X/Y for original-x86, our-x86, device @2400x1080 — explicitly listing
   the element(s) that were bunched-to-center BEFORE and now match the original spread AFTER. With
   `RESULT: ALL MENU ELEMENTS PLACED CORRECTLY (device, full draw list matches original)`. Must name
   the previously-missed bunched element class (the one Gmenu-placement's PART check did not cover).
2. our-x86 == original-x86; any `goal_src/**` edit must be a documented pristine revert.
3. Fix-summary `.autoport/reports/Gmenu-textures-fix-summary.md` ≥60 lines; temp instrumentation
   removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free to the menu; `deploy_verify.sh eae4df44`
   PASS; if a TIT.DGO/CGO data fix is needed, the consolidated known-good backup is refreshed.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
