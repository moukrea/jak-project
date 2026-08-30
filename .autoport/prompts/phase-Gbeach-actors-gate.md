# Gbeach-actors-gate — les collecteurs d'Eco vert n'apparaissent pas pendant le survol

## Le defaut, signale DEUX FOIS par l'owner

2026-08-28 puis 2026-08-29 :

> « la cinématique qui se déclenche quand on retourne à la hutte du Sage vert après avoir terminé
> Geyser Rock, toujours mes soucis de chargement des collecteurs d'Eco vert (pas chargés pendant
> le fly over, pop-in) parce qu'ils sont pas dans le nouveau Sandover Village mais à Sandover
> beach qui est le niveau juste à côté ! »

**Sa cause est la bonne** : les collecteurs sont dans `beach`, pas dans `village1`.

## LA LIGNE QUI TRANCHE A ETE CAPTUREE — ne pas la rechercher

Mesure du 2026-08-29, phase `Gloading-screen` :

    LOADGATE arm  scene=sage-intro-sequence-e levels=beach timeout=20000ms
    LOADGATE open scene=...                   reason=resident

**`reason=resident`, PAS `timeout`.** Et les dix acteurs sortent `trouve=#f`.

Donc :
- **Le plafond de 20 s est HORS DE CAUSE.** Ne pas le relever : si on le relevait, on allongerait
  l'ecran noir de l'owner sans rien reparer. C'est deja ecrit comme interdit et ca le reste.
- **La barriere attend la GEOMETRIE et la scene a besoin des ACTEURS.** `mark_level_resident`
  (`Loader.cpp:1462`) est publie quand le fr3 du niveau est monte sur le GPU. Rien dans ce signal
  ne dit que les acteurs du niveau sont lies et instanciables.

## Ce que la scene demande, precisement

`goal_src/jak1/levels/village1/sage.gc:109`, `sage-intro-sequence-e` :

    (0   want-levels village1 beach)
    (937 display-level beach movie)
    (937 want-force-vis beach #t)
    (938 alive "ecoventrock-3" ... "ecoventrock-7")     <- les events
    (938 alive "harvester-87"  ... "harvester-91")      <- LES COLLECTEURS

Ce sont des **ACTEURS**, reveilles un par un a la frame 938. La barriere ouvre a la frame 0.

Balayage statique deja fait sur les 179 spool-anim : cette scene EST dans les 18 que
`scene-load-gate!` retient, et elle s'arme bien sur `beach`. **Le mecanisme n'est pas contourne**,
il attend la mauvaise grandeur.

## Le travail

1. **Trouver le signal qui dit qu'un ACTEUR d'un niveau est instanciable**, distinct de la
   residence GPU du decor. Publier son nom et l'endroit ou il est produit.
2. Faire attendre la barriere sur CE signal pour les scenes qui reveillent des acteurs d'un
   niveau voisin, en gardant la residence pour le decor.
3. **Ne pas casser ce qui marche** : la barriere couvre aujourd'hui cinq chemins d'attente et
   l'owner a valide l'ecran de chargement. Publier que les cinq chemins repondent toujours.

## Exige pour fermer

1. Une trace montrant les dix acteurs `trouve=#t` AVANT que la scene ne les reveille — c'est
   l'inverse exact du `trouve=#f` mesure aujourd'hui.
2. La ligne `LOADGATE open scene=sage-intro-sequence-e` avec son motif et son attente.
3. Le plafond de 20 s est INCHANGE. Le prouver.
4. Les cinq chemins d'attente existants sont inchanges.
