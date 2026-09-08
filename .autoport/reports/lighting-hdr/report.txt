DIRECTIVES va841fb32b6
Correction alpha partielle livrée sur Redmi ; critère non atteint (hdr_tonemap_defects=4), cinq régressions owner non validées.
Dix-neuf shaders bornent leur alpha après les tests ; trois mélanges soustractifs restaurent l’alpha zéro du chemin normalisé. RGB HDR et courbe inchangés.
La garde du producteur officiel compte désormais les cinq cas régionaux absents, en mode ordinaire et par lots ; aucun validateur modifié.
Build incrémental gk + repack réussi ; MD5 build/APK/Redmi b5fcc76756a9d12bd1cc40875bd3b0a4 (notes/essai22/build-deploy.log).
Test GPU Mesa des shaders réels : alpha2,00781→1, RGB2,5/3/4 conservé, RGBA8 identique dans les cas testés, failures=0 (notes/essai22/alpha_gpu.log).
Tests harnais : 120 passed ; bash -n et diff --check des sources réussis. Ces tests hors appareil ne prouvent pas les cinq cas jeu.
Huit lignes exactes de proof.txt, run officiel 157 s :
```text
serial=eae4df44
crash=0
frames=1200
FEATURE lighting-hdr armed=1 hits=672253
tonemap_sites=1
hdr_batch_pairs=4
hdr_owner_regressions_missing=5
hdr_tonemap_defects=4
```
Lot APRÈS : batches/essai22-alpha/20260908T052020-3705704 ; zéro erreur de lot, quatre paires, deux cellules niveau/heure.
A42 : huit lectures float alpha∈[0,1], sans attribution matière ; aucun LOADSCREEN-SHOW dans le run (notes/essai22/after-analysis.json).
Lot AVANT conservé : essai22-before/20260908T051058-3695478, captures noires/achromatiques pendant chargement ; deux paires refusées.
L’ancien parcours legacy puis extérieur produit les captures APRÈS ; l’arrivée directe en extérieur reste non corrigée.
Comparaison diagnostique avec les quatre paires essai21 correspondantes conservée dans notes/essai22/after-analysis.json, sans identité de frame exigée.
À regarder dans Options > Recharged : blancs des nuages, éclairs éco bleue, éclat du soleil couchant, sol devant la hutte, couleur/blancs du warp gate.
non prouvé : correction de ces cinq régions, blancs attendus préservés, attribution du violet, séquence éco ; aucun zéro qualité revendiqué.
non prouvé : équilibre21niveaux/8h du nouveau binaire, tous acquis, alpha après tous les modes accumulatifs, sortie HDR native.
Les anciens lots restent diagnostiques, incompatibles avec la nouvelle bibliothèque ; la campagne complète n’a pas été relancée avant résolution des cinq cas prioritaires.
Redmi relancé sans propriétés debug persistantes ni verrou ; generic reste à l’orchestrateur, aucun owner-ok écrit.
