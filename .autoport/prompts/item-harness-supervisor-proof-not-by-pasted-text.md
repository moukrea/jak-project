# Une session ouverte a la main ne peut pas se faire passer pour le superviseur en recevant le texte d'un reveil

## Defaut cite
- 2026-09-23 : « Ok mais codex c'est pas prioritaire du tout, ça sera codex lui même qui traitera quand il voudra, vraiment en bas du bas de la pile »

## Cause connue
Signale par le worker de harness-supervisor-reader-must-be-the-supervisor (reports/.../FINDINGS.txt), non corrige ; l'owner a dit « Ok » le 23/09 (JAK-198).
`.autoport/lib/supervisor_alive.py:supervisor_proof` (preuve « reveil ») repose sur l'heuristique de texte `est_un_reveil` : une session non-worker qui recoit un long prompt citant « autoport » + « supervision » se declare superviseur. 0 cas sur 7 jours.

## Livrable
1. La preuve « reveil » exige un marqueur que seul le reveil programme porte (ou l'inscription du lanceur), pas la forme du texte.
2. `supervisor_proof_by_text` = sessions declarees superviseur sur la seule forme du texte ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`supervisor_proof_by_text == 0` dans `reports/harness-supervisor-proof-not-by-pasted-text/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-proof-not-by-pasted-text x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
