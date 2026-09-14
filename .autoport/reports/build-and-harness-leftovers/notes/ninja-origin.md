DIRECTIVES vbbd78e3a00

Le producteur initial de la corruption reste non identifié.
Capture brute avant réparation : lib/census/capture-build-and-harness-leftovers/ninja_deps.before.gz.
SHA256 décompressé : 748e87a8491fe088085f96aacc0e10726dc3740b855e3cb33aec42226a5d889d.
Le même lecteur forensique v4 trouve un enregistrement de chemin complet à l’offset 2831912,
fin 2831988 : ID stocké 5487, ID attendu 5490, chemin déjà inscrit sous ID5487.
Le chemin est game/CMakeFiles/runtime.dir/graphics/opengl_renderer/frame_ubo.cpp.o.
Le journal actuel est lu avec le même détecteur ; son empreinte et son résultat sont republiés par le census.

Source primaire : https://raw.githubusercontent.com/ninja-build/ninja/v1.13.1/src/deps_log.cc
Lignes 239–247 : le chargeur vérifie ID séquentiel et absence de chemin déjà enregistré.
Son commentaire cite les Ninja concurrents comme cause de ces incohérences.
Ligne192 puis254–264 : offset incrémenté avant validation ; recovery tronque après le record complet invalide.
Ce mécanisme explique la taille conservée et les nouveaux append illisibles des mesures du12/09,
conservées dans lib/census/capture-build-tree-reinvalidates-itself/avant-journal-deps.txt.

Écarté comme explication suffisante : une simple queue tronquée ; le record fautif est complet et dupliqué.
Fortement compatible : deux écrivains Ninja dont un a un compteur d’IDs périmé.
Restent compatibles : copie/restauration d’un journal, autre écriture externe, incidents I/O associés.
Une interruption, ENOSPC ou un défaut matériel ne sont pas absolument exclus faute de chronologie initiale.
La présence de disk_reclaim.sh ne constitue pas une preuve d’ENOSPC pendant cet incident.
La capture peut être postérieure à plusieurs reprises ; aucun PID initial n’est conservé.
Aucun script vivant retrouvé ne copie directement .ninja_deps ; le selftest modifie son propre arbre jetable.
Les commentaires de build_x86 distinguent désormais mécanisme de reprise et auteur inconnu.

Le terme10 vaut0 si la corruption est retrouvée dans la capture, absente du journal courant,
et si l’investigation est publiée sous cause_non_etablie conformément à l’exception du contrat.
Ce zéro ne prouve ni l’identité de l’écrivain, ni l’impossibilité de récidive.
