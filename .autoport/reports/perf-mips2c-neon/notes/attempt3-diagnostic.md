# Reprise — essai 3
DIRECTIVES vaff5c1afea

## Correction terminée
`game/kernel/jak1/kmachine.cpp:5974` distingue maintenant environnement absent et explicitement vide.
Le repli Android reste disponible au premier warp quand l'environnement est absent.
Une position vide posée par `refset.cpp:1641` ne reprend plus la propriété initiale.
Le chemin perf_baseline garde sa priorité et son traitement du vide.
Trace du défaut historique : proof-engine.log:51753–51755, beach-start reçoit (-116,14,40).
Test du bloc de production extrait : notes/attempt3-warp-precedence.py ; dix PASS dans le .txt voisin.
Ce test compile sur hôte, avec un substitut de propriété pour la branche Android ; aucune preuve en jeu.
Builds : notes/attempt3-build-x86.log et attempt3-build-arm64.log, build_exit_code=0.
Source < objet < archive < binaire sur chaque architecture ; x86 bx_bin_fresh=1, bx_residual_work=0.
Première invocation directe du script x86 : code126 (mode non exécutable) ; reprise via bash réussie.
Pas de déploiement, proof_run ou validateur. Sélection USB en lecture seule : eae4df44, code0.

## Cibles — audit indépendant vérifié
Les compteurs ci-dessous sont HISTORIQUES, run 20260914T211200Z-949576-04ffe282.
| Fonction | Chemin / trace | Décision |
|---|---|---|
| bones-mtx-calc | ancien chemin ; proof.txt:905 = 0 opération | ne pas réintroduire |
| new-bones-mtx-calc-asm | GOAL actif selon source, machine déjà vectorielle, audit essai2 | ne pas rediriger |
| cspace<-parented-transformq-joint! | proof.txt:908–909 = 20183198 opérations / 13886 images | gain supplémentaire inconnu |
| sp-launch-particles-var | proof.txt:915–916 = 159438 opérations / 1634 images | gain supplémentaire inconnu |
| sp-process-block-2d | proof-engine.log:686932 = 10.13ms/1620c/96000it | fast-path Gperf-particles déjà acquis |
| sp-process-block-3d | même ligne = 0.88ms/180c/7680it | coût du bloc candidat non isolé |
Ces temps sont des TOTAUX PAR 60 IMAGES : android/android_opengl_renderer.cpp:1420 échange les compteurs et divise par 1e6, sans /60.
Les itérations incluent les emplacements invalides (game/mips2c/spart_prof.h:15).
2D : sparticle.cpp:684–741 calcule déjà les vecteurs localement ; quantification acquise :802–815.
Les objets ARM déjà examinés contiennent des opérations vectorielles ; aucun ajout d'intrinsics ne suffit à démontrer un gain.
3D :247–278 reste une piste, pas une spec justifiée par un coût propre ni une amélioration machine établie.
Trois cibles pertinentes NON établies : le contrat interdit dès lors ajout SIMD et course.
Compteurs/comparateurs non raccordés à de nouvelles cibles ; séparation oracle/coût reste à traiter lors du raccordement.

## Références supplémentaires retrouvées, mais incompatibles
Lot : .autoport/reports/lighting-hdr/batches/essai43-coverage/20260908T162138-84202/.
manifest.json:549–558 : producer=proof_run.sh, serial=eae4df44, binary_fnv=a82801927bc19926.
captures/origine-lumiere/beach-start-h09.png.provenance.txt : phase origine-lumiere, capture_lf=1635,
data=268cbd69a53f761f, input=6df5d1ca3dadbd94 ; SHA256 PNG/sidecar correspondent au manifeste (audit researcher).
Ce lot n'a pas de référence origine phase1 ; manifest.json:14 porte exact_frame_required=false.
Les beach-sun retrouvés hors fixtures sont du lot essai62-x86-final/20260909T112350-625123 et ses copies rejetées ; source=x86 au manifeste:467.
Aucune référence plage Android phase1 qualifiée retrouvée ; aucun transfert, renommage, recapture ou changement d'origine.

## Hutte : régime de capture historique non équivalent
C = .autoport/reports/lighting-hdr/notes/refset-capture-032947.log ; R = proof-engine.log de cet item.
C:929–930 : neutral.inputs, seed=0x0ad12345, mode=2 ; C:3636 : RNG forcé.
R:1047 : mode=0 ; R:5096 : input=0000000000000000. Le rejeu manette est explicitement désactivé.
C:51397 : dernier FBO avant h09 à 960x432 ; R:5211 : dernier FBO avant comparaison à 800x600.
C:58019 : origine/h09 step=9/24 ; R:51747 : chain_lf=1082 anchor_lf=902, premier cas.
La frame nominale 2701 de l'ancienne capture se déduit de l'ancre901, settle180 et indice9 ; elle n'est pas directement journalisée.
Ces traces établissent des différences de régime, pas leur contribution isolée à maxdiff233 (R:51748).
La liaison cryptographique entre cette capture032947 et le PNG USB h09 inventorié à l'essai2 n'est pas établie ici.
Il faut reconstruire la provenance/configuration exacte avant tout réglage de replay ; aucun changement manuel de prop/backlog.

## Décision et reprise
Différences effectives depuis essai1 : wrappers retirés à l'essai2 ; priorité env/prop corrigée à l'essai3.
Cibles nouvelles : aucune ; références remplacées/distribuées : aucune ; scénario et seuils : inchangés.
Preuves historiques conservées et empreintées dans attempt3-preservation.txt, jamais résultat courant.
Les archives des rapport/handoff/FINDINGS essai2 sont dans notes/attempt2-*.
Le superviseur dispose maintenant d'un diagnostic plus précis pour résoudre le périmètre des références et des trois noyaux ; cet essai ne le réduit pas.
Non prouvé : replay=0, parité trois populations/600 images, hd-mtx-check-all, gain par seau, absence de crash en jeu et fraîcheur appareil.
