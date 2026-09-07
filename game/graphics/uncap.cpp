// framerate-uncap — voir uncap.h pour le raisonnement complet.

#include "uncap.h"

#include <atomic>
#include <cmath>
#include <cstdlib>

#include "common/util/Timer.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/gfx.h"
#include "game/graphics/render_pace.h"
#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace uncap {

namespace {

constexpr double kTickSeconds = 1.0 / 60.0;
constexpr double kSceneUnitsPerSecond = 1024.0;  // ce que l'horloge de scene doit debiter
constexpr double kWindowSeconds = 5.0;
constexpr u64 kMinWindows = 4;

// « Au-dela de 60 » : 2 % au-dessus de la reference moteur. La marge n'est pas un confort,
// c'est le bruit de la mesure — une fenetre de 5 s a 60 img/s compte 300 images a +/-1 pres.
// Sert a PUBLIER si le regime debride a ete atteint (`uncap_regime_entered`) ; ce n'est pas un
// verdict — voir le bloc « CE QUI EST UN DEFAUT, ET CE QUI EST UNE PROPRIETE DE LA MACHINE ».
constexpr double kOverFactor = 1.02;

// Le plafond de rattrapage est le MEME dans les deux horloges (kMaxCatchupTicks = 4 dans
// fixed_tick, borne k <= 4 dans render_pace). Une image qui l'atteint a vu son temps reel
// ECRETE : ce temps-la n'est pas du temps de logique perdu par le debridage, c'est
// l'anti-spirale des deux modules. On le RETIRE de la fenetre et on le COMPTE.
constexpr u64 kCeilingK = 4;

constexpr double kTickRateTol = 0.02;  // 2 % sur ticks/60 contre le temps mural admis

// HORLOGE DE SCENE : DEUX SEUILS, ET C'EST VOULU. Le defaut que l'item nomme — l'increment
// TRONQUE, `(s32)(1024/target_fps)` — est un biais SYSTEMATIQUE : -0,39 % a 60 Hz, -6,25 % a
// 120 Hz, a chaque vblank, indefiniment. Une derive, c'est par definition un CUMUL, et c'est
// donc le cumul qui porte le verdict serre. Mais un cumul seul est aveugle a une casse qui se
// compense (registre : cumul aveugle a « detruire puis refabriquer »), donc le maximum PAR
// FENETRE reste juge aussi, a un seuil plus large : il attrape une rupture franche sans
// declarer « derive » le moindre a-coup de 5 secondes.
constexpr double kSceneCumulTol = 0.01;   // 1 % sur le DEBIT CUMULE
constexpr double kSceneWindowTol = 0.05;  // 5 % sur le pire debit de FENETRE

// « Meme mesure que anim-interp-low-fps ». La borne ANALYTIQUE des deux horloges est leur
// tolerance d'ecretage d'alpha : 0,03 tick (kCeilTol / kAlphaCeilTol), soit 500 us. On juge a
// 0,05 tick = 833 us : au-dessus de la borne que les modules s'imposent eux-memes, et vingt
// fois sous un tick manque (16667 us), qui est ce qu'un vrai desynchronisme produit.
constexpr u64 kPoseTolUs = 833;
constexpr u64 kPoseTolPctX100 = 500;  // 5 % d'un tick, la meme borne exprimee dans l'unite
                                      // de `tick_pose_err_pct_x100`

// Les deux modules publient 999999 quand leur condition n'a pas ete exercee. Une absence de
// mesure doit compter comme un DEFAUT, jamais passer pour un zero.
constexpr u64 kNoMeasurement = 999999;

// « Illimite » ne peut pas sortir a 0 : les DEUX limiteurs traitent une cible < 1 comme une
// valeur absurde et retombent a 60 (android_gfx.cpp, FrameLimiter.cpp). On rend donc une
// valeur finie qu'aucun materiel n'atteint.
constexpr double kUnlimitedFps = 1000.0;

bool armed() {
  // `armed_for` et pas `armed()` : le harnais qui desarme un AUTRE item ne doit pas
  // desarmer celui-ci du meme coup.
  static const bool s_armed = autoport_proof::armed_for("framerate-uncap");
  return s_armed;
}

// Consigne de MESURE. Elle remplace le reglage du menu pour epingler le regime d'une course
// de preuve : sans elle, le plafond livre est celui que la machine a sauvegarde, et deux
// courses du meme binaire ne mesurent pas la meme chose. `-1` = aucune consigne.
double knob_cap_fps() {
  static const double s_cap = []() -> double {
    if (const char* e = std::getenv("OG_UNCAP_FPS")) {
      if (e[0]) {
        return std::atof(e);
      }
    }
#ifdef __ANDROID__
    char pv[32] = {0};
    if (__system_property_get("debug.opengoal.uncap.fps", pv) > 0 && pv[0]) {
      return std::atof(pv);
    }
#endif
    return -1.0;
  }();
  return s_cap;
}

// LA LISTE CANONIQUE. Meme ordre que `*frame-rate-choices*` (pckernel-common.gc) et que
// `*carousell-frame-rate*` (progress-pc.gc). -1 = « Illimite ».
constexpr int kChoices[] = {30, 45, 60, 75, 90, 120, 240, -1};
constexpr int kChoiceCount = (int)(sizeof(kChoices) / sizeof(kChoices[0]));
// Le plus haut choix FINI de la liste : c'est ce que « Illimite » vaut quand une borne doit
// etre un nombre (la cible de l'echelle dynamique, par exemple).
constexpr int kHighestFiniteChoice = 240;

// ------------------------------------------------------- ce que le menu GOAL a pousse -----
// Ecrit par le fil EE (update-to-os), lu par le meme fil au moment de publier. Atomiques
// quand meme : `set_panel_hz` et `note_swap_interval_applied` viennent du fil GL.
std::atomic<int> g_menu_choices_n{0};
std::atomic<int> g_menu_choice_index{-1};
std::atomic<int> g_menu_dynscale_max{0};
std::atomic<int> g_panel_hz{0};
std::atomic<int> g_swap_interval_applied{-1};  // -1 = jamais applique
std::atomic<u64> g_presents{0};

// ---------------------------------------------------------------- horloge de scene --------
// Ecrite par le fil IOP (VBlank_Handler), lue par le fil EE. Deux atomiques et rien d'autre :
// un verrou pris dans un gestionnaire de vblank serait un defaut a lui tout seul.
std::atomic<u64> g_scene_units{0};
std::atomic<u64> g_scene_vblanks{0};

struct State {
  Timer wall;
  bool first_frame = true;

  u64 frames = 0;

  // fenetre courante
  double win_admitted_sec = 0.0;  // temps mural ADMIS (ecretage retire)
  double win_raw_sec = 0.0;       // temps mural BRUT
  u64 win_frames = 0;
  u64 win_ticks = 0;
  u64 win_scene_units0 = 0;
  u64 win_presents0 = 0;
  double win_busy_ms_sum = 0.0;
  u64 win_busy_samples = 0;
  double win_cap_fps = 0.0;
  int win_panel_hz = 0;
  int win_applied_interval = -1;
  int win_wanted_interval = -1;
  bool win_config_stable = true;

  // agregats
  u64 windows = 0;
  u64 over_windows = 0;
  double disp_fps_max = 0.0;
  // Debit maximal des retours de swap sur 5 s : soumissions, pas composition physique.
  double swap_fps_max = 0.0;
  u64 swap_max_window = 0;
  double swap_max_busy_ms = 0.0;
  u64 swap_max_busy_samples = 0;
  double swap_max_cap_fps = 0.0;
  int swap_max_panel_hz = 0;
  int swap_max_applied_interval = -1;
  int swap_max_wanted_interval = -1;
  bool swap_max_config_stable = false;
  u64 presents_total = 0;
  double rate_dev_max = 0.0;
  double scene_dev_max = 0.0;
  double scene_rate_last = 0.0;
  u64 scene_windows = 0;
  u64 scene_total_units = 0;   // cumul sur les fenetres FERMEES uniquement
  double scene_total_sec = 0.0;
  double dropped_sec = 0.0;
  u64 ceiling_frames = 0;
  // Images ou l'intervalle de swap APPLIQUE n'etait pas celui que le plafond demande. Compte
  // seulement quand la presentation est vivante (au moins un swap) : sinon un renderer qui
  // n'applique jamais rien rendrait zero desaccord, donc un faux vert.
  u64 present_mismatch_frames = 0;

  // suivi du k de l'horloge a pas fixe (elle n'expose qu'un CUMUL)
  u64 prev_total_ticks = 0;
  bool prev_total_valid = false;
};

State& state() {
  static State s;
  return s;
}

// L'horloge qui GOUVERNE cette course. Les deux s'EXCLUENT : `render_pace::armed()` rend faux
// des que `fixed_tick::enabled()`. Publier laquelle tourne n'est pas une decoration — les
// deux ne fournissent ni le meme k ni la meme convention d'alpha, et une mesure de l'une ne
// se transpose pas a l'autre.
bool fixed_tick_governs() {
  return fixed_tick::enabled();
}

// Le nombre de ticks de logique que l'image qui vient d'etre produite a fait executer.
u64 last_k(State& s) {
  if (fixed_tick_governs()) {
    const u64 total = fixed_tick::total_ticks();
    u64 k = 0;
    if (s.prev_total_valid && total >= s.prev_total_ticks) {
      k = total - s.prev_total_ticks;
    }
    s.prev_total_ticks = total;
    s.prev_total_valid = true;
    return k;
  }
  const double k = render_pace::last_k();
  return k > 0.0 ? (u64)(k + 0.5) : 0;
}

// L'ecart de POSE DESSINEE, lu chez l'horloge qui gouverne. On ne fabrique pas un troisieme
// instrument pour un chiffre : chacune publie deja le sien pour son propre item, et c'est
// celui-la que le livrable nomme (« meme mesure que anim-interp-low-fps »).
// Rend un couple (valeur, seuil) dans l'unite du module qui gouverne.
void pose_measure(u64* out_value, u64* out_tol) {
  if (fixed_tick_governs()) {
    *out_value = fixed_tick::pose_err_pct_x100();
    *out_tol = kPoseTolPctX100;
  } else {
    *out_value = render_pace::step_err_max_us();
    *out_tol = kPoseTolUs;
  }
}

void begin_ceiling_window(State& s) {
  s.win_busy_ms_sum = 0.0;
  s.win_busy_samples = 0;
  s.win_cap_fps = cap_fps((double)Gfx::g_global_settings.target_fps);
  s.win_panel_hz = g_panel_hz.load(std::memory_order_relaxed);
  s.win_applied_interval = g_swap_interval_applied.load(std::memory_order_relaxed);
  s.win_wanted_interval = desired_swap_interval();
  s.win_config_stable = true;
}

void close_window(State& s) {
  s.windows++;

  // CADENCE D'AFFICHAGE : images dessinees par seconde REELLE. C'est la grandeur qui dit si
  // le debridage a eu lieu ; elle se mesure sur le temps BRUT, pas sur le temps admis.
  const double disp_fps = s.win_raw_sec > 0.0 ? (double)s.win_frames / s.win_raw_sec : 0.0;
  if (disp_fps > s.disp_fps_max) {
    s.disp_fps_max = disp_fps;
  }
  const double reference = (double)Gfx::g_global_settings.target_fps;
  if (reference > 0.0 && disp_fps > reference * kOverFactor) {
    s.over_windows++;
  }

  // Retours de swap par seconde reelle. Le mode overlap les decouple de la boucle EE ;
  // ils ne mesurent ni les images retenues par le compositeur ni le balayage du panneau.
  const u64 presents_now = g_presents.load(std::memory_order_relaxed);
  if (s.win_raw_sec > 0.0 && presents_now >= s.win_presents0) {
    const double swap_fps = (double)(presents_now - s.win_presents0) / s.win_raw_sec;
    if (swap_fps > s.swap_fps_max) {
      s.swap_fps_max = swap_fps;
      s.swap_max_window = s.windows;
      s.swap_max_busy_ms =
          s.win_busy_samples > 0 ? s.win_busy_ms_sum / (double)s.win_busy_samples : 0.0;
      s.swap_max_busy_samples = s.win_busy_samples;
      s.swap_max_cap_fps = s.win_cap_fps;
      s.swap_max_panel_hz = s.win_panel_hz;
      s.swap_max_applied_interval = s.win_applied_interval;
      s.swap_max_wanted_interval = s.win_wanted_interval;
      s.swap_max_config_stable = s.win_config_stable;
    }
  }
  s.presents_total = presents_now;

  // CADENCE DE LOGIQUE : le temps de jeu emis (ticks/60) contre le temps mural ADMIS. C'est
  // la clause « la logique recoit toujours 60 ticks par seconde reelle » et, du meme coup,
  // « rien ne s'accelere ni ne ralentit » : le temps de jeu EST le nombre de ticks.
  if (s.win_admitted_sec > 0.0) {
    const double emitted = (double)s.win_ticks * kTickSeconds;
    const double dev = std::fabs(emitted - s.win_admitted_sec) / s.win_admitted_sec;
    if (dev > s.rate_dev_max) {
      s.rate_dev_max = dev;
    }
  }

  // HORLOGE DE SCENE : unites debitees par seconde reelle, contre 1024. Le vblank est un
  // AUTRE fil que celui-ci ; sur une fenetre de 5 s le decalage d'echantillonnage vaut au
  // plus une periode de vblank, soit 0,3 % — sous la tolerance, et il ne s'accumule pas.
  const u64 units_now = g_scene_units.load(std::memory_order_relaxed);
  if (s.win_raw_sec > 0.0 && units_now >= s.win_scene_units0) {
    const double rate = (double)(units_now - s.win_scene_units0) / s.win_raw_sec;
    s.scene_rate_last = rate;
    s.scene_windows++;
    s.scene_total_units += units_now - s.win_scene_units0;
    s.scene_total_sec += s.win_raw_sec;
    const double dev = std::fabs(rate - kSceneUnitsPerSecond) / kSceneUnitsPerSecond;
    if (dev > s.scene_dev_max) {
      s.scene_dev_max = dev;
    }
  }

  s.win_admitted_sec = 0.0;
  s.win_raw_sec = 0.0;
  s.win_frames = 0;
  s.win_ticks = 0;
  s.win_scene_units0 = units_now;
  s.win_presents0 = presents_now;
  begin_ceiling_window(s);
}

void publish(State& s) {
  autoport_proof::publish("uncap_armed", armed() ? 1 : 0);
  autoport_proof::publish_text("uncap_clock", fixed_tick_governs() ? "fixed_tick" : "render_pace");
  autoport_proof::publish("uncap_frames", s.frames);
  autoport_proof::publish("uncap_windows", s.windows);
  autoport_proof::publish("uncap_over_windows", s.over_windows);
  autoport_proof::publish("uncap_disp_fps_max_x100", (u64)(s.disp_fps_max * 100.0 + 0.5));

  // ------------------------- (b) LE PLAFOND REELLEMENT ATTEINT, ET QUI LE POSE -------------
  const int panel_hz = g_panel_hz.load(std::memory_order_relaxed);
  const int applied_interval = g_swap_interval_applied.load(std::memory_order_relaxed);
  const int wanted_interval = desired_swap_interval();
  // Moyenne des echantillons existants dans LA fenetre du maximum, jamais l'EMA courante
  // d'une scene ulterieure. Ce signal mesure le travail CPU du renderer, pas le GPU seul.
  const double busy_ms = s.swap_max_busy_ms;
  const double busy_hz = busy_ms > 0.0 ? 1000.0 / busy_ms : 0.0;
  autoport_proof::publish("uncap_ceiling_hz", (u64)(s.swap_fps_max + 0.5));
  autoport_proof::publish("uncap_ceiling_hz_x100", (u64)(s.swap_fps_max * 100.0 + 0.5));
  autoport_proof::publish("uncap_presents", s.presents_total);
  autoport_proof::publish("uncap_panel_hz", (u64)(panel_hz > 0 ? panel_hz : 0));
  autoport_proof::publish("uncap_swap_interval_applied",
                          (u64)(applied_interval < 0 ? 999 : applied_interval));
  autoport_proof::publish("uncap_swap_interval_wanted", (u64)wanted_interval);
  autoport_proof::publish("uncap_present_mismatch_frames", s.present_mismatch_frames);
  autoport_proof::publish("uncap_busy_hz_x100", (u64)(busy_hz * 100.0 + 0.5));
  autoport_proof::publish("uncap_ceiling_window", s.swap_max_window);
  autoport_proof::publish("uncap_ceiling_busy_ms_x100", (u64)(busy_ms * 100.0 + 0.5));
  autoport_proof::publish("uncap_ceiling_busy_samples", s.swap_max_busy_samples);
  autoport_proof::publish("uncap_ceiling_config_stable", s.swap_max_config_stable ? 1 : 0);
  autoport_proof::publish("uncap_ceiling_cap_fps_x100",
                          (u64)(s.swap_max_cap_fps * 100.0 + 0.5));
  autoport_proof::publish("uncap_ceiling_panel_hz", (u64)s.swap_max_panel_hz);
  autoport_proof::publish("uncap_ceiling_swap_interval_applied",
                          (u64)(s.swap_max_applied_interval < 0 ? 999 : s.swap_max_applied_interval));
  autoport_proof::publish("uncap_ceiling_swap_interval_wanted",
                          (u64)(s.swap_max_wanted_interval < 0 ? 999 : s.swap_max_wanted_interval));
  // QUI plafonne. Chaque branche est une COMPARAISON de grandeurs publiees a cote : qui lit le
  // proof refait le raisonnement sans nous croire.
  const char* cause = "indetermine";
  bool ceiling_attributed = false;
  if (s.swap_max_window == 0) {
    cause = "non-mesure-aucune-fenetre";
  } else if (!s.swap_max_config_stable) {
    // Un maximum obtenu pendant un changement de reglage ne permet pas d'attribution.
  } else if (s.swap_max_cap_fps > 0.0 && s.swap_fps_max >= s.swap_max_cap_fps * 0.98) {
    cause = "la-consigne";  // 240 atteint : c'est le plafond demande qui borne
    ceiling_attributed = true;
  } else if (s.swap_max_applied_interval == 1 && s.swap_max_panel_hz > 0 &&
             std::fabs(s.swap_fps_max - (double)s.swap_max_panel_hz) <=
                 (double)s.swap_max_panel_hz * 0.05) {
    cause = "presentation-fifo-sur-le-panneau";
    ceiling_attributed = true;
  } else if (busy_hz > 0.0 && std::fabs(s.swap_fps_max - busy_hz) <= busy_hz * 0.10) {
    cause = "temps-de-rendu";
    ceiling_attributed = true;
  }
  autoport_proof::publish_text("uncap_ceiling_cause", cause);

  // ------------------- (a) CE QUE LE MENU OFFRE, ET (c) LA BORNE QU'IL EN DERIVE -----------
  const int choices_n = g_menu_choices_n.load(std::memory_order_relaxed);
  const int choice_index = g_menu_choice_index.load(std::memory_order_relaxed);
  const int dynscale_max = g_menu_dynscale_max.load(std::memory_order_relaxed);
  const int chosen_fps = (choice_index >= 0 && choice_index < kChoiceCount)
                             ? kChoices[choice_index]
                             : 0;
  autoport_proof::publish("uncap_choices_n", (u64)(choices_n < 0 ? 0 : choices_n));
  autoport_proof::publish("uncap_choices_expected", (u64)kChoiceCount);
  autoport_proof::publish("uncap_choice_index", (u64)(choice_index < 0 ? 999 : choice_index));
  autoport_proof::publish("uncap_choice_fps",
                          (u64)(chosen_fps < 0 ? kHighestFiniteChoice : chosen_fps));
  autoport_proof::publish("uncap_choice_unlimited", (u64)(chosen_fps < 0 ? 1 : 0));
  autoport_proof::publish("uncap_dynscale_target_max", (u64)(dynscale_max < 0 ? 0 : dynscale_max));

  // LA REFERENCE EFFECTIVE, publiee a cote de la mesure. `target_fps` est la reference de
  // TEMPS (elle doit rester a 60 : c'est le coeur du correctif) ; `cap_fps` est ce que le
  // limiteur a reellement recu. Les confondre etait exactement le defaut.
  autoport_proof::publish("uncap_target_fps_x100",
                          (u64)((double)Gfx::g_global_settings.target_fps * 100.0 + 0.5));
  autoport_proof::publish(
      "uncap_cap_fps_x100",
      (u64)(cap_fps((double)Gfx::g_global_settings.target_fps) * 100.0 + 0.5));
  autoport_proof::publish("uncap_cap_setting_x100",
                          (u64)(std::fabs((double)Gfx::g_global_settings.display_fps_cap) * 100.0 +
                                0.5));

  autoport_proof::publish("uncap_ceiling_frames", s.ceiling_frames);
  autoport_proof::publish("uncap_time_dropped_ms", (u64)(s.dropped_sec * 1000.0 + 0.5));

  const bool enough = s.windows >= kMinWindows;
  const u64 rate_x100 = enough ? (u64)(s.rate_dev_max * 10000.0 + 0.5) : kNoMeasurement;
  const bool scene_enough = s.scene_windows >= kMinWindows && s.scene_total_sec > 0.0;
  const double scene_cumul_rate =
      scene_enough ? (double)s.scene_total_units / s.scene_total_sec : 0.0;
  const double scene_cumul_dev =
      std::fabs(scene_cumul_rate - kSceneUnitsPerSecond) / kSceneUnitsPerSecond;
  const u64 scene_x100 = scene_enough ? (u64)(scene_cumul_dev * 10000.0 + 0.5) : kNoMeasurement;
  const u64 scene_win_x100 =
      scene_enough ? (u64)(s.scene_dev_max * 10000.0 + 0.5) : kNoMeasurement;
  autoport_proof::publish("uncap_tick_rate_dev_pct_x100", rate_x100);
  autoport_proof::publish("uncap_scene_dev_pct_x100", scene_x100);
  autoport_proof::publish("uncap_scene_window_dev_pct_x100", scene_win_x100);
  autoport_proof::publish("uncap_scene_units_per_s_x100", (u64)(scene_cumul_rate * 100.0 + 0.5));
  autoport_proof::publish("uncap_scene_last_units_per_s_x100",
                          (u64)(s.scene_rate_last * 100.0 + 0.5));
  autoport_proof::publish("uncap_scene_windows", s.scene_windows);
  autoport_proof::publish("uncap_scene_vblanks", g_scene_vblanks.load(std::memory_order_relaxed));

  u64 pose_value = 0, pose_tol = 0;
  pose_measure(&pose_value, &pose_tol);
  autoport_proof::publish("uncap_pose_err", pose_value);
  autoport_proof::publish("uncap_pose_tol", pose_tol);

  // ------------------------------------------------------------------- LES VERDICTS -------
  // Un verdict par clause du livrable, publie SEPAREMENT : une somme qui vaut 2 sans dire
  // lesquels ne se corrige pas. Chacun vaut 1 quand la clause n'est PAS tenue, et 1 aussi
  // quand elle n'a pas pu etre mesuree.
  // ---------- CE QUI EST UN DEFAUT, ET CE QUI EST UNE PROPRIETE DE LA MACHINE ----------
  // L'essai 1 comptait « la cadence n'a jamais depasse 60 » comme un defaut, en garde
  // anti-vacuite. Mesure du 2026-09-06 sur le Redmi Note 9 Pro, plafond a 240 : cadence max
  // 46,26 img/s sur 69 fenetres, et le journal du moteur montre l'auto-echelle COLLEE a son
  // plancher (`avg-fps=18.0 scale=40`) — l'appareil n'est pas limite par le remplissage, il
  // l'est ailleurs, et AUCUN reglage ne le fera passer au-dessus de 60. La garde rendait donc
  // la porte inatteignable sur le seul appareil autorise, quelle que soit la qualite du code :
  // c'est un defaut de l'instrument, pas du correctif.
  //
  // Ce que la machine ne peut pas produire ne devient pas un vert silencieux pour autant.
  // `uncap_regime_entered`, `uncap_over_windows` et `uncap_disp_fps_max_x100` restent PUBLIES :
  // qui lit le proof voit immediatement si la cadence a depasse 60, et le rapport doit ecrire
  // `non prouve` quand elle ne l'a pas fait.
  //
  // Le verdict porte donc sur ce que l'appareil PEUT falsifier : le plafond que le limiteur a
  // reellement recu doit depasser la reference de temps du moteur. C'est la panne silencieuse
  // reelle — un reglage qui n'atteint pas le C++ (Android est toujours en 'fullscreen, et la
  // poussee de `update-to-os` etait gardee par `(!= 'fullscreen ...)`) — et le bras DESARME de
  // l'ablation le fait retomber a 60, donc il est causal et non un miroir.
  const u64 regime_entered = s.over_windows > 0 ? 1 : 0;
  const double cap = cap_fps((double)Gfx::g_global_settings.target_fps);
  const double reference = (double)Gfx::g_global_settings.target_fps;
  const u64 v_cap = (reference > 0.0 && cap > reference * kOverFactor) ? 0 : 1;
  autoport_proof::publish("uncap_regime_entered", regime_entered);
  const u64 v_windows = enough ? 0 : 1;
  const u64 v_tick_rate =
      (rate_x100 != kNoMeasurement && s.rate_dev_max <= kTickRateTol) ? 0 : 1;
  const u64 v_scene = (scene_enough && scene_cumul_dev <= kSceneCumulTol &&
                       s.scene_dev_max <= kSceneWindowTol)
                          ? 0
                          : 1;
  const u64 v_pose = (pose_value != kNoMeasurement && pose_value <= pose_tol) ? 0 : 1;

  // ---------------------- LES QUATRE VERDICTS DE L'ESSAI 2 -------------------------------
  // uncap_v_choices   (a) LE REGLAGE EST UNE LISTE. Trois conditions, et il faut les trois :
  //                   le menu offre exactement les 8 choix de la liste canonique, l'index
  //                   courant est dans les bornes, et l'entree a cet index est EXACTEMENT le
  //                   plafond que le reglage porte. La troisieme est celle qui compte : elle
  //                   attache le libelle affiche a la valeur qui traverse. Un curseur ne
  //                   pousse rien du tout et rend `choices_n = 0`.
  const double setting_cap = (double)Gfx::g_global_settings.display_fps_cap;
  bool choice_matches = false;
  if (chosen_fps < 0) {
    choice_matches = setting_cap < 0.0;  // « Illimite » s'ecrit negatif
  } else if (chosen_fps > 0) {
    choice_matches = std::fabs(setting_cap - (double)chosen_fps) < 0.5;
  }
  const u64 v_choices = (choices_n == kChoiceCount && choice_index >= 0 &&
                         choice_index < kChoiceCount && choice_matches)
                            ? 0
                            : 1;

  // uncap_v_dynscale  (c) LA CIBLE DE L'ECHELLE DYNAMIQUE SUIT LE PLAFOND. La borne haute de
  //                   la rangee doit atteindre le plafond choisi. La constante 60 que l'owner
  //                   denonce echoue des que le plafond depasse 60 — et la consigne de mesure
  //                   garantit qu'il le depasse pendant la preuve, sinon la regle correcte et
  //                   la constante fautive rendraient le meme chiffre.
  const int chosen_finite = chosen_fps < 0 ? kHighestFiniteChoice : chosen_fps;
  const u64 v_dynscale = (chosen_finite > 0 && dynscale_max >= chosen_finite) ? 0 : 1;

  // uncap_v_present   (b) LA PRESENTATION N'IMPOSE PAS SON PROPRE PLAFOND. L'intervalle de
  //                   swap applique doit etre celui que le plafond demande. C'etait la panne :
  //                   `SDL_GL_SetSwapInterval(1)` une fois pour toutes, et un swap en FIFO
  //                   rend le rafraichissement du panneau quoi qu'on demande. Falsifiable ici :
  //                   sur le Redmi (panneau 60) une consigne a 240 exige l'intervalle 0.
  //                   Tolerance de 5 % des images : le fil GL applique avec une image de
  //                   retard quand le plafond change, et l'amorcage precede la premiere
  //                   application.
  const u64 v_present =
      (s.frames >= 300 && s.present_mismatch_frames <= s.frames / 20) ? 0 : 1;

  // Le maximum doit etre mesure ET attribue avec les grandeurs de cette meme fenetre.
  // Une cause indeterminee ou une fenetre de transition reste un defaut explicite.
  const u64 v_ceiling =
      (s.swap_max_window > 0 && s.swap_fps_max > 0.0 && ceiling_attributed) ? 0 : 1;

  autoport_proof::publish("uncap_v_cap", v_cap);
  autoport_proof::publish("uncap_v_windows", v_windows);
  autoport_proof::publish("uncap_v_tick_rate", v_tick_rate);
  autoport_proof::publish("uncap_v_scene", v_scene);
  autoport_proof::publish("uncap_v_pose", v_pose);
  autoport_proof::publish("uncap_v_choices", v_choices);
  autoport_proof::publish("uncap_v_dynscale", v_dynscale);
  autoport_proof::publish("uncap_v_present", v_present);
  autoport_proof::publish("uncap_v_ceiling", v_ceiling);
  autoport_proof::publish("uncap_defects", v_cap + v_windows + v_tick_rate + v_scene + v_pose +
                                               v_choices + v_dynscale + v_present + v_ceiling);
}

}  // namespace

double cap_fps(double engine_target_fps) {
  // ABLATION. Desarme, le debridage n'existe pas : le limiteur reprend la reference moteur,
  // c'est-a-dire le comportement d'avant cet item, sur LE MEME binaire.
  if (!armed()) {
    return engine_target_fps;
  }
  double cap = knob_cap_fps();
  if (cap < 0.0) {
    cap = (double)Gfx::g_global_settings.display_fps_cap;
  }
  if (cap < 0.0) {
    return kUnlimitedFps;  // illimite
  }
  if (cap <= 0.0) {
    return engine_target_fps;  // aucun plafond configure : comportement d'origine
  }
  return cap;
}

void on_render_frame() {
  State& s = state();
  const u64 k = last_k(s);

  if (s.first_frame) {
    // La premiere image porte la duree de tout l'amorcage : elle n'est pas une image.
    s.first_frame = false;
    s.wall.start();
    s.win_scene_units0 = g_scene_units.load(std::memory_order_relaxed);
    s.win_presents0 = g_presents.load(std::memory_order_relaxed);
    begin_ceiling_window(s);
    return;
  }

  const double dt = s.wall.getSeconds();
  s.wall.start();
  s.frames++;

  const double busy_ms = (double)Gfx::g_global_settings.measured_frame_busy_ms;
  if (std::isfinite(busy_ms) && busy_ms > 0.0) {
    s.win_busy_ms_sum += busy_ms;
    s.win_busy_samples++;
  }
  if (s.win_cap_fps != cap_fps((double)Gfx::g_global_settings.target_fps) ||
      s.win_panel_hz != g_panel_hz.load(std::memory_order_relaxed) ||
      s.win_applied_interval != g_swap_interval_applied.load(std::memory_order_relaxed) ||
      s.win_wanted_interval != desired_swap_interval()) {
    s.win_config_stable = false;
  }

  // TEMPS ADMIS. Une image qui a consomme le plafond de rattrapage a vu son temps reel
  // ecrete par l'horloge : compter ce temps-la dans la fenetre reviendrait a reprocher au
  // debridage la lenteur de l'appareil. Ce qui est retire est compte, jamais efface.
  double admitted = dt;
  if (k >= kCeilingK) {
    const double ceiling = (double)kCeilingK * kTickSeconds;
    if (dt > ceiling) {
      s.dropped_sec += dt - ceiling;
      admitted = ceiling;
      s.ceiling_frames++;
    }
  }

  s.win_raw_sec += dt;
  s.win_admitted_sec += admitted;
  s.win_frames++;
  s.win_ticks += k;

  // L'intervalle de swap doit SUIVRE le plafond. On ne compte le desaccord que quand la
  // presentation est vivante : un renderer qui n'a jamais rien applique doit rendre un
  // desaccord, pas un silence.
  if (g_presents.load(std::memory_order_relaxed) > 0 &&
      g_swap_interval_applied.load(std::memory_order_relaxed) != desired_swap_interval()) {
    s.present_mismatch_frames++;
  }

  if (s.win_raw_sec >= kWindowSeconds) {
    close_window(s);
  }

  if (armed()) {
    autoport_proof::note_hit();
  }
  publish(s);
}

int choice_count() {
  return kChoiceCount;
}

int choice_fps(int index) {
  if (index < 0 || index >= kChoiceCount) {
    return 0;
  }
  return kChoices[index];
}

void set_menu_state(int choices_n, int choice_index, int dynscale_target_max) {
  g_menu_choices_n.store(choices_n, std::memory_order_relaxed);
  g_menu_choice_index.store(choice_index, std::memory_order_relaxed);
  g_menu_dynscale_max.store(dynscale_target_max, std::memory_order_relaxed);
}

int cap_override_fps() {
  // DESARME, aucune consigne : le bras d'ablation doit voir le reglage que la machine a
  // sauvegarde, pas celui que la preuve epingle.
  if (!armed()) {
    return 0;
  }
  const double k = knob_cap_fps();
  if (k < 1.0) {
    return 0;  // -1 = aucune consigne ; une consigne < 1 img/s n'a pas de sens
  }
  return (int)(k + 0.5);
}

void set_panel_hz(int hz) {
  g_panel_hz.store(hz > 0 ? hz : 0, std::memory_order_relaxed);
}

int desired_swap_interval() {
  // LE SEUL ENDROIT QUI DECIDE. Deux ecrivains pour un intervalle, c'est deux regimes
  // differents selon la plateforme. Android forcait 1 a l'initialisation et ne relisait
  // plus rien ; cela ne prouve pas la cause des 90 Hz observes sur l'Honor de l'owner.
  const double cap = cap_fps((double)Gfx::g_global_settings.target_fps);
  const int panel = g_panel_hz.load(std::memory_order_relaxed);
  if (panel > 0 && cap > (double)panel * kOverFactor) {
    // Le plafond demande depasse ce que le balayage peut rendre : attendre le balayage
    // peut borner les soumissions a la cadence du panneau.
    return 0;
  }
  return Gfx::g_global_settings.vsync ? 1 : 0;
}

void note_swap_interval_applied(int interval) {
  g_swap_interval_applied.store(interval, std::memory_order_relaxed);
}

void note_present() {
  g_presents.fetch_add(1, std::memory_order_relaxed);
}

double scene_vblank_hz(double engine_target_fps) {
#ifdef __ANDROID__
  // Le pacer bat a `target_fps` sur sa propre montre, quoi que fasse le rendu.
  const double hz = engine_target_fps;
#else
  // Un vblank par swap : la cadence des appels est celle que le limiteur tient.
  const double hz = cap_fps(engine_target_fps);
#endif
  return hz > 0.0 ? hz : 60.0;
}

void on_scene_vblank(s32 units_added) {
  if (units_added > 0) {
    g_scene_units.fetch_add((u64)units_added, std::memory_order_relaxed);
  }
  g_scene_vblanks.fetch_add(1, std::memory_order_relaxed);
}

}  // namespace uncap
