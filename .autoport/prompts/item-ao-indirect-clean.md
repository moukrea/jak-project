> LIS D'ABORD `prompts/item-ao-indirect-clean-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une nouvelle AO : l'ancienne à la poubelle, la nouvelle calculée dans l'éclairage sur le seul indirect, plus jamais un filtre posé à la fin

## Defaut cite
- 2026-09-17 : « Et aussi, attention au cycle jour/nuit, ça peut peut-être jo… »

## Cause connue
Owner 17/09 : « AO legacy poubelle → Nouvelle AO plus en filtre à la fin », puis « être clair sur ce qu'on veut exactement par rapport à la spec » : le livrable recopie la spec (4.2 lignes 2-6, 4.6, 4.7), il ne la resume pas. Et : « une bande claire à la zone de contact… l'AO est juste posée par-dessus comme un filtre ». Ce ticket REMPLACE lighting-ao-indirect (14 essais, livrable devenu illisible) : memes mesures, contrat lisible. Prepasse (ao-prepass-tie-alpha) et sonde stable (ao-static-probe […suite dans le contrat]

## Livrable
`ao_owner_defects` = 0, somme de termes publies SEPAREMENT ; un terme non mesure compte 1. CE QUE LA SPEC DIT, EXACTEMENT (SPEC lumiere 4.2, 4.6, 4.7) :

A. L'ANCIENNE AO EST SUPPRIMEE (4.7) : la passe qui composait l'AO sur l'image opaque finale (`ao_composite.frag`, `GL_ZERO / GL_ONE_MINUS_SRC_COLOR`, espace gamma, tout le pixel), son masque de luminance `1 - smoothstep(0.45, 0.90, luma)` et la copie de scene `m_scene_tex` n'existent plus dans le binaire : sites = 0, temoin de compilation, auc […suite dans le contrat]

## Preuve exigee
`ao_owner_defects == 0` dans `reports/ao-indirect-clean/proof.txt`.
Le proof se produit par `lib/proof_run.sh ao-indirect-clean device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage recharge > Occlusion ambiante, chaque mode et chaque qualite, force au maximum, sur le dernier build de jak-builds : le raccord mur/toit de la hutte porte une ombre de contact sans bande claire ; les facades n'ont ni damier ni grain ; l'AO n'a plus l'air d'un filtre pose sur l'image ; les buissons n'ont pas d'ombre flottante ; camera immobile, rien ne bouge..

## Hors perimetre
Pas de nouveau modele d'AO, pas de reglage en plus dans le menu. Tout ce qui n'est pas cet item.
