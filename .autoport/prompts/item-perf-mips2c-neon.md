> LIS D'ABORD `prompts/item-perf-mips2c-neon-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les calculs d animation et de particules coutent moins sans changer leurs resultats

## Defaut cite
- 2026-09-15 : « Reprise superviseur requise pour : perf-mips2c-neon. Ces pri… »

## Cause connue
16/09 ARBITRAGE OWNER : « t'es sur qu'il n'y a aucun gain ? je prefere si ca a plus de perfs potentielle c'est mieux, mais faut que ca casse rien ». Donc 3 essais, et SEUL oracle admis : le banc frontiere complet de l'essai 9 (notes/attempt9/frontier-parity.cpp), jamais les blocs extraits. Interdit : redecouvrir sample13, rejouer les essais 7/8, toute correction arithmetique des candidats rejetes. Livrable : un noyau vectorise qui passe la parite complete (mips2c_parity_defects=0) ET un gain MES […suite dans le contrat]

## Livrable
REPRISE HARNAIS APRES ESSAI8 : le diagnostic sample13 est termine (permutation des operandes NaN) et la correction essayee reste fausse :343/6048 x86,163 ARM GCC,153 ARM Clang. Les deux candidats ont ete rejetes, aucune livraison. Ne refaire ni leur decouverte ni une correction arithmetique de plus.
NOUVEL OBJET BORNE : qualifier le comparateur contre les FONCTIONS COMPLETES compilees. Le worker a etabli que l objet moteur complet x86 conserve l ordre du site sample13 alors que le bloc extrait l […suite dans le contrat]

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.
