> LIS D'ABORD `prompts/item-harness-reload-must-not-kill-the-loop-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un fichier a moitie ecrit ne tue plus la boucle du harnais

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
PANNE MESUREE LE 12/09 : l'orchestrateur est MORT a 15:33:16 et le harnais est reste a l'arret dix minutes, jusqu'a ce que le superviseur le relance a 15:43.
LA TRACE : `orchestrator.load_backlog()` fait `importlib.reload(backlog)` a CHAQUE tour ; `backlog.py:62` fait a son tour `importlib.reload(gate_verdict)` — ajoute expres pour que l'autorite ne diverge jamais du point de production ; `gate_verdict.py:345` appelle `impossible.arm_name`. A 15:33 le worker de `harness-naming-authority-completion` etait EN TRAIN d'editer ces deux fichiers : `gate_verdict` appelait deja le nouveau nom que `impossible` ne portait pas encore. `AttributeError` a l'import, remontee jusqu'a `main`, processus mort […suite dans le contrat]

## Livrable
`reload_survival_defects` = 0, somme de termes publies SEPAREMENT.
1. UN RECHARGEMENT QUI ECHOUE NE TUE PLUS LA BOUCLE : le module deja charge est conserve, l'echec est journalise avec le fichier, la ligne et l'exception, et le tour continue. Publier le compte de rechargements refuses et le compte de tours poursuivis malgre eux.
2. L'ETAT DEGRADE EST DIT, pas subi : tant qu'un rechargement echoue, le journal le repete a chaque tour et le texte rendu a l'owner le porte. Un harnais qui tourne sur une autorite vieille doit le DIRE, sinon on retombe sur la promotion gelee en silence que ce mecanisme corrigeait.
3. Preuve a deux bras sur une copie jetable : un `gate_verdict.py` volontairement cas […suite dans le contrat]

## Preuve exigee
`reload_survival_defects == 0` dans `reports/harness-reload-must-not-kill-the-loop/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-reload-must-not-kill-the-loop x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la survie de la boucle pendant qu'un worker ecrit..

## Hors perimetre
Ne touche a aucun code du jeu. Ne retire aucun rechargement : on les protege, on ne les supprime pas.
