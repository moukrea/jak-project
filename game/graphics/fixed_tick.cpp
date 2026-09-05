// Gfixed-tick-interpolation — voir fixed_tick.h pour le raisonnement complet.

#include "fixed_tick.h"

#include <cmath>
#include <cstdlib>

#include "fmt/core.h"

#include "common/util/Timer.h"

#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace fixed_tick {

namespace {

// ---------------------------------------------------------------------------------------
// RECENSEMENT DE CONSERVATION DU TEMPS DE JEU (item `fixed-tick-interpolation`).
//
// LE DEFAUT DE L'OWNER, RAMENE A UNE SEULE GRANDEUR. « quand le jeu va en dessous de ce
// qu'il est sense tourner sur PS2, les sauts, les mouvements de camera ça chie un peu dans
// la colle et ça casse le gameplay (skips, camera jumps, sauts trop courts...) ». Un saut
// de Jak est une SUITE DE TICKS de 1/60 s : sa hauteur ne depend que du nombre de ticks
// passes en l'air. Il est donc identique a 25 comme a 120 images/s SI ET SEULEMENT SI la
// logique recoit 60 ticks par seconde REELLE quelle que soit la cadence d'affichage.
// C'est cette egalite, et rien d'autre, que ce recensement mesure — et c'est la seule
// chose qu'une porte machine peut lire de ce chantier, puisque « le saut a l'air bon » n'en
// est pas une.
//
// CE QU'IL COMPARE. Par fenetre de `kCensusWindowSeconds` secondes de temps mural ADMIS :
//     ecart = | ticks_emis / 60 - secondes_admises | / secondes_admises
// et la porte lit le MAXIMUM sur toutes les fenetres. Pas la moyenne : sous le balayage de
// cadence (`OG_FRAME_LIMIT_FPS`), une moyenne noierait le bras a 20 images/s — celui de
// l'owner — dans les quatre autres.
//
// « ADMIS » ET NON « ECOULE », ET POURQUOI CE N'EST PAS UN SEAU D'EXCLUSION. Une image dont
// la duree depasse `kMaxCatchupTicks` (chargement, hoquet de flux) voit son temps ECRETE :
// au-dela, l'horloge le JETTE, sinon le jeu part en spirale de rattrapage. Ce temps jete
// n'est pas une erreur de conversion, c'est une decision — mais il ne disparait pas de la
// preuve pour autant : il est compte EN ENTIER dans `tick_time_dropped_ms` et dans
// `tick_drift_ms`. Aucune fenetre n'est jamais ecartee ; ecarter les fenetres des cadences
// basses reviendrait a exclure exactement le cas que l'owner joue.
//
// LE PLANCHER DE LA MESURE est la quantification de l'accumulateur : un tick au plus par
// fenetre, soit 1/(60 * kCensusWindowSeconds) = 0,33 % a 5 s. Tout ce qui depasse est du
// temps de jeu FABRIQUE ou PERDU : un k mal choisi, un reste detruit, ou la REECRITURE de
// la duree d'image que fait le verrou de cadence (`dt = lock_n / 60`) — dont l'erreur
// propre est publiee a part, `tick_lock_err_pct_x100`, parce qu'elle ne vient pas de la
// conversion mais du fait de remplacer la mesure.
// ---------------------------------------------------------------------------------------
constexpr double kCensusWindowSeconds = 5.0;

// En dessous de ce nombre de fenetres il n'y a rien a juger, et un maximum sur zero
// echantillon vaut zero — c'est-a-dire un VERT obtenu par ABSENCE de mesure. On publie
// alors une valeur hors bande, qui fait ECHOUER la porte. Meme patron que
// `render_pace.cpp` (`kMinJudgedSteps` / `kNoMeasurement`).
constexpr u64 kCensusMinWindows = 8;
constexpr u64 kCensusNoMeasurement = 999999;

// Memes planchers pour l'invariant par image. `kMinLockTransients` est le plus important
// des trois : c'est le nombre d'images HORS GRILLE rencontrees PENDANT QUE LE VERROU TIENT,
// c'est-a-dire le nombre de fois ou le defaut corrige avait l'occasion de se produire. A
// zero, la porte serait verte sans avoir rien exerce. Le stimulus qui les produit est
// `OG_FRAME_SPIKE_EVERY` (game/graphics/pipelines/opengl.cpp).
constexpr u64 kMinConserveFrames = 600;
constexpr u64 kMinLockTransients = 8;

// Etat de l'horloge. Tout ceci ne vit QUE sur le fil GOAL/EE : `begin_render_frame`
// est appelee depuis la soumission de la chaine DMA, sur le fil GOAL/EE. Aucune synchronisation necessaire, et
// surtout aucune lecture depuis le fil graphique (ce serait une course).
struct State {
  Timer timer;
  bool have_last = false;
  double accumulator = 0.0;
  s32 alpha_micro = 1000000;  // 1.0 == pose courante == pas d'interpolation
  bool deterministic = false;
  bool disarmed_fast_display = false;
  // Gfixed-tick-anim-interp : « l'horloge gouverne cette image » n'est PLUS la meme
  // chose que « cette image porte un tick ». Au-dessus de 60 Hz elle gouverne des
  // images de RENDU SEUL, qui portent zero tick.
  bool clock_governs = false;
  u64 ticks = 0;
  u64 render_frames = 0;
  u64 armed_frames = 0;
  PublishFn publisher = nullptr;
  // Armement. `forced` vaut -1 quand l'environnement ne dit rien (le reglage du joueur
  // decide alors), 0 ou 1 quand il FORCE l'etat pour une course d'ablation.
  int forced = -2;  // -2 == pas encore lu
  bool armed_setting = false;
  // Moyenne glissante de la duree reelle d'une image. Sert UNIQUEMENT a decider si
  // l'affichage tourne plus vite que 60 Hz (perimetre de l'etape 1). Une decision
  // prise sur une frame isolee ferait clignoter l'armement a chaque hoquet.
  double dt_ema = kFixedTickSeconds;
  // Gfixed-tick-anim-interp-2 — VERROU DE CADENCE HYSTERETIQUE.
  // L'etat initial est VERROUILLE sur 1 tick : c'est le panneau 60 Hz, et c'est ce qui
  // rend une course a 60 images/s identique au bit DES LA PREMIERE IMAGE, sans passer
  // par une phase d'acquisition. Une cadence differente sort du verrou en
  // `kUnlockBadFrames` images.
  bool locked = true;
  double lock_n = 1.0;
  int good_run = kLockFrames;
  int bad_run = 0;
  double last_dev = 0.0;
  u64 lock_events = 0;
  u64 unlock_events = 0;
  u64 ceiling_clamps = 0;
  u64 catchup_clamps = 0;
  // essai 2 — CONSERVATION DU TEMPS DE JEU, IMAGE PAR IMAGE. Sur une image gouvernee,
  // le temps reel ADMIS doit se retrouver ENTIER quelque part : converti en ticks, ou
  // garde dans l'accumulateur.
  //     dt_admis  ==  k * kFixedTickSeconds + (accumulateur_apres - accumulateur_avant)
  // Tout ecart est du temps de jeu DETRUIT (un skip) ou FABRIQUE (un fast-forward). Le
  // recensement par fenetre de 5 s ne peut pas le voir : 23 ms detruites puis 16,7 ms
  // refabriquees dans la meme seconde se compensent dans un cumul. C'est exactement ce
  // qui est arrive a l'essai 1 (tick_drift_ms=1.0 pendant que le verrou reecrivait des
  // durees de 137 %), et c'est pour ca que cette grandeur est mesuree PAR IMAGE.
  double conserve_err_max = 0.0;  // en TICKS, tolerance du verrou deja retranchee
  u64 conserve_frames = 0;        // images jugees par l'invariant (transitions exclues)
  u64 lock_transients = 0;        // images HORS grille pendant que le verrou TIENT :
                                  // c'est LA condition du defaut. Si elle vaut zero, la
                                  // course n'a rien exerce et la porte doit echouer.
  double fabricated_sec = 0.0;    // temps fabrique par le rebase de sortie de verrou
  // Recensement de conservation du temps de jeu — voir le bloc de commentaire ci-dessus.
  // Montre SEPAREE de `timer` : celle-ci mesure la duree que l'horloge s'accorde (elle est
  // ecretee, et REECRITE par le verrou) ; celle-la mesure la duree REELLE, qui est la
  // reference contre laquelle on juge.
  Timer census_timer;
  bool census_have = false;
  double win_sec = 0.0;         // temps mural ADMIS accumule dans la fenetre courante
  u64 win_ticks = 0;            // ticks emis dans la fenetre courante
  double dev_max = 0.0;         // fraction, pas pourcentage
  double lock_err_max = 0.0;    // fraction
  double drift_sec = 0.0;       // (ticks/60 - mur admis) cumule, SIGNE
  double dropped_sec = 0.0;     // temps reel jete par l'ecretage, cumule
  u64 windows = 0;
  u64 census_frames = 0;
  u64 census_locked = 0;
  u64 prev_ticks = 0;
};

State& state() {
  static State s;
  return s;
}

// Lit la CONSIGNE D'ENVIRONNEMENT. Rend -1 quand elle est absente : dans ce cas le
// reglage du joueur (menu Recharged Settings) decide, et son defaut est DESARME.
//
// DEFAUT DESARME depuis le 2026-08-30 (superviseur). Ce chantier reecrit le pas de
// simulation — sauts, camera, seuils d'etat. Il etait actif par defaut dans le build
// publie a 17h32 et installe par l'owner, qui a vu le jeu planter. Une telle reecriture
// ne part pas armee chez lui sans qu'il l'ait demandee. `OG_FIXED_TICK=1` (ou la
// propriete Android a "1") l'arme pour nos propres mesures ; `...=0` la desarme meme si
// le joueur l'a activee. C'est l'ablation sur LE MEME BINAIRE qu'exigent les directives
// pour un avant/apres honnete, et c'est pour ca que l'environnement PRIME sur le menu.
int read_force_flag() {
  const char* e = std::getenv("OG_FIXED_TICK");
  if (e && (e[0] == '0' || e[0] == '1')) {
    return e[0] - '0';
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get("debug.opengoal.fixed_tick", pv) > 0 &&
      (pv[0] == '0' || pv[0] == '1')) {
    return pv[0] - '0';
  }
#endif
  return -1;
}

// Sonde de cadence, une ligne par image dessinee. Gate a part, parce qu'une sonde
// par-image livree ARMEE est un defaut deja paye (40 Mo de sortie en 220 s sur
// l'appareil). Sur Android stdout/stderr sont routes vers logcat
// (android/gk_android_main.cpp), donc la meme sonde sert aux deux plateformes — mais
// l'environnement n'y est pas reglable, d'ou la propriete.
bool read_probe_flag() {
  if (std::getenv("OG_FIXED_TICK_PROBE") != nullptr) {
    return true;
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get("debug.opengoal.fixed_tick_probe", pv) > 0 && pv[0] == '1') {
    return true;
  }
#endif
  return false;
}

// Gfixed-tick-anim-interp — lecture d'un interrupteur 0/1 avec un DEFAUT declare.
// L'environnement (bureau) prime, puis la propriete Android, sinon le defaut. C'est
// le meme patron que `read_force_flag`, et c'est ce qui permet l'ablation SUR LE MEME
// BINAIRE que les directives exigent : une course avec, une course sans, meme .so.
bool read_bool_flag(const char* env_name, const char* prop_name, bool dflt) {
  const char* e = std::getenv(env_name);
  if (e && (e[0] == '0' || e[0] == '1')) {
    return e[0] == '1';
  }
#ifdef __ANDROID__
  char pv[8] = {0};
  if (__system_property_get(prop_name, pv) > 0 && (pv[0] == '0' || pv[0] == '1')) {
    return pv[0] == '1';
  }
#else
  (void)prop_name;
#endif
  return dflt;
}

// Une image gouvernee par l'horloge vient de passer : on solde sa duree REELLE contre les
// ticks qu'elle a produits. Appelee APRES `begin_render_frame`, donc `s.locked`, `s.lock_n`
// et `s.ticks` decrivent deja la decision prise pour CETTE image.
void census_frame() {
  State& s = state();
  const u64 dticks = s.ticks - s.prev_ticks;
  s.prev_ticks = s.ticks;

  if (!s.census_have) {
    // Premiere image gouvernee, ou reprise apres un desarmement. C'est aussi l'image ou
    // l'horloge POSE dt = 1 tick au lieu de le mesurer (`have_last`) : il n'y a donc rien
    // a juger, on se contente de demarrer la montre.
    s.census_timer.start();
    s.census_have = true;
    return;
  }
  const double dt = s.census_timer.getSeconds();
  s.census_timer.start();

  s.census_frames++;
  if (s.locked) {
    s.census_locked++;
  }

  // TEMPS ADMIS : ce que l'horloge a accepte de convertir en ticks. Au-dela du plafond de
  // rattrapage elle jette, et le temps jete est compte ici en entier.
  const double ceiling = (double)kMaxCatchupTicks * kFixedTickSeconds;
  double admitted = dt;
  if (admitted > ceiling) {
    s.dropped_sec += dt - ceiling;
    admitted = ceiling;
  }

  // (`lock_err_max` est mesure dans `advance()`, AU SITE DE LA SUBSTITUTION : il jugeait ici
  //  toute image passee en etat verrouille, y compris celles dont la duree n'est PAS reecrite
  //  depuis le correctif de l'essai 2. Il publiait donc 300 % sur un build ou plus rien n'est
  //  reecrit — un chiffre rouge a cote d'une porte verte, c'est-a-dire le prochain faux
  //  diagnostic. Et la duree jugee ici vient d'une AUTRE montre que celle que l'horloge a
  //  utilisee : au site de la substitution, la comparaison porte sur la meme.)

  s.drift_sec += (double)dticks * kFixedTickSeconds - admitted;

  s.win_sec += admitted;
  s.win_ticks += dticks;
  if (s.win_sec >= kCensusWindowSeconds) {
    const double dev =
        std::fabs((double)s.win_ticks * kFixedTickSeconds - s.win_sec) / s.win_sec;
    if (dev > s.dev_max) {
      s.dev_max = dev;
    }
    s.windows++;
    s.win_sec = 0.0;
    s.win_ticks = 0;
  }
}

// Publie le recensement pour `lib/proof_run.sh`. Appelee a CHAQUE image, y compris quand
// l'horloge est desarmee : une course d'ablation doit porter `tick_armed=0` et la valeur
// hors bande, pas une absence de ligne — une cle absente et une cle a zero se lisent
// pareil dans un rapport, et l'une des deux est un faux vert.
void census_publish() {
  State& s = state();
  autoport_proof::publish("tick_armed", s.armed_frames > 0 ? 1 : 0);
  autoport_proof::publish("tick_frames", s.armed_frames);
  autoport_proof::publish("tick_ticks", s.ticks);
  autoport_proof::publish("tick_rate_windows", s.windows);
  autoport_proof::publish("tick_rate_dev_pct_x100",
                          s.windows >= kCensusMinWindows
                              ? (u64)(s.dev_max * 10000.0 + 0.5)
                              : kCensusNoMeasurement);
  autoport_proof::publish("tick_lock_err_pct_x100", (u64)(s.lock_err_max * 10000.0 + 0.5));
  autoport_proof::publish(
      "tick_locked_pct",
      s.census_frames ? (u64)((100.0 * (double)s.census_locked) / (double)s.census_frames + 0.5)
                      : (u64)0);
  autoport_proof::publish("tick_time_dropped_ms", (u64)(s.dropped_sec * 1000.0 + 0.5));
  autoport_proof::publish("tick_ceiling_clamps", s.ceiling_clamps);
  autoport_proof::publish("tick_catchup_clamps", s.catchup_clamps);
  autoport_proof::publish("tick_lock_armed", tick_lock_enabled() ? 1 : 0);
  autoport_proof::publish("tick_lock_strict", tick_lock_strict() ? 1 : 0);
  autoport_proof::publish("tick_lock_events", s.lock_events);
  autoport_proof::publish("tick_unlock_events", s.unlock_events);
  autoport_proof::publish("tick_lock_transients", s.lock_transients);
  autoport_proof::publish("tick_conserve_frames", s.conserve_frames);
  autoport_proof::publish("tick_time_fabricated_us", (u64)(s.fabricated_sec * 1e6 + 0.5));
  {
    // ERREUR DE CONSERVATION PAR IMAGE, en centiemes de pourcent d'un tick — la meme unite
    // que `tick_rate_dev_pct_x100` (une erreur relative x 10000).
    const double e = s.conserve_err_max > 0.0 ? s.conserve_err_max : 0.0;
    const u64 conserve_x100 = (u64)(e * 10000.0 + 0.5);
    autoport_proof::publish("tick_conserve_err_pct_x100", conserve_x100);
    // LA GRANDEUR DE LA PORTE. Le pire des deux ecarts entre le temps de jeu que l'horloge
    // declare et le temps reel : celui du cumul par fenetre de 5 s, et celui de l'image
    // isolee. Prendre le MAXIMUM et non l'un des deux est le point : l'essai 1 a publie un
    // cumul propre (0,20 %) pendant que le verrou reecrivait la duree d'une image de 137 %,
    // parce que la destruction et la refabrication se compensent dans un cumul.
    //
    // HORS BANDE SI LA CONDITION EST ABSENTE. Un maximum sur zero echantillon vaut zero,
    // c'est-a-dire un VERT obtenu en ne mesurant rien. Il faut donc : assez de fenetres,
    // assez d'images jugees, ET des images HORS GRILLE PENDANT QUE LE VERROU TIENT — la
    // condition exacte du defaut corrige. Sans elles, la course n'a rien exerce.
    const u64 rate_x100 = s.windows >= kCensusMinWindows
                              ? (u64)(s.dev_max * 10000.0 + 0.5)
                              : kCensusNoMeasurement;
    u64 worst;
    if (s.windows < kCensusMinWindows || s.conserve_frames < kMinConserveFrames ||
        s.lock_transients < kMinLockTransients) {
      worst = kCensusNoMeasurement;
    } else {
      worst = rate_x100 > conserve_x100 ? rate_x100 : conserve_x100;
    }
    autoport_proof::publish("tick_worst_dev_pct_x100", worst);
  }
  // Signe : un drift NEGATIF est du temps de jeu PERDU (le monde ralentit), un positif est
  // du temps FABRIQUE (il accelere). Les deux cassent le gameplay, et pas de la meme facon.
  autoport_proof::publish_text("tick_drift_ms",
                               fmt::format("{:.1f}", s.drift_sec * 1000.0).c_str());
}

}  // namespace

bool enabled() {
  State& s = state();
  // BRAS D'ABLATION DU HARNAIS, ET IL PRIME SUR TOUT LE RESTE, ENVIRONNEMENT COMPRIS.
  // `proof_run.sh --off` pose `AUTOPORT_FEATURE=fixed-tick-interpolation` +
  // `AUTOPORT_FEATURE_ARMED=0`, alors que le MEME `proof_env` pose `OG_FIXED_TICK=1` pour
  // les DEUX bras. Sans cette priorite, le bras desarme tournerait avec l'horloge armee :
  // l'ablation ne separerait rien et publierait deux lignes identiques.
  // `armed_for` ne rend faux que si le harnais nomme EXACTEMENT cet item — la course d'un
  // autre item, et le binaire de l'owner, ne passent jamais par ce chemin.
  if (!autoport_proof::armed_for("fixed-tick-interpolation")) {
    return false;
  }
  if (s.forced == -2) {
    s.forced = read_force_flag();
  }
  if (s.forced >= 0) {
    return s.forced == 1;
  }
  return s.armed_setting;
}

void set_enabled(bool on) {
  State& s = state();
  if (s.forced == -2) {
    s.forced = read_force_flag();
  }
  if (s.forced >= 0) {
    return;  // une course d'ablation est en cours : le menu ne la contredit pas
  }
  if (on == s.armed_setting) {
    return;
  }
  s.armed_setting = on;
  // Rebase a chaque transition. Sans ca, la premiere image apres l'armement lirait une
  // montre arretee depuis la derniere image ARMEE (potentiellement des minutes) et
  // fabriquerait un rattrapage de 4 ticks pour rien.
  s.have_last = false;
  s.accumulator = 0.0;
  s.dt_ema = kFixedTickSeconds;
  s.alpha_micro = 1000000;
  // Meme etat initial que le demarrage : verrouille sur 1 tick.
  s.locked = true;
  s.lock_n = 1.0;
  s.good_run = kLockFrames;
  s.bad_run = 0;
}

bool probe_enabled() {
  static const bool s_probe = read_probe_flag();
  return s_probe;
}

bool anim_interp_enabled() {
  static const bool s_on = read_bool_flag("OG_ANIM_INTERP", "debug.opengoal.animinterp", true);
  return s_on;
}

bool anim_probe_enabled() {
  static const bool s_on = read_bool_flag("OG_ANIM_PROBE", "debug.opengoal.animprobe", false);
  return s_on;
}

// Grecharged-foliage-wind3 — ABLATION DE LA CADENCE DU VENT NATIF, SUR LE MEME BINAIRE.
// A 1 (defaut) le vent de ND avance d'un pas de 1/60 s par 1/60 s de temps de jeu, quelle que
// soit la cadence d'affichage ; a 0 il reprend le chemin « high fps » d'avant cette phase (UN
// pas par image dessinee, index d'anneau et amplitude multiplies par `time-adjust-ratio`), qui
// laisse 48 des 64 slots de l'anneau jamais ecrits a 15 images/s. Le drapeau ne pilote que
// `goal_src/jak1/engine/gfx/background/wind.gc` : le ressort du renderer derive son nombre de
// pas du COMPTEUR `wind-time` lui-meme, donc les deux jambes ne peuvent pas se contredire.
// Vit ici et pas dans Tie3.cpp parce que c'est un reglage de CADENCE DE SIMULATION, du meme
// genre que le pas fixe, et parce que `fixed_tick_publish` est deja le point qui ecrit les
// valeurs de symbole une fois par image dessinee.
bool wind_native_rate_enabled() {
  static const bool s_on =
      read_bool_flag("OG_WIND_NATIVE_RATE", "debug.opengoal.wind.native_rate", true);
  return s_on;
}

// Gfixed-tick-anim-interp-2 — ABLATION DU CORRECTIF DE CETTE PHASE, SUR LE MEME BINAIRE.
// A 0, l'horloge reprend l'ACCROCHAGE PAR IMAGE livre a l'owner : toute image a moins de
// kSnapLegacyTolerance d'un nombre entier de ticks y est ramenee ET l'accumulateur est
// remis a zero. C'est ce que le build qu'il a teste faisait, et c'est ce qui fabriquait
// la gigue qu'il decrit. Sans cet interrupteur, l'avant/apres se ferait entre deux
// binaires — donc entre deux compilations, deux jeux de donnees et deux courses.
bool tick_lock_enabled() {
  static const bool s_on = read_bool_flag("OG_TICK_LOCK", "debug.opengoal.ticklock", true);
  return s_on;
}

// essai 2 — ABLATION DU CORRECTIF DE CET ESSAI, SUR LE MEME BINAIRE. A 0, le verrou
// reprend le comportement de l'essai 1 : la duree d'une image est remplacee par
// `lock_n / 60` DES QUE l'etat est verrouille, y compris sur les kUnlockBadFrames - 1
// images HORS grille qui precedent une sortie de verrou, et le reste accumule est
// detruit. C'est la substitution qui fabriquait le skip. Defaut ARME (1) : le correctif
// est livre, l'interrupteur n'existe que pour mesurer l'avant/apres sur la MEME course,
// le MEME binaire et la MEME suite de durees d'image.
bool tick_lock_strict() {
  static const bool s_on =
      read_bool_flag("OG_TICK_LOCK_STRICT", "debug.opengoal.ticklockstrict", true);
  return s_on;
}

bool armed_last_frame() {
  return state().clock_governs;
}

bool fast_display() {
  return state().disarmed_fast_display;
}

void set_deterministic(bool on) {
  state().deterministic = on;
}

s32 render_alpha_micro() {
  return state().alpha_micro;
}

u64 total_ticks() {
  return state().ticks;
}

u64 total_render_frames() {
  return state().render_frames;
}

u64 total_armed_frames() {
  return state().armed_frames;
}

int lock_state() {
  return state().locked ? 1 : 0;
}

double last_dev_ticks() {
  return state().last_dev;
}

u64 lock_events() {
  return state().lock_events;
}

u64 unlock_events() {
  return state().unlock_events;
}

u64 ceiling_clamps() {
  return state().ceiling_clamps;
}

u64 catchup_clamps() {
  return state().catchup_clamps;
}

void set_publisher(PublishFn fn) {
  state().publisher = fn;
}

// Une image vient d'etre produite : on fait avancer l'accumulateur puis on publie le
// resultat vers GOAL. Publier MEME quand l'horloge n'est pas armee est deliberé — sinon
// `*fixed-tick-armed*` garderait la valeur de la derniere image armee et le moteur
// resterait sur le chemin a pas fixe apres un desarmement.
void on_render_frame() {
  State& s = state();
  const int k = begin_render_frame();
  if (s.clock_governs) {
    s.armed_frames++;
    // PREUVE DE CABLAGE. `hits` ne monte que lorsque l'horloge a REELLEMENT gouverne une
    // image ; desarmee elle n'appelle pas, et le bras d'ablation publie `hits=0`. Un
    // compteur qui monte des deux cotes ne separe rien.
    autoport_proof::note_hit();
    census_frame();
  } else if (s.census_have) {
    // Desarmement en pleine course (le joueur decoche la case) : on rebase la montre du
    // recensement, sinon la premiere image REARMEE porterait tout le temps ecoule pendant
    // le desarmement et fabriquerait une fenetre fausse.
    s.census_have = false;
    s.win_sec = 0.0;
    s.win_ticks = 0;
  }
  census_publish();
  if (s.publisher) {
    // `armed` suit desormais l'horloge, pas le nombre de ticks : une image de RENDU
    // SEUL est ARMEE et porte `skip=1`. Publier `armed=0` pour elle rendrait la main
    // au calcul d'origine, qui deduit le pas de la duree de la frame — c'est-a-dire
    // exactement le pas variable que ce module existe pour supprimer.
    s.publisher(s.clock_governs ? 1 : 0, k >= 1 ? (k - 1) : 0, s.alpha_micro,
                (s.clock_governs && k == 0) ? 1 : 0);
  }
}

int begin_render_frame() {
  if (!enabled()) {
    state().clock_governs = false;
    return 0;
  }
  State& s = state();
  s.clock_governs = true;
  s.render_frames++;

  // Mode deterministe (harnais de rejeu) : exactement un tick par image, sans lire la
  // montre. Le pas vaut 1/60 s a TOUS les framerates cibles, ce qui isole la taille du
  // pas comme seule variable de la mesure.
  if (s.deterministic) {
    s.accumulator = 0.0;
    s.alpha_micro = 1000000;
    s.have_last = false;  // la premiere frame apres le mode reel rebase la montre
    s.ticks++;
    return 1;
  }

  double dt;
  if (!s.have_last) {
    // Premiere image : aucune duree a mesurer. On pose exactement un tick plutot que
    // d'inventer une valeur — c'est le defaut sur lequel le moteur demarre deja.
    dt = kFixedTickSeconds;
    s.have_last = true;
  } else {
    dt = s.timer.getSeconds();
  }
  s.timer.start();

  // Gfixed-tick-anim-interp — CE BLOC DESARMAIT, IL NE FAIT PLUS QUE CONSTATER.
  // Jusqu'ici, des que la moyenne glissante de la duree d'image passait sous 0,95 tick
  // (~63 img/s), l'horloge rendait la main au calcul d'origine. Deux consequences
  // mesurees : la simulation reprenait la cadence de l'AFFICHAGE sur tout panneau
  // 90/120 Hz, et l'ablation de cette phase publiait `armed=0` DES DEUX COTES au-dessus
  // de 60 img/s — donc deux lignes identiques et une comparaison vide.
  // L'horloge reste desormais armee et rend k = 0 pour les images qui ne meritent pas
  // de tick ; `time-ratio` vaut alors 0 cote GOAL et la logique n'avance pas.
  s.dt_ema = 0.85 * s.dt_ema + 0.15 * dt;
  s.disarmed_fast_display = (s.dt_ema < kFixedTickSeconds * kDisarmFasterThan);

  // Un hoquet (chargement, changement de niveau) ne doit pas fabriquer un
  // fast-forward : on borne l'apport a ce que le rattrapage peut absorber. Le temps
  // au-dela est JETE — c'est compte, parce qu'un temps jete est une saccade.
  const double dt_ceiling = kMaxCatchupTicks * kFixedTickSeconds;
  bool ceiling_hit = false;
  if (dt > dt_ceiling) {
    dt = dt_ceiling;
    ceiling_hit = true;
    s.ceiling_clamps++;
  }

  // ------------------------------------------------------------------------------
  // VERROU DE CADENCE HYSTERETIQUE (Gfixed-tick-anim-interp-2). Voir fixed_tick.h
  // pour la mesure qui refute l'accrochage par image qu'il remplace.
  // ------------------------------------------------------------------------------
  const double ticks_f = dt / kFixedTickSeconds;
  const double nearest = std::floor(ticks_f + 0.5);
  s.last_dev = std::fabs(ticks_f - nearest);
  // Une image ECRETEE n'est pas une mesure de cadence : son `ticks_f` vaut exactement
  // kMaxCatchupTicks par construction, donc elle tomberait pile sur la grille et
  // ferait croire a un verrou. Elle est declaree hors grille.
  // Et on refuse de verrouiller au-dela du plafond de rattrapage : le verrou
  // declarerait N ticks que la boucle ne saurait pas executer, donc du temps jete a
  // chaque image.
  const bool on_grid = !ceiling_hit && nearest >= 1.0 &&
                       nearest <= (double)kMaxCatchupTicks && s.last_dev <= kLockTolerance;

  if (!tick_lock_enabled()) {
    // BRAS D'ABLATION : l'accrochage PAR IMAGE tel qu'il a ete livre. Conserve pour que
    // l'avant/apres se mesure sur LE MEME binaire, la MEME course et la MEME suite de
    // durees d'image. `locked` sert alors d'etiquette « cette image a ete accrochee ».
    s.locked = nearest >= 1.0 && s.last_dev <= kSnapLegacyTolerance;
    if (s.locked) {
      dt = nearest * kFixedTickSeconds;
      s.accumulator = 0.0;
    }
    s.accumulator += dt;
    int kl = 0;
    while (s.accumulator >= kFixedTickSeconds && kl < kMaxCatchupTicks) {
      s.accumulator -= kFixedTickSeconds;
      kl++;
    }
    if (s.accumulator >= kFixedTickSeconds) {
      s.accumulator = kFixedTickSeconds * 0.999;
      s.catchup_clamps++;
    }
    if (s.locked && kl >= 1 && s.accumulator < 1e-9) {
      s.alpha_micro = 1000000;
    } else {
      double al = s.accumulator / kFixedTickSeconds;
      if (al < 0.0) {
        al = 0.0;
      }
      if (al > 1.0) {
        al = 1.0;
      }
      s.alpha_micro = (s32)(al * 1000000.0 + 0.5);
    }
    if (kl < 1) {
      return 0;
    }
    s.ticks += (u64)kl;
    return kl;
  }

  // essai 2 — LA SUBSTITUTION EST CONDITIONNEE A LA CONFORMITE DE L'IMAGE, PLUS A L'ETAT.
  // Le defaut corrige ici : `if (s.locked) { dt = lock_n/60; accumulator = 0; }` s'appliquait
  // AUSSI aux kUnlockBadFrames - 1 images hors grille qui precedent une sortie de verrou.
  // Sur la course de l'essai 1 une de ces images durait 2,38x la duree qu'on lui DECLARAIT
  // (tick_lock_err_pct_x100=13763) : 23 ms de temps de jeu detruites, et l'avance de la pose
  // dessinee vaut `k + alpha(n) - alpha(n-1)`, donc le reste detruit se retranche de
  // l'avance. C'est le mecanisme exact d'un « skip ».
  // `lock_hit` est vrai UNIQUEMENT quand l'image est sur la grille au pas verrouille : c'est
  // le seul cas ou remplacer sa duree par `lock_n / 60` ne reecrit rien de plus que la
  // tolerance qui a servi a l'accepter (kLockTolerance).
  bool lock_hit = false;
  bool declared_transition = ceiling_hit;
  const double dt_real = dt;
  const double acc_before = s.accumulator;
  if (s.locked) {
    if (on_grid && nearest == s.lock_n) {
      s.bad_run = 0;
      lock_hit = true;
    } else if (++s.bad_run >= kUnlockBadFrames) {
      // SORTIE DE VERROU. Une image isolee hors grille (une image sautee sur un
      // panneau 60 Hz) ne casse rien : il en faut kUnlockBadFrames de suite.
      s.lock_transients++;
      s.locked = false;
      s.unlock_events++;
      s.good_run = 0;
      s.lock_n = 0.0;
      // CONTINUITE D'ALPHA. Verrouille il valait 1,0 ; le regime libre le calcule en
      // acc/tick. On repart donc du HAUT de l'intervalle pour que la premiere image
      // libre publie 1,0 moins epsilon, et non 0 — sans quoi la pose reculerait d'un
      // tick entier sur l'image de transition.
      // C'est une FABRICATION assumee de temps de jeu (au plus un tick, une fois par
      // sortie de verrou) : elle achete la continuite de la pose, qui est ce que
      // l'owner voit. Elle est comptee (`tick_time_fabricated_us`), l'image est exclue
      // de l'invariant par image, et son cumul reste juge par le recensement de
      // fenetre — qui, lui, n'exclut rien.
      declared_transition = true;
      const double rebase = kFixedTickSeconds * (1.0 - 1e-6);
      if (rebase > s.accumulator) {
        s.fabricated_sec += rebase - s.accumulator;
      }
      s.accumulator = rebase;
    } else {
      s.lock_transients++;
    }
  } else {
    if (on_grid && nearest == s.lock_n) {
      s.good_run++;
    } else {
      s.lock_n = on_grid ? nearest : 0.0;
      s.good_run = on_grid ? 1 : 0;
    }
    if (s.good_run >= kLockFrames) {
      // (l'encliquetage ci-dessous est une transition declaree : le glissement de phase
      //  a FABRIQUE kPhaseSlew par image depuis la sortie de verrou, et la remise a zero
      //  de l'accumulateur DETRUIT exactement ce que le glissement a fabrique. Les deux
      //  se soldent, mais pas sur la meme image : l'image d'encliquetage est donc exclue
      //  de l'invariant par image, comme la sortie de verrou.)
      // ENTREE EN VERROU. La cadence est stable depuis kLockFrames images ; il reste a
      // aligner la PHASE. On ne la saute pas — un saut vaudrait jusqu'a un tick entier,
      // c'est-a-dire le defaut qu'on corrige. On la fait GLISSER de kPhaseSlew par
      // image (0,33 ms) jusqu'au haut de l'intervalle, ou alpha vaut deja 1,0 moins
      // epsilon : l'encliquetage ne coute alors que kPhaseSlew de tick.
      s.accumulator += kPhaseSlew * kFixedTickSeconds;
      if (s.accumulator >= kFixedTickSeconds * (1.0 - kPhaseSlew)) {
        s.locked = true;
        s.lock_events++;
        s.bad_run = 0;
        s.accumulator = 0.0;
        declared_transition = true;
      }
    }
  }

  const bool strict = tick_lock_strict();
  if (s.locked && (lock_hit || !strict)) {
    // La cadence EST un multiple entier du tick : on le declare exactement.
    dt = s.lock_n * kFixedTickSeconds;
    if (!strict) {
      // BRAS DE COMPARAISON (OG_TICK_LOCK_STRICT=0) : le comportement de l'essai 1,
      // substitution sur l'ETAT et destruction du reste. Il est la pour que l'avant/apres
      // se mesure sur le MEME binaire et la MEME suite de durees d'image.
      s.accumulator = 0.0;
    }
    // ERREUR PROPRE DU VERROU, mesuree LA OU LA SUBSTITUTION A LIEU et sur la duree que
    // l'horloge a elle-meme mesuree : de combien la duree DECLAREE s'ecarte de la duree
    // REELLE de l'image. Arme, elle est bornee par kLockTolerance / lock_n par construction
    // — une image n'est substituee que si elle est sur la grille.
    {
      const double e = std::fabs(dt_real - dt) / dt;
      if (e > s.lock_err_max) {
        s.lock_err_max = e;
      }
    }
    // ARME (defaut) : l'accumulateur N'EST PLUS remis a zero. A cadence verrouillee propre
    // il vaut deja zero — la reference « identique au bit a 60 img/s » ne bouge pas — et
    // le reste qu'une image hors grille a laisse est du temps REEL deja ecoule : le
    // detruire, c'est fabriquer le skip que ce chantier corrige.
  }

  s.accumulator += dt;

  int k = 0;
  while (s.accumulator >= kFixedTickSeconds && k < kMaxCatchupTicks) {
    s.accumulator -= kFixedTickSeconds;
    k++;
  }
  if (s.accumulator >= kFixedTickSeconds) {
    // Le plafond de rattrapage a mordu : on jette le retard au lieu de le porter,
    // sinon la frame suivante hériterait d'un backlog qui ne se resorbe jamais.
    s.accumulator = kFixedTickSeconds * 0.999;
    s.catchup_clamps++;
    declared_transition = true;
  }

  // INVARIANT DE CONSERVATION, JUGE ICI ET PAS DANS LE RECENSEMENT DE FENETRE : le temps
  // reel admis de CETTE image doit se retrouver entier, en ticks ou dans l'accumulateur.
  // La tolerance du verrou est retranchee parce qu'une image CONFORME est declaree a son
  // pas nominal a kLockTolerance pres — c'est ce que « verrouille » veut dire, et c'est
  // borne. Les transitions declarees (ecretage, encliquetage, sortie de verrou) sont
  // exclues : elles sont comptees chacune par son propre compteur publie, et leur cumul
  // reste juge par `tick_rate_dev_pct_x100`, qui n'exclut aucune fenetre.
  if (!declared_transition) {
    s.conserve_frames++;
    const double conserved = (double)k * kFixedTickSeconds + (s.accumulator - acc_before);
    const double err = std::fabs(dt_real - conserved) / kFixedTickSeconds - kLockTolerance;
    if (err > s.conserve_err_max) {
      s.conserve_err_max = err;
    }
  }

  // ALPHA. Verrouille => 1,0, aucune interpolation, aucune latence ajoutee : c'est la
  // reference 60 images/s, et elle est obtenue par l'ETAT de l'horloge, pas par une
  // coincidence numerique sur le reste accumule.
  // Libre => acc/tick, ce qui fait avancer la pose dessinee exactement du temps reel
  // ecoule. Vrai AUSSI pour une image de rendu seul (k = 0, affichage plus rapide que
  // le tick) : c'est le meme calcul, il n'y a plus deux chemins.
  if (s.locked) {
    s.alpha_micro = 1000000;
  } else {
    double a = s.accumulator / kFixedTickSeconds;
    if (a < 0.0) {
      a = 0.0;
    }
    if (a > 1.0) {
      a = 1.0;
    }
    s.alpha_micro = (s32)(a * 1000000.0 + 0.5);
  }
  if (k < 1) {
    // IMAGE DE RENDU SEUL : le temps reel n'a pas encore paye un tick entier. Le reste
    // accumule est conserve, donc rien n'est perdu ni invente.
    return 0;
  }

  s.ticks += (u64)k;
  return k;
}

}  // namespace fixed_tick
