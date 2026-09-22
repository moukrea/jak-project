# La liste des retours de l'owner sans reponse, dans le reveil du superviseur, dit depuis quand chacun attend et monte d'un cran quand ca dure

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 3), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/lib/wake_gate.py:249-261` lit la liste « retours owner sans reponse » par regex sur les 40 000 derniers octets de logs/linear_sync.txt, sans horodatage : elle ne dit pas depuis QUAND un retour attend, repete le meme nom sans jamais escalader, et devient muette des qu'un autre journal pousse la ligne hors des 40 ko.

## Livrable
1. La liste se lit a la source horodatee (owner_sla / backlog), plus par regex sur un journal.
2. Chaque retour porte son age, et le bloc escalade au-dela du delai convenu.
3. `wake_unanswered_lost` = retours sans reponse absents du bloc de reveil ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`wake_unanswered_lost == 0` dans `reports/harness-wake-unanswered-list-carries-its-age/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-wake-unanswered-list-carries-its-age x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
