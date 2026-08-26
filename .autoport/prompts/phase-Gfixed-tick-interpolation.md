# PAS DE TEMPS FIXE + INTERPOLATION DE RENDU, CONTRE LA REFERENCE D'ORIGINE

Chantier de fond demande par l'owner le 2026-08-26.

## La demande (verbatim)

« quand le jeu va en dessous de ce qu'il est sensé tourner sur PS2, les sauts, les mouvements de
caméra, etc etc ça chie un peu dans la colle et ça casse le gameplay (skips, camera jumps, sauts
trop courts...) je sais qu'OpenGoal a déjà du travail pour ça, mais j'ai l'impression que c'est pas
bon [...] On devrait en fait faire de l'interpolation VERSUS l'original histoire de mitiger tous les
problèmes sans tout casser. »

« Ça permettrait de tourner sans réel souci à des framerates inférieurs (imaginons qu'on aille all
in avec les settings PBR, realtime lighting, grass etc etc... mais que ça permette que de maintenir
un framerate à 25FPS sur le device concerné, faudrait pas que ça casse le gameplay ni le confort de
jeu) et dans l'autre sens, imaginons qu'on puisse aller au delà de 60FPS (75, 90, 120, etc...
variable bien sûr)... Je sais que OpenGoal a déjà un truc pour 120FPS... Mais pareil, c'est pas bon,
ça bénéficierait tout autant de l'interpolation au lieu de hacks spécifiques, puis en plus ça
s'adapterait aux variations de framerate de façon bien plus souple ! »

## Ce que le moteur fait AUJOURD'HUI (constate dans l'arbre, 2026-08-26)

- **Pas de temps variable, applique partout dans la logique de jeu.** Le code GOAL multiplie chaque
  increment par `(seconds-per-frame)` : `powerups.gc:470`, `settings.gc:159/164/167/170/223`, et des
  centaines d'autres sites. La simulation avance donc d'un pas PROPORTIONNEL au temps de frame reel.
- `target-fps` (`pckernel-h.gc:134`), `set-frame-rate!` (`:259`), et cote natif `gfx.h:98
  target_fps = 60`, `common/util/FrameLimiter.h`.
- Sur Android le `target-fps` prend le taux de rafraichissement du panneau et non 60
  (`pckernel-h.gc:349-355`), pour que `seconds-per-frame = time-ratio/target-fps` fasse avancer le
  temps de jeu a vitesse constante.
- Un defaut de ce modele est DEJA documente dans l'arbre : `kmachine.cpp:4507` — « at a STABLE
  framerate the gameplay camera juders while the world/Jak stay smooth ».

**Pourquoi ca casse.** Un pas variable applique a une simulation concue pour un pas FIXE de 1/60 s
ne conserve ni les trajectoires balistiques (hauteur de saut = f(dt) non lineaire), ni les seuils
d'etat (une fenetre de detection large de 2 frames disparait quand dt double), ni les integrations
d'orientation. D'ou exactement ce que l'owner decrit : sauts trop courts, sauts d'etat (« skips »),
a-coups de camera.

## Ce qu'il faut construire

**Simulation a pas FIXE, presentation INTERPOLEE.**

1. La logique de jeu avance par ticks de **1/60 s exactement** — le pas de la PS2 —, quel que soit
   le framerate d'affichage. Accumulateur de temps : `while (acc >= dt_fixe) { tick(); acc -= dt; }`.
2. Le rendu interpole entre l'etat du tick precedent et celui du tick courant, avec
   `alpha = acc / dt_fixe`. Positions, orientations (slerp), et poses d'animation.
3. La camera est interpolee de la meme facon : c'est le symptome le plus visible (voir la note
   `kmachine.cpp:4507`).
4. Sous 60 fps : la simulation reste juste (plusieurs ticks par image affichee si necessaire, avec
   un plafond anti-spirale de la mort). Cible utile : **jouable a 25 fps** avec PBR + eclairage
   temps reel + herbe actives, sans casse de gameplay.
5. Au-dessus de 60 fps (75 / 90 / 120 / **variable**) : la fluidite vient de l'interpolation, pas
   d'un chemin special par palier. Le « truc pour 120 FPS » existant devient inutile.

## Comment le PROUVER (aucune capture, que des mesures)

- **Reference d'origine** : la meme sequence d'entrees, rejouee, doit produire les MEMES
  trajectoires a 25, 60, 90 et 120 fps. Comparer numeriquement, pas visuellement.
- **Hauteur et longueur de saut** identiques a tous les framerates, a la tolerance flottante pres.
- **Judder de camera** : la pose de camera par image doit varier de facon monotone ; publier
  l'ecart-type de la derivee seconde a chaque framerate, avant et apres.
- Le harnais de rejeu existe deja (`pad_replay_dump_camera`, `kmachine.cpp:4507` et suivants) : il
  force le pas a 1.0 pour isoler les divergences numeriques. **Le reutiliser.**

## Contraintes

- **Ne pas casser le comportement a 60 fps.** C'est la reference : a 60 fps, sortie identique a
  l'actuel.
- Changement transversal (GOAL + natif) : avancer par etapes prouvees, jamais en un seul lot.
- Profite a TOUTES les cibles : x86, Redmi (Adreno), Honor (Mali), appareil de test (Tegra).
