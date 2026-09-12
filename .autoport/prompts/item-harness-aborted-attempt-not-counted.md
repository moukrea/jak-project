> LIS D'ABORD `prompts/item-harness-aborted-attempt-not-counted-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un essai TUE par le lanceur ne compte pas comme un essai rate

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
RECENSEMENT DU 12/09 SUR LES JOURNAUX. Le CLI attend 600 s les taches de fond d'un worker qui a rendu la main, puis les TERMINE : « Background tasks still running after 600s; terminating ». Le worker n'a rien conclu, mais l'orchestrateur enchaine sur le validateur, qui juge un arbre incoherent — source moteur plus recente que la preuve, sha du binaire different de celui du disque, preuve x86 sur un item qui exige l'appareil — et l'essai est COMPTE dans `max_retries`.
QUATRE ESSAIS DETRUITS AINSI : Grecharged-mesh-browser essai 6, refset-replay-stable essai 2, lighting-hdr essai 7, et lighting-legacy-purge essai 8 le 12/09 a 02:2x. Ce dernier a epuise le budget d'un item que l'owner avait mis […suite dans le contrat]

## Livrable
`aborted_attempt_defects` = 0, somme de termes publies SEPAREMENT.
1. L'orchestrateur RECONNAIT un essai tue par le lanceur : la ligne « Background tasks still running after ...; terminating » dans la sortie du worker est lue, et l'essai est marque ABORTE. Publier le compte d'essais abortes reconnus.
2. Un essai aborte N'INCREMENTE PAS `max_retries`. Preuve a deux bras sur un etat jetable : le bras d'AVANT compte l'essai, le bras d'APRES ne le compte pas, meme entree.
3. Un essai aborte ne passe PAS au validateur : juger un arbre que le worker n'a pas fini de poser produit des constats qui ne decrivent aucun defaut du travail. Publier le compte de validations evitees.
4. Le journal le DIT en […suite dans le contrat]

## Preuve exigee
`aborted_attempt_defects == 0` dans `reports/harness-aborted-attempt-not-counted/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-aborted-attempt-not-counted x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la comptabilite des essais du harnais..

## Hors perimetre
Ne touche a aucun code du jeu. Ne debloque et ne reouvre aucun item au passage : rendre ses essais a lighting-legacy-purge est une decision de l'owner, pas de ce chantier.
