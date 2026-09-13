# Le sable au bord de l'eau : la coque lit le rivage de l'eau, elle ne le redefinit pas

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 10. L'eau possede shore_sdf / shore_dir / floor_depth (.waterbake de water-shore) et le sable mouille (shade()). Nous lisons shore_sdf AU BAKE (falloff vers la ligne, EXCLUSION sous -0,5 m : aucune coque sur le fond marin) et la phase du jet de rive au runtime (scalaire publie par water-shore, ajoute a son livrable) pour accelerer la relaxation. Aucune ecriture croisee.

## Livrable
`soft_shore_defects` = 0, somme de termes publies SEPAREMENT.
1. RIEN NE DEPASSE DE L'EAU AU REPOS : compte de texels de coque au-dessus de la surface d'eau sous la ligne = zero.
2. L'EAU EFFACE : relaxation mesuree la ou la phase passe vs a cote, ecart au-dessus d'un plancher declare.
3. AUCUNE ECRITURE CROISEE : deux compagnons, deux pools ; compte de sites ou la coque ecrit une donnee d'eau ou l'eau une donnee de coque = zero.
4. LE REPLI EST DEFINI : sans .waterbake, falloff statique par la mer a y = 0, `soft_shore_missing=1`, pas d'effacement ; le sable au-dessus de 2 m n'attend pas.
PREUVE : `FEATURE soft-water-contract armed=1 hits=<texels de coque sous influence du rivage>` + la ligne `soft_shore_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_shore_defects == 0` dans `reports/soft-water-contract/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-water-contract device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur la plage de Sentinel Beach : le sable n'emerge pas de l'eau, les traces s'effacent la ou la vague passe..

## Hors perimetre
Ne touche a aucun fichier de l'eau ; l'ajout de la phase est demande a water-shore, pas fait ici. Tout ce qui n'est pas cet item.
