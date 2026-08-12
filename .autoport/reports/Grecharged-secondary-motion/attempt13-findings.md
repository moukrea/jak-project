# KEIRA — 16e PASSE. TROIS CAUSES ÉLIMINÉES PAR LA MESURE, ET UN DÉFAUT DE HARNAIS QUI DÉTRUIT LE TRAVAIL

Cycle du 2026-08-12, branche `physics-keira-clean`.

DIRECTIVES v4e8d7808e6

Ce fichier porte les mesures de cette tentative sous un nom qui n'appartient qu'à elle. C'est
délibéré, et la section 1 dit pourquoi : `report.txt` est écrit par deux processus à la fois
aujourd'hui, donc un rapport déposé là ne survit pas forcément à la minute qui suit.

---

## 0. CE QUE CETTE TENTATIVE PEUT ET NE PEUT PAS FERMER

Le validateur échoue sur `OPEN-DEFECTS`, et c'est **voulu** : cinq défauts rapportés par l'owner
sont ouverts dans `owner-defects.txt`, et cette liste ne se vide que sur SA parole. Je n'y ai pas
touché. La phase ne peut donc pas se déclarer terminée, quelle que soit la qualité du travail.

Ce que cette tentative apporte : **elle élimine des causes avec des nombres, et elle en désigne
d'autres.** Une cause éliminée vaut un cycle gagné pour la suivante — c'est ce qui manquait aux
quatorze passes précédentes, qui ont plusieurs fois « corrigé » un mécanisme qui n'était pas
le bon.

---

## 1. INCIDENT DE HARNAIS — DEUX WORKERS IDENTIQUES TRAVAILLENT SUR CETTE PHASE EN MÊME TEMPS

C'est le point le plus important du rapport, il passe donc devant la physique.

```
PID 922762   démarré  mer. août 12 06:59:09 2026
PID 925937   démarré  mer. août 12 06:59:25 2026
```

Les deux lignes de commande sont **identiques au caractère près** — même prompt de phase, mêmes
cinq défauts ouverts, même `--dangerously-skip-permissions`, même arbre de travail. Seize secondes
d'écart au lancement.

Ce que ça produit, constaté et daté pendant cette tentative :

| heure | fait |
|---|---|
| 07:05:50 | `recharged_assets/physics_chains.txt` — état HEAD (`radii=4000` sur la poitrine) |
| ~07:11 | **je** lance la salle ; `gk` lit les paramètres à cet instant |
| 07:12:56 | **l'autre worker** ajoute `cover_perp_radius`/`fit_cover_radius` au générateur |
| 07:14:00 | **l'autre worker** régénère `physics_chains.txt` (capsules p95, poitrine remise à 656) |
| 07:17:13 | **l'autre worker** modifie `goal_src/jak1/pc/jak-hd-physics.gc` (+79 lignes) |
| 07:18:57 | **l'autre worker** recompile `GAME.CGO` |
| ~07:33 | **ma** course atteint `PHYSEND` |

Trois conséquences, toutes vérifiables :

1. **Les deux workers écrivent le même fichier de trace** (`keira-room-x86.log`) et le même
   `keira-room-table.txt`. Deux courses qui se chevauchent laissent un seul log, et le tableau
   décrit alors un état que personne n'a choisi.
2. **Les deux écriront `report.txt`.** Le dernier gagne, le travail de l'autre disparaît.
3. **Les deux commitent sur la même branche**, l'un par-dessus les modifications non commitées de
   l'autre.

L'owner, le 2026-08-11 : « t'assurer que ton travail n'est pas systématiquement détruit, c'est
chelou comme comportement, tu peux pas juste dire "ah oups", corriger et laisser reproduire en
boucle ! » — **en voici un mécanisme, et il est dans le harnais, pas dans la physique.** La règle
de non-destruction dit de rendre la perte impossible au point de PRODUCTION : ici, le point de
production est le lanceur de workers, qui doit refuser de démarrer une seconde instance sur une
phase déjà tenue (un verrou par phase, pas une convention).

**Ce que j'en ai fait, et ce que je n'ai pas fait.** Je n'ai tué aucun processus : l'autre worker
porte du travail non commité qui est bon, et le tuer l'aurait détruit — ce serait exactement la
faute que je signale. Je me suis retiré des fichiers qu'il tient (`physics_keira_gen2.py`,
`jak-hd-physics.gc`, `physics_chains.txt`), j'en ai pris une copie de sûreté dans
`/tmp/keira_concurrent_snapshot/`, et j'ai porté mon travail sur ce qu'il ne fait pas : la mesure.
**Je n'ai pas relancé `gk` après avoir constaté qu'il mesurait** — deux instances se seraient
disputé la trace.

---

## 2. `flesh-jelly` — LE PLAFOND D'EXCURSION N'EST PAS LA CAUSE. A/B MESURÉ, HYPOTHÈSE RÉFUTÉE

### 2.1 Le montage

Le plafond d'excursion (`raddrop`, `jak-hd-physics.gc:922-947`) borne l'écart d'un lien seul à son
propre rayon mesuré. Sur la poitrine il valait 656 u pour un os de 977 u, et la 15e passe l'avait
mesuré **saturé** : 18 894 morsures sur ~19 000 frames, `shape` figé à 0.6727 = 656/977 au
dix-millième près. C'est la signature d'un limiteur assis sur sa butée, et une butée saturée rend
la même valeur quel que soit le stimulus — donc un excellent suspect pour « ça change de taille
sans que ce soit cohérent ».

Deux états, **rien d'autre ne change**, aucune compilation (palier DONNÉES SEULES) :

| | `radii=` poitrine | md5 de `physics_chains.txt` | preuve d'exécution |
|---|---|---|---|
| **CAP ON** | 656 / 660 | tableau du cycle précédent | `chestL raddrop=18894`, `chestR=14613` |
| **CAP OFF** | 4000 / 4000 | `4dd207d747abc26cf2384aaba3bac7bd` (HEAD) | `chestL raddrop=0`, `chestR raddrop=0` |

`raddrop = 0` n'est pas une promesse : c'est la conséquence arithmétique de `radii=4000`. Après la
projection de longueur, `|p − ancre| = |T − ancre| = want = 977 u`, donc `|p − T| ≤ 2·want = 1954 u`,
strictement sous 4000. Le compteur ne PEUT pas monter, et il ne monte pas. Les deux courses ont
atteint `PHYSEND`, 3410 mesures, 31/31 animations.

### 2.2 Le résultat — il réfute l'hypothèse

`ROOM-JELLY` = fraction de l'étendue de la fenêtre parcourue en UNE frame (plus haut = plus
saccadé ; plafond dérivé 0.5, soit 6 frames par oscillation, 10 Hz).

| chaîne | pilotage | CAP ON | CAP OFF | |
|---|---|---|---|---|
| chestL | accel | 0.7264 | **0.8275** | EMPIRE |
| chestL | jerk | 0.7809 | 0.3969 | améliore |
| chestL | tilt | 0.3498 | **0.4016** | EMPIRE |
| chestL | leftright | 0.2298 | 0.1839 | améliore |
| chestR | jerk | 0.7636 | **0.9711** | EMPIRE |
| chestR | leftright | 0.5114 | **0.7455** | EMPIRE |
| chestR | accel | 0.5473 | **0.6568** | EMPIRE |
| chestR | updown | 0.4819 | 0.3832 | améliore |

Le pire du fichier est **inchangé** : `botstrapL` sous `jerk` lit `1.0000` (période 2.00 frames,
le maximum structurel) dans les DEUX états. Le nombre de couples (chaîne, pilotage) au-dessus du
plafond dérivé passe de 40 à 38 sur 110 — du bruit.

**Conclusion, et elle est nette : retirer entièrement le plafond d'excursion ne supprime pas le
broutement de la poitrine ; sur les stimuli les plus forts il l'aggrave.** Le plafond n'est donc pas
le mécanisme de `flesh-jelly`. Une cause de plus est éliminée, avec son chiffre — après le min doux
hors boucle (14e passe) et la fréquence propre du ressort (§2.4).

### 2.3 Et il coûte cher en échange

| chaîne | tipvar max CAP ON | CAP OFF | écart |
|---|---|---|---|
| chestL | 0.3809 | 0.6219 | **+63 %** |
| chestR | 0.3754 | 0.5274 | **+40 %** |
| botstrapL | 0.4255 | 0.7357 | **+73 %** |
| goggles | 0.4936 | 0.5567 | +13 % |
| **les 18 autres chaînes** | — | — | **identiques à 10⁻⁴** |

+63 % d'amplitude sur une poitrine que l'owner vient de juger « quasiment parfaite sur les
mouvements subtils », pour un broutement au mieux inchangé : ce n'est pas un arbitrage, c'est une
perte sèche. **Le plafond à 656/660 est le bon état, et c'est celui que l'autre worker a rétabli
en régénérant** (§5).

### 2.4 Ce que la même mesure élimine AUSSI, par le calcul

La 15e passe posait à l'owner un arbitrage entre (a) « c'est le régime propre du ressort » et (b)
« c'est encore un limiteur ». **(a) se tranche sans lui, à la main :**

`jak-hd-physics.gc:1729-1731` — `w = 2π·stiffness/√mass`, `k2 = w²·dt²`. Poitrine :
`stiffness = 1.45`, `mass = 1.45`, `dt = 1/60` → `w = 7.567 rad/s`, **`k2 = 0.0159`**.
Pour Verlet non amorti, `cos ω = 1 − k2/2 = 0.99205`, donc `ω = 0.1261 rad/frame` et
**période propre ≈ 49.8 frames (1.2 Hz)**.

Le broutement mesuré est à 3.2–3.9 frames (15–19 Hz), soit **treize fois** la fréquence propre.
Ce n'est pas le ressort. L'arbitrage (a) est retiré : il ne faut pas alourdir ni amortir la
poitrine, et l'amplitude que l'owner apprécie n'a pas à être payée.

**Ce qui reste, et qui n'a jamais été testé :** la poitrine est en contact avec un volume du corps
**à peu près toutes les frames** (`contact_frames = 17893` sur ~19 000, tableau du cycle
précédent), alors que `flip = 0` — elle n'entre ni ne sort, elle est POSÉE sur la surface en
permanence. Sa position écrite est donc dictée frame par frame par la capsule du buste ANIMÉE, pas
par le ressort. C'est le seul mécanisme restant qui tourne à la fréquence de la frame, et c'est le
prochain à mesurer.

---

## 3. DANGER À SIGNALER — CETTE COURSE PEUT EMPOISONNER LE PLANCHER DE MOUVEMENT

La gate `FLOOR` garde un maximum courant par chaîne dans `motion-floor.txt`, et **la référence ne
descend jamais**. Si le validateur est exécuté sur un tableau issu de l'état CAP OFF, la référence
de `chestL` passe de 0.3809 à 0.6219 — une valeur que le moteur au plafond 656 **ne peut plus
atteindre**. La gate bloquerait alors tous les builds corrects suivants, y compris ceux que
l'owner approuve.

**Je n'ai donc PAS lancé le validateur sur la course CAP OFF**, et le tableau est écrit sous un nom
qui n'est pas celui que la gate lit :

* `keira-room-table.CAP656.txt` — l'état livrable (copie du tableau du cycle précédent)
* `keira-room-table.CAP4000.txt` — l'expérience, hors du chemin de la gate

C'est la même classe de piège que le « ratchet running-max qui se mange lui-même » : une référence
qui monte sur une mesure d'expérience condamne la production.

---

## 4. PREUVE OBTENUE GRATUITEMENT — LA COLLISION CHAÎNE↔CHAÎNE EST BRANCHÉE

Les DIRECTIVES (5e passe) exigeaient : « nombre de corrections chaîne↔chaîne effectivement
appliquées, par paire. Zéro correction sur une paire déclarée = la collision chaîne↔chaîne n'est
pas branchée. » Aucun compteur par paire n'existe (vérifié : les seuls sites d'écriture de
`*phys-dg*` sont les lignes 873, 902, 936, 1014, 1166, 1263, 1325, 1907, 2112, 2115, 2146, 2366 —
la poussée de collision, ligne 1168-1170, n'incrémente rien).

**Le A/B le prouve sans compteur.** Je n'ai changé QUE le plafond d'excursion de `chestL`/`chestR`.
Ont bougé : `chestL` (+63 %), `chestR` (+40 %), **`botstrapL` (+73 %)** et **`goggles` (+13 %)`.
Les **18 autres chaînes sont identiques à 10⁻⁴**.

`botstrapL` et `goggles` ne partagent aucun paramètre avec la poitrine. Le seul chemin par lequel
un changement de la poitrine peut les atteindre est la collision contre les sphères `lBoob`/`rBoob`
portées par les joints **simulés** — et l'ordre des chaînes le permet : `chestL` = 7, `chestR` = 8,
`goggles` = 9, `botstrapL` = 12, et l'écriture dans `skel bones` est **dans** la boucle par chaîne
(`jak-hd-physics.gc:1665` ouvre, `2383` ferme ; écriture `2249-2382`).

C'est un contrôle positif au sens de la SPEC : on injecte une modification d'un côté, on voit le
chiffre monter de l'autre. **La collision chaîne↔chaîne est branchée et mesurable.**

**Réserve honnête, et elle compte** : `chestL` (7) est résolue AVANT `chestR` (8), donc `chestL`
teste contre le `rBoob` **d'auteur** pendant que `chestR` teste contre le `lBoob` **simulé**. Les
deux seins ne sont pas dans le même état. C'est un candidat direct pour l'asymétrie gauche/droite
observée depuis le début (0.66 contre 1.04 à l'époque ; aujourd'hui `baseline` de `ROOM-JELLY`
0.1754 à gauche contre 0.4281 à droite, soit un facteur 2.4 pour des paramètres identiques).

---

## 5. `goggles-chest` — LE VOLUME PROPRE DES LUNETTES NE CONTIENT PAS LES LUNETTES

Mesuré sur le mesh (`decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb`, primitives
`keira-lens-large`, `keira-glasses`, `keira-gogglestrap` = 531 sommets) contre les volumes que la
chaîne `goggles` porte réellement (`radii=196,150`) :

| volume du lien | % des sommets de lunettes DEHORS | dépassement max |
|---|---|---|
| sphère `gogglesBase` r=196 | **98 %** | 1458 u = **0.356 m** |
| sphère `gogglesMid` r=150 | **93 %** | 1302 u = **0.318 m** |

Et, **à la pose bind, 47 sommets de lunettes sont DÉJÀ à l'intérieur des sphères de sein** :
`lBoob` 28 sommets (profondeur max 129 u), `rBoob` 19 sommets (max 108 u).

**Le mécanisme est complet :** le solveur maintient hors des seins une bille de 150 u posée sur
`gogglesMid`, pendant que les verres — huit fois plus loin du joint — traversent librement. Le
plancher de pose modèle, calculé sur cette bille (`floor0 = 0` contre les seins puisqu'elle est à
722 u de leur centre, soit 400 u DEHORS), ne protège rien du recouvrement réellement sculpté.
`meshpen` lit zéro, honnêtement, contre un volume qui ne représente pas l'objet.

C'est la même faute que les capsules inter-quartiles (§6), sur le lien au lieu de l'obstacle :
**un rayon d'ÉPAISSEUR sert de volume de COLLISION.** Les lunettes sont une pièce large et plate ;
aucune sphère posée sur leur joint ne peut les représenter — l'élargir engloberait la tête et les
seins, et `phys-vol-floor` déclarerait alors tout libre, ce qui aggrave au lieu de corriger
(l'owner l'a déjà vécu : `708 → 712 →` « ça clipe toujours »).

**Ce que ça impose, et c'est une correction de GÉNÉRATION, pas un rayon à monter :** le lien des
lunettes a besoin d'une **capsule** ajustée par couverture, comme les obstacles du corps, orientée
le long de la monture. Le générateur sait déjà le faire depuis aujourd'hui (`cover_perp_radius`) —
il ne l'applique qu'aux obstacles, pas aux volumes de lien.

**Je ne l'ai pas implémenté** : `physics_keira_gen2.py` est tenu par l'autre worker (§1) et y écrire
en même temps aurait détruit son travail. Le chiffre et le chemin sont ici pour qu'il soit fait sans
avoir à le rechercher.

---

## 6. `straps-elastic` — LES CAPSULES DU CORPS ÉTAIENT DES MOYENNES, PAS DES COUVERTURES

Mesuré sur les 24 capsules **livrées** (géométrie identique à `phys-collide-depth`, pose bind) :

```
capsules livrées : rayon == moyenne inter-quartile  ->  50 % à 85 % des sommets DEHORS
sphères livrées  : rayon == p95 de couverture       ->   0 % à  8 % dehors
```

**Aucune capsule ne descend sous 50 % de sommets hors du volume** — c'est la signature exacte d'une
moyenne inter-quartile. Sur l'élastique du bas du crop top (98 sommets, tous possédés par `chest`) :

| capsule | distance à l'axe (moy/max) | rayon à cette hauteur | déficit | % hors |
|---|---|---|---|---|
| `neck→chest` | 723 / 1002 | 556 | **+167 / +481 u (0.117 m)** | 92 % |
| `chest→main` | 871 / 1189 | 671 | +200 / +518 u (0.126 m) | 96 % |

**34 % de l'élastique est hors de TOUS les volumes déclarés.** Une bretelle qui passe là ne traverse
rien au sens du moteur : `meshpen = 0` est vrai et ne prouve rien.

C'est ce que l'autre worker corrige en ce moment (`cover_perp_radius`, p95 restreint au segment) —
je ne le refais pas. Contrôle de sa correction, calculé sur son fichier régénéré : l'élastique passe
de **34 % hors de tout à 0 %**. La correction porte.

**Réserve à vérifier avant qu'elle parte** : 12 des 48 bouts de capsule n'ont pas assez de sommets
qui se projettent dans leur segment (`SPAN-EMPTY`) et gardent donc leur rayon inter-quartile —
dont `neck`, les deux `Lshoulder`/`Rshoulder`, `hips` sur les capsules de cuisse. Ces bouts-là
restent des moyennes.

---

## 6bis. ALERTE — LA CORRECTION DE COUVERTURE, TELLE QU'ELLE EST DANS L'ARBRE, RÉGRESSE `pant-calf`

**Elle ne doit pas partir en build en l'état, et aucune gate ne l'arrêterait.**

`phys-vol-floor` (`jak-hd-physics.gc:744-751`) déclare un volume **LIBRE** pour un lien dès que
`floor0 >= 2·rl` : ce qui est entièrement dedans au repos n'a plus aucune surface devant lui et ne
sera **plus jamais repoussé**. Un volume plus gros ⇒ `floor0` plus grand ⇒ des liens basculent.

Calculé à la pose bind avec l'algèbre exacte du moteur, sur le fichier régénéré
(md5 `ce78207640f541bfcb0efa7c2bfa93dd`), capsules de mollet `Lankle→Lknee` 411/329 → **861/538** :

| lien | rl | 2·rl | volume | floor0 AVANT | floor0 APRÈS | |
|---|---|---|---|---|---|---|
| `pantflapL.0` | 429 | 858 | `Lankle→Lknee` | 614.4 | **943.0** | **AVALÉ** |
| `pantflapR.0` | 443 | 886 | `Rankle→Rknee` | 620.4 | **958.4** | **AVALÉ** |
| `anklestrapL.0` | 225 | 450 | `Lankle→Lknee` | 298.9 | **699.4** | **AVALÉ** |
| `anklestrapR.0` | 225 | 450 | `Rankle→Rknee` | 287.9 | **701.7** | **AVALÉ** |
| `toestrapL.0` | 188 | 376 | `Lankle→Lknee` | 0.0 | 346.9 | à 29 u |
| `kneeflapL.0` | 244 | 488 | `Lankle→Lknee` | 246.3 | 457.7 | à 30 u |

`pantflapL/R` sont **exactement le défaut ouvert** « le bas du pantacourt est avalé à l'intérieur
des mollets, comme si son pantacourt s'arrêtait aux genoux ». Après la modification, le pan de
tissu **ne peut plus jamais être repoussé hors du mollet** : le défaut passe d'ouvert à
structurellement irréparable.

Algèbre, pour que la borne ne soit pas un avis : `floor0 = rr + rl − d`, avec `d = 184.3` et
`t = 0.504` constants (la capsule ne bouge pas par rapport au pan — `LpantFlap`, `Lanklestrap`,
`lKneeFlap` et `Lankle` ont tous le même parent `Lknee`). L'enfouissement est donc `rr >= rl + d`.

> **CONDITION DE NON-RÉGRESSION, DÉRIVÉE, PAS ESTIMÉE :**
> `capsule Lankle Lknee radius <= 689` préserve le pantacourt ; **`<= 547` préserve aussi les
> sangles de cheville.** Proposé dans l'arbre : **861**. Valeur d'avant : 411.
> `547` reste **+33 %** de couverture par rapport à 411 — le gain de la correction est en grande
> partie conservé, sans qu'aucun lien simulé ne devienne invisible.

Ce que ça révèle comme invariant manquant, et c'est la vraie leçon : **un volume d'obstacle ne doit
jamais avaler entièrement un lien simulé à la pose du modèle.** C'est une propriété que le
générateur peut vérifier — il connaît les deux côtés — et de la même famille que l'exclusion
chaîne↔elle-même. Tant qu'elle n'est pas posée, chaque élargissement d'obstacle peut éteindre
silencieusement une chaîne.

**Ce qui n'est PAS touché, vérifié aussi** : `chestL`/`chestR` (marge 348 u sur 644, `chest→main`
et `neck→chest` donnent `floor0 = 0`) et `goggles` (0 volume actif avant comme après). L'acquis
« quasiment parfait » de la poitrine ne bouge pas, et `goggles-chest` n'est pas un problème de
`phys-vol-floor` — ce qui confirme le §5 par un autre chemin.

**Pourquoi je n'ai pas appliqué la borne moi-même.** Elle vit dans `physics_keira_gen2.py`, tenu par
l'autre worker (§1), et il mesurait au moment où j'ai eu le chiffre. Y écrire aurait détruit son
travail ou déchiré sa course — la faute même que la §1 dénonce. La borne est ici, dérivée et prête,
et elle s'applique en une ligne.

---

## 7. `pant-calf` — L'INSTRUMENT N'EXISTE PAS, ET LES DEUX COMPTEURS EXISTANTS SONT AVEUGLES

Les DIRECTIVES (11e passe, point 4) exigent `ROOM-SIDE: chain=<nom> inside_frames=<n>` = 0.
**`ROOM-SIDE` n'existe nulle part** : deux occurrences dans tout le dépôt, toutes deux dans
`.autoport/DIRECTIVES.md` (lignes 641 et 666). Rien dans `phys-room.gc`, rien dans
`jak-hd-physics.gc`, rien dans `physics_room_table.py`.

Les deux compteurs qu'on serait tenté de lire à sa place ne voient pas le défaut :

* **`buried`** (`*phys-dg*` index 9, incrémenté `jak-hd-physics.gc:1325`) compte « le lien est
  entièrement dans un volume **à sa pose de MODÈLE** ». Il lit **`pantflapL = 0` et
  `pantflapR = 0`** — la chaîne même que l'owner voit avalée. Il mesure la pose d'auteur, pas la
  position écrite.
* **`meshpen`** lit `-0.0565` sur `pantflapR` : c'est la **sentinelle « aucun contact »**
  (`PHYS-NOCONTACT`), pas une pénétration nulle. Le pan de tissu ne touche jamais aucune capsule de
  jambe de toute la course.

**Le défaut est donc réel et non mesuré** : le point du lien flotte librement, hors de tout volume,
pendant que la géométrie qu'il porte traverse le mollet. C'est le même écart que pour les lunettes
(§5) — on teste un point, l'owner voit une surface.

### Et le mécanisme, lui, est identifié — c'est la TOLÉRANCE de `phys-vol-floor`, pas le rayon

Le chiffre de la §6bis le dit, et il vaut aussi pour l'état **actuellement livré** (mollet 411) :

```
pantflapL, pose du modèle, contre Lankle→Lknee r=411/329 :
    floor0 = 614.4 u     (soit 15,0 cm)
    2·rl   = 858 u
```

Le pan n'est donc pas « avalé » au sens de la bascule (`614 < 858`, il reste contraint) — mais la
tolérance que le moteur lui accorde est **614 unités, quinze centimètres**. Autrement dit : rien ne
le repousse tant qu'il n'a pas pénétré de 15 cm dans le mollet. **C'est exactement la profondeur à
laquelle un pan de pantacourt disparaît dans une jambe**, et c'est ce que l'owner décrit depuis la
11e passe.

`phys-vol-floor` est bâti sur une règle juste — « ce qui est déjà dedans au repos y reste » — mais
son argument est la profondeur du lien au repos, or **le lien du pantacourt EST au repos près de
l'axe de la jambe** : sa tolérance est donc presque toute l'épaisseur du mollet. La règle correcte
serait « ce qui est déjà dedans au repos n'a pas le droit d'aller **plus profond** », c'est-à-dire
un plancher pris sur la profondeur d'auteur **de la frame courante** et non une franchise fixe
dérivée du rayon.

**Je ne l'ai pas implémenté, et je dis pourquoi plutôt que de le faire à moitié :** ce changement
touche `phys-vol-floor`, donc les 22 chaînes d'un coup, et durcir un plancher RETIRE du mouvement —
c'est un point de GROUPE B au sens du plan de reprise, qui exige d'être mesuré contre
`motion-floor.txt` avant d'être conservé. Le mesurer demande une course de salle, et l'autre worker
en tenait une (§1). Un changement de solveur livré sans sa mesure est précisément ce qui a coûté
les cycles précédents. Il est décrit ici avec son chiffre, prêt à être mesuré en une course.

---

## 8. SPEC 1bis « ILS S'ENTRECHOQUENT » — GÉOMÉTRIQUEMENT HORS DE PORTÉE AUJOURD'HUI

La SPEC exige « nombre de contacts `chestL`↔`chestR` > 0 sur `jerk`, et pénétration nulle ».
Mesuré sur le rig et le mesh, à la pose bind :

```
centre du volume lBoob  (600.6, 7962.1,  998.7)   r = 321.8
centre du volume rBoob (-603.5, 7952.4,  998.5)   r = 311.2
distance entre centres                   = 1204.1 u  (0.294 m)
r(lBoob) + r(rBoob)                      =  633.0 u
VIDE À COMBLER                           =  571.1 u  (0.139 m)
```

Rien n'exclut la paire (`phys-col-own?` ne l'écarte pas, aucun filtre `chains=`/`at=` dans les
données, `phys-vol-floor` ne peut pas la déclarer libre puisque `floor0 = 0` au repos) : **elle est
testée, et elle ne se déclenche jamais.** Raison mesurée : les cinq pilotages appliquent la MÊME
accélération monde aux deux chaînes, qui se déplacent donc **en parallèle**, jamais l'une vers
l'autre. Aucun pilotage n'est antisymétrique.

**Dit sans de-scope :** cette exigence de la SPEC ne peut pas être satisfaite par un réglage. Il
faut soit un pilotage antisymétrique dans la salle (une rotation du buste sur son axe, qui envoie
les deux seins en sens opposés), soit accepter qu'elle reste ouverte — et c'est un arbitrage, pas
un oubli. Je la signale plutôt que de la laisser passer pour « mesurée à zéro ».

---

## 9. DÉRIVE DE DONNÉES — `radius=4000` COMMITÉ SANS DOCUMENTATION

`git show fcd84c374b` (2026-08-12 01:53, message « checkpoint automatique du constructeur »)
contient **une seule modification fonctionnelle** :

```
-chain chestL ... radius=656  ... radii=656
+chain chestL ... radius=4000 ... radii=4000
-chain chestR ... radius=660  ... radii=660
+chain chestR ... radius=4000 ... radii=4000
```

Ce 4000 n'est **ni** produit par le générateur (aucune occurrence de `4000` dans
`physics_keira_gen2.py`), **ni** demandé par `keira-owner-tuning.txt`, **ni** couvert par une
mesure : le tableau publié à 01:46 porte `raddrop = 18894`, donc il décrit l'état 656. Un
checkpoint automatique a ramassé une expérience laissée sur le disque et l'a livrée.

Trois choses en découlent :
1. la gate `TUNING` ne l'a pas vue — elle vérifie que les réglages de l'owner sont PRÉSENTS, pas
   qu'aucune valeur non documentée ne s'est ajoutée ;
2. l'A/B de la §2 mesure précisément cet écart, et conclut que 656 est le bon état ;
3. **le règlement de fond est le bon** : un fichier généré doit être égal à
   `générateur + keira-owner-tuning.txt`, et toute autre valeur est une dérive. La régénération de
   l'autre worker à 07:14 l'a d'ailleurs effacée toute seule — ce qui est la bonne propriété, et
   la raison pour laquelle rien ne doit jamais être réglé en éditant `physics_chains.txt` à la main.

**Bug latent à corriger quand le fichier sera libre** : `physics_keira_gen2.py` appelle
`apply_owner_tuning.py` **sans argument** (ligne ~1032), donc toujours sur le chemin par défaut.
Une régénération avec `--out` ailleurs produit un fichier **sans les réglages de l'owner** tout en
affichant « [tuning] appliqué ». C'est exactement le mécanisme qui a effacé ses réglages deux fois.

---

## 9bis. CE QUE CE CYCLE A CORRIGÉ — UN VERROU D'INSTANCE UNIQUE SUR L'ORCHESTRATEUR

La cause de la §1 est identifiée et elle est en amont de tout : **deux orchestrateurs tournent sur
ce dépôt**, PID `705057` et `924374`, et chacun lance son worker sur la même phase.

`.autoport/orchestrator.py` prend désormais un **verrou exclusif `flock`** sur
`.autoport/.orchestrator.lock`, avant toute lecture d'état, et une seconde instance refuse de
démarrer en nommant le PID qui tient le dépôt.

`flock` et pas un fichier de PID : le noyau relâche le verrou à la mort du processus, donc un
orchestrateur tué laisse le dépôt libre — un verrou périmé qui bloque tout serait un défaut pire
que celui qu'on corrige.

**Contrôle positif, exécuté, pas raconté** — deux processus, le second doit refuser :

```
--- première instance  : RESULT ACQUIRED
--- seconde instance   : Un orchestrateur tourne deja sur ce depot (PID 1053344).
                         Verrou : /home/emeric/code/jak-project/.autoport/.orchestrator.lock
                         RESULT BUSY
GATE: premier=ACQUIRED, second=BUSY  ->  True
```

Les deux orchestrateurs en cours ne sont **pas** affectés : Python lit le fichier à l'import, donc
la modification prend effet au prochain démarrage. Je n'ai tué aucun des deux — l'un porte le
travail non commité de l'autre worker.

C'est la règle de l'owner appliquée à la lettre : « quand une perte se répète, on la rend impossible
au point de PRODUCTION, pas détectable au point de contrôle. »

---

## 10. CE QUI RESTE OUVERT — AUCUN DE-SCOPE SILENCIEUX

* Les **cinq défauts** d'`owner-defects.txt` restent ouverts. Je n'en ai fermé aucun et je n'ai
  touché à aucune ligne : c'est sa parole qui les ferme.
* **`flesh-jelly`** : deux causes éliminées (plafond d'excursion, §2 ; fréquence propre du ressort,
  §2.4), une désignée et non testée (le contact permanent avec la capsule du buste, 17 893 frames
  sur ~19 000 avec `flip = 0`).
* **`goggles-chest`** : mécanisme établi et chiffré (§5), correction non implémentée — fichier tenu
  par l'autre worker.
* **`straps-elastic`** : cause établie et chiffrée (§6), correction en cours par l'autre worker,
  contrôle calculé (34 % → 0 %), réserve `SPAN-EMPTY` sur 12 bouts de capsule.
* **`pant-calf`** : l'instrument exigé n'existe pas et les deux compteurs voisins sont aveugles (§7).
* **`hair-angles`** : non traité ce cycle. Rien de neuf à en dire, et je préfère l'écrire que de
  meubler.
* **Les trois autres nombres de l'évaluation « colliders dérivés du mesh »** (coût par frame sur le
  Redmi, coût de la déformation du mesh skinné, quatre niveaux de précision) ne sont toujours pas
  mesurés.
* **La salle ne tourne pas sur le device.** Toutes les mesures de ce rapport sont x86.
