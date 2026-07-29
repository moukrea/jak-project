# PHASE Grecharged-loader-packfix — LE BUILD NE DÉMARRE PLUS SUR L'APPAREIL DE L'OWNER

Owner : "je veux mes meshes corrigés, mon build avec le mesh browser et compagnie, débrouilles toi !"

C'est la phase la plus prioritaire du projet : l'owner n'a AUCUN build utilisable contenant le
travail des trois derniers jours. Tout est écrit, mesuré, empaqueté — et rien ne démarre chez lui.

## CE QUI EST ÉTABLI, MESURÉ SUR SON HONOR (BKQ-N49, serial AREE026206000788)
* Le build du 27/07 (APK 345 Mo, pack embarqué 190 Mo) DÉMARRE : il extrait ses 74 fichiers CGO
  dans files/cgo/jak1 et le process vit (>70 s observées).
* Les builds du 28 et du 29 (APK 580 Mo / 1,0 Go, pack embarqué 420 Mo) MEURENT immédiatement,
  AVANT toute extraction : files/cgo et files/custom restent absents, le process disparaît en <15 s.
* Le seul changement structurel entre les deux : le pack embarqué est passé de 190 Mo à 420 Mo
  parce qu'on y a déplacé les fr3 (217 Mo), les sidecars, l'index mesh et les textures recharged
  (règle owner : ce qui n'est pas original va dans l'APK). C'est le suspect n°1.
* LoaderActivity.java entoure unpackCgoPackIfNeeded + unpackCustomPackIfNeeded d'un
  try/catch(Throwable) qui affiche "Setup failed" — mais le PROCESS MEURT quand même, donc ce
  qui le tue n'est pas une exception Java rattrapable (OOM du process, kill système, ou mort
  dans du natif). À déterminer.
* PIÈGE DE TEST, à ne pas répéter : `am start ... /org.opengoal.gk.MainActivity` COURT-CIRCUITE
  LoaderActivity, donc n'extrait RIEN. Le point d'entrée réel est
  `org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity` (cmd package resolve-activity le confirme).
  Le superviseur a perdu des heures là-dessus.
* Le Honor CHIFFRE son logcat (lignes "(HKS)...") : aucune sortie applicative lisible, et aucun
  tombstone n'est produit pour ce crash. Le diagnostic doit donc passer par des ÉCRITURES DE
  FICHIERS depuis l'app (comme files/asset_route.txt le fait déjà) ou par dumpsys/meminfo.

## LIVRABLE
1. Trouver POURQUOI le process meurt avant l'extraction, avec une preuve, pas une hypothèse. Pistes
   par ordre de vraisemblance :
   a) mémoire : extraire/valider un pack de 420 Mo dans le heap Java ou en mémoire native peut
      dépasser la limite du process. Vérifier la consommation (dumpsys meminfo pendant l'unpack),
      le mode d'ouverture de l'asset (ACCESS_STREAMING vs buffer complet), et la validation CRC.
   b) taille d'asset : un asset compressé de 420 Mo dans l'APK peut heurter des limites de
      l'AssetManager. Mesurer, ne pas supposer.
   c) durée : si l'extraction dépasse un watchdog Android, le système tue le process.
2. CORRIGER de façon structurelle, pas en réduisant le contenu : l'owner a exigé que le dérivé
   voyage dans l'APK, et le navigateur de mesh a besoin de son index. Si l'extraction monolithique
   ne passe pas, streamer/segmenter, extraire à la demande, ou poser les données autrement — mais
   l'owner doit avoir SES données dans SON APK.
3. LIVRER un APK qui, sur le Honor, via LoaderActivity : démarre, extrait, et atteint le menu.
4. VÉRIFIER SUR L'APPAREIL, pas dans le paquet : la preuve attendue est le process vivant + les
   fichiers extraits + la ligne MESH BROWSER RÉELLEMENT AFFICHÉE à l'écran. Le superviseur a
   plusieurs fois confondu "la chaîne est dans le fichier" et "la fonctionnalité marche".

## CE QUI DOIT ARRIVER À L'OWNER AU BOUT
* Les corrections d'orientation (village1 66,8 % -> 96,99 % de sommets bien orientés, 26 sidecars).
* Le navigateur de mesh, index des 25 niveaux, atteignable depuis RECHARGED SETTINGS (la ligne est
  TOUJOURS active, même master OFF — c'est écrit dans progress-pc.gc).
* Les deux APK : damier et normal.

## CONTRAINTES
* Le Honor est branché et disponible (serial AREE026206000788). Le Redmi est débranché.
* Un build de secours FONCTIONNEL est installé dessus (.autoport/dist/app-jak1-NORMAL-recharged.apk,
  du 27/07) : ne le casse pas sans avoir mieux à proposer, l'owner joue avec.
* Mesure visuelle in-game toujours interdite : démarrage/crash/perf uniquement.
* Toujours reconstruire avec `./build.sh android-arm64 --pbr` (sans --pbr, Loader.cpp ne compile
  même pas : références recharged_pbr_* non gardées).

--------------------------------------------------------------------------------
CHANGEMENT D'APPAREIL (owner, 2026-07-29) — LE HONOR EST REPARTI, C'EST LE REDMI
--------------------------------------------------------------------------------
Owner : "J'ai dû récupérer le Honor, j'ai rebranché le Redmi, faudra pousser les prochains builds sur
jak-builds... Utilise le Redmi pour tes tests."

* L'appareil de test est désormais le REDMI, serial eae4df44. Le Honor (AREE026206000788) n'est plus
  disponible : ne l'attends pas, ne t'appuie pas dessus.
* La preuve device déjà obtenue sur le Honor RESTE VALABLE et acquise (process vivant 15-120 s,
  74 CGO, 428 Mo de pack, ligne MESH BROWSER photographiée). Ne la refais pas pour le plaisir ;
  refais-la sur le Redmi seulement si tu modifies quelque chose qui peut l'invalider.
* ATTENTION, le Redmi est plus LENT que le Honor. Le crash SIGILL corrigé était une course dont
  l'issue dépendait de la vitesse : un défaut de ce type peut donc NE PAS se manifester sur le
  Redmi alors qu'il frapperait l'owner. Ne conclus jamais "ça marche" du seul fait que le Redmi
  démarre — dis explicitement ce que le Redmi peut et ne peut pas prouver.
* LIVRAISON : les builds vont sur la release jak-builds jak1-rtlight-wip (les deux APK, damier et
  normal, même commit, libgk distincts). L'owner installe depuis là, il n'a plus de câble.
