# Les acteurs loin de Jak dorment comme sur PS2, et c'est un reglage

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
drawable.gc:1306-1309 ecrit run-time a 0 sur PC (« pour se debarrasser de la compensation de lag ») ; entity.gc:1056-1078 s'en servait pour ramener pause-dist de 220 m a 50 m et birth-max de 25 a 1 sous charge. Un acteur pause est saute entier par le kernel (gkernel.gc:1262-1275). Sur PC pause-dist = 220 m pour toujours (mesure crate-collision : birthmax=25 runtime=0 pausedist=901120) et use-vis? = #f fait naitre tout ce qui est a moins de 220 m, occlus ou non. Entites a moins de 220 m / 50 m : village1 120/18, beach 206/21, jungle 235/26. Chaque acteur actif paie decompression d'animation et cspace par joint en mips2c scalaire, visible ou non.

## Livrable
Un reglage explicite de distance de pause (50/110/220 m, defaut 220 = valeur ND), pousse par pc-set-*! (scalaire, slot par image), epingle dans les proof_env refset (OG_ACTOR_PAUSE_DIST). JAMAIS un frein pilote par run-time (montre murale = rejeux non deterministes, SPEC lumiere 7.3). Le moteur publie actors_active, actors_paused, joints_evaluated par image et actor_pause_defects = (reglage non applique) + (acteur < distance mis en pause) + (refset_replay_maxdiff != 0 a 220 m). Gain publie : goal_busy_ms a 220 vs 50 m sur beach.

## Preuve exigee
`actor_pause_defects == 0` dans `reports/perf-actor-pause-dist/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-actor-pause-dist device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Performance : « distance d'activite des PNJ » 50 / 110 / 220 m ; en jeu, les PNJ lointains ne bougent plus mais restent visibles.

## Hors perimetre
Pas de changement de birth-max ni de use-vis. Un PNJ gele qui n'eclabousse plus est le comportement ND (SPEC eau 5.4). Ne touche a aucune feature validee.
