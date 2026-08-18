# CE QU'IL Y A À SAVOIR SUR CE CYCLE — rien de neuf à regarder à l'écran

Branche `physics-keira-clean`.

**LA PHYSIQUE N'A PAS BOUGÉ D'UN BIT, ET C'EST PROUVÉ, PAS AFFIRMÉ.** J'ai ajouté deux mesures dans
le code (donc le binaire change), mais **rien qui déplace un os**. La preuve : j'ai relancé la salle
de test au complet et regénéré le tableau de mesures — il est à **zéro ligne d'écart** de celui
d'avant. Les ~4700 lignes, tous les compteurs, toutes les colonnes : identiques. Le maillage, les
volumes et tes réglages sont eux aussi inchangés au bit près.

Donc : **tu ne verras aucune différence à l'écran**, et ce n'est pas un build retenu pour cause de
qualité (ta consigne là-dessus est respectée). Ce qui a changé est ce que je peux MESURER — et cinq
de mes annonces précédentes étaient fausses à cause de ce que je ne mesurais pas.

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

## 3. CE QUI EST MAINTENANT MESURÉ POUR LA PREMIÈRE FOIS

Tes sections 10, 11 et 12 chiffrent un déplacement du **centre de masse** du sein selon
l'orientation. Mon instrument n'en calculait que la moitié — la part portée par les **os** — en
oubliant la part portée par la **déformation de la chair**, qui est précisément le mécanisme que ta
§10 décrit. Les deux moitiés sont maintenant mesurées. Résultat :

| | ta cible | mesuré (gauche / droite) | |
|---|---|---|---|
| sur le dos (§10) | 23 % (18–28) | 26 % / 27 % | **dans la bande** |
| à plat ventre (§11) | 24 % (20–30) | 24 % / 25 % | **dans la bande, quelle que soit la définition du contour du sein** |
| couché sur le côté (§12) | 19 % (15–24) | 8 % et 19 % / 15 % et **3 %** | **le point faible** |

**§11 est la première de tes sections d'orientation à être tenue** sur la grandeur qu'elle nomme, des
deux côtés, et sans que le choix du contour du sein change le verdict.

**§12 (couchée sur le côté) est le défaut qui reste, et il est directionnel.** Chaque sein répond
correctement quand la gravité tire d'un côté et deux à sept fois trop peu quand elle tire de l'autre
— et c'est en miroir entre les deux seins. Ce n'est donc pas un manque d'amplitude global : c'est une
direction qui ne répond pas. C'est le prochain chantier de physique.

**ET JE CORRIGE CE QUE JE T'AI ÉCRIT PLUS HAUT DANS CE MÊME CYCLE.** J'avais annoncé « sur le dos :
29 % à gauche, 18 % à droite », soit une asymétrie de 59 % entre tes deux seins. C'était la moitié de
déformation qui me manquait : sur la mesure complète c'est 26 % et 27 %, **1,6 % d'écart**. Il n'y a
pas d'asymétrie gauche/droite sur le dos, et tu n'as pas à la chercher.

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
