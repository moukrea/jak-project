# Phase Gref-en — capture the ENGLISH pristine intro/title/menu reference FRAMES + pixel-diff the phone against them (FOUNDATION for "match the real build")

## Why (owner directive: "English is the gold standard")

The owner confirmed **English is canonical** (their French desktop was an outlier with a French save; the phone is English = correct). Every "fix it to match the real build" phase needs a real-build VISUAL reference, but so far we only have the pristine boot *log* (`.autoport/gold/pristine-boot-sequence.log`), not frames — so the supervisor could only verify "renders," not "matches." This phase produces the missing piece: **the English pristine gold build's actual intro/title/menu frames**, and a **pixel-diff of the current phone against them**, turning the owner's verbal issue list into a precise, grounded divergence list. It also settles the SCE-screen question empirically (we will SEE exactly what English-gold shows in the first frames instead of guessing from source).

## CAPTURE METHOD (reconned already — use this directly, do NOT re-investigate; recon-heavy attempts stall out)

The environment was already mapped: a live **Xwayland `:0`** + real GPU (`/dev/dri`) and a GNOME session are up; `wayland-0` also live. **No xdotool/ydotool** (can't press F2/START externally). gk uses SDL2; F2 writes a screenshot to disk via `make_screenshot_filepath`; GOAL exposes **`pc-screen-shot`** (kmachine.cpp:1067); the **GNOME Shell `Screenshot` DBus** method is reachable. So capture the pristine gk like this (pick the one that works fastest, don't spend turns re-discovering):
- Run `.autoport/gold/gk` with `DISPLAY=:0` (or on the wayland session) so it renders to the real GPU, boot jak1 (`--game jak1 --portable -fakeiso -iso-data ... -- -boot`), let the intro play, and grab frames at timed offsets (t≈2s,5s,8s,12s,30s,60s + after a START press if reachable) via **GNOME Shell Screenshot DBus** (`gdbus call org.gnome.Shell.Screenshot`) OR gk's own `pc-screen-shot`/F2-to-disk. Move them to `.autoport/gold/pristine-en/`.
- Work in SHORT steps (launch, wait, capture, kill) so the stall watchdog (>45s idle) doesn't cut you off mid-recon. Don't narrate a long investigation — just capture.

## Mandate (in order)

1. **Run the pristine gold build in ENGLISH and capture intro frames.** `.autoport/gold/gk` is the pristine upstream `704972dd6` build. Run it (jak1, fakeiso, default = English) and capture screenshots through the boot intro → title → main-menu sequence into `.autoport/gold/pristine-en/` (named by beat: SCE-or-none, ndi/ND-logo, jak-daxter-logo, title-press-start, menu-open). Use whatever headless-capture works (Xvfb + screenshot, the gk screenshot key, or offscreen) — document it. These are the REAL-BUILD ground-truth frames.
2. **Capture the current PHONE build at the same beats** (it's English already) into `.autoport/reports/Grefen-device-*` with spool/frame tags like prior phases.
3. **Pixel-diff phone vs pristine-en, beat by beat.** Produce `.autoport/reports/Grefen-divergences.md`: for each intro/title/menu beat, PRISTINE-EN shows X, PHONE shows Y, divergence = Z. Map each to the owner's reported issues: SCE screen (does English-gold even show one? what exactly?), ND/Daxter logo background (black vs level), J&D logo right-edge black coverage, stray level-names over PRESS START, water (animation/sunlight), missing geometry (rocks/structures/see-through), camera trajectory, menu garbled textures. Rank by severity + chronological order.
4. **Flag which of our own recent phases diverge from gold.** In particular: does the phone now show an SCE "presents" screen that English-pristine does NOT (i.e. did the Gsce un-gate force a non-gold screen)? State it plainly with the frame evidence so the supervisor can revert/correct.
5. **`Grefen-fix-summary.md`** (≥80 lines): the capture method, the per-beat pristine-vs-phone divergence table, the mapping to the owner's issues, and the prioritized fix order.

## Rules / Anti-cheat (hard)

This is a REFERENCE/AUDIT phase — it must NOT modify the engine/compiler/game. Locks: `goalc/**`, `game/**`, `goal_src/**`, `android/**`, `.autoport/lib/**`, `.autoport/validators/**`, the existing `.autoport/gold/` core (`gk`/`cgo`/`dgo`/`tierA*`/`pristine-boot*` — read-only; you may ADD `.autoport/gold/pristine-en/`), `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. No engine edits. `export ANDROID_SERIAL=eae4df44` for the phone capture; keyguard; reversible app disables + RE-ENABLE. The supervisor reviews the divergence frames by eye.

## Validator (`phase-Grefen-english-pristine-frames-audit.sh`)

PASS requires: a real **`Grefen-fix-summary.md`** (≥80 lines) with a per-beat pristine-vs-phone divergence table; a non-empty `.autoport/gold/pristine-en/` with captured pristine reference frames (≥3 beats); `.autoport/reports/Grefen-divergences.md` present; ≥1 `Grefen-device-*.png` phone capture; NO engine/compiler/game edits (reference-only); our x86 smoke still reaches `link finish: logo`. The supervisor reviews the pristine frames + divergence map by eye to drive the one-at-a-time fixes.

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

Stop guessing the intro from source — SEE what English-gold renders and diff the phone against it. This gives the supervisor real-build reference frames (finally able to verify "matches," not just "renders"), a pixel-grounded version of the owner's issue list, and the empirical answer to the SCE question. Then each beat gets fixed one at a time against these frames.
