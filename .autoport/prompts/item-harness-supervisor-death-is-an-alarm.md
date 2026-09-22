> LIS D'ABORD `prompts/item-harness-supervisor-death-is-an-alarm-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La mort du superviseur est elle-meme une alerte : la file « retour owner sans reponse » ne peut pas rester servie a un lecteur qui n'existe plus

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 22/09 : « Pourquoi tu réagis plus a mes feedbacks sur Linear ». Chaine verifiee ce jour-la : linear_sync RECOPIE bien ses commentaires dans owner_feedback (les deux de 10:27 et 10:30 y sont, verbatim), pose « A traiter » sur le ticket, et crie « À TRAITER : JAK-176 » a chaque passage — 7 585 fois dans logs/linear_sync.txt. wake_gate.py insere bien le bloc « RETOURS DE L'OWNER SANS REPONSE » en tete de chaque reveil. TOUT fonctionne sauf le lecteur : la session superviseur (fc2d3cfc, transcript de 318 Mo) a rendu sa derniere reponse a 09:50:56, le reveil de 10:20:48 est reste EN FILE sans jamais etre traite, la demande a ete interrompue a 11:06:42 et la session s'est terminee a 11:07:54 […suite dans le contrat]

## Livrable
`orphan_owner_feedback_defects` = 0, somme de termes publies SEPAREMENT. Un terme non mesure compte 1.

1. LE COUT D'AVANT EST CHIFFRE : sur les 7 derniers jours, pour chaque retour owner recopie dans `owner_feedback`, le delai entre son horodatage Linear et le premier commentaire du harnais poste APRES lui sur le meme ticket (sans reponse = delai ouvert). Publier le nombre de retours au-dela de 2 h et le maximum. Non nul par construction (2 cas le 22/09, 24 h le 21/09).

2. LE LECTEUR EST VIVANT, MESURE : un releve publie dit si un superviseur existe — pid de `.autoport/.supervisor-terminal.json` vivant AVEC le meme starttime (champ 22 de /proc/<pid>/stat, jamais `kill -0` : il reussit sur […suite dans le contrat]

## Preuve exigee
`orphan_owner_feedback_defects == 0` dans `reports/harness-supervisor-death-is-an-alarm/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-death-is-an-alarm x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
