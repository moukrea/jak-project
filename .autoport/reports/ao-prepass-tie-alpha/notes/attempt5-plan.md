DIRECTIVES v775512c234

Campagne autorisée du 14 septembre : neuf courses au total, aucune déjà consommée
au début de cet essai. Identité prévue : tie-alpha-20260914-attempt5.
Chaque lancement et son résultat seront consignés dans campaign-runs.jsonl.
Le validateur est réservé à l'orchestrateur.

Par vue : ON référence native avec shader de mesure antérieur, OFF corrigé avec
comparaison couleur, ON corrigé avec comparaison native et couleur. L'ordre garde
la référence native disponible (OFF ne la lit pas) et livre l'agrégat dans proof.txt.
Les trois courses emploient le même binaire et les mêmes entrées de scène.
La sélection du shader antérieur ne change que le retour alpha de la mesure.

Positions préparées :
- village1-hut : reprise village1-hut, position -116 14 40 mètres, caméra normale.
- village1-out : reprise village1-hut, position -126 46 212 mètres, caméra normale.
  Cette vue reprend la position de l'alias refset, pas sa caméra haute particulière.
- beach : reprise beach-start, position et caméra natives du continue-point
  (Jak : -504960.22, 9477.325, -223513.81 unités GOAL).
Population prévue dans chaque vue : TIE statique TieCategory::NORMAL.
Les populations réellement observées doivent être non vides ; aucun nombre de
pixels nouveau n'est supposé avant sa mesure. village1 et beach restent chargés.

Instrumentation ajoutée uniquement dans le moteur : lecture couleur native au tick
1400, après les acquisitions statiques inchangées 1200 à 1353 ; AO éteinte pendant
ce seul échantillon. Comparaison exacte de couleur et masque TIE visible, références
identifiées par campagne, vue, binaire, dimensions et tick.
L'agrégateur conserve les termes de chaque vue et pénalise toute mesure manquante.
Limite annoncée : le masque TIE mesure les fragments finaux visibles par pixel,
pas tous les fragments superposés rejetés/écrasés pendant les draws.

Build incrémental arm64 et repack seulement après toutes les éditions ; TMPDIR
dans notes/tmp-build pour éviter le quota /tmp déjà établi à l'essai 1.
Timeout CLI prévu : 125 s ; durée totale réelle consignée sans la tronquer.

Après course07 : beach référence termine à 1380 images, avant le tick couleur1400.
Le bras08 était déjà lancé à125s. Le helper impose désormais135s pour beach ;
seul le bras09 restant en bénéficiera. Aucun bras répété, aucune référence fabriquée.
