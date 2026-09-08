DIRECTIVES vb7966a3839
Essai20 : seules les deux lacunes ciel sont recapturées ; rendu et configuration artistique identiques à essai19.
Swamp : start mesuré lot20260908T021311-3567359=(449,84;5,13;-1790,36)m, cap−166,8°. Dock1 level-info.gc:1006=(332,13;1,42;−2006,56)m.
La formule camera_pin refset.cpp:3463 donne, avec20:195:2462:63, caméra≈(333,4;11,43;−2007,3)m. Le warp reste start, la caméra se place près du dock.
Ceci ne prouve ni visibilité GPU du ciel ni absence de crash ; le lot officiel les mesure. Les anciennes demandes start sont remplacées explicitement, y compris les mappings précédents.
Sunkenb : candidate20:90:0:700 fondée sur intersections des background.glb Sunkenb et Sunken ; le rayon central ne touche aucun des deux, contrairement à−18:0:50:700 antérieur.
Ce test géométrique statique ne certifie ni surfaces dynamiques ni pixels visibles. Conservation de helix pour la vue intérieure, remplacement explicite de start70m.
Chaque appel complet et son code de sortie figurent dans campaign-runs.jsonl ; seul proof_run écrit les manifestes et proof.txt.

Diagnostic appareil ultérieur : start élevé n'avait pas chargé sub.VIS, et les captures passent sous LOADSCREEN-SHOW arm6 (lot023227, engine.log:18200/19419/20977). L'acteur exit-chamber-1 est trouvé(:18114) ; aucune preuve de ciel n'en découle.
level.gc:1215-1231/1253 conditionne chargementVIS aux boîtes de caméra ; target-death.gc:178-184 attend all-visible?, masque4 maintenu. L'amorçage helix natif charge sub.VIS dans lot010942(:9857-9863).
Le lot024020 passe donc par helix avantstart, sans masquer écran ni forcerVIS ; les8paireshelix sont rejouées pour cette dépendance de chargement et remplacées explicitement.
Swamp023107 : sig11 dans intern_from_c avantwarp, aucune caméra exercée ; seul retryidentique023556 atteint caméra dockavantSIG11 (swa.VIS chargé, GRV-NULLFG-REPAIR puislibsigchain PC01e751fc, lignes9534-9561).
Ces deux crashs sont conservés comme lots défectueux jusqu'à remplacement explicite qualifié.

Résultat final : lot024020 31sondes/32captures (GL1282 avantstart h00ON) ; lot024828 settle60/load480 26/32, six GL1282 avantsonde. Aucune paire nouvelle qualifiée ; 192 paires antérieures retenues par l’agrégat, 44 lots, 352 erreurs, gate=6.
Incidentcollecteur : éditionconcurrente du script luparbash lors024312,finalisationexit2 ; manifestecrash1 et dixfichiersscellésintacts. Le dernierproof_run024828 a réintégréce lot officiellement ; aucunchampdepreuvecrééàlamain.
Tests du correctifPID : python3 -m pytest .autoport/tests/harness/test_hdr_batches.py -q =>108 passed in41.95s ; bash -n et gitdiff--check0. Huit cas avecfauxadb,aucune preuvejeu.
