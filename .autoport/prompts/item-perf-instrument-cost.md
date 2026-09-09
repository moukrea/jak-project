# Un instrument desarme ne coute rien, et le prouve lui-meme

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
A OFF tout tourne encore : ~120 autoport_proof::publish par image (mutex + string + map) et deux vidages complets vers logcat toutes les 60 images (autoport_proof.cpp:87-158, android_gfx.cpp:791-795) ; npc_flicker::note_draw par paquet merc (mutex + 2 hachages), sonde d'etirement O(os x 16) (Merc2.cpp:2722-2830), TTL HD sur 256 slots x16/img ; lighting_census et shade_proof armes par defaut = 2 mutex par draw ; recensement vent toutes les 300 images (copie de toutes les instances, FFT, mutex) sans regarder enabled() ; maybe-spawn-jak-hd! parcourt l'arbre des process avec 4 string= par drawable avant de lire le drapeau (jak-hd.gc:3391-3402) ; 32 intern_from_c par image (gk_android_main.cpp:812-843) ; a36_tree_scan_per_frame a chaque syncv (:3565-3780).

## Livrable
Chaque instrument est un no-op quand armed_for() est faux, avec UNE lecture de l'etat par image (jamais par draw) ; publish/flush regroupes en une emission par 60 images sans vidage double ; gpu_ms_* reste compile ; chaque instrument publie son propre instrument_cost_us. instrument_cost_us_per_frame = somme mesuree tous instruments desarmes. Un binaire temoin AUTOPORT_INSTRUMENTS=0 sert UNIQUEMENT a chiffrer le residu (publie a cote), jamais a livrer : toutes les portes des refontes sont des cles autoport_proof (SPEC lumiere 7.1).

## Preuve exigee
`instrument_cost_us_per_frame <= 200` dans `reports/perf-instrument-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-instrument-cost device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel.

## Hors perimetre
Aucun instrument de spec supprime ; le vent natif shrub est une feature validee, pas un instrument. Ne touche a aucune feature validee.
