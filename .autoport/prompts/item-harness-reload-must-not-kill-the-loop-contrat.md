# Un fichier a moitie ecrit ne tue plus la boucle du harnais — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

PANNE MESUREE LE 12/09 : l'orchestrateur est MORT a 15:33:16 et le harnais est reste a l'arret dix minutes, jusqu'a ce que le superviseur le relance a 15:43.
LA TRACE : `orchestrator.load_backlog()` fait `importlib.reload(backlog)` a CHAQUE tour ; `backlog.py:62` fait a son tour `importlib.reload(gate_verdict)` — ajoute expres pour que l'autorite ne diverge jamais du point de production ; `gate_verdict.py:345` appelle `impossible.arm_name`. A 15:33 le worker de `harness-naming-authority-completion` etait EN TRAIN d'editer ces deux fichiers : `gate_verdict` appelait deja le nouveau nom que `impossible` ne portait pas encore. `AttributeError` a l'import, remontee jusqu'a `main`, processus mort. Vingt minutes plus tard l'arbre etait coherent et l'import repassait.
LA LECON : le rechargement qui rend les correctifs vivants rend AUSSI la boucle tuable par n'importe quelle edition a moitie ecrite. Aucun filet n'entoure ces rechargements. Chaque item de harnais est donc un risque d'arret complet, et il n'y a personne la nuit pour relancer.

## Livrable — le contrat, en entier

`reload_survival_defects` = 0, somme de termes publies SEPAREMENT.
1. UN RECHARGEMENT QUI ECHOUE NE TUE PLUS LA BOUCLE : le module deja charge est conserve, l'echec est journalise avec le fichier, la ligne et l'exception, et le tour continue. Publier le compte de rechargements refuses et le compte de tours poursuivis malgre eux.
2. L'ETAT DEGRADE EST DIT, pas subi : tant qu'un rechargement echoue, le journal le repete a chaque tour et le texte rendu a l'owner le porte. Un harnais qui tourne sur une autorite vieille doit le DIRE, sinon on retombe sur la promotion gelee en silence que ce mecanisme corrigeait.
3. Preuve a deux bras sur une copie jetable : un `gate_verdict.py` volontairement casse doit TUER la boucle dans le bras d'AVANT et la laisser tourner dans celui d'APRES. Le stimulus est un vrai fichier incoherent, pas un drapeau.
4. Le meme filet couvre les trois rechargements de l'orchestrateur (`backlog`, `deploy_verify`, `preflight`) et celui de `backlog.py`. Publier la liste des sites couverts et le compte : quatre.

## Hors perimetre

Ne touche a aucun code du jeu. Ne retire aucun rechargement : on les protege, on ne les supprime pas.

## Ou l'owner regardera

Invisible. C'est la survie de la boucle pendant qu'un worker ecrit.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

