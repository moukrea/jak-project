# Le cout reel de l'herbe, mesure avant qu'on y touche

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, et il porte le lien vers l'investigation complete que l'owner a validee le 12/09. SPEC section 1. Le seul chiffre dont on dispose vient d'un rapport de plantage d'aout : herbe ON 4,6 a 6,0 img/s contre OFF 20,0 a 21,1 sur le Redmi, soit un facteur 3,5 pour 726 851 instances. Ce rapport le dit lui-meme : « Ce cout existait avant, il etait simplement invisible parce que le jeu mourait d'abord. » Aucune mesure fine n'existe : ni par palier, ni decomposee entre preparation, sommets et fragments, ni comparee au nombre d'instances reellement dessinees. Sans cette base, aucun gain ulterieur de la campagne n'est demontrable.

## Livrable
`grass_baseline_gaps` = 0 : aucune des grandeurs exigees ci-dessous ne manque. Un zero se lit « tout est mesure », jamais « rien a mesurer ».
1. LE COUT PAR IMAGE, sur l'appareil, herbe ALLUMEE puis ETEINTE, aux CINQ paliers, au MEME vantage et sur le MEME binaire. Publier chaque cadence et le nombre d'images de chaque releve. Un releve de moins de 300 images ne compte pas.
2. LA DECOMPOSITION : temps de preparation cote processeur, temps de dessin, et le compte d'instances SOUMISES contre celles reellement DANS LE CHAMP DE VISION. C'est l'ecart entre ces deux comptes qui chiffre ce que le culling rendra.
3. LE CHARGEMENT, decompose comme il l'est deja — source, expansion, televersement — par palier, plus la memoire des deux tampons.
4. LE COMPTE D'INSTANCES CONSTRUITES ET JAMAIS DESSINEES, publie seul sur sa ligne. Un journal d'aout l'estime a 110 472 sur 726 851 ; cet item le MESURE sur le binaire courant.
PREUVE : `FEATURE grass-baseline-cost armed=1 hits=<releves de cadence effectivement pris>` + la ligne `grass_baseline_gaps=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`grass_baseline_gaps == 0` dans `reports/grass-baseline-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-baseline-cost device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir. C'est une mesure, aucun pixel ne bouge..

## Hors perimetre
Ne change RIEN. Aucune optimisation, aucun reglage, aucun shader. Cet item mesure l'etat present et s'arrete la. Tout ce qui n'est pas cet item.
