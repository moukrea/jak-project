# jak-project — portage Android d'OpenGOAL

Fork d'OpenGOAL (décompilation de *Jak and Daxter*, C++ + langage GOAL) porté sur Android,
plus une couche d'améliorations visuelles : modèles HD, herbe, éclairage, polices, HUD.
Branche de travail : `physics-keira-clean`.

**Le `CLAUDE.md` de `~/code/` ne s'applique PAS ici.** Il décrit snag / cairn / jaunt
(Rust, `cargo build`, `task-list.json`). Rien de tout cela n'existe dans ce dépôt.

## Le harnais

Tout le pilotage automatisé vit dans `.autoport/` : orchestrateur, validateurs, preuves,
rapports. Il est en cours de remise d'équerre — lis
`.autoport/plans/2026-09-03-remise-d-equerre.md` avant d'y toucher.

* Les ordres permanents tiennent dans `.autoport/DIRECTIVES.md` (3 Ko). Le périmètre d'une
  tâche est dans son prompt, jamais dans DIRECTIVES.
* Le journal de la phase physique d'août est archivé dans
  `.autoport/archive/journal-keira-physique-2026-08.md`. C'est un carnet de laboratoire,
  pas un contrat : n'en cite aucune ligne comme un ordre en vigueur.

## Appareils

* **Redmi `eae4df44`** — le seul qu'on touche. Tout `adb` porte `-s eae4df44`.
* **Honor de l'owner** — invisible, il prend les builds publiés. Rien ne s'en déduit.
* **La SHIELD (192.168.1.32) est interdite.** Aucune commande vers elle.

## Preuve

Aucune preuve visuelle n'est acceptée : ni capture, ni vidéo, ni « ça a l'air bon ». Une
porte lit une grandeur produite par le code — compteur, identifiant, empreinte, mesure.
C'est un ordre de l'owner, pas une préférence.

## Build — les pièges qui coûtent des heures

* **Ne reconfigure jamais avec `cmake -B`** sur un arbre déjà configuré : ça repart de zéro
  et écrase les options. Utilise le dossier de build existant.
* **`cmake --build build --target gk -j`** (cible unique) suffit pour le moteur x86 ;
  `build-android` pour l'arm64. L'arbre complet est long et inutile la plupart du temps.
* **Rebâtis `goalc` après tout changement de header sérialisé.** Un `--target gk` relie
  `libcommon` avec le nouveau champ et laisse `libcompiler` sur l'ancien : `goalc` part en
  SIGSEGV dans `serialize`, et le symptôme ne ressemble pas à sa cause.
* **`(build-game)` ne livre rien au `gk` qui tourne.** Il écrit dans `out/jak1/obj` ; le jeu
  boote sur les CGO. Bâtis `out/jak1/iso/GAME.CGO` **et** `out/jak1/iso/ENGINE.CGO`, puis
  vérifie avec un `grep -a` d'un marqueur neuf dans chacun.
* **Un fichier GOAL neuf doit être listé dans `goal_src/jak1/dgos/game.gd` et `engine.gd`**,
  sinon `gk` saute dans le vide au chargement avec une pile inexploitable.
* **Le build arm64 livré est `build-android/`.** `build-arm64/` a toutes les options à OFF
  et n'a jamais produit de binaire : un échec là-bas est un faux rouge.
* **Un `-Wreturn-type` ignoré est un plantage arm64 garanti.** x86/GCC retombe par hasard
  sur une valeur de retour, clang/arm64 non.

## Conventions

* Commits : `[autoport/<id-de-tâche>] <ce que ça change>`.
* Le C++ du moteur vit sous `game/`, `goalc/`, `common/` ; notre code GOAL ajouté vit sous
  `goal_src/jak1/pc/`. Les sources traduites de Naughty Dog ne se réécrivent pas.
* Les assets « rechargés » (les nôtres, téléchargés automatiquement) et ceux extraits des
  ISO (Naughty Dog, produits par l'utilisateur) sont deux familles distinctes. Les
  confondre est une faute, pas un détail.
