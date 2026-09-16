> LIS D'ABORD `prompts/item-grass-baseline-cost-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le cout reel de l'herbe, mesure avant qu'on y touche

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
16/09 superviseur — CAUSE DES CINQ ESSAIS A VIDE (2 a 6) : « Ne change RIEN » a ete lu comme une interdiction d'ajouter les instruments, et chaque essai a attendu une « autorisation des instruments neutres » qui n'a jamais ete demandee a personne. C'est une erreur de lecture : AJOUTER les compteurs, chronometres et le site de recensement (note_hit_for + AUTOPORT_FEATURE_SITE, publication de `grass_baseline_gaps` et des dix fenetres) EST le livrable. Un instrument qui n'ecrit aucun pixel n'est pas un changement de rendu. « Ne change RIEN » interdit seulement optimisation, reglage et shader. Aucune autorisation supplementaire n'est a attendre : instrumenter, mesurer sur l'appareil USB, produir […suite dans le contrat]

## Livrable
`grass_baseline_gaps` = 0 : aucune des grandeurs exigees ci-dessous ne manque. Un zero se lit « tout est mesure », jamais « rien a mesurer ».
1. LE COUT PAR IMAGE, sur l'appareil, herbe ALLUMEE puis ETEINTE, aux CINQ paliers, au MEME vantage et sur le MEME binaire. Publier chaque cadence et le nombre d'images de chaque releve. Un releve de moins de 300 images ne compte pas.
2. LA DECOMPOSITION : temps de preparation cote processeur, temps de dessin, et le compte d'instances SOUMISES contre celles reellement DANS LE CHAMP DE VISION. C'est l'ecart entre ces deux comptes qui chiffre ce que le culling rendra.
3. LE CHARGEMENT, decompose comme il l'est deja — source, expansion, televersement — pa […suite dans le contrat]

## Preuve exigee
`grass_baseline_gaps == 0` dans `reports/grass-baseline-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-baseline-cost device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir. C'est une mesure, aucun pixel ne bouge..

## Hors perimetre
Ne change RIEN. Aucune optimisation, aucun reglage, aucun shader. Cet item mesure l'etat present et s'arrete la. Tout ce qui n'est pas cet item.
