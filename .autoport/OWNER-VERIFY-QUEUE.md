# RIEN A TESTER DANS CE BUILD — MAIS JE DOIS TE RETIRER CE QUE JE T'AI DIT HIER SOIR

Branche `physics-keira-clean`. **Ce build ne change pas un bit de la physique** : pas une ligne de
moteur, pas une donnee. Ne perds pas de temps dessus.

En echange j'ai un fait neuf, et il est plus utile que tout ce que je t'ai envoye cette semaine.

---

## 1. JE RETIRE CE QUE JE T'AI ECRIT HIER SOIR SUR SES ANIMATIONS

Je t'ai dit deux choses hier soir, et **les deux sont a corriger**.

**(a) « Tes animations ne secouent son torse qu'a 1,06 g au plus. »** Faux — ou plutot incomplet,
ce qui revient au meme. Je mesurais le torse **en translation seulement**. Mais sa poitrine n'est
pas accrochee au centre du torse : elle est au bout d'un bras de levier, et quand le torse
**tourne**, le bout du levier prend beaucoup plus que le centre. En comptant la rotation, l'entree
reelle monte a **7,65 g**. Ma mesure ne pouvait pas la voir.

**(b) « Il reste juste a filtrer un a-coup d'une image et la cible redevient atteignable. »**
Faux aussi, et c'est le plus important. **Cet a-coup ne produit pas ce que tu vois.** Je l'ai
verifie en appariant les 31 animations une a une : l'a-coup pilote mon compteur d'entree presque
parfaitement (0,96 sur 1), et le mouvement de sa poitrine **pas du tout** (-0,04). Les animations
qui n'ont aucun a-coup ont meme une poitrine qui s'ecarte **davantage** que celles qui en ont un.

Si je l'avais filtre comme je te l'annoncais, **tu n'aurais rien vu changer a l'ecran.**

---

## 2. LE FAIT NEUF, ET IL EXPLIQUE MIEUX CE QUE TU DECRIS DEPUIS DEUX SEMAINES

**Sa poitrine est deja a 10 a 13 cm de la position que l'artiste a dessinee QUAND ELLE NE BOUGE
PAS.**

Ce n'est pas une phrase en l'air, c'est la mesure. J'ai isole les animations ou son corps est
reellement immobile — trois criteres a la fois : il ne se deplace pas (0,03 mm par image), il ne
tourne pas (0,015 degre par image), il n'accelere pas. Il en reste cinq. Sur ces cinq :

    huit mesures sur dix depassent DEJA le plafond maximum de ta spec
    et le pire ecart de toute la course — 12,9 cm, pour un plafond de 7,3 cm —
    tombe sur l'animation ou elle est LA PLUS IMMOBILE des trente et une.

Puis j'ai multiplie l'entree par **380** — de « immobile » a « choc violent ». Resultat :
**l'ecart ne bouge pas.** Il baisse meme de 4 %.

**Donc ce n'est pas un ballotement excessif.** Et en creusant j'ai trouve mieux — voir le point 3,
qui corrige ce que je viens d'ecrire. Ca colle beaucoup mieux a ce que tu me dis
depuis le 13 — « ca suit aucune logique », « c'est du pudding » — qu'une sur-reaction aux gestes :
un pudding ne reagit pas trop fort, il **se tient mal**.

**Et ca veut dire que j'ai passe plusieurs cycles a chasser la mauvaise chose.** Tout le chantier
depuis une semaine visait a calmer sa reaction au mouvement. La reaction au mouvement n'est pas le
probleme — le probleme est la ou elle se pose quand il n'y a pas de mouvement du tout.

J'ai verifie que ce n'etait pas mon instrument qui se trompait de reference (c'etait l'explication
la plus commode) : il compare bien a la pose de l'artiste de la meme image, je l'ai relu dans le
code. **L'ecart est reel.**

---

## 3. ET EN FAIT C'EST L'INVERSE DE CE QUE JE CROYAIS — JE ME CORRIGE UNE DEUXIEME FOIS

J'ai d'abord conclu « sa poitrine ne revient pas ou l'artiste l'a mise ». **Puis j'ai compare au
modele 3D livre lui-meme, et c'est faux : elle y revient a 8 millimetres pres.** L'os de poitrine
se repose exactement la ou ton modele le place.

Ce que mon chiffre mesurait, c'est **l'ecart entre le modele et ce que l'ANIMATION demande** — et
il vaut 5 a 6 cm, **le meme sur les 31 animations**. Autrement dit : l'animation veut mettre sa
poitrine quelque part, et **la physique refuse de l'y suivre** ; elle la tient au modele.

**Ca renverse completement le diagnostic.** Depuis dix jours je cherche a la faire bouger MOINS.
La mesure dit qu'elle bouge TROP PEU la ou l'animation lui demande de bouger — ce qui ressemble
beaucoup plus a ce que tu me dis depuis le debut (« trop statiques », « aucune physique quand
elle soude ») qu'a une sur-reaction.

**Il me reste une question a trancher avant de toucher a quoi que ce soit**, et elle est a une
mesure : ces 5-6 cm sont-ils une vraie intention des animateurs de Naughty Dog, ou une constante
parasite introduite quand on transpose leurs animations sur le squelette HD ? **Les deux
demandent des corrections opposees** — dans un cas il faut suivre l'animation, dans l'autre
surtout pas. Je ne bouge pas tant que je ne l'ai pas mesure.

---

## 4. CE QUI T'APPARTIENT ENCORE, INCHANGE

  - Ta section 16 ecrit « **Recommended soft ceiling** : MaxApexDisplacement ≈ 0.50 B0 ». Le mot
    est « soft » — recommande, souple. Je l'ai implemente **dur**. Dis-moi lequel des deux tu veux.
  - Le denominateur `B0`, la longueur de reference de tout le dossier. Ton texte est lisible de
    deux facons et le choix deplace quinze sections d'un coup. Je ne tranche pas a ta place.

---

**A TESTER : RIEN.** Et je maintiens ce que je t'ai dit le 20 : tant qu'une seule section de ta
spec sur 38 est tenue, te demander de juger a l'oeil te coute plus que ca ne me rapporte. Le jour
ou le bloc qui gouverne ce que tu vois tiendra ensemble, je te le dirai et je te demanderai de
regarder.

`OPEN-DEFECTS` : `breast-spec-incomplete` reste ouverte. Elle ne se ferme que quand tu le dis.
