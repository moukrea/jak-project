# Les bourrelets : la matiere repoussee, bornee, du bon cote

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 4 et decision 6 : redistribution partielle vers le cote oppose au mouvement, dans la meme tuile ; bornes 25 % / 5 % / 12 % de h selon la matiere ; nul en frontiere ; fusion ; adoucissement.

## Livrable
`soft_ridge_defects` = 0, somme de termes publies SEPAREMENT.
1. LA HAUTEUR POSITIVE EST BORNEE : compte de texels de bourrelet au-dessus de la borne du profil = zero.
2. RIEN EN FRONTIERE, RIEN SOUS UN OBJET : compte de texels de bourrelet a distance de frontiere nulle = zero.
3. PAS D'OSCILLATION : variation de hauteur par texel entre deux images consecutives sans nouveau tampon ≤ seuil declare ; compte de pics = zero.
4. DU BON COTE : compte de bourrelets dont la direction s'oppose au mouvement de l'interacteur ; compte d'inversions = zero.
PREUVE : `FEATURE soft-ridges armed=1 hits=<tampons ayant produit un bourrelet>` + la ligne `soft_ridge_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_ridge_defects == 0` dans `reports/soft-ridges/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-ridges device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Dans la neige profonde, la neige se repousse sur les cotes du sillon ; dans le sable, a peine..

## Hors perimetre
Pas de shading. Tout ce qui n'est pas cet item.
