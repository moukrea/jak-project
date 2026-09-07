# SPEC — REFONTE DE L'ÉCLAIRAGE DE JAK 1

> Version 2 · 2026-09-03 · écrite depuis la consigne de l'owner des 2026-09-03.
> Statut : contrat d'ingénierie. Aucun code n'a été modifié pour l'écrire.
> Remplace la version 1 (« plan » de haut niveau) : celle-ci est implémentable sans deviner.

---

## §0 — COMMENT LIRE CE DOCUMENT

### 0.1 Marquage des affirmations

Le harnais interdit de présenter un commentaire comme une preuve. Ce document applique la même
règle à lui-même. Chaque affirmation porte l'un de ces marqueurs :

* **[M]** — **MESURÉ** dans l'arbre `physics-keira-clean` au 2026-09-03. La source est citée
  (fichier, ligne, ou chemin de donnée). Reproductible.
* **[C]** — **CONCEPTION**. C'est une décision de ce document, pas un fait. Elle peut être
  discutée ; elle n'est pas prouvée.
* **[O]** — **OWNER**. Mot pour mot, jamais reformulé, avec sa date.

Un chiffre sans marqueur est une erreur de rédaction : signale-la.

### 0.2 Vocabulaire fixé

| Terme | Sens dans ce document |
|---|---|
| **créneau** | Un des 8 emplacements de `mood-lights-table` / de la palette de couleurs `PackedTimeOfDay`. Les deux sont indexés par le même entier (§3.1). |
| **astre** | Corps céleste visible. Il y en a exactement deux en jak 1 : le **soleil** et la **lune verte** (§3.4). |
| **clé** (lumière clé) | La directionnelle dominante d'un créneau. Ce n'est **pas** toujours un astre (§3.2). |
| **direct** | Lumière qui arrive d'une source identifiée, occultable par une ombre. |
| **indirect** | Tout le reste : rebond, ciel, occlusion. Occultable par l'AO, jamais par une ombre. |
| **régime** | Classe de comportement d'un créneau : clé dure, dôme couvert, ambiante dominante, source basse, ambiante seule. |
| **Éclairage Rechargé** | `recharged_lighting`. **LE maître de cette refonte**, et le seul. Toutes les sous-options d'éclairage vivent dessous. ON par défaut. |
| **ORIGINE-LUMIÈRE** | `recharged_lighting` OFF, master ON. L'éclairage de Naughty Dog, **tout le reste du Recharged conservé** (modèles HD, herbe, textures, HUD). C'est le retour à l'original qu'un JOUEUR veut. |
| **ORIGINE-TOTAL** | `recharged_master` OFF. Le jeu d'origine entier. C'est l'A/B global. |
| **RECHARGED** | master ON + `recharged_lighting` ON. |
| **palette A** | La palette `PackedTimeOfDay` d'origine, dans le fr3. Jamais réécrite. |
| **palette B** | La palette dé-éclairée, dans le compagnon `.lightbake`. |
| **compagnon** | Fichier `<niveau>.lightbake` posé à côté du `.fr3`, sur le patron de `.meshweld`. |

### 0.3 Fichiers de référence

Cette spec cite ces fichiers ; les lire avant d'implémenter n'est pas optionnel.

| Rôle | Chemin |
|---|---|
| Ombrage monde | `game/graphics/opengl_renderer/shaders/{tfrag3,etie_base,tie_wind,shrub,hfrag}.frag` |
| Chunks partagés | `game/graphics/opengl_renderer/shaders/pbr_{uniforms,helpers,fused,modern*}.glsl` |
| Setup d'uniformes | `game/graphics/opengl_renderer/background/background_common.cpp` |
| Ombres actuelles | id. `pbr_shadow_*` (l. 1501-2059) |
| Sonde d'environnement | `game/graphics/opengl_renderer/FollowProbe.{h,cpp}` |
| AO | `game/graphics/opengl_renderer/AmbientOcclusion.{h,cpp}` + `shaders/ao_*.{vert,frag}` |
| Acteurs | `shaders/merc2.{vert,frag}`, `foreground/Merc2.cpp`, `foreground/Shadow2.cpp` |
| Graphe de passes | `game/graphics/opengl_renderer/OpenGLRenderer.cpp` |
| Réglages C++ | `game/graphics/gfx.h` |
| Pont GOAL→C++ | `game/kernel/jak1/kmachine.cpp`, `goal_src/jak1/pc/hud-classes-pc.gc` |
| Menus | `goal_src/jak1/pc/progress-pc.gc` |
| Mood / TOD | `goal_src/jak1/engine/gfx/mood/{mood,mood-tables,time-of-day}.gc` |
| Ciel / astres | `goal_src/jak1/engine/gfx/sky/{sky,sky-h,sky-tng}.gc` |
| Niveaux | `goal_src/jak1/engine/level/level-info.gc` |
| Format fr3 | `common/custom_data/Tfrag3Data.h`, `TFrag3Data.cpp` |
| Patron de compagnon | `common/custom_data/MeshConsolidate.{h,cpp}` |
| Preuve | `.autoport/lib/proof_run.sh`, `.autoport/validators/generic.sh`, `.autoport/lib/backlog.py` |
| **Publicateur de preuve** | `game/system/autoport_proof.{h,cpp}` — **existe déjà**, voir §7.1 |

---

## §1 — CONTRAT

### 1.1 Les quatre règles non négociables

#### Règle 1 — L'ORIGINAL NE DISPARAÎT JAMAIS

**[O] 2026-09-03 :**

> « si on désactive notre option de realtime lighting modernisé des options rechargées, faut
> que l'éclairage original et tout ce qui en découle (l'ombrage, le baked, etc etc d'origine)
> soit toujours là (quand notre refonte est désactivé) dans l'idée ce remake pourra à tout
> moment passer du rendu "original" au rendu "recharged" d'une simple combinaison de touches,
> et les ajouts sont tous tweakables et desactivables individuellement justement pour que les
> joueurs puissent ajuster leurs settings en fonction de leurs préférences/capacités hardware.
> Donc tu réécris pas en dur en supprimant l'original si tu vois ce que je veux dire. »

**[C] Traduction en contraintes vérifiables :**

1. **Deux gestes d'extinction, tous deux légitimes, et il ne faut pas les confondre** (owner,
   2026-09-06) :

   | Geste | Ce qui s'éteint | Ce qui reste |
   |---|---|---|
   | `recharged_lighting` OFF | **toute la refonte lumière** | modèles HD, herbe, textures, HUD, polices — tout le reste du Recharged |
   | `recharged_master` OFF | **tout le projet Recharged** | rien : c'est le jeu de Naughty Dog |
   | une sous-option OFF | cette couche seule | le reste de la refonte |

   Le master n'est PAS l'interrupteur de cette refonte. L'éteindre pour retrouver l'éclairage
   d'origine coûte au joueur ses modèles HD, son herbe et ses textures : ce n'est pas un choix
   qu'on doit lui imposer. Chacun des trois gestes rend un pixel identique à un build sans la
   couche concernée. Pas « proche » : **identique**. Portes en §7.3.
2. **Aucune donnée d'origine n'est réécrite.** Le bake écrit un compagnon **à côté** ; la
   palette A reste dans le fr3, octet pour octet. Un item qui modifierait la palette A échoue.
3. **Chaque ajout a son propre interrupteur**, et son OFF est bit-identique à son absence. Un
   interrupteur dont l'OFF diffère de l'absence est un échec d'item, pas un détail.
4. **Un raccourci bascule le master en jeu**, sans passer par les menus (§6.4).
5. Le mécanisme existe **[M]** (`gfx.h:146` `recharged_master`, `gfx.h:575`
   `Gfx::recharged_active(flag) = flag && recharged_master_active()`). On s'y branche ; on ne
   crée pas un second mécanisme.

#### Règle 2 — MÊMES FONCTIONNALITÉS PARTOUT, LA QUALITÉ EST UN RÉGLAGE

**[O] 2026-07-23** (archive `Grecharged-pbr-realtime-fusion`, rounds 1-25) :

> « NO platform gating — SAME FEATURES on mobile and PC. Quality is a USER setting. »

**[O] 2026-09-03 :**

> « C'est aussi x86/64 sur des machines de fou furieux, des PC bas de gamme, des devices Android
> ultra haut de gamme (genre Snapdragon 8 Elite Gen 5), etc etc. Pas seulement un device pourri
> (le Redmi utilisé pour les tests)... Lui c'est juste un worst case scénario et est utilisé par
> le harnais pour des tests, mais c'est justement là tout le truc cool d'un portage qui peut run
> sur toute sortes de devices, on a des settings qu'on peut tweaker pour que ce soit plus fluide
> ou plus beau en fonction des préférences du joueur et/ou de son matériel. »

**[C] Conséquences :**

* **Aucun `#ifdef __ANDROID__` ne décide d'une fonctionnalité.** Il peut décider d'un défaut de
  palier, jamais de l'existence d'un chemin.
* Les paliers sont des **programmes GLSL compilés** (`#define LIGHT_TIER 0|1|2`), pas des
  branches dynamiques. Justification **[C]** : sur un GPU à ordonnancement large, une branche
  divergente coûte la pression de registres de l'union de toutes ses branches, même non prise.
* Un palier de départ est **déduit** du matériel, puis **entièrement écrasable** par le joueur.

#### Règle 3 — LA STYLISATION PRIME SUR LA PHYSIQUE

**[O] 2026-09-03 :**

> « Pour l'ambiance qui vient du ciel attention avec l'artistic intent... On peut ajuster à tous
> les niveaux pour que ce soit en phase avec les teintes, ombres et lumières du baked qui
> reflète l'artistic intent original en terme d'ambiance (couleurs, température de lumière,
> variations de teintes influencés par le baked, trucs faits de façon subjective, etc.) car
> justement ils ne se sont pas basés sur le ciel uniquement mais y ont mis leur pâte stylisée
> (et le jeu est stylisée donc ça vise pas le réalisme non plus) faut être super smart là
> dessus »

**[C] Traduction :** la STRUCTURE est physique (énergie conservée, unités cohérentes, une seule
fonction d'ombrage). La **direction**, la **teinte** et le **niveau** viennent des tables de
mood de Naughty Dog, jamais d'un modèle de ciel. §5.2 montre que ces deux choses sont
séparables **et mesurables** : la part physique est reconstruite, le reste est le **résidu
artistique**, mesuré et conservé tel quel.

Trois garde-fous numériques, un par item concerné :
* `bake_reconstruction_maxdelta` — la décomposition est inversible (§5.2, item 4).
* `env_amb_tone_delta` — la moyenne de notre ambiante égale `amb-color` du créneau (§4.10, item 5).
* `refset_replay_maxdiff` sur ORIGINE — le point 0 du curseur est le jeu d'origine (§7.3).

#### Règle 4 — L'ORDRE EST IMPOSÉ PAR LES DÉPENDANCES

**[O] 2026-09-03 :**

> « déjà avoir un lighting up to modern standards qui nous permet d'avoir des vrais matériaux
> plutôt que des textures plates c'est un win énorme et ça fera une différence de fou, avec ou
> sans les matériaux... Sachant que les matériaux, PBR et tesselation viendront après car ils
> dépendent du lightning pour être au top »

**[C] Pourquoi c'est mécanique et pas une préférence :** une couleur baked est le produit final
d'un éclairage ; elle ne contient plus de direction de lumière. Une carte de normales module la
réponse d'une surface **à une direction d'éclairage**. S'il n'y a pas de direction, il n'y a
rien à moduler : le seul effet possible est un faux relief teinté à la main. C'est exactement ce
que 25 rounds de `Grecharged-pbr-realtime-fusion` ont vérifié **[M]** (aucun accepté).

### 1.2 Les cinq décisions, tranchées

**[O] 2026-09-03 : « je suis d'accord avec les suggestions sur les décisions ».**

| # | Décision | Ce qui est acté |
|---|---|---|
| 1 | Frontière du mode original | **Deux préréglages nommés** (« Original », « Recharged ») qui posent les cases ; toutes les cases restent accessibles derrière. Pas de troisième mode nommé. |
| 2 | L'aplat PS2 de `shadow-geo` | Il **survit** comme repli hors portée des cascades et comme mode Original. `shadow-geo` reste comme **proxy de profondeur** sur palier bas. Jak n'a **jamais** deux ombres à la fois. |
| 3 | Première livraison | **Quatre niveaux, un par régime** : `village1` (clé dure), `swamp` (dôme couvert), `lavatube` (aucun ciel, source basse), `snow` (ambiante dominante). Les 22 autres en une passe ensuite. |
| 4 | Intensité de la lune verte | **Dérivée du `lgt-color` du créneau de nuit du niveau** — donc de la table de ND — au lieu de la constante 0,40 en dur **[M]** (`background_common.cpp`, `moon_intensity = 0.40f`). Un curseur par-dessus. |
| 5 | Préréglage à la première installation | **Recharged, au palier auto-détecté, sur toutes les plateformes**, avec le mode Original mis en avant dans le menu et le raccourci de bascule. |

### 1.3 Cibles matérielles

**[M]** Mesures du 2026-09-03 et configuration du contexte.

| Classe | Exemple | Contexte | Cadence | Facteur limitant |
|---|---|---|---|---|
| Bureau x86-64 | Linux / Windows | GL **4.3** core (`opengl.cpp:171-173`) | 60 | marge disponible |
| Android très haut de gamme | SD 8 Elite / Adreno 840 | GLES **3.2** | 60 | marge disponible |
| Android entrée de gamme | Redmi Note 9 Pro / Adreno 618 | GLES **3.2** | **19** | **le fil GOAL arm64** |
| macOS | — | GL **4.1** (`opengl.cpp:175`) | — | **pas de compute shader** |

**[M] La mesure qui change la conception.** Cinématique `mayor-introduction` sur le Redmi
`eae4df44` : 1 190 images en 63,4 s (18,8 img/s), `Kernel dispatch time: 55 ms`, **identique
avec les modèles HD allumés (1 226 images, 19,3 img/s) ou éteints**. Ce n'est pas le GPU qui
plafonne, c'est le fil GOAL arm64. Le Honor (Adreno 840) et le bureau x86 sont à 60.

**[C] Règles de conception qui en découlent :**
1. **Rien de nouveau par image sur le fil GOAL.** Le pont GOAL→C++ ne pousse que des scalaires,
   comme aujourd'hui. Tout calcul nouveau vit sur le fil de rendu ou hors ligne.
2. **Le compute shader est un accélérateur optionnel, jamais une dépendance** (macOS = 4.1).
   Chaque chemin qui l'utilise a un repli CPU/fragment mesuré.
3. Un item mesure son coût sur les **trois** classes, au même point de vue, avec les deux bras.

### 1.4 Hors périmètre

* **Le ray tracing.** Optionnel et minoritaire dans les jeux actuels, hors de ce chantier,
  aucune ligne de code, rien à prévoir. Seule remarque : ce plan sépare direct et indirect pour
  ses propres raisons (§5.2), donc la question resterait ouverte plus tard sans rien à défaire.
* **Vulkan** (`OG_FEAT_VULKAN_SUPPORT`, OFF **[M]**) : autre chantier.
* **Jak 2 et Jak 3.** Le code partagé ne doit pas régresser ; rien n'est ajouté pour eux.
* **Les matières, le PBR, la tessellation** avant l'item 10 : c'est l'inversion que la règle 4
  interdit. La tessellation et le displacement existants sont **ré-hébergés tels quels**, pas
  retravaillés.
* **Les sources traduites de Naughty Dog ne se réécrivent pas.** On LIT `mood.gc`,
  `mood-tables.gc`, `sky.gc`, `time-of-day.gc`, `level-info.gc`, `bones.gc`. Notre code GOAL
  ajouté vit sous `goal_src/jak1/pc/`.
* **Le reciblage des modèles HD**, la chaîne d'assets rechargés, la soudure des maillages : tous
  validés, tous intouchés.

---

## §2 — ÉTAT DES LIEUX

### 2.1 Ce que le substrat Naughty Dog contient déjà

**[M] Le baked est une base de 8 fonctions, pas une couleur.**
Chaque sommet de `tfrag`/`TIE`/`shrub`/`hfrag` porte un `color_index` (u16) dans une palette de
8 entrées (`Tfrag3Data.h:312` `PackedTimeOfDay`, `read(color, palette, channel)`).
`interp_time_of_day()` (`background_common.cpp:3234`, SSE) calcule `Σ wᵢ · paletteᵢ` avec un
poids **par canal**, et le résultat est uploadé dans une texture **8192×1 RGBA8**
(`TFragment.cpp:525`), lue par `texelFetch(ivec2(i,0))` dans le vertex shader. Il y a un
ping-pong à deux textures (`time_of_day_texture` / `_pp`).

Conséquence de dimensionnement **[M]** : `TIME_OF_DAY_COLOR_COUNT = 8192`
(`TFragment.h:204`, `Tie3.h:188`, `Shrub.h:102`, `Hfrag.h:70`), 32 octets par entrée
⇒ **256 Ko par arbre au maximum**. Une seconde palette complète coûte donc au pire 256 Ko par
arbre, et une grandeur scalaire par index de couleur (visibilité, AO) coûte 8 Ko.

**[M] Les sommets portent déjà normale et tangente.**
`PreloadedVertex.nor` (2-10-10-10 empaqueté), `PackedTieVertices::Vertex.{nx,ny,nz}` (s8),
`ShrubGpuVertex.nor`, et `TfragTree::baked_tangents` / `TieTree::baked_tangents`
(`TFRAG3_VERSION = 44`, « Gprecompute-deterministic-bake — baked per-vertex tangents »).
Les maillages sont soudés et orientés hors ligne (`.meshweld`, `kBakeVersion = 9`).
**C'est la fondation géométrique du bake : elle est déjà là et validée par l'owner.**

**[M] Le jeu connaît ses zones intérieures.**
`update-mood-village1` (`mood.gc:761`) porte **sept ancres avec rayon** — les sept huttes de
Sandover — et bascule `(-> *target* draw light-index)` sur 1..7 selon la distance, avec un
`target-interp` continu. Chaque entité du niveau porte un `light-index` dans son res-lump
(`process-drawable.gc:390`). `drawable.gc:479-527` choisit et interpole le `light-group`.

**[M] Le jeu nomme ses émetteurs.**
Recensement TIE des 24 DGO : **1 191 lignes** (niveau × arbre × proto), **951 noms distincts**,
**44 415 instances**. En cherchant les jetons `light, lite, lamp, lant, torch, glow, flame,
candle, brazier, spotlight, neon` : **62 prototypes candidats, 1 192 instances**, dont
**16 jumeaux `-glow.mb`** (307 instances) — les surfaces émissives authorées par ND. Liste
complète en annexe C. Faux amis inclus, volontairement (`palmplant-base.mb` contient « lant ») :
c'est pour ça que le lexique exige un verdict explicite par nom.

**[M] Le jeu anime ses sources.**
`update-mood-flames` (`mood.gc:348`) fait vaciller `times[slot].w` avec un tirage aléatoire de
durée et d'amplitude ; `update-mood-lightning` (`:446`) joue des tables `*flash0..7*` ;
`update-mood-light` (`:550`), `update-mood-lava` (`:580`), `update-mood-caustics` (`:605`).
À Sandover c'est **le créneau 5** (`update-mood-flames arg0 5 1 0 0.5 0.001953125 1.0`).

### 2.2 Nos couches : inventaire chiffré

**[M]** Tout sous `#ifdef OG_PBR` / `OG_FEAT_PBR` (ON dans `build/` et `build-android/`).

| Grandeur | Valeur |
|---|---|
| Lignes de shading monde | **4 106** : `tfrag3.frag` 1111, `etie_base.frag` 645, `shrub.frag` 644, `tie_wind.frag` 642, `pbr_fused.glsl` 818, `pbr_uniforms.glsl` 242 |
| Déclarations d'uniformes dans l'étage fragment monde | **94** : 79 scalaires/vecteurs/matrices + 15 samplers |
| Chemins d'ombrage exclusifs | **5** |
| Dont morts à l'exécution | **2** |
| Samplers dans l'étage fragment | **15** (plafond GLES 3.2 : 16) |
| Dont liés à une texture noire 1×1 | **4** (`u_rt_probe_dc/l1a/l1b/l1c`) |
| Bits de bissection A/B | **~35**, deux banques (`u_pbr_bisect`, `u_pbr_bisect2`) |
| Propriétés de debug Android | **131** |
| Variables d'environnement `OG_*` | **79** |
| Cascades d'ombre | **1**, `DEPTH_COMPONENT16`, demi-étendue 150 m par défaut |
| Lumières ponctuelles | **0** |
| Classes d'objets projetant une ombre | **3** (tfrag, tie, shrub) — **pas les acteurs** |
| Format du framebuffer monde | **RGBA8** (`OpenGLRenderer.cpp:929/933`) |
| Sites de tone map | **6** `pow(1/2.2)` + un genou maison `RT_KNEE = 0.8` par chemin |
| `recharged_rt_light_enable` par défaut | **false** |
| `recharged_ao_mode` par défaut | **0** (éteint) |

### 2.3 Les six causes structurelles

**Cause 1 — Il n'y a pas un modèle d'éclairage, il y en a cinq, et ils se contredisent. [M]**

Le chemin pris par un fragment du décor dépend de quatre booléens :

| Condition | Chemin | Composite |
|---|---|---|
| `u_rt_light_on != 0` et `u_pbr_mode != 0` | B · PBR fusionné | `pbr_fused.glsl` : GGX + baked linéarisé + split-sum |
| `u_rt_light_on != 0` et `u_pbr_mode == 0` et `u_rt_probe_on == 0` | A · modulation du baked | `color.rgb *= mix(shd_mul, lit_mul, lit)` |
| `u_rt_light_on != 0` et `u_rt_probe_on != 0` | D · composite à sondes | **MORT** |
| `u_rt_light_on == 0` et `u_pbr_mode != 0` | C · PBR autonome | quasi-copie de B, autre composite |
| sinon, `u_pbr_shadow_on != 0` | E · relight legacy | 3ᵉ modèle N·L, normale par dérivée d'écran |

Trois espaces colorimétriques, trois définitions de « éclairé », trois tone maps. Toucher à un
chemin casse silencieusement l'A/B des autres. C'est la mécanique qui a produit 25 rounds non
acceptés.

**Cause 2 — Le baked sert à la fois de réponse et de référence. [M]**

Le seul chemin validé fait, dans `tfrag3.frag` :

```glsl
vec3 rt_mod = mix(vec3(1.0), mod_y, w_y) * mix(vec3(1.0), mod_g, w_g);
color.rgb = max(color.rgb * rt_mod, vec3(0.0));
```

Le soleil ne s'ajoute pas : il **teinte** ce que le bake a décidé. Il ne peut donc **jamais**
éclairer ce que le bake a laissé sombre. Au-delà de la distance d'ombre, `color = mix(sun_disp,
baked_disp, far_t)` refond vers le baked brut.

C'est la cause racine de **[O] 2026-07-19 : « moins beau que du baked »**. Toute la calibration
qui a suivi n'existe que pour rattraper la double-dose que cette structure fabrique **[M]** :
`u_pbr_direct = 0.3f`, `u_rt_lit_boost = 1.15f`, `u_rt_shadow_mul = 0.65f`,
`u_rt_sun_boost = 0.25f`, `RT_PROBE_IND = 0.45`, `u_rt_detail_norm`, `ind_k`, et une EMA de
lissage de bascule à `alpha = 0.10`.

**Cause 3 — Une seule scène a servi d'étalon : Sandover en plein jour. [M]** Voir §3.3.

**Cause 4 — Les acteurs sont hors du système, et leur ombre est un décalque PS2. [M]** Voir §3.5.

**Cause 5 — L'ambiante et les reflets sont inventés, pas mesurés. [M]**

`FollowProbe::eval_env` (`FollowProbe.cpp:95`) évalue **au CPU** :
`band = mix(horizon, zenith, smoothstep(dir.y)) ; e = band + sun_glow * pow(dot(dir,L), 4)`,
écrit le résultat par `glTexSubImage2D` face par face, et appelle `glGenerateMipmap` **à chaque
image**. Aucun élément du monde n'apparaît jamais dans un reflet. Pendant ce temps
`mood-lights-table[i].amb-color` — la vraie ambiante art-dirigée — est là, en clair, ignorée.

**Cause 6 — Tout est en LDR, donc rien ne peut claquer. [M]**

`make_fbo(..., GL_RGBA8, ...)`, `pow(1/2.2)` dans six shaders, plus par chemin :
`e = exp(-max(lit - 0.8, 0) / 0.2) ; lit = mix(lit, 1 - 0.2*e, step(0.8, lit))`.
Aucune marge au-dessus de 1 : un éclat spéculaire, un bloom, une adaptation d'exposition n'ont
physiquement pas la place d'exister.

### 2.4 Le code mort à retirer (inventaire exact)

**[M]** `FollowProbe::update_and_bind` exécute inconditionnellement
`glUniform1i(loc("u_rt_probe_on"), 0)` et lie `m_dummy_3d` (RGBA8 1×1×1 noir) sur les unités
4-7. Donc **ne s'exécutent jamais** :

| Élément | Fichier | Taille approx. |
|---|---|---|
| `rt_probe_sh()` + la boucle de confinement à 8 coins `texelFetch` | `tfrag3.frag` | ~60 lignes |
| `rt_probe_eval()` | `tfrag3.frag` | ~8 lignes |
| Branche « BAKED AMBIENT curiosity » (`u_rt_probe_on != 0`) | `tfrag3.frag` + 3 copies | ~150 × 4 lignes |
| **Tous** les sites de lecture de `u_rt_probe_cube` — voir D.2 | 5 shaders | 6 sites |
| Uniformes `u_rt_probe_{origin,inv_cell,dims,range}` | `pbr_uniforms.glsl` | 4 |
| Samplers `u_rt_probe_{dc,l1a,l1b,l1c}` | `pbr_uniforms.glsl` | **4 unités de texture** |
| Uniformes `u_rt_{sh[9],env_zenith,env_horizon,env_ground,sun_glow}` | `pbr_uniforms.glsl` | 5 |
| Uniformes `u_rt_{sky_color,ground_color,ambient_model,ambient_key,ambient_contrast,flat_normal}` | id. | 6 |

**Nuance, pour ne pas surestimer.** `rt_sh_ambient()` et `rt_ibl_ambient()` ne sont PAS morts :
ils sont inatteignables sur le chemin A (celui que l'owner a validé) mais **atteignables** depuis
`pbr_fused.glsl` (`rt_amb_eval`, `fenv_sharp`), donc sur tout draw qui porte des cartes PBR. Ils
ne sont pas supprimés comme du code mort : ils sont **remplacés** par l'environnement mesuré du
§4.10, ce qui est un changement de comportement assumé et porté par l'item 5.

**En revanche, une chose est bien morte et elle coûte à chaque image.** Tous les sites de lecture
du cube de `FollowProbe` sont gardés par `u_rt_probe_on != 0` **[M]** :

| Site | Garde |
|---|---|
| `pbr_fused.glsl:733` | `if (u_rt_probe_on != 0 && u_rt_probe_reflections != 0)` |
| `tfrag3.frag:961` | idem |
| `tfrag3.frag:540`, `etie_base.frag:475`, `shrub.frag:475`, `tie_wind.frag:474` | dans la branche « BAKED AMBIENT », qui exige `u_rt_probe_on != 0` |

Et `FollowProbe::update_and_bind` écrit `glUniform1i(loc("u_rt_probe_on"), 0)`
**inconditionnellement, sur chaque draw**. Donc :

> **Le cube de `FollowProbe` n'est lu par aucun shader.** La classe rastérise pourtant 6 faces
> au CPU (32² à 128² selon le palier, `recharged_follow_probe = 1` par défaut **[M]**), pousse une
> face par image par `glTexSubImage2D`, et appelle `glGenerateMipmap(GL_TEXTURE_CUBE_MAP)`
> **à chaque image**, pour une texture que personne n'échantillonne.

Trois des commentaires du code le disaient déjà sans en tirer la conséquence :
`etie_base.frag:589`, `shrub.frag:589`, `tie_wind.frag:588` portent « *u_rt_probe_cube stays
declared but unused* ».

Retirer ce qui est listé ci-dessus n'est **pas** un changement de comportement : c'est du texte
qui n'exécute pas, plus un travail par image dont le résultat n'est lu par personne. La porte de
l'item 1 (`refpix` à diff nul sur les deux références) le prouve, et l'item 1 doit publier
`gpu_ms_followprobe` avant/après pour chiffrer ce qui est récupéré.

---

## §3 — CE QUE LA DONNÉE DU JEU DIT

### 3.1 La découverte fondatrice : créneau du bake = créneau de lumière

**[M]** `update-mood-palette` (`mood.gc:146`) fait, pour l'heure courante :

```
v1-7   = palette-interp.hour[heure]        ; snapshot1, snapshot2, morph-start/end
s3-0   = v1-7.snapshot1                    ; créneau A
s2-0   = v1-7.snapshot2                    ; créneau B
f30-0  = lerp(morph-start, morph-end, frac(heure))

times[s3-0].w = (64 - round(64*f30)) / 64  ; ← POIDS DE LA PALETTE DE SOMMETS
times[s2-0].w =        round(64*f30)  / 64 ; ←

light-group[0].dir0 = { direction = mood-lights[s3-0].direction,
                        color     = mood-lights[s3-0].lgt-color,
                        levels.x  = 1 - f30 }
light-group[0].dir1 = { direction = mood-lights[s2-0].direction,
                        color     = mood-lights[s2-0].lgt-color,
                        levels.x  = f30 }
light-group[0].ambi.color = lerp(mood-lights[s3-0].amb-color,
                                 mood-lights[s2-0].amb-color, f30)
current-shadow = lerp(mood-lights[s3-0].shadow, mood-lights[s2-0].shadow, f30)
```

Puis `update-mood-itimes` (`mood.gc:30`) transforme `times[i].xyz * times[i].w` en `itimes`,
et `interp_time_of_day` applique ces poids **par canal** à la palette de couleurs.

**Conclusion, et c'est le pivot de toute la spec :**

> **La lumière qui a produit l'entrée `i` de la palette baked est `mood-lights-table[i]`, et on
> l'a en clair : `direction`, `lgt-color`, `amb-color`, `shadow`.**

Le bake et le light-group sont **le même objet**, lu deux fois. La décomposition (§5.2) n'a donc
rien à estimer : elle a une forme close.

Corollaire **[M]** : `levels.y` porte `2R + 4G + B` de `lgt-color`, la pondération luminance que
le moteur utilise déjà pour trier ses lumières. C'est celle que cette spec emploie partout.

### 3.2 Les régimes lumineux, mesurés

**[M]** Extrait de `mood-tables.gc`, 17 tables, 62 créneaux non vides. Table complète en
annexe A. Classification **[C]**, seuils explicites :

| Régime | Critère | Comportement attendu du direct |
|---|---|---|
| **clé dure** | `lgt/amb > 3` | l'astre porte ; pénombre étroite ; contraste plein ; spéculaire net |
| **dôme couvert** | `élévation > 0,85` **et** chroma neutre (`max|R−G|,|G−B| < 0,06`) | la clé EST le ciel ; pénombre très large ; contraste écrasé ; pas de spéculaire net |
| **ambiante dominante** | `lgt/amb < 1` | la clé devient un léger gradient ; les lumières locales portent la scène |
| **source basse** | `élévation < −0,2` | source sous les pieds (lave) ; ombres portées vers le HAUT ; pas de ciel |
| **ambiante seule** | `lgt ≈ 0` | aucune directionnelle ; tout est indirect + locales |
| **source pure** | `amb == 0` et élévation ≥ 0 | éclair / flash : directionnelle sans ambiante, transitoire |

Les cas qui sortent de l'hypothèse « il y a un soleil » — et qui sont donc les cas que le moteur
actuel traite mal :

| Table | Créneau | Élévation | `lgt` | `amb` | l/a | Régime |
|---|---|---|---|---|---|---|
| `misty` | 1 | 0,933 | 0,88 gris | 0,374 | 2,34 | **dôme couvert** |
| `swamp` | 1 | 0,933 | 0,82 gris | 0,374 | 2,21 | **dôme couvert** |
| `village2` | 1 | 0,933 | 0,79 gris | 0,374 | 2,12 | **dôme couvert** |
| `ogre2` | 1, 2 | 0,933 | 0,79 gris | 0,374 | 2,12 | **dôme couvert** |
| `rolling` | 2 | 0,908 | 0,91 gris | 0,359 | 2,50 | **dôme couvert** |
| `lavatube` | 2..7 | **−1,000** | 1,00 0,36 0,00 | 0,000 | ∞ | **source basse** (lave) |
| `firecanyon` | 5 | **−1,000** | 1,00 0,36 0,00 | 0,000 | ∞ | **source basse** (lave) |
| `darkcave` | 1 | **−1,000** | 0,30 0,40 0,50 | 0,386 | 1,00 | **source basse** |
| `village3` | 1 | 0,250 | **0,00** | 0,414 | 0,00 | **ambiante seule** |
| `snow` | 2 | 0,966 | 0,66 0,44 0,29 | 0,36 0,57 0,72 | 0,90 | **ambiante dominante** |
| `sunken` | 1, 2 | 1,000 | 0,27..0,17 | 0,374..0,446 | 0,99 / 0,44 | **ambiante dominante** |

**[O] 2026-09-03 :**

> « Il y a aussi des niveaux et/zones ou le ciel n'est pas visible (tunels, overcast) come le
> lava tube ou le niveau de swamp par example, ou encore la tour de goal et Maia, et j'en
> passe. Dans le cas de ciels overcast (ie. Swamp level) la lumière est diffusée par le ciel,
> pas le soleil car il n'y est pas vraiment visible (encore une fois, c'est un truc qu'on peut
> observer dans la vraie vie). C'est à considérér ! Dans ces niveau et environnements
> (intérieurs, ciels overcast de nuit, etc.) les sources de lumière en sus du soleil/lune sont
> d'autant plus importantes à valoriser. »

La table dit exactement ça, et le confirme au-delà : **cinq tables** sont en dôme couvert (pas
seulement `swamp`), et la tour de Gol et Maia (`ogre`, `ogre2`, `ogre3`) en fait partie.

### 3.3 Ciel et soleil visible, par niveau

**[M]** `level-load-info` (`level-h.gc:95`) porte `sky : symbol` et `sun-fade : float`.
Table complète en annexe B. Synthèse :

| Situation | Niveaux | Nombre |
|---|---|---|
| `sky = #f` — **aucun ciel** | `citadel`, `darkcave`, `jungleb`, `lavatube`, `maincave`, `robocave`, `sunken` (+ `demo`, `intro`, `title`) | **7** de jeu |
| `sky = #t`, `sun-fade = 0` — **le sprite du soleil n'apparaît jamais** | `swamp`, `village2`, `village3`, `firecanyon`, `ogre`, `rolling`, `sunkenb` | **7** |
| `sun-fade < 1` — **voilé** | `misty` 0,25 · `snow` 0,5 | **2** |
| `sun-fade = 1` — **plein soleil** | `village1`, `beach`, `jungle`, `training`, `test-zone`, `finalboss`, `halfpipe` | **7** |

**[M]** `sun-fade` est mutable à l'exécution (`mood.gc:1677` et `:1688` l'écrivent pour
`citadel`) et il gouverne l'apparition des DEUX sprites d'astre (`time-of-day.gc:45` et `:52`,
condition `(!= (-> *time-of-day-context* sun-fade) 0.0)`). `weather-part.gc:469` le lit aussi.

#### Le défaut que ça révèle **[M]**

```
goal_src/jak1/pc/hud-classes-pc.gc:1766     ; SANS AUCUNE GARDE
    (pc-set-pbr-sky-sun! (-> *sky-parms* upload-data sun 0 pos))

game/graphics/opengl_renderer/background/background_common.cpp
    const float* ss = gs.recharged_pbr_sky_sun;
    float ssl = sqrt(...);
    if (ssl > 1e-3f && ss[1] / ssl > 0.02f) {
      light_dir[0] = ss[0]/ssl; light_dir[1] = ss[1]/ssl; light_dir[2] = ss[2]/ssl;
    }                                        // ← ÉCRASE la clé du créneau
```

Donc dans les 7 niveaux sans ciel, les 7 sans sprite de soleil, et les 2 voilés — **16 niveaux
sur 20 de jeu** — la direction de la lumière du monde est celle d'un soleil que le joueur ne
voit pas, et qui n'est pas la clé de la scène. Le seul régime pour lequel le moteur actuel est
calibré est « clé dure », mesuré à Sandover en plein jour.

### 3.4 Les deux astres

**[M]** `sky.gc` définit trois orbites, `sky-make-sun-data` / `sky-make-moon-data` les évaluent :

```
pos.y = dist · cos(2π (t − high_noon) / 24) · cos(tilt)
```

| Orbite | Nom dans le code | `high-noon` | `tilt` | `rise` | `dist` | Sprite affiché en jak 1 ? |
|---|---|---|---|---|---|---|
| 0 | soleil | 12,5 | −15° | 0° | 9950 | **oui** (`time-of-day.gc:45`, 6 h 25 → 18 h 45) |
| 1 | « green sun » = **la lune verte** | 4,0 | 0° | 60° | 9950 | **oui** (`:52`, ≥ 21 h 45 ou ≤ 10 h 15) |
| 2 | « moon » | 0,0 | 0° | −10° | 9950 | **NON — jamais spawné** |

Couleur de la lune verte **[M]** : `sky-set-sun-colors *sky-parms* 1` = `#xc2 #xfe #x78`
= (194, 254, 120) = (0,761, 0,996, 0,471).

**Deux conclusions :**

1. **Il y a exactement deux astres à l'écran.** L'orbite 2 est calculée par `update-sky-tng-data`
   mais aucun `spawn` ne la dessine. **La terminologie de l'owner est la bonne** : ce que le code
   appelle « green sun » est la lune. Cette spec dit **soleil** et **lune verte**.
2. **Ils cohabitent 3 h 30 par jour.** Élévations : soleil positif pour `6,5 < t < 18,5` ; lune
   verte positive pour `t > 22` ou `t < 10`. Chevauchement : **6 h 30 → 10 h**. Les fenêtres de
   sprite confirment : **6 h 25 → 10 h 15**. Et il y a une fenêtre symétrique **sans aucun
   astre** : 18 h 45 → 21 h 45.

**[O] 2026-09-03 :**

> « Ce que j'appelle la lune c'est ton soleil vert... Comme dans la vraie vie, on a le soleil qui
> émet de la lumière et la lune qui en émet aussi [...] et quand les deux overlap... Bah ça doit
> être pris en compte, ça l'est pour nous aussi quand on a la lune et le soleil visibles en même
> temps ! »

**[M] Le moteur actuel est bâti sur la prémisse inverse.** Commentaire de
`background_common.cpp`, attempt-9 : « *the "overlap crossfade" it aimed for does not exist
because the two suns are ANTIPHASE with a dark twilight GAP (never both up at once)* ». C'est
**faux**. Toute la machinerie construite dessus — une seule carte d'ombre attribuée au plus haut,
`u_rt_shadow_conf` (fondu de confiance `smoothstep(0.05, 0.30, owning_up)`), l'EMA de lissage
`alpha = 0.10` sur trois scalaires, les poids d'orientation d'ambiante `ambW_y/ambW_g` — existe
pour masquer une bascule qui n'a pas lieu d'être : il suffit de deux lumières et deux ombres.

### 3.5 Les acteurs

**[O] 2026-09-03 :**

> « Les acteurs je sais que leur lighting est faked, faut plus que ce soit le cas ! Et
> d'ailleurs, l'ombre que cast Jak, ennemies et PNJ est très bizarre, on dirait une version
> ultra low poly projeté sur le sol, c'est pas la bonne méthode pour un truc modern, c'est à
> reprendre aussi et intégrer dans le reste évidemment. »

**[M] Éclairage.** `merc2.vert` :

```glsl
rotated_nrm = normalize(Σ bones[matsᵏ].R * normal_in * weightsᵏ);
vec3 light_intensity = light_dir0_fade.xyz * rotated_nrm.x
                     + light_dir1_fade_en.xyz * rotated_nrm.y
                     + light_dir2       * rotated_nrm.z;
light_intensity = max(light_intensity, vec3(0));
vec4 light_color = light_ambient + Σ light_intensity[i] * light_col[i];
```

`merc2.frag` ne fait ensuite que `color = vtx_color * T0 * 2.0`. Donc : **par sommet**, trois
directionnelles + une ambiante issues de `vu-lights` (`lights-h.gc`), **aucune** normale par
pixel, **aucune** réception d'ombre, **aucune** AO, **aucune** ambiante partagée avec le décor.
Le shader ne déclare même pas de sampler d'ombre.

**[M] Ombre.** Le mécanisme complet :

1. Chaque modèle porte un maillage d'ombre **séparé et authoré** : `shadow-geo`
   (`shadow-cpu.gc:14`), accroché à `(-> arg0 shadow-joint-index)` (`bones.gc:721`).
2. `shadow-control::collide-to-find-planes` (`shadow-cpu-h.gc:49`) trouve par collision un
   `bot-plane` et un `top-plane` (`shadow-settings`, `shadow-cpu-h.gc:25`).
3. `draw-bones-shadow` (`bones.gc:676`) empile le paquet DMA ; `Shadow2.cpp` le lit :
   `kTopVertexDataAddr = 4`, `kBottomVertexDataAddr = 174`, `kCapIndexDataAddr = 344`,
   `kWallIndexDataAddr = 600` — **115 sommets haut + 115 sommets bas**, `top_vertex_data`
   commentée « always 115 ».
4. Le volume est extrudé entre les deux plans, rendu en **volume de stencil**, puis un aplat
   sombre est peint là où le stencil est non nul (bucket `SHADOW = 47`, `INCR/DECR` depuis 0,
   dessin où `NOTEQUAL 0`).
5. `fade-dist` / `fade-start` coupent le dessin au loin (`shadow-flags disable-draw`).

C'est de la technique PS2 : pas de pénombre, pas de contact, pas de silhouette réelle, un aplat
uniforme. Le constat de l'owner est exact au sens littéral.

---

## §4 — ARCHITECTURE D'EXÉCUTION

### 4.1 Le graphe de passes, image par image

**[C]** Deux graphes, sélectionnés par `Gfx::recharged_master_active()` au sommet de la frame.

```
     ┌── master OFF, ou `recharged_lighting` OFF ──►  GRAPHE ORIGINE (inchangé, LDR, RGBA8)
                       │                   sky · tfrag · tie · shrub · merc · alpha ·
  début de frame ──────┤                   SHADOW(47) aplat stencil · sprite · UI
                       │                   AUCUNE de nos passes n'est créée
                       │
                       └── master ON  ──►  GRAPHE RECHARGED
```

Graphe RECHARGED, dans l'ordre d'exécution :

| # | Passe | Écrit | Lit | Palier min. |
|---|---|---|---|---|
| P0 | Interpolation de palette (CPU/SIMD, existante) | texture TOD 8192×1 (**palette B**) | `.lightbake` | toujours |
| P1 | **Prépasse** opaque monde + acteurs | `depth`, `RG16F` normale octaédrique + `R8` rugosité | géométrie | toujours |
| P2 | **Atlas d'ombres** — N tuiles, N passes de profondeur | `depth` atlas | géométrie + acteurs | toujours |
| P3 | **Capture d'environnement** (amortie, 1 face / n frames) | cube RGBA16F + SH L2 | dôme de ciel réel | tier ≥ 1 |
| P4 | **AO** (SSAO/HBAO/GTAO existants, cible modifiée) | `R8` texture d'AO | P1 | tier ≥ 1 |
| P5 | **Grille de clusters** (fil de rendu, CPU ou compute) | UBO lumières + texture d'index | liste d'émetteurs | toujours |
| P6 | **Ombrage forward** — TOUS les renderers via `shade()` | `RGBA16F` scène | P1..P5 + palette B | toujours |
| P7 | **Ombres de contact** (fusionnées dans P6, pas une passe) | — | P1 | tier ≥ 1 |
| P8 | Effets écran optionnels (bloom, SSR — **plus tard**) | `RGBA16F` | P6, P1 | — |
| P9 | **Tone map + exposition**, site unique | `RGBA8` | P6/P8 | toujours |
| P10 | UI, sprites, debug (inchangé, LDR) | `RGBA8` | — | toujours |

**[C] Points d'insertion dans le code existant :**
* P1/P2/P3/P5 s'ordonnancent dans `OpenGLRenderer::render` avant le premier bucket monde
  (aujourd'hui `BucketId::SKY_DRAW = 3`), pas dans un bucket : ce ne sont pas des consommateurs
  de DMA GOAL.
* P4 remplace l'insertion actuelle de `m_ao_pass.render(...)` (`OpenGLRenderer.cpp:1608`, après
  l'opaque) : la passe **monte** avant l'ombrage et cesse de composer sur l'image.
* P9 remplace les six `pow(1/2.2)` et s'insère au resolve, avant `begin_ui_pass()`.
* Le bucket `SHADOW = 47` (aplat PS2) est **conservé**. Il est sauté par draw quand la vraie
  ombre de cet acteur est dans l'atlas (décision 2, §1.2), jamais désactivé globalement.

### 4.2 `shade()` — l'interface exacte

**[C]** Un chunk `shaders/lighting/shade.glsl`, inclus par `#include "lighting/shade.glsl"`.
Le mécanisme d'include existe **[M]** (`Shader.cpp:129-180`, expansion verbatim, profondeur max
4, table `kChunks` côté Android, expansion **avant** `subst_tokens` et l'injection de `OG_PBR`).

```glsl
// ============================ CONTRAT ============================
// Un renderer REMPLIT Surface et APPELLE shade(). Il ne décide de rien d'autre.
// Tout ce qui n'est pas dans Surface vient des uniformes/UBO de §4.3 : les
// lumières, l'environnement, les ombres, la grille de clusters, les paliers.
// shade() ne lit AUCUN varying directement : c'est ce qui permet à merc, à
// l'herbe et à l'océan de l'appeler sans avoir les varyings du décor.
// =================================================================

struct Surface {
  // --- géométrie, espace MONDE ---
  vec3  P_rel;        // position relative caméra, MÈTRES (== l'actuel v_fringe_rel)
  vec3  P_world;      // position absolue, unités de jeu (== l'actuel v_world)
  vec3  N;            // normale de surface, unitaire, orientée vers l'extérieur
  vec4  T;            // tangente MikkTSpace : xyz monde, w = sens (±1)
  vec3  V;            // surface -> œil, unitaire ( = normalize(-P_rel) )

  // --- apparence ---
  vec2  uv;           // UV de la couleur de base, APRÈS parallaxe si applicable
  vec3  albedo;       // linéaire, déjà dé-gamma
  float alpha;        // pour le discard, hors du modèle d'éclairage

  // --- indirect cuit (palette B + compagnon) ---
  vec3  indirect;     // linéaire. C'est Σ wᵢ·indirectᵢ, PAS le baked d'origine.
  float sky_vis;      // 0..1, visibilité cosinus-pondérée du ciel (cuite)
  vec3  bent_N;       // normale coudée cuite (direction moyenne non occultée)
  float ao_baked;     // 0..1, AO statique cuite

  // --- matière ---
  float roughness;    // perceptuelle, clampée [0.045, 1]
  float metallic;
  vec3  f0;           // réflectance spéculaire à incidence normale
  float ao_map;       // 0..1, carte _ao / _orm.r ; 1 si absente
  vec3  emissive;     // linéaire, s'ajoute sans être éclairé
  float thickness;    // 0..1, diffusion sous-surface ; 0 = opaque (palier ≥ 2)

  // --- contexte de draw ---
  int   flags;        // SURF_* ci-dessous
  float screen_ao;    // 0..1, AO d'écran échantillonnée par le renderer en P4
};

const int SURF_TWO_SIDED   = 1;   // feuillage, herbe : N re-signée vers la caméra
const int SURF_NO_SHADOW   = 2;   // ne reçoit pas d'ombre (ciel, effets)
const int SURF_SKIN        = 4;   // acteur : autorise le SSS et le biais de contact
const int SURF_WATER       = 8;   // eau : réflexion spéculaire dominante
const int SURF_NO_INDIRECT = 16;  // pas de palette (merc) : indirect vient des sondes

// Sortie : radiance LINÉAIRE, non tone-mappée, non fogged.
// Le brouillard et le discard restent au renderer : ils ne sont pas de l'éclairage.
vec3 shade(in Surface s);
```

**[C] Contrat de composition, dans l'ordre exact où `shade()` l'exécute :**

```
1. N_shading  = perturbe(s.N, normal map, TBN(s.N, s.T))         // matière
2. occ_spec   = specular_occlusion(s.ao_map * s.ao_baked, roughness, N·V)
3. ao_total   = s.screen_ao * s.ao_map * s.ao_baked              // JAMAIS le direct
4. E_ind      = s.indirect                                       // cuit, art compris
              + env_diffuse(bent_N ou N) * s.sky_vis             // ciel mesuré, si tier ≥ 1
5. L_diffuse  = albedo/π * E_ind * ao_total
6. L_spec_ind = env_specular(reflect(-V, N_shading), roughness) * split_sum(f0, rough, N·V)
                * occ_spec
7. pour chaque astre a ∈ {soleil, lune verte} avec poids_a > 0 :
     vis_a   = shadow_atlas(a, P_rel) * contact_shadow(P_rel, L_a)
     L_dir  += BRDF(N_shading, V, L_a, matière) * couleur_a * (N·L_a) * vis_a * régime_a
8. pour chaque lumière locale l du cluster de ce fragment :
     att     = atténuation_physique(dist, radius_l) * cone(l)
     vis_l   = contact_shadow(P_rel, L_l)        // pas de carte d'ombre par lumière
     L_dir  += BRDF(...) * couleur_l * (N·L_l) * att * vis_l
9. return L_diffuse + L_spec_ind + L_dir + s.emissive
```

**[C] Invariants que `shade()` garantit, et qui sont testables :**

| Invariant | Conséquence |
|---|---|
| L'AO n'apparaît qu'aux lignes 3-6. | La lumière directe n'est **jamais** multipliée par l'AO. Porte de l'item 3. |
| `s.indirect` n'est jamais multiplié par une visibilité d'ombre. | Une ombre portée ne peut pas éteindre le rebond. |
| Si toutes les lumières ont un poids nul, `shade()` rend `albedo/π · s.indirect · ao_total` (+ émissif). | Avec AO à 1 et `env` à 0, c'est le produit d'origine. Base de la porte de l'item 4. |
| Aucun `dFdx`/`dFdy` n'est utilisé pour construire N ou le TBN. | Supprime la source des facettes des rounds 8-14 **[M]**. |
| Aucune branche ne dépend d'un booléen de fonctionnalité : les paliers sont des `#define`. | Pas de pression de registres pour du code non exécuté. |

### 4.3 Uniformes, blocs et unités de texture

**[C] Blocs d'uniformes.** Justification du choix UBO plutôt que SSBO : macOS plafonne à GL 4.1
**[M]**, où les SSBO n'existent pas. Le minimum garanti par la spec pour un UBO est 16 Ko : tous
les blocs ci-dessous tiennent dessous.

| Bloc | Contenu | Taille |
|---|---|---|
| `ub_frame` | matrices caméra, exposition, temps, taille d'écran, palier | ~512 o |
| `ub_astres` | 2 × { dir, couleur, poids, régime, index de tuile d'ombre, matrice } | ~320 o |
| `ub_env` | SH L2 (9 × vec3 → 9 × vec4), niveau et teinte d'ambiante du créneau, `sky_vis` global | 192 o |
| `ub_shadow` | par tuile : matrice, plage, texel monde, biais ; + splits de cascade | ~640 o |
| `ub_lights` | **256** × `Light` (48 o) : `pos(3) radius(1) color(3) intensity(1) dir(3) cos_outer(1) cos_inner(1) type(1) flicker_id(1) pad(1)` | **12 Ko** |
| `ub_material` | constantes de la matière du draw (rugosité, métal, F0, sens du vert, échelles) | 64 o |

**[C] Unités de texture, étage FRAGMENT.** Budget cible **≤ 12** ; plafond matériel 16 **[M]**.

| Unité | Nom | Format | Note |
|---|---|---|---|
| 0 | `tex_albedo` | RGBA8 sRGB | l'actuel `tex_T0` |
| 1 | `tex_screen_ao` | R8 | sortie de P4 |
| 2 | `tex_shadow_atlas` | DEPTH16 | comparaison **manuelle** (l'Adreno 618 renvoie 1.0 sur le chemin matériel **[M]**) |
| 3 | `tex_env_cube` | RGBA16F, mips | sortie de P3 ; spéculaire ambiant |
| 4 | `tex_cluster` | RG32UI 3D | offset + nombre par froxel |
| 5 | `tex_light_index` | R32UI 2D | la liste d'index |
| 6 | `tex_prepass_depth` | DEPTH24 | ombres de contact |
| 7 | `tex_mat_orm` | RGBA8 | occlusion / rugosité / métal empaquetés |
| 8 | `tex_mat_n` | RG ou RGB8 | normale (Z reconstruit si 2 canaux) |
| 9 | `tex_mat_h` | R8 | hauteur (parallaxe / tessellation) |
| 10 | `tex_mat_e` | RGB8 sRGB | émissif |
| 11 | `tex_mat_th` | R8 | épaisseur, palier ≥ 2 |

**Libérés par rapport à aujourd'hui [M]** : les 4 `sampler3D` de la grille de sondes supprimée,
et les samplers séparés `tex_PBR_R`/`_M`/`_AO` fusionnés dans `tex_mat_orm`. Gain net : 5 unités.

**[C] Étage VERTEX** (budget séparé, non contraint) : la palette TOD (`tex_tod`, 8192×1) plus
deux textures 8192×1 nouvelles, `tex_tod_skyvis` (R8) et `tex_tod_ao` (R8). Les trois sont lues
par `texelFetch(ivec2(color_index, 0), 0)` et passées en varyings. **Aucune n'entre dans le
budget fragment.** Le volume de sondes est lu dans le vertex shader pour merc et dans le fragment
seulement au palier ≥ 2.

### 4.4 Variantes de programme et paliers

**[C]** Trois paliers, un `#define LIGHT_TIER` par programme, plus des `#define` de
fonctionnalité. Ce qu'un palier **supprime**, il le supprime du texte compilé.

| Capacité | `LIGHT_TIER 0` (bas) | `1` (moyen) | `2` (haut) |
|---|---|---|---|
| Astres directs | 2 | 2 | 2 |
| Cascades pour l'astre dominant | 2 | 3 | 4 |
| Taps PCF | 4 (grille tournée) | 16 (Poisson tourné) | 16 + pénombre variable |
| Ombres de contact | non | 8 pas | 16 pas |
| Environnement diffus | SH L2 depuis la table de mood seule | SH L2 depuis la capture de ciel | id. |
| Environnement spéculaire | approximation analytique | cube 32², 4 mips | cube 128², 6 mips |
| Lumières par froxel | 4 | 8 | 16 |
| AO | désactivable, SSAO | HBAO | GTAO |
| Sondes d'irradiance | par objet (vertex) | par objet | **par pixel** |
| SSS | non | non | oui (`thickness`) |
| Parallaxe / tessellation | tel qu'aujourd'hui | id. | id. |

**[C] Nombre de programmes.** Le décor a 5 hôtes (`tfrag3`, `etie_base`, `tie_wind`, `shrub`,
`hfrag`) plus la variante tessellée, les acteurs 3 (`merc2`, `generic`, `emerc`), l'herbe et
l'océan 2 : **11 hôtes × 3 paliers = 33 programmes**, à comparer aux ~20 programmes monde
d'aujourd'hui. Un palier ne compile que le sien : le coût est le temps de compilation au premier
boot, mesuré, avec cache disque.

### 4.5 HDR, exposition, tone map

**[C]** Décision structurante : **ni ORIGINE-TOTAL ni ORIGINE-LUMIÈRE ne passent par la chaîne
HDR.** `recharged_master` OFF **ou** `recharged_lighting` OFF ⇒ FBO `RGBA8`, pas de tone map,
exactement le chemin d'aujourd'hui. C'est ce qui rend l'équivalence bit-à-bit atteignable sans
discuter de courbe.

**[C] Le HDR est gardé par l'éclairage, pas par le master.** La forme correcte est
`recharged_active(recharged_hdr) && recharged_active(recharged_lighting)` — ou, mieux, un helper
`lighting_active(sous_drapeau)` qui compose les trois niveaux une seule fois, sur le modèle de
`Gfx::recharged_active()`. Un sous-réglage d'éclairage qui ne consulte que le master est un
défaut : c'est celui que l'owner a trouvé le 2026-09-06.

Master ON :

| Élément | Valeur |
|---|---|
| Format de la scène | `RGBA16F`. Repli déclaré : `R11F_G11F_B10F`, puis `RGBA8` à exposition fixe. |
| Exposition | `ub_frame.exposure`, défaut **1,0**. Calibrée pour que « direct = 0 » reproduise l'original. |
| Courbe « Fidélité » (défaut SDR) | Courbe monotone calibrée sur les comparaisons statistiques ON/OFF : réserver une marge aux hautes lumières, préserver teinte et détails. Pas d’identité imposée jusqu’à 1 : elle ne laisse aucune marge SDR au-delà. |
| Courbe « Filmique » (option) | Khronos PBR Neutral. Préserve mieux la teinte des hautes lumières que ACES sur du contenu stylisé, ce qui est la règle 3. |
| Site d'application | **un seul**, en P9. `tonemap_sites == 1` est la porte de l'item 2. |

#### Séparation artistique / sortie — arbitrage du 7 septembre 2026

Le contrat exécutable est porté par les livrables `lighting-hdr` et
`hdr-display-output` du backlog et leurs portes de défauts. Cette séparation remplace
l'assimilation du tone mapping à tout l'étalonnage ; elle ne demande pas une LUT obligatoire.

`scène HDR → exposition / étalonnage artistique commun → adaptation de sortie SDR OU HDR`

| Responsabilité | Exigence |
|---|---|
| Profil artistique par niveau | Commun aux deux sorties, transitions lissées. Domaine, encodage et plage déclarés ; conserve les valeurs au-delà de 1 avant adaptation écran. |
| LUT éventuelle | Représentation du profil, pas intrinsèquement un tone map. Pas de compression SDR incorporée dans la LUT commune. Domaine HDR adapté (par exemple log déclaré), pas de clamp 0..1 de la radiance. |
| Sortie SDR, chantier actuel | Courbe/exposition globales puis corrections résiduelles mesurées. Ajustements propres au SDR séparés du profil commun. Comparaison statistique, jamais identité ON/OFF imposée. |
| Sortie HDR, chantier suivant | Part de la même scène étalonnée ; adapte luminance, gamut et encodage à l'écran détecté. Ne part jamais de l'image déjà comprimée SDR. Un écran HDR nécessite aussi une adaptation à ses limites. |
| Organisation GPU | Séparation logique des paramètres et responsabilités ; fusion dans une passe ou LUT de sortie générée permise. Ne pas imposer plusieurs passes plein écran pour cette séparation. |
| Options / coût | Sortie HDR et calcul HDR interne sont distincts. Les questions owner ne commandent pas un nouveau chemin LDR. Coût GPU à mesurer si instrumentation disponible, sinon explicitement non mesuré, sans retarder les corrections. |

`hdr_tonemap_defects` doit couvrir l'écrêtage avant adaptation et la confusion du profil
artistique avec la compression SDR, en plus des défauts d'image existants.
`hdr_out_defects` doit couvrir la perte/changement du profil lors du toggle, le passage
intermédiaire par SDR et la double adaptation. Profil identité et entrées supérieures à 1
servent de contrôles programmatiques ; un compteur de passes seul ne prouve pas l'ordre.
La preuve reste produite par `proof_run.sh` et jugée par `generic.sh`.

Les comparaisons SDR guident la calibration actuelle ; elles ne prouvent pas à elles seules
que le profil convient en sortie HDR. Le second chantier vérifie sur écran HDR réel.
La sortie HDR reste après la correction SDR, sans rétablir de prérequis de rejeux exacts.

**[C]** Le moteur publie `hdr_overbright_px` : le nombre de pixels dont la luminance linéaire
dépasse 1,0 avant tone map. Dans le build actuel il vaut **0 par construction** (RGBA8 clampe) :
c'est le dénominateur qui prouve que la marge existe.

### 4.6 La prépasse

**[C]**

* Cibles : `depth` (partagée avec P6 pour éviter un second Z-write), `RG16F` normale en
  octaédrique, `R8` rugosité.
* Contenu : tout l'opaque monde + les acteurs opaques. **Pas** l'alpha, **pas** l'eau, **pas** les
  particules.
* Shaders : deux programmes seulement (décor / merc skinné), pas de texture sauf pour l'alpha-test
  du feuillage (qui doit y participer, sinon son AO et ses ombres de contact sont fausses).
* Réutilisation : P6 tourne en `GL_EQUAL` / `glDepthMask(GL_FALSE)` sur l'opaque, ce qui supprime
  le surdessin dans la passe chère.
* Gain attendu **[C]**, à mesurer : sur une scène où l'opaque monde se recouvre 2 à 3 fois, la
  prépasse coûte un Z-only et économise 1 à 2 exécutions du fragment le plus lourd du jeu.
* **La normale de la prépasse remplace les dérivées d'écran** partout : `cross(dFdx(v_fringe_rel),
  dFdy(v_fringe_rel))` disparaît des cinq shaders monde. C'est la source mesurée des facettes des
  rounds 8 à 14 **[M]** et du « camera-signed handedness » du round 26.

### 4.7 AO et occlusion spéculaire

**[C] Ce qui change, exactement :**

| | Aujourd'hui **[M]** | Cible **[C]** |
|---|---|---|
| Cible de la passe | compose sur l'image opaque, `GL_ZERO / GL_ONE_MINUS_SRC_COLOR` | écrit une texture `R8` |
| Espace | gamma (l'image porte déjà `pow(1/2.2)`) | linéaire |
| Ce qui est multiplié | **tout** le pixel | le **seul** terme indirect |
| Protection du direct | masque `1 − smoothstep(0.45, 0.90, luma)` | **aucun masque** : le direct n'est pas touché |
| Transparents | exclus par construction (la passe est pré-alpha) | ombrés comme le reste |
| Eau | exclue par stencil | `SURF_WATER`, traitée par la matière |
| Combinaison avec l'AO de matière et l'AO cuite | aucune, superposition au hasard | produit explicite, ligne 3 de §4.2 |

**[C] Occlusion spéculaire.** Un terme dérivé, pas une seconde passe :
`occ_spec = clamp(pow(N·V + ao, roughness²) − 1 + ao, 0, 1)` (forme usuelle), appliqué au **seul**
spéculaire ambiant. Sans lui, un creux occulté garde un reflet d'environnement pleine intensité —
c'est la moitié du « voile plastique » que la bissection avait attribuée au spéculaire **[M]**
(`u_pbr_bisect` bit 4 : « zeroing this term halved the wall luma »).

**[C] Les trois estimateurs existants (SSAO/HBAO/GTAO) ne changent pas.** Ce qui change est leur
entrée (la prépasse au lieu de la profondeur reconstruite) et leur sortie (une texture au lieu
d'un blend). Le masque de luminance et la copie de scène `m_scene_tex` disparaissent.

### 4.8 Ombres

**[C] Une seule texture, des tuiles.** Un atlas `DEPTH16` carré, découpé en 4 tuiles :

| Palier | Atlas | Tuile | Mémoire | Répartition |
|---|---|---|---|---|
| 0 | 2048² | 1024² | 8 Mo | 2 cascades soleil + 1 lune + 1 libre |
| 1 | 4096² | 2048² | 32 Mo | 3 cascades soleil + 1 lune |
| 2 | 8192² | 4096² | 128 Mo | 4 cascades soleil + 1 lune (tuile lune à 2048² dans le coin) |

Le palier `Very High 8192²` **par carte** disparaît : c'était 256 Mo pour une seule cascade **[M]**.

**[C] Sélection de cascade** : par distance caméra, splits pratiques `{8 m, 32 m, 150 m, ∞}` au
palier 1, avec transition en fondu sur 10 % de la borne. Stabilisation : la boîte ortho est
**snappée au texte monde** (`floor(pos / texel_world) * texel_world`) pour supprimer le
scintillement de bord quand la caméra bouge — ce que le code actuel ne fait pas **[M]**.

**[C] Biais** : décalage le long de la normale (`normal offset`), en mètres, proportionnel au
texel monde de la tuile et à `1 − N·L`, plus un biais de profondeur constant minuscule. C'est ce
que le code fait déjà et c'est correct **[M]** ; ce qui change est que la valeur est **par tuile**
au lieu d'être globale.

**[C] Filtrage** : Poisson 16 taps tourné par un hash de `gl_FragCoord`, rayon **piloté par le
régime** (§4.11) et par la distance à l'occulteur, pas seulement par la distance caméra. En
régime « dôme couvert » le rayon part au maximum : une ombre sous un ciel couvert n'a pas de bord.

**[C] Deux astres, deux ombres.** Chaque astre a sa ou ses tuiles et son poids. Aucune
« attribution », aucun fondu de confiance, aucune EMA : ils s'additionnent, chacun occulté par sa
propre carte. Règle de budget **[C]** : la lune verte ne reçoit une tuile que si son poids
directionnel dépasse 5 % du direct total ; sinon elle reste une lumière **sans ombre**, ce qui est
le comportement physique observable (la Lune ne projette pas d'ombre visible en plein jour).

**[C] Ombres de contact.** Marche en espace écran sur `tex_prepass_depth` le long de `L`,
8 ou 16 pas, longueur monde plafonnée (~0,5 m), épaisseur de rejet pour ne pas auto-ombrer.
Elles règlent le sous-texel au point d'appui **et** suppriment le compromis actuel : le
`normal offset` doit aujourd'hui être assez gros pour tuer l'acné, ce qui décolle l'ombre du pied
de l'occulteur (« peter-panning ») **[M]** (le commentaire de `tfrag3.frag` documente exactement
ce compromis).

**[C] Ce que l'atlas contient.** Classes de projecteurs : `tfrag`, `tie` (+ `tie_wind`),
`shrub`, **`merc`**. `shadow_caster_classes == 4` est la porte de l'item 6. Les acteurs y entrent
avec leur maillage skinné ; au palier 0 ils y entrent avec `shadow-geo` comme proxy de profondeur
(115 sommets **[M]**, un cadeau pour une passe Z-only).

### 4.9 Lumières locales

**[C] Grille de clusters.** 16 × 9 × 24 froxels, Z exponentiel entre le near plane et 120 m.
Remplissage sur le **fil de rendu** (jamais le fil GOAL, règle §1.3) : soit en compute là où il
existe, soit en C++ (une sphère contre une froxel est un test trivial ; à 256 lumières visibles
le coût est de l'ordre de quelques dizaines de microsecondes). Le compute est un accélérateur
mesuré, jamais une dépendance.

**[C] Type de lumière.**

| `type` | Sens | Paramètres utilisés |
|---|---|---|
| 0 | ponctuelle | `pos`, `radius`, `color`, `intensity` |
| 1 | cône (spot) | + `dir`, `cos_outer`, `cos_inner` |
| 2 | surfacique plate (lave, flaque d'éco) | `pos`, `dir` = normale, `radius` = étendue |

**[C] Atténuation** : inverse du carré avec un plafond de proximité et une **coupure lisse au
rayon** (`(1 − (d/r)⁴)²` × `1/d²`), pour que le culling par froxel soit exact : une lumière ne
doit pas contribuer au-delà du rayon qui a servi à la ranger.

**[C] Vacillement.** Le jeu anime déjà ses sources **[M]** (`update-mood-flames` sur `times[5].w`
à Sandover, `update-mood-lava` sur six créneaux au lavatube). Le pont pousse **un scalaire par
canal de vacillement** (au plus 8, comme les créneaux), et chaque lumière du lexique déclare le
canal qu'elle suit. Résultat : les torches clignotent **en phase** avec le vacillement du baked
d'origine, parce que c'est la même donnée.

**[C] Pas d'ombre par lumière locale.** Justification : une carte cubique par lumière est hors
budget sur toute la gamme basse, et le gain visuel d'une ombre de lanterne est faible devant son
coût. À la place : l'occlusion vient de l'AO, des ombres de contact, et de la **visibilité cuite
par lumière** (§5.3.6) pour la géométrie statique. Une ombre projetée par une lumière locale est
un chantier ultérieur, pas un manque de celui-ci.

### 4.10 Environnement

**[C] La forme vient du ciel, le niveau et la teinte viennent de la table.**

```
1. si le niveau a un ciel (sky = #t) et tier ≥ 1 :
     capture du DÔME RÉEL dans un cube (32² à 128² selon le palier), amortie
       1 face / n images (le ciel change lentement : 8 créneaux sur 24 h)
     projection SH L2  ->  sh_raw[9]
   sinon :
     sh_raw = SH du volume de sondes au point de vue de la caméra (§4.12)

2. RENORMALISATION (c'est ici que la règle 3 est tenue) :
     mean_raw   = irradiance moyenne de sh_raw sur la sphère  ( = sh_raw[0] * cste )
     amb_target = amb-color du créneau courant  ×  ambient_strength (réglage)
     sh[i]      = sh_raw[i] * (luma(amb_target) / luma(mean_raw))
     sh[0]     += (amb_target − luma(amb_target)) ...   // la TEINTE est celle de la table

   => la DISTRIBUTION (quelle direction est plus claire, de combien) vient du ciel ;
      le NIVEAU et la TEINTE viennent de mood-lights[créneau].amb-color.

3. le moteur publie env_amb_tone_delta = | luma(mean(sh)) − luma(amb_target) | ;
   la porte de l'item 5 exige qu'il reste sous ε.
```

**[C] Spéculaire ambiant** : le même cube, préfiltré en chaîne de mips par rugosité, consommé par
l'approximation split-sum. Au palier 0, le cube n'existe pas et le spéculaire ambiant est
l'évaluation analytique du SH dans la direction de réflexion — pas un dégradé inventé, le SH
mesuré.

**[C] Le TIE envmap d'origine.** `etie` / `etie_base` portent le mapping d'environnement de
Naughty Dog, avec sa propre texture **[M]**. Il est **repointé sur `tex_env_cube`** au lieu de
garder son look propre, sous son propre interrupteur : c'est le seul moyen qu'un objet à envmap et
un objet PBR reflètent le même monde. Le mode ORIGINE garde la texture d'origine.

**[C] Fichier d'ajustement par niveau.** `recharged_assets/lighting_overrides.txt`, format §5.7.2 :
il permet de corriger le niveau, la teinte, le contraste directionnel et l'intensité relative des
astres **par niveau et par créneau**, sans rebuild ni APK. C'est la soupape que la règle 3 exige :
« On peut ajuster à tous les niveaux ».

### 4.11 Le régime pilote le direct

**[C]** Le régime est calculé **hors ligne** (§5.3.7), stocké par niveau × créneau dans le
compagnon, et interpolé par le moteur entre les deux créneaux actifs comme tout le reste.
`ub_astres` porte, par astre, un `régime` qui module :

| Régime | Poids direct | Rayon de pénombre | Spéculaire | Clé |
|---|---|---|---|---|
| clé dure | 1,0 | nominal | plein | astre |
| dôme couvert | 0,45 | **× 4** | atténué à 0,25 | **direction du créneau**, pas l'astre |
| ambiante dominante | 0,25 | × 3 | atténué à 0,4 | direction du créneau |
| source basse | 1,0 | × 2 | plein | direction du créneau (élévation < 0) |
| ambiante seule | 0,0 | — | ambiant seul | aucune |
| source pure | 1,0 | nominal | plein | direction du créneau, transitoire |

**[C] Règle dure, et c'est la porte de l'item 5 :** la direction de la clé est
`mood-lights[créneau].direction`, interpolée. Elle n'est remplacée par la position d'un astre
**que si** (a) le niveau a `sun-fade > 0`, (b) l'astre est au-dessus de l'horizon, et (c) l'angle
entre les deux vecteurs est inférieur à 30° — c'est-à-dire seulement quand le créneau décrit
manifestement cet astre. Le moteur publie `regime_sun_override_wrong` : le nombre d'images où
l'écrasement a eu lieu alors qu'une des trois conditions manquait. Il vaut aujourd'hui le nombre
total d'images dans 16 niveaux sur 20.

`sun-fade` multiplie la part directe des astres (et seulement elle) : `misty` 0,25, `snow` 0,5.

### 4.12 Sondes d'irradiance

**[C] Ce qui a été appris de l'échec précédent [M]** : la grille supprimée était **dense**
(~39 000 sondes), lue **par pixel** avec une boucle `texelFetch` sur 8 coins, et sa fuite était
traitée par un « snap vers la cellule contenante » — un correctif au point de constat.

**[C] La forme retenue :**

* **Éparse** : seules les cellules dont la visibilité du ciel est intermédiaire (`0,02 < sky_vis <
  0,98`) ou intérieures portent une sonde. Les zones franchement extérieures n'en ont pas besoin :
  le SH d'environnement suffit.
* **L1** : DC + 3 coefficients, 4 × RGB8 = **16 octets** par sonde, plus un octet par voisin pour
  la visibilité mutuelle.
* **Anti-fuite au point de production** : la **visibilité entre sondes voisines est cuite**
  (§5.3.5). L'interpolation pondère chaque coin par cette visibilité. Une sonde derrière un mur a
  un poids nul, par construction, sans boucle de confinement à l'exécution.
* **Lecture** : par objet (au barycentre, dans le vertex shader) aux paliers 0 et 1 ; par pixel au
  palier 2. Les acteurs y lisent leur indirect (`SURF_NO_INDIRECT`).
* Porte de l'item 8 : `probe_leak_permille` — la fraction en pour mille de l'irradiance d'une
  sonde intérieure qui provient de sondes extérieures, mesurée en annulant ces dernières.

### 4.13 Les acteurs

**[C]**

| Aujourd'hui **[M]** | Cible |
|---|---|
| éclairage par sommet dans `merc2.vert` | `merc2.frag` appelle `shade()` ; le vertex ne fait plus que la peau et les varyings |
| pas de normale par pixel | `rotated_nrm` devient un varying ; carte de normales si la matière en a une |
| pas de réception d'ombre | `tex_shadow_atlas`, mêmes cascades que le décor |
| pas d'AO | `tex_screen_ao`, plus l'AO de matière |
| ambiante = `vu-lights.ambient` | volume de sondes, avec `light-index` en surcharge locale |
| ombre = aplat stencil 115 sommets | maillage skinné dans l'atlas ; l'aplat devient repli et mode Original |

**[C] `light-index` est conservé comme intention artistique.** Le jeu bascule Jak sur un
`light-group` local près de chaque hutte, avec un `target-interp` continu **[M]**. Ce choix reste :
il **teinte** l'indirect lu dans les sondes, il ne le remplace pas. C'est de l'art-direction, on
n'y touche pas.

**[C] `generic` et `emerc`** passent par le même chunk. `emerc` (envmap merc) est repointé sur
`tex_env_cube` comme `etie`.

**[C] Coût.** L'ombrage acteur passe du vertex au fragment. Sur le Redmi, où le goulot est le fil
GOAL et non le GPU **[M]**, c'est le bon sens du transfert. À mesurer quand même : le palier 0
utilise 4 taps PCF et pas d'ombre de contact sur la peau.

### 4.14 Matières

**[C]** Rien de neuf dans le modèle : la BRDF du chemin fusionné actuel est déjà correcte dans
ses pièces (GGX, Smith height-correlated, Fresnel plafonné par la rugosité, split-sum de Karis)
**[M]**. Ce qui change :

* Elle vit **une seule fois**, dans `shade()`, au lieu de trois copies divergentes.
* `surfaces.json` reste la source des propriétés **[M]** (`managed_assets/<jeu>/surfaces.json`,
  172 enregistrements mesurés, avec index par nom nu et copie externe prioritaire).
* **Une matière sans aucune carte est un cas normal**, pas une exception derrière une porte. Le
  bricolage actuel (`u_pbr_mode` bit 256, « ouvrir la porte pour rendre les constantes
  atteignables » **[M]**) disparaît : les constantes sont toujours atteignables.
* Les cartes `_roughness` / `_metallic` / `_ao` se rangent dans un `_orm` unique (canal R = AO,
  G = rugosité, B = métal), ce qui libère deux unités de texture.
* La tessellation et la parallaxe sont **ré-hébergées telles quelles** : mêmes lois, mêmes
  mesures par matière (`u_pbr_uv_per_m`, `u_pbr_height_lambda`, statistiques de hauteur), même
  gate par programme. Aucun retravail dans ce chantier.

### 4.15 Ce qui garantit le mode ORIGINE

**[C]** Quatre mécanismes indépendants, pas un seul :

1. **Graphe séparé, sur DEUX portes.** `recharged_master` OFF **ou** `recharged_lighting` OFF ⇒
   aucune de nos passes n'est créée, le FBO est `RGBA8`, aucun tone map. Le chemin est celui
   d'aujourd'hui, littéralement. Un sous-réglage d'éclairage qui ne consulte que le master laisse
   la refonte tourner alors que le joueur l'a éteinte — c'est le défaut du 2026-09-06.
2. **Palette A intacte.** Le compagnon ajoute la palette B ; le fr3 n'est jamais réécrit. Une
   porte compare les octets.
3. **`Gfx::recharged_active()` unique.** Aucun consommateur ne lit un drapeau de fonctionnalité
   directement (règle déjà en place **[M]**).
4. **Garde de non-régression rejouée** à chaque fermeture d'item, sur les **trois** jeux de
   référence (§7.3), dont ORIGINE-LUMIÈRE.

---

## §5 — LE BAKE HORS LIGNE

### 5.1 L'outil

**[C]** `tools/light_bake`, sur le patron de `tools/mesh_audit` **[M]** (qui lit les fr3, calcule,
et écrit un compagnon avec `--bake`).

```
tools/light_bake [options] <fr3-dir> [niveaux...]

  --bake                 écrit <fr3-dir>/<niveau>.lightbake   (sans : audit seul)
  --rays N               rayons par sommet pour la visibilité (défaut 64)
  --probe-cell M         arête de cellule de sonde en mètres (défaut 4)
  --emitters FILE        lexique d'émetteurs (défaut recharged_assets/light_emitters.txt)
  --overrides FILE       ajustements par niveau (défaut recharged_assets/lighting_overrides.txt)
  --report FILE          rapport texte + CSV, une ligne par niveau
  --verify               recalcule la reconstruction et sort non-zéro si l'écart dépasse le seuil
```

Sorties par niveau : le compagnon, un bloc de rapport lisible, une ligne CSV. Le format du
rapport suit `format_mesh_audit` **[M]** pour que 26 niveaux restent greppables.

### 5.2 Les mathématiques de la dé-illumination

**[C]** Pour le créneau `i` d'un niveau, la lumière est connue (§3.1). On modélise ce que le bake
de ND contient :

```
bakedᵢ(v)  =  [  ambᵢ · skyvis(v)  +  lgtᵢ · max(N(v)·Lᵢ, 0) · visᵢ(v)  ]  ×  artᵢ(v)
               └────── part reconstruite (physique) ──────┘                 └── résidu ──┘
où
  ambᵢ      = mood-lights[i].amb-color          (connu, table)
  lgtᵢ      = mood-lights[i].lgt-color          (connu, table)
  Lᵢ        = mood-lights[i].direction          (connu, table)
  N(v)      = normale du sommet                 (connue, fr3 v44 soudé)
  skyvis(v) = visibilité cosinus du ciel        ← À CALCULER (§5.3.1)
  visᵢ(v)   = visibilité de la clé du créneau i ← À CALCULER (§5.3.2)
```

On en tire, par index de couleur :

```
physᵢ    =  ambᵢ · skyvis  +  lgtᵢ · max(N·Lᵢ,0) · visᵢ
artᵢ     =  bakedᵢ / max(physᵢ, ε)                     ← MESURÉ, jamais inventé
indirectᵢ =  ambᵢ · skyvis  ×  artᵢ                     ← la palette B
directᵢ  =  lgtᵢ · max(N·Lᵢ,0) · visᵢ  ×  artᵢ          ← ce que le temps réel refait
```

**[C] Trois propriétés, et ce sont elles qui rendent la chose défendable :**

1. **Inversibilité.** `indirectᵢ + directᵢ = bakedᵢ` exactement, par construction. C'est la porte
   de l'item 4 : le moteur recalcule les deux termes au chargement, aux 8 heures canoniques, et
   publie `bake_reconstruction_maxdelta` en unités 1/255.
2. **Le résidu porte la stylisation.** Tout ce que ND a peint à la main — teinte subjective,
   ombre décorative, dégradé d'ambiance — se retrouve dans `artᵢ`, qui multiplie **tout** ce que
   le temps réel calcule ensuite. On ne le corrige pas, on ne le lisse pas : on le transporte.
   L'outil publie `art_residual_p50` et `art_residual_p95` (dispersion de `artᵢ` autour de 1) :
   c'est la mesure de « combien de ce bake est de l'art plutôt que de la physique ».
3. **Bornage.** `artᵢ` est clampé à `[0,25 ; 4,0]` **[C]** : au-delà, `physᵢ` est trop petit pour
   que la division ait un sens (surface noire, créneau éteint). Hors des bornes, on stocke
   `indirectᵢ = bakedᵢ` et `directᵢ = 0` — c'est-à-dire « ce sommet reste tel quel », le
   comportement le plus sûr. L'outil publie `art_clamped_frac`.

**[C] Granularité.** Le bake travaille **par index de couleur** (≤ 8192 par arbre), pas par
sommet, parce que la palette l'est. Deux sommets qui partagent un index avaient la même couleur
baked aux 8 créneaux : ils partagent donc aussi `skyvis` et `visᵢ` à la précision qu'avait le
bake. `N` reste par sommet ; l'outil agrège `max(N·Lᵢ,0)` sur les sommets d'un index en pondérant
par la surface. La **normale coudée** reste par sommet (2 octets), là où elle sert.

### 5.3 Les algorithmes

#### 5.3.1 Visibilité du ciel (`skyvis`)

**[C]** Par index de couleur. Lancer de `--rays` rayons dans l'hémisphère de `N`, distribution
cosinus (Hammersley + rotation par index pour décorréler), contre un BVH construit sur la
géométrie **soudée** de tous les arbres du niveau plus les instances TIE développées.
`skyvis = (rayons non bloqués) / (rayons émis)`. Origine du rayon décalée de `ε·N` pour éviter
l'auto-intersection. Un rayon qui sort de la boîte englobante du niveau compte comme ciel.

Pour un niveau `sky = #f` **[M]**, `skyvis` reste calculé (il mesure l'ouverture géométrique) mais
n'est pas multiplié par une radiance de ciel à l'exécution : il sert au classement intérieur et à
l'AO.

#### 5.3.2 Visibilité de la clé (`visᵢ`)

**[C]** Par index de couleur et par créneau. Rayon unique vers `Lᵢ` (la clé est directionnelle),
plus 4 rayons dans un cône de 2° pour adoucir — sinon la porte de reconstruction devient bruitée
sur les bords d'ombre. `visᵢ = fraction non bloquée`. Si `max(N·Lᵢ,0) == 0`, `visᵢ` n'est pas
calculé (le terme est nul de toute façon) : économie mesurable, ~40 % des couples (index, créneau)
sur `village1`.

Cas particulier **[C]** : un créneau en **source basse** (élévation < −0,2) ou en **dôme couvert**
n'est pas une directionnelle ponctuelle. Pour ceux-là, `visᵢ` est calculé comme une visibilité de
**cône large** (60° pour le dôme, 90° vers le bas pour la lave) : c'est ce qui rend la
reconstruction juste sur `swamp` et `lavatube`.

#### 5.3.3 Normale coudée et AO

**[C]** Dans la même passe que 5.3.1, à coût marginal nul :
`bent_N = normalize(Σ dir_non_bloquée)`, `ao = skyvis` (l'AO cosinus **est** la visibilité du
ciel dans une scène sans ciel coloré). Stockage : `bent_N` en octaédrique 2 × u8 par sommet,
`ao` en u8 par index de couleur.

#### 5.3.4 Placement des sondes

**[C]** Grille régulière de `--probe-cell` mètres sur la boîte du niveau, puis élagage :
une cellule est conservée si (a) elle n'est pas dans du solide, et (b) `0,02 < skyvis_moyen <
0,98` **ou** elle est classée intérieure. Le SH L1 de chaque sonde est intégré par lancer de
rayons depuis son centre : chaque rayon qui touche une surface récupère l'`indirectᵢ` de cette
surface (donc la sonde porte **l'art**, elle aussi) ; chaque rayon qui sort porte l'ambiante du
créneau. Résultat : un SH L1 **par créneau**, ce qui garde le cycle jour/nuit dans les intérieurs.

Budget **[C]** : `village1` à 4 m donne de l'ordre de quelques milliers de cellules brutes, dont
une petite fraction survit à l'élagage. À 16 octets par sonde et par créneau, l'outil publie
`probes` et `probe_bytes` par niveau ; le budget est un chiffre, pas une supposition.

#### 5.3.5 Visibilité inter-sondes

**[C]** Pour chaque sonde et chacun de ses 6 voisins d'axe : rayon direct entre les deux centres.
Un octet par paire (`0` = bloqué, `255` = libre, valeurs intermédiaires par sur-échantillonnage).
L'interpolation à l'exécution pondère chaque coin du cube par le produit des visibilités le long
du chemin depuis la cellule contenante. **C'est l'anti-fuite au point de production** : une sonde
derrière un mur a un poids nul sans aucun test à l'exécution.

#### 5.3.6 Visibilité par lumière locale

**[C]** Pour chaque lumière extraite (§5.3.8) et chaque index de couleur dans son rayon : un rayon
vers le centre de la lumière. Stocké de façon éparse (`(light_id, color_index) -> u8`), avec un
plafond par niveau. C'est ce qui remplace une carte d'ombre par lanterne : sur la géométrie
statique l'occlusion est exacte et gratuite ; sur les acteurs, l'ombre de contact prend le relais.

#### 5.3.7 Classement des régimes

**[C]** Par niveau et par créneau, exactement les règles du tableau §3.2, appliquées à
`mood-lights-table[i]` du `mood` du niveau (`level-load-info.mood` **[M]**). Le résultat est un
octet par créneau. L'outil publie la table complète pour les 26 niveaux : elle doit correspondre
à l'annexe A, ce qui est un contrôle de non-régression du classificateur lui-même.

#### 5.3.8 Extraction des émetteurs

**[C]** Trois sources, dans cet ordre de priorité :

1. **Le lexique.** Pour chaque instance TIE dont le nom de prototype est déclaré `LUMIERE` dans
   `light_emitters.txt`, une lumière est émise à la position `matrice · offset`, avec la couleur,
   l'intensité, le rayon et le type du lexique.
2. **Les jumeaux `-glow.mb`.** Si un prototype `X-glow.mb` existe et que `X.mb` n'est pas déjà
   traité, la lumière est émise au **barycentre de la géométrie du jumeau**, et sa couleur est la
   **moyenne pondérée par la surface de la texture du jumeau** — donc la couleur que ND a peinte.
   16 prototypes, 307 instances **[M]**.
3. **Les créneaux à source basse.** Un créneau en régime « source basse » (lave) produit un
   **émetteur surfacique** par surface dont le sommet regarde vers le bas et dont l'`indirectᵢ`
   du créneau est au-dessus d'un seuil. C'est ainsi que la lave du lavatube devient une lumière,
   au lieu d'être devinée depuis un nom de prototype (« lava- » est un préfixe de niveau, pas un
   matériau : `lava-metalplank.mb` est une planche **[M]**).

**[C] Le résidu est publié.** `lights_unjudged` = nombre de prototypes dont le nom porte un jeton
d'émetteur (`light, lite, lamp, lant, torch, glow, flame, candle, brazier, spotlight, neon`) et
que le lexique ne tranche **ni** en `LUMIERE` **ni** en `EXCLU`. Porte de l'item 7 : `== 0`.
Le dénominateur mesuré est de **62 prototypes / 1 192 instances** (annexe C), faux amis compris
(`palmplant-base.mb` contient « lant » : il doit être explicitement `EXCLU`).

### 5.4 Format du compagnon `.lightbake`

**[C]** Sur le patron exact de `.meshweld` **[M]** (`MeshConsolidate.cpp:4105-4135`) : magie,
version, empreinte, puis des sections préfixées par leur taille. Tout est petit-boutien.

```
en-tête
  u32   magic            'LBAK' = 0x4B41424C
  u32   version          incrémenté à CHAQUE changement de sémantique, jamais réutilisé
  --- empreinte structurelle (mêmes champs que .meshweld) ---
  str   level_name
  u32   num_verts
  u32   num_trees
  per tree: u8 system, u32 gcount, u32 index_count, u32 color_count
  u32   tfrag3_version   la version du fr3 avec lequel ce compagnon a été cuit
  u32   mood_hash        hash de la mood-lights-table du niveau (voir ci-dessous)

section PALETTE_B        (par arbre)
  u32   tree_index
  u32   color_count
  u8[]  data             MÊME disposition que PackedTimeOfDay : color_quad*128 + pal*16 + c*4 + ch

section SKYVIS           (par arbre)  u32 count, u8[count]
section AO               (par arbre)  u32 count, u8[count]
section BENTN            (par arbre)  u32 vert_count, u8[2*vert_count]   octaédrique

section REGIME
  u8[8]  regime par créneau
  f32[8][3] amb_color et lgt_color recopiés  (contrôle de cohérence à la lecture)

section PROBES
  f32[3] origin ; f32 cell ; u32 dims[3] ; u32 count
  u32[count] cell_index                                  (indices épars dans la grille)
  u8[count][8][4][3] sh                                  L1 = 4 coeff × RGB, par créneau
  u8[count]  interior                                    0..255
  u8[count][6] neighbour_vis                             visibilité inter-sondes

section LIGHTS
  u32 count
  per light: f32 pos[3], f32 radius, u8 color[3], f32 intensity,
             f32 dir[3], f32 cos_outer, f32 cos_inner,
             u8 type, u8 flicker_channel, u16 proto_id
  u32 name_table_bytes ; str[] proto names          (pour le rapport et le debug)

section LIGHTVIS         (éparse, optionnelle)
  u32 count ; per entry: u16 light_id, u32 color_index_global, u8 vis

section STATS            (texte, jamais lu par le moteur, pour le rapport)
```

**[C] Règles de rejet.** Le compagnon est **ignoré** (et le moteur reste sur le chemin
d'aujourd'hui, sans erreur fatale) si : la magie ou la version diffère ; l'empreinte structurelle
ne correspond pas ; `tfrag3_version` diffère de celui du fr3 chargé ; `mood_hash` diffère de la
table de mood compilée. Ce dernier point est **la leçon des cinq bumps de `.meshweld`** **[M]** :
l'empreinte y est « COUNTS-only », donc un compagnon périmé passait la vérification et écrasait
la correction. Ici, un changement de table de mood invalide le bake, parce qu'il invalide
réellement `physᵢ`.

**[C] `mood_hash`** = FNV-1a sur les 8 × (`direction`, `lgt-color`, `amb-color`, `shadow`) de la
table du niveau, arrondis à 1e-4. Il est calculé côté C++ à partir des valeurs poussées par GOAL,
pas à partir du texte source : ce qui compte est ce que le moteur voit.

### 5.5 Chargement à l'exécution

**[C]**

1. `LoaderStages` (ou un étage frère) lit le compagnon en même temps que `.meshweld`. Coût : une
   lecture de fichier, aucun calcul. La règle est celle de `.meshweld` **[M]** : le compagnon
   remplace 45,8 s de passe vive sur `village1` par une lecture ; on ne calcule pas au chargement.
2. `PALETTE_B` va dans une seconde `PackedTimeOfDay` par arbre. `interp_time_of_day` est appelée
   sur **A ou B** selon le master — le même noyau SIMD, un pointeur différent. **Coût
   supplémentaire par image : zéro.**
3. `SKYVIS` et `AO` vont dans deux textures 8192×1 R8 par arbre, lues dans le vertex shader.
4. `BENTN` s'ajoute au flux de sommets (2 octets), à côté de `nor` et `seam_w` qui utilisent déjà
   le rembourrage existant **[M]**.
5. `PROBES` va dans une texture 3D éparse (indirection : une texture d'index + un atlas de sondes)
   ou, au palier 0/1, reste en mémoire CPU pour la lecture par objet.
6. `LIGHTS` alimente le remplissage de clusters.
7. **Vérification à la lecture** : le moteur recalcule `physᵢ` pour un échantillon d'indices
   (1 sur 64, plafonné), reconstruit `indirectᵢ + directᵢ`, compare à la palette A, et publie
   `bake_reconstruction_maxdelta`. C'est la porte de l'item 4, et elle juge **la donnée livrée**,
   pas ce qu'un outil a imprimé un jour.

### 5.6 Où vivent les fichiers

**[C]** La règle des deux familles d'assets est absolue **[M]** :

| Fichier | Famille | Emplacement | Empaqueté par |
|---|---|---|---|
| `<niveau>.lightbake` | **dérivé des ISO** | à côté du `.fr3`, dans `out/jak1/fr3/` | `scripts/package_game_assets.sh` |
| `light_emitters.txt` | **rechargé** | `recharged_assets/` puis `managed_assets/<jeu>/` | dépôt d'assets, pas l'APK |
| `lighting_overrides.txt` | **rechargé** | id. | id. |
| `surfaces.json` | **rechargé** | id. **[M]** (déjà le cas) | id. |

Les deux familles ne se croisent jamais. Un fichier rechargé est modifiable par une poussée de
quelques kilo-octets, sans rebuild ni APK — c'est la condition de la règle 3.

### 5.7 Formats des fichiers d'assets

#### 5.7.1 `light_emitters.txt`

**[C]** Format ligne, sur le patron de `foliage_wind_protos.txt` **[M]** (données, pas du code ;
relu au chargement de niveau ; résidu publié).

```
# Un verdict par prototype. Deux verdicts possibles, aucun implicite.
#   LUMIERE <proto>  type=<point|spot|area>  rgb=<r,g,b>  cd=<intensité>  r=<rayon m>
#                    [off=<x,y,z>] [cone=<inner°,outer°>] [flicker=<0..7>]
#   EXCLU   <proto>  <raison en clair>
#
# Le rayon r est la coupure : au-delà, la lumière ne contribue pas (§4.9).
# flicker= désigne le canal de vacillement, qui suit un créneau de mood (§4.9).

LUMIERE vil1-outdoor-light.mb   type=point rgb=255,214,140 cd=14  r=9   off=0,1.8,0  flicker=5
LUMIERE lantern.mb              type=point rgb=255,196,110 cd=8   r=6   off=0,0.9,0  flicker=5
LUMIERE torch.mb                type=point rgb=255,150,60  cd=18  r=11  off=0,1.4,0  flicker=5
LUMIERE snow-forttorch.mb       type=point rgb=255,150,60  cd=18  r=11  off=0,1.6,0  flicker=5
LUMIERE spotlight-tower-a.mb    type=spot  rgb=230,240,255 cd=60  r=40  cone=12,26
EXCLU   palmplant-base.mb       le nom contient « lant » : c'est une plante
EXCLU   plantboss-litepod.mb    piece de batiment, pas un luminaire
```

#### 5.7.2 `lighting_overrides.txt`

**[C]** La soupape artistique. Une ligne par (niveau, créneau) ou par niveau entier.

```
# <niveau> [slot=<0..7>] clé=valeur ...
#   amb_mul=<f>          multiplie le niveau d'ambiante du créneau
#   amb_tint=<r,g,b>     remplace la TEINTE d'ambiante (le niveau reste celui de la table)
#   dir_mul=<f>          multiplie la part directe
#   moon_mul=<f>         multiplie la lune verte relativement au soleil
#   regime=<clé|dome|ambiante|basse|seule>   force le régime (le classement auto est un défaut)
#   penumbra_mul=<f>     multiplie le rayon de pénombre
#   contrast=<f>         contraste directionnel de l'ambiante

swamp     slot=1  regime=dome  penumbra_mul=1.5
lavatube  slot=2  regime=basse dir_mul=1.2
village1          moon_mul=1.0
```

---

## §6 — RÉGLAGES, MENUS, PERSISTANCE

### 6.1 Le pont GOAL → C++

**[M] Le mécanisme existant, à réutiliser tel quel :**

```
goal_src/jak1/pc/pckernel-impl.gc    (define-extern pc-set-rt-light! (function int none))
goal_src/jak1/pc/hud-classes-pc.gc   (pc-set-rt-light! (if (-> obj realtime-lighting?) 1 0))
game/kernel/jak1/kmachine.cpp:3207   void pc_set_rt_light(u32 sym) {
                                       Gfx::g_global_settings.recharged_rt_light_enable = (sym != 0); }
game/kernel/jak1/kmachine.cpp:4798   make_function_symbol_from_c("pc-set-rt-light!", (void*)pc_set_rt_light);
game/graphics/gfx.h:474              bool recharged_rt_light_enable = false;
consommateur                         Gfx::recharged_active(gs.recharged_rt_light_enable)
```

**[C] Règles pour tout nouveau réglage :**

1. Un `int` ou un `float` encodé en `int` (convention en place : pourcentages ×100 **[M]**). Jamais
   une structure, jamais un pointeur — sauf `pc-set-pbr-lights!` qui existe déjà et reste.
2. Poussé **à chaque image** depuis `hud-classes-pc.gc`, comme les autres. Coût sur le fil GOAL :
   un appel FFI par réglage, ce qui est ce qu'il fait déjà.
3. **Jamais lu directement** : toujours via `Gfx::recharged_active()` / `recharged_active_mode()`.
4. Un `debug.opengoal.<...>` (Android) et un `OG_<...>` (bureau) pour l'A/B sans menu, comme
   aujourd'hui. Mais : **un réglage de menu n'est jamais remplacé par une propriété de debug dans
   le build livré** — la propriété écrase, elle ne définit pas.

**[C] Ce qui doit être poussé en plus de ce qui l'est déjà :**

| Nouveau | Type | Source GOAL |
|---|---|---|
| `pc-set-recharged-lighting!` | int 0/1 | **le maître de la refonte** — remplace `pc-set-rt-light!` |
| `pc-set-light-preset!` | int 0..4 | l'échelle Très bas → Ultra |
| `pc-set-light-tier!` | int 0..2 | palier de shader (déduit du préréglage, écrasable) |
| `pc-set-flicker!` | 8 × int (%) | `(-> *time-of-day-context* moods 0 times i w)` par canal de vacillement |
| `pc-set-mood-slot!` | 2 × int + int (%) | les deux créneaux actifs et leur morph — **le moteur en a besoin pour lire le régime** |
| `pc-set-sun-fade!` | int (%) | `(-> *time-of-day-context* sun-fade)` — **jamais poussé aujourd'hui, c'est le défaut §3.3** |
| `pc-set-mood-lights!` | pointeur | la `mood-lights-table` du niveau courant, 8 × 4 vecteurs, poussée **au changement de niveau seulement** |
| `pc-set-tonemap!` | int 0..1 | Fidélité / Filmique |
| `pc-set-shadow-cascades!` | int 2..4 | |
| `pc-set-contact-shadows!` | int 0..2 | |
| `pc-set-local-lights!` | int 0/1 | |
| `pc-set-local-light-budget!` | int 4..16 | lumières par froxel |
| `pc-set-probes!` | int 0..2 | off / par objet / par pixel |
| `pc-set-env-source!` | int 0..2 | table seule / capture de ciel / capture + cube |
| `pc-set-ao-target!` | int 0..1 | indirect seul (nouveau) / composite (legacy, pour A/B) |

**[C]** `pc-set-mood-lights!` et `pc-set-sun-fade!` sont les deux plus importants : sans eux le
moteur ne peut pas connaître le régime, et il retombe sur l'hypothèse « il y a un soleil » qui est
la cause 3.

### 6.2 La liste complète des réglages exposés

**[C]** Un tableau, parce que « tweakables et desactivables individuellement » est une exigence
et pas une intention.

**[C] La hiérarchie, décidée le 2026-09-06.** Elle a UNE racine pour cette refonte, et ce n'est
pas le master :

```
Recharged  (master, existant)              — TOUT le projet Recharged
├── ÉCLAIRAGE RECHARGÉ  (recharged_lighting, NOUVEAU, ON par défaut)
│   ├── Ombres portées            (cascades · contact · 2e astre)
│   ├── Occlusion ambiante
│   ├── Lumières locales          (+ vacillement)
│   ├── Sondes d'irradiance
│   ├── Source d'environnement
│   ├── HDR + tone map
│   └── Matières PBR              (+ relief · speculaire · displacement · matieres modernes)
├── Modèles HD · Herbe · Textures rechargées · HUD · Polices · Menus
```

**[C] `recharged_rt_light_enable` (« Realtime Lighting ») est RETIRÉ.** Son sens réel est
« prendre le composite A/B plutôt que C/E » — un artefact d'implémentation qui cesse d'exister
dès qu'il n'y a qu'un modèle. Le garder perpétuerait la confusion à cinq chemins que cette
refonte supprime, et c'est déjà ce qui a trompé l'owner sur le HDR le 2026-09-06 : il a éteint
« Realtime Lighting » et le HDR a continué de tourner. Sa ligne de menu est **remplacée** par
« Éclairage Rechargé ».

**[C] Les matières PBR passent SOUS l'éclairage.** C'est la règle 4 appliquée à l'interface : une
matière sans lumière n'a rien à réfléchir, donc « Matières PBR ON + Éclairage Rechargé OFF » est
une combinaison qui n'a pas de sens et qui ne doit pas être proposée.

| Rubrique | Réglage | Valeurs | Défaut | Interrupteur individuel |
|---|---|---|---|---|
| Master | **Rendu** | Original / Recharged | Recharged | c'est lui |
| Master | Préréglage | Très bas · Bas · Moyen · Haut · Ultra · Personnalisé | auto | — |
| Éclairage | **ÉCLAIRAGE RECHARGÉ** | on/off — **off = l'éclairage d'origine, on = notre refonte** | **on** | **c'est le maître de la refonte, et une LIGNE DE MENU, pas un raccourci (§6.4)** |
| Éclairage | Intensité du soleil | 0..2 | 1,0 | — |
| Éclairage | Intensité de la lune verte | 0..2 (× la valeur dérivée de la table) | 1,0 | — |
| Éclairage | Dosage du direct (« Fidélité ») | 0..1 | 1,0 | **0 = le jeu d'origine, prouvé** |
| Éclairage | Ambiante | on/off | on | oui |
| Éclairage | Niveau d'ambiante | 0..2 × table | 1,0 | — |
| Éclairage | Contraste directionnel de l'ambiante | 0..1,5 | selon niveau | — |
| Éclairage | Source d'environnement | table / ciel / ciel+cube | ciel+cube | oui |
| Ombres | Ombres portées | on/off | on | oui |
| Ombres | Résolution d'atlas | 2048 / 4096 / 8192 | selon palier | — |
| Ombres | Cascades | 2 / 3 / 4 | 3 | — |
| Ombres | Distance | 40..200 m | 150 | — |
| Ombres | Force | 0..1 | 0,8 | — |
| Ombres | Ombres de contact | off / 8 pas / 16 pas | 8 | oui |
| Ombres | Ombres d'acteurs | vraies / aplat PS2 / aucune | vraies | oui |
| Ombres | Ombre du second astre | on/off | on | oui |
| Occlusion | Occlusion ambiante | off / SSAO / HBAO / GTAO | HBAO | oui |
| Occlusion | Qualité d'AO | bas / moyen / haut | moyen | — |
| Occlusion | Force d'AO | 0..2 | 1,0 | — |
| Lumières | Lumières locales | on/off | on | oui |
| Lumières | Budget par froxel | 4 / 8 / 16 | 8 | — |
| Lumières | Vacillement | on/off | on | oui |
| Sondes | Sondes d'irradiance | off / par objet / par pixel | par objet | oui |
| Image | Tone map | Fidélité / Filmique | Fidélité | — |
| Image | Exposition | 0,5..2 | 1,0 | — |
| Matières | Matières PBR | on/off | on | oui |
| Matières | Matières modernes | on/off | off | oui |
| Matières | Relief de texture | 0..3 | 1,5 | — |
| Matières | Intensité spéculaire | 0..2 | 0,15 | — |
| Matières | Displacement | off / parallaxe / tessellation | parallaxe | oui |

**[C] Contrainte de vérification** : pour chaque ligne marquée « interrupteur individuel : oui »,
l'item qui la livre doit prouver que son OFF est **bit-identique** à un build sans elle. C'est la
règle 1.1 point 3, et c'est la porte de l'item 11.

### 6.3 Préréglages et auto-détection

**[C]** L'auto-détection choisit un **point de départ**, jamais une limite.

```
palier_de_depart :
  1. capacités : gpu_caps::detect() donne gles/desktop, version, familles de compression
     (déjà en place [M]) ; on y ajoute GL_MAX_TEXTURE_SIZE, la présence du flottant rendu,
     la présence du compute, et GL_RENDERER
  2. mesure : les 120 premières images publient measured_frame_busy_ms [M] ; le contrôleur
     d'échelle de rendu adaptatif existant sert de signal
  3. décision : le préréglage le plus élevé dont le budget mesuré tient sous la cible de
     cadence choisie par le joueur (30/60/illimité)
  4. le joueur écrase n'importe quelle ligne -> le préréglage devient « Personnalisé »
     et rien n'est plus jamais choisi pour lui
```

**[C] Grille de préréglages** (les valeurs sont un point de départ à calibrer, pas un dogme) :

| | Très bas | Bas | Moyen | Haut | Ultra |
|---|---|---|---|---|---|
| `LIGHT_TIER` | 0 | 0 | 1 | 2 | 2 |
| Atlas d'ombre | 1024 | 2048 | 4096 | 4096 | 8192 |
| Cascades | 2 | 2 | 3 | 3 | 4 |
| Ombres de contact | off | off | 8 | 16 | 16 |
| Ombre du 2ᵉ astre | off | on | on | on | on |
| AO | off | SSAO bas | HBAO moyen | GTAO haut | GTAO haut |
| Lumières / froxel | 4 | 4 | 8 | 16 | 16 |
| Environnement | table | ciel | ciel + cube 32² | cube 64² | cube 128² |
| Sondes | off | par objet | par objet | par pixel | par pixel |
| Échelle de rendu | 0,6 | 0,75 | 1,0 | 1,0 | 1,0 |

### 6.4 Le raccourci Original / Recharged

**[O] 2026-09-03 :** « ce remake pourra à tout moment passer du rendu "original" au rendu
"recharged" d'une simple combinaison de touches ».
**[O] 2026-09-06 :** « sur mobile on peut simplement avoir un bouton dédié, à la manette on
pourrait imaginer le combo L3+R3 » — puis, sur la cible : « le bouton de l'overlay tactile c'est
pour le master toggle des settings rechargés, pas juste l'éclairage ! Et l'éclairage doit avoir
son entrée, off c'est d'origine, on c'est notre refonte » — puis, sur la collision : « Et R3 pour
le navigateur de mesh... On peut dégager on s'en fiche de ce raccourcis ».

#### La cible : `recharged_master`, et rien d'autre

Le geste bascule le master. Il n'est pas remappable sur l'éclairage : c'est l'A/B du projet
Recharged entier. **L'éclairage a sa propre entrée de réglages** (§6.2), OFF = l'éclairage
d'origine, ON = notre refonte — une ligne de menu, pas un raccourci.

| Mécanisme | Cible | Où |
|---|---|---|
| Le geste | `recharged_master` | en jeu, hors menu |
| La ligne « ÉCLAIRAGE RECHARGÉ » | `recharged_lighting` | Options > Recharged |

> **⚠ J'avais tranché cette cible à la place de l'owner, dans le mauvais sens.** En révision 3
> j'avais écrit que le geste bascule `recharged_lighting`. Il n'avait répondu que sur le GESTE ;
> j'ai comblé le silence au lieu de le laisser ouvert.

#### Le geste

| Plateforme | Geste | État |
|---|---|---|
| Mobile / tactile | **un bouton dédié** dans l'overlay | **aucun conflit.** L'overlay porte déjà des boutons ajoutés ; celui-ci est masquable comme les autres. |
| Manette | **L3 + R3** | **retenu**, au prix nommé ci-dessous |
| Bureau (clavier) | une touche par défaut, remappable | hors conflit avec les raccourcis existants |

#### Le prix de L3+R3, mesuré

**[M] Aucun bouton de la manette n'est libre en jak1** : `l3` 25 sites, `r3` 13, `x` 41, `up` 36,
`down` 34, `circle` 30, `left`/`right` 32, `r1`/`r2` 25, `l1` 22, `triangle`/`square` 21,
`start` 12, `select` 7. Un geste dédié est donc forcément un accord, et il coûte quelque chose.

**Deux** conditions, et le chantier les livre ensemble :

1. **Le raccourci R3/L3 du navigateur de mesh part.** `mesh-browser-pc.gc:1939` (R3 seul en jeu →
   caméra libre), `:1946`, `:1621` (L3 dans le navigateur), et le bouton tactile « CAM » mappé sur
   `RIGHT_STICK` (`TouchOverlayView.java:268`). **[O]** l'owner l'a autorisé le 2026-09-06.
2. **L'accord s'écrit modificateur + touche, et il consomme R3.**
   `(and (cpad-hold? 0 l3) (cpad-pressed? 0 r3))` puis `(cpad-clear! 0 r3)`. Deux raisons :
   un appui simultané sur la même image n'est pas fiable ; et **[M]** `drawable.gc:1274` teste
   `(cpad-pressed? 0 select r3 start) ;; push pause` — **R3 met le jeu en pause**.
   **[M] L'ordonnancement le permet** : ce test vit dans `determine-pause-mode`, appelé depuis
   `display-sync` (`drawable.gc:1348`) **après l'envoi de la chaîne DMA**, donc à la toute fin de
   l'image. Un gestionnaire placé là où `pc-set-*` tourne déjà s'exécute avant lui. `cpad-clear!`
   est le patron établi de l'arbre (60+ sites, dont `mesh-browser-pc.gc:1940` sur R3 précisément).
> **[M] Il n'y a PAS de troisième condition — vérifié le 2026-09-06, signalé par le superviseur.**
> J'avais mis « la bascule des infos d'acteur sur L3 se re-clave » en condition 3. Faux : le site
> `pckernel-common.gc:1134` est enfermé dans `(when *debug-segment*` (ligne 1126, sous l'en-tête
> `;;;; entity debugging`), une forme **enveloppante** qui conditionne l'installation même du
> `defmethod update-pad` de `entity-debug-inspect`. Et `*debug-segment*` est **faux dans le build
> livré, sur les deux plateformes** :
>
> | Plateforme | Lancement | Chaîne | `DebugSegment` |
> |---|---|---|---|
> | Android | `gk_android_main.cpp:9552` pousse **`-boot`** | `InitParms` : `-boot` ⇒ 0 | **0** |
> | Bureau | `./gk --game jak1` — `game_args` ne porte que le passe-plat après `--`, donc vide | `arg_ptrs = {""}` ⇒ `argc == 1` ⇒ 0 | **0** |
>
> Le `defmethod` n'est donc jamais installé et la lecture de L3 n'existe pas. Reste une note, pas
> une condition : un lancement de DÉVELOPPEMENT (`-debug`, ou le redémarrage après plantage qui
> pousse `-boot -debug`, `main.cpp:712`) l'installe — un développeur qui utilise le raccourci
> verrait l'overlay d'infos d'acteur clignoter. Ce n'est pas le build de l'owner.

> **⚠ J'ai écrit « L3+R3 est impossible ». C'était faux, et c'est ma troisième erreur sur ce
> point.** La collision avec la pause est réelle, mais elle se résout par l'ordre d'exécution et
> `cpad-clear!`, deux mécanismes déjà en place dans l'arbre. Ce que je n'avais pas fait : lire
> QUI appelle `determine-pause-mode`.

#### Pourquoi pas L2+R2 (l'alternative que j'avais recommandée)

**[M] Elle n'est pas plus propre, et sur un point elle est pire.** Mon recensement la donnait
« jamais testée en paire » ; c'était faux, parce que GOAL écrit les deux touches en deux appels
distincts joints par `and`, que mon motif ne voyait pas. Le superviseur a relevé l'erreur. Sites
réels : `progress.gc:83/89/983/1034` et `progress-draw.gc:907` (derrière `*progress-cheat*`, à
`#f` par défaut, `main.gc:1594`), `main.gc:1661` et `pckernel.gc:57` (quatre touches, debug et
codes de triche) — et surtout **`hud.gc:43`, qui lit L2 maintenu SANS aucune garde** pour forcer
le HUD à l'écran. Tenir L2+R2 ferait donc apparaître le HUD à chaque usage du raccourci : un
effet de bord plus visible que l'overlay d'infos d'acteur du point 3.

#### Dans les deux cas

* Le geste **persiste** dans les réglages et affiche une **cartouche d'une seconde** nommant le
  mode actif — un joueur qui bascule par erreur doit savoir pourquoi son image a changé.
* Armé **hors menu seulement**, et jamais pendant une cinématique.
* Le graphe de passes change à la frame suivante ; les FBO sont recréés paresseusement. La
  bascule ne doit **pas** recharger le niveau.

#### Leçon de méthode, à appliquer aux prochains recensements de touches

**Deux fois de suite mon motif de recherche a produit un `[M]` faux dans le même sens** —
trop restrictif, donc « c'est libre ». GOAL écrit le symbole **nu** (`l3`, pas `'l3`) et répartit
un accord sur **plusieurs appels** joints par `and`. La règle : chercher le symbole nu sans
supposer la forme de l'expression, puis **lire les sites à la main**. C'est ce qui a sorti la
pause, et c'est ce qui aurait dû sortir `hud.gc:43`.

---

## §7 — INSTRUMENTATION ET PREUVE

### 7.1 Le contrat du harnais

**[M]** `lib/proof_run.sh` produit `reports/<id>/proof.txt` ; `validators/generic.sh` le juge et
n'accepte rien d'écrit par un humain. Le moteur DOIT donc :

1. Lire `AUTOPORT_FEATURE` / `AUTOPORT_FEATURE_ARMED` (bureau, environnement) ou
   `debug.opengoal.feature` / `debug.opengoal.feature.armed` (appareil, propriétés).
2. Émettre `FEATURE <item-id> armed=<0|1> hits=<n>`. Le validateur exige `armed=1` et `hits > 0`
   sur le bras armé.
3. Émettre **une ligne `clé=valeur` seule sur sa ligne** par grandeur, dont celle de la porte.
4. Sous `--off` : `FEATURE <id> armed=0 hits=0`, et **la même scène**. Une ablation où la
   condition mesurée est absente ne vaut rien.

**[M] LE MODULE EXISTE DÉJÀ — NE PAS EN ÉCRIRE UN SECOND.**
`game/system/autoport_proof.{h,cpp}` est le publicateur que `proof_run.sh` moissonne. Il a été
créé le 2026-09-03, pendant la rédaction de cette spec, par le chantier en cours. Son en-tête
documente précisément le trou qu'il ferme : « *grep -rn "AUTOPORT_FEATURE|debug.opengoal.feature"
game/ common/ rendait zéro le 2026-09-03, alors que proof_run.sh pose les deux depuis sa première
version* ». Tant qu'il n'existait pas, **aucun** item du backlog ne pouvait passer sa porte.

API à utiliser telle quelle :

```cpp
namespace autoport_proof {
  const char* feature_id();                 // "" si le harnais n'a rien demandé
  bool feature_is(const char* id);          // le harnais mesure-t-il CET item ?
  bool armed();                             // global — voir l'avertissement ci-dessous
  bool armed_for(const char* id);           // ← C'EST CELLE-CI QU'UN ITEM UTILISE
  void note_hit(uint64_t n = 1);            // no-op si désarmé : c'est ce qui rend l'ablation lisible
  void publish(const char* key, uint64_t v);// une ligne `cle=valeur`, la dernière gagne
  void frame_tick();                        // une fois par image ; émet le bloc périodiquement
  void flush();                             // fin de scène / fin de course
}
```

**[C] Trois règles d'emploi pour les 12 items :**

1. **`armed_for("lighting-<x>")`, jamais `armed()`.** L'en-tête du module explique pourquoi : si
   le harnais mesure l'item A avec `armed=0`, un `armed()` global désarme du même coup le
   correctif de l'item B, qui n'a rien demandé — deux features livrées se désarment l'une l'autre
   et la course ne mesure plus le binaire de l'owner.
2. **`note_hit()` au site du geste, pas au site du prédicat.** Le `hits` de chaque item est le
   dénominateur nommé au §7.2. Un `note_hit()` posé là où on *décide* au lieu de là où on *agit*
   compte des intentions.
3. **Interdit** : publier une clé qui n'a aucun site d'écriture, ou dont le seul site est dans une
   branche jamais prise. C'est une faute déjà commise dans cet arbre, et le §2.4 en documente un
   cas encore vivant.

L'armement par défaut est **VRAI** quand rien n'est posé **[M]**, et c'est délibéré : « une
correction livrée derrière un drapeau éteint par défaut n'existe pas pour l'owner ». Cette spec
suit la même logique pour ses interrupteurs (§1.1 règle 1 point 3, §6.2).

### 7.2 Les clés publiées, item par item

**[C]** `hits` est choisi pour être un **dénominateur utile**, jamais un simple témoin.

| Item | Porte | `hits` | Autres clés publiées |
|---|---|---|---|
| 0 `lighting-census` | `refset_replay_maxdiff == 0` | draws monde classés | `light_census_A..E`, `light_census_unaccounted`, `gpu_ms_<passe>`, `refset_frames` |
| 1 `lighting-unify` | `shade_variants == 1` | draws passés par `shade()` | `refpix_maxdiff_origine`, `refpix_maxdiff_recharged`, `samplers_bound_to_dummy`, `dead_lines_removed` |
| 2 `lighting-hdr` | `tonemap_sites == 1` | images passées par le tone map | `hdr_overbright_px`, `hdr_format`, `hdr_fallback_used`, `ldr_ref_delta` |
| 3 `lighting-ao-indirect` | `ao_direct_leak_px == 0` | pixels dont l'indirect a reçu l'AO | `ao_apply_site`, `prepass_normal_agreement`, `overdraw_opaque_before/after`, `ao_on_alpha_px` |
| 4 `lighting-bake` | `bake_reconstruction_maxdelta <= 2` | index de couleur vérifiés | `art_residual_p50/p95`, `art_clamped_frac`, `palette_a_bytes_changed`, `skyvis_mean`, `probes`, `emitters`, `lightbake_bytes` |
| 5 `lighting-regimes` | `regime_sun_override_wrong == 0` | images dont le régime a été lu | `env_amb_tone_delta`, `regime_hist_<0..5>`, `sun_fade_applied`, `key_dir_source` |
| 6 `lighting-shadows` | `shadow_caster_classes == 4` | pixels de sol ombrés par un acteur | `shadow_lights_active`, `cascade_texel_world_<0..3>`, `contact_shadow_px`, `shadow_atlas_bytes`, `peter_pan_px` |
| 7 `lighting-local-lights` | `lights_unjudged == 0` | pixels éclairés par une locale | `lights_extracted`, `lights_visible_p95`, `froxel_overflow_px`, `flicker_channels_bound` |
| 8 `lighting-interiors` | `probe_leak_permille <= 10` | sondes échantillonnées | `probes_loaded`, `interior_cells`, `probe_bytes`, `neighbour_vis_zero_frac` |
| 9 `lighting-actors` | `merc_legacy_light_draws == 0` | pixels merc ayant lu l'atlas | `merc_shadowed_px`, `stencil_blob_draws`, `merc_probe_samples`, `merc_gpu_ms` |
| 10 `lighting-materials` | `materials_named_but_unreached == 0` | matières atteintes au draw | `materials_with_record`, `materials_total`, `orm_packed_frac`, `checker_ok` |
| 11 `lighting-presets` | `preset_apply_mismatch == 0` | réglages posés par le préréglage | `auto_tier_chosen`, `feature_off_bitidentical_<n>`, `gpu_ms_par_preset` |

### 7.3 La garde de non-régression à deux références

**[C]** Livrée par l'item 0, **rejouée à la fermeture de chaque item suivant**.

| Jeu | Condition | Contenu | Règle |
|---|---|---|---|
| **ORIGINE-TOTAL** | `recharged_master` OFF | N vantages fixes × 8 heures canoniques × 4 niveaux | **ne bouge JAMAIS**, `maxdiff == 0` |
| **ORIGINE-LUMIÈRE** | master ON, `recharged_lighting` OFF | id. | **ne bouge JAMAIS**, `maxdiff == 0` |
| **RECHARGED** | master ON + `recharged_lighting` ON, préréglage figé | id. | ne bouge que si l'item le déclare, et seulement pour ce qu'il déclare |

**[C] Pourquoi le deuxième bras existe, et ce qu'il aurait attrapé.** À la révision 2 il n'y avait
que deux jeux : master OFF, et master ON + éclairage temps réel ON. **Aucun** n'exerçait la
configuration livrée (master ON + temps réel OFF), qui est celle qu'un joueur lance. C'est
exactement là que l'owner a trouvé des blancs brûlés après `lighting-hdr` le 2026-09-06 : les
composites hérités C et E appliquaient encore leur propre exposition et leur propre `pow(1/2.2)`,
et la nouvelle chaîne HDR en ajoutait une seconde par-dessus. Deux bras verts, la condition
absente. Le jeu ORIGINE-LUMIÈRE est le bras qui l'aurait vu, et c'est pour ça qu'il est
obligatoire.

**[C] Mécanique.** Une course déterministe : point de reprise nommé, heure forcée, entrée
neutralisée, N images, écriture des images dans `reports/<id>/refset/`, comparaison par un script
qui publie `maxdiff` (le plus grand écart absolu par canal, 0..255) et `diffpx` (le nombre de
pixels différents). Aucune image n'est une preuve : **le nombre l'est**. Le déterminisme est
atteignable **[M]** : le harnais a déjà un mécanisme de rejeu d'entrée (`Ginput-replay*`) et des
points de reprise nommés (`village1-hut`, `beach-start`, `jungle-start`).

**[C] Ce que la garde protège**, au-delà de la règle 1.1 : la soudure des maillages, les tangentes
cuites, le vent du feuillage, la densité d'herbe, l'ombre de Jak, le HUD, les polices — tous
validés par l'owner, tous dans le cadre.

### 7.4 Pièges de mesure, appris dans cet arbre

**[M]** Chacun a déjà coûté une course ou un faux vert. Ils s'appliquent à tous les items.

1. **Une ablation dont la condition est absente ne prouve rien.** Le bras désarmé doit se dérouler
   dans la même scène, au même vantage, à la même heure.
2. **Un seau « exclu » n'est pas un seau « correct ».** Si une mesure exclut des cas, le compte des
   exclus se publie à côté du compte des corrects.
3. **Mesurer sur la table source n'est pas mesurer ce qui est dessiné.** Une grandeur d'éclairage
   se lit au point de **lecture** (le fragment), pas au point de **poussée** (l'uniforme).
4. **Un compteur publié sans site d'écriture est une fausse constante.** Idem un seuil d'impression
   qui censure les petites valeurs.
5. **`stdout` redirigé est bufferisé par blocs** : `stdbuf -oL`, sinon la course se termine avant
   d'avoir écrit.
6. **Un chemin n'est pas une date** : la provenance d'un compagnon se prouve par l'empreinte de son
   contenu, pas par son emplacement.
7. **Le TIMING ne se reproduit pas d'un appareil à l'autre** : Redmi 19 img/s, Honor et bureau 60.
   Un défaut lié à une fenêtre en images ne se reproduit ni sur l'un ni sur l'autre.
8. **`(build-game)` ne livre rien au `gk` qui tourne**, et un `--target gk` partiel casse l'ABI de
   `goalc`. Une preuve prise dans ces conditions décrit un binaire qui n'existe pas.

---

## §8 — LE PLAN D'EXÉCUTION

Douze items. La chaîne de dépendances est stricte : `next_open()` ne peut en prendre qu'un à la
fois, dans cet ordre. **Les douze items sont dans `.autoport/backlog.yaml`** depuis le
2026-09-03, aux priorités **30 à 41** — donc après la file de tête en cours (11 à 20) et avant
l'ancien fond de file (205+). `backlog.yaml` est la seule vérité : il n'existe aucune autre copie
de ces items, et leurs prompts sont **régénérés** par `lib/backlog.py`, jamais édités à la main.

### Item 0 — `lighting-census`

**Objet.** Rendre mesurable l'état actuel, et figer les deux références.

**Fichiers.** `game/system/autoport_proof.{h,cpp}` **existant** (§7.1) — ne pas en écrire un second ; instrumentation dans les 5 shaders monde (un
`u_census_path` par draw, ou un compteur CPU au site de décision — au choix, mais **au site de
décision**, pas déduit) ; un script de rejeu et de comparaison dans `.autoport/`.

**Porte.** `refset_replay_maxdiff == 0`. **`hits`** = draws monde classés.
**Ablation.** `armed=0 hits=0` : le recensement ne tourne pas, aucune ligne.
**Ne change aucun pixel.** C'est vérifié par sa propre porte.

### Item 1 — `lighting-unify`

**Objet.** Cinq chemins → un. Sortie identique sur les deux références.

**Fichiers.** Nouveau `shaders/lighting/shade.glsl` ; `tfrag3.frag`, `etie_base.frag`,
`tie_wind.frag`, `shrub.frag`, `hfrag.frag` réduits à « remplir `Surface`, appeler `shade()` » ;
suppression du code mort listé en §2.4 ; `pbr_uniforms.glsl` réduit ; `background_common.cpp`
`first_tfrag_draw_setup` scindé (aujourd'hui **1 105 lignes** **[M]**, l. 2084-3189) en
`push_frame_uniforms` / `push_light_uniforms` / `push_material_uniforms` ; `FollowProbe` supprimé,
ses 8 uniformes de modulation ré-hébergés là où ils appartiennent.

**Porte.** `shade_variants == 1`. **`hits`** = draws passés par `shade()`.
**Publie aussi.** `refpix_maxdiff_origine` et `refpix_maxdiff_recharged` doivent être 0 : c'est la
condition de sortie, pas un bonus.
**Risque.** C'est le plus gros refactor du lot. Budget : 1 600 tours, 8 essais.

### Item 2 — `lighting-hdr`

**Objet.** `RGBA16F`, un seul tone map, repli déclaré.

**Fichiers.** `OpenGLRenderer.cpp` (`make_fbo`, `setup_frame`, `blit_display`, `do_pcrtc_effects`) ;
nouveau `shaders/tonemap.{vert,frag}` ; retrait des six `pow(1/2.2)` et du genou `RT_KNEE`.

**[C] AJOUT DU 2026-09-06 — cet item crée `recharged_lighting`.** C'est lui qui a exposé le
problème et il touche déjà `gfx.h` et les menus. Il livre donc, en plus : le drapeau
`recharged_lighting` (ON par défaut), son setter `pc-set-recharged-lighting!`, sa ligne de menu
« ÉCLAIRAGE RECHARGÉ » **à la place** de « Realtime Lighting », le helper qui compose les trois
niveaux, et le troisième jeu de référence ORIGINE-LUMIÈRE. Sa chaîne HDR se garde dessus.
**Et les composites hérités C et E doivent céder leur `pow(1/2.2)` et leur `u_pbr_exposure` au
site unique** : sans ça `tonemap_sites == 1` est vrai éclairage ON et vaut 3 éclairage OFF, ce qui
est exactement le double traitement que l'owner voit. Ce changement bouge des pixels dans la
configuration livrée : il se **déclare** et le jeu RECHARGED se recapture.

**Porte.** `tonemap_sites == 1`. **`hits`** = images passées par le tone map.
**Bras appareil.** Obligatoire : c'est là que le flottant rendu peut être refusé.
**Publie.** `hdr_overbright_px` (0 par construction avant), `hdr_fallback_used`.

### Item 3 — `lighting-ao-indirect`

**Objet.** Prépasse, et l'AO au bon endroit.

**Fichiers.** Nouveau `PrePass.{h,cpp}` + `shaders/prepass_{world,merc}.{vert,frag}` ;
`AmbientOcclusion.cpp` (cible : texture au lieu de blend ; entrée : prépasse) ;
`ao_composite.frag` **supprimé** (le masque de luminance et `m_scene_tex` disparaissent) ;
`shade.glsl` (lignes 2-6 de §4.2) ; retrait de tous les `dFdx/dFdy` de construction de normale.

**Porte.** `ao_direct_leak_px == 0`. **`hits`** = pixels dont l'indirect a reçu l'AO.
**Contrôle causal.** Un pixel en plein direct sans indirect : variation nulle. Un pixel purement
ambiant : variation > 0. Les deux publiés.

### Item 4 — `lighting-bake` ⭐

**Objet.** La clé de voûte. Palette B à côté de la palette A.

**Fichiers.** Nouveau `tools/light_bake/` ; nouveau `common/custom_data/LightBake.{h,cpp}`
(sérialisation, empreinte, application) ; `Tfrag3Data.h` (`TFRAG3_VERSION` bumpé, seconde
`PackedTimeOfDay` par arbre, `bent_n` par sommet) ; `LoaderStages.cpp` (lecture du compagnon) ;
`background_common.cpp` (`interp_time_of_day` sur A ou B) ; `scripts/package_game_assets.sh`.

**Porte.** `bake_reconstruction_maxdelta <= 2` (unités 1/255).
**`hits`** = index de couleur vérifiés au chargement.
**Publie.** `palette_a_bytes_changed` doit être 0. `art_residual_p50/p95`, `art_clamped_frac`.
**Périmètre.** Les 4 niveaux de la première livraison. Budget : 2 000 tours, 8 essais.
**Rappel de piège.** Bumper `TFRAG3_VERSION` **et** rebâtir `goalc` (en-tête sérialisé).

### Item 5 — `lighting-regimes`

**Objet.** La clé n'est plus supposée. L'environnement vient du ciel pour la forme, de la table
pour le ton.

**Fichiers.** `hud-classes-pc.gc` + `kmachine.cpp` (`pc-set-mood-lights!`, `pc-set-sun-fade!`,
`pc-set-mood-slot!`) ; `background_common.cpp` (la clé, le régime, la suppression de
l'écrasement inconditionnel) ; nouveau `SkyCapture.{h,cpp}` (P3) ; `shade.glsl` ;
`lighting_overrides.txt` côté assets.

**Porte.** `regime_sun_override_wrong == 0`. **`hits`** = images dont le régime a été lu.
**Publie.** `env_amb_tone_delta` (la règle 3, chiffrée), `regime_hist_<0..5>`.
**Vantages.** Un dans `village1` (clé dure), un dans `swamp` (dôme couvert), un dans `lavatube`
(source basse). Le troisième est celui qui compte : c'est le régime qu'aucune calibration
existante n'a jamais vu.

### Item 6 — `lighting-shadows`

**Objet.** Atlas tuilé, cascades stabilisées, deux astres, acteurs projetant, contact.

**Fichiers.** `background_common.cpp` (`pbr_shadow_*` réécrit en atlas ; la machinerie
`shadow_conf` / EMA / `shadow_light` supprimée) ; `Merc2.cpp` (passe de profondeur) ;
`shade.glsl` (échantillonnage, contact) ; `Shadow2.cpp` (saut par draw, pas désactivation).

**Porte.** `shadow_caster_classes == 4`. **`hits`** = pixels de sol ombrés par un acteur.
**Ablation.** Acteur retiré ⇒ `hits == 0`. C'est le test causal, les deux bras.
**Publie.** `shadow_lights_active` (doit valoir 2 pendant la fenêtre 6 h 30 – 10 h),
`cascade_texel_world_<i>`, `peter_pan_px`.
**Bras appareil.** Obligatoire.

### Item 7 — `lighting-local-lights`

**Objet.** Les lampes, torches et laves éclairent. Le lexique, les clusters, le vacillement.

**Fichiers.** `light_emitters.txt` (assets) ; `tools/light_bake` (extraction) ; nouveau
`ClusterGrid.{h,cpp}` ; `shade.glsl` (boucle de cluster) ; `hud-classes-pc.gc` +
`kmachine.cpp` (`pc-set-flicker!`).

**Porte.** `lights_unjudged == 0`. **`hits`** = pixels éclairés par au moins une locale.
**Ablation.** Liste vidée ⇒ `hits == 0`.
**Publie.** `lights_extracted` et `lights_visible_p95` par niveau, `froxel_overflow_px`.
**Dénominateur.** 62 prototypes candidats, 1 192 instances (annexe C).
**Bras appareil.** Obligatoire : c'est un item de budget.

### Item 8 — `lighting-interiors`

**Objet.** Le volume de sondes, étanche par construction.

**Fichiers.** `tools/light_bake` (placement, SH, visibilité inter-sondes) ; `LightBake.cpp` ;
nouveau `ProbeVolume.{h,cpp}` ; `shade.glsl`.

**Porte.** `probe_leak_permille <= 10`. **`hits`** = sondes échantillonnées par image.
**Publie.** `interior_cells`, `probes_loaded`, `neighbour_vis_zero_frac` (la mesure que
l'anti-fuite existe **dans la donnée**, pas seulement dans le shader).

### Item 9 — `lighting-actors`

**Objet.** Les acteurs entrent dans la scène.

**Fichiers.** `merc2.vert` (plus d'éclairage, des varyings), `merc2.frag` (appelle `shade()`),
`generic.{vert,frag}`, `emerc.{vert,frag}` ; `Merc2.cpp` (uniformes, sondes, `light-index`) ;
`Shadow2.cpp` (le saut par draw devient effectif).

**Porte.** `merc_legacy_light_draws == 0`. **`hits`** = pixels merc ayant lu l'atlas.
**Ablation.** Occulteur retiré ⇒ `merc_shadowed_px == 0`.
**Publie.** `stencil_blob_draws` (doit tomber à ~0 en champ proche), `merc_gpu_ms`.
**Bras appareil.** Obligatoire : le shading passe du vertex au fragment.

### Item 10 — `lighting-materials`

**Objet.** Le PBR devient le cas normal. Plus de « fusion ».

**Fichiers.** `shade.glsl` (les cartes comme entrées ordinaires) ; `LoaderStages.cpp` +
`CustomTextureReplacements.{h,cpp}` (empaquetage `_orm`, matière sans carte comme cas normal) ;
`surfaces.json` étendu ; retrait du bit 256 de `u_pbr_mode` et de la porte « exige une carte ».

**Porte.** `materials_named_but_unreached == 0`. **`hits`** = matières atteintes au draw.
**Publie.** `materials_with_record / materials_total`, `orm_packed_frac`, `checker_ok`.
**Remplace.** Les items `recharged-pbr-realtime-fusion` et `pbr-per-material` du backlog actuel.

### Item 11 — `lighting-presets`

**Objet.** L'échelle de qualité, l'auto-détection, et la preuve que chaque OFF est propre.

**[C] Ce qui a QUITTÉ cet item le 2026-09-06.** Le regroupement des réglages n'est plus différé
ici : la hiérarchie est décidée (§6.2) et `recharged_lighting` est créé par l'item 2. Il ne reste
à cet item que les paliers, l'auto-détection et la preuve d'orthogonalité de chaque OFF.

**Fichiers.** `gfx.h` (les réglages) ; `kmachine.cpp` + `hud-classes-pc.gc` (les setters) ;
`progress-pc.gc` (les lignes de menu) ; `GpuCaps.cpp` (les capacités ajoutées) ; le contrôleur
d'échelle de rendu existant ; le raccourci de bascule.

**Porte.** `preset_apply_mismatch == 0`. **`hits`** = réglages posés par le préréglage.
**Publie.** `auto_tier_chosen` (journalisé sur chaque appareil de test),
`feature_off_bitidentical_<n>` — un chiffre par interrupteur individuel.
**Bras appareil.** Obligatoire.

### Chaîne de dépendances

```
0 census ─► 1 unify ─► 2 hdr ─► 3 ao-indirect ─┬─► 4 bake ─► 5 regimes ─► 7 local-lights ─┐
                                               │                                          │
                                               └─► 6 shadows ──────────────────────┐       │
                                                                                   │       │
                                       8 interiors ◄──────────────────────────── (4 et 7) ─┘
                                                │
                                                └─► 9 actors ─► 10 materials ─► 11 presets
```

---

## §9 — BUDGETS

**[C]** Un item qui dépasse son budget ne sort pas sans palier. Les cibles sont par classe.

| Ressource | Aujourd'hui **[M]** | Cible | Comment on tient |
|---|---|---|---|
| Fil GOAL (Redmi) | 55 ms de dispatch | **≤ 55 ms** | Rien de nouveau par image sur ce fil. Le pont ne pousse que des scalaires. La grille de clusters vit sur le fil de rendu. |
| GPU, palier 0 | — | tenir la cadence cible | Prépasse contre surdessin ; `shade()` unique contre 1 111 lignes à 5 branches et une boucle POM à 64 pas ; paliers en programmes. |
| Mémoire, ombres | 8 à 256 Mo | **8 à 128 Mo selon palier** | Un atlas tuilé au lieu de N textures. Le 8192² **par carte** disparaît. |
| Mémoire, bake | — | ≤ 280 Ko/arbre + 2 o/sommet | Palette B, `skyvis`, `ao` sont **par index de couleur** (≤ 8192), pas par sommet. |
| Samplers, fragment | 15 / 16 | **≤ 12** | 4 `sampler3D` morts libérés ; `_orm` fusionne 3 cartes. |
| Uniformes | 79 non-samplers | ≤ 20 + 6 UBO | Les blocs remplacent les uniformes éparses. |
| Chargement de niveau | compagnon | compagnon | Le bake est hors ligne. Le chargement lit, il ne calcule pas. |
| Compilation de shaders | ~20 programmes monde | ~33 (11 hôtes × 3 paliers) | Un palier ne compile que le sien, plus le cache disque. Mesuré au premier boot. |
| Portabilité | GLES 3.2 / GL 4.3 / GL 4.1 | inchangée | Pas de SSBO, pas de compute obligatoire, forward donc pas de MRT gras. |

---

## §10 — COMPATIBILITÉ ET MIGRATION

**[C]**

| Situation | Comportement exigé |
|---|---|
| Compagnon `.lightbake` absent | Le niveau se charge et se rend comme aujourd'hui. Aucune erreur fatale. Publié : `lightbake_missing=1`. |
| Compagnon avec une mauvaise version, magie ou empreinte | Ignoré avec un `lg::warn` nommant la raison exacte, comme `.meshweld` le fait **[M]**. |
| `mood_hash` différent | Ignoré. C'est le garde-fou que `.meshweld` n'a pas et qui lui a coûté cinq bumps **[M]**. |
| fr3 reconstruit | `tfrag3_version` dans l'empreinte le détecte. |
| Pilote qui refuse `RGBA16F` | Repli `R11F_G11F_B10F`, puis `RGBA8` à exposition fixe, avec `hdr_fallback_used` publié. |
| Pilote sans compute (macOS 4.1) | Chemin CPU/fragment, mesuré. Aucune fonctionnalité perdue. |
| Pilote dont la comparaison de profondeur matérielle est fausse (Adreno 618 **[M]**) | Comparaison manuelle, comme aujourd'hui. |
| Sauvegarde d'un build antérieur | Les nouveaux réglages prennent leur défaut ; aucun réglage existant ne change de sens. |
| Modification tierce (fr3 non cuit) | Chemin d'aujourd'hui. |

**[C] Ordre de bump.** `TFRAG3_VERSION` (item 4) et la version du compagnon sont **indépendantes**.
Un changement de sémantique du bake bumpe la version du compagnon **et** ajoute une ligne à sa
table d'historique, sur le modèle documenté de `kBakeVersion` **[M]** — parce que l'empreinte est
volontairement pauvre et qu'un compagnon périmé qui passe est le pire des cas.

---

## §11 — REGISTRE DES RISQUES

| # | Risque | Gravité | Ce qui l'empêche |
|---|---|---|---|
| R1 | Perdre le rendu d'origine | **critique** | Graphe séparé sur DEUX portes (master, `recharged_lighting`), palette A intacte, `refset maxdiff == 0` sur ORIGINE-TOTAL **et** ORIGINE-LUMIÈRE rejoué à chaque item, `palette_a_bytes_changed == 0`. |
| R2 | Dénaturer les teintes | **critique** | Résidu artistique mesuré et transporté ; `env_amb_tone_delta < ε` ; tone map « Fidélité » identité sous 1 ; `lighting_overrides.txt`. |
| R3 | Un 26ᵉ round de calibration | haute | Les items 0-5 suppriment les quatre causes (5 chemins, pas de référence, prémisse fausse sur les astres, un seul régime étalon). Aucun réglage ne se discute avant `shade_variants == 1` et `tonemap_sites == 1`. |
| R4 | Le bas de gamme décroche | haute | Budget mesuré par item sur trois classes ; paliers en programmes compilés ; le goulot du Redmi est le CPU, or ce plan déplace le travail vers le GPU. |
| R5 | Le bake est faux et personne ne le voit | haute | Porte d'inversibilité **sur la donnée livrée**, vérifiée au chargement, pas sur la sortie d'un outil. `art_clamped_frac` publie les cas où le modèle n'a pas tenu. |
| R6 | Fuite de lumière dans les intérieurs | moyenne | Anti-fuite **au point de production** (visibilité inter-sondes cuite), plus `probe_leak_permille` et `neighbour_vis_zero_frac`. |
| R7 | Mélanger les deux familles d'assets | moyenne | Tableau §5.6, et le lexique publie son résidu. |
| R8 | Casser un acquis validé | moyenne | Référence RECHARGED figée à l'item 0. |
| R9 | Compagnon périmé accepté | moyenne | `mood_hash` + `tfrag3_version` dans l'empreinte. C'est la leçon des cinq bumps de `.meshweld`. |
| R10 | Explosion du nombre de programmes | basse | 33 programmes, un palier compile le sien, cache disque, mesuré au premier boot. |
| R11 | Le raccourci de bascule est déclenché par accident | basse | Combinaison non jouable, cartouche d'une seconde nommant le mode. |
| R12 | La lune verte projette une ombre en plein jour | basse | Seuil de 5 % du direct total pour attribuer une tuile ; en dessous, lumière sans ombre. |

---

## §12 — PIÈGES DE CET ARBRE

**[M]** Chacun a déjà coûté des heures. Ils ne se négocient pas.

* Un fichier GOAL neuf doit être listé dans `goal_src/jak1/dgos/game.gd` **et** `engine.gd`,
  sinon `gk` saute dans le vide au chargement avec une pile inexploitable.
* `(build-game)` ne livre rien au `gk` qui tourne : il écrit `out/jak1/obj`. Bâtir
  `out/jak1/iso/GAME.CGO` **et** `ENGINE.CGO`, puis vérifier au `grep -a` d'un marqueur neuf dans
  **chacun**.
* Tout changement d'en-tête sérialisé impose de **rebâtir `goalc`** : un `--target gk` relie
  `libcommon` avec le nouveau champ et laisse `libcompiler` sur l'ancien ⇒ SIGSEGV dans
  `serialize`, et le symptôme ne ressemble pas à sa cause. L'item 4 est exactement ce cas.
* Un `-Wreturn-type` ignoré est un **plantage arm64 garanti** : x86/GCC retombe par hasard sur une
  valeur de retour, clang/arm64 non.
* Le build arm64 livré est `build-android/`. `build-arm64/` a toutes les options à OFF et n'a
  jamais produit de binaire : un échec là-bas est un **faux rouge**.
* Ne jamais reconfigurer avec `cmake -B` un arbre déjà configuré : ça repart de zéro et écrase les
  options.
* Un `.frag`/`.vert`/`.glsl` neuf doit passer `shaders/preprocess.py` : GLES exige `#version` en
  première position, pas de `sampler1D`, pas de `noperspective`, et le fichier doit compiler sous
  **GLSL 4.10 core ET GLES 3.20** sans `#ifdef`. Le préprocesseur ne fait que des transformations
  structurelles ; toute autre différence doit être écrite portable en amont.
* Redmi `eae4df44` uniquement, tout `adb` porte `-s eae4df44`. **La SHIELD est interdite.**
* Avant toute course appareil : réveiller l'écran (un écran endormi fait
  `onResume → onPause → onStop` en une seconde, `gk` ne démarre jamais, la capture rend zéro ligne,
  et ça se lit comme « aucun défaut »).
* Jamais `pkill -f <motif>` : le motif se matche lui-même. PID exacts uniquement, jamais `claude`.

---

## §13 — CONDITION DE FIN

Les douze items sont `validated` — c'est-à-dire que l'owner l'a dit, jamais le harnais — et :

1. **Le rendu d'origine est atteignable à tout moment, par un raccourci, et prouvé bit-identique.**
2. Chaque ajout a son interrupteur, son palier, et un OFF prouvé bit-identique à son absence.
3. **Une seule fonction ombre tout ce que le jeu dessine** — décor, feuillage, herbe, eau,
   acteurs, effets.
4. Les régimes lumineux du jeu sont **lus dans sa donnée**, pas supposés : les 16 niveaux qui ne
   sont pas « Sandover en plein jour » sont éclairés selon ce que leur table déclare.
5. Les deux astres éclairent et projettent, y compris pendant les 3 h 30 où ils cohabitent.
6. Les lampadaires, lanternes, torches et la lave éclairent leurs alentours, en phase avec le
   vacillement d'origine.
7. Les intérieurs gardent leur lumière locale ; la lumière entre par les fenêtres et ne traverse
   pas les murs.
8. **Jak porte une vraie ombre, et il est éclairé comme le sol sur lequel il marche.**
9. L'occlusion ambiante assombrit les creux et ne touche jamais le soleil.
10. Le jeu tourne du Redmi au Snapdragon 8 Elite et du PC bas de gamme à la machine de fou
    furieux, avec la même liste de fonctionnalités et un palier par machine.

Et le chantier suivant — vrais matériaux, PBR par matière, tessellation, bloom, reflets — peut
commencer, parce qu'il a enfin de la lumière à réfléchir.

---
---

# ANNEXES — DONNÉES MESURÉES

Ces trois tables sont la donnée brute sur laquelle la spec s'appuie. Elles sont reproductibles :
un script qui les régénère depuis les sources doit rendre exactement ceci.

## ANNEXE A — RÉGIME PAR NIVEAU ET PAR CRÉNEAU

Source : `goal_src/jak1/engine/gfx/mood/mood-tables.gc`, 17 tables, 62 créneaux non vides.
`elev` = `direction.y` (unitaire). `lgtL`/`ambL` = luminance `(2R+4G+B)/7`, la pondération
que le moteur emploie lui-même (`levels.y`, `mood.gc:171`). `neutre` = `max|R−G|,|G−B| < 0,06`.
Le régime proposé applique les seuils du §3.2.

```
table        cr    elev   lgtL   ambL    l/a  neutre lgt RGB              regime propose
----------------------------------------------------------------------------------------------------------------
village1      1   0.250  1.309  0.352   3.72     non (1.56,1.45,0.23)     cle dure
village1      2   0.683  1.577  0.400   3.95     non (1.63,1.59,1.43)     cle dure
village1      3   0.966  1.588  0.371   4.28     non (1.64,1.60,1.44)     cle dure
village1      4   0.683  1.577  0.400   3.95     non (1.63,1.59,1.43)     cle dure
village1      5   0.250  1.109  0.377   2.94     non (1.65,1.12,0.00)     mixte
village1      6   1.000  0.500  0.304   1.64     non (0.25,0.50,1.00)     mixte
village1      7   0.483  0.338  0.460   0.74     non (0.19,0.26,0.96)     ambiante dominante
snow          1   0.250  0.792  0.414   1.91     non (0.94,0.88,0.14)     mixte
snow          2   0.966  0.479  0.533   0.90     non (0.66,0.44,0.29)     ambiante dominante
snow          3   0.250  0.729  0.404   1.80     non (1.06,0.75,0.00)     mixte
snow          4   0.500  0.118  0.429   0.27     non (0.07,0.09,0.33)     ambiante dominante
jungleb       1   1.000  0.301  0.201   1.50     non (0.29,0.28,0.40)     mixte
maincave      1   1.000  0.521  0.193   2.70     non (0.25,0.60,0.75)     mixte
darkcave      1  -1.000  0.386  0.386   1.00     non (0.30,0.40,0.50)     source BASSE
misty         1   0.933  0.877  0.374   2.34     oui (0.88,0.88,0.88)     DOME COUVERT
misty         2   0.483  0.386  0.452   0.85     non (0.33,0.35,0.64)     ambiante dominante
village2      1   0.933  0.793  0.374   2.12     oui (0.79,0.79,0.79)     DOME COUVERT
village2      2   0.483  0.259  0.446   0.58     non (0.17,0.26,0.43)     ambiante dominante
village2      3   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
village2      4   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
swamp         1   0.933  0.825  0.374   2.21     oui (0.82,0.82,0.82)     DOME COUVERT
swamp         2   0.483  0.272  0.461   0.59     non (0.17,0.26,0.52)     ambiante dominante
swamp         3   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
swamp         4   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
sunken        1   1.000  0.370  0.374   0.99     non (0.27,0.39,0.51)     ambiante dominante
sunken        2   1.000  0.197  0.446   0.44     non (0.17,0.18,0.30)     ambiante dominante
rolling       1   0.683  0.905  0.359   2.52     oui (0.92,0.91,0.87)     mixte
rolling       2   0.908  0.898  0.359   2.50     oui (0.91,0.90,0.87)     DOME COUVERT
rolling       3   0.483  0.135  0.423   0.32     non (0.09,0.14,0.23)     ambiante dominante
rolling       4   0.710  0.108  0.423   0.26     non (0.05,0.13,0.13)     ambiante dominante
firecanyon    1   0.658  0.984  0.416   2.36     non (1.10,1.06,0.47)     mixte
firecanyon    2   0.966  1.588  0.373   4.26     non (1.64,1.60,1.44)     cle dure
firecanyon    3   0.834  0.884  0.376   2.35     non (1.14,0.89,0.35)     mixte
firecanyon    4   0.483  0.299  0.455   0.66     non (0.18,0.26,0.70)     ambiante dominante
firecanyon    5  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
ogre          1   0.683  1.133  0.359   3.16     oui (1.15,1.13,1.09)     cle dure
ogre          2   0.908  1.103  0.359   3.07     non (1.14,1.12,0.94)     cle dure
ogre          3   0.483  0.169  0.423   0.40     non (0.11,0.17,0.28)     ambiante dominante
ogre          4   0.710  0.135  0.423   0.32     non (0.06,0.17,0.16)     ambiante dominante
ogre          5   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
ogre          6   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
ogre2         1   0.933  0.793  0.374   2.12     oui (0.79,0.79,0.79)     DOME COUVERT
ogre2         2   0.933  0.793  0.374   2.12     oui (0.79,0.79,0.79)     DOME COUVERT
ogre2         3   0.483  0.259  0.446   0.58     non (0.17,0.26,0.43)     ambiante dominante
ogre2         4   0.483  0.259  0.446   0.58     non (0.17,0.26,0.43)     ambiante dominante
ogre2         5   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
ogre2         6   0.574  2.000  0.000    inf     oui (2.00,2.00,2.00)     source pure (amb=0)
ogre3         1   0.666  0.536  0.357   1.50     non (0.60,0.51,0.51)     mixte
village3      1   0.250  0.000  0.414   0.00     oui (0.00,0.00,0.00)     ambiante SEULE
village3      2   0.966  0.479  0.533   0.90     non (0.66,0.44,0.29)     ambiante dominante
village3      3   0.250  0.729  0.404   1.80     non (1.06,0.75,0.00)     mixte
village3      4   0.500  0.118  0.429   0.27     non (0.07,0.09,0.33)     ambiante dominante
lavatube      1   1.000  0.146  0.354   0.41     non (0.19,0.13,0.13)     ambiante dominante
lavatube      2  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
lavatube      3  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
lavatube      4  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
lavatube      5  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
lavatube      6  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
lavatube      7  -1.000  0.494  0.000    inf     non (1.00,0.36,0.00)     source BASSE
citadel       1   1.000  0.700  0.300   2.33     non (0.75,0.72,0.50)     mixte
```

## ANNEXE B — CIEL, SOLEIL VISIBLE ET MOOD PAR NIVEAU

Source : `goal_src/jak1/engine/level/level-info.gc`. `sun-fade` absent du bloc statique vaut
`0.0` : le sprite du soleil et celui de la lune verte ne sont alors **jamais** créés
(`time-of-day.gc:45` et `:52` testent `(!= sun-fade 0.0)`). `sun-fade` est mutable à
l'exécution (`mood.gc:1677`, `:1688`).

```
niveau        mood-func                   sky   sun-fade  mood
------------------------------------------------------------------------------------------
beach         update-mood-village1        #t    1.0       *beach-mood*
finalboss     update-mood-finalboss       #t    1.0       *finalboss-mood*
halfpipe      update-mood-default         #t    1.0       *default-mood*
jungle        update-mood-jungle          #t    1.0       *jungle-mood*
test-zone     update-mood-village1        #t    1.0       *village1-mood*
training      update-mood-training        #t    1.0       *training-mood*
village1      update-mood-village1        #t    1.0       *village1-mood*
snow          update-mood-snow            #t    0.5       *snow-mood*
misty         update-mood-misty           #t    0.25      *misty-mood*
default-level update-mood-default         #t    0.0       *default-mood*
firecanyon    update-mood-firecanyon      #t    0.0       *firecanyon-mood*
ogre          update-mood-ogre            #t    0.0       *ogre-mood*
rolling       update-mood-rolling         #t    0.0       *rolling-mood*
sunkenb       update-mood-sunken          #t    0.0       *sunkenb-mood*
swamp         update-mood-swamp           #t    0.0       *swamp-mood*
village2      update-mood-village2        #t    0.0       *village2-mood*
village3      update-mood-village3        #t    0.0       *village3-mood*
citadel       update-mood-citadel         #f    0.0       *citadel-mood*
darkcave      update-mood-darkcave        #f    0.0       *darkcave-mood*
demo          update-mood-default         #f    0.0       *default-mood*
intro         update-mood-default         #f    0.0       *default-mood*
jungleb       update-mood-jungleb         #f    0.0       *jungleb-mood*
lavatube      update-mood-lavatube        #f    0.0       *lavatube-mood*
maincave      update-mood-maincave        #f    0.0       *maincave-mood*
robocave      update-mood-robocave        #f    0.0       *robocave-mood*
sunken        update-mood-sunken          #f    0.0       *sunken-mood*
title         update-mood-village1        #f    0.0       *village1-mood*
(27 entrees)
```

## ANNEXE C — PROTOTYPES TIE CANDIDATS ÉMETTEURS

```
ANNEXE C — PROTOTYPES TIE CANDIDATS EMETTEURS
Source : .autoport/reports/Grecharged-foliage-wind3/tie-census-full.txt
Denominateur : 1191 lignes de recensement (niveau x arbre x proto), 951 noms DISTINCTS, 44415 instances.
Jetons cherches dans le nom : light, lite, lamp, lant, torch, glow, flame, candle, brazier, spotlight, neon
« lava » et « crystal » sont DELIBEREMENT hors jetons : ce sont des prefixes de NIVEAU
(lava-metalplank.mb est une planche de metal du Lava Tube, pas de la lave). La lave se lit
dans la table de mood, pas dans un nom : creneaux a elevation -1.00 (annexe A).
Tout prototype liste ici DOIT recevoir un verdict dans light_emitters.txt : LUMIERE ou EXCLU.

prototype                                 inst  niveaux
--------------------------------------------------------------------------------------------------
pre-wall-a-glow.mb                          92  CIT
palmplant-base.mb                           91  JUN TRA VI1
prec-tunnel-hole-lite.mb                    83  ROL
bch-palmplant-base.mb                       80  BEA
jng-halfsphere-glow.mb                      70  JUB
torch-geo.mb                                67  INT MIS
jng-wall-a-base-glow.mb                     60  JUB
lamp.mb                                     60  JUN TRA
pre-wall-light-norm.mb                      47  CIT
vil2-sticklite.mb                           34  VI2
wall-light-norm.mb                          34  CIT
torch.mb                                    29  CIT
column-big-light.mb                         28  CIT
vil1-outdoor-light.mb                       26  VI1
pre-wall-light-norm-glow.mb                 25  CIT
vil1-planterbox-01.mb                       23  VI1
pre-wall-base-broken-glow.mb                22  CIT
tri-window-lite1.mb                         21  ROL
tri-window-lite2.mb                         21  ROL
tri-window-lite3.mb                         21  ROL
triangular-lite-top.mb                      20  JUN
triangular-lite.mb                          20  JUN
snow-forttorch.mb                           19  SNO
big-bubble-lite.mb                          17  ROL
pre-wall-light-broken-base.mb               15  CIT
lantern.mb                                  12  BEA
vil1-windowplanter-01.mb                    11  VI1
vil2-outdoor-light.mb                       11  VI2
pre-wall-light-broken-details.mb            10  CIT
pre-wall-light-broken-glow.mb               10  CIT
snow-torchpole.mb                            9  SNO
plantboss-support.mb                         7  JUB
center-wall-lite.mb                          6  JUN
jng-wall-d-glow.mb                           6  JUB
plantboss-wall-01-glow.mb                    6  JUB
plantboss-wall-01.mb                         6  JUB
prec-tunnel-gate-lite.mb                     6  ROL
vil3-lantern-miners.mb                       6  VI3
wall-top-lite.mb                             6  JUN
eggroom-wall-01-glow.mb                      5  JUB
plantboss-shaft-mid.mb                       5  JUN
jng-wall-a-just-light.mb                     4  JUB
oval-lite.mb                                 4  MIS
spotlight-tower-a.mb                         4  MIS
spotlight-tower-b.mb                         4  MIS
spotlight-tower-c.mb                         4  MIS
spotlight-tower-d.mb                         4  MIS
jng-wall-b-glow.mb                           3  JUB
jng-wall-c-glow.mb                           3  JUB
plantboss-litepod.mb                         3  JUB
cit-warpgate-clamp.mb                        1  CIT
eggroom-floor-glow.mb                        1  JUB
plantboss-floor.mb                           1  JUB
plantboss-funnel.mb                          1  JUB
plantboss-roof.mb                            1  JUB
plantboss-shaft.mb                           1  JUB
pod-center-glow.mb                           1  JUB
pod-north-glow.mb                            1  JUB
pod-west-glow.mb                             1  JUB
prec-pipes-b-light.mb                        1  ROL
snow-eggroom-glow.mb                         1  SNO
vil3-warpgate-clamp.mb                       1  VI3

TOTAL : 62 prototypes candidats, 1192 instances.
Dont 16 JUMEAUX '-glow.mb' (307 instances) : les surfaces emissives authorees par ND.
```

## ANNEXE D — LES 94 DÉCLARATIONS D'UNIFORME ACTUELLES ET LEUR SORT

**[M]** Inventaire exhaustif de l'étage fragment monde (`tfrag3.frag` + `pbr_uniforms.glsl` +
`pbr_modern_uniforms.glsl`) : **79** uniformes non-samplers + **15** samplers.
**[C]** Le sort de chacun à l'item 1 ou 5. C'est la liste de travail du refactor : rien ne doit
rester non classé.

### D.1 — SURVIVENT, déplacés dans un bloc d'uniformes (§4.3)

| Uniforme actuel | Destination |
|---|---|
| `u_pbr_exposure`, `u_mm_exposure` | `ub_frame.exposure` (fusionnés : un seul site d'exposition) |
| `u_pbr_light_dir[3]`, `u_pbr_light_color[3]` | `ub_astres` (réduits à 2 astres + le régime) |
| `u_rt_sun_dir`, `u_rt_sun_color`, `u_rt_sun_elev` | `ub_astres[0]` |
| `u_rt_moon_dir`, `u_rt_moon_color`, `u_rt_green_amp` | `ub_astres[1]` (intensité dérivée de la table, décision 4) |
| `u_pbr_shadow_mvp`, `u_rt_shadow_range`, `u_rt_shadow_res`, `u_pbr_shadow_bias` | `ub_shadow`, **par tuile** au lieu d'une valeur globale |
| `u_rt_shadow_residual` | `ub_astres` (dérivé de la force d'ombre) |
| `u_pbr_ambient` | `ub_env.amb_target` |
| `u_pbr_mat`, `u_pbr_mat2`, `u_pbr_normal_dc`, `u_pbr_height_stat`, `u_pbr_uv_per_m`, `u_pbr_height_lambda`, `u_pbr_normal_strength`, `u_pbr_height_scale`, `u_pbr_spec_intensity`, `u_pbr_emissive_str` | `ub_material` |
| `u_mm_aniso`, `u_mm_coat`, `u_mm_sss`, `u_mm_sss2`, `u_mm_flags` | `ub_material` (le stack « matières modernes » garde son interrupteur) |
| `u_pbr_mode`, `u_pbr_displacement`, `u_pbr_tess_active` | `ub_material.flags` + `#define` de palier |
| `u_fringe_fade` | inchangé : c'est de l'herbe, pas de l'éclairage |

### D.2 — SUPPRIMÉS : morts à l'exécution

| Uniforme | Pourquoi |
|---|---|
| `u_rt_probe_on` | écrit à `0` inconditionnellement par `FollowProbe::update_and_bind` |
| `u_rt_probe_origin`, `u_rt_probe_inv_cell`, `u_rt_probe_dims`, `u_rt_probe_range` | lus seulement dans la branche que `u_rt_probe_on` ferme |
| `u_rt_probe_dc`, `u_rt_probe_l1a`, `u_rt_probe_l1b`, `u_rt_probe_l1c` | **4 unités de texture** liées à un 1×1×1 noir |
| `u_rt_probe_cube`, `u_rt_probe_reflections`, `u_rt_probe_strength` | tous les sites de lecture sont derrière `u_rt_probe_on != 0` (§2.4) |
| `u_rt_flat_normal` | A/B de la normale plate ; la prépasse rend la question sans objet |
| `u_pbr_bisect`, `u_pbr_bisect2` | ~35 bits d'A/B remplacés par des interrupteurs nommés (§6.2) |
| `u_pbr_debug` | **remplacé, pas supprimé** : un sélecteur de visualisation propre survit (albédo, normale, rugosité, AO, direct, indirect, ombre, couverture de displacement). Le damier de matière n'est PAS un mode de debug — c'est une matière synthétique de `PbrDrawBinder` — et il reste, parce qu'il est le test d'acceptation que l'owner a standardisé le 2026-07-26. |

### D.3 — SUPPRIMÉS : le chemin qu'ils servaient disparaît

| Uniforme | Chemin |
|---|---|
| `u_pbr_world_relight`, `u_pbr_wr_direct`, `u_pbr_wr_indirect` | chemin E, « relight legacy » — un 3ᵉ modèle N·L par face |
| `u_pbr_legacy_shadow` | assombrissement forfaitaire des fragments non-PBR |
| `u_pbr_direct`, `u_pbr_indirect`, `u_pbr_baked_weight` | la calibration anti-double-dose : sans objet après la décomposition (§5.2) |
| `u_rt_lit_boost`, `u_rt_shadow_mul`, `u_rt_tint_lit`, `u_rt_tint_shadow` | chemin A, « modulation du baked » : remplacé par un vrai additif |
| `u_rt_detail`, `u_rt_detail_norm`, `u_rt_sun_boost` | ré-injection de détail : sans objet, le détail est DANS la palette B |
| `u_rt_shadow_conf`, `u_rt_shadow_light` | l'attribution d'une carte unique à « l'astre le plus haut » : deux astres, deux tuiles (§4.8) |

### D.4 — REMPLACÉS par l'environnement mesuré (§4.10), item 5

| Uniforme | Remplaçant |
|---|---|
| `u_rt_ambient_on`, `u_rt_ambient_model` | `ub_env` + `#define` de palier |
| `u_rt_sky_color`, `u_rt_ground_color` | SH L2 de la capture de ciel, renormalisé sur `amb-color` |
| `u_rt_sh[9]` | `ub_env.sh[9]`, **mesuré** au lieu d'analytique |
| `u_rt_env_zenith`, `u_rt_env_horizon`, `u_rt_env_ground`, `u_rt_sun_glow` | supprimés : c'étaient les 3 bandes + le lobe `pow 4` inventés |
| `u_rt_ambient_key`, `u_rt_ambient_contrast` | `ub_env.contrast` + `lighting_overrides.txt` (le contraste reste un réglage, sa direction vient du SH) |
| `u_rt_light_on` | `Gfx::recharged_active()` au niveau du choix de graphe, plus un booléen dans le shader |

### D.5 — SAMPLERS : la nouvelle disposition

| Actuel | Devient |
|---|---|
| `tex_T0` | `tex_albedo`, unité 0 |
| `tex_PBR_N` | `tex_mat_n`, unité 8 |
| `tex_PBR_R`, `tex_PBR_M`, `tex_PBR_AO` | **fusionnés** dans `tex_mat_orm` (R=AO, G=rugosité, B=métal), unité 7 — **2 unités gagnées** |
| `tex_PBR_H` | `tex_mat_h`, unité 9 |
| `tex_PBR_E` | `tex_mat_e`, unité 10 |
| `tex_PBR_S` | supprimé : le flux « specular workflow » est absorbé par `f0` dans `ub_material` |
| `tex_PBR_TH` | `tex_mat_th`, unité 11, palier ≥ 2 |
| `tex_PBR_SHADOW` | `tex_shadow_atlas`, unité 2 |
| `u_rt_probe_cube`, `u_rt_probe_dc/l1a/l1b/l1c` | **supprimés — 5 unités gagnées** |
| — | **nouveaux** : `tex_screen_ao` (1), `tex_env_cube` (3), `tex_cluster` (4), `tex_light_index` (5), `tex_prepass_depth` (6) |

**Bilan [C] : 15 samplers déclarés aujourd'hui → 12 au palier 2, 9 au palier 0.**

---

*Fin de la spec. Les douze items vivent dans `.autoport/backlog.yaml`, priorités 30 à 41.*
