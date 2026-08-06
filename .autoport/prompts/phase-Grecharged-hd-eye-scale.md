# Grecharged-hd-eye-scale — les yeux HD deviennent globuleux

## VERDICT OWNER (2026-08-06, backlog assumé)
« Les yeux de Daxter sont bien des yeux HD, mais il y a un truc non maîtrisé... Dans Jak 1 ses yeux
changent de TAILLE (cartoon), et visiblement l'influence de cet effet est beaucoup trop grosse sur les
yeux HD, ce qui génère des yeux bien trop GLOBULEUX sur certaines animations exagérées (bien plus
globuleux que ce qu'ils sont avec les modèles originaux). Donc à TONE DOWN pour que ça ne fasse pas
buggé. »

## CE QU'IL FAUT FAIRE
1. Trouver le canal qui fait varier la taille des yeux (jak1 = effet cartoon volontaire : eye-h /
   eye.gc, le scale de l'os/quad d'oeil piloté par l'anim ou par la table d'yeux).
2. Comprendre POURQUOI il porte plus fort sur un oeil HD que sur l'oeil stock (échelle relative à une
   taille de base différente ? facteur appliqué en absolu au lieu d'être relatif ? oeil HD plus gros
   au bind donc même facteur = plus d'amplitude en valeur absolue ?).
3. Réduire le GAIN sur les modèles HD sans supprimer l'effet — l'exagération HD doit rester <= à
   l'exagération du modèle d'origine.
4. Vérifier les autres persos HD qui héritent du même canal (Jak, Keira, Samos, variantes de look).

## PREUVE (interdiction des preuves visuelles — owner, permanent)
Mesurer CÔTÉ CODE le facteur d'échelle effectivement appliqué à l'oeil, min/max sur une animation
exagérée, en STOCK et en HD, et montrer que HD <= stock après correction. Pas de capture, pas de
comparaison à l'oeil.
