# La mare d'eco noire non rendue dans la cinematique d'intro

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Ouvert en juin, bloque par l'orchestrateur sans raison enregistree. La mare d'eco noire n'est pas rendue sur arm64, donc la forme d'ottsel de Daxter apparait trop tot.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh echo-pool x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la cinematique de nouvelle partie, quand Daxter tombe dans l'eco noire.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
