HDR non validé : le débordement de pile est corrigé et les deux parcours de chargement passent sans crash, mais quatre défauts restent signalés.
DIRECTIVES v708c60642a
Le tampon de hachage de 64 Kio quitte la pile GOAL de 32 Kio ; le candidat d’internement reste local. Aucun effet supprimé, aucun réglage artistique ajouté.
Tests : 5 cas de hachage sur pile 32768, 2 cas noyau passent ; build Android incrémental : 3 actions en 21 s, repack en 38 s, lib b58734a565c15f3b installée sur Redmi.
Le producteur attend désormais les derniers compteurs avant arrêt ; scénario de coupure prématurée couvert, 256 tests harnais passent.
Menu normal : OFF à 15:42:53 puis ON à 15:43:40 sans override ; ombres ON cast_idx=886502/read_valid=1 ; persistance ON confirmée après redémarrage (notes/essai39/menu/verdict.md).
Portail : 4 captures sans crash ; ON 56.013/111.704 s et OFF 42.171/84.822 s après purge, âges 659/1319. Lot conservé diagnostic : ancien arrêt prématuré avait laissé compteur à 3.
Disque portail ON/OFF : luma 103.693/130.777, nearwhite 40/56 ; écart présent avant sprites, amplification bleue différente après (notes/essai39/portal/verdict.md).
Ciel neuf : 36 captures, 3 paires acceptées, 85 fichiers scellés, 0 erreur SHA ; nuages toujours signalés en échec (notes/essai39/sky/verdict.md).
Huit lignes de la dernière preuve officielle :
source=device
serial=eae4df44
sha=b58734a565c15f3b
crash=0
frames=1920
FEATURE lighting-hdr armed=1 hits=399863
hdr_batch_errors=0
hdr_tonemap_defects=4
Soleil : disque et deux rayons observés, blancs OFF=0 ; helper refuse de juger sans blancs OFF. Limite du jugement à arbitrer, pas une preuve de soleil défectueux.
Non prouvé : correction des 5 régressions, ombres OFF/persistance OFF, 21 niveaux × 8 h/ciels/intérieurs/vraie hutte ; campagne finale non exécutée, aucune validation owner.
À regarder : Options > Recharged, Lighting OFF/ON ; nuages, soleil couchant, éclairs éco bleue, sol devant Samos et portail après 10 s animées.
Réglages owner restaurés exactement SHA 78108670… ; propriétés debug vides ; dernier PID 30275 stable 20 s. APK livré sur Redmi, APK du publieur inchangé.
Validateur non exécuté par le worker : contrôle laissé à l’orchestrateur ; aucun owner-ok.
