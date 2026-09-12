# Le reliquat du chantier de la construction : neuf petites choses, aucune urgente — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

NEUF SIGNALEMENTS DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt), reunis ici parce qu'aucun ne merite son propre chantier. CE CHANTIER N'OUVRE PAS DE SUCCESSEUR : ses propres signalements s'ajoutent a lui.
1. `gate_verdict.py:118` : `code_scope` tranche en premier et la prose n'est JAMAIS relue. Un champ qui CONTREDIT l'`out_of_scope` passe sans un mot. Publier le compte de contradictions.
2. `orchestrator.py:1682` : le message de refus dit encore « mets `no_code: true` », alors que le champ qui fait foi depuis le 12/09 est `code_scope`. Le message envoie au mauvais endroit.
3. `third-party/discord-rpc/src/CMakeLists.txt` : la cible `clangformat` n'a AUCUNE sortie, donc elle se rejoue a chaque construction.
4. `.gitignore:181` : le motif `build-*/` n'est pas ancre et avale tout dossier commencant par `build-` a n'importe quelle profondeur, y compris une capture d'essai.
5. `build/game/CMakeFiles/runtime.dir` : 374 objets sur le disque pour 358 enregistrements et 338 aretes. Une quinzaine d'orphelins que rien ne nettoie.
6. `lib/build_x86.sh` : la constante posee contient le numero de version de SDL EN DUR, et elle ne vit que dans le cache de l'arbre — un arbre reconfigure a neuf la perd.
7. Sept scripts construisent `build-android`/`build-arm64` chacun a leur facon (`d1_build.sh`, `d3_build.sh`, `c2_run.sh`, `c3_run.sh`, `c4_run.sh`, `qemu_repro.sh`, `lib/emitter_stress.sh`) : autant de chemins qui peuvent diverger.
8. `PITFALLS.md:12` promet que `preflight.py` verifie le verrou a chaque tentative ; a verifier et corriger l'un ou l'autre.
9. `census/build-tree-reinvalidates-itself.sh` compare son gain a un journal FIGE dans la capture versionnee : la reference vieillira.
10. `build/.ninja_deps` : la corruption est reparee et detectee a chaque construction, mais CE QUI L'A ECRITE n'est pas etabli. Tant qu'on ne le sait pas, elle peut revenir.

## Livrable — le contrat, en entier

`build_leftovers_defects` = 0, somme de DIX termes publies SEPAREMENT, un par point.
Pour chacun : le defaut est RETROUVE sur le commit d'avant par le meme detecteur, puis absent apres. Un point qui ne peut pas etre retrouve avant n'est pas corrige, il est declare NON REPRODUIT et son terme le dit.
Le point 10 est le seul qui peut se conclure par « cause non etablie » : publier alors ce qui a ete ecarte et ce qui reste possible, pas un silence.

## Hors perimetre

Ne touche a aucun code du jeu. N'ouvre AUCUN item successeur : ses propres signalements s'ajoutent a celui-ci. Priorite 37 : tout le reste passe avant.

## Ou l'owner regardera

Invisible. Petit outillage et petites incoherences.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

