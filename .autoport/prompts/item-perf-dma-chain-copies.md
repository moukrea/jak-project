# La chaine DMA n'est plus parcourue cinq fois par image

## Defaut cite
- 2026-09-15 : « pour les perfs DMA truc muche, c'est validepour les perfs DMA truc muche, c'est validé »

## Cause connue
Android : sonde d'envoi (android_gfx.cpp:1253-1304), copieur par tranches de 128 Ko (:1360, dma_copy.cpp:89-170), sonde A37 cote GL (:500-508), count_chain_bytes (android_opengl_renderer.cpp:1193-1200), puis le rendu = 5 parcours. PC : zero copie (opengl.cpp:58). Le volume copie n'est jamais journalise (370-450 Ko de chaine).

## Livrable
Sonde et copie fusionnees, parcours de diagnostic derriere une prop, dma_chain_bytes_copied et dma_chain_walks_per_frame publies (<= 2 : copie + rendu). refset_replay_maxdiff == 0.

## Preuve exigee
`dma_chain_walks_per_frame <= 2` dans `reports/perf-dma-chain-copies/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-dma-chain-copies device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel.

## Hors perimetre
Le zero-copie PC n'est pas transpose (les stomps arm64 exigent la copie). Ne touche a aucune feature validee.
