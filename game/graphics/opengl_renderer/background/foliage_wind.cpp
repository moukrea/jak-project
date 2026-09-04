#include "game/graphics/opengl_renderer/background/foliage_wind.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <unordered_map>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/system/autoport_proof.h"

namespace foliage_wind {
namespace {

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

constexpr float kBendDefaultM = 0.14f;
constexpr float kBendMaxM = 0.50f;
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
std::map<std::pair<std::string, int>, u32> g_unclassified;
u64 g_frames = 0;
u64 g_last_frame_idx = (u64)-1;
float g_dir_x = 0.70710678f;
float g_dir_z = 0.70710678f;
bool g_paused = false;

// Assez souvent pour qu'une course de deux minutes republie une vingtaine de fois, assez rare pour
// que le cout O(N x voisins) ne se voie pas : 300 images, c'est 5 s sur bureau.
constexpr u64 kRepublishFrames = 300;

// « côté à côte » : 12 m. Au-dela l'oeil ne compare plus deux plantes, il regarde un paysage.
constexpr float kPairRadiusU = 12.f * 4096.f;
// « identiques » : meme taille apparente a 1,5 pres.
constexpr float kHeightRatioMax = 1.5f;
// le seuil de divergence : un facteur 2 sur la flexion RELATIVE.
constexpr float kDivergeRatio = 2.0f;
// plancher numerique : sous 0,1 mm de flexion, une plante ne bouge pas. Sert a separer « nul » de
// « minuscule » sans faire dependre le verdict d'un bruit de quantification.
constexpr float kStillM = 1e-4f;

}  // namespace

// ------------------------------------------------------------------------------------- reglages --

bool enabled() {
  // Le forcage est lu UNE fois : c'est un levier de mesure, il ne doit pas pouvoir basculer en
  // cours de course et rendre deux moities de preuve incomparables.
  static const bool s_forced = [] {
    char buf[32] = {0};
    if (!read_knob_raw("debug.opengoal.foliage.force", "FOLIAGE_WIND_FORCE", buf, sizeof(buf))) {
      return false;
    }
    return buf[0] != '0';
  }();
  if (s_forced) {
    return true;
  }
  // Le bras d'ablation du harnais (`proof_run.sh --off` sur CET item) eteint la brise ajoutee ;
  // sans item nomme, ou pour un autre item, `armed_for` rend vrai et rien ne change pour l'owner.
  if (!autoport_proof::armed_for("foliage-wind")) {
    return false;
  }
  return Gfx::recharged_active(Gfx::g_global_settings.recharged_foliage_wind);
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

float clock_seconds(u64 frame_idx, bool paused) {
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
    if (!paused) {
      s_t += dt;
    }
  }
  return s_t;
}

void set_wind_state(float x, float z, bool paused_now) {
  g_paused = paused_now;
  const float len = std::sqrt(x * x + z * z);
  if (!(len > 1e-4f)) {
    return;  // vecteur nul ou NaN : on garde le cap precedent
  }
  g_dir_x = x / len;
  g_dir_z = z / len;
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
  const GLint amp_loc = glGetUniformLocation(program, "u_tie_sway_amp");
  const GLint time_loc = glGetUniformLocation(program, "u_tie_sway_time");
  const GLint dir_loc = glGetUniformLocation(program, "u_tie_sway_dir");
  const GLint flut_loc = glGetUniformLocation(program, "u_tie_sway_flutter");
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
    // Ligne de preuve one-shot PAR PASSE : les deux modes de defaillance SILENCIEUX de ce chemin,
    // parce qu'aucun d'eux ne produit d'erreur GL — un `loc` a -1 (l'uniforme n'existe pas dans le
    // programme lie : chunk absent du blob GLES, bloc optimise), et `attr7_on=0` (l'attribut 7
    // n'est pas active sur le VAO courant, donc le poids arrive a 0 partout et RIEN ne bouge).
    static std::map<std::string, bool> s_logged;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!s_logged[pass]) {
      s_logged[pass] = true;
      GLint attr_on = 0, attr_size = 0;
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &attr_on);
      glGetVertexAttribiv(7, GL_VERTEX_ATTRIB_ARRAY_SIZE, &attr_size);
      lg::info(
          "[foliage-wind] sway ACTIVE pass={} bend={:.4f}m flutter={:.2f} amp_loc={} time_loc={} "
          "dir_loc={} flutter_loc={} attr7_on={} attr7_size={} dir=({:.3f},{:.3f})",
          pass, amp / 4096.f, flutter_fraction(), amp_loc, time_loc, dir_loc, flut_loc, attr_on,
          attr_size, g_dir_x, g_dir_z);
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
  const float g1 = std::sin(t * 0.2971f - travel + pp * 0.31f);
  const float g2 = std::sin(t * 0.5107f - travel * 1.73f + pp * 0.77f + 1.7f);
  const float g3 = std::sin(t * 0.8807f - travel * 2.91f + pp * 0.29f + 4.1f);
  const float swell = 0.50f * g1 + 0.31f * g2 + 0.19f * g3;
  const float gust = 0.16f + 0.84f * std::pow(0.5f + 0.5f * swell, 1.7f);
  const float along = gust * (0.80f + 0.30f * std::sin(t * 1.1731f + pp * 1.19f + travel * 0.6f));
  const float cross = gust * 0.28f * std::sin(t * 0.7639f + pp * 1.61f + 2.3f);
  const float flut_gain = 0.25f + 0.75f * gust;

  const float perp_x = -dir_z;
  const float perp_z = dir_x;
  float ox = (dir_x * along + perp_x * cross) * (bend_u * w);
  float oz = (dir_z * along + perp_z * cross) * (bend_u * w);

  if (flutter_f > 0.f) {
    const float lf1 = std::sin(t * 8.7965f + ph01 * 12.566f + w * 2.9f);
    const float lf2 = std::sin(t * 13.4035f + ph01 * 7.3f + w * 4.1f + 1.3f);
    const float lf_amp = bend_u * w * flutter_f * flut_gain;
    ox += (dir_x * (0.62f * lf1 + 0.38f * lf2) + perp_x * (lf2 * 0.45f)) * lf_amp;
    oz += (dir_z * (0.62f * lf1 + 0.38f * lf2) + perp_z * (lf2 * 0.45f)) * lf_amp;
  }

  *out_x = ox;
  *out_z = oz;
  if (out_flutter_gain) {
    *out_flutter_gain = flut_gain;
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
    g_unclassified.erase({level, 0});
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
  }
}

void note_unclassified(const std::string& level, int tree, u32 count) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_unclassified[{level, tree}] = count;
}

namespace {

// Le calcul de paires, sous verrou. Grille uniforme au pas du rayon de paire : chaque instance ne
// regarde que les 9 cellules qui l'entourent, donc le cout est lineaire en pratique.
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

  u64 still = 0;
  for (const auto& in : pop) {
    if (!(response_m(in) > kStillM)) {
      still++;
    }
  }

  // grille
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
            continue;  // chaque paire une seule fois
          }
          const auto& b = pop[j];
          const float ddx = a.anchor_x - b.anchor_x;
          const float ddz = a.anchor_z - b.anchor_z;
          if (ddx * ddx + ddz * ddz > r2) {
            continue;
          }
          if (!(a.height_m > 0.f) || !(b.height_m > 0.f)) {
            continue;  // hauteur inconnue : la paire n'est pas jugeable, et on ne la juge pas
          }
          const float hr = a.height_m > b.height_m ? a.height_m / b.height_m
                                                   : b.height_m / a.height_m;
          if (hr > kHeightRatioMax) {
            continue;  // pas « identiques » : tailles apparentes differentes
          }
          pairs++;
          // la flexion RELATIVE : un angle, pas une longueur.
          const float ra = response_m(a) / a.height_m;
          const float rb = response_m(b) / b.height_m;
          const float lo = std::min(ra, rb);
          const float hi = std::max(ra, rb);
          float ratio;
          if (!(lo > kStillM / 100.f)) {
            // l'une des deux ne bouge pas : divergence maximale, quel que soit le seuil.
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

  u64 unclassified = 0;
  for (const auto& kv : g_unclassified) {
    unclassified += kv.second;
  }

  // LA REGLE ANTI-FAUX-VERT : aucune paire examinee, ou brise ETEINTE (toute paire est alors
  // immobile des deux cotes et le zero ne mesure rien) => la porte ne peut pas etre verte.
  const u64 gate = (pairs == 0 || !on) ? kNoMeasurement : divergent;
  autoport_proof::publish("wind_divergent_pairs", gate);
  autoport_proof::publish("wind_pairs_examined", pairs);
  autoport_proof::publish("wind_instances_censused", (u64)pop.size());
  autoport_proof::publish("wind_instances_still", still);
  autoport_proof::publish("wind_trees_drawn", trees_drawn);
  autoport_proof::publish("wind_unclassified_protos", unclassified);
  autoport_proof::publish("wind_option_on", on ? 1 : 0);
  autoport_proof::publish("wind_worst_ratio_x100",
                          (u64)std::min(1e9, (double)worst_ratio * 100.0));
  autoport_proof::publish("wind_bend_mm", (u64)(bend_m * 1000.f + 0.5f));
  if (pairs > 0 && on) {
    // Le chemin de code a tire : des paires reelles ont ete jugees sur des instances reellement
    // dessinees, brise allumee. Aucun `note_hit` quand rien n'a ete mesure.
    autoport_proof::note_hit();
  }

  static u64 s_logged = 0;
  if ((s_logged++ % 4) == 0) {
    lg::info(
        "[foliage-wind] pairs divergent={} examined={} instances={} still={} trees_drawn={} "
        "unclassified={} option_on={} worst_ratio={:.3f} bend_m={:.4f}",
        gate, pairs, pop.size(), still, trees_drawn, unclassified, on ? 1 : 0, worst_ratio,
        bend_m);
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
  if ((g_frames % kRepublishFrames) == 0) {
    recompute_and_publish_locked();
  }
}

}  // namespace foliage_wind
