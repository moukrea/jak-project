# Les matieres PBR eclairees par la lumiere temps reel

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
25 rounds archives dans prompts/archive-Grecharged-pbr-realtime-fusion-rounds1-25.md. La branche rt-lighting du shader ignore encore les cartes PBR ; le chemin autonome u_pbr_mode est le repli faible. Jamais accepte par l'owner.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-pbr-realtime-fusion device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les matieres PBR avec l'eclairage temps reel allume.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
