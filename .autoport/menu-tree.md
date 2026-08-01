# Jak 1 — Arborescence des menus — REFONTE Grecharged-menu-overhaul

> Réécrit 2026-08-01 pour la refonte validée par l'owner (propal superviseur 2026-07-30). Remplace
> l'arborescence "état actuel" du 2026-07-21. Source : `goal_src/jak1/pc/progress-pc.gc`,
> `goal_src/jak1/engine/ui/progress/progress-h.gc` / `progress.gc` / `progress-static.gc`,
> `goal_src/jak1/engine/ui/text-h.gc`, `game/assets/jak1/text/game_custom_text_*.json`.
>
> **Légende** : `[R]` = ajout/tweak Recharged (nous) · `[STOCK]` = jeu d'origine / PC-port OpenGOAL ·
> `[SUPPR]` = retiré (historique conservé en §11) · `[NEW]` = créé par la refonte ·
> `(grisé si …)` = `option-disabled-func` (visible, non-sélectionnable) · `(caché si …)` = retiré de la
> liste (length mutée) · `{FLAG_X}` = présent uniquement si le flag de build est ON.
>
> **STATUT D'IMPLÉMENTATION** (2026-08-01, en cours — refonte multi-commits) :
> - ✅ FAIT : les 4 mécanismes UI (en-tête de groupe / valeur live / hint / lignes conditionnelles) ;
>   l'écran-titre conditionnel ; le flux Quitter ; le HUB OPTIONS à 6 catégories ; le flag `--debug` ;
>   les 24 text-ids × 6 langues.
> - 🚧 EN COURS : la réorganisation INTERNE de chaque page-catégorie (déplacement des lignes existantes
>   dans les groupes, restauration des 3 lignes Android inertes, dissolution de Grass dans RENDU,
>   extraction des lignes debug vers DEBUG). Tant que ce n'est pas fait, les pages-catégories affichent
>   encore leur contenu existant. Les mécanismes sont prêts ; il reste le câblage par-catégorie.

---

## 0. Les deux points d'entrée (convergent sur le même HUB OPTIONS)

```
ÉCRAN-TITRE (progress-screen title)  — CONDITIONNEL sur la présence de sauvegarde
  Aucune save (*title-pc*)      : Nouvelle partie / Options / Secrets / Quitter / Retour
  >=1 save   (*title-pc-continue*): CONTINUER / Charger une partie / Nouvelle partie / Options /
                                    Secrets / Quitter / Retour
  -> "Charger" est ABSENT quand il n'y a rien à charger ; "CONTINUER" charge la save la + récente en 1 clic.
  -> mécanisme : init-game-options choisit le tableau via (any-save-present?), comme le swap cheat-mode.

PAUSE (progress-screen settings ; *main-options-pc* / *main-options-secrets*)
  Options / Charger / Sauvegarder / Désactiver l'auto-save / (Secrets) / Quitter / Retour
  -> "Options" ouvre le MÊME hub que le titre (settings-title -> *options-hub*).
```

## 1. HUB OPTIONS unifié (`*options-hub*`, écran settings-title)  [NEW]

Un seul écran, 6 catégories. Chaque ligne porte un hint. "Recharged Settings" est DISSOUS : ce n'est plus
un sous-sous-menu sous Graphics, c'est la catégorie RENDU de premier niveau.

| # | Catégorie | text-id | ouvre l'écran | hint |
|---|-----------|---------|---------------|------|
| 0 | JOUABILITÉ | pc-text-cat-gameplay | game-settings | pc-text-hint-gameplay |
| 1 | AFFICHAGE | pc-text-cat-display | graphic-settings | pc-text-hint-display |
| 2 | RENDU | pc-text-cat-render | recharged-settings | pc-text-hint-render |
| 3 | AUDIO | pc-text-cat-audio | sound-settings | pc-text-hint-audio |
| 4 | COMMANDES | pc-text-cat-controls | input-options | pc-text-hint-controls |
| 5 | DEBUG | pc-text-cat-debug | debug-options | pc-text-hint-debug |
| 6 | Retour | back | — | — |

**DEBUG est caché, pas supprimé** : la ligne 5 est retirée de la liste (length mutée 7->6) quand
`*debug-menus-visible?*` est faux. Ce symbole est semé une fois au boot depuis la constante compile-time
`FLAG_DEBUG_MENUS` (= `build.sh --debug`). Le code de la page DEBUG (`*opt-debug*`) est compilé dans TOUS
les builds ; seul son affichage est conditionné. Builds de test/damier : `--debug` ; builds release : non.

## 2. Quitter (titre ET pause)  [NEW]

- **Pause** (`*quit-pause-options*`, écran quit) : `[ RETOUR AU TITRE | QUITTER LE JEU | ANNULER ]`
  - RETOUR AU TITRE -> `initialize! *game-info* 'game #f "title-start"` (redémarre le moteur au titre)
  - QUITTER LE JEU -> `commit-to-file` + `kernel-shutdown`
  - ANNULER -> revient au menu pause
- **Titre** (`*quit-title-options*`, écran quit-title) : `[ QUITTER LE JEU | ANNULER ]` (pas de "retour titre")

L'invite "QUITTER ?" (draw-quit) reste au-dessus ; les choix sont des boutons dessinés par draw-options.

## 3. Les 4 mécanismes UI  [NEW, ✅ FAITS]

1. **EN-TÊTES DE GROUPE** : nouveau `game-option-type group-header`. Ligne non-sélectionnable — la nav
   (haut/bas) la saute (direction-aware), l'entrée d'écran normalise le focus hors en-tête, la confirmation
   l'ignore ; dessinée dans une couleur de titre (progress-blue), sans curseur ni valeur.
2. **VALEUR LIVE sur 100 % des lignes porteuses de valeur** : on/off (': ON/OFF'), sliders (': 50'),
   langues, et désormais TOUS les carrousels (': CHOIX COURANT') via `carousell-current-string` (lit le
   réglage live, pas le scratch int-backup). Les lignes sans valeur (menu, bouton, en-tête, confirmation)
   n'affichent rien — c'est correct.
3. **HINT** : chaque `game-option` porte un champ `hint` (text-id, 0 = aucun). draw-options dessine une
   ligne d'aide en bas de la bande d'options pour la ligne focalisée, fondue avec la transition du menu.
4. **LIGNES CONDITIONNELLES** : réutilise le mécanisme éprouvé de mutation de length
   (`graphic-options-set-mtf-visible!`) et le swap de tableau (cheat-mode) — utilisés ici pour le
   titre conditionnel et la catégorie DEBUG.

---

## 4. Contenu CIBLE des pages-catégories (🚧 réorg interne en cours)

### JOUABILITÉ (game-settings)
hints, sous-titres, 3 langues, sous-titres locuteur, **auto-save** (nouveau toggle), (Misc : money
starburst / discord / skips cinématiques / mode speedrun).

### AFFICHAGE (graphic-settings) — groupes internes
- **groupe ÉCRAN** : Aspect Ratio, Game Resolution, **Display mode\***, **Display/moniteur\***, plein écran
- **groupe PERFORMANCE** : Dynamic Render Scale, Render/Min Render Scale, Min Target FPS, **Frame rate\***,
  V-Sync, MSAA
- **groupe HUD** : FPS Counter, **HUD Recharged** {FLAG_RECHARGED_HUD}
  `\*` = les 3 lignes rétablies sur Android, inertes, avec hint `pc-text-hint-no-mobile` "(SANS EFFET SUR MOBILE)".
  Règle générale : on ne cache plus de menus sur Android.

### RENDU (recharged-settings) — groupes internes ; le sous-menu Grass est DISSOUS ici
- **groupe GÉNÉRAL** : RECHARGED MASTER (coupe-circuit global, en tête), Recharged Textures
- **groupe MATÉRIAUX** : PBR Materials, Texture Relief, Specular Intensity, Displacement (Off/Parallax/Tess)
- **groupe ÉCLAIRAGE** : Realtime Lighting, Env Probe, Ambient Model, Ambient Strength/Contrast, Shadow
  Distance/Quality, AO (mode/qualité/force)
- **groupe VÉGÉTATION** : Recharged Grass + distances/densité/mode/overhang (ex-sous-menu Grass dissous),
  Foliage Wind

### AUDIO (sound-settings)
SFX / Music / Speech volumes, Music fade-in, **langue des voix**.

### COMMANDES (input-options)
Camera, Controller, Keyboard/Mouse enable, Mouse options, Auto-hide cursor, Reassign binds, Restore
defaults, **overlay tactile**.

### DEBUG (debug-options) — {caché sauf --debug}
Mesh Browser (freecam / gizmos / damier), **PBR Test Preset**, **PBR Isolate**. (Presets/isolate à
migrer depuis RENDU.)

---

## 5. TABLE DE CORRESPONDANCE ANCIEN -> NOUVEAU (garde-fou "l'utilisateur n'est pas perdu")

Chaque ligne existante et sa destination. Aucune option n'est orpheline ; les fusions sont notées.

| Ancien emplacement | Ligne | Nouvel emplacement |
|--------------------|-------|--------------------|
| Titre `*title-pc*` | New Game / Options / Secrets / Quit | Titre (inchangé) ; **Load** = caché sans save |
| Titre (nouveau) | **CONTINUE** | Titre `*title-pc-continue*` (1-clic, save la + récente) [NEW] |
| Pause : Game Options | menu -> game-settings | **HUB OPTIONS > JOUABILITÉ** (fusion des 3 entrées) |
| Pause : Graphic Options | menu -> graphic-settings | **HUB OPTIONS > AFFICHAGE** |
| Pause : Sound Options | menu -> sound-settings | **HUB OPTIONS > AUDIO** |
| Pause : Load / Save / Disable Auto-Save / Quit / Back | — | Pause (inchangé, sous "Options") |
| Titre : Options -> settings-title (`*options*` Game/Graphics/Sound) | — | **HUB OPTIONS à 6 catégories** |
| Game Options : Input Options | menu -> input-options | **COMMANDES** (déplacé) |
| Game Options : Play Hints / Subtitles / Hint Subtitles / Language / Subtitles Language / Text Language / Speaker | — | **JOUABILITÉ** (inchangé de contenu) |
| Game Options : Misc Options | menu -> misc-options | **JOUABILITÉ** (sous-groupe Misc) |
| (nouveau) Auto-Save | toggle | **JOUABILITÉ** [NEW] |
| Graphics : Aspect / Resolution | menu | **AFFICHAGE > groupe ÉCRAN** |
| Graphics : Display mode / Display(moniteur) / Frame rate | carousell/menu | **AFFICHAGE > ÉCRAN/PERFORMANCE** ; **RÉTABLIS INERTES sur Android** + hint mobile |
| Graphics : Dynamic Render Scale / Render Scale / Min Target FPS / V-Sync / MSAA | — | **AFFICHAGE > groupe PERFORMANCE** |
| Graphics : FPS Counter | on-off | **AFFICHAGE > groupe HUD** |
| Graphics : **RECHARGED SETTINGS** (sous-menu) | menu -> recharged-settings | **DISSOUS** : devient la catégorie **RENDU** de 1er niveau |
| Graphics : Advanced Settings | menu -> gfx-ps2-options | **AFFICHAGE** (conservé, sous-menu Avancé) |
| Graphics : Vulkan Renderer {FLAG_VULKAN} | on-off | **AFFICHAGE > PERFORMANCE** {FLAG_VULKAN} |
| Recharged : RECHARGED MASTER | on-off | **RENDU > GÉNÉRAL** (en tête) |
| Recharged : Recharged HUD {FLAG_RECHARGED_HUD} | on-off | **AFFICHAGE > groupe HUD** {FLAG_RECHARGED_HUD} |
| Recharged : Grass Settings (sous-sous-menu) | menu -> grass-settings | **DISSOUS dans RENDU > groupe VÉGÉTATION** |
| Recharged : Load Custom Assets / Recharged Textures | on-off | **RENDU > GÉNÉRAL** |
| Recharged : PBR Materials / Texture Relief / Specular / Displacement | — | **RENDU > groupe MATÉRIAUX** |
| Recharged : Enhanced Models {FLAG_HD_MODELS} | on-off | **RENDU > MATÉRIAUX** {FLAG_HD_MODELS} |
| Recharged : Foliage Wind | on-off | **RENDU > groupe VÉGÉTATION** |
| Recharged : AO (mode/qualité/force) | carousell ×3 | **RENDU > groupe ÉCLAIRAGE** |
| Recharged : Realtime Lighting / Env Probe / Ambient Model / Ambient Strength/Contrast / Shadow Distance/Quality | — | **RENDU > groupe ÉCLAIRAGE** |
| Recharged : **PBR Test Preset** / **PBR Isolate** | carousell | **DEBUG** (déplacé — outils debug) |
| Recharged : **MESH BROWSER** | button | **DEBUG** (déplacé — outil debug) |
| Grass sous-menu : Recharged Grass / Near/Card dist / Density / Mode / Overhang | — | **RENDU > groupe VÉGÉTATION** (dissous) |
| Sound : SFX/Music/Speech volumes / fade-in | slider/on-off | **AUDIO** (inchangé) |
| (voix) langue des voix | — | **AUDIO** [NEW placement] |
| Input Options + sous-menus (camera/controller/mouse/keyboard/binds) | — | **COMMANDES** (inchangé de contenu) |
| (nouveau) overlay tactile | toggle | **COMMANDES** [NEW] |
| Secrets (titre/pause) / Cheats / Music Player / Checkpoint / Speedrun / Aspect / Advanced / Memcard | — | **inchangés** (hors périmètre OPTIONS ; toujours atteignables) |

## 6. Persistance

Aucune clé de sauvegarde de réglage n'est renommée ni réinitialisée. Le déplacement des lignes ne touche
que `value-to-modify` / la position ; les champs `*pc-settings*` et `*setting-control*` restent identiques
(mêmes clés `settings.ini` / memcard). Les réglages existants survivent à la mise à jour.

## 7. Langues

Chaque nouvel intitulé/hint est un `text-id` (jamais `name-override`, qui est anglais-seul) présent dans
les 6 langues supportées du jeu — ENG, FRE, GER, ITA, JAP, SPA — sur 7 fichiers locale
(`game_custom_text_{en-US,en-GB,fr-FR,de-DE,es-ES,it-IT,ja-JP}.json`). 24 nouveaux ids `#x1729`–`#x1740`
(6 catégories, 7 en-têtes de groupe, continue/retour-titre/annuler, 8 hints), soit 24 × 7 fichiers = 168
chaînes. Les de/es/it/ja n'avaient AUCUNE chaîne custom 17xx auparavant : couverture pleine désormais.

## 8. Flag de build `--debug`

`build.sh --debug` -> `(defglobalconstant FLAG_DEBUG_MENUS #t)` (+ `_N`) dans le
`recharged-flags.gc` généré, ajouté au FLAG_LIST (marqueur ogflags recalculé, paires CGO/libgk
conservées). Flag GOAL-only (aucun define C++/CMake nécessaire : la catégorie DEBUG est dessinée
entièrement en GOAL). Semé dans `*debug-menus-visible?*` au boot.

---

## 9. Mécanismes à connaître (rappel)

1. **Ordre** = ordre des éléments du tableau statique ; réorganiser = réordonner + ré-indexer le câblage
   `init-game-options` (chaque ligne à value-to-modify/name-override est câblée par index).
2. **3 niveaux de visibilité** : `{FLAG_X}` build-time (absent du CGO) ; `option-disabled-func` (grisé) ;
   length mutée (retiré de la liste) ; + NEW `group-header` (présent mais non-sélectionnable).
3. **Sélection de tableau au runtime** : `init-game-options` choisit quel tableau lie chaque écran
   (`*options-remap*`) — utilisé pour le titre conditionnel et le swap cheat-mode.
4. **Desktop ≠ Android** : deux tableaux graphics ; l'Android RÉTABLIT désormais les 3 lignes inertes.
5. **Pagination** : `PROGRESS_PC_PAGE_HEIGHT = 7` ; au-delà, scroll.
6. **RECHARGED MASTER** : coupe-circuit global (grise toutes les lignes Recharged sans réinitialiser).

---

## 10. Câblage fragile à surveiller (réorg interne restante)

- `apply-dynamic-rs-menu-mode!` suppose le **Min Target FPS à l'index 4** de chaque tableau graphics et
  cache/montre cette ligne par mutation de length. Insérer des en-têtes de groupe DANS le tableau graphics
  déplace cet index -> le mécanisme MTF doit être ré-ancré en même temps. NE PAS toucher à l'un sans l'autre.
- `*recharged-options-pc*` : câblage `fw-idx` runtime (progress-pc.gc ~3390-3510) dérivé des `FLAG_*_N`
  (les lignes flag-gated décalent les index). Dissoudre Grass / déplacer les lignes debug impose de
  reconstruire ce tableau + réécrire ce câblage explicitement.

---

## 11. 🗑️ Éléments RETIRÉS (historique conservé)  [SUPPR]

- **Baked Lighting toggle** (`realtime-lighting-baked?`) — supprimé Grecharged-directional-ambient : baked
  = !realtime en dur. (owner : double toggle confus.)
- **Baked Ambient / Baked Reflections / Baked Ambient Quality** — supprimés 2026-07-21 (OWNER #3
  UNIFICATION) : fusionnés dans le groupe AMBIENT unifié (les données probe alimentent les paliers de
  l'Ambient Model). Baked Ambient partiellement restauré puis re-fusionné ; cubemaps bakées gardées comme
  ressource consommée par PBR/eau uniquement.
- **Sous-menu "Recharged Settings" en tant que tel** — DISSOUS par cette refonte : promu catégorie RENDU
  de 1er niveau ; son sous-sous-menu Grass dissous dans le groupe VÉGÉTATION ; ses lignes debug (PBR Test
  Preset, PBR Isolate, Mesh Browser) déplacées dans la catégorie DEBUG.
- **Écran-titre "Load Game" inconditionnel** — remplacé par un affichage conditionnel (caché sans save).
- **Quitter yes/no** — remplacé par les menus boutons Retour-titre/Quitter/Annuler.
