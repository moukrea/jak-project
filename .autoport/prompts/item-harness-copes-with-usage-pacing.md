> LIS D'ABORD `prompts/item-harness-copes-with-usage-pacing-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Quand le frein d'usage de l'owner met un worker en pause, le harnais attend au lieu de tuer l'essai, et ne compte jamais ce temps comme une panne

## Defaut cite
- 2026-09-24 : « Faut que le harnais compose avec ce frein, c'est un frein qu… »

## Cause connue
23/09, constate par le superviseur : le crochet global UserPromptSubmit de l'owner (`~/.claude/settings.json` : `/usr/bin/python3 ~/.local/share/resetdeck-agent/app/launch.py ... pacing-hook --provider claude`, timeout 691200 s) met les sessions Claude en pause pour eviter les limites d'usage HEBDOMADAIRES. C'est VOULU par l'owner et doit rester. Il s'execute aussi dans les workers `claude -p` du harnais (un processus resetdeck-agent fils du worker a ete vu vivant). Pendant la pause le worker ne produit rien : 8 essais de suite (harness-backlog-write-cost 1-3, lighting-bake 1-3, harness-dead-dependency-is-named-never-silent 1-2) ont fait 4 a 7 actions en 45-90 min, puis l'orchestrateur les a […suite dans le contrat]

## Livrable
1. DETECTER la pause : un crochet de rythme en cours d'execution dans l'arbre de processus du worker (ou de ses sous-agents), sans lire aucun secret. Publier l'etat « freine » et sa duree.
2. Pendant la pause, les gardes `no-progress` et `hard-silence` sont suspendues (le temps freine ne compte pas) ; la garde reprend a la sortie de la pause.
3. Un essai interrompu pendant une pause n'est ni compte ni empreinte (comme un signal), et la regle « meme echec 3 essais de suite » ne le voit pas.
4. `autoport status` dit « En pause : frein d'usage depuis X » au lieu d'avoir l'air mort ; le reveil du superviseur ne s'en alarme pas.
5. `paced_attempts_killed` = essais tues ou comptes alors qu'un croc […suite dans le contrat]

## Preuve exigee
`paced_attempts_killed == 0` dans `reports/harness-copes-with-usage-pacing/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-copes-with-usage-pacing x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
