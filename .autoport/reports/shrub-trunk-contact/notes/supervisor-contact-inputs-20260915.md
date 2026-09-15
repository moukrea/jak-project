# Contrôle local après l'alerte de reprise du 15 septembre

Aucune course supplémentaire, aucun contact appareil, aucun code jeu modifié.
Handoff10 et validator010 relus : le validateur rejette correctement la preuve
historique de l'essai3. La référence réellement produite à l'essai10 reste dans
notes/attempt-10-reference-result/, avec zéro capture et470 erreurs.

Précision nouvelle sur la couverture : `actors=0` dans Shrub.cpp affiche seulement
`grass_occ::g_tramp_published.size()`. Dans le témoin, GrassRenderer.cpp:687-713
compte et transmet Jak séparément (contact_jak, contact_ledge, contact_trail).
La preuve archivée porte wind_contact_jak_samples=20616 et
wind_contact_tie_jak_samples=61848, avec binding_failures=0.
Cela établit la présence de sources Jak transmises, PAS une intersection avec
les sommets du mini-palmier. Ne pas diagnostiquer un parcours sans Jak depuis actors=0.

Le clip binaire a été décodé sans modification : version2, enregistrements6 octets,
7800 entrées ; neutre0..119, mouvement120..249, neutre250..7799.
L'ancrage du rejeu est bien consigné au tick logique603. La trace archivée contient
6713 lignes CAM, aucune ligne d'état du personnage : elle ne permet pas à elle
seule de prouver le contact géométrique. Conserver le contrôle de population et
d'intersection dans la capture réparée avant les comparaisons ON/OFF.

L'extension +1 reste proposée, pas autorisée par la notification automatique.
Le budget existant reste1/3 consommé. Les réparations sont prêtes ; ne refaire
ni l'audit ni la course échouée à l'identique.
