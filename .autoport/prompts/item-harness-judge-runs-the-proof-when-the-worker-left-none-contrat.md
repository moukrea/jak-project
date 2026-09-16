# Quand le worker termine sans preuve NEUVE, le juge lance lui-meme `proof_run.sh <id> device`, attend, puis juge : la mesure n'est plus a la charge du worker — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 16/09 (« vas-y ! ») apres le releve du superviseur : 125 verdicts en 4 jours, 72 echecs, dont 37 « preuve PERIMEE reutilisee » (source editee apres la preuve, proof_attempt_id d'un autre essai, sha du binaire, verdict_sources) et 11 « proof.txt absent ». 48 echecs sur 72 = le worker n'a pas laisse de mesure neuve, parce qu'une course appareil dure 7 a 30 min et qu'il rend la main avant. Le juge refuse alors une vieille preuve et COMPTE UN ESSAI : le budget de l'item part en plomberie, pas en jeu. Le harnais a pourtant tout pour mesurer seul : `lib/proof_run.sh <id> device`, `proof_timeout`, `pick_device.sh`, le verrou du constructeur, le deploiement (item harness-proof-run-device-deploys-or-refuses-first).

## Livrable — le contrat, en entier

`stale_proof_verdicts` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : compte de verdicts archives (logs/*/validator-*.txt) dont le premier constat est une preuve perimee ou absente, par item ; non nul (48 sur 4 jours au 16/09).

2. LE JUGE MESURE : quand le worker est sorti et qu'aucune course de cet item n'est vivante (item precedent), si proof.txt est absent OU plus vieux que le debut de l'essai OU refuse pour identite (attempt_id, sha binaire, sources), l'orchestrateur lance UNE course `proof_run.sh <id> device` (x86 si `device: false`), bornee par `proof_timeout` + deploiement, puis appelle le validateur sur CETTE preuve. Publier : declencheur (absent/perime/identite), duree, rc de la course.

3. UNE SEULE COURSE, JAMAIS EN BOUCLE : la course du juge n'est lancee qu'une fois par essai ; si elle echoue (appareil absent, build non relie, rc nomme), l'essai est requalifie « preuve impossible » (non compte) avec la cause, jamais « echec ».

4. L'ESSAI COMPTE SUR LA MESURE NEUVE : un essai dont la preuve finale est celle du juge est juge comme si le worker l'avait produite ; le handoff du worker n'est pas ecrase, le journal dit qui a mesure.

5. LE TEMOIN A DEUX BRAS : bac a sable, faux worker qui sort sans preuve ; bras livre = une course lancee par le juge, verdict rendu sur elle, compteur d'essais inchange si elle est impossible ; `--off` = comportement d'avant (vieille preuve refusee, essai compte). Les deux verdicts cote a cote.

PREUVE : `FEATURE harness-judge-runs-the-proof-when-the-worker-left-none armed=1 hits=<courses lancees par le juge>` + la ligne `stale_proof_verdicts=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne change pas les criteres des portes ; ne relance jamais une course vivante ; ne touche ni aux validateurs d'items ni a proof_run.sh au-dela de son appel. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a voir dans le jeu : c'est du harnais. L'effet se lit dans le tableau des causes d'echec : les lignes « preuve perimee » et « preuve absente » tombent a zero.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

