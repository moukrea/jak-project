# L'herbe cesse d'etre un aplat : du relief par la couleur, pas par la geometrie — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 7. Le degrade racine-pointe existe et il est correct. Ce qui manque est la variation SPATIALE : `inst_gcol` n'est PAS un echantillonnage du terrain sous le brin, c'est la moyenne de la TEXTURE ENTIERE du draw source, mise en cache par identifiant. Avec trois noms de texture admis, il existe au plus TROIS couleurs de sol dans tout le champ, et UNE seule en pratique sur Geyser Rock. Le commentaire de `grass.vert:462-468` qui annonce « per-location » est FAUX. La seule variation spatiale reelle est la lumiere cuite du centroide du TRIANGLE : 11 080 valeurs pour 847 000 brins.

20/09 RETOUR OWNER (JAK-121) : « Aucune variation sur la verticale, c'est juste de haut en bas, et non c'est pas coherent… en gros j'ai l'impression qu'on voit plus ou moins toutes les teintes sur toutes les touffes, nul ! ». LA PORTE mesurait un degrade et une dispersion GLOBALE de teinte ; elle ne regardait pas la coherence PAR TOUFFE. PERIMETRE : (1) teinte de base tiree PAR TOUFFE (meme racine que les silhouettes), faible dispersion dans la touffe, forte entre touffes voisines ; (2) le degrade vertical reste mais s'attenue (il n'est plus la seule variation) ; (3) une variation laterale : assombrissement des brins interieurs / face sous le vent, ou ombre d'auto-occlusion simple par densite locale. PORTE : dispersion de teinte INTRA-touffe <= 1/3 de la dispersion INTER-touffes (mesurees sur les couleurs de sommets emises) ; part de la variance de couleur expliquee par la seule hauteur <= 60 %. Capture jointe.

20/09 09:45 RETOUR OWNER (JAK-121), PRIORITAIRE sur ma reformulation de 08:55 : « Un degrade SUR LA LONGUEUR DU BRIN j'ai dit, c'est-a-dire pas de haut en bas, ca donnera du relief a ces geometries tres simples, c'est pas forcement pour une touffe, ca permet de creer en plus des changements de geometrie des variations de TYPES de brins etc ». LECTURE : le degrade actuel est un haut/bas (hauteur monde ou ecran) ; il doit etre parametre sur la longueur PROPRE du brin (t de 0 a la racine a 1 a la pointe, LE LONG de la courbure, y compris quand le brin est couche par le vent ou le pas), et la palette varie par TYPE de brin (les 6 silhouettes de grass-blade-variants), pas d'abord par touffe. La teinte par touffe, l'assombrissement par densite et la face eclairee/opposee (SPEC §7) restent des complements, pas le coeur. PORTE : (1) la couleur emise d'un sommet est fonction de sa coordonnee t LE LONG du brin, pas de sa hauteur monde : sur des brins couches (vent force), la correlation couleur/t reste >= 0,9 et la correlation couleur/hauteur-monde tombe ; (2) les 6 types de brins ont des palettes distinctes (distance de teinte entre types >= seuil) ; (3) le degrade est visible sur toute la longueur (amplitude racine->pointe >= 25 % de luminance). Capture jointe.

COHERENCE HERBE (owner 20/09, sur les tickets variantes ET couleur : « a voir avec l'ensemble des tickets lies… j'aurais cru que c'etait compris depuis le debut ») : les chantiers d'herbe (silhouettes, couleur, vent, exposition, pas, biomes) forment UN SEUL rendu que l'owner juge d'un coup. Avant de coder : lire la SPEC-refonte-herbe EN ENTIER et TOUS les retours owner des items grass-* (owner_feedback de chacun) ; ne rien defaire de ce qu'un autre item d'herbe a livre ; si un choix ici contraint un autre item d'herbe, l'ecrire dans FINDINGS avec '-> item:<id>'. Les silhouettes par touffe (grass-blade-variants) sont le socle : couleur et vent s'y appuient et passent APRES.

20/09 11:40 OWNER (JAK-121) : « Attention les types de brins simples niveau geometrie impliquent aussi des "especes differentes" au meme titre que les degrades et compagnie, ca joue sur la coherence des types, biomes, especes differentes ». LECTURE : une silhouette + sa palette + sa raideur au vent + sa hauteur = une ESPECE d'herbe ; les six types ne sont pas six formes interchangeables mais six especes coherentes (une lame haute et souple n'a pas la palette ni la raideur d'un jonc court). Cette coherence par ESPECE est le fil qui relie silhouettes (grass-blade-variants), couleur (grass-shading), vent (grass-wind) et biomes (grass-biome-profiles, qui choisit QUELLES especes poussent ou). Un item d'herbe ne definit jamais un parametre par type sans le rattacher a l'espece : une table unique des especes (nom, silhouette, palette, hauteur, raideur, densite) est la source, les shaders la lisent, les biomes en tirent des proportions.

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

Niveau d'entrainement, de pres, sur le build nomme dans le commentaire « build publie ». Trois oui/non : (1) le degrade suit-il LE BRIN sur sa longueur (sombre a la racine, clair a la pointe, en suivant sa courbure), au lieu d'un simple haut/bas de l'ecran ? (2) les differents TYPES de brins (lame, fine, large, faux, jonc, touffu) ont-ils des teintes ou des palettes differentes ? (3) l'ensemble a-t-il du relief, ou reste-t-il un aplat ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-20
> Aucune variation sur la verticale, c'est juste de haut en bas, et non c'est pas cohérent… en gros j'ai l'impression qu'on voit plus ou moins toutes les teintes sur toutes les touffes, nul !

### 2026-09-20
> Un dégradé sur la longueur du brin j'ai dit, c'est à dire pas de haut en bas, ça donnera du relief à ces géométries très simples, c'est pas forcément pour une touffe, ça permet de créer en plus des changements de géométrie des variations de types de brins etc etc, à voir avec l'ensemble des tickets d'herbe… j'aurai cru que c'était compris depuis le début ça commence à me saouler

### 2026-09-20
> Attention les types de brins simple niveau géométrie impliquent aussi des "espèces différentes" a même titre que les dégradés et compagnie, ça joue sur la cohérence des types, biomes, espèces différentes et compagnie

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

