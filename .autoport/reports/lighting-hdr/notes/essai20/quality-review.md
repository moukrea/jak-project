# Essai20 — revue quantitative hors appareil
DIRECTIVES vb7966a3839
Verdict : les données existantes ne justifient pas un changement global déterminé de courbe/exposition ; elles orientent vers des résidus par niveau/heure à investiguer, sans prouver leur cause ni une calibration locale précise.

Sources : `batches/essai19-current/measurements.json`, `notes/essai19/summary.json` (relatifs à `reports/lighting-hdr/`) ; contrat SPEC-refonte-lumiere.md §4.5.
Méthode : lecture JSON par Python 3, différences ON−OFF, moyenne des vues dans chaque cellule (niveau,heure), puis poids égal des 168 cellules = 21 niveaux × 8 heures ; 192 paires qualifiées, chacune 57 600 pixels.
Les agrégats suivants reprennent `balanced_deltas` et ont été recalculés ; aucun test existant, build, appareil, validateur ou production de preuve n'a été lancé.
Moyennes équilibrées : luma +3.866833819031085 ; saturation +0.0007643610926049995 ; aplats +0.008921326538356013 ; gradient +0.16341433641809283.
La luma augmente dans 81 cellules et baisse dans 87 ; saturation + dans 95/− dans 73 ; aplats + dans 112/− dans 56.
Luma moyenne par heure, chaque niveau de même poids (arrondi 6 décimales) : 00 +4.827327 ; 03 +6.745720 ; 06 +9.118392 ; 09 +0.094678 ; 12 −1.838758 ; 15 +1.258526 ; 18 +4.017364 ; 21 +6.711421.
Luma moyenne par niveau, chaque heure de même poids : ogre +20.740182291666667, rolling +19.529385850694446 ; swamp −6.126312934027779, maincave −5.13554253472222, lavatube −4.099355468749999.
Ces signes opposés rendent injustifiée une correction d'exposition uniforme déduite de la seule moyenne ; ils ne démontrent pas qu'aucune autre courbe globale ne pourrait améliorer le résultat.

Blanc = trois canaux à 255 ; quasi-blanc = trois canaux >=245 ; écrêtage = au moins un canal à 255 (définitions existantes, aucun seuil ajouté).
Sur les 192 paires, sommes descriptives OFF→ON : blancs 4770→0 ; quasi-blancs 8250→1632 ; écrêtage d'au moins un canal 246183→83877. Ces sommes ne sont pas équilibrées par niveau/heure.
Aucune paire qualifiée n'augmente les blancs ou quasi-blancs ; plus grand nombre ON de quasi-blancs : village1-out h09, 2264→733 pixels ; plus grande baisse de blancs : village1-out h15, 1402→0.
Résidu d'écrêtage maximal ON : beach-start h12, 21975→15543 pixels ; plus forte hausse : citadel-start h21, 75→118 (+43). L'absence de RGB255 ne prouve donc pas l'absence d'écrêtage coloré ni de ciel délavé.
Couleur : distance entre histogrammes de teinte normalisés (demi-L1, pas un angle) maximale beach-start h12 = 0.36024044763616164, puis training-start h12 = 0.2930251339249499, village1-out h12 = 0.2519337457591382.
Ces trois vues de midi associent baisse de luma (−13.311649305555562, −10.972743055555554, −9.569375000000008) et hausse des aplats (+0.08952557748550813, +0.091592091206809, +0.005043694506225813), sans hausse des quasi-blancs.
Saturation : pire baisse village1/legacy h00, 0.6193408046908775→0.5801626235556913 (−0.03917818113518623) ; plus forte hausse misty-start h15, +0.019556622892347608.
Luma : plus forte hausse ogre-start h18, 68.40003472222222→106.03013888888889 (+37.63010416666667, ratio 1.5501474424608908) ; plus forte baisse village1/legacy h12, 90.9335763888889→74.74590277777777 (−16.187673611111123).
Aplats : plus forte hausse ogre-start h12, 0.13766834206055936→0.2515367506698657 (+0.11386840860930633), avec luma +19.511631944444446 ; plus forte baisse finalboss-start h12, −0.07548028931192097.
Le gradient moyen reste un diagnostic ; sa hausse globale ou sa baisse locale ne prouve ni gain ni perte de détail, conformément à l'arbitrage du 8 septembre.

Limites : `quality_bad=[]` n'est pas une validation artistique ; 8 erreurs sunkenb-start (captures noires/achromatiques et ciel non expliqué) persistent dans l'agrégat.
`missing`, `interior_missing`, `hut_missing` sont vides, mais `sky_missing` contient sunkenb et swamp à chacune des 8 heures : ciel non jugé dans ces 16 cellules malgré la couverture de niveau.
Les métriques décrivent des images entières de vues compatibles, sans segmentation de surfaces/ciels ; elles ne permettent pas d'attribuer leurs dérives à une matière ou région précise ni d'isoler le tone map des autres différences d'éclairage ON/OFF.
Priorités d'investigation résiduelle : beach/training/village1 à midi (couleur), ogre/rolling (luma), ogre à midi et beach/training (aplats), village1/legacy de nuit (saturation).
Non prouvé : disparition des défauts signalés par l'owner, qualité des régions non couvertes, correction locale à appliquer, pertinence sur écran HDR réel et coût GPU. Aucun nouveau seuil, aucune identité ON/OFF, aucune preuve verte fabriquée.
