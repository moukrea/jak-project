# Une construction sans edition cesse de tout recompiler, et de laisser un binaire perime derriere elle

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
MESURE DU 12/09 (reports/census-audit-blind-spots/FINDINGS.txt), horodatee.
Une construction incrementale SANS AUCUNE edition de source recompile les 338 cibles de `runtime` a chaque invocation de `cmake --build build --target gk`. Pire : les DEUX premieres invocations ont laisse `build/game/gk` NON RELIE — `libruntime.a` a 14:43:15 pour un `gk` reste a 14:36:03 — et il a fallu une TROISIEME passe de 445 s pour que le lien se fasse.
LE CODE DE RETOUR ETAIT 0 AUX TROIS PASSES. Un worker qui fait confiance a ce zero mesure donc un binaire d'AVANT son propre changement, et seul un `ls -la` compare le revele. C'est la classe de defaut la plus chere du projet : une preuve qui decrit un autre binaire que celui qu'on croit.
COUT : environ sept minutes par cycle de preuve, sur chaque item qui bati. Multiplie par le nombre d'essais d'une journee, c'est le poste de gaspillage le plus gros que la journee ait mesure.

## Livrable
`build_reinvalidation_defects` = 0, somme de termes publies SEPAREMENT.
1. LA CAUSE EST NOMMEE, pas contournee : publier ce qui invalide les 338 cibles — horodatage regenere, fichier genere a chaque configuration, dependance sur un repertoire. Un correctif qui reduit le temps sans nommer la cause ne compte pas.
2. Une construction sans edition de source recompile ZERO cible : publier le compte de cibles recompilees, AVANT et APRES, sur deux invocations consecutives.
3. LE LIEN NE PEUT PLUS ETRE SAUTE EN SILENCE : publier, apres chaque construction, l'horodatage du binaire et celui de la bibliotheque la plus recente dont il depend. Un binaire plus vieux que sa dependance est un DEFAUT, pas un avertissement, et il ne peut plus sortir avec un code de retour nul.
4. Le gain est chiffre en secondes, mesure sur trois invocations consecutives, AVANT et APRES.

## Preuve exigee
`build_reinvalidation_defects == 0` dans `reports/build-tree-reinvalidates-itself/proof.txt`.
Le proof se produit par `lib/proof_run.sh build-tree-reinvalidates-itself x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible dans le jeu. Le gain se voit sur la duree de chaque essai..

## Hors perimetre
Ne change aucun code du moteur. Ne touche pas au build Android, seulement au build de bureau.
