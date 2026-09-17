# Les libelles ecrits POUR le tactile repartent dans l'APK

## Defaut cite
- 2026-09-12 : « pour le appuie sur start ou touche l'ecran j'avais deja valide ce matin, je vais pas le valider 45 fois »

## Cause connue
Trouve par le worker de hd-stretch-flag-in-game-logic le 2026-09-10, en bâtissant l'APK de sa propre preuve. `android/build_cgo_pack.sh` compare le md5 des surcharges figees `out/jak1-android-text/{0,1}COMMON.TXT` (datees du 31/08) au banc bureau FRAIS ; elles ne correspondent plus, la regeneration (`.autoport/gtt_build_android_text.sh`) ne s'est pas declenchee, et le packeur les ABANDONNE : `android-overrides: 0`. Son propre message le dit — « android-only wording for that bank is lost this build ». L'APK part donc avec le banc bureau : l'ecran-titre affiche « Press Start » / « Appuie sur start » au lieu de « Press Start or Tap Screen » / « Appuie sur start ou touche l'ecran » (id #x16e), sur un appareil ou il n'y a pas de bouton start. Ce n'est pas une regression d'un jour : ca se reproduit a CHAQUE build ou le banc bureau a bouge, en silence, depuis le 31/08.

## Livrable
La surcharge tactile est PRODUITE a partir du banc courant au moment de l'empaquetage, jamais relue d'une copie figee : une perte qui se repete se rend impossible au point de PRODUCTION, pas detectable au point de controle. Si elle ne peut pas etre produite, l'empaquetage ECHOUE au lieu de livrer un texte degrade en silence. Le moteur publie, sur l'appareil, `android_text_touch_variant_ids` = le nombre d'identifiants du banc CHARGE dont le texte est la variante tactile et non celle du bureau (aujourd'hui : 0).

## Preuve exigee
`android_text_touch_variant_ids >= 1` dans `reports/android-text-overrides-dropped/proof.txt`.
Le proof se produit par `lib/proof_run.sh android-text-overrides-dropped device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : ecran-titre, avant d'appuyer : le libelle doit parler de toucher l'ecran, pas d'un bouton start.

## Hors perimetre
Ne pas retraduire le jeu ni toucher aux 23 bancs livres. On repare la CHAINE de la surcharge tactile.
