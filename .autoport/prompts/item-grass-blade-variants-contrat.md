# Plusieurs silhouettes de brins simples, au lieu d'une seule forme hachee — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Trois geometries existent, toutes generees depuis `gl_VertexID` sans aucun asset, mais ce sont trois REPRESENTATIONS DE DISTANCE, pas trois especes : un ruban de 10 sommets en proche, deux quads croises en moyen, une carte suspendue pour l'overhang. Hauteur, courbure, largeur, teinte et phase sont cinq hachages de la MEME forme. L'owner l'a dit et c'est verifie.

20/09 RETOUR OWNER (JAK-120) : « tu fais juste des touffes avec toutes les geometries, pas de touffes d'herbe differentes, pas de variations de hauteur… certaines des geometries… on voit clairement leurs polygones de pres, c'est nul ! ». LA PORTE ETAIT AVEUGLE a ces trois choses : elle comptait la diversite des BRINS, pas l'organisation en TOUFFES. PERIMETRE : (1) la variante se tire au niveau de la TOUFFE (hachage de la racine de touffe), avec une silhouette dominante par touffe et une minorite (<= 20 %) d'autres formes ; les touffes voisines different ; (2) hauteur PAR TOUFFE : facteur 0,7-1,3 tire par touffe, en plus de la variation par brin ; (3) de pres (< 6 m), aucun polygone visible : profil de largeur lisse et assez de segments pour que l'angle entre deux segments consecutifs reste sous 12 degres a la distance de LOD 0 ; le compte de sommets soumis ne monte pas (replier les rangees comme aujourd'hui). PORTE : part de touffes a silhouette dominante >= 80 % ; ecart-type de hauteur ENTRE touffes >= 15 % ; angle max entre segments a LOD 0 <= 12 degres, mesure sur les sommets emis ; sommets soumis inchanges. Capture jointe au passage en test.

COHERENCE HERBE (owner 20/09, sur les tickets variantes ET couleur : « a voir avec l'ensemble des tickets lies… j'aurais cru que c'etait compris depuis le debut ») : les chantiers d'herbe (silhouettes, couleur, vent, exposition, pas, biomes) forment UN SEUL rendu que l'owner juge d'un coup. Avant de coder : lire la SPEC-refonte-herbe EN ENTIER et TOUS les retours owner des items grass-* (owner_feedback de chacun) ; ne rien defaire de ce qu'un autre item d'herbe a livre ; si un choix ici contraint un autre item d'herbe, l'ecrire dans FINDINGS avec '-> item:<id>'. Les silhouettes par touffe (grass-blade-variants) sont le socle : couleur et vent s'y appuient et passent APRES.

20/09 11:10 RETOUR OWNER (JAK-120) : « Toutes les touffes se ressemblent… tres mid… on voit plus les polygones et on a il semblerait des hauteurs differentes par contre ». ACQUIS : plus de polygones visibles, hauteurs par touffe. RESTE : les touffes ne se DISTINGUENT pas entre elles. La porte (part de touffes a silhouette dominante >= 80 %) est tenue et pourtant l'owner ne voit pas de difference : la silhouette dominante ne suffit pas a distinguer deux touffes si les 6 silhouettes se ressemblent a distance de jeu ou si la repartition tire presque toujours la meme. PERIMETRE : (1) mesurer la distribution REELLE des silhouettes dominantes sur une zone (si 2 des 6 font 80 % des touffes, c'est ca) et l'equilibrer ; (2) rendre les silhouettes distinguables a 3-8 m : ecart de hauteur moyenne entre types >= 30 %, ecart de largeur >= 40 %, port different (droit / courbe / retombant) ; (3) densite et nombre de brins PAR TOUFFE varies (une touffe clairsemee a cote d'une touffe dense). PORTE : sur une zone de 10x10 m, entropie de la silhouette dominante >= 2 bits sur 6 types ; ecart-type des hauteurs moyennes de touffes >= 20 % ; ecart-type du nombre de brins par touffe >= 25 %. Le rendu se juge AVEC la couleur par type (grass-shading) : les deux chantiers sont lies, la couleur par type est ce qui rendra les silhouettes lisibles.

20/09 11:40 OWNER (JAK-121) : « Attention les types de brins simples niveau geometrie impliquent aussi des "especes differentes" au meme titre que les degrades et compagnie, ca joue sur la coherence des types, biomes, especes differentes ». LECTURE : une silhouette + sa palette + sa raideur au vent + sa hauteur = une ESPECE d'herbe ; les six types ne sont pas six formes interchangeables mais six especes coherentes (une lame haute et souple n'a pas la palette ni la raideur d'un jonc court). Cette coherence par ESPECE est le fil qui relie silhouettes (grass-blade-variants), couleur (grass-shading), vent (grass-wind) et biomes (grass-biome-profiles, qui choisit QUELLES especes poussent ou). Un item d'herbe ne definit jamais un parametre par type sans le rattacher a l'espece : une table unique des especes (nom, silhouette, palette, hauteur, raideur, densite) est la source, les shaders la lisent, les biomes en tirent des proportions.

## Livrable — le contrat, en entier

`grass_variant_defects` = 0, somme de termes publies SEPAREMENT.
1. LES VARIANTES EXISTENT ET SONT DISTRIBUEES : publier le compte de brins par variante et le compare aux proportions declarees par le profil. Un ecart au-dela d'une tolerance declaree est le defaut.
2. LE BUDGET GEOMETRIQUE TIENT : publier le nombre de sommets par variante et le total de sommets transformes par image, compare a la mesure de reference. La diversite ne se paie pas en geometrie.
3. LE PALIER COMMANDE LE NOMBRE DE VARIANTES, et la selection reste DETERMINISTE : un brin donne recoit la meme variante a tous les paliers qui la proposent. Publier le compte de brins changeant de variante entre deux paliers : zero.
4. AUCUNE MODELISATION : publier le compte d'assets de maillage charges par le systeme d'herbe, qui vaut zero. C'est l'ordre explicite de l'owner.
PREUVE : `FEATURE grass-blade-variants armed=1 hits=<brins ayant recu une variante>` + la ligne `grass_variant_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Pas de fleurs, pas de fougeres, pas de plantes detaillees, aucun asset de maillage. Ne change ni la couleur ni le vent. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Niveau d'entrainement, de pres. UNE question : deux touffes voisines se distinguent-elles au premier coup d'oeil (silhouette dominante differente, hauteur differente, port different), ou toutes les touffes se ressemblent-elles encore ? (polygones et hauteurs par touffe : acquis par l'owner).

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-19
> Ce chantier ne touche pas le jeu ? Qu'es-ce ce que tu racontes, comment tu peux être autant à côté de la plaque ?

### 2026-09-20
> Alors tu fais juste des touffes avec toutes les géométries, pas de touffes d'herbe différentes, pas de variations de hauteur… certaines des géométrie… on voit clairement leurs polygones de près, c'est nul !

### 2026-09-20
> Idem à voir àvec l'ensemble des tickets lié

### 2026-09-20
> Toutes les touffes se ressemblent… je sais pas si un autre chantier traite ça mais en l'état j'ai l'impression que c'est très mid… on voit plus les polygones et on a il semblerait des hauteurs différentes par contre

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

