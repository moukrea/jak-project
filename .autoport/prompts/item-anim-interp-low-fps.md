> LIS D'ABORD `prompts/item-anim-interp-low-fps-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les animations saccadees quand le jeu descend vers 20 images/s

## Defaut cite
- 2026-09-06 : « Validé je pense »

## Cause connue
Owner 2026-09-05 : propre a 30 et 60, jitter a 45. Ce sont exactement les cadences ou les 60 ticks/s de la logique tombent en compte ENTIER par image (2 ticks a 30, 1 a 60). A 45 il en faudrait 1,333 : la suite reelle est 1,2,1,1,2... et le reste doit etre absorbe par l'alpha d'interpolation. `*fixed-tick-alpha*` n'a que DEUX consommateurs (cam-update.gc:246 et drawable.gc:1107) ; si le retimage d'animation ne le consomme pas, la pose saute d'un tick entier certaines images et pas d'autres — invisible aux ratios entiers, visible a 45. | 2026-09-05, essai 7 : le residu est concentre dans UN canal d'animation immobile (16 606 us). La porte precedente lisait un modele C++ au lieu de la pose dessinee.

## Livrable
Le moteur emet `anim_sweep_defects=N`, somme de verdicts qu'il publie aussi separement, sur un balayage qui DOIT contenir 45, 50, 75 et 90 img/s en plus de 30 et 60 :
  (1) chaque cadence demandee est REELLEMENT atteinte — `anim_sweep_rate_miss` = nombre de paliers dont la cadence obtenue s'ecarte de plus de 5 % de la consigne. Le Redmi plafonne vers 30 img/s : les paliers hauts se mesurent la ou ils sont atteignables (x86), et la preuve dit sur quelle machine chaque palier a tourne.
  (2) `anim_sweep_missing_rates` = 0 — aucun des six paliers 30/45/50/60/75/90 ne manque.
  (3) `anim_step_jitter_worst_us` <= 500 sur CHAQUE palier, y compris les non entiers.
  (4) `anim_step_bitexact_30` = `anim_step_bitexact_60` = 1 — le comportement aux deux cadences que l'owner declare propres ne change pas d'un bit.
N est la somme des manquements ; zero.

## Preuve exigee
`anim_sweep_defects == 0` dans `reports/anim-interp-low-fps/proof.txt`.
Le proof se produit par `lib/proof_run.sh anim-interp-low-fps device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : joue a 45 images/s (et 50, 75) : les animations doivent etre aussi lisses qu'a 30 et a 60.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
