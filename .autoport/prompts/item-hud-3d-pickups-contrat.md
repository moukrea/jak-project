# Mécamouche, orbe, particule d'éco verte et pile d'énergie du HUD : les vrais modèles du jeu à la place des sprites — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

17/09 REFUS OWNER (build ae4272) : mecamouche au milieu de l'ecran des la premiere image tant que le HUD n'a pas ete affiche ; pile d'energie minuscule toujours visible, positionnement absolu en pixels sur une petite resolution (aspect faux) ; mecamouche un peu trop haute une fois le HUD affiche ; pile pas placee. Les deux captures sont dans owner-feedback/hud-3d-pickups/ (regarde-les). La porte de l'essai 1 etait aveugle : mesurer sur l'IMAGE RENDUE de l'appareil, et suivre la visibilite du HUD d'origine.

SPEC HUD §5, mots de l'owner du 17/09 : « la vraie mecamouche du jeu et plus un sprite dégueu », « une vraie orbe », « une vraie particule d'eco verte comme celles qu'on ramasse in game », « pour la pile d'énergie, idem ».

## Livrable — le contrat, en entier

`hud_model_defects` = 0, somme de termes publies SEPAREMENT.

1. QUATRE EMPLACEMENTS, QUATRE MODELES : mecamouche (vue de face), orbe, particule d'eco verte, pile ; par emplacement, l'identifiant du modele dessine est publie et c'est celui du jeu (le meme que l'objet ramassable).

2. PLUS DE SPRITE : allume, le nombre d'appels du chemin sprite d'origine pour ces quatre elements = 0.

3. LA POSITION ET LA TAILLE : chaque modele est cadre dans le rectangle de l'element d'origine (rectangles publies, ecart 0 px).

4. LE COUT : temps par image du HUD allume contre eteint, >= 300 images, publie (< 0,3 ms sur le telephone).

5. ETEINT = ORIGINE.

PREUVE : `FEATURE hud-3d-pickups armed=1 hits=<emplacements du HUD dessines avec un modele>` + la ligne `hud_model_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` et le HUD d'origine bit-identique.

S'AJOUTE (REFUS DE L'OWNER, 17/09, build ae4272, deux captures dans owner-feedback/hud-3d-pickups/) : « tant que le hud n'a pas été affiché in game, dès la première frame du jeu on l'a [la mécamouche] en plein milieu de l'écran » ; « une pile d'énergie tout minuscule juste en dessous… on la voit tout le temps in game, je pense que t'as fait du positionning absolu pour la pile d'énergie sur une petite résolution » ; « in game, la mécamouche trouve bien sa place dans le hud quand on l'affiche (la pile d'énergie non) mais est un poil trop haute par rapport à où était originalement son sprite ». La porte a rendu 0 sur 15 720 images : son terme de position etait un MIROIR (calcule depuis les variables du placement, pas depuis l'image). Verdicts ajoutes :

6. LA VISIBILITE EST CELLE DU HUD D'ORIGINE : un modele n'est dessine QUE dans les images ou le sprite d'origine l'aurait ete (ecran titre et premieres images comprises, HUD replie compris). Publier, sur la course entiere, le compte d'images « modele dessine sans sprite d'origine correspondant » (bras `--off` = temoin) : 0, et le compte d'images ou le HUD est visible (non nul).

7. LA POSITION SE MESURE SUR L'IMAGE RENDUE DE L'APPAREIL : pour chaque element, boite englobante du modele lue sur l'image finale du telephone (masque d'identite de dessin, resolution et aspect reels : 2400x1080, 21:9), contre la boite du sprite d'origine lue de la MEME facon sur le bras `--off` : centre a 2 px pres, taille a 5 % pres, publies par element. Aucune coordonnee absolue en pixels : le placement est une fraction de l'espace HUD d'origine, aspect compris.

8. LA MECAMOUCHE N'EST PAS TROP HAUTE : ecart vertical de son centre contre le centre du sprite d'origine, en pixels sur l'appareil, publie : <= 2 px.

## Hors perimetre

Ne touche ni au coeur ni a la jauge. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

HUD en jeu : la mecamouche, l'orbe, la particule d'eco verte a cote du coeur et la pile d'energie sont les vrais objets du jeu en 3D, a la place des sprites plats.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> Les specs… Linear il peut pas les avoir ? ça serait pratique parce que voir que la spec existe sans pouvoir la lire…

### 2026-09-17
> Alors la mecamouche elle est bizarre… tant que le hud n'a pas été affiché in game, dès la première frame du jeu on l'a en plein milieu de l'écran, ça se règle dès qu'on ouvre le hud in game. Si tu paie bien attention au même screen, tu verra qu'on voit aussi une pile d'énergie tout minuscule juste en dessous… et elle, on l'a voit tout le temps on game, je pense que t'as fais du positionning absolu pour la pile d'énergie sur une petite résolution et du coup c'est complètement à côté de la plaque (avec un aspect ratio différent en prime je présume). Sinon, in game, la mecamouche trouve bien sa place dans le hud uand on l'affiche (la pile d'énergie non) mais est un poil trop haute par rapport à où était originalement son sprite, tu devrais pouvoir facilement régler ça   ![71422.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/6f19ebc7-9cda-42ba-9daf-b4b876156c8d/6085f020-ebfa-4e85-9d28-653fd6d46658)  ![71423.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/66db29eb-44f2-497c-935d-6cbab80bb657/e6f6d4aa-4c7c-4d4a-b3c0-e0840fe80e57) [images enregistrees : .autoport/owner-feedback/hud-3d-pickups/20260917T1225-1.jpg ; .autoport/owner-feedback/hud-3d-pickups/20260917T1225-2.jpg]

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

