> LIS D'ABORD `prompts/item-lighting-shadows-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Deux astres, deux jeux d'ombres, et les acteurs qui en projettent

## Defaut cite
- 2026-09-25 : « Alors ça fonctionne, on a bien l'ombre sur les ponts et comp… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Une seule cascade attribuee a « l'astre le plus haut », avec fondu et EMA pour cacher une bascule qui n'a pas lieu d'etre : les deux astres sont leves ENSEMBLE 3 h 30 par jour. Et aucun acteur n'entre dans la carte. SPEC 3.4 et 4.8.

RETOUR DE TEST DE L'OWNER (24/09, build 60d16fa6, sur telephone) : avec le reglage « vraies ombres », il voit TOUJOURS les aplats PS2 ; seul « Aucune » ch […suite dans le contrat]

## Livrable
Atlas unique tuile, cascades stabilisees pour l'astre dominant, une tuile pour le second, les acteurs dans la passe de profondeur avec leur maillage skinne, ombres de contact sur la prepasse. L'aplat PS2 reste le repli et le mode Original. SPEC 4.8. PREUVE : `FEATURE lighting-shadows armed=1 hits=<pixels de sol ombres par un acteur>` + la ligne `shadow_caster_classes=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof […suite dans le contrat]

## Preuve exigee
`shadow_caster_classes == 4` dans `reports/lighting-shadows/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-shadows device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'ombre de Jak et des PNJ au sol, et le matin quand les deux astres sont leves ; et dans le marais et le tube de lave : l'ombre doit montrer que la lumiere ne vient plus d'un soleil invisible (verification reportee de lighting-regimes, owner 25/09)..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. L'aplat PS2 de shadow-geo n'est pas retire ici : il devient le repli et le mode original (decision owner 2026-09-03). Son remplacement en champ proche est lighting-actors.
