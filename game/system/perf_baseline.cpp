#include "game/system/perf_baseline.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "game/graphics/fixed_tick.h"
#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/render_pace.h"
#include "game/system/autoport_proof.h"
#include "game/system/perf_instruments.h"

namespace perf_baseline {
namespace {

constexpr const char* kItemId = "perf-stock-baseline";

// ── LES VANTAGES ────────────────────────────────────────────────────────────────────────────
// `cont` est le nom du continue-point tel qu'il existe dans level-info.gc — `beach` et
// `jungle` n'y existent NI comme continue NI comme vantage, les points reels sont
// `beach-start` (level-info.gc:295) et `jungle-start` (:348). `key` est l'etiquette courte qui
// compose les cles publiees : `autoport_proof` refuse un `-` en silence, d'ou l'underscore.
// `pos` vide = on ne pousse RIEN et le continue-point garde sa position d'origine ; pousser
// « 0 0 0 » teleporterait a l'origine du monde.
struct Vantage {
  const char* key;
  const char* cont;
  const char* pos;
};
constexpr Vantage kVantages[] = {
    {"village1_hut", "village1-hut", "-116 14 40"},
    {"beach", "beach-start", ""},
    {"jungle", "jungle-start", ""},
};
constexpr int kVantageCount = (int)(sizeof(kVantages) / sizeof(kVantages[0]));

// LE VANTAGE 0 NE SE TELEPORTE PAS DEPUIS ICI. Le premier teleport est pose par le harnais
// (`debug.opengoal.level.warp` / `OG_LEVEL_WARP`) et execute par `level_warp_maybe`, verrouillee
// par son `static bool s_done` : la campagne DEMARRE sur le vantage 0. Elle ne depense donc que
// DEUX `(start 'play ...)`, un par vantage restant. Ce n'est pas une economie de style : le jeu
// de references meurt en SIGILL au 4e `(start 'play)` (trois courses appareil du 2026-09-08,
// `A36-TREE` puis signal 4) parce qu'il double-teleporte a chaque vantage. Aucun teleport « de
// confort », aucun re-warp de recalage.
constexpr int kFirstWarpVantage = 1;

constexpr int kMaxScales = 8;
constexpr int kMaxSamples = 600;
constexpr size_t kMinPercentileSamples = 30;

// PLAFOND DE L'ATTENTE D'AMORCAGE, ET IL N'OUVRE AUCUNE CELLULE. `kBoot` attend des acteurs ;
// si le teleport pose par le harnais n'a pas abouti, le jeu est reste a l'ecran-titre. Mesurer
// la en etiquetant les cellules `village1_hut` rendrait 15 lignes vertes sur une mesure qui ne
// decrit rien. Au-dela de ce plafond on PUBLIE le motif (`base_boot_timeout=1`, le dernier
// compte d'acteurs vu) et on RESTE dans `kBoot` : la porte doit rester rouge.
constexpr uint64_t kBootMaxFrames = 6000;

// Bornes de temps : une cellule a 3 img/s ne doit pas manger toute la course. Une fenetre se
// ferme sur son compte d'images OU sur sa borne de temps, la premiere atteinte.
constexpr double kMeasureMaxSeconds = 20.0;
constexpr double kWarmupMaxSeconds = 5.0;
constexpr double kSettleMaxSeconds = 45.0;

enum State {
  kBoot = 0,
  kSettle,
  kWarmup,
  kMeasure,
  kWarp,
  kDone,
};

// ── reglage ─────────────────────────────────────────────────────────────────────────────────
// `OG_PERF_BASELINE` / `debug.opengoal.perf.baseline` =
//   <basew>x<baseh>[:<s1,s2,...>][@<measure>/<warmup>/<settle>]
// Defaut : 2400x1080:25,40,60,80,100@240/60/600
int g_base_w = 2400;
int g_base_h = 1080;
int g_scales[kMaxScales] = {25, 40, 60, 80, 100};
int g_scale_count = 5;
int g_measure_frames = 240;
int g_warmup_frames = 60;
int g_settle_frames = 600;

std::atomic<int> g_enabled{-1};  // -1 jamais evalue, 0 eteint, 1 allume
bool g_config_parsed = false;

// Le reglage, tel quel. "" = absent (l'item est alors arme par `AUTOPORT_FEATURE` seul et les
// defauts ci-dessus s'appliquent).
bool read_knob(char* out, size_t cap) {
  out[0] = 0;
  if (const char* e = std::getenv("OG_PERF_BASELINE")) {
    if (e[0]) {
      std::snprintf(out, cap, "%s", e);
      return true;
    }
  }
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.perf.baseline", buf) > 0 && buf[0]) {
    std::snprintf(out, cap, "%s", buf);
    return true;
  }
#endif
  return false;
}

void parse_config(const char* spec) {
  if (g_config_parsed) {
    return;
  }
  g_config_parsed = true;
  if (!spec || !spec[0]) {
    return;
  }
  int w = 0, h = 0;
  const char* p = spec;
  if (std::sscanf(p, "%dx%d", &w, &h) == 2 && w >= 64 && h >= 64 && w <= 8192 && h <= 8192) {
    g_base_w = w;
    g_base_h = h;
  }
  if (const char* colon = std::strchr(p, ':')) {
    int n = 0;
    const char* q = colon + 1;
    while (*q && *q != '@' && n < kMaxScales) {
      char* end = nullptr;
      long v = std::strtol(q, &end, 10);
      if (end == q) {
        break;
      }
      if (v >= 5 && v <= 400) {
        g_scales[n++] = (int)v;
      }
      q = end;
      if (*q == ',') {
        q++;
      } else {
        break;
      }
    }
    if (n > 0) {
      g_scale_count = n;
    }
  }
  if (const char* at = std::strchr(p, '@')) {
    int m = 0, wu = 0, st = 0;
    if (std::sscanf(at + 1, "%d/%d/%d", &m, &wu, &st) == 3) {
      // Bornes dures : au-dela, une seule cellule mange la course entiere.
      g_measure_frames = std::max(30, std::min(600, m));
      g_warmup_frames = std::max(0, std::min(600, wu));
      g_settle_frames = std::max(0, std::min(1200, st));
    }
  }
}

void evaluate_enabled() {
  char knob[160];
  const bool has_knob = read_knob(knob, sizeof(knob));
  const bool on =
      autoport_proof::armed_for(kItemId) && (autoport_proof::feature_is(kItemId) || has_knob);
  if (on && has_knob) {
    parse_config(knob);
  }
  g_enabled.store(on ? 1 : 0, std::memory_order_relaxed);
}

inline int64_t now_ns() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// ── etat traversant les fils ────────────────────────────────────────────────────────────────
// La resolution imposee : ecrite par le fil GL a l'entree d'une cellule, lue par le fil GOAL a
// chaque image dans `pc_set_game_resolution`. Trois entiers independants suffisent : une image
// ecrite avec la largeur de la cellule N et la hauteur de la cellule N+1 n'existe pas ici (les
// deux sont poses ensemble, hors mesure, pendant le WARMUP qui suit).
std::atomic<int> g_res_w{0};
std::atomic<int> g_res_h{0};
std::atomic<bool> g_res_active{false};
std::atomic<uint64_t> g_autoscale_overrides{0};
std::atomic<int> g_autoscale_goal_w_last{0};

// La demande de teleport : un couple de CHAINES, donc un mutex et pas un atomique. Pose par le
// fil GL (machine a etats), consomme par le fil GOAL (`pc_autoport_frame`).
std::mutex g_warp_mutex;
bool g_warp_pending = false;
char g_warp_name[64] = {0};
char g_warp_pos[64] = {0};
char g_warp_pos_current[64] = {0};  // ecrit et lu par le fil GOAL seul, sous le meme mutex
std::atomic<uint64_t> g_warp_taken{0};
std::atomic<uint64_t> g_warp_requested{0};

// ── etat de la machine (fil GL uniquement) ──────────────────────────────────────────────────
int g_state = kBoot;
int g_vantage = 0;
int g_scale_idx = 0;
uint64_t g_state_frames = 0;
int64_t g_state_t0 = 0;
uint64_t g_boot_streak = 0;
uint64_t g_frames_total = 0;
uint64_t g_warp_target = 0;
uint64_t g_warp_consumed_at = 0;
uint64_t g_cells_done = 0;
uint64_t g_metrics_missing = 0;
bool g_witness_done = false;
bool g_boot_timeout = false;
bool g_done_published = false;

int64_t g_last_frame_ns = 0;
std::vector<float> g_samples;
double g_gl_cpu_sum = 0;
uint64_t g_gl_cpu_n = 0;
uint64_t g_gpu_ns_at_entry = 0;
uint64_t g_gpu_frames_at_entry = 0;
bool g_gpu_ok_at_entry = false;

inline double state_seconds() {
  return (double)(now_ns() - g_state_t0) / 1.0e9;
}

void enter_state(int s) {
  g_state = s;
  g_state_frames = 0;
  g_state_t0 = now_ns();
}

// ── publication ─────────────────────────────────────────────────────────────────────────────
void cell_key(char* out, size_t cap, int vantage, int scale_idx, const char* suffix) {
  std::snprintf(out, cap, "base_%s_s%d_%s", kVantages[vantage].key, g_scales[scale_idx], suffix);
}

int host_render_scale_pct() {
#if defined(__ANDROID__)
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get("debug.opengoal.render.scale", buf) > 0 && buf[0]) {
    const int v = std::atoi(buf);
    if (v >= 25 && v <= 400) {
      return v;
    }
  }
#endif
  return 100;
}

// Les temoins de REGIME. Un chiffre de cadence sans le regime qui l'a produit n'est pas une
// mesure : une cellule mesuree avec le pas fixe arme, la synchro verticale coupee ou le pack
// Recharged allume ne se compare pas a une autre. Relus a chaque fermeture de cellule — la
// derniere valeur gagne — parce qu'ils sont poses par GOAL bien apres le boot.
void publish_witnesses() {
  char v[64];
  std::snprintf(v, sizeof(v), "%dx%d", g_base_w, g_base_h);
  autoport_proof::publish_text("base_game_size", v);
  std::string scales;
  for (int i = 0; i < g_scale_count; i++) {
    if (!scales.empty()) {
      scales += ",";
    }
    scales += std::to_string(g_scales[i]);
  }
  autoport_proof::publish_text("base_scales", scales.c_str());
#if defined(__ANDROID__)
  autoport_proof::publish_text("base_source", "android");
#else
  autoport_proof::publish_text("base_source", "x86");
#endif
  uint64_t gpu_ns = 0, gpu_frames = 0;
  autoport_proof::publish("base_gpu_timer_supported",
                          lighting_census::gpu_frame_totals(&gpu_ns, &gpu_frames) ? 1 : 0);
  autoport_proof::publish("base_autoscale_overrides",
                          g_autoscale_overrides.load(std::memory_order_relaxed));
  autoport_proof::publish("base_autoscale_goal_w_last",
                          (uint64_t)std::max(0, g_autoscale_goal_w_last.load(
                                                    std::memory_order_relaxed)));
  // LE MAITRE EFFECTIF, PAS LE REGLAGE. `OG_RECHARGED` / `debug.opengoal.recharged` surchargent
  // ce que settings.ini porte, et c'est la surcharge que le rendu lit. Mesure du 2026-09-10 :
  // le journal disait « [recharged-master] override -> 0 (setting ON) » pendant que ce temoin
  // publiait 1 — la table entiere aurait porte la mauvaise etiquette de regime. On publie donc
  // LES DEUX : sans le reglage, une surcharge qui cesserait de mordre ressemblerait a un
  // reglage ; sans l'effectif, le reglage ressemble au regime.
  autoport_proof::publish("base_recharged", Gfx::recharged_master_active() ? 1 : 0);
  autoport_proof::publish("base_recharged_setting",
                          Gfx::g_global_settings.recharged_master ? 1 : 0);
  autoport_proof::publish("base_fixed_tick", fixed_tick::enabled() ? 1 : 0);
  autoport_proof::publish("base_vsync", Gfx::g_global_settings.vsync ? 1 : 0);
  std::snprintf(v, sizeof(v), "%.1f", (double)Gfx::g_global_settings.display_fps_cap);
  autoport_proof::publish_text("base_frame_cap", v);
  // Le plafond que GOAL a REGLE n'est pas forcement celui que le limiteur TIENT :
  // `OG_FRAME_LIMIT_FPS` / `debug.opengoal.frame.limit` deplacent la cible du limiteur seul.
  // Accesseur en LECTURE PURE (`stimulus_fps` ecrirait le segment courant sous le module qui
  // le mesure). 0 = aucun balayage demande, et alors `base_frame_cap` est bien l'effectif.
  std::snprintf(v, sizeof(v), "%.1f", render_pace::stimulus_segment_fps());
  autoport_proof::publish_text("base_frame_cap_stimulus", v);
  autoport_proof::publish("base_render_scale_pct_host", (uint64_t)host_render_scale_pct());
  autoport_proof::publish("base_perf_instruments_enabled", perf_instruments::enabled() ? 1 : 0);
  autoport_proof::publish("base_warps_requested", g_warp_requested.load(std::memory_order_relaxed));
  // Les deux temoins de l'amorcage. `base_perf_instruments_enabled=0` avec
  // `base_boot_actors_last=0` NOMME la panne : sans le knob `perf.buckets=1`, `actors_active`
  // reste a zero pour toujours et la campagne ne quitterait jamais `kBoot` en silence.
  autoport_proof::publish("base_boot_timeout", g_boot_timeout ? 1 : 0);
  autoport_proof::publish("base_boot_actors_last", perf_instruments::snapshot().actors_active);
}

// LE COMPTE DE CE QUI MANQUE SE LIT DANS LA TABLE QUI SERA MOISSONNEE, jamais dans une variable
// interne : c'est elle qui fait foi, et une cellule « publiee » dont la cle a ete refusee
// (caractere illegal, valeur avec un blanc) doit se voir.
void publish_totals() {
  const int expected = kVantageCount * g_scale_count;
  autoport_proof::publish("perf_baseline_expected", (uint64_t)expected);
  uint64_t missing = 0;
  std::string missing_cells;
  char key[96];
  for (int v = 0; v < kVantageCount; v++) {
    for (int s = 0; s < g_scale_count; s++) {
      cell_key(key, sizeof(key), v, s, "frame_ms_p50");
      if (!autoport_proof::has_key(key)) {
        missing++;
        if (missing_cells.size() < 220) {
          if (!missing_cells.empty()) {
            missing_cells += ",";
          }
          missing_cells += kVantages[v].key;
          missing_cells += "_s";
          missing_cells += std::to_string(g_scales[s]);
        }
      }
    }
  }
  autoport_proof::publish("perf_baseline_missing", missing);
  autoport_proof::publish_text("perf_baseline_missing_cells",
                               missing_cells.empty() ? "none" : missing_cells.c_str());
  autoport_proof::publish("perf_baseline_metrics_missing", g_metrics_missing);
  // `hits` est un compteur GLOBAL et PARTAGE : la campagne tient le sien.
  autoport_proof::publish("perf_baseline_cells_done", g_cells_done);
}

void close_cell() {
  const int v = g_vantage;
  const int s = g_scale_idx;
  char key[96];
  char val[48];

  std::sort(g_samples.begin(), g_samples.end());
  const size_t n = g_samples.size();
  if (n >= kMinPercentileSamples) {
    const size_t i50 = n / 2;
    size_t i95 = (n * 95) / 100;
    if (i95 >= n) {
      i95 = n - 1;
    }
    cell_key(key, sizeof(key), v, s, "frame_ms_p50");
    std::snprintf(val, sizeof(val), "%.3f", (double)g_samples[i50]);
    autoport_proof::publish_text(key, val);
    cell_key(key, sizeof(key), v, s, "frame_ms_p95");
    std::snprintf(val, sizeof(val), "%.3f", (double)g_samples[i95]);
    autoport_proof::publish_text(key, val);
  }
  cell_key(key, sizeof(key), v, s, "frames");
  autoport_proof::publish(key, (uint64_t)n);

  // `goal_busy_ms` et `actors_active` sont deja des moyennes glissantes de 60 images cote
  // perf_instruments : on les echantillonne a la FERMETURE, pas image par image.
  const perf_instruments::Snapshot snap = perf_instruments::snapshot();
  cell_key(key, sizeof(key), v, s, "goal_busy_ms");
  std::snprintf(val, sizeof(val), "%.3f", snap.busy_ms);
  autoport_proof::publish_text(key, val);
  cell_key(key, sizeof(key), v, s, "actors_active");
  autoport_proof::publish(key, snap.actors_active);

  cell_key(key, sizeof(key), v, s, "gl_cpu_ms");
  std::snprintf(val, sizeof(val), "%.3f",
                g_gl_cpu_n ? (g_gl_cpu_sum / (double)g_gl_cpu_n) : 0.0);
  autoport_proof::publish_text(key, val);

  // Le temps GPU se lit PAR DELTA : `lighting_census` cumule et ne remet jamais a zero, et
  // d'autres modules lisent le meme cumul. Cle ABSENTE quand le timer n'est pas supporte —
  // un zero sans son pourquoi serait une fausse constante.
  uint64_t gpu_ns = 0, gpu_frames = 0;
  if (g_gpu_ok_at_entry && lighting_census::gpu_frame_totals(&gpu_ns, &gpu_frames) &&
      gpu_frames > g_gpu_frames_at_entry && gpu_ns >= g_gpu_ns_at_entry) {
    const double d_ns = (double)(gpu_ns - g_gpu_ns_at_entry);
    const double d_frames = (double)(gpu_frames - g_gpu_frames_at_entry);
    cell_key(key, sizeof(key), v, s, "gpu_ms_total");
    std::snprintf(val, sizeof(val), "%.4f", d_ns / d_frames / 1.0e6);
    autoport_proof::publish_text(key, val);
  }

  cell_key(key, sizeof(key), v, s, "res");
  std::snprintf(val, sizeof(val), "%dx%d", g_res_w.load(std::memory_order_relaxed),
                g_res_h.load(std::memory_order_relaxed));
  autoport_proof::publish_text(key, val);

  // Les cles de metrique ABSENTES de cette cellule, comptees dans la table de publication.
  static const char* const kMetrics[] = {"frame_ms_p50", "frame_ms_p95", "goal_busy_ms",
                                         "gl_cpu_ms",    "actors_active", "frames",
                                         "res"};
  for (const char* m : kMetrics) {
    cell_key(key, sizeof(key), v, s, m);
    if (!autoport_proof::has_key(key)) {
      g_metrics_missing++;
    }
  }
  if (g_gpu_ok_at_entry) {
    cell_key(key, sizeof(key), v, s, "gpu_ms_total");
    if (!autoport_proof::has_key(key)) {
      g_metrics_missing++;
    }
  }

  g_cells_done++;
  publish_witnesses();
  publish_totals();
}

void post_warp_request(int vantage) {
  {
    std::lock_guard<std::mutex> lock(g_warp_mutex);
    std::snprintf(g_warp_name, sizeof(g_warp_name), "%s", kVantages[vantage].cont);
    std::snprintf(g_warp_pos, sizeof(g_warp_pos), "%s", kVantages[vantage].pos);
    g_warp_pending = true;
  }
  g_warp_target = g_warp_taken.load(std::memory_order_relaxed) + 1;
  g_warp_requested.fetch_add(1, std::memory_order_relaxed);
  // Publie DES LA DEMANDE, pas a la fin : si la course meurt au teleport, la derniere valeur
  // moissonnee dit lequel.
  autoport_proof::publish("base_warps_requested",
                          g_warp_requested.load(std::memory_order_relaxed));
  printf("PERF-BASELINE warp request vantage=%s cont=%s\n", kVantages[vantage].key,
         kVantages[vantage].cont);
  fflush(stdout);
}

void begin_cell_scale() {
  const int s = g_scales[g_scale_idx];
  g_res_w.store(std::max(64, g_base_w * s / 100), std::memory_order_relaxed);
  g_res_h.store(std::max(64, g_base_h * s / 100), std::memory_order_relaxed);
  g_res_active.store(true, std::memory_order_relaxed);
  printf("PERF-BASELINE cell vantage=%s scale=%d res=%dx%d\n", kVantages[g_vantage].key, s,
         g_res_w.load(std::memory_order_relaxed), g_res_h.load(std::memory_order_relaxed));
  fflush(stdout);
  enter_state(kWarmup);
}

void begin_measure() {
  // Une seule reservation par cellule, jamais une allocation par image.
  g_samples.clear();
  g_samples.reserve(kMaxSamples);
  g_gl_cpu_sum = 0;
  g_gl_cpu_n = 0;
  g_gpu_ns_at_entry = 0;
  g_gpu_frames_at_entry = 0;
  g_gpu_ok_at_entry = lighting_census::gpu_frame_totals(&g_gpu_ns_at_entry, &g_gpu_frames_at_entry);
  enter_state(kMeasure);
}

void advance_after_cell() {
  g_scale_idx++;
  if (g_scale_idx < g_scale_count) {
    begin_cell_scale();
    return;
  }
  g_scale_idx = 0;
  g_vantage++;
  if (g_vantage >= kVantageCount) {
    g_res_active.store(false, std::memory_order_relaxed);
    enter_state(kDone);
    return;
  }
  // Le vantage 0 est celui ou le harnais nous a deja deposes : seuls les suivants coutent un
  // `(start 'play ...)`.
  if (g_vantage >= kFirstWarpVantage) {
    g_res_active.store(false, std::memory_order_relaxed);
    post_warp_request(g_vantage);
    enter_state(kWarp);
    return;
  }
  enter_state(kSettle);
}

}  // namespace

bool enabled() {
  int v = g_enabled.load(std::memory_order_relaxed);
  if (v < 0) {
    evaluate_enabled();
    v = g_enabled.load(std::memory_order_relaxed);
  }
  return v == 1;
}

bool resolution_override(int* w, int* h) {
  if (!enabled() || !w || !h) {
    return false;
  }
  if (!g_res_active.load(std::memory_order_relaxed)) {
    return false;
  }
  const int cw = g_res_w.load(std::memory_order_relaxed);
  const int ch = g_res_h.load(std::memory_order_relaxed);
  if (cw <= 0 || ch <= 0) {
    return false;
  }
  // CE QUE LE CONTROLEUR GOAL DEMANDAIT, et combien de fois sa decision a ete jetee : sans ces
  // deux temoins, « la campagne impose l'echelle » ne se distingue pas de « la fonction n'a
  // jamais ete appelee ».
  g_autoscale_goal_w_last.store(*w, std::memory_order_relaxed);
  g_autoscale_overrides.fetch_add(1, std::memory_order_relaxed);
  *w = cw;
  *h = ch;
  return true;
}

bool take_warp_request(char* name, size_t ncap, char* pos, size_t pcap) {
  if (!enabled() || !name || !pos || ncap == 0 || pcap == 0) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_warp_mutex);
  if (!g_warp_pending) {
    return false;
  }
  g_warp_pending = false;
  std::snprintf(name, ncap, "%s", g_warp_name);
  std::snprintf(pos, pcap, "%s", g_warp_pos);
  std::snprintf(g_warp_pos_current, sizeof(g_warp_pos_current), "%s", g_warp_pos);
  g_warp_taken.fetch_add(1, std::memory_order_relaxed);
  return true;
}

const char* warp_pos_override() {
  if (!enabled()) {
    return "";
  }
  std::lock_guard<std::mutex> lock(g_warp_mutex);
  return g_warp_pos_current;
}

void note_drawn_frame(double gl_cpu_ms) {
  g_frames_total++;
  // Le reglage peut etre pose (propriete) apres le boot : relu periodiquement, comme
  // perf_instruments, pour ne pas figer un etat lu trop tot.
  if (g_frames_total % 240 == 1) {
    evaluate_enabled();
  }
  if (!enabled()) {
    return;
  }
  // DES LA PREMIERE IMAGE ARMEE, quel que soit l'etat : une campagne qui reste bloquee en
  // amorcage doit publier POURQUOI, pas un proof vide. Les valeurs sont relues plus tard, la
  // derniere gagne (regle de moissonnage de proof_run.sh).
  if (!g_witness_done) {
    g_witness_done = true;
    publish_witnesses();
    publish_totals();
  }
  const int64_t t = now_ns();
  const int64_t prev = g_last_frame_ns;
  g_last_frame_ns = t;
  g_state_frames++;

  switch (g_state) {
    case kBoot: {
      // L'ECRAN DE CHARGEMENT N'A PAS D'ACTEURS. On attend que le teleport pose par le harnais
      // ait vraiment abouti : 30 images consecutives avec au moins un acteur qui a couru.
      if (perf_instruments::snapshot().actors_active > 0) {
        g_boot_streak++;
      } else {
        g_boot_streak = 0;
      }
      if (g_boot_streak >= 30) {
        publish_witnesses();
        publish_totals();
        enter_state(kSettle);
        return;
      }
      if (g_state_frames > kBootMaxFrames && !g_boot_timeout) {
        g_boot_timeout = true;
        publish_witnesses();
        publish_totals();
        printf("PERF-BASELINE boot timeout frames=%llu actors=%llu\n",
               (unsigned long long)g_state_frames,
               (unsigned long long)perf_instruments::snapshot().actors_active);
        fflush(stdout);
      }
      return;
    }
    case kSettle: {
      if (g_state_frames >= (uint64_t)g_settle_frames || state_seconds() >= kSettleMaxSeconds) {
        begin_cell_scale();
      }
      return;
    }
    case kWarmup: {
      if (g_state_frames >= (uint64_t)g_warmup_frames || state_seconds() >= kWarmupMaxSeconds) {
        begin_measure();
      }
      return;
    }
    case kMeasure: {
      if (prev > 0 && t > prev && g_samples.size() < (size_t)kMaxSamples) {
        g_samples.push_back((float)((double)(t - prev) / 1.0e6));
      }
      if (gl_cpu_ms > 0.0) {
        g_gl_cpu_sum += gl_cpu_ms;
        g_gl_cpu_n++;
      }
      if (g_state_frames >= (uint64_t)g_measure_frames || state_seconds() >= kMeasureMaxSeconds) {
        close_cell();
        advance_after_cell();
      }
      return;
    }
    case kWarp: {
      if (g_warp_taken.load(std::memory_order_relaxed) < g_warp_target) {
        return;
      }
      // Consomme : les 60 images se comptent A PARTIR DE LA CONSOMMATION, pas de l'entree dans
      // l'etat — le fil GOAL peut mettre plusieurs images a venir prendre la demande.
      if (g_warp_consumed_at == 0) {
        g_warp_consumed_at = g_state_frames;
      }
      if (g_state_frames - g_warp_consumed_at >= 60) {
        g_warp_consumed_at = 0;
        enter_state(kSettle);
      }
      return;
    }
    case kDone:
    default: {
      if (!g_done_published) {
        g_done_published = true;
        publish_witnesses();
        publish_totals();
        printf("PERF-BASELINE done cells=%llu\n", (unsigned long long)g_cells_done);
        fflush(stdout);
      }
      return;
    }
  }
}

}  // namespace perf_baseline
