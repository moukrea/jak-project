#include "game/system/recharged_gating.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>

#include "game/graphics/gfx.h"
#include "game/system/autoport_proof.h"

namespace recharged_gating {
namespace {

// ─── LA TABLE ────────────────────────────────────────────────────────────────────────────────
// Une ligne par option, et le PARENT est ici — nulle part ailleurs. Le grisage du menu, la porte
// du moteur et le recensement de preuve lisent tous les trois CETTE colonne.
//
// `kNode` = un maitre (master / eclairage / eau). Son champ recoit la valeur VOULUE telle quelle,
// SANS composition : ce sont les helpers de gfx.h qui composent, et eux seuls, parce qu'ils
// ajoutent les surcharges du harnais (`debug.opengoal.recharged`, `OG_LIGHTING`, l'epinglage
// refset, le binaire-temoin AUTOPORT_ORIGIN_ABLATE). Les court-circuiter ici casserait le jeu de
// references et la campagne HDR, qui epinglent ces trois drapeaux ; ce n'est pas le perimetre.
//
// `kToggle` / `kMode` = ce que le joueur allume et eteint. STOCK = 0 : eteint doit valoir ABSENT.
// `kParamI` / `kParamF` = un sous-parametre continu (distance, force, exposition). Son STOCK est
//   le DEFAUT DE `gfx.h`, c'est-a-dire la valeur du champ dans un moteur ou personne n'a jamais
//   configure l'option — la definition honnete de « comme si l'option n'existait pas ». Le mettre
//   a zero fabriquerait un etat que le jeu n'a jamais connu (une distance d'ombre nulle n'est pas
//   « absent », c'est « configure a zero »).
// `kExternal` = l'option ne vit pas dans `GfxGlobalSettings` (la sortie HDR a son propre
//   `std::atomic` dans hdr_output.cpp). Le module suit sa valeur voulue et publie son parent ; sa
//   porte est appliquee chez elle (hdr_output.cpp:257) et comptee par `on()` a son site.
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
// COMPILEE (`gating_not_compiled`), jamais comme « sans defaut ».
#ifdef OG_FEAT_PBR
#define PB(f) (&GS::f)
#define PI(f) (&GS::f)
#define PF(f) (&GS::f)
#else
#define PB(f) (static_cast<bool GS::*>(nullptr))
#define PI(f) (static_cast<int GS::*>(nullptr))
#define PF(f) (static_cast<float GS::*>(nullptr))
#endif

#define NOB (static_cast<bool GS::*>(nullptr))
#define NOI (static_cast<int GS::*>(nullptr))
#define NOF (static_cast<float GS::*>(nullptr))

// L'ordre DOIT suivre l'enum `Opt` : verifie a l'initialisation (`check_table_once`), et une
// table qui ne se verifie pas publie une SENTINELLE au lieu d'un zero.
const Row kOptions[kOptCount] = {
    {"master", -1, Kind::kNode, &GS::recharged_master, NOI, NOF, 0},

    {"water", kMaster, Kind::kNode, &GS::recharged_water, NOI, NOF, 0},
    {"lighting", kMaster, Kind::kNode, &GS::recharged_lighting, NOI, NOF, 0},
    {"grass", kMaster, Kind::kToggle, &GS::recharged_grass, NOI, NOF, 0},
    {"textures", kMaster, Kind::kToggle, &GS::recharged_textures, NOI, NOF, 0},
    {"load-custom-assets", kMaster, Kind::kToggle, &GS::load_custom_assets, NOI, NOF, 0},
    {"managed-assets", kMaster, Kind::kToggle, &GS::recharged_managed_assets, NOI, NOF, 0},
    {"enhanced-models", kMaster, Kind::kToggle, &GS::recharged_enhanced_models, NOI, NOF, 0},
    {"foliage-wind", kMaster, Kind::kToggle, &GS::recharged_foliage_wind, NOI, NOF, 0},
    {"crisp-title-logo", kMaster, Kind::kToggle, &GS::recharged_crisp_title_logo, NOI, NOF, 0},
    {"mesh-browser-checker", kMaster, Kind::kMode, NOB, &GS::recharged_mesh_browser_checker, NOF, 0},

    {"grass-near-dist", kGrass, Kind::kParamF, NOB, NOI, &GS::recharged_grass_near_dist, 30.0},
    {"grass-card-dist", kGrass, Kind::kParamF, NOB, NOI, &GS::recharged_grass_card_dist, 95.0},
    {"grass-density", kGrass, Kind::kParamI, NOB, &GS::recharged_grass_density_preset, NOF,
     (double)grass_bake::kDensityPresetDefault},
    {"grass-precomputed", kGrass, Kind::kToggle, &GS::recharged_grass_precomputed, NOI, NOF, 0},
    {"grass-overhang", kGrass, Kind::kToggle, &GS::recharged_grass_overhang, NOI, NOF, 0},

    {"ao-mode", kLighting, Kind::kMode, NOB, &GS::recharged_ao_mode, NOF, 0},
    {"ao-quality", kAoMode, Kind::kParamI, NOB, &GS::recharged_ao_quality, NOF, 1},
    {"ao-strength", kAoMode, Kind::kParamI, NOB, &GS::recharged_ao_strength, NOF, 1},
    {"rt-light", kLighting, Kind::kToggle, PB(recharged_rt_light_enable), NOI, NOF, 0},
    {"rt-shadow-res", kLighting, Kind::kParamI, NOB, PI(recharged_rt_shadow_res), NOF, 2048},
    {"rt-shadow-dist", kLighting, Kind::kParamF, NOB, NOI, PF(recharged_rt_shadow_dist), 150.0},
    {"rt-shadow-strength", kLighting, Kind::kParamF, NOB, NOI, PF(recharged_rt_shadow_strength),
     0.8},
    {"rt-ambient", kLighting, Kind::kToggle, PB(recharged_rt_ambient_enable), NOI, NOF, 0},
    {"rt-ambient-model", kRtAmbient, Kind::kParamI, NOB, PI(recharged_rt_ambient_model), NOF, 1},
    {"rt-ambient-strength", kRtAmbient, Kind::kParamF, NOB, NOI, PF(recharged_rt_ambient_strength),
     0.2},
    {"rt-ambient-contrast", kRtAmbient, Kind::kParamF, NOB, NOI, PF(recharged_rt_ambient_contrast),
     1.0},
    {"hdr", kLighting, Kind::kToggle, &GS::recharged_hdr, NOI, NOF, 0},
    {"hdr-knee", kHdr, Kind::kParamF, NOB, NOI, &GS::recharged_hdr_knee, 0.96},
    {"hdr-curve", kHdr, Kind::kParamI, NOB, &GS::recharged_hdr_curve, NOF, 0},
    {"hdr-exposure", kHdr, Kind::kParamF, NOB, NOI, &GS::recharged_hdr_exposure, 1.0},
    {"hdr-output", kLighting, Kind::kExternal, NOB, NOI, NOF, 0},
    {"pbr", kLighting, Kind::kToggle, PB(recharged_pbr_enable), NOI, NOF, 0},

    {"pbr-relief", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_texture_relief), 1.5},
    {"pbr-specular", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_spec_intensity), 0.15},
    {"pbr-displacement", kPbr, Kind::kMode, NOB, PI(recharged_pbr_displacement), NOF, 0},
    {"pbr-exposure", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_exposure), 1.0},
    {"pbr-isolate", kPbr, Kind::kMode, NOB, PI(recharged_pbr_isolate), NOF, 0},
    {"mesh-subdiv", kPbr, Kind::kParamI, NOB, &GS::recharged_mesh_subdiv_rounds, NOF, 1},
    {"modern-materials", kPbr, Kind::kToggle, PB(recharged_modern_materials), NOI, NOF, 0},
};

#undef PB
#undef PI
#undef PF
#undef NOB
#undef NOI
#undef NOF

// ─── ETAT ────────────────────────────────────────────────────────────────────────────────────
std::recursive_mutex g_mutex;

struct State {
  double desired = 0;        // ce que le joueur veut. JAMAIS ecrase par une porte.
  bool desired_set = false;  // avant la premiere volonte, on ne touche pas au defaut du moteur
  double last_written = 0;   // ce que `apply()` a mis dans le champ la derniere fois
  bool written = false;
  // Les compteurs sont ATOMIQUES et `on()` / `mode()` ne prennent AUCUN verrou : ces deux
  // fonctions sont appelees par DESSIN sur le fil GL (background_common.cpp:1077 et ses
  // voisines). Un mutex a cet endroit ferait payer a chaque dessin le prix d'un instrument —
  // dans un item dont le motif est justement le cout des options grisees. La lecture non
  // verrouillee de `desired` / `force` est la meme course benigne que le cache de 0,25 s des
  // maitres (gfx.h) : deux lecteurs de la meme image peuvent voir deux valeurs pendant la
  // fenetre d'un basculement, et le balayage laisse expres 90 images par fenetre.
  std::atomic<uint64_t> eval{0};        // le site a consulte la porte
  std::atomic<uint64_t> exec{0};        // ... et elle etait OUVERTE : le travail a eu lieu
  std::atomic<uint64_t> suppressed{0};  // ... et elle etait FERMEE
  std::atomic<int> force{-1};           // balayage : -1 aucun, 0 force eteint, 1 force au maximum
  std::atomic<uint64_t> foreign_writes{0};
};

State g_state[kOptCount];
bool g_table_ok = false;
bool g_checked = false;

bool is_node(int opt) {
  return kOptions[opt].kind == Kind::kNode;
}

bool has_field(int opt) {
  const Row& r = kOptions[opt];
  return r.fb != nullptr || r.fi != nullptr || r.ff != nullptr;
}

// La valeur « au maximum » : celle que le controle positif impose pour que chaque site ait une
// chance de tirer. Une bascule ou un mode montent a 1 ; un parametre continu n'a pas d'etat
// « allume », il garde son defaut.
double max_value(int opt) {
  switch (kOptions[opt].kind) {
    case Kind::kNode:
    case Kind::kToggle:
    case Kind::kMode:
    case Kind::kExternal:
      return 1;
    default:
      return kOptions[opt].stock;
  }
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

// La valeur telle qu'elle sera REELLEMENT dans le champ apres conversion : c'est elle qu'il faut
// memoriser, sinon un `float` compare a un `double` signalerait une ecriture etrangere a chaque
// image et `gating_ungated_sites` serait un faux rouge permanent.
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

// La valeur que le champ d'un MAITRE doit porter : la volonte du joueur, telle quelle. La
// composition (master > eclairage > eau, plus les surcharges du harnais) reste chez gfx.h.
double node_field_value(int opt) {
  const State& s = g_state[opt];
  const int f = s.force.load(std::memory_order_relaxed);
  if (f == 0) {
    return 0;
  }
  if (f == 1) {
    return 1;
  }
  return s.desired;
}

// L'etat effectif d'un MAITRE, lu par les helpers de gfx.h — donc surcharges du harnais et
// binaire-temoin compris. Le forçage du balayage est deja dans le champ (voir `apply`).
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

// L'option elle-meme est-elle allumee, sans regarder ses ancetres ?
bool self_on(int opt) {
  if (is_node(opt)) {
    return node_active(opt);
  }
  const State& s = g_state[opt];
  const int f = s.force.load(std::memory_order_relaxed);
  if (f == 0) {
    return false;
  }
  const double v = (f == 1) ? max_value(opt) : s.desired;
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

bool ancestors_on(int opt) {
  int p = kOptions[opt].parent;
  int guard = 0;
  while (p >= 0 && guard++ <= kOptCount) {
    if (!self_on(p)) {
      return false;
    }
    p = kOptions[p].parent;
  }
  return true;
}

double effective_value(int opt) {
  if (!ancestors_on(opt)) {
    return kOptions[opt].stock;
  }
  const State& s = g_state[opt];
  const int f = s.force.load(std::memory_order_relaxed);
  if (f == 0) {
    return kOptions[opt].stock;
  }
  if (f == 1) {
    return max_value(opt);
  }
  return s.desired;
}

void check_table_once() {
  if (g_checked) {
    return;
  }
  g_checked = true;
  g_table_ok = kOptions[kMaster].parent == -1;
  for (int i = 0; i < kOptCount; i++) {
    const int p = kOptions[i].parent;
    if (p < -1 || p >= kOptCount || p == i) {
      g_table_ok = false;
      continue;
    }
    int q = p, guard = 0;
    while (q >= 0 && guard <= kOptCount) {
      q = kOptions[q].parent;
      guard++;
    }
    if (guard > kOptCount) {
      g_table_ok = false;
    }
  }
  // La table est indexee PAR L'ENUM : si les deux derivent, chaque porte designe une autre
  // option et tous les chiffres deviennent faux sans qu'aucun ne soit absent. Quelques ancres
  // reparties dans la table suffisent a le voir.
  // AMORCAGE DE LA VOLONTE. Plusieurs options n'ont AUCUN ecrivain (`recharged_hdr`,
  // `recharged_hdr_knee/curve/exposure`, `recharged_pbr_exposure`) : elles vivent sur le defaut
  // de `gfx.h` et aucune rangee de menu ne les touche. Sans cet amorcage leur `desired` vaudrait
  // 0, `on()` les declarerait eteintes et la chaine HDR s'arreterait — un changement de RENDU,
  // que cet item n'a pas le droit de faire. On part donc de ce que le champ porte deja.
  for (int i = 0; i < kOptCount; i++) {
    if (has_field(i)) {
      g_state[i].desired = read_field(i);
      g_state[i].desired_set = true;
    }
  }
  const struct {
    int opt;
    const char* name;
  } anchors[] = {{kMaster, "master"},   {kLighting, "lighting"}, {kGrassOverhang, "grass-overhang"},
                 {kAoMode, "ao-mode"},  {kHdrOutput, "hdr-output"}, {kPbr, "pbr"},
                 {kModernMaterials, "modern-materials"}};
  for (const auto& a : anchors) {
    if (std::strcmp(kOptions[a.opt].name, a.name) != 0) {
      g_table_ok = false;
    }
  }
}

// ─── LE BALAYAGE DE MESURE ───────────────────────────────────────────────────────────────────
// Il ne tourne QUE quand le harnais nomme cet item : c'est l'INSTRUMENT qui est sous drapeau,
// jamais le correctif. Hors mesure, le module applique les portes et ne force rien.
//
// POURQUOI UN CONTROLE POSITIF DANS LA MEME COURSE. Une fenetre « parent eteint » ou la
// dependante rend exec=0 ne prouve rien si elle rendait DEJA zero parent allume — c'est la porte
// verte par inaction, et sur l'appareil de l'owner c'est le cas par defaut (son settings.ini
// porte `pbr-materials? = #f`). Chaque fenetre eteinte est donc precedee d'une fenetre ou TOUTES
// les options sont forcees au maximum : `exec_on` est le temoin de couverture, et une option dont
// `exec_on` vaut zero est comptee NON COUVERTE — un defaut, jamais un silence.
const int kParents[] = {kLighting, kPbr,      kAoMode,        kRtAmbient,
                        kGrass,    kWater,    kEnhancedModels, kMaster};
constexpr int kParentCount = (int)(sizeof(kParents) / sizeof(kParents[0]));

constexpr uint64_t kWarmFrames = 60;
constexpr uint64_t kWindowFrames = 90;

struct Sweep {
  bool wanted = false;
  bool started = false;
  bool done = false;
  uint64_t frame = 0;
  int stage = -1;  // -1 chauffe, 0 temoin (tout au max), 1..kParentCount un parent eteint
  uint64_t exec_on[kOptCount] = {0};
  uint64_t exec_off[kParentCount][kOptCount] = {{0}};
  uint64_t mark[kOptCount] = {0};
  double desired_before[kOptCount] = {0};
  bool desired_snapped = false;
  int value_restored = -1;
  uint64_t windows_done = 0;
};

Sweep g_sweep;

void force_all(int f) {
  for (int i = 0; i < kOptCount; i++) {
    g_state[i].force.store(f, std::memory_order_relaxed);
  }
}

void snapshot_marks() {
  for (int i = 0; i < kOptCount; i++) {
    g_sweep.mark[i] = g_state[i].exec.load(std::memory_order_relaxed);
  }
}

void collect(uint64_t* into) {
  for (int i = 0; i < kOptCount; i++) {
    into[i] = g_state[i].exec.load(std::memory_order_relaxed) - g_sweep.mark[i];
  }
}

// ─── RECENSEMENT DU MENU ─────────────────────────────────────────────────────────────────────
struct MenuState {
  bool open = false;
  bool ever = false;
  uint64_t rows = 0;
  uint64_t unknown = 0;    // une rangee que la table ne connait pas
  uint64_t misplaced = 0;  // une rangee dessinee ailleurs que dans la page de son parent
  std::string parents;     // « option:parent,... », publie tel quel
};

MenuState g_menu;

// La page ou une option DOIT vivre, DEDUITE DE SON PARENT. C'est la meme colonne que la porte :
// un sous-menu qui derive de la hierarchie se voit immediatement.
const char* expected_page(int opt) {
  if (opt == kGrass || opt == kLighting) {
    return "recharged";  // la ligne d'ENTREE du sous-menu vit dans la page mere
  }
  int p = kOptions[opt].parent;
  int guard = 0;
  while (p >= 0 && guard++ <= kOptCount) {
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

void publish_all();

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
    std::lock_guard<std::recursive_mutex> lock(g_mutex);
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
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  return g_state[opt].desired;
}

double effective(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  return effective_value(opt);
}

bool disabled_by_ancestor(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return false;
  }
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  return !ancestors_on(opt);
}

bool on(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return false;
  }
  const bool open = ancestors_on(opt) && self_on(opt);
  g_state[opt].eval.fetch_add(1, std::memory_order_relaxed);
  (open ? g_state[opt].exec : g_state[opt].suppressed).fetch_add(1, std::memory_order_relaxed);
  return open;
}

int mode(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  const int v = ancestors_on(opt) ? (int)std::lround(effective_value(opt)) : 0;
  g_state[opt].eval.fetch_add(1, std::memory_order_relaxed);
  (v != 0 ? g_state[opt].exec : g_state[opt].suppressed).fetch_add(1, std::memory_order_relaxed);
  return v;
}

void apply() {
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  check_table_once();
  // Les MAITRES d'abord : tout le reste depend de leur champ, que gfx.h relit.
  for (int pass = 0; pass < 2; pass++) {
    for (int i = 0; i < kOptCount; i++) {
      const Row& r = kOptions[i];
      const bool node = is_node(i);
      if ((pass == 0) != node) {
        continue;
      }
      if (r.kind == Kind::kExternal || !has_field(i)) {
        continue;
      }
      State& s = g_state[i];
      if (!s.desired_set && s.force.load(std::memory_order_relaxed) < 0) {
        continue;  // personne n'a encore rien voulu : le defaut du moteur reste
      }
      // AVANT d'ecrire : le champ porte-t-il encore ce que NOUS y avons mis ? Sinon quelqu'un
      // d'autre l'a pose, donc il court-circuite la porte. C'est l'unique entree de
      // `gating_ungated_sites`, et elle monte a la moindre affectation directe du champ.
      if (s.written && read_field(i) != s.last_written) {
        s.foreign_writes.fetch_add(1, std::memory_order_relaxed);
      }
      const double v = quantize(i, node ? node_field_value(i) : effective_value(i));
      write_field(i, v);
      s.last_written = v;
      s.written = true;
    }
  }
}

void menu_begin() {
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  g_menu.open = true;
  g_menu.ever = true;
  g_menu.rows = 0;
  g_menu.unknown = 0;
  g_menu.misplaced = 0;
  g_menu.parents.clear();
}

void menu_row(const char* page, const char* opt_id) {
  const int opt = by_name(opt_id);
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  if (!g_menu.open) {
    return;
  }
  g_menu.rows++;
  if (opt < 0) {
    g_menu.unknown++;
    return;
  }
  if (!page || std::strcmp(page, expected_page(opt)) != 0) {
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
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  g_menu.open = false;
}

void tick() {
  std::lock_guard<std::recursive_mutex> lock(g_mutex);

  if (!g_sweep.started) {
    g_sweep.started = true;
    g_sweep.wanted = autoport_proof::feature_is("recharged-gating-real");
  }

  if (g_sweep.wanted && !g_sweep.done) {
    if (!g_sweep.desired_snapped) {
      for (int i = 0; i < kOptCount; i++) {
        g_sweep.desired_before[i] = g_state[i].desired;
      }
      g_sweep.desired_snapped = true;
    }
    g_sweep.frame++;
    const uint64_t f = g_sweep.frame;
    if (g_sweep.stage < 0) {
      if (f >= kWarmFrames) {
        g_sweep.stage = 0;
        force_all(1);
        snapshot_marks();
        g_sweep.frame = 0;
      }
    } else if (f >= kWindowFrames) {
      if (g_sweep.stage == 0) {
        collect(g_sweep.exec_on);
      } else {
        collect(g_sweep.exec_off[g_sweep.stage - 1]);
      }
      g_sweep.windows_done++;
      g_sweep.stage++;
      if (g_sweep.stage <= kParentCount) {
        force_all(1);
        g_state[kParents[g_sweep.stage - 1]].force.store(0, std::memory_order_relaxed);
        snapshot_marks();
        g_sweep.frame = 0;
      } else {
        // Fin : on RELACHE tout, et on verifie que la valeur voulue a survecu au balayage —
        // c'est la memoire que l'owner demande, mesuree apres un vrai aller-retour OFF/ON.
        force_all(-1);
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

  apply();
  publish_all();
}

namespace {

void publish_all() {
  // ── vrai de TOUTE course, mesuree ou non ──
  uint64_t foreign = 0, not_compiled = 0;
  std::string foreign_names;
  for (int i = 0; i < kOptCount; i++) {
    const Row& r = kOptions[i];
    if (r.kind != Kind::kExternal && !has_field(i)) {
      not_compiled++;
      continue;
    }
    if (g_state[i].foreign_writes.load(std::memory_order_relaxed)) {
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

  // ── le menu ──
  autoport_proof::publish("gating_menu_rows", g_menu.rows);
  autoport_proof::publish("gating_menu_unknown", g_menu.unknown);
  autoport_proof::publish("gating_menu_misplaced", g_menu.misplaced);
  autoport_proof::publish("gating_menu_seen", g_menu.ever ? 1 : 0);
  if (!g_menu.parents.empty()) {
    autoport_proof::publish_text("gating_menu_parent", g_menu.parents.c_str());
  }

  // ── le balayage ──
  uint64_t effet = 0, uncovered = 0, covered = 0;
  std::string defect_names, uncovered_names;
  if (g_sweep.done) {
    for (int i = 0; i < kOptCount; i++) {
      if (i == kMaster) {
        continue;  // la racine n'a aucun ancetre a trahir. Les DEUX autres maitres, si :
                   // « master OFF => aucun chemin Recharged execute » se lit sur eux aussi.
      }
      if (g_sweep.exec_on[i] == 0) {
        uncovered++;
        if (uncovered_names.size() < 400) {
          if (!uncovered_names.empty()) {
            uncovered_names += ",";
          }
          uncovered_names += kOptions[i].name;
        }
        continue;
      }
      covered++;
      for (int p = 0; p < kParentCount; p++) {
        int q = kOptions[i].parent, guard = 0;
        bool under = false;
        while (q >= 0 && guard++ <= kOptCount) {
          if (q == kParents[p]) {
            under = true;
            break;
          }
          q = kOptions[q].parent;
        }
        if (under && g_sweep.exec_off[p][i] > 0) {
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
                          g_sweep.value_restored == 1 ? 1 : 0);
  if (!defect_names.empty()) {
    autoport_proof::publish_text("gating_effect_defect_names", defect_names.c_str());
  }
  if (!uncovered_names.empty()) {
    autoport_proof::publish_text("gating_uncovered_names", uncovered_names.c_str());
  }

  // ── LE VERDICT ────────────────────────────────────────────────────────────────────────────
  // LA VACUITE EST UN ECHEC, PAS UN ZERO. Table incoherente, balayage non termine, menu jamais
  // recense, ou pas une seule option couverte par le temoin positif : on publie une SENTINELLE
  // hors de portee de la porte. Un compteur qui n'a rien regarde ne doit jamais dire « zero
  // defaut » — c'est la lecon de `settings_case_l10n`.
  constexpr uint64_t kVacuous = 9000;
  uint64_t defects;
  if (!g_table_ok) {
    defects = kVacuous + 1;
  } else if (!g_sweep.wanted) {
    // Course ordinaire du joueur : le module applique les portes, il ne mesure pas. On ne publie
    // pas un zero qui passerait une porte, on publie « pas mesure ».
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
