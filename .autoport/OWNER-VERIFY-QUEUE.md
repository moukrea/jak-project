# RIEN A TESTER — MAIS IL N'Y A PLUS UNE SEULE LIGNE DE TA SPEC SANS VERDICT

Branche `physics-keira-clean`. **Ce build ne change pas un bit de la physique** : pas une ligne de
moteur, pas une donnee. Ne perds pas de temps dessus. Ce qui a change, c'est ce que je SAIS.

---

## 1. LES 38 SECTIONS DE TA SPEC PORTENT MAINTENANT TOUTES UN VERDICT

Il y a deux jours il en restait une que je ne savais pas juger — la 10, celle qui decrit ce qui
doit se passer **quand elle est allongee sur le dos**. Elle est jugee, et la reponse est non.

    ta ligne  « le sein migre vers l'exterieur de 4 a 10 % de sa largeur »
    mesure    sein gauche  +2,3 %      -> deux fois trop peu
              sein droit   -2,0 %      -> il part dans l'AUTRE SENS, il rentre

Et une deuxieme ligne de la meme section, que je lisais mal jusqu'ici :

    ta ligne  « la projection vers l'avant se reduit de 25 a 35 % »
    mesure    elle se reduit de 18 % a gauche, 20 % a droite -> pas assez ecrase

Etat complet : **1 section tenue, 5 tenues par construction, 21 partielles, 11 non tenues, 0
inconnue.** Ce qui compte dans cette ligne, c'est le dernier chiffre. Depuis le 20 aout j'avancais
en transformant des inconnues en verdicts — c'etait du progres reel, mais **cette source est
epuisee**. Il ne reste plus que le vrai travail : faire passer des rouges au vert. Il n'a pas
commence.

---

## 2. POURQUOI JE NE VOYAIS PAS LA 10, ET C'EST UNE FAUTE D'INSTRUMENT

Ta section dit « migration vers **l'exterieur** » et « deplacement vers **le thorax** ». Ce sont
des DIRECTIONS. Mon instrument, lui, publiait une DISTANCE — juste la longueur du deplacement,
sans son sens. Une longueur est toujours plus grande qu'une direction, et surtout **elle ne voit
pas le signe** : un sein qui rentre vers le milieu du corps y donnait exactement le meme chiffre
qu'un sein qui sort. C'est ce qui a cache le probleme du sein droit pendant 25 cycles.

Corrige : je mesure maintenant la projection sur les axes que ton personnage porte reellement
(mesures sur son squelette, pas choisis par moi — les deux cotes sortent exactement opposes, et
l'axe « avant » des deux seins coincide a 0,02 degre, ce qui prouve que je le mesure et ne
l'invente pas).

---

## 3. LE FAIT INTERESSANT, ET IL EST A L'ENVERS

En decomposant le deplacement en deux parts — ce que font les OS, et ce que fait la PEAU :

    sein gauche   os -1,0 %   peau +3,3 %   total +2,3 %
    sein droit    os -4,3 %   peau +2,3 %   total -2,0 %

**La peau pousse le sein vers l'exterieur, et les os le tirent vers l'interieur.** Les deux
s'annulent presque. Le mouvement que ta spec decrit existe bien dans le moteur, mais il est
defait par la chaine d'os avant d'arriver a l'ecran. Ce n'est pas un reglage a monter : c'est
deux mecanismes qui se combattent.

---

## 4. DEUX CHOSES QUE JE RETIRE

**(a) Ce que je t'ai dit hier soir sur les seins qui « ne peuvent pas etre corriges par une
rotation » etait faux.** J'avais ecrit qu'une rotation deplace le sein perpendiculairement, donc
qu'elle ne peut agir que sur 9 a 15 % du probleme. C'est une erreur de geometrie elementaire : une
rotation sur un vrai angle (pas un angle infiniment petit) agit tres largement dans la direction
que je disais inaccessible. Verifie a la main, puis mesure : il y a dans le mouvement actuel une
rotation d'**au moins 33 a 37 degres**, et c'est elle qui produit la majeure partie du
depassement — pas la translation, qui est trop petite, ni l'etirement, qui est bloque a 1,7 %.

Ca ne veut pas dire que la correction que j'avais essayee marche : elle a ete essayee, mesuree, et
elle a AGGRAVE le probleme. Ce qui tombe, c'est l'explication que j'en avais donnee.

**(b) Un nombre dont je me servais depuis un mois n'avait aucun producteur.** La largeur de
reference du sein (18,95 cm) etait ecrite dans mes notes et **nulle part dans le code** : aucun
script ne la calculait, aucune trace ne la portait. Je l'ai recalculee : elle tombe exactement sur
le meme chiffre, identique sur les deux seins et stable quelle que soit la facon de decouper
l'organe. Elle est juste — mais elle etait un souvenir, pas une mesure, et maintenant elle est
produite a chaque course.

---

## 5. UNE CHOSE QUE J'AVAIS OUBLIEE PENDANT 30 CYCLES, ET QUI EST A MOI

Le 20 aout j'avais ecrit noir sur blanc qu'il fallait corriger, au cycle suivant, le fait que
**le deuxieme os du sein droit ne pilote AUCUNE des pointes de chair** (poids exactement 0,0000).
Autrement dit : tout ce que je mesure sur la pointe du sein droit depuis un mois decrit **un seul
os**, pas la chaine. Je l'avais ecrit avec la mention « surtout pas l'oubli », et je l'ai oublie
30 cycles. C'est retrouve, chiffre, et c'est le prochain chantier evident — c'est un travail de
maillage, pas de reglage.

---

**A TESTER : RIEN.** Le moteur n'a pas bouge. Et je maintiens ce que je t'ai dit le 20 : tant
qu'une seule section sur 38 est tenue, te demander de juger a l'oeil te coute plus que ca ne me
rapporte. Le jour ou le bloc qui gouverne ce que tu vois tiendra ensemble, je te le dirai et je te
demanderai de regarder.

`OPEN-DEFECTS` : `breast-spec-incomplete` reste ouverte. Elle ne se ferme que quand tu le dis.
