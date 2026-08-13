# À TESTER — Keira : la géométrie des mèches ne devrait plus casser

Branche `physics-keira-clean`, commit `5ce634f5c5`.
(Le tag est lisible sur le device : `files/.custom_pack_stamp_jak1`. Si ce n'est pas ce commit-là,
tu testes un vieux build.)

⚠️ **RE-TÉLÉCHARGE `jak1_hd_assets.zip`.** Le correctif est ENTIÈREMENT dans le mesh, donc il voyage
uniquement par le pack HD externe — un APK frais avec l'ancien pack ne changera **rien** du tout.

## LE SEUL CHANGEMENT DE CE BUILD, ET C'EST TON DIAGNOSTIC

Ton retour du 12 août : « la physique ne s'applique pas à toute la géométrie de ces deux mèches mais
à seulement une partie, donc on a des polygones qui bougent et des polygones voisins parfaitement
statiques, causant la géométrie qui casse ».

**C'était exact, et voici ce qui se passait.** Le correcteur de poids graduait la frontière entre
« la mèche » et « le crâne » — mais il comptait le **maillon de racine** parmi les os qui bougent,
alors que ce maillon est *verrouillé* : il est soudé au crâne, aussi immobile que lui. Donc un
polygone tenu par la racine (figé) collé à un polygone tenu par le maillon suivant (mobile) lui
paraissait parfaitement continu. Il lissait une frontière qui ne casse pas, et **la vraie cassure
lui était invisible** — comme à tous mes instruments, qui faisaient la même erreur.

Mesuré sur le mesh que tu as en main : **116 arêtes déchirées** que rien ne voyait —
`backhair` 28, `rmidhair` 48, `rbang` 20, `lbang` 18, `lmidhair` 2. Toutes **au milieu** de la mèche,
pas à la racine. Après correction : **0**, sur les cinq mèches.

## CE QUE JE TE DEMANDE DE REGARDER

1. **La géométrie des mèches quand elle bouge la tête** — c'est le seul endroit où ça doit se voir.
   Les polygones qui « partaient tout seuls » à mi-mèche ne devraient plus le faire. `rmidhair` et
   `backhair` étaient les pires, regarde-les en priorité.
2. **Les mèches ne doivent PAS s'être décollées du crâne.** C'est le seul risque de ce correctif :
   pour recoller la peau, il faut lui donner un peu de poids mobile, et trop en donner détacherait
   la coiffe. La mesure dit que la limite tient (aucun sommet n'est passé majoritairement du côté
   mobile), mais c'est ton œil qui tranche — si tu vois la chevelure « flotter » ou se détacher à la
   racine, dis-le, c'est ça le signe.

## CE QUI N'A PAS CHANGÉ, POUR QUE TU NE LE CHERCHES PAS

**L'amplitude est identique au build précédent, au bit près.** Ce build ne touche QUE les poids de
peau : le solveur, les chaînes, les volumes sont rigoureusement les mêmes fichiers. Donc :

* si les mèches fines te semblent toujours trop mortes (ou trop vives), c'est **un autre sujet** et
  ton retour là-dessus reste nécessaire ;
* le pantacourt dans les mollets, les lunettes, les languettes de genoux, l'effet gelée sur les
  mouvements brusques, la nuque : **rien n'a bougé**, je ne te fais pas chercher une différence qui
  n'existe pas.

Les neuf défauts que tu as signalés restent ouverts tant que tu ne les as pas fermés toi-même.
