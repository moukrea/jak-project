# Le Redmi tient son budget : Bas et Moyen mesures sur l'appareil

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 13. Sur le Redmi seul le TOTAL GPU par image est un chiffre (repartition par bucket inexploitable) ; goal_busy_ms ≤ baseline ; budgets proposes Bas 0,6 + 0,2 ms, Moyen 1,5 + 0,3 ms ; watchdog kgsl ~2 s.

## Livrable
`soft_device_budget_defects` = 0, somme de termes publies SEPAREMENT.
1. BAS ET MOYEN SOUS BUDGET : total GPU par image et goal_busy_ms publies avec et sans la coque, sur 300 images minimum a un vantage nomme, ecart ≤ budget du palier.
2. AUCUN BLOCAGE : compte de blocages kgsl sur 300 images = zero, glFenceSync compte si pose.
3. LA MATRICE EST AJUSTEE PAR LA MESURE : valeurs de la section 12 revisees et publiees avec le chiffre qui les justifie.
4. LA MEMOIRE EST CELLE DECLAREE : memoire de tuiles et de coque publiee par palier.
PREUVE : `FEATURE soft-device-budget armed=1 hits=<images mesurees sur l appareil>` + la ligne `soft_device_budget_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_device_budget_defects == 0` dans `reports/soft-device-budget/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-device-budget device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : La cadence en jeu sur le telephone, coque allumee en Bas et en Moyen, et la chauffe sur 10 minutes..

## Hors perimetre
Pas Ultra. Tout ce qui n'est pas cet item.
