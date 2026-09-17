#include "game/system/grass_cull.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "game/graphics/grass_density_presets.h"
#include "game/system/autoport_proof.h"

namespace grass_cull {
namespace {

constexpr const char* kItemId = "grass-chunk-cull";

// LE SITE EST DECLARE AU CHARGEMENT, pas a l'execution : c'est ce qui separe « aucun site de cet
// item n'est compile ici » de « le site existe et la course ne l'a pas atteint ».
AUTOPORT_FEATURE_SITE(kItemId);

// ── Le plan de course ────────────────────────────────────────────────────────────────────────
// Trois vues. La vue 0 est la camera du jeu telle quelle et porte les jambes LONGUES (cadence) ;
// les vues 1 et 2 tournent la camera de l'herbe et ne portent que le recensement et le cout
// processeur, ou la rotation ne fausse rien (voir l'en-tete).
constexpr int kViewCount = 3;
constexpr float kViewYawDeg[kViewCount] = {0.f, 120.f, 240.f};
constexpr int kBootFrames = 60;
constexpr int kAimFrames[kViewCount] = {45, 20, 20};
constexpr int kLegFrames[kViewCount] = {180, 60, 60};
// Le recensement tombe apres ce nombre d'images de jambe : assez tard pour que le regime soit
// pose, assez tot pour qu'il reste des images a chronometrer apres lui.
constexpr int kCensusAtFrame = 30;
constexpr int kMaxSamples = 256;

enum State { kBoot, kAim, kLegCull, kLegCtrl, kDone };

struct Leg {
  bool seen = false;
  double fps_x100 = 0;
  double prep_us_x10 = 0;
  double submit_us_x10 = 0;
  uint64_t draws = 0;
  uint64_t submitted = 0;
};

struct ViewResult {
  bool census_seen = false;
  uint64_t submitted = 0;
  uint64_t chunk_visible = 0;
  uint64_t offscreen = 0;
  uint64_t dropped_visible = 0;
  uint64_t ideal = 0;
  uint64_t chunks_kept = 0;
  uint64_t chunks_total = 0;
  float fwd[3] = {0.f, 0.f, 0.f};
  Leg cull, ctrl;
};

struct Samples {
  std::vector<double> dt_ms, prep, submit;
  uint64_t draws_sum = 0, submitted_last = 0, frames = 0;
  void clear() {
    dt_ms.clear();
    prep.clear();
    submit.clear();
    draws_sum = 0;
    submitted_last = 0;
    frames = 0;
  }
};

double median(std::vector<double>& v) {
  if (v.empty()) {
    return 0.0;
  }
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

// Etat global. TOUT ce qui suit ne vit que sur le fil GL, SAUF ce qui est atomique ci-dessous :
// les trois surcharges de regime tournent sur le fil GOAL (kmachine.cpp les appelle a chaque
// image), et le fil GOAL n'a le droit de lire que des atomiques.
std::atomic<int> g_enabled{-1};          // -1 = pas encore evalue, 0 = non, 1 = oui
std::atomic<bool> g_regime_active{true};  // faux des que la campagne est finie (etat kDone)
State g_state = kBoot;
int g_state_frames = 0;
int g_view = 0;

// ── LE TEMOIN DE PROGRESSION, PUBLIE MEME QUAND LA CAMPAGNE N'ABOUTIT PAS ────────────────────
// Essai 1 : les trois surcharges ci-dessous n'etaient appelees par PERSONNE. Sur l'appareil
// l'herbe est restee eteinte, `GrassRenderer::render` n'a jamais tourne, `note_frame` non plus,
// la machine a etats est restee a `kBoot` et `publish_all` n'a jamais ete atteint. La preuve ne
// portait alors AUCUNE cle de la campagne : muette, donc inexploitable — il a fallu relire le
// journal du moteur pour comprendre. Ces compteurs-ci sont publies depuis le fil GOAL, qui tourne
// que l'herbe soit dessinee ou non : une course qui n'aboutit pas NOMME desormais son blocage.
std::atomic<uint64_t> g_grass_overrides{0};
std::atomic<uint64_t> g_preset_overrides{0};
std::atomic<uint64_t> g_dists_overrides{0};
std::atomic<uint64_t> g_render_frames{0};
std::atomic<uint64_t> g_field_ready_frames{0};
std::atomic<int> g_state_pub{kBoot};
std::atomic<int> g_view_pub{0};
std::atomic<int> g_state_frames_pub{0};
std::atomic<int> g_published_pub{0};
Samples g_samples;
ViewResult g_res[kViewCount];
bool g_published = false;

uint64_t g_chunks = 0, g_inst_min = 0, g_inst_p50 = 0, g_inst_p90 = 0, g_inst_max = 0;
uint64_t g_chunk_mismatch = 0, g_field_instances = 0;
bool g_partition_seen = false, g_partition_from_file = false;
uint64_t g_uniform_lookups = 0;
uint64_t g_chunk_tests_total = 0;

std::chrono::steady_clock::time_point g_last_frame{};
bool g_last_frame_valid = false;

void enter(State s) {
  g_state = s;
  g_state_frames = 0;
  g_samples.clear();
  g_last_frame_valid = false;
  // Le fil GOAL ne lit que ceci : a `kDone` les surcharges se taisent et le reglage du joueur
  // reprend la main a l'image suivante.
  g_regime_active.store(s != kDone, std::memory_order_relaxed);
  g_state_pub.store((int)s, std::memory_order_relaxed);
  g_state_frames_pub.store(0, std::memory_order_relaxed);
}

void close_leg(Leg& leg) {
  leg.seen = g_samples.frames > 0;
  const double dt = median(g_samples.dt_ms);
  leg.fps_x100 = dt > 0.0 ? (100000.0 / dt) : 0.0;  // 1000/dt_ms images/s, x100
  leg.prep_us_x10 = median(g_samples.prep) * 10.0;
  leg.submit_us_x10 = median(g_samples.submit) * 10.0;
  leg.draws = g_samples.frames ? (g_samples.draws_sum / g_samples.frames) : 0;
  leg.submitted = g_samples.submitted_last;
}

void pub(const std::string& key, uint64_t v) {
  autoport_proof::publish(key.c_str(), v);
}

uint64_t rnd(double v) {
  if (!(v > 0.0)) {
    return 0;
  }
  return (uint64_t)(v + 0.5);
}

// LE VERDICT. Chaque terme est publie SEPAREMENT juste avant d'entrer dans la somme, et la somme
// relit `has_key` sur la table qui sera moissonnee — jamais ses propres variables. Une cle refusee
// en silence (caractere illegal, valeur a espace) doit se voir comme un manque, pas disparaitre.
void publish_all() {
  if (g_published) {
    return;
  }
  g_published = true;

  pub("grass_cull_views", kViewCount);
  pub("grass_cull_chunks", g_chunks);
  pub("grass_cull_chunk_inst_min", g_inst_min);
  pub("grass_cull_chunk_inst_p50", g_inst_p50);
  pub("grass_cull_chunk_inst_p90", g_inst_p90);
  pub("grass_cull_chunk_inst_max", g_inst_max);
  pub("grass_cull_chunk_mismatch", g_chunk_mismatch);
  pub("grass_cull_field_instances", g_field_instances);
  pub("grass_cull_uniform_driver_calls_per_frame", g_uniform_lookups);
  autoport_proof::publish_text("grass_cull_chunk_source",
                               g_partition_seen ? (g_partition_from_file ? "fichier" : "recalcule")
                                                : "absent");

  int views_measured = 0;
  uint64_t sum_gap = 0, sum_dropped = 0, sum_offscreen = 0, empty_views = 0;
  for (int v = 0; v < kViewCount; v++) {
    const ViewResult& r = g_res[v];
    const std::string p = "grass_cull_v" + std::to_string(v) + "_";
    pub(p + "yaw_mdeg", (uint64_t)(int64_t)std::lround(kViewYawDeg[v] * 1000.0));
    pub(p + "camera_rotated", v == 0 ? 0 : 1);
    pub(p + "census_seen", r.census_seen ? 1 : 0);
    pub(p + "submitted", r.submitted);
    pub(p + "chunk_visible", r.chunk_visible);
    pub(p + "offscreen", r.offscreen);
    pub(p + "dropped_visible", r.dropped_visible);
    pub(p + "ideal", r.ideal);
    pub(p + "chunks_kept", r.chunks_kept);
    pub(p + "chunks_total", r.chunks_total);
    // L'avant de la camera EFFECTIVE, signe compris : deux vues qui rendraient le meme triplet
    // seraient la meme vue, et le compte de trois serait un mensonge arithmetique.
    for (int k = 0; k < 3; k++) {
      const char* an[3] = {"fwd_x_x1000", "fwd_y_x1000", "fwd_z_x1000"};
      const int64_t q = (int64_t)std::lround(r.fwd[k] * 1000.0);
      autoport_proof::publish_text((p + an[k]).c_str(), std::to_string(q).c_str());
    }
    // L'ECART, DANS LES DEUX SENS, ET UN SEUL EST UN DEFAUT.
    //   `_offscreen`     : soumis SANS que l'oracle garde le lot -> du travail pour rien. PORTE.
    //   `_oracle_slack`  : garde par l'oracle sans etre soumis -> les 5 cm de marge que l'oracle
    //                      s'ajoute pour qu'une egalite flottante au bord d'un plan ne rougisse
    //                      pas la porte. Publie, jamais somme : le sommer reviendrait a exiger
    //                      que deux ecritures de la meme algebre tombent au bit pres.
    const uint64_t slack = r.chunk_visible > r.submitted ? r.chunk_visible - r.submitted : 0;
    const uint64_t gap = r.submitted >= r.chunk_visible ? r.submitted - r.chunk_visible
                                                        : r.chunk_visible - r.submitted;
    pub(p + "gap", gap);
    pub(p + "oracle_slack", slack);
    pub(p + "cull_fps_x100", rnd(r.cull.fps_x100));
    pub(p + "ctrl_fps_x100", rnd(r.ctrl.fps_x100));
    pub(p + "cull_prep_us_x10", rnd(r.cull.prep_us_x10));
    pub(p + "ctrl_prep_us_x10", rnd(r.ctrl.prep_us_x10));
    pub(p + "cull_submit_us_x10", rnd(r.cull.submit_us_x10));
    pub(p + "ctrl_submit_us_x10", rnd(r.ctrl.submit_us_x10));
    pub(p + "cull_draws", r.cull.draws);
    pub(p + "ctrl_draws", r.ctrl.draws);
    pub(p + "cull_submitted", r.cull.submitted);
    pub(p + "ctrl_submitted", r.ctrl.submitted);
    if (r.census_seen && r.submitted > 0) {
      views_measured++;
    } else if (r.census_seen) {
      empty_views++;
    }
    sum_gap += gap;
    (void)slack;
    sum_dropped += r.dropped_visible;
    sum_offscreen += r.offscreen;
  }
  pub("grass_cull_views_measured", (uint64_t)views_measured);
  pub("grass_cull_views_empty", empty_views);
  pub("grass_cull_sum_gap", sum_gap);
  pub("grass_cull_sum_dropped_visible", sum_dropped);
  pub("grass_cull_sum_offscreen", sum_offscreen);

  // CE QUI MANQUE, LU DANS LA TABLE MOISSONNEE. Une cle par vue et par grandeur du contrat.
  uint64_t missing = 0;
  static const char* kPerView[] = {"submitted", "chunk_visible", "offscreen", "dropped_visible",
                                   "gap",       "cull_draws",    "ctrl_draws"};
  for (int v = 0; v < kViewCount; v++) {
    const std::string p = "grass_cull_v" + std::to_string(v) + "_";
    for (const char* k : kPerView) {
      if (!autoport_proof::has_key((p + k).c_str())) {
        missing++;
      }
    }
  }
  for (const char* k : {"grass_cull_chunks", "grass_cull_chunk_mismatch",
                        "grass_cull_field_instances", "grass_cull_views_measured"}) {
    if (!autoport_proof::has_key(k)) {
      missing++;
    }
  }
  if (views_measured < kViewCount) {
    missing += (uint64_t)(kViewCount - views_measured);
  }
  if (!g_partition_seen || g_chunks == 0 || g_field_instances == 0) {
    missing++;
  }
  pub("grass_cull_missing_terms", missing);

  // Les invariants des plages sont publies par le renderer (il est le seul a les connaitre) ;
  // on les RELIT dans la table moissonnee pour les faire entrer dans la somme. Une cle absente
  // compte comme un manque : un chemin de dessin qui n'aurait jamais verifie son arithmetique ne
  // doit pas se lire comme un chemin verifie a zero.
  uint64_t run_viol = 0;
  if (!autoport_proof::read_uint("grass_cull_run_invariant_violations", run_viol)) {
    run_viol = 0;
    missing++;
    pub("grass_cull_missing_terms", missing);
  }

  // LA PORTE. Somme des termes ci-dessus, tous nuls quand le culling est correct et mesure.
  // `sum_gap` n'y entre PAS : il porte la marge deliberee de l'oracle (voir plus haut). Ce qui y
  // entre est ce qu'aucun culling correct ne peut produire — soumettre un lot hors du volume,
  // retirer une instance qui aurait dessine, une partition qui ne reproduit pas celle du fichier,
  // et une course qui n'aurait pas mesure ses trois vues.
  pub("grass_offscreen_submitted",
      sum_dropped + sum_offscreen + g_chunk_mismatch + missing + empty_views + run_viol);

  // `hits` = les lots TESTES par le culling sur toute la course (`hits_means` de l'item).
  autoport_proof::note_hit_for(kItemId, g_chunk_tests_total ? g_chunk_tests_total : 1);

  // Les memes cles de diagnostic que le temoin du fil GOAL, posees une derniere fois avec l'etat
  // final. Le temoin continue de battre apres `kDone` et republiera ces valeurs a l'identique.
  g_published_pub.store(1, std::memory_order_relaxed);
  g_state_pub.store((int)kDone, std::memory_order_relaxed);
  pub("grass_cull_grass_overrides", g_grass_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_preset_overrides", g_preset_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_dists_overrides", g_dists_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_render_frames", g_render_frames.load(std::memory_order_relaxed));
  pub("grass_cull_field_ready_frames", g_field_ready_frames.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_state", (uint64_t)kDone);
  pub("grass_cull_campaign_view", (uint64_t)g_view_pub.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_state_frames",
      (uint64_t)g_state_frames_pub.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_complete", 1);
}

// LE TEMOIN, POSE SUR LE FIL GOAL. Il ne lit que des atomiques et ne publie que des cles de
// DIAGNOSTIC : le verdict reste a `publish_all`, sur le fil GL. Deux publications par seconde
// environ (le fil GOAL tourne a la cadence du jeu) — un verrou de table, rien d'autre.
void heartbeat() {
  static std::atomic<uint64_t> ticks{0};
  if ((ticks.fetch_add(1, std::memory_order_relaxed) % 120) != 0) {
    return;
  }
  pub("grass_cull_grass_overrides", g_grass_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_preset_overrides", g_preset_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_dists_overrides", g_dists_overrides.load(std::memory_order_relaxed));
  pub("grass_cull_render_frames", g_render_frames.load(std::memory_order_relaxed));
  pub("grass_cull_field_ready_frames", g_field_ready_frames.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_state", (uint64_t)g_state_pub.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_view", (uint64_t)g_view_pub.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_state_frames",
      (uint64_t)g_state_frames_pub.load(std::memory_order_relaxed));
  pub("grass_cull_campaign_complete", (uint64_t)g_published_pub.load(std::memory_order_relaxed));
}

}  // namespace

bool enabled() {
  int v = g_enabled.load(std::memory_order_relaxed);
  if (v < 0) {
    v = (autoport_proof::armed_for(kItemId) && autoport_proof::feature_is(kItemId)) ? 1 : 0;
    g_enabled.store(v, std::memory_order_relaxed);
  }
  return v == 1;
}

// ── fil GOAL. LE REGIME SE POSE ICI OU IL NE SE POSE NULLE PART ──────────────────────────────
// `pc_set_recharged_grass` et `pc_set_grass_dists` (kmachine.cpp) repoussent le reglage du joueur
// a CHAQUE image ; c'est le seul point ou la campagne peut tenir le sien.
bool grass_on_override(bool* on) {
  if (!on || !enabled()) {
    return false;
  }
  // Le temoin bat AVANT la garde de regime : apres `kDone` les surcharges se taisent, et un
  // temoin qui se tairait avec elles laisserait `grass_cull_campaign_complete` a 0 pour toujours.
  heartbeat();
  if (!g_regime_active.load(std::memory_order_relaxed)) {
    return false;
  }
  g_grass_overrides.fetch_add(1, std::memory_order_relaxed);
  *on = true;
  return true;
}

bool preset_override(int* preset) {
  if (!preset || !enabled() || !g_regime_active.load(std::memory_order_relaxed)) {
    return false;
  }
  g_preset_overrides.fetch_add(1, std::memory_order_relaxed);
  // medium : le palier livre, celui que la ligne de base a mesure
  *preset = grass_bake::kDensityPresetDefault;
  return true;
}

bool dists_override(float* near_m, float* card_m) {
  if (!near_m || !card_m || !enabled() || !g_regime_active.load(std::memory_order_relaxed)) {
    return false;
  }
  g_dists_overrides.fetch_add(1, std::memory_order_relaxed);
  *near_m = 30.f;
  *card_m = 95.f;
  return true;
}

bool view_yaw(float* yaw_rad) {
  if (!enabled() || g_state == kBoot || g_state == kDone) {
    return false;
  }
  if (g_view <= 0 || g_view >= kViewCount) {
    return false;
  }
  *yaw_rad = kViewYawDeg[g_view] * 3.14159265358979323846f / 180.f;
  return true;
}

bool culling_active() {
  // Hors campagne, le correctif tourne : c'est ce que l'owner joue. La jambe TEMOIN est le seul
  // endroit ou il se tait, et elle n'existe que sous la campagne.
  if (!enabled()) {
    return true;
  }
  return g_state != kLegCtrl;
}

bool want_census() {
  if (!enabled()) {
    return false;
  }
  return g_state == kLegCull && g_state_frames == kCensusAtFrame;
}

void note_partition(uint64_t chunks,
                    uint64_t inst_min,
                    uint64_t inst_p50,
                    uint64_t inst_p90,
                    uint64_t inst_max,
                    bool from_file,
                    uint64_t mismatch,
                    uint64_t instances) {
  if (!enabled()) {
    return;
  }
  g_partition_seen = true;
  g_partition_from_file = from_file;
  g_chunks = chunks;
  g_inst_min = inst_min;
  g_inst_p50 = inst_p50;
  g_inst_p90 = inst_p90;
  g_inst_max = inst_max;
  g_chunk_mismatch = mismatch;
  g_field_instances = instances;
}

void note_census(uint64_t submitted,
                 uint64_t chunk_visible,
                 uint64_t offscreen,
                 uint64_t dropped_visible,
                 uint64_t ideal,
                 uint64_t chunks_kept,
                 uint64_t chunks_total,
                 const float fwd[3]) {
  if (!enabled() || g_view < 0 || g_view >= kViewCount) {
    return;
  }
  ViewResult& r = g_res[g_view];
  r.census_seen = true;
  r.submitted = submitted;
  r.chunk_visible = chunk_visible;
  r.offscreen = offscreen;
  r.dropped_visible = dropped_visible;
  r.ideal = ideal;
  r.chunks_kept = chunks_kept;
  r.chunks_total = chunks_total;
  r.fwd[0] = fwd[0];
  r.fwd[1] = fwd[1];
  r.fwd[2] = fwd[2];
}

void note_frame(double prep_us,
                double submit_us,
                uint64_t draws,
                uint64_t submitted,
                uint64_t chunks_tested,
                uint64_t uniform_lookups,
                bool field_ready) {
  if (!enabled() || g_state == kDone) {
    return;
  }
  g_chunk_tests_total += chunks_tested;
  g_uniform_lookups = uniform_lookups;
  // Miroirs pour le fil GOAL (voir `heartbeat`). `render_frames` est LA grandeur qui separe
  // « l'herbe n'a jamais ete dessinee » de « elle l'a ete et la campagne a cale ».
  g_render_frames.fetch_add(1, std::memory_order_relaxed);
  if (field_ready) {
    g_field_ready_frames.fetch_add(1, std::memory_order_relaxed);
  }
  g_view_pub.store(g_view, std::memory_order_relaxed);
  g_state_frames_pub.store(g_state_frames, std::memory_order_relaxed);

  const auto now = std::chrono::steady_clock::now();
  const bool have_dt = g_last_frame_valid;
  const double dt_ms = have_dt
                           ? std::chrono::duration<double, std::milli>(now - g_last_frame).count()
                           : 0.0;
  g_last_frame = now;
  g_last_frame_valid = true;

  if (g_state == kBoot) {
    // Le champ doit EXISTER : une course qui mesure un champ vide publierait des zeros partout et
    // la porte les lirait comme « rien hors du champ n'est soumis ».
    if (!field_ready) {
      g_state_frames = 0;
      return;
    }
    if (++g_state_frames >= kBootFrames) {
      g_view = 0;
      enter(kAim);
    }
    return;
  }

  if (g_state == kAim) {
    if (++g_state_frames >= kAimFrames[g_view]) {
      enter(kLegCull);
    }
    return;
  }

  // Jambes de mesure. L'image du recensement est EXCLUE des echantillons de temps : son balayage
  // complet des instances entrerait dans un chiffre qui doit decrire le dessin.
  const bool census_frame = (g_state == kLegCull && g_state_frames == kCensusAtFrame);
  if (have_dt && !census_frame && g_samples.dt_ms.size() < kMaxSamples) {
    g_samples.dt_ms.push_back(dt_ms);
    g_samples.prep.push_back(prep_us);
    g_samples.submit.push_back(submit_us);
  }
  if (!census_frame) {
    g_samples.draws_sum += draws;
    g_samples.submitted_last = submitted;
    g_samples.frames++;
  }

  if (++g_state_frames < kLegFrames[g_view]) {
    return;
  }
  if (g_state == kLegCull) {
    close_leg(g_res[g_view].cull);
    enter(kLegCtrl);
    return;
  }
  close_leg(g_res[g_view].ctrl);
  if (++g_view < kViewCount) {
    enter(kAim);
    return;
  }
  g_view = kViewCount - 1;
  enter(kDone);
  publish_all();
}

}  // namespace grass_cull
