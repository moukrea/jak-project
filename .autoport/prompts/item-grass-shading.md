# L'herbe cesse d'etre un aplat : du relief par la couleur, pas par la geometrie

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 7. Le degrade racine-pointe existe et il est correct. Ce qui manque est la variation SPATIALE : `inst_gcol` n'est PAS un echantillonnage du terrain sous le brin, c'est la moyenne de la TEXTURE ENTIERE du draw source, mise en cache par identifiant. Avec trois noms de texture admis, il existe au plus TROIS couleurs de sol dans tout le champ, et UNE seule en pratique sur Geyser Rock. Le commentaire de `grass.vert:462-468` qui annonce « per-location » est FAUX. La seule variation spatiale reelle est la lumiere cuite du centroide du TRIANGLE : 11 080 valeurs pour 847 000 brins.

## Livrable
`grass_shading_defects` = 0, somme de termes publies SEPAREMENT.
1. LA VARIATION SPATIALE EXISTE : publier le nombre de couleurs de base distinctes dans le champ, aujourd'hui egal a un, au-dessus d'un plancher declare. Et la publier PAR TOUFFE, pas par triangle.
2. LE DEGRADE EST MESURE : publier l'ecart de luminance entre la racine et la pointe d'un meme brin, au-dessus d'un plancher declare, et le meme ecart entre la face eclairee et la face opposee.
3. LA LUMIERE CUITE GAGNE EN RESOLUTION : publier le nombre de valeurs d'eclairage distinctes servies au champ, avant et apres. Une valeur par triangle devient une valeur par touffe.
4. LA DIRECTION ARTISTIQUE TIENT : aucune de ces variations ne depasse une amplitude declaree. Le rendu reste stylise, il ne part pas vers le photorealisme, et l'owner juge.
PREUVE : `FEATURE grass-shading armed=1 hits=<brins ayant recu une couleur derivee de leur touffe>` + la ligne `grass_shading_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_shading_defects == 0` dans `reports/grass-shading/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-shading device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement, de pres : les brins ne doivent plus ressembler a des aplats de couleur. Base plus sombre, pointe plus claire, et des touffes voisines qui ne sont pas de la meme teinte..

## Hors perimetre
Aucun ajout de geometrie. Aucune dependance a un systeme graphique indisponible sur les backends reellement supportes. Tout ce qui n'est pas cet item.
