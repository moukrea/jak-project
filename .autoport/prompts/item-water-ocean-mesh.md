# La clipmap remplace le microcode VU1, la houle reste celle de Naughty Dog

## Defaut cite
- 2026-09-09 : « la refonte de l'eau doit pouvoir être toggled off individuellement aussi, ou on retrouve l'eau vanilla. »
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. L'ocean mid ecrit la profondeur en GL_ALWAYS au bucket 4 AVANT le monde et le near au 63 sans Z (SPEC 2.1) : la profondeur de scene est illisible au dessin. Les 64 frames 32x32 de houle sont LUES par le gameplay a 4 endroits : elles se conservent comme couche A (SPEC 5.2).

## Livrable
Sous recharged_water, les buckets 4 et 63 consomment leur DMA sans dessiner (renderers ND vivants) ; un nouveau OceanRecharged dessine la clipmap 3 anneaux (SPEC 5.3) a la position W2a, couche A captee au DMA near (ocean-near-add-heights) en texture R8 32x32 avec le MEME modulo 32 que ocean-get-height, decoupe par les masques ND, far-color au loin. Shading provisoire = l'actuel. OFF = graphe ORIGINE bit-identique (refset_replay_maxdiff=0). Publie aussi water_visual_excess_mm (<= 450) et gpu_ms_ocean. Nouveau .cpp dans game/ ET android/CMakeLists.txt. PREUVE : `FEATURE water-ocean-mesh armed=1 hits=<sommets de clipmap deplaces>` + la ligne `water_gameplay_height_maxdelta_mm=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-ocean-mesh"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`water_gameplay_height_maxdelta_mm == 0` dans `reports/water-ocean-mesh/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-ocean-mesh device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la mer depuis le village de Sandover et la plage : meme houle qu'avant, sans trou ni fente, et l'eau vanilla a l'identique quand Eau Rechargee est OFF.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de nouveau shading, pas de rivage, pas de rides : c'est l'item 2 et suivants.
