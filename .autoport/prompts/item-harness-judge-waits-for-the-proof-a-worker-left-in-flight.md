> LIS D'ABORD `prompts/item-harness-judge-waits-for-the-proof-a-worker-left-in-flight-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un worker qui laisse une course de preuve EN VOL n'est plus ferme apres 45 s : le juge attend la course, bornee par proof_timeout, avant de trancher

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
16/09, trois essais brules en 50 min (ao-prepass-tie-alpha 14 et 15, perf-mips2c-neon 10). Le worker Claude lance `proof_run.sh <id> device` en arriere-plan, arme un moniteur sur son PID et TERMINE SON TOUR (« En vol — j'attends la notification », « I'll wait for the run rather than poll »). En mode `-p` cette notification n'arrive jamais : l'orchestrateur voit un `result`, compte 45 s d'inactivite (STALL_POST_RESULT_SEC, orchestrator.py:143) et fait `_kill('post-result')`, puis juge : `proof.tx […suite dans le contrat]

## Livrable
`inflight_kill_defects` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : compte d'essais archives dont le journal porte « fermeture forcee » (post-result) ET dont le validateur dit « proof.txt absent » ou « course ECRIVAIT » ; publie par item ; non nul (au moins 3 le 16/09).

2. LE JUGE ATTEND LA COURSE : quand le worker a emis son resultat et se tait, l'orchestrateur regarde d'abord si une course de preuve de CET item est vivante (verrou/PID de proof_run.sh, ou process […suite dans le contrat]

## Preuve exigee
`inflight_kill_defects == 0` dans `reports/harness-judge-waits-for-the-proof-a-worker-left-in-flight/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-judge-waits-for-the-proof-a-worker-left-in-flight x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais AO et perf qui ne meurent plus avec leur preuve en vol..

## Hors perimetre
Ne change pas STALL_POST_RESULT_SEC pour tout le monde ; ne relance jamais une course ; ne touche ni au validateur ni a proof_run.sh au-dela du verrou/PID lisible. Tout ce qui n'est pas cet item.
