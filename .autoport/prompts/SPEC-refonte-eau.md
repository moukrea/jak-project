# SPEC — REFONTE DE L'EAU DE JAK 1

> Version 1 · 2026-09-09 · écrite depuis la consigne de l'owner du 2026-09-09, validée le même jour
> (« bah je valide, beau boulot ! »).
> Statut : contrat d'ingénierie. Aucun code n'a été modifié pour l'écrire.
> La version illustrée (figures, tables complètes) est l'artifact « Refonte de l'eau de Jak 1 » ;
> ce fichier en est le texte de référence pour les items du backlog.

---

## §0 — COMMENT LIRE CE DOCUMENT

### 0.1 Marquage

Même convention que `SPEC-refonte-lumiere.md` : **[M]** mesuré dans l'arbre `physics-keira-clean`
au 2026-09-09, source citée ; **[C]** conception, une décision de ce document ; **[O]** owner, mot
pour mot, daté ; **[S]** source externe (industrie), citée en annexe B. Un chiffre sans marqueur est
une erreur de rédaction.

### 0.2 Vocabulaire fixé

| Terme | Sens |
|---|---|
| **océan** | Le renderer `ocean` de Naughty Dog : l'eau infinie des 10 niveaux côtiers. Pas les rivières, pas les mares. |
| **plan d'eau** | Une surface `water-anim` (maillage merc déformé par `ripple`) ou un `water-vol` nu. Mares, rizières, fontaine, boue, eco noir, lave, eau électrifiée. |
| **hauteur de jeu** | Ce que le GAMEPLAY lit : `ocean-get-height` ou `ripple-find-height`. Décide si Jak patauge, nage, coule. **Ne change pas.** |
| **hauteur visuelle** | Ce que le GPU dessine : hauteur de jeu + détail visuel + rides. Dépasse la hauteur de jeu d'au plus 0,45 m. |
| **rivage** | La ligne eau/sol, décrite par un champ de distance signée (SDF) cuit hors ligne. |
| **RT de rides** | Texture de hauteur en espace monde centrée sur Jak, simulée sur le GPU, injectée par événements. |
| **Eau Rechargée** | `recharged_water`. **Le maître de cette refonte.** Sous `recharged_master`, à côté de `recharged_lighting`. OFF = eau de Naughty Dog, bit-identique. |
| **compagnon** | `<niveau>.waterbake` à côté du `.fr3`, sur le patron de `.meshweld` et `.lightbake`. |

### 0.3 Fichiers de référence

| Rôle | Chemin |
|---|---|
| Océan C++ | `game/graphics/opengl_renderer/ocean/` — 13 fichiers, 12 237 lignes dont 9 223 de microcode VU1 traduit **[M]** |
| Shaders océan | `shaders/ocean_common.{vert,frag}`, `ocean_texture*.{vert,frag}` — 3 programmes |
| Océan GOAL | `goal_src/jak1/engine/gfx/ocean/{ocean,ocean-h,ocean-frames,ocean-tables,ocean-mid,ocean-near,ocean-transition,ocean-texture}.gc` |
| Plans d'eau GOAL | `engine/common-obs/{water-h,water,water-anim,dark-eco-pool}.gc`, `engine/gfx/foreground/ripple.gc`, `merc-h.gc` |
| Joueur | `engine/target/target2.gc`, `logic-target.gc:1255`, `target-death.gc` |
| Ripple / houle C++ | `game/mips2c/jak1_functions/{ripple,ocean_vu0}.cpp` |
| Buckets, graphe | `game/graphics/opengl_renderer/{buckets.h,OpenGLRenderer.cpp}`, `android/.../android_opengl_renderer.cpp` |
| Éclairage | `prompts/SPEC-refonte-lumiere.md` — `shade()` §4.2, graphe §4.1, pont §6.1, preuve §7 |
| Preuve | `game/system/autoport_proof.{h,cpp}`, `lib/proof_run.sh`, `validators/generic.sh` |

---

## §1 — CONTRAT

### 1.1 La commande

**[O] 2026-09-09 :** « faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau
genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec
tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on
marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit
impressionant, des costiques, de l'écume, des vagues distinctes sur le rivage (qui épouse le rivage
avec l'écume et compagnie), ça c'est pour la mer mais il nous faut aussi repenser les points d'eau
hors mer, puis les cascades d'eau et l'intéraction de ses dernières avec l'endroit où elles se
jettent [...] faut que ça claque mais pas que ce soit photoréaliste car le jeu est stylisé (ça ferait
tâche) »

### 1.2 Les six règles non négociables

**Règle 1 — L'original ne disparaît jamais, et l'eau a son propre interrupteur.**
**[O] 2026-09-09 :** « la refonte de l'eau doit pouvoir être toggled off individuellement aussi, ou on
retrouve l'eau vanilla. »
`recharged_water` est une ligne de menu à lui seul, sous le master, à côté de `recharged_lighting`.
Master OFF *ou* `recharged_water` OFF : graphe de Naughty Dog, bit-identique, prouvé par
`refset_replay_maxdiff == 0`. Aucune de nos passes n'est créée, aucun compagnon n'est lu. On peut
garder l'éclairage Rechargé et retrouver l'eau vanilla, ou l'inverse. Chaque sous-réglage a le même
contrat à son échelle.

**Règle 2 — La hauteur de jeu ne bouge pas.** `ocean-get-height` et `ripple-find-height` restent les
sources du gameplay **[M]** (`water.gc:587-600`, `rigid-body.gc:252`, `fisher.gc:775`). Le visuel
s'ajoute PAR-DESSUS, borné : |visuel − jeu| ≤ 0,45 m, sous le seuil de pataugeage de 0,5 m
(`water-h.gc:100`). Ce chantier est visuel : il ne touche à aucune physique.

**Règle 3 — La stylisation prime sur la physique.** Structure physique (Fresnel, absorption,
conservation), apparence décidée par des tables : couleurs par paliers, écume à bord net, éclats
plutôt que bruit. Pas de FFT, pas de bruit haute fréquence (§4).

**Règle 4 — Rien de nouveau par image sur le fil GOAL.** Le Redmi plafonne à 19 img/s sur le fil GOAL
arm64 **[M]** (spec éclairage §1.3). Le pont ne pousse que des scalaires ; la simulation vit sur le
fil de rendu. +0 appel FFI par image, +1 par événement d'eau.

**Règle 5 — L'eau est éclairée par `shade()`.** `SURF_WATER = 8` existe dans le contrat de `shade()`
**[M]** (spec éclairage §4.2). Une seule fonction ombre le décor, les acteurs et l'eau. Aucun second
modèle de lumière.

**Règle 6 — Le pire appareil est un banc d'essai, pas la cible.**
**[O] 2026-09-09 :** « tu pense encore et toujours que la target c'est le Redmi. non ça va aller sur
PC, des devices hyper puissantes, des devices faibles... donc faut pas focus sur le pire, le pire sert
de test et on peut avoir des réglages variables avec plus ou moins de techno embarquées et qualité
d'effets a guise avec des options customisables ! »
**[C]** Conséquence : ce document conçoit d'abord le palier **Ultra**, puis retire vers le bas. Un
palier n'est qu'un jeu de valeurs par défaut posé sur des réglages individuels ; aucun réglage n'est
verrouillé par le palier. Tessellation, SSR, RT haute résolution, planaire existent dans le moteur et
sont livrés ; ils sont OFF par défaut là où le matériel ne suit pas.

### 1.3 Les décisions tranchées **[C]**

| # | Question | Décision | Pourquoi |
|---|---|---|---|
| 1 | Déformation | **Grille clipmap en vertex + tessellation par-dessus.** La clipmap est le socle à tous les paliers ; la tessellation existante (`tfrag3_tess.*`, détection `Shader.cpp:36-111`) raffine l'anneau proche ×2 à ×8 aux paliers Haut et Ultra, réglable, pilotée par la distance et l'énergie des rides. | Le socle garantit l'effet partout ; la tessellation le rend impressionnant. ARM : Mali sans unité de tessellation dédiée **[S]** → OFF par défaut là, jamais interdite. La détection à chaud a coûté trois rounds (« tess still falls back ») **[M]** : le socle n'en dépend jamais. |
| 2 | Vagues | **Les 64 frames de ND restent la houle de jeu** ; 4 à 8 ondes de Gerstner de faible amplitude et deux cartes de normales portent le détail. | Règle 2. GPU Gems : « fine waves in the texture dominate realism » **[S]**. La FFT produit le bruit HF que la DA bannit. |
| 3 | Rivage | **SDF de rivage cuit hors ligne** dans `.waterbake`, plus depth fade écran pour le dynamique. | Crest : l'écume par profondeur a une largeur dépendante de la pente **[S]**. Des vagues qui marchent vers la côte exigent une distance. Patron `.lightbake`. |
| 4 | Reflet | **Échelle à quatre crans** réglable : ciel analytique → cube capturé (P3 éclairage) → planaire sur plans immobiles → SSR sur toute l'eau (Ultra), cube en repli. | Genshin : ciel 128²/image, SSR console seulement **[S]**. NiloCat : SSPR < 1 ms (Adreno 630) à 8 ms (Adreno 506) **[S]** : un cran de menu, pas une interdiction. |
| 5 | Où dessiner | **Après tous les opaques et les alphas**, à la place du bucket 63, avec une copie unique de couleur + profondeur. | Le mid écrit la profondeur en `GL_ALWAYS` au bucket 4, AVANT le monde **[M]** : la profondeur de scène y est illisible. |
| 6 | Première livraison | **Quatre lieux** : plage de `beach` (mer + rivage), fontaine et rizières de `village1`, chutes de `jungle` (cascades + rivière), bassin d'eco noir de `misty`. Le reste ensuite. | Un lieu par famille de surface (§2). |

### 1.4 Hors périmètre

* **Jak 2 et Jak 3.** Leur `TextureAnimator` et leurs buckets TFRAG/TIE WATER ne servent pas à jak1
  **[M]** (`TextureAnimator.cpp:294` : `ASSERT_NOT_REACHED` pour jak1).
* **La physique, toute la physique.** **[O] 2026-09-09 :** « ça n'a aucun rapport avec la physique de
  Keira, ni peut-être même la physique tout court... avec la physique peut-être mais dans le sens ou
  Jak interagit avec l'eau, et on y est pas encore du tout ! on a potentiellement tout un chantier sur
  un moteur physique vraiment carré, mais c'est un truc qui n'a pas encore été mis en backlog, ça peut
  rester sur des trucs à faire "après la physique" et en attendant simuler "pour de faux" ». L'interaction
  est *simulée pour de faux* : une surface qui réagit à des événements, sans force en retour, sans
  flottabilité, sans courant qui pousse. Le couplage réel appartient à un chantier « moteur physique »
  hors backlog ; §9 lui réserve une case sans item.
* **La simulation de fluide volumique** (SPH, Navier-Stokes, lattice-Boltzmann).
* **Le ray tracing, Vulkan.**
* **Les sources de Naughty Dog ne se réécrivent pas.** On LIT `ocean*.gc`, `water*.gc`, `ripple.gc`.
  Notre GOAL vit sous `goal_src/jak1/pc/`.
* **Le son.**

---

## §2 — ÉTAT DES LIEUX **[M]** (2026-09-09, deux enquêtes en lecture seule)

### 2.1 L'océan : une animation cuite, pas une simulation

| Grandeur | Valeur | Source |
|---|---|---|
| Hauteurs de houle | 32 × 32 int8, **64 frames** cuites, 64 Ko | `ocean-h.gc:107-111`, `ocean-frames.gc:10` |
| Cellule / période | 3 m / **96 m** (modulo 32) | `ocean.gc:16-35` |
| Cadence | t = integral-frame-counter × time-factor/5 ; frame = (t≫5) & 63 | `ocean.gc:463`, `ocean_vu0.cpp:31-36` |
| Injection, propagation, sillage | aucun | interpolation linéaire entre deux frames |
| Amplitude | ≈ ±0,75 m (int8 × échelle VU0) | `ocean-vu0.gc:11` |
| Texture d'océan | cible 128 × 128 RGBA8, 8 mips, 2 112 sommets, rendue **deux fois** par image | `OceanTexture.h:41,112-114`, `ocean.gc:482,501` |
| « Mousse » | alpha des mips = 1 / 0,49 / 0 dès le mip 2 | `OceanTexture.cpp:427-431` |
| Reflet | env map **statique** `environment-ocean-alphamod` ; aucune cubemap | `ocean-texture.gc:127` |
| Grille mid | 6 × 6 tuiles de 768 m, sous-cellules 96 m, 6 niveaux d'index | `ocean-mid.gc:833-834, 217-222` |
| Transition / near | sous-cellules 24 m ; near seulement si \|cam.y\| < 48 m | `ocean-transition.gc:337`, `ocean.gc:498` |
| Couleurs de rivage | 2 548 rgba (52 × 49) par carte, 4 couleurs `ocean-near-colors` | `ocean-h.gc:51-52, 85-89` |
| Écume nommée | `grep foam ocean/` : 0 ; rivage = masque d'alpha seau `GL_ZERO, GL_ONE` | `CommonOceanRenderer.cpp:257-261` |
| Lointain | un quad plat `far-color` | `ocean.gc:63-69` |
| Niveaux à océan | 10 (3 cartes : village1, village2, sunken) | `level-info.gc`, `ocean-tables.gc:11208-11266` |
| Ordre | mid+far au **bucket 4**, Z écrit `GL_ALWAYS` ; near au 63 sans Z | `buckets.h`, `CommonOceanRenderer.cpp:464-551, 280-357` |
| Mélange env map | `GL_DST_ALPHA, GL_ONE` : l'alpha de destination est un facteur réel | `CommonOceanRenderer.cpp:486-503` ; `hdr.cpp:36-40` refuse `R11F_G11F_B10F` pour ça |
| Culling / découpe | 36 sphères (6×6), masques 8×8 bits par tuile | `ocean-h.gc:48-49`, `ocean-mid.gc:452-460` |

La houle cuite est **lue par le gameplay** à quatre endroits : elle se conserve comme couche de base.

### 2.2 Les plans d'eau : 102 entités, 46 maillages, 4 sinus

| Niveau | Surfaces | Type et hauteur | Remarque |
|---|---|---|---|
| beach | 8 water-vol | suivent l'océan (wt08), h 0 | aucun maillage propre |
| village1 | 8 water-vol + 4 merc | rizières looks 43/45/46 (1,3 / 2,3 / 3 m), fontaine look 44 (11 m) | groupe de particules 9 items `village1-part.gc:885` |
| jungle | 3 water-vol + 1 merc | rivière look 34, 20,2 m, ripple | 4 groupes de cascade `jungle-part.gc:525-575` |
| misty | 10 water-vol + 12 merc | 11 boues (wt18) 16 à 28 m ; 1 eco noir létal | deux jeux d'ondes |
| village2 | 7 water-vol + 1 merc | seau look 47 | 6 groupes cascade/jets `village2-part2.gc` |
| training | 5 water-vol + 1 merc | look 36, 16 m | 2 cascades + 4 geysers |
| rolling | 2 merc | looks 38/39, sans éclaboussure | |
| sunken / sunkenb | 12 + 3 merc | électrifiée looks 0-12 (deadly-fade, wt19), eco noir, hélice | ≈ 45 émetteurs de bulles, `whirlpool.gc` |
| maincave / darkcave / robocave | 6 + 1 + 1 merc | eco noir 15-19, eau de grotte 14/37 (violet) | 72 + 24 émetteurs de gouttes |
| ogre / village3 / lavatube | 1 + 1 + 1 merc | lave (global-scale 0,5 m), 'heat | acteurs merc `lavafall` |
| finalboss | 1 merc | eco noir look 41 | |
| snow, citadel, firecanyon, jungleb | 0 | — | |

Maillage merc déformé par `ripple` : au plus **4 sinus** par surface (`merc-h.gc:252-268`), 16
requêtes par image, `global-scale` 0,75 m (lave 0,5 m), fondu 40 à 60 m (`ripple.gc:107-146`). CPU
(mips2c `ripple.cpp`), lié sur arm64. Textures **statiques** : pas de `TextureAnimator` jak1, pas de
`texture-anim` GOAL, seulement le `texscroll` merc (`bones.gc:120-137`).

### 2.3 Le joueur

`water-control` sur Jak au joint 9 : `swim-height` 2 m, `wade-height` 0,5 m, `ripple-size` 0,4 m
(`logic-target.gc:1255`, `water-h.gc:100-101`). États `target2.gc:1066-1557` : wade-stance/walk,
swim-stance/walk, swim-down, swim-up, swim-jump. Éclaboussures : `group-part-water-splash` (40) et
`-small` (41), 20 specs redimensionnés par `part-water-splash-callback` (`water.gc:223-281, 776-862`).
Entrée dans l'eau : `water-control-method-15` (`water.gc:869-885`). PNJ avec `water-control` :
sharkey, yakow, junglefish, swamp-rat, projectiles. Tout existe pour les *événements* ; la *surface*
ne réagit pas.

### 2.4 Les cascades : des particules devant une texture fixe

Aucune classe GOAL, aucun acteur ne dessine une nappe. Chutes de `jungle`, `village2`, `training`,
`beach`, fontaine de `village1` : **uniquement** des groupes sparticle (`falls-particle`, `middot`,
`bigpuff`, fondu 70 m). La nappe est de la géométrie de niveau (tfrag/tie) à texture statique, non
identifiable depuis GOAL. **Aucune caustique** (`update-mood-caustics` = cycle de palette sunken,
`mood.gc:621-628`), aucun reflet du ciel, aucune réfraction.

### 2.5 Ce que notre couche a déjà fait

* `Gwater-ocean-render` (archivé) : builders mips2c océan sur arm64, renderers enregistrés dans
  `android_opengl_renderer.cpp:709-719`. `Gwater-lod` : PASS sans code.
* `lod-force-ocean` (`pckernel-h.gc:236`) : **réglage mort**, aucun consommateur. À retirer (item 0).
* L'AO tague au stencil les pixels d'océan au bucket 4 (`OpenGLRenderer.cpp:1661-1672`) : correctif
  de l'emplacement erroné de l'océan, qui disparaît avec la décision 5.
* `lighting_census.cpp:73-80` chronomètre `kPassOcean` (`gpu_ms_ocean`).
* Plateforme : GL 4.3 core (x86), GLES 3.2 (Android, shaders figés `kChunks`, `#version 320 es`),
  FBO RGBA16F repli RGBA8, profondeur en texture `DEPTH24_STENCIL8` quand l'AO est armée, copie
  d'écran `DepthCue` au bucket 64. Pas de compute, pas de geometry shader dans les 123 shaders.

---

## §3 — CE QUE L'INDUSTRIE FAIT (veille du 2026-09-09, sources annexe B)

| Thème | Ce qu'ils font | Ce qu'on retient |
|---|---|---|
| Forme de la mer | GPU Gems : 4 Gerstner en vertex + ~15 dans une normal map 256² **[S]**. Sea of Thieves : FFT, shading non-PBR volontaire. Horizon FW : aucune sim temps réel, vagues cuites Houdini **[S]**. Wind Waker : plan plat + 3 textures. | Gerstner + normales. Le cuit hors ligne est une voie de studio. |
| Rivage, écume | Crest : depth cache cuit ; écume par profondeur, largeur dépendante de la pente **[S]**. Cyanilux : UV 0→1 vers la côte, vague = cos(t·v + uv·3,2) **[S]**. HFW : front = une coupe transversale cuite. Wind Waker / Genshin : Voronoi à bord net. | SDF cuit (jump flood) = la coordonnée « distance à la côte ». Vagues = f(distance, temps). |
| Interaction | RT de rides top-down suivant le joueur, 1024² PC / 128-256² mobile, lue en vertex et fragment **[S]**. Équation d'onde 2D ping-pong. SoT : depth buffer projeté dans la sim **[S]**. | Une RT en espace monde, injectée par événements, partagée océan / plans / cascades. |
| Optique | Réfraction = UV + normale × force sur une copie ; mobile : une seule copie ½ (Unity) **[S]**. Absorption par paliers. Reflet : Genshin ciel 128² **[S]**. SoT : deux couleurs + masque de crête. Caustiques : Voronoi projeté, 3 échantillons RGB (Ameye) **[S]**. | Un fragment shader à une copie près. Cube de ciel P3 = reflet de base. |
| Petits plans | Deux normales world-space scrollantes. Sunshine : 2 textures 64² **[S]**. Planaire réservée aux petits plans immobiles **[S]**. | Le maillage merc et son ripple CPU restent ; le shader change. |
| Cascades | Alisavakis : bruit étiré, posterisation round(n·5)/5, écume basse par step **[S]**. Catlike : flow 2 phases décalées de 0,5 **[S]**. | Bandes posterisées + flow, anneau d'écume, impulsion continue à l'impact. |
| Mobile | ARM : pas d'unité de tessellation sur Mali **[S]**. Tile-based : une seule copie. RGBA16F « device-dependent ». | Clipmap vertex-only comme socle. Repli RGBA8 pour la RT. |

Non trouvé : talk technique eau pour Rift Apart, GoW Ragnarök, Kena, Astro Bot, Crash 4, Spyro
Reignited, Sonic Frontiers. Aucun chiffre de ces jeux n'est cité.

---

## §4 — DIRECTION ARTISTIQUE **[C]**

Sept invariants :

1. **Couleur à 3 paliers** : peu profond (turquoise, fond visible), moyen (bleu du niveau), profond
   (`far-color` ND). Seuils par niveau, pas Beer-Lambert brut.
2. **Écume à bord net** : smoothstep serré sur Voronoi tilée. Trois écumes : intersection, rivage, crête.
3. **Spéculaire en éclats** : lobe serré + étincelles seuillées. Fresnel plafonné, jamais 1 à l'horizon.
4. **Pas de bruit HF** : deux cartes de normales à 4 m et 12 m, lentes. Aucune octave sous 1 m.
5. **SSS à deux couleurs** (SoT) : crête éclairée par-derrière = couleur « lagon » par niveau.
6. **Animation lente et lisible** : vague de rivage toutes les 6 à 8 s ; rides amorties en 2 s.
7. **La mer est tranquille, mais elle a des vagues.**
   **[O] 2026-09-09 :** « pour la mer, j'attends quand même des vagues sur le rivage, on voit bien
   l'eau monter et descendre dans le jeu, on perçois que c'est plus par contrainte technique qu'ils ont
   pas mi de vagues que par choix. ça justifiera l'écume et ça aura un effet Waouw. bien sûr on est pas
   sur des vagues énormes et un tempête, faut rester cohérent la mer a l'air tranquille, donc les
   vagues sont tranquilles »
   **[M]** La houle ND monte et descend de ±0,75 m sur 96 m ; le rivage est un masque d'alpha. Il y a
   un mouvement vertical, il n'y a pas de vague qui arrive. §5.5 construit des vagues géométriques
   vraies, calmes, qui arrivent une à une, se cambrent, déferlent et remontent le sable.

Huit matières, paramétrées dans `water_materials.txt` (§5.8), jamais dans le shader :

| Matière | Où | Distingue | N'a pas |
|---|---|---|---|
| Mer | 10 niveaux côtiers | houle ND + Gerstner, vagues de rivage, SSS lagon, caustiques, étincelles | — |
| Rivière | jungle | flow map, écume aux rochers | vagues de rivage, houle |
| Mare / rizière / bassin | village1, training, rolling, grottes | calme, reflet fort, rides dominantes, planaire (Haut+) | houle, écume de crête |
| Fontaine, jets | village1, village2, geysers | jet en maillage UV panning + anneau de rides continu | — |
| Boue | misty | mate, opaque, rides lentes (amortissement ×4) | transparence, reflet, caustique, écume blanche |
| Eco noir | misty, sunken, grottes, finalboss | opaque, émissif violet en bord de rides, filaments sombres | reflet du ciel, caustiques claires |
| Lave | ogre, village3, lavatube | émissive HDR, flow lent, croûte Voronoi, lumière locale | Fresnel, transparence, écume |
| Électrifiée | sunken | eau claire + arcs émissifs sur les crêtes, pulsés par `deadly-fade` | — |

---

## §5 — ARCHITECTURE D'EXÉCUTION **[C]**

### 5.1 Le graphe de passes

Le graphe ORIGINE ne change pas d'une ligne. Graphe RECHARGED (`recharged_water` ON) :

| # | Passe | Écrit | Lit | Palier min. |
|---|---|---|---|---|
| W1 | **RT de rides** : équation d'onde 2D, une itération/image, ping-pong ; hors bucket, avant le monde, comme P1-P5 | R16F 256² (repli RGBA8 encodé) + écume R8 | file d'impulsions, position de Jak | Moyen (Très bas = statique) |
| — | bucket 4 (`OCEAN_MID_AND_FAR`) et 63 (`OCEAN_NEAR`) : **le DMA est consommé, rien n'est dessiné** ; les renderers ND restent vivants pour avancer le DMA | — | — | — |
| W0 | **Copie de scène** après les alphas, `DepthCue` la partage | couleur + profondeur (½ ou pleine) | FBO de scène | Très bas (profondeur seule) |
| W2a | **Océan** : clipmap 3 anneaux déplacée en vertex, à la position du bucket 63 | scène RGBA16F | houle ND 32² (texture), Gerstner, RT, SDF, W0, cube P3 | Très bas |
| W2b | **Plans d'eau** : maillages merc (buckets 58/59), programme `merc2_water` | scène | ripple CPU déjà appliqué, RT, W0, matières | Très bas |
| W2c | **Cascades** : prototypes listés, matériau flow | scène | flow, anneau, W0 | Très bas |
| W3 | **Planaire / SSR** | RGBA16F ¼ ou ½ | monde | Haut / Ultra |
| — | **Caustiques** : pas une passe ; `shade()` lit une texture projetée pour tout fragment sous le plan d'eau | — | hauteur d'eau, texture, `floor_depth` | Très bas |
| — | **Sous l'eau** : brouillard teinté + fenêtre de Snell, dans W2 vu par-dessous et au tone map | — | caméra vs plan | Très bas |


**[C] Amendement du 2026-09-09 (dossier « stock 60 img/s ») :** W0 se place AVANT l'invalidate de depth/stencil posé par `perf-fbo-passes` (commentaire nommé dans les deux renderers) ; la porte `water_scene_copies_per_frame == 1` est inchangée.

### 5.2 Le modèle de hauteur à trois couches

```
hauteur de JEU     = A                      (ocean-get-height / ripple-find-height, INCHANGÉE)
hauteur VISUELLE   = A + B + C              (vertex shader)
  A  houle ND      : 32×32 int8 × 64 frames, période 96 m, ±0,75 m — captée au DMA near
                     (ocean-near-add-heights, 2 × 2048 o) → texture R8 32², bilinéaire, même modulo 32
  B  détail visuel : 2..8 ondes de Gerstner, λ 6 à 30 m, Σ amplitudes ≤ 0,25 m au large ;
                     s'efface devant la vague de rivage (§5.5) qui prend sa place : vague ≤ 0,30 m
  C  RT de rides   : ≤ 0,20 m (≤ 0,10 m près de la côte), amortie ~2 s
  borne            : |visuel − jeu| ≤ 0,45 m < wade 0,5 m — publiée : water_visual_excess_mm
plans d'eau (merc) : A' = ripple CPU de ND (intact), B' = normales seules, C = la MÊME RT
```

La hauteur de jeu et la couche A visuelle sont la *même fonction* évaluée deux fois. Aucun GOAL
réécrit, le fil GOAL ne fait rien de plus.


**[C] Amendement du 2026-09-09 (dossier « stock 60 img/s ») :** le calcul GOAL de la houle (`ocean-interp-wave`, `ocean-generate-verts`) n'a lieu qu'avec une carte d'océan (`perf-ocean-idle`) ; la couche A en dépend et ne rétablit pas ce calcul sans carte.

### 5.3 La clipmap d'océan

| Anneau | Étendue | Pas | Sommets | Contenu |
|---|---|---|---|---|
| 0 | 96 × 96 m | 0,75 m | 128² (64² Très bas, 256² Ultra) | A + B + C, rivage, réfraction |
| 1 | 384 × 384 m | 3 m | ≈ 15 400 | A + B, rivage |
| 2 | 4 608 × 4 608 m (= 6 tuiles ND) | 36 m | ≈ 15 400 | A, `far-color` |

VBO statique (≈ 47 000 sommets), offset caméra en uniforme, morphing de bord (geo-mipmap ARM), grille
**snappée au pas** de l'anneau. Découpe par les 36 sphères et les masques 8×8 de la carte ND (texture
de masque 48², 1 bit). **Tessellation par-dessus** (Haut, Ultra) : anneau 0 en patchs, ×2 à ×8, facteur
= f(distance, énergie locale de la RT) ; état effectif publié `water_tess_level_effective`.

### 5.4 La RT de rides et la file d'impulsions

Un champ de hauteur **en espace monde** sur 48 × 48 m (96 m Ultra) centré sur Jak
(`recharged_jak_pos` déjà poussé **[M]**, `gfx.h:414`).

```
h_new = 2·h[t] − h[t−1] + c²·Δh[t]       // stencil 5 points, c² ≤ 0,5
h_new *= damping                        // 0,985 eau, 0,94 boue, 0,97 lave
h_new += Σ impulsions                   // disques gaussiens (rayon, force)
écume = max(écume·0,97, |Δh_new|·k)     // canal R8
re-projection par pas entiers de texel quand Jak bouge (sinon l'écume glisse — SoT)
```

**Simulé pour de faux, assumé** : la RT lit des événements et dessine leur conséquence ; elle ne pousse
rien, ne porte rien. Un futur moteur physique en devient producteur et consommateur sans changer sa
nature — c'est pourquoi elle est en espace monde.

Producteurs de la file (fil de rendu) :
* **Sillage de Jak** : dérivé de la position et de la hauteur de jeu poussée (§7). Aucun GOAL.
* **Événements** : entrée, sortie, pas, attaque tourbillon, PNJ. Un appel FFI `pc-water-impulse!` posé
  *au site où ND lance déjà l'éclaboussure* (`splash-spawn`, `water.gc:776`). Un appel par événement.
* **Bases de cascade et jets** : impulsion continue à position fixe (`water_falls.txt`), sans GOAL.

Éclaboussures : les deux groupes sparticle ND restent ; s'y ajoute un maillage (anneau + gerbe 12
pétales, 0,6 s, bord net, teinté par la matière), émis par le moteur au même événement.


**[C] Amendement du 2026-09-09 (dossier « stock 60 img/s ») :** `pc-set-water-height!` et `recharged_jak_pos` suivent la règle 5 de la spec lumière §6.1 (slot par image de logique, jamais un pointeur lu par le fil de rendu).

### 5.5 Le rivage : un champ de distance cuit, et de vraies vagues

Compagnon `<niveau>.waterbake`, par plan d'eau (océan compris) :

| Champ | Format | Produit par | Sert à |
|---|---|---|---|
| `shore_sdf` | R16 signé, 1 texel = 1,5 m (océan) / 0,5 m (plan), jump flood depuis le masque « collision à h ± 0,3 m » croisé avec le fr3 | `water_bake` | bandes d'écume constantes, vagues f(d), sable mouillé, fondu du déplacement |
| `shore_dir` | RG8, gradient normalisé | id. | direction de marche des vagues |
| `floor_depth` | R16, raycast top-down sur la collision | id. | couleur par paliers et caustiques sans copie de profondeur (Très bas) |
| `flow` | RG8, optionnel | outil ou `water_flow_<niveau>.png` | rivières, cascades, geysers |

**Une vague de rivage est une vraie vague** (vertex, vue de profil), calme, en quatre phases sur d :

| Phase | d (m) | Ce qui se passe |
|---|---|---|
| Houle | 40 → 12 | Gerstner λ 12 m, période 7 s, amplitude 0,15 m, le long de `shore_dir` ; remplace B |
| Cambrure | 12 → 3 | amplitude → 0,30 m, raideur Q 0,2 → 0,8 : la crête s'affine et penche vers la côte ; ligne de SSS |
| Déferlement | 3 → 0 | Q > 0,7 : la crête émet une bande d'écume nette qui glisse vers d = 0, se disperse en dentelle 2 s ; amplitude → 0,1 m |
| Jet de rive | 0 → −4 | lame de 2 cm sur le sol qui avance de 3 à 4 m puis se retire ; sable mouillé (albédo × 0,6, roughness 0,15 via `shade()`) ; dentelle 3 s à la limite |

```
phase = d/λ_shore − t/T_shore ; env = smoothstep(40,12,d)
amp   = mix(0.15,0.30,smoothstep(12,3,d)) · smoothstep(−1,1,d) ; Q = mix(0.2,0.8,smoothstep(12,3,d))
vague = gerstner(phase, amp, Q, −shore_dir) ; B_large *= (1−env)
déplacement = A + B_large + vague + C           // borne totale ≤ 0,45 m
écume_crête = smoothstep(0.65,0.75, Q·crête(phase)) · voronoi(uv + s·t)
variation   = bruit 1D le long de la côte, une ligne par front (HFW)
```

**Tranquille par construction** : amplitude ≤ 0,30 m, une vague par tranche de 12 m, aucune écume au
large (B ne dépasse jamais Q = 0,3). Valeurs par niveau dans `water_overrides.txt`. Publié :
`shore_wave_amp_max_mm ≤ 300`, `shore_runup_max_m ≤ 4`, `shore_wave_period_s ≈ 7`.

**Pourquoi la règle 2 tient** : sur la plage la hauteur de jeu vaut 0 ; la vague ajoute ≤ 0,30 m, le
jet de rive est une lame de 2 cm sur le sol. Jak peut avoir de l'écume aux chevilles sans que le jeu le
sache, jamais de l'eau aux genoux.

Le depth fade écran (W0) complète le SDF pour le dynamique (Jak, PNJ, rochers, bateaux).

### 5.6 Le matériau d'eau et `shade()`

Chunk `shaders/water/water_surface.glsl`, inclus par W2a, W2b, W2c :

```
1. N   = normale géométrique (dérivée analytique de A+B en vertex, JAMAIS dFdx) ⊕ 2 normal maps ⊕ ∇(RT)
2. F   = mix(f0_mat, 1, pow(1−N·V,5)) · fresnel_ceiling_mat      // plafond < 1
3. réfraction : uv + N.xy·k_mat·(1−depth_fade) ; REJET si l'échantillon est devant la surface
4. d_w = min(depth_scene − depth_surface, floor_depth) ; couleur = palier3(d_w, table_mat)
5. T   = mix(couleur_eau, scene_W0, exp(−d_w·k_abs_mat)) · (1−F)
6. Surface s : albedo 0, f0 0.02, roughness rough_mat, N, P, SURF_WATER → L_surf = shade(s)
7. SSS : L_surf += sss_color · max(0, dot(V,−L_sun)) · crête(A+B) · (1−F)
8. étincelles : + sun_color · step(0.985, dot(N_hf,H)) · sparkle_mask(t)        // Moyen+
9. écume : mix(T + L_surf, écume_color · shade_diffuse, écume_totale)             // albédo blanc éclairé
10. émissif de matière (lave, eco noir, arcs)
11. brouillard ND, puis sortie linéaire vers le tone map P9
```

Invariants testables : aucun `dFdx` pour N ; la réfraction ne lit jamais un pixel devant la surface ;
`F ≤ fresnel_ceiling` ; tables à zéro et sans copie → `couleur_eau · brouillard`.

### 5.7 Cascades et jets

La nappe est de la géométrie de niveau **[M]** : l'item 0 la nomme. `water_falls.txt`, un verdict
par prototype, patron `light_emitters.txt` :

```
CHUTE  <proto>  dir=<x,y,z> vitesse=<m/s> bandes=<n> impact=<x,y,z> r=<m> force=<0..1> brume=<groupe>
JET    <proto>  impact=<x,y,z> r=<m> periode=<s>
NAPPE  <proto>  matiere=<mer|riviere|mare|boue|eco|lave|electrique>
EXCLU  <proto>  <raison>
```

Matériau W2c : UV.y + t·vitesse, bruit étiré ×6, **posterisation 5-6 bandes**, flow 2 phases décalées
de 0,5, écume basse par `step` sur 15 %, bord de nappe clair. Base : anneau d'écume radial, impulsion
continue dans la RT (la surface d'arrivée ondule vraiment), brume ND conservée. Jak sous la chute :
impulsion et écume le suivent (depth fade) ; `drip-wetness` existe **[M]** (`water.gc:745-768`).

### 5.8 Compagnon et assets (famille « rechargés »)

| Fichier | Contenu |
|---|---|
| `<niveau>.waterbake` | en-tête (magie, version, empreinte fr3 + `tfrag3_version` + hash des tables ND) ; par plan : hauteur, boîte, `shore_sdf`, `shore_dir`, `floor_depth`, `flow`. Absent = rendu sans rivage ni caustiques, `waterbake_missing=1`, jamais fatal. |
| `water_materials.txt` | 8 matières : paliers, k_abs, roughness, f0, fresnel_ceiling, sss_color, amortissement, échelles de normales, écume, émissif |
| `water_falls.txt` | verdicts des prototypes |
| `water_overrides.txt` | par niveau : λ_shore, T_shore, teinte lagon, matière par look (les 48 looks ont un verdict, annexe A) |
| textures | `water_normal_a/b` 256², `foam_voronoi` 512², `caustics` 512² (3 frames RGB), `splash_sheet` |

L'outil `water_bake` lit la collision et le fr3 produits par l'utilisateur (famille ISO) et n'écrit que
le compagnon. Les deux familles ne se confondent pas.

---

## §6 — PALIERS, RÉGLAGES INDIVIDUELS ET BUDGETS **[C]**

Conçu depuis Ultra. Un palier pose des défauts sur les réglages de §7 ; tout est écrasable un par un.
Un `#define` par capacité : ce qu'un réglage éteint est retiré du texte compilé.

| Capacité (= un réglage) | Très bas (Adreno 618) | Moyen (Adreno 7xx, PC portable) | Haut (SD 8 Elite, PC) | Ultra (PC puissant) |
|---|---|---|---|---|
| Clipmap anneau 0 | 64² | 128² | 128² + tess ×2 | 256² + tess ×4-×8 pilotée par distance et énergie |
| Gerstner B | 2 ondes | 4 | 8 | 8 + normales 1024² 3 octaves |
| RT de rides | 128² statique, normale seule | 256², onde, hauteur + normale | 512² | 1024² sur 96 m, 2 itérations, écume persistante feedback |
| Copie W0 | profondeur ½ | couleur + profondeur ½ | pleine | pleine + mips (réfraction floue) |
| Reflet | SH ciel | cube 32² P3 | cube 128² + planaire ¼ plans immobiles | SSR toute l'eau (16-32 pas, repli cube) + planaire ½ |
| Écume | rivage + intersection | + crête | + persistante | + sillage 2 échelles |
| Caustiques | 1 échantillon | 3 RGB décalés | + rayons sous l'eau | corrélées à ∇h de la RT + rayons volumétriques |
| SSS, étincelles | non | oui | oui | + éclats en profondeur |
| Éclaboussures | sparticles ND | + maillage | + maillage | + gouttes GPU, mouillage du sol |
| Cascades | bandes 5 | bandes 6 + flow | + anneau animé | + brume volumétrique, réfraction de nappe |
| Résolution passe eau | ½ | 1 | 1 | 1, SSAA 2× de W2 en option |

Budgets GPU (part de l'image à la cadence de la classe, même vantage, deux bras ; dépassement = un cran
sur le réglage le plus cher, pas un palier entier) :

| Passe | Très bas | Moyen | Haut | Ultra | Instrument |
|---|---|---|---|---|---|
| W1 rides | 0,2 ms | 0,4 | 0,8 | 1,5 | `gpu_ms_water_ripple` |
| W0 copie | 0,3 | 0,6 | 1,0 | 1,2 | `gpu_ms_water_copy` |
| W2 eau | 1,5 | 2,5 | 4,0 | 6,0 | `gpu_ms_ocean` **[M]** étendu |
| W3 reflet | — | — | 1,5 | 3,0 | `gpu_ms_water_reflect` |
| **Total** | **≤ 2,0** | **≤ 3,5** | **≤ 7,5** | **≤ 12** | |
| Fil GOAL | +0 FFI/image, +1/événement sur toutes les classes | | | | `Kernel dispatch time` |

Le plancher a une contrainte documentée (fil GOAL 55 ms, fill-rate Adreno 618) : c'est pour cette
classe seule que la copie est à ½ et la RT sans itération. Rien ne remonte dans les autres colonnes.

---


**[C] Amendement du 2026-09-09 (dossier « stock 60 img/s ») :** la ligne « Fil GOAL … `Kernel dispatch time` » utilise l'instrument `goal_busy_ms` de `perf-instruments` ; la prémisse « 55 ms » est une mesure sérialisée GOAL + rendu, pas le fil GOAL.

## §7 — RÉGLAGES, MENUS, PONT GOAL **[C]**

Mécanisme de la spec éclairage §6.1 (`pc-set-*!` depuis `hud-classes-pc.gc`, `Gfx::recharged_active()`).
Hiérarchie : `recharged_master` → `recharged_water` → sous-réglages. « Original » met
`recharged_water` OFF ; « Recharged » ON au palier détecté.

| Réglage | Type | Défaut | Menu |
|---|---|---|---|
| `pc-set-recharged-water!` | int 0/1 | 1 | Options › Recharged › Eau Rechargée |
| `pc-set-water-tier!` | int 0..3 | = palier éclairage | Qualité de l'eau (Auto / Très bas / Moyen / Haut / Ultra) : pose les défauts, n'en verrouille aucun |
| `pc-set-water-tess!` | int 0..3 | = tier | Tessellation (Off / ×2 / ×4 / ×8) |
| `pc-set-water-waves!` | int 2..8 | = tier | Détail de houle |
| `pc-set-water-interaction!` | int 0..4 | = tier | Rides et sillage (Off / Statique / 256 / 512 / 1024) |
| `pc-set-water-shore!` | int 0..2 | = tier | Vagues de rivage et écume (Off / Rivage / + persistante) |
| `pc-set-water-refraction!` | int 0..3 | = tier | Réfraction (Off / ½ / Pleine / + flou) |
| `pc-set-water-reflection!` | int 0..3 | = tier | Reflets (Ciel / Cube / Planaire / SSR) |
| `pc-set-water-caustics!` | int 0..3 | = tier | Caustiques (Off / Simple / RGB / Corrélées + rayons) |
| `pc-set-water-splash!` | int 0..2 | = tier | Éclaboussures (Origine / Maillage / + gouttes) |
| `pc-set-water-falls!` | int 0..2 | = tier | Cascades (Origine / Rechargées / + brume volumétrique) |
| `pc-set-water-res!` | int % | = tier | Résolution de la passe d'eau (50-200 %) |
| `pc-set-water-height!` | int mm | — | pas un menu : hauteur de jeu sous Jak, déjà calculée par `water-control`, poussée par image (un FFI) |
| `pc-water-impulse!` | 4 int | — | pas un menu : un appel par événement au site de `splash-spawn` |

`debug.opengoal.water.*` (appareil) et `OG_WATER_*` (bureau) pour l'A/B ; la propriété écrase, ne
définit pas. `lod-force-ocean` retiré. Libellés selon `recharged-settings-case-l10n`.

---

## §8 — INSTRUMENTATION ET PREUVE

**[M]** `autoport_proof.{h,cpp}` existe : `armed_for("water-<x>")`, jamais `armed()` ; `note_hit()` au
site du geste ; une ligne `clé=valeur` par grandeur ; `--off` rend `armed=0 hits=0` dans la même scène.
Aucune preuve visuelle. Vantages fixées par item, répétées sur x86 avant l'appareil.

| Item | Porte | `hits` = | Autres clés |
|---|---|---|---|
| 0 water-census | `water_proto_unassigned == 0` | prototypes et looks classés | `water_proto_total`, `water_looks_total=48`, `water_entities=102`, `gpu_ms_ocean` de référence |
| 1 water-ocean-mesh | `water_gameplay_height_maxdelta_mm == 0` | sommets déplacés | `refset_replay_maxdiff` OFF = 0, `water_visual_excess_mm ≤ 450`, `gpu_ms_ocean` |
| 2 water-surface-material | `water_shade_calls_outside_shade == 0` | fragments d'eau par `shade()` | `water_refract_front_reject > 0`, `water_dfdx_sites=0` |
| 3 water-shore | `waterbake_sdf_coverage_pct == 100` (10 cartes) | vagues arrivées à d = 0 (au déferlement) | `waterbake_missing`, `shore_wave_period_s`, `shore_wave_amp_max_mm ≤ 300`, `shore_runup_max_m ≤ 4`, `shore_band_width_var` |
| 4 water-interaction | `ripple_impulses_dropped == 0` | impulsions injectées | `ripple_energy` avant/après un pas (causal), `ripple_reproject_slips=0`, `splash_mesh_spawned` |
| 5 water-refraction-reflection | `water_scene_copies_per_frame == 1` | pixels réfractés | `water_fresnel_max ≤ plafond`, `water_env_source` |
| 6 water-caustics | `caustic_above_water_px == 0` | fragments sous le plan avec caustique | `caustic_sun_only=1`, `caustic_levels` |
| 7 water-falls | `falls_without_impact == 0` | chutes avec anneau + impulsion | `falls_total`, `falls_bands`, `ripple_energy_at_impact > 0` sans Jak |
| 8 water-materials-types | `water_look_unmapped == 0` | surfaces rendues avec leur matière | `lava_emissive_lumens`, `mud_reflection_px=0`, `eco_caustic_px=0` |
| 9 water-underwater | `underwater_state_mismatch == 0` | images sous l'eau | `snell_window_deg`, `underwater_fog_applied` |
| 10 water-presets | `water_preset_apply_mismatch == 0` | réglages posés | par réglage : OFF bit-identique à l'absence (binaire-témoin), chaque cran intermédiaire posé |

**Deux contrôles causaux obligatoires.** (1) Règle 2 : la hauteur de jeu est échantillonnée par le
moteur aux mêmes (x, z) que 64 sommets de la clipmap et comparée à la couche A relue d'une texture de
contrôle ; l'écart max en mm est la porte de l'item 1. (2) `ripple_energy` publié sur deux fenêtres,
avant et après un pas de Jak forcé par `cpad_inject` ; nul avant, positif après. Un chiffre vert sans
le bras désarmé ne vaut rien.

---


**[C] Amendement du 2026-09-09 (dossier « stock 60 img/s ») :** `gpu_ms_water_*` sont des passes de `lighting_census` étendu par `perf-instruments`, jamais un module à part ; `water-census` en dépend.

## §9 — LE PLAN EN ONZE ITEMS

```
0 census ─► 1 ocean-mesh ─► 2 surface-material ⭐ ─┬─► 3 shore ──┬─► 6 caustics ─┐
   (indépendants de l'éclairage)   ▲              │             └─► 7 falls ────┤
                        lighting-hdr + ao-indirect ├─► 4 interaction ─► 7 falls   ├─► 9 underwater ─► 10 presets
                                                   └─► 5 refraction-reflection ─► 8 materials-types ─┘
                                                              ▲ lighting-regimes              ▲ lighting-presets
```

| # | id | Objet | Dépend de |
|---|---|---|---|
| 0 | `water-census` | Nommer chaque goutte : 48 looks → matière, prototypes TIE/tfrag à texture d'eau → verdict `water_falls.txt`, 10 cartes exportées, `gpu_ms_ocean` de référence à 4 vantages, outil `water_bake` (inventaire seul), retrait de `lod-force-ocean` | — |
| 1 | `water-ocean-mesh` | Buckets 4 et 63 consomment sans dessiner ; `OceanRecharged` dessine la clipmap à la position W2a, couche A captée au DMA near, découpe par masques ND, `far-color` ; shading provisoire = actuel. OFF bit-identique | 0 |
| 2 | `water-surface-material` ⭐ | `water_surface.glsl` : normales, Fresnel plafonné, paliers, absorption, `shade()` + `SURF_WATER`, SSS, étincelles. Hôtes : clipmap et merc water (programme `merc2_water`). W0 profondeur seule | 1, `lighting-hdr`, `lighting-ao-indirect` |
| 3 | `water-shore` | `.waterbake` (SDF, direction, profondeur) par `water_bake` ; vagues géométriques en 4 phases, calmes, ≤ 0,30 m ; trois écumes ; sable mouillé. Lieu : `beach` | 2 |
| 4 | `water-interaction` | RT de rides W1, file d'impulsions, sillage, `pc-water-impulse!` au site de `splash-spawn`, maillage d'éclaboussure, lecture vertex + fragment. **Aucune physique** | 2 |
| 5 | `water-refraction-reflection` | W0 couleur (une copie, partagée avec `DepthCue`), réfraction avec rejet, reflet cube P3, planaire, SSR | 2, `lighting-regimes` |
| 6 | `water-caustics` | Dans `shade()`, sous le plan d'eau : module le SEUL direct du soleil, projeté en monde, 3 échantillons, atténué par `floor_depth` et l'ombre ; rayons (Haut+) | 3 |
| 7 | `water-falls` | Matériau W2c sur `CHUTE`/`JET`, anneau, impulsion continue, brume ND. Lieux : `jungle`, fontaine `village1` | 3, 4 |
| 8 | `water-materials-types` | Boue, eco noir, lave (lumière locale), électrifiée. Lieu : `misty` | 4, 5 |
| 9 | `water-underwater` | Face arrière, fenêtre de Snell, brouillard teinté au tone map, rayons ; Sunken lisible | 6, 7, 8 |
| 10 | `water-presets` | Réglages §7 au menu, palier auto, préréglages, binaire-témoin par réglage, budgets §6 sur quatre classes | 9, `lighting-presets` |

Fichiers par item : voir l'artifact ; chaque `.cpp` neuf est listé dans `game/CMakeLists.txt` ET
`android/CMakeLists.txt`, chaque shader neuf dans `kChunks`, chaque GOAL neuf dans `game.gd` et
`engine.gd`.

**Après la physique — case réservée, sans item.** Flottabilité sur la hauteur visuelle, courant des
rivières qui pousse Jak (le champ `flow` est déjà là), houle qui déplace les barques, objets qui
injectent leur volume dans la RT. Rien n'est promis ; ce plan garantit seulement que rien ne devra
être défait : hauteur de jeu ND intacte, RT en espace monde, file d'impulsions ouverte.

---

## §10 — RISQUES ET PIÈGES DE CET ARBRE

| Risque | Parade |
|---|---|
| Le microcode VU1 traduit consomme le DMA d'une façon qu'on ne reproduit pas | Item 1 garde les deux renderers ND vivants en « consommer sans dessiner » |
| Alpha de destination = facteur de mélange (`GL_DST_ALPHA`) **[M]** | Le graphe RECHARGED ne l'utilise plus ; l'ORIGINE garde son format |
| Copie de scène = deux résolves de tuiles sur TBDR | UNE copie, `DepthCue` la partage ; porte `water_scene_copies_per_frame == 1` |
| RGBA16F « device-dependent » | Repli R8 encodé, `ripple_rt_fallback` publié |
| Fil GOAL du Redmi (19 img/s, 55 ms) **[M]** | 0 FFI/image ajouté, 1 par événement |
| SIGILL arm64 dans un `behavior` GOAL neuf | Notre GOAL = un `define-extern` + un appel au site existant ; tout le reste en C++ |
| Shader absent de `kChunks`, `.cpp` absent de `android/CMakeLists.txt` | Chaque item liste ses fichiers Android ; preuve appareil obligatoire pour 1, 4, 5, 10 |
| SDF cuit depuis la collision ≠ décor visuel | `water_bake` croise collision et fr3 ; `shore_band_width_var` publié |
| Écume qui glisse avec la caméra | Re-projection par texel entier, `ripple_reproject_slips == 0` |
| Visuel au-dessus de la hauteur de jeu | Bornes dans le shader, `water_visual_excess_mm ≤ 450` |
| Tessellation qui retombe en silence (3 rounds brûlés **[M]**) | Le socle est complet sans elle ; `water_tess_level_effective` publié, le menu affiche la valeur obtenue |
| Un OFF qui n'égale pas l'absence | Binaire-témoin par réglage à l'item 10 |
| Concevoir depuis le plancher (réflexe du harnais, corrigé le 2026-09-09) | §6 écrit depuis Ultra ; « parce que le Redmi » = défaut de Très bas, jamais une limite |

---

## §11 — CONDITION DE FIN

Les onze items sont `validated` (l'owner l'a dit) et :

1. L'eau d'origine est atteignable à tout moment, par le préréglage Original, prouvée bit-identique.
2. La hauteur que le gameplay lit n'a pas changé d'un millimètre.
3. La mer de Sandover a une lumière, un ciel dedans, des couleurs par profondeur, et des vagues
   tranquilles qui arrivent une à une, se cambrent, déferlent en écume et remontent le sable.
4. L'eau Rechargée s'éteint d'une ligne de menu et rend l'eau vanilla, l'éclairage Rechargé conservé ;
   chaque effet s'éteint aussi seul.
5. Marcher dans l'eau laisse un sillage ; tomber dedans fait une gerbe et des anneaux ; les PNJ aussi.
6. On voit le fond à travers, la lumière y danse, jamais au-dessus de la surface.
7. Les cascades ont des bandes, une base d'écume, et la rivière ondule là où elles tombent.
8. Boue, eco noir, lave, eau électrifiée sont quatre matières distinctes ; la lave éclaire.
9. Sous l'eau, on est sous l'eau.
10. Du Redmi au PC puissant, même liste de fonctionnalités, un palier par machine, chaque réglage libre.
11. Une seule fonction, `shade()`, éclaire l'eau comme le sable qu'elle recouvre.

---

## ANNEXE A — LES 48 LOOKS `water-anim` ET LEUR MATIÈRE **[C]** (source **[M]** `water-anim.gc:7-56, 328-475`)

| Looks | Niveaux | Classe ND | Matière |
|---|---|---|---|
| 0-12 | sunken, sunkenb | `sunken-water` | électrifiée |
| 13, 10 (sunken), 15-19 (maincave), 20 (robocave), 32 (misty), 41 (finalboss) | — | `dark-eco-pool` | eco noir |
| 14, 37 | maincave, darkcave | `cave-water` | mare (teinte violette conservée) |
| 21-31 | misty | `mud` | boue |
| 33, 35, 42 | ogre, village3, lavatube | `*-lava` | lave |
| 34 | jungle | `jungle-water` | rivière (flow) |
| 36, 38, 39 | training, rolling | `training-water`, `rolling-water` | mare |
| 40 | sunkenb | `helix-water` | électrifiée |
| 43, 45, 46 | village1 | `villagea-water` | mare (rizières) |
| 44 | village1 | `villagea-water` | mare + JET (fontaine) |
| 47 | village2 | `villageb-water` | mare (seau) |

Les 56 `water-vol` nus héritent de la matière de l'océan (wt08) ou de leur volume.

## ANNEXE B — SOURCES

Sea of Thieves SIGGRAPH 2018 (history.siggraph.org … 2018-Talks-Ang_The-Technical-Art-of-Sea-of-Thieves.pdf) ·
Horizon FW SIGGRAPH 2022 (advances.realtimerendering.com/s2022/SIGGRAPH2022-Advances-Water-Malan.pdf) ·
GPU Gems ch. 1 (developer.nvidia.com/gpugems) · ARM OpenGL ES SDK Ocean FFT, Tessellation
(arm-software.github.io/opengl-es-sdk-for-android/) · NiloCat Mobile SSPR (github.com/ColinLeung-NiloCat) ·
Catlike Coding Flow (catlikecoding.com/unity/tutorials/flow/) · Cyanilux Shoreline · Roystan Toon Water ·
Ameye Realtime Caustics · Alisavakis Unlit Waterfall, Stylized Water · Crest Shallows and Shorelines ·
Unity URP perf, HDRP Water · UE5 Water plugin · Genshin console pipeline (nugglet.github.io) ·
Nathan Gordon, The Ocean (Wind Waker) · Jasper St. Pierre, Super Mario Sunshine water · GodotOceanWaves,
godot4-oceanfft, Waterways · Homoki UE4 cartoon water · Trümpler RiME water · Uncharted 4 Rendering
Rapids · AC IV Black Flag (fxguide) · Khronos `GL_EXT_shader_framebuffer_fetch` · ARM Mali TBDR blogs.
