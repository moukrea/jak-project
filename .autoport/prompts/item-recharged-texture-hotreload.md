# Basculer les textures Recharged sans redemarrer le jeu

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Aucun cycle n'a tourne sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`hotreload_pixels_changed >= 1` dans `reports/recharged-texture-hotreload/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-texture-hotreload device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : bascule les textures Recharged en pleine partie, sans redemarrer.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
