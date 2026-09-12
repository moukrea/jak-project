# La porte de fermeture cesse de bruler un essai par item de harnais, et ne promeut plus sans relire le verdict — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

DEUX SIGNALEMENTS DU 12/09 (reports/harness-proof-props-pin/FINDINGS.txt).
1. `orchestrator.py:1033` (GATE 1) : un item dont le perimetre INTERDIT de toucher `game/ android/ goalc/ goal_src/` echoue FORCEMENT a sa premiere fermeture, parce que `no_code` n'est pose par personne a la creation de l'item et que rien ne le dit au LANCEMENT de l'essai — seulement a sa fermeture. Cout mesure : l'essai 1 de `harness-proof-props-pin` le 12/09, porte machine TENUE, refusee pour un drapeau absent. Un essai entier par item de harnais, et ca se repete a chaque nouvel item.
2. `lib/backlog.py:machine_proved_to_validated` s'appelle « machine_proved » mais promeut TOUT `to-test` portant `owner_test: false`, SANS relire le verdict du validateur. Sans danger aujourd'hui parce que seule la porte de fermeture pose `to-test`, et apres sa porte. Mais la fonction vient d'etre rebranchee : un `to-test` pose a la main, par un superviseur ou par une future voie de parking, serait valide sans qu'aucune preuve n'ait tenu. La garde manquante est « la porte a-t-elle tenu », pas « l'owner a-t-il regarde ».

## Livrable — le contrat, en entier

`close_gate_code_free_defects` = 0, somme de termes publies SEPAREMENT.
1. GATE 1 se prononce au LANCEMENT, pas seulement a la fermeture : un item dont le perimetre interdit le code est reconnu comme tel avant que l'essai brule. Publier le compte d'items lances sans `no_code` alors que leur perimetre l'exige.
2. Aucun essai n'est plus refuse pour ce seul drapeau. Preuve a deux bras : le bras d'AVANT doit refuser, le bras d'APRES doit passer, sur le MEME item jetable.
3. La promotion machine relit le VERDICT : un `to-test` dont la porte n'a pas tenu n'est pas promu. Semer les deux controles dans une copie jetable — un item dont la porte a tenu, qui doit sortir ; un item dont elle n'a pas tenu, qui doit rester — et publier les deux.
4. Le nom de la fonction et ce qu'elle fait cessent de diverger : soit elle verifie ce que son nom promet, soit elle change de nom. Dire lequel.

## Hors perimetre

Ne touche a aucun code du jeu. Ne promeut aucun item existant au passage.

## Ou l'owner regardera

Invisible. C'est la porte de fermeture du harnais.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

