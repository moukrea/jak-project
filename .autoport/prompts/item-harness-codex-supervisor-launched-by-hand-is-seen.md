# Un superviseur Codex lance a la main est vu vivant par le harnais

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 7), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/lib/supervisor_alive.py:self_declare` : une session superviseur sous CODEX ouverte hors run-supervisor.sh ne passe pas par les crochets Claude : elle ne se declare pas et reste « non inscrit ». Apres une bascule codex a la main, l'alerte peut partir sur le ticket de l'owner alors qu'un lecteur tourne. Meme famille pour Claude : le fichier de terminal ne note ni la session ni le backend (ligne 4).
AJOUT 23/09 (signale par le worker de harness-supervisor-reader-must-be-the-supervisor) : le probleme est PLUS LARGE que le lancement a la main. `.autoport/codex/hook.py` n'appelle JAMAIS wake_gate (pas d'equivalent UserPromptSubmit) : un superviseur Codex, meme lance par run-supervisor.sh, ne tamponne jamais .supervisor-seen.json ; l'alarme le dira mort ou non inscrit apres 1 h -> fausse alerte « superviseur mort » sur le ticket de l'owner des qu'on bascule sur Codex. Le recensement AVANT de l'item voisin ne lisait que les transcripts Claude (~/.codex/sessions ignores).

## Livrable
1. Chemin de declaration pour une session Codex hors lanceur.
2. `supervisor_undeclared_live` = superviseurs vivants non vus par le releve ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`supervisor_undeclared_live == 0` dans `reports/harness-codex-supervisor-launched-by-hand-is-seen/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-codex-supervisor-launched-by-hand-is-seen x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
