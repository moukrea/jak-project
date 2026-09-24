# L'orchestrateur ne perd plus les dernieres lignes d'un worker qui sort, et un essai freine a chaque fois finit par etre nomme

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-copes-with-usage-pacing (reports/.../FINDINGS.txt), non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
(1) `orchestrator.py` boucle de lecture de run_attempt (branche `if not ready:` -> `proc.poll()` -> break) : `select` sur le fd puis `readline` bufferise : les lignes deja en tampon sont PERDUES quand le worker sort (mesure sur le banc). Voir la memoire feedback_select_on_fd_with_buffered_readline_swallows_a_line : lire par os.read.
(2) Outcome « paced » sans borne d'affilee (contrairement a `aborted`, MAX_ABORTED_IN_A_ROW) : un worker qui mourrait a CHAQUE pause tournerait sans jamais etre compte.

## Livrable
1. Lecture par os.read + decoupage des lignes ; vidange complete a la sortie du worker.
2. Borne d'essais « paced » d'affilee, au-dela : bloque avec une raison NOMMEE.
3. `worker_stream_lost_lines` = lignes perdues sur un worker fabrique qui ecrit N lignes et sort aussitot ; doit valoir 0.
CONTROLE POSITIF (ancien code : lignes perdues) + CONTROLE NEGATIF.

## Preuve exigee
`worker_stream_lost_lines == 0` dans `reports/harness-worker-stream-no-lost-lines/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-worker-stream-no-lost-lines x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
