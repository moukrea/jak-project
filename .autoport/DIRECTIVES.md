# DIRECTIVES — contrat courant, autorité supérieure au prompt de tâche

Ce fichier est **relu à chaque étape** par le manager de phase ET par chaque sous-agent
(`autoport-researcher`, `autoport-implementer`, `autoport-tester`). Il est **plus récent** que le
prompt qui t'a lancé : en cas de conflit, **c'est lui qui gagne**, et tu le signales dans ton
rapport au lieu de suivre une consigne périmée.

Première action obligatoire, avant tout outil de travail : lire ce fichier, puis le contrat de
périmètre qu'il désigne ci-dessous.

---

## 2026-08-14 03:40 — CORRECTION : MA DIRECTIVE DE 03:10 S'APPUYAIT SUR UNE SERIE TRONQUEE

**Ce que j'ai écrit à 03:10 est FAUX et retiré.** J'ai gravé en priorité absolue « le solveur draine
linéairement, il n'exécute pas son équation », en relayant une série de **15 échantillons** alors que
la trace en contient **149**. Sur la trace complète :
  - **le rebond EXISTE** : 4,7 % (chestL) / 9,5 % (chestR) — contre les 31 % qu'exige sa §26 ;
  - les deux suspects désignés (boucle de 26 projections, poussées contre le buste) sont **réfutés**
    comme mécanisme commun : 20 chaînes sur 22 gardent 80 à 140 % par demi-cycle dans la même boucle.
Le worker a démenti sa propre conclusion ; je l'avais amplifiée dans le contrat sans vérifier le
nombre d'échantillons. **Une série tronquée ressemble exactement à une décroissance linéaire.**

**LE VRAI DEFAUT, MESURE : L'EXCURSION SORT DE L'ENVELOPPE DE SA SPEC.**
`B0` relevé sur le rig (`PHYSBONE len=977.13`), le déplacement d'apex vaut **1,10 à 1,41 B0** sous
les cinq pilotages, contre **`HardMaxApexDisplacement = 0.50 B0`** au preset de sa §38. **Les cinq
dépassent, y compris le plus doux** — de deux à près de trois fois. Et hors enveloppe le ressort de
corde devient non linéaire (69 % du linéaire), donc la réponse cesse d'être proportionnelle au
stimulus : c'est très exactement « un pudding sur lequel on tape au moindre mouvement », et sa §22
plafonnait déjà l'excursion pour cette raison.

**PRIORITE : ramener l'excursion sous 0.50 B0** (§22, §38), par la saturation `tanh` de sa §21 —
`D = D_max·tanh(|D|/D_max)`, une saturation douce, jamais un écrêtage brutal (§37). Le rebond se
recalibre ENSUITE vers 31 %, une fois qu'on opère dans la zone linéaire du ressort.

## [RETIRE 03:40 — conclusion issue d'une serie tronquee] 03:10 — le solveur n executerait pas son equation

Mesure du worker à 02:42, série brute `PHYSRING c=7 l=0` (chestL, maillon libre) :

    81.7  65.3  49.5  34.8  21.7  11.1  6.8
    écarts successifs : 16.4  15.8  14.7  13.1

**Une QUANTITÉ constante part chaque frame.** Un amortissement visqueux retirerait une FRACTION
constante — l'exponentielle donnerait `23.3 16.7 11.0 6.1`. Et **aucun rebond** là où sa §26 en exige
un à 31 %, alors que les paramètres livrés encodent `ζ = 0.3500` exact.

**Donc le solveur ne résout pas `M·ẍ + C·ẋ + K·x = M·a_drive`.** Il draine linéairement. C'est un
limiteur ou un écrêtage qui vide un montant fixe par frame, pas une force. Ça explique d'un coup
« pas d'impression de masse », « pas de gravité » et « ça suit aucune logique » : la forme même de
la décroissance n'est pas physique, quelles que soient les valeurs qu'on y met.

**PRIORITÉ ABSOLUE : trouver et retirer le terme qui soustrait une quantité fixe par frame.** Tant
qu'il est là, aucune calibration — pas même la §24 vérifiée à 2,300 Hz — ne peut produire le
comportement décrit par la spec. Preuve de sortie exigée : la série `PHYSRING` doit montrer une
décroissance à **fraction** constante et un rebond à ~31 % (§26).

**RAPPEL DE TAILLE, troisième mesure consécutive à la hausse :**

    4525 → 4622 → 4596 → 4651 → 4767 lignes

Le moteur est revenu à son point de départ (4798 avant la bascule). La directive de 22:37 demandait
une boucle **petite**. Chaque terme ajouté qui n'est pas dans `SPEC-breast-softbody.md` §23 doit être
justifié par une mesure, ou retiré. Un solveur qui draine linéairement pendant qu'on lui ajoute des
correctifs est exactement le ré-empilement qu'on a décidé d'arrêter.


## 2026-08-14 01:00 — MA GATE BLOQUAIT SA SPEC. LA SPEC GAGNE. ARBITRAGE DU SUPERVISEUR.

Fait constaté dans `keira-owner-tuning.txt` :

    # chain chestL stiffness=2.7696 damping=0.1686   (RETIRE : cassait FLOOR-WEAK sur chestR)
    # chain chestR stiffness=2.8804 damping=0.1753   (RETIRE : idem)

La calibration **exacte de sa §24** (2.300 Hz, vérifiée par recalcul) a été appliquée puis
**retirée parce qu'elle faisait échouer `FLOOR-WEAK`** — une gate que J'AI écrite. Le rapport le dit
sans détour : « la porter à 2.30 Hz divise la flèche par 3.65 et casse le plancher ».

**ARBITRAGE : la spécification de l'owner prime sur toutes mes gates, sans exception.**

Et `FLOOR-WEAK` est ici invalide pour trois raisons cumulées, toutes déjà consignées :
  1. **Elle est calée sur un état qu'il n'a jamais approuvé.** J'ai établi à 21:50 qu'aucun
     échantillon approuvé n'existe sur ce personnage. Le plancher protège donc du pudding.
  2. **Elle encliquette un maximum courant** — piège `floor-ratchet-mirror` : sur la paire miroir
     `kneeflapL`/`kneeflapR`, paramètres identiques, planchers stockés 0.0884 contre 0.0174,
     facteur 5,1.
  3. **Elle protège une flèche que la spec INTERDIT.** Ses §2 et §9 : le modèle debout livré est
     l'équilibre 1 g, `AdditionalStandingSag = 0`. Une flèche statique divisée par 3,65 n'est pas
     une perte de mouvement, c'est le **retour à la pose d'auteur qu'il exige**. Le plancher
     mesurait un affaissement qui n'a pas le droit d'exister.

**CONSÉQUENCES, à appliquer :**
  - Réappliquer la calibration §24 sur `chestL`/`chestR` (2.30 Hz vertical, asymétrie §32 ±3–5 %),
    et ne plus jamais la retirer au motif d'une de mes gates.
  - `FLOOR` et `FLOOR-WEAK` sont **suspendues sur toute chaîne couverte par la spec**, jusqu'à être
    recalées sur les cibles de la spec elle-même (§16 §17 §18 §22 donnent les amplitudes attendues
    par régime) plutôt que sur un maximum observé.
  - Toute gate qui contredit une ligne de `SPEC-breast-softbody.md` est fausse par construction :
    on corrige la gate, jamais la spec.

**RÈGLE GÉNÉRALE QUI EN DÉCOULE** — à vérifier avant d'ajouter une gate, en plus des trois questions
déjà en vigueur : *« que se passe-t-il si l'owner demande précisément ce que cette gate interdit ? »*
Une gate calée sur l'état courant transforme le statu quo en obligation.


## 2026-08-13 23:35 — SPEC POITRINE DE L'OWNER : `SPEC-breast-softbody.md`. AUTORITAIRE.

Il a écrit une spécification complète (Keira + Maia, 39 sections chacune, presets chiffrés). Elle
est dans le dépôt à la racine : **`SPEC-breast-softbody.md`**. À appliquer **À LA LETTRE** pour la
poitrine, et à **TRANSPOSER** pour tout le reste (cheveux, mèches, lanières, lunettes) : même
architecture de solveur, valeurs propres à chaque organe.

### ELLE ME CORRIGE SUR UN POINT, ET IL FAUT LE DIRE

J'ai écrit à 22:40 que « la pose au repos doit ÉMERGER de la gravité, pas être ramenée à un dessin ».
**C'est faux, et sa spec dit l'inverse — §2 et §9 :** le modèle debout livré EST l'équilibre 1 g à
100 %, `AdditionalStandingSag = 0`, et « no additional gravity sag shall be applied merely because
the simulation is active ». Le rappel vers la pose d'auteur n'est donc PAS le défaut.

### CE QUI EST VRAIMENT LE DÉFAUT, ET SA SPEC LE NOMME EXACTEMENT — §3

    a_drive = (g_local - g_ref) - a_torso + a_angular

Notre moteur pilote par `fl = -couple · acc`, où `acc` est la **dérivée seconde de la POSE ANIMÉE**
(`jak-hd-physics.gc:3409`). Ce n'est aucun des trois termes de la spec. Conséquence directe et
mesurable : **un à-coup d'animation produit un coup**, ce qui est mot pour mot « un pudding sur
lequel on tape très fort au moindre mouvement ». La spec exige au contraire une réponse à
la **réorientation de la gravité** et à l'**accélération du torse** — deux grandeurs qui valent zéro
quand le personnage est immobile, et qui varient continûment, pas par à-coups.

C'est LE correctif de fond, et il est petit : remplacer le terme moteur. Pas 274 fonctions.

### CE QUE LA SPEC APPORTE ET QUI N'EXISTE NULLE PART CHEZ NOUS

  - **Fréquences propres par axe** (Keira 2.30 / 2.50 / 2.65 Hz — la verticale la PLUS LENTE),
    ζ = 0.35, premier rebond 31 %, stabilisation 1.0–1.5 s. Des cibles physiques, vérifiables,
    qui ne viennent pas de moi.
  - **Conservation de volume** 98–101 % (96–102 % en transitoire) — et explicitement PAS une mise à
    l'échelle affine globale : la racine bouge peu, le distal se déforme le plus.
  - **Saturation en `tanh`** pour combiner translation et rotation, au lieu d'un écrêtage brutal.
  - **Anisotropie** (vertical 1.00 / AP 0.90 / latéral 0.82 / torsion 0.72).
  - **Gradient racine→pointe** `w(r) = r^1.6…2.0`, 30 % de volume fortement ancré, **aucune frontière
    d'attache nette** — exactement le contraire de notre « 124 sommets sur une seule charnière ».
  - **Indépendance gauche/droite** avec variation ±2–5 %, et collision sein↔sein (restitution 0.06)
    et sein↔thorax (0.02) : l'énergie devient déformation, pas rebond.
  - **≥120 Hz effectifs**, 2 sous-pas à 60 FPS, 3–4 sur impact ; rebase sur téléport/cinématique/
    discontinuité — « artificial transforms must not generate physical breast impulses ».

### TRANSPOSITION AUX CHEVEUX (ce qu'il demande explicitement)

Même solveur, valeurs propres : pilotage par `(g_local - g_ref) - a_root + a_angular`, jamais par la
dérivée seconde de l'animation ; fréquence propre et ζ calibrés par mèche ; gradient racine→pointe
sans frontière nette ; saturation `tanh` ; collision qui dissipe au lieu de rebondir.

### CE QUE ÇA CHANGE POUR LE TRAVAIL EN COURS

L'interdiction de régler reste. Mais la cible n'est plus à inventer : **elle est chiffrée section par
section dans son fichier.** Toute mesure de la salle doit désormais se lire contre une ligne de cette
spec, et toute valeur publiée doit citer la section dont elle relève.


## 2026-08-13 22:40 — LE MODÈLE EST FAUX, PAS SES RÉGLAGES. C'EST LA SEULE TÂCHE.

Owner : « Physique = simulation, gravité, masse, élasticité, déformation, solidité… J'ai
l'impression là que tu fais juste bouger des trucs, tu simules rien du tout. »

**Il a raison, et c'est lisible dans le solveur** (`jak-hd-physics.gc:3399-3520`). Ce qui est
intégré n'est pas la position d'un cheveu : c'est un **ÉCART À LA POSE ANIMÉE** (`*phys-ox/oy/oz*`,
rappelé vers 0). Chaque maillon est un ressort qui ramène l'os au dessin de l'animateur, excité par
la **dérivée seconde de cette pose** multipliée par `couple` (`fl = -couple · acc`, ligne 3452).

    position finale  =  pose animée  +  petit écart amorti

**Un seul défaut explique les quatre plaintes**, ce ne sont pas quatre chantiers :
  - « pas d'impression de masse » → l'équilibre est la POSE ANIMÉE, pas une position déterminée par
    la gravité. Les cheveux ne pendent pas, ils reviennent à leur dessin.
  - « ça suit pas la gravité » → la gravité n'est qu'une perturbation autour de cette pose ; elle ne
    peut pas faire tomber la mèche, seulement la décaler.
  - « un pudding sur lequel on tape très fort AU MOINDRE MOUVEMENT » → littéral : le pilotage est
    l'ACCÉLÉRATION de l'animation. Un mouvement petit mais sec donne un pic d'accélération, donc un
    coup. Le moteur ne suit pas le mouvement, il réagit à ses à-coups.
  - « hystérésis » → l'écart intégré a sa propre mémoire et revient lentement à zéro.

**CE QU'IL FAUT À LA PLACE — et c'est la seule tâche jusqu'à nouvel ordre :**
une vraie simulation de particules. Des points portant une MASSE, tombant sous la GRAVITÉ, reliés à
leur parent par une CONTRAINTE DE DISTANCE, arrêtés par des COLLISIONS. Dans un tel système la pose
au repos **émerge** de la gravité : les cheveux pendent parce qu'ils tombent, pas parce qu'un
ressort les ramène à un dessin. L'animation d'auteur n'entre plus que par l'ANCRE (la racine suit le
crâne) — plus par un rappel sur chaque maillon.

**INTERDIT tant que ce modèle n'est pas en place** : tout réglage de `stiffness`, `damping`,
`gravity`, `maxangle`, tout nouvel opérateur de repesage, toute nouvelle gate. Ils portent tous sur
un modèle qui ne peut pas produire ce qu'il demande.

**Rappel de proportion** : le moteur qui couvrait TOUT le casting faisait 1 241 lignes. Celui-ci en
fait 4 798 pour un personnage et fait moins bien. La nouvelle boucle doit être **petite** — si elle
ne tient pas dans quelques centaines de lignes, c'est qu'on ré-empile.


## CORRECTION OWNER 2026-08-13 21:50 — J'AI INVENTÉ DEUX VALIDATIONS QUI N'ONT JAMAIS EU LIEU

Verbatim : « je t'ai jamais dit que la branche parquée je la validais… il y a eu des bons trucs dans
son historique, l'état final était à chier. Aussi, à 14h et quelques, j'ai pas du tout validé les
mèches fines, elles étaient elle aussi victimes de l'effet pudding. C'était mieux qu'avant dans le
sens où enfin les pointes bougeaient plus que le milieu, mais c'est quand même du pudding dégueulasse
[…] Tu comprends tout de travers pas étonnant que ça avance pas ! »

**ERREUR 1 — j'ai écrit « verdict owner positif » sur l'état 08-06 de la branche parkée.**
Il ne l'a jamais dit. Il dit l'inverse : des bons morceaux dans l'HISTORIQUE, un état final « à
chier ». On mine des mécanismes ponctuels, on ne restaure pas un état, et **aucun commit de cette
branche ne porte une approbation de sa part**. Ne plus jamais attribuer un verdict à l'owner à
partir d'un message de commit écrit par moi ou par un worker.

**ERREUR 2 — TOUT MON « CONTRÔLE APPARIÉ » ÉTAIT FAUX.**
J'ai lu « les mèches fines sont vraiment pas mal » comme une validation, et j'ai bâti dessus toute
la méthode : cible = « la valeur mesurée sur `lbang`/`rbang` ». **Il n'a jamais validé les fines.**
Elles étaient *moins pires* (les pointes bougeaient enfin plus que le milieu), mais du pudding quand
même. Donc :
  - il n'existe **AUCUN échantillon approuvé** sur ce personnage ;
  - `lbang`/`rbang` ne sont **PAS** une cible : viser leurs 84–96 frames, c'est viser du pudding ;
  - toute directive de la journée formulée comme « combler l'écart vers `lbang` » est **ANNULÉE**.

**LA CIBLE, DANS SES MOTS, ET IL N'Y EN A PAS D'AUTRE :**
« de la physique cohérente et réaliste qui donne une impression de masse, de gravité, qui suit le
mouvement » — et le défaut : « un pudding sur lequel on tape très fort **au moindre mouvement** ».

Ce que ça dit techniquement, et qui est mesurable sans inventer de cible :
  1. **La réponse est disproportionnée au stimulus.** Un petit mouvement produit un ballottement
     violent. Grandeur : rapport amplitude de réponse / amplitude du mouvement moteur, par régime.
     Des cheveux réels suivent avec un gain < 1 et du retard ; ici on a un gain qui explose.
  2. **Pas d'impression de masse** = pas d'inertie : la chaîne saute au lieu de traîner.
  3. **Pas de gravité** = elle ne pend pas, elle ne retombe pas.
  4. « **au moindre mouvement** » = le seuil de déclenchement est trop bas, la chaîne est excitée par
     du bruit d'animation.

**Ces quatre points remplacent toutes les cibles chiffrées de la journée.**


## RETOUR OWNER 2026-08-13 21:30 — VERDICT DUR, ET IL A RAISON. CHANGEMENT DE MÉTHODE.

Verbatim : « les cheveux de sa nuque et ses mèches (fines et grosses) c'est du pudding, ça suit
aucune logique […] ça suit pas une logique de gravité, ça n'a pas l'air d'avoir une masse
particulière, c'est claqué complet ! […] beaucoup d'hystérésis pour tous les cheveux […] j'ai envie
de la désactiver parce que c'est horrible ! Il serait temps que tu progresses […] ça va faire deux
semaines […] C'est dingue que tu fasses pas bien mieux en étant concentré sur un seul personnage que
quand tu bossais sur tous les personnages en même temps ! »

**FAIT MESURÉ QUI RÉPOND À SA DERNIÈRE PHRASE — l'accumulation EST le défaut.**

    08-06, physique sur TOUT LE CASTING, (état 08-06, AUCUN verdict owner) : 1 241 lignes, UN solveur
    aujourd'hui, Keira HD seule, verdict « claqué complet »     :  4 798 lignes, 274 fonctions

Le moteur a quadruplé en se dégradant. C'est le même mal que la branche parkée avait fini par
attraper, et je l'ai reproduit en trois jours sur un moteur « propre ».

**RÉGRESSION QUE JE N'AVAIS PAS VUE : j'ai cassé l'échantillon qu'il approuvait.**
À 14:45 les mèches FINES étaient « vraiment pas mal ». Elles sont maintenant du pudding elles aussi.
Leurs paramètres sont **inchangés depuis 14:37** (stiffness 1.3089, damping 0.0784, gravity 0.1592,
maxangle 137.29) — donc ce n'est pas un réglage, **c'est le MESH** : la campagne de repesage visant
les grosses mèches a dégradé les fines. Mon contrôle apparié est mort, tué par moi.

**CE QUE LA BRANCHE PARKÉE APPREND (historique 08-05/08-06, lu, pas copié).**
Le solveur qui marchait tenait dans **une seule fonction** (`phys-slot-step!`, ~570 lignes) et
paramétrait chaque chaîne par des grandeurs PHYSIQUES, pas par des réglages abstraits :
  - `*phys-comega*` = **2·π·f** — la chaîne est décrite par sa **fréquence propre**, pas par une
    raideur brute. C'est ce qui donne un mouvement pendulaire cohérent et une impression de masse.
    Aujourd'hui la donnée livre `stiffness`/`damping`/`mass` crus : « ça n'a pas l'air d'avoir une
    masse particulière » est la conséquence directe.
  - `*phys-cinertia*`, `*phys-cstretch*`, `*phys-cmaxrad*` (cône de débattement en radians)
  - `*phys-cfric*` — **friction de contact**. L'HYSTÉRÉSIS qu'il décrit est exactement ce que produit
    une friction ou un limiteur qui s'accroche sans relâcher : la réponse dépend de l'histoire et ne
    revient pas. **PREMIÈRE PISTE À MESURER, avant tout le reste.**
  - `*phys-canim*` (0 garder / 1 remplacer / 2 exciter) + `*phys-cexcite*` — l'articulation propre
    avec l'animation d'origine.

**DIRECTIVE : on arrête d'ajouter.** Aucun nouvel opérateur, aucune nouvelle gate, aucun nouveau
suppresseur tant que les trois points suivants ne sont pas traités :
  1. **HYSTÉRÉSIS** — identifier et mesurer tout terme dépendant de l'historique (friction, limiteur
     qui latche, encliquetage d'angle). Grandeur : la chaîne revient-elle à la même pose après un
     aller-retour identique ? Un écart non nul EST l'hystérésis.
  2. **RÉGRESSION DES MÈCHES FINES** — retrouver le mesh du build qu'il validait à 14:45 et mesurer
     ce que le repesage leur a fait. Le mesh de 14:45 est reconstructible depuis git.
  3. **MASSE ET GRAVITÉ** — repasser la description des chaînes en grandeurs physiques
     (fréquence propre, inertie) comme dans le moteur qui marchait.

**Et il redemande pour la deuxième fois de fouiller l'historique parké. C'est fait, ci-dessus.**
Il reste 4 439 commits : continuer à le miner est un travail à part entière, pas une note de bas de
page.


## RETOUR OWNER 2026-08-13 14:45 — IL CORRIGE MON DIAGNOSTIC, LIRE AVANT TOUTE ACTION

Verbatim : « Les grosses mèches sont pas bonnes hein, une partie de la géométrie reste encrée et ça
casse ! J'ai pas l'impression que t'a saisi ce feedback ! Et la gélatine c'est plus du pudding, c'est
pas trop lent et mou, c'est vraiment pas cohérent... On dirait les mouvements quand on tape sur un
pudding, pas des mouvements naturels de cheveux ! »

**Deux corrections de MA part d'analyse, pas deux nouveaux défauts.**

1. `hair-anchored-geo` — la passe précédente a fermé la **couture** (`tear` 82→0) alors qu'il parle de
   la **géométrie figée**. Mesure sur le mesh livré : backhair cov 0.726–0.856, lmidhair 0.781,
   rmidhair 0.775 → 14 à 27 % des sommets pesés `head 100%`, soudés au crâne. Correctif d'ASSET
   (repesage du donneur), et la cible est le **profil de bande de mélange de lbang**, pas cov=1.0.

2. `hair-pudding` — j'avais diagnostiqué une fréquence (trop lent). **C'est faux.** Il décrit une
   forme de réponse : une masse qui ballotte après un choc, pas une chaîne qui balance. Mesure neuve
   exigée `ROOM-RINGDOWN` : (a) oscillations libres après l'arrêt du stimulus, (b) retard de phase
   racine→pointe. Repère LOCAL. **Ne pas dériver ça d'une formule d'amortissement supposée du
   solveur : on le lit dans la salle.**

**19:40 — DEUX DE MES DIRECTIVES ÉTAIENT FAUSSES, LE WORKER L'A MESURÉ. ELLES SONT RECTIFIÉES.**

**(a) « Retard racine→pointe ≥ 5 » : cible ANNULÉE, elle venait d'un artefact d'instrument.**
La fenêtre de recherche vaut `dmax = round(tapp/2)`. `lbang` mesure `tapp=10`, donc `dmax=5`, et
rapporte `lag12=5` ET `lag23=5` — **exactement au bord**. Le retard n'est déterminé que modulo une
demi-période : 5 sur une fenêtre ±5 est congru à 0. Autrement dit **`lbang mono=yes` et
`backhair lag12=0` sont LA MÊME MESURE**. Recalculée sur ±14, la corrélation de `lbang` monte encore
là où la fenêtre livrée s'arrête (+5 : 0,82 · +7 : 0,89 · +9 : 0,93) — le « 5 » est le bord, pas un
pic. J'ai fixé une cible à la valeur que mon propre instrument ne pouvait pas dépasser : c'est le
piège `never-fit-a-parameter-to-the-instrument`, et c'est moi qui l'avais écrit.
**Ce qui reste valable** : la durée de ballottement (84–96 frames), stable et cohérente entre
courses. Et `backhair` a un vrai pic net à d=0 (0,97) — **son mouvement en bloc est, lui, bien mesuré**.

**(b) « Injecter un os » au sens ajouter en bout : FAUX pour ces trois chaînes.**
Il n'y a **aucune géométrie au-delà de la pointe** (orphan 3,8/4,8/4,5 %, `tail_m` 0,0000 — `backhair`
est même mieux couverte que `lbang` à 4,9 %). Un os ajouté en bout aurait été un **maillon inerte**.
Le vrai défaut mesuré : les trois grosses mèches portent **60 à 93 % de leur masse pesée sur UN SEUL
segment libre**, contre **35–37 % sur `lbang`/`rbang`** que l'owner approuve. C'est ÇA le pudding, et
c'est la grandeur qui discrimine — pas le retard de phase.
La bonne opération est la **subdivision** (`subdiv`) : le joint de pointe recule à la médiane de
masse, la position libérée devient la nouvelle pointe, la rampe partage la géométrie 50/50, les
longueurs se somment exactement. `lbang`/`rbang` partaient de 3 joints avec de la géométrie à
piloter — leur cas n'était pas le même, et j'ai généralisé leur recette à tort.

**NOUVELLE CIBLE, mesurable et non bornée par la fenêtre** : part de masse du segment le plus lourd
ramenée de 60–93 % vers **35–37 %**, et durée de ballottement dans 84–96 frames.

**17:40 — LE BLOCAGE DU §6 EST LEVÉ. L'INJECTION EST LA SEULE CHOSE À FAIRE MAINTENANT.**

Le rapport avait raison sur le fait et tort sur la fatalité : `decompiler_out/jak2` et `jak3`
avaient bien disparu — **c'est mon nettoyage disque de 12:17 qui les a supprimés**, pas une panne du
pipeline. Les ISO étaient intactes ; `rip_levels` était à `false` dans la config jak2, ce qui est la
raison pour laquelle un simple `decomp2.sh` ne les rendait pas.

**État vérifié à 17:37, fichier par fichier :**
  - `rip_levels: true` remis dans `decompiler/config/jak2/jak2_config.jsonc`
  - décompilation jak2 relancée : **finie en 110 s**, 401 rips `*-highres-lod0.glb`
  - **11 donneurs sur 11** présents parmi les entrées déclarées de `build_enhanced_models.sh`
  - les fr3 sources exigées sont là : `out/jak2/fr3/lintcstb.fr3`, `introcst.fr3`, `out/jak3/fr3/ldax.fr3`
  - `GAME.fr3` cuit (25 438 408 octets) **sauvegardé** dans
    `/home/emeric/.autoport-scratch/meshbak-20260813-1737/` avant toute cuisson

Donc `build_enhanced_models.sh` ne sortira plus en deux lignes, **le repesage peut être cuit et le
4e os peut être posé**. Plus aucune raison de reporter : c'est le seul travail du prochain cycle.
Rappel du plafond : `PHYS-LINKS 4`, ces chaînes vont de 3 à 4, rien à toucher.

**CAUSE STRUCTURELLE TROUVÉE 16:35 — ARRÊTER DE RÉGLER L'AMORTISSEMENT SUR CES TROIS CHAÎNES.**

La salle le dit elle-même à l'exécution : `mono=n/a(1 lien libre)` sur `backhair`, `lmidhair`,
`rmidhair`, contre `lag01/lag12/lag23` sur `lbang`/`rbang`. Confirmé par la donnée livrée, le
compte de `radii` = un rayon par maillon :

    backhair   radii=358,442,360           3 articulations  -> 1 maillon libre (root verrouillé)
    lmidhair   radii=222,145,363           3 articulations  -> 1 maillon libre
    rmidhair   3 articulations                              -> 1 maillon libre
    lbang      radii=112,104,154,189       4 articulations  -> l'onde peut descendre
    rbang      4 articulations                              -> l'onde peut descendre

**UN MAILLON LIBRE EST UN BLOC PAR CONSTRUCTION.** Il n'y a rien derrière lui pour être en retard :
aucune valeur d'amortissement, de raideur ou de masse ne peut créer une propagation racine→pointe
sur une chaîne qui n'a qu'un seul maillon qui bouge. Le « tout part en bloc » que l'owner appelle
pudding **n'est pas un réglage mal choisi, c'est l'absence du degré de liberté**.

**LES CHAÎNES QU'IL REJETTE SONT EXACTEMENT CELLES QUI N'ONT PAS REÇU D'OS.** `keira-hd-inject-joints.txt`
déclare pourtant une ligne pour chacune (`backhair backHair2 backHair3`, `lmidhair Lmidhairb
Lmidhairc`, `rmidhair Rmidhairb Rmidhairc`) — mais `lbang`/`rbang` sont passés à 4 articulations et
ces trois-là sont restées à 3. **L'injection n'a pas abouti pour elles : c'est ÇA le travail.**

C'est la même classe que `knee-tabs`, que l'owner a fermé, et que le passage de `lbang` à 4 maillons.
Recette connue, ~45 min, plafond `PHYS-LINKS 4` (`jak-hd-physics.gc:125`) — ces chaînes vont de 3 à
4, donc **sous le plafond, aucune constante à toucher**.

Et ça referme les DEUX défauts prioritaires d'un coup : `hair-pudding` (l'onde pourra descendre) et
`hair-anchored-geo` (le repesage accompagne l'injection, cov 0.73–0.86 → profil de `lbang` 0.977) —
mêmes chaînes, même correctif d'asset.

**PREUVE EXIGÉE, à l'exécution, pas dans un commentaire** : `radii=` à 4 valeurs sur les trois
chaînes, la salle qui cesse d'écrire `1 lien libre`, et `ROOM-RINGDOWN` qui remonte dans la bande
approuvée (84–96 frames, retard racine→pointe ≥ 5).

**PRÉCISION 16:05 — MA FORMULATION ÉTAIT AMBIGUË ET ELLE A PRODUIT UNE COPIE.**
J'ai écrit « la cible est la valeur mesurée sur lbang/rbang ». Le worker a copié le PARAMÈTRE
(`damping=0.0784` recopié tel quel sur trois chaînes de raideur et de masse différentes). Ce n'est
pas ce que je voulais dire, et c'est le piège `never-fit-a-parameter-to-the-instrument`.

**La cible est la RÉPONSE MESURÉE, jamais le réglage qui la produit** :
  - durée de ballottement 84–96 frames (lbang 84, rbang 96)
  - retard racine→pointe 5–8 frames, l'onde DESCEND (lag12/lag23 ≥ 5)
Chaque chaîne doit atteindre CETTE RÉPONSE avec un amortissement **dérivé de sa propre géométrie**
(raideur, masse, longueurs). Copier le nombre d'une autre chaîne n'est pas une dérivation.

**CE QUE LA COPIE A DONNÉ, MESURÉ** — elle marche sur deux chaînes et rate la troisième :
    lmidhair  50 → 102 frames, retard 1 → 6   ATTEINT
    rmidhair  50 →  85 frames, retard 1 → 8   ATTEINT
    backhair  21 →  28 frames, retard 1 → 1   **TOUJOURS DANS LA BANDE REJETÉE**
`backhair` est la plus raide (1.80 contre 1.50 et 1.31) et la plus lourde : le même amortissement
n'y produit pas la même réponse. **C'est la mèche dont l'owner se plaint le plus, et elle n'est pas
corrigée.** À dériver pour elle-même, contre la réponse cible ci-dessus.

**LE CONTRÔLE APPARIÉ.** Il approuve les mèches fines, il rejette les grosses — même moteur, même
salle. Toute cible chiffrée de ces deux défauts est désormais la valeur **mesurée sur lbang/rbang**,
jamais un nombre choisi. Les grosses mèches portent encore `stiffness=1.80 damping=0.18 mass=0.90`
(ronds génériques) là où lbang porte des valeurs dérivées : elles n'ont jamais reçu la passe.


## PÉRIMÈTRE ACTIF (2026-08-11)

SCOPE-SERIAL: 4
<!-- Bump ce numéro UNIQUEMENT pour un vrai changement de périmètre : il invalide
     immédiatement la tentative en cours (gate SYNC). Corriger une coquille ou
     reformuler ne doit jamais coûter une tentative. -->

* Phase : `Grecharged-secondary-motion` — physique secondaire. Branche : **`physics-keira-clean`**.
* **DÉPART PROPRE, ACTÉ LE 2026-08-11 — MAIS RÉVISÉ LE 2026-08-12 (INVENTAIRE AVANT DE RASER).**
  Owner : « parke tous les commits propres à la physique sur une branche dédiée et repars propre ».
  J'ai alors écrit « `physics-attic-2026-08-11` n'est pas une base de travail, on ne la consulte
  pas ». **C'était une erreur, et l'owner l'a relevée le 2026-08-12** :

  > « Ce qui me troue sur ton travail actuel sur Keira (les cheveux), c'est que dans l'historique de
  > ce qu'on a parké il y a des commits où la physique des cheveux de Keira fonctionnait bien. Je
  > comprends pas pourquoi tu t'en sors pas alors que tu travailles UNIQUEMENT sur Keira et
  > UNIQUEMENT sur le modèle HD, alors que sur cette branche on traitait tous les personnages. »

  Il a raison. Repartir propre voulait dire **jeter l'empilement de suppresseurs**, pas jeter les
  **solutions acquises sur des semaines**. En réduisant le moteur à 51 lignes et en tout
  re-dérivant, j'ai perdu du travail qui marchait — et j'ai passé trois jours à redécouvrir à la
  main des choses probablement déjà résolues là-bas (rotation du dernier maillon, couverture de
  peau, dimensionnement des volumes).

  **NOUVELLE CONSIGNE : `physics-attic-2026-08-11` SE MINE — COMME RÉFÉRENCE, JAMAIS COMME SOURCE.**
  Précision de l'owner (2026-08-12) : « attention, faudra t'assurer que le travail de la branche
  parkée ne te pollue pas, et parcourir son **historique** ! La branche est là à des fins de
  référence et d'investigation, autant en profiter. »

  Méthode, dans cet ordre :
  1. **Parcourir l'HISTORIQUE, pas seulement la pointe.** Les commits où les cheveux fonctionnaient
     sont *dans* l'historique, avant que l'empilement de suppresseurs ne les étouffe. `git log -p`
     sur les fichiers de chaînes de cheveux, en cherchant les états intermédiaires, pas l'état final.
  2. **Lire, comprendre, formuler la LEÇON** — ordre d'écriture des joints, verrouillage de racine,
     couverture des joints par chaîne, traitement du premier et du dernier maillon.
  3. **Réimplémenter dans le moteur propre**, à la main, avec la mesure qui l'atteste et le plancher
     qui la protège. **Aucun `git checkout`, aucun cherry-pick, aucun copier-coller de bloc.** Un
     morceau importé sans être compris ramènerait avec lui le contexte qui l'entourait — et c'est ce
     contexte-là (clamps, hystérésis, gels) qui avait tué le mouvement.
  4. **Rapporter ce qui a été trouvé et ce qui a été écarté**, avec le hash du commit consulté. Une
     leçon tirée de l'attic se cite comme n'importe quelle autre preuve.

  Autrement dit : la branche parkée est un **carnet de laboratoire**, pas un dépôt de pièces
  détachées. On y cherche *pourquoi ça marchait*, on ne récupère pas *le code qui marchait*.
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

## DÉCISIONS PRISES PAR LE SUPERVISEUR (2026-08-11 16:00) — elles ne remontent PAS à l'owner

L'owner : « règle les problèmes ! Tu devrais les régler tout seul au lieu de les enterrer ou de
mettre un pansement dessus… t'es censé être assez smart pour savoir quand il faut régler des
soucis, c'est ton rôle. » Il a raison : deux questions que j'avais fait remonter étaient les
miennes à trancher. Elles sont tranchées, avec la mesure qui les ferme.

**DÉCISION 1 — Volumes qui se recouvrent : PRIORITÉ, pas solveur conjoint.**
Le résidu d'inversion (180) vient de deux volumes qui se renvoient le lien de l'un à l'autre. Un
solveur conjoint est la réponse théorique, mais c'est une refonte du cœur pour un défaut qui a une
cause simple. On impose donc un **ordre déterministe** : quand un lien est contraint par plusieurs
volumes dans la même frame, le volume du **corps** l'emporte sur celui d'une chaîne, et entre deux
volumes de corps, le **parent dans le rig** l'emporte. Un seul volume décide par frame et par lien,
les autres sont ignorés — pas moyennés, ignorés.
→ **Cible : `ROOM-INVERSIONS residual = 0`**, contrôle positif toujours ≥ 4× le résidu. Si la
priorité ne suffit pas, on le dit avec le nombre au lieu de le laisser à 180.

**DÉCISION 2 — Poitrine : on remonte la vivacité, et l'allongement se tient par la contrainte.**
J'avais baissé le couplage de 1.45 à 1.20 pour tuer l'allongement sur les à-coups, et le mouvement
est tombé de 0.66–1.04 à 0.38–0.39 : j'ai payé le défaut avec la qualité que l'owner venait
d'apprécier. C'est un pansement. La vraie règle est la sienne, ancienne : **rotation autour de
l'ancre à longueur invariante**.
→ La contrainte de longueur devient **dure** : projection itérée jusqu'à ce que l'écart relatif de
chaque maillon soit ≤ 1 %, plafonnée à un nombre d'itérations fixe, et l'écart résiduel est publié.
→ **Une fois cette contrainte en place**, le couplage de la poitrine remonte à **1.45** et
l'allongement doit rester ≤ 3 % sur les pilotages `jerk` et `accel`.
→ **Mesure exigée** : `ROOM-STRETCH: max=<r> chain=<nom> drive=<mode>` par course. Au-dessus de
3 %, c'est la contrainte qui est en cause, pas le couplage — on ne rebaisse pas le couplage.

**DÉCISION 3 — Réponse non linéaire des grosses mèches : on chasse le seuil, on ne règle pas autour.**
« Trop statiques sur les mouvements faibles, trop hystériques sur les brusques » = il y a une marche
dans la courbe de réponse. Le moteur contient au moins deux seuils (détection d'intention, zone
morte du test de côté).
→ **Mesure exigée** : `ROOM-RESPONSE: chain=<nom> in=<amplitude d'excitation> out=<amplitude de
pointe>` sur au moins 6 amplitudes croissantes par chaîne. La courbe doit être **monotone et sans
marche** ; toute marche > 2× entre deux points voisins désigne le seuil, qui est alors soit retiré,
soit remplacé par une transition continue.

**CE QUE LE SUPERVISEUR A DÉJÀ FAIT LUI-MÊME :** retiré ses quatre capsules estimées à la main
(le rig en génère 24, mesurées), retiré son override de rayon de poitrine (le générateur produit
désormais des volumes **placés** — rayon 183 avec offset, au lieu d'une sphère de 708 sur le joint),
posé la gate `TUNING`, déplacé la réapplication des réglages dans le producteur, et remis la
livraison en marche (patience bornée + respawn des deux maillons).

## LE VERDICT DU 2026-08-11 16:15 — MES MESURES SONT VERTES, SON ÉCRAN NE BOUGE PAS

> « Les petites mèches fines sont toujours complètement hystériques dès que ça bouge. Les seins
> s'étirent sur les mouvements brusques et ne bougent pas assez sur les mouvements soft. Aucun
> mouvement en fonction de l'inclinaison (quand elle se penche en avant pour souder), zéro gravité
> sur ses seins du coup. Honnêtement je vois pas d'amélioration. C'est vraiment très décevant. »

**Vérifié d'abord : le build CONTIENT bien les corrections.** Données livrées `gravity=0.45` sur la
poitrine, marqueur d'auto-collision présent dans le CGO arm64 bâti à 15:44, versions des deux packs
qui changent à chaque build donc l'extraction se fait. Ce n'est pas un problème de livraison.

**Donc c'est la mesure qui ne vaut rien, et voici pourquoi.** Le test d'admissibilité de la SPEC §7
dit : « si ce chiffre est vert et que l'owner voit encore le défaut, qu'est-ce qui l'expliquerait ?
S'il y a une réponse, la mesure ne vaut rien. » La réponse est là, dans le tableau :

    seins, mouvement de pointe par pilotage
      accel 0.3490 · jerk 0.3614 · leftright 0.3606 · updown 0.3535 · tilt 0.3889

Cinq pilotages violents — translations, à-coups, inclinaison à 60° — et **la réponse est plate à
0.35 partout**. Un système physique correct répond DIFFÉREMMENT à une secousse et à une inclinaison
soutenue. Une réponse identique quel que soit le stimulus veut dire que **ce qu'on mesure n'est pas
piloté par le stimulus** : c'est le bruit de l'animation qui domine, et la salle le compte comme du
mouvement. Le `tilt` à 0.3889 n'est pas une réaction à la gravité, c'est la même valeur que les
autres.

**Ce que ça implique, et c'est la seule chose à faire ensuite :**

1. **La salle doit mesurer la RÉPONSE, pas l'agitation.** Pour chaque pilotage, publier l'amplitude
   de pointe **rapportée à l'amplitude du stimulus**, et la valeur **sous animation seule** (aucun
   pilotage) comme ligne de base à soustraire. Un pilotage dont la réponse ne dépasse pas la ligne
   de base n'a rien excité. `ROOM-RESPONSE: drive=<mode> stimulus=<a> tip=<b> baseline=<c> gain=<b-c/a>`
2. **L'inclinaison doit produire un DÉPLACEMENT SOUTENU, pas une variance.** Mesurer la position
   moyenne de la pointe à 0° et à 60°, dans le repère de l'ancre : l'écart entre les deux EST la
   réponse gravitaire. Aujourd'hui rien ne le mesure, et c'est exactement ce que l'owner regarde
   quand elle se penche pour souder. `ROOM-GRAVSAG: chain=<nom> at0=<p> at60=<p> sag=<d>` — un
   `sag` nul sur une chaîne de famille A avec `gravity>0` est un échec.
3. **La raideur vers la pose du modèle écrase la gravité.** C'est l'explication mécanique de « zéro
   gravité » : le ressort qui ramène à la pose du modèle est un rappel POSITIONNEL permanent, la
   gravité une force constante bien plus faible. Pour la famille A, la SPEC dit que la gravité agit
   sur la dynamique **et reprend quand elle n'est plus debout** : la cible du ressort doit donc
   **s'incliner avec l'ancre**, de sorte qu'à 60° l'équilibre lui-même soit déplacé. Sans ça, aucun
   réglage de `gravity=` ne produira jamais quoi que ce soit.
4. **Mèches fines hystériques malgré `SELFCOL run=0`** : le compteur est honnête mais il ne mesure
   qu'une cause. Mesurer la réponse (point 1) sur `lbang`/`rbang` : si le gain est très supérieur à
   celui des autres chaînes aux mêmes stimuli, la cause est le rapport raideur/masse, pas la
   collision — et se corrige alors par la courbe de réponse, pas par une correction de collision.

**Aucun APK ne repart tant que `ROOM-GRAVSAG` n'est pas non nul sur la poitrine.** C'est la première
chose qu'il regarde, et c'est la seule qui n'a jamais été mesurée.

## TOUTES LES ANIMATIONS, ET LIVRAISON AU FIL DE L'EAU (owner 2026-08-11 16:15)

> « Faut tester vraiment toutes les animations qu'utilise le perso (ici Keira) tout au long du jeu,
> pas quelques unes ! » — « Et n'oublie pas de livrer au fil de l'eau comme je t'ai demandé maintes
> et maintes fois. »

**1. COUVERTURE : 31 sur 31, pas 18.** Les 13 écartées appartiennent à ses variantes (Fire Canyon,
Lava Tube, Village 2 et 3), dont le rig porte 94 joints là où le porteur de physique en a 96. C'est
un obstacle technique, pas une raison de ne pas tester : **la salle spawne déjà les six art-groups**,
elle doit donc jouer chaque animation **sur son propre art-group** au lieu de les filtrer contre un
seul rig. La gate refuse désormais tout `skipped > 0` — une raison écrite ne transforme pas un
de-scope en couverture.

**2. LIVRAISON AU FIL DE L'EAU — je l'ai enfreinte aujourd'hui.** J'ai écrit « aucun APK ne repart
tant que ROOM-GRAVSAG n'est pas non nul ». C'était moi qui remettais un filtre que l'owner a
explicitement retiré : il veut le build **même quand ce n'est pas vert**, pour juger de ses yeux et
renvoyer des retours — c'est la boucle la plus rapide qu'on ait, et elle a produit tous les vrais
diagnostics de la journée. **Aucune condition de qualité ne retient un build.** Le seul motif de
non-publication reste technique : APK anormalement gros (espace mort) ou build échoué.

## SEPTIÈME PASSE — LE GRADIENT EST INVERSÉ, ET L'INSTRUMENT NE PEUT PAS LE VOIR (2026-08-11 16:30)

> « Les mèches fines sont toujours hystériques, par contre on dirait qu'entre la racine et les
> pointes c'est zone de guerre et les pointes bougent quasi pas, au lieu d'un dégradé progressif des
> racines aux pointes (idem sur le reste des cheveux). Les seins sont encore plus immobiles sur les
> mouvements faibles, du coup c'est d'autant plus bizarre sur les mouvements brusques parce que là
> ça bouge. Toujours rien sur la gravité quand elle se penche. (Pas sûr que ça ait une valeur mais
> je te fais le feedback quand même.) »

**Ce retour a la plus grande valeur de la journée**, et il décrit quelque chose que le tableau est
structurellement incapable de mesurer.

**1. LE GRADIENT EST INVERSÉ.** La SPEC §2 exige : racine soudée, mouvement qui **croît vers la
pointe**. Il observe l'inverse — les deux extrémités tenues et le milieu qui part en vrille. Or
l'instrument publie **UN SEUL nombre par chaîne** (`tipvar`). Une chaîne dont le milieu s'agite et
dont la pointe est figée produit exactement le même `tipvar` qu'une chaîne saine : c'est une
deuxième mesure non discriminante, de la même famille que celle rejetée ce matin.
→ **`ROOM-GRADIENT: chain=<nom> anim=<nom> link0=<v> link1=<v> … linkN=<v>` par chaîne.** La suite
doit être **croissante** de la racine vers la pointe. Toute chaîne dont un maillon intermédiaire
dépasse la pointe est un échec, quel que soit son `tipvar`. Chercher d'abord si le **dernier maillon
est intégré ET écrit** : une pointe recollée sur la pose de l'animation donne exactement cette
silhouette.

**2. LES SEINS : ENCORE PLUS IMMOBILES SUR LES MOUVEMENTS FAIBLES, MOBILES SUR LES BRUSQUES.** C'est
la confirmation du seuil, et il s'est **aggravé**. Une réponse qui démarre à partir d'un certain
niveau d'excitation est un seuil, pas un réglage. La courbe `ROOM-RESPONSE` (6 amplitudes
croissantes) doit être monotone **et partir de zéro sans marche**.

**3. GRAVITÉ : la formulation écrite dans le moteur est la bonne** — `g_eff = R_ancre⁻¹·g − R_bind⁻¹·g`,
soit l'écart entre la gravité d'aujourd'hui et celle de la pose de référence (la pose du modèle est
déjà une pose sous gravité, sculptée debout). Buste droit : les deux termes s'annulent, l'équilibre
reste la pose du modèle. Buste incliné : l'écart apparaît. **Elle n'était pas dans le build qu'il a
testé** — elle doit l'être dans le suivant, et `ROOM-GRAVSAG` doit le prouver.

**Le motif de fond, pour la troisième fois aujourd'hui : il décrit une FORME et je publie un
SCALAIRE.** Un nombre par chaîne ne peut pas décrire un dégradé le long de la chaîne, pas plus
qu'une variance ne pouvait décrire un affaissement sous gravité. Avant d'ajouter une mesure, se
demander de quelle nature est le défaut décrit — amplitude, forme, ou déplacement soutenu — et
mesurer cette nature-là.

## DIXIÈME PASSE — BUILD 5f49ca-c7ff53, LE PREMIER QU'IL AIT VRAIMENT TESTÉ (2026-08-11 18:00)

> « Les seins s'allongent de nouveau sur les mouvements brusques et le sag est invisible sur
> l'inclinaison toujours. Les mèches c'est mieux, mais c'est toujours un peu hystérique, le milieu
> est plus hystérique (bouge beaucoup plus) que les pointes, c'est pas censé ! »

**1. L'ALLONGEMENT EST REVENU — c'était le test, et il tranche.** J'avais écrit dans le BUILD-INFO :
« si l'étirement revient, c'est la contrainte de longueur qui cède, et je ne rebaisserai PAS le
couplage ». Il est revenu avec `couple=1.55`. **La contrainte de longueur n'est donc pas dure.**
→ Projection itérée jusqu'à ce que l'écart relatif de chaque maillon soit ≤ 1 %, plafond fixe
d'itérations, écart résiduel publié : `ROOM-STRETCH: max=<r> chain=<nom> drive=<mode>`, cible ≤ 3 %
sur `jerk` et `accel`. **Le couplage reste à 1.55** : c'est le symptôme qu'on corrige, pas la
qualité qu'il apprécie.

**2. LE SAG RESTE INVISIBLE ALORS QUE LA GRAVITÉ A ÉTÉ TRIPLÉE (0.45 → 1.30).** Ce n'est donc plus
un réglage : la gravité de la famille A n'atteint pas la poitrine. Le chiffre le disait déjà —
`chestL` 0.0156 contre `backhair` 0.1149, sept fois moins — et tripler l'entrée n'a rien changé de
perceptible. Piste : la poitrine est une chaîne à **UN SEUL maillon**, donc son affaissement passe
entièrement par une rotation autour de l'ancre, bornée par l'angle max et par la raideur. Vérifier
(a) que le terme de gravité est bien appliqué aux chaînes à un maillon, (b) qu'aucun angle max ne le
plafonne, (c) que `ROOM-GRAVSAG` est exprimé dans une unité comparable entre une chaîne d'un maillon
et une chaîne de trois — sinon on compare deux choses différentes.

**3. « LE MILIEU BOUGE BEAUCOUP PLUS QUE LES POINTES » — MA MESURE DIT LE CONTRAIRE.** `ROOM-GRADIENT`
donne link0=0.0000 · link1=0.2240 · link2=0.3846, donc croissant. Son œil dit l'inverse. **C'est ma
mesure qui est fausse, et je vois pourquoi** : elle mesure le déplacement de chaque maillon dans le
repère du MONDE. Un maillon hérite alors de tout le mouvement de son parent — une pointe accrochée à
un milieu qui part en vrille affiche un grand chiffre **sans bouger d'un pouce par rapport à son
parent**. C'est la même faute que « différencier la position au lieu de la sortie ».
→ **Le gradient doit être mesuré RELATIVEMENT AU PARENT** : déviation angulaire de chaque maillon par
rapport à son parent, ou déplacement exprimé dans le repère de l'ancre. C'est cette suite-là qui doit
croître de la racine vers la pointe. Republier `ROOM-GRADIENT` sur cette base, et la comparer à
l'ancienne dans le rapport — l'écart entre les deux est la mesure de mon erreur.

## DEUX APPAREILS, À NE JAMAIS CONFONDRE (owner 2026-08-11)

> « Mélange pas le build qui run sur le Redmi qui est à ta disposition, et moi sur mon Honor que tu
> vois pas du tout, qui teste les builds sur jak-builds. »

* **Redmi `eae4df44`** = l'instrument du superviseur. On y installe, on y mesure, on y prouve. Ce
  qu'il affiche ne dit **rien** de l'owner.
* **Honor de l'owner** = invisible. Il récupère les builds publiés sur jak-builds et les teste
  lui-même. Aucune trace, aucune télémétrie, aucun moyen de savoir ce qu'il fait ni quel build il a —
  d'où le tag `<commit6>-<pack6>` qu'il peut lire dans `files/.custom_pack_stamp_jak1`.

Conséquence corrigée : l'auto-constructeur différait une installation « parce que l'owner est
peut-être en train de tester », en se fondant sur l'app au premier plan **du Redmi**. Raisonnement
faux — c'était une mesure du superviseur. Aucune décision ne se déduit de l'activité de l'owner :
elle n'est pas observable.

## ONZIÈME PASSE — LE MEILLEUR RETOUR DE LA JOURNÉE (build 19:53, 2026-08-11 21:15)

> « Les seins c'est maintenant quasiment parfait sur les mouvements subtils, bon sag, ça bouge de
> façon cohérente. Mais lors de mouvements brusques il y a un effet d'étirement et un peu gelée où
> ça change de taille (plus petit, plus gros, plus long, plus court, écrasé), c'est pas cohérent !
> Mais c'est vraiment 100x mieux qu'avant. Pour les mèches fines c'est vraiment pas mal, mais
> certains maillons mériteraient un traitement pour éviter de créer des angles extrêmes qui mettent
> en lumière le lack of géométrie — soit une subdivision intelligente, soit une atténuation sur les
> angles extrêmes. Pour les grosses mèches, idem. Ses bretelles c'est vraiment pas mal du tout mais
> ça clipe toujours avec l'élastique orange du bas de son débardeur crop top rose. Les lanières à
> ses genoux n'ont plus l'air d'avoir de physique du tout (je suis sûr d'en avoir vu par le passé)
> et le bas de son pantacourt clipe toujours à l'intérieur de ses mollets au lieu d'être visible,
> comme si son pantacourt s'arrêtait aux genoux. Ses lunettes clipent toujours légèrement avec ses
> seins. Mais c'est déjà beaucoup mieux, on se rapproche du but ! »

**ACQUIS À NE PAS CASSER : la poitrine sur les mouvements subtils, et le sag.** Toute modification
qui les dégrade est un échec, même si elle corrige autre chose. À protéger par un plancher mesuré.

**1. « ÉTIREMENT ET EFFET GELÉE, ÇA CHANGE DE TAILLE » sur les mouvements brusques.** L'allongement
mesuré est tombé de 21,5 % à 4,07 % — il reste donc, et son œil le voit. Mais « plus petit, plus
gros, écrasé » dit plus que de l'allongement : **le volume n'est pas conservé**. Une chaîne à un os
doit tourner autour de son ancre à longueur ET section invariantes. Vérifier qu'aucune échelle
n'arrive dans la matrice écrite (une correction appliquée en position sur un joint dont l'enfant est
recollé produit exactement une variation de taille visible).
→ **CORRECTION IMPORTANTE (owner, 21:20)** : « attention sur le fait qu'ils doivent conserver leur
volume — c'est pas des ballons durs non plus, c'est naturel que ça change un peu de forme, d'autant
plus que sur des mouvements forts ça s'écrase, se compresse, se tire. C'est juste beaucoup trop en
l'état du build de 19h53. »

La déformation n'est donc **pas** à supprimer : elle est à **borner**, et elle doit être une
RÉPONSE, pas un tremblement. Une contrainte à 2 % aurait produit les ballons durs qu'il refuse.
Trois exigences, pas une :
  1. **Amplitude bornée** : `ROOM-SHAPE: max=<écart relatif d'échelle> chain=<nom> drive=<mode>`,
     plafond ≈ **15 %** sous stimulus fort — assez pour qu'on voie la chair travailler, pas assez
     pour la gelée. Le chiffre exact se cale sur son œil, pas sur une théorie.
  2. **Corrélée au stimulus** : la déformation doit croître avec la force du mouvement. Une
     déformation présente à stimulus faible est un défaut ; elle doit être quasi nulle sur les
     mouvements subtils — qu'il juge déjà « quasiment parfaits », donc à ne pas toucher.
  3. **Elle revient** : à l'arrêt, retour à la forme du modèle. `ROOM-SHAPE-RECOVER: <frames>` court,
     et pas d'oscillation d'échelle entre deux frames (c'est ça, l'effet « gelée » : un changement de
     taille qui n'est corrélé à rien).
L'allongement de longueur d'os (`ROOM-STRETCH`) reste borné à 3 % : **un os ne s'allonge pas**, c'est
la CHAIR qui se déforme. Ce sont deux choses distinctes et il ne faut pas les confondre.

**2. ANGLES EXTRÊMES QUI CASSENT LE MESH — son idée est la bonne.** Le modèle n'a pas assez de
polygones pour encaisser un pli serré entre deux maillons. Deux réponses possibles, il propose les
deux : subdivision intelligente, ou **atténuation des angles extrêmes**. La seconde est bien moins
coûteuse et suffit : **limiter l'angle entre maillons consécutifs**, avec une transition douce (pas
un clamp brutal qui ferait un à-coup). L'angle limite se dérive du rig : au-delà, la peau se plie
au-delà de ce que ses arêtes permettent.
→ `ROOM-BEND: chain=<nom> max=<angle> link=<i> anim=<nom>` par chaîne, et un plafond par chaîne.

**3. RÉGRESSION APPARENTE SUR LES LANIÈRES DE GENOUX — vérifié, ce n'en est pas une.** `kneeflapL`
et `kneeflapR` existent, sont simulées et bougent (0,1298 et 0,0979 de mouvement de pointe). Mais
c'est **deux fois moins** que les sangles de cheville (0,1426) et il ne les voit plus. Leur
amplitude est trop faible pour être perçue : monter leur vivacité (couplage/masse), pas les
recréer.

**4. BAS DU PANTACOURT À L'INTÉRIEUR DES MOLLETS — « comme s'il s'arrêtait aux genoux ».** C'est le
plus grave visuellement : le pan est *avalé* par la jambe. `pantflapL/R` bougent (0,1196 / 0,1530)
mais finissent du mauvais côté de la capsule de mollet. Piste : la résolution de collision les
pousse **vers l'intérieur** au lieu de l'extérieur — un signe de normale inversée ou de point de
départ déjà à l'intérieur du volume. Mesurer le **côté** : `ROOM-SIDE: chain=<nom> inside_frames=<n>`,
doit être zéro.

**5. BRETELLES vs ÉLASTIQUE ORANGE du bas du crop top**, et **6. LUNETTES vs SEINS** : les deux
survivent. Ce sont des volumes manquants ou trop petits sur des pièces précises du vêtement, pas des
réglages de chaîne. Les dériver comme le reste du corps.

## PLAN DE REPRISE DEPUIS LE BUILD 19h53 (owner 2026-08-11 22:30)

> « Bon bah à partir du build de 19h53 tu peux appliquer mon feedback sur ce build justement ! »

Les cinq retours ont été traités **ensemble** la première fois, et le mouvement s'est effondré d'un
facteur 8 à 14. On reprend depuis `613218dfa3`, **dans l'ordre du risque de muselage**, un point à
la fois, chacun mesuré contre le plancher `motion-floor.txt` avant d'être conservé.

**GROUPE A — aucun risque de museler la physique. À faire en premier, ensemble.**
1. *Sangles de genoux imperceptibles.* Traité côté données par le superviseur : couplage 1.00→1.60,
   masse 0.60→0.85, raideur 2.00→1.60. Elles bougeaient (0.1298) mais deux fois moins que les
   chevilles ; il fallait de la vivacité, pas une résurrection.
2. *Bretelles vs élastique orange du bas du crop top.* Volume manquant sur une pièce précise du
   vêtement. À **dériver** comme le reste du corps — surtout pas une capsule estimée à la main.
3. *Lunettes vs seins.* Idem : les volumes de poitrine sont des sphères décalées, pas des volumes
   dérivés. Les dériver, sans jamais gonfler un rayon pour compenser.
4. *Bas du pantacourt avalé par les mollets.* La résolution pousse le pan **vers l'intérieur** :
   c'est un défaut de signe ou un départ déjà dans le volume, pas un manque de force. Mesurer
   `ROOM-SIDE: inside_frames = 0`. Corriger un signe n'enlève aucun mouvement.

**GROUPE B — peut museler. UN SEUL À LA FOIS, et on garde seulement si le plancher tient.**
5. *Étirement et effet gelée sur les mouvements brusques.* L'os ne s'allonge pas (`STRETCH ≤ 3 %`,
   déjà atteint à 1.43 %) ; la **chair se déforme**, bornée à ~15 %, corrélée au stimulus et
   récupérée à l'arrêt. Ce n'est pas la suppression de la déformation, c'est son cadrage.
6. *Angles extrêmes qui révèlent le manque de polygones.* **UNIQUEMENT SUR LES CHEVEUX**, précision
   de l'owner (22:35) : « l'atténuation pour éviter la géométrie extrême c'est juste sur les mèches,
   pas le reste, encore moins les seins ».
   Périmètre exact : `lbang`, `rbang`, `lmidhair`, `rmidhair`, `backhair`. Rien d'autre.
   **Et c'est mécaniquement évident une fois posé** : le défaut est un pli trop serré *entre deux
   maillons* d'une mèche, que la peau à faible densité de polygones ne peut pas encaisser. Une
   chaîne à **un seul maillon** — `chestL`, `chestR` — n'a aucun angle inter-maillon : y appliquer
   une atténuation ne peut rien corriger et ne fait que **retirer du mouvement**. C'est
   exactement ce qui s'est produit, et c'est une partie de l'effondrement x8.
   L'atténuation reste par ailleurs **progressive** (un clamp brut ferait un à-coup) et **locale au
   maillon fautif**, pas appliquée à toute la chaîne.

**RÈGLE DE CONSERVATION** : après chaque point, la course de la salle doit montrer que **aucune
chaîne** n'est passée sous 60 % de son plancher. Si le plancher casse, le point est retiré — pas
adouci, retiré — et repris autrement.

## DOUZIÈME PASSE — LE ZÉRO EST DÉMENTI PAR SON ŒIL (2026-08-12 12:20)

> « Les seins en mouvements subtils on dirait qu'ils ont été un peu mutés, sur les mouvements
> brusques c'est toujours des ballons d'eau qui font n'importe quoi. Les lunettes clipent toujours
> un peu à travers des seins et sur certaines animations se retrouvent derrière son dos. Les grosses
> mèches ont toujours des déformations extrêmes sur de très gros mouvements qui cassent leur
> géométrie, les petites bougent peut-être plus assez. Les lanières des genoux bougent toujours pas
> et le bas du pantacourt est toujours dans les mollets. Bof ! »

**1. `ROOM-SIDE = 0` EST DÉMENTI PAR SON ŒIL, ET LE CONTRÔLE EST LA CAUSE.** Il produit **43**
événements là où le phénomène réel en produisait **11 446** — soit **0,4 %**. Un contrôle qui
n'exerce pas le défaut **à son échelle** ne prouve pas qu'on l'a corrigé : il prouve seulement que
le compteur sait compter. Règle ajoutée à la gate : un contrôle doit atteindre **au moins 20 % de
la ligne de base** du phénomène, sinon il est déclaré non concluant.
→ Et donc : **le franchissement n'est pas corrigé**. Les lunettes finissent toujours dans son dos,
le pantacourt reste dans les mollets. Chercher ce que la mesure ne couvre pas — très probablement
les **intervalles entre capsules** (une chaîne passe entre deux volumes sans jamais être « dedans »)
et le **tunneling** en une frame.

**2. RÉGRESSION SUR LES MOUVEMENTS SUBTILS DE LA POITRINE, et mon plancher ne l'a pas vue.** Il
protège l'amplitude **maximale** sur cinq pilotages ; or ce qu'il juge « muté » est la réponse aux
**petits** stimuli. `chestL` : stimulus 15,82 → 0,2208 aujourd'hui. Le plancher doit porter sur le
pilotage **le plus faible**, pas sur le maximum — c'est là qu'il regarde, et c'est ce qu'il avait
qualifié de « nickel ».

**3. « Les petites mèches bougent peut-être plus assez »** : même famille. Elles avaient été
calmées à sa demande ; le curseur est peut-être passé de l'autre côté. À traiter APRÈS le
franchissement, et seulement sur son retour, pas sur un chiffre.

**4. Inchangés et attendus** : lanières de genoux (l'os n'existe pas dans le rig HD — reprise
d'asset), déformations extrêmes des grosses mèches (l'atténuation n'a jamais été appliquée),
ballons d'eau sur mouvements brusques (le bornage de la chair n'est pas fait).

## PRIORITÉ ABSOLUE — LE GRADIENT EST INVERSÉ, ET MON INSTRUMENT LE CONFIRME (2026-08-12 14:10)

> « On dirait que les mèches ne suivent pas l'inclinaison, on dirait qu'elles sont ancrées (les
> pointes) au même titre que les racines, et que c'est ce qu'il y a entre les pointes et les racines
> qui bouge vraiment… Franchement ça commence à faire longtemps qu'on est sur Keira et que tu
> progresses pas vraiment. »

**Il a raison sur les deux points, et le second est mérité.** Sur le premier, `ROOM-GRADIENT`
mesuré relativement au parent dit maintenant exactement ce qu'il voit :

    lbang     link0=0.0000  link1=50.77  link2=29.76      <- le MILIEU bouge 1.7x la POINTE
    rbang     link0=0.0000  link1=73.39  link2=26.87      <- 2.7x
    backhair  link0=0.0000  link1=75.29
    lmidhair  link0=0.0000  link1=49.36

La SPEC §2 exige une suite **croissante** de la racine vers la pointe. Elle est **décroissante**.
Hier je publiais 0.0000 / 0.2240 / 0.3846 — croissant — parce que la mesure était en repère MONDE :
la pointe héritait du mouvement de son parent et paraissait la plus mobile. En repère parent, la
vérité apparaît : **la pointe ne bouge presque pas d'elle-même**.

**C'EST LE DÉFAUT QUI EXPLIQUE LE PLUS DE CE QU'IL VOIT** — mèches qui « pètent un plomb » au
milieu, pointes qui ne suivent pas l'inclinaison, silhouette qui casse la géométrie. Il passe
devant tout le reste, y compris les collisions.

**Piste à vérifier EN PREMIER, elle est mécanique** : le dernier maillon d'une chaîne est-il
intégré ET écrit comme les autres ? Le moteur a déjà eu ce défaut exact sur la ROTATION (« il ne
tournait un maillon que s'il avait un enfant simulé à viser, donc jamais le dernier »). La même
condition `(< (+ l 1) n)` peut exister sur d'autres traitements — force, contrainte, écriture.
**Chercher toute condition qui exclut le dernier maillon**, et mesurer après correction que la
suite `link0 < link1 < link2` est bien croissante sur les cinq chaînes de cheveux.

## TREIZIÈME PASSE — SON DIAGNOSTIC SUR LES MÈCHES EST LE BON (2026-08-12 22:00)

> « La physique ne s'applique pas à toute la géométrie de ces deux mèches mais à seulement une
> partie, donc on a des polygones qui bougent et des polygones voisins parfaitement statiques,
> causant la géométrie qui casse. Faudrait que la mèche entière soit prise en compte ! […] Les
> mèches fines sur l'avant sont maintenant complètement statiques. […] Les cheveux entiers sont
> nuls à chier. Les seins, les mouvements subtils sont toujours OK. »

**1. COUVERTURE DE PEAU — PRIORITÉ 1, et c'est son diagnostic, pas le mien.** Une chaîne pilote des
JOINTS ; le mesh, lui, est pesé sur des joints qui ne sont pas tous simulés. Les sommets pesés sur
un joint non simulé restent à la pose d'auteur pendant que leurs voisins bougent — **d'où des
polygones mobiles collés à des polygones figés, et la géométrie qui casse**. C'est exactement ce
qu'il décrit, et aucune de mes mesures ne le voyait : elles regardent la position des JOINTS, pas
celle des SOMMETS.
→ **Mesure exigée** : `ROOM-SKINCOV: chain=<nom> verts=<n> driven=<n> frac=<%>` — la fraction des
sommets pesés sur la mèche qui est réellement pilotée par un joint simulé. **Toute fraction < 100 %
est le défaut**, et la correction est d'étendre la chaîne aux joints manquants (ou de re-peser),
pas de régler une raideur.

**2. RÉGRESSION SUR LES MÈCHES FINES, ET MES DEUX PLANCHERS L'ONT LAISSÉE PASSER.** `lbang` : 0.3467
contre un plancher de 0.4191 (−17 %, sous le seuil de 40 %) et 0.0838 au stimulus faible contre un
plancher de 0.0871 (−4 %, sous le seuil de 30 %). **Les deux gates sont vertes et il les voit
mortes.** Cause : un plancher relatif protège contre une chute brutale, il ne dit rien sur la
**visibilité**. Il faut un **plancher ABSOLU**, calibré sur ce qu'il a approuvé — la poitrine
subtile qu'il juge « OK » donne l'ordre de grandeur.

**3. NUQUE** : clipe dans le cou et ne bouge pas ou mal. À rapprocher de la preuve arithmétique du
jour : la pointe a 820 u de portée contre 915 de rayon de capsule de tête — **elle ne peut pas en
sortir**. Le volume doit rétrécir, la chaîne ne peut rien.

**4. OREILLES** : « je ne sais pas si c'est la physique ou les animations d'origine ». Exigence :
**quand l'animation ne pilote pas une oreille, la physique doit s'y appliquer**. Mesurer, par
animation, la part de frames où l'oreille est pilotée par l'anim et la part où la physique agit —
si la seconde est nulle, la physique ne s'applique jamais.

**5. ACQUIS CONFIRMÉ** : poitrine sur mouvements subtils « toujours OK ». À protéger.
