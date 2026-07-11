# Phase Grecharged-ambient-occlusion — optional screen-space AO (SSAO), gated Recharged toggle

## Owner request (2026-07-11, backlog discussion)
"Tu penses que ça serait dur d'intégrer de l'occlusion ambiante ? Ça donnerait beaucoup plus de relief
partout ! À voir si pertinent sur l'herbe, et faut faire attention aux mesh transparents qui poussent
une texture avec de l'alpha car ça pourrait donner des ombres sur des parties transparentes (le truc
auquel faire giga attention). Pareil avec un toggle dans les Recharged settings."

## Approach (screen-space AO, post-process)
Add a GLES post-process SSAO pass using the EXISTING depth FBO (the renderer already renders to a depth
buffer). Reconstruct view-space position + normal from depth, compute a hemispheric occlusion factor
(kernel samples + range check), blur it (bilateral, depth-aware), and multiply it into the scene during
the final composite. HALF-RES AO buffer + blur for Adreno 618 fill-rate. Do NOT restructure the DMA->GLES
pipeline — this is an added full-screen pass.

## #1 RISK (owner-flagged, handle from the start): alpha/transparent meshes
Jak renders many "solid" things as ALPHA-CUT textures on simple meshes (foliage, fences, the recharged
grass CARDS, etc.). If these write to the AO depth, SSAO computes occlusion on the MESH silhouette, not
the visible alpha shape -> boxy shadows / halos on the transparent parts. MUST exclude alpha-blended /
alpha-tested transparent surfaces from the AO-depth (only truly OPAQUE geometry contributes to AO), or
handle alpha-tested with proper coverage. Verify explicitly on a foliage/grass-card beat: no square
shadow on transparent bits.

## Toggle + scope
Recharged Settings row "AMBIENT OCCLUSION" ON/OFF, persisted, default OFF (OFF == byte-identical stock).
Optional quality/strength setting. Engine goal_src untouched (renderer/pc layer only). Report fps ON/OFF
on device (SSAO is fill-heavy — must stay playable; tune radius/samples/res).

## Verify (device eae4df44)
AO ON shows real contact/crease darkening (screencaps: a corner/contact vs OFF); NO boxy shadows on
alpha-cut foliage/grass cards (the risk beat); OFF == stock; fps ON/OFF reported; deploy_verify +
deploy_verify_assets PASS; force-stop after tests.

## Report (.autoport/reports/Grecharged-ambient-occlusion/report.txt) RESULT: AMBIENT OCCLUSION <verdict>
the SSAO pass (depth source, half-res, blur, composite), the alpha-exclusion handling + proof, the
toggle, fps ON/OFF, device captures ON vs OFF incl. the alpha-foliage risk beat.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 3500, max_retries 6. device: true, owner_verify: true.
