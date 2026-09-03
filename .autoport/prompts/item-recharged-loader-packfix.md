# Le build ne demarrait plus sur son Honor (pack de 420 Mo)

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Le pack de 190 Mo du 27/07 demarrait, ceux de 420 Mo des 28-29/07 mouraient AVANT l'extraction. Aucun cycle n'a tourne depuis, et les builds actuels demarrent chez l'owner : verifie d'abord que l'item a encore un objet.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-loader-packfix device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la premiere installation sur ton Honor.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
