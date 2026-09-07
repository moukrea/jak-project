# Notes — lighting-census, essai 7
DIRECTIVES v6fca51fe40

Reprise du code et de la capture de l’essai 6, pas seulement du handoff essai 5.
Le journal historique `.autoport/refset/refset-capture.log` finit sur
`REFSET done steps=564 captured=564 compared=0 maxdiff=0 diffpx=0 missing=0 slip=0..0 rewarps=591 settle=180`.
Ce zéro est celui d’une CAPTURE sans comparaison, pas un rejeu validé.
Dernières grandeurs historiques : niveaux=21, intérieurs=13, niveaux à ciel=14,
ciel manquant=8 (sunkenb, toutes les heures), marge de chargement minimale=179.
La capture a duré environ 38 minutes (notes/capture-final.out : 09:25–10:03).
Conformément à l’économie de preuve, aucune répétition de cette campagne pendant cet essai.

## Corrections
Les six vues à deux heures passent à huit : misty-bike, village2-dock, sunkenb-helix,
swamp-start, swamp-cave1, snow-fort. Plan attendu : 28 × 8 × 3 = 672 images.
La porte census conserve la sentinelle si couverture incomplète ou cinq rejeux exacts absents.
Les lignes de registre éligibles portent aussi une empreinte de configuration et l’armement ;
les anciennes lignes et les courses désarmées ne créditent pas les cinq rejeux.
Les anciennes clés de comparaison des autres items conservent leur comportement.
Le recensement distingue ORIGINE-LUMIÈRE et respecte la capacité C/E du programme lié,
ainsi que le bypass de textures. Aucun shader ni donnée d’origine modifié.

## Références conservées
`references-essai7.sha256` fige les empreintes des 572 fichiers existants du plan neuf.
564 appartiennent à la dernière capture complète. Les 8 autres sont des fichiers antérieurs
aux heures supplémentaires (liste `references-hors-derniere-capture-essai7.txt`) : leur présence
ne les qualifie pas comme références du nouveau plan. 100 fichiers sont absents
(liste `references-manquantes-essai7.txt`), donc 108 étapes restent à établir.
Aucun PNG ni captured-by.txt ni registre historique n’a été réécrit par le worker.

## Sunkenb : limite du constat
Le flag sky est vrai (level-info.gc:903), mais ses deux continue-points sont profonds
et affichent aussi sunken (level-info.gc:907–942). sky-tng.gc:901–913 exige d’autres
conditions de dessin, sans suppression spécifique à sunkenb trouvée.
Les mesures à zéro n’établissent PAS une impossibilité générale de montrer le ciel.
Ne pas retirer sunkenb de la liste moteur ni reprendre l’affirmation historique
« son ciel n’est jamais visible » comme un fait établi.

## Exécution
Build unique : `cmake --build build --target gk -j 4`, code 0, build-essai7.log.
Premier appel proof_run interrompu avant lancement : son pgrep -f prenait le PID 2750541
(comm=codex, prompt contenant goalc/) pour un compilateur. Builder 2541075 repris par trap.
Correction minimale du runner : pgrep -x pour goalc/ninja/ninja-build/cc1plus ; détection
Java conservée. Aucun validateur ni collecte/champ de preuve modifié.
Tests ciblés : test_proof_busy.py, 5 passed en 0.30 s ; bash -n proof_run.sh, code 0.
Reprise autorisée : une course armée 180 s, une ablation 120 s ; pas de nouveau build.
Le builder idle est suspendu par PID exact pendant ces courses, puis repris via trap EXIT.

## Correction de dernière revue
Le premier run moteur a été interrompu à 106 s / 6020 frames pour corriger la passe ETIE.
Son proof a été produit par le runner (rc moteur143 => crash1) puis archivé sous
`essai7-interrompu-proof.txt`, avec son log ; ce résultat ne qualifie pas le binaire final.
ETIE est une passe envmap sans shade() (Tie3.cpp:1679, shader etie.frag), mais le miroir
CPU lui attribuait A lorsque rt_light_on=1. host_paths distingue maintenant présence de
shade() et disponibilité des composites legacy. Les hôtes sont TFRAG3, TFRAG3_TESS,
ETIE_BASE, TIE_WIND, SHRUB sous OG_FEAT_PBR ; HFRAG et profondeur gardent leurs catégories.
Revue native Codex après correction : aucun défaut nouveau identifié ; aucune écriture GL ajoutée.
Une seconde compilation incrémentale est donc nécessaire (build-essai7-final.log).

## Résultats finaux
Armée : proof_run code0, durée180s, crash0, frames10320, sha5eeed592dba35c6b.
Ablation : code0, durée120s, crash0, frames6836, même sha, FEATURE armed0 hits0.
Wrapper des courses code0 ; builder PID2541075 repris, STAT Ss.
Armée : total4374701=sum(A..E+unaccounted), residual0, rb_checks12720, rb_mismatch0,
lc_orig_light_un1282703, gpu_ms_buckets7.4994 ; 47/672 comparaisons, maxdiff254,
census_coverage_missing237, census_replay_runs0. Ablation : 28/672 comparaisons, maxdiff254.
Les sentinelles désignent des plans incomplets ; aucune validation globale revendiquée.
Contrôle Python après course : sha moteur égale proof ; somme draws égale total ;
les 572 hashes de references-essai7.sha256 restent identiques. Aucun PNG de référence réécrit.

Anomalies moteur conservées : proof-engine.log:9079 GL_INVALID_OPERATION glReadBuffer(GL_FRONT),
:9082 screenshot to clipboard NYI non-Windows, :9084 GL_BACK. Elles surviennent dans le
chemin automatique refset ; aucun screenshot externe ni appréciation visuelle.
Après reprise du daemon, checkpoint automatique 0a589b258c a commité nos quatre fichiers moteur.
Le commit worker suivant ne récupère que le correctif runner/tests et les rapports/preuves.
