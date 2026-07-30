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
| 4 | **Recharged Textures** [R] | on-off | Grecharged-bundled-textures (2026-07-22) : textures de remplacement first-party de l'owner, EMBARQUÉES dans l'APK (pack custom → `<custom root>/recharged_textures/`) ; ON = base swaps bundled, OFF = stock ; les maps `_height/_normal/_roughness` du bundle suivent le toggle PBR (pas cette ligne) ; précédence user custom_assets > bundled > stock ; `pc-set-recharged-textures!`, défaut ON, appliqué au prochain chargement de niveau ; grisé si RECHARGED MASTER OFF | — |
| 5 | PBR Materials | on-off | matériaux Cook-Torrance via custom_assets ; grisé si RECHARGED MASTER OFF | {FLAG_PBR} |
| 6 | Enhanced Models | on-off | modèles HD jak2 (Jak/Daxter/Samos/Keira) ; caché si FR3 HD absent ; grisé si RECHARGED MASTER OFF | {FLAG_HD_MODELS} |
| 7 | Foliage Wind | on-off | vent léger sur palmiers TIE + shrubs ; grisé si RECHARGED MASTER OFF | — |
| 8 | Ambient Occlusion | carousell | **Off / SSAO / HBAO / GTAO** ; grisé si RECHARGED MASTER OFF | — |
| 9 | AO Quality | carousell | **Low / Medium / High** (cond: AO == Off ou RECHARGED MASTER OFF) | — |
| 10 | AO Strength | carousell | **Weaker / Default / Stronger** (cond: AO == Off ou RECHARGED MASTER OFF) | — |
| 11 | **Realtime Lighting** | on-off | `realtime-lighting?` — **maître** de tout le bloc lighting ci-dessous ; grisé si RECHARGED MASTER OFF | {FLAG_PBR} |
| 12 | **Env Probe** [R] | carousell | **[SUPPR Baked Ambient 2026-07-23]** puis **REMPLI 2026-07-23 (Grecharged-pbr-realtime-fusion)** : **Off / Low / Mid / High**, **défaut Low** → `follow-probe` (0/1/2/3) — tier de la **DYNAMIC FOLLOW-PROBE** (cubemap caméra amortie, source env pour PBR/eau/acteurs), poussé en index brut chaque frame via `pc-set-follow-probe!`. Occupe le slot vacant fw-idx +5 (ancien toggle `realtime-probe?` supprimé). Miroir exact du carousell **Displacement** (int-backup + respond-common). Grisé si **PBR Materials OFF** ou RECHARGED MASTER OFF. Câblé aux presets PBR TEST : ALL-IN=3, FUSED=2, FUSED FLAT=1, PBR ONLY=2, RT ONLY=0, STOCK=0. | {FLAG_PBR} |
| 13 | **Ambient Model** | carousell | **Hemisphere / SH / IBL = FIDÉLITÉ D'ÉVALUATION des données PROBE (probe-fed)** — ne s'applique qu'au chemin curiosité "Baked Ambient" ON ; estimation analytique seulement là où il n'y a pas de couverture probe (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 14 | Ambient Strength | slider | 0.0..0.5 pas 0.05 (déc.) → `realtime-ambient-strength` (chemin curiosité uniquement ; cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 15 | Ambient Contrast | slider | 0.0..1.5 pas 0.1 (déc.) → `realtime-ambient-contrast` (chemin curiosité uniquement ; cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 16 | Shadow Distance | slider | 20..200 m pas 10 (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 17 | Shadow Quality | carousell | **Low/Med/High = 1024/2048/4096** (cond: Realtime OFF ou RECHARGED MASTER OFF) | {FLAG_PBR} |
| 18 | **Texture Relief** [R] | slider | 0.0..3.0 pas 0.25 (déc.) → `pbr-texture-relief`, **défaut 1.5** (1.0 = look pré-slider) — multiplie la force de la normal-map + parallax du chemin PBR MATERIALS (cond: **PBR Materials OFF** ou RECHARGED MASTER OFF). **Ajout Gpbr-fusion REOPEN #2** | {FLAG_PBR} |
| 19 | **Specular Intensity** [R] | slider | 0.0..3.0 pas 0.1 (déc.) → `pbr-specular-intensity`, **défaut 0.15 (REOPEN #6 matte-dielectric)** — échelle le spéculaire GGX fusionné, mais NE contrôle PLUS le look matte : les surfaces rugueuses (dielectrics = pierre/sable/herbe) sont matte par construction via le `matte_gate` shader (spéc → ~0 dès roughness ≥ 0.60), ce slider ne fait que doser le reflet résiduel sur les texels VRAIMENT lisses/métalliques. Owner monte pour les matériaux brillants (cond: **PBR Materials OFF** ou RECHARGED MASTER OFF). **Ajout Gpbr-fusion REOPEN #2 ; défaut abaissé 1.0→0.15 REOPEN #6** | {FLAG_PBR} |
| 20 | **Displacement** [R] | carousell | **Off / Parallax / Tessellation**, **défaut Parallax** → `pbr-displacement` (0/1/2) — mode de déplacement du chemin PBR MATERIALS, poussé en index brut via `pc-set-pbr-displacement!` (cond: **PBR Materials OFF** ou RECHARGED MASTER OFF). **Ajout Gpbr-fusion REOPEN #3** | {FLAG_PBR} |
| 21 | **PBR Test Preset** [R] | carousell | **DEBUG (retirable plus tard)** — **ALL-IN / FUSED / FUSED FLAT / PBR ONLY / RT ONLY / STOCK**, **défaut FUSED** → `pbr-test-preset` (0..5) ; applicateur one-click : à la confirmation il ÉCRIT les réglages sous-jacents (master/textures/pbr/realtime/custom-assets + relief/spéculaire/displacement/ambient-model) et le `commit-to-file` partagé persiste tout. **TOUJOURS actif** (pas de option-disabled-func) — le preset STOCK met `recharged-master?` à OFF, la ligne doit rester utilisable pour revenir en arrière. **RT ONLY (idx 4) garde `load-custom-assets?` ON depuis 2026-07-23** (RT sur textures custom, cartes PBR OFF). **Ajout Gpbr-fusion REOPEN #3** | {FLAG_PBR} |
| 22 | **PBR Isolate** [R] | carousell | **DEBUG (retirable plus tard)** — **BOTH / NORMAL-MAP ONLY / PARALLAX ONLY / NEITHER**, défaut BOTH → `pbr-isolate` (0..3), poussé chaque frame en index brut via `pc-set-pbr-isolate!` ; setter C++ mappe index→masque `u_pbr_bisect` (BOTH 0 / NORMAL-MAP ONLY 128 / PARALLAX ONLY 64 / NEITHER 192) et écrit l'état dans `files/pbr_tan_diag.txt` à chaque changement. Bisection de terme IN-MENU (owner isole les facettes sans adb). Grisé selon **PBR Materials OFF** ou RECHARGED MASTER OFF. **Ajout Gpbr-fusion REOPEN #10 ; diag REOPEN #11 ; labels d'option = strings globales runtime (bank-indépendant) REOPEN #11 pré-livraison** | {FLAG_PBR} |
| 23 | **MESH BROWSER** [R] | button | **DEBUG — navigateur de mesh** (`pc-text-mesh-browser` #x1728). Ouvre l'overlay `*mesh-browser*` : **CAMÉRA LIBRE** autour de n'importe quel mesh des **25 niveaux** indexés — **le joueur n'est JAMAIS déplacé**, c'est la caméra qui va au mesh —, prévisualise textures/PBR, bascule damier / tessellation-parallax-off / relief / heure du jour, orbite 360° + élévation ±89° (dessus d'un toit comme dessous d'un surplomb), spin du mesh, note hors-ligne affichée. **TOUJOURS actif** (un outil debug doit rester atteignable même master OFF) ; respond-common appelle `mesh-browser-open!` et repasse en `master-mode 'game`. Tactile (glissement + inertie, poignée de défilement, tap direct, pincement) ET manette, sans adb. **Ajout Grecharged-mesh-browser ; tactile réel + FREE CAM, RÉOUVERTURES 2026-07-29 ; V2 2026-07-30 : la liste devient l'UI SECONDAIRE, le mode principal est le FREECAM+RÉTICULE (voir addendum V2 ci-dessous) — entrée hors-menu par R3 / bouton overlay CAM (groupe Start/Select, placement owner)** | — |
| 24 | Back | button | (jamais grisé) | — |

> **Ajout (2026-07-23, Gpbr-fusion REOPEN #2)** : deux sliders **Texture Relief** (0..3, défaut 1.5) et
> **Specular Intensity** (0..2, défaut 1.0) insérés APRÈS Shadow Quality, AVANT Back (Back renuméroté 18→20).
> Contrairement aux sliders lighting, ceux-ci sont grisés selon **PBR Materials** (pas Realtime Lighting) car
> ils vivent dans le chemin matériau PBR. Poussés chaque frame en int PERCENT (1.5→150 / 1.0→100) via
> `pc-set-pbr-texture-relief!` / `pc-set-pbr-specular-intensity!`.
>
> **Ajout (2026-07-23, Gpbr-fusion REOPEN #3)** : carousell **Displacement** (Off / Parallax / Tessellation,
> défaut Parallax) inséré APRÈS Specular Intensity, AVANT Back (Back renuméroté 20→21). Grisé selon **PBR
> Materials** (comme les deux sliders REOPEN #2). Miroir exact du carousell **Ambient Model** (int-backup +
> respond-common), poussé chaque frame en index brut via `pc-set-pbr-displacement!` (0 OFF / 1 PARALLAX /
> 2 TESSELLATION). Ids texte : `pc-text-parallax` #x1719 / `pc-text-tessellation` #x171a (Off réutilise l'id générique).
>
> **Ajout (2026-07-23, Gpbr-fusion REOPEN #3 — DEBUG, retirable plus tard)** : carousell **PBR Test Preset**
> (ALL-IN / FUSED / FUSED FLAT / PBR ONLY / RT ONLY / STOCK, défaut FUSED) inséré APRÈS Displacement, AVANT
> Back (Back renuméroté 21→22 ; Displacement inchangé, reste ligne 20). Applicateur one-click de config
> voulue : la MACHINERIE carousell est identique à Displacement (int-backup + respond-common), mais l'arm de
> WRITE-BACK est spécial — sur confirmation il ÉCRIT les champs sous-jacents (`recharged-master?`,
> `recharged-textures?`, `pbr-materials?`, `realtime-lighting?`, `load-custom-assets?`, `pbr-texture-relief`,
> `pbr-specular-intensity`, `pbr-displacement`, `realtime-ambient-model`) puis stocke le choix dans
> `pbr-test-preset` ; le `commit-to-file` partagé de fin de branche persiste tout. **TOUJOURS actif** (aucune
> option-disabled-func) car le preset STOCK coupe `recharged-master?` et la ligne doit rester utilisable pour
> revenir. AUCUN extern/push C++ (le preset n'écrit que d'autres réglages ; le C++ ne le lit jamais). Ids
> texte : `pc-text-preset-allin` #x171b .. `pc-text-preset-stock` #x1720.
>
> **Correctif (2026-07-23)** : l'arm **RT ONLY** (index 4) garde désormais les **custom assets ON**
> (`load-custom-assets?` #f → #t) — l'éclairage realtime s'applique sur **les mêmes textures custom que
> FUSED**, seules les cartes PBR (normal/rough/metal/height/spec) restent OFF. Avant, le RT ONLY forçait
> `load-custom-assets?` OFF et rendait des textures quasi-stock (« aucun effet visible » côté owner).
> Le preset **STOCK** qui n'affiche « que les textures » (vanilla) reste **voulu** : c'est le killswitch
> vanilla complet (master OFF, tout OFF).
>
> **Ajout (2026-07-23, Grecharged-pbr-realtime-fusion)** : carousell **Env Probe** (Off / Low / Mid / High,
> défaut Low) posé dans le slot **12** vacant laissé par la suppression du toggle Baked Ambient (`realtime-probe?`).
> Pilote le tier de la **DYNAMIC FOLLOW-PROBE** (source env cubemap amortie pour PBR/eau/acteurs). Miroir exact
> du carousell **Displacement** : champ `follow-probe int32` (défaut 1), extern `pc-set-follow-probe!`
> `(function int none)`, push chaque frame en index brut dans update-to-os, `game-option-type follow-probe`,
> `*carousell-follow-probe*`, `*envprobe-label*` "ENV PROBE", wiring name-override à fw-idx +5, arms
> respond-common (int-backup / select / write-back) + 4 listes nav-length. Le remplissage de ce slot **réaligne**
> le câblage RT (Ambient Model .. PBR Test Preset) qui référençait fw-idx +6..+14 depuis la suppression du
> toggle. Ids texte : `pc-text-envprobe-low` #x1721 / `-mid` #x1722 / `-high` #x1723 (Off réutilise l'id générique).
> Câblé aux presets PBR TEST : ALL-IN=3, FUSED=2, FUSED FLAT/PLATE=1, PBR ONLY=2, RT ONLY=0, STOCK=0.
> Setter C++ : `pc_set_follow_probe(u32 tier)` → `Gfx::g_global_settings.recharged_follow_probe` (clamp ≤3).
>
> **Ajout (2026-07-24, Gpbr-fusion REOPEN #10 — DEBUG, retirable plus tard)** : carousell **PBR Isolate**
> (Both / Normal-map only / Parallax only / Neither, défaut Both) inséré APRÈS PBR Test Preset, AVANT Back
> (Back renuméroté 22→23 ; les lignes précédentes inchangées — ajout en fin de bloc PBR à fw-idx +15).
> Grisé selon **PBR Materials** (comme Displacement). C'est la **bisection de terme IN-MENU** demandée par
> l'owner : il isole lui-même le terme responsable des facettes résiduelles sur l'herbe à SON vantage, sans
> adb. Miroir exact du carousell **Displacement** (int-backup + respond-common, 4 arms + wiring name-override).
> Champ `pbr-isolate int32` (défaut 0), extern `pc-set-pbr-isolate!` `(function int none)`, push chaque frame
> en index brut via update-to-os, `game-option-type pbr-isolate`, `*carousell-pbr-isolate*`,
> `*pbr-isolate-label*` "PBR ISOLATE". Setter C++ `pc_set_pbr_isolate(u32 idx)` mappe l'index carousell vers le
> **masque `u_pbr_bisect`** : BOTH 0, NORMAL-MAP ONLY 128 (POM off), PARALLAX ONLY 64 (normal-map off),
> NEITHER 192 → `Gfx::g_global_settings.recharged_pbr_isolate`, qui **amorce** `pbr_bisect` dans le chemin
> fusionné (le prop/env debug l'écrase encore pour l'A/B headless du superviseur sur l'ensemble des termes).
> Ids texte : `pc-text-pbr-iso-both` #x1724 / `-nm` #x1725 / `-pom` #x1726 / `-neither` #x1727.
>
> **Correctif (2026-07-24, Gpbr-fusion REOPEN #11 — le menu ISOLATE était CASSÉ chez l'owner)** : les 4
> options s'affichaient « Unknown ID 5924-5927 » (= décimal de #x1724-#x1727) et flipper ne faisait RIEN.
> Cause 1 (Unknown ID) : les 4 strings existaient bien dans `game_custom_text_en-US.json` / `_fr-FR.json`
> (ids 0x1724-0x1727) et dans les banques desktop fraîches, MAIS l'overlay `out/jak1-android-text/*COMMON.TXT`
> (périmé 2026-07-23) écrasait la banque desktop fraîche dans `build_cgo_pack.sh` → le `0COMMON.TXT` du device
> (40016 o) n'avait AUCUNE des 4 strings (classe « desktop TXT poussé par-dessus l'overlay android »). FIX =
> régénérer l'overlay android-text (`gtt_build_android_text.sh`) → banques fraîches (40208 o) portant les 4
> strings (EN+FR) → repack cgo + push → device `0COMMON.TXT` porte désormais les 4 VRAIS LABELS (prouvé).
> Cause 2 (flip inerte) : le câblage GOAL→C++→uniform était en fait intact, mais SANS OBSERVABILITÉ (le fichier
> diag mandé par l'owner #11 n'était pas implémenté). FIX = `pc_set_pbr_isolate` écrit maintenant l'index actif +
> le masque `u_pbr_bisect` résolu dans `files/pbr_tan_diag.txt` à CHAQUE changement. Preuve device : naviguer au
> row PBR ISOLATE et flipper BOTH→NORMAL-MAP ONLY→PARALLAX ONLY→NEITHER écrit `settings.ini pbr-isolate =
> 0/1/2/3` ET le diag montre `mask = 0/128/64/192` — le flip change bien le masque que lit le shader fusionné.
> Rapport à PBR TEST PRESET : la ligne ISOLATE est un override DEBUG indépendant du masque de bisection (elle
> amorce `pbr_bisect` via `recharged_pbr_isolate`) ; le preset écrit les autres réglages mais jamais le champ
> isolate → ils se composent (le preset pose la config, l'isolate bisecte les termes à l'intérieur). Vérifié
> pré-livraison sur le Redmi (cpad_inject nav + screenshots des vrais labels + diag change à chaque flip).
>
> **Correctif PRÉ-LIVRAISON (2026-07-24, Gpbr-fusion REOPEN #11 — la vérif supervisor a RATTRAPÉ le menu
> ENCORE en « Unknown ID 5924-5927 »)** : le correctif ci-dessus reposait sur la fraîcheur de la banque
> `COMMON.TXT` (artefact de build slim-APK qui REDEVIENT périmé — classe récurrente). Les options du carousell
> se résolvent via `lookup-text! *common-text*` sur des text-ids ⇒ tant que le device n'est pas sur un pack
> fraîchement rebâti, elles retombent sur « Unknown ID ». Correctif DURABLE, indépendant de la banque : les 4
> labels d'OPTION sont désormais des **strings globales runtime** (comme `*displacement-label*`) —
> `*pbr-iso-both-label*` / `*pbr-iso-nm-label*` / `*pbr-iso-pom-label*` / `*pbr-iso-neither-label*`, remplies
> par `(format (clear …) "BOTH"/"NORMAL-MAP ONLY"/"PARALLAX ONLY"/"NEITHER")` dans `progress-pc.gc`. Un
> résolveur `carousell-option-string` route UNIQUEMENT les 4 ids `pc-text-pbr-iso-*` vers ces globales ; tout
> autre id de carousell passe par le chemin `lookup-text!` inchangé (zéro régression sur displacement/AO/preset/
> etc.). `print-string-in-carousell` appelle ce résolveur : les 4 options rendent des VRAIS LABELS compilés
> dans le GOAL, « Unknown ID » ne peut plus réapparaître quelle que soit la fraîcheur de la banque texte. Les
> strings JSON (0x1724-0x1727 EN+FR) sont GARDÉES en ceinture+bretelles mais ne sont plus sur le chemin
> critique. Texte affiché IDENTIQUE (BOTH / NORMAL-MAP ONLY / PARALLAX ONLY / NEITHER) — seule la SOURCE du
> label change (text-id → globale runtime). Le supervisor re-vérifie sur le Redmi avant l'owner.
>
> **Changement de défaut (2026-07-23, Gpbr-fusion REOPEN #6 — MATTE-DIELECTRIC)** : après playtest #4 owner
> (décompo : « Lighting-only » BON, la vitre n'apparaît QUE avec PBR ⇒ la vitre EST le terme spéculaire/env sur
> matériaux MATTE), le look par défaut devient **matte** : le shader `tfrag3.frag` gagne un `matte_gate` =
> `max(1 - smoothstep(0.30,0.60,roughness), metal)` qui pousse TOUT le spéculaire (GGX des 2 soleils + réflexion
> env) vers ~0 dès que la surface est rugueuse (roughness ≥ 0.60 ⇒ zéro reflet, zéro highlight caméra-dépendant),
> sur les DEUX chemins (fusionné rt-ON+pbr-ON ET standalone pbr-ONLY). Seuls les texels vraiment lisses/métal
> gardent un reflet. Le **défaut du slider Specular Intensity passe 1.0 → 0.15** (matte est la norme ; le slider
> ne dose que le résiduel lisse/métal). Presets réalignés : ALL-IN spéc 0.2, FUSED/FUSED FLAT spéc 0.15.
> Bisect bit **4096** = matte_gate OFF (killswitch device A/B : restaure l'ancienne vitre pour prouver que le
> chemin matte est actif). `_roughness` manquante ⇒ 0.9 (ROUGH) sur les deux chemins (jamais lisse).
>
> **Réorganisation (2026-07-21, OWNER #3 UNIFICATION)** : les trois anciennes lignes BAKED AMBIENT /
> BAKED REFLECTIONS / BAKED AMBIENT QUALITY ont été **fusionnées** dans le groupe AMBIENT unifié
> ci-dessus — les données probe alimentent désormais les paliers de l'Ambient Model. Le menu reste
> long et plat (HUD / assets / matériaux / modèles / foliage / AO / lighting) ; regroupement en
> sous-catégories toujours envisageable (ex : *Lighting*, *Materials*, *Vegetation*, *AO*, *Models*, *HUD*).
>
> **Ajout (2026-07-27, Grecharged-mesh-browser — DEBUG)** : bouton **MESH BROWSER** inséré APRÈS PBR Isolate,
> AVANT Back (Back renuméroté 23→24 ; toutes les lignes précédentes inchangées — ajout en fin de bloc, au tail
> après tout le câblage/collapse existant, donc seules les gardes de longueur totale changent, pas les indices
> fw-idx ni la boucle de collapse). Id texte `pc-text-mesh-browser` #x1728 ("MESH BROWSER" EN+FR). C'est un
> **bouton** (`game-option-type button`), pas un carousell : `respond-common` matche l'id, joue `select-option`,
> appelle `mesh-browser-open!` et repasse en `set-master-mode 'game` (l'overlay prend l'écran). **TOUJOURS actif**
> (aucune option-disabled-func) — un outil de debug doit rester atteignable même avec RECHARGED MASTER OFF.
> Ouvre l'overlay `*mesh-browser*` (`pc/mesh-browser-pc.gc`), piloté par un seul appel par frame
> `(mesh-browser-update)` accroché dans `(update *pc-settings*)` juste après `draw-pc-fps-counter` — ne fait RIEN
> tant qu'il est fermé (chemin de rendu normal inchangé bit-à-bit). Modes : LEVEL PICKER → MESH LIST (filtres
> ALL / FAILING / TFRAG / TIE, tri PIRE-NOTE-D'ABORD hérité de l'index, note hors-ligne affichée) → OBSERVE
> (warp + auto-cadrage depuis la bounding box, orbite libre cam-orbit, spin lumière-vs-mesh L1/R1, bascules
> damier / displacement / relief / heure du jour). Identifiant mesh affiché à l'écran ET exporté dans
> `files/mesh_select.txt` (owner sans adb). Tactile ET manette (strip de boutons tap en bas d'écran = parité
> pad). Index par niveau `mesh_index_<level>.txt` distillé de tess_sign par `tools/mesh_index`, embarqué dans
> l'APK (`<custom root>/mesh_index/`, `file_util::get_bundled_mesh_index_dir`). Le damier réutilise le mode
> `PbrTestPattern` existant via `recharged_mesh_browser_checker` (gfx.h) : sans prop/env debug, le toggle menu
> possède le pattern ; le prop/env l'écrase encore dans les deux sens (A/B headless superviseur inchangé).
>
> **V2 (2026-07-30, Grecharged-mesh-browser — refonte owner "le mesh browser actuel est à chier")** : le mode
> principal devient le **FREECAM + RÉTICULE** ; la liste ci-dessus SURVIT en écran secondaire (elle sait sauter
> vers un mesh lointain). **Entrées HORS-MENU** (aucune nouvelle ligne de menu) : **R3** (clic stick droit) en
> jeu, **R3 depuis n'importe quel écran du browser** (depuis OBSERVE, la caméra CONTINUE — le mesh observé est
> pré-ciblé), et côté tactile un **bouton overlay `CAM`** (TouchOverlayView, mode normal uniquement) qui émule
> R3 — **placement owner 2026-07-30 ("à côté de start et select") : DANS le groupe Start/Select**, même rangée,
> même taille et style de pilule, à droite de START (le groupe se lit SELECT | START | CAM). **R3 ressort** (monde rendu tel qu'emprunté : want-list, border-mode, joueur réveillé, caméra au joueur).
> En freecam l'overlay tactile reste en MODE PAD (mode natif `pc-mb-set-active!` = 2, contrairement au mode 1
> liste qui suspend le pad pour le multi-touch brut) avec un set de contrôles freecam : stick virtuel = VOL
> (toutes directions, y compris l'air — la translation suit le regard), zone caméra = ORIENTATION, boutons
> séparés R1/R2/L1/L2/□/○/△/X(BOOST)/TOD±/REL±/EXIT. Manette : **stick gauche vol, stick droit regard,
> R1/R2 = cibler le mesh sous le viseur** (**V2.2** : PREMIER IMPACT le long du rayon — ray-test des VRAIS
> triangles de chaque candidat (Möller-Trumbore, même parcours que le grader hors-ligne), tri par distance de
> surface la plus proche, candidats boîte-seule éliminés ; un mesh occulté par un autre sur le même rayon ne
> gagne JAMAIS, un mesh derrière la caméra n'est JAMAIS candidat (tmax<0 rejeté) ; R1/R2 cyclent les
> candidats survivants), **L1 = cacher / L2 = montrer** la cible, **□ = damier COMPLET** sur la cible
> (**V2.2** : albedo + height + normal + roughness damier, ET le chemin de displacement courant réellement
> engagé sur les draws de la cible — pas la texture seule), **○ = gizmos de
> normales** (flèches par face, convention de winding = celle de tess_sign : une normale rentrante SE VOIT),
> **△ = defocus** (cible nulle, toggles inertes), **X = boost**, **dpad ←/→ = heure, ↑/↓ = relief**. Le NOM
> ciblé (matériau + niveau + shell + tex + note hors-ligne) s'affiche en clair et reste exporté dans
> `files/mesh_select.txt`. Contrairement au damier V1 global-au-chargement (mort à l'écran : le Loader ne
> ré-uploade jamais le niveau), les bascules V2 agissent **par draw AU MOMENT DU DRAW** via le canal cible
> `mb_target_*` (gfx.h) consulté dans les boucles TFRAG/TIE — preuves runtime par compteurs monotones
> `rt_hidden`/`rt_checker`/`rt_gizmo_*` publiés dans `files/mesh_browser_state.txt`.
>
> **RÉOUVERTURE (2026-07-29, owner : « C'est impossible à parcourir via le tactile (le mesh browser) »)**.
> La ligne de menu elle-même est INCHANGÉE (même id, même position, même comportement) ; c'est le CONTENU de
> l'overlay qui a été refait, parce que le navigateur était inutilisable au doigt sur le seul appareil dont
> l'owner dispose. Trois défauts indépendants, tous corrigés :
> 1. **Aucun événement tactile n'atteignait le navigateur.** L'overlay Android ne transmet un tap
>    (`NativeGk.onMenuTap`) que si `NativeGk.isInMenu()` est vrai — or le navigateur tourne volontairement en
>    `master-mode 'game`. Le chemin était donc mort par construction. Désormais le navigateur lève un drapeau
>    natif (`pc-mb-set-active!`) que l'overlay interroge : tant qu'il est levé, l'overlay SUSPEND la manette
>    virtuelle et transmet le MULTI-TOUCH BRUT (`NativeGk.onBrowserTouch`).
> 2. **Le hit-test était faux d'un facteur 2.** Les lignes étaient normalisées par 448 alors que l'espace de
>    dessin 2D fait `screen-sy` = 224 unités de haut (`draw-sprite2d-xy` borne à `screen-miny..screen-maxy`).
>    Le strip de boutons OBSERVE était pire : dessiné à y=232..248 et x jusqu'à 1090, donc entièrement HORS
>    de l'espace 512×224 — invisible ET intouchable. Tout est maintenant déclaré une seule fois en
>    coordonnées normalisées [0,1] et converti au dernier moment : le rectangle dessiné et la cible tactile
>    sont le même rectangle par construction.
> 3. **Il n'existait aucune donnée de geste.** `pc-get-touch-tap` ne porte qu'un FRONT de tap : ni appui/relâché,
>    ni mouvement, ni second doigt. Un reconnaisseur de gestes réel vit désormais dans
>    `game/kernel/jak1/kmachine.cpp` (`pc_mb_touch_event`), lu une fois par frame par GOAL.
>
> **Gestes (tout au doigt, aucune manette, aucun adb)** — LISTE : glissement vertical = défilement avec
> INERTIE ; poignée de défilement au bord droit = traverse les 3613 entrées de village1 d'un seul geste ;
> tap sur une ligne = sélection directe (pas de curseur à déplacer), re-tap = ouvre ; boutons d'en-tête
> BACK / ALL / FAILING / TFRAG / TIE ; bouton OPEN en pied. OBSERVE : glissement 1 doigt = orbite
> (horizontal = azimut, vertical = ÉLÉVATION, deux axes distincts) ; PINCE = zoom ; glissement 2 doigts =
> FAIT TOURNER LE MESH (la caméra ET la lumière tournent du même angle autour du centroïde : rotation rigide
> de l'objet vis-à-vis des deux, donc l'objet paraît tourner sous une lumière fixe) ; grille de 2×7 boutons
> tactiles : CHECKER/REAL, DISP-, DISP+, REL-, REL+, SPIN-, SPIN+, TOD-, TOD+, DAY, NIGHT, RESET, LIST, EXIT.
> La manette reste en parité complète (d-pad/X/triangle, sticks pour orbite+zoom, L1/R1 spin, etc.).
> En OBSERVE le navigateur PREND la caméra (`*camera-look-through-other*`, le hook cutscene « caméra ICI,
> regardant LÀ ») au lieu d'emprunter `cam-orbit` : `cam-orbit` lit le stick droit directement dans
> `*cpad-list*` et ne stocke qu'un azimut sans terme d'élévation, donc le piloter au doigt reviendrait à lui
> disputer le stick chaque frame. En le possédant, orbite/élévation/zoom sont exactement trois nombres.
> **Robustesse d'accès** : `TouchOverlayView` est désormais TOUJOURS ajouté à la hiérarchie de vues (le
> réglage `touch_overlay_enabled`, dont le défaut est calculé une seule fois au premier lancement et
> persisté, ne supprime plus que le RÔLE manette via `setPadSuppressed`) ; et une manette branchée ne met
> plus la vue en `View.GONE` tant que le navigateur est ouvert (GONE = plus aucun hit-test = plus aucun
> geste). État observable écrit dans `files/mesh_browser_state.txt` (copie-sortie pour l'owner sans adb, et
> preuve falsifiable geste→changement d'état).
>
> **RÉOUVERTURE #2 (2026-07-29, owner : « le warp to model warp toujours au même endroit, et warp le joueur…
> moi je voulais pouvoir tourner en FREE CAM autour dudit mesh (origine au centre du modèle) »)**.
> La ligne de menu reste INCHANGÉE (même id `pc-text-mesh-browser`, même position 23, même `respond-common`) ;
> c'est la sémantique de la SÉLECTION D'UN MESH qui change :
> - **LE JOUEUR N'EST PLUS JAMAIS DÉPLACÉ.** L'ancien code posait `current-continue` puis appelait
>   `(initialize! *game-info* 'die …)`, ce qui fait RÉAPPARAÎTRE Jak au point de continue du niveau —
>   un seul et même endroit par niveau, littéralement le « toujours au même endroit » constaté — puis
>   l'épinglait sur le centroïde chaque frame (`mesh-browser-pin-jak`, SUPPRIMÉ). Plus une seule écriture
>   de position joueur dans le fichier.
> - **Seule la CAMÉRA va au mesh**, sur une sphère d'orbite centrée sur le CENTROÏDE de l'index, distance
>   initiale déduite de la BOÎTE ENGLOBANTE. Valide parce que la visibilité du décor est pilotée par la
>   CAMÉRA et non par le joueur (`update-visible` → `bsp-camera-asm((-> *math-camera* trans))`,
>   `engine/camera/cam-update.gc:84-97`).
> - **Le NIVEAU** (pas le joueur) est demandé quand le mesh vit ailleurs, via le mécanisme de streaming
>   `load-state-want-levels` ; le niveau où se tient Jak est gardé dans le second slot pour que le sol sous
>   lui ne soit jamais déchargé.
> - Le joueur est mis en SOMMEIL (`(process-mask sleep)`, l'idiome moteur) pour qu'il ne s'égare pas hors
>   champ — endormir ne déplace pas. Les boutons du pad sont blanchis après lecture pour que START
>   n'ouvre pas le menu pause par-dessus l'overlay.
> - **Élévation ±89°** (`MB_EL_MIN/MB_EL_MAX`) : on peut regarder un toit à la verticale du dessus ET la
>   face inférieure d'un surplomb à la verticale du dessous. Azimut 360° inchangé.
> - **Le sélecteur de niveau liste désormais les 25 niveaux indexés** (au lieu de 15) et défile avec la même
>   physique tactile que la liste de mesh.
> - Le damier ne re-warpe plus : il re-demande le NIVEAU (le pattern est substitué au chargement de texture,
>   `LoaderStages.cpp:149`), ce qui recharge les textures sans toucher au joueur.
> - `files/mesh_browser_state.txt` porte maintenant `focus=` (centroïde), `cam=` (position réelle de
>   `*math-camera*`), `cam_r=` et `player_moved=` : de quoi prouver, mesh par mesh, que la caméra se centre
>   bien sur CE centroïde-là et que le joueur n'a pas bougé d'un millimètre.

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
