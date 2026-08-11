# SPEC — PHYSIQUE DE KEIRA (contrat, réécrit le 2026-08-11 depuis la consigne de l'owner)

Ce document remplace toutes les versions précédentes. Il est écrit à partir du message de l'owner
du 2026-08-11, qui est la seule source d'exigences. Tout ce qui n'y est pas n'est pas demandé.

**Départ propre.** Toute la physique accumulée est parkée sur `physics-attic-2026-08-11` (rien n'est
perdu, rien n'est repris). Le travail se fait sur `physics-keira-clean`. Le moteur est réécrit à
neuf derrière les 5 mêmes prises (`jak-hd-physics-init/step/release`, `phys-note-covered!`,
`phys-rider-post!`) pour que rien d'autre dans le jeu ne bouge.

**Périmètre : KEIRA SEULE.** « On ne passera à un autre personnage que quand Keira sera 100 %
validé. » Aucun autre modèle n'a de données de chaînes tant que l'owner n'a pas validé Keira.

---

## 1. CE QUI A DE LA PHYSIQUE

Oreilles · cheveux · mèches · seins · lunettes · les trucs qui pendent.

Rien d'autre. Chaque élément de cette liste doit bouger de façon perceptible — un élément déclaré
mais inerte est un échec, pas une prudence.

## 1 bis. LA POITRINE — DESCRIPTION DE L'OWNER (2026-08-11), MOT POUR MOT ET TRADUITE

> « Ses seins sont fermes, elle est jeune. Mais comme ils ne sont pas non plus petits, ils doivent
> bouger pas mal, mais plus perky et pas des trucs qui pendouillent. Ils doivent aussi évidemment
> être influencés par la gravité : elle s'incline d'un côté, ils s'y conforment… Mais ils sont
> fermes, donc pas des trucs qui s'allongent non plus. Elle se penche en avant pour souder, idem !
> Ils ont une masse, le point de référence c'est quand elle est debout (position naturelle des seins
> du coup, car c'est comme ça que le modèle est fait), mais ils suivent la gravité ! Les mouvements :
> ils bougent, bouncent, s'entrechoquent sur les mouvements brusques… comme des vrais seins fermes ! »

Traduction en exigences, chacune vérifiable :

| Ce qu'il décrit | Ce que ça impose | Ce qui le mesure |
|---|---|---|
| **fermes, jeunes** | pas d'allongement du tout : la longueur de l'os est invariante, contrainte **dure** | `ROOM-STRETCH ≤ 3 %` sur `jerk`/`accel` |
| **pas petits → bougent pas mal** | amplitude franche et visible, pas un frémissement | réponse ≥ celle des autres chaînes de famille A à stimulus égal |
| **perky, pas pendouillant** | retour rapide vers la référence : sous-amorti, une ou deux oscillations nettes, pas un affaissement mou | temps de retour court, dépassement présent |
| **la référence = debout** | au repos debout, exactement la pose du modèle — c'est ainsi qu'il a été sculpté | `ROOM-IDLE` ≈ 0 |
| **elle s'incline, ils s'y conforment** | la gravité déplace l'**équilibre** selon l'orientation, pas seulement la dynamique | `ROOM-GRAVSAG` franc, du même ordre que les autres chaînes de famille A |
| **ils ont une masse** | l'inertie retarde la réponse sur un départ brusque : ils restent en arrière puis rattrapent | déphasage mesurable entre l'ancre et la pointe |
| **ils s'entrechoquent** | collision **chaîne↔chaîne** entre `chestL` et `chestR`, avec rebond | nombre de contacts `chestL`↔`chestR` > 0 sur `jerk`, et pénétration nulle |

Les trois derniers points n'ont **jamais** été satisfaits : le sag est resté sept fois plus petit que
celui des cheveux, aucun contact `chestL`↔`chestR` n'a jamais été compté, et l'allongement revient
dès que le couplage monte. Ce sont les trois défauts à fermer, dans cet ordre.

## 2. LA RACINE NE BOUGE PAS

Les cheveux **restent ancrés à la racine**. La racine suit rigidement l'os porteur (crâne, torse) ;
le mouvement croît vers la pointe, et c'est **sur la pointe** qu'on juge s'il y a du mouvement. Une
racine qui dérive = cheveux décollés = défaut. Les deux moitiés sont indissociables : ancré ET mobile.

**Le gradient est monotone, et ce n'est pas négociable.** Owner 2026-08-11 : « faut pas que le milieu
des petites mèches bouge plus que les pointes, c'est juste logique ». Le mouvement de chaque maillon,
**mesuré relativement à son parent**, doit être ≥ celui du maillon précédent. Un milieu plus agité
que la pointe est un échec, quelle que soit l'amplitude globale.

## 3. COLLISIONS PROPRES — LA LISTE EXACTE

Aucun de ces contacts ne doit se produire :

| Ce qui bouge | Ne doit jamais traverser |
|---|---|
| cheveux, mèches | crâne, visage, épaules, **oreilles** |
| lunettes | le corps de Keira, **ses seins** |
| oreilles | les mèches |

**Les oreilles ont de la physique elles aussi** — elles sont donc à la fois un objet simulé et un
obstacle. Idem pour les mèches et les seins : ce sont des volumes, pas seulement des chaînes.
Il faut de **bons colliders** : qui suivent la forme réelle du personnage, pas des approximations
posées à la main à côté de la plaque.

## 4. LE REPOS, C'EST LE MODÈLE

Au repos (idle), chaque élément doit **retrouver exactement la pose du modèle de base** — pas plus
bas, pas plus écrasé. Exception : **ce qui doit pendre** (les lunettes) pend et reste pendu ; ça ne
retourne pas à la pose du modèle.

## 5. L'ANIMATION D'AUTEUR A LA PRIORITÉ — MAIS SEULEMENT SUR CE QU'ELLE MANIPULE

Si un os bouge sur une **intention d'animation**, l'animation gagne : c'est voulu par l'animation
originale de Naughty Dog. La physique reprend ensuite. La détection se fait **par chaîne** — un os
sans rapport ne suspend rien.

Précision de l'owner (2026-08-11), qui est une règle et pas une nuance : « les bones qui ne sont pas
explicitement animés (juste ils suivent leur ancrage au reste mais ne sont pas ajustés par
l'animation) devraient rester en physique, histoire de ne pas muter la physique pour rien ».

Donc le test porte sur le canal **LOCAL** du joint dans les données d'animation, jamais sur son
déplacement dans le monde :
* canal local qui varie ⟹ l'animation manipule le joint ⟹ elle gagne ;
* canal local constant et seul le parent qui bouge ⟹ **la physique garde la main**.

Suspendre une chaîne parce que le buste s'agite est toujours faux. C'est ce qui rendait la poitrine
inerte pendant l'animation de soudure sur le Zoomer.

## 6. LA SALLE DE TEST — ÉTAPE 1, AVANT TOUTE PHYSIQUE

> « il serait bon d'avoir une test room dans laquelle **on ne spawn pas le player** mais le
> personnage à tester, qu'on déplace in game de haut en bas, de gauche à droite, avec diverses
> accélérations, à coups, animations (toutes celles concernant ledit PNJ/Actor/Enemy, ici Keira)
> histoire de pouvoir tester pour de vrai la physique pour ledit personnage. »

Exigences, chacune vérifiable :

1. **PAS DE JOUEUR.** Jak n'est pas spawné, pas endormi, pas hors champ : **absent**. La tentative
   précédente hébergeait la mesure dans une partie normale à `village1-hut` avec Jak jouable —
   l'owner l'a vu à l'écran. Ça ne se reproduit pas. Zone vide : le sujet, la caméra, rien d'autre.
2. **LE SUJET EST SPAWNÉ PAR NOM** (Keira) et c'est le seul acteur de la zone.
3. **ON LE DÉPLACE** : haut/bas, gauche/droite, **diverses accélérations**, **à-coups** (départs et
   arrêts brutaux).
4. **TOUTES SES ANIMATIONS** sont jouées — la liste complète de son art-group, pas un cycle choisi.
5. Chaque chiffre extrême porte le **nom de l'animation** où il s'est produit.

## 7. CE QUI FAIT FOI

La **position écrite du joint**, frame par frame, telle que le moteur l'écrit dans le squelette.
Tout en dérive : mouvement de pointe, déviation de racine, pénétration d'une surface, pire saut
d'une frame. Aucun instrument inventé par-dessus.

Trois règles qui ont coûté une semaine et qui ne se renégocient pas :

* **Un commentaire n'est pas une preuve.** Toute affirmation sur ce que le programme fait cite une
  trace d'exécution. Jamais un docstring, jamais une intention écrite dans le source.
* **Tout zéro exige un contrôle positif qui a tiré** : on injecte le défaut, on voit le compteur
  **monter**, on l'enlève. Un contrôle qui fait *baisser* le compteur est un contrôle cassé.
* **AVANT D'ÉCRIRE UNE MESURE, RÉPONDRE À TROIS QUESTIONS.** Les trois faux verts du 2026-08-11 ont
  la même racine : la grandeur mesurée ne correspondait pas au défaut décrit.
  1. **De quelle NATURE est le défaut ?** Une amplitude, une **forme**, un **déplacement soutenu**,
     ou une fréquence ? Une variance ne peut pas décrire un affaissement sous gravité ; un scalaire
     unique ne peut pas décrire un dégradé le long d'une chaîne.
  2. **Dans quel REPÈRE ?** Un maillon hérite du mouvement de son parent : mesuré en repère monde,
     une pointe parfaitement immobile par rapport à son parent affiche un grand chiffre. Le mouvement
     propre se mesure **relativement au parent** ou dans le repère de l'ancre.
  3. **Que lit-elle quand le défaut est ABSENT ?** Sans cette ligne de base, un chiffre n'a pas
     d'échelle et le contrôle positif n'a rien à comparer.
  Une mesure publiée sans ces trois réponses écrites à côté d'elle est provisoire, pas acquise.
* **Une mesure doit DISCRIMINER.** Une grandeur publiée par stimulus doit varier quand le stimulus
  change du tout au tout. Mesuré le 2026-08-11 : 16 chaînes sur 22 rendaient la même amplitude sous
  une secousse, une translation et une inclinaison à 60° (`backhair` : 3 % d'écart). Une réponse
  plate veut dire qu'on mesure le bruit de l'animation, pas la physique — et c'est ainsi qu'un
  chiffre vert coexiste avec un défaut que l'owner voit. Seuil : moins de 25 % d'écart relatif entre
  le plus fort et le plus faible stimulus = mesure non discriminante, rejetée.
* **Pas de suppresseur par défaut.** Gel de calme, clamp, hystérésis, sommeil : absents. La cause
  mesurée de l'échec précédent est leur empilement (le moteur est passé de 1 940 à 6 000 lignes,
  clamps 9 → 84, détection d'anim 45 → 172) jusqu'à ce que 42 % des mesures soient à zéro. On en
  ajoute un uniquement si un défaut mesuré l'exige, et on chiffre **combien de mouvement il retire**.

## 8. QUAND C'EST FINI

Keira validée **par l'owner, de ses yeux**, sur un build livré en **paire cohérente** (APK + pack de
données du même commit — une paire dépareillée donne du comportement aléatoire). Alors, et seulement
alors, on passe au personnage suivant.
