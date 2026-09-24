# La separation de l'eclairage en ambiante + soleil (validee) ne peut plus regresser : un acquis la protege

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
L'owner a VALIDE lighting-bake le 24/09 ; aucun `acquis/lighting-bake.sh` ne le protege. La grandeur existe deja : le jeu verifie au chargement que ambiante + soleil recolles redonnent l'original (bake_reconstruction_maxdelta, ecart d'un demi-cran sur 255) sur village1, swamp, lavatube, snow.

## Livrable
1. `.autoport/acquis/lighting-bake.sh` : lit bake_reconstruction_maxdelta par niveau (4 niveaux) et rend non nul au-dela du seuil valide.
2. CONTROLE POSITIF : fausser la reconstruction d'un niveau -> l'acquis rougit et nomme le niveau. CONTROLE NEGATIF : binaire courant -> 0.
3. Publier `lighting_bake_acquis_defects` et le nombre de niveaux mesures (0 niveau = defaut).

## Preuve exigee
`lighting_bake_acquis_defects == 0` dans `reports/acquis-lighting-bake/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-lighting-bake x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder dans le jeu : garde-fou du harnais..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
