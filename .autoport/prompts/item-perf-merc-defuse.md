# Le fil de rendu n'attend plus le GPU au milieu de chaque image

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Merc2.cpp:4470-4527 (#ifdef __ANDROID__, contournement F1a/F1d) mappe en LECTURE 16 octets de l'IBO puis du VBO merc, par niveau et par image, pour eviter un SIGSEGV dans libGLESv2_adreno au premier draw d'un niveau televerse par tranches glBufferSubData (LoaderStages.cpp:1697-1726). Un map READ sans UNSYNCHRONIZED est une barriere : le pilote attend que tout ce qui reference le tampon soit fini, donc l'image precedente entiere. Mesure : 19,4 ms medians, 52 ms max, 0 draw (A35-PERF, framerate-uncap essai 4). 5 ms en juillet. Rien ne prouve que la faute existe encore sur le build actuel (les runs 16-19 precedent la refonte du loader).

## Livrable
merc_defuse_maps_per_frame == 0 en regime, ET 0 SIGSEGV sur une traversee village1 -> misty -> beach -> jungle repetee 3 fois sur l'appareil (merc_defuse_defects = maps par image > 0, ou plantage, ou refset_replay_maxdiff != 0). Par risque croissant, s'arreter au premier qui tient : A/B par prop du bloc ; map unique par (niveau, load_id) au chargement ; glCopyBufferSubData 16 o vers un scratch (commande GPU) ; televersement en un seul glBufferData ; EXT_buffer_storage. Le defuse par image reste derriere une prop comme filet. Publier la cause retenue.

## Preuve exigee
`merc_defuse_defects == 0` dans `reports/perf-merc-defuse/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-merc-defuse device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la cadence en jeu ; et le jeu ne plante pas en entrant dans misty, beach, jungle depuis village1.

## Hors perimetre
Pas de changement de shading merc (lighting-shadows et lighting-actors viennent apres et reutilisent le meme VAO). Ne touche a aucune feature validee.
