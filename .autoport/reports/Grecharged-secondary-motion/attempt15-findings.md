# KEIRA — DEUX REGLES DU MOTEUR NE POUVAIENT PAS S'APPLIQUER LA OU L'OWNER VOIT LES DEFAUTS

Cycle du 2026-08-12, branche `physics-keira-clean`.

DIRECTIVES v4e8d7808e6

Palier de build : **GOAL SEUL** (`(mi)`, 551 cibles, ~40 s) — un seul fichier `.gc` et un
script python. Aucun NDK, aucun cmake, aucune reconfiguration. Six courses de salle x86
completes (3410 mesures, 31/31 animations, `PHYSEND`), dont **deux dediees a un A/B** et
**une dediee a un retrait**.

---

## 0. CE QUE CETTE TENTATIVE PEUT ET NE PEUT PAS FERMER

Le validateur echoue sur **OPEN-DEFECTS**, et c'est structurel : sept defauts sont ouverts et
cette liste ne se vide **que sur la parole de l'owner**. Je n'ai retire aucune ligne `OPEN`.
En mode sans humain dans la boucle, cette gate ne peut pas passer — ce n'est pas un echec
technique, c'est une porte humaine, et la signaler est la seule conduite correcte.

**Toutes les autres gates du validateur passent, sauf une : COLLIDE**, sur UNE ligne de mesure
sur 3410 (section 5). Verifie en rejouant le code du validateur lui-meme, byte-identique, le
seul bloc `OPEN-DEFECTS` saute — et en **restaurant** ensuite `motion-floor.txt`, pour qu'un
run de diagnostic ne remonte pas le cliquet d'anti-regression que le vrai validateur n'a
jamais atteint.

---

## 1. LA METHODE : LIRE LE CODE CONTRE SES PROPRES CHIFFRES PUBLIES

Les deux causes racines de ce cycle n'ont demande aucune nouvelle instrumentation. Elles
etaient visibles en confrontant une ligne de code a une colonne que la salle publie **depuis
des jours** :

| colonne publiee | ce qu'elle disait | la ligne de code |
|---|---|---|
| `raddrop` = 0 sur les 11 chaines `rootlock=1`, 15 000-25 000 sur les 11 autres | un limiteur ne s'applique qu'a la moitie des chaines | `(when (= l 0))` sous une boucle qui saute deja `l < rlk` |
| `inv` = 0 sur les 11 memes chaines, 27-93 sur les autres | le test de cote non plus | meme predicat |
| `buried` = 50 642 sur `goggles` | 50 642 paires sans aucune contrainte | la branche `PHYS-VOL-FREE` |

C'est la lecon de la journee et elle est generalisable : **quand une colonne vaut exactement
zero sur un sous-ensemble entier de chaines, ce n'est pas un resultat, c'est un predicat.**

---

## 2. CAUSE RACINE 1 — `l = 0` NE POUVAIT JAMAIS ETRE VRAI SUR ONZE CHAINES

`phys-length-chain` porte deux regles ecrites pour « le lien attache a l'ancre » :

* le **test de cote** (« une chaine de famille A doit rester du cote de la pose du modele » —
  la reponse de l'owner au sein retourne vers l'interieur) ;
* le **plafond d'excursion** du lien seul.

Les deux etaient gardees par `(= l 0)`. Or la boucle qui les contient commence par
`(when (>= l rlk))` : sur une chaine `rootlock=1`, le maillon 0 **n'est jamais visite**. Le
test de cote et le plafond etaient donc **structurellement morts** sur onze chaines sur
vingt-deux — oreilles, cheveux, meches, lunettes, les quatre bretelles.

Ce que ca produisait, mesure par `tiprot` (rotation d'os REELLEMENT ecrite dans la matrice) :

| chaine | avant | apres | |
|---|---|---|---|
| topstrapL | **179.06°** | 92.86° | une bretelle retournee bout pour bout |
| botstrapR | 177.89° | 92.86° | |
| topstrapR | 176.75° | 92.85° | |
| goggles | 175.81° | 92.76° | |
| botstrapL | 174.55° | 92.86° | |
| earR / earL | 161.36 / 156.25° | 91.26 / 92.02° | |
| lmidhair / rmidhair | 125.76 / 123.38° | 88.99 / 88.97° | |
| backhair | 95.84° | 80.15° | |

179 degres, c'est un tissu cousu a l'epaule qui repart vers le torse. **C'est
`straps-elastic`**, et aucun reglage ne pouvait l'atteindre.

**Correction** : `(= l rlk)` — le premier lien LIBRE, celui dont l'attache est rigide. C'est
la lecture fidele de l'intention deja ecrite dans le commentaire ; `l = 0` n'y coincidait que
par accident quand `rootlock` valait 0. Applique aux **trois** sites (solveur, mesure du
residu, compteur), pour que l'instrument de mesure reste l'instrument de decision.

**Preuve d'execution** : `inv` passe de 0 a 320 (topstrapL), 467 (topstrapR), 628 (botstrapR),
206 (goggles), 223 (backhair) — sur des chaines ou il valait exactement zero.

### Ce que je n'ai PAS etendu, et le chiffre qui l'interdit

Le **plafond d'excursion** garde `(= l 0)`. `rmax` est la demi-epaisseur du morceau de
geometrie, pas un budget de course : sur un os seul les deux sont du meme ordre (lBoob 656 u
contre 977 u d'os, soit 39.2°), sur une bretelle non (157 u contre **1364 u** d'os, soit
`2*asin(157/2728)` = **6.6°** — la bretelle serait morte).

Le tableau de la salle **affirmait depuis des jours** « il porte desormais sur tout maillon
libre » pendant que le code lisait `l = 0`, et sa propre colonne `raddrop` le dementait.
Corrige dans `physics_room_table.py` : un commentaire n'est pas une preuve, y compris dans le
tableau qui sert a les produire.

---

## 3. CAUSE RACINE 2 — « ENTIEREMENT DEDANS » VOULAIT DIRE « PLUS AUCUNE CONTRAINTE »

`phys-vol-floor` rendait `PHYS-VOL-FREE` des que `floor0 >= 2 rl` : « ce lien est deja tout
entier dans ce volume a sa pose d'auteur, donc il n'a aucune surface devant lui ». Le
raisonnement est juste sur la **surface** et faux sur la **decision** : n'avoir aucune surface
devant soi n'autorise pas a s'enfoncer plus loin. Une fois FREE, la paire n'etait plus
contrainte **du tout**.

Colonne `buried`, par chaine, meme course :

    goggles 50 642   botstrapR 37 603   rbang 16 740   topstrapL 7 019
    kneeflapL 7 019  backhair 5 400     botstrapL 2 567

**50 642 fois par course, les lunettes n'avaient plus aucun volume devant elles.** C'est
`goggles-tunnel` : il suffit qu'une pose de cinematique les enfonce un peu plus (mesure de la
passe precedente : `gogglesBase` est a 227 u dedans pour `2 rl` = 392 u) pour que le buste
cesse d'exister pour elles.

**Correction** : `feff = floor0`, sans exception — la phrase de la SPEC, litteralement (« ce
qui est deja dedans au repos y reste »). Et elle **se degrade toute seule** dans le cas qui
avait motive la branche : `dep` est maximale sur l'axe du volume, donc un lien dont la pose
d'auteur est SUR l'axe a `floor0` = maximum atteignable et la contrainte devient vide **par
arithmetique**, sans branche. Pour un lien enfoui mais excentre (le pan de pantacourt, a 95 u
de l'axe du mollet) elle se lit « ne t'approche pas de l'axe plus que l'auteur ne t'y a mis » :
toute la rotation autour de la jambe reste libre, seul l'enfoncement est interdit.

`buried` reste **mesure** et cesse de **decider** : le compteur qui a designe le defaut reste
publie, il ne commande plus rien. `phys-flip-count` est re-cle sur le predicat de contact,
sans quoi son bit serait devenu constant et le compteur de bascules serait mort en silence en
affichant du vert.

---

## 4. LE RESULTAT MESURE, ET LE PLANCHER

| grandeur | avant (attempt 13) | apres | |
|---|---|---|---|
| `ROOM-SIDE` traversees d'axe | 19 430 | **11 446** | −41 % |
| dont topstrapL | 2 402 | 291 | −88 % |
| dont botstrapR | 3 454 | 927 | −73 % |
| dont pantflapL / R | 2 912 / 2 804 | 1 792 / 1 901 | −38 % / −32 % |
| `ROOM-STRETCH` max | 0.0561 (`rbang`) | **0.0272** (`lbang`) | **sous le plafond de 3 % pour la premiere fois** |
| `ROOM-SELFCOL` | 0 (controle 3 579) | 0 (controle 4 004) | inchange, controle tire |
| lignes a penetration positive | 1 / 3410 | 1 / 3410 | inchange |

**PLANCHER DE MOUVEMENT : zero chaine sous 60 %**, et quatre chaines **au-dessus** de leur
meilleur etat connu :

    topstrapL 0.2637 -> 0.4741 (+80 %)    botstrapR 0.3636 -> 0.6709 (+85 %)
    botstrapL 0.4455 -> 0.6309 (+42 %)    topstrapR 0.3639 -> 0.4668 (+28 %)
    la plus basse : kneeflapR a 70 % de son plancher, backhair a 71 %

Rendre une bretelle incapable de se retourner lui rend du mouvement au lieu de lui en prendre :
elle cesse de passer son temps coincee de l'autre cote de son attache.

---

## 5. CE QUI RESTE ROUGE, ET POURQUOI — L'INVARIANT DU RECUL A CEDE

**COLLIDE echoue sur UNE ligne sur 3410** : `rmidhair`, anim `assistant-firecanyon-idle-down`,
drive `accel`, **0.0017 m** (7 unites). La gate a raison de la refuser.

La cause est identifiee et elle est structurelle. Le recul garantit « rien ne traverse » parce
qu'il existe **toujours** un point admissible : la pose du modele, ou `dep == floor0` par
construction. Cet invariant a cede le jour ou `floor0` a ete mesure contre l'**instantane**
d'auteur du volume pendant que `dep` l'est contre sa position **courante** : pour un volume
porte par un joint **simule** (une meche voisine, un sein), les deux membres ne decrivent plus
le meme obstacle. `rmidhair` est la chaine 6 ; `lmidhair`, `lbang`, `rbang`, `earL`, `earR` ont
deja ecrit leurs joints quand elle est resolue, et ce sont exactement les joints qui portent
les volumes qu'elle heurte.

Ce n'etait **pas mesure**. Ca l'est : `ROOM-RETREAT-ANCHOR: fallback=531` — 531 fois par
course, le recul ne trouve aucun point admissible sur son chemin, pas meme la pose du modele.
Le compteur existait dans le moteur, la salle l'emettait (`PHYSLIM2`), et **le tableau ne l'a
jamais lu** : un instrument emis et jamais publie est un instrument muet. Il l'est desormais.

### Un correctif essaye, mesure, et RETIRE

J'ai essaye de faire atterrir le recul sur le **moins mauvais** point de son chemin quand
aucun n'est admissible — un point dont la penetration est, par construction, inferieure ou
egale a celle de la pose du modele. Course complete :

    lignes a penetration positive : 1 / 3410  ->  8 / 3410
    pire penetration              : 0.0017 m  ->  0.0030 m

Le raisonnement local etait juste, le resultat global pire : la pose du modele n'est pas
seulement un point admissible, c'est un **point fixe**. S'y reposer ramene la chaine au meme
etat a chaque frame ; se poser sur un minimum local la laisse ailleurs et la frame suivante
repart de plus loin. **Un minimum instantane ne vaut pas un point fixe.** Retire — pas
adouci, retire.

Une troisieme course a montre que le vrai coupable de ces 8 lignes n'etait meme pas
l'atterrissage mais le **premier pas force a `mid = 0`** : quand la pose du modele penetre, il
faisait tomber `hi` a 0 et l'intervalle se refermait sur le point de depart, ce qui privait la
dichotomie de ses douze pas. La dichotomie a le droit de partir d'une borne inadmissible et de
trouver quand meme un point admissible plus loin sur l'arc. Corrige : `it = 0` **mesure**, il
ne decide pas. `fallback` retombe de 668 a 531 et la penetration revient a 1 ligne.

---

## 6. `flesh-jelly` — UNE BARRIERE ECRITE POUR LUI, UN A/B QUI DIT NON

La signature du defaut est arithmetiquement fermee. `tiprot` de `chestL` vaut
**39.2376 / 39.2525 / 39.2890 / 39.2449** degres sous quatre pilotages radicalement differents
— la meme valeur a trois decimales sous une translation, une acceleration et un a-coup de 39 g.
C'est un plafond **epingle**, et il se recalcule a la main a partir de deux nombres publies :

    2*asin(rmax / (2 * longueur d'os)) = 2*asin(656 / (2*977)) = 39.24 deg     (mesure 39.2376)
    kneeflapL : 2*asin(244 / (2*0.0800*4096)) = 43.7169 deg                    (mesure 43.72)

Le mecanisme : le gain statique de l'integrateur vaut `1/k2` = 62.9, donc sous `accel` la force
du repere demande un ecart de ~11 950 u pour un budget de 656. Le systeme est sature d'un
facteur 18 : **la position ecrite ne depend plus de l'amplitude de la force, seulement de sa
direction** — et sous un a-coup cette direction change de signe d'une frame a l'autre. `jump`
= 0.1604 m sur une seule frame, soit 657 u, exactement le plafond traverse de part en part.

J'ai pose devant ce mur une **barriere** : une raideur qui monte en `k2/(1-(|o|/cap)^6)`,
une force, appelee une seule fois par frame (le piege d'idempotence de `phys-softmin` ne s'y
applique pas ; stabilite verifiee, pas supposee : plafonnee a 1.0, module des racines
`sqrt(1-0.26)` = 0.86 < 1).

**A/B complet, cette barriere pour seule variable, deux courses de 3410 mesures :**

| | armee | desarmee |
|---|---|---|
| `ROOM-JELLY excess` chestL accel | **0.4348** | 0.5510 |
| `ROOM-JELLY excess` chestL jerk | **0.5510** | 0.6055 |
| `ROOM-JELLY excess` chestL leftright | 0.5061 | **0.0543** |
| `ROOM-JELLY excess` chestL tilt | 0.3342 | **0.1743** |
| `ROOM-JELLY excess` chestR jerk | 0.4023 | **0.3258** |
| `raddrop` (impacts du mur dur), 10 chaines | 1 578-7 572 | 5 089-25 043 (**-69 a -77 %**) |
| `ROOM-SIDE` traversees | **11 446** | 13 344 |
| lignes a penetration positive | **1** | 2 |
| `ROOM-GRAVSAG` chestL / chestR | 0.0725 / 0.1022 | 0.0725 / 0.1039 |
| amplitude de pointe | −0.4 % a −4.9 % | reference |

**Verdict, et je l'ecris dans le code a cote de la barriere** : elle **ne corrige pas**
`flesh-jelly`. Mieux sur les deux pilotages brusques a gauche, pire ailleurs, pire sur `jerk` a
droite. Ce n'est pas une correction, c'est un deplacement, et `flesh-jelly` reste **OUVERT**.

Elle est **gardee** pour ce qu'elle fait reellement et qui est mesure : −72 % d'impacts sur le
mur dur, −14 % de traversees d'axe, une ligne de penetration au lieu de deux — pour un prix de
5 % d'amplitude au pire et un affaissement gravitaire **inchange** (0.0725 contre 0.0725).
L'acquis que l'owner a nomme (« quand elle se penche : nickel ») n'est pas touche.

Ce qu'il faudra pour fermer `flesh-jelly`, et ce n'est pas un reglage de plus : **desaturer**.
Soit toucher raideur/couplage — c'est-a-dire l'amplitude qu'il a approuvee — soit
sous-echantillonner le pas. Les deux se decident devant son oeil.

---

## 7. `knee-tabs` — LA CAUSE ECRITE DANS LE FICHIER ETAIT FAUSSE

`owner-defects.txt` portait : « les os LfootFlaps/RfootFlaps n'existent pas dans le rig HD.
Reprise d'ASSET requise ». Le premier fait est vrai, la conclusion ne l'est pas — et elle
allait envoyer le prochain cycle faire du travail d'asset inutile.

**Mesure** (`.autoport/probe_knee_tabs.py`, sur le mesh skinne et le rig, ecrit ce cycle) :

    lKneeFlap / rKneeFlap possedent 24 sommets chacun, a p50=716 u et max=888 u de l'AXE DE
    LA JAMBE, quand la PEAU de la jambe (Lknee, Lthigh) est a 322..486 u du meme axe.
    Aucun autre os ne possede de geometrie dans ce voisinage a une distance comparable.

Ce qui depasse de 17 a 22 cm de la jambe, **c'est la geometrie de `lKneeFlap`** — les
languettes. Elles ont une chaine, elle tourne (`tiprot` 43.72°, ecrit dans la matrice).

**La vraie cause est ailleurs, et elle n'avait jamais ete regardee** : sous pilotage elles
bougent (0.167 / 0.087 m), mais **sous animation seule — la seule chose que l'owner voie en
jeu** — la ligne de base vaut **0.0780 m a gauche et 0.0093 m a droite**. Neuf millimetres. Et
`kneeflapR` est en contact **17 893** frames contre **5 473** a gauche : c'est la collision qui
l'ecrase, pas l'absence d'os. L'asymetrie gauche/droite est un defaut a part entiere.

Consequence de methode : **la gate MOVE lit le maximum sous un pilotage a 39 g, pas ce que
l'owner voit.** Une chaine peut passer MOVE a 0.167 et etre invisible en jeu a 0.009. Je le
signale sans toucher a la gate (regle 5).

---

## 8. CE QUI RESTE OUVERT, DEFAUT PAR DEFAUT

| defaut | etat apres ce cycle |
|---|---|
| `straps-elastic` | cause racine trouvee et corrigee : le repliement a 179° n'est plus possible (92.9°), et les bretelles **gagnent** 28 a 85 % de mouvement. A juger de ses yeux. |
| `goggles-tunnel` | cause racine trouvee et corrigee : les 50 642 paires sans aucune contrainte n'existent plus. Non prouve autrement que par la mesure de salle — **aucune cinematique n'est jouee par la salle**, et c'est la ou il l'a vu. |
| `goggles-bottom` | `ROOM-SIDE` des lunettes 4 911 -> 4 092 (−17 %). **Le moins ameliore des trois.** Aucune mesure ne separe encore le BAS des lunettes du reste de la chaine. |
| `pant-calf` | `ROOM-SIDE` −38 % / −32 %, mais 1 792 / 1 901 traversees subsistent. **Non ferme, et la cause est identifiee** : le volume que le pan presente est une SPHERE de 429 u centree sur son joint, lequel est a 95 u de l'axe du mollet — donc la sphere contient la jambe. Un fourreau ne peut pas etre une sphere posee sur l'axe qu'il entoure. |
| `flesh-jelly` | **non ferme**, diagnostic complet en section 6, A/B publie. |
| `hair-big-angles` | partiellement : le premier maillon libre passe de 125.8° a 89.0°, `bendcut` baisse de 44 % ; mais le maillon PROFOND de `lbang`/`rbang` reste a 122° et n'est borne par rien. |
| `knee-tabs` | la cause ecrite etait fausse (section 7). La vraie est mesuree : 9 mm sous animation seule a droite, et une asymetrie de contact de 3x. |

Restent aussi, inchanges et non tus : `ROOM-INVERSIONS residual = 380` (la priorite deterministe
entre volumes qui se recouvrent n'est toujours pas implementee ; le controle positif tient a
1523, soit 4.0x le residu), et **toutes les mesures de ce rapport sont x86** — la salle ne
tourne pas sur le device.

---

## 9. CE QUE JE DEMANDE A L'OWNER SUR CE BUILD

1. **Les bretelles** : elles ne peuvent plus se retourner et elles bougent 28 a 85 % de plus.
   Est-ce que ca clipe encore au travers de l'elastique orange ? Est-ce que c'est trop ?
2. **Les lunettes en cinematique** : c'est le defaut le plus grave et c'est celui que je ne
   peux pas verifier — la salle ne joue pas de cinematique. Est-ce qu'elles traversent encore ?
3. **Les oreilles et les meches** : leur premier maillon ne se replie plus au-dela de 90°.
   Est-ce que la geometrie est plus propre, ou est-ce que ca les a raidies ?
4. Le reste (gelee, bas des lunettes, pantacourt, languettes) n'a recu **aucune correction
   fermante** ce cycle : inutile d'y chercher du neuf, mais leurs causes sont maintenant
   chiffrees.

---

## 10. `goggles-bottom` — 94 % DES LUNETTES N'ETAIENT TESTEES CONTRE RIEN (ajout, meme cycle)

Le point le mieux ferme de ce cycle, et il ne demandait aucun build : `physics_chains.txt` est
lu a l'execution.

La chaine `goggles` est `gogglesBase -> gogglesMid`. Le generateur s'y arrete parce que
`gogglesMid` **fourche**, et son propre docstring le documentait comme voulu (« which is why
the goggles chain stops at gogglesMid »). Personne n'avait mesure ce que la fourche coute :

    gogglesBase  16 sommets      gogglesMid   11 sommets
    gogglesLeft 244 sommets      gogglesRight 244 sommets

**27 sommets sur 515 sont simules. Les 488 autres — 94 %, les VERRES — n'ont aucune chaine,
donc aucun volume de collision, et ne sont testes contre RIEN.** Le moteur les deplace
rigidement par propagation de delta. Le seul volume teste est une sphere de rayon 150 posee sur
`gogglesMid`, et `gogglesMid` est a **932 u** de `lBoob`/`rBoob` en pose bind pour une geometrie
de verre qui porte a **603 u** de son joint : les verres atteignent l'interieur des spheres de
poitrine, le volume teste non. C'est `goggles-bottom`, au complet.

**L'AMPLITUDE, mesuree.** J'ai change la regle (« une fourche ouvre une chaine par branche »),
regenere, et lance la salle : les verres deviennent `gogglesleft` / `gogglesright` (os de
0.107 / 0.099 m) et la course rapporte immediatement **11 318 et 9 018 frames de CONTACT** avec
les volumes du corps, et jusqu'a **0.0838 m de penetration reelle** sous `jerk`. Le defaut
existait a l'identique avant : il n'etait simplement mesure par rien. Ce n'est pas
« legerement ».

**ET C'EST RETIRE.** `gogglesLeft` / `gogglesRight` sont les deux coquilles d'une monture
**rigide**. Leur donner un ressort propre les fait osciller par rapport a la monture et la
resolution de collision les pousse hors du corps INDEPENDAMMENT d'elle : le verre se decolle de
son cerclage. Regle 6 de l'owner — « une resolution pire que le clip est pire que rien » — et il
a par ailleurs valide la physique des lunettes telle quelle (« leur physique marche bien ») : le
defaut est un CLIPPING, pas un manque de mouvement. Le generateur est revenu a la regle
precedente, `physics_chains.txt` est **identique** a l'etat livre (22 chaines), et la note
mesuree est ecrite dans le generateur pour que la prochaine passe parte de la.

**CE QU'IL FAUT** : un volume ajuste sur `gogglesMid` qui **couvre les verres en les laissant
rigides** (`*phys-lcr*`), pas une chaine de plus. Non pose ici : ca demande son propre A/B — la
meme idee appliquee aux cheveux a coute 43 % du mouvement de `backhair`, et l'owner a prevenu
que gonfler un volume finirait par « decoller les lunettes du corps ».
