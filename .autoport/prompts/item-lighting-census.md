# Savoir quel chemin d'eclairage a dessine chaque pixel, et figer les deux references

## Defaut cite
- 2026-09-03 : « on a deja implemente du rela time lighting et un support de PBR qu'on a jamais finalise (et probablement tres bancal) »
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Cinq composites d'ombrage exclusifs choisis par quatre interrupteurs globaux : personne ne peut dire lequel a dessine un pixel, et aucun item suivant ne peut prouver qu'il n'a rien casse. SPEC 2.3.

## Livrable
Le moteur publie la repartition des draws monde entre les cinq chemins (la somme egale le total) et le temps GPU par passe. Plus DEUX jeux d'images de reference rejouables — ORIGINE (master OFF) et RECHARGED — et le script qui les compare, rejoue a la fermeture de chaque item suivant. SPEC 7.3. PREUVE : `FEATURE lighting-census armed=1 hits=<draws monde classes dans un des cinq chemins>` + la ligne `refset_replay_maxdiff=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-census"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle.
