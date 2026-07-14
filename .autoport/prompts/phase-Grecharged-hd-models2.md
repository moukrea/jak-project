## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself via the OWNER'S REAL INSTALL FLOW (below), never adb-push shortcuts.

# Phase Grecharged-hd-models2 — ROUND 2. Round 1 shipped CURSED models; owner play-test FAILED.

## Owner play-test on round 1 (2026-07-14, verbatim — HIS eye is the gate)
"ça a effectivement chargé les modèles PS2 (mais je pense les modèles in game du 2 au lieu des modèles
que je disais)... Ils sont cursed as fuck, les polygones sont garbled, il manque des éléments, le
retargeting est complètement foiré ... Pour les modèles seuls Jak and Daxter sont changés"

## THREE hard failures to fix (round-1 report "4/4 acceptable" was FALSE on device)
1. WRONG SOURCE. Owner wants the jak2 FIRST cutscene models — the intro cinematic BEFORE the rift gate,
   where the cast still looks like JAK1-style characters in HD (owner original spec 2026-07-07). Round 1
   ripped jak2 IN-GAME / generic highres actors. Identify the exact intro/first-cutscene actor source
   (the jak1-look highres set), NOT the in-game models. Prove the source with a still of the rip vs the
   jak2 intro cutscene.
2. GARBLED RETARGET. Polygons garbled + elements missing = the weight-borrow find_closest spatial hack
   fails. Do it properly: name-based joint remap to the jak1 rig (custom skin + enable_custom_weights,
   joints reordered to jak1 order) so the mesh deforms clean — or, if a character can't be made clean,
   DO NOT ship that character (honest partial), never ship garbled geometry.
3. COVERAGE. Only Jak+Daxter swapped; Samos+Keira did not. Either fix all four or ship only the clean
   ones and say which — no silent 2/4 while claiming 4/4.

## MANDATORY VERIFICATION — the owner's REAL install flow (my Redmi adb-push tests were worthless)
Do NOT validate by adb-pushing assets to the device external folder. Validate the way the OWNER installs:
build the SLIM APK + the external archive (scripts/package_game_assets.sh jak1), install the slim APK
clean, extract the archive to the external asset root, boot, kill+relaunch (models load on reload),
toggle ENHANCED MODELS, and CAPTURE each of the 4 characters. A pass requires clean (non-garbled) HD
geometry from the CORRECT source on the characters you claim, via THIS flow. OFF==stock. goal_src rules
apply. Report RESULT: + honest per-character verdict + the install-flow evidence.
Max: max_turns 3000, max_retries 6.
