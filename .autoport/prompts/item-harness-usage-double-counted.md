# Le compteur de jetons d'un essai compte chaque message trois à cinq fois : le coût affiché est gonflé d'un quart

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par l'etude owner-se-renseigner-sur-le-combo-le-plus-efficient-tou (reports/<id>/FINDINGS.txt, 19/09), items crees par le superviseur le 19/09 13:55. orchestrator.py:620,693,727 : `_accumulate_usage` est appele sur CHAQUE evenement `assistant` (le meme message revient 3 a 5 fois dans le flux) PUIS sur `result`, dont l'usage est deja le total de session ; et un essai peut porter PLUSIEURS `result`, chacun republiant un `modelUsage` CUMULE (40 evenements sur ao-indirect-clean/1, de 18,8 M a 21,3 M). Les additionner gonfle le cout de 25 %. Aussi : `usage.output_tokens` des lignes `assistant` est un ACOMPTE (7 541 contre 32 646 factures sur un essai temoin). PORTE : sur un journal d'essai temoin choisi et sur les 3 derniers essais, le total calcule par l'orchestrateur = celui du DERNIER `result` (sortie et cache) a 1 % pres ; un test rejoue un journal fabrique a doublons et doit rendre le bon total. Publier par lib/census/<id>.sh.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`usage_double_count_defects == 0` dans `reports/harness-usage-double-counted/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-usage-double-counted x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
