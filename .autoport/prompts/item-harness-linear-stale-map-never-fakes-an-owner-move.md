# La synchro ne prend jamais un etat perime de sa carte pour un deplacement de ticket par l'owner

## Defaut cite
- 2026-09-23 : « Ok »

## Cause connue
Signale par le worker de harness-linear-sync-never-creates-two-tickets-for-one-item (reports/.../FINDINGS.txt), non corrige ; l'owner a dit « Ok » pour l'ouvrir le 23/09 (JAK-229).
`.autoport/linear_sync.py:pull_owner` : une carte reculee rend un `last_state` perime, lu comme « l'owner a deplace le ticket » ; le 23/09 a 00:19:47, deux faux deplacements ont ete appliques par `apply_owner_move` (harness-x86-proof... Todo->In Progress, harness-supervisor-death-is-an-alarm In Progress->In Review). Sans consequence ce jour-la (ils correspondaient a l'etat reel), mais un faux deplacement peut valider, rouvrir ou archiver un item au nom de l'owner. Empeche aujourd'hui par le cliche hors git ; revient si carte ET cliche reculent ensemble (git clean -x puis reset).

## Livrable
1. Un deplacement n'est attribue a l'owner que si Linear le prouve (historique du ticket : auteur = l'owner, date posterieure au dernier passage), jamais par difference avec la carte locale.
2. `fake_owner_moves` = deplacements appliques sans auteur owner prouve ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`fake_owner_moves == 0` dans `reports/harness-linear-stale-map-never-fakes-an-owner-move/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-stale-map-never-fakes-an-owner-move x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
