#include "game/graphics/refset.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "common/util/FileUtil.h"

#include "game/graphics/fixed_tick.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/render_pace.h"
#include "game/system/autoport_proof.h"
#include "game/system/pad_replay.h"

#include "third-party/fpng/fpng.h"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace refset {
namespace {

// ── le plan ─────────────────────────────────────────────────────────────────────────────────
// Deux jeux x huit creneaux horaires. Les huit heures sont les huit creneaux de
// `mood-lights-table` (SPEC §3.1) espaces de trois heures : c'est la grille sur laquelle la
// donnee de Naughty Dog est art-dirigee.
constexpr int kHours[8] = {0, 3, 6, 9, 12, 15, 18, 21};

struct Step {
  int phase;  // 1 = ORIGINE (master OFF), 2 = RECHARGED (master ON, prereglage fige)
  int hour;
};

// Frames de LOGIQUE. Elles ne dependent pas de la cadence : `pad_replay` force un pas de
// 1/60 s par image des l'ancre.
constexpr int64_t kAnchorSettle = 300;  // 5 s apres le premier warp : le niveau est charge et lie
// Frames de logique entre le TELEPORT d'une etape et sa photo. Reglable par
// `OG_REFSET_SETTLE` : c'est le seul curseur du compromis « la camera n'a pas encore diverge »
// contre « l'heure et le lissage de la lumiere sont poses ». Le regler ne demande pas de rebatir.
int64_t g_step_settle = 180;

constexpr int kShotW = 320;
constexpr int kShotH = 180;

std::mutex g_mutex;

int g_mode = 0;  // 0 = eteint, 1 = capture, 2 = replay
std::string g_dir = ".autoport/refset";

std::vector<Step> g_steps;
size_t g_cur = 0;  // etape en cours
bool g_finished = false;

int g_tod_x100 = -1;

// ── demande de capture, du fil GOAL vers le fil graphique ───────────────────────────────────
// UN SEUL automate, et pas trois booleens. Avec trois booleens le fil graphique pouvait
// re-armer la meme demande entre la fin d'une capture et le passage du fil GOAL a l'etape
// suivante : mesure du 2026-09-06, 16 captures annoncees pour 10 fichiers ecrits, les heures
// 03, 15 et 21 SAUTEES dans les deux jeux. Une etape sautee est une reference manquante, et
// une reference manquante rend la porte inoperante sur ce creneau.
enum CapState { kCapIdle = 0, kCapWaitWarp, kCapArmed, kCapInFlight, kCapDone };
int g_cap = kCapIdle;
int64_t g_capture_frame = -1;      // la chaine attendue porte cette frame de logique
std::string g_capture_name;        // <jeu>/h<hh>

// ── horloge de logique ──────────────────────────────────────────────────────────────────────
// Chaque instant du plan est ancre sur un EVENEMENT (un teleport), jamais sur « l'image ou j'ai
// remarque que... » : une image de logique non rendue ne decale donc rien.
int64_t (*g_logic_fn)() = nullptr;
// UN TELEPORT PAR ETAPE. Le point de repos de la camera depend du chemin : deux courses
// identiques le trouvent a ~0,02 m l'une de l'autre, ce qui suffit a rendre la moitie des pixels
// differents. Un `(start 'play <continue>)` juste avant chaque photo remet la camera a une pose
// TELEPORTEE, et la photo est prise assez tot pour que la derive n'ait pas eu le temps de
// s'installer.
int64_t g_warp1 = -1;             // premier warp : sert seulement a savoir que le niveau est la
bool g_rewarp_asked = false;      // une demande de teleport est en vol
int64_t g_rewarp_asked_lf = -1;   // depuis quand : une demande perdue doit se re-poser
int64_t g_step_anchor = -1;       // frame de logique du teleport de l'etape courante
uint64_t g_rewarps = 0;

// ── mesures ─────────────────────────────────────────────────────────────────────────────────
uint64_t g_captured = 0;
// L'alpha BRUT du retimeur de rendu, echantillonne une fois par image dessinee. Voir
// `publish_state` : c'est la mesure de ce que la course de reference supprime.
int64_t g_raw_alpha_min = 1 << 30;
int64_t g_raw_alpha_max = -1;
uint64_t g_raw_alpha_n = 0;
uint64_t g_compared = 0;
uint64_t g_missing = 0;
uint64_t g_size_bad = 0;
uint64_t g_decode_bad = 0;
uint64_t g_roundtrip_bad = 0;
uint64_t g_maxdiff = 0;
uint64_t g_diffpx = 0;
int64_t g_frame_slip_max = 0;
int64_t g_frame_slip_min = 1 << 20;

const char* set_name(int phase) {
  return phase == 1 ? "origine" : "recharged";
}

// `setenv` n'existe pas sur MSVC ; le seul appelant est ce module.
void put_env(const char* key, const char* value) {
#if defined(_WIN32)
  _putenv_s(key, value);
#else
  setenv(key, value, 1);
#endif
}

bool read_knob(const char* env, const char* prop, char* out, size_t cap) {
  if (const char* e = std::getenv(env)) {
    if (e[0]) {
      std::snprintf(out, cap, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, cap, "%s", buf);
    return true;
  }
#else
  (void)prop;
#endif
  return false;
}

void publish_state() {
  autoport_proof::publish_text("refset_mode", g_mode == 1 ? "capture" : "replay");
#if defined(__ANDROID__)
  autoport_proof::publish_text("refset_platform", "device");
#else
  autoport_proof::publish_text("refset_platform", "x86");
#endif
  autoport_proof::publish("refset_steps", g_steps.size());
  autoport_proof::publish("refset_step_done", g_cur);
  autoport_proof::publish("refset_step_anchor_set", g_step_anchor >= 0 ? 1 : 0);
  autoport_proof::publish("refset_rewarps", g_rewarps);
  autoport_proof::publish("refset_settle", (uint64_t)g_step_settle);
  autoport_proof::publish("refset_captured", g_captured);
  autoport_proof::publish("refset_slip_max", (uint64_t)(g_frame_slip_max < 0 ? 0
                                                                             : g_frame_slip_max));
  autoport_proof::publish("refset_slip_min",
                          (uint64_t)(g_frame_slip_min > (1 << 19) ? 0 : g_frame_slip_min));
  autoport_proof::publish("refset_roundtrip_bad", g_roundtrip_bad);
  // LE RETIMEUR DE RENDU, LU SUR SON ETAT REELLEMENT LATCHE — pas sur notre intention.
  // `render_pace` est la seule entree de montre murale du chemin de dessin : son alpha
  // reecrit la pose DESSINEE de la camera (cam-update.gc:246) et celle des articulations
  // (drawable.gc:1107). Tant qu'il est arme, deux courses identiques ne peuvent pas rendre
  // la meme image, et `refset_replay_maxdiff` le dirait sans dire pourquoi. Ces deux lignes
  // nomment la cause dans la preuve elle-meme : une reference n'est rejouable que capturee
  // et rejouee avec `refset_pace_armed=0`.
  autoport_proof::publish("refset_pace_armed", render_pace::armed() ? 1 : 0);
  autoport_proof::publish("refset_fixed_tick_armed", fixed_tick::enabled() ? 1 : 0);
  // CE QUE LA NEUTRALISATION SUPPRIME, MESURE. `refset_pace_alpha` est ce que GOAL lit
  // vraiment (1000000 = identite). `refset_raw_alpha_min/max` est ce que `render_pace` a
  // calcule depuis la cadence d'affichage REELLE pendant la meme course : min != max prouve
  // que la grandeur supprimee variait, donc que la neutralisation n'est pas une clause vide.
  autoport_proof::publish("refset_pace_alpha", (uint64_t)(int64_t)render_pace::alpha_micro());
  autoport_proof::publish("refset_pace_skip", render_pace::skip() ? 1 : 0);
  if (g_raw_alpha_n) {
    autoport_proof::publish("refset_raw_alpha_min", (uint64_t)g_raw_alpha_min);
    autoport_proof::publish("refset_raw_alpha_max", (uint64_t)g_raw_alpha_max);
    autoport_proof::publish("refset_raw_alpha_n", g_raw_alpha_n);
  }
  if (g_mode == 2) {
    autoport_proof::publish("refset_compared", g_compared);
    autoport_proof::publish("refset_missing", g_missing);
    autoport_proof::publish("refset_size_bad", g_size_bad);
    autoport_proof::publish("refset_decode_bad", g_decode_bad);
    autoport_proof::publish("refset_replay_diffpx", g_diffpx);
    // 254 = le plan n'est pas alle au bout ; 255 = une reference manque ou ne se decode pas.
    // La vraie mesure ne remplace ces deux valeurs QUE lorsque tout a ete compare.
    uint64_t gate;
    if (g_missing || g_size_bad || g_decode_bad) {
      gate = 255;
    } else if (!g_finished) {
      gate = 254;
    } else {
      gate = g_maxdiff;
    }
    autoport_proof::publish("refset_replay_maxdiff", gate);
  }
  // En mode capture on ne publie AUCUNE valeur de porte : une course qui fabrique ses propres
  // references ne doit pas pouvoir la franchir.
}

std::string image_path(const std::string& name) {
  return g_dir + "/" + name + ".png";
}

void apply_step_config(const Step& s) {
  // Le master et la lumiere temps reel se pilotent par les surcharges d'environnement qui
  // EXISTENT (gfx.h:554 `OG_RECHARGED`, background_common.cpp:2635 `OG_RT_LIGHT`). Ecrire
  // directement dans `g_global_settings` ne tiendrait pas : GOAL repousse `recharged-master?`
  // a chaque image (hud-classes-pc.gc:1747). Les deux variables sont posees a leur longueur
  // definitive des l'initialisation, donc chaque bascule n'est qu'un `strcpy` en place.
  if (s.phase == 1) {
    put_env("OG_RECHARGED", "0");
    put_env("OG_RT_LIGHT", "0");
  } else {
    put_env("OG_RECHARGED", "1");
    put_env("OG_RT_LIGHT", "1");
  }
  g_tod_x100 = s.hour * 100;
  lighting_census::set_phase(s.phase);
}

// Compare deux tampons RGBA de meme taille. L'alpha est ignore : `finish_screenshot` le force a
// 0xff, il ne porte donc aucune information.
void compare(const uint8_t* a, const uint8_t* b, int n_px, uint64_t* maxd, uint64_t* npx) {
  uint64_t md = 0, np = 0;
  for (int i = 0; i < n_px; i++) {
    int d = 0;
    for (int c = 0; c < 3; c++) {
      int t = (int)a[i * 4 + c] - (int)b[i * 4 + c];
      if (t < 0) {
        t = -t;
      }
      if (t > d) {
        d = t;
      }
    }
    if (d > 0) {
      np++;
      if ((uint64_t)d > md) {
        md = (uint64_t)d;
      }
    }
  }
  *maxd = md;
  *npx = np;
}

}  // namespace

bool enabled() {
  static int s_init = 0;
  if (s_init) {
    return g_mode != 0;
  }
  s_init = 1;
  char v[32] = {0};
  if (!read_knob("OG_REFSET", "debug.opengoal.refset", v, sizeof(v))) {
    return false;
  }
  if (std::strcmp(v, "capture") == 0) {
    g_mode = 1;
  } else if (std::strcmp(v, "replay") == 0) {
    g_mode = 2;
  } else {
    return false;
  }
  char d[512] = {0};
  if (read_knob("OG_REFSET_DIR", "debug.opengoal.refset.dir", d, sizeof(d))) {
    g_dir = d;
  }
  {
    char sv[32] = {0};
    if (read_knob("OG_REFSET_SETTLE", "debug.opengoal.refset.settle", sv, sizeof(sv))) {
      const long v = std::strtol(sv, nullptr, 10);
      if (v >= 2 && v <= 3600) {
        g_step_settle = v;
      }
    }
  }
  fpng::fpng_init();
  for (int phase = 1; phase <= 2; phase++) {
    for (int h : kHours) {
      g_steps.push_back(Step{phase, h});
    }
  }
  // Poser les deux variables a leur longueur definitive AVANT que le fil graphique ne les lise
  // pour la premiere fois : ainsi chaque bascule ulterieure reecrit un unique octet en place.
  put_env("OG_RECHARGED", "0");
  put_env("OG_RT_LIGHT", "0");
  file_util::create_dir_if_needed(g_dir + "/origine");
  file_util::create_dir_if_needed(g_dir + "/recharged");
  std::printf("REFSET mode=%s dir=%s steps=%d res=%dx%d\n", g_mode == 1 ? "capture" : "replay",
              g_dir.c_str(), (int)g_steps.size(), kShotW, kShotH);
  std::fflush(stdout);
  return true;
}

int tod_override_x100() {
  return g_tod_x100;
}

void set_logic_frame_provider(int64_t (*fn)()) {
  g_logic_fn = fn;
}

int64_t current_logic_frame() {
  return g_logic_fn ? g_logic_fn() : -1;
}

void note_anchor() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const int64_t lf = current_logic_frame();
  if (g_warp1 < 0) {
    g_warp1 = lf;
    std::printf("REFSET warp1 lf=%lld (le plan demarre dans %lld images)\n", (long long)lf,
                (long long)kAnchorSettle);
    std::fflush(stdout);
    return;
  }
  g_rewarps++;
  g_rewarp_asked = false;
  if (g_cap == kCapWaitWarp) {
    g_step_anchor = lf;
    g_capture_frame = lf + g_step_settle;
    g_cap = kCapArmed;
  }
}

bool wants_rewarp() {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapWaitWarp || g_warp1 < 0) {
    return false;
  }
  const int64_t lf = current_logic_frame();
  if (g_rewarp_asked) {
    // Le slot `*listener-function*` est partage : une demande peut etre ecrasee avant que le
    // noyau ne la lance. Sans ce re-armement l'etape resterait bloquee pour toujours, et la
    // porte rendrait 254 sans dire pourquoi.
    if (lf < g_rewarp_asked_lf + 300) {
      return false;
    }
  }
  g_rewarp_asked = true;
  g_rewarp_asked_lf = lf;
  return true;
}

void tick() {
  if (!enabled()) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  // AVANT tout retour anticipe : l'alpha brut s'echantillonne sur TOUTE la course, y compris
  // le chargement. Le poser apres les gardes ci-dessous ne mesurerait que les images du plan.
  {
    const int64_t raw = (int64_t)render_pace::raw_alpha_micro();
    if (raw < g_raw_alpha_min) {
      g_raw_alpha_min = raw;
    }
    if (raw > g_raw_alpha_max) {
      g_raw_alpha_max = raw;
    }
    g_raw_alpha_n++;
  }
  if (g_warp1 < 0 || g_finished) {
    return;
  }
  const int64_t lf = current_logic_frame();
  if (lf < 0 || lf < g_warp1 + kAnchorSettle) {
    return;
  }

  if (g_cap == kCapDone) {
    g_cap = kCapIdle;
    g_cur++;
    if (g_cur >= g_steps.size()) {
      g_finished = true;
      lighting_census::set_phase(0);
      g_tod_x100 = -1;
      publish_state();
      std::printf("REFSET done steps=%d captured=%llu compared=%llu maxdiff=%llu diffpx=%llu "
                  "missing=%llu slip=%lld..%lld rewarps=%llu settle=%lld\n",
                  (int)g_steps.size(), (unsigned long long)g_captured,
                  (unsigned long long)g_compared, (unsigned long long)g_maxdiff,
                  (unsigned long long)g_diffpx, (unsigned long long)g_missing,
                  (long long)g_frame_slip_min, (long long)g_frame_slip_max,
                  (unsigned long long)g_rewarps, (long long)g_step_settle);
      std::fflush(stdout);
      return;
    }
  }

  if (g_cap == kCapIdle) {
    // La configuration est posee AVANT le teleport : l'heure et le master sont donc deja ceux de
    // l'etape quand la camera se repose.
    const Step& st = g_steps[g_cur];
    apply_step_config(st);
    char nm[64];
    std::snprintf(nm, sizeof(nm), "%s/h%02d", set_name(st.phase), st.hour);
    g_capture_name = nm;
    g_cap = kCapWaitWarp;
    if (g_cur == 0) {
      std::printf("REFSET start lf=%lld warp1=%lld settle=%lld\n", (long long)lf,
                  (long long)g_warp1, (long long)g_step_settle);
      std::fflush(stdout);
    }
  }
  publish_state();
}

bool capture_for_chain(int64_t lf, char* name_out, int name_cap, int* w, int* h) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapArmed || lf < g_capture_frame) {
    return false;
  }
  // `lf > g_capture_frame` veut dire qu'une chaine a saute : on le MESURE au lieu de l'ignorer,
  // parce qu'un decalage d'une frame de logique suffit a faire mentir la comparaison.
  // Le decalage entre la frame de logique DEMANDEE et celle que porte la chaine rendue. Il est
  // constant par construction (l'ordre des appels dans une image de GOAL est fixe) ; ce qui
  // serait dangereux, c'est qu'il VARIE. On publie donc le min ET le max : `slip_min ==
  // slip_max` est la preuve que l'appariement est stable, un intervalle ouvert dit que non.
  const int64_t slip = lf - g_capture_frame;
  if (slip > g_frame_slip_max) {
    g_frame_slip_max = slip;
  }
  if (slip < g_frame_slip_min) {
    g_frame_slip_min = slip;
  }
  // Desarmer ICI, pas a la fin de la capture : entre les deux, le fil graphique dessine une ou
  // deux images de plus et re-prendrait la meme demande.
  g_cap = kCapInFlight;
  std::snprintf(name_out, name_cap, "%s", g_capture_name.c_str());
  *w = kShotW;
  *h = kShotH;
  return true;
}

bool consume_capture(int w, int h, const void* rgba) {
  if (!enabled()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_cap != kCapInFlight) {
    return false;
  }
  const std::string path = image_path(g_capture_name);
  const int n_px = w * h;
  const uint8_t* cur = (const uint8_t*)rgba;

  if (g_mode == 1) {
    file_util::write_rgba_png(path, const_cast<void*>(rgba), w, h);
    g_captured++;
    std::printf("REFSET cap %s step=%d/%d\n", g_capture_name.c_str(), (int)g_cur,
                (int)g_steps.size());
    std::fflush(stdout);
    // Un chemin n'est pas une preuve : on relit tout de suite ce qu'on vient d'ecrire et on
    // verifie que l'aller-retour PNG est exact. Sinon la reference ne vaut rien et personne ne
    // le saurait avant l'item suivant.
    std::vector<uint8_t> back;
    uint32_t bw = 0, bh = 0, bc = 0;
    if (fpng::fpng_decode_file(path.c_str(), back, bw, bh, bc, 4) != 0 || (int)bw != w ||
        (int)bh != h) {
      g_roundtrip_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, back.data(), n_px, &md, &np);
      if (md != 0) {
        g_roundtrip_bad++;
      }
    }
  } else {
    std::vector<uint8_t> ref;
    uint32_t rw = 0, rh = 0, rc = 0;
    const int rc_dec = fpng::fpng_decode_file(path.c_str(), ref, rw, rh, rc, 4);
    if (rc_dec == fpng::FPNG_DECODE_FILE_OPEN_FAILED) {
      g_missing++;
      std::printf("REFSET missing %s\n", path.c_str());
      std::fflush(stdout);
    } else if (rc_dec != 0) {
      g_decode_bad++;
    } else if ((int)rw != w || (int)rh != h) {
      g_size_bad++;
    } else {
      uint64_t md = 0, np = 0;
      compare(cur, ref.data(), n_px, &md, &np);
      g_compared++;
      if (md > g_maxdiff) {
        g_maxdiff = md;
      }
      g_diffpx += np;
      char key[96];
      std::snprintf(key, sizeof(key), "refset_d_%s_h%02d",
                    set_name(g_steps[g_cur].phase), g_steps[g_cur].hour);
      autoport_proof::publish(key, md);
      std::printf("REFSET cmp %s maxdiff=%llu diffpx=%llu\n", g_capture_name.c_str(),
                  (unsigned long long)md, (unsigned long long)np);
      std::fflush(stdout);
      if (md != 0) {
        // L'image REELLE d'un ecart est ecrite a cote de la preuve pour que l'ecart soit
        // localisable hors ligne. Elle ne prouve rien : c'est le nombre qui prouve.
        const std::string out = ".autoport/reports/lighting-census/refset-actual";
        file_util::create_dir_if_needed(out);
        file_util::write_rgba_png(out + "/" + set_name(g_steps[g_cur].phase) + "-h" +
                                      (g_steps[g_cur].hour < 10 ? "0" : "") +
                                      std::to_string(g_steps[g_cur].hour) + ".png",
                                  const_cast<void*>(rgba), w, h);
      }
    }
  }

  g_cap = kCapDone;
  publish_state();
  return true;
}

}  // namespace refset
