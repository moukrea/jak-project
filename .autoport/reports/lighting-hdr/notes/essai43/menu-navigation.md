DIRECTIVES v8aed688f73

Navigation préparée en lecture seule ; aucun appareil interrogé, aucune mémoire écrite, aucun menu ouvert, aucun build. Sources : variante livrée `#unless FLAG_MENU_OVERHAUL`, progress-pc.gc:6441–12693. Les dumps cités sont ceux du PID12983 de l'essai42, pas l'état actuel.

**Correction de mapping : Recharged = 67, Grass = 68.** L'énumération PC de `goal_src/jak1/engine/ui/progress/progress-h.gc:60–143` donne title27, settings-title28, graphic-settings5, recharged-settings67, grass-settings68. Le param3 effectivement lu reste l'autorité pour le binaire courant ; ne pas entrer aveuglément dans l'écran68 proposé initialement.

| Page | Tableau livré | Sélection à reconnaître dans le tableau runtime |
| --- | --- | --- |
| title27 | `*title-pc*`, progress-pc.gc:8877 ; remap10316 | `option-type=6`, `name=0x150` (Options), `param3=28` ; index statique2, pas3 |
| settings-title28 | `*options*`, progress-static.gc:79 ; remap10317 | `option-type=6`, `name=0x128` (Graphic Options), `param3=5` ; index statique1 |
| graphic-settings5 | `*graphic-options-pc-android*`, progress-pc.gc:7221 ; remap10291 | `option-type=6`, `param3=67`, name-override égal au contenu de `*recharged-settings-label*` ; index9 complet,8 après masquage Min Target FPS |
| recharged-settings67 | `*recharged-options-pc*`, remap10338 | `option-type=2` (on-off), name-override égal à `*recharged-lighting-label*`, value-to-modify vers le symbole `recharged-lighting?` ; aucun index constant |

Le compactage Graphics est réel : `graphic-options-set-mtf-visible!` (8348–8368) retire l'objet physique4 Min Target FPS, décale tous les pointeurs suivants et décrémente length lorsque Dynamic Render Scale est OFF. Ce n'est pas FPS Counter qui disparaît. Recharged peut aussi se compacter selon les assets HD ; l'initialisation recherche fw-idx, puis câble Lighting à fw-idx+4 (10514–10539). Lighting porte initialement name=vsync/0x103b : rechercher son `name` seul est ambigu. Son `on-change` persiste immédiatement le réglage (7515–7523).

**Pourquoi les anciens taps ont dévié.** `menu-off/start3.json` publie title27 et six lignes : index2 cy=.430200, index3 cy=.549700. `proof-engine.log:15819` mesure le premier tap fy=.5500, best=3 : Secrets51 est donc attendu (`options.json`), sans hypothèse de calibration. Ensuite fy=.1906 sur les trois lignes Secrets donne distance .1821, au-delà de 3×half_h=.17925 (`:17576`) : retour titre. Le tap suivant fy=.1906 sélectionne index0/New Game (`:19152`), donc save-game-title18. `options3.json` mélange deux boutons et quatre slots mémoire ; son rang de ligne dans la liste ne représente plus abs-index. Les taps suivants conduisent à11 ; `observations.json` et verdict.md confirment 27→51→27→18→11. Aucun Options/Graphics/Recharged atteint. L'origine du crash ultérieur ne se déduit pas de cette erreur de navigation.

**Décodage mémoire proposé avec les instruments existants.** Réutiliser seulement le lecteur `/proc/<PID>/mem` de `essai42/menu-off/read-menu.py`, en vérifiant le PID vivant et la base EE du processus courant. Ancienne base=0x7f00000000, s7/#f=0x14fd24. Tous les offsets ci-dessous sont relatifs à la valeur du pointeur GOAL, pas au début physique de l'objet (les basic sont tagués +4). Lectures little-endian ; aucun appel de fonction GOAL.

| Objet/champ | Lecture depuis son pointeur GOAL |
| --- | --- |
| boxed-array length / allocated-length / content-type | +0 i32 / +4 i32 / +8 u32 |
| boxed-array élément i (pointeur, non objet inline) | +12+4*i u32 |
| game-option option-type / name / scale | +4 u64 / +12 u32 / +16 u32 |
| game-option param1 / param2 / param3 | +20 f32 / +24 f32 / +28 i32 |
| game-option value-to-modify / option-disabled-func | +32 u32 / +36 u32 |
| game-option name-override / on-change / on-confirm | +40 u32 / +44 u32 / +48 u32 |
| string capacité / octets terminés NUL | +0 i32 / +4, lecture bornée à capacité |
| menu-touch n-rows / screen | +0 i32 / +4 i64 |
| menu-touch ligne physique j | +12+32*j ; abs-index i16+0, oy f32+4, cx+8, cy+12, half-h+16 |
| progress display-state / next-display-state / option-index | +124 i64 / +132 i64 / +140 i32 après déréférencement de `*progress-process*` |

Dérivation : game-option progress-h.gc:255–274, enum option-type uint64:145 et text-id uint32 text-h.gc:12 ; les offset-assert historiques préfixes confirment les positions physiques8/16/32/36 dans all-types.gc:15898–15908. Les champs PC ajoutés suivent value-to-modify sans déplacer ce préfixe. Arrays/strings : common/type_system/TypeSystem.cpp:1212–1214,1244–1252. Menu-touch : variante livrée progress-pc.gc:6559–6584 ; stride32 et données concordent avec les dumps. Progress : champs hérités inchangés, progress-h.gc:276 et all-types.gc:15911–15918. Ces derniers offsets sont dérivés des types, pas relus sur un nouvel appareil.

Résoudre `*options-remap*` par le même scanner de symboles que read-menu.py ; ne pas inventer son adresse, absente des anciens dumps. Attention : progress-static.gc:263 alloue ce tableau avec **length=0 et allocated-length=72** ; indexer ses pages selon allocated-length, puis contrôler length du tableau d'options obtenu. Résoudre aussi `*recharged-lighting-label*` et `*recharged-settings-label*`, puis comparer les pointeurs/contenus aux name-override. Pour chaque symbole, vérifier hash CRC et chaîne, même avec le cache guards.json historique ; la sym-info vaut slot+131068 (common/goal_constants.h:24–25), chaîne à string+4. Le cache n'est pas une observation actuelle.

Adresses anciennes, uniquement repères du dump start3.json : slot `*menu-touch*` 0x14958c→0x2067684 ; `*progress-process*` 0x1434d4→0x1dcd04 (ppointer à déréférencer) ; `*pc-settings*` 0x14814c→0x1d5f5c4 ; `*progress-state*` 0x14908c→0x202d434. Ce dernier est un progress-global-state, pas le progress courant : son champ starting-state ne remplace pas display-state. Relire ces valeurs après toute transition/relocalisation.

Pour une navigation ultérieure autorisée, relever ensemble page, tableau, identité de l'option et ligne tactile portant son **abs-index**, puis attendre deux relevés stables avant action. Joindre les lignes tactiles à options[abs-index], jamais au rang j ; si la cible est hors page, lire le nouvel état après chaque défilement. La coordonnée cy publiée est normalisée ; convertir avec la surface tactile courante, sans réutiliser des pixels d'un autre écran. `Gtm-tap` mesure le résultat du hit-test (progress-pc.gc:6736). Une lecture non atomique peut chevaucher un redraw : rejeter les snapshots incohérents, sans arrêter/écrire le processus.

Lighting doit être contrôlé par le u32 pointé par value-to-modify, avec #f=s7 et #t résolu comme symbole ; ni zéro seul ni le nom de la page ne prouvent OFF. Le tactile on-off retourne la valeur actuelle indépendamment de la moitié touchée (6669–6681). Lire les pointeurs de fonctions désactivantes ne permet pas de les évaluer : ne jamais les exécuter depuis le lecteur. Cette note prépare l'identification ; elle ne prouve ni navigation, ni persistanceOFF, ni suppression des ombres.
