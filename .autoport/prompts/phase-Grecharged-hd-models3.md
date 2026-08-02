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

## OWNER SYMPTOM ADDENDUM (2026-07-14 18:20, verbatim, Redmi with round-2 overlay + ENHANCED ON)
"le build sur le Redmi montre des trucs où on dirait que les modèles n'ont pas d'assets et rendent des
normales, très chelou"
=> On some draws the texture pages are apparently NOT BOUND AT ALL (untextured/normal-ish fallback
rendering), not merely mis-wrapped. Strengthens the per-draw texture audit: enumerate every draw's bound
page at runtime; any draw with a missing/failed binding must be named + fixed (or the character not
shipped). This is symptom #1 to reproduce and kill in round 3.

## CORRECTION (owner 2026-07-14 18:25, verbatim): "On parle de modèles de sol, pas des modèles remplacés !"
=> The untextured/normals-like rendering is on GROUND/level geometry, NOT the swapped characters. The
enhanced/ fr3s are FULL LEVEL files (the HD bake rebuilds the whole level fr3) — so the round-2 enhanced
bake CORRUPTED level-wide texture references (ground included), a bake-integrity failure, much bigger
than character texture binding. MANDATORY in round 3:
- Level-bake integrity gate: the enhanced <level>.fr3 must be IDENTICAL to stock for every non-character
  draw (same texture ids/pages, same geometry) — diff the fr3 contents draw-by-draw (or rebuild with a
  method that provably only touches the swapped merc models). Any diff outside the 4 characters = FAIL.
- Quick confirmation available: toggling ENHANCED MODELS OFF selects the stock fr3 -> ground textures
  should return instantly; if they do, the corrupted-enhanced-bake diagnosis is confirmed.

## ESCALATION (2026-07-14 19:10): the round-2 enhanced overlay is ACTIVELY TOXIC
Owner saw "tout violet" (all-magenta missing textures) on the Redmi — the corrupted round-2 enhanced
LEVEL fr3s were still being loaded because recharged-enhanced-models? stayed #t on the device. The
supervisor turned it #f (stock restored). RULES going forward:
- NO phase may leave ENHANCED ON on a device after its runs (same discipline as force-stop).
- Round 3 must treat the round-2 overlay as RECALLED: until the level-bake integrity gate passes, the
  enhanced fr3s must not ship, and the release notes must tell the owner to keep the toggle OFF.

## ============================================================
## DIRECTION FINALE 2026-08-02 — ANIM-RETARGET (REMPLACE le re-rig ci-dessus)
## ============================================================
L'owner a choisi le RETARGET D'ANIMATION plutôt que le re-rig. NE re-rig PLUS le maillage sur eichar.
On GARDE le squelette HD + ses poids d'origine, et on le LIE à eichar (qui joue les anims + sert les
joint-node hardcodés). Approche PROUVÉE offline à la précision machine (PROOF A err 8.9e-16, PROOF B).

DÉJÀ FAIT ET COMMITÉ (réutilise, ne refais pas) :
- `scripts/shell/prep_hd_actor_glb.py` : rip GLB → build_actor en gardant le squelette HD (pas de re-rig).
- `build_actor` fabrique déjà l'art-group (jgeo+merc-ctrl+anim) → `recharged_assets/hd_anim/jak-highres-ag.go`.
- `scripts/shell/retarget_fill_table.py` : table k→e (75/75) + preuve du remplissage.
- `tools/hd_merc_swap add` + `extract_merc.cpp::add_named_merc_model_to_level` : pose un `jak-highres-lod0`
  MercModel dans un FR3 stock par son NOM, append-only, INTEGRITY PASS.
- Boot `--hd-models` root-causé + gardé (build.sh vérifie la feature du libgk APK ; deploy_verify 4b).

IL RESTE — LE PROCESS COMPAGNON (goal_src, additif Recharged, autorisé) :
1. Charger `jak-highres-ag.go` dans un DGO de niveau + l'enregistrer dans `*art-info*` (miroir des `-ag.go`).
2. `defskelgroup *jak-hd-sg*` → art-group jak-highres, indices jgeo/mgeo/janim 0/1/2.
3. Nouveau process `jak-hd` calqué sur `sidekick.gc` (chevauche `*target*` via parent-override ; tourne
   dans `*matrix-engine*` APRÈS le driver pour que les bones d'eichar soient valides).
4. `do-joint-math!` override de `jak-hd` : au init précalculer `bind_hd[k]=inverse(jgeo_hd[k].bind-pose)` ;
   par frame, pour chaque k : `e=(-> *jak-hd->eichar-joint* k)` (utilise `recharged_assets/hd_anim/jak-hd-k2e.gc-snippet`) ;
   si `e==#xff` → `bone_hd[k]=bind_hd[k]` (repos) ; sinon
   `bone_hd[k] = (-> *target* skeleton bones (+ e 1) transform) · (-> *target* jgeo data e bind-pose) · bind_hd[k]`.
   Puis laisser le chemin stock `new-bones-mtx-calc-asm` tourner.
5. Cacher le maillage d'eichar SANS le figer : `(draw-status skip-bones)` sur le draw de `*target*` (PAS
   `hidden`, qui early-return `do-joint-math!` et gèlerait le driver).
6. Hook de spawn depuis target (miroir `sidekick.gc` `init-sidekick`), gaté derrière `--hd-models`.

VIGILANCE (à valider sur device) : le GLB prep a décrémenté JOINTS_0 (drop de `align`) tandis que
build_actor re-préfixe `align` dans le squelette de l'art-group → possible OFF-BY-ONE du binding d'os
au runtime. Vérifie l'alignement de l'index `align` entre le chemin add-model FR3 et l'art-group.

PREUVE EXIGÉE (device eae4df44, pas desktop) : `--pbr --debug --hd-models` boote propre (pid vivant
+ MainActivity à t+150s, exit-info sans reason=5/2), ET le skin HD de Jak SUIT une anim d'eichar
(nombres objectifs : deltas de position d'os/écran qui suivent l'anim ; os non-mappés au repos).
Jugement esthétique = l'œil de l'owner. Scope M1 = Jak seul ; les 4 persos + toutes anims = ensuite.

## ============================================================
## ARCHITECTURE IP (owner 2026-08-02) — NON NÉGOCIABLE
## ============================================================
Les modèles HD dérivent des dumps Jak 2 / Jak 3 = PROPRIÉTÉ DE NAUGHTY DOG. Donc :
1. FEATURE DISTINCTE avec son PROPRE feature flag (FLAG_HD_MODELS, déjà séparé du menu/PBR/etc.).
2. GATÉE SUR LES DUMPS : Jak-HD n'est POSSIBLE que si le dump correspondant est fourni par l'utilisateur
   (modèles Jak2 -> dump Jak2 présent ; modèles Jak3 -> dump Jak3 présent). Sans le dump : feature
   indisponible, build == stock à l'octet près.
3. ASSETS JAMAIS DANS LE BINAIRE : les assets HD (art-groups + merc générés) NE vont PAS dans l'APK /
   le custom pack (ce serait distribuer l'IP de ND). Ils sont GÉNÉRÉS LOCALEMENT depuis les dumps de
   l'utilisateur (iso_data/jak2|3) et placés dans l'ASSET PACK du jeu (les assets originaux fournis par
   l'utilisateur), comme tous les assets des jeux d'origine — chargés en externe sur le device.
4. DISTINCTION CLAIRE : les assets "Recharged" (nos propres créations de remake, PAS l'IP de ND) vont
   dans le binaire / custom pack. Les assets dérivés de ND (HD) vont dans l'asset pack externe, gatés
   sur les dumps. Ne JAMAIS committer d'asset dérivé de ND (déjà .gitignore : recharged_assets/hd_*).
