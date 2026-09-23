> LIS D'ABORD `prompts/item-recharged-secondary-motion-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Ancien chantier de physique des personnages HD (a reclasser)

## Defaut cite
- 2026-08-28 : « un terme de COM dans le tenseur valant x1,61 a x1,68 »
- 2026-09-05 : « Je pense que la physique on peut mettre vraiment tout en bas de la pile, d'ailleurs cet item date d'avant la spec des seins de Keira je pense donc on peut reclasser après le moteur de physique, les seins de Keira, de Maïa, etc. Et mettre tout ce qui est lié à la physique tout en bas de la pile »
- 2026-09-07 : « Je vois pas ce que c'est le mouvement secondaire des personnages HD et Keira mouvements brusques... Je vois pas ce que ça fout là »

## Cause connue
Le deficit et l'exces vivent dans DEUX canaux differents (angulaire 9/10 au-dessus, lineaire centre) : aucun operateur d'amplitude ne ferme les deux. Le plafond d'apex de §22 ne bornait que translation+rotation et laissait le tenseur libre a 0,59 B0. Les echelles de forme sont au niveau de l'ORGANE, appliquees par maillon.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`secondary_motion_defects == 0` dans `reports/recharged-secondary-motion/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-secondary-motion device` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucune mesure visuelle. Ne rouvre pas les items deja valides (yeux de Daxter, visiere de Keira, sangle de la veste).
