> LIS D'ABORD `prompts/item-grass-clumps-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe pousse en touffes coherentes, plus en bruit blanc de brins independants

## Defaut cite
- 2026-09-17 : « Alors je peux très bien valider cet item du coup, l'herbe es… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Il n'existe AUCUNE touffe. Le placement est un tirage barycentrique uniforme par triangle, graine par triangle, et chaque brin tire ses cinq proprietes d'un hachage independant. Une recherche exhaustive ne trouve aucune structure de regroupement : le mot « tuft » du code designe une decoupe de fragment a l'interieur d'une carte, et `D_TARGET = 150 tufts/m^2` est un abus de langage pour brins/m^2.

## Livrable
`grass_clump_defects` = 0, somme de termes publies SEPAREMENT.
1. LE REGROUPEMENT EST MESURE, pas affirme : publier une statistique de dispersion spatiale des racines, comparee a celle du tirage uniforme actuel sur la MEME surface. Elle doit s'ecarter d'un plancher declare. Une touffe qu'aucune mesure ne distingue d'un tirage uniforme n'existe pas.
2. LES TOUFFES NE SE RESSEMBLENT PAS : publier la dispersion du nombre de brins par touffe et celle de leur rayon. Deux touffes identiques cote a cote sont un defaut.
3. LES PALIERS RESTENT IMBRIQUES : un palier inferieur retire des brins DANS les memes touffes, il ne redistribue rien. Publier le compte de touffes dont l'origine bouge entre deux p […suite dans le contrat]

## Preuve exigee
`grass_clump_defects == 0` dans `reports/grass-clumps/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-clumps device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a juger a l'oeil pour l'instant : cette brique pose la STRUCTURE des touffes de la SPEC §6 (origine cuite, graine, rayon 110 mm ±21 %, 4,9 brins en moyenne, 2,5 x plus de voisins proches qu'un tirage uniforme, stable entre paliers). Le rendu qui change l'aspect vient avec les variantes de brins, le shading, le vent et les profils par biome : c'est LA que l'owner regardera l'herbe..

## Hors perimetre
Ne change ni la densite moyenne, ni la couleur, ni le vent — ce sont les items suivants, qui dependent de celui-ci. Tout ce qui n'est pas cet item.
