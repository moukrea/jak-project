#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/origin_ablate.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <unordered_set>
#include <unordered_map>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"
#include "fmt/format.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/background/Shrub.h"
#include "game/graphics/opengl_renderer/background/Tie3.h"
#include "game/graphics/refset.h"
#include "game/graphics/opengl_renderer/PrePass.h"
#include "game/system/autoport_proof.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
AUTOPORT_FEATURE_SITE("foliage-wind");

namespace foliage_wind {
namespace {

constexpr const char* kTrunkItemId = "shrub-trunk-contact";
AUTOPORT_FEATURE_SITE(kTrunkItemId);

// ----------------------------------------------------------------------------- lecture de bouton
// Meme discipline que les boutons existants de Tie3.cpp : propriete Android / variable
// d'environnement bureau, valeur illisible, negative, NaN ou hors borne -> le DEFAUT, jamais un
// rabotage. Un doigt qui glisse sur le clavier rend la brise nominale, jamais une tempete.
bool read_knob_raw(const char* prop, const char* env, char* out, size_t out_sz) {
#ifdef __ANDROID__
  (void)env;
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    std::snprintf(out, out_sz, "%s", buf);
    return true;
  }
#else
  (void)prop;
  const char* e = std::getenv(env);
  if (e && e[0]) {
    std::snprintf(out, out_sz, "%s", e);
    return true;
  }
#endif
  return false;
}

float knob(const char* prop, const char* env, float def, float hi) {
  char buf[32] = {0};
  if (!read_knob_raw(prop, env, buf, sizeof(buf))) {
    return def;
  }
  const float v = (float)std::atof(buf);
  if (!(v >= 0.f) || v > hi) {
    return def;
  }
  return v;
}

// Essai 11 : 0,14 m etait « twitch à peine » (owner 2026-09-04) ; 0,61 m sur une onde de 30 cm
// etait « une tempête » (2026-08-31). 0,30 m de couronne sur un arbre de 8 m et plus, soit ~9 cm sur
// un buisson de 2,3 m, oscillation de +/-30 % autour de la flexion moyenne dans la rafale.
constexpr float kBendDefaultM = 0.30f;
constexpr float kBendMaxM = 0.80f;
constexpr float kFlutterDefault = 0.35f;
constexpr float kFlutterMax = 1.0f;

// --------------------------------------------------------------------------- l'etat du recensement
struct TreeKey {
  std::string level;
  int system;
  int tree;
  int geo;
  bool operator<(const TreeKey& o) const {
    if (level != o.level) {
      return level < o.level;
    }
    if (system != o.system) {
      return system < o.system;
    }
    if (tree != o.tree) {
      return tree < o.tree;
    }
    return geo < o.geo;
  }
};

struct TreeEntry {
  std::vector<Instance> instances;
  bool drawn = false;
};

std::mutex g_mutex;
std::map<TreeKey, TreeEntry> g_trees;
// Inventory of the shipped Jak1 TIE lexicon and SHRUB sidecar. These are expected
// levels, not successful observations: a level enters g_levels_seen only at draw.
const char* const kVegetatedLevels[] = {
    "beach", "finalboss", "firecanyon", "intro", "jungle", "jungleb", "maincave",
    "misty", "ogre", "robocave", "rolling", "snow", "sunken", "sunkenb", "swamp",
    "training", "village1", "village2", "village3"};
std::set<std::string> g_levels_seen;
std::map<std::pair<std::string, int>, u32> g_unclassified;
u64 g_frames = 0;
u64 g_last_frame_idx = (u64)-1;
float g_dir_x = 0.70710678f;
float g_dir_z = 0.70710678f;
bool g_paused = false;

// --- le vent du jeu (verdict 1) ---
bool g_gw_seeded = false;
u32 g_gw_first_time = 0;
u32 g_gw_last_time = 0;
u64 g_gw_last_frame = (u64)-1;
std::chrono::steady_clock::time_point g_gw_last_wall;
float g_gw_force_prev[64];
u32 g_gw_slot_last_change[64];
double g_gw_sum_dwind = 0.0;   // pas de vent VUS par le renderer (delta de `wind-time` du DMA)
double g_gw_sum_dwall = 0.0;   // secondes murales, memes images (diagnostic, hors verdict)
u64 g_gw_frames = 0;

// --- la cadence, rapportee par son PRODUCTEUR (`update-wind-ticks!`, une fois par image) ---
double g_rate_expected = 0.0;  // somme des `time-adjust-ratio` : le temps de JEU ecoule, en 1/60 s
double g_rate_got = 0.0;       // somme des appels a `update-wind` reellement faits
u64 g_rate_frames = 0;
u64 g_rate_hitch = 0;          // images ecretees a la production (ratio > 8) : hors des deux sommes
u64 g_native_samples = 0;
u64 g_native_sat = 0;
double g_native_raw_sq = 0.0;
float g_shrub_native_shear_peak = 0.f;

// --- l'echantillon de la loi (verdicts 5 et 7) ---
struct Sample {
  float t;
  float d;   // projection sur le cap du vent : le signal des verdicts (5) et (7)
  float rx;  // le deplacement dans le REPERE DU VENT (rx = le long, rz = en travers) : verdict (9)
  float rz;
  float gx;  // le cap du vent EFFECTIVEMENT pousse aux shaders, pour le diagnostic de derapage
  float gz;
};
constexpr size_t kSampleRing = 16384;
constexpr double kPi = 3.14159265358979323846;  // kPi n'est pas garanti par <cmath> partout (Bionic)
std::vector<Sample> g_samples;
size_t g_sample_head = 0;
size_t g_sample_count = 0;
float g_sample_last_t = -1.f;

// Assez souvent pour qu'une course de quatre minutes republie une quarantaine de fois, assez rare
// pour que le cout O(N x voisins) + FFT ne se voie pas : 300 images, c'est 5 s sur bureau.
constexpr u64 kRepublishFrames = 300;

// « côté à côte » : 12 m. Au-dela l'oeil ne compare plus deux plantes, il regarde un paysage.
constexpr float kPairRadiusU = 12.f * 4096.f;
// « identiques » : meme taille apparente a 1,5 pres.
constexpr float kHeightRatioMax = 1.5f;
// le seuil de divergence : un facteur 2 sur la flexion RELATIVE.
constexpr float kDivergeRatio = 2.0f;
// plancher numerique : sous 0,1 mm de flexion, une plante ne bouge pas.
constexpr float kStillM = 1e-4f;

// --- les seuils des sept verdicts, ceux du livrable ---
constexpr u64 kV1MaxDevPct = 1;
constexpr u64 kV5MaxPeakPct = 40;
constexpr double kV6MaxRatio = 0.15;
constexpr double kV7MinCv = 0.30;
constexpr double kV8MinGradient = 3.0;
constexpr double kV9MinSpreadDeg = 20.0;
// Sous ce nombre d'instances mesurables, (8) n'est pas mesure : un minimum pris sur trois plantes
// ne dit rien du decor et se lirait « correct » par chance.
constexpr u64 kTipMinInstances = 20;
// La fenetre du lissage du cap, en echantillons de 10 Hz. 2,0 s : au-dessus des periodes du
// balancement (0,45 s) et du fremissement (0,11 s), bien au-dessous de celles du lacet (26 a 68 s).
constexpr size_t kDirSmoothSamples = 20;

}  // namespace

// ------------------------------------------------------------------------------------- reglages --

// SHRUB includes rocks and props as well as plants. Native stiffness is not a
// vegetation classifier (flowers and whole levels of bushes have stiffness zero).
bool shrub_contact_prototype(const std::string& name) {
  static const std::unordered_set<std::string> plants = {
      "bch-palmplant-base.mb",
      "grass-clump-02.mb",
      "grass-clump.mb",
      "palmplant-base.mb",
      "swp-thornbush-05.mb",
      "swp-thornbush-06.mb",
      "swp-thornbush-07.mb",
      "swp-thornbush-07a.mb",
      "swp-thornbush-08.mb",
      "swp-thornbush-08a.mb",
      "swp-thornbush-08c.mb",
      "swp-thornbush-09a.mb",
      "swp-thornbush-09b.mb",
      "swp-thornbush-09c.mb",

      "bamboo.mb",
      "bch-bush.mb",
      "bch-cattail-01.mb",
      "bch-coral-leaf.mb",
      "bch-exotic-plant.mb",
      "bch-fullmoss.mb",
      "bch-grass.mb",
      "bch-kelp.mb",
      "bch-palmplanttop.mb",
      "bch-plantflower.mb",
      "bch-shrub-grass.mb",
      "bigleaves.mb",
      "bushpalm.mb",
      "cav-mushroom-01-geo.mb",
      "cav-mushroom-02-geo.mb",
      "cav-mushroom-03-geo.mb",
      "cav-mushroom-04-geo.mb",
      "cav-mushroom-05-geo.mb",
      "exotic-plant-half.mb",
      "fan-coralgroup.mb",
      "fcn-bush.mb",
      "fin-tree.mb",
      "fire-burnt-grass.mb",
      "fire-burnt-shrub-01.mb",
      "grass-01.mb",
      "grass-02.mb",
      "grass.mb",
      "jng-cattailplant.mb",
      "jng-cattailplant2.mb",
      "jng-clump-leaf-01.mb",
      "jng-clump-leaf-02.mb",
      "jng-curvedleafplant.mb",
      "jng-flatgrass.mb",
      "jng-fuzzystalk.mb",
      "jng-grass.mb",
      "jng-half-fern.mb",
      "jng-lavanders.mb",
      "jng-palm-leaf-01.mb",
      "jng-tall-grass.mb",
      "jng-vinebase-02.mb",
      "jng-vinebase.mb",
      "leafy-plant.mb",
      "mis-shrub-01.mb",
      "mis-shrub-02.mb",
      "mis-shrub-03.mb",
      "mis-shrub-04.mb",
      "mis-shrub-05.mb",
      "mis-shrub-06.mb",
      "mis-twig-01.mb",
      "mis-twig-02.mb",
      "ogr-cave-mush-01-geo.mb",
      "ogr-cave-mush-01grp-geo.mb",
      "ogr-fuzzyplant.mb",
      "ogr-grassstuff-01.mb",
      "ogr-grassstuff-02.mb",
      "ogr-grassstuff-03.mb",
      "ogr-lavenders.mb",
      "ogr-mushrooms01.mb",
      "ogr-scrub.mb",
      "palmplant-top.mb",
      "plant_3.mb",
      "plant_6.mb",
      "plantflower.mb",
      "rol-bonzai-lowrez-trunk.mb",
      "rol-bonzaibranch-01.mb",
      "rol-bonzaicanopy-01.mb",
      "rol-bonzaicanopy.mb",
      "rol-cattailplant.mb",
      "rol-cattailplant2.mb",
      "rol-flatgrass.mb",
      "rol-flower-grass-group.mb",
      "rol-fuzzystalk.mb",
      "rol-grass.mb",
      "rol-grassgroup.mb",
      "rol-lavanders.mb",
      "rol-mushroomgroup.mb",
      "rol-mushrooms.mb",
      "rol-tall-grass-flowers.mb",
      "rol-tall-grass.mb",
      "roofgrass.mb",
      "roofgrass2.mb",
      "root-06.mb",
      "shrub-grass-03.mb",
      "smallsingleleaf.mb",
      "snow-grassclump.mb",
      "sun-coral-fan.mb",
      "sun-coral-leaf.mb",
      "sun-coral-seaweed.mb",
      "sun-coral-sponge.mb",
      "sun-kelp.mb",
      "sun-mushroom-ears.mb",
      "sun-mushroom-group.mb",
      "swp-branch-03.mb",
      "swp-branch-03m.mb",
      "swp-branch-04moss.mb",
      "swp-cattail-02.mb",
      "swp-grass-01.mb",
      "swp-grass-02.mb",
      "swp-leafy-plant.mb",
      "swp-moss-01m.mb",
      "swp-moss-03m.mb",
      "swp-multithorns-05.mb",
      "swp-multithorns-06.mb",
      "swp-multithorns-07.mb",
      "swp-multithorns-07a.mb",
      "swp-multithorns-07b.mb",
      "swp-multithorns-08.mb",
      "swp-multithorns-08a.mb",
      "swp-multithorns-08c.mb",
      "swp-multithorns-09a.mb",
      "swp-multithorns-09b.mb",
      "swp-multithorns-09c.mb",
      "swp-pad.mb",
      "swp-scum.mb",
      "swp-small-leaf.mb",
      "swp-spanmoss-01.mb",
      "tall-grass-01.mb",
      "trunk01vine.mb",
      "trunk02vine1.mb",
      "trunk02vine2.mb",
      "trunk02vine3.mb",
      "v2-coral-fan.mb",
      "v2-coral-leaf.mb",
      "v2-coral-seaweed.mb",
      "v2-kelp.mb",
      "vil-cattail-01.mb",
      "vil-riceplant-01.mb",
      "vil2-bonzaibranch-01.mb",
      "vil2-bonzaicanopy-01.mb",
      "vil2-cattail.mb",
      "vil2-grass-burned.mb",
      "vil2-grass-long.mb",
      "vil2-grass-whispy.mb",
      "vil2-grass.mb",
      "vil2-lil-shrubtree.mb",
      "vil2-pine-shrub.mb",
      "vil2-wheat.mb",
      "vil3-mushroom-01-geo.mb",
  };
  return plants.count(name) != 0;
}

bool enabled() {
  if (prepass::static_probe_wind_disabled()) return false;
  // Le forcage est lu UNE fois : c'est un levier de mesure, il ne doit pas pouvoir basculer en
  // cours de course et rendre deux moities de preuve incomparables.
  static const bool s_forced = [] {
    char buf[32] = {0};
    if (!read_knob_raw("debug.opengoal.foliage.force", "FOLIAGE_WIND_FORCE", buf, sizeof(buf))) {
      return false;
    }
    return buf[0] != '0';
  }();
#if !AUTOPORT_ORIGIN_ABLATE
  if (s_forced) {
    return true;
  }
#endif
  // Le bras d'ablation du harnais (`proof_run.sh --off` sur CET item) eteint la brise ajoutee ;
  // sans item nomme, ou pour un autre item, `armed_for` rend vrai et rien ne change pour l'owner.
  if (!autoport_proof::armed_for("foliage-wind")) {
    return false;
  }
  return recharged_gating::on(recharged_gating::kFoliageWind);
}

float bend_metres() {
  static float s_cached = kBendDefaultM;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) == 0) {
    s_cached = knob("debug.opengoal.foliage.bend", "FOLIAGE_WIND_BEND", kBendDefaultM, kBendMaxM);
  }
  return s_cached;
}

float flutter_fraction() {
  static float s_cached = kFlutterDefault;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) == 0) {
    s_cached =
        knob("debug.opengoal.foliage.flutter", "FOLIAGE_WIND_FLUTTER", kFlutterDefault, kFlutterMax);
  }
  return s_cached;
}

bool shrub_native_enabled() {
#if AUTOPORT_ORIGIN_ABLATE
  // BINAIRE-TEMOIN : ce drapeau vaut TRUE par defaut et ne consulte aucun maitre. Il arme
  // `Shrub.cpp:323` `wind_active`, donc il DEPLACE des sommets d'arbustes maitre eteint.
  return false;
#else
  static const bool s_on = [] {
    char buf[32] = {0};
    if (!read_knob_raw("debug.opengoal.wind.shrub_native", "OG_WIND_SHRUB_NATIVE", buf,
                       sizeof(buf))) {
      return true;
    }
    return buf[0] != '0';
  }();
  return s_on;
#endif
}

// REFSET : L'HORLOGE DE LA BRISE DEVIENT UNE FONCTION DE LA FRAME DE LOGIQUE.
// Ce compteur integrait un `dt` pris a la `steady_clock`, donc la phase du vent poussee aux
// shaders dependait de la vitesse de la machine : deux rejeux du meme plan ne rendaient pas les
// memes pixels. Sous `refset::enabled()` seulement, l'horloge vaut `lf / 60` — pure, sans
// accumulation, donc reproductible au bit. Le joueur, lui, ne voit RIEN changer : hors refset le
// chemin ci-dessous est celui d'avant, ligne pour ligne.
// `refset_wind_clock_pinned` compte les frames de logique DISTINCTES ou l'epinglage a servi :
// a zero, dire « l'horloge est neutralisee » serait une clause vide.
float clock_seconds(u64 frame_idx, bool paused_now) {
  const int64_t probe_lf = prepass::static_probe_logic_frame();
  if (probe_lf >= 0) return (float)probe_lf / 60.f;
  if (refset::enabled()) {
    const int64_t lf = refset::render_logic_frame();
    if (lf >= 0) {
      static int64_t s_pin_last_lf = -1;
      static uint64_t s_pin_count = 0;
      if (lf != s_pin_last_lf) {
        s_pin_last_lf = lf;
        s_pin_count++;
        autoport_proof::publish("refset_wind_clock_pinned", s_pin_count);
      }
      return (float)lf / 60.f;
    }
  }
  static float s_t = 0.f;
  static u64 s_last_frame = (u64)-1;
  static std::chrono::steady_clock::time_point s_last = std::chrono::steady_clock::now();
  if (frame_idx != s_last_frame) {
    s_last_frame = frame_idx;
    const auto now = std::chrono::steady_clock::now();
    float dt = std::chrono::duration<float>(now - s_last).count();
    s_last = now;
    if (!(dt > 0.f)) {
      dt = 0.f;
    }
    if (dt > 0.1f) {
      dt = 0.1f;  // un a-coup de chargement ne fait pas defiler la brise
    }
    if (!paused_now) {
      s_t += dt;
    }
  }
  return s_t;
}

// LE CAP DU VENT, LISSE. `wind-normal` de ND (wind.gc:60-64) est une MARCHE ALEATOIRE sur l'angle :
// `w += rand(-1024, 1024)` puis (cos w, sin w), un pas par 1/60 s — soit +/- 5,6 degres PAR PAS,
// donc ~25 degres d'ecart-type en une seconde. Le ressort natif de ND integre cette marche et n'en
// voit qu'une moyenne ; notre brise, elle, prenait le cap BRUT et le tournait a chaque image. C'est
// un tremblement de direction, pas un vent — et il tombe exactement sous « un mouvement très
// binaire [...] aucune variation ». Le cap pousse aux shaders est donc lisse a la constante de
// temps `kDirTauSeconds` : la marche aleatoire devient une derive lente et coherente, sur laquelle
// le LACET de breeze.glsl ajoute son virage voulu. Le ressort NATIF n'est pas touche (il lit
// `m_wind_vectors`, pas ceci) : le chemin stock reste le chemin stock.
constexpr float kDirTauSeconds = 3.0f;

void set_wind_state(float x, float z, bool paused_now) {
  g_paused = paused_now;
  const float len = std::sqrt(x * x + z * z);
  if (!(len > 1e-4f)) {
    return;  // vecteur nul ou NaN : on garde le cap precedent
  }
  const float tx = x / len;
  const float tz = z / len;
  static std::chrono::steady_clock::time_point s_last = std::chrono::steady_clock::now();
  static bool s_seeded = false;
  const auto now = std::chrono::steady_clock::now();
  float dt = std::chrono::duration<float>(now - s_last).count();
  s_last = now;  // tenu a jour DANS LES DEUX CAS : sortir du mode refset ne doit pas rendre un dt geant
  if (!(dt > 0.f) || dt > 0.5f) {
    dt = 0.f;  // un a-coup de chargement ne fait pas tourner le vent d'un quart de tour
  }
  if (refset::enabled()) {
    // UN PAS PAR FRAME DE LOGIQUE, PAS PAR APPEL. Ce lissage est un ACCUMULATEUR : poser
    // `dt = 1/60` ne suffit pas, parce que cette fonction est appelee une fois par image RENDUE
    // et que la course en dessine plusieurs par image simulee (mesure du 2026-09-06 sur
    // eae4df44 : `frames=16320` pour `refset_pump_logic=5223`, soit 3,1 appels par frame de
    // logique, et ce rapport depend de la charge). On ne fait donc avancer le filtre que sur une
    // frame de logique NEUVE ; les appels suivants de la meme frame rendent le cap deja calcule.
    static int64_t s_lf_last = -1;
    const int64_t lf = refset::render_logic_frame();
    if (lf >= 0) {
      if (lf == s_lf_last) {
        return;
      }
      s_lf_last = lf;
    }
    dt = 1.f / 60.f;
  }
  if (!s_seeded) {
    s_seeded = true;
    g_dir_x = tx;
    g_dir_z = tz;
    return;
  }
  const float a = 1.f - std::exp(-dt / kDirTauSeconds);
  const float nx = g_dir_x + (tx - g_dir_x) * a;
  const float nz = g_dir_z + (tz - g_dir_z) * a;
  const float nl = std::sqrt(nx * nx + nz * nz);
  if (nl > 1e-4f) {  // le lissage d'un vecteur unitaire peut passer pres de zero : on ne le suit pas
    g_dir_x = nx / nl;
    g_dir_z = nz / nl;
  }
}

void direction(float* out_x, float* out_z) {
  *out_x = g_dir_x;
  *out_z = g_dir_z;
}

bool paused() {
  return g_paused;
}

float push_uniforms(GLuint program, u64 frame_idx, const char* pass) {
  const float amp = enabled() ? bend_metres() * 4096.f : 0.f;
  const float t = clock_seconds(frame_idx, g_paused);
  const GLint amp_loc = glu::loc(program, "u_tie_sway_amp");
  const GLint time_loc = glu::loc(program, "u_tie_sway_time");
  const GLint dir_loc = glu::loc(program, "u_tie_sway_dir");
  const GLint flut_loc = glu::loc(program, "u_tie_sway_flutter");
  if (amp_loc >= 0) {
    glUniform1f(amp_loc, amp);
  }
  if (time_loc >= 0) {
    glUniform1f(time_loc, t);
  }
  if (dir_loc >= 0) {
    glUniform2f(dir_loc, g_dir_x, g_dir_z);
  }
  if (flut_loc >= 0) {
    glUniform1f(flut_loc, flutter_fraction());
  }
  if (amp > 0.f) {
    // Ligne de preuve one-shot PAR PASSE : les modes de defaillance SILENCIEUX de ce chemin — un
    // `loc` a -1 (l'uniforme n'existe pas dans le programme lie) et un attribut 7/8 inactif sur le
    // VAO courant (le poids arrive a 0 partout et RIEN ne bouge). Aucun ne produit d'erreur GL.
    static std::map<std::string, bool> s_logged;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!s_logged[pass]) {
      s_logged[pass] = true;
      GLint attr7_on = 0, attr7_type = 0, attr8_on = 0;
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &attr7_on);
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_TYPE, &attr7_type);
      glGetVertexAttribiv(8, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &attr8_on);
      lg::info(
          "[foliage-wind] sway ACTIVE pass={} bend={:.4f}m flutter={:.2f} amp_loc={} time_loc={} "
          "dir_loc={} flutter_loc={} attr7_on={} attr7_type={:#x} attr8_on={} dir=({:.3f},{:.3f})",
          pass, amp / 4096.f, flutter_fraction(), amp_loc, time_loc, dir_loc, flut_loc, attr7_on,
          attr7_type, attr8_on, g_dir_x, g_dir_z);
    }
  }
  return amp;
}

// --------------------------------------------------- la loi, jumelle de shaders/breeze.glsl -----
// Toute modification ici DOIT etre reportee dans shaders/breeze.glsl, et reciproquement. Les
// constantes portent les memes valeurs dans le meme ordre pour que la comparaison soit visuelle.
void breeze_offset(float anchor_x,
                   float anchor_z,
                   float dir_x,
                   float dir_z,
                   float ph01,
                   float t,
                   float w,
                   float bend_u,
                   float flutter_f,
                   float* out_x,
                   float* out_z,
                   float* out_flutter_gain) {
  constexpr float kGustK = 1.27828e-5f;  // 2*pi / (120 m * 4096)
  const float travel = (anchor_x * dir_x + anchor_z * dir_z) * kGustK;
  const float pp = ph01 * 6.2831853f;
  const float g = 0.30f * std::sin(t * 0.2513f - travel + pp * 0.31f) +
                  0.27f * std::sin(t * 0.4084f - travel * 1.73f + pp * 0.77f + 1.7f) +
                  0.22f * std::sin(t * 0.6597f - travel * 2.91f + pp * 0.29f + 4.1f) +
                  0.13f * std::sin(t * 1.0053f - travel * 1.31f + pp * 1.13f + 2.6f) +
                  0.08f * std::sin(t * 1.5708f + pp * 0.53f + 0.9f);
  const float gust =
      0.12f + 0.88f * std::pow(std::min(std::max(0.5f + 0.5f * g, 0.f), 1.f), 1.6f);
  const float sway = 0.55f + 0.30f * std::sin(t * 2.1991f + pp * 1.19f + travel * 0.6f) +
                     0.18f * std::sin(t * 3.5343f + pp * 2.03f + 1.1f) +
                     0.10f * std::sin(t * 4.8381f + pp * 0.71f + 2.9f);
  const float along = gust * sway;
  const float cross = gust * (0.22f * std::sin(t * 2.7646f + pp * 1.61f + 2.3f) +
                              0.10f * std::sin(t * 1.3823f + pp * 0.4f));
  const float flut_gain = 0.25f + 0.75f * gust;

  // regle (6) de breeze.glsl : LE CAP TOURNE. Trois composantes lentes, +/- 0,66 rad.
  const float ya = 0.34f * std::sin(t * 0.0917f + pp * 0.23f + 0.7f) +
                   0.21f * std::sin(t * 0.1571f - travel * 0.7f + pp * 0.61f + 2.2f) +
                   0.11f * std::sin(t * 0.2437f + pp * 1.07f + 4.4f);
  const float cy = std::cos(ya);
  const float sy = std::sin(ya);
  const float wdir_x = dir_x * cy - dir_z * sy;
  const float wdir_z = dir_x * sy + dir_z * cy;

  const float perp_x = -wdir_z;
  const float perp_z = wdir_x;
  float ox = (wdir_x * along + perp_x * cross) * (bend_u * w);
  float oz = (wdir_z * along + perp_z * cross) * (bend_u * w);

  if (flutter_f > 0.f) {
    const float lf1 = std::sin(t * 8.7965f + ph01 * 12.566f + w * 2.9f);
    const float lf2 = std::sin(t * 13.4035f + ph01 * 7.3f + w * 4.1f + 1.3f);
    const float lf_amp = bend_u * w * flutter_f * flut_gain;
    ox += (wdir_x * (0.62f * lf1 + 0.38f * lf2) + perp_x * (lf2 * 0.45f)) * lf_amp;
    oz += (wdir_z * (0.62f * lf1 + 0.38f * lf2) + perp_z * (lf2 * 0.45f)) * lf_amp;
  }

  *out_x = ox;
  *out_z = oz;
  if (out_flutter_gain) {
    *out_flutter_gain = flut_gain;
  }
}

// ------------------------------------------------------------------- le vent du jeu (verdict 1) --

int wind_ticks_for(u32 now, u32& last, bool& seeded, bool paused_now) {
  if (!seeded) {
    seeded = true;
    last = now;
    return 1;  // premiere image apres un chargement : on ne rattrape pas l'historique du monde
  }
  if (paused_now) {
    last = now;
    return 0;  // en pause GOAL n'avance plus `wind-time` ; on n'integre pas non plus
  }
  const u32 d = now - last;  // arithmetique non signee : robuste au repliement de l'uint32
  last = now;
  if (d > 8) {
    return 8;
  }
  return (int)d;
}

void note_game_wind(const float* force64, u32 wind_time, bool paused_now, u64 frame_idx) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (frame_idx == g_gw_last_frame) {
    return;  // plusieurs Tie3 residents deposent la meme copie : une seule compte
  }
  g_gw_last_frame = frame_idx;
  const auto now = std::chrono::steady_clock::now();
  if (!g_gw_seeded) {
    g_gw_seeded = true;
    g_gw_first_time = wind_time;
    g_gw_last_time = wind_time;
    g_gw_last_wall = now;
    for (int i = 0; i < 64; i++) {
      g_gw_force_prev[i] = force64[i];
      g_gw_slot_last_change[i] = wind_time;
    }
    return;
  }
  // slots de l'anneau : une force qui n'a pas change depuis 128 pas n'est plus ecrite
  for (int i = 0; i < 64; i++) {
    if (force64[i] != g_gw_force_prev[i]) {
      g_gw_force_prev[i] = force64[i];
      g_gw_slot_last_change[i] = wind_time;
    }
  }
  // cadence : pas de vent contre ticks de logique, sur les images HORS pause
  const double dwall = std::chrono::duration<double>(now - g_gw_last_wall).count();
  const u32 dwind = wind_time - g_gw_last_time;
  if (!paused_now && !g_paused && dwall < 2.0) {
    g_gw_sum_dwind += (double)dwind;
    g_gw_sum_dwall += dwall;
    g_gw_frames++;
  }
  g_gw_last_time = wind_time;
  g_gw_last_wall = now;
}

// LA CADENCE AU POINT DE PRODUCTION. `update-wind-ticks!` appelle ceci une fois par tour de
// `display-loop`, juste apres avoir execute ses pas : `ratio` est ce que le MOTEUR pense que
// l'image vaut en 1/60 s de temps de jeu, `steps` ce que le vent a reellement avance. Comparer
// les deux, c'est comparer la brise a l'horloge du JEU — pas a la montre murale, qui derive avec
// la cadence d'affichage et rendait 3,6 % sur un vent correct (essai 11).
void note_wind_rate(float ratio, int steps) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!std::isfinite(ratio) || ratio < 0.f || steps < 0) {
    return;  // rien de mesurable : une valeur non finie ne se moyenne pas
  }
  if (ratio > 8.f) {
    // Ecretee a la production (`wind-ticks-this-frame` borne a 8) : un a-coup de chargement ne
    // doit pas faire defiler la brise d'un huitieme de seconde. L'image sort des DEUX sommes et
    // se compte ici, pour qu'aucun seau exclu ne se lise « correct ».
    g_rate_hitch++;
    return;
  }
  g_rate_expected += (double)ratio;
  g_rate_got += (double)steps;
  g_rate_frames++;
}

namespace {
std::vector<u8> g_game_wind_copy;
size_t g_game_wind_n = 0;
}  // namespace

void set_game_wind_copy(const void* bytes, size_t n) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_game_wind_copy.size() < n) {
    g_game_wind_copy.resize(n);
  }
  std::memcpy(g_game_wind_copy.data(), bytes, n);
  g_game_wind_n = n;
}

const void* game_wind_bytes(size_t* out_n) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (out_n) {
    *out_n = g_game_wind_n;
  }
  return g_game_wind_n ? g_game_wind_copy.data() : nullptr;
}

void note_native_sample(float raw, bool saturated) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_native_samples++;
  g_native_raw_sq += (double)raw * raw;
  if (saturated) {
    g_native_sat++;
  }
}

void note_shrub_native_shear_peak(float s) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (s > g_shrub_native_shear_peak) {
    g_shrub_native_shear_peak = s;
  }
}

// ----------------------------------------------------------------------------- le recensement ----

void set_tree(const std::string& level, int system, int tree, int geo, std::vector<Instance>&& v) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto& e = g_trees[TreeKey{level, system, tree, geo}];
  e.instances = std::move(v);
  e.drawn = false;  // un arbre recharge n'herite pas du « deja dessine » de l'ancien
}

void forget(const std::string& level, int system) {
  std::lock_guard<std::mutex> lock(g_mutex);
  for (auto it = g_trees.begin(); it != g_trees.end();) {
    if (it->first.level == level && it->first.system == system) {
      it = g_trees.erase(it);
    } else {
      ++it;
    }
  }
  if (system == kSystemTieStatic) {
    for (auto it = g_unclassified.begin(); it != g_unclassified.end();) {
      if (it->first.first == level) {
        it = g_unclassified.erase(it);
      } else {
        ++it;
      }
    }
  }
}

void mark_drawn(const std::string& level, int system, int tree, int geo) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto it = g_trees.find(TreeKey{level, system, tree, geo});
  if (it != g_trees.end()) {
    it->second.drawn = true;
    if (enabled() && std::any_of(it->second.instances.begin(), it->second.instances.end(),
                               [](const Instance& in) { return in.peak_w > 0.f; })) {
      if (g_levels_seen.insert(level).second) {
        lg::info("[foliage-wind] level drawn lev={} system={} instances={}",
                 level, system, it->second.instances.size());
      }
    }
  }
}

void note_unclassified(const std::string& level, int tree, u32 count) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_unclassified[{level, tree}] = count;
}

namespace {

// FFT radix-2 en place, N puissance de 2.
void fft(std::vector<std::complex<double>>& a) {
  const size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; i++) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      std::swap(a[i], a[j]);
    }
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    const double ang = -2.0 * kPi / (double)len;
    const std::complex<double> wl(std::cos(ang), std::sin(ang));
    for (size_t i = 0; i < n; i += len) {
      std::complex<double> w(1.0, 0.0);
      for (size_t k = 0; k < len / 2; k++) {
        const auto u = a[i + k];
        const auto v = a[i + k + len / 2] * w;
        a[i + k] = u + v;
        a[i + k + len / 2] = u - v;
        w *= wl;
      }
    }
  }
}

// Verdicts (5) et (7) sur l'echantillon de la loi. `ok` = assez de temps mesure (>= 51,2 s).
struct SpectrumVerdict {
  bool ok = false;
  double peak_pct = 0.0;
  double peak_hz = 0.0;
  double env_cv = 0.0;
  double window_s = 0.0;
  size_t n = 0;
  bool dir_ok = false;
  double dir_spread_deg = 0.0;
  double slew_deg_s = -1.0;
};

SpectrumVerdict spectrum_locked() {
  SpectrumVerdict out;
  if (g_sample_count < 64) {
    return out;
  }
  // l'echantillon dans l'ordre du temps
  std::vector<Sample> s;
  s.reserve(g_sample_count);
  const size_t start = (g_sample_head + kSampleRing - g_sample_count) % kSampleRing;
  for (size_t i = 0; i < g_sample_count; i++) {
    s.push_back(g_samples[(start + i) % kSampleRing]);
  }
  const float t_end = s.back().t;
  const float t_begin = s.front().t;
  const double avail = (double)(t_end - t_begin);
  constexpr double fs = 10.0;  // Hz — Nyquist 5 Hz, au-dessus des 2,13 Hz des feuilles
  size_t n = 2048;             // 204,8 s
  while (n > 512 && (double)n / fs > avail) {
    n >>= 1;
  }
  if ((double)n / fs > avail) {
    return out;  // moins de 51,2 s d'horloge de brise : pas mesurable encore
  }
  out.n = n;
  out.window_s = (double)n / fs;
  // reechantillonnage uniforme par interpolation lineaire sur les `n / fs` dernieres secondes
  std::vector<double> d(n, 0.0), vx(n, 0.0), vz(n, 0.0), gx(n, 0.0), gz(n, 0.0);
  const double t0 = (double)t_end - (double)n / fs;
  size_t j = 0;
  for (size_t i = 0; i < n; i++) {
    const double t = t0 + (double)i / fs;
    while (j + 1 < s.size() && (double)s[j + 1].t <= t) {
      j++;
    }
    if (j + 1 < s.size() && (double)s[j + 1].t > (double)s[j].t) {
      const double a =
          std::min(std::max((t - (double)s[j].t) / ((double)s[j + 1].t - (double)s[j].t), 0.0), 1.0);
      d[i] = (double)s[j].d + a * ((double)s[j + 1].d - (double)s[j].d);
      vx[i] = (double)s[j].rx + a * ((double)s[j + 1].rx - (double)s[j].rx);
      vz[i] = (double)s[j].rz + a * ((double)s[j + 1].rz - (double)s[j].rz);
      gx[i] = (double)s[j].gx + a * ((double)s[j + 1].gx - (double)s[j].gx);
      gz[i] = (double)s[j].gz + a * ((double)s[j + 1].gz - (double)s[j].gz);
    } else {
      d[i] = (double)s[j].d;
      vx[i] = (double)s[j].rx;
      vz[i] = (double)s[j].rz;
      gx[i] = (double)s[j].gx;
      gz[i] = (double)s[j].gz;
    }
  }
  // enveloppe : moyenne de |d| par seconde, puis ecart-type / moyenne
  {
    const size_t per = (size_t)fs;
    std::vector<double> env;
    for (size_t i = 0; i + per <= n; i += per) {
      double m = 0.0;
      for (size_t k = 0; k < per; k++) {
        m += std::fabs(d[i + k]);
      }
      env.push_back(m / (double)per);
    }
    double mean = 0.0;
    for (double e : env) {
      mean += e;
    }
    mean /= (double)std::max<size_t>(env.size(), 1);
    double var = 0.0;
    for (double e : env) {
      var += (e - mean) * (e - mean);
    }
    var /= (double)std::max<size_t>(env.size(), 1);
    out.env_cv = mean > 1e-12 ? std::sqrt(var) / mean : 0.0;
  }
  // spectre : moyenne retiree, fenetre de Hann, part de la raie dominante hors continu
  {
    double mean = 0.0;
    for (double v : d) {
      mean += v;
    }
    mean /= (double)n;
    std::vector<std::complex<double>> a(n);
    for (size_t i = 0; i < n; i++) {
      const double w = 0.5 - 0.5 * std::cos(2.0 * kPi * (double)i / (double)(n - 1));
      a[i] = std::complex<double>((d[i] - mean) * w, 0.0);
    }
    fft(a);
    double total = 0.0, peak = 0.0;
    size_t peak_k = 1;
    for (size_t k = 1; k < n / 2; k++) {
      const double p = std::norm(a[k]);
      total += p;
      if (p > peak) {
        peak = p;
        peak_k = k;
      }
    }
    out.peak_pct = total > 0.0 ? peak / total * 100.0 : 100.0;
    out.peak_hz = (double)peak_k * fs / (double)n;
  }
  // (9) LE CAP. Moyenne glissante de 2 s sur le VECTEUR : elle efface le balancement (>= 2,2 Hz) et
  // le fremissement (>= 8,8 Hz) et ne garde que la flexion moyenne, donc le cap du LEAN. Sans elle
  // la mesure est vide (voir foliage_wind.h). Les instants ou la flexion lissee tombe sous le quart
  // de sa moyenne sont ecartes : leur cap est un rapport de deux quasi-zeros. C'est le sens
  // CONSERVATEUR de l'exclusion — ce sont eux qui portent les plus grands ecarts de cap.
  if (n > kDirSmoothSamples + 64) {
    const size_t m = n - kDirSmoothSamples + 1;
    std::vector<double> lx(m, 0.0), lz(m, 0.0);
    double ax = 0.0, az = 0.0;
    for (size_t k = 0; k < kDirSmoothSamples; k++) {
      ax += vx[k];
      az += vz[k];
    }
    lx[0] = ax / (double)kDirSmoothSamples;
    lz[0] = az / (double)kDirSmoothSamples;
    for (size_t i = 1; i < m; i++) {
      ax += vx[i + kDirSmoothSamples - 1] - vx[i - 1];
      az += vz[i + kDirSmoothSamples - 1] - vz[i - 1];
      lx[i] = ax / (double)kDirSmoothSamples;
      lz[i] = az / (double)kDirSmoothSamples;
    }
    double mean_mag = 0.0;
    for (size_t i = 0; i < m; i++) {
      mean_mag += std::sqrt(lx[i] * lx[i] + lz[i] * lz[i]);
    }
    mean_mag /= (double)m;
    double sc = 0.0, ss = 0.0;
    std::vector<double> angs;
    angs.reserve(m);
    for (size_t i = 0; i < m; i++) {
      const double mag = std::sqrt(lx[i] * lx[i] + lz[i] * lz[i]);
      if (!(mag > 0.25 * mean_mag)) {
        continue;
      }
      const double a = std::atan2(lz[i], lx[i]);
      sc += std::cos(a);
      ss += std::sin(a);
      angs.push_back(a);
    }
    if (angs.size() >= 64) {
      const double mu = std::atan2(ss, sc);
      std::vector<double> dev;
      dev.reserve(angs.size());
      for (double a : angs) {
        double e = a - mu;
        while (e > kPi) {
          e -= 2.0 * kPi;
        }
        while (e < -kPi) {
          e += 2.0 * kPi;
        }
        dev.push_back(e);
      }
      std::sort(dev.begin(), dev.end());
      const double p5 = dev[(size_t)(0.05 * (double)dev.size())];
      const double p95 = dev[(size_t)(0.95 * (double)dev.size())];
      out.dir_spread_deg = (p95 - p5) * 180.0 / kPi;
      out.dir_ok = true;
    }
  }
  // DIAGNOSTIC, hors verdict : de combien de degres par seconde le cap POUSSE aux shaders tourne.
  // Avant le lissage de `set_wind_state` il portait la marche aleatoire de ND (~25 deg/s) ; apres,
  // il derive. Publie pour que le lissage se verifie au lieu de se croire.
  {
    double sl = 0.0;
    size_t cnt = 0;
    for (size_t i = 1; i < n; i++) {
      const double la = std::sqrt(gx[i - 1] * gx[i - 1] + gz[i - 1] * gz[i - 1]);
      const double lb = std::sqrt(gx[i] * gx[i] + gz[i] * gz[i]);
      if (la < 1e-6 || lb < 1e-6) {
        continue;
      }
      const double dot = (gx[i - 1] * gx[i] + gz[i - 1] * gz[i]) / (la * lb);
      const double crs = (gx[i - 1] * gz[i] - gz[i - 1] * gx[i]) / (la * lb);
      sl += std::fabs(std::atan2(crs, std::min(std::max(dot, -1.0), 1.0)));
      cnt++;
    }
    out.slew_deg_s = cnt ? sl / (double)cnt * fs * 180.0 / kPi : -1.0;
  }
  out.ok = true;
  return out;
}

// Le calcul des sept verdicts, sous verrou.
void recompute_and_publish_locked() {
  std::vector<Instance> pop;
  u64 trees_drawn = 0;
  for (const auto& kv : g_trees) {
    if (!kv.second.drawn) {
      continue;
    }
    trees_drawn++;
    pop.insert(pop.end(), kv.second.instances.begin(), kv.second.instances.end());
  }

  const bool on = enabled();
  const float bend_m = on ? bend_metres() : 0.f;
  // la flexion en metres, lue au point de lecture : l'uniforme reellement pousse x le poids
  // reellement televerse (voir l'en-tete)
  auto response_m = [bend_m](const Instance& in) { return bend_m * in.peak_w; };

  // (3) immobiles
  u64 still = 0;
  for (const auto& in : pop) {
    if (!(response_m(in) > kStillM)) {
      still++;
    }
  }

  // (4) paires divergentes — grille uniforme au pas du rayon de paire
  std::unordered_map<u64, std::vector<u32>> grid;
  grid.reserve(pop.size() * 2 + 1);
  auto cell_of = [](float v) { return (s64)std::floor(v / kPairRadiusU); };
  auto key_of = [](s64 cx, s64 cz) {
    return ((u64)(u32)(s32)cx << 32) | (u64)(u32)(s32)cz;
  };
  for (u32 i = 0; i < pop.size(); i++) {
    grid[key_of(cell_of(pop[i].anchor_x), cell_of(pop[i].anchor_z))].push_back(i);
  }
  u64 pairs = 0;
  u64 divergent = 0;
  float worst_ratio = 1.f;
  const float r2 = kPairRadiusU * kPairRadiusU;
  for (u32 i = 0; i < pop.size(); i++) {
    const auto& a = pop[i];
    const s64 cx = cell_of(a.anchor_x);
    const s64 cz = cell_of(a.anchor_z);
    for (s64 dx = -1; dx <= 1; dx++) {
      for (s64 dz = -1; dz <= 1; dz++) {
        auto it = grid.find(key_of(cx + dx, cz + dz));
        if (it == grid.end()) {
          continue;
        }
        for (u32 j : it->second) {
          if (j <= i) {
            continue;
          }
          const auto& b = pop[j];
          const float ddx = a.anchor_x - b.anchor_x;
          const float ddz = a.anchor_z - b.anchor_z;
          if (ddx * ddx + ddz * ddz > r2) {
            continue;
          }
          if (!(a.height_m > 0.f) || !(b.height_m > 0.f)) {
            continue;
          }
          const float hr = a.height_m > b.height_m ? a.height_m / b.height_m
                                                   : b.height_m / a.height_m;
          if (hr > kHeightRatioMax) {
            continue;
          }
          pairs++;
          const float ra = response_m(a) / a.height_m;
          const float rb = response_m(b) / b.height_m;
          const float lo = std::min(ra, rb);
          const float hi = std::max(ra, rb);
          float ratio;
          if (!(lo > kStillM / 100.f)) {
            ratio = (hi > kStillM / 100.f) ? 1e6f : 1.f;
          } else {
            ratio = hi / lo;
          }
          if (ratio > worst_ratio) {
            worst_ratio = ratio;
          }
          if (ratio > kDivergeRatio) {
            divergent++;
          }
        }
      }
    }
  }

  // (6) tronc / couronne, et (2) ligne de sol des buissons enfonces
  double base_to_crown = 0.0;
  double base_shift_mm = 0.0;
  u64 shrubs = 0, shrubs_ground = 0, shrubs_sunk = 0, shrubs_native = 0;
  for (const auto& in : pop) {
    if (in.peak_w > 0.f) {
      base_to_crown = std::max(base_to_crown, (double)in.low_w / (double)in.peak_w);
    }
    if (in.shrub) {
      shrubs++;
      if (in.ground_found) {
        shrubs_ground++;
      }
      if (in.sunk_mm > 0) {
        shrubs_sunk++;
      }
      if (in.native_stiff) {
        shrubs_native++;
      }
      // deplacement dessine a la ligne de sol : |poids interpole| x (flexion ajoutee + cisaillement
      // natif x hauteur-par-poids). `height_m / peak_w` = span / taille = ce que le shader multiplie.
      double k_m = 0.0;
      if (in.native_stiff && in.peak_w > 0.f) {
        k_m = (double)in.height_m / (double)in.peak_w;
      }
      const double shift_m =
          (double)in.base_w * ((double)bend_m + k_m * (double)g_shrub_native_shear_peak);
      base_shift_mm = std::max(base_shift_mm, shift_m * 1000.0);
    }
  }

  // (8) LE GRADIENT D'EXTREMITE, instance par instance, sur les poids RELUS APRES QUANTIFICATION.
  // Le MINIMUM est publie : une seule plante qui bouge d'un bloc ouvre le verdict. Une instance dont
  // une bande manque de sommets est NON MESURABLE et se compte a part — un seau exclu qu'on ne
  // publie pas se lit « correct ».
  double tip_grad_min = 1e30;
  u64 tip_measured = 0, tip_unmeasured = 0;
  for (const auto& in : pop) {
    if (!(in.att_w >= 0.f) || !(in.tip_w >= 0.f)) {
      tip_unmeasured++;
      continue;
    }
    tip_measured++;
    // attache EXACTEMENT immobile : le rapport n'est pas infini, il est plafonne — une valeur
    // infinie rendrait le minimum insensible a cette instance au lieu de la juger.
    const double g = in.att_w > 1e-9f ? (double)in.tip_w / (double)in.att_w : 1e6;
    tip_grad_min = std::min(tip_grad_min, g);
  }

  // (1) le natif
  u64 dead_slots = 0;
  bool ring_ok = false;
  if (g_gw_seeded && (u32)(g_gw_last_time - g_gw_first_time) >= 256) {
    ring_ok = true;
    for (int i = 0; i < 64; i++) {
      if ((u32)(g_gw_last_time - g_gw_slot_last_change[i]) > 128) {
        dead_slots++;
      }
    }
  }
  // CADENCE : les pas de vent EXECUTES contre le temps de JEU ecoule sur les memes images, les
  // deux rapportes par `update-wind-ticks!` lui-meme. La montre murale et les ticks de
  // `fixed_tick` (eteint par defaut) ne sont plus des references : voir foliage_wind.h.
  double rate_dev_pct = 0.0;
  bool rate_ok = false;
  const double expected = g_rate_expected;
  const char* rate_ref = "game";
  if (expected >= 600.0) {  // au moins 10 s de temps de jeu mesure
    rate_ok = true;
    rate_dev_pct = std::fabs(g_rate_got - expected) / expected * 100.0;
  }
  // La part de temps sur la butee est PUBLIEE mais n'entre pas dans le verdict : mesuree ici meme
  // sur le chemin stock au bit pres (x86, 60 images/s, rate_ticks=1, ratio_peak=1.000), elle vaut
  // 3 a 7 % — c'est le ressort de ND qui tape sa butee dans les bouffees, sur console aussi. Le
  // defaut du port etait la saturation PERMANENTE (anneau a moitie vide, commande x4), et celle-la
  // se lit sur les deux autres composantes : slots morts et cadence.
  const double sat_pct =
      g_native_samples > 0 ? (double)g_native_sat / (double)g_native_samples * 100.0 : 0.0;
  const bool v1_measured = ring_ok && rate_ok && g_native_samples > 0;
  const double dead_pct = (double)dead_slots / 64.0 * 100.0;
  const u64 v1 = v1_measured ? (u64)std::lround(std::max(dead_pct, rate_dev_pct)) : kNoMeasurement;

  // (5) et (7)
  const SpectrumVerdict sp = on ? spectrum_locked() : SpectrumVerdict{};
  const u64 v5 = sp.ok ? (u64)std::lround(sp.peak_pct) : kNoMeasurement;

  u64 unclassified = 0;
  for (const auto& kv : g_unclassified) {
    unclassified += kv.second;
  }

  // LA REGLE ANTI-FAUX-VERT : aucune paire examinee, ou brise ETEINTE (toute paire est alors
  // immobile des deux cotes et le zero ne mesure rien) => les verdicts (2)-(7) ne peuvent pas etre
  // verts. Le natif (1) se mesure dans les deux etats.
  const bool measured = (pairs > 0) && on;
  const u64 v2 = measured ? (u64)std::lround(base_shift_mm) : kNoMeasurement;
  const u64 v3 = measured ? still : kNoMeasurement;
  const u64 v4 = measured ? divergent : kNoMeasurement;
  const bool v6_ok = measured && base_to_crown <= kV6MaxRatio;
  const bool v7_ok = measured && sp.ok && sp.env_cv >= kV7MinCv;
  const bool v8_measured = measured && tip_measured >= kTipMinInstances;
  const bool v8_ok = v8_measured && tip_grad_min >= kV8MinGradient;
  const bool v9_ok = measured && sp.ok && sp.dir_ok && sp.dir_spread_deg >= kV9MinSpreadDeg;

  u64 levels_uncovered = 0;
  std::string missing_levels;
  for (const char* level : kVegetatedLevels) {
    if (!g_levels_seen.count(level)) {
      ++levels_uncovered;
      if (!missing_levels.empty()) missing_levels += ",";
      missing_levels += level;
    }
  }
  const auto contacts = shrub_contact_stats();
  const auto tie_contacts = tie_contact_stats();
  // Linked uploads establish activity of the shared contact path, not geometric
  // displacement on the GPU. Keep the contact verdict unmeasured until both
  // a player and an actor source have reached a populated shrub draw.
  const bool contact_measured = on && contacts.uploads > 0 && contacts.shrub_instances > 0 &&
                                contacts.jak_samples > 0 && contacts.object_samples > 0 &&
                                tie_contacts.uploads > 0 && tie_contacts.eligible_instances > 0 &&
                                tie_contacts.jak_samples > 0 && tie_contacts.object_samples > 0;
  const u64 contact_defects = contact_measured
      ? contacts.binding_failures + tie_contacts.binding_failures + tie_contacts.mapping_failures
      : kNoMeasurement;
  const u64 open = (v1 <= kV1MaxDevPct ? 0 : 1) + (v2 == 0 ? 0 : 1) + (v3 == 0 ? 0 : 1) +
                   (v4 == 0 ? 0 : 1) + (v5 <= kV5MaxPeakPct ? 0 : 1) + (v6_ok ? 0 : 1) +
                   (v7_ok ? 0 : 1) + (v8_ok ? 0 : 1) + (v9_ok ? 0 : 1) +
                   (levels_uncovered == 0 ? 0 : 1) + (contact_defects == 0 ? 0 : 1);

  char buf[64];
  autoport_proof::publish("wind_owner_defects_open", open);
  autoport_proof::publish("wind_levels_uncovered", levels_uncovered);
  autoport_proof::publish("wind_levels_expected", std::size(kVegetatedLevels));
  autoport_proof::publish_text("wind_levels_missing", missing_levels.c_str());
  autoport_proof::publish("wind_contact_defects", contact_defects);
  autoport_proof::publish("wind_contact_uploads", contacts.uploads);
  autoport_proof::publish("wind_contact_binding_failures", contacts.binding_failures);
  autoport_proof::publish("wind_contact_shrub_instances", contacts.shrub_instances);
  autoport_proof::publish("wind_contact_jak_samples", contacts.jak_samples);
  autoport_proof::publish("wind_contact_object_samples", contacts.object_samples);
  autoport_proof::publish("wind_contact_tie_uploads", tie_contacts.uploads);
  autoport_proof::publish("wind_contact_tie_binding_failures", tie_contacts.binding_failures);
  autoport_proof::publish("wind_contact_tie_mapping_failures", tie_contacts.mapping_failures);
  autoport_proof::publish("wind_contact_tie_instances", tie_contacts.eligible_instances);
  autoport_proof::publish("wind_contact_tie_vertices", tie_contacts.eligible_vertices);
  autoport_proof::publish("wind_contact_tie_jak_samples", tie_contacts.jak_samples);
  autoport_proof::publish("wind_contact_tie_object_samples", tie_contacts.object_samples);
  autoport_proof::publish("wind_native_stock_dev_pct", v1);
  autoport_proof::publish("wind_ring_dead_slots", ring_ok ? dead_slots : kNoMeasurement);
  std::snprintf(buf, sizeof(buf), "%.3f", rate_ok ? rate_dev_pct : -1.0);
  autoport_proof::publish_text("wind_native_rate_dev_pct", buf);
  autoport_proof::publish("wind_rate_frames", g_rate_frames);
  autoport_proof::publish("wind_rate_hitch_frames", g_rate_hitch);
  autoport_proof::publish("wind_rate_expected_steps", (u64)std::llround(g_rate_expected));
  autoport_proof::publish("wind_rate_got_steps", (u64)std::llround(g_rate_got));
  autoport_proof::publish("wind_native_steps_seen", (u64)std::llround(g_gw_sum_dwind));
  // DIAGNOSTIC, HORS VERDICT : le meme ecart mesure contre la MONTRE MURALE — la reference de
  // l'essai 11. Il ne juge rien parce qu'il ne mesure pas le vent : `time-adjust-ratio` est plafonne
  // a 4,0 (display.gc `set-time-ratios`), donc sous 15 images/s le jeu tourne AU RALENTI et la
  // brise doit ralentir avec lui. Ce chiffre dit de combien ; il reste publie pour que la valeur
  // rouge de l'essai 11 (3,6 %) ne disparaisse pas en silence.
  std::snprintf(buf, sizeof(buf), "%.3f",
                g_gw_sum_dwall > 0.0
                    ? std::fabs(g_gw_sum_dwind - g_gw_sum_dwall * 60.0) / (g_gw_sum_dwall * 60.0) *
                          100.0
                    : -1.0);
  autoport_proof::publish_text("wind_native_wall_dev_pct", buf);
  std::snprintf(buf, sizeof(buf), "%.3f", sat_pct);
  autoport_proof::publish_text("wind_native_sat_pct", buf);
  autoport_proof::publish("wind_native_samples", g_native_samples);
  autoport_proof::publish("wind_shrub_base_shift_mm", v2);
  autoport_proof::publish("wind_instances_still", v3);
  autoport_proof::publish("wind_divergent_pairs", v4);
  autoport_proof::publish("wind_spectrum_peak_pct", v5);
  std::snprintf(buf, sizeof(buf), "%.3f", measured ? base_to_crown : -1.0);
  autoport_proof::publish_text("wind_base_to_crown_ratio", buf);
  std::snprintf(buf, sizeof(buf), "%.3f", (measured && sp.ok) ? sp.env_cv : -1.0);
  autoport_proof::publish_text("wind_envelope_cv", buf);
  std::snprintf(buf, sizeof(buf), "%.3f", v8_measured ? std::min(tip_grad_min, 999999.0) : -1.0);
  autoport_proof::publish_text("wind_tip_gradient_min", buf);
  autoport_proof::publish("wind_tip_instances", tip_measured);
  autoport_proof::publish("wind_tip_unmeasured", tip_unmeasured);
  std::snprintf(buf, sizeof(buf), "%.3f",
                (measured && sp.ok && sp.dir_ok) ? sp.dir_spread_deg : -1.0);
  autoport_proof::publish_text("wind_dir_variation_deg", buf);
  std::snprintf(buf, sizeof(buf), "%.3f", sp.ok ? sp.slew_deg_s : -1.0);
  autoport_proof::publish_text("wind_dir_slew_deg_s", buf);
  autoport_proof::publish("wind_pairs_examined", pairs);
  autoport_proof::publish("wind_instances_censused", (u64)pop.size());
  autoport_proof::publish("wind_trees_drawn", trees_drawn);
  autoport_proof::publish("wind_unclassified_protos", unclassified);
  autoport_proof::publish("wind_option_on", on ? 1 : 0);
  autoport_proof::publish("wind_shrubs_censused", shrubs);
  autoport_proof::publish("wind_shrubs_ground_found", shrubs_ground);
  autoport_proof::publish("wind_shrubs_sunk", shrubs_sunk);
  autoport_proof::publish("wind_shrubs_native_stiff", shrubs_native);
  autoport_proof::publish("wind_worst_ratio_x100",
                          (u64)std::min(1e9, (double)worst_ratio * 100.0));
  autoport_proof::publish("wind_bend_mm", (u64)(bend_m * 1000.f + 0.5f));
  if (measured) {
    // Le chemin de code a tire : des paires reelles ont ete jugees sur des instances reellement
    // dessinees, brise allumee. Aucun `note_hit` quand rien n'a ete mesure.
    autoport_proof::note_hit_for("foliage-wind");
  }

  static u64 s_logged = 0;
  if ((s_logged++ % 4) == 0) {
    lg::info(
        "[foliage-wind] verdicts open={} v1_native_dev={} (dead_slots={} rate_dev={:.3f}% ref={} "
        "wind_steps={:.0f} expected={:.0f} sat={:.3f}% samples={}) v2_base_shift_mm={} "
        "v3_still={} v4_divergent={} (pairs={}) v5_peak={}% ({:.3f} Hz, fenetre {:.0f} s) "
        "v6_base_to_crown={:.3f} v7_env_cv={:.3f} v8_tip_gradient_min={:.3f} (mesurees={} "
        "non_mesurables={}) v9_dir_spread={:.1f} deg (ok={}) instances={} shrubs={} sol={} "
        "enfonces={} natif_raideur={} trees_drawn={} option_on={} bend_m={:.3f} "
        "native_shear_peak={:.4f}",
        open, v1, dead_slots, rate_dev_pct, rate_ref, g_rate_got, expected, sat_pct,
        g_native_samples, v2, v3, v4, pairs, v5, sp.peak_hz, sp.window_s, base_to_crown,
        sp.env_cv, v8_measured ? std::min(tip_grad_min, 999999.0) : -1.0, tip_measured,
        tip_unmeasured, sp.dir_ok ? sp.dir_spread_deg : -1.0, sp.dir_ok ? 1 : 0, pop.size(),
        shrubs, shrubs_ground, shrubs_sunk, shrubs_native, trees_drawn,
        on ? 1 : 0, bend_m, g_shrub_native_shear_peak);
  }
}

}  // namespace

void frame(u64 frame_idx) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (frame_idx == g_last_frame_idx) {
    return;  // deja comptee par un autre renderer sur cette image
  }
  g_last_frame_idx = frame_idx;
  g_frames++;
  // L'ECHANTILLON DE LA LOI : le deplacement sous le vent d'un sommet de couronne (w = 1,
  // bend = 1 m) d'une plante de reference, a l'instant de l'horloge de brise. C'est la fonction que
  // les shaders evaluent, aux memes instants : le spectre et l'enveloppe publies sont ceux du
  // mouvement dessine, pas d'un modele a cote.
  if (enabled()) {
    const float t = clock_seconds(frame_idx, g_paused);
    if (t != g_sample_last_t) {
      g_sample_last_t = t;
      float ox = 0.f, oz = 0.f;
      breeze_offset(0.f, 0.f, g_dir_x, g_dir_z, 0.37f, t, 1.f, 1.f, flutter_fraction(), &ox, &oz);
      if (g_samples.empty()) {
        g_samples.resize(kSampleRing);
      }
      // DANS LE REPERE DU VENT. Le verdict (9) doit juger le virage que NOTRE loi ajoute, pas la
      // marche aleatoire de ND : mesure sur le cap ABSOLU, il rendait 320 degres (le tour complet)
      // avec un lacet a ZERO — un vert impossible a mettre au rouge. Projetee dans le repere du
      // cap instantane, la variation restante est exactement celle de `breeze_yaw` + le terme
      // lateral : la meme loi sans lacet rend 18 degres, avec 56.
      const float rx = ox * g_dir_x + oz * g_dir_z;
      const float rz = -ox * g_dir_z + oz * g_dir_x;
      g_samples[g_sample_head] = Sample{t, rx, rx, rz, g_dir_x, g_dir_z};
      g_sample_head = (g_sample_head + 1) % kSampleRing;
      if (g_sample_count < kSampleRing) {
        g_sample_count++;
      }
    }
  }
  if ((g_frames % kRepublishFrames) == 0) {
    recompute_and_publish_locked();
    trunk_census_publish();  // shrub-trunk-contact : meme cadence, verrou distinct
  }
}

// ================================================================================================
// shrub-trunk-contact (owner 2026-09-13) — LA CLASSE TRONC/FEUILLAGE, TIREE DES DONNEES.
//
// CE QUE L'OWNER A VU. « le tronc s'ecrase aussi comme si c'etait un vulgaire brin d'herbe c'est
// debile (et en plus les feuilles sont donc desolidarisees du tronc quand ca se produit) ».
//
// CE QUE LA MESURE A TROUVE. Un mini-palmier n'est pas un modele : c'est un ASSEMBLAGE de deux
// instances de deux systemes de rendu differents. A Geyser Rock (`training`), le tronc est une
// instance TIE de `palmplant-base.mb` (32) et la frondaison une instance SHRUB de
// `palmplant-top.mb` (32), posees a 4 a 99 cm l'une de l'autre. Les deux recoivent la loi de
// contact de l'herbe, chacune avec SON ancre :
//   * la frondaison pivote sur son propre pied (`base_y == ymin`), donc son pied ne bouge pas ;
//   * le tronc pivote sur le sien, donc sa CIME prend le deplacement maximal.
// Le tronc s'ecrase (`heightMul` descend a 0,2) et sa cime part sous la frondaison immobile : les
// deux plaintes motivent la correction ; leur resolution exige une mesure du deplacement rendu.
//
// LA REGLE : promotion geometrique parmi les plantes deja eligibles au contact. Le lexique
// `shrub_contact_prototype` filtre cette population ; la promotion tronc utilise ensuite la
// relation de portage entre prototypes, dans chaque niveau.
//
// DEUX REGLES ECARTEES, PAR LA MESURE. (1) L'ELANCEMENT r/h : `palmplant-base.mb` rend 0,332 de
// mediane, mais `fin-tree.mb` rend 0,167, les mousses, les kelps et les massettes descendent plus
// bas encore — or ceux-la DOIVENT plier. (2) Le PORTAGE par instance seule : a 1,5 m de rayon il
// classait 1790 porteurs, champignons et touffes d'herbe compris, simplement parce qu'une plante
// en surplombe une autre sur une pente.
//
// LA MARGE, MESUREE SUR LES 26 NIVEAUX DE JAK 1. Part des instances d'un prototype qui en portent
// une d'un prototype DIFFERENT :
//     trunk02vine3.mb        19/19   100,0 %      <- retenu
//     palmplant-base.mb      89/91    97,8 %      <- retenu (le mini-palmier de Geyser Rock)
//     bch-palmplant-base.mb  70/80    87,5 %      <- retenu (celui de la plage)
//     ----------------------------------- seuil a 60 % -----------------------------------
//     swp-thornbush-05.mb    47/100   47,0 %      <- ecarte
//     swp-thornbush-09a.mb   12/28    42,9 %      <- ecarte
//     v2-coral-seaweed.mb   100/240   41,7 %      <- ecarte
// Quarante points separent le dernier retenu du premier ecarte. Le seuil est pose AU MILIEU de ce
// vide, pas sur un bord (`minimum-on-search-boundary`).
// ================================================================================================

namespace {

// Le PIED de la portee se rencontre DANS la moitie haute du porteur, et pas au-dessus de sa cime
// d'un quart de sa hauteur. Mesure sur les 320 instances de `bch-palmplant-base.mb` : le pied de
// la frondaison tombe entre 0,56 et 0,86 de la hauteur du tronc, soit 0,2 a 0,35 m SOUS sa cime
// (les deux geometries s'interpenetrent, c'est une jointure).
constexpr float kSupportFootFrac = 0.50f;
constexpr float kSupportOverFrac = 0.25f;
// Ce qui est porte doit DEPASSER franchement : sinon deux troncs voisins se portent l'un l'autre.
constexpr float kSupportRiseFrac = 0.50f;
// L'emprise : la portee horizontale du porteur, plus un metre. Mesure : la frondaison se pose
// jusqu'a 2,37 m du centroide du tronc, dont la portee propre vaut 1,1 a 1,4 m.
constexpr float kSupportSlackMeters = 1.0f;
// La promotion au prototype. En dessous de ce nombre d'instances, la part n'est pas une mesure :
// `fan-coralgroup.mb` rendait 1/1 = 100 %.
constexpr u32 kTrunkMinInstances = 8;
constexpr double kTrunkMinFrac = 0.60;

struct VegInst {
  tfrag3::TieTree::SwayInstance* si = nullptr;
  const std::string* proto = nullptr;
};

bool supports(const VegInst& carrier, const VegInst& carried) {
  if (carrier.si == carried.si || *carrier.proto == *carried.proto) return false;
  const auto& A = *carrier.si;
  const auto& B = *carried.si;
  const float H = A.ymax - A.ymin;
  if (!(H > 0.f)) return false;
  const float reach = A.r_xz + kSupportSlackMeters * 4096.f;
  const float dx = A.cx - B.cx, dz = A.cz - B.cz;
  if (dx * dx + dz * dz > reach * reach) return false;
  if (B.ymin < A.ymin + kSupportFootFrac * H) return false;
  if (B.ymin > A.ymax + kSupportOverFrac * H) return false;
  if (B.ymax < A.ymax + kSupportRiseFrac * H) return false;
  return true;
}

// Toutes les instances de vegetation ELIGIBLES AU CONTACT du niveau, TIE et SHRUB confondus : la
// relation de portage traverse les deux systemes, et c'est precisement ce qu'aucun des deux
// chargeurs ne pouvait voir depuis sa propre table.
void gather_contact_instances(tfrag3::Level& lev, std::vector<VegInst>& out) {
  for (auto& tree : lev.shrub_trees) {
    for (size_t mi = 0; mi < tree.sway_instances.size(); mi++) {
      auto& si = tree.sway_instances[mi];
      if (!si.valid || mi >= tree.wind_proto_of_inst.size()) {
        continue;
      }
      const size_t pi = tree.wind_proto_of_inst[mi];
      if (pi >= tree.proto_names.size() || !shrub_contact_prototype(tree.proto_names[pi])) {
        continue;
      }
      si.proto_idx = (u16)pi;
      out.push_back({&si, &tree.proto_names[pi]});
    }
  }
  // Le TIE est livre en QUATRE geometries qui reposent les MEMES instances. Les classer quatre
  // fois ne changerait pas le verdict par instance, mais il fausserait la PART par prototype (les
  // parts se comparent a un seuil) : on ne recense donc que la geometrie 0, et on reporte sa
  // decision sur les autres a la fin.
  if (!lev.tie_trees.empty()) {
    for (auto& tree : lev.tie_trees[0]) {
      for (auto& si : tree.sway_instances) {
        if (!si.valid || si.proto_idx >= tree.proto_names.size()) {
          continue;
        }
        if (!shrub_contact_prototype(tree.proto_names[si.proto_idx])) {
          continue;
        }
        out.push_back({&si, &tree.proto_names[si.proto_idx]});
      }
    }
  }
}


// ---------------------------------------------------------------------------- le RECENSEMENT ---
// Diagnostic structurel CPU des classes et ancres. Aucune mesure GPU, aucun deplacement reel
// de tronc/feuillage ni ecart de deplacement a la jonction ne sont mesures ici.
std::mutex g_trunk_mutex;
std::set<std::string> g_trunk_levels;        // un niveau recharge ne se recompte pas
using TrunkProtoKey = std::pair<std::string, std::string>;  // niveau, prototype
std::map<TrunkProtoKey, std::string> g_trunk_proto_rows;  // porteuses/total, separe des classes
struct TrunkClassCounts {
  u32 row_id = 0;  // stable pour toute la course, meme si un niveau arrive plus tard
  u32 trunk_instances = 0, trunk_verts = 0;
  u32 foliage_instances = 0, foliage_verts = 0;
};
std::map<TrunkProtoKey, TrunkClassCounts> g_trunk_class_rows;
u32 g_trunk_instances = 0, g_trunk_verts = 0;
u32 g_foliage_instances = 0, g_foliage_verts = 0;
u32 g_joint_pairs = 0;
// Ecarts absolus des pivots CPU au plan d'attache de la plante portee. Un zero ne prouve ni immobilite
// du tronc ni solidarite de la jonction dans le rendu.
u32 g_joint_pivot_offset_mm = 0;
// Reference structurelle du pivot de sol, independante de l'armement.
u32 g_joint_ground_pivot_offset_mm = 0;
u32 g_joint_span_min_mm = UINT32_MAX;
u64 g_trunk_anchored = 0;          // troncs ayant RECU une ancre de contact : doit rester 0
u64 g_foliage_anchored = 0;        // feuillages ayant recu une ancre : doit rester > 0

void trunk_census_note(const std::string& level,
                       const std::vector<VegInst>& veg,
                       u32 trunk_instances,
                       u32 trunk_verts,
                       u32 joint_pairs,
                       const std::map<std::string, u32>& proto_total,
                       const std::map<std::string, u32>& proto_carrying) {
  std::lock_guard<std::mutex> lock(g_trunk_mutex);
  if (!g_trunk_levels.insert(level).second) {
    return;  // ce niveau a deja ete recense : un rechargement ne doit pas doubler les comptes
  }
  g_trunk_instances += trunk_instances;
  g_trunk_verts += trunk_verts;
  g_joint_pairs += joint_pairs;
  for (const auto& v : veg) {
    // Sommets canoniques classes, une fois par niveau ; note_hit_for respecte le bras OFF.
    autoport_proof::note_hit_for(kTrunkItemId, v.si->n_verts);
    auto inserted = g_trunk_class_rows.emplace(TrunkProtoKey{level, *v.proto}, TrunkClassCounts{});
    auto& counts = inserted.first->second;
    if (inserted.second) counts.row_id = (u32)g_trunk_class_rows.size() - 1;
    if (v.si->load_bearing) {
      counts.trunk_instances++;
      counts.trunk_verts += v.si->n_verts;
    } else {
      counts.foliage_instances++;
      counts.foliage_verts += v.si->n_verts;
    }
    if (!v.si->load_bearing) {
      g_foliage_instances++;
      g_foliage_verts += v.si->n_verts;
    }
    if (v.si->carried) {
      // Ecart structurel entre le pivot de sol et le plan d'attache, sans simulation du contact.
      const float off = std::abs(v.si->base_y - v.si->contact_pin_y);
      if (off > 0.f) {
        g_joint_ground_pivot_offset_mm =
            std::max(g_joint_ground_pivot_offset_mm, (u32)(off / 4096.f * 1000.f + 0.5f));
      }
    }
  }
  for (const auto& total : proto_total) {
    const auto& name = total.first;
    const auto it_t = proto_total.find(name);
    const auto it_c = proto_carrying.find(name);
    g_trunk_proto_rows[{level, name}] =
        fmt::format("{}/{}", it_c == proto_carrying.end() ? 0 : it_c->second,
                    it_t == proto_total.end() ? 0 : it_t->second);
  }
}

}  // namespace

void trunk_note_anchor(const tfrag3::TieTree::SwayInstance& si, bool anchored, float pivot_y) {
  if (!anchored) {
    return;  // pas d'ancre = pas de contact : rien a mesurer, et surtout rien a compter comme
             // « feuillage ancre » ; son deplacement reel reste inconnu.
  }
  std::lock_guard<std::mutex> lock(g_trunk_mutex);
  if (si.load_bearing) {
    g_trunk_anchored++;  // un tronc a recu une ancre : c'est le defaut que la porte cherche
  } else {
    g_foliage_anchored++;
  }
  if (si.carried) {
    // Diagnostic structurel du pivot de deformation CPU, sans mesure de jonction GPU.
    const float off = std::abs(pivot_y - si.contact_pin_y);
    if (off > 0.f) {
      g_joint_pivot_offset_mm =
          std::max(g_joint_pivot_offset_mm, (u32)(off / 4096.f * 1000.f + 0.5f));
    }
    const float span = si.ymax - pivot_y;
    g_joint_span_min_mm =
        std::min(g_joint_span_min_mm, span > 0.f ? (u32)(span / 4096.f * 1000.f) : 0u);
  }
}

void trunk_census_publish() {
  std::lock_guard<std::mutex> lock(g_trunk_mutex);
  const u32 no_trunk = g_trunk_instances == 0 ? 1 : 0;
  const u32 no_joint = g_joint_pairs == 0 ? 1 : 0;
  // Nom historique : cette garde constate seulement une absence d'ancres de feuillage.
  const u32 frozen_all = g_foliage_anchored == 0 ? 1 : 0;
  const u64 defects =
      no_trunk + g_trunk_anchored + no_joint + g_joint_pivot_offset_mm + frozen_all;

  autoport_proof::publish_text(
      "shrub_trunk_rule",
      "instance_portant_une_plante_d_un_AUTRE_prototype;promue_au_prototype_a>=60%_des_instances;"
      "min_8_instances;promotion_geometrique_par_niveau;population_lexique_contact_existant");
  // Une ligne par niveau/prototype : ne pas depasser la limite logcat en concatenant le niveau.
  for (const auto& kv : g_trunk_class_rows) {
    const auto& c = kv.second;
    const auto class_key = fmt::format("shrub_trunk_classes_{}", c.row_id);
    const auto class_row = fmt::format(
        "level={},proto={},trunk_instances={},trunk_verts={},foliage_instances={},foliage_verts={}",
        kv.first.first, kv.first.second, c.trunk_instances, c.trunk_verts,
        c.foliage_instances, c.foliage_verts);
    autoport_proof::publish_text(class_key.c_str(), class_row.c_str());
    const auto ratio_key = fmt::format("shrub_trunk_protos_{}", c.row_id);
    const auto ratio_row = fmt::format("level={},proto={},carrying/total={}",
                                      kv.first.first, kv.first.second, g_trunk_proto_rows.at(kv.first));
    autoport_proof::publish_text(ratio_key.c_str(), ratio_row.c_str());
  }
  autoport_proof::publish("shrub_trunk_classes_count", g_trunk_class_rows.size());
  autoport_proof::publish("shrub_trunk_protos_count", g_trunk_proto_rows.size());
  autoport_proof::publish("shrub_trunk_instances", g_trunk_instances);
  autoport_proof::publish("shrub_trunk_verts", g_trunk_verts);
  autoport_proof::publish("shrub_foliage_instances", g_foliage_instances);
  autoport_proof::publish("shrub_foliage_verts", g_foliage_verts);
  autoport_proof::publish("shrub_trunk_anchored", g_trunk_anchored);
  autoport_proof::publish("shrub_foliage_anchored", g_foliage_anchored);
  autoport_proof::publish("shrub_joint_pairs", g_joint_pairs);
  autoport_proof::publish("shrub_joint_pivot_offset_mm", g_joint_pivot_offset_mm);
  autoport_proof::publish("shrub_joint_ground_pivot_offset_mm", g_joint_ground_pivot_offset_mm);
  autoport_proof::publish("shrub_joint_span_min_mm",
                          g_joint_span_min_mm == UINT32_MAX ? 0 : g_joint_span_min_mm);
  autoport_proof::publish("shrub_trunk_vacuous_no_trunk", no_trunk);
  autoport_proof::publish("shrub_trunk_vacuous_no_joint", no_joint);
  autoport_proof::publish("shrub_trunk_vacuous_all_frozen", frozen_all);
  autoport_proof::publish("shrub_trunk_anchor_defects", defects);
}

void classify_load_bearing(tfrag3::Level& lev) {
  std::vector<VegInst> veg;
  gather_contact_instances(lev, veg);

  // --- la relation de portage, instance par instance ---------------------------------------
  std::map<std::string, u32> proto_total, proto_carrying;
  std::vector<u8> carries(veg.size(), 0);
  // Predicat commun aux deux passes : aucun stockage quadratique des relations.
  for (size_t i = 0; i < veg.size(); i++) {
    proto_total[*veg[i].proto]++;
    for (size_t j = 0; j < veg.size(); j++) {
      if (supports(veg[i], veg[j])) {
        carries[i] = 1;
        break;  // seule l'existence d'une portee sert au ratio de promotion
      }
    }
    if (carries[i]) proto_carrying[*veg[i].proto]++;
  }

  // --- la promotion au PROTOTYPE ------------------------------------------------------------
  std::set<std::string> trunk_protos;
  for (const auto& kv : proto_total) {
    if (kv.second < kTrunkMinInstances) {
      continue;
    }
    const auto it = proto_carrying.find(kv.first);
    const u32 carrying = it == proto_carrying.end() ? 0 : it->second;
    if ((double)carrying / (double)kv.second >= kTrunkMinFrac) {
      trunk_protos.insert(kv.first);
    }
  }

  u32 trunk_instances = 0, trunk_verts = 0, joint_pairs = 0;
  for (auto& v : veg) {
    v.si->load_bearing = trunk_protos.count(*v.proto) != 0;
    v.si->carried = false;
    v.si->contact_pin_y = v.si->ymin;
    if (v.si->load_bearing) {
      trunk_instances++;
      trunk_verts += v.si->n_verts;
    }
  }
  // matrix_idx est compacte par geometrie dans extract_tie.cpp : son identite inter-LOD
  // n'est pas garantie. Conserver la classe par prototype, puis tester le placement de chaque
  // instance contre tous les troncs, LOD compris, sans les ajouter au census canonique.
  std::vector<VegInst> all_veg = veg;
  u32 trunk_instances_lod = 0;
  for (size_t geo = 1; geo < lev.tie_trees.size(); geo++) {
    for (auto& tree : lev.tie_trees[geo]) {
      for (auto& si : tree.sway_instances) {
        si.load_bearing = false;
        si.carried = false;
        si.contact_pin_y = si.ymin;
        if (!si.valid || si.proto_idx >= tree.proto_names.size()) continue;
        const auto& proto = tree.proto_names[si.proto_idx];
        if (!shrub_contact_prototype(proto)) continue;
        si.load_bearing = trunk_protos.count(proto) != 0;
        if (si.load_bearing) trunk_instances_lod++;
        all_veg.push_back({&si, &proto});
      }
    }
  }

  // Toutes les classes LOD sont posees avant de calculer les plans d'attache.
  // Seules les relations entre instances canoniques entrent dans joint_pairs.
  for (size_t i = 0; i < all_veg.size(); i++) {
    const auto& carrier = all_veg[i];
    if (!carrier.si->load_bearing) continue;
    for (size_t j = 0; j < all_veg.size(); j++) {
      const auto& target = all_veg[j];
      if (supports(carrier, target)) {
        target.si->carried = true;
        target.si->contact_pin_y = std::max(target.si->contact_pin_y, carrier.si->ymax);
        if (i < veg.size() && j < veg.size()) joint_pairs++;
      }
    }
  }

  std::string names;
  for (const auto& n : trunk_protos) {
    if (!names.empty()) {
      names += ",";
    }
    names += n;
  }
  lg::info(
      "[shrub-trunk-contact] lev={} eligibles={} porteuses={} protos_tronc={} instances_tronc={} "
      "(+{} en lod) regle=porte_une_autre_plante>={}%_des_instances,min={} noms={}",
      lev.level_name, veg.size(), (u32)std::count(carries.begin(), carries.end(), (u8)1),
      trunk_protos.size(), trunk_instances, trunk_instances_lod, (int)(kTrunkMinFrac * 100),
      kTrunkMinInstances, names.empty() ? "-" : names);
  trunk_census_note(lev.level_name, veg, trunk_instances, trunk_verts, joint_pairs,
                    proto_total, proto_carrying);
}

void finalize_contact_geometry(tfrag3::Level& lev) {
  const auto start = std::chrono::steady_clock::now();
  using SI = tfrag3::TieTree::SwayInstance;
  struct Vertex {
    std::array<float, 3> xyz;
    SI* si;
    int geo;  // -1: SHRUB; >= 0: actual TIE geometry
  };
  // Positions and instance identities live only during this loader pass.
  std::vector<Vertex> vertices;
  std::map<SI*, float> final_ymax;
  std::vector<VegInst> veg;
  gather_contact_instances(lev, veg);
  u64 mapping_errors = 0, nonfinite = 0, trunks = 0, foliage = 0;
  u64 unclassified_contact_vertices = 0;
  const auto note = [&](const auto& v, SI* si, int geo) {
    if (!std::isfinite(v.x) || !std::isfinite(v.y) || !std::isfinite(v.z)) {
      ++nonfinite;
      return;
    }
    if (!si) return;
    // Numerical equality of finite floats is exact; canonicalize signed zero explicitly.
    vertices.push_back({{v.x == 0.f ? 0.f : v.x, v.y == 0.f ? 0.f : v.y,
                         v.z == 0.f ? 0.f : v.z}, si, geo});
    auto inserted = final_ymax.emplace(si, v.y);
    if (!inserted.second) inserted.first->second = std::max(inserted.first->second, v.y);
    if (si->load_bearing) ++trunks;
    else ++foliage;
  };
  for (size_t geo = 0; geo < lev.tie_trees.size(); ++geo) {
    for (auto& tree : lev.tie_trees[geo]) {
      const size_t nv = tree.unpacked.vertices.size();
      std::vector<u8> flags(nv, 0);
      bool mapping_ok = true;
      // Same vegetation-only tiling as the contact upload (mixed vertices are excluded).
      for (const auto& draw : tree.static_draws) {
        if (!draw.plain_indices.empty()) mapping_ok = false;
        size_t run_i = 0;
        for (const auto& vg : draw.vis_groups) {
          const bool plant = vg.tie_proto_idx < tree.proto_names.size() &&
              shrub_contact_prototype(tree.proto_names[vg.tie_proto_idx]);
          u32 remaining = vg.num_inds;
          while (remaining && run_i < draw.runs.size()) {
            const auto& run = draw.runs[run_i];
            const u32 count = (u32)run.length + 1;
            if (count > remaining) { mapping_ok = false; break; }
            for (size_t v = run.vertex0; v < (size_t)run.vertex0 + run.length; ++v) {
              if (v < nv) flags[v] |= plant ? 1 : 2;
              else mapping_ok = false;
            }
            ++run_i;
            remaining -= count;
          }
          if (remaining) mapping_ok = false;
        }
        if (run_i != draw.runs.size()) mapping_ok = false;
      }
      std::unordered_map<u32, SI*> instances;
      for (auto& si : tree.sway_instances) {
        if (!instances.emplace(si.matrix_idx, &si).second) mapping_ok = false;
        if (geo && si.valid && si.proto_idx < tree.proto_names.size() &&
            shrub_contact_prototype(tree.proto_names[si.proto_idx])) {
          veg.push_back({&si, &tree.proto_names[si.proto_idx]});
        }
      }
      size_t total = 0;
      for (const auto& group : tree.packed_vertices.matrix_groups) {
        if (group.end_vert < group.start_vert ||
            group.end_vert > tree.packed_vertices.vertices.size()) { mapping_ok = false; break; }
        const size_t count = group.end_vert - group.start_vert;
        if (total > nv || count > nv - total) { mapping_ok = false; break; }
        total += count;
      }
      if (total != nv) mapping_ok = false;
      if (!mapping_ok) { ++mapping_errors; continue; }
      size_t offset = 0;
      for (const auto& group : tree.packed_vertices.matrix_groups) {
        const size_t count = group.end_vert - group.start_vert;
        SI* si = nullptr;
        if (group.matrix_idx >= 0) {
          const auto it = instances.find((u32)group.matrix_idx);
          // Nonvegetation groups need not have a sway instance.
          const bool plant = std::find(flags.begin() + offset, flags.begin() + offset + count,
                                       (u8)1) != flags.begin() + offset + count;
          if (plant && (it == instances.end() || !it->second->valid)) ++mapping_errors;
          if (it != instances.end() && it->second->valid &&
              it->second->proto_idx < tree.proto_names.size() &&
              shrub_contact_prototype(tree.proto_names[it->second->proto_idx])) si = it->second;
        }
        for (size_t v = offset; v < offset + count; ++v) {
          // matrix_idx=-1 is prototype space, not a world-space contact vertex.
          if (group.matrix_idx >= 0) {
            if (flags[v] == 1 && !si) ++unclassified_contact_vertices;
            note(tree.unpacked.vertices[v], flags[v] == 1 ? si : nullptr, (int)geo);
          }
        }
        offset += count;
      }
    }
  }
  for (auto& tree : lev.shrub_trees) {
    const size_t nv = tree.unpacked.vertices.size();
    size_t total = 0;
    bool mapping_ok = true;
    for (const auto& group : tree.packed_vertices.instance_groups) {
      if (group.end_vert < group.start_vert ||
          group.end_vert > tree.packed_vertices.vertices.size()) { mapping_ok = false; break; }
      const size_t count = group.end_vert - group.start_vert;
      if (total > nv || count > nv - total) { mapping_ok = false; break; }
      total += count;
    }
    if (total != nv) mapping_ok = false;
    if (!mapping_ok) { ++mapping_errors; continue; }
    size_t offset = 0;
    for (const auto& group : tree.packed_vertices.instance_groups) {
      const size_t count = group.end_vert - group.start_vert;
      SI* si = nullptr;
      if (group.matrix_idx < 0 || (size_t)group.matrix_idx >= tree.sway_instances.size() ||
          (size_t)group.matrix_idx >= tree.wind_proto_of_inst.size()) {
        ++mapping_errors;
      } else {
        const auto pi = tree.wind_proto_of_inst[group.matrix_idx];
        if (pi >= tree.proto_names.size()) ++mapping_errors;
        else if (shrub_contact_prototype(tree.proto_names[pi])) {
          si = &tree.sway_instances[group.matrix_idx];
          if (!si->valid) { ++mapping_errors; si = nullptr; }
        }
      }
      for (size_t v = offset; v < offset + count; ++v) note(tree.unpacked.vertices[v], si, -1);
      offset += count;
    }
  }

  // The SAME predicate on unchanged pre-weld bounds preserves existing carrier identities.
  // Only contact_pin_y changes; base_y, ymin/ymax, classification and wind weights are untouched.
  for (const auto& carrier : veg) {
    if (!carrier.si->load_bearing) continue;
    const auto ymax = final_ymax.find(carrier.si);
    if (ymax == final_ymax.end()) continue;
    for (const auto& target : veg) {
      if (supports(carrier, target)) {
        target.si->contact_pin_y = std::max(target.si->contact_pin_y, ymax->second);
      }
    }
  }
  std::map<std::array<float, 3>, std::vector<const Vertex*>> trunk_at;
  for (const auto& v : vertices) {
    if (v.si->load_bearing) trunk_at[v.xyz].push_back(&v);
  }
  // Each pair contains two real CPU vertex entries. Duplicated topology is counted, not
  // deduplicated into physical joints. Different TIE LOD alternatives cannot form a pair.
  std::map<std::pair<int, int>, u64> pairs_by_geo;
  u64 pairs = 0, canonical_pairs = 0;
  for (const auto& leaf : vertices) {
    if (leaf.si->load_bearing) continue;
    const auto found = trunk_at.find(leaf.xyz);
    if (found == trunk_at.end()) continue;
    for (const auto* trunk : found->second) {
      if (trunk->geo >= 0 && leaf.geo >= 0 && trunk->geo != leaf.geo) continue;
      ++pairs;
      ++pairs_by_geo[{trunk->geo, leaf.geo}];
      if (trunk->geo <= 0 && leaf.geo <= 0) ++canonical_pairs;
      leaf.si->carried = true;
      leaf.si->contact_pin_y = std::max(leaf.si->contact_pin_y, final_ymax.at(trunk->si));
    }
  }
  u64 no_mobile_zone = 0, nonpositive_contact_span = 0;
  for (const auto& entry : final_ymax) {
    if (!entry.first->load_bearing && entry.first->carried) {
      if (entry.second <= entry.first->contact_pin_y) ++no_mobile_zone;
      // Uploads intentionally retain the wind-era ymax: distinguish their contact span from
      // the final CPU geometry's mobile zone instead of conflating the two diagnostics.
      if (entry.first->ymax <= entry.first->contact_pin_y) ++nonpositive_contact_span;
    }
  }
  const double ms = std::chrono::duration<double, std::milli>(
      std::chrono::steady_clock::now() - start).count();
  // Per-level replacement avoids accumulating reloads. These are CPU geometry facts only.
  std::string level_key;
  for (unsigned char c : lev.level_name) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
      level_key += (char)c;
    } else {
      level_key += fmt::format("_{:02x}", c);
    }
  }
  const std::string prefix = "shrub_contact_cpu_" + level_key + "_";
  autoport_proof::publish((prefix + "exact_vertex_pairs_all_lods").c_str(), pairs);
  autoport_proof::publish((prefix + "exact_vertex_pairs_geo0").c_str(), canonical_pairs);
  autoport_proof::publish((prefix + "final_trunk_vertices_all_lods").c_str(), trunks);
  autoport_proof::publish((prefix + "final_foliage_vertices_all_lods").c_str(), foliage);
  autoport_proof::publish((prefix + "unclassified_contact_vertices").c_str(), unclassified_contact_vertices);
  autoport_proof::publish((prefix + "mapping_errors").c_str(), mapping_errors);
  autoport_proof::publish((prefix + "nonfinite_positions").c_str(), nonfinite);
  autoport_proof::publish((prefix + "foliage_without_mobile_zone").c_str(), no_mobile_zone);
  autoport_proof::publish((prefix + "foliage_nonpositive_contact_span").c_str(), nonpositive_contact_span);
  for (int trunk_geo = -1; trunk_geo < (int)lev.tie_trees.size(); ++trunk_geo) {
    for (int leaf_geo = -1; leaf_geo < (int)lev.tie_trees.size(); ++leaf_geo) {
      if (trunk_geo >= 0 && leaf_geo >= 0 && trunk_geo != leaf_geo) continue;
      const u64 n = pairs_by_geo[{trunk_geo, leaf_geo}];
      const auto key = fmt::format("{}exact_pairs_trunk_{}_leaf_{}", prefix,
                                  trunk_geo < 0 ? "shrub" : "geo" + std::to_string(trunk_geo),
                                  leaf_geo < 0 ? "shrub" : "geo" + std::to_string(leaf_geo));
      autoport_proof::publish(key.c_str(), n);
      if (n) lg::info("[shrub-contact-cpu-geometry] lev={} trunk_geo={} leaf_geo={} exact_vertex_pairs={} "
                      "(-1=shrub; LOD alternatives, not unique physical joints)",
                      lev.level_name, trunk_geo, leaf_geo, n);
    }
  }
  lg::info("[shrub-contact-cpu-geometry] lev={} final_trunk_vertices_all_lods={} final_foliage_vertices_all_lods={} "
           "exact_vertex_pairs_all_lods={} exact_vertex_pairs_geo0={} mapping_errors={} "
           "unclassified_contact_vertices={} "
           "nonfinite_positions={} foliage_without_mobile_zone={} "
           "foliage_nonpositive_contact_span={} ms={:.3f}",
           lev.level_name, trunks, foliage, pairs, canonical_pairs, mapping_errors,
           unclassified_contact_vertices, nonfinite,
           no_mobile_zone, nonpositive_contact_span, ms);
}

}  // namespace foliage_wind
