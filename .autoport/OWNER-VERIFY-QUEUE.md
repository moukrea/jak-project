# RIEN A TESTER — MAIS J'AI UNE QUESTION SUR TA SPEC, ET DEUX CHOSES A TE DIRE

Branche `physics-keira-clean`. **Ces deux cycles ne changent pas un bit de la physique** : pas une
ligne de moteur, pas une donnee. Ne perds pas de temps a tester.

---

## 1. MA QUESTION, ET C'EST LA SEULE CHOSE QUE JE TE DEMANDE

Dans ta section 12 (elle est couchee sur le cote) tu ecris trois lignes. La premiere est :

> **Global lateral COM response: 15-24% B0, nominal 19%**

**Je ne sais pas ce que « Global » veut dire ici**, et les trois facons de le lire ne donnent pas
le meme resultat :

  - la reponse laterale de **chaque sein** pris separement  -> entre 0,006 et 0,163 (bande 0,15-0,24)
  - la **moyenne des deux** a chaque pose                   -> 0,102 et 0,077, donc SOUS
  - la **longueur totale** du deplacement de chaque sein    -> entre 0,042 et 0,187

Selon la lecture, ta ligne est tenue ou pas. Je ne tranche pas a ta place — dis-moi laquelle tu
avais en tete et je la mesure.

---

## 2. LES 38 SECTIONS DE TA SPEC PORTENT MAINTENANT TOUTES UN VERDICT

La derniere qui restait sans reponse — la 10, allongee sur le dos — est jugee, et c'est non.

    ta ligne  « le sein migre vers l'exterieur de 4 a 10 % de sa largeur »
    mesure    sein gauche  +2,0 %      -> deux fois trop peu
              sein droit   -1,7 %      -> il part dans l'AUTRE SENS, il rentre

    ta ligne  « la projection vers l'avant se reduit de 25 a 35 % »
    mesure    elle se reduit de 13 % a gauche, 12 % a droite  -> pas assez ecrase

    ta ligne  « le volume vertical augmente de 5 a 12 % »
    mesure    +0,4 % a gauche, +4,3 % a droite                -> pas assez non plus

Etat complet : **1 section tenue, 5 tenues par construction, 21 partielles, 11 non tenues, 0
inconnue.** Le dernier chiffre est celui qui compte. Depuis dix jours j'avancais en transformant
des inconnues en verdicts ; **cette source est epuisee**, et le vrai travail — faire passer des
rouges au vert — n'a pas commence.

---

## 3. J'AI TROUVE POURQUOI TANT DE TES LIGNES DE FORME SONT ROUGES, ET C'EST ENCOURAGEANT

Le moteur calcule d'abord la forme d'equilibre que tes sections 10, 11 et 12 decrivent — et **il
la calcule BIEN** : sur les 16 mesures de forme de ces trois sections, **13 tombent dans tes
bandes**.

Puis il applique deux corrections par-dessus (l'etirement quand ca bouge vite, l'ecrasement au
contact). Ces deux-la ne gonflent rien — elles conservent le volume exactement — mais elles
**defont** l'equilibre : apres elles, il ne reste que **8 mesures sur 16** dans tes bandes.

Autrement dit : ce que tu decris est deja produit, puis efface en aval. C'est la piste la plus
large que j'aie, et c'est la prochaine que j'attaque.

---

## 4. DEUX ERREURS DE MESURE QUE JE CORRIGE, ET ELLES SONT A MOI

**(a) Je mesurais ta section 12 sur le mauvais sein.** Sa premiere phrase dit que le sein du
DESSOUS s'ecrase et que celui du DESSUS migre vers le milieu. Ce sont donc deux lignes qui parlent
chacune d'UN sein — et je les lisais sur les deux. Corrige : le role (dessus / dessous) est
maintenant deduit de la direction de la gravite mesuree, pas d'une etiquette.

**(b) Je mesurais les formes le long des axes du squelette, pas ceux que ta spec definit.** Il y a
**12 degres** entre les deux. Sur les 16 mesures de forme, **5 changent de verdict** une fois
corrige — dont deux qui deviennent bonnes et deux qui deviennent mauvaises. Les deux lectures sont
publiees cote a cote pour que la difference soit visible.

---

## 5. ET UNE CHOSE QUE J'AVAIS OUBLIEE PENDANT 30 CYCLES

Le 20 aout j'avais ecrit qu'il fallait corriger, au cycle suivant, le fait que **le deuxieme os du
sein droit ne pilote AUCUNE des pointes de chair** (poids exactement zero). Tout ce que je mesure
sur la pointe du sein droit depuis un mois decrit donc **un seul os**, pas la chaine. Je l'avais
ecrit avec la mention « surtout pas l'oubli », et je l'ai oublie. C'est retrouve, chiffre, et
verifie : ce n'est pas un artefact de la facon dont je decoupe l'organe, c'est le maillage.

---

**A TESTER : RIEN.** Le moteur n'a pas bouge. Je maintiens ce que je t'ai dit le 20 : tant qu'une
seule section sur 38 est tenue, te demander de juger a l'oeil te coute plus que ca ne me rapporte.

`OPEN-DEFECTS` : `breast-spec-incomplete` reste ouverte. Elle ne se ferme que quand tu le dis.
