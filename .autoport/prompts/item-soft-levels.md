# Niveau par niveau : snow, training, village1, puis beach et ogre

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 15. Ordre des pilotes : snow compact, congeres de snow, training hors eau, village1 haut, beach (APRES soft-water-contract valide), ogre ; puis village2, intro. Rien sur misty ni sur le fond marin. Chaque niveau est une donnee cuite, rebake cible.

## Livrable
`soft_level_defects` = 0, somme de termes publies SEPAREMENT.
1. CHAQUE NIVEAU PUBLIE SON INVENTAIRE : triangles eligibles, desaccords, epaisseurs (min/mediane/max), rejets, objets statiques cuits.
2. LE CHARGEMENT NE BLOQUE PAS : temps de chargement du compagnon par niveau, 0 ms bloque, asynchrone.
3. LE COUT PAR IMAGE EST PUBLIE PAR NIVEAU au palier Moyen sur les deux cibles.
4. BEACH N'ARRIVE QU'AVEC L'EAU : la coque de beach est cuite sans shore_sdf tant que soft-water-contract n'est pas valide (temoin `soft_shore_missing=1`), et recuite avec quand il l'est.
PREUVE : `FEATURE soft-levels armed=1 hits=<niveaux cuits et charges>` + la ligne `soft_level_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_level_defects == 0` dans `reports/soft-levels/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-levels device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : L'herbe... non : la neige et le sable existent partout ou le jeu en a — Snowy Mountain, Geyser Rock, Sandover, puis Sentinel Beach et Mountain Pass..

## Hors perimetre
Rien sur misty, rien sous la mer, rien sur les autres matieres. Tout ce qui n'est pas cet item.
