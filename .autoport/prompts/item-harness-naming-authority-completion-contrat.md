# L'autorite de nommage devient la SEULE, et les bancs cessent de compter des litteraux — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SEPT SIGNALEMENTS DU 12/09 (reports/harness-impossible-single-namer/FINDINGS.txt). Le chantier precedent a fait de `lib/impossible.py` l'autorite de nommage pour l'ECRIVAIN et le LECTEUR. Il reste des nommeurs paralleles et des bancs qui mesurent la mauvaise chose.
1. `proof_run.sh:424` : l'effacement de l'etat REFABRIQUE son nom au lieu de le demander a l'autorite. C'est le deuxieme nommeur.
2. `census/harness-attempt-not-burned-by-foreign-cause.sh:110` lit `proof-impossible.txt` code EN DUR, donc le bras LIVRE seulement : un etat pose sur le bras d'ablation reste invisible. Troisieme nommeur, et c'est EXACTEMENT la divergence deja corrigee deux fois.
3. `impossible_read_selftest.py:408-409` et `impossible_hygiene_selftest.py:115` construisent ou comptent le nom a la main : trois bancs de plus a corriger le jour ou le nom change.
4. `foreign_cause_selftest.py:340` : temoin d'un item VALIDE qui compte un LITTERAL DE CODE au lieu de mesurer un comportement a l'execution. Tout renommage le fait rougir sans defaut.
5. `impossible_hygiene_selftest.py:458` : `src_detection_intacte` affirme `git diff --quiet HEAD -- lib/proof_impossible.sh`. Un test de PROPRETE D'ARBRE dans un recensement fait rougir tout chantier qui touche ce fichier, pour une raison qui n'est pas la sienne.
6. `impossible.py purge()`, `orchestrator.py:2127`, `proof_run.sh:414` : le verrou serialise le JOURNAL, pas le `os.remove` de l'etat. Deux purges simultanees peuvent courir sur le meme fichier.
7. `backlog.py bloc_impossible` : la section « Preuve impossible » du texte rendu a l'owner n'a plus de borne — elle liste tout etat debout du disque, dans la file ou non.

## Livrable — le contrat, en entier

`naming_authority_defects` = 0, somme de termes publies SEPAREMENT.
1. UN SEUL nommeur : publier le compte de sites qui fabriquent un nom d'etat sans passer par l'autorite. Zero, et le compte est obtenu par recensement, pas par affirmation.
2. Le bras d'ablation est couvert partout ou le bras livre l'est : publier, par bras, le nom ecrit et le nom lu par chaque lecteur. L'egalite est le verdict.
3. Aucun banc ne compte un LITTERAL DE CODE la ou un comportement est mesurable : publier le compte de temoins convertis et le compte de temoins restes litteraux, avec leur raison.
4. Aucun recensement n'affirme la proprete de l'arbre : c'est le travail des portes, pas d'un instrument. Publier le compte de tels tests retires.
5. La suppression de l'etat est serialisee par le meme verrou que son journal : preuve par deux purges lancees ensemble sur le meme fichier.
6. La section rendue a l'owner est BORNEE et dit combien d'etats elle n'affiche pas.

## Hors perimetre

Ne touche a aucun code du jeu. Priorite 35 volontaire : tout le jeu passe AVANT. CE CHANTIER EST LE DERNIER DE SA CHAINE : ses propres signalements ne doivent PAS ouvrir un nouvel item, ils s'ajoutent a celui-ci.

## Ou l'owner regardera

Invisible. C'est la coherence du nommage et l'honnetete des bancs du harnais.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

