# L'empreinte des consignes s'ecrit toujours au meme endroit, d'ou que l'outil soit lance : une consigne n'est plus gelee en silence

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
`.autoport/lib/backlog.py:1030` `_FINGERPRINTS` est un chemin RELATIF au cwd (.autoport/.prompt_fingerprints.json) : un write_prompt lance hors de la racine ecrit l'empreinte ailleurs, et la consigne relue depuis la racine passe « a-la-main » (plus jamais refabriquee).

## Livrable
1. Chemin ancre sur le fichier (comme AP/ROOT ailleurs).
2. Recenser les empreintes egarees hors racine et les consignes passees « a-la-main » a tort.
3. `prompt_fingerprints_misplaced` ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`prompt_fingerprints_misplaced == 0` dans `reports/harness-prompt-fingerprints-absolute-path/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-prompt-fingerprints-absolute-path x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
