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
