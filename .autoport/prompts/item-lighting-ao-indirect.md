> LIS D'ABORD `prompts/item-lighting-ao-indirect-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'occlusion ambiante multiplie l'indirect, plus l'image finale

## Defaut cite
- 2026-09-17 : « Top, mais étrangement je vois aucun ticket liés à ce dernier… »

## Cause connue
17/09 OWNER (Linear) : « Toujours pertinent ? Bloqué pourquoi ? ». Reponse : c'est le ticket PARENT de l'AO. Ses 7 termes sont tous mesures ; 5 sont acquis (Eleve pleine resolution, damier des facades, alpha appareil, fuite du direct, bande de contact), le 6e (sonde stable) est fait, le 7e est le raccord mur/toit de la hutte, en cours dans ao-prepass-tie-alpha. Quand l'enfant passe, cet item se rejoue UNE fois pour mesurer les 7 termes ensemble sur le meme binaire et fermer l'AO. Pas de redecoup […suite dans le contrat]

## Livrable
`ao_owner_defects` = 0 — LA PORTE LIT DESORMAIS TOUS LES POINTS DE L'OWNER, plus un seul terme. Somme publiee SEPAREMENT de : (1) `ao_direct_leak_px` ; (2) `ao_pattern_over_ceiling` = 1 si `ao_flatstep_worst_delivered` > 10 a un palier quelconque (le damier des facades) ; (3) `ao_sway_gap_px` (prepasse contre scene sous vent, shrub ET TIE : `ao_geom_tie_absent_px` compte dedans) ; (4) `ao_on_alpha_device_px` (alpha respecte SUR L'APPAREIL, vent allume) ; (5) `ao_static_cam_delta_px` (camera fixe […suite dans le contrat]

## Preuve exigee
`ao_owner_defects == 0` dans `reports/lighting-ao-indirect/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-indirect device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting > Ambient Occlusion : essaie CHAQUE palier de qualite — aucun damier ni pixelisation. Et regarde les shrubs : plus d'ombre qui flotte au-dessus des brins d'herbe..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF, et recharged_lighting OFF ; tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas. Precision par variable dans shade() : SPEC 4.4 amendee.
