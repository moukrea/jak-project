# Un essai ne brule plus pour une cause exterieure a l'item — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

QUATRE SIGNALEMENTS DU 12/09 (reports/harness-commit-paths-all-or-nothing/FINDINGS.txt). Tous disent la meme chose : un essai est COMPTE pour une salete que l'item n'a pas le droit de nettoyer, ou pour une ressource qu'il ne controle pas.
1. GATE 0 rend `fail` quand l'arbre est sale : l'essai compte, et la consigne renvoyee au worker lui demande de nettoyer l'arbre d'un AUTRE item — ce que son perimetre lui interdit. Il peut bruler ses cinq essais dessus.
2. Un chemin refuse par `git add` et non committable reste sale INDEFINIMENT : represente et re-refuse a chaque essai suivant. Le correctif du 12/09 ne le PERD plus, il ne le RESOUT pas. Une salete permanente declenche GATE 0 en boucle sur tous les items qui suivent.
3. Deux listes independantes du meme territoire : GATE 0 lit ('game/','common/','android/', 'goal_src/','goalc/'), GATE 1 code en dur ['game/','android/','goalc/','goal_src/'] — sans `common/`. Un fichier de `common/` compte comme du vrai travail pour une porte et pas pour l'autre.
4. Le constructeur a tenu `.autoport/.deploy-in-progress` pendant 6 h 38 (cycle arm64 legitime). `lib/proof_run.sh` attend jusqu'a 1800 s puis sort en 3 SANS ecrire de preuve. Une preuve peut donc etre impossible pendant des heures sans qu'aucun compteur ne le dise.

## Livrable — le contrat, en entier

`foreign_cause_defects` = 0, somme de termes publies SEPAREMENT.
1. Une salete ETRANGERE a l'item ne compte plus comme un essai rate : elle est nommee, publiee, et l'essai est classe a part. Publier le compte de fichiers sales etrangers et le compte d'essais ainsi requalifies. Un zero se lit « aucune salete etrangere », jamais « pas regarde ».
2. Un chemin durablement non committable est SIGNALE une fois et cesse d'etre represente : publier la liste des chemins mis de cote et depuis quand. Une salete permanente qui rebloque chaque item est pire que la perte qu'elle remplace.
3. Le territoire moteur est defini a UN SEUL endroit, lu par les deux portes. Publier la liste effective que chaque porte a utilisee : deux listes identiques, ou le defaut est compte.
4. Un verrou de deploiement tenu trop longtemps est MESURE : publier la duree d'attente et la sortie 3 de `proof_run.sh` comme un etat NOMME, pas comme une absence de preuve. Une preuve impossible doit se lire « impossible », jamais « pas produite ».

## Hors perimetre

Ne touche a aucun code du jeu. Ne nettoie pas l'arbre, ne debloque aucun item.

## Ou l'owner regardera

Invisible. C'est la comptabilite des essais et la definition du territoire moteur.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

