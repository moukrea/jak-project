# Qualification — lecture statique essai35
DIRECTIVES v6fca51fe40
Aucun build ni run supplémentaire pour ce constat ; researcher Astra/high.
`game/graphics/refset.cpp:1716` crée les candidats en version2.
`:1729-1746` interdit le repli historique par suppression du marqueur.
`:1759` publie missing-state-and-baseline ; `:2005` exige version1 pour census_ok.
`:2062-2066` conserve254 pour version2 même après cinq rejeux exacts.
Aucun chemin d’adoption/qualification indépendante trouvé dans le code/outils actifs ciblés.
refset.sh ne propose que capture/replay ; refset_compare.py est un diagnostic hors ligne.
Une égalité locale après correction ne qualifie ni tous les états ni les trois modes.
Il manque une qualification indépendante vérifiable reliant baseline, état rejouable et candidat.
Ne pas convertir version2 en version1 pour contourner cette absence.
Plan actuel : 672 étapes,34 arrivées (refset.cpp:2363-2393 et :575-579).
Estimation statique : >=39min16 par tour par défaut ; cinq tours dépassent trois heures.
Cela dépasse les courses courtes sans campagne demandées ; aucun tel tour lancé.
Sunkenb reste manquant tant que sa couverture ciel n’est pas démontrée.
