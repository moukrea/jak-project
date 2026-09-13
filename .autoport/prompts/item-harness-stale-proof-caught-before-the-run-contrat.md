# Une preuve perimee se voit AVANT la course, pas au validateur une heure plus tard — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

PITFALLS porte deja la garde `editing-a-shared-verdict-source-reddens-every-in-flight-proof`, mais elle vise le SUPERVISEUR. Le cout qui reste vient du WORKER : il edite sa propre source (moteur, ou son recensement `lib/census/<id>.sh`), NE RELANCE PAS la preuve, et ne l'apprend qu'au validateur — apres avoir depense l'essai entier. Mesure du 2026-09-12 : 12 essais refuses pour ce motif sur 5 items (android-text-overrides-dropped 4, lighting-hdr 3, menu-back-label 2, lighting-legacy-purge 2, mesh-browser-removal 1). L'essai 1 de menu-back-label a couru 43 minutes avant de mourir la-dessus. L'outil de detection EXISTE (`bash lib/verdict_sources.sh <id>`) : ce qui manque, c'est qu'il soit lu au bon moment.

## Livrable — le contrat, en entier

`stale_proof_late_catches` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE. Publier, depuis les journaux de validateur archives, le compte d'essais refuses pour « source editee APRES la preuve », par item. Non nul — c'est le denominateur de cet item, et un zero AVANT rendrait la suite vide.
2. LA PEREMPTION SE DETECTE AVANT DE DEPENSER LA COURSE. La comparaison des sources epinglees contre le disque se fait au demarrage de la preuve, pas au verdict. Publier le compte de fichiers compares — non nul — et le code de sortie pris, distinct de celui d'un echec de mesure.
3. LE TEMOIN NE PEUT PAS ETRE VIDE. Dans un bac a sable jetable, semer DEUX controles : un fichier volontairement modifie apres la capture, que la detection doit voir, et un arbre intact, qu'elle doit laisser passer. Publier les deux verdicts cote a cote. Un seul bras prouve la moitie.
4. LE MOTIF DISPARAIT DES REFUS TARDIFS. Sur les essais qui suivent la livraison, publier le compte de refus AU VALIDATEUR pour ce motif : zero, avec le compte d'essais observes a cote. Un zero sur zero essai est un defaut, pas une reussite.
PREUVE : `FEATURE harness-stale-proof-caught-before-the-run armed=1 hits=<fichiers de source de verdict compares avant la course>` + la ligne `stale_proof_late_catches=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change AUCUNE regle de ce qui est epingle : la liste des sources de verdict reste celle d'aujourd'hui. On deplace le moment de la lecture, on n'assouplit pas le juge. Ne touche pas au verdict d'un item en vol. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur la duree des essais perdus.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

