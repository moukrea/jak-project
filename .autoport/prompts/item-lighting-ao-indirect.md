# L'occlusion ambiante multiplie l'indirect, plus l'image finale

## Defaut cite
- 2026-09-10 : « l'occlusion ambiante... J'ai l'impression que l'option sert toujours l'ancien chemin d'avant la refonte, et l'ancienne faut la degager complet j'ai peur que ca se colisionne. Elle doit vivre dans le sous-menu Recharged L… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable
Prepasse profondeur+normale+rugosite. L'AO ecrit une texture ; shade() l'applique au SEUL terme indirect, en lineaire, avant le tone map. Le masque de luminance disparait, l'alpha et l'eau sont ombrees. SPEC 4.6, 4.7. PREUVE : `FEATURE lighting-ao-indirect armed=1 hits=<px dont l'indirect a recu l'AO>` + `ao_direct_leak_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene. Publicateur : armed_for(), jamais armed(). AMENDEMENT 09-09 : `ub_frame` + cache des emplacements d'uniformes (SPEC 4.3). S'AJOUTE (refus 10/09) : (a) l'option « Ambient Occlusion » pilote le chemin de CETTE refonte, pas l'ancien : compteur des deux chemins publie, l'ancien a 0. (b) l'ancienne AO est SUPPRIMEE du code, pas debranchee. (c) la ligne vit dans le sous-menu « Recharged Lighting » avec ses sous-reglages (qualite, technique, intensite).

## Preuve exigee
`ao_direct_leak_px == 0` dans `reports/lighting-ao-indirect/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-indirect x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Ambient Occlusion : les creux et les angles, et surtout les zones en plein soleil qui ne doivent plus s'assombrir.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF, et recharged_lighting OFF ; tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas. Precision par variable dans shade() : SPEC 4.4 amendee.
