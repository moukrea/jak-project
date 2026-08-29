# Gcutscene-reframe — recadrer les cinematiques au lieu de les masquer

## La demande, mot pour mot (owner 2026-08-28)

> « Lors des cinématiques, sur PS2 ça mettait des barres noires en haut et en bas [...] au lieu
> d'avoir des barres noires on devrait grossir la partie visible pour qu'elle prenne toute la
> hauteur, et ne rien masquer horizontalement [...] QUELQUE SOIT L'ASPECT RATIO ! [...] on peut
> voir sur les aspect ratio très larges que le compteur de FPS se retrouve sous les barres
> noires, bien sûr le compteur de FPS devrait être exactement au même endroit où il est
> habituellement, idem pour les sous-titres et compagnie. »

## Mesure deja faite — le comportement actuel

`goal_src/jak1/engine/game/main.gc:24`, fonction `letterbox`. En mode natif (pas `use-vis?`),
le jeu **force du 16:9 en toutes circonstances** :

- ecran plus etroit que 16:9 -> deux bandes horizontales, hauteur
  `112 * (1 - aspect/16:9)` ;
- ecran plus LARGE que 16:9 -> deux bandes **VERTICALES**, largeur
  `256 * (1 - 16:9/aspect)`, dessinees en x=0 et x=512-lbx_w.

Le second cas est celui que l'owner decrit en ultra-large.

**Le compteur de FPS sous les bandes est explique** : les bandes sont emises dans le bucket
`debug-no-zbuf`, un des DERNIERS. Elles peignent donc par-dessus tout, HUD compris. Ce n'est pas
un probleme de position du compteur, c'est un probleme d'ORDRE DE DESSIN.

## La correction demandee

Ne rien masquer : RECADRER. Conserver le champ de vision VERTICAL de la bande prevue, et deduire
l'horizontal du format reel de l'ecran. La composition verticale voulue par les auteurs est alors
preservee exactement, l'horizontal s'etend, et **aucune bande n'est plus necessaire, a aucun
format**.

## Le risque a MESURER avant de livrer

Elargir l'horizontal montre ce que les auteurs avaient laisse HORS CADRE : decor non construit,
acteurs qui apparaissent, bords de plateau. C'est le piege classique de l'elargissement de champ
dans un jeu de cette epoque. **Passer les cinematiques une par une** et publier la liste de
celles qui revelent quelque chose ; prevoir une limite pour celles-la plutot que de renoncer au
principe.

## Le HUD

Compteur de FPS et sous-titres doivent rester exactement a leur place habituelle : dessines en
espace ECRAN et APRES le recadrage. Le placement des sous-titres est aujourd'hui cale sur la
bande 16:9 et devra suivre le nouveau cadre.

## Ordre impose

1. Recadrage de la camera (champ vertical conserve, horizontal deduit).
2. Suppression des bandes.
3. Ordre de dessin du HUD.
4. Passe scene par scene sur ce que l'elargissement revele.

---

# RETOUR OWNER 2026-08-29 — LE RECADRAGE FAIT L'INVERSE DE CE QUI EST DEMANDE

> « latéralement, au lieu de laisser voir plus de champ de vue, tu as fait en sorte que là où
> l'image s'arrêtait avec les barres à gauche et à droite aille aux bords de l'écran... Ce qui
> fait que ça sacrifie le cadre vertical que j'avais demandé de préserver (en zoomant pour n'avoir
> que la hauteur visible entre les barres en haut et en bas). Les barres latérales, elles, c'est
> le CHAMP DE VISION qui doit s'agrandir pour qu'on ne les voie pas. »

## Ce que la demande dit, en une phrase

Le cadre VERTICAL de la bande d'origine est intouchable. Les barres LATERALES se suppriment en
**elargissant le champ de vision horizontal**, jamais en etirant ni en recadrant l'image.

## Etat du code, ligne par ligne (`math-camera.gc:68-83`)

    (set! (-> math-cam y-ratio) (* (1/ ASPECT_16X9) (-> math-cam x-ratio)))
    (*! (-> math-cam x-ratio) (/ (-> *pc-settings* aspect-ratio) ASPECT_16X9))

L'INTENTION est juste : `y` fixe la bande 16:9 d'auteur, `x` croit avec le format d'ecran.
Mais l'owner OBSERVE l'inverse. Les deux ne peuvent pas etre vrais en meme temps, donc **la
valeur qui arrive dans `(-> *pc-settings* aspect-ratio)` n'est pas le format de son ecran.**

C'est le meme suspect que la phase `Gandroid-window-size` : ce consommateur-la n'a peut-etre pas
ete couvert par le correctif du clamp d'hote.

## A FAIRE, dans cet ordre

1. **Publier la valeur reellement lue** par cette ligne, a cote du format physique de l'ecran,
   au moment ou une cinematique tourne. Une seule ligne de trace. Sans elle on continuera de
   deviner : c'est deja ce qui a coute plusieurs allers-retours a l'owner.
2. **Comparer le champ de vision horizontal cinematique au champ de vision GAMEPLAY** au meme
   format d'ecran. Le gameplay fait `x *= aspect/(4:3)` et l'owner le trouve bon. Publier les
   deux valeurs cote a cote : si la cinematique montre MOINS sur les cotes que le gameplay, la
   plainte est mecaniquement expliquee.
3. Corriger de sorte que, a format d'ecran croissant : `y` reste CONSTANT et `x` CROIT.
   Publier le tableau `aspect / x / y` sur cinq formats pour le prouver.

## Piege a ne pas repeter

L'ancienne version de ce document affirmait « mesure sur sept formats : le vertical rend la meme
valeur partout (0,3514) ». Cette mesure portait sur la fonction, pas sur ce que l'owner voit.
**Une grandeur constante dans un banc d'essai peut varier en production si son ENTREE varie.**
