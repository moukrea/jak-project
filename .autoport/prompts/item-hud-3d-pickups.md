> LIS D'ABORD `prompts/item-hud-3d-pickups-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Mécamouche, orbe, particule d'éco verte et pile d'énergie du HUD : les vrais modèles du jeu à la place des sprites

## Defaut cite
- 2026-09-18 : « Alors t'aurais pu joindre un screen ça aurait accéléré les c… »

## Cause connue
17/09 20:55 REFUS OWNER (build 4833ab) : orbe, mecamouche, eco vert acquis ; la PILE D'ENERGIE apparait minuscule et « squeezee » au centre de l'ecran, avec la bonne animation mais pas la bonne place ni la bonne echelle (positionnement absolu suspecte, aspect faux). La mesure de position de l'essai 2 a rendu 0 px pour la pile : elle mesurait a cote. Corriger la mesure d'abord, puis la pile. Ne pas toucher aux trois autres elements.

17/09 REFUS OWNER (build ae4272) : mecamouche au milieu de l'ec […suite dans le contrat]

## Livrable
`hud_model_defects` = 0, somme de termes publies SEPAREMENT.

1. QUATRE EMPLACEMENTS, QUATRE MODELES : mecamouche (vue de face), orbe, particule d'eco verte, pile ; par emplacement, l'identifiant du modele dessine est publie et c'est celui du jeu (le meme que l'objet ramassable).

2. PLUS DE SPRITE : allume, le nombre d'appels du chemin sprite d'origine pour ces quatre elements = 0.

3. LA POSITION ET LA TAILLE : chaque modele est cadre dans le rectangle de l'element d'origine (rectangles publie […suite dans le contrat]

## Preuve exigee
`hud_model_defects == 0` dans `reports/hud-3d-pickups/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-3d-pickups device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : HUD en jeu, sur le build nomme dans le commentaire « build publie ». UNE question : la lueur de la pile d'energie est-elle a la MEME hauteur que la pile elle-meme ? (position de la pile, taille, lueur presente et les trois autres emplacements sont deja valides par l'owner : ne pas les redemander)..

## Hors perimetre
Ne touche ni au coeur ni a la jauge. Tout ce qui n'est pas cet item.
