#pragma once

// Gcutscene-npc-flicker (owner 2026-08-31) — RECENSEMENT DES PNJ QUI CLIGNOTENT EN CINEMATIQUE.
//
// CE QUE C'EST, ET POURQUOI IL EXISTE UN MODULE A PART.
// -----------------------------------------------------
// L'owner : « le probleme des modeles des PNJ qui apparaissent, disparaissent et reapparaissent
// plusieurs fois pendant les cinematiques est revenu ! c'est pas la premiere fois ». Le defaut a
// deja ete corrige (Grecharged-hd-models3/4/5) et il est revenu. La garde laissee par ces
// phases-la etait le compteur `[hd-flicker] blackouts=` de Merc2.cpp :
//
//     $ grep -c 's_hd_blackout_events++' game/graphics/opengl_renderer/foreground/Merc2.cpp
//     0
//
// Le compteur est DECLARE, IMPRIME, et JAMAIS INCREMENTE — le correctif « fail-open » de
// 45b7140ca7 a supprime son unique site d'increment et a laisse la ligne dans l'entete. Les trois
// jambes de preuve (hd4_x86_intro_flicker.sh, hd4_intro_blerc_leg.sh, hd5_proof_bonus.sh) exigent
// toutes `blackouts=0` et zero ligne `[hd-flicker] BLACKOUT` : deux conditions qu'AUCUN chemin de
// code ne peut violer. La garde etait donc VIDE, et elle serait passee au vert quoi qu'il arrive.
//
// DEUX CONSEQUENCES DE CONCEPTION, ET ELLES SONT LA RAISON D'ETRE DE CE FICHIER :
//   1. le recensement ne vit PAS sous `#ifdef OG_FEAT_HD_MODELS`. L'ancien detecteur ne voyait que
//      les acteurs COUVERTS par un modele HD ; un PNJ purement stock qui clignote ne produisait
//      aucune ligne. Ici la mesure est la meme avec les modeles HD allumes ou eteints, ce qui rend
//      l'ablation possible SUR LE MEME BINAIRE ;
//   2. c'est un module autonome, sans OpenGL et sans etat de jeu, exactement comme
//      game/system/load_gate.cpp — donc il se compile seul et ses proprietes se PROUVENT sans
//      appareil et sans course (.autoport/npc_flicker_selftest.sh). Le controle positif fait
//      partie de la garde : le test echoue si le compteur ne MONTE PAS quand on lui injecte une
//      disparition. C'est precisement ce qui manquait a la garde precedente.
//
// LA GRANDEUR MESUREE, ET SON REPERE.
// -----------------------------------
// Nature du defaut : une PRESENCE qui s'interrompt puis revient — pas une amplitude, pas une
// frequence. On mesure donc, par acteur et par image, « quelque chose a-t-il ete DESSINE pour
// lui », et on compte les EPISODES d'absence encadres par deux presences.
//
// Repere : l'image RENDUE. Cote rendu, `note_draw` est appele pour chaque paquet merc a son issue
// (dessine / supprime par la couverture HD / modele absent du chargeur). Cote GOAL, le recensement
// tourne dans `post-sync-draw` (main.gc), c'est-a-dire APRES la passe de dessin de la meme image :
// le bit `was-drawn` (draw-status 3, « passe les tests de culling ») y est donc celui de CETTE
// image, et il separe proprement deux familles :
//     was-drawn = 1 et rien de dessine  -> la perte est cote RENDU   (supprime / modele absent)
//     was-drawn = 0                     -> la perte est cote GOAL    (mort / hidden / no-anim /
//                                                                     culling)
//
// Ligne de base quand le defaut est ABSENT : un acteur present a l'ecran d'un bout a l'autre de la
// cinematique rend `cycles=0` avec `frames=` egal a la duree de la scene. Une scene ou l'acteur
// n'apparait jamais rend `frames=0` et ne compte pour rien — un episode ne s'ouvre qu'apres une
// PREMIERE presence dessinee, sinon un PNJ absent par conception compterait comme un defaut.
//
// CE QUE LE COMPTEUR NE COMPTE PAS, ET C'EST VOULU. Un episode plus court que
// `kMinEpisodeFrames` images est publie separement (`blinks=`) et n'entre pas dans `cycles=` :
// le recensement GOAL et le compteur d'images du rendu sont deux horloges differentes et leur
// decalage vaut au plus une image. Sous-compter est honnete ; sur-compter fabriquerait un faux
// rouge, qui coute aussi cher qu'un faux vert.

#include <cstdint>
#include <string>
#include <vector>

namespace npc_flicker {

// --- cote rendu -------------------------------------------------------------
enum class Outcome {
  kDrawn = 0,       // le paquet a ete accepte et dessine
  kSuppressed = 1,  // la couverture HD a jete le paquet stock (Merc2, per-pid TTL)
  kMissing = 2,     // le modele merc n'est pas resident dans le chargeur
  // Gcutscene-npc-flicker-2 (cycle 3) : le paquet a ete DESSINE, mais ses matrices d'os sont
  // INVALIDES (NaN/inf, os projete a des kilometres de la camera, ou matrice nulle). Un tel
  // dessin ne met RIEN a l'ecran : les sommets partent a l'infini ou s'effondrent en un point.
  // C'etait l'angle mort structurel du recensement : « GOAL a soumis, le rendu a dessine » etait
  // compte comme une presence, alors que l'oeil ne voit rien. Le rendu continue de dessiner le
  // paquet tel quel — c'est une MESURE, pas une correction.
  kGarbage = 3,
};

// Un paquet merc vient d'etre traite pour l'acteur `owner_pid`. Pour un paquet de COMPAGNON HD,
// `owner_pid` doit etre le pid du DRIVER (l'acteur du jeu), pas celui du compagnon : c'est le
// personnage qui est visible ou non, pas le processus qui le dessine.
//
// `merc_name` (2026-09-03) : LE NOM DU MODELE DESSINE, ET C'EST LA SECONDE CLE.
// Le pid seul a un angle mort structurel : pendant une cinematique, le personnage a l'ecran n'est
// pas toujours dessine par SON process. Jak passe en `target-clone-anim` et c'est un CLONE, avec
// son propre pid, qui porte le modele. Le recensement, indexe sur le pid du process recense,
// voyait alors « rien de dessine » pendant que le modele etait bel et bien a l'ecran — mesure du
// 2026-09-03 sur `mayor-introduction` : `eichar-lod0` compte 1132 images « dans le champ et rien
// de dessine » sur 3719. L'owner ne voit pas des pid, il voit des MODELES : on note donc aussi le
// nom, et une presence vaut si l'un OU l'autre repond. Sous-compter est honnete, sur-compter
// fabriquerait un faux rouge.
void note_draw(uint32_t owner_pid, Outcome outcome, bool is_hd_model, const char* merc_name);

// Une image rendue de plus. Appelee une fois par image (Merc2::render deduplique).
void end_render_frame(uint64_t frame_idx);

// --- cote GOAL (une fois par image, uniquement pendant une cinematique) ------
// `scene` = nom de la cinematique en cours, ou nullptr / "hors-cinematique" pour la terminer.
void begin_census(const char* scene);

// Un acteur du recensement. `draw_status` est l'octet draw-status de jak1 :
//   bit0 needs-clip, bit1 hidden, bit2 no-anim, bit3 was-drawn, bit4 no-skeleton-update,
//   bit5 skip-bones, bit6 do-not-check-distance, bit7 has-joint-channels.
// `level_active` : 1 = le niveau de l'acteur dessine reellement — status 'active ET display?
// non-#f. Le second terme a ete AJOUTE au cycle 2 : `display-level <lev> #f` deconnecte le bsp du
// moteur de fond (level.gc:645) SANS changer `status`, donc lire `status` seul publiait 1 pour un
// niveau qui ne dessine plus, et l'episode retombait dans `culled`, non gate. Or
// `mayor-introduction` fait `(0 display-level beach special)` et le maire est un acteur de beach.
// 0 = il ne l'est plus, -1 = l'acteur n'a pas d'entite (il vit sur level-default, qui tourne
// toujours). Sans cette entree, « le niveau a ete desactive sous l'acteur » et « la camera l'a
// laisse hors champ » rendent le MEME etat : pas de paquet et `was-drawn` a 0.
// `in_fov` : LE CONTROLE INDEPENDANT DU CULLING, et la raison pour laquelle il vient de GOAL.
//   1 = la position RACINE de l'acteur (root trans, la source ecrite par sa logique) tombe dans le
//       frustum de la camera courante ; 0 = elle est dehors ; -1 = non evalue.
// Le moteur, lui, cull sur `draw origin + draw bounds` (drawable.gc:452-460) — une AUTRE source,
// ecrite par `do-joint-math!`, qui ne l'ecrit pas du tout quand l'acteur porte hidden ou no-anim
// (process-drawable.gc:240). Comparer les deux est donc une mesure, pas un miroir : elles ne
// peuvent diverger que si la sphere de culling a cesse de suivre l'acteur.
// `is_npc` : 1 quand GOAL a reconnu un `process-taskable` — le type du jeu pour les personnages
// avec qui on parle (mayor, sage, oracle, farmer...). C'est LA population que l'owner nomme :
// « les PNJ, pas Jak ni Daxter ». Le recensement suit tout le monde ; seul le compteur de la
// porte se restreint a cette population, et le compteur large est publie a cote pour qu'aucune
// exclusion ne se fasse en silence.
void census_actor(const char* proc_name,
                  const char* merc_name,
                  uint32_t pid,
                  uint32_t draw_status,
                  int level_active,
                  int in_fov,
                  int is_npc);

void end_census();

// Cycle 3 : a la fin de chaque scene, une ligne `NPCCULL scene= pnj= dans_frustum_et_culled=N
// images_dans_frustum=M images= plateforme=` par acteur — N = images ou la racine est DANS le
// frustum, l'acteur n'est ni hidden ni no-anim, et was-drawn vaut 0 quand meme (ecarte du rendu
// pendant qu'il est dans le champ). Par IMAGE, pas par episode : un trou d'une image y compte.

// Un CLONE de cinematique (`clone-anim-once`, engine/common-obs/generic-obs.gc) n'a pas pu suivre
// sa source cette image et s'est pose `hidden` lui-meme. C'est le SEUL moyen de separer ce
// masquage-la d'un masquage voulu par le jeu : les deux posent le meme bit. Les figurants des
// cinematiques (sidekick-human, evilsis, allpontoons, les deux mineurs...) sont des clones, et
// une anim de scene est STREAMEE : le slot de son groupe d'art peut etre delie sous ses pieds a
// chaque frontiere de partie — 22 pour `sage-intro-sequence-a`, 16 pour `mayor-introduction`.
void note_clone_remap_fail(const char* merc_name);

// LE CORRECTIF, ET SON POINT DE PRODUCTION (2026-09-03).
// `clone-anim-once` posait `hidden` sur LUI-MEME des que `joint-control-remap!` rendait #f
// (generic-obs.gc:81). En dessous : une anime de cinematique est STREAMEE ; a chaque frontiere de
// partie, `ja-play-spooled-anim` appelle `(update *art-control* #f)` (loader.gc:1193-1195), et
// `unlink-art!` (loader.gc:202-222) remet a #f les slots du groupe d'art MAITRE. Le PILOTE se
// protege — il attend `(!= (file-status ...) 'active)` (loader.gc:1197-1207) ; la boucle
// `clone-anim` (generic-obs.gc:89-91) n'a AUCUNE attente equivalente. Le clone ne retrouve donc
// plus son anime, se masque, et `dma-add-process-drawable` (drawable.gc:448) refuse de soumettre
// quoi que ce soit : le modele DISPARAIT, puis revient des que le remap repasse. Une frontiere de
// partie = un clignotement.
// La correction precedente (45b7140ca7) n'a touche que la suppression du paquet stock cote C++
// (Merc2, couverture HD). Elle ne pouvait pas tenir : quand le clone est `hidden`, GOAL n'emet
// AUCUN paquet et il n'y a rien a laisser passer.
//
// CE QUE FAIT LE CORRECTIF. Le clone garde la pose de l'image precedente au lieu de disparaitre.
// C'est gratuit et sur : `draw-bones` (bones.gc:1141-1147) n'inscrit qu'un POINTEUR sur
// `(-> draw skeleton bones)`, un tableau PERSISTANT (mspace-h.gc:41) que seul `do-joint-math!`
// ecrit (process-drawable.gc:267). Ne pas l'appeler = la pose de l'image precedente, jamais une
// pose de bind.
//
// BORNE EN TEMPS, PAS EN IMAGES. Un echec TRANSITOIRE (une frontiere de partie) dure une a trois
// images ; un echec PERMANENT (l'anime n'existe pas dans le groupe du clone) durerait toute la
// scene, et un modele fige dix secondes serait un autre defaut. Au-dela de `kCloneHoldMs`, on
// retombe exactement sur l'ancien comportement, et le compteur `npc_clone_hold_expired` le dit.
// Rend faux quand la feature est DESARMEE : c'est le bras d'ablation du harnais.
bool should_hold_clone(uint32_t pid);
int clone_hold_ms();

// LE CORRECTIF DE LA COUVERTURE HD, ET SON OCCASION.
// `jak-hd.gc` eteignait le compagnon HD des que le pilote portait `no-anim` plus de N images.
// Or `drawable.gc:446` refuse DEJA de dessiner le stock sous `no-anim` : eteindre le compagnon
// ne rend pas la main au stock, ca laisse un TROU. Mesure sur le Redmi, 2026-09-03 :
// `[JAK-HD] noanim-run entry=1 images=8 seuil=4 bloque=1` — 8 images sans rien a l'ecran.
// `note_hd_noanim_cover()` compte les images ou le compagnon EST MAINTENU alors que l'ancien
// code l'aurait eteint : c'est l'OCCASION, sans laquelle un zero ne voudrait rien dire.
void note_hd_noanim_cover();

// --- lecture ----------------------------------------------------------------
struct Totals {
  uint64_t scenes = 0;
  uint64_t actors = 0;
  uint64_t cycles = 0;   // episodes DEFECTUEUX (voir la note sur les causes gatees)
  uint64_t coupes = 0;   // episodes explicables : hors du frustum, ou masque volontairement
  uint64_t longues = 0;  // episodes de cause DEFECTUEUSE mais plus longs que la borne haute
  uint64_t blinks = 0;   // episodes de 1 a kMinEpisodeFrames-1 images (publies, non gates)
  uint64_t by_reason[11] = {};  // indexe par Reason
  uint64_t frames = 0;
  // cycle 3 : sommes des lignes NPCCULL (par image, cf. end_census)
  uint64_t in_fov_frames = 0;
  uint64_t in_fov_culled_frames = 0;
  // 2026-09-03 — LA GRANDEUR DE LA PORTE, ET POURQUOI ELLE N'EST PAS `in_fov_culled_frames`.
  // Cette derniere exige `!was-drawn && !hidden && !no-anim`. Elle est donc AVEUGLE a trois
  // familles entieres de disparition : un acteur que le jeu masque pendant qu'il est a l'ecran
  // (`hidden`), un acteur entre deux segments d'animation (`no-anim` — et `do-joint-math!` ne
  // tourne pas non plus, donc rien n'est dessine), et toute perte COTE RENDU (couverture HD,
  // modele non resident, matrices d'os invalides) qui laisse `was-drawn` a 1. Sur le Redmi,
  // `mayor-introduction`, le 2026-09-03 : `dans_frustum_et_culled=0` pour les sept acteurs, dont
  // le maire, alors qu'il n'etait pas dessine pendant 55 images d'affilee (2117 ms).
  // Celui-ci compte ce que l'OWNER voit : l'acteur est dans le champ, et RIEN n'est a l'ecran
  // pour lui. Aucun bit de statut n'excuse — du point de vue de l'oeil, ils produisent tous la
  // meme chose. Ne compte qu'apres une PREMIERE presence dessinee dans la scene : un acteur qui
  // n'est jamais apparu n'a pas disparu.
  uint64_t in_fov_dark_frames = 0;      // toute la population recensee
  uint64_t in_fov_dark_frames_npc = 0;  // les `process-taskable` seuls — la porte
  uint64_t in_fov_frames_npc = 0;       // le denominateur : un zero sans lui serait muet
};

// DEUX FAMILLES, ET LA DISTINCTION PORTE LE VERDICT.
//   GATEES (comptees dans `cycles`) : rien dans le jeu n'a demande que l'acteur disparaisse.
//     mort / noanim / supprime / modele-absent / niveau / clone / nodraw / cull-aveugle.
//   EXPLIQUEES (comptees dans `coupes`, publiees, jamais gatees) :
//     culled  — GOAL a juge l'acteur hors du frustum, ET un test INDEPENDANT de sa position
//               racine le confirme hors champ. C'est le moteur qui fonctionne : une cinematique
//               COUPE d'un cadrage a l'autre.
//     hidden  — le jeu a explicitement pose (draw-status hidden). C'est une decision d'auteur.
//
// GCUTSCENE-NPC-FLICKER-2 : `culled` ETAIT UN FOURRE-TOUT, ET C'EST LA LE DEFAUT DE L'INSTRUMENT.
// Au cycle 1, `culled` recevait TROIS etats structurellement differents, tous non gates, et il
// portait 100 % des episodes observes (37 a 106 par course, sur les sept courses archivees de
// `.autoport/reports/Gcutscene-npc-flicker/` : `culled` = le seul seau non vide). Un seau exclu
// qui contient toute la population n'est pas une exclusion, c'est un angle mort — l'owner a
// revu le defaut, l'instrument publiait `cycles=0`.
// Les trois etats sont desormais separes, et les deux nouveaux sont des DEFAUTS :
//   * `culled`       was-drawn a 0 et le test independant de position dit « hors champ »   -> normal
//   * `cull-aveugle` was-drawn a 0 alors que la POSITION RACINE de l'acteur est DANS le frustum.
//                    Ce n'est donc pas la camera qui l'a laisse dehors : ou bien la sphere de
//                    culling que le moteur teste (draw origin + draw bounds, drawable.gc:452-460)
//                    a derive de l'acteur, ou bien il n'est jamais passe par la passe de dessin.
//                    Le test est INDEPENDANT parce qu'il porte sur une AUTRE source de position
//                    (`root trans`, ecrite par la logique) que celle que le moteur cull
//                    (`draw origin`, ecrite par do-joint-math! — et do-joint-math! ne l'ecrit PAS
//                    quand l'acteur porte hidden ou no-anim, process-drawable.gc:240).
//   * `nodraw`       was-drawn a 1 — GOAL a SOUMIS — et le rendu n'a rien dessine, sans que la
//                    couverture HD ni l'absence de modele l'expliquent. « Le jeu dit qu'il l'a
//                    dessine, l'ecran dit que non. » Couvre les sorties tardives de
//                    dma-add-process-drawable (skip-bones :611, LOD/distance :582/:594) et le
//                    debordement du moteur d'avant-plan.
enum Reason {
  kReasonDead = 0,        // le processus a disparu de l'arbre
  kReasonHidden = 1,      // (draw-status hidden)
  kReasonNoAnim = 2,      // (draw-status no-anim)
  kReasonCulled = 3,      // was-drawn a 0 ET la position racine est hors du frustum
  kReasonSuppressed = 4,  // GOAL a soumis, le rendu a supprime (couverture HD)
  kReasonMissing = 5,     // GOAL a soumis, le modele n'etait pas resident
  kReasonLevel = 6,       // le niveau de l'acteur ne dessine plus (status ou display?)
  kReasonRemap = 7,       // un CLONE de cinematique n'a pas pu suivre sa source et s'est masque
  kReasonNodraw = 8,      // GOAL a soumis (was-drawn) et RIEN n'a ete dessine, sans explication
  kReasonCullBlind = 9,   // was-drawn a 0 alors que la position racine EST dans le frustum
  kReasonGarbage = 10,    // dessine avec des matrices d'os INVALIDES : rien de visible a l'ecran
};
constexpr int kReasonCount = 11;
bool reason_is_defect(Reason r);
const char* reason_name(Reason r);

Totals totals();

// --- compteurs de PLATEFORME, DANS LA LIGNE DE SCENE (essai 11, 2026-09-04) -------------------
// LE DEFAUT N'EXISTE QUE SUR L'APPAREIL DE L'OWNER. Huit courses de `mayor-introduction` sur le
// Redmi (arm64, 20 img/s), trois sur x86 a 60 et ~110 img/s, pas fixe arme ou non : la scene est
// identique a la milliseconde, aucun cycle. Le Honor (Snapdragon 8 Elite, 60-120 img/s) montre le
// defaut a chaque fois, et son logcat est invisible. La SEULE trace qui en revient est le fichier
// `npc_flicker.txt` que ce module ecrit dans le dossier de reglages. Il doit donc porter, PAR
// SCENE, ce que l'hote sait des mecanismes qui n'existent que la-bas :
//   * les REPARATIONS arm64 (android/gk_android_main.cpp) : un joint-eval sur un frame-group nul
//     repare en « sauter l'anim de ce canal cette image » (= pas de dessin), un RET vers une
//     adresse pietinee redirige vers return-from-thread-dead (= le process MEURT), un store a
//     double base EE complete ou jete... chacune est UNE disparition possible d'un modele, et
//     aucune n'apparait dans les bits de draw-status ;
//   * la chaine DMA REJETEE (android/android_gfx.cpp, android_opengl_renderer.cpp) : une image
//     dont la chaine est corrompue est re-presentee (A42) ou un seau merc entier est saute (A37) —
//     tous les modeles du seau disparaissent UNE image ;
//   * la couverture HD (Merc2.cpp) : fail-open et trous de soumission du compagnon.
// npc_flicker ne connait ni Android ni OpenGL : l'hote et le rendu ENREGISTRENT une fonction qui
// remplit les cases qu'ils connaissent. Les index sont fixes, les noms publies sont dans
// `kPlatCounterNames`. Une case qu'aucune source ne remplit reste a 0 ET la ligne dit
// `sources=` : un zero sans source se lit « pas cable », jamais « sain ».
constexpr int kPlatCounterCount = 12;
enum PlatCounter {
  kPlatNullFg = 0,       // joint-eval sur frame-group nul, anim du canal sautee (nullfg)
  kPlatBareRet = 1,      // RET vers un offset GOAL nu, process deactive (bareret)
  kPlatDblEe = 2,        // store a double base EE, complete apres correction (dblee)
  kPlatKernCode = 3,     // idem mais cible = code du noyau : JETE (kerncode)
  kPlatEnterState = 4,   // enter-state avec code nul, repare (enterstate)
  kPlatRftd = 5,         // trampoline return-from-thread-dead pietine / RET nul (rftd)
  kPlatSuspend = 6,      // debordement de pile a la suspension, tolere (suspend)
  kPlatChainPrecopy = 7, // chaine DMA corrompue avant copie : image RE-PRESENTEE (precopy)
  kPlatChainLoop = 8,    // chaine DMA sans fin : image SAUTEE (chainloop)
  kPlatBucketBad = 9,    // seau DMA malforme : seau SAUTE (malformed)
  kPlatHdFailOpen = 10,  // couverture HD : fail-open, le stock redessine (hd_failopen)
  kPlatHdGap = 11,       // couverture HD : trou de soumission du compagnon (hd_gap)
};
extern const char* const kPlatCounterNames[kPlatCounterCount];
// `out` a `n` cases, deja a zero ; la source n'ecrit que les index qu'elle connait et verifie
// `n` avant d'ecrire. Sources : 1 = hote (Android), 2 = rendu (Merc2).
typedef void (*PlatformCountersFn)(uint64_t* out, int n);
void set_host_counters_fn(PlatformCountersFn fn);
void set_render_counters_fn(PlatformCountersFn fn);
// Ce que la derniere lecture a donne : masque des sources cablees, et cumul des deltas par
// scene depuis le debut (ce que publient `npc_plat_*`).
uint32_t platform_sources();
const uint64_t* platform_totals();  // kPlatCounterCount cases

// --- controle positif, sur le binaire LIVRE ---------------------------------
// Env OG_NPCF_INJECT="<fragment-de-nom>:<periode>:<duree>" — ETEINT par defaut. Quand il est
// arme, le rendu jette les paquets dont le nom contient <fragment> pendant <duree> images toutes
// les <periode> images. Un compteur ne vaut que s'il existe une entree qui le fait MONTER : la
// garde precedente n'avait pas ce bras, et son zero etait un zero de compilation.
bool inject_drop(const char* merc_name);

// Bornes de l'episode compte comme CLIGNOTEMENT. En dessous de la borne basse : `blinks`
// (l'ecart des deux horloges vaut au plus une image, sous-compter est honnete). Au-dessus de la
// borne haute : `longues` — l'owner decrit un PNJ qui « apparait, disparait et reapparait
// plusieurs fois pendant UNE cinematique » ; une absence de plusieurs secondes est un autre
// phenomene (un acteur reellement parti, un decor qui se recharge) et se signalerait comme « le
// PNJ manque », pas comme un clignotement. Mesure a l'appui : la seule absence de cause
// DEFECTUEUSE relevee sur `intro-start` etait une caisse morte pendant 1760 images (29 s).
int min_episode_frames();
int max_episode_frames();
int max_episode_ms();

void reset_for_test();

// --- Gcutscene-npc-flicker-2, cycle 3 : L'APPAREIL DE L'OWNER DEVIENT LISIBLE -----------------
// L'owner voit le defaut sur SON telephone, que personne d'autre ne peut observer ; les courses
// sur le Redmi et sur x86 rendent zero. Trois sorties de plus, toutes produites par le CODE :
//   * `plateforme=` sur chaque ligne publiee : "x86", ou la marque Android en minuscules lue
//     dans `ro.product.brand` ("redmi", "honor"). Une ligne dit ainsi d'elle-meme d'ou elle vient.
//   * les lignes NPCFLICK/NPCSCENE sont AUSSI ecrites dans un fichier du dossier de reglages
//     (`<dossier settings>/npc_flicker.txt`, borne en taille) — sur le telephone de l'owner,
//     c'est /storage/emulated/0/OpenGOAL/jak1/npc_flicker.txt, qu'il peut envoyer.
//   * `live_status()` : l'etat de la scene EN COURS, que le compteur FPS affiche a l'ecran pendant
//     une cinematique. L'owner lit un NOMBRE produit par le code, pas une image.
const char* platform_tag();
void set_log_path(const char* path);  // nullptr / "" = pas de fichier

struct Live {
  bool in_scene = false;  // une cinematique est recensee en ce moment
  uint64_t cycles = 0;    // cycles de cause DEFECTUEUSE fermes dans la scene en cours
  uint64_t blinks = 0;    // episodes trop courts pour etre comptes
  uint64_t coupes = 0;    // coupes de camera / masquages voulus
  int last_reason = -1;   // Reason du dernier episode DEFECTUEUX ferme, -1 si aucun
  uint64_t frames = 0;    // images de recensement de la scene en cours
};
Live live_status();

}  // namespace npc_flicker
