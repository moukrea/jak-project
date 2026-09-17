> LIS D'ABORD `prompts/item-hud-3d-pickups-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Mécamouche, orbe, particule d'éco verte et pile d'énergie du HUD : les vrais modèles du jeu à la place des sprites

## Defaut cite
- 2026-09-17 : « Attention le téléphone run en 4:3 sur une résolution basse,… »

## Cause connue
17/09 20:55 REFUS OWNER (build 4833ab) : orbe, mecamouche, eco vert acquis ; la PILE D'ENERGIE apparait minuscule et « squeezee » au centre de l'ecran, avec la bonne animation mais pas la bonne place ni la bonne echelle (positionnement absolu suspecte, aspect faux). La mesure de position de l'essai 2 a rendu 0 px pour la pile : elle mesurait a cote. Corriger la mesure d'abord, puis la pile. Ne pas toucher aux trois autres elements.

17/09 REFUS OWNER (build ae4272) : mecamouche au milieu de l'ecran des la premiere image tant que le HUD n'a pas ete affiche ; pile d'energie minuscule toujours visible, positionnement absolu en pixels sur une petite resolution (aspect faux) ; mecamouche un peu t […suite dans le contrat]

## Livrable
`hud_model_defects` = 0, somme de termes publies SEPAREMENT.

1. QUATRE EMPLACEMENTS, QUATRE MODELES : mecamouche (vue de face), orbe, particule d'eco verte, pile ; par emplacement, l'identifiant du modele dessine est publie et c'est celui du jeu (le meme que l'objet ramassable).

2. PLUS DE SPRITE : allume, le nombre d'appels du chemin sprite d'origine pour ces quatre elements = 0.

3. LA POSITION ET LA TAILLE : chaque modele est cadre dans le rectangle de l'element d'origine (rectangles publies, ecart 0 px).

4. LE COUT : temps par image du HUD allume contre eteint, >= 300 images, publie (< 0,3 ms sur le telephone).

5. ETEINT = ORIGINE.

PREUVE : `FEATURE hud-3d-pickups armed=1 hits=<empl […suite dans le contrat]

## Preuve exigee
`hud_model_defects == 0` dans `reports/hud-3d-pickups/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-3d-pickups device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : HUD en jeu : la mecamouche, l'orbe, la particule d'eco verte a cote du coeur et la pile d'energie sont les vrais objets du jeu en 3D, a la place des sprites plats..

## Hors perimetre
Ne touche ni au coeur ni a la jauge. Tout ce qui n'est pas cet item.
