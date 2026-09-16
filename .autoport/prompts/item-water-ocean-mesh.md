> LIS D'ABORD `prompts/item-water-ocean-mesh-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La clipmap remplace le microcode VU1, la houle reste celle de Naughty Dog

## Defaut cite
- 2026-09-10 : « la riviere de forbidden jungle sort litteralement de son lit… »

## Cause connue
16/09 ARBITRAGE OWNER : « 2 a » = 3 essais pour corriger les defauts NOMMES dans FINDINGS.txt, dans cet ordre, rien d'autre : (1) ocean_recharged.frag ecrit alpha=1 : restituer l'attenuation ND jusqu'a zero (ocean_recharged.vert:60 / OceanNear_PS2.cpp:1205) ; (2) anneaux qui se recouvrent sans morphing de bord ni culling par les 36 spheres ND (OceanRecharged.cpp:195) ; (3) houle A conservee sans DMA near et sans identite de carte, OFF/ON sans reactivation (OceanRecharged.cpp:723/733/755, OceanNear.cpp:30) ; (4) comparateur raster ND/clipmap par niveau/cellule absent (OceanRecharged.cpp:326) : le construire, c'est lui qui juge 1-3. Chaque defaut corrige = un terme publie ; un terme non mesure […suite dans le contrat]

## Livrable
Sous recharged_water : buckets 4 et 63 consomment leur DMA sans dessiner ; OceanRecharged dessine la clipmap 3 anneaux (SPEC 5.3) en W2a, couche A captee au DMA near, MEME modulo 32 que ocean-get-height, decoupe par les masques ND. Shading provisoire = l'actuel. OFF = graphe ORIGINE bit-identique. Publie water_visual_excess_mm (<= 450) et gpu_ms_ocean. PREUVE : `FEATURE water-ocean-mesh armed=1 hits=<sommets deplaces>` + `water_gameplay_height_maxdelta_mm=` seule sur sa ligne. S'AJOUTE (refus 10/09) : L'EAU NE SORT PAS DE SON LIT — Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur), la houle deborde. Mesurer par niveau et par cellule l'emprise de l'eau DESSINEE contre cel […suite dans le contrat]

## Preuve exigee
`water_gameplay_height_maxdelta_mm == 0` dans `reports/water-ocean-mesh/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-ocean-mesh device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur) : la houle ne deborde plus du lit. Puis la mer depuis Sandover..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF et recharged_water OFF ; tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2). La hauteur de JEU ne bouge pas.
