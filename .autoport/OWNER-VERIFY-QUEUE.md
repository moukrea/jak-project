# CE QU'IL Y A À REGARDER SUR CE BUILD — la poitrine, et elle seule

Branche `physics-keira-clean`. (Le tag est lisible sur le device : `files/.custom_pack_stamp_jak1`.)

Rien d'autre sur Keira n'a été touché : cheveux, bretelles, lunettes, languettes, pantacourt
restent **gelés** par ton ordre du 14/08 — pas réparés, gelés, avec leur mesure au dossier.

**Aucune donnée n'a changé sur ce build** : les réglages, le maillage et les volumes sont
identiques au bit près au build précédent. Ce qui a changé est **le solveur**, à un seul endroit.
Donc tout écart que tu verras vient de là, et de rien d'autre.

---

## 1. D'ABORD, UNE CORRECTION : CE QUE JE T'AI ÉCRIT AU BUILD PRÉCÉDENT ÉTAIT FAUX

Je t'avais écrit que la poitrine traversait le buste **« parce que dans la pose d'origine, physique
éteinte, le nœud du sein est déjà 5,9 cm à l'intérieur du volume épaule→torse »**, et que c'était
donc le volume qu'il fallait refaire, pas la physique.

**Le fait est vrai, la conclusion était fausse**, et je l'ai vérifiée par le calcul avant de
repartir dessus. Le chiffre que je publie (« pénétration ») n'est pas une profondeur : c'est un
**écart à la pose d'origine**, donc cette profondeur de départ en est **déjà retranchée**. J'ai
comparé une distance avec une autre dont elle avait été soustraite.

La vérification : si on rétrécit un volume de collision, la profondeur de départ change de
plusieurs centimètres et le chiffre que je publie **ne bouge pas d'un cheveu** — c'est exact au
bit près, pour une raison géométrique. Autrement dit : **refaire ce volume n'aurait rien donné**,
et j'allais y passer un cycle entier.

## 2. CE QUI A ÉTÉ CORRIGÉ À LA PLACE

Le solveur finissait chaque image par **remettre l'os à sa bonne longueur** — et cette dernière
opération **remettait le sein dans le buste** juste après l'en avoir sorti. Personne ne revérifiait
après. C'est réparé : la poussée qui sort le sein du buste est maintenant faite **le long de son
arc de rotation**, donc la remise à longueur ne la défait plus.

Ce que ça donne, mesuré :

| | build précédent | **ce build** |
|---|---|---|
| mouvement de la pointe | 0,178 / 0,182 | **0,194 / 0,197** (+9 %) |
| nombre de fois où un volume écrase le sein | 32 275 / 26 906 | **23 513 / 21 235** (−27 % / −21 %) |
| allongement de l'os | 0,02 % | **0,02 %** (l'os ne s'allonge toujours pas) |

**CE QUE ÇA DEVRAIT DONNER À L'ŒIL** : la poitrine devrait réagir **différemment selon le
mouvement** — une secousse et une inclinaison ne doivent plus se ressembler. Avant ce build, elle
répondait presque pareil à tout, parce qu'un volume la plaquait à chaque image.

## 3. LA QUESTION QUE JE TE POSE, ET C'EST LA SEULE

**Le retour au calme est plus lent.** Après un à-coup, ça met plus de temps à s'arrêter qu'au build
précédent (1,5 s à droite au lieu de 1,5 s tout juste ; à gauche c'est sorti de ma fenêtre de
mesure). C'est la contrepartie directe des 9 % de mouvement gagnés.

Tu as dit « perky, pas pendouillant ». **Est-ce que c'est encore perky, ou est-ce que ça commence à
traîner ?** Si ça traîne, je sais exactement quoi remonter, et j'ai déjà le réglage mesuré qui le
ramène dans la bande (il coûte un peu sur la traversée).

## CE QUI N'EST TOUJOURS PAS RÉGLÉ, ET JE NE LE CACHE PAS

* **La poitrine traverse encore le buste sur les mouvements forts, et le pire n'a pas baissé**
  (0,097 m à gauche, 0,089 m à droite, contre 0,094 / 0,079). La moitié basse du problème a
  reculé — la valeur médiane baisse, 199 fenêtres sur 310 s'améliorent — mais **l'extrême n'a pas
  bougé**. Ce build sait pour la première fois **contre quoi** :
  * à gauche, contre **la bretelle** (le petit volume de la sangle du haut). Ce volume n'accorde
    **aucune tolérance** : le mur est posé pile sur la pose d'origine. Or la bretelle **repose dans
    la chair** — elle est 1,9 cm à l'intérieur du sein au repos. Une bretelle qui s'enfonce dans la
    chair, c'est normal ; là, c'est interdit par construction. **C'est le prochain chantier**, et
    c'est une décision à prendre, pas un réglage.
  * à droite, contre la capsule d'épaule, et là c'est un vrai reste de solveur : la direction de
    sortie est presque alignée sur l'os, donc la rotation ne peut presque pas l'en sortir.
* **Les deux seins ne se voient pas l'un l'autre de la même façon** : le contact sein↔sein n'est
  compté que du côté de celui qui est résolu en second dans le fichier. Mesuré et prouvé au build
  précédent par une inversion d'ordre, **pas encore corrigé** — je n'ai pas voulu faire deux
  changements de solveur dans la même mesure, ça les aurait rendus inattribuables.
* **Le retour exact au repos** reste très bon (écart 0,0004 sur un plafond de 1,0).
