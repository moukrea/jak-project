> LIS D'ABORD `prompts/item-harness-gate-verdict-must-outlive-its-log-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La preuve qu'une porte a tenu vit dans l'item, pas dans un journal que rien ne conserve

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
TROIS SIGNALEMENTS DU 12/09 (reports/harness-close-gate-code-free/FINDINGS.txt).
1. La promotion machine relit desormais le VERDICT avant de valider un `to-test` — c'etait le correctif demande. Mais ce verdict vit dans `logs/<id>/validator-NNN.txt`, et `.gitignore:174` exclut tout `.autoport/logs/`. Sur un clone neuf, ou apres une purge de journaux, le verdict est INTROUVABLE. Le code choisit alors de ne pas promouvoir, ce qui est le bon defaut, mais l'effet est qu'un item prouve reste gele — exactement la panne que `perf-ocean-idle` a vecue deux jours.
2. `orchestrator.py:2837` : la porte ne laisse AUCUNE TRACE dans l'item de ce qu'elle a rendu. Elle pose `to-test` et `delivered`, rien d'au […suite dans le contrat]

## Livrable
`verdict_durability_defects` = 0, somme de termes publies SEPAREMENT.
1. Le verdict de la porte est ECRIT DANS L'ITEM au moment ou elle le prononce : au minimum le resultat, la date, et l'empreinte de la preuve jugee. Publier le compte d'items `to-test` portant ce champ et le compte de ceux qui n'en ont pas.
2. La promotion machine lit ce champ EN PREMIER et ne retombe sur le journal que s'il manque. Preuve a deux bras sur une copie jetable : journaux EFFACES, le bras d'AVANT ne promeut pas, celui d'APRES promeut. C'est la purge des journaux qui est le stimulus, pas un drapeau.
3. Le perimetre cesse d'etre devine dans une phrase. Un champ explicite fait foi ; la lecture de la prose ne sert p […suite dans le contrat]

## Preuve exigee
`verdict_durability_defects == 0` dans `reports/harness-gate-verdict-must-outlive-its-log/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-gate-verdict-must-outlive-its-log x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est ce qui reste d'une porte une fois les journaux effaces..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change pas la definition du verdict lui-meme, ni les criteres de `generic.sh`. Priorite 31 volontaire : la refonte de l'eclairage passe AVANT.
