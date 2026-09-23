> LIS D'ABORD `prompts/item-water-underwater-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Sous la surface, on est sous l'eau

## Defaut cite
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ND cache deja le maillage water-anim quand la camera passe sous surface - 2 m (water-anim.gc:571) ; rien d'autre n'existe (SPEC 2.2).

## Livrable
Quand la camera est sous un plan : face arriere de la surface (fenetre de Snell, reflet interne total au-dela de 48 deg), brouillard teinte par la matiere applique avant le tone map (hdr.cpp), caustiques renforcees, rayons au cran Haut+. L'etat moteur « sous l'eau » est derive de la camera et du plan, publie et compare a la hauteur de jeu poussee. SPEC 5.1, 9. Publie snell_window_deg et underwater_fog_applied. PREUVE : `FEATURE water-underwater armed=1 hits=<images rendues avec la camera sous un plan d'eau>` + la ligne `underwater_state_mismatch=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-underwater"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`underwater_state_mismatch == 0` dans `reports/water-underwater/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-underwater device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : plonger dans la mer a Sandover, et Sunken City : la surface vue par-dessous, la fenetre de Snell, un brouillard teinte.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de simulation de plongee, pas de gameplay.
