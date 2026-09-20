# L'herbe cesse d'etre un aplat : du relief par la couleur, pas par la geometrie — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 7. Le degrade racine-pointe existe et il est correct. Ce qui manque est la variation SPATIALE : `inst_gcol` n'est PAS un echantillonnage du terrain sous le brin, c'est la moyenne de la TEXTURE ENTIERE du draw source, mise en cache par identifiant. Avec trois noms de texture admis, il existe au plus TROIS couleurs de sol dans tout le champ, et UNE seule en pratique sur Geyser Rock. Le commentaire de `grass.vert:462-468` qui annonce « per-location » est FAUX. La seule variation spatiale reelle est la lumiere cuite du centroide du TRIANGLE : 11 080 valeurs pour 847 000 brins.

20/09 RETOUR OWNER (JAK-121) : « Aucune variation sur la verticale, c'est juste de haut en bas, et non c'est pas coherent… en gros j'ai l'impression qu'on voit plus ou moins toutes les teintes sur toutes les touffes, nul ! ». LA PORTE mesurait un degrade et une dispersion GLOBALE de teinte ; elle ne regardait pas la coherence PAR TOUFFE. PERIMETRE : (1) teinte de base tiree PAR TOUFFE (meme racine que les silhouettes), faible dispersion dans la touffe, forte entre touffes voisines ; (2) le degrade vertical reste mais s'attenue (il n'est plus la seule variation) ; (3) une variation laterale : assombrissement des brins interieurs / face sous le vent, ou ombre d'auto-occlusion simple par densite locale. PORTE : dispersion de teinte INTRA-touffe <= 1/3 de la dispersion INTER-touffes (mesurees sur les couleurs de sommets emises) ; part de la variance de couleur expliquee par la seule hauteur <= 60 %. Capture jointe.

## Livrable — le contrat, en entier

`grass_shading_defects` = 0, somme de termes publies SEPAREMENT.
1. LA VARIATION SPATIALE EXISTE : publier le nombre de couleurs de base distinctes dans le champ, aujourd'hui egal a un, au-dessus d'un plancher declare. Et la publier PAR TOUFFE, pas par triangle.
2. LE DEGRADE EST MESURE : publier l'ecart de luminance entre la racine et la pointe d'un meme brin, au-dessus d'un plancher declare, et le meme ecart entre la face eclairee et la face opposee.
3. LA LUMIERE CUITE GAGNE EN RESOLUTION : publier le nombre de valeurs d'eclairage distinctes servies au champ, avant et apres. Une valeur par triangle devient une valeur par touffe.
4. LA DIRECTION ARTISTIQUE TIENT : aucune de ces variations ne depasse une amplitude declaree. Le rendu reste stylise, il ne part pas vers le photorealisme, et l'owner juge.
PREUVE : `FEATURE grass-shading armed=1 hits=<brins ayant recu une couleur derivee de leur touffe>` + la ligne `grass_shading_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Aucun ajout de geometrie. Aucune dependance a un systeme graphique indisponible sur les backends reellement supportes. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Niveau d'entrainement, de pres. Deux oui/non : (1) chaque touffe a-t-elle SA teinte (une touffe plus jaune, la voisine plus bleue), au lieu de montrer toutes les teintes ? (2) la variation de couleur va-t-elle au-dela du simple degrade bas-sombre / haut-clair (cotes, brins, ombre portee entre brins) ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-20
> Aucune variation sur la verticale, c'est juste de haut en bas, et non c'est pas cohérent… en gros j'ai l'impression qu'on voit plus ou moins toutes les teintes sur toutes les touffes, nul !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

