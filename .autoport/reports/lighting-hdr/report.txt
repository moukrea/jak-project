DIRECTIVES vb7966a3839
Non validé : hdr_tonemap_defects=6 ; les ciels Sunkenb/Swamp et les lots crashés restent non couverts.
Correction livrée : proof_run collecte immédiatement un lot HDR dont le PID connu disparaît/change ; une erreur adb ne déclare pas un crash.
Tests : 108 réussis dans test_hdr_batches.py, dont huit cas de surveillance PID ; bash -n et diff --check réussis. Tests synthétiques, pas preuve jeu.
Moteur 810a60f430 inchangé ; aucun réglage artistique, build ou nouvel APK dans cet essai.
Bibliothèque build/appareil MD5 4d5024c55ede04ab75430e22d1d3c324 ; SHA256 2e6a7759c45543b4a98ffd0cdcb9e07c6ce6d75ef71320dbf682855814516316.
Six lots ciblés ajoutés par proof_run, sans rejouer les 21 niveaux ; aucune nouvelle paire qualifiée, les 192 antérieures sont conservées.
Huit lignes de proof.txt, produit le 2026-09-08T02:48:25Z, durée 189 s :
```text
serial=eae4df44
crash=0
frames=4080
FEATURE lighting-hdr armed=1 hits=704154
hdr_batch_pairs=192
hdr_batch_missing=16
hdr_batch_errors=352
hdr_tonemap_defects=6
```
Couverture conservée : 44 lots, 168/168 cellules, 21/21 niveaux ; intérieurs requis et hutte complets ; 16 cellules ciel manquantes.
Les 352 erreurs comprennent remplacements refusés, doublons, demandes non qualifiées et trois crashs non remplacés ; aucun effacement de lot.
Swamp : premier SIG11 dans intern_from_c avant warp ; arrivée près du dock puis amorçage cave1 échouent avec GRV-NULLFG et PC GOAL 01e751fc.
Sunkenb : la caméra élevée bloquait sub.VIS et maintenait LOADSCREEN-SHOW ; amorcer Helix natif charge réellement la VIS.
Après amorçage : 32 captures colorées/31 sondes ; attente prolongée : 32 captures/26 sondes, six GL1282 avant sonde. Remplacements refusés.
Le dernier run est sans crash ; les trois autres crashs demeurent dans le verdict global. Les groupes de chaîne passent au rouge faute de mesures dans ces lots.
Ce rouge ne démontre pas une régression du tone map : aucune modification du rendu ; origine des GL1282 et des crashs non résolue.
Incident de travail : édition du collecteur pendant sa lecture, finalisation Swamp interrompue ; manifeste brut conservé, intégré par le dernier proof_run officiel.
Courbe Fidélité 0, exposition 1, genou 0,95 conservés. Mesures retenues : luma équilibrée +3,8668/255, signes opposés dans 81/87 cellules ; quality_bad=0.
Pires diagnostics : Ogre h18 luma +55 %, Beach h12 distance d’histogrammes de teinte 0,360 ; cela ne justifie pas une correction globale précise.
À regarder : Options > Recharged, Fidélité ; ciels/zones lumineuses, Beach et hutte à midi, Rolling et Ogre. Aucun nouveau résultat artistique livré ici.
non prouvé : ciels manquants, correction artistique/résidus locaux, origine des GL1282, résolution des crashs et tous les acquis.
non prouvé : ordre/identité GPU, Filmique 1, coût GPU, sortie écran HDR native et détection précoce de crash sur appareil avec le nouveau collecteur.
Redmi relancé normalement PID 18928 ; zéro propriété debug.opengoal non vide, aucun verrou de déploiement.
Validateur réservé à l’orchestrateur, non lancé ; aucun owner-ok ni changement du backlog par ce worker. Détails et commandes : notes/essai20/.
