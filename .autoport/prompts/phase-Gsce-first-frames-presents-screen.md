# Phase Gsce — restore the "Sony Computer Entertainment presents" screen in the FIRST frames (chronological step 0)

## Ground truth (owner, direct observation — this is authoritative, not the source comments)

On the REAL game — **including the French / European (SCEE) version** — a **"Sony Computer Entertainment" presents screen appears in the very FIRST frames of boot**, before the Naughty Dog / Daxter logo. Our Android build does NOT show it. This must be restored. The owner has seen it directly; do not argue the point from source comments.

## PRIMARY LEAD (owner, decisive): it's a LANGUAGE/territory difference

The owner's **local desktop build runs in FRENCH and SHOWS the SCE screen**; the **phone build runs in ENGLISH and does NOT**. So the SCE screen's appearance is almost certainly **language/territory-gated**, NOT a render bug. OpenGOAL's title code gates by language/territory: `title-obs.gc` has `(#if PC_PORT (if (= (-> *setting-control* default language) (language-enum japanese)) ...))` (lines 180-189, 427-434) and `static-screen-spawn` is gated to `GAME_TERRITORY_SCEI` (line 554). **Find the exact gate that makes FRENCH show SCE and ENGLISH not**, then make the SCE screen show for the phone's language (English) too — matching the original (which shows an SCE "presents" screen in every region). The fix may be: un-gate the spawn for all languages/territories, OR correct how the Android build reports language/territory (`scf-get-territory` / `*setting-control* language` — the Android `DecodeTerritory()` / settings path may report English→a territory that drops SCE). Empirically diff the FRENCH-local vs ENGLISH-phone code path to pin the gate.

## Secondary detail (verify empirically — do not treat as settled)

OpenGOAL upstream appears to gate the boot static screen to **Japan only**: `goal_src/jak1/levels/title/title-obs.gc:554` spawns `static-screen-spawn` only when `(= (scf-get-territory) GAME_TERRITORY_SCEI) AND *first-boot*`. Our territory is SCEA/SCEE, so it never spawns — and the pristine upstream build (`.autoport/gold/`) ALSO doesn't show it on non-Japan (this is an UPSTREAM removal, not our port bug). So restoring the SCE screen is an **intentional content restoration to match the ORIGINAL game**, which deliberately DIVERGES from OpenGOAL upstream. The gold standard is for catching port bugs; here the TARGET is the original game's behavior, which the owner remembers and upstream dropped.

But CONFIRM empirically first: capture our boot's very first frames (t0-t5s) and verify the SCE screen is absent; identify exactly what asset/process renders it on the original (it may be `static-screen` index 5, or a different boot asset — find out, don't assume).

## Mandate (in order)

1. **Empirically confirm the gap.** Capture device frames at the earliest boot moments (before `ndi-intro`). Confirm no SCE screen renders. Determine what the original shows there (SCE "presents" — a static full-screen image/logo) and what code path produces it (lead: `static-screen` in `levels/demo/static-screen.gc` + the title-obs.gc:554 spawn).
2. **Restore it for all regions.** Un-gate the SCE static screen so it plays in the first frames on SCEA/SCEE (not just SCEI), matching the original game. This is a deliberate `goal_src` content change (the territory gate at title-obs.gc:554, and/or the related language/territory branches). It WILL change x86 too (shared source) — that is intended and fine (x86 would then also show SCE). Keep it faithful to the original sequence: SCE presents → (then ND/Daxter logo → title).
3. **Make it RENDER.** The SCE screen is a static-image/texture blit; ensure it actually displays on GLES in the first frames (if the static-screen render path has the same arm64 issues the ND logo hit, coordinate with Gnd's stomp fix — but the SCE static image is simpler than blend-shape geometry).
4. **Verify**: device frames in the first ~3 seconds VISIBLY show the "Sony Computer Entertainment" screen, BEFORE the ND/Daxter logo. Title still boots crash-free (regression gate). Capture the ordered sequence: SCE → (ND logo) → title.
5. **`Gsce-fix-summary.md`** (≥80 lines): what renders the SCE screen, the un-gate change, and first-frame evidence (frames showing SCE).

## Rules / Anti-cheat (hard)

This phase is permitted to edit `goal_src/jak1/levels/title/title-obs.gc` and `goal_src/jak1/levels/demo/static-screen.gc` (the SCE-gate content restoration) — an INTENTIONAL divergence from upstream, documented. Still LOCKED: `goalc/emitter/IGenX86_64.{cpp,h}`, the rest of `goal_src/**` (only the two title/static-screen files above), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/gold/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`. No hardcoded/painted SCE image — it must render from the real `static-screen` asset. x86 still boots to `link finish: logo` (it may now also show SCE — fine). `export ANDROID_SERIAL=eae4df44`; keyguard; reversible app disables + RE-ENABLE. The supervisor pixel-judges whether the SCE screen actually shows in the first frames.

## Validator (`phase-Gsce-first-frames-presents-screen.sh`)

PASS requires: a real **`Gsce-fix-summary.md`** (≥80 lines, references `static-screen`/territory-gate/SCE) PLUS the newest `Gsce-routed-logcat-*.log` showing ZERO `sig=11`, a `static-screen` SPAWN marker (not just link) — proving the screen is now created on our territory — frame ≥ 300, PLUS the newest `Gsce-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gsce-device-*.png` from the first ~3s. Only `goalc/emitter/IGenX86_64` + the locked set must be untouched (the two title/static-screen goal_src files MAY change). Whether the SCE screen visibly renders in the first frames is judged by the supervisor's eyes.

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

The owner sees "Sony Computer Entertainment" in the first frames of the real (incl. French) game; upstream OpenGOAL dropped it on non-Japan. Restore it for all regions, render it, and put the boot's very first beat back where it belongs — then the chronological intro is: SCE presents → ND/Daxter logo → title.
