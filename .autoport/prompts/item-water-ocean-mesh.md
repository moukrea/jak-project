# La clipmap remplace le microcode VU1, la houle reste celle de Naughty Dog

## Defaut cite
- 2026-09-10 : « pour la refonte de l'eau, si j'ai bien compris la t'as remplace l'eau Vanilla par la nouvelle avec les nouvelles vagues... Je sais pas ce qui est attendu mais je peux te dire qu'en l'etat elle est opaque (donc on voit pas les orbes sous l'eau par example), les vagues suivent une seule direction au l… »
- 2026-09-10 : « la riviere de forbidden jungle sort litteralement de son lit avec les vagues, bizarre ! Je parle de la partie qui prolonge la mer, c'est la ou il y a le mini jeu avec le pecheur »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. L'ocean mid ecrit la profondeur en GL_ALWAYS au bucket 4 AVANT le monde et le near au 63 sans Z (SPEC 2.1) : la profondeur de scene est illisible au dessin. Les 64 frames 32x32 de houle sont LUES par le gameplay a 4 endroits : elles se conservent comme couche A (SPEC 5.2).

## Livrable
Sous recharged_water : buckets 4 et 63 consomment leur DMA sans dessiner ; OceanRecharged dessine la clipmap 3 anneaux (SPEC 5.3) en W2a, couche A captee au DMA near, MEME modulo 32 que ocean-get-height, decoupe par les masques ND. Shading provisoire = l'actuel. OFF = graphe ORIGINE bit-identique. Publie water_visual_excess_mm (<= 450) et gpu_ms_ocean. PREUVE : `FEATURE water-ocean-mesh armed=1 hits=<sommets deplaces>` + `water_gameplay_height_maxdelta_mm=` seule sur sa ligne. S'AJOUTE (refus 10/09) : L'EAU NE SORT PAS DE SON LIT — Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur), la houle deborde. Mesurer par niveau et par cellule l'emprise de l'eau DESSINEE contre celle de l'origine : aucun pixel d'eau la ou l'origine n'en dessine pas, excedent publie et nul. Verifier nommement les jonctions mer/riviere.

## Preuve exigee
`water_gameplay_height_maxdelta_mm == 0` dans `reports/water-ocean-mesh/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-ocean-mesh device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur) : la houle ne deborde plus du lit. Puis la mer depuis Sandover..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF et recharged_water OFF ; tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2). La hauteur de JEU ne bouge pas.
