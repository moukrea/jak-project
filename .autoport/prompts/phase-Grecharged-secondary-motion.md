# PHYSIQUE DE KEIRA — DÉPART PROPRE (2026-08-11)

Le contrat est `.autoport/prompts/SPEC-keira-physique.md`, réécrit depuis le message de l'owner.
Il est inliné dans ce prompt : lis-le, c'est la seule source d'exigences.

Branche : `physics-keira-clean`. Toute la physique accumulée est parkée sur
`physics-attic-2026-08-11` — **elle n'est pas une base de travail, on ne va pas y repêcher du code**.
Le moteur est un squelette de 5 prises (`jak-hd-physics.gc`, ~45 lignes) et le fichier de chaînes
est vide. Le jeu compile et tourne sans physique : c'est l'état de départ, il est sain.

## L'ORDRE DE TRAVAIL, ET IL N'Y EN A PAS D'AUTRE

1. **LA SALLE DE TEST, SANS JOUEUR.** C'est l'étape 1 et le validateur échoue dessus en premier.
   Jak n'est **pas spawné** — ni endormi, ni hors champ : absent, et tu le prouves par le log de la
   course (`ROOM-NOPLAYER:`). Le sujet est spawné **par nom**, seul acteur de la zone
   (`ROOM-ACTORS: 1 subject=…`). Tu le déplaces **haut/bas** et **gauche/droite**, avec **diverses
   accélérations** et des **à-coups** (`drive=updown|leftright|accel|jerk`). Tu joues **toutes** les
   animations de son art-group (`ROOM-ANIMS: joué/total`, et joué == total). Chaque chiffre extrême
   porte le **nom de l'animation** (`worst chain=… anim=…`).
2. **LES CHAÎNES DE KEIRA, GÉNÉRÉES depuis son rig** : oreilles, cheveux (racine ancrée), mèches,
   seins, lunettes, ce qui pend. Rien d'autre. Aucune ligne écrite à la main.
3. **LES COLLISIONS** de la liste exacte (SPEC §3), avec de vrais colliders qui suivent la forme du
   personnage — et un contrôle positif qui fait **monter** le compteur.
4. **LE REPOS = LA POSE DU MODÈLE** (sauf ce qui pend), et **l'intention d'animation ND a la
   priorité**, détectée **par chaîne**.

## CE QUI FAIT ÉCHOUER IMMÉDIATEMENT

* une affirmation sur le comportement qui ne cite pas une trace d'exécution (un commentaire n'est
  pas une preuve) ;
* un zéro sans contrôle positif qui a fait **monter** le compteur ;
* une chaîne déclarée mais inerte (tipvar < 0.05) — « ce qu'on veut c'est de la physique sur les
  oreilles, cheveux, mèches, seins, lunettes » ;
* une racine qui dérive ;
* un moteur qui repasse au-dessus de 2500 lignes : l'ancien en faisait 6000 et c'est l'empilement de
  suppresseurs qui a tué le mouvement ;
* un autre modèle que Keira dans les données.

Substrat : **x86** pour découvrir (itération en secondes), device `eae4df44` pour confirmer.
Livraison en **paire cohérente** APK + pack du même commit.
