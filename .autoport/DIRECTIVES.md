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

## TROISIÈME PASSE DE L'OWNER (2026-08-11, APK de 11:40) — et un incident de process

> « les mouvements de ses seins sont plus prononcés c'est cool, mais des fois ça saute d'une frame
> à l'autre comme un mini jitter. Quand elle fait l'animation de soudure sur le Zoomer ses seins
> ont aucune physique. Ses mèches les plus fines sur le front jittent comme des folles constamment.
> Les plus grosses maintenant bougent bien mais ça fait des petits bugs de géométrie. Ses lunettes
> clipent encore un chouille sur les seins. **Les bretelles c'est vraiment beaucoup, beaucoup
> mieux !** Mais ça clipe avec le bas de son débardeur, l'élastique orange. J'ai encore vu un de
> ses seins retourné vers l'intérieur. Les petites languettes sur les bandes autour de ses genoux
> ne bougent pas du tout. Le bout du pantacourt de sa jambe droite glitche au travers de son
> mollet. Sa chaussure gauche donne l'impression qu'un polygone de la semelle se fait la malle. »

**INCIDENT DE PROCESS — à ne pas reproduire.** `physics_chains.txt` est régénéré depuis le rig, et
la régénération a **effacé deux fois** les réglages issus de ses retours : il a testé un APK dont
les corrections qu'il avait demandées avaient disparu. Corrigé structurellement :
`recharged_assets/keira-owner-tuning.txt` porte les réglages validés par son œil,
`.autoport/apply_owner_tuning.py` les réapplique après génération, et `android/build_custom_pack.sh`
l'appelle à chaque empaquetage. **Toute régénération doit passer par là.** Une directive sans cible
est signalée, jamais avalée en silence.

**Traité côté données (ne pas refaire) :** mèches fines `stiffness 3.30 → 1.65` — ma correction
précédente allait dans le mauvais sens, une raideur élevée dans un intégrateur explicite à pas fixe
produit de l'oscillation numérique, pas de la fermeté, et le « folles » initial venait déjà de là ;
seins `stiffness 2.80 → 2.20, damping 0.26 → 0.33`, couplage conservé (l'amplitude lui plaît) ;
`lBoob/rBoob → 708/712` ; extrémité basse du collider de tronc `470 → 545` (élastique du débardeur) ;
**colliders de mollet ajoutés** `Rknee→Rankle` et `Lknee→Lankle` (il n'existait aucun collider de
jambe) ; `pantflapL` **rétablie** — elle avait été supprimée du fichier au lieu d'être réparée.

**À FAIRE DANS LE MOTEUR — ce sont des défauts, pas des réglages :**
1. **Les seins n'ont aucune physique pendant l'animation de soudure sur le Zoomer.** La détection
   d'animation d'auteur suspend la poitrine alors que l'animation ne pilote pas ces os. La règle est
   « détection PAR CHAÎNE » : un os sans rapport ne suspend rien. À mesurer : la salle doit rapporter,
   par animation, quelles chaînes ont été suspendues et pourquoi.
2. **Un sein retourné vers l'intérieur, toujours** (déjà décrit : `phys-length-chain` saute la
   contrainte sous `d < 0.0001`). Compteur d'inversions exigé, à zéro, avec contrôle positif.
3. **« Petits bugs de géométrie » sur les grosses mèches** et **un polygone de la semelle de la
   chaussure gauche qui se fait la malle** : une chaîne écrit des joints qui entraînent de la
   géométrie qu'elle ne devrait pas toucher. Vérifier quels joints chaque chaîne écrit réellement,
   et que `LtoeStrap`/`LfootFlaps` ne tirent pas la semelle.
4. **Les languettes des bandes de genoux ne bougent pas du tout.** `kneeflapL/R` mesurent pourtant
   0,66 et 0,25 : soit la chaîne pilote le mauvais joint, soit les languettes sont une pièce
   distincte (`LfootFlaps`/`RfootFlaps` existent dans le rig et ne sont chaînées par rien).

## PRÉCISION DE L'OWNER SUR LA PRIORITÉ D'ANIMATION (2026-08-11) — RÈGLE, PAS NUANCE

> « Lors des animations, les bones qui ne sont pas explicitement animés (juste ils suivent leur
> ancrage au reste mais ne sont pas ajustés par l'animation) devraient donc rester en physique,
> histoire de ne pas muter la physique pour rien. L'animation a la priorité sur la physique
> uniquement pour ce qui est **explicitement manipulé** par l'animation. »

**Traduction technique, et c'est le cœur du bug des seins pendant la soudure sur le Zoomer :**
un os qui bouge dans le monde *parce que son parent bouge* n'est PAS piloté par l'animation. Le
test actuel confond « ce joint s'est déplacé » et « l'animation pilote ce joint ». Le seul test
valable porte sur la transformation **LOCALE** du joint par rapport à son parent, telle qu'elle
sort des données d'animation :

* l'animation manipule le joint ⟺ son canal **local** varie dans l'animation (rotation/translation
  propre) ;
* si le canal local est constant et que seul le parent bouge, **la physique garde la main** ;
* corollaire : suspendre une chaîne parce que le buste bouge est toujours faux. Pendant la soudure,
  le torse s'agite, les os de poitrine n'ont aucun canal propre → la physique doit tourner.

**Mesure attendue dans la salle** : par animation et par chaîne, rapporter (a) si le canal local
varie, (b) si la chaîne a été suspendue, et (c) combien de frames. Une chaîne suspendue alors que
son canal local est constant est un défaut, et le compteur correspondant doit être à zéro avec un
contrôle positif qui l'a fait monter (animation qui pilote réellement la chaîne → suspension
attendue).

## QUATRIÈME PASSE DE L'OWNER (2026-08-11, APK de 12:05)

> « Pour les mèches fines, j'ai l'impression que les pointes et racines sont un peu ancrées avec
> l'entre-deux qui bouge énormément, très bizarre. J'ai encore vu un sein retourné vers l'intérieur
> et les lunettes clipent encore un peu avec les seins. »

**1. MÈCHES FINES — racine ET pointe fixes, milieu qui gonfle. Hypothèse à vérifier EN PREMIER,
elle est structurelle :** les colliders déclarés sont **les joints-racines des chaînes elles-mêmes**
(`Lbanga`, `Rbanga`, `Lmidhaira`, `Rmidhaira`, `lEara`, `rEara`, `lBoob`, `rBoob`). Une mèche est
donc poussée hors de **sa propre sphère de racine** : le maillon 0 est verrouillé par `rootlock`, le
maillon du milieu est éjecté par le collider de sa propre racine, et la pointe reste près de la pose.
Signature exacte de ce que l'owner décrit.
→ **Une chaîne ne doit jamais entrer en collision avec ses propres maillons ni avec le collider
porté par son propre joint-racine.** Ce n'est pas un `colskip` (interdit) : c'est une exclusion
structurelle chaîne↔elle-même, comme la collision chaîne↔chaîne est structurellement autorisée.
→ **À mesurer** : par chaîne, le nombre de corrections de collision provenant de son propre
collider. Doit être **zéro**, avec un contrôle positif qui l'a fait monter.
→ Vérifier aussi que le **dernier maillon est bien simulé et écrit** : une pointe qui reste sur la
pose de l'animation donne la même silhouette.

**2. SEIN RETOURNÉ, TOUJOURS** — troisième signalement. Reste le défaut de `phys-length-chain`
(contrainte sautée sous `d < 0.0001`, le lien se restabilise du mauvais côté de son ancre). Une
chaîne à un os de famille A doit rester du côté de la pose du modèle ; compteur d'inversions à zéro
avec contrôle positif. **C'est le défaut le plus visible qui reste, il passe devant le reste.**

**3. LUNETTES vs SEINS** — traité côté données : on cesse d'enfler la poitrine (ça finirait par
décoller les lunettes du corps), ce sont les lunettes qui manquaient de volume propre. Leur second
maillon passe de 79 à 150.

## CINQUIÈME PASSE DE L'OWNER (2026-08-11, APK de 12:20)

> « Les mèches fines sont toujours en crazy jitter, ça n'a pas changé. Les seins ne bougent toujours
> pas quand elle soude, pourtant son torse se déplace donc logiquement la physique devrait opérer.
> Ses lunettes clipent toujours un peu sur ses seins. Les changements brusques de direction causent
> un truc chelou au niveau des seins, ils s'allongent, c'est un peu débile — c'est pourtant nickel
> sur le reste des animations plus subtiles. »

Rien de surprenant sur les deux premiers : les corrections sont **moteur**, elles ne sont pas dans
ce build. Ils restent en tête de file. Mais deux choses nouvelles :

**1. LES SEINS S'ALLONGENT sur les changements brusques de direction.** C'est un défaut de solveur,
et mon réglage l'a rendu visible : j'avais monté `couple` de 1.00 à 1.45, or le couplage est une
déviation **positionnelle** — sous forte accélération il **étire** au lieu de faire tourner. Ramené
à 1.20 côté données, mais **le vrai correctif est dans le moteur** :
→ une chaîne à un seul os doit **tourner autour de son ancre à longueur invariante**, jamais se
translater ni s'allonger. La contrainte de longueur doit être **dure** (projection appliquée jusqu'à
convergence sur la frame), pas un ressort qui cède quand l'impulsion est forte.
→ **À mesurer** : allongement relatif max du maillon (|longueur courante / longueur de repos − 1|)
par chaîne et par animation, sur les pilotages `jerk` et `accel` en particulier. Doit rester sous
3 %, avec un contrôle positif qui l'a fait monter.

**2. LES LUNETTES CLIPENT ENCORE malgré deux élargissements.** Hypothèse : le collider de poitrine
est une sphère posée sur le **joint-racine** du sein, alors que le sein **est simulé et se déplace**.
Les lunettes évitent donc la position de repos de la poitrine, pas sa position réelle. C'est la
collision **chaîne↔chaîne** que la SPEC §3 exige (« les oreilles ont de la physique elles aussi…
ce sont des volumes, pas seulement des chaînes ») et qui n'existe visiblement pas.
→ Les lunettes doivent collisionner contre la position **courante simulée** des chaînes `chestL`/
`chestR`, pas contre une sphère statique. Même chose pour cheveux ↔ oreilles.
→ **À mesurer** : nombre de corrections chaîne↔chaîne effectivement appliquées, par paire. Zéro
correction sur une paire déclarée = la collision chaîne↔chaîne n'est pas branchée.

## SIXIÈME PASSE DE L'OWNER (2026-08-11, APK de 13:48) — quatre points, tous ouverts

> « Les mèches fines continuent de jitter like crazy dès que la tête bouge (peu importe si c'est la
> tête qui bouge ou si elle est déplacée dans l'espace par le reste du squelette) et les mèches les
> plus grosses sont trop statiques sur les mouvements faibles, trop hystériques sur les mouvements
> brusques. Les seins n'ont pas l'air d'être soumis à la gravité, aucun mouvement quand elle se
> penche en avant pour souder par exemple, pas cohérent du tout. Et les lunettes clipent toujours
> légèrement dessus, et même en idle — donc c'est pas juste les capsules de collision qui bougent
> pas, mais plutôt mes capsules de collision qui sont pas bonnes. Le bas de son pantacourt clipe au
> travers de ses deux mollets maintenant, pas seulement le droit. »

**CE QUE LE SUPERVISEUR A CORRIGÉ (ne pas refaire) :** mes quatre capsules estimées à la main
(`chest→hips`, `neck→chest`, `Rknee→Rankle`, `Lknee→Lankle`) sont **retirées**. Le rig en génère 24,
mesurées, et les miennes se posaient sur les mêmes segments avec des rayons plus fins
(`Rknee→Rankle` 300/205 contre 398/326 mesurée). Une gate `TUNING` vérifie désormais que tous ses
réglages sont dans le fichier livré — la régénération les avait effacés deux fois.

**LES QUATRE DÉFAUTS, PAR ORDRE :**

1. **MÈCHES FINES, jitter dès que la tête bouge, quelle que soit l'origine du mouvement.** Troisième
   signalement identique, aucun réglage ne l'a jamais changé — donc ce n'est pas un réglage. Piste
   restée sans réponse : les colliders `Lbanga`/`Rbanga`/`Lmidhaira`/`Rmidhaira` sont **les
   joints-racines des chaînes elles-mêmes**, et les capsules `Lbangb→Lbanga` (rayon 558 !) sont des
   maillons de la mèche. Une mèche est donc en collision permanente avec elle-même. **À mesurer :
   par chaîne, le nombre de corrections issues de son propre collider ou d'une capsule portée par
   ses propres joints. Doit être zéro, contrôle positif à l'appui.**
2. **GROSSES MÈCHES : rien sur les petits mouvements, hystériques sur les brusques.** Réponse
   non linéaire = il y a un seuil quelque part. Le moteur en contient au moins deux (seuil de
   détection d'intention, zone morte du test de côté). **Mesurer la réponse : amplitude de pointe en
   fonction de l'amplitude d'excitation, sur les quatre pilotages. Une marche dans la courbe désigne
   le seuil coupable.**
3. **SEINS SANS GRAVITÉ.** `chestL`/`chestR` ont `gravity=0.00` : c'était voulu (famille A, le repos
   doit être la pose du modèle), mais la SPEC dit que la gravité agit sur la **dynamique** et que
   l'exception s'applique **quand elle n'est plus debout**. Elle se penche pour souder, rien ne
   tombe. **Il faut une gravité exprimée dans le repère de l'ancre** : elle ne déplace pas le point
   d'équilibre quand le buste est droit, elle agit dès qu'il s'incline. Le pilotage `tilt` de la
   salle doit le mesurer et il ne le voit pas aujourd'hui.
4. **LUNETTES QUI CLIPENT MÊME EN IDLE.** Son diagnostic est juste et il est mécanique : `lBoob` et
   `rBoob` sont des **sphères nues posées sur le joint-racine** (708/712), alors que tout le reste du
   corps est en capsules dérivées. Une sphère au joint ne peut pas épouser un sein. **Il faut des
   volumes de poitrine dérivés comme les autres**, et arrêter d'en gonfler le rayon : au troisième
   élargissement les lunettes finiront par flotter loin du corps.

## RÈGLE DE REPRISE (owner 2026-08-11) — SON RETOUR EST LE VERDICT

> « Qu'est-ce que tu racontes sur la porte humaine ? T'as eu mon feedback, tu dois t'assurer que ça
> reprenne. »

Un retour de l'owner qui décrit des défauts **est** un verdict de non-validation. La phase se rouvre
**immédiatement** — on ne l'annonce pas comme bloquée, on ne l'attend pas au point de supervision
suivant. Le superviseur retire la phase de `validator_passed` et relance ; le jeton
`.autoport/owner-ok/<phase>` reste **exclusivement** le geste de l'owner et n'est jamais créé à sa
place. Une porte humaine ne se signale que lorsqu'il n'a rien dit.

## RÈGLE DE NON-DESTRUCTION (owner 2026-08-11)

> « T'assurer que ton travail n'est pas systématiquement détruit, c'est chelou comme comportement,
> tu peux pas juste dire "ah oups", corriger et laisser reproduire en boucle ! »

Ses réglages ont été effacés deux fois par la régénération. Corriger après coup, deux fois, en
accrochant la réapplication à l'**empaquetage** — un appelant parmi d'autres — n'a pas empêché la
récurrence. La réapplication est maintenant faite **par le producteur lui-même**, à la fin de
l'écriture de `physics_chains.txt` : il n'existe plus de chemin qui régénère sans réappliquer.
Règle générale : **quand une perte se répète, on la rend impossible au point de production, pas
détectable au point de contrôle.** Une gate qui constate la perte arrive toujours trop tard.

## SUGGESTION TECHNIQUE DE L'OWNER — COLLIDERS DÉRIVÉS DU MESH, PAS DU RIG

> « Pourquoi dériver du rig et pas du mesh en suivant ses déformations avec plus ou moins
> d'accuracy en fonction de la précision demandée (réduire les tris du mesh collider en fonction du
> niveau de précision) plutôt que des capsules ? Je sais pas si c'est mieux, c'est une suggestion. »

**À évaluer sérieusement, avec des nombres, pas un avis.** Les 24 capsules actuelles sont dérivées
du RIG (segment os→os + rayon), donc elles ne peuvent pas épouser une forme : c'est précisément
pourquoi une poitrine reste une sphère et pourquoi les lunettes clipent même à l'arrêt. Un collider
issu du **mesh skinné décimé** suit la vraie silhouette et se déforme avec elle, et le niveau de
précision déjà présent dans le menu donne naturellement le budget de triangles.

Ce qu'il faut mesurer avant de trancher, sur Keira et sur le device :
1. **Fidélité** : distance max d'un sommet du mesh à l'extérieur du volume, capsules vs mesh décimé,
   à budgets égaux. C'est le chiffre qui dit si la forme est mieux épousée.
2. **Coût par frame** : les capsules sont un test analytique ; un mesh décimé demande une structure
   d'accélération et un test point↔triangle. Mesurer sur le Redmi, pas sur x86.
3. **Déformation** : le mesh décimé doit être **skinné**, donc re-transformé chaque frame — c'est là
   que se joue le coût réel, et c'est aussi ce qui le rend supérieur.
4. **Niveaux** : bas = capsules actuelles, moyen = mesh très décimé, haut = décimation fine. Le
   toggle existe déjà.
Livrer les quatre nombres avant de choisir. Si le mesh gagne en fidélité pour un coût device
acceptable, c'est lui qui répond à son blocage historique (« les colliders ne suivent pas les formes
du mesh ») — mieux que n'importe quel réglage de rayon.
