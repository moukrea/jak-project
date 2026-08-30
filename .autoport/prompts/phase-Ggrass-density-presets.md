# Ggrass-density-presets — cinq paliers de densite pre-calcules, plus de chemin direct

Demande owner mot pour mot : `.autoport/reports/Ggrass-density-presets/owner-request.txt`.

## Objectif
Remplacer le curseur continu de densite d'herbe par CINQ paliers nommes (very low, low,
medium, high, very high), chacun avec son propre pre-calcul livre. Le placement EN DIRECT
ne doit plus jamais etre emprunte en jeu.

## Pourquoi
Le repli en direct est declenche par « density slider above bake density ». Mesure :
735 Mo de pointe avec pre-calcul contre 1 207 Mo en direct, et c'est sur le chemin direct
que les deux morts ont ete reproduites sur le Redmi. Cinq paliers pre-calcules suppriment
la condition par CONSTRUCTION.

## Contraintes mesurees
- `kGrassLevels` declare `training` ET `beach`, MAIS la plage ne place jamais un brin :
  sur les courses de test, `niveau=beach` sort 300 fois contre 13 pour `training`, et les
  26 placements enregistres concernent TOUS `training`. L'owner (2026-08-30) : « sur la
  plage [...] ca n'a jamais ete visible, tu peux completement dismiss ».
  => 5 paliers x 1 niveau = 5 bakes, < 10 Mo.
  => AVANT de retirer `beach` de `kGrassLevels`, publier ce qu'elle coutait reellement
     (brins, temps, memoire par chargement) : on doit savoir si on supprime du VIDE ou du
     GACHIS paye a chaque chargement du niveau le plus visite du jeu. Puis prouver par un
     avant/apres que chargement et memoire de la plage ne montent pas.
- Le pack livre contient aujourd'hui ZERO `.grassbake`. Les livrer fait partie du chantier.
- Le bake est invalide si `loaded.fr3_size != cur_fr3`. Regenerer les bakes CONTRE LES fr3
  REELLEMENT LIVRES (versions enhanced du pack), sinon ils seront rejetes a l'arrivee.

## Preuve exigee
    GRASSPRESET palier=<very-low|low|medium|high|very-high> niveau=<training|beach> bake_octets=<n> fr3_size=<n>
    GRASSLIVE courses=<n> basculements_en_direct=<n>
    GRASSMEM palier=<...> rss_max_mo=<f>
    GRASSPACK bakes_dans_le_pack=<n>
Verifie : 10 lignes GRASSPRESET (5 paliers x 2 niveaux) ; `basculements_en_direct` == 0 sur
au moins 10 courses couvrant LES CINQ paliers ; GRASSPACK == 10 ; et le pic memoire de
chaque palier reste sous celui mesure en direct (1 207 Mo).
