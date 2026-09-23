# La limite d'espace Linear suit le vrai plan, et le recensement de l'archivage automatique applique la duree de vie de la limite apprise

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-learned-limit-can-rise / harness-owner-feedback-write-never-loses-a-return / acquis-hud-eco-gauge (reports/<id>/FINDINGS.txt), non corrige. Ouvert par le superviseur le 23/09 sous la delegation de l'owner pour ce type de signalement (« traite comme tu l'entends », JAK-235/237).
(1) `linear_sync.py:SPACE_LIMIT` : le plafond par defaut (250, plan gratuit) reste FIXE ; si l'owner passe a un plan plus grand sans refus prealable, make_room archive toujours des 212 tickets actifs. (2) `lib/census/harness-linear-auto-archive-when-space-runs-out.sh:B` recalcule la limite par `min(SPACE_LIMIT, learned_limit)` sans la duree de vie : sa porte peut juger contre une limite perimee.

## Livrable
1. Lire le plan/la limite reelle depuis l'API si elle l'expose, sinon sonder ; 2. le recensement applique la duree de vie.
3. `linear_space_limit_stale` ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`linear_space_limit_stale == 0` dans `reports/harness-linear-space-limit-minor/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-space-limit-minor x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
