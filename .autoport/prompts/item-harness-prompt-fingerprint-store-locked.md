# Le magasin d'empreintes des consignes s'ecrit sous verrou : deux ecrivains simultanes ne font plus passer une consigne « a la main » en silence

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-prompt-fingerprints-absolute-path (reports/.../FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
(1) `lib/backlog.py:_stamp_prompt` : lecture-modification-ecriture du magasin d'empreintes SANS verrou ; orchestrateur + linear_sync + superviseur ecrivent en meme temps -> une empreinte perdue -> la consigne repasse « a-la-main » et n'est plus jamais refabriquee. (2) Commentaires devenus faux « _FINGERPRINTS est relatif au cwd » dans lib/census/harness-owner-feedback-write-never-loses-a-return.sh:194 et harness-supervisor-relay-command.sh:61. (3) 15 consignes re-adoptees d'items validated/archived restent « perime » (honor-boot-crash, cutscene-npc-flicker, anim-interp-low-fps, foliage-wind, ...). 6 consignes vraiment manuelles restent a-la-main (hd-models, memory-ceiling-and-crash, precompute-deterministic-bake, loadgate-crash-regression, fixed-tick-interpolation, proof-kv-provenance) : NE PAS les refabriquer.

## Livrable
1. Ecriture du magasin sous verrou (relire-fusionner-ecrire).
2. Corriger les deux commentaires.
3. Refabriquer les 15 consignes perimees d'items clos (prompt_state == perime), jamais les 6 manuelles.
4. `prompt_fingerprints_lost` = empreintes perdues sur 50 ecritures concurrentes fabriquees + consignes perimees d'items clos ; doit valoir 0.
CONTROLE POSITIF (course fabriquee sans verrou -> perte) + CONTROLE NEGATIF (les 6 manuelles intactes a l'octet).

## Preuve exigee
`prompt_fingerprints_lost == 0` dans `reports/harness-prompt-fingerprint-store-locked/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-prompt-fingerprint-store-locked x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
