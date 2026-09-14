#include "AmbientOcclusion.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/origin_ablate.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/PrePass.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/system/autoport_proof.h"

#include <string>
#include <type_traits>
#include <utility>
#include <vector>

// ============================================================================
// Grecharged-ambient-occlusion
// ============================================================================
// Three interchangeable estimators keyed off recharged_ao_mode; per-quality resolution
// scale off recharged_ao_quality.
//
// lighting-ao-indirect (SPEC §4.7) : la source de profondeur est la texture de la PREPASSE
// (PrePass.cpp), jamais le FBO de rendu ; la sortie est une texture R8 pleine resolution
// echantillonnee par shade.glsl. Rien n'est compose sur l'image ici. OFF == stock : quand
// effective_mode()==0 rien de tout ceci ne tourne (ni la prepasse).

// ---------------------------------------------------------------------------
// Live-tunable mode/quality resolution.
//
// Re-read the debug override at most every 250 ms WALL TIME (a frame-count throttle
// stalls for tens of seconds at the locked-full-res 4-12 fps the Redmi runs the capture
// protocol at — attempt-4's mode flips landed mid-segment). A value that is
// absent/empty/-1 means "no override, use the game setting". Every override CHANGE is
// logged ("[recharged-ao] override <tag> -> <v>") so capture scripts can wait for the
// flip deterministically instead of sleeping.
// Android reads system properties debug.opengoal.ao.force_mode / .force_quality;
// desktop reads env AO_FORCE_MODE / AO_FORCE_QUALITY.
// ---------------------------------------------------------------------------
namespace {

// Returns the parsed override (>=0) or -1 for "no override".
int read_ao_override(const char* android_prop, const char* env_name) {
  char buf[32] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get(android_prop, buf) > 0 && buf[0]) {
    have = true;
  }
  (void)env_name;
#else
  (void)android_prop;
  const char* e = std::getenv(env_name);
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  if (!have) {
    return -1;
  }
  int v = std::atoi(buf);
  return v;  // -1 (explicitly written) also means "no override"
}

// Time-throttled, change-logged override cache. GL-thread only (all effective_* callers
// are on the render thread).
struct AoOverride {
  const char* tag;
  const char* prop;
  const char* env;
  int cached = -1;
  double last_read_s = -1.0;

  int read() {
    const double now =
        std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
            .count();
    if (last_read_s < 0.0 || now - last_read_s >= 0.25) {
      last_read_s = now;
      const int v = read_ao_override(prop, env);
      if (v != cached) {
        lg::info("[recharged-ao] override {} -> {}", tag, v);
        cached = v;
      }
    }
    return cached;
  }
};

// ─── LES DEUX CHEMINS, COMPTES (refus owner du 2026-09-10) ─────────────────────────────────────
// « J'ai l'impression que l'option sert toujours l'ancien chemin d'avant la refonte. » Deux
// temoins repondent, et aucun des deux n'est un zero par inaction.
//
// 1. LE COMPTE DES CIBLES DE DESSIN. Chaque dessin de la passe declare la cible qu'il vient de
//    lier. L'ANCIEN chemin composait sur l'image de scene : il aurait dessine dans le FBO que la
//    passe trouve en entrant (`prev_fbo`). Le NOUVEAU ecrit dans ses propres textures R8. Les deux
//    compteurs montent au MEME endroit, dans le MEME code : `ao_draws_on_scene` vaut zero parce
//    que la comparaison a lieu et echoue, pas parce qu'aucun site n'existe. `ao_draws_total` est
//    son denominateur, et il n'est jamais nul quand la passe tourne.
//
// 2. LE TEMOIN DE COMPILATION. Un compteur ne peut pas prouver l'absence d'un code supprime : il
//    n'a plus de site ou vivre. `ao_has_composite` demande au COMPILATEUR si la classe porte
//    encore une methode de composite sur la scene, et `ao_legacy_witness_selftest` prouve que le
//    detecteur sait rendre 1 sur un type de controle qui, lui, la porte. Sans ce controle, un zero
//    du detecteur serait indiscernable d'un detecteur casse.
template <class T, class = void>
struct ao_has_composite : std::false_type {};
template <class T>
struct ao_has_composite<T, std::void_t<decltype(std::declval<T&>().composite_on_scene())>>
    : std::true_type {};
struct AoLegacyWitnessControl {
  void composite_on_scene() {}
};

uint64_t s_ao_draws_total = 0;
uint64_t s_ao_draws_on_scene = 0;

// ── LA CAMPAGNE DE COUT (refus owner (f), 2026-09-12) ────────────────────────────────────────
// « Publier le temps par image, AO eteinte puis SSAO puis GTAO, au MEME vantage, sur le MEME
// binaire, camera immobile, avec le nombre d'images de chaque releve. Un releve de moins de
// 300 images ne compte pas, et une cadence lue sur une image ne compte pas du tout. »
// Cinq jambes, dans l'ordre, chacune 60 images de chauffe puis 300 images mesurees. La
// chauffe existe parce que changer de palier recree les cibles d'AO (`ensure_targets`) : la
// premiere image d'une jambe porte cette allocation et n'est pas representative.
//
// Elle demarre TARD, et c'est delibere : les grandeurs de la porte (`ao_direct_leak_px` et
// tout le recensement) sont produites par les images SONDEES de la phase normale. Si la
// campagne tournait en premier et que la course expirait avant sa fin, la preuve sortirait
// SANS sa cle de porte. La campagne prend donc ce qui reste et se laisse tronquer sans rien
// casser : elle publie combien de jambes elle a bouclees (`ao_cost_legs_done`) et le plus
// petit compte d'images des cinq (`ao_cost_min_frames`).
struct CostLeg {
  int mode;
  int quality;
  const char* key;
};
constexpr CostLeg kCostLegs[5] = {
    {0, 0, "off"}, {1, 0, "ssao_q0"}, {1, 2, "ssao_q2"}, {3, 0, "gtao_q0"}, {3, 2, "gtao_q2"}};
constexpr uint64_t kCostStartFrame = 2000;  // apres la phase de recensement. Ce nombre est un
                                            // COMPROMIS mesure : la porte (ao_direct_leak_px)
                                            // vient des images SONDEES, qui se taisent pendant
                                            // la campagne ; la campagne demande 5 x 360 images
                                            // de plus et se laisse tronquer sans rien casser.
                                            // 2000 laisse ~66 sondes aux 12 etats AVANT elle,
                                            // et les sondes reprennent apres sa derniere jambe.
constexpr uint64_t kCostWarm = 60;
constexpr uint64_t kCostMeasured = 300;

// ── L'ETAT DE MESURE, A TROIS DIMENSIONS (verdict owner (e) du 2026-09-12) ───────────────────
// Quel ESTIMATEUR (1 = SSAO, 3 = GTAO ; -1 = aucune contrainte), quel PALIER (0..2), et quel
// regime de BRUIT (0 = livre, 1 = le temoin d'AVANT, l'ancrage MONDE restaure dans le shader
// par `u_ao_legacy_noise`). L'owner a vu le damier « en qualite faible (SSAO) » ET « en qualite
// elevee (GTAO) » : une grandeur qui ne couvre qu'un estimateur ne repond pas a son verdict, et
// une grandeur qui ne retrouve pas le defaut sur le binaire d'AVANT ne prouve pas sa
// disparition. Les trois sont a leur valeur neutre EN JEU : rien ici ne s'arme tout seul.
int s_measure_mode = -1;
int s_measure_quality = -1;
int s_measure_legacy = 0;

// Le reglage impose par la campagne (-1 = aucune contrainte, binaire rendu a son reglage
// normal). Lu par effective_mode()/effective_quality().
int s_timing_mode = -1;
int s_timing_quality = -1;
int s_cost_leg = -1;
uint64_t s_cost_leg_frame = 0;
uint64_t s_cost_us[5] = {0, 0, 0, 0, 0};
uint64_t s_cost_frames[5] = {0, 0, 0, 0, 0};
std::chrono::steady_clock::time_point s_cost_last;
bool s_cost_have_last = false;
uint64_t s_cost_legs_done = 0;

}  // namespace

int AmbientOcclusionPass::effective_mode() {
#if AUTOPORT_ORIGIN_ABLATE
  return 0;  // BINAIRE-TEMOIN : `AO_FORCE_MODE` allume l'AO meme maitre eteint.
#else
  // ORDRE DE PRECEDENCE. (1) La campagne de cout (verdict (f)) PRIME : elle mesure un temps par
  // image et ne doit etre perturbee par rien. (2) Le recensement du motif (verdict (e)) impose
  // l'estimateur de l'image sondee. (3) Le reste, inchange. Les deux premiers valent -1 en jeu.
  if (s_timing_mode >= 0) {
    return s_timing_mode;
  }
  if (s_measure_mode >= 0) {
    return s_measure_mode;
  }
  static AoOverride s_ov{"mode", "debug.opengoal.ao.force_mode", "AO_FORCE_MODE"};
  const int v = s_ov.read();
  // Grecharged-master-toggle: the master composes with the SETTINGS value; the explicit
  // debug force-prop keeps top precedence (it is a bisect tool, not a user path).
  // L'occlusion ambiante est SOUS l'eclairage recharge (SPEC §6.2) : recharged_gating::mode()
  // compose master -> ECLAIRAGE RECHARGE -> mode, donc eteindre l'eclairage rend le mode 0 (AO off).
  return (v >= 0) ? v : recharged_gating::mode(recharged_gating::kAoMode);
#endif
}

int AmbientOcclusionPass::effective_quality() {
  if (s_timing_quality >= 0) {
    return s_timing_quality;
  }
  if (s_measure_quality >= 0) {
    return s_measure_quality;
  }
  static AoOverride s_ov{"quality", "debug.opengoal.ao.force_quality", "AO_FORCE_QUALITY"};
  const int v = s_ov.read();
  return (v >= 0) ? v : Gfx::settings().recharged_ao_quality;
}

int AmbientOcclusionPass::effective_strength() {
  static AoOverride s_ov{"strength", "debug.opengoal.ao.force_strength", "AO_FORCE_STRENGTH"};
  const int v = s_ov.read();
  return (v >= 0) ? v : Gfx::settings().recharged_ao_strength;
}

int AmbientOcclusionPass::effective_debug() {
  static AoOverride s_ov{"debug", "debug.opengoal.ao.debug", "AO_DEBUG"};
  const int v = s_ov.read();
  return (v >= 0) ? v : 0;
}

// ── L'AVANCEMENT DE LA CAMPAGNE DE COUT ──────────────────────────────────────────────────────
// Appelee au DEBUT de chaque image par la prepasse. Hors mesure, ou avant kCostStartFrame,
// elle relache le reglage impose et oublie l'horodatage precedent (un ecart mesure a cheval
// sur l'entree en campagne compterait une image qui n'appartient a aucune jambe).
void AmbientOcclusionPass::measure_frame_begin(uint64_t frame) {
  if (!autoport_proof::feature_is("lighting-ao-indirect") || frame < kCostStartFrame) {
    s_timing_mode = -1;
    s_timing_quality = -1;
    s_cost_have_last = false;
    return;
  }
  if (s_cost_leg < 0) {
    s_cost_leg = 0;
    s_cost_leg_frame = 0;
  }
  if (s_cost_leg >= 5) {
    // Campagne finie : on rend le binaire a son reglage normal.
    s_timing_mode = -1;
    s_timing_quality = -1;
    return;
  }
  s_timing_mode = kCostLegs[s_cost_leg].mode;
  s_timing_quality = kCostLegs[s_cost_leg].quality;

  const auto now = std::chrono::steady_clock::now();
  if (s_cost_have_last && s_cost_leg_frame >= kCostWarm &&
      s_cost_frames[s_cost_leg] < kCostMeasured) {
    s_cost_us[s_cost_leg] +=
        (uint64_t)std::chrono::duration_cast<std::chrono::microseconds>(now - s_cost_last).count();
    s_cost_frames[s_cost_leg]++;
  }
  s_cost_last = now;
  s_cost_have_last = true;

  s_cost_leg_frame++;
  if (s_cost_leg_frame >= kCostWarm + kCostMeasured) {
    s_cost_leg++;
    s_cost_leg_frame = 0;
    s_cost_have_last = false;
    s_cost_legs_done++;
  }
}

bool AmbientOcclusionPass::measure_timing_active() {
  return s_timing_mode >= 0;
}

void AmbientOcclusionPass::publish_cost_census() {
  uint64_t min_frames = s_cost_frames[0];
  for (int i = 0; i < 5; i++) {
    // MICROSECONDES PAR IMAGE, arrondies : pas de milliemes de milliseconde, pas de division
    // par 1000 qui reperdrait ce qu'une multiplication par 1000 venait de gagner.
    const std::string key = std::string("ao_us_") + kCostLegs[i].key;
    autoport_proof::publish(key.c_str(),
                            s_cost_frames[i] ? (s_cost_us[i] / s_cost_frames[i]) : 0ull);
    // LE DENOMINATEUR, a cote de la valeur : « un releve de moins de 300 images ne compte pas ».
    const std::string fkey = std::string("ao_us_frames_") + kCostLegs[i].key;
    autoport_proof::publish(fkey.c_str(), s_cost_frames[i]);
    if (s_cost_frames[i] < min_frames) {
      min_frames = s_cost_frames[i];
    }
  }
  autoport_proof::publish("ao_cost_legs_done", s_cost_legs_done);
  // Rend falsifiable « un releve de moins de 300 images ne compte pas » sans relire 5 cles.
  autoport_proof::publish("ao_cost_min_frames", min_frames);
}

// ---------------------------------------------------------------------------
// Small math helpers (CPU-side inverse camera).
// ---------------------------------------------------------------------------
namespace {

// Full 4x4 inverse in double precision. Column-major storage m[col*4 + row], matching
// the way camera_matrix[col] is laid out (each math::Vector4f is a column). Returns
// false if the matrix is (near-)singular (skip AO that frame).
bool invert4x4(const double m[16], double out[16]) {
  double inv[16];
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
           m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
           m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
           m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
            m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
           m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
           m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
           m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
            m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
           m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
           m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
            m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
            m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
           m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
           m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
            m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
            m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

  double det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  if (std::abs(det) < 1e-12) {
    return false;
  }
  double idet = 1.0 / det;
  for (int i = 0; i < 16; i++) {
    out[i] = inv[i] * idet;
  }
  return true;
}

}  // namespace

AmbientOcclusionPass::~AmbientOcclusionPass() {
  // GL context is generally torn down before renderers; deleting 0 handles is a no-op
  // and the driver/context teardown reclaims anything still live. Kept minimal.
  free_targets();
  if (m_quad_vbo) {
    glDeleteBuffers(1, &m_quad_vbo);
  }
  if (m_quad_vao) {
    glDeleteVertexArrays(1, &m_quad_vao);
  }
}

void AmbientOcclusionPass::init_shaders(ShaderLibrary& shaders) {
  m_shaders = &shaders;
}

void AmbientOcclusionPass::ensure_quad() {
  if (m_quad_ready) {
    return;
  }
  // Same layout as OpenGLRenderer's screen_vao/vbo: 4 vec2 verts, TRIANGLE_STRIP,
  // attribute location 0. post_processing.vert consumes it (position_in).
  struct Vertex {
    float x, y;
  };
  const std::array<Vertex, 4> verts = {Vertex{-1, -1}, Vertex{-1, 1}, Vertex{1, -1},
                                       Vertex{1, 1}};
  glGenVertexArrays(1, &m_quad_vao);
  glGenBuffers(1, &m_quad_vbo);
  glBindVertexArray(m_quad_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_quad_vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 4, verts.data(), GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_TRUE, sizeof(Vertex), nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  m_quad_ready = true;
}

void AmbientOcclusionPass::free_targets() {
  gl_query_census::Armed _ap("ao-free-targets");
  if (m_ao_fbo[0]) {
    // defect #6: drain before deleting targets the previous frame's blur/composite may
    // still reference in Adreno's deferred queue (only runs on a resolution change).
    glFinish();
    glDeleteFramebuffers(2, m_ao_fbo);
    glDeleteTextures(2, m_ao_tex);
    m_ao_fbo[0] = m_ao_fbo[1] = 0;
    m_ao_tex[0] = m_ao_tex[1] = 0;
  }
  if (m_ao_full_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_full_fbo);
    glDeleteTextures(1, &m_ao_full_tex);
    m_ao_full_fbo = 0;
    m_ao_full_tex = 0;
  }
}

void AmbientOcclusionPass::ensure_targets(int ao_w, int ao_h, int full_w, int full_h) {
  if (m_ao_fbo[0] && m_ao_w == ao_w && m_ao_h == ao_h && m_ao_full_fbo &&
      m_ao_full_w == full_w && m_ao_full_h == full_h) {
    return;
  }
  free_targets();
  m_ao_w = ao_w;
  m_ao_h = ao_h;
  m_ao_full_w = full_w;
  m_ao_full_h = full_h;
  glGenFramebuffers(2, m_ao_fbo);
  glGenTextures(2, m_ao_tex);
  for (int i = 0; i < 2; i++) {
    glBindTexture(GL_TEXTURE_2D, m_ao_tex[i]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, ao_w, ao_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
    // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
    hdr::note_input_source_indexed("ao-target", i, GL_R8, ao_w, ao_h);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[i]);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_tex[i], 0);
    GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, bufs);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      lg::error("AO: ao target FBO {} incomplete ({}x{})", i, ao_w, ao_h);
    }
  }
  // full-res target for the upsampling V blur pass (owner tuning #2).
  glGenFramebuffers(1, &m_ao_full_fbo);
  glGenTextures(1, &m_ao_full_tex);
  glBindTexture(GL_TEXTURE_2D, m_ao_full_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, full_w, full_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
  // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
  hdr::note_input_source("ao-full", GL_R8, full_w, full_h, 1);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, m_ao_full_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_full_tex, 0);
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("AO: full-res ao target FBO incomplete ({}x{})", full_w, full_h);
  }
}

// ---------------------------------------------------------------------------
// Uniform upload helper: the shared world<->screen transform uniforms every AO/blur
// pass needs. Uploads camera + inverse + hvdf + fog + cam_pos + sizes.
// ---------------------------------------------------------------------------
namespace {

void upload_common_uniforms(GLuint id,
                            SharedRenderState* rs,
                            const float inv[16],
                            float depth_w,
                            float depth_h,
                            float ao_w,
                            float ao_h) {
  // u_camera: same column layout the grass renderer uploads (camera_matrix[0].data()
  // is 16 contiguous floats, column-major).
  glUniformMatrix4fv(glu::loc(id, "u_camera"), 1, GL_FALSE,
                     rs->camera_matrix[0].data());
  glUniformMatrix4fv(glu::loc(id, "u_inv_camera"), 1, GL_FALSE, inv);
  glUniform4f(glu::loc(id, "u_hvdf_offset"), rs->camera_hvdf_off[0],
              rs->camera_hvdf_off[1], rs->camera_hvdf_off[2], rs->camera_hvdf_off[3]);
  glUniform1f(glu::loc(id, "u_fog"), rs->camera_fog.x());
  glUniform4f(glu::loc(id, "u_cam_pos"), rs->camera_pos[0], rs->camera_pos[1],
              rs->camera_pos[2], rs->camera_pos[3]);
  glUniform2f(glu::loc(id, "u_depth_size"), depth_w, depth_h);
  glUniform2f(glu::loc(id, "u_ao_size"), ao_w, ao_h);
}

}  // namespace

// ---------------------------------------------------------------------------
// LE RECENSEMENT DU MOTIF PERIODIQUE (refus owner du 2026-09-10 (a) : « en qualite faible ca
// fait des damiers bugges/pixelises la ou elle s'applique »).
//
// Le damier est une STRUCTURE DE PERIODE p : l'AP est estimee a 1/p de la resolution puis
// remontee, donc un upsample rate laisse des blocs de p pixels. On le mesure sans supposer
// l'alignement des blocs : pour chaque phase f de 0..p-1 on moyenne |A(x+1,y) - A(x,y)| sur
// les paires dont x % p == f. Un champ SANS structure de periode p rend des moyennes egales,
// donc max(moy)/moy(moy) == 1 ; un champ en BLOCS durs met toute l'energie de bord dans une
// seule phase et le rapport tend vers p. C'est exactement « la force du motif periodique ».
//
// Tout ceci est SOUS MESURE SEULEMENT : s_measure_quality vaut -1 et s_pattern_census_request
// vaut faux par defaut, et personne ici ne les arme. Hors mesure le chemin est un `if` faux.
// ---------------------------------------------------------------------------
namespace {

// L'armement d'UNE image. `s_measure_mode` / `s_measure_quality` / `s_measure_legacy` vivent
// plus haut, avec les autres etats lus par effective_mode()/effective_quality().
bool s_pattern_census_request = false;

// LE PLAFOND DECLARE. Un champ sans structure de periode p rend 1000 ; un champ en blocs durs
// tend vers 1000*p (4000 au palier bas). 1600 laisse la courbure d'un champ lisse reconstruit
// au bilineaire et refuse tout ce qui se voit.
constexpr uint64_t kAoPatternCeilingX1000 = 1600;

// ── LES DOUZE ETATS DU RECENSEMENT (verdict owner (e)) ───────────────────────────────────────
// index = legacy*6 + mode_idx*3 + quality,  mode_idx : 0 = SSAO, 1 = GTAO.
// Les six premiers sont le regime LIVRE, les six suivants le regime TEMOIN (l'ancrage MONDE
// d'avant le 2026-09-13, restaure dans le shader par `u_ao_legacy_noise`). Meme course, meme
// scene, meme binaire : c'est la seule facon de prouver que la grandeur SAIT voir le damier
// avant de dire qu'il a disparu.
// lighting-ao-indirect, 2026-09-13 : la texture de PROFONDEUR de la derniere estimation.
// `ao_flatstep_*` a besoin de la GEOMETRIE pour separer une marche d'AO posee sur une surface
// CONTINUE — le damier — d'une marche posee sur une silhouette, qui est l'AO correcte. Sans
// elle, `ao_blocky_*` confond les deux et rend le MEME chiffre aux deux bras (mesure du
// 2026-09-13 : 323 livre contre 278 temoin, c'est-a-dire rien).
GLuint s_census_depth_tex = 0;
int s_census_depth_w = 0, s_census_depth_h = 0;
std::vector<float> s_depth_buf;

constexpr int kCensusStates = 12;
constexpr const char* kCensusName[kCensusStates] = {
    "ssao_q0", "ssao_q1", "ssao_q2", "gtao_q0", "gtao_q1", "gtao_q2",
    "legacy_ssao_q0", "legacy_ssao_q1", "legacy_ssao_q2",
    "legacy_gtao_q0", "legacy_gtao_q1", "legacy_gtao_q2"};

// Accumulateurs par palier de qualite (0..2). CES CLES-LA (ao_pattern_*, ao_grain_*,
// ao_lag_rough_*) sont celles de l'essai 5 : elles n'accumulent QUE dans le regime LIVRE, pour
// rester comparables a lui et a lui seul.
uint64_t s_pat_sum_milli[3] = {0, 0, 0};
uint64_t s_pat_frames[3] = {0, 0, 0};
uint64_t s_pat_worst_milli[3] = {0, 0, 0};
uint64_t s_pat_px[3] = {0, 0, 0};

// ── CE QUE LE TEST DE PHASE NE PEUT PAS VOIR ─────────────────────────────────────────────────
// Le test ci-dessus juge une structure de periode p EN ECRAN. Le bruit de rotation des trois
// estimateurs, lui, est ancre sur une CELLULE DU MONDE (`floor(P / max(1024, dcam*0.02))`,
// ao_ssao.frag / ao_gtao.frag / ao_hbao.frag) : sa projection a l'ecran n'est periodique dans
// aucune direction, et un test de phase le lit a 1000 comme un champ parfaitement lisse. Publier
// ce 1000 tout seul serait un vert par inaction. Deux grandeurs SANS ECHELLE le completent, sur
// la MEME relecture et pour zero cout de plus :
//   grain      = |A(x+1) - A(x)| moyen, en millienes de la pleine echelle. Ce que l'oeil appelle
//                « ca grouille » : il doit BAISSER quand la qualite monte, pas l'inverse.
//   lag_rough  = 8 * moy|delta_1| / moy|delta_8|. Un champ localement LINEAIRE rend 1000 ; un
//                bruit par pixel rend BEAUCOUP PLUS (delta_1 sature) ; un champ en cellules
//                plus larges que 8 px rend MOINS (delta_1 est plat a l'interieur). Les deux
//                modes de laideur s'ecartent de 1000, et dans des sens opposes.
uint64_t s_grain_sum[3] = {0, 0, 0};
uint64_t s_rough_sum[3] = {0, 0, 0};

// La concentration de la variation (voir `blockiness`), sommee en milliemes, indexee par ETAT
// (0..11) et non par palier : le verdict (e) se juge en comparant livre et temoin.
// `s_blocky_pop` est la population n1 CUMULEE — sans elle, un ecran presque entierement a 255
// rendrait un `blocky` bas et rassurant qu'aucune cle ne contredirait.
uint64_t s_blocky_sum[kCensusStates] = {0};
uint64_t s_hardstep_sum[kCensusStates] = {0};
uint64_t s_blocky_pop[kCensusStates] = {0};
// ── LA MARCHE D'AO SUR UNE SURFACE CONTINUE (refus owner (a)/(e)) ────────────────────────────
// `s_flat_pop` : couples voisins dont la surface est LOCALEMENT PLANE. `s_flat_step` : ceux
// d'entre eux ou l'AO fait une MARCHE. Le plafond est declare sur le rapport des deux.
uint64_t s_flat_pop[kCensusStates] = {0};
uint64_t s_flat_step[kCensusStates] = {0};
uint64_t s_flat_frames[kCensusStates] = {0};
int s_flat_unsupported = 0;
// Diagnostic de `flat_step` : sans lui, un `ao_flatpop = 0` ne dit pas SI la profondeur est
// illisible, SI tout l'ecran est du ciel, ou SI le test de planeite rejette tout. Trois zeros
// differents que le seul `pop` confondait.
uint64_t s_flat_dbg_visited = 0, s_flat_dbg_sky = 0, s_flat_dbg_edge = 0, s_flat_dbg_nbr = 0;
uint64_t s_flat_dbg_zmax_x1e6 = 0;
uint64_t s_census_frames[kCensusStates] = {0};

// LES PLAFONDS DECLARES des deux nouvelles familles.
// Au-dela de 400/1000, la variation est logee sur des frontieres minces : c'est un champ en
// blocs, pas une AO.
constexpr uint64_t kAoBlockyCeilingX1000 = 400;
// 6/1000 de pleine echelle = 1,5 niveau sur 255 entre deux relectures, scene et camera
// immobiles.
constexpr uint64_t kAoTemporalCeilingX1000 = 6;

// ── LA VARIATION TEMPORELLE (refus owner (d) du 2026-09-12) ──────────────────────────────────
// Le tampon d'AO de la DERNIERE relecture de CHAQUE palier, avec ses dimensions : les paliers
// alternent d'une image sondee a l'autre, une comparaison ne melange donc jamais deux paliers.
// INDEXE PAR ETAT, pas par palier : un tampon partage entre les deux regimes ferait comparer
// une image LIVREE a une image TEMOIN et mesurerait l'ecart entre les deux BRAS au lieu du
// temps. C'est le piege central de cet indexage.
std::vector<uint8_t> s_prev_buf[kCensusStates];
int s_prev_w[kCensusStates] = {0};
int s_prev_h[kCensusStates] = {0};
uint64_t s_temporal_sum_milli[kCensusStates] = {0};
uint64_t s_temporal_frames[kCensusStates] = {0};
uint64_t s_temporal_worst_milli[kCensusStates] = {0};

// Le cout de l'INSTRUMENT, pas du rendu : la relecture n'existe que sous mesure, elle ne pese
// sur aucune image livree. Publie pour qu'on puisse le soustraire d'une lecture de cadence.
uint64_t s_pat_readback_us_total = 0;
uint64_t s_pat_readback_calls = 0;
// 1 si la relecture du tampon d'AO a rendu une erreur GL (grandeur non mesurable ici).
uint64_t s_pat_unsupported = 0;

// Tampon de relecture, garde d'une image a l'autre pour ne pas reallouer par image.
std::vector<uint8_t> s_pat_buf;

// La force du motif dans UNE direction : `horizontal` choisit la paire (x,x+1) a phase x % p,
// sinon la paire (y,y+1) a phase y % p. Rend -1.0 si la population comptee est trop maigre
// pour juger (moins de 4096 paires) ; la population lue est rendue dans tous les cas.
double phase_ratio(const uint8_t* A,
                   int w,
                   int h,
                   int p,
                   bool horizontal,
                   uint64_t* population_out) {
  std::vector<uint64_t> sum((size_t)p, 0);
  std::vector<uint64_t> cnt((size_t)p, 0);
  uint64_t total = 0;
  if (horizontal) {
    for (int y = 0; y < h; y++) {
      const uint8_t* row = A + (size_t)y * (size_t)w;
      for (int x = 0; x + 1 < w; x++) {
        const uint8_t a = row[x];
        const uint8_t b = row[x + 1];
        // L'AO est INACTIVE au-dessus de 250 (ciel, surfaces non occultees) : la paire ne dit
        // rien du motif, elle ne doit ni monter ni diluer une moyenne.
        if (std::min(a, b) >= 250) {
          continue;
        }
        const int f = x % p;
        sum[(size_t)f] += (uint64_t)std::abs((int)a - (int)b);
        cnt[(size_t)f]++;
        total++;
      }
    }
  } else {
    for (int y = 0; y + 1 < h; y++) {
      const uint8_t* row = A + (size_t)y * (size_t)w;
      const uint8_t* nxt = row + w;
      const int f = y % p;
      for (int x = 0; x < w; x++) {
        const uint8_t a = row[x];
        const uint8_t b = nxt[x];
        if (std::min(a, b) >= 250) {
          continue;
        }
        sum[(size_t)f] += (uint64_t)std::abs((int)a - (int)b);
        cnt[(size_t)f]++;
        total++;
      }
    }
  }
  *population_out = total;
  if (total < 4096) {
    return -1.0;
  }
  double max_mean = 0.0;
  double acc = 0.0;
  int used = 0;
  for (int f = 0; f < p; f++) {
    if (cnt[(size_t)f] == 0) {
      continue;
    }
    const double m = (double)sum[(size_t)f] / (double)cnt[(size_t)f];
    if (m > max_mean) {
      max_mean = m;
    }
    acc += m;
    used++;
  }
  if (used == 0) {
    return -1.0;
  }
  const double mean_of_means = acc / (double)used;
  return max_mean / std::max(mean_of_means, 1e-6);
}

// La granularite et la rugosite de retard, sur les MEMES paires horizontales que ci-dessus.
// Rend faux si la population est trop maigre pour juger.
bool grain_and_roughness(const uint8_t* A, int w, int h, double* grain_x1000,
                         double* rough_x1000) {
  uint64_t s1 = 0, n1 = 0, s8 = 0, n8 = 0;
  for (int y = 0; y < h; y++) {
    const uint8_t* row = A + (size_t)y * (size_t)w;
    for (int x = 0; x + 1 < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = row[x + 1];
      if (std::min(a, b) >= 250) {
        continue;
      }
      s1 += (uint64_t)std::abs((int)a - (int)b);
      n1++;
    }
    for (int x = 0; x + 8 < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = row[x + 8];
      if (std::min(a, b) >= 250) {
        continue;
      }
      s8 += (uint64_t)std::abs((int)a - (int)b);
      n8++;
    }
  }
  if (n1 < 4096 || n8 < 4096) {
    return false;
  }
  const double m1 = (double)s1 / (double)n1;
  const double m8 = (double)s8 / (double)n8;
  *grain_x1000 = 1000.0 * m1 / 255.0;
  *rough_x1000 = 1000.0 * 8.0 * m1 / std::max(m8, 1e-6);
  return true;
}

// ── CE QUI VOIT UN CHAMP EN BLOCS, SANS PERIODE ET SANS ECHELLE ──────────────────────────────
// `phase_ratio` juge une periode d'ECRAN et `lag_rough` separe le bruit par pixel d'une rampe.
// Aucune des deux ne voit un champ CONSTANT PAR MORCEAUX dont les frontieres ne sont pas
// periodiques : pour des cellules de largeur W, moy|D1| = saut/W et moy|D8| = 8*saut/W, le
// rapport vaut 1000 exactement, comme une rampe. C'est pourtant CE champ-la que l'owner voit —
// le damier.
// La signature d'un champ en blocs est la CONCENTRATION de sa variation : plat partout, et
// toute la variation logee sur des frontieres minces.
//   blocky   = (somme des |D1| qui depassent 4x la moyenne) / (somme de tous les |D1|), en
//              milliemes. Un champ lisse ou un bruit large-bande logent peu de variation
//              au-dela de 4x la moyenne ; un champ en blocs y loge PRESQUE TOUT.
//   hardstep = proportion, en milliemes, des couples voisins dont |D1| depasse 8/255 — une
//              marche de 3 % d'AO entre deux texels voisins, que rien de geometrique ne
//              produit sur une surface continue.
// Les deux sont sans echelle, sans periode, et definies sur la MEME relecture : elles ne
// coutent qu'un second parcours du tampon deja en memoire.
bool blockiness(const uint8_t* p,
                int w,
                int h,
                double* blocky_x1000,
                double* hardstep_x1000,
                uint64_t* pop_out) {
  // Passe 1 : la moyenne des ecarts voisins, horizontaux ET verticaux. Un couple dont les DEUX
  // valeurs valent 255 est du ciel / rien d'occulte : il ne porte aucune information et ne
  // ferait que gonfler le denominateur.
  uint64_t sum1 = 0, n1 = 0;
  for (int y = 0; y < h; y++) {
    const uint8_t* row = p + (size_t)y * (size_t)w;
    for (int x = 0; x + 1 < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = row[x + 1];
      if (a == 255 && b == 255) {
        continue;
      }
      sum1 += (uint64_t)std::abs((int)a - (int)b);
      n1++;
    }
  }
  for (int y = 0; y + 1 < h; y++) {
    const uint8_t* row = p + (size_t)y * (size_t)w;
    const uint8_t* nxt = row + w;
    for (int x = 0; x < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = nxt[x];
      if (a == 255 && b == 255) {
        continue;
      }
      sum1 += (uint64_t)std::abs((int)a - (int)b);
      n1++;
    }
  }
  *pop_out = n1;
  if (n1 < 1000) {
    return false;
  }
  if (sum1 == 0) {
    // Champ parfaitement constant : aucune variation a concentrer. 0/0 n'est pas un blocage.
    *blocky_x1000 = 0.0;
    *hardstep_x1000 = 0.0;
    return true;
  }

  // Passe 2 : la part de la variation logee au-dela de 4x la moyenne, et les marches dures.
  const double thr = 4.0 * (double)sum1 / (double)n1;
  uint64_t sum_hi = 0, n_hard = 0;
  for (int y = 0; y < h; y++) {
    const uint8_t* row = p + (size_t)y * (size_t)w;
    for (int x = 0; x + 1 < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = row[x + 1];
      if (a == 255 && b == 255) {
        continue;
      }
      const uint64_t d = (uint64_t)std::abs((int)a - (int)b);
      if ((double)d >= thr) {
        sum_hi += d;
      }
      if (d > 8) {
        n_hard++;
      }
    }
  }
  for (int y = 0; y + 1 < h; y++) {
    const uint8_t* row = p + (size_t)y * (size_t)w;
    const uint8_t* nxt = row + w;
    for (int x = 0; x < w; x++) {
      const uint8_t a = row[x];
      const uint8_t b = nxt[x];
      if (a == 255 && b == 255) {
        continue;
      }
      const uint64_t d = (uint64_t)std::abs((int)a - (int)b);
      if ((double)d >= thr) {
        sum_hi += d;
      }
      if (d > 8) {
        n_hard++;
      }
    }
  }
  *blocky_x1000 = 1000.0 * (double)sum_hi / (double)sum1;
  *hardstep_x1000 = 1000.0 * (double)n_hard / (double)n1;
  return true;
}


// ── CE QUI VOIT LE DAMIER, ET RIEN D'AUTRE ───────────────────────────────────────────────────
// L'owner (verdict (e)) : « l'item doit publier une mesure prise SUR L'IMAGE RENDUE, au vantage
// de l'owner, et prouver qu'elle voit le damier qu'il voit ». Les deux grandeurs precedentes
// echouent pour la meme raison : `ao_blocky_*` mesure la CONCENTRATION de la variation, et une
// AO PROPRE — plate sur les surfaces, nette sur les silhouettes — est justement concentree.
// Elle a rendu 323 sur le bras livre contre 278 sur le temoin : elle ne separe rien.
//
// Ce qui separe, c'est la GEOMETRIE. Un damier est une marche d'AO posee la ou la surface ne
// fait AUCUNE marche ; une silhouette est une marche d'AO posee la ou la surface en fait une.
// Le test de planeite se lit directement sur la profondeur de fenetre, sans reconstruire le
// monde : sous une projection perspective, la profondeur de fenetre est une fonction AFFINE des
// coordonnees d'ecran sur tout plan. Sa DERIVEE SECONDE est donc nulle sur un plan, quel que
// soit l'angle de vue, et explose sur une arete. C'est exact, pas empirique.
// Sur ces triples-la seulement, on regarde la derivee seconde de l'AO : un gradient de contact
// lisse la laisse petite, une frontiere de cellule la fait sauter. Le seuil est 8/255 (3 %).
void flat_step(const uint8_t* ao,
               const float* depth,
               int w,
               int h,
               uint64_t* pop_out,
               uint64_t* step_out) {
  uint64_t pop = 0, step = 0;
  const double kPlanarRel = 0.02;   // 2 % de la courbure que porteraient les differences 1res
  const double kPlanarAbs = 1e-5;   // et un plancher, pour la surface vue de face (D1 ~ 0)
  const int kAoStep = 8;            // 8/255 = 3 % d'AO entre deux texels : une MARCHE
  auto z = [&](int x, int y) -> double {
    return (double)depth[(size_t)y * (size_t)w + (size_t)x];
  };
  auto a = [&](int x, int y) -> int {
    return (int)ao[(size_t)y * (size_t)w + (size_t)x];
  };
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      s_flat_dbg_visited++;
      const double z0 = z(x, y);
      if (z0 * 1e6 > (double)s_flat_dbg_zmax_x1e6) {
        s_flat_dbg_zmax_x1e6 = (uint64_t)(z0 * 1e6);
      }
      if (z0 <= 1e-9) {
        s_flat_dbg_sky++;
        continue;  // ciel (convention PS2 : 0 = le plus loin)
      }
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        const double zm = z(x - dx, y - dy);
        const double zp = z(x + dx, y + dy);
        if (zm <= 1e-9 || zp <= 1e-9) {
          s_flat_dbg_nbr++;
          continue;
        }
        const double d1 = z0 - zm;
        const double d2 = zp - z0;
        const double curv = std::fabs(d2 - d1);
        if (curv > kPlanarRel * (std::fabs(d1) + std::fabs(d2)) + kPlanarAbs) {
          s_flat_dbg_edge++;
          continue;  // arete, silhouette, pli : une marche d'AO y est LEGITIME
        }
        pop++;
        const int ao_curv = std::abs(a(x + dx, y + dy) - 2 * a(x, y) + a(x - dx, y - dy));
        if (ao_curv > kAoStep) {
          step++;
        }
      }
    }
  }
  *pop_out = pop;
  *step_out = step;
}

// Relit le tampon d'AO pleine resolution et accumule la force du motif pour `quality`.
// `scale` donne la periode candidate : p = max(2, round(1/scale)) — 4 au palier bas, 2 ailleurs.
void pattern_census(int quality, int state, float scale, GLuint ao_full_fbo, int w, int h) {
  if (quality < 0 || quality > 2 || ao_full_fbo == 0 || w <= 1 || h <= 1) {
    return;
  }
  // `state` vaut -1 quand l'estimateur courant n'est pas un des deux que le verdict (e) nomme
  // (HBAO) : les cles par etat ne s'accumulent pas, les cles par palier continuent.
  const bool has_state = (state >= 0 && state < kCensusStates);
  const auto t0 = std::chrono::steady_clock::now();

  // Le binding de LECTURE courant, a rendre tel quel : la passe vient de restaurer son etat.
  GLint prev_read_fbo = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read_fbo);
  GLint prev_pack = 4;
  glGetIntegerv(GL_PACK_ALIGNMENT, &prev_pack);

  const size_t n = (size_t)w * (size_t)h;
  if (s_pat_buf.size() < n) {
    s_pat_buf.resize(n);
  }

  while (glGetError() != GL_NO_ERROR) {
  }  // vidange : on veut l'erreur de NOTRE relecture, pas celle d'un voisin
  glBindFramebuffer(GL_READ_FRAMEBUFFER, ao_full_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RED, GL_UNSIGNED_BYTE, s_pat_buf.data());
  const GLenum err = glGetError();
  glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read_fbo);

  const auto t_end_gl = std::chrono::steady_clock::now();
  if (err != GL_NO_ERROR) {
    // Rien a accumuler : une moyenne sur zero image se lirait comme un succes.
    s_pat_unsupported = 1;
    autoport_proof::publish("ao_pattern_unsupported", s_pat_unsupported);
    s_pat_readback_calls++;
    s_pat_readback_us_total += (uint64_t)std::chrono::duration_cast<std::chrono::microseconds>(
                                   t_end_gl - t0)
                                   .count();
    return;
  }

  const int p = std::max(2, (int)std::lround(1.0 / (double)std::max(scale, 1e-6f)));
  uint64_t pop_h = 0, pop_v = 0;
  const double rh = phase_ratio(s_pat_buf.data(), w, h, p, true, &pop_h);
  const double rv = phase_ratio(s_pat_buf.data(), w, h, p, false, &pop_v);

  double ratio = -1.0;
  if (rh > 0.0) {
    ratio = rh;
  }
  if (rv > ratio) {
    ratio = rv;
  }
  // Le regime TEMOIN ne doit pas polluer les cles de l'essai 5 : elles jugent le LIVRE.
  const bool delivered = (s_measure_legacy == 0);
  if (ratio > 0.0 && delivered) {
    const uint64_t milli = (uint64_t)std::max<int64_t>(0, std::llround(ratio * 1000.0));
    s_pat_sum_milli[quality] += milli;
    s_pat_frames[quality]++;
    if (milli > s_pat_worst_milli[quality]) {
      s_pat_worst_milli[quality] = milli;
    }
    s_pat_px[quality] += ((rh > 0.0) ? pop_h : 0) + ((rv > 0.0) ? pop_v : 0);
    double grain = 0.0, rough = 0.0;
    if (grain_and_roughness(s_pat_buf.data(), w, h, &grain, &rough)) {
      s_grain_sum[quality] += (uint64_t)std::max<int64_t>(0, std::llround(grain));
      s_rough_sum[quality] += (uint64_t)std::max<int64_t>(0, std::llround(rough));
    }
  }

  // ── LA GRANDEUR DE BLOCS, PAR ETAT ───────────────────────────────────────────────────────
  // Hors du `if (ratio > 0.0)` : `phase_ratio` est precisement la grandeur qui ne voit PAS un
  // champ en blocs non periodique, son echec ne doit pas rendre `blockiness` muette.
  if (has_state) {
    double blocky = 0.0, hardstep = 0.0;
    uint64_t pop = 0;
    const bool ok = blockiness(s_pat_buf.data(), w, h, &blocky, &hardstep, &pop);
    s_blocky_pop[state] += pop;
    if (ok) {
      s_blocky_sum[state] += (uint64_t)std::max<int64_t>(0, std::llround(blocky));
      s_hardstep_sum[state] += (uint64_t)std::max<int64_t>(0, std::llround(hardstep));
      s_census_frames[state]++;
    }
  }

  // ── LA MARCHE D'AO SUR SURFACE CONTINUE, PAR ETAT ────────────────────────────────────────
  // Une relecture de la PROFONDEUR de plus, sur l'image sondee seulement. `glGetTexImage`
  // n'existe pas en GLES : sur appareil la grandeur est ABSENTE du binaire, pas a zero.
#ifndef __ANDROID__
  if (has_state) {
    if (s_census_depth_tex == 0 || s_census_depth_w != w || s_census_depth_h != h) {
      // Chaine d'AO et profondeur de tailles differentes : le test de planeite lirait la
      // geometrie d'un AUTRE pixel. On le DIT plutot que de publier un chiffre faux.
      s_flat_unsupported = 1;
    } else {
      if (s_depth_buf.size() < n) {
        s_depth_buf.resize(n);
      }
      const GLuint dfbo = (GLuint)prepass::depth_fbo();
      GLint prev_read2 = 0;
      glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read2);
      while (glGetError() != GL_NO_ERROR) {
      }
      glBindFramebuffer(GL_READ_FRAMEBUFFER, dfbo);
      glPixelStorei(GL_PACK_ALIGNMENT, 1);
      glReadPixels(0, 0, w, h, GL_DEPTH_COMPONENT, GL_FLOAT, s_depth_buf.data());
      const GLenum derr = dfbo == 0 ? GL_INVALID_OPERATION : glGetError();
      glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
      glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read2);
      if (derr != GL_NO_ERROR) {
        s_flat_unsupported = 1;
      } else {
        uint64_t fpop = 0, fstep = 0;
        flat_step(s_pat_buf.data(), s_depth_buf.data(), w, h, &fpop, &fstep);
        s_flat_pop[state] += fpop;
        s_flat_step[state] += fstep;
        s_flat_frames[state]++;
      }
    }
  }
#endif

    // ── LA VARIATION TEMPORELLE (refus owner (d) du 2026-09-12 : « un flou vraiment
    // degueulasse qui bouge dans tous les sens ») ──────────────────────────────────
    // La force du motif est un chiffre PAR IMAGE : elle ne dit rien de ce qui change d'une
    // image a l'autre. On compare la relecture courante a la DERNIERE relecture DU MEME
    // PALIER (les paliers alternent d'une image sondee a l'autre, il n'y a donc jamais deux
    // paliers dans la meme comparaison), et on publie l'ecart moyen en milliemes de pleine
    // echelle. Scene et camera immobiles, un estimateur dont le bruit ne depend ni du temps
    // ni de la camera rend ZERO par construction, pas « peu » : la valeur est donc
    // falsifiable dans les deux sens.
  if (has_state) {
    if (s_prev_w[state] == w && s_prev_h[state] == h && s_prev_buf[state].size() >= n) {
      uint64_t acc = 0;
      for (size_t i = 0; i < n; i++) {
        const int d = (int)s_pat_buf[i] - (int)s_prev_buf[state][i];
        acc += (uint64_t)(d < 0 ? -d : d);
      }
      const uint64_t milli =
          (uint64_t)std::llround(1000.0 * (double)acc / ((double)n * 255.0));
      s_temporal_sum_milli[state] += milli;
      s_temporal_frames[state]++;
      if (milli > s_temporal_worst_milli[state]) {
        s_temporal_worst_milli[state] = milli;
      }
    }
    s_prev_buf[state].assign(s_pat_buf.begin(), s_pat_buf.begin() + (ptrdiff_t)n);
    s_prev_w[state] = w;
    s_prev_h[state] = h;
  }

  s_pat_readback_calls++;
  s_pat_readback_us_total +=
      (uint64_t)std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - t0)
          .count();
}

}  // namespace

void AmbientOcclusionPass::set_measure_state(int mode, int quality, int legacy) {
  // `mode` n'est contraint qu'aux deux estimateurs que le verdict (e) nomme ; toute autre
  // valeur relache la contrainte plutot que de forcer un estimateur que personne n'a demande.
  s_measure_mode = (mode == 1 || mode == 2 || mode == 3) ? mode : -1;
  s_measure_quality = (quality >= 0 && quality <= 2) ? quality : -1;
  s_measure_legacy = (legacy != 0) ? 1 : 0;
}

void AmbientOcclusionPass::request_pattern_census(bool on) {
  s_pattern_census_request = on;
}

void AmbientOcclusionPass::publish_pattern_census() {
  autoport_proof::publish("ao_pattern_ratio_q0_x1000",
                          s_pat_frames[0] ? (s_pat_sum_milli[0] / s_pat_frames[0]) : 0);
  autoport_proof::publish("ao_pattern_ratio_q1_x1000",
                          s_pat_frames[1] ? (s_pat_sum_milli[1] / s_pat_frames[1]) : 0);
  autoport_proof::publish("ao_pattern_ratio_q2_x1000",
                          s_pat_frames[2] ? (s_pat_sum_milli[2] / s_pat_frames[2]) : 0);
  autoport_proof::publish("ao_pattern_worst_q0_x1000", s_pat_worst_milli[0]);
  autoport_proof::publish("ao_pattern_worst_q1_x1000", s_pat_worst_milli[1]);
  autoport_proof::publish("ao_pattern_worst_q2_x1000", s_pat_worst_milli[2]);
  // LE DENOMINATEUR : une moyenne sans son compte d'images ne se juge pas.
  autoport_proof::publish("ao_pattern_frames_q0", s_pat_frames[0]);
  autoport_proof::publish("ao_pattern_frames_q1", s_pat_frames[1]);
  autoport_proof::publish("ao_pattern_frames_q2", s_pat_frames[2]);
  autoport_proof::publish("ao_pattern_px_q0", s_pat_px[0]);
  autoport_proof::publish("ao_pattern_px_q1", s_pat_px[1]);
  autoport_proof::publish("ao_pattern_px_q2", s_pat_px[2]);
  autoport_proof::publish("ao_grain_q0_x1000", s_pat_frames[0] ? (s_grain_sum[0] / s_pat_frames[0]) : 0);
  autoport_proof::publish("ao_grain_q1_x1000", s_pat_frames[1] ? (s_grain_sum[1] / s_pat_frames[1]) : 0);
  autoport_proof::publish("ao_grain_q2_x1000", s_pat_frames[2] ? (s_grain_sum[2] / s_pat_frames[2]) : 0);
  autoport_proof::publish("ao_lag_rough_q0_x1000", s_pat_frames[0] ? (s_rough_sum[0] / s_pat_frames[0]) : 0);
  autoport_proof::publish("ao_lag_rough_q1_x1000", s_pat_frames[1] ? (s_rough_sum[1] / s_pat_frames[1]) : 0);
  autoport_proof::publish("ao_lag_rough_q2_x1000", s_pat_frames[2] ? (s_rough_sum[2] / s_pat_frames[2]) : 0);
  // ── LES DOUZE ETATS (verdict owner (e)) ──────────────────────────────────────────────────
  // Aucune moyenne sans son compte a cote : `ao_census_frames_<nom>` = 0 dit la verite, la
  // moyenne publiee a cote ne vaut rien et ne doit pas etre lue seule.
  uint64_t worst_delivered = 0, worst_legacy = 0;
  uint64_t worst_flat_delivered = 0, worst_flat_legacy = 0;
  for (int i = 0; i < kCensusStates; i++) {
    const std::string n = kCensusName[i];
    const uint64_t blocky = s_census_frames[i] ? (s_blocky_sum[i] / s_census_frames[i]) : 0;
    autoport_proof::publish(("ao_blocky_" + n + "_x1000").c_str(), blocky);
    autoport_proof::publish(("ao_hardstep_" + n + "_x1000").c_str(),
                            s_census_frames[i] ? (s_hardstep_sum[i] / s_census_frames[i]) : 0);
    autoport_proof::publish(("ao_blocky_pop_" + n).c_str(), s_blocky_pop[i]);
    autoport_proof::publish(
        ("ao_temporal_" + n + "_x1000").c_str(),
        s_temporal_frames[i] ? (s_temporal_sum_milli[i] / s_temporal_frames[i]) : 0);
    autoport_proof::publish(("ao_temporal_worst_" + n + "_x1000").c_str(),
                            s_temporal_worst_milli[i]);
    autoport_proof::publish(("ao_temporal_frames_" + n).c_str(), s_temporal_frames[i]);
    autoport_proof::publish(("ao_census_frames_" + n).c_str(), s_census_frames[i]);
    // ── LA GRANDEUR QUI SEPARE : marche d'AO sur surface CONTINUE ─────────────────────────
    const uint64_t flat = s_flat_pop[i] ? (1000ull * s_flat_step[i] / s_flat_pop[i]) : 0;
    autoport_proof::publish(("ao_flatstep_" + n + "_x1000").c_str(), flat);
    autoport_proof::publish(("ao_flatpop_" + n).c_str(), s_flat_pop[i]);
    autoport_proof::publish(("ao_flatframes_" + n).c_str(), s_flat_frames[i]);
    if (s_flat_pop[i]) {
      if (i < 6) {
        worst_flat_delivered = std::max(worst_flat_delivered, flat);
      } else {
        worst_flat_legacy = std::max(worst_flat_legacy, flat);
      }
    }
    if (s_census_frames[i]) {
      if (i < 6) {
        worst_delivered = std::max(worst_delivered, blocky);
      } else {
        worst_legacy = std::max(worst_legacy, blocky);
      }
    }
  }
  // LES DEUX CLES QU'UN HUMAIN LIT EN PREMIER. `legacy` doit DEPASSER le plafond — sinon la
  // grandeur ne sait pas voir le damier que l'owner voit, et le `delivered` bas ne prouve rien.
  autoport_proof::publish("ao_blocky_worst_delivered_x1000", worst_delivered);
  autoport_proof::publish("ao_blocky_worst_legacy_x1000", worst_legacy);
  // ── LES DEUX CLES DU VERDICT (a)/(e) ──────────────────────────────────────────────────
  // `ao_flatstep_*` compte, sur les couples voisins dont la GEOMETRIE est localement plane,
  // ceux ou l'AO fait une marche. C'est le damier et rien d'autre : une silhouette n'est pas
  // plane, un degrade de contact n'est pas une marche. La cle `legacy` doit DEPASSER le
  // plafond — une grandeur qui ne retrouve pas le defaut connu ne peut pas prouver sa
  // disparition (owner, verdict (e)).
  autoport_proof::publish("ao_flatstep_worst_delivered_x1000", worst_flat_delivered);
  autoport_proof::publish("ao_flatstep_worst_legacy_x1000", worst_flat_legacy);
  // Le plafond : une AO qui saute de plus de 3 % entre deux texels voisins d'une surface
  // CONTINUE est un artefact. On en tolere 10 pour mille de la population plane — de quoi
  // laisser passer la quantification 8 bits sur un degre de contact raide, rien de plus.
  autoport_proof::publish("ao_flatstep_ceiling_x1000", 10ull);
  autoport_proof::publish("ao_flatstep_unsupported", (uint64_t)s_flat_unsupported);
  autoport_proof::publish("ao_flat_dbg_visited", s_flat_dbg_visited);
  autoport_proof::publish("ao_flat_dbg_sky", s_flat_dbg_sky);
  autoport_proof::publish("ao_flat_dbg_nbrsky", s_flat_dbg_nbr);
  autoport_proof::publish("ao_flat_dbg_edge", s_flat_dbg_edge);
  autoport_proof::publish("ao_flat_dbg_zmax_x1e6", s_flat_dbg_zmax_x1e6);
  // `ao_blocky_*` est CONSERVEE mais ELLE NE JUGE RIEN : mesure du 2026-09-13, 323 sur le bras
  // livre contre 278 sur le temoin. Elle compte la CONCENTRATION de la variation, et une AO
  // propre — plate sur les surfaces, nette sur les silhouettes — est concentree par nature.
  autoport_proof::publish("ao_blocky_ceiling_x1000", kAoBlockyCeilingX1000);
  autoport_proof::publish("ao_temporal_ceiling_x1000", kAoTemporalCeilingX1000);
  autoport_proof::publish("ao_pattern_ceiling_x1000", kAoPatternCeilingX1000);
  autoport_proof::publish("ao_pattern_unsupported", s_pat_unsupported);
  // Le cout de l'INSTRUMENT (relecture seule), pas du rendu.
  autoport_proof::publish("ao_pattern_readback_us_total", s_pat_readback_us_total);
  autoport_proof::publish("ao_pattern_readback_calls", s_pat_readback_calls);
  // La campagne de cout (verdict (f)) publie avec le reste du recensement.
  publish_cost_census();
}

bool AmbientOcclusionPass::estimate(SharedRenderState* rs,
                                    GLuint depth_tex,
                                    int depth_w,
                                    int depth_h) {
  gl_query_census::Armed _ap("ao-estimate");
  // lighting-ao-indirect : le recensement `ao_flatstep_*` a besoin de CETTE profondeur-la,
  // celle que l'estimateur vient de lire. On la range ici et nulle part ailleurs.
  s_census_depth_tex = depth_tex;
  s_census_depth_w = depth_w;
  s_census_depth_h = depth_h;
  if (!m_shaders || depth_tex == 0 || depth_w <= 0 || depth_h <= 0) {
    return false;
  }
  const int mode = effective_mode();  // 1=SSAO,2=HBAO,3=GTAO
  if (mode == 0) {
    return false;
  }
  int quality = effective_quality();
  if (quality < 0) {
    quality = 0;
  }
  if (quality > 2) {
    quality = 2;
  }
  // Sous mesure : le palier impose par la sonde, pour que les trois paliers soient juges dans
  // la MEME course et sur la MEME scene. Hors mesure, s_measure_quality vaut -1 et ceci est mort.
  if (s_measure_quality >= 0 && s_measure_quality <= 2) {
    quality = s_measure_quality;
  }
  const int dbg = effective_debug();  // 2 = raw estimator debug (depth bands), sinon 0

  // (1) resolution scale by quality
  // lighting-ao-indirect, 2026-09-13, MESURE : le palier HAUT etait le PLUS SALE des trois.
  // `ao_flatstep_*` compte les marches d'AO posees la ou la GEOMETRIE est continue — le damier
  // et rien d'autre. Releve du jour, plafond declare 10 pour mille :
  //     SSAO  19 / 18 / 50      GTAO  11 / 12 / 42      (bas / moyen / HAUT)
  // Le palier haut est 3 a 4 fois pire que les deux autres, dans les DEUX estimateurs. Or
  // « un palier de qualite plus laid qu'AO ETEINTE est un DEFAUT, pas un compromis » (owner,
  // 2026-09-10) — et un palier plus laid que le palier BAS est une absurdite avant d'etre un
  // defaut. La cause n'est pas l'estimateur : c'est que ce palier seul estimait a l'echelle
  // 1:1, donc une valeur par pixel de sortie, quand le flou ne couvre que 4 texels. A 0,25 et
  // 0,5 le flou remonte en resolution et lisse par construction ; a 1,0 il ne reste RIEN pour
  // moyenner la variance de l'estimateur d'un pixel a son voisin.
  // Le palier haut estime donc lui aussi a la demi-resolution, et ce qui le distingue du
  // palier moyen redevient ce que « qualite » doit vouloir dire : le NOMBRE d'echantillons
  // (SSAO 16 -> 24 ; GTAO 6x8 -> 8x10), c'est-a-dire MOINS de variance, pas plus de pixels.
  // Effet de bord mesure et voulu : le cout du palier haut tombe d'un facteur ~4 en pixels.
  const float scale = (quality == 0) ? 0.25f : 0.5f;
  const int src_w = depth_w;  // depth resolution (render-scale sized)
  const int src_h = depth_h;
  const int out_w = (m_hint_w > 0) ? m_hint_w : src_w;  // AO/blur target sizing: keyed to the
  const int out_h = (m_hint_h > 0) ? m_hint_h : src_h;  // WINDOW so render-scale changes never
                                                        // recreate the AO chain (no churn/blink)
  const int ao_w = std::max(1, (int)(out_w * scale));
  const int ao_h = std::max(1, (int)(out_h * scale));

  // ── (l) L'ECHELLE DU PALIER, PUBLIEE ──────────────────────────────────────────────────────
  // « Publier par palier l'echelle effective du tampon d'AO, la taille et le type du filtre de
  // remontee. » Trois faits, pas une opinion : la profondeur que l'estimateur lit, le tampon
  // d'AO qu'il ecrit, et la cible PLEINE RESOLUTION ou la passe verticale du flou remonte. Sur
  // Android `out_w` est la taille de la FENETRE, pas celle de la scene : c'est la seule facon de
  // voir le surdimensionnement sans relire le code. Publie sous mesure seulement — hors mesure
  // le palier ne change pas d'une image a l'autre et une ecriture par image ne dirait rien de
  // plus.
  if (s_measure_quality >= 0 && s_measure_quality <= 2) {
    const std::string q = "_q" + std::to_string(quality);
    autoport_proof::publish(("ao_scale" + q + "_x1000").c_str(),
                            (uint64_t)std::lround(scale * 1000.0));
    autoport_proof::publish(("ao_buf_w" + q).c_str(), (uint64_t)ao_w);
    autoport_proof::publish(("ao_buf_h" + q).c_str(), (uint64_t)ao_h);
    autoport_proof::publish("ao_depth_w", (uint64_t)src_w);
    autoport_proof::publish("ao_depth_h", (uint64_t)src_h);
    autoport_proof::publish("ao_full_w", (uint64_t)out_w);
    autoport_proof::publish("ao_full_h", (uint64_t)out_h);
    // Le filtre de remontee : H a la resolution du tampon, V a la PLEINE resolution, quatre taps
    // a poids egaux ponderes par l'ecart au PLAN TANGENT local (ao_blur.frag). Pas d'espace dans
    // la valeur : proof.txt coupe a l'espace.
    autoport_proof::publish_text("ao_upsample_filter",
                                 "boite-4-taps-bilaterale-prediction-de-plan;V-en-pleine-res");
  }

  // (2a) pure-CPU early-outs FIRST — after this point the function must not return
  // without running the state-restore block at the end.
  double cam[16];
  for (int c = 0; c < 4; c++) {
    for (int r = 0; r < 4; r++) {
      cam[c * 4 + r] = (double)rs->camera_matrix[c][r];
    }
  }
  double invd[16];
  if (!invert4x4(cam, invd)) {
    return false;  // singular camera -> skip AO this frame
  }
  float invf[16];
  for (int i = 0; i < 16; i++) {
    invf[i] = (float)invd[i];
  }

  auto ao_glerr = [&](const char* stage) {
    for (GLenum e; (e = glGetError()) != GL_NO_ERROR;) {
      if (m_err_logged < 24) {
        lg::error("AOERR stage={} gl=0x{:x}", stage, (unsigned)e);
        m_err_logged++;
      }
    }
  };
  ao_glerr("pre");  // drain pre-existing errors so later reads are ours

  // (2) full GL state snapshot (restored before returning). The pass runs mid-frame, avant le
  // premier draw ombre : ANY state it inherits can silently break it (a leftover GL_CULL_FACE
  // culls the CW fullscreen quad; scissor clips it) and ANY state it leaks breaks the
  // following buckets.
  GLint prev_fbo = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  GLint prev_viewport[4];
  glGetIntegerv(GL_VIEWPORT, prev_viewport);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  GLint prev_program = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  GLint prev_vao = 0;
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  GLint prev_array_buffer = 0;
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &prev_array_buffer);
  GLint prev_active_tex = GL_TEXTURE0;
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  // the pass only ever touches texture units 0 and 1 — snapshot their 2D bindings.
  GLint prev_tex0 = 0, prev_tex1 = 0;
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex1);
  // pin unit 0 active so every glBindTexture in the ensure_* helpers below lands on a
  // unit we snapshot+restore (they would otherwise bind on whatever unit was active).
  glActiveTexture(GL_TEXTURE0);
  // neutralize inherited state that would break the fullscreen passes.
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

  // (5) targets + (6) quad
  ensure_targets(ao_w, ao_h, out_w, out_h);
  ensure_quad();

  // Chaque dessin de la passe declare sa cible ici. `prev_fbo` est le FBO de SCENE tel que la
  // passe l'a trouve en entrant : un dessin qui y atterrirait serait, par definition, le composite
  // d'image de l'ancien chemin.
  auto note_target = [&](GLuint target) {
    s_ao_draws_total++;
    if ((GLint)target == prev_fbo) {
      s_ao_draws_on_scene++;
    }
  };

  const float depth_wf = (float)src_w;  // depth texture size (render-scale sized)
  const float depth_hf = (float)src_h;
  const float ao_wf = (float)ao_w;
  const float ao_hf = (float)ao_h;

  // per-quality kernel sizes
  int u_samples = 16, u_dirs = 6, u_steps = 6;
  switch (mode) {
    case 1:  // SSAO
      u_samples = (quality == 0) ? 8 : (quality == 1) ? 16 : 24;
      break;
    case 2:  // HBAO
      u_dirs = (quality == 0) ? 4 : (quality == 1) ? 6 : 8;
      u_steps = (quality == 0) ? 4 : (quality == 1) ? 6 : 8;
      break;
    case 3:  // GTAO
      u_dirs = (quality == 0) ? 3 : (quality == 1) ? 6 : 8;
      u_steps = (quality == 0) ? 6 : (quality == 1) ? 8 : 10;
      break;
    default:
      break;
  }
  // Per-mode look calibration (owner tuning #1/#3, 2026-07-15): every tier must be
  // UNMISTAKABLE vs OFF when toggled mid-game, with distinct characters — SSAO broad/soft
  // (large radius), HBAO mid, GTAO sharp/physical. The defect-#5 open-area cap (<=5%) is
  // held by the estimators returning ~1.0 on flat surfaces (aligned-slice / analytic-
  // tangent / tangent-plane fixes), NOT by keeping strength low. 4096 units = 1 m.
  // lighting-ao-indirect : le `k` de composite (u_ao_strength) a disparu avec le composite ;
  // l'intensite de l'ESTIMATEUR, elle, est conservee telle quelle par mode.
  float u_radius = 1434.0f;
  float u_intensity = 1.0f;
  switch (mode) {
    case 1:  // SSAO
      u_radius = 5120.0f;
      u_intensity = 2.0f;
      break;
    case 2:  // HBAO
      u_radius = 2867.0f;
      // closing round v2: the open-terrain wash is killed by the grazing-modulated occ
      // GATE in ao_hbao.frag (runs BEFORE intensity, so this scales creases only).
      u_intensity = 2.0f;
      break;
    case 3:  // GTAO
      u_radius = 3072.0f;  // 0.75 m — read large-scale concavities, not just tight creases
      u_intensity = 0.65f;
      break;
    default:
      break;
  }

  // AO STRENGTH row (owner closing round 2026-07-16): Weaker/Default/Stronger applies a
  // per-mode multiplier on the ESTIMATOR intensity — on flat open ground occ~0 so
  // intensity*occ stays ~0 and the defect-#5 open-area cap holds structurally even at
  // Stronger. Round G (owner 2026-07-16 22:20): HBAO/GTAO Default == old Weaker (0.6),
  // Stronger == old Default (1.0), Weaker one proportional step below (0.36). SSAO untouched.
  const int ao_strength_sel = effective_strength();
  const float ao_strength_mul =
      (mode == 1) ? ((ao_strength_sel == 0) ? 0.6f : (ao_strength_sel == 2) ? 1.5f : 1.0f)
                  : ((ao_strength_sel == 0) ? 0.36f : (ao_strength_sel == 2) ? 1.0f : 0.6f);
  static int s_ladder_logged_mode = -1, s_ladder_logged_sel = -1;
  if (mode != s_ladder_logged_mode || ao_strength_sel != s_ladder_logged_sel) {
    lg::info("[recharged-ao] ladder mode={} strength={} mul={:.2f}", mode, ao_strength_sel,
             ao_strength_mul);
    s_ladder_logged_mode = mode;
    s_ladder_logged_sel = ao_strength_sel;
  }
  u_intensity *= ao_strength_mul;

  glBindVertexArray(m_quad_vao);
  glDisable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDepthMask(GL_FALSE);

  // (7) Pass 1: AO estimate -> m_ao_tex[0]
  {
    ShaderId sid = (mode == 1) ? ShaderId::AO_SSAO
                   : (mode == 2) ? ShaderId::AO_HBAO
                                 : ShaderId::AO_GTAO;
    auto& shader = (*m_shaders)[sid];
    shader.activate();
    GLuint id = shader.id();
    glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[0]);
    glViewport(0, 0, ao_w, ao_h);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, depth_tex);
    glUniform1i(glu::loc(id, "u_depth"), 0);
    upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
    glUniform1f(glu::loc(id, "u_radius"), u_radius);
    glUniform1f(glu::loc(id, "u_intensity"), u_intensity);
    // round F (owner 2026-07-16 16:50): HBAO/GTAO get an SSAO-model broad soft depth
    // term at SSAO's calibrated intensity (2.0, strength-scaled like the contact term).
    // SSAO itself has no u_broad uniform (location -1, upload ignored).
    glUniform1f(glu::loc(id, "u_broad"),
                (mode == 1) ? 0.0f : 2.0f * ao_strength_mul);
    glUniform1i(glu::loc(id, "u_samples"), u_samples);
    glUniform1i(glu::loc(id, "u_dirs"), u_dirs);
    glUniform1i(glu::loc(id, "u_steps"), u_steps);
    glUniform1i(glu::loc(id, "u_debug"), (dbg == 2) ? 2 : 0);
    // lighting-ao-indirect, verdict (e) : le temoin de bruit. 0 EN JEU, TOUJOURS — seule la
    // mesure l'allume, une image sondee sur deux. A 1, le shader restaure LITTERALEMENT
    // l'ancrage MONDE d'avant le 2026-09-13, celui sur lequel l'owner a vu le damier.
    glUniform1i(glu::loc(id, "u_ao_legacy_noise"), s_measure_legacy);
    // defect #6 residual (gtao-high title kill): the estimator is the one potentially
    // GPU-heavy draw (GTAO High = full-res x 6 slices x 20 samples ~ 1s+ on Adreno 618).
    // A single mega-draw trips the KGSL GPU watchdog under level-load churn. Split into
    // scissored horizontal bands: the driver preempts and the watchdog resets at draw
    // boundaries, so each submission stays bounded.
    const int bands = std::min(8, 1 + (ao_w * ao_h) / 400000);
    if (bands > 1) {
      glEnable(GL_SCISSOR_TEST);
    }
    for (int b = 0; b < bands; b++) {
      const int y0 = (int)((int64_t)ao_h * b / bands);
      const int y1 = (int)((int64_t)ao_h * (b + 1) / bands);
      if (bands > 1) {
        glScissor(0, y0, ao_w, y1 - y0);
      }
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    if (bands > 1) {
      glDisable(GL_SCISSOR_TEST);  // pass invariant: scissor off (restored at the end)
    }
    note_target(m_ao_fbo[0]);
  }
  ao_glerr("estimate");

  // (8) Bilateral blur: pass H at AO res (tex0 raw -> tex1), pass V at FULL res
  // (tex1 -> m_ao_full_tex). The full-res V pass doubles as a depth-aware upsample
  // (owner tuning #2: a sub-full-res AO term read raw is blocky at full render res; the
  // linear-filtered low-res source + full-res depth weights kill the stair-stepping
  // without bleeding across depth edges).
  bool produced = false;
  if (dbg != 2) {
    auto& shader = (*m_shaders)[ShaderId::AO_BLUR];
    for (int p = 0; p < 2; p++) {
      shader.activate();
      GLuint id = shader.id();
      if (p == 0) {
        glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[1]);
        glViewport(0, 0, ao_w, ao_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_ao_tex[0]);
      } else {
        glBindFramebuffer(GL_FRAMEBUFFER, m_ao_full_fbo);
        glViewport(0, 0, out_w, out_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_ao_tex[1]);
      }
      glUniform1i(glu::loc(id, "u_ao"), 0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, depth_tex);
      glUniform1i(glu::loc(id, "u_depth"), 1);
      upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
      if (p == 0) {
        glUniform2f(glu::loc(id, "u_dir"), 1.0f / ao_wf, 0.0f);
      } else {
        glUniform2f(glu::loc(id, "u_dir"), 0.0f, 1.0f / ao_hf);
      }
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      note_target((p == 0) ? m_ao_fbo[1] : m_ao_full_fbo);
    }
    glActiveTexture(GL_TEXTURE0);
    produced = true;
  } else {
    // vue de debug 2 : l'estimation brute, sans flou, recopiee telle quelle en pleine
    // resolution pour que shade() la voie (u_screen_ao_on == 2 l'affiche).
    glBindFramebuffer(GL_READ_FRAMEBUFFER, m_ao_fbo[0]);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_ao_full_fbo);
    glBlitFramebuffer(0, 0, ao_w, ao_h, 0, 0, out_w, out_h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    note_target(m_ao_full_fbo);
    produced = true;
  }
  ao_glerr("blur");

  // (10) restore EVERY piece of state the pass touched (defect #4: any leak here
  // corrupts the following buckets).
  glBindVertexArray(prev_vao);
  glBindBuffer(GL_ARRAY_BUFFER, prev_array_buffer);
  glUseProgram(prev_program);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, prev_tex1);
  glActiveTexture(prev_active_tex);
  if (prev_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }
  if (prev_depth_test) {
    glEnable(GL_DEPTH_TEST);
  } else {
    glDisable(GL_DEPTH_TEST);
  }
  glDepthMask(prev_depth_mask);
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_viewport[0], prev_viewport[1], prev_viewport[2], prev_viewport[3]);

  autoport_proof::publish("ao_draws_total", s_ao_draws_total);
  autoport_proof::publish("ao_draws_on_scene", s_ao_draws_on_scene);
  autoport_proof::publish("ao_legacy_composite_compiled",
                          ao_has_composite<AmbientOcclusionPass>::value ? 1 : 0);
  autoport_proof::publish("ao_legacy_witness_selftest",
                          ao_has_composite<AoLegacyWitnessControl>::value ? 1 : 0);
  // Le recensement du motif, UNE image par armement : la sonde arme, `estimate` consomme.
  if (produced && dbg != 2 && s_pattern_census_request) {
    s_pattern_census_request = false;
    // L'ETAT, EXPLICITE : legacy*6 + mode_idx*3 + quality, mode_idx 0 = SSAO, 1 = GTAO.
    // HBAO (mode 2) n'est nomme par aucun des deux verdicts : il rend -1 et n'alimente que
    // les cles par palier.
    const int mode_idx = (mode == 1) ? 0 : (mode == 3) ? 1 : -1;
    const int census_state =
        (mode_idx < 0) ? -1 : ((s_measure_legacy ? 1 : 0) * 6 + mode_idx * 3 + quality);
    pattern_census(quality, census_state, scale, m_ao_full_fbo, m_ao_full_w, m_ao_full_h);
  }

  return produced;
}
