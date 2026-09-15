> LIS D'ABORD `prompts/item-perf-mips2c-neon-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les calculs d animation et de particules coutent moins sans changer leurs resultats

## Defaut cite
- 2026-09-15 : « Reprise superviseur requise pour : perf-mips2c-neon. Ces pri… »

## Cause connue
Essai8 : premiere divergence NaN expliquee et correction rejetee. NOUVELLE LIMITE HARNAIS : ordre des operandes different entre banc extrait et fonction moteur complete x86. Comparateur a qualifier au niveau des fonctions completes avant toute autre optimisation. Essai7 candidat3D retire :343 divergences/6048 x86 et163 ARM GCC. Banc Clang repare par choix explicite des CRT ARM :330/6048, cause de premiere operation encore non attribuee. Les trois compilateurs rejettent le candidat ; aucun gain n […suite dans le contrat]

## Livrable
REPRISE HARNAIS APRES ESSAI8 : le diagnostic sample13 est termine (permutation des operandes NaN) et la correction essayee reste fausse :343/6048 x86,163 ARM GCC,153 ARM Clang. Les deux candidats ont ete rejetes, aucune livraison. Ne refaire ni leur decouverte ni une correction arithmetique de plus.
NOUVEL OBJET BORNE : qualifier le comparateur contre les FONCTIONS COMPLETES compilees. Le worker a etabli que l objet moteur complet x86 conserve l ordre du site sample13 alors que le bloc extrait l […suite dans le contrat]

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.
