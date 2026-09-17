# La cuisson de l'herbe se recuit quand son CONTENU change, automatiquement, niveau par niveau

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SPEC herbe §5, qu'aucun item ne portait (audit superviseur 17/09 sur remarque owner : « on parle de refonte »). Defaut connu : GrassRenderer.cpp:1032-1036 compare la TAILLE du .fr3, pas une empreinte de contenu ; scripts/shell/build_grass_bakes.sh n'est appele par aucun script de build, cuisson manuelle et totale.

## Livrable
`grass_bake_stale_defects` = 0, somme de termes publies SEPAREMENT.

1. EMPREINTE DE CONTENU : l'invalidation compare une empreinte du contenu du .fr3 (et des tables qui en dependent), plus jamais la taille. Publier l'empreinte lue et l'empreinte attendue par niveau.

2. DECLENCHEMENT AUTOMATIQUE : la cuisson est appelee par le script de build de livraison quand une empreinte diffère ; publier le nombre de niveaux recuits et la cause par niveau.

3. REBAKE CIBLE : seul le niveau et la categorie de donnees perimes se recuisent ; publier le temps de recuisson cible contre la recuisson totale d'avant (non nul, plus court).

4. LE TEMOIN A DEUX BRAS : un .fr3 reconstruit a TAILLE IDENTIQUE et contenu different ; `--off` = la garde de taille le laisse passer (defaut reproduit, compte), bras livre = refuse et recuit. Les deux verdicts cote a cote.

PREUVE : `FEATURE grass-bake-invalidation armed=1 hits=<comparaisons d'empreinte faites>` + la ligne `grass_bake_stale_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_bake_stale_defects == 0` dans `reports/grass-bake-invalidation/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-bake-invalidation x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : une cuisson d'herbe perimee ne peut plus etre livree..

## Hors perimetre
Ne change ni le format des bakes ni le rendu. Tout ce qui n'est pas cet item.
