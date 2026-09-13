# Les instruments et la baseline des surfaces meubles : l'epaisseur des congeres, mesuree

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC sections 1 et 13. L'epaisseur de la neige profonde est INCONNUE : les 19 ilots deepsnow de snow sont la collision de congeres TIE, et aucun outil ne relie un draw a son prototype et a ses instances. Le Redmi n'a pas de chronometre GPU par passe exploitable (l'ocean absorbe 92-95 %). La densite du sol n'est auditee que sur village1 (arete 4,885 m). Aucun compteur de triangles de collision par materiau n'existe.

## Livrable
`soft_baseline_gaps` = 0, somme de termes publies SEPAREMENT.
1. L'ECART VISIBLE/COLLISION DES CONGERES EST MESURE : un decodeur des arbres TIE du .fr3 attribue chaque ilot deepsnow (19 a snow, 18 a ogre) a son prototype et publie l'ecart vertical surface rendue -> collision (min, mediane, max par ilot, en unites ET en m). C'est la decision 4 de la SPEC qui en depend.
2. LA TABLE MATERIAU x NIVEAU EST VERSIONNEE : `tools/soft_bake --census` publie triangles et aire par pat-material et par niveau, pour les 25 niveaux, et retrouve les chiffres de l'investigation (snow 5968 / 72 181 m² ; deepsnow 762 / 2 332 m² ; beach sand 10 294 / 90 299 m²) a l'unite pres.
3. LA DENSITE DU SOL EST CONNUE OU ELLE COMPTE : arete moyenne et mediane des triangles tfrag eligibles pour snow, beach, training, village1 ; compteur de sommets et triangles DESSINES par systeme et par image.
4. LE COUT D'UNE TUILE EST MESURE SUR LES DEUX CIBLES : `glTexSubImage2D` d'une R16 64² et 128², et la rasterisation d'un quad dans une R16 attachee, en ms par tuile, sur x86 et sur le Redmi, publies cote a cote.
PREUVE : `FEATURE soft-baseline armed=1 hits=<grandeurs de baseline publiees>` + la ligne `soft_baseline_gaps=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_baseline_gaps == 0` dans `reports/soft-baseline/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-baseline device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : des chiffres. La vue de debug colore la collision par materiau..

## Hors perimetre
Aucune coque, aucune deformation, aucun changement d'image. Tout ce qui n'est pas cet item.
