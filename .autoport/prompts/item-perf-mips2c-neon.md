> LIS D'ABORD `prompts/item-perf-mips2c-neon-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les calculs d animation et de particules coutent moins sans changer leurs resultats

## Defaut cite
- 2026-09-15 : « Reprise superviseur requise pour : perf-mips2c-neon. Ces pri… »

## Cause connue
Essais5/6 : absence de troisieme cible et references phase1 incompletes provoquaient un arret avant toute experimentation locale. Reprise bornee a un candidat, sans appareil ; criteres finaux conserves. DIAGNOSTIC DE REPRISE : l hypothese de boucles source scalaires sans SIMD est refutee par old-codegen-review.txt. Le compilateur vectorisait deja os et joints. bones.gc active *use-new-bones* et execute new-bones-mtx-calc-asm, pas bones-mtx-calc : 0 operation de ce dernier et 0 image qualifiee, m […suite dans le contrat]

## Livrable
ETAPE DE REPRISE LOCALE DU15/09 : les essais5/6 ont identifie les deux prealables manquants. Ne pas refaire ces audits. Le prochain essai doit produire UN candidat concret avant/apres, compile et compare localement. Les trois cibles sont une exigence de livraison finale, PAS un prealable a toute preparation : l absence de troisieme cible ou de references Android n interdit pas cet essai local. Choisir parmi les chemins joints/particules deja observes actifs ; commencer par examiner les transfert […suite dans le contrat]

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.
