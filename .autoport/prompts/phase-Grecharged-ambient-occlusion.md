# Phase Grecharged-ambient-occlusion — optional screen-space AO (SSAO), gated Recharged toggle

## Owner request (2026-07-11, backlog discussion)
"Tu penses que ça serait dur d'intégrer de l'occlusion ambiante ? Ça donnerait beaucoup plus de relief
partout ! À voir si pertinent sur l'herbe, et faut faire attention aux mesh transparents qui poussent
une texture avec de l'alpha car ça pourrait donner des ombres sur des parties transparentes (le truc
auquel faire giga attention). Pareil avec un toggle dans les Recharged settings."

## Approach (screen-space AO, post-process)
Add GLES post-process AO passes (SSAO/HBAO/GTAO share the pipeline) using the EXISTING depth FBO (the renderer already renders to a depth
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

## Two settings (owner 2026-07-11) — TYPE selector + separate QUALITY, implement ALL variants except baked
The Adreno 618 is only the WEAK test target for perf work — the shipping game also runs on powerful
devices (owner's Snapdragon 8 Elite Gen 5) and PCs. So AO is NOT gated by the Redmi; users scale it in
settings. Two Recharged Settings rows:
  1. "Ambient Occlusion: Off / SSAO / HBAO / GTAO"  (the ALGORITHM; Off == byte-identical stock)
  2. "AO Quality: Low / Medium / High"             (shown only when AO != Off; scales resolution +
     sample count: Low=quarter-res/few samples, Medium=half-res, High=full-res/full samples)
Implement ALL THREE algorithms (SSAO, HBAO, GTAO). Do NOT implement baked AO (owner: "sauf baked").
- SSAO  — classic screen-space hemisphere-kernel AO from the depth buffer. The cheapest/baseline.
- HBAO  — horizon-based: march rays in screen-space along depth to find the horizon angle. Higher
          quality, heavier than SSAO.
- GTAO  — ground-truth AO: physically-based horizon integral (cosine-weighted visibility). Highest
          quality, heaviest — meant for strong devices/PC; may be unplayable at High on the Redmi,
          that is EXPECTED and fine (the setting exists so the user picks what their device handles).
All three share the same depth-FBO source, the same alpha-exclusion handling, the same blur+composite;
they differ only in the occlusion-estimation shader. Engine goal_src untouched (renderer/pc layer only).
Report device fps for EACH algorithm at EACH quality (SSAO/HBAO/GTAO x Low/Med/High) on the Redmi so the
owner sees the cost curve; note which combos are Redmi-playable vs strong-device-only.

## PERF PHILOSOPHY (owner 2026-07-11) — Redmi max-settings fps is NOT a gate
Report the per-combo fps as an INFORMATIONAL cost curve only. Low Redmi fps at High/GTAO is EXPECTED
and is NOT a failure — the game ships to strong devices (Snapdragon 8 Elite / PC). The only perf
requirement: a fluid experience is reachable at a LOW setting (Off/SSAO-Low). Do NOT gate on, or spend
effort optimizing, Redmi max-settings fps. Gate on VISUAL QUALITY + Off==stock + no alpha artifacts.

## Verify (device eae4df44)
AO ON shows real contact/crease darkening (screencaps: a corner/contact vs OFF); NO boxy shadows on
alpha-cut foliage/grass cards (the risk beat); OFF == stock; fps ON/OFF reported; deploy_verify +
deploy_verify_assets PASS; force-stop after tests.

## Report (.autoport/reports/Grecharged-ambient-occlusion/report.txt) RESULT: AMBIENT OCCLUSION <verdict>
the SSAO pass (depth source, half-res, blur, composite), the alpha-exclusion handling + proof, the
toggle, fps ON/OFF, device captures ON vs OFF incl. the alpha-foliage risk beat.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 3500, max_retries 6. device: true, owner_verify: true.
