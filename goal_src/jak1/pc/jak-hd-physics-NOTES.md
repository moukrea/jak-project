# jak-hd-physics — NOTES DE CONCEPTION (rationale extraite du moteur)

Ce fichier porte la JUSTIFICATION des choix du solveur `goal_src/jak1/pc/jak-hd-physics.gc`.
Elle vivait en blocs de commentaires DANS le moteur ; elle en est sortie le 2026-08-14 pour
tenir sous le plafond de lignes de la gate CLEAN (4800) sans supprimer une seule ligne de
RAISONNEMENT ni une seule ligne de CODE. Chaque bloc deplace a laisse dans le moteur une ligne
`;; [NOTE-nn] ... -> jak-hd-physics-NOTES.md` a sa place exacte.

PREUVE QUE RIEN D'AUTRE N'A BOUGE : le moteur prive de tous ses commentaires est BIT-IDENTIQUE
avant et apres l'extraction (verifie par diff dans le rapport du cycle 7).

RAPPEL DE LA REGLE 0 : un commentaire n'est pas une preuve. Ce fichier explique POURQUOI le code
est ecrit ainsi ; ce que le programme FAIT se lit dans les traces d'execution, jamais ici.

## NOTE-01  (moteur, aux alentours de la ligne 76)

```
8 = `gradient`, documente par le parseur C++ comme « root->tip freedom exponent »
(kmachine.cpp:912). Il etait PARSE et JAMAIS LU : le moteur propre n'a aucun profil d'influence
(`grep -n infl` ne rend rien), et le fichier de donnees livre n'en porte aucune occurrence.

POURQUOI CET INDICE ET PAS `rootfree` (16), QUI DECRIT LE MEME CONCEPT. `rootfree` vaut
**0.3 PAR DEFAUT** dans le parseur (kmachine.cpp:1028, « rootfree DEFAULTS to 0.3 — cast-wide by
construction »). Le lire ici aurait donc arme un maillon 0 gradue sur LES 22 CHAINES d'un coup,
sans qu'une seule ligne de donnees le demande — et le constructeur automatique aurait publie ca
a l'owner avant qu'aucune course ne l'ait mesure. L'indice 8 vaut **0 par defaut** (le tableau
d'initialisation kmachine.cpp:1010 rend params[8] = 0), donc tant qu'aucune chaine ne l'ecrit,
ce moteur se comporte AU BIT PRES comme avant ce cycle. C'est la propriete qui rend le
changement livrable sans l'avoir encore juge.
```
## NOTE-02  (moteur, aux alentours de la ligne 179)

```
------------------------------------------------------------------------------------------------
LE VOLUME QU'UN LIEN PORTE QUAND IL BOUGE — et c'est LE MEME que celui qu'il presente quand il
est un OBSTACLE. Owner, 6e passe : « c'est pas juste les capsules de collision qui bougent pas,
mais plutot mes capsules de collision qui sont pas bonnes ».

Le moteur croyait deux choses differentes du meme morceau de corps :
  * comme OBSTACLE, le sein est la sphere que le generateur a ajustee sur le mesh — rayon 183,
    centre au CENTROIDE mesure de sa geometrie, 662 unites hors du joint (`collider lBoob`) ;
  * comme MOBILE, il etait une sphere de rayon 656 posee SUR LE JOINT — la demi-epaisseur
    `radii=`, qui mesure la distance des sommets a l'AXE de l'os, un axe qui traverse le sein de
    part en part. 656 unites, c'est 16 cm de rayon centre a 16 cm du sein.
Deux volumes pour un seul sein, et c'est le gros et mal place qui decidait de ses mouvements.
Mesure du 2026-08-11 18:40 : la poitrine reculait 8653 fois et son plafond d'excursion mordait
1910 fois par course — la gravite arrivait bien (gn=0.83, tf=0.70) et la collision la renvoyait.

Ce n'est ni un masque ni un flag (DIRECTIVES 4) : aucune donnee nouvelle, aucune exception par
nom. On cesse simplement d'avoir deux definitions du meme volume. Un joint qui ne declare aucune
sphere garde exactement le comportement precedent (`*phys-rad*`, centre sur le joint).
```

## NOTE-03  (moteur, aux alentours de la ligne 257)

```
------------------------------------------------------------------------------------------------
LA POSE D'AUTEUR DE CHAQUE VOLUME, PRISE UNE FOIS PAR FRAME AVANT QUE QUOI QUE CE SOIT N'ECRIVE.

Le plancher de pose modele (`floor0`) repond a UNE question : « a quelle profondeur ce lien
est-il deja, DANS LA POSE QUE L'AUTEUR A SCULPTEE ? » — ce qui est deja dedans au repos y reste.
C'est une propriete de la POSE DU MODELE, des deux cotes : le lien ET le volume.

Or les chaines sont resolues l'une apres l'autre et chacune ECRIT son joint dans le squelette
avant que la suivante ne commence. Un volume porte par un joint simule (`lBoob`, `rBoob` : la
poitrine n'a pas de rootlock, donc son lien 0 est ecrit) presentait donc sa position SIMULEE au
calcul de `floor0`, pendant que le lien y etait pris a sa pose d'auteur. Les deux membres
n'etaient pas dans le meme etat, et le sens de l'erreur est exactement celui du defaut que
l'owner decrit : quand le sein simule se rapproche des lunettes, `floor0` MONTE, donc la
tolerance monte, donc la poussee qui devrait naitre a ce moment precis n'existe pas.
Algebre, sur les nombres du fichier de donnees : `gogglesMid` rl=150, sphere `lBoob` r=322 ->
`floor0 = 472 - d`, et `floor0 >= 2*rl = 300` des que d <= 172 u : la paire est declaree LIBRE
et ne sera plus jamais repoussee. C'est « les lunettes clipent legerement avec les seins, et
meme en idle ».

La correction ne change pas la regle, elle la rend coherente : `floor0` est desormais mesure
contre le volume A SA POSE D'AUTEUR (ce tableau), et la penetration courante `dep` contre le
volume a sa position COURANTE. Pour les 31 volumes qui ne sont portes par aucun joint simule les
deux sont identiques au bit pres, donc rien d'autre ne bouge.
```

## NOTE-04  (moteur, aux alentours de la ligne 288)

```
------------------------------------------------------------------------------------------------
L'OBSTACLE NE DOIT PAS DEPENDRE DE L'ORDRE DE RESOLUTION DES CHAINES (instantane de JACOBI).

NATURE de ce que ces tableaux portent : une POSITION MONDE (unites de jeu), pas une variance et
pas une amplitude. REPERE : monde. CE QU'ILS VALENT QUAND LE DEFAUT EST ABSENT : exactement la
position que le squelette porte, au bit pres, pour les 24 volumes qu'aucune chaine ne simule.

LE DEFAUT QU'ILS CORRIGENT, ET IL EST MESURE. Les chaines sont resolues en sequence
(jak-hd-physics-step, `dotimes (c nch)`) et CHACUNE ECRIT SES JOINTS DANS LE SQUELETTE avant que
la suivante ne calcule ses collisions. Or `phys-col-centre` lit le squelette COURANT : la chaine
n^k voit donc les volumes des chaines 0..k-1 a leur position SIMULEE de cette frame, et ceux des
chaines k+1..N a leur pose ANIMEE. La reponse d'une chaine depend alors de son RANG dans le
fichier, ce qui n'est pas une propriete physique.
La trace : `chestL` est la chaine 7, `chestR` la chaine 8, parametres identiques au centieme et
rig miroir exact a 0.0020 u (18e passe). ROOM-JELLY les separe pourtant du tout au tout —
    chestR  ratio 0.9923 / 0.9975 / 0.9927 / 0.9990   periode 2.17 / 2.09 / 2.17 / 2.06 frames
    chestL  ratio 0.6212 / 0.6729 / 0.7092 / 0.6983   periode 4.69 / 4.26 / 3.98 / 4.06 frames
Une periode de 2.06 frames avec un saut qui vaut 99.9 % de l'amplitude, c'est un cycle limite a
la frequence de Nyquist : chestR poursuit `lBoob` DEJA DEPLACEE cette frame pendant que chestL
poursuit `rBoob` restee sur l'animation. C'est « des fois ça saute d'une frame a l'autre comme un
mini jitter » et « un effet gelee ou ca change de taille », et aucun reglage ne pouvait l'oter.
La correction : tout volume porte par un joint SIMULE est lu par TOUTES les chaines a sa position
de FIN DE FRAME PRECEDENTE. Symetrique par construction, une frame de retard a 60 Hz, et la
collision chaine<->chaine que la SPEC 1bis exige (« ils s'entrechoquent ») reste entiere.
```

## NOTE-05  (moteur, aux alentours de la ligne 321)

```
------------------------------------------------------------------------------------------------
DESARME PAR DEFAUT — IL CORRIGE CE QU'IL VISE, ET IL COUTE PLUS CHER AILLEURS.

CE QU'IL CORRIGE, et c'est reel : l'asymetrie chestL/chestR s'effondre. Ecart de `ratio` entre
les deux chaines, moyenne sur les quatre translations, 0.3200 -> 0.0916 (-71 %) ; ecart de
periode 2.12 -> 0.65 frame (-69 %). Et ce n'est pas un lissage de compteur : `chestR` rendait
0.0236 / 0.0832 / 0.1144 / 0.0367 de mouvement de pointe dans la fenetre JELLY, elle rend
0.1780 / 0.1704 / 0.2679 / 0.0886 — du mouvement APPARU, du meme ordre que `chestL`.

CE QU'IL COUTE, mesure par la course d'isolement (priorite desarmee, lui seul arme) :
    ROOM-STRETCH  0.0272 -> 0.4896   soit 49 % d'allongement d'os sur `lbang`, SEIZE fois le
                                     plafond de 3 % du contrat
    ROOM-RETREAT-ANCHOR fallback  278 -> 933
Les deux chiffres sont le meme evenement : en rendant l'obstacle une frame plus vieux, il fait
echouer plus souvent le point de depart du recul sur la sphere du modele, et ce repli-la ABANDONNE
la longueur de l'os.

LE PREALABLE A ETE LEVE, LE DRAPEAU A ETE ARME, ET LA COURSE L'A REFUSE. Essai fait, mesure,
retire — le negatif est le resultat, et il economise le prochain cycle.
Le repli du recul n'abandonne plus la longueur (le balayage de sphere de `phys-retreat-chain` le
sauve 204 fois sur 227), donc l'objection de la note ci-dessus ne tient plus. Arme sur cette base,
course complete du 2026-08-12, ce drapeau pour SEULE variable :
    ROOM-RETREAT-ANCHOR fallback  23 -> 30      ROOM-RETREAT-SPHERE rescued  204 -> 377
    ROOM-STRETCH  0.0003 -> 0.0933              9,3 % d'allongement d'os sur `lbang`, TROIS fois
                                                le plafond de 3 % du contrat
    ROOM-JELLY chestR  ratio 0.9990 period 2.06  ->  ratio 0.9990 period 2.06 : INCHANGE
    ROOM-JELLY chestL jerk  ratio 0.7153 period 3.94  ->  0.9083 / 2.76 : EMPIRE
DEUX CHOSES QUE CA ETABLIT. (1) L'allongement ne passe PAS que par le repli du recul — 30 replis
ne peuvent pas produire 9,3 % : il vient de la poussee, qui resout contre un obstacle d'une frame
plus vieux et sort de la sphere plus qu'une iteration ne rattrape. (2) LE GAIN ANNONCE PAR LA
NOTE CI-DESSUS NE SE REPRODUIT PLUS : l'asymetrie ne s'effondre pas, la periode de 2.06 frames ne
bouge pas d'un centieme. Cette mesure datait d'un moteur sans contrainte de cote ni balayage.
La gelee n'est donc PAS un defaut d'ordre de resolution, et le prochain cycle n'a plus a depenser
un essai ici.
```

### TROISIEME ESSAI, 2026-08-18 — **ARME, ET GARDE**. LES DEUX REFUS CI-DESSUS SONT PERIMES.

```
CE QUI A CHANGE DANS LE SOLVEUR, ET C'EST EXACTEMENT L'OBJECTION QUI LE REFUSAIT. Les deux refus
tenaient a UNE grandeur : `ROOM-STRETCH` 0.0003 -> 0.0933, soit 9.3 % d'allongement d'os pour un
plafond de 3 %, explique par « il resout contre un obstacle d'une frame plus vieux et sort de la
sphere plus qu'une iteration ne rattrape ». Depuis :
  - `phys-retreat-chain` a ete RETIREE (2026-08-13, pierre tombale dans le source) ;
  - la poitrine est passee de UN a DEUX maillons (2026-08-17) ;
  - et la boucle de finition ALTERNE desormais une poussee de profondeur TANGENTIELLE avec la
    reprojection de longueur, qui reste sa DERNIERE operation (NOTE-61, 2026-08-18). La longueur
    est exacte par construction : `ROOM-STRETCH` = 0.0002 mesure, 150 fois SOUS le plafond.
Le mecanisme par lequel Jacobi cassait la longueur n'existe plus.

COURSE COMPLETE DU 2026-08-18 17:02, CE DRAPEAU POUR SEULE VARIABLE (`physics_chains.txt`
bit-identique, aucun autre octet de moteur touche) :

    grandeur                          desarme      arme      lecture
    ROOM-STRETCH (plafond 0.03)        0.0002     0.0002     INCHANGE — l'objection ne se reproduit PAS
    contacts sein<->sein, chestL           15       535
    contacts sein<->sein, chestR          217       464
    -> asymetrie                        14.5x     1.15x      LE DEFAUT DE SA 32 EST FERME
    ROOM-REST-MIX (coef. moyen)        0.0204    0.0212      la restitution de sa 33 (0.06) passe
                                                             de ~1 % a ~3 % des restitutions
    DISCRIMINANT chestL / chestR    30.0/51.8  33.4/55.0     PASSE, et s'ameliore
    tipvar chestL / chestR        0.1937/0.1967 0.2035/0.2103  +5.1 % / +6.9 %
    §27 t1 chestR                       1.55 s    1.50 s     revient DANS la bande 1.0-1.5
    ROOM-IDLE maxdev                   0.0004    0.0004     inchange
    ROOM-GRAVSAG                  0.0376/0.0297 identiques   inchange
    §24, six canaux au repos          4 DANS     4 DANS      inchange (ecarts < 0.005 Hz)
    ROOM-SKINPEN (regle 6, le mesh) 0.1418/0.1408 0.1421/0.1418  +0.2 % / +0.7 %
    CE QUE CA COUTE :
    meshpen chestL                     0.0974    0.1114     +14 %  (chestR inchange a 0.0887)
    franchissements d'axe                   2         5

POURQUOI ON LE GARDE MALGRE LE COUT. `COLLIDE` est deja rouge d'un facteur ~195 et son ARGMAX
n'est PAS l'autre sein (c'est `sphere:lTopStrap2` a gauche, `Rshoulder->chest` a droite) : le
couplage ne cause pas ce rouge, il le rend un peu plus visible. En face, sa 32 exige
l'independance gauche/droite et sa 33 une restitution sein<->sein — deux sections de SA spec, que
le desarmement violait par une cause qui n'etait dans AUCUN parametre. DIRECTIVES 2026-08-17
23:50 : « un plancher qui casse n'est plus un motif de retrait : c'est la LISTE DE TRAVAIL [...]
on avance A TRAVERS les rouges ».

LECON, ET ELLE EST GENERALE. Ce correctif etait DEJA ECRIT dans le moteur, cable a zero, et son
setter avait ete retire faute d'appelant — le piege `declared-but-never-selected`. Le cycle 24 a
depense un controle d'inversion d'ordre a PROUVER le defaut sans voir que le remede dormait a
cote. Quand une note dit « essaye, mesure, retire », relire CE QUE la mesure incriminait : si ce
mecanisme-la a change depuis, le refus est perime, et le re-essayer n'est pas re-litiger.
```

## NOTE-06  (moteur, aux alentours de la ligne 357)

```
------------------------------------------------------------------------------------------------
DECISION 1 DU SUPERVISEUR — UN SEUL VOLUME DECIDE PAR LIEN ET PAR FRAME.

« quand un lien est contraint par plusieurs volumes dans la meme frame, le volume du CORPS
l'emporte sur celui d'une CHAINE, et entre deux volumes de corps, le PARENT DANS LE RIG
l'emporte. Un seul volume decide par frame et par lien, les autres sont ignores — pas moyennes,
ignores. »

CE QUE CA CORRIGE, MESURE PAR LA COURSE : `kneeflapR` vit dans DEUX capsules qui se recouvrent
(Rknee->Rthigh et Rankle->Rknee) ; sortir de l'une enfonce dans l'autre, aucune position ne les
satisfait toutes deux, et le recul epingle donc la languette sur la pose du modele
15913 frames sur 17893 — 89 % du temps. C'est la definition exacte de « les languettes au niveau
des genoux ne bougent pas », et ce n'est ni un defaut de donnees ni une reprise d'asset.
    kneeflapR  retreat=15913  contact 17893/17893 frames (100 %)
    kneeflapL  retreat=4138   contact 12493/17893 frames (69.8 %)
L'autre trace du meme defaut est ROOM-INVERSIONS residual=379 : deux volumes qui se renvoient le
lien de l'un a l'autre.

LA DECISION VAUT POUR LE SOLVEUR ENTIER — poussee ET recul. Ne l'appliquer qu'a la poussee
laisserait le recul re-epingler sur le volume ignore, donc ne changerait rien au defaut.
ELLE NE VAUT PAS POUR LA MESURE : `phys-pen-chain` continue de regarder TOUS les volumes, sinon
le chiffre deviendrait aveugle a ce que la decision laisse passer — c'est le piege du « zero
vert pendant que l'owner voit le defaut », et il n'est pas question de le reconstruire ici.
```

## NOTE-07  (moteur, aux alentours de la ligne 381)

```
------------------------------------------------------------------------------------------------
ELLE EST DESARMEE PAR DEFAUT, ET C'EST LA MESURE QUI L'A REJETEE — PAS UNE PRUDENCE.

Course complete du 2026-08-12, la priorite pour SEULE variable armee, comparee a la course de
reference. Les trois chiffres qui la condamnent :

  * PENETRATION. `meshpen` passe de 0.0000 a POSITIF sur TREIZE chaines : rbang 0.0589 m,
    goggles 0.0297, lbang 0.0261, chestR 0.0195, topstrapR 0.0092, rmidhair 0.0089,
    backhair 0.0081, botstrapR 0.0065... Ignorer un volume, c'est le laisser traverser.
    Regle 6, qui ne se negocie pas : « rien ne traverse le mesh de son personnage, quelle qu'en
    soit la raison — une resolution pire que le clip est pire que rien. »
  * ALLONGEMENT D'OS. `ROOM-STRETCH` passe de 0.0272 a 0.4746 : 47 % sur `lbang`, quinze fois
    le plafond de 3 %. Un os ne s'allonge pas.
  * ET ELLE RATE SA PROPRE CIBLE. Elle a ete ecrite pour desepingler `kneeflapR` (defaut
    `knee-tabs`) : son `retreat` passe de 15913 a 21229 frames sur 17893. Elle EMPIRE le defaut
    qu'elle devait corriger.

Pourquoi, et c'est instructif : ecarter un volume ne resout pas le conflit, il le deplace. Le
lien sort du volume prioritaire, entre dans celui qu'on a ignore, et le recul — a qui l'on a
retire le meme volume — n'a plus de quoi l'en sortir. `ROOM-VOLPRIO` chiffre l'ampleur de ce
qu'on ecartait : 346 055 paires sur 18 chaines (goggles 99 758, chestR 85 301, kneeflapR 45 138).

CE QUE LA MESURE GARDE, ET C'EST LE VRAI ACQUIS : `ROOM-VOLPRIO` est le premier chiffre qui dise
OU les volumes se contredisent, par chaine. `ROOM-INVERSIONS residual` etait un scalaire global
qu'aucune chaine ne portait. Le code reste, desarme, avec son compteur : le conflit est
MESURE sans etre ARBITRE, en attendant un arbitrage qui ne fasse pas traverser — la piste
mesuree est la frontiere de l'UNION des volumes, pas le choix de l'un d'entre eux.
Desarme, `*phys-lwin*` reste a -1 et le comportement est celui d'avant AU BIT PRES.
```

## NOTE-08  (moteur, aux alentours de la ligne 413)

```
MESURER LE CONFLIT SANS L'ARBITRER — 2026-08-13.

Le commentaire ci-dessus affirme « le conflit est MESURE sans etre ARBITRE ». C'ETAIT FAUX, et le
code le dit : la passe de selection ET ses trois compteurs etaient TOUS a l'interieur du
`(when (zero? *phys-prio-off*)`. Desarmee, la passe ne tournait pas, donc `ROOM-VOLPRIO` publiait
`pairs_ignored=0 chains=0` — un zero tire d'un DOMAINE VIDE, pas une absence de conflit. Le
chiffre de 346 055 paires cite plus haut vient d'une course ou la priorite etait ARMEE ; depuis
qu'elle est desarmee, la ligne lit 0 et se laisse lire comme « les volumes ne se contredisent
plus ». C'est exactement le faux vert que la SPEC 7 interdit.

Ce drapeau-ci fait tourner la passe de selection POUR SES COMPTEURS SEULEMENT : `*phys-lwin*` est
remis a -1 avant la resolution, donc aucun volume n'est ecarte et le comportement reste celui du
desarmement AU BIT PRES. Il vaut 0 par defaut : le jeu ne paie pas la passe supplementaire (52
volumes par lien et par frame) ; seule la salle l'arme, parce que seule la salle mesure.
```

## NOTE-09  (moteur, aux alentours de la ligne 429)

```
------------------------------------------------------------------------------------------------
MESURE (SPEC 7). Les colonnes du tableau de la salle sont accumulees ICI parce que c'est ici que
la position ecrite est connue. La salle remet a zero au debut de chaque fenetre et relit a la
fin ; elle n'invente aucun instrument par-dessus.
   0 nsamp    frames de la fenetre
   1 sumjump  somme des |delta o| de pointe (moyenne = vitesse de pointe)
   2 maxjump  pire |delta o| de pointe sur UNE frame
   3 maxroot  pire residu d'ancrage : max(|p0 - T0|, |residu de longueur du 1er lien libre|)
   4 maxpen   pire penetration RESIDUELLE (au-dela du plancher de pose modele) apres commit
   5 maxidle  pire |p - T| sur les liens libres = ecart a la pose du modele
 6..11 boite englobante de l'ecart de pointe (oxmin oxmax oymin oymax ozmin ozmax) : sa
        diagonale est l'AMPLITUDE de mouvement de la pointe due a la physique seule. L'animation
        d'auteur n'y contribue pas d'un micron : une chaine qui ne fait que suivre son os
        anime mesure zero. C'est volontairement le test le plus severe de « ca bouge ».
12..15 SOMME de l'ecart de pointe et NOMBRE de frames : leur quotient est la POSITION MOYENNE de
        la pointe dans le repere de l'ancre. C'est un DEPLACEMENT SOUTENU, pas une variance, et
        c'est la seule chose qui puisse mesurer la gravite. Verdict de l'owner du 2026-08-11
        16:15 : « aucun mouvement en fonction de l'inclinaison quand elle se penche en avant pour
        souder, zero gravite sur ses seins ». Une inclinaison tenue ne produit AUCUNE variance —
        la chaine se pose sur un nouvel equilibre et ne bouge plus — donc la boite englobante
        (6..11) y mesure zero et l'a toujours mesure. La reponse gravitaire est l'ecart entre la
        moyenne a 0 degre et la moyenne a 60 degres : c'est ROOM-GRAVSAG, et rien ne le mesurait.
   16 pire |acceleration MONDE de la pose d'auteur| de la POINTE sur la fenetre, en u/frame^2.
        C'est LE STIMULUS QUE LA CHAINE A REELLEMENT RECU, quelle qu'en soit la source. Sans lui
        on ne peut pas distinguer « la chaine ne repond pas au pilotage » de « le pilotage est
        noye sous autre chose », et c'est cette confusion qui a fait publier des amplitudes
        identiques sous cinq stimuli differents.
------------------------------------------------------------------------------------------------
   17 pire ALLONGEMENT RELATIF d'un lien sur la fenetre, |longueur/longueur_de_repos - 1|.
        NATURE : un rapport sans dimension. REPERE : aucun — c'est une longueur divisee par une
        longueur, mesuree entre le lien et SON ATTACHE (lien precedent, ou ancre pour le lien 0),
        donc invariante par tout mouvement du personnage. LECTURE QUAND LE DEFAUT EST ABSENT : 0,
        parce qu'une chaine qui ne fait que tourner autour de son attache garde sa longueur au
        bit pres. La meme grandeur existait deja par CHAINE et par COURSE (phys-diag 5) : elle est
        ici par FENETRE, donc attribuable a un pilotage — « ils s'allongent sur les mouvements
        BRUSQUES » est une phrase sur un pilotage, pas sur une course.
   18 |g_effective| / |g|, sans dimension, max sur la fenetre. NATURE : l'amplitude du stimulus
        gravitaire lui-meme, pas la reponse. REPERE : celui de l'ancre. LECTURE QUAND LE DEFAUT
        EST ABSENT : 0 debout (les deux gravites s'annulent), 1.0 a 60 degres. Sans elle, un
        affaissement nul ne dit pas si c'est la gravite qui n'arrive pas ou la chaine qui n'y
        repond pas — et c'est exactement l'ambiguite qui a coute trois passes.
   19 fraction TANGENTIELLE de g_effective : sqrt(1 - (g^.b^)^2) ou b^ est la direction de l'os.
        NATURE : sans dimension, dans [0,1]. La contrainte de longueur n'autorise qu'une ROTATION
        autour de l'attache : la part de la gravite dirigee LE LONG de l'os ne peut produire aucun
        deplacement, elle est annulee par construction. Une chaine dont la gravite est presque
        radiale ne s'affaissera jamais, quelle que soit la valeur de `gravity=` — c'est une
        propriete geometrique du rig, et sans ce nombre elle est indiscernable d'un bug.
```

## NOTE-10  (moteur, aux alentours de la ligne 478)

```
------------------------------------------------------------------------------------------------
LE GRADIENT LE LONG DE LA CHAINE (7e passe de l'owner, 2026-08-11 16:30) : « entre la racine et
les pointes c'est zone de guerre et les pointes bougent quasi pas, au lieu d'un degrade
progressif des racines aux pointes ».

Il decrit une FORME et le tableau publiait un SCALAIRE. `tipvar` ne regarde que la POINTE : une
chaine dont le maillon du milieu part en vrille pendant que la pointe reste collee a la pose
d'auteur rend exactement le meme `tipvar` qu'une chaine saine. Aucune mesure ne pouvait donc voir
le defaut qu'il decrit, et c'est la meme famille d'aveuglement que la reponse plate du matin.

On garde donc la boite englobante de l'ecart POUR CHAQUE MAILLON, pas seulement pour la pointe.
SPEC 2 exige que la suite soit CROISSANTE de la racine vers la pointe ; toute chaine dont un
maillon intermediaire depasse sa pointe est un echec, quel que soit son `tipvar`.
6 valeurs par maillon : oxmin oxmax oymin oymax ozmin ozmax.
```

## NOTE-11  (moteur, aux alentours de la ligne 495)

```
------------------------------------------------------------------------------------------------
LE GRADIENT, MAIS DANS LE BON REPERE — 10e passe de l'owner (2026-08-11 18:00) :

  « les meches c'est mieux, mais le MILIEU est plus hysterique (bouge beaucoup plus) que les
    POINTES, c'est pas cense ! »

La boite englobante ci-dessus disait le contraire (link0 0.0000, link1 0.2240, link2 0.3846,
croissante). Elle a tort, et pour une raison structurelle : elle mesure l'ecart de CHAQUE maillon
a sa pose d'auteur, un ecart qui se CUMULE le long de la chaine. Une pointe soudee a son parent —
qui ne bouge donc pas d'un micron PAR RAPPORT A LUI — herite integralement de l'ecart du parent et
affiche un grand chiffre. C'est la meme faute que « differencier la position au lieu de la
sortie » : la grandeur mesuree n'est pas celle du defaut decrit.

Le mouvement PROPRE d'un maillon, c'est sa deviation ANGULAIRE par rapport a son attache :

     angle( p_l - attache_l ,  auteur_l - auteur_attache )     en degres

Elle vaut zero pour un maillon qui suit rigidement son parent, quelle que soit l'agitation de
celui-ci, et c'est CETTE suite que SPEC 2 exige croissante de la racine vers la pointe.
NATURE : un angle (une forme), pas une amplitude. REPERE : celui du PARENT, par construction.
LECTURE QUAND LE DEFAUT EST ABSENT : une suite croissante, racine a 0 (rootlock).
```

## NOTE-12  (moteur, aux alentours de la ligne 517)

```
------------------------------------------------------------------------------------------------
LE GRADIENT, ETAGE PAR ETAGE DU SOLVEUR — defaut `hair-gradient`, PRIORITE 1 du superviseur.

« Faut pas que le milieu des petites meches bouge plus que les pointes, c'est juste logique »
(owner) ; SPEC 2 : la suite doit CROITRE de la racine vers la pointe. Elle DECROIT, et de
beaucoup : `lbang` link1 = 50.8 a 86.9 deg contre link2 = 19.8 a 58.3 ; `rbang` 73.4 contre 26.9.
Le milieu devie 1,7 a 2,7 fois plus que la pointe, sur les cinq pilotages, dans le build livre.

CE QUE `ROOM-GRADIENT` NE PEUT PAS DIRE, ET C'EST POURQUOI TROIS PASSES N'ONT PAS AVANCE : il
publie l'angle TEL QU'ECRIT, a la fin de la frame. Or la frame comporte trois etages qui peuvent
chacun aplatir la pointe — l'integration, la boucle de contraintes (longueur x8, collision x8,
attenuation d'angle) et la finition (longueur + collision + recul, x3). Un seul chiffre en sortie
ne peut pas designer lequel. On mesure donc le MEME angle aux trois etages :
  stage 0 : juste apres l'integration, avant toute contrainte
  stage 1 : apres la boucle de contraintes et l'attenuation d'angle
  final   : tel qu'ecrit (`*phys-la*`), ce que l'oeil de l'owner voit
L'etage ou le rapport link1/link2 bascule EST la cause. Aucune hypothese n'est privilegiee : si
le rapport est deja inverse au stage 0, c'est l'integration ; s'il s'inverse au stage 1, c'est la
contrainte de longueur ou l'attenuation ; s'il s'inverse a la fin, c'est le recul.
NATURE : un angle en degres. REPERE : monde, les deux directions partant de la MEME attache — la
simulee pour la direction courante, l'animee pour la direction du modele, exactement comme
`*phys-la*`, sinon les etages ne seraient pas comparables entre eux.
LECTURE QUAND LE DEFAUT EST ABSENT : une suite CROISSANTE avec l'index du maillon, aux trois
etages.
```

## NOTE-13  (moteur, aux alentours de la ligne 543)

```
------------------------------------------------------------------------------------------------
LA DEVIATION SIGNEE. `*phys-la*` est un MODULE (`atan2`, `sn >= 0`) : le signe est perdu, donc un
mouvement PLAN y montre une periode DEUX FOIS trop courte pendant qu'un mouvement qui PRECESSE y
montre la bonne — et les deux rendent la MEME colonne. D'ou « aucun rebond », « rebond 4.7 % » et
« decroissance a quantite constante » tires successivement de la MEME trace.
NATURE : un VECTEUR, `u_courant - u_modele`, tous deux UNITAIRES depuis la MEME attache (simulee
  pour le courant, animee pour le modele : la convention de `*phys-la*`). Norme = 2 sin(theta/2),
  monotone en l'angle ; DIRECTION = la phase.
REPERE : le MONDE — legitime dans la seule fenetre de repos, ou `physroom-hold` fige position,
  orientation et animation, donc ou la direction du modele est constante. Publiee la seulement.
INSTANTANEE, ecrasee chaque frame : un maximum courant ne peut pas porter une phase.
LECTURE QUAND LE DEFAUT EST ABSENT : (0,0,0) exactement, a la pose du modele comme pour un maillon
  qui suit rigidement son parent.
LUE PAR `.autoport/physics_ringdown.py`, valide par CONTROLE POSITIF sur deux series synthetiques
  (zeta connu 0.35 -> rendu 0.366 ; drain lineaire pur -> classe « QUANTITE constante par frame »).
```

## NOTE-14  (moteur, aux alentours de la ligne 559)

```
------------------------------------------------------------------------------------------------
SPEC-breast-softbody.md §24 + §29 — TROIS RAIDEURS, DONC UN TRIEDRE. ET LES DEUX SECTIONS SE
FERMENT ENSEMBLE, PAR UN SEUL MECANISME.

§24 donne trois frequences propres AVEC LEUR PLAGE :
    Vertical 2.30 Hz (2.1-2.5) · Front/Back 2.50 Hz (2.3-2.7) · Lateral 2.65 Hz (2.4-2.9)
§29 donne trois mobilites, SANS plage :
    Vertical 1.00 · Front/back 0.90 · Lateral 0.82 · Torsional 0.72

CE SONT DEUX VUES DE LA MEME GRANDEUR, et elles ne coincident pas a leur nominal. La mobilite
d'un ressort est `1/k`, et `k` va comme `f^2`, donc une anisotropie de frequence FIXE
l'anisotropie de mobilite :
    nominal §24 -> mobilite AP = (2.30/2.50)^2 = 0.846   contre 0.90 en §29   (-6.0 %)
                   mobilite lat = (2.30/2.65)^2 = 0.753   contre 0.82 en §29   (-8.2 %)
Poser les nominaux de §24 rate donc §29 de 6 a 8 %. L'INVERSE, LUI, NE RATE RIEN :
    §29 exact  -> f_AP  = 2.30/sqrt(0.90) = 2.4244 Hz, DANS la plage 2.3-2.7 de §24
                  f_lat = 2.30/sqrt(0.82) = 2.5399 Hz, DANS la plage 2.4-2.9 de §24
Un nombre donne avec une plage est tenu partout dans sa plage ; un nombre donne sans plage est
un point. On prend donc §29 AU POINT et §24 DANS SES PLAGES : les deux sections sont tenues
telles qu'elles sont ECRITES, et il n'a fallu inventer aucun degre de liberte pour y arriver.
La verticale, elle, reste le nominal EXACT de §24 (2.30 Hz) et la mobilite 1.00 de §29 : c'est
la reference des deux sections, et c'est le `stiffness` que la donnee livre.

CE SONT DES RAIDEURS, PAS DES REGLAGES : `*phys-axs*` est un facteur multiplicatif sur `k2l`,
derive des seuls nombres de sa §29, et l'amortissement suit par `dmp*sqrt(s)` pour que `zeta`
reste 0.35 SUR LES TROIS AXES (§25) — la meme derivation que celle deja appliquee le long de la
chaine (`dmp_l = dmp*sqrt(k2l/k2)`), pour la meme raison : `zeta` est une constante du MATERIAU.
```

## NOTE-15  (moteur, aux alentours de la ligne 608)

```
------------------------------------------------------------------------------------------------
ET POURQUOI L'ANISOTROPIE EST ARMEE SEPAREMENT DE LA CLASSIFICATION.

DIRECTIVES du 2026-08-14 09:45, ordre impose : « 1. La STRUCTURE d'abord. Un sein doit porter
assez de degres de liberte pour exprimer §30-31. Tant que c'est un point, tout reglage est une
perte de temps. 2. PUIS §24 + §29 ». Aujourd'hui chaque sein est une chaine a UNE articulation.

ET LA MESURE DONNE RAISON A CET ORDRE, CHIFFRE EN MAIN (course du 2026-08-14) :
    anisotropie ARMEE   -> `chestL` meshpen = 0.0022 m   (ns=2 ET ns=4 : identique)
    anisotropie DESARMEE-> `chestL` meshpen = -1.7e-07 m (aucun contact)
Le plafond epingle du validateur vaut 0.0005 m, et la regle 6 de l'owner ne se negocie pas :
« rien ne traverse le mesh de son personnage, quelle qu'en soit la raison — une resolution pire
que le clip est pire que rien. » Une section de la spec ne rachete pas une traversee.
Mecanisme le plus probable, SIGNALE et non prouve : `PHYSDIAG5 volprio` compte 109 et 136
arbitrages par course — le lien est dispute par PLUSIEURS volumes, et la regle de priorite
(decision du 2026-08-11) en laisse gagner UN et ignore les autres. Un residu est alors possible
par construction, et aucune passe de fermeture supplementaire ne peut le fermer : c'est verifie,
passer les sous-pas de 2 a 4 ne bouge pas le chiffre d'un dix-millieme.

DONC : la classification et la MESURE par axe tournent TOUJOURS (c'est ce que l'etape 2 de la
directive reclame — « une mesure qui les distingue »), et la RAIDEUR par axe ne s'arme que sur
une chaine qui porte assez d'articulations pour la soutenir. Ce n'est pas un flag de derogation
au sens de la regle 4 : c'est un predicat de CAPACITE lu sur le rig, comme `rlk` et `nfr` le
sont deja. Le jour ou la structure arrive, il s'arme tout seul, et les constantes de sa §29 sont
deja cablees a l'endroit exact ou elles doivent agir.
```

## NOTE-16  (moteur, aux alentours de la ligne 698)

```
------------------------------------------------------------------------------------------------
LA GRAVITE DE LA FAMILLE A DEPLACE LA CIBLE DU RESSORT, ELLE NE LUTTE PLUS CONTRE LUI.

Superviseur, 2026-08-11 16:15, apres le troisieme « zero gravite sur ses seins » : « le ressort
qui ramene a la pose du modele est un rappel POSITIONNEL permanent, la gravite une force
constante bien plus faible. La cible du ressort doit s'incliner avec l'ancre, de sorte qu'a 60
degres l'equilibre lui-meme soit deplace. Sans ca, aucun reglage de gravity= ne produira jamais
quoi que ce soit. »

PREMIERE REPONSE (7e passe) : deplacer la CIBLE du ressort plutot qu'ajouter une force, d'une
distance valant `gravity x 0.33 x longueur_d_os`. Elle a ete essayee, mesuree, et elle a ECHOUE :

  * mesure du 2026-08-11 17:06, chestL : sag = 0.0156 m — la plus petite des 22 chaines, sept
    fois moins que backhair (0.1149) ;
  * le superviseur a TRIPLE `gravity=` (0.45 -> 1.30) entre deux builds : sag inchange a 0.0156.
    Une grandeur qui ne bouge pas quand son propre reglage est triple ne depend pas de ce
    reglage. C'etait la preuve, et elle etait deja dans le tableau.

POURQUOI. Une cible plafonnee a une fraction de l'os est ecrasee par la contrainte de longueur
des qu'elle est dirigee LE LONG de l'os : la contrainte n'autorise qu'une rotation autour de
l'attache, donc la composante radiale est annulee par construction et ce qui survit est un
residu du second ordre, insensible au reglage. C'est exactement la geometrie d'un sein, dont l'os
part du buste vers l'avant pendant que l'inclinaison fait basculer la gravite... vers l'avant.
Et 0.33 etait un nombre invente, sans rien derriere (SPEC 7).

CE QUI EST FAIT MAINTENANT : la gravite est une FORCE pour les deux familles, exactement comme la
famille B que l'owner a validee sur les bretelles. L'equilibre statique vaut alors g_eff/k2 —
proportionnel a `gravity=`, donc reglable a l'oeil, et sans constante inventee. Avec le reglage
du jour (stiffness 1.45, mass 1.45 => k2 = 0.0159, gravity 1.30) la poitrine dispose de
1.30 x 11.16 / 0.0159 = 912 u = 22 cm d'affaissement d'equilibre AVANT projection, dont la part
utile est la composante TANGENTIELLE — publiee a cote du resultat (phys-stat 19) pour que
« la gravite n'arrive pas » et « la geometrie l'annule » cessent d'etre indiscernables.
La contrainte de longueur transforme ensuite ce deplacement en ROTATION autour de l'ancre a
longueur invariante : c'est la regle de l'owner, et elle s'applique sans exception ici aussi.
------------------------------------------------------------------------------------------------
```

## NOTE-17  (moteur, aux alentours de la ligne 734)

```
SENTINELLE « aucun contact ». Un residu de penetration reel ne depasse jamais quelques milliers
d'unites, donc -1e9 ne peut pas etre confondu avec une mesure ; le SEUIL de reconnaissance est en
revanche a -1e6 et pas a -999999999.0, parce que ce dernier s'arrondit a -1e9 EXACTEMENT en
flottant 32 bits : la comparaison devenait fausse et la sentinelle traversait jusque dans le
tableau (-244140 m sur earL, mesure du 2026-08-11). Meme piege qu'un 0 truthy.
ZONE MORTE du test de cote, en cosinus. Le test « le lien est-il du mauvais cote de l'axe ? » est
un SIGNE de produit scalaire : quand le lien frole le plan de l'axe, le vrai produit vaut ~0 et
son signe se decide sur l'arrondi, donc le solveur peut miroiter puis se re-miroiter sans fin.
On n'agit donc que quand le lien est FRANCHEMENT de l'autre cote : cos < -0.05. Comparaison au
carre, sans racine, parce que ce test est dans la boucle chaude.
CE QUI EST MESURE, et rien de plus : sur x86 la zone morte fait passer les corrections de 8338 a
7313 par course et le residu de 638 a 595, sans rien changer aux amplitudes. Une course device a
bien rapporte 85 396 420 corrections, mais SON squelette n'etait pas pose (toutes les mesures a
zero, 13 millions de paires « lien entierement dans le volume ») : ce chiffre-la ne dit rien sur
arm64, il dit que la course etait degeneree. Ne pas le citer comme une divergence de backend.
```

## NOTE-18  (moteur, aux alentours de la ligne 838)

```
------------------------------------------------------------------------------------------------
QUEL VOLUME CONTRAINT QUELLE CHAINE — l'instrument que trois cycles de suite ont nomme comme
manquant, sans jamais le poser.

CE QU'IL MANQUAIT, mot pour mot dans le rapport du cycle 21 : « il faudrait la penetration par
(lien, VOLUME), toujours pas instrumentee ». La course sait dire qu'une chaine est en contact
17893 frames sur 17893 ; elle ne sait pas dire CONTRE QUOI. Sans ce nom, `lbang` en contact
permanent reste une enigme, `chestR` qui recule 6466 fois contre `chestL` 104 reste une
asymetrie sans cause, et chaque cycle repart en devinant.

NATURE : un COMPTE de triplets (frame, MAILLON, volume). REPERE : celui du volume teste, c'est
contre lui que la profondeur `res` est evaluee. LECTURE QUAND LE DEFAUT EST ABSENT : zero — un
maillon qu'aucun volume ne contraint n'a aucune ligne.

2026-08-14 — LE SEAU PORTE DESORMAIS L'INDEX DU MAILLON. Il etait indexe (chaine, volume) et
jetait `l` a l'ecriture ; deux cycles de suite ont bute sur « lequel des deux maillons du sein
viole ? » sans pouvoir y repondre. Indexation : `(sc * PHYS-LINKS + l) * PHYS-COLS + ci`, taille
`PHYS-SCL * PHYS-COLS`. La salle publie `PHYSCVOL c= l= ci= n=`, et le tableau continue de
sommer sur les maillons pour son total par chaine, sinon la serie historique de
`ROOM-CONTACT-VOL` cesserait d'etre comparable. `*phys-cfh*` (le conflit) reste PAR CHAINE.

Il ne compte QUE pendant la passe de MESURE (le meme drapeau que `buried`, arme une fois par
frame par `phys-pen-chain`) : les trois reculs et leurs treize pas de dichotomie ne comptent pas,
sinon le chiffre mesurerait l'effort du solveur au lieu de l'obstacle.
```

## NOTE-19  (moteur, aux alentours de la ligne 865)

```
------------------------------------------------------------------------------------------------
DIAGNOSTIC PAR CHAINE (6e passe de l'owner). Les trois defauts qu'il decrit se decident chaine
par chaine, donc les compteurs qui les mesurent sont PAR CHAINE — un total global ne dit pas si
ce sont les meches fines qui jittent ou les sangles de cheville.
  0 selfcol  corrections venues d'un volume porte par les PROPRES joints de la chaine. « Une
             meche est en collision permanente avec elle-meme » : doit valoir ZERO, et le
             controle positif (*phys-self-inject*) desarme l'exclusion pour le faire monter.
  1 retreat  reculs vers la pose du modele (le limiteur violent : il saute)
  2 flip     (lien, volume) qui ont CHANGE d'etat de contrainte d'une frame a l'autre. C'etait un
             interrupteur binaire evalue chaque frame sur la pose du modele : quand il bascule,
             la position du lien saute. C'est la mesure du defaut « jitter » lui-meme.
  3 inv      inversions corrigees (le lien etait passe du mauvais cote de son attache)
  4 invres   inversions RESIDUELLES apres tout le solveur : doit valoir ZERO
  5 elong    pire allongement RELATIF du premier lien libre (|l/l0 - 1|) : « les seins
             s'allongent sur les changements brusques de direction » — doit rester sous 3 %.
  6 raddrop  fois ou le PLAFOND D'EXCURSION d'un lien seul (son propre rayon mesure) a mordu.
             C'est un suppresseur, donc SPEC 7 exige qu'il chiffre ce qu'il retire, PAR CHAINE :
             un affaissement gravitaire ecrete par ce plafond se lit ici et nulle part ailleurs.
  7 bendcut  DEGRES retires par l'attenuation d'angle des CHEVEUX, cumules sur la fenetre.
             NATURE : un angle cumule, donc un SUPPRESSEUR chiffre (SPEC 7). REPERE : celui de
             l'attache du maillon, comme la mesure d'angle elle-meme. LECTURE QUAND LE DEFAUT EST
             ABSENT : 0 — une meche qui ne se replie jamais au-dela de sa limite geometrique ne
             paie rien, et c'est le cas de lmidhair (116 deg mesures pour une limite de 141.6).
  8 shape    pire ECART RELATIF du maillon a sa pose de modele, |p - T| / longueur de son os.
             NATURE : un rapport sans dimension — la DEFORMATION que le skinning lineaire impose
             a la chair, pas une amplitude : deux sommets voisins dont les poids different d'un
             dixieme s'ecartent d'un dixieme de ce nombre. C'est la grandeur de « ca change de
             taille, plus petit plus gros ecrase » (owner, 11e passe), que ni tipvar (une
             variance) ni elong (la longueur de l'OS, qui ne bouge pas) ne pouvaient decrire.
             REPERE : aucun, c'est une longueur sur une longueur mesuree depuis l'attache.
             LECTURE QUAND LE DEFAUT EST ABSENT : 0 (le maillon est a sa pose de modele).
 10 tiprot   pire ROTATION D'OS effectivement ECRITE dans la matrice du DERNIER maillon, en
             degres. NATURE : un angle. REPERE : celui de l'attache du maillon. LECTURE QUAND LE
             DEFAUT EST PRESENT : ZERO — c'est le defaut, le dernier maillon ne recevait qu'une
             translation, donc sa peau etait cisaillee de toute la rotation manquante. C'est donc
             une mesure a l'envers des autres : un NON-ZERO est la preuve d'execution du chemin
             neuf, et il doit valoir la deviation angulaire que ROOM-GRADIENT publie pour ce meme
             maillon (chestL 39.29 deg, earL 35.95, toestrapL 15.39 sur la course du 2026-08-12).
  9 buried   paires (lien, volume) ou le lien est ENTIEREMENT dans un volume A SA POSE DE MODELE,
             donc sans surface devant lui — le compteur global existait deja, il est ici PAR
             CHAINE. C'est la mesure du « bas du pantacourt avale a l'interieur des mollets,
             comme s'il s'arretait aux genoux » : un pan dont la pose de modele est dans la
             jambe n'a rien a traverser, donc meshpen reste a zero pendant que l'owner le voit
             disparaitre. NATURE : un compte de paires. LECTURE QUAND LE DEFAUT EST ABSENT : 0.
  11 side     paires (lien, volume) ou le lien a TRAVERSE l'axe du volume dans lequel sa pose de
             modele se trouvait : il est du COTE OPPOSE a celui que l'auteur lui donne.
             C'est la mesure que les DIRECTIVES reclament depuis la 11e passe (`ROOM-SIDE`), et
             elle existe parce qu'aucune des autres ne peut voir ce defaut-la : une profondeur
             de penetration est MAXIMALE sur l'axe et REDESCEND quand le lien ressort de
             l'autre cote, donc un lien qui a traverse de part en part rend une profondeur
             faible — indistinguable d'un lien sagement dehors. C'est pour ca que « le bas du
             pantacourt est a l'interieur des mollets » et « en cinematique les lunettes
             traversent le buste pour aller se poser dans le dos » coexistent avec meshpen=0.
             NATURE : un COMPTE de paires, pas une distance — le defaut est un changement de
             COTE, une grandeur discrete, et une distance ne peut pas le decrire.
             REPERE : celui du volume — direction allant du point le plus proche de son AXE vers
             le lien, comparee entre la pose du modele et maintenant. Ni monde, ni ancre : c'est
             le volume qui a deux cotes.
             LECTURE QUAND LE DEFAUT EST ABSENT : 0. Un lien qui reste du cote ou l'auteur l'a
             pose ne compte jamais, quelle que soit son amplitude.
  12 volprio  paires (lien, volume) que la DECISION 1 a ECARTEES, parce qu'un autre volume
             decidait deja pour ce lien cette frame. C'est le seul chiffre qui dise OU les
             volumes se contredisent, et il manquait : sans lui, `ROOM-INVERSIONS residual=379`
             n'est attribuable a rien et retombe dans « un scalaire pour une forme ».
             NATURE : un COMPTE de paires sur la fenetre, pas une profondeur.
             REPERE : sans objet — c'est un compte d'evenements de decision.
             LECTURE QUAND LE DEFAUT EST ABSENT : 0, et c'est le cas courant — un lien qui n'est
             en conflit avec aucun volume n'ecarte personne. Une chaine dont ce compteur est
             GRAND est une chaine que des volumes se disputaient, donc une chaine que le recul
             epinglait (kneeflapR : retreat 15913 sur 17893 frames).
  13 libre — il portait l'ecart radial du mecanisme retire le 2026-08-14 (pierre tombale plus haut).
14 = `rootrot`, l'angle ecrit dans la 3x3 du maillon `rootlock` (voir le bloc d'ecriture).
15 = `raddrop-m`, le PRIX du mur dur d'excursion : somme, par chaine, de l'excursion qu'il a
     retiree. Le compte (slot 6) disait combien de fois il mordait, jamais combien il coutait.
17 depuis le 2026-08-13 : le slot 16 porte l'erreur de longueur que le repli du recul AURAIT
ecrite (phys-retreat-chain), gardee comme controle positif de sa correction.
------------------------------------------------------------------------------------------------
SPEC 18 — LA SURFACE REELLE DU PERSONNAGE. Mesure du 2026-08-13 (probe_skin_in_volume.py, sur le
mesh LIVRE) : les volumes de collision representent 29.7 % de la geometrie que la physique
pilote — 0 % pour backhair et les deux pantflap, 10 % pour les lunettes (531 sommets sur 0.38 m
decrits par deux billes). `meshpen`, ROOM-SIDE et SELFCOL mesurent tous contre ces VOLUMES : leur
zero est donc compatible avec tout ce que l'owner voit. Les compteurs sont honnetes, leur DOMAINE
est trop petit. Ce qui suit ne touche PAS le solveur — c'est une MESURE contre le mesh DESSINE,
donc elle ne peut pas retirer de mouvement. 55 os portent des echantillons, 12 au plus chacun.
```

## NOTE-20  (moteur, aux alentours de la ligne 1270)

```
------------------------------------------------------------------------------------------------
QUEL VOLUME EST UNE SURFACE POUR QUEL LIEN — et pourquoi ce n'est pas un filtre de donnees.

« Traverser le mesh » suppose une surface a traverser. Un lien dont la sphere est ENTIEREMENT
contenue dans un volume a sa pose de modele n'a aucune surface de ce volume devant lui : il est
a l'interieur du corps, et il y etait deja avant qu'on simule quoi que ce soit. Le contraindre
quand meme n'apporte rien de visible et coute tout : mesure du 2026-08-11, `LpantFlap` est
enfoui a la fois dans la capsule de la cuisse (rayon 1321) et dans celle des hanches (810), dont
les normales de sortie s'opposent ; l'intersection des deux contraintes se reduit a sa pose de
modele et la chaine etait MORTE (amplitude 0.0062 m, quand le plancher de la SPEC est 0.05).

Le critere est donc geometrique, calcule a chaque frame sur la pose du modele, et identique dans
la resolution ET dans la mesure : un volume V contraint un lien L d'autant moins qu'il l'enfouit
profondement au repos. Aucun flag, aucun masque, aucune liste (DIRECTIVES 4).

POURQUOI CE N'EST PLUS UN INTERRUPTEUR. Il l'a ete : « V contraint L si et seulement si
profondeur_repos < 2*rayon(L) ». Or `profondeur_repos` est recalculee A CHAQUE FRAME sur la pose
d'auteur, donc elle traverse ce seuil en cours d'animation — et le jour ou elle le traverse, le
lien passe SANS TRANSITION de « contraint » a « libre » et saute. C'est un des deux seuils que la
6e passe de l'owner designe : « les meches fines jittent like crazy des que la tete bouge » et
« les grosses meches : rien sur les petits mouvements, hysteriques sur les brusques ». Une
reponse non lineaire, c'est un seuil, et celui-ci etait binaire.

La forme continue garde EXACTEMENT les deux extremes et interpole entre eux : plus le lien est
deja enfoui au repos, plus on lui laisse de mou, et le mou part a l'infini pile quand il est
entierement dedans.
     w = clamp01((2*rl - floor0) / rl)        w=1 des que floor0 <= rl, w=0 a floor0 = 2*rl
     plancher effectif = floor0 / w           = floor0 quand w=1, -> +inf quand w -> 0
Aucun nombre nouveau : les deux memes grandeurs (floor0, rl) qu'avant.
```

## NOTE-21  (moteur, aux alentours de la ligne 1301)

```
------------------------------------------------------------------------------------------------
UN PLAFOND QUI NE SE COLLE PAS — et c'est le correctif de « l'effet gelee ».

Owner, 11e passe (2026-08-11 21:15) : « lors de mouvements brusques il y a un effet d'etirement
et un peu gelee ou ca change de taille (plus petit, plus gros, plus long, plus court, ecrase),
c'est PAS COHERENT ». Le mot qui compte est « pas coherent » : ce n'est pas l'amplitude qui le
gene, c'est qu'elle ne suive pas le mouvement. Precision du 21:20 : « c'est pas des ballons durs
non plus, c'est naturel que ca change un peu de forme ».

MESURE, et elle est sans appel. Deviation angulaire du maillon, sous QUATRE pilotages
radicalement differents (ROOM-GRADIENT, course du 2026-08-11 23:07) :
    chestL      39.2379  39.2540  39.2541  39.2460
    pantflapL   59.9995  60.0121  60.0465  60.0049
    kneeflapL   43.7184  43.7257  43.7179  ...
    toestrapL   15.3923  15.3932  15.3926  15.3929
La meme valeur a quatre decimales sous une secousse, une translation et une inclinaison a 60
degres : la signature d'un plafond EPINGLE. Toutes les chaines a un maillon sont collees a leur
plafond d'excursion (leur propre rayon ajuste) sur la totalite du pilotage.

Un plafond dur `min(e, cap)` fait deux degats, et les deux sont dans son retour :
  * la sortie ne depend plus de l'entree — d'ou « ne bouge pas assez sur les mouvements soft,
    et ca bouge sur les brusques » : la reponse est plate au-dessus du seuil et proportionnelle
    en dessous, c'est-a-dire une MARCHE, exactement ce que la DECISION 3 du superviseur exige
    de supprimer ;
  * sa derivee est discontinue au seuil. Quand l'excitation oscille autour du plafond, la
    position ecrite alterne entre « ecretee » et « libre » a chaque frame, la peau suit en
    cisaillement lineaire, et ca donne un changement de taille qui n'est correle a rien. C'est
    la definition meme de « gelee ».

LA FORME UTILISEE ICI est une SATURATION A GENOU (remplacement du 2026-08-14, mesure plus bas).
Avec `cap` le mur — pour les cheveux, `maxangle`, une donnee du rig :
    kn = 0.84 * cap                      le genou
    cp = cap - kn = 0.16 * cap           la marge jusqu'au mur
    v <= kn  ->  f(v) = v                                     IDENTITE STRICTE
    v >  kn  ->  x = (v - kn) / cp   puis   f(v) = kn + cp * x / (1 + x)
Proprietes, toutes verifiables a la main :
  f(kn) = kn et f'(v) = 1/(1+x)^2 donc f'(kn) = 1 : AUCUNE CASSURE DE PENTE au raccord ;
  f' > 0 partout, donc strictement croissante (la sortie suit l'entree) ;
  f(v) < v pour tout v > kn, donc c'est bien un limiteur ;
  f -> cap quand v -> inf, donc LE MUR EST INCHANGE. f(cap) = 0.92 cap, f(3 cap) = 0.989 cap.

LE SEUL NOMBRE TRANSPOSE EST 0.84, ET IL N'Y EN A PAS D'AUTRE. C'est le rapport genou/mur de la
SPEC de l'owner, §22 : `NormalMaxApexDisplacement = 0.42 B0`, `HardMaxApexDisplacement = 0.50 B0`,
soit 0.42/0.50 = 0.84 — transpose comme la directive du 2026-08-13 23:35 l'ordonne (« meme
architecture de solveur, valeurs propres a chaque organe »). C'est la forme deja en service sur
la poitrine (SPEC 21, bloc du plafond positionnel) : identite sous le genou, exces seul sature.

CE QU'ELLE REMPLACE ET POURQUOI. L'ancienne forme etait le min doux de norme p (p = 4),
`f(v) = v / (1 + (v/cap)^4)^(1/4)`. Elle n'a AUCUNE ZONE MORTE : f(v) < v pour TOUT v > 0. Avec
la garde `adg2 < adeg - 0.01` de son unique appelant, son seuil de morsure effectif tombait donc
tres au-dessous du mur declare par la donnee :
    backhair 14.09 deg pour maxangle 60.99      lmidhair 15.07 / 66.39   rmidhair 15.15 / 66.79
    rbang    26.87 / 136.79                     lbang    26.95 / 137.29
soit 4.3 a 5.1 fois trop bas. Mesure en fenetre de REPOS (stimulus arrete, frames 41-149) : elle
tirait jusqu'a 91 fois sur 109 au maillon 3 de `lmidhair` et retirait 21.11 deg sur `rmidhair`
l3 — elle agissait quand plus rien n'excitait la chaine. Et l'angle qu'elle borne est l'ECART A
LA POSE D'AUTEUR (voir la note de son appelant), donc c'etait un rappel vers le dessin qui taxait
le mouvement NORMAL, pas l'attenuation des angles EXTREMES que l'owner a demandee (11e passe).
`bendcut` (PHYSDIAG3) le chiffrait : 250533 deg sur backhair, 234293 lmidhair, 186203 rmidhair,
60600 rbang, 56925 lbang, 0.0 sur les 17 autres chaines. Le mur ne bouge pas d'un degre ici :
c'est la MORSURE SOUS LE GENOU qui est retiree, et rien d'autre.

SECURITE — relacher cette morsure ne retire aucune protection qui existait : 7 passes de
collision (3 a la boucle `dotimes (it 3)` + 4 a la boucle `dotimes (it 4)`) tournent APRES
l'unique application du limiteur, donc ce n'est jamais lui qui tient le plafond en fin de frame.
------------------------------------------------------------------------------------------------
IL NE S'APPLIQUE QU'UNE FOIS PAR FRAME, ET CE N'EST PAS UN DETAIL D'IMPLEMENTATION.

Un plafond dur est IDEMPOTENT : min(min(e,c),c) = min(e,c). On peut donc l'appeler autant de fois
qu'on veut dans une boucle de Gauss-Seidel, il ne retire rien de plus. LA FORME A GENOU L'EST
SOUS LE GENOU — v <= kn donne f(v) = v, donc f^k(v) = v — MAIS PAS AU-DESSUS : chaque appel y
rapproche un peu plus du mur, donc onze appels comprimeraient la bande kn..cap. `phys-bend-chain`
l'appelle UNE SEULE FOIS PAR FRAME, en dehors des deux boucles de contraintes : c'est correct, et
ca doit le rester. L'ancienne forme, elle, n'etait idempotente NULLE PART (f(v) < v des v > 0) :
  f^11(cap) = 0.841^11 = 0.15 cap.

CE N'EST PAS UNE DEDUCTION, C'EST UNE MESURE. Cette ancienne forme, posee DANS la boucle de
contraintes, course x86 du 2026-08-12 : onze chaines sous 60 % de leur plancher —
    chestL 0.3866 -> 0.1987 (-49 %)   chestR 0.3789 -> 0.1846 (-51 %)
    kneeflapL 0.1680 -> 0.0840 (-50 %)  toestrapL 0.1279 -> 0.0654 (-49 %)
soit exactement le « tout est muted as heck » que la gate FLOOR existe pour empecher, et que
l'owner a deja vu une fois. La gate l'a arrete avant l'APK ; le plafond dur est retabli la ou il
tourne en boucle, et ce min doux ne sert plus qu'aux passes APPELEES UNE SEULE FOIS PAR FRAME.

REGLE GENERALE, parce que le piege se representera : un limiteur pose dans une boucle de solveur
DOIT etre idempotent. S'il ne l'est pas, il n'a rien a y faire — il se pose en dehors, une fois.
```

## NOTE-22  (moteur, aux alentours de la ligne 1559)

```
------------------------------------------------------------------------------------------------
CONTRAINTE 1 — CE QUE LA GEOMETRIE DU PERSONNAGE AUTORISE. Deux cas, et un seul des deux est une
longueur d'os :

  * TOUT lien libre garde EXACTEMENT la longueur que le modele donne a son os, autour de son
    attache : le lien precedent quand il y en a un, l'ANCRE quand le lien est seul. `want` est
    relu dans le squelette NON ECRIT a chaque frame, ce n'est pas un cache.
  * le seul cas particulier restant est l'os qui N'EXISTE PAS dans le modele (le joint est
    confondu avec son attache : `LpantFlap` l'etait). La sphere de rotation s'y reduit a un
    point et epinglerait le lien ; ce lien-la garde donc pour seul plafond SA PROPRE TAILLE,
    le rayon que le generateur a ajuste sur les sommets skinnes qu'il possede.
------------------------------------------------------------------------------------------------
```

## NOTE-23  (moteur, aux alentours de la ligne 1650)

```
LE COTE, ET SEULEMENT SUR LE PREMIER LIEN LIBRE — celui dont l'attache est RIGIDE.
C'est exactement ce que l'owner a demande : « une chaine A UN SEUL OS de famille A
doit rester du cote de la pose du modele ». Sur un lien PROFOND (dont l'attache est
elle-meme simulee), ce test serait une butee d'articulation a 90 degres que
personne n'a demandee.

2026-08-12 — LE PREDICAT ETAIT `l = 0`, ET IL NE POUVAIT PAS TIRER. La boucle
au-dessus saute deja tout `l < rlk` : sur une chaine `rootlock=1` le maillon 0
n'est jamais visite, donc `l = 0` n'y est JAMAIS vrai. Le test ne tournait donc que
sur les 11 chaines a un seul os, et etait structurellement mort sur les 11 autres —
oreilles, cheveux, meches, lunettes, bretelles. La colonne `inv` de la course le
dit sans ambiguite : 27 a 93 corrections sur chaque chaine a un os, ZERO sur
chacune des onze chaines rootlockees.

Or le premier maillon LIBRE d'une chaine rootlockee est dans la meme situation
geometrique qu'un os seul : son attache est le maillon rigide, qui porte la pose du
modele au bit pres. Ce n'est pas un lien profond, c'est LE lien attache a du rigide.
`l = rlk` est donc la lecture fidele de l'intention ecrite ci-dessus, et `l = 0`
n'y coincidait que par accident quand `rootlock` valait 0.

CE QUE CA CORRIGE, MESURE (colonne `tiprot`, course du 2026-08-12) : les onze
chaines sans test de cote repliaient leur maillon libre jusqu'a
    topstrapL 179.06   botstrapR 177.89   topstrapR 176.75   goggles 175.81
    botstrapL 174.55   earR 161.36        earL 156.25        lmidhair 125.76
179 degres, c'est une bretelle retournee bout pour bout : elle repart vers le
torse, et c'est « la bretelle clipe au travers de l'elastique orange ». Un tissu
cousu a l'epaule ne peut pas se replier au-dela de son propre point d'attache.
On REFLECHIT la composante le long de la direction du modele, ce qui remet le lien
de son cote SANS changer sa longueur. La zone morte evite le miroitement sans fin
quand le lien frole le plan perpendiculaire, ou le signe du produit scalaire se
decide sur l'arrondi.
```

## NOTE-24  (moteur, aux alentours de la ligne 1701)

```
PIERRE TOMBALE — LE MUR D'EXCURSION EST RETIRE DE CETTE BRANCHE, A NE PAS
REMETTRE. Il bornait |p - pose animee| par `rmax` ; mais ici la contrainte de
longueur vient de poser le lien sur une sphere, donc un plafond de CORDE y est
une BUTEE ANGULAIRE `2*asin(rmax/(2*want))` — le rapport entre la demi-epaisseur
d'un morceau de geometrie et la longueur de son os, cote a cote par accident
(chestL/R 39.2 deg, kneeflapL/R 43.7, toestrapL/R 15.4, anklestrapL/R 5.96).
Trois instruments lisaient cette butee et pas de la physique (`tiprot` a 0.03 deg
pres, `shape` = 2*sin(tiprot/2), `rootdev` = `rmax` a 0.6 mm), et son prix mesure
etait de 293.66 m d'excursion, dont 167.9 m sur `kneeflapL` seule. C'etait un
limiteur d'angle non declare sur des chaines qui ne sont pas des cheveux, alors
que l'owner a ferme ce perimetre le 2026-08-11 22:35 (« juste sur les meches,
encore moins les seins ») ; il explique `knee-tabs` mot pour mot, car aucun
reglage de ressort ne deplace un lien plaque contre une butee dure.
CE QUI BORNE LE LIEN MAINTENANT : la longueur (dure), le test de COTE, et la
collision. IL RESTE INTACT DANS LA BRANCHE `(< want 0.01)`, ou l'os n'existe pas,
ou la sphere est un point et ou la contrainte de longueur EPINGLERAIT le lien —
c'est le cas qui avait tue `LpantFlap`.
```

## NOTE-25  (moteur, aux alentours de la ligne 1721)

```
------------------------------------------------------------------------------------------------
L'ANGLE QUE LA PEAU PEUT ENCAISSER — CHEVEUX SEULEMENT (`maxangle` > 0 dans les donnees, derive
du rig par le generateur, absent partout ailleurs).

Owner, 11e passe (2026-08-11 21:15) : « certains maillons meriteraient un traitement pour eviter
de creer des angles extremes qui mettent en lumiere le lack of geometrie — soit une subdivision
intelligente, soit une ATTENUATION sur les angles extremes ». Puis le perimetre, ferme a 22:35 :
« c'est juste sur les meches, pas le reste, encore moins les seins ».
Mesure du 2026-08-11 (ROOM-GRADIENT) : lbang link1 = 178.57 deg, rbang 176.20, backhair 176.95.
178 degres, c'est une epingle a cheveux : la meche se replie sur elle-meme et la peau, qui n'a
pas les aretes pour ca, se croise.

TROIS PROPRIETES, et chacune repond a un mot de sa phrase :
  * « attenuation », pas clamp : min DOUX a genou (phys-softmin, :1277) — identite stricte sous
    0.84 * maxangle et pente continue au raccord, donc aucun a-coup au passage du seuil, et rien
    de retire tant que l'angle reste dans la zone que la donnee declare representable ;
  * « les angles EXTREMES » : la zone morte est ce qui rend la phrase vraie. La forme d'avant
    (min doux de norme p) mordait des 14 a 27 deg pour des maxangle de 61 a 137 — voir la note
    de `phys-softmin` ;
  * « certains maillons » : chaque maillon est teste separement, seul le fautif paie ;
  * longueur invariante : on ne fait que ramener la direction vers celle du modele SUR LE MEME
    ARC, donc l'os ne change pas de taille et `elong` n'en voit rien.

APPELE UNE SEULE FOIS PAR FRAME, entre la boucle de contraintes et la finition — voir la note
d'idempotence de `phys-softmin` : pose DANS la boucle, il coutait la moitie du mouvement de onze
chaines. La finition qui suit (collision puis recul) garde donc le dernier mot sur « rien ne
traverse », et le passage de longueur qu'elle contient le dernier mot sur la longueur.
------------------------------------------------------------------------------------------------
```

## NOTE-26  (moteur, aux alentours de la ligne 1858)

```
LE MEME DECALAGE, MAIS PORTE PAR L'ORIENTATION *SIMULEE* DU LIEN.

`phys-link-off!` tourne le decalage par la matrice de l'os ANIMEE. Tant qu'il vaut 0,0,0 la
difference n'existe pas ; des qu'il vaut quelques centaines d'unites, le volume est pose la ou le
lien N'EST PAS, la poussee de collision s'applique au mauvais point avec ce bras de levier, et
l'erreur croit avec l'angle parcouru. MESURE, deux fois : recentrer les volumes sur le centroide
de leur geometrie cassait backhair (-41 %) et midhair (-42/-43 %) et sortait 46 % d'allongement
d'os sur lbang. La premiere fois la cause avait ete attribuee a la TAILLE du volume ; en gardant
la taille AU BIT PRES et en ne bougeant que le centre, la casse est identique. Ce n'est donc pas
la taille : c'est ce decalage-ci.

Le lien tourne AUTOUR DE SON ATTACHE a longueur invariante (c'est la contrainte dure de la SPEC).
La rotation cherchee est donc la rotation minimale qui amene la direction d'os du MODELE sur la
direction SIMULEE, et on l'applique au decalage. Elle se calcule en DEUX REFLEXIONS — pas de
produit vectoriel, pas d'axe a normaliser :
    R = S_h o S_m   avec   S_n v = v - 2(n.v)n   et   h = m + u
(S_m envoie m sur -m, S_h renvoie -m sur u ; verifiable en une ligne avec |m+u|^2 = 2(1+m.u)).
Elle degenere seulement pour u = -m, un demi-tour exact, que la contrainte de cote interdit deja.
`b` = l'attache du lien, `p` = sa position SIMULEE (ou la position CANDIDATE que le recul teste :
le volume doit suivre le point qu'on evalue, sinon la dichotomie cherche avec un obstacle fige).
```

## NOTE-27  (moteur, aux alentours de la ligne 2031)

```
------------------------------------------------------------------------------------------------
CONTRAINTE 2 — LES COLLIDERS, avec le PLANCHER DE POSE MODELE. `floor0` est la profondeur du
MEME lien a sa place d'auteur dans le MEME volume ; le plancher EFFECTIF en derive de facon
CONTINUE (phys-vol-floor) : ce qui est deja dedans au repos y reste, ce qui va plus profond est
repousse, et un lien deja entierement dedans n'a aucune surface devant lui. Calcule a chaque
frame, par (lien, volume) — ce n'est ni un masque de donnees ni un filtre de volumes.
`sweeps` > 1 parce que sortir d'un volume peut faire entrer dans le voisin (hanche/cuisse,
crane/oreille) : un balayage unique laisse ce residu-la sur la table.

LA POUSSEE NE CHANGE PAS LA LONGUEUR DU LIEN — 10e passe de l'owner (2026-08-11 18:00) : « les
seins s'allongent de nouveau sur les mouvements brusques ». Le pari du build precedent etait
ecrit noir sur blanc : si l'etirement revient, c'est la contrainte de longueur qui cede. Il est
revenu, et la mesure le chiffre — chestL 7.0 %, chestR 7.6 %, botstrapL 113 %.

La cause est l'ORDRE, pas la contrainte : le solveur terminait sur (collision, recul) pour que
« rien ne traverse » soit vrai a la derniere operation, et la poussee de collision est une
TRANSLATION le long de la normale de sortie. Quand cette normale est dirigee dans l'axe de
l'attache — c'est exactement le cas d'un sein pousse par la capsule du buste, dont l'axe passe
par l'ancre — la translation est purement RADIALE : elle n'a aucun autre effet que d'allonger le
lien. Repasser la longueur apres coup remettait le lien dans le volume dont il venait de sortir
(penetration mesuree a +0.07 m sur rbang), donc ce n'etait pas la solution non plus.

La sortie est de rendre la poussee elle-meme compatible avec la sphere : on pousse, puis on
REPROJETTE sur la sphere de rayon `want` centree sur l'attache. Le lien tourne au lieu de
s'etirer, et « rien ne traverse » reste garanti par la derniere operation de la frame, le recul,
qui cherche son point admissible SUR CETTE MEME SPHERE (phys-retreat-chain, branche `sphere?`) en
partant de la pose du modele — admissible par construction, puisque le plancher de pose modele
est defini comme la profondeur du lien A CETTE POSE. Les deux contraintes cessent donc de se
contredire : la longueur devient dure sans que la collision cede quoi que ce soit.
------------------------------------------------------------------------------------------------
```

## NOTE-28  (moteur, aux alentours de la ligne 2234)

```
LE PLANCHER SE MESURE CONTRE LES DEUX POSES DU VOLUME, ET ON GARDE LA PLUS
PERMISSIVE. L'invariant dont depend tout le recul est « la pose du modele est
ADMISSIBLE » : dep(pose du modele) <= feff. Il tenait tant que `floor0` et
`dep` regardaient le meme obstacle. Il a cesse de tenir le jour ou `floor0` a
ete mesure contre l'INSTANTANE d'auteur (ra/rb) pendant que `dep` l'est contre
la position COURANTE (ca/cb) : pour un volume porte par un joint SIMULE — les
spheres lEara/Lbanga/Lmidhaira/lBoob — les deux membres decrivent deux
obstacles differents des que la meche voisine a bouge. La pose du modele
pouvait alors etre AVALEE par un volume deplace, et le recul n'avait plus
aucun point d'ancrage : ROOM-RETREAT-ANCHOR fallback=531, et la seule ligne de
mesure a penetration positive sur 3410 (rmidhair, chaine 6, dont les voisines
1..5 ont deja ecrit leurs joints quand elle est resolue).
Prendre le MAX des deux restaure l'invariant par construction — `floorc` est
exactement `dep` evalue en `rest` — sans jamais RESSERRER une paire par
rapport a aujourd'hui, donc sans pouvoir retirer du mouvement.
```

## NOTE-29  (moteur, aux alentours de la ligne 2269)

```
----------------------------------------------------------------
LA FERMETURE DU FRANCHISSEMENT D'AXE — LA GRANDEUR QUE `meshpen`
PUBLIE ET QUE CE SOLVEUR N'AVAIT AUCUN CODE POUR RESOUDRE.

PREUVE ARITHMETIQUE, SANS COURSE. La profondeur est bornee par
construction a `rr + rl` : `phys-collide-depth` rend
`(rr + rlink) - d` et `feff = floor0 >= 0`. Sur `anklestrapR` c'est
411 + 225 = 636 u = 0.1553 m — et la colonne publiait 0.7697 m, soit
4.96 fois le maximum atteignable. 16 chaines sur 19 depassent ainsi
leur propre borne : ce n'est pas une profondeur. C'est l'AUTRE terme
de `phys-link-pen` (:2628-2630), la DISTANCE A L'AXE DU MAUVAIS COTE
que `phys-axis-dir` ecrit dans `w`.

CORROBORATION EXACTE, PAS UNE CORRELATION : les 19 chaines a
`meshpen > 0` sont exactement les 19 de `ROOM-SIDE`, et les 3
absentes (earL, earR, toestrapL) exactement les 3 a residu nul.
C'est le meme predicat, dans le meme `when` (:2624).

C'EST L'INVARIANT QUE `phys-retreat-chain` TENAIT SANS LE DIRE : il
visait la pose du modele, qui est du BON cote de CHAQUE axe par
construction. En le retirant on a rouvert `goggles-tunnel`, que
l'owner avait FERME le 2026-08-13 12:45.

POURQUOI ICI, DANS LE BALAYAGE, ET PAS APRES LA REPROJECTION DE
LONGUEUR — C'EST MESURE, PAS SUPPOSE. Essaye apres la reprojection
(course du 2026-08-14 00:26), la fermeture devient bien la derniere
ecriture et `crossing` descend plus bas (12282 -> 8112), mais plus
rien ne tient la longueur : `ROOM-STRETCH` passe de 0.0003 a 1.2090,
soit 120 % d'allongement d'os sur `topstrapR` contre un plafond de
3 %. « Un os ne s'allonge pas » : on garde donc la reprojection en
dernier mot, et le franchissement se ferme DANS le balayage, ou les
deux contraintes se partagent les iterations.

DEPLACEMENT MINIMAL, PAS UNE ROTATION. On projette orthogonalement
sur le PLAN FRONTIERE du demi-espace admissible : le plus court
chemin qui satisfait la contrainte. Une rotation a rayon constant
jusqu'a la perpendiculaire parcourt strictement plus, et ca se
mesure — elle portait la colonne `jump` (pire saut d'UNE frame) de
0.1155 a 0.8053 m sur `botstrapL`.

CE QU'ELLE N'EST PAS. Ce qui est emprunte a la pose d'auteur est le
SIGNE D'UN AZIMUT (`ua`, une direction unitaire) — exactement
l'information que la MESURE utilise deja pour DECLARER la violation
— jamais une position, jamais une distance. Elle est IDEMPOTENTE :
des que `ua . ub >= 0` c'est un no-op, donc aucune memoire de
l'historique du contact, donc aucune hysteresis fabriquee ici. Et
elle ne borne aucune amplitude : tourner autour du membre reste
libre, seul le passage AU TRAVERS de l'axe est refuse.

NATURE : un deplacement, en unites monde. REPERE : monde. LECTURE
HORS DEFAUT : nul. Sous `*phys-side-off*` comme la mesure, pour que
le controle positif commande enfin quelque chose : il valait
`armed=15171 disarmed=15399` — 1.2 % d'ecart, c'est-a-dire rien.
----------------------------------------------------------------
SON DOMAINE EST CELUI DE L'OBSTACLE, ET IL NE L'ETAIT PAS.
(2026-08-14, correctif de ce cycle.)

L'ARMEMENT NE REGARDAIT QUE `floor0`, C'EST-A-DIRE LA PROFONDEUR DE
LA POSE D'AUTEUR. Le lien SIMULE, lui, n'entrait pas dans la
condition — on pouvait donc teleporter un maillon situe tres loin
DEHORS parce que sa pose d'auteur, elle, effleurait le volume.

PREUVE ARITHMETIQUE, SANS COURSE, sur la pire chaine de la course 7 :
  rbang pointe   distance a l'axe tete->cou = 2313.6 u
                 portee du volume  rr + rl  =  915 + 193 = 1108 u
La pointe est donc 1205 u (29 cm) DEHORS d'une sphere qu'on
l'accusait de traverser, et sa pose d'auteur n'est enfoncee que de
6 a 10 u dans cette meme sphere de 915 : elle EFFLEURE la surface.
Le moindre balayage lateral la met « de l'autre cote » de l'azimut
sans qu'elle approche jamais le crane.

ET LE PRIX EST EXACTEMENT LE `jump` QUE LA COURSE 7 A PAYE. Le
deplacement vaut `cc = dt0 * (ub w)`, donc il CROIT avec la distance
a l'axe : plus le cheveu est loin du corps, plus la correction le
teleporte. C'est la forme mesuree (`botstrapL` 0.1155 -> 0.5372 m,
`goggles` 0.1183 -> 0.4237) et c'est la regle 6 a l'envers — « une
resolution pire que le clip est pire que rien ».

CE QUI CHANGE : `(> dep 0.0)`. `dep` est deja calcule au-dessus
(:2298) — c'est la profondeur du CENTRE DU VOLUME SIMULE dans cet
obstacle-ci, avant la poussee. Le veto d'azimut ne s'applique donc
plus qu'aux maillons qui sont REELLEMENT dans le volume, la ou « de
quel cote » decide si la poussee de profondeur les sort du bon cote.
Dehors, il n'y a rien a traverser : le domaine de la RESOLUTION
devient egal au domaine de l'OBSTACLE.

CE QUE CA NE COUVRE PLUS, ET JE NE LE TAIS PAS : un maillon qui
traverserait le volume de part en part EN UNE FRAME ressort dehors,
donc `dep <= 0`, donc il echappe au veto. C'est le tunneling, et sa
reponse structurelle est la SPEC 37 de l'owner (>= 120 Hz effectifs,
2 sous-pas a 60 FPS) — PAS FAITE. La contrainte de longueur borne le
trajet d'un maillon par frame, ce qui le rend rare, pas impossible.

NATURE : un deplacement, en unites monde. REPERE : monde. LECTURE
HORS DEFAUT : nul (idempotent des que `ua . ub >= 0`). CE QUE LA
COURSE DOIT MONTRER : `jump` redescend vers sa ligne de base (~0.12 m)
sur les sangles et les lunettes, et `meshpen` REMONTE sur les meches
frontales — parce que la resolution zeroutait sa propre mesure, et
que cette mesure-la est fausse (voir la note de `phys-link-pen`).
----------------------------------------------------------------
```

## NOTE-30  (moteur, aux alentours de la ligne 2401)

```
------------------------------------------------------------------------------
LA FINITION : LONGUEUR ET FRANCHISSEMENT ALTERNES JUSQU'A CONVERGENCE.

CE QUE MESURE LE PROBLEME QUE CETTE BOUCLE RESOUT. Les deux contraintes se
defaisaient l'une l'autre, et les deux ordres possibles ont ete essayes en course :
  * decroisement AVANT la reprojection (course 00:12/00:40) : `ROOM-STRETCH` reste a
    0.0003 mais la reprojection re-croise, `ROOM-SIDE crossing` plafonne a 11282 ;
  * decroisement APRES la reprojection (course 00:26) : `crossing` tombe a 8112 mais
    plus rien ne tient la longueur, `ROOM-STRETCH` explose a 1.2090 pour un plafond
    de 3 % — REJETE, « un os ne s'allonge pas ».
Aucun des deux ordres ne suffit parce qu'il n'y a pas d'ordre gagnant : ce sont deux
contraintes simultanees. On les alterne donc, et on FINIT sur la longueur — c'est
elle qui doit etre exacte, son residu est publie et plafonne a 3 % ; le
franchissement, lui, est mesure par `ROOM-SIDE` et n'a pas besoin d'etre exact au
dernier bit pour que la piece cesse de traverser.

GEOMETRIQUEMENT LES DEUX SONT COMPATIBLES DES QUE LEUR INTERSECTION EST NON VIDE :
la reprojection contraint le lien a une SPHERE centree sur l'attache, le
decroisement a un DEMI-ESPACE. Une sphere et un demi-espace s'intersectent sauf si
la sphere est entierement du mauvais cote — cas ou aucune position admissible
n'existe, et ou la longueur gagne (l'owner l'a tranche : « une resolution pire que
le clip est pire que rien »).

NATURE : une projection alternee (Gauss-Seidel sur deux contraintes). REPERE : monde.
LECTURE HORS DEFAUT : la boucle est un no-op des le premier tour.
```

## NOTE-31  (moteur, aux alentours de la ligne 2707)

```
CHANGER DE COTE EST UNE PENETRATION, ET C'EST LA SEULE QUE LA PROFONDEUR NE PEUT
PAS VOIR. Elle est maximale SUR l'axe et redescend en ressortant : un lien qui
traverse la piece de part en part repasse donc sous son propre plancher et
ressort « admissible » de l'autre cote. Le compteur existait depuis des jours et
disait 11446 ; rien ne l'interdisait.
  goggles 4092  — « en cinematique les lunettes TRAVERSENT le buste pour aller
                   se poser dans le dos »
  pantflapR 1901 / pantflapL 1792 — « le bas du pantacourt est a l'interieur des
                   mollets, comme s'il s'arretait aux genoux »
  botstrapR 927 / botstrapL 787 / topstrap 291+291 — la bretelle et l'elastique
La regle est donc : un lien dont la POSE DU MODELE est dans un volume reste du
COTE DE L'AXE ou l'auteur l'a mis. Elle ne borne aucune amplitude — tourner
autour du membre reste entierement libre, seul le passage a travers l'axe est
refuse — et la pose du modele la satisfait par construction (produit scalaire
= 1), donc le recul garde son point d'arrivee.
Le residu publie est la distance a l'axe DU MAUVAIS COTE, en metres : ce que le
lien doit parcourir pour revenir, pas une constante choisie.
Les deux directions se lisent contre la position COURANTE du volume, comme
`dep` : les comparer a deux poses differentes de l'obstacle etait la meme faute
que celle corrigee sur `floor0`.
```

## NOTE-32  (moteur, aux alentours de la ligne 2839)

```
------------------------------------------------------------------------------
LA PLACE DE SECOURS EST CELLE QUE LE RIG DONNE, PAS UNE DISTANCE INVENTEE.

Owner, 11e passe (2026-08-11 21:15) : « le bas de son pantacourt clipe toujours a
l'interieur de ses mollets au lieu d'etre visible, COMME SI SON PANTACOURT
S'ARRETAIT AUX GENOUX ». C'est litteralement ce que la re-assise faisait.

MESURE (.autoport/probe_keira_volumes.py, 2026-08-12, sur le rig et le mesh) :
    LpantFlap est a 1349 u de Lknee dans la pose BIND — une pose parfaitement
    saine. C'est le RETARGET qui l'envoie a 1 061 104 u (259 m) a l'execution.
    La re-assise le replacait a `rl` = 429 u du genou : 3.1 fois trop pres,
    c.-a-d. juste sous le genou au lieu de la mi-mollet. Le pan de tissu etait
    donc dessine dans la jambe, et son enfouissement dans la capsule du mollet
    rendait tout volume inoperant devant lui (phys-vol-floor le declare libre).
    Elle est re-assise 18 101 fois par course : le defaut est permanent.

`rl` est un RAYON — l'epaisseur du morceau de geometrie — et rien n'autorisait a
s'en servir comme d'une LONGUEUR D'OS. Le rig porte la vraie valeur et le moteur
y a acces : la bind-pose d'un joint EST son inverse-bind (jak-hd.gc:461), donc
    L = inv(bind-pose[kk]) . bind-pose[kp]
a pour translation la position bind de kk DANS LE REPERE BIND DE kp — exactement
la meme construction que `L'_k` du retarget (jak-hd.gc:500-502). Portee par la
matrice courante du porteur, elle rend la place que le modele lui donne, direction
ET distance, sans une seule constante inventee.
A defaut (jgeo hors de portee), on retombe sur l'ancienne heuristique, et ce repli
est COMPTE a part : un secours silencieux est un defaut qui attend.
------------------------------------------------------------------------------
```

## NOTE-33  (moteur, aux alentours de la ligne 2988)

```
---------------------------------------------------------------------------
LA GRAVITE, VUE DEPUIS LE REPERE DE L'ANCRE. Owner, 6e passe : « les seins
n'ont pas l'air d'etre soumis a la gravite, aucun mouvement quand elle se
penche en avant pour souder, pas coherent du tout. »
Famille B (ce qui PEND) : gravite absolue, elle deplace l'equilibre, ca pend et
ca reste pendu — l'exception de SPEC 4. Famille A (ce qu'elle EST) : SPEC 4
exige qu'au repos on retrouve EXACTEMENT la pose du modele, donc une gravite
absolue est interdite. Mais la pose du modele est deja une pose SOUS gravite (le
sculpteur l'a modelee debout) : ce qui doit agir est l'ECART entre la gravite
d'aujourd'hui et celle de la pose de reference, dans le repere de l'ancre :

    g_effective = R_ancre^-1 . g_monde  -  g_ref

ET `g_ref` EST LA POSE DEBOUT D'AUTEUR, PAS LA BIND-POSE DU RIG — l'erreur a ete
MESUREE, pas deduite. Sa SPEC 3 : « g_ref = local gravity vector in the AUTHORED
UPRIGHT STANDING POSE », puis « standing still gives g_local = g_ref [...]
therefore a_drive = 0 ». Le code prenait `R_bind^-1 . g` en AFFIRMANT en
commentaire que debout les deux termes s'annulent ; personne ne l'avait lu a
l'execution (regle 0). Lu sur la fenetre de repos : `PHYSIDLEG c=0 gn=0.2077
tf=0.9876` — 20,77 % de g en permanence, quasi toute tangentielle, soit l'ecart
de SPEC 9 (23.86 / 19.40 u pour 0.0000). Un HD retargete n'est pas lie debout :
sa bind-pose porte l'orientation du DONNEUR, ~11,9 deg a cote (gn = 2 sin(t/2)).
Relevee a la premiere frame (`warm = 0`), sur `R_ancre^-1 . g` lui-meme et a la
MEME frame que `*phys-ux*` : terme moteur nul au bit pres, cible elastique sur la
pose d'auteur, donc l'equilibre EST la pose d'auteur. `*phys-warm*` repart a 0 a
l'init du slot (:1041) — le « rebase on teleport » de sa SPEC 7, pas un etat qui
vieillit. INCHANGE : buste incline -> `R_ancre` bouge, `g_ref` non, l'ecart
apparait et la poitrine tombe ; rotation autour de l'axe de g -> invariante.
---------------------------------------------------------------------------
```

## NOTE-34  (moteur, aux alentours de la ligne 3021)

```
---------------------------------------------------------------------------
SPEC 24 / SPEC 29 — LE TRIEDRE DE L'ANCRE, CLASSE UNE FOIS PAR CHAINE.
La derivation des trois facteurs est a la declaration de `*phys-axs*`. Ici on
ne decide que QUELLE LIGNE de la matrice de l'ancre porte quel axe, et les
deux grandeurs qui le decident sont MESUREES sur le rig, pas supposees :
  - la verticale est la ligne la plus alignee avec `gl`, la gravite vue de
    l'ancre — c'est la definition de « vertical » dans sa §24, et elle ne
    suppose rien de l'orientation du modele ni du nom des os ;
  - l'avant-arriere est, PARMI LES DEUX RESTANTES, la plus alignee avec la
    direction ancre -> joint de l'organe : pour un sein cette direction EST sa
    protrusion, et « Front/Back » de sa §24 ne designe rien d'autre ;
  - le lateral est la troisieme, par elimination — donc le triedre reste
    orthogonal par construction, sans qu'aucun axe ne soit choisi deux fois.
PREUVE : `PHYSAXIS` publie par la salle porte les trois index ET les deux
grandeurs qui les ont decides. Une classification qu'on ne peut pas relire
dans la trace resterait une supposition, et une supposition n'a jamais tenu
dans ce dossier.
```

## NOTE-35  (moteur, aux alentours de la ligne 3073)

```
LA GRAVITE ABSOLUE, VUE DE L'ANCRE, AVANT TOUTE SOUSTRACTION. C'est elle qui
sert a PRE-COMPENSER la direction de repos de la chair (section 1) ; `gl` ne
garde le terme differentiel que pour la MESURE (`*phys-st*` 18, le stimulus
gravitaire que la salle publie : 0 debout, 1.0 a 60 degres).

LA FORCE, ELLE, N'EST PLUS PRISE ICI. Une particule tombe dans le repere MONDE :
la gravite entre a la section 1 comme (0, gy, 0), sans rotation et sans
differentiel. C'est le fond du correctif du 22:40 — tant que l'equilibre etait
la pose animee, la fleche gravitaire etait plafonnee a g/omega^2 (1.3 a 1.9 cm
sur ces chaines) et aucun reglage de `gravity=` ne pouvait faire pendre une
meche (physics-attic-2026-08-11, d99b193792 : « a stiff spring allows
(g/omega^2) is all gravity can ever buy »).
```

## NOTE-36  (moteur, aux alentours de la ligne 3096)

```
---------------------------------------------------------------------------
`a_drive` — LE TERME MOTEUR, ET C'EST LA SECTION 3 DE LA SPEC DE L'OWNER,
PORTEE EN REPERE MONDE PARCE QUE L'INTEGRATEUR Y TRAVAILLE.

    a_drive = (g_local - g_ref) - a_torso + a_angular

NATURE : une acceleration, en u/frame^2. REPERE : MONDE (l'integrateur est en
position monde). LECTURE HORS DEFAUT : le vecteur nul debout et immobile.

LE PREMIER TERME EST `gl`, DEJA CALCULE : il vaut exactement (g_local - g_ref)
pour la famille A, exprime dans le repere de l'ancre. On le remet en monde par
la rotation de l'ancre, et on renormalise a sa propre longueur parce que la
matrice d'un os retargete n'est pas garantie orthonormale — sans ca l'echelle
de l'os entrerait dans l'amplitude de la gravite (meme piege que celui
corrige plus haut sur `gl` lui-meme).

LES DEUX AUTRES TERMES NE SONT PAS ECRITS ICI, ET CE N'EST PAS UN OUBLI :
l'integration se fait en position MONDE avec une attache qui bouge. Un point
libre dans le repere monde, relie a une ancre acceleree par la contrainte de
distance, subit dans le repere de cette ancre exactement `-a_torso` et le terme
centrifuge/d'Euler `a_angular`. Les ecrire en plus les compterait deux fois.
C'est ce que l'owner decrit — « ils restent en arriere puis rattrapent » : la
particule TRAINE derriere son ancre, gain < 1 et retard, au lieu de sauter avec
elle.

ET C'EST LA LE CORRECTIF DE FOND. Le moteur pilotait par `fl = -couple * acc`,
ou `acc` etait la DERIVEE SECONDE DE LA POSE ANIMEE : aucun des trois termes
ci-dessus. D'ou « un pudding sur lequel on tape tres fort AU MOINDRE
MOUVEMENT » — un a-coup d'animation, meme minuscule, produisait un pic de
force. Les trois termes de la spec valent zero quand le personnage est
immobile et varient continument : un a-coup d'animation ne peut plus produire
de coup.

FAMILLE B (ce qui PEND) : gravite ABSOLUE, inchangee. C'est l'exception de la
SPEC 4 du contrat (« ce qui doit pendre pend et reste pendu ») et elle ne
releve pas de la spec poitrine.
---------------------------------------------------------------------------
```

## NOTE-37  (moteur, aux alentours de la ligne 3172)

```
---- 1. UNE PARTICULE PAR MAILLON, INTEGREE EN POSITION MONDE. -------------

PIERRE TOMBALE — L'ANCIEN MODELE D'ECART, RETIRE le 2026-08-13 22:40 sur
ordre de l'owner (« le modele est faux, pas ses reglages »), A NE PAS
REMETTRE. Il integrait `*phys-o**`, un ECART A LA POSE ANIMEE rappele vers
zero et excite par la DERIVEE SECONDE de cette pose (`fl = -couple * acc`).
Ses quatre symptomes decoulaient d'une seule forme : l'equilibre etait le
dessin (pas de masse), la fleche gravitaire y etait plafonnee a g/omega^2
(1.3 a 1.9 cm ici, d'ou « pas de gravite » quel que soit `gravity=`), le
pilotage etait un a-coup (« un pudding sur lequel on tape au moindre
mouvement ») et l'ecart integre portait sa propre memoire (hysteresis).

CE QUI EST INTEGRE MAINTENANT : la POSITION MONDE d'un point qui porte une
masse ; `p` et `q` sont tout l'etat, et `p - q` EST l'inertie. L'animation
n'entre plus que par l'ANCRE ; `couple` n'est plus lu par le solveur.
SEULE EXCEPTION, et elle est de SPEC 2 / SPEC 9 de l'owner (le modele debout
livre EST l'equilibre 1 g, `AdditionalStandingSag = 0`, et la pose d'auteur
doit etre restauree exactement) : la famille A garde un terme ELASTIQUE vers
une direction de repos du MATERIAU — statique, portee par l'ancre, jamais la
pose animee du maillon. Une corde pure violerait sa section 9.
LE TERME MOTEUR EST SA SECTION 3, `a_drive = (g_local - g_ref) - a_torso +
a_angular` (voir `gdw` plus haut) : debout il vaut zero, donc l'equilibre est
la pose d'auteur sans pre-compensation.
```

## NOTE-38  (moteur, aux alentours de la ligne 3207)

```
SPEC 31 — GRADIENT RACINE -> POINTE, `w(r) = r^1.6..2.0`. On prend
l'exposant 2.0, borne HAUTE de l'intervalle que la spec donne
elle-meme : c'est un carre (une multiplication), et surtout ce n'est
pas un nombre choisi par moi.
  r = abscisse du maillon dans la partie LIBRE, prise au MILIEU de son
      segment (sinon la pointe rendrait r = 1 exactement, donc une
      part ancree nulle, donc une chaine a un maillon sans ressort) ;
  a = 1 - r^2 = la part ANCREE. SPEC 30 : racine profonde 90-100 %,
      intermediaire 55-85 %, mi-volume 25-55 %, distal 5-30 %, apex
      minimal — et « there shall be no hard attachment boundary », ce
      que satisfait une fonction continue et decroissante.
      Sur 4 maillons libres : 0.984 / 0.859 / 0.609 / 0.234.

NORMALISE EN MOYENNE, ET CE N'EST PAS UN DETAIL. Le gradient
REDISTRIBUE la raideur le long de la chaine ; il n'en change pas le
total. Consequence voulue et verifiable : une chaine a UN SEUL maillon
libre (poitrine, oreilles) rend exactement 1.0 et reste inchangee au
bit pres. « Poitrine sur mouvements subtils : toujours OK » est un
acquis de l'owner ; on ne le paie pas pour corriger les cheveux.
```

## NOTE-39  (moteur, aux alentours de la ligne 3348)

```
LA PRE-COMPENSATION A ETE RETIREE ICI, ET C'EST LA MEME PIECE
QUE LE PASSAGE A `a_drive`. Elle creusait d'avance, dans la
direction de repos, la fleche `g/k2` que la gravite ABSOLUE
allait produire, pour que l'equilibre debout retombe sur la
pose d'auteur. Avec `a_drive = (g_local - g_ref)` il n'y a plus
rien a compenser : debout, le terme moteur est nul et
l'equilibre EST la pose d'auteur — SPEC 2, `AdditionalStandingSag
= 0`, sans detour.

ET ELLE N'ETAIT PAS TRANSPOSABLE AUX CHEVEUX, PAR ARITHMETIQUE.
La fleche vaut `gsc*|g| / k2` ; sur `backhair` (stiffness
1.2161, mass 0.90, gravity 0.45) : k2 = (2*pi*1.2161/sqrt(0.90)
* 1/60)^2 = 0.01802, donc fleche = 0.45*11.16/0.01802 = 279 u,
pour un os de 258 u (`PHYSBONE c=2 l=3 len=258.0191`). Le
rapport vaut 1.08 : la compensation depassait la longueur de
l'os et aurait pointe la direction de repos AU-DESSUS de
l'horizontale. Etendre l'ancien modele aux cheveux etait donc
impossible ; c'est le terme moteur qui devait changer.
```

## NOTE-40  (moteur, aux alentours de la ligne 3385)

```
---- INTEGRATION EN POSITION MONDE. Trois termes, et c'est TOUT :
---- l'inertie (retenue par la trainee), la gravite, et la force
---- du materiau quand il y en a une. Aucun etat par chaine
---- au-dela de `p` et `q` : c'est ce qui rend l'hysteresis
---- impossible a fabriquer ici.
---- LA TRAINEE EST DERIVEE DE LA RAIDEUR DE CE MAILLON-CI, PAS
---- RECOPIEE DE LA CHAINE, et c'est une DERIVATION, pas un
reglage : SPEC 25 fait de `zeta` une constante du MATERIAU (0.35)
alors que SPEC 31 redistribue la raideur le long de la chaine
(`k2l`) pendant que `damping` reste UN scalaire. Sans correction,
zeta_l = dmp/(2 sqrt(k2l)) derivait d'un facteur 1.78 racine ->
pointe (mesure sur la donnee livree : pointe a 0.61-0.62 pour une
bande 0.32-0.42, rebond 8-9 % pour 31 % — trois maillons d'une
meche se comportaient comme trois materiaux). On impose donc
zeta_l = zeta_chaine, soit dmp_l = dmp*sqrt(k2l/k2).
DEUX INVARIANTS VERIFIES AVANT D'ECRIRE : sur une chaine a UN
maillon libre `k2l` vaut `k2` au bit pres, donc `kd` est inchange
(l'acquis « poitrine subtile » n'est pas paye pour les cheveux) ;
et la famille B a `ela = 0`, donc aucun `zeta` a definir.
---- SPEC 37 — LES SOUS-PAS, ET POURQUOI ILS SONT EXACTS ICI.
« The simulation shall be timestep-independent. Recommended
effective soft-body update frequency >= 120 Hz ; at 60 FPS,
2 substeps minimum ; hard impacts may use 3-4 adaptive substeps. »

CE QUE `p` ET `q` SONT VRAIMENT, et c'est la verification qui
conditionne tout le reste : la recurrence livree est un EULER
SYMPLECTIQUE, pas un Stormer-Verlet. `v = p - q` est REMPLACE par
`v*kd + f + g` puis `p += v`, donc `q` ne porte QUE la vitesse, en
unites de DEPLACEMENT PAR FRAME. Decouper la frame en `ns` est
alors une division exacte, sans aucun terme correctif : `v/ns` en
entree, `ns*v` en sortie, `k2` et `g` en `1/ns^2` (ce sont un
`w^2 dt^2` et un `a dt^2`), trainee `kds` telle que `kds^ns = kd`.
Sur un Stormer-Verlet la meme division aurait ete FAUSSE (la
difference arriere y contient un demi-pas d'acceleration) : c'est
pour ca que la nature de la recurrence se verifie avant, pas apres.
A `ns = 1` ce bloc est BIT-IDENTIQUE a celui d'hier : fns=1 donne
k2s=k2l, gg*=gsc*gdw, kds=kd, v=(p-q), une seule passe, et
`q <- p - v` rend exactement l'ancien `p`.

`ns` EST ADAPTATIF ET SES DEUX VALEURS SONT CELLES DE LA SPEC :
2 par defaut, 4 quand le maillon entre deja la frame au-dela du
genou de SPEC 22 (0.42 B0) — le « hard impact » de sa phrase.
Aucun seuil de mon invention : c'est le meme 0.42 B0 que la
saturation, et il ne s'ouvre que sur les chaines que SPEC 21
couvre (`sat`), donc les 20 autres tournent a `ns = 2` fixe.
```

## NOTE-41  (moteur, aux alentours de la ligne 3445)

```
SPEC 37 — LE PAS DE TEMPS SUIT LE MODE LE PLUS RAPIDE,
ET C'EST L'ANISOTROPIE QUI L'A IMPOSE.
« Recommended effective soft-body update frequency
>= 120 Hz ; at 60 FPS, 2 substeps minimum ; hard impacts
may use 3-4 adaptive substeps. » `ns = 2` donne 120 Hz,
soit exactement le MINIMUM de sa phrase. Or SPEC 29
multiplie la raideur laterale par 1.2195, donc la
pulsation du mode le plus rapide par sqrt(1.2195) = 1.104 :
a `ns` constant, la resolution PAR MODE baisse d'autant,
et le minimum de la spec n'est plus tenu sur cet axe.
MESURE QUI L'A MONTRE (course du 2026-08-14, pilotage
`accel`) : la penetration de `chestL` est passee de
-9.5e-07 m (aucun contact) a 0.0022 m des que
l'anisotropie a ete posee, a `ns` inchange.
Sa phrase suivante est le critere qui tranche :
« The simulation shall be timestep-independent. » Si le
resultat bouge quand on ajoute des sous-pas, c'est que le
pas precedent n'etait pas converge — le defaut est LA,
pas dans l'anisotropie. On passe donc les chaines
anisotropes a 4 sous-pas (240 Hz), ce que sa phrase
autorise nommement, et le rapport publie l'avant/apres.
```

## NOTE-42  (moteur, aux alentours de la ligne 3536)

```
SPEC 21 SOUS LA SEULE FORME QUI NE RETIRE RIEN :
UN RESSORT QUI RAIDIT. `D -> D_max tanh(D/D_max)`
est la reponse STATIQUE d'un ressort durcissant ;
ecrire la saturation sur la FORCE plutot que sur
l'ETAT donne la meme borne d'excursion en rendant
l'energie au lieu de la jeter. Forme, avec les DEUX
nombres de SPEC 22 (« normal <= 42% B0,
exceptional <= 50% B0 ») et sans transcendante :
  D <= 0.42 B0  -> facteur 1.0, IDENTITE STRICTE ;
  D  > 0.42 B0  -> F = k (Dn + cp x/(1-x)),
                   x = (D-Dn)/cp, cp = 0.08 B0.
C1 au genou (d/dx = 1 en x=0, donc aucune cassure
de pente, donc aucun a-coup) et asymptote EXACTE en
0.50 B0 : l'energie potentielle diverge en x -> 1,
donc le mur est infranchissable en continu, quelle
que soit l'energie cinetique. `B0` = SPEC 6, pris
sur la LONGUEUR D'OS mesuree du rig (`*phys-blen*`),
jamais sur une constante de l'instrument.
LES DEUX BORNES SONT DES BORNES DE STABILITE, PAS
DES REGLAGES : `x` est borne a 0.99 pour que le
facteur reste fini, et `k2s*mu` a 1.0 parce qu'un
Euler symplectique diverge au-dela de ~4. Avec
`ns = 4` sur la poitrine (k2s ~ 0.0036) le plafond
vaut ~275 la ou le mur en demande 17 : il ne mord
pas, et c'est LUI qui exigeait les sous-pas.
```

## NOTE-43  (moteur, aux alentours de la ligne 3624)

```
------------------------------------------------------------------------
SPEC 21 — LE PLAFOND POSITIONNEL EST DEVENU UN FILET, PAS LE MECANISME.
Le mecanisme est desormais le RESSORT QUI RAIDIT, applique dans l'integration
ci-dessus (voir sa note) : c'est la forme que SPEC 37 reclame nommement,
« soft displacement clamps should be preferred to abrupt positional clamps ».
UNE FORCE NE RETIRE PAS D'ENERGIE, ELLE LA REND ; ce bloc-ci, lui, ECRIT
l'etat, donc il en retire — et son prix est publie (`PHYSLIM4 sat_sum`).

POURQUOI IL RESTE QUAND MEME. Le mur du ressort est infranchissable en
CONTINU (son energie potentielle diverge en 0.50 B0), pas en discret : le
facteur de raideur est borne pour rester stable, donc un depassement
transitoire reste arithmetiquement possible. La regle 6 de l'owner (« rien ne
traverse le mesh, quelle qu'en soit la raison ») et SPEC 22 (`HardMax
0.50 B0`) ne se negocient pas : on garde un filet, et on MESURE combien de
fois il sert. `sat_n` doit s'effondrer maintenant que la force fait le
travail — s'il ne s'effondre pas, c'est le ressort qui est mal pose, et
c'est ce chiffre-la qui le dira.

A/B QUI INTERDIT DE LE RETIRER (2026-08-14, deux courses completes) : sans
aucun plafond, `chestL` traverse le torse de 0.4924 m (contre 0.0003 avec) et
l'apex monte a 1.10-1.41 B0, soit 2.8x le maximum DUR que l'owner a ecrit
lui-meme. Le retrait n'est pas un allegement, c'est une regression.

LA FORME, INCHANGEE : identite stricte sous 0.42 B0, puis l'EXCES seul est
sature, asymptote 0.50 B0 (SPEC 22, ses deux nombres). `tanh` par son
approximant de Pade (3,2) `x(27+x^2)/(27+9x^2)` — GOAL n'a pas
d'exponentielle — exact en x=3, ecart maximal 0.0235, plus petit que la
largeur de la bande 0.42..0.50 que la spec donne elle-meme.

PLACE DANS LA FRAME : apres l'etage 0 et AVANT les contraintes, pour que la
collision garde le dernier mot — regle 6.
------------------------------------------------------------------------
```

## NOTE-44  (moteur, aux alentours de la ligne 3692)

```
L'ATTENUATION D'ANGLE DES CHEVEUX, UNE SEULE FOIS. Elle reste : c'est le
traitement que l'owner a lui-meme demande (11e passe, « soit une subdivision
intelligente, soit une attenuation sur les angles extremes ») et elle est
bornee aux chaines qui portent `maxangle`, c'est-a-dire les cheveux
(« c'est juste sur les meches, pas le reste, encore moins les seins », 22:35).
CORRECTION 2026-08-14 — CE COMMENTAIRE AFFIRMAIT LE CONTRAIRE DU CODE, ET LA
PHRASE RETIREE ETAIT : « Ce n'est pas un rappel vers le dessin : elle borne un
PLI entre deux maillons voisins ». Releve dans `phys-bend-chain` (:1690-1695) :
`mx/my/mz` est pris entre les os ANIMES `kk` et `kp` (`skel bones ... transform`),
donc l'angle mesure est l'ECART DE CE MAILLON A SA POSE D'AUTEUR, pas le pli
entre deux maillons simules. C'EST DONC BIEN UN RAPPEL VERS LE DESSIN, adouci.
ELLE A DONC UNE ZONE MORTE DEPUIS LE 2026-08-14, ET C'EST TOUT LE CORRECTIF.
`phys-softmin` (:1277) etait un min doux de norme p SANS zone morte — f(e) < e
pour TOUT e > 0 — donc il rognait des l'ecart non nul : seuil de morsure
effectif 14.09 deg pour un `maxangle` de 60.99 (backhair), 15.07 / 66.39
(lmidhair), 15.15 / 66.79 (rmidhair), 26.87 / 136.79 (rbang), 26.95 / 137.29
(lbang). MESURE, fenetre de REPOS, stimulus arrete, frames 41-149 (N=109) : il
tirait 0 fois au maillon 1 et jusqu'a 91 fois au maillon 3 (lmidhair), retirant
21.11 deg sur rmidhair l3 — un SUPPRESSEUR a gradient racine->pointe qui
agissait quand plus rien n'excitait la chaine, c'est-a-dire une taxe sur le
mouvement NORMAL, pas sur les angles EXTREMES que l'owner a demande d'attenuer.
Il est donc CORRIGE, pas retire : identite stricte sous 0.84 * maxangle, meme
mur a l'infini (voir la note de `phys-softmin`). `bendcut` (PHYSDIAG3) mesure
l'effet en A/B : avant, 250533 deg backhair / 234293 lmidhair / 186203 rmidhair
/ 60600 rbang / 56925 lbang, et 0.0 sur les 17 autres chaines.
```

## NOTE-45  (moteur, aux alentours de la ligne 3736)

```
------------------------------------------------------------------------
LA FERMETURE D'ADMISSIBILITE — ET C'EST ELLE QUI REMPLACE LE RECUL.

MESURE QUI L'EXIGE, course complete du 2026-08-13 : en retirant le recul,
`meshpen` est passe de 0.0000 a POSITIF sur 19 chaines (anklestrapR 0.7697 m,
goggles 0.6058, rbang 0.5582). Le compteur le dit sans ambiguite —
`PHYSLIM retreat_n` valait 60 444 par course : le recul n'etait pas un
ornement, c'etait LUI qui rendait la frame admissible, et rien ne l'avait
remplace. La regle 6 de l'owner ne se negocie pas (« rien ne traverse le mesh
de son personnage, quelle qu'en soit la raison »), donc il FAUT une
fermeture — mais pas celle-la, qui visait la pose de l'animateur.

CE QUE FAIT CELLE-CI, ET POURQUOI ELLE NE RAMENE PAS VERS LE DESSIN : que de
la COLLISION, sans contrainte de longueur pour la defaire. Chaque passe
repousse le lien hors des volumes qu'il viole, le long de la normale du
volume, en partant de la position que la physique a produite. Aucune
reference a la pose animee n'entre ici, donc aucune memoire de l'historique
du contact : l'hysteresis que le recul fabriquait ne peut pas renaitre.

POURQUOI LA LONGUEUR CEDE ET PAS LA PENETRATION. Les deux contraintes
peuvent etre incompatibles (la sphere de rayon `want` autour de l'attache
peut etre entierement dans un volume) ; il faut donc dire laquelle gagne.
L'owner l'a tranche : « une resolution pire que le clip est pire que rien ».
La longueur a deja ete imposee onze fois et son residu est publie
(`ROOM-STRETCH`, plafond 3 %) : le prix de cette fermeture est donc mesure,
chaine par chaine, au lieu d'etre suppose.
```

## NOTE-46  (moteur, aux alentours de la ligne 3764)

```
------------------------------------------------------------------------
PIERRE TOMBALE — ABSORBER LA CORRECTION DE COLLISION DANS `q`. ESSAYE DEUX
FOIS LE 2026-08-14, MESURE, RETIRE. A NE PAS REMETTRE SOUS CETTE FORME.
L'IDEE ETAIT JUSTE ET LE DEFAUT EST REEL : la fermeture ecrit `p` sans toucher
`q`, or la vitesse de la frame suivante EST `p - q`, donc la poussee hors du
volume repart en vitesse — restitution de fait 0.53 a 0.83 sur les pointes de
`Lmidhaira`/`Rmidhaira`/`backHair1`, mesuree dans la fenetre de REPOS, stimulus
arrete, contre 0.02-0.06 aux §33/§34 (« not bounce »). Controle qui discrimine
dans la meme course : `Lbanga`/`Rbanga` rendent un NEGATIF (vraie decroissance).
CE QUI L'A CONDAMNEE, RUN16 : `chestL` tipvar 0.2174 -> 0.0833 (-62 %),
`sat_n` 1493 -> 37766, `sat_sum` 2.67e6 -> 3.35e10, penetration des meches
INCHANGEE (0.4990 / 0.5277). Aucun NaN, aucun PHYSFAIL : ce n'est pas une
divergence numerique, c'est un muselage.
POURQUOI, ET C'EST LA LECON : en contact PERSISTANT la poussee n'est pas une
impulsion, c'est la surface qui TIENT le maillon. L'absorber a chaque frame
accumule une fausse vitesse VERS la surface, qui creuse le contact, qui
agrandit la poussee — boucle positive, que le filet d'apex doit ensuite ecreter
(d'ou sat_n x25). Une reprise doit distinguer l'IMPACT du CONTACT REPOSANT :
ne retirer que la vitesse d'APPROCHE, jamais ajouter de vitesse de separation.
La premiere version (instantane avant les 4 derniers balayages purement
collision) ne changeait meme pas la grandeur du defaut (0.53 -> 0.53) : a ce
stade les 11 balayages precedents ont deja resolu les contacts.
------------------------------------------------------------------------
combien de paires (lien, volume) ont bascule d'etat de contrainte depuis la
frame precedente : la mesure du defaut « jitter » lui-meme.
```

## NOTE-47  (moteur, aux alentours de la ligne 4163)

```
---- 6. ECRITURE DANS LE SQUELETTE (SPEC 7 : c'est ca qui fait foi) ----
------------------------------------------------------------------------
LE MAILLON `rootlock` EST ECRIT LUI AUSSI — MAIS SEULE SA 3x3 CHANGE.
Residu de `hair-gradient` (PRIORITE 1), owner du 2026-08-12 14:10 : « on
dirait qu'elles sont ancrees (les pointes) au meme titre que les racines, et
que c'est ce qu'il y a entre les pointes et les racines qui bouge vraiment ».

CE QUI ETAIT ECRIT ICI, et que la garde `(>= l rlk)` interdisait : RIEN. Sur
les onze chaines rootlockees le maillon 0 n'est ni integre ni ecrit, donc le
PREMIER SEGMENT de chaque meche est fige a 0 degre en permanence — pas petit,
pas amorti : structurellement nul. La geometrie ainsi soudee au crane, comptee
sur le mesh skinne (commentaires de `physics_chains.txt`) :
  earL 82/158 · earR 81/158 · backhair 167/320 · lbang 103/324 ·
  rbang 106/307 · lmidhair 212/383 · rmidhair 219/395   -> ~50 % des cheveux.
Une chaine a 2 joints (oreilles, backhair, midhair) se reduisait donc a UN
segment rigide articule EN SON MILIEU : la moitie haute clouee au crane, la
moitie basse qui bat autour du pli. C'est mot pour mot la silhouette decrite.

POURQUOI CE N'EST PAS UNE DERIVE DE RACINE (SPEC 2, « une racine qui derive =
cheveux decolles = defaut »). Pour `l < rlk` le solveur force `o = 0` et
`p = pose d'auteur` A CHAQUE FRAME (voir le `cond` de l'integration, branche
`(or (< warm 1) (< l rlk))`). La translation ecrite ci-dessous vaut donc
`*phys-px*` = `tw` = exactement ce que le squelette portait deja : elle est un
NO-OP AU BIT PRES, et l'ancrage est preserve par CONSTRUCTION, pas par
reglage. Le residu d'ancrage mesure (`*phys-st*` 3) est releve AVANT ce bloc
et ne peut pas bouger non plus. SPEC 2 demande « ancre ET mobile » : la
POSITION reste ancree, l'ORIENTATION devient mobile.

CE QUE CA CHANGE. Le joint 0 vise desormais la position SIMULEE de son enfant,
exactement comme tout autre maillon (branche `(< (+ l 1) n)` inchangee) : le
premier segment suit le pli de la meche au lieu de le subir. Sur lbang/rbang
les trois segments deviennent libres et le degrade peut exister ; sur les
chaines a 2 joints le pli quitte le milieu de la meche pour aller au cuir
chevelu, ou il est anatomique.

CE QUE CA COUTE, ET LA PREMIERE VERSION DE CE COMMENTAIRE SE TROMPAIT.
J'avais ecrit ici « aucune position simulee ne change, le plancher est
invariant PAR CONSTRUCTION ». C'est faux, et le code le dit : ce bloc tourne
APRES le solveur, donc DANS la frame aucune position ne bouge — mais
`phys-snapshot-sim!` releve ensuite la place de tout volume porte par un joint
simule, et `phys-col-centre` place un volume a offset non nul en le passant
par la MATRICE COMPLETE du joint (`vector-matrix*!`), pas par sa seule
position. Un volume porte par un joint rootlock — il en existe, la course
d'avant ce cycle compte `sphere:Lmidhaira` parmi les obstacles de `lbang` —
se deplace donc avec l'orientation neuve, et la collision chaine<->chaine de
la frame SUIVANTE le lit. Le retour existe, decale d'une frame.
Le plancher est donc MESURE par l'A/B contre `motion-floor.txt`, pas garanti
par un raisonnement. Un commentaire n'est pas une preuve — y compris le mien.
MESURE : `rootrot` (`*phys-dg*` 14), l'angle REELLEMENT ecrit dans la 3x3 du
maillon rootlock. NATURE : un angle, en degres. REPERE : la direction d'os du
joint, pose du modele -> simulee, prise depuis son ancre. LECTURE QUAND LE
DEFAUT EST PRESENT : 0.0000 exactement, structurellement (le bloc etait saute)
— c'est le controle positif de ce correctif, et il se lit sur la course d'A/B.
------------------------------------------------------------------------
```

## NOTE-48  (moteur, aux alentours de la ligne 4224)

```
------------------------------------------------------------
ORIENTATION. « Sans ca la chaine se translate sans tourner et le
SKINNING CISAILLE » — la phrase etait deja la, et elle designait
un defaut qui n'etait traite qu'a MOITIE.

Le bloc ne tournait le lien que s'il avait un ENFANT SIMULE a
viser : `(when (< (+ l 1) n))`. Le DERNIER maillon de chaque
chaine n'en a pas, donc il ne recevait qu'une translation, sa
matrice 3x3 restant celle de la pose d'auteur. Or `chestL` et
`chestR` sont des chaines a UN SEUL maillon : leur unique maillon
EST le dernier, donc le sein n'a JAMAIS tourne — il GLISSAIT, avec
son orientation figee, jusqu'a 656 unites (16 cm) de cote.

C'est mot pour mot ce que l'owner decrit (11e passe) : « lors de
mouvements brusques il y a un effet d'etirement et un peu gelee ou
ca change de taille — plus petit, plus gros, plus long, plus court,
ECRASE ». Un os qui se deplace sans tourner cisaille sa peau
exactement de la rotation qu'il n'a pas appliquee : les sommets
ponderes sur lui suivent la translation, ceux ponderes sur le
porteur ne bougent pas, et la chair entre les deux s'etire.

Le dernier maillon vise donc SA PROPRE DIRECTION D'OS : de son
attache vers lui, pose du modele -> position simulee. C'est la
meme rotation que la contrainte de longueur lui fait deja subir
(elle ne l'autorise qu'a tourner autour de son attache), donc on
n'invente rien : on ECRIT enfin dans la matrice la rotation que le
solveur avait deja decidee.

CA NE COUTE AUCUNE AMPLITUDE : la position ecrite ne change pas
d'un bit, seule la 3x3 change. Le plancher est donc invariant par
construction, et ce n'est pas un pari — `tipvar` est calcule sur
l'ecart AVANT ce bloc.

La pose d'AUTEUR de l'attache doit venir de `*phys-t1*` et non du
squelette : le maillon precedent a deja ete ECRASE par sa position
simulee quelques lignes plus haut (la boucle ecrit dans l'ordre).
Pour le maillon 0 l'attache est l'ANCRE, que cette chaine n'ecrit
jamais, donc le squelette y porte encore la pose d'auteur.
------------------------------------------------------------
```

## NOTE-49  (moteur, aux alentours de la ligne 4312)

```
`atan` de GOAL rend des UNITES DE ROTATION (65536 =
un tour ; `cos` y est `(sin (+ 16384 x))`), pas des
radians — et `matrix-axis-angle!` en attend aussi,
puisqu'elle appelle `sin`/`cos`. La conversion
« x 57.2957795 » qui etait ici traitait la sortie
comme des radians : elle multipliait l'angle par 57,
et `sin` ne garde que les 16 bits bas, donc un
flechissement de 1 degre faisait tourner l'os de 57
degres et au-dela ca repliait modulo un tour. Toute
chaine qui flechissait ecrivait donc une orientation
fausse — c'est le « petits bugs de geometrie sur les
grosses meches » et le « polygone de la semelle de la
chaussure gauche qui se fait la malle » de la 3e
passe. La position, elle, etait juste : seule
l'orientation partait, donc rien dans les chiffres de
position ne pouvait le voir.
PREUVE D'EXECUTION du chemin neuf : l'angle
REELLEMENT ecrit dans la 3x3 du dernier maillon.
Avant ce cycle il valait structurellement zero.
```


## NOTE-50  (moteur, aux alentours de la ligne 1112)

```
UN TAUX D'AMORTISSEMENT N'EST PAS UN FACTEUR DE RETENTION.

Le solveur ecrivait, aux TROIS endroits ou il amortit une vitesse, `retention = 1 - taux`, avec
`taux = 2 zeta omega dt`. C'est le PREMIER TERME du developpement de `e^-taux`, et l'ecart n'est
pas academique : il est MESURE sur la course du cycle 10, et il explique trois lignes du tableau
de conformite d'un coup.

CE QUE LA LINEARISATION LIVRE REELLEMENT (racines de la recurrence symplectique, pas une
approximation continue : module `sqrt(det)`, phase `acos(tr / 2 sqrt(det))`) :

  site                          taux     retention      zeta livre   f livre     cible SPEC
  mode principal (l. 2775)      0.1686   0.8314         0.3789       2.327 Hz    0.35 / 2.30
  mode secondaire (l. 3711)     0.7079   0.2921         0.8384       7.009 Hz    0.65 / 5.20
  torsion SPEC 29 (l. 3826)     0.1987   0.8013         0.3682       2.873 Hz    0.35

CE QUE LA SALLE A LU, et c'est ce qui valide le modele plutot qu'une conviction :
  zeta 0.38 / 0.38 / 0.40 sur les fenetres a residu 0.002-0.004, contre 0.3789 predit ;
  f 2.325 Hz contre 2.327 predit ; rebond 0.250 / 0.269 / 0.274 contre 0.2763 predit.
Le modele tombe sur la mesure a la troisieme decimale. Ce n'est donc pas une hypothese.

ET SPEC 36 ETAIT UN FAUX VERT. Le tableau la reportait TENUE « zeta 0.65 » en LISANT LA
CONSTANTE `PHYS-SEC-Z`, jamais une mesure. Le mode livre est a 0.838 et 7.01 Hz : sur-amorti et
35 % trop rapide. C'est exactement le piege `declared-but-never-selected`, sur la section que
l'owner voit le moins mais qui porte le « second mouvement » de sa spec.

LA CONVERSION EXACTE. Pour la retention, `e^-taux`. On ne s'appuie PAS sur `exp` de
`trigonometry.gc` : c'est une routine PS2 decompilee dont la borne interne (0x435C6BBA =
220.42) ne correspond a aucune base evidente, et un solveur ne doit pas dependre d'une
primitive qu'on n'a pas verifiee. Un Pade(3,3) rend l'erreur relative sous 1e-6 sur [0, 0.8] —
la plage REELLEMENT utilisee ici est [0.021, 0.708] — et ne depend de rien :

    e^-x ~= (1 - x/2 + x^2/10 - x^3/120) / (1 + x/2 + x^2/10 + x^3/120)

MEME FAMILLE D'ERREUR DU COTE DU RESSORT. `k2 = (omega dt)^2` est le terme dominant, pas la
valeur qui fait rendre `omega` a la recurrence. Sur le mode principal l'ecart vaut 1.2 %
(2.327 Hz lus pour 2.300 nominal) ; sur SPEC 36, ou `omega dt` vaut 0.545, il vaut 35 %. La
valeur exacte s'obtient en IMPOSANT les racines au lieu de les subir : on veut un module
`r = e^-zeta omega h` et une phase `theta = omega h sqrt(1 - zeta^2)`, donc

    kd = r^2                        k2 = (1 - r)^2 + 4 r sin^2(theta/2)

ECRIT `4 r sin^2(theta/2)` ET JAMAIS `1 - cos theta` : les deux sont egaux en algebre, mais
`1 - cos` perd ses chiffres significatifs quand theta est petit, et theta vaut 0.06 sur le mode
principal. La forme retenue est une somme de termes positifs, donc `k2 > 0` toujours : elle ne
peut pas destabiliser la boucle.

OU LA CORRECTION EXACTE EST APPLIQUEE, ET OU ELLE NE L'EST PAS — c'est un choix, pas un oubli.
  - SPEC 36 et la torsion SPEC 29 sont des oscillateurs SCALAIRES, sans anisotropie : la forme
    exacte s'y pose en deux expressions, et elle les met tous les deux sur leur nominal.
  - Le mode PRINCIPAL porte l'anisotropie de SPEC 29 (`s0/s1/s2` sur la force, `sqrt(s)` sur la
    trainee). Y imposer aussi la raideur exacte demanderait de rendre `k2s` dependant de l'axe,
    donc de restructurer le chemin de force. On n'y corrige donc QUE la retention. Ce que ca
    laisse sur la table est chiffre et non cache : la frequence reste a 2.325 Hz au lieu de
    2.300, soit +1.1 %, sur une ligne que le cycle 10 rapporte deja DANS sa bande. Le gain
    aurait ete de 1.1 % contre un risque reel sur le seul acquis que l'owner a valide.

CE QUE LA CORRECTION DOIT PRODUIRE, ecrit AVANT la course pour qu'elle puisse la dementir :
  mode principal   zeta 0.3789 -> 0.3463    rebond 0.2763 -> 0.3136    f inchangee (2.325)
  mode secondaire  zeta 0.8384 -> 0.6500    f 7.009 -> 5.200 Hz
  torsion          zeta 0.3682 -> 0.3500    f 2.873 -> 2.711 Hz
SPEC 25 passe de +8.3 % a -1.1 % de son nominal ; SPEC 26 de -11 % a +1.2 % de sa cible 0.31 ;
SPEC 36 cesse d'etre un faux vert. Une seule derivation, quatre lignes du tableau.
```

## NOTE-51  (moteur, aux alentours de la ligne 4700) — LE TRIEDRE DE SPEC 7, ET POURQUOI IL LUI FALLAIT UN ACCESSEUR

`phys-chain-axis` ne rend que des INDICES DE LIGNE (`rv`/`rap`/`rlat`) : il dit quelle ligne porte
l'avant-arriere, jamais dans quel SENS elle pointe. Or le sens est la seule chose qui distingue
supine de prone, et il decide a lui seul de quel triplet de SPEC 10 / SPEC 11 s'applique.

La note de `*phys-fz*` fixe ce sens par une mesure — mais elle a ete ecrite quand `axa` valait 0
(« la ligne 0 EST l'avant-arriere, la ligne 2 EST le lateral »), alors que la course publie
aujourd'hui `PHYSAXIS rv=1 rap=2 rlat=0` : les roles ont ete RENOMMES depuis par l'invariant
inter-seins (`PHYSAXNAME src=1`), et le SIGNE, lui, n'a jamais ete re-mesure. Un indice de ligne
juste avec un signe perime — c'est `axis-role-labels-need-naming-measurement`, une couche plus bas.

NATURE : trois cosinus directeurs, sans unite. REPERE : le meme que `gla`, c'est-a-dire l'espace
ANCRE — et c'est le piege du bloc : `phys-axis-world` / `PHYSAXW` rendent des lignes en espace
MONDE. Croiser les deux « prouve » que le triedre est melange (`fz . ligne_AP = +0.06`) alors qu'il
ne l'est pas ; en espace ancre `fz ≈ e2` a 0.995. Toujours verifier que les deux operandes sont
dans le meme repere avant de conclure qu'un axe est mal affecte.

CE QUI DISCRIMINE : le signe de `fz` croise avec un invariant ANATOMIQUE externe releve sur le rig
LIVRE. LIGNE DE BASE : `fok=0` -> trois zeros, le triedre n'est pas releve, rien a conclure.

## NOTE-52  (moteur, aux alentours de la ligne 3706) — SPEC 10 ET SPEC 11 ETAIENT INTERVERTIES

Les colonnes `wbk` et `wfw` recevaient le triplet l'une de l'autre. Aucune constante n'est modifiee
par la correction : les memes cinq triplets, affectes a l'autre signe de `gzc`.

    gzc < 0   gravite vers l'AVANT    -> face contre terre -> SPEC 11 prone   0.900 / 0.910 / 1.230
    gzc > 0   gravite vers l'ARRIERE  -> sur le dos        -> SPEC 10 supine  1.230 / 1.090 / 0.700

TROIS PREUVES INDEPENDANTES, aucune n'est un commentaire :

1. ANATOMIE, sur le rig LIVRE (`recharged_assets/hd_anim/keira-hd-k2e.json` -> `hd_glb` =
   `out/jak1/fr3/skin/keira-hd-donor-injected.glb`), en espace chest, composante sur la ligne 2
   (celle que la course nomme `rap`) :
       Lbanga / Rbanga  (frange, AVANT du crane)      -0.3
       gogglesMid       (lunettes, portees AU VISAGE) -0.2
       backHair1 / 2    (nuque, ARRIERE)              +0.1
   Trois marqueurs, deux sens opposes, verdict unique : **+ligne2 = ARRIERE**. Les memes lignes
   nomment les deux autres axes gratuitement et confirment `rap=2` (`lBoob`/`rBoob` se separent sur
   la ligne 0 = lateral ; `head`/`hips` sur la ligne 1 = vertical). UN SEUL marqueur n'aurait pas
   suffi : la protrusion propre du sein vaut -0.0 sur cette ligne, et c'est exactement
   l'heuristique que la course C avait deja refutee.

2. MECANIQUE. A stimulus IDENTIQUE (|g_eff| = 1.4142 aux deux poles), le canal du joint rend
   0.1205 B0 d'un cote et 0.0107 B0 de l'autre. La direction BLOQUEE est celle ou il y a un corps :
   l'ARRIERE. Le seul volume en contact est `Lshoulder->chest`, normale a 95.7 % sur l'axe
   avant-arriere, et la pose d'auteur est EXACTEMENT sur sa frontiere (`dep = feff`, test strict).

3. INCOHERENCE INTERNE de l'etat livre : le morph « hanging freely » de SPEC 11 (sz=1.2195) etait
   applique la ou le joint ne peut PAS bouger, et le morph « comprime contre le thorax » de
   SPEC 10 (sz=0.7370) la ou il bouge le plus.

CHAINE DE SIGNES, FERMEE A L'EXECUTION : `gy = -11.16` -> `gl` part en (0,-11.16,0) = BAS monde
puis `vector-rotate*! gl gl w2l`, donc `gla` EST la gravite en espace ancre ; `*phys-fy*` vaut
`-g_ref/|g_ref|`, donc le HAUT, d'ou `gyc = -1.0000` debout et `wdn` qui tire bien le triplet
(1,1,1) de SPEC 9 ; `*phys-fz*` = `e[rap]` orthogonalise contre `fy`, mesure a l'execution par
`PHYSTRI` a (-0.01761, 0.09422, 0.99539), soit `e2` a 0.995.

CE QUE CA CHANGE A L'ECRAN : quand elle se penche en avant pour souder, la poitrine recevait
`sz = 0.700` — elle S'APLATISSAIT de 30 % — la ou SPEC 11 exige `1.230`, c'est-a-dire qu'elle PEND
(« the root remains relatively stable while DISTAL TISSUE becomes longer »). Le morph tournait a
l'envers.

VERIFIE PAR LA COURSE, contre `C13-PREDICTIONS.txt` ecrit avant de lire une ligne : `i=6` et `i=8`
ECHANGENT leurs triplets ; le multi-ensemble des `sz` est IDENTIQUE et `ROOM-ORI-SPAN` reste
0.7370 / 1.2195 / 0.4825 (c'est le controle qui distingue une permutation d'une deformation) ;
`det` reste 1.0000 ; le canal du JOINT est BIT-IDENTIQUE aux neuf orientations, ce qui prouve que
le canal de deformation est bien un canal de RENDU sans retro-action. SPEC 11 passe de SOUS
(0.1465 / 0.1332) a DANS sa bande (0.2823 / 0.2605, bande 0.20-0.30) sur LES DEUX chaines.

## NOTE-53  (moteur, `*phys-col-off*` ~ligne 770 et `phys-vol-floor` ~ligne 1130) — LE CONTROLE k=4 : LE MUR DE COLLISION DESARME

POURQUOI CE CONTROLE EXISTE. Le cycle 13 a mesure, a stimulus IDENTIQUE (`|g_eff| = 1.4142` aux
deux poles), un canal de joint qui rend 0.1205 B0 vers l'AVANT et 0.0107 B0 vers l'ARRIERE sur
`chestL` — un rapport de 11.3 a 90 deg et de 34.4 a 45 deg, la ou les paires LATERALES du meme
instrument et de la meme fenetre restent entre 1.16 et 1.40. Aucune anisotropie de sa SPEC 29 ne
produit ca : son rapport le plus extreme est 1.00/0.72.

TROIS SUSPECTS ETAIENT DEJA DESARMES, ET DEUX SONT EXONERES : `k=2` (contrainte de COTE) et `k=3`
(rayon de capsule) rendent des chiffres IDENTIQUES A QUATRE DECIMALES a la reference. `k=1`
(contrainte de LONGUEUR) symetrise, mais c'est le MECANISME qui confisque le degre de liberte, pas
la CAUSE de son asymetrie : `phys-len-project!` est un rehaussement RADIAL PUR, donc isotrope dans
son propre corps. L'asymetrie est EMERGENTE, et le cycle 13 a ecrit qu'il ne la devinait pas.

LE SUSPECT QUI A LA BONNE TAILLE ET LE BON SIGNE, et que rien ne desarmait : le mur de collision
plafonne a la PROFONDEUR D'AUTEUR. `phys-vol-floor` rend `floor0`, le test est STRICT (`dep >
feff`), et la pose d'auteur est EXACTEMENT sur la frontiere (`dep = floor0 = feff`). Le seul volume
en contact est `Lshoulder->chest`, dont la normale sortante est a 95.7 % sur l'axe avant-arriere.
Consequence mecanique : le premier micron vers l'ARRIERE est repousse, l'AVANT est libre. Un mur
unilateral place exactement au point de repos produit precisement un canal redresse.

CE QUE LE CONTROLE FAIT, ET POURQUOI IL PASSE PAR `phys-vol-floor`. `feff` est calcule a TROIS
sites (`phys-collide-chain` passe de comptage, `phys-collide-chain` passe de poussee,
`phys-retreat-chain`). Les desarmer un par un aurait laisse un site oublie muet — le piege
`declared-but-never-selected`. Le drapeau vit donc dans la FEUILLE que les trois appellent :
`(if (nonzero? *phys-col-off*) PHYS-VOL-FREE floor0)`. Un seul point, trois sites couverts.

CE QU'IL N'EST PAS. Ce n'est PAS la branche `PHYS-VOL-FREE` retiree en aout (`floor0 >= 2 rl` =>
plus aucune contrainte), qui avait produit `goggles-tunnel` en declarant les lunettes libres 50 642
fois par course. Celle-la etait un COMPORTEMENT LIVRE ; celui-ci est un CONTROLE, arme a la
premiere frame de la passe k=4 et rendu a 0 en sortant de la phase d'orientation, comme
`phys-len-off-set!` / `phys-side-off-set!` / `phys-cone-off-set!` le sont deja.

COMMENT LE LIRE. Si `k=4` symetrise les quatre directions comme `k=1` le fait, le mur est la CAUSE
et la correction porte sur lui. S'il ne change rien, le mur est EXONERE comme le cote et la
capsule, la liste des suspects tombe a zero et la cause est dans la FORCE (le ressort vers la pose
d'auteur, ou le terme de gravite) — ce qui est un resultat, pas un echec.

## NOTE-54  (moteur, `*phys-len-off*` ~ligne 770) — LE CONTROLE DE LA CONTRAINTE DE LONGUEUR

Ce n'est pas un assouplissement : c'est le controle qui tranche l'hypothese de tete du cycle 8.
`ROOM-AXSEL` mesure qu'un seul axe sur trois est isolable — pousser le sein le long de son propre
axe vertical ne met que 17.7 % de la reponse sur cet axe. L'explication proposee est qu'un point
contraint sur une sphere autour de son ancre n'a que DEUX degres de liberte de translation, la ou
SPEC 24 en demande TROIS (une frequence par axe). C'est une lecture du code, pas une mesure — et
une lecture du code n'est pas une preuve.

LE CONTROLE : si la contrainte de longueur est bien ce qui confisque le troisieme degre de liberte,
la desarmer doit faire MONTER la selectivite. Si la selectivite ne bouge pas, l'hypothese est
fausse et la cause est ailleurs.

RESTE A 0 EN LIVRAISON : aucune fenetre de mesure hors des phases AXZ ne le voit non nul, et
SPEC 22 (« un os ne s'allonge pas ») garde sa contrainte dure partout ailleurs.

## NOTE-55  (moteur, `PHYS-FLESH-YIELD` ~ligne 605 et `phys-vol-floor` ~ligne 1136) — LE MUR DE COLLISION CESSE D'ETRE UN REDRESSEUR

### CE QUE LE MUR FAISAIT, ET C'EST UNE MESURE QUI LE DIT

`feff = floor0` : la profondeur admissible d'une paire (lien, volume) etait EXACTEMENT sa
profondeur a la pose d'auteur. Comme `floor0` vaut **0.0000 sur toutes les paires de la poitrine
sauf deux** (`PHYSPAIR c=0 ci=4 fl=66.1956`, `c=1 ci=7 fl=55.4145`), la regle se lisait en clair :
**la poitrine n'a pas le droit d'entrer d'un seul micron dans le thorax.**

Un mur unilateral pose exactement au point de repos ne reduit pas une reponse, il la REDRESSE.
Cycle 14, `ROOM-ORICTL-POLES`, stimulus IDENTIQUE (|g_eff| = 0.7653 a 45 deg) :

    chestL AP45   pole libre   0.13997 B0      pole bloque   0.02511 B0      rapport 5.57
    chestR AP45   pole libre   0.12980 B0      pole bloque   0.02420 B0      rapport 5.36

Sur le canal du joint (`PHYSORICTL c=0`, composante `tz`), le signe apparait et ne laisse aucune
place au doute : `i=5` (pole libre) `tz = -64.50`, `i=7` (pole bloque) `tz = -0.17`. Desarme, le
meme canal rend `-64.42` et `+83.55` : **bipolaire**. Le degre de liberte n'etait pas echange
contre autre chose, il etait confisque.

### POURQUOI C'EST UNE CONTRADICTION AVEC SA SPEC, PAS UN COMPROMIS

`SPEC 10` : « COM toward thorax: 18–28 % B0, nominal 23 % B0 ». Le mur repondait « ce qui est deja
dedans au repos y reste, ni plus ni moins », c'est-a-dire **zero**. Mesure armee : 0.1465 / 0.1332
B0, SOUS la bande. Mur desarme (k=4) : 0.2773 / 0.2561 B0, DANS la bande, **sans que `SPEC 11`
(prone), `SPEC 12` (lateral) ni les poles lateraux ne bougent de plus de 1.3 %**.

Et `SPEC 10` / `SPEC 11` sont quasi symetriques — 0.23 B0 contre 0.24 B0. La spec dit donc que le
thorax ne doit PAS raidir la reponse du COM : ce qu'il produit, sa `SPEC 34` l'ecrit, c'est de la
**deformation** (`SupineProjectionScale = 0.70`, `SupineWidthScale = 1.23`), « collision energy
should primarily become deformation, redistribution and damping — **not bounce** ».

### LA BANDE N'EST PAS CHOISIE, ELLE EST LUE DANS SA SPEC 10

`PHYS-FLESH-YIELD = 0.30` vient de `SupineProjectionScale = 0.70` : sur le dos, la projection avant
perd 30 %, donc l'apex approche le thorax de `0.30 * B0` avant que la chair ne touche l'os. C'est
le SEUL chiffre de sa spec qui dise jusqu'ou la chair s'ecrase, et c'est une ligne de `SPEC 10`
DISTINCTE de celle que l'instrument mesure (la profondeur de COM, 0.23 B0).

**C'est la difference entre poser une raideur et ajuster un parametre sur son instrument.** Dans la
bande, la seule chose qui resiste est la raideur propre de la chaine (`SPEC 24` / `SPEC 29`) : la
profondeur d'equilibre n'est pas posee, elle SORT de l'equilibre des forces, et on lit ensuite ou
`SPEC 10` tombe. L'ordre inverse — choisir la bande pour que l'instrument affiche 0.23 — est
`never-fit-a-parameter-to-the-instrument`, et le cycle 14 avait refuse de le faire pour cette
raison exacte.

`0.30 * 602 = 180.6 u`. Le mur bite donc a 180.6 u d'approche au lieu de 0 : au-dela il redevient
DUR, ce qui garde la regle 6 de l'owner (« rien ne traverse le mesh ») avec une borne, au lieu de
la garder avec une interdiction totale qui contredisait sa spec.

### CE QUE LA BANDE N'EST PAS

Ce n'est PAS un mur compliant au sens de `SPEC 23` (`F_collision` comme force dans l'equation).
Une poussee FRACTIONNAIRE ne survivrait pas a la structure du solveur : `phys-collide-chain` est
appelee **15 fois par frame** (8 + 3 + 4) avec `sweeps = 3`, soit **45 projections**, et toute
correction de la forme « retirer une fraction de l'exces » converge vers le mur dur en quelques
iterations (`e_N = band / (N + band/e_0)`, soit ~4 u apres 45 passes). Le mur reste donc une
projection dure, POSEE AU BON ENDROIT. La complaisance dans la bande est fournie par la raideur de
la chaine elle-meme, ce qui est une lecture defendable de `SPEC 23` : `F_collision` est nul tant que
la chair n'a pas touche l'os.

### L'INSTRUMENT NE BOUGE PAS AVEC LE SOLVEUR

`phys-link-pen` (le troisieme site de `feff`, celui qui publie `meshpen`) passe **`b0 = 0`** et
mesure donc toujours la profondeur au-dela de la pose d'AUTEUR. Sans ca, elargir le mur ferait
BAISSER la penetration mesuree **par construction** et le chiffre cesserait de valoir quoi que ce
soit. C'est le principe deja ecrit dans `phys-pen-chain` : « l'instrument mesure toujours contre le
solide que la DONNEE designe, quel que soit le predicat que le SOLVEUR utilise ».

### LES DEUX FORMES RETIREES AVANT CELLE-CI (historique, ne pas les remettre)

1. `floor0 / w` avec `w = (2 rl - floor0) / rl` : DIVERGE quand `floor0` approche `2 rl`. Elle ne
   disait plus « reste ou tu es » mais « enfonce-toi de plus en plus a mesure que tu es deja
   enfonce ». Mesure sur `LpantFlap` (rl = 429, capsule de mollet) : profondeur au repos 614 u,
   tolerance accordee 1082 u — 468 u de penetration EN PLUS de la pose sculptee, la moitie d'un
   mollet. C'est `pant-calf`, mot pour mot.
2. Branche `PHYS-VOL-FREE` (`floor0 >= 2 rl` => plus AUCUNE contrainte) : n'avoir aucune surface
   devant soi n'autorise pas a s'enfoncer plus loin. Colonne `buried` : les lunettes etaient
   declarees libres 50 642 fois par course, et c'est `goggles-tunnel`.

La difference avec `PHYS-FLESH-YIELD` : ces deux-la accordaient une tolerance **sans borne** ou
**proportionnelle a l'erreur deja commise**. Celle-ci est une CONSTANTE de la spec, bornee, la meme
pour toutes les paires, et le mur redevient dur au-dela.

### ADDENDA CYCLE 15 — DEUX CORRECTIONS QUE LA MESURE A IMPOSEES, DANS L'ORDRE OU ELLE LES A IMPOSEES

**(a) LA BANDE NE S'APPLIQUE QU'AU BUSTE (`phys-vol-yield`).** Le premier jet accordait la bande a
TOUS les volumes. Mesure de la course : `ROOM-CONTACT-VOL` chestL passe de 274 a 14398 frames et
fait apparaitre `Lhand->Lelbow` 1143, `Lelbow->Lshoulder` 869, `sphere:gogglesMid` 278 — c'est-a-dire
que la poitrine gagnait le droit de s'enfoncer de 44 mm dans un BRAS, une MAIN et les LUNETTES. Sa
`SPEC 10` parle de la compression contre le THORAX, et la regle 6 de l'owner interdit le reste
(« les lunettes clipent sur ses seins » est un defaut qu'il a signale six fois). Le critere est
STRUCTUREL et vient du rig, jamais d'une liste ecrite a la main (regle 4) : le volume doit porter
l'ANCRE de la chaine comme extremite. Pour `chestL`/`chestR` (ancre `chest`) ca designe exactement
`chest->main`, `neck->chest`, `Lshoulder->chest`, `Rshoulder->chest` — c'est-a-dire les 3 volumes qui
portaient 100 % des contacts au cycle 14, donc la bande garde tout son effet sur `SPEC 10`.

**(b) L'INSTRUMENT REPREND LE PLANCHER DU SOLVEUR, ET C'EST L'INVERSE DE CE QUE J'AVAIS ECRIT.**
Premier jet : `phys-link-pen` passait `b0 = 0` pour « ne pas faire baisser `meshpen` par
construction ». La course a montre que c'etait faux, et le chiffre est net — ancre a la pose
d'AUTEUR, l'instrument lit un **offset constant** egal a la bande (0.0441 m) que le controle positif
ne peut plus dominer :

    ROOM-POSCONTROL  arme 0.0668  desarme 0.0440     la gate exige arme >= 3x desarme  -> ECHEC
    ROOM-CONE        arme 0.0440  desarme 0.0441     l'arme passe SOUS le desarme      -> N'A PAS TIRE

**Une compression que la spec AUTORISE n'est pas une penetration.** La violation, c'est ce qui
depasse l'admissible — donc l'instrument doit mesurer contre le meme plancher que le solveur. Ce qui
protege contre le « j'elargis le mur, le chiffre baisse » n'est pas l'ancrage de l'instrument, c'est
que la bande est une CONSTANTE DE LA SPEC nommee et publiee, et que `skinpen` (distance signee a la
PEAU, `phys-surf-sd`) ne passe pas par `feff` du tout et ne bouge donc avec rien.


## NOTE-57  (moteur, `*phys-cpx*` ~ligne 412) — SPEC 23, LE TROISIEME DEGRE DE LIBERTE

Externalise du moteur le 2026-08-17 (cycle 16) : le plafond de 4800 lignes est un
signal, et la directive du cycle 15 disait « le prochain cycle doit externaliser avant
d'ajouter ». Le texte n'est pas resume, il est deplace tel quel.

```
============================================================================================
SPEC 23 — LE TROISIEME DEGRE DE LIBERTE, CELUI QUE LA CONTRAINTE DE LONGUEUR CONFISQUAIT.

« M.x'' + C.x' + K.x = M.a_drive + F_collision, ou `x` = relative breast COM displacement [...]
  A SINGLE SPRING ATTACHED TO THE NIPPLE/APEX IS INSUFFICIENT. »

CE QUI MANQUAIT, ET C'EST MESURE, PAS SUPPOSE. Le point integre est l'APEX, et il est projete
chaque frame sur la sphere de rayon `want` autour de son ancre (`phys-length-chain`, 11 fois par
frame). Un point sur une sphere a DEUX degres de liberte ; sa §24 en demande TROIS. Le degre
manquant est le RADIAL — et le rig dit lequel c'est : l'os `chest -> lBoob` vaut
(+0.3646, -0.9192, -0.1490) dans le triedre de l'ancre, donc **84.5 % de l'axe VERTICAL**,
celui que sa §24 appelle « intentionally the SLOWEST ». La fréquence propre verticale ne pouvait
donc structurellement pas exister, et deux cycles ont cherche une cause a un degre de liberte
absent. Controle du cycle 9, contrainte levee : la selectivite verticale passe de 17.8 % a
60.6 % et la serie s'ajuste a 2.3400 Hz contre les 2.30 Hz de sa §24.

POURQUOI IL S'AJOUTE ICI ET PAS EN LIBERANT LA PROJECTION. Sa §22 ordonne que l'OS ne s'allonge
pas (« ROOM-STRETCH <= 3 % », `el = 0.0000` aujourd'hui) et sa §22 AUTORISE en meme temps le
TISSU a s'allonger (« local tissue elongation: common 5-15 %, large 15-21 %, exceptional
21-25 %, absolute clamp 25 % »). Ce sont deux grandeurs distinctes, et le dossier a deja paye
de les avoir confondues. Le degre de liberte radial est donc celui de la CHAIR : il s'integre
comme les deux autres, avec la meme raideur projetee sur le triedre (§29) et le meme
amortissement (§25), et il atteint l'ecran par le canal de deformation qui existe deja — pas
par la position du joint. L'os reste invariant, le tissu respire.

CE N'EST PAS UN SUPPRESSEUR : il vaut ZERO au repos debout (aucune elongation), donc §9 — le
retour EXACT a la pose d'auteur — est preservee par construction. Et il n'atteint QUE les
chaines de famille A dont le triedre est arme : les organes geles par l'owner ne le voient pas.

COMMENT IL EST INTEGRE, ET POURQUOI PAS AUTREMENT. Premiere ecriture de ce cycle : un
oscillateur SCALAIRE sur la coordonnee radiale relative. RETIREE AVANT TOUTE MESURE, parce
qu'elle etait morte par construction et que le code le dit : pour une chaine de famille A,
`gdw` ne porte QUE la reorientation de la gravite (`gl - g_ref`, :2513-2523) ; la TRANSLATION du
torse n'y entre pas — elle atteint la particule par l'ANCRE qui deplace la cible du ressort
(« c'est par elle, et par elle seule, que le mouvement du crane atteint la particule — par la
contrainte, pas par un ressort »). Une coordonnee RELATIVE n'a pas d'ancre qui bouge : elle
n'aurait vu que l'inclinaison, et serait restee plate sous `updown`, `accel` et `jerk`. Un
degre de liberte qui ne repond qu'a un pilotage sur cinq aurait rendu une serie plate qu'on
aurait lue « le degre de liberte n'arrive pas », pour une raison qui n'a rien de physique.

CE QUI EST INTEGRE A LA PLACE : LE MEME POINT, SANS LA PROJECTION. Un compagnon integre avec la
MEME cible, la MEME raideur anisotrope, le MEME amortissement et le MEME pilotage que l'apex —
et qui n'est simplement JAMAIS projete sur la sphere. Son excitation vient donc du meme
mecanisme que celle de l'apex, sans terme invente. L'ecart de RAYON entre lui et la sphere de
l'os EST le degre de liberte confisque, et c'est lui qui nourrit l'elongation du tissu.
Sa borne est celle que sa §22 donne au COM (« normal <= 35 % B0, hard transient <= 40 % B0 »),
distincte de celle de l'apex (42 % / 50 %) : deux lignes de sa spec, deux bandes.

CE QUE CE N'EST PAS, ET JE L'ECRIS ICI POUR QUE PERSONNE NE LE LISE DE TRAVERS : le point
integre reste situe A L'APEX, pas au centre de masse du sein. Sa §23 nomme `x` « the relative
breast COM displacement ». Le nombre de degres de liberte est desormais celui qu'elle demande,
et la deformation locale en derive comme elle l'ordonne ; le POINT D'APPLICATION, lui, reste
celui d'avant. C'est le residu de §23, il est connu, et il est ecrit dans le rapport.
```

## NOTE-58  (moteur, aux alentours de la ligne 468)

```
============================================================================================
LA MEME DEVIATION, NON NORMALISEE — ET C'EST LA CORRECTION D'UN AVEUGLEMENT DE `*phys-lda*`.

`*phys-lda*` projette `(u/|u| - m/|m|)` : une DIFFERENCE DE DEUX VECTEURS UNITAIRES. Deux
points de la sphere unite, donc une grandeur TANGENTE a `m` au premier ordre — sa composante
RADIALE est nulle PAR CONSTRUCTION, quelle que soit la physique. Mesure sur la trace du cycle 8
(PCA des 12 fenetres d'impulsion) : la serie est PLANE, sigma3/sigma1 = 0.9 a 3.1 %, et la
direction nulle est LA MEME dans les 12 — (0.92, 0.35, 0.18) en (v, ap, lat). Autrement dit
l'instrument est aveugle a 92 % de l'axe VERTICAL, celui dont SPEC 24 dit qu'il est « le plus
lent » : sa frequence propre ne pouvait structurellement pas se lire.
LES FENETRES A CONTRAINTE LEVEE (`PHYSRINGAZ`) SONT TOUT AUSSI PLANES (0.97 a 2.5 %), et c'est
la que le cycle 8 s'est trompe de conclusion. Il avait pose la bonne hypothese — la contrainte
de longueur confisque le degre de liberte — puis l'a declaree REFUTEE parce que la lever ne
changeait pas la selectivite. Mais il a EVALUE ce controle avec `*phys-lda*`, qui ne peut pas
voir le degre de liberte que le controle venait de rendre. Un controle valide, lu par un
instrument aveugle a ce qu'il restaure, ne refute rien.
Et les deux manques se superposent, ils ne s'excluent pas :
- le SOLVEUR n'a pas de mouvement radial quand la contrainte est armee — `el`, l'allongement
d'os du meme bloc, vaut `0.0000` sur TOUTES les courses de la phase (`PHYSSTR el=`), donc la
longueur est exactement invariante et le point vit sur une sphere : 2 degres de liberte de
translation la ou SPEC 24 en demande 3 ;
- la MESURE ne le verrait pas non plus si on le rendait.
L'axe VERTICAL etant a 92 % l'axe RADIAL, c'est precisement la frequence que SPEC 24 appelle
« la plus lente » qui est doublement inaccessible. `*phys-ldb*` retire le second manque ; le
premier se lit alors sur les fenetres a contrainte levee, et lui seul releve du solveur.

NATURE : deplacement instantane signe du maillon par rapport a sa pose d'auteur, en UNITES DE
JEU (u) — pas un ecart de directions. Les TROIS degres de liberte sont portes.
REPERE : le meme triedre orthonorme de l'ANCRE (torse) que `*phys-lda*`, meme ordre (v, ap, lat),
meme instant, meme point de la frame — les deux series sont donc directement comparables, et
leur ECART EST LA MESURE DE L'AVEUGLEMENT.
LECTURE QUAND LE DEFAUT EST ABSENT : (0,0,0) exactement, a la pose du modele.
`*phys-lda*` N'EST PAS RETIREE ni modifiee : elle continue d'etre publiee telle quelle, pour que
les chiffres du cycle 8 restent lisibles et que la comparaison ait un avant.
```

## NOTE-59  (moteur, aux alentours de la ligne 2863)

> **PERIMEE DEPUIS LE CYCLE 32 (2026-08-19), ET ELLE AFFIRME L'INVERSE DU CODE.** Cette section conclut que la garde « RESTE SUR `rlk` ». Le cycle 32 l'a changee en `(>= l rlk)` : le point libre de §23 existe desormais sur TOUS les maillons, et le distal est passe de 0 valeur non nulle sur 150 a 150 sur 150, sur six canaux. L'etat courant est decrit par **NOTE-80**, qui fait foi. Ce qui suit est conserve comme trace de la decision d'alors, pas comme description du moteur.

```
---- SPEC 23 : LE TROISIEME DEGRE DE LIBERTE ----------
Voir la note de `*phys-cpx*`. Le point LIBRE part de
l'etat de l'apex a sa premiere frame, puis vit sa vie :
meme cible, meme raideur, meme traineee, meme pilotage,
et AUCUNE projection. `rlo` l'arme sur le seul maillon
qui porte l'ancre rigide.
RESTE SUR `rlk`, ET C'EST UNE CORRECTION MESUREE
(2026-08-17). Je l'avais deplace sur le DERNIER maillon
en craignant qu'a n=2 le proximal soit epingle pres du
thorax et rende le COM de SPEC 22 artificiellement petit.
Cette crainte supposait `rootlock=1` — regle qui a ete
retiree de la poitrine depuis, parce qu'elle figeait 75 %
de la chair. Le maillon 0 est donc LIBRE et porte ces
75 % : c'est lui le meilleur representant du COM, pas la
pointe.
CE QUE LA MESURE A DIT DU DEPLACEMENT, et c'est sans
appel : arme sur le distal, SPEC 24 tombe de 4 axes sur 6
DANS (residus 0.008-0.021) a ZERO LISIBLE — les six axes
se collent a f=1.200 avec des residus de 0.29 a 0.73,
« la serie ne porte pas un mode unique ». Le canal lisait
un maillon dont j'avais par ailleurs assoupli la raideur,
melange au mode du proximal : deux modes, aucun lisible.
```

## NOTE-60  (moteur, aux alentours de la ligne 3919)

```
(f) LA MATRICE, BATIE UNE FOIS PAR CHAINE ET PAR FRAME.
`D_ancre` est diagonale dans le triedre de sa §7 : `Sum_k s_k f_k (x) f_k`.
On la ramene au monde par conjugaison avec la matrice de l'ancre,
`D_monde = am^-1 . D_ancre . am` — `w2l` est deja l'inverse et il est
deja calcule, donc ca ne coute pas une inversion de plus. La ligne de
translation qui en sort est SANS OBJET : l'ecriture la remplace par la
position du joint, ce qui centre la deformation sur la RACINE du sein.
C'est exactement ce qu'exigent §10 (« the entire breast shall not simply
scale uniformly from its center ») et §30-31 (racine ancree, distal
mobile) : le champ de poids de la peau, deja gradue en r^1.63, fait le
reste — un sommet partage avec le buste ne recoit qu'une part de S.
SPEC 22/38 — L'ALLONGEMENT DYNAMIQUE DE LA CHAIR, LE LONG DU
DEPLACEMENT. « NormalDynamicStretch 0.15 / StrongDynamicStretch 0.21 /
AbsoluteStretchClamp 0.25 », et c'est mot pour mot ce que l'owner
demandait le 2026-08-11 a 21:20 : « c'est pas des ballons durs non plus,
c'est naturel que ca change un peu de forme, d'autant plus que sur des
mouvements forts ca s'ecrase, se comprime, se tire. C'est juste beaucoup
trop. » Donc : borne, CORRELEE au stimulus, et qui revient a l'arret.
L'os, lui, ne s'allonge pas — c'est un axiome separe, tenu par la
contrainte de longueur (ROOM-STRETCH <= 3 %), et les deux ne se
confondent pas.
Le tenseur est un etirement d'axe `u` (la direction du deplacement) et de
rapport `1+s`, avec les deux perpendiculaires en `1/sqrt(1+s)` : son
determinant vaut EXACTEMENT 1, donc §8 est tenue sans correction.
SPEC 23 — LE DEGRE DE LIBERTE RADIAL ARRIVE ICI, ET NULLE PART AILLEURS.
Deux contributions a UNE SEULE elongation de tissu, sommees EN VECTEUR
avant le plafond :
- celle que le deplacement du maillon impose (cinematique, deja la) ;
- celle que l'oscillateur radial de §23 porte, le long de l'axe de
l'os (`*phys-u**`, meme repere d'ancre que `*phys-o**`).
SOMMEES, PAS COMPOSEES : deux tenseurs multiplies auraient laisse
l'elongation atteindre 1.25 x 1.25 = 1.56 quand les deux axes
s'alignent, et sa §22 fixe un CLAMP ABSOLU a 25 %. Une seule norme, un
seul plafond, une seule direction : la borne de sa §22 est exacte par
construction, et `*phys-dynm*` continue de la mesurer telle quelle.
A `*phys-rr*` = 0 ce bloc rend BIT POUR BIT l'ancien : `dl` vaut
`PHYS-DYN-K * |o| / b0f` et l'axe vaut `o/|o|`, comme avant.
LE COEFFICIENT DU TERME RADIAL EST `PHYS-DYN-K`, LE MEME QUE LE TERME
TANGENTIEL, ET IL EST DERIVE D'ELLE. La premiere ecriture portait le
deplacement radial 1:1 dans l'elongation ; sa §14 l'interdit en toutes
lettres — « the majority of visible movement must come from global mass
lag and rotation, NOT from stretching the tissue by the complete
displacement magnitude » — et sa §38 donne le couple exact :
`NormalMaxCOMDisplacement 0.35 B0`  <->  `NormalDynamicStretch 0.15`
soit 0.15 / 0.35 = 0.4286, qui EST `PHYS-DYN-K` (:356, deja derive de
ces deux memes lignes pour le terme tangentiel). Quatre autres sections
donnent le meme ordre par une voie independante : §14 (COM 15-25 % ->
+7 a +13 %), §16 (25-35 % -> +16 a +21 %), §17 (10-18 % -> +5 a +10 %),
§20 (15-22 % -> +5 a +12 %) — un rapport de 0.47 a 0.64. Le meme
coefficient pour les deux composantes est donc sa regle, pas un reglage.
```

## NOTE-61  (moteur, boucle de finition de `phys-collide-chain`)

```
LES DEUX CONTRAINTES SE RESOLVAIENT SUR DEUX VARIETES DIFFERENTES, ET LA DERNIERE ECRITE GAGNAIT.

CE QUE FAISAIT LA BOUCLE `fin` AVANT CE CYCLE : (a) la fermeture de cote, puis (b) la reprojection
de longueur sur la sphere de l'attache. AUCUN terme de profondeur. Les balayages qui precedent
poussent le maillon HORS des volumes le long de la normale — donc en partie RADIALEMENT, le long
de l'os — et (b) annule exactement cette part radiale en ramenant le point sur la sphere de rayon
`want`. Le maillon revient dans le volume, et plus rien ne le reteste : la derniere ecriture du
solveur est celle qui reintroduit la profondeur.

MONTER LE NOMBRE DE TOURS NE POUVAIT PAS Y CHANGER QUOI QUE CE SOIT — chaque tour finit de la
MEME facon, sur la meme reprojection non controlee. C'est ce qui avait ete essaye et chiffre
(36 balayages : course 3.7x plus lente, residu au meme endroit).

LE CORRECTIF : resoudre les deux contraintes sur la MEME variete. La poussee de profondeur est
projetee sur le PLAN TANGENT a la sphere de l'attache, `t = (n - (n.u) u) * (fq - fe)` avec `u` la
direction attache -> maillon. (b) la renormalise ensuite, et comme le pas etait tangent, il ne
defait presque rien : l'intersection d'une sphere et du complementaire d'un volume est une calotte,
et deux projections alternees sur une calotte convergent.

AUCUN COEFFICIENT N'EST CHOISI, ET C'EST LE POINT. Le pas n'est PAS amplifie par `1/s` (le pas de
Newton exact) : il vaut la projection nue, donc la profondeur decroit d'un facteur `s^2` par tour
avec `s = sin(n,u)`. Un pas de Newton complet aurait un gain de `1/s` non borne — sur la paire la
plus profonde (`lBooc` / `Lshoulder->chest`, s = 0.231, mesure hors moteur avant d'ecrire une
ligne) il aurait deplace le maillon de 4.3 fois la profondeur, soit un saut de 0.4 m. La projection
nue ne peut pas depasser sa cible ; ce qu'elle coute, ce sont des tours, et le budget existe deja
(PHYS-FIN-ITERS = 4, et `phys-collide-chain` est appelee 15 fois par frame).

QUAND `s -> 0` LE RESIDU RESTE, ET C'EST VOULU. Une normale d'echappement alignee sur l'os veut
dire que la contrainte de longueur et le volume sont geometriquement incompatibles pour ce
maillon : aucune rotation autour de l'attache ne l'en sort. On ne cache pas ce cas derriere un
ecretage — `meshpen` le publie.

CE QUE CE CORRECTIF REMPLACE, ET LA MESURE QUI L'A REOUVERT. Le cycle 24 avait conclu que la cause
de `COLLIDE` « n'est pas dans le solveur », sur l'argument que 63 % / 73 % du residu publie existe
deja dans la pose d'auteur (`lBooc` 0.059 m dans `Lshoulder->chest`, physique eteinte). CETTE
CONCLUSION EST FAUSSE, et c'est une erreur de NATURE de grandeur : `meshpen` n'est pas une
profondeur, c'est `res = dep - feff` avec `feff = floor0 + 0.30 B0` et `floor0` la profondeur du
point de POSE D'AUTEUR contre le meme volume (phys-link-pen). La profondeur de repos est donc DEJA
retranchee, et comparer 0.059 m a 0.0938 m compare deux grandeurs differentes.
Verification numerique (`/tmp/res_invariance.py`, geometrie livree, distance de tronc de cone
identique a `phys-collide-depth`) : sous un changement UNIFORME des deux rayons d'une capsule,
`floor0` bouge de 100 u et `res` ne bouge PAS D'UN BIT (30.39 / 75.57 / 82.38 / -60.44 / 224.26 /
-212.65 avant comme apres). Un tronc de cone dont on retire d de chaque rayon est sa surface
offset : les DEUX distances se decalent de d, la difference est invariante. Redimensionner un
volume ne peut donc pas faire baisser `meshpen` — et l'hypothese que la gate ecrit elle-meme
(defaut d'ORDRE et de TERMINAISON) redevient la seule en lice.
```

## NOTE-62  (moteur, aux alentours de la ligne 3025)

```
L'ELONGATION RADIALE : LA COMPOSANTE DU POINT LIBRE LE LONG DE
L'AXE COURANT DE L'OS — c'est-a-dire selon la NORMALE de la
contrainte que la projection annule, et rien d'autre.

CORRIGE LE 2026-08-16, ET C'EST UNE MESURE QUI L'A EXIGE, pas
une relecture. La premiere ecriture prenait l'ECART DE RAYON,
`|cp - ancre| - bl`. UN RAYON EST AVEUGLE A LA DIRECTION : un
deplacement PUREMENT TANGENTIEL de longueur `d` — une rotation,
exactement ce que l'os a le droit de faire a longueur
invariante — fait passer le rayon de `bl` a `sqrt(bl^2 + d^2)`.
La rotation entrait donc EN ENTIER dans « l'elongation du
tissu ». Ce que ca a coute, lu dans la salle du 2026-08-16 :
- `rrm` monte a 0.9102 B0 sous `tilt`, la ou sa §22 borne le
COM a 0.40 B0 — 2.3x la borne dure ;
- le canal de deformation s'est colle a son plafond absolu de
25 % sur LES DIX fenetres (25.00 partout), la ou il donnait
15.56 a 21.29 et DISCRIMINAIT entre les pilotages.
Un limiteur sature ne repond plus au stimulus : c'est le
« ballon d'eau » que l'owner decrit, fabrique par ce bloc.
La projection sur l'axe de l'os rend EXACTEMENT zero pour une
rotation pure et ne garde que l'elongation vraie.
```

## NOTE-63  (moteur, aux alentours de la ligne 3175)

```
------------------------------------------------------------------------
SPEC 33/34 — LA RESTITUTION, UNE FOIS PAR FRAME, SUR LA VITESSE SEULE.
Ce que le solveur faisait jusqu'ici, et c'est de l'ARITHMETIQUE, pas une
opinion : `q` est fige a `p_int - ns*v_int` AVANT les contraintes, et la
collision n'ecrit que `p`. Une poussee `D` devenait donc integralement de la
vitesse a la frame suivante (`v = v_int + D`) — une restitution EFFECTIVE DE
+1, de l'energie INJECTEE par un contact. Sa §34 dit l'inverse en toutes
lettres : « collision energy should primarily become deformation,
redistribution and damping — NOT bounce ».
La correction est chirurgicale et ne touche QUE la part normale de contact :
v_libre = (p - D) - q     (la vitesse qu'aurait eue le lien sans le contact)
vn      = v_libre . n     (n = direction de la poussee cumulee)
si vn < 0 (il ARRIVE sur le volume) : la sortante devient -e*vn
q <- q + D + (1+e)*vn*n
LES DEUX CONTROLES SONT DES INTERRUPTEURS, PAS DES VALEURS RECOPIEES :
`*phys-rst-off*` = 1 rend EXACTEMENT le comportement d'avant ce cycle (`q`
jamais touche, donc restitution effective +1) — c'est la ligne de base ;
`*phys-rst-k*` multiplie le coefficient (15.0 -> e = 0.90 sein<->sein) et
doit faire MONTER la vitesse sortante relue en 0bis. Un compteur qui ne bouge
sous aucun des deux prouve que ce bloc n'est jamais atteint.
La POSITION n'est pas touchee : la regle 6 (rien ne traverse) reste tenue par
la meme poussee qu'avant, au bit pres.
```

## NOTE-64  (moteur, aux alentours de la ligne 651)

```
LE DOMAINE D'UNE PAIRE, ET PAS SEULEMENT SES CONTACTS — SPEC 33.
`*phys-cfh*` compte les violations. Quand il rend ZERO il ne dit pas laquelle des deux choses
s'est produite : la paire a-t-elle failli se toucher, ou est-elle restee a un metre l'une de
l'autre ? Le cycle 7 a publie « 0 contact sein<->sein sur 2978 » sans pouvoir trancher, et a
ecrit lui-meme que la cause n'etait pas etablie. C'est le piege `zero-from-an-empty-domain` :
un zero dont on ne connait pas le domaine ne prouve rien.
  `*phys-cdm*` NATURE : une longueur (profondeur d'approche MAXIMALE atteinte par la paire sur
               toute la course), en unites de jeu, 4096 u = 1 m. REPERE : monde.
  `*phys-cfl*` NATURE : une longueur (le plancher `feff` que cette paire tolere, c'est-a-dire sa
               profondeur A LA POSE D'AUTEUR). Meme unite, meme repere.
CE QU'ILS RENDENT QUAND LE DEFAUT EST ABSENT : `cdm <= cfl`, et l'ecart `cfl - cdm` est la marge
que la paire n'a jamais franchie. `cdm` NEGATIF veut dire que les deux volumes ne se sont jamais
recouverts du tout — sa valeur est alors l'oppose de la distance minimale entre les surfaces, et
c'est CE nombre qui dit si « ils s'entrechoquent » est atteignable ou hors de portee.
Ecrits une fois par (lien, volume) et par frame, dans le balayage, AVANT toute poussee.
la derniere profondeur SIGNEE calculee par `phys-collide-depth`, en unites de jeu. Ecrite a
chaque appel, lue seulement par la mesure ci-dessus, jamais par le solveur.
```

## NOTE-65  (moteur, aux alentours de la ligne 718)

```
CONTROLE k=5 — 1 = LA BORNE §22 DU CANAL RADIAL EST DESARMEE (`rcap` -> +inf), sur la fenetre
d'orientation seule. C'est le suspect que le cycle 28 a DIMENSIONNE sans pouvoir le desarmer.

POURQUOI IL EXISTE. L'ablation a cinq passes designe la CONTRAINTE DE LONGUEUR comme cause du
deficit medial de sa §12 (k=1 : le pole medial de `chestL` passe de 0.0807 a 0.2141 B0 et celui
de `chestR` de 0.0283 a 0.2095, les deux ENTRENT dans la bande 0.15-0.24 ; k=2/3/4 le laissent
a x1.00). Mais la contrainte de longueur ne peut pas etre retiree — sa §1bis exige que l'OS ne
s'allonge pas (`ROOM-STRETCH <= 3 %`). Ce qu'elle fait est CONFISQUER la composante du
pilotage LE LONG de l'os, a charge pour le canal radial de §23 de la rendre. La question
d'apres, et c'est la seule qui soit actionnable, est donc : ce canal la rend-il, ou est-il
ecrete avant ?

CE QUI LE DESIGNE, ET C'EST DEJA DANS LA COURSE LIVREE (`ROOM-RAD`) : le canal radial BRUT
`rrr` vaut jusqu'a 0.6843 B0 la ou le canal BORNE `rrm` rend 0.3900 — 43 % du signal retire —
et le pic transitoire `rrt` est colle a 0.3998-0.3999 sur les HUIT orientations non nulles des
DEUX chaines, c'est-a-dire exactement le plafond `0.40 B0`. Un limiteur actif partout ne borne
plus une exception : il publie sa propre asymptote a la place de la reponse, et c'est ce que
`ROOM-RAD-DISCRIM` lit deja sur `chestL` — `spread=10.3 % verdict=PLAT`.

CE QU'IL NE FAIT PAS : changer un octet du comportement LIVRE. Il vaut 0 partout sauf pendant
la passe de mesure k=5, que la salle arme et REND A 0 en sortant, exactement comme les quatre
autres. Ce n'est pas un assouplissement de la borne de sa §22 — c'est le controle qui dira si
cette borne est le mecanisme, avant qu'on ait le droit d'y toucher.
```

## NOTE-66  (moteur, aux alentours de la ligne 3111)

```
[NOTE-C28] CE `b0f` N'EST PAS LE RAYON DU MAILLON, ET C'EST
MESURE — mais le corriger a ete ESSAYE ET REFUTE, alors la
note reste et le code ne bouge pas. Le commentaire vingt
lignes plus haut affirme qu'a deux maillons la borne « s'
applique telle quelle a l'apex » : le mesh livre dit non. Le
joint distal est a **0.2332 B0** de la racine de chaine
(140.42 u contre B0 = 602), donc la borne de 301 u posee sur
lui vaut **2.14 x la longueur de son propre os** — un
plafond de deplacement plus grand que l'os n'impose aucune
limite d'angle, et l'apex de chair (768.7 u de la racine)
peut parcourir **2.74 B0** la ou sa SPEC 22 en autorise 0.50.
Le filet n'est pas inerte pour autant : `PHYSLIM4
sat_n=16240 sat_sum=14751666`, 908 u retires par morsure.

CE QUE LE CYCLE 28 A ESSAYE : remplacer `b0f` par le rayon
propre du maillon (0.50 x 140.42 = 70.2 u au distal, racine
inchangee). MESURE, ET REFUTE — voir
`.autoport/reports/.../C28-apexr-refutation.txt` :
  SPEC 33 chestL 487.82 -> 437.17 u  (-10 %, argmax change)
  SPEC 33 chestR 443.33 -> 509.88 u  (**PIRE de 15 %**)
  filet    16 240 -> 42 567 morsures (**x2.62**, un limiteur
           sature : il publie son asymptote, pas la reponse)
  SPEC 12 medial chestL 0.0807 -> 0.0315 B0 (**-61 %**)
Raison : seul le maillon DISTAL etait resserre. Le maillon
RACINE pivote sur l'ancre `chest` a **1040.5 u** (`PHYSBONE
c=0 l=0 len=1040.5006`) et gardait ses 301 u — c'est LUI qui
promene l'organe entier. La cinematique est le bon mecanisme,
le maillon borne n'etait pas celui qui la porte.
NE PAS refaire ce changement tel quel : commencer par mesurer
le maillon RACINE (16.6 deg permis a 301 u sur un bras de
1040.5).
```

## NOTE-67  (moteur, aux alentours de la ligne 3641)

```
+Z = L'AXE AVANT-ARRIERE DE L'ANCRE, ET C'EST UNE CORRECTION MESUREE.
J'avais pris la direction ancre -> racine du sein comme « la
protrusion ». La course A l'a refutee : sous un TANGAGE de 90 deg,
ce pretendu +Z ne recevait que 0.565 de la gravite sur chestL et
-0.941 sur chestR — deux reperes qui ne sont pas l'image l'un de
l'autre, donc `supine` et `prone` echanges d'un sein a l'autre.
La raison est geometrique : ancre -> racine est domine par le
decalage LATERAL, pas par la protrusion.
Ce que la course B a etabli, en publiant la gravite sur les trois
lignes de l'ancre : tangage 90 deg -> 0.980 sur la ligne 0 ;
roulis 90 deg -> 0.993 sur la ligne 2. La ligne 0 EST l'avant-
arriere, la ligne 2 EST le lateral — donc `*phys-axa*` et
`*phys-axl*` sont bien nommes, et l'anisotropie de §29 est posee
sur les bons axes (je m'attendais a l'inverse ; la mesure tranche).
En espace ANCRE la ligne `axa` est le vecteur unitaire de cet
indice — les lignes de `am` SONT la base de cet espace.
```

## NOTE-68  (moteur, aux alentours de la ligne 3667)

```
LE SIGNE : `+ligne[axa]`, ET IL EST MESURE, PAS SUPPOSE.
Course B, gravite publiee sur les trois lignes de l'ancre :
a TANGAGE +90 deg (elle se penche en avant, donc le bas du
monde devient l'avant du corps) la gravite arrive a +0.980
sur la ligne 0. `+ligne[axa]` EST donc l'avant.
J'avais d'abord fixe ce signe par la direction ancre ->
racine du sein : la course C l'a REFUTE — cette direction
est dominee par le decalage lateral, sa composante avant est
residuelle, et son signe differait d'un sein a l'autre.
Resultat : `prone` sur un sein et `supine` sur l'autre pour
la MEME inclinaison. Une heuristique geometrique ne remplace
pas une mesure, et la voila remplacee par elle.
VERIFICATION PERMANENTE, pas une note : `ROOM-ORI` publie
`gz` a chaque course. A tangage +90 il doit etre proche de
+1 sur LES DEUX seins ; un rig qui orienterait sa ligne 0
vers l'arriere se verrait immediatement.
```

## NOTE-69  (moteur, aux alentours de la ligne 3691)

```
(b) SPEC 10-13 — L'EQUILIBRE DE FORME, CONTINU EN LA DIRECTION DE LA
GRAVITE. Sa §13 l'exige mot pour mot : « supine, prone, upright and
lateral states SHALL NOT exist as unrelated hard-coded morph targets ;
the equilibrium state shall vary CONTINUOUSLY with the local gravity
direction ». Les cinq triplets sont donc les VALEURS AUX POLES et rien
d'autre ; entre deux poles c'est un melange, exact a chaque pole,
continu partout (les poids sont |gx|, |gy|, |gz|, dont la somme ne
s'annule jamais pour une direction unitaire).
  debout   (-Y)  1.000 1.000 1.000   §9  : la pose d'auteur EST l'equilibre 1 g
  supine   (-Z)  1.230 1.090 0.700   §10 : projection -30 %, largeur +23 %
  prone    (+Z)  0.900 0.910 1.230   §11 : longueur +23 %, largeur -10 %
  lateral  (±X)  0.800 1.118 1.118   §12 : aplatissement -20 %, compense
  inverse  (+Y)  0.900 1.230 0.910   NON SPECIFIEE : la loi de §11
                                     (tissu libre, il s'allonge selon g)
                                     portee sur +Y. Extrapolation
                                     DECLAREE, exigee par la continuite.
```

## NOTE-70  (moteur, aux alentours de la ligne 3779)

```
SPEC 37 : « soft displacement clamps should be preferred to
abrupt positional clamps ». C'ETAIT UN ECRETAGE DUR, et il
etait ecrit DANS L'ETAT juste en dessous : la salle mesurait
5 frames sur 90 collees a |s| = 0.0700000 EXACTEMENT, que
l'ajustement de zeta devait EXCLURE — d'ou son « DESACCORD —
prudence » sur les deux chaines. Un etat reecrit par une
borne n'est plus l'oscillateur dont sa 36 donne zeta.
`phys-softmin` (:1051) est deja la borne douce du moteur, et
sert deja l'apex (:3059) et la torsion (:3890) : IDENTITE
STRICTE sous kn = 0.84*cap, seul l'EXCES sature, asymptote
exacte a cap.
ET LE GENOU TOMBE OU LA SPEC LE VEUT, ce qui est la parade
au piege `saturation-per-frame-compounds` : kn vaut
0.84 * 0.07 = 0.0588, soit 5.88 %, AU-DESSUS du haut de la
bande normale de sa 36 (`SecondaryJiggleAmplitude = 0.02-0.05`).
La bande normale est donc traversee en identite — aucune perte
par frame ne peut y composer — et la saturation ne mord que
dans la plage « strong impulse 5-7 % » que la 36 nomme.
```

## NOTE-71  (moteur, aux alentours de la ligne 3825)

```
(e) SPEC 29 — LE DEGRE DE LIBERTE EN TORSION, `TorsionalCompliance 0.72`.
Le tissu porte un angle de roulis PROPRE autour de son axe racine->apex ;
l'ancre porte le sien ; le ressort les relie. Aucune derivee seconde de
l'animation n'entre ici — c'est la meme construction que le mode
principal (on integre l'ABSOLU et on relie a la reference portee par
l'ancre), donc l'inertie et le retard EMERGENT au lieu d'etre pilotes
par un a-coup. Raideur = 1/0.72 fois celle de la verticale, exactement
comme `*phys-axs*` porte 1/0.90 et 1/0.82.
L'AXE DE TORSION EST L'AXE DE REPOS, PAS L'AXE SIMULE — et c'est une
correction, pas un choix. Mesure de la course A : la torsion montait a
25 a 76 degres, ce qui n'est pas une torsion de chair mais un artefact
de repere. Le roulis se mesure comme l'angle d'un vecteur de reference
AUTOUR de l'axe ; si l'axe lui-meme balance, sa propre rotation entre
dans la mesure (holonomie) et s'ACCUMULE frame apres frame. L'axe de
repos, lui, ne bouge qu'avec l'ancre : c'est exactement ce qu'on veut
mesurer, et rien d'autre.
```

## NOTE-72  (moteur, aux alentours de la ligne 3843)

```
LE ROULIS DE L'ANCRE, PAR DECOMPOSITION SWING/TWIST — ET C'EST LA
TROISIEME VERSION, CHACUNE CORRIGEE PAR UNE MESURE.
  v1 : angle d'un vecteur de reference autour de l'axe SIMULE.
       Course A : 25 a 76 deg de torsion. L'axe balancait, sa
       propre rotation entrait dans la mesure.
  v2 : le meme angle autour de l'axe de REPOS. Course C : la
       torsion sature son plafond sur les CINQ pilotages, y compris
       `updown`, une translation PURE ou le roulis vrai est nul.
       Un tangage du buste, pourtant orthogonal a l'axe, produisait
       encore un increment — c'est l'holonomie, et elle s'ACCUMULE.
  v3, ici : on ne mesure plus un angle projete, on extrait la part
       AXIALE de la rotation incrementale de l'ancre.
       `R = am(t-1)^T . am(t)` est cette rotation, exprimee dans le
       repere de l'ancre ; sa part antisymetrique est le vecteur de
       rotation, et `omega . u` en est la composante de TORSION.
       Une rotation orthogonale a `u` y rend exactement zero, ce
       qu'aucune projection de vecteur ne peut garantir.
```

## NOTE-73  (moteur, aux alentours de la ligne 279)

```
QUEL AXE DE L'ANCRE EST QUOI — classe UNE FOIS par chaine, a sa premiere frame utile, et JAMAIS
suppose depuis un nom d'os ni depuis un ordre d'axes :
  vertical = l'axe local de l'ancre le plus aligne avec la GRAVITE vue de l'ancre (`gl`, deja
             calculee pour §3) — c'est la definition meme de « vertical » dans sa §24, et elle
             ne suppose rien de l'orientation du modele ;
  lateral  = parmi les deux restants, celui que le SEGMENT INTER-SEINS designe — voir la note de
             `*phys-axsep*`. CETTE LIGNE A ETE CORRIGEE LE 2026-08-14 (cycle 10) : elle disait
             « AP = le plus aligne avec la direction ancre -> joint de l'organe », ce qui posait
             le role AP sur la ligne 0 de `chest`, mesuree a (+1,0,0) — le lateral du personnage.
             §29 et §24 travaillaient donc sur deux axes intervertis ;
  AP       = le troisieme, celui qui reste.
On stocke l'INDEX DE LIGNE (0/1/2) de la matrice de l'ancre ; le solveur relit les axes sur la
matrice COURANTE, donc le triedre tourne avec le torse sans jamais etre reclasse.
```

## NOTE-74  (moteur, aux alentours de la ligne 307)

```
============================================================================================
CE QUI NOMME LES AXES, ET POURQUOI CE N'EST PLUS UNE HEURISTIQUE (cycle 10).

La regle precedente disait : « AP = celle des deux lignes restantes sur laquelle l'OS se
projette le plus ». Rien d'anatomique n'entrait dans ce choix, et il etait FAUX : mesure sur le
rig, `chest` a pour ligne 0 (+1,0,0) — le lateral gauche-droite du personnage — et c'est
precisement la ligne que cette regle appelait `ap`. Consequence : §29 posait la compliance 0.90
(avant-arriere) sur le LATERAL et 0.82 (lateral) sur l'AVANT-ARRIERE, et §24 comparait ses
2.50 / 2.65 Hz aux mauvais axes. Le mecanisme etait arme, la mesure etait propre, et les deux
sections etaient fausses sans que rien ne puisse le signaler : une mesure par axe qui ne publie
que des VALEURS ne peut pas attraper une permutation de ses propres axes.

LA NOUVELLE REGLE REPOSE SUR UN INVARIANT QUE L'ETIQUETAGE NE PEUT PAS INFLUENCER : les deux
seins sont separes GAUCHE-DROITE. `lBoob` et `rBoob` partagent le meme parent (`chest`), donc
la difference de leurs positions EST le segment inter-seins, et il est lateral par definition
anatomique. La ligne sur laquelle il tombe est le LATERAL ; l'autre est l'avant-arriere.
Mesure du rig : (+712.31, +0.01, -0.00) u = 17.4 cm, 100 % sur la ligne 0.

ET LE RESULTAT EST PUBLIE, pas suppose : `*phys-axsep*` porte les deux projections que la
decision a comparees et `*phys-axsrc*` dit LAQUELLE des deux regles a tranche. La salle en fait
`PHYSAXNAME`, donc l'affectation se lit dans la trace d'une course — un commentaire ne prouve
rien (regle 0), et c'est exactement ce qui manquait pour voir l'interversion.
```

## NOTE-75  (moteur, aux alentours de la ligne 331)

```
============================================================================================
SPEC 8 / 10-13 / 29-torsion / 33-34 / 36 — LE CANAL DE DEFORMATION, LA TORSION, LA RESTITUTION.
Ajoutes le 2026-08-14 (cycle 7), dans l'ordre que sa directive de 11:50 fixe au point 4.

POURQUOI LE DEGRE DE LIBERTE EN TORSION EST AJOUTE ICI ET PAS PAR UN OS :
une torsion est une rotation PROPRE, et une chaine de particules PONCTUELLES n'en porte aucune,
QUEL QUE SOIT son nombre d'os. Ajouter un joint distal ne la rend donc pas disponible — c'est
pourquoi le degre de liberte manquant est ajoute la ou il manque, dans le solveur.
CORRECTION DU 2026-08-17 : ce paragraphe portait aussi l'argument « `sat` n'est armee qu'a UN
maillon (garde `(= n 1)`), donc injecter un os DESARMERAIT deux sections TENUES ». C'etait vrai
du code d'alors, et ce n'etait pas une raison de ne pas injecter : les deux gardes ont ete
RETIREES (`sat` ~:2644, mur d'apex ~:3108), la famille A suffisant a selectionner chestL/chestR.

AUCUN DE CES TROIS ETATS N'EST UN SUPPRESSEUR : chacun vaut ZERO au repos debout (echelle
identite, torsion nulle, mode secondaire nul), donc SPEC 9 — le retour EXACT a la pose
d'auteur, tenue au cycle 6 — est preservee par construction et non par reglage.
```

## NOTE-76  (moteur, aux alentours de la ligne 361)

```
§23 — « the solver should then derive local deformation from COM displacement, angular lag,
root constraints, VOLUME CONSERVATION and LOCAL COLLISION PRESSURE ». Les quatre premiers sont
livres (etirement dynamique, torsion, ancrage a la racine + poids gradues, determinant a 1) ;
le cinquieme est ce couple de constantes. La pression de contact APLATIT le tissu le long de la
normale et le redistribue sur les deux perpendiculaires — sa §34 : « collision energy should
primarily become DEFORMATION, redistribution and damping ». Le plafond est celui de sa §12,
l'aplatissement lateral qu'elle chiffre a 15-25 % quand tout le poids porte sur un sein.
LE GAIN, CALE SUR SA §12 ET SUR RIEN D'AUTRE. Mesure de la course F, qui publie l'aplatissement
AVANT plafond : a 1.00 les trois pilotages forts rendaient 40 a 56 % brut pour un plafond a 25 %,
donc un limiteur sature — la meme signature que le mode secondaire au premier essai, et la meme
correction. A 0.45 les memes fenetres rendent ~5 % sur les contacts doux (updown, tilt) et 18 a
25 % sur les forts : c'est exactement la bande que sa §12 chiffre pour un appui de tout le poids
(« gravity-side lateral flattening -15 a -25 %, nominal -20 % »).
```

## NOTE-77  (moteur, aux alentours de la ligne 2502)

```
LA DIRECTION MONDE DE CHACUNE DES TROIS LIGNES DU TRIEDRE, normalisee.
POURQUOI ELLE EXISTE, ET C'EST UNE MESURE QUI L'EXIGE : la salle a
excite les trois axes MONDE (Y, Z, X) et a mesure la part de reponse
tombant sur chaque projection du triedre. Une impulsion MONDE-Y ne met
que 21.5 % (chestL) a 25.7 % (chestR) de sa reponse sur l'axe VERTICAL
du solveur ; cinq des six fenetres sont dominees par l'axe AP. Le
repere du sujet et le triedre de l'ancre ne sont PAS alignes — donc
aucune excitation en axes monde n'isole un mode propre, et SPEC 24
reste indecidable tant qu'on pousse dans le mauvais repere.
NATURE : un vecteur unitaire. REPERE : monde. Indexation
`sc*9 + ligne*3 + composante`, la LIGNE etant celle de `am`, pas le
role : c'est `phys-axis-world` qui fait la traduction role -> ligne.
```

## NOTE-78  (moteur, aux alentours de la ligne 3543)

```
---- 5bis. SPEC 8 / 10-13 / 29-torsion / 36 — L'ETAT DE FORME ET DE TORSION.
Sa §23 : « the solver should then DERIVE LOCAL DEFORMATION from COM
displacement, angular lag, root constraints, volume conservation and local
collision pressure ». Jusqu'a ce cycle le moteur n'ecrivait qu'une POSITION
et une rotation : il n'existait aucun canal par lequel une deformation ait pu
sortir, donc §8, §10, §11, §12, §13 et §36 ne pouvaient etre ni implementees
ni mesurees. Ce bloc calcule l'etat ; l'ecriture est 20 lignes plus bas.

NATURE de ce qui est calcule ici : un triplet d'ECHELLES sans dimension,
rapport a la forme d'auteur. REPERE : le triedre de sa §7, releve une fois a
la pose debout d'auteur. LECTURE HORS DEFAUT : 1.000 / 1.000 / 1.000 debout —
donc §9, tenue au cycle 6, ne peut pas etre payee par ce bloc.
```

## NOTE-73 — SPEC 9 : la cible de repos du ressort est-elle la pose d'auteur ?

Le cycle 29 a mesure que `comex` (l'excursion du centre de chair, mesuree **contre la pose
d'auteur de la meme frame**) vaut 1.04 / 1.07 B0 en moyenne sur la fenetre de LIGNE DE BASE, ou la
salle ne pousse rien, pour un plafond dur de 0.40 B0 (sa §22), et en a conclu a une SATURATION.

Le cycle 30 a repris la meme trace a exposition egale : sur cette meme fenetre le stimulus
reellement recu (`PHYSACC`) varie d'un facteur **274** (0.32 a 87.66) et `comex` est PLAT —
r = +0.005 (chestL) et +0.184 (chestR) — le tiers le plus CALME rendant meme un `comex` plus grand
(1.1269) que le tiers le plus agite (1.0738). Le minimum sur 186 fenetres vaut 0.6762 B0 : la
grandeur n'approche jamais zero.

Une grandeur grande, constante et independante de toutes ses entrees n'est pas une reponse.

Or le ressort de materiau ne vise pas la pose d'auteur. Sa cible est, textuellement :

    tg = attache + R_ancre . u_capture . bl

ou `u_capture` est relevee UNE SEULE FOIS (`*phys-ucap*`) a la premiere frame utile et gelee pour
toute la vie de l'acteur (remise a zero uniquement a l'acquisition d'un slot). C'est deliberé, et
c'est sa §2/§9 : le repos doit etre la pose du modele debout, jamais ce que l'animation dessine.
Mais si la pose d'AUTEUR du joint s'ecarte ensuite de cette cible portee par l'ancre, l'ecart entre
la pose ecrite et la pose d'auteur est non nul **meme avec un solveur immobile et converge**, et
aucune raideur, aucun limiteur, aucun contact ne peut le faire baisser.

Les deux emplacements 24/26 (maximums de fenetre) et 25/27 (somme et compte) separent les deux
parts, et les deux se calculent au MEME endroit du solveur, avec la MEME attache et la MEME
longueur d'os relevee sur la pose animee — leur difference est donc purement angulaire,
`2.bl.sin(dtheta/2)`.

Ce sont des EMETTEURS : ils ne produisent aucune force et ne deplacent aucun os.
`perr` porte un retard d'UNE frame (`tg` se calcule avant l'integration, `p` y est donc l'etat
laisse par la frame precedente). Au repos c'est sans effet ; c'est dit, pas cache.

## NOTE-74 — SPEC 24 contre SPEC 31 : le gradient racine→pointe ne vit plus dans la frequence

Le solveur calcule la pulsation de la chaine `w = 2*pi*stiffness/sqrt(mass)` puis, jusqu'au
2026-08-19, GRADUAIT la raideur par maillon pour honorer sa §31 :

    k2l = k2 * (1 - r^2) / gmean     r = (l - rlk + 0.5)/nfr    gmean = 1 - (0.5/nfr)^2

Or dans cette formulation `w_l = w * sqrt(k2l/k2)` : **graduer la raideur EST graduer la frequence
propre.** Sur la chaine livree (`nfr = 2`, `rlk = 0`) le rapport vaut 1.0000 au maillon racine et
0.4667 au maillon distal, donc :

| chaine | stiffness | mass | f_chaine | f maillon 0 | f maillon 1 (AVANT) |
|---|---|---|---|---|---|
| chestL | 2.7696 | 1.4500 | 2.3000 | 2.3000 Hz | **1.5712 Hz** |
| chestR | 2.9081 | 1.4800 | 2.3904 | 2.3904 Hz | **1.6330 Hz** |

Sa §24 donne 2.30 / 2.50 / 2.65 Hz, bande la plus basse `[2.10, 2.50]`. Le maillon distal tournait
donc **25 % sous le plancher, sur les trois axes** — et c'est lui qui pilote 43.5 % / 37.5 % de la
chair depuis le repesage du cycle 24. Personne ne l'avait vu parce que le fit de ring-down est
publie PAR CHAINE : il rend le mode dominant, celui du maillon le plus raide.

**Pourquoi la graduation part et pas la §24.** Sa §31 ecrit « a USEFUL deformation weighting is
`w(r) = r^1.6…2.0` » — une suggestion de ponderation ; sa §24 donne trois bandes chiffrees et sa §28
les relie a `k = m(2*pi*f)^2`. Entre une suggestion et une bande chiffree, la bande gagne (arbitrage
de l'owner du 2026-08-14 01:00). Et le gradient de §31 n'est PAS perdu : il est deja porte, et
mesure, par la PEAU — profil d'ancrage de §30 decroissant de 0.95 a 0, exposant 1.63, os distal
majoritaire sur 43.5 % / 37.5 % du nuage. Le porter une seconde fois dans la frequence, c'etait le
compter deux fois, et la deuxieme fois cassait §24.

**Le maillon RACINE est inchange au bit pres, par construction** : pour tout `nfr`,
`r(rlk) = 0.5/nfr` et `gmean = 1 - (0.5/nfr)^2`, donc `(1 - r^2)/gmean = 1.0000` exactement. La
raison d'etre de la normalisation introduite le 2026-08-17 (NOTE-38 : empecher que passer de 1 a 2
maillons fasse sortir la racine de sa bande a 2.709 Hz) est donc integralement preservee — `k2l = k2`
rend la meme valeur sur ce maillon-la.

`rate = dmp * sqrt(k2l/k2)` redevient `dmp` : `zeta` est conserve, §25 n'est pas touchee.

`nfr` et `gmean` n'avaient plus d'autre lecteur et sont retires avec la graduation — une liaison
morte et son commentaire perime sont exactement la classe de defaut que ce dossier paie depuis des
cycles.

---

## NOTE-79 — LE CANAL RADIAL DE SA §23 ETAIT CALCULE PAR MAILLON ET RANGE PAR CHAINE

> **CORRIGEE : SA PHRASE SUR `*phys-rr*` EST PERIMEE DEPUIS LE CYCLE 32.** Elle ecrit que `*phys-rr*` « reste le seul que le solveur lise ». C'est faux depuis que le tenseur de deformation lit `*phys-rrl*` a `:3749` sur l'index de POINTE (`tl`). `*phys-rr*` ne garde plus que la valeur du maillon RACINE, et **NOTE-80** fait foi sur ce point.

**Le defaut, et il est d'indexation, pas de physique.** Le calcul d'elongation radiale tourne DANS
la boucle par maillon du solveur — `(dotimes (l n)` ouvre a `:2550` et lie `scl` a `:2551`, et le
bloc l'utilise (`(set! (-> *phys-qx* scl) ...)`) — mais il ecrivait son resultat dans `*phys-rr*`,
un tableau dimensionne `PHYS-SC`, **c'est-a-dire par CHAINE**. Chaque tour de boucle ecrasait donc
le precedent : le tableau ne gardait que le DERNIER maillon execute.

**Ce que ca produisait dans la trace, et pourquoi personne ne le voyait.** `phys-room.gc` imprime
`PHYSRINGCX` DANS une boucle par maillon et met un `l=` sur chaque ligne. Les deux lignes portaient
donc des `l=` differents et la MEME valeur. Mesure du cycle 31, sur les 6 combinaisons
(chaine x axe), 150 frames chacune : **`max|l0 - l1| = 0`, exactement**. Un `l=` decoratif est pire
qu'un champ absent — il donne l'apparence d'une mesure resolue par maillon sans en etre une, et
c'est la classe de defaut que ce dossier paie depuis des cycles.

**Pourquoi ca comptait precisement ICI.** Le tableau de salle designe lui-meme `PHYSRINGCX` comme la
SEULE source valide du verdict §24 vertical (`physics_room_table.py:4026-4039`) : les deux autres
tags, `PHYSRINGA` et `PHYSRINGBX`, lisent la position du JOINT, qui vit sur une sphere, donc leur
composante radiale est nulle par construction. Or sa §24 appelle le mode vertical « intentionally
the SLOWEST » et il est a 84.5 % radial. **L'axe que sa spec distingue le plus explicitement n'avait
donc aucune resolution par maillon** — et le maillon distal pilote 43.5 % / 37.5 % de la chair.

**Le correctif, et ce qu'il ne touche PAS.** On ajoute `*phys-rrl*` (`PHYS-SCL`), ecrit avec le meme
`drr` a cote de `*phys-rr*`, et un accesseur `phys-chain-radial-link`. `*phys-rr*` **garde
exactement la meme valeur et reste le seul que le solveur lise** (`:3728`, le terme `rdr` de la
deformation dynamique) : le comportement livre est inchange au bit pres, et c'est verifiable —
aucune donnee livree n'a bouge, et les grandeurs de la course doivent se reproduire.
C'est un ajout d'INSTRUMENT. Un instrument ne peut pas deplacer un joint, et celui-ci ne le peut
structurellement pas : rien ne le lit sauf l'emetteur de trace.

**La regle generale a en retirer.** Quand un calcul vit dans une boucle par maillon, verifier que sa
DESTINATION est dimensionnee par maillon. L'inverse — calcul par maillon, rangement par chaine — ne
plante pas, ne previent pas, et rend une serie parfaitement plausible : celle du dernier tour.
Le controle qui l'attrape tient en une ligne et il est desormais dans la sonde : **deux series qui
portent des index differents doivent DIFFERER**. Si `max|l0 - l1| = 0` sur toute une course, le
champ d'index est decoratif.

## NOTE-80 — LE TROISIEME DEGRE DE LIBERTE DE SA §23 N'EXISTAIT QUE SUR UN MAILLON

Sa §23 dit qu'« un seul ressort a l'apex est INSUFFISANT » : le tissu a besoin d'un degre de liberte
RADIAL, celui que la contrainte de longueur confisque a une chaine d'os. Le moteur le porte par un
POINT LIBRE — une particule qui s'integre avec la meme cible, la meme raideur anisotrope, la meme
trainee et le meme pilotage que l'apex, mais que rien ne projette. Sa composante le long de l'os,
moins la longueur d'os, EST l'elongation radiale (`*phys-rr*`), et c'est le seul canal par lequel
l'axe VERTICAL de sa §24 peut se mesurer : l'os de poitrine est vertical a 84.5 %, donc la
composante verticale de la deviation POSITIONNELLE est nulle par construction.

**CE QUI N'ALLAIT PAS.** Les six tableaux d'etat de ce point libre (`*phys-cp{x,y,z}*`,
`*phys-cq{x,y,z}*`) et son drapeau d'amorcage `*phys-rok*` etaient dimensionnes `PHYS-SC` — PAR
CHAINE. Le bloc d'integration etait donc garde par `(= l rlk)` : un seul point libre par chaine,
celui du maillon racine. Depuis l'injection du second os (cycle 30), le maillon DISTAL pilote 43.5 %
(`lBooc`) et 37.5 % (`rBooc`) des sommets de la chair — et il n'avait aucun troisieme degre de
liberte. Mesure du cycle 31 : sa serie radiale etait identiquement nulle, 0 valeur non nulle sur
150 echantillons, sur les SIX canaux (2 chaines x 3 axes).

Ce n'etait donc pas un emetteur qui manquait, c'etait le MECANISME. Un emetteur ne peut pas publier
une grandeur que le solveur ne calcule pas — et c'est pour ca que les 4 canaux verticaux de sa §24
etaient classes NON MESURABLES au tableau de conformite du cycle 31.

**LE CORRECTIF.** Les sept tableaux passent en `PHYS-SCL`, la garde devient `(>= l rlk)`, et
l'amorcage se fait UNE FOIS PAR MAILLON sur l'etat de SON apex — ce qui preserve §9 par
construction : a la premiere frame l'elongation vaut exactement 0 sur chaque maillon, pas seulement
sur la racine.

**ET LE CONSOMMATEUR SUIT, SINON LE DEGRE DE LIBERTE SERAIT DECORATIF.** Le seul terme du solveur
qui lit ce canal est `rdr`, dans le tenseur d'etirement dynamique de sa §38. Il lisait `*phys-rr*`
(par chaine) pour TOUS les maillons : le distal se deformait donc avec l'elongation de la racine.
Il lit maintenant `*phys-rrl*` (par maillon). C'est ce qui fait de ce changement une modification de
PHYSIQUE et pas d'instrument, et c'est ce qui evite le piege `declared-but-never-selected` du
registre : un mecanisme arme dont aucun consommateur ne lit la sortie n'est pas arme.

**CE QUI RESTE PAR CHAINE, DELIBEREMENT.** `*phys-rr*` garde la valeur du maillon RACINE et rien
d'autre : `phys-chain-radial` la publie depuis le cycle 10, et laisser le distal l'ecraser aurait
change en silence ce que designe un nombre deja publie — exactement le defaut que NOTE-79 vient de
corriger, retourne. En revanche les trois AGREGATS (`*phys-rrr*` avant borne, `*phys-rrm*` maximum
de fenetre, `*phys-rrsat*` frames ou la borne de §22 a mordu) couvrent desormais TOUTE la chaine :
un maximum de §22 qui ignorerait un maillon ne bornerait pas le tissu, il bornerait un tiers de lui.
Ce changement de PORTEE est ecrit dans la docstring de l'accesseur et dans le rapport du cycle 32 ;
il n'a pas a etre devine en comparant deux tableaux.

## NOTE-81 — LA BORNE DE §22 SUR LE CANAL RADIAL, ET « QUEL MAILLON SATURE ? »

### CORRECTION DU 2026-08-19 (cycle 40) — CE N'ETAIT PAS LA BONNE LIGNE DE SPEC, NI LE BON METRE

Tout ce qui suit cette section reste vrai de la borne TELLE QU'ELLE ETAIT. Elle a change, et voici
la mesure qui l'a commandee.

`dr0` est une ELONGATION DE TISSU. Sa §22 lui consacre sa propre ligne — « Local tissue elongation:
common 5-15 %, large 15-21 %, exceptional 21-25 % ; Absolute stretch clamp: 25 % » — et cette ligne
est SANS UNITE. Un rapport de deformation a pour denominateur la longueur de repos LOCALE. La borne
prenait la ligne « Breast COM <= 40 % B0 », qui est un DEPLACEMENT, et le denominateur `b0e`, qui
est l'organe entier. Deux erreurs sur la meme expression.

Ce que le plafond de `0.40*b0e` = 240.8 u vaut EN DEFORMATION REELLE, longueurs lues dans la course
(`PHYSBONE`) :

    l=0  LEVIER chest->lBoob   1040.5 u   240.8/1040.5 =   23.1 %      (aucune chair dessus)
    l=1  CHAIR  lBoob->lBooc    140.4 u   240.8/ 140.4 =  **171.5 %**  pour une clef de 25 %

Et ce que le canal LIVRAIT, mesure sur les 744 fenetres de la course du cycle 38 :
`rrm` moyen 179.7 u sur un segment de 140.4 u = **128.0 %** de deformation locale (121.2 % a
droite), 92.5 % / 90.3 % des fenetres au-dessus du clamp de 25 %, maximum demande 294 % / 325 %.

D'ou `rcap = fmin(0.40*b0e, PHYS-DYN-MAX*bl)`. Le `fmin` garantit que la borne ne devient jamais
plus large qu'avant : sur le LEVIER `0.25*1040.5 = 260.1 u > 240.8`, donc le levier garde sa borne
au bit pres ; sur la CHAIR `0.25*140.4 = 35.1 u`, et c'est la que la §22 etait violee x5.1.

**CE QUE CETTE BORNE NE PEUT PAS FAIRE, ET IL FAUT LE LIRE ICI AVANT DE LA RE-REGLER.** Le segment
de chair simule couvre `r` de 0.480 a 0.674 sur les 0..1 de sa §31, soit **19.4 % de l'organe**.
Pour livrer l'elongation d'organe que sa §22 autorise (25 % de 734 u = 183.6 u) a une deformation
locale <= 25 %, il faudrait un segment de 734 u. Il en fait 140. **Facteur manquant x5.23 / x5.32.**
Aucune valeur de `rcap` ne tient les deux lignes a la fois : ce choix-ci tient la deformation locale
(23-25 %) et fait tomber l'elongation d'organe a 4.7-4.8 %, sous le plancher 5 % de sa bande
courante. C'est un defaut de GEOMETRIE, et le chantier suivant est le segment, pas la borne.


**LA BORNE ELLE-MEME.** Sa §22 dit « Breast COM: normal <= 35 % B0, hard transient <= 40 % B0 »
(§38 : `NormalMaxCOMDisplacement 0.35`, `HardMaxCOMDisplacement 0.40`). Le canal radial est borne
par `phys-softmin` avec le cap TRANSITOIRE, exactement comme la borne d'apex de la torsion : le
genou de `phys-softmin` vaut 0.84 x cap = 0.336 B0, ce qui tombe sur la borne NORMALE a 4 % pres —
et 0.84 n'est pas un chiffre choisi, c'est le rapport que sa spec donne deja a l'apex
(0.42 / 0.50 = 0.84 EXACTEMENT). L'ecart de 4 % est ECRIT plutot que rattrape en deplacant le
genou : on ne regle pas l'instrument pour qu'il tombe juste.

`phys-softmin` est appelee UNE SEULE FOIS et sur la valeur PUBLIEE, jamais sur l'etat : elle n'est
pas idempotente au-dessus de son genou (sa propre docstring l'ecrit), donc la rappeler chaque frame
sur `*phys-cp**` ferait fondre l'oscillateur frame apres frame. C'est exactement ce que fait deja
la torsion : `twn` brut conserve dans l'etat, `rel` borne publie.

**LE CONTROLE k=5** (`*phys-rr-off*`) desarme la borne : `rcap` part a l'infini et `phys-softmin`
redevient l'identite (sa branche `(<= v kn)`), donc le canal radial passe ENTIER. Il vaut 0 partout
ailleurs, donc le comportement livre est inchange au bit pres hors de la passe de mesure.

**ET LE PROBLEME QUE LE CYCLE 32 A OUVERT.** Une fois le degre de liberte arme sur les DEUX maillons,
l'elongation que le solveur voudrait produire AVANT la borne atteint **1.42 B0 pour un plafond de
0.40** sur `accel` (0.43 quand le distal etait desarme), et le nombre de frames bornees passe de 5 a
23. Un canal colle a sa borne ne repond plus au stimulus : c'est la signature de saturation du
registre, et c'est une des formes du « pudding » que l'owner decrit.

Deux remedes sont candidats et ils ne se choisissent pas a l'intuition :
  (a) la borne de 0.40 B0 est celle du COM de la chair ENTIERE ; l'appliquer identiquement a chaque
      maillon la compte deux fois, et il faudrait une borne PAR MAILLON ;
  (b) la raideur radiale du distal est a re-deriver pour que l'excursion libre retombe sous la bande.
Au niveau de la CHAINE les deux predisent la meme chose. Au niveau du MAILLON, non.

**D'OU LES TROIS MIROIRS PAR MAILLON** `*phys-rrml*` / `*phys-rrrl*` / `*phys-rrsl*` : les memes
maximums de fenetre et le meme compte de saturation, resolus par maillon, **et lus par personne
d'autre qu'un `format`**. C'est le patron de NOTE-79, pour la meme raison : un agregat par chaine
qui cache une verite par maillon n'est pas une mesure, c'est une moyenne qui a l'air d'une mesure.
Ils sont publies par `PHYSRADL` (`phys-room.gc`) et lus par `ROOM-RAD-LINK`.

## NOTE-82 — LA DECOMPOSITION EXACTE DE `dr0` : L'OS OU LA CHAIR ?

Le cycle 33 etape 1 a etabli QUI sature — le maillon DISTAL, a x3.55 / x3.57 le plafond de §22 —
et il a REFUTE le remede « une borne par maillon ». Il n'a pas explique POURQUOI cet oscillateur
court 3.5x trop loin, et il a nomme un candidat sans le mesurer (« ce qui differe est leur
ATTACHE »).

`dr0`, la grandeur pre-borne que publie `rrr`, vaut :

    dr0 = dot(cp - a, m^) - bl        m = px(scl) - a ,  m^ = m/ml ,  ml = |m|

Comme `dot(m, m^) = ml` par construction, la decomposition suivante est une **identite**, pas un
modele :

    dr0 = ( ml - bl )  +  dot(cp - px, m^)
          \________/     \______________/
           (A) l'OS        (B) la CHAIR
          n'est pas sur    au-dela de la
          sa sphere        pointe de l'os

**(A) peut etre non nul, et ce n'est pas une supposition :** `phys-length-chain` est appelee a
`:3075` et `:3095`, c'est-a-dire APRES la fermeture de la boucle des maillons ou `dr0` est calcule.
Au moment de la mesure, la contrainte de longueur de la frame COURANTE n'a pas encore tourne. `ml`
peut donc differer de `bl`, et cette difference entre dans `dr0`, dans la borne de §22 qui le suit,
**et dans `*phys-rrl*` — l'etat que le tenseur de deformation LIT**. Si (A) domine, le tissu recoit
une elongation que le solveur ANNULE trois lignes plus loin.

Les deux termes sont releves **a la frame de l'argmax de `rrr`**, jamais comme deux maximums
independants : le maximum d'une somme n'est pas la somme des maximums, et deux agregats separes ne
se recomposeraient pas. `(B)` est calcule par son PROPRE produit scalaire et non par soustraction,
pour que `mlb + cdev = rrr` (au signe pres) soit un controle d'integrite qui passe par deux chemins
de calcul distincts et pas une tautologie.

Mesure seule : `*phys-rrol*` et `*phys-rrcl*` ne sont lus par aucun terme du solveur.

## NOTE-83 — SPEC 37 : LA MOITIE TRANSLATION DU REBASE, ET LA MESURE QUI JUGE SON SEUIL

Sa §37 : *« rebase on teleport / cutscene / discontinuity — artificial transforms must not generate
physical breast impulses. »*

**LA MOITIE ROTATION EXISTAIT DEPUIS LONGTEMPS, LA MOITIE TRANSLATION ETAIT ABSENTE.** Le moteur
protege le roulis accumule de l'ancre (`*phys-twa*`, la torsion de §29) contre une ROTATION brusque
(`:3701-3707`, « au-dela d'un demi-radian en une frame ce n'est plus une rotation du buste, c'est un
teleport ou une coupe »). Rien ne protegeait l'etat de POSITION — `*phys-px/py/pz*`,
`*phys-qx/qy/qz*` — ni celui du point libre de §23 contre une TRANSLATION brusque.

**MESURE QUI L'A ETABLI (cycle 33 etape 2), et elle sort d'un controle de fiabilite, pas d'une
recherche :** `perr` (|apex − cible de repos| / B0) par fenetre, dans la salle —

| fenetre | fenetres | max > 5 B0 | perr max |
|---|---|---|---|
| updown | 62 | 14 | 63.97 B0 |
| leftright | 62 | **0** | 0.94 B0 |
| accel | 62 | **0** | 1.12 B0 |
| jerk | 62 | **0** | 1.27 B0 |
| tilt | 62 | 2 | 5.08 B0 |
| SANS PILOTAGE | 62 | **62** | 53.54 B0 |

Et l'a-coup est reel dans la POSE ECRITE, pas seulement dans la reference : `PHYSBASE jump` vaut
**175.7 u (0.2918 B0)** et **188.7 u (0.3135 B0)** dans des fenetres ou la salle ne commande rien.

**LA FORME DU REBASE, ET C'EST POURQUOI C'EST LA BONNE.** On applique le MEME delta d'ancre a `p`,
`q`, `cp` et `cq` :

    p += d ; q += d   ->   (p - q) INCHANGE        -> aucune vitesse creee
    et p - anc INCHANGE                            -> aucune erreur de ressort creee

Une transformation artificielle ne produit donc, **par construction**, aucune impulsion. Ce n'est
pas un amortisseur, pas un clamp, pas un gel : rien n'est retire au mouvement, l'etat est simplement
transporte. C'est la difference entre un rebase et un suppresseur, et elle se verifie par le fait
que `p - q` est litteralement le meme nombre avant et apres.

**LE SEUIL : MON PREMIER CHOIX ETAIT FAUX, ET LA MESURE L'A DIT EN UNE COURSE.**

J'avais retenu `0.50 × b0e` (301 u), l'enveloppe DURE d'apex de sa §38, en ecrivant d'avance que le
risque etait qu'il morde un mouvement legitime. **Il l'a mordu :** 2308 frames rebasees sur les
fenetres `leftright`/`accel`/`jerk`, c'est-a-dire sur des pilotages COMMANDES — 20 % des frames de
`tilt`. A ce seuil le rebase est un SUPPRESSEUR, et le contrat l'interdit.

**LA DISTRIBUTION MESUREE DONNE LE BON SEUIL, ET ELLE MONTRE UN INTERVALLE VIDE :**

    |delta ancre| max par fenetre, unites de jeu
      leftright       354.4        \
      accel           519.7         |  PILOTAGES COMMANDES (legitimes)
      jerk            582.3         |  plus grand : 582.3
      tilt           2872.5        /   (min sur les 31 fenetres : 2747.0)
      ----------------------------------- INTERVALLE VIDE, facteur 2.27x
      ligne de base  6513.0 (min)  \  FRONTIERES DE FENETRE (artificielles)
      updown        37811.6         /  jusqu'a 37 811 u

Seuil retenu : **`7.00 × b0e` = 4214 u**, place DANS l'intervalle vide, a **1.47x** au-dessus du
plus grand deplacement legitime et **1.55x** au-dessous du plus petit deplacement artificiel.

**LA PROVENANCE DE `7.00` EST UNE MESURE, PAS SA SPEC, ET IL FAUT LE DIRE AINSI.** Aucune ligne de
`SPEC-breast-softbody.md` ne donne ce nombre : il vient de l'intervalle vide ci-dessus, releve sur
une course. Il se re-derive de la meme facon si la salle change de pilotages. Ce qui est GENERAL et
qui ne depend pas de la course, c'est la METHODE : mesurer la distribution des deux populations,
verifier qu'un intervalle vide les separe, et poser le seuil dedans avec ses deux marges publiees.
Un seuil pose sans cette distribution — comme celui de `0.5 rad` du rebase de ROTATION a `:3701`,
qui n'a jamais ete confronte a une mesure — est un nombre choisi, et il peut mordre sans qu'on le
sache.

**LE COMPTEUR ET LA DISTRIBUTION PARTENT DANS LA MEME COURSE, ET C'EST CE QUI A PERMIS DE TRANCHER
EN UN ESSAI :**

* `PHYSREBASE fired` = COMPTE de frames rebasees dans CETTE fenetre. Doit valoir **exactement 0** sur
  `leftright`, `accel` et `jerk`. Non nul = le seuil est mauvais, et il se re-derive sur la mesure.
* `PHYSREBASE amax` = MAXIMUM du deplacement d'ancre d'une frame a la suivante, unites de jeu. Il
  donne la DISTRIBUTION, donc il dit si un intervalle VIDE separe les translations legitimes des
  discontinuites — ou si les deux se recouvrent, auquel cas aucun seuil sur cette grandeur ne peut
  les separer et il faut le dire au lieu d'en choisir un.

Un limiteur sans compteur est interdit par le contrat ; celui-ci publie combien de fois il agit, a
cote de la grandeur qui permet de juger s'il a eu raison d'agir.


## NOTE-84 — LE POINT LIBRE DE SA §23 N'EST PROJETE PAR RIEN, ET C'EST CE QUE `rrtl`/`cddl` MESURENT

Deux choses vivaient dans le meme commentaire inline et sont ici.

**(a) La borne de §22 est appelee UNE SEULE FOIS, sur la valeur LIVREE, jamais sur l'ETAT.**
`phys-softmin` n'est pas idempotent au-dessus de son genou (sa propre docstring l'ecrit) : la
rappeler chaque frame sur `*phys-cp**` ferait fondre l'oscillateur frame apres frame. C'est
exactement ce que fait deja la torsion (`twn` brut conserve dans l'etat, `rel` borne publie).

**(b) `*phys-rr*` garde la valeur du MAILLON RACINE et rien d'autre** : `phys-chain-radial` la
publie depuis le cycle 10, et laisser le distal l'ecraser changerait en silence ce que designe un
nombre deja publie. Le distal vit dans `*phys-rrl*`. Les agregats (`rrr`, `rrm`, `*phys-rrsat*`)
portent, eux, TOUTE la chaine : un maximum de §22 qui ignorerait un maillon ne bornerait pas le
tissu.

**(c) ET LE CANAL NEUF DU CYCLE 34.** Le cycle 33 etape 2 a etabli que l'elongation qui sature sa
§22 est celle de la CHAIR (`cdev = dot(cp - px, m^)`, 94 % et 97 %) et non celle de l'os. Mais
`cdev` melange encore DEUX choses, et c'est la meme faute d'agregat un cran plus bas :

    cdev = dot(cp - tg, m^)  +  dot(tg - px, m^)
           \______________/     \______________/
            (C) le point libre    (D) la contrainte
            n'a pas rejoint SA    ecarte l'OS de SA
            cible                 cible

`rrtl` = (C)/B0 (signee, sur `m^`) et `cddl` = |cp - tg|/B0 (la norme du meme ecart), toutes deux
relevees A LA FRAME DE L'ARGMAX de `rrr` — jamais deux maximums independants, parce que
`max(a+b) != max(a) + max(b)` et que deux agregats separes ne se recomposeraient pas. (D) se deduit
par soustraction : aucun troisieme canal.

**POURQUOI CETTE SEPARATION EST LA BONNE QUESTION.** Recensement du symbole sur le fichier entier :
`*phys-cpx*` n'est ecrit qu'a l'amorcage (`cp := px`), au rebase de §37 et a la publication. Ni
`phys-length-chain` ni `phys-collide-chain` ne le touchent. **L'OS obeit a sa sphere de rayon `bl`
et aux 54 volumes ; LA CHAIR n'obeit a rien.**

**LA BORNE ARITHMETIQUE QUI REND (D) REFUTABLE SUR PAPIER.** `tg` est construit comme `a + bl*u^`
avec `u^` UNITAIRE, donc `|tg - a| = bl` EXACTEMENT — par construction, pas par reglage. Avec
`|px - a| = ml` par definition :

    (D) = bl*cos(theta) - ml     =>     |D| <= bl + ml     =>     |D|/B0 <= 2*bl/B0 + rrol

Maillon distal : `bl` = 140 u, B0 = 602 u, donc |D| <= 0.47 B0 environ, quand `cdev` mesure
-1.3354 et -1.4790 B0. (D) ne peut pas, a lui seul, produire le nombre.

**CONTROLE D'INTEGRITE NON TAUTOLOGIQUE** : `|rrtl| <= cddl`. Les deux membres sont calcules par
des chemins differents — un produit scalaire pour l'un, une racine de somme de carres pour l'autre.
S'il casse, l'instrument est faux et aucune conclusion ne se publie.

## NOTE-85  (moteur : la mesure de `comex`, SPEC 22 — prose deplacee telle quelle du moteur)

---- SPEC 22 : L'EXCURSION DU **CENTRE DE CHAIR**, EN B0 ---------
Sa §22 borne DEUX grandeurs et les nomme : « Breast COM: normal
<= 35 % B0, hard transient <= 40 % B0 » et « Distal/apex
displacement: normal <= 42 %, exceptional <= 50 % ». Le moteur
borne aujourd'hui le JOINT (borne d'apex, :3115) et le CANAL
RADIAL (borne de COM, :2960) — deux grandeurs dont AUCUNE n'est
le centre de masse de la chair. Il n'existait donc, jusqu'ici,
aucune mesure de la grandeur que la borne de COM designe.
CE QUI EST PRIS ICI : le centre du volume que le generateur a
MESURE sur le mesh (« measured centroid of the geometry this
joint owns »), transporte par la matrice d'AUTEUR (`pre`, copiee
en tete de cette boucle) puis par la matrice ECRITE (`bm`, qui
porte deja la rotation ET la deformation de §8/§10-13). La
difference est donc le deplacement de la chair, deformation
COMPRISE — c'est la lecon du cycle 27 (un COM bati sur les seuls
joints est la moitie de la grandeur).
NATURE : une LONGUEUR rapportee a B0, maximum sur la fenetre.
REPERE : le monde, a la frame ecrite, contre la pose d'AUTEUR de
la meme frame. LIGNE DE BASE : 0.0000 a la pose d'auteur.

## NOTE-86  (moteur : la projection de la force sur le triedre, SPEC 24/29 — prose deplacee telle quelle)

SPEC 24 / SPEC 29 — LA FORCE EST PROJETEE SUR LE
TRIEDRE ET CHAQUE AXE PORTE SA PROPRE RAIDEUR. C'est
le SEUL mecanisme des deux sections : trois raideurs,
donc trois frequences propres et trois mobilites, et
rien d'autre n'a ete ajoute pour les tenir.
`mu` (la saturation de SPEC 21) reste calculee sur la
NORME de l'ecart, donc SPEC 21/22 gardent exactement
la borne d'excursion qu'ils avaient : l'anisotropie
redistribue la raideur, elle ne touche pas au mur.
`axo = 0` -> les trois facteurs valent 1.0 et cette
branche rend `k2s*mu*e`, BIT POUR BIT l'ancienne.

## NOTE-87 — SA §21 BORNE LE DEPLACEMENT, ET LE MOTEUR EN AVAIT FAIT UN MULTIPLICATEUR DE FORCE

**LE FAIT ARITHMETIQUE, ET IL NE DEPEND D'AUCUNE MESURE.** La saturation de §21 sur le point libre
s'ecrivait `xr = min(0.99, (cdd - ckn)/ccp)` puis `|f| = k2s * (ckn + ccp * xr/(1-xr))`. Le
`min 0.99` GELE le numerateur des que `cdd >= ckn + 0.99*ccp = 240.5 u`, c'est-a-dire **exactement
a la bande de 0.40 B0 de sa §22**. Au-dela :

    |f| = k2s * (ckn + 99*ccp) = 0.0036256 * 3190.6 = 11.57 u/sous-pas = 46.3 u/frame, CONSTANT

L'ecart mesure au cycle 34 etape 1 vaut 1015 a 1118 u. Le mur tirait donc a 4.4 % de l'erreur par
frame, et il aurait tire la MEME chose si l'erreur avait valu 10 000 u. **Une force constante ne
borne pas un deplacement.** Le garde-fou `cmu <= 1/k2s` n'intervenait jamais : il ne mord que sous
`cdd < 11.6 u`.

Et le `min 0.99` n'etait pas un mauvais choix de constante : la forme `x/(1-x)` n'est DEFINIE que
pour `x < 1` et change de signe au-dela. Le geler etait la seule facon de s'en servir.

**CE QUE SA SPEC ECRIT, ET QUI EST DEJA AU DEPOT.** §21 : `D = D_max * tanh(|D|/D_max)` — une
saturation du DEPLACEMENT, douce, jamais un ecretage. `phys-softmin(v, cap)` a exactement cette
forme : identite stricte sous son genou `0.84*cap`, asymptote exacte a `cap`, pente continue au
genou, strictement croissante.

    e = cp - tg ;  cp <- tg + e * softmin(|e|, ckn+ccp)/|e|

  - **Sous 0.336 B0 c'est l'IDENTITE.** Rien n'est retire au mouvement subtil. Ce n'est pas une
    intention : c'est la docstring de `phys-softmin`, et K3 des predictions le mesure sur les deux
    canaux qui y sont deja.
  - **Aucune vitesse creee.** `cq` est ecrit `cp - fns*cv` APRES la correction, donc `cp - cq` est
    inchange. C'est l'invariant du rebase de §37 ([NOTE-83]), verifiable arithmetiquement.
  - **Une fois par frame**, a la publication de l'etat, jamais dans une boucle de contraintes :
    `phys-softmin` n'est pas idempotent au-dessus de son genou et sa docstring l'interdit.
  - **Il se chiffre** (`phys-limiter` 11/12, emis en `PHYSLIMW`) et **il est desarmable** par
    `*phys-rr-off*`, l'interrupteur d'ablation qui existait deja.

**POURQUOI CE N'EST PAS « UN SUPPRESSEUR DE PLUS ».** Le contrat en interdit un qui retire du
mouvement sans mesure. Celui-ci ne peut pas en retirer sous le genou (identite), et au-dessus il
applique la borne que l'owner a lui-meme chiffree dans sa §22. Le controle negatif exact est la
course precedente : la salle est reproductible octet pour octet.

## NOTE-88  (moteur, aux alentours de la ligne 3918)

```
PREUVE D'EXECUTION du maillon rootlock : l'angle reellement ecrit dans SA 3x3. Il valait 0.0000
structurellement avant ce cycle (le bloc entier etait saute par `(>= l rlk)`), donc toute valeur
non nulle ici prouve que le chemin neuf tourne — et le remettre a `(>= l rlk)` le ramene a zero :
c'est l'A/B.

`rlk0` : ce diagnostic porte sur le maillon que les DONNEES declarent epingle. Sur une racine
graduee il continue donc de publier l'angle ecrit dans sa 3x3, au lieu de disparaitre parce que
`rlk` est tombe a 0.
```

## NOTE-89  (moteur, aux alentours de la ligne 3932)

```
L'ANGLE DU MAILLON 0, SUR TOUTE CHAINE — parce que le zero de `rootrot` juste au-dessus est VIDE
DE DOMAINE des que `rlk0` vaut 0 (les deux chaines de poitrine).

NATURE : un ANGLE en degres (une orientation ecrite), maximum sur la fenetre.
REPERE : direction d'os du joint, pose du modele -> position simulee de son enfant, prise depuis
SON ANCRE — son mouvement PROPRE.
LECTURE QUAND LE MAILLON NE TOURNE PAS : 0.0000, et cette fois le domaine n'est PAS vide (`l = 0`
existe sur toute chaine), donc le zero est une MESURE.
```

## NOTE-90  (moteur, aux alentours de la ligne 4006)

```
23 = LE MEME MAXIMUM QUE 19, MAIS PAR FENETRE DE PUBLICATION (chaine, animation, pilotage). Un
emplacement SEPARE, et c'est necessaire : remettre 19 a zero a chaque fenetre changerait le
maximum de course deja publie. Ses §14 a §20 donnent une bande de COM par REGIME (saut,
atterrissage, freinage, lacet, tangage, roulis) ; un maximum global ne peut se comparer a aucune
d'elles.
```

## NOTE-91  (moteur, aux alentours de la ligne 4015)

```
UN MAXIMUM NE DIT PAS SI UNE BORNE CLIPERAIT UN EXTREME OU MUSELLERAIT LA REPONSE. Trois cumuls
le disent, et c'est la SEULE grandeur qui separe un correctif d'un suppresseur :
   20 = somme des echantillons, 21 = leur nombre,
   22 = combien depassent le plafond DUR de sa §22 (0.40 B0).
NATURE : deux COMPTES et une SOMME, cumules sur la fenetre — ils croissent avec sa duree et ne se
comparent qu'entre chaines d'une MEME course. `20/21` rend la moyenne, `22/21` la part de frames
que la borne mordrait.
```

## NOTE-93  (moteur, aux alentours de la ligne 3099)

```
PIERRE TOMBALE — `phys-retreat-chain`, RETIREE le 2026-08-13, A NE PAS REMETTRE.

Elle cherchait par dichotomie un point admissible SUR LE SEGMENT QUI VA VERS LA POSE DU MODELE :
un aimant vers le dessin de l'animateur, d'autant plus fort que le contact etait profond, donc un
etat qui depend de l'HISTORIQUE du contact — la definition meme de l'hysteresis que l'owner
signale sur TOUS les cheveux (2026-08-13 21:30).

Meme piece, meme role, meme aveu dans l'attic : `d436c4488a`, « the clamp was writing the
ANIMATOR's pose onto every chain that penetrated ».

La regle 6 est desormais tenue par la COLLISION, qui a le dernier mot et ne cite jamais la pose
animee.
```

## NOTE-94  (moteur, aux alentours de la ligne 3469)

```
L'IDENTITE DU CANAL D'AUTEUR, EN REPERE MONDE. `sv` recoit le deplacement ecrit-moins-auteur, `uv`
l'ecart simule remis dans le monde ; leur difference doit etre nulle.

POURQUOI EN MONDE ET NON EN REPERE D'ANCRE : le sujet vit a ~1e5 unites de l'origine. La
transformation de point y soustrait deux grandeurs de 1e6 pour en rendre une de 1e2, et la seule
annulation catastrophique du flottant 32 bits y vaut 0.06 unite — au-dessus de la tolerance, donc
un compteur qui echouait sur 40 % des frames sans qu'aucun defaut n'existe (mesure du
2026-08-11). En monde, les deux membres valent ~1e2 et le bruit tombe a 1e-5.
```

## NOTE-92  (moteur, lignes 637-640, ~3966 et ~4009 — CYCLE 35 ETAPE 1)

```
L'ATTRIBUTION DE `comex` A SES TROIS TERMES, PAR UNE IDENTITE.

Le cycle 34 laisse `comex` a 1.8529 / 1.9097 B0 pour un plafond dur de 0.40 (§22) — le plus gros
depassement ouvert — et il a PROUVE PAR INTERVENTION que borner le point libre `cp` ne le baisse
pas (K5 : +6.4 % / -2.2 %). Il fallait donc savoir QUEL terme le porte avant de dimensionner quoi
que ce soit. Attribuer avant de corriger, comme aux cycles 33 et 34.

`comex` est ecrit  e = [p_sim + D.lc] - [p_auth + R_auth.lc],  ou D = R_auth . rot . T.
En inserant `R_auth . rot . lc`, qui s'annule :

    e =   (p_sim - p_auth)                 [A] TRANSLATION : le joint a bouge
        + R_auth . (rot - I) . lc          [B] ROTATION    : ce maillon a tourne, x son bras `lc`
        + R_auth . rot . (T - I) . lc      [C] DEFORMATION : le tenseur, x son bras `lc`

C'est une IDENTITE : la somme des trois EST `e`, exactement, quelles que soient les valeurs. Ce
n'est pas un modele et il n'y a rien a y croire.

CE QUI EST PUBLIE : les trois PROJECTIONS SIGNEES sur `e^`, de sorte que
    tp + rp + dp = |e|   EXACTEMENT.
Des NORMES ne se recomposent pas — deux termes peuvent s'annuler et trois normes ne le diraient
pas. Des projections signees, si, et leur somme est verifiable par le lecteur.

NATURE  trois LONGUEURS SIGNEES en unites de jeu, relevees a l'ARGMAX de `comex` DE LA FENETRE.
REPERE  le monde, meme frame, contre la pose d'auteur de cette frame — le meme que `comex`.
ABSENT  tp = rp = dp = 0.0000 a la pose d'auteur.

POURQUOI LE RELEVE EST DANS LE MEME `when` QUE L'EMPLACEMENT 23, ET PAS AILLEURS : trois maxima
independants decriraient trois frames differentes, et leur somme ne vaudrait plus `comex`. C'est
exactement le defaut `ROOM-RAD-FLESH-IPAIR` du cycle 34, ou deux lecteurs de la MEME trace
retenaient deux fenetres differentes et sortaient cinq violations qui n'existaient que dans
l'appariement. Un seul `when`, un seul echantillon, trois termes.

POURQUOI `*phys-c1*` EST UN GLOBAL ET NON UNE LIAISON : le terme charniere `R_auth . rot . lc` se
lit entre la pose de `rot` et la post-multiplication par `T`, deux blocs `when` distincts. Ecriture
et lecture ont lieu dans la MEME iteration de la MEME boucle, a une dizaine de lignes d'intervalle
— un global de trois flottants est la forme la moins couteuse qui traverse les deux blocs. Il n'a
aucune duree de vie au-dela de l'iteration et rien d'autre ne le lit.

GEOMETRIE LIVREE QUI REND CETTE ATTRIBUTION NECESSAIRE (course du cycle 34) :
    maillon 0 : os de 1040.50 u = 1.728 B0, centre de chair a 651.18 u = 1.081 B0
    maillon 1 : os de  140.42 u = 0.233 B0, centre de chair a 514.54 u = 0.855 B0
Le maillon 1 porte donc son centre de chair a 3.7x la longueur de son propre os, et le maillon 0
balaie ce centre depuis un bras de 1.73 B0 — pour un budget total de 0.40 B0. Aucune des trois
contributions n'est negligeable a priori, et c'est pourquoi on les mesure au lieu de les supposer.
```

## NOTE-95  (moteur, aux alentours de la ligne 3848 — CYCLE 35 ETAPE 2)

```
LE LEVIER DE ROTATION D'UN MAILLON EST CELUI DE SON ANCRE, PAS CELUI DE SON OS LOCAL.

CE QUE L'ETAPE 1 A MESURE. `comex` (§22) se decompose exactement en trois termes, et la ROTATION
en porte 67 % : moyennes sur 372 fenetres, en B0, pour un budget de 0.40 —
    |tp| 0.2328 (le joint a bouge) · |rp| 0.7714 (le maillon a tourne) · |dp| 0.1761 (le tenseur)
[B] domine 340 fenetres sur 372, et le maillon 0 porte 329 des 372 maxima.

L'ARITHMETIQUE DE LA CAUSE, SUR LES LONGUEURS LIVREES :
  - la rotation ecrite du maillon 0 venait de la direction `lBoob -> lBooc`, un os de 140.42 u ;
  - sa chair est a 651.18 u de lui, et a 89.665 deg de cet os — composante perpendiculaire PLEINE ;
  - amplification 651.18 / 140.42 = 4.637. Pour le maillon 1 : 514.54 / 140.42 = 3.664.
Un tremblement de 100 u (2.4 cm) du joint distal produisait donc 464 u = 0.77 B0 d'excursion du
centre de chair, presque DEUX FOIS le budget entier de sa §22. C'est exactement le `|rp|` mesure.

ET CET OS DE 140 u EST CELUI QUI A ETE INJECTE POUR SA §23. Avant lui, le maillon 0 prenait sa
direction de l'ancre (`chest -> lBoob`, 1042 u) et l'amplification valait 0.625. **La structure
qu'exige sa §23 a rendu sa §22 7.4x plus dure** — invisible jusqu'ici parce que `comex` n'avait ni
resolution par terme ni resolution par maillon.

CE QUE FAIT LE MECANISME. `rest` et `pt` sont desormais lus depuis l'ANCRE DE CHAINE : la
rotation ecrite est celle de la POSITION DU MAILLON AUTOUR DE SON ANCRE, pose d'auteur contre
position simulee. Leviers : 1042 u (maillon 0) et 1182 u (maillon 1), contre 140 u avant.
Amplifications : 0.625 et 0.435 — sous 1, donc la chair se deplace MOINS que le joint, ce qui est
la seule situation physiquement saine.

CE QUE LE MECANISME N'EST PAS. Aucun clamp, aucun seuil, aucune hysteresis, aucune borne : on
change QUEL VECTEUR definit l'orientation, jamais l'amplitude de quoi que ce soit. Sur une chaine
dont la chair serait PROCHE de son os, cette meme regle AUGMENTERAIT le mouvement.

CE QU'IL FAUT SAVOIR AVANT DE REARMER UNE AUTRE CHAINE. Cette regle vaut pour TOUT le write-back,
pas seulement la poitrine — il n'y a pas de drapeau de derogation (regle 4 du contrat). Elle est
juste tant que la chair d'un maillon est LOIN de son os. Pour une meche de cheveux, dont la
geometrie epouse son propre segment, le levier d'ancre serait le mauvais choix et il faudra y
revenir. Le perimetre actuel ne simule que `chestL` et `chestR` (ordre owner du 2026-08-14 07:30),
donc aucune chaine vivante n'est dans ce cas — mais ce n'est pas une raison de le taire.

LE CONTROLE EST LA COURSE PRECEDENTE, ET IL EST EXACT : M6 du cycle 35 etape 1 prouve la salle
reproductible a 32787 lignes `PHYS`, 0 differente. Aucun interrupteur d'ablation n'est ajoute : il
ferait double emploi avec un temoin parfait et couterait des lignes sous la gate CLEAN.

LA BRANCHE SUPPRIMEE. Le `cond` d'avant choisissait la direction vers l'ENFANT simule quand le
maillon en avait un, et celle du parent sinon. Les deux donnaient le meme os de 140 u sur cette
chaine : `pt` etait litteralement identique dans les deux branches (`p_sim(1) - p_sim(0)`), seul
`rest` differait de reference. La simplification retire 23 lignes et ne perd aucun cas.
```

## NOTE-96  (moteur, aux alentours des lignes 385, 3752, 3782 et 4715 — CYCLE 35 ETAPE 3)

```
LES DEUX ENTREES DU TENSEUR, MESUREES AVANT LEUR PLAFOND.

POURQUOI. M3 du cycle 35 a etabli que le tenseur est le porteur RESTANT de sa §22 : 0.2614 B0 de
moyenne pour un budget de 0.40, soit 36 % de ce qui reste apres le correctif de levier. Or ses deux
SORTIES sont collees a leur plafond dans TOUTES les courses mesurees :
    dynm = PHYS-DYN-MAX = 0.2500 exactement      prsm = PHYS-PRS-MAX = 0.2500 exactement
Une sortie collee a son plafond ne dit pas de combien l'entree le depasse — et une entree saturee
ne repond a aucun stimulus. C'est exactement le mode d'echec du cycle 34, ou la saturation de §21
ecrite comme MULTIPLICATEUR DE FORCE gelait le rappel a 46.3 u/frame quel que soit l'ecart.

L'ENTREE DE PRESSION ETAIT DEJA TRACEE (`*phys-prsr*`, publiee en `PHYSSHAPE4 prsr=`) et elle est
enorme : 24.7164 avant le correctif de levier, 15.2761 apres — soit **99x puis 61x son plafond**.
L'ENTREE D'ETIREMENT n'avait AUCUN traceur avant plafond. C'est le trou que cette note comble.

CE QUI EST AJOUTE, ET POURQUOI QUATRE GRANDEURS ET PAS UNE :
    *phys-dynr*  `dl` AVANT `fmin PHYS-DYN-MAX`, maximum de fenetre — l'AMPLITUDE du depassement
    *phys-dynn*  frames ou `dl > PHYS-DYN-MAX` — la FREQUENCE du depassement
    *phys-prsn*  le meme compte pour `pr0 > PHYS-PRS-MAX`
    *phys-dyna*  le nombre de frames comptees, DENOMINATEUR COMMUN aux deux
Une amplitude sans frequence ne distingue pas un canal mort d'un pic rare, et deux comptes sans
denominateur commun ne se comparent pas : c'est la lecon `zero-from-empty-domain` appliquee a
l'envers — ici c'est le domaine qui manquerait pour interpreter un compte non nul.

L'ARITHMETIQUE POSEE AVANT LA MESURE (predictions C35E3, md5 bc44d0e77d1d9c27b528f3ae5e29d483) :
    dx = PHYS-DYN-K * (ox / b0f) + rdr * ux, avec PHYS-DYN-K = 0.43 et rdr <= 0.172 (rrl deja
    borne a 0.40 b0e). Pour `ox` ~ 300 u et b0f = 602 : dl ~ 0.39 pour un plafond de 0.25, soit
    ~1.5x — PAS 60x. Les deux entrees ne saturent donc PAS au meme ordre, et c'est ce que la
    mesure doit trancher : si la pression sature 61x pendant que l'etirement sature 1.5x, le terme
    de §23 qui n'a plus aucune dynamique est la PRESSION DE CONTACT, et le correctif ne se pose
    pas au meme endroit.

CANDIDAT DE CAUSE POUR L'ENTREE DE PRESSION, DEJA MESURE (cycle 35) : les deux volumes de chair
d'un meme sein decrivent LE MEME morceau de chair (recouvrement 75.6 % / 65.3 %, et la sphere
proximale ne couvre pas un seul sommet que la distale ne couvre deja). Le contact est donc applique
DEUX FOIS sur la meme chair a chaque frame.

L'INSTRUMENT EST INERTE : il n'ecrit que ses propres compteurs et ne lit aucun etat du solveur.
Q0 des predictions le verifie ligne pour ligne contre la course C35E2.
```

## NOTE-100  (moteur, aux alentours de la ligne 3347 — CYCLE 36 ETAPE 1)

```
LA DEFORMATION QUE LA CHAIR SUBIT, et ce n'est ni tipvar ni
elong. Owner, 11e passe : « ca change de taille, plus petit,
plus gros, plus long, plus court, ecrase ». Le skinning est
LINEAIRE : deux sommets voisins dont les poids sur ce joint
different de w se separent de w x |p - T|. Rapporte a la
longueur de l'os — la distance sur laquelle les poids passent
de 1 a 0 — ce quotient EST l'echelle de la deformation locale.
`elong` ne peut pas la voir : elle mesure la longueur de l'OS,
qui est justement invariante par construction, et `tipvar` est
une variance, pas une forme.
```

## NOTE-97b  (moteur, aux alentours de la ligne 569 — CYCLE 36 ETAPE 1)

```
REPLIS DU RECUL : fois ou le point de depart de sa recherche, pris sur la sphere du MODELE,
n'etait pas admissible et ou il a fallu repartir de la pose d'auteur exacte. Chacun laisse un
residu d'allongement sur ce lien-la : le chiffre dit combien, au lieu de le laisser deviner.
... et fois ou le BALAYAGE DE LA SPHERE a trouve une direction admissible que l'arc ne pouvait pas
atteindre. Ce compteur et le precedent partagent le meme evenement declencheur (le point de
depart du modele penetre) : leur somme est le nombre de fois ou l'arc etait aveugle, et le rapport
dit combien de ces cas la sphere sauve. Un `retfb` non nul avec `sphere` nul dirait que le
balayage ne trouve jamais rien, donc qu'il ne sert a rien.
```

## NOTE-98  (moteur, aux alentours de la ligne 1740 — CYCLE 36 ETAPE 1)

```
ARME, le controle positif LEVE l'exclusion : le compteur `selfcol` doit alors
monter. Un zero que rien ne peut faire monter ne prouve rien — et c'est
exactement ce qui vient d'arriver. Depuis qu'un lien porte LE MEME volume que
celui que son joint declare, lever la seule exclusion ne suffit plus : le lien
est au centre de sa propre sphere, donc ENTIEREMENT dedans, donc `phys-vol-floor`
le declare libre et aucune poussee ne peut naitre. Mesure : le compteur arme est
tombe de 4457 a 0 sans qu'aucun defaut n'ait ete corrige. Le controle doit donc
injecter le DEFAUT lui-meme — une chaine repoussee hors de ses propres volumes —
et non seulement retirer sa protection : arme, le plancher des paires propres
passe a zero.
```

## NOTE-99  (moteur, aux alentours de la ligne 2738 — CYCLE 36 ETAPE 1)

```
NATURE deux longueurs / B0, maximum et somme sur la fenetre.
REPERE le monde, meme frame, meme attache, meme `bl`. ABSENT
`rgap` = 0.0000 quand la cible EST la pose d'auteur. `perr`
porte un retard d'UNE frame (`tg` precede l'integration).
RESTREINT AU PREMIER MAILLON LIBRE, ET C'EST CE QUI REND LA
GRANDEUR STATIQUE : la, l'attache est l'ANCRE (pose d'auteur),
donc `tg` et `tw` sont sur la MEME sphere de rayon `bl` et leur
ecart est purement angulaire. Au maillon suivant l'attache est
la position SIMULEE du precedent, ce qui melangerait la
dynamique a une mesure declaree sans dynamique.
```

## NOTE-101b  (moteur, aux alentours de la ligne 570 — CYCLE 37 ETAPE 1)

```
------------------------------------------------------------------------------------------------
SPEC 21 / SPEC 22 — SATURATION DE L'EXCURSION. Combien de fois la saturation a mordu sur la
fenetre, et combien de mouvement elle a retire au total.
  NATURE : `n` est un COMPTE d'evenements ; `sum` est une LONGUEUR cumulee, en unites de jeu.
  REPERE : une magnitude de deplacement, donc invariante par rotation — la meme en monde et dans
           le repere du torse que la SPEC 7 de l'owner nomme.
  LECTURE QUAND LE DEFAUT EST ABSENT : `n` = 0 exactement. La saturation ne mord que si
           l'excursion depasse le plafond de l'owner ; une course qui reste dans son enveloppe
           n'incremente rien, et c'est ainsi qu'on distingue « borne » de « brime ».
SPEC 7 du contrat exige de chiffrer ce qu'un suppresseur retire : c'est `sum`, et il est publie.
```

## NOTE-102  (moteur, aux alentours de la ligne 1386 — CYCLE 37 ETAPE 1)

```
------------------------------------------------------------------------------------------------
OU EST LE CENTRE D'UN VOLUME. Une sphere n'est pas forcement centree sur son joint : la 6e passe
de l'owner dit « une sphere au joint ne peut pas epouser un sein ». Son centre est le CENTROIDE
MESURE de la geometrie que ce joint porte, ecrit dans les donnees en espace bind du joint, et
ramene ici dans le monde par la matrice de l'os — donc il suit l'animation comme le joint. Un
offset absent vaut (0,0,0) et le centre redevient le joint, au bit pres.
------------------------------------------------------------------------------------------------
LE DECALAGE MONDE entre le joint d'un lien et le CENTRE du volume qu'il porte. Nul quand ce joint
ne declare aucune sphere ajustee — le comportement est alors exactement celui d'avant, au bit
pres. Ne tourne que la rotation de l'os : c'est un vecteur, pas un point.
```

## NOTE-103  (moteur, aux alentours de la ligne 1545 — CYCLE 37 ETAPE 1)

```
------------------------------------------------------------------------------------------------
UNE CHAINE SE COGNE-T-ELLE DANS SON PROPRE VOLUME ? Owner, 4e et 6e passes : « les pointes et
racines sont ancrees avec l'entre-deux qui bouge enormement », « les meches fines jittent like
crazy des que la tete bouge ». Les colliders `Lbanga`, `Lmidhaira`, `lBoob`... sont les
JOINTS-RACINES des chaines elles-memes, et les capsules `Lbangb->Lbanga` sont des MAILLONS de la
meche : sans exclusion, une meche est poussee hors de sa propre sphere de racine et de ses
propres maillons, en permanence.
L'exclusion est STRUCTURELLE (chaine <-> elle-meme), pas un `colskip` : elle ne lit aucune
donnee, elle compare des index de joints deja resolus.
------------------------------------------------------------------------------------------------
```

## NOTE-104  (moteur, aux alentours de la ligne 4650 — CYCLE 37 ETAPE 1)

```
SPEC 33 — LE DOMAINE DE LA PAIRE (chaine, volume), pas son compte de contacts.
  `which` = 0 -> `cdm`, la profondeur d'approche MAXIMALE atteinte sur toute la course.
             1 -> `cfl`, le plancher que la paire tolere (sa profondeur a la pose d'auteur).
             2 -> 1.0 si la paire a ete echantillonnee au moins une fois, 0.0 sinon. C'est le
                  discriminant qui empeche de lire un tableau jamais ecrit comme un « 0 mesure » :
                  une paire jamais testee et une paire testee qui ne se touche pas rendraient
                  toutes deux 0.0 sans lui.
NATURE : une longueur, unites de jeu (4096 u = 1 m). REPERE : monde. `cdm` NEGATIF = les deux
surfaces ne se sont jamais rejointes, et sa valeur absolue EST l'ecart minimal atteint.
Accumulees sur TOUTE la course : volontairement hors de `phys-diag-reset!`, qui est par fenetre.
```

## NOTE-106  (moteur, aux alentours de la ligne 3760 — CYCLE 37 ETAPE 2)

```
Sa §23 demande « local collision PRESSURE » : une INTENSITE.
`cl` n'en est pas une — l'etape 1 l'a mesure : c'est la somme
de 150 a 254 poussees petites et de meme sens accumulees sur
les 45 balayages de la frame (psum/cl = 1.11 et 1.28), soit
4.4 et 5.0 METRES de chemin de correction en une frame. La
PLUS GRANDE POUSSEE SEULE, elle, est une intensite : 404.7 et
262.4 u, de l'ordre de la penetration mesuree (390 / 374 u).
LA DIRECTION RESTE CELLE DE `*phys-cpu*` (bien conditionnee,
les poussees s'alignent) : seul le MODULE change de source.
CE N'EST PAS UN SUPPRESSEUR : `PHYS-PRS-MAX` ne bouge pas, et
sur une frame a UNE poussee `pmx` = `cl` au bit pres.
```

## NOTE-107  (moteur, aux alentours de la ligne 448 — CYCLE 37 ETAPE 2)

```
SPEC 5 — L'ANIMATION D'AUTEUR. Detection PAR CHAINE, dans le repere de l'ancre (rotation
comprise) : c'est la seule facon de distinguer « l'animateur a bouge CET os » de « l'os porteur a
tourne et a emmene la chaine avec lui ». Le second n'est pas une intention d'auteur sur la
chaine, et le confondre avec la premiere est exactement le piege qui a fige l'ancien moteur.
  u = pointe d'AUTEUR en repere ancre, s = pointe ECRITE en repere ancre (s = u + o).
  frame PILOTEE PAR L'ANIM  : |delta u| > PHYS-AUTH-EPS
  TRANSMISSION de la chaine : somme(delta s . delta u) / somme(delta u . delta u)
Un ressort en repere monde retarde l'auteur et transmet ~0.5 ; la forme additive transmet 1.0.
Ces compteurs survivent aux fenetres : c'est le bilan de la course.
```

## NOTE-108  (moteur, aux alentours de la ligne 82 — CYCLE 37 ETAPE 2)

```
SPEC 6 — `B0`, LA LONGUEUR CARACTERISTIQUE RACINE->APEX DE LA CHAIR, EN UNITES, MESUREE SUR LE
MAILLAGE. Ce n'est PAS la longueur d'os, et la confusion coutait une gate muette : sa §6 dit
« B0 neutral characteristic root-to-apex length […] shall derive normalized dimensions directly
from the character mesh », reference humaine 115-125 mm. Sur Keira l'os `chest->lBoob` fait
977 u (238 mm) — la distance du thorax a un joint qui est DERRIERE la chair — la ou la chair
elle-meme court sur 602 u (147 mm). Une borne exprimee « en B0 » contre l'os est donc 1.62x trop
large, et le plafond d'apex de sa §22 ne pouvait pas mordre : l'excursion mesuree « 0.479 B0 »
vaut 0.778 B0 contre sa reference.
0 = NON DECLARE : on retombe alors exactement sur la longueur d'os, donc une chaine qui ne porte
pas la cle ne bouge pas d'un bit.
```

## NOTE-110  (moteur, aux alentours de la ligne 1667 — CYCLE 37 ETAPE 2)

```
[DECISION 1, critere revise 2026-08-18] Le decideur est LE PLUS PROFOND
VIOLEUR (res = dep - feff) ; la cle structurelle ne departage plus qu'un
res strictement egal. ATTENTION, ET C'EST MESURE : ce choix est INERTE
dans l'etat livre — `*phys-prio-off*` vaut 1 (NOTE-07 : l'arbitrage a
ete ARME une fois, il faisait passer `meshpen` positif sur 13 chaines)
et ses deux consommateurs exigent `(zero? *phys-prio-off*)`. Tableau
BIT-IDENTIQUE avant/apres (course du 18/08 09:31). Il ne corrige donc
PAS le `meshpen` de la structure a 2 maillons : cette attribution-la,
ecrite ici le 18/08 au matin, etait fausse et elle est retiree.
```

## NOTE-111  (moteur, aux alentours de la ligne 476 — CYCLE 37 ETAPE 2)

```
MARGE DE SORTIE de la projection de collision, en unites de jeu (0.5 u = 0.12 mm). Ce n'est pas
un suppresseur de mouvement : c'est la tolerance qui rend la sortie STRICTEMENT geometrique
plutot que « a l'arrondi pres ». Sans elle, resoudre a l'egalite laisse un residu de signe
aleatoire de l'ordre de 1e-3 u, et « penetration nulle » devient « penetration nulle une fois
sur deux ». Elle retire 0.12 mm d'amplitude a la chaine, chiffre dans le rapport.
NOMBRE D'ALTERNANCES (longueur <-> franchissement) A LA FINITION DE CHAQUE LIEN.
4 : au-dela, la course ne bouge plus (les deux contraintes sont des projections, la convergence
est geometrique). En dessous de 2 il n'y a pas d'alternance du tout, donc pas de resolution
simultanee -- et c'est l'etat mesure qui plafonnait `ROOM-SIDE crossing` a 11282.
```


## NOTE-110  (moteur, aux alentours de la ligne 1727 — CYCLE 38 ETAPE 4)

`*phys-cfl*` etait ecrit par une AFFECTATION (`set!`) pendant que `*phys-cdm*`, range trois lignes
plus bas et sous le meme drapeau de domaine, etait accumule en MAXIMUM. Les deux etaient publies
cote a cote par `PHYSCVDOM` et lus l'un contre l'autre.

**C'est une comparaison entre un maximum de course et UN echantillon** — le dernier frame evalue
pour cette paire (chaine, volume). L'ecart `cdm - feff` ne repondait donc a aucune question de
population : il melangeait deux statistiques de natures differentes, exactement le piege que le
registre nomme (« un max divise par une autre statistique »). Un `feff = 0` ne disait pas « la pose
d'auteur n'a JAMAIS mis ce lien dans ce volume », il disait « elle ne l'y mettait pas a la derniere
frame ».

**LES DEUX SONT MAINTENANT DES MAXIMA, sous le MEME drapeau `*phys-cdmok*`**, donc commensurables :
`feff` devient « la plus grande profondeur que la pose d'AUTEUR ait jamais rendue admissible pour
cette paire », et `cdm` « la plus grande profondeur que le lien SIMULE ait jamais atteinte ». Leur
difference est alors la question posee : ce que le maillon ajoute par-dessus ce que l'auteur accorde.

Rien d'autre ne lit `*phys-cfl*` : le calcul de la poussee utilise la variable LOCALE `feff`, pas le
tableau. Le changement est donc purement instrumental, et sa preuve est que les lignes `PHYS` de la
course, hors `PHYSCVDOM`, doivent rester identiques.

**DEUXIEME CORRECTION, LE MEME CYCLE, ET ELLE TOUCHE AUSSI L'INSTRUMENT D'ORIGINE.** Passer `feff`
en maximum a fait remonter **`PHYS-VOL-FREE` = 1e9** sur les 108 paires : c'est le sentinelle que
`phys-vol-floor` rend quand le controle k=4 DESARME le mur de collision (`*phys-col-off*`). Un
maximum avale un sentinelle et ne le signale pas — le piege du registre, paye une fois de plus.

Et la consequence porte plus loin que ma ligne : **`*phys-cdm*` etait deja un maximum depuis le
cycle 34, et il accumulait lui aussi pendant la jambe ou le mur est desarme** — c'est-a-dire la
jambe ou le lien va precisement plus profond que partout ailleurs, par construction. La grandeur
« la plus grande profondeur atteinte » melangeait donc deux regimes dont l'un existe pour mesurer
autre chose.

Les DEUX maxima sont desormais accumules **uniquement quand le mur est ARME** (`(zero?
*phys-col-off*)`), ce qui est le seul regime ou la question « ce que l'auteur accorde contre ce que
le lien prend » a un sens. Le drapeau de domaine suit la meme condition, donc une paire qui n'existe
que dans la jambe desarmee se lit `ok=0` et non « profondeur nulle ».

## NOTE-112  (moteur, aux alentours de la ligne 3956, et `phys-comexw-reset!` — CYCLE 41)

**UN CENTRE DE MASSE EST UNE MOYENNE PONDEREE PAR LA MASSE. `comex` EST UN MAXIMUM SUR DEUX
ECHANTILLONS. CE NE SONT PAS LA MEME GRANDEUR, ET C'EST LA SECONDE QUI EST PUBLIEE DEPUIS 40
CYCLES SOUS LE NOM QUE SA SPEC DONNE A LA PREMIERE.**

Sa SPEC 6 : « `P0` neutral breast center-of-mass POSITION ». Sa SPEC 22 : « Breast COM : normal
<= 35 % B0, hard transient <= 40 % B0 ». Sa SPEC 23 : « `x` = relative breast COM displacement ».
Les trois designent UN point par sein — la moyenne des positions de la chair, ponderee par sa
masse.

Ce que l'emplacement 23 contient : pour chaque maillon `l`, le moteur calcule l'excursion du
point `joint_l + lc_l` ou `lc_l` est le centre du VOLUME DE COLLISION porte par ce joint
(`jak-hd-physics.gc:936-939`, lu dans `physics_chains.txt`), puis garde le PLUS GRAND des deux
(l'emplacement est indexe par CHAINE, pas par maillon). Trois ecarts avec la grandeur nommee :

  1. **UN MAXIMUM N'EST PAS UNE MOYENNE.** Il repond « quel est le point le plus loin » et jamais
     « ou est le centre ».
  2. **LES DEUX ECHANTILLONS NE PESENT PAS PAREIL.** Mesure sur le mesh livre
     (`out/jak1/fr3/skin/keira-hd-lod0.glb`), nuage = sommets portant un poids non nul sur au
     moins un os de chaine, poids normalises a 4.5e-08 pres :

         chestL n=94   chest 45.57 %   lBooc 35.24 %   lBoob 18.91 %   Lshoulder 0.28 %
         chestR n=90   chest 45.33 %   rBooc 31.94 %   rBoob 22.00 %   Rshoulder 0.73 %

     Le maillon 0 possede 18.9 % / 22.0 % de la masse — et c'est lui qui porte le maximum publie
     dans 82.3 % / 93.0 % des fenetres, parce que son bras de chair pend au bout du levier le
     plus long (1040 u + 651 u contre 140 u + 515 u).
  3. **45.6 % / 45.3 % DE LA CHAIR EST ANCREE ET SON EXCURSION EST NULLE PAR CONSTRUCTION.**
     `chest` et `?shoulder` ne sont pas simules : leur matrice ecrite EST leur matrice d'auteur,
     donc `p_sim - p_auteur` y vaut exactement zero. Cette moitie de la masse ne peut par
     definition pas entrer dans un maximum, alors qu'elle entre dans une moyenne — et elle la
     divise presque par deux.

**CE QUE LES EMPLACEMENTS 35-42 AJOUTENT, ET CE QU'ILS N'AJOUTENT PAS.**
  * `35+l` = le meme `ee` que 23, mais PAR MAILLON, avant l'ecrasement. C'est la seule chose qui
    manquait pour recomposer une moyenne : le lecteur applique les poids MESURES ci-dessus.
  * `39+l` = |p_sim - p_auteur| du JOINT seul, rapporte a B0, releve A LA FRAME QUI MAXIMISE
    `35+l` — jamais son propre maximum, sinon les deux viendraient de deux frames differentes
    (piege `RAD-FLESH-IPAIR`, cycle 34). C'est la part de l'excursion qui NE DEPEND PAS de `lc` :
    elle borne par en dessous ce que la mesure vaudrait si le centre de chair etait pose sur le
    joint, et elle repond donc a « le depassement est-il un artefact du placement du centroide ? »
  * Ils n'ajoutent AUCUN mecanisme : rien dans le solveur ne les relit. Le controle d'inertie est
    que toutes les autres lignes publiees soient identiques au bit pres a la course precedente.

**POURQUOI LA PONDERATION N'EST PAS FAITE DANS LE MOTEUR.** Les poids de peau ne sont pas une
donnee que le moteur lit ; les cabler en dur serait la rustine que la regle 4 interdit, et un
chiffre unique calcule ici serait invivrifiable. Publier les deux `ee` bruts laisse la
ponderation au lecteur, avec des poids mesures sur le mesh LIVRE et cites.

**RESERVE, ET ELLE EST DANS LE RAPPORT AUSSI.** Recomposer |somme ponderee de VECTEURS| a partir
de NORMES donne une BORNE SUPERIEURE (inegalite triangulaire), pas la valeur. Elle n'est serree
que si les deux excursions sont presque colineaires — ce que la part `jt` permet de verifier au
lieu de le supposer. Et `lc` est le centroide de la geometrie possedee AU SENS DE LA CHAINE
(somme de chaine > 0.5, partage par argmax) ; le centroide pondere par le poids du joint est plus
COURT de 7.6 % (lBoob) et 1.0 % (lBooc), donc la borne publiee est conservatrice des deux cotes.

**REMISE A ZERO.** Les vingt emplacements 23-42 ont tous la portee d'une FENETRE (chaine,
animation, pilotage) et la meme valeur de repos : `phys-comexw-reset!` les balaye d'un seul
`dotimes`. Les enumerer un par un etait le vrai risque — un emplacement neuf ouvert ailleurs
pouvait etre oublie ici, et il aurait alors publie a chaque fenetre le maximum de la COURSE sans
que rien ne le dise. Les emplacements 19 a 22 gardent la portee de la COURSE et ne sont pas
touches.

## NOTE-113

**SPEC 22 EST UNE BORNE DE REPLI, PAS UNE LAISSE VERS LA POSE D'AUTEUR.**

La borne de SPEC 22 etait comparee a `dd = |p_simule - p_auteur|`, la distance du joint a SA
position d'auteur dans le MONDE. Sur le maillon RACINE c'est la bonne grandeur : son attache est
l'ancre, l'ancre n'est pas simulee, donc sa position d'auteur et sa position simulee coincident et
`dd` EST le repli du maillon autour de son attache.

Sur un maillon NON-RACINE, non. Son attache est le maillon precedent, qui est SIMULE et qui a sa
propre deviation. `dd` y additionne donc deux choses de natures differentes : le repli propre du
maillon (ce que SPEC 22 borne) et le deplacement que son parent lui fait SUBIR (dont il n'est pas
responsable et qui, lui, est deja borne sur le parent). Serrer `dd` sur un maillon distal ne
borne pas son repli : cela le tire vers sa pose d'auteur en LUTTANT contre la contrainte de
longueur — c'est-a-dire que cela l'epingle a l'animation, exactement le mode d'echec que la
directive du 2026-08-18 interdit sur un os injecte.

La cible est donc decalee de la deviation du parent : `t' = t_auteur + (p_parent - t_parent)`.
Sur le maillon racine le terme ajoute vaut ZERO par construction (`kp = -1`), donc `t' = t` et le
maillon racine est INCHANGE AU BIT PRES — c'est la preuve de non-regression, elle est structurelle
et pas experimentale. Sur un maillon distal, `dd` devient le repli seul.

## NOTE-114

**LA MEME LONGUEUR ABSOLUE SUR DEUX OS DE 1040.5 ET 140.4 u : TENDUE SUR L'UN, INATTEIGNABLE SUR
L'AUTRE.**

`kn = 0.42 B0` et `cp = 0.08 B0` sont des LONGUEURS ABSOLUES (252.84 u et 48.16 u pour B0 = 602).
Elles etaient appliquees telles quelles a tous les maillons. Or un maillon qui pivote de `theta`
autour de son attache deplace son joint de `2*bl*sin(theta/2)` : la meme longueur absolue est donc
un ANGLE PERMIS qui depend de la longueur de l'os. Mesure sur la trace (`PHYSBONE`) :

    chestL  l=0 bl=1040.5006  ->  plafond 301.0 u = 16.6331 deg   MESURE max 16.73 deg  (+0.58 %)
    chestR  l=0 bl=1039.0379  ->  plafond 301.0 u = 16.6567 deg   MESURE max 19.35 deg  (+16.2 %)
    chestL  l=1 bl= 140.4225  ->  2*bl = 280.845 u < 301.0 u  ->  AUCUN pivot n'atteint la borne
    chestR  l=1 bl= 144.2315  ->  2*bl = 288.463 u < 301.0 u  ->  IDEM

Sur le distal la borne est donc GEOMETRIQUEMENT INATTEIGNABLE : pas meme un repli de 180 degres ne
la declenche. Et c'est ce que la trace montre — `PHYSGRAD ang` du maillon distal atteint
**145.67 deg** (chestL, `updown`) et **143.92 deg** (chestR), mediane 72 a 88 deg sous pilotage,
et deja 26.10 / 20.29 deg de mediane sur l'ANIMATION SEULE. La contrainte de longueur, elle, tient
(`PHYSSTR el` = 0.0001 a 0.0002) : c'est donc une ROTATION RIGIDE de l'os, pas un effondrement de
la mesure. Cet os porte 35.24 % / 31.94 % du poids de la chair du sein et est MAJORITAIRE sur
43.5 % / 37.5 % du nuage (cycle 41) : son repli est de la chair retournee.

Le correctif rend la borne commensurable a l'os qui la subit :

    rl = fmin(1.0, blen(maillon) / blen(maillon racine))
    kn = 0.42 * B0 * rl        cp = 0.08 * B0 * rl

`rl` vaut EXACTEMENT 1.0 sur le maillon racine (le rapport d'une grandeur a elle-meme), donc la
racine est inchangee au bit pres, comme en NOTE-113. Le `fmin 1.0` garantit que l'intervention est
MONOTONE : elle ne peut que SERRER, jamais desserrer, donc elle ne peut ajouter de mouvement nulle
part. Le plafond devient le meme ANGLE sur tous les maillons — l'angle que SPEC 22 permet deja sur
le levier de la racine — sans qu'aucune constante neuve soit introduite ni aucun nombre ajuste.

**RESERVE PUBLIEE.** SPEC 31 demande une mobilite CROISSANTE vers la pointe. Un plafond d'angle
commun est un PLAFOND, pas une cible, et le mouvement ABSOLU du distal reste superieur puisqu'il
herite du proximal ; mais une borne GRADUEE derivee de SPEC 31 reste a etablir, et elle n'est pas
inventee ici. Non touche non plus : la saturation de SPEC 21 a l'interieur du sous-pas
(`kn`/`cpp` sur `b0e`, meme fichier), qui porte sur une AUTRE grandeur (la distance a la cible du
ressort de materiau, pas a la pose d'auteur) et qui n'a pas de mesure l'incriminant.

## NOTE-115

**PORTEE DE SPEC 21/22, RELEVEE SUR LA COURSE ET PAS SUR UN NOM** (prose deplacee du source le
2026-08-19, cycle 42, pour rendre de la marge sous le plafond de lignes de la gate `CLEAN` ; pas
une ligne de code n'a change avec elle).

`PHYSCHAIN` publie `fam=` et `links=` pour les 22 chaines, et le couple (famille A) ne selectionne
que `c=7 lBoob` et `c=8 rBoob`. Sens mecanique d'origine : une chaine a UN maillon n'a aucune
articulation interne, donc toute son excursion EST la rotation d'un bloc autour de son ancre — la
grandeur meme que SPEC 22 borne. Les 13 chaines de famille B (lunettes, sangles, languettes) sont
hors perimetre par construction, donc `goggles-tunnel` et `knee-tabs`, que l'owner a FERMES, ne
peuvent pas etre payes ici.

**ET CE « UN MAILLON » N'EST PLUS VRAI DEPUIS LE 2026-08-18** : sa SPEC 23/30 a impose le second
os, la chaine porte `links=2`, et l'excursion n'est plus la rotation d'un bloc — elle a une
articulation interne, qui s'est reveleee non bornee (voir NOTE-114). La phrase est conservee ici
telle qu'elle a ete ecrite, avec sa date de peremption, parce que c'est elle qui a justifie
plusieurs choix encore en place.

**[NOTE-56]** `(= n 1)` RETIRE le 2026-08-17 : c'etait la garde qui aurait DESARME SPEC 21 et
SPEC 22 a l'injection du second os. Famille A ne selectionne que `chestL`/`chestR` (les seules
chaines simulees, ordre du 2026-08-14 07:30), donc le `n` etait un doublon de selecteur — et un
zero produit par un bloc qui ne s'execute plus n'est pas un zero gagne.

**[NOTE-38]** `gmean` et sa normalisation RETIREES le 2026-08-19 : voir NOTE-74.

## NOTE-116

**L'ANGLE DE SPEC 22, DERIVE ET NON CHOISI, QUAND LA DONNEE N'EN POSE PAS.**

`phys-bend-chain` est la borne de repli A LONGUEUR CONSTANTE : elle fait TOURNER le maillon autour
de son attache, `dl` inchange, avec `phys-softmin` (identite stricte sous 0.84*cap, asymptote
exacte a `cap`). Elle etait pilotee UNIQUEMENT par la cle de donnee `maxangle=`, et le generateur
`physics_keira_gen2.py` interdit activement cette cle hors des meches (auto-controle 6b, :2218) :
la poitrine ne pouvait donc pas l'armer par la donnee, quoi qu'on ecrive dans le fichier.

Quand la donnee ne pose rien (`maxangle <= 0`) et que la chaine est de famille A, l'angle est
maintenant DERIVE des deux memes nombres que la borne positionnelle de SPEC 22 :

    amax = 2*asin( 0.50*B0 / (2*blen(maillon racine)) )
         = 16.633 deg (chestL, B0=602, blr=1040.50)   16.657 deg (chestR, blr=1039.04)

C'est l'angle que le plafond dur de SPEC 22 permet DEJA sur le levier de la racine — donc aucune
constante neuve, aucun nombre ajuste, et sur le maillon racine la borne coincide avec celle qui y
regnait deja. Le genou de `phys-softmin` vaut 0.84*cap, c'est-a-dire EXACTEMENT le rapport
0.42/0.50 de SPEC 22 : les deux saturations ont la meme forme par construction.

**POURQUOI ICI ET PAS DANS LA BORNE POSITIONNELLE (NOTE-114).** Les trois etages du meme maillon,
mesures apres NOTE-113/114 (chestL l=1, `PHYSGRADS`/`PHYSGRAD`) :

    apres integration seule (cap-ang etage 0, :3032)             134.31 deg
    apres la borne positionnelle de SPEC 22 (:3040)              <= 16.63 deg par construction
    apres les 8 balayages longueur+collision (etage 1, :3091)  ** 164.13 deg **
    final                                                        116.09 deg

Le repli n'est pas produit par l'integration : il est produit par les BALAYAGES DE CONTRAINTE, qui
emmenent le maillon de 16.6 a 164 deg — plus haut que ce que l'integration seule donnait. Une
borne POSITIONNELLE placee avant eux ne peut donc rien tenir. `phys-bend-chain` est appelee :3087,
APRES ces 8 balayages, et c'est la seule position ou une borne de repli puisse mordre.

**CE QUE CELA NE TIENT PAS ENCORE.** Sept balayages tournent APRES `phys-bend-chain` (:3093 trois
longueur+collision, :3096 quatre collision seule). Ce qu'ils rendent au repli se lit dans l'ecart
entre `PHYSGRADS a1` et `PHYSGRAD ang` finaux, et il est publie a chaque cycle.

**PORTEE.** Le comportement des chaines qui posent `maxangle=` dans la donnee (les meches, gelees
depuis le 2026-08-14) est INCHANGE : la donnee reste prioritaire. Seule la famille A sans cle
derive son angle. Et c'est un mecanisme que l'owner avait exclu de la poitrine le 2026-08-11
22:35, au motif ecrit qu'« une chaine a un seul maillon n'a aucun angle inter-maillon » — motif
mort le 2026-08-18 avec l'injection du second os. Sa consigne est citee, sa premisse est datee,
et l'arbitrage lui revient.

## [NOTE-117] L'ATTENUATION D'ANGLE ENTRE DANS LA RELAXATION DE QUEUE

Mesure du cycle 43 (course `keira-room-x86.C42E4-BENDARM.log`, appariee PAR FENETRE, donc sans
comparer des maxima issus de fenetres differentes) :

    pire fenetre chestL l=1 (anim 14, accel) : a0=121.16 -> a1=16.54 -> FINAL 111.56   (+95.03 deg)
    pire fenetre chestR l=1 (anim  6, accel) : a0=115.96 -> a1=16.57 -> FINAL  94.02   (+77.45 deg)
    mediane de l'ajout de queue : +27.22 deg (chestL l=1) · +26.46 deg (chestR l=1)

`phys-bend-chain` etait un COUP UNIQUE pose HORS de la boucle de relaxation, alors que longueur et
collision sont DEDANS. Dans un Gauss-Seidel, une contrainte hors boucle est une contrainte que les
suivantes reecrivent : les 7 balayages de queue RESTAURENT le repli que l'attenuation vient de
retirer. Le controle le prouve — sur la course d'AVANT l'attenuation, le meme ajout de queue a une
mediane de **0.00 deg**. La queue ne « finit » pas : elle ne bouge ce maillon que quand quelqu'un
d'autre l'a bouge d'abord.

POURQUOI CE MAILLON-LA, ET PAS LA RACINE. Converti en deplacement (d = 2*bl*sin(theta/2)), l'ajout
de queue vaut jusqu'a **1.37 fois la LONGUEUR de l'os qu'il corrige** (191.8 u sur 140.4 u), alors
que la MEME machinerie ne deplace pas la racine (mediane 0.00 u sur 1040.5 u). La difference n'est
pas dans les volumes — le cycle 38 a mesure qu'AU REPOS ces joints sont dans 1-2 volumes, MOINS
qu'un coude temoin. Elle est dans le BRAS : un meme push rend **7.4 fois plus d'angle** sur l'os
distal (32 u -> 1.76 deg sur la racine, 13.09 deg sur le distal).

CE QUE CE CHANGEMENT EST, ET CE QU'IL N'EST PAS. Aucune constante neuve, aucun nombre ajuste,
aucune donnee modifiee : le meme `amax` derive des memes deux nombres, appele dans chaque iteration
de queue au lieu d'une fois avant elles. **Ce n'est pas un suppresseur ajoute** — c'est une
contrainte deja ecrite, remise dans le solveur ou vivent les autres. Le cout en mouvement est
publie au rapport, il n'est pas cache.

CE QU'IL NE CORRIGE PAS, ecrit d'avance : la boucle de collision ne converge pas sur un ensemble de
volumes incoherent (cycle 37 : les 12 derniers balayages ne portent aucune contrainte de longueur
et poussent encore a 94-97 % de la moyenne de frame ; `skinpen` 0.142 m > `meshpen` 0.098 m, donc
les capsules n'enveloppent pas le mesh). Interleaver est un ARBITRAGE entre deux contraintes qui se
contredisent, pas une reconciliation. Le chantier suivant est l'ensemble de volumes.

## [NOTE-118] `phys-bend-chain` REPOSE LE JOINT A LA LONGUEUR DU MODELE, PAS A LA COURANTE

Regression MESUREE et introduite par [NOTE-117] dans la meme heure : `ROOM-STRETCH` max
**0.0002/0.0003 -> 0.0594** (chestR, leftright, `assistant-lavatube-start-idle-b`), soit 1 couple
(chaine, pilotage) au-dessus du plafond de 3 % que NOTE-45 publie. Sa regle est « un os ne
s'allonge pas ».

LA CAUSE, LUE DANS LE SOURCE. `phys-length-chain` projette sur la sphere de rayon `want` = |m|, le
vecteur entre les positions ANIMEES du parent et du joint — la longueur que LE MODELE donne a cet os
cette frame-ci. `phys-bend-chain` calcule EXACTEMENT le meme `m` (meme source, meme frame) et en
tire `ml`, puis reposait le joint a `dl`, la distance COURANTE a l'attache. Bend traite l=0 puis
l=1 : quand il deplace l=0, l'attache de l=1 bouge, donc le `dl` de l=1 mesure une autre longueur —
et bend la GRAVAIT au lieu de la corriger. Appele une fois apres une passe de longueur c'etait sans
effet ; appele 7 fois de plus, dont une en fin de frame sans passe de longueur derriere (NOTE-45 :
le dernier bloc est de la collision SEULE, deliberement), l'ecart se compose.

LE CORRECTIF EST DE TROIS JETONS : `dl` -> `ml` dans les trois ecritures de position. Aucune
constante neuve ; `ml` est deja calcule dans le meme `let*`, depuis la meme source que `want`. Bend
devient ce que l'owner a ecrit mot pour mot pour la famille A — « tourner autour de son ancre A
LONGUEUR INVARIANTE » — au lieu d'une rotation qui conserve l'erreur de longueur qu'elle trouve.

PORTEE. Le bloc reste gate par `(< adg2 (- adeg 0.01))` : sur les frames ou l'angle est DANS sa
borne, bend n'ecrit rien et ne touche donc a aucune longueur. Ce n'est pas une contrainte de
longueur permanente qui doublerait `phys-length-chain` ; c'est la meme rotation, posee sur le bon
rayon.

## [NOTE-119] `hard?` — UNE BORNE QUI VIT DANS UNE BOUCLE DOIT ETRE IDEMPOTENTE

`phys-softmin` (:963) porte dans SON PROPRE DOCSTRING : « NON IDEMPOTENT AU-DESSUS DU GENOU
[...] NE JAMAIS L'APPELER DANS UNE BOUCLE DE CONTRAINTES ». Le registre porte la meme lecon,
payee le 2026-08-12 : un min DOUX dans la boucle avait coute ~50 % du mouvement de pointe sur
onze chaines. **[NOTE-117] a fait exactement cela**, en portant `phys-softmin` de 1 a 8
applications par frame.

PREUVE ARITHMETIQUE, SANS COURSE. Point fixe approche de f^8, amax = 16.633 / 16.657, genou
kn = 0.84*amax = 13.972 / 13.992 :

    depart  18 deg -> apres 8 applications  14.279 / 14.299
    depart  40 deg ->                       14.300 / 14.321
    depart 120 deg ->                       14.303 / 14.324
                          MESURE SUR LA COURSE :  **14.26 sur LES DEUX CHAINES**

Le plafond devient INDEPENDANT DE L'ENTREE a 0.03 deg pres sur un rapport d'entree de 1 a 6.7 —
la definition d'une mesure non discriminante (ecart entre pilotages tombe a 2.9 %). Signature qui
confirme : le pilotage BASE (13.85 / 13.43) est SOUS le genou, donc identite, donc **le seul
intouche** — et c'est exactement le seul qui n'a pas bouge.

LE CORRECTIF. Un parametre `hard?` :
  * appel HORS boucle (:3091) : `#f` -> `phys-softmin`. La FORME douce de l'approche est
    conservee, UNE fois par frame, exactement comme avant [NOTE-117].
  * appels DANS les deux blocs de queue (:3101, :3105) : `#t` -> `(fmin adeg amax)`. Idempotent
    (`min(min(x,c),c) = min(x,c)`), donc appelable 7 fois sans rien eroder : il ne fait que
    REFUSER DE DEPASSER `amax`, il ne tire jamais en dessous.
Aucune constante neuve ; `amax` est le meme, derive des memes deux nombres.

LA REGLE GENERALE, ET ELLE VAUT AU-DELA D'ICI : avant de mettre une contrainte dans une
relaxation, verifier qu'elle est IDEMPOTENTE. Une saturation lisse ne l'est jamais au-dessus de
son genou ; repetee, elle converge vers son genou et efface l'entree. Le test qui la debusque est
gratuit : comparer le plafond obtenu depuis deux entrees tres differentes — s'il est le meme,
c'est un point fixe, pas une borne.


## NOTE-000 — LA FORME DU MOTEUR, ET POURQUOI ELLE FAIT TOMBER SIX SECTIONS D'UN COUP

Externalise depuis l'en-tete de `jak-hd-physics.gc` le 2026-08-19 (cycle 45). Rien n'est retire :
le texte est integral ci-dessous, et le fichier source en garde le pointeur. Motif : le moteur
etait a 4804 lignes contre le plafond de 4800 de la gate CLEAN, et ce plafond vise l'empilement
de SUPPRESSEURS. Rendre de la marge en deplacant de la PROSE (zero changement de comportement,
GAME.CGO bit-identique) est la seule facon d'y revenir sans toucher a la gate, que la regle 5
me gele explicitement.

```
jak-hd-physics.gc — PHYSIQUE SECONDAIRE DE KEIRA (depart propre 2026-08-11).

L'ancien moteur (6000 lignes) est parke sur `physics-attic-2026-08-11`. Il n'est PAS une base de
travail : la cause MESUREE de son echec est l'empilement de suppresseurs (1940 -> 6000 lignes,
clamps 9 -> 84, detection d'anim 45 -> 172) jusqu'a ce que 42 % des mesures soient a zero.
Celui-ci implemente `.autoport/prompts/SPEC-keira-physique.md`, section par section, et RIEN
d'autre. Aucun gel de calme, aucun sommeil, aucune hysteresis, aucun clamp de vitesse, aucun
masque ni filtre de volume : ce qui limite une chaine est soit la LONGUEUR D'UN OS, soit un
COLLIDER, soit la POSE DU MODELE. Ce sont les trois seuls limiteurs de la SPEC.

LA FORME DU MOTEUR — et c'est elle qui fait tomber trois exigences d'un coup.
Le simule n'est pas la position du joint : c'est son ECART a la pose d'auteur, exprime dans le
repere de l'os porteur (l'ancre). La position ecrite vaut

    p_l  =  T_l  +  R_ancre . o_l                (T = pose retargetee, o = ecart simule)

d'ou, sans un seul cas particulier :
  SPEC 2  la racine ne bouge pas   -> o = 0 sur les liens `rootlock` : ils ne sont ni integres
                                      ni ecrits, la pose du retarget reste, au bit pres.
  SPEC 4  le repos = le modele     -> famille A (gravite nulle) : o -> 0, donc p -> T. Ce n'est
                                      pas un reglage, c'est le point fixe de l'integrateur.
                                      Famille B (gravite) : o s'arrete sur un ecart statique,
                                      ca pend et ca reste pendu.
  SPEC 5  l'animation d'auteur     -> le deplacement d'auteur (T) traverse avec un coefficient
                                      de 1 : la physique AJOUTE o, elle ne remplace rien et ne
                                      peut donc pas retarder l'animation. Un ressort ecrit en
                                      repere monde, lui, la retarde — c'est ce que mesure la
                                      colonne `authored` de la salle, et c'est ce qui separe
                                      les deux formes.
  SPEC 1  ce qui a de la physique  -> les chaines viennent du fichier de donnees, genere depuis
                                      le rig. Le moteur ne connait aucun nom de joint en dur.
  SPEC 3  collisions propres       -> projection hors des volumes ajustes sur le mesh, avec le
                                      PLANCHER DE POSE MODELE : un lien deja dans un volume au
                                      repos (une racine de cheveu sous le cuir chevelu) a le
                                      droit d'y etre, il n'a pas le droit d'aller PLUS PROFOND.
                                      C'est ce qui remplace le `colskip` retire.
  SPEC 7  ce qui fait foi          -> la position ECRITE du joint, mesuree ici meme.

REGLE 0 (owner) : un commentaire n'est pas une preuve. Tout ce que ce fichier PRETEND faire est
mesure par la salle de test (phys-room.gc) et publie dans keira-room-table.txt.
```

## [NOTE-120] SA §22 BORNE L'APEX, SA §21 SATURE LA COMBINAISON — LE MOTEUR BORNAIT LE MAILLON

Cycle 46. Ce que la borne rendait avant, mesure sur la course livree du cycle 45 (`ROOM-GRADIENT`,
angle du maillon de CHAIR, cinq pilotages dont le stimulus varie de x38.9) :

    chestL link1  16.6427  16.6450  16.6465  16.6483  16.6509     ecart total 0.049 %
    chestR link1  16.6705  16.6716  16.6744  16.6746  16.6786     ecart total 0.049 %
    sa propre demande, au meme instant : 37.51 -> 156.06 deg, soit x4.16

**Une constante a quatre decimales n'est pas une reponse, c'est la valeur d'une borne.** C'est la
lecture mecanique de « ca suit aucune logique » et de « un pudding sur lequel on tape au moindre
mouvement » : la sortie ne depend plus de l'entree.

CAUSE. `amax = 2*asin(0.50*B0 / (2*bl_RACINE))` etait derive de l'os de la RACINE (1040.5 u, le
levier, qui ne porte aucune chair) puis applique a TOUS les maillons. Sur l'os de chair (140.4 u)
le meme ANGLE ne vaut plus que `2*140.4*sin(amax/2)` = 40.6 u de deplacement, soit 0.0675 B0 —
**7.4 fois plus serre** que le 0.50 B0 que sa §22 accorde. Le facteur `rl` de NOTE-114 (borne
positionnelle) fait exactement la meme chose dans l'autre monnaie.

TROIS LIGNES DE SA SPEC DISENT L'AUTRE FORME :
  * §21 « `D_combined = D_max * tanh( |D_linear + D_angular| / D_max )` » — la saturation porte sur
    la COMBINAISON, donc UN facteur pour la somme, pas un ecretage par terme.
  * §22 « Distal/apex displacement: normal <=42% B0, exceptional <=50% B0 » — la grandeur bornee
    est celle de l'APEX, c'est-a-dire de la POINTE de la chaine, pas de chaque maillon pris a part.
  * §31 « little deformation at the root; progressively increasing mobility; largest displacement
    in distal tissue » — la mobilite CROIT vers la pointe. Un budget proportionnel a la longueur de
    l'os la fait DECROITRE, et NOTE-114 publie elle-meme cette reserve sans la lever.

**[EN PLACE. SON RETRAIT A ETE ESSAYE AU CYCLE 87 ET IL A COUTE — voir NOTE-471.]**
`phys-apex-scale` borne la POINTE, c'est-a-dire un JOINT, alors que §22 nomme un point de CHAIR
situe a 1,228 / 1,235 B0 de lui : c'est un PROXY, et le cycle 58 l'avait deja dit. Le cycle 87 en
a tire la conclusion qui semblait suivre — le retirer — et **la paire appariee a mesure que le
proxy est un MAJORANT PLUS STRICT que la grandeur qu'il approxime** : sans lui, apex moyen
0,6778 -> 0,7413 (chestL) et 0,7007 -> 0,7660 (chestR), `|tp|` median +17,5 % / +15,7 %.
Il reste donc EN PLACE. Un proxy ne se retire pas parce qu'il est un proxy ; il se retire quand
la mesure montre que ce qui le remplace fait mieux.

CORRECTIF. `phys-apex-scale` rend UN facteur `asc = ds/dd`, ou `dd` est la deviation ABSOLUE de la
pointe a sa pose d'auteur et `ds` le meme nombre sature au plafond `0.50*B0`. Chaque maillon voit
son DEPLACEMENT multiplie par ce facteur commun ; comme un maillon qui pivote de `a` autour de son
attache se deplace de `2*ml*sin(a/2)`, cela s'ecrit exactement `sin(a'/2) = asc*sin(a/2)`.
La rotation reste a longueur du MODELE (idiome NOTE-118, `ml` et jamais `dl`), donc rien ne
s'allonge, et la pointe herite du facteur au lieu d'un plafond.

**POURQUOI CA PEUT DISCRIMINER LA OU UN ECRETAGE NE LE PEUT PAS.** Un `fmin` rend la BORNE des que
la demande la depasse : au-dela, la sortie ne depend plus de l'entree. Un facteur commun rend
`asc * demande` : la sortie reste proportionnelle a la demande, et la REPARTITION entre les
maillons — qui, elle, varie avec le stimulus — survit a la saturation. C'est precisement ce que
« saturer la COMBINAISON » veut dire.

IDEMPOTENCE (NOTE-119, et la regle a ete violee deux fois). Le facteur est calcule UNE fois par
appel, avant la boucle sur les maillons. Sous le plafond il vaut EXACTEMENT 1.0, donc l'appel est
l'identite au bit pres — c'est la partie prouvee. Au-dessus, le mode DUR (`fmin`) vise le plafond
lui-meme, donc un second appel repart d'une pointe deja au plafond et ne retire plus rien au
premier ordre ; ce qui n'est PAS prouve, c'est l'absence d'erosion au SECOND ordre, due au
couplage sequentiel entre les deux maillons (le distal est mesure depuis un parent deja deplace).
Le test est publie et il est gratuit : si la sortie du distal reste plate a mieux que 5 % entre
les pilotages, c'est un POINT FIXE et pas une borne, et le correctif est retire.

PORTEE. Les chaines qui posent `maxangle=` dans la donnee (les meches, gelees depuis le
2026-08-14) sont INCHANGEES : elles gardent `fmin`/`phys-softmin` sur leur angle. Seule la
famille A sans cle passe au facteur d'apex. Et cela retire de la poitrine le mecanisme que
l'owner en avait explicitement exclu le 2026-08-11 22:35 (« l'attenuation pour eviter la geometrie
extreme c'est juste sur les meches, pas le reste, encore moins les seins ») : la borne d'angle
par maillon disparait de chestL/chestR, le budget de deplacement de sa §22 reste.

## [NOTE-122] DOCSTRING DE `phys-length-chain`, DEPLACEE DU SOURCE (cycle 46)

Texte integral, retire du source pour rendre de la marge sous le plafond de lignes de la
gate `CLEAN`. Pas une ligne de code n'a change avec ce deplacement.

LA CONTRAINTE DE LONGUEUR, DURE, ET LA MEME POUR LES DEUX FORMES DE LIEN.

   Owner, 5e passe : « les changements brusques de direction causent un truc chelou au niveau des
   seins, ils s'allongent, c'est un peu debile » — « une chaine a un seul os doit TOURNER AUTOUR DE
   SON ANCRE A LONGUEUR INVARIANTE, jamais se translater ni s'allonger ». Ce que faisait l'ancienne
   version pour un lien SEUL : elle bornait |p - pose_du_lien| par le rayon du lien. C'est un
   plafond de POSITION, pas une longueur — sous forte acceleration le lien s'ecartait de son ancre
   et la distance ancre->lien changeait, donc il S'ALLONGEAIT. Desormais un lien seul est traite
   exactement comme un lien de chaine, son attache etant l'ANCRE au lieu du lien precedent :
   projection sur la sphere de rayon `want`, ou `want` est la longueur que LE MODELE donne a cet os,
   relue chaque frame. Une egalite, pas un plafond : ca tourne, ca ne s'etire pas.

   Owner, 2e/3e/4e passes (trois fois) : « j'ai encore vu un de ses seins retourne vers l'interieur,
   la meme animation relancee et c'etait nickel ». Le ressort est symetrique autour de l'attache,
   donc le cote oppose est un equilibre STABLE mais FAUX. Le test de cote est donc ici, contre la
   DIRECTION DU MODELE — et plus contre l'axe d'un volume, ou il ne voulait rien dire (un volume est
   une coquille symetrique, son axe ne designe aucun « bon cote »).

   `*phys-len-off*` DESARME toute cette contrainte : voir la note de ce drapeau. Controle du
   cycle 8, actif sur les seules fenetres AXZ, 0 en livraison.

## [NOTE-121] PIERRE TOMBALE — LA MONOTONIE DE SPEC 31, POSEE, MESUREE, RETIREE

**A NE PAS REMETTRE SANS LIRE CE QUI SUIT.** Cycle 46, jambe 2. Elle a tourne une course complete
(31/31 animations) et elle est retiree parce qu'elle a **rate son propre but**, pas parce qu'elle
etait difficile.

CE QU'ELLE FAISAIT. Un maillon non-racine ne pouvait plus rebrousser la deviation de son parent :
`d_l . e_{l-1} >= 0`. Sur l'angle, avec `A = m^.e^` et `B = q^.e^` :
`d . e^ = ml*2 sin(a/2)*[B cos(a/2) - A sin(a/2)]`, donc plafond `amn = 2*atan(B/A)` quand `A > 0`.
Idempotent par construction (la rotation reste dans le plan `(m^, q^)`, donc `A` et `B` sont
inchanges), aucune constante neuve, racine et meches intouchees.

L'HYPOTHESE QU'ELLE TESTAIT, ET QUI EST MAINTENANT REFUTEE : « le distal tourne CONTRE son parent
(enveloppe pointe/racine 1.01-1.08 la ou sa §31 veut la plus grande excursion au distal), donc
c'est le REPLI qui met la pointe dans le tronc, donc l'interdire fera redescendre `meshpen` ».

    grandeur                        jambe 1        jambe 2        predit
    enveloppe pointe/racine         1.082 / 1.011  1.085 / 1.065  > 1.30        REFUTE
    `meshpen` chestL                0.1061         **0.1195**     < 0.1061      REFUTE (+12.6 %)
    `meshpen` chestR                0.0898         **0.0953**     < 0.0898      REFUTE (+6.1 %)
    `ROOM-SIDE` franchissements     8              6              0             REFUTE
    §27 `t1` chestR                 1.38 s         **1.75 s**     <= 1.7 s      REFUTE (hors bande)
    ecart du distal (l'acquis)      22.4 / 40.2 %  34.5 / 36.9 %  >= 20 %       tenue
    `tipvar`                        0.172 / 0.174  0.180 / 0.181  >= 0.160      tenue

**LA LECON, ET ELLE VAUT POUR LE PROCHAIN QUI Y PENSERA : sur cet organe, LA DIRECTION DU MAILLON
DISTAL N'EST PAS CE QUI COUTE LA PENETRATION.** Interdire le repli n'a quasiment pas bouge
l'enveloppe (1.082 -> 1.085) et a fait MONTER `meshpen`. Ce qui coute, c'est l'EXCURSION du maillon
libere, pas son signe. Toute future tentative de payer `meshpen` avec une contrainte de FORME doit
d'abord expliquer ce resultat-la.

DEUXIEME LECON, ECRITE AVANT LE RESULTAT (addendum `C46E2B`) : cette contrainte interdit aussi le
**RETARD**. Si le distal retarde, `p_l ~ pose_l` donc `d_l ~ -e_{l-1}` et le produit scalaire est
negatif — c'est la signature meme de l'inertie, et sa §19 la demande en toutes lettres (« breast
mass lags behind »), sa §23 la nomme (« angular lag »), et l'owner aussi (« ils restent en arriere
puis rattrapent »). **§31 decrit une FORME D'EQUILIBRE, §19/§23 un TRANSITOIRE ; les appliquer a la
meme echelle de temps confond les deux.** Mesure : `lag01` chestL 2 -> 0 (effondre) et chestR
-4 -> +7 (ameliore) — l'instrument ne tranche pas, mais la confusion d'echelles, elle, est reelle.
Si la monotonie revient un jour, elle doit porter sur une MOYENNE DE FENETRE, jamais sur la frame.

TROISIEME LECON, ET C'EST UN PIEGE DE CABLAGE : la premiere pose de cette contrainte etait NICHEE
sous `(< asc 1.0)`, le gate de la borne d'apex. Une course complete l'a rendue **INERTE** —
`PHYSGRAD` identique AU BIT PRES sur 744 lignes. Deux contraintes independantes ne se nichent pas
l'une dans l'autre. Le tell qui l'a trouvee est gratuit : comparer la trace, pas le raisonnement.

RETRAIT PROUVE PAR EMPREINTE, PAS AFFIRME : apres retrait, `GAME.CGO` recompile porte le md5
**34efc3f2fcf11704aad6a34642f5d5ea**, celui de la course de la jambe 1. L'etat livre EST l'etat
mesure.

## [NOTE-122] DOCSTRING DE `phys-length-chain`, DEPLACEE DU SOURCE (cycle 46)

Texte integral, retire du source pour rendre de la marge sous le plafond de lignes de la
gate `CLEAN`. Pas une ligne de code n'a change avec ce deplacement.

LA CONTRAINTE DE LONGUEUR, DURE, ET LA MEME POUR LES DEUX FORMES DE LIEN.

   Owner, 5e passe : « les changements brusques de direction causent un truc chelou au niveau des
   seins, ils s'allongent, c'est un peu debile » — « une chaine a un seul os doit TOURNER AUTOUR DE
   SON ANCRE A LONGUEUR INVARIANTE, jamais se translater ni s'allonger ». Ce que faisait l'ancienne
   version pour un lien SEUL : elle bornait |p - pose_du_lien| par le rayon du lien. C'est un
   plafond de POSITION, pas une longueur — sous forte acceleration le lien s'ecartait de son ancre
   et la distance ancre->lien changeait, donc il S'ALLONGEAIT. Desormais un lien seul est traite
   exactement comme un lien de chaine, son attache etant l'ANCRE au lieu du lien precedent :
   projection sur la sphere de rayon `want`, ou `want` est la longueur que LE MODELE donne a cet os,
   relue chaque frame. Une egalite, pas un plafond : ca tourne, ca ne s'etire pas.

   Owner, 2e/3e/4e passes (trois fois) : « j'ai encore vu un de ses seins retourne vers l'interieur,
   la meme animation relancee et c'etait nickel ». Le ressort est symetrique autour de l'attache,
   donc le cote oppose est un equilibre STABLE mais FAUX. Le test de cote est donc ici, contre la
   DIRECTION DU MODELE — et plus contre l'axe d'un volume, ou il ne voulait rien dire (un volume est
   une coquille symetrique, son axe ne designe aucun « bon cote »).

   `*phys-len-off*` DESARME toute cette contrainte : voir la note de ce drapeau. Controle du
   cycle 8, actif sur les seules fenetres AXZ, 0 en livraison.

## [NOTE-121] SPEC 31 : LA POINTE PROLONGE LA DEVIATION DE SON PARENT, ELLE NE LA REBROUSSE PAS

Cycle 46, jambe 2. La jambe 1 a remplace l'ecretage par maillon par un FACTEUR COMMUN derive du
budget d'APEX (NOTE-120) : la sortie du distal cesse d'etre une constante (0.05 % -> 22.40 % et
40.24 % d'ecart). **Prix mesure : `meshpen` +116 % / +186 %, et `ROOM-SIDE` 0 -> 8 frames.**

CE QUE LA MESURE DIT DE LA CAUSE, et ce n'est pas une amplitude (`PHYSGRAD amp`, enveloppe de
l'ecart a la pose d'auteur, repere ancre, unites de jeu) :

    chestL  l=0 391.87-651.18   l=1 423.62-704.56   pointe/racine 1.08
    chestR  l=0 409.75-704.26   l=1 420.36-711.98   pointe/racine 1.01

Le distal pivote de 79 a 102 deg — soit `2*140.4*sin(50 deg)` = **215 u** de deplacement de joint —
et n'ajoute que ~50 u a une enveloppe de 650-700 u. **Il tourne CONTRE la deviation de son parent
au lieu de la prolonger.** Sa §31 exige l'inverse en toutes lettres : « little deformation at the
root; progressively increasing mobility; **largest displacement in distal tissue** ».

**POURQUOI LA BORNE D'APEX NE PEUT PAS L'ATTRAPER, ET C'EST GENERAL.** Elle borne
`|e_racine + d_distal| <= 0.50 B0` : la NORME D'UNE SOMME, donc une grandeur AVEUGLE A LA
DIRECTION. Un repli ou `d_distal` annule `e_racine` tient dans le budget tout en mettant la pointe
dans le tronc. **Quand un limiteur porte sur la norme d'une somme, demander quelle configuration
rend la somme petite avec des termes grands ; si cette configuration est physiquement fausse, la
norme est le mauvais invariant et il faut une contrainte de FORME a cote, pas un plafond plus bas.**

LA CONTRAINTE, ET SON ECRITURE EXACTE. Un maillon qui pivote de `a` autour de son attache, dans le
plan `(m^, q^)`, se deplace de `d = ml*((cos a - 1) m^ + sin a q^)`. En notant `e^` la direction de
la deviation du PARENT, `A = m^.e^` et `B = q^.e^` :

    d . e^  =  ml * 2 sin(a/2) * [ B cos(a/2) - A sin(a/2) ]

Sur `a` dans (0, pi) le premier facteur est positif, donc `d.e^ >= 0` equivaut a
`tan(a/2) <= B/A` quand `A > 0`. Le plafond est donc **`amn = 2*atan(B/A)`**, et `0` quand `B <= 0`
(aucune rotation dans ce plan ne prolonge le parent).

CE QU'IL EST, ET CE QU'IL N'EST PAS :
  * **AUCUNE CONSTANTE NEUVE.** `A` et `B` sont deux produits scalaires de la frame courante.
  * **CE N'EST PAS UN PLAFOND FIXE** — `e^` varie avec le stimulus, donc `amn` aussi. C'est
    exactement ce qui le distingue du 16.63 deg qu'on vient de retirer, et ce qui l'empeche de
    reproduire la sortie constante.
  * **IDEMPOTENT, ET PAR CONSTRUCTION** (NOTE-119, regle violee deux fois) : la rotation reste dans
    le plan `(m^, q^)`, donc `A` et `B` sont inchanges apres application. Un second appel recalcule
    le MEME `amn` et `fmin` est alors l'identite. Point fixe exact, pas une erosion.
  * **LA RACINE N'EST PAS TOUCHEE** : son attache est l'ancre, qui n'est pas simulee, donc
    `e_{l-1} = 0` et la garde `(> l 0)` la laisse passer inchangee au bit pres.
  * **LES MECHES NE SONT PAS TOUCHEES** : la garde `apx?` ne selectionne que la famille A sans cle
    `maxangle=` dans la donnee.

CE QU'ELLE NE PRETEND PAS FAIRE : fermer `COLLIDE`. Meme ramenee a sa valeur d'avant le cycle 46,
la penetration resterait a 98x le plafond de 0.0005 m. Et elle ne touche pas le canal RADIAL du
distal, qui reste plat parce que le degre de liberte de sa §23 n'est arme que sur la racine.

## [NOTE-125] LE PAS TANGENTIEL CORRIGE : ESSAYE, MESURE, RETIRE (cycle 47)

Site : `phys-collide-chain`, bloc `(a1)`. Le pas LIVRE est celui de NOTE-61, inchange. Ce qui reste
du cycle 47, ce sont **trois sondes inertes sur la trajectoire** — elles lisent et accumulent, elles
n'ecrivent jamais `qx/qy/qz`.

### LA GEOMETRIE, QUI EST JUSTE, ET QUI N'A PAS SUFFI

`u^` = direction radiale attache -> joint. `nrm` = normale sortante du volume (unitaire).
`cn = nrm . u^`, `t = nrm - cn*u^`, `|t| = s`, et `t . nrm = 1 - cn^2 = s^2`.

Le pas livre avance de `dd * t`, donc ne retire que `dd * s^2` : il se paie son obliquite DEUX
fois. Le deplacement qui retire exactement `dd` en restant tangent est `(dd/s^2) * t`. C'est la
projection au premier ordre sur la **calotte** = (sphere de l'attache) INTER (complementaire du
volume) — les deux contraintes sur la MEME variete, exactement ce que le commentaire 4 du
validateur prescrit depuis le cycle 43.

**Ce correctif a ete ecrit, cuit et couru.** Il fait ce qu'il promet : le rendement passe de
**37.56 % a 73.57 %**, les contacts baissent de 11.5 % / 9.0 %, `ROOM-SIDE` tombe de 8 a 4, et
`tipvar` ne bouge pas (0.1720 -> 0.1718). **Et `meshpen` MONTE : 0.1061 -> 0.1160 et
0.0898 -> 0.1376 (+9.3 % / +53.2 %).** Le plafond epingle de `COLLIDE` dit « il ne peut que
DESCENDRE » : le pas est donc RETIRE, sur mesure, comme la jambe 2 du cycle 46.

### POURQUOI POUSSER MIEUX A EMPIRE LE RESIDU — LA MESURE LE DIT

    capn/n        = 489705 / 730541  = 67.0 %   des poussees ont une CALOTTE VIDE
    capdepth/sum  = 69122570 / 82114735 = 84.2 % de TOUTE la profondeur y vit
    capgive (max) = 4.0447                       soit +404 % de rayon

La calotte est vide quand `dd > en*(1-cn)` : **aucun deplacement a longueur constante ne sort le
joint**, quelle que soit la direction. 84 % de la profondeur est dans ce regime. Un pas plus fort
n'en sort donc pas le joint — il le fait **glisser le long de la surface jusque dans un volume
voisin**, et c'est ce que `meshpen` a lu.

### CE QUE CA REFUTE, ET C'EST UN CYCLE ECONOMISE

`capgive = 4.04` veut dire qu'il faudrait **quintupler la longueur du maillon** pour que la
contrainte de longueur et la contrainte de volume redeviennent compatibles. SPEC 22 pose
« Absolute stretch clamp: 25% ». **4.04 depasse ce clamp d'un facteur 16.** Donc la piste « la
longueur cede » (SPEC 33 « local compression ») — celle que le commentaire du validateur ET le
registre designaient comme la suite — est **REFUTEE AVANT D'ETRE ECRITE**. Elle ne peut pas fermer
`COLLIDE`, et aucune borne admissible par la spec ne le peut.

### CE QUE LES SONDES DISENT, ET POURQUOI ELLES RESTENT

  * `oldremoved` = ce que le pas CORRIGE retirerait, mesure SANS l'appliquer. Le jour ou la
    geometrie change, on verra immediatement si la situation a bouge, sans re-ecrire le pas.
  * `capn` / `capdepth` / `capgive` = la taille du regime ou aucune reponse de contact locale ne
    peut rien. C'est la grandeur qui designe le vrai chantier.

### LE CHANTIER QUE CETTE MESURE DESIGNE

Le joint distal est plus PROFOND dans le volume que le maillon n'est LONG (`dd` moyen 112 u sur un
os de chair de 140.4 u, et jusqu'a 5x). Aucune reponse de contact ne peut corriger ca : ce n'est pas
la finition qui met le joint la, c'est **l'EXCURSION du maillon RACINE** (levier de 1040.5 u,
enveloppe 391-704 u) qui l'y transporte. Le cycle 46 l'avait deja conclu par une autre voie
(« ce n'est pas la DIRECTION du distal, c'est son EXCURSION ») ; le cycle 47 le mesure par la
geometrie du contact lui-meme. Les deux voies convergent, et c'est le levier, pas le contact.


## NOTE-131  (moteur, aux alentours de la ligne 3465)

L'ANIMATION EST-ELLE PASSEE INTACTE ? La position ecrite
doit valoir la pose d'AUTEUR + l'ecart simule, sans que le
second n'ampute le premier : dans le repere de l'ancre cela
s'ecrit s == u + o, et l'ecart mesure ici est
|s - u - o|. Il vaut zero quand l'animation traverse a
coefficient 1 et NE PEUT PAS valoir zero si quoi que ce
soit la met a l'echelle, la mixe ou la retarde — c'est ce
que le controle positif (*phys-auth-lag*) verifie en
retardant l'animation d'une frame.


## NOTE-130  (moteur, aux alentours de la ligne 3396)

L'INSTRUMENT DE MESURE EST L'INSTRUMENT DE DECISION : le
solveur ne corrige le cote QUE sur le PREMIER LIEN LIBRE, celui
dont l'attache est rigide, donc la mesure ne le compte que la.
Compter les liens profonds donnait 24 117 « inversions
residuelles » que rien ne corrigeait et que rien n'avait
demande de corriger — un chiffre sans decision derriere.
Le predicat suit celui du solveur (`l = rlk`, corrige le
2026-08-12) : sur les chaines rootlockees `l = 0` n'etait
jamais visite, donc les deux lisaient zero par construction.


## NOTE-129  (moteur, aux alentours de la ligne 3356)

LA MEME DEVIATION, PROJETEE SUR LE TRIEDRE DE L'ANCRE
(SPEC 24, voir la note de `*phys-lda*`). Meme instant,
meme grandeur, meme ligne de base : c'est le MEME vecteur
lu dans une autre base, pas une seconde mesure qui
pourrait contredire la premiere. L'ordre publie est
(v, ap, lat) — celui de SPEC 24 — et non l'ordre des
lignes de la matrice, qui ne veut rien dire hors du rig.
Chaine non classee : la serie reste a 0 et l'outil ecrit
`insufficient-excitation`, jamais un repli.


## NOTE-132  (moteur, aux alentours de la ligne 2896)

---- SPEC 23, LE MEME SOUS-PAS, LE POINT LIBRE -----------
Il s'integre DANS la boucle de sous-pas, donc a la meme
frequence effective que l'apex (§37 : `ns` = 4 sur cette
chaine, soit 240 Hz). L'integrer dehors lui donnerait
60 Hz et sa §37 serait fausse pour lui seul.
MEME CIBLE, MEME RAIDEUR ANISOTROPE, MEME TRAINEE, MEME
PILOTAGE que l'apex : le seul terme qui differe est la
bande de saturation (§22 donne 0.35/0.40 B0 au COM et
0.42/0.50 B0 a l'apex), et l'absence de projection.


## NOTE-133  (moteur, aux alentours de la ligne 2808)

ET LA TRAINEE SUIT LA RAIDEUR, AXE PAR AXE : sur un axe
le TAUX doit aller comme `sqrt(k)` pour que
`zeta = taux/(2 sqrt(k))` reste la constante de MATERIAU
que SPEC 25 fixe a 0.35. Sans ca, l'anisotropie de
raideur ferait deriver `zeta` a 0.332 (AP) et 0.317
(lateral) — ce dernier SOUS le plancher 0.32 de sa plage.
La mise a l'echelle porte sur le TAUX, pas sur `1 - kd` :
c'est le taux qui est proportionnel a `sqrt(k)`, et la
retention en est l'exponentielle (NOTE-50).


## NOTE-134  (moteur, aux alentours de la ligne 2773)

---- SPEC 24 / SPEC 29 : LE TRIEDRE DE L'ANCRE ---------
Les trois lignes de `am`, RENORMALISEES — la matrice d'un
os retargete n'est pas garantie orthonormale, et une base
non unitaire ferait entrer l'echelle de l'os dans la
raideur (exactement le piege deja paye sur `gl`).
Elles sont relues sur la matrice COURANTE a chaque frame :
le triedre tourne donc avec le torse sans etre reclasse,
ce que SPEC 7 impose (« relative to the torso/root
transform rather than directly in world space »).


## NOTE-135  (moteur, aux alentours de la ligne 2438)

LATERAL D'ABORD, et c'est le renversement du cycle 10 : c'est le
segment INTER-SEINS qui designe une ligne, et l'avant-arriere est
« celle qui reste ». Le repli (chaine seule, pas de partenaire) lit
la protrusion propre de l'organe et la nomme LATERALE elle aussi :
la racine d'un sein est decalee lateralement par rapport au sternum,
mesure sur le rig a (+356, -898, -146) u en repere `chest`, donc
parmi les deux lignes non verticales c'est bien le lateral qui
domine (13.3 % contre 2.2 %). Les deux regles rendent donc le meme
verdict ici, et `*phys-axsrc*` dit laquelle a tranche.

## NOTE-126  (moteur, `*phys-comw*` et sa lecture dans `jak-hd-physics-init` — CYCLE 48)

**`comw=` EST LA PART DE MASSE DE PEAU DE CHAQUE MAILLON, ET C'EST UN PARAMETRE D'INSTRUMENT.**

Rien dans le solveur ne la lit : elle n'entre dans aucune force, aucune contrainte, aucune
collision. Elle sert exclusivement a former le CENTRE DE MASSE que sa §22 borne.

Sa §6, mot pour mot : « `P0` neutral breast center-of-mass position ».
Sa §22, mot pour mot : « Breast COM:              normal <=35% B0, hard transient <=40% B0 ».

**UN CENTRE DE MASSE EST UNE MOYENNE PONDEREE PAR LA MASSE.** Ce que le moteur publiait sous ce nom
(`comex`) est un MAXIMUM SUR DEUX CENTROIDES DE MAILLON — NOTE-112 le documente depuis le cycle 41,
mais la ligne de VERDICT n'avait jamais ete rebranchee sur la recomposition. L'arbitrage des
DIRECTIVES du 2026-08-19 23:50 autorise ce rebranchement a trois conditions (course de controle ;
la ligne publie borne superieure + moyenne + part au-dessus du plafond dur ; le nom dit ce qu'il
mesure).

**L'IDENTITE, QUI EST EXACTE SOUS SKINNING LINEAIRE.** Le deplacement d'un sommet est la somme
ponderee des deplacements de ses joints, donc sur le nuage de chair :

    d_COM = (1/N) * SOMME_j W_j * (M_j^sim - M_j^auth) * c_j

    W_j = somme des poids de peau du joint j        c_j = (SOMME_v w_jv v_bind) / W_j
    N   = SOMME_v SOMME_j w_jv                      comw[l] = W_l / N

Un joint NON simule a `M^sim == M^auth` : il contribue EXACTEMENT zero. C'est pourquoi la chair
ANCREE (`chest` 45.57 % / 45.33 %, `?shoulder` 0.28 % / 0.73 %) n'est pas dans la liste et pourquoi
les poids livres somment volontairement a 0.5415 / 0.5394 et non a 1. Cette moitie de la masse ne
peut pas entrer dans un MAXIMUM ; elle entre dans une MOYENNE, et elle la divise presque par deux.

**VERIFIEE, PAS SUPPOSEE** (`.autoport/probe_c48_com_identity.py`, mesh LIVRE
`out/jak1/fr3/skin/keira-hd-lod0.glb` md5 `5cb8a493c43211acf3a04c5b6433df81`) : somme des poids par
sommet = 1.0 a 4.47e-08 pres sur 7963 sommets, 0 poids negatif ; et sur une pose simulee tiree au
sort, le COM du nuage par skinning lineaire EXACT contre la formule differe de 2.1e-05 % (chestL) et
1.1e-05 % (chestR), pour un eps float32 de 1.2e-05 %.

**LA FRONTIERE DE L'ORGANE EST UN CHOIX, ET IL EST DECLARE PARCE QU'IL DEPLACE LE CHIFFRE.**
Retenue : `w > 0` — un centre de masse integre TOUTE la masse, un seuil en jetterait. A `w >= 0.25`
la part ancree tombe de 45.85/46.06 % a 34.52/34.90 % (11 points) et les poids deviendraient
0.2146,0.4402 / 0.2542,0.3968, donc un COM PLUS GRAND. Le seuil retenu n'est donc PAS celui qui
flatte la borne, et le tableau publie la borne superieure AUX DEUX frontieres pour que la
sensibilite reste lisible au lieu d'etre un choix cache.

**POURQUOI CETTE DONNEE VIT DANS `keira-owner-tuning.txt` ET PAS DANS LE GENERATEUR.** Meme raison
que `b0=` : elle se mesure sur le maillage LIVRE, qui n'existe qu'apres le bake, alors que
`physics_keira_gen2.py` lit le DONNEUR. Le jour ou le generateur lira le maillage livre, c'est lui
qui emettra `comw=`.

**RESERVE DECLAREE ET BORNEE.** Le moteur applique l'excursion au centre de la SPHERE DE COLLISION
(`offset=`, `jak-hd-physics.gc` : `*phys-lcx*` <- `*phys-cox*`), pas a `c_j`. Ecart vectoriel mesure
97.5 u / 17.3 u (chestL) et 87.4 u / 20.4 u (chestR). Report sur le COM borne par
`SOMME_l w_l (2 sin(th_l/2) + |T-I|) |lc_l - c_l|` <= 0.0285 / 0.0301 B0, soit 8.1 % / 8.6 % de la
bande de 0.35, DANS UN SENS INCONNU. Le corriger demande un canal VECTORIEL `comc=` ; il ne sera
ouvert que si un chiffre atterrit a moins de cette borne d'un seuil de la spec.

## NOTE-127  (moteur, etape 6 de `jak-hd-physics-step`, emplacements 43-46 — CYCLE 48)

**LE COM SE FORME VECTORIELLEMENT ET DANS LA MEME FRAME, SINON CE N'EST PAS UN COM.**

L'accumulateur (`cwx/cwy/cwz/cwn`) est ouvert JUSTE AVANT la boucle par maillon de l'etape 6 et
vide JUSTE APRES : sa portee est exactement UNE FRAME d'UNE chaine. C'est ce qui evite les deux
pieges qui rendaient toute recomposition a posteriori inexacte :

  1. **L'INEGALITE TRIANGULAIRE.** Recomposer `|SOMME_l w_l e_l|` a partir des NORMES `|e_l|` rend
     une BORNE SUPERIEURE, jamais la valeur — elle n'est serree que si les excursions sont
     colineaires. Ici on somme les VECTEURS, donc il n'y a pas de reserve a poser.
  2. **DEUX MAXIMA DE DEUX FRAMES DIFFERENTES.** Les emplacements 35-42 sont des maxima PAR
     MAILLON : rien ne garantit qu'ils sont atteints a la meme frame. Les additionner melange deux
     instants (meme piege que `RAD-FLESH-IPAIR`, cycle 34). L'accumulateur ne peut pas le faire :
     il n'a acces qu'a la frame courante.

**EMPLACEMENTS.** 43 = maximum de la fenetre · 44 = somme sur les frames · 45 = compte de frames ·
46 = compte de frames au-dessus du plafond dur de 0.40 B0. Les quatre ont la portee d'une FENETRE
(chaine, animation, pilotage) et sont balayes par `phys-comexw-reset!`, dont le `dotimes` passe de
20 a 24 pour les couvrir — c'est le seul endroit a tenir a jour, et NOTE-112 explique pourquoi il
est ecrit comme un balayage et non comme une enumeration.

**TOUS LES MAILLONS, OU AUCUN CHIFFRE.** La publication est gardee par `(= cwn n)`. Un maillon dont
le poids est absent, ou dont le joint n'existe pas sur ce rig, fait donc DISPARAITRE la ligne au
lieu de produire un COM ampute qui se lirait comme un COM sain plus petit. Un poids manquant ne
doit jamais se lire comme un centre de masse immobile — c'est la forme locale de la regle « tout
zero exige un controle positif ».

**LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000** — a la pose d'auteur, `M^sim == M^auth` sur tous les
maillons, donc chaque `e_l` est nul et la somme ponderee aussi.

## NOTE-136  (moteur, dans le bloc du COM pondere, aux alentours de la ligne 3975) — LE VECTEUR DU COM

```
---------------------------------------------------------------------------
POURQUOI UNE NORME NE SUFFIT PAS, ET CE QUE CA A BLOQUE.

L'emplacement 43 porte |d_COM| / B0 : une LONGUEUR. Elle repond aux sections
qui bornent une amplitude (SPEC 22, SPEC 14, SPEC 16, SPEC 17, SPEC 18,
SPEC 20) et elle est AVEUGLE a tout ce qui parle d'une DIRECTION. Or cinq
sections de sa spec en parlent, et l'une d'elles ne parle QUE de ca :

  SPEC 14 « upward torso acceleration -> breast downward lag »
  SPEC 15 « jump apex -> breast may CROSS NEUTRAL position »
  SPEC 17 « Braking produces the corresponding OPPOSITE response »
  SPEC 19 « the authored standing geometry IS CROSSED »
  SPEC 10 « COM toward thorax »

Une norme est positive par construction : un sein qui traverse le neutre et
un sein qui ne le traverse pas rendent la MEME norme. Mesurer SPEC 15 sur 43
seule aurait ete la mesure non discriminante que le contrat interdit — meme
famille que « une variance pour un affaissement sous gravite ».

CE QUI EST STOCKE : les trois composantes de (cwx, cwy, cwz) / B0, latchees
DANS LE MEME `when` que le maximum de 43, donc a l'ARGMAX de la norme et sur
UNE SEULE frame. Trois maxima independants auraient recompose un vecteur qui
n'existe dans aucune frame — c'est le piege `RAD-FLESH-IPAIR` du cycle 34.

REPERE : MONDE, et c'est un choix, pas une facilite. Le triedre de SPEC 7
(`phys-tri-world`) vit en espace ANCRE ; `*phys-axw*` vit en monde mais son
SIGNE n'a jamais ete mesure (NOTE-51). Croiser un vecteur monde avec le
premier serait le melange de reperes que NOTE-51 documente ; se fier au signe
du second serait `axis-sign-outlives-role-naming`. En monde, le signe est
decide par une chose qu'on sait : pendant les regimes de translation de la
salle (SPEC 14 a 17) le sujet est a QUATERNION IDENTITE, donc +Y monde EST la
verticale du personnage. Le lecteur qui interprete `cy` sur une fenetre OU LE
SUJET EST INCLINE lit un melange d'axes, et le tableau le dit au lieu de le
cacher.

PORTEE : la FENETRE. Les trois emplacements sont dans la tranche contigue
23-49 que `phys-comexw-reset!` efface en entier — la docstring de cette
fonction dit pourquoi enumerer les emplacements un par un etait le vrai
risque, et le `dotimes` a ete elargi de 24 a 27 dans le meme geste.
---------------------------------------------------------------------------
```

## NOTE-138  (moteur, dans le melange de forme de SPEC 10-13, aux alentours de la ligne 3511) — SPEC 12, LE COTE

```
---------------------------------------------------------------------------
CE QUE SA SPEC 12 EXIGE, MOT POUR MOT (l.189-190) :

  « The breasts shall NOT behave identically. The gravity-side breast
    experiences stronger thoracic compression, while the opposite breast
    migrates across the chest. »

CE QUI ETAIT ECRIT : `(wlt (fabs gxc))`. La valeur absolue rendait le meme
poids lateral aux deux SIGNES de gravite laterale, donc le meme triplet aux
deux poses. Mesure : `sx` = 0.8240 / 0.8212 aux deux poles, 0.34 % d'ecart.

ET RETIRER LE `fabs` N'AURAIT PAS SUFFI — c'est le fait qui a coute la
verification, et il est publie dans la trace. `PHYSAXW` et `PHYSTRI` sont
IDENTIQUES sur les deux chaines : elles partagent l'ancre `chest`, donc elles
partagent son triedre, donc `gxc` est LE MEME NOMBRE pour chestL et chestR.
Un poids signe aurait distingue « couchee sur le cote gauche » de « couchee
sur le cote droit » et aurait continue a donner LE MEME TRIPLET AUX DEUX
SEINS. Or la clause porte sur les deux SEINS, pas sur les deux poses.

CE QUI DISCRIMINE LES DEUX CHAINES EXISTE DEJA, MESURE ET PUBLIE :
`*phys-axsep*` slot 0 (`PHYSAXNAME sja`) vaut +754.9434 sur chestL et
-754.9434 sur chestR — meme module, signe oppose. C'est la separation de la
chaine le long de la ligne laterale : c'est le COTE.

    gxs = gxc * signe(sja)     la gravite VUE DU COTE DE CETTE CHAINE
    wlt = max(0,  gxs)         cote gravite  -> 0.800 / 1.118 / 1.118
    wne = max(0, -gxs)         cote oppose   -> 1.000 / 1.000 / 1.000

POURQUOI `wne` EXISTE, ET CE N'EST PAS UN ORNEMENT. Sans lui, le sein oppose
perdrait TOUT poids a gravite purement laterale : `wsm` tomberait sur son
plancher de 0.0001 et les trois echelles partiraient a zero. La partition
reste unitaire et le sein oppose cesse simplement de s'aplatir.

AUCUN CHIFFRE N'EST INVENTE, ET C'EST DELIBERE. 0.800/1.118/1.118 est le
triplet lateral deja livre ; 1.000/1.000/1.000 est le pole debout deja livre.
Le correctif ne fait que choisir LEQUEL des deux recoit le poids. Sa §12 ne
donne d'ECHELLE qu'au cote gravite (« Gravity-side lateral flattening: -15 to
-25%, nominal -20% ») ; pour le sein oppose elle donne une MIGRATION (« medial
migration: 10-18% W0 »), c'est-a-dire une translation, que la dynamique
produit deja par `gl`. Inventer un triplet pour le cote oppose aurait ete la
faute de la x5.2 : deduire un chiffre d'une ligne que la spec ne contient pas.

CE QUE CE CORRECTIF NE FAIT PAS : il ne rend pas §12 TENUE. Sa clause chiffree
« Global lateral COM response: 15-24% B0 » reste encadree par deux bornes qui
ne se rejoignent pas, et « medial migration 10-18% W0 » reste sans instrument
parce que `W0` n'est mesure nulle part.

CONTROLE : debout, `gl = 0` donc `gxc = 0` EXACTEMENT (le garde
`(> gnn 0.0001)` met `ivg` a zero), donc `wlt = wne = 0` et le melange est
identique a `fabs(0)`. Les fenetres de regime a quaternion identite doivent
donc rester IDENTIQUES AU BIT — c'est la prediction P1 de C50E1.
---------------------------------------------------------------------------
```

---------------------------------------------------------------------------
## NOTE-139  (moteur : declarations ~line 133, `phys-pt-exc!`, le remplissage de l'init, le bloc
## d'ecriture ~line 3890 et la publication ~line 4000) — L'APEX, ET LES DEUX EXTREMES DE SPEC 15

**LE TROU QUE CE CANAL COMBLE.** Sept sections de `SPEC-breast-softbody.md` bornent un
deplacement d'APEX en % B0 — §14 (« Apex displacement: ordinary 20-30% B0, strong 30-38% B0 »),
§16 (« Strong landing apex: 30-42% B0 » / « Very hard / exceptional: 42-50% B0 »), §17
(« Apex displacement: strong 25-35% B0, upper transient ~40% B0 »), §18 (« Apex displacement:
strong 20-30% B0, exceptional ~35% B0 »), §19 (« 30-40% B0 apex displacement without requiring
comparable local stretch »), §20 (« apex 20-30% B0 ») et §22 (« Distal/apex displacement: normal
<=42% B0, exceptional <=50% B0 ») — et **aucun canal de la salle ne publiait un apex**. §19 n'a
meme que cette clause : son COM etait mesure et ne repondait a aucune de ses lignes. Six sections
ne pouvaient pas etre fermees, dans un sens ou dans l'autre, tant que ce canal n'existait pas.

**CE QUE L'APEX EST ICI, ET CE N'EST PAS UN SOMMET.** §22 ecrit « **Distal/apex** displacement »
et §31 « r = 1 at distal/apex **region** » : la spec nomme une REGION. La region retenue est le
**decile distal** du nuage de chair le long de l'axe anatomique racine->apex (`APEX_FRAC = 0.10`
dans `.autoport/physics_c14_meshsamples.py`). Un sommet unique serait un extremum de maillage,
sensible au bruit de triangulation ; un decile est une statistique. **La fraction est FIXEE AVANT
toute course** et ne se choisit pas au vu du verdict — les variantes 0.05 et 0.25 sont mesurees et
publiees dans `mesh_extents_c14.txt` A COTE, meme discipline que la frontiere `w>0` / `w>=0.25` du
bloc COM.

**L'ALGEBRE EST EXACTE, PAS UNE APPROXIMATION.** Sous skinning lineaire un sommet vaut
`SOMME_j w_ij M_j v_i`, donc le centroide de masse de la region se deplace de

    d_apex = SOMME_l w_l * (M_l^sim - M_l^auth) * p_l

    w_l = (SOMME_{i dans R} w_il) / |R|        p_l = (SOMME_{i dans R} w_il v_i) / SOMME w_il

`v_i` etant le sommet en espace bind du maillon l. C'est la MEME identite que `comw=` (NOTE-126),
appliquee a une SOUS-POPULATION au lieu du nuage entier. Les joints non simules ont
`M^sim == M^auth` et contribuent EXACTEMENT zero : ils disparaissent de la somme, et c'est
pourquoi les poids livres somment a MOINS de 1.

**LE CHIFFRE QUI BORNE TOUT LE RESTE, ET IL N'EST PAS UN REGLAGE.** Mesure sur le mesh LIVRE
(`out/jak1/fr3/skin/keira-hd-lod0.glb`, md5 `5cb8a493c43211acf3a04c5b6433df81`), la composition de
la masse de peau de la region distale :

    chestL   chest 43.24 %  ANCRE      lBoob 40.95 %      lBooc 15.80 %     -> somme simulee 0.5676
    chestR   chest 40.64 %  ANCRE      rBoob 45.27 %      rBooc 14.09 %     -> somme simulee 0.5936

**41 a 43 % de l'apex est soude au torse**, sur `chest`, qui n'est pas simule et dont la matrice
ecrite EST sa matrice d'auteur. Le deplacement d'apex que le moteur peut produire est donc
PLAFONNE a 0.5676 / 0.5936 de ce que ses maillons simules produisent, **quelle que soit la
physique**. Sa §30 ecrit « Apex — minimal direct anchoring » : c'est le contraire de ce que le
mesh livre porte, et c'est le meme profil d'ancrage en U deja au dossier. Aucun reglage de
raideur, d'amortissement ou de gravite ne peut lever ce plafond ; seule une repesee le peut.

**LA GEOMETRIE, ET UNE DIVERGENCE QUE JE NE TRANCHE PAS.** L'axe employe est celui de
`probe_c48_com_identity.py:337-344` — du joint racine vers le centroide de l'organe pondere par
le poids de chaine — parce que c'est LUI qui produit le `b0=602` livre (etendue mesuree du nuage
sur cet axe : 597.9 / 598.3 u = 0.99 B0). **Une autre definition existe dans le depot et ne
s'accorde pas** : `probe_breast_chain_span.py` rend 734.2 / 766.6 u pour la meme grandeur. Le
choix est declare ici ; le trancher demande un invariant anatomique, pas un raisonnement de plus
sur les memes nombres.

L'echelle de bind des quatre joints de poitrine vaut **1.000000 exactement sur les trois valeurs
singulieres** (MESURE, pas suppose) : les deux conventions de `to_bone_local` du depot — celle de
`physics_c14_meshsamples.py:130` qui garde l'echelle et celle de `probe_c48:62` qui la retire —
coincident donc ici, et le choix de l'une ou l'autre ne peut pas biaiser le resultat.

**NATURE / REPERE / LECTURE HORS DEFAUT.**
  `phys-pt-exc!` : NATURE trois longueurs SIGNEES en unites de jeu · REPERE MONDE, meme frame,
  pose ECRITE `bm` (deformation comprise, c'est le meme `bm` que l'ecriture livre au squelette,
  donc le meme point que l'owner voit) CONTRE la pose d'auteur `pre` · A LA POSE D'AUTEUR 0.0.
  C'est la MEME formule que le bloc `lc` de l'ecriture ; elle est ecrite une fois et le bloc `lc`
  n'a PAS ete refactorise pour l'appeler, exprès : ce cycle depense son controle de bit-identite
  sur la trace entiere, et deplacer une expression flottante qui alimente `comex`, `ee`, `jt` et
  le COM pour economiser des lignes aurait mis ce controle en jeu contre rien.

  emplacements 53-56 : 53 = |d_apex| / B0, MAXIMUM DE FENETRE ; 54/55/56 = les trois composantes
  SIGNEES du meme vecteur, relevees A L'ARGMAX de 53, donc les trois ensemble et sur UNE frame —
  jamais trois maxima separes (piege `RAD-FLESH-IPAIR`, cycle 34).

  La garde de publication est `awn > 0` et NON `awn = n`, contrairement au COM : un maillon sans
  part de la region distale (`ax` a w=0) n'a rien a apporter et ne doit pas supprimer la mesure,
  la ou un `comw` manquant fausserait une MOYENNE.

**LES DEUX EXTREMES VERTICAUX (emplacements 57/58) — SPEC 15.** Sa §15 : « jump apex -> breast may
**cross neutral position** ». Le registre portait la clause NON DEMONTREE avec la raison exacte :
le vecteur du COM est releve a l'ARGMAX de sa norme, c'est-a-dire UNE frame, ce qui n'etablit ni
la presence ni l'absence d'une traversee. Il faut les deux extremes de la composante verticale
SIGNEE sur la fenetre.

**ET CE SONT DEUX MAXIMA, JAMAIS UN MIN ET UN MAX.** Le reset de fenetre met les emplacements a
0.0. Un MINIMUM initialise a 0.0 ne peut pas remonter au-dessus de 0 : sur une fenetre
entierement positive il LIRAIT 0 et annoncerait un passage par le neutre qui n'a pas eu lieu —
un faux vert sur la seule clause que §15 rend verifiable. D'ou : 57 = max(-cy)/B0 (le plus BAS
atteint, en positif), 58 = max(+cy)/B0 (le plus HAUT). La traversee exige les DEUX strictement
positifs, et « jamais vu » se lit 0.0000 sur l'un des deux.

**LA DONNEE.** `ax <chaine> <maillon> <w> <x> <y> <z>` dans `recharged_assets/physics_mesh.txt`,
emise par `.autoport/physics_c14_meshsamples.py` — le meme producteur, le meme fichier et le meme
mesh que les enregistrements `ms` de SPEC 18. Elle ne passe PAS par `physics_chains.txt` : ce
fichier porte les reglages de l'owner, une regeneration les a deja effaces deux fois, et une
mesure derivee n'a rien a y faire. Le C++ la parse a cote du bloc `ms` et publie
`apex-links=` / `apex-dropped=` dans sa ligne `[hd-phys] MESHSRC=` : sans ce compteur, un `ax`
ignore serait invisible et le canal serait INERTE en se lisant comme un apex nul.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
## NOTE-140  (moteur, aux alentours de la ligne 3543) — SPEC 8 — LE DETERMINANT DES TROIS ECHELLES

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
                                 ;; (c) SPEC 8 — `Sx.Sy.Sz = 1`. Les triplets de sa spec sont des
                                 ;; BOITES ENGLOBANTES et elle le dit (« the volume constraint
                                 ;; applies to the actual deformable volume, NOT merely to the
                                 ;; bounding-box dimensions quoted below ») : celui de §10 vaut
                                 ;; 0.938. On garde donc ses RAPPORTS de forme et on ramene le
                                 ;; determinant a 1 — les trois valeurs restent dans ses bandes
                                 ;; (supine 0.715 / 1.256 / 1.113 contre -25..-35 %, +18..+28 %,
                                 ;; +5..+12 %). Racine cubique par deux pas de Newton, l'entree
                                 ;; etant toujours proche de 1.
```

---------------------------------------------------------------------------
## NOTE-141  (moteur, aux alentours de la ligne 2643) — LA PART DE LA GRAVITE QUE LA GEOMETRIE AUTORISE

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
                               ;; ET LA PART DE CETTE GRAVITE QUE LA GEOMETRIE AUTORISE. La
                               ;; contrainte de longueur n'admet qu'une ROTATION autour de
                               ;; l'attache : la composante de la gravite dirigee dans l'axe de l'os
                               ;; ne peut produire aucun deplacement. Une chaine dont la gravite est
                               ;; presque radiale ne s'affaissera JAMAIS, quel que soit le reglage —
                               ;; c'est une propriete du rig, pas un bug, et sans ce nombre publie
                               ;; les deux sont indiscernables. (Instrument inchange : il se lit sur
                               ;; `gl`, le meme vecteur qu'avant.)
```

---------------------------------------------------------------------------
## NOTE-142  (moteur, aux alentours de la ligne 1844) — UNE SEULE PASSE SUR LES VOLUMES, DEUX CORRECTIONS

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
              ;; --- (a) UNE SEULE PASSE SUR LES VOLUMES, DEUX CORRECTIONS.
              ;; La mise en place d'un volume (`phys-col-now!`, `phys-col-rest!`, les trois
              ;; profondeurs) coute le meme prix pour le franchissement de cote et pour la
              ;; profondeur : la faire DEUX fois doublait le cout de la boucle de finition et la
              ;; course de la salle ne tenait plus dans son delai. Une passe, deux consommateurs.
              ;; Le test de cote garde son propre interrupteur (`*phys-side-off*`) et son propre
              ;; predicat d'exclusion (`phys-col-own?` NON leve par `self-inject`), exactement
              ;; comme avant : c'est un partage de calcul, pas une fusion de semantiques.
```

---------------------------------------------------------------------------
## NOTE-143  (moteur, aux alentours de la ligne 1764) — SPEC 33/34 — ON NE FAIT QUE CUMULER ICI

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
                            ;; SPEC 33/34 — ON NE FAIT QUE CUMULER ICI. La poussee est appliquee a
                            ;; la POSITION comme avant (rien de change pour la regle 6 : le lien
                            ;; sort du volume) ; ce qui manquait est son effet sur la VITESSE, et il
                            ;; ne peut pas etre traite dans cette fonction, appelee 15 fois par
                            ;; frame. `e` est celui du volume qui pousse : 0.06 si ce volume est
                            ;; porte par un joint SIMULE (l'autre sein, sa §33), 0.02 sinon (buste
                            ;; et externe, sa §34). Le dernier qui pousse decide, comme pour
                            ;; l'arbitrage de volume.
```

---------------------------------------------------------------------------
## NOTE-144  (moteur, aux alentours de la ligne 544) — SPEC 21 SOUS SA FORME DE FORCE — COMBIEN DE SOUS-PAS

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
;; SPEC 21 SOUS SA FORME DE FORCE (le RESSORT QUI RAIDIT, 2026-08-14). Combien de SOUS-PAS ont ete
;; integres au-dela du genou de SPEC 22, donc avec un facteur de raideur > 1.
;;   NATURE : un COMPTE d'evenements (sous-pas), pas une longueur.
;;   REPERE : sans objet — c'est un compte.
;;   LECTURE QUAND LE DEFAUT EST ABSENT : 0 exactement. Sous 0.42 B0 le facteur vaut 1.0 et la garde
;;            `(> dd kn)` ne s'ouvre pas : le regime subtil que l'owner a valide n'incremente rien.
;; CE N'EST PAS UN SUPPRESSEUR ET IL N'A PAS DE `sum` : une force ne retire pas d'energie, elle la
;; rend. Ce qui en retire, c'est le plafond POSITIONNEL, et lui garde ses deux compteurs ci-dessus.
```

---------------------------------------------------------------------------
## NOTE-145  (moteur, aux alentours de la ligne 4201) — LE MOUVEMENT PROPRE D UN MAILLON, EN DEGRES

Texte DEPLACE VERBATIM depuis `jak-hd-physics.gc` au cycle 51, sans une virgule
changee. Le moteur porte un pointeur a sa place. La raison est le plafond de
lignes de la gate CLEAN (4800), que le contrat GELE et que je ne touche pas : le
canal APEX est de la MESURE, pas un suppresseur, et cette prose vit aussi bien
ici — c est la convention du fichier depuis 174 pointeurs.

```
;; LE MOUVEMENT PROPRE D'UN MAILLON, en DEGRES : sa deviation angulaire par rapport a SON ATTACHE.
;; 10e passe de l'owner : « le milieu est plus hysterique (bouge beaucoup plus) que les pointes,
;; c'est pas cense ! » — pendant que `phys-link-amp` publiait une suite croissante. Les deux ne
;; mesurent pas la meme chose : `phys-link-amp` est un ecart a la pose d'auteur, donc il CUMULE le
;; long de la chaine et une pointe soudee a son parent y affiche le chiffre de son parent. Celle-ci
;; est relative au parent par construction et vaut zero pour un maillon qui ne bouge pas tout seul.
;; Les deux sont publiees cote a cote : leur ecart EST la mesure de l'erreur de l'ancienne.
```

## [NOTE-146]

`*phys-cfh*` — LE SEAU DU CONFLIT, PAR CHAINE : combien de fois le volume `ci`
s'est DISPUTE un lien de la chaine avec au moins un autre volume, dans la meme
frame. Alimente par la passe de SELECTION, donc par toute la course. Il repond a
la question que `ROOM-VOLPRIO` pose sans y repondre : `chestR` conflicte 85895
fois contre 2264 a gauche — MAIS AVEC QUI ?

`*phys-cvh*` — le COMPTE de triplets (frame, MAILLON, volume) en violation
(`res > 0`), alimente par `phys-pen-chain` (drapeau `*phys-buried-tally*`), donc
une fois par frame et par chaine.

**CORRECTION D'UNE PHRASE PERIMEE, cycle 59.** Le texte que le moteur portait
ici disait que `*phys-cvh*` « n'est alimente que par la fenetre de controle
positif (mesure du 2026-08-13 : `meshpen_max = 0.0000` sur toutes les phases de
mesure) ». **C'est faux depuis le cycle 15** : `meshpen` est non nul sur 224 des
310 cellules de la course livree, et `PHYSCVOL` publie des comptes de l'ordre de
2000 par (maillon, volume) — c'est-a-dire toute la course, pas 90 frames de
PCON. Une phrase juste en aout 13 et fausse en aout 20 est un commentaire qui
tient lieu de preuve : elle est corrigee ici plutot que recopiee.

`*phys-cvm*` — **NOUVEAU, cycle 59.** Le MAXIMUM de `res` par (maillon, volume)
sur toute la course, dans les memes unites de jeu que `meshpen`, arme au meme
endroit et par le meme drapeau que le compte.

POURQUOI IL MANQUAIT, ET CE QU'IL FERME. `PHYSCVOL` donne un COMPTE et
`PHYSDIAG6` un ARGMAX (`worstres=456.7879 worstci=39`). Ni l'un ni l'autre ne
repond a la question de POPULATION dont depend tout choix de correctif : *si on
retirait le volume qui porte le maximum, que vaudrait le suivant ?* Un argmax
repond DANS une frame, jamais sur une population (registre
`argmax-anchor-is-not-a-population`). Sans ce chiffre, « corriger le volume
fautif » et « le residu est un plateau sur tous les volumes proches » sont
indiscernables — et les deux appellent des chantiers opposes.

NATURE : une LONGUEUR (unites de jeu, 4096 u = 1 m), maximum de course, par
couple (maillon, volume). REPERE : celui du volume teste, comme `res`.
LECTURE QUAND LE DEFAUT EST ABSENT : aucune ligne pour ce couple — le volume
n'a jamais rien demande a ce maillon. CONTROLE : `*phys-col-off*` desarme le mur
par `phys-vol-floor` et doit faire tomber TOUTE la colonne (`feff` devient
`PHYS-VOL-FREE`, donc `res` devient tres negatif et le seau ne se remplit plus).

## [NOTE-147]

Texte d'origine, conserve, il dit ce que le solveur FAIT :

```
;; on raisonne sur le CENTRE du volume porte par le lien, pas sur son joint : c'est le
;; volume que le generateur a mesure sur le mesh, le meme que ce lien presente aux
;; autres chaines. Le decalage est rigide, donc la poussee se reporte telle quelle sur
;; le joint a la sortie.
;; DEUX decalages, pas un : la pose du MODELE porte son volume par la matrice ANIMEE,
;; la position SIMULEE le porte par l'orientation SIMULEE du lien. Les confondre posait
;; le volume la ou le lien n'est pas des que le decalage n'etait plus nul.
```

**CE QUE « RIGIDE » VEUT DIRE, ET CE QU'IL NE VEUT PAS DIRE (cycle 59).** Le decalage est rigide
DANS LE REPERE DU LIEN. Il ne l'est PAS par rapport au JOINT : `phys-link-off-sim!` porte `off` par
la rotation d'arc minimal qui envoie la direction du MODELE sur la direction SIMULEE du lien.
Deplacer le joint TANGENTIELLEMENT tourne le lien, donc tourne le decalage. Deux consequences, et
elles sont mesurables :

1. **LE SOLVEUR ET L'INSTRUMENT NE POUSSENT PAS LE MEME POINT.** `phys-collide-chain` calcule `offs`
   UNE FOIS sur la position d'ENTREE du lien, puis pousse `joint + offs` pendant 3 balayages et 4
   tours de finition sans jamais le recalculer. `phys-link-pen` le recalcule sur la position de
   SORTIE. L'ecart vaut `|offs| x angle parcouru`. Mesure par `PHYSDIAG6 offdrift=`.

2. **LA BOUCLE DE COLLISION EST SUR-RELAXEE D'UN FACTEUR `1 + |offs| / want`.** Bouger le joint de
   `e` tangentiellement fait bouger le CENTRE de `e (1 + |offs|/want)` : la rotation du lien
   (`e/want`) emmene le decalage avec elle. Le solveur applique la correction de profondeur AU
   CENTRE puis la reporte TELLE QUELLE sur le joint, donc le centre se deplace de `1 + |offs|/want`
   fois ce qui etait demande.

        chaine   maillon   |offs|    want     gain = 1 + |offs|/want
        chestL   l=0       651.2    1040.5    1.626
        chestL   l=1       514.6     140.4    4.665
        chestR   l=0       629.5    1039.0    1.606
        chestR   l=1       467.4     144.2    4.241

   Une projection alternee dont le pas depasse 2 ne converge pas. Le maillon distal est a 4.2-4.7,
   le proximal a 1.6 — et c'est EXACTEMENT la repartition mesuree du residu au cycle 59
   (`l0/l1 = 0.173 / 0.284`, quand le rapport des gains predit 0.171 / 0.187).

   Ca rend compte, sans hypothese supplementaire, de trois observations que le dossier avait
   chacune classee comme un mystere separe : (a) monter le nombre de balayages a 36 ne change rien
   (une iteration divergente ne s'ameliore pas avec les tours) ; (b) le pas « corrige » du cycle 47,
   qui multipliait la poussee par `1/s^2` pour ameliorer le rendement, a fait MONTER `meshpen` (il
   augmentait encore la relaxation) ; (c) le residu vit sur le maillon distal.

**CE QUI RESTE A PROUVER, ET LA COURSE QUI LE TRANCHE** : rien de ce paragraphe n'est une mesure
tant que `offdrift` n'a pas ete lu. Predictions gravees avant, dans
`.autoport/reports/Grecharged-secondary-motion/C59E3-offdrift-predictions.txt`.

## [NOTE-128]

Texte deplace du moteur (plafond de lignes de la gate CLEAN, 4800, que le contrat GELE) :

```
;; SPEC 33 — LE DOMAINE DE LA PAIRE. Un echantillon par (lien, volume) et
;; par frame, pris a l'ENTREE (`sub` = 0, avant toute poussee de ce
;; balayage). `*phys-depsigned*` porte la profondeur NON bornee que
;; `phys-collide-depth` vient de calculer pour `pt` — c'est le dernier des
;; trois appels du `let*`, donc la variable porte bien celle de `dep`.
;; Le drapeau evite un sentinelle flottant (piege deja paye) : premier
;; echantillon = affectation, les suivants = maximum.
```

## [NOTE-149]

Texte deplace du moteur, meme raison :

```
;; LA LONGUEUR, A CHAQUE BALAYAGE — le correctif du residu de penetration. Appliquee
;; seulement APRES les `sweeps`, elle defaisait la part RADIALE de chaque poussee de
;; profondeur sans jamais la retester contre le volume, et monter le nombre de tours
;; n'y pouvait rien — chaque tour finissait pareil. Alternee DANS la boucle, c'est une
;; projection alternee sur deux ensembles (sphere de l'attache, complementaire du
;; volume) qui converge vers leur intersection des qu'elle est non vide. `pt` est ici
;; le CENTRE DU VOLUME : on repasse en coordonnees de joint pour la reprojection.
```

**PRECISION DU CYCLE 59, ET ELLE CHANGE LA CONCLUSION DE CE PARAGRAPHE.** « Une projection
alternee converge vers l'intersection des qu'elle est non vide » n'est vrai QUE si le pas est bien
dimensionne. Il ne l'etait pas : la correction est calculee sur le CENTRE du volume et reportee
telle quelle sur le JOINT, alors que le centre parcourt `1 + |offs|/want` fois ce que le joint
parcourt (voir [NOTE-147]) — 4.2 a 4.7 sur le maillon distal. Une projection alternee dont le pas
depasse 2 ne converge pas, et c'est pour ca que porter les balayages a 36 n'avait rien change.

## [NOTE-151] SPEC 8/10-13/29/36 — LA DEFORMATION ENTRE ICI, ET NULLE PART AILLEURS

```
                              ;; translation : la position simulee, telle quelle
                              ;; SPEC 8/10-13/29/36 — LA DEFORMATION ENTRE ICI, ET NULLE PART
                              ;; AILLEURS. La 3x3 est post-multipliee : un sommet de peau va
                              ;; d'abord la ou l'os d'auteur le mettait, puis subit l'echelle et la
                              ;; torsion, puis est pose a la position simulee. La ligne 3 est mise a
                              ;; zero avant, sinon la deformation s'appliquerait aussi a une
                              ;; translation qu'on va de toute facon remplacer.
```

## [NOTE-105 (texte complet, deplace ici le 2026-08-20)] CYCLE 37 : LE GROUPE DE COLLISION SEULE

```
                              ;; [NOTE-105] CYCLE 37 : le GROUPE DE COLLISION SEULE est celui des
                              ;; appels 12 a 15, donc les balayages 34 a 45 — il n'a AUCUNE
                              ;; contrainte de longueur pour ramener le lien en arriere. Si une
                              ;; poussee y est encore d'amplitude comparable a la moyenne de la
                              ;; frame, ce n'est pas la longueur qui recree la penetration : c'est
                              ;; l'ensemble des VOLUMES qui est inconsistant. `nlast` est le
                              ;; DOMAINE de `slast`, sans quoi un zero ne se distingue pas d'un
                              ;; groupe qui n'a pas tourne. `p1` dit ce qu'UNE projection accomplit.
```

## [NOTE-152] LA DIRECTION MONDE DE L'AXE `axis` DU SOLVEUR

```
;; LA DIRECTION MONDE DE L'AXE `axis` DU SOLVEUR : 0 = vertical, 1 = avant-arriere, 2 = lateral —
;; les ROLES de SPEC 7, pas les lignes de la matrice. La traduction role -> ligne se fait ici, par
;; `*phys-axv*` / `*phys-axa*` / `*phys-axl*`, exactement comme le solveur la fait pour la raideur.
;; NATURE : composante d'un vecteur unitaire. REPERE : monde.
;; REND 0.0 TANT QUE LA CHAINE N'EST PAS CLASSEE (`axok` = 0) — l'appelant doit le voir, sinon une
;; impulsion nulle passerait pour une impulsion sans reponse. C'est pour ca que la salle publie la
;; direction qu'elle a REELLEMENT utilisee au lieu de la supposer.
```

## [NOTE-150] LA PROFONDEUR **AJOUTEE** SOUS LA PEAU — LA SEULE QUE LA PHYSIQUE AIT ECRITE

Les DIRECTIVES du 2026-08-20 10:55 tranchent que `meshpen` N'EST PAS UNE PROFONDEUR mais un
DEPLACEMENT (`res = dep - feff`, la meme fonction 1-lipschitzienne evaluee en deux points contre le
MEME volume a la MEME frame), et que la gate COLLIDE doit lire « la penetration contre la surface
DESSINEE, **des que sa ligne de base au repos existe** (physique desarmee, fenetre de repos), qui
manque toujours ». Cette note construit cette ligne de base — et elle la construit PAR FRAME au
lieu d'une fenetre de repos separee, ce qui est strictement plus fort.

CE QUI EXISTAIT : `skinpen` = `-sd(point simule)`, la profondeur du JOINT sous la peau. L'os de
poitrine est INTERIEUR par construction anatomique (0.13 a 0.16 m sous la peau), donc `skinpen`
mesure l'anatomie et pas la physique. Son zero n'a jamais existe et son maximum ne se compare a
rien : c'est une constante de rig bruitee par le mouvement.

CE QUI EST AJOUTE : `skinadd = max(0, sd(point d'AUTEUR) - sd(point SIMULE))`, les deux distances
prises A LA MEME FRAME, sur LA MEME surface, pour LE MEME lien. L'offset anatomique se retranche
EXACTEMENT au lieu d'etre estime sur une autre fenetre — c'est la meme construction que `feff` pour
les volumes (« la profondeur d'auteur est deja retranchee »), mais contre le mesh DESSINE.
  NATURE  : une LONGUEUR (4096 u = 1 m), maximum de la fenetre, jamais un cumul.
  REPERE  : le monde, a la frame ecrite — le meme point d'ou `meshpen` est tire.
  ABSENT  : 0.0000. La pose d'auteur rend 0 AU BIT : les deux appels evaluent le meme point.
  DOMAINE : `tests` (PHYSSKIN) distingue « rien ne penetre » de « je n'ai pas regarde ».

CE QU'IL FAUT LUI OPPOSER AVANT DE LUI FAIRE PORTER UN VERDICT, ET C'EST ECRIT AVANT LA COURSE :
`phys-surf-sd` monte la matrice VIVANTE de chaque os, donc la peau que la poitrine pilote SUIT la
poitrine. Si l'echantillon le plus proche du joint appartient TOUJOURS a sa propre chair, la
grandeur est TAUTOLOGIQUE et vaut 0 par construction — le faux vert le plus cher de ce dossier.
LE CONTROLE POSITIF TRANCHE, il n'y a rien a supposer : l'injection de 400 u (`*phys-inject*`)
enfonce le point SIMULE et laisse le point d'AUTEUR ou il est. Si `skinadd` ne monte pas sous
l'injection, l'instrument est tautologique et il est retire ; s'il monte, il ne l'est pas.

## [NOTE-153] LA COLLISION EST LA DERNIERE OPERATION DE LA FRAME — L'INVARIANT ETAIT ECRIT, LE CODE NE LE TENAIT PLUS

CE QUE LE DOSSIER PRESCRIT, EN TOUTES LETTRES ET A DEUX ENDROITS :
  * moteur, en-tete de l'etage 2 : « des balayages de collision SEULS pour finir — la collision est
    la contrainte dure de la SPEC 3, c'est donc elle qui doit etre exacte a la fin » ;
  * [NOTE-45] : « il FAUT une fermeture [...] la longueur a deja ete imposee onze fois et son
    residu est publie » ; [NOTE-118] cite meme le bloc final comme etant « de la collision SEULE,
    deliberement » ; la note de `phys-bend-chain` : « la finition qui suit (collision puis recul)
    garde donc le dernier mot sur "rien ne traverse" ».

CE QUE LE CODE FAISAIT DEPUIS LE CYCLE 43. [NOTE-117] a remis `phys-bend-chain` DANS la boucle de
queue — pour une raison juste et mesuree (une contrainte hors boucle est reecrite par celles qui
sont dedans, +95 deg apparie sur le maillon distal). Mais elle l'a placee APRES `phys-collide-chain`
dans les deux boucles, donc la DERNIERE ecriture de position de la frame est devenue la borne
d'angle. Depuis [NOTE-118] cette ecriture repose le joint a `ml`, la longueur du MODELE, dans une
direction que la borne choisit — et elle n'est JAMAIS retestee contre les volumes.

LE CHANGEMENT. Les deux appels sont echanges dans la boucle de queue : `bend` puis `collide`.
  * l'intention de [NOTE-117] est intacte : la borne reste DANS la boucle, appelee 4 fois ;
  * l'invariant de [NOTE-45] est restaure : la derniere ecriture de la frame est une poussee de
    collision suivie de sa reprojection de longueur ([NOTE-149]), donc `ROOM-STRETCH` reste exact
    par construction et `rien ne traverse` est evalue en dernier ;
  * aucune constante neuve, aucun terme neuf, aucun suppresseur : deux lignes echangees ;
  * `hard?` = #t rend la borne idempotente ([NOTE-119]), donc le double appel de `bend` au raccord
    des deux boucles est un no-op et non une double attenuation.

CE QUE CA COUTE, ET C'EST L'ARBITRAGE QUE [NOTE-45] A DEJA TRANCHE. La collision peut repousser le
maillon AU-DELA de la borne d'apex de sa 22 : la borne cesse d'etre exacte a la fin de frame,
c'est la collision qui l'est. « Une resolution pire que le clip est pire que rien » (regle 6) place
la collision devant. Le prix se lit sur `ROOM-APEX` et sur `bendcut`, il est publie, pas suppose.

## [NOTE-160] SPEC 38 — la torsion deplace un point de la

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
                                                    ;; SPEC 38 — la torsion deplace un point de la
                                                    ;; chair situe a `rw` du centre de `rw * theta`.
                                                    ;; Sa borne est donc CELLE DE L'APEX, pas un
                                                    ;; chiffre invente : `HardMaxApexDisplacement
                                                    ;; 0.50 B0`, et le genou de `phys-softmin`
                                                    ;; (0.84 x cap) tombe exactement sur son
                                                    ;; `NormalMaxApexDisplacement 0.42 B0`.
```

## [NOTE-161] (d) SPEC 36 — LE MODE SECONDAIRE. Oscillateur propre a 5.2 Hz,

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
                                 ;; (d) SPEC 36 — LE MODE SECONDAIRE. Oscillateur propre a 5.2 Hz,
                                 ;; zeta 0.65, EXCITE PAR UN CHANGEMENT DE DIRECTION de la masse
                                 ;; globale (« this response should mainly appear after a change in
                                 ;; direction of the global breast mass ») : l'entree est donc la
                                 ;; VARIATION de la vitesse de pointe d'une frame a l'autre, rapportee
                                 ;; a B0. Meme recurrence que le mode principal (Euler symplectique),
                                 ;; meme forme d'amortissement `2 zeta w dt`.
```

## [NOTE-162] ---- 0bis. SPEC 33/34 — CE QUI RESTE DE LA RESTITUTION, MESURE ET NON DEDUIT.

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
                    ;; ---- 0bis. SPEC 33/34 — CE QUI RESTE DE LA RESTITUTION, MESURE ET NON DEDUIT.
                    ;; La vitesse sortante `e*|vn|` est vraie A L'INSTANT OU on l'ecrit ; ce qui
                    ;; compte est ce qu'il en RESTE apres que la frame se soit terminee (longueur,
                    ;; balayages, attenuation). On relit donc `v = p - q` ICI, avant que cette
                    ;; frame-ci n'integre quoi que ce soit : c'est exactement l'etat laisse par la
                    ;; frame precedente. Sans ca, `out` serait `e * in` par construction — un nombre
                    ;; qui se compare a lui-meme, le faux vert le plus facile de ce dossier.
```

## [NOTE-163] ARMEE DES QU'IL Y A UN MAILLON LIBRE. Ce verrou exigeait DEUX

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
                          ;; ARMEE DES QU'IL Y A UN MAILLON LIBRE. Ce verrou exigeait DEUX
                          ;; articulations, et sa raison n'etait pas physique — une masse ponctuelle
                          ;; sur un ressort anisotrope a bien trois frequences propres. C'etait un
                          ;; INTERVERROUILLAGE : §29 armee avait ete mesuree a `meshpen` 0.0022 m
                          ;; contre le plafond de 0.0005. Le correctif de B0 (SPEC 6) ayant reduit
                          ;; l'excursion de 30-36 %, l'interverrouillage se re-mesure au lieu d'etre
                          ;; suppose — et il se retire si `meshpen` remonte au-dessus de 0.0005.
```

## [NOTE-164] DEUX JEUX D'INDICES LA OU IL N'Y EN AVAIT QU'UN. `rootlock` portait DEUX roles :

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
              ;; DEUX JEUX D'INDICES LA OU IL N'Y EN AVAIT QU'UN. `rootlock` portait DEUX roles :
              ;;   (1) « quels maillons sont epingles » — ce que toutes les gardes `(>= l rlk)`
              ;;       lisent (contrainte de longueur, collision, recul, angles, mesures) ;
              ;;   (2) « quel maillon les DONNEES declarent epingle », qui doit rester lisible meme
              ;;       quand une racine graduee met `rlk` a 0 — sinon le diagnostic `rootrot`
              ;;       disparait au lieu de publier l'angle reellement ecrit dans sa 3x3.
              ;; `rlk0` porte le role (2), `rlk` le role (1) et lui seul.
```

## [NOTE-165] ----------------------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; ------------------------------------------------------------------------------------------------
;; COMBIEN DE PAIRES (LIEN, VOLUME) ONT BASCULE D'ETAT DEPUIS LA FRAME PRECEDENTE. C'est la mesure
;; du defaut que la 6e passe designe : un interrupteur binaire evalue chaque frame sur la pose du
;; modele saute quand il bascule, et le lien saute avec lui. On mesure l'etat CONTRAINT / LIBRE
;; (plancher effectif fini ou non) par paire, on le compare a celui de la frame precedente, et on
;; publie le nombre de bascules par chaine. La forme continue doit le faire tomber.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-166] UNE TRONCATURE SILENCIEUSE EST UN DE-SCOPE (2026-08-13). Un maillon

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
                        ;; UNE TRONCATURE SILENCIEUSE EST UN DE-SCOPE (2026-08-13). Un maillon
                        ;; au-dela de PHYS-LINKS etait simplement ignore, sans un mot : la chaine
                        ;; tournait avec moins d'os que les donnees en declarent et rien ne le
                        ;; disait. L'injection de joints de ce cycle amene lbang/rbang a EXACTEMENT
                        ;; 4 maillons, soit le plafond — le prochain os ajoute tomberait dans ce
                        ;; trou. On ne releve pas le plafond (il dimensionne plusieurs tableaux),
                        ;; on le rend BRUYANT.
```

## [NOTE-167] LE MEME INSTANT QUE `*phys-lsv*`, MAIS DANS LE TRIEDRE DE L'ANCRE.

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; LE MEME INSTANT QUE `*phys-lsv*`, MAIS DANS LE TRIEDRE DE L'ANCRE.
;; NATURE : deplacement instantane signe du maillon par rapport a sa pose d'auteur.
;; REPERE : triedre orthonorme de l'ANCRE (torse), jamais le monde — un maillon herite du mouvement
;;   de son parent, et c'est en repere monde que ce mouvement propre devient illisible ; une
;;   frequence PAR AXE (§24) ne peut structurellement pas se lire sur des x/y/z monde.
;; INSTANTANEE, ecrasee chaque frame, au meme point de la frame que `*phys-lsv*`.
;; LECTURE QUAND LE DEFAUT EST ABSENT : (0,0,0) exactement, a la pose du modele.
```

## [NOTE-168] LA MEME DEFORMATION, MAIS EN ESPACE ANCRE — et c'est celle-la qui est MESURABLE. `*phys-

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; LA MEME DEFORMATION, MAIS EN ESPACE ANCRE — et c'est celle-la qui est MESURABLE. `*phys-dfm*`
;; est conjuguee en monde (`w2l . A . am`), donc illisible depuis la trace sans refaire la
;; conjugaison. Le cycle 26 a du RECONSTRUIRE `A` hors moteur a partir de `PHYSORI2` (les trois
;; echelles de `dfa`) et du triedre, ce qui laissait dehors `dfb` (etirement dynamique de SPEC 38)
;; et `dfc` (pression de contact de SPEC 23) : le COM publie n'etait donc que PARTIEL. Publier `A`
;; telle quelle supprime la reconstruction ET l'omission. Ecriture SEULE, aucun lecteur dans le
;; solveur : ce tableau ne peut pas deplacer un joint.
```

## [NOTE-169] §36 — LE GAIN D'EXCITATION, CALE SUR SA BANDE ET SUR RIEN D'AUTRE. Mesure de la course B

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; §36 — LE GAIN D'EXCITATION, CALE SUR SA BANDE ET SUR RIEN D'AUTRE. Mesure de la course B, qui
;; publie l'amplitude AVANT ecretage : a 2.5 le mode secondaire rendait 19 % a 312 % selon le
;; pilotage, donc un plafond a 7 % touche en permanence — un limiteur sature, pas une amplitude.
;; A 0.05 les memes fenetres rendent : tilt 0.4-0.7 %, updown 1.5 %, jerk 4.0-4.5 %,
;; leftright 4.5-5.5 %, accel 5.7-6.2 %. Sa bande : « normal 2-5 %, strong impulse 5-7 %,
;; hard ceiling 7 % ». Le pilotage quasi-statique (tilt) tombe SOUS la bande, et c'est correct :
;; §36 est excitee par un CHANGEMENT DE DIRECTION, et une pose tenue n'en contient aucun.
```

## [NOTE-170] LA DIRECTION DE REPOS DU MATERIAU, dans le repere de l'ancre, relevee UNE FOIS et consta

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; LA DIRECTION DE REPOS DU MATERIAU, dans le repere de l'ancre, relevee UNE FOIS et constante
;; ensuite. Elle ne concerne QUE la chair de famille A a un seul maillon libre (oreilles, poitrine) :
;; un sein n'est pas une corde, c'est une masse sur un tissu elastique, et l'owner a fixe lui-meme sa
;; reference (« le point de reference c'est quand elle est debout, car c'est comme ca que le modele
;; est fait, MAIS ils suivent la gravite », SPEC 1bis). Les CHEVEUX n'en ont pas : ils pendent.
;; Elle est PRE-COMPENSEE de la fleche gravitaire a la capture, de sorte que debout l'equilibre
;; retombe exactement sur la pose du modele (SPEC 4) et que s'incliner la deplace pour de bon.
```

## [NOTE-171] `*phys-o1x/o1y/o1z*` sont retires : declares, remis a zero dans la branche d'ancre, et R

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes ; aucune ligne de code n'a ete refactoree)

```
;; `*phys-o1x/o1y/o1z*` sont retires : declares, remis a zero dans la branche d'ancre, et RELUS
;; NULLE PART — 6 occurrences dans tout `goal_src`, toutes des ecritures.
;; ETAT SIMULE — LA POSITION MONDE DE LA PARTICULE. C'est desormais le SEUL etat integre, et il n'y
;; en a pas d'autre : `p` (courant) et `q` (frame precedente), soit un verlet en position. Toute la
;; physique en decoule — la vitesse implicite `p - q` EST l'inertie, donc la masse ; la gravite s'y
;; ajoute comme une vraie acceleration monde ; la contrainte de distance et les collisions la
;; projettent. La pose au repos n'est plus imposee, elle EMERGE de cet equilibre.
```

## [NOTE-172] L'ARMEMENT, pas la classification : une chaine classee

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
                                        ;; L'ARMEMENT, pas la classification : une chaine classee
                                        ;; mais non armee (1 seule articulation) doit integrer
                                        ;; EXACTEMENT ce qu'elle integrait avant ce bloc, sans
                                        ;; meme passer par l'aller-retour de projection — dont
                                        ;; l'erreur d'arrondi suffirait a bouger un dernier chiffre
                                        ;; et a rendre la non-regression indemontrable.
```

## [NOTE-173] ----------------------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; ------------------------------------------------------------------------------------------------
;; ------------------------------------------------------------------------------------------------
;; PIERRE TOMBALE — `phys-retreat-chain` a ete retiree ici le 2026-08-13 ; la note complete est a
;; l'endroit ou elle etait appelee, dans `jak-hd-physics-step`. Ses compteurs `*phys-retreat-*`
;; restent definis et restent a zero : un limiteur retire se chiffre, il ne se tait pas.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-174] EN CONTACT = dedans a sa pose de modele, ou dedans maintenant. Une paire dont

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
                ;; EN CONTACT = dedans a sa pose de modele, ou dedans maintenant. Une paire dont
                ;; les deux profondeurs sont nulles (un volume a l'autre bout du corps) n'est pas
                ;; un contact : la compter rendrait le residu identiquement nul et la colonne
                ;; deviendrait un zero constant, c.-a-d. indistinguable d'une colonne fabriquee.
                ;; `skip` ne porte QUE sur la profondeur : c'est la seule grandeur sur laquelle
                ;; deux volumes qui se recouvrent peuvent se contredire.
```

## [NOTE-175] ----------------------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; ------------------------------------------------------------------------------------------------
;; MESURE de la penetration RESIDUELLE d'UN lien place en `pt` : meme predicat, memes volumes, meme
;; plancher de pose modele que la resolution, mais SANS marge et sans rien deplacer. C'est la seule
;; definition de « ca traverse » du moteur, et elle sert aux trois usages (resoudre, reculer,
;; mesurer) — il n'y a donc pas d'instrument de mesure different de l'instrument de decision.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-176] L'ETAT SUIVI EST « EN CONTACT », plus « contraint ou libre ». Depuis que la

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
                    ;; L'ETAT SUIVI EST « EN CONTACT », plus « contraint ou libre ». Depuis que la
                    ;; branche PHYS-VOL-FREE est retiree, toute paire est contrainte : garder
                    ;; l'ancien predicat aurait rendu ce bit constamment 1, donc le compteur de
                    ;; bascules identiquement nul — un instrument mort qui affiche du vert. Le
                    ;; predicat de contact est celui de `phys-link-pen`, donc les deux passes
                    ;; parlent de la meme chose : dedans a la pose du modele, ou dedans maintenant.
```

## [NOTE-177] MESURE SEULE : on a compte, on ne decide pas. Rendre `*phys-lwin*` a -1 remet le

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
                ;; MESURE SEULE : on a compte, on ne decide pas. Rendre `*phys-lwin*` a -1 remet le
                ;; comportement a l'identique du desarmement — c'est la valeur que la ligne 1959
                ;; venait d'y mettre, et les deux seuls consommateurs (`skip` en poussee, `skip` au
                ;; recul) exigent de toute facon `(zero? *phys-prio-off*)`. La remise est donc
                ;; redondante par deux fois, et c'est voulu : une mesure ne doit pas pouvoir
                ;; devenir un arbitrage par accident.
```

## [NOTE-178] LA PROFONDEUR NON BORNEE, POUR LA MESURE SEULE. La valeur RENDUE est bornee a 0 par le b

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
      ;; LA PROFONDEUR NON BORNEE, POUR LA MESURE SEULE. La valeur RENDUE est bornee a 0 par le bas
      ;; — c'est ce que veut une poussee — et deux paires qui ne se touchent pas rendent donc le
      ;; MEME zero, qu'elles soient a un cheveu ou a un metre. Ce store rend la grandeur SIGNEE
      ;; `want - d` : positive = recouvrement, negative = l'ecart entre les deux surfaces.
      ;; Un seul store, avant le `cond`, aucune branche touchee : la valeur de retour et la normale
      ;; sont inchangees au bit pres. Aucun consommateur du solveur ne lit cette variable.
```

## [NOTE-179] ----------------------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; ------------------------------------------------------------------------------------------------
;; GEOMETRIE — un lien contre un collider. Le collider est une SPHERE (joint2 < 0) ou une CAPSULE
;; (segment joint..joint2, rayon interpole). Les deux suivent la forme reelle du personnage : leurs
;; rayons sont ajustes sur les sommets skinnes du mesh par le generateur, pas poses a la main.
;; Retourne la profondeur de penetration (0 si dehors) et ecrit la normale de sortie dans `nrm`.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-180] PREUVE D'EXECUTION (regle 0) : `gradient=` traverse le fichier de donnees,

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
                      ;; PREUVE D'EXECUTION (regle 0) : `gradient=` traverse le fichier de donnees,
                      ;; le parseur C++ et la garde `param_id < kPhysNumChainParams` avant d'arriver
                      ;; ici, et un zero silencieux a l'une de ces couches rendrait la racine
                      ;; graduee INERTE sans qu'aucun chiffre ne le dise -- on croirait avoir mesure
                      ;; le correctif alors qu'on aurait mesure son absence. La ligne ne s'imprime
                      ;; que pour les chaines qui le declarent, donc son ABSENCE est aussi une mesure.
```

## [NOTE-181] CONTROLE DU CYCLE 44 — 1 = LA BORNE D'ANGLE `phys-bend-chain` EST ENTIEREMENT DESARMEE.

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; CONTROLE DU CYCLE 44 — 1 = LA BORNE D'ANGLE `phys-bend-chain` EST ENTIEREMENT DESARMEE.
;; RESTE A 0 EN LIVRAISON. C'est une ABLATION de mesure, sur le modele exact de `*phys-col-off*`,
;; `*phys-len-off*` et `*phys-side-off*` : elle repond a « combien de la platitude livree est le
;; fait de la borne, et a quel prix la borne l'achete ». La demande a l'etage 0 discrimine de
;; 34.7 a 79.4 % sur six pilotages ; la livraison de 0.03 a 19.4 %. Desarmer la borne est le seul
;; controle qui attribue cet ecart, et il n'est JAMAIS livre a 1.
```

## [NOTE-182] ... et le MEME compte, mais PAR CHAINE et UNE SEULE FOIS PAR FRAME. Le compteur global c

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; ... et le MEME compte, mais PAR CHAINE et UNE SEULE FOIS PAR FRAME. Le compteur global ci-dessus
;; est incremente par chaque appel de `phys-link-pen`, y compris les douze pas de dichotomie du
;; recul : son total (369 876) est un nombre d'evaluations, pas un nombre de paires enfouies, et il
;; ne dit pas QUELLE chaine est enfouie. Or c'est exactement la question que pose « le bas du
;; pantacourt est avale a l'interieur des mollets ». Ce drapeau n'est leve que pendant la passe de
;; MESURE (phys-pen-chain), donc le compte par chaine est un compte de frames x paires.
```

## [NOTE-183] LE TRIEDRE DE SA SPEC 7 (+X lateral sortant, +Y haut du torse, +Z vers l'avant du buste)

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; LE TRIEDRE DE SA SPEC 7 (+X lateral sortant, +Y haut du torse, +Z vers l'avant du buste), en
;; espace ANCRE, releve UNE fois a la pose debout d'auteur — la meme frame que `g_ref` et que
;; `*phys-ux*`, pour que les trois references soient coherentes. Il ne se deduit d'aucun nom d'os :
;; +Y = -g_ref (la verticale telle que le modele a ete sculpte), +Z = la protrusion racine->apex
;; orthogonalisee, +X = leur produit. Un rig retargete peut donc arriver dans n'importe quelle
;; orientation sans que rien ici ne change.
```

## [NOTE-184] PIERRE TOMBALE DU FOURREAU — retire le 2026-08-14. Le pan de pantacourt (`pantflapL/R`) 

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; PIERRE TOMBALE DU FOURREAU — retire le 2026-08-14. Le pan de pantacourt (`pantflapL/R`) etait
;; contraint par CONCENTRICITE (borner son ecart radial a l'axe du mollet qu'il entoure) au lieu
;; d'etre ejecte de ce membre. Le mecanisme est mort dans la course actuelle : 0 chaine sur 22
;; declare `shell > 0` — les deux seules qui portent la cle sont a `shell=0` —, donc le predicat
;; rendait #f partout et le controle positif ne pouvait plus tirer (`ROOM-SHELL-CONTROL
;; armed=disarmed=0`). La cle `shell=` reste dans les donnees livrees ; seul le code mort part.
```

## [NOTE-185] L'ANGLE QUE LA PEAU PEUT ENCAISSER, EN DEGRES — CHEVEUX SEULEMENT, 0 = pas de limite.

(bloc deplace du moteur le 2026-08-20, cycle 60, pour tenir sous le plafond CLEAN de 4800 lignes)

```
;; L'ANGLE QUE LA PEAU PEUT ENCAISSER, EN DEGRES — CHEVEUX SEULEMENT, 0 = pas de limite.
;; Owner 2026-08-11 21:15 : « certains maillons meriteraient un traitement pour eviter de creer des
;; angles extremes qui mettent en lumiere le lack of geometrie » ; 22:35, le perimetre : « juste sur
;; les meches, pas le reste, encore moins les seins ». La valeur est DERIVEE DU RIG par le
;; generateur (2*atan(min(L_entrant,L_sortant)/rayon), l'angle ou les deux tubes de peau se
;; croisent) et recalculee par son controle 6b : le moteur ne connait toujours aucun nom de joint.
```

## [NOTE-156] LA LIGNE DE BASE AU REPOS DE SPEC 33/34 — MESUREE SUR LE CHEMIN DE LA COURSE

L'arbitrage du 2026-08-20 13:20 exige `ROOM-SKINPEN-REST`, « la ligne de base au repos, physique
DESARMEE », et fait ECHOUER la gate tant qu'elle manque (« NON ETABLI n'est pas c'est bon »).

PREMIERE TENTATIVE, ET ELLE EST REFUTEE PAR SA PROPRE MESURE. J'avais construit la ligne de base a
partir du POINT D'AUTEUR evalue a la meme frame (`sd(A)`), en faisant valoir que la pose d'auteur
EST la pose sans physique. L'argument reste juste ; l'INSTRUMENT ne l'est pas. `skinout` compte
41842 lectures qui placent ce point DEHORS, ce qui est anatomiquement impossible pour un os que le
rig place a l'interieur, et la preuve tient sans aucun taux : sur la frame du maximum,
`skinadd = sd(A) - sd(S) = 1052.01 u` et `-sd(S) <= skinpen max = 556.15 u`, donc `sd(A) >= 495.87 u`
DEHORS, alors que la meme passe le mesure a 411.38 u SOUS la peau. Erreur de signe de 0.221 m.
Cause : `phys-surf-sd` est une SDF de NUAGE DE POINTS filtree par une phase large
(`|p - os| < bsr + 512`), donc PAS lipschitzienne au franchissement d'un ensemble d'os — voir
[NOTE-150]. La valeur reste publiee comme DIAGNOSTIC (`ROOM-SKINPEN-REST-AUTEUR`), jamais comme
plancher.

CE QUI LA PORTE MAINTENANT : la FENETRE DE REPOS elle-meme (`PHYSROOM-PH-IDLE`), avec
`PHYSSKIN tag=rest`. Elle a l'avantage decisif d'utiliser le MEME chemin que la course — meme
fonction, meme point (`*phys-px*`, la position simulee), meme garde `sd < 0` — donc les deux
colonnes sont comparables terme a terme, sans changement de grandeur en chemin. Le point d'auteur
n'entre plus du tout dans le verdict.

« PHYSIQUE DESARMEE » EST ICI UNE MESURE ET PAS UNE PROMESSE. La fenetre est `physroom-hold`
(position, orientation et animation figees) et `PHYSIDLE dev`, publie sur CETTE MEME fenetre, donne
l'ecart residuel du joint a sa pose d'auteur, chaine par chaine — 0.47 / 1.02 u sur la course de
reference. Le validateur plafonne lui-meme cette grandeur a 1.0 (gate IDLE). Le desarmement est
donc chiffre a cote de la ligne de base qu'il justifie, au lieu d'etre affirme.

CE QUE CETTE LIGNE ETABLIT, ET CE QU'ELLE N'ETABLIT PAS — a lire avant d'en tirer un vert. Elle
compare la profondeur d'un point INTERIEUR (le joint) sous la surface dessinee, en mouvement contre
au repos. Elle repond donc a « la physique enfonce-t-elle le joint plus profond que la pose de
repos ? ». Elle ne repond PAS a « une surface en traverse-t-elle une autre » : cela demanderait de
porter la mesure sur les SOMMETS de peau, pas sur le joint. Le jour ou §33/§34 se declarent TENUES,
c'est cette reserve-la qu'il faudra lever.

## [NOTE-190] LE MOUVEMENT PROPRE DU MAILLON : l'angle entre sa direction

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                                  ;; LE MOUVEMENT PROPRE DU MAILLON : l'angle entre sa direction
                                  ;; courante et la direction que le MODELE donne au meme os, tous
                                  ;; deux mesures depuis LA MEME ATTACHE. Un maillon qui suit
                                  ;; rigidement son parent vaut zero ici quelle que soit l'agitation
                                  ;; du parent — c'est ce que la boite englobante ne pouvait pas
                                  ;; voir, et c'est la suite que SPEC 2 exige croissante.
```

## [NOTE-191] --- ALLONGEMENT RELATIF et INVERSION RESIDUELLE, sur la position ECRITE et

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                      ;; --- ALLONGEMENT RELATIF et INVERSION RESIDUELLE, sur la position ECRITE et
                      ;; --- APRES tout le solveur. Ce sont les deux nombres que la 5e et la 2e/3e/4e
                      ;; --- passe de l'owner exigent : « ils s'allongent, c'est un peu debile » et
                      ;; --- « un de ses seins retourne vers l'interieur ». Meme attache, meme
                      ;; --- direction de modele que la contrainte : l'instrument de mesure est
                      ;; --- l'instrument de decision.
```

## [NOTE-192] ------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                    ;; ------------------------------------------------------------------------
                    ;; 5. MESURE (SPEC 7). ELLE SE FAIT ICI, AVANT L'ECRITURE, et c'est structurel :
                    ;; une fois le squelette ecrit, `skel bones` porte la pose SIMULEE et la pose
                    ;; d'auteur a disparu. Ce qui est compare : *phys-p** = la pose COMMITEE (elle
                    ;; sera ecrite telle quelle au bloc suivant), `skel bones` = le RETARGET.
                    ;; ------------------------------------------------------------------------
```

## [NOTE-193] ---- 4bis. CONTROLE POSITIF DU CANAL D'AUTEUR. Arme, la position ecrite est

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                    ;; ---- 4bis. CONTROLE POSITIF DU CANAL D'AUTEUR. Arme, la position ecrite est
                    ;; ---- batie sur la pose d'auteur de la frame PRECEDENTE : l'animation est
                    ;; ---- retardee d'une frame, ce que la SPEC 5 interdit. Applique APRES le
                    ;; ---- report dans l'ecart, sinon l'ecart absorberait le defaut et le compteur
                    ;; ---- d'identite ne verrait rien — c'est le piege qui rendrait le controle
                    ;; ---- muet.
```

## [NOTE-194] contenir un echantillon plus proche que le meilleur deja trouve. `bestd2` part de

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
            ;; contenir un echantillon plus proche que le meilleur deja trouve. `bestd2` part de
            ;; 1e12, donc les premiers ensembles ne sont jamais ecartes, et le test se resserre a
            ;; mesure qu'un candidat apparait : c'est un branch-and-bound, il ne change RIEN au
            ;; resultat sauf qu'il cesse de pouvoir se tromper.
            ;; CE QU'IL REMPLACE, ET POURQUOI : `(< |dv| (+ bsr 512.0))` ecartait un ensemble sur
            ;; une MARGE INVENTEE. Mesure du cycle 60, fenetre de repos, physique desarmee
            ;; (`PHYSIDLE dev` 0.47 / 1.02 u) : `chestL` rendait `skinpen = 0.0000` — pas
            ;; « dehors », mais la SENTINELLE « aucun echantillon a portee » — pendant que
            ;; `chestR` rendait 417.23 u DEDANS. Un os que le rig place a 0.10 m sous la peau ne
            ;; peut pas etre hors de portee de la peau : c'etait la marge qui coupait.
```

## [NOTE-158] LA PEAU ETAIT TRONQUEE EN SILENCE — LA CAUSE COMMUNE DE TOUT LE FIL DU CYCLE 60

MESURE, lue dans la trace livree et pas deduite :

    [hd-phys] BSURFSRC=package bsets=92 dropped=0
    [HD-PHYS] bsurf ag=keira-hd sets=64/92 lies=64 non-lies=0

`PHYS-BSURF-SETS` valait 64 : **28 ensembles de surface sur 92 etaient JETES**. Et chaque ensemble
retenu etait tronque a `PHYS-BSURF-MAX` = **12 echantillons**, un PREFIXE arbitraire. `phys-surf-sd`
voyait donc au plus **768 points** pour tout le personnage.

CE QUE CA EXPLIQUE, ET C'EST TOUT LE FIL :
  * `chestL skinpen = 0.0000` dans la fenetre de REPOS avec `skinmiss = 0` — donc des echantillons
    etaient bien a portee, et la SDF a quand meme rendu « dehors » pour un os que le rig place a
    0.10 m SOUS la peau — pendant que `chestR` rendait 417.23 u DEDANS ;
  * `skinout` = 41842 sur le point d'AUTEUR ;
  * `skinadd` = 1052 u la ou `|A - S|` ne depasse jamais 301 u, c'est-a-dire la violation de la
    borne 1-lipschitzienne relevee en [NOTE-150]. Une SDF batie sur 768 points epars n'est
    lipschitzienne nulle part.

DEUX HYPOTHESES REFUTEES AVANT CELLE-CI, ET JE LES LAISSE ECRITES :
  1. « le point d'AUTEUR est le mauvais point de reference » ([NOTE-154]) — non : le point SIMULE
     souffre du meme defaut, mesure dans la fenetre de repos ;
  2. « la phase large ecarte l'ensemble le plus proche » ([NOTE-157]) — non : `skinmiss` = 0 apres
     le passage en branch-and-bound exact, et `chestL` lisait toujours 0.0000. Le branch-and-bound
     RESTE (il supprime une marge inventee et ne peut pas se tromper), mais il n'etait pas la cause.

CORRECTIF : `PHYS-BSURF-SETS` 64 -> 96 (couvre les 92 declares) et `PHYS-BSURF-MAX` 12 -> 48.
ET SURTOUT, LA TRONCATURE NE PEUT PLUS SE TAIRE : `PHYSBSURF sets=/declared=/max=` est emis par la
salle et publie par le tableau en `ROOM-SKINPEN-COVERAGE`. Tant que `sets < declared`, le tableau
REFUSE de publier `ROOM-SKINPEN-REST` sous le nom que la gate lit — un plancher tire d'une surface
qui n'est pas celle du personnage ne vaut rien, dans un sens comme dans l'autre.

## [NOTE-159] LA VRAIE CAUSE EST DANS LA DONNEE : 12 ECHANTILLONS PAR OS, ET AUCUN POUR LES SEINS

Apres avoir refute TROIS causes (le point d'auteur [NOTE-154], la phase large [NOTE-157], la
troncature des plafonds [NOTE-158]), la mesure suivante ferme la question, et elle se lit dans le
fichier LIVRE sans rien executer :

    grep "^bs " recharged_assets/physics_mesh.txt | awk '{print $3}' | sort -n | uniq -c
        84 ensembles a 12 echantillons · 3 a 10 · 2 a 6 · 1 a 11 · 1 a 8 · 1 a 2

    les 92 noms d'ensembles contiennent lTopStrap2, rTopStrap2, gogglesMid, chaque doigt, chaque
    meche — et **PAS lBoob, PAS rBoob, PAS lBooc, PAS rBooc**.

DONC : le SEUL organe que cette phase simule n'a AUCUN echantillon de surface a lui. Le point de
peau le plus proche d'un joint de poitrine est l'un des **12** echantillons de `chest`, repartis
sur tout le buste. `phys-surf-sd` decide « dedans / dehors » sur la normale de CE point-la.

C'EST POURQUOI RELEVER LES PLAFONDS N'A RIEN CHANGE : `PHYS-BSURF-MAX` valait 12 et la donnee en
declare 12. Le passage a 48 est INERTE tant que le generateur n'en produit pas davantage. Le
passage de `PHYS-BSURF-SETS` de 64 a 96 reste, lui, un vrai correctif — 28 ensembles declares
etaient JETES (`sets=64/92` -> `sets=92/92`) — mais il ne touche pas la poitrine, qui n'a pas
d'ensemble a jeter.

CONSEQUENCE POUR SPEC 33/34, ET ELLE N'EST PAS NEGOCIABLE : le verdict que l'arbitrage du
2026-08-20 13:20 fait porter a `skinpen` repose sur une SDF qui n'a pas de peau la ou elle mesure.
Elle rend `chestL skinpen = 0.0000` au repos (« dehors ») et 556.15 u en course (« dedans »), soit
un ecart de 0.136 m que le deplacement du joint (borne 301 u = 0.073 m) ne peut pas produire : elle
se contredit ELLE-MEME entre deux fenetres. Le tableau refuse donc de publier le plancher, et la
gate reste NON ETABLI — c'est la lecture correcte, pas un contournement.

CE QUI DEBLOQUERAIT LA SECTION, ET C'EST UNE TACHE D'ASSET, PAS DE SOLVEUR : regenerer
`physics_mesh.txt` avec (a) un ensemble de surface pour chacun des quatre joints de poitrine, et
(b) une densite qui permette a une SDF de nuage de points de decider un cote — 12 points pour un
buste entier n'y suffisent pas. Tant que ce fichier n'a pas de peau de poitrine, aucun reglage du
moteur ne rendra `skinpen` lisible sur cet organe.

## [NOTE-160] LE JEU DE DONNEES QUI REPONDRAIT A SPEC 33/34 EXISTE — ET PERSONNE NE LE LIT

[NOTE-159] etablit que la peau des seins ne peut PAS apparaitre dans `bs` : `model_bsurf` exclut
tout os qui est un maillon de chaine, et c'est CORRECT pour un jeu d'OBSTACLES — un sein n'est pas
un obstacle pour lui-meme.

CE QUI MANQUE N'EST DONC PAS `bs`, C'EST SON PENDANT. Le generateur ecrit, depuis le cycle 14, des
enregistrements `ms <chaine> <maillon> <n> (x y z)*n` — « the handful of skinned vertices that
stick out FURTHEST from the link, expressed in the bone's own bind-local frame so they can be
carried by the solved link transform every frame and tested against the body volumes AT THE
SURFACE » (docstring de `physics_c14_meshsamples.py`). C'est EXACTEMENT la grandeur que sa 33
demande : la peau du sein, portee par la matrice resolue, testee contre le corps.

CORRECTION — J'AI PUBLIE UNE AFFIRMATION FAUSSE ET JE LA RETIRE. J'avais ecrit qu'il n'existait
« AUCUN accesseur `ms`, ni dans le C++ ni dans le GOAL ». **La moitie C++ est fausse**, et l'erreur
est bete : j'ai cherche la chaine `msurf` alors que les accesseurs s'appellent `msample`.

CE QUI EST VRAI, VERIFIE : le C++ EXPOSE deja `pc-physics-chain-msample-count` et
`pc-physics-chain-msample-mi` (`kmachine.cpp:1966-1993`, enregistres a `:4200-4202`), et il PARSE
les enregistrements `ms` (`:1725-1749`) dans `PhysChain::mesh_samples`. Le trou est UNIQUEMENT du
cote GOAL : `grep msample goal_src/` ne rend RIEN. La donnee est produite, parsee, exposee — et
aucun appelant ne la lit.

CE QUE CA CHANGE POUR LE CHANTIER, ET C'EST BEAUCOUP : il ne demande AUCUNE reconstruction de `gk`.
C'est un changement GOAL seul — charger les `msample` comme les `bs` le sont deja (:759-804), puis
porter `skinpen` sur CES points au lieu du JOINT. Le joint est interieur par
construction et ne peut pas repondre a une question de SURFACE ; ces points-la sont la surface.
La ligne de base au repos se calcule alors de la meme facon, sur la pose d'auteur, et la
comparaison redevient homogene.

## [NOTE-200] POSITION MOYENNE de la pointe dans le repere de l'ancre. La boite

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                            ;; POSITION MOYENNE de la pointe dans le repere de l'ancre. La boite
                            ;; ci-dessus ne retient que la VARIANCE : sous une inclinaison TENUE la
                            ;; chaine se pose sur un nouvel equilibre et ne bouge plus, donc la
                            ;; boite y mesure zero et l'a toujours mesure (PHYSTILT amp=0.0000 sur
                            ;; 19 chaines sur 22). La gravite ne se lit que dans le DEPLACEMENT
                            ;; SOUTENU, c'est-a-dire ici.
```

## [NOTE-201] LA MEME DIFFERENCE, SANS NORMALISER (voir la note

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
                                              ;; LA MEME DIFFERENCE, SANS NORMALISER (voir la note
                                              ;; de `*phys-ldb*`). `u` et `m` partent de LA MEME
                                              ;; ATTACHE, donc `u - m` EST le deplacement du
                                              ;; maillon par rapport a sa pose d'auteur — les trois
                                              ;; degres de liberte, dont le RADIAL que la version
                                              ;; normalisee annule par construction.
```

## [NOTE-202] Le joint est INTERIEUR par construction du rig : il ne peut pas repondre a une questio

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
          ;; Le joint est INTERIEUR par construction du rig : il ne peut pas repondre a une question
          ;; de SURFACE, et le cycle 60 l'a paye — `chestL` s'y lisait DEHORS au repos (0.0000) et
          ;; DEDANS en course (556 u), une contradiction que son deplacement ne peut pas produire.
          ;; On teste desormais les sommets EXTREMAUX du maillon (`ms`), portes par la matrice de
          ;; l'os, contre la surface du CORPS (`bs`) — qui exclut a raison les os de chaine, donc
          ;; aucun sein ne se mesure contre lui-meme. C'est la grandeur que sa 33 nomme.
          ;; LA ROTATION EST LA MEME DES DEUX COTES (matrice de l'os d'auteur) : elle disparait donc
          ;; de la difference course-repos, qui ne garde que le deplacement du maillon.
```

## [NOTE-203] INVERSIONS. Owner 2026-08-11 : « j'ai encore vu un de ses seins retourne vers l'interi

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; INVERSIONS. Owner 2026-08-11 : « j'ai encore vu un de ses seins retourne vers l'interieur ».
;; Cause : le ressort est symetrique autour de l'ancre, donc le cote oppose est un equilibre STABLE
;; mais FAUX, et la contrainte de longueur se taisait dans le cas degenere (distance sous 1e-4), ce
;; qui laissait la porte ouverte. Comptees ici, remises a zero par la salle, et un controle positif
;; les provoque expres pour prouver que le compteur voit quelque chose.
```

## [NOTE-204] ce que les limiteurs RETIRENT de mouvement, mesure et non estime (SPEC 7 : un suppress

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; ce que les limiteurs RETIRENT de mouvement, mesure et non estime (SPEC 7 : un suppresseur se
;; chiffre). Deux limiteurs peuvent reculer un lien :
;;   retreat  quand la projection ne trouve aucun point admissible, le lien recule vers sa pose de
;;            modele — la seule position admissible par construction ;
;;   raddrop  quand un lien SEUL (pas de parent simule) depasse le rayon que le mesh lui mesure.
```

## [NOTE-205] RETARD D'UNE FRAME injecte pour le CONTROLE POSITIF du canal d'auteur. 0 = desarme. Ar

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; RETARD D'UNE FRAME injecte pour le CONTROLE POSITIF du canal d'auteur. 0 = desarme. Arme, la
;; position ecrite est batie sur la pose d'auteur de la frame PRECEDENTE au lieu de celle-ci : c'est
;; exactement le defaut que la SPEC 5 interdit (la physique retarde l'animation). Le compteur
;; d'identite doit alors s'effondrer. Sans ce controle, « l'animation passe intacte » serait une
;; affirmation invérifiable sur notre propre construction.
```

## [NOTE-206] LE MEME MAXIMUM, MAIS AVANT LE PLAFOND DE SA §38. Sans lui, un mode secondaire sature 

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; LE MEME MAXIMUM, MAIS AVANT LE PLAFOND DE SA §38. Sans lui, un mode secondaire sature se lit
;; `0.0700` a chaque fenetre et devient indiscernable d'un mode correctement excite qui frole le
;; plafond — c'est la signature du limiteur sature, deja payee une fois sur ce dossier. C'est ce
;; nombre-la qui dit de combien le gain d'excitation est a cote, et c'est la seule facon de le
;; caler sur SA bande (2-5 % normal, 5-7 % impulsion forte) sans le regler sur l'instrument.
```

## [NOTE-207] LA MEME GRAVITE, MAIS SUR LES TROIS LIGNES DE LA MATRICE DE L'ANCRE — donc sur les axe

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; LA MEME GRAVITE, MAIS SUR LES TROIS LIGNES DE LA MATRICE DE L'ANCRE — donc sur les axes que la
;; classification de §29 a nommes `rv`/`rap`/`rlat`. Elle repond a une question que rien ne pouvait
;; trancher jusqu'ici : la ligne appelee AP est-elle vraiment l'avant-arriere ? Sous un TANGAGE
;; c'est l'avant-arriere qui doit s'allumer, sous un ROULIS le lateral. Si c'est l'inverse, les
;; deux compliances de §29 (0.90 et 0.82) sont posees sur les mauvais axes.
```

## [NOTE-208] L'ECART A LA POSE D'AUTEUR, DANS LE REPERE DE L'ANCRE. Ce fut l'etat INTEGRE du solveu

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; L'ECART A LA POSE D'AUTEUR, DANS LE REPERE DE L'ANCRE. Ce fut l'etat INTEGRE du solveur, et
;; c'est le modele que l'owner a rejete le 2026-08-13 a 22:40 (« on integre un ECART, pas un
;; cheveu »). Il n'est plus integre : il est DERIVE de la position monde a la section 4, et il ne
;; sert plus qu'a la mesure — toute l'instrumentation de la salle est definie sur lui, et le
;; contrat interdit de changer l'instrument en meme temps que ce qu'il mesure.
```

## [NOTE-209] LA LONGUEUR D'OS DE CHAQUE MAILLON, relevee sur la pose ANIMEE a chaque frame.

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; LA LONGUEUR D'OS DE CHAQUE MAILLON, relevee sur la pose ANIMEE a chaque frame.
;; (Sa moyenne `*phys-lmean*` a ete retiree le 2026-08-14 : elle ne servait qu'au ressort angulaire
;; `k2a`, qui n'existe plus depuis la bascule du 2026-08-13 22:40 — le symbole etait ecrit et lu
;; par personne dans tout `goal_src/`, verifie par recensement, et sa narration decrivait un
;; mecanisme absent.)
```

## [NOTE-210] LIBERTE GRADUEE DE LA RACINE, 0 = aucune (le maillon 0 reste epingle, comportement d'a

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; LIBERTE GRADUEE DE LA RACINE, 0 = aucune (le maillon 0 reste epingle, comportement d'avant ce
;; cycle au bit pres). Une valeur g dans ]0,1] rend le maillon 0 SIMULE, mais avec sa raideur
;; angulaire multipliee par 1/g^2 : sa deviation d'equilibre est donc de l'ordre de g fois celle
;; d'une racine libre. g=1 = racine entierement libre, et c'est l'etat que l'owner a DEJA rejete
;; (« cheveux decolles du crane »). Ce parametre n'existe pas pour etre mis a 1.
```

## [NOTE-211] 6e passe de l'owner : « lBoob et rBoob sont des spheres NUES posees sur le joint-racin

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; 6e passe de l'owner : « lBoob et rBoob sont des spheres NUES posees sur le joint-racine, alors
;; que tout le reste du corps est en capsules derivees. Une sphere au joint ne peut pas epouser un
;; sein. » Le centre de la sphere est desormais le CENTROIDE MESURE de la geometrie du joint, dans
;; l'espace bind de ce joint ; le moteur le transforme par la matrice de l'os, donc il suit
;; l'animation. Absent des donnees = 0,0,0 = le centre reste le joint (comportement d'avant).
```

## [NOTE-212] --------------------------------------------------------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 60)

```
;; ------------------------------------------------------------------------------------------------
;; PONT C++ — le magasin de parametres vit dans game/kernel/jak1/kmachine.cpp (parse de
;; recharged_assets/physics_chains.txt). Aucune valeur flottante ne traverse la frontiere : tout
;; arrive en MILLI-unites (kmachine.cpp:884-887, phys_mi:1721).
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-161] SPEC 33/34 SE MESURE SUR LA PEAU DE LA CHAINE, PAS SUR SON JOINT

CE QUI PRECEDE, ET QUI EST ETABLI : [NOTE-159] montre que la peau des seins ne peut PAS entrer
dans `bs` — `model_bsurf` exclut tout os qui est un maillon de chaine, et c'est CORRECT : un sein
n'est pas un obstacle pour lui-meme. `skinpen` retombait donc sur le JOINT, interieur par
construction, et rendait des verdicts qui se contredisent : `chestL` lu DEHORS au repos (0.0000)
et 556 u DEDANS en course, un ecart de 0.136 m que son deplacement (borne 301 u) ne peut pas
produire.

CE QUE J'AI PUBLIE ET QUI ETAIT FAUX, RETIRE EN [NOTE-160] : « aucun accesseur `ms`, ni C++ ni
GOAL ». La moitie C++ est fausse — les accesseurs s'appellent `msample`, pas `msurf`, et ils
existent (`kmachine.cpp:1966-1993`, enregistres a `:4200-4202`). Le trou etait cote GOAL SEUL.

CE QUE CETTE NOTE FAIT : le GOAL charge enfin les `msample` (les sommets EXTREMAUX de peau de
chaque maillon, espace bind local, deja parses par le C++ depuis le cycle 14) et `skinpen` porte
sur EUX. Donnee livree : `ms chestL 0 2`, `ms chestL 1 2`, `ms chestR 0 2`, `ms chestR 1 2` — deux
sommets par maillon, ceux qui sortent le plus loin, c'est-a-dire ceux qui traversent EN PREMIER.
La question devient celle que sa 33 pose : la peau du sein entre-t-elle dans le corps ?

DEUX CHOSES QUE JE DECLARE AU LIEU DE LES TAIRE :
  1. la ROTATION appliquee a l'offset est celle de l'os d'AUTEUR, des DEUX cotes (point simule et
     point d'auteur). Elle est donc IDENTIQUE dans les deux termes et disparait de leur difference,
     qui ne garde que le deplacement du maillon. Ce n'est pas la rotation ECRITE ; l'approximation
     est bornee et elle est la meme au repos et en course ;
  2. `skinout` CHANGE DE SENS avec la grandeur. Sur le joint, une lecture « dehors » etait une
     anomalie. Sur un sommet EXTREMAL de peau, etre dehors est la DEFINITION d'un point de surface :
     ce compte devient un DOMAINE, pas une alarme. Il reste publie, et aucun verdict ne s'en tire.

ET UNE GARDE EST RETIREE AVEC SA PREMISSE. Le controle de coherence du cycle 60 comparait repos et
course a la borne de deplacement du JOINT (301 u). Les sommets de peau sont a un RAYON du joint :
leur deplacement vaut celui du joint plus `2 r sin(theta/2)`, r allant jusqu'a ~650 u. Appliquer
301 u produirait un `NON ETABLI` sur une mesure legitime — un faux rouge. Les deux autres gardes
restent, premisses intactes : `skinmiss > 0` et `sets < declared`.

## [NOTE-240] [NOTE-109] CYCLE 37 ETAPE 2 — LE CUMUL PAR BRANCHE, ET L'ABLATION DE LA SPHERE PROXIMALE.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; [NOTE-109] CYCLE 37 ETAPE 2 — LE CUMUL PAR BRANCHE, ET L'ABLATION DE LA SPHERE PROXIMALE.
;; `*phys-cpc*` cumule sur TOUTES les frames depuis la derniere remise a zero de diagnostic :
;; 0 = nombre de poussees, 1 = somme de leurs modules (u), 2 = la meme sur les balayages 34-45.
;; C'est un AGREGAT, pas un maximum de fenetre : la question « la boucle converge-t-elle » est une
;; question de POPULATION, et le cycle 37 etape 1 a paye pour l'apprendre.
```

## [NOTE-239] ARMEE PAR LA SALLE SEULE (0 par defaut). 55 ensembles x 12 echantillons par lien et par frame,

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ARMEE PAR LA SALLE SEULE (0 par defaut). 55 ensembles x 12 echantillons par lien et par frame,
;; c'est le prix d'une mesure, pas d'un rendu : le JEU ne doit pas le payer sur le telephone de
;; l'owner. Meme forme que `*phys-prio-meas*`, dont l'armement avait deja porte la course de 420 a
;; 708 s. La phase large (rayon englobant) coupe l'essentiel, mais un cout qu'on ne mesure pas est
;; un cout qu'on decouvre chez lui.
```

## [NOTE-238] INIT — resolution des chaines DEPUIS LE RIG. Le moteur ne porte aucun nom de joint : il parcour

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ------------------------------------------------------------------------------------------------
;; INIT — resolution des chaines DEPUIS LE RIG. Le moteur ne porte aucun nom de joint : il parcourt
;; les joints du squelette HD, demande au magasin C++ le role de chaque NOM, et se construit ses
;; chaines. Une chaine absente du fichier de donnees n'existe pas ; un joint absent du rig non plus.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-237] le triedre de SPEC 24/29 se classe lui aussi a la premiere frame utile, sur

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; le triedre de SPEC 24/29 se classe lui aussi a la premiere frame utile, sur
                    ;; la pose retargetee : un slot reutilise doit le reclasser, sinon la chaine
                    ;; heriterait de l'orientation d'un autre acteur. Les trois facteurs partent a
                    ;; 1.0 — l'isotropie stricte — de sorte qu'une chaine non classee integre
                    ;; exactement ce qu'elle integrait avant que ce bloc n'existe.
```

## [NOTE-236] PREUVE D'EXECUTION (regle 0) : un zero silencieux au parseur C++ ou a la

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                      ;; PREUVE D'EXECUTION (regle 0) : un zero silencieux au parseur C++ ou a la
                      ;; garde `param_id < kPhysNumChainParams` ferait retomber la borne de SPEC 22
                      ;; sur l'os — 1.62x trop large — sans qu'aucun chiffre ne le dise. La ligne ne
                      ;; s'imprime que pour les chaines qui portent la cle : son absence est une
                      ;; mesure. L'os se lit a cote, sur `PHYSBONE`, a l'execution.
```

## [NOTE-235] --- 2 ter. SPEC 18 : les echantillons de surface, resolus vers des joints ---

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                  ;; --- 2 ter. SPEC 18 : les echantillons de surface, resolus vers des joints ---
                  ;; Meme forme que les colliders juste apres : on lit ce que le C++ expose et on
                  ;; resout les NOMS d'os vers des index du rig porteur. Un ensemble dont l'os
                  ;; n'existe pas sur ce rig est de la surface qui n'a jamais pu se lier : il est
                  ;; COMPTE, jamais avale en silence.
```

## [NOTE-234] --- 3a bis. CE QUE CHAQUE VOLUME EST, pour l'instantane de Jacobi et pour la

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; --- 3a bis. CE QUE CHAQUE VOLUME EST, pour l'instantane de Jacobi et pour la
                    ;; --- priorite (DECISION 1). Deux proprietes STRUCTURELLES, lues sur le rig et
                    ;; --- sur les chaines deja chargees : aucune donnee nouvelle, aucun flag.
                    ;; ---   csim : ce volume est-il porte par un joint qu'une chaine SIMULE ?
                    ;; ---   cdep : la profondeur RIG du plus proche de la racine de ses deux joints.
```

## [NOTE-233] L'OS N'EXISTE PAS DANS LE MODELE : le joint est confondu avec son attache, donc

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
               ;; L'OS N'EXISTE PAS DANS LE MODELE : le joint est confondu avec son attache, donc
               ;; « tourner autour d'elle a longueur invariante » n'a pas de sens — la sphere est un
               ;; point et le lien serait EPINGLE. C'est exactement ce qui avait tue LpantFlap.
               ;; Ce lien-la garde le seul plafond que la geometrie lui donne : SA PROPRE TAILLE,
               ;; le rayon que le mesh lui mesure. Compte et publie comme le limiteur qu'il est.
```

## [NOTE-232] LE PRIX DU SUPPRESSEUR, PAR CHAINE. SPEC 7 : « on en ajoute un uniquement

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                     ;; LE PRIX DU SUPPRESSEUR, PAR CHAINE. SPEC 7 : « on en ajoute un uniquement
                     ;; si un defaut mesure l'exige, et on chiffre COMBIEN DE MOUVEMENT IL
                     ;; RETIRE ». La somme existait deja mais GLOBALE (`*phys-raddrop-sum*`) :
                     ;; elle ne pouvait donc designer aucune chaine, et le prix du mur n'a jamais
                     ;; pu etre mis en face du mouvement qu'il coute.
```

## [NOTE-231] ---- DECISION 1 : QUI DECIDE POUR CE LIEN, CETTE FRAME ----------------------------

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
            ;; ---- DECISION 1 : QUI DECIDE POUR CE LIEN, CETTE FRAME ----------------------------
            ;; Une passe de SELECTION, sur la position d'entree du lien, avant toute poussee : elle
            ;; ne deplace rien, elle designe. Le round-robin qu'elle remplace faisait sortir le lien
            ;; d'un volume pour l'enfoncer dans le voisin a l'iteration suivante, et le recul
            ;; finissait par l'epingler sur la pose du modele (kneeflapR, 15913 frames sur 17893).
```

## [NOTE-230] [NOTE-97] L'INSTRUMENT DU CYCLE 36 : `cl` est le module de la somme

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                            ;; [NOTE-97] L'INSTRUMENT DU CYCLE 36 : `cl` est le module de la somme
                            ;; VECTORIELLE ci-dessus. On releve a cote le COMPTE des evenements, le
                            ;; plus GRAND seul, la somme de leurs MODULES et l'ordinal du dernier
                            ;; balayage — les quatre grandeurs qui separent une repetition d'un
                            ;; ping-pong et d'un contact reellement profond. Aucune ne modifie rien.
```

## [NOTE-229] `buried` = le lien est entierement dans ce volume A SA POSE DE MODELE. Depuis le

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                ;; `buried` = le lien est entierement dans ce volume A SA POSE DE MODELE. Depuis le
                ;; 2026-08-12 c'est une MESURE et plus une DECISION : elle ne dispense plus la paire
                ;; d'etre contrainte (cf. phys-vol-floor, branche FREE retiree). Le nombre reste
                ;; publie parce que c'est lui qui a designe `goggles-tunnel` — mais il ne commande
                ;; plus rien, et l'instrument de mesure cesse d'etre l'instrument de derogation.
```

## [NOTE-228] QUEL VOLUME PORTE LE PIRE RESIDU. `meshpen` ne publiait qu'un MAXIMUM, donc le

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                ;; QUEL VOLUME PORTE LE PIRE RESIDU. `meshpen` ne publiait qu'un MAXIMUM, donc le
                ;; cycle suivant repartait sans savoir CONTRE QUOI. On garde le max de la fenetre
                ;; (17) et l'indice du volume qui le porte (18) : c'est l'argmax, pas une moyenne.
                ;; `*phys-buried-tally*` : MEME drapeau que `buried` et `*phys-cvh*`, pour la
                ;; MEME raison — cet argmax est un diagnostic PAR FRAME, et la sonde du controle
                ;; positif ([NOTE-155]) fait une seconde passe de mesure qui le polluerait. Aucun
                ;; changement de comportement aujourd'hui : `phys-pen-chain` est le seul appelant a
                ;; `prio` = 0 et il pose le drapeau autour de sa boucle.
```

## [NOTE-227] [NOTE-161] CONTROLE D'INTEGRITE, REDEFINI AVEC LA GRANDEUR. Un sommet

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                            ;; [NOTE-161] CONTROLE D'INTEGRITE, REDEFINI AVEC LA GRANDEUR. Un sommet
                            ;; de peau EXTREMAL est DEHORS a la pose d'auteur — c'est la definition
                            ;; d'un sommet de surface. Ce compte n'est donc plus une anomalie ici,
                            ;; il devient le DOMAINE : il dit combien d'echantillons se comportent
                            ;; comme de la surface. Il est publie tel quel, sans en tirer de verdict.
```

## [NOTE-226] LE PAS — appele depuis do-joint-math! de jak-hd, APRES fill-jak-hd-bones!. A cet instant le

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ------------------------------------------------------------------------------------------------
;; LE PAS — appele depuis do-joint-math! de jak-hd, APRES fill-jak-hd-bones!. A cet instant le
;; squelette porte la pose retargetee complete en espace MONDE (jak-hd.gc:551-556), et rien ne l'a
;; encore lue : bones-mtx-calc-execute (drawable.gc:895) vient bien plus tard dans la frame.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-225] L'INVARIANT EXTERNE QUI NOMME LE LATERAL — voir la note de `*phys-axsep*`.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                        ;; L'INVARIANT EXTERNE QUI NOMME LE LATERAL — voir la note de `*phys-axsep*`.
                        ;; On cherche l'AUTRE chaine de famille A pendue a la MEME ancre : c'est le
                        ;; sein oppose, et le segment qui va de l'un a l'autre est lateral par
                        ;; anatomie, pas par convention de rig. Rien ici ne suppose une orientation
                        ;; de modele, un nom d'os ni un ordre d'axes.
```

## [NOTE-224] 28 = la SOMME de `perr`. Le maximum seul ne separe pas « un

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                     ;; 28 = la SOMME de `perr`. Le maximum seul ne separe pas « un
                                     ;; seul instant » de « toutes les frames », et c'est
                                     ;; exactement la question : un champ de contact permanent
                                     ;; deplace la particule a CHAQUE frame, un saut de fenetre une
                                     ;; seule fois. `28/27` rend la moyenne.
```

## [NOTE-223] SPEC 23 — AMORCAGE DU POINT LIBRE, une seule fois par MAILLON.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                 ;; SPEC 23 — AMORCAGE DU POINT LIBRE, une seule fois par MAILLON.
                                 ;; Il part exactement de l'etat de l'apex : meme position, meme
                                 ;; vitesse verlet. Donc a la premiere frame l'elongation radiale
                                 ;; qu'il produit vaut ZERO, et §9 (« retour EXACT a la pose
                                 ;; d'auteur ») est preservee par construction et non par reglage.
```

## [NOTE-222] §22 SUR LE COM, ET C'EST UNE AUTRE BANDE QUE CELLE DE

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                        ;; §22 SUR LE COM, ET C'EST UNE AUTRE BANDE QUE CELLE DE
                                        ;; L'APEX : « Breast COM: normal <= 35 % B0, hard transient
                                        ;; <= 40 % B0 » contre « distal/apex: 42 % / 50 % ». Meme
                                        ;; construction que `kn`/`cpp`, deux bandes parce que sa
                                        ;; spec en donne deux.
```

## [NOTE-221] ---- 2. LES CONTRAINTES. Gauss-Seidel : longueur puis collision, puis des

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; ---- 2. LES CONTRAINTES. Gauss-Seidel : longueur puis collision, puis des
                    ;; ---- balayages de collision seuls pour finir — la collision est la contrainte
                    ;; ---- dure de la SPEC 3, c'est donc elle qui doit etre exacte a la fin.
                    ;; ETAGE 0 du gradient : l'angle tel que L'INTEGRATION SEULE le produit, avant
                    ;; qu'aucune contrainte n'ait touche le maillon. Voir la note de `*phys-la0*`.
```

## [NOTE-220] ---- 3. L'INJECTION DE DEFAUT A DEMENAGE — [NOTE-155]. Elle etait ICI, EN

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; ---- 3. L'INJECTION DE DEFAUT A DEMENAGE — [NOTE-155]. Elle etait ICI, EN
                    ;; ---- PLACE, donc elle CONTAMINAIT l'etat : `*phys-px*` est la position portee
                    ;; ---- d'une frame a l'autre (Verlet), pas une variable de frame. Les deux
                    ;; ---- branches du controle ne comparaient donc pas deux mesures mais deux
                    ;; ---- TRAJECTOIRES. Elle est desormais une SONDE appariee, sur la meme frame,
                    ;; ---- avec restauration au bit — voir le site de mesure plus bas.
```

## [NOTE-219] --- ancrage de la racine (SPEC 2). Deux residus, on garde le pire :

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                      ;; --- ancrage de la racine (SPEC 2). Deux residus, on garde le pire :
                      ;;      a) de combien la RACINE ecrite s'ecarte de la racine du modele
                      ;;         (identiquement nul sur un lien rootlock : il n'est pas ecrit) ;
                      ;;      b) de combien le PREMIER LIEN LIBRE s'ecarte de la longueur que le
                      ;;         modele donne a son os — son attache est l'ancre quand il est seul.
```

## [NOTE-218] MEME FORME QUE LE MODE PRINCIPAL, a la lettre : la trainee ne

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                 ;; MEME FORME QUE LE MODE PRINCIPAL, a la lettre : la trainee ne
                                 ;; porte que l'ANCIENNE vitesse, la force et l'excitation
                                 ;; s'ajoutent apres. Ecrire `kd2 * (v - k2 m)` amortirait aussi la
                                 ;; force et le mode secondaire ne serait plus le meme oscillateur
                                 ;; que celui dont sa §36 donne zeta.
```

## [NOTE-217] SPEC 37 — « artificial transforms must not generate

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                             ;; SPEC 37 — « artificial transforms must not generate
                                             ;; physical impulses » : au-dela d'un demi-radian en une
                                             ;; frame ce n'est plus une rotation du buste, c'est un
                                             ;; teleport ou une coupe. On REBASE (la reference suit)
                                             ;; au lieu d'injecter le saut.
```

## [NOTE-216] §23 — LA PRESSION DE CONTACT, CINQUIEME ET DERNIER TERME DE SA LISTE.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                            ;; §23 — LA PRESSION DE CONTACT, CINQUIEME ET DERNIER TERME DE SA LISTE.
                            ;; La poussee cumulee de la frame est deja calculee pour §33/34 : on la
                            ;; reutilise, aucune grandeur nouvelle n'est inventee. Le tissu s'aplatit
                            ;; LE LONG DE LA NORMALE et se redistribue sur les deux perpendiculaires,
                            ;; determinant exactement 1. Un contact nul ne change rien au bit pres.
```

## [NOTE-215] QUEL MAILLON porte ce maximum. Les deux ecrivent le MEME

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                                        ;; QUEL MAILLON porte ce maximum. Les deux ecrivent le MEME
                                        ;; emplacement 23, et leurs bras de levier n'ont rien de
                                        ;; comparable (1.08 B0 contre 0.86 B0 pour des os de 1.73 et
                                        ;; 0.23 B0) : sans cette colonne l'attribution ne designe
                                        ;; aucune piece, et le correctif de l'etape 2 non plus.
```

## [NOTE-214] ---- L'INSTANTANE QUE LA FRAME SUIVANTE LIRA -------------------------------------

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
          ;; ---- L'INSTANTANE QUE LA FRAME SUIVANTE LIRA -------------------------------------
          ;; Ici, et nulle part ailleurs : toutes les chaines ont ecrit, la propagation aux
          ;; descendants non simules est faite, donc le squelette porte l'etat FINAL de la frame.
          ;; C'est cet etat-la que les 22 chaines liront toutes ensemble la frame prochaine, au
          ;; lieu de lire chacune un etat different selon son rang.
```

## [NOTE-213] CE QUE LES LIMITEURS ONT RETIRE, en unites de jeu (SPEC 7 : un suppresseur se chiffre).

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; CE QUE LES LIMITEURS ONT RETIRE, en unites de jeu (SPEC 7 : un suppresseur se chiffre).
;; 11/12 = le MUR du point libre de §21/§22 (identite stricte sous 0.336 B0, donc un zero ici veut
;; dire que le tissu n'est jamais sorti de sa bande, pas que le mecanisme est absent).
;; which 0 = recul vers la pose du modele : nombre de fois / total retire
;;       2 = plafond de taille d'un lien seul : nombre de fois / total retire
```

## [NOTE-256] SPEC 18 — les echantillons de SURFACE du mesh skinne. Le C++ les parse depuis

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; SPEC 18 — les echantillons de SURFACE du mesh skinne. Le C++ les parse depuis
;; `recharged_assets/physics_mesh.txt` (prefixe `bs`) et les expose depuis toujours ; aucune ligne
;; de GOAL ne les appelait. Le consommateur avait existe (bdd5d07d9c) et le depart propre l'a
;; emporte avec les 6000 lignes de suppresseurs — on reimplemente, on ne recupere pas de bloc.
```

## [NOTE-255] TAILLES. Un slot = un compagnon HD vivant. Keira seule aujourd'hui, mais le jeu peut porter

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ------------------------------------------------------------------------------------------------
;; TAILLES. Un slot = un compagnon HD vivant. Keira seule aujourd'hui, mais le jeu peut porter
;; quatre compagnons (jak/daxter/keira/samos) et le moteur ne doit pas se marcher dessus.
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-254] LE FACTEUR DE RAIDEUR PAR LIGNE DE LA MATRICE DE L'ANCRE, `1/mobilite` de sa §29. Il reste a 1.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; LE FACTEUR DE RAIDEUR PAR LIGNE DE LA MATRICE DE L'ANCRE, `1/mobilite` de sa §29. Il reste a 1.0
;; sur les trois lignes tant qu'aucun triedre n'a pu etre classe : la mise a jour par axe redevient
;; alors la mise a jour scalaire d'avant, BIT POUR BIT, au lieu de pousser dans une direction
;; arbitraire. C'est aussi ce qui fait que les 20 chaines gelees ne changent pas d'un bit.
```

## [NOTE-253] LA DIRECTION DE LA GRAVITE TELLE QUE LE SOLVEUR LA VOIT, dans le triedre de sa §7 : c'est

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; LA DIRECTION DE LA GRAVITE TELLE QUE LE SOLVEUR LA VOIT, dans le triedre de sa §7 : c'est
;; l'ENTREE de §10-13, et elle est publiee a cote de la sortie. Sans elle, une forme mesuree ne
;; peut pas etre rattachee a l'orientation qui l'a produite — et c'est l'orientation VUE, jamais
;; celle que la salle croit avoir commandee.
```

## [NOTE-252] tolerance de l'identite « position ecrite - pose d'auteur == ecart simule remis dans le monde »

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; tolerance de l'identite « position ecrite - pose d'auteur == ecart simule remis dans le monde »,
;; en unites de jeu. Les deux membres valent ~1e2 unites et une rotation de flottant 32 bits y laisse
;; ~1e-5. 0.05 u (12 micrometres) est trois mille fois au-dessus de ce bruit et vingt fois en dessous
;; du plus petit deplacement d'auteur detectable (1 u) : la fenetre est large des deux cotes.
```

## [NOTE-251] injection de defaut pour le CONTROLE POSITIF (SPEC 7 : tout zero exige un controle qui a fait

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; injection de defaut pour le CONTROLE POSITIF (SPEC 7 : tout zero exige un controle qui a fait
;; MONTER le compteur). 0 = desarme. > 0 = chaque lien libre est pousse de N unites vers l'interieur
;; du corps APRES la resolution : la penetration residuelle doit alors exploser. La salle arme,
;; mesure, desarme.
```

## [NOTE-250] [NOTE-161] LES SOMMETS DE PEAU DE CHAQUE MAILLON, espace bind local a l'os, unites de jeu.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; [NOTE-161] LES SOMMETS DE PEAU DE CHAQUE MAILLON, espace bind local a l'os, unites de jeu.
;; C'est la SURFACE de l'organe simule — celle que `bs` ne peut pas contenir, puisqu'il exclut par
;; construction tout os qui est un maillon de chaine. 8 au plus : le C++ empaquete l'indice
;; d'echantillon sur 3 bits.
```

## [NOTE-249] [NOTE-241] SPEC 33/34 — LA NON-TRAVERSEE EST DEVENUE UNE CONTRAINTE, PLUS SEULEMENT UNE MESURE.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; [NOTE-241] SPEC 33/34 — LA NON-TRAVERSEE EST DEVENUE UNE CONTRAINTE, PLUS SEULEMENT UNE MESURE.
;; `*phys-sdn*` : normale sortante du plus proche echantillon de `bs`, ecrite par `phys-surf-sd`.
;; `*phys-skin-off*` : 1 = contrainte DESARMEE (la jambe d'ablation de la salle, controle positif).
;; Les trois compteurs CHIFFRENT ce que la contrainte retire — un correctif qui enleve du mouvement
;; se declare avec son cout, il ne se glisse pas.
```

## [NOTE-248] SPEC 37 « rebase on teleportation / level transition » : le degre de liberte

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; SPEC 37 « rebase on teleportation / level transition » : le degre de liberte
                    ;; radial est un ETAT, il repart donc de zero comme la torsion et le mode
                    ;; secondaire. Un tissu qui garderait son elongation a travers un respawn
                    ;; violerait §9 des la premiere frame.
```

## [NOTE-247] [NOTE-161] LES SOMMETS DE PEAU DU MAILLON. Meme cycle de vie que les

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                      ;; [NOTE-161] LES SOMMETS DE PEAU DU MAILLON. Meme cycle de vie que les
                      ;; rayons ci-dessus, meme fichier, meme convention milli. Zero echantillon =
                      ;; la mesure de surface compte ce maillon HORS de son domaine, jamais comme
                      ;; un maillon propre.
```

## [NOTE-246] --- 3b. LE VOLUME QUE CHAQUE LIEN PORTE. Par defaut sa demi-epaisseur,

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; --- 3b. LE VOLUME QUE CHAQUE LIEN PORTE. Par defaut sa demi-epaisseur,
                    ;; --- centree sur le joint (comportement precedent). Si ce joint declare deja
                    ;; --- une SPHERE ajustee sur le mesh, c'est ELLE — centre et rayon — parce que
                    ;; --- c'est le meme morceau de corps, qu'il bouge ou qu'il soit heurte.
```

## [NOTE-245] ATTRIBUTION PAR VOLUME. On incremente d'abord tout violeur, et si le

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                          ;; ATTRIBUTION PAR VOLUME. On incremente d'abord tout violeur, et si le
                          ;; lien n'en avait qu'UN on le retire juste apres : ce seau ne compte donc
                          ;; que les volumes qui se DISPUTAIENT le lien. Une seule passe, aucune
                          ;; geometrie recalculee.
```

## [NOTE-244] DECISION 1 : les volumes que la priorite a ecartes sont IGNORES, pas

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                       ;; DECISION 1 : les volumes que la priorite a ecartes sont IGNORES, pas
                       ;; moyennes. Distinct de `own` a dessein — `own` est l'exclusion
                       ;; structurelle chaine<->elle-meme, que le controle positif `self-inject`
                       ;; leve ; celle-ci ne se leve que par `prio-off`, son propre controle.
```

## [NOTE-243] `pt` arrive en coordonnees de JOINT (c'est ce que manipulent le solveur et le recul) :

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
        ;; `pt` arrive en coordonnees de JOINT (c'est ce que manipulent le solveur et le recul) :
        ;; on le porte sur le centre du volume, comme la resolution. La pose du MODELE porte son
        ;; volume par la matrice ANIMEE, le point EVALUE le porte par SA direction : sans ca la
        ;; dichotomie du recul chercherait avec un obstacle fige sur l'animation.
```

## [NOTE-242] MEME PLANCHER QUE LE SOLVEUR, IMPOSE PAR UNE MESURE : ancre a la pose d'AUTEUR

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                     ;; MEME PLANCHER QUE LE SOLVEUR, IMPOSE PAR UNE MESURE : ancre a la pose d'AUTEUR
                     ;; il lisait un OFFSET CONSTANT (+0.0441 m, la bande SPEC 10) qui noyait le
                     ;; controle positif (POSCONTROL 0.0668/0.0440, CONE 0.0440 SOUS 0.0441). Une
                     ;; compression que la spec AUTORISE n'est pas une penetration. NOTE-55.
```

## [NOTE-241] SPEC 33/34 — LA NON-TRAVERSEE DEVIENT UNE CONTRAINTE, ET ELLE PORTE SUR LA PEAU

(cycle 61, 2026-08-20)

### CE QUI ETAIT FAUX, ET C'ETAIT DANS L'INSTRUMENT AVANT D'ETRE DANS LE SOLVEUR

Le cycle 60 a livre `skinpen` — la profondeur des sommets extremaux de peau du maillon sous la
surface du CORPS — et l'a fait juger par la gate COLLIDE contre un plancher tire de la fenetre de
REPOS (`physroom-hold`, 120 frames). La course, elle, porte sur 16 740 frames et 31 animations.
Deux populations, un rapport : `ratio-of-two-statistics`.

Le controle negatif est arithmetique et il etait DEJA dans la trace livree. `PHYSSKIN2 tag=run
skinrest` est la lecture du point que l'AUTEUR a dessine — la pose sans physique, par definition —
sur exactement la meme fenetre, les memes frames, les memes maillons, les memes echantillons et la
meme fonction que `skinpen` :

    fenetre de REPOS (120 frames)   chestL 143.64 u   chestR 203.97 u
    point d'AUTEUR sur la COURSE    chestL 268.90 u   chestR 458.05 u
    point SIMULE   sur la COURSE    chestL 430.72 u   chestR 572.43 u

Physique ENTIEREMENT desarmee, la gate aurait donc lu 268.90 et 458.05 contre un plancher de
143.64 : **elle echouait deja**. Une gate qu'aucune physique ne peut passer ne mesure pas la
physique. La gate n'a jamais bouge — c'est le tableau qui lui donnait la mauvaise colonne.

Le plancher publie est desormais la colonne d'AUTEUR de la MEME fenetre, et une garde NEUVE decide
s'il est lisible : dans la fenetre de repos, ou la physique est mesurablement au repos, la lecture
SIMULEE et la lecture d'AUTEUR doivent coincider. Mesure : 0.09 % sur chestL, 0.18 % sur chestR.
C'est ce qui prouve que la colonne d'auteur EST la colonne desarmee, au lieu de le promettre.

### LA CONTRAINTE

Le solveur contraignait le JOINT contre des CAPSULES. Sa 33 et sa 34 parlent de SURFACES qui se
traversent. `phys-skin-chain` contraint donc les SOMMETS DE PEAU contre la SURFACE, avec la MEME
fonction que l'instrument : on contraint ce qu'on mesure.

Le sommet de peau est un decalage RIGIDE du joint (la rotation appliquee a l'offset est celle de
l'os d'AUTEUR des deux cotes), donc la lecture a la pose d'auteur vaut

    sa = sd - dot(dj, nrm)          dj = joint simule - joint d'auteur

sans seconde recherche. La correction est

    v = min( -sd , -dot(dj, nrm) )     appliquee si v > 0, le long de `nrm`

et chacun des deux termes dit un refus : **jamais plus loin que la surface**, **jamais plus que la
part RENTRANTE du deplacement**. Trois consequences qui sont des garanties, pas des intentions :

  1. a la pose d'auteur `dj` = 0 donc `v` <= 0 : la contrainte est INERTE AU BIT au repos. SPEC 2/9
     et la gate IDLE ne peuvent pas la voir bouger, et ce n'est pas un reglage, c'est l'algebre ;
  2. elle ne peut JAMAIS tirer un sein plus DEHORS que la ou l'auteur l'a mis ;
  3. elle borne la mesure qu'elle vise : `skinpen <= skinrest` sur la fenetre, par construction.

La poussee est TANGENTIELLE a la sphere de l'attache, comme celle des volumes, et la reprojection
de longueur suit : `ROOM-STRETCH` reste exact. Elle entre dans `*phys-cpu*` avec la restitution de
sa 34 (0.02), donc une contrainte de position ne devient pas de la vitesse verlet.

ELLE EST LA DERNIERE OPERATION DE POSITION DE LA FRAME, apres la boucle `collide`/`bend` : c'est
l'invariant que le dossier prescrit a trois endroits et que l'ordre `collide` puis `bend` ne tenait
plus depuis le cycle 43. On l'obtient ici sans echanger deux lignes du solveur — la contrainte qui
ferme la frame est celle qui parle de la grandeur que la spec nomme.

### VERDICT DU CYCLE : ELLE EST LIVREE **DESARMEE**, ET C'EST LA MESURE QUI L'INTERDIT

Trois mesures independantes, toutes de la meme course, condamnent l'armement :

  1. **AU REPOS, ELLE DETRUIT SPEC 2/9.** `PHYSIDLE c=0 dev=331.90 amp=242.37` contre `dev=0.95
     amp=0.00` sans elle : chestL s'ecarte de 8.1 cm de la pose d'auteur et OSCILLE a 6 cm
     d'amplitude dans une fenetre ou l'animation est figee. « No additional sag shall be applied
     merely because the simulation is active » — c'est exactement ce qu'elle fait.
  2. **LA GARDE DE CALIBRATION QUE J'AI ECRITE A TIRE CONTRE ELLE.** Dans la fenetre de repos la
     lecture SIMULEE et la lecture d'AUTEUR doivent coincider : elles sont a 38.51 % sur chestL
     (0.0216 contre 0.0351) et a 0.00 % sur chestR. Le plancher est refuse, donc la gate reste
     NON ETABLI — l'instrument refuse de se certifier lui-meme, ce qui est le comportement voulu.
  3. **ELLE NE FERME PAS.** `reste` — la pire violation qui SURVIT aux six passes, mesuree par une
     7e passe qui ne corrige pas — vaut exactement `skinpen` : 466.65 u sur chestR. Sur le sommet
     qui porte le maximum, la correction n'agit pas du tout.

LA CAUSE EST COMMUNE AUX TROIS, ET ELLE EST DANS LA DONNEE, PAS DANS LA CONTRAINTE. `phys-surf-sd`
est DISCONTINUE a une echelle de plusieurs CENTAINES d'unites : au repos, deux requetes distantes
de moins d'une unite (le point d'auteur et le point simule) tombent dans des cellules differentes
du nuage et rendent des lectures separees de centaines d'unites. Une contrainte de position pilotee
par un champ discontinu a l'echelle qu'elle doit arbitrer produit un cycle limite — c'est ce que
`amp=242` est.

Et la discontinuite se demontre : `sd = dot(p - q, n)` avec `|n| = 1`, donc `|sd| <= |p - q|`. Une
profondeur lue de 501.68 u EXIGE que le plus proche echantillon de toute la surface du corps soit a
plus de 12.2 cm. C'est un TROU, pas une penetration. Mesure du nuage livre : 1071 echantillons,
92 ensembles, et **84 des 92 sont exactement au plafond `BSURF_MAX = 12`** — `bs chest` porte
12 points pour une envergure de 65 cm.

Le chantier est donc la DENSITE de la surface, pas le solveur. La contrainte reste au dossier,
desarmee, avec sa jambe d'ablation : elle se rearmera quand la surface pourra la porter.

### CE QU'ELLE COUTE, ET COMMENT ON LE SAIT

`*phys-skin-off*` la desarme. La salle joue les deux jambes sur les 31 animations
(`PHYSROOM-PH-SKINARM` 34 / `PHYSROOM-PH-SKINDIS` 35, appendues apres PH-SYM, donc aucune ligne
existante ne peut changer de valeur a cause d'elles). Desarmee, `skinpen` doit REMONTER.
`PHYSSKINC` publie le nombre de corrections, leur cumul et la pire : un correctif qui enleve du
mouvement se chiffre.

## [NOTE-290] la direction MONDE des trois lignes du triedre de l'ancre, normalisee : `sc*9 + ligne*3 + comp`

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; la direction MONDE des trois lignes du triedre de l'ancre, normalisee : `sc*9 + ligne*3 + comp`.
;; C'est ce qui permet a la salle d'EXCITER un axe du solveur au lieu d'un axe monde — voir la note
;; du site d'ecriture, et la mesure qui l'a rendue necessaire.
```

## [NOTE-289] Frames ou la borne §22 du COM a effectivement mordu. Un limiteur qui mord en PERMANENCE ne

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; Frames ou la borne §22 du COM a effectivement mordu. Un limiteur qui mord en PERMANENCE ne
;; borne plus, il remplace la mesure par sa propre valeur — c'est ce qui vient d'arriver au canal
;; de deformation (25.00 sur les dix fenetres). On le compte, exactement comme `*phys-twsat*`.
```

## [NOTE-288] SPEC 33/34 — la poussee de contact CUMULEE sur la frame et le coefficient du volume qui a

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; SPEC 33/34 — la poussee de contact CUMULEE sur la frame et le coefficient du volume qui a
;; decide. La restitution ne peut pas s'appliquer dans `phys-collide-chain` : elle y serait
;; appliquee jusqu'a 15 fois par frame (8 + 3 + 4 balayages). Elle s'applique UNE fois, apres.
```

## [NOTE-287] somme, sur TOUTE la course, du deplacement MONDE de la pose d'auteur de la pointe. Une chaine d

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; somme, sur TOUTE la course, du deplacement MONDE de la pose d'auteur de la pointe. Une chaine dont
;; ce nombre est nul pendant que le personnage est secoue n'est pas attachee au personnage : c'est la
;; seconde preuve, independante du rapport de distance, qu'un joint a ete envoye ailleurs.
```

## [NOTE-286] frames, sur toute la course, ou cette chaine avait au moins une paire (lien, volume) EN CONTACT

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; frames, sur toute la course, ou cette chaine avait au moins une paire (lien, volume) EN CONTACT.
;; Publie a cote de la penetration : un zero sur une chaine qui n'a jamais rien touche ne dit pas la
;; meme chose qu'un zero sur une chaine qui a frotte le crane pendant 3000 frames.
```

## [NOTE-285] seuil de detection, en unites de jeu par frame (4096 u = 1 m). Un os que l'anim ne touche pas n

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; seuil de detection, en unites de jeu par frame (4096 u = 1 m). Un os que l'anim ne touche pas ne
;; bouge PAS dans ce repere : le seuil separe l'intention du bruit numerique de la cascade de
;; matrices, il ne filtre aucun mouvement reel.
```

## [NOTE-284] SPEC 10 `SupineProjectionScale = 0.70` : la projection avant perd 30 % contre le thorax. BANDE 

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; SPEC 10 `SupineProjectionScale = 0.70` : la projection avant perd 30 % contre le thorax. BANDE que
;; la chair cede avant que le mur ne redevienne dur, en B0 (SPEC 6 : 602 u de CHAIR, pas l'os). Elle
;; ne se regle pas, sa spec l'ecrit. Voir `phys-vol-floor` / `phys-vol-yield`.
```

## [NOTE-283] RE-ASSISES : liens dont la pose du modele est hors de portee de leur porteur et que le moteur

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; RE-ASSISES : liens dont la pose du modele est hors de portee de leur porteur et que le moteur
;; replace sur lui. Owner/superviseur 2026-08-11 : « pantflapL retablie — elle avait ete supprimee du
;; fichier au lieu d'etre REPAREE ».
```

## [NOTE-282] COMBIEN DE FOIS LA PROFONDEUR A ETE POUSSEE TANGENTIELLEMENT DANS LA BOUCLE DE FINITION.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; COMBIEN DE FOIS LA PROFONDEUR A ETE POUSSEE TANGENTIELLEMENT DANS LA BOUCLE DE FINITION.
;; Regle 0 : le correctif ci-dessous ne se prouve pas par son commentaire. Ce compteur dit qu'il a
;; TIRE, et `PHYSTAN` le publie ; a zero, le bloc n'a jamais ete atteint et le tableau ment.
```

## [NOTE-281] ... et combien de ces re-assises ont du retomber sur l'ancienne heuristique (rayon le long de

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ... et combien de ces re-assises ont du retomber sur l'ancienne heuristique (rayon le long de
;; l'os du porteur) faute de bind-pose lisible. Doit valoir ZERO : un secours silencieux est un
;; defaut qui attend, et c'est celui-la qui posait le pan du pantacourt dans le mollet.
```

## [NOTE-280] [NOTE-157] `skinpen = 0` veut dire DEUX choses — « le lien est dehors » et « aucun echantillon

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; [NOTE-157] `skinpen = 0` veut dire DEUX choses — « le lien est dehors » et « aucun echantillon
;; n'etait a portee ». Ce compte les separe, PAR CHAINE. Sans lui, un plancher de repos a 0.0000
;; se lit comme une mesure alors que c'est un trou.
```

## [NOTE-279] petits utilitaires

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; ------------------------------------------------------------------------------------------------
;; petits utilitaires
;; ------------------------------------------------------------------------------------------------
```

## [NOTE-278] SPEC 37 — « rebase on teleportation / level transition ». Un slot reutilise

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; SPEC 37 — « rebase on teleportation / level transition ». Un slot reutilise
                    ;; redemande TOUTES ses references : triedre, torsion, mode secondaire. Un etat
                    ;; qui survit a un respawn est un etat qui vieillit, et sa spec l'interdit.
```

## [NOTE-277] la direction de repos du materiau se releve a la premiere frame utile, sur la

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; la direction de repos du materiau se releve a la premiere frame utile, sur la
                    ;; pose retargetee : un slot reutilise doit la redemander, sinon la chaine
                    ;; heriterait du repos d'un autre acteur.
```

## [NOTE-276] le rayon englobant vient des echantillons RETENUS, jamais du

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                               ;; le rayon englobant vient des echantillons RETENUS, jamais du
                               ;; nombre declare : un prefixe ne peut alors que le RETRECIR, et
                               ;; jamais revendiquer une portee qu'il n'a pas.
```

## [NOTE-275] PREUVE D'EXECUTION (regle 0) : sans cette ligne, un fichier absent, un

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; PREUVE D'EXECUTION (regle 0) : sans cette ligne, un fichier absent, un
                    ;; parseur muet ou un rig sans ces os rendraient la mesure identiquement nulle
                    ;; et indistinguable d'une peau que rien ne traverse.
```

## [NOTE-274] `w` porte la DISTANCE a l'axe. Elle est deja calculee ici ; la jeter obligeait

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
         ;; `w` porte la DISTANCE a l'axe. Elle est deja calculee ici ; la jeter obligeait
         ;; l'appelant a la recalculer ou a se rabattre sur une constante. C'est elle qui chiffre
         ;; « de combien le lien est passe du mauvais cote », en metres, sans terme invente.
```

## [NOTE-273] CONTROLE POSITIF DU PREDICAT CONIQUE : 1 = on REMET le rayon interpole sur le parametre de

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
;; CONTROLE POSITIF DU PREDICAT CONIQUE : 1 = on REMET le rayon interpole sur le parametre de
;; projection, c'est-a-dire le predicat faux d'avant. Ce qu'il rend au systeme est la difference
;; exacte entre le solide que la ligne de donnees DESIGNE et l'ensemble que le moteur TESTAIT.
```

## [NOTE-272] part radiale prise sur le VECTEUR perpendiculaire, pas par |p|^2 - x^2 : la

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
              ;; part radiale prise sur le VECTEUR perpendiculaire, pas par |p|^2 - x^2 : la
              ;; soustraction de deux grands nombres presque egaux perd ses chiffres quand le
              ;; point est pres de l'axe, c'est-a-dire exactement le cas qui decide.
```

## [NOTE-271] CAS DEGENERE : le lien s'est confondu avec son attache, la direction n'existe

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
               ;; CAS DEGENERE : le lien s'est confondu avec son attache, la direction n'existe
               ;; plus. Se taire ici laissait le lien se restabiliser n'importe ou, y compris du
               ;; mauvais cote — on REPART de la direction du modele.
```

## [NOTE-270] `atan` de GOAL rend des UNITES DE ROTATION (65536 = un tour) ;

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                         ;; `atan` de GOAL rend des UNITES DE ROTATION (65536 = un tour) ;
                         ;; 360/65536 = 0.0054931641 les convertit en degres, et 182.04444
                         ;; revient aux unites que `sin`/`cos` attendent.
```

## [NOTE-269] les deux azimuts du veto de cote : celui de la pose d'auteur et celui du lien simule.

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
        ;; les deux azimuts du veto de cote : celui de la pose d'auteur et celui du lien simule.
        ;; Memes noms et meme role que dans `phys-link-pen` (:2513-2514), pour que le predicat de
        ;; DECISION se lise exactement comme le predicat de MESURE.
```

## [NOTE-268] ARMEE (prio-off = 0) elle DESIGNE et ses compteurs comptent ; en mesure seule

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
            ;; ARMEE (prio-off = 0) elle DESIGNE et ses compteurs comptent ; en mesure seule
            ;; (prio-meas = 1) elle ne fait que COMPTER, et `*phys-lwin*` est rendu a -1 juste
            ;; apres, donc rien n'est ecarte. Voir *phys-prio-meas*.
```

## [NOTE-267] `sc` PORTE DEJA LE SLOT (`sc = slot*PHYS-CHAINS + c`, cf. :922) : le

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                          ;; `sc` PORTE DEJA LE SLOT (`sc = slot*PHYS-CHAINS + c`, cf. :922) : le
                          ;; remultiplier ecrirait HORS du tableau des le slot 1. Meme indexation
                          ;; que l'accesseur `phys-chain-conf`. `*phys-cvh*` est, LUI, PAR MAILLON.
```

## [NOTE-266] `floor0` contre le volume A SA POSE D'AUTEUR, `dep` contre sa position

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; `floor0` contre le volume A SA POSE D'AUTEUR, `dep` contre sa position
                    ;; COURANTE : le plancher de pose modele est une propriete de la pose du
                    ;; modele des DEUX cotes (cf. phys-snapshot-colliders!).
```

## [NOTE-265] --- (a2) LE FRANCHISSEMENT D'AXE. Deux conditions, pas une : la pose

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                          ;; --- (a2) LE FRANCHISSEMENT D'AXE. Deux conditions, pas une : la pose
                          ;; --- d'AUTEUR doit etre dans le volume pour que « de quel cote » ait un
                          ;; --- sens pour elle, ET le maillon SIMULE doit y etre aussi.
```

## [NOTE-264] LA 7e PASSE NE CORRIGE PAS, ELLE MESURE : `*phys-skc-r*` est la pire

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                    ;; LA 7e PASSE NE CORRIGE PAS, ELLE MESURE : `*phys-skc-r*` est la pire
                    ;; violation qui SURVIT aux six passes. C'est la contrainte qui se juge
                    ;; elle-meme — si elle ne ferme pas, ce chiffre le dit avant la gate.
```

## [NOTE-263] compte une fois par frame (le meme drapeau que `buried` : `phys-pen-chain`

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                  ;; compte une fois par frame (le meme drapeau que `buried` : `phys-pen-chain`
                  ;; l'arme, le recul ne l'arme pas, donc les 3 reculs et leurs 13 pas de
                  ;; dichotomie ne comptent pas).
```

## [NOTE-262] QUEL VOLUME CONTRAINT QUEL MAILLON. Compte les paires (lien, volume) en

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
                ;; QUEL VOLUME CONTRAINT QUEL MAILLON. Compte les paires (lien, volume) en
                ;; VIOLATION, pas en contact : `res > 0` veut dire que ce volume-ci demande une
                ;; correction cette frame. Un contact a profondeur nulle n'est pas une contrainte,
                ;; et le compter rendrait la colonne aveugle a la difference entre les deux.
```

## [NOTE-261] `phys-link-pen` incremente `*phys-buried-n*` SANS passer par `*phys-buried-tally*` : la

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
        ;; `phys-link-pen` incremente `*phys-buried-n*` SANS passer par `*phys-buried-tally*` : la
        ;; seconde passe de mesure de cette sonde le doublerait sur la fenetre armee, et `PHYSLIM
        ;; buried=` est publie APRES elle. On le rend a sa valeur d'entree — une sonde qui laisse
        ;; une trace dans un compteur n'est pas une sonde.
```

## [NOTE-260] la sentinelle est RENDUE TELLE QUELLE : « aucun contact » n'est pas « penetration nulle »,

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
    ;; la sentinelle est RENDUE TELLE QUELLE : « aucun contact » n'est pas « penetration nulle »,
    ;; et c'est l'appelant qui compte les deux separement. Confondre les deux, c'est annoncer un
    ;; zero mesure la ou rien n'a ete mesure.
```

## [NOTE-259] 9.81 m/s^2 dans les unites de l'integrateur : 9.81 * 4096 u/m / 3600 frames^2/s^2

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
             ;; 9.81 m/s^2 dans les unites de l'integrateur : 9.81 * 4096 u/m / 3600 frames^2/s^2
             ;; = 11.16 u/frame^2. L'ancienne valeur (-160, ENCORE multipliee par dt^2) donnait
             ;; 0.044 u/frame^2, 250 fois trop faible : la famille B ne pendait pas du tout. C'est
             ;; une erreur d'unites, pas un reglage.
```

## [NOTE-258] LA POSE D'AUTEUR DES VOLUMES, AVANT QUE LA PREMIERE CHAINE N'ECRIVE. Les chaines sont

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
        ;; LA POSE D'AUTEUR DES VOLUMES, AVANT QUE LA PREMIERE CHAINE N'ECRIVE. Les chaines sont
        ;; resolues l'une apres l'autre et chacune ecrit son joint dans le squelette : passe ce
        ;; point, `skel bones` ne porte plus la pose d'auteur pour les joints deja traites.
```

## [NOTE-257] LA POSE DU MODELE EST-ELLE PLAUSIBLE ? Une fois par chaine, a sa premiere frame, ou

(bloc deplace du moteur le 2026-08-20, cycle 61 — plafond de lignes)

```
              ;; LA POSE DU MODELE EST-ELLE PLAUSIBLE ? Une fois par chaine, a sa premiere frame, ou
              ;; le squelette porte enfin la pose retargetee. Une chaine ecartee passe a zero lien et
              ;; tout ce qui suit la saute — y compris son bloc de mesure, sinon elle publierait des
              ;; chiffres pris sur le joint d'a cote.
```

## [NOTE-242] L'ESTIMATEUR DE SURFACE DEVIENT CONTINU, ET C'EST CE QUI PERMET D'ARMER LA CONTRAINTE

(cycle 61, second temps)

### POURQUOI L'ANCIEN EST MORT

`phys-surf-sd` signait la distance par la normale du SEUL plus proche echantillon. Deux mesures
l'ont tue, et aucune n'est une opinion :

  1. `sd = dot(p-q, n)` avec `|n| = 1` donc `|sd| <= |p-q|` : une profondeur lue de 501 u EXIGE que
     le plus proche echantillon de toute la peau soit a plus de 12 cm. C'est un TROU du nuage.
  2. TEST DE RAFFINEMENT : a solveur IDENTIQUE AU BIT, en portant le nuage de 1071 a 2966
     echantillons, la lecture bougeait de **30 %**. Un point plus PROCHE dont la normale est plus
     OBLIQUE rendait une lecture plus PROFONDE : un seul mauvais echantillon decidait de tout.

### CE QUI LE REMPLACE

Moyenne des distances aux plans des `PHYS-SD-K` = 8 plus proches echantillons, ponderee par un
noyau `w = (1 - d^2/h^2)^2` dont le rayon `h` EST la distance au K-ieme voisin.

  - **CONTINUITE** : l'echantillon qui entre ou sort du K-voisinage porte un poids NUL. La valeur ne
    saute plus quand le voisinage change. C'est la propriete qui manquait.
  - **ROBUSTESSE** : un plan oblique isole est noye par ses sept voisins.
  - **AUCUNE LONGUEUR CHOISIE A LA MAIN** : `h` s'adapte a la densite locale.
  - `*phys-sdn*` rend la normale PONDEREE des memes K plans : la direction et la profondeur sortent
    de la MEME population, sinon la contrainte pousserait le long d'un plan qui n'a pas decide.

MESURE QUI L'ATTESTE, dans la fenetre de repos : chestL lit **0.0000 des deux cotes** (simule et
auteur) — un sommet EXTREMAL de peau est DEHORS, ce qui est sa definition — et chestR lit
127.16 / 127.34, soit **0.14 %** d'ecart la ou l'ancien estimateur en donnait 38.51 %.

### ET LA CONTRAINTE S'ARME, EN DEUX TEMPS QUI SONT DEUX MESURES

Armee telle quelle sur le champ continu, elle tient la borne sur la course (`skinpen` 243.91/311.50
sous des planchers de 250.79/361.84) **mais s'emballe au repos** : `PHYSIDLE c=0 dev=374 amp=544`.
Elle n'avait aucun terme la rattachant a la pose d'auteur — une poussee deplace le joint, ce
deplacement change la lecture, qui redemande une poussee.

**LE PLAFOND DE DEPLACEMENT** ferme la boucle : la physique ne peut se voir demander que de defaire
**SA PROPRE part RENTRANTE**, `-dot(dj, n)`, ou `dj` est l'ecart du joint a sa pose d'auteur PRIS A
L'ENTREE DE LA FRAME. A la pose d'auteur `dj` = 0 donc le plafond est 0 : la contrainte est INERTE
au repos par ALGEBRE, pas par reglage. Et elle est auto-limitante — pousser dehors rend `dot(dj,n)`
positif, donc le plafond retombe.

`dj` PRIS A L'ENTREE et non au fil des passes : avec le `dj` courant, chaque poussee refermait le
plafond sur la contrainte avant qu'elle ait fini (chestL restait a +41.7 u de son propre plancher ;
a l'entree, +32.5 u). Le deplacement rentrant d'une frame est une quantite DE LA FRAME.

RESULTAT : `PHYSIDLE dev` 0.5644 / 0.4881 avec `amp = 0.0000` — mieux que la course non contrainte
(0.4721 / 1.0232). SPEC 2/9 tenue.

### CE QUI RESTE OUVERT, ET IL EST PUBLIE

`reste` (la pire violation qui survit aux six passes, mesuree par une 7e qui ne corrige pas) vaut
encore 142.23 u, et **chestL reste 32.5 u au-dessus de SON PROPRE plancher** (chestR est dessous).
La gate lit le PIRE des deux planchers et passe donc ; le registre de couverture, lui, classe
§33/§34 **PARTIELLE** et pas TENUE, parce que sa regle 2 l'exige : « une seule chaine conforme =
PARTIELLE ». L'ecart de chestL (0.0079 m) est sous le plancher d'erreur miroir de l'instrument
(0.0176 m), ce qui n'en fait pas un zero — seulement une grandeur que cet instrument ne separe pas
de son propre bruit gauche/droite.

## NOTE-291  (moteur, dans `phys-skin-chain`, aux alentours de la ligne 1946)

```
[NOTE-242] LE PLAFOND DE DEPLACEMENT, ET C'EST LUI QUI EMPECHE
L'EMBALLEMENT. Sans lui la correction n'a aucun terme qui la
rattache a la pose d'auteur : une poussee deplace le joint, ce
deplacement change la lecture, qui redemande une poussee — mesure
sans lui, `PHYSIDLE c=0 dev=374 amp=544` DANS LA FENETRE DE REPOS.
La physique ne peut se voir demander que de defaire SA PROPRE part
RENTRANTE : `-dot(dj, n)`, ou `dj` est l'ecart du joint a sa pose
d'auteur. A la pose d'auteur `dj` = 0, donc le plafond est 0 et la
contrainte est INERTE — ce n'est pas un reglage, c'est l'algebre.
Et il est auto-limitant : pousser vers l'exterieur rend `dot(dj,n)`
positif, donc le plafond retombe a zero de lui-meme.
`dj` EST PRIS A L'ENTREE DE LA FRAME (`ox/oy/oz`), PAS APRES LES
PASSES DEJA APPLIQUEES. Mesure : avec le `dj` courant, chaque
poussee rend `dot(dj,n)` moins negatif, donc le plafond se referme
sur la contrainte avant qu'elle ait fini de defaire sa propre part
rentrante — chestL restait a +41.7 u au-dessus de son propre
plancher. Le deplacement RENTRANT de la frame est une quantite de
la frame : il se lit une fois, a l'entree.
```

## NOTE-296  (docstring de `phys-shape`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 8/10-13/29/36 — L'ETAT DE FORME ET DE TORSION, LU SUR LE MECANISME ARME.
   NATURE : `which` 0/1/2 = les trois ECHELLES appliquees (lateral, vertical, projection), sans
   dimension, rapport a la forme d'auteur ; 3 = leur determinant (le volume de sa §8) ; 4 = la
   modulation courante du mode secondaire de §36 (fraction d'epaisseur) ; 5 = son maximum sur la
   FENETRE ; 6 = la torsion RELATIVE ecrite dans la 3x3 (radians) ; 7 = son maximum sur la fenetre ;
   8 = 1.0 si le canal est ARME sur cette chaine, 0.0 sinon ; 9/10/11 = la direction de la GRAVITE
   vue par le solveur dans ce meme triedre (l'ENTREE de §10-13, unitaire, (0,-1,0) debout) ;
   12 = le maximum de fenetre du mode secondaire AVANT le plafond de §38 (c'est lui qui dit si le
   `0.0700` publie est une saturation ou une valeur) ; 13 = le maximum de fenetre de l'etirement
   dynamique de §22/38 ; 18 = le nombre de frames ou la saturation douce de la torsion a mordu ;
   19 = l'aplatissement de PRESSION DE CONTACT de §23 (max de fenetre), 20 = le meme AVANT plafond ;
   21 = `dl`, l'entree d'ETIREMENT, AVANT son `fmin` (max de fenetre) ; 22 = le NOMBRE de frames
   ou elle a mordu son plafond ; 23 = le meme compte pour la PRESSION ; 24 = le nombre de frames
   comptees, denominateur COMMUN aux deux — sans lui, 22 et 23 ne sont pas des parts.
   REPERE : le triedre de sa SPEC 7 (+X lateral, +Y haut, +Z avant), releve a la pose debout
   d'auteur. LECTURE HORS DEFAUT : 1.000 / 1.000 / 1.000 / 1.000 / 0 / 0 / 0 / 0 debout et immobile.
   CE QUE CE N'EST PAS : la deformation VUE sur le mesh. Un sommet partage avec le buste ne recoit
   qu'une part de cette echelle (champ de poids gradue en r^1.63, §31) ; ce nombre est ce que le
   solveur COMMANDE a la racine, et le rapport doit le dire a chaque fois qu'il le cite.
```

## NOTE-297  (docstring de `phys-chain-radial`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 23 — LE TROISIEME DEGRE DE LIBERTE, LU A L'EXECUTION. Voir la note de `*phys-rr*`.
   which 0 = elongation radiale du MAILLON RACINE en unites de jeu (signee) — le distal se lit par
             `phys-chain-radial-link` ;
         1 = la meme, rapportee a B0 (SPEC 6) — c'est la grandeur que borne sa SPEC 22
             (« local tissue elongation: common 5-15 %, large 15-21 %, exceptional 21-25 % ») ;
         2 = son maximum absolu sur la fenetre, SUR TOUS LES MAILLONS ARMES (cycle 32) ;
         3 = LE MEME MAXIMUM, MAIS AVANT LA BORNE §22 — sans lui, un canal colle a sa borne est
             indiscernable d'un canal qui l'effleure, et c'est exactement la confusion qui a laisse
             passer un plafond de deformation atteint sur les dix fenetres ;
         4 = le nombre de frames ou la borne §22 a mordu (compteur global, rendu en float).
   NATURE : une DEFORMATION signee (sans unite pour 1 et 2), pas une amplitude agregee : c'est une
   serie temporelle, et c'est ce qui permet d'en ajuster la frequence propre.
   REPERE : l'axe de l'OS, dans le triedre de l'ANCRE (SPEC 7) — le degre de liberte que la
   projection de longueur confisquait, a 84.5 % l'axe VERTICAL de sa SPEC 24.
   LIGNE DE BASE : 0.0 exactement a la pose debout d'auteur (SPEC 9) — un tissu au repos ne
   s'allonge pas, donc un zero ici n'est pas un trou de mesure, c'est l'etat neutre.
```

## NOTE-298  (docstring de `phys-skin-chain`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 33/34 — LA PEAU N'ENTRE PAS DANS LE CORPS, ET C'EST LA DERNIERE CONTRAINTE DE POSITION DE
   LA FRAME. Le solveur contraignait le JOINT contre des CAPSULES ; sa 33 et sa 34 parlent de
   SURFACES. On lit donc, pour chaque sommet extremal de peau du maillon (les `ms`, EXACTEMENT la
   donnee que l'instrument lit), la distance signee a la surface du CORPS avec la MEME fonction que
   l'instrument : on contraint ce qu'on mesure, sinon la borne ne se transporte pas.
   LA LECTURE D'AUTEUR EST UNE VRAIE REQUETE, PAS UNE LINEARISATION — c'est la correction du
   premier essai de ce cycle, et elle est mesuree, pas supposee : `sa = sd - dot(dj, nrm)` suppose
   que les deux points tombent dans la MEME cellule du nuage, ce qui est faux des qu'on change de
   plus proche echantillon. L'instrument, lui, interroge les deux points. La borne
   `skinpen <= skinrest` ne vaut donc que si la contrainte interroge les deux aussi.
   ELLE EST GRATUITE PAR FRAME : le point d'auteur ne depend pas de la position simulee, donc il se
   lit UNE FOIS et sert aux quatre passes.
   LA CORRECTION EST `v = min(0, sa) - sd`, appliquee si elle est positive : jamais plus loin que la
   surface, jamais au-dela de la profondeur que l'auteur avait deja. A la pose d'auteur les deux
   lectures coincident, donc `v <= 0` : la contrainte est INERTE au repos, et SPEC 2/9 comme la gate
   IDLE ne peuvent pas la voir bouger.
   ELLE S'APPLIQUE PAR ROTATION AUTOUR DE L'ATTACHE, ET C'EST LA SECONDE CORRECTION DU CYCLE : une
   poussee tangentielle suivie d'une reprojection de longueur laisse la reprojection defaire une
   part de la correction et rend la borne inexacte. `b + |u| * normalize(u^ + k t^)` EST une
   rotation : la longueur est invariante AU BIT, aucune reprojection n'est necessaire, donc plus
   rien ne s'execute apres la contrainte et la borne tient a l'instant ou l'instrument mesure.
   CE QU'ELLE NE PEUT PAS FAIRE, ET JE LE DECLARE AU LIEU DE LE TAIRE : si la normale est presque
   RADIALE (`sp2 <= 0.05`), aucune rotation ne sort le sommet — il faudrait changer la longueur de
   l'os, ce que sa 22 interdit. Ces cas-la sont laisses tels quels.
   NATURE : une profondeur, unites de jeu. REPERE : le monde, frame courante. LECTURE HORS DEFAUT :
   `*phys-skc-n*` = 0, aucune correction appliquee.
```

## NOTE-299  (docstring de `phys-surf-sd`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
(SPEC 18) DISTANCE SIGNEE du point `p` a la VRAIE SURFACE SKINNEE. Positive = dehors.
   NATURE : une distance, unites de jeu. REPERE : le monde, frame courante. LECTURE HORS DEFAUT :
   positive. La sentinelle 1000000.0 = « aucun echantillon a portee », ce qui n'est PAS zero.

   [NOTE-242] L'ESTIMATEUR A CHANGE PARCE QUE L'ANCIEN N'AVAIT PAS CONVERGE, ET C'EST MESURE.
   Il signait la distance par la normale du SEUL plus proche echantillon. Deux faits l'ont tue :
   `|sd| <= |p - q|` par Cauchy-Schwarz, donc une profondeur de 501 u EXIGE que le plus proche
   echantillon soit a plus de 12 cm — un TROU du nuage, pas une penetration ; et en triplant
   l'echantillonnage (1071 -> 2966) a solveur IDENTIQUE AU BIT, la lecture bougeait de 30 %. Un
   estimateur qui bouge de 30 % quand on raffine son maillage mesure l'echantillonnage, pas la
   surface — un point plus PROCHE dont la normale est plus OBLIQUE rendait une lecture plus
   PROFONDE, et un seul mauvais echantillon decidait de tout.

   CE QUI LE REMPLACE : la moyenne des distances aux plans des `PHYS-SD-K` plus proches
   echantillons, ponderee par un noyau qui S'ANNULE au K-ieme. Deux proprietes, et ce sont elles
   qu'on achete :
     - CONTINUITE : l'echantillon qui entre ou sort du K-voisinage porte un poids NUL, donc la
       valeur ne saute pas quand le voisinage change. C'est ce qui manquait — [NOTE-241] mesure une
       chaine qui OSCILLE a 242 u au repos parce qu'une contrainte lisait un champ qui sautait ;
     - ROBUSTESSE : un plan oblique isole est noye par ses sept voisins au lieu de decider seul.
   Le rayon du noyau est la distance au K-ieme voisin, donc il S'ADAPTE a la densite locale : il n'y
   a aucune longueur choisie a la main dans cette fonction.
   `*phys-sdn*` rend la normale PONDEREE des memes K plans, renormalisee : la direction sort avec la
   distance et de la MEME population, sinon la contrainte pousserait le long d'un plan qui n'est pas
   celui qui a decide de la profondeur.
```

## NOTE-300  (docstring de `phys-collide-depth`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
DISTANCE AU SOLIDE QUE LA LIGNE DE DONNEES DESIGNE — l'enveloppe convexe des deux spheres.

   CE QUI ETAIT FAUX, ET C'EST MESURE (rapport du cycle 22, section 9, probe
   `.autoport/probe_mesh_vs_capsule_fidelity.py` : `sd_round_cone` contre `sd_engine`) : le code
   projetait le point sur le segment, bornait le parametre, PUIS interpolait le rayon a ce
   parametre-la. C'est evaluer f(t) = |p - C(t)| - r(t) au parametre de PROJECTION au lieu de la
   MINIMISER sur [0,1]. Pour une capsule a rayons egaux les deux coincident ; les 24 capsules
   livrees sont TOUTES coniques (`physics_chains.txt` lignes 171-240), donc l'ecart existait sur
   chacune : 186 sommets sur 7963 changeaient de cote, ecart max 0.0974 m — neuf centimetres sur
   des pieces ou l'owner voit des clips, et plus que le rayon propre des lunettes (48 mm).

   LE PARAMETRE EXACT. Avec x la coordonnee axiale de p, y sa distance a l'axe, L la longueur de
   l'axe et dr = rb - ra, f est CONVEXE en t (racine d'un quadratique moins une affine), donc son
   minimum sur [0,1] est son minimum libre borne. f'(t) = 0 donne
       t* = ( x + dr*y / sqrt(L^2 - dr^2) ) / L
   et dr = 0 le ramene a x/L, c'est-a-dire exactement l'ancien code : la correction ne touche que
   les capsules coniques. Quand L^2 <= dr^2 une sphere contient l'autre et le solide EST la plus
   grosse — le cas ou l'ancien predicat se trompait le plus, puisqu'il faisait descendre le rayon
   jusqu'au petit bout d'un cone qui n'existe pas.

   LA NORMALE EST CORRIGEE PAR LA MEME OPERATION, et ce n'est pas un bonus : au parametre optimal,
   la direction de C(t*) vers p EST le gradient de la distance signee, donc la vraie normale
   sortante du tronc de cone. A un parametre quelconque elle ne l'est pas.

   CE QUE CETTE CORRECTION NE FAIT PAS : deplacer la ligne de base. La franchise accordee a chaque
   paire (`floors`/`floorc`, lignes 1855-1858, 1943-1946, 2052) est calculee par CETTE fonction sur
   la pose du modele : elle se corrige donc du meme coup. Ce qui change est la FORME de la surface,
   pas de combien on a le droit d'y entrer.
```

## NOTE-301  (docstring de `phys-vol-floor`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
Profondeur maximale que cette paire (lien, volume) tolere : sa profondeur d'auteur PLUS ce que la
   chair cede avant de toucher l'os. La bande n'est pas choisie, c'est le seul chiffre de sa spec qui
   dise jusqu'ou la chair s'ecrase contre le thorax : SPEC 10 `SupineProjectionScale = 0.70` donne
   `0.30 * B0`, pas un point de plus. La PROFONDEUR DE COM qui en resulte n'est PAS posee : elle sort
   de l'equilibre des forces (dans la bande seule la raideur SPEC 24/29 resiste) et se lit ENSUITE
   contre la ligne de SPEC 10 qui la chiffre, 0.23 B0.
   POURQUOI ELLE NE POUVAIT PAS RESTER A `floor0` : mur UNILATERAL pose EXACTEMENT au point de repos,
   donc il repoussait le premier micron vers le thorax et laissait l'autre sens libre. Cycle 14,
   stimulus IDENTIQUE : pole libre 0.13997 B0 contre pole bloque 0.02511 B0. REDRESSEE. NOTE-55.
   `b0` = 0 rend la forme d'avant, sans complaisance : c'est ce que recoit toute paire que
   `phys-vol-yield` n'a pas reconnue comme du buste. LA POSE DU MODELE RESTE ADMISSIBLE a fortiori :
   `feff >= floor0`, test STRICT. `*phys-col-off*` DESARME le mur entierement (controle k=4) et passe
   par ICI pour couvrir les TROIS sites de `feff` d'un seul point. Voir [NOTE-53].
```

## NOTE-302  (docstring de `phys-rest`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 33/34 — LA RESTITUTION DE CONTACT, SUR LA FENETRE.
   0 = nombre de contacts ou elle a ete appliquee (un entier rendu en float) ; 1 = somme des
   vitesses normales ENTRANTES (u/frame, positives) ; 2 = somme des vitesses normales SORTANTES
   RELUES A LA FRAME SUIVANTE (donc mesurees, pas deduites de `e`) ; 3 = somme des coefficients
   appliques, qui lit le melange 0.06 (sein<->sein, §33) / 0.02 (buste, §34) ; 4 = nombre de
   sorties effectivement relues.
   NATURE : des vitesses en unites de jeu par frame. REPERE : le MONDE, projete sur la normale de
   contact. LECTURE HORS DEFAUT : tout a zero quand rien ne touche — et un zero ici ne vaut que
   s'il est accompagne du domaine (nombre de contacts), sans quoi c'est un zero de domaine vide.
```

## NOTE-303  (docstring de `phys-comexw-reset!`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
REMET A ZERO LA TRANCHE 23-42 — TOUT CE QUI A LA PORTEE D'UNE FENETRE (chaine, animation,
   pilotage) — sur toutes les chaines. Les emplacements 19 (maximum de COURSE) et 20/21/22 (la
   distribution cumulee) ne sont PAS touches : ils portent des grandeurs de portee differente,
   deja publiees, et les confondre rendrait le maximum de course egal a celui de la derniere
   fenetre. La tranche : 23 `comex` max · 24-28 `rgap`/`perr` · 29/30 SPEC 37 · 31-34 l'attribution
   de `comex` et son maillon · 35-42 [NOTE-112] le COM par MAILLON · 43-46 le COM PONDERE ·
   47-49 [NOTE-136] son VECTEUR. La tranche est CONTIGUE et le `dotimes` la couvre EN ENTIER.
   ENUMERER CES VINGT EMPLACEMENTS UN PAR UN etait le vrai risque : ils ont tous la meme portee et
   la meme valeur de repos, et chaque emplacement neuf ouvert ailleurs pouvait etre OUBLIE ici —
   auquel cas il aurait publie a chaque fenetre le maximum de la COURSE, sans que rien le dise.
```

## NOTE-304  (docstring de `phys-chain-radial-link`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 23 — l'elongation radiale du MAILLON `link`. which 0 = unites de jeu · 1 = rapportee a B0 ·
   2 = maximum de FENETRE apres la borne de §22 · 3 = le meme AVANT la borne · 4 = frames ou la
   borne a mordu SUR CE MAILLON · 5 = (ml-bl)/B0 et 6 = dot(cp-px,m^)/B0, les DEUX TERMES de `dr0`
   releves a l'ARGMAX de 3, somme = 3 au signe pres ([NOTE-82]) · 7 = dot(cp-tg,m^)/B0 et
   8 = |cp-tg|/B0, MEME frame : 6 se scinde en 7 + dot(tg-px,m^)/B0, et |7| <= 8 est un controle
   d'integrite non tautologique ([NOTE-84]).
   Version RESOLUE PAR MAILLON de `phys-chain-radial`, qui ne rend que la RACINE. C'est aussi l'etat
   que le solveur lit. NATURE deformation signee · REPERE axe de l'os dans le triedre de l'ANCRE
   (SPEC 7) · LIGNE DE BASE 0.0 a la pose d'auteur (SPEC 9). [NOTE-79] -> jak-hd-physics-NOTES.md
```

## NOTE-305  (docstring de `phys-link-rest-dir`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
L'AXE D'OS AU REPOS, PAR MAILLON, TEL QUE LE SOLVEUR L'A RELEVE — `*phys-ux*/uy/uz`, releve une
   fois a la meme frame que `g_ref`. Il existait dans le moteur et n'etait publie nulle part, si
   bien que le tableau l'AJUSTAIT par ACP sur la dispersion de neuf deplacements : ajustement
   declare « NON PLAN — le reste du bloc est invalide » sur les deux chaines, et pourtant consomme
   par SPEC 10/11/12 et par l'anisotropie de SPEC 29. NATURE : un vecteur UNITAIRE, sans dimension.
   REPERE : la base de l'ANCRE, ordre (x, y, z) de ses lignes. LECTURE HORS DEFAUT : rend 0.0 tant
   que la direction de repos n'est pas relevee (`*phys-ucap*` = 0), ce qui se distingue d'un axe
   nul.
```

## NOTE-306  (docstring de `phys-dfm-anc`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
SPEC 8/10-13/23/38 — L'ELEMENT (i,j) DE LA DEFORMATION EN ESPACE ANCRE, telle que le solveur
   l'applique : `dfa` (equilibre d'orientation) x `dfb` (etirement dynamique) x `dfc` (pression de
   contact). NATURE : une matrice sans dimension, rapport a la forme d'auteur ; l'identite quand
   rien ne deforme. REPERE : la base de l'ANCRE, la meme que `phys-link-dev-anc-abs` — donc un
   deplacement de peau se compose directement avec un ecart de joint, ce qui etait impossible tant
   que seule la version conjuguee en monde existait. LECTURE HORS DEFAUT : diag(1,1,1).
   CE QUE CE N'EST PAS : la deformation VUE sur le mesh. C'est ce que le solveur COMMANDE ; la peau
   n'en recoit qu'une part graduee en r^1.63 (SPEC 31).
```

## NOTE-307  (docstring de `phys-link-pen`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
LA PENETRATION DU LIEN `l` SI SON JOINT ETAIT EN `pt`.
   NATURE : une profondeur, en metres. REPERE : monde. LECTURE HORS DEFAUT : PHYS-NOCONTACT.

   `prio` = 1 quand l'appel SERT LE SOLVEUR (le recul) : la DECISION 1 s'applique, seul le volume
   decideur du lien compte pour la PROFONDEUR. `prio` = 0 quand l'appel MESURE : tous les volumes
   comptent, sinon le chiffre deviendrait aveugle a ce que la decision laisse passer.

   LE FRANCHISSEMENT D'AXE N'EST JAMAIS SOUMIS A LA PRIORITE, ET CE N'EST PAS UNE EXCEPTION DE
   CONFORT : deux volumes ne peuvent pas se contredire dessus. La pose du modele est du BON cote de
   CHAQUE axe par construction, donc reculer vers elle les satisfait tous a la fois — il n'y a
   aucun conflit a arbitrer. Le soumettre a la priorite rouvrirait `goggles-tunnel` (les lunettes
   qui traversent le buste pour se poser dans le dos), que ce veto est precisement ce qui ferme.
```

## NOTE-308  (ENTREE ANNULEE — capture erronee du 2026-08-20)

```
Cette entree avait ete produite par un deplacement de docstring qui a mordu sur le CODE de
`phys-link-pen` (le `let` des vecteurs de pile). Le code a ete REMIS dans le moteur le jour
meme et le compilateur l'atteste ; la docstring de `phys-link-pen`, elle, vit en [NOTE-307].
L'entree est gardee VIDE au lieu d'etre supprimee : un numero qui disparait laisserait croire
qu'un renvoi du moteur pointe vers rien.
```

## NOTE-309  (docstring de `phys-col-key`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
LA CLE DE PRIORITE D'UN VOLUME — depuis le 2026-08-18, DEPARTAGE SEULEMENT (le decideur est le
   plus profond violeur, voir le site de selection) : corps avant chaine, puis parent dans le rig.

   LA REGLE ECRITE N'EST PAS TOTALISANTE, ET C'EST MESURE : trois volumes de corps sont a egalite
   de profondeur minimale 1 (`hips->main`, `chest->main`, la sphere `main`). Sans departage le
   decideur dependrait de l'ordre de parcours, c'est-a-dire du fichier — la meme faute que celle
   qu'on corrige. Le departage est l'index rig du joint porteur : les 33 `cj` sont deux a deux
   distincts (verifie sur le rig), donc la cle est TOTALE et deux frames identiques designent
   toujours le meme decideur.
```

## NOTE-310  (docstring de `phys-cpc`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
LE CUMUL DE POUSSEES DE CONTACT DEPUIS LA DERNIERE REMISE A ZERO DE DIAGNOSTIC.
   0 = NOMBRE de poussees (un compte, sans unite) ; 1 = somme de leurs MODULES (unites de jeu,
   4096 = 1 m) ; 2 = la meme somme restreinte aux balayages 34 a 45, c'est-a-dire au groupe de
   COLLISION SEULE (sans contrainte de longueur pour ramener le lien en arriere).
   NATURE : un compte et deux longueurs, AGREGES sur toutes les frames de la jambe — pas des maxima
   de fenetre. REPERE : le monde. LECTURE QUAND RIEN NE TOUCHE : les trois a zero, et le 0 sert de
   DOMAINE aux deux autres.
```

## NOTE-311  (docstring de `phys-link-dev-anc-abs`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
LA MEME DEVIATION QUE `phys-link-dev-anc`, MAIS NON NORMALISEE (voir la note de `*phys-ldb*`).
   `phys-link-dev-anc` projette une difference de vecteurs UNITAIRES : sa composante radiale est
   nulle par construction, et la PCA des fenetres d'impulsion du cycle 8 le montre (serie plane a
   1 %, direction nulle a 92 % verticale). Celle-ci porte les TROIS degres de liberte, en unites de
   jeu. Meme triedre d'ancre, meme ordre (v, ap, lat), meme instant, meme garde de classification —
   l'ecart entre les deux series EST la mesure de l'aveuglement, pas une seconde opinion.
```

## NOTE-312  (docstring de `phys-pose-repair`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
RE-ASSEOIR un lien que le retarget a envoye ailleurs, au lieu de le simuler autour d'une position
   fausse ET au lieu de le supprimer des donnees. Owner/superviseur du 2026-08-11 : une chaine se
   REPARE, elle ne se retire pas. La position de secours est derivee du rig et de rien d'autre : le
   porteur, prolonge le long de SON os (de son parent vers lui), a la distance que le mesh mesure
   pour ce lien (son rayon ajuste). Elle est ecrite dans le squelette AVANT la physique, donc la
   geometrie du lien suit, et la reparation est comptee et publiee. C'est un defaut de MODELE
   corrige au dernier moment possible, pas une physique inventee.
```

## NOTE-313  (docstring de `phys-pen-chain`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
L'INSTRUMENT MESURE TOUJOURS CONTRE LE SOLIDE QUE LA DONNEE DESIGNE, quel que soit le predicat
   que le SOLVEUR utilise. Sans ca le controle de `*phys-cone-off*` serait casse dans le sens que
   les DIRECTIVES sanctionnent : arme, le solveur cesserait de pousser ET la mesure cesserait de
   regarder, donc le compteur TOMBERAIT sous le defaut au lieu de MONTER. Ici il monte, parce que
   le solveur laisse le lien dans un solide que la mesure, elle, continue de voir en entier.
   `prio` = 0 n'a que CE seul appelant (le solveur passe 1) : la restauration est donc totale.
```

## NOTE-314  (docstring de `phys-inject-probe!`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
[NOTE-155] CONTROLE POSITIF DE `meshpen`, EN PAIRE ET SUR LA MEME FRAME.
   On injecte LE DEFAUT QUE LE COMPTEUR MESURE — `*phys-inject*` unites de PROFONDEUR, le long de
   la normale RENTRANTE du volume ou le lien est deja le plus enfonce — puis on remesure avec le
   MEME predicat (`phys-link-pen`, `prio` = 0) et on RESTAURE la position au bit.
   NATURE : deux profondeurs residuelles, en unites de jeu. REPERE : le monde, MEME frame.
   LECTURE HORS DEFAUT : les deux maxima sont egaux, donc la hausse est 0.
```

## NOTE-315  (docstring de `phys-len-project!`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
RAMENE LE LIEN SUR LA SPHERE DE SON ATTACHE — ROTATION, PAS TRANSLATION. `want` est la longueur
   que le MODELE donne a cet os ; un os que le modele ne donne pas (`want` ~ 0) n'a pas de sphere et
   garde son comportement en translation. `pt` est en coordonnees de JOINT, pas en centre de volume.
   DEUX APPELANTS depuis ce cycle : c'est le correctif du residu, voir la note au balayage.

   `*phys-len-off*` DESARME la projection : voir la note de ce drapeau. C'est le controle de
   l'hypothese du cycle 8, actif sur les seules fenetres AXZ, et 0 en livraison.
```

## NOTE-316  (docstring de `phys-col-prox?`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
UN VOLUME EST UNE SPHERE PROXIMALE si son joint porteur est le joint du MAILLON 0 d'une chaine
   declaree ET qu'il n'a pas de second joint (donc une sphere, pas une capsule). Predicat DERIVE :
   aucun nom d'os n'y figure, donc il suit un renommage ou une reinjection.
   POURQUOI IL EXISTE : le cycle 35 a mesure que les deux spheres de chair d'un sein decrivent LA
   MEME chair — sur les 55 sommets de `chestL`, la proximale ne couvre pas UN SEUL sommet que la
   distale ne couvre deja. Cet interrupteur demande ce que ca coute a l'execution.
```

## NOTE-317  (docstring de `phys-col-now!`, deplacee le 2026-08-20 pour tenir le plafond CLEAN ; aucune ligne de CODE touchee)

```
LES DEUX EXTREMITES DU VOLUME TELLES QUE TOUTES LES CHAINES DOIVENT LES VOIR CETTE FRAME.
   NATURE : une position monde, en unites de jeu. REPERE : monde.
   CE QU'ELLE REND QUAND LE DEFAUT EST ABSENT : le squelette courant, au bit pres — c'est le cas
   des 24 volumes qu'aucune chaine ne simule, et du premier pas de chaque acteur.

   Un volume porte par un joint SIMULE est lu dans l'instantane de FIN DE FRAME PRECEDENTE. Sinon
   la reponse d'une chaine depend de son rang dans le fichier : voir la note de `*phys-csim*`.
```

## NOTE-318  (SPEC 33 — LA SURFACE MEDIALE DE L'AUTRE SEIN, et pourquoi son domaine etait vide)

```
[NOTE-295] SPEC 33 — LA SURFACE MEDIALE DE L'AUTRE SEIN. Sa 33 dit « medial surfaces shall
collide or repel BEFORE visible interpenetration » ; jusqu'a ce cycle le sein oppose etait exclu
de TOUTE surface que le moteur lit, donc le DOMAINE de la section etait vide par construction et
aucune valeur ne pouvait rien en dire, ni rouge ni vert.
NATURE : `medgap` est une distance SIGNEE minimale (positive = les deux surfaces sont separees),
  `medpen` la pire penetration (positive quand une surface est DEDANS l'autre), `medn` le nombre
  de lectures valides — c'est LUI qui dit si le domaine est vide, et un domaine vide se declare
  au lieu d'etre lu comme « zero penetration ».
REPERE : le monde, a la frame mesuree. Les colonnes `a` sont le MEME calcul au point d'AUTEUR :
  meme frame, memes sommets, meme fonction — c'est la ligne de base « physique desarmee ».
```

## NOTE-319  (les deux populations de la famille `bs`, et pourquoi la passe 0 est bit-identique)

```
[NOTE-294] PASSE 0 = LES OS DE CORPS, PASSES 1..nc = LES OS DE CHAQUE CHAINE.
L'acceptation est la MEME expression pour les deux — `cch = pass - 1`, avec
`cch = -1` pour un os qui n'appartient a aucune chaine. La passe 0 range donc
exactement la population d'avant ce cycle, dans le MEME ordre, aux MEMES
indices : `phys-surf-sd`, qui lit [0, *phys-slot-nbsurf*), ne peut pas voir la
difference, et SPEC 34 ne bouge pas d'un bit. Les surfaces de chaine sont
rangees APRES, contigues par chaine, et une requete doit NOMMER sa chaine pour
les atteindre.
```

## NOTE-320  (l'espacement du nuage, mesure sur la donnee livree)

```
L'ESPACEMENT DU NUAGE, MESURE SUR LA DONNEE LIVREE. Pour chaque echantillon
d'un ensemble de chaine, la distance a son plus proche voisin DU MEME
ensemble ; on garde la moyenne, et par chaine le maximum sur ses ensembles.
C'est le rayon au-dela duquel la surface n'est pas echantillonnee : aucune
longueur n'est choisie a la main, elle sort du fichier.
```

## NOTE-321  (l'injection du controle positif de SPEC 33)

```
L'INJECTION du controle positif de SPEC 33. ARMEE EN PERMANENCE : elle n'ecrit QUE
l'accumulateur `*phys-medgapi*` et jamais un etat de solveur, donc elle ne peut pas contaminer
la trajectoire mesuree — c'est la condition que le registre pose a tout controle positif.
CONTROLE DE CETTE PROPRIETE, cycle 62 : apres le passage en fraction, la seule ligne du tableau
qui bouge est `ROOM-SKINPEN-TESTS` (154 428 542 -> 154 428 116, soit 0,0003 %), le compteur de
travail de l'INSTRUMENT ; `skinpen`, `tipvar`, `rootdev`, `meshpen`, `ROOM-IDLE` et `ROOM-SIDE`
sont identiques. L'ecart de 426 comparaisons EST la preuve que l'injection a bien change de
point de depart : un no-op aurait rendu le compteur identique lui aussi.

CYCLE 62 — C'EST UNE FRACTION SANS DIMENSION, PLUS UNE LONGUEUR EN UNITES DE JEU.
Elle valait 200 u (0,0488 m) FIXES, et la prediction `approche - injection` n'a de sens que tant
que `injection < approche`. Sur la fenetre de COURSE l'approche vaut 47 et 50 u : le point
injecte TRAVERSAIT la surface et le controle sortait NON EVALUABLE — c'est-a-dire exactement sur
la fenetre qui PORTE le verdict. Il ne tirait que sur la fenetre de repos, ou le domaine est
VIDE. LE CONTROLE TIRAIT DONC LA OU IL N'Y A RIEN A MESURER, ET MANQUAIT LA OU ON MESURE.

Une FRACTION rend la prediction bien posee PARTOUT : le point sonde avance de `f x d1` vers le
plus proche echantillon, donc il ne peut jamais traverser la surface tant que `f < 1`, et
l'approche apres injection vaut `(1 - f) x d1`. Comme le minimum sur la fenetre commute avec la
multiplication par une constante positive, la prediction sur les grandeurs PUBLIEES est exacte :

    gapi = (1 - f) x gap,  soit une BAISSE de `f x gap`.

Aucune longueur n'est choisie a la main, et la prediction reste QUANTITATIVE (arbitrage du
2026-08-20 13:20 : une prediction, jamais un ratio a une ligne de base qui bouge). MESURE a
f = 0,50 : les QUATRE cellules (2 chaines x 2 fenetres) tirent a 0,0-0,1 % d'ecart, sur des
baisses predites de 0,0057 a 0,0705 m — un facteur 12,4. L'instrument SUIT SON ENTREE sur plus
d'un ordre de grandeur au lieu de republier une constante, ce qui est precisement ce qu'un
controle doit demontrer.
```

## NOTE-322  (deux populations dans le meme tableau)

```
[NOTE-293] DEUX POPULATIONS DANS LE MEME TABLEAU, ET C'EST CE QUI DONNE UN DOMAINE A SPEC 33.
Les ensembles de CORPS occupent [0, *phys-slot-nbsurf*) — c'est ce que `phys-surf-sd` lit par
defaut, donc SPEC 34 ne bouge pas d'un bit. Les ensembles portes par un os de CHAINE sont
RANGES APRES, par chaine et contigus, et ne sont lus que par une requete qui NOMME sa chaine.
Un sein n'est donc jamais un obstacle pour lui-meme, et il en devient un pour l'autre.
```

## NOTE-323  (SPEC 33/34 — la peau ferme la frame)

```
[NOTE-241] SPEC 33/34 — LA PEAU FERME LA FRAME. Toutes les contraintes qui
precedent raisonnent sur le JOINT et sur des CAPSULES ; celle-ci raisonne sur
les SOMMETS DE PEAU et sur la SURFACE, c'est-a-dire sur ce dont sa 33 et sa
34 parlent, et sur ce que l'instrument mesure. Elle est la DERNIERE, donc
rien ne la defait — c'est l'invariant que le dossier prescrit depuis le
cycle 43 et que l'ordre `collide` puis `bend` ne tenait plus.
```

## [NOTE-325] la troncature de la peau, mesuree : `sets=64/92` et 12 echantillons par ensemble.

(bloc deplace du moteur le 2026-08-20, cycle 63 — plafond de lignes CLEAN)

```
;; Mesure, trace du 2026-08-20 : « bsurf ag=keira-hd sets=64/92 » — 28 ensembles de surface sur 92
;; JETES par ce plafond, et chaque ensemble retenu tronque a ses 12 PREMIERS echantillons. La SDF
;; voyait donc au plus 768 points pour tout le personnage. C'est pour ca qu'un os INTERIEUR pouvait
;; se lire DEHORS (`chestL skinpen=0.0000` au repos avec `skinmiss=0`, contre 417.23 u sur chestR).
```

## [NOTE-326] `*phys-bssl*` : l'ORIGINE a laquelle chaque ensemble de surface est porte.

(bloc deplace du moteur le 2026-08-20, cycle 63 — plafond de lignes CLEAN)

```
;; PAR ENSEMBLE : le `scl` du maillon qui le porte, -1 pour un os de CORPS. Il decide de l'ORIGINE
;; a laquelle les echantillons sont portes — un os de corps suit l'animation, un maillon de chaine
;; suit la position RESOLUE. Sans lui, le sein oppose serait teste a sa pose d'auteur pendant que
;; le sein testeur est a sa pose simulee : deux instants dans une meme distance.
```

## [NOTE-327] `*phys-sd-d1*` : la distance au plus proche echantillon dit MESURE ou EXTRAPOLATION.

(bloc deplace du moteur le 2026-08-20, cycle 63 — plafond de lignes CLEAN)

```
;; LA DISTANCE AU PLUS PROCHE ECHANTILLON de la derniere requete, et c'est elle qui dit si la
;; reponse est une MESURE ou une EXTRAPOLATION. `|sd| <= |p - q|` par Cauchy-Schwarz : une lecture
;; de 2618 u EXIGE que le plus proche echantillon soit a 64 cm, ce qui n'est pas une penetration,
;; c'est un plan prolonge a l'infini loin de la ou il a ete echantillonne. Sentinelle 1000000.0.
```

## [NOTE-328] `*phys-sd-auth*` : pourquoi la colonne d'auteur a besoin de son propre interrupteur.

(bloc deplace du moteur le 2026-08-20, cycle 63 — plafond de lignes CLEAN)

```
;; 1 = les ensembles de CHAINE sont portes par la pose d'AUTEUR (la translation de l'os), 0 = par
;; la position RESOLUE. Sans cet interrupteur la colonne d'auteur comparerait un point d'auteur a
;; une surface SIMULEE : deux instants dans une meme distance, et le pair ne mesurerait plus la
;; physique. C'est le defaut exact que le cycle 61 a paye sur `skinrest`.
```

## [NOTE-329] `*phys-skinpen*` : la pire ENTREE sous la peau, sa NATURE et son REPERE.

(bloc deplace du moteur le 2026-08-20, cycle 63 — plafond de lignes CLEAN)

```
;; La pire ENTREE sous la peau, par chaine, sur la fenetre de mesure.
;; NATURE : une profondeur signee, en unites de jeu, positive quand le lien est SOUS la surface.
;; REPERE : le monde, a la frame ecrite — la meme position que celle dont `meshpen` est tire, pour
;;          que les deux colonnes soient comparables terme a terme.
;; LECTURE QUAND LE DEFAUT EST ABSENT : 0. Un lien qui reste dehors n'ecrit jamais rien ici.
```

## [NOTE-324] SPEC 7 — LE MIROIR DU LATERAL SORTANT, ET IL EST PAR CHAINE.

```
---------------------------------------------------------------------------
CE QUE SA SPEC 7 EXIGE, MOT POUR MOT (l.126-133) :

  « +X = character's outward lateral direction / +Y = upward along torso /
    +Z = forward from chest.  For the left and right breasts, outward `+X`
    should be MIRRORED so that the equations remain symmetrical. »

CE QUI ETAIT ECRIT : `fx = cross(fy, fz)`, dont LES DEUX ENTREES sont
identiques pour les deux chaines (meme ancre `chest`). Le lateral ne POUVAIT
donc pas differer : le miroir n'etait pas « pas encore fait », il etait
impossible dans cette construction. Mesure du cycle 62, emise pour la
premiere fois : `a0 = (-0.98297 -0.18374 +0.00000)` SUR LES DEUX CHAINES,
`angle(a0[chestL], -a0[chestR]) = 179.749 deg` la ou la clause exige 0.

CE QUI NOMME LE COTE, ET IL EXISTAIT DEJA : `sep`, le segment qui va du sein
OPPOSE a celui-ci, deja calcule pour nommer la ligne laterale. Il pointe vers
l'exterieur par ANATOMIE, pas par convention de rig. Il n'etait garde que par
ses PROJECTIONS (`*phys-axsep*`) ; il est desormais garde en VECTEUR
(`*phys-sepv*`), et le miroir se lit sur lui :

    si dot(fx, sep) < 0   ->   fx := -fx

Le triedre d'une chaine sur deux devient GAUCHER, et c'est la consequence
geometrique exacte du miroir d'un seul axe sur trois — pas un repere casse.
`det` doit donc sortir OPPOSE sur les deux chaines, et `ROOM-SPEC7-SENS` le
lit.

CE QUE CA CORRIGE EN AVAL, ET CE N'EST PAS UN EFFET DE BORD : SPEC 12.
Le cycle 50 avait donne un cote a §12 en composant `gxc` avec `signe(sja)`,
faute d'un lateral par chaine. Mais `fx` pointe le long de -e_ja (composante
mesuree -0.98297), donc `gxc * signe(sja) = -(g . sortant)` : le poids
d'aplatissement tombait sur le sein OPPOSE a la gravite, quand §12 ecrit
« The GRAVITY-SIDE breast experiences stronger thoracic compression ». Le
signe avait ete SUPPOSE, jamais mesure — piege `axis-sign-outlives-role-
renaming` du registre. Le miroir rend `gxc = g . sortant` par construction :
`wlt = max(0, gxc)` tombe alors du bon cote, et le signe rapporte disparait.

OU LE MIROIR N'EST PAS DEFINI : sans chaine partenaire, `sep = 0`, le produit
scalaire vaut 0, aucune chaine n'est retournee et le comportement d'avant est
reproduit a l'identique. `PHYSAXNAME src=` publie ce cas.
```

## [NOTE-330] CONTROLE POSITIF : l'offset GELE, pour que l'injection deplace le POINT MESURE.

```
---------------------------------------------------------------------------
LE DEFAUT, MESURE AU CYCLE 63 : `ROOM-POSCONTROL` ne restituait que 69,2 % de
son injection (86,9 % au cycle 62), pour une bande exigee de 75-125 %.

CE QUI N'ETAIT PAS LA CAUSE, ET IL FAUT LE DIRE PARCE QUE JE L'AI CRU :
  - PAS la saturation de l'injection. Le gain d'un deplacement de A le long de
    la normale vaut A tant que A <= d, ou d = |point - axe du volume|. Comme
    `want = rr + rlink` et que les rayons de MAILLON valent 587 a 725 u, d est
    de l'ordre de 700 u pour A = 400 u : ca ne sature pas.
  - PAS le fait que `armed` et `disarmed` soient deux maxima courants. Pour le
    critere tel qu'il est ecrit (« la mesure PUBLIEE doit monter de X »), la
    difference de deux maxima est la bonne formulation.

LA CAUSE : L'INJECTION DEPLACE LE JOINT, LA MESURE LIT UN AUTRE POINT.
`phys-link-pen` ne sonde pas le joint `p` mais

    q = p + R(u) . off,   u = normalise(p - b),   |off| = 467 a 651 u

ou `R(u)` est la rotation qui amene la direction de BIND sur la direction
COURANTE (`phys-link-off-sim!`, deux reflexions). Injecter `p' = p - A.n`
change `u`, donc change `R(u)`, donc

    q' - q = -A.n + (R(u') - R(u)) . off

et sa norme n'est PAS A. Avec un bras de ~1000 u, A = 400 u fait tourner `u`
d'environ 22 deg, ce qui balaie l'offset de ~250 u ; projete sur `n`, ca mange
la difference. Ordre de grandeur du deficit mesure : 0,0977 - 0,0675 =
0,0302 m = 124 u. C'est la meme famille que `apex-bound-reads-a-joint-not-the-
apex` : on agit sur un joint et on lit une grandeur qui vit ailleurs.

LE CORRECTIF : pendant la SEULE relecture ARMEE, l'offset est GELE a la valeur
qu'il avait au balayage, c'est-a-dire A LA POSITION NON INJECTEE. Le point
mesure translate alors de -A.n EXACTEMENT, et la profondeur monte de A.

CE N'EST PAS UN AJUSTEMENT POUR PASSER LA BANDE, ET LA PREDICTION LE PROUVE :
elle n'est pas « >= 75 % », elle est « 100 % ». `armed` doit passer de 0,1521 a
0,0845 + 0,0977 = 0,1822 m, `disarmed` doit rester au bit, et tout le reste du
tableau doit etre INCHANGE (l'interrupteur est pose et retire a l'interieur de
la sonde). Un resultat qui atterrirait entre les deux refuterait l'explication.

LA ROTATION DE L'OFFSET N'EST PAS LE DEFAUT QU'ON INJECTE : elle decrit comment
le volume suit l'os. Le defaut injecte est « A de penetration en plus », et il
se pose sur le point qui porte la penetration.
```


## [NOTE-408] LE `+Z` DU TRIEDRE DE §7 POINTE VERS L'ARRIERE — MESURE, CYCLE 69

`SPEC-breast-softbody.md` l.130 ecrit « `+Z = forward from chest` ». Le trièdre construit a
`jak-hd-physics.gc:3532-3547` pose `fz = +e[ia]` orthogonalise contre `fy`, **avec le signe `+`
ecrit en dur et aucune mesure**. Sur le rig livre, `ia = 2` (`PHYSAXIS rap=2`), et `+e2` pointe
vers l'ARRIERE. Trois routes independantes, toutes sur des donnees publiees :

1. **L'os de racine de chaque sein**, `PHYSURST` (base de l'ancre) : composante `fz` de
   **-0.14776** (chestL) et **-0.14794** (chestR). Un sein FAIT SAILLIE ; il pointe donc a
   l'oppose de `+fz`. Les deux chaines s'accordent a 0.12 %.
2. **Trois marqueurs d'anatomie sur `keira-hd-donor-injected.glb`**, en espace `chest`, axe 2 :
   frange (`Lbanga`/`Rbanga`) **-0.3135**, lunettes (`gogglesMid`) **-0.2189**, nuque
   (`backHair1`/`backHair2`) **+0.0618 / +0.0990**. L'avant du crane est negatif, l'arriere positif.
3. **La rotation commandee du balayage d'orientation** : la cellule `i=6` est `Rz(+90)` autour du
   monde ; la gravite monde `(0,-1,0)` y devient `(-1,0,0)` en coordonnees du corps, et
   `PHYSORI4 r2 = -0.9933`. Le triplet d'echelles de cette cellule est `0.8912 / 0.9199 / 1.2195`,
   c'est-a-dire **§11 prone** (largeur -10 %, epaisseur -9 %, longueur +23 %). Une gravite
   `r2 < 0` correspond donc au sein PENDANT, donc a une gravite vers l'AVANT.

**LE CALCUL AVAL EST JUSTE, C'EST LA CONVENTION QUI S'ECARTE DE LA SPEC.** `:3569-3570` pose
`wbk = max(0, -gzc)` et `wfw = max(0, gzc)`, et `:3576-3581` donne a `wbk` le triplet prone
`0.900/0.910/1.230` et a `wfw` le triplet supine `1.230/1.090/0.700`. Les deux erreurs de sens
— convention inversee et affectation inversee — se compensent exactement, ce qui rend le defaut
INVISIBLE a toute mesure de sortie et visible seulement en lisant les deux ensemble.

**CE QUE CA COUTE QUAND MEME :** tout consommateur NEUF qui lit `gz` en croyant la docstring ou
la §7 inversera §10 et §11. C'est arrive : la docstring de `phys-shape` l'ecrivait, et
**[NOTE-67] et [NOTE-68] sont PERIMEES** — elles concluent sur `axa = 0` alors que la course
publie `rap = 2`, et NOTE-68 conclut « +ligne[axa] = l'avant », l'inverse de ce que le rig livre
mesure. Ne pas les relire comme des references.

**PORTEE DE LA CORRECTION DE CE CYCLE :** aucune ligne de calcul n'est touchee. Seules les
docstrings fausses sont corrigees, et le NOMMAGE des cellules d'orientation passe desormais par
un chemin unique cote tableau (`orole()`), qui derive le role de `PHYSORI4` au lieu de le lire
dans une etiquette. Une etiquette ne se verifie pas ; une gravite mesuree si.

## NOTE-330 — LE MUR DE FORCE DE §21 DEVIENT DESARMABLE, PARCE QU'UN MECANISME NON DESARMABLE EST INFALSIFIABLE

`*phys-fwall*` (moteur, ligne ~562) — 1 = le multiplicateur `mu` du bloc `:2939-2944` est ARME,
c'est-a-dire l'etat de toutes les courses jusqu'au cycle 71 inclus ; 0 = il vaut 1.0 partout et le
materiau redevient un ressort LINEAIRE.

**POURQUOI IL FALLAIT UN INTERRUPTEUR AVANT DE TOUCHER AU MECANISME.** Le registre le dit sous
`attribution-harness-outlives-its-defect` : « ajoute l'interrupteur d'ablation AVANT de t'autoriser
a corriger le mecanisme que tu soupconnes. Un mecanisme DIMENSIONNE mais pas DESARMABLE est
infalsifiable. » Le cycle 28 l'avait fait pour la borne radiale (`phys-rr-off-set!`) et le controle
avait **exonere** le suspect : la « correction » serait partie inerte. Le mur de force est ici dans
la meme position — soupconne, chiffre, jamais desarme.

**CE QUE LE MUR EST, EN ALGEBRE ET SANS MESURE.** `xr = min(0.99, (dd - kn)/cpp)` puis
`|f| = k2s * (kn + cpp * xr/(1-xr))`. Le `min 0.99` GELE le numerateur des que
`dd >= kn + 0.99*cpp = 0.4992 B0` : au-dela, la force de rappel est **CONSTANTE**
(5020.68 u, soit 16.7x ce que le ressort lineaire rendrait a cette distance), identique a 0.50 B0
d'erreur et a 5 B0 d'erreur. Une force constante est un TAUX, pas une BORNE — le defaut exact que
le cycle 34 a mesure et corrige sur l'AUTRE canal ([NOTE-87]) et qui n'a jamais ete porte sur
celui-ci.

**ET LA §21 EST DEJA IMPLEMENTEE, CORRECTEMENT, VINGT LIGNES PLUS BAS.** Le bloc `:3120-3141`
(`*phys-sat-n*`) sature le **DEPLACEMENT** : genou a `0.42 B0`, tanh de Pade, asymptote exacte a
`0.50 B0` — les deux nombres de sa §22, dans la forme que sa §21 ecrit
(`D = D_max * tanh(|D|/D_max)`). Le moteur porte donc DEUX implementations de la meme section sur
le meme canal : une sur la bonne grandeur, une sur la mauvaise.

**L'ARGUMENT QUI TRANCHE N'EST PAS §21, C'EST §24.** Sa §24 donne UNE frequence propre par axe
(2.30 / 2.50 / 2.65 Hz). Un multiplicateur de raideur qui monte a x16.7 rend la frequence
instantanee dependante du deplacement (x4.09 sur la racine carree) : les deux lignes ne peuvent pas
etre vraies ensemble. Une saturation de DEPLACEMENT, elle, laisse la raideur intacte — c'est
precisement pourquoi la spec la met la.

**PORTEE DECLAREE.** L'interrupteur ne touche QUE le maillon principal. Le point libre de §23
(`cmu`, `:2988-2992`) porte la meme faute de forme et n'est PAS touche : son `cdd` est deja borne a
~0.40 B0 par le filet de [NOTE-87], donc sa degenerescence est marginale, et un probleme a la fois.

**COMMENT ON L'ARME.** Constante de compilation, un build GOAL (26 s) par jambe. Pas de `-set!` :
le moteur est a 4799 lignes pour un plafond de 4800, et une fonction d'armement en coute cinq. La
salle etant deterministe au bit (mesure au cycle 32, re-mesuree au cycle 71 : 0 ligne differente
sur 43 254), deux courses successives font une paire appariee exacte.

## NOTE-331 — POURQUOI LA GARDE `(= n 1)` A ETE RETIREE DU MUR D'APEX DE SPEC 22

```
`(= n 1)` RETIRE le 2026-08-17 — meme raison qu'a `sat` : cette garde aurait
fait disparaitre le mur d'apex de SPEC 22 des l'injection du second os, et
`*phys-sat-n*` aurait publie 0 parce que le bloc ne tourne plus. La borne
porte sur l'ecart de CHAQUE maillon a SA propre pose d'auteur, donc elle
s'applique telle quelle a l'apex quand il y en a deux.
```

## NOTE-332 — SPEC 33 : LE MEME SOMMET, CONTRE LA SURFACE DE L'AUTRE SEIN

```
[NOTE-295] SPEC 33 : LE MEME SOMMET, CONTRE LA SURFACE DE L'AUTRE SEIN.
Memes points, meme fonction, meme frame que SPEC 34 juste au-dessus — les
deux sections deviennent comparables terme a terme au lieu de sortir de deux
populations. La fenetre de lecture est posee puis RENDUE immediatement.
```

## NOTE-333 — LE RAYON DE SUPPORT DECIDE SI LA LECTURE EST UNE MESURE

```
LE RAYON DE SUPPORT DECIDE SI LA LECTURE EST UNE MESURE. Un point plus
loin du nuage que DEUX espacements n'est sur aucune surface
echantillonnee : sa distance signee est un plan prolonge, pas une
profondeur. Ces lectures sont COMPTEES (`medfar`), jamais publiees.
```

## NOTE-334 — LE STIMULUS GRAVITAIRE LUI-MEME, AVANT TOUTE REPONSE

```
LE STIMULUS GRAVITAIRE LUI-MEME, avant toute reponse. Sans ce nombre, un
affaissement nul est indiscernable entre « la gravite n'arrive pas jusqu'a
cette chaine » et « la chaine n'y repond pas », et c'est cette ambiguite qui
a laisse quatre passes de l'owner sans reponse. 0 debout, 1.0 a 60 degres.
```

## NOTE-335 — LE RESIDU SIGNE DE PENETRATION PART DE -1e9, PAS DE ZERO

```
--- residu SIGNE de penetration (SPEC 3). > 0 = ca traverse, <= 0 = la
--- marge qui reste avant de traverser. Le maximum de la fenetre part donc
--- de -1e9 (voir phys-stats-reset!) et non de zero : un maximum plafonne a
--- zero aurait rendu la colonne constante et donc inverifiable.
```

## NOTE-336 — LES DEUX CORRELATIONS PUBLIEES MAIS NON GATEES

```
publies mais NON gates : la correlation du deplacement
ecrit avec celui d'auteur, et les deux amplitudes qui
disent pourquoi cette correlation est bruitee des que le
pilotage domine l'animation.
```

## NOTE-337 — LE TRIEDRE DE SPEC 7, RELEVE UNE SEULE FOIS

```
(a) LE TRIEDRE DE SA SPEC 7 (+X lateral, +Y haut, +Z avant), releve UNE
fois, a la MEME frame que `g_ref` et `*phys-ux*`. Il ne se lit sur aucun
nom d'os : +Y est l'oppose de la gravite de la pose d'auteur, +Z la
protrusion racine->apex orthogonalisee, +X leur produit vectoriel.
```

## NOTE-338 — LES TROIS TERMES DE L'APEX, MESURES LA OU ILS EXISTENT (cycle 73)

`SPEC-breast-softbody.md:301` : « Distal/apex displacement: normal <=42% B0, exceptional <=50% B0 ».
Le cycle 58 a cartographie les cinq sites du moteur qui portent `0.42|0.50 x B0` : **aucun ne lit le
point d'apex**, et le seul qui borne quoi que ce soit (`:3120-3141`) borne `*phys-px*`, la
TRANSLATION du joint. Le cycle 58 a essaye de lui faire lire l'apex et l'a **refute par la mesure** :
la borne mordait deux fois moins, parce qu'au point ou elle s'applique le tenseur de deformation
n'existe pas encore. Sa conclusion, verbatim : « §22 n'est pas bornable depuis la boucle de
contraintes ; le chantier est de borner l'apex APRES la construction du tenseur (section 6, ou `bm`
existe) ».

**AVANT DE BORNER, IL FAUT SAVOIR CE QU'ON BORNE — ET LE CHIFFRE DU CYCLE 58 A QUATORZE CYCLES.**
Depuis, les axes ont ete classes, le tenseur a change, la §37 a ete recablee, la pose de la salle a
ete corrigee deux fois. Concevoir une borne contre une decomposition perimee est exactement
`attribution-harness-outlives-its-defect`. Ce cycle republie donc la decomposition SUR LE SOLVEUR
COURANT, et rien d'autre.

    e  = tp + rp + dp        (identite exacte, tous les termes sur LA MEME frame)
    tp = SUM_l w_l (p_l - pre_l.trans)                 la TRANSLATION du maillon
    dp = SUM_l w_l (bm_l.R . (dfm - I)) . o_l          le TENSEUR applique au bras de chair
    rp = e - tp - dp                                   la ROTATION de visee, DERIVEE

**POURQUOI `rp` SE DERIVE ET NE S'EMET PAS.** Trois mesures independantes plus une quatrieme
redondante ne se contredisent jamais : la quatrieme serait decorative. Derivee, elle transforme
l'identite en CONTROLE — si `e - tp - dp` sortait de l'ordre de grandeur d'une rotation, c'est que
l'un des trois termes est faux. C'est le seul controle interne que ce canal possede.

**OU CHAQUE TERME EST CAPTE, ET POURQUOI LA-BAS.**
  - `dp` est capte **a l'interieur meme du bloc qui applique le tenseur** : `tmp = bm . dfm` et `bm`
    y ont tous deux leur translation a zero, donc `phys-pt-exc!(tmp, bm, o)` rend EXACTEMENT
    `(tmp.R - bm.R) . o`. Le capter ailleurs demanderait de reconstruire `dfm`, donc d'introduire
    une seconde formule pour la meme grandeur — la faute de `two-half-blind-readers`.
  - `tp` est capte sous LA MEME garde `aw > 0` que l'apex complet, donc sur exactement la meme
    population de maillons. Une garde differente donnerait deux termes qui ne se soustraient pas.
  - les six valeurs sont ecrites **au MEME argmax que `apex`** (meme bloc `when`), donc sur la meme
    frame. Trois maxima pris sur trois frames differentes ne se soustraient pas : c'est
    `argmax-anchor-is-not-a-population`, et l'identite serait fausse sans que rien ne le dise.

**CE QUE CE CANAL NE FAIT PAS.** Il ne borne rien. Aucun terme du solveur n'est touche : la
prediction de bit-identite du cycle 73 porte sur les 43 386 lignes `PHYS` anterieures, qui doivent
etre identiques UNE A UNE a celles de la course precedente.

## NOTE-339 — LE TENSEUR PORTE UNE TRANSLATION D'ANCRE, ET LA MESURE L'AURAIT ABSORBEE

`*phys-dfm*` est construit `:3783-3785` comme `w2l . A . am`. `A` (`dfa`/`dfb`) a bien sa ligne 3
mise a `(0,0,0,1)` explicitement — mais **`w2l` et `am` sont des transformations d'ancre et portent
une TRANSLATION**. Donc `dfm vector 3` n'est pas nul, et `tmp = bm . dfm` en herite une.

Le solveur, lui, s'en moque : trois lignes plus bas il ecrase `bm vector 3` avec `*phys-px*`. La
translation parasite ne va nulle part. **La MESURE, elle, l'aurait lue** — `phys-pt-exc!` additionne
`tmp.trans`, donc `dp` aurait publie la translation de l'ancre sous le nom du tenseur, sur un canal
cree precisement pour separer ces deux choses.

Mise a zero AVANT la lecture. **Sans effet sur le solveur** : cette ligne est ecrasee juste apres, ce
que la prediction de bit-identite verifie sur les 43 386 lignes anterieures.

**REGLE :** une grandeur intermediaire qu'un solveur JETTE n'est pas une grandeur nulle. Avant de
brancher un instrument sur un temporaire, verifier ce que le code fait de chaque composante — celles
qu'il ecrase sont precisement celles que personne n'a jamais eu besoin de tenir propres.


## NOTE-341 — DIAGNOSTIC PAR CHAINE — la legende des emplacements de `*phys-dg*`

------------------------------------------------------------------------------------------------
DIAGNOSTIC PAR CHAINE — les quatre defauts de la 6e passe se lisent ici, chaine par chaine.
which : 0 selfcol  1 retreat  2 flip  3 inv  4 invres  5 elong (allongement relatif max)
------------------------------------------------------------------------------------------------


## NOTE-342 — `phys-link-amp` — l'amplitude PAR MAILLON, la seule qui voit le gradient inverse

AMPLITUDE DE MOUVEMENT D'UN MAILLON DONNE, meme instrument que `phys-tip-amp` mais pris sur le
maillon `link` au lieu de la pointe. C'est la suite que SPEC 2 exige croissante de la racine vers
la pointe, et la seule mesure capable de voir « le milieu part en vrille et la pointe ne bouge
pas » — que `tipvar`, qui ne regarde que la pointe, rendait indistinguable d'une chaine saine.


## NOTE-343 — `phys-tip-mean` — un DEPLACEMENT SOUTENU, pas une variance (ROOM-GRAVSAG)

POSITION MOYENNE de la pointe sur la fenetre, dans le repere de l'ancre, axe par axe (0=x 1=y
2=z). C'est le DEPLACEMENT SOUTENU dont la salle fait ROOM-GRAVSAG : la difference entre la
moyenne debout et la moyenne penchee a 60 degres EST la reponse a la gravite. Zero si la fenetre
n'a pas de frame — jamais une valeur inventee.


## NOTE-344 — ce que la remise a zero des statistiques de fenetre couvre, emplacement par emplacement

somme et compte de la position moyenne de la pointe (12..15), pire stimulus recu (16),
pire allongement relatif (17), stimulus gravitaire (18), sa part tangentielle (19) et la
profondeur AJOUTEE sous la peau (20, [NOTE-150]) — ce dernier est un maximum d'une
grandeur positive : 0 est sa lecture QUAND LE DEFAUT EST ABSENT, pas une sentinelle.


## NOTE-345 — SPEC 23 — le troisieme degre de liberte est celui du TISSU, pas du premier maillon

[NOTE-59] ---- SPEC 23 : LE TROISIEME DEGRE DE LIBERTE ---------- -> jak-hd-physics-NOTES.md
`(>= l rlk)` DEPUIS LE CYCLE 32, et c'etait `(= l rlk)` :
sa §23 donne un troisieme degre de liberte au TISSU, pas
au premier maillon. Le distal en etait prive, et sa serie
radiale etait identiquement nulle (0 sur 150, 6 canaux).


## NOTE-346 — `*phys-sdq*` — le controle positif de SPEC 33 est une PREDICTION, pas un ratio

LA POSITION MONDE du plus proche echantillon de la derniere requete. Elle sert au CONTROLE
POSITIF de SPEC 33 : on deplace le point sonde EXACTEMENT vers lui d'une longueur connue, donc
la reponse attendue est une PREDICTION (`approche - injection`), pas un ratio a une ligne de
base qui bouge — arbitrage du 2026-08-20 13:20.


## NOTE-347 — les deux ETAGES de `phys-cap-ang!` : ce que longueur, collision et attenuation retirent

ETAGE 1 : apres la boucle de contraintes ET l'attenuation d'angle, avant la
finition. L'ecart entre l'etage 0 et celui-ci est ce que longueur, collision
et attenuation retirent.


## NOTE-340 — `PHYSSTG` : LES SEPT ETAGES DE LA BORNE DE SPEC 22 DANS UNE MEME FRAME (cycle 74)

**Ce qu'il mesure.** `|p_rlk - pose_auteur_rlk| / B0`, la MEME grandeur que `jt` de `PHYSCOMWL`
(emplacement 39+l), relevee a SEPT instants de la frame au lieu d'un seul.

  NATURE  : une LONGUEUR rapportee a `B0` (SPEC 6, la CHAIR, 602,0 u — pas l'os).
  REPERE  : le monde, contre la pose d'AUTEUR de la MEME frame.
  LECTURE QUAND LE DEFAUT EST ABSENT : 0,0000 aux sept etages (`ROOM-IDLE maxdev` = 0,0002).
  ETAGES  : 0 avant le filet de §22 · 1 apres le filet · 2 apres la 1re contrainte de LONGUEUR ·
            3 apres la 1re COLLISION · 4 apres les 8 iterations · 5 avant la peau ·
            6 apres `phys-skin-chain` = **la valeur LIVREE**.

**Pourquoi un latch et pas sept maximums.** Les sept valeurs viennent d'UNE SEULE frame, celle qui
maximise l'etage 6 dans la fenetre. Sept maximums independants viendraient de sept frames
differentes et ne pourraient soutenir aucun modele reliant deux etages — piege `RAD-FLESH-IPAIR`
du cycle 34.

**CONTROLE INTERNE, GRATUIT.** L'etage 1 est `<= 0,50 B0` PAR ALGEBRE (`ds = kn + cp*tanh(x)`,
strictement `< kn + cp`). Mesure : **0 fenetre au-dessus sur 372**. S'il ne l'etait pas, ce serait
l'INSTRUMENT qui serait faux, pas le solveur, et rien d'autre de la ligne ne serait lisible.

**CONTROLE DE NON-PERTURBATION.** Les 44 130 lignes `PHYS` anterieures sont identiques UNE A UNE a
celles de la course precedente : **0 differente**. Le canal LIT, il n'est pas un terme.

**CE QU'IL A TROUVE (cycle 74).** Les etages 0 a 5 respectent le plafond de 0,50 B0 ; l'etage 6 le
depasse sur 184/186 et 156/186 fenetres. **La fuite entiere de la §22 est produite par
`phys-skin-chain`, et par elle seule** — les quinze passes de contraintes que le cycle 73
soupconnait laissent la borne INTACTE (la contrainte de longueur la fait meme BAISSER de 0,3 %).

**SA LIMITE, ET ELLE EST PUBLIEE AVEC LUI.** Le septuplet ne prend que **6 et 10 valeurs
distinctes sur 186 fenetres**, la ou `PHYSAPEX` en rend 182 / 180 sur la MEME course. Il n'est donc
**PAS DISCRIMINANT ENTRE STIMULI** au sens de SPEC 7, et aucune phrase du cycle 74 ne s'appuie sur
une variation entre fenetres. Cause : son latch est cle sur l'etage 6, **qui sature** — la cle d'un
argmax ne peut pas etre une grandeur saturee. Il attribue DANS une frame, ce pour quoi il est bati.
A rebatir sur une cle non saturee avant toute lecture par stimulus.


---
## NOTE-409 — L'ECHELLE EFFECTIVEMENT APPLIQUEE, dans CE triedre : (lateral, vertical, projection). C'est la

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; L'ECHELLE EFFECTIVEMENT APPLIQUEE, dans CE triedre : (lateral, vertical, projection). C'est la
;; grandeur que la salle publie ; sa NATURE est un rapport sans dimension a la forme d'auteur, son
;; REPERE est celui de l'ancre, et sa LECTURE HORS DEFAUT est 1.000 sur les trois (debout).
```

---
## NOTE-410 — 96 -> 112 : les os de CHAINE entrent desormais dans la meme famille `bs`, donc le

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; [NOTE-292] 96 -> 112 : les os de CHAINE entrent desormais dans la meme famille `bs`, donc le
;; nombre d'ensembles DECLARES passe de 92 a 96 et touchait EXACTEMENT le plafond. Un plafond
;; atteint est une troncature qui attend son tour.
```

---
## NOTE-411 — PAR CHAINE : l'espacement MOYEN entre echantillons voisins de sa surface, mesure sur la donnee

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; PAR CHAINE : l'espacement MOYEN entre echantillons voisins de sa surface, mesure sur la donnee
;; livree et jamais choisi a la main. Il donne le RAYON DE SUPPORT du nuage : au-dela, la surface
;; n'est tout simplement pas echantillonnee et une distance signee n'y a pas de sens.
```

---
## NOTE-412 — LES LECTURES REJETEES PARCE QUE LE POINT EST HORS DU SUPPORT DU NUAGE. Publie a cote de `medn`

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; LES LECTURES REJETEES PARCE QUE LE POINT EST HORS DU SUPPORT DU NUAGE. Publie a cote de `medn`
;; pour que l'exclusion soit VISIBLE : un rejet silencieux transformerait une extrapolation en
;; « rien a signaler », ce qui est la forme meme d'un faux vert.
```

---
## NOTE-413 — PHASE LARGE EXACTE : on n'ecarte un ensemble que s'il ne peut contenir AUCUN

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
            ;; PHASE LARGE EXACTE : on n'ecarte un ensemble que s'il ne peut contenir AUCUN
            ;; echantillon plus proche que le K-ieme deja trouve — la borne du voisinage, pas du
            ;; plus proche, sinon on jetterait des plans qui ont droit de vote.
```

---
## NOTE-414 — LA 7e PASSE NE CORRIGE PAS, ELLE MESURE : `*phys-skc-r*` est la pire

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; LA 7e PASSE NE CORRIGE PAS, ELLE MESURE : `*phys-skc-r*` est la pire
                    ;; violation qui SURVIT aux six passes. C'est la contrainte qui se juge
                    ;; elle-meme — si elle ne ferme pas, ce chiffre le dit avant la gate.
```

---
## NOTE-415 — LA COLONNE D'AUTEUR EST ENTIEREMENT D'AUTEUR : le point sonde ET la

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; LA COLONNE D'AUTEUR EST ENTIEREMENT D'AUTEUR : le point sonde ET la
                          ;; surface opposee sont a la pose dessinee. Comparer un point d'auteur a
                          ;; une surface simulee melangerait deux instants dans une seule distance.
```

---
## NOTE-416 — LA POSITION MONDE DE L'ANCRE, POUR QUE LA SALLE MESURE SON BRAS DE LEVIER.

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                      ;; [NOTE-137] LA POSITION MONDE DE L'ANCRE, POUR QUE LA SALLE MESURE SON BRAS DE LEVIER.
                      ;; HORS de la tranche 23-49 que `phys-comexw-reset!` efface : ce n'est pas un
                      ;; maximum de fenetre, c'est un ETAT — la derniere valeur ecrite, et elle doit
                      ;; survivre a l'ouverture d'une fenetre pour etre lisible a sa premiere frame.
```

---
## NOTE-417 — ---- 0. LES LONGUEURS D'OS, avant d'integrer quoi que ce soit. -------------

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; ---- 0. LES LONGUEURS D'OS, avant d'integrer quoi que ce soit. -------------
                    ;; Relevees sur la pose ANIMEE a chaque frame : elles sont quasi constantes,
                    ;; mais les lire evite de supposer que le retarget n'a pas change une longueur.
```

---
## NOTE-418 — L'ANCRE — LE SEUL POINT PAR LEQUEL L'ANIMATION ENTRE. Maillon

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                               ;; L'ANCRE — LE SEUL POINT PAR LEQUEL L'ANIMATION ENTRE. Maillon
                               ;; `rootlock` (SPEC 2 : la racine suit rigidement l'os porteur), ou
                               ;; premiere frame : la pose d'auteur EST la position, sans etat.
```

---
## NOTE-419 — L'ATTACHE : le maillon precedent DEJA SIMULE, ou l'ancre pour le

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                               ;; L'ATTACHE : le maillon precedent DEJA SIMULE, ou l'ancre pour le
                               ;; premier maillon libre. C'est par elle, et par elle seule, que le
                               ;; mouvement du crane atteint la particule — par la contrainte, pas
                               ;; par un ressort.
```

---
## NOTE-420 — SPEC 6 — LE METRE DES BORNES DE SPEC 22, ET CE N'EST PAS

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                      ;; SPEC 6 — LE METRE DES BORNES DE SPEC 22, ET CE N'EST PAS
                                      ;; `bl` : `bl` est l'OS (la contrainte de longueur porte bien
                                      ;; sur lui), `b0e` est la CHAIR. Voir PHYS-P-B0.
```

---
## NOTE-421 — LA CIBLE du ressort de materiau, pas sa force : elle ne

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                      ;; LA CIBLE du ressort de materiau, pas sa force : elle ne
                                      ;; depend pas de `p`, donc elle se calcule UNE FOIS PAR FRAME
                                      ;; pendant que la force, elle, se recalcule a chaque SOUS-PAS.
                                      ;; C'est exactement la separation que SPEC 37 impose.
```

---
## NOTE-422 — ---- LA CIBLE DE LA FORCE ELASTIQUE DU MATERIAU. Elle est portee

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; ---- LA CIBLE DE LA FORCE ELASTIQUE DU MATERIAU. Elle est portee
                                 ;; ---- rigidement par l'ancre ; elle ne connait pas l'animation du
                                 ;; ---- maillon, donc elle ne peut pas la « suivre ».
```

---
## NOTE-423 — `rate` = le TAUX (2 zeta omega dt), `kd` la RETENTION qu'il

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; `rate` = le TAUX (2 zeta omega dt), `kd` la RETENTION qu'il
                                 ;; produit sur une frame. Voir NOTE-50 : c'est `e^-rate`, pas
                                 ;; `1 - rate`, et l'ecart valait +8.3 % sur le zeta de SPEC 25.
```

---
## NOTE-424 — LA MEME PROJECTION POUR LA TRAINEE (SPEC 25) : `zeta` est

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                       ;; LA MEME PROJECTION POUR LA TRAINEE (SPEC 25) : `zeta` est
                                       ;; une constante du materiau, donc l'amortissement doit
                                       ;; suivre la raideur AXE PAR AXE, pas rester scalaire.
```

---
## NOTE-425 — IDENTITE STRICTE sous 0.84*(ckn+ccp) = 0.336 B0 : rien n'est

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                     ;; IDENTITE STRICTE sous 0.84*(ckn+ccp) = 0.336 B0 : rien n'est
                                     ;; retire au mouvement subtil. `cq` etant ecrit `cp - fns*cv`
                                     ;; APRES, `cp - cq` est inchange -> AUCUNE vitesse creee.
```

---
## NOTE-426 — ---- 3bis. CONTROLE POSITIF DES INVERSIONS. Arme, chaque lien libre est

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; ---- 3bis. CONTROLE POSITIF DES INVERSIONS. Arme, chaque lien libre est
                    ;; ---- MIROITE a travers son attache : c'est exactement le defaut que l'owner a
                    ;; ---- vu deux fois. Le compteur d'inversions doit alors monter — la correction
                    ;; ---- s'applique a la frame suivante, quand la contrainte revoit le cote.
```

---
## NOTE-427 — ---- 4. LES CONTRAINTES ONT BOUGE LA POSITION : on remet cet effet dans

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; ---- 4. LES CONTRAINTES ONT BOUGE LA POSITION : on remet cet effet dans
                    ;; ---- l'ecart, sinon la frame suivante repartirait d'un etat que rien ne
                    ;; ---- soutient (et la vitesse verlet perdrait la perte d'energie du choc).
```

---
## NOTE-428 — --- LE GRADIENT : la boite englobante de l'ecart POUR CHAQUE MAILLON.

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                      ;; --- LE GRADIENT : la boite englobante de l'ecart POUR CHAQUE MAILLON.
                      ;; Un maillon rootlock a un ecart identiquement nul et mesure donc zero, ce
                      ;; qui est exactement ce que SPEC 2 demande de la racine.
```

---
## NOTE-429 — LE CONTROLE POSITIF, APPARIE SUR CETTE FRAME. Il ne tourne que

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                        ;; [NOTE-155] LE CONTROLE POSITIF, APPARIE SUR CETTE FRAME. Il ne tourne que
                        ;; sous armement de la salle, il restaure la position au bit, et il recoit
                        ;; `pen` — la mesure NON injectee de cette meme frame — pour que les deux
                        ;; maxima soient pris sur la MEME trajectoire.
```

---
## NOTE-430 — LE MEME ALLONGEMENT, MAIS PAR FENETRE : « ils s'allongent sur

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                    ;; LE MEME ALLONGEMENT, MAIS PAR FENETRE : « ils s'allongent sur
                                    ;; les mouvements BRUSQUES » est une phrase sur un PILOTAGE, et
                                    ;; le compteur par course ne peut pas la verifier.
```

---
## NOTE-431 — LA MEME DEVIATION, MAIS SIGNEE ET VECTORIELLE (voir la note de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                  ;; LA MEME DEVIATION, MAIS SIGNEE ET VECTORIELLE (voir la note de
                                  ;; `*phys-lsv*`). Ecrasee, jamais accumulee : c'est l'etat de
                                  ;; CETTE frame, la seule forme qui puisse porter une phase.
```

---
## NOTE-432 — OSCILLATEUR SCALAIRE, SANS ANISOTROPIE : la forme EXACTE de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; OSCILLATEUR SCALAIRE, SANS ANISOTROPIE : la forme EXACTE de
                                 ;; NOTE-50 s'y pose directement. Elle n'est pas un raffinement
                                 ;; ici — `omega dt` vaut 0.545, et l'ancienne ecriture livrait
                                 ;; zeta 0.838 a 7.01 Hz la ou sa SPEC 36 demande 0.65 a 5.20.
```

---
## NOTE-433 — SPEC 36 s'applique a l'EPAISSEUR locale et conserve le volume :

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; SPEC 36 s'applique a l'EPAISSEUR locale et conserve le volume :
                                 ;; l'epaisseur (axe +Z) module, les deux perpendiculaires prennent
                                 ;; l'inverse de sa racine.
```

---
## NOTE-434 — OSCILLATEUR SCALAIRE : forme EXACTE de NOTE-50.

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                             ;; OSCILLATEUR SCALAIRE : forme EXACTE de NOTE-50.
                                             ;; `zt` n'introduit AUCUNE constante neuve — c'est le
                                             ;; zeta que la donnee livree porte deja, relu comme
                                             ;; `taux / (2 omega h)` au lieu d'etre suppose.
```

---
## NOTE-435 — PAR MAILLON depuis le cycle 32 : `*phys-rr*` (par chaine) donnait

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; PAR MAILLON depuis le cycle 32 : `*phys-rr*` (par chaine) donnait
                                 ;; au distal l'elongation de la RACINE. C'est le seul terme du
                                 ;; solveur qui lit le degre de liberte de §23.
```

---
## NOTE-436 — RELEVE A L'ARGMAX DE `cl`, PAS EN MAXIMA INDEPENDANTS.

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                              ;; [NOTE-97] RELEVE A L'ARGMAX DE `cl`, PAS EN MAXIMA INDEPENDANTS.
                              ;; C'est la lecon N3/N4 du cycle 35 : deux maxima de fenetre pris sur
                              ;; des grandeurs differentes ne se comparent pas, parce que l'argmax
                              ;; n'est pas la meme frame. `tl` est deja un index PAR MAILLON.
```

---
## NOTE-437 — SPEC 29 — la torsion est une ROTATION propre autour de l'axe

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                            ;; SPEC 29 — la torsion est une ROTATION propre autour de l'axe
                            ;; racine->apex, appliquee AVANT l'echelle (l'axe est un axe propre de
                            ;; l'echelle a 10^-3 pres, les deux commutent en pratique).
```

---
## NOTE-438 — la MEME frame, le MEME vecteur, pondere par la masse

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                    ;; [NOTE-127] la MEME frame, le MEME vecteur, pondere par la masse
                                    ;; de peau du maillon : c'est la seule facon d'obtenir le COM sans
                                    ;; melanger deux frames ni majorer par l'inegalite triangulaire.
```

---
## NOTE-439 — NATURE trois longueurs SIGNEES / B0 · REPERE MONDE, meme frame, contre la

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                        ;; NATURE trois longueurs SIGNEES / B0 · REPERE MONDE, meme frame, contre la
                        ;; pose d'auteur · A LA POSE D'AUTEUR 0.0000. Relevees A L'ARGMAX de `cw`,
                        ;; donc les trois ensemble et sur UNE frame — jamais trois maxima separes.
```

---
## NOTE-440 — AU MEME ARGMAX, DONC SUR LA MEME FRAME QUE 53-56 : c'est ce qui rend

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; AU MEME ARGMAX, DONC SUR LA MEME FRAME QUE 53-56 : c'est ce qui rend
                          ;; l'identite `e = tp + rp + dp` verifiable au lieu de comparer trois
                          ;; maxima pris sur trois frames differentes.
```

---
## NOTE-441 — process-drawable.gc:287 appelle ceci sur TOUT process-drawable — y compris les compagnons HD,

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; process-drawable.gc:287 appelle ceci sur TOUT process-drawable — y compris les compagnons HD,
;; AVANT fill-jak-hd-bones! (jak-hd.gc:552-553). Le rider stock n'est pas dans le perimetre de
;; cette phase (KEIRA SEULE, via son compagnon HD) : il ne fait rien, et surtout pas sur un
;; compagnon dont la pose n'est pas encore retargetee.
```

---
## NOTE-442 — suite

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; ------------------------------------------------------------------------------------------------
;; ACCES POUR LA SALLE DE TEST (phys-room.gc). Les accumulateurs vivent ici parce que c'est ici que
;; la position ecrite est connue ; la salle ne fait que fenetrer et publier.
;; ------------------------------------------------------------------------------------------------
```


---
## NOTE-443 — suite

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; ------------------------------------------------------------------------------------------------
;; les deux prises restantes attendues par le reste du jeu.
;; ------------------------------------------------------------------------------------------------
```

---
## NOTE-444 — SPEC 29/36 — les deux maximums de FENETRE. Ce sont des compteurs de mesure, pas des etats

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
    ;; SPEC 29/36 — les deux maximums de FENETRE. Ce sont des compteurs de mesure, pas des etats
    ;; du solveur : `*phys-sec*`, `*phys-tw*` et leurs vitesses ne sont PAS remis a zero ici, sans
    ;; quoi chaque fenetre relancerait le mode secondaire et la torsion depuis rien.
```

---
## NOTE-445 — MEME PORTEE QUE `dynm`, ET ILS NE L'AVAIENT PAS : `dynr`/`dynn`/`dyna`/`prsn`

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
    ;; [NOTE-110] MEME PORTEE QUE `dynm`, ET ILS NE L'AVAIENT PAS : `dynr`/`dynn`/`dyna`/`prsn`
    ;; (21/22/24/23) n'etaient remis a zero que dans `jak-hd-physics-init` — cumuls de COURSE
    ;; publies sous la cle par FENETRE. `dlr` rendait la meme valeur partout (0.4061, ecart 0.7 %).
```

---
## NOTE-446 — §23 : maximum de FENETRE, donc remis a zero ici. `*phys-rr*` et `*phys-rq*` — l'etat — ne le

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
    ;; §23 : maximum de FENETRE, donc remis a zero ici. `*phys-rr*` et `*phys-rq*` — l'etat — ne le
    ;; sont PAS, pour la meme raison que le mode secondaire et la torsion : chaque fenetre
    ;; relancerait sinon l'oscillateur radial depuis rien.
```

---
## NOTE-447 — `phys-cap-e22!` : LA BORNE DE SPEC 22 SUR LA VALEUR **LIVREE** (cycle 76)

**LE DEFAUT QU'ELLE FERME, ET IL EST MESURE, PAS SUPPOSE.** Le filet de SPEC 22 (`:3120-3141`)
tient parfaitement A SON INSTANT — mesure sur la course livree du cycle 75, `PHYSSTG`, 372
fenetres, etage 1 : maximum **0,5000 / 0,4998**, **zero** fenetre au-dessus du plafond dur. Il est
ensuite EFFACE en aval : etage 6 (la valeur qui part au rendu), **184/186 et 156/186 fenetres
au-dessus de 0,50**, maximum 0,6539 / 0,6670, soit **+33 %**.

L'etage 5 — apres les quinze passes de contraintes, AVANT la peau — ne fuit pas non plus :
**0 et 1 fenetre sur 186** au-dessus de 0,50. Le producteur unique est donc `phys-skin-chain`
(cycle 74), et une borne posee APRES elle est, par construction, une borne sur la valeur livree :
plus rien n'ecrit `*phys-px*` ensuite (seules la restitution — qui ne touche que la VITESSE — et
les injections de controle, desarmees en livraison, suivent).

**POURQUOI UNE ROTATION ET PAS UNE CONTRACTION.** Le filet amont contracte radialement vers la
cible (`p := t + d*sf`). Applique en fin de frame, ce geste changerait `|p - b|` — la longueur de
l'os — et **aucune passe ne pourrait plus la reparer**. `phys-cap-e22!` tourne le maillon autour
de son attache : `|p - b|` est invariant AU BIT pour tout angle.

**LA FORME EST CLOSE ET EXACTE.** `p` vit sur la sphere de rayon `ln` centree sur l'attache `b` ;
sur cette sphere, `|p - t|` ne depend que de l'angle a `g = (t - b)/|t - b|` :

    |p - t|^2 = ln^2 + cl^2 - 2.ln.cl.cos(angle)

On impose donc `cos(angle) = (ln^2 + cl^2 - ds^2) / (2.ln.cl)` et on reconstruit `p` dans le plan
`(h, g)` : `h' = cb.g + sqrt(1 - cb^2).w/|w|` avec `w = h - (h.g).g`. Pas de bissection, pas
d'`acos`, **pas de sur-correction** : le resultat vaut `ds` au flottant pres, jamais moins.

**LE SEUIL EST CELUI DE LA SECTION, PAS UN REGLAGE.** Genou `0,42*B0*rl`, asymptote `0,50*B0*rl`,
la MEME tangente hyperbolique de Pade que le filet amont. Le duplicat de ces quatre lignes est
ASSUME : les factoriser ferait bouger la course DESARMEE d'un ULP et detruirait le controle de
bit-identite qui est la seule chose autorisant a lire la jambe armee
(`never-spend-the-bit-identity-control-on-line-count`).

**INERTE AU REPOS PAR ALGEBRE, PAS PAR REGLAGE.** A la pose d'auteur `|p - t| = 0`, donc sous le
genou : la fonction sort sans rien ecrire. C'est la meme bonne forme que le plafond de deplacement
de `phys-skin-chain` (cycle 61), et l'inverse d'un suppresseur qui mordrait en permanence.

**CE QU'ELLE NE FAIT PAS, ET IL FAUT LE DIRE.** Elle borne le terme de **TRANSLATION** du maillon.
La grandeur que SPEC 22 NOMME est le deplacement d'un point de CHAIR a 1,23 B0 de ce joint, dont
l'excursion se decompose en `tp + rp + dp` — translation, rotation du maillon, tenseur de
deformation. `rp` (jusqu'a 0,2313 B0) et `dp` (jusqu'a 0,4660 B0) ne sont vus par AUCUNE borne, et
le cycle 58 a mesure puis REFUTE la tentative de faire lire l'apex a une borne posee dans la boucle
de contraintes. **§22 ne devient donc pas TENUE ; ce qui devient vrai, c'est que sa borne de
translation n'est plus effacee en aval.**

**SON PRIX.** `phys-skin-chain` resout §33/§34 en poussant le joint dehors ; lui refuser la part
qui depasse §22 lui reprend une partie de ce qu'elle avait achete. Ce prix est mesure et publie sur
`ROOM-SKINPEN-DETAIL`, jamais tu.


---
## NOTE-448 — LE STIMULUS QUE LA POINTE A REELLEMENT RECU sur la fenetre, en u/frame^2 : le pire module de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; LE STIMULUS QUE LA POINTE A REELLEMENT RECU sur la fenetre, en u/frame^2 : le pire module de
;; l'acceleration de sa pose d'auteur. C'est le denominateur honnete du gain — celui que la salle
;; COMMANDE ne vaut que si rien d'autre ne le domine, et c'est ce chiffre-la qui le dit.
```

---
## NOTE-449 — 5 = QUELLE REGLE A NOMME LES AXES (0 = protrusion propre, faute de partenaire ;

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
            ;; 5 = QUELLE REGLE A NOMME LES AXES (0 = protrusion propre, faute de partenaire ;
            ;; 1 = segment inter-seins, l'invariant externe). Sans ce champ, une course ne dirait
            ;; pas si le verdict vient de l'anatomie ou du repli.
```

---
## NOTE-450 — SPEC 4, l'exception : `hang` > 0 = « ce qui doit pendre » (les lunettes), qui ne retourne PAS a

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; SPEC 4, l'exception : `hang` > 0 = « ce qui doit pendre » (les lunettes), qui ne retourne PAS a
;; la pose du modele. La salle s'en sert pour compter ces chaines a part au repos, au lieu de
;; devenir complice d'un ecart residuel qu'elle ne saurait pas expliquer.
```

---
## NOTE-451 — la longueur que LE MODELE donne a l'os d'un lien (son attache est l'ancre pour le lien 0). C'est

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; la longueur que LE MODELE donne a l'os d'un lien (son attache est l'ancre pour le lien 0). C'est
;; le plafond geometrique de l'amplitude de ce lien : la salle le publie pour que personne n'ait a
;; deviner si une chaine « ne bouge pas assez » ou « ne peut pas bouger plus ».
```

---
## NOTE-452 — `comp` < 0 : LA LONGUEUR, exactement ce que cette fonction rendait. 0/1/2 : la COMPOSANTE

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
  ;; `comp` < 0 : LA LONGUEUR, exactement ce que cette fonction rendait. 0/1/2 : la COMPOSANTE
  ;; x/y/z de sa DIRECTION UNITAIRE, repere MONDE. Cycle 53 : la contrainte de longueur retire la
  ;; composante ALIGNEE avec l'os, donc l'angle os/pilotage decide de ce qu'elle confisque.
```

---
## NOTE-453 — CONTROLE POSITIF DE L'AUTO-COLLISION : 1 = l'exclusion chaine <-> ses propres volumes est LEVEE.

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; CONTROLE POSITIF DE L'AUTO-COLLISION : 1 = l'exclusion chaine <-> ses propres volumes est LEVEE.
;; Le compteur `selfcol` doit alors monter. Un zero structurel que rien ne peut faire monter ne
;; prouve rien — c'est la regle « tout zero exige un controle positif qui a tire ».
```

---
## NOTE-454 — CONTROLE DU CYCLE 8 : 1 = la contrainte de longueur est DESARMEE. Voir la note de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; CONTROLE DU CYCLE 8 : 1 = la contrainte de longueur est DESARMEE. Voir la note de
;; `*phys-len-off*`. La salle l'arme sur les trois fenetres AXZ et le REND A 0 juste apres — un
;; controle qui resterait arme changerait toutes les mesures suivantes.
```

---
## NOTE-455 — `phys-jacobi-off-set!` et `phys-prio-off-set!` retirees : ZERO site d'appel dans tout `goal_src`

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; `phys-jacobi-off-set!` et `phys-prio-off-set!` retirees : ZERO site d'appel dans tout `goal_src`,
;; leurs interrupteurs restaient donc a leur valeur livree (1 et 1, la priorite de volume que le
;; superviseur a retiree sur mesure). Pas un controle perdu — il etait deja injoignable.
```

---
## NOTE-456 — le collider resolu numero ci : son joint, son second joint (-1 = sphere), ses deux rayons. Publi

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; le collider resolu numero ci : son joint, son second joint (-1 = sphere), ses deux rayons. Publie
;; par la salle pour que le tableau puisse dire QUELLES PARTIES DU CORPS sont couvertes — un zero de
;; penetration contre un ensemble qui ne couvre pas le corps ne prouve rien.
```

---
## NOTE-457 — SPEC 5. which 0 = frames ou l'anim pilotait cette chaine, 1 = celles ou la pose ecrite est parti

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; SPEC 5. which 0 = frames ou l'anim pilotait cette chaine, 1 = celles ou la pose ecrite est partie
;; du meme cote, 2/3 = somme(ecrit . auteur) et somme(auteur . auteur), dont le rapport est la
;; TRANSMISSION. Ces quatre-la survivent aux fenetres : c'est le bilan de la course.
```

---
## NOTE-458 — 25-29 : LA NATURE DE L'ENTREE DE PRESSION (cycle 36 etape 1).

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis) pour tenir le plafond de 4800 lignes.
Aucune ligne de code n'a ete deplacee ni reecrite.

```
        ;; [NOTE-97] 25-29 : LA NATURE DE L'ENTREE DE PRESSION (cycle 36 etape 1).
        ;; 25-31 : les sept emplacements de `*phys-cpa*` releves a l'argmax de `cl`
        ;; (npf, pmax, psum, lastsw, slast, nlast, p1) ; 32 : leur DOMAINE.
```



---
## NOTE-459 — LA PEAU DE LA CHAINE ELLE-MEME — le pendant de `bs`, expose depuis toujours et

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; [NOTE-161] LA PEAU DE LA CHAINE ELLE-MEME — le pendant de `bs`, expose depuis toujours et
;; JAMAIS APPELE. `link_si` empaquete (maillon << 3) | echantillon, comme kmachine.cpp le documente.
```

---
## NOTE-460 — `g_ref` DE SA SPEC 3 — la gravite de la pose debout d'auteur, vue de l'ancre, relevee une fois p

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; `g_ref` DE SA SPEC 3 — la gravite de la pose debout d'auteur, vue de l'ancre, relevee une fois par
;; chaine a la meme frame que `*phys-ux*`. Derivation, mesure et raison complete au site d'usage.
```

---
## NOTE-461 — historique MONDE de la pose d'auteur, par lien : sa difference seconde est l'acceleration du

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; historique MONDE de la pose d'auteur, par lien : sa difference seconde est l'acceleration du
;; repere que la chaine subit. C'est la seule chose qui EXCITE une chaine dont l'ecart cible est nul.
```

---
## NOTE-462 — L'ELONGATION RADIALE PAR MAILLON. Depuis le cycle 32 ce n'est plus un miroir de mesure :

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; [NOTE-79] L'ELONGATION RADIALE PAR MAILLON. Depuis le cycle 32 ce n'est plus un miroir de mesure :
;; c'est la valeur que LIT le solveur (terme `rdr` du tenseur de §38, plus bas). `*phys-rr*` ne
```

---
## NOTE-463 — La matrice de deformation de la chaine, en repere MONDE, rebatie a chaque frame. Elle vaut

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; La matrice de deformation de la chaine, en repere MONDE, rebatie a chaque frame. Elle vaut
;; l'identite tant que rien n'est arme : `matrix*!` par l'identite ne change pas un bit.
```

---
## NOTE-464 — combien de poussees ont REELLEMENT eu lieu. Un controle positif qui n'a rien injecte ne prouve

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 76 bis).
Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; combien de poussees ont REELLEMENT eu lieu. Un controle positif qui n'a rien injecte ne prouve
;; rien : c'est ce compteur, pas la valeur armee, qui dit que le defaut a ete pose.
```


---
## NOTE-465 — `p` vit sur la sphere de rayon `ln` centree sur l'attache ; `|p - t|` n'y

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 77) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; `p` vit sur la sphere de rayon `ln` centree sur l'attache ; `|p - t|` n'y
                    ;; depend que de l'angle a `g`. On IMPOSE cet angle par sa loi des cosinus, en
                    ;; forme close et exacte : pas de bissection, pas d'acos, pas de sur-correction.
```

---
## NOTE-466 — LE SEPTUPLET D'ETAGES A PORTEE DE FENETRE, ET POURQUOI L'ANCIEN RESTE

**Le defaut, mesure.** Le latch de `PHYSSTG` (emplacements 72-78) n'est remis a zero que par
`phys-diag-reset!`, appele **une fois par PHASE**, alors que sa docstring affirmait « la frame qui
maximise l'etage 6 DANS LA FENETRE ». Sur la course livree du cycle 76 : **0 descente sur les 186
emissions de chaque chaine, 7 (chestL) et 8 (chestR) septuplets distincts sur 186**. C'est UN
maximum courant republie 186 fois. Tout comptage de fenetres tire de cette colonne aux cycles 74,
75 et 76 est retire (`SPEC-COVERAGE.md` porte la correction) ; le MAXIMUM, lui, survit — la valeur
terminale d'un maximum courant EST le maximum de la course.

**Deux causes, pas une.** (1) la PORTEE, ci-dessus. (2) la CLE : l'argmax porte sur l'etage 6, que
`phys-cap-e22!` borne desormais a 0,5000 exactement — tous les candidats sont ex aequo et l'argmax
designe une frame arbitraire (`argmax-latch-key-must-not-saturate`). Le cycle 74 avait publie le
symptome et n'avait impute que la seconde.

**Le correctif, et il est au PRODUCTEUR.** Emplacements 79-85 : le MEME septuplet, (a) remis a zero
dans `phys-comexw-reset!` — le seul point par lequel toute fenetre passe, dans toutes les phases,
donc il n'existe plus de chemin qui ouvre une fenetre sans reinitialiser la tranche — et (b) cle
sur l'**etage 0**, releve AVANT le filet de §22, que rien ne borne. L'emplacement 79 porte l'etage 0
de la frame latchee et sert donc de cle sans consommer de slot supplementaire, exactement comme 78
le fait pour l'ancien. Resultat : **186 septuplets distincts sur 186 fenetres, 97 descentes.**

**Pourquoi 72-78 n'est PAS corrige.** `PHYSSTGT` (cycle 75) le lit pour publier le septuplet PAR
JAMBE, et la portee « depuis la derniere remise a zero du diagnostic » EST la bonne pour cette
comparaison-la : une jambe entiere. Lui donner une portee de fenetre casserait l'arbitrage du
cycle 75 sans rien apporter. Les deux sont donc publies cote a cote, `ROOM-STG` et
`ROOM-STG-PHASE`, la seconde portant son verdict `RATCHET` sur sa propre ligne — le piege est
desormais visible par machine et plus seulement par memoire.

**Controle de non-regression, tenu au bit.** Course du cycle 77 contre course livree du cycle 76 :
**46 937 lignes `PHYS` hors `PHYSSTGW`/`PHYSSTGR`, ZERO differente**, `PHYSSTG` et `PHYSSTGT`
compris. C'est un ajout pur.

## NOTE-472 — LA PART RADIALE DE L'EXCURSION D'APEX : LE NOMBRE QUI DECIDE L'OPERATEUR

NOTE-471 explique l'echec de la borne-par-rotation par « la correction demandee est RADIALE, une
rotation est TANGENTIELLE ». **Le cycle 88 a mesure cette explication au lieu de la laisser en
hypothese** — c'etait le prealable que le cycle 87 s'etait lui-meme impose (« aucune ligne de
solveur ne se touche avant cette mesure »), et il a ete tenu.

`PHYSAPEXR ... rad=<B0>`, emplacement 86 de `*phys-dg*`, latche au MEME argmax que 53-56.
NATURE une LONGUEUR SIGNEE en B0, PAS un rapport : somme ponderee par `aw` des projections de
l'excursion de chaque maillon sur **son propre** levier de chair (les deux maillons n'ont pas le
meme levier). REPERE le monde, contre la pose d'auteur de la meme frame.

    chaine   |rad|/apex  min      mediane   p90      max      rad median   signe<0
    chestL               0,0068   0,9114    0,9755   0,9897   +0,6132 B0   7/186
    chestR               0,0064   0,8465    0,9663   0,9808   +0,5786 B0   7/186

**L'excursion est presque entierement RADIALE, et POSITIVE : le point de chair s'eloigne de son
joint.** Une rotation le deplace sur la sphere de rayon `|bm.o|`, donc perpendiculairement : elle
ne peut agir que sur 9 a 15 %. NOTE-471 est confirmee par une mesure directe.

DEUX CONTROLES, ET ILS SONT DANS LA TRACE, PAS DANS CE COMMENTAIRE :
  - INERTIE AU BIT : la course privee de la seule ligne neuve rend le meme md5
    `863743f90c962b8f488a1ef6e1cd7876` sur 78 462 lignes `PHYS`, 0 differente. Pur observateur.
  - INTEGRITE : `rad` est une projection, donc `|rad| <= apex` doit tenir — 372/372.

**BORNE DE LECTURE, POSEE AVANT QU'ON SUR-LISE LE CHIFFRE.** `rad` n'est PAS l'allongement du
levier : `rad = r^.(p - p_auteur) + |r| - r^.r_auteur` melange la translation du joint projetee
sur le levier et la variation de longueur du levier. **Aucun pourcentage d'elongation de tissu
n'en sort**, et il ne se compare pas au « Absolute stretch clamp: 25% » de §22. Le separer demande
`|bm.o|` publie a cote : c'est le prealable du geste suivant, parce qu'une contraction du levier ne
peut retirer que le second terme.

## NOTE-471 — BORNER LE POINT DE CHAIR PAR UNE ROTATION : ESSAYE AU CYCLE 87, MESURE, REFUTE, RETIRE

**VERDICT, EN TETE, PARCE QUE C'EST LUI QUI COMPTE.** Le mecanisme decrit plus bas a ete
implemente, joue sur la course complete en PAIRE APPARIEE (jambe desarmee / jambe armee, meme
build, meme salle), et **il AGGRAVE la section qu'il visait**. Il est retire ; le code n'existe
plus dans l'arbre. Ce qui suit est conserve parce que la RAISON de l'echec est un resultat, pas
un accident de reglage.

                          c81 (avant)   B = retrait seul   A = retrait + borne
    apex moyen chestL       0,6778          0,7413              0,8382
    apex moyen chestR       0,7007          0,7660              0,8651
    apex max   chestL       0,8929          1,1048              1,1327
    apex max   chestR       0,9405          1,0273              1,2014
    fenetres > 0,50 B0      177/180         182/183             183/183

Prediction posee d'avance par le cycle 86 : « apex max sous 0,52 B0 ; au-dessus de 0,55 le geste
se retire ». Mesure : **1,1327 / 1,2014**. La borne a pourtant bien mordu — `PHYSE21 n=33338`,
`cut_b0=4045,83` — et son controle negatif est propre (`n=0` exactement sur les 14 tags de la
jambe desarmee, contre `PHYSE22 n=59330` dans la meme course).

**LA CAUSE, ET ELLE SE LIT DANS LA DECOMPOSITION.** `|tp|` et `|dp|` ne bougent pas (0,4424 ->
0,4405 et 0,3210 -> 0,3152) : la borne ne touche ni la translation ni le tenseur, comme prevu.
**TOUTE la hausse est dans `rp`, le terme de ROTATION : 0,2721 -> 0,3317 (+21,9 %) et
0,2766 -> 0,3611 (+30,5 %).** Le geste cense retirer de l'excursion en AJOUTE, et il en ajoute
exactement par le canal qu'il actionne.

**POURQUOI — UNE ROTATION EST TANGENTIELLE, LA CORRECTION DEMANDEE EST RADIALE.** Le point de
chair est au bout d'un levier `|o|` = 1,228 / 1,235 B0. Une rotation autour du joint le deplace
sur la SPHERE de rayon `|o|` : le deplacement qu'elle peut produire est orthogonal au levier.
Or la correction demandee, `-(1-gg)*c2`, a une composante RADIALE (le long du levier) que la
rotation ne peut pas produire. La rotation substitue donc un deplacement TANGENTIEL a un
deplacement RADIAL : le deficit radial reste, le tangentiel s'y ajoute **en quadrature**, et la
norme MONTE. C'est arithmetique, pas un reglage — aucune valeur de `D_max` ne l'inverse.

**ET CA N'EST PAS EN CONTRADICTION AVEC LE CYCLE 76, IL FAUT LE DIRE PRECISEMENT.** NOTE-447 a
pose avec succes une borne « par ROTATION, pas par contraction » — mais sur le JOINT, dont le
levier est l'os depuis l'ATTACHE et dont l'excursion a corriger est justement tangentielle a cet
os. Transposer la FORME sans re-verifier la GEOMETRIE etait le pas de trop. **Une forme
d'operateur ne se transporte pas d'une grandeur a une autre : elle se re-derive sur le levier de
la nouvelle grandeur.**

**LE PROCHAIN GESTE, ET IL EST FALSIFIABLE.** La correction radiale d'un point de chair est une
CONTRACTION DU LEVIER DE CHAIR — c'est-a-dire une compression de tissu, que §22 autorise
explicitement dans son budget local (« Local tissue elongation: common 5-15%, large 15-21%,
exceptional 21-25% ») et que §22 DEMANDE meme (« Large apex displacement shall not imply equally
large tissue extension »). Elle ne touche ni `bm.trans` (donc pas la longueur d'os) ni le
determinant si elle est compensee. **PREALABLE OBLIGATOIRE, ET IL EST GRATUIT** : publier
`dot(c2, o^)/|c2|` a cote de `|c2|` dans `PHYSAPEX`. Si la part RADIALE de l'excursion est
faible, l'analyse ci-dessus est fausse et le chantier change. Aucune ligne de solveur ne se
touche avant cette mesure.

---

### CE QUI SUIT DECRIT LE MECANISME RETIRE, CONSERVE POUR LA TRACABILITE


**CE QUI EST REMPLACE, ET POURQUOI CE N'EST PAS UN AJOUT.** `phys-apex-scale` (retire au cycle 87)
appliquait un facteur COMMUN pour ramener la POINTE dans le budget d'apex de §22. La pointe est un
JOINT ; §22 nomme le « distal/apex displacement », c'est-a-dire un point de CHAIR situe a
**1,228 / 1,235 B0** du joint (`recharged_assets/physics_mesh.txt`, enregistrements `ax`). Les deux
grandeurs ne coincident pas, et l'ecart n'est pas un detail de reglage :

  - cycle 76, PAR INTERVENTION : retirer **25 %** de la translation du joint rendait **-0,2 %**
    d'apex sur chestR (et -8,1 % sur chestL) ;
  - cycle 86, PAR DECOMPOSITION de la trace archivee : `e = tp + rp + dp`, et le terme du TENSEUR
    `dp` porte **+40,6 % / +37,3 %** de l'excursion en projection signee. **Aucune borne posee sur
    un joint ne peut l'atteindre** — le tenseur est applique en section 6, apres toutes les
    contraintes.

**LA FORME, ET LES TROIS CONTRAINTES QU'ELLE DOIT RESPECTER.** La borne s'applique la ou `bm` est
complet (section 6, apres le tenseur, apres l'ecriture de la translation), sur l'excursion du point
de chair `c2` que `phys-pt-exc!` vient de calculer :

    ed = |c2|                             l'excursion livree du point de chair
    es = phys-softmin(ed, 0.50 * B0)      §22 l.301, « exceptional <=50% B0 »
    gg = es / ed                          identite stricte sous 0,84 x cap : rien sous le genou

Puis `bm` est TOURNE autour du joint pour amener le point de chair sur la cible :

  1. **`bm.trans` est INTACT.** Une contraction du point de chair vers sa cible passerait par la
     translation du joint, et casserait `|p - b|` — la longueur d'os — que plus aucune passe ne
     pourrait reparer ([[feedback_bound_undone_by_downstream_constraint_loop]], cycle 73/76).
  2. **Le DETERMINANT est intact.** Une rotation le conserve exactement, donc §8 (« 98-101 % of
     neutral volume ») n'est pas touchee par ce geste.
  3. **La cible n'est atteinte qu'a la sphere pres.** `|bm . o|` est invariant par rotation : le
     point ne peut se deplacer que sur la sphere de rayon `|bm . o|` centree sur `bm.trans`. La
     rotation choisie est celle qui vise le point cible ; si la cible n'est pas sur cette sphere,
     c'est le point le plus proche qui est atteint. **Cet ecart se MESURE (`ROOM-APEX` apres
     coup), il ne se calcule pas** — c'est pourquoi la prediction du cycle 86 portait une marge.

**L'ETAT DU SOLVEUR N'EST PAS ECRIT.** La borne ne touche que `bm`, la matrice livree au
renderer ; `*phys-px*` n'est pas modifie. C'est la regle de [NOTE-84] (« la borne est appelee sur
la valeur LIVREE, jamais sur l'etat ») et c'est aussi ce qui rend la simulation du cycle 86 exacte :
sans retro-action de frame a frame, la sortie corrigee se calcule terme a terme depuis la sortie
mesuree.

**CE QUE LA BORNE CONTAMINE, ET IL FAUT LE DIRE.** `dp` est releve AVANT la rotation de correction.
Une rotation conserve sa NORME — `|dp|` reste donc exact — mais pas sa DIRECTION, et `rp`, qui est
DERIVE (`rp = e - tp - dp`), absorbe l'ecart. L'identite `e = tp + rp + dp` referme toujours, mais
le partage entre `rp` et `dp` n'est plus lisible sur les fenetres ou `PHYSE21 n` est non nul. Le
bloc `ROOM-SPEC21` du tableau le declare sur sa propre ligne.

**INTERRUPTEUR ET COMPTEURS.** `*phys-e21-off*` (0 en livraison, 1 desarme) est pose EN MEME TEMPS
que le mecanisme, jamais apres ([[feedback_attribution_harness_outlives_its_defect]]). `PHYSE21
tag=<t> n=<compte> cut_b0=<longueur cumulee / B0>` publie ce que la borne reprend ; desarmee, elle
DOIT rendre exactement 0, et c'est son controle negatif.



---
## NOTE-473 — paires (lien, volume) ou le lien est ENTIEREMENT dans le volume a sa pose de modele : pas de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 91) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; paires (lien, volume) ou le lien est ENTIEREMENT dans le volume a sa pose de modele : pas de
;; surface devant lui, donc rien a traverser. Comptees a chaque mesure, publiees par la salle.
```

---
## NOTE-474 — la somme des profondeurs que ces poussees ont vues a l'entree (u de jeu) : elle donne l'ordre de

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 91) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; la somme des profondeurs que ces poussees ont vues a l'entree (u de jeu) : elle donne l'ordre de
;; grandeur de ce qui restait a corriger apres les balayages, que le compte seul ne dit pas.
```

---
## NOTE-475 — combien d'ensembles le PACKAGE declare, face a combien on en CHARGE. Sans ce second

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 91) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; [NOTE-158] combien d'ensembles le PACKAGE declare, face a combien on en CHARGE. Sans ce second
;; nombre, `sets=64/92` reste dans une ligne de log et la troncature redevient silencieuse.
```

---
## NOTE-476 — FENETRE DE LECTURE de `phys-surf-sd`. lo=0 / hi=-1 rend EXACTEMENT la population de corps :

Migre VERBATIM depuis `jak-hd-physics.gc` (cycle 91) pour tenir le plafond de 4800 lignes
de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; FENETRE DE LECTURE de `phys-surf-sd`. lo=0 / hi=-1 rend EXACTEMENT la population de corps :
;; les valeurs par defaut reproduisent le comportement d'avant ce cycle par construction.
```

---
## NOTE-477 — §22 EST UNE LIMITE *DYNAMIQUE* : CE QUI EST TENU EST DEJA L'EQUILIBRE DE §10-§13

Cycle 91. Le pilotage de `dfb` — l'etirement local de sa §22 — etait l'ECART A LA POSE D'AUTEUR
DEBOUT (`*phys-ox/oy/oz*`), plus l'elongation radiale du maillon. A une orientation TENUE, cet
ecart n'est pas un transitoire : **c'est l'equilibre d'orientation lui-meme**, celui que ses §10,
§11 et §12 chiffrent (« COM toward thorax 18-28% B0 », « Static COM displacement 20-28% B0 »,
« Global lateral COM response 15-24% B0 »). Le moteur le convertissait donc **une seconde fois**
en elongation locale, et sur l'axe du DEPLACEMENT au lieu des trois axes que ces sections bornent.

MESURE, sur la trace ARCHIVEE, sans une seule course neuve (`.autoport/c91_axis_and_downstream.py`) :
`B = dfa^-1 . A` est un etirement UNIAXIAL de determinant 1 (a 3e-4 pres sur les 18 cellules),
**nul a la verticale** (|B - I| = 0,0007 a i=0, la ligne de base de §9), et de magnitude

    lam_max - 1  =  0,43 x |deplacement d'equilibre| / B0      (mediane 1,014 ; 0,93 a 1,30)

ou 0,43 est exactement `PHYS-DYN-K`. Ce n'est donc pas une reponse dynamique : c'est l'equilibre,
compte deux fois. Cout mesure : sur les 16 echelles de forme de §10/§11/§12 lues sur le triedre
de sa §7, **13 cellules DANS pour `dfa` seul, 6 pour le produit que la peau recoit**.

LE CORRECTIF, ET SA FORME. On ne retire pas le canal — sa §22 en a besoin des que ca bouge. On
retire de son pilotage la partie **TENUE**, par une moyenne lente `*phys-dyb*` : `d := r - dbar`,
`dbar += ka.d`. A l'equilibre `d -> 0` et `dfb -> I`, donc la peau recoit l'equilibre que la spec
specifie ; en transitoire `dbar` ne suit pas et le canal repond comme avant.

LA CONSTANTE VIENT DE DEUX LIGNES DE SPEC, PAS D'UN REGLAGE. `PHYS-DYN-TAU = 0,30 s` :
  - **borne haute** — §27 (« mostly settled ~1.0-1.5 s ») et la fenetre d'etablissement de la
    salle (60 frames = 1,0 s) : apres 1 s il doit rester moins de 5 % de la partie tenue.
    `e^(-1,0/0,30) = 3,6 %`.
  - **borne basse** — §24 (modes propres 2,30 / 2,50 / 2,65 Hz) : le filtre doit LAISSER PASSER
    le mode le plus lent. Coupure `1/(2.pi.0,30) = 0,53 Hz`, transmission a 2,30 Hz =
    `2,30/sqrt(2,30^2 + 0,53^2) = 97,4 %`.
Aucune valeur n'a ete ajustee sur une mesure de sortie (`never-fit-a-parameter-to-the-instrument`).

`*phys-dyb-off*` desarme le filtre par `ka = 0` : `dbar` reste nul et `d = r - 0` reproduit
**l'expression exacte d'avant le cycle 91**, donc la jambe desarmee est bit-pour-bit l'ancienne.

CE QUE LE CORRECTIF NE PEUT PAS CHANGER, ET C'EST LE CONTROLE : `*phys-dfm*` n'entre QUE dans la
partie 3x3 de la matrice d'os ecrite (`:3898-3906`), la translation etant reposee juste apres
depuis `*phys-px/py/pz*`. Aucune position simulee, aucune vitesse, aucune contrainte ne le lit.
Toute grandeur de POSITION du tableau doit donc rester identique au bit ; seules les grandeurs de
FORME et les compteurs `dyn*` ont le droit de bouger.

## [NOTE-433] §24 — LA RAIDEUR PAR AXE EST POSEE *APRES* LE PROJECTEUR DE LONGUEUR (cycle 99)

`jak-hd-physics.gc:205-206` (constantes) et `:2673-2674` (site d'armement).

**LE DEFAUT, ETABLI AUX CYCLES 94/96/97.** La raideur par axe est definie en 3-D
(`K = diag(s_v, s_ap, s_lat)` dans le triedre de l'ancre), PUIS la contrainte de longueur
restreint le mouvement au plan perpendiculaire a l'os. La raideur qui atteint reellement le joint
est donc `A = P K P`, `P = I - m^ m^T`. Avec les compliances de §29 lues comme des raideurs
(`s = 1/0.90`, `1/0.82`), les deux valeurs propres non nulles de `A` valent 1,1078 / 1,1911
(chestL) et 1,1078 / 1,1917 (chestR) : un rapport de frequences de **1,031-1,039 quand §24 en
exige 1,0600**. L'anisotropie n'arrivait pas au joint. `sv` est de surcroit annulee par le
projecteur, l'os etant a ~92 % sur la verticale du triedre.

**LE CORRECTIF : ON INVERSE `P K P` AU LIEU DE POSER `K`.** Pour un `A` de rang 2 :

    T = trace(A) = somme_i s_i (1 - m_i^2)                  = tau_ap + tau_lat
    D = det(K) * m^T K^-1 m^ = s_ap s_lat m_v^2
                            + s_v s_lat m_ap^2
                            + s_v s_ap m_lat^2              = tau_ap * tau_lat

avec `tau_ap = (2.50/2.30)^2 = 1,1814745` et `tau_lat = (2.65/2.30)^2 = 1,3275047`, les rapports
de raideur que §24 (l.325-329) demande. `s_v` reste a 1,0. La premiere equation est LINEAIRE :
on substitue et on resout la quadratique en `s_lat`. Forme fermee, aucun ajustement.

**LES DEUX RACINES SONT POSITIVES** — la positivite ne discrimine pas. Ce qui discrimine est
l'AFFECTATION DES MODES : la racine `s_ap > s_lat` place le mode LENT a 85,8 deg de `ap`, donc
§24 a l'envers ; la racine retenue le place a 11,4 deg de `ap` et le mode rapide a 21,8 deg de
`lat`. C'est ce test, pas le signe, qui choisit.

**LES DEUX CHAINES DONNENT LA MEME REPONSE, ET C'EST POURQUOI DEUX CONSTANTES SUFFISENT.**
En base d'ANCRE (et non en base monde — `*phys-ux/uy/uz*` sont deja tournes par `w2l`,
cf. `:2846-2853`), l'axe d'os vaut `(v -0,919254, ap -0,147761, lat +0,364882)` sur chestL et
`(v -0,920567, ap -0,147941, lat -0,361483)` sur chestR : de vrais miroirs, et seule la
composante laterale change de signe — or seuls les CARRES entrent dans `T` et `D`. Solutions :
1,186970 / 1,376174 et 1,186953 / 1,375137, soit **0,075 % d'ecart**. Les constantes posees sont
leur moyenne. Sensibilite : 1 deg de rotation d'os deplace `s_ap` de 0,12 % et `s_lat` de 0,38 %.

**LE CANAL RADIAL DE §23 LIT LE MEME `K`** (`:3038-3040`, `d_i = s_i q_i` sur le point libre, qui
n'est PAS projete) : `f_v` monte donc aussi, de +1,1 %. C'est declare, pas ignore — et c'est la
raison pour laquelle les rapports `ap/v` et `lat/v` atteignent 1,059 et 1,122 au lieu des 1,087 et
1,152 de §24, quand `lat/ap` tombe a 1,0600 exactement. Les six lectures restent DANS leurs bandes.

**`zeta` EST INVARIANT PAR CONSTRUCTION**, et c'est ce qui protege §25 et §26 : le taux par axe
vaut `rate * sqrt(s_i)` (`:2954-2956`) quand la pulsation vaut `omega * sqrt(s_i)`, donc
`zeta_i = rate_i / (2 omega_i)` ne depend pas de `s_i`.

**CE QUE CA COUTE, ET JE NE LE LISSE PAS : §29 ET §24 SONT INCOMPATIBLES.** Les compliances
equivalentes deviennent 0,8425 / 0,7267 la ou §29 (l.366-367) ecrit 0,90 / 0,82 — soit -6,4 % et
-11,4 %. Le projecteur dilue l'anisotropie : il faut `s_lat/s_ap = 1,1594` dans `K` brut pour
obtenir 1,1236 dans le plan. Tant que c'est le MEME bouton qui porte les deux sections, l'une des
deux cede. Les chiffres de §29 tiendraient simultanement si l'inertie effective differait par axe
(`m_ap/m_v = 0,940`, `m_lat/m_v = 0,919`) — ce n'est ni mesure ni implemente, donc ce n'est PAS
une echappatoire, c'est une question ouverte a remonter a l'owner. `PHYS-MOB-TOR` (§29 torsion,
0,72) n'est pas touchee.

### [NOTE-433] — CE QUE LA COURSE A MESURE, ET LA PARTIE DE MA PREDICTION QU'ELLE REFUTE

Course x86 du cycle 99, meme salle, meme tableau, meme trace-pipeline que le cycle 98 ; seule la
paire de constantes change. `PHYSAXISS c=0/c=1 sv=1.0000 sap=1.1869 slat=1.3756` — le binaire porte
bien les nouvelles valeurs (le cycle 98 portait `1.1111 / 1.2195`).

**CE QUI EST CONFIRME — les deltas tangentiels.** Sur `ROOM-AXRATIO-SPEC24` :

    chestL  ap   2.440 -> 2.510 Hz  (+2.9 % mesure, +3.3 % predit)   ecart au nominal §24 : -3.24 % -> -0.47 %
    chestL  lat  2.550 -> 2.720 Hz  (+6.7 % mesure, +5.6 % predit)   ecart au nominal §24 : -4.60 % -> +1.76 %
    chestR  lat  non lisible -> 2.690 Hz DANS                        ecart au nominal §24 : -3.12 %

**CE QUI EST REFUTE — « `f_v` monte de +1,1 % ».** J'avais ecrit que le canal radial de §23 lisant le
meme `K`, la verticale monterait. `ROOM-AXFIT-RAD` mesure **chestL 2.320 -> 2.320** (identique au
millieme) et **chestR 2.415 -> 2.410** (-0,2 %). La verticale N'A PAS BOUGE. Le raisonnement
(`:3038-3040` applique bien `s_i` au point libre) reste vrai au code ; ce qui est faux est d'en
conclure que la FREQUENCE lue sur ce canal suit `sqrt(m^T K m^)`. La consequence pratique est
FAVORABLE — les rapports `ap/v` et `lat/v` gagnent tout le delta tangentiel au lieu d'en perdre une
part au denominateur — mais elle est favorable par accident, pas par prevision, et c'est dit ici.

**CE QUE CA COUTE, MESURE, ET QUI N'EST PAS LISSE :**
  * `ROOM-SKINPEN-VERDICT chestR` passe de `-0.0021 m -> TENUE` a `+0.0010 m -> DEPASSEE` : la
    penetration de peau monte de 0.0863 a 0.0893 m et franchit SON PROPRE plancher (0.0883).
    `chestL` etait deja dessus et se degrade de +0.0079 a +0.0083 m. La gate COLLIDE §33/§34 du
    validateur passe donc au ROUGE. Mecanisme coherent : une raideur tangentielle plus haute tire le
    point de chair plus fort vers sa cible et le repoussoir de collision perd le bras de fer.
  * `ROOM-RINGFIT repos chestR ap` sort par le HAUT : 2.645 DANS -> 2.795 HORS (plafond §24-ap 2.7).
  * La jambe de CONTROLE `ROOM-AXFIT-RAD-NOLEN` (contrainte de longueur DESARMEE) se degrade : 3
    cellules sur 6 passent `INSUFFISANT` (residu > 0.08), aucune ne l'etait. A contrainte levee et
    raideur plus haute, la serie ne porte plus un mode unique.

**CE QUI S'AMELIORE PAR AILLEURS** : `ROOM-COM` (§22) baisse des deux cotes, chestL 0.4940 -> 0.4583
et chestR 0.4452 -> 0.4302 B0 — toujours au-dessus du plafond dur 0.40, mais dans le bon sens.

**RESERVE D'INSTRUMENT, NOMMEE ET NON TRAITEE ICI.** Le verdict §24 du TABLEAU est bati sur les six
fenetres AX d'origine (`ROOM-AXFIT`), pas sur les fenetres a entree propre `PH-AXC` que le cycle 96 a
construites (leurs tags `PHYSAXPRE`/`PHYSAXWN`/`PHYSAXRESN` sont bien dans la trace, mais le tableau
ne les lit pas). Le registre, lui, cite l'ajustement hors ligne du cycle 97 sur ces fenetres propres.
**Deux instruments, un seul numero de section** : c'est ce qui explique que le cycle 97 lise
`chestL lat = 2.393 SOUS` la ou le tableau lisait `2.550 DANS` a la meme course. A reconcilier avant
de prononcer §24 `TENUE`, et c'est le blocage reel de la section.

## NOTE-478 — SPEC 37, LA MOITIE ROTATION DU REBASE. Elle n'existait pas ; la cellule du registre
affirmait le contraire, et le cycle 101 l'a etabli au source. Ce qui suit est le correctif, et il
est une GENERALISATION STRICTE de la moitie translation, pas un mecanisme de plus.

**LE DECLENCHEUR NE CHANGE PAS.** Aucun seuil neuf, aucun parametre neuf, aucun etat neuf. Le
`when` reste `rbd > 7.00 * B0` ([NOTE-83]) : un rebase est UNE operation sur UN evenement, et
donner a la rotation son propre seuil aurait demande d'arbitrer un nombre que rien ne derive.

**L'ACTION PASSE D'UNE TRANSLATION A UN MOUVEMENT RIGIDE.**

    avant :  p' = p + (anc - anp)                     translation pure
    apres :  p' = R.p + t   avec   R = a0m^T . am ,   t = anc - R.anp

`R` est la rotation que l'ancre a subie en une frame, `a0m` etant son orientation a la frame -1.
Les quatre jeux de points de l'etat (`p`, `q` verlet, `cp`, `cq`) subissent le MEME mouvement, donc
aucune vitesse relative n'est creee : c'est exactement « artificial transforms must not generate
physical breast impulses » (l.441).

**POURQUOI C'EST UNE GENERALISATION STRICTE.** Quand `R = I`, `R.p = p` au bit pres (produit par
la matrice identite) et `t = anc - anp`, donc `p' = p + (anc - anp)` : la forme d'avant, a
l'identique. Le chemin de code vit ENTIEREMENT dans le `when`, donc toute fenetre ou le rebase ne
tire pas est inchangee AU BIT — c'est le controle de ce cycle, pose avant la course.

**L'ETAT EST REUTILISE, PAS DUPLIQUE.** `*phys-a0m*` porte deja l'orientation de l'ancre a la
frame -1 ; il est maintenu par le bloc de torsion de §29, qui s'execute PLUS LOIN dans la meme
iteration de `(dotimes (c nch))` (site du rebase :2718, mise a jour de `a0m` :3691/:3717 — meme
fonction `jak-hd-physics-step`, profondeur de parentheses verifiee). A l'instant du rebase, `a0m`
est donc la frame -1. Le garde `*phys-twok*` couvre le seul cas ou il ne le serait pas — la toute
premiere passe, ou `a0m` vaut encore ZERO : sans garde, `R` serait la matrice nulle et TOUT l'etat
s'effondrerait sur l'ancre. Le garde met a l'identite les DEUX matrices de la composition (`rot` ET
la copie `tmp` de `am`), pas seulement la premiere : mettre `rot = I` seul laisserait `R = am`,
c'est-a-dire l'orientation ABSOLUE de l'ancre appliquee a l'etat — pire que le defaut. Avec les
deux, `R = I` exactement et `t = anc - anp` : le rebase retombe sur sa moitie translation, au bit.
Ce chemin ne devrait jamais s'executer (`twok` passe a 1 des la 1re passe, le rebase exige
`warm > 1`, soit la 3e, et les deux sont remis a zero au meme endroit :603/:618) — il est ecrit
parce que « ne devrait jamais » n'est pas une mesure.

**RESERVE DECLAREE, ET ELLE EST A NOUS.** La mise a jour de `a0m` est gardee par
`(> al 0.0001)` (`al` = longueur de l'axe de chaine). Sur une frame ou ce garde ne passerait pas,
`a0m` aurait plus d'une frame d'age et `R` couvrirait plus d'une frame. Le rebase ne tire que sur
une discontinuite, ou transporter par un delta multi-frames reste un mouvement rigide coherent ;
mais l'age n'est pas MESURE, et tant qu'il ne l'est pas, cette ligne le dit au lieu de le taire.

**IMPLEMENTATION.** `phys-rebase-pt!` prend les trois tableaux d'un jeu de points, l'indice du
maillon, les deux matrices (`a0m^T` puis `am` — deux rotations successives, jamais leur produit :
`matrix*!` sur des 4x4 melangerait les translations dans le bloc 3x3) et le vecteur `t`. Huit
parametres : c'est la limite du compilateur, et c'est pourquoi la translation est pre-composee dans
`t` au site d'appel plutot que passee en `anc`/`anp`.

---
## NOTE-470 — cycle 104 : §22 ET §33/§34 SONT ALTERNEES, PARCE QU'ELLES VIVENT SUR LA MEME SPHERE

**LE DEFAUT, ETABLI PAR ABLATION AU CYCLE 103, PAS SUPPOSE.** L'ordre livre etait
`phys-skin-chain` puis `phys-cap-e22!`, une fois chacune. Les deux sont des ROTATIONS autour de la
MEME attache, donc leurs deux ensembles admissibles vivent sur la MEME sphere de rayon `|p - b|` :
la seconde peut defaire la premiere, et c'est ce qu'elle faisait. `*phys-e22-off*` 0 -> 1 fait
passer `ROOM-SKINPEN` de chestR de **0.0886 a 0.0836 m** — la borne de §22 enfoncait **5,0 mm** de
peau dans le thorax, et 0,3 mm de cet enfoncement passaient au-dessus du plancher d'auteur
(0.0883 m), c'est-a-dire au-dessus de la regle 6 de l'owner : « rien ne traverse le mesh de son
personnage, quelle qu'en soit la raison ».

C'etait la classe `bound-undone-by-downstream-constraint-loop` **dans l'autre sens** : ce n'est pas
§22 qui se faisait effacer en aval, c'est §22 qui effacait §33/§34. Et les DEUX docstrings se
contredisaient — celle de `phys-skin-chain` disait « rien ne s'execute apres elle », celle de
`phys-cap-e22!` disait « rien n'ecrit `*phys-px*` apres elle ». Le code rendait la seconde vraie.

**LE CORRECTIF, ET POURQUOI CE N'EST PAS UN ECHANGE DE ROUGE.** Permuter simplement les deux
appels aurait rendu §34 verte en rendant §22 rouge : NOTE-447 a mesure que sans borne posee apres
la peau, l'etage 6 vaut 0,6539 / 0,6670 B0 contre un plafond dur de 0,50, sur 184/186 et 156/186
fenetres. Le cycle 103 l'avait vu et avait refuse de trancher a l'aveugle — a juste titre.

Les deux contraintes sont donc **ALTERNEES** :

```
(dotimes (it 2) (phys-cap-e22! skel sc n rlk an nbone) (phys-skin-chain skel sc n rlk nbone))
```

**L'INTERSECTION N'EST PAS VIDE, ET C'EST CE QUI FAIT LA DIFFERENCE ENTRE UNE ALTERNANCE ET UN
BALANCIER.** La cible `t` de §22 EST la pose d'auteur ; la penetration de la pose d'auteur EST, par
definition, le plancher `ROOM-SKINPEN-REST`. Le centre de la calotte admissible de §22 est donc un
point ou §33/§34 est tenue exactement a son plancher. Les deux ensembles se coupent, et des
projections alternees sur deux ensembles geodesiquement convexes d'intersection non vide
convergent vers cette intersection. Ce n'est pas un reglage : c'est la raison pour laquelle deux
tours suffisent la ou un tour de chaque ne suffisait pas.

**ORDRE DANS LE TOUR : §22 D'ABORD, LA PEAU ENSUITE.** La derniere ecriture de `*phys-px*` de la
frame est donc la fermeture de peau, ce qui rend enfin VRAIE la docstring de `phys-skin-chain`
(posee au cycle 74) et ce qui applique la regle 6 de l'owner, qui est dans sa liste
« RÈGLES QUI NE SE NÉGOCIENT JAMAIS ». §22 n'est pas retiree pour autant : elle passe DEUX fois par
frame, donc sa borne tient partout ou elle n'entre pas en conflit avec la peau, et ce qu'elle perd
la ou le conflit existe se lit a l'etage 6 de `PHYSSTG`, publie a chaque cycle.

**COUT EN LIGNES : ZERO.** 3 lignes remplacent 3 lignes, `jak-hd-physics.gc` reste a 4800 pour un
plafond CLEAN de 4800. **COUT EN CALCUL : `phys-skin-chain` est evaluee deux fois par frame et par
maillon au lieu d'une** — c'est la partie chere du solveur (`ROOM-SKINPEN-TESTS` compte 154 462 959
echantillons de surface sur la fenetre), et le cout est declare, pas tu.

## NOTE-479 — cycle 105 : LE VERDICT DE §33/§34 EST VALIDE QUAND IL ECHOUE ET **VIDE** QUAND IL PASSE

`ROOM-SKINPEN-VERDICT` publie `skinpen - skinrest`. Les deux termes sont des **maxima courants
INDEPENDANTS** (`jak-hd-physics.gc:2404-2405` et `:2412-2413`), remis a zero ensemble par
`phys-skinpen-reset!` (`:2087`) mais latches separement : rien ne les oblige a tomber sur la meme
frame, le meme maillon, ni le meme echantillon `ms`. Le tag `run` couvre TOUTE la course (un seul
`physroom-emit-diag "run"`, `phys-room.gc:3588`, depuis le reset de `:3391`), soit 31 animations
x 5 pilotages : les deux argmax ont ~16 700 frames pour diverger.

**L'ASYMETRIE LOGIQUE, ET C'EST TOUTE LA NOTE.**
  * `max(skinpen) > max(skinrest)`  ==> il EXISTE un echantillon qui viole. **SOUND.**
  * `max(skinpen) <= max(skinrest)` ==> **RIEN.** Un maximum sous un autre maximum ne dit rien
    d'une inegalite ECHANTILLON PAR ECHANTILLON. La direction qui fait passer est vide.

Donc la ligne est un bon detecteur d'ECHEC et un detecteur de SUCCES sans contenu. Or c'est
exactement par la direction vide que §34 a gagne son statut au cycle 104.

**LA MESURE, tag=run, une seule fenetre, memes frames, memes echantillons, meme fonction :**

    chestL   max(skinpen) 280.1669 u   max(skinrest) 250.7885 u   difference  +29.3784 u = +0.0072 m
    chestR   max(skinpen) 349.7382 u   max(skinrest) 361.8413 u   difference  -12.1031 u = -0.0030 m

**LE `-0.0030` DE chestR SE REFUTE TOUT SEUL.** La grandeur visee est une profondeur AJOUTEE,
ecretee a zero par construction : elle ne peut pas etre negative. Une difference negative est donc
la **preuve** que les deux maxima ne sont pas co-localises — et c'est ce nombre-la, et lui seul,
qui imprimait `TENUE`.

**ET LA BORNE QUE [NOTE-241] DECLARAIT « PAR CONSTRUCTION » EST REFUTEE PAR LA MEME LIGNE.**
[NOTE-241] (cycle 61) ecrit : « elle borne la mesure qu'elle vise : `skinpen <= skinrest` sur la
fenetre, par construction ». Si cette borne tenait ECHANTILLON PAR ECHANTILLON elle tiendrait sur
les maxima. Sur **chestL** elle ne tient pas (280.17 > 250.79) : au moins un echantillon viole. Sur
chestR l'ordre des maxima lui est compatible — ce qui, par l'asymetrie ci-dessus, ne la prouve pas.
Ce n'est pas une construction, c'est une esperance, et elle est fausse sur une chaine sur deux.

**LA GRANDEUR APPARIEE EXISTE, ELLE EST CALCULEE DANS LA MEME PASSE, ET LE VERDICT NE LA LIT PAS.**
`skinadd` (`*phys-saf*`, `:2411`) est prise sur le MEME echantillon, a la MEME frame, contre la
MEME surface. Elle rend **617.7986 u = 0.1508 m** (chestL) et **602.1514 u = 0.1470 m** (chestR) :
**21x** ce que la difference de maxima publie sur chestL, et un nombre POSITIF la ou celle-ci est
negative. L'inegalite `max(A) - max(B) <= max(A - B)` rend l'ecart inevitable et unilateral : la
ligne de verdict est assise sur la borne INFERIEURE de la grandeur qu'elle pretend borner.

**POURQUOI LA GRANDEUR APPARIEE NE PORTAIT PAS LE VERDICT : SON CONTROLE N'EN EST PAS UN.**
`ROOM-SKINADD-CONTROL` declarait `skinadd` NON PROBANT sur la foi d'une injection de 400 u
(`*phys-inject*`). Cette injection ne peut pas la toucher, et c'est structurel :
  1. `phys-inject-probe!` (`:2276`) tourne **APRES** `phys-pen-chain` (`:3328` puis `:3336`), seul
     ecrivain de `*phys-saf*` / `*phys-skinadd*` ;
  2. elle n'appelle **jamais** `phys-surf-sd` — elle ne mesure que `phys-link-pen`, contre les
     VOLUMES : c'est le controle de `meshpen` ([NOTE-155]), pas celui de la peau ;
  3. elle **restaure** `*phys-px/py/pz*` avant de rendre la main (`:2350-2355`).
Les deux jambes comparees (`pcon` / `pcoff`) sont donc deux FENETRES differentes et rien d'autre —
d'ou un « arme 0.1219 < desarme 0.1368 » qui n'est pas un controle qui echoue mais un controle
absent. C'est [[feedback_injection_must_displace_the_measured_point]] : deplacer un point que la
mesure ne sonde pas, apres qu'elle a deja latche.

**CE QUE LE CYCLE 105 CHANGE.**
  * `:2411` publie desormais `(- (fmin 0.0 sa) sd)` — **exactement** l'expression que la contrainte
    minimise (`:1971`). Deux formules pour une meme question etaient en vigueur : la mesure ajoutait
    la distance de SORTIE du point d'auteur sur les lectures ou il est DEHORS (`skinout` = 105 441,
    ~9,8 % des lectures). L'ecretage ne peut que faire BAISSER `skinadd`, jamais monter. **0 ligne**
    (4800 -> 4800).
  * `ROOM-SKINADD-CONTROL` cesse de citer une injection qui ne l'exerce pas et passe a l'ABLATION
    de la contrainte elle-meme (`*phys-skin-off*`, tags `skin-armed` / `skin-disarmed`), qui deplace
    le point MESURE. Les tailles de population sont publiees A COTE : 148 260 086 contre
    25 748 571, soit **5,76x** — comparer deux MAXIMA sur des populations dans ce rapport est
    `ratio-of-two-statistics`, et un controle qui tire CONTRE ce biais (la petite jambe rend le plus
    grand maximum) est concluant, tandis qu'un ecart DANS le sens du biais ne l'est pas.
  * `ROOM-SKINPEN-VERDICT` publie les TROIS grandeurs (difference de maxima, appariee, tailles) et
    **refuse d'imprimer `TENUE`** sur la direction vide. Regle du 2026-08-19 23:50, appliquee au mot.

**CE QUI N'EST PAS TOUCHE : LA GATE.** `phase-Grecharged-secondary-motion.sh:434-451` lit
`ROOM-SKINPEN:` et `ROOM-SKINPEN-REST:`, pas la ligne de verdict, pas `skinadd`. Aucune de ces
corrections ne peut faire verdir quoi que ce soit par accident (regle 5, et la condition posee par
l'arbitrage du 2026-08-19 23:50). La faiblesse de la gate — un plancher unique `PIRE-DES-DEUX`
applique aux DEUX chaines — est remontee, pas corrigee.

## NOTE-480 — cycle 105 (suite) : LE PLAFOND DE DEPLACEMENT EST **REFUTE** COMME COUPABLE SUR chestL, ET CE QUI RESTE EST UNE BORNE DE LEVIER

Le cycle 104 nommait comme prochaine tache « faire fermer la contrainte de peau sur chestL » avec
un ecart de **7,2 mm**. Le cycle 105 a montre que ce chiffre venait d'une difference de deux maxima
latches separement : la vraie cible est **280,1669 u = 0,0684 m**, soit **9,5x** plus. Cette note
resserre le diagnostic AVANT d'engager le chantier, et elle ELIMINE une hypothese sur les trois.

**HYPOTHESE B — LE PLAFOND `-dn` — REFUTEE, PAR ALGEBRE, SUR L'ECHANTILLON QUI DECIDE.**
La contrainte borne sa correction par `v = fmin((fmin 0.0 sa) - sd, -dn)` avec
`dn = (o - b) . n` : `o` le joint simule a l'entree, `b` le joint d'AUTEUR, `n` la normale de
l'echantillon (sortante — c'est le gradient de `phys-surf-sd`, et le code pousse vers `+nb`).
Le cycle 105 etablit que sur chestL, a l'argmax, **`sa >= 0`** (`skinpen` et `skinadd` EGAUX au
chiffre, 280,1669). L'echantillon et le joint partagent le MEME deplacement (l'offset `ap` est
rigide), donc `n . (o - b) ~= sd - sa <= sd < 0`, d'ou **`-dn >= sa - sd >= -sd = v demande`**.
**Le plafond laisse donc passer la totalite de la correction demandee.** Il n'est pas le coupable.

**CE QUI RESTE, ET C'EST UNE BORNE DE FORME, PAS UN REGLAGE.** La correction est une **ROTATION**
autour de l'attache du maillon. Son autorite dans la direction NORMALE est bornee, par iteration :

    progres_normal <= ln * kr/sqrt(1+kr^2) * pp ,  avec kr <= 0.5  donc  <= 0.4472 * ln * pp

ou `pp = sin(angle entre la normale n et l'axe attache->joint h)`. Une rotation est TANGENTIELLE :
quand la poussee demandee devient RADIALE (`pp -> 0`), son autorite tend vers zero, et sous
`pp <= 0.05` le code ne corrige meme plus du tout. C'est
[[feedback_operator_form_does_not_transport_between_quantities]], sur un autre operateur.

**LES DEUX LEVIERS SONT MESURES** (`PHYSBONE c=0`) : racine `l=0` **1040,4951 u**, chair `l=1`
**140,4159 u**. Avec 6 iterations correctrices, fermer 280,1669 u exige donc :

    maillon        ln          progres max / iteration     pp requis      angle n/os requis
    racine l=0   1040,4951 u      465,32 * pp u            >= 0,1003        >= 5,8 deg
    chair  l=1    140,4159 u       62,80 * pp u            >= 0,7436       >= 48,0 deg

**C'EST UNE CONDITION NECESSAIRE, ET ELLE EST GENEREUSE** : elle suppose `kr` sature a 0,5 a CHAQUE
iteration et aucune interference entre echantillons. Le progres reel est inferieur.

**LA MESURE QUI TRANCHE, ET ELLE EST FALSIFIABLE.** Instrumenter, a l'argmax de `skinadd` : (1) le
MAILLON proprietaire, (2) `pp`, (3) `kr` et s'il sature. Alors :
  * si l'echantillon vit sur le maillon de CHAIR avec `pp < 0,74`, la contrainte **ne peut pas**
    fermer avec sa forme et son budget actuels — le chantier est STRUCTUREL, pas un reglage
    d'iterations ;
  * si `pp >= 0,74`, ou si l'echantillon vit sur la RACINE, la borne de levier n'explique rien et
    il reste l'hypothese C (un echantillon corrige par iteration, 6 iterations, 8 echantillons).

**ET LE PIEGE A NE PAS TOMBER DEDANS, ECRIT D'AVANCE.** « Il suffit d'ajouter une composante
RADIALE » est faux tel quel : une poussee radiale change la LONGUEUR du maillon, que
`phys-length-chain` reprojette et que `ROOM-STRETCH <= 3 %` interdit (l'owner : « les seins sont
FERMES, l'os ne s'allonge pas »). C'est precisement pourquoi l'auteur de la contrainte a choisi une
rotation. Le chantier doit donc arbitrer entre : porter la correction sur le maillon au GRAND
levier (racine), relever le plafond `kr`, augmenter les iterations, ou admettre une deformation de
CHAIR qui n'est pas une elongation d'OS. Aucune de ces quatre voies n'est gratuite, et le cycle qui
l'engage doit publier ce qu'elle coute ([[feedback_never_spend_the_bit_identity_control_on_line_count]]).

**COUT EN LIGNES DE MOTEUR : ZERO** — cette note ne touche pas le moteur. Mais l'instrumentation
qu'elle prescrit, elle, en demande, et la marge est **0** (4800/4800). Le plafond CLEAN est donc le
blocage effectif du prochain cycle, et c'est remonte comme tel.


## NOTE-481  (moteur, en-tete du fichier, lignes 4-10 avant le cycle 106)

Bloc d'en-tete deplace VERBATIM ici au cycle 106 pour rendre 6 lignes sous le plafond CLEAN
de 4800 (le moteur y etait a 4800/4800, marge ZERO). Aucune ligne de CODE n'a bouge :
`git diff` du cycle ne montre que des lignes de commentaire a cet endroit.

```
;; jak-hd-physics.gc — PHYSIQUE SECONDAIRE DE KEIRA (depart propre 2026-08-11).
;;
;; [NOTE-000] LA FORME DU MOTEUR (l'ecart a la pose d'auteur en repere ancre) ET COMMENT ELLE
;; FAIT TOMBER LES SPEC 1/2/3/4/5/7 D'UN COUP. -> jak-hd-physics-NOTES.md
;;
;; REGLE 0 (owner) : un commentaire n'est pas une preuve. Tout ce que ce fichier PRETEND faire est
;; mesure par la salle de test (phys-room.gc) et publie dans keira-room-table.txt.
```


## NOTE-482  (moteur, `phys-skin-chain` et `phys-pen-chain`, cycle 106)

**CE QUE MESURE `*phys-skl*`, ET POURQUOI CETTE GRANDEUR-LA.** Le cycle 105 a laisse une question
nommee et falsifiable : la contrainte de peau laisse 0,0684 m (chestL) / 0,0681 m (chestR) de
profondeur AJOUTEE par la physique, et le plafond de deplacement `-dn` est REFUTE comme coupable
sur chestL. Ce qui restait etait une **borne de LEVIER** : la correction est une ROTATION autour
de l'attache, donc son autorite dans la direction NORMALE vaut au plus `0,4472 * ln * pp` par
iteration, ou `ln` est la longueur du maillon et `pp = sin(angle entre la normale et l'axe de
l'os)`. Six iterations ne peuvent donc fermer que `2,683 * ln * pp`.

  * `ln = 140,4159 u` (maillon de CHAIR) exige `pp >= 0,7436`, soit 48,0 deg ;
  * `ln = 1040,4951 u` (maillon RACINE) exige `pp >= 0,1003`, soit 5,8 deg.

**NATURE ET REPERE.** `bv`, `ln` et le residu sont des LONGUEURS en unites de jeu (4096 u = 1 m),
maxima de FENETRE (la fenetre de `phys-diag-reset!`, la meme que `phys-skc`). `pp` est un SINUS
sans dimension. Les indices de maillon sont des ENTIERS ranges dans des cases flottantes. Le
repere est le MONDE, frame courante. **Piege declare** : les cases 0 a 4 sont co-localisees (elles
sont ecrites ENSEMBLE, au meme argmax), mais les cases 10 et 13 sont des maxima SEPARES — les
comparer entre elles est `ratio-of-two-statistics`, exactement le defaut que le cycle 105 a retire
du verdict de §34.

**POURQUOI LE LATCH EST POSE AVANT LE TEST `pp > 0.05` ET PAS APRES.** Quand `pp <= 0.05` le
moteur ne corrige RIEN : la demande est refusee en silence, et `*phys-skc-w*` — qui ne latche
qu'apres le test — ne la voit jamais. Un refus faute de levier est precisement la forme la plus
directe du defaut structurel cherche ; il fallait donc le compter (cases 5 a 8) et non le laisser
tomber dans l'angle mort de l'instrument precedent.

**CONTROLE INTERNE.** La case 13 est un maximum de `add` par chaine, latche a la main dans
`phys-pen-chain` ; `*phys-skinadd*` est le meme maximum obtenu par un autre chemin (max des
maxima de frame). Les deux DOIVENT etre egaux au chiffre. Un ecart denonce le latch, pas le
solveur.

**COUT EN LIGNES DE MOTEUR : +3** (un global, un latch de levier, un accesseur), les autres
latches etant des extensions de lignes existantes. Les lignes ont ete rendues en migrant l'en-tete
du fichier vers [NOTE-481], VERBATIM — aucune ligne de CODE n'a bouge, et c'est la seule methode
autorisee ([[feedback_never_spend_the_bit_identity_control_on_line_count]]).

**AJOUT DU MEME CYCLE — LE TRIPLET CO-LOCALISE DE LA 7e PASSE (cases 15 a 19).** La premiere
course a rendu un fait que je ne pouvais etablir que par une INEGALITE ENTRE DEUX MAXIMA :
`max(min(add, -dn))` = 129,55 u contre `max(add)` = 280,17 u sur chestL. L'inegalite est
rigoureuse — le `min` est le seul operateur entre les deux — mais comparer deux maxima est
exactement le defaut que le cycle 105 a retire du verdict de SPEC 34, et je ne construis pas un
diagnostic dessus. Les cases 15 a 19 lisent donc `add` NON ECRETEE, le plafond `-dn`, le module du
deplacement du joint par rapport a la pose d'auteur, le maillon et la valeur retenue **dans la
MEME expression, sur le MEME echantillon, a la MEME frame**. La difference `add - v` est alors ce
que le plafond retient A CE POINT, pas un ecart entre deux populations.

`rdisp` (le module du deplacement) est la pour trancher le MECANISME et pas seulement le fait :
`-dn` est la composante NORMALE de ce deplacement. Si `-dn << rdisp`, le deplacement qui produit la
penetration est en grande part TANGENTIEL, et un plafond qui ne borne que la composante normale
est alors trop serre par construction, pas par reglage. COUT EN LIGNES : **zero** — le latch est
une extension de la ligne qui existait deja.


## NOTE-483  (moteur, `phys-skin-chain`, le plafond de deplacement — cycle 106)

**[NOTE-291] EST CORRIGEE PAR UNE MESURE CO-LOCALISEE, ET LA MESURE EST NETTE.** La note posait
que la contrainte de peau ne peut se voir demander que de defaire « SA PROPRE part RENTRANTE »,
et l'operationnalisait par `-dot(dj, n)` — la composante NORMALE de l'ecart du joint a sa pose
d'auteur. Elle notait meme la propriete comme un avantage : « pousser vers l'exterieur rend
`dot(dj,n)` positif, donc le plafond retombe a zero de lui-meme ».

**AU POINT QUI PORTE LE VERDICT PUBLIE DE SPEC 34, IL VAUT DEJA ZERO — ET EN DESSOUS.** Triplet lu
dans la MEME expression, sur le MEME echantillon, a la MEME frame (7e passe, celle qui ne corrige
pas), tag `run` :

    chaine   demande NON ecretee   plafond -dn    applique   deplacement du joint / auteur
    chestL       280,1669 u        **-58,0360**   0,0000 u   |dj| 249,54 u = 58,04 N + 242,70 T
    chestR       278,9003 u        **-32,0811**   0,0000 u   |dj| 139,13 u = 32,08 N + 135,36 T

`radd` egale `addw` egale `skinadd` AU CHIFFRE : ce n'est pas un point voisin, c'est LE point du
verdict. Le plafond y est NEGATIF, donc `v > bv` est faux (`bv` part de 0.0) : l'echantillon n'est
jamais elu `bq` et **le moteur n'applique AUCUNE correction dessus**. Ce n'est pas un etranglement
partiel, c'est une inhibition totale.

**LE MECANISME, ET IL EST GEOMETRIQUE.** 97,3 % du deplacement qui produit la penetration est
TANGENTIEL a la surface. Le plafond ne borne que la composante NORMALE, et celle-ci pointe vers le
DEHORS (`dn > 0`) : la regle « tu ne peux pas pousser plus dehors que la pose d'auteur » se declenche
alors que la PEAU est enfoncee de 6,84 cm. Le sein a pivote LE LONG du torse ; le joint est passe
devant sa pose d'auteur en normale tout en emmenant l'echantillon de peau, distant de ~700 u, dans
le corps. La grandeur qui gouverne n'etait pas mesuree sur le bon axe.

**ET LE PLAFOND EST REDONDANT, PAS SEULEMENT MAL PROJETE.** `add = min(0,sa) - sd` retranche DEJA
la profondeur de l'AUTEUR : c'est deja « la part de la physique », et c'est la definition meme que
[NOTE-150] donne a la colonne. `-dot(dj,n)` est donc un SECOND garde-fou pose sur la meme intention.

**CE QUI REMPLACE, ET POURQUOI CA GARDE LA PROPRIETE QUI COMPTE.** Le plafond devient `|dj|` — le
MODULE du meme ecart. Il tient le meme role (rattacher la correction a la pose d'auteur, ce qui
etait la raison d'etre du plafond) et il garde l'inertie AU BIT au repos : `dj = 0` implique budget
0, donc SPEC 2 et SPEC 9 restent tenues PAR ALGEBRE et pas par reglage. Ce qu'il perd, c'est
l'auto-limitation par signe ; ce qu'il gagne, c'est de ne plus etre aveugle a la direction
([[feedback_radius_blind_to_direction]]). Le cout se chiffre dans le rapport du cycle : `tipvar`,
SPEC 22 etage 6, `ROOM-STRETCH` et `ROOM-IDLE` sont publies avant/apres.

## MIGRATION DU 2026-08-22 (cycle 109) — 17 blocs sortis pour tenir sous le plafond CLEAN

Le canal de preset (`pk <Cle> <valeur>` lu dans le fichier livre) coute 15 lignes au moteur, et
la gate CLEAN en plafonne 4800. Conformement a la convention de ce fichier, les lignes se
trouvent en deplacant des blocs de COMMENTAIRE, VERBATIM, jamais en refactorisant du code : un
deplacement d'expression flottante ferait bouger la course et detruirait le controle de
bit-identite qui est justement la preuve que ce cycle apporte.

## NOTE-484  (moteur, aux alentours de la ligne 490)

```
;; L'APPROCHE MINIMALE MESUREE AVEC L'INJECTION ARMEE, meme frame et memes points que sans elle :
;; controle APPAIRE, donc l'ecart des deux colonnes n'est imputable qu'a l'injection.
```

## NOTE-485  (moteur, aux alentours de la ligne 507)

```
;; combien d'echantillons ont ete VRAIMENT testes : un zero avec un compteur de tests a zero veut
;; dire « je n'ai pas regarde », pas « rien ne penetre ». Les deux se distinguent, toujours.
```

## NOTE-486  (moteur, aux alentours de la ligne 531)

```
;; etat de contrainte de la frame precedente, par (lien, volume), pour compter les bascules.
;; 1 bit par volume, un mot par lien : PHYS-COLS <= 96 tient sur trois mots de 32 bits.
```

## NOTE-487  (moteur, aux alentours de la ligne 536)

```
;; CONTROLE POSITIF de l'auto-collision : arme, l'exclusion chaine<->ses propres volumes est levee.
;; Le compteur `selfcol` doit alors monter — sinon il ne mesure rien.
```

## NOTE-488  (moteur, aux alentours de la ligne 539)

```
;; ARME, LA CONTRAINTE DE COTE EST LEVEE et son compteur doit MONTER. Un compteur tombe a zero
;; est soit une correction, soit un predicat devenu inevaluable — le piege de `(= l 0)`.
```

## NOTE-489  (moteur, aux alentours de la ligne 544)

```
;; [NOTE-53] CONTROLE k=4 — 1 = LE MUR DE COLLISION EST DESARME (`feff` -> PHYS-VOL-FREE), sur la
;; fenetre d'orientation seule. C'est le suspect que le cycle 13 a dimensionne sans le desarmer.
```

## NOTE-490  (moteur, aux alentours de la ligne 555)

```
;; deltas de propagation aux descendants non simules (les verres de lunettes pendent sous
;; gogglesMid : si on bouge le milieu sans eux, ils se decrochent).
```

## NOTE-491  (moteur, aux alentours de la ligne 709)

```
                      ;; [NOTE-126] la part de masse de peau de CHAQUE maillon. 0 = non declaree,
                      ;; et le COM pondere n'est alors pas publie du tout, jamais publie a zero.
```

## NOTE-492  (moteur, aux alentours de la ligne 895)

```
                    ;; PREUVE D'EXECUTION (regle 0) : ce que le moteur a REELLEMENT resolu, pas ce
                    ;; que le fichier promet. Le validateur et la salle s'ancrent sur cette ligne.
```

## NOTE-493  (moteur, aux alentours de la ligne 1120)

```
                      ;; PLAFOND DUR, ET IL DOIT LE RESTER : voir la note d'IDEMPOTENCE au-dessus
                      ;; de `phys-softmin`. Ce bloc tourne onze fois par frame.
```

## NOTE-494  (moteur, aux alentours de la ligne 1153)

```
               ;; LONGUEUR INVARIANTE : projection sur la sphere de rayon `want` centree sur
               ;; l'attache.
```

## NOTE-495  (moteur, aux alentours de la ligne 1603)

```
                            ;; une correction issue d'un volume PROPRE a la chaine : elle ne peut
                            ;; arriver que sous controle positif, et c'est ce compteur qui le dit.
```

## NOTE-496  (moteur, aux alentours de la ligne 1661)

```
            ;; retour aux coordonnees du JOINT : le solveur, la contrainte de longueur et l'ecriture
            ;; dans le squelette raisonnent tous sur le joint, jamais sur le centre du volume.
```

## NOTE-497  (moteur, aux alentours de la ligne 1714)

```
                                  ;; `dd * s^2` = ce que le pas retire REELLEMENT. Le rapport
                                  ;; `removed/sumdepth` EST le rendement geometrique moyen.
```

## NOTE-498  (moteur, aux alentours de la ligne 1743)

```
              ;; --- (b) LA LONGUEUR, et c'est la DERNIERE operation de la boucle, donc du
              ;; --- solveur : `ROOM-STRETCH` reste exact par construction.
```

## NOTE-499  (moteur, aux alentours de la ligne 1848)

```
    ;; [NOTE-293] LA FENETRE DE LECTURE. lo=0 / hi=-1 (les valeurs par defaut, jamais modifiees
    ;; hors de `phys-medial-scan`) rendent EXACTEMENT [0, nbsurf) : la population de CORPS.
```

## NOTE-500  (moteur, aux alentours de la ligne 1880)

```
                          ;; insertion triee : le K-voisinage reste ordonne par distance, donc le
                          ;; dernier porte toujours le rayon du noyau.
```

## NOTE-501  (moteur, les trois `define-extern` du preset)

```
LE PRESET EST UNE ENTREE, PAS UNE DESCRIPTION. Owner, 2026-08-22 : « tu pourrais faire en sorte
que ce soit des boutons qu'on tourne justement, regarde le preset de Maia, les memes proprietes
des presets ont des valeurs differentes... c'est un peu le but d'un preset. »

Sa premisse se verifie sur le document : les deux presets de la section 38 partagent 74 cles
(71 ecrites avec `=`, 3 avec `≈` ou `>=`) et 53 portent des valeurs differentes (51 parmi les 71).
Un document qui donne les MEMES cles avec des valeurs DIFFERENTES pour deux personnages n'ecrit
pas des observations : il ecrit des ENTREES.

Les trois prises ci-dessous rendent donc chaque cle LISIBLE depuis le fichier livre :
  pc-physics-chain-preset-mi     (chaine, id de cle) -> milli, ou -1 si la cle n'est pas au fichier
  pc-physics-chain-preset-count  (chaine)            -> nombre de cles `pk` que le fichier porte
  pc-physics-chain-preset-absent (chaine)            -> celles que CE moteur ne lit pas : CANAL ABSENT

-1 et pas 0 pour l'absence : `AdditionalStandingSag = 0.00` est une valeur legitime du preset, donc
un zero ne peut jamais vouloir dire « absente ». Le moteur remplace une cle absente par l'element
NEUTRE (1.0 pour une echelle, 0.0 pour une amplitude) et le compte : un canal manquant apparait
dans la trace au lieu de restaurer en silence une ancienne constante.

La table des cles CABLEES vit dans `kPhysPresetKeys` (kmachine.cpp), une seule liste : une cle
absente de cette liste n'a pas de canal, et c'est exactement ce que `preset-absent` compte.
```

## NOTE-502  (moteur, `*phys-pset*`)

```
LES VALEURS DU PRESET, PAR CHAINE, LUES DANS LE FICHIER LIVRE.

Rangement `(* sc PHYS-PSET-N) + id`. PAR CHAINE et non global : la section 32 (Left/Right
Independence) demande 2 a 5 % d'ecart entre les deux seins, donc la granularite du preset est la
chaine, pas le modele.

CE QUE CE MAGASIN SUPPRIME, ET C'EST SA RAISON D'ETRE. Six valeurs de FORME etaient ECRITES EN DUR
dans le tenseur de deformation (sections 10 et 11 : Supine{Projection,Width,Height}Scale,
Hanging{Length,Width,Thickness}Scale). L'instrument relisait donc la constante qu'il etait cense
verifier — 13 entrees du registre etaient dans ce cas et comptaient comme mesurees. Elles ne le
sont plus : la valeur vient du fichier, l'instrument mesure ce que le fichier a demande.

ET CA DONNE LE CONTROLE POSITIF DE NIVEAU SYSTEME QUE CE DOSSIER N'A JAMAIS EU : poser le preset de
MAIA sur la chaine de KEIRA doit produire un comportement MESURABLEMENT different, dans le sens que
ses ecarts prescrivent. Un moteur qui consomme vraiment le preset le montre ; un moteur qui fait
semblant rend la meme chose. Le perimetre ne bouge pas pour autant : ses chiffres sont un VECTEUR
DE TEST sur la chaine de Keira, on ne livre pas sa physique et on ne touche pas a son personnage.
```


## [NOTE-501] `PHYSSTGQ` — LE SEPTUPLET EN INSTANTANE, AU POINT DE PARCAGE

```
[NOTE-501] INSTANTANE, ET C'EST LA DIFFERENCE QUI COMPTE. 72-78 et 79-85 sont des LATCHES sur un argmax : ils repondent DANS une frame choisie pour son extremum, jamais dans une frame de REPOS. Le cycle 114b a etabli que la chaine se gare a un point qui depend du CHEMIN (sigma30 nul sur 324 series, decalage jamais nul sur 324) et que la mesure manquante est le septuplet AU POINT DE PARCAGE. Cette tranche-ci n'a donc ni cle ni reset : elle porte toujours la DERNIERE frame ecrite, et c'est la salle qui choisit QUAND la lire — a la fermeture de la fenetre PH-AXC, la ou la chaine est immobile au bit pres.
```


## NOTE-503 — cycle 115 : `PHYS-DYN-K` ETAIT UN RAPPORT DE DEUX CLES, RECOPIE. UN BALAYAGE PAR VALEUR NE POUVAIT PAS LE VOIR.

Le cycle 114 a inverse la charge de la preuve sur les constantes du moteur : tout litteral egal a une
valeur du preset sort en `NON TRIE` tant qu'il n'est pas JUSTIFIE. Ce balayage a un angle mort qu'il
declarait lui-meme, et `PHYS-DYN-K` etait dedans :

    PHYS-DYN-K = 0.43  =  NormalDynamicStretch / NormalMaxCOMDisplacement  =  0.15 / 0.35

**Une constante ajustee sur un RAPPORT de deux cles n'egale AUCUNE valeur du preset.** Aucun
balayage par valeur ne peut la trouver, quelle que soit sa completude. Elle ne se trouve qu'a la
lecture, et elle ne se retire qu'en cablant les deux cles.

CE QUI A ETE FAIT. `NormalMaxCOMDisplacement` etait deja cablee (indice 18) ; `NormalDynamicStretch`
ne l'etait pas et entre en indice 26 (`kPhysPresetKeys`, `kmachine.cpp`), `PHYS-PSET-N` passe de 26
a 27. Le gain se calcule a l'execution, par chaine, avec sa garde de division par zero — le repli
`0.0` DESARME le canal, qui est le neutre correct pour un etirement.

**LE PIEGE, ET IL AURAIT RENDU LE GAIN 6,7 FOIS TROP GRAND.** La regle d'element neutre de
`pc-physics-chain-preset-mi` rendait `1.0` pour tout indice `>= 22` et `0.0` sinon. Un indice 26
neuf tombait donc dans la branche `1.0`, ce qui donne un gain de `1.0 / 0.35 = 2.857` au lieu de
`0.4286`. La clause est bornee a `(and (>= pki 22) (< pki 26))` dans le meme lot, et la valeur est
republiee a l'execution (`PHYSPSETF ndyn=`) pour que le defaut se voie en une ligne au lieu de
contaminer une course entiere.

**CE RECABLAGE N'EST PAS BIT-IDENTIQUE, ET C'EST DIT AVANT LA COURSE.** `float32(0.43)` vaut
0.4300000072 et `float32(0.15/0.35)` vaut 0.4285714626 : facteur **0.9966778**, soit -0.333 %.
`rdr`, `rx`, `ry`, `rz` sont LINEAIRES en ce gain, donc `dl` aussi. Le signal le plus net n'est pas
un flottant mais un COMPTE ENTIER : `PHYSSHAPE5 dsat=`, le nombre de fenetres ou l'ecretage mord,
qui doit passer de 11 a 10 sur chestL. Un flottant a -0,33 % pourrait etre du bruit d'arrondi ; une
fenetre qui cesse de saturer ne peut pas l'etre.

ET L'INSTRUMENT SUIVAIT LE MEME NOMBRE. `.autoport/physics_room_table.py` portait `_RAD_K = 0.43`,
une TROISIEME copie. `ROOM-RAD elong` valait donc `0.43 x rrm` — un RENOMMAGE DETERMINISTE du
verdict `com=`, incapable de dire quoi que ce soit d'independant. Il lit desormais le gain DANS LA
TRACE qu'il analyse (`PHYSPSETF ndyn=` / `PHYSPSETD ckn=`) et non dans le fichier livre : une course
de CONTROLE tourne sur un vecteur d'essai, et un lecteur qui irait chercher le fichier livre
decrirait une configuration qui n'est pas celle de la trace.


## NOTE-504 — cycle 115 : `PHYS-SEC-K` EST UNE CONSTANTE MOTEUR **SANS CLE**, ET ON NE LUI EN INVENTE PAS UNE

`PHYS-SEC-K = 0.05` est le gain d'excitation du mode secondaire de la 36. Contrairement a
`PHYS-DYN-K`, **ce n'est le rapport d'AUCUNE paire de cles** : la [NOTE-169] decrit un balayage
(2.5 -> 0.05) mene jusqu'a ce que la sortie tombe dans la bande. C'est
`never-fit-a-parameter-to-the-instrument` a l'etat pur, et le cabler ne le corrigerait pas.

**IL Y A UNE COINCIDENCE NUMERIQUE EXACTE, ET ELLE EST NOMMEE ICI POUR QU'ELLE NE SOIT PAS
« DECOUVERTE » COMME UN CABLAGE EVIDENT AU CYCLE SUIVANT** : `SecondaryJiggleAmplitudeHi` vaut
0.05 chez Keira. Ecrire `PHYS-SEC-K := pset[SecondaryJiggleAmplitudeHi]` serait bit-identique sur
Keira et rendrait 0.07 sur Maia — un canal qui AURAIT L'AIR de tirer alors que l'egalite est
fortuite. Les natures ne correspondent pas : `PHYS-SEC-K . dvn` est un gain sur une VARIATION DE
POSITION normalisee par frame, tandis que `SecondaryJiggleAmplitudeHi` est une AMPLITUDE en fraction
d'epaisseur locale. C'est `declared-channel-must-be-proven-by-perturbation`, pris a l'envers.

CE QUI EST DONC ECRIT : la constante se declare `CONSTANTE MOTEUR SANS CLE`. La paire qui DEVRAIT
la gouverner est `SecondaryJiggleAmplitudeLo/Hi` (0.02-0.05, la bande « normal 2-5 % » de la 36), et
le cablage correct n'est pas une affectation mais une NORMALISATION : deriver le gain pour que
l'amplitude de regime etabli du mode secondaire SOIT la cle. Ca demande de mesurer le gain de
l'oscillateur (f=5.2 Hz, zeta=0.65) sur l'excitation `dvn` — **NON ETABLI**, et pas invente.


## NOTE-505 — cycle 115 : `PHYSRESTQ`, PARCE QUE `rgap` N'ETAIT PAS EMIS SUR LA FENETRE DU VERDICT

Le cycle 114c a interdit de toucher au solveur tant que `rgap` (0.0145 B0) et la deviation au point
de parcage (0.0004-0.0010 B0) ne seraient pas reconciliees — « facteur ~24 ». **L'audit rend une
reponse que ni l'un ni l'autre des deux chiffres ne laissait deviner : ils ne vivent pas sur la meme
fenetre, et l'un des deux n'etait meme pas mesure la ou le verdict se prend.**

  1. `rgap` n'est PAS la constante 0.0145 : c'est le **p90 des maxima de fenetre**. Sur 186 fenetres
     par chaine, le max de fenetre a pour mediane **0.0034** (chestL) et **0.0002** (chestR), et la
     moyenne sur les 16 740 frames vaut 0.003805 / 0.002722 B0. Prendre un p90 de maxima pour une
     valeur typique est `classify-population-by-window-maximum`, deja au registre.
  2. `PHYSRESTW` n'a qu'un emetteur (`physroom-emit-window`) et un seul appelant (PH-MEAS), et sa
     cle est (animation, pilotage). **PH-AXC n'a ni l'une ni l'autre.** Le verdict de 2/9 se prend
     sur PH-AXC ; `rgap` n'y etait pas emis. Le « facteur 24 » comparait des maxima releves sous
     animation qui AVANCE a un instantane sous animation GELEE.
  3. `rgap` est **purement angulaire, par identite de code** : `*phys-blen*` est recalculee chaque
     frame depuis la MEME paire d'os que `tw`, donc `|tw - anc| = bl` exactement et
     `rgap = (bl/b0e) . 2 sin(dtheta/2)`. Aucun terme de longueur ne peut y entrer. dtheta va de
     0.003 a 0.634 degre.
  4. Et sa variance est expliquee a **90.9 % / 91.6 % par l'ANIMATION**, a **2.0 % / 1.9 % par le
     PILOTAGE**. Maximum sur `assistant-village2-idle-hut-breath`, une RESPIRATION — donc
     l'animation qui articule le thorax ; minimum (0.0002) sur les poses de soudure TENUES.
     `rgap` mesure la derive angulaire de la POSE D'AUTEUR depuis la frame de capture de `u`, ce
     que la [NOTE-422] decrit deja comme un CHOIX (« elle ne suit pas l'animation ») et dont on
     n'avait jamais publie l'amplitude.

`PHYSRESTQ` publie donc `rgap` et `perr` a la derniere frame de PH-AXC, juste au-dessus de
`PHYSSTGQ`, avec la MEME portee — le `phys-diag-reset!` de `pframe = 1` de cette fenetre.

**CE QU'ELLE TRANCHE, ET LES DEUX FACES SONT ECRITES AVANT LA COURSE.** Si `rgap` y vaut du meme
ordre que `PHYSSTGQ`, la cible du ressort EST la pose d'auteur dans cette pose et l'attribution du
cycle 114c tombe comme artefact de population. Si `rgap` y vaut ~0.013 pendant que `PHYSSTGQ` reste
a 0.0006, alors la these du 114c est REFUTEE : la chaine ne se repose pas sur la cible du ressort,
et comme le septuplet est plat sur ses sept etages, ce serait l'INTEGRATION qui la tient.

**ET LE SOLVEUR N'EST PAS TOUCHE, POUR UNE RAISON CHIFFREE.** Recalculer `u` chaque frame ferait du
ressort une LAISSE vers la pose d'auteur, ce que la [NOTE-113] et `author-pinned-floor-is-a-rectifier`
interdisent. Et l'ecart MAXIMAL de `rgap` (0.019 B0) vaut 22 a 26 fois MOINS que la bande d'apex de
la 22 (0.42-0.50 B0), pendant que `perr` moyen vaut 0.388 B0 — **102 fois `rgap` moyen**. Corriger
`rgap` serait travailler le centieme du defaut.

## NOTE-513 — cycle 118 : docstring de `phys-skin-off-set!`, deplacee VERBATIM

Texte d'origine, mot pour mot, tel qu'il vivait dans `jak-hd-physics.gc` :

    ABLATION, 0 EN LIVRAISON : 1 DESARME la contrainte de peau de SPEC 33/34 ([NOTE-241]).
    C'est SON controle positif — desarmee, `skinpen` doit REMONTER au-dessus de `skinrest`, et
    l'ecart entre les deux jambes EST ce que la contrainte tient. Armee, elle ne peut pas tirer un
    sein dehors, donc un ecart dans l'autre sens denoncerait un defaut de la contrainte elle-meme.

## NOTE-514 — cycle 118 : docstring de `phys-skc`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    CE QUE LA CONTRAINTE DE PEAU RETIRE, AGREGE sur toutes les frames depuis la derniere remise a
    zero de diagnostic : un cumul de JAMBE, jamais un maximum de fenetre. GLOBAL A LA COURSE ET PAS
    PAR CHAINE — il ne se publie donc jamais comme une colonne par chaine (regle 7).
    0 = NOMBRE de corrections. 1 = somme de leurs modules (unites de jeu). 2 = la pire d'entre elles.
    LECTURE QUAND LA CONTRAINTE NE MORD PAS : les trois a zero.

AJOUT DU CYCLE 118 : les cases 6 et 7 portent le meme couple pour la borne de §21 posee sur la
valeur LIVREE — 6 = NOMBRE de corrections `*phys-e21-n*`, 7 = somme des modules retranches en
unites de `B0` (`*phys-e21-d*`). Memes NATURE et REPERE que 4/5 (`phys-cap-e22!`), meme cycle de
vie (cumul de JAMBE remis a zero par le diagnostic). LECTURE QUAND LA BORNE NE MORD PAS : les deux
a zero — et desarmee (`*phys-e21-off*` = 1) elles y sont PAR CONSTRUCTION, ce qui est le controle
negatif de la case elle-meme.

## NOTE-515 — cycle 118 : docstring de `phys-rr-off-set!`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    1 = la borne §22 du canal RADIAL est desarmee (`rcap` -> +inf), sur la fenetre d'orientation
    seule. La salle l'arme sur la passe k=5 du balayage et le REND A 0 en sortant. Arme, le canal
    radial doit REMONTER vers son brut `rrr` (jusqu'a 0.6843 B0 mesures contre 0.3900 bornes) : si
    le pole medial de sa §12 remonte avec lui, l'ecretage est le mecanisme ; s'il ne bouge pas, la
    borne est exoneree et la cause est ailleurs dans la confiscation de longueur.

## NOTE-516 — cycle 118 : docstring de `phys-cone-off-set!`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    1 = le rayon redevient interpole sur le parametre de PROJECTION, c'est-a-dire le predicat faux
    d'avant. La penetration residuelle mesuree contre les 24 capsules — toutes coniques — doit alors
    REMONTER : desarme, le moteur teste le solide que la donnee designe ; arme, il teste un ensemble
    plus PETIT, donc il laisse entrer ce qu'il devrait refuser.

## NOTE-517 — cycle 118 : docstring de `phys-prio-meas-set!`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    1 = la passe de selection tourne POUR COMPTER, sans jamais ecarter un volume. C'est ce qui rend
    `ROOM-VOLPRIO` non vide pendant que la priorite reste desarmee. Le controle de cette mesure est
    son propre desarmement : a 0, la passe ne tourne pas et les trois compteurs doivent retomber a
    zero exactement — un compteur qui resterait non nul mesurerait autre chose que cette passe.

## NOTE-518 — cycle 118 : SPEC 21, LA SATURATION EST POSEE SUR LA COMBINAISON **LIVREE**

§21 (l.290-293), mot pour mot :

    Linear and rotational displacement contributions shall combine vectorially. **They shall not be
    added without saturation.**
        D_combined = D_max . tanh( |D_linear + D_angular| / D_max )

**CE QUE LE MOTEUR FAISAIT AVANT CE CYCLE.** Les trois termes de l'excursion d'apex — `tp`
(translation du joint), `rp` (rotation de visee), `dp` (tenseur de deformation) — etaient ADDITIONNES
sans qu'aucune saturation ne porte sur leur somme. Le mur de force `mu` (`:2984-2990`) multiplie une
FORCE et ne voit ni la rotation ni la combinaison ; `phys-cap-e22!` borne `|p - cible|` du JOINT,
c'est-a-dire `tp` seul (son maximum vaut 0.5008 B0 pour un plafond de 0.5000, cycle 58). La grandeur
que la section NOMME — `s = D_linear + D_angular = e - dp` — n'etait bornee par rien, et
`ROOM-SPEC21` la publiait depuis le cycle 86 a `max 0.5622 / 0.5836 B0` pour un plafond dur de 0.50.

**CE QUE CE BLOC FAIT.** Une fois la matrice d'os LIVREE ecrite (rotation, tenseur, translation), il
lit `e` par `phys-pt-exc!` contre la pose d'AUTEUR de la meme frame, retranche `dp` releve dix lignes
plus haut, et sature la somme restante :

    g = phys-softmin(|s|, cap) / |s|        cap = (cle 16 + cle 17) * B0 = 0.50 B0
    bm.v3 -= (1 - g) * s

`phys-softmin` a son genou a `0.84 * cap`, soit **exactement les 0.42 B0** que la §22 appelle
« normal », et son asymptote exactement au plafond dur de 0.50 : les deux bornes de la spec sont la
FORME de l'operateur, aucune n'est un reglage. En dessous du genou c'est l'IDENTITE STRICTE, donc a
la pose d'auteur (`|s| = 0`) la borne est **INERTE PAR ALGEBRE**, pas par reglage — meme propriete
que la borne de collision du cycle 61.

**POURQUOI UNE TRANSLATION, ET PAS UNE ROTATION.** Le cycle 87 a implemente cette meme borne PAR
ROTATION du point de chair : elle a AGGRAVE §22 (apex moyen 0.7413 -> 0.8382 et 0.7660 -> 0.8651),
et le cycle 88 a mesure pourquoi — la part RADIALE de l'excursion vaut 0.9114 / 0.8465 en mediane,
alors qu'une rotation autour du joint ne deplace le point que TANGENTIELLEMENT. Une translation, elle,
rend exactement la direction `-s` : la forme de l'operateur correspond a la demande. C'est la seule
difference avec le geste refute, et c'est elle qui rend l'algebre de la sortie exacte.

**CE QUE CA COUTE DANS LA DECOMPOSITION, ET C'EST DECLARE, PAS TU.** La correction etant une
translation, elle tombe entierement dans `tp` : `rp` et `dp` sont inchanges, `tp` absorbe
`-(1-g) s`, et l'identite `e = tp + rp + dp` referme comme avant. La valeur ECRITE du joint cesse
donc d'etre egale a `*phys-px*` — c'est le sens meme de « la borne porte sur la valeur LIVREE », et
et c'est ce qui la rend attribuable.

**ET CE QUE J'AI CRU GARANTIR ET QUI EST FAUX, MESURE DANS LE MEME CYCLE.** J'ai ecrit ici que la
borne, n'ecrivant pas `*phys-px*`, n'avait « aucune retro-action de frame a frame ». **C'est faux.**
`phys-snapshot-sim!` (`:1376`, [NOTE-214]) releve en FIN DE FRAME, **sur le squelette ECRIT**, la
position de tout volume porte par un joint simule, et c'est ce que la frame SUIVANTE lit comme
obstacle. Deplacer la valeur livree deplace donc les volumes de collision, donc la trajectoire.
Mesure : `PHYSRESTW` — qui ne lit que `*phys-px*` — differe sur **346 cellules sur 372** entre la
course armee et la course archivee, les 8 premieres etant identiques et la divergence s'ouvrant a
(a=0, d=4). La consequence pratique : l'algebre de la sortie reste une bonne APPROXIMATION (ecart
mesure de 0,006 a 0,03 B0 sur `|s| max`), jamais une prediction exacte, et toute lecture qui s'y
appuie doit le dire.

**ET UNE SECONDE CORRECTION, PAR MESURE AUSSI : LA BORNE PORTE SUR L'ORGANE, PAS SUR LE MAILLON.**
La premiere implementation du cycle 118 saturait la contribution de CHAQUE maillon. Or la grandeur
que §21 et §22 nomment est le deplacement de l'ORGANE, c'est-a-dire la somme PONDEREE `Σ aw_l e_l`
que `PHYSAPEX` publie — et la somme des poids d'apex vaut **0,9402 / 0,9549**, pas 1. Une borne par
maillon a 0,4998 B0 rendait donc un plafond PUBLIE de 0,4699 / 0,4773 B0 : plus serre que ce que la
spec ecrit, et il mordait sur 76 a 87 % des fenetres au lieu de 52 a 77 %. Mesure de la premiere
implementation : `|s| max` 0,4688 / 0,4702 la ou l'algebre de l'organe annoncait 0,4972 / 0,4987 —
c'est cet ecart qui a revele le defaut. La borne porte desormais sur la somme ponderee, et la
correction est repartie sur les maillons par `dl = (1-g)/Σaw` : une TRANSLATION RIGIDE de l'organe
dont la somme ponderee vaut exactement `-(1-g) s`.

## NOTE-519 — cycle 118 : docstring de `phys-link-dev-ax`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    LA MEME DEVIATION QUE `phys-link-dev`, DANS LE TRIEDRE DE L'ANCRE (voir `*phys-lda*`).
    axis 0/1/2 = vertical / avant-arriere / lateral — l'ordre de SPEC 24, pas celui des lignes de la
    matrice. REPERE : le triedre de l'ANCRE, que SPEC 7 impose ; le repere monde ne peut pas separer
    les trois axes de SPEC 24. Instantanee, nulle a la pose du modele. Rend 0.0 sur une chaine que le
    solveur n'a pas classee — l'outil de lecture le declare, il ne le comble pas.

## NOTE-520 — cycle 118 : docstring de `phys-axsel`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    LA CLASSIFICATION DU TRIEDRE, TELLE QUE LE SOLVEUR L'A FAITE — pour que la salle la publie et
    qu'elle soit RELISIBLE dans la trace au lieu d'etre supposee.
    which 0 = classee (0/1), 1/2/3 = index de ligne vertical / avant-arriere / lateral,
    4 = raideur par axe ARMEE (0/1) — voir la note de `*phys-axan*` : classee et armee ne sont pas
    la meme chose, et c'est precisement l'ecart entre les deux qu'il faut pouvoir lire.

## NOTE-521 — cycle 118 : docstring de `phys-osc-k2`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    Raideur par pas telle que la recurrence symplectique rende EXACTEMENT l'amortissement `z` et
    la pulsation dont `wh` = omega * pas. Retention a lui associer : `(phys-decay (* 2.0 z wh))`.
    `4 r sin^2(theta/2)` et JAMAIS `1 - cos theta` : egaux en algebre, mais `1 - cos` perd ses
    chiffres significatifs quand theta est petit, et theta vaut 0.06 sur le mode principal.
    Somme de termes positifs, donc k2 > 0 toujours : ne peut pas destabiliser la boucle.

## NOTE-522 — cycle 118 : docstring de `phys-vol-yield`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    La bande de SPEC 10 est la compression de la chair CONTRE SON PROPRE BUSTE — pas une licence de
    traverser un bras, une main ou les lunettes (regle 6). Critere STRUCTUREL, tire du rig et jamais
    d'une liste a la main (regle 4) : le volume doit porter l'ANCRE de la chaine comme extremite.
    Ancre `chest` => `chest->main`, `neck->chest`, `L|Rshoulder->chest`, RIEN d'autre : les bras,
    `head->neck` et `sphere:gogglesMid` gardent le mur dur. Meme plancher pour la mesure. NOTE-55.

## NOTE-523 — cycle 118 : docstring de `phys-axis-dir`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    Direction unitaire allant du point le plus proche de l'AXE du volume vers `pt`, que `pt` soit
    dedans ou dehors. `phys-collide-depth` ne peut pas servir a ca : elle ecrit une normale
    arbitraire (0,1,0) des que le point est hors du volume, ce qui est correct pour une poussee et
    faux pour un COTE. Rend #f quand le point est sur l'axe, ou aucun cote n'existe.

## NOTE-524 — cycle 118 : docstring de `phys-prox-off-set!`, deplacee VERBATIM

Texte d'origine, mot pour mot :

    ABLATION DE MESURE, 0 EN LIVRAISON : 1 retire les SPHERES PROXIMALES de la liste des obstacles.
    Le cycle 35 a mesure qu'elles ne couvrent aucun sommet que la sphere distale ne couvre deja ;
    cet interrupteur repond a la question a l'execution, sans toucher aux rayons — qui sont une
    SURCHARGE DE L'OWNER que la gate TUNING protege.

## [NOTE-506] `phys-cap-e22!` — docstring integrale, deplacee VERBATIM depuis le source

Deplacee au cycle 119b pour rendre 8 lignes au plafond de 4800 du moteur, sans toucher une
instruction. Methode etablie depuis le cycle 51 et reemployee au cycle 118 (11 docstrings, 17
lignes). Le texte ci-dessous est celui qui etait dans `jak-hd-physics.gc`, mot pour mot :

    SPEC 22, ALTERNEE AVEC LA PEAU (cycle 104) : elle n'est PLUS le dernier ecrivain de
    `*phys-px*` — voir NOTE-470. NATURE : une LONGUEUR rapportee a `B0` (SPEC 6, la CHAIR).
    REPERE : le monde, contre la pose d'AUTEUR de la MEME frame rebasee sur l'ecart du parent —
    exactement la cible du filet amont, pas une laisse vers la pose. LECTURE QUAND LE DEFAUT EST
    ABSENT : aucune correction, `*phys-e22-n*` = 0 (a la pose d'auteur l'ecart vaut 0, donc sous le
    genou de 0.42 B0 : la borne est INERTE PAR ALGEBRE, pas par reglage).
    ROTATION EXACTE AUTOUR DE L'ATTACHE, donc `|p - b|` invariant AU BIT : une contraction radiale
    vers la cible — la forme du filet amont — casserait la longueur, et aucune passe ne pourrait
    plus la reparer. Justification complete : [NOTE-447] de jak-hd-physics-NOTES.md.

## [NOTE-507] `phys-shape` — docstring integrale, deplacee VERBATIM depuis le source

Deplacee au cycle 120 pour rendre 6 lignes au plafond de 4800 du moteur, sans toucher une
instruction. Meme methode qu'aux cycles 51, 118 et 119b. Le texte ci-dessous est celui qui etait
dans `jak-hd-physics.gc`, mot pour mot :

    SPEC 8/10-13/29/36 — L'ETAT DE FORME ET DE TORSION, LU SUR LE MECANISME ARME.
    NATURE : `which` 0/1/2 = les trois ECHELLES appliquees, sans unite (1.0 = pose d'auteur) ; 3 =
    leur determinant ; 8 = l'interrupteur ; 9/10/11 la gravite unitaire ; 15/16/17 en repere ancre.
    REPERE : le triedre de sa SPEC 7 — mais +X est le lateral SORTANT et **+Z pointe vers
    l'ARRIERE**, PAS vers l'avant comme sa §7 l.130 et cette ligne l'ecrivaient : `gz > 0` =
    SUPINE. Mesure et consequences : [NOTE-408]. LECTURE HORS DEFAUT : 1/1/1.
    Justification complete : [NOTE-296] de jak-hd-physics-NOTES.md.

## NOTE-508 — cycle 120 : LE CANAL DE FORME ETAIT SANS MEMOIRE, ET C'EST POUR CA QUE LE PIC DE §11 N'EXISTAIT PAS

**LE FAIT DE STRUCTURE.** `sx0/sy0/sz0` sont un melange CONVEXE des six poids de direction de
gravite (`wdn/wup/wbk/wfw/wlt/wne`), evalue a la frame, **sans aucun etat**. Une fonction sans
memoire ne peut pas depasser sa propre valeur d'equilibre : quel que soit le geste, l'echelle
saute a sa cible et s'y tient. Le seul terme dynamique du canal etait le mode secondaire de §36
(`smc`), borne a `SecondaryJiggleHardMax` = 0.07 et EXCITE PAR LA VITESSE DE LA POINTE, pas par le
changement d'orientation : la trace du cycle 119b le mesure a **1.0 % / 1.9 %** du depassement que
§11 demande sur la cellule prone, et — le tell — a **82.6 % / 52.9 % sur la cellule DEBOUT**, ou
§11 ne demande rien. Un transitoire qui est cinquante fois plus fort la ou la section n'en veut pas
n'est pas le transitoire de la section.

**LA LOI QUE LE DOCUMENT ECRIT, ET IL L'ECRIT DEUX FOIS.** `HangingTransientLengthMax` n'est pas un
reglage independant :

    HangingTransientLengthMax  =  1 + (HangingLengthScale - 1) x (1 + FirstBounceRatio)
    KEIRA  1 + 0.23 x 1.31 = 1.3013  contre 1.30 ecrit (l.481)  -> +0.10 %
    MAIA   1 + 0.33 x 1.33 = 1.4389  contre 1.45 ecrit (l.953)  -> -0.76 %, et DANS la plage
                                     « +40 to +45% » que sa propre prose ecrit (l.690)

Les trois cles sont du document (`FirstBounceRatio` l.467 / l.939). RESERVE : exact sur Keira,
dans la bande sur Maia — donc ce n'est PAS une `P-IDENTITE` au sens du cycle 119, qui exige
l'exactitude sur les deux presets. Elle tranche neanmoins la lecture que le cycle 119b avait
remontee sans la fermer : un plafond arbitraire ne tomberait pas a 0.10 % du depassement de
second ordre qu'imposent deux autres cles de la meme page. **Le pic doit EXISTER.**

**LE LOT.** Un second ordre sur les trois echelles, `phys-sdyn`, exactement la recurrence
symplectique de §29 et §36 (`phys-osc-k2` / `phys-decay`), avec omega = 2.pi.raideur/sqrt(masse)
et zeta = `*phys-damp*`/(2.omega.dt) — c'est-a-dire `GlobalFrequencyVertical` et
`GlobalDampingRatio`, tous deux LUS DANS LE FICHIER LIVRE. `HangingTransientLengthMax` n'est
**pas** donne au solveur : le pic reste EMERGENT, sinon la mesure serait un miroir
(`mirror-is-the-couple-not-the-location`).

**POURQUOI C'EST INERTE AU REPOS, PAR ALGEBRE ET PAS PAR REGLAGE.** A la pose debout d'auteur la
cible vaut exactement (1,1,1) — c'est la lecture du melange convexe quand `wdn` porte tout le
poids — et l'etat est INITIALISE a (1,1,1) au meme point que `*phys-dfs*`. L'etat est donc au
POINT FIXE des la premiere frame : vitesse nulle, correction nulle. §2 (« Additional Procedural
Sag = 0% ») et §9 (« restored exactly ») ne peuvent pas etre violees par ce lot tant que
l'orientation ne bouge pas.

**L'ORDRE DES TROIS OPERATEURS COMPTE, ET IL EST CELUI-CI :** (1) la cible de gravite, (2) le
second ordre, (3) la conservation de volume `cvn`, (4) le mode secondaire de §36. `cvn` est
recalcule sur les echelles DYNAMIQUES et non sur la cible : sinon le determinant ne serait
normalise qu'a l'equilibre et §8 (« 98-101 %, 96-102 % en transitoire ») sortirait de sa bande
pendant l'etablissement, c'est-a-dire exactement pendant le transitoire que le lot produit.

**COUT DECLARE D'AVANCE** : le tenseur porte 37-41 % de l'exces d'apex de §22
(`apex-excess-lives-in-the-deformation-tensor`). Un depassement de +31 % du PAS d'echelle pendant
l'etablissement fait donc monter `comex` et `meshpen` en transitoire. C'est ecrit dans
`.autoport/c120-predictions.txt` AVANT la course, avec son falsificateur.

## [NOTE-509] `phys-surf-sd` — docstring integrale, deplacee VERBATIM depuis le source

Deplacee au cycle 120, meme methode que [NOTE-507] : 4 lignes rendues au plafond de 4800, aucune
instruction touchee. Texte d'origine, mot pour mot :

    (SPEC 18) DISTANCE SIGNEE du point `p` a la VRAIE SURFACE SKINNEE. Positive = dehors.
    NATURE : une distance, unites de jeu. REPERE : le monde, frame courante. LECTURE HORS DEFAUT :
    positive. La sentinelle 1000000.0 = aucun echantillon a portee, ce qui n'est PAS zero.
    La FENETRE lue est [*phys-sd-lo*, *phys-sd-hi*), 0/-1 par defaut = la population de CORPS.
    Justification complete : [NOTE-299] de jak-hd-physics-NOTES.md.

## NOTE-510  (cycle 121 — SIX BORNES ESSAYEES, SIX MESUREES, ZERO LIVREE ; ET L'EXPLICATION QUE J'EN DONNAIS EST REFUTEE PAR [NOTE-521], MEME CYCLE)

**RIEN DE CE CYCLE N'EST DANS LE MOTEUR.** `phys-skin-chain` est exactement celle du cycle 120.
Ce qui est acquis est un REGISTRE D'ELIMINATION, et il vaut plus qu'un lot : il ferme une famille
entiere de correctifs et il nomme le mecanisme qui la ferme.

**LE DEFAUT DE DEPART, REMESURE ET NON SUPPOSE.** `PHYSSKLV5 tag=run`, cycle 120, au point qui
porte le verdict publie de SPEC 33/34 — meme expression, meme echantillon, meme frame (7e passe) :

    chaine   demande `radd`   plafond `-dn`    applique     pp        ln
    chestL     285,2682 u     **-64,5091**     0,0000 u    0,9975   1040,1988 u
    chestR     268,0815 u     **  0,0187**     0,0000 u    0,7570   1038,7474 u

Le plafond accorde 0,019 u pour une demande de 268 u : inhibition TOTALE au point du verdict.
C'est [NOTE-483] (cycle 106) retrouvee telle quelle apres son retrait.

**LES SIX BORNES, LEUR PRIX, ET LA COURSE QUI LE MESURE.** Ligne de base = cycle 120 :
`skinpen` 0,0696 / 0,0887 m · `skinadd` 0,0696 / 0,0654 m · `ROOM-IDLE` 0,0001 m ·
DISCRIMINANT 46,9 % / 34,0 % · 8 frames en depassement · 23 534 corrections pour 101,5 m cumules
et un residu de 7e passe de 0,0277 m.

    borne                          skinadd L/R      IDLE      DISCR L/R     verdict
    A  `|dj|` qui se consomme      0,0404 / 0,0592  x710      7,7 / 18,0    REFUTEE (repos, discr)
    B  monotone vers l'auteur      0,0723 / 0,0737  rendu     —             REFUTEE (grandeur
                                                                            HONNETE aggravee des
                                                                            deux cotes : faux vert)
    C  boule de rayon `|dj|`       —                —         —             REFUTEE (le candidat
                                                                            tombe a 312,99/444,16 u
                                                                            pour 279,21/211,57
                                                                            alloues : REJET au point
                                                                            du verdict, skinpen MONTE
                                                                            a 0,0917)
    D  aucune borne + descente     0,0540 / 0,0559  0,0051 m  —             REFUTEE (21 646 frames
                                                                            en depassement, course
                                                                            jamais terminee)
    E  borne = la DEMANDE          0,0510 / 0,0532  0,0405 m  —             REFUTEE (repos x405)
    F  `kr <= 0,1` + descente      0,0505 / 0,0572  0,0405 m  13,8 / 22,9   REFUTEE (repos x405 ET
                                                                            DISCRIMINANT sous 25 %)

**LES QUATRE QUI FONT BAISSER LA GRANDEUR HONNETE (A, D, E, F) FONT TOUTES LA MEME CHOSE, ET LE
TABLEAU DE `tipvar` LE MONTRE SANS INTERPRETATION.** Sur F :

    chestL  tilt  0,0981 -> 0,1724  (+76 %)      pendant que  accel 0,1848 -> 0,1855  (+0,4 %)

La contrainte AJOUTE ~0,07 de mouvement aux stimuli FAIBLES et ~0 aux stimuli FORTS. Ce n'est pas
un muselage : c'est un **PLANCHER D'AGITATION independant du stimulus**, exactement ce que l'owner
appelle « un pudding sur lequel on tape au moindre mouvement ». Le meme plancher se relit au repos
(`ROOM-IDLE` 0,0405 m contre 0,0001).

**ET LE CHIFFRE QUI NOMME LE MECANISME, PARCE QU'IL NE DEMANDE AUCUNE INTERPRETATION :**

    cycle 120 : 23 534 corrections · 101,5 m cumules · residu de 7e passe **0,0277 m**
    F         : 39 127 corrections · 331,1 m cumules · residu de 7e passe **0,0572 m**

**3,3 fois plus de travail pour DEUX FOIS PLUS de residu.** Une projection qui converge fait
l'inverse.

**LA LECTURE QUE J'EN AI TIREE EST REFUTEE, DANS LE MEME CYCLE, PAR SON PROPRE FALSIFICATEUR.**
J'avais ecrit ici : « c'est un CYCLE LIMITE ; les six bornes echouent parce qu'elles bornent la
MAGNITUDE d'un pas dont c'est la DIRECTION qui oscille — `*phys-sdn*` est une moyenne ponderee sur
un K-voisinage dont le rayon s'adapte a la densite locale, donc la normale bascule ». Le
falsificateur etait ecrit AVANT la course (lot H de `.autoport/c121-predictions.txt`) : « si la
part de renversements est < 5 % sur tous les maillons des deux chaines, cette lecture est FAUSSE ».
L'instrument de [NOTE-521] rend **63/1387 (4,5 %) · 8/201 (4,0 %) · 59/1361 (4,3 %) ·
17/2380 (0,7 %)** — les quatre sous le seuil. **LA DIRECTION NE BASCULE PAS, ET LA LECTURE EST
RETIREE.**

**CE QUI RESTE MESURE** : les six bornes echouent ; le plancher d'agitation est independant du
stimulus ; le travail croit sans que le residu baisse. **CE QUI TOMBE** : l'explication.

**LECTURE DE REMPLACEMENT — ETIQUETEE LECTURE, PAS MESURE.** Direction stable + travail sans
convergence + ecart permanent au repos = la contrainte ne resout pas une geometrie, elle
**s'equilibre contre le ressort de rappel**. Elle pousse dans le meme sens a chaque frame, le
rappel vers la pose d'auteur la defait a chaque frame, et le point fixe du bras de fer est un ecart
NON NUL — c'est-a-dire `ROOM-IDLE`. Soutien deja mesure : l'ecart CROIT avec la liberte laissee a
la contrainte (0,0001 m au cycle 120 · 0,0051 m pour D · 0,0405 m pour A, E et F). Sous cette
lecture, `-dot(dj,n)` n'est pas un suppresseur de cycle limite mais un **suppresseur d'OFFSET
D'EQUILIBRE** : il vaut zero quand la physique n'a pas pousse vers l'interieur, donc le bras de fer
ne peut pas s'installer.

**CE QUE CA REND AU CYCLE SUIVANT — LES DEUX FALSIFICATEURS DE LA LECTURE DE REMPLACEMENT, A
EXECUTER AVANT D'Y CROIRE :**
  (a) sur la fenetre de repos, publier la SERIE PAR FRAME de la correction de peau et de l'ecart
      `PHYSIDLE`. Un bras de fer donne DEUX PLATEAUX non nuls ; une rampe ou une oscillation le
      refute — et le registre previent deja que la derniere frame d'une fenetre est sur la rampe
      (`parking-point-is-a-plateau-not-the-last-frame`) ;
  (b) test a UNE variable sur un bouton qui existe deja : diviser `stiffness` par deux doit
      MULTIPLIER l'ecart par ~2 si c'est un equilibre de forces, et le laisser inchange sinon.
Ce qui NE change pas : la famille des bornes de MAGNITUDE reste fermee par la MESURE (six fois),
independamment de l'explication qu'on en donne.

## [NOTE-520] `phys-skin-chain` — docstring integrale, deplacee VERBATIM depuis le source

Deplacee au cycle 121 pour rendre 5 lignes au plafond de 4800 du moteur, sans toucher une
instruction. Meme methode qu'aux cycles 51, 118, 119b et 120. Le texte ci-dessous est celui qui
etait dans `jak-hd-physics.gc`, mot pour mot :

    SPEC 33/34 — LA PEAU N'ENTRE PAS DANS LE CORPS, et c'est la DERNIERE contrainte de position de
    la frame : la correction est une ROTATION autour de l'attache, donc la longueur est invariante
    AU BIT et rien ne s'execute apres elle. NATURE : une profondeur, unites de jeu. REPERE : le
    monde, frame courante. LECTURE HORS DEFAUT : aucune correction (la pose d'auteur la rend nulle).
    Justification complete : [NOTE-298] de jak-hd-physics-NOTES.md.

## NOTE-521 — cycle 121 : LE DIAGNOSTIC DE DIRECTION, PARCE QU'UNE LECTURE N'EST PAS UNE MESURE

[NOTE-510] conclut que les six bornes de deplacement echouent parce qu'elles bornent la MAGNITUDE
d'un pas dont c'est la **DIRECTION** qui oscille. **C'etait une lecture du mecanisme, pas une
mesure**, et elle etait publiee comme telle. Cette note est l'instrument qui la met a l'epreuve.

**CE QUI EST MESURE.** A la premiere passe de correction de chaque appel a `phys-skin-chain`, et
pour chaque (chaine, maillon), le moteur garde la normale `nb` de l'echantillon **qui decide** — la
direction dans laquelle la correction va pousser — et la compare a celle de l'appel precedent au
meme endroit. Deux compteurs par maillon, dans `*phys-nflip*` :

    w=0   nombre d'appels ou l'angle depasse **90 degres** (produit scalaire negatif) : un vrai
          RENVERSEMENT, c'est-a-dire un pas qui repousse dans l'autre sens ;
    w=1   nombre total d'appels compares.

**NATURE** : un COMPTE, sans dimension. **REPERE** : le monde, deux appels consecutifs — et
`phys-skin-chain` est appelee **DEUX fois par frame** (l'alternance avec `phys-cap-e22!` de
[NOTE-470]), donc l'unite de comparaison est l'APPEL, pas la frame. **LECTURE HORS DEFAUT** : `w=0`
nul. **GARDE DE VACUITE** : le premier appel d'une fenetre n'a pas de predecesseur — la normale
memorisee est remise a zero par `phys-diag-reset!` et un vecteur de longueur nulle n'est jamais
compare, donc `w=1` compte les appels QUI PEUVENT rendre un verdict, pas tous les appels.

**INSTRUMENT PUR** : `*phys-sdnp*` et `*phys-nflip*` ne sont lus par aucune expression du solveur.
Le controle est publie avec le lot : toutes les grandeurs de solveur restent identiques au chiffre
publie.

**LE FALSIFICATEUR, ECRIT AVANT LA COURSE** (`.autoport/c121-predictions.txt`, lot H) : si la part
de renversements est **< 5 % sur tous les maillons des deux chaines**, la lecture de [NOTE-510] est
FAUSSE, le cycle limite vient d'ailleurs, et c'est ce resultat-la qu'il faut publier.

## MIGRATION DU 2026-08-25 (cycle 122) — 7 docstrings sorties pour tenir sous le plafond CLEAN

Le lot de ce cycle coute 17 lignes au moteur (budget d'entree par echantillon, test de descente,
deux compteurs et leur accesseur), et la gate CLEAN en plafonne 4800. Conformement a la convention
de ce fichier, les lignes se trouvent en deplacant des blocs de TEXTE, VERBATIM, jamais en
refactorisant du code : un deplacement d'expression flottante ferait bouger la course.

## NOTE-527  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "min DOUX de v et cap A ZONE MORTE : IDENTITE STRICTE sous le genou kn = 0.84 cap, puis l'EXCES
   seul est sature, asymptote exacte a cap. Pente continue au genou (f'(kn) = 1), strictement
   croissante partout. NON IDEMPOTENT AU-DESSUS DU GENOU (en dessous c'est l'identite, donc
   idempotent) : ne jamais l'appeler dans une boucle de contraintes."
```

## NOTE-528  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "Profondeur maximale que cette paire (lien, volume) tolere : sa profondeur d'AUTEUR plus ce que
   la SPEC 22 autorise a l'excursion. NATURE : une profondeur, unites de jeu. REPERE : le monde.
   LECTURE HORS DEFAUT : la profondeur mesuree reste dessous.
   Justification complete : [NOTE-301] de jak-hd-physics-NOTES.md."
```

## NOTE-529  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "DISTANCE AU SOLIDE QUE LA LIGNE DE DONNEES DESIGNE — l'enveloppe convexe des deux spheres,
   minimisee sur [0,1] (jamais projeter puis interpoler le rayon). NATURE : une profondeur signee,
   unites de jeu, positive DEDANS. REPERE : le monde, frame courante. `nrm` rend la normale.
   Justification complete : [NOTE-300] de jak-hd-physics-NOTES.md."
```

## NOTE-530  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "LA CONTRAINTE DE LONGUEUR, DURE, ET LA MEME POUR LES DEUX FORMES DE LIEN : projection sur la
   sphere de rayon `want` = la longueur que LE MODELE donne a cet os. Une egalite, pas un plafond :
   ca tourne, ca ne s'etire pas. `*phys-len-off*` la DESARME (controle, 0 en livraison).
   [NOTE-122] -> jak-hd-physics-NOTES.md"
```

## NOTE-531  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "RELEVE L'ANGLE DE CHAQUE MAILLON A UN ETAGE DU SOLVEUR (voir la note de `*phys-la0*`).
   Rigoureusement le meme calcul que la mesure de fin de frame : direction courante prise depuis
   l'attache SIMULEE, direction du modele prise depuis l'attache ANIMEE. Deux etages mesures
   autrement ne seraient pas comparables, et c'est leur COMPARAISON qui designe le coupable."
```

## NOTE-532  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "SPEC 23 — LE TROISIEME DEGRE DE LIBERTE, LU A L'EXECUTION. Voir la note de `*phys-rr*`.
   NATURE : une DEFORMATION signee, sans unite, pas une amplitude agregee. REPERE : l'axe de l'OS,
   dans le triedre de l'ANCRE (SPEC 7). LECTURE HORS DEFAUT : 0 (aucune deformation radiale).
   Justification complete : [NOTE-297] de jak-hd-physics-NOTES.md."
```

## NOTE-533  (docstring deplacee le 2026-08-25 ; aucune ligne de CODE touchee)

```
  "LES DEUX PROJECTIONS QUE LA DECISION DE NOMMAGE A COMPARE, et la norme du segment inter-seins.
   which 0/1 = les deux projections candidates, 2 = |separation|, 3/4/5 = le VECTEUR lui-meme.
   REPERE : le triedre de l'ANCRE (SPEC 7). NATURE : une longueur signee, en unites de jeu.
   LIGNE DE BASE : 0 quand il n'y a pas de chaine partenaire — et `phys-chain-axis … 5` le dit."
```

## NOTE-525  (moteur, `phys-skin-chain` — LE BUDGET D'ENTREE REMPLACE LE PLAFOND DE [NOTE-291], cycle 122)

**CE QUI EST RETIRE.** `v = min(add, -dot(dj, n))`, ou `dj = o - joint_auteur` etait pris a
l'entree de l'appel et `n` la normale de surface a l'echantillon. [NOTE-483] (cycle 106) avait
deja mesure que ce plafond vaut **-58,0 / -32,1 u AU POINT QUI PORTE LE VERDICT** de SPEC 34,
c'est-a-dire qu'il n'etranglait pas la correction : il l'**INTERDISAIT** (un `v <= 0` ne peut pas
etre elu `bq`, `bv` partant de 0.0). Le cycle 120 le remesure a **-64,5091 u** sur chestL et
**+0,0187 u** sur chestR pour des demandes de 285,27 et 268,08 u — 100,0 % retenus des deux cotes.

**POURQUOI IL EST FAUX, ET C'EST GEOMETRIQUE, PAS UN REGLAGE.** Au point du verdict, 96,6 % /
100,0 % du deplacement du joint par rapport a la pose d'auteur est **TANGENTIEL** a la surface.
Le plafond ne lit que la composante NORMALE, et elle pointe DEHORS : la regle « tu ne peux pas
pousser plus dehors que la pose d'auteur » se declenche alors que la peau est enfoncee de 6,5 a
7 cm. La grandeur qui gouverne n'etait pas mesuree sur le bon axe — et surtout, elle etait
mesuree par une PROJECTION LINEAIRE alors que la profondeur est lue par un champ de nuage de
points qui n'est pas localement lineaire sur 250 u ([[feedback_point_cloud_sdf_not_lipschitz]]).

**CE QUI REMPLACE, ET IL GARDE LES DEUX PROPRIETES QUI COMPTAIENT.** Le budget est desormais lu
**AVEC LE MEME CHAMP QUE LE VERDICT, ET SUR LE MEME ECHANTILLON** :

    bud_q = min(0, sa_q) - sd_q(entree)      ;  v = min( add_q(courant), bud_q )

  - **inerte a la pose d'auteur PAR ALGEBRE** : `sd(entree) = sa` donne `bud = 0`. SPEC 2 et
    SPEC 9 restent tenues par construction, exactement comme avec l'ancien plafond, et pas par
    reglage ;
  - **auto-limitant et SIGNE** : si la physique a rendu l'echantillon PLUS DEHORS que la pose
    d'auteur, `bud < 0` et rien n'est pousse. C'est la propriete que [NOTE-291] appelait
    « il retombe a zero de lui-meme », rendue dans les unites du verdict au lieu d'une
    projection ;
  - **il interdit a la contrainte de courir apres ce qu'elle a elle-meme cree** : le budget est
    fige a l'ENTREE de l'appel. Corriger l'echantillon A fait tourner le maillon et peut enfoncer
    l'echantillon B ; B ne peut alors etre corrigee qu'a hauteur de sa violation D'ENTREE. C'est
    la reponse au symptome mesure au cycle 121 (« 3,3 fois plus de travail pour DEUX FOIS plus de
    residu »).

`dn` reste calcule et **PUBLIE** (cases 16/17 de `*phys-skl*`, ligne `ROOM-SKINLEVER`) : il
devient un DIAGNOSTIC, il ne decide plus rien. Le rapport doit le lire comme tel.

**FALSIFICATEUR, ECRIT AVANT LA COURSE.** Si `ROOM-IDLE` depasse 0,02 m ou si `DISCRIMINANT`
tombe sous 25 % sur une chaine, ce lot est REFUTE et se retire — c'est exactement ce qui a tue
les six bornes du cycle 121, et il n'y a aucune raison de s'en exempter.

## NOTE-526  (moteur, `phys-skin-chain` — LE TEST DE DESCENTE, cycle 122)

`phys-surf-sd` est une moyenne ponderee sur un K-voisinage d'un NUAGE DE POINTS : elle n'est pas
lisse, et une passe peut deplacer le maillon de `0,5 * pp * ln` ~ 9,6 cm d'un coup. Rien ne
garantissait que la profondeur de l'echantillon qui a DECIDE la correction baisse reellement.

Le moteur relit donc la surface **au point candidat**, pour le meme echantillon `bq`, et
n'applique le deplacement que si `sd(candidat) > sd(decideur)`. Sinon la passe est comptee comme
REFUSEE et rien n'est ecrit.

**CE N'EST PAS UN SUPPRESSEUR, ET LA MESURE LE DIT** : `PHYSSKIND` publie `nref/ntot` et le cumul
refuse. Un `nref = 0` voudrait dire que le test ne se declenche jamais, donc qu'il ne mesure rien
— et c'est alors LUI qu'il faut retirer, pas le garder « au cas ou ». Le compteur est remis a
zero par jambe, comme `PHYSSKINC`, donc les deux jambes d'une ablation restent comparables.

**AJOUT DU MEME CYCLE — UN REFUS RETIRE L'ECHANTILLON DE L'ELECTION.** Sans cela, l'argmax
redesigne l'echantillon refuse a l'iteration suivante (rien n'a bouge), et les six passes se
consomment sur un candidat qu'on vient de juger nuisible — la contrainte ne corrigerait alors
RIEN sur ce maillon, pas meme les echantillons suivants. Le refus met donc `bud[bq]` a zero :
`v = min(ad, 0) = 0` ne peut plus etre elu (`bv` part de 0.0), et l'iteration suivante passe au
deuxieme candidat. C'est la difference entre « on ne fait pas ce pas-la » et « on ne fait plus
rien ».

## NOTE-525 bis  (LE BUDGET D'ENTREE EST REFUTE PAR SON PROPRE FALSIFICATEUR — cycle 122, course J1)

Le falsificateur P5 de `.autoport/c122-predictions.txt` etait ecrit AVANT la course : « DISCRIMINANT
ecart >= 25 % sur LES DEUX chaines, sinon REFUTE, le lot se retire ». **Il a tire**, et la mesure
est publiee telle quelle :

    chestL   ecart 13 %   (accel 0,1882 · jerk 0,1855 · leftright 0,1762 · tilt 0,1867 · updown 0,1635)
    chestR   ecart 15 %   (accel 0,1771 · jerk 0,1620 · leftright 0,1641 · tilt 0,1917 · updown 0,1792)

**CE QUE LE LOT ACHETAIT, ET IL FAUT LE DIRE PARCE QUE C'ETAIT REEL** : `ROOM-SKINPEN` 0,0696 ->
**0,0590** et 0,0887 -> **0,0789** (la gate `COLLIDE` passait, et pour la premiere fois LES DEUX
chaines tombaient sous LEUR PROPRE plancher) ; `ROOM-SKINADD`, la grandeur APPARIEE, 0,0696 ->
**0,0502** (-27,9 %) et 0,0654 -> **0,0602** (-7,9 %) ; le controle positif d'ablation tirait
**sur les deux chaines et contre son biais de population** pour la premiere fois (desarmee 0,0709
contre armee 0,0353 ; 0,0627 contre 0,0539). `ROOM-STRETCH` 2,7913 -> 2,2689 %.

**ET VOICI L'ATTRIBUTION, QUI EST NEUVE ET QUI FERME LA DIRECTION.** L'echec de DISCRIMINANT n'est
pas un aplatissement du PLAFOND, c'est un RELEVEMENT DU PLANCHER, et les cinq pilotages le disent
sans interpretation (chestL) :

    accel  0,1848 -> 0,1882  (+1,8 %)     le stimulus le PLUS FORT ne bouge pas
    jerk   0,1771 -> 0,1855  (+4,7 %)
    updown 0,1268 -> 0,1635  (+28,9 %)
    tilt   0,0981 -> 0,1867  (+90,3 %)    le stimulus le PLUS FAIBLE double

La contrainte ajoute une quantite de mouvement QUASI CONSTANTE, independante du stimulus. C'est,
mot pour mot, « un pudding sur lequel on tape tres fort au moindre mouvement ».

**LE MECANISME EST CHIFFRE, ET C'EST UN BARATTAGE POSITIONNEL.** `PHYSSKINC tag=run` :
23 534 corrections pour 101,5 m (cycle 121) contre **35 783 pour 261,3 m** (J1) — 4,3 mm par
correction contre **7,3 mm**, soit ~6 mm de deplacement de joint par frame contre **~15 mm**.
`ROOM-IDLE` suit la meme loi : 0,0001 -> 0,0051 m, et `PHYSIDLE dev` chestR 0,2301 -> **20,9039 u**
— *exactement* la valeur de la variante D du cycle 121 (20,90), ce qui montre que le budget
d'entree ne mord PAS au repos.

**CONSEQUENCE POUR LA SUITE, ET ELLE EST GENERALE.** Sur les SEPT bornes maintenant essayees
(A-F au cycle 121, ce budget au cycle 122), **toutes celles qui font baisser `skinadd` augmentent
le barattage, et toutes celles qui augmentent le barattage relevent le plancher de `tipvar`**. La
relation est monotone sur les deux points mesures (6 mm/frame -> 47 % d'ecart ; 15 mm/frame ->
13 %). Toute proposition future qui augmente l'AUTORITE de `phys-skin-chain` doit donc predire son
barattage par frame AVANT sa course, et montrer pourquoi elle echappe a cette relation.

## NOTE-534  (moteur, `phys-snapshot-sim!` + le bloc d'ecriture — LE VOLUME DE COLLISION EST UN PROXY RIGIDE, cycle 122)

**LE FAIT QUI OUVRE CETTE NOTE, ET IL EST MESURE, PAS DEDUIT.** Build JETABLE, canal de forme rendu
SANS MEMOIRE (`sxd/syd/szd` = `sx0/sy0/sz0`, c'est-a-dire l'etat d'AVANT le lot §11 du cycle 120),
tout le reste bit-identique au cycle 121, meme salle, meme pilotage :

    ROOM-SKINPEN chestR   cycle 121 : 0,0887 m     canal SANS MEMOIRE : **0,0869 m**
    ROOM-SKINPEN chestL   cycle 121 : 0,0696 m     canal SANS MEMOIRE :   0,0690 m

0,0869 <= 0,0883 : **la gate `COLLIDE` passerait**. Et 0,0869 est EXACTEMENT la valeur que le
cycle 120 avait relevee AVANT son propre lot. **La cause de l'echec de `COLLIDE §33/§34` n'etait
pas `phys-skin-chain`.** Les cycles 118 a 122 ont cherche cinq familles de correctifs dans une
fonction qui n'etait pas la coupable.

**LE CHEMIN, ET IL EST UNIQUE.** Pendant le solveur, `skel bones` porte la pose d'AUTEUR de la
frame — l'animation la recalcule a chaque frame et la physique n'ecrit qu'a la fin. Donc ni
`phys-surf-sd` (qui construit la surface avec `skel bones`), ni les points d'echantillon de
`phys-skin-chain`, ni ceux de `phys-pen-chain` ne voient le tenseur de forme. Le tenseur n'entre
que dans la matrice ECRITE (`:3879`), et **la seule chose qui relit cette matrice est
`phys-snapshot-sim!`**, qui place les VOLUMES DE COLLISION que la frame suivante lira
([[feedback_delivered_value_bound_feeds_back_via_snapshot]]). Audit fait PAR VALEUR sur les sept
appels a `phys-surf-sd` et sur les deux instantanes, pas sur une liste ecrite a la main.

**CE QUI ETAIT INCOHERENT.** `phys-col-centre` applique la matrice ECRITE — donc
`R_auteur . rot . DFM` — a l'offset local du volume. Le CENTRE suivait donc le tenseur de forme,
pendant que le RAYON, mesure sur la geometrie de bind, ne le suivait pas. Avec un offset de
~651 u et des echelles a 0,97-1,06 en fenetre `run`, cela deplace le centre de plusieurs dizaines
d'unites — et le transitoire du second ordre de §11, qui monte a 1,29, l'amplifie.

**LE CORRECTIF.** Le repere du maillon est releve JUSTE AVANT que le tenseur entre
(`*phys-rgm*`, `*phys-rgok*`), et c'est lui que `phys-snapshot-sim!` utilise. La deformation reste
INTACTE dans ce qui est LIVRE au rendu : `phys-skin-chain` n'est pas touchee d'un bit, et §11 est
conservee AU CHIFFRE (`ROOM-SPEC11-STEP` pic 1,2939 / 1,2852, identiques au cycle 121).

**LE PRIX, MESURE ET PUBLIE.** `DISCRIMINANT` sur `chestR` tombe de 34 % a **23,5 %**, sous le
plancher de 25 % — et la SIGNATURE est l'inverse de celle des sept bornes de peau : ici c'est le
PLAFOND qui baisse (`accel` 0,2064 -> 0,1842, -10,8 %) et non le plancher qui monte (`updown`
0,1363 -> 0,1410, `tilt` 0,1432 -> 0,1432 inchange). `chestL` PASSE et s'ameliore meme (46,9 % ->
48,0 %). Le mouvement que le lot retire est celui que le volume de collision injectait en suivant
le tenseur avec un rayon fixe, et il n'apparait qu'a fort stimulus.

**CE QUE LE LOT AMELIORE PAR AILLEURS, SUR LA MEME COURSE :** `ROOM-STRETCH` 2,7913 -> 2,1863 % ·
`ROOM-APEX` chestR 0,9397 -> 0,8796 B0 · `ROOM-COM` chestR 0,4388 -> 0,4154 B0 · `meshpen` chestL
0,0499 -> 0,0490 m. `ROOM-IDLE` reste a 0,0001 m et le controle positif d'ablation tire toujours
sur les deux chaines.

**LA QUESTION OUVERTE QUE CE LOT NE TRANCHE PAS.** Un volume de collision doit-il suivre une
deformation qui CONSERVE LE VOLUME (`ROOM-SPEC8` : det = 0,999998 a 1,000000) mais change la
FORME, quand le proxy est une sphere ou une capsule qui ne peut representer aucune anisotropie ?
Les deux reponses coherentes sont « ni le centre ni le rayon » (ce lot) et « le centre ET la
forme » (qui demande un proxy non spherique). Ce qui n'est pas coherent est ce qu'il y avait :
le centre suivait, la forme non. La seconde reponse n'est pas essayee ici et se nomme comme
chantier, elle ne se suppose pas resolue.

## NOTE-536  (docstring deplacee le 2026-08-25, lot L ; aucune ligne de CODE touchee)

```
  "e^-x pour x >= 0 : le facteur de RETENTION qu'un taux `x` produit sur UN pas. Pade(3,3),
   erreur relative < 1e-6 sur [0, 0.8] — la plage reellement utilisee ici est [0.021, 0.708].
   Ne depend pas de `exp` de trigonometry.gc, routine PS2 decompilee non verifiee."
```

## NOTE-537  (docstring deplacee le 2026-08-25, lot L ; aucune ligne de CODE touchee)

```
  "Facteur COMMUN qui met la POINTE dans le budget d'apex de SPEC 22 (SPEC 21 sature la COMBINAISON).
   NATURE rapport sans dimension ; REPERE deviation ABSOLUE de la pointe a sa pose d'auteur, monde
   (SPEC 2/9) ; ABSENT = 1.0 exact dans le budget. [NOTE-120] -> jak-hd-physics-NOTES.md"
```

## NOTE-538  (docstring deplacee le 2026-08-25, lot L ; aucune ligne de CODE touchee)

```
  "L'instantane de JACOBI : la position de FIN DE FRAME de tout volume porte par un joint simule.
   Appelee une seule fois, apres que toutes les chaines ont ecrit. C'est ce que la frame SUIVANTE
   lira, pour toutes les chaines a la fois."
```

## NOTE-539  (docstring deplacee le 2026-08-25, lot L ; aucune ligne de CODE touchee)

```
  "La pire entree SOUS la peau vue sur la fenetre, en unites de jeu, ou 0 si le lien est reste
   dehors. A lire A COTE de `meshpen` : celui-ci mesure contre les VOLUMES (29.7 % de la
   geometrie), celui-la contre la PEAU."
```

## NOTE-535  (moteur — LE VOLUME DE COLLISION SUIT LA FORME D'EQUILIBRE, PAS LE TRANSITOIRE, cycle 122 lot L)

**CE QUI FONDE CE LOT EST UNE MESURE, PAS UNE IDEE.** La course de diagnostic ([NOTE-534]) a ete
relue avec le CODE DE LA GATE `DISCRIMINANT` extrait tel quel. L'extracteur est CONTROLE : sur la
course du moteur du cycle 121 il rend **46,9 % / 34,0 %**, exactement les chiffres publies. Sur la
course de diagnostic (canal de forme SANS MEMOIRE) il rend **47,0 % / 28,2 %** — les deux au-dessus
du plancher de 25 %, avec `skinpen chestR` a 0,0869. **Le diagnostic tenait donc DEJA les deux
gates ; ce qu'il ne tenait pas, c'est §11.**

**LE LOT.** Un second tenseur `*phys-dfmq*` est bati avec les MEMES echelles prises a la cible de
gravite directe (`sx0/sy0/sz0`) au lieu de l'etat du second ordre — meme racine cubique de
conservation de volume, meme `sqz`/`smc`, meme torsion. Le repere que l'instantane de Jacobi lira
(`*phys-rgm*`) est le repere du maillon compose de CE tenseur. Le tenseur ECRIT au squelette, lui,
garde le second ordre : **§11 est conservee AU CHIFFRE** (`ROOM-SPEC11-STEP` pic 1,2939 / 1,2852,
identiques au cycle 121). Le proxy de collision suit la forme que l'ORIENTATION dicte ; il ne
chasse pas un transitoire qu'une sphere a rayon fixe ne peut pas representer.

**RESULTAT — LES 13 GATES DE MESURE PASSENT, `[PASS]` EST IMPRIME.**

    ROOM-SKINPEN         0,0696 / 0,0887  ->  0,0749 / **0,0865**   (plancher 0,0883)
    DISCRIMINANT         46,9 % / 34,0 %  ->  46,1 % / **33,4 %**
    ROOM-SPEC11-STEP     1,2939 / 1,2852  ->  1,2939 / 1,2852       (INCHANGE)
    ROOM-IDLE            0,0001 m         ->  0,0001 m
    meshpen chestR       0,0915 m         ->  **0,0724 m**

**ET VOICI LE PRIX, QUI EST REEL ET QUI DOIT ETRE LU AVANT LE VERT.** La grandeur APPARIEE — la
seule qui dise ce que la PHYSIQUE enfonce — **EMPIRE SUR LES DEUX CHAINES** :

    ROOM-SKINADD   chestL 0,0696 -> **0,0749** (+7,6 %)   chestR 0,0654 -> **0,0681** (+4,1 %)
    ROOM-STRETCH   2,7913 -> 2,8973 %      ROOM-COM chestL 0,4363 -> 0,4630 B0
    residu 7e passe 0,0277 -> 0,0415 m

**DONC : `COLLIDE` AU VERT NE VEUT PAS DIRE QUE §33/§34 EST TENUE, ET LE REGISTRE LA GARDE
`NON TENUE`.** La gate compare deux MAXIMA LATCHES, et le registre sait depuis longtemps que ce
verdict-la est SAIN quand il echoue et VIDE quand il passe
([[feedback_verdict_on_difference_of_latched_maxima]]). Ici il passe pendant que la grandeur
honnete recule : c'est la definition meme d'un faux vert, et il est declare comme tel au lieu
d'etre presente comme un progres.

**UNE PREMISSE N'EST PAS VERIFIEE, ET JE LA NOMME.** J'avais predit (P18) que le lot reproduirait
le diagnostic, puisque le rendu ne retro-agit QUE par l'instantane. Sur `chestR` c'est vrai
(0,0865 contre 0,0869 predit a +-0,0005). **Sur `chestL` c'est FAUX : 0,0749 contre 0,0690.** Un
ecart de 8,5 % que je n'explique pas. Soit mon tenseur quasi-statique n'est pas celui du
diagnostic, soit le rendu retro-agit par un second chemin que [NOTE-534] n'a pas trouve. **C'est
le premier falsificateur du cycle 123**, et il se teste sans course neuve : comparer
`*phys-dfsq*` publie contre `*phys-dfs*` du build de diagnostic, frame a frame, sur `chestL`.


---
## [NOTE-540] — le rayon du noyau EST la distance au dernier voisin retenu : il s'adapte a la

Migre VERBATIM depuis `jak-hd-physics.gc:1870-1871` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
        ;; le rayon du noyau EST la distance au dernier voisin retenu : il s'adapte a la densite
        ;; locale, et le poids qui s'y annule est ce qui rend la fonction continue.
```

---
## [NOTE-541] — les m voisins sont a la MEME distance : le noyau s'annule partout et la moyenn

Migre VERBATIM depuis `jak-hd-physics.gc:1886-1887` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
             ;; les m voisins sont a la MEME distance : le noyau s'annule partout et la moyenne
             ;; ponderee n'est pas definie. On rend le plus proche, sans inventer de poids.
```

---
## [NOTE-542] — MEME GENOU, MEME ASYMPTOTE, MEME TANH DE PADE QUE LE FILET AMONT. Le duplicat

Migre VERBATIM depuis `jak-hd-physics.gc:2018-2019` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
              ;; MEME GENOU, MEME ASYMPTOTE, MEME TANH DE PADE QUE LE FILET AMONT. Le duplicat est
              ;; assume : factoriser ferait bouger la course DESARMEE et detruirait son controle.
```

---
## [NOTE-543] — la mesure mediale partage la fenetre de la peau : un seul reset, donc jamais d

Migre VERBATIM depuis `jak-hd-physics.gc:2063-2064` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
    ;; la mesure mediale partage la fenetre de la peau : un seul reset, donc jamais deux
    ;; populations sous un meme rapport (`ratio-of-two-statistics`, deja paye au cycle 61).
```

---
## [NOTE-544] — DECISION 1, cote SOLVEUR uniquement : la profondeur du volume ecarte ne partic

Migre VERBATIM depuis `jak-hd-physics.gc:2187-2188` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                 ;; DECISION 1, cote SOLVEUR uniquement : la profondeur du volume ecarte ne
                 ;; participe pas au recul. La MESURE (`prio` = 0) continue de la voir.
```

---
## [NOTE-545] — DOMAINE : les DEUX termes reellement EN CONTACT. Le tableau rabote a zero un r

Migre VERBATIM depuis `jak-hd-physics.gc:2312-2313` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
              ;; DOMAINE : les DEUX termes reellement EN CONTACT. Le tableau rabote a zero un
              ;; residu negatif ; un couple dont un terme est rabote ne mesure aucune reponse.
```

---
## [NOTE-546] — direction de l'os du porteur : de SON parent vers lui. A defaut (porteur racin

Migre VERBATIM depuis `jak-hd-physics.gc:2476-2477` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                  ;; direction de l'os du porteur : de SON parent vers lui. A defaut (porteur
                  ;; racine), la verticale du monde vers le bas — ce qui pend, pend.
```

---
## [NOTE-547] — LA PREUVE QUE LA PLACE A CHANGE, et de combien : la distance au porteur que le

Migre VERBATIM depuis `jak-hd-physics.gc:2499-2500` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                ;; LA PREUVE QUE LA PLACE A CHANGE, et de combien : la distance au porteur que le
                ;; rig donne, contre celle que l'ancienne heuristique donnait (le rayon `rl`).
```

---
## [NOTE-548] — les deux lignes restantes, sans branche cachee : iv=0 -> (1,2) iv=1 -> (0,2) i

Migre VERBATIM depuis `jak-hd-physics.gc:2617-2618` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                               ;; les deux lignes restantes, sans branche cachee :
                               ;;   iv=0 -> (1,2)   iv=1 -> (0,2)   iv=2 -> (0,1)
```

---
## [NOTE-549] — CE QUE LA DECISION A COMPARE, publie tel quel : sans ces deux nombres, « le la

Migre VERBATIM depuis `jak-hd-physics.gc:2626-2627` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; CE QUE LA DECISION A COMPARE, publie tel quel : sans ces deux nombres,
                          ;; « le lateral est la ligne 0 » resterait une affirmation de source.
```

---
## [NOTE-550] — --- MESURE SEULEMENT. Acceleration MONDE de la pose d'auteur de ce lien : elle

Migre VERBATIM depuis `jak-hd-physics.gc:2735-2736` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                            ;; --- MESURE SEULEMENT. Acceleration MONDE de la pose d'auteur de ce
                            ;; lien : elle ne produit plus aucune force, elle definit le stimulus.
```

---
## [NOTE-551] — LE STIMULUS REELLEMENT RECU PAR LA POINTE, quelle qu'en soit la source (pilota

Migre VERBATIM depuis `jak-hd-physics.gc:2745-2746` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                            ;; LE STIMULUS REELLEMENT RECU PAR LA POINTE, quelle qu'en soit la
                            ;; source (pilotage de la salle, rotation du porteur, animation).
```

---
## [NOTE-552] — ---- LA CHAIR : direction de repos du MATERIAU, relevee UNE fois ---- et const

Migre VERBATIM depuis `jak-hd-physics.gc:2815-2816` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                 ;; ---- LA CHAIR : direction de repos du MATERIAU, relevee UNE fois
                                 ;; ---- et constante ensuite. Elle ne suit pas l'animation.
```

---
## [NOTE-553] — le facteur de raideur de chaque LIGNE (1.0 partout tant que la chaine n'est pa

Migre VERBATIM depuis `jak-hd-physics.gc:2921-2922` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                        ;; le facteur de raideur de chaque LIGNE (1.0 partout tant
                                        ;; que la chaine n'est pas classee : isotropie stricte)
```

---
## [NOTE-554] — SPEC 22 : plafond NORMAL (genou) et marge jusqu'au plafond DUR, en unites de `

Migre VERBATIM depuis `jak-hd-physics.gc:3129-3130` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                     ;; SPEC 22 : plafond NORMAL (genou) et marge jusqu'au plafond
                                     ;; DUR, en unites de `B0` — la CHAIR (SPEC 6), pas l'os.
```

---
## [NOTE-555] — SPEC 33/34 — la poussee de contact de CETTE frame, remise a zero avant les bal

Migre VERBATIM depuis `jak-hd-physics.gc:3153-3154` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; SPEC 33/34 — la poussee de contact de CETTE frame, remise a zero avant les
                    ;; balayages : elle n'est pas un etat, elle est l'integrale d'une frame.
```

---
## [NOTE-97] — bloc rattache a la note existante (cycle 128) — les quatre grandeurs de l'instrument vivent EXACTEMENT le meme cycle de vie qu

Bloc RATTACHE a [NOTE-97], qu'il portait deja dans le source. Migre VERBATIM depuis
`jak-hd-physics.gc:3159-3160` (cycle 128) pour tenir le plafond de 4800 lignes de la gate
CLEAN. Aucun numero neuf n'est consomme. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                        ;; [NOTE-97] les quatre grandeurs de l'instrument vivent EXACTEMENT le meme
                        ;; cycle de vie que `*phys-cpu*` : une frame, pas un etat.
```

---
## [NOTE-556] — t2 porte la pose d'auteur de la frame PRECEDENTE : le bloc d'integration vient

Migre VERBATIM depuis `jak-hd-physics.gc:3257-3258` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                              ;; t2 porte la pose d'auteur de la frame PRECEDENTE : le bloc
                              ;; d'integration vient d'y decaler l'ancienne valeur de t1.
```

---
## [NOTE-557] — frame ou au moins une paire (lien, volume) etait en contact : c'est la seule s

Migre VERBATIM depuis `jak-hd-physics.gc:3301-3302` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; frame ou au moins une paire (lien, volume) etait en contact : c'est la
                          ;; seule sorte de frame ou « penetration nulle » veut dire quelque chose.
```

---
## [NOTE-558] — 360 / 65536 : `atan` rend des unites de rotation, on publie des degres.

Migre VERBATIM depuis `jak-hd-physics.gc:3388-3389` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                           ;; 360 / 65536 : `atan` rend des unites de rotation, on
                                           ;; publie des degres.
```

---
## [NOTE-559] — MEME LIGNE, MEME NORMALISATION DE LIGNE, MEME INSTANT : seule la grandeur proj

Migre VERBATIM depuis `jak-hd-physics.gc:3422-3423` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                              ;; MEME LIGNE, MEME NORMALISATION DE LIGNE, MEME
                                              ;; INSTANT : seule la grandeur projetee change.
```

---
## [NOTE-560] — --- la pointe : amplitude de l'ecart (physique seule) et intention --- d'auteu

Migre VERBATIM depuis `jak-hd-physics.gc:3434-3435` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                      ;; --- la pointe : amplitude de l'ecart (physique seule) et intention
                      ;; --- d'auteur sur CETTE chaine, la meme frame (SPEC 5).
```

---
## [NOTE-561] — pointe d'AUTEUR dans le repere de l'ancre (transformation de POINT : w = 1, la

Migre VERBATIM depuis `jak-hd-physics.gc:3442-3443` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                            ;; pointe d'AUTEUR dans le repere de l'ancre (transformation de POINT :
                            ;; w = 1, la translation compte)
```

---
## [NOTE-562] — la normale est celle de la poussee, exprimee en MONDE ; le tenseur de deformat

Migre VERBATIM depuis `jak-hd-physics.gc:3764-3765` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                                ;; la normale est celle de la poussee, exprimee en MONDE ; le tenseur
                                ;; de deformation vit en espace ANCRE, on y ramene donc la normale.
```

---
## [NOTE-563] — la correction est une TRANSLATION RIGIDE de l'organe : `dl` la repartit sur le

Migre VERBATIM depuis `jak-hd-physics.gc:4025-4026` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; la correction est une TRANSLATION RIGIDE de l'organe : `dl` la repartit sur les
                          ;; maillons de sorte que la somme PONDEREE recoive exactement `-(1-g) s`.
```

---
## [NOTE-564] — les accumulateurs suivent EXACTEMENT la correction : une translation entre dan

Migre VERBATIM depuis `jak-hd-physics.gc:4035-4036` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; les accumulateurs suivent EXACTEMENT la correction : une translation entre dans
                          ;; `tp`, `rp` et `dp` sont inchanges, et l'identite e = tp + rp + dp referme.
```

---
## [NOTE-565] — ET LE COM SUIT : les maillons deplaces portent `cws` de la masse de COM, donc

Migre VERBATIM depuis `jak-hd-physics.gc:4039-4041` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                          ;; ET LE COM SUIT : les maillons deplaces portent `cws` de la masse de COM, donc le
                          ;; centre publie bouge de `cws * dl * s`. Laisser `comex` sur la valeur d'avant
                          ;; publierait un COM qui ne decrit plus le squelette livre (regle du 2026-08-19 23:50).
```

---
## [NOTE-127] — bloc rattache a la note existante (cycle 128) — TOUS les maillons ont contribue, ou AUCUN chiffre n'est publie : un poids manq

Bloc RATTACHE a [NOTE-127], qu'il portait deja dans le source. Migre VERBATIM depuis
`jak-hd-physics.gc:4044-4045` (cycle 128) pour tenir le plafond de 4800 lignes de la gate
CLEAN. Aucun numero neuf n'est consomme. Aucune ligne de code n'a ete deplacee ni reecrite.

```
                    ;; [NOTE-127] TOUS les maillons ont contribue, ou AUCUN chiffre n'est publie : un
                    ;; poids manquant ne doit jamais se lire comme un COM de zero.
```

---
## [NOTE-566] — la boite englobante part vide : un min a 0 la forcerait a contenir l'origine e

Migre VERBATIM depuis `jak-hd-physics.gc:4116-4117` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
      ;; la boite englobante part vide : un min a 0 la forcerait a contenir l'origine et
      ;; gonflerait l'amplitude mesuree.
```

---
## [NOTE-567] — la deviation angulaire propre de CHAQUE maillon part de zero : c'est un maximu

Migre VERBATIM depuis `jak-hd-physics.gc:4130-4131` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
      ;; la deviation angulaire propre de CHAQUE maillon part de zero : c'est un maximum, et un
      ;; maillon qui suit rigidement son parent doit pouvoir lire exactement zero.
```

---
## [NOTE-81] — bloc rattache a la note existante (cycle 128) — les trois miroirs par maillon sont des maximums et un compte DE FENETRE, comme

Bloc RATTACHE a [NOTE-81], qu'il portait deja dans le source. Migre VERBATIM depuis
`jak-hd-physics.gc:4135-4136` (cycle 128) pour tenir le plafond de 4800 lignes de la gate
CLEAN. Aucun numero neuf n'est consomme. Aucune ligne de code n'a ete deplacee ni reecrite.

```
      ;; [NOTE-81] les trois miroirs par maillon sont des maximums et un compte DE FENETRE, comme
      ;; leurs equivalents par chaine juste en dessous : meme portee, meme remise a zero.
```

---
## [NOTE-568] — la colonne du tableau : le residu signe de la fenetre, ou 0 si aucune frame de

Migre VERBATIM depuis `jak-hd-physics.gc:4180-4181` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; la colonne du tableau : le residu signe de la fenetre, ou 0 si aucune frame de la fenetre n'a eu
;; le moindre contact. Le nombre de frames en contact est publie a part (phys-auth which=7).
```

---
## [NOTE-569] — AMPLITUDE de mouvement de la pointe due a la PHYSIQUE seule, sur la fenetre :

Migre VERBATIM depuis `jak-hd-physics.gc:4186-4187` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; AMPLITUDE de mouvement de la pointe due a la PHYSIQUE seule, sur la fenetre : la diagonale de la
;; boite englobante de l'ecart. Zero si la fenetre n'a pas de frame.
```

---
## [NOTE-155] — bloc rattache a la note existante (cycle 128) — les deux maxima apparies partent de la sentinelle « aucun contact », comme l'e

Bloc RATTACHE a [NOTE-155], qu'il portait deja dans le source. Migre VERBATIM depuis
`jak-hd-physics.gc:4455-4456` (cycle 128) pour tenir le plafond de 4800 lignes de la gate
CLEAN. Aucun numero neuf n'est consomme. Aucune ligne de code n'a ete deplacee ni reecrite.

```
  ;; [NOTE-155] les deux maxima apparies partent de la sentinelle « aucun contact », comme
  ;; l'emplacement 4 de `*phys-st*` : un maximum plafonne a zero rendrait la colonne constante.
```

---
## [NOTE-570] — CONTROLE POSITIF DU CANAL D'AUTEUR : 1 = l'animation est retardee d'une frame

Migre VERBATIM depuis `jak-hd-physics.gc:4465-4466` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; CONTROLE POSITIF DU CANAL D'AUTEUR : 1 = l'animation est retardee d'une frame dans la position
;; ecrite. Le compteur d'identite doit s'effondrer ; s'il ne bouge pas, il ne mesure rien.
```

---
## [NOTE-571] — SPEC 21/22 : 6 = sous-pas integres avec le RESSORT QUI RAIDIT actif (pas un su

Migre VERBATIM depuis `jak-hd-physics.gc:4476-4477` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
    ;; SPEC 21/22 : 6 = sous-pas integres avec le RESSORT QUI RAIDIT actif (pas un suppresseur, il
    ;; ne retire rien) ; 9 = fois ou le FILET positionnel a mordu, 10 = ce que LUI a retire (unites).
```

---
## [NOTE-572] — l'etat de contrainte de la frame precedente est oublie aussi : sinon la premie

Migre VERBATIM depuis `jak-hd-physics.gc:4520-4521` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
  ;; l'etat de contrainte de la frame precedente est oublie aussi : sinon la premiere frame de la
  ;; fenetre suivante compterait une bascule qui n'a pas eu lieu dans cette fenetre.
```

---
## [NOTE-109] — bloc rattache a la note existante (cycle 128) — le cumul par branche vit le meme cycle que le reste du diagnostic : c'est ce q

Bloc RATTACHE a [NOTE-109], qu'il portait deja dans le source. Migre VERBATIM depuis
`jak-hd-physics.gc:4523-4524` (cycle 128) pour tenir le plafond de 4800 lignes de la gate
CLEAN. Aucun numero neuf n'est consomme. Aucune ligne de code n'a ete deplacee ni reecrite.

```
  ;; [NOTE-109] le cumul par branche vit le meme cycle que le reste du diagnostic : c'est ce qui
  ;; rend les deux jambes d'un controle comparables sans qu'aucune ne herite de l'autre.
```

---
## [NOTE-573] — COMBIEN DE FOIS LE VOLUME `ci` A CONTRAINT LE MAILLON `link` DE `chain` — le c

Migre VERBATIM depuis `jak-hd-physics.gc:4639-4640` (cycle 128) pour tenir le plafond de
4800 lignes de la gate CLEAN. Aucune ligne de code n'a ete deplacee ni reecrite.

```
;; COMBIEN DE FOIS LE VOLUME `ci` A CONTRAINT LE MAILLON `link` DE `chain` — le compte est
;; desormais PAR MAILLON, plus par chaine : c'est la dimension qui manquait pour dire LEQUEL viole.
```

## [NOTE-574]

SPEC 11 — L'ETAGE RIGIDE : 12 constantes de mesh par chaine, le rapport MESURE chaque frame, et
son DENOMINATEUR publie a cote.

**LE DEFAUT QUE CA CORRIGE, ET IL EST CHIFFRE PAR ETAGE (cycle 127).** La chaine livre DEJA
1,0977 a 1,1415 de longueur racine->apex par sa seule RECONFIGURATION — nuage `RIGID` : matrices
livrees, decomposition polaire, rotation seule, `S = I`, zero etirement de tissu. Et le tenseur de
forme recevait malgre tout la cible TOTALE de la section (`PHYSORI2` 1,2195 / 1,2125). Resultat :
1,13 x 1,22 = 1,38 commande pour une bande de 1,18-1,26, et 1,2734 a 1,3363 effectivement livre
sur la peau re-skinnee. **C'est un DOUBLE COMPTE, pas un mauvais reglage** : la meme longueur
etait demandee deux fois, une fois par la geometrie et une fois par le solveur.

**POURQUOI DES CONSTANTES CUITES, ET POURQUOI CE N'EST PAS UN REGLAGE.** Sous skinning lineaire le
vecteur racine->apex de la chair est EXACTEMENT une somme par OS :

        d = c_dist - c_prox = Somme_b ( ds_b . R_b + dm_b t_b )

`ds_b` et `dm_b` sont des differences de centroides ponderes entre la population DISTALE et la
population PROXIMALE, chacune renormalisee par son propre total. Elles ne dependent QUE du mesh
livre et de la pose de bind — aucun verdict, aucune mesure de course n'entre dans leur calcul.
Meme classe que `*phys-lcx/lcy/lcz*` et `*phys-apx/apy/apz*`, deja cuits et deja lus.
Cuisson et validation : `.autoport/c128_bake_rigid.py`.

**DEUX PROPRIETES EXACTES QU'ON EXPLOITE.** (1) `Somme_b dm_b = 0` par construction, donc `t_b`
peut etre pris RELATIF A L'ANCRE sans rien changer : la contribution de translation de l'ancre
s'annule, et les magnitudes tombent de ~1e5 unites monde a ~1e3 unites d'offset, ce qui rend le
transport en milli-unites (`phys_mi`) sans effet. (2) `dm` est malgre tout multiplie par un offset
de ~1e3 unites : il est donc cuit **x1000** et remultiplie par 0,001 ici. Sans ce facteur, la
quantification couterait 0,4 point sur le rapport ; avec, elle en coute 0,0004.

**CE QUI A ETE ESSAYE ET REFUTE AVANT D'EN ARRIVER LA — trois estimateurs moins chers, tous tues
par leur propre falsificateur, tous ecrits d'avance :**
  - `|pos(distal) - pos(proximal)|`, le PROXY POSITIONNEL (c127b) : 13,0 / 14,2 points d'ecart.
    Cause : la corde d'os est invariante a 1e-4 dans toutes les poses — l'etage rigide est
    **entierement ANGULAIRE** ;
  - `|apex - joint racine|`, l'estimateur GRATUIT (c127, P9), calculable sans un seul flottant
    neuf : 9,3 a 14,7 points. Meme cause que P8c — la part de la region DISTALE portee par
    l'ANCRE n'est cuite dans aucun enregistrement, et c'est exactement le trou de SPEC 23 ;
  - `1 + k (1 - cos theta)`, le proxy ANGULAIRE a un parametre (c128, C1) : REFUSE par sa GARDE DE
    VACUITE avant meme d'etre juge sur son ecart. `theta` ne vaut que **6,9 a 8,3 degres** au
    prone pour un allongement de +13 % : le levier est de ~x18, donc une erreur de 1 degre sur
    l'angle deplacerait l'estimation de 30 %. **L'etage rigide est un LEVIER, pas une rotation** —
    tout estimateur qui passe par un angle SCALAIRE est hypersensible par construction.
  - l'agregat a DEUX os {ancre, distal} (c128, C2) : 6,96 points, au-dessus de la barre des 5. Le
    maillon PROXIMAL compte.
Le controle NEGATIF, `rigide = 1` (aucune correction), echoue a 9,8-14,2 points : le double compte
est reel et non trivial.

## [NOTE-575]

SPEC 11 — L'ETAGE RIGIDE, MESURE ICI (etape (b)) ET DIVISE HORS DE LA CIBLE DE FORME.

**POURQUOI ICI ET PAS A L'ECRITURE.** L'ordre du pas est : 0 longueurs d'os -> 1 integration ->
2 contraintes -> **(b) cibles de forme** -> (f) matrice -> 6 ecriture. Les POSITIONS sont FINALES
quand (b) tourne (les contraintes sont passees), mais les MATRICES d'os solvees n'existent qu'a
l'etape 6. Latcher l'estimateur a l'etape 6 pour le consommer a (b) aurait coute ~15 lignes de
moins et **une frame de retard** — c'est-a-dire une boucle de retro-action sur le diviseur, dans un
dossier qui a deja paye deux cycles limites (`feedback_constraint_on_discontinuous_field_limit_cycles`,
`feedback_bound_undone_by_downstream_constraint_loop`). On paie les lignes, pas le retard : la
rotation de deflexion est donc RECONSTRUITE ici a partir des positions finales, exactement comme
l'etape 6 la reconstruira (`rest` -> `pt` autour du pivot d'ANCRE, `matrix-axis-angle!`).

**L'ESTIMATEUR EST AUTO-NORMALISANT, ET C'EST UNE CORRECTION MESUREE, PAS UN CHOIX DE STYLE.**
Le premier jet cuisait le denominateur `L0` a la pose de BIND. Mesure : 706,4 / 717,4 unites, la ou
la cellule DEBOUT de la course en rend 597,6 / 645,3 — **la pose debout d'auteur n'est PAS la pose
de bind**, ecart de 11,2 a 18,2 %. Le rapport devenait faux d'autant alors que la FORME de
l'estimateur etait juste a 0,06 / 0,40 point. Le moteur calcule donc les DEUX au meme instant :

        d_defl = ds_a . R_ancre + Somme_l [ ds_l . (R_auteur,l . rot_l) + dm_l (p_solvee,l - ancre) ]
        d_auth = ds_a . R_ancre + Somme_l [ ds_l .  R_auteur,l          + dm_l (p_auteur,l - ancre) ]
        rigide = |d_defl| / |d_auth|

`d_auth` est la MEME chaine, a la MEME orientation, SANS la deflexion physique. Le rapport est donc
« ce que la reconfiguration ajoute », qui est la definition meme du nuage `RIGID`, et il vaut 1,000
par construction quand la physique ne deflechit rien — sans aucune constante de reference.

**RESERVE, ET ELLE EST PUBLIEE PLUTOT QUE TUE.** Cette forme suppose que `|d_auth|` ne depend pas
de l'orientation, ce qui est vrai si l'animation ne pilote pas les joints de poitrine (SPEC §5).
Ce n'est PAS verifiable hors ligne : la trace archivee ne porte que les matrices LIVREES. Le moteur
publie donc `dauth` a cote du rapport (`PHYSRIGID`), et la constance se lit sur la course. Une
hypothese muette serait un faux vert en attente.

**CE QUE LA DIVISION TOUCHE, ET C'EST UNE SEULE LIGNE.** `phl` — la cle `HangingLengthScale`
(index 3 du preset, SPEC 11 l.179) — devient `phl / rigide` AVANT d'entrer dans le melange
d'orientation. Aucune ligne de commande n'est ajoutee. Consequences par construction :
  - a la pose DEBOUT, `rigide = 1` et la cible est INCHANGEE : la correction a un domaine, et son
    controle negatif de portee est cette invariance ;
  - au SUPINE, `rigide < 1` mais le poids de melange de `phl` y est nul : la division ne peut pas
    y agir, et c'est verifie plutot que suppose ;
  - la chaine sans enregistrement `rg` garde `rigide = 1,0` : un manque de donnee ne se lit JAMAIS
    comme une correction de zero (`*phys-rsok*`, et l'accesseur C++ rend 0 pour une chaine muette).

## [NOTE-576]

LA DIVISION RESIDUELLE DE §11 A ETE CABLEE ICI AU CYCLE 128, MESUREE, PUIS **RETIREE PAR SON PROPRE
FALSIFICATEUR**. Ce commentaire existe pour que le prochain cycle ne la recable pas sans savoir ce
qu'elle coute.

**CE QUI A ETE CABLE, EN UNE LIGNE.** `phl` (= `HangingLengthScale`, cle 3 du preset) devenait
`phl / rigide`, ou `rigide` est l'etage rigide mesure par [NOTE-575]. C'est la correction du DOUBLE
COMPTE etabli au cycle 127 : la chaine livre deja ~1,13 des 1,23 que §11 demande, et le tenseur
recevait malgre tout la cible TOTALE.

**CE QUE CA A DONNE, MESURE SUR UNE COURSE COMPLETE** (trace conservee :
`.autoport/reports/Grecharged-secondary-motion/keira-room-x86.c128-experiment.log`, md5
`10aea9db79c1a039eb4bcca8ba408377`) :
  - commande 1,2195 / 1,2125 -> **1,1290 / 1,1129**, DANS l'intervalle admissible que le cycle 126
    avait derive par un balayage de valeur singuliere INDEPENDANT (1,1060-1,1384) ;
  - « Root-to-apex length +18 to +26 % » 1,3363 / 1,2734 / 1,3183 / 1,3116 -> **1,2512 / 1,1986 /
    1,2350 / 1,2246 : DANS sur les QUATRE cellules** ;
  - **MAIS** la clause de COM de §11 passe `DANS` -> `SOUS` sur LES DEUX chaines (0,2278 / 0,2273
    -> 0,1811 / 0,1809 B0, plancher 0,20) : **elle etait tenue PAR le double compte** ;
  - **ET LA GATE `DISCRIMINANT` TOMBE SUR chestR : 33,4 % -> 23,0 %** pour un seuil de 25 %. La
    reponse s'APLATIT — `accel` perd 13,7 % (0,2047 -> 0,1767) pendant que `tilt` ne bouge pas.
    `tipvar` reste tres au-dessus de son plancher (0,1767 contre 0,05) : c'est exactement
    `aplatir n'est pas museler`, et c'est le defaut que l'owner appelle « pudding ».

**LES DEUX COURSES PARTENT DU MEME ETAT** (`target-title`, meme pile, meme tas), donc l'ecart n'est
pas l'artefact de conditions initiales que le cycle 125 a documente. Il est reel.

**CE QUE LA MESURE ETABLIT ET QUI SURVIT AU RETRAIT.** Les deux clauses de §11 sont INCOMPATIBLES
sous un seul bouton, et c'est mesure sur deux points de la meme droite : ramener le COM a son
plancher de 0,20 demande une commande de ~1,166, ou la longueur rend ~1,286, au-dessus de 1,26.
**Aucune valeur de `HangingLengthScale` ne met les deux clauses dans leur bande.** §11 demande donc
un SECOND DEGRE DE LIBERTE — la migration de centre de masse doit se decoupler de l'echelle de
longueur — et c'est le MEME deficit que §10 nomme depuis le cycle 123b (« Outward COM migration
4-10 % W0 » mesuree a +0,797 / -3,744 %).

**L'ESTIMATEUR, LUI, RESTE.** [NOTE-574]/[NOTE-575] sont conserves et publient `PHYSRIGID` : c'est
la grandeur que le prochain lot doit commander, elle est validee (0,000-0,442 pt contre le nuage
`RIGID`), et son denominateur est verifie a la course (etendue 0,007 %). Ce qui est retire est la
COMMANDE, pas la MESURE.

## [NOTE-579]

**`phys-shape` 38/39 — LA PREUVE D'EXECUTION DU GAIN `lyield`, ET ELLE MANQUAIT AU CYCLE 135.**

Le cycle 135 a cable le canal `lyield=` (correction du DOUBLE COMPTE de §11, [NOTE-578]) et l'a
mesure par ses effets — longueur et COM livres. Il n'a publie AUCUNE ligne disant que le canal
avait ete LU. C'est le mode d'echec de [NOTE-236], sur un autre parametre : un zero silencieux au
parseur C++ (cle mal orthographiee, `kPhysNumChainParams` pas incremente, id deja pris) rend le
tableau `*phys-lyd*` a zero, donc le diviseur `1 + ly*(rs-1)` a **1.0 exactement**, donc le moteur
**bit-identique** a celui d'avant. Un cycle entier sans effet, dont les chiffres se lisent comme un
resultat — et rien dans la trace ne permettrait de le distinguer.

**NATURE** : deux nombres SANS DIMENSION, par chaine. **REPERE** : aucun, ce sont des rapports.
**LIGNE DE BASE, c'est-a-dire ce que l'instrument lit quand le canal est ABSENT** : `ly = 0.0000`
et `div = 1.0000` exactement — la valeur par defaut de toute chaine qui ne declare pas la cle, et
l'identite par algebre. Une ligne `PHYSRIGID … ly=0.0000 div=1.0000` dit donc, sans ambiguite,
« le canal n'a rien fait ».

  - **38** = la valeur que le PARSEUR a reellement deposee dans le tableau que lit la ligne du
    tenseur (`jak-hd-physics.gc:3594`) — pas la valeur ecrite dans `physics_chains.txt`, pas celle
    du source : celle qui est dans le tableau, a la frame ou on la lit ;
  - **39** = le DIVISEUR effectivement applique, ecrit avec l'expression EXACTE de cette ligne,
    `fmax 0.0001` compris, sur les MEMES deux tableaux. Le publier avec sa garde permet de voir la
    branche degeneree si elle etait un jour atteinte, au lieu de la supposer inatteignable.

`rs` (38 est lu a cote de 36 sur la meme ligne `PHYSRIGID`) rend la relation verifiable de
l'exterieur : `div` doit valoir `1 + ly*(rs-1)` a l'arrondi pres, sur chacune des 22 cellules du
balayage d'orientation. Un desaccord designerait un `sc` qui n'est pas le meme des deux cotes.

**POURQUOI CETTE LIGNE ET PAS UN `format` AU CHARGEMENT.** Un echo au chargement prouverait que le
parseur a rendu la valeur, pas que le tenseur la lit a la frame ou le verdict se forme. La ligne
`PHYSRIGID` est emise DANS le balayage d'orientation, cellule par cellule — c'est-a-dire exactement
la ou §11 est jugee, et par le meme chemin que `rs` que le verdict utilise deja.

## [NOTE-578]

SPEC 11 — LA DIVISION DU DOUBLE COMPTE EST RECABLEE, AVEC UN GAIN, PARCE QUE LE FALSIFICATEUR QUI
L'AVAIT RETIREE REPOSAIT SUR UN INSTRUMENT REFUTE DEPUIS.

**CE QUI CHANGE PAR RAPPORT A [NOTE-576], ET C'EST UNE MESURE, PAS UN AVIS.** [NOTE-576] conclut
« Aucune valeur de `HangingLengthScale` ne met les deux clauses dans leur bande » et ferme la
route. Sa clause de COM venait de l'instrument SUBSTITUT, celui que le cycle 133 a refute pour une
erreur de MODELE : il substituait `(D-I).L/N` — des moments en base de BIND, autour de l'ANCRE — a
un tenseur que le moteur applique `bm.D`, APRES la rotation de l'os et AUTOUR DU JOINT.

Recalcul avec l'instrument du c133 (`c133_delivered_com.py`), MEME code, MEMES traces archivees,
controle de portage **0,0000 %** sur les 8 cellules de decile, lecture hors defaut (i=9) a
0,0004-0,0009 B0 :

                          t=0 (livre)     t=1 (lot c128)    bande
      longueur chestL      1,336258         1,251187        <= 1,26
      longueur chestR      1,318303         1,235022        <= 1,26
      COM      chestL      0,2459           0,1966          >= 0,20
      COM      chestR      0,2413           0,1924          >= 0,20
      DISCRIM  chestL       46,1 %           48,6 %         >= 25 %
      DISCRIM  chestR       33,4 %           23,0 %         >= 25 %

Le substitut publiait **0,1811 / 0,1809** a t=1, soit -9,5 % / -9,6 % sous le plancher. La valeur
LIVREE est **0,1966 / 0,1924**, soit **-1,7 % / -3,8 %**. C'est ce facteur ~5 sur l'AMPLEUR du
defaut qui avait ferme la route, et il n'existait pas.

**LES DEUX CLAUSES SE BORNENT PAR LES DEUX BOUTS, DONC LA CORRECTION EST UN GAIN.** La longueur
exige d'en mettre ASSEZ, le COM d'en mettre PAS TROP, et la gate generique `DISCRIMINANT` ajoute un
plafond sur chestR. Fenetres du modele a deux points, par chaine :

      chestL : longueur t >= 0,8964 · COM t <= 0,9310 · DISCRIMINANT ne contraint pas (il MONTE)
      chestR : longueur t >= 0,7001 · COM t <= 0,8446 · DISCRIMINANT t <= 0,8157

Les deux sont NON VIDES, et elles ne se recouvrent pas entre chaines : le gain est **par chaine**,
ce qui est la granularite naturelle — `phl` est deja par chaine (`pb = sc * PHYS-PSET-N`) et
`rigide` est mesure par chaine (`*phys-rsv*`).

**FORME EXACTE, ET SON CONTROLE NEGATIF EST UNE IDENTITE :**

      phl_effectif = phl / (1 + lyield * (rigide - 1))

`lyield=0` rend le diviseur **exactement 1** — pas « proche de 1 », exactement 1 — donc le moteur
est bit-identique a celui d'avant ce cycle, et c'est le defaut de toute chaine qui ne declare pas
la cle. `lyield=1` rend `phl / rigide`, c'est-a-dire **exactement le lot c128** : c'est ce qui rend
le modele a deux points legitime, les deux bouts etant des points MESURES et non extrapoles.

**CE QUI RESTE UNE HYPOTHESE, ET ELLE EST PUBLIEE PLUTOT QUE TUE.** L'interpolation entre les deux
bouts est LINEAIRE et rien ne l'impose. Les deux bouts sont mesures ; tout ce qui est entre eux est
un modele, et la course le teste. Les six predictions chiffrees et leur falsificateur sont ecrits
AVANT le lot dans `.autoport/c135-predictions.txt`. La plus mince est `DISCRIMINANT` sur chestR :
0,67 point au-dessus d'une gate a 25 %. C'est nomme d'avance, et c'est precisement pourquoi
`lyield` est de la **DONNEE** — une reprise ne coute pas un build.

## [NOTE-577]

**SPEC 31 — LE POINT FIXE DE LA DEFORMATION EST CELUI QUE LA SECTION NOMME, PAS L'ORIGINE DU JOINT.**

Sa §31 (`SPEC-breast-softbody.md:388-390`) ecrit son abscisse mot pour mot : « With `r = 0` at chest
attachment and `r = 1` at distal/apex region, a useful deformation weighting is `w(r) = r^1.6…2.0`
— **little deformation at the root** ». Le moteur, lui, mettait `bm vector 3` a zero avant le
produit par `dfm` puis ECRASAIT la translation par la position du solveur : le point fixe du
tenseur etait donc **l'origine du joint**, un point que la spec ne nomme nulle part.

**MESURE (cycle 132, mesh LIVRE `out/jak1/fr3/skin/keira-hd-lod0.glb`, pose de bind, axe de §31 tel
qu'il est deja construit par `.autoport/physics_c14_meshsamples.py:340-348` — celui-la meme qui cuit
`ax` et `b0`) : l'origine du joint tombe a**

    lBoob r = -0,0654   45,87 u = 0,0762 B0      lBooc r = -0,0602   42,28 u = 0,0702 B0
    rBoob r = -0,0423   30,43 u = 0,0505 B0      rBooc r = -0,0443   31,83 u = 0,0529 B0

soit **EN ARRIERE** du point r=0 des quatre cotes, de x2,5 a x3,8 le seuil de refutation declare
d'avance (0,02 B0). L'axe de §31 est par ailleurs **quasi perpendiculaire a l'axe d'os** (88,5 deg /
90,6 deg) : le deplacement joint -> r=0 est presque entierement TRANSVERSE, il n'est pas colineaire
a l'os et ne peut donc pas etre porte par un facteur d'echelle le long de la chaine.

**LE CANAL.** Ancrer `D` en `a` au lieu du joint ajoute a chaque sommet pilote l'offset constant
`a.(I - D)`. Le moteur calculait DEJA cette grandeur — `phys-pt-exc!` sur le point d'apex, rangee
dans `dwx/dwy/dwz` — et il la JETAIT. Ici elle est calculee sur le point `anch . anp`, deposee dans
la translation de `tmp`, et l'ecriture finale ADDITIONNE `(-> bm vector 3 …)` au lieu de l'ecraser.

**TROIS PROPRIETES, ET C'EST CE QUI REND LE LOT SUR :**
  1. **le point desarme est l'identite PAR ALGEBRE, pas par reglage.** A `anch = 0` le point passe a
     `phys-pt-exc!` est `(0,0,0)`, dont l'excursion vaut `tmp.trans - bm.trans = 0 - 0` exactement,
     donc la translation deposee est `0.0` et l'ecriture rend `p` au bit pres. Meme forme que le
     plafond de §21, inerte au repos par algebre (arbitrage du 2026-08-20 18:50) ;
  2. **`dw` reste honnete sans une ligne de plus.** L'offset est depose dans `tmp vector 3` AVANT
     l'appel d'apex, donc ce dernier rend `c2(q) - c2(a)` par linearite : la part TENSEUR de
     l'excursion d'apex inclut l'ancrage, et `s = aw - dw` que lit le plafond de §21 en est
     EXACTEMENT invariant. L'ancrage ne se fait donc pas defaire par la boucle de contrainte en
     aval (`bound-undone-by-downstream-constraint-loop`) ;
  3. **§2/§9 ne peuvent pas etre violees de facon mesurable.** A la pose debout d'auteur le melange
     convexe rend `D` a `6,2e-4 / 4,8e-4` de l'identite (mesure sur `PHYSDFMA c=* i=0`, pas
     raisonnee) ; l'offset y est borne par `|a| . ||A - I||` = **0,0285 u / 0,0147 u**, soit
     `4,7e-5 / 2,4e-5 B0` — **sous le plancher ULP float32 de l'integration monde** (0,0625 u sur
     X/Z, 0,015625 u sur Y). **Ce n'est PAS zero, et l'ecrire « identiquement nul par algebre »
     serait faux** : `D = I` n'est exact qu'en arithmetique reelle.

**RESERVE PUBLIEE AVEC LE CHIFFRE, ET ELLE GOUVERNE L'AMPLITUDE.** Le dossier utilise **deux
populations differentes sous le meme nom « axe de §31 »** : le decile d'apex est cuit sur
`ws>0` PONDERE, la regle livree `anchor30 … gate=0.05 axis=anat` (`recharged_assets/physics_reskin.txt:351-352`)
travaille sur `ws>0,05` NON PONDERE. L'ecart du joint au point r=0 passe de **0,05-0,08 B0** a
**0,32-0,34 B0** selon celle qu'on lit — un facteur 4 a 6 sur la reponse. La spec ne nomme aucun
seuil de poids ; **le choix n'est donc pas tranchable par le texte**, et `anp=` porte la premiere
lecture (celle qui cuit `ax`) parce que c'est celle du reste de la chaine de mesure. Meme classe
que `two-distal-axes-are-not-the-same-population`.

## [NOTE-580]

**SPEC 10 — LE MUR MEDIAN. LE DEFAUT ETAIT UN SIGNE, ET AUCUNE ECHELLE NE RETOURNE UN VECTEUR.**

Sa §10 (`SPEC-breast-softbody.md` l.169) : « **Outward COM migration per breast: 4-10% W0, nominal
7% W0** ». Mesure du cycle 136 sur l'organe LIVRE (`c133_delivered_com.py`, cellule supine i=8, cut
`w>0.00`) : **-2,260 % W0 (chestL) / -7,164 % W0 (chestR)**. Le COM migre vers l'**INTERIEUR**, sur
les deux chaines. Ce n'est pas une amplitude a corriger : c'est un signe, et le cycle 136 l'avait
nomme sans le traiter (« aucune valeur de `lyield` ne retourne un vecteur »).

**CE QUE LE SIGNE N'EST PAS.** L'axe `out` de l'instrument est anti-symetrique par construction
(`probe_breast_com_mass.py:99-102` : `OUTW = {'chestL': -sepv, 'chestR': +sepv}`), donc une derive
COMMUNE au monde y rendrait des signes OPPOSES. Les deux mesures ont le **MEME** signe : ce n'est
donc pas un artefact de repere, c'est une migration mediale reelle des deux cotes. Le falsificateur
etait deja ecrit dans l'instrument avant d'etre utile — il a tire.

**OU LE DEFICIT VIT, MESURE ETAGE PAR ETAGE ET PAS RAISONNE.** La ligne `DECOMPOSITION SIGNEE SUR
`out`` ajoutee a `c133_delivered_com.py` au cycle 137 separe l'identite exacte du skinning lineaire
en ses deux moities (elle se referme a 1,2e-10 u) :

        i=8 supine, cut w>0.00      ROTATION+TENSEUR    TRANSLATION    somme
        chestL                          -1,010 %W0       -1,250 %W0    -2,260
        chestR                          -3,303 %W0       -3,861 %W0    -7,164

**LES DEUX ETAGES TIRENT VERS L'INTERIEUR, a peu pres a parts egales.** Ce n'est donc pas « le
solveur » contre « le tenseur » : c'est que **rien** dans le moteur ne pousse vers l'exterieur. Le
balayage par valeur des 13 ecritures de `*phys-px/py/pz*` le confirme : gravite, ressort, §21, §22
et la contrainte de longueur sont soit commun-mode, soit purement radiaux ou rotationnels ; les
seuls termes a signe PAR CHAINE sont la collision (:1744) et la contrainte de peau (:1985), et
aucun des deux n'est actif dans la cellule supine.

**LE MECANISME QUE LA SECTION NOMME, ET IL EST DEJA A MOITIE LA.** Le tenseur elargit deja l'organe
au supine — `sx` = **1,2257 / 1,2057** (cle `SupineWidthScale` = 1,23), publie par `PHYSORI2`, et la
largeur LIVREE suit a 1,171 / 1,161. Mais il l'elargit **AUTOUR DU JOINT**, et la section interdit
exactement cela, en gras dans son texte :

    l.174  « The breast root shall remain broadly attached. **The entire breast shall not simply
             scale uniformly from its center.** »
    l.172  « wider footprint against the thorax; moderate outward migration; increased separation »
    §8 l.145 « flattening redistributes material laterally »

Elargir autour du joint fait traverser au **bord MEDIAL de la chair** le plan sagittal contre lequel
il repose au repos. Ce qui manquait n'est pas une force : c'est la **NON-PENETRATION** de ce
bord-la.

    d_sortant = medw * max(0, sx - 1)          porte par `*phys-fx*`, le lateral SORTANT

**POURQUOI `max(0, .)` ET PAS UN GAIN SYMETRIQUE — c'est la propriete qui protege trois sections.**
Un sternum resiste a la compression du bord medial ; il ne tire jamais. La contrainte est donc
UNILATERALE, comme tout contact, et ce n'est pas un choix de commodite : c'est ce qui rend le terme
nul **PAR ALGEBRE** partout ou §10 ne parle pas.

        debout        sx = 1,0000 (PHYSORI2 i=9)          -> terme 0   §2/§9 intactes
        prone         sx = 0,9234 / 0,9338                -> terme 0   §11 intacte (gain du c136)
        couchee-cote  sx = 0,8240 / 0,8047 cote gravite   -> terme 0   §12 intacte (l'une des 4 TENUE)

Sans l'unilateralite, le meme terme aurait retire **-4,20 % W0** a §11 et **-8,4 % W0** aux deux
cellules de §12 — c'est-a-dire qu'il aurait paye §10 avec une section TENUE. Le point admissible
commun a ete cherche AVANT la course, pas apres (`bound-undone-by-downstream-constraint-loop`).

**LA VALEUR EST MESUREE, PAS AJUSTEE — ET C'EST LA CONDITION POUR QUE CE NE SOIT PAS UN MIROIR.**
La directive du 2026-08-23 16:00 interdit de fabriquer un canal pour une cle-REPONSE : « une reponse
se MESURE, elle ne se pose pas ». « Outward COM migration 4-10 % W0 » EST une reponse — il n'existe
donc aucun bouton a ce nom, et `medw` n'en est pas un. C'est une longueur relevee sur le maillage
LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`) :

        joint `chest`                            x = 0,000 u  — exactement sur le plan sagittal
        racines lBoob / rBoob                    +379,90 / -379,91 u  — miroir exact
        sommet de chair le plus MEDIAL           +54,24 u du plan sagittal, IDENTIQUE sur les DEUX
                                                 chaines a 0,01 u pres
        medw = 379,90 - 54,24 = 325,66 (chestL)  ·  379,91 - 54,24 = 325,67 (chestR)

Le produit livre est donc (geometrie du maillage) x (cle du preset), sans un seul degre de liberte
ajuste sur la bande visee. **RESERVE PUBLIEE AVEC LA VALEUR** : `min` est un EXTREMUM, et le
registre porte `argmax-anchor-is-not-a-population`. Il est retenu parce qu'une non-penetration est
gouvernee PAR DEFINITION par le point le plus profond, et parce que ce point est le meme au
centieme d'unite sur les deux chaines — c'est le sternum, pas un aberrant. Sensibilite declaree :
au 5e percentile (-217,18 / -229,70 u) le terme vaudrait 6,32 / 6,09 % W0 au lieu de 9,47 / 8,63.

**CE QUE LE TERME LIT, ET CE QU'IL NE LIT PAS.** `sx` est `*phys-dfs*` +0, c'est-a-dire l'echelle
d'EQUILIBRE de la forme (`dfa`), pas le produit complet `dfa . dfb . dfc` qui porte aussi
l'etirement dynamique et la pression de contact. C'est deliberé : le mur est une contrainte
anatomique QUASI-STATIQUE, et l'accrocher au transitoire injecterait une impulsion de position a
chaque frame, ce que sa §37 interdit (« artificial transforms must not generate physical breast
impulses »).

**OU IL VIT, ET LA DETTE QUE CA LAISSE.** Le terme est ajoute a `bm vector 3` au site d'ecriture,
juste avant que la position du solveur y soit additionnee — donc `PHYSORIM` le voit, et l'instrument
de l'organe livre aussi. Il ne touche PAS `*phys-px/py/pz*`, donc **les volumes de collision ne
suivent pas ce glissement** : ils restent la ou le solveur a mis les maillons. C'est la meme couture
que le tenseur occupe deja depuis toujours (les volumes lisent `*phys-dfmq*`, la matrice, jamais la
translation), mais c'est une dette et elle se nomme au lieu de se taire.

**PREUVE DE LECTURE, PAS PREUVE PAR LES EFFETS.** `PHYSMEDW c= i= mw= sx= d=` est emise PAR CHAINE
et DANS le balayage d'orientation — la ou §10 se juge — et publie l'operateur APPLIQUE (`d`), pas un
seul de ses facteurs. Ligne de base quand le canal est ABSENT : `mw=0.0000 d=0.0000`. Sans elle, un
zero du parseur (cle mal ecrite, `kPhysNumChainParams` pas incremente) rendrait la course entiere
bit-identique a la precedente, ce qui se relit exactement comme « le modele est faux »
(`channel-measured-by-effect-is-not-channel-proven-read`, et [NOTE-236] pour le mode d'echec).

## [NOTE-581]
### SPEC 8 / SPEC 31 — LE GRADIENT RACINE->APEX, ET IL RETIRE LA TRANSFORMATION AFFINE UNIQUE QUE SPEC 8 INTERDIT EN GRAS

**LES DEUX LIGNES QUI L'EXIGENT, TOUTES DEUX EN GRAS DANS SON TEXTE.**

    SPEC 8  l.143  « ...**but the whole breast shall not be represented by one affine scale
                     transformation.** Instead: root tissue moves little; intermediate tissue
                     redistributes; distal tissue deforms most... »
    SPEC 10 l.173  « **The entire breast shall not simply scale uniformly from its center.** »
    SPEC 31 l.390  « With r = 0 at chest attachment and r = 1 at distal/apex region, a useful
                     deformation weighting is w(r) = r^1.6...2.0 — little deformation at the root;
                     progressively increasing mobility; largest displacement in distal tissue. »

Jusqu'au cycle 138 le moteur appliquait **UNE matrice par CHAINE** (`*phys-dfm* sc`), la meme aux
deux maillons : litteralement la transformation affine unique que sa 8 interdit, et c'etait le seul
motif de son `NON TENUE`.

**LA FORME, ET ELLE EST CHOISIE POUR QUE `CANAL ABSENT` = `COMPORTEMENT D'AVANT` PAR ALGEBRE.**

    A_l  =  B_l . ( I + w_l (D - I) )      B_l = la rotation d'os du maillon, D = le tenseur

ecrit au site d'ecriture comme le melange lineaire des deux matrices qui l'encadrent :

    tmp  <-  w_l . (bm . D)  +  (1 - w_l) . bm

`w_l = 1` rend donc `bm . D` **AU BIT**, et le moteur retombe exactement sur le tenseur uniforme.
C'est ce qui arrive quand `spr=` est absent (`r = 0` -> poids 1 partout) et quand les deux cles de
preset manquent (exposant 0 -> `r^0 = 1` partout). Un canal absent ne fabrique rien.

**LA NORMALISATION, ET C'EST ELLE QUI PROTEGE LES SECTIONS DEJA TENUES.**

    w_l  =  g_l . ( SOMME_k comw_k ) / ( SOMME_k comw_k . g_k )      avec  g_l = spr_l ^ p

La moyenne du poids, ponderee par la MASSE DE PEAU de chaque maillon, vaut donc 1 par construction :
le gradient REDISTRIBUE la deformation le long de la chaine sans en changer le total. Sans cette
normalisation, tout `w < 1` aurait rabote l'amplitude d'ensemble et paye la 8 avec la 11 et la 12,
qui sont dans leur bande — la faute `compensation-route-refuted-by-sibling-section` du registre.

**L'EXPOSANT VIENT DU FICHIER LIVRE, PAS DU MOTEUR.** `RootDeformationExponentLo` (1.6) et
`RootDeformationExponentHi` (2.0) sont dans le preset depuis toujours et n'avaient AUCUN canal ;
elles sont ajoutees a `kPhysPresetKeys` aux indices 27/28 et le moteur en prend le MILIEU. GOAL n'a
pas de puissance flottante : `x^p` est calcule par developpement DYADIQUE (partie entiere par
multiplications, partie fractionnaire par 5 `sqrtf` successifs), donc l'exposant **APPLIQUE** vaut
1.78125 pour un `p` demande de 1.8. L'ecart est publie a cote, et il est sans consequence mesurable
ici : sur la trace archivee, faire varier `p` de 1.6 a 2.0 deplace la clause de sa 10 de 0,03 point
de %W0.

**CE QUE J'AI MESURE AVANT D'ECRIRE, ET CA JOUE CONTRE LE LOT.** `.autoport/c138_graded_tensor.py`
predit l'effet exactement, par identite algebrique sur les matrices LIVREES (`PHYSORIM` x
`PHYSDFMA`), avec deux gardes : `D` est falsifie par l'orthonormalite de `B = A . D^-1` (8.7e-06) et
le controle hors defaut `w = 1` reproduit `c133_delivered_com.py` a 2.3e-13 u. Verdict :

    §10 sortant chestL   +3.062  ->  +2.968 %W0      §10 sortant chestR   -2.536  ->  -2.662 %W0

**Le gradient bouge la clause de 0,09 a 0,13 point, et dans le mauvais sens.** La raison est dans le
RIG et elle se mesure sans course :

    joint lBoob  r = -0.3103        joint lBooc  r = -0.3039      ecart 0,64 % de l'organe
    joint rBoob  r = -0.1744        joint rBooc  r = -0.1767      ecart -0,23 %

**Les deux actionneurs de la chaine sont au MEME `r`.** Un gradient qui est une fonction de `r` n'a
donc aucun levier : il ne peut pas produire « little deformation at the root; largest displacement
in distal tissue » quand la racine et le distal sont au meme `r`. Pire, la chair qu'ils pilotent est
INVERSEE par rapport a leurs noms — `lBoob` (« racine ») pilote une chair a r = 0.8407, `lBooc`
(« distal ») a r = 0.7323. Le gradient est donc applique a la CHAIR, ce que la section decrit, et
non aux noms ; c'est pour cela que le poids du maillon dit « racine » sort **plus grand** que celui
du maillon dit « distal ».

**CE QUE CA NOMME POUR LA SUITE, ET CE N'EST PAS UN DE-SCOPE.** Le blocage de sa 8, de sa 10 et de sa
31 n'est pas dans le solveur : c'est que la chaine ne s'etend pas le long de l'axe racine->apex. Elle
s'etend LATERALEMENT (joints a 325,7 et 376,9 u du bord medial ; chair a 439,2 et 568,7 u). Le
correctif est un REPESAGE, deja autorise par l'owner le 2026-08-17 23:50 (« meme si ca implique de
modifier le rig ») et le 2026-08-19 20:00 (« c'est la geometrie qui bouge »), et c'est exactement la
regle du 2026-08-18 08:55 : une injection d'os n'existe que si le repesage l'accompagne, et la
preuve est la REPARTITION.

**CE QUE LE GRADIENT NE TOUCHE PAS, ET C'EST UNE DETTE, PAS UN OUBLI.** Il est applique a `tmp` au
site d'ecriture, donc a la matrice que `PHYSORIM` publie et que la peau recoit. Il n'est PAS applique
a `*phys-rgm*` (:3914), qui compose `*phys-dfmq*` — le tenseur QUASI-STATIQUE que lisent les volumes
de collision. **Les volumes ne suivent donc pas le gradient**, exactement la meme couture que le mur
median de [NOTE-580] et que le tenseur lui-meme depuis toujours. Elle se nomme.
La TRANSLATION, elle, est intacte : le melange ne porte que sur les neuf coefficients 3x3, et le mur
median lit `bm vector 3` et la matrice d'ancre, jamais la 3x3 — donc la moitie TRANSLATION du COM est
invariante par ce lot, ce que la prediction du cycle utilise et que la course doit confirmer.

**PREUVE DE LECTURE, PAS PREUVE PAR LES EFFETS.** `PHYSGRAD31 c= i= r0= r1= w0= w1=` et
`PHYSGRAD31P c= i= p=` sont emises PAR CHAINE et DANS le balayage d'orientation. Elles publient ce
que le PARSEUR a depose (`r`) ET l'operateur APPLIQUE (`w`), jamais un seul de ses facteurs. Ligne
de base d'un canal ABSENT : `r0=0 r1=0 w0=1 w1=1 p=0`.

## [NOTE-582]

SPEC 10 / SPEC 31 — LE MUR MEDIAN EST GRADUE, ET LES DEUX OPERATEURS DU CHEMIN D'ECRITURE SONT
RETENUS PAR MAILLON.

**CE QUE LA MESURE DU CYCLE 139 A ETABLI AVANT D'ECRIRE UNE LIGNE.** Les colonnes `squel.` et
`tens.` de `ROOM-SPEC10`, qui rendent le verdict de la clause PORTEUSE de §10 (l.169, « Outward
COM migration per breast: 4-10% W0 »), sont baties sur `PHYSORICOML` (issu de `*phys-ldb*`, ecrit
a `jak-hd-physics.gc:3411`) et sur `PHYSDFMA` (la 3x3 de `*phys-dfa*`, batie a :3803-3814). Les
deux PRECEDENT le chemin d'ecriture squelette (:3908). **Donc les deux mecanismes ecrits POUR
cette clause — le MUR MEDIAN du cycle 137 (:3927-3936) et le POINT FIXE de §31 du cycle 132
(:3913-3917) — y sont invisibles AU BIT.** Ce n'est pas une question d'amplitude : c'est
structurel, et c'est MESURE, pas deduit — au cycle 132, deux courses ne differant que par `anch`
(0 -> 1) changent 20 632 des 93 378 enregistrements et laissent `PHYSDFMA`, `PHYSORICOML`,
`PHYSORICOM`, `PHYSORICOM2`, `PHYSORICOM2L` et `PHYSROW` **identiques au bit**.

Sur l'ORGANE LIVRE (`PHYSORIM`, les matrices que le moteur ecrit vraiment dans le squelette — la
grandeur que le contrat de perimetre §7 designe comme « ce qui fait foi »), la meme clause, la
meme cellule (i=8, supine) et la meme frontiere (w>0.00) rendent **+2,968 %% W0 sur chestL et
-2,662 sur chestR**, contre **+0,797 / -3,744** pour le substitut. L'ecart vaut plus de la moitie
de la distance qui separe chestL du plancher de sa bande.

**CE QUE LE LOT ECRIT.**

  1. `mw` devient `medw * max(0, sx-1) * grw_l` : le mur porte desormais le MEME poids de §31 que
     le tenseur depuis le cycle 138. Le mur du cycle 137 etait un GLISSEMENT RIGIDE — le meme
     deplacement a la racine et au distal — c'est-a-dire exactement le cas degenere que §10 l.173
     interdit en gras (« **The entire breast shall not simply scale uniformly from its center.** »)
     et que §31 l.390 chiffre (« little deformation at the root ; ... largest displacement in
     distal tissue »). `*phys-grw*` etant normalise par la masse de peau
     (`SOMME_l comw_l . grw_l = SOMME_l comw_l`), la REDISTRIBUTION ne deplace PAS le centre de
     masse : la prediction ecrite avant la course (`.autoport/c139-predictions.txt`, P6/P7) est
     **zero effet sur §10**, et c'est elle qui rend le lot falsifiable. Si le COM bouge de plus de
     0,01 point, c'est la normalisation du cycle 138 qui est fausse, pas ce lot.
  2. `*phys-mwa*` et `*phys-anca*` retiennent, PAR MAILLON, les deux operateurs TELS QU'APPLIQUES,
     projetes SIGNES sur le lateral sortant MONDE de la chaine. `phys-write-op` les expose et
     `PHYSORIW` (`phys-room.gc`) les publie dans la cellule d'orientation ou le verdict se forme.
     Sans ces deux cases, les deux canaux ne sont mesurables que par leurs EFFETS — ce que
     `channel-measured-by-effect-is-not-channel-proven-read` interdit, et ce qui a fait croire au
     cycle 132 que le point fixe « ne convertit rien » alors que l'instrument ne pouvait pas le
     voir.

**CE QUE LE LOT NE FAIT PAS, ET C'EST NOMME.** Il n'arme pas `anch` (il reste a 0, donc `anc`
vaut 0 par algebre sur toute la trace : c'est la LECTURE HORS DEFAUT de `PHYSORIW`). Il ne touche
pas les volumes de collision : `*phys-rgm*` compose `*phys-dfmq*`, non gradue, et le mur n'entre
pas dedans — meme couture que le tenseur depuis toujours. Dette nommee, pas corrigee ici.

**LE RESULTAT DE LA COURSE, AJOUTE APRES COUP (cycle 139, course md5
`df3ffdbfc2be45c744e70da3de379813`, 31/31 animations, 310 mesures ; controle : la course du cycle
138 md5 `dd3d7273924f3a783af13a8649793069`, meme code SAUF ce lot, dont le tableau a ete REGENERE
par le MEME analyseur pour que la comparaison soit ligne a ligne).**

  - **LA PREDICTION QUI PORTAIT LE LOT EST VERIFIEE, ET ELLE ANNONCAIT ZERO.** La clause porteuse
    passe de `+2,968` a `+2,969 %% W0` sur chestL et de `-2,662` a `-2,661` sur chestR : **+0,001
    point**, dans la bande de +/-0,01 ecrite avant la course. La normalisation du cycle 138 tient
    donc sur l'ORGANE LIVRE, pas seulement en algebre.
  - **LE CONTROLE INTERNE FERME A 5.10^-5.** `SOMME_l comw_l . mur_l` = 42,0195 u (chestL) et
    36,5363 u (chestR) contre `d . SOMME_l comw_l` = 42,0215 et 36,5370, soit 0,0049 %% et
    0,0019 %% d'ecart ; normalisation mesuree `SOMME comw.grw / SOMME comw` = 0,99995 / 0,99998.
  - **LES DEUX LECTURES HORS DEFAUT DE `PHYSORIW` TIRENT**, ce qui est le seul moyen de distinguer
    « le canal rend zero » de « le canal n'existe pas » : `anc` = 0,0000 sur **les 44 lignes** sans
    exception (identite algebrique, `anch`=0) ; `mur` = 0 sur **7 des 11 cellules** et non nul
    exactement la ou `PHYSMEDW` publie `sx > 1`. Le compteur suit sa condition de declenchement
    cellule par cellule, pas l'index.
  - **L'UNILATERALITE EST PROUVEE PAR IDENTITE, PAS AFFIRMEE.** Au prone (i=6) `sx` vaut 0,9234 /
    0,9337, donc `max(0, sx-1) = 0` : les deciles racine->apex de §11 sont **identiques au 6e
    decimal** entre les deux courses (1,262916 / 1,260459). « Un sternum resiste et ne tire pas »
    est desormais un nombre.
  - **CE QUE LE LOT GAGNE EST UNE CLAUSE DE FORME, ET ELLE EST MESURABLE.** A COM immobile, la
    distance racine->apex entre centroides de decile de la cellule supine bouge de **-0,242 %%**
    (chestL) et **-0,429 %%** (chestR) ; et l'ecart entre les deux courses aux frontieres SERREES
    monte a +0,006 / +0,029 point la ou la normalisation n'est pas definie, contre +0,001 a
    `w>0,00` ou elle l'est. L'identite tient exactement la ou elle est censee tenir, et pas
    ailleurs — confirmation independante du controle interne.
  - **COUT MESURE : NUL SUR LES DEUX GRANDEURS QUI POUVAIENT PAYER.** `skinpen` 0,0690 / 0,0731 et
    `meshpen` 0,0724 sont INCHANGES AU BIT, `ROOM-IDLE maxdev` reste a 0,0001. La seule prediction
    ratee est P11 : `ROOM-APEX pic_typique` **monte** de +0,0001 B0 des deux cotes (0,6696 ->
    0,6697 et 0,6927 -> 0,6928) la ou j'annoncais « baisse ou nul ». C'est 4 000 fois plus petit
    que l'ecart de §22 (x1,59 / x1,65) et du meme ordre que le controle d'identite de la section
    (`|e|-apex` = 0,000109 B0), donc ca ne separe rien — mais ce n'est ni une baisse ni un zero.

**LA CONSEQUENCE POUR LES LOTS SUIVANTS, ET ELLE EST NEGATIVE ET DEFINITIVE.** +0,001 point sur un
deficit de **1,031** (chestL) et **6,661** (chestR) points de %% W0 : la redistribution paie 0,1 %%
et 0,015 %% du chemin. **Toute route qui esperait fermer §10 en re-repartissant un glissement le
long de la chaine est refutee d'avance** — la normalisation par la masse de peau, celle-la meme qui
protege §11 et §12 d'etre payees pour §10, interdit mecaniquement a une redistribution de deplacer
un centre de masse. Il faut l'AMPLITUDE d'un canal, ou un canal qui n'existe pas encore. La piste
suivante est nommee et mesuree : les moities TRANSLATION livrees valent **+4,073** (chestL) contre
**+0,767** (chestR) pour des glissements appliques dans un rapport de 1,15 seulement — le facteur
5,3 entre les deux n'est PAS explique par le mur, et c'est la premiere chose a mesurer, dans le lot
qui ecrit.

## [NOTE-583]

SPEC 37 — LE DECLENCHEUR DU REBASE ETAIT UNE DISTANCE, ET UNE ANCRE QUI TOURNE SUR PLACE PASSE AU
TRAVERS.

**LE FAIT, ET IL SE VERIFIE EN TROIS GREPS DANS LE MOTEUR DE LA VEILLE.** Sa 37 (l.441-444) exige
un rebase « on teleportation, instant cutscene placement, animation root discontinuity, level
transition, or implausibly large one-frame transform changes », et conclut en gras : « **Artificial
transforms must not generate physical breast impulses.** » L'ACTION du rebase porte bien ses deux
moities depuis le cycle 33 — elle transporte `p`, `q`, `cp`, `cq` par la transformation RIGIDE
`a0m^T . am` plus l'offset d'ancre, et remet a zero la compensation de Kahan (`:2686-2694`). Son
DECLENCHEUR, lui, n'en a jamais eu qu'une :

    rbd = |anc - *phys-anp*|                 <- *phys-anp* est un `vector` (:310)
    (when (> rbd (* 7.00 (fmax 1.0 b0))) ...)

Une ancre qui tourne **sans deplacer son origine** rend `rbd = 0`. Elle ne franchit donc jamais ce
seuil, et toute sa rotation est livree a la chaine comme une impulsion — exactement ce que la
derniere phrase de la section interdit. Le commentaire de `phys-room.gc` affirmait le contraire
(« la moitie ROTATION existe depuis longtemps, roulis de l'ancre, seuil de 0.5 rad ») : le site
qu'il cite ne rebase rien, sa garde `(when (< (fabs dphi) 0.5))` ne fait que **sauter le cumul de
torsion de §29**. Corrige dans le meme lot — un commentaire n'est pas une preuve (regle 0).

**CE QUE LE CYCLE 101 AVAIT MESURE, ET QUI N'AVAIT PAS DE CONSOMMATEUR.** Angle de l'ancre EN UNE
FRAME, 372 fenetres, trace archivee `keira-room-x86.c101-ANROT.log` — p50 / p90 / max, en degres :

    updown                3,62 /  55,66 / 171,87
    leftright/accel/jerk  0,36 /   1,92 /   2,50
    tilt                  3,90 /   4,39 /   4,60
    AUCUN pilotage       59,91 /  60,29 /  60,58    <- sur 100 %% des fenetres

Deux ordres de grandeur separent le regime ordinaire (0,36 deg) du saut (59,9) : il n'y a pas de
zone grise a arbitrer. Et la fenetre SANS PILOTAGE est precisement celle ou vivent les six rouges
d'apex (cycle 80 §4 : p50 0,6443 / 0,6278 B0, **100 %% des fenetres au-dessus de 0,42**, les cinq
pilotages n'ajoutant que +2,0 %% / +13,4 %% par-dessus).

**CE QUE LE CYCLE 140 ECRIT.**

  - `phys-anrot-omc` — `1 - cos(angle)` de la rotation d'ancre d'une frame, par la trace de
    `a0m^T . am` sur les lignes **NORMALISEES** des deux reperes. La normalisation n'est pas une
    precaution de style : une matrice d'os porte une echelle, et une trace lue sur des lignes non
    unitaires melangerait l'echelle a l'angle. NATURE : un scalaire sans dimension, monotone en
    l'angle sur [0, 180 deg] — **ce n'est pas un angle**, et la conversion en degres est faite par
    l'analyseur. REPERE : aucun, c'est la comparaison des deux reperes entre eux, donc invariante
    par rotation du monde. LECTURE HORS DEFAUT : 0.0 exactement quand ils coincident.
  - `rbrot=` (id 32 du magasin C++) — le seuil, **livre en DEGRES** dans `physics_chains.txt` et
    range en `1000 * (1 - cos theta)`. Le facteur 1000 n'est pas cosmetique : le magasin traverse
    vers GOAL en MILLI-unites, et un `1 - cos` nu arrondirait 1 degre (1,52e-4) a **zero** milli —
    un seuil pose pour un controle positif se lirait alors comme DESARME. Avec le facteur, un
    milli vaut 1e-6 de corde, soit 1,7e-4 degre a 20 degres.
  - le declencheur : `(when (or (> rbd (* 7.00 ...)) (and (> rbt 0.0) (> omc rbt))) ...)`.
    `rbt = 0` rend la seconde branche **inatteignable**, donc le defaut de toute chaine qui ne
    declare pas la cle est BIT-IDENTIQUE a tous les builds anterieurs.
  - **LE SIGNE PORTE L'ARMEMENT, et c'est ce qui fait tenir la mesure ET son controle negatif dans
    UNE SEULE course.** Le COMPTE (case 101) lit `|rbt|`, le REBASE lit `rbt`. Un seuil NEGATIF
    compte donc les frames qui franchiraient `|theta|` **sans rien rebaser** : la course reste
    bit-identique au build de la veille et repond quand meme a la seule question qui decide si le
    correctif est livrable — `nrot / nfr`. Sans ce partage, une course desarmee ne distingue pas un
    SCALPEL (une ou deux frames par fenetre) d'un BAILLON (toutes les frames, la chaine chevauchant
    l'ancre rigidement), et seul le second est une raison de ne pas livrer.
  - quatre cases de diagnostic a portee de FENETRE (100 = max de `omc`, 101 = compte de
    declenchements, 102 = compte de frames evaluees, **103 = `rbfix`, le maximum de
    `|p_apres - p_avant|` que le rebase applique a un maillon**, en unites de jeu), publiees par
    `PHYSANROT` et `PHYSANROTF`, plus `PHYSANROTK` qui publie la valeur **DEPOSEE PAR LE
    PARSEUR**. `rbfix` est la grandeur que la derniere phrase de la section designe : le rebase
    transporte `p` ET `q` par la MEME transformation rigide, donc la vitesse est conservee dans le
    repere de l'ancre et ce qui est retire est exactement le rattrapage que la chaine aurait du
    faire en une frame — c'est-a-dire **l'impulsion qu'une transformation artificielle lui aurait
    livree**. Nul par algebre en mode MESURE SEULE, ce qui en fait son propre controle negatif. Sans cette derniere, `nrot = 0` ne distingue
    pas « canal absent » de « canal casse » ; sans `nfr`, « une frame par fenetre » et « toutes les
    frames » sont le meme nombre a l'oeil — et le second serait un **MUSELAGE**, la chaine suivant
    l'ancre rigidement au lieu de la subir.

**LE SEUIL EST A NOUS, PAS AU DOCUMENT, ET IL EST DECLARE COMME TEL.** Sa 37 nomme la CLASSE
d'evenement (« implausibly large ») et ne donne aucun nombre. Le choix se justifie par la
distribution mesuree, jamais l'inverse — c'est la regle du 2026-08-20 02:50 sur les durees de
geste, appliquee a un angle.
