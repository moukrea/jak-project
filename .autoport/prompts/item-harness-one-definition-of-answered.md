# Une seule definition de « repondu » : le reveil du superviseur et le compteur de retours ne peuvent plus se contredire

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/lib/wake_gate.py:276-290` lit le bloc « RETOURS DE L'OWNER SANS REPONSE » sur l'etiquette « A traiter » du journal de synchro, pas sur owner_sla ; `linear_sync.py --comment` retire l'etiquette meme hors fil. Le reveil peut taire un retour que owner_sla compte encore ouvert. Recoupe harness-wake-unanswered-list-carries-its-age (s'il est deja livre, partir de son etat).

## Livrable
1. Le reveil lit la liste depuis owner_sla, source unique.
2. `answered_definitions_disagree` = retours ouverts pour owner_sla mais absents du reveil (ou l'inverse) ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`answered_definitions_disagree == 0` dans `reports/harness-one-definition-of-answered/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-one-definition-of-answered x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
