# RIEN A TESTER DANS CE BUILD — MAIS JE DOIS TE RETIRER UN AUTRE CHIFFRE QUE JE T'AI DONNE

Branche `physics-keira-clean`. **Ce build ne change pas un bit de la physique.** Je n'ai ajoute
qu'une ligne de trace. Ne perds pas de temps dessus : je te le publie parce que tu m'as demande de
livrer au fil de l'eau.

Deux choses te reviennent. La premiere est une correction, la seconde est une question qui
n'appartient qu'a toi.

---

## 1. JE RETIRE LE « x1,85 ». LA POITRINE NE DEBORDE PAS DE 85 % PARTOUT, ET SURTOUT PAS DANS LE MEME SENS.

Je t'ai fait remonter que l'excursion de sa poitrine valait **« environ 1,85 fois ce que ta spec
autorise »**, que c'etait **un seul defaut exprime six fois**, et qu'en le divisant par 1,85 **six
sections de ta spec basculeraient ensemble**.

**Les trois affirmations sont fausses. Je les retire.**

Le 1,85 est un **maximum sur toute la course**, tous stimuli confondus, sur une seule ligne de ta
spec (la 22). Mais la ou ta spec attache une amplitude a un **geste precis** — une detente, une
reception, un freinage, un demi-tour, un buste en avant, une inclinaison laterale —, j'ai vingt
mesures, et elles ne disent pas la meme chose du tout :

    dans ta bande         4 mesures sur 20
    au-dessus            12 mesures sur 20    de 5 % a 64 % de trop  (jamais 85 %)
    **en dessous**        4 mesures sur 20    jusqu'a **trois fois trop peu**

**Un tiers des mesures de ta section 16 (l'atterrissage) manque sa bande PAR LE BAS.** Diviser
l'excursion, comme je te le proposais, les aurait rendues encore plus mortes.

Et le pire : **son sein gauche et son sein droit demandent des corrections en sens OPPOSE** sur
quatre des six sections. Sur le demi-tour rapide, le gauche bouge trop peu et le droit trop —
au meme instant, sous le meme geste. Aucun reglage commun ne peut satisfaire les deux. J'ai
balaye tous les facteurs possibles : **le meilleur imaginable n'en corrige que deux sur six**, et
celui que je te proposais (1,85) n'en corrige **aucune**.

Je n'ai pas trouve pourquoi les deux cotes se comportent a l'envers l'un de l'autre. J'ai teste
mon explication — la geometrie de sa pose — et **elle est fausse aussi**. Je ne t'en propose pas
une autre tant que je ne l'ai pas mesuree.

---

## 2. UNE QUESTION SUR TES ANIMATIONS, ET ELLE EST A TOI. TES ANIMATIONS SECOUENT SA POITRINE 2,5 FOIS PLUS FORT QUE LE GESTE LE PLUS VIOLENT DE TA PROPRE SPEC.

C'est le vrai resultat du cycle, et je ne l'attendais pas.

Ma salle de test peut la secouer avec cinq stimuli, du plus doux (1 g, la gravite) au plus brutal
(**39 g** — l'equivalent d'un crash). Elle joue aussi une sixieme fenetre **sans aucune secousse**,
ou seule son animation d'origine tourne.

Voila ce que ca donne sur le deplacement du bout de son sein :

    sans AUCUNE secousse, animation seule ......... 10 cm en median, jusqu'a 13 cm
    avec la secousse a 39 g ....................... +10 % seulement

**Ta ligne 22 plafonne ce deplacement a 7,3 cm.** Il est deja a 10 cm **quand on ne la secoue pas
du tout**. Et 100 % des animations depassent ta bande dans cette condition.

La cause est mesuree : **ses animations d'origine delivrent jusqu'a 7,85 g a sa poitrine**, la ou
le geste le plus dur que TA spec decrit — une reception dure apres un gros saut — vaut **3,11 g**.
Ses animations tapent **2,5 fois plus fort** que ce que ta spec considere comme le maximum.

**Et c'est la que j'ai besoin de toi, parce que les deux issues sont opposees et que je ne peux
pas choisir a ta place :**

  - **soit ces 7,85 g sont reels** — son torse bouge vraiment comme ca dans les animations de
    Naughty Dog — et alors la physique fait ce qu'il faut, c'est **ta bande de 7,3 cm qui est
    inatteignable tant qu'on joue ces animations telles quelles** ;
  - **soit ces 7,85 g sont un artefact** — un a-coup dans la facon dont on echantillonne
    l'animation, pas un vrai mouvement de torse — et alors c'est **a nous de le corriger**, et ta
    bande redevient atteignable.

Je sais comment trancher (regarder si le pic dure une seule image ou une dizaine), et je le ferai
au prochain cycle. Mais **si la reponse est la premiere**, c'est toi qui devras dire ce que tu
veux : une poitrine conforme a ta spec, ou une poitrine qui suit fidelement des animations qui la
secouent plus fort que ta spec ne l'envisage. **On ne peut pas avoir les deux.**

---

## 3. LA QUESTION DU CYCLE PRECEDENT TIENT TOUJOURS

Ta section 16 ecrit : « **Recommended soft ceiling** : MaxApexDisplacement ≈ 0.50 B0 ». Le mot est
**« soft »** — recommande, souple. Le moteur l'a implemente **dur** : il coupe net a 0,50, et la
bande que la meme section demande d'atteindre a l'atterrissage (42 a 50 %) est exactement celle ou
ce plafond se ferme. C'est ton appel, pas le mien.
