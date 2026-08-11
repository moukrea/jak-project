# À TESTER — Keira, cycle complet (validateur + close-gate PASSÉS, ton œil est la dernière porte)

Branche `physics-keira-clean`, commit 13d1c71d — moteur réécrit, 22 chaînes, 13 colliders.

## CE QUI EST MESURÉ COMME CORRIGÉ
* **Pénétration nulle sur tes trois paires**, sur 1584 mesures — contre 0,0270 (lunettes) et
  0,0839 (sangle) au cycle précédent :
  cheveux/mèches vs crâne-visage-épaules-oreilles · lunettes vs corps et seins · oreilles vs mèches.
* **Sein retourné : corrigé.** La cause n'était PAS l'ancre (mon hypothèse) mais **l'axe du volume** :
  une capsule est une coquille symétrique, les deux côtés sont admissibles, donc un lien poussé au
  travers s'y retrouve tenu du mauvais côté — équilibre stable et faux.
  Compteur : 7313 corrections, **résidu 595** (pas zéro, voir plus bas). Contrôle positif ×9,1.

## CE QUI N'EST PAS RÉGLÉ, ET POURQUOI — DEUX DÉCISIONS SONT À TOI
1. **Les seins pendant la soudure.** Mon hypothèse (l'animation suspend la physique) est **réfutée
   par la mesure** : ce moteur ne suspend rien, et la poitrine n'est pas dans les 8 chaînes que
   l'animation pilote. La vraie cause : l'animation de soudure bouge son torse **2,5 à 4 fois moins**
   que les autres (0,077 m contre 0,20–0,295 m). Il n'y a presque rien à exciter, et debout immobile
   l'animation est la seule excitation. → Veux-tu (a) plus de couplage/moins de raideur sur la
   poitrine, quitte à la rendre plus mobile partout, ou (b) une excitation de respiration ?
2. **Résidu d'inversion 595, pas zéro.** Deux volumes qui se recouvrent se renvoient le lien d'un
   côté à l'autre. Il faut soit un solveur conjoint sur les volumes, soit une priorité entre eux —
   décision de conception que le worker n'a pas prise seul.

## CE SUR QUOI TON ŒIL SERT
1. Le sein qui se retournait : le vois-tu encore ? (résidu non nul, donc c'est possible)
2. Les mèches fines : toujours en jitter, ou calmées ?
3. Les lunettes : clipent-elles encore sur les seins ?
4. Les bretelles et le pantacourt : le torse et les mollets ont des colliders maintenant.
5. L'allongement des seins sur les changements brusques de direction.
