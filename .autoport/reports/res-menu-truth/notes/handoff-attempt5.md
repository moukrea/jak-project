## ÉTABLI
DIRECTIVES vb28ab89244
Essai5 : source 07e19f3ccc, pack a0e3070ffd ; GOAL arm64/x86 compilé, APK installé USB eae4df44, aucun build C++.
Unique proof_run device : 2026-09-15T05:20:28Z, 309 s, frames 9000, crash 0, res_menu_defects 2.
Matrice 108 états, défauts 0 ; compteur moteur 1500/1500 transitions, défauts 0 ; export 1498 traces complètes, deux fragmentaires.
14 gestes résolution depuis source DRS réduite respectent tous l’ordre de pixels : notes/extract-attempt5.txt et CSV.
Frames4174→4177 : BASE1920x1080/FBO1728x972 → BASE1280x720/FBO1152x648 ; maintien 90 % réellement exécuté.
108 libellés présélectionnés concordent ; 640x480=307200px, 800x600=480000px ; acquis FBO extra/invalidate=0.
Fin normale RES-AUDIT restored width=800 height=600 drs=#f à 07:25:08.807 ; teardown efface 2 propriétés.
libgk SHA256 9e3f6ce42e4867a8f4b870f4616cf9cd1d0b3ef26365b9edb2037afe2b657479 ; MD5 local/appareil identiques.
## TENTÉ
Correction minimale : suppression reset100 au changement de base ; maintien du pourcentage, déverrouillage/EMA/délai conservés.
Les transitions immédiates réduites sont mesurées, mais DRS peut ensuite converger au même FBO pour deux bases : contrat strict incompatible avec optimum tenant même cible.
La matrice observe encore a7/r6=1555200px@100% et r7=865532px@70% ; observation courte, pas convergence.
Restart toujours incompatible avec contrôle PID0/PID1 de proof_run:1383,1419 ; aucune modification harnais ni seconde course.
Export : source absente pour (5,4,1)→aspect7 à 07:23:01.316 et FBO/frame absent pour (5,5,1)→aspect7 à 07:24:05.034 ; pas de données inventées.
## RESTE
Faire arbitrer par superviseur le conflit monotonie stricte/DRS adaptatif et obtenir protocole de restart autorisé ; ne pas relancer la même matrice sans nouveau périmètre.
La preuve reste rouge ; aucun zéro de remplacement ni owner-ok. Validateur non lancé par worker, laissé à orchestrateur.
Gain de cadence non mesuré ; libgk contient les changements AO intervenus depuis essai4, pas de comparaison causale entre essais.
Annulation précoce, effacement override actif, Jak2 et écran >8:3 non prouvés ; détails et cas de parseur dans FINDINGS.txt.
