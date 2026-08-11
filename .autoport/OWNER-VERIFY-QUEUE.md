# À TESTER — Keira, réponse à ton retour de 18:00 (les seins s'allongent / pas de sag / le milieu bouge plus que les pointes)

Branche `physics-keira-clean`, commit `613218dfa3`, tag de build **613218-ceb901**.
(Le tag est aussi lisible sur le device : si ce n'est pas celui-là, tu testes un vieux build.)

## TES TROIS PHRASES, ET CE QUI A CHANGÉ

1. **« Les seins s'allongent de nouveau sur les mouvements brusques. »**
   C'était la contrainte de longueur qui cédait — pas au ressort, à la **collision** : sa poussée
   est une translation, et quand elle est dirigée dans l'axe de l'ancre (un sein poussé par la
   capsule du buste) elle ne fait rien d'autre qu'allonger. Elle est maintenant reprojetée sur la
   sphère de l'attache : ça **tourne** au lieu de s'étirer. Le couplage n'a PAS été rebaissé,
   comme annoncé dans le build précédent.
   Mesuré : allongement de la poitrine **0,070 → 0,0000** sur les cinq pilotages.

2. **« Le sag est invisible sur l'inclinaison toujours. »**
   Deux causes, les deux réparées. (a) la gravité de la poitrine n'était pas une **force** mais un
   déplacement de cible plafonné, annulé par la contrainte de longueur — d'où « tripler `gravity=`
   ne change rien », ce que le chiffre disait déjà et que personne n'avait lu. (b) le moteur croyait
   **deux volumes du même sein** : une petite sphère bien placée quand on le heurte, une grosse
   sphère de 16 cm posée sur l'os quand il bouge. C'est la grosse qui décidait, et elle le renvoyait
   8653 fois par course.
   Mesuré : affaissement penchée à 60° **0,0156 m → 0,0725 et 0,1036 m**.
   ⚠️ **Regarde aussi DEBOUT** : il reste ~2,3 cm d'affaissement permanent. Si c'est trop bas,
   dis-le — `gravity=` est devenu un réglage linéaire, ça se baisse sans aucun build.

3. **« Le milieu est plus hystérique que les pointes. »**
   Tu avais raison contre mon instrument, pour la troisième fois de la journée : je mesurais
   l'écart à la pose d'animation, qui **s'additionne** le long de la chaîne, donc une pointe soudée
   à son parent affichait le chiffre de son parent. Le gradient est maintenant l'angle de chaque
   maillon **par rapport à son propre parent**. Il trouve **7** cas de milieu-plus-mobile-que-la-pointe
   là où l'ancienne mesure en voyait **0**. C'est instrumenté, ce n'est pas encore corrigé — je veux
   savoir si ce que tu vois correspond.

## EN PRIME, TROUVÉ EN VÉRIFIANT MES PROPRES UNITÉS
L'orientation écrite dans le squelette était **fausse depuis le début** : `atan` rend des unités de
rotation (65536 = un tour) et le code la traitait comme des radians. Un fléchissement de 1° faisait
tourner l'os de 57°, et au-delà ça repliait modulo un tour. La **position** était juste, donc aucun
de mes chiffres ne pouvait le voir. Candidat direct pour deux défauts que tu avais signalés et que
je n'expliquais pas : les **« petits bugs de géométrie » sur les grosses mèches** et le **polygone de
la semelle de la chaussure gauche qui se fait la malle**. C'est le seul point de ce build que je ne
peux pas chiffrer — ton œil tranche.

## CE QUI N'EST PAS RÉGLÉ, ET JE LE DIS
* `rbang`/`lbang` s'allongent encore jusqu'à 21 % sur les à-coups (216 frames sur la course).
  Quand « rien ne traverse » et « longueur invariante » se contredisent, c'est le premier qui gagne.
* Résidu d'inversion **181** (l'ordre de priorité entre volumes qui se recouvrent n'est pas fait).
* Ta suggestion des colliders dérivés du **mesh** décimé plutôt que du rig : pas évaluée, elle
  demande son propre cycle. La correction (2b) ci-dessus en est un acompte, pas un remplacement.
