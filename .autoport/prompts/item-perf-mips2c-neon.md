> LIS D'ABORD `prompts/item-perf-mips2c-neon-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les calculs d animation et de particules coutent moins sans changer leurs resultats

## Defaut cite
- 2026-09-15 : « Reprise superviseur requise pour : perf-mips2c-neon. Ces pri… »

## Cause connue
DIAGNOSTIC DE REPRISE : l hypothese de boucles source scalaires sans SIMD est refutee par old-codegen-review.txt. Le compilateur vectorisait deja os et joints. bones.gc active *use-new-bones* et execute new-bones-mtx-calc-asm, pas bones-mtx-calc : 0 operation de ce dernier et 0 image qualifiee, malgre joints/particules compares sans ecart. Le candidat os grossit de 716 a 4812 octets ; aucun gain demontre. Refset USB : hutte maxdiff233 et deux references plage absentes ; A/B x86 egalement incompl […suite dans le contrat]

## Livrable
Lot 1 : gnd_oob_check compile hors du build quand la prop n'est pas armee. Lot 2 : NEON (arm64) et SSE (x86) sur les trois noyaux les plus chauds selon goal_bucket_ms_*, bit-identiques (hd-mtx-check-all, A/B x86, ripple.cpp intact ou bit-identique car l'eau lit ripple-find-height). mips2c_parity_defects = ecarts bit a bit entre chemin scalaire et vectoriel sur 600 images + (refset_replay_maxdiff != 0). Gain publie par seau.
REPRISE DIAGNOSTIQUE OBLIGATOIRE AVANT NOUVELLE COURSE :
1. Auditer le c […suite dans le contrat]

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.
