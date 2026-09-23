# Un secret colle par l'owner dans un commentaire Linear n'est jamais recopie en clair : ni dans le backlog, ni dans un journal, ni dans un prompt

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-owner-sla-matches-every-owner-comment : le Client Secret Linear que l'owner a colle en commentaire le 17/09 etait EN CLAIR dans logs/linear_sync.txt (pull_owner imprime 80 caracteres de chaque retour). Le superviseur a constate le 23/09 qu'il etait AUSSI dans backlog.yaml (owner_feedback), .owner_sla.json, le prompt item-harness-linear-own-identity-contrat.md, deux journaux d'essai, et dans 18 commits dont 23b8f3370a (17/09) POUSSE sur le depot GitHub PUBLIC moukrea/jak-project. Masque a la main le 23/09 (commit dad5e35790) ; le secret reste dans l'historique public, seule sa rotation par l'owner le neutralise.

## Livrable
1. Au point de PRODUCTION (pull_owner, avant toute ecriture : backlog, journal, owner_sla, prompt, image), detecter les formes de secret (cles Linear lin_api_/lin_oauth_, jetons hex/base64 longs a cote de « secret », « token », « key », « password », cles connues du ~/.config/autoport/*.env) et les remplacer par [SECRET-MASQUE].
2. Recenser AVANT : toute occurrence d'un secret connu dans le depot suivi, les journaux, et `git log --remotes` ; publier le compte.
3. Hook de commit (ou porte) qui refuse un commit contenant un secret connu du ~/.config/autoport/*.env.
4. `owner_secret_leaks` = occurrences d'un secret connu hors de ~/.config ; doit valoir 0.
CONTROLE POSITIF : un commentaire owner fabrique portant un faux secret -> masque partout, commit refuse. CONTROLE NEGATIF : un commentaire ordinaire (hash de commit, md5 d'APK) n'est pas masque.

## Preuve exigee
`owner_secret_leaks == 0` dans `reports/harness-owner-secret-never-copied-in-clear/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-secret-never-copied-in-clear x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
