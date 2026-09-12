> LIS D'ABORD `prompts/item-harness-attempt-not-burned-by-foreign-cause-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un essai ne brule plus pour une cause exterieure a l'item

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
QUATRE SIGNALEMENTS DU 12/09 (reports/harness-commit-paths-all-or-nothing/FINDINGS.txt). Tous disent la meme chose : un essai est COMPTE pour une salete que l'item n'a pas le droit de nettoyer, ou pour une ressource qu'il ne controle pas.
1. GATE 0 rend `fail` quand l'arbre est sale : l'essai compte, et la consigne renvoyee au worker lui demande de nettoyer l'arbre d'un AUTRE item — ce que son perimetre lui interdit. Il peut bruler ses cinq essais dessus.
2. Un chemin refuse par `git add` et non committable reste sale INDEFINIMENT : represente et re-refuse a chaque essai suivant. Le correctif du 12/09 ne le PERD plus, il ne le RESOUT pas. Une salete permanente declenche GATE 0 en boucle sur […suite dans le contrat]

## Livrable
`foreign_cause_defects` = 0, somme de termes publies SEPAREMENT.
1. Une salete ETRANGERE a l'item ne compte plus comme un essai rate : elle est nommee, publiee, et l'essai est classe a part. Publier le compte de fichiers sales etrangers et le compte d'essais ainsi requalifies. Un zero se lit « aucune salete etrangere », jamais « pas regarde ».
2. Un chemin durablement non committable est SIGNALE une fois et cesse d'etre represente : publier la liste des chemins mis de cote et depuis quand. Une salete permanente qui rebloque chaque item est pire que la perte qu'elle remplace.
3. Le territoire moteur est defini a UN SEUL endroit, lu par les deux portes. Publier la liste effective que chaque po […suite dans le contrat]

## Preuve exigee
`foreign_cause_defects == 0` dans `reports/harness-attempt-not-burned-by-foreign-cause/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-attempt-not-burned-by-foreign-cause x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la comptabilite des essais et la definition du territoire moteur..

## Hors perimetre
Ne touche a aucun code du jeu. Ne nettoie pas l'arbre, ne debloque aucun item.
