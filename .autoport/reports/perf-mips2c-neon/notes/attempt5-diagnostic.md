# Reprise — essai 5
DIRECTIVES vaff5c1afea

## Diagnostic repris, sans nouvelle course
Le contrat complet et validator-004.txt ont été lus. Le validateur constate huit
défauts, dont l'identité de course essai1 au lieu d'essai4 et parity_defects=3.
Ces refus de fraîcheur ne justifient pas de répéter une course aux préalables absents.
Les audits des essais2–4 restent acquis ; leurs recherches n'ont pas été répétées.
Deux researchers natifs Codex, high, ont examiné les seuls reliquats et la préparation.

## Défaut indépendant dans la qualification des images
Avant correction, perf_instruments.cpp:69–79 utilise les cumuls compared[] pour
qualifier une image où un seul des compteurs avance. Une image commune suivie de
599 images joints peut donc couper l'oracle avec une seule image os/particules.
La correction exige que chacun des trois compteurs avance dans l'image courante.
Elle conserve le seuil600, les compteurs individuels, les défauts et la condition refset.
Tests exécutés : attempt5-parity-tests-before.txt reproduit sparse avec frames=600,
verify=0 et défauts=0 (1 échec,6 succès). Après : frames=1, warmup=599,
verify=1 et défauts=1 (7 succès dans attempt5-parity-tests-after.txt).
Les builds sont consignés séparément ; aucun résultat en jeu ne se déduit de ces tests. Aucun nouveau noyau ni consommateur SIMD ajouté.

## Reliquats et activité
Researcher : git diff --exit-code 8363e895b1^ HEAD sur bones.cpp, joint.cpp et
sparticle_launcher.cpp rend0 : retrait des noyaux spéculatifs déjà terminé.
settings/record n'ont actuellement aucun consommateur moteur. Le raccordement
kmachine.cpp:5547 -> perf_instruments.cpp:frame_boundary existe toujours.
Sans item nommé, le compteur retourne ; avec item nommé, il publie chaque60 images.
Son surcoût n'est pas mesuré ; aucun oracle permanent actuellement appelé n'est établi.
La table fonction/chemin/activité reste celle d'attempt3-diagnostic.md (historique).
Troisième optimisation pertinente toujours non établie : pas d'ajout SIMD ni de course.

## Préparation refset, lecture seule
proof_run.sh n'appelle aucun préparateur de replay de cet item. Les préparateurs HDR
sont réservés aux campagnes HDR. Le manque de PNG est découvert en jeu
(refset.cpp:4001–4005), après amorçage et remplacement des journaux de la course.
Le filtrage par continue-point inclut beach-sun avec beach-start (refset.cpp:2866–2869).
Un contrôle d'existence empêcherait cette dépense, mais ne qualifierait pas la provenance.
Pas d'ajout d'un second sélecteur de cas codé en dur ni d'un nouveau banc de préparation :
les préalables contractuels empêchent déjà cette course ; absence signalée dans FINDINGS.
Les conclusions attempt4-refset-audit.md restent applicables : h09 non lié à son
manifeste et références plage Android phase1 manquantes. Aucune distribution justifiée.

## Préservation et autorisation
proof*, sources des noyaux, ripple, validateur, producteur et backlog empreintés dans
attempt5-preservation-before.json. Rapports de l'essai4 archivés dans notes/attempt4-*.
Sélection USB en lecture seule par pick_device.sh : eae4df44, code0.
Aucun proof_run, validateur, déploiement ni capture lancé. Aucun owner-ok créé.
Différences de cibles/références depuis essai1 : wrappers retirés en essai2 ; aucune
nouvelle cible, aucune référence remplacée ; priorité warp corrigée en essai3,
nettoyage shell corrigé en essai4, qualification des images corrigée en essai5.

## Compilation du correctif
Tester natif Codex medium : x86 code0 en45,554s, ARM64 code0 en9,522s.
La porte x86 publie bx_bin_fresh=1,46 entrées, aucun travail résiduel.
Source<objet<binaire sur les deux arbres ; aucun warning:/error: dans ces logs.
Synthèse machine : attempt5-build-summary.txt ; ce ne sont pas des mesures en jeu.
