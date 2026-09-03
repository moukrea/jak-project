# Le mouvement secondaire des personnages HD (physique de Keira)

## Defaut cite
- 2026-08-27 : « la spec a 100%, pas de raccourcis »
- 2026-08-28 : « le budget d'execution du chantier pre-specifie est de QUATRE lignes »
- 2026-08-28 : « un terme de COM dans le tenseur valant x1,61 a x1,68 »

## Cause connue
Le deficit et l'exces vivent dans DEUX canaux differents (angulaire 9/10 au-dessus, lineaire centre) : aucun operateur d'amplitude ne ferme les deux. Le plafond d'apex de §22 ne bornait que translation+rotation et laissait le tenseur libre a 0,59 B0. Les echelles de forme sont au niveau de l'ORGANE, appliquees par maillon.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-secondary-motion device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les personnages HD en mouvement brusque.

## Hors perimetre
Aucune mesure visuelle. Ne rouvre pas les items deja valides (yeux de Daxter, visiere de Keira, sangle de la veste).
