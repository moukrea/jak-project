# RIEN À TESTER SUR CE BUILD — et c'est volontaire

Branche `physics-keira-clean`.
(Le tag est lisible sur le device : `files/.custom_pack_stamp_jak1`.)

⚠️ **Ce build est, pour la physique, IDENTIQUE au précédent.** Aucune ligne de `goal_src/`, aucun
octet de `physics_chains.txt`, aucun mesh n'a changé. Te faire chercher une différence te ferait
perdre ton temps. Le cycle a servi à **mesurer**, et ce qu'il a trouvé répond à la question que tu
poses depuis le début.

---

## CE QUE J'AI MESURÉ, ET POURQUOI ÇA EXPLIQUE TES QUATRE DÉFAUTS D'UN COUP

Tous mes compteurs de collision (`meshpen`, `ROOM-SIDE`, `SELFCOL`) surveillent les **os** des
chaînes. J'ai enfin mesuré ce que ces os **représentent** de la géométrie qu'ils portent, sur le
mesh que tu as en main :

> **Les volumes de collision représentent 29,7 % de ce qui bouge sur Keira.**
> (546 sommets couverts sur 1837.)

Le détail qui fait mal :

| pièce | ce que la collision en voit |
|---|---|
| **nuque, bas de pantacourt gauche et droit** | **0 %** — ces trois pièces ne présentent **rien** |
| **lunettes** | **10 %** — 531 sommets étalés sur 38 cm, testés comme **deux billes** de 5 cm |
| oreilles | 20 % |
| languettes de genou | 29 % |
| grosses mèches | 36–42 % |
| mèches fines | 51–53 % |
| **seins** | **59 % / 70 %** — la sphère s'arrête à 322 u, la peau va jusqu'à 467 |

**Donc un zéro sur mes compteurs est compatible avec absolument tout ce que tu vois.** Ce ne sont
pas des faux verts au sens habituel : les compteurs sont honnêtes, c'est leur *domaine* qui est trop
petit. Ça vaut pour les trois défauts que tu répètes :

* **« les lunettes traversent le buste pour se poser dans le dos »** — les deux billes peuvent
  contourner un torse sans jamais le pénétrer pendant que la monture le traverse. `ROOM-SIDE = 0`
  est vrai *pour les deux billes*, et n'a jamais rien dit du reste.
* **« le bas des lunettes clipe dans les seins »** — la sphère du sein s'arrête 3,5 cm avant la
  vraie surface. Les lunettes peuvent donc s'enfoncer de 3,5 cm dans le sein sans qu'aucun compteur
  ne bouge : il compte contre le *volume*, pas contre la peau.
* **« les cheveux de nuque clipent dans son cou »** — **50,7 % de la peau de la nuque est DANS la
  capsule de la tête**, jusqu'à 15 cm de profondeur, dans la pose du modèle elle-même.

**Ton intuition — « pourquoi dériver du rig et pas du mesh ? » — n'est plus une suggestion à
évaluer.** Les capsules échouent maintenant **deux fois pour la même raison**, sur le torse et sur
la tête, chacune avec un A/B : trop petite, la peau sort du volume ; trop grande, la pièce est
déclarée enterrée et traverse tout. Il n'existe pas de valeur intermédiaire, parce qu'un torse
n'est pas un cylindre et une tête non plus.

---

## `pant-calf` A UNE RÉPONSE, ET ELLE NE VA PAS TE PLAIRE À MOITIÉ

Tu l'as signalé quatre fois (« le bas du pantacourt est à l'intérieur des mollets, comme si son
pantacourt s'arrêtait aux genoux »). C'est tranché, et ce n'est pas un problème de réglage :

* le mollet **n'avale pas** le tissu — 0 % de la peau du pan est dans la capsule de la jambe
  (l'hypothèse évidente, que j'avais formée, est **fausse** et mesurée telle) ;
* le pan **fait le tour de la jambe** : sa peau occupe **10 secteurs angulaires sur 12** ;
* il n'a qu'**UN seul joint**, posé quasiment **sur l'axe** de la jambe (184 u).

Un joint au centre d'un anneau ne peut lui donner que trois mouvements : tourner autour de la jambe
(**invisible** par symétrie), glisser le long de la jambe (un ourlet qui monte et descend — ce n'est
pas ce que fait du tissu), ou décentrer l'anneau, ce qui enfonce mécaniquement sa moitié dans le
mollet. C'est pour ça que tout ce que j'ai tenté a échoué, et pourquoi lever la contrainte avait
**empiré** les choses.

Pour comparaison, sur la même jambe : la languette de genou occupe **1 secteur sur 12** — c'est une
vraie languette, sur un côté — et elle, elle bouge.

**Il faut re-rigger l'ourlet** (plusieurs joints répartis *autour*, ou l'ourlet fendu en pans).
Tant que ce n'est pas fait, aucun réglage ne le fera pendre. Je ne l'ai pas fermé dans la liste des
défauts — c'est ton œil qui ferme, pas mon explication.

---

## CE QUE JE N'AI PAS FAIT, ET POURQUOI

Deux correctifs sont chiffrés et prêts : ajuster les volumes de poitrine sur leur peau (+145/+157 u)
et donner un volume aux trois chaînes qui n'en ont aucune. Les deux sont des changements de
**volume**, et mes deux dernières tentatives de déplacement de volume ont cassé le plancher de
mouvement (backhair −41 %, midhair −42/−43 %). Avec le plancher déjà rouge sur trois chaînes, en
poser un troisième à l'aveugle en fin de cycle aurait eu toutes les chances de payer une correction
avec du mouvement. Ils partent au prochain cycle, **un seul à la fois**, chacun mesuré contre le
plancher avant d'être conservé.

## LES COLLIDERS DÉRIVÉS DU MESH — TON IDÉE EST CÂBLÉE, ET ELLE N'EST PAS ENCORE UTILISABLE

C'était à moitié dans l'arbre depuis toujours : la moitié C++ intacte, le format de données bon au
jeton près, la livraison déjà branchée. Ce qui manquait, c'est la moitié GOAL — que le « départ
propre » avait emportée avec les 6000 lignes de suppresseurs. Elle est réécrite, et les deux bouts
sont prouvés par la trace de la course :

```
[hd-phys] BSURFSRC=package bsets=55 dropped=0
[HD-PHYS] bsurf ag=keira-hd sets=55/55 lies=55 non-lies=0
```

55 os portent maintenant de vrais échantillons de la surface skinnée — y compris les doigts, les
gants, le masque et les deux moitiés des lunettes, qui n'avaient **aucune** représentation de
collision. La passe est armée par la salle de test seule : **ton téléphone ne la paie pas.**

**Mais je ne te vends pas le résultat, parce qu'il ne vaut rien en l'état.** 25 millions
d'échantillons comparés, et les 22 chaînes rendent 7 à 49 cm de pénétration là où l'ancien compteur
rendait 0,0000017 m. C'était tentant à publier. Sauf que les **paires miroir** — paramètres
identiques, géométrie miroir, donc tout écart est de l'erreur d'instrument — divergent de 60 %
(`lmidhair` 0,197 contre `rmidhair` 0,489), et les sangles d'orteil, que je prouve propres au
repos, rendent quand même 7 cm. Le plancher d'erreur est de 0,29 m et dépasse presque toutes les
valeurs publiées.

La cause est la **densité** : 12 échantillons par os, c'est un espacement du même ordre que ce
qu'on mesure. La colonne se déclare donc « non discriminante » dans la course même qui la produit.
Le câblage, lui, est acquis et ne sera pas à refaire — c'est un problème de densité, chiffré et
localisé, pas un problème de principe.

---

## SI TU VEUX QUAND MÊME REGARDER QUELQUE CHOSE

Rien n'a changé depuis ton dernier retour, donc tes observations d'hier tiennent toujours. Le seul
retour qui m'aiderait maintenant : **est-ce que la nuque et les lunettes te gênent plus que les
mèches ?** Ça décide de l'ordre dans lequel je câble les volumes de surface.
