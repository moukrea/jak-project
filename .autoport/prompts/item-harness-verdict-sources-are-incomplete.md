> LIS D'ABORD `prompts/item-harness-verdict-sources-are-incomplete-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Tout ce qui PRONONCE un verdict est epingle, y compris le critere lui-meme

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SEPT SIGNALEMENTS DU 12/09 (reports/harness-verdict-integrity/FINDINGS.txt). Le chantier precedent epingle les SCRIPTS qui produisent un verdict. Il en reste trois familles dehors, et un piege intermittent.
1. LE CRITERE LUI-MEME n'est pas epingle. `gate.key/op/value` et `frames_min` vivent dans `backlog.yaml`, que l'orchestrateur reecrit, et `verdict_sources_sha` ne les couvre pas. Un critere peut donc changer apres la course sans que la fraicheur s'en apercoive. Le critere produit le verdict autant que le script qui le calcule.
2. LES HUIT SCRIPTS D'ACQUIS (`.autoport/acquis/*.sh`) prononcent un verdict a CHAQUE fermeture (GATE 3) et ne sont epingles par rien : ni la fraicheur moteur, ni ` […suite dans le contrat]

## Livrable
`verdict_sources_defects` = 0, somme de termes publies SEPAREMENT.
1. Le CRITERE entre dans l'empreinte epinglee : publier l'empreinte du critere jugee et celle relue a la fermeture. Preuve a deux bras — modifier le critere apres la course doit REFUSER dans le bras d'APRES et passer dans celui d'AVANT.
2. Les scripts d'acquis entrent dans la meme empreinte. Publier leur nombre et leur empreinte collective : un compte de huit qui tombe a sept est un defaut, pas un detail.
3. La derivation ignore les commentaires. Publier le compte de fichiers epingles avant et apres ce changement, et la liste de ceux qui sortent : chacun doit etre justifiable.
4. `proof.txt` n'est plus ecrit apres son propre […suite dans le contrat]

## Preuve exigee
`verdict_sources_defects == 0` dans `reports/harness-verdict-sources-are-incomplete/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-verdict-sources-are-incomplete x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est ce qui a le droit de changer entre une preuve et son verdict..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change aucun critere existant au passage. Priorite 32 volontaire : la refonte de l'eclairage passe AVANT.
