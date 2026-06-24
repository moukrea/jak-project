# Phase Gaudio-hint-voices — in-game tutorial/hint dialog VOICES are silent (+ some action sounds)

## The defect (owner clarification, 2026-06-24) — NARROW, specific
NOT all audio: the cinematic voices + background sounds are FINE. Missing on Android:
- **The VOICES of the in-game mini-cinematic / tutorial-hint dialogs** — e.g. the Sage / hint
  speaker who explains orbs, items, mechanics during gameplay. The text/cinematic plays but **no
  voice**. (Cinematic voices work — so the general VAG/voice path is fine; it's the in-game
  hint/`talker`/`ambient` dialog voice trigger specifically that doesn't play on arm64.)
- **Some action sounds** missing on certain actions (identify which vs x86).

## Methodology — x86-first, find the in-game hint-voice trigger gap
1. x86-first: identify the in-game tutorial/hint dialog system (`talker`/`ambient`/`hint`/`speech`
   — the GOAL process that plays the Sage explanations) and how its VOICE plays on x86
   (`play-ambient`/`talker` → VAG stream slot → 989snd). Note which stream slot/handle it uses
   (distinct from the cinematic voice slot, which works).
2. On device: when an in-game hint should speak, does the talker process fire? does it request the
   VAG voice stream? does that stream slot reach AAudio (per-source RMS, like Gaudio-sfx's meter)?
   Find where the hint-voice path diverges from the (working) cinematic-voice path on arm64.
3. Likewise isolate the missing action sounds (which `snd-play` calls produce 0 on device vs >0 x86).
4. Fix the root in the translation layer; goal_src 1-to-1; x86 unaffected.

## Validator (`phase-Gaudio-hint-voices.sh`) PASS requires
1. `.autoport/reports/Gaudio-hint-voices/voices.txt`: device per-source RMS shows the in-game
   hint/tutorial dialog VOICE goes from 0 (BEFORE) to >0 (AFTER) when a hint speaks, and the named
   missing action sounds go 0->>0 — calibrated, with the cinematic voice (working) as reference.
   With `RESULT: IN-GAME HINT VOICES + ACTION SFX AUDIBLE (device)`. Name the trigger/route gap.
2. Real code change; goal_src 1-to-1; fix-summary >=60 lines; temp instrumentation removed; golden
   pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS. Owner ear = final.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. `.autoport/gold` READ-ONLY. Keep device awake. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
