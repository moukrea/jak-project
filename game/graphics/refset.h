#pragma once

// refset — LES DEUX JEUX D'IMAGES DE REFERENCE, ET LEUR REJEU.
//
// POURQUOI. SPEC-refonte-lumiere.md §7.3 : la refonte de l'eclairage compte douze items, et
// chacun peut casser silencieusement le rendu d'un autre. La garde est un couple de jeux
// d'images :
//   ORIGINE   (`recharged_master` OFF)  — ne bouge JAMAIS, `maxdiff == 0`.
//   RECHARGED (master ON, prereglage fige) — ne bouge que si l'item le declare.
// Elle est posee par l'item 0 et REJOUEE a la fermeture de chaque item suivant.
//
// AUCUNE IMAGE N'EST UNE PREUVE : LE NOMBRE L'EST. Ce module ne montre rien. Il rejoue une
// course deterministe, relit le tampon de couleur, le compare octet a octet a la reference
// stockee, et publie `refset_replay_maxdiff` (le plus grand ecart absolu par canal, 0..255) et
// `refset_replay_diffpx`. C'est cette grandeur, et elle seule, qui ferme la porte.
//
// D'OU VIENT LE DETERMINISME. Rien d'invente : les quatre leviers existaient deja dans cet
// arbre et sont ceux que le harnais utilise depuis des mois.
//   1. `OG_LEVEL_WARP=<continue>` (+ `_POS`) pose Jak a un point nomme (kmachine.cpp:5660).
//   2. `OG_PAD_REPLAY_REPLAY=<demo>` ancre la course sur l'apparition de *target*, force TOUTES
//      les sources d'alea a une graine fixe, force un pas de temps de 1/60 s par image, et
//      neutralise l'entree (pad_replay.h). L'index est la frame de LOGIQUE, pas l'image
//      dessinee : le boot et le chargement, de duree variable, sont absorbes.
//   3. L'heure du jeu est reposee A CHAQUE IMAGE par `set-time-of-day` (hud-classes-pc.gc:1841)
//      depuis la valeur que ce module publie — l'horloge ne derive pas.
//   4. La capture passe par le chemin de capture d'ecran INTERNE : l'image est rendue a une
//      resolution FIXE (320x180, msaa 1) dans le FBO interne, donc la taille de la fenetre de
//      la machine qui rejoue n'entre pas dans la comparaison.
//   5. LES DEUX SORTIES DU RETIMEUR DE RENDU SONT NEUTRALISEES sous `OG_REFSET` seulement
//      (render_pace.cpp `alpha_micro()` rend 1e6, `skip()` rend faux ; le module RESTE arme, donc
//      `ee_timer()` continue de rendre l'horloge virtuelle).
//      C'etait la derniere entree de montre murale du chemin de dessin, et c'etait LA cause de
//      l'echec de l'essai 1 : `render_pace::alpha_micro()` publie la position du temps REEL
//      entre deux ticks, et deux consommateurs en reecrivent ce qui est dessine —
//      `cam-render-interp!` (cam-update.gc:246) retime trans + inv-camera-rot de *math-camera*,
//      `*anim-interp-alpha*` (drawable.gc:1107) retime les poses d'articulation. Mesure du
//      2026-09-06 : deux courses strictement identiques divergeaient sur la pose camera des
//      l'ancre+7 puis se figeaient a ~0,02 m, alors que la translation de *target* etait
//      bit-identique sur 900 images de logique. La preuve porte `refset_pace_alpha=1000000` et
//      `refset_raw_alpha_min/max` : le second dit que la grandeur supprimee VARIAIT vraiment,
//      sans quoi la neutralisation serait une clause vide.
// La capture est appariee a la frame de LOGIQUE de la chaine DMA rendue, pas au numero d'image
// du renderer : sans ca l'entrelacement des deux fils deciderait, a une frame pres, de quelle
// pose de Jak on garde la photo — et une frame d'ecart suffit a faire mentir la porte.
//
// CE QUI EMPECHE LA PORTE DE SE MENTIR A ELLE-MEME.
//   * En mode `capture`, `refset_replay_maxdiff` n'est PAS publie du tout. Une course qui
//     fabrique ses propres references ne peut donc pas passer la porte.
//   * En mode `replay`, la valeur vaut 254 des la premiere image et ne devient la vraie mesure
//     que lorsque les 16 etapes sont TOUTES faites : une course interrompue est rouge, jamais
//     vide. Une reference absente ou de taille differente rend 255.
//   * Les references sont capturees avec le recensement DESARME et rejouees avec le
//     recensement ARME : `maxdiff == 0` prouve alors, litteralement, que l'item 0 ne change
//     aucun pixel.
//
// LA STABILITE DE L'INSTRUMENT, ET COMMENT ELLE SE PROUVE (item `refset-replay-stable`).
// Un `maxdiff` juste ne suffit pas : il faut qu'il soit LE MEME deux fois. Mesure du 2026-09-06,
// meme binaire et memes references octet pour octet, quatre rejeux : 188, 0, 0, 184. La cause
// est NOMMEE, pas absorbee par une tolerance — `Loader::refresh_recharged_textures` amortissait
// la re-resolution des 2761 textures Recharged sur une borne en MILLISECONDES REELLES ; le jeu
// de references bascule `recharged-master?` a chaque etape, donc la photo tombait avant ou apres
// la fin de la passe selon la charge de la machine. Sous `OG_REFSET` cette borne est retiree et
// seule celle qui se compte en IMAGES reste (Loader.cpp), et `hotreload_rt_bound_hits` publie
// combien de fois la borne retiree AURAIT coupe : a zero, la neutralisation serait une clause
// vide.
// La grandeur de porte est `refset_replay_flaky` : le nombre de paires de rejeux CONSECUTIFS,
// meme binaire et memes references, dont le `maxdiff` differe. Elle porte sur des COURSES, donc
// le moteur tient un registre `<dir>/replay-ledger.txt` (une ligne par rejeu complet, avec
// l'empreinte du binaire et celle des 16 references) et publie le verdict qu'il en lit :
// `refset_replay_runs` lignes retenues, 254 tant qu'il y en a moins de CINQ, 255 si la course
// n'a pas pu se mesurer. Un binaire rebati ou une reference recapturee change une empreinte et
// perime le registre tout seul.
//
// PORTEE. Le jeu de references tourne SUR LES DEUX plateformes depuis le 2026-09-06. Sur
// bureau la capture part de `render_game_frame` (game/graphics/pipelines/opengl.cpp:655), sur
// appareil de `refset_capture_if_step` (android/android_opengl_renderer.cpp:1725), qui relit le
// FBO composite et le sous-echantillonne en 320x180 a bornes entieres. `refset_platform` dit
// laquelle a produit la course, et les deux familles d'images vivent dans des dossiers de noms
// DIFFERENTS : re-rendu en resolution interne d'un cote, sous-echantillonnage 4:3 de l'autre —
// les comparer est faux par construction, et le melange est rendu impossible a la PRODUCTION.
//
// LES DEUX PLATEFORMES NE TELEPORTENT PAS PAREIL, et c'est mesure, pas esthetique. Le plan
// re-lance `(start 'play <continue>)` a chaque etape ; sur arm64 le TROISIEME appel tue la
// course en SIGILL (`GK-DIAG A36-TREE VIOLATION ... tree-self`, puis signal 4) — `start`
// appelle `stop`, donc `kill-by-name 'target *active-pool*` suivi d'une vague de naissances
// dans le dead-pool-heap, et l'arbre de processus ne survit pas a la repetition. Sur appareil,
// le teleport par etape est donc ETEINT par defaut (`refset_warp_per_step=0`) : seul le
// re-teleport de l'etape 0 a lieu, celui qui supprime la dependance au chemin de chargement.
// Les instants des 23 autres photos se DEDUISENT de l'ancre du plan.

#include <cstdint>

namespace refset {

// Le harnais a-t-il demande un jeu de references ? (env `OG_REFSET=capture|replay`, propriete
// `debug.opengoal.refset`). Faux par defaut : le joueur ne subit jamais ce mode, qui deplace
// l'heure du jeu et bascule le master.
// Capture exige un OG_REFSET_DIR neuf : un chemin existant (meme un lien symbolique) est
// refuse avec un diagnostic et EXIT_FAILURE, avant toute ecriture de reference. Replay
// utilise les jeux existants ; les captures partielles doivent donc rester separees.
bool enabled();

// L'HORLOGE. `fn` rend *display* actual-frame-counter : +1 par image de logique SIMULEE,
// independamment de la cadence. Enregistree par le noyau jak1 (InitMachineScheme), appelee
// depuis le fil GOAL seulement.
void set_logic_frame_provider(int64_t (*fn)());
int64_t current_logic_frame();
// Renderer thread only: identity copied with the accepted DMA chain, never live GOAL memory.
void set_render_logic_frame(int64_t frame);
int64_t render_logic_frame();

// L'INSTANT ABSOLU DU PREMIER TELEPORT, en frames de LOGIQUE. Lu par `level_warp_maybe`
// (kmachine.cpp) A LA PLACE de son delai apres readiness : ce delai depend de la vitesse de
// chargement, et une frame de logique d'ecart entre deux courses suffit a rendre 30 % des
// pixels differents. `OG_REFSET_WARP_AT` / `debug.opengoal.refset.warpat`, defaut 900.
int64_t warp_at_frame();

// L'ANCRE, prise AU POINT DE L'EVENEMENT et non par un sondage par image. Appelee par le warp
// de niveau juste apres `(start 'play <continue>)`. Le PREMIER appel n'ancre rien : il arme le
// second warp (voir `wants_rewarp`). C'est le SECOND qui pose l'ancre.
//
// Pourquoi pas un sondage : `pc_autoport_frame` tourne une fois par image RENDUE, alors que le
// compteur de frames de logique avance a chaque image SIMULEE. Pendant un chargement les deux
// se desynchronisent, et l'ancre lue par sondage tombait a 601 dans une course et 600 dans la
// suivante — une frame de logique d'ecart, donc une pose de Jak differente, donc 30 % des
// pixels differents (mesure du 2026-09-06 : maxdiff 172-215, diffpx ~17000 sur 57600).
void note_anchor();

// LE SECOND WARP, ET POURQUOI IL EXISTE. Le chargement du niveau est asynchrone : `(start 'play
// <continue>)` rend la main avant que `village1` soit entierement resident, et la camera passe
// donc quelques images a se poser contre une geometrie incomplete. Son point de repos depend du
// chemin : mesure du 2026-09-06, deux rejeux STRICTEMENT identiques divergent a partir de
// l'ancre+7, se figent a ~0,02 m d'ecart, et rendent 27000 pixels differents sur 57600 — alors
// que la translation de Jak est bit-identique sur 900 images de logique.
// Le second warp re-lance `(start 'play <continue>)` 600 images de logique plus tard, quand le
// niveau est entierement charge : la camera est alors TELEPORTEE depuis un monde complet, et son
// point de repos ne depend plus de la vitesse du disque.
// Rend vrai UNE seule fois, l'image ou il faut le declencher.
bool wants_rewarp();

// Une image de plus (appelee depuis `pc_autoport_frame`, fil GOAL). Fait avancer le plan.
void tick();

// LA CADENCE DU PLAN : UNE FOIS PAR FRAME DE LOGIQUE, JAMAIS PAR IMAGE RENDUE.
//
// LE DEFAUT QUE CETTE FONCTION FERME (essai 4, mesure du 2026-09-06 sur eae4df44). `note_anchor`
// avait deja quitte le sondage par image (voir ci-dessus), mais les DEUX autres consommateurs du
// plan — `wants_rewarp` et `tick` — restaient appeles depuis `pc_autoport_frame`, c'est-a-dire
// une fois par image RENDUE. Deux courses au meme .so, aux memes proprietes et au meme
// `refset_warp1_lf=600` ont alors rendu `REFSET start lf=902` a la capture et `lf=903` au rejeu,
// puis une ancre de re-teleport `refset_plan_base_lf=906` contre `908`. Consequence mesuree sur
// `origine/h00` : 18766 pixels differents sur 57600 (32,6 %), dont 10431 a 1-2 niveaux pres, et
// un maxdiff de 118 — avec un meilleur recalage entier de dx=0 dy=0, donc PAS un deplacement de
// camera : une autre PHASE d'animation. Le verdict 4 de `lighting-hdr` demande zero.
//
// CE QU'ELLE FAIT. Elle se de-duplique sur la frame de LOGIQUE : le premier appel d'une frame
// donnee rend vrai, les suivants faux. Elle est donc appelable depuis les deux points sans
// compter deux fois :
//   - le chemin LOGIQUE, `pad_replay::on_cpad_read` (manette 0) via le rappel de pas de temps,
//     qui tourne exactement une fois par image SIMULEE — c'est lui qui cadence le plan ;
//   - le chemin RENDU, `pc_autoport_frame`, conserve en REPLI pour les courses sans harnais de
//     rejeu d'entrees (sans lui, un plan lance sans `padreplay` ne demarrerait jamais).
// `from_logic` ne change AUCUN comportement : il ne sert qu'a publier `refset_pump_logic` et
// `refset_pump_render`, sans quoi « le plan est cadence par la logique » serait une affirmation
// invérifiable dans la preuve.
bool begin_logic_frame(bool from_logic);

// L'heure du jeu que l'etape courante impose, en heure*100 ; -1 quand le module n'impose rien.
// Consomme par `pc_get_tod_hour` (kmachine.cpp), donc applique par GOAL a chaque image.
int tod_override_x100();

// FIL GRAPHIQUE. La chaine DMA qu'on s'apprete a rendre porte la frame de logique `lf`.
// Rend vrai si cette chaine-la est celle qu'une etape attend ; remplit alors le nom de sortie
// et la resolution de capture.
bool capture_for_chain(int64_t lf, char* name_out, int name_cap, int* w, int* h);

// ── LA COUVERTURE, MESUREE ET PAS DECLAREE (lighting-census, owner 2026-09-07) ───────────────
// L'owner demande TOUS les niveaux, exterieurs ET interieurs. Trois grandeurs le disent, et
// aucune ne se lit dans la table de vantages — une porte qui lirait sa propre table serait un
// miroir :
//   `refset_levels`          niveaux DISTINCTS dont la geometrie etait en service au moment
//                            d'une photo (le nom vient du chargeur, pas de la table).
//   `refset_sky_views`       vues dont TOUTES les photos portent au moins 15 % de pixels
//                            d'arriere-plan, c'est-a-dire de ciel.
//   `refset_interior_views`  vues dont AUCUNE photo ne porte plus de 1 % d'arriere-plan : la
//                            geometrie enferme la camera.
//
// COMMENT « PIXEL DE CIEL » SE MESURE. Le decor de jak1 teste la profondeur en GEQUAL avec la
// convention PS2 inversee (`background_common.cpp:164-180`), et la profondeur est effacee a
// **0,0** (`OpenGLRenderer.cpp:1450`) : 0 est donc le PLUS LOIN. Le ciel est dessine au bucket 3
// (`buckets.h:10`), avant tout le decor, par un `DirectRenderer` dont le paquet GS n'a pas de
// `zmsk` (`sky-tng.gc:716`) et qui porte le z du fond. Un pixel encore a 0 apres le dernier
// bucket 3D est donc un pixel que rien n'a couvert : le ciel, ou le vide dans un niveau a
// `:sky #f`. Ce n'est pas une deduction de ce commentaire, c'est la convention DEJA en service
// dans cet arbre : `ao_ssao.frag:67` teste `d <= 0.000001` et l'appelle « sky / far ».
//
// LE POINT DE LECTURE EST CHOISI, PAS PRIS AU HASARD. La sonde tourne au bucket
// `DEPTH_CUE` (64), AVANT son rendu : les 64 premiers buckets — ciel, ocean lointain, tfrag,
// tie, shrub, alpha, ombres, eau, `OCEAN_NEAR` — ont tous ecrit, et aucun `DirectRenderer` 2D
// n'a encore touche la profondeur. Lire a `finish_screenshot` mesurerait le HUD : sous refset
// `game_res == draw_region`, donc `split_active` est FAUX et la 2D ecrit dans le MEME FBO.
//
// PORTEE HONNETE : un pixel couvert seulement par une surface qui n'ecrit PAS la profondeur
// (certains alphas) compte comme arriere-plan. La mesure est donc un MAJORANT du ciel ; c'est
// pour ca que `refset_sky_views` prend le MINIMUM sur les photos d'une vue et que le
// denominateur (`refset_bg_px`) est publie a cote.
// Le releve des niveaux tourne a CHAQUE image d'une course de reference (il date l'instant ou le
// niveau attendu devient dessinable, d'ou `refset_load_margin_min`) ; la relecture de profondeur,
// elle, ne tourne que sur les 174 images photographiees.
bool wants_level_census();
bool wants_scene_probe();
void note_scene_probe(uint64_t bg_px, uint64_t total_px);
void note_level_in_use(const char* level_name);

// FIL GOAL. Quels niveaux ONT un ciel, lu dans `level-load-info.sky` — la donnee que
// `sky-tng.gc:901` teste lui-meme avant d'emettre le DMA du ciel. Appele une fois par image et
// par niveau ACTIF depuis `hud-classes-pc.gc`. C'est la SOURCE de `refset_sky_levels`, et elle
// est deliberement disjointe de la mesure de pixels qui alimente `refset_sky_missing` : une
// porte dont l'ensemble de depart se deduit de sa propre sortie ne peut pas echouer.
void note_level_sky(const char* level_name, int has_sky);

// ── LA CAMERA EPINGLEE ──────────────────────────────────────────────────────────────────────
// `note_warp_pose` : fil GOAL, appele par `level_warp_run` juste avant le `(start 'play ...)`,
// avec la position ou Jak va apparaitre (metres) et son quaternion de cap. C'est la seule
// entree du calcul ; il ne lit AUCUN etat de la camera du jeu, donc il ne peut pas heriter du
// point de repos de `cam-string` ni de la vitesse du chargement.
// `camera_pin` : fil GOAL, une fois par image dessinee. Rend la pose a imposer — position en
// metres et vecteur avant unitaire — ou faux si la camera du jeu doit garder la main.
// Pourquoi la camera du jeu ne peut pas servir : `target-continue` (target-death.gc:166) laisse
// la camera en `cam-string`, qui se replace derriere Jak, a l'horizontale. Mesure du
// 2026-09-07 : sur 26 points de vue, le ciel occupe au mieux 119 pour mille de l'image et huit
// vues n'en montrent aucun. La porte de l'owner en demande 150.
void note_warp_pose(const float* trans_m, const float* quat);
bool camera_pin(float* out_trans_m, float* out_fwd);

// FIL GRAPHIQUE. Le tampon de couleur vient d'etre relu (RGBA, deja retourne a l'endroit).
// Rend vrai si c'etait notre capture — l'appelant n'ecrit alors pas le PNG de capture d'ecran.
bool consume_capture(int w, int h, const void* rgba);

// ── lighting-hdr : quatre des six verdicts de `hdr_tonemap_defects` ─────────────────────────
// Convention identique pour les quatre : 0 = tenu, 1 = defaut. Il n'y a PAS de valeur « pas
// mesurable » : une grandeur qu'on n'a pas pu mesurer est un defaut. Sinon une course
// interrompue rendrait quatre zeros et fermerait la porte sans avoir rien prouve.
// Le jeu de reference des verdicts 1 et 2 est ORIGINE-LUMIERE (master ON, eclairage OFF) : la
// configuration que l'owner joue, et celle qu'aucun des deux jeux d'origine n'exercait.
// ── lighting-hdr essai 6 : LES DEUX GESTES QUI RENDENT LA PHOTO REPRODUCTIBLE ───────────────
// LE DEFAUT MESURE (2026-09-06, eae4df44, images du plan relues pixel a pixel). Le seul objet
// qui differe entre la reference et le rejeu de la phase 1 (master OFF, ou notre chaine ne
// dessine RIEN) est le FEU de la hutte de Samos et la lumiere qu'il jette :
//     h00..h12  12132..12140 px differents sur 57600, contenus dans une boite en bas a gauche
//     h15/h18/h21  ~25400 px : aux heures ou le feu est la source dominante, sa phase repeint
//                  tout l'ecran ; hors de la boite du feu et hors du compteur FPS il reste
//                  4400 px de jour et 16400 px au crepuscule, c'est-a-dire son ECLAIRAGE.
// Sa phase est posee A LA NAISSANCE de l'acteur (`sparticle-launcher.gc:590` prend
// `real-actual-frame-counter`, `:604` prend `*particle-300hz-timer*`), donc a une frame de
// logique qui depend de la vitesse du chargement asynchrone. Le re-teleport de l'ancre ne la
// remet pas a zero : `reset-actors` n'est pas appele.
//
// LE MEME OBJET FAIT ECHOUER LES VERDICTS 1 ET 2, par un autre chemin. Ces deux verdicts
// apparient RECHARGED et ORIGINE-LUMIERE au meme creneau, mais a 180 frames de logique d'ecart
// (`refset_pair_gap_lf`), et le feu se decorrele en bien moins que 3 secondes. Mesure du
// 2026-09-06, contraste du decile le plus lumineux decompose par region :
//     h03  tout 83,8 %   |  DANS le feu 59,0 %  |  hors du feu  99,4 %
//     h06  tout 87,4 %   |  DANS le feu 68,0 %  |  hors du feu  99,5 %
//     h15  tout 92,4 %   |  DANS le feu 67,7 %  |  hors du feu 102,9 %
//     h21  tout 99,2 %   |  DANS le feu 104,3 % |  hors du feu  98,5 %
// Hors du feu la courbe preserve le detail partout ; le deficit est ENTIEREMENT la phase du
// feu, et elle joue dans les deux sens (59 % a h03, 104 % a h21). Le plancher de bruit de
// l'instrument le confirme : la MEME configuration photographiee dans DEUX courses rend des
// rapports de 91 a 119 %, alors que le verdict 2 exige 95 %. On ne mesure pas une courbe avec
// un instrument dont le bruit depasse son seuil.
//
// LES DEUX GESTES, ET POURQUOI CE SONT DES GESTES ET PAS UNE TOLERANCE.
//   * `wants_particle_repin()` — a l'ancre du plan, une frame de logique FIXE, tous les
//     lanceurs de particules sont re-ancres (`kill-and-free-particles` remet `local-clock` a 0
//     et efface `particles-active`, si bien que `spawn-time` se repose sur l'instant courant).
//     La phase du feu cesse de dependre du chemin de chargement. Rend vrai UNE seule fois.
//   * `freeze_particles()` — a partir de l'instant de la PREMIERE photo, le temps des
//     particules est fige (`*sp-frame-time*` a zero). Les 24 photos du plan voient alors
//     EXACTEMENT le meme feu : l'appariement des verdicts 1 et 2 ne compare plus que la
//     configuration d'eclairage, ce qu'il est cense mesurer. Le feu reste DESSINE et reste la
//     haute lumiere dominante — on ne retire pas l'objet de la mesure, on retire son
//     scintillement de l'ecart entre les deux photos.
// Les deux sont sans effet hors `enabled()` : le joueur ne les rencontre jamais.
// `refset_parts_repins`, `refset_parts_repin_lf` et `refset_parts_frozen_frames` sont publies :
// a zero, ces deux clauses seraient invérifiables.
//   * `particle_step_mode()` — LE PAS DES PARTICULES, UN PAR FRAME DE LOGIQUE, ET RIEN QUE UN.
//     Rend 2 hors du plan (le moteur garde son chemin normal), 1 la premiere fois qu'on le
//     consulte dans une frame de logique NEUVE (le GOAL pose alors un pas FIXE de 5 unites de
//     1/300 s, soit 1/60 s — la duree d'un tick du plan), 0 sinon : appel repete dans la meme
//     frame de logique, ou plan arrive a sa premiere photo (gel).
//     POURQUOI CE N'EST PAS UN BOOLEEN DE GEL. Mesure du 2026-09-06 sur eae4df44 : deux rejeux
//     du MEME binaire, memes references, memes donnees, rendent `diffpx=380759` puis `505224`,
//     et l'ecart est ENTIEREMENT dans le feu — alors que le meme plan, meme politique de
//     teleport, rend `diffpx=0` sur x86. Ce qui differe entre les deux plateformes, c'est le
//     nombre d'images DESSINEES par image simulee. `process-particles` est appele depuis la
//     boucle d'affichage ; si elle tourne plus d'une fois par frame de logique, les particules
//     avancent d'autant de pas, et ce nombre-la depend de la charge de la machine. Le pas est
//     donc epingle sur la frame de LOGIQUE, exactement comme le lissage du cap du vent
//     (foliage_wind.cpp). `refset_parts_extra_calls` publie combien d'appels ont ete
//     supprimes : a zero, cette hypothese est FAUSSE et la clause est vide — c'est la mesure
//     qui tranche, pas ce commentaire.
bool wants_particle_repin();
int particle_step_mode();

//   * `mood_flame_pin()` — L'AUTRE HORLOGE DU FEU. `update-mood-flames` (mood.gc:366) avance un
//     compteur prive une fois par appel, et son appelant pend a `real-main-draw-hook`, hors de la
//     boucle de rattrapage : une fois par image DESSINEE. Le poids qu'il produit repeint, via
//     `interp_time_of_day`, tout ce que le foyer eclaire. Sous refset l'etat de flamme est repose
//     a une valeur FIXE a chaque appel ; hors refset la fonction rend -1 et rien ne change.
//     `refset_mood_pins` prouve que le geste a eu lieu, `refset_mood_span_min/max` prouvent que
//     le nombre d'images dessinees entre deux photos variait VRAIMENT — sans quoi la clause
//     serait vide.
int mood_flame_pin();

//   * `text_mute()` — LES INCRUSTATIONS DE TEXTE 2D NE SONT PAS DE LA SCENE. Le plan photographie
//     le hall de la hutte, ou Jak se tient a portee du maire : `process-taskable.gc:615` y
//     dessine l'invite « Appuie sur (O) pour parler. » — un texte blanc de 100 x 12 pixels sur
//     une image de 320 x 180. Il n'est pas dessine a chaque photo : il s'efface pendant qu'un
//     indice de niveau parle (`level-hint-displayed?`, meme fichier ligne 594), donc il est
//     PRESENT dans une photo du couple et ABSENT dans l'autre. Mesure du 2026-09-07 sur les 24
//     images de la course de 00:12 : dix etapes le portent (5, 8, 9, 13, 14, 17, 18, 19, 22, 23)
//     et quatorze non, la MEME liste que la course de 21:49 — c'est un etat du plan, pas du bruit.
//     Ses gradients valent 91 par pixel la ou le decor en vaut 13 : a lui seul il fait tomber
//     `hdr_hlc_pct_h03` de 101 a 82 et `h06` de 104 a 86, les deux seuls creneaux sous le seuil.
//     Sous refset, `print-game-text` est donc force en mode NO-DRAW : il calcule tout, il ne
//     dessine rien. Hors refset la fonction rend 0 et le joueur garde son texte, a la ligne pres.
//     Non-vacuite : `refset_text_steps_with` / `_without` comptent les photos ou le texte AURAIT
//     ete dessine. Si `_with` valait 0 ou 24, l'invite ne serait pas asymetrique et retirer le
//     texte n'expliquerait rien.
//     LA PHASE 1 EST EXEMPTEE (2026-09-07, `lighting-origin-bitexact`). L'atlas de police
//     `gamefontnew` est le seul site du recensement qui remplace la texture d'origine SANS
//     consulter le maitre : muettre l'invite retire de la scene le seul objet qui le dessine, et
//     la porte « maitre eteint => identique au bit » passerait au vert sur un defaut present.
//     Les phases 2 et 3, celles qu'apparient les verdicts de `lighting-hdr`, gardent le mute.
int text_mute();

int verdict_saturation();          // 1 — pixels satures RECHARGED <= ORIGINE-LUMIERE
int verdict_highlight_contrast();  // 2 — contraste du decile le plus lumineux >= 95 %
int verdict_master_off_bitexact(); // lighting-origin-bitexact : master OFF identique au bit a
                                   // ORIGINE-TOTAL. Sorti de lighting-hdr le 2026-09-07 ; publie
                                   // sous `origin_bitexact_defects`, hors de la somme HDR.
int verdict_origine_lumiere_set(); // 4 — le jeu ORIGINE-LUMIERE existe et sert de base

}  // namespace refset
