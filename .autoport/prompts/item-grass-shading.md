> LIS D'ABORD `prompts/item-grass-shading-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe cesse d'etre un aplat : du relief par la couleur, pas par la geometrie

## Defaut cite
- 2026-09-20 : « Aucune variation sur la verticale, c'est juste de haut en ba… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 7. Le degrade racine-pointe existe et il est correct. Ce qui manque est la variation SPATIALE : `inst_gcol` n'est PAS un echantillonnage du terrain sous le brin, c'est la moyenne de la TEXTURE ENTIERE du draw source, mise en cache par identifiant. Avec trois noms de texture admis, il existe au plus TROIS couleurs de sol dans tout le champ, et UNE seule en pratique sur Geyser Rock. Le commentai […suite dans le contrat]

## Livrable
`grass_shading_defects` = 0, somme de termes publies SEPAREMENT.
1. LA VARIATION SPATIALE EXISTE : publier le nombre de couleurs de base distinctes dans le champ, aujourd'hui egal a un, au-dessus d'un plancher declare. Et la publier PAR TOUFFE, pas par triangle.
2. LE DEGRADE EST MESURE : publier l'ecart de luminance entre la racine et la pointe d'un meme brin, au-dessus d'un plancher declare, et le meme ecart entre la face eclairee et la face opposee.
3. LA LUMIERE CUITE GAGNE EN RESOLUTION : p […suite dans le contrat]

## Preuve exigee
`grass_shading_defects == 0` dans `reports/grass-shading/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-shading device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Niveau d'entrainement, de pres. Deux oui/non : (1) chaque touffe a-t-elle SA teinte (une touffe plus jaune, la voisine plus bleue), au lieu de montrer toutes les teintes ? (2) la variation de couleur va-t-elle au-dela du simple degrade bas-sombre / haut-clair (cotes, brins, ombre portee entre brins) ?.

## Hors perimetre
Aucun ajout de geometrie. Aucune dependance a un systeme graphique indisponible sur les backends reellement supportes. Tout ce qui n'est pas cet item.
