# DIRECTIVES — contrat courant, autorité supérieure au prompt de tâche

Ce fichier est **relu à chaque étape** par le manager de phase ET par chaque sous-agent
(`autoport-researcher`, `autoport-implementer`, `autoport-tester`). Il est **plus récent** que le
prompt qui t'a lancé : en cas de conflit, **c'est lui qui gagne**, et tu le signales dans ton
rapport au lieu de suivre une consigne périmée.

Première action obligatoire, avant tout outil de travail : lire ce fichier, puis le contrat de
périmètre qu'il désigne ci-dessous.

---

## PÉRIMÈTRE ACTIF (2026-08-11)

SCOPE-SERIAL: 3
<!-- Bump ce numéro UNIQUEMENT pour un vrai changement de périmètre : il invalide
     immédiatement la tentative en cours (gate SYNC). Corriger une coquille ou
     reformuler ne doit jamais coûter une tentative. -->

* Phase : `Grecharged-secondary-motion` — physique secondaire. Branche : **`physics-keira-clean`**.
* **DÉPART PROPRE, ACTÉ LE 2026-08-11.** Owner : « parke tous les commits propres à la physique sur
  une branche dédiée et repars propre en ne faisant un focus que sur Keira comme on a dit ». Toute
  la physique accumulée est sur `physics-attic-2026-08-11` : **elle n'est pas une base de travail**,
  on ne la consulte pas pour « récupérer » du code. Le moteur est un squelette de 5 prises et le
  fichier de chaînes est **vide**.
* **CONTRAT UNIQUE : `.autoport/prompts/SPEC-keira-physique.md`**, réécrit depuis son message. Il
  dit ce qui a de la physique (oreilles, cheveux à racine ancrée, mèches, seins, lunettes, ce qui
  pend), la liste exacte des collisions interdites, le repos = pose du modèle sauf ce qui pend, et
  la priorité à l'intention d'animation de Naughty Dog.
* **ÉTAPE 1, AVANT TOUTE PHYSIQUE : LA SALLE DE TEST SANS JOUEUR.** Jak n'est **pas spawné** — ni
  endormi, ni hors champ : absent. Le sujet est spawné par nom, seul dans la zone, déplacé
  haut/bas, gauche/droite, avec diverses accélérations et à-coups, et **toutes** ses animations
  jouées, chaque chiffre extrême portant le nom de l'animation. La tentative précédente mesurait
  dans une partie normale à `village1-hut` avec Jak jouable à l'écran : l'owner l'a vu, ça ne se
  reproduit pas.
* **KEIRA SEULE.** « On ne passera à un autre personnage que quand Keira sera 100 % validé. » Aucun
  autre modèle ne reçoit de données.
* Livraison par **paire cohérente** APK + pack du même commit. Substrat x86 pour découvrir, Redmi
  `eae4df44` pour confirmer.

## RÈGLES QUI NE SE NÉGOCIENT JAMAIS (owner)

0. **UN COMMENTAIRE N'EST PAS UNE PREUVE.** Owner 2026-08-11 : « me raconte pas de conneries, je
   sais ce que je vois ». Toute affirmation sur ce que le programme FAIT doit citer une trace
   d'exécution (ligne de log, compteur, nombre mesuré) — jamais un commentaire, un docstring ou
   une intention écrite dans le source. Exemple de la faute : `phys-room.gc:429` affirme « the
   player is asleep, nothing else is in it » ; aucune trace ne le confirme, et l'owner voit Jak
   jouer normalement dans la hutte du Sage pendant la mesure. Cette règle vaut pour le worker,
   les sous-agents ET le superviseur.

1. **Aucun faux vert.** Un chiffre vert dont l'owner voit encore le défaut est une mesure sans
   valeur : elle est retirée, pas défendue. Tout zéro exige un **contrôle positif qui a tiré**
   (injecter le défaut, voir le compteur monter, l'enlever).
2. **Aucune preuve visuelle.** Interdiction permanente des campagnes de captures/verdicts à l'œil.
   La qualité est jugée par l'owner ; toi tu produis des nombres.
3. **Aucun de-scope silencieux.** Si une partie du périmètre est bloquée, tu finis tout le reste
   et tu le dis explicitement — jamais réduire en silence.
4. **Données générées, jamais rustinées.** Les chaînes viennent du rig + des règles de la SPEC.
   Aucun flag de dérogation (`colskip`, filtres de volumes, masques).
5. **Gates gelées.** N'ajoute, ne modifie et n'assouplis **aucune** gate du validateur — c'est un
   verrou dur. Si une gate te semble fausse, tu le rapportes ; c'est le superviseur qui tranche.
6. **Rien ne traverse le mesh de son personnage, quelle qu'en soit la raison.** Une résolution
   pire que le clip est pire que rien.
7. **Une mesure par chaîne doit varier par chaîne.** Constante partagée ou rampe d'index =
   fabriquée, rejetée.
8. Jamais `git push --force`, jamais `rm -rf` sur du code, jamais de kill par motif (auto-match) —
   PID exacts uniquement.

## RAPPORT

Ton rapport doit contenir, en clair, la ligne de synchronisation que le prompt t'a donnée :

```
DIRECTIVES <version>
```

Elle prouve que tu as travaillé sur le contrat courant. Une version périmée fait échouer la
tentative immédiatement, au lieu de gaspiller des heures sur un périmètre abandonné.

## ÉTAT MESURÉ PAR LE SUPERVISEUR (2026-08-11 10:00, course x86 réelle)

J'ai lancé la salle moi-même pendant le blocage de quota. Ce qui est **acquis, prouvé par le log** :

```
PHYSROOM-START target-before=#<target ... suspended ...>
PHYSROOM-START target-after=#f spawned=1
```

→ l'exigence n°1 est remplie : le joueur existait, la salle le supprime, le sujet est spawné à sa
place. **Ne la refais pas, ne la « répare » pas.**

Ce qui **manque**, et c'est tout ce qui reste de l'étape 1 : la course n'a produit que **2 lignes
`PHYSROOM`**. Aucun pilotage, aucune animation, aucune mesure n'est sortie. Il faut donc :
`drive=updown|leftright|accel|jerk`, **toutes** les animations de son art-group avec
`ROOM-ANIMS: joué/total`, une ligne `row` par (chaîne, animation) avec les six colonnes, le nom de
l'animation sur chaque extrême, et les lignes `ROOM-NOPLAYER:`, `ROOM-ACTORS:`, `ROOM-POSCONTROL:`,
`ROOM-IDLE:`, `ROOM-AUTHORED:` que le validateur lit.

Le moteur (806 lignes) et la salle (471 lignes) **compilent** : 551 cibles en 41 s. Pas de temps à
passer sur la compilation.
