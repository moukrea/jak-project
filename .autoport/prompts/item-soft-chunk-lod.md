# Chunks, culling, LOD : la coque a distance, sans pop et sans couture

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 9. Chunks de 8 m par nappe ; CINQ portees de culling publiees separement ; chaine L0-L3 par index avec hysteresis 0,9x/1,1x et morphing ; la tuile est la meme a tous les niveaux ; a distance, mip de tuile plus grossier ; marge d'un texel ecrite des deux cotes d'une frontiere de chunk.

## Livrable
`soft_lod_popin_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUN SAUT AU SEUIL : sur un travelling franchissant chaque seuil, compte de sommets dont la hauteur bouge de > 1 quantum entre les deux images qui encadrent le seuil = zero ; transitions par seconde camera tenue au seuil ≤ plafond ; les deux seuils d'hysteresis publies.
2. LE SILLON TRAVERSE LES CHUNKS : continuite d'une trace a cheval sur deux chunks ≥ 0,98 ; ecart de hauteur entre les deux marges = zero.
3. CINQ PORTEES, CINQ COMPTES : chunks rendus, simules, collectes, vieillis, a normales, publies separement ; instances soumises hors champ = zero.
4. LA LECTURE LOINTAINE GARDE LES SILLONS : au palier lointain, longueur de sillon majeur conservee ≥ 0,9 de la longueur proche ; petites empreintes effacees (compte publie).
PREUVE : `FEATURE soft-chunk-lod armed=1 hits=<franchissements de seuil observes>` + la ligne `soft_lod_popin_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_lod_popin_defects == 0` dans `reports/soft-chunk-lod/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-chunk-lod device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : En s'eloignant d'une zone tracee : rien ne saute, les grands sillons restent lisibles..

## Hors perimetre
Pas le contrat eau. Tout ce qui n'est pas cet item.
