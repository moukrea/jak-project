# Essai37 — instrumentation des crashes de chargement

DIRECTIVES v708c60642a

Instrumentation diagnostique seulement; aucune cause établie et aucun correctif comportemental.

- `kscheme.cpp` fournit le gate partagé, lu une fois : `OG_HDR_LOAD_DIAG=1` OU propriété Android `debug.opengoal.hdr.load_diag=1`. Ligne unique `HDR-LOAD-DIAG armed` puis flush stderr. Armer avant lancement du processus.
- Chaque intern/find possède un contexte local restauré par pointeur TLS : id monotone atomique, TID noyau Linux/Android (identifiant de thread haché ailleurs), profondeur, hash, candidat, deux intervalles avec compteurs de probes et compteur de probes fixes. Aucun ring ni allocation dédiée.
- Les trois sites d’écriture du scratch global sont suivis par atomiques relaxés (id/TID/slot; slot nul signifie reset). Le scratch reste non atomique et reste la source de l’adresse réellement consommée.
- Un nouveau symbole avec adresse consommée nulle ou différente du candidat local produit `HDR-LOAD lookup reason=new-symbol-slot`, avant l’écriture du type. Les deux débordements produisent la même famille de ligne avec `reason=double-overflow` au point de production. Chaque ligne donne bornes et NumSymbols puis flush stderr.
- Le snapshot des champs écrivain est best effort : ids avant/après peuvent révéler une modification concurrente, mais des ids égaux ne démontrent pas un snapshot cohérent ni l’absence de concurrence. Les stores atomiques diagnostiques ne sérialisent pas la table et peuvent eux-mêmes être entrelacés avec les écritures originales.
- `klink.cpp` trace uniquement `*default-dead-pool*`, `*nk-dead-pool*`, `lurkerworm-strike`, `spawn-bird`, pour chaque relocation de `symlink_v3`, donc chaque instruction ADRP/ADD enregistrée dans les relocations. Sont lus nom demandé, slot/valeur/hash/nom réel, objet/base data, offset, mots avant/après, cible hôte et deux représentations GOAL attendues (adresse et différence s7).
- Les deux adresses de pools sont retenues aux symlinks. Après chaque top-level v3 effectivement exécuté, les slots mémorisés sont relus directement. Journal forcé pour gkernel/seagull; ailleurs seulement changement slot/valeur/hash/adresse de chaîne par rapport au checkpoint précédent. Les changements transitoires entre checkpoints restent invisibles.
- Les lectures diagnostiques vérifient plage table et limites mémoire avant d’accéder aux cellules/infos/chaînes; nom limité à 255 octets terminés. `valid` désigne l’accès cellule/info; `actual=<invalid>` peut signaler une chaîne invalide indépendamment. Le checkpoint ne réinterne aucun symbole. Les champs relocation/before/after des checkpoints valent zéro et ne décrivent pas une relocation.

Vérification statique : `git diff --check -- game/kernel/jak1/kscheme.cpp game/kernel/jak1/klink.cpp` termine avec code 0; clang-format appliqué aux zones modifiées. Relecture des formats et des signatures; aucune compilation exécutée, conformément à l’ordre du manager. Le diff reste limité aux deux sources autorisées et à cette note; les autres changements du workspace ne sont pas ceux de cet agent.

Non prouvé : compilation x86/arm64, armement à l’exécution, reproduction des deux crashes, cause du slot nul, identité/valeur effective des pools après gkernel et après seagull, absence de concurrence. Aucun proof.txt ni validateur modifié.
