DIRECTIVES vb7966a3839
# Essai 21 — revue quantitative des lots compatibles
Source : .autoport/reports/lighting-hdr/batches/essai21-readback/measurements.json ; SHA256 f7f6772d4157b8a7cba238a6d83a3ba2d742eb3936306d05d98eb8d5041790a3.
200 paires, 25 vues, 168 cellules = 21 niveaux × 8 heures. Différences ON−OFF ; moyenne des vues dans chaque cellule, puis poids égal des cellules. Mesures ImageMagick existantes ; aucun nouveau seuil ni preuve visuelle.
Les listes errors, missing, sky_missing, interior_missing, hut_missing et quality_bad sont vides dans cet agrégat.
Moyennes équilibrées : {"detail": 0.15975071531563528, "flat": 0.01004183481066548, "luma": 4.603167576058201, "saturation": 0.00039646011727395396}.
Signes par cellule : {"luma": {"positive": 94, "negative": 74}, "saturation": {"positive": 97, "negative": 71}, "flat": {"positive": 109, "negative": 59}, "detail": {"positive": 90, "negative": 78}}.
Blanc = trois canaux à 255 ; quasi-blanc = trois canaux >=245 ; écrêtage = au moins un canal à 255.
Sommes descriptives OFF/ON, sans pondération : {"white": {"off": 6719, "on": 0}, "nearwhite": {"off": 12084, "on": 2650}, "clipped": {"off": 274581, "on": 88266}}.
Proportions de pixels équilibrées par cellule : {"white": {"off": 0.00037352223875661376, "on": 0.0}, "nearwhite": {"off": 0.0006830253802910053, "on": 0.0001459160052910053}, "clipped": {"off": 0.022709625082671957, "on": 0.007675212880291005}}.
luma min : 20260908T032334-3635041/legacy h12 : 90.932048611 → 74.745503472, delta -16.186545139.
luma max : 20260908T035912-3673185/ogre-start h18 : 68.399826389 → 106.030121528, delta +37.630295139.
saturation min : 20260908T032334-3635041/legacy h00 : 0.619305968 → 0.580150921, delta -0.039155047.
saturation max : 20260908T032933-3642700/misty-start h15 : 0.338300880 → 0.357850161, delta +0.019549281.
flat min : 20260908T031529-3628144/sunkenb-helix h21 : 0.152659323 → 0.070576697, delta -0.082082626.
flat max : 20260908T035912-3673185/ogre-start h12 : 0.137668342 → 0.251536751, delta +0.113868409.
detail min : 20260908T032532-3637139/beach-start h09 : 12.523510972 → 10.497451884, delta -2.026059088.
detail max : 20260908T034633-3663552/village2-start h12 : 9.963345651 → 14.433687676, delta +4.470342026.
Écrêtage ON maximal : 20260908T032532-3637139/beach-start h12, 21966 → 15545 pixels ; luma 101.866233 → 88.547049.
Couleur : distance demi-L1 entre histogrammes normalisés de teinte maximale 0.360032120 : 20260908T032532-3637139/beach-start h12. Ce n’est pas un angle ni une cible d’identité ON/OFF.
Décision : conserver Fidélité 0, exposition 1, genou 0,95. Les signes de luma opposés et les différences de couleur/aplats ne déterminent pas une correction uniforme ; aucune calibration locale inventée.
Les nombres nuls de blancs ne prouvent ni absence de ciel délavé ni absence d’écrêtage coloré. Les métriques portent sur l’image entière et ne localisent pas la matière responsable. Le gradient et le contraste restent diagnostiques.
À examiner dans le jeu : Beach et Training à midi, hutte et extérieur Sandover, Ogre/Rolling, les ciels Swamp et Sunkenb ; zones lumineuses et détails des ombres.
non prouvé : satisfaction artistique du défaut owner, correction locale à appliquer, ordre/identité GPU complet, Filmique 1, coût GPU et sortie HDR native. Le compteur nul n’est pas une validation owner.
