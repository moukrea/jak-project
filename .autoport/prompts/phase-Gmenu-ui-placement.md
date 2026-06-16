# Phase Gmenu-ui-placement — the menu UI elements are bunched in the CENTER instead of placed correctly. DIAGNOSE OPENLY, then fix. DATA/owner-gated, NO screenshot grind.

## Symptom (owner's words — do NOT presume the cause)
On the Android device the main menu (the progress-screen reached by START at the title: NEW GAME / LOAD GAME / OPTIONS / SECRETS / QUIT GAME / BACK + a wooden ornamental frame + an eco-orb) renders with **all the UI elements bunched toward the CENTER instead of placed where they belong** — the frame is squeezed in, the backdrop bleeds through the wide sides, the eco-orb is mis-placed. The owner explicitly did NOT call this an "aspect-ratio" bug; a prior over-anchored "force the aspect enum to 16:9" framing is WRONG to assume. The owner's hypotheses (to test, not assume): incomplete support for various aspect ratios, OR the device's **ultrawide ~20:9 / 21:9** panel (2400x1080) simply isn't supported (the game knows 4:3 and 16:9, not ultrawide), OR something else in the 2D UI placement.

## Mandate — DIAGNOSE FIRST, openly
1. **Read the menu UI placement path** and figure out, on a 2400x1080 (20:9) window, WHY the elements center: `engine/ui/progress/progress.gc::adjust-ratios` and how it positions elements; how the 2D UI virtual coordinates (PS2 512x416-style) are scaled/offset to the actual window; how the aspect-ratio is detected/selected (`scf-get-aspect`/`*setting-control*`/settings) and which branch the device takes; whether any path supports an aspect WIDER than 16:9.
2. **Compare to the original/desktop at the SAME 20:9 window.** Run our x86 (`build-x86/game/gk`) — and if useful the pristine `/home/emeric/code/jak-original-v033` (read-only) — at **2400x1080** and reach the menu. Does the ORIGINAL also bunch the UI center at 20:9, or does it place it correctly? This is decisive: if the original ALSO centers at 20:9, the game genuinely lacks ultrawide UI support (the fix is to ADD ultrawide handling); if the original places it correctly at 20:9 but our build doesn't, then our build broke something (aspect detection / placement math) — fix that.
3. **Pin the real cause** from 1+2 (e.g.: device picks the 4:3 branch when it should pick 16:9; OR the game has no >16:9 layout so 16:9 content sits centered on the 20:9 panel; OR the 2D scale/offset math mis-maps to 20:9). State it plainly with evidence.
4. **Fix it so the menu UI is placed correctly for the device's actual panel** — whatever the diagnosis requires (correct aspect selection, AND/OR proper ultrawide/20:9 UI layout handling, AND/OR fixed placement math). Engine/boot-CGO change → FULL consistent rebuild (no standalone CGO push) + redeploy.

## HARD ANTI-GRIND (mandatory)
NO screenrecording, NO `.mp4`s, NO frame-pooling, NO animated screenshot phase-matching (it filled the disk + wasted tokens). Verification = the diagnosis evidence (code + a couple of static x86/device screencaps to compare placement) + the OWNER's eye on the deployed menu. A single static `adb exec-out screencap` is fine; large video/frame intermediates fail the validator.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Oracle repo + `.autoport/gold/` read-only. x86/`#else` path byte-identical. Don't break the title (it looks good now) or the intro.

## DEPLOY-LANDING DISCIPLINE (mandatory — fixes have silently failed to land)
After your fix: do a **CLEAN/forced rebuild** of libgk.so (don't trust incremental dep-tracking to recompile after a header change) → reassemble the APK → reinstall on the device. Then run `bash .autoport/lib/deploy_verify.sh eae4df44` and confirm it PASSES (the device provably runs the fresh HEAD libgk.so: build==APK==device, built after the change). The validator runs this as a hard gate — a stale/un-landed build CANNOT pass. A fix is not done until deploy_verify passes AND the owner sees it on that build. See [[deploy-landing-guard]].

## Validator (`phase-Gmenu-ui-placement.sh`)
PASS requires: a `Gmenu-ui-placement-fix-summary.md` that documents the OPEN diagnosis (which code path centers the UI, the x86@20:9 comparison verdict, the pinned cause) + the fix; a real UI/placement/aspect code change (not a no-op); no large `.mp4`/frame-pool intermediates + disk headroom; on device no sig=11, boot sustained (frame≥300, tris>0); x86 still `link finish: logo`; a single static `.autoport/reports/Gmenu-ui/menu-*.png` screencap for the owner's eye. The menu placement itself is OWNER-verified by eye on the deployed build.

## Max settings
`max_turns: 1200`, `max_retries: 3`.

## Strategic note
Do NOT assume aspect-enum. The decisive experiment is step 2 (does the ORIGINAL center the menu at 20:9 too?). If yes → add ultrawide support; if no → our build regressed the placement. Fix the real thing; the owner eye-confirms.
