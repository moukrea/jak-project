# Un rouge de la suite ne du commit d'un autre ne tue plus l'essai qui l'herite

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker de hdr-shadow-range (essai 3, 13/09, FINDINGS.txt). `lib/suite_gate.py:352` refuse la fermeture avec « La suite etait VERTE et ce build la rend rouge » sans lire ses PROPRES grandeurs `unwaived_new` / `unwaived_known`, qui distinguent un rouge NEUF d'un rouge HERITE. Mesure du 13/09 : les deux rouges qui ont tue l'essai 2 de hdr-shadow-range sont nes de `1c197e3620` ([autoport/supervisor], 20:51 — cinq validations de l'owner ont vide « A tester », qu'un test exigeait sans condition), trois commits AVANT le travail de l'essai. L'item les a herites, il ne les a pas fabriques, et il a paye l'essai.

## Livrable
`inherited_red_refusals` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE : compte d'essais refuses par la porte de suite dont TOUS les rouges preexistaient au premier commit de l'essai (bisect sur les journaux archives), publie par item ; non nul.
2. LA PORTE DISTINGUE : un rouge present a la base de l'essai est HERITE et publie comme tel (`unwaived_known`), un rouge absent a la base et present apres est NEUF (`unwaived_new`) ; seul le NEUF refuse la fermeture. Publier les deux comptes et la base retenue.
3. L'HERITE NE MEURT PAS EN SILENCE : un rouge herite est publie dans le rapport de l'essai ET devient un signalement (`-> item:` ou `-> ecarte:`), pour que quelqu'un le repare — l'essai suivant ne doit pas le retrouver.
4. LE TEMOIN A DEUX BRAS : dans un bac a sable, un test rouge a la base et apres = fermeture acceptee et publiee comme heritee ; un test rouge seulement apres = refus. Les deux verdicts cote a cote.
PREUVE : `FEATURE harness-close-gate-separates-inherited-reds armed=1 hits=<fermetures jugees par la porte de suite>` + la ligne `inherited_red_refusals=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`inherited_red_refusals == 0` dans `reports/harness-close-gate-separates-inherited-reds/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-close-gate-separates-inherited-reds x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais qui ne meurent plus pour cette cause..

## Hors perimetre
Ne relache aucun refus sur un rouge NEUF : la porte reste aussi dure sur ce que l'essai a casse. Tout ce qui n'est pas cet item.
