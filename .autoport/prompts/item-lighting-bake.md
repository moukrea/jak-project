# Le baked devient l'indirect, et l'original reste intact

## Defaut cite
- 2026-07-19 : « moins beau que du baked »
- 2026-09-03 : « j'imagine qu'ils utilisent du baked aussi, faut qu'on soit en phase, et que malgre nos changements ca suive le ton du jeu original, juste plus "real time possible" »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Le chemin valide fait color.rgb *= rt_mod : le soleil teinte le bake au lieu de s'y ajouter, donc il ne peut jamais eclairer ce que le bake a laisse sombre. La decomposition a pourtant une forme CLOSE. SPEC 3.1 et 5.2.

## Livrable
tools/light_bake ecrit <niveau>.lightbake A COTE du fr3 : palette B, residu artistique, visibilite du ciel, AO, normales coudees, sondes, regimes, emetteurs. La palette A n'est JAMAIS reecrite. Le moteur verifie la reconstruction au chargement. SPEC 5 en entier, format octet par octet en 5.4. PREUVE : `FEATURE lighting-bake armed=1 hits=<index de couleur reconstruits et verifies>` + la ligne `bake_reconstruction_maxdelta=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-bake"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`bake_reconstruction_maxdelta <= 2` dans `reports/lighting-bake/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-bake x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les quatre niveaux de la premiere livraison : village1, swamp, lavatube, snow.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. Les 22 autres niveaux viennent apres les quatre de la premiere livraison.
