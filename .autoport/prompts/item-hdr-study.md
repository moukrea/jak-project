> LIS D'ABORD `prompts/item-hdr-study-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Comprendre pourquoi le HDR ne gagne rien dans les ombres, avant d'y retoucher

## Defaut cite
- 2026-09-11 : « je me demande si l'espace couleur dans lequel on calcule le… »

## Cause connue
Cinq refus de l'owner sur hdr-display-output, cinq corrections a l'aveugle, et la meme plainte a chaque fois : aucun gain dans les ombres, un effet qui se resume a « les endroits brillants brillent plus ». Owner 11/09 : « je me demande si l'espace couleur dans lequel on calcule le HDR est assez riche pour commencer... avant la prochaine iteration faut vraiment creuser le sujet en profondeur ». Il a raison : chaque tour a regle une courbe sans jamais etablir CE QUI ENTRE dans cette courbe. Et le code avoue deja une partie du probleme — le gain dans les ombres publie compare des nombres de paliers de quantification, pas de la luminance.

## Livrable
Un document, pas une correction : `reports/hdr-study/ETUDE.md`. AUCUN changement de rendu. Il repond, mesure a l'appui, a six questions — chacune avec le chiffre releve sur l'appareil et le site de code qui le produit. (1) LA CHAINE COMPLETE, du calcul d'eclairage au pixel envoye a la dalle : chaque etape nommee, son format et sa precision (nombre de bits, virgule flottante ou entier, espace lineaire ou encode). Ou la scene perd-elle sa plage ? (2) LE TAMPON DE CALCUL est-il assez riche ? Publier sa profondeur reelle et la plage de valeurs qu'il contient sur du jeu reel — combien de scenes depassent 1,0, et de combien. (3) LES OMBRES : quelle est la plus petite difference de luminance distinguable, en nits livres, en SDR puis en HDR, sur les memes images ? Si le HDR n'en gagne pas, DIRE POURQUOI. (4) LA COURBE VARIE-T-ELLE VRAIMENT dans le temps sur un parcours reel, et de combien ? L'ow […suite dans le contrat]

## Preuve exigee
`hdr_study_questions_open == 0` dans `reports/hdr-study/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-study device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : c'est une etude, elle ne change pas le rendu ; owner_test=false.

## Hors perimetre
AUCUNE correction, aucun changement de rendu, aucune option ajoutee. Ce chantier produit un document et des mesures. Corriger avant d'avoir compris est precisement ce qui a coute cinq refus.
