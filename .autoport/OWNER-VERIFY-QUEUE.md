> # DEUX CORRECTIONS AVANT TOUT LE RESTE — CE DOCUMENT PORTAIT DEUX CHIFFRES FAUX DE MOI
>
> Ce document date du 2026-08-19 14:45. Deux choses que je t'y ai ecrites ont ete reconnues
> fausses le soir meme, et **je ne les avais pas corrigees ICI** — donc tu as pu les relire
> depuis. Je les corrige en tete, pas en note de bas de page.
>
> **1. « un segment de 14 cm dans un organe de 73 cm » est FAUX d'un facteur 4.** J'avais divise
> les unites du moteur par 10 au lieu de **4096** (4096 unites = 1 metre). Les vraies longueurs
> sont **3,4 cm de chair simulee dans un organe de 17,9 cm**. Le RAPPORT que j'en tirais — 19 %
> de l'organe est simule, 81 % suivent sans participer — **est juste et ne bouge pas** ; ce sont
> les deux longueurs affichees qui etaient absurdes. Tu l'as vu tout de suite, et tu avais raison.
>
> **2. « ta section 22 voudrait 21-25 % » AU NIVEAU DE L'ORGANE : cette ligne n'existe pas dans
> ta spec.** Verifie mot pour mot : sa §22 ecrit « **Local** tissue elongation: common 5-15%,
> large 15-21%, exceptional 21-25% » et « Absolute stretch clamp: 25% ». Les deux sont **LOCALES**.
> J'avais multiplie un plafond LOCAL par la longueur de l'ORGANE, ce qui est un changement de
> denominateur, et j'en avais deduit qu'il fallait multiplier par 5,2 la chair simulee. **Cette
> conclusion est retiree.** Pire, elle allait contre ta propre spec, qui dit en gras a la meme
> section : « Large apex displacement shall **not** imply equally large tissue extension. »
>
> **Ce qui reste vrai dans ce document** : le correctif d'etirement du 19/08 (de ~30 % a 5,5 %),
> le fait que 19 % seulement de l'organe est simule, et le point 3b (« prendre une grosse part du
> budget ne veut pas dire etre la cause »).
>
> **Et ce que les cycles 49 a 56 ont change pour TOI : rien.** Ils ont tous porte sur la MESURE —
> jouer des regimes jamais joues, corriger des instruments, epingler des poses. **Aucune valeur
> livree n'a bouge depuis ce document.** Il n'y a donc rien de neuf a regarder de ton cote, et je
> prefere te le dire que te faire chercher une difference qui n'existe pas.

# CE BUILD CHANGE UNE CHOSE, ET UNE SEULE — DIS-MOI SI TU LA VOIS

Branche `physics-keira-clean`. **Sa poitrine devrait se DEFORMER moins qu'avant. Elle devrait
BOUGER exactement pareil.** C'est mesure : le mouvement varie de +0,3 % et +3,4 % (donc rien),
l'etirement de la chair passe d'environ 30 % a 5,5 % de la taille de l'organe.

Si tu vois autre chose changer, c'est une information importante et inattendue — dis-le-moi.

---

## 1. CE QUE J'AI TROUVE, ET C'EST UNE HISTOIRE DE METRE

Ta spec fixe deux sortes de limites, et elles ne se mesurent pas pareil :
* des **deplacements**, en fraction de la taille de sa poitrine ;
* un **etirement de tissu**, en POURCENT — et un pourcent se rapporte a la longueur de la piece
  qu'on etire, pas a la taille de tout l'organe.

Le moteur utilisait la taille de l'organe pour les deux. Resultat, mesure : la seule piece de
chair que le moteur simule vraiment est un segment de **14 cm** dans un organe de **73 cm**, et
on lui demandait de s'etirer de **128 %** de sa propre longueur — cinq fois ce que ta spec
autorise. La limite censee l'en empecher valait **171 %** de la longueur de la piece : elle ne
pouvait rien retenir.

**Corrige, en un seul terme.** L'etirement livre est maintenant a **23,6 % et 23,3 %** pour un
plafond de 25 %. **C'est la premiere fois que cette ligne de ta spec est tenue.**

## 2. ET J'AI TROUVE PIRE, QUE JE NE PEUX PAS REPARER SANS TOUCHER AU SQUELETTE

Le segment de chair simule ne couvre que **19 %** de sa poitrine. Les 81 % restants n'ont
**aucune articulation** — ils suivent, ils ne participent pas.

Ca cree une contradiction dont on ne sort pas par un reglage. Pour que sa poitrine s'etire autant
que ta spec l'autorise (25 %), il faudrait faire passer tout cet etirement par un segment cinq
fois trop court. Soit on viole ta limite locale d'un facteur 5 (c'etait l'etat d'avant), soit on
etire trop peu (c'est l'etat de ce build). **Il n'y a pas de troisieme valeur.** Le facteur qui
manque est **x5,2**.

J'ai ecrit d'abord que la reparation serait de **glisser l'articulation racine vers l'interieur
de sa chair**. **J'ai construit l'outil qui verifie ca avant de cuire, et il dit que je me
trompais** — je te le raconte au point 3c.

## 3. JE ME CORRIGE SUR DEUX CHOSES QUE JE T'AI DITES HIER

**(a) « Sa poitrine repond presque pareil a une secousse et a un mouvement doux. »** C'etait
FAUX, et c'est ma mesure qui etait mal decoupee : j'avais regarde uniquement les moments ou le
frein etait deja a fond. Sur l'ensemble des mouvements, la reponse varie de **68 % et 75 %**.
**Elle repond bien.** Le « pudding » que tu decris ne vient pas de la.

**(b) « J'ai trouve le frein qui porte le defaut, il en prend 73-75 %. »** Le chiffre etait juste,
la conclusion etait fausse. J'ai retire **81 %** de ce que ce frein laisse passer : le
depassement que tu m'as demande de corriger **n'a pas bouge d'un pouce** (100 % du temps hors
limite avant, 100 % apres). Prendre une grosse part du budget ne veut pas dire etre la cause.
**Je ne sais donc toujours pas ce qui porte ce depassement**, et je le dis plutot que de te
resservir une explication.

**(c) « Il suffira de glisser l'articulation vers l'interieur de sa chair. » — DIT IL Y A UNE
HEURE, ET DEJA FAUX.** Avant de lancer cette operation j'ai bati l'outil qui en predit le
resultat sans rien cuire. Il m'apprend que **ta section 30 l'interdit** : le profil d'ancrage que
tu as ecrit donne au thorax plus de la moitie de la chair sur toute la moitie arriere du sein.
Une articulation posee la-dedans ne pilote **aucun** sommet — c'est exactement le defaut « l'os
est pose mais il ne bouge rien » que tu m'as fait reprendre trois fois. **J'allais le cuire.**

## 4. CE QUI RESTE ROUGE, ET NE SE CACHE PAS

* **Sa poitrine traverse toujours son thorax** : 0,095 m et 0,089 m contre un plafond de 0,0005.
  En baisse de 3 % et 1 % — donc quasiment rien.
* **L'excursion reste hors limite 100 % du temps.** Porteur inconnu (voir 3b).
* **Ta SPEC 35 (son debardeur ne doit rien faire) reste absente** — elle demande une recuisson.
* **Sa SPEC 33 (qu'ils s'entrechoquent) reste hors de portee du test** actuel.
* **Un defaut neuf, mesure, non corrige** : environ un tiers de l'etirement demande a sa chair
  est un artefact de calcul (une cible figee comparee a un axe qui tourne), pas de la physique.

## 4bis. CE QUI EST PRET, ET C'EST UN CHOIX QUI T'APPARTIENT

L'outil a quand meme trouve le meilleur placement possible. Il fait passer la deformation livree
de **4,8 %** a **9,0 %** de la taille de l'organe — soit **presque le double**, et ca la sort du
sous-plancher pour la mettre dans la bande « courante » de ta spec.

~~Mais il ne peut pas aller plus haut : ta section 22 voudrait 21-25 %, et ta section 30 plafonne
le segment pilotable a ~37 % de l'organe. Les deux sections ne sont pas satisfiables ensemble.~~

**CE PARAGRAPHE EST RETIRE — voir la correction 2 en tete.** Il opposait deux de tes sections l'une
a l'autre sur la foi d'une ligne que ta §22 **ne contient pas** : ses deux lignes d'elongation sont
**LOCALES** (« **Local** tissue elongation… », « Absolute stretch clamp: 25% »), pas au niveau de
l'organe. Il n'y a donc **aucune contradiction** entre ta §22 et ta §30, et la question ci-dessous
reposait sur une contradiction que j'avais fabriquee.

> **Veux-tu que je cuise ce placement (x1,8 sur la deformation) ?** C'est un arbitrage de qualite,
> donc le tien. Un mot et je le construis.

## 5. CE QUE JE TE DEMANDE DE REGARDER

1. **Se deforme-t-elle trop peu maintenant ?** C'est la question du cycle. Si oui, la reponse
   n'est pas de relacher le frein — c'est de rallonger le segment simule (point 2).
2. **Bouge-t-elle toujours autant qu'avant ?** Ma mesure dit oui. Si ton oeil dit non, ma mesure
   rate quelque chose et je veux le savoir.
