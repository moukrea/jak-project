DIRECTIVES v6133a247b4
Verdict : correctif partiel livré sur le Redmi ; HDR NON VALIDÉ, hdr_tonemap_defects=4.
Les shaders Sprite3 bornent la couleur source après texture et avant mélange ; accumulation HDR et tone map unique conservés.
Préparation temporelle : second téléport supprimé, purge par bras/heure, ancre explicite par séquence, âge contrôlé avant écriture.
Attribution étendue à lightning3/hotdot/bigpuff/starflash ; ces deux dernières couches restent sans témoin attribué.
Le helper vérifie âges/dates de purge, distingue date et réglage, et retire le faux rattachement legacy=hutte ; critères qualité inchangés.
Build incrémental/repack/install réussis ; lib build/APK/Redmi SHA256 008b1f81b596f3593cdd0db00fbbc56de1734f9b62ecc47112801d9ef2f3a480.
Tests hors jeu : 171 tests harnais passent ; 48 contrôles GPU passent (SDR identique sur cas testés, accumulation >1, alpha conservé).
Huit lignes recopiées de proof.txt, produit exclusivement par proof_run.sh :
```
source=device
sha=008b1f81b596f359
crash=0
frames=1260
tonemap_draws=389
tonemap_sites=1
hdr_owner_regressions_failed=1
hdr_tonemap_defects=4
```
Lot livré : essai26-source-color/20260908T070411-3795215 ; 24 captures, quatre purges, âges11/23/35/47/59/71, slip0.
Recalcul officiel sans nouveau run : errors0/pairs2/quality_bad1 ; owner measured1/failed1/missing4/passed0 ; sources brutes inchangées.
Comparaison premier bras ON12 avant/après source, ROI10012 commune : clipped moyen2269.5→2095.67 ; blancs62.5→59.67. Ce progrès ne valide pas le rendu.
Échec restant : clipped à12h (excès global181 après tolérance), pertes de blancs10012 à18h (ON14.83/OFF65.5). Quatre observations éco échouent.
Les deux runs échoués du cycle précédent restent conservés : SIGSEGV GOAL avant capture puis erreur introduite de purge interséquence, corrigée sur le lot livré.
À regarder par l'owner, Options > Recharged : éclairs éco, blancs des nuages, éclat du soleil couchant, sol devant vraie hutte Sage vert et portail.
non prouvé : correction complète des cinq régressions, attribution bigpuff/starflash, régions nuages/soleil/sol/portail, couverture21niveaux×8h/vraie hutte, tous acquis et HDR natif.
Pas de nouvelle variante de courbe sans diagnostic ; campagne complète non lancée car corrections ciblées encore rouges. Aucun owner-ok ni validateur touché/lancé.
Notes et sources avant/après : notes/essai26/ ; suite détaillée dans handoff.md.
Redmi restauré normal : PID14441 stable12s, A35-RENDER frame360/draws70 ; propriétés debug vides et verrou absent (notes/essai26/normal-restoration.json).
