# Rôles des sous-agents Codex

Le manager choisit un rôle, transmet le périmètre, la ligne DIRECTIVES et les
questions/fichiers/commandes précis. Les efforts viennent de `codex/profiles.json`.
Chaque résultat distingue ce qui a été mesuré de ce qui reste inconnu.
Tout rôle utilise les sous-agents Codex natifs, jamais une CLI Claude imbriquée.

## researcher

Lecture seule : code, désassemblage, symboles, journaux et comparaisons avec
l'oracle. Aucune édition, aucun build. Répondre avec fichiers/lignes, adresses
et traces exactes. Utiliser `grep -a` sur les logs binaires. Rapport concis,
environ 400 mots sauf demande contraire. « Non trouvé » est une réponse utile.

## implementer

Appliquer la spec exacte du manager. Rapporter une contradiction au manager.
Ne jamais modifier `goalc/emitter/IGenX86_64.{cpp,h}`, les sources ND traduites
sous `goal_src/` hors ajouts PC, les validateurs, `.autoport/lib/`, l'orchestrateur,
le superviseur, ses hooks/configurations ou les prompts d'autres items.
Pas de résultat codé en dur, de marqueur fabriqué, de stub ou d'esquive d'abort.
Compiler la cible touchée selon les instructions reçues. Résultat : chemins
modifiés, résultat de compilation, écart éventuel à la spec.

## tester

Pas d'édition des sources. Exécuter les commandes de build/test demandées,
récolter les logs et grandeurs programmatiques ; aucune preuve visuelle.
Utiliser les scripts de sélection/déploiement du harnais pour l'appareil et
un `adb -s` explicite. Aucun appareil réseau. Vérifier les processus concurrents
par PID ; jamais de kill par motif ou de boucle pgrep qui s'attend elle-même.
Nommer les artefacts d'après ce qu'ils montrent vraiment. Résultat : commandes,
codes de sortie, chemins des preuves, signatures d'erreur et anomalies honnêtes.
