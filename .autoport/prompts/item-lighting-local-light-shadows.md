# Les lampes et torches projettent des ombres (Jak devant une lampe), comme reglage : coupe sur les paliers bas, actif sur les paliers hauts et Ultra

## Defaut cite
- 2026-09-25 : « trop coûteux pour un téléphone… MAIS TU ME CASSES LE COUILLES ! C'est pas qu'à target de téléphone, ça vise aussi les PC ultra haut de gamme putain de merde! »

## Cause connue
Demande de l'owner le 25/09 (JAK-52) apres que le superviseur a repris la justification de la SPEC §4.9 (« Pas d'ombre par lumiere locale : hors budget sur toute la gamme basse ») : le projet vise AUSSI les PC ultra haut de gamme. Regle du projet : concevoir depuis Ultra, chaque techno est un REGLAGE, le pire appareil est un banc d'essai, pas une limite. La SPEC dit elle-meme « Une ombre projetee par une lumiere locale est un chantier ulterieur » : c'est celui-ci.

## Livrable
1. Ombres des lumieres locales (les N lumieres les plus proches/importantes, N par palier) : carte d'ombre par lumiere (cubique ou atlas), acteurs (Jak, PNJ) ET decor dynamique projetes.
2. Un reglage « Ombres des lampes » : Off / N lumieres, pose par les paliers (Off sur Tres bas/Bas, actif a partir de Haut, maximal en Ultra) et ecrasable ; Off = bit-identique a l'absence.
3. UNE grandeur : de nuit sous un lampadaire de Sandover avec le reglage actif, rapport sol-a-l'ombre-de-Jak / sol-eclaire-par-la-lampe ; ombre lisible. Publier le cout par image (regimes alternes dans une course).
4. Puis livrer : l'owner juge.

## Preuve exigee
`local_shadow_defects == 0` dans `reports/lighting-local-light-shadows/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-local-light-shadows x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : De nuit a Sandover, reglage d'ombres de lampes actif (palier haut/Ultra) : Jak devant un lampadaire ou une torche projette une ombre au sol et sur les murs..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
