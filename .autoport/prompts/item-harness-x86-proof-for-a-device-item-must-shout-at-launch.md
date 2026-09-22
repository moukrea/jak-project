> LIS D'ABORD `prompts/item-harness-x86-proof-for-a-device-item-must-shout-at-launch-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un `proof_run.sh <id> x86` lance pour un item dont le critere porte `device=1` le dit A LA PREMIERE LIGNE et l'inscrit dans proof.txt, au lieu de laisser le worker decouvrir au verdict que sa preuve ne sera jamais lue

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
22/09 : hud-eco-gauge a perdu DEUX essais d'affilee (15 et 16) sur le meme constat unique — « l'item exige l'appareil, la preuve est en source=x86 ». L'essai 16 mesurait pourtant hud_gauge_defects=0 : le chiffre n'a jamais ete lu. Le telephone (Redmi eae4df44) etait branche et joignable pendant les deux courses ; ce n'est donc pas une panne d'appareil mais un enchainement de worker : il calibre sur x86 (ce que le harnais lui recommande), puis rend la main sans refaire la course sur l'appareil. ` […suite dans le contrat]

## Livrable
`x86_proof_unwarned` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : nombre de verdicts archives (logs/*/validator-*.txt) dont le constat porte « exige l'appareil, la preuve est en source=x86 », par item et par date. Non nul (au moins 2 sur hud-eco-gauge les 21-22/09). Publier le compte et la liste.

2. L'AVERTISSEMENT EXISTE : pour un item dont le critere contient `device=1`, `lib/proof_run.sh <id> x86` ecrit, AVANT de lancer le moteur, une ligne visible dans son jour […suite dans le contrat]

## Preuve exigee
`x86_proof_unwarned == 0` dans `reports/harness-x86-proof-for-a-device-item-must-shout-at-launch/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-x86-proof-for-a-device-item-must-shout-at-launch x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder dans le jeu : c'est du harnais. L'effet se lit au journal d'une course de calibration : le worker est prevenu tant qu'il lui reste du temps pour refaire la course sur le telephone..

## Hors perimetre
Ne change AUCUN critere de porte et n'assouplit rien : une preuve x86 sur un item a critere device reste refusee. Ne lance pas de course de lui-meme (c'est harness-judge-runs-the-proof-when-the-worker-left-none). Ne touche pas au choix d'appareil ni a pick_device.sh. Tout ce qui n'est pas cet item.
