> LIS D'ABORD `prompts/item-harness-close-gate-code-free-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La porte de fermeture cesse de bruler un essai par item de harnais, et ne promeut plus sans relire le verdict

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
DEUX SIGNALEMENTS DU 12/09 (reports/harness-proof-props-pin/FINDINGS.txt).
1. `orchestrator.py:1033` (GATE 1) : un item dont le perimetre INTERDIT de toucher `game/ android/ goalc/ goal_src/` echoue FORCEMENT a sa premiere fermeture, parce que `no_code` n'est pose par personne a la creation de l'item et que rien ne le dit au LANCEMENT de l'essai — seulement a sa fermeture. Cout mesure : l'essai 1 de `harness-proof-props-pin` le 12/09, porte machine TENUE, refusee pour un drapeau absent. Un essai entier par item de harnais, et ca se repete a chaque nouvel item.
2. `lib/backlog.py:machine_proved_to_validated` s'appelle « machine_proved » mais promeut TOUT `to-test` portant `owner_test: false`, […suite dans le contrat]

## Livrable
`close_gate_code_free_defects` = 0, somme de termes publies SEPAREMENT.
1. GATE 1 se prononce au LANCEMENT, pas seulement a la fermeture : un item dont le perimetre interdit le code est reconnu comme tel avant que l'essai brule. Publier le compte d'items lances sans `no_code` alors que leur perimetre l'exige.
2. Aucun essai n'est plus refuse pour ce seul drapeau. Preuve a deux bras : le bras d'AVANT doit refuser, le bras d'APRES doit passer, sur le MEME item jetable.
3. La promotion machine relit le VERDICT : un `to-test` dont la porte n'a pas tenu n'est pas promu. Semer les deux controles dans une copie jetable — un item dont la porte a tenu, qui doit sortir ; un item dont elle n'a pas tenu […suite dans le contrat]

## Preuve exigee
`close_gate_code_free_defects == 0` dans `reports/harness-close-gate-code-free/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-close-gate-code-free x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la porte de fermeture du harnais..

## Hors perimetre
Ne touche a aucun code du jeu. Ne promeut aucun item existant au passage.
