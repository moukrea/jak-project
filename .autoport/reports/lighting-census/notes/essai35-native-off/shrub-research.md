# Correction native OFF — recherche statique Astra/high
DIRECTIVES v6fca51fe40
Baseline : /home/emeric/code/jak-lighting-baseline, commit a9ea15a690.
Avant patch Shrub.cpp:351-367 ajoutait master_on à la condition historique baseline:321-323.
Cette condition empêchait intégration CPU (:586-587) et uniforme natif (:824,:853).
Le corps de update_native_wind est identique à la baseline : aucun changement nécessaire.
Le shader conserve le cisaillement X/Z existant (shrub.vert:80-83).
La brise enrichie reste séparée : foliage_wind.cpp:519 pousse amplitude0 si enabled faux.
Le contact dépend de enabled et tree.contact_active ; la ligne zéro LUT reste native.
Le seul consommateur du compteur supprimé était hdr.cpp:729 ; déclaration dans Shrub.h.
Retrait du diagnostic caduc plutôt qu’une publication constante zéro.
Aucun changement de comportement statique pour les arbres initialisés maître ON.
OFF→ON conserve désormais l’historique du ressort comme la baseline ; non mesuré ici.
AUTOPORT_ORIGIN_ABLATE garde son désarmement natif explicite ; non modifié.
Les lignes ci-dessus sont de la lecture de code, pas une preuve d’exécution.
