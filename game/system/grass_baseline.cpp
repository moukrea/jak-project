#include "game/system/grass_baseline.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "game/graphics/fixed_tick.h"
#include "game/graphics/gfx.h"
#include "game/graphics/grass_density_presets.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/system/autoport_proof.h"
#include "game/system/load_gate.h"
#include "game/system/perf_instruments.h"

namespace grass_baseline {
namespace {

constexpr const char* kItemId = "grass-baseline-cost";

// LES CINQ PALIERS, ETIQUETTES POUR UNE CLE. `autoport_proof::publish` refuse en SILENCE une cle
// qui ne respecte pas `[A-Za-z_][A-Za-z0-9_]*`, et les slugs livres portent un tiret
// (`very-low`). On ne renomme pas la table des paliers — elle est la seule source, lue par le
// moteur, la cuisson et l'empaqueteur (grass_density_presets.h) — on lui donne ici son etiquette
// de cle, et on verifie que les deux tables ont la meme taille.
constexpr const char* kPresetKeys[] = {"very_low", "low", "medium", "high", "very_high"};
static_assert(sizeof(kPresetKeys) / sizeof(kPresetKeys[0]) ==
                  (size_t)grass_bake::kDensityPresetCount,
              "l'etiquette de cle doit suivre la table des paliers");

// LE PALIER LIVRE PAR DEFAUT. Le chiffre d'aout qu'on vient contredire ou confirmer — 110 472
// instances mortes sur 726 851 — a ete releve au regime livre, c'est-a-dire MEDIUM (150 %). La
// grandeur publiee seule sur sa ligne est donc celle de ce palier-la, et les quatre autres sont
// publiees a cote sous leur propre cle.
constexpr int kShippedPreset = grass_bake::kDensityPresetDefault;

// LA FENETRE. Le contrat est explicite : « un releve de moins de 300 images ne compte pas ». Ce
// n'est donc pas une cible mais un PLANCHER, et le plafond de temps qui l'accompagne ne
// raccourcit jamais la fenetre — il abandonne la cellule, qui se lira comme un manque.
constexpr uint64_t kMeasureFrames = 300;
// LE PLAFOND DE TEMPS EST DIMENSIONNE SUR LA CADENCE ATTENDUE, PAS CHOISI ROND. Le chiffre
// archive est 4,6 img/s a l'herbe allumee au palier MEDIUM : 300 images y demandent 65 s, et le
// palier VERY HIGH porte 1,67 fois les instances, donc ~110 s. 220 s laissent le double de
// marge sur la cellule la plus lourde tout en tenant dans les 1800 s de `proof_timeout`
// (5 cellules allumees x 220 + 5 eteintes x ~30 = 1250 s au pire, plus l'amorcage). Un plafond
// atteint ne RACCOURCIT pas la fenetre : il la laisse sous le plancher de 300 images, ou
// `grass_baseline_gaps` la compte comme un manque.
constexpr double kMeasureMaxSeconds = 220.0;
constexpr uint64_t kWarmupFrames = 60;
constexpr double kWarmupMaxSeconds = 15.0;
constexpr uint64_t kSettleFrames = 240;
constexpr double kSettleMaxSeconds = 30.0;
constexpr double kSettleBlockedMaxSeconds = 240.0;
constexpr uint64_t kBootStreakFrames = 30;
constexpr uint64_t kBootMaxFrames = 12000;
// L'application d'un palier passe par une RECONSTRUCTION du champ (chargement du `.grassbake` du
// palier, re-enumeration, televersement), asynchrone. On attend qu'elle ABOUTISSE : mesurer une
// cellule « high » sur le champ « medium » encore en place rendrait cinq lignes vertes decrivant
// un seul palier.
constexpr double kApplyMaxSeconds = 180.0;
constexpr uint64_t kCensusMaxFrames = 180;
constexpr double kCensusMaxSeconds = 30.0;
constexpr size_t kMaxSamples = 420;
constexpr size_t kMinPercentileSamples = 30;

// LES DEUX SEUILS DU VANTAGE. Ce qu'on refuse est un CHANGEMENT DE POINT DE VUE — plusieurs
// metres, une autre orientation — jamais le frisson d'une position au repos. 100 mm pour Jak ;
// 1 decimetre pour la camera, dont la valeur publiee est DEJA quantifiee au decimetre par
// troncature, ce qui laisse un seau entier de jeu a la frontiere.
constexpr uint64_t kVantageMaxMm = 100;
constexpr uint64_t kCameraMaxDm = 1;
// L'unite de longueur de GOAL : 4096 par metre. `jak_pos` est publie dans cette unite brute.
constexpr double kUnitsPerMeter = 4096.0;

// LES DIX CELLULES, DANS CET ORDRE, ET L'ORDRE COMPTE. L'herbe ALLUMEE vient d'abord pour chaque
// palier : c'est la cellule allumee qui declenche la reconstruction du champ, donc le chargement
// qu'on decompose. Eteinte, `GrassRenderer::render` n'est jamais appele et un changement de
// palier ne charge rien.
struct Cell {
  int preset;
  bool grass_on;
};
constexpr Cell kCells[] = {
    {0, true}, {0, false}, {1, true}, {1, false}, {2, true},
    {2, false}, {3, true}, {3, false}, {4, true}, {4, false},
};
constexpr int kCellCount = (int)(sizeof(kCells) / sizeof(kCells[0]));

enum State {
  kBoot = 0,
  kSettle,
  kApply,
  kWarmup,
  kMeasure,
  kCensus,
  kDone,
};

std::atomic<int> g_enabled{-1};  // -1 jamais evalue, 0 eteint, 1 allume

void evaluate_enabled() {
  const bool on = autoport_proof::armed_for(kItemId) && autoport_proof::feature_is(kItemId);
  g_enabled.store(on ? 1 : 0, std::memory_order_relaxed);
}

inline int64_t now_ns() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// ── le regime impose, traversant les fils ───────────────────────────────────────────────────
// Ecrit par le fil GL a l'entree d'une cellule, lu par le fil GOAL a chaque poussee de reglages.
std::atomic<bool> g_regime_active{false};
std::atomic<bool> g_regime_grass_on{false};
std::atomic<int> g_regime_preset{grass_bake::kDensityPresetDefault};
std::atomic<uint64_t> g_grass_overrides{0};
std::atomic<uint64_t> g_preset_overrides{0};

// ── ce que le renderer rapporte, par image ──────────────────────────────────────────────────
std::atomic<bool> g_census_wanted{false};
std::atomic<bool> g_census_ready{false};
std::atomic<uint64_t> g_census_in{0};
std::atomic<uint64_t> g_census_lod{0};
std::atomic<uint64_t> g_census_tested{0};
std::atomic<uint64_t> g_census_behind{0};
std::atomic<int> g_cam_x{0};
std::atomic<int> g_cam_y{0};
std::atomic<int> g_cam_z{0};
std::atomic<bool> g_cam_seen{false};
// Le palier REELLEMENT charge, publie par `note_load` a la fin de la construction du champ.
std::atomic<int> g_loaded_preset{-1};
std::atomic<uint64_t> g_loads_seen{0};

// ── etat de la machine (fil GL uniquement) ──────────────────────────────────────────────────
int g_state = kBoot;
int g_cell = 0;
uint64_t g_state_frames = 0;
int64_t g_state_t0 = 0;
uint64_t g_boot_streak = 0;
uint64_t g_frames_total = 0;
uint64_t g_cells_done = 0;
uint64_t g_cells_short = 0;
uint64_t g_apply_timeouts = 0;
uint64_t g_census_timeouts = 0;
uint64_t g_settle_blocked_frames = 0;
int64_t g_settle_blocked_t0 = 0;
bool g_boot_timeout = false;
bool g_settle_timeout = false;
bool g_witness_done = false;
bool g_done_published = false;

int64_t g_last_frame_ns = 0;
int64_t g_window_t0 = 0;
// LE COMPTE D'IMAGES DE LA FENETRE, RELEVE QUAND ELLE SE FERME — pas a la publication.
// `g_state_frames` appartient a l'ETAT courant, et `enter_state(kCensus)` le remet a zero : lu
// dans `close_cell`, il aurait rendu le nombre d'images du recensement, pas celui du releve.
// Et ce n'est pas `g_samples.size()` non plus : un delta nul entre deux images rend un
// echantillon de moins, ce qui aurait fait tomber une fenetre de 300 images a 299 — donc sous le
// plancher du contrat — pour une raison qui n'a rien a voir avec la mesure.
uint64_t g_window_frames = 0;
std::vector<float> g_samples;
// Accumulateurs de la cellule courante. Les `note_*` du renderer ecrivent dedans depuis le MEME
// fil GL que la machine a etats : pas d'atomique necessaire, et une image qui arrive hors
// fenetre est jetee par le drapeau.
bool g_collect = false;
uint64_t g_render_frames = 0;
uint64_t g_loadcover_frames = 0;
double g_prep_us_sum = 0;
uint64_t g_prep_n = 0;
double g_fence_us_sum = 0;
double g_submit_us_sum = 0;
uint64_t g_draw_n = 0;
uint64_t g_blade_sum = 0;
uint64_t g_card_sum = 0;
uint64_t g_gpu_ns_at_entry = 0;
uint64_t g_gpu_frames_at_entry = 0;
bool g_gpu_ok_at_entry = false;

inline double state_seconds() {
  return (double)(now_ns() - g_state_t0) / 1.0e9;
}

// LE SETTLE NE COMPTE QUE QUAND LE MONDE EST DESSINE (meme raison que `perf_baseline`, meme
// mesure) : sous un ecran de chargement la cadence MONTE, il n'y a presque rien a dessiner, et
// 240 images passent en quelques secondes. Une cellule ouverte la mesurerait l'ecran opaque.
inline bool settle_is_blocked() {
  return load_gate::loading_screen_is_covering() ||
         perf_instruments::snapshot().actors_active == 0;
}

void enter_state(int s) {
  g_state = s;
  g_state_frames = 0;
  g_state_t0 = now_ns();
}

const char* preset_key(int preset) {
  return kPresetKeys[grass_bake::clamp_density_preset(preset)];
}

void cell_key(char* out, size_t cap, int cell, const char* suffix) {
  std::snprintf(out, cap, "grass_%s_%s_%s", kCells[cell].grass_on ? "on" : "off",
                preset_key(kCells[cell].preset), suffix);
}

void load_key(char* out, size_t cap, int preset, const char* suffix) {
  std::snprintf(out, cap, "grass_load_%s_%s", preset_key(preset), suffix);
}

void pub_f(const char* key, double v, int decimals) {
  char val[48];
  std::snprintf(val, sizeof(val), "%.*f", decimals, v);
  autoport_proof::publish_text(key, val);
}

// ── les temoins de regime ───────────────────────────────────────────────────────────────────
// Une cadence sans le regime qui l'a produite n'est pas une mesure. Relus a chaque fermeture de
// cellule — la derniere valeur gagne — parce que GOAL les pose bien apres l'amorcage.
void publish_witnesses() {
  char v[64];
#if defined(__ANDROID__)
  autoport_proof::publish_text("grass_baseline_source", "android");
#else
  autoport_proof::publish_text("grass_baseline_source", "x86");
#endif
  // LE MAITRE EFFECTIF, PAS LE REGLAGE (perf_baseline, meme piege) : `OG_RECHARGED` /
  // `debug.opengoal.recharged` surchargent ce que settings.ini porte, et c'est la surcharge que
  // le rendu lit. Herbe et maitre eteints rendraient dix cellules identiques.
  autoport_proof::publish("grass_baseline_recharged", Gfx::recharged_master_active() ? 1 : 0);
  autoport_proof::publish("grass_baseline_recharged_setting",
                          Gfx::g_global_settings.recharged_master ? 1 : 0);
  autoport_proof::publish("grass_baseline_vsync", Gfx::g_global_settings.vsync ? 1 : 0);
  autoport_proof::publish("grass_baseline_fixed_tick", fixed_tick::enabled() ? 1 : 0);
  pub_f("grass_baseline_frame_cap", (double)Gfx::g_global_settings.display_fps_cap, 1);
  uint64_t gpu_ns = 0, gpu_frames = 0;
  autoport_proof::publish("grass_baseline_gpu_timer",
                          lighting_census::gpu_frame_totals(&gpu_ns, &gpu_frames) ? 1 : 0);
  autoport_proof::publish("grass_baseline_perf_instruments",
                          perf_instruments::enabled() ? 1 : 0);
  autoport_proof::publish("grass_baseline_boot_timeout", g_boot_timeout ? 1 : 0);
  autoport_proof::publish("grass_baseline_boot_actors_last",
                          perf_instruments::snapshot().actors_active);
  autoport_proof::publish("grass_baseline_settle_timeout", g_settle_timeout ? 1 : 0);
  autoport_proof::publish("grass_baseline_settle_blocked_frames", g_settle_blocked_frames);
  autoport_proof::publish("grass_baseline_apply_timeouts", g_apply_timeouts);
  autoport_proof::publish("grass_baseline_census_timeouts", g_census_timeouts);
  autoport_proof::publish("grass_baseline_cells_short", g_cells_short);
  autoport_proof::publish("grass_baseline_cells_done", g_cells_done);
  autoport_proof::publish("grass_baseline_expected", (uint64_t)kCellCount);
  autoport_proof::publish("grass_baseline_state", (uint64_t)g_state);
  autoport_proof::publish("grass_baseline_cell_index", (uint64_t)g_cell);
  // LES DEUX SURCHARGES, COMPTEES. Sans elles, « la campagne impose son regime » et « le pont
  // GOAL n'a jamais appele ces fonctions » rendent la meme table.
  autoport_proof::publish("grass_baseline_grass_overrides",
                          g_grass_overrides.load(std::memory_order_relaxed));
  autoport_proof::publish("grass_baseline_preset_overrides",
                          g_preset_overrides.load(std::memory_order_relaxed));
  autoport_proof::publish("grass_baseline_loads_seen",
                          g_loads_seen.load(std::memory_order_relaxed));
  autoport_proof::publish("grass_baseline_loaded_preset",
                          (uint64_t)std::max(0, g_loaded_preset.load(std::memory_order_relaxed)));
  // LE VANTAGE, SUR TOUTES LES CELLULES. La position de Jak est poussee par GOAL a chaque image
  // (`pc-set-jak-pos!`), donc elle est lisible meme dans les cellules ou l'herbe est eteinte et
  // ou le renderer d'herbe ne tourne pas. C'est le temoin qui rend « au MEME vantage »
  // verifiable au lieu d'etre affirme.
  const auto& jp = Gfx::g_global_settings.recharged_jak_pos;
  std::snprintf(v, sizeof(v), "%.1f_%.1f_%.1f", (double)jp[0], (double)jp[1], (double)jp[2]);
  autoport_proof::publish_text("grass_baseline_vantage", v);
}

// ── LE COMPTE DE CE QUI MANQUE ──────────────────────────────────────────────────────────────
// Il se lit dans la TABLE QUI SERA MOISSONNEE (`has_key`), jamais dans une variable interne : une
// porte calculee sur ses propres variables est un miroir, pas une mesure. Une cellule dont la
// fenetre n'a pas atteint 300 images compte pour un manque de plus, meme si toutes ses cles sont
// la : le contrat refuse ce releve.
const char* const kCellMetrics[] = {"fps",   "frames",         "frame_ms_p50",  "frame_ms_p95",
                                    "jak_pos", "render_frames", "actors_active", "loadcover_frames"};
const char* const kOnMetrics[] = {"prep_us",        "fence_us",       "submit_us",
                                  "submitted_blade", "submitted_card", "frustum_in",
                                  "frustum_lod",    "frustum_tested", "frustum_behind",
                                  // `cam_dm` est publie dans la MEME image que le recensement,
                                  // par l'appel qui precede `note_frustum` sans aucune garde
                                  // (GrassRenderer.cpp:2301) : sa population est exactement
                                  // celle des quatre `frustum_*`. L'exiger ne peut donc pas
                                  // rougir pour une raison qu'elles ne rougiraient pas deja, et
                                  // sans lui le comparateur de vantage ci-dessous n'aurait rien
                                  // a relire sur une cellule dont la camera a bouge.
                                  "cam_dm"};
const char* const kLoadMetrics[] = {"total_ms",   "source_ms", "expand_ms", "upload_ms",
                                    "blocked_ms", "async",     "waits",     "instances",
                                    "requested",  "drawn",     "dead",       "inst_bytes",
                                    "light_bytes"};

// ── LE VANTAGE, JUGE ET PAS SEULEMENT PUBLIE ────────────────────────────────────────────────
// « au MEME vantage » est la clause 1 du contrat, et elle n'avait AUCUN terme : `jak_pos` etait
// exige PRESENT, jamais EGAL d'une cellule a l'autre, et `cam_dm` n'etait dans aucune liste. Dix
// cellules prises sous dix points de vue passaient donc vertes, et l'ecart ON/OFF — la seule
// grandeur pour laquelle cet item existe — aurait compare deux scenes differentes sans qu'un
// seul terme proteste. C'est un faux vert, pas une lacune de confort.
//
// LES DEUX GRANDEURS SONT NECESSAIRES. La position de Jak dit qu'il n'a pas bouge ; elle ne dit
// RIEN de la direction du regard. La position de la camera, qui orbite autour d'un Jak immobile,
// la fixe : meme Jak + meme camera = meme volume de vue, donc les `frustum_in` des cinq cellules
// allumees sont comparables. L'ORIENTATION elle-meme n'est pas relevee (non prouve : voir le
// rapport) ; ces deux positions la contraignent, elles ne la mesurent pas.
//
// ON RELIT LA TABLE QUI SERA MOISSONNEE, pas les variables du module — meme regle que le reste de
// `publish_gaps`. Une porte calculee sur son propre etat est un miroir : ici c'est la valeur
// REELLEMENT publiee, celle que l'owner lira dans `proof.txt`, qui est comparee.
//
// ON PUBLIE UNE MAGNITUDE, JAMAIS UN BOOLEEN. `..._spread_mm` / `..._spread_dm` disent DE COMBIEN
// le vantage a bouge ; un drapeau dirait qu'il a bouge sans nommer l'ampleur, et personne ne
// saurait si le releve est a jeter ou a lire avec une reserve.
//
// LA POPULATION SORT A COTE. `..._cells` est le denominateur : sans lui, un ecart nul se lirait
// « toutes les cellules au meme endroit » alors qu'il peut vouloir dire « une seule cellule
// relue » — une porte verte par INACTION. Moins de deux cellules comparables EST un manque, et il
// se nomme au lieu de se publier en zero.
//
// Rend le nombre de cellules relues ET analysees ; `*spread` recoit l'ecart maximal sur les trois
// axes, multiplie par `scale`. Une cellule dont la cle manque ou dont le texte ne se relit pas en
// trois nombres n'entre dans aucun des deux : elle se compte deja comme cle manquante ailleurs.
int vantage_spread(bool on_cells_only, const char* metric, double scale, double* spread) {
  int cells = 0;
  double lo[3] = {0.0, 0.0, 0.0};
  double hi[3] = {0.0, 0.0, 0.0};
  char key[96];
  char val[96];
  for (int c = 0; c < kCellCount; c++) {
    if (on_cells_only && !kCells[c].grass_on) {
      continue;
    }
    cell_key(key, sizeof(key), c, metric);
    if (!autoport_proof::read_text(key, val, sizeof(val))) {
      continue;
    }
    double p[3] = {0.0, 0.0, 0.0};
    if (std::sscanf(val, "%lf_%lf_%lf", &p[0], &p[1], &p[2]) != 3) {
      continue;
    }
    for (int a = 0; a < 3; a++) {
      if (cells == 0 || p[a] < lo[a]) {
        lo[a] = p[a];
      }
      if (cells == 0 || p[a] > hi[a]) {
        hi[a] = p[a];
      }
    }
    cells++;
  }
  double s = 0.0;
  for (int a = 0; a < 3; a++) {
    s = std::max(s, hi[a] - lo[a]);
  }
  *spread = s * scale;
  return cells;
}

void publish_gaps() {
  uint64_t gaps = 0;
  // COMBIEN DE CELLULES ONT VU LEUR REGIME RELU. Une porte agregee qui compte 1 par terme NON
  // MESURE se lit comme une porte verte : ce denominateur sort a cote de `gaps` pour qu'on
  // sache, AVANT de lire la somme, sur combien de cellules le terme de regime a mordu.
  uint64_t regime_read = 0;
  std::string missing;
  char key[96];
  auto miss = [&](const char* what) {
    gaps++;
    if (missing.size() < 200) {
      if (!missing.empty()) {
        missing += ",";
      }
      missing += what;
    }
  };
  for (int c = 0; c < kCellCount; c++) {
    for (const char* m : kCellMetrics) {
      cell_key(key, sizeof(key), c, m);
      if (!autoport_proof::has_key(key)) {
        miss(key);
      }
    }
    if (kCells[c].grass_on) {
      for (const char* m : kOnMetrics) {
        cell_key(key, sizeof(key), c, m);
        if (!autoport_proof::has_key(key)) {
          miss(key);
        }
      }
    }
    // LE PLANCHER DU CONTRAT, COMPTE COMME UN MANQUE. `frames` est publie meme court : c'est la
    // valeur qui dit POURQUOI la cellule ne compte pas.
    cell_key(key, sizeof(key), c, "frames");
    uint64_t n = 0;
    if (autoport_proof::read_uint(key, n) && n < kMeasureFrames) {
      miss(key);
    }
    // LE REGIME DE LA CELLULE, JUGE ET PAS SEULEMENT PUBLIE. `render_frames` etait exige PRESENT
    // et jamais relu : une cellule ETEINTE dont la surcharge n'a pas mordu — GOAL qui n'appelle
    // pas `pc_set_recharged_grass`, porte `recharged_gating` ecrasee — mesure l'herbe ALLUMEE,
    // publie une cadence, et `gaps` reste a zero. Les cinq cellules « OFF » seraient alors une
    // copie des cinq « ON », et l'ECART ON/OFF — la seule grandeur pour laquelle cet item
    // existe — serait faux sans qu'un seul terme rougisse. C'est un faux vert, pas une lacune
    // de confort. Le terme ne coute rien : la valeur est deja dans la table moissonnee.
    //
    // LES DEUX SENS, parce qu'un seul laisserait l'autre panne muette : une cellule ALLUMEE ou
    // le renderer n'a jamais tourne rend « l'herbe ne coute rien » et « l'instrument n'a pas
    // tourne » sur la meme ligne. Le seuil est `!= 0`, pas `>= frames` : la course a blanc rend
    // 288 sur 300 au palier very_low (`has_pc_data` faux quelques images), et un plancher serre
    // rougirait sur un regime pourtant correct.
    cell_key(key, sizeof(key), c, "render_frames");
    uint64_t rf = 0;
    if (autoport_proof::read_uint(key, rf)) {
      regime_read++;
      if (kCells[c].grass_on ? (rf == 0) : (rf != 0)) {
        char why[128];
        std::snprintf(why, sizeof(why), "%s_vaut_%llu_sous_regime_%s", key,
                      (unsigned long long)rf, kCells[c].grass_on ? "on" : "off");
        miss(why);
      }
    }
  }
  for (int p = 0; p < grass_bake::kDensityPresetCount; p++) {
    for (const char* m : kLoadMetrics) {
      load_key(key, sizeof(key), p, m);
      if (!autoport_proof::has_key(key)) {
        miss(key);
      }
    }
  }
  if (!autoport_proof::has_key("grass_baseline_dead_instances")) {
    miss("grass_baseline_dead_instances");
  }
  if (!autoport_proof::has_key("grass_baseline_built_instances")) {
    miss("grass_baseline_built_instances");
  }
  // LE VANTAGE (clause 1 du contrat). Voir le commentaire au-dessus de `vantage_spread`.
  {
    char v[48];
    char why[160];
    double spread = 0.0;
    const int cells = vantage_spread(false, "jak_pos", 1000.0 / kUnitsPerMeter, &spread);
    autoport_proof::publish("grass_baseline_vantage_cells", (uint64_t)cells);
    if (cells >= 2) {
      const uint64_t mm = (uint64_t)(spread + 0.5);
      std::snprintf(v, sizeof(v), "%llu", (unsigned long long)mm);
      autoport_proof::publish_text("grass_baseline_vantage_spread_mm", v);
      if (mm > kVantageMaxMm) {
        std::snprintf(why, sizeof(why), "vantage_spread_mm_vaut_%llu_sur_%d_cellules",
                      (unsigned long long)mm, cells);
        miss(why);
      }
    } else {
      // JAMAIS ZERO ICI. Un ecart non mesure et un ecart nul se publieraient sur la meme ligne,
      // et c'est le zero qui se lirait comme la reussite.
      autoport_proof::publish_text("grass_baseline_vantage_spread_mm", "-");
      std::snprintf(why, sizeof(why), "vantage_cells_vaut_%d_sur_%d", cells, kCellCount);
      miss(why);
    }
  }
  {
    char v[48];
    char why[160];
    double spread = 0.0;
    const int cells = vantage_spread(true, "cam_dm", 1.0, &spread);
    autoport_proof::publish("grass_baseline_camera_cells", (uint64_t)cells);
    int on_cells = 0;
    for (int c = 0; c < kCellCount; c++) {
      on_cells += kCells[c].grass_on ? 1 : 0;
    }
    if (cells >= 2) {
      const uint64_t dm = (uint64_t)(spread + 0.5);
      std::snprintf(v, sizeof(v), "%llu", (unsigned long long)dm);
      autoport_proof::publish_text("grass_baseline_camera_spread_dm", v);
      if (dm > kCameraMaxDm) {
        std::snprintf(why, sizeof(why), "camera_spread_dm_vaut_%llu_sur_%d_cellules",
                      (unsigned long long)dm, cells);
        miss(why);
      }
    } else {
      autoport_proof::publish_text("grass_baseline_camera_spread_dm", "-");
      std::snprintf(why, sizeof(why), "camera_cells_vaut_%d_sur_%d", cells, on_cells);
      miss(why);
    }
  }
  autoport_proof::publish_text("grass_baseline_missing", missing.empty() ? "-" : missing.c_str());
  autoport_proof::publish("grass_baseline_regime_read", regime_read);
  autoport_proof::publish("grass_baseline_gaps", gaps);
}

void begin_cell() {
  const Cell& c = kCells[g_cell];
  g_regime_grass_on.store(c.grass_on, std::memory_order_relaxed);
  g_regime_preset.store(c.preset, std::memory_order_relaxed);
  g_regime_active.store(true, std::memory_order_relaxed);
  g_census_wanted.store(false, std::memory_order_relaxed);
  g_census_ready.store(false, std::memory_order_relaxed);
  printf("GRASS-BASELINE cell %d/%d grass=%s preset=%s\n", g_cell + 1, kCellCount,
         c.grass_on ? "on" : "off", preset_key(c.preset));
  fflush(stdout);
  enter_state(kApply);
}

void begin_measure() {
  g_samples.clear();
  g_samples.reserve(kMaxSamples);
  g_render_frames = 0;
  g_loadcover_frames = 0;
  g_prep_us_sum = 0;
  g_prep_n = 0;
  g_fence_us_sum = 0;
  g_submit_us_sum = 0;
  g_draw_n = 0;
  g_blade_sum = 0;
  g_card_sum = 0;
  g_gpu_ns_at_entry = 0;
  g_gpu_frames_at_entry = 0;
  g_gpu_ok_at_entry =
      lighting_census::gpu_frame_totals(&g_gpu_ns_at_entry, &g_gpu_frames_at_entry);
  g_collect = true;
  g_window_frames = 0;
  g_window_t0 = now_ns();
  enter_state(kMeasure);
}

void close_cell() {
  g_collect = false;
  const int c = g_cell;
  char key[96];
  const uint64_t n = g_window_frames;
  const double window_s = (double)(now_ns() - g_window_t0) / 1.0e9;

  cell_key(key, sizeof(key), c, "frames");
  autoport_proof::publish(key, n);
  // Le denominateur des percentiles est publie A COTE du nombre d'images : les deux peuvent
  // differer d'une unite, et un lecteur qui trouverait 299 la ou le contrat en exige 300 doit
  // pouvoir voir LEQUEL des deux il lit.
  cell_key(key, sizeof(key), c, "samples");
  autoport_proof::publish(key, (uint64_t)g_samples.size());
  // LA CADENCE SUR LA FENETRE, denominateur compris : `frames / secondes`. On ne la derive pas du
  // percentile — une mediane de deltas et une cadence moyenne ne sont pas la meme grandeur, et
  // c'est la cadence que le contrat demande de publier a cote du nombre d'images.
  if (n > 0 && window_s > 0.0) {
    cell_key(key, sizeof(key), c, "fps");
    pub_f(key, (double)n / window_s, 3);
  }
  std::sort(g_samples.begin(), g_samples.end());
  const size_t ns = g_samples.size();
  if (ns >= kMinPercentileSamples) {
    const size_t i50 = ns / 2;
    size_t i95 = (ns * 95) / 100;
    if (i95 >= ns) {
      i95 = ns - 1;
    }
    cell_key(key, sizeof(key), c, "frame_ms_p50");
    pub_f(key, (double)g_samples[i50], 3);
    cell_key(key, sizeof(key), c, "frame_ms_p95");
    pub_f(key, (double)g_samples[i95], 3);
  }

  const perf_instruments::Snapshot snap = perf_instruments::snapshot();
  cell_key(key, sizeof(key), c, "actors_active");
  autoport_proof::publish(key, snap.actors_active);
  cell_key(key, sizeof(key), c, "goal_busy_ms");
  pub_f(key, snap.busy_ms, 3);
  cell_key(key, sizeof(key), c, "render_frames");
  autoport_proof::publish(key, g_render_frames);
  cell_key(key, sizeof(key), c, "loadcover_frames");
  autoport_proof::publish(key, g_loadcover_frames);
  {
    char v[64];
    const auto& jp = Gfx::g_global_settings.recharged_jak_pos;
    std::snprintf(v, sizeof(v), "%.1f_%.1f_%.1f", (double)jp[0], (double)jp[1], (double)jp[2]);
    cell_key(key, sizeof(key), c, "jak_pos");
    autoport_proof::publish_text(key, v);
  }

  uint64_t gpu_ns = 0, gpu_frames = 0;
  if (g_gpu_ok_at_entry && lighting_census::gpu_frame_totals(&gpu_ns, &gpu_frames) &&
      gpu_frames > g_gpu_frames_at_entry && gpu_ns >= g_gpu_ns_at_entry) {
    cell_key(key, sizeof(key), c, "gpu_ms");
    pub_f(key, (double)(gpu_ns - g_gpu_ns_at_entry) /
                   (double)(gpu_frames - g_gpu_frames_at_entry) / 1.0e6,
          4);
  }

  if (kCells[c].grass_on) {
    if (g_prep_n > 0) {
      cell_key(key, sizeof(key), c, "prep_us");
      pub_f(key, g_prep_us_sum / (double)g_prep_n, 1);
    }
    if (g_draw_n > 0) {
      cell_key(key, sizeof(key), c, "fence_us");
      pub_f(key, g_fence_us_sum / (double)g_draw_n, 1);
      cell_key(key, sizeof(key), c, "submit_us");
      pub_f(key, g_submit_us_sum / (double)g_draw_n, 1);
      cell_key(key, sizeof(key), c, "submitted_blade");
      autoport_proof::publish(key, g_blade_sum / g_draw_n);
      cell_key(key, sizeof(key), c, "submitted_card");
      autoport_proof::publish(key, g_card_sum / g_draw_n);
    }
    if (g_census_ready.load(std::memory_order_relaxed)) {
      cell_key(key, sizeof(key), c, "frustum_in");
      autoport_proof::publish(key, g_census_in.load(std::memory_order_relaxed));
      cell_key(key, sizeof(key), c, "frustum_lod");
      autoport_proof::publish(key, g_census_lod.load(std::memory_order_relaxed));
      cell_key(key, sizeof(key), c, "frustum_tested");
      autoport_proof::publish(key, g_census_tested.load(std::memory_order_relaxed));
      cell_key(key, sizeof(key), c, "frustum_behind");
      autoport_proof::publish(key, g_census_behind.load(std::memory_order_relaxed));
      if (g_cam_seen.load(std::memory_order_relaxed)) {
        char v[64];
        // Decimetres entiers : `publish_text` remplace tout blanc par `_`, et un flottant
        // formate ici resterait de toute facon une chaine. L'entier evite de publier du bruit
        // de virgule la ou on ne compare que des positions.
        std::snprintf(v, sizeof(v), "%d_%d_%d", g_cam_x.load(std::memory_order_relaxed),
                      g_cam_y.load(std::memory_order_relaxed),
                      g_cam_z.load(std::memory_order_relaxed));
        cell_key(key, sizeof(key), c, "cam_dm");
        autoport_proof::publish_text(key, v);
      }
    }
  }

  // `hits` = « releves de cadence effectivement pris ». Une fenetre qui n'atteint pas le plancher
  // du contrat n'est pas un releve : elle ne compte pas ici, et elle se compte dans les manques.
  if (n >= kMeasureFrames) {
    g_cells_done++;
    autoport_proof::note_hit_for(kItemId, 1);
  } else {
    g_cells_short++;
  }
  publish_witnesses();
  publish_gaps();
  // LA TABLE SORT MAINTENANT, PAS DANS SOIXANTE IMAGES. `frame_tick` n'emet qu'une fois sur 60 ;
  // a 4 images/s, la derniere cellule d'une course qui se termine pourrait ne jamais etre
  // moissonnee. Un `flush` par cellule coute dix emissions sur toute la course.
  autoport_proof::flush();
}

void advance_after_cell() {
  g_cell++;
  if (g_cell >= kCellCount) {
    g_regime_active.store(false, std::memory_order_relaxed);
    enter_state(kDone);
    return;
  }
  begin_cell();
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

bool grass_on_override(bool* on) {
  if (!on || !enabled() || !g_regime_active.load(std::memory_order_relaxed)) {
    return false;
  }
  g_grass_overrides.fetch_add(1, std::memory_order_relaxed);
  *on = g_regime_grass_on.load(std::memory_order_relaxed);
  return true;
}

bool preset_override(int* preset) {
  if (!preset || !enabled() || !g_regime_active.load(std::memory_order_relaxed)) {
    return false;
  }
  g_preset_overrides.fetch_add(1, std::memory_order_relaxed);
  *preset = g_regime_preset.load(std::memory_order_relaxed);
  return true;
}

void note_render_entry() {
  if (!enabled() || !g_collect) {
    return;
  }
  g_render_frames++;
}

void note_prepare_us(double us) {
  if (!enabled() || !g_collect || us < 0.0) {
    return;
  }
  g_prep_us_sum += us;
  g_prep_n++;
}

void note_draw(double fence_us, double submit_us, uint64_t blade_instances,
               uint64_t card_instances) {
  if (!enabled() || !g_collect) {
    return;
  }
  g_fence_us_sum += fence_us < 0.0 ? 0.0 : fence_us;
  g_submit_us_sum += submit_us < 0.0 ? 0.0 : submit_us;
  g_blade_sum += blade_instances;
  g_card_sum += card_instances;
  g_draw_n++;
}

bool want_frustum_census() {
  return enabled() && g_census_wanted.load(std::memory_order_relaxed) &&
         !g_census_ready.load(std::memory_order_relaxed);
}

void note_frustum(uint64_t in_frustum, uint64_t in_frustum_lod, uint64_t tested,
                  uint64_t behind) {
  if (!enabled()) {
    return;
  }
  g_census_in.store(in_frustum, std::memory_order_relaxed);
  g_census_lod.store(in_frustum_lod, std::memory_order_relaxed);
  g_census_tested.store(tested, std::memory_order_relaxed);
  g_census_behind.store(behind, std::memory_order_relaxed);
  g_census_ready.store(true, std::memory_order_relaxed);
}

void note_camera(float x, float y, float z) {
  if (!enabled()) {
    return;
  }
  // U = 4096 unites monde par metre (grass_bake) ; on publie en decimetres pour garder un entier
  // lisible sans dependre d'une constante de plus dans ce fichier.
  g_cam_x.store((int)(x / 409.6f), std::memory_order_relaxed);
  g_cam_y.store((int)(y / 409.6f), std::memory_order_relaxed);
  g_cam_z.store((int)(z / 409.6f), std::memory_order_relaxed);
  g_cam_seen.store(true, std::memory_order_relaxed);
}

void note_load(int preset,
               int requested,
               double total_ms,
               double source_ms,
               double expand_ms,
               double upload_ms,
               double blocked_ms,
               bool async,
               uint64_t waits,
               uint64_t instances,
               uint64_t drawn_instances,
               uint64_t inst_bytes,
               uint64_t light_bytes) {
  if (!enabled()) {
    return;
  }
  const int p = grass_bake::clamp_density_preset(preset);
  char key[96];
  load_key(key, sizeof(key), p, "total_ms");
  pub_f(key, total_ms, 2);
  load_key(key, sizeof(key), p, "source_ms");
  pub_f(key, source_ms, 2);
  load_key(key, sizeof(key), p, "expand_ms");
  pub_f(key, expand_ms, 2);
  load_key(key, sizeof(key), p, "upload_ms");
  pub_f(key, upload_ms, 2);
  // CE QUE LE FIL DE RENDU A REELLEMENT PAYE. Sur le chemin asynchrone livre, `expand_ms` couvre
  // plusieurs images d'ATTENTE : lu seul, il ferait passer un delai pour une charge processeur.
  load_key(key, sizeof(key), p, "blocked_ms");
  pub_f(key, blocked_ms, 2);
  load_key(key, sizeof(key), p, "async");
  autoport_proof::publish(key, async ? 1 : 0);
  load_key(key, sizeof(key), p, "waits");
  autoport_proof::publish(key, waits);
  load_key(key, sizeof(key), p, "requested");
  autoport_proof::publish(key, (uint64_t)grass_bake::clamp_density_preset(requested));
  load_key(key, sizeof(key), p, "instances");
  autoport_proof::publish(key, instances);
  load_key(key, sizeof(key), p, "drawn");
  autoport_proof::publish(key, drawn_instances);
  // LA QUEUE MORTE : construite, televersee, JAMAIS dessinee. `OG_FEAT_GRASS_OVERHANG` est
  // eteint dans les deux arbres livres, donc la passe brin s'arrete a `m_droop_start` et la
  // passe carte n'y va jamais. La difference est donc entierement payee au chargement et en
  // memoire GPU, pour rien.
  load_key(key, sizeof(key), p, "dead");
  autoport_proof::publish(key, instances >= drawn_instances ? instances - drawn_instances : 0);
  load_key(key, sizeof(key), p, "inst_bytes");
  autoport_proof::publish(key, inst_bytes);
  load_key(key, sizeof(key), p, "light_bytes");
  autoport_proof::publish(key, light_bytes);
  if (p == kShippedPreset) {
    autoport_proof::publish("grass_baseline_dead_instances",
                            instances >= drawn_instances ? instances - drawn_instances : 0);
    autoport_proof::publish("grass_baseline_built_instances", instances);
  }
  g_loaded_preset.store(p, std::memory_order_relaxed);
  g_loads_seen.fetch_add(1, std::memory_order_relaxed);
}

void note_drawn_frame(double gl_cpu_ms) {
  (void)gl_cpu_ms;
  g_frames_total++;
  // Le nommage de l'item arrive par une propriete systeme, posee APRES le teardown de
  // `proof_run.sh` : relu periodiquement, comme perf_instruments, pour ne pas figer un etat lu
  // trop tot.
  if (g_frames_total % 240 == 1) {
    evaluate_enabled();
  }
  if (!enabled()) {
    return;
  }
  if (!g_witness_done) {
    g_witness_done = true;
    publish_witnesses();
    publish_gaps();
  }
  // LA TABLE DIT OU EN EST LA CAMPAGNE, A TOUTE IMAGE MOISSONNEE. Ces deux publications ne
  // tournaient qu'aux FERMETURES de cellule : entre deux, la table moissonnee portait l'etat
  // d'AVANT, et une course arretee en cours de route — plafond de temps, plantage — se lisait
  // `grass_baseline_state=0`, c'est-a-dire « jamais sortie de l'amorcage ». Mesure de la course a
  // blanc x86 du 2026-09-16 : `state=0` et `cell_index=0` publies pendant que le journal du meme
  // processus annoncait « cell 1/10 », et `gaps=192` maintenu alors que le palier MEDIUM venait
  // de publier ses treize grandeurs de chargement. Le recalcul complet — une relecture de la
  // table de publication — coute une passe toutes les 120 images.
  if (g_frames_total % 120 == 0) {
    publish_witnesses();
    publish_gaps();
  }
  const int64_t t = now_ns();
  const int64_t prev = g_last_frame_ns;
  g_last_frame_ns = t;
  g_state_frames++;
  if (g_collect && load_gate::loading_screen_is_covering()) {
    g_loadcover_frames++;
  }

  switch (g_state) {
    case kBoot: {
      // L'ECRAN DE CHARGEMENT N'A PAS D'ACTEURS. On attend que le teleport pose par le harnais
      // ait vraiment abouti : 30 images consecutives avec au moins un acteur qui a couru.
      if (perf_instruments::snapshot().actors_active > 0) {
        g_boot_streak++;
      } else {
        g_boot_streak = 0;
      }
      if (g_boot_streak >= kBootStreakFrames) {
        publish_witnesses();
        enter_state(kSettle);
        return;
      }
      if (g_state_frames > kBootMaxFrames && !g_boot_timeout) {
        g_boot_timeout = true;
        publish_witnesses();
        publish_gaps();
        printf("GRASS-BASELINE boot timeout frames=%llu actors=%llu\n",
               (unsigned long long)g_state_frames,
               (unsigned long long)perf_instruments::snapshot().actors_active);
        fflush(stdout);
      }
      return;
    }
    case kSettle: {
      if (settle_is_blocked()) {
        if (g_settle_blocked_t0 == 0) {
          g_settle_blocked_t0 = t;
        }
        g_settle_blocked_frames++;
        g_state_frames = 0;
        g_state_t0 = t;
        if (!g_settle_timeout &&
            (double)(t - g_settle_blocked_t0) / 1.0e9 >= kSettleBlockedMaxSeconds) {
          g_settle_timeout = true;
          publish_witnesses();
          publish_gaps();
          printf("GRASS-BASELINE settle blocked frames=%llu cover=%d actors=%llu\n",
                 (unsigned long long)g_settle_blocked_frames,
                 load_gate::loading_screen_is_covering() ? 1 : 0,
                 (unsigned long long)perf_instruments::snapshot().actors_active);
          fflush(stdout);
        }
        return;
      }
      g_settle_blocked_t0 = 0;
      if (g_state_frames >= kSettleFrames || state_seconds() >= kSettleMaxSeconds) {
        begin_cell();
      }
      return;
    }
    case kApply: {
      // LE REGIME DOIT AVOIR MORDU AVANT QU'ON MESURE. Pour une cellule allumee cela veut dire
      // que le champ du PALIER DEMANDE est construit : `note_load` publie le palier servi. Pour
      // une cellule eteinte il n'y a rien a charger — l'herbe ne dessine plus — mais le monde
      // doit rester dessine.
      const bool blocked = settle_is_blocked();
      const bool ready =
          !blocked && (!kCells[g_cell].grass_on ||
                       g_loaded_preset.load(std::memory_order_relaxed) == kCells[g_cell].preset);
      if (ready) {
        enter_state(kWarmup);
        return;
      }
      if (state_seconds() >= kApplyMaxSeconds) {
        // ON N'OUVRE PAS LA CELLULE SUR LE MAUVAIS CHAMP. On la SAUTE : ses cles resteront
        // absentes, `grass_baseline_gaps` les comptera, et `grass_baseline_apply_timeouts` dira
        // combien de fois c'est arrive.
        g_apply_timeouts++;
        printf("GRASS-BASELINE apply timeout cell=%d want=%s loaded=%d blocked=%d\n", g_cell,
               preset_key(kCells[g_cell].preset),
               g_loaded_preset.load(std::memory_order_relaxed), blocked ? 1 : 0);
        fflush(stdout);
        publish_witnesses();
        publish_gaps();
        advance_after_cell();
      }
      return;
    }
    case kWarmup: {
      if (g_state_frames >= kWarmupFrames || state_seconds() >= kWarmupMaxSeconds) {
        begin_measure();
      }
      return;
    }
    case kMeasure: {
      if (prev > 0 && t > prev && g_samples.size() < kMaxSamples) {
        g_samples.push_back((float)((double)(t - prev) / 1.0e6));
      }
      if (g_state_frames >= kMeasureFrames || state_seconds() >= kMeasureMaxSeconds) {
        g_window_frames = g_state_frames;
        g_collect = false;
        if (kCells[g_cell].grass_on) {
          // LE RECENSEMENT DU CHAMP DE VISION SE FAIT HORS FENETRE. Un balayage des centaines de
          // milliers d'instances coute plusieurs millisecondes : mesure DANS la fenetre, il
          // entrerait dans le temps de preparation qu'on publie a cote.
          g_census_ready.store(false, std::memory_order_relaxed);
          g_census_wanted.store(true, std::memory_order_relaxed);
          enter_state(kCensus);
          return;
        }
        close_cell();
        advance_after_cell();
      }
      return;
    }
    case kCensus: {
      if (g_census_ready.load(std::memory_order_relaxed)) {
        g_census_wanted.store(false, std::memory_order_relaxed);
        close_cell();
        advance_after_cell();
        return;
      }
      if (g_state_frames >= kCensusMaxFrames || state_seconds() >= kCensusMaxSeconds) {
        g_census_timeouts++;
        g_census_wanted.store(false, std::memory_order_relaxed);
        close_cell();
        advance_after_cell();
      }
      return;
    }
    case kDone:
    default: {
      if (!g_done_published) {
        g_done_published = true;
        publish_witnesses();
        publish_gaps();
        autoport_proof::flush();
        printf("GRASS-BASELINE done cells=%llu short=%llu\n", (unsigned long long)g_cells_done,
               (unsigned long long)g_cells_short);
        fflush(stdout);
      }
      return;
    }
  }
}

// CE BINAIRE PORTE UN SITE DE CET ITEM. Declare au CHARGEMENT, avant toute image : c'est ce qui
// separe « aucun instrument compile » de « instrument jamais atteint », les deux zeros que la
// porte confondait avant `proof-feature-hits-is-vacuous`.
AUTOPORT_FEATURE_SITE("grass-baseline-cost");

}  // namespace grass_baseline
