DIRECTIVES v07b292c21f
L'ESSAI 10 A ABOUTI : ce fichier n'est plus un relais, c'est le releve de ce qui a debloque
l'item. Le verdict complet est dans `report.txt`, la mesure dans `proof.txt`.

## ETABLI (mesure)
`grass_baseline_gaps=0` sur eae4df44, 55 920 images, crash=0, 1816 s, dix cellules de 300
images au meme vantage (spreads 0 mm / 0 dm), binaire 6f1a86f039b3e3e86497f3113361f1e9.
CE QUI BLOQUAIT LES ESSAIS 8, 9 ET LE DEBUT DU 10 : le telephone etait en Direct Boot, PIN
jamais saisi depuis son demarrage de 16:23. Grandeurs lues, pas deduites :
  dumpsys user -> [0=RUNNING_LOCKED] ; dumpsys trust -> deviceLocked=1, strongAuth=0x1
  getprop sys.boot_completed -> 1  (le demarrage etait FINI : ce n'etait pas l'excuse de 16:24)
  cmd package resolve-activity --brief org.opengoal.gk.jak1 -> No activity found
CE DERNIER TEMOIN ETAIT LE DECISIF et manquait a l'essai 9 : ce n'etait pas l'INSTALLATION qui
etait impossible, c'etait LE LANCEMENT. A 16:42:28 l'owner a deverrouille ; a 16:42:30 la garde
binaire a installe l'APK du premier coup (`Success`) et publie
`proof_device_launch_resolve=org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity`. Le binaire
n'a JAMAIS ete en cause, et aucune reconstruction n'a eu lieu.
PISTE MIUI MORTE, MESUREE : les 4 reglages d'installation ADB etaient DEJA a 0 et le refus
persistait. Ne pas la refaire.

## TENTE, et ce que ca a donne
1. `proof_run.sh`, bloc VERROU-ECRAN avant la garde binaire (commit ecf837bb21) : rend l'etat
   NOMME `appareil-verrouille` (die3, code 3) au lieu du code 6 qui ordonnait de reconstruire.
   Eprouve sur trois controles, puis EXERCE en course reelle sur le bras deverrouille — il a
   publie ses trois temoins et laisse passer. `impossible_state.read` ne filtre pas sur la
   raison : tout etat nomme requalifie l'essai, verifie dans orchestrator.py:1664.
2. `notes/watch-unlock-essai10.sh` (pid 327728) : sonde `dumpsys user` toutes les 10 s et lance
   la course DES le deverrouillage. C'est ce qui a converti un geste de 2 s en une mesure.
3. PREVENIR L'OWNER : IMPOSSIBLE, et c'est la dette qui reste. `lib/notify.sh:2` porte un
   `exit 0` pose par l'owner le 13/06 ; l'« alerte ntfy » que l'essai 9 dit avoir envoyee n'est
   jamais partie. Aucun autre canal n'existe. Je n'ai pas re-active ntfy : l'owner l'a coupe
   expressement — c'est au superviseur de choisir le canal, pas au worker.

## RESTE
1. Rien pour cet item : la mesure est faite, `owner_test` n'a rien a montrer (aucun pixel).
2. Pour la campagne : le gisement de culling est chiffre (22,8 % a medium, `submitted ==
   frustum_tested` aux cinq paliers) et le cout est 99,8 % GPU. Voir FINDINGS.
3. Pour le harnais : donner au harnais un moyen de DEMANDER un geste physique a l'owner. Trois
   essais ont attendu un PIN que personne n'a jamais su qu'il fallait saisir.
