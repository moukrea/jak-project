#include "game/system/recharged_gating.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "game/graphics/gfx.h"
#include "game/system/autoport_proof.h"

namespace recharged_gating {
namespace {

// ─── LA TABLE ────────────────────────────────────────────────────────────────────────────────
// Une ligne par option, et le PARENT est ici — nulle part ailleurs. Le grisage du menu, la porte
// du moteur et le recensement de preuve lisent tous les trois CETTE colonne.
//
// `kNode` = un maitre (master / eclairage / eau). Son champ garde la valeur VOULUE et le module
// ne l'ecrit jamais : son etat effectif vient des helpers de gfx.h, qui composent en plus les
// surcharges du harnais (`debug.opengoal.recharged`, `OG_LIGHTING`, l'epinglage refset, le
// binaire-temoin AUTOPORT_ORIGIN_ABLATE). Les detourner ici casserait le jeu de references et la
// campagne HDR, qui epinglent ces trois drapeaux ; ce n'est pas le perimetre de cet item.
//
// `kToggle` / `kMode` = ce que le joueur allume et eteint. STOCK = 0 : eteint doit valoir ABSENT.
// `kParamI` / `kParamF` = un sous-parametre continu (distance, force, exposition). Son STOCK est
//   le DEFAUT DE `gfx.h`, c'est-a-dire la valeur du champ dans un moteur ou personne n'a jamais
//   configure l'option — la definition honnete de « comme si l'option n'existait pas ». Le mettre
//   a zero fabriquerait un etat que le jeu n'a jamais connu (une distance d'ombre nulle n'est pas
//   « absent », c'est « configure a zero »).
// `kExternal` = l'option ne vit pas dans `GfxGlobalSettings`. Le module suit sa valeur voulue et
//   publie son parent ; sa porte est appliquee chez elle et comptee par `on()` a son site.
enum class Kind { kNode, kToggle, kMode, kParamI, kParamF, kExternal };

using GS = GfxGlobalSettings;

struct Row {
  const char* name;
  int parent;
  Kind kind;
  bool GS::*fb;
  int GS::*fi;
  float GS::*ff;
  double stock;
};

// Les champs du bloc PBR n'existent qu'avec OG_FEAT_PBR. Sans lui l'option reste dans la table
// (elle garde son parent et sa place au menu) mais n'a pas de champ : elle est publiee comme NON
// COMPILEE, jamais comme « sans defaut ».
#ifdef OG_FEAT_PBR
#define PB(f) (&GS::f)
#define PI(f) (&GS::f)
#define PF(f) (&GS::f)
#else
#define PB(f) (static_cast<bool GS::*>(nullptr))
#define PI(f) (static_cast<int GS::*>(nullptr))
#define PF(f) (static_cast<float GS::*>(nullptr))
#endif

constexpr bool GS::*kNoB = nullptr;
constexpr int GS::*kNoI = nullptr;
constexpr float GS::*kNoF = nullptr;

// L'ordre DOIT suivre l'enum `Opt` : verifie a l'initialisation, sentinelle si faux.
const Row kOptions[kOptCount] = {
    // nom                     parent              genre           bool                 int                       float                        stock
    {"master", -1, Kind::kNode, &GS::recharged_master, kNoI, kNoF, 0},

    {"water", kMaster, Kind::kNode, &GS::recharged_water, kNoI, kNoF, 0},
    {"lighting", kMaster, Kind::kNode, &GS::recharged_lighting, kNoI, kNoF, 0},
    {"grass", kMaster, Kind::kToggle, &GS::recharged_grass, kNoI, kNoF, 0},
    {"textures", kMaster, Kind::kToggle, &GS::recharged_textures, kNoI, kNoF, 0},
    {"load-custom-assets", kMaster, Kind::kToggle, &GS::load_custom_assets, kNoI, kNoF, 0},
    {"managed-assets", kMaster, Kind::kToggle, &GS::recharged_managed_assets, kNoI, kNoF, 0},
    {"enhanced-models", kMaster, Kind::kToggle, &GS::recharged_enhanced_models, kNoI, kNoF, 0},
    {"foliage-wind", kMaster, Kind::kToggle, &GS::recharged_foliage_wind, kNoI, kNoF, 0},
    {"crisp-title-logo", kMaster, Kind::kToggle, &GS::recharged_crisp_title_logo, kNoI, kNoF, 0},
    {"mesh-browser-checker", kMaster, Kind::kMode, kNoB, &GS::recharged_mesh_browser_checker, kNoF,
     0},

    {"grass-near-dist", kGrass, Kind::kParamF, kNoB, kNoI, &GS::recharged_grass_near_dist, 30.0},
    {"grass-card-dist", kGrass, Kind::kParamF, kNoB, kNoI, &GS::recharged_grass_card_dist, 95.0},
    {"grass-density", kGrass, Kind::kParamI, kNoB, &GS::recharged_grass_density_preset, kNoF,
     (double)grass_bake::kDensityPresetDefault},
    {"grass-precomputed", kGrass, Kind::kToggle, &GS::recharged_grass_precomputed, kNoI, kNoF, 0},
    {"grass-overhang", kGrass, Kind::kToggle, &GS::recharged_grass_overhang, kNoI, kNoF, 0},

    {"ao-mode", kLighting, Kind::kMode, kNoB, &GS::recharged_ao_mode, kNoF, 0},
    {"ao-quality", kAoMode, Kind::kParamI, kNoB, &GS::recharged_ao_quality, kNoF, 1},
    {"ao-strength", kAoMode, Kind::kParamI, kNoB, &GS::recharged_ao_strength, kNoF, 1},
    {"rt-light", kLighting, Kind::kToggle, PB(recharged_rt_light_enable), kNoI, kNoF, 0},
    {"rt-shadow-res", kLighting, Kind::kParamI, kNoB, PI(recharged_rt_shadow_res), kNoF, 2048},
    {"rt-shadow-dist", kLighting, Kind::kParamF, kNoB, kNoI, PF(recharged_rt_shadow_dist), 150.0},
    {"rt-shadow-strength", kLighting, Kind::kParamF, kNoB, kNoI, PF(recharged_rt_shadow_strength),
     0.8},
    {"rt-ambient", kLighting, Kind::kToggle, PB(recharged_rt_ambient_enable), kNoI, kNoF, 0},
    {"rt-ambient-model", kRtAmbient, Kind::kParamI, kNoB, PI(recharged_rt_ambient_model), kNoF, 1},
    {"rt-ambient-strength", kRtAmbient, Kind::kParamF, kNoB, kNoI, PF(recharged_rt_ambient_strength),
     0.2},
    {"rt-ambient-contrast", kRtAmbient, Kind::kParamF, kNoB, kNoI, PF(recharged_rt_ambient_contrast),
     1.0},
    {"hdr", kLighting, Kind::kToggle, &GS::recharged_hdr, kNoI, kNoF, 0},
    {"hdr-knee", kHdr, Kind::kParamF, kNoB, kNoI, &GS::recharged_hdr_knee, 0.96},
    {"hdr-curve", kHdr, Kind::kParamI, kNoB, &GS::recharged_hdr_curve, kNoF, 0},
    {"hdr-exposure", kHdr, Kind::kParamF, kNoB, kNoI, &GS::recharged_hdr_exposure, 1.0},
    {"hdr-output", kLighting, Kind::kExternal, kNoB, kNoI, kNoF, 0},
    {"pbr", kLighting, Kind::kToggle, PB(recharged_pbr_enable), kNoI, kNoF, 0},

    {"pbr-relief", kPbr, Kind::kParamF, kNoB, kNoI, PF(recharged_pbr_texture_relief), 1.5},
    {"pbr-specular", kPbr, Kind::kParamF, kNoB, kNoI, PF(recharged_pbr_spec_intensity), 0.15},
    {"pbr-displacement", kPbr, Kind::kMode, kNoB, PI(recharged_pbr_displacement), kNoF, 0},
    {"pbr-exposure", kPbr, Kind::kParamF, kNoB, kNoI, PF(recharged_pbr_exposure), 1.0},
    {"pbr-isolate", kPbr, Kind::kMode, kNoB, PI(recharged_pbr_isolate), kNoF, 0},
    {"mesh-subdiv", kPbr, Kind::kParamI, kNoB, &GS::recharged_mesh_subdiv_rounds, kNoF, 1},
    {"modern-materials", kPbr, Kind::kToggle, PB(recharged_modern_materials), kNoI, kNoF, 0},
};

#undef PB
#undef PI
#undef PF

// ─── ETAT ────────────────────────────────────────────────────────────────────────────────────
std::mutex g_mutex;

struct State {
  double desired = 0;       // ce que le joueur veut. JAMAIS ecrase par une porte.
  bool desired_set = false; // une valeur a-t-elle deja ete posee ? (avant, on n'ecrit rien)
  double last_written = 0;  // ce que `apply()` a mis dans le champ la derniere fois
  bool written = false;
  uint64_t eval = 0;        // le site a consulte la porte
  uint64_t exec = 0;        // ... et elle etait OUVERTE : le travail a eu lieu
  uint64_t suppressed = 0;  // ... et elle etait FERMEE
  int force = -1;           // balayage de mesure : -1 aucun, 0 force eteint, 1 force au maximum
  uint64_t foreign_writes = 0;
};

State g_state[kOptCount];
bool g_table_ok = false;
bool g_checked = false;

// La valeur « au maximum » d'une option, celle que le controle positif impose pour que chaque
// site ait une chance de tirer. Pour un parametre continu c'est son defaut (il n'a pas d'etat
// « allume »), pour une bascule c'est 1, pour un mode c'est 1 (le premier mode non nul).
double max_value(int opt) {
  switch (kOptions[opt].kind) {
    case Kind::kToggle:
    case Kind::kNode:
    case Kind::kExternal:
      return 1;
    case Kind::kMode:
      return 1;
    case Kind::kParamI:
    case Kind::kParamF:
      return kOptions[opt].stock;
  }
  return kOptions[opt].stock;
}

bool has_field(int opt) {
  const Row& r = kOptions[opt];
  return r.fb != nullptr || r.fi != nullptr || r.ff != nullptr;
}

double read_field(int opt) {
  const Row& r = kOptions[opt];
  const GS& gs = Gfx::g_global_settings;
  if (r.fb) {
    return (gs.*(r.fb)) ? 1 : 0;
  }
  if (r.fi) {
    return (double)(gs.*(r.fi));
  }
  if (r.ff) {
    return (double)(gs.*(r.ff));
  }
  return 0;
}

void write_field(int opt, double v) {
  const Row& r = kOptions[opt];
  GS& gs = Gfx::g_global_settings;
  if (r.fb) {
    gs.*(r.fb) = (v != 0);
  } else if (r.fi) {
    gs.*(r.fi) = (int)std::lround(v);
  } else if (r.ff) {
    gs.*(r.ff) = (float)v;
  }
}

// La valeur telle qu'elle sera REELLEMENT ecrite, apres l'arrondi du champ : c'est elle qu'il
// faut memoriser pour detecter un ecrivain etranger, sinon un `float` compare a un `double`
// signalerait une ecriture etrangere a chaque image.
double quantize(int opt, double v) {
  const Row& r = kOptions[opt];
  if (r.fb) {
    return (v != 0) ? 1 : 0;
  }
  if (r.fi) {
    return (double)(int)std::lround(v);
  }
  if (r.ff) {
    return (double)(float)v;
  }
  return v;
}

// L'etat effectif d'un MAITRE. Il passe par les helpers de gfx.h et pas par le champ, pour que
// les surcharges du harnais et le binaire-temoin gardent leur droit de veto (voir la table).
bool node_active(int opt) {
  switch (opt) {
    case kMaster:
      return Gfx::recharged_master_active();
    case kLighting:
      return Gfx::recharged_lighting_active();
    case kWater:
      return Gfx::recharged_water_active();
    default:
      return true;
  }
}

// Vrai si l'option elle-meme est allumee (sans regarder ses ancetres).
bool self_on_unlocked(int opt) {
  if (kOptions[opt].kind == Kind::kNode) {
    return node_active(opt);
  }
  const State& s = g_state[opt];
  if (s.force == 0) {
    return false;
  }
  const double v = (s.force == 1) ? max_value(opt) : s.desired;
  switch (kOptions[opt].kind) {
    case Kind::kToggle:
    case Kind::kMode:
    case Kind::kExternal:
      return v != 0;
    default:
      // Un sous-parametre continu n'a pas d'etat « eteint » : il ne ferme jamais la porte de ses
      // propres enfants. Ce sont ses ancetres qui decident.
      return true;
  }
}

bool ancestors_on_unlocked(int opt) {
  int p = kOptions[opt].parent;
  int guard = 0;
  while (p >= 0 && guard++ < kOptCount) {
    if (!self_on_unlocked(p) || !ancestors_on_unlocked_step(p)) {
      return false;
    }
    p = kOptions[p].parent;
  }
  return true;
}

// (declaration utilitaire : la boucle ci-dessus n'a pas besoin de recursion ; conservee simple)
bool ancestors_on_unlocked_step(int) {
  return true;
}

double effective_unlocked(int opt) {
  const State& s = g_state[opt];
  const double want = (s.force == 1) ? max_value(opt) : (s.force == 0 ? kOptions[opt].stock : s.desired);
  if (!ancestors_on_unlocked(opt)) {
    return kOptions[opt].stock;
  }
  return want;
}

void check_table_once() {
  if (g_checked) {
    return;
  }
  g_checked = true;
  g_table_ok = true;
  for (int i = 0; i < kOptCount; i++) {
    const int p = kOptions[i].parent;
    if (p < -1 || p >= kOptCount || p == i) {
      g_table_ok = false;
    }
    // aucun cycle : en remontant on doit atteindre -1 en moins de kOptCount pas
    int q = p, guard = 0;
    while (q >= 0 && guard++ <= kOptCount) {
      q = kOptions[q].parent;
    }
    if (guard > kOptCount) {
      g_table_ok = false;
    }
  }
  if (kOptions[kMaster].parent != -1) {
    g_table_ok = false;
  }
}

// ─── LE BALAYAGE DE MESURE ───────────────────────────────────────────────────────────────────
// Il ne tourne QUE quand le harnais nomme cet item. C'est l'INSTRUMENT qui est sous drapeau,
// jamais le correctif : hors mesure, le module applique les portes et ne force rien.
//
// POURQUOI UN CONTROLE POSITIF DANS LA MEME COURSE. Une fenetre « parent eteint » ou la
// dependante rend exec=0 ne prouve rien si elle rendait DEJA zero parent allume — c'est la porte
// verte par inaction. Chaque fenetre eteinte est donc precedee d'une fenetre ou TOUTES les
// options sont forcees au maximum : `exec_on` est le temoin de couverture, et une option dont
// `exec_on` vaut zero est declaree NON COUVERTE, jamais « sans defaut ».
const int kParents[] = {kMaster, kLighting, kWater,   kGrass,
                        kAoMode, kPbr,      kRtAmbient, kEnhancedModels};
constexpr int kParentCount = (int)(sizeof(kParents) / sizeof(kParents[0]));

constexpr uint64_t kWarmFrames = 60;
constexpr uint64_t kWindowFrames = 90;

struct Sweep {
  bool wanted = false;
  bool started = false;
  bool done = false;
  uint64_t frame = 0;
  int stage = -1;  // -1 chauffe, 0 = tout allume, 1..kParentCount = un parent eteint, puis fin
  uint64_t exec_on[kOptCount] = {0};
  uint64_t exec_off[kParentCount][kOptCount] = {{0}};
  uint64_t mark[kOptCount] = {0};
  double desired_before[kOptCount] = {0};
  bool desired_snapped = false;
  int value_restored = -1;
  uint64_t windows_done = 0;
};

Sweep g_sweep;

void sweep_force_all(int f) {
  for (int i = 0; i < kOptCount; i++) {
    if (kOptions[i].kind == Kind::kNode && i != kMaster && i != kLighting && i != kWater) {
      continue;
    }
    g_state[i].force = f;
  }
}

void sweep_snapshot_marks() {
  for (int i = 0; i < kOptCount; i++) {
    g_sweep.mark[i] = g_state[i].exec;
  }
}

void sweep_collect(uint64_t* into) {
  for (int i = 0; i < kOptCount; i++) {
    into[i] = g_state[i].exec - g_sweep.mark[i];
  }
}

// ─── RECENSEMENT DU MENU ─────────────────────────────────────────────────────────────────────
struct MenuState {
  bool open = false;
  bool ever = false;
  uint64_t rows = 0;
  uint64_t unknown = 0;      // une rangee que la table ne connait pas
  uint64_t misplaced = 0;    // une rangee dessinee dans une page qui n'est pas celle de son parent
  std::string parents;       // « opt:parent,opt:parent,... » — publie tel quel
};

MenuState g_menu;

// La page ou une option DOIT vivre, deduite de son parent. C'est la meme colonne que la porte :
// un sous-menu qui derive de la hierarchie se voit tout de suite.
const char* expected_page(int opt) {
  int p = kOptions[opt].parent;
  if (p == kGrass || opt == kGrass) {
    return "grass";
  }
  if (opt == kLighting) {
    return "lighting";
  }
  while (p >= 0) {
    if (p == kLighting) {
      return "lighting";
    }
    if (p == kGrass) {
      return "grass";
    }
    p = kOptions[p].parent;
  }
  return "recharged";
}

void publish_all_unlocked();

}  // namespace

// ─── API ─────────────────────────────────────────────────────────────────────────────────────

const char* name(int opt) {
  return (opt >= 0 && opt < kOptCount) ? kOptions[opt].name : "";
}

int by_name(const char* id) {
  if (!id || !id[0]) {
    return -1;
  }
  for (int i = 0; i < kOptCount; i++) {
    if (std::strcmp(kOptions[i].name, id) == 0) {
      return i;
    }
  }
  return -1;
}

int parent(int opt) {
  return (opt >= 0 && opt < kOptCount) ? kOptions[opt].parent : -1;
}

void set(int opt, double value) {
  if (opt < 0 || opt >= kOptCount) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    check_table_once();
    g_state[opt].desired = value;
    g_state[opt].desired_set = true;
  }
  apply();
}

double desired(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_state[opt].desired;
}

double effective(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return effective_unlocked(opt);
}

bool disabled_by_ancestor(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  return !ancestors_on_unlocked(opt);
}

bool on(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const bool open = effective_unlocked(opt) != 0 && ancestors_on_unlocked(opt);
  g_state[opt].eval++;
  if (open) {
    g_state[opt].exec++;
  } else {
    g_state[opt].suppressed++;
  }
  return open;
}

int mode(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  const double v = ancestors_on_unlocked(opt) ? effective_unlocked(opt) : kOptions[opt].stock;
  g_state[opt].eval++;
  if (v != 0) {
    g_state[opt].exec++;
  } else {
    g_state[opt].suppressed++;
  }
  return (int)std::lround(v);
}

void apply() {
  std::lock_guard<std::mutex> lock(g_mutex);
  check_table_once();
  for (int i = 0; i < kOptCount; i++) {
    const Row& r = kOptions[i];
    if (r.kind == Kind::kNode || r.kind == Kind::kExternal || !has_field(i)) {
      continue;
    }
    State& s = g_state[i];
    if (!s.desired_set) {
      continue;  // personne n'a encore rien voulu : on ne touche pas au defaut du moteur
    }
    // AVANT d'ecrire : le champ porte-t-il encore ce que NOUS y avons mis ? Sinon quelqu'un
    // d'autre l'a pose, donc il court-circuite la porte. C'est l'unique entree de
    // `gating_ungated_sites`, et elle monte a la moindre affectation directe.
    if (s.written && read_field(i) != s.last_written) {
      s.foreign_writes++;
    }
    const double v = quantize(i, effective_unlocked(i));
    write_field(i, v);
    s.last_written = v;
    s.written = true;
  }
}

void menu_begin() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_menu.open = true;
  g_menu.ever = true;
  g_menu.rows = 0;
  g_menu.unknown = 0;
  g_menu.misplaced = 0;
  g_menu.parents.clear();
}

void menu_row(const char* page, const char* opt_id) {
  const int opt = by_name(opt_id);
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_menu.open) {
    return;
  }
  g_menu.rows++;
  if (opt < 0) {
    g_menu.unknown++;
    return;
  }
  const char* want = expected_page(opt);
  if (!page || std::strcmp(page, want) != 0) {
    g_menu.misplaced++;
  }
  if (!g_menu.parents.empty()) {
    g_menu.parents += ",";
  }
  const int p = kOptions[opt].parent;
  g_menu.parents += kOptions[opt].name;
  g_menu.parents += ":";
  g_menu.parents += (p >= 0 ? kOptions[p].name : "-");
}

void menu_end() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_menu.open = false;
}

void tick() {
  apply();
  std::lock_guard<std::mutex> lock(g_mutex);

  if (!g_sweep.started) {
    g_sweep.started = true;
    g_sweep.wanted = autoport_proof::feature_is("recharged-gating-real");
  }

  if (g_sweep.wanted && !g_sweep.done) {
    g_sweep.frame++;
    if (!g_sweep.desired_snapped) {
      for (int i = 0; i < kOptCount; i++) {
        g_sweep.desired_before[i] = g_state[i].desired;
      }
      g_sweep.desired_snapped = true;
    }
    const uint64_t f = g_sweep.frame;
    if (g_sweep.stage < 0 && f >= kWarmFrames) {
      // fenetre TEMOIN : tout au maximum. Sans elle, un zero plus bas ne parlerait de rien.
      g_sweep.stage = 0;
      sweep_force_all(1);
      sweep_snapshot_marks();
      g_sweep.frame = 0;
    } else if (g_sweep.stage == 0 && f >= kWindowFrames) {
      sweep_collect(g_sweep.exec_on);
      g_sweep.windows_done++;
      g_sweep.stage = 1;
      sweep_force_all(1);
      g_state[kParents[0]].force = 0;
      sweep_snapshot_marks();
      g_sweep.frame = 0;
    } else if (g_sweep.stage >= 1 && g_sweep.stage <= kParentCount && f >= kWindowFrames) {
      sweep_collect(g_sweep.exec_off[g_sweep.stage - 1]);
      g_sweep.windows_done++;
      g_sweep.stage++;
      if (g_sweep.stage <= kParentCount) {
        sweep_force_all(1);
        g_state[kParents[g_sweep.stage - 1]].force = 0;
        sweep_snapshot_marks();
        g_sweep.frame = 0;
      } else {
        // fin : on RELACHE tout et on verifie que la valeur voulue a survecu au balayage.
        sweep_force_all(-1);
        g_sweep.value_restored = 1;
        for (int i = 0; i < kOptCount; i++) {
          if (g_state[i].desired != g_sweep.desired_before[i]) {
            g_sweep.value_restored = 0;
          }
        }
        g_sweep.done = true;
      }
    }
  }

  publish_all_unlocked();
}

namespace {

void publish_all_unlocked() {
  // ── la partie qui est vraie de TOUTE course, mesuree ou non ──
  uint64_t foreign = 0;
  uint64_t not_compiled = 0;
  std::string foreign_names;
  for (int i = 0; i < kOptCount; i++) {
    const Row& r = kOptions[i];
    if (r.kind != Kind::kNode && r.kind != Kind::kExternal && !has_field(i)) {
      not_compiled++;
      continue;
    }
    if (g_state[i].foreign_writes) {
      foreign++;
      if (!foreign_names.empty()) {
        foreign_names += ",";
      }
      foreign_names += r.name;
    }
  }
  autoport_proof::publish("gating_ungated_sites", foreign);
  autoport_proof::publish("gating_options", (uint64_t)kOptCount);
  autoport_proof::publish("gating_not_compiled", not_compiled);
  autoport_proof::publish("gating_table_ok", g_table_ok ? 1 : 0);
  if (!foreign_names.empty()) {
    autoport_proof::publish_text("gating_ungated_names", foreign_names.c_str());
  }

  // ── le recensement du menu ──
  autoport_proof::publish("gating_menu_rows", g_menu.rows);
  autoport_proof::publish("gating_menu_unknown", g_menu.unknown);
  autoport_proof::publish("gating_menu_misplaced", g_menu.misplaced);
  autoport_proof::publish("gating_menu_seen", g_menu.ever ? 1 : 0);
  if (!g_menu.parents.empty()) {
    autoport_proof::publish_text("gating_menu_parent", g_menu.parents.c_str());
  }

  // ── le balayage ──
  uint64_t effet = 0, uncovered = 0, covered = 0;
  std::string defect_names;
  if (g_sweep.done) {
    for (int i = 0; i < kOptCount; i++) {
      if (kOptions[i].kind == Kind::kNode) {
        continue;
      }
      if (g_sweep.exec_on[i] == 0) {
        uncovered++;
        continue;
      }
      covered++;
      for (int p = 0; p < kParentCount; p++) {
        // l'option est-elle sous CE parent ?
        int q = kOptions[i].parent, guard = 0;
        bool under = false;
        while (q >= 0 && guard++ < kOptCount) {
          if (q == kParents[p]) {
            under = true;
            break;
          }
          q = kOptions[q].parent;
        }
        if (!under) {
          continue;
        }
        if (g_sweep.exec_off[p][i] > 0) {
          effet++;
          if (!defect_names.empty()) {
            defect_names += ",";
          }
          defect_names += kOptions[i].name;
          defect_names += "<";
          defect_names += kOptions[kParents[p]].name;
          break;
        }
      }
    }
  }
  autoport_proof::publish("gating_sweep_done", g_sweep.done ? 1 : 0);
  autoport_proof::publish("gating_sweep_windows", g_sweep.windows_done);
  autoport_proof::publish("gating_effect_defects", effet);
  autoport_proof::publish("gating_covered", covered);
  autoport_proof::publish("gating_uncovered", uncovered);
  autoport_proof::publish("gating_value_restored",
                          g_sweep.value_restored < 0 ? 0 : (uint64_t)g_sweep.value_restored);
  if (!defect_names.empty()) {
    autoport_proof::publish_text("gating_effect_defect_names", defect_names.c_str());
  }

  // ── LE VERDICT ────────────────────────────────────────────────────────────────────────────
  // LA VACUITE EST UN ECHEC, PAS UN ZERO. Table incoherente, balayage non termine, menu jamais
  // recense, ou pas une seule option couverte par le temoin positif : le module publie une
  // SENTINELLE hors de portee de la porte. Un compteur qui n'a rien regarde ne doit jamais dire
  // « zero defaut » — c'est la lecon de `settings_case_l10n`.
  constexpr uint64_t kVacuous = 9000;
  uint64_t defects = 0;
  if (!g_table_ok) {
    defects = kVacuous + 1;
  } else if (!g_sweep.wanted) {
    // Course ordinaire du joueur : le module applique les portes, il ne mesure pas. On ne publie
    // PAS un zero qui passerait une porte, on publie la sentinelle « pas mesure ».
    defects = kVacuous + 2;
  } else if (!g_sweep.done) {
    defects = kVacuous + 3;
  } else if (!g_menu.ever) {
    defects = kVacuous + 4;
  } else if (covered == 0) {
    defects = kVacuous + 5;
  } else {
    defects = effet + foreign + uncovered + g_menu.unknown + g_menu.misplaced +
              (g_sweep.value_restored == 1 ? 0 : 1);
  }
  autoport_proof::publish("gating_defects", defects);
}

}  // namespace
}  // namespace recharged_gating
