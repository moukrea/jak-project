# RIEN A TESTER — MAIS JE DOIS RETIRER CE QUE JE T'AI ENVOYE IL Y A UNE HEURE

Branche `physics-keira-clean`. **Ce build ne change pas un bit de la physique** : pas une ligne de
moteur, pas une donnee. Ne perds pas de temps dessus.

En echange, la mesure que je t'annoncais est faite — et **elle dit le contraire de ce que je
t'avais ecrit**.

---

## 1. JE RETIRE LE POINT 3 DE MON MESSAGE PRECEDENT. IL ETAIT FAUX.

Je t'ai ecrit, il y a une heure :

> « l'animation veut mettre sa poitrine quelque part, et la physique refuse de l'y suivre ; elle la
> tient au modele. Ces 5-6 cm sont les memes sur les 31 animations. »

**Non. Il n'y a pas de 5-6 cm entre l'animation et ton modele.** La position que l'animation
demande pour ses os de poitrine **est** celle de ton modele : **0,6 a 1,3 millimetre** d'ecart en
moyenne, **1,4 cm** au pire moment de toute la course.

Comment j'ai pu me tromper : j'avais compare **le pire instant** d'une grandeur a **la moyenne**
d'une autre. Les deux chiffres etaient justes ; les mettre cote a cote ne l'etait pas. C'est
exactement la faute que je m'etais interdite par ecrit il y a huit jours, et je l'ai commise quand
meme.

**Ce qui vaut 5 a 6 cm, c'est le mouvement que la PHYSIQUE produit, a son maximum.** Sa valeur
courante est 3 a 6 fois plus petite. Donc c'est bien un mouvement, pas un decalage fige — et le
defaut est bien celui que je decrivais avant hier soir : **elle bouge trop, pas trop peu.**

---

## 2. COMMENT JE L'AI VERIFIE, PARCE QUE CETTE FOIS J'AI PRIS LA PRECAUTION D'AVANCE

J'ai eteint la physique **d'un seul sein a la fois** et refait la course. Sur le sein eteint, la
position affichee est **exactement celle que l'animation demande** — plus rien d'autre ne l'ecrit.
Ensuite je compare avec la course normale.

Le controle qui rend ca valable : le sternum et la racine du corps ne sont simules par rien, donc
ils doivent etre **identiques** entre les deux courses. Ils le sont : **27 528 nombres compares,
zero different.** Sans ca je n'aurais rien publie.

Et j'ai compare a **ton modele 3D lui-meme**, pas a un intermediaire — par un chemin qui ne
reutilise aucun des outils qui avaient produit le chiffre precedent. C'est la double verification
que je m'etais imposee avant d'engager le travail sur les six points rouges d'amplitude. **Les deux
chemins sont d'accord.** Ces six points sont donc travaillables ; c'est ce qui debloque la suite.

---

## 3. UN FAIT NEUF SUR TES ANIMATEURS, ET IL EST JOLI

**Naughty Dog a anime sa poitrine.** Pas beaucoup — jusqu'a **1 centimetre** — mais c'est la, et
c'est concentre exactement ou on l'attendrait : les ralentis de respiration et d'appui.

    assistant-village2-idle-hut-breath   10,5 mm   <- la plus forte des 31
    assistant-idle-leaning-right          7,3 mm
    assistant-idle-leaning-left           4,7 mm
    ... et six autres idles, entre 2,7 et 4,8 mm
    les 22 autres animations                0 mm   (le canal ne bouge pas du tout)

**Aujourd'hui notre physique ecrase ce mouvement-la** : elle remplace la position de l'os par la
sienne, et sa cible de repos est relevee une seule fois au demarrage. Ta regle du 11 aout dit que
l'animation gagne sur ce qu'elle manipule explicitement — donc c'est un defaut, et il est a nous.

**Je ne le mets pas en tete de liste, et je te dis pourquoi** : il vaut 1 cm quand le mouvement que
la physique produit en vaut 7. Le corriger d'abord serait soigner le detail avant le probleme.

---

## 4. CE QUI T'APPARTIENT ENCORE, INCHANGE

  - Ta section 16 ecrit « **Recommended soft ceiling** : MaxApexDisplacement ~ 0.50 B0 ». Le mot est
    « soft » — recommande, souple. Je l'ai implemente **dur**. Dis-moi lequel des deux tu veux.
  - Le denominateur `B0`, la longueur de reference de tout le dossier. Ton texte est lisible de deux
    facons et le choix deplace quinze sections d'un coup. Je ne tranche pas a ta place.

---

**A TESTER : RIEN.** Je maintiens ce que je t'ai dit le 20 : tant qu'une seule section de ta spec
sur 38 est tenue, te demander de juger a l'oeil te coute plus que ca ne me rapporte. Le jour ou le
bloc qui gouverne ce que tu vois tiendra ensemble, je te le dirai et je te demanderai de regarder.

`OPEN-DEFECTS` : `breast-spec-incomplete` reste ouverte. Elle ne se ferme que quand tu le dis.
