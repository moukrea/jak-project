// render_pace — voir render_pace.h pour le raisonnement complet.

#include "render_pace.h"

#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "fmt/core.h"

#include "common/util/Timer.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/gfx.h"
#include "game/system/autoport_proof.h"

namespace render_pace {

namespace {

// Plafond de rattrapage. MEME valeur que celle que GOAL s'impose deja
// (`set-time-ratios`, goal_src/jak1/engine/gfx/hw/display.gc:39, `fmin 4.0`) : au-dela,
// le temps est JETE, et c'est compte.
constexpr double kMaxTicks = 4.0;

// « Sur la grille ». Un instant a moins de 2 % d'un nombre entier de ticks est declare
// entier. Mesure de la phase precedente : ecart median a la grille 0,0017 tick a 60 img/s
// verrouillees, contre 0,1910 a 20 img/s avec gigue — un fosse de facteur cent. Le seuil
// est pose au centre du fosse, cote grille.
constexpr double kGridTol = 0.02;

// Tolerance du `ceil`. Sans elle, un `inc` de 1,0000001 ferait k = 2 : une image sur deux
// porterait un tick de trop a 60 img/s verrouillees, exactement le contraire du but. Elle
// laisse `deficit` depasser k de 0,03 tick au plus ; alpha est alors borne a 1,0 et la pose
// accuse 0,03 tick (0,5 ms) de retard, qui reste VISIBLE dans l'erreur publiee.
constexpr double kCeilTol = 0.03;

// Nombre d'images dessinees a laisser passer avant de DEMARRER le balayage de cadence.
// L'amorcage et le chargement du niveau prennent les premieres centaines d'images ; un
// segment qui tombe dedans est exerce mais VIDE de pose animee, et une mesure vide se lit
// comme un zero, c'est-a-dire comme un vert.
constexpr u64 kSweepStartFrames = 300;

// Plus petit nombre de pas juges pour qu'un SEGMENT de cadence compte. En dessous, la
// cadence a ete demandee mais pas mesuree : on ne publie pas un ecart type sur trois
// echantillons, on publie `kNoMeasurement` et la porte tombe. 120 pas = 4 s a 30 img/s.
constexpr u64 kMinSegSteps = 120;

// Bornes du balayage.
constexpr int kMaxSegments = 12;

// L'unite de `__read-ee-timer` : des ticks a 300 MHz (kmachine.cpp `read_ee_timer`).
// `get-bus-clock/256` les divise par 512 (engine/ps2/timer-h.gc:31), et `*ticks-per-frame*`
// est exprime dans CETTE unite : 585900 / cadence-cible (engine/gfx/hw/video.gc:38), soit
// 9765 a 60 img/s.
constexpr double kEeTicksPerBusUnit = 512.0;
constexpr double kBusUnitsPerSecond = 585937.5;  // 300e6 / 512

struct State {
  Timer wall;   // duree de l'image qui vient de finir
  Timer boot;   // horloge murale monotone, base de l'horloge EE brute
  bool have_wall = false;

  double deficit = 0.0;   // ticks dus, non encore executes ; vit dans (-1, kCeilTol]
  double k_last = 1.0;    // k de la DERNIERE image qui a porte un tick : l'unite de l'alpha
  bool skip = false;      // cette image dessinee ne porte aucun tick de logique
  u64 virtual_ee = 0;    // horloge rendue a GOAL quand le module est arme
  s32 alpha = 1000000;

  // L'image dont on ne connait pas encore l'alpha CONSOMME : soldee a l'appel suivant.
  bool pending = false;
  double pending_k = 1.0;
  double pending_k_last = 1.0;
  double pending_inc_raw = 1.0;  // temps reel ADMIS, avant accrochage sur la grille
  s32 pending_alpha = 1000000;
  bool pending_on_grid = false;

  double last_deficit_pre = 1.0;
  u64 prev_anim_interp_n = 0;

  double sum_pose = 0.0;  // avance cumulee de la pose DESSINEE, en ticks
  double sum_real = 0.0;  // temps reel admis cumule, en ticks
  bool have_prev = false;
  bool prev_judged = false;
  double prev_pose = 0.0;
  double prev_pose_push = 0.0;
  double prev_real = 0.0;

  double err_max = 0.0;         // ticks, sur les pas JUGES (alpha reellement consomme)
  double err_max_pushed = 0.0;  // ticks, en supposant l'alpha pousse consomme
  u64 frames = 0;
  u64 steps_judged = 0;
  u64 frames_retimed = 0;
  u64 ceiling_clamps = 0;
  u64 catchup_clamps = 0;
  u64 grid_snaps = 0;
  u64 skip_frames = 0;
  u64 k_max = 1;

  // ------------------------------------------------------- mesure PAR CADENCE ----------
  // La porte de l'essai 5 ne demande plus un maximum sur toute la course : elle demande
  // l'ECART TYPE du pas, cadence par cadence. Un maximum global est domine par le pire
  // segment et ne dit pas LEQUEL ; une moyenne reste verte sur l'alternance 1-2-1-1-2 ticks
  // qui est exactement le defaut. Chaque segment du balayage a donc son propre seau.
  int pending_bucket = -1;
  int prev_bucket = -1;
  u64 straddle_dropped = 0;

  // ----------------------------------------------- LA SONDE DE POSE DESSINEE ----------
  // L'essai 5 mesurait un MODELE. Ces champs-ci suivent ce que GOAL a REELLEMENT dessine.
  bool have_prev_probe = false;
  u64 prev_probe_n = 0;
  u32 prev_probe_id = 0;
  s32 prev_probe_rate_q = 0;
  double prev_probe_ticks = 0.0;
  u64 probe_samples = 0;    // images ou GOAL a depose un echantillon
  u64 probe_rejected = 0;   // echantillons ecartes (identite changee, bouclage, taux nul)
  // POURQUOI un pas est ecarte. Un total d'ecarts ne dit pas quoi reparer : 15049 rejets sur
  // 15055 echantillons se lisaient « la sonde ne marche pas » sans dire lequel des trois
  // predicats mordait. Chacun est donc compte separement.
  u64 rej_id = 0;    // l'ANIMATION (frame-group) a change entre les deux images
  u64 rej_rate = 0;  // le TAUX a change : le pas n'a plus de reference
  u64 rej_step = 0;  // pas negatif ou hors bande : bouclage d'animation
  GoalReadout last_readout{};
};

// Un seau de mesure = un segment de cadence du balayage.
struct Bucket {
  double fps_nominal = 0.0;  // cadence DEMANDEE au limiteur (0 = aucun balayage)
  u64 frames = 0;            // images dessinees tombees dans ce segment
  u64 steps = 0;             // pas JUGES (les deux images retimees, ou alpha == 1,0)
  double sum_e = 0.0;        // somme de e(n) = avance de pose - temps reel, en ticks
  double sum_e2 = 0.0;
  double sum_raw = 0.0;      // somme du pas de pose BRUT, en ticks
  double sum_raw2 = 0.0;
  double sum_real = 0.0;     // temps reel admis du segment, en ticks
  u64 ee_n = 0;              // dispersion de l'intervalle de la boucle EE
  double ee_sum = 0.0;
  double ee_sum2 = 0.0;
  u64 non_identity = 0;      // images ou alpha != 1,0 : l'interpolation a MODIFIE la sortie
  u64 on_grid = 0;           // images DECLAREES sur la grille (a kGridTol pres)
  u64 present_n = 0;         // dispersion de l'intervalle de SWAP (fil GL, Android)
  double present_sum = 0.0;
  double present_sum2 = 0.0;
  u64 dsteps = 0;      // pas de pose DESSINEE juges (sonde GOAL)
  double dsum = 0.0;   // somme de d(n) = pas de pose dessine - temps reel, en ticks
  double dsum2 = 0.0;
};

std::mutex& present_mutex() {
  static std::mutex m;
  return m;
}

std::array<Bucket, kMaxSegments + 1>& buckets() {
  static std::array<Bucket, kMaxSegments + 1> b;
  return b;
}

// Ecart type d'un echantillon (sum, sum2, n), en ticks. Rend 0 quand n < 2.
double stddev(double sum, double sum2, u64 n) {
  if (n < 2) {
    return 0.0;
  }
  const double mean = sum / (double)n;
  const double var = sum2 / (double)n - mean * mean;
  return var > 0.0 ? std::sqrt(var) : 0.0;
}

State& state() {
  static State s;
  return s;
}

bool probe_enabled() {
  static const bool s_on = std::getenv("OG_RENDER_PACE_PROBE") != nullptr;
  return s_on;
}

double target_fps() {
  double tfps = Gfx::g_global_settings.target_fps;
  if (!(tfps >= 1.0) || tfps > 1000.0) {
    tfps = 60.0;
  }
  return tfps;
}

u64 raw_ee_now() {
  return (u64)((state().boot.getNs() * 3) / 10);
}

// En dessous de ce nombre de pas juges, il n'y a rien a juger : une course ou aucun acteur
// n'anime a l'ecran ne dirait ni « corrige » ni « casse », et un maximum sur zero echantillon
// vaut zero — c'est-a-dire un VERT. On publie donc une valeur hors bande, qui fait echouer la
// porte au lieu de la passer par absence de mesure.
constexpr u64 kMinJudgedSteps = 300;
constexpr u64 kNoMeasurement = 999999;

// =========================================================================================
// LE BALAYAGE DE CADENCE. Voir render_pace.h pour le pourquoi.
// =========================================================================================
// Il vit ICI et non dans `game/graphics/pipelines/opengl.cpp` (ou il est ne) parce que ce
// fichier-la n'est PAS compile dans `libgk.so` : `android/CMakeLists.txt` ne le liste pas.
// L'item est passe en `device: true` ; tant que le stimulus restait cote bureau, la course
// appareil ne pouvait exercer AUCUNE des cadences que la porte nomme, et une cadence non
// exercee se mesure a zero, c'est-a-dire au vert.
struct Sweep {
  std::vector<double> fps;
  double seg = 15.0;
  bool configured = false;
};

// Consigne : environnement d'abord (bureau), propriete ensuite (Android — l'application ne
// recoit pas l'environnement du shell qui l'a lancee). Meme patron que
// `autoport_proof::read_knob`.
bool read_knob_str(const char* env, const char* prop, char* out, size_t out_sz) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, out_sz, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

const Sweep& sweep() {
  static const Sweep s_sweep = []() -> Sweep {
    Sweep sw;
    char raw[128] = {0};
    if (!read_knob_str("OG_FRAME_LIMIT_FPS", "debug.opengoal.frame.limit", raw, sizeof(raw))) {
      return sw;
    }
    std::string v(raw);
    const auto at = v.find('@');
    if (at != std::string::npos) {
      const double sec = std::atof(v.substr(at + 1).c_str());
      if (sec > 0.0) {
        sw.seg = sec;
      }
      v = v.substr(0, at);
    }
    size_t pos = 0;
    while (pos <= v.size()) {
      const auto comma = v.find(',', pos);
      const std::string tok =
          v.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
      const double f = std::atof(tok.c_str());
      if (f > 0.0 && (int)sw.fps.size() < kMaxSegments) {
        sw.fps.push_back(f);
      }
      if (comma == std::string::npos) {
        break;
      }
      pos = comma + 1;
    }
    sw.configured = !sw.fps.empty();
    return sw;
  }();
  return s_sweep;
}

// Images dessinees, en atomique : le limiteur tourne sur le fil principal (bureau) et sur le
// fil EE (Android), la mesure toujours sur le fil EE. Un `u64` de `State` lu de deux fils
// serait une course ; ce compteur-la est le seul etat partage entre les deux.
std::atomic<u64> g_frames_atomic{0};

// Horloge du balayage. Elle ne demarre qu'a la kSweepStartFrames-ieme image : avant, le jeu
// charge son niveau et aucun acteur n'anime.
std::atomic<int> g_segment{-1};

double sweep_elapsed() {
  static Timer s_timer;
  static bool s_started = false;
  if (!s_started) {
    if (g_frames_atomic.load(std::memory_order_relaxed) < kSweepStartFrames) {
      return -1.0;
    }
    s_started = true;
    s_timer.start();
  }
  return s_timer.getSeconds();
}

// Seau de MESURE de l'image en cours :
//   0..n-1  segment du balayage,
//   0       seau unique quand aucun balayage n'est demande (le binaire de l'owner),
//   -1      balayage demande mais pas encore demarre : ces images-la sont JETEES, elles
//           appartiennent a l'amorcage et pollueraient le premier segment.
int metric_bucket() {
  const Sweep& sw = sweep();
  if (!sw.configured) {
    return 0;
  }
  return g_segment.load(std::memory_order_relaxed);
}

double bucket_nominal_fps(int b) {
  const Sweep& sw = sweep();
  if (!sw.configured || b < 0 || b >= (int)sw.fps.size()) {
    return 0.0;
  }
  return sw.fps[b];
}

void publish() {
  State& s = state();
  const double us_per_tick = 1.0e6 / target_fps();
  autoport_proof::publish("anim_render_step_err_max_us",
                          s.steps_judged >= kMinJudgedSteps
                              ? (u64)(s.err_max * us_per_tick + 0.5)
                              : kNoMeasurement);
  autoport_proof::publish("anim_render_step_err_pushed_us",
                          (u64)(s.err_max_pushed * us_per_tick + 0.5));
  autoport_proof::publish("anim_render_steps_judged", s.steps_judged);
  autoport_proof::publish("anim_render_frames_retimed", s.frames_retimed);
  autoport_proof::publish("anim_render_frames", s.frames);
  autoport_proof::publish("anim_render_armed", armed() ? 1 : 0);
  autoport_proof::publish("anim_pace_grid_snaps", s.grid_snaps);
  autoport_proof::publish("anim_pace_skip_frames", s.skip_frames);
  autoport_proof::publish("anim_pace_ceiling_clamps", s.ceiling_clamps);
  autoport_proof::publish("anim_pace_catchup_clamps", s.catchup_clamps);
  autoport_proof::publish("anim_pace_k_max", s.k_max);

  // ----------------------------------------------------- LA GRANDEUR DE LA PORTE --------
  // `anim_step_jitter_worst_us` = le PIRE, sur toutes les cadences du balayage, de l'ECART
  // TYPE de e(n) = (avance de la pose DESSINEE) - (temps reel ecoule), image apres image.
  //
  // POURQUOI e ET PAS LE PAS BRUT. Le pas brut de pose contient la gigue de l'AFFICHAGE :
  // sur un telephone la duree reelle d'une image varie, et une pose qui suit exactement ce
  // temps reel est LISSE — c'est meme la definition de lisse. Un ecart type sur le pas brut
  // rendrait donc rouge une image parfaitement corrigee, et ce rouge-la ne decrirait aucun
  // defaut. e(n) est nul si et seulement si la pose avance PROPORTIONNELLEMENT au temps
  // reel ; il vaut un demi-tick d'amplitude sur l'alternance 1-2-1-1-2 ticks que l'owner
  // decrit a 45 img/s. Le pas brut est publie a cote (`anim_step_rawjit_worst_us`) : le
  // superviseur peut trancher sur les deux chiffres au lieu de me croire.
  //
  // UNE CADENCE DEMANDEE MAIS NON MESUREE VAUT `kNoMeasurement`, PAS ZERO. Un ecart type sur
  // zero echantillon vaut zero, c'est-a-dire un vert : c'est exactement comme cela qu'une
  // porte valide une condition absente.
  {
    const Sweep& sw = sweep();
    const int nb = sw.configured ? (int)sw.fps.size() : 1;
    double worst = 0.0, worst_raw = 0.0, worst_ee = 0.0, worst_present = 0.0;
    double worst_model = 0.0;
    double worst_fps = 0.0;
    bool missing = false;
    for (int b = 0; b < nb; b++) {
      const Bucket& q = buckets()[b];
      const double fps_nom = sw.configured ? sw.fps[b] : 0.0;
      const int key_fps = (int)(fps_nom > 0.0 ? fps_nom + 0.5 : target_fps() + 0.5);
      const bool enough = q.steps >= kMinSegSteps;
      const double sd_model = enough ? stddev(q.sum_e, q.sum_e2, q.steps) : 0.0;
      const double sd_raw = enough ? stddev(q.sum_raw, q.sum_raw2, q.steps) : 0.0;
      if (!enough) {
        missing = true;
      } else {
        // LE MODELE NE GOUVERNE PLUS LA PORTE. Il garde son propre pire cas, publie a cote.
        if (sd_model > worst_model) {
          worst_model = sd_model;
        }
        if (sd_raw > worst_raw) {
          worst_raw = sd_raw;
        }
      }

      // ------------------------------------------------- LA GRANDEUR DE LA PORTE --------
      // Ecart type de d(n) = (pas de la pose REELLEMENT DESSINEE, lue dans
      // `*anim-probe-frame*`) - (temps reel de l'image). Aucun modele C++ n'intervient.
      const bool denough = q.dsteps >= kMinSegSteps;
      const double sd_drawn = denough ? stddev(q.dsum, q.dsum2, q.dsteps) : 0.0;
      if (!denough) {
        missing = true;   // une cadence sans pose MESUREE n'est pas une cadence propre
      } else if (sd_drawn > worst) {
        worst = sd_drawn;
        worst_fps = fps_nom;
      }
      const double sd_ee = stddev(q.ee_sum, q.ee_sum2, q.ee_n);
      if (sd_ee > worst_ee) {
        worst_ee = sd_ee;
      }
      double sd_present = 0.0;
      {
        std::lock_guard<std::mutex> lock(present_mutex());
        sd_present = stddev(q.present_sum, q.present_sum2, q.present_n);
      }
      if (sd_present > worst_present) {
        worst_present = sd_present;
      }
      autoport_proof::publish(fmt::format("anim_step_jitter_{}_us", key_fps).c_str(),
                              denough ? (u64)(sd_drawn * us_per_tick + 0.5) : kNoMeasurement);
      autoport_proof::publish(fmt::format("anim_probe_steps_{}", key_fps).c_str(), q.dsteps);
      autoport_proof::publish(fmt::format("anim_step_model_jitter_{}_us", key_fps).c_str(),
                              enough ? (u64)(sd_model * us_per_tick + 0.5) : kNoMeasurement);
      autoport_proof::publish(fmt::format("anim_step_steps_{}", key_fps).c_str(), q.steps);
      // Cadence REELLEMENT atteinte, x100. Une cadence demandee que l'appareil ne tient pas
      // est un PLAFOND, pas une mesure : sans cette ligne, un segment a 90 demande / 58 tenu
      // se lirait « 90 img/s mesurees ».
      autoport_proof::publish(
          fmt::format("anim_step_fps_{}_x100", key_fps).c_str(),
          q.sum_real > 0.0 ? (u64)((double)q.frames / (q.sum_real / target_fps()) * 100.0 + 0.5)
                           : 0);
    }
    autoport_proof::publish("anim_step_jitter_worst_us",
                            missing ? kNoMeasurement : (u64)(worst * us_per_tick + 0.5));
    autoport_proof::publish("anim_step_jitter_worst_fps", (u64)(worst_fps + 0.5));
    autoport_proof::publish("anim_step_model_jitter_worst_us",
                            (u64)(worst_model * us_per_tick + 0.5));
    autoport_proof::publish("anim_step_rawjit_worst_us",
                            missing ? kNoMeasurement : (u64)(worst_raw * us_per_tick + 0.5));
    autoport_proof::publish("anim_step_straddle_dropped", s.straddle_dropped);
    autoport_proof::publish("anim_step_sweep_segments", (u64)(sw.configured ? sw.fps.size() : 0));

    // RECOUPEMENT : la cadence que l'oeil voit est-elle celle que ce module mesure ?
    // `on_render_frame` chronometre la boucle EE ; l'ecran, lui, change a chaque
    // `SDL_GL_SwapWindow`. Une phase precedente a AFFIRME en commentaire que les deux sont
    // 1:1 (android_gfx.cpp) ; une affirmation n'est pas une trace. Si l'intervalle de swap
    // se disperse beaucoup plus que celui de la boucle EE, tout ce module corrige une
    // horloge que personne ne regarde — et le chiffre de la porte serait un faux vert.
    autoport_proof::publish("anim_step_ee_jitter_worst_us", (u64)(worst_ee * us_per_tick + 0.5));
    autoport_proof::publish("anim_step_present_jitter_worst_us",
                            (u64)(worst_present * us_per_tick + 0.5));

    // IDENTIQUE AU BIT A 30 ET A 60. Ces deux cadences sont celles ou les 60 ticks/s tombent
    // en compte entier par image : `deficit` reste nul, alpha vaut EXACTEMENT 1,0, et
    // `joint-channel-render-frame` comme `cam-render-interp!` sortent en identite — la sortie
    // ne bouge pas d'un bit. Le compteur lu est donc le nombre d'images ou alpha a DIFFERE de
    // 1,0 : zero image modifiee == identique au bit. `kNoMeasurement` quand la cadence n'a pas
    // ete exercee du tout : une non-regression non mesuree n'est pas une non-regression tenue.
    for (const int want : {30, 60}) {
      int found = -1;
      for (int b = 0; b < nb; b++) {
        if (sw.configured && (int)(sw.fps[b] + 0.5) == want) {
          found = b;
          break;
        }
      }
      const char* key = want == 30 ? "anim_step_bitexact_30" : "anim_step_bitexact_60";
      const char* nkey = want == 30 ? "anim_step_nonident_30" : "anim_step_nonident_60";
      const char* gkey = want == 30 ? "anim_step_ongrid_30" : "anim_step_ongrid_60";
      if (found < 0 || buckets()[found].frames == 0) {
        autoport_proof::publish(key, kNoMeasurement);
        autoport_proof::publish(nkey, kNoMeasurement);
        autoport_proof::publish(gkey, kNoMeasurement);
      } else {
        autoport_proof::publish(key, buckets()[found].non_identity == 0 ? 1 : 0);
        autoport_proof::publish(nkey, buckets()[found].non_identity);
        // POURQUOI CE TROISIEME CHIFFRE. « Identique au bit a 30 et a 60 » n'est tenable que
        // sur des images REELLEMENT sur la grille : l'identite sort de `deficit == 0`, qui
        // sort de `inc == entier`. Si la cadence nominale est tenue EN MOYENNE mais que
        // chaque image derive de plus de kGridTol, alpha vaut legitimement moins de 1 et la
        // pose recule — c'est la correction qui fonctionne, pas une regression. Sans ce
        // compteur, un `bitexact = 0` se lirait « le correctif abime le cas 60 img/s » alors
        // qu'il veut dire « cette course n'a pas tenu 60 img/s a 2 % pres ».
        autoport_proof::publish(gkey, buckets()[found].on_grid);
      }
    }

    // RECENSEMENT DES POSES NON RETIMEES, PAR CAUSE. Le modele de l'essai 5 ne pouvait pas les
    // voir : il ne decrivait que le canal `frame-num`. Ces chiffres disent OU la pose saute.
    const GoalReadout& g = state().last_readout;
    autoport_proof::publish("anim_cen_total", g.cen_total);
    autoport_proof::publish("anim_cen_ident", g.cen_ident);
    autoport_proof::publish("anim_cen_zero", g.cen_zero);
    autoport_proof::publish("anim_cen_blend", g.cen_blend);
    autoport_proof::publish("anim_cen_done", g.cen_done);
    autoport_proof::publish("anim_cen_static", g.cen_static);
    autoport_proof::publish("anim_cen_seekend", g.cen_seekend);
    autoport_proof::publish("anim_cen_other", g.cen_other);
    autoport_proof::publish("anim_djm_total", g.djm_total);
    autoport_proof::publish("anim_djm_shift", g.djm_shift);
    autoport_proof::publish("anim_djm_noroot", g.djm_noroot);
    autoport_proof::publish("anim_djm_rotv", g.djm_rotv);
    autoport_proof::publish("anim_probe_samples", state().probe_samples);
    autoport_proof::publish("anim_probe_rejected", state().probe_rejected);
    autoport_proof::publish("anim_probe_rej_id", state().rej_id);
    // LES VALEURS BRUTES DE LA DERNIERE IMAGE. 15169 rejets pour 10 causes nommees : le
    // predicat de base mordait, et un compteur de rejets ne dit pas LAQUELLE de ses cinq
    // clauses. On publie donc ce que GOAL a reellement depose, sans interpretation.
    autoport_proof::publish("anim_probe_raw_id", (u64)g.probe_id);
    autoport_proof::publish("anim_probe_raw_rate_q", (u64)(s64)g.probe_rate_q);
    autoport_proof::publish("anim_probe_raw_frame_q", (u64)(s64)g.probe_frame_q);
    autoport_proof::publish("anim_probe_raw_p0_q", (u64)(s64)g.probe_p0_q);
    autoport_proof::publish("anim_probe_branch", (u64)g.probe_br);
    // Le k de GOAL contre le k du C++, en ticks x1000. Un ecart qui CROIT dit que les deux
    // horloges ne comptent pas la meme chose ; un ecart nul innocente le compte et accuse le
    // retimeur lui-meme.
    autoport_proof::publish("anim_goal_ksum_x1000",
                            (u64)((double)g.goal_ksum_q * 1000.0 / 1024.0 + 0.5));
    autoport_proof::publish("anim_cpp_ksum_x1000", (u64)(state().sum_pose * 1000.0 + 0.5));
    autoport_proof::publish("anim_probe_rej_rate", state().rej_rate);
    autoport_proof::publish("anim_probe_rej_step", state().rej_step);
    autoport_proof::publish("anim_probe_n", g.probe_n);
  }
}

}  // namespace

bool armed() {
  // LATCHE UNE SEULE FOIS. `fixed_tick::enabled()` suit un reglage de menu que GOAL peut
  // basculer en pleine course : si l'armement changeait en cours de route, `ee_timer()`
  // passerait de l'horloge virtuelle a la montre murale d'une image a l'autre, GOAL verrait
  // un saut de plusieurs minutes et fabriquerait un rattrapage geant. L'etat est donc fige
  // au premier appel — avant la premiere image.
  static const bool s_armed = []() {
    if (fixed_tick::enabled()) {
      // L'horloge a pas fixe impose deja `time-ratio` et son propre alpha
      // (drawable.gc:1088-1098) : deux horloges sur la meme image ne mesurent rien.
      return false;
    }
    return autoport_proof::armed_for("anim-interp-low-fps");
  }();
  return s_armed;
}

s32 alpha_micro() {
  if (!armed()) {
    return 1000000;
  }
  return state().alpha;
}

bool skip() {
  return armed() && state().skip;
}

double last_k() {
  return state().pending_k;
}

double last_deficit() {
  return state().last_deficit_pre;
}

// -------------------------------------------------------------------------- stimulus ----
// APPELE PAR LE LIMITEUR, ET PAR LUI SEUL : le fil principal sur bureau
// (`GLDisplay::render`), le fil EE sur Android (`android_gfx::vsync`). Un seul fil de chaque
// cote, donc les statiques locales de `sweep_elapsed()` ne sont pas partagees ; le seul etat
// qui traverse est `g_segment`, atomique.
double stimulus_fps(double target) {
  const Sweep& sw = sweep();
  if (!sw.configured) {
    return target;  // le binaire de l'owner : la cible ressort telle quelle, cout nul.
  }
  const double t = sweep_elapsed();
  if (t < 0.0) {
    // Amorcage : on ne touche pas encore a la cadence, et les images de cette periode
    // n'appartiennent a aucun segment.
    g_segment.store(-1, std::memory_order_relaxed);
    return target;
  }
  const int n = (int)sw.fps.size();
  const int i = (int)(((u64)(t / sw.seg)) % (u64)n);
  g_segment.store(i, std::memory_order_relaxed);
  return sw.fps[i];
}

int stimulus_segment() {
  return metric_bucket();
}

double stimulus_segment_fps() {
  return bucket_nominal_fps(metric_bucket());
}

void note_present() {
  const int b = metric_bucket();
  if (b < 0 || b >= kMaxSegments) {
    return;
  }
  // Fil GL uniquement (android_renderer.cpp, juste apres `SDL_GL_SwapWindow`).
  static Timer s_swap;
  static bool s_have = false;
  const double dt = s_swap.getSeconds();
  s_swap.start();
  if (!s_have) {
    s_have = true;  // la premiere mesure n'a pas de bord gauche
    return;
  }
  const double ticks = dt * target_fps();
  if (!(ticks > 0.0) || ticks > kMaxTicks * 4.0) {
    return;  // hoquet de compositeur : hors bande, il ne decrit pas la cadence
  }
  std::lock_guard<std::mutex> lock(present_mutex());
  Bucket& q = buckets()[b];
  q.present_n++;
  q.present_sum += ticks;
  q.present_sum2 += ticks * ticks;
}

u64 ee_timer() {
  State& s = state();
  if (!armed()) {
    return raw_ee_now();
  }
  if (s.virtual_ee == 0) {
    // Avant la premiere image (amorcage, edition de liens) : on seme une fois et on tient la
    // valeur constante, donc `timer-count` rend 0 et GOAL prend time-ratio = 1 — le defaut sur
    // lequel le moteur demarre deja.
    s.virtual_ee = raw_ee_now();
  }
  return s.virtual_ee;
}

void on_render_frame(const GoalReadout& g) {
  State& s = state();

  // ------------------------------------------------------------- solde de l'image d'avant --
  // On sait MAINTENANT si son alpha a ete consomme : `*anim-interp-n*` compte les canaux
  // reellement retimes (process-drawable-h.gc:176) et l'arbre des process a tourne entre
  // l'appel precedent et celui-ci. Un alpha pousse mais jamais lu se solde a 1,0 : la mesure
  // decrit ce qui a ete DESSINE, pas ce qu'on a voulu pousser.
  const bool retimed = g.anim_interp_n > s.prev_anim_interp_n;
  s.prev_anim_interp_n = g.anim_interp_n;
  s.last_readout = g;

  if (s.pending) {
    if (retimed) {
      s.frames_retimed++;
    }
    const double a_eff = retimed ? ((double)s.pending_alpha / 1000000.0) : 1.0;
    const double a_push = (double)s.pending_alpha / 1000000.0;

    // P(n) = E(n) - (1 - alpha) * k(n). On suit P et D en cumule, l'ecart d'un pas est leur
    // difference premiere.
    // P(n) = E(n) - (1 - alpha) * k_last : `k_last` est l'unite dans laquelle les retimeurs
    // reculent (`joint-channel-tick-delta` lit `*render-pace-ratio*`, le pas du DERNIER tick),
    // et c'est aussi 0 tick d'avance quand l'image ne porte pas de tick.
    s.sum_pose += s.pending_k;
    s.sum_real += s.pending_inc_raw;
    const double pose = s.sum_pose - (1.0 - a_eff) * s.pending_k_last;
    const double pose_push = s.sum_pose - (1.0 - a_push) * s.pending_k_last;
    // Un pas n'est JUGE que si les deux images qui le bornent ont ete retimees, ou si l'alpha
    // valait exactement 1,0 (rien a retimer). Une image sans acteur anime a l'ecran ne prouve
    // rien, ni dans un sens ni dans l'autre : elle est comptee a part, pas noyee dedans.
    const bool judged = retimed || s.pending_alpha >= 1000000;
    if (s.have_prev) {
      // DEUX REFERENCES, DEUX SUITES. Compare l'alpha pousse a l'alpha pousse de l'image
      // d'AVANT, jamais a l'alpha effectif : melanger les deux reperes fabrique un ecart d'un
      // tick entier sur toute image qui change de regime, et ce chiffre-la ne decrit alors
      // aucun defaut. `err_max_pushed` repond a une seule question : de combien la mesure
      // changerait si l'alpha pousse etait lu PARTOUT.
      const double e_push = std::fabs((pose_push - s.prev_pose_push) - (s.sum_real - s.prev_real));
      if (e_push > s.err_max_pushed) {
        s.err_max_pushed = e_push;
      }
      if (judged && s.prev_judged) {
        const double e = std::fabs((pose - s.prev_pose) - (s.sum_real - s.prev_real));
        if (e > s.err_max) {
          s.err_max = e;
        }
        s.steps_judged++;
      }
    }
    // ---------------------------------------------------- le seau de CETTE cadence ------
    // L'image qu'on vient de solder appartient au segment ou elle a ete PRODUITE, pas a
    // celui ou on la solde : le balayage peut avoir bascule entre les deux appels.
    const int b = s.pending_bucket;
    if (b >= 0 && b < kMaxSegments) {
      Bucket& q = buckets()[b];
      q.frames++;
      q.sum_real += s.pending_inc_raw;
      q.ee_n++;
      q.ee_sum += s.pending_inc_raw;
      q.ee_sum2 += s.pending_inc_raw * s.pending_inc_raw;
      if (s.pending_alpha != 1000000) {
        q.non_identity++;
      }
      if (s.pending_on_grid) {
        q.on_grid++;
      }
      if (s.have_prev && judged && s.prev_judged) {
        if (s.prev_bucket == b) {
          const double raw = pose - s.prev_pose;
          const double e = raw - (s.sum_real - s.prev_real);
          q.steps++;
          q.sum_e += e;
          q.sum_e2 += e * e;
          q.sum_raw += raw;
          q.sum_raw2 += raw * raw;
        } else {
          // LE PAS QUI ENJAMBE UNE FRONTIERE DE SEGMENT EST JETE, ET C'EST COMPTE. Au
          // changement de cadence la duree d'image saute d'un facteur deux : ce transitoire
          // est un artefact du STIMULUS, pas un defaut du jeu, et il gonflerait l'ecart type
          // du segment qui commence. Un seul pas par frontiere, donc au plus n-1 par cycle.
          s.straddle_dropped++;
        }
      }
    }

    // ------------------------------------------- LA POSE REELLEMENT DESSINEE ------------
    // ALIGNEMENT. `s.pending_*` decrit l'image preparee a l'appel PRECEDENT ; l'arbre des
    // process a tourne entre cet appel-la et celui-ci, donc la valeur que GOAL vient de
    // deposer EST la pose de cette image. Son pas se compare donc a `pending_inc_raw`, le
    // temps reel qui gouvernait cette meme image. Un decalage d'une image injecterait ici la
    // gigue de l'affichage elle-meme (9846 us d'ecart type mesures sur l'appareil).
    {
      const double rate = (double)g.probe_rate_q / 65536.0;
      const double frame = (double)g.probe_frame_q / 65536.0;
      const bool fresh = g.probe_n > s.prev_probe_n;
      if (fresh) {
        s.probe_samples++;
      }
      const bool base_ok = fresh && g.probe_id != 0 && g.probe_rate_q > 0 && s.have_prev_probe;
      if (base_ok && g.probe_id != s.prev_probe_id) {
        s.rej_id++;
      } else if (base_ok && g.probe_rate_q != s.prev_probe_rate_q) {
        s.rej_rate++;
      }
      const bool usable = base_ok && g.probe_id == s.prev_probe_id &&
                          g.probe_rate_q == s.prev_probe_rate_q;
      const double ticks = (rate > 0.0) ? (frame / rate) : 0.0;
      if (usable) {
        const double step = ticks - s.prev_probe_ticks;
        // Un pas negatif ou enorme est un BOUCLAGE d'animation ou un changement de groupe :
        // il ne decrit pas la fluidite. Il est ecarte ET COMPTE, jamais absorbe dans la moyenne.
        if (step > 0.0 && step < kMaxTicks * 3.0) {
          const double d = step - s.pending_inc_raw;
          const int bb = s.pending_bucket;
          if (bb >= 0 && bb < kMaxSegments && s.prev_bucket == bb) {
            Bucket& qd = buckets()[bb];
            qd.dsteps++;
            qd.dsum += d;
            qd.dsum2 += d * d;
          }
        } else {
          s.probe_rejected++;
          s.rej_step++;
        }
      } else if (fresh && s.have_prev_probe) {
        s.probe_rejected++;
      }
      if (fresh) {
        s.prev_probe_n = g.probe_n;
        s.prev_probe_id = g.probe_id;
        s.prev_probe_rate_q = g.probe_rate_q;
        s.prev_probe_ticks = ticks;
        s.have_prev_probe = true;
      }
    }
    s.prev_bucket = b;
    s.prev_pose = pose;
    s.prev_pose_push = pose_push;
    s.prev_real = s.sum_real;
    s.prev_judged = judged;
    s.have_prev = true;
  }

  // ------------------------------------------------------------------- la nouvelle image --
  const double budget_sec = 1.0 / target_fps();
  double dt;
  if (!s.have_wall) {
    dt = budget_sec;  // premiere image : aucune duree a mesurer, on pose exactement un tick
    s.have_wall = true;
  } else {
    dt = s.wall.getSeconds();
  }
  s.wall.start();

  double inc = dt / budget_sec;
  if (!(inc >= 0.0)) {
    inc = 0.0;
  }
  if (inc > kMaxTicks) {
    inc = kMaxTicks;  // hoquet : le temps au-dela est JETE, et c'est compte
    s.ceiling_clamps++;
  }
  const double inc_raw = inc;  // ce que la montre a REELLEMENT admis : la reference de mesure

  bool on_grid = false;
  const double nearest = std::floor(inc + 0.5);
  if (nearest >= 1.0 && nearest <= kMaxTicks && std::fabs(inc - nearest) <= kGridTol) {
    inc = nearest;  // cadence sur la grille : DECLAREE entiere, le reste n'est pas detruit
    s.grid_snaps++;
    on_grid = true;
  }

  double k;
  if (armed()) {
    s.deficit += inc;
    s.last_deficit_pre = s.deficit;
    k = std::ceil(s.deficit - kCeilTol);
    // k PEUT VALOIR ZERO, et c'est le point qui manquait. Tant qu'on imposait au moins un tick
    // par image dessinee, une cadence d'affichage egale ou superieure a la cadence cible
    // poussait la simulation devant le temps reel : `deficit` se collait a -1, alpha se collait
    // a 0, et la pose etait dessinee un tick entier en arriere, image apres image. Mesure du
    // 2026-09-05 sur 2838 images a 60 img/s avec 35 % de gigue : 2444 images (86 %) a
    // `alpha == 0`, erreur moyenne 0,148 tick — l'interpolation ne servait a rien. Avec k = 0
    // le reste reste dans (-1, kCeilTol] et alpha balaie tout son intervalle.
    if (!(k >= 0.0)) {
      k = 0.0;
    }
    if (k > kMaxTicks) {
      k = kMaxTicks;
      s.catchup_clamps++;  // le plafond a mordu : du temps de jeu est JETE, et c'est compte
      s.deficit = kMaxTicks;
    }
    if (k >= 1.0) {
      s.deficit -= k;
      s.k_last = k;
      // L'horloge virtuelle avance du MILIEU de la bande de k, de sorte que la formule de GOAL
      // — `(/ timer-count *ticks-per-frame*) + 1`, division ENTIERE — retombe exactement sur k.
      // (k - 0,5) marche pour k = 1 aussi : floor(0,5) + 1 = 1.
      s.virtual_ee +=
          (u64)((k - 0.5) * (kBusUnitsPerSecond / target_fps()) * kEeTicksPerBusUnit + 0.5);
      s.skip = false;
    } else {
      // IMAGE DE RENDU SEUL. L'horloge virtuelle ne bouge pas ; GOAL calculerait quand meme
      // time-ratio = 1, c'est `*render-pace-skip*` qui la force a 0 (drawable.gc).
      s.skip = true;
      s.skip_frames++;
    }
    // alpha = 1 + reste / k_last. A reste nul (cadence sur la grille) il vaut EXACTEMENT 1,0,
    // les deux retimeurs sortent en identite et la sortie 60 img/s ne bouge pas d'un bit. Le
    // reste vivant dans (-1, kCeilTol] et k_last >= 1, alpha ne se colle jamais a 0.
    double a = 1.0 + s.deficit / s.k_last;
    if (!(a >= 0.0)) {
      a = 0.0;
    }
    if (a > 1.0) {
      a = 1.0;
    }
    s.alpha = (s32)(a * 1000000.0 + 0.5);
  } else {
    // BRAS D'ABLATION. GOAL lit l'horloge MURALE et choisit k tout seul ; pour que la mesure
    // decrive ce bras-la, on refait ici SA formule, celle de drawable.gc:1057-1069 :
    //     k = (timer-count / *ticks-per-frame*) + 1   [division entiere]
    //     puis k = 1 si le rapport flottant est sous 1,3 (garde PC), puis fmin 4,0.
    // C'est une REPRODUCTION, pas une lecture : elle ne sert qu'a proof-off.txt, que le
    // validateur ne juge pas sur cette grandeur.
    k = std::floor(inc_raw) + 1.0;
    if (inc_raw < 1.3) {
      k = 1.0;
    }
    if (k > kMaxTicks) {
      k = kMaxTicks;
    }
    s.alpha = 1000000;
    s.deficit = 0.0;
    s.k_last = k;
    s.skip = false;
    s.last_deficit_pre = inc_raw;
  }

  s.pending = true;
  s.pending_k = k;
  s.pending_k_last = s.k_last;
  s.pending_inc_raw = inc_raw;
  s.pending_alpha = armed() ? s.alpha : 1000000;
  s.pending_on_grid = on_grid;
  s.pending_bucket = metric_bucket();
  s.frames++;
  g_frames_atomic.store(s.frames, std::memory_order_relaxed);
  if ((u64)k > s.k_max) {
    s.k_max = (u64)k;
  }

  if (armed()) {
    autoport_proof::note_hit();
  }
  publish();

  // Sonde de cadence, une ligne par image dessinee (env `OG_RENDER_PACE_PROBE=1`, muette
  // sinon). Elle publie les grandeurs qui DECIDENT — pas un resume — parce que l'erreur
  // residuelle vient toujours d'un bornage, et un bornage ne se lit pas dans un maximum.
  if (probe_enabled()) {
    fmt::print(stderr, "RPACE n={} dt_ms={:.3f} inc={:.4f} def_pre={:.4f} k={} alpha={} def_post={:.4f}\n",
               s.frames, dt * 1000.0, inc_raw, s.last_deficit_pre, (int)k, s.alpha, s.deficit);
  }
}

}  // namespace render_pace
