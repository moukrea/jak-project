# La suite du harnais ne depend plus du quota temporaire sature — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Le validateur de ao-static-probe-deterministic essai 1 confirme ao_static_defects=0 puis refuse sur test_pin_props.py::test_le_teardown_nomme_ce_qu_il_efface, rouge HERITE a la base b87ff10b773c et non consigne. Le 14/09 le superviseur rejoue ce seul test avec TMPDIR sous ~/.cache : 1 passed en 0,25 s. Le faux adb du test appelle mktemp sans chemin ; suite_gate._run_pytest herite TMPDIR et la veille/orchestrateur n en portaient pas. Quota /tmp sature deja confirme dans le handoff. Cause exacte de ce rouge pas encore demontree ; ne pas annoncer une correction sur le seul test isole vert. Complement diagnostique livraison essais 2-6 : font-urbanist.sh:137 utilise mktemp sans dossier et orchestrator.py:1816 ne passe aucun env. Parent PID 383084 sans TMPDIR/TMP/TEMP ; /tmp EDQUOT=122 mesure a l essai 4 ; rejeu historique Urbanist hors quota vert a l essai 3, mais cause exacte du timeout/gk historique non demontree. Corriger uniquement _run_pytest laisserait cette collecte exposee.

## Livrable — le contrat, en entier

Publier suite_tmp_defects=0 avec populations de banc non vides : le lanceur de suite et ses rejeux transmettent un repertoire temporaire hors /tmp a pytest ET aux outils shell enfants, meme si TMPDIR=/tmp est herite. Verifier les vrais chemins crees dans un banc isole ; temoin de repertoire temporaire indisponible nomme et refuse sans accuser le code du jeu. Reproduire le rouge test_pin_props archive ou conclure explicitement non reproduit, puis executer le fichier test_pin_props et la suite appropriee hors quota. Aucun test desactive, aucune dispense ajoutee. Preuve produite par lib/proof_run.sh, jugee par generic.sh. Couvrir aussi les scripts acquis appeles par orchestrator.close_gate : TMPDIR, TMP et TEMP transmis hors /tmp a chaque processus enfant, y compris parent sans ces variables ou avec TMPDIR=/tmp. Banc isole de fermeture avec faux acquis creant et ecrivant reellement via mktemp ; verifier refus nomme si stockage indisponible, propagation intacte d un acquis rouge et absence de contournement de la rotation. Aucun acquis reel ni appareil lance par ce banc. Le verdict suite_tmp_defects couvre aussi ces cas non vides.

## Hors perimetre

Aucun code jeu, aucun appareil, aucun nettoyage destructif de /tmp ; aucune relaxation des criteres ni modification de la preuve AO. Ne pas ouvrir de campagne moteur.

## Ou l'owner regardera

Invisible dans le jeu : eviter un refus de fermeture cause par les temporaires du banc.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-14
> Reprise superviseur requise pour : ao-static-probe-deterministic. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic.

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.
