# La mort du superviseur est elle-meme une alerte : la file « retour owner sans reponse » ne peut pas rester servie a un lecteur qui n'existe plus — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 22/09 : « Pourquoi tu réagis plus a mes feedbacks sur Linear ». Chaine verifiee ce jour-la : linear_sync RECOPIE bien ses commentaires dans owner_feedback (les deux de 10:27 et 10:30 y sont, verbatim), pose « A traiter » sur le ticket, et crie « À TRAITER : JAK-176 » a chaque passage — 7 585 fois dans logs/linear_sync.txt. wake_gate.py insere bien le bloc « RETOURS DE L'OWNER SANS REPONSE » en tete de chaque reveil. TOUT fonctionne sauf le lecteur : la session superviseur (fc2d3cfc, transcript de 318 Mo) a rendu sa derniere reponse a 09:50:56, le reveil de 10:20:48 est reste EN FILE sans jamais etre traite, la demande a ete interrompue a 11:06:42 et la session s'est terminee a 11:07:54. `.autoport/.supervisor-terminal.json` designe toujours le pid 68980, mort ; le tty qu'il nomme (/dev/pts/3) fait tourner un `codex --yolo resume` depuis 4 jours. Aucune porte, aucun journal, aucun `autoport status` ne regarde si le superviseur existe : `grep -i linear .autoport/autoport` ne rend RIEN. Consequence mesuree : 2 retours owner sans reponse pendant 2 h 45, et JAK-176 dans la file « a traiter » sur 10 766 des 12 391 passages de synchro.

## Livrable — le contrat, en entier

`orphan_owner_feedback_defects` = 0, somme de termes publies SEPAREMENT. Un terme non mesure compte 1.

1. LE COUT D'AVANT EST CHIFFRE : sur les 7 derniers jours, pour chaque retour owner recopie dans `owner_feedback`, le delai entre son horodatage Linear et le premier commentaire du harnais poste APRES lui sur le meme ticket (sans reponse = delai ouvert). Publier le nombre de retours au-dela de 2 h et le maximum. Non nul par construction (2 cas le 22/09, 24 h le 21/09).

2. LE LECTEUR EST VIVANT, MESURE : un releve publie dit si un superviseur existe — pid de `.autoport/.supervisor-terminal.json` vivant AVEC le meme starttime (champ 22 de /proc/<pid>/stat, jamais `kill -0` : il reussit sur un zombie), et horodatage de sa derniere reponse effective. Publier les deux, et la duree depuis la derniere reponse.

3. LA MORT EST UNE ALERTE, PAS UNE LIGNE DE JOURNAL : quand un retour owner attend depuis plus de `AUTOPORT_OWNER_SLA_S` (defaut 2 h) ET qu'aucun superviseur vivant ne l'a lu, le harnais l'ecrit la ou quelqu'un regarde — en tete de `autoport status` (rubrique nommee, avec l'age du plus vieux retour) ET en commentaire sur le ticket concerne, une seule fois par retour. Porte : simuler un superviseur mort + un retour de 3 h -> la rubrique apparait et le commentaire part ; superviseur vivant -> ni l'un ni l'autre (controle negatif) ; deux passages de suite -> UN seul commentaire (pas de repetition).

4. LE FICHIER DE TERMINAL NE MENT PLUS : `.supervisor-terminal.json` qui designe un pid mort, ou un tty dont le programme n'est pas le superviseur, est traite comme « pas de superviseur » et non comme « superviseur declare ». Publier le cas mesure sur le releve du 22/09 (pid 68980 mort, pts/3 = codex).

## Hors perimetre

(non precise)

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

