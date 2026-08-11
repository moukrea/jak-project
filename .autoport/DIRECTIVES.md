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

## VERDICT DE L'OWNER SUR L'APK DU 2026-08-11 11:24 (il a vu Keira lui-même)

> « Alors c'est pas dégueu. Ses seins pourraient bouger un peu plus mais à défaut ça rend pas mal
> quand même. Les mèches les plus fines sur le devant par contre sont folles, et les plus grosses un
> peu trop statiques. Ses bretelles passent au travers de son torse sur le devant (au niveau du dos
> ça a l'air ok). »

**Premier retour globalement positif de la série.** Ce qui en découle, déjà appliqué par le
superviseur côté DONNÉES (inutile de le refaire) :
* `lbang`/`rbang` « folles » : raideur 2.60 → 3.30, couple 1.00 → 0.70, masse 0.70 → 0.88.
  L'amortissement n'a PAS été touché (amortir = tuer, c'est ce qui avait tué Maia).
* `lmidhair`/`rmidhair` « trop statiques » : raideur 2.00 → 1.50, couple 1.00 → 1.40, masse → 0.72.
* `chestL`/`chestR` « pourraient bouger un peu plus » : couple 1.00 → 1.45, amortissement 0.35 →
  0.26, **raideur inchangée** (ferme = raideur, et un grand angle donnerait un ballon d'eau).

**CE QUI RESTE À FAIRE, ET C'EST STRUCTUREL** : les bretelles ne traversaient pas le torse par
mauvais réglage — **il n'existait aucun collider de buste**. Les 9 colliders étaient `main` (549),
les deux oreilles, les quatre mèches et les deux seins. J'ai ajouté `chest→hips` et `neck→chest`
depuis les joints réels du rig (`chest`, `neck`, `hips` existent dans `assistant-ag.go`), mais **les
rayons sont une estimation** : à vérifier et à ajuster contre la vraie épaisseur du mesh, et à
mesurer par la salle (la pénétration des bretelles doit tomber à zéro avec un contrôle positif qui
monte). C'est exactement la cause racine que l'owner désigne depuis le début : *les colliders ne
suivent pas la forme du personnage*.

Asymétrie à expliquer aussi : `chestL` mesuré à 0,66 contre `chestR` à 1,04 pour des paramètres
quasi identiques (656 vs 660).

## DEUXIÈME PASSE DE L'OWNER (2026-08-11, même APK)

> « les bretelles des fois sont OK, des fois non. Ses seins, j'ai vu un coup où un des seins était
> retourné vers l'intérieur… la même animation relancée et c'était nickel. Les lunettes (leur
> physique) marchent bien, mais clipent à peine un poil avec ses seins, faudrait ajuster d'un petit
> chouilla. »

* **Lunettes vs seins** : traité côté données par le superviseur — colliders `lBoob` 656→676 et
  `rBoob` 660→680. Ne pas refaire.
* **Bretelles intermittentes** : cohérent avec l'absence totale de collider de buste, corrigée
  depuis (`chest→hips`, `neck→chest`). À confirmer sur le prochain retour ; si ça persiste, les
  rayons estimés sont à mesurer contre le mesh.
* **UN SEIN RETOURNÉ VERS L'INTÉRIEUR, par intermittence, sur la même animation** — c'est un
  défaut de SOLVEUR, à corriger dans le moteur, pas un réglage :
  `phys-length-chain` saute la contrainte quand la distance à l'ancre passe sous `0.0001`
  (`(when (> d 0.0001) …)`). La direction devient indéfinie et le lien peut se restabiliser **du
  mauvais côté de son ancre** — un équilibre stable mais faux, puisque le ressort est symétrique
  autour de l'ancre. D'où l'intermittence et la disparition en relançant.
  Correction attendue : une chaîne à un seul os de famille A doit rester **du côté de la pose du
  modèle**. Si le produit scalaire entre la direction courante et la direction de la pose devient
  négatif, on réfléchit le lien au lieu de laisser filer ; et le cas dégénéré (d ≈ 0) doit repartir
  de la direction de la pose, jamais être ignoré. C'est la règle « rotation autour de l'ancre,
  longueur invariante » — le même défaut de fond que le « giga pointe ou quasiment plat ».
  **À mesurer** : la salle doit compter les inversions (produit scalaire négatif) et le compteur
  doit tomber à zéro avec un contrôle positif qui l'a fait monter.
