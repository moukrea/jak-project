# Chaque techno d'eau a son reglage, son echelle, et un OFF prouve

## Defaut cite
- 2026-09-09 : « la refonte de l'eau doit pouvoir être toggled off individuellement aussi, ou on retrouve l'eau vanilla. »
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Le pire appareil est un banc d'essai, pas la cible (regle 6) : un palier ne pose que des defauts, chaque reglage est libre. lod-force-ocean etait un reglage mort (SPEC 2.5).

## Livrable
Les 12 reglages de SPEC 7 au menu Recharged avec leurs echelles, le palier auto-deduit (= palier eclairage par defaut) qui ne verrouille rien, l'integration aux prereglages Original / Recharged. Pour CHAQUE reglage : un binaire-temoin ou la couche n'est pas compilee et la preuve que OFF lui est bit-identique (refset_replay_maxdiff=0), et la preuve que chaque cran intermediaire est pose. Budgets SPEC 6 mesures sur les quatre classes. Libelles selon recharged-settings-case-l10n. PREUVE : `FEATURE water-presets armed=1 hits=<reglages d'eau effectivement poses par le prereglage>` + la ligne `water_preset_apply_mismatch=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-presets"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`water_preset_apply_mismatch == 0` dans `reports/water-presets/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-presets device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : la ligne Eau Rechargee, la qualite de l'eau, et chaque reglage individuel (tessellation, rides, rivage, refraction, reflets, caustiques, eclaboussures, cascades, resolution).

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Aucun reglage de menu remplace par une propriete de debug dans le build livre.
