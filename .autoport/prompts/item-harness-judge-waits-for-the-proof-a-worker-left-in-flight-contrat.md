# Un worker qui laisse une course de preuve EN VOL n'est plus ferme apres 45 s : le juge attend la course, bornee par proof_timeout, avant de trancher — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

16/09, trois essais brules en 50 min (ao-prepass-tie-alpha 14 et 15, perf-mips2c-neon 10). Le worker Claude lance `proof_run.sh <id> device` en arriere-plan, arme un moniteur sur son PID et TERMINE SON TOUR (« En vol — j'attends la notification », « I'll wait for the run rather than poll »). En mode `-p` cette notification n'arrive jamais : l'orchestrateur voit un `result`, compte 45 s d'inactivite (STALL_POST_RESULT_SEC, orchestrator.py:143) et fait `_kill('post-result')`, puis juge : `proof.txt absent` (validator-014/015). `wait_for_proof_writer` n'aide pas : au moment du juge la course est deja morte avec le groupe de processus du worker, ou pas encore verrouillee. L'essai 14 avait pourtant trouve la cause de 13 essais aveugles (fenetre de la sonde statique au tick 1200, courses tuees a 840 par --timeout 150) : ce travail est perdu deux fois.

## Livrable — le contrat, en entier

`inflight_kill_defects` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : compte d'essais archives dont le journal porte « fermeture forcee » (post-result) ET dont le validateur dit « proof.txt absent » ou « course ECRIVAIT » ; publie par item ; non nul (au moins 3 le 16/09).

2. LE JUGE ATTEND LA COURSE : quand le worker a emis son resultat et se tait, l'orchestrateur regarde d'abord si une course de preuve de CET item est vivante (verrou/PID de proof_run.sh, ou processus enfant `proof_run.sh <id>`) ; si oui, il n'envoie aucun signal, attend sa fin bornee par `proof_timeout` de l'item + 120 s, et juge APRES. Publier l'attente et le PID.

3. LA FERMETURE N'EMPORTE PAS LA COURSE : quand la fermeture forcee reste legitime (aucune course vivante), une course lancee par le worker en `setsid` survit au `_kill` ; temoin : bac a sable, faux worker qui lance un faux proof_run de 60 s puis emet un resultat et se tait ; proof.txt final present et juge.

4. LE TEMOIN A DEUX BRAS : meme bac a sable, (a) course vivante = pas de kill, verdict sur la preuve finale ; (b) aucune course = kill post-result inchange apres 45 s. Les deux verdicts cote a cote, `--off` = comportement d'avant (course tuee, proof absent).

PREUVE : `FEATURE harness-judge-waits-for-the-proof-a-worker-left-in-flight armed=1 hits=<juges retenus par une course vivante>` + la ligne `inflight_kill_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change pas STALL_POST_RESULT_SEC pour tout le monde ; ne relance jamais une course ; ne touche ni au validateur ni a proof_run.sh au-dela du verrou/PID lisible. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais AO et perf qui ne meurent plus avec leur preuve en vol.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

