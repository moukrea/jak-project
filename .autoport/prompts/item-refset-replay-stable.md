# La garde de reference d'image doit rendre le meme chiffre deux fois de suite

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Mesure du 2026-09-06 consignee dans .autoport/refset/README.md : trois rejeux du MEME binaire (sha=fbf84cf9802b7c11) contre les MEMES references octet pour octet ont rendu maxdiff 188, puis 0, puis 0. Tant que l'instrument est intermittent, toute porte a diff nul brule des essais pour des raisons d'instrument. Le moteur emet `refset_replay_flaky` = nombre de paires de rejeux consecutifs, meme binaire et memes references, dont les maxdiff different. Zero sur au moins cinq rejeux. La CAUSE doit etre nommee, pas contournee par une tolerance : un seuil qui absorbe 188 absorbe aussi un vrai defaut. Le sens de l'erreur est rassurant (l'instabilite fait monter maxdiff, donc faux ROUGE jamais faux vert) mais le cout est reel.

## Preuve exigee
`refset_replay_flaky == 0` dans `reports/refset-replay-stable/proof.txt`.
Le proof se produit par `lib/proof_run.sh refset-replay-stable x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Ne pas relever la tolerance de comparaison pour faire taire le symptome.
