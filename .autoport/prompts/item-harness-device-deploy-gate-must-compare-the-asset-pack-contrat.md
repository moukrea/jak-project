# La porte de deploiement sur appareil compare AUSSI le pack d'assets GOAL, pas seulement libgk.so : un essai qui ne touche que du GOAL ne doit plus mesurer le pack PRECEDENT en croyant avoir livre le sien — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

22/09, 5e exposition (essais 11, 12, 13, 16, 17 de hud-eco-gauge). `lib/deploy_verify.sh:30` ne compare QUE `lib/arm64-v8a/libgk.so`. Le pack d'assets GOAL (`assets/bundle/jak1_cgo.zip`, qui porte GAME.CGO et ENGINE.CGO) n'est compare NULLE PART. Consequence pour un essai 100 % GOAL : le binaire est identique, la porte ecrit `proof_binary_decision=identique` et `deploy_attempted=0`, rien n'est pousse — et la course mesure le pack de l'essai PRECEDENT en le prenant pour le sien. L'essai 17 n'a donne un chiffre juste que parce que le pack a ete installe A LA MAIN (`notes/essai17-livraison.sh`).
Le correctif est deja ECRIT et MORT : `.autoport/lib/deploy_verify_assets.sh` existe et n'est appele par AUCUN chemin appareil de `proof_run.sh`. Un garde ecrit mais jamais branche coute plus cher que pas de garde, parce qu'il donne l'impression que le trou est bouche.
Ordre de l'owner du 22/09 : « Le build ne livre pas les assets... c'est un truc que tu devrais corriger tout seul. »

## Livrable — le contrat, en entier

`asset_deploy_ungated` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : parmi les preuves appareil archivees, combien portent `proof_binary_decision=identique` ET `deploy_attempted=0` alors que le commit de l'essai ne touchait que des fichiers `goal_src/` ou des assets. Non nul (au moins 5 sur hud-eco-gauge). Publier le compte, l'item, l'essai et le commit de chacun.

2. LA PORTE LIT LES DEUX : le chemin appareil de `proof_run.sh` appelle `deploy_verify_assets.sh` et publie, cote a cote, l'empreinte LOCALE et l'empreinte SUR L'APPAREIL du pack (les octets du zip, pas une date, pas le md5 du binaire). Une divergence force le deploiement ; un deploiement qui echoue est un ROUGE immediat, jamais un `identique` silencieux.

3. CONTROLE POSITIF FABRIQUE : partir d'un appareil portant le pack N-1, changer UN SEUL octet observable du pack local sans toucher a libgk.so, et montrer que la porte d'AVANT rend `identique/deploy_attempted=0` la ou la porte d'APRES deploie et le dit. Publier les deux verdicts.

4. CONTROLE NEGATIF : pack local identique au pack de l'appareil -> aucun deploiement, `asset_deploy_ungated=0`, et la course tourne. La porte ne doit pas repousser le pack a chaque essai.

5. AUCUNE LIVRAISON A LA MAIN : `notes/essai17-livraison.sh` et tout equivalent deviennent inutiles. Le dire, et publier le terme qui le prouve.

## Hors perimetre

Ne touche pas au moteur ni au jeu. Ne touche pas au publieur d'APK (`auto_push_builds.sh`) : il pousse bien le build a l'owner, le trou est cote PREUVE.

## Ou l'owner regardera

`.autoport/lib/deploy_verify.sh` (ligne 30 : la comparaison qui ne lit que libgk.so), `.autoport/lib/deploy_verify_assets.sh` (ecrit, jamais appele), et le chemin appareil de `.autoport/lib/proof_run.sh`.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

