# Jak 1 — Arborescence des menus — DÉFAUT LIVRÉ (FLAG_MENU_OVERHAUL OFF)

> Gmenu-flag-off (owner 2026-08-04) : la refonte Grecharged-menu-overhaul est sortie des builds
> livrés. `goal_src/jak1/pc/progress-pc.gc` porte DEUX corps complets sélectionnés à la compile :
> `#unless FLAG_MENU_OVERHAUL` = **l'ANCIEN menu fonctionnel** (état pré-refonte 1000f7ab03,
> + 2 fixes de longueur, voir §fix) — C'EST CE QUI EST LIVRÉ ; `#when FLAG_MENU_OVERHAUL` = la
> refonte gelée (annexe en bas de ce fichier). Flag généré par build.sh (`--menu-overhaul`,
> défaut OFF, univers ogflags 7 flags / 128 sous-ensembles).
>
> Légende : `[R]` = ajout Recharged · `{FLAG_X}` = ligne présente uniquement si le flag de build
> est ON · `(grisé si …)` = option-disabled-func · valeurs = champ *pc-settings* piloté.

## Entrées

```
ÉCRAN-TITRE (*title-pc*) : Nouvelle partie / Charger / Options / Secrets / Quitter
PAUSE (*main-options-pc* 8 lignes / *main-options-secrets* 9) : Game/Graphics/Sound Options,
  Charger/Sauvegarder, auto-save, (Secrets), Quitter — structure PS2 d'origine + lignes PC.
```

## GRAPHICS (desktop `*graphic-options-pc*` 15 lignes / Android `*graphic-options-pc-android*` 12)

Aspect, Résolution (desktop), Dynamic Render Scale (`dynamic-render-scale?`), Render Scale,
Min Target FPS (`dyn-target-fps`), FPS Counter, VSync, MSAA, [desktop : Display Mode, Display,
Frame Rate], **RECHARGED SETTINGS** (sous-menu), Advanced, Vulkan `{FLAG_VULKAN_SUPPORT}`, Back.

## RECHARGED SETTINGS (`*recharged-options-pc`* — 28 lignes livrées avec hd-models+pbr, HUD off)

| idx | ligne | pilote |
|---|---|---|
| 0 | RECHARGED MASTER (on-off) | `recharged-master?` |
| 1 | GRASS SETTINGS (sous-menu) | → `*grass-options-pc*` |
| 2 | LOAD CUSTOM ASSETS | `load-custom-assets?` |
| 3 | RECHARGED TEXTURES | `recharged-textures?` |
| 4 | PBR MATERIALS `{FLAG_PBR}` | `pbr-materials?` |
| 5 | ENHANCED MODELS `{FLAG_HD_MODELS}` (collapse si FR3 HD absents) | `recharged-enhanced-models?` |
| **6** | **JAK LOOK (carousell ORIGINAL / HD / JAK II / JAK 3 / JAK 3 MASKED)** `{FLAG_HD_MODELS}` (grisé si master ou ENHANCED MODELS off) | **`hd-look-jak`** via int-backup (write-back respond-common) |
| **7** | **DAXTER LOOK (carousell ORIGINAL / HD / PANTS)** `{FLAG_HD_MODELS}` (même grisage) | **`hd-look-daxter`** via int-backup |
| **8** | **KEIRA LOOK (carousell ORIGINAL / HD / JAK 3)** `{FLAG_HD_MODELS}` (même grisage) | **`hd-look-keira`** via int-backup |
| **9** | **SAMOS LOOK (carousell ORIGINAL / HD / YOUNG)** `{FLAG_HD_MODELS}` (même grisage) | **`hd-look-samos`** via int-backup |
| 10 | FOLIAGE WIND | `recharged-foliage-wind?` |
| 11-13 | AMBIENT OCCLUSION / AO QUALITY / AO STRENGTH (carousells) | `ambient-occlusion`/`ao-quality`/`ao-strength` via int-backup |
| 14 | REALTIME LIGHTING `{FLAG_PBR}` | `realtime-lighting?` |
| 15-16 | FOLLOW PROBE / AMBIENT MODEL (carousells) `{FLAG_PBR}` | int-backup → champs rt |
| 17-19 | AMBIENT STRENGTH / CONTRAST / SHADOW DISTANCE (sliders) `{FLAG_PBR}` | `realtime-ambient-strength`/`-contrast`/`realtime-shadow-dist` |
| 20 | SHADOW QUALITY (carousell) `{FLAG_PBR}` | int-backup → `shadow-quality` |
| 21-22 | TEXTURE RELIEF / SPECULAR INTENSITY (sliders) `{FLAG_PBR}` | `pbr-texture-relief`/`pbr-specular-intensity` |
| **23** | **DISPLACEMENT (carousell Off/Parallax/Tessellation)** `{FLAG_PBR}` (grisé si master ou materials off) | **`pbr-displacement`** via int-backup (write-back respond-common) |
| 24 | PBR TEST PRESET (carousell, jamais grisé) `{FLAG_PBR}` | applique le preset complet |
| 25 | PBR ISOLATE (carousell) `{FLAG_PBR}` | `pbr-isolate` |
| **26** | **PHYSICS (on-off, défaut ON)** `{FLAG_PHYSICS}` (grisé si master off uniquement) | **`physics?`** |
| **27** | **PHYSICS DETAIL (carousell LIGHT / FULL / MAXIMUM, défaut FULL)** `{FLAG_PHYSICS}` (grisé si master ou PHYSICS off) | **`physics-quality`** via int-backup (write-back respond-common) |
| 28 | MESH BROWSER (bouton) | ouvre l'overlay mesh-browser |
| 29 | Back | — |

### Grecharged-hd-models5 — LOOK par personnage (idx 6-9)

Quatre carousells `int32` persistés dans `settings.ini` : `hd-look-jak` (0 ORIGINAL / 1 HD /
2 JAK II / 3 JAK 3 / 4 JAK 3 MASKED), `hd-look-daxter` (0 ORIGINAL / 1 HD / 2 PANTS), `hd-look-keira`
(0 ORIGINAL / 1 HD / 2 JAK 3), `hd-look-samos` (0 ORIGINAL / 1 HD / 2 YOUNG). **Défaut = 1 (HD)**
pour les quatre = le comportement d'ENHANCED MODELS avant ces lignes.

Le bloc HD compte désormais **5 lignes** gatées `FLAG_HD_MODELS` : chaque terme HD de
l'arithmétique longueur-exacte du menu ancien passe de `FLAG_HD_MODELS_N` à
`(* 5 FLAG_HD_MODELS_N)` (longueur pleine `(+ 10 hud-N pbr-N (* 5 hd-N) (* 12 pbr-N))` = 28,
`fw-idx` = `(+ 4 hud-N pbr-N (* 5 hd-N))` = 10), et le collapse "FR3 HD absents" retire
**les 5 lignes d'un bloc** (`length -= 5`, décalage `+5`).

Les 7 libellés d'options (ORIGINAL / HD / JAK II / JAK 3 / PANTS / YOUNG / JAK 3 MASKED — cycle-4 item 3, tag id #x17b6 -> jakm-hd entrée 9) sont des **globales
runtime** (`*hd-look-*-label*`) résolues par `carousell-option-string` depuis les tags réservés
`#x17b0..#x17b5` — même mécanisme anti-banque-de-texte-périmée que PBR ISOLATE, donc aucun
"Unknown ID" possible sur Android. Libellés de lignes via `name-override` (`JAK LOOK`,
`DAXTER LOOK`, `KEIRA LOOK`, `SAMOS LOOK`), comme `*enhanced-models-label*`. Anglais uniquement.

### Grecharged-secondary-motion — PHYSICS + PHYSICS DETAIL (idx 26-27)

Deux lignes présentes **uniquement dans les builds `--physics`** (`FLAG_PHYSICS`) ; absentes du CGO
sinon (`flag-row`, filtrage à l'expansion GOOS). Elles sont **ajoutées EN QUEUE de tableau**,
juste avant MESH BROWSER + Back : aucun index existant ne bouge (classe de bug index-shift de
Gmenu-flag-off). Le seul impact arithmétique = `+ (* 2 FLAG_PHYSICS_N)` sur les constantes de
**longueur statique pleine** (garde `fw-idx` et garde de collapse HD) — exactement le traitement
déjà appliqué à la ligne queue MESH BROWSER. Le câblage (`value-to-modify` / `name-override`) est
adressé **relativement à la longueur vivante** (`length-3` = PHYSICS, `length-2` = PHYSICS DETAIL),
donc il reste juste avant comme après le collapse HD (qui décale la queue et baisse `length` du
même nombre) et il est idempotent sur ré-init.

- **PHYSICS** (`physics?`, symbole) : secondary motion (chaînes) — cheveux / tissu / sangles.
  **Défaut ON** (la feature est opt-in au BUILD). `option-disabled-func` = master seul : **pas**
  de dépendance à ENHANCED MODELS (la physique pilotera aussi des NPC stock). `on-change` persiste
  et pousse `pc-set-physics!` ; le pont per-frame `update-to-os` la pousse également.
- **PHYSICS DETAIL** (`physics-quality`, int 0/1/2 = LIGHT / FULL / MAXIMUM). **Défaut 1 (FULL)**.
  Carousell calqué sur DISPLACEMENT : pas d'`on-change`, backup/write-back dans `respond-common`
  via `*progress-carousell* int-backup`, grisé tant que PHYSICS est off.

Libellés : **jamais la banque de texte / COMMON.TXT**. Les libellés de LIGNE passent par
`name-override` (`*physics-label*` "PHYSICS", `*physics-detail-label*` "PHYSICS DETAIL", gatés
`FLAG_PHYSICS`) ; les 3 libellés d'OPTION sont des globales runtime (`*physics-light-label*`,
`*physics-full-label*`, `*physics-max-label*`, définies inconditionnellement) résolues par
`carousell-option-string` depuis les tags réservés **`#x17b9` LIGHT / `#x17ba` FULL /
`#x17bb` MAXIMUM** — même mécanisme anti-banque-périmée que HD LOOK / PBR ISOLATE. Les tags
**`#x17b7` (PHYSICS) et `#x17b8` (PHYSICS DETAIL)** sont **réservés** pour les libellés de ligne
(non consommés à l'exécution : `name-override` court-circuite toute recherche de texte).
Anglais uniquement.

## GRASS SETTINGS (`*grass-options-pc*` 7 lignes)

RECHARGED GRASS (`recharged-grass?`), NEAR DIST, CARD DIST, DENSITY, GRASS MODE
(`recharged-grass-precomputed?`), GRASS OVERHANG `{FLAG_GRASS_OVERHANG}`, Back.

## §fix — 2 corrections de longueur dans le corps restauré (Gmenu-flag-off)

1. **fw-idx** : le terme "longueur statique pleine" du garde était resté à `(* 9 FLAG_PBR_N)`
   (écrit quand 9 lignes PBR suivaient MATERIALS ; DISPLACEMENT+PRESET+ISOLATE l'ont porté à 12).
   Sur un build hd-models+pbr le garde lisait le tableau PLEIN comme "collapsé" et câblait
   FOLIAGE WIND et toute la suite UNE LIGNE TROP TÔT (= la classe de collisions vue par l'owner).
   → `(* 12 FLAG_PBR_N)`.
2. **Collapse HD** : son garde utilisait l'arithmétique pré-PBR (longueur 11+hud+pbr) et ne
   pouvait JAMAIS tirer sur un build --pbr → ligne ENHANCED MODELS fantôme si FR3 HD absents au
   runtime. → garde sur la vraie longueur pleine + décalage de TOUTES les lignes suivantes.

Preuve bindings : `.autoport/reports/Gmenu-flag-off/x86_binding_proof.log` (dump table + toggles
runtime via la vraie file respond-common/menu-touch). Le porthole (fond fenêtre) est CONSERVÉ
dans le menu livré (le hide V3-E d'adjust-sprites est `#when FLAG_MENU_OVERHAUL`).

---

# ANNEXE — Arborescence de la REFONTE (FLAG_MENU_OVERHAUL **ON** — NON LIVRÉE)

> ⛔ **Gmenu-flag-off (owner 2026-08-04)** : la refonte ci-dessous est **CASSÉE** (paramètres
> inventés, bindings en collision, sélecteur displacement perdu) et est **compilée-out par
> défaut** (`build.sh --menu-overhaul` pour la réactiver, uniquement pour sa future phase de
> rework). Ce qui suit décrit l'état gelé du corps `#when FLAG_MENU_OVERHAUL` de
> `progress-pc.gc`. **L'arborescence LIVRÉE est celle de la section principale ci-dessus.**

> Réécrit 2026-08-01 pour la refonte validée par l'owner, **après le RECADRAGE owner du 2026-08-01** :
> on organise **PAR FONCTION, jamais par origine**. L'ancien couple AFFICHAGE (affichage vanilla) +
> RENDU (rendu Recharged) est **FUSIONNÉ** en UNE seule zone **GRAPHISMES** ; les catégories séparées
> "AFFICHAGE" et "RENDU" **N'EXISTENT PLUS**. Les réglages Recharged sont des citoyens de première classe,
> fondus au milieu des réglages d'origine correspondants (comme un vrai remake, pas un hack).
> Source : `goal_src/jak1/pc/progress-pc.gc`, `goal_src/jak1/engine/ui/progress/progress-h.gc` / `progress.gc`,
> `goal_src/jak1/engine/ui/text-h.gc`, `game/assets/jak1/text/game_custom_text_*.json`.
>
> **Légende** : `[R]` = ajout/tweak Recharged (nous) · `[STOCK]` = jeu d'origine / PC-port OpenGOAL ·
> `[SUPPR]` = retiré (historique conservé en §11) · `[NEW]` = créé par la refonte ·
> `[HDR]` = en-tête de groupe (non-sélectionnable) · `(grisé si …)` = `option-disabled-func` ·
> `(caché si …)` = retiré de la liste (length mutée) · `{FLAG_X}` = présent uniquement si le flag ON.
>
> **STATUT D'IMPLÉMENTATION** (2026-08-01) : ✅ FUSION FAITE — compile propre x86 (549 cibles).
> Les 4 mécanismes UI, l'écran-titre conditionnel, le flux Quitter, le flag `--debug`, les 6 langues, et
> la **zone GRAPHISMES unifiée assemblée par référence** (`build-graphics-unified!`) sont en place.
> NON validé visuellement (l'œil de l'owner juge) — pattern : validator+gates passés → play-test owner.

---

## 0. Les deux points d'entrée (convergent sur le même HUB OPTIONS)

```
ÉCRAN-TITRE (progress-screen title)  — CONDITIONNEL sur la présence de sauvegarde
  Aucune save (*title-pc*)      : Nouvelle partie / Options / Secrets / Quitter / Retour
  >=1 save   (*title-pc-continue*): CONTINUER / Charger une partie / Nouvelle partie / Options /
                                    Secrets / Quitter / Retour
  -> "Charger" est ABSENT quand il n'y a rien à charger ; "CONTINUER" charge la save la + récente en 1 clic
     (progress-newest-save-slot). init-game-options choisit le tableau via (any-save-present?).

PAUSE (progress-screen settings ; *main-options-pc* / *main-options-secrets*)
  Options / Charger / Sauvegarder / Désactiver l'auto-save / (Secrets) / Quitter / Retour
  -> "Options" ouvre le MÊME hub que le titre (settings-title -> *options-hub*).
```

## 1. HUB OPTIONS unifié (`*options-hub*`, écran settings-title)  [NEW]

Un seul écran, **5 catégories** (par fonction). Chaque ligne porte un hint. Il n'y a **plus** de catégorie
"RENDU/Recharged" séparée — le rendu Recharged est fondu dans GRAPHISMES.

| # | Catégorie | text-id (label) | ouvre l'écran | hint |
|---|-----------|-----------------|---------------|------|
| 0 | JOUABILITÉ | pc-text-cat-gameplay | game-settings | pc-text-hint-gameplay |
| 1 | **GRAPHISMES** | pc-text-cat-display (relabellé "GRAPHISMES") | graphic-settings | pc-text-hint-display |
| 2 | AUDIO | pc-text-cat-audio | sound-settings | pc-text-hint-audio |
| 3 | COMMANDES | pc-text-cat-controls | input-options | pc-text-hint-controls |
| 4 | DEBUG | pc-text-cat-debug | debug-options | pc-text-hint-debug |
| 5 | Retour | back | — | — |

- `pc-text-cat-display` porte désormais la chaîne **GRAPHISMES / GRAPHICS / GRAFIK / GRÁFICOS / GRAFICA /
  グラフィック** (7 fichiers locale) ; son hint `pc-text-hint-display` liste les sous-sections.
- `pc-text-cat-render` (RENDU) est **abandonné** (plus référencé ; l'entrée reste dans l'enum, inerte).
- **DEBUG est caché, pas supprimé** : la ligne 4 est retirée de la liste (length mutée 6->5) quand
  `*debug-menus-visible?*` est faux. Ce symbole est semé une fois au boot depuis la constante compile-time
  `FLAG_DEBUG_MENUS` (= `build.sh --debug`). `*opt-debug*` est compilé dans TOUS les builds ; seul son
  affichage est conditionné. Builds de test/damier : `--debug` ; builds release : non.

## 2. Quitter (titre ET pause)  [NEW]

- **Pause** (`*quit-pause-options*`, écran quit) : `[ RETOUR AU TITRE | QUITTER LE JEU | ANNULER ]`
  - RETOUR AU TITRE -> `initialize! *game-info* 'game #f "title-start"` (redémarre le moteur au titre)
  - QUITTER LE JEU -> `commit-to-file` + `kernel-shutdown`
  - ANNULER -> revient au menu pause
- **Titre** (`*quit-title-options*`, écran quit-title) : `[ QUITTER LE JEU | ANNULER ]` (pas de "retour titre")

L'invite "QUITTER ?" (draw-quit) reste au-dessus ; les choix sont des boutons dessinés par draw-options.

## 3. Les 4 mécanismes UI  [NEW, ✅ FAITS]

1. **EN-TÊTES DE GROUPE** : `game-option-type group-header`. Ligne non-sélectionnable — la nav (haut/bas)
   la saute (direction-aware, progress-pc.gc:3719-3773), l'entrée d'écran normalise le focus hors en-tête,
   la confirmation l'ignore (:4001) ; dessinée dans une couleur de titre (progress-blue, :5127), sans
   curseur ni valeur (:5024).
2. **VALEUR LIVE sur 100 % des lignes porteuses de valeur** : on/off, sliders, langues, et TOUS les
   carrousels via `carousell-current-string` (lit le réglage live). Menu/bouton/en-tête/confirmation
   n'affichent aucune valeur — correct.
3. **HINT** : chaque `game-option` porte un champ `hint` (text-id, 0 = aucun). draw-options dessine une
   ligne d'aide en bas de la bande pour la ligne focalisée (:5150-5163), localisée et fondue.
4. **LIGNES CONDITIONNELLES** : mutation de length + swap de tableau — titre conditionnel, catégorie DEBUG,
   et la ligne **Min Target FPS** dans GRAPHISMES (présente seulement si Dynamic Render Scale ON).

---

## 4. La zone **GRAPHISMES** unifiée (`*graphics-unified-pc*`, écran graphic-settings)  [NEW]

UNE seule page, organisée PAR FONCTION, avec le **MASTER Recharged en tête** puis 6 sous-sections séparées
par des en-têtes de groupe. **Assemblée au runtime par RÉFÉRENCE** (`build-graphics-unified!`) à partir des
lignes déjà câblées des tableaux sources (`*graphic-options-pc(-android)*` + `*recharged-options-pc*` +
`*grass-options-pc*`) : `game-option` étant un `basic`, une ligne partagée porte son `value-to-modify` /
`name-override` / `on-change` / `option-disabled-func` / `hint` dans la page fusionnée — aucun recâblage
dupliqué, et respond-common/draw-options dispatchent par `option-type` (le réordonnancement est sûr).
Les tableaux sources restent câblés (substrat) mais ne sont plus atteints par le hub.

Ordre exact (config de ship : PLATFORM_ANDROID, FLAG_PBR ON, HUD/HD/OVERHANG/VULKAN OFF) :

```
RENDU RECHARGED (MASTER)                [R] coupe-circuit global, en tête
[HDR] ÉCRAN            (pc-text-grp-screen)
  Aspect Ratio                          [STOCK]
  Game Resolution                       [STOCK]
  Display mode                          [STOCK] rétabli INERTE sur Android + hint "(SANS EFFET SUR MOBILE)"
  Display / moniteur                    [STOCK] rétabli INERTE sur Android + hint mobile
[HDR] PERFORMANCE     (pc-text-grp-performance)
  Dynamic Render Scale                  [R]
  Render Scale / Min Render Scale       [R] (repointée par apply-dynamic-rs-menu-mode!)
  Min Target FPS                        [R] (cachée si Dynamic Render Scale OFF — length mutée)
  V-Sync                                [STOCK]
  MSAA                                  [STOCK]
  Frame rate                            [STOCK] rétabli INERTE sur Android + hint mobile
[HDR] MATÉRIAUX & DÉTAIL (pc-text-grp-materials)
  PBR Materials            {FLAG_PBR}   [R] (grisé si master OFF)
  Relief (Off/Parallax/Tessellation) {FLAG_PBR} [R] (ex-"Displacement" ; grisé si master/PBR OFF)
  Texture Relief (force)   {FLAG_PBR}   [R]
  Specular Intensity       {FLAG_PBR}   [R]
  Recharged Textures                    [R] (grisé si master OFF)
  Load Custom Assets                    [R] (grisé si master OFF)
[HDR] ÉCLAIRAGE       (pc-text-grp-lighting)
  Realtime Lighting        {FLAG_PBR}   [R] (grisé si master OFF)
  Ambient Occlusion (mode)              [R] (grisé si master OFF)
  AO Quality                            [R] (grisé si master OFF ou AO=Off)
  AO Strength                           [R] (grisé si master OFF ou AO=Off)
  Ambient Model            {FLAG_PBR}   [R] (grisé si master OFF ou Realtime OFF)
  Ambient Strength         {FLAG_PBR}   [R]
  Ambient Contrast         {FLAG_PBR}   [R]
  Env Probe                {FLAG_PBR}   [R]
  Shadow Distance          {FLAG_PBR}   [R]
  Shadow Quality           {FLAG_PBR}   [R]
[HDR] VÉGÉTATION      (pc-text-grp-vegetation)    -- le sous-sous-menu Grass est DISSOUS ici
  Recharged Grass                       [R]
  Near Grass Distance                   [R]
  Grass Card Distance                   [R]
  Grass Density                         [R]
  Grass Mode (précalculé/live)          [R]
  Foliage Wind                          [R] (grisé si master OFF)
[HDR] INTERFACE       (pc-text-grp-hud)
  FPS Counter                           [R]
  Recharged HUD          {FLAG_RECHARGED_HUD}  [R] (absent en ship)
  Advanced (sous-menu PS2 gfx-ps2)      [STOCK] conservé, jamais orphelin
Retour                                  [STOCK]
```

Longueur vive ≈ 42 lignes (41 si Dynamic Render Scale OFF) ; tableau alloué 48. Scroll au-delà de
`PROGRESS_PC_PAGE_HEIGHT (7)`. Les autres catégories restent en pages dédiées :

- **JOUABILITÉ** (game-settings) : Play Hints, Subtitles, Hint Subtitles, Language, Subtitles Language,
  Text Language, Speaker, Misc (money starburst / discord / skips / speedrun). [STOCK/R]
- **AUDIO** (sound-settings) : volumes SFX / Music / Speech, fade-in, langue des voix. [STOCK]
- **COMMANDES** (input-options) : Camera, Controller, Keyboard/Mouse enable, Mouse options, Auto-hide
  cursor, Reassign binds, Restore defaults, overlay tactile. [STOCK/R]
- **DEBUG** (`*opt-debug*`, {caché sauf --debug}) : **Mesh Browser** (freecam / gizmos / damier), **PBR Test
  Preset**, **PBR Isolate** (déplacés hors de GRAPHISMES — outils de mise au point, pas des options joueur),
  Retour. Preset/Isolate = carrousels frais câblés dans init-game-options ({FLAG_PBR}).

---

## 5. TABLE DE CORRESPONDANCE ANCIEN -> NOUVEAU (garde-fou "l'utilisateur n'est pas perdu")

Chaque ligne existante et sa destination après le RECADRAGE. Aucune option n'est orpheline ; les fusions
délibérées sont notées.

| Ancien emplacement | Ligne | Nouvel emplacement |
|--------------------|-------|--------------------|
| Titre `*title-pc*` | New Game / Options / Secrets / Quit | Titre (inchangé) ; **Load** = caché sans save |
| Titre (nouveau) | **CONTINUE** | Titre `*title-pc-continue*` (1-clic, save la + récente) [NEW] |
| Pause : Game Options | menu -> game-settings | **HUB > JOUABILITÉ** (fusion des 3 entrées en 1 "Options") |
| Pause : Graphic Options | menu -> graphic-settings | **HUB > GRAPHISMES** |
| Pause : Sound Options | menu -> sound-settings | **HUB > AUDIO** |
| Titre : Options (`*options*` Game/Graphics/Sound) | — | **HUB à 5 catégories** |
| Game Options : Input Options | menu -> input-options | **COMMANDES** |
| Game Options : Play Hints / Subtitles / Hint Subtitles / Language / Sub Language / Text Language / Speaker | — | **JOUABILITÉ** (inchangé) |
| Game Options : Misc Options | menu -> misc-options | **JOUABILITÉ** (sous-groupe Misc) |
| Graphics : Aspect / Resolution | menu | **GRAPHISMES > [HDR] ÉCRAN** |
| Graphics : Display mode / Display(moniteur) / Frame rate | carousell/menu | **GRAPHISMES > ÉCRAN/PERFORMANCE** ; **RÉTABLIS INERTES sur Android** + hint mobile |
| Graphics : Dynamic Render Scale / Render Scale / Min Target FPS / V-Sync / MSAA | — | **GRAPHISMES > [HDR] PERFORMANCE** |
| Graphics : FPS Counter | on-off | **GRAPHISMES > [HDR] INTERFACE** |
| Graphics : **RECHARGED SETTINGS** (sous-menu) | menu -> recharged-settings | **DISSOUS** : ventilé PAR FONCTION dans GRAPHISMES (plus de catégorie séparée) |
| Graphics : Advanced Settings | menu -> gfx-ps2-options | **GRAPHISMES > INTERFACE** (queue, conservé) |
| Graphics : Vulkan Renderer {FLAG_VULKAN} | on-off | **GRAPHISMES > PERFORMANCE** {FLAG_VULKAN} (source câblée) |
| Recharged : RECHARGED MASTER | on-off | **GRAPHISMES — en tête (coupe-circuit)** |
| Recharged : Recharged HUD {FLAG_RECHARGED_HUD} | on-off | **GRAPHISMES > [HDR] INTERFACE** {FLAG_RECHARGED_HUD} |
| Recharged : Grass Settings (sous-sous-menu) | menu -> grass-settings | **DISSOUS dans GRAPHISMES > [HDR] VÉGÉTATION** |
| Recharged : Load Custom Assets / Recharged Textures | on-off | **GRAPHISMES > [HDR] MATÉRIAUX & DÉTAIL** |
| Recharged : PBR Materials / Texture Relief / Specular / Relief(Displacement) | — | **GRAPHISMES > [HDR] MATÉRIAUX & DÉTAIL** |
| Recharged : Enhanced Models {FLAG_HD_MODELS} | on-off | source câblée (absente en ship ; irait en MATÉRIAUX) |
| Recharged : Foliage Wind | on-off | **GRAPHISMES > [HDR] VÉGÉTATION** |
| Recharged : AO (mode/qualité/force) | carousell ×3 | **GRAPHISMES > [HDR] ÉCLAIRAGE** |
| Recharged : Realtime Lighting / Env Probe / Ambient Model / Ambient Strength/Contrast / Shadow Distance/Quality | — | **GRAPHISMES > [HDR] ÉCLAIRAGE** |
| Recharged : **PBR Test Preset** / **PBR Isolate** | carousell | **DEBUG** (déplacé — outils de mise au point) |
| Recharged : **MESH BROWSER** | button | **DEBUG** (déplacé — outil debug) |
| Grass sous-menu : Recharged Grass / Near/Card dist / Density / Mode / Overhang | — | **GRAPHISMES > [HDR] VÉGÉTATION** (dissous) |
| Sound : SFX/Music/Speech volumes / fade-in | slider/on-off | **AUDIO** (inchangé) |
| Input Options + sous-menus (camera/controller/mouse/keyboard/binds) | — | **COMMANDES** (inchangé) |
| Secrets (titre/pause) / Cheats / Music Player / Checkpoint / Speedrun / Aspect / Advanced / Memcard | — | **inchangés** (hors périmètre OPTIONS ; toujours atteignables) |

## 6. Persistance

Aucune clé de sauvegarde de réglage n'est renommée ni réinitialisée. La fusion ne fait que **partager les
mêmes objets `game-option`** dans une nouvelle page ; les `value-to-modify` pointent toujours vers les
mêmes champs `*pc-settings*` / `*setting-control*` (mêmes clés `settings.ini` / memcard). Les réglages
existants survivent à la mise à jour.

## 7. Langues

Chaque intitulé/hint est un `text-id` présent dans les 6 langues supportées du jeu — **ENG, FRE, GER, ITA,
JAP, SPA** — sur 7 fichiers locale (`game_custom_text_{en-US,en-GB,fr-FR,de-DE,es-ES,it-IT,ja-JP}.json`).
Les text-ids `#x1729`–`#x1740` (catégories, 7 en-têtes de groupe, continue/retour-titre/annuler, 8 hints)
existent déjà en 6 langues (batch menu-overhaul). Le RECADRAGE ne fait que **repointer** `pc-text-cat-display`
(→ "GRAPHISMES") et son hint `pc-text-hint-display` (→ liste des sous-sections) dans les 7 fichiers ; les
6 en-têtes de fonction réutilisent des ids déjà localisés (grp-screen/performance/materials/lighting/
vegetation/hud). Aucun texte anglais-seul.

## 8. Flag de build `--debug`

`build.sh --debug` -> `(defglobalconstant FLAG_DEBUG_MENUS #t)` (+ `_N`) dans le `recharged-flags.gc`
généré, ajouté au FLAG_LIST (marqueur ogflags recalculé, paires CGO/libgk conservées). Flag GOAL-only
(la catégorie DEBUG est dessinée entièrement en GOAL). Semé dans `*debug-menus-visible?*` au boot.

---

## 9. Mécanismes à connaître (rappel)

1. **Fusion par référence** : `build-graphics-unified!` (progress-pc.gc, après *grass-options-pc*)
   remplit `*graphics-unified-pc*` en copiant les RÉFÉRENCES des lignes sources dans l'ordre fonctionnel,
   avec les en-têtes de groupe intercalés. Rejouée par `apply-dynamic-rs-menu-mode!` (pour ajouter/retirer
   Min Target FPS). Les index sources réutilisent l'arithmétique `fw-idx`/`FLAG_*_N` existante.
2. **3 (+1) niveaux de visibilité** : `{FLAG_X}` build-time (absent du CGO) ; `option-disabled-func`
   (grisé) ; length mutée (retiré de la liste) ; + `group-header` (présent mais non-sélectionnable).
3. **Sélection de tableau au runtime** (`*options-remap*`) : titre conditionnel, swap cheat-mode, route
   graphic-settings -> `*graphics-unified-pc*`.
4. **Desktop ≠ Android** : `build-graphics-unified!` choisit le tableau graphics source via `#if
   PLATFORM_ANDROID` et ses index (Display/Frame rate en queue inerte sur Android, au milieu sur desktop).
5. **Pagination** : `PROGRESS_PC_PAGE_HEIGHT = 7` ; au-delà, scroll (keyé sur `(length options)`).
6. **RECHARGED MASTER** : coupe-circuit global (grise toutes les lignes Recharged sans réinitialiser).

---

## 10. Câblage fragile — RÉSOLU par la fusion par référence

- L'ancien risque « insérer des en-têtes DANS les tableaux graphics déplace l'index 4 (Min Target FPS) et
  casse `apply-dynamic-rs-menu-mode!` » est **évité** : les tableaux sources ne sont PAS réordonnés. La
  page GRAPHISMES est un tableau SÉPARÉ assemblé par référence. `apply-dynamic-rs-menu-mode!` maintient
  désormais les tableaux sources en layout PLEIN (`#t`) — donc leurs index restent canoniques — et délègue
  la visibilité de Min Target FPS à `build-graphics-unified!` (paramètre `dyn?`).
- Le câblage `fw-idx` de `*recharged-options-pc*` (progress-pc.gc ~3550-3610) reste **inchangé** ; la page
  fusionnée RÉUTILISE exactement les mêmes expressions d'index pour lire les lignes, donc elle suit les
  flags à l'identique. Aucun tableau reconstruit, aucun recâblage réécrit.

---

## 11. 🗑️ Éléments RETIRÉS (historique conservé)  [SUPPR]

- **Baked Lighting toggle** (`realtime-lighting-baked?`) — supprimé Grecharged-directional-ambient : baked
  = !realtime en dur. (owner : double toggle confus.)
- **Baked Ambient / Baked Reflections / Baked Ambient Quality** — supprimés 2026-07-21 (OWNER #3
  UNIFICATION) : fusionnés dans le groupe AMBIENT unifié (les données probe alimentent les paliers de
  l'Ambient Model). Cubemaps bakées gardées comme ressource consommée par PBR/eau uniquement.
- **Catégorie "AFFICHAGE" + catégorie "RENDU" (tri PAR ORIGINE)** — REJETÉES par le RECADRAGE owner
  2026-08-01 (« c'est débile … comme si c'était un vrai remake et pas un hack »). Fusionnées en UNE zone
  **GRAPHISMES** organisée par fonction. `pc-text-cat-render` abandonné.
- **Sous-menu "Recharged Settings" en tant que tel** — DISSOUS : ses lignes sont ventilées PAR FONCTION
  dans GRAPHISMES (matériaux avec matériaux, éclairage avec éclairage, végétation avec végétation) ; son
  sous-sous-menu Grass dissous dans VÉGÉTATION ; ses lignes debug (PBR Test Preset, PBR Isolate, Mesh
  Browser) déplacées dans la catégorie DEBUG.
- **Écran-titre "Load Game" inconditionnel** — remplacé par un affichage conditionnel (caché sans save).
- **Quitter yes/no** — remplacé par les menus boutons Retour-titre/Quitter/Annuler.
- **Fond hublot + overlay orange du menu** — RETIRÉ des écrans de menu (V2 2026-08-02). Les particules de
  fond `progress particles 0` (tint orange, part 90), `1` (panneau hublot gauche, part 88) et `2` (panneau
  hublot droit, part 89) sont déplacées hors écran (`init-pos x = -320`) sur les écrans holo. Remplacées par
  l'hologramme. Conservées telles quelles sur les pages de stats (cellules/orbes/mouches) et notices memcard.
- **Ligne de hint ancrée sous la bande d'options (origin-y magique 205-215)** — REMPLACÉE (V2) : l'ancre
  grandissait avec le nombre de lignes et sortait de l'écran sur le menu pause/titre. Désormais dérivée du
  cadre : `HOLO_HINT_Y = HOLO_Y + HOLO_H - 12 = 196` (dans le cadre, < 224).

---

## 12. V2 — REDESIGN VISUEL COMPLET (owner 2026-08-02, réouverture)  [NEW]

> La STRUCTURE des §0-11 (5 catégories, GRAPHISMES par fonction, table de correspondance §5) est **INCHANGÉE
> et VALIDÉE** par l'owner (« beaucoup mieux »). Le V2 ne DÉPLACE aucune option — la table §5 reste le
> garde-fou « l'utilisateur n'est pas perdu ». Le V2 est un **re-skin au sol** : le menu vit désormais dans un
> hologramme vertical bleuté (moitié gauche) projeté par le drone de comm. Tout est confiné aux écrans de menu
> (`progress-holo-screen?`) ; les pages de stats / notices memcard gardent leur rendu d'origine. Code :
> `goal_src/jak1/pc/progress-pc.gc`. **L'owner juge le visuel ; le validator gate les faits code.**

**Géométrie (unités menu : x 0..512, y 0..224 ; moitié gauche = x<=256), constantes dérivées d'un seul jeu :**
- `HOLO_X 20` `HOLO_W 224` (<= 256 = demi-écran ; bord droit 244) `HOLO_Y 16` `HOLO_H 192` (bord bas 208).
  Marges > 0 sur chaque bord ; cadre aligné à GAUCHE. Centre du cadre x = 132.
- Boîte texte : `HOLO_TEXT_X 22` `HOLO_TEXT_W 220` (centre 132 = centre du cadre) ; `HOLO_SCALE 0.62`.
- `HOLO_HINT_Y 196` = `HOLO_Y + HOLO_H - 12` (DANS le cadre, à l'écran).

**Les 6 briques (toutes compilent x86, 548 cibles) :**
1. **Hint on-screen** — `draw-options` (progress-pc.gc) : Y = `HOLO_HINT_Y` sur écrans holo (dérivé du cadre),
   sinon ancienne formule *clampée* `(min 214 …)`. Le hint x = `opt-x0` (boîte holo). Corrige le bug pause/titre.
2. **Hints 100 %** — `menu-resolve-hint` résout un text-id pour CHAQUE ligne sélectionnable : hint explicite,
   sinon fallback par NOM (new-game/load/save/options/secrets/quit/back/continue/return-title/cancel/
   disable-auto-save), sinon générique par TYPE (toggle/slider/bind/button/choice). En-têtes de groupe → 0.
   Preuve : `menu-hint-coverage` imprime `screen S: N/N` par écran. 15 nouveaux text-ids `#x1741..#x174f`.
3. **Sections distinctes** — en-têtes de groupe : couleur cyan (progress-blue) + échelle ×1.15 + **filet cyan
   souligné** (`draw-sprite2d-xy`, largeur `HOLO_TEXT_W`) → lisiblement une SECTION, pas une entrée.
4. **Fond nettoyé** — porthole + tint orange (particules 0/1/2) déplacés hors écran sur écrans holo (§11).
5. **Hologramme** — `draw-menu-holo-frame!` : corps translucide cyan + bordure + scanlines via
   `draw-sprite2d-xy` (bucket `sprite`), moitié gauche, `w=224<=256`, marges. Compteur `*menu-holo-draw-count*`
   ++ par frame. Le texte du menu (repositionné via `HOLO_TEXT_X/W/SCALE`) vit DANS le cadre.
6. **Vaisseau-drone projecteur + faisceau** — `update-and-draw-menu-projector!` : représentation 2D-overlay du
   drone de comm **`voicebox`** (mesh `speaker`, `engine/common-obs/voicebox.gc`, résident GAME.CGO/
   `levels/common`) — le petit appareil qui flotte près de Jak lors des comms sages/Assistant. Le vrai
   `voicebox` est couplé à `*target*` + esclave-caméra (`camera-voicebox`) et dangereux à spawner sur la frame
   pause figée, d'où un projecteur 2D contrôlable **documenté**. Il ORBITE l'espace libre à droite du cadre,
   reste ORIENTÉ vers le centre du cadre (vecteur recalculé par frame), et émet un FAISCEAU (points dégradés)
   vers la face du cadre. Spawn à l'ouverture / despawn à la fermeture (`menu-projector-set-active!` depuis le
   `post` + l'`enter` de `progress-going-out`). Compteurs : `*menu-projector-spawn-count*` /
   `*-despawn-count*` / `*-draw-count*` / `*menu-beam-draw-count*`. Lecture : `(menu-holo-stats)`.

---

## V4 (owner 2026-08-02, 3e rejet visuel « pur AI slop ») — RENDU seulement, aucune option déplacée

La STRUCTURE (catégories, emplacements des options, mapping ancien→nouveau ci-dessus) est **inchangée** en
V4 : c'est un pass de RENDU. Défauts owner corrigés :

- **Hologramme = RÉPLIQUE de Jak2** (plus une approximation maison). `draw-menu-holo-frame!` porte la vraie
  recette `hud-box` de `goal_src/jak2/engine/ui/hud.gc` : la table dégradée cyan-vert `scan-colors`
  (:207-240, recopiée verbatim en `*menu-holo-scan-colors*`), le balayage `draw-scan-and-line` (:245 —
  `scanline += 6`/frame, mod hauteur → bande phosphore qui défile), le blend additif GS (`:b 2 :d 1`) et la
  passe `line` d'interlignes blancs. [SUPPR V3] les rectangles `draw-sprite2d-xy` plats.
- **Drone = VRAIE entité 3D** : `update-and-draw-menu-projector!` spawne un `manipy` réel dessinant
  `*voicebox-sg*` (mesh `speaker`), enfant du process progress, dessiné via le chemin HUD
  (`dma-add-process-drawable-hud`, mask `pause`) comme les icônes fuel-cell/money (`progress.gc:243-269`). Il
  ORBITE à côté du cadre + FAISCEAU additif vers le centre. [SUPPR V3] le drone projeté en sprites 2D.
- **Texte centré** sur `HOLO_TEXT_CX` (132) ; **interlignes resserrés** `HOLO_LINE_PITCH` (22, était 30) ;
  **hint clampé** dans le cadre (`HOLO_HINT_Y`/`HOLO_HINT_W`) ; **police teintée cyan** = intégrée à l'holo ;
  **sections** en-tête pleine largeur + options en retrait, toutes centrées.
