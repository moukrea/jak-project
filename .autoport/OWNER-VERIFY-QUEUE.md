# RIEN A TESTER DANS CE BUILD — MAIS JE DOIS TE RETIRER UN CHIFFRE QUE JE T'AI DONNE

Branche `physics-keira-clean`. **Ce build ne change pas un bit de la physique.** Il est identique
au precedent pour tout ce qui se voit. Ne perds pas de temps dessus : je te le publie parce que tu
m'as demande de livrer au fil de l'eau, pas parce qu'il y a quelque chose a regarder.

Deux choses te reviennent quand meme, et la premiere est une correction.

---

## 1. JE RETIRE LE « UN SEPTIEME ». C'ETAIT MON INSTRUMENT, PAS SA POITRINE.

Je t'ai ecrit au cycle precedent, mot pour mot :

> « Quand elle retombe d'un saut, sa poitrine rend entre un septieme et un quart du mouvement que
> sa propre elasticite devrait produire. »

**C'est faux. Je le retire.**

Ce que j'avais fait : je comparais ce que le moteur produit a ce que produirait un ressort **sans
aucun plafond**. Or le moteur en a deux, et ils sont armes en permanence — le plafond de ta
section 22 (50 % de B0) et la contrainte qui empeche l'os de s'allonger. Comparer une sortie qui
tape dans son plafond a un modele qui n'en a pas fabrique un facteur qui n'existe pas.

**Refait correctement, avec les memes plafonds que le code, sans aucun reglage ajuste pour que ca
tombe juste : le solveur rend en mediane 96 % de ce que sa propre mecanique implique**, sur les
huit regimes (detente, vol, reception, course), sur deux mesures independantes.

Et je ne me suis pas contente d'un calcul. **J'ai desarme en vrai le plus gros frein interne** et
rejoue toute la salle : le mouvement ne monte que de **16 % en mediane**, au mieux 84 %. Pas x7.

**Donc : il n'y a pas de mouvement qui se perd quelque part dans le moteur.** Quatre cycles l'ont
cherche (70, 71, 76, 77). Il n'y a rien a trouver. C'est une piste morte, et c'est moi qui l'avais
ouverte.

---

## 2. UNE QUESTION SUR TA SPEC — ET C'EST TOI QUI DOIS TRANCHER, PAS MOI

Ce qui limite vraiment sa poitrine, c'est un **plafond**, et il vient de ta propre spec.

Ta **section 22** dit : deplacement de pointe **<= 42 %** de B0 en normal, **<= 50 %** en
exceptionnel. Le moteur l'applique : au-dela de 42 % il raidit, et a 49,9 % il se ferme.

Ta **section 16** (atterrissage) dit, mot pour mot :

        Strong landing apex:       30-42% B0
        Very hard / exceptional:   42-50% B0

**La bande que ta section 16 demande d'atteindre a l'atterrissage est exactement celle ou le
plafond de ta section 22 se ferme.** Les deux lignes sont dans ton fichier, elles sont coherentes
sur le papier (l'une dit « jusqu'a », l'autre dit « va jusque-la »), mais dans un solveur ca veut
dire que la reception vit en permanence contre la butee. C'est mecaniquement pourquoi §14 a §20
restent sous leurs bandes.

**Ce que je ne fais pas :** je ne touche pas a tes chiffres. Tu m'as dit « la spec ne bouge pas ».
**Ce que je te demande :** est-ce que le plafond de 50 % doit etre une **butee dure** (ce qu'il est
aujourd'hui), ou une **limite molle** qu'un atterrissage tres dur a le droit de frôler et de
depasser brievement ? Ta section 16 ecrit d'ailleurs « **Recommended soft ceiling** » — le mot est
« soft », et le moteur l'a implemente dur. C'est peut-etre la toute la reponse, mais c'est ton
appel, pas le mien.

---

## 3. UN DETAIL QUI EXPLIQUE POURQUOI LES SAUTS RENDENT MOINS QUE LA COURSE

Mesure neuve, prise sur le maillage livre : l'os qui porte son sein part de son torse et monte
**presque a la verticale** — 23 degres seulement de la verticale.

Comme cet os ne peut pas s'allonger, le sein **pivote** autour de son attache. Et un pendule ne
reagit qu'a ce qui le pousse **de cote**, pas a ce qui le pousse le long de son propre axe.

    saut / atterrissage (ca pousse vers le haut)  ->  **39 %** seulement de la poussee est utile
    course / freinage   (ca pousse vers l'avant)  ->  **99 %** de la poussee est utile

Ce n'est pas un bug, c'est ou l'os est place dans le rig. Ca veut dire que si tu veux plus de
reaction **au saut** precisement, ca ne se gagnera pas en reglant le solveur.

---

## CE QUE TU DOIS FAIRE : RIEN

Pas de test demande. Le build est la si tu le veux, il est identique au precedent a l'oeil.
`breast-spec-incomplete` reste ouverte, et elle ne se ferme que quand **tu** dis que c'est bon.
