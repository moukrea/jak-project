> LIS D'ABORD `prompts/item-ao-indirect-clean-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin

## Defaut cite
- 2026-09-17 : « Alors si ça peut t'aider, je vois les mesures tourner sur le… »

## Cause connue
17/09 18:35 ARBITRAGE OWNER : « Option a, mais 0,009 % c'est infime, et tu parles d'un truc mobile j'ai l'impression ». 2 essais, PERIMETRE UNIQUE : le point F « rien ne bouge camera fixe » (1802 texels sur 21 M, bords de buissons) et les 2 px de `ao_sway_gap_px`. Tout le reste est acquis et ne se retouche pas (A-E, G). ORDRE : (1) d'abord NOMMER la source du changement image a image sur une scene immobile par ablation, en une course : (i) la prepasse echantillonne-t-elle le feuillage autrement […suite dans le contrat]

## Livrable
`ao_owner_defects` = 0, somme de termes publies SEPAREMENT ; un terme non mesure compte 1. CE QUE LA SPEC DIT, EXACTEMENT (SPEC lumiere 4.2, 4.6, 4.7) :

A. L'ANCIENNE AO EST SUPPRIMEE (4.7) : la passe qui composait l'AO sur l'image opaque finale (`ao_composite.frag`, `GL_ZERO / GL_ONE_MINUS_SRC_COLOR`, espace gamma, tout le pixel), son masque de luminance `1 - smoothstep(0.45, 0.90, luma)` et la copie de scene `m_scene_tex` n'existent plus dans le binaire : sites = 0, temoin de compilation, auc […suite dans le contrat]

## Preuve exigee
`ao_owner_defects == 0` dans `reports/ao-indirect-clean/proof.txt`.
Le proof se produit par `lib/proof_run.sh ao-indirect-clean device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage recharge > Occlusion ambiante, chaque mode et chaque qualite, force au maximum, sur le dernier build de jak-builds : le raccord mur/toit de la hutte porte une ombre de contact sans bande claire ; les facades n'ont ni damier ni grain ; l'AO n'a plus l'air d'un filtre pose sur l'image ; les buissons n'ont pas d'ombre flottante ; camera immobile, rien ne bouge..

## Hors perimetre
Pas de nouveau modele d'AO, pas de reglage en plus dans le menu. Tout ce qui n'est pas cet item.
