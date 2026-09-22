# Deux superviseurs en meme temps sont comptes separement : la mort de l'un ne se cache plus derriere l'autre

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 9), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/.supervisor-seen.json` est un emplacement UNIQUE (dernier ecrivain gagne) partage par le superviseur inscrit et le lecteur hors registre : si l'un meurt juste apres que l'autre a tamponne, sa mort ne se voit pas ; deux lecteurs simultanes ne sont pas recenses.

## Livrable
1. Un tampon par lecteur (pid+starttime), le releve les enumere tous.
2. `supervisor_readers_merged` = lecteurs vivants confondus dans un meme tampon ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`supervisor_readers_merged == 0` dans `reports/harness-supervisor-seen-stamp-per-reader/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-seen-stamp-per-reader x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
