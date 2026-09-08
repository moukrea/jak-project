HDR non validé : le dépassement alpha mesuré est corrigé sur Redmi, mais la preuve conserve quatre défauts.
DIRECTIVES v708c60642a
Quatre branches de mélange HDR séparent l’alpha des couleurs ; Generic limite ce changement au monde et conserve le HUD. Courbe et exposition inchangées.
Huit cas GPU hôte passent, dont le HUD avec HDR actif. Build final incrémental : 17,7 s ; repack isolé : 69,9 s ; identité build/APK/Redmi concordante.
Lib 32d5e7e2e9f427d8 et APK 883014b77b6fe30e… installés ; packs, CGO et APK du publieur inchangés (notes/essai40/build-final/device-identity.json).
Le premier lot a été interrompu avant capture pour corriger le risque HUD trouvé en revue ; ses traces restent diagnostiques, sans réagrégation.
Lot final : 398 s, 4 captures, 21 fichiers scellés, aucune divergence SHA. Attentes ON : 54,494/109,762 s ; OFF : 42,632/84,271 s après purge ; âges 659/1319.
Disque portail : alpha maximum ON de 2 à 1 ; occurrences alpha>1 sur deux samples de 87 à 0 avant et après sprites ; OFF reste à 1/0 (portal-final/alpha-before-after.json).
Le rendu reste insuffisant : disque ON/OFF, luma 102,022/127,016 et quasi-blancs 41,5/48,5. Déficit rouge/vert avant sprites et surplus bleu après sprites demeurent.
Huit lignes de la preuve officielle produite par proof_run.sh :
source=device
serial=eae4df44
sha=32d5e7e2e9f427d8
crash=0
frames=4560
FEATURE lighting-hdr armed=1 hits=1029885
hdr_batch_errors=0
hdr_tonemap_defects=4
Les observations du ciel39 restent diagnostiques : perte de blancs due en partie à la courbe ; disque solaire et deux rayons présents, blancs OFF=0 ne démontrant pas un défaut.
Le jugement solaire refuse toujours blancs OFF=0 ; nuages/portail restent partiels, sol sans ROI, HUT_VIEWS vide. Aucun critère ni validateur assoupli.
non prouvé : correction des cinq cas, ombres OFF/persistance OFF, image OFF/HUD entière, couverture 21 niveaux × 8 h/ciels/intérieurs/vraie hutte ; 343 éléments manquants dans ce lot.
À regarder : Options > Recharged, Lighting OFF/ON ; nuages, soleil couchant, éclairs éco bleue, sol devant Samos et portail après dix secondes animées.
Réglages owner restaurés exactement (SHA 78108670…) ; propriétés debug vides ; PID 3726 identique aux deux lectures espacées de 12 s (notes/essai40/portal-final/restoration.json).
Validateur laissé à l’orchestrateur ; aucun owner-ok. Les cinq cas et la couverture finale restent obligatoires.
