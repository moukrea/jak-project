# La boule de neige, le yakow, les montures : traces d'objets qui bougent vraiment

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 5. snow-ball = sphere r 2,5 m qui roule le long d'une courbe (transv, quat) ; yakow, seagull, pelican ; zoomer/flutflut = collider 'racer/'flut de Jak. Les caisses ne bougent JAMAIS : objets statiques cuits, pas interacteurs. Aucun OBB dans le jeu.

## Livrable
`soft_object_defects` = 0, somme de termes publies SEPAREMENT.
1. LA BOULE LAISSE UNE TRACE CONTINUE : longueur / distance ≥ 0,98, largeur constante (ecart-type publie).
2. UN OBJET IMMOBILE CESSE DE CREUSER : compte de tampons d'un objet a transv nul apres saturation = zero.
3. LES MONTURES CREUSENT PLUS LARGE : largeur de trace en mode racer et flut > mode normal, publiee.
4. AUCUNE CAISSE N'EST UN INTERACTEUR : compte de tampons issus d'un crate = zero ; leurs depressions viennent du bake.
PREUVE : `FEATURE soft-objects armed=1 hits=<tampons d objets appliques>` + la ligne `soft_object_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_object_defects == 0` dans `reports/soft-objects/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-objects device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : La boule de neige de Snowy Mountain laisse un sillon ; le yakow de Sandover marque le sable..

## Hors perimetre
Pas les ennemis, pas les PNJ immobiles. Tout ce qui n'est pas cet item.
