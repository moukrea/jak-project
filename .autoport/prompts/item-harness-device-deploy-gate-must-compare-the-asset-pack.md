> LIS D'ABORD `prompts/item-harness-device-deploy-gate-must-compare-the-asset-pack-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La porte de deploiement sur appareil compare AUSSI le pack d'assets GOAL, pas seulement libgk.so : un essai qui ne touche que du GOAL ne doit plus mesurer le pack PRECEDENT en croyant avoir livre le sien

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
22/09, 5e exposition (essais 11, 12, 13, 16, 17 de hud-eco-gauge). `lib/deploy_verify.sh:30` ne compare QUE `lib/arm64-v8a/libgk.so`. Le pack d'assets GOAL (`assets/bundle/jak1_cgo.zip`, qui porte GAME.CGO et ENGINE.CGO) n'est compare NULLE PART. Consequence pour un essai 100 % GOAL : le binaire est identique, la porte ecrit `proof_binary_decision=identique` et `deploy_attempted=0`, rien n'est pousse — et la course mesure le pack de l'essai PRECEDENT en le prenant pour le sien. L'essai 17 n'a do […suite dans le contrat]

## Livrable
`asset_deploy_ungated` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : parmi les preuves appareil archivees, combien portent `proof_binary_decision=identique` ET `deploy_attempted=0` alors que le commit de l'essai ne touchait que des fichiers `goal_src/` ou des assets. Non nul (au moins 5 sur hud-eco-gauge). Publier le compte, l'item, l'essai et le commit de chacun.

2. LA PORTE LIT LES DEUX : le chemin appareil de `proof_run.sh` appelle `deploy_verify_assets.sh` et pu […suite dans le contrat]

## Preuve exigee
`asset_deploy_ungated == 0` dans `reports/harness-device-deploy-gate-must-compare-the-asset-pack/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-device-deploy-gate-must-compare-the-asset-pack x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : `.autoport/lib/deploy_verify.sh` (ligne 30 : la comparaison qui ne lit que libgk.so), `.autoport/lib/deploy_verify_assets.sh` (ecrit, jamais appele), et le chemin appareil de `.autoport/lib/proof_run.sh`..

## Hors perimetre
Ne touche pas au moteur ni au jeu. Ne touche pas au publieur d'APK (`auto_push_builds.sh`) : il pousse bien le build a l'owner, le trou est cote PREUVE.
