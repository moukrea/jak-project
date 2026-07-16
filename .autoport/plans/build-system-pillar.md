# PILIER : Compilation / Delivery / Feature-flags — plan (2026-07-17)
Owner pitch verbatim archivé dans prompts/phase-Grecharged-buildsys-*.md. Ceci est le plan pensé AVANT
l'édition du backlog, comme mandaté ("réfléchis très fort... avant même d'éditer le backlog").

## 0. Lecture du besoin (ce qui change vraiment)
1. UNE commande de build par cible, embarquant TOUTES les améliorations du fork, avec des FEATURE FLAGS
   de build (pas runtime) pour exclure les features half-baked des builds par défaut.
2. Un packaging à DEUX artefacts par cible et par jeu :
   - PACKAGE (APK / archive desktop) = moteur + TOUT ce qui est custom au port (CGO/DGO compilés, textes,
     modèles HD, PNGs recharged, custom shaders...). AUCUNE donnée dérivée non-modifiée du jeu source.
   - assets.zip = UNIQUEMENT la donnée dérivée non-altérée du jeu PS2 fourni (iso_data: STR/VAG/TXT*/VIS/
     SBK/MUS/VAGWAD..., fr3 repacks). *TXT: nos banques TXT reconstruites contiennent NOS ids custom ->
     elles sont "altérées" -> PACKAGE. Décision de tri = "un diff avec la sortie du pipeline vanilla
     OpenGOAL est-il vide ?" -> vide = assets.zip, non-vide = package.
   Conséquence Android : l'actuel jak1_cgo.zip in-APK est déjà conforme ; l'overlay enhanced/ et les
   PNGs recharged SORTENT de l'archive et entrent dans le package.
3. Premier démarrage : file browser NATIF par OS -> racine choisie, arborescence NORMALISÉE :
   <root>/jakN/{assets/, custom_assets/, saves/, settings.ini}. PAS de migration, pas de rétro-compat.
   settings.ini = nouveau format INI (bridge sérialisation <-> valeurs pc-settings GOAL existantes).
   custom_assets/ = override par nom de fichier des assets originaux (textures d'abord).
4. Cibles : linux-x86_64 (local, testé), android-arm64 (local, device-testé), windows-x86_64 (CI GitHub
   Actions — pas de machine locale ; smoke wine best-effort), macos-arm64 (SEULEMENT si le fork a gardé
   le support upstream ; CI, zéro effort local). ARM Linux/Windows : non-objectifs explicites.
5. Multi-game single build (collection) : DROPPÉ pour l'instant (owner). jak2/jak3 packagés par le même
   pipeline quand leurs assets sources sont présents au build.
6. Docs user-centric : README réécrit non-dev + docs/ par cible.

## 1. Architecture feature-flags (le point techniquement délicat)
Un flag doit exclure la feature du BINAIRE ET des MENUS. Or menus = code GOAL (goalc), renderer = C++.
=> UNE source de vérité : la CLI de build génère
   a) CMake defines (-DRECHARGED_HUD=0 ...) -> #ifdef côté C++/shaders ;
   b) un fichier GOAL GÉNÉRÉ goal_src/jak1/pc/recharged-flags.gc ((defconstant *flag-recharged-hud* #f)
      ...) consommé par les menus/pckernel -> les lignes de menu des features off NE SONT PAS COMPILÉES.
CONSÉQUENCE CLEF : le set de CGO dépend des flags -> le cache CGO et release_verify doivent être keyés
par le flag-set (hash des flags dans la version bundle). Danger identifié d'avance : builds mixtes
flag-set A (CGO) / flag-set B (libgk) = classe staleness connue -> le hash de flags entre dans
deploy_verify/release_verify.
Flags initiaux : --recharged-hud, --grass-overhang, --hd-models, --vulkan-support ; --yolo = tous.
Défaut = AUCUN (build propre). Les features validées (grass base, précompute, ombre, AO, foliage-wind
quand fini) sont TOUJOURS incluses, pas flaggées.
Menus cachés Android mais gardés desktop : c'est une dimension ORTHOGONALE aux flags (par-plateforme,
pas par-feature) -> constante GOAL *platform-android* générée par la même mécanique.

## 2. Découpage en phases (une tâche à la fois, chacune shippable)
P1 Grecharged-buildsys-flags : la CLI unifiée (./build.sh <cible> [--flags]) pour linux-x86_64 +
   android-arm64 en local, génération duale (CMake defines + recharged-flags.gc), 4 flags + --yolo,
   CGO-cache keyé par flag-set, vérif : build défaut SANS menus/code des 4 features, build --yolo AVEC ;
   menus desktop-only préservés sur linux. CI windows (+macos si support) = squelette de workflow posé
   mais la preuve Windows complète est P4.
P2 Grecharged-buildsys-packaging : tri package/assets.zip par la règle du diff-vanilla, producteurs
   réécrits (par jeu, par cible), release_verify/deploy_verify re-keyés (flags+contenu), sorties :
   app-jak1-<cible>.<ext> + jak1_assets.zip. Enhanced/recharged pngs déplacés dans le package.
P3 Grecharged-buildsys-firstboot : arborescence <root>/jakN/..., pickers NATIFS (Android SAF déjà là à
   adapter ; Linux xdg portal/zenity ; Windows IFileDialog en CI), settings.ini (bridge INI<->pc-settings,
   écrit par les menus, lu au boot), custom_assets override par nom (textures), MISE À JOUR DE TOUT LE
   HARNAIS device (les scripts warp/capture/settings pointent l'ancien OpenGOAL/jak_1 -> gros coût caché
   identifié), cutover Redmi (pull saves ADB -> wipe -> install clean -> replace saves dans le nouvel
   arbre). Cutover Honor = à la demande de l'owner, procédure fournie.
P4 Grecharged-buildsys-ci-docs : workflows CI windows(+macos) verts, README réécrit non-dev, docs/
   build-<cible>.md + guides d'install par OS (tonton Jeanot-proof), release jak-builds au nouveau format.

## 3. Impacts sur le backlog existant
- Grecharged-asset-prompt-migration : SUPPRIMÉE/SUPERSÉDÉE (owner: "ballec de la migration") -> P3.
- hd-models3, foliage-wind2, overhang (parqué) : passent DERRIÈRE le pilier ; --hd-models et
  --grass-overhang les couvrent en attendant (exclus des builds par défaut).
- Les phases jak2/jak3 futures héritent du pipeline (rien à re-spécifier).

## 4. Risques nommés d'avance
R1 flag-set mixe CGO/libgk (staleness) -> hash de flags dans les deux verify, refus de deploy si mismatch.
R2 goalc par flag-set = temps de build x combos -> cache par hash de flags, seuls défaut et --yolo sont
   des combos "supportés" officiellement.
R3 pickers natifs Linux headless (CI/harnais) -> fallback --game-root=<path> en argument CLI partout.
R4 settings.ini : divergence INI<->GOAL si on duplique la vérité -> le GOAL reste la vérité, l'INI n'est
   que la sérialisation (write-through, parse au boot).
R5 harnais device cassé par le nouveau layout -> P3 inclut la migration des scripts + un smoke harnais.
R6 Windows invérifiable localement -> CI + wine smoke, et l'owner teste le .zip Windows s'il veut.

## 5. Fact-checks (2026-07-17)
- macOS ARM: CONFIRMÉ — le fork garde CMake APPLE + workflow .github/workflows/macos-build-arm.yaml.
- Windows: workflows upstream présents (voir .github/workflows/) — la base CI existe, P4 les adapte à
  nos cibles/flags/packaging.
