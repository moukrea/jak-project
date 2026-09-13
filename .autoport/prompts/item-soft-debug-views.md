# Les vues de debug de la coque, des le debut

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 14 et artifact section 28. Chaque defaut doit se lire par niveau, chunk, nappe, materiau, profil, interacteur, palier. Les canaux statiques d'abord : eligibilite et matiere, support (fil de fer), epaisseur, direction, frontieres et falloffs, chunk et LOD (damier), bounds, rejets nommes.

## Livrable
`soft_debug_channels_missing` = 0, somme de termes publies SEPAREMENT.
1. CHAQUE CANAL DECLARE EST DESSINE : compte de canaux declares = compte de canaux rendus, publies par nom.
2. CHAQUE DEFAUT EST LOCALISE : tout compteur de defaut de la campagne publie niveau, chunk, nappe, materiau et, quand il existe, l'interacteur ; compte de defauts sans localisation = zero.
3. LE MODE DEBUG NE COUTE RIEN ETEINT : instrument_cost_us par image en mode normal ≤ 200 (perf-instrument-cost).
4. LES CANAUX DYNAMIQUES ONT LEUR PLACE RESERVEE : tuile, region dirty, compression, bourrelet, age, interacteurs, volumes balayes, priorite, cause d'eviction — declares, remplis par les items suivants, comptes comme absents tant qu'ils ne le sont pas.
PREUVE : `FEATURE soft-debug-views armed=1 hits=<canaux de debug dessines>` + la ligne `soft_debug_channels_missing=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_debug_channels_missing == 0` dans `reports/soft-debug-views/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-debug-views x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Un reglage de debug qui colore la coque par canal ; rien en jeu normal..

## Hors perimetre
Aucun canal dynamique rempli ici. Tout ce qui n'est pas cet item.
