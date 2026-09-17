> LIS D'ABORD `prompts/item-water-ocean-mesh-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La clipmap remplace le microcode VU1, la houle reste celle de Naughty Dog

## Defaut cite
- 2026-09-17 : « Alors je sais pas si c'est intentionnel mais la nouvelle mer… »

## Cause connue
17/09 RETOUR OWNER sur c42de2 : « la nouvelle mer ressemble trait pour trait à l'ancienne, sauf que elle est opaque » ; « sur le title screen l'eau est noire » ; « avant cette reprise les vagues ressemblaient plus à des vagues ». La porte de hauteur de jeu a tenu, mais l'alpha a 1 (defaut n°1 du FINDINGS, non traite) est une REGRESSION visible, l'ecran titre noir aussi. 3 essais : d'abord A et B (regressions), puis C. Ne pas toucher a la hauteur de jeu (water_gameplay_height_maxdelta_mm reste a 0).

16/09 ARBITRAGE OWNER : « 2 a » = 3 essais pour corriger les defauts NOMMES dans FINDINGS.txt, dans cet ordre, rien d'autre : (1) ocean_recharged.frag ecrit alpha=1 : restituer l'attenuation ND j […suite dans le contrat]

## Livrable
Sous recharged_water : buckets 4 et 63 consomment leur DMA sans dessiner ; OceanRecharged dessine la clipmap 3 anneaux (SPEC 5.3) en W2a, couche A captee au DMA near, MEME modulo 32 que ocean-get-height, decoupe par les masques ND. Shading provisoire = l'actuel. OFF = graphe ORIGINE bit-identique. Publie water_visual_excess_mm (<= 450) et gpu_ms_ocean. PREUVE : `FEATURE water-ocean-mesh armed=1 hits=<sommets deplaces>` + `water_gameplay_height_maxdelta_mm=` seule sur sa ligne. S'AJOUTE (refus 10/09) : L'EAU NE SORT PAS DE SON LIT — Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur), la houle deborde. Mesurer par niveau et par cellule l'emprise de l'eau DESSINEE contre cel […suite dans le contrat]

## Preuve exigee
`water_ocean_owner_defects == 0` dans `reports/water-ocean-mesh/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-ocean-mesh device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Forbidden Jungle, la riviere qui prolonge la mer (mini-jeu du pecheur) : la houle ne deborde plus du lit. Puis la mer depuis Sandover..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF et recharged_water OFF ; tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2). La hauteur de JEU ne bouge pas.
