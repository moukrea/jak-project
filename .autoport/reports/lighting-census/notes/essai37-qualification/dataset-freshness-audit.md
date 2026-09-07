# Fraîcheur de qualification agrégée
DIRECTIVES v6fca51fe40
Audit source, pas preuve jeu : evaluate ne recevait que current_bin et comparait data uniquement au sein de chaque paire.
Un replay propre sur datasetB pouvait demander adoption de racines datasetA via un manifeste ne contenant pas la racine rejouée.
Correction minimale : current_data requis, égalité de chaque capture au dataset courant rehashé par le producteur, donnée liée dans l'adoption.
Contrôle des assets : snapshots syntaxiques et empreintés ne suffisaient pas ; égalité exacte des ensembles de lignes asset capture/replay ajoutée, checkpoints exclus.
Mesure sur premiers cinq rejeux réels : 2261 lignes asset candidat et2380 baseline ; différence d'ensembles0/0 sur chacun des dix rejeux.
Ces changements ne modifient ni rendu, ni caméra, ni seuil, ni validateur. Les tests temporaires restent distincts de la preuve moteur.
