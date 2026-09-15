DIRECTIVES v775512c234
## ÉTABLI
Essai11 : candidat partiel compilé, shader ca400d609b07cfc5, libgk d661208db0ec9150.
Aucun appareil touché, aucune course ni preuve neuve ; budgets9/9 et6/6 clos ; porte non passée.
Reconstruction concave après flou, moyennes AO filtrée±1/2 ; ancien ridge et flou préservés.
Gardes ciel, convexité immédiate et profondeur cumulative2% ; critères sonde inchangés.
Même pilote Intel/Mesa,425pixels/15contacts figés bras3 : SSAO12/max3→0, HBAO2/max1→0, GTAO7/max2→0.
29côtésvalides SSAO/GTAO ; HBAO28valides+1censuré ;1manquant conservé dans chaque mode.
Zéro uniquement préfixe contact : pic intérieur subsiste au mur100,550, SSAO[133,138,135,133,131,130].
GTAO[160,165,162,160,159,158], HBAO[160,164,162,161,160,160] : correction complète NON établie.
GLES/GLSL410 compile+lien0 ;16×480000pixels synthétiques identiques, phases4x4 range0.
Build arm64 incrémental0, source exacte testée et embarquée ; pas APK, pas déploiement.
## TENTÉ
Minimum voisins sans moyenne :2profils censurés ; minimum fenêtres dans flou :HBAO empire ; rejetés.
Stencil3 :4profils censurés par mode ; rejeté, archives conservées.
Stencil2 retenu PARTIEL : fixe premier pixel sans supprimer pic+1 ; zéro natif pas défendu comme succès.
Revue géométrie : gardes convexité immédiate et écart cumulé ajoutées au candidat final, rejeu/tests repassés.
## RESTE
Reprendre notes/attempt11-summary.md, attempt11-delivery.json et attempt11-delivered/summary.json.
Traiter le pic secondaire sans élargir arbitrairement masque ni réinjecter AO brut ; préserver phases/damier/shrubs.
Lecteur actuel compte un préfixe depuis contact : ne prouve pas absence de pic après premier pixel sombre.
Conserver1manquant et1HBAOcensuré ; ne pas les transformer en zéros. Équivalence locale ne vaut pas appareil.
Rejeux prêts : attempt11-replay.py --shader CHEMIN --output notes/attempt11-NOM (chemin complet).
Tests : attempt11-run-invariants.py ; commandes exactes dans attempt11-delivered-invariants/commands.md.
Contrat complet couleur/troisvues/stabilité/somme finale reste non prouvé ; aucune validation owner.
Aucune nouvelle course autorisée dans cette reprise ; FINDINGS conserve les limites et coûts non mesurés.
