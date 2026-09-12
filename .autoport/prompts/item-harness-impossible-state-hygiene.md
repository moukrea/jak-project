> LIS D'ABORD `prompts/item-harness-impossible-state-hygiene-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'etat « preuve impossible » se purge, et se lit sous le nom que la course a vraiment ecrit

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
TROIS SIGNALEMENTS DU 12/09 (reports/harness-proof-impossible-must-be-read/FINDINGS.txt), sur le mecanisme livre la nuit meme.
1. RIEN NE PURGE un `proof-impossible.txt` debout. `proof_run.sh` ne l'efface qu'a sa propre relance, sur le MEME item et le MEME bras. Un item abandonne en cours de route garde donc son etat, et `autoport status` continue d'annoncer une impossibilite perimee — a l'owner.
2. NOM DE FICHIER DIVERGENT, deja mesure : `proof_run.sh:766` ecrit `proof$SUF-wait.txt`, donc `proof-off-wait.txt` pour le bras d'ablation. Le recensement de `harness-attempt-not-burned-by-foreign-cause` lit un `proof-wait.txt` code EN DUR. L'attente du bras d'ablation n'est donc lue par personne, […suite dans le contrat]

## Livrable
`impossible_hygiene_defects` = 0, somme de termes publies SEPAREMENT.
1. Un etat d'impossibilite est PURGE des qu'il ne decrit plus le present : changement d'item, changement de bras, ou course ulterieure aboutie. Publier le compte d'etats purges et le compte d'etats encore debout, separement. Un zero d'etats debout se lit « rien en cours », jamais « rien verifie ».
2. Preuve a deux bras sur un etat SEME : un etat perime doit disparaitre du texte de statut dans le bras d'APRES et y figurer dans celui d'AVANT. C'est le texte RENDU qui est juge, pas une intention.
3. Les noms de fichiers d'attente sont derives du MEME endroit par l'ecrivain et par le lecteur. Publier, par bras, le nom ecrit et […suite dans le contrat]

## Preuve exigee
`impossible_hygiene_defects == 0` dans `reports/harness-impossible-state-hygiene/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-impossible-state-hygiene x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est ce que le harnais raconte quand il n'a pas pu mesurer..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change pas la detection de l'impossibilite elle-meme.
