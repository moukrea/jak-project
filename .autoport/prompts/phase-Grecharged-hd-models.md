## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY yourself (look at the models on screen). Delegate to autoport-researcher
(art/merc format + skeleton analysis, jak2 model extraction), autoport-implementer (pipeline edits),
autoport-tester (builds/device/screencaps). Parallelize.

# Phase Grecharged-hd-models — jak2's detailed character models INTO jak1 (conditional Recharged option)

## Owner idea (2026-07-07)
jak2's intro cinematic (before "2 years later") shows Jak, Daxter, Samos and Keira in their JAK1 look
(bright jak1 colors/tone) but with jak2's MUCH more detailed cinematic models. If jak2's assets are
AVAILABLE at jak1 build time, extract those 4 character models and use them to REPLACE the low-poly
jak1 models. Skeleton/skinning ("zones d'influence") may not match perfectly — worth trying anyway.

## Mandate
1. **Feasibility first (honest)**: extract the 4 jak2 intro-era character models (Jak, Daxter, Samos,
   Keira — the jak1-look variants used pre-timeskip) from iso_data/jak2 (decompiler art extraction /
   .glb rip). Compare rigs vs jak1's: bone counts/names/hierarchy, skinning weights, joint indices
   used by jak1 anims (jak1 animations must drive the new mesh — we replace the MODEL, not the anims).
2. **Import path**: use/extend OpenGOAL's custom-model pipeline (.glb -> jak1 merc; the custom actor/
   model tooling) to rebuild the jak2 meshes on jak1's skeletons — retarget/remap bones where names
   differ; re-bind weights to the nearest jak1 joint when needed. Textures come along (jak1-look
   palette). PER CHARACTER: land what works; an honest partial (e.g. Jak + Daxter only) is a WIN.
   Document precisely any character that can't be made to deform acceptably and why.
3. **Conditional build**: a build flag auto-set by jak2-asset availability (iso_data/jak2 present at
   build time). If absent -> jak1 builds exactly as today, option hidden. If present -> the enhanced
   models are baked as an ALTERNATE asset set (both sets shipped in the jak1 build).
4. **Toggle**: Graphics Options > Recharged Settings > "ENHANCED MODELS" ON/OFF (persisted, default
   OFF = stock low-poly; row only visible when the build carries the enhanced set). Runtime switch of
   which model set loads (relaunch acceptable if live-swap is unreasonable).
5. OFF path byte-identical to stock. Engine goal_src untouched where possible (pc/ + asset pipeline +
   renderer/loader glue; gated hooks). x86 + Android both.

## Verify (device eae4df44 + x86)
Screencaps ON vs OFF per landed character (in-game + ideally a cutscene beat): enhanced mesh visibly
more detailed, jak1 animations play WITHOUT broken deformation (elbows/knees/jaw not collapsing —
capture idle + walk + a talk cutscene). mCurrentFocus=jak1. Toggle hidden when built without jak2
assets (prove with a no-jak2 build). OFF == stock. deploy_verify PASS; x86 link finish: logo.

## Report (`.autoport/reports/Grecharged-hd-models/report.txt`) `RESULT: HD MODELS <landed>/4`
per-character verdict (landed / partial / infeasible + WHY: bone map, weight rebind quality), the
extraction+import pipeline, the conditional-build mechanism, toggle proof, ON/OFF screencaps.

## Locks: ANDROID_SERIAL=eae4df44 only; OFF==stock; .autoport/gold READ-ONLY; full consistent builds;
verify mCurrentFocus=jak1 before trusting frames.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
