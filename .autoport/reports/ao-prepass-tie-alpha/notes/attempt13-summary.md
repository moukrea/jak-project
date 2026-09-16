DIRECTIVES v775512c234
# Essai13 — la voie imposee est REFUTEE par la mesure ; la cause geometrique est chiffree

Aucune source du jeu n'a ete modifiee : `ao_blur.frag` reste sha256 `9bda9d04174d8256`, identique
a `c1581d95da`. Les quatre candidats ci-dessous vivent dans `notes/`, jamais dans `game/`.
Meme banc que l'essai 12 (Intel/Mesa 25.3.6), memes 425 px / 15 contacts, meme lecteur natif.

## 1. La cause, chiffree sur l'archive appareil (22160-600, colonne x=100)

Profondeur de fenetre : mur `+5,84e-6`/texel, toit `+8,089e-5`/texel, contact a `1,4532e-2`.
Le tap du pixel de mur (100,550) qui tombe sur le TOIT a un residu au plan `rz = 1,498e-4`
pour `zsig = 4*zlim = 5,81e-4` : **il garde 96,7 % de son poids**. La ponderation bilaterale
ne s'annule donc JAMAIS sur ce raccord — c'est le chiffre qui manquait au diagnostic.

AO brute au contact : `25`. Apres les DEUX passes de pas 1 : `52`. Apres celles de pas 2 : `85`.
A la fin : `141`, quand l'interieur du mur se pose a `130`. **Les passes de pas 1 conservent le
contact ET annulent la tuile 4x4 ; ce sont les boites LARGES (pas 2, 3, 5) qui l'effacent.**

Geometrie : le creux de contact fait **3 px** (mur brut 25,31,23 puis 63,78,94,101,173 ;
toit 61,71,132,98,160), le support composite fait **29 texels** au palier Eleve. De part et
d'autre du pli la surface REDEVIENT CLAIRE en trois pixels.

## 2. Voie imposee le 16/09 (poids nul / deplacement des taps traversants) : REFUTEE

`attempt13-relocate.frag` deplace tout tap traversant de `off - 4*sign(off)` — MEME classe
modulo 4, MEME poids, donc phases exactement conservees, support non reduit.
Resultat (`attempt11-a13-reloc`) : largeurs cumulees **17/7/10** (SSAO/HBAO/GTAO) contre
**12/2/7** au livre ; max **5/4/4** contre **3/1/2**. **PIRE.** Et `flat_step` y monte a
**54/39/41** pour un plafond de 10 : cette voie casse AUSSI l'acquis du damier.
Raison mesuree : les deux cotes du pli sont clairs a plus de trois pixels, donc l'origine des
taps ne change rien ; c'est la LARGEUR de la moyenne qui perd le contact, pas son cote.

## 3. Borner la sortie par l'entree au pli : le contact revient, le DAMIER revient aussi

| candidat | armement | bande SSAO/HBAO/GTAO | `flat_step` x1000 SSAO/HBAO/GTAO |
|---|---|---|---|
| livre (HEAD) | — | 12/2/7 (max 3/1/2) | **8 / 5 / 5** |
| `attempt13-foldbound` | un tap casse la pente, pas 2..5 | 8/0/1 (max 1/0/1) | **30 / 25 / 25** |
| `attempt13-creasebound` | pli au TEXEL +-1, pas 2..5 | 5/3/4 (max 1/2/2) | **33 / 31 / 30** |
| `attempt13-bound2` | idem, pas 2 seul | 9/2/7 | 8 / 5 / 6 |
| `attempt13-bound23` | idem, pas 2 et 3 | 13/8/11 | 10 / 7 / 8 |
| `attempt13-relocate` | §2 | 17/7/10 | 54 / 39 / 41 |

`flat_step` est la grandeur qui arme `ao_pattern_over_ceiling` (acquis owner « plus de damier
ni pixelisation »), **plafond 10**. Reimplementation fidele de `AmbientOcclusion.cpp:1153`
(`kPlanarRel=0,02`, `kPlanarAbs=1e-5`, `kAoStep=8`), population `pop=902744` identique pour les
quatre images. Les deux candidats efficaces sont donc a **trois fois le plafond** : ils
rendraient a l'owner exactement le defaut qu'il a declare disparu. Les deux qui restent SOUS
le plafond (`bound2`, `bound23`) ne corrigent rien : 9/2/7 et 13/8/11 contre 12/2/7 livre.
**Aucun point du reglage ne tient les deux a la fois** — c'est le constat central de l'essai.
Releve integral et reproducteur : `attempt13-flatstep.py`, `attempt13-flatstep.log`.

Mecanisme, nomme : la borne est une decision BINAIRE par pixel. Deux voisins qui la prennent
differemment recoivent des quantites de flou differentes, ce qui cree une marche d'AO d'un
texel — et `flat_step` compte precisement les marches des pixels PLANS, dont ceux qui bordent
un pli. Toute modulation binaire d'un lisseur produit ce defaut a sa frontiere.

## 4. Pourquoi « aucun pixel hors raccord ne change » n'est pas atteignable ainsi

Population des plis de l'archive, test de cassure de pente relative (memes constantes que
`contact_band()`), par axe et par pas :

| pas | 1 | 2 | 3 | 5 |
|---|---|---|---|---|
| vertical | 11,2 % | 21,3 % | 28,3 % | **35,2 %** |
| horizontal | 10,2 % | 20,6 % | 28,9 % | **41,4 %** |

Et le ratio de cassure au raccord mur/toit vaut **2,56**, quand le 95e centile de tout l'ecran
vaut **2,11** et le 99e **3,87** : le raccord de la hutte n'est PAS un point aberrant de la
scene. Une boite de pas 5 porte a dix texels ; dans un village, son support touche un pli
presque partout. Mesure a l'appui : `attempt13-creasebound` change **211 709 pixels PLANS sur
436 496** (48 %), `attempt13-foldbound` autant. Aucun reglage du detecteur ne separe le
raccord du reste de la scene, parce qu'il n'y a rien a separer.

## 5. Ce qui a ete verifie sur les candidats (et n'a PAS suffi)

`attempt13-creasebound` passe les 16 temoins plans/ciel/silhouette (`COMPARE ... changed=0
max_abs=0` 16 fois, `gl_errors=0`) et rend `FOLD_PHASE_MAX R8 max_range=0` — pas de damier en
8 bits au pli. Son `R32F` vaut `2,369e-5` contre `7,749e-7` a la reference : **0,006 quantum R8**,
a comparer aux `0,1098` (28 quanta) de la variante `ray` rejetee a l'essai 12. Ce n'est donc pas
la phase qui le condamne : c'est `flat_step`.

## 6. Ce qui reste, et ce que ces mesures excluent

Exclu par la mesure, ne pas rejouer : deplacer/annuler les taps traversants (§2) ; borner la
sortie des boites larges, a n'importe quel sous-ensemble de pas (§3). Sont deja exclus par les
essais 11-12 : enveloppe concave, reflexion, rayon reduit, recherche locale du pli.
Reste ouvert, non teste ici : une restauration APRES le flou dont le profil soit CONTINU (une
marche dure au pli ferait remonter `flat_step` par le meme mecanisme qu'au §3) ; ou un
estimateur dont le creux de contact soit plus large que 3 px, donc survivant a 29 texels de
moyenne. Les deux sortent du perimetre « ne pas elargir ni reduire le support ».

Commandes : `attempt13-commands.md`. Rejeux : `attempt11-a13-{reloc,bound,crease,b2,b23}`.
Diagnostic complet : `attempt12-a13-bound-diagnostic.json`.
