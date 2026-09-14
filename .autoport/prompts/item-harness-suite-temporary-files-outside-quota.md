# La suite du harnais ne depend plus du quota temporaire sature

## Defaut cite
- 2026-09-14 : « Reprise superviseur requise pour : ao-static-probe-deterministic. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic. »

## Cause connue
Le validateur de ao-static-probe-deterministic essai 1 confirme ao_static_defects=0 puis refuse sur test_pin_props.py::test_le_teardown_nomme_ce_qu_il_efface, rouge HERITE a la base b87ff10b773c et non consigne. Le 14/09 le superviseur rejoue ce seul test avec TMPDIR sous ~/.cache : 1 passed en 0,25 s. Le faux adb du test appelle mktemp sans chemin ; suite_gate._run_pytest herite TMPDIR et la veille/orchestrateur n en portaient pas. Quota /tmp sature deja confirme dans le handoff. Cause exacte de ce rouge pas encore demontree ; ne pas annoncer une correction sur le seul test isole vert.

## Livrable
Publier suite_tmp_defects=0 avec populations de banc non vides : le lanceur de suite et ses rejeux transmettent un repertoire temporaire hors /tmp a pytest ET aux outils shell enfants, meme si TMPDIR=/tmp est herite. Verifier les vrais chemins crees dans un banc isole ; temoin de repertoire temporaire indisponible nomme et refuse sans accuser le code du jeu. Reproduire le rouge test_pin_props archive ou conclure explicitement non reproduit, puis executer le fichier test_pin_props et la suite appropriee hors quota. Aucun test desactive, aucune dispense ajoutee. Preuve produite par lib/proof_run.sh, jugee par generic.sh.

## Preuve exigee
`suite_tmp_defects == 0` dans `reports/harness-suite-temporary-files-outside-quota/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-suite-temporary-files-outside-quota x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible dans le jeu : eviter un refus de fermeture cause par les temporaires du banc..

## Hors perimetre
Aucun code jeu, aucun appareil, aucun nettoyage destructif de /tmp ; aucune relaxation des criteres ni modification de la preuve AO. Ne pas ouvrir de campagne moteur.
