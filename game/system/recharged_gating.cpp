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
  // `row` = cette option a une RANGEE dans le menu livre. Le recensement exige alors de la voir
  // passer : une rangee qui perd son `gating-id` (parce que le cablage GOAL a derive d'un cran)
  // disparait du recensement, et c'est justement la classe de bug qu'on ne veut plus laisser
  // filer en silence. `false` = l'option existe mais n'est reglable que par settings.ini, ou sa
  // rangee est absente du build livre (`pbr-isolate` n'apparait qu'avec --pbr --debug).
  bool row;
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

// Meme raison pour l'auvent d'herbe : TOUS ses sites reels sont sous `#ifdef
// OG_FEAT_GRASS_OVERHANG` (GrassRenderer.cpp:1685 et :1797, background_common.cpp:79), et sa
// rangee de menu est sous `FLAG_GRASS_OVERHANG`. Drapeau eteint, l'option n'est pas « sans
// defaut » : elle n'existe pas. Le champ, lui, survit dans `gfx.h` — c'est exactement le piege
// « TU feature-gatee » : un champ present et zero site compile.
#ifdef OG_FEAT_GRASS_OVERHANG
#define GOB(f) (&GS::f)
#else
#define GOB(f) (static_cast<bool GS::*>(nullptr))
#endif

#define NOB (static_cast<bool GS::*>(nullptr))
#define NOI (static_cast<int GS::*>(nullptr))
#define NOF (static_cast<float GS::*>(nullptr))

// L'ordre DOIT suivre l'enum `Opt` : verifie a l'initialisation (`check_table_once`), et une
// table qui ne se verifie pas publie une SENTINELLE au lieu d'un zero.
const Row kOptions[kOptCount] = {
    {"master", -1, Kind::kNode, &GS::recharged_master, NOI, NOF, 0, true},

    {"water", kMaster, Kind::kNode, &GS::recharged_water, NOI, NOF, 0, true},
    {"lighting", kMaster, Kind::kNode, &GS::recharged_lighting, NOI, NOF, 0, true},
    {"grass", kMaster, Kind::kToggle, &GS::recharged_grass, NOI, NOF, 0, true},
    {"textures", kMaster, Kind::kToggle, &GS::recharged_textures, NOI, NOF, 0, true},
    {"load-custom-assets", kMaster, Kind::kToggle, &GS::load_custom_assets, NOI, NOF, 0, true},
    {"managed-assets", kMaster, Kind::kToggle, &GS::recharged_managed_assets, NOI, NOF, 0, true},
    {"enhanced-models", kMaster, Kind::kToggle, &GS::recharged_enhanced_models, NOI, NOF, 0, true},
    {"foliage-wind", kMaster, Kind::kToggle, &GS::recharged_foliage_wind, NOI, NOF, 0, true},
    {"crisp-title-logo", kMaster, Kind::kToggle, &GS::recharged_crisp_title_logo, NOI, NOF, 0, true},
    {"mesh-browser-checker", kMaster, Kind::kMode, NOB, &GS::recharged_mesh_browser_checker, NOF, 0, false},

    {"grass-near-dist", kGrass, Kind::kParamF, NOB, NOI, &GS::recharged_grass_near_dist, 30.0, true},
    {"grass-card-dist", kGrass, Kind::kParamF, NOB, NOI, &GS::recharged_grass_card_dist, 95.0, true},
    {"grass-density", kGrass, Kind::kParamI, NOB, &GS::recharged_grass_density_preset, NOF,
     (double)grass_bake::kDensityPresetDefault, true},
    // `grass-precomputed` choisit la SOURCE des touffes (cuisson hors ligne ou dispersion vive) :
    // c'est un COMMENT, pas un SI. Il n'a pas d'etat « absent » — eteint, l'herbe pousse quand
    // meme — et ses seuls lecteurs vivent DANS `GrassRenderer::render/rebuild`, donc derriere la
    // porte de l'herbe. Il est donc classe comme un sous-parametre : son verdict est HERITE de
    // `grass`, et publie comme tel dans `gating_inherited`. Son STOCK est le defaut de gfx.h.
    {"grass-precomputed", kGrass, Kind::kParamI, &GS::recharged_grass_precomputed, NOI, NOF, 1, false},
    {"grass-overhang", kGrass, Kind::kToggle, GOB(recharged_grass_overhang), NOI, NOF, 0, false},

    {"ao-mode", kLighting, Kind::kMode, NOB, &GS::recharged_ao_mode, NOF, 0, true},
    {"ao-quality", kAoMode, Kind::kParamI, NOB, &GS::recharged_ao_quality, NOF, 1, true},
    {"ao-strength", kAoMode, Kind::kParamI, NOB, &GS::recharged_ao_strength, NOF, 1, true},
    {"rt-light", kLighting, Kind::kToggle, PB(recharged_rt_light_enable), NOI, NOF, 0, false},
    {"rt-shadow-res", kLighting, Kind::kParamI, NOB, PI(recharged_rt_shadow_res), NOF, 2048, true},
    {"rt-shadow-dist", kLighting, Kind::kParamF, NOB, NOI, PF(recharged_rt_shadow_dist), 150.0, true},
    {"rt-shadow-strength", kLighting, Kind::kParamF, NOB, NOI, PF(recharged_rt_shadow_strength),
     0.8, false},
    {"rt-ambient", kLighting, Kind::kToggle, PB(recharged_rt_ambient_enable), NOI, NOF, 0, false},
    {"rt-ambient-model", kRtAmbient, Kind::kParamI, NOB, PI(recharged_rt_ambient_model), NOF, 1, true},
    {"rt-ambient-strength", kRtAmbient, Kind::kParamF, NOB, NOI, PF(recharged_rt_ambient_strength),
     0.2, true},
    {"rt-ambient-contrast", kRtAmbient, Kind::kParamF, NOB, NOI, PF(recharged_rt_ambient_contrast),
     1.0, false},
    {"hdr", kLighting, Kind::kToggle, &GS::recharged_hdr, NOI, NOF, 0, false},
    {"hdr-knee", kHdr, Kind::kParamF, NOB, NOI, &GS::recharged_hdr_knee, 0.96, false},
    {"hdr-curve", kHdr, Kind::kParamI, NOB, &GS::recharged_hdr_curve, NOF, 0, false},
    {"hdr-exposure", kHdr, Kind::kParamF, NOB, NOI, &GS::recharged_hdr_exposure, 1.0, false},
    {"hdr-output", kLighting, Kind::kExternal, NOB, NOI, NOF, 0, true},
    {"pbr", kLighting, Kind::kToggle, PB(recharged_pbr_enable), NOI, NOF, 0, true},

    {"pbr-relief", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_texture_relief), 1.5, true},
    {"pbr-specular", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_spec_intensity), 0.15, true},
    {"pbr-displacement", kPbr, Kind::kMode, NOB, PI(recharged_pbr_displacement), NOF, 0, true},
    {"pbr-exposure", kPbr, Kind::kParamF, NOB, NOI, PF(recharged_pbr_exposure), 1.0, false},
    {"pbr-isolate", kPbr, Kind::kMode, NOB, PI(recharged_pbr_isolate), NOF, 0, false},
    {"mesh-subdiv", kPbr, Kind::kParamI, NOB, &GS::recharged_mesh_subdiv_rounds, NOF, 1, true},
    {"modern-materials", kPbr, Kind::kToggle, PB(recharged_modern_materials), NOI, NOF, 0, true},
};

#undef PB
#undef PI
#undef PF
#undef GOB
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
  // AMORCAGE DE LA VOLONTE. Il est appele par `set`, `desired`, `effective` et
  // `disabled_by_ancestor` — les quatre portes d'entree — parce que le PREMIER geste du moteur
  // est souvent une LECTURE : les setters de kmachine.cpp comparent `desired()` a la nouvelle
  // valeur pour decider d'un effet de bord (invalidation du pack telecharge, rechargement de
  // `surfaces.json`, ligne de log). Sans l'amorcage a la lecture, `desired` vaudrait 0 alors que
  // le champ vaut `true`, et le tout premier push d'un `#t` se lirait comme un CHANGEMENT :
  // un `managed_assets::invalidate()` de trop au boot, avant le moindre chargement de niveau. Plusieurs options n'ont AUCUN ecrivain (`recharged_hdr`,
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
  // TEMOIN D'AMORCAGE. Une option qui n'agit qu'au CHARGEMENT (les textures, le pack telecharge,
  // les modeles HD, le weld du niveau) consulte sa porte UNE fois, dans le constructeur du
  // renderer, bien avant la premiere image. Aucune fenetre d'images ne peut la voir tirer : lui
  // demander un `exec` par fenetre rendrait zero pour une raison qui n'a rien a voir avec la
  // porte. On garde donc, du boot, l'etat de ses ancetres et son compteur de vie. Ce temoin-la
  // est le PLUS proche du defaut de l'owner : il juge la configuration REELLE de son appareil
  // (son settings.ini porte `pbr-materials? = #f`), pas une configuration fabriquee.
  bool boot_disabled[kOptCount] = {false};
  bool boot_snapped = false;
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
  uint64_t missing = 0;    // une option qui DOIT avoir une rangee et qu'on n'a pas vue passer
  uint64_t absent = 0;     // une rangee que GOAL declare RETIREE de ce build/de cet ecran
  bool seen[kOptCount] = {false};
  bool declared_absent[kOptCount] = {false};
  std::string parents;     // « option:parent,... », publie tel quel
  std::string missing_names;
};

MenuState g_menu;

// La page ou une option DOIT vivre, DEDUITE DE SON PARENT. C'est la meme colonne que la porte :
// un sous-menu qui derive de la hierarchie se voit immediatement.
const char* expected_page(int opt) {
  // Le TOGGLE global d'un sous-menu vit DANS sa page, pas dans la page mere : c'est ce que
  // l'owner demande (« un sous menu Recharged Lighting avec un toggle global »). La ligne
  // d'ENTREE qui ouvre la page est un lanceur, pas une option : elle ne porte aucun
  // `gating-id` et n'est donc jamais recensee ici.
  if (opt == kGrass) {
    return "grass";
  }
  if (opt == kLighting) {
    return "lighting";
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
    // RIEN A FAIRE SI RIEN N'A CHANGE. `update-to-os` (hud-classes-pc.gc:1777) repousse les ~35
    // reglages A CHAQUE IMAGE, avec les memes valeurs : appliquer a chaque appel ferait 35
    // balayages complets de la table par image pour zero changement. Cet item est ne du cout des
    // options grisees ; son instrument n'a pas le droit d'en ajouter un.
    if (g_state[opt].desired_set && g_state[opt].desired == value) {
      return;
    }
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
  check_table_once();
  return g_state[opt].desired;
}

double effective(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return 0;
  }
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  check_table_once();
  return effective_value(opt);
}

bool disabled_by_ancestor(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return false;
  }
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  check_table_once();
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
  g_menu.missing = 0;
  g_menu.absent = 0;
  g_menu.parents.clear();
  g_menu.missing_names.clear();
  for (int i = 0; i < kOptCount; i++) {
    g_menu.seen[i] = false;
    g_menu.declared_absent[i] = false;
  }
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
  g_menu.seen[opt] = true;
  // UNE RANGEE PEUT ETRE LEGITIMEMENT ABSENTE, ET C'EST GOAL QUI LE SAIT. « HDR OUTPUT » est
  // RETIREE du tableau vivant quand l'ecran n'annonce aucun mode HDR (`*rch-hdr-row-hidden?*`) ;
  // sur un bureau sans ecran HDR elle n'existe pas, et la compter « manquante » serait un faux
  // rouge d'instrument. GOAL la declare avec la page `hidden` : absence DECLAREE, pas absence
  // constatee. Une rangee qu'on oublie de declarer, elle, reste comptee manquante.
  if (page && std::strcmp(page, "hidden") == 0) {
    g_menu.declared_absent[opt] = true;
    g_menu.absent++;
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

int page_of(int opt) {
  if (opt < 0 || opt >= kOptCount) {
    return -1;
  }
  const char* p = expected_page(opt);
  if (std::strcmp(p, "lighting") == 0) {
    return 2;
  }
  if (std::strcmp(p, "grass") == 0) {
    return 1;
  }
  return 0;
}

bool census_wanted() {
  return autoport_proof::feature_is("recharged-gating-real");
}

void menu_end() {
  std::lock_guard<std::recursive_mutex> lock(g_mutex);
  g_menu.open = false;
  // TOUTE option qui a une rangee livree doit avoir ete VUE. C'est ce terme qui transforme un
  // `gating-id` perdu (cablage GOAL decale d'un cran — la classe de bug Gmenu-flag-off) en
  // defaut compte, au lieu d'une rangee qui redevient silencieusement libre de tout parent.
  for (int i = 0; i < kOptCount; i++) {
    if (kOptions[i].row && !g_menu.seen[i]) {
      g_menu.missing++;
      if (!g_menu.missing_names.empty()) {
        g_menu.missing_names += ",";
      }
      g_menu.missing_names += kOptions[i].name;
    }
  }
}

void tick() {
  std::lock_guard<std::recursive_mutex> lock(g_mutex);

  if (!g_sweep.started) {
    g_sweep.started = true;
    g_sweep.wanted = autoport_proof::feature_is("recharged-gating-real");
  }

  if (g_sweep.wanted && !g_sweep.done) {
    if (!g_sweep.boot_snapped) {
      for (int i = 0; i < kOptCount; i++) {
        g_sweep.boot_disabled[i] = !ancestors_on(i);
      }
      g_sweep.boot_snapped = true;
    }
    g_sweep.frame++;
    const uint64_t f = g_sweep.frame;
    if (g_sweep.stage < 0) {
      if (f >= kWarmFrames) {
        // LA VOLONTE SE PHOTOGRAPHIE A LA FIN DE LA CHAUFFE, PAS A LA PREMIERE IMAGE.
        // `tick()` tourne depuis `npc-census-tick` ; `update-to-os`, qui pousse les ~35 reglages
        // depuis `*pc-settings*`, tourne dans une AUTRE passe de la meme image. A la premiere
        // image la table ne porte donc pas encore les reglages du joueur mais les defauts de
        // `gfx.h`, et la comparaison de fin voyait « la valeur a change » alors que rien n'avait
        // ete perdu : `gating_value_restored` sortait a 0 sur un aller-retour parfait (mesure
        // x86 du 2026-09-10). 60 images de chauffe suffisent : le reglage persiste est pousse
        // a chaque image.
        for (int i = 0; i < kOptCount; i++) {
          g_sweep.desired_before[i] = g_state[i].desired;
        }
        g_sweep.desired_snapped = true;
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
        g_sweep.value_restored = g_sweep.desired_snapped ? 1 : 0;
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
  // UNE CLE DE TEXTE NE SE VIDE JAMAIS TOUTE SEULE. `publish_text` garde la DERNIERE valeur
  // posee, et `publish_all` tourne a chaque image : une liste publiee a l'image 200 survit dans
  // proof.txt meme quand elle est devenue vide a l'image 900. Mesure du 2026-09-10 sur le Honor :
  // `gating_uncovered=0` et, deux lignes plus bas, sept noms d'options « non couvertes ». Les
  // deux ne peuvent pas etre vrais, et c'est le TEXTE qui mentait. On publie donc TOUJOURS, avec
  // « - » pour dire « aucun » : une preuve ne doit pas porter une ligne qui contredit son compteur.
  autoport_proof::publish_text("gating_ungated_names",
                               foreign_names.empty() ? "-" : foreign_names.c_str());

  // ── le menu ──
  autoport_proof::publish("gating_menu_rows", g_menu.rows);
  autoport_proof::publish("gating_menu_unknown", g_menu.unknown);
  autoport_proof::publish("gating_menu_misplaced", g_menu.misplaced);
  autoport_proof::publish("gating_menu_missing", g_menu.missing);
  autoport_proof::publish("gating_menu_absent", g_menu.absent);
  autoport_proof::publish_text("gating_menu_missing_names",
                               g_menu.missing_names.empty() ? "-" : g_menu.missing_names.c_str());
  autoport_proof::publish("gating_menu_seen", g_menu.ever ? 1 : 0);
  autoport_proof::publish_text("gating_menu_parent",
                               g_menu.parents.empty() ? "-" : g_menu.parents.c_str());

  // ── le balayage ────────────────────────────────────────────────────────────────────────────
  // QUI EST JUGE PAR SON PROPRE COMPTEUR, ET QUI HERITE.
  //
  // Une BASCULE / un MODE a un etat « eteint » et un site qui consulte sa porte : son verdict est
  // son compteur d'execution, mesure fenetre par fenetre. C'est le coeur de la criterion EFFET.
  //
  // Un SOUS-PARAMETRE CONTINU (une distance d'ombre, une force d'ambiante, un relief) n'a PAS
  // d'etat eteint : sa valeur « absente » est le defaut du moteur, qui est aussi sa valeur
  // ordinaire. Le forcer d'un cote ou de l'autre ne produit AUCUNE difference observable, et lui
  // demander un compteur d'execution fabriquerait un zero qui ne parle de rien. Son extinction
  // est portee ENTIEREMENT par son ancetre : si le parent n'a pas execute, la valeur n'a pas ete
  // consommee. Son verdict est donc HERITE — et publie comme tel, jamais tu.
  //
  // CE QUI EMPECHE CET HERITAGE D'ETRE UN SEAU D'EXCLUSION. Une option heritee dont l'ancetre est
  // lui-meme NON COUVERT est comptee NON COUVERTE a son tour : une branche entiere que rien n'a
  // fait tirer ne peut pas se cacher derriere « c'est le parent qui decide ». Et le champ de
  // chaque sous-parametre reste sous la surveillance de `gating_ungated_sites` : un ecrivain qui
  // le poserait par-dessus la porte serait compte, herite ou pas.
  uint64_t effet = 0, uncovered = 0, covered = 0, inherited = 0;
  std::string defect_names, uncovered_names;
  if (g_sweep.done) {
    // 1er passage : le verdict de ceux qui ont leur propre compteur.
    bool self_covered[kOptCount] = {false};
    bool self_judged[kOptCount] = {false};
    for (int i = 0; i < kOptCount; i++) {
      const Kind k = kOptions[i].kind;
      self_judged[i] = (k == Kind::kToggle || k == Kind::kMode || k == Kind::kExternal) &&
                       (k == Kind::kExternal || has_field(i));
      if (self_judged[i]) {
        self_covered[i] = g_sweep.exec_on[i] > 0 ||
                          g_state[i].eval.load(std::memory_order_relaxed) > 0;
      }
    }
    // Un MAITRE (kNode) est couvert des qu'une de ses descendantes l'est : c'est par elles qu'il
    // agit, il n'a pas de site a lui.
    for (int i = 0; i < kOptCount; i++) {
      if (kOptions[i].kind != Kind::kNode) {
        continue;
      }
      for (int j = 0; j < kOptCount; j++) {
        int q = kOptions[j].parent, guard = 0;
        while (q >= 0 && guard++ <= kOptCount) {
          if (q == i && self_judged[j] && self_covered[j]) {
            self_covered[i] = true;
          }
          q = kOptions[q].parent;
        }
      }
    }

    for (int i = 0; i < kOptCount; i++) {
      if (i == kMaster) {
        continue;  // la racine n'a aucun ancetre a trahir.
      }
      // L'ancetre le plus proche qui possede un verdict propre : c'est de lui qu'on herite.
      int anchor = i;
      if (!self_judged[i]) {
        anchor = -1;
        int q = kOptions[i].parent, guard = 0;
        while (q >= 0 && guard++ <= kOptCount) {
          if (self_judged[q] || kOptions[q].kind == Kind::kNode) {
            anchor = q;
            break;
          }
          q = kOptions[q].parent;
        }
        inherited++;
      }
      if (kOptions[i].kind != Kind::kExternal && !has_field(i)) {
        continue;  // NON COMPILEE dans ce jeu de drapeaux (`gating_not_compiled` la publie) :
                   // elle n'existe pas, elle n'est donc ni couverte ni non couverte. Un
                   // drapeau de build eteint ne doit ni fabriquer un defaut ni fabriquer un
                   // zero — c'est le piege « TU feature-gatee ».
      }
      if (g_menu.declared_absent[i]) {
        continue;  // GOAL a declare la rangee retiree de ce build : rien a couvrir, rien a juger.
      }
      // LE TEMOIN D'AMORCAGE, avant de declarer quoi que ce soit non couvert. Une option a
      // porte propre qui n'a JAMAIS tire dans une fenetre mais qui a bien ete CONSULTEE (son
      // `eval` de vie est non nul) est une option de CHARGEMENT : elle a rendu son verdict au
      // boot, avec la configuration reelle de l'appareil. On le lit la.
      if (self_judged[i] && g_sweep.exec_on[i] == 0 &&
          g_state[i].eval.load(std::memory_order_relaxed) > 0) {
        covered++;
        if (g_sweep.boot_disabled[i] && g_state[i].exec.load(std::memory_order_relaxed) > 0) {
          effet++;
          if (!defect_names.empty()) {
            defect_names += ",";
          }
          defect_names += kOptions[i].name;
          defect_names += "<boot";
        }
        continue;
      }
      const bool cov = (anchor >= 0) && self_covered[anchor];
      if (!cov) {
        uncovered++;
        if (uncovered_names.size() < 400) {
          if (!uncovered_names.empty()) {
            uncovered_names += ",";
          }
          uncovered_names += kOptions[i].name;
        }
        continue;
      }
      if (!self_judged[i]) {
        continue;  // couverte par son ancre, et jugee a travers elle
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
  autoport_proof::publish("gating_inherited", inherited);
  {
    // Combien d'options ont rendu leur verdict au CHARGEMENT plutot que dans une fenetre : la
    // repartition doit etre lisible, sinon « couvert » melangerait deux mesures differentes.
    uint64_t boot_judged = 0;
    for (int i = 0; i < kOptCount; i++) {
      const Kind k = kOptions[i].kind;
      if ((k == Kind::kToggle || k == Kind::kMode || k == Kind::kExternal) &&
          g_sweep.exec_on[i] == 0 && g_state[i].eval.load(std::memory_order_relaxed) > 0) {
        boot_judged++;
      }
    }
    autoport_proof::publish("gating_judged_at_load", boot_judged);
  }
  autoport_proof::publish("gating_uncovered", uncovered);
  autoport_proof::publish("gating_value_restored", g_sweep.value_restored == 1 ? 1 : 0);
  autoport_proof::publish_text("gating_effect_defect_names",
                               defect_names.empty() ? "-" : defect_names.c_str());
  autoport_proof::publish_text("gating_uncovered_names",
                               uncovered_names.empty() ? "-" : uncovered_names.c_str());

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
    defects = effet + foreign + uncovered + g_menu.unknown + g_menu.misplaced + g_menu.missing +
              (g_sweep.value_restored == 1 ? 0 : 1);
  }
  autoport_proof::publish("gating_defects", defects);
}

}  // namespace
}  // namespace recharged_gating
