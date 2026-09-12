> LIS D'ABORD `prompts/item-harness-verdict-integrity-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le verdict d'un item de harnais est aussi epingle et aussi falsifiable que celui d'un item moteur

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
CINQ SIGNALEMENTS DU 12/09 (reports/harness-proof-props-pin/FINDINGS.txt).
1. `validators/generic.sh:23` refuse une preuve dont une source de `game/ common/ android/ goal_src/` est plus RECENTE qu'elle, mais ne regarde PAS `.autoport/`. Or le verdict d'un item de harnais vit maintenant dans `lib/census/<id>.sh` : il peut etre edite APRES la course sans que la porte s'en apercoive. Le precedent `builder-checkpoint-steals-work` avait mis sa somme dans `game/system/checkpoint_census.cpp` exactement pour ca.
2. Le teardown de FIN de course (trap EXIT de proof_run.sh, ~ligne 460) ne recoit pas `AUTOPORT_TEARDOWN_REPORT` : ce qu'il efface apres la course reste muet, et la course suivante repart d' […suite dans le contrat]

## Livrable
`verdict_integrity_defects` = 0, somme de termes publies SEPAREMENT.
1. La fraicheur du validateur couvre les sources qui PRODUISENT le verdict, `.autoport/` comprise. Publier le nombre de fichiers epingles et leur empreinte RECALCULEE a la lecture, pas seulement recopiee. Une preuve plus vieille que son propre juge est refusee.
2. Le teardown de FIN de course dit ce qu'il efface, comme celui du debut. Publier le compte et les noms. Un zero se lit « rien n'etait pose », jamais « pas regarde ».
3. Le bras x86 relit `/proc/<pid>/environ` du processus MESURE. Publier le compte de variables relues a cet endroit, et le comparer a celui du shell : l'ecart est la grandeur qui compte.
4. Un `getprop […suite dans le contrat]

## Preuve exigee
`verdict_integrity_defects == 0` dans `reports/harness-verdict-integrity/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-verdict-integrity x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est l'integrite des preuves du harnais lui-meme..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change le verdict d'aucun item deja ferme.
