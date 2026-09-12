# La suite de tests du harnais redevient un signal : verte quand rien ne casse

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
DEUX SIGNALEMENTS DU 12/09 (reports/harness-commit-paths-all-or-nothing/FINDINGS.txt), verifies par le worker dans un worktree DETACHE sur HEAD, donc sans aucune de ses modifications.
1. SEPT tests echouent deja a HEAD : cinq dans `test_backlog.py`, deux dans `test_cli_backend.py`. « Personne ne sait depuis quand. » Une suite qui rougit en permanence n'est plus un signal : un vrai regressif s'y noie.
2. `tests/harness/test_proof_busy.py::test_prompt_mentionnant_compilateur_ne_bloque_pas` lit les processus REELS de la machine : il echoue des qu'un vrai `ninja` ou `clang++` tourne. Constate pendant ce chantier, constructeur arm64 actif. Faux rouge aleatoire selon ce que fait le constructeur au meme moment.
CONTEXTE CONNU : `test_real_backlog_only_fails_lint_on_missing_gates` exige que le backlog livre n'ait qu'une famille de reproche ; il en reste trois budgets au-dessus du defaut sans raison ecrite, et c'est une decision de l'OWNER, pas un defaut de code. Ce chantier dit lesquels des sept echecs sont des defauts et lesquels sont des attentes de decision.

## Livrable
`test_suite_defects` = 0, somme de termes publies SEPAREMENT.
1. Les sept echecs sont TRIES et publies un par un : defaut de code, attente d'une decision de l'owner, ou test devenu faux. Publier le compte de chaque categorie. Un total sans ventilation ne vaut rien.
2. Aucun test ne depend plus de ce que la machine fait au meme moment : celui qui lit les processus reels lit une liste INJECTEE. Prouver par deux courses, l'une avec un `ninja` factice en cours, l'autre sans, memes resultats.
3. La suite passe en entier, ou chaque echec restant porte la raison ECRITE de sa survie et le nom de qui doit trancher. Publier la liste.
4. Publier la date du dernier commit ou la suite etait entierement verte, pour que « depuis quand » cesse d'etre inconnu.

## Preuve exigee
`test_suite_defects == 0` dans `reports/harness-test-suite-is-not-a-signal/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-test-suite-is-not-a-signal x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est le filet du harnais lui-meme..

## Hors perimetre
Ne touche a aucun code du jeu. Ne desactive aucun test pour le faire passer, et n'ecrit aucune raison « budget : » a la place de l'owner.
