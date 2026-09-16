DIRECTIVES v07b292c21f

## ÉTABLI (mesuré)

AUCUN APPAREIL USB N'EXISTE SUR CETTE MACHINE. `lsusb` ne liste qu'un disque WD, un lecteur de
cartes, une webcam et le Bluetooth Intel — pas un seul appareil Android. Serveur adb tué et
relancé : `List of devices attached` vide. `pick_device.sh` sort en 3. Ce n'est pas un incident adb.

LA COURSE A ÉTÉ LANCÉE, et elle a NOMMÉ son empêchement — c'est ce que l'essai 7 n'avait pas fait.
`lib/proof_run.sh grass-baseline-cost device` (essai `grass-baseline-cost@8`, pid 276419) a pris le
verrou d'écriture, attendu 135 s le verrou de déploiement d'un build arm64 VIVANT (pid 222205),
puis écrit `reports/grass-baseline-cost/proof-impossible.txt` :
`proof_impossible_reason=appareil-non-choisi`, `exit=3`. `impossible.py standing` rend
`standing=1`. `orchestrator.close_gate` lit cet état en GATE -1 (`orchestrator.py:951`) :
l'essai est REQUALIFIÉ, `retries` est rendu, et 3 d'affilée BLOQUENT l'item au lieu de boucler.
La preuve de l'essai 1 n'a PAS été réutilisée ni détruite : copiée dans
`notes/proof-essai1-device-20260915-ARCHIVE.txt`, et `proof_run.sh` ne l'a pas effacée.

UN FAUX VERT CORRIGÉ DANS LA PORTE DE L'ITEM. `publish_gaps` exigeait `render_frames` PRÉSENT sans
jamais le relire : une cellule ÉTEINTE dont la surcharge d'herbe n'aurait pas mordu mesurait
l'herbe ALLUMÉE, publiait une cadence, et `gaps` restait à 0 — les cinq « OFF » devenaient une
copie des cinq « ON » et l'écart ON/OFF, seule grandeur pour laquelle cet item existe, était faux
sans qu'un terme rougisse. Le terme juge maintenant les deux sens (`off ⇒ ==0`, `on ⇒ !=0`) et
nomme le coupable avec sa valeur. Seuil `!= 0` et non un plancher : la course à blanc rend 288/300
au palier very_low (`has_pc_data` faux quelques images, cf. FINDINGS). Denominateur publié à côté :
`grass_baseline_regime_read`. Les deux arbres rebâtis par leur porte (x86 46 s ; arm64 `gk` lié),
marqueur `_vaut_%llu_sous_regime_%s` vérifié par `strings` dans build/game/gk ET
build-android/lib/arm64-v8a/libgk.so.

## TENTÉ, et pourquoi ça a échoué

Preuve APPAREIL : impossible, cause matérielle ci-dessus. Veille USB de 40 min pendant l'essai :
aucun appareil. Bras `--off` non lancé, même cause.
Égalité du VANTAGE entre cellules (clause 1 du contrat) NON corrigée : `autoport_proof.h` n'expose
que `has_key` et `read_uint`, aucun lecteur de TEXTE, et `jak_pos`/`cam_dm` sont du texte. La
corriger demande d'élargir un module partagé par tous les items. Inscrit en FINDINGS, pas fait.

## RESTE

1. Brancher l'USB, puis `lib/proof_run.sh grass-baseline-cost device`. Rien d'autre à préparer.
2. AVANT : vérifier que l'APK porte le `libgk.so` du 16/09 16:09. Le démon `auto_build_apk.sh` a
   refusé son tour (« sources modifiees pendant la fabrication ») parce que l'édition est tombée
   pendant son build ; il retente seul, mais l'APK de 16:05 est ANTÉRIEUR au binaire.
   Contrôle : `unzip -p <apk> lib/arm64-v8a/libgk.so | md5sum` contre le fichier de build-android.
3. NE PAS rééditer game/ common/ android/ goal_src/ après la course.
4. Mode d'échec le plus probable sur appareil : throttling thermique sur les cellules `high` et
   `very_high`, qui passent en DERNIER (FINDINGS ligne 18). Si `cells_short>0`, c'est ça, pas
   l'instrument.
