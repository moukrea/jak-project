# Du Redmi au Snapdragon 8 Elite : des paliers, et chaque ajout debrayable

## Defaut cite
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Les reglages d'eclairage sont epars, sans echelle coherente ni detection, et le Redmi a servi de cible alors qu'il est le pire cas du harnais — et que son goulot est le fil GOAL, pas le GPU. SPEC 1.2 et 1.3.

## Livrable
Une echelle Tres bas -> Ultra qui pose toutes les valeurs, un palier de depart deduit du materiel et du temps de frame, chaque reglage ecrasable. Deux prereglages nommes Original et Recharged, et un raccourci de bascule. Chaque fonctionnalite prouve que son OFF est bit-identique a son absence. SPEC 6.2, 6.3 et 6.4. PREUVE : `FEATURE lighting-presets armed=1 hits=<reglages effectivement poses par le prereglage>` + la ligne `preset_apply_mismatch=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-presets"), jamais armed(), et n'en ecris pas un second. A QUITTE CET ITEM le 2026-09-06 : le regroupement des reglages n'est plus differe ici, la hierarchie est decidee (SPEC 6.2) et recharged_lighting est cree par lighting-hdr. Il reste les paliers, l'auto-detection et la preuve d'orthogonalite.

## Preuve exigee
`preset_apply_mismatch == 0` dans `reports/lighting-presets/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-presets device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : l'echelle de qualite, et le raccourci Original/Recharged.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle.
