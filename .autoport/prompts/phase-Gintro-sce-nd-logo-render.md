# Phase Gintro — make the pre-title intro RENDER: SCE "presents" static screen + Naughty Dog/Daxter logo (chronological step 1)

## Ground truth (from the gold standard — do not re-derive)

The pristine boot sequence (`.autoport/gold/pristine-boot-sequence.log`, built from upstream `704972dd6`) is, all under master-mode `'game`:
**SCE static screen → ND logo (`ndi-intro` spool) → Jak&Daxter flythrough (`logo-intro`/`logo-intro-2`) → `logo-loop` attract → PRESS START.** Source chain (goal_src is byte-identical to pristine across our fork, so authoritative):
- `target-title` state — `goal_src/jak1/levels/title/title-obs.gc:523-603`: spawns the **SCE/SCEA static boot screen** via `static-screen-spawn` (title-obs.gc:553-563 — a **texture blit**, not text), then `(process-spawn logo "logo-1" ... 'ndi)` (**Naughty Dog logo**) and `(process-spawn logo ... 'logo)` (**Jak&Daxter title logo**).
- `logo` process — title-obs.gc:10-25/417-521: arg `'ndi` → `(go-virtual ndi)` plays **"ndi-intro"**; arg `'logo` → `(go-virtual startup)` plays "logo-intro"→"logo-intro-2"→loops "logo-loop". Slave actors: logo-slave×N, `*jchar-sg*` (Jak), `*sidekick-sg*` (Daxter), `*ndi-cam-sg*` / `*logo-cam-sg*` cameras.

## The bug (already localized by the gold-standard boot diff — DO NOT re-investigate whether states run)

On our **G1-stable Android build**, a boot-marker diff vs pristine shows the intro states **EXECUTE**: `static-screen` fires (1×), `ndi-intro` streams (30×), `logo-intro`/`logo-intro-2`/`logo-loop` all stream — same as pristine. **But the owner sees the SCE screen and the ND/Daxter logo SKIPPED on screen** — the title flythrough (`logo-intro-2`/`logo-loop`) renders, the earlier SCE + ND portions do not. **So this is a RENDER-PATH gap, not a state-machine skip.** Your job: find why the SCE static-screen texture blit and the `ndi` state (ND logo + `*ndi-cam-sg*` camera + Daxter/`*sidekick-sg*` merc draws) don't DISPLAY on GLES while the later `logo` flythrough does.

## Mandate (in order)

1. **Locate the render divergence with the 3-tier harness.** `.autoport/gold/compare-3tier.sh --boot` diffs our Android boot vs pristine. The state markers match — so the gap is in the DRAW path specific to: (a) `static-screen-spawn`'s full-screen texture blit (does our GLES DirectRenderer/sprite path handle it? is the texture bound? is it drawn to the visible framebuffer or a stale one?), and (b) the `ndi` camera (`*ndi-cam-sg*`) + the ND-logo geometry + Daxter (`*sidekick-sg*`) merc draws (does `ndi-cam` get installed as the active camera? do the ndi logo-slaves render? — contrast with `*logo-cam-sg*` which works in the later flythrough). Compare the render bucket / camera / texture setup between the `ndi` segment and the working `logo-intro-2` segment on Android.
2. **Fix at the mechanism** (GLES render path / camera install / texture bind — NOT the state machine, which is correct). No hardcoded blits, no faking the screens. The SCE screen and ND/Daxter logo must render from the real `static-screen`/`ndi` draws.
3. **Verify by capturing the RIGHT MOMENTS.** Per pristine timestamps the order is: SCE static (~boot), `ndi-intro` ND logo (~7-19s after title link), then `logo-intro-2` flythrough (~23s+). Capture device frames at early boot (SCE), mid (ND logo / Daxter), and late (title flythrough) with `mCurrentFocus` brackets, labeled by VERIFIED content. The SCE screen + ND/Daxter logo must be VISIBLE in their frames.
4. **Title-regression gate**: the title must STILL boot crash-free and fly (G1's win — `sig=11`=0, frame≥300, focus org.opengoal). Do not regress it.
5. **`Gintro-fix-summary.md`** (≥80 lines): the 3-tier render diff (what the SCE/ndi draw path does on Android vs why it doesn't display vs the working logo path), the fix, and the SCE→ND→title frame evidence.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**` (the state chain is correct — fix the renderer/runtime, NOT the .gc), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, `.autoport/gold/**` (gold reference is read-only), other phase prompts. You MAY edit the GLES renderer (`game/graphics/**`) and android runtime. No hardcoded/painted intro screens. `export ANDROID_SERIAL=eae4df44` only; keyguard; reversible app disables + RE-ENABLE; pgrep leftover run scripts. The supervisor judges whether the SCE screen + ND/Daxter logo actually render, by eye.

## Validator (`phase-Gintro-sce-nd-logo-render.sh`) — STRICT

PASS requires: a real **`Gintro-fix-summary.md`** (≥80 lines, must reference `static-screen`/`ndi`/`ndi-cam` AND the 3-tier/oracle render diff) PLUS the newest `Gintro-routed-logcat-*.log` showing ZERO `sig=11`, the `ndi-intro` + `logo` markers present, frame ≥ 300, set-master-mode reached, PLUS the newest `Gintro-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gintro-device-*.png`. Whether the SCE screen + ND/Daxter logo actually RENDER (and in order) is judged by the supervisor's own eyes on the captured early/mid frames — a clean title alone does NOT pass (that's G1's bar; this phase must show the EARLIER intro).

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

The gold standard already did the hard localization: the intro logic runs, only the SCE + ND/Daxter DRAW doesn't display. Diff the `ndi`/`static-screen` render path against the working `logo-intro-2` path (same engine, adjacent in time), find the GLES/camera/texture gap, and make the first two beats of the boot visible — in chronological order, before we touch the title-flythrough polish (Gtitle).
