# Ggrass-crash — L'HERBE FAIT PLANTER LE JEU. Bissection faite par l'owner.

Retour et bissection de l'owner : `.autoport/reports/Gloadgate-crash-regression/owner-bisection.txt`.
Ses questions sur le menu : `.autoport/reports/Gloadgate-crash-regression/owner-menu-questions.txt`.

## L'owner a fait le plan d'experience que nous n'avions pas fait
Toutes les options Recharged eteintes : pas de plantage. Reactivees UNE PAR UNE :
l'HERBE seule fait basculer. C'est causal et c'est propre. Nos deux suspects (ecran de
chargement, pas de temps fixe) tombent. Et cela explique nos non-reproductions : nos
courses tournent avec la configuration PAR DEFAUT, sans l'herbe telle qu'il l'active.
=> TOUTE course de reproduction doit desormais activer l'herbe explicitement.

## Faits deja etablis par le superviseur (verifies, a ne pas re-deriver)
1. Le pack livre `jak1_hd_assets.zip` contient 14 fichiers : 3 fr3 « enhanced »
   (GAME, village1, village2) et 11 squelettes HD. Il ne contient AUCUN `.grassbake`.
   Le pre-calcul d'herbe n'arrive donc JAMAIS sur l'appareil.
2. Localement, `village1.grassbake` fait 64 octets (vide en pratique) contre 1,4 Mo pour
   beach et 2,0 Mo pour training. C'est deja le cas dans la sauvegarde de juillet.
3. `GrassRenderer.cpp` (~ligne 700) invalide le bake si `loaded.fr3_size != cur_fr3` et
   bascule alors sur le placement EN DIRECT (« PRECOMPUTED unavailable -> LIVE fallback »).
   Or le pack livre REMPLACE `village1.fr3` par la version enhanced : la taille change,
   donc le bake serait invalide meme s'il etait livre.
=> Hypothese principale : sur l'appareil, l'herbe est TOUJOURS placee en direct, chemin
   lourd, et c'est la que le jeu meurt. A CONFIRMER PAR LA MESURE, pas a presupposer.

## Ordre de travail
1. Reproduire AVEC L'HERBE ACTIVEE — x86 d'abord, puis Redmi eae4df44.
   La Shield est INTERDITE (television de l'owner).
2. Publier la ligne « PRECOMPUTED unavailable (<raison>) -> LIVE fallback » telle qu'elle
   sort sur l'appareil : la RAISON exacte nomme la cause.
3. Trace complete du plantage : signal, pile, fil.
4. Corriger. Deux directions possibles, choisir sur mesure :
   soit livrer un bake VALIDE pour les fr3 enhanced (et le mettre dans le pack),
   soit rendre le chemin direct sur non plantant.
5. Prouver : >= 10 cycles avec l'herbe activee, zero plantage, sur x86 ET Redmi.

## Format des marqueurs
    RESULT: GRASS NO CRASH
    GRASSREPRO plateforme=<x86|redmi> herbe=<on|off> tentatives=<n> plantages=<n>
    GRASSFALLBACK niveau=<nom> from_bake=<0|1> raison=<...>
    GRASSTRACE signal=<...> fil=<...> frame0=<...>
    GRASSPACK bakes_dans_le_pack=<n> tailles=<...>
    GRASSOK plateforme=<x86|redmi> cycles=<n> plantages=0
Verifie : au moins une GRASSREPRO avec herbe=on ET plantages>=1 (sans reproduction, rien
n'est prouve) ; une GRASSREPRO avec herbe=off pour le controle negatif ; GRASSFALLBACK
avec sa raison ; GRASSOK >= 10 cycles et 0 plantage sur x86 au minimum.
