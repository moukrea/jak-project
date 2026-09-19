# L'agent principal relit 20,7 millions de jetons de mémoire par essai : c'est là que part l'argent, pas dans le choix des modèles

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par l'etude owner-se-renseigner-sur-le-combo-le-plus-efficient-tou (reports/<id>/FINDINGS.txt, 19/09), items crees par le superviseur le 19/09 13:55. MESURE : l'agent principal pese 86,4 % des jetons d'un essai ; 20,7 M de jetons de cache relus par essai ; 93 messages par essai. Le [1m] (pas de compaction) double le cout (35,82 $ contre 17,25 $) sans rendre plus de verts. LEVIERS A CHIFFRER, pas a supposer : (1) taille du prompt d'item + DIRECTIVES + contrat relus a chaque tour (mesurer en jetons) ; (2) seuil de compaction et taille de contexte que Claude Code garde entre les tours ; (3) sorties d'outils volumineuses relues (journaux, proof.txt entiers) ; (4) nombre de tours par essai (93 messages) — quels tours sont de l'attente (boucles de sleep/grep sur un build ou une preuve) que le juge pourrait porter a la place du worker (cf. items harness-judge-*). PORTE : cout par essai mesure sur >= 5 essais APRES, sur des items comparables, contre les 278 essais opus-5/high de reference (17,25 $) : baisse >= 20 % avec un taux de verts non degrade (fenetre a nommer), sinon defaut. Le rapport nomme le levier qui a paye.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`context_volume_defects == 0` dans `reports/harness-main-agent-context-volume/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-main-agent-context-volume x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine (cout par essai AVANT/APRES sur les memes items, jetons de cache lus par essai)..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
