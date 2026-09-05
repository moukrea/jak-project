# L'occlusion ambiante multiplie l'indirect, plus l'image finale

## Defaut cite
- 2026-09-03 : « L'occlusion Ambiante screen... Je comprend pas ca, on l'a fait tout a la fin du rendu par dessus le reste plutot qu'en composant integral du rendu comme font (je suppose, a toi de dire) les jeux modernes ? »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable
Prepasse profondeur+normale+rugosite. L'AO ecrit une texture ; shade() l'applique au SEUL terme indirect, en lineaire, avant le tone map. Le masque de luminance disparait, l'alpha et l'eau sont enfin ombrees. SPEC 4.6 et 4.7. PREUVE : `FEATURE lighting-ao-indirect armed=1 hits=<pixels dont le terme indirect a recu l'AO>` + la ligne `ao_direct_leak_px=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-ao-indirect"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`ao_direct_leak_px == 0` dans `reports/lighting-ao-indirect/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-indirect x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Ambient Occlusion : les creux et les angles, et surtout les zones en plein soleil qui ne doivent plus s'assombrir.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas.
