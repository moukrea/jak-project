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

## ============================================================
## HANDOFF TO FRAMEWORK WORKER 2026-08-03 (supervisor did the M1 groundwork by hand; now YOURS)
## ============================================================
The companion is WRITTEN + COMMITTED and builds. What remains is making the HD Jak actually RENDER on
device. STATE + hard-won findings (do NOT re-derive):

COMMITTED (on the current branch): goal_src/jak1/pc/jak-hd.gc (the jak-hd companion: defskelgroup
*jak-hd-sg* jak-hd 0 2, do-joint-math! override = stock then fill-jak-hd-bones!, spawn via
maybe-spawn-jak-hd! from (update *pc-settings*), get-process *default-dead-pool* + activate(*target*) +
run-now-in-process init-jak-hd), its DGO entries (game.gd+engine.gd), Loader.cpp load_common stages the
external hd/jak-hd-ag.go into <jak_project_dir>/out/jak1/obj/, build_enhanced_models.sh now APPENDS
jak-hd-lod0 to GAME.fr3 (append-only, NO re-rig REPLACE) + ships stock village1/village2 to overwrite
stale cursed overlays, build.sh gate updated for the APPEND, Merc2.cpp has a one-shot [jak-hd-render]
SUBMITTED name=... found=0/1 diagnostic log.

VERIFIED WORKING:
- companion spawns + loads its 76-bone/75-joint skeleton + is crash-free in-game (device, earlier builds).
- geometry jak-hd-lod0 IS appended to GAME.fr3 and IS on the device (/sdcard/OpenGOAL/jak1/assets/fr3/
  enhanced/GAME.fr3, 1448153 bytes). External→internal art-group copy PROVEN.
- OWNER SAW A VISIBLE HD JAK ON DESKTOP (x86) — so the full pipeline WORKS on desktop; the bug is
  DEVICE-SPECIFIC.

OPEN BUGS (owner-reported, in priority order):
1. **Jak (and Daxter) INVISIBLE in-game on device**, but VISIBLE on desktop. On the last Honor test
   (build9, BKQ-N49 serial AREE026206000788) the companion did NOT even spawn (no [JAK-HD] log) although
   *target* was valid in-game (GK-DIAG F1D showed a real world pos) — so the enhanced-models SETTING was
   likely #f in-app despite settings.ini being #t (the app may rewrite/re-read it). FIRST: confirm the
   companion actually spawns in the owner's real gameplay (check for [JAK-HD] spawned + [jak-hd-render]
   SUBMITTED in the routed logcat — opengoal-gk lines DO survive on both devices). If it submits but
   found=0 → merc name/index mismatch; if submits+found=1 but invisible → bones. Note Daxter invisibility
   is a KNOWN side effect: sidekick copies *target*'s draw-status every frame, so the companion's
   skip-bones on *target* propagates to Daxter — do NOT hide *target* until the HD Jak is confirmed
   rendering, and when you do, clear skip-bones on (-> *target* sidekick 0) each frame.
2. device bone-dump earlier showed the retarget SOURCE bones = (0,0,0) — but that was likely a
   non-gameplay test state; desktop listener shows *target* draw skeleton bones VALID. Re-check in REAL
   gameplay. draw skeleton bones ARE filled in do-joint-math! (post), and the companion is a child of
   *target* so its post follows.
3. matrix*! order in fill-jak-hd-bones! UNVALIDATED — if the HD Jak renders but is deformed, transpose
   the two matrix*!.

TOOLS BUILT (use/repair): .autoport/hd_x86_mercdiag.sh (desktop merc-submit probe — reads the
[jak-hd-render] log), .autoport/hd_x86_render_inspect.sh (has a listener form bug), Merc2.cpp diagnostic.
Desktop gk was rebuilt with OG_FEAT_HD_MODELS=ON (required or the HD C++ externs are unbound → crash).
Devices: Honor BKQ-N49 = AREE026206000788 (currently plugged in), Redmi eae4df44 (unplugged). Owner's
model-sourcing roadmap for Daxter/Samos/Keira is in memory [[project_hd_model_sourcing_roadmap]]. Owner
is FURIOUS about repeated broken deliveries — DO NOT ship again until the HD Jak is VISIBLY rendering
(the owner is the visual judge); verify the companion submits + the merc is found on device first.

## DEFINITIVE LIVE CLUE 2026-08-03 (Honor, app running in-game, owner watching)
The companion DOES spawn (routed logcat: `[R24CENSUS] excl jak-hd (-155.9720 33.8351 187.9818)`), but it
sits at ~ORIGIN (-155,33,187) while *target* is at world (-638861,138588,769973) — ~150km away. So the HD
mesh renders near origin, OFF-SCREEN from where Jak actually is → invisible + census-excluded. Root cause
is POSITIONING/CULLING, not geometry or submission (both are in place). Likely one of: (a) the jak-hd-clone
:post is not ticking, so (vector-copy! (-> self root trans) (-> *target* root trans)) + the origin update
never run → the process is stuck at its init/origin transform; or (b) the retarget bones in
fill-jak-hd-bones! are in LOCAL space, not the world space the merc/culling path expects (desktop showed
*target* skeleton bones as WORLD coords ~(-5.3e6,...), so the READ path gives world — verify the WRITE/merc
consumption). FIRST STEP for the worker: instrument the companion's root trans + draw origin + a filled
bone's world pos in the :post (they should equal *target*'s ~(-638861,...)); if they're ~origin, the :post
isn't running (fix the child-of-target activation / state) — if they're world but the mesh is still at
origin, the merc bone-space is wrong. Owner: the setting IS #t, target IS valid in-game; do not blame the
setting. The [jak-hd-render] merc log is ONE-SHOT (static bool) so it may have already fired+rolled off —
make it repeat-with-throttle if you need a live read.

## ============================================================
## OWNER REQUIREMENT 2026-08-03 (late): the chosen model must apply EVERYWHERE — incl. the ND-logo screen
## ============================================================
Owner: "pourquoi ça utilise pas le modèle HD au logo de Naughty Dog ?! Ça devrait utiliser le modèle
choisi (la version HD de Jak) PARTOUT ! Si ça se trouve c'est une partie de ton problème."

He is right on the design: the OLD replace-based approach swapped eichar-lod0's geometry in the fr3, so
the HD Jak appeared EVERYWHERE eichar is drawn (ND-logo intro, title, gameplay, cutscenes) — but it was
re-rigged = cursed. The current companion only shadows *target* (the playable Jak), so every OTHER
process that draws eichar (the ND-logo intro actors, cutscene actors, title) stays STOCK. That is a
DESIGN GAP to close, not a nice-to-have:

1. REQUIREMENT: when the enhanced-models toggle is ON, the HD model must cover EVERY instance of the
   character on screen — ND-logo intro, title screen, in-game, cutscenes. "Le modèle choisi partout."
2. INVESTIGATE (may also explain the in-game invisibility — same class of question, "which process
   draws Jak where"): enumerate the processes that draw eichar-lod0 (the ND-logo/title intro actor(s),
   *target*, cutscene actors). For each, decide the mechanism: per-process companion (generalize
   jak-hd.gc beyond *target*), or a smarter unified path. NOTE the constraint that killed the old
   approach: a merc model is skinned by the bone palette of the process that draws it, so geometry
   swapped INTO eichar's slot must be weighted on eichar's skeleton (= re-rig, deforms). The companion
   exists precisely to keep the HD skeleton. If you find a way to REPLACE eichar-lod0 with the HD
   geometry re-INDEXED via the proven k->e table (weights kept, joints remapped, bind-delta baked) that
   does NOT deform, that would give "everywhere" for free — evaluate honestly, do not re-create the
   carnage. Otherwise: companions for the logo/cutscene processes too.
3. The logo screen showing STOCK Jak+Daxter right now is the append-only fix working as designed (the
   cursed enhanced eichar replace is gone) — expected, but per the requirement above it must become HD.
