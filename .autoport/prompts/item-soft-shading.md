# La trace se voit dans la lumiere : normales, albedo, rugosite, dans shade()

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 6. Normale par gradient de tuile fournie a la prepasse (RG16F octaedrique) et a shade() via Surface.N ; compression et age modulent Surface.albedo et Surface.roughness AVANT shade() ; pas de second pipeline de matiere ; jamais dFdx pour N.

## Livrable
`soft_shading_defects` = 0, somme de termes publies SEPAREMENT.
1. LA NORMALE DE TRACE EXISTE DANS LA PREPASSE : ecart angulaire moyen entre normale de repos et normale de trace, lu dans la cible RG16F sur un vantage nomme, au-dessus d'un plancher declare.
2. L'AO REPOND : ecart moyen du R8 d'AO dans une trace vs a cote, publie, non nul.
3. ALBEDO ET RUGOSITE SUIVENT LE PROFIL : valeurs publiees dans et hors trace par matiere ; sens declare respecte (compacte plus brillante, profonde plus rugueuse au fond).
4. AUCUN dFdx POUR N, AUCUN SECOND MODELE : compte de sites = zero ; tout passe par Surface.
PREUVE : `FEATURE soft-shading armed=1 hits=<fragments de coque ombres avec une normale de trace>` + la ligne `soft_shading_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_shading_defects == 0` dans `reports/soft-shading/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-shading device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le fond d'un sillon est plus sombre et rugueux ; une empreinte dans la neige compacte brille un peu..

## Hors perimetre
Pas d'humidite (c'est l'eau). Tout ce qui n'est pas cet item.
