# Savoir quel chemin d'eclairage a dessine chaque pixel, et figer les deux references

## Defaut cite
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un rée… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Cinq composites d'ombrage exclusifs choisis par quatre interrupteurs globaux : personne ne peut dire lequel a dessine un pixel, et aucun item suivant ne peut prouver qu'il n'a rien casse. SPEC 2.3.

## Livrable
Le moteur publie la repartition des draws monde entre les cinq chemins (la somme egale le total) et le temps GPU par passe. Plus DEUX jeux d'images de reference rejouables — ORIGINE (master OFF) et RECHARGED — et le script qui les compare, rejoue a la fermeture de chaque item suivant. SPEC 7.3. PREUVE : `FEATURE lighting-census armed=1 hits=<draws monde classes dans un des cinq chemins>` + la ligne `refset_replay_maxdiff=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-census"), jamais armed(), et n'en ecris pas un second. CORRECTION 2026-09-07 : les jeux de reference sont INSUFFISANTS. Huit vues d'un seul point (`village1-hut`), en 320x180, dont le quart superieur est du brun a zero pixel sature — aucun CIEL. Un defaut de ciel ne pouvait donc etre vu par aucune porte qui s'appuie dessus, et lighting-hdr est passe au vert pendant que l'owner voyait le ciel blanc. Les trois jeux (ORIGINE-TOTAL, ORIGINE-LUMIERE, RECHARGED) doivent couvrir au moins trois niveaux EXTERIEURS avec du ciel visible sur au moins 15 % de l'image, plus l'interieur actuel. `refset_sky_views` >= 3 et `refset_levels` >= 3, publies par le moteur.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle.
