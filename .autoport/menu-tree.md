# Jak 1 — Arborescence COMPLÈTE des menus (start menu) — état actuel

> But : tout poser à plat pour réorganiser. Source : `goal_src/jak1/pc/progress-pc.gc` (tableaux d'options),
> `goal_src/jak1/engine/ui/progress/progress-h.gc` (enums). Généré 2026-07-21 (read-only, rien modifié).
>
> **Légende** :
> `[R]` = ajout/ tweak **Recharged** (nous) · `[STOCK]` = jeu d'origine / PC-port OpenGOAL · `[SUPPR]` = retiré par nous (historique)
> `(cond: …)` = **grisé** tant que la condition est vraie (`option-disabled-func`, reste visible)
> `(caché si …)` = **retiré de la liste** au runtime (length mutée, n'apparaît pas du tout)
> `{FLAG_X}` = présent uniquement si le flag de build est ON (sinon **absent du binaire**)

---

## 0. Deux points d'entrée

- **Écran-titre (attract)** → menu titre.
- **En jeu (pause)** → menu principal (= "Settings"), qui ajoute Load/Save + Disable Auto-Save.

Les deux convergent sur les mêmes sous-menus Game / Graphics / Sound.

```
ÉCRAN-TITRE (title / settings-title)
├─ New Game            → save-game-title
├─ Load Game           → load-game
├─ Options             → settings (Game / Graphics / Sound)
├─ Secrets             → secrets            [STOCK, débloqué]
├─ Quit Game           → quit-title
└─ Back

PAUSE (main-options-pc / *-secrets)
├─ Game Options        → game-settings
├─ Graphics Options    → graphic-settings
├─ Sound Options       → sound-settings
├─ Load Game           → load-game
├─ Save Game           → save-game
├─ (Secrets)           → secrets            [dans la variante *-secrets]
├─ Disable Auto-Save   → memcard-disable-auto-save
├─ Quit Game           → quit
└─ Back
```

---

## 1. GAME OPTIONS (`*game-options-pc*`, screen game-settings)  [STOCK]

| # | Option | Type | Valeurs / notes |
|---|--------|------|-----------------|
| 0 | Input Options | menu → input-options | (voir §7) |
| 1 | Play Hints | on-off | persiste `memcard-play-hints?` |
| 2 | Subtitles | on-off | |
| 3 | Hint Subtitles | on-off | |
| 4 | Language | language | |
| 5 | Subtitles Language | language-subtitles | |
| 6 | Text Language | language-text | |
| 7 | Subtitles Speaker | speaker | |
| 8 | Misc Options | menu → misc-options | (voir §8) |
| 9 | Back | button | |

---

## 2. GRAPHICS OPTIONS  — **desktop** (`*graphic-options-pc*`) vs **Android** (`*graphic-options-pc-android*`)

Ordre figé par **Goptions-reorder** (owner 2026-07-01). L'Android **omet** Display mode / Display / Frame rate
(un seul écran 60 Hz). Longueurs pleines : desktop 14 (15 si {FLAG_VULKAN}), android 11 (12 si {FLAG_VULKAN}).

| # desktop | # android | Option | Type | Valeurs / conditions |
|---|---|--------|------|----------------------|
| 0 | 0 | Aspect Ratio | menu → aspect-ratio | (voir §9) |
| 1 | 1 | Game Resolution | menu → resolution | picker résolution `[R? PC-port]` |
| 2 | 2 | **Dynamic Render Scale** | on-off | `[R]` on-change relabel/repointe la ligne 3 + montre/cache la 4 |
| 3 | 3 | **Render Scale** / **Min Render Scale** | slider | `[R]` 10..100 pas 10. OFF→render-scale (manuel) ; ON→min-render-scale (plancher auto) |
| 4 | 4 | **Min Target FPS** | slider | `[R]` 25..60 pas 5 → dyn-target-fps. **(caché si Dynamic Render Scale OFF)** |
| 5 | 5 | **FPS Counter** | on-off | `[R]` label via override |
| 6 | 6 | V-Sync | on-off | |
| 7 | 7 | MSAA | msaa | |
| 8 | — | Display mode | display-mode | **desktop only** (windowed/fullscreen/borderless) |
| 9 | — | Display (moniteur) | menu → monitor | **desktop only** (cond: mode == windowed) |
| 10 | — | Frame rate | frame-rate | **desktop only** (cond: speedrun-mode OU refresh ≤ 60) |
| 11 | 8 | **RECHARGED SETTINGS** | menu → recharged-settings | `[R]` **← le cœur de nos ajouts (voir §3)** |
| 12 | 9 | Advanced Settings | menu → gfx-ps2-options | (ex-"PS2 Options", relabel ; voir §6) |
| 13 | 10 | Vulkan Renderer | on-off | `[R]` {FLAG_VULKAN} — OFF=OpenGL/GLES, ON=Vulkan (Android : préférence persistée, rendu reste GLES) |
| 14 | 11 | Back | button | |

---

## 3. ⭐ RECHARGED SETTINGS (`*recharged-options-pc*`, screen recharged-settings)  [R]

Toutes ces lignes sauf indication sont **{FLAG_PBR}** ou d'autres flags (donc absentes du binaire si le flag est off).
Les lignes lighting sont **grisées tant que "Realtime Lighting" est OFF**.
**Toutes les lignes individuelles (sauf la ligne 0 MASTER et Back) sont grisées tant que "RECHARGED MASTER" (ligne 0) est OFF** (composé avec leur condition propre) — le maître force alors l'état stock de TOUTES les features Recharged sans réinitialiser les réglages individuels.

| # | Option | Type | Valeurs / conditions | Flag |
|---|--------|------|----------------------|------|
| 0 | **RECHARGED MASTER** [R] | on-off | maître GLOBAL — OFF force l'état stock de TOUTES les features Recharged sans réinitialiser les réglages individuels ; prop headless `debug.opengoal.recharged` (0 = vanilla forcé, non-vide ≠0 = forcé ON, vide = suit le réglage) | — |
| 1 | Recharged HUD | on-off | HUD optionnel du fork Recharged ; grisé si RECHARGED MASTER OFF | {FLAG_RECHARGED_HUD} |
| 2 | **Grass Settings** | menu → grass-settings | sous-sous-menu (voir §4) ; grisé si RECHARGED MASTER OFF | — |
| 3 | Load Custom Assets | on-off | pousse le flag runtime (`pc-set-load-custom-assets!`) ; grisé si RECHARGED MASTER OFF | — |
| 4 | PBR Materials | on-off | matériaux Cook-Torrance via custom_assets ; grisé si RECHARGED MASTER OFF | {FLAG_PBR} |
| 5 | Enhanced Models | on-off | modèles HD jak2 (Jak/Daxter/Samos/Keira) ; caché si FR3 HD absent ; grisé si RECHARGED MASTER OFF | {FLAG_HD_MODELS} |
| 6 | Foliage Wind | on-off | vent léger sur palmiers TIE + shrubs ; grisé si RECHARGED MASTER OFF | — |
| 7 | Ambient Occlusion | carousell | **Off / SSAO / HBAO / GTAO** ; grisé si RECHARGED MASTER OFF | — |
| 8 | AO Quality | carousell | **Low / Medium / High** (cond: AO == Off ou RECHARGED MASTER OFF) | — |
| 9 | AO Strength | carousell | **Weaker / Default / Stronger** (cond: AO == Off ou RECHARGED MASTER OFF) | — |
| 10 | **Realtime Lighting** | on-off | `realtime-lighting?` — **maître** de tout le bloc lighting ci-dessous ; grisé si RECHARGED MASTER OFF | {FLAG_PBR} |
| 11 | **Baked Ambient** [R] | on-off | `realtime-probe?` (cond: Realtime OFF ou RECHARGED MASTER OFF) — **DÉFAUT OFF** (OWNER FINAL ARCHITECTURE 2026-07-21) : toggle "curiosité" de la PROJECTION-MONDE des probes (l'ancien composite probe-fed). Par défaut le rendu realtime = **BAKED-MODULATION** (le baked n'est jamais retiré, les soleils le modulent ×) et les probes restent une **RESSOURCE** pour PBR/eau (chargement lazy + upload GPU sauté quand OFF). Ex-ligne "Ambient" (`realtime-ambient?`) recâblée | {FLAG_PBR} |
| 12 | **Ambient Model** | carousell | **Hemisphere / SH / IBL = FIDÉLITÉ D'ÉVALUATION des données PROBE (probe-fed)** — ne s'applique qu'au chemin curiosité "Baked Ambient" ON ; estimation analytique seulement là où il n'y a pas de couverture probe (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 13 | Ambient Strength | slider | 0.0..0.5 pas 0.05 (déc.) → `realtime-ambient-strength` (chemin curiosité uniquement ; cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 14 | Ambient Contrast | slider | 0.0..1.5 pas 0.1 (déc.) → `realtime-ambient-contrast` (chemin curiosité uniquement ; cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 15 | Shadow Distance | slider | 20..200 m pas 10 (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 16 | Shadow Quality | carousell | **Low/Med/High = 1024/2048/4096** (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 17 | Back | button | (jamais grisé) | — |

> **Réorganisation (2026-07-21, OWNER #3 UNIFICATION)** : les trois anciennes lignes BAKED AMBIENT /
> BAKED REFLECTIONS / BAKED AMBIENT QUALITY ont été **fusionnées** dans le groupe AMBIENT unifié
> ci-dessus — les données probe alimentent désormais les paliers de l'Ambient Model. Le menu reste
> long et plat (HUD / assets / matériaux / modèles / foliage / AO / lighting) ; regroupement en
> sous-catégories toujours envisageable (ex : *Lighting*, *Materials*, *Vegetation*, *AO*, *Models*, *HUD*).

---

## 4. GRASS SETTINGS (`*grass-options-pc*`, screen grass-settings)  [R] — sous-menu de Recharged

| # | Option | Type | Valeurs | Flag |
|---|--------|------|---------|------|
| 0 | Recharged Grass | on-off | maître herbe | — |
| 1 | Near Grass Distance | slider | 15..45 m pas 5 | — |
| 2 | Grass Card Distance | slider | 50..140 m pas 10 | — |
| 3 | Grass Density | slider | 100..250 % pas 25 (re-scatter au changement) | — |
| 4 | Grass Mode | on-off | ON=Precomputed (tables bakées) / OFF=Live (scan complet) | — |
| 5 | Grass Overhang | on-off | herbe 3D retombante sur les bords | {FLAG_GRASS_OVERHANG} |
| 6 | Back | button | | — |

---

## 5. SOUND OPTIONS (`*sound-options-pc*`, screen sound-settings)  [STOCK]
| # | Option | Type | Notes |
|---|--------|------|-------|
| 0 | SFX Volume | slider | |
| 1 | Music Volume | slider | |
| 2 | Speech Volume | slider | |
| 3 | Music Fade-in | on-off | |
| 4 | Back | button | |

## 6. ADVANCED SETTINGS / ex-"PS2 Options" (`*gfx-ps2-options*`, screen gfx-ps2-options)  [STOCK]
| # | Option | Type | Notes |
|---|--------|------|-------|
| 0 | LOD Background | lod-bg | niveau de détail décor |
| 1 | LOD Foreground | lod-fg | niveau de détail acteurs |
| 2 | PS2 Particles | on-off | |
| 3 | Force Envmap | on-off | |
| 4 | Force Actors | on-off | (cond) |
| 5 | Back | button | |

## 7. INPUT OPTIONS (`*input-options*`, screen input-options)  [STOCK PC-port]
| # | Option | Type | Cond |
|---|--------|------|------|
| 0 | Camera Options | menu → camera-options | |
| 1 | Controller Options | menu → controller-options | grisé si aucun pad |
| 2 | Enable Keyboard | on-off | |
| 3 | Enable Mouse | on-off | |
| 4 | Mouse Options | menu → mouse-options | grisé si souris off |
| 5 | Auto-hide Cursor | on-off | |
| 6 | Reassign Binds | menu → reassign-binds-options | |
| 7 | Restore Defaults | confirmation | |
| 8 | Back | button | |

### 7a. Camera Options (`*camera-options*`)
1st-person Horizontal / 1st-person Vertical / 3rd-person Horizontal / 3rd-person Vertical (normal-inverted ×4) ·
Restore Defaults (confirmation) · Back

### 7b. Controller Options (`*controller-options*`)
Select Controller (menu → select-controller) · Vibrations (on-off, cond) · Analog Deadzone (slider) ·
Analog Sensitivity (slider) · Ignore Controller when Window Unfocused (on-off) ·
LED Reflect HP (on-off, cond) · LED Reflect Eco (on-off, cond) · LED Reflect Heat (on-off, cond) ·
Pressure Sensitivity (on-off, cond) · Restore Defaults (confirmation) · Back

### 7c. Mouse Options (`*mouse-options*`)
Enable Mouse Camera (on-off) · Horizontal Sens (slider, cond) · Vertical Sens (slider, cond) ·
Enable Mouse Movement (on-off) · Restore Defaults (confirmation) · Back

### 7d. Reassign Binds (`*reassign-binds-options*`)
Controller Binds (menu → controller-binds, cond) · Keyboard Binds (menu → keyboard-binds, cond) ·
Mouse Binds (menu → mouse-binds, cond) · Back
> `controller-binds` / `keyboard-binds` / `mouse-binds` = **écrans spéciaux** de rebinding (liste d'actions,
> pas un tableau game-option).

## 8. MISC OPTIONS (`*misc-options*`, screen misc-options)  [STOCK PC-port]
Money Starburst (on-off) · Discord RPC (on-off) · Cutscene Skips (on-off) · Speedrunner Mode (on-off) · Back

## 9. ASPECT RATIO (`*aspect-ratio-options*`, screen aspect-ratio)  [STOCK PC-port]
Fit to Screen (aspect-new) · Auto/format (aspect-new) · 4:3 PS2 · 16:9 PS2 · autres formats (aspect-new ×4) · Back
> `[R]` tweak Gaspect/Gmenu : le calcul d'aspect a été corrigé sur Android (défaut 4:3 → 16:9).

## 10. SECRETS  [STOCK, débloqué]
- **Depuis l'écran-titre** (`*secrets-title*`) : Music Player (→music-player) · Cheats (→cheats) · Back
- **En jeu / pause** (`*secrets*`) : Cheats (→cheats) · Checkpoint Select (→checkpoint-select, **grisé tant que
  complétion < 100 %**) · Back

### 10a. Cheats (`*cheats*`, screen cheats)  — 15 cheat-toggle + Back
Sidekick Alt · Big Head · Small Head · Big Fist · Big Head NPC · Tunes · Sky · Huge Head · Mirror ·
Eco Yellow · Eco Blue · Eco Red · Eco Green · Invincibility · No Textures · Back

### 10b. Music Player (`*music-player-options*`, screen music-player)  — 21 pistes (button-music) + Back
Village1 · Beach · Jungle · Fishgame · JungleB · Misty · Fire Canyon · Village2 · Rolling · Swamp · Sunken ·
Ogre · Ogre Boss · Village3 · Snow · Cave · Lavatube · Citadel · Final Boss · Credits · Danger · Back

### 10c. Checkpoint Select (`*checkpoint-select-options*`, screen checkpoint-select)  — 17 niveaux (button) + Back
Training · Village1 · Beach · Jungle · Misty · Fire Canyon · Village2 · Sunken · Swamp · Rolling · Ogre ·
Village3 · Snow · Cave · Lavatube · Citadel · Final Boss · Back

## 11. SPEEDRUN (`*speedrun-options*`, screen speedrun-options)  [STOCK PC-port]
Reset Current Run (button) · New Full-Game Run (button) · New Individual Level (menu → speedrun-il-options) ·
New Category Extension (menu → speedrun-cat-ext-options) · Back
- **11a. Individual Level** (`*speedrun-il-options*`) : 16 niveaux (Training · Village1 · Beach · Jungle · Misty ·
  Fire Canyon · Village2 · Sunken · Swamp · Rolling · Ogre · Village3 · Snow · Cave · Lavatube · Citadel) + Back
- **11b. Category Extension** (`*speedrun-cat-ext-options*`) : Full-Game · New-Game+ · Hub1 100% · Hub2 100% ·
  Hub3 100% · All Cutscenes · Back

## 12. MEMORY CARD / SAVE-LOAD (écrans, screen load-game / save-game / save-game-title / auto-save / memcard-*)  [STOCK]
Pas des tableaux d'options mais des **écrans dédiés** (listes de slots + prompts/messages) :
load-game · save-game · save-game-title (saisie nom) · auto-save · memcard-disable-auto-save /
memcard-auto-save-disabled · memcard-no-space / not-inserted / not-formatted / format / data-exists /
loading / saving / formatting / creating / insert / removed / no-data · memcard-error-loading / -saving /
-formatting / -creating · memcard-auto-save-error · quit / quit-title.

## 13. ÉCRANS SPÉCIAUX (pas de tableau game-option — UIs/pickers/messages dédiés)
- **resolution** : picker de résolution (échelle `*resolution-ladder-widths/heights*` + "NATIVE").
- **monitor** : sélection de l'écran/moniteur (desktop).
- **select-controller** : liste des manettes détectées.
- **controller-binds / keyboard-binds / mouse-binds** : UIs de rebinding (liste d'actions).
- **accessibility-options**, **game-ps2-options** : écrans dédiés (enum présent).
- **hint-log** : journal des indices reçus.
- **scrapbook** : galerie d'art / collectibles.
- **scene-player** : rejoueur de cinématiques.
- **flava-player** : lecteur de "flava" musicaux.
- **credits** : défilement des crédits.
- **title / settings-title** : écrans-titre/racine réglages.
- Écrans de statut : pal-change-to-60hz, pal-now-60hz, no-disc, bad-disc, monitor.

---

## 11. 🗑️ Éléments RETIRÉS par nous  [SUPPR] (à conserver en mémoire, cf. ta demande)
- **Baked Lighting toggle** (`realtime-lighting-baked?` + sa ligne de menu + label + wiring) — supprimé à
  Grecharged-directional-ambient (prereq 2) : simplification 2-toggles→1. Désormais **baked = !realtime** en
  dur (Realtime ON ⇒ baked off ; Realtime OFF ⇒ chemin baked stock). Raison : l'owner trouvait le double
  toggle confus ("ne revient pas au défaut").
- **Baked Ambient (on/off)** (`realtime-probe?` + ligne + label `*probe-enable-label*` + wiring) — supprimé
  2026-07-21 par OWNER #3 UNIFICATION : fusionné dans le groupe AMBIENT unifié ci-dessus. Les données probe
  alimentent désormais les paliers de l'Ambient Model (Hemisphere/SH/IBL) ; plus de ligne dédiée.
  **[RESTAURÉ 2026-07-21 soir, OWNER FINAL ARCHITECTURE]** : la ligne 10 redevient "Baked Ambient"
  (`realtime-probe?`, défaut OFF) en recâblant l'ex-ligne "Ambient" (label `*hemisphere-ambient-label*`
  réutilisé, pas de nouveau text-id) — toggle curiosité de la projection-monde ; `realtime-ambient?` n'a
  plus de ligne de menu (interne au chemin curiosité).
- **Baked Reflections (on/off)** (`realtime-probe-reflections?` + ligne + label `*probe-reflections-label*` +
  wiring) — supprimé 2026-07-21 par OWNER #3 UNIFICATION : fusionné dans le groupe AMBIENT unifié. Les cubemaps
  bakées restent bakées et exposées comme **RESSOURCE** consommée uniquement par les phases PBR/eau (roughness/
  metalness IBL) — jamais d'application sur le monde.
- **Baked Ambient Quality (carousell)** (`realtime-probe-quality` + ligne + label `*probe-quality-label*` +
  wiring) — supprimé 2026-07-21 par OWNER #3 UNIFICATION : fusionné dans le groupe AMBIENT unifié. La fidélité
  d'évaluation est désormais portée par l'Ambient Model ; l'enum quality reste réservé (dead-but-compiling)
  pour le handoff PBR-fusion.
- (Rien d'autre de supprimé au niveau menu à ce jour ; les autres tweaks sont des ajouts/reorders.)

---

## 12. Mécanismes à connaître pour réorganiser
1. **Ordre** = ordre des éléments dans le tableau statique. Réorganiser = réordonner le tableau **+** ré-indexer
   le wiring `init-game-options` (chaque ligne à name-override/value-to-modify est câblée par index).
2. **3 niveaux de visibilité** :
   - `{FLAG_X}` build-time (macro `flag-row`) : la ligne est **absente du CGO** si le flag est off.
   - `option-disabled-func` : la ligne est **grisée** (visible, non sélectionnable) selon une condition runtime.
   - **length mutée** au runtime (ex. Min Target FPS) : la ligne est **retirée de la liste** dynamiquement.
3. **Labels** : beaucoup de lignes Recharged utilisent `:name (text-id vsync)` comme placeholder + un
   **name-override** (string runtime, MAJUSCULES car la police menu ne mappe pas les minuscules). Les textes
   langue sont aux ids #x1700+ (`game_custom_text_*.json`).
4. **Desktop ≠ Android** : deux tableaux graphics distincts ; pense aux deux en réorganisant.
5. **Pagination** : `PROGRESS_PC_PAGE_HEIGHT = 7` ; au-delà, scroll. La page Grass fait pile 7 pour tout voir.
6. **RECHARGED MASTER** (Grecharged-master-toggle) : ligne **index 0** de `*recharged-options-pc*` (toutes
   les autres lignes décalées +1, arithmétique d'index dans `init-game-options` mise à jour). Grisage de chaque
   ligne individuelle via `option-disabled-func` **composé** (`(or (not recharged-master?) <cond-existante>)`) ;
   Back et la ligne master ne sont jamais grisés. Persistance `recharged-master?` dans `settings.ini`
   (handle-input/output-settings). Push per-frame `pc-set-recharged-master!` (update-to-os) + à la charge des
   settings au boot. Côté C++ un **unique helper `Gfx::recharged_active`** compose le maître avec chaque flag
   individuel à chaque gate (la prop headless `debug.opengoal.recharged` / env `OG_RECHARGED` est lue
   dans ce helper : 0 = vanilla forcé, ≠0 = forcé ON, vide = suit le réglage) ; seed pré-GOAL du maître
   depuis `settings.ini` dans `Loader::load_common`. OFF == vanilla forcé sans réinitialiser les
   réglages individuels.
