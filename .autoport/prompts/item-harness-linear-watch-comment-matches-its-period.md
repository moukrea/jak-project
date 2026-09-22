# Le commentaire de linear_watch.sh dit la vraie frequence de la veille Linear

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 1), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/linear_watch.sh:2` annonce « toutes les 5 min », le code fait `sleep 30` : facteur 10. Toute borne calee sur le commentaire (budget d'API, anti-rebond) est dimensionnee 10 fois trop large.

## Livrable
1. Une seule source pour la periode (variable lue par le code ET citee par le texte).
2. `linear_watch_period_mismatch` = ecart entre periode annoncee et periode executee ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_watch_period_mismatch == 0` dans `reports/harness-linear-watch-comment-matches-its-period/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-watch-comment-matches-its-period x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
