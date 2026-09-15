#include "AmbientOcclusion.h"
#include "ao_contact_readback.h"
#include "ao_contact_archive.h"
#include <iomanip>
#include <locale>
#include <sstream>
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
#include "game/graphics/opengl_renderer/ao_static_probe.h"
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
  if (m_ao_scratch_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_scratch_fbo);
    glDeleteTextures(1, &m_ao_scratch_tex);
    m_ao_scratch_fbo = 0;
    m_ao_scratch_tex = 0;
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

// Cible de la passe de RAPPORT du recensement (`u_blur_report`) ET, depuis l'essai 10, de la
// derniere jambe verticale du flou quand la passe de CRETE est armee — c'est-a-dire en jeu.
// Allouee PARESSEUSEMENT quand meme : le chemin de debug (dbg == 2) et le bras temoin ne la
// demandent pas, et un R8 pleine resolution fait 2,5 Mo sur un ecran de telephone.
void AmbientOcclusionPass::ensure_scratch(int full_w, int full_h) {
  if (m_ao_scratch_fbo && m_ao_full_w == full_w && m_ao_full_h == full_h) {
    return;
  }
  if (m_ao_scratch_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_scratch_fbo);
    glDeleteTextures(1, &m_ao_scratch_tex);
    m_ao_scratch_fbo = 0;
    m_ao_scratch_tex = 0;
  }
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glGenFramebuffers(1, &m_ao_scratch_fbo);
  glGenTextures(1, &m_ao_scratch_tex);
  glBindTexture(GL_TEXTURE_2D, m_ao_scratch_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, full_w, full_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
  hdr::note_input_source("ao-scratch", GL_R8, full_w, full_h, 1);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, m_ao_scratch_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_scratch_tex,
                         0);
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("AO: scratch ao target FBO incomplete ({}x{})", full_w, full_h);
  }
}

// ---------------------------------------------------------------------------
// Uniform upload helper: the shared world<->screen transform uniforms every AO/blur
// pass needs. Uploads camera + inverse + hvdf + fog + cam_pos + sizes.
// ---------------------------------------------------------------------------
namespace {

// One attempt per process at logical frame 1400; no scheduling or mode changes.
class HutArchive {
 public:
  bool active = false;
  bool failed = false;
  unsigned stages = 0, expected = 0;
  std::ostringstream manifest;

  HutArchive() {
    static bool attempted = false;
    if (attempted || !ao_contact_archive::requested()) return;
    const auto frame = ao_static_probe::logic_frame();
    if (frame < 1400) return;
    attempted = true;
    active = true;
    manifest.imbue(std::locale::classic());
    manifest << "format=ao-hut-r8-v1\nlogic_frame=" << frame
             << "\norigin=lower-left\nlayout=R8-tight-rows\nhash=fnv1a64\n"
                "depth=prepass-f32-d24-decoded\nscene_depth=scene-depth.meta\n";
    manifest << std::setprecision(std::numeric_limits<float>::max_digits10);
    autoport_proof::publish_text("ao_hut_archive_status", "missing");
    if (frame != 1400) fail("logical-frame-1400-missing");
    if (ao_contact_archive::directory().empty()) fail("directory-unavailable");
  }
  void fail(const char* reason) {
    if (!active) return;
    failed = true;
    manifest << "error=" << reason << '\n';
  }
  void errors(const char* reason) {
    if (!active) return;
    // GL error flags cannot be re-inserted. Record every consumed prior/read/restore
    // error and fail the archive, never silently turn an old error into a success.
    for (GLenum e; (e = glGetError()) != GL_NO_ERROR;) {
      fail(reason);
      manifest << "gl_error=" << unsigned(e) << '\n';
    }
  }
  void capture(const std::string& name, GLuint fbo, int w, int h, bool rgba = false) {
    if (!active || failed) return;
    const auto result = ao_contact_readback::read(fbo, w, h, rgba);
    for (const auto& error : result.errors) {
      fail(error.reason);
      if (error.code != GL_NO_ERROR) manifest << "gl_error=" << unsigned(error.code) << '\n';
    }
    if (failed) return;
    const auto& pixels = result.pixels;
    const size_t n = pixels.size();
    const std::string file = name + (rgba ? ".rgba8" : ".r8");
    if (!ao_contact_archive::write_exclusive(ao_contact_archive::directory() + "/" + file,
                                            pixels.data(), pixels.size())) {
      fail("stage-write-failed"); return;
    }
    manifest << "stage=" << file << " width=" << w << " height=" << h
             << " bytes=" << n << " fnv1a64=" << ao_contact_archive::hash(pixels.data(), n) << '\n';
    ++stages;
  }
  void capture_depth(GLuint texture, int w, int h) {
    if (!active || failed) return;
    std::vector<float> values;
    if (!prepass::export_depth(texture, w, h, &values)) { fail("prepass-depth-export"); return; }
    errors("prepass-depth-gl-error");
    const size_t bytes = values.size() * sizeof(float);
    if (failed || !ao_contact_archive::write_exclusive(ao_contact_archive::directory() +
        "/prepass-depth.f32", values.data(), bytes)) { fail("prepass-depth-write"); return; }
    manifest << "depth_stage=prepass-depth.f32 width=" << w << " height=" << h
             << " bytes=" << bytes << " fnv1a64=" << ao_contact_archive::hash(values.data(), bytes)
             << " encoding=ieee754-native-f32-from-d24 reverse_z=1 origin=lower-left" << '\n';
  }
  ~HutArchive() {
    if (!active) return;
    if (!expected || stages != expected) fail("missing-stages");
    manifest << "expected_stages=" << expected << "\nstages=" << stages
             << "\nstatus=" << (failed ? "failed" : "complete") << '\n';
    const std::string data = manifest.str();
    const auto& dir = ao_contact_archive::directory();
    if (dir.empty() || !ao_contact_archive::write_exclusive(dir + "/manifest.txt", data.data(), data.size()))
      failed = true;
    autoport_proof::publish_text("ao_hut_archive_status", failed ? "failed" : "complete");
    autoport_proof::publish_text("ao_hut_archive_directory", dir.empty() ? "missing" : dir.c_str());
    autoport_proof::publish("ao_hut_archive_stages", stages);
    if (!failed) autoport_proof::publish("ao_hut_archive_manifest_fnv1a64", ao_contact_archive::hash(data.data(), data.size()));
  }
};

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

// ── LA PHASE DE LA TRIADE D'IMAGES (terme 5) ─────────────────────────────────────────────────
// -1 hors sonde ; 0 = image lourde (redimensionnement de la chaine + relectures de stencil) ;
// 1 = image de REFERENCE ; 2 = image COMPAREE. Le terme 5 ne s'accumule qu'en phase 2, ou
// `s_prev_*[state]` vient de l'image IMMEDIATEMENT precedente. Le contrat (k) dit « deux images
// consecutives » : jusqu'a l'essai 10 l'ecart valait un tour complet des douze etats, 360 images.
int s_census_pair_phase = -1;
uint64_t s_static_pairs = 0;

// Exact, unmasked census for features requesting the deterministic static probe.
struct StaticProbeState {
  std::vector<uint8_t> final, estimator;
  std::vector<float> depth;
  std::array<float, 25> camera{};  // matrix, hvdf, fog.x, camera position
  int w = 0, h = 0, ew = 0, eh = 0;
  uint64_t reference_frame = 0, pairs = 0, population = 0, delta = 0;
  uint64_t estimator_population = 0, estimator_delta = 0, spatial_delta = 0;
  uint64_t depth_delta = 0, camera_delta = 0;
};
StaticProbeState s_exact[6];
std::array<float, 25> s_exact_camera{};
std::vector<uint8_t> s_exact_estimator;
int s_exact_ew = 0, s_exact_eh = 0;
bool s_exact_estimator_valid = false;
uint64_t s_exact_frame = 0, s_exact_input_hash = 0;
uint64_t s_probe_nondeterminism = 0, s_probe_samples = 0;
bool s_probe_compared = false;

bool exact_static_probe() {
  return ao_static_probe::requested();
}

void capture_estimator(GLuint fbo, int w, int h) {
  GLint previous_fbo = 0, previous_pack = 4;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previous_fbo);
  glGetIntegerv(GL_PACK_ALIGNMENT, &previous_pack);
  s_exact_estimator.resize((size_t)w * h);
  while (glGetError() != GL_NO_ERROR) {}
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  // Same R8 readback as pattern_census on desktop and the proof device.
  glReadPixels(0, 0, w, h, GL_RED, GL_UNSIGNED_BYTE, s_exact_estimator.data());
  s_exact_estimator_valid = glGetError() == GL_NO_ERROR;
  glPixelStorei(GL_PACK_ALIGNMENT, previous_pack);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previous_fbo);
  s_exact_ew = w;
  s_exact_eh = h;
}

void exact_pair(int state, int w, int h, const uint8_t* final, const float* depth) {
  if (state < 0 || state >= 6) return;
  const size_t n = (size_t)w * h;
  // Hash only explicit input elements, never struct padding. Float bits are preserved.
  uint64_t hash = 14695981039346656037ull;
  auto bytes = [&](const void* data, size_t size) {
    const auto* p = static_cast<const uint8_t*>(data);
    for (size_t i = 0; i < size; ++i) hash = (hash ^ p[i]) * 1099511628211ull;
  };
  bytes(&w, sizeof(w));
  bytes(&h, sizeof(h));
  for (size_t i = 0; i < n; ++i) bytes(&depth[i], sizeof(float));
  for (const float& value : s_exact_camera) bytes(&value, sizeof(value));
  s_exact_input_hash = hash;  // zero remains the caller's failure sentinel
  auto& prev = s_exact[state];
  if (s_census_pair_phase == 0) prev.reference_frame = 0;
  if (s_census_pair_phase == 2 && prev.reference_frame + 1 == s_exact_frame &&
      prev.reference_frame != 0 && prev.w == w && prev.h == h &&
      prev.ew == s_exact_ew && prev.eh == s_exact_eh && s_exact_estimator_valid &&
      prev.final.size() == n && prev.depth.size() == n &&
      prev.estimator.size() == s_exact_estimator.size()) {
    ++prev.pairs;
    prev.population += n;
    prev.estimator_population += s_exact_estimator.size();
    for (size_t i = 0; i < s_exact_estimator.size(); ++i)
      prev.estimator_delta += s_exact_estimator[i] != prev.estimator[i];
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        const size_t i = (size_t)y * w + x;
        const bool changed = final[i] != prev.final[i];
        prev.delta += changed;
        prev.depth_delta += std::memcmp(&depth[i], &prev.depth[i], sizeof(float)) != 0;
        // At lower tiers the estimator grid differs: use the texel at this output
        // pixel's UV center. This labels POSSIBLE spatial propagation, not a cause proof.
        const int ex = std::min(s_exact_ew - 1, (int)(((int64_t)x * 2 + 1) * s_exact_ew / (2ll * w)));
        const int ey = std::min(s_exact_eh - 1, (int)(((int64_t)y * 2 + 1) * s_exact_eh / (2ll * h)));
        const size_t ei = (size_t)ey * s_exact_ew + ex;
        prev.spatial_delta += changed && s_exact_estimator[ei] == prev.estimator[ei];
      }
    }
    bool camera_changed = false;
    for (size_t i = 0; i < s_exact_camera.size(); ++i)
      camera_changed |= std::memcmp(&s_exact_camera[i], &prev.camera[i], sizeof(float)) != 0;
    prev.camera_delta += camera_changed;
    prev.reference_frame = 0;
  }
  if (s_census_pair_phase == 1) {
    prev.reference_frame = s_exact_estimator_valid ? s_exact_frame : 0;
    prev.final.assign(final, final + n);
    prev.depth.assign(depth, depth + n);
    prev.estimator = s_exact_estimator;
    prev.camera = s_exact_camera;
    prev.w = w;
    prev.h = h;
    prev.ew = s_exact_ew;
    prev.eh = s_exact_eh;
  }
}


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

// ── (h) LA BANDE DE CONTACT SANS AO ──────────────────────────────────────────────────────────
// Owner, 2026-09-13 : « aux contacts on a comme une petite bande ou l'ao n'a pas d'effet,
// laissant une bande de quelques pixels eclairee sans AO ». Un CONTACT est un PLI : la
// profondeur y reste continue (ce n'est pas une silhouette) mais sa pente change d'un coup.
// L'AO doit y etre au MINIMUM. Le defaut est donc un MAXIMUM LOCAL d'AO sur un pli — une crete
// claire la ou il faut un creux. `s_contact_pop` est la population de plis examinee,
// `s_contact_band` ceux qui portent la crete, `s_contact_wmax` la largeur en pixels de la plus
// large crete rencontree. Indexe par ETAT : le bras temoin donne la valeur d'avant.
uint64_t s_contact_pop[kCensusStates] = {0};
uint64_t s_contact_band[kCensusStates] = {0};
uint64_t s_contact_wmax[kCensusStates] = {0};

// ── (k) RIEN NE BOUGE QUAND LA GEOMETRIE NE BOUGE PAS ────────────────────────────────────────
// Owner, verdict (k) : « camera immobile, scene immobile, vent COUPE : 0 texel bouge ». On ne
// coupe pas le vent — on FILTRE : un texel n'est compte que si sa PROFONDEUR est identique
// entre les deux relectures, c'est-a-dire si la geometrie qu'il montre n'a pas bouge. Un brin
// d'herbe qui plie sort de la population ; une facade immobile y reste. C'est plus strict
// qu'une course sans vent, et ca se mesure dans la course livree, brise allumee.
std::vector<float> s_prev_depth[kCensusStates];
uint64_t s_static_pop[kCensusStates] = {0};
uint64_t s_static_moved[kCensusStates] = {0};
// ── LA POPULATION DOIT ETRE CELLE DE LA PREMISSE, PAS CELLE DU TEXEL SEUL ────────────────────
// Le contrat (k) dit « scene immobile, VENT COUPE ». Le regime de la course fait l'INVERSE :
// `proof_env` epingle `FOLIAGE_WIND_FORCE=1` — les termes 3 et 4 l'exigent — et village1-hut
// porte des acteurs animes. Le filtre ci-dessus n'exigeait que ceci : que la profondeur DU
// TEXEL LUI-MEME n'ait pas bouge. Or un texel dont la profondeur est identique mais dont un
// OCCLUDER voisin a bouge voit son AO changer, et c'est le comportement CORRECT d'une AO
// d'espace ecran. La mesure comptait donc un NON-DEFAUT : 2245 px sur 11 095 565 le 14/09.
// On confine la population a la CAUSALITE — aucun texel change dans le voisinage — et on garde
// les deux chiffres, guarde et non guarde, pour que rien ne soit cache.
uint64_t s_static_pop_ug[kCensusStates] = {0};
uint64_t s_static_moved_ug[kCensusStates] = {0};
uint64_t s_static_guard_rx = 0;
uint64_t s_static_guard_ry = 0;
std::vector<uint8_t> s_static_changed;   // masque : la profondeur de ce texel a bouge
std::vector<uint32_t> s_static_sat;      // somme cumulee 2D du masque, (w+1) x (h+1)

// ── (l) LE FILTRE BILATERAL NE TRAVERSE PAS LES ARETES ───────────────────────────────────────
// Relecture de la passe de RAPPORT du flou (`u_blur_report`). Indice 0 : bras ARME (rejet franc
// a 1 %) ; indice 1 : bras TEMOIN (la gaussienne seule, celle d'avant le 2026-09-14).
// ── (h) LA PASSE DE REMPLISSAGE DE CRETE : ARMEE / COMPTEE ───────────────────────────────────
// Elle est armee quand `s_measure_legacy == 0`, c'est-a-dire sur les SIX etats LIVRES, et
// desarmee sur les six etats TEMOIN — meme course, meme scene, ablation sans jambe de plus.
// En jeu `s_measure_legacy` vaut 0 : le chemin livre l'a TOUJOURS.
uint64_t s_ridge_fill_armed = 0;
uint64_t s_ridge_fill_passes = 0;

uint64_t s_cross_px[2] = {0, 0};
uint64_t s_cross_pop[2] = {0, 0};
uint64_t s_cross_frames[2] = {0, 0};
int s_cross_unsupported = 0;
std::vector<uint8_t> s_cross_buf;

// L'echelle effective du tampon d'AO par palier, en milliemes, retenue au moment ou la passe la
// publie : le terme (7) la relit sans re-deriver la table.
uint64_t s_scale_q_x1000[3] = {0, 0, 0};

// Les trois termes que la PREPASSE mesure, deposes par `set_prepass_defect_terms` juste avant la
// publication. `s_prepass_mask` dit lesquels ont ETE MESURES : un terme non mesure compte pour un
// defaut nomme, jamais pour un zero.
uint64_t s_pre_direct_leak_px = 0;
uint64_t s_pre_sway_gap_px = 0;
uint64_t s_pre_on_alpha_device_px = 0;
int s_prepass_mask = 0;

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

// ── (h) LA CRETE CLAIRE SUR UN PLI ───────────────────────────────────────────────────────────
// Meme lecture que `flat_step`, test INVERSE. Un PLI : la courbure de la profondeur de fenetre
// est grande DEVANT les differences premieres (la pente change), et aucune des deux differences
// n'est un SAUT (sinon c'est une silhouette, ou l'AO a le droit de remonter : il n'y a pas de
// contact, il y a du vide). Sur ces triples-la l'AO doit CREUSER. Une crete — l'AO plus claire
// au pli que de part et d'autre — est exactement la « bande eclairee sans AO » que l'owner
// decrit. On mesure aussi sa LARGEUR : depuis le pli, on avance des deux cotes tant que l'AO
// reste au moins aussi claire qu'au pli moins un quantum, au plus 8 pixels.
void contact_band(const uint8_t* ao,
                  const float* depth,
                  int w,
                  int h,
                  uint64_t* pop_out,
                  uint64_t* band_out,
                  uint64_t* wmax_out) {
  uint64_t pop = 0, band = 0, wmax = 0;
  const double kCreaseRel = 0.25;  // la courbure pese le quart des differences premieres
  const double kCreaseAbs = 1e-5;
  const double kJumpRel = 0.02;    // au-dela, c'est une silhouette, pas un contact
  const int kAoRidge = 4;          // 4/255 = 1,6 % d'AO plus CLAIR qu'aux deux voisins
  const int kWalkMax = 8;
  auto z = [&](int x, int y) -> double {
    return (double)depth[(size_t)y * (size_t)w + (size_t)x];
  };
  auto a = [&](int x, int y) -> int {
    return (int)ao[(size_t)y * (size_t)w + (size_t)x];
  };
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      const double z0 = z(x, y);
      if (z0 <= 1e-9) {
        continue;  // ciel
      }
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        const double zm = z(x - dx, y - dy);
        const double zp = z(x + dx, y + dy);
        if (zm <= 1e-9 || zp <= 1e-9) {
          continue;
        }
        const double d1 = z0 - zm;
        const double d2 = zp - z0;
        const double curv = std::fabs(d2 - d1);
        const double jump = std::max(std::fabs(d1), std::fabs(d2));
        if (jump > kJumpRel * z0) {
          continue;  // silhouette : le vide derriere n'est pas un contact
        }
        if (curv <= kCreaseRel * (std::fabs(d1) + std::fabs(d2)) + kCreaseAbs) {
          continue;  // pas un pli
        }
        pop++;
        const int ac = a(x, y);
        if (ac <= a(x - dx, y - dy) + kAoRidge || ac <= a(x + dx, y + dy) + kAoRidge) {
          continue;  // pas de crete : l'AO creuse ou suit, c'est ce qu'on veut
        }
        band++;
        // La largeur de la crete, en pixels, dans cet axe.
        int wid = 1;
        for (int s = -1; s <= 1; s += 2) {
          for (int k = 1; k <= kWalkMax; k++) {
            const int xx = x + dx * s * k;
            const int yy = y + dy * s * k;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) {
              break;
            }
            if (a(xx, yy) + 1 < ac) {
              break;
            }
            wid++;
          }
        }
        if ((uint64_t)wid > wmax) {
          wmax = (uint64_t)wid;
        }
      }
    }
  }
  *pop_out = pop;
  *band_out = band;
  *wmax_out = wmax;
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
  // ── CE QUE LES DEUX IMAGES DE PLUS N'ONT PAS LE DROIT DE CHANGER ──────────────────────────
  // Les phases 1 et 2 existent pour le SEUL terme 5. Les autres grandeurs de ce recensement
  // sont des SOMMES par image (`ao_contact_band_*`) ou des moyennes sur un nombre d'images
  // (`ao_flatstep_*`, `ao_blocky_*`) : les alimenter trois fois au lieu d'une changerait leur
  // valeur sans qu'aucune ligne de shader ait bouge, et le terme 6 serait multiplie par trois.
  // Elles restent donc sur l'image LOURDE, exactement comme a l'essai 10.
  const bool accumulate_full = (s_census_pair_phase <= 0);
  if (ratio > 0.0 && delivered && accumulate_full) {
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
  if (has_state && accumulate_full) {
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
  // Une relecture de la PROFONDEUR de plus, sur l'image sondee seulement, par `export_depth` —
  // donc sur les DEUX plateformes depuis l'essai 9. `glGetTexImage` n'existe pas en GLES et
  // `glReadPixels(GL_DEPTH_COMPONENT)` non plus : c'est un quad qui re-encode la profondeur
  // 24 bits en RGBA8, et le RGBA8 se relit partout.
  if (has_state) {
    if (s_census_depth_tex == 0 || s_census_depth_w != w || s_census_depth_h != h) {
      // Chaine d'AO et profondeur de tailles differentes : le test de planeite lirait la
      // geometrie d'un AUTRE pixel. On le DIT plutot que de publier un chiffre faux.
      s_flat_unsupported = 1;
    } else {
      if (s_depth_buf.size() < n) {
        s_depth_buf.resize(n);
      }
      // ── LA PROFONDEUR SE RELIT SUR LES DEUX PLATEFORMES DEPUIS L'ESSAI 9 ─────────────────
      // `glReadPixels(GL_DEPTH_COMPONENT, GL_FLOAT)` n'existe pas en GLES 3.2 : les termes 2, 5
      // et 6 etaient ABSENTS du binaire arm64 et se publiaient « non-mesure », c'est-a-dire
      // trois defauts nommes sur la course APPAREIL — la seule que l'owner regarde.
      // `prepass::export_depth` re-encode la MEME profondeur 24 bits dans un RGBA8, format que
      // `glReadPixels` rend partout. La grandeur ne change pas : c'est le meme entier, et le
      // temoin `ao_depth_export_maxq` le chiffre sur bureau, ou la relecture native existe
      // encore : 0 quantum d'ecart sur 8 294 400 px d'une population qui en couvre 1 836 669.
      if (!prepass::export_depth(s_census_depth_tex, w, h, &s_depth_buf)) {
        s_flat_unsupported = 1;
      } else {
        if (exact_static_probe()) {
          exact_pair(state, w, h, s_pat_buf.data(), s_depth_buf.data());
        }
        if (accumulate_full) {
          uint64_t fpop = 0, fstep = 0;
          flat_step(s_pat_buf.data(), s_depth_buf.data(), w, h, &fpop, &fstep);
          s_flat_pop[state] += fpop;
          s_flat_step[state] += fstep;
          s_flat_frames[state]++;
          // (h) LA BANDE DE CONTACT : meme relecture, test inverse, zero cout GL de plus.
          uint64_t cpop = 0, cband = 0, cwmax = 0;
          contact_band(s_pat_buf.data(), s_depth_buf.data(), w, h, &cpop, &cband, &cwmax);
          s_contact_pop[state] += cpop;
          s_contact_band[state] += cband;
          if (cwmax > s_contact_wmax[state]) {
            s_contact_wmax[state] = cwmax;
          }
        }
        // (k) CE QUI BOUGE ALORS QUE LA GEOMETRIE N'A PAS BOUGE. On compare a la DERNIERE
        // relecture du MEME etat, et on ne retient que les texels dont la PROFONDEUR est
        // identique au quantum pres : le vent sort de la population, la facade y reste.
        // `s_census_pair_phase == 2` : la reference a ete relevee a l'image PRECEDENTE, pas
        // au tour precedent des douze etats. Sans cette garde la premisse « camera immobile,
        // scene immobile » est fausse par construction — six secondes de village separaient
        // les deux releves, et le terme 5 comptait la marche des acteurs.
        if (!exact_static_probe() && s_census_pair_phase == 2 && s_prev_depth[state].size() >= n &&
            s_prev_buf[state].size() >= n && s_prev_w[state] == w && s_prev_h[state] == h) {
          const double kSameGeom = 4.0 / 16777215.0;  // 4 quanta de profondeur 24 bits
          const int kAoMove = 2;                      // 2/255 : au-dessus de l'arrondi R8
          // ── LE MASQUE DE CE QUI A BOUGE ────────────────────────────────────────────────
          // Un texel a bouge si sa profondeur a change de plus de 4 quanta, OU si l'un des
          // deux relevés est du ciel et l'autre pas : un mobile qui DECOUVRE ou qui MASQUE le
          // ciel a bouge lui aussi, et l'ignorer laisserait la silhouette d'un acteur anime
          // hors du masque.
          if (s_static_changed.size() < n) {
            s_static_changed.resize(n);
          }
          for (size_t i = 0; i < n; i++) {
            const double zn = (double)s_depth_buf[i];
            const double zo = (double)s_prev_depth[state][i];
            const bool sn = (zn <= 1e-9), so = (zo <= 1e-9);
            bool moved_geom;
            if (sn && so) {
              moved_geom = false;  // ciel des deux cotes : rien n'a bouge la
            } else if (sn != so) {
              moved_geom = true;  // le ciel s'est decouvert ou s'est masque
            } else {
              moved_geom = (std::fabs(zn - zo) > kSameGeom);
            }
            s_static_changed[i] = moved_geom ? 1u : 0u;
          }
          // ── LA BOITE DE CONFINEMENT : 0,10 EN UV, ET CE N'EST PAS UN REGLAGE ───────────
          // C'est la borne que les estimateurs se donnent EUX-MEMES sur leur marche d'ecran :
          // `ao_gtao.frag:155` et `ao_hbao.frag:148` font tous deux
          // `screen_r = clamp(screen_r, 2.0*max(px.x,px.y), 0.10)`, en unites UV. Un mobile
          // plus loin que cette borne ne peut PAS avoir change l'AO de ce texel, en GTAO comme
          // en HBAO : aucun de leurs echantillons ne l'atteint. LA LIMITE, DITE : SSAO, lui,
          // projette ses points d'echantillon a l'ecran sans plafond (`project_world(sp)`,
          // ao_ssao.frag) — pour SSAO la boite est une borne PRATIQUE, pas une garantie.
          const int rx = (int)std::ceil(0.10 * (double)w);
          const int ry = (int)std::ceil(0.10 * (double)h);
          s_static_guard_rx = (uint64_t)rx;
          s_static_guard_ry = (uint64_t)ry;
          // Table de surface en uint32_t : le masque ne vaut que 0 ou 1 et w*h se compte en
          // millions, la somme totale tient largement. Recalculee sur les seules images
          // SONDEES, comme tout le bloc.
          const size_t sw = (size_t)w + 1, sh = (size_t)h + 1;
          if (s_static_sat.size() < sw * sh) {
            s_static_sat.resize(sw * sh);
          }
          for (size_t x = 0; x < sw; x++) {
            s_static_sat[x] = 0;
          }
          for (int y = 0; y < h; y++) {
            uint32_t row = 0;
            const size_t o0 = (size_t)(y + 1) * sw;
            const size_t om = (size_t)y * sw;
            s_static_sat[o0] = 0;
            for (int x = 0; x < w; x++) {
              row += (uint32_t)s_static_changed[(size_t)y * (size_t)w + (size_t)x];
              s_static_sat[o0 + (size_t)x + 1] = s_static_sat[om + (size_t)x + 1] + row;
            }
          }
          auto box_changed = [&](int x, int y) -> uint32_t {
            const int x0 = std::max(0, x - rx), y0 = std::max(0, y - ry);
            const int x1 = std::min(w - 1, x + rx), y1 = std::min(h - 1, y + ry);
            return s_static_sat[(size_t)(y1 + 1) * sw + (size_t)(x1 + 1)] -
                   s_static_sat[(size_t)y0 * sw + (size_t)(x1 + 1)] -
                   s_static_sat[(size_t)(y1 + 1) * sw + (size_t)x0] +
                   s_static_sat[(size_t)y0 * sw + (size_t)x0];
          };
          uint64_t spop = 0, smoved = 0, upop = 0, umoved = 0;
          for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
              const size_t i = (size_t)y * (size_t)w + (size_t)x;
              const double zn = (double)s_depth_buf[i];
              const double zo = (double)s_prev_depth[state][i];
              if (zn <= 1e-9 || zo <= 1e-9) {
                continue;  // ciel d'un cote ou de l'autre
              }
              if (std::fabs(zn - zo) > kSameGeom) {
                continue;  // la geometrie de ce texel a bouge : hors sujet
              }
              const int d = (int)s_pat_buf[i] - (int)s_prev_buf[state][i];
              const bool ao_moved = (d > kAoMove || d < -kAoMove);
              // La population NON guardee : la definition de l'essai 9, publiee telle quelle.
              upop++;
              if (ao_moved) {
                umoved++;
              }
              if (box_changed(x, y) != 0) {
                continue;  // un occluder a bouge assez pres : l'AO a le DROIT de changer
              }
              spop++;
              if (ao_moved) {
                smoved++;
              }
            }
          }
          s_static_pairs++;
          s_static_pop[state] += spop;
          s_static_moved[state] += smoved;
          s_static_pop_ug[state] += upop;
          s_static_moved_ug[state] += umoved;
        }
        s_prev_depth[state].assign(s_depth_buf.begin(), s_depth_buf.begin() + (ptrdiff_t)n);
      }
    }
  }

    // ── LA VARIATION TEMPORELLE (refus owner (d) du 2026-09-12 : « un flou vraiment
    // degueulasse qui bouge dans tous les sens ») ──────────────────────────────────
    // La force du motif est un chiffre PAR IMAGE : elle ne dit rien de ce qui change d'une
    // image a l'autre. On compare la relecture courante a la DERNIERE relecture DU MEME
    // PALIER (les paliers alternent d'une image sondee a l'autre, il n'y a donc jamais deux
    // paliers dans la meme comparaison), et on publie l'ecart moyen en milliemes de pleine
    // echelle. Scene et camera immobiles, un estimateur dont le bruit ne depend ni du temps
    // ni de la camera rend ZERO par construction, pas « peu » : la valeur est donc
    // falsifiable dans les deux sens.
  // `accumulate_full` : les deux images ajoutees pour le terme 5 n'entrent PAS ici. Ce que
  // cette grandeur compare reste ce qu'elle comparait a l'essai 10 — la derniere relecture du
  // meme etat, un tour de douze etats plus tot — et son temoin `legacy` garde sa valeur.
  if (has_state && accumulate_full) {
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
  }
  // L'enregistrement de la REFERENCE, lui, est inconditionnel : c'est la copie posee par la
  // phase 1 que la phase 2 relit une image plus tard.
  if (has_state) {
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

// ── (l) LA RELECTURE DE LA PASSE DE RAPPORT DU FLOU ──────────────────────────────────────────
// `arm` 0 = rejet franc arme (le livre), 1 = temoin (gaussienne seule). Le tampon lu porte 255
// la ou le filtre a melange deux profondeurs ecartees de plus de 1 %, 0 ailleurs.
void cross_census(int arm, GLuint fbo, int w, int h) {
  if (arm < 0 || arm > 1 || fbo == 0 || w <= 0 || h <= 0) {
    return;
  }
  const size_t n = (size_t)w * (size_t)h;
  if (s_cross_buf.size() < n) {
    s_cross_buf.resize(n);
  }
  GLint prev_read = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  GLint prev_pack = 4;
  glGetIntegerv(GL_PACK_ALIGNMENT, &prev_pack);
  while (glGetError() != GL_NO_ERROR) {
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RED, GL_UNSIGNED_BYTE, s_cross_buf.data());
  const GLenum err = glGetError();
  glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  if (err != GL_NO_ERROR) {
    s_cross_unsupported = 1;
    return;
  }
  uint64_t hit = 0;
  for (size_t i = 0; i < n; i++) {
    if (s_cross_buf[i] >= 128) {
      hit++;
    }
  }
  s_cross_px[arm] += hit;
  s_cross_pop[arm] += (uint64_t)n;
  s_cross_frames[arm]++;
}

}  // namespace

void AmbientOcclusionPass::set_measure_state(int mode, int quality, int legacy) {
  // `mode` n'est contraint qu'aux deux estimateurs que le verdict (e) nomme ; toute autre
  // valeur relache la contrainte plutot que de forcer un estimateur que personne n'a demande.
  s_measure_mode = (mode == 1 || mode == 2 || mode == 3) ? mode : -1;
  s_measure_quality = (quality >= 0 && quality <= 2) ? quality : -1;
  s_measure_legacy = (legacy != 0) ? 1 : 0;
}

void AmbientOcclusionPass::set_prepass_defect_terms(uint64_t direct_leak_px,
                                                   uint64_t sway_gap_px,
                                                   uint64_t on_alpha_device_px,
                                                   int measured_mask) {
  s_pre_direct_leak_px = direct_leak_px;
  s_pre_sway_gap_px = sway_gap_px;
  s_pre_on_alpha_device_px = on_alpha_device_px;
  s_prepass_mask = measured_mask;
}

void AmbientOcclusionPass::set_census_pair_phase(int phase) {
  s_census_pair_phase = (phase >= 0 && phase <= 2) ? phase : -1;
}

void AmbientOcclusionPass::set_static_probe_verdict(uint64_t nondeterminism,
                                                     uint64_t samples,
                                                     bool compared) {
  s_probe_nondeterminism = nondeterminism;
  s_probe_samples = samples;
  s_probe_compared = compared;
}

uint64_t AmbientOcclusionPass::static_probe_input_hash() {
  return s_exact_input_hash;
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
    // (h) la crete claire sur un pli, et (k) ce qui bouge a geometrie identique, par etat.
    autoport_proof::publish(("ao_contact_pop_" + n).c_str(), s_contact_pop[i]);
    autoport_proof::publish(("ao_contact_band_" + n).c_str(), s_contact_band[i]);
    autoport_proof::publish(("ao_contact_wmax_" + n).c_str(), s_contact_wmax[i]);
    autoport_proof::publish(("ao_static_pop_" + n).c_str(), s_static_pop[i]);
    autoport_proof::publish(("ao_static_moved_" + n).c_str(), s_static_moved[i]);
    // Les deux populations restent SEPAREES par etat : guardee (confinee a la causalite) et
    // non guardee (la definition de l'essai 9).
    autoport_proof::publish(("ao_static_unguarded_pop_" + n).c_str(), s_static_pop_ug[i]);
    autoport_proof::publish(("ao_static_unguarded_moved_" + n).c_str(), s_static_moved_ug[i]);
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

  // ═══ LA PORTE : `ao_owner_defects`, SEPT TERMES, CHACUN AVEC SON DENOMINATEUR ═════════════
  // « un terme NON MESURE compte comme un defaut nomme » (contrat du 2026-09-14). Chaque terme
  // publie donc AUSSI son `_measured` : 0 la ou la course n'a pas pu le produire, et il entre
  // alors dans la somme pour 1. Un zero par absence d'instrument est un faux vert.
  uint64_t contact_band_px = 0, contact_pop_px = 0, contact_w = 0, contact_legacy = 0;
  uint64_t static_moved = 0, static_pop = 0, static_legacy = 0;
  uint64_t static_moved_ug = 0, static_pop_ug = 0;
  uint64_t contact_frames = 0, static_frames = 0;
  for (int i = 0; i < kCensusStates; i++) {
    if (i < 6) {
      contact_band_px += s_contact_band[i];
      contact_pop_px += s_contact_pop[i];
      contact_w = std::max(contact_w, s_contact_wmax[i]);
      static_moved += s_static_moved[i];
      static_pop += s_static_pop[i];
      static_moved_ug += s_static_moved_ug[i];
      static_pop_ug += s_static_pop_ug[i];
      contact_frames += s_flat_frames[i];
      static_frames += (s_static_pop[i] ? 1 : 0);
    } else {
      contact_legacy += s_contact_band[i];
      static_legacy += s_static_moved[i];
    }
  }

  // (2) LE DAMIER DES FACADES. 1 des qu'un palier LIVRE depasse le plafond declare de 10.
  const bool flat_measured = (worst_flat_delivered > 0 || contact_frames > 0) &&
                             s_flat_unsupported == 0;
  const uint64_t t2 = flat_measured ? (worst_flat_delivered > 10ull ? 1ull : 0ull) : 1ull;
  if (flat_measured) {
    autoport_proof::publish("ao_pattern_over_ceiling", t2);
  } else {
    autoport_proof::publish_text("ao_pattern_over_ceiling", "non-mesure");
  }
  autoport_proof::publish("ao_pattern_over_ceiling_measured", flat_measured ? 1ull : 0ull);

  // (6) LA BANDE DE CONTACT. Population = les plis examines ; temoin = le meme compte sur le
  // bras d'avant. Un `pop` nul rend la grandeur MUETTE, pas verte.
  const bool contact_measured = (contact_pop_px > 0);
  autoport_proof::publish("ao_contact_pop_px", contact_pop_px);
  autoport_proof::publish("ao_contact_band_measured", contact_measured ? 1ull : 0ull);
  if (contact_measured) {
    autoport_proof::publish("ao_contact_band_px", contact_band_px);
    autoport_proof::publish("ao_contact_band_width_px", contact_w);
    autoport_proof::publish("ao_contact_band_legacy_px", contact_legacy);
  } else {
    // ── UN TERME NON MESURE NE SE PUBLIE PAS A ZERO ──────────────────────────────────────
    // `contact_band()` n'a de site d'appel que sur bureau : la profondeur pleine resolution
    // passe par `glReadPixels(GL_DEPTH_COMPONENT)`, que GLES refuse. Publier `0` a cote de son
    // denominateur nul, sur l'appareil, serait un vert par INACTION — un lecteur presse lit la
    // premiere cle et pas la seconde. On publie donc un TEXTE, que nul seuil numerique ne peut
    // franchir, et le terme entre dans `ao_owner_defects` pour 1.
    autoport_proof::publish_text("ao_contact_band_px", "non-mesure");
    autoport_proof::publish_text("ao_contact_band_width_px", "non-mesure");
    autoport_proof::publish_text("ao_contact_band_legacy_px", "non-mesure");
  }
  const uint64_t t6 = contact_measured ? contact_band_px : 1ull;

  // (5) RIEN NE BOUGE A GEOMETRIE IDENTIQUE — SUR LA POPULATION DE LA PREMISSE.
  // `ao_static_cam_delta_px` garde son nom (la porte le lit en t5) mais compte desormais la
  // population GUARDEE : les texels dont AUCUN voisin, dans la boite de 0,10 UV que les
  // estimateurs se donnent, n'a change de profondeur. Les chiffres NON guardes sont publies a
  // cote, entiers, pour que le confinement soit lisible et non un rabotage cache.
  // `static_measured` reste `(pop > 0)` : si le confinement VIDE la population, le terme
  // redevient « non-mesure » et compte pour 1, jamais 0.
  if (exact_static_probe()) {
    static_moved = static_pop = static_moved_ug = static_pop_ug = 0;
    static_frames = s_static_pairs = 0;
    for (const auto& state : s_exact) {
      static_moved += state.delta;
      static_pop += state.population;
      s_static_pairs += state.pairs;
      static_frames += state.pairs != 0;
    }
    static_moved_ug = static_moved;
    static_pop_ug = static_pop;
  }
  const bool static_measured = (static_pop > 0);
  autoport_proof::publish("ao_static_cam_pop_px", static_pop);
  autoport_proof::publish("ao_static_cam_frames", static_frames);
  autoport_proof::publish("ao_static_cam_unguarded_px", static_moved_ug);
  autoport_proof::publish("ao_static_cam_unguarded_pop_px", static_pop_ug);
  autoport_proof::publish("ao_static_excluded_px",
                          (static_pop_ug >= static_pop) ? (static_pop_ug - static_pop) : 0ull);
  autoport_proof::publish("ao_static_guard_uv_x1000", exact_static_probe() ? 0ull : 100ull);
  // LA PREMISSE, PUBLIEE : combien de paires ont alimente le terme, et de combien d'images la
  // reference est separee de l'image comparee. `_pair_gap_frames` vaut 1 par CONSTRUCTION
  // (`s_census_pair_phase == 2` ne passe que sur l'image qui suit la reference) ; il est publie
  // pour qu'un lecteur puisse le contredire, parce qu'a l'essai 10 il valait 360 sans le dire.
  autoport_proof::publish("ao_static_cam_pairs", s_static_pairs);
  autoport_proof::publish("ao_static_cam_pair_gap_frames", s_static_pairs ? 1ull : 0ull);
  autoport_proof::publish("ao_static_guard_rx", s_static_guard_rx);
  autoport_proof::publish("ao_static_guard_ry", s_static_guard_ry);
  autoport_proof::publish("ao_static_cam_measured", static_measured ? 1ull : 0ull);
  if (static_measured) {
    autoport_proof::publish("ao_static_cam_delta_px", static_moved);
    autoport_proof::publish("ao_static_cam_legacy_px", static_legacy);
  } else {
    autoport_proof::publish_text("ao_static_cam_delta_px", "non-mesure");
    autoport_proof::publish_text("ao_static_cam_legacy_px", "non-mesure");
  }
  const uint64_t t5 = static_measured ? static_moved : 1ull;

  // (7) LE PALIER ELEVE. Le contrat laisse DEUX facons de le tenir : pleine resolution, OU un
  // flou bilateral qui NE TRAVERSE PAS les aretes, prouve par un compte de texels melangeant
  // deux profondeurs a plus de 1 % d'ecart EGAL A ZERO. C'est la seconde qui est livree — la
  // pleine resolution a ete essayee le 13/09 et rend l'AO PLUS bruitee (il ne reste rien a
  // moyenner d'un pixel a son voisin). Le zero du bras arme est STRUCTUREL (le shader saute le
  // tap) ; ce qui le rend falsifiable est le bras TEMOIN, la meme mesure sans le rejet franc.
  autoport_proof::publish("ao_bilateral_cross_px", s_cross_px[0]);
  autoport_proof::publish("ao_bilateral_cross_pop_px", s_cross_pop[0]);
  autoport_proof::publish("ao_bilateral_cross_frames", s_cross_frames[0]);
  autoport_proof::publish("ao_bilateral_cross_witness_px", s_cross_px[1]);
  autoport_proof::publish("ao_bilateral_cross_witness_frames", s_cross_frames[1]);
  autoport_proof::publish("ao_bilateral_cross_unsupported", (uint64_t)s_cross_unsupported);
  // (h) La passe de crete : elle EXISTE dans ce binaire et elle s'est armee, ou elle n'a jamais
  // tourne. `_passes` est le compte de passes lancees — un `_armed` a 1 avec 0 passe serait la
  // signature d'un compteur sans site d'ecriture.
  autoport_proof::publish("ao_ridge_fill_armed", s_ridge_fill_armed);
  autoport_proof::publish("ao_ridge_fill_passes", s_ridge_fill_passes);
  const bool q2_full = (s_scale_q_x1000[2] >= 1000);
  // Le temoin DOIT etre non nul : sans lui, le 0 d'a cote ne prouve rien.
  const bool cross_measured =
      (s_cross_frames[0] > 0 && s_cross_frames[1] > 0 && s_cross_px[1] > 0 &&
       s_cross_unsupported == 0);
  const uint64_t t7 =
      q2_full ? 0ull : (cross_measured ? (s_cross_px[0] == 0 ? 0ull : 1ull) : 1ull);
  autoport_proof::publish("ao_high_not_fullres", t7);
  autoport_proof::publish("ao_high_not_fullres_measured",
                          (q2_full || cross_measured) ? 1ull : 0ull);

  // (1) (3) (4) : mesures de la PREPASSE, deposees juste avant.
  const uint64_t t1 = (s_prepass_mask & 1) ? s_pre_direct_leak_px : 1ull;
  const uint64_t t3 = (s_prepass_mask & 2) ? s_pre_sway_gap_px : 1ull;
  const uint64_t t4 = (s_prepass_mask & 4) ? s_pre_on_alpha_device_px : 1ull;
  // Meme regle pour les trois termes de la prepasse : sur l'appareil, la sonde de stencil et
  // la profondeur de prepasse sont hors d'atteinte de GLES ; `ao_direct_leak_px` et
  // `ao_sway_gap_px` y vaudraient 0 sans que rien ne les ait comptes.
  if (!(s_prepass_mask & 1)) {
    autoport_proof::publish_text("ao_direct_leak_px", "non-mesure");
  }
  if (!(s_prepass_mask & 2)) {
    autoport_proof::publish_text("ao_sway_gap_px", "non-mesure");
  }
  if (!(s_prepass_mask & 4)) {
    autoport_proof::publish_text("ao_on_alpha_device_px", "non-mesure");
  }
  autoport_proof::publish("ao_owner_term1_direct_leak", t1);
  autoport_proof::publish("ao_owner_term2_pattern", t2);
  autoport_proof::publish("ao_owner_term3_sway", t3);
  autoport_proof::publish("ao_owner_term4_alpha_device", t4);
  autoport_proof::publish("ao_owner_term5_static_cam", t5);
  autoport_proof::publish("ao_owner_term6_contact_band", t6);
  autoport_proof::publish("ao_owner_term7_high_res", t7);
  autoport_proof::publish("ao_owner_terms_measured",
                          (uint64_t)(((s_prepass_mask & 1) ? 1 : 0) +
                                     ((s_prepass_mask & 2) ? 1 : 0) +
                                     ((s_prepass_mask & 4) ? 1 : 0) + (flat_measured ? 1 : 0) +
                                     (static_measured ? 1 : 0) + (contact_measured ? 1 : 0) +
                                     ((q2_full || cross_measured) ? 1 : 0)));
  autoport_proof::publish("ao_owner_defects", t1 + t2 + t3 + t4 + t5 + t6 + t7);
  if (exact_static_probe()) {
    uint64_t missing = 0, depth_delta = 0, camera_delta = 0;
    uint64_t estimator_delta = 0, spatial_delta = 0, estimator_pop = 0;
    for (int i = 0; i < 6; ++i) {
      const auto& state = s_exact[i];
      const std::string suffix = std::string("_") + kCensusName[i];
      auto publish = [&](const char* key, uint64_t value) {
        autoport_proof::publish((key + suffix).c_str(), value);
      };
      publish("ao_static_cam_delta_px", state.delta);
      publish("ao_static_cam_pop_px", state.population);
      publish("ao_static_cam_pairs", state.pairs);
      publish("ao_estimator_delta_px", state.estimator_delta);
      publish("ao_estimator_pop_px", state.estimator_population);
      publish("ao_spatial_filter_delta_px", state.spatial_delta);
      publish("ao_final_with_estimator_delta_px", state.delta - state.spatial_delta);
      publish("ao_static_depth_delta_px", state.depth_delta);
      publish("ao_static_camera_changed_pairs", state.camera_delta);
      publish("ao_static_missing_pairs", state.pairs ? 0 : 1);
      missing += state.pairs == 0;
      depth_delta += state.depth_delta;
      camera_delta += state.camera_delta;
      estimator_delta += state.estimator_delta;
      estimator_pop += state.estimator_population;
      spatial_delta += state.spatial_delta;
    }
    autoport_proof::publish_text("ao_estimator_source", "pass1:m_ao_tex[0]:R8:exact-byte-difference");
    autoport_proof::publish_text("ao_spatial_filter_source",
        "final:m_ao_full_tex:bilateral-HV-boxes-and-ridge-fill;possible-spatial-propagation;"
        "final-changed-and-raw-UV-center-texel-identical;not-exclusive-causal-attribution");
    autoport_proof::publish_text("ao_final_with_estimator_source",
        "final-changed-and-raw-UV-center-texel-changed;spatial-filter-also-applied");
    autoport_proof::publish_text("ao_static_depth_source", "prepass-export-depth24:all-texels:exact-float-bits");
    autoport_proof::publish_text("ao_static_camera_source", "camera-matrix16:hvdf4:fog-x:camera-pos4:exact-float-bits");
    // estimate() consumes no history texture: all following passes are spatial.
    autoport_proof::publish("ao_temporal_passes", 0ull);
    autoport_proof::publish("ao_estimator_delta_px", estimator_delta);
    autoport_proof::publish("ao_estimator_pop_px", estimator_pop);
    autoport_proof::publish("ao_spatial_filter_delta_px", spatial_delta);
    autoport_proof::publish("ao_final_with_estimator_delta_px", static_moved - spatial_delta);
    autoport_proof::publish("ao_static_depth_delta_px", depth_delta);
    autoport_proof::publish("ao_static_camera_changed_pairs", camera_delta);
    autoport_proof::publish("ao_static_missing_pairs", missing);
    if (s_probe_compared) autoport_proof::publish("ao_probe_nondeterminism", s_probe_nondeterminism);
    else autoport_proof::publish_text("ao_probe_nondeterminism", "non-mesure");
    autoport_proof::publish("ao_probe_samples", s_probe_samples);
    autoport_proof::publish("ao_probe_compared", s_probe_compared ? 1ull : 0ull);
    const uint64_t nondeterminism = s_probe_compared && s_probe_samples ? s_probe_nondeterminism : 1ull;
    const uint64_t premise = missing + depth_delta + camera_delta;
    const uint64_t anchors = ao_static_probe::anchor_defects.load() +
                            (ao_static_probe::anchor_executions.load() == 2 ? 0 : 1);
    // PrePass sets bits 8..13 only after each live-wind acquisition is complete.
    const uint64_t acquisition_mask = ((unsigned)s_prepass_mask >> 8) & 0x3fu;
    uint64_t missing_acquisitions = 0;
    for (int state = 0; state < 6; ++state) {
      missing_acquisitions += (acquisition_mask & (1ull << state)) == 0;
    }
    autoport_proof::publish("ao_probe_wind_on_acquisition_mask", acquisition_mask);
    autoport_proof::publish("ao_probe_wind_on_acquisition_missing", missing_acquisitions);
    autoport_proof::publish("ao_static_term_missing_acquisitions", missing_acquisitions);
    autoport_proof::publish("ao_static_term_scene_anchor", anchors);
    autoport_proof::publish("ao_static_term_pair_gap", ao_static_probe::pair_gap_defects);
    autoport_proof::publish("ao_static_term_nondeterminism", nondeterminism);
    autoport_proof::publish("ao_static_term_premise", premise);
    autoport_proof::publish("ao_static_term_final_variation", static_moved);
    autoport_proof::publish("ao_static_term_estimator_variation", estimator_delta);
    autoport_proof::publish("ao_static_term_high_not_fullres", t7);
    autoport_proof::publish("ao_static_term_pattern_over_ceiling", t2);
    autoport_proof::publish("ao_static_term_on_alpha_device", t4);
    autoport_proof::publish("ao_static_term_direct_leak", t1);
    autoport_proof::publish("ao_static_term_contact_band", t6);
    autoport_proof::publish("ao_static_defects", nondeterminism + premise + static_moved + estimator_delta + anchors + ao_static_probe::pair_gap_defects + missing_acquisitions + t7 + t2 + t4 + t1 + t6);
  }
}

bool AmbientOcclusionPass::estimate(SharedRenderState* rs,
                                    GLuint depth_tex,
                                    int depth_w,
                                    int depth_h) {
  gl_query_census::Armed _ap("ao-estimate");
  HutArchive hut_archive;
  ++s_exact_frame;
  s_exact_input_hash = 0;
  s_exact_estimator_valid = false;
  if (exact_static_probe() && s_pattern_census_request) {
    for (int c = 0; c < 4; ++c)
      for (int r = 0; r < 4; ++r) s_exact_camera[c * 4 + r] = rs->camera_matrix[c][r];
    for (int i = 0; i < 4; ++i) s_exact_camera[16 + i] = rs->camera_hvdf_off[i];
    s_exact_camera[20] = rs->camera_fog.x();
    for (int i = 0; i < 4; ++i) s_exact_camera[21 + i] = rs->camera_pos[i];
  }
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
  // ── LE PALIER ELEVE PASSE EN PLEINE RESOLUTION, ET L'ARCHEOLOGIE DIT POURQUOI ────────────
  // Refus du superviseur, essai 7 : « le palier ELEVE a la MEME resolution que le MOYEN ». Le
  // contrat (l) laissait une seconde porte de sortie — `ao_bilateral_cross_px == 0` — mais elle
  // est INATTEIGNABLE telle que la mesure est construite : l'ecart-type de la ponderation vaut
  // 4*zlim et le seuil de « traversee » vaut zlim, donc TOUT tap entre 1 et ~15 zlim compte
  // comme traversant. Releve du 14/09 : 10 524 788 px traversants sur une population de
  // 24 986 880 (temoin 10 482 532) — les deux bras au meme ordre de grandeur. Il ne reste donc
  // qu'une facon de tenir le terme 7 : la PLEINE RESOLUTION.
  //
  // CE QUI A REELLEMENT ETE MESURE (`.autoport/logs/lighting-ao-indirect/attempt-008.jsonl`) :
  //     07:49:19Z rejet FRANC, demi-res           flatstep_worst 67, cross_px 0,
  //                                               contact 23331, static 38368
  //     07:55:42Z sigma = zlim, PLEINE res        flatstep_worst 38, contact 11832, static 9895
  //     08:00:19Z sigma = 4*zlim, PLEINE res      flatstep_worst 23, contact 3250,  static 6294
  //     08:05:05Z UNE boite de pas 16, pleine res flatstep_worst 46
  //     08:14:28Z sigma = 4*zlim, demi-res, UNE boite
  //                                               flatstep_worst 8, contact 851, static 1747
  // CE QUE CE PAVE AFFIRMAIT ET QUI EST FAUX : « echelle 0,50 -> ao_flatstep_ssao_q2_x1000 = 13 ».
  // AUCUNE course n'a jamais publie cette valeur. Le 13 etait un q1 lu en PLEINE resolution ;
  // il a servi a condamner la pleine resolution en la comparant a un chiffre qui n'existait pas.
  //
  // CE QUI N'A JAMAIS ETE MESURE, et que l'essai 10 lance : la pleine resolution SOUS LA PILE DE
  // TROIS BOITES (pas 1, 2, 3 ; support 19 texels), le flou livre depuis c70e048bad. Les quatre
  // relevés « pleine res » ci-dessus datent tous d'une boite UNIQUE de 4 taps, support 4 texels.
  // En support d'ECRAN — la seule unite ou les regimes se comparent : la demi-res a une boite
  // faisait 8 px et rendait 8 ; la pleine res a une boite faisait 4 px et rendait 23 ; la pleine
  // res a trois boites en fait 19. C'est CETTE course-la qui tranche, pas les precedentes.
  // Le nombre d'echantillons par palier ne bouge pas : ce qui distingue le palier haut reste
  // SSAO 16 -> 24, GTAO 6x8 -> 8x10.
  const float scale = (quality == 0) ? 0.25f : (quality == 1) ? 0.5f : 1.0f;
  const int src_w = depth_w;  // depth resolution (render-scale sized)
  const int src_h = depth_h;
  const int out_w = (m_hint_w > 0) ? m_hint_w : src_w;  // AO/blur target sizing: keyed to the
  const int out_h = (m_hint_h > 0) ? m_hint_h : src_h;  // WINDOW so render-scale changes never
                                                        // recreate the AO chain (no churn/blink)
  const int ao_w = std::max(1, (int)(out_w * scale));
  const int ao_h = std::max(1, (int)(out_h * scale));

  // ── TROIS BOITES RAPPROCHEES, PAS UNE BOITE LARGE ────────────────────────────────────────
  // Mesure du 2026-09-14 : a empreinte d'ecran EGALE (52 px), une seconde boite de pas 16 rend
  // `ao_flatstep_ssao_q2` = 46 la ou une de pas 3 rend 23. Un pas large echantillonne quatre
  // points ISOLES ; leurs poids bilateraux different d'un pixel a l'autre et cette variation
  // est elle-meme de la haute frequence. On empile donc TROIS boites de pas 1, 2 et 3 : leurs
  // taps restent voisins, le support composite fait 19 texels par axe, et l'ecart-type du bruit
  // tombe d'un facteur ~8 au lieu de ~2. Le pas 1 est celui qui annule la tuile 4x4 des
  // estimateurs ; les pas 2 et 3 l'annulent aussi a eux seuls (leurs quatre taps couvrent les
  // quatre phases, 2 et 3 etant chacun premier avec 4 ou le couvrant exactement).
  // ── UNE QUATRIEME BOITE AU SEUL PALIER ELEVE, ET C'EST UNE MESURE QUI L'AJOUTE ───────────
  // Course x86 du 14/09 12:55, pleine resolution sous trois boites (support 19 texels) :
  // `ao_flatstep_ssao_q2_x1000` = 14 et `gtao_q2` = 9, pour un plafond de 10 — les paliers BAS
  // et MOYEN, eux, rendent 2 a 7. La cause est structurelle et il faut la dire : a la
  // demi-resolution, deux pixels d'ecran voisins sortent d'une INTERPOLATION BILINEAIRE des
  // memes texels d'AO, donc leur difference SECONDE — ce que `flat_step` mesure — est petite par
  // construction. La pleine resolution n'a plus ce lissage gratuit : elle porte une valeur par
  // pixel, et c'est justement ce que l'owner demande a l'Eleve. Elle doit donc l'acheter par du
  // filtrage, pas par de la resolution en moins. Une boite de plus (pas 5) porte le support de
  // 19 a 29 texels sans jamais isoler ses taps — la faute mesuree le 14/09 08:05, ou UNE boite
  // de pas 16 avait fait remonter flatstep a 46.
  constexpr int kBlurStrides[4] = {1, 2, 3, 5};
  const int nboxes = (quality == 2) ? 4 : 3;

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
    s_scale_q_x1000[quality] = (uint64_t)std::lround(scale * 1000.0);
    autoport_proof::publish(("ao_scale" + q + "_x1000").c_str(), s_scale_q_x1000[quality]);
    autoport_proof::publish(("ao_buf_w" + q).c_str(), (uint64_t)ao_w);
    autoport_proof::publish(("ao_buf_h" + q).c_str(), (uint64_t)ao_h);
    autoport_proof::publish(("ao_blur_boxes" + q).c_str(), (uint64_t)nboxes);
    autoport_proof::publish(("ao_blur_support_texels" + q).c_str(),
                            (uint64_t)(nboxes == 4 ? 29 : 19));
    autoport_proof::publish(("ao_blur_screen_px" + q).c_str(),
                            (uint64_t)std::lround((nboxes == 4 ? 29.0 : 19.0) / (double)scale));
    autoport_proof::publish("ao_depth_w", (uint64_t)src_w);
    autoport_proof::publish("ao_depth_h", (uint64_t)src_h);
    autoport_proof::publish("ao_full_w", (uint64_t)out_w);
    autoport_proof::publish("ao_full_h", (uint64_t)out_h);
    // Le filtre de remontee : H a la resolution du tampon, V a la PLEINE resolution, quatre taps
    // a poids egaux ponderes par l'ecart au PLAN TANGENT local (ao_blur.frag). Pas d'espace dans
    // la valeur : proof.txt coupe a l'espace.
    autoport_proof::publish_text("ao_upsample_filter",
                                 "trois-boites-de-4-pas-1-2-3;bilaterale-plan-en-profondeur-de-fenetre;V-en-pleine-res;remplissage-de-crete-au-contact");
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
  hut_archive.errors("preexisting-gl-error");
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

  if (hut_archive.active) {
    hut_archive.expected = dbg == 2 ? 0 : 7 + ((s_measure_legacy != 0) ? 2 : 2 * nboxes + 4);
    hut_archive.manifest << "render_frame=" << rs->frame_idx << "\nmode=" << mode << "\nquality=" << quality
        << "\nlegacy=" << s_measure_legacy << "\ndebug=" << dbg
        << "\nradius=" << u_radius << "\nintensity=" << u_intensity
        << "\nsamples=" << u_samples << "\ndirs=" << u_dirs << "\nsteps=" << u_steps
        << "\nbroad=" << ((mode == 1) ? 0.0f : 2.0f * ao_strength_mul)
        << "\ndepth_width=" << depth_w << "\ndepth_height=" << depth_h << '\n';
    for (int c = 0; c < 4; ++c) for (int r = 0; r < 4; ++r)
      hut_archive.manifest << "camera_" << c * 4 + r << "=" << rs->camera_matrix[c][r] << '\n';
    for (int i = 0; i < 16; ++i) hut_archive.manifest << "inverse_" << i << "=" << invf[i] << '\n';
    for (int i = 0; i < 4; ++i) {
      hut_archive.manifest << "hvdf_" << i << "=" << rs->camera_hvdf_off[i] << '\n';
      hut_archive.manifest << "pos_" << i << "=" << rs->camera_pos[i] << '\n';
    }
    hut_archive.manifest << "fog=" << rs->camera_fog.x() << '\n';
    hut_archive.capture_depth(depth_tex, depth_w, depth_h);
  }
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
    glUniform1i(glu::loc(id, "u_hut_report"), 0);
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
    // One archived tick only: replay the same estimator into a private target.
    // The production R8 target is never rebound for drawing by this diagnostic.
    if (hut_archive.active && !hut_archive.failed && dbg != 2) {
      ao_contact_readback::ExportState saved;
      GLuint diagnostic_fbo = 0, diagnostic_texture = 0;
      const GLint report = glu::loc(id, "u_hut_report");
      if (report < 0) hut_archive.fail("estimator-report-uniform-missing");
      if (!saved.errors.empty()) hut_archive.fail("estimator-report-state-error");
      if (!hut_archive.failed) {
        glGenTextures(1, &diagnostic_texture);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, diagnostic_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, ao_w, ao_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glGenFramebuffers(1, &diagnostic_fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, diagnostic_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                               diagnostic_texture, 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
          hut_archive.fail("estimator-report-framebuffer");
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, depth_tex);
        glDisable(GL_STENCIL_TEST);
        glDisable(GL_CULL_FACE);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        hut_archive.errors("estimator-report-init");
        hut_archive.manifest << "estimator_report_encoding=rgba8-normal-and-terms-unorm-counts-integer-bytes\n"
            << "report_2=offscreen,sky,beyond-radius,below-min-radius\n"
            << "report_3=bias-or-horizon,above-plane,degenerate-slice,candidates\n"
            << "report_4=broad-offscreen,broad-sky,broad-beyond-radius,broad-below-min-radius\n"
            << "report_5=broad-bias,broad-above-plane,broad-accepted,broad-candidates\n"
            << "report_6=occ-before-gate,occ-after-gate,fade,ao-final\n"
            << "report_counts_overlap=1\nreport_gtao_horizon_count_unavailable=1\n";
        for (int channel = 1; channel <= 6 && !hut_archive.failed; ++channel) {
          glUniform1i(report, channel);
          if (bands > 1) glEnable(GL_SCISSOR_TEST);
          for (int b = 0; b < bands; ++b) {
            const int y0 = int(int64_t(ao_h) * b / bands);
            const int y1 = int(int64_t(ao_h) * (b + 1) / bands);
            if (bands > 1) glScissor(0, y0, ao_w, y1 - y0);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
          }
          if (bands > 1) glDisable(GL_SCISSOR_TEST);
          hut_archive.capture("estimator-report-" + std::to_string(channel),
                              diagnostic_fbo, ao_w, ao_h, true);
        }
        glUniform1i(report, 0);
      }
      if (diagnostic_fbo) glDeleteFramebuffers(1, &diagnostic_fbo);
      if (diagnostic_texture) glDeleteTextures(1, &diagnostic_texture);
      if (!saved.restore()) hut_archive.fail("estimator-report-restore-error");
      hut_archive.errors("estimator-report-final-error");
    }
  }
  hut_archive.capture("estimator", m_ao_fbo[0], ao_w, ao_h);
  ao_glerr("estimate");
  if (exact_static_probe() && s_pattern_census_request && dbg != 2) {
    capture_estimator(m_ao_fbo[0], ao_w, ao_h);
  }

  // (8) Bilateral blur: pass H at AO res (tex0 raw -> tex1), pass V at FULL res
  // (tex1 -> m_ao_full_tex). The full-res V pass doubles as a depth-aware upsample
  // (owner tuning #2: a sub-full-res AO term read raw is blocky at full render res; the
  // linear-filtered low-res source + full-res depth weights kill the stair-stepping
  // without bleeding across depth edges).
  //
  // lighting-ao-indirect, refus owner du 2026-09-13 (« Sur les facades meme en eleve on a un
  // aspect pixelise, comme si c'etait un filtre colle par dessus en pauvre qualite »).
  // SIX passes, et UNE SEULE en pleine resolution — donc le cout de remontee ne bouge pas,
  // seules s'ajoutent des passes a la resolution du TAMPON (un quart des pixels au palier
  // moyen, un seizieme au palier bas). Le releve `ao_us_*` le chiffre.
  //   p0 H pas 1, p1 V pas 1 : la boite de 4 CONSECUTIFS. Elle annule EXACTEMENT la tuile 4x4
  //      des estimateurs, sur des offsets ENTIERS de texel et dans les DEUX axes.
  //   p2..p5 : les boites de pas 2 puis 3. La derniere V est aussi la remontee pleine res.
  // Pour un bruit blanc, l'ecart-type residuel passe de 1/2 a 1/3 de celui de l'estimateur :
  // c'est la marge qui manquait a `ao_flatstep_worst_delivered_x1000` (19 mesure, plafond 10).
  // Une boite de 8 ne traverse aucune arete : le rejet FRANC a 1 % (verdict (l)) ferme la boite
  // sur son centre des que la prediction de plan casse.
  // Le cout est PUBLIE (`ao_us_*`, campagne du verdict (f)).
  bool produced = false;
  if (dbg != 2) {
    auto& shader = (*m_shaders)[ShaderId::AO_BLUR];
    struct BlurLeg {
      GLuint fbo;
      GLuint src;
      int vw, vh;
      float dx, dy;
    };
    // ── LE BRAS TEMOIN REJOUE LA CHAINE D'AVANT, PAS SEULEMENT L'ANCRAGE DU BRUIT ──────────
    // `ao_flatstep_*_legacy_*` doit DEPASSER le plafond, sinon le 7 du bras livre ne prouve
    // rien (verdict (e) de l'owner : « une grandeur qui ne retrouve pas le defaut connu ne peut
    // pas prouver sa disparition »). Jusqu'ici le temoin ne changeait que l'ANCRAGE du bruit
    // des estimateurs, pas le flou : les deux bras recevaient le nouveau flou et rendaient le
    // MEME chiffre. Le temoin rejoue donc la chaine d'AVANT le 2026-09-14 — UNE boite de 4 a
    // pas 1, H a la resolution du tampon puis V en pleine resolution, ponderee par la
    // gaussienne sur la DISTANCE MONDE. C'est l'etat sur lequel l'owner a vu la pixelisation.
    const int nlegs = (s_measure_legacy != 0) ? 2 : (2 * nboxes);
    const float leg_reject = (s_measure_legacy != 0) ? 0.0f : 1.0f;
    // ── (h) LA PASSE DE CRETE EST ARMEE SUR LE BRAS LIVRE, DESARMEE SUR LE TEMOIN ─────────
    // L'ablation ne coute AUCUNE jambe de plus : les six etats temoin gardent la crete que
    // l'owner decrit (« une bande de quelques pixels eclairee sans AO »), les six etats livres
    // ne l'ont plus, dans la MEME course. Quand elle est armee, la derniere jambe VERTICALE
    // n'ecrit plus dans `m_ao_full_fbo` mais dans le brouillon, et c'est la passe de crete qui
    // produit `m_ao_full_fbo` : aucune recopie, aucun blit de plus.
    const bool ridge_fill = (s_measure_legacy == 0);
    if (ridge_fill) {
      ensure_scratch(out_w, out_h);
    }
    const GLuint last_v_fbo = m_ao_full_fbo;
    BlurLeg legs[8];
    if (nlegs == 2) {
      legs[0] = {m_ao_fbo[1], m_ao_tex[0], ao_w, ao_h, 1.0f / ao_wf, 0.0f};
      legs[1] = {last_v_fbo, m_ao_tex[1], out_w, out_h, 0.0f, 1.0f / ao_hf};
    }
    for (int b = 0; b < nboxes && s_measure_legacy == 0; b++) {
      const float s = (float)kBlurStrides[b];
      const bool last = (b == nboxes - 1);
      // H : toujours a la resolution du tampon (tex[0] -> fbo[1]).
      legs[b * 2 + 0] = {m_ao_fbo[1], m_ao_tex[0], ao_w, ao_h, s / ao_wf, 0.0f};
      // V : a la resolution du tampon (tex[1] -> fbo[0]), sauf la DERNIERE qui est aussi la
      // remontee en pleine resolution (tex[1] -> m_ao_full_fbo).
      legs[b * 2 + 1] = last
                            ? BlurLeg{last_v_fbo, m_ao_tex[1], out_w, out_h, 0.0f, s / ao_hf}
                            : BlurLeg{m_ao_fbo[0], m_ao_tex[1], ao_w, ao_h, 0.0f, s / ao_hf};
    }
    for (int p = 0; p < nlegs; p++) {
      shader.activate();
      GLuint id = shader.id();
      glBindFramebuffer(GL_FRAMEBUFFER, legs[p].fbo);
      glViewport(0, 0, legs[p].vw, legs[p].vh);
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D, legs[p].src);
      glUniform1i(glu::loc(id, "u_ao"), 0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, depth_tex);
      glUniform1i(glu::loc(id, "u_depth"), 1);
      upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
      glUniform2f(glu::loc(id, "u_dir"), legs[p].dx, legs[p].dy);
      // Le rejet FRANC a 1 % (verdict (l)) est ARME dans le jeu, toujours. Le regime temoin
      // n'existe que dans la passe de RAPPORT du recensement, plus bas : desarmer ici
      // changerait l'image que l'owner voit.
      glUniform1f(glu::loc(id, "u_edge_reject"), leg_reject);
      glUniform1i(glu::loc(id, "u_blur_report"), 0);
      // `glUseProgram` ne remet AUCUN uniforme a zero : un `u_ridge_fill` laisse a 1 par la
      // passe precedente transformerait toute la chaine de flou en passes de crete.
      glUniform1i(glu::loc(id, "u_ridge_fill"), 0);
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      note_target(legs[p].fbo);
      if (hut_archive.active) {
        hut_archive.manifest << "blur_" << p << "_dx=" << legs[p].dx
                             << "\nblur_" << p << "_dy=" << legs[p].dy
                             << "\nblur_" << p << "_edge_reject=" << leg_reject << '\n';
        hut_archive.capture("blur-" + std::to_string(p), legs[p].fbo, legs[p].vw, legs[p].vh);
      }
    }

    // ── (h) LA PASSE DE CRETE, EN PLEINE RESOLUTION, APRES LE FLOU ─────────────────────────
    // Elle lit l'AO DEJA FLOUTEE (la derniere jambe verticale vient de l'ecrire dans
    // `m_ao_full_tex`) et la profondeur de la passe, et redepose son resultat dans
    // `m_ao_full_fbo` — la texture que shade() lit — apres un aller-retour par le brouillon.
    // ORDRE IMPERATIF : elle passe AVANT la passe de RAPPORT du flou ci-dessous, qui reutilise
    // le MEME brouillon ; l'ecraser ensuite est sans consequence, l'inverse ne l'est pas.
    if (ridge_fill) {
      // ── POURQUOI PLUS DE DEUX PASSES : L'OPERATEUR N'EST PAS IDEMPOTENT ──────────────────
      // La passe teste l'image d'ENTREE et `contact_band()` juge l'image de SORTIE. Un texel
      // peut donc dominer ses voisins de plus de 4/255 EN SORTIE sans avoir jamais ete un
      // maximum local EN ENTREE : ses voisins ont ete abaisses, chacun au minimum de SES
      // propres voisins, dans la MEME passe. Ce n'est pas l'interaction des deux axes seule,
      // comme le disait le commentaire d'avant le 2026-09-14 : c'est le decalage d'une passe
      // entre ce qui est teste et ce qui est juge, et il survit a n'importe quel nombre pair.
      // L'operateur est un MINIMUM restreint aux plis : il ne fait que baisser, il est borne,
      // il CONVERGE — et a son point fixe `out(P) = min(out(P), out(P-1), out(P+1))` sur tout
      // pli, donc `contact_band` vaut zero par construction et non par marge. La queue mesuree
      // se divise par ~30 a chaque passe : 850 (0 passe), 302 (1), 5 a 9 (2). D'ou QUATRE.
      // Nombre PAIR : le resultat retombe dans `m_ao_full_fbo`, la texture que shade() lit,
      // sans une seule recopie.
      constexpr int kRidgeFillPasses = 4;
      GLuint id = shader.id();
      const GLuint ping_fbo[2] = {m_ao_scratch_fbo, m_ao_full_fbo};
      const GLuint ping_tex[2] = {m_ao_full_tex, m_ao_scratch_tex};
      for (int rpi = 0; rpi < kRidgeFillPasses; rpi++) {
        const int rp = rpi & 1;
        glBindFramebuffer(GL_FRAMEBUFFER, ping_fbo[rp]);
        glViewport(0, 0, out_w, out_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, ping_tex[rp]);
        glUniform1i(glu::loc(id, "u_ao"), 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, depth_tex);
        glUniform1i(glu::loc(id, "u_depth"), 1);
        upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
        glUniform2f(glu::loc(id, "u_dir"), 0.0f, 0.0f);  // la crete prend ses deux axes
        glUniform1f(glu::loc(id, "u_edge_reject"), leg_reject);
        glUniform1i(glu::loc(id, "u_blur_report"), 0);
        glUniform1i(glu::loc(id, "u_ridge_fill"), 1);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        note_target(ping_fbo[rp]);
        if (hut_archive.active)
          hut_archive.capture("ridge-" + std::to_string(rpi), ping_fbo[rp], out_w, out_h);
        s_ridge_fill_passes++;
      }
      s_ridge_fill_armed = 1;
    }
    // ── (l) LE FILTRE NE TRAVERSE PAS LES ARETES, ET ON LE MESURE ────────────────────────
    // Deux passes de RAPPORT, sur l'image SONDEE seulement, avec les parametres EXACTS de la
    // derniere jambe (celle dont l'empreinte est la plus large). Bras ARME : le compte doit
    // etre 0 — le `continue` du shader le garantit par construction, et c'est justement ce
    // qu'il faut dire. Bras DESARME : le MEME comptage avec la seule gaussienne d'avant, qui
    // ne s'annule jamais ; il doit etre NON NUL, sinon la grandeur ne sait pas voir ce
    // qu'elle declare absent.
      if (s_pattern_census_request && s_census_pair_phase <= 0) {
      ensure_scratch(out_w, out_h);
      GLuint id = shader.id();
      for (int arm = 0; arm < 2; arm++) {
        glBindFramebuffer(GL_FRAMEBUFFER, m_ao_scratch_fbo);
        glViewport(0, 0, out_w, out_h);
        glActiveTexture(GL_TEXTURE0);
        // Configuration EXACTE de la jambe p3 — la seule en pleine resolution, donc celle dont
        // l'empreinte de rejet est la plus large — mais ecrite dans le tampon de brouillon, pas
        // dans `m_ao_full_fbo` : le livre ne doit pas etre ecrase par une image de drapeaux.
        glBindTexture(GL_TEXTURE_2D, m_ao_tex[1]);
        glUniform1i(glu::loc(id, "u_ao"), 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, depth_tex);
        glUniform1i(glu::loc(id, "u_depth"), 1);
        upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
        glUniform2f(glu::loc(id, "u_dir"), 0.0f, 3.0f / ao_hf);
        glUniform1f(glu::loc(id, "u_edge_reject"), (arm == 0) ? 1.0f : 0.0f);
        glUniform1i(glu::loc(id, "u_blur_report"), 1);
        glUniform1i(glu::loc(id, "u_ridge_fill"), 0);  // rapport de FLOU, pas de crete
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        note_target(m_ao_scratch_fbo);
        cross_census(arm, m_ao_scratch_fbo, out_w, out_h);
      }
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
