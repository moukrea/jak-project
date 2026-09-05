// render_pace — voir render_pace.h pour le raisonnement complet.

#include "render_pace.h"

#include <cmath>
#include <cstdlib>

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

  double last_deficit_pre = 1.0;
  u64 prev_anim_interp_n = 0;

  double sum_pose = 0.0;  // avance cumulee de la pose DESSINEE, en ticks
  double sum_real = 0.0;  // temps reel admis cumule, en ticks
  bool have_prev = false;
  bool prev_judged = false;
  double prev_pose = 0.0;
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
};

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

void on_render_frame(u64 anim_interp_n) {
  State& s = state();

  // ------------------------------------------------------------- solde de l'image d'avant --
  // On sait MAINTENANT si son alpha a ete consomme : `*anim-interp-n*` compte les canaux
  // reellement retimes (process-drawable-h.gc:176) et l'arbre des process a tourne entre
  // l'appel precedent et celui-ci. Un alpha pousse mais jamais lu se solde a 1,0 : la mesure
  // decrit ce qui a ete DESSINE, pas ce qu'on a voulu pousser.
  const bool retimed = anim_interp_n > s.prev_anim_interp_n;
  s.prev_anim_interp_n = anim_interp_n;

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
      const double e_push = std::fabs((pose_push - s.prev_pose) - (s.sum_real - s.prev_real));
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
    s.prev_pose = pose;
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

  const double nearest = std::floor(inc + 0.5);
  if (nearest >= 1.0 && nearest <= kMaxTicks && std::fabs(inc - nearest) <= kGridTol) {
    inc = nearest;  // cadence sur la grille : DECLAREE entiere, le reste n'est pas detruit
    s.grid_snaps++;
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
  s.frames++;
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
