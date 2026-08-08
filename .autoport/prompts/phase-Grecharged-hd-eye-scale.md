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

## REJET OWNER 2026-08-08 08:30 — « ABSOLUMENT AUCUNE DIFFÉRENCE »
« Les yeux de Daxter continuent de DOUBLER DE TAILLE, au point où les deux yeux se TOUCHENT sur
beaucoup d'animations. Absolument aucune différence. PAS VALIDÉ. »

### CE QUE ÇA PROUVE
Le rapport mesure `iris stock max=1,0938 -> HD max=0,4922`, « excursion conservée à 45 % », avec les
paramètres lus depuis le pack livré (`PARAMSRC=package`). Ces chiffres sont probablement exacts —
et pourtant rien ne change à l'écran. Donc **le canal mesuré n'est PAS celui qui fait grossir l'oeil
que l'owner voit**. On a comprimé quelque chose de réel qui n'est pas le défaut.

### CE QU'IL FAUT FAIRE, DANS CET ORDRE
  1. **Identifier ce qui rend l'oeil GROS À L'ÉCRAN sur Daxter**, en jeu, pas en théorie. Le zoom de
     la sprite d'iris dans la tuile 32x32 n'est qu'un candidat. Autres candidats à éliminer
     explicitement : l'échelle du QUAD d'oeil lui-même, une cible de blend (blerc) sur les paupières
     ou le globe, un scale d'os d'oeil dans l'animation, la table d'yeux (`eye.gc` / EyeRenderer)
     qui redimensionne le sprite selon un index d'anim.
  2. **Le symptôme donne la mesure** : l'owner dit que les DEUX YEUX SE TOUCHENT. C'est une distance
     mesurable. Rapporter, sur une animation exagérée de Daxter, la distance bord-à-bord entre les
     deux yeux, en STOCK et en HD, frame par frame. Si les bords se rejoignent en HD et pas en stock,
     on tient le défaut et sa mesure. Ce chiffre-là ne peut pas mentir.
  3. Ne PAS re-livrer une compression sur un canal dont on n'a pas prouvé qu'il pilote CE symptôme.
