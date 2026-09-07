# Diagnostic borné — essai 8
DIRECTIVES v6fca51fe40

## Ciel : constat conservé
Le log de capture historique est `.autoport/refset/refset-capture.log` (pas sous reports).
Lignes 1233150–1233151 : helix h09/h21 = 0‰ ; start huit heures = 0‰.
Ligne 1233165 : huit couples manquants, tous sunkenb.
Poses moteur : ligne 510640, start y=-249.00 ; ligne 577963, helix y=-448.97.
`level-info.gc:887–943` déclare sky=#t et ces deux continue-points seulement.
`sun-exit-chamber.gc:571–582` passe à sunken/village2 avant l'émersion ;
`718–729` recharge sunken/sunkenb après la plongée.
Un extérieur village2 ne qualifie donc pas sunkenb. Aucun autre cadrage validé trouvé.
La sonde de profondeur ne nomme pas l'occulteur ; absence générale de ciel non prouvée.

## Rejeux : défaut avant la fin du plan
L'essai7 interrompu (`notes/essai7-interrompu-engine.log:9076`) et sa preuve finale
(`proof-engine.log` archivé par le tester, ancienne ligne 9083) ont tous deux
`REFSET cmp origine/h00 maxdiff=202 diffpx=794`.
Les huit couples (maxdiff,diffpx) ORIGINE-TOTAL sont égaux entre ces deux courses ;
idem ORIGINE-LUMIÈRE (h00=200/716 et h21=201/813).
Cela ne prouve ni l'identité des pixels différents ni la cause de leur différence.
Les anciens diagnostics STOCK/ENHANCED du README concernaient d'autres écarts.
La sentinelle finale 254 ne signifie pas que les comparaisons déjà exécutées valent zéro.

## Coût et couverture
Calcul du plan, pas une nouvelle mesure : 672×180 frames de stabilisation,
27×600 frames de chargement et premier warp à 600 donnent au moins 137760 frames.
À 60 frames/s : 2296 s, soit 38 min 16 s par tour, avant surcoûts.
Les horloges vent/herbe utilisent la frame logique ; raccourcir le settle change les images.
`OG_UNCAP_FPS` existe, mais change aussi `uncap::scene_vblank_hz` : ce n'est pas
une simple suppression d'attente. Accélération bit-identique non établie.
Le plan à 672 étapes ajoute 108 images à la dernière capture de 564 :
100 absentes et 8 présentes sans provenance dans cette capture (listes essai7 conservées).
Un rejeu ne remplit pas ces trous. Aucune tournée complète supplémentaire lancée.

## Corrections
Capture interne non MSAA : GL_COLOR_ATTACHMENT0 remplace GL_FRONT sur le FBO.
Chaque GL_READ_BUFFER est restauré pendant que son framebuffer est lié.
Le moteur réserve un répertoire capture neuf, refuse un existant et conserve les références.
Le lanceur prépare désormais un candidat neuf ; REFSET_DIR permet sa sélection en replay.
Ni adoption automatique, ni recapture sur place, ni changement de shader/caméra/porte.
Les vérifications exécutées et leurs limites sont dans le compte rendu du tester.
