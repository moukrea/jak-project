## WORK ECONOMY: MANAGER verifies via the OWNER'S REAL INSTALL FLOW + close-up FACE captures.

# Phase Grecharged-hd-models3 — ROUND 3. Round 2 owner verdict: "un carnage".

## Owner verdict on round 2 (2026-07-14 16:10, verbatim — the acceptance list)
"Pour les personnages HD, les textures ça colle mal, le retargeting est loupé, on voit pas la mâchoire
de Daxter, les polygones ont un drôle de shading, c'est complètement loupé... Les yeux de Jak sont pas
texturés, ni son masque, la texture est très mal wrap... Enfin un carnage, tu peux faire beaucoup mieux
que ça !"

## Defects → prime technical suspects (verify each, don't guess)
1. "texture très mal wrap" + "drôle de shading": round-2's retarget WELDED vertices by position and
   RECOMPUTED smooth normals. Welding across UV seams merges vertices that carry DIFFERENT UVs → broken
   texture wrapping; recomputed normals discard the donor's authored normals → wrong shading. FIX:
   never merge vertices with distinct UVs; PRESERVE the donor GLB's authored normals (transformed by the
   re-pose), no recompute. Prove with a UV-integrity check (per-vertex UV identical donor->shipped) and
   an offline render matching the jak2 intro look.
2. "yeux de Jak pas texturés, ni son masque": enumerate the donor model's DRAWS and their texture pages;
   eyes/mask likely use separate pages or the jak1 eye-draw system (copy_eye_draws). Every draw must bind
   its real page — list them in the report (draw -> texture name) and show a FACE CLOSE-UP capture.
3. "on voit pas la mâchoire de Daxter": find the jaw polys in the donor — missing draw, inverted
   winding/backface cull, or zero-weight collapse. Name the cause, fix, close-up proof.
4. "retargeting loupé": re-audit the name remap on the deformation actually seen (not just weight
   stats): capture idle+walk+talk close-ups per character and compare against the JAK2 INTRO CUTSCENE
   RENDER as ground truth (side-by-side, same character same angle).

## Verification (unchanged discipline + NEW: faces)
Real install flow only (slim APK + archive extraction, sha==device); all 3 loaded-model discriminators
per run; NEW MANDATORY: close-up FACE captures (eyes/mask/jaw visible) per character ON vs the jak2
intro ground-truth still — the owner judged at face distance, the round-2 zooms were too far. OFF==stock.
Honest per-character verdict; do NOT ship a character whose face is broken (honest partial beats carnage).
Report RESULT + per-defect proof. Max: max_turns 3000, max_retries 6.
