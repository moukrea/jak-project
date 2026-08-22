# RIEN A TESTER — MAIS UNE LIGNE DE TA SPEC EST PASSEE AU VERT, ET J'AI UNE ERREUR A RETIRER

Branche `physics-keira-clean`. **A tester : rien.** Je maintiens ce que je t'ai dit le 20 : tant
qu'une poignee de sections sur 38 tiennent, te demander de juger a l'oeil te coute plus que ca ne
me rapporte. Le build est la si tu le veux.

---

## 1. LA PREMIERE LIGNE DE TA SPEC QUI PASSE AU VERT PAR UN CHANGEMENT DE PHYSIQUE

Ta section 12 — celle du corps couche sur le cote — est **tenue**, sur ses deux lignes chiffrees
qui designent un sein precis :

    ta ligne  « le sein du dessus migre vers le milieu de 10 a 18 % de sa largeur »
    mesure    sein gauche 12,4 a 15,1 %   ·   sein droit 12,5 a 16,1 %      DANS, des deux cotes

    ta ligne  « le sein du dessous s'aplatit de 15 a 25 % »
    mesure    0,84 et 0,82 d'echelle, soit -16 % et -18 %                   DANS, des deux cotes

Jusqu'ici c'etait « a moitie » des deux cotes. C'est la premiere fois depuis le debut du dossier
qu'une section passe au vert **parce que le moteur a change**, et pas parce que j'ai reclasse une
mesure.

**Ta troisieme ligne de la 12 reste sans verdict, et c'est toujours ma question du 21** : que veut
dire « Global » dans « Global lateral COM response 15-24 % » ? Selon la lecture, la ligne est tenue
ou pas. Si tu reponds « la moyenne des deux seins », la section 12 retombe a moitie le jour meme.
Je ne tranche pas a ta place.

---

## 2. TA SECTION 11 (allongee sur le ventre, seins pendants) : 4 LIGNES SUR 5 SONT DANS TES BANDES

    longueur racine-a-pointe  +18 a +26 %   mesure  +21,8 % et +21,0 %      DANS
    largeur                    -7 a -13 %   mesure   -10,8 % et  -9,6 %     DANS
    epaisseur                  -6 a -12 %   mesure    -7,8 % et  -8,5 %     DANS
    deplacement du centre     20 a 28 %     mesure    25,2 % et  25,5 %     DANS
                                            (avant :  32,1 % et  30,4 %, hors bande des deux cotes)

Il reste une ligne : ton « pic transitoire ~+30 % » pendant que ca s'installe. Je la mesure a
+31,6 % et +33,7 %, donc un peu au-dessus — mais sur un instrument qui a tendance a sur-estimer, et
je refuse de la declarer violee tant que je ne la lis pas correctement.

---

## 3. CE QUE J'AI CORRIGE, ET LA MOITIE ETAIT UNE ERREUR A MOI

**(a) Le moteur comptait deux fois le meme effet.** Quand elle est penchee et qu'elle le RESTE, ses
seins se deplacent — c'est ce que tes sections 10, 11 et 12 decrivent, avec leurs chiffres. Le
moteur produisait bien ce deplacement, puis il le reprenait une seconde fois pour en faire un
ETIREMENT de la chair, par-dessus, et dans une direction que tes sections ne prevoient pas. Mesure :
cet etirement valait exactement 0,43 fois le deplacement, et il etait **nul quand elle est debout**
— ce qui prouve que c'etait bien l'inclinaison qu'il comptait deux fois. Corrige : le canal ne
repond plus qu'a ce qui BOUGE, plus a ce qui est TENU. Sur les 16 mesures de forme de tes trois
sections, on passe de **6 a 13 dans tes bandes**.

**(b) Je mesurais tes formes sur le mauvais axe, et c'est moi qui l'avais casse hier.** Ta section 7
dit « +Y = vers le haut le long du TORSE ». Hier j'ai construit cet axe a partir de la direction
dans laquelle le sein pointe — or un sein pointe en avant ET vers le bas, donc mon axe penchait de
12 degres. L'axe du torse se mesure directement sur le squelette (hanches vers cou), et je l'ai
fait : trois facons de le mesurer donnent exactement la meme direction. Trois de tes lignes
changeaient de verdict a cause de mon erreur.

---

## 4. ET UNE CHOSE QUE J'AI PREDITE ET QUI ETAIT FAUSSE

J'avais annonce, en lisant le code, que ce changement ne pouvait PAS toucher aux positions — qu'il
n'agissait que sur la forme de la peau. J'ai fait tourner les deux versions cote a cote pour le
verifier, et **les positions bougent** (le mouvement de pointe baisse de 0,7 % et 3,2 %).

**J'ai trouve pourquoi, et c'est une chose que tu dois savoir.** La boule de collision de chaque
sein n'est pas posee sur l'os : elle est **decalee de 651 unites** (c'est comme ca qu'on lui fait
epouser la forme du sein). Or ce decalage est porte par la matrice de l'os — la meme dans laquelle
on ecrit la deformation de la chair. Resultat : **quand la chair se deforme, la boule de collision
se deplace avec elle, jusqu'a 30 % de son propre rayon** (104 unites pour une boule de 345). Et la
frame suivante s'en sert pour les contacts.

Ce n'est pas forcement un mal — c'est meme la direction de ce que tu demandes depuis le 11 aout
(« les colliders ne suivent pas les formes du mesh »). Mais ce n'est pas un choix : c'est un effet
de bord, il n'est ecrit nulle part, et il arrive avec **une frame de retard**. Je ne le touche pas
tout seul : garder ce comportement et l'assumer, ou le couper et faire suivre la boule par un
mecanisme explicite, c'est une decision, pas une correction.

Le controle, lui, est net : la version desarmee reproduit la course d'hier **bit pour bit**, sur
tous les enregistrements. Tout ce qui change vient donc du correctif et de rien d'autre.

---

**A TESTER : RIEN.** Une seule chose t'est demandee, et c'est une question sur ta spec : le sens de
« Global » dans ta section 12.

`OPEN-DEFECTS` : `breast-spec-incomplete` reste ouverte. Elle ne se ferme que quand tu le dis.
