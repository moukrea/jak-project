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
