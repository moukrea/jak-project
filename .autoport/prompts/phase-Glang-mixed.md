# Phase Glang-mixed — audio EN + texte FR: certains textes d'interaction restent en anglais

## Why (owner 2026-07-03, v3 playtest)
With AUDIO set to English and everything else (text/subtitles) set to French, SOME texts remain in
English — specifically interaction prompts with objects or characters. They must follow the TEXT
language (French), not the audio language.

## Mandate
1. REPRODUCE on eae4df44: set audio=EN, text/subtitles=FR (menu or pc-settings.gc), walk to an
   interactive object/NPC and screencap the offending English prompt(s). Sweep for MORE cases (hint
   prompts, talk/examine, warp/save prompts, HUD strings) — list every affected string.
2. ORACLE: same settings on the pristine x86 golden. If x86 shows French there, this is an Android/
   arm64 divergence (settings plumbing or text-bank load) — find where the text-language id gets
   lost (pc-settings load order? a bank keyed off audio language? a missing FR entry falling back
   EN?). If x86 ALSO shows English, it is an upstream behavior the owner still wants fixed —
   implement in the pc/ layer (pc/ goal_src + runtime are ours), document the delta honestly.
3. FIX so every affected string follows the TEXT language. Verify: the repro prompts render French
   with audio EN; switching text language back to EN still works; no other-language regression
   (check at least EN/FR both ways). x86 link finish: logo. Full CONSISTENT build, deploy_verify.

## Report (`.autoport/reports/Glang-mixed/report.txt`) with `RESULT: TEXT FOLLOWS TEXT LANGUAGE`
the affected-string list, the oracle verdict (divergence vs upstream), where the language id was
lost, the fix (file:line), before/after screencaps, both-ways language check, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched (pc/ ok); .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
