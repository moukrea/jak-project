# Le banc de la suite n'herite plus de l'environnement de celui qui la lance

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker de hdr-shadow-range (essai 3, 13/09, FINDINGS.txt). `tests/harness/test_proof.py:129` (`_juge`) construit son environnement par `dict(os.environ, ...)` : le banc herite TOUT l'environnement de qui lance la suite. Depuis une session de worker, `AUTOPORT_ATTEMPT_ID` est pose : le validateur exige alors `proof_attempt_id=` dans la preuve synthetique, que `_proof` n'ecrit pas, et `test_une_preuve_produite_par_la_machine_passe` — le CONTROLE POSITIF du banc — rougit. Un test qui change de verdict selon qui le lance n'est pas un test.

## Livrable
`bench_env_leaks` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE : compte de tests du banc dont le verdict differe entre un lancement depuis un shell nu et depuis une session de worker (variables `AUTOPORT_*` posees), publie par nom ; non nul.
2. LE BANC PART D'UN ENVIRONNEMENT MAITRISE : liste blanche des variables transmises (PATH, HOME, LANG et celles que le test pose lui-meme), tout `AUTOPORT_*` du parent retire sauf mention explicite ; publier la liste effective.
3. LE CONTROLE POSITIF TIENT SOUS LES DEUX LANCEMENTS : `test_une_preuve_produite_par_la_machine_passe` vert depuis un shell nu ET depuis un environnement de worker simule ; les deux verdicts publies.
4. AUCUNE FUITE APRES : compte de variables du parent lisibles depuis un test sonde = celles de la liste blanche, zero autre.
PREUVE : `FEATURE harness-test-bench-does-not-inherit-the-worker-env armed=1 hits=<tests du banc executes sous environnement maitrise>` + la ligne `bench_env_leaks=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`bench_env_leaks == 0` dans `reports/harness-test-bench-does-not-inherit-the-worker-env/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-test-bench-does-not-inherit-the-worker-env x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais qui ne meurent plus pour cette cause..

## Hors perimetre
Ne change ni le validateur ni ce que la preuve synthetique doit contenir. Tout ce qui n'est pas cet item.
