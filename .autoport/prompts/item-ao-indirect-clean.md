> LIS D'ABORD `prompts/item-ao-indirect-clean-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 17/09 : « Basique : AO legacy poubelle → Nouvelle AO plus en filtre à la fin ». Et : « on a quand même (quel que soit le modèle d'AO et la qualité) une bande claire à la zone de contact… l'AO est juste posée par-dessus comme un filtre, comme si elle était calculée tout à la fin ». SPEC lumiere 4.7, table aujourd'hui/cible : aujourd'hui ao_composite.frag multiplie l'image opaque FINALE en gamma, tout le pixel, avec un masque de luminance 1-smoothstep(0.45,0.90,luma) ; cible : texture R8, li […suite dans le contrat]

## Livrable
`ao_owner_defects` = 0, somme de termes publies SEPAREMENT ; un terme non mesure compte 1.

A. L'ANCIENNE AO EST A LA POUBELLE : la passe de composition finale (ao_composite.frag, GL_ZERO/GL_ONE_MINUS_SRC_COLOR) et son masque de luminance n'existent plus dans le binaire (sites = 0, temoin de compilation), aucun chemin ne les rappelle.

B. LA NOUVELLE AO EST DANS L'ECLAIRAGE : la texture d'AO (R8) est lue dans shade(), en lineaire, avant le tone map, et multiplie le SEUL terme indirect. Temoins : […suite dans le contrat]

## Preuve exigee
`ao_owner_defects == 0` dans `reports/ao-indirect-clean/proof.txt`.
Le proof se produit par `lib/proof_run.sh ao-indirect-clean device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage recharge > Occlusion ambiante, chaque mode et chaque qualite, force au maximum, sur le dernier build de jak-builds : le raccord mur/toit de la hutte porte une ombre de contact sans bande claire ; les facades n'ont ni damier ni grain ; l'AO n'a plus l'air d'un filtre pose sur l'image ; les buissons n'ont pas d'ombre flottante ; camera immobile, rien ne bouge..

## Hors perimetre
Pas de nouveau modele d'AO, pas de reglage en plus dans le menu. Tout ce qui n'est pas cet item.
