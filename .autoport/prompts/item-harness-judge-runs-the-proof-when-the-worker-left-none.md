> LIS D'ABORD `prompts/item-harness-judge-runs-the-proof-when-the-worker-left-none-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Quand le worker termine sans preuve NEUVE, le juge lance lui-meme `proof_run.sh <id> device`, attend, puis juge : la mesure n'est plus a la charge du worker

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 16/09 (« vas-y ! ») apres le releve du superviseur : 125 verdicts en 4 jours, 72 echecs, dont 37 « preuve PERIMEE reutilisee » (source editee apres la preuve, proof_attempt_id d'un autre essai, sha du binaire, verdict_sources) et 11 « proof.txt absent ». 48 echecs sur 72 = le worker n'a pas laisse de mesure neuve, parce qu'une course appareil dure 7 a 30 min et qu'il rend la main avant. Le juge refuse alors une vieille preuve et COMPTE UN ESSAI : le budget de l'item part en plomberie, pas […suite dans le contrat]

## Livrable
`stale_proof_verdicts` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : compte de verdicts archives (logs/*/validator-*.txt) dont le premier constat est une preuve perimee ou absente, par item ; non nul (48 sur 4 jours au 16/09).

2. LE JUGE MESURE : quand le worker est sorti et qu'aucune course de cet item n'est vivante (item precedent), si proof.txt est absent OU plus vieux que le debut de l'essai OU refuse pour identite (attempt_id, sha binaire, sources), l'orchestra […suite dans le contrat]

## Preuve exigee
`stale_proof_verdicts == 0` dans `reports/harness-judge-runs-the-proof-when-the-worker-left-none/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-judge-runs-the-proof-when-the-worker-left-none x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit dans le tableau des causes d'echec : les lignes « preuve perimee » et « preuve absente » tombent a zero..

## Hors perimetre
Ne change pas les criteres des portes ; ne relance jamais une course vivante ; ne touche ni aux validateurs d'items ni a proof_run.sh au-dela de son appel. Tout ce qui n'est pas cet item.
