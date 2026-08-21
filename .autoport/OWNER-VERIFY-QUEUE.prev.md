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

## 2. TES ANIMATIONS NE SONT PAS EN CAUSE. C'EST UN A-COUP D'UNE SEULE IMAGE, ET IL EST A NOUS.

J'avais commence a t'ecrire ici une question pour toi : « tes animations secouent sa poitrine
2,5 fois plus fort que le geste le plus violent de ta propre spec, choisis entre ta spec et tes
animations ». **J'ai mesure avant de te l'envoyer, et le dilemme n'existe pas. Je le retire.**

Ce que j'avais : la chaine recoit jusqu'a **7,85 g** sans qu'on la secoue. Ce que je n'avais pas :
d'ou ca vient. Je ne regardais que des os que la physique elle-meme deplace — donc je voyais sa
reponse, pas son entree. J'ai ajoute a la mesure l'os du **buste**, que la physique ne touche
jamais : lui, c'est ton animation pure.

**Trois choses en sortent, et elles renversent la question :**

  - **Le pic ne dure qu'UNE SEULE IMAGE.** Sur l'image d'avant et celle d'apres, l'acceleration
    est quasi nulle (1,3 % du pic). Sur la duree de la fenetre, la valeur habituelle vaut **0,01 g**
    et le pic **6 g** : un rapport de **750**. Aucun mouvement humain ne fait ca. Ce n'est pas une
    acceleration, c'est un **saut** dans la trajectoire.
  - **Son buste, lui, est parfaitement raisonnable.** En isolant le mouvement du TORSE seul, il ne
    depasse jamais **1,06 g** — bien en dessous des 3,11 g que ta spec envisage pour une reception
    dure. **Tes animations de torse sont dans les clous.**
  - **Le saut est dans le deplacement d'ENSEMBLE du personnage**, pas dans son buste : 76 a 86 %
    de ce que la poitrine encaisse vient de la racine du personnage qui change de vitesse d'un
    coup, en une image.

**Donc : rien a arbitrer de ton cote, et rien a changer a tes animations.** C'est un a-coup qu'on
laisse passer, et c'est a nous de le filtrer. Ta section 37 dit d'ailleurs exactement ca —
« artificial transforms must not generate physical breast impulses » — et le mecanisme existe deja
chez nous : il attrape bien les teleportations (167 a 258 cm, il tire a chaque fois). Mais les
a-coups qui font le degat valent **0,7 a 1,0 cm** : ils sont cent a mille fois plus petits que ce
qu'il surveille, et ils passent dessous. **C'est ca, le prochain travail.**

Et ca change ce que je t'annonce sur sa poitrine : le depassement de ta section 22 n'est **pas**
une fatalite de tes animations. Une fois cet a-coup filtre, la bande que tu demandes redevient un
objectif atteignable.

## 3. LA QUESTION DU CYCLE PRECEDENT TIENT TOUJOURS

Ta section 16 ecrit : « **Recommended soft ceiling** : MaxApexDisplacement ≈ 0.50 B0 ». Le mot est
**« soft »** — recommande, souple. Le moteur l'a implemente **dur** : il coupe net a 0,50, et la
bande que la meme section demande d'atteindre a l'atterrissage (42 a 50 %) est exactement celle ou
ce plafond se ferme. C'est ton appel, pas le mien.
