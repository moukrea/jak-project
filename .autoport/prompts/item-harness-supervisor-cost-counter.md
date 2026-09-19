# Le superviseur coûte 3,38 $ par essai et 11 000 $ depuis le début sans apparaître dans aucun compteur : le compter, puis le réduire

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par l'etude owner-se-renseigner-sur-le-combo-le-plus-efficient-tou (reports/<id>/FINDINGS.txt, 19/09), items crees par le superviseur le 19/09 13:55. MESURE : les transcriptions du superviseur (~/.claude/projects/-home-emeric-code-jak-project/) totalisent 16,0 G de jetons de cache et 35,3 M de sortie, ~11 000 $ au tarif Opus 5 ; 3,38 $ par essai sur la periode Opus 5, 20 % de plus que l'essai lui-meme. Personne ne le regardait. PORTE : (1) un compteur PUBLIE du cout du superviseur par jour, tire des transcriptions, relu par le digest ; (2) la decomposition par activite (digest de 30 min, reponses Linear, veilles, relectures) ; (3) au moins un levier chiffre et mis en oeuvre (ex. : un digest qui ne se reveille que si `status --changed` ou Linear a bouge, calcule par un script sans modele ; reponses Linear plus courtes ; ne pas relire des journaux entiers), avec le cout AVANT/APRES sur 3 jours. Le rapport est ecrit pour l'owner, en francais courant.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`supervisor_cost_defects == 0` dans `reports/harness-supervisor-cost-counter/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-cost-counter x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le rapport reports/<id>/RAPPORT.md : le cout du superviseur par jour et par essai, ce qui le compose (digests, veilles, reponses Linear, relectures de journaux), et les 3 postes les plus chers avec une proposition chiffree chacun. Toi seul tranches ce qu'on coupe..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
