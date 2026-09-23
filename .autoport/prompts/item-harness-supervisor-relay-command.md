# Les mots que l'owner dit au superviseur dans le terminal sont recopies par une commande qui les marque comme relayes

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
Aucun outil n'ecrit `via: {source: supervisor}` quand le superviseur relaie des mots de l'owner dits hors Linear ; un relais non etiquete compte NON APPARIE et le compteur rougit sur des relais legitimes. Le superviseur l'ecrit a la main depuis le 23/09 (ce retour-ci en porte un). 3 retours du 17/09 (water-ocean-mesh, grass-path-transitions, ao-prepass-tie-alpha) sont classes « relais hors Linear » sur la seule absence de commentaire correspondant.

## Livrable
1. `autoport feedback <id> "<mots>"` : ajoute un owner_feedback verbatim date avec `via: {source: supervisor}`, regenere le prompt si l'item le demande.
2. Recenser les relais existants non etiquetes et les etiqueter si prouves (commit du superviseur).
3. `unlabeled_relays` = owner_feedback sans `via` recents (apres la bascule) ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`unlabeled_relays == 0` dans `reports/harness-supervisor-relay-command/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-relay-command x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
