# Le constructeur d'APK ne prend plus un demon Gradle inactif pour un build en cours, et dit dans son journal pourquoi il ne construit pas — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

16/09 17:41 -> 17/09 00:40 : SEPT HEURES sans build ni ligne de journal alors que des commits livrables (herbe, harnais, ocean a 00:16) attendaient. Cause mesuree par le superviseur : auto_build_apk.sh:398-403 compte `java` dans `busy` ET `hard` ; un GradleDaemon INACTIF (lance par le gradle d'un proof_run appareil, vivant 3 h) fait donc `continue` sans `say`, et la patience de 20 min ne s'applique jamais puisque `hard` > 0. `./gradlew --stop` a 00:25 a libere 2 demons ; le proof_run suivant en a relance un a 00:33 et le blocage a repris (busy=1 au tick de 00:41:40). Meme famille que harness-busy-guard-matches-gradle-daemon (proof_run.sh), copie VIVANTE dans le constructeur. Deuxieme sortie muette : auto_build_apk.sh:473 `flock -n` rate = `continue` sans un mot.

## Livrable — le contrat, en entier

`builder_silent_skips` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : duree du plus long silence du journal du constructeur entre deux ticks alors qu'un commit livrable non bati existait (>= 7 h le 16/09), et nombre de ticks muets ; non nuls.

2. UN DEMON GRADLE INACTIF N'EST PAS UN BUILD : la garde distingue un `java` GradleDaemon sans travail (etat Idle de `gradle --status`, ou aucun enfant compilateur et CPU nulle sur 10 s) d'un gradle qui construit ; l'inactif ne compte ni dans busy ni dans hard. Publier les deux comptes et la decision a chaque tick.

3. AUCUN TICK MUET : chaque `continue` de la boucle ecrit UNE ligne nommant sa cause (WIP, deja bati, verrou tenu par pid, compilateur pid, livraison en cours), au plus une ligne par cause et par 20 min pour ne pas noyer le journal.

4. LE TEMOIN A DEUX BRAS : bac a sable avec un faux GradleDaemon inactif (processus `java` nomme GradleDaemon qui dort) et un commit livrable ; bras livre = build declenche au tick suivant, journal explicite ; `--off` = tick muet, aucun build. Les deux verdicts cote a cote.

PREUVE : `FEATURE harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build armed=1 hits=<ticks ou un demon inactif a ete ecarte>` + la ligne `builder_silent_skips=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne touche pas au publieur ni a proof_run.sh ; ne tue aucun demon Gradle a la place de la garde. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu : c'est du harnais. L'effet : un build publie dans l'heure qui suit un commit livrable, meme quand des mesures appareil tournent.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

