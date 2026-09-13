# Le moteur de deformation : tuiles par chunk, tampons de contact, volumes balayes

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 4. Tuiles R16 compression / R8 bourrelet / R8 age par chunk, pool borne ; DEUX producteurs — rasterisation de quads (Moyen+) et CPU + glTexSubImage2D (Bas) — UN consommateur : le vertex shader de la coque ne sait pas qui a ecrit. Jamais de compute, jamais de relecture (cible flottante non relisible en GLES3). Echantillonnage des segments a la DISTANCE (rayon/2 au plus), pas aux images. Saturation par max. Normales par gradient. Teste avec un interacteur SYNTHETIQUE avant tout acteur reel.

## Livrable
`soft_deform_defects` = 0, somme de termes publies SEPAREMENT.
1. LA MEME TRAJECTOIRE DONNE LA MEME TRACE A 30, 60 ET 120 Hz : rejeu d'un segment synthetique (fixed_tick, render_pace) ; ecart de compression par texel ≤ 1 quantum ; compte de trous le long du segment = zero.
2. RIEN NE CREUSE SOUS LE SUPPORT : compression max = 1 exactement, profondeur ≤ epaisseur sur tous les texels (compte de depassements = zero), saturation par max prouvee par deux passages superposes.
3. LES DEUX PRODUCTEURS SE VALENT : la meme sequence de tampons ecrite par rasterisation et par CPU donne deux tuiles identiques a la tolerance declaree, publiee.
4. LE TRAVAIL EST BORNE : tampons par image, tuiles relaxees par image et reports comptes ; `gpu_ms_soft` publie sur x86 ; sur le Redmi, total GPU par image avant/apres et `glFenceSync` si le pilote kgsl le demande.
PREUVE : `FEATURE soft-deform-core armed=1 hits=<tampons de contact appliques>` + la ligne `soft_deform_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_deform_defects == 0` dans `reports/soft-deform-core/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-deform-core device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir sans interacteur reel ; la vue de debug montre les tuiles, les regions dirty et la compression..

## Hors perimetre
Aucun acteur du jeu : l'interacteur est synthetique. Pas de profil de matiere, pas de bourrelet fin. Tout ce qui n'est pas cet item.
