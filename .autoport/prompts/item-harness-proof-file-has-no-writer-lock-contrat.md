# Une course tuee ne peut plus ecraser la preuve de celle qui lui succede — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

DEUX SIGNALEMENTS DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt), dont un CHIFFRE et reproduit dans l'heure.
1. AUCUN ecrivain unique, AUCUN verrou sur `reports/<id>/proof.txt`. Un essai TUE laisse son `proof_run.sh` VIVANT : il finit sa course et ecrit sa preuve par-dessus celle de l'essai suivant. Le validateur juge alors la course d'AVANT en croyant juger celle d'apres.
2. RIEN N'EMPECHE UN COMMIT EXTERIEUR PENDANT UNE COURSE. Mesure du 12/09 : le SUPERVISEUR a commite a 16:12:59 pendant une course, et l'empreinte des sources de verdict a bouge entre la mesure et son jugement. L'essai a ete refuse pour une raison qui ne decrivait aucun defaut de son travail. Le meme defaut s'est reproduit dans l'heure.
C'est la meme famille que les quatre essais detruits par le plafond de 600 s : un essai perdu pour une cause qui n'est pas la sienne, sauf qu'ici la consequence est pire — un verdict rendu sur la MAUVAISE course.
3. DEUXIEME CAS MESURE LE MEME JOUR. `build-android-reinvalidates-itself` a ete BLOQUE le 12/09 a 18:12 sur trois refus identiques « proof.txt absent ou vide », alors que son travail etait commite a 18:04 et 18:06 et que sa preuve — 34 340 octets, porte tenue — a ete ecrite a 18:21. Le juge est passe trois fois avant la fin de la chaine. La garde anti-boucle a alors lu trois empreintes d'echec identiques et a bloque l'item, ce qui a demande un arbitrage humain pour un travail qui etait fait. Publier le compte d'essais juges avant l'ecriture de leur propre preuve : c'est la grandeur qui manque.

## Livrable — le contrat, en entier

`proof_writer_defects` = 0, somme de termes publies SEPAREMENT.
1. UN SEUL ecrivain par `proof.txt`, par verrou : une seconde course sur le meme item attend ou refuse, elle n'ecrase pas. Publier le compte de tentatives d'ecriture concurrentes rencontrees.
2. Une preuve porte l'identite de la COURSE qui l'a produite, et la porte refuse une preuve dont l'identite ne correspond pas a l'essai courant. Preuve a deux bras : une preuve d'un essai precedent, semee, doit etre ACCEPTEE dans le bras d'avant et REFUSEE dans celui d'apres.
3. Un `proof_run.sh` orphelin est detecte et arrete quand son essai a ete tue : publier le compte d'orphelins trouves et arretes.
4. Un commit exterieur pendant une course est DIT : publier le compte de commits survenus entre le debut de la course et son jugement, et lesquels ont touche une source de verdict. Ne pas l'interdire — le superviseur doit pouvoir travailler — mais le rendre visible pour que le refus nomme la vraie cause.

## Hors perimetre

Ne touche a aucun code du jeu. N'interdit aucun commit.

## Ou l'owner regardera

Invisible. C'est la garantie que le verdict porte sur la bonne course.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

