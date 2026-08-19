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

La reparation est connue et chiffree : **glisser l'articulation racine vers l'interieur de sa
chair**, pour que le segment simule couvre sa poitrine du debut a la fin. Ca touche son squelette
et ca demande une recuisson du maillage. Tu m'as autorise a modifier le rig ; **je ne l'ai pas
lance en fin de cycle a l'aveugle**, parce que cette operation ecrase des fichiers qui ne se
reconstruisent qu'en recuisant, et je veux d'abord pouvoir predire son effet sur l'ancrage de ta
section 30 (celui que tu m'as fait reprendre trois fois). C'est le chantier du prochain cycle.

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

## 4. CE QUI RESTE ROUGE, ET NE SE CACHE PAS

* **Sa poitrine traverse toujours son thorax** : 0,095 m et 0,089 m contre un plafond de 0,0005.
  En baisse de 3 % et 1 % — donc quasiment rien.
* **L'excursion reste hors limite 100 % du temps.** Porteur inconnu (voir 3b).
* **Ta SPEC 35 (son debardeur ne doit rien faire) reste absente** — elle demande une recuisson.
* **Sa SPEC 33 (qu'ils s'entrechoquent) reste hors de portee du test** actuel.
* **Un defaut neuf, mesure, non corrige** : environ un tiers de l'etirement demande a sa chair
  est un artefact de calcul (une cible figee comparee a un axe qui tourne), pas de la physique.

## 5. CE QUE JE TE DEMANDE DE REGARDER

1. **Se deforme-t-elle trop peu maintenant ?** C'est la question du cycle. Si oui, la reponse
   n'est pas de relacher le frein — c'est de rallonger le segment simule (point 2).
2. **Bouge-t-elle toujours autant qu'avant ?** Ma mesure dit oui. Si ton oeil dit non, ma mesure
   rate quelque chose et je veux le savoir.
