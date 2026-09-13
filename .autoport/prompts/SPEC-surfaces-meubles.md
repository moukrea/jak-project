# SPEC — surfaces meubles deformables (neige profonde, neige compacte, sable)

Contrat de la campagne `soft-*`. Chaque item cite les sections qui le concernent dans son `known_cause`
et ses `notes`. Ce document fait foi ; un item ne le contredit jamais.

Investigation complete, lisible par l'owner :
* artifact : https://claude.ai/code/artifact/0e939862-8d2a-4ec9-a7fd-0ed886d7e049
* copie versionnee : `.autoport/plans/2026-09-13-surfaces-meubles.html`

Approuve par l'owner le 2026-09-13 sans correction : « J'approuve l'artifact by the way, let's goo pour
la phase d'apres ! ». Les seize decisions de la section 33 de l'artifact sont donc prises dans le sens
RECOMMANDE ; elles sont rappelees en section 16 de cette SPEC. L'owner peut en renverser une par un
mot ; l'item concerne est alors rouvert avec son prompt regenere.

---

## 0. FAITS ETABLIS PAR L'OWNER — CONTRAINTES, PAS HYPOTHESES

1. Dans la neige profonde, Jak marche sur une surface de collision INVISIBLE situee sous la surface de
   neige visible, et penetre volontairement le volume rendu. C'est intentionnel. INTERDIT : deplacer la
   collision au sommet, relever Jak, supprimer l'intersection.
2. La neige compacte et le sable recoivent une fine couche visuelle AU-DESSUS de la collision
   historique ; la collision ne change pas ; enfoncement perceptif de 3 a 4 cm, a calibrer.
3. Il n'existe pas de corps persistants : les ennemis s'evaporent. Aucun cadavre, aucun ragdoll.

CONSTANTES : 1 m = 4096 unites (`METER_LENGTH`, `types-h.gc:23`). 3 cm = 122,88 u ; 4 cm = 163,84 u.
Jak : collider de 2,8 m, rayon de corps 0,7 m, racine 2,2 m ; 3-4 cm = 1,07 a 1,43 % de sa hauteur.
Toute grandeur publiee l'est BRUTE (unites) ET CONVERTIE (m ou cm) — PITFALLS l.411.

---

## 1. CE QUE L'INVESTIGATION A ETABLI

* `pat-material` (`pat-h.gc:5-28`) classe le sol par triangle de collision : sand=5, snow=9,
  deepsnow=10 (aussi quicksand=2, dirt=15 ; gravel=14 a ZERO triangle dans tout jak1). Bits 6..11 de
  `pat-surface` (`Tfrag3Data.h:736-748`). AUCUN lecteur du materiau dans `game/` ni `common/` ; cote GOAL,
  seuls `effect-control.gc` (7 sites) et `target-death.gc:967-968`. Aucun code de mouvement n'en depend.
* LA NEIGE PROFONDE N'EST PAS DU TERRAIN. Les 762 triangles deepsnow de `snow` forment 19 ilots
  deconnectes (13 x 42 tris, 6 x 36 ; 25 a 366 m² ; 2 332 m² au total ; 0 sommet partage avec
  snow/stone/ice) : ce sont les fragments de collision de prototypes TIE instancies — des congeres
  (`snow-top-01.mb`, `snow-top-02.mb`, `snow-sloped.mb`, `snow-flattop.mb`, `snow-flapjack-01.mb`,
  attribution a verifier). Pente mediane 28,4°, 83 faces a |ny| < 0,7, faces retournees marchables,
  denivele interne 3 a 6 m. `ogre` porte 18 ilots de 16 tris (17 congruents, 37 m², 0,5-1,0 m).
  L'ECART VERTICAL visible/collision est INCONNU : il faut un decodeur des arbres TIE du .fr3.
* La neige compacte (5 968 tris, 72 181 m², normale mediane 0,995) et le sable sont du terrain tfrag.
  Sable : beach 10 294 tris / 90 299 m² (38 % de l'aire a ±2 m de l'eau, 26 007 m² sous −5 m) ;
  training 8 728 / 56 233 m² (42 ilots, 2 952 tris en mode MUR) ; village1 8 304 / 60 019 m² ;
  intro 2 464 / 11 941 m² ; village2 616 / 5 255 m². misty : 0 sable (terre). Mer a y = 0.
* AUCUN SABLE HUMIDE n'existe (0 texture wet/damp sur 1 471). Le sable mouille est une promesse de
  `water-shore` (albedo x 0,6, roughness 0,15 via `shade()`).
* Le maillage du sol est GROSSIER : arete moyenne 4,885 m (village1), mediane des patches 1,03 m ;
  VBO STATIQUES par niveau ; normales tfrag ABSENTES du .fr3, reconstruites au chargement
  (`TFrag3Data.cpp:1900-1976`). Une empreinte de 0,6 m n'existe pas sur un triangle de 5 m.
* TROIS vertex shaders projettent le terrain : `tfrag3.vert:66-75` (couleur, seul a appliquer sway et
  contact), `prepass_world.vert:29-38` (prepasse AO), `pbr_depth.vert:6` (carte d'ombre soleil 2048² D16,
  double-bufferee, compare manuel). Aucun point de composition unique. Les chunks GLSL partages
  passent par `Shader::expand_includes` (`Shader.cpp:222-224`).
* Renderer : PC GL 4.3 core, Android GLES 3.2 (shaders reecrits 410 -> 320 es par `preprocess.py`).
  UTILISE : lecture de texture au sommet (6 .vert, dont la palette TOD de tfrag3), render-to-texture
  (13 fichiers), RGBA16F / RGBA32F / R32F, instancing, glTexSubImage2D par image, glFenceSync.
  JAMAIS UTILISE : compute, image load/store, atomiques, SSBO, MRT effectif, geometry, tessellation
  (SUPPRIMEE le 11/09 par lighting-legacy-purge), glBufferStorage, transform feedback. Une cible
  flottante ne se relit pas en octets sur GLES3. Pieges Adreno 618 : tableaux d'uniformes a index
  dynamique -> 0/garbage (derouler a index litteral), `normalize(mix())` fige, watchdog kgsl ~2 s.
* `hfrag` (Jak 3) n'est PAS reutilisable : non compile Android, `sampler1D`, cellules de 8 m statiques.
* L'ocean Recharged lit une texture R32F 32x32 dans son vertex shader et deplace une clipmap de
  16 641 sommets : le patron « hauteur en texture, lue au sommet » existe.
* Les effets de pas de la neige profonde N'EXISTENT PAS : `group-*-dpsnow` = 5 symboles sans
  `defpartgroup`, parts 2251/2263 absents, sons `walk-deepsnow1` demandes contre `walk-dpsnow1` en banque.
  Sur sable et neige compacte, `group-just-footprint-{sand,snow}` posent un sprite `footprntr` de 0,6 m,
  oriente par la normale du sol et le lacet de Jak, efface en 3,5 s (part 2376 / 94).
* JAK : root `collide-shape-moving` (trans, quat, transv, `onground`, `ground-pat`, `ground-poly-normal`,
  `ground-touch-point` — UN point, fige en l'air —, `ground-impact-vel`) ; 6 spheres sur la racine,
  AUCUNE primitive de pied ; squelette `eichar` 84 noeuds : Lankle 29, Rankle 33, Lball 69, Rball 73,
  Ltoes 71, Rtoes 75, matrices monde apres `ja-post`. Tags de pas dans les animations
  (`effect-walk-step-left/right`, `effect-run-step-*`, `effect-land`, `effect-slide`, `effect-roll`,
  `effect-just-footprint`…) avec index de joint, resolus AVANT `do-joint-math!` (os de l'image
  precedente), sans orientation ni vitesse. Ne JAMAIS armer le bit 0 des flags d'effect-control chez
  Jak (route vers `target-powerup-effect`). Sous interpolation d'animation, `do-joint-math!` recule
  `trans` avant de construire les os.
* ENNEMIS : nav-enemies a `move-to-ground` -> memes champs sol que Jak par image ; spheres racine et
  d'os ; aucune primitive de pied. MORT (`nav-enemy-die`, `nav-enemy.gc:807-827`) : collision retiree a
  l'image 0 (`clear-collide-with-as`), chute balistique sans collision pendant l'anim, dissolution
  75/5+1 = 16 images, masquage. Un filtre `collide-with != 0` retire l'ennemi a l'image 0.
* PNJ : les `process-taskable` ne marchent pas ; mobiles au sol : yakow (village1), seagull, pelican
  (beach). OBJETS : caisses = prim mesh boite, JAMAIS mobiles (objets statiques cuits) ; `snow-ball` =
  sphere r 2,5 m qui roule (transv, quat) ; zoomer/flutflut = collider 'racer/'flut de Jak. Aucun OBB.
* CANAL HERBE : `pc-set-jak-pos!` par image ; balayage d'acteurs toutes les 15 images ; jusqu'a 8
  disques uploades (16 avec statiques), `u_trample2` repacke pour Adreno, deroulage litteral sur 8.
  Rien pour la velocite, l'orientation, les pieds. Pont GOAL->C : 6 arguments GPR ; au-dela, tableau
  GOAL inline enregistre une fois (patron `*hd-ring*`, `jak-hd.gc:90`).
* BASELINE : x86, vantage du recensement : tfrag 3,7-5,1 ms, tie 5,6-6,5 ms GPU/image. Redmi : total
  16,9-26,0 ms GPU/image ; REPARTITION PAR BUCKET INEXPLOITABLE (l'ocean absorbe 92-95 % : GPU a tuiles).
  Cadence Redmi herbe OFF 20,0-21,1 img/s (`reports/Ggrass-crash/report.txt:101-103`). Budgets GPU
  voisins (eau) : 2,0 / 3,5 / 7,5 / 12 ms.
* BACKLOG : sujet vierge (0 item, 0 commit). Voisins : `grass-surface-truth` (lecteur pat-material),
  `grass-chunk-cull`, `grass-overlay-meshes`, `water-shore` (shore_sdf, sable mouille),
  `water-interaction` (patron RT monde + file d'impulsions + 1 FFI au site ND `splash-spawn`),
  `lighting-ao-indirect` (prepasse), `lighting-shadows` (atlas), `lighting-bake` (bump TFRAG3_VERSION=44),
  `lighting-presets`, `water-presets`, `perf-goal-gl-overlap` (slot par image), `perf-instrument-cost`.

---

## 2. L'ARCHITECTURE : UNE COQUE DE MATIERE

HORS LIGNE, chaque triangle de sol eligible (classification a deux sources) est subdivise en une chaine
de niveaux de detail IMBRIQUES (L0 12,5 cm, L1 25 cm, L2 50 cm, L3 = triangle d'origine), ses sommets
de FRONTIERE figes (h = 0, jamais deplaces), ses sommets interieurs souleves de l'epaisseur h le long
d'une DIRECTION DE COUCHE cuite. UV, `color_index`, normale sont herites des parents.

AU CHARGEMENT, les triangles eligibles sont RETIRES de l'index du terrain et la coque prend leur place :
jamais deux surfaces au meme endroit, pas de z-fight, pas de double shading, apparence au repos = terrain
+ epaisseur.

AU RUNTIME, la coque a son renderer (patron GrassRenderer), son VBO, ses programmes dans les TROIS
passes qui ecrivent la profondeur (couleur, prepasse, carte d'ombre soleil), tous incluant UN chunk GLSL
`soft_displace.glsl`. Elle est deplacee au sommet par des TUILES DE HAUTEUR dynamiques par chunk :
`p = p_repos − dir · h · compression + dir · bourrelet`, compression dans [0 ; 1]. Une tuile ne PEUT PAS
exprimer un creusement sous le support, par construction.

LA NEIGE PROFONDE applique la meme coque a la surface rendue des congeres, avec une epaisseur cuite par
point jusqu'a l'ilot de collision. LA NEIGE COMPACTE ET LE SABLE recoivent une coque de 3,5 cm au depart
(decision 5), compressible jusqu'au support.

LE SUPPORT DE COLLISION NE BOUGE PAS D'UNE UNITE. Aucun item ne touche `collide-shape*`, la navigation,
les tests de sol, les triggers, la camera. Preuve : rejeu d'une trajectoire ON/OFF, positions de Jak
identiques a 0 u.

---

## 3. CE QUI EST PRECALCULE, CE QUI NE L'EST PAS

AU BAKE (`tools/soft_bake`, deterministe, sans aleatoire ni horloge ni fil, `-ffp-contract=off`,
round-trip integre) : classification, support, epaisseur par sommet, direction de couche, distances
aux frontieres et aux objets statiques, depressions statiques (caisses, coffres, plateformes, TNT),
rejets (murs, faces retournees, pente > seuil du profil), coque L0-L3, chunks + bounds + repere local,
liste des triangles a ceder, textures statiques par chunk (epaisseur R8, frontiere R8), lecture du
`shore_sdf` de `.waterbake` si present, table de validation.

AU CHARGEMENT (asynchrone, 0 ms bloque) : lecture du compagnon, VBO/EBO, filtrage d'index du terrain.
Compagnon absent ou perime = NON FATAL : `soft_missing=1`, terrain intact, image bit-identique a OFF.

AU RUNTIME : collecte des interacteurs, volumes balayes, tampons de contact, relaxation, eviction,
culling, LOD, lecture de la phase d'eau. AUCUNE analyse geometrique.

FORMAT : `<niveau>.softbake`, en-tete de la famille des compagnons (magie, version du format, EMPREINTE
DE CONTENU du .fr3 — jamais sa taille, le defaut connu du .grassbake —, `tfrag3_version`), sections
adressables par chunk. Version du compagnon INDEPENDANTE de `TFRAG3_VERSION` (que `lighting-bake` va
bumper). Rebake cible par niveau et par section ; declenchement par la chaine de build.

---

## 4. LE MOTEUR DE DEFORMATION

* TUILES par chunk : R16 compression, R8 bourrelet, R8 age ; pool borne par palier ; repere local par
  chunk (base tangente au plan moyen de la nappe) ; une nappe par etage superpose.
* DEUX PRODUCTEURS, UN CONSOMMATEUR : rasterisation de quads de contact dans la tuile (Moyen et
  au-dessus) ou calcul CPU + `glTexSubImage2D` (Bas). Jamais de compute. Jamais de relecture.
  Le shader de la coque ne sait pas lequel a ecrit.
* VOLUMES BALAYES : chaque interacteur garde sa position precedente ; le segment est echantillonne
  tous les rayon/2 AU PLUS, quel que soit le nombre d'images. 30, 60, 120 Hz donnent la meme trace a
  ±1 quantum par texel. Un saut > 5 m entre deux images (teleport, warp) coupe le segment.
* SATURATION : compression = max(existant, nouveau), jamais la somme ; a 1, plus rien ne creuse.
  Application avec une vitesse (3 images a 60 Hz, en TEMPS reel), pas instantanee.
* NORMALES : gradient de la tuile (differences finies) dans le repere de la coque, mele a la normale
  cuite ; fournies a la prepasse (RG16F octaedrique) et a `shade()` via `Surface.N`. Jamais `dFdx`.
* RELAXATION : cadence FIXE par dt accumule, tuiles actives seulement, profil par matiere.
* TRAVAIL BORNE par image : N tampons, M tuiles relaxees, le reste reporte et compte.

---

## 5. LES INTERACTEURS

* CANAL GOAL -> C++ : un tableau GOAL inline enregistre une fois (patron `*hd-ring*`), rempli par image
  depuis `hud-classes-pc.gc` : Jak (trans, transv, quat, drapeaux, ground-pat, classe d'etat, 4 noeuds
  de pieds en monde) ; les N interacteurs mobiles les plus proches (id, sphere, transv, type), balayes
  CHAQUE image pour ceux-la ; un appel unique au site ND `effect-control-method-11` pour les tags de pas
  (gauche/droit, joint, materiau). Regle du lot perf : scalaires en SLOT par image, jamais un pointeur
  lu par le fil de rendu ; rien de nouveau par image sur le fil GOAL au-dela du slot.
* PIEDS : deux capsules cheville -> plante (Lankle->Lball, Rankle->Rball). Contact si la capsule est sous
  la surface de repos ET root `onground` ET classe d'etat autorisee (jamais falling/jump). Le tag de pas
  CONFIRME et date, il ne cree pas seul (une image de retard). Aucune empreinte depuis la racine.
  Le sprite `footprntr` ND est desactive quand la coque est active sur ce materiau (double empreinte).
* JAMBES (neige profonde) : capsules hanche->genou->cheville, actives seulement si l'epaisseur disponible
  depasse la hauteur des chevilles. Reception = disque a la racine selon `ground-impact-vel`. Glissade =
  capsule allongee selon transv. Roulade = sphere de la racine balayee. Accroche de rebord = rien.
* ENNEMIS : spheres racine et d'os balayees ; retires a l'image 0 de la mort par `collide-with != 0`.
  Aucune deformation posthume : la chute balistique ne touche pas le sol.
* OBJETS : snow-ball (sphere r 2,5 m balayee), yakow, seagull, pelican ; zoomer/flutflut via le collider
  de Jak. Caisses et plateformes = depressions statiques CUITES, pas des interacteurs.
* PRIORITE sous budget : Jak toujours ; puis distance a la camera x taille apparente x nouveaute ;
  hors des chunks actifs = ignore sans cout.

---

## 6. RENDU ET PASSES

* Trois programmes de coque (`soft_color`, `soft_prepass`, `soft_depth`), memes attributs et uniformes
  lies par le C++ (patron `PrePass.cpp:264,527` / `TFragment.cpp:780`). Publier le compte de programmes
  lies incluant `soft_displace.glsl` : il vaut 3.
* Dessin apres les tfrag du niveau, phase opaque, convention GEQUAL ; en GL_EQUAL sur la passe avant de
  la refonte lumiere, position BIT-IDENTIQUE entre prepasse et couleur (meme chunk, memes uniformes,
  `highp`). Les volumes stencil PS2 (bucket 47) suivent la profondeur ecrite : rien a faire.
* `Surface` de `shade()` remplie normalement ; la trace module `albedo` et `roughness` par compression
  et age AVANT `shade()`. Pas de second pipeline de matiere.
* Bounds du chunk = repos + profondeur max + bourrelet max.
* LES DEUX BOUCLES : tout site par passe est visite dans `OpenGLRenderer.cpp` ET
  `android/android_opengl_renderer.cpp`. Tout `.cpp` neuf dans les DEUX CMakeLists. Shaders Android
  dans `kChunks`. GOAL neuf dans `game.gd` et `engine.gd`.

---

## 7. PENTES ET FRONTIERES

* Direction de couche : `dir = normalize(mix(up, N_lissee, w(pente)))`, w nul sous 10°, unitaire au-dela
  de 35°, cuite par sommet, NULLE en frontiere. Compression le long de dir, vers le support.
* Frontieres : distance cuite a l'arete non eligible, au mur, a l'objet statique (empreinte de contact
  au sol, sommets TIE non eligibles densifies au pas de 0,35 m comme l'herbe), a la ligne d'eau.
  Falloff cosinusoidal sur 0,3 m (sable) / 0,5 m (neige). Sous un objet pose : depression cuite plus
  large de 0,1 m que l'empreinte.
* Rejets comptes : faces retournees (ny < 0), murs (mode 1), pente > seuil du profil, 2 952 tris de
  sable en mode MUR a training, meshes superposes sable-sur-grass (decision 12).
* Coutures IMPOSSIBLES par construction : sommets de frontiere figes, direction nulle en frontiere,
  LOD imbriques par index, marge d'un texel ecrite des deux cotes d'une frontiere de chunk.

---

## 8. CYCLE DE VIE

* Eviction : pool borne ; LRU distance a la camera x age ; une tuile evincee laisse une copie R8 au
  quart, reappliquee au retour. Un chunk sous un objet actif ne s'evince pas.
* Persistance : tant que le niveau est charge, y compris checkpoint et mort de Jak ; rien dans la
  sauvegarde ; reinitialisation au changement de niveau.
* Changement de palier : reechantillonnage des tuiles sur deux images, pool redimensionne par eviction
  progressive ; JAMAIS de remise a zero.
* Perte de contexte (mobile) : tuiles perdues, copies grossieres restaurees si presentes, sinon repos.

---

## 9. CHUNKS, CULLING, LOD

* Chunks de 8 m (valeur de depart), une nappe par etage, coupes le long des aretes de triangles ;
  tuile 128² a 6,25 cm de texel, 64² a 12,5 cm ; propre grille, pas les VisNode du terrain.
* CINQ portees de culling publiees separement : rendu, simulation (plus large), collecte, vieillissement
  (cadence reduite hors champ), normales (au rendu).
* LOD : chaine L0-L3 par index, hysteresis entree 0,9x / sortie 1,1x, morphing de hauteur sur une plage ;
  la tuile est la meme a tous les niveaux -> aucune redistribution possible. A distance, mip de tuile
  plus grossier : les empreintes s'effacent, les sillons majeurs survivent.
* Streaming : compagnon adressable par chunk ; teleport et warp coupent les segments et deplacent la
  fenetre active sans vider le pool.

---

## 10. LE CONTRAT AVEC L'EAU

L'EAU POSSEDE : la hauteur de jeu (GOAL, inchangee), la hauteur visuelle, `shore_sdf`/`shore_dir`/
`floor_depth` (cuits dans `.waterbake` par `water-shore`), le sable mouille (via `shade()`).
NOUS POSSEDONS : la geometrie du sable, son epaisseur, ses traces. L'eau ne deplace JAMAIS un sommet de
coque ; la coque ne deplace jamais l'eau.
NOUS LISONS : `shore_sdf` AU BAKE (falloff d'epaisseur vers la ligne d'eau, EXCLUSION sous −0,5 m —
decision 9 : aucune coque sur le fond marin) ; la PHASE DU JET DE RIVE au runtime (un scalaire par
image, a publier par `water-shore` — ajout demande a son livrable) pour accelerer la relaxation ou la
lame passe.
TANT QUE `water-shore` N'EST PAS LIVRE : falloff statique par la mer a y = 0, pas d'effacement, pas
d'humidite. Le sable au-dessus de 2 m (training, village1 haut) se deploie sans attendre.
Aucune ecriture concurrente : deux compagnons, deux pools de tuiles, une lecture croisee au bake.

---

## 11. HERBE ET AUTRES SYSTEMES

* EXCLUSIVITE HERBE / COQUE par classification : un triangle sand/snow/deepsnow n'est jamais eligible
  a l'herbe, et reciproquement ; le desaccord texture/materiau se compte dans les deux campagnes avec
  le MEME lecteur (`grass-surface-truth`). Compte croise d'eligibilite aux deux = 0. Le canal d'acteurs
  de l'herbe est ETENDU, pas duplique.
* Terrain : les triangles cedes sortent de l'index au chargement ; on ne depend pas de l'invariant de
  `MeshConsolidate` (item ouvert pour le retirer).
* Lumiere : coque dans P1, P2, P6 ; `LIGHT_TIER` par `#define` comme les autres hotes ; l'atlas lit une
  carte d'une image de retard, la coque aussi.
* Effets de pas : le systeme de deformation possede la geometrie ; `effect-control` garde poussiere et
  sons ; le trou `dpsnow` est un item ADJACENT hors campagne, a la decision de l'owner (non cree).
* PBR : modulation dans `Surface` uniquement ; les parametres de matiere de la coque peuvent vivre dans
  `surfaces.json` si `lighting-materials` le permet.
* Sauvegardes : rien. Menu : `recharged_master` -> `recharged_soft`, MASQUER pas griser, vrais
  sous-menus (owner 10/09). Ancien reglage remplace = code SUPPRIME, pas debranche (owner 11/09).

---

## 12. PALIERS

`recharged_soft` : Auto (suit le palier lumiere) / Tres bas / Bas / Moyen / Haut / Ultra. Un
interrupteur par matiere pour le debug. Tout le reste est interne, par profil ou par niveau.
Matrice de depart (artifact section 25) : Tres bas = coque NON CHARGEE, image = OFF (decision 13,
assumee : le Redmi tourne a 19-20 img/s sans elle) ; Bas = texel 25 cm, producteur CPU, 20/25 m, 16
chunks, Jak+2, pieds par disque racine + tag, pas de jambes ; Moyen = 12,5 cm, rasterisation, 35/45 m,
48 chunks, Jak+6, 2 capsules, 2 capsules de jambes ; Haut = 6,25 cm, 60/80 m, 128 chunks, Jak+12, 4
capsules de jambes ; Ultra = 3,1 cm, 100/130 m, 320 chunks, Jak+24, 6 capsules, seuils LOD x 1,6.
UN PALIER INFERIEUR REDUIT resolution, portee, interacteurs — JAMAIS LE PROFIL : la neige profonde reste
profonde en Bas. Chaque OFF est bit-identique a l'absence, prouve par binaire-temoin (regle des SPEC
lumiere et eau). Bornes de compression (0..1) et de bourrelet identiques entre paliers.

---

## 13. BUDGETS

GPU + CPU par image, proposes : Bas 0,6 + 0,2 ms ; Moyen 1,5 + 0,3 ; Haut 3,0 + 0,4 ; Ultra 6,0 + 0,5.
Memoire de tuiles : Bas ≈ 0,1 Mo ; Moyen ≈ 1,2 Mo ; Haut ≈ 10 Mo ; Ultra ≈ 80 Mo. Sur l'appareil, seul
le TOTAL GPU par image est un chiffre (repartition par bucket inexploitable) ; `goal_busy_ms` ≤ baseline.
Instrument : `gpu_ms_soft` sur x86 via `lighting_census`, `note_hit_for` JAMAIS par sommet
(`water-ocean-mesh-hit-counter-cost`), cout d'instrument ≤ 200 µs (`perf-instrument-cost`).

---

## 14. REGLES DE PREUVE DE LA CAMPAGNE

* Aucune preuve visuelle. Une porte lit une grandeur : compte, ecart, duree.
* Chaque item : `FEATURE <id> armed=1 hits=<hits_means>` + `<gate.key>=` seule sur sa ligne ; `--off`
  rend `armed=0 hits=0` dans la MEME scene ; `armed_for("<id>")`, jamais `armed()`.
* Un zero AVANT rend la suite vide : chaque item de retrait publie un compte NON NUL avant.
* Une trajectoire de test est un fichier rejouable par le harnais (positions par image), rejoue a 30,
  60 et 120 Hz (`fixed_tick`, `render_pace`) ; tolerance 1 quantum par texel.
* Tout item qui touche une passe ecrit la profondeur : ecart de profondeur entre passes mesure par la
  sonde `refset_read_scene_depth` sur des vantages nommes (`snow-start`, `snow-fort`, et ceux a creer).
* Les items `owner_test: true` sont ceux ou l'oeil de l'owner est le juge final APRES la porte : 5
  (les 3-4 cm), 9, 10, 13, 14, 15, 21, 22.

---

## 15. DEPLOIEMENT

Ordre des zones pilotes : 1 snow neige compacte (72 181 m², plate) ; 2 les 19 congeres de snow ;
3 training sable hors eau (42 ilots, murs) ; 4 village1 sable haut ; 5 beach rivage (contrat eau) ;
6 ogre. Puis village2, intro. Rien sur misty ni sur le fond marin. Chaque niveau = une donnee cuite.

---

## 16. LES SEIZE DECISIONS, TRANCHEES PAR L'APPROBATION SANS CORRECTION DU 2026-09-13

1. Representation : coque cuite REMPLACANT les triangles eligibles (pas superposee).
2. Producteur de tuiles : rasterisation des Moyen, CPU en Bas.
3. Direction d'epaisseur : normale lissee bornee, verticale a plat.
4. Epaisseur des congeres : a trancher APRES l'item 1 (coque sur toute l'epaisseur, ou les 0,5 m
   superieurs si l'ecart est grand) — la seule decision encore ouverte, portee par soft-baseline.
5. Calibration : 3,5 cm (143 u) pour neige compacte et sable, multiplicateur par niveau, jugee a l'oeil.
6. Bourrelets : redistribution bornee dans la meme tuile (25 % / 5 % / 12 % de h).
7. Pieds : deux capsules cheville -> plante, tags de pas en confirmation.
8. Jambes : capsules des Moyen, actives selon l'epaisseur disponible.
9. Fond marin : aucune coque sous −0,5 m.
10. Persistance : niveau charge, checkpoint et mort compris ; rien en sauvegarde.
11. Eviction : LRU distance x age, copie grossiere au quart.
12. Meshes superposes (sable sur collision grass) : EXCLUS tant que `grass-overlay-meshes` n'a pas mesure.
13. Appareils modestes : Tres bas ETEINT ; Bas garde une version geometrique a 25 cm.
14. Eau : lecture de `shore_sdf` au bake + phase publiee par `water-shore` ; humidite a l'eau.
15. Place dans la file : priorites 80-101, apres l'herbe ; pilotes dans l'ordre de la section 15.
16. Item adjacent des effets de pas dpsnow : NON CREE, en attente d'un mot de l'owner.

---

## 17. CE QUI N'EST PAS DANS CETTE CAMPAGNE

Corps persistants, cadavres, ragdolls ; simulation granulaire ; toute modification de collision, de
navigation ou de gameplay ; refonte du terrain ; refonte de l'eau ; meteo ; boue (swamp), cendres et
toute autre matiere ; les caisses comme interacteurs mobiles ; misty (terre) ; le fond marin ; le trou
des effets de pas dpsnow (item adjacent, a decider) ; toute analyse geometrique au chargement ; le
compute, la tessellation, les OBB — parce qu'ils n'existent pas ou ne sont pas exerces sur les cibles.
