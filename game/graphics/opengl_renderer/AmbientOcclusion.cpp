#include "game/graphics/opengl_renderer/soft_draw_census.h"
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
#include "game/graphics/opengl_renderer/ao_hut_edge_reference.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/system/autoport_proof.h"
#include "game/system/ao_item.h"

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

// ── (n) LES FAITS D'ARCHITECTURE QUE LA PREPASSE MESURE ──────────────────────────────────────
// Le terme 9 se juge ici, mais trois de ses grandeurs se produisent la ou l'AO est LIEE aux
// programmes du decor (`prepass::bind_screen_ao`) : c'est le seul endroit qui connaisse les
// programmes lies, et seul le PILOTE peut dire si un nom d'uniforme a un lecteur. Elles
// arrivent par `set_arch_terms`, comme les trois termes de prepasse.
uint64_t s_arch_indirect_hit_px = 0;
uint64_t s_arch_probe_px = 0;
uint64_t s_arch_luma_mask_sites = 0;
uint64_t s_arch_switch_readers = 0;
uint64_t s_arch_programs_queried = 0;

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
// petit compte d'images des quatre (`ao_cost_min_frames`).
struct CostLeg {
  int mode;
  int quality;
  const char* key;
};
// ao-indirect-clean (G) : « temps par image AO eteinte / SSAO / HBAO / GTAO, meme vantage,
// >= 300 images chacun, publie ». LES QUATRE JAMBES QUE LE CONTRAT NOMME, ET HBAO EN FAISAIT
// PARTIE SANS ETRE LA : les cinq jambes d'avant etaient off / ssao_q0 / ssao_q2 / gtao_q0 /
// gtao_q2 — l'estimateur du milieu n'avait AUCUNE jambe, et rien ne le disait. Les trois
// estimateurs sont releves au meme palier (Eleve, 2), celui que l'owner force au maximum quand
// il teste ; le palier est publie (`ao_cost_quality`) pour qu'on ne le devine pas. Quatre
// jambes au lieu de cinq, c'est aussi 360 images de moins a tenir dans la course.
constexpr int kCostQuality = 2;
constexpr CostLeg kCostLegs[4] = {
    {0, kCostQuality, "off"},
    {1, kCostQuality, "ssao"},
    {2, kCostQuality, "hbao"},
    {3, kCostQuality, "gtao"}};
constexpr int kCostLegCount = (int)(sizeof(kCostLegs) / sizeof(kCostLegs[0]));
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
uint64_t s_cost_us[kCostLegCount] = {0, 0, 0, 0};
uint64_t s_cost_frames[kCostLegCount] = {0, 0, 0, 0};
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
  if (!ao_item::measured() || frame < kCostStartFrame) {
    s_timing_mode = -1;
    s_timing_quality = -1;
    s_cost_have_last = false;
    return;
  }
  if (s_cost_leg < 0) {
    s_cost_leg = 0;
    s_cost_leg_frame = 0;
  }
  if (s_cost_leg >= kCostLegCount) {
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
  for (int i = 0; i < kCostLegCount; i++) {
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
  autoport_proof::publish("ao_cost_legs_total", (uint64_t)kCostLegCount);
  autoport_proof::publish("ao_cost_quality", (uint64_t)kCostQuality);
  autoport_proof::publish("ao_cost_frames_min_required", kCostMeasured);
  autoport_proof::publish("ao_cost_start_frame", kCostStartFrame);
  // Rend falsifiable « un releve de moins de 300 images ne compte pas » sans relire 4 cles.
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
  if (m_ao_gterm_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_gterm_fbo);
    glDeleteTextures(1, &m_ao_gterm_tex);
    m_ao_gterm_fbo = 0;
    m_ao_gterm_tex = 0;
    m_ao_gterm_w = 0;
    m_ao_gterm_h = 0;
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

// Cible de la carte `g` de la restauration de contact (essai 15). Meme forme que le brouillon,
// meme allocation paresseuse : le bras temoin et la vue de debug ne la demandent pas.
void AmbientOcclusionPass::ensure_gterm(int full_w, int full_h) {
  if (m_ao_gterm_fbo && m_ao_gterm_w == full_w && m_ao_gterm_h == full_h) {
    return;
  }
  if (m_ao_gterm_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_gterm_fbo);
    glDeleteTextures(1, &m_ao_gterm_tex);
    m_ao_gterm_fbo = 0;
    m_ao_gterm_tex = 0;
  }
  m_ao_gterm_w = full_w;
  m_ao_gterm_h = full_h;
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glGenFramebuffers(1, &m_ao_gterm_fbo);
  glGenTextures(1, &m_ao_gterm_tex);
  glBindTexture(GL_TEXTURE_2D, m_ao_gterm_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, full_w, full_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
  hdr::note_input_source("ao-gterm", GL_R8, full_w, full_h, 1);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, m_ao_gterm_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_gterm_tex, 0);
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("AO: contact gterm FBO incomplete ({}x{})", full_w, full_h);
  }
}

// ---------------------------------------------------------------------------
// Uniform upload helper: the shared world<->screen transform uniforms every AO/blur
// pass needs. Uploads camera + inverse + hvdf + fog + cam_pos + sizes.
// ---------------------------------------------------------------------------
namespace {

// One attempt per process at the explicit hut capture tick; no probe scheduling changes.
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
    if (frame < ao_contact_archive::kCaptureLogicFrame) return;
    attempted = true;
    active = true;
    manifest.imbue(std::locale::classic());
    manifest << "format=ao-hut-r8-v1\nexpected_logic_frame=" << ao_contact_archive::kCaptureLogicFrame
             << "\nlogic_frame=" << frame
             << "\norigin=lower-left\nlayout=R8-tight-rows\nhash=fnv1a64\n"
                "depth=prepass-f32-d24-decoded\nscene_depth=scene-depth.meta\n";
    manifest << std::setprecision(std::numeric_limits<float>::max_digits10);
    autoport_proof::publish_text("ao_hut_archive_status", "missing");
    if (frame != ao_contact_archive::kCaptureLogicFrame) fail("logical-capture-frame-missing");
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
// (k) LA PREMISSE DU TERME 5 : le vent etait-il coupe sur CETTE image, et l'etait-il sur les
// DEUX images de la paire jugee ? `s_static_pairs_wind_cut` doit egaler `s_static_pairs`, sinon
// le terme se declare non mesure — et un terme non mesure compte pour un defaut nomme.
bool s_census_wind_cut = false;
uint64_t s_static_pairs_wind_cut = 0;
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

// (m) HBAO ENTRE AU RECENSEMENT. L'owner a teste les TROIS modes, et le contrat compte 1 par
// couple (mode, qualite) NON mesure : laisser HBAO hors du recensement, c'est trois defauts
// nommes d'avance. L'ordre ci-dessous est l'arithmetique `legacy*9 + mode_idx*3 + quality`.
constexpr int kCensusStates = 18;
constexpr const char* kCensusName[kCensusStates] = {
    "ssao_q0", "ssao_q1", "ssao_q2", "gtao_q0", "gtao_q1", "gtao_q2",
    "hbao_q0", "hbao_q1", "hbao_q2",
    "legacy_ssao_q0", "legacy_ssao_q1", "legacy_ssao_q2",
    "legacy_gtao_q0", "legacy_gtao_q1", "legacy_gtao_q2",
    "legacy_hbao_q0", "legacy_hbao_q1", "legacy_hbao_q2"};

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
// ── (terme 5) LE MEME MASQUE, MAIS SANS SEUIL — POUR NOMMER LA CAUSE, PAS POUR LA JUGER ──────
// `kSameGeom` vaut 4 quanta de profondeur 24 bits : un mobile qui se deplace MOINS que ca d'une
// image a l'autre reste dans la population alors que l'estimateur d'AO, lui, l'a vu bouger. Le
// signalement de l'essai 16 de `lighting-ao-indirect` le disait deja et personne ne l'a chiffre.
// Ces deux compteurs le chiffrent, SANS toucher a la definition du terme : parmi les texels
// comptes « l'AO a bouge alors que rien n'a bouge », combien ont, a UN quantum pres (egalite
// stricte des entiers 24 bits relus), soit un voisin dans la boite qui a bouge, soit une
// profondeur a eux qui a bouge. Si la quasi-totalite tombe dedans, le residu est un defaut du
// SEUIL, pas une instabilite de l'AO — et ca se lit au lieu de se supposer.
std::vector<uint8_t> s_static_changed_x;  // masque exact (zn != zo), aucun seuil
std::vector<uint32_t> s_static_sat_x;     // sa somme cumulee 2D
uint64_t s_static_moved_near_any = 0;   // ... dont un voisin de la boite a bouge, seuil 0
uint64_t s_static_moved_self_dz = 0;    // ... dont la profondeur PROPRE a bouge, seuil 0
// ── (terme 5) LA MEME POPULATION SOUS UN GARDE SANS SEUIL, ET SON DENOMINATEUR ───────────────
// « 27 807 texels sur 27 807 ont un voisin qui a bouge » ne classe RIEN tant qu'on ne sait pas
// combien de texels de la POPULATION en ont un : la boite fait 0,10 UV de demi-cote, soit
// ~160 x 120 texels, et un seul mobile quelque part dedans la marque. D'ou ces deux tableaux :
// la population et les texels qui bougent sous le garde EXACT (profondeur propre inchangee au
// quantum pres ET aucun voisin de la boite qui ait bouge d'un seul quantum). `_pop` est le
// denominateur qui rend `_moved` lisible ; `_moved` est la valeur que le terme 5 prendrait si
// son garde n'avait pas de seuil. Publies par etat, sommes par bras. Aucun terme ne les lit.
uint64_t s_static_pop_x[kCensusStates] = {0};
uint64_t s_static_moved_x[kCensusStates] = {0};
// ── (terme 5, essai 3) LE GARDE QUI COUVRE CE QUE LE TEXEL LIT VRAIMENT ──────────────────────
// La boite ci-dessus fait 0,10 UV : c'est le plafond que GTAO et HBAO se donnent sur leur marche
// d'ECRAN (`ao_gtao.frag`, `ao_hbao.frag`), et rien de plus. Or le texel publie n'est pas la
// sortie de l'estimateur. Entre les deux il y a, dans cet ordre :
//   . le FLOU, 4 boites a la qualite Elevee et 3 sinon, strides {1,2,3,5}, taps a ±2·s TEXELS DU
//     TAMPON D'AO (`kBlurStrides`, AmbientOcclusion.cpp) — soit 2·Σs/scale PIXELS D'ECRAN :
//     22 px en pleine resolution, 24 px a demi, 48 px au quart ;
//   . la passe de CRETE, ±1 texel pleine resolution (`ao_blur.frag`, `u_ridge_fill`) ;
//   . la carte de CONTACT, ±(kContactRadius + 1) puis une tente ±2, pleine resolution : ±8 px.
// Un occluder qui bouge entre 80 et 137 pixels du texel change donc son AO sans que le garde de
// 0,10 UV ne le voie, et le texel est compte comme un defaut. Ces compteurs-ci portent le garde
// ELARGI a la chaine ENTIERE, avec la profondeur identique AU BIT PRES (aucun seuil de 4 quanta),
// et DEUX seuils d'ecart d'AO : `_gt2` garde l'ancien (2/255) pour la comparaison, `_any` n'en a
// AUCUN. C'est `_any` que le terme 5 lit — le contrat dit « 0 texel bouge », pas « peu » — et
// c'est defendable : entrees identiques au bit pres, un shader deterministe rend la MEME sortie,
// et les trois estimateurs n'ont ni `u_frame` ni `u_time` (leur bruit est procedural, ancre a
// l'ECRAN dans le regime livre). Un ecart non nul est un defaut, pas un arrondi.
uint64_t s_static_pop_w[kCensusStates] = {0};
uint64_t s_static_moved_w_gt2[kCensusStates] = {0};
uint64_t s_static_moved_w_any[kCensusStates] = {0};
uint64_t s_static_box_rx[kCensusStates] = {0};
uint64_t s_static_box_ry[kCensusStates] = {0};
uint64_t s_static_w_worst_ao = 0, s_static_w_worst_x = 0, s_static_w_worst_y = 0;
uint64_t s_static_w_worst_state = 0;
uint64_t s_static_moved_worst_ao = 0;   // le plus gros ecart d'AO (unites R8) parmi eux
uint64_t s_static_moved_worst_x = 0, s_static_moved_worst_y = 0;
uint64_t s_static_moved_worst_state = 0, s_static_moved_worst_dzq = 0;

// ── (l) LE FILTRE BILATERAL NE TRAVERSE PAS LES ARETES ───────────────────────────────────────
// Relecture de la passe de RAPPORT du flou (`u_blur_report`). Indice 0 : bras ARME (rejet franc
// a 1 %) ; indice 1 : bras TEMOIN (la gaussienne seule, celle d'avant le 2026-09-14).
// ── (h) LA PASSE DE REMPLISSAGE DE CRETE : ARMEE / COMPTEE ───────────────────────────────────
// Elle est armee quand `s_measure_legacy == 0`, c'est-a-dire sur les SIX etats LIVRES, et
// desarmee sur les six etats TEMOIN — meme course, meme scene, ablation sans jambe de plus.
// En jeu `s_measure_legacy` vaut 0 : le chemin livre l'a TOUJOURS.
uint64_t s_ridge_fill_armed = 0;
uint64_t s_ridge_fill_passes = 0;
// ── ao-prepass-tie-alpha, essai 15 : la restauration de contact ──────────────────────────────
// `s_contact_strength_milli` est le K EFFECTIVEMENT pose sur la derniere jambe ; `s_contact_fbo`
// donne au recensement de quoi relire la carte `g` produite par le GPU, pour que la preuve porte
// une grandeur MESUREE et pas un compteur de passes qui se regarde lui-meme.
constexpr float kContactStrength = 0.25f;
uint64_t s_contact_armed = 0;
uint64_t s_contact_passes = 0;
uint64_t s_contact_strength_milli = 0;
uint64_t s_contact_g_frames = 0;
uint64_t s_contact_g_pop = 0;
uint64_t s_contact_g_px = 0;
uint64_t s_contact_g_hi_px = 0;
uint64_t s_contact_g_max = 0;
uint64_t s_contact_g_sum = 0;
GLuint s_contact_gterm_fbo = 0;
std::vector<uint8_t> s_contact_buf;

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
uint8_t s_prev_wind_cut[kCensusStates] = {0};
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

// ── (essai 17) CE QUE `contact_band()` NE PEUT PAS VOIR, ET LE TEMOIN QUI LE DIT ─────────────
// `contact_band()` exige que le pixel du PLI soit un maximum local a 3 taps, 4/255 au-dessus de
// SES DEUX voisins. Le defaut que l'owner decrit n'a pas cette forme : c'est une RAMPE claire A
// COTE du pli. Sur une rampe monotone tout pixel a un voisin plus clair, le `||` court-circuite
// toujours, et `band` reste 0 — mesure locale sur le tampon d'AO APPAREIL de la hutte
// (`notes/attempt17-band-calib.json`) : 0 sur l'etat livre ET sur l'etat d'avant, la ou le
// lecteur de profils en compte 12. Un zero par CECITE, pas par proprete.
//
// Pourquoi pas un simple comptage de pixels clairs. Le meme banc chiffre le plancher : une regle
// « plus clair que le fond de 4/255 » rend 1,2435 par cote sur un VRAI PLAN, ou il n'y a aucun
// contact. Transpose aux 35 379 cotes de plis, son plancher vaut ~44 000 : une porte `== 0` y
// serait condamnee par le bruit, et le correctif ne la deplace que de 3,7 %.
//
// D'ou le TEMOIN GRATUIT : la MEME statistique, dans la MEME image, sur les pixels dont la
// profondeur est PLANE au sens de l'essai 15 (courbure sous 2 % des differences premieres aux
// rayons 1..6, deux axes). Un plan n'a pas de contact : ce qu'on y lit est le zero de
// l'instrument. Le defaut, lui, est l'EXCES des plis sur ce zero.
struct ContactRamp {
  uint64_t sides = 0;        // cotes juges (denominateur)
  uint64_t positive = 0;     // cotes dont le contact est plus CLAIR que le fond, d'un quantum
  uint64_t bright = 0;       // idem, mais de 4/255 : le seuil de la crete historique
  uint64_t lift_pos = 0;     // somme des levees positives, en milli-quanta d'AO
  uint64_t lift_neg = 0;     // somme des levees negatives, meme unite, VALEUR ABSOLUE
  uint64_t rejected = 0;     // cotes ECARTES : hors ecran, ou la marche quitte la surface
};
// Fenetres du profil : `near` colle au contact, `far` est le fond de la MEME surface. Les deux
// fenetres ont la MEME largeur : le banc local montre qu'une fenetre asymetrique (2 pres / 4
// loin) biaise la moyenne de 5,8 ecarts-types sur un plan, ou elle doit valoir zero.
constexpr int kRampNear = 3;   // v[0..2]
constexpr int kRampFar0 = 6;   // v[6..8]
constexpr int kRampLen = 9;
constexpr int kRampBright = 4;  // 4/255, le meme seuil que la crete historique
constexpr double kRampJumpRel = 0.02;  // au-dela, la marche a quitte la surface
constexpr int kPlaneRadius = 6;
constexpr double kPlaneRel = 0.02;
constexpr double kPlaneAbs = 1e-5;
constexpr int kPlaneStride = 4;  // le plan est vaste : un pixel sur 16 suffit a sa moyenne

// Un cote : le profil de `k = 0..8` en s'eloignant du point, dans la direction (dx,dy)*s.
// LA MARCHE DOIT RESTER SUR LA SURFACE. Mesure locale : sans ce confinement, 23 % des cotes
// d'un plan en sortent, et ils portent A EUX SEULS un biais de +0,78 quantum — un biais qui
// CROIT avec la force du correctif, donc qui se ferait passer pour son effet. Confinee, la
// moyenne d'un plan vaut zero a 0,002 erreur-type pres.
inline void ramp_side(const uint8_t* ao,
                      const float* depth,
                      const uint8_t* mask,
                      int w,
                      int h,
                      int x,
                      int y,
                      int dx,
                      int dy,
                      int s,
                      ContactRamp* out) {
  int v[kRampLen];
  double zprev = 0.0;
  for (int k = 0; k < kRampLen; k++) {
    const int xx = x + dx * s * k;
    const int yy = y + dy * s * k;
    if (xx < 0 || yy < 0 || xx >= w || yy >= h) {
      out->rejected++;
      return;
    }
    const size_t idx = (size_t)yy * (size_t)w + (size_t)xx;
    const double zz = (double)depth[idx];
    if (zz <= 1e-9 || (mask && !mask[idx])) {
      out->rejected++;
      return;
    }
    if (k > 0 && std::fabs(zz - zprev) > kRampJumpRel * zz) {
      out->rejected++;  // un SAUT : la marche est passee sur une autre surface
      return;
    }
    zprev = zz;
    v[k] = (int)ao[idx];
  }
  int near_sum = 0, far_sum = 0;
  for (int k = 0; k < kRampNear; k++) near_sum += v[k];
  for (int k = kRampFar0; k < kRampLen; k++) far_sum += v[k];
  const int n_near = kRampNear, n_far = kRampLen - kRampFar0;
  // Levee = moyenne pres du point MOINS moyenne au loin, SIGNEE, en milli-quanta.
  const int64_t lift =
      ((int64_t)near_sum * 1000) / n_near - ((int64_t)far_sum * 1000) / n_far;
  out->sides++;
  if (lift > 0) {
    out->lift_pos += (uint64_t)lift;
    out->positive++;
  } else {
    out->lift_neg += (uint64_t)(-lift);
  }
  if (lift > (int64_t)kRampBright * 1000) {
    out->bright++;
  }
}

// Le plan : courbure nulle a tous les rayons 1..6, deux axes — la definition de l'essai 15.
inline bool plane_pixel(const float* depth, int w, int h, int x, int y) {
  auto z = [&](int xx, int yy) -> double {
    return (double)depth[(size_t)yy * (size_t)w + (size_t)xx];
  };
  const double z0 = z(x, y);
  if (z0 <= 1e-9) return false;
  for (int r = 1; r <= kPlaneRadius; r++) {
    for (int axis = 0; axis < 2; axis++) {
      const int dx = axis == 0 ? r : 0;
      const int dy = axis == 0 ? 0 : r;
      if (x - dx < 0 || y - dy < 0 || x + dx >= w || y + dy >= h) return false;
      const double zm = z(x - dx, y - dy), zp = z(x + dx, y + dy);
      if (zm <= 1e-9 || zp <= 1e-9) return false;
      const double d1 = z0 - zm, d2 = zp - z0;
      if (std::fabs(d2 - d1) > kPlaneRel * (std::fabs(d1) + std::fabs(d2)) + kPlaneAbs) {
        return false;
      }
    }
  }
  return true;
}

// Le masque de plan ne depend QUE de la profondeur, et la camera ne bouge pas : il se calcule
// une fois et se relit pour les douze etats. L'empreinte de la profondeur le dit — un plan
// recalcule sur une autre image serait un temoin d'une AUTRE scene.
std::vector<uint8_t> s_plane_mask;
uint64_t s_plane_mask_key = 0;
int s_plane_mask_w = 0, s_plane_mask_h = 0;
uint64_t s_plane_mask_px = 0;

const uint8_t* plane_mask(const float* depth, int w, int h) {
  uint64_t key = 14695981039346656037ull;
  const size_t n = (size_t)w * (size_t)h;
  const auto* bytes = reinterpret_cast<const uint8_t*>(depth);
  for (size_t i = 0; i < n * sizeof(float); i++) key = (key ^ bytes[i]) * 1099511628211ull;
  if (key != s_plane_mask_key || w != s_plane_mask_w || h != s_plane_mask_h) {
    s_plane_mask.assign(n, 0);
    s_plane_mask_px = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (plane_pixel(depth, w, h, x, y)) {
          s_plane_mask[(size_t)y * (size_t)w + (size_t)x] = 1;
          s_plane_mask_px++;
        }
      }
    }
    s_plane_mask_key = key;
    s_plane_mask_w = w;
    s_plane_mask_h = h;
  }
  return s_plane_mask.data();
}

void contact_ramp(const uint8_t* ao,
                  const float* depth,
                  int w,
                  int h,
                  ContactRamp* folds_out,
                  ContactRamp* plane_out) {
  const double kCreaseRel = 0.25, kCreaseAbs = 1e-5, kJumpRel = 0.02;
  auto z = [&](int x, int y) -> double {
    return (double)depth[(size_t)y * (size_t)w + (size_t)x];
  };
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      const double z0 = z(x, y);
      if (z0 <= 1e-9) continue;
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        const double zm = z(x - dx, y - dy), zp = z(x + dx, y + dy);
        if (zm <= 1e-9 || zp <= 1e-9) continue;
        const double d1 = z0 - zm, d2 = zp - z0;
        if (std::max(std::fabs(d1), std::fabs(d2)) > kJumpRel * z0) continue;
        if (std::fabs(d2 - d1) <= kCreaseRel * (std::fabs(d1) + std::fabs(d2)) + kCreaseAbs) {
          continue;
        }
        // MEME population que `contact_band()` : les deux partagent leur denominateur, et
        // `ao_contact_pop_px` reste lisible a cote de `ao_ramp_sides`.
        ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, -1, folds_out);
        ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, +1, folds_out);
      }
    }
  }
  const uint8_t* mask = plane_mask(depth, w, h);
  for (int y = 1; y < h - 1; y += kPlaneStride) {
    for (int x = 1; x < w - 1; x += kPlaneStride) {
      if (!mask[(size_t)y * (size_t)w + (size_t)x]) continue;
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        ramp_side(ao, depth, mask, w, h, x, y, dx, dy, -1, plane_out);
        ramp_side(ao, depth, mask, w, h, x, y, dx, dy, +1, plane_out);
      }
    }
  }
}
ContactRamp s_contact_ramp[kCensusStates];
ContactRamp s_contact_plane[kCensusStates];

// ── (essai 18, verdict H) LES ARETES QUALIFIEES, TROUVEES PAR LE MOTEUR ─────────────────────
// Verdict H du contrat (17/09) : « la population des aretes mur/toit de la hutte est trouvee par
// le moteur (angle diedre + profondeur), pas par des triangles choisis a la main ».
//
// POURQUOI ce detecteur, et pas la population de plis deja mesuree. `contact_ramp()` juge
// 35 379 cotes : le raccord que l'owner montre n'en pese que 22. La mesure de l'essai 17 le
// chiffre — la levee moyenne y est NEGATIVE des deux cotes, donc l'agregat ne peut pas isoler
// le raccord. Sa population est definie par une courbure RELATIVE de la profondeur
// (`curv > 0,25*(|d1|+|d2|)`), qui retient des milliers de pixels quasi plans : un seuil
// relatif n'a pas d'echelle, il compare du bruit a du bruit.
//
// CE QUE CELUI-CI AJOUTE : un ANGLE. La profondeur de fenetre se deprojette en position MONDE
// par la MEME fonction que les quatre shaders d'AO (`world_from_depth`, ao_ssao.frag:36-43 et
// jumelles) ; de part et d'autre du pli, a `kEdgeSpan` pixels, on ajuste une normale par la
// MEME formule que l'estimateur (voisin le plus proche en profondeur, orientee vers la camera,
// ao_gtao.frag:146-156). L'angle entre ces deux normales est le DIEDRE, en degres, et il ne
// depend ni de la distance ni de l'angle de vue.
//
// LE SIGNE N'EST PAS SUPPOSE. Un raccord mur/toit est CONCAVE — c'est pour cela que l'AO doit y
// creuser — mais rien dans le code ne peut le decreter : le sens de la profondeur (reverse-Z),
// l'orientation des normales et la convention d'ecran s'y composent. Les deux populations sont
// donc detectees et publiees SEPAREMENT, avec leur rampe : le CONVEXE est le controle gratuit
// de la meme image. Un booleen aurait rendu une population juste et MUETTE.
struct HutEdge {
  uint64_t fold_sides = 0;    // denominateur : cotes de pli examines par le detecteur
  uint64_t angled_sides = 0;  // ... dont le diedre est qualifie (normales des deux cotes valides)
  uint64_t sign_agree = 0;    // ... dont les DEUX lectures du signe (profondeur / monde) disent
                              // la meme chose : le temoin croise, jamais suppose
  uint64_t concave_px = 0;    // pixels retenus, diedre CONCAVE
  uint64_t convex_px = 0;     // pixels retenus, diedre CONVEXE (controle gratuit)
  uint64_t components = 0;    // composantes connexes des pixels concaves = les ARETES trouvees
  uint64_t largest = 0;       // pixels de la plus grande
  uint64_t ref_depth_px = 0;     // des 425 px de l'essai 10, combien portent une SURFACE
                                 // aujourd'hui : le temoin que la camera n'a pas bouge
  uint64_t ref_edges_hit = 0;    // des 15 aretes de l'essai 10, combien sont retrouvees
  uint64_t ref_px_hit = 0;       // des 425 px de l'essai 10, combien portent un pixel detecte
  uint64_t detected_in_ref = 0;  // ... et combien des detectes tombent dans ces 425 px
};

// La camera de l'image sondee, telle que les estimateurs la recoivent : `pattern_census()` est
// appelee depuis `estimate()`, qui les a posees une ligne plus haut. Rien n'est recalcule ici —
// une deuxieme inversion de matrice serait un SECOND instrument.
float s_census_cam_inv[16] = {0};
float s_census_cam_hvdf[4] = {0};
float s_census_cam_pos[4] = {0};
float s_census_cam_fog = 0.0f;
bool s_census_cam_valid = false;

// `world_from_depth` des shaders, au flottant pres : memes constantes GS (256, -128, 2048,
// 2^23), meme `u_fog` en composante W, meme inverse column-major. Le recensement lit la
// profondeur A LA MEME RESOLUTION que `u_depth` (garde `s_census_depth_w != w`), donc le centre
// de texel `(x+0,5)/w` EST le `snapped` du shader.
inline void census_world(int x, int y, int w, int h, float d, float out[3]) {
  const float ndc_x = ((float)x + 0.5f) / (float)w * 2.0f - 1.0f;
  const float ndc_y = ((float)y + 0.5f) / (float)h * 2.0f - 1.0f;
  const float ndc_z = d * 2.0f - 1.0f;
  const float v[4] = {ndc_x * 256.0f + 2048.0f - s_census_cam_hvdf[0],
                      ndc_y * -128.0f + 2048.0f - s_census_cam_hvdf[1],
                      (ndc_z + 1.0f) * 8388608.0f - s_census_cam_hvdf[2], s_census_cam_fog};
  float p[4];
  for (int r = 0; r < 4; r++) {
    p[r] = s_census_cam_inv[0 * 4 + r] * v[0] + s_census_cam_inv[1 * 4 + r] * v[1] +
           s_census_cam_inv[2 * 4 + r] * v[2] + s_census_cam_inv[3 * 4 + r] * v[3];
  }
  const float iw = (p[3] != 0.0f) ? 1.0f / p[3] : 0.0f;
  out[0] = p[0] * iw;
  out[1] = p[1] * iw;
  out[2] = p[2] * iw;
}

// Position et normale MONDE de toute l'image. La camera ne bouge pas et les douze etats
// partagent la MEME profondeur : la carte se calcule une fois et se relit. La cle est
// l'empreinte de la profondeur, comme pour `plane_mask` — une carte recalculee sur une autre
// image serait le temoin d'une AUTRE scene.
struct CensusGeometry {
  uint64_t key = 0;
  int w = 0, h = 0;
  std::vector<float> P;
  std::vector<float> N;
  std::vector<uint8_t> ok;  // 1 = position valide, 2 = position ET normale valides
  uint64_t surface_px = 0;
  uint64_t normal_px = 0;
};
CensusGeometry s_geom;

uint64_t depth_key(const float* depth, int w, int h) {
  uint64_t key = 14695981039346656037ull;
  const size_t n = (size_t)w * (size_t)h * sizeof(float);
  const auto* bytes = reinterpret_cast<const uint8_t*>(depth);
  for (size_t i = 0; i < n; i++) key = (key ^ bytes[i]) * 1099511628211ull;
  return key;
}

const CensusGeometry* census_geometry(const float* depth, int w, int h) {
  if (!s_census_cam_valid) return nullptr;
  const uint64_t key = depth_key(depth, w, h);
  if (key == s_geom.key && w == s_geom.w && h == s_geom.h) return &s_geom;
  const size_t n = (size_t)w * (size_t)h;
  s_geom.P.assign(n * 3, 0.0f);
  s_geom.N.assign(n * 3, 0.0f);
  s_geom.ok.assign(n, 0);
  s_geom.surface_px = 0;
  s_geom.normal_px = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      const size_t i = (size_t)y * (size_t)w + (size_t)x;
      if (depth[i] <= 1e-9f) continue;  // ciel : reverse-Z, 0 = le plus loin
      census_world(x, y, w, h, depth[i], &s_geom.P[i * 3]);
      s_geom.ok[i] = 1;
      s_geom.surface_px++;
    }
  }
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      const size_t i = (size_t)y * (size_t)w + (size_t)x;
      if (!s_geom.ok[i]) continue;
      const size_t l = i - 1, r = i + 1, dn = i - (size_t)w, up = i + (size_t)w;
      if (!s_geom.ok[l] || !s_geom.ok[r] || !s_geom.ok[dn] || !s_geom.ok[up]) continue;
      const float d = depth[i];
      // Le MEME choix de voisin que l'estimateur : le plus proche en profondeur, pour que la
      // normale reste sur la surface quand le pli est a un pixel.
      const float* p = &s_geom.P[i * 3];
      const float* px = (std::fabs(depth[r] - d) < std::fabs(depth[l] - d)) ? &s_geom.P[r * 3]
                                                                           : &s_geom.P[l * 3];
      const float sx = (std::fabs(depth[r] - d) < std::fabs(depth[l] - d)) ? 1.0f : -1.0f;
      const float* py = (std::fabs(depth[up] - d) < std::fabs(depth[dn] - d)) ? &s_geom.P[up * 3]
                                                                             : &s_geom.P[dn * 3];
      const float sy = (std::fabs(depth[up] - d) < std::fabs(depth[dn] - d)) ? 1.0f : -1.0f;
      const float dh[3] = {(px[0] - p[0]) * sx, (px[1] - p[1]) * sx, (px[2] - p[2]) * sx};
      const float dv[3] = {(py[0] - p[0]) * sy, (py[1] - p[1]) * sy, (py[2] - p[2]) * sy};
      float nx = dh[1] * dv[2] - dh[2] * dv[1];
      float ny = dh[2] * dv[0] - dh[0] * dv[2];
      float nz = dh[0] * dv[1] - dh[1] * dv[0];
      const float len = std::sqrt(nx * nx + ny * ny + nz * nz);
      if (!(len > 1e-12f)) continue;
      nx /= len; ny /= len; nz /= len;
      const float vx = s_census_cam_pos[0] - p[0], vy = s_census_cam_pos[1] - p[1],
                  vz = s_census_cam_pos[2] - p[2];
      if (nx * vx + ny * vy + nz * vz < 0.0f) { nx = -nx; ny = -ny; nz = -nz; }
      s_geom.N[i * 3] = nx; s_geom.N[i * 3 + 1] = ny; s_geom.N[i * 3 + 2] = nz;
      s_geom.ok[i] = 2;
      s_geom.normal_px++;
    }
  }
  s_geom.key = key;
  s_geom.w = w;
  s_geom.h = h;
  return &s_geom;
}

constexpr int kEdgeSpan = 4;        // les deux normales sont prises a 4 px du pli : leurs
                                    // fenetres d'ajustement (rayon 1) ne se recouvrent pas
constexpr double kEdgeCosQual = 0.9063;   // 25 deg : en deca, ce n'est pas une arete
constexpr double kEdgeCosFlat = -0.9063;  // 155 deg : au dela, la surface se replie sur elle-meme
constexpr double kEdgeOpenRel = 0.02;     // marge du test de concavite, en fraction de l'ecart
constexpr int kEdgeMinPx = 3;             // une arete de moins de 3 px est du bruit de normale

HutEdge s_hut_edge[kCensusStates];
ContactRamp s_hutedge_ramp[kCensusStates];
ContactRamp s_hutedge_convex[kCensusStates];
ContactRamp s_hutedge_ref[kCensusStates];
std::vector<uint8_t> s_edge_mask;  // bit0 : concave axe +x, bit1 : concave axe +y,
                                   // bit2/bit3 : idem convexe
std::vector<uint8_t> s_ref_mask;   // les 425 px de l'essai 10, pour le seul recouvrement

// Le recensement d'aretes. MEME relecture et MEME test de pli que `contact_ramp()`, a une
// restriction pres qu'il faut nommer : seuls les pixels dont la NORMALE a pu etre ajustee
// entrent, donc pas la bordure de l'image ni les pixels qui touchent le ciel. `fold_sides` est
// ce denominateur-la, PAS `ao_ramp_sides` ; les deux se lisent cote a cote et leur ecart est la
// mesure de cette restriction. Ce qui s'ajoute ensuite est la QUALIFICATION par l'angle diedre
// et par le signe du repli.
void hut_edge_census(const uint8_t* ao,
                     const float* depth,
                     int w,
                     int h,
                     HutEdge* out,
                     ContactRamp* concave_ramp,
                     ContactRamp* convex_ramp,
                     ContactRamp* ref_ramp) {
  const CensusGeometry* geom = census_geometry(depth, w, h);
  if (!geom) return;
  // `HutEdge` decrit UNE image (une population, pas une somme) : il s'ECRASE. Le nombre
  // d'images qui l'ont alimente se lit a cote, dans `ao_census_frames_<etat>`. Les rampes, elles,
  // s'accumulent comme celles de l'essai 17 — ce sont des sommes de cotes.
  *out = HutEdge{};
  const double kCreaseRel = 0.25, kCreaseAbs = 1e-5, kJumpRel = 0.02;
  const size_t n = (size_t)w * (size_t)h;
  s_edge_mask.assign(n, 0);
  // La reference de l'essai 10, en carte : elle ne sert QU'A des temoins — le recouvrement, et
  // la rampe RESTREINTE au raccord que l'owner a photographie. Elle ne qualifie aucun pixel.
  const bool ref_frame = (w == ao_hut_edge_reference::kWidth &&
                          h == ao_hut_edge_reference::kHeight);
  if (ref_frame && s_ref_mask.size() != n) {
    s_ref_mask.assign(n, 0);
    for (const auto& p : ao_hut_edge_reference::kPixels)
      s_ref_mask[(size_t)p.y * (size_t)w + (size_t)p.x] = 1;
  }
  auto z = [&](int x, int y) -> double {
    return (double)depth[(size_t)y * (size_t)w + (size_t)x];
  };
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      const size_t i = (size_t)y * (size_t)w + (size_t)x;
      if (geom->ok[i] != 2) continue;
      const double z0 = z(x, y);
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        const double zm = z(x - dx, y - dy), zp = z(x + dx, y + dy);
        if (zm <= 1e-9 || zp <= 1e-9) continue;
        const double d1 = z0 - zm, d2 = zp - z0;
        if (std::max(std::fabs(d1), std::fabs(d2)) > kJumpRel * z0) continue;  // silhouette
        if (std::fabs(d2 - d1) <= kCreaseRel * (std::fabs(d1) + std::fabs(d2)) + kCreaseAbs)
          continue;  // pas un pli
        out->fold_sides++;
        const int xm = x - dx * kEdgeSpan, ym = y - dy * kEdgeSpan;
        const int xp = x + dx * kEdgeSpan, yp = y + dy * kEdgeSpan;
        if (xm < 0 || ym < 0 || xp >= w || yp >= h) continue;
        const size_t im = (size_t)ym * (size_t)w + (size_t)xm;
        const size_t ip = (size_t)yp * (size_t)w + (size_t)xp;
        if (geom->ok[im] != 2 || geom->ok[ip] != 2) continue;
        const float* nm = &geom->N[im * 3];
        const float* np = &geom->N[ip * 3];
        const float* pm = &geom->P[im * 3];
        const float* pp = &geom->P[ip * 3];
        const double cosine = (double)(nm[0] * np[0] + nm[1] * np[1] + nm[2] * np[2]);
        if (cosine > kEdgeCosQual || cosine < kEdgeCosFlat) continue;  // pas un diedre
        out->angled_sides++;
        // ── LE SIGNE DU REPLI, SANS PROJECTION ────────────────────────────────────────────
        // Sous une projection perspective, la profondeur de FENETRE est une fonction AFFINE des
        // coordonnees d'ecran sur tout plan (c'est le theoreme que `flat_step` exploite deja).
        // Sur les deux faces d'un pli, elle suit donc deux droites, et le pli est leur
        // intersection : sa position par rapport a la CORDE qui joint les deux echantillons
        // lointains donne le sens du repli, exactement, sans matrice. Reverse-Z (0 = le plus
        // loin) : un pli PLUS LOIN que la corde est un creux — un raccord CONCAVE.
        const double zspan_m = z(xm, ym), zspan_p = z(xp, yp);
        if (zspan_m <= 1e-9 || zspan_p <= 1e-9) continue;
        const double chord = 0.5 * (zspan_m + zspan_p) - z0;
        const double reach = std::fabs(zspan_p - zspan_m) + std::fabs(chord);
        if (!(reach > 0.0)) continue;
        const bool concave_depth = chord > kEdgeOpenRel * reach;
        const bool convex_depth = chord < -kEdgeOpenRel * reach;
        // Le MEME signe, lu dans le MONDE : chaque face voit-elle l'autre du cote de sa normale
        // sortante ? Deux instruments independants pour une seule grandeur — leur ACCORD est
        // publie (`ao_hutedge_sign_agree`), il n'est pas suppose.
        const double ex = pp[0] - pm[0], ey = pp[1] - pm[1], ez = pp[2] - pm[2];
        const double span = std::sqrt(ex * ex + ey * ey + ez * ez);
        const double margin = kEdgeOpenRel * span;
        const double am = nm[0] * ex + nm[1] * ey + nm[2] * ez;
        const double ap = -(np[0] * ex + np[1] * ey + np[2] * ez);
        const bool concave_world = span > 0.0 && am > margin && ap > margin;
        const bool convex_world = span > 0.0 && am < -margin && ap < -margin;
        if (concave_depth == concave_world && convex_depth == convex_world) out->sign_agree++;
        if (concave_depth) {
          s_edge_mask[i] |= (uint8_t)(1 << axis);
        } else if (convex_depth) {
          s_edge_mask[i] |= (uint8_t)(4 << axis);
        }
      }
    }
  }
  // Les cotes de rampe, sur CETTE population et sur son controle convexe. `ramp_side()` est
  // celle de l'essai 17, inchangee : elle confine la marche a la surface.
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      const uint8_t m = s_edge_mask[(size_t)y * (size_t)w + (size_t)x];
      if (!m) continue;
      if (m & 3) out->concave_px++;
      if (m & 12) out->convex_px++;
      for (int axis = 0; axis < 2; axis++) {
        const int dx = axis == 0 ? 1 : 0;
        const int dy = axis == 0 ? 0 : 1;
        if (m & (1 << axis)) {
          ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, -1, concave_ramp);
          ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, +1, concave_ramp);
          // ── LE RACCORD DE SA CAPTURE, ET LUI SEUL ─────────────────────────────────────
          // La population qualifiee couvre tout l'ecran : 2 124 aretes, dont celle de la
          // hutte. Un agregat sur 74 082 cotes ne peut pas dire si LE raccord qu'il montre
          // est encore clair — c'est la lecon des dix-sept essais precedents. Cette rampe-ci
          // est la MEME mesure, restreinte aux pixels detectes qui tombent dans les 425 px de
          // sa capture. Elle est un TEMOIN : elle ne qualifie rien et n'entre dans aucune
          // population de decision.
          if (ref_frame && s_ref_mask[(size_t)y * (size_t)w + (size_t)x]) {
            ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, -1, ref_ramp);
            ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, +1, ref_ramp);
          }
        }
        if (m & (4 << axis)) {
          ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, -1, convex_ramp);
          ramp_side(ao, depth, nullptr, w, h, x, y, dx, dy, +1, convex_ramp);
        }
      }
    }
  }
  // LES ARETES : les composantes connexes (4-voisinage) des pixels concaves. Une arete de moins
  // de `kEdgeMinPx` pixels est ecartee et le dit — c'est du bruit de normale, pas un raccord.
  std::vector<uint8_t> seen(n, 0);
  std::vector<int> stack;
  for (size_t i = 0; i < n; i++) {
    if (!(s_edge_mask[i] & 3) || seen[i]) continue;
    uint64_t size = 0;
    stack.clear();
    stack.push_back((int)i);
    seen[i] = 1;
    while (!stack.empty()) {
      const int c = stack.back();
      stack.pop_back();
      size++;
      const int cx = c % w, cy = c / w;
      const int nb[4][2] = {{cx - 1, cy}, {cx + 1, cy}, {cx, cy - 1}, {cx, cy + 1}};
      for (const auto& q : nb) {
        if (q[0] < 0 || q[1] < 0 || q[0] >= w || q[1] >= h) continue;
        const size_t j = (size_t)q[1] * (size_t)w + (size_t)q[0];
        if (seen[j] || !(s_edge_mask[j] & 3)) continue;
        seen[j] = 1;
        stack.push_back((int)j);
      }
    }
    if (size >= (uint64_t)kEdgeMinPx) {
      out->components++;
      if (size > out->largest) out->largest = size;
    }
  }
  // LE RECOUVREMENT AVEC L'ESSAI 10 — publie, jamais utilise pour decider. Une arete de
  // reference est RETROUVEE si l'un de ses deux pixels porte une detection sur le MEME axe.
  if (ref_frame) {
    for (const auto& e : ao_hut_edge_reference::kEdges) {
      const int dx = e.axis == 0 ? 1 : 0, dy = e.axis == 0 ? 0 : 1;
      const size_t a = (size_t)e.y * (size_t)w + (size_t)e.x;
      const size_t b = (size_t)(e.y + dy) * (size_t)w + (size_t)(e.x + dx);
      const uint8_t bit = (uint8_t)(1 << e.axis);
      if ((s_edge_mask[a] & bit) || (b < n && (s_edge_mask[b] & bit))) out->ref_edges_hit++;
    }
    for (const auto& p : ao_hut_edge_reference::kPixels) {
      const size_t i = (size_t)p.y * (size_t)w + (size_t)p.x;
      if (geom->ok[i]) out->ref_depth_px++;
      if (s_edge_mask[i] & 3) out->ref_px_hit++;
    }
    for (size_t i = 0; i < n; i++)
      if ((s_edge_mask[i] & 3) && s_ref_mask[i]) out->detected_in_ref++;
  }
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

  // ── (essai 15) CE QUE LA RESTAURATION DE CONTACT A REELLEMENT POSE, RELU SUR LE GPU ───────
  // Une relecture R8 de plus, dans la MEME image de recensement, sur la carte `g`. Sans elle la
  // preuve ne porterait qu'un compteur de passes — un miroir de la variable qui l'incremente.
  // Bras temoin : `s_contact_gterm_fbo` reste a 0, donc `ao_contact_g_frames` vaut 0 et les
  // quatre grandeurs aussi. La population est publiee a cote des comptes.
  if (s_contact_gterm_fbo != 0) {
    if (s_contact_buf.size() < n) {
      s_contact_buf.resize(n);
    }
    while (glGetError() != GL_NO_ERROR) {
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, s_contact_gterm_fbo);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RED, GL_UNSIGNED_BYTE, s_contact_buf.data());
    const GLenum gerr = glGetError();
    glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read_fbo);
    if (gerr == GL_NO_ERROR) {
      uint64_t px = 0, hi = 0, sum = 0, mx = 0;
      for (size_t i = 0; i < n; i++) {
        const uint8_t g = s_contact_buf[i];
        if (g) {
          px++;
          sum += g;
          if (g >= 64) {
            hi++;
          }
          if (g > mx) {
            mx = g;
          }
        }
      }
      s_contact_g_frames++;
      s_contact_g_pop += (uint64_t)n;
      s_contact_g_px += px;
      s_contact_g_hi_px += hi;
      s_contact_g_sum += sum;
      if (mx > s_contact_g_max) {
        s_contact_g_max = mx;
      }
    }
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
          // (essai 17) La MEME relecture sert la grandeur qui SAIT voir la rampe, et son temoin
          // de plan. Zero cout GL de plus, une passe CPU sur le tampon deja en memoire.
          contact_ramp(s_pat_buf.data(), s_depth_buf.data(), w, h, &s_contact_ramp[state],
                       &s_contact_plane[state]);
          // (essai 18, verdict H) Les aretes QUALIFIEES, sur la meme relecture : zero appel GL
          // de plus. La carte de positions/normales est partagee par les douze etats.
          hut_edge_census(s_pat_buf.data(), s_depth_buf.data(), w, h, &s_hut_edge[state],
                          &s_hutedge_ramp[state], &s_hutedge_convex[state],
                          &s_hutedge_ref[state]);
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
          // (terme 5, diagnostic) le MEME masque, seuil 0 : « ce texel a-t-il bouge du tout ».
          if (s_static_changed_x.size() < n) {
            s_static_changed_x.resize(n);
          }
          for (size_t i = 0; i < n; i++) {
            const double zn = (double)s_depth_buf[i];
            const double zo = (double)s_prev_depth[state][i];
            const bool sn = (zn <= 1e-9), so = (zo <= 1e-9);
            s_static_changed_x[i] = (sn && so) ? 0u : ((sn != so || zn != zo) ? 1u : 0u);
          }
          // ── LA BOITE DE CONFINEMENT : 0,10 EN UV, ET CE N'EST PAS UN REGLAGE ───────────
          // C'est la borne que GTAO et HBAO se donnent sur leur MARCHE D'HORIZON :
          // `screen_r = clamp(screen_r, 2.0*max(px.x,px.y), 0.10)`, en unites UV.
          // ATTENTION — CE N'EST UNE GARANTIE POUR AUCUN DES TROIS ESTIMATEURS, et l'essai 3 l'a
          // chiffre. Les trois portent EN PLUS un noyau hemispherique MONDE de rayon 5120 qui
          // n'est pas plafonne a l'ecran (SSAO directement, GTAO et HBAO par `broad_occ`, arme
          // en jeu par `u_broad`) : sur la vue de la hutte il porte a 157 px en x et 137 px en y,
          // contre les 80 x 60 de cette boite. Et la boite n'a jamais compte AUCUNE des passes
          // qui suivent l'estimateur — le flou porte a lui seul 48 px a la qualite Basse.
          // Cette boite-ci reste donc ce qu'elle est : le garde LACHE, publie sous
          // `ao_static_loose_*` et qu'AUCUN terme ne lit plus. Le terme 5 lit le garde de la
          // portee reelle, calcule pixel par pixel un peu plus bas.
          const int rx = (int)std::ceil(0.10 * (double)w);
          const int ry = (int)std::ceil(0.10 * (double)h);
          s_static_guard_rx = (uint64_t)rx;
          s_static_guard_ry = (uint64_t)ry;
          // ══ LA PORTEE REELLE D'UN TEXEL D'AO, ET POURQUOI ELLE N'EST PAS 0,10 UV ═══════════
          // Le commentaire ci-dessus est FAUX et la mesure de l'essai 3 le montre : le plafond
          // `clamp(screen_r, …, 0.10)` ne borne QUE la marche d'horizon de GTAO et HBAO. Les
          // trois estimateurs portent EN PLUS un noyau hemispherique MONDE, non plafonne a
          // l'ecran :
          //   . SSAO : `sp = P + N*0,02*R + dir*R`, R = 5120 (ao_ssao.frag:167 ; u_radius,
          //     AmbientOcclusion.cpp, case 1) ;
          //   . GTAO et HBAO : le MEME noyau par `broad_occ`, `BR = 5120` (ao_gtao.frag:71,85 et
          //     ao_hbao.frag), arme EN JEU par `u_broad` (jamais nul pour les modes 2 et 3).
          // Le texel lit donc une BOULE MONDE de rayon 1,02*5120 — et le rapport monde/pixel va
          // en 1/D. Une boite fixe est soit trop petite au premier plan (157 px mesures sur la
          // vue de la hutte contre 80), soit absurde au fond, ou elle mangerait la population
          // entiere. On convertit donc la boule PIXEL PAR PIXEL, avec la MEME deprojection que
          // les shaders (`census_world`), en mesurant ce que vaut UN pixel en unites monde a la
          // profondeur de CE texel. Aucun reglage : deux constantes du code et une projection.
          // S'y ajoute ce que la chaine AVAL propage, en pixels d'ecran :
          //   . le flou, 2·Σ strides / scale  (kBlurStrides {1,2,3,5}, nboxes 4 a la qualite
          //     Elevee et 3 sinon) : 22 px en pleine resolution, 24 a demi, 48 au quart ;
          //   . la passe de crete, 4 passes de ±1 texel pleine resolution ;
          //   . la carte de contact, ±(kContactRadius+1) puis une tente ±2 : ±8 px.
          const int q_state = state % 3;
          const int sum_strides = (q_state == 2) ? (1 + 2 + 3 + 5) : (1 + 2 + 3);
          const uint64_t q_milli =
              s_scale_q_x1000[q_state] ? s_scale_q_x1000[q_state]
                                       : (q_state == 0 ? 250ull : q_state == 1 ? 500ull : 1000ull);
          const int blur_px = (int)std::ceil(2000.0 * (double)sum_strides / (double)q_milli);
          const int chain_px = blur_px + 4 /* crete, 4 passes de ±1 */ + 8 /* carte de contact */;
          constexpr float kAoWorldReach = 1.02f * 5120.f;  // le plus grand |sp - P| des trois
          // `s_static_box_rx/ry` gardent le PLUS GRAND rayon exige sur TOUTE la course : les
          // remettre a `chain_px` a chaque paire ne publierait que la derniere.
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
          // (terme 5, diagnostic) la MEME table de surface, sur le masque sans seuil.
          if (s_static_sat_x.size() < sw * sh) {
            s_static_sat_x.resize(sw * sh);
          }
          for (size_t x = 0; x < sw; x++) {
            s_static_sat_x[x] = 0;
          }
          for (int y = 0; y < h; y++) {
            uint32_t row = 0;
            const size_t o0 = (size_t)(y + 1) * sw;
            const size_t om = (size_t)y * sw;
            s_static_sat_x[o0] = 0;
            for (int x = 0; x < w; x++) {
              row += (uint32_t)s_static_changed_x[(size_t)y * (size_t)w + (size_t)x];
              s_static_sat_x[o0 + (size_t)x + 1] = s_static_sat_x[om + (size_t)x + 1] + row;
            }
          }
          auto box_changed_x = [&](int x, int y) -> uint32_t {
            const int x0 = std::max(0, x - rx), y0 = std::max(0, y - ry);
            const int x1 = std::min(w - 1, x + rx), y1 = std::min(h - 1, y + ry);
            return s_static_sat_x[(size_t)(y1 + 1) * sw + (size_t)(x1 + 1)] -
                   s_static_sat_x[(size_t)y0 * sw + (size_t)(x1 + 1)] -
                   s_static_sat_x[(size_t)(y1 + 1) * sw + (size_t)x0] +
                   s_static_sat_x[(size_t)y0 * sw + (size_t)x0];
          };
          auto box_changed_x_w = [&](int x, int y, int brx, int bry) -> uint32_t {
            const int x0 = std::max(0, x - brx), y0 = std::max(0, y - bry);
            const int x1 = std::min(w - 1, x + brx), y1 = std::min(h - 1, y + bry);
            return s_static_sat_x[(size_t)(y1 + 1) * sw + (size_t)(x1 + 1)] -
                   s_static_sat_x[(size_t)y0 * sw + (size_t)(x1 + 1)] -
                   s_static_sat_x[(size_t)(y1 + 1) * sw + (size_t)x0] +
                   s_static_sat_x[(size_t)y0 * sw + (size_t)x0];
          };
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
              // ── (terme 5) LE GARDE DE LA CHAINE ENTIERE ────────────────────────────────
              // Il se compte AVANT le `continue` du garde LACHE : sinon le terme serait un
              // SOUS-ENSEMBLE d'une population que le seuil de 4 quanta a deja rabotee, et
              // son zero dependrait du seuil qu'il est justement cense ne plus porter.
              int brx = 0, bry = 0;
              if (zn == zo && s_census_cam_valid) {
                // UN pixel, en unites monde, A CETTE PROFONDEUR : la deprojection du voisin
                // immediat AU MEME z. Pas de matrice avant a connaitre, pas de focale supposee.
                float pc[3], pxn[3], pyn[3];
                census_world(x, y, w, h, (float)zn, pc);
                census_world(x + 1, y, w, h, (float)zn, pxn);
                census_world(x, y + 1, w, h, (float)zn, pyn);
                const float ux = std::sqrt((pxn[0] - pc[0]) * (pxn[0] - pc[0]) +
                                           (pxn[1] - pc[1]) * (pxn[1] - pc[1]) +
                                           (pxn[2] - pc[2]) * (pxn[2] - pc[2]));
                const float uy = std::sqrt((pyn[0] - pc[0]) * (pyn[0] - pc[0]) +
                                           (pyn[1] - pc[1]) * (pyn[1] - pc[1]) +
                                           (pyn[2] - pc[2]) * (pyn[2] - pc[2]));
                brx = (ux > 1e-4f) ? (int)std::ceil(kAoWorldReach / ux) : w;
                bry = (uy > 1e-4f) ? (int)std::ceil(kAoWorldReach / uy) : h;
                brx = std::min(brx, w) + chain_px;
                bry = std::min(bry, h) + chain_px;
                if ((uint64_t)brx > s_static_box_rx[state]) {
                  s_static_box_rx[state] = (uint64_t)brx;
                }
                if ((uint64_t)bry > s_static_box_ry[state]) {
                  s_static_box_ry[state] = (uint64_t)bry;
                }
              }
              if (zn == zo && s_census_cam_valid && box_changed_x_w(x, y, brx, bry) == 0) {
                s_static_pop_w[state]++;
                if (ao_moved) {
                  s_static_moved_w_gt2[state]++;
                }
                if (d != 0) {
                  s_static_moved_w_any[state]++;
                  const uint64_t adw = (uint64_t)(d < 0 ? -d : d);
                  // Le bras LIVRE seulement : `ao_static_moved_worst_state` valait 17, c'est-a-
                  // dire `legacy_hbao_q2` — le « texel a regarder » designait le TEMOIN, pas le
                  // defaut que la porte compte.
                  if (state < 9 && adw > s_static_w_worst_ao) {
                    s_static_w_worst_ao = adw;
                    s_static_w_worst_x = (uint64_t)x;
                    s_static_w_worst_y = (uint64_t)y;
                    s_static_w_worst_state = (uint64_t)state;
                  }
                }
              }
              if (box_changed(x, y) != 0) {
                continue;  // un occluder a bouge assez pres : l'AO a le DROIT de changer
              }
              spop++;
              // (terme 5, diagnostic) LE MEME TEXEL SOUS UN GARDE SANS SEUIL. La condition est
              // strictement plus severe que celle au-dessus : `zn == zo` implique
              // `|zn - zo| <= kSameGeom`, et une boite vide au seuil 0 implique une boite vide
              // au seuil de 4 quanta. Cette population est donc un SOUS-ENSEMBLE de `spop`, et
              // le rapport des deux dit ce que le seuil laisse passer.
              if (zn == zo && box_changed_x(x, y) == 0) {
                s_static_pop_x[state]++;
                if (ao_moved) {
                  s_static_moved_x[state]++;
                }
              }
              if (ao_moved) {
                smoved++;
                // (terme 5, diagnostic) CE QUI A BOUGE MALGRE TOUT, sans seuil de profondeur.
                if (box_changed_x(x, y) != 0) {
                  s_static_moved_near_any++;
                }
                if (zn != zo) {
                  s_static_moved_self_dz++;
                }
                const uint64_t ad = (uint64_t)(d < 0 ? -d : d);
                if (ad > s_static_moved_worst_ao) {
                  s_static_moved_worst_ao = ad;
                  s_static_moved_worst_x = (uint64_t)x;
                  s_static_moved_worst_y = (uint64_t)y;
                  s_static_moved_worst_state = (uint64_t)state;
                  s_static_moved_worst_dzq =
                      (uint64_t)(std::fabs(zn - zo) * 16777215.0 + 0.5);
                }
              }
            }
          }
          s_static_pairs++;
          if (s_census_wind_cut && s_prev_wind_cut[state] != 0) {
            s_static_pairs_wind_cut++;
          }
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
    s_prev_wind_cut[state] = s_census_wind_cut ? 1u : 0u;
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

void AmbientOcclusionPass::set_arch_terms(uint64_t indirect_hit_px,
                                          uint64_t probe_px,
                                          uint64_t luma_mask_sites,
                                          uint64_t switch_readers,
                                          uint64_t programs_queried) {
  s_arch_indirect_hit_px = indirect_hit_px;
  s_arch_probe_px = probe_px;
  s_arch_luma_mask_sites = luma_mask_sites;
  s_arch_switch_readers = switch_readers;
  s_arch_programs_queried = programs_queried;
}

void AmbientOcclusionPass::set_census_wind_cut(bool cut) {
  s_census_wind_cut = cut;
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
    // (essai 17) La RAMPE, et le plan qui lui sert de zero — chacun avec son denominateur.
    autoport_proof::publish(("ao_ramp_sides_" + n).c_str(), s_contact_ramp[i].sides);
    autoport_proof::publish(("ao_ramp_positive_" + n).c_str(), s_contact_ramp[i].positive);
    autoport_proof::publish(("ao_ramp_bright_" + n).c_str(), s_contact_ramp[i].bright);
    autoport_proof::publish(("ao_ramp_rejected_" + n).c_str(), s_contact_ramp[i].rejected);
    autoport_proof::publish(("ao_plane_sides_" + n).c_str(), s_contact_plane[i].sides);
    autoport_proof::publish(("ao_plane_positive_" + n).c_str(), s_contact_plane[i].positive);
    autoport_proof::publish(("ao_plane_rejected_" + n).c_str(), s_contact_plane[i].rejected);
    autoport_proof::publish(("ao_static_pop_" + n).c_str(), s_static_pop[i]);
    autoport_proof::publish(("ao_static_moved_" + n).c_str(), s_static_moved[i]);
    // Les deux populations restent SEPAREES par etat : guardee (confinee a la causalite) et
    // non guardee (la definition de l'essai 9).
    autoport_proof::publish(("ao_static_unguarded_pop_" + n).c_str(), s_static_pop_ug[i]);
    autoport_proof::publish(("ao_static_unguarded_moved_" + n).c_str(), s_static_moved_ug[i]);
    if (s_flat_pop[i]) {
      if (i < 9) {
        worst_flat_delivered = std::max(worst_flat_delivered, flat);
      } else {
        worst_flat_legacy = std::max(worst_flat_legacy, flat);
      }
    }
    if (s_census_frames[i]) {
      if (i < 9) {
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
  // (terme 5, essai 3) LE GARDE DE LA CHAINE ENTIERE, agrege par bras.
  uint64_t chain_pop = 0, chain_any = 0, chain_gt2 = 0;
  uint64_t chain_pop_leg = 0, chain_any_leg = 0, chain_gt2_leg = 0;
  for (int i = 0; i < kCensusStates; i++) {
    if (i < 9) {
      chain_pop += s_static_pop_w[i];
      chain_any += s_static_moved_w_any[i];
      chain_gt2 += s_static_moved_w_gt2[i];
    } else {
      chain_pop_leg += s_static_pop_w[i];
      chain_any_leg += s_static_moved_w_any[i];
      chain_gt2_leg += s_static_moved_w_gt2[i];
    }
    if (i < 9) {
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

  // ── (essai 17) LA RAMPE DE CONTACT, ET LE PLAN QUI EN DONNE LE ZERO ──────────────────────
  // `ao_contact_band_px` ci-dessus reste la CRETE historique — elle ne sait voir qu'un pic d'un
  // pixel, et le banc local prouve qu'elle rend 0 sur le tampon d'AO appareil qui PORTE le
  // defaut. Elle n'est pas retiree (aucune grandeur publiee ne se redefinit en silence) ; la
  // grandeur qui REPOND a l'owner est publiee A COTE, avec son temoin de plan et ses deux
  // denominateurs. L'EXCES des plis sur le plan est le defaut : sur un plan il n'y a pas de
  // contact, donc pas de bande — ce qu'on y lit est le bruit de l'estimateur, dans la MEME image.
  {
    ContactRamp fold_on{}, fold_off{}, plane_on{}, plane_off{};
    auto add = [](ContactRamp& dst, const ContactRamp& src) {
      dst.sides += src.sides;
      dst.positive += src.positive;
      dst.bright += src.bright;
      dst.lift_pos += src.lift_pos;
      dst.lift_neg += src.lift_neg;
      dst.rejected += src.rejected;
    };
    for (int i = 0; i < kCensusStates; i++) {
      add(i < 9 ? fold_on : fold_off, s_contact_ramp[i]);
      add(i < 9 ? plane_on : plane_off, s_contact_plane[i]);
    }
    auto rate = [](const ContactRamp& r) -> uint64_t {
      return r.sides ? (1000ull * r.bright / r.sides) : 0ull;
    };
    auto prate = [](const ContactRamp& r) -> uint64_t {
      return r.sides ? (1000ull * r.positive / r.sides) : 0ull;
    };
    auto publish_arm = [&](const char* suffix, const ContactRamp& f, const ContactRamp& p) {
      const std::string s = suffix;
      autoport_proof::publish(("ao_ramp_sides" + s).c_str(), f.sides);
      autoport_proof::publish(("ao_ramp_rejected" + s).c_str(), f.rejected);
      autoport_proof::publish(("ao_ramp_positive" + s).c_str(), f.positive);
      autoport_proof::publish(("ao_ramp_positive_rate" + s + "_x1000").c_str(), prate(f));
      autoport_proof::publish(("ao_ramp_bright" + s).c_str(), f.bright);
      autoport_proof::publish(("ao_ramp_bright_rate" + s + "_x1000").c_str(), rate(f));
      autoport_proof::publish(("ao_ramp_lift_up" + s + "_milli").c_str(),
                              f.sides ? f.lift_pos / f.sides : 0ull);
      autoport_proof::publish(("ao_ramp_lift_down" + s + "_milli").c_str(),
                              f.sides ? f.lift_neg / f.sides : 0ull);
      autoport_proof::publish(("ao_plane_sides" + s).c_str(), p.sides);
      autoport_proof::publish(("ao_plane_rejected" + s).c_str(), p.rejected);
      autoport_proof::publish(("ao_plane_positive" + s).c_str(), p.positive);
      autoport_proof::publish(("ao_plane_positive_rate" + s + "_x1000").c_str(), prate(p));
      autoport_proof::publish(("ao_plane_bright" + s).c_str(), p.bright);
      autoport_proof::publish(("ao_plane_bright_rate" + s + "_x1000").c_str(), rate(p));
      autoport_proof::publish(("ao_plane_lift_up" + s + "_milli").c_str(),
                              p.sides ? p.lift_pos / p.sides : 0ull);
      autoport_proof::publish(("ao_plane_lift_down" + s + "_milli").c_str(),
                              p.sides ? p.lift_neg / p.sides : 0ull);
      // L'EXCES, dans les deux sens : un contact CORRECT est plus SOMBRE qu'un plan, donc
      // `deficit > 0` et `excess == 0`. Publier les deux interdit de perdre le SIGNE.
      const uint64_t rf = rate(f), rp = rate(p);
      autoport_proof::publish(("ao_contact_bright_excess" + s + "_x1000").c_str(),
                              rf > rp ? rf - rp : 0ull);
      autoport_proof::publish(("ao_contact_bright_deficit" + s + "_x1000").c_str(),
                              rp > rf ? rp - rf : 0ull);
      const uint64_t pf = prate(f), pp = prate(p);
      autoport_proof::publish(("ao_contact_positive_excess" + s + "_x1000").c_str(),
                              pf > pp ? pf - pp : 0ull);
      autoport_proof::publish(("ao_contact_positive_deficit" + s + "_x1000").c_str(),
                              pp > pf ? pp - pf : 0ull);
      const int64_t lf = f.sides ? (int64_t)(f.lift_pos / f.sides) - (int64_t)(f.lift_neg / f.sides) : 0;
      const int64_t lp = p.sides ? (int64_t)(p.lift_pos / p.sides) - (int64_t)(p.lift_neg / p.sides) : 0;
      autoport_proof::publish(("ao_contact_lift_excess" + s + "_milli").c_str(),
                              lf > lp ? (uint64_t)(lf - lp) : 0ull);
      autoport_proof::publish(("ao_contact_lift_deficit" + s + "_milli").c_str(),
                              lp > lf ? (uint64_t)(lp - lf) : 0ull);
      autoport_proof::publish(("ao_ramp_measured" + s).c_str(),
                              (f.sides > 0 && p.sides > 0) ? 1ull : 0ull);
    };
    publish_arm("", fold_on, plane_on);
    publish_arm("_legacy", fold_off, plane_off);
    autoport_proof::publish("ao_ramp_near_taps", (uint64_t)kRampNear);
    autoport_proof::publish("ao_ramp_far_taps", (uint64_t)(kRampLen - kRampFar0));
    autoport_proof::publish("ao_ramp_bright_threshold", (uint64_t)kRampBright);
    autoport_proof::publish("ao_plane_stride", (uint64_t)kPlaneStride);
    autoport_proof::publish("ao_plane_radius", (uint64_t)kPlaneRadius);
    autoport_proof::publish("ao_plane_mask_px", s_plane_mask_px);
  }

  // ── (essai 18, verdict H) LES ARETES QUALIFIEES, ET CE QUE L'AO Y FAIT ────────────────────
  // La population de l'owner, trouvee PAR LE MOTEUR : un pli de profondeur dont les deux faces,
  // deprojetees en monde, forment un diedre d'au moins 25 degres, et dont le repli est
  // CONCAVE. Le recouvrement avec les 15 aretes / 425 px de l'essai 10 est publie A COTE : il
  // juge le detecteur, il ne le guide pas.
  //
  // TROIS POPULATIONS DANS LA MEME IMAGE, pour qu'aucun zero ne soit muet :
  //   concave  — le raccord ; c'est la que l'AO doit CREUSER, et la que l'owner voit du blanc ;
  //   convexe  — le controle gratuit : meme detecteur, signe oppose, l'AO n'y doit rien ;
  //   plan     — le zero de l'instrument, deja mesure par `ao_plane_*` dans la MEME image.
  {
    HutEdge edge_on{}, edge_off{};
    ContactRamp cc_on{}, cc_off{}, cx_on{}, cx_off{}, plane_on{}, plane_off{};
    ContactRamp rf_on{}, rf_off{};
    auto addr = [](ContactRamp& dst, const ContactRamp& src) {
      dst.sides += src.sides; dst.positive += src.positive; dst.bright += src.bright;
      dst.lift_pos += src.lift_pos; dst.lift_neg += src.lift_neg; dst.rejected += src.rejected;
    };
    auto adde = [](HutEdge& dst, const HutEdge& src) {
      dst.fold_sides += src.fold_sides; dst.angled_sides += src.angled_sides;
      dst.concave_px += src.concave_px; dst.convex_px += src.convex_px;
      dst.sign_agree += src.sign_agree;
      dst.components += src.components;
      if (src.largest > dst.largest) dst.largest = src.largest;
      if (src.ref_depth_px > dst.ref_depth_px) dst.ref_depth_px = src.ref_depth_px;
      if (src.ref_edges_hit > dst.ref_edges_hit) dst.ref_edges_hit = src.ref_edges_hit;
      if (src.ref_px_hit > dst.ref_px_hit) dst.ref_px_hit = src.ref_px_hit;
      if (src.detected_in_ref > dst.detected_in_ref) dst.detected_in_ref = src.detected_in_ref;
    };
    for (int i = 0; i < kCensusStates; i++) {
      adde(i < 9 ? edge_on : edge_off, s_hut_edge[i]);
      addr(i < 9 ? cc_on : cc_off, s_hutedge_ramp[i]);
      addr(i < 9 ? cx_on : cx_off, s_hutedge_convex[i]);
      addr(i < 9 ? rf_on : rf_off, s_hutedge_ref[i]);
      addr(i < 9 ? plane_on : plane_off, s_contact_plane[i]);
    }
    auto rate = [](const ContactRamp& r) -> uint64_t {
      return r.sides ? (1000ull * r.bright / r.sides) : 0ull;
    };
    auto lift = [](const ContactRamp& r) -> int64_t {
      return r.sides ? (int64_t)(r.lift_pos / r.sides) - (int64_t)(r.lift_neg / r.sides) : 0;
    };
    auto arm = [&](const char* suffix, const HutEdge& e, const ContactRamp& cc,
                   const ContactRamp& cx, const ContactRamp& pl, const ContactRamp& rf) {
      const std::string t = suffix;
      autoport_proof::publish(("ao_hutedge_fold_sides" + t).c_str(), e.fold_sides);
      autoport_proof::publish(("ao_hutedge_angled_sides" + t).c_str(), e.angled_sides);
      autoport_proof::publish(("ao_hutedge_sign_agree" + t).c_str(), e.sign_agree);
      autoport_proof::publish(("ao_hutedge_concave_px" + t).c_str(), e.concave_px);
      autoport_proof::publish(("ao_hutedge_convex_px" + t).c_str(), e.convex_px);
      autoport_proof::publish(("ao_hutedge_edges" + t).c_str(), e.components);
      autoport_proof::publish(("ao_hutedge_largest_px" + t).c_str(), e.largest);
      // LE RECOUVREMENT AVEC L'ESSAI 10, terme par terme et avec ses DEUX denominateurs.
      autoport_proof::publish(("ao_hutedge_ref_edges" + t).c_str(),
                              (uint64_t)ao_hut_edge_reference::kEdges.size());
      autoport_proof::publish(("ao_hutedge_ref_edges_hit" + t).c_str(), e.ref_edges_hit);
      autoport_proof::publish(("ao_hutedge_ref_overlap" + t + "_x1000").c_str(),
                              1000ull * e.ref_edges_hit / ao_hut_edge_reference::kEdges.size());
      autoport_proof::publish(("ao_hutedge_ref_px" + t).c_str(),
                              (uint64_t)ao_hut_edge_reference::kPixels.size());
      autoport_proof::publish(("ao_hutedge_ref_px_hit" + t).c_str(), e.ref_px_hit);
      autoport_proof::publish(("ao_hutedge_detected_in_ref" + t).c_str(), e.detected_in_ref);
      // LE TEMOIN DE CAMERA. Les 425 px ont ete releves a l'image logique 600, le recensement
      // mesure vers 1380. Si la camera avait bouge, ces pixels ne porteraient plus de surface :
      // ce compte le CHIFFRE au lieu de le supposer.
      autoport_proof::publish(("ao_hutedge_ref_depth_px" + t).c_str(), e.ref_depth_px);
      // CE QUE L'AO FAIT SUR CHAQUE POPULATION. `bright_rate` = part des cotes dont le contact
      // est plus CLAIR que le fond de la meme surface, de 4/255 ; `lift` = la levee moyenne
      // signee, en milli-quanta. Un contact CORRECT est plus SOMBRE : levee negative.
      autoport_proof::publish(("ao_hutedge_ramp_sides" + t).c_str(), cc.sides);
      autoport_proof::publish(("ao_hutedge_ramp_rejected" + t).c_str(), cc.rejected);
      autoport_proof::publish(("ao_hutedge_ramp_bright" + t).c_str(), cc.bright);
      autoport_proof::publish(("ao_hutedge_ramp_bright_rate" + t + "_x1000").c_str(), rate(cc));
      autoport_proof::publish(("ao_hutedge_ramp_lift_up" + t + "_milli").c_str(),
                              cc.sides ? cc.lift_pos / cc.sides : 0ull);
      autoport_proof::publish(("ao_hutedge_ramp_lift_down" + t + "_milli").c_str(),
                              cc.sides ? cc.lift_neg / cc.sides : 0ull);
      autoport_proof::publish(("ao_hutedge_convex_sides" + t).c_str(), cx.sides);
      autoport_proof::publish(("ao_hutedge_convex_bright_rate" + t + "_x1000").c_str(), rate(cx));
      autoport_proof::publish(("ao_hutedge_plane_sides" + t).c_str(), pl.sides);
      autoport_proof::publish(("ao_hutedge_plane_bright_rate" + t + "_x1000").c_str(), rate(pl));
      // L'EXCES SUR LE PLAN : sur un plan il n'y a pas de contact, donc pas de bande. Ce qu'on y
      // lit est le bruit de l'estimateur, dans la MEME image. Le defaut est l'EXCES.
      const uint64_t rc = rate(cc), rp = rate(pl);
      autoport_proof::publish(("ao_hutedge_bright_excess" + t + "_x1000").c_str(),
                              rc > rp ? rc - rp : 0ull);
      autoport_proof::publish(("ao_hutedge_bright_deficit" + t + "_x1000").c_str(),
                              rp > rc ? rp - rc : 0ull);
      const int64_t lc = lift(cc), lp = lift(pl);
      autoport_proof::publish(("ao_hutedge_lift_excess" + t + "_milli").c_str(),
                              lc > lp ? (uint64_t)(lc - lp) : 0ull);
      autoport_proof::publish(("ao_hutedge_lift_deficit" + t + "_milli").c_str(),
                              lp > lc ? (uint64_t)(lp - lc) : 0ull);
      // ── LE RACCORD DE LA CAPTURE DE L'OWNER, NOMME ────────────────────────────────────
      // Les memes cotes, restreints aux pixels detectes qui tombent dans ses 425 px. C'est la
      // seule grandeur de cette preuve qui reponde a sa phrase — « on voit un peu de blanc non
      // ombre du mur pile entre le mur et le toit » — sur SON raccord et pas sur une moyenne
      // d'ecran. `sides` est son denominateur : s'il est nul, la grandeur est MUETTE, pas verte.
      autoport_proof::publish(("ao_hutedge_ref_ramp_sides" + t).c_str(), rf.sides);
      autoport_proof::publish(("ao_hutedge_ref_ramp_rejected" + t).c_str(), rf.rejected);
      autoport_proof::publish(("ao_hutedge_ref_ramp_bright" + t).c_str(), rf.bright);
      autoport_proof::publish(("ao_hutedge_ref_ramp_bright_rate" + t + "_x1000").c_str(), rate(rf));
      autoport_proof::publish(("ao_hutedge_ref_ramp_lift_up" + t + "_milli").c_str(),
                              rf.sides ? rf.lift_pos / rf.sides : 0ull);
      autoport_proof::publish(("ao_hutedge_ref_ramp_lift_down" + t + "_milli").c_str(),
                              rf.sides ? rf.lift_neg / rf.sides : 0ull);
      autoport_proof::publish(("ao_hutedge_ref_ramp_measured" + t).c_str(),
                              rf.sides > 0 ? 1ull : 0ull);
      autoport_proof::publish(("ao_hutedge_measured" + t).c_str(),
                              (e.fold_sides > 0 && cc.sides > 0 && pl.sides > 0) ? 1ull : 0ull);
    };
    arm("", edge_on, cc_on, cx_on, plane_on, rf_on);
    arm("_legacy", edge_off, cc_off, cx_off, plane_off, rf_off);
    // (m) LE CONTRAT DEMANDE CHAQUE MODE ET CHAQUE QUALITE, PAS UNE MOYENNE : « un mode ou une
    // qualite non mesure compte 1 ». Les agregats ci-dessus restent ; ils ne disent pas LEQUEL
    // des neuf couples porte la bande claire que l'owner voit.
    for (int i = 0; i < kCensusStates; i++) {
      arm((std::string("_") + kCensusName[i]).c_str(), s_hut_edge[i], s_hutedge_ramp[i],
          s_hutedge_convex[i], s_contact_plane[i], s_hutedge_ref[i]);
    }
    autoport_proof::publish("ao_hutedge_span_px", (uint64_t)kEdgeSpan);
    autoport_proof::publish("ao_hutedge_cos_qual_x1000", (uint64_t)(kEdgeCosQual * 1000.0));
    autoport_proof::publish("ao_hutedge_min_px", (uint64_t)kEdgeMinPx);
    autoport_proof::publish("ao_hutedge_open_rel_x1000", (uint64_t)(kEdgeOpenRel * 1000.0));
    autoport_proof::publish("ao_hutedge_cam_valid", s_census_cam_valid ? 1ull : 0ull);
    autoport_proof::publish("ao_hutedge_surface_px", s_geom.surface_px);
    autoport_proof::publish("ao_hutedge_normal_px", s_geom.normal_px);
    autoport_proof::publish("ao_hutedge_geom_w", (uint64_t)s_geom.w);
    autoport_proof::publish("ao_hutedge_geom_h", (uint64_t)s_geom.h);
  }

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
  // essai 16 : LA PREMISSE EST UNE CONDITION, PLUS UNE INTENTION. Trois faits, tous exigibles,
  // chacun publie a cote pour qu'un lecteur puisse les contredire un par un :
  //   . la population guardee est non vide — si le confinement mange tout, il n'y a rien a lire ;
  //   . CHAQUE paire jugee a eu le vent COUPE sur ses DEUX images (contrat (k) : « camera
  //     immobile, scene immobile, vent COUPE pour la mesure »). Jusqu'a l'essai 15 la course de
  //     l'item PARENT n'en coupait AUCUNE : `g_census_witness` n'est arme que sous
  //     `ao_static_probe::active()`, qui ne nomme que les deux items ENFANTS. Le terme etait
  //     mesure sous un regime que son propre contrat interdit, et personne ne le voyait ;
  //   . quelque chose a BOUGE quelque part dans cette course — le bras temoin (l'ancrage MONDE
  //     du bruit d'avant) ou la population NON guardee du bras livre. Les deux a zero, la scene
  //     entiere etait figee et le zero du terme est un vert par INACTION, pas une mesure.
  const bool wind_premise =
      exact_static_probe() || (s_static_pairs > 0 && s_static_pairs_wind_cut == s_static_pairs);
  const bool motion_seen = exact_static_probe() || (static_legacy > 0) || (static_moved_ug > 0);
  // ═══ (terme 5, essai 3) CE QUE LA PORTE LIT CHANGE, ET CA S'ECRIT ═══════════════════════
  // Jusqu'a l'essai 2 le terme lisait `static_moved` : le garde LACHE (profondeur a 4 quanta
  // pres, boite de 0,10 UV). Mesure de l'essai 2, course appareil : 14 191 des 14 195 texels
  // comptes par les deux bras avaient un voisin de la boite qui avait bouge SANS AUCUN SEUIL.
  // Le terme mesurait la tolerance de son propre garde. Il lit desormais le garde EXACT etendu
  // a la portee reelle de la chaine (`s_static_*_w`, declaration ci-dessus), avec zero seuil
  // d'ecart d'AO. L'ancienne grandeur n'est PAS retiree : elle est republiee sous
  // `ao_static_loose_*`, avec son denominateur, pour que les cinq courses de l'essai 2 restent
  // comparables et que personne n'ait a deviner ce qui a change.
  const bool probe5 = exact_static_probe();
  const uint64_t term5_moved = probe5 ? static_moved : chain_any;
  const uint64_t term5_pop = probe5 ? static_pop : chain_pop;
  const uint64_t term5_legacy = probe5 ? static_legacy : chain_any_leg;
  const bool static_measured = (term5_pop > 0) && wind_premise && motion_seen;
  autoport_proof::publish("ao_static_loose_delta_px", static_moved);
  autoport_proof::publish("ao_static_loose_pop_px", static_pop);
  autoport_proof::publish("ao_static_loose_legacy_px", static_legacy);
  autoport_proof::publish("ao_static_chain_gt2_px", chain_gt2);
  autoport_proof::publish("ao_static_chain_legacy_gt2_px", chain_gt2_leg);
  autoport_proof::publish("ao_static_chain_legacy_pop_px", chain_pop_leg);
  autoport_proof::publish("ao_static_chain_worst_ao", s_static_w_worst_ao);
  autoport_proof::publish("ao_static_chain_worst_x", s_static_w_worst_x);
  autoport_proof::publish("ao_static_chain_worst_y", s_static_w_worst_y);
  autoport_proof::publish("ao_static_chain_worst_state", s_static_w_worst_state);
  // Les deux constantes du code dont la boite descend, publiees pour qu'on puisse la refaire :
  // le rayon monde des noyaux hemispheriques, et le fait que la camera etait relue.
  autoport_proof::publish("ao_static_chain_world_reach", (uint64_t)(1.02 * 5120.0));
  autoport_proof::publish("ao_static_chain_cam_valid", s_census_cam_valid ? 1ull : 0ull);
  // PAR ETAT : sans ca, « 4 texels bougent » ne dit pas QUEL couple (mode, qualite) les porte,
  // et le correctif suivant vise au hasard. Le rayon de boite retenu par etat est publie avec.
  for (int i = 0; i < kCensusStates; i++) {
    const std::string sfx = std::string("_") + kCensusName[i];
    autoport_proof::publish(("ao_static_chain_pop_px" + sfx).c_str(), s_static_pop_w[i]);
    autoport_proof::publish(("ao_static_chain_moved_px" + sfx).c_str(), s_static_moved_w_any[i]);
    // Le PLUS GRAND rayon de garde qu'un texel de cet etat ait exige (pixels d'ecran) : la
    // boule monde convertie a la profondeur du texel, plus ce que la chaine aval propage.
    autoport_proof::publish(("ao_static_chain_box_rx" + sfx).c_str(), s_static_box_rx[i]);
    autoport_proof::publish(("ao_static_chain_box_ry" + sfx).c_str(), s_static_box_ry[i]);
  }
  autoport_proof::publish("ao_static_cam_wind_cut_pairs", s_static_pairs_wind_cut);
  autoport_proof::publish("ao_static_cam_wind_premise", wind_premise ? 1ull : 0ull);
  autoport_proof::publish("ao_static_cam_motion_seen", motion_seen ? 1ull : 0ull);
  autoport_proof::publish("ao_static_cam_pop_px", term5_pop);
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
    autoport_proof::publish("ao_static_cam_delta_px", term5_moved);
    // (terme 5, diagnostic) LE RESIDU, NOMME. `_near_any_px` / `_self_dz_px` disent combien des
    // texels comptes ont, sans AUCUN seuil, un voisin de la boite ou eux-memes une profondeur qui
    // a change : c'est la mesure du signalement « kSameGeom = 4 quanta laisse passer les mobiles
    // lents » (FINDINGS de l'essai 16 de lighting-ao-indirect). Les `_worst_*` donnent le texel a
    // regarder. Aucun de ces compteurs n'entre dans un terme.
    {
      uint64_t xpop_l = 0, xmoved_l = 0, xpop_w = 0, xmoved_w = 0;
      for (int i = 0; i < kCensusStates; i++) {
        if (i < 9) {
          xpop_l += s_static_pop_x[i];
          xmoved_l += s_static_moved_x[i];
        } else {
          xpop_w += s_static_pop_x[i];
          xmoved_w += s_static_moved_x[i];
        }
      }
      autoport_proof::publish("ao_static_exactguard_pop_px", xpop_l);
      autoport_proof::publish("ao_static_exactguard_moved_px", xmoved_l);
      autoport_proof::publish("ao_static_exactguard_legacy_pop_px", xpop_w);
      autoport_proof::publish("ao_static_exactguard_legacy_moved_px", xmoved_w);
    }
    autoport_proof::publish("ao_static_moved_near_any_px", s_static_moved_near_any);
    autoport_proof::publish("ao_static_moved_self_dz_px", s_static_moved_self_dz);
    autoport_proof::publish("ao_static_moved_worst_ao", s_static_moved_worst_ao);
    autoport_proof::publish("ao_static_moved_worst_x", s_static_moved_worst_x);
    autoport_proof::publish("ao_static_moved_worst_y", s_static_moved_worst_y);
    autoport_proof::publish("ao_static_moved_worst_state", s_static_moved_worst_state);
    autoport_proof::publish("ao_static_moved_worst_dzq", s_static_moved_worst_dzq);
    autoport_proof::publish("ao_static_cam_legacy_px", term5_legacy);
  } else {
    autoport_proof::publish_text("ao_static_cam_delta_px", "non-mesure");
    autoport_proof::publish_text("ao_static_cam_legacy_px", "non-mesure");
  }
  const uint64_t t5 = static_measured ? term5_moved : 1ull;

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
  autoport_proof::publish("ao_contact_restore_armed", s_contact_armed);
  autoport_proof::publish("ao_contact_restore_passes", s_contact_passes);
  autoport_proof::publish("ao_contact_restore_strength_milli", s_contact_strength_milli);
  autoport_proof::publish("ao_contact_restore_radius", 5);
  // Ce que le GPU a REELLEMENT produit, relu par le recensement : population, pixels portes,
  // pixels a plus de 25 %, maximum et somme. Bras temoin = zero partout, sans exception.
  autoport_proof::publish("ao_contact_g_frames", s_contact_g_frames);
  autoport_proof::publish("ao_contact_g_pop_px", s_contact_g_pop);
  autoport_proof::publish("ao_contact_g_px", s_contact_g_px);
  autoport_proof::publish("ao_contact_g_hi_px", s_contact_g_hi_px);
  autoport_proof::publish("ao_contact_g_max", s_contact_g_max);
  autoport_proof::publish("ao_contact_g_sum", s_contact_g_sum);
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
  // ═══ (m) LA BANDE DU RACCORD, PAR MODE ET PAR QUALITE ════════════════════════════════════
  // Retour owner du 2026-09-17 : « on a quand meme (QUELQUE SOIT le model de AO selectionne ET
  // la qualite) une bande claire a la zone de contact ». Le contrat (m) l'ecrit en grandeur :
  // publier l'exces de clarte du raccord pour CHACUN des neuf couples (SSAO/HBAO/GTAO x q0/q1/
  // q2) ; « un mode ou une qualite non mesure compte 1 ». Jusqu'a cet essai HBAO n'entrait dans
  // AUCUN etat de recensement : trois couples sur neuf etaient aveugles sans qu'aucune cle ne
  // le dise. La grandeur jugee est l'EXCES sur le plan (`bright_rate` du pli moins celui du
  // plan, meme image) et non `ao_contact_band_px` : ce dernier exige un maximum LOCAL a trois
  // taps et rend donc 0 sur une RAMPE, qui est la forme du defaut (banc de l'enfant, essai 17).
  // Il reste publie a cote, comme crete historique.
  uint64_t t8 = 0, band_couples_measured = 0, band_couples_bright = 0;
  {
    std::string uncovered;
    for (int i = 0; i < 9; i++) {
      const ContactRamp& cc = s_hutedge_ramp[i];
      const ContactRamp& pl = s_contact_plane[i];
      const bool measured = (s_census_frames[i] > 0 && cc.sides > 0 && pl.sides > 0);
      const uint64_t rc = cc.sides ? (1000ull * cc.bright / cc.sides) : 0ull;
      const uint64_t rp = pl.sides ? (1000ull * pl.bright / pl.sides) : 0ull;
      const uint64_t excess = (rc > rp) ? rc - rp : 0ull;
      if (!measured) {
        t8++;
        if (!uncovered.empty()) {
          uncovered += ",";
        }
        uncovered += kCensusName[i];
        continue;
      }
      band_couples_measured++;
      if (excess > 0) {
        t8++;
        band_couples_bright++;
      }
    }
    autoport_proof::publish("ao_band_couples_total", 9ull);
    autoport_proof::publish("ao_band_couples_measured", band_couples_measured);
    autoport_proof::publish("ao_band_couples_bright", band_couples_bright);
    // Une cle de TEXTE garde sa derniere valeur : une liste vide se publie « - », jamais rien.
    autoport_proof::publish_text("ao_band_couples_uncovered",
                                 uncovered.empty() ? "-" : uncovered.c_str());
  }

  // ═══ (n) L'AO N'EST PLUS UN FILTRE FINAL ═════════════════════════════════════════════════
  // Retour owner du 2026-09-17 : « j'ai toujours comme cette impression que l'AO est juste
  // posee par dessus comme un filtre, comme si elle etait calculee tout a la fin ». SPEC 4.7,
  // ligne « Aujourd'hui / Cible » : la passe condamnee composait sur l'image opaque en gamma,
  // multipliait TOUT le pixel et protegeait le direct par un masque de luminance. Le terme
  // compte un defaut par fait NON TENU, et un fait non mesurable compte aussi :
  //   . la classe de composite n'est plus compilee   (temoin : le detecteur se teste lui-meme
  //     sur une classe qui LA porte — sans lui, un zero prouverait seulement que le detecteur
  //     ne detecte rien)
  //   . aucun dessin d'AO ne prend le FBO de scene pour cible
  //   . aucun programme lie n'expose d'uniforme de masque de luminance, et le controle positif
  //     du meme interrogatoire (l'uniforme d'AO lui-meme) est trouve
  //   . l'indirect a REELLEMENT recu l'AO sur cette course (le bras `--off` rend 0)
  // Le quatrieme fait du contrat — « un pixel eclaire par le direct seul a la MEME valeur AO
  // allumee et eteinte » — est deja le terme 1 (`ao_direct_leak_px`) et n'est pas compte deux
  // fois.
  uint64_t t9 = 0, t9_measured = 0;
  {
    const uint64_t composite_compiled = ao_has_composite<AmbientOcclusionPass>::value ? 1ull : 0ull;
    const uint64_t selftest = ao_has_composite<AoLegacyWitnessControl>::value ? 1ull : 0ull;
    const bool mask_measured = (s_arch_programs_queried > 0 && s_arch_switch_readers > 0);
    autoport_proof::publish("ao_arch_composite_compiled", composite_compiled);
    autoport_proof::publish("ao_arch_composite_selftest", selftest);
    autoport_proof::publish("ao_arch_draws_on_scene", s_ao_draws_on_scene);
    autoport_proof::publish("ao_arch_programs_queried", s_arch_programs_queried);
    autoport_proof::publish("ao_arch_switch_readers", s_arch_switch_readers);
    autoport_proof::publish("ao_arch_luma_mask_sites", s_arch_luma_mask_sites);
    autoport_proof::publish("ao_arch_luma_mask_measured", mask_measured ? 1ull : 0ull);
    autoport_proof::publish("ao_arch_indirect_hit_px", s_arch_indirect_hit_px);
    autoport_proof::publish("ao_arch_indirect_pop_px", s_arch_probe_px);
    autoport_proof::publish_text("ao_arch_apply_site", "shade.glsl:shade_body (avant tone map)");
    t9 += (composite_compiled != 0) ? 1ull : 0ull;
    t9 += (selftest != 1) ? 1ull : 0ull;
    t9 += (s_ao_draws_on_scene != 0) ? 1ull : 0ull;
    t9 += mask_measured ? ((s_arch_luma_mask_sites != 0) ? 1ull : 0ull) : 1ull;
    t9 += (s_arch_probe_px > 0) ? ((s_arch_indirect_hit_px == 0) ? 1ull : 0ull) : 1ull;
    t9_measured = (mask_measured && s_arch_probe_px > 0) ? 1ull : 0ull;
  }

  // ═══ (G) LE COUT EST CHIFFRE, OU IL NE L'EST PAS ═════════════════════════════════════════
  // Contrat de `ao-indirect-clean`, point G : « temps par image AO eteinte / SSAO / HBAO /
  // GTAO, meme vantage, >= 300 images chacun, publie ». Jusqu'ici ce point n'entrait dans
  // AUCUN terme : la campagne pouvait rendre `ao_cost_legs_done=0` — ce qu'elle a fait a
  // l'essai 15, la course s'arretant a 1680 images pour un depart a 2000 — et la porte passer
  // quand meme. Un point du contrat qu'aucun terme ne lit est un vert obtenu en ne regardant
  // pas ; la regle du contrat est « un terme non mesure compte 1 », elle vaut pour celui-la.
  // Le terme compte UNE unite par jambe qui n'a pas ses 300 images mesurees : il nomme
  // COMBIEN de jambes manquent, pas seulement qu'il en manque.
  uint64_t t10 = 0, cost_legs_measured = 0;
  {
    std::string uncovered;
    for (int i = 0; i < kCostLegCount; i++) {
      if (s_cost_frames[i] >= kCostMeasured) {
        cost_legs_measured++;
        continue;
      }
      t10++;
      if (!uncovered.empty()) {
        uncovered += ",";
      }
      uncovered += kCostLegs[i].key;
    }
    autoport_proof::publish("ao_cost_legs_measured", cost_legs_measured);
    // Une cle de TEXTE garde sa derniere valeur : une liste vide se publie « - », jamais rien.
    autoport_proof::publish_text("ao_cost_legs_uncovered",
                                 uncovered.empty() ? "-" : uncovered.c_str());
  }

  autoport_proof::publish("ao_owner_term1_direct_leak", t1);
  autoport_proof::publish("ao_owner_term2_pattern", t2);
  autoport_proof::publish("ao_owner_term3_sway", t3);
  autoport_proof::publish("ao_owner_term4_alpha_device", t4);
  autoport_proof::publish("ao_owner_term5_static_cam", t5);
  autoport_proof::publish("ao_owner_term6_contact_band", t6);
  autoport_proof::publish("ao_owner_term7_high_res", t7);
  autoport_proof::publish("ao_owner_term8_band_by_mode", t8);
  autoport_proof::publish("ao_owner_term9_not_a_final_filter", t9);
  autoport_proof::publish("ao_owner_term10_cost", t10);
  autoport_proof::publish("ao_owner_terms_measured",
                          (uint64_t)(((s_prepass_mask & 1) ? 1 : 0) +
                                     ((s_prepass_mask & 2) ? 1 : 0) +
                                     ((s_prepass_mask & 4) ? 1 : 0) + (flat_measured ? 1 : 0) +
                                     (static_measured ? 1 : 0) + (contact_measured ? 1 : 0) +
                                     ((q2_full || cross_measured) ? 1 : 0) +
                                     ((band_couples_measured == 9) ? 1 : 0) +
                                     (int)t9_measured +
                                     ((cost_legs_measured == kCostLegCount) ? 1 : 0)));
  autoport_proof::publish("ao_owner_terms_total", 10ull);
  // LA PORTE. Les sept termes du 14/09, les deux que le retour owner du 17/09 a ajoutes —
  // (m) la bande du raccord couple par couple, (n) l'AO qui n'est plus un filtre final — et
  // le dixieme que `ao-indirect-clean` ajoute : (G) le cout chiffre sur ses quatre jambes.
  // Un terme non mesure compte pour un defaut nomme — c'est la regle du contrat, et c'est
  // elle qui interdit un vert obtenu en ne regardant pas.
  autoport_proof::publish("ao_owner_defects",
                          t1 + t2 + t3 + t4 + t5 + t6 + t7 + t8 + t9 + t10);
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
    hut_archive.expected = dbg == 2 ? 0 : 7 + ((s_measure_legacy != 0) ? 2 : 2 * nboxes + 5);
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
      soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
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
            soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
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
    // ── (essai 15) LA CARTE `g` SE CALCULE AVANT LE FLOU, ELLE NE DEPEND QUE DE LA PROFONDEUR ─
    // Trois passes pleine resolution : une qui lit 26 texels de profondeur et rend la concavite,
    // deux qui la lissent (tente 1,4,6,4,1 en H puis en V). Le brouillon sert d'intermediaire :
    // aucune cible de plus que `m_ao_gterm_tex`. Elles sont DESARMEES sur le bras temoin, donc
    // `ao_contact_g_*` y vaut zero et l'ablation est gratuite.
    const bool contact_restore = ridge_fill;
    // REMIS A ZERO A CHAQUE IMAGE : sans ca, une image du bras TEMOIN relirait la carte `g`
    // laissee par l'image LIVREE precedente et l'ablation rendrait le meme chiffre des deux
    // cotes — une porte verte par inertie, pas par mesure.
    s_contact_gterm_fbo = 0;
    if (contact_restore) {
      ensure_gterm(out_w, out_h);
      s_contact_gterm_fbo = m_ao_gterm_fbo;
      shader.activate();
      GLuint gid = shader.id();
      struct GLeg { GLuint fbo; GLuint src; int pass; float dx, dy; };
      const GLeg glegs[3] = {
          {m_ao_gterm_fbo, 0u, 1, 0.0f, 0.0f},
          {m_ao_scratch_fbo, m_ao_gterm_tex, 2, 1.0f / (float)out_w, 0.0f},
          {m_ao_gterm_fbo, m_ao_scratch_tex, 2, 0.0f, 1.0f / (float)out_h}};
      for (const auto& leg : glegs) {
        glBindFramebuffer(GL_FRAMEBUFFER, leg.fbo);
        glViewport(0, 0, out_w, out_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, leg.src ? leg.src : m_ao_tex[0]);
        glUniform1i(glu::loc(gid, "u_ao"), 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, depth_tex);
        glUniform1i(glu::loc(gid, "u_depth"), 1);
        upload_common_uniforms(gid, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
        glUniform2f(glu::loc(gid, "u_dir"), leg.dx, leg.dy);
        glUniform1f(glu::loc(gid, "u_edge_reject"), 1.0f);
        glUniform1i(glu::loc(gid, "u_blur_report"), 0);
        glUniform1i(glu::loc(gid, "u_ridge_fill"), 0);
        glUniform1i(glu::loc(gid, "u_contact_pass"), leg.pass);
        glUniform1f(glu::loc(gid, "u_contact_strength"), 0.0f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
        note_target(leg.fbo);
        s_contact_passes++;
      }
      s_contact_armed = 1;
      s_contact_strength_milli = (uint64_t)std::lround(kContactStrength * 1000.0f);
      if (hut_archive.active) {
        hut_archive.capture("contact-g", m_ao_gterm_fbo, out_w, out_h);
      }
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
      // La restauration de contact ne se pose que sur la DERNIERE jambe — celle qui ecrit dans
      // la texture que shade() lit. Sur les autres, K vaut 0 : le flou reste exactement celui
      // d'avant, et le facteur (1 - K.g) n'est applique qu'UNE fois, pas huit.
      glUniform1i(glu::loc(id, "u_contact_pass"), 0);
      const bool last_leg = (p == nlegs - 1);
      glUniform1f(glu::loc(id, "u_contact_strength"),
                  (contact_restore && last_leg) ? kContactStrength : 0.0f);
      glActiveTexture(GL_TEXTURE2);
      glBindTexture(GL_TEXTURE_2D, contact_restore ? m_ao_gterm_tex : depth_tex);
      glUniform1i(glu::loc(id, "u_gterm"), 2);
      glActiveTexture(GL_TEXTURE0);
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
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
        glUniform1i(glu::loc(id, "u_contact_pass"), 0);
        glUniform1f(glu::loc(id, "u_contact_strength"), 0.0f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
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
        glUniform1i(glu::loc(id, "u_contact_pass"), 0);
        glUniform1f(glu::loc(id, "u_contact_strength"), 0.0f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        soft_draw_census::record_arrays("postprocess", 4, GL_TRIANGLE_STRIP);
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
  // L'unite 2 n'existait pas avant l'essai 15 : la passe la pose pour `u_gterm`, elle la rend.
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, 0);
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
    // L'ETAT, EXPLICITE : legacy*9 + mode_idx*3 + quality, mode_idx 0 = SSAO, 1 = GTAO,
    // 2 = HBAO. Les trois modes que l'owner teste sont recenses, chacun sur ses trois paliers.
    const int mode_idx = (mode == 1) ? 0 : (mode == 3) ? 1 : (mode == 2) ? 2 : -1;
    const int census_state =
        (mode_idx < 0) ? -1 : ((s_measure_legacy ? 1 : 0) * 9 + mode_idx * 3 + quality);
    // (essai 18) La camera que les estimateurs viennent de recevoir, rangee pour le detecteur
    // d'aretes : `invf` est l'inverse deja calcule plus haut, pas un second calcul.
    for (int i = 0; i < 16; i++) s_census_cam_inv[i] = invf[i];
    for (int i = 0; i < 4; i++) s_census_cam_hvdf[i] = rs->camera_hvdf_off[i];
    for (int i = 0; i < 4; i++) s_census_cam_pos[i] = rs->camera_pos[i];
    s_census_cam_fog = rs->camera_fog.x();
    s_census_cam_valid = true;
    pattern_census(quality, census_state, scale, m_ao_full_fbo, m_ao_full_w, m_ao_full_h);
  }

  return produced;
}
