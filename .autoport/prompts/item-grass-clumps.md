# L'herbe pousse en touffes coherentes, plus en bruit blanc de brins independants

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Il n'existe AUCUNE touffe. Le placement est un tirage barycentrique uniforme par triangle, graine par triangle, et chaque brin tire ses cinq proprietes d'un hachage independant. Une recherche exhaustive ne trouve aucune structure de regroupement : le mot « tuft » du code designe une decoupe de fragment a l'interieur d'une carte, et `D_TARGET = 150 tufts/m^2` est un abus de langage pour brins/m^2.

## Livrable
`grass_clump_defects` = 0, somme de termes publies SEPAREMENT.
1. LE REGROUPEMENT EST MESURE, pas affirme : publier une statistique de dispersion spatiale des racines, comparee a celle du tirage uniforme actuel sur la MEME surface. Elle doit s'ecarter d'un plancher declare. Une touffe qu'aucune mesure ne distingue d'un tirage uniforme n'existe pas.
2. LES TOUFFES NE SE RESSEMBLENT PAS : publier la dispersion du nombre de brins par touffe et celle de leur rayon. Deux touffes identiques cote a cote sont un defaut.
3. LES PALIERS RESTENT IMBRIQUES : un palier inferieur retire des brins DANS les memes touffes, il ne redistribue rien. Publier le compte de touffes dont l'origine bouge entre deux paliers : zero.
4. LE DETERMINISME TIENT : deux chargements donnent les memes touffes aux memes endroits. Publier une empreinte de l'ensemble des origines.
PREUVE : `FEATURE grass-clumps armed=1 hits=<touffes effectivement montees>` + la ligne `grass_clump_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_clump_defects == 0` dans `reports/grass-clumps/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-clumps device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement : l'herbe doit se lire par groupes, avec des brins dominants et des brins peripheriques, au lieu d'un tapis uniforme..

## Hors perimetre
Ne change ni la densite moyenne, ni la couleur, ni le vent — ce sont les items suivants, qui dependent de celui-ci. Tout ce qui n'est pas cet item.
