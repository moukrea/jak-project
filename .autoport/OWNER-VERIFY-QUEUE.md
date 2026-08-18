# CE QU'IL Y A À SAVOIR SUR CE CYCLE — et il n'y a pas de nouveau build

Branche `physics-keira-clean`.

**AUCUN OCTET LIVRÉ N'A CHANGÉ.** Le moteur, le maillage, les volumes et les réglages sont
identiques au bit près au build précédent — tu as déjà exactement ce binaire, et il n'y a donc rien
à télécharger ni à regarder de neuf à l'écran. Ce n'est pas un build retenu pour cause de qualité
(ta consigne là-dessus est respectée) : il n'y a pas de build à retenir.

Ce cycle a corrigé mes **instruments** et audité mes **chiffres**. Cinq de mes annonces du build
précédent étaient fausses. Voilà ce qui compte pour toi.

---

## 1. LE RÉGLAGE QUE TU MONTES DEPUIS LE 11 AOÛT N'EST BRANCHÉ SUR RIEN

`couple` — celui que tu as fait passer de 1.00 à 1.45, puis 1.20, 1.55, 1.85 pour que ses seins
« bougent un peu plus ». Il est lu dans le fichier, rangé dans une variable, et **utilisé nulle
part**. Vérifié en listant toutes ses occurrences dans le moteur : il y en a trois, et aucune n'est
un calcul de force.

**Ce n'est pas un oubli, c'est une conséquence de ta propre spec.** Le 13 août, sur ta demande, le
terme moteur `−couple × accélération de l'animation` a été remplacé par celui de ta §3
(réorientation de la gravité + accélération du torse). Cette formule-là n'a pas de coefficient de
couplage : il n'y avait plus rien à multiplier. Le réglage a survécu au modèle qui l'utilisait.

Mon fichier de réglages affirme encore noir sur blanc que `couple` « reste ACTIF ». C'est faux, et
c'est corrigé au dossier.

**C'est à toi de trancher, parce que c'est ta ligne dans ton fichier :** je peux la retirer, ou la
laisser comme trace. Je ne l'efface pas sans que tu le dises. Et le rebrancher n'est pas une
option — ça remettrait le modèle que tu as fait retirer.

**Ce qu'il faut retenir en pratique** : si tu trouves que ça ne bouge pas assez, le levier n'est pas
`couple`. Ce sont les fréquences de ta §24 et la raideur de ta §28, qui sont implémentées et qui
mesurent dans leurs bandes.

## 2. JE RETIRE LA QUESTION QUE JE T'AI POSÉE AU BUILD PRÉCÉDENT

Je t'avais demandé : « est-ce que le sein gauche traîne plus que le droit après un à-coup ? », en
t'annonçant que le gauche était sorti de ma fenêtre de mesure (>2,5 s) alors que le droit était à
1,50 s.

**C'était mon instrument, pas ses seins.** Ma mesure cherche l'instant où l'agitation retombe sous
1 % de son niveau de départ. Le résidu qui reste quand tout est calmé vaut **1,04 %** à gauche et
**0,67 %** à droite. À gauche il est juste au-dessus de la barre, donc la barre n'est jamais
franchie et mon instrument écrit « jamais » ; à droite il est juste en dessous, donc il écrit
« 1,50 s ». Les deux seins se distinguent de 0,37 point de pourcentage et j'en ai fait un abîme.

Et mon autre instrument, sur la même course, dit que **les six canaux des deux seins se stabilisent
en 0,82 à 0,95 s**, dans la fenêtre visée. Tu n'as pas cette asymétrie à chercher.

## 3. CE QUI EST MAINTENANT MESURÉ POUR LA PREMIÈRE FOIS, ET QUI EST SOUS TA CIBLE

Tes sections 10, 11 et 12 chiffrent un déplacement du **centre de masse** du sein selon
l'orientation. Mon seul instrument qui le mesurait n'en calculait que la moitié : la part portée par
les **os**, en oubliant la part portée par la **déformation de la chair** — qui est précisément le
mécanisme que ta §10 décrit (« le centre de masse se rapproche du thorax »). En l'ajoutant :

| | ta cible | mesuré |
|---|---|---|
| sur le dos (§10) | 23 % | 29 % à gauche, 18 % à droite |
| à plat ventre (§11) | 24 % | 21 % à gauche, 23 % à droite |
| **couché sur le côté (§12)** | **19 %** | **8 % et 18 % à gauche · 17 % et 4 % à droite** |

**Le côté est le point faible, et il est asymétrique en miroir** : chaque sein répond correctement
quand la gravité tire d'un côté et deux à quatre fois trop peu quand elle tire de l'autre. En
moyenne sur les quatre mesures : 12 % contre les 15–24 % que tu demandes.

En revanche la **forme** (aplatissement, élargissement, allongement) tient tes **neuf** chiffres,
sur les deux seins, dans les trois orientations. Ça n'avait jamais été comparé à ta spec.

## 4. CE QUI RESTE OUVERT ET QUE TU PEUX VOIR

**Les deux seins se traversent encore**, jusqu'à 12 cm sur les mouvements forts. C'est même la pire
traversée du sein gauche — et c'est le mécanisme que le cycle précédent venait d'armer pour
satisfaire ton « ils s'entrechoquent ». Le contact existe donc bien des deux côtés maintenant, mais
l'interpénétration n'est pas fermée. Je m'étais trompé au build précédent en accusant la bretelle :
la mesure de la course livrée désigne le sein opposé.

## 5. UN POINT DE STRUCTURE, ET TU L'AS DÉJÀ AUTORISÉ

Les deux os de chaque sein sont alignés **sur le rayon qui va du torse au sein**, et la masse du
sein se trouve à **86 degrés** de cet axe. Autrement dit : la déformation de la chair est bien
orientée (elle tient ses neuf cibles), mais l'**articulation** ne l'est pas — elle ne peut pas
exprimer l'allongement racine→pointe que ta §11 demande, parce que sa direction n'est pas celle du
sein.

Le corriger demande de déplacer un os **hors** de ce rayon, donc de retoucher le rig. Tu l'as
autorisé explicitement le 17 août (« même si ça implique de modifier le rig »). C'est une passe de
rig et de cuisson de maillage, pas une retouche — c'est le prochain gros morceau.
