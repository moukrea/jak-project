# CE BUILD CHANGE OU LA PEAU DE SA POITRINE EST ACCROCHEE — PAS UN SEUL REGLAGE

Branche `physics-keira-clean`. **Aucun reglage de physique n'a bouge** : ni raideur, ni
amortissement, ni gravite, ni couplage. La preuve la plus nette est dans la mesure : les os de sa
poitrine bougent **exactement pareil**, au quatre-decimales pres, avant et apres. Ce qui a change,
c'est **quelle part de sa peau suit ces os** au lieu d'etre soudee a son torse.

## 1. JE ME CORRIGE SUR QUELQUE CHOSE QUE JE TE REPETE DEPUIS SIX CYCLES

Je t'ecrivais qu'un plafond bloquait le mouvement de sa poitrine et qu'**aucune physique ne
pourrait jamais l'atteindre**. Je le chiffrais a **x1.76**.

**C'ETAIT FAUX, et la faute etait dans mon propre outil.**

Quand je recalcule les poids de peau, j'applique le profil de ta section 30 : tres accroche au
thorax au fond, de plus en plus libre vers la pointe. **Je l'appliquais le long du mauvais axe** —
celui des deux os de la chaine, qui sur ce personnage est a **78 degres** de la direction
fond-du-sein -> pointe. Le profil etait donc parfait, installe presque perpendiculairement a la
direction ou il devait descendre. Resultat : **43 % de la pointe de son sein etait soudee au
torse**, et suivait son buste comme un bloc rigide.

Ce n'est pas une deduction. Le profil que mon outil imposait **predit 0.4314** d'ancrage a la
pointe ; j'en **mesure 0.4324** sur le mesh livre. 0,001 d'ecart : c'est bien lui l'auteur.

**Corrige.** La pointe passe de **43 % soudee a 6 %** (et de 41 % a 5 % sur l'autre sein). Les cinq
bandes de ta section 30 passent de **1 sur 5** a **5 sur 5** dans la bande, des deux cotes.

## 2. CE QUE TU DEVRAIS VOIR — ET CE QUI VA TE DEPLAIRE

**Ce qui devrait aller mieux :** sa poitrine bouge nettement plus, surtout la pointe. Et le bord ou
la peau passait de fixe a mobile devrait moins casser : les aretes qui cassaient a cet endroit
tombent de **15 a 5** et de **22 a 7**, et celles qui restent sont a la RACINE, la ou ta spec veut
justement que ce soit accroche.

**CE QUI VA TE DEPLAIRE, ET JE TE LE DIS AVANT QUE TU LE VOIES : MAINTENANT CA BOUGE TROP.**

Ta section 22 pose un plafond dur : deplacement de pointe **<= 42 %** en normal, **<= 50 %** en
exceptionnel. Mesure sur cette course :

    avant :  pic typique 0.40 / 0.41      maximum 0.54 / 0.56
    apres :  pic typique 0.69 / 0.70      maximum 0.92 / 0.96      -> x1.85 et x1.92 AU-DESSUS

Et **99 % des fenetres** depassent maintenant les 42 %. Pire, ta section 19 (le buste qui se penche)
etait **la seule section d'amplitude que je tenais** : ses quatre lectures etaient dans ta bande
0.30-0.40, elles sont maintenant a 0.58-0.64. **Elle repasse au rouge, et c'est ce cycle qui l'y a
mise.**

**CE QUE CA VEUT DIRE, ET C'EST LE VRAI RESULTAT DU CYCLE :** la soudure au torse **cachait** un
solveur trop nerveux. Elle divisait le mouvement de la pointe par 1,76 avant qu'il n'arrive a
l'ecran, et ca donnait des chiffres qui avaient l'air corrects. Maintenant que la peau suit, on
voit l'amplitude reelle que le solveur produit — et elle est presque deux fois ta limite.

**Le prochain chantier est donc de calmer le solveur, pas la peau.** Je ne toucherai pas aux
reglages sans te le dire, parce que c'est exactement le genre de curseur dont tu m'as dit qu'il ne
fallait pas le bouger a l'aveugle.

## 3. UNE QUESTION OUVERTE SUR TA SPEC — JE NE LA TRANCHE PAS A MA CONVENANCE

Tes sections 30 et 31 se contredisent legerement sur ce personnage, et je prefere te le demander
plutot que de choisir :

* la **30** donne cinq bandes d'ancrage (racine 90-100 %, arriere 55-85 %, milieu 25-55 %, distal
  5-30 %, pointe minimale). Les tenir toutes force la courbe d'ancrage a un exposant de **0,83**.
* la **31** demande une ponderation de deformation en **r^1.6 a 2.0**. Or un ancrage en
  `(1-r)^0.83` donne mecaniquement une mobilite en **r^1.16** — mesure : 1,158 et 1,118.

**Tenir tes cinq bandes INTERDIT ton exposant.** Les deux ne peuvent pas etre vraies ensemble ici.
Dis-moi laquelle des deux prime et j'applique ; en attendant je tiens les cinq bandes, parce
qu'elles sont chiffrees bande par bande alors que l'exposant est introduit par « a **useful**
deformation weighting is ».

## 4. CE QUI N'EST PAS REPARE, ET JE LE DIS AU LIEU DE LE TAIRE

* Le deuxieme os de chaque sein ne pilote **plus rien** de la pointe (poids 0,08 a gauche, **0,00**
  a droite). Corriger un axe d'ancrage ne deplace aucun os : pour que le deuxieme os serve, il
  faudrait le **deplacer**, et c'est un chantier de rig, pas de poids.
* `StrongRootFraction` de ta 30 reste hors bande sur le sein droit.
* La penetration mesuree au niveau des os n'a **pas bouge du tout** (0,1115 / 0,1019 m) : elle ne
  voit pas les poids de peau. Celle qui les voit a **baisse** de 4 % et 16 % — mais j'avais predit
  qu'elle monterait, donc **je ne revendique pas cette baisse**, je la declare inexpliquee.
* **Rien de tout ceci n'est valide par toi**, et aucun de ces chiffres ne devient une reference.

## 5. LES CHIFFRES, SI TU VEUX LES VERIFIER

Course de la salle, 31/31 animations, 2 chaines, 310 mesures, empreinte de trace
`50811803513d356c224c99d1fe68d3ec`. Mesh cuit `ec0658bf2f5a59fe88f3b23caff0f55d`.

    ce qui est MESURE                             avant        apres
    ancrage de la pointe (§30 veut « minimal »)   0.4324/0.4064  0.0598/0.0451
    cinq bandes d'ancrage de la §30 DANS           1/5 · 1/5      5/5 · 5/5
    deplacement de pointe, mediane sur 15 regimes    —          x1.68 (x1.42-1.86)
    §22 pic typique   (plafond dur 0.42)          0.3984/0.4134  0.6876/0.7003
    §22 maximum       (plafond dur 0.50)          0.5431/0.5553  0.9249/0.9592
    §19 flexion/retour (bande 0.30-0.40)          4 lectures DANS  4 lectures AU-DESSUS
    aretes cassees a la frontiere peau fixe/mobile  15 · 22        5 · 7
    penetration vue par les OS                    0.1115/0.1019  0.1115/0.1019  (identique)
    penetration vue par la PEAU                   0.1409/0.1426  0.1358/0.1203

**LE CONTROLE QUI REND TOUT CA ATTRIBUABLE, ET JE NE L'AVAIS PAS PREVU** : les mesures prises au
niveau des OS — amplitude de pointe, derive de racine, penetration, saut — sont **IDENTIQUES AU
QUATRIEME CHIFFRE** avant et apres, sur les cinq pilotages. Le solveur n'a donc bougé d'aucun
chiffre, et tout l'ecart ci-dessus est bien ce que la PEAU herite. C'est la meilleure attribution
qu'on ait eue sur ce chantier.

**ET UN CHIFFRE QUI S'EST DEGRADE, QUE JE NE CACHE PAS** : l'ecart entre les deux seins sur la
penetration vue par la peau passe de **1 % a 11 %**. C'est la mesure que j'utilise comme controle
d'erreur de mon propre instrument, donc elle est moins fiable qu'avant sur cette section.

---

*Aucune ligne de ce document n'est validee par toi. `TENUE` dans mon registre veut dire « ma mesure
est dans la bande », jamais « approuve ». Il n'y a jamais eu de validation de ta part sur aucune
section de la poitrine.*
