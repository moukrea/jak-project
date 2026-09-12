> LIS D'ABORD `prompts/item-harness-proof-file-has-no-writer-lock-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une course tuee ne peut plus ecraser la preuve de celle qui lui succede

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
DEUX SIGNALEMENTS DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt), dont un CHIFFRE et reproduit dans l'heure.
1. AUCUN ecrivain unique, AUCUN verrou sur `reports/<id>/proof.txt`. Un essai TUE laisse son `proof_run.sh` VIVANT : il finit sa course et ecrit sa preuve par-dessus celle de l'essai suivant. Le validateur juge alors la course d'AVANT en croyant juger celle d'apres.
2. RIEN N'EMPECHE UN COMMIT EXTERIEUR PENDANT UNE COURSE. Mesure du 12/09 : le SUPERVISEUR a commite a 16:12:59 pendant une course, et l'empreinte des sources de verdict a bouge entre la mesure et son jugement. L'essai a ete refuse pour une raison qui ne decrivait aucun defaut de son travail. Le meme defau […suite dans le contrat]

## Livrable
`proof_writer_defects` = 0, somme de termes publies SEPAREMENT.
1. UN SEUL ecrivain par `proof.txt`, par verrou : une seconde course sur le meme item attend ou refuse, elle n'ecrase pas. Publier le compte de tentatives d'ecriture concurrentes rencontrees.
2. Une preuve porte l'identite de la COURSE qui l'a produite, et la porte refuse une preuve dont l'identite ne correspond pas a l'essai courant. Preuve a deux bras : une preuve d'un essai precedent, semee, doit etre ACCEPTEE dans le bras d'avant et REFUSEE dans celui d'apres.
3. Un `proof_run.sh` orphelin est detecte et arrete quand son essai a ete tue : publier le compte d'orphelins trouves et arretes.
4. Un commit exterieur pendant une co […suite dans le contrat]

## Preuve exigee
`proof_writer_defects == 0` dans `reports/harness-proof-file-has-no-writer-lock/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-file-has-no-writer-lock x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la garantie que le verdict porte sur la bonne course..

## Hors perimetre
Ne touche a aucun code du jeu. N'interdit aucun commit.
