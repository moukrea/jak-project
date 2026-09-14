> LIS D'ABORD `prompts/item-lighting-ao-indirect-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'occlusion ambiante multiplie l'indirect, plus l'image finale

## Defaut cite
- 2026-09-13 : « Occlusion ambiante : j'ai poussé à l'extrême les tests... Du… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable
`ao_owner_defects` = 0 — LA PORTE LIT DESORMAIS TOUS LES POINTS DE L'OWNER, plus un seul terme. Somme publiee SEPAREMENT de : (1) `ao_direct_leak_px` ; (2) `ao_pattern_over_ceiling` = 1 si `ao_flatstep_worst_delivered` > 10 a un palier quelconque (le damier des facades) ; (3) `ao_sway_gap_px` (prepasse contre scene sous vent, shrub ET TIE : `ao_geom_tie_absent_px` compte dedans) ; (4) `ao_on_alpha_device_px` (alpha respecte SUR L'APPAREIL, vent allume) ; (5) `ao_static_cam_delta_px` (camera fixe, vent coupe : 0 texel bouge) ; (6) `ao_contact_band_px` (largeur de la bande sans AO aux contacts) ; (7) `ao_high_not_fullres` = 1 si `ao_scale_q2` < 1,0 (Eleve doit etre pleine resolution ou son filtre bilateral publie). Chaque terme est publie avec son denominateur.
RENVOYE PAR LE SUPERVISEUR le 14/09 (pas un refus de l'owner) : l'essai 7 a ete promu « a tester » sur `ao_direct_leak_px == 0` al […suite dans le contrat]

## Preuve exigee
`ao_owner_defects == 0` dans `reports/lighting-ao-indirect/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-indirect device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting > Ambient Occlusion : essaie CHAQUE palier de qualite — aucun damier ni pixelisation. Et regarde les shrubs : plus d'ombre qui flotte au-dessus des brins d'herbe..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF, et recharged_lighting OFF ; tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas. Precision par variable dans shade() : SPEC 4.4 amendee.
