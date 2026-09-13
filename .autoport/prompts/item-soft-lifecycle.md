# Le cycle de vie : vieillissement, eviction, persistance, changement de palier

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 8. Relaxation a cadence fixe par dt accumule ; pool borne, LRU distance x age ; une tuile evincee laisse une copie R8 au quart, reappliquee au retour ; un chunk sous un objet actif ne s'evince pas ; persistance tant que le niveau vit, checkpoint et mort compris ; rien en sauvegarde ; changement de palier = reechantillonnage, JAMAIS de remise a zero.

## Livrable
`soft_lifecycle_defects` = 0, somme de termes publies SEPAREMENT.
1. LE POOL EST BORNE EN TOUTE CIRCONSTANCE : memoire de tuiles publiee par image ≤ budget du palier, y compris a un teleport et a un changement de palier.
2. L'EVICTION EST INVISIBLE : ecart de hauteur entre une tuile evincee-restauree et l'originale ≤ tolerance declaree ; compte de tuiles evincees sous un objet actif = zero.
3. LA PERSISTANCE EST CELLE DECLAREE : traces presentes apres checkpoint et mort de Jak (compte non nul), absentes apres changement de niveau (compte = zero).
4. LE CHANGEMENT DE PALIER CONSERVE : compte de tuiles conservees / total au passage Moyen -> Haut -> Moyen, publie ; compte de remises a zero = zero.
PREUVE : `FEATURE soft-lifecycle armed=1 hits=<tuiles gerees par le pool>` + la ligne `soft_lifecycle_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_lifecycle_defects == 0` dans `reports/soft-lifecycle/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-lifecycle device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Une trace vieillit et s'adoucit ; en revenant dans une zone, les sillons majeurs sont encore la..

## Hors perimetre
Pas les LOD geometriques. Tout ce qui n'est pas cet item.
