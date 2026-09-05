#include "game/graphics/opengl_renderer/background/foliage_wind.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
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

#include "game/graphics/fixed_tick.h"
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
u64 g_gw_last_ticks = 0;
std::chrono::steady_clock::time_point g_gw_last_wall;
float g_gw_force_prev[64];
u32 g_gw_slot_last_change[64];
double g_gw_sum_dwind = 0.0;   // pas de vent (hors pause)
double g_gw_sum_dticks = 0.0;  // ticks de logique (fixed_tick), memes images
double g_gw_sum_dwall = 0.0;   // secondes murales, memes images
u64 g_gw_frames = 0;
u64 g_native_samples = 0;
u64 g_native_sat = 0;
double g_native_raw_sq = 0.0;
float g_shrub_native_shear_peak = 0.f;

// --- l'echantillon de la loi (verdicts 5 et 7) ---
struct Sample {
  float t;
  float d;
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

bool shrub_native_enabled() {
  static const bool s_on = [] {
    char buf[32] = {0};
    if (!read_knob_raw("debug.opengoal.wind.shrub_native", "OG_WIND_SHRUB_NATIVE", buf,
                       sizeof(buf))) {
      return true;
    }
    return buf[0] != '0';
  }();
  return s_on;
}

float clock_seconds(u64 frame_idx, bool paused_now) {
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
  const u64 ticks = fixed_tick::total_ticks();
  if (!g_gw_seeded) {
    g_gw_seeded = true;
    g_gw_first_time = wind_time;
    g_gw_last_time = wind_time;
    g_gw_last_ticks = ticks;
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
  const u64 dticks = ticks - g_gw_last_ticks;
  if (!paused_now && !g_paused && dwall < 2.0) {
    g_gw_sum_dwind += (double)dwind;
    g_gw_sum_dticks += (double)dticks;
    g_gw_sum_dwall += dwall;
    g_gw_frames++;
  }
  g_gw_last_time = wind_time;
  g_gw_last_ticks = ticks;
  g_gw_last_wall = now;
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
  std::vector<double> d(n, 0.0);
  const double t0 = (double)t_end - (double)n / fs;
  size_t j = 0;
  for (size_t i = 0; i < n; i++) {
    const double t = t0 + (double)i / fs;
    while (j + 1 < s.size() && (double)s[j + 1].t <= t) {
      j++;
    }
    if (j + 1 < s.size() && (double)s[j + 1].t > (double)s[j].t) {
      const double a = (t - (double)s[j].t) / ((double)s[j + 1].t - (double)s[j].t);
      d[i] = (double)s[j].d + std::min(std::max(a, 0.0), 1.0) * ((double)s[j + 1].d - (double)s[j].d);
    } else {
      d[i] = (double)s[j].d;
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
  double rate_dev_pct = 0.0;
  bool rate_ok = false;
  double expected = 0.0;
  const char* rate_ref = "aucune";
  if (g_gw_sum_dticks > 0.0) {
    expected = g_gw_sum_dticks;
    rate_ref = "ticks";
  } else if (g_gw_sum_dwall > 0.0) {
    expected = g_gw_sum_dwall * 60.0;
    rate_ref = "wall";
  }
  if (expected >= 600.0) {
    rate_ok = true;
    rate_dev_pct = std::fabs(g_gw_sum_dwind - expected) / expected * 100.0;
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

  const u64 open = (v1 <= kV1MaxDevPct ? 0 : 1) + (v2 == 0 ? 0 : 1) + (v3 == 0 ? 0 : 1) +
                   (v4 == 0 ? 0 : 1) + (v5 <= kV5MaxPeakPct ? 0 : 1) + (v6_ok ? 0 : 1) +
                   (v7_ok ? 0 : 1);

  char buf[64];
  autoport_proof::publish("wind_owner_defects_open", open);
  autoport_proof::publish("wind_native_stock_dev_pct", v1);
  autoport_proof::publish("wind_ring_dead_slots", ring_ok ? dead_slots : kNoMeasurement);
  std::snprintf(buf, sizeof(buf), "%.3f", rate_ok ? rate_dev_pct : -1.0);
  autoport_proof::publish_text("wind_native_rate_dev_pct", buf);
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
    autoport_proof::note_hit();
  }

  static u64 s_logged = 0;
  if ((s_logged++ % 4) == 0) {
    lg::info(
        "[foliage-wind] verdicts open={} v1_native_dev={} (dead_slots={} rate_dev={:.3f}% ref={} "
        "wind_steps={:.0f} expected={:.0f} sat={:.3f}% samples={}) v2_base_shift_mm={} "
        "v3_still={} v4_divergent={} (pairs={}) v5_peak={}% ({:.3f} Hz, fenetre {:.0f} s) "
        "v6_base_to_crown={:.3f} v7_env_cv={:.3f} instances={} shrubs={} sol={} enfonces={} "
        "natif_raideur={} trees_drawn={} option_on={} bend_m={:.3f} native_shear_peak={:.4f}",
        open, v1, dead_slots, rate_dev_pct, rate_ref, g_gw_sum_dwind, expected, sat_pct,
        g_native_samples, v2, v3, v4, pairs, v5, sp.peak_hz, sp.window_s, base_to_crown,
        sp.env_cv, pop.size(), shrubs, shrubs_ground, shrubs_sunk, shrubs_native, trees_drawn,
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
      g_samples[g_sample_head] = Sample{t, ox * g_dir_x + oz * g_dir_z};
      g_sample_head = (g_sample_head + 1) % kSampleRing;
      if (g_sample_count < kSampleRing) {
        g_sample_count++;
      }
    }
  }
  if ((g_frames % kRepublishFrames) == 0) {
    recompute_and_publish_locked();
  }
}

}  // namespace foliage_wind
