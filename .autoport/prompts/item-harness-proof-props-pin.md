> LIS D'ABORD `prompts/item-harness-proof-props-pin-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un worker doit pouvoir epingler le regime de SA course, et le verifier

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
MECANISME ETABLI LE 12/09 — ce n'est PAS une reecriture du backlog.
`proof_run.sh` lit `proof_props` depuis le backlog a la ligne 145, puis lance `lib/device_teardown.sh` a la ligne 471, qui efface TOUTES les proprietes commencant par `debug.opengoal.` lues sur l'appareil, et seulement APRES pose les siennes (lignes 473 a 486). Une propriete posee par le worker depuis l'hote AVANT la course est donc effacee entre sa pose et le lancement. Seul `proof_props`, qui traverse le teardown dans une variable du script, survit. Signale par le worker du chantier C (reports/hdr-output-regime/FINDINGS.txt, dernier point), verifie ligne a ligne.
CE QUE J'AVAIS REFUSE D'ECRIRE, ET QUI ETAIT BIEN FAUX. Le w […suite dans le contrat]

## Livrable
`pin_props_defects` = 0, somme de termes publies SEPAREMENT.
1. L'EFFACEMENT CESSE D'ETRE SILENCIEUX. Le teardown publie ce qu'il efface : le nombre de proprietes `debug.opengoal.*` trouvees posees a son passage, et leurs noms. Un worker qui en a pose une depuis l'hote doit pouvoir le LIRE dans la preuve, au lieu de mesurer l'autre regime sans rien voir. Un zero se lit « rien n'etait pose », jamais « rien n'a ete efface ».
2. Le chemin de lecture de `proof_props` est trace de bout en bout : ce que le fichier porte, ce que `proof_run.sh` extrait, ce que l'appareil rend a `getprop` APRES le teardown. Publier les trois. L'ecart entre le premier et le troisieme est la grandeur qui compte.
3. Une […suite dans le contrat]

## Preuve exigee
`pin_props_defects == 0` dans `reports/harness-proof-props-pin/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-props-pin x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le harnais : lib/backlog.py, orchestrator.py, lib/proof_run.sh..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change aucun statut d'item existant.
