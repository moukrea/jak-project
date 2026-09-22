# Seul le vrai superviseur compte comme lecteur vivant : une autre session Claude du depot ne peut plus eteindre l'alerte « superviseur mort »

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 8), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/lib/supervisor_alive.py:is_worker` : « pas un worker » = ni AUTOPORT_ATTEMPT_ID ni AUTOPORT_PHASE_ID. Toute autre session Claude du depot (owner a la main, juge lance sans ces variables) se declare lectrice et peut eteindre l'alarme sans lire aucun retour. Non mesure combien de sessions de ce type existent.

## Livrable
1. Recensement AVANT : sessions qui ont tamponne `.supervisor-seen.json` sur 7 jours, classees superviseur / autre.
2. Le tampon exige une preuve positive d'etre le superviseur (role declare par le lanceur ou le reveil de supervision), pas l'absence de variables de worker.
3. `supervisor_foreign_stamps` = tampons poses par une session non superviseur ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`supervisor_foreign_stamps == 0` dans `reports/harness-supervisor-reader-must-be-the-supervisor/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-reader-must-be-the-supervisor x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
