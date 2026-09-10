#include "game/graphics/opengl_renderer/hdr.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/opengl_renderer/hdr_output.h"

#include <cmath>
#include <cstring>
#include <cstdlib>
#include <map>
#include <set>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/DirectRenderer.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/graphics/opengl_renderer/background/Shrub.h"
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#include "game/graphics/refset.h"
#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace hdr {
namespace {

constexpr const char* kItemId = "lighting-hdr";

thread_local bool s_frame_active = false;
thread_local bool s_frame_chain = false;

// L'echelle de repli du §4.5, dans l'ordre. On ne descend d'un cran que lorsque le pilote a
// REFUSE le cran precedent (FBO incomplet) : le repli est mesure, jamais suppose.
//
// POURQUOI R11F_G11F_B10F N'Y EST PAS, alors que le §4.5 le nomme. Ce format n'a PAS de canal
// alpha, et l'alpha du tampon de scene de ce moteur n'est pas decoratif : `GL_DST_ALPHA` est un
// facteur de melange reellement utilise (background_common.cpp:221 `glBlendFunc(GL_DST_ALPHA,
// GL_ONE)`, DirectRenderer.cpp:543, DirectRenderer2.cpp:282, CommonOceanRenderer.cpp:344 et 537,
// Generic2_OpenGL.cpp:170). Sur une cible sans alpha, GL lit un alpha de destination de 1,0 :
// ces six sites changeraient de resultat en silence. Le cran est donc RETIRE, pas oublie — et
// il n'est pas necessaire : GLES 3.2 rend RGBA16F obligatoirement color-renderable.
// Le dernier cran (RGBA8) est celui du §4.5 : « RGBA8 a exposition fixe ». La chaine reste
// active, le site de tone map tire toujours, mais il n'y a plus de marge au-dessus de 1.
constexpr GLenum kFormatLadder[] = {GL_RGBA16F, GL_RGBA8};
constexpr int kLadderLen = 2;
int s_ladder_step = 0;

// ------------------------------------------------------------------------------ recensement --
struct DisplaySite {
  bool narrowed = false;
  uint64_t count = 0;
};
std::map<std::string, DisplaySite> s_display_sites;  // chemin d'affichage
std::map<std::string, DisplaySite> s_aux_sites;      // effets, hors chemin d'affichage
std::set<std::string> s_explicit_sites;              // d'ou le tone map a REELLEMENT ete tire

struct ProgInfo {
  bool has_compression = false;
  uint64_t oetf_occurrences = 0;
};
std::map<std::string, ProgInfo> s_progs;

uint64_t s_frames = 0;
uint64_t s_chain_frames = 0;
uint64_t s_tonemap_draws = 0;
// lighting-hdr, verdict 5 : `tonemap_sites == 1` dans les TROIS configurations, pas seulement
// eclairage allume. On compte donc PAR CONFIGURATION et PAR IMAGE, jamais globalement : un
// recensement cumule sur toute la course melangerait les trois et rendrait 1 alors qu'une des
// trois en porte zero ou deux.
//   1 = ORIGINE-TOTAL (master OFF) · 2 = RECHARGED · 3 = ORIGINE-LUMIERE (master ON, lumiere OFF)
uint64_t s_cfg_frames[4] = {0, 0, 0, 0};
uint64_t s_cfg_bad[4] = {0, 0, 0, 0};
bool s_drew_this_frame = false;
uint64_t s_sites_now = 0;  // le compte de la DERNIERE image, dans SA configuration
int s_cfg_now = 0;
// La PREMIERE image dont le recensement n'a pas rendu 1, avec ses trois termes separes.
uint64_t s_bad_first_frame = 0, s_bad_first_cfg = 0, s_bad_first_sites = 0;
uint64_t s_bad_first_draw = 0, s_bad_first_fmt8 = 0, s_bad_first_shader = 0;

// ------------------------------------------------------------------------------------ sonde --
constexpr int kProbeW = 96;
constexpr int kProbeH = 54;
constexpr uint64_t kProbeEvery = 30;
GLuint s_probe_fbo = 0;
GLuint s_probe_tex = 0;
int s_probe_state = 0;  // 0 = jamais tente, 1 = pret, -1 = impossible (dit pourquoi)
uint64_t s_probe_px = 0;
uint64_t s_probe_overbright = 0;
uint64_t s_probe_frames = 0;
uint64_t s_probe_max_x1000 = 0;   // le plus grand canal vu, x1000
uint64_t s_ldr_ref_delta = 0;     // max |epaule - ecretage| sur 0..255

bool env_or_prop_override(const char* prop, const char* env, int* out) {
#ifdef __ANDROID__
  (void)env;
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    *out = std::atoi(buf);
    return true;
  }
#else
  (void)prop;
  const char* e = std::getenv(env);
  if (e && e[0]) {
    *out = std::atoi(e);
    return true;
  }
#endif
  return false;
}

// Miroir scalaire de l'epaule SDR a blanc fini de tonemap.frag, par canal.
float shoulder(float x, float k) {
  if (x <= k) {
    return x;
  }
  const float w = (1.f - k) > 1e-4f ? (1.f - k) : 1e-4f;
  const float above = x - k;
  return above >= 2.f * w ? 1.f : k + above - above * above / (4.f * w);
}

// lighting-hdr, verdict 3 : « courbe monotone sans coude ».
// Miroir SCALAIRE de ce que `tonemap.frag` applique, evalue sur la diagonale grise (r=g=b) —
// c'est la seule direction ou les deux courbes se reduisent a une fonction d'une variable, et
// c'est la courbe de tonalite au sens ou l'entend la SPEC §4.5.
// Pour `hdr_neutral` (Khronos) sur du gris, les etapes de desaturation s'annulent et il ne
// reste que `newPeak` : le calcul ci-dessous est la reduction exacte, pas une approximation.
float curve_eval(float x, float k, int curve) {
  if (curve != 1) {
    return shoulder(x, k);
  }
  const float kStart = 0.76f, kDesat = 0.15f;
  const float offset = x < 0.08f ? x - 6.25f * x * x : 0.04f;
  const float peak = x - offset;
  if (peak < kStart) {
    return peak;
  }
  const float d = 1.f - kStart;
  (void)kDesat;
  return 1.f - d * d / (peak + d - kStart);
}

// 0 = tenu, 1 = defaut — meme convention que les quatre verdicts de refset.h.
// On juge la courbe REELLEMENT configuree, pas le defaut : c'est celle qui est livree.
// Trois clauses, et chacune peut echouer seule :
//   monotone  — f(x+h) >= f(x) partout ; une inversion rendrait un degrade non ordonne.
//   sans coude — la derivee est continue. Echantillonnee au pas h, une derivee CONTINUE fait
//                varier la difference finie de l'ordre de |f''|*h (ici <= ~0,01 au genou) ;
//                une derivee DISCONTINUE la fait sauter de l'ordre de 1. La borne 0,05 separe
//                les deux de deux ordres de grandeur, elle ne calibre rien.
//   bornee    — f(x) <= 1 : au-dela, le tampon 8 bits final reprendrait un ecretage, et le
//                site unique n'en serait plus un.
uint64_t s_curve_kink_max_x1000 = 0;
uint64_t s_curve_samples = 0;
int s_curve_mono_bad = 0;
int s_curve_bound_bad = 0;

int verdict_curve() {
  const float k = Gfx::g_global_settings.recharged_hdr_knee;
  const int curve = Gfx::g_global_settings.recharged_hdr_curve;
  const float h = 0.001f;
  const int n = 8000;  // 0 .. 8,0 : bien au-dela du maximum mesure (hdr_probe_max_x1000)
  float prev = curve_eval(0.f, k, curve);
  float prev_d = 0.f;
  float kink_max = 0.f;
  int mono_bad = 0, bound_bad = 0;
  for (int i = 1; i <= n; i++) {
    const float x = (float)i * h;
    const float f = curve_eval(x, k, curve);
    if (f < prev - 1e-6f) {
      mono_bad++;
    }
    if (f > 1.f + 1e-4f) {
      bound_bad++;
    }
    const float d = (f - prev) / h;
    if (i > 1) {
      const float jump = std::fabs(d - prev_d);
      if (jump > kink_max) {
        kink_max = jump;
      }
    }
    prev_d = d;
    prev = f;
  }
  s_curve_kink_max_x1000 = (uint64_t)(kink_max * 1000.f + 0.5f);
  s_curve_samples = (uint64_t)n;
  s_curve_mono_bad = mono_bad;
  s_curve_bound_bad = bound_bad;
  return (mono_bad == 0 && bound_bad == 0 && kink_max <= 0.05f) ? 0 : 1;
}

// HDR exige les deux configurations eclairage ON/OFF (2/3) ; les autres items gardent 1/2/3.
// Une configuration JAMAIS VISITEE est un defaut, pas une dispense : c'est exactement la faute
// qui a produit ce bug (deux bras verts, la configuration livree absente des deux).
int verdict_sites_three_configs() {
  for (int c = autoport_proof::feature_is(kItemId) ? 2 : 1; c <= 3; c++) {
    if (s_cfg_frames[c] == 0 || s_cfg_bad[c] != 0) {
      return 1;
    }
  }
  return 0;
}

// Les jetons d'une COMPRESSION DE PLAGE dans un texte fragment. Ce sont des identifiants, pas
// des motifs generiques : `min(x, 1.0)` sur un facteur intermediaire n'est pas une compression
// de l'image, et le compter rendrait le recensement inexploitable.
const char* kCompressionTokens[] = {
    "RT_KNEE",          // l'epaule de pbr_fused.glsl, deplacee au site unique par cet item
    "MM_KNEE",          // l'epaule de pbr_modern.glsl, idem
    "mm_tonemap_aces",  // la courbe ACES opt-in de pbr_modern, idem
};

// Le recensement lit le CODE, pas les commentaires. Les trois jetons ci-dessus apparaissent
// justement dans les commentaires qui expliquent leur retrait : les compter la rendrait la
// grandeur inexploitable — et pire, la rendrait sensible a une phrase. On retire donc `//...`
// et les blocs avant de chercher. En cas de doute, l'erreur va vers le ROUGE (un commentaire
// mal retire fait monter le compte), jamais vers un faux vert.
std::string strip_comments(const std::string& src) {
  std::string out;
  out.reserve(src.size());
  enum { kCode, kLine, kBlock } st = kCode;
  for (size_t i = 0; i < src.size(); i++) {
    const char c = src[i];
    const char n = (i + 1 < src.size()) ? src[i + 1] : '\0';
    if (st == kCode) {
      if (c == '/' && n == '/') {
        st = kLine;
        i++;
      } else if (c == '/' && n == '*') {
        st = kBlock;
        i++;
      } else {
        out.push_back(c);
      }
    } else if (st == kLine) {
      if (c == '\n') {
        st = kCode;
        out.push_back(c);
      }
    } else {
      if (c == '*' && n == '/') {
        st = kCode;
        i++;
      }
    }
  }
  return out;
}

uint64_t count_occurrences(const std::string& hay, const std::string& needle) {
  uint64_t n = 0;
  size_t at = 0;
  while ((at = hay.find(needle, at)) != std::string::npos) {
    n++;
    at += needle.size();
  }
  return n;
}

void ensure_probe() {
  if (s_probe_state != 0) {
    return;
  }
  glGenFramebuffers(1, &s_probe_fbo);
  glGenTextures(1, &s_probe_tex);
  glBindTexture(GL_TEXTURE_2D, s_probe_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, kProbeW, kProbeH, 0, GL_RGBA, GL_FLOAT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, s_probe_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s_probe_tex, 0);
  const GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (st != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-hdr] sonde de marge indisponible : FBO 0x{:x}", (unsigned)st);
    s_probe_state = -1;
    return;
  }
  s_probe_state = 1;
}

float half_to_float(uint16_t h) {
  const uint32_t sign = (uint32_t)(h >> 15) << 31;
  uint32_t exp = (h >> 10) & 0x1f;
  uint32_t man = h & 0x3ff;
  if (exp == 0) {
    if (man == 0) {
      float f;
      uint32_t b = sign;
      std::memcpy(&f, &b, 4);
      return f;
    }
    while (!(man & 0x400)) {
      man <<= 1;
      exp--;
    }
    exp++;
    man &= 0x3ff;
  } else if (exp == 31) {
    exp = 255;
  }
  if (exp != 255) {
    exp = exp + 112;
  }
  const uint32_t bits = sign | (exp << 23) | (man << 13);
  float f;
  std::memcpy(&f, &bits, 4);
  return f;
}

}  // namespace

// ---------------------------------------------------------------------------------- regime ----

FrameScope::FrameScope()
    : m_previous_active(s_frame_active), m_previous_chain(s_frame_chain) {
  const bool chain = chain_active();
  s_frame_chain = chain;
  s_frame_active = true;
}

FrameScope::~FrameScope() {
  s_frame_active = m_previous_active;
  s_frame_chain = m_previous_chain;
}

bool chain_active() {
  if (s_frame_active) {
    return s_frame_chain;
  }
#if defined(AUTOPORT_ABLATE_LIGHTING_HDR)
  // BINAIRE TEMOIN DU VERDICT 4 — la seule chose que cette macro fabrique.
  //
  // Le verdict 4 dit « master eteint => sortie identique au bit a ORIGINE-TOTAL ». Si la
  // reference ORIGINE-TOTAL est capturee par LE BINAIRE QU'ON JUGE, l'affirmation se compare a
  // elle-meme : elle mesure la stabilite de l'appareil, pas l'innocuite de l'item, et elle
  // rendrait zero meme si tout avait ete casse. Sur bureau la reference vient de l'item 0 ; sur
  // l'appareil aucun binaire d'avant l'item ne sait capturer (le port de capture arm64 date du
  // 2026-09-06). On construit donc UNE FOIS un binaire ou la chaine de cet item ne peut
  // PHYSIQUEMENT pas tourner, on capture ORIGINE-TOTAL avec lui, et le rejeu se fait avec le
  // binaire normal. `refset::self_fingerprint()` les distingue, et le temoin de capture refuse
  // l'egalite.
  //
  // CE QUE CE TEMOIN NE COUVRE PAS, ecrit ici pour que personne ne le lise plus large qu'il
  // n'est : l'ablation est en C++. Les shaders, eux, sont les MEMES dans les deux binaires. Un
  // eventuel debordement de l'item qui vivrait UNIQUEMENT dans du GLSL atteint sous master OFF
  // ne serait pas vu par cette comparaison. Les chemins modifies (`pbr_fused`, `pbr_modern`,
  // composites C/E de `shade.glsl`) sont tous gardes par `u_pbr_mode != 0`, que le mode ORIGINE
  // laisse a zero — c'est un argument de lecture, pas une mesure.
  return false;
#else
  int ov = -1;
  const bool has_ov = env_or_prop_override("debug.opengoal.hdr", "OG_HDR", &ov);
  // L'override epingle LE SOUS-DRAPEAU de cet item, jamais la composition : les trois niveaux
  // (master -> ECLAIRAGE RECHARGE -> HDR) restent toujours consultes, via Gfx::lighting_active().
  // Sans ca, poser `debug.opengoal.hdr=1` — ce que font les proof_props de l'item — sauterait la
  // garde d'eclairage pendant la course de preuve, exactement la ou elle doit mordre : la chaine
  // HDR tournerait avec `recharged_lighting` OFF. C'est la regle « epingler le regime de SA
  // feature » : on epingle SON reglage, pas les maitres qui sont au-dessus de lui.
  // Le compteur de la porte tire INCONDITIONNELLEMENT : un compteur qui ne s'incremente que
  // dans la branche « pas d'override » ne prouverait rien de l'autre branche.
  const bool sub_gate = recharged_gating::on(recharged_gating::kHdr);
  const bool sub_on = has_ov ? (ov != 0) : sub_gate;
  if (!Gfx::lighting_active(sub_on)) {
    return false;
  }
  // L'ablation du harnais est CAUSALE : `--off` eteint la chaine, le tone map n'est pas tire,
  // `hits` tombe a 0 parce que le geste n'a pas eu lieu — pas seulement parce que le compteur
  // s'est tu. Arme par defaut quand le harnais ne demande rien.
  return autoport_proof::armed_for(kItemId);
#endif
}

GLenum scene_color_format() {
  if (!chain_active()) {
    return GL_RGBA8;
  }
  return kFormatLadder[s_ladder_step];
}

bool note_scene_fbo_result(GLenum requested, bool complete) {
  if (complete) {
    return false;
  }
  for (int i = 0; i < kLadderLen; i++) {
    if (kFormatLadder[i] == requested && i + 1 < kLadderLen) {
      s_ladder_step = i + 1;
      lg::error("[lighting-hdr] {} refuse par le pilote : repli sur {}", format_name(requested),
                format_name(kFormatLadder[s_ladder_step]));
      return true;
    }
  }
  return false;
}

bool format_is_float(GLenum fmt) {
  return fmt == GL_RGBA16F || fmt == GL_R11F_G11F_B10F || fmt == GL_RGBA32F;
}

const char* format_name(GLenum fmt) {
  switch (fmt) {
    case GL_RGBA16F:
      return "RGBA16F";
    case GL_R11F_G11F_B10F:
      return "R11F_G11F_B10F";
    case GL_RGBA32F:
      return "RGBA32F";
    case GL_RGBA8:
      return "RGBA8";
    default:
      return "autre";
  }
}

// ----------------------------------------------------------------------------- site unique ----

bool tonemap_draw(Shader& shader,
                  const char* site,
                  GLuint src_tex,
                  GLuint dst_fbo,
                  int dst_w,
                  int dst_h,
                  GLuint vao,
                  GLuint vbo) {
  if (!shader.okay()) {
    lg::error("[lighting-hdr] programme `tonemap` indisponible : le blit d'origine est repris");
    return false;
  }
  // L'appelant reprend son programme et ses liaisons ; framebuffer et viewport restent
  // volontairement sur la destination pour la suite du rendu UI.
  GLint saved_program = 0, saved_vao = 0, saved_array_buffer = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &saved_program);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &saved_vao);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saved_array_buffer);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDepthMask(GL_FALSE);

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, src_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  shader.activate();
  glUniform1i(glGetUniformLocation(shader.id(), "tex_T0"), 0);
  // lighting-hdr : LE SITE UNIQUE PORTE L'EXPOSITION DES DEUX ETAGES.
  // Les composites C et E poussent desormais `u_pbr_exposure = 1,0` (background_common.cpp) et
  // rendent leur exposition ici. Le facteur repris est `E_pbr^(1/2,2)` et pas `E_pbr` : eux
  // l'appliquaient en LINEAIRE avant leur `pow(1/2,2)`, ce site l'applique APRES, dans l'espace
  // d'affichage du tampon. C'est l'egalite exacte, pas un reglage approche — sans l'exposant, le
  // deplacement changerait la luminance de tout le decor.
  const float e_pbr = Gfx::g_global_settings.recharged_pbr_exposure;
  const float e_moved = (e_pbr > 0.f) ? std::pow(e_pbr, 1.f / 2.2f) : 1.f;
  const float effective_exposure = e_moved * Gfx::g_global_settings.recharged_hdr_exposure;
  glUniform1f(glGetUniformLocation(shader.id(), "u_hdr_exposure"), effective_exposure);
  if (autoport_proof::feature_is(kItemId) && s_frames % 30 == 0) {
    autoport_proof::publish_text("hdr_exposure_x1000",
                                 std::to_string(std::llround(effective_exposure * 1000.f)).c_str());
  }
  glUniform1f(glGetUniformLocation(shader.id(), "u_hdr_knee"),
              Gfx::g_global_settings.recharged_hdr_knee);
  glUniform1i(glGetUniformLocation(shader.id(), "u_hdr_curve"),
              Gfx::g_global_settings.recharged_hdr_curve);
  // hdr-display-output : le plafond. 1,0 tant que la surface est SDR (identite stricte avec
  // ce qui precede) ; la marge de l'ecran quand la sortie HDR est ACTIVE.
  glUniform1f(glGetUniformLocation(shader.id(), "u_hdr_ceiling"), hdr_output::tonemap_ceiling());
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  // hdr-display-output : sonde d'assombrissement (preuve seulement) — rejoue CE programme deux
  // fois hors ecran (plafond 1,0 / plafond HDR) sur la meme scene ; restaure dst_fbo + viewport.
  hdr_output::probe_tonemap(shader, dst_fbo, dst_w, dst_h);
  glUseProgram(saved_program);
  glBindVertexArray(saved_vao);
  glBindBuffer(GL_ARRAY_BUFFER, saved_array_buffer);
  glDepthMask(GL_TRUE);

  // AU SITE DU GESTE : le quad vient de partir. `hits` = images tone-mappees.
  s_explicit_sites.insert(site ? site : "?");
  s_tonemap_draws++;
  s_drew_this_frame = true;
  autoport_proof::note_hit();
  return true;
}

// ------------------------------------------------------------------------------ recensement ----

void note_fragment_source(const std::string& name, const std::string& src) {
  const std::string code = strip_comments(src);
  ProgInfo info;
  if (name != "tonemap") {
    for (const char* tok : kCompressionTokens) {
      if (code.find(tok) != std::string::npos) {
        info.has_compression = true;
        break;
      }
    }
  }
  info.oetf_occurrences = count_occurrences(code, "1.0 / 2.2");
  s_progs[name] = info;
}

void note_display_copy(const char* site, GLenum src_fmt, GLenum dst_fmt) {
  auto& e = s_display_sites[site ? site : "?"];
  e.count++;
  // hdr-display-output : la SEULE cible 10 bits de ce moteur est la surface de fenetre HDR10
  // (RGB10_A2, encodee PQ par le quad final). Y recopier un tampon flottant n'est pas une
  // compression de plage : l'OETF PQ porte jusqu'a 10 000 nits, la marge du tone map y tient
  // entiere. Toute autre cible non flottante ecrete, et compte.
  if (format_is_float(src_fmt) && !format_is_float(dst_fmt) && dst_fmt != GL_RGB10_A2) {
    e.narrowed = true;
  }
}

uint64_t last_frame_sites() {
  return s_sites_now;
}

void note_aux_scene_read(const char* site, GLenum src_fmt, GLenum dst_fmt) {
  auto& e = s_aux_sites[site ? site : "?"];
  e.count++;
  if (format_is_float(src_fmt) && !format_is_float(dst_fmt)) {
    e.narrowed = true;
  }
}

void probe_scene(GLuint scene_fbo, int w, int h, GLenum fmt) {
  if (!autoport_proof::feature_is(kItemId) || !format_is_float(fmt)) {
    return;  // instrument : ne tourne que sous mesure, et seulement sur un tampon flottant
  }
  if ((s_frames % kProbeEvery) != 0) {
    return;
  }
  ensure_probe();
  if (s_probe_state != 1) {
    return;
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, scene_fbo);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, s_probe_fbo);
  // NEAREST : une moyenne diluerait exactement ce qu'on cherche a compter.
  glBlitFramebuffer(0, 0, w, h, 0, 0, kProbeW, kProbeH, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, s_probe_fbo);

  GLint read_fmt = 0, read_type = 0;
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &read_fmt);
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &read_type);
  std::vector<float> px;
  bool ok = false;
  if (read_fmt == GL_RGBA && read_type == GL_HALF_FLOAT) {
    std::vector<uint16_t> raw((size_t)kProbeW * kProbeH * 4);
    glReadPixels(0, 0, kProbeW, kProbeH, GL_RGBA, GL_HALF_FLOAT, raw.data());
    px.resize(raw.size());
    for (size_t i = 0; i < raw.size(); i++) {
      px[i] = half_to_float(raw[i]);
    }
    ok = true;
  } else {
    px.resize((size_t)kProbeW * kProbeH * 4);
    glReadPixels(0, 0, kProbeW, kProbeH, GL_RGBA, GL_FLOAT, px.data());
    ok = (glGetError() == GL_NO_ERROR);
  }
  if (!ok) {
    lg::error("[lighting-hdr] relecture de la sonde refusee (fmt=0x{:x} type=0x{:x})",
              (unsigned)read_fmt, (unsigned)read_type);
    s_probe_state = -1;
    return;
  }

  const float k = Gfx::g_global_settings.recharged_hdr_knee;
  s_probe_frames++;
  for (size_t i = 0; i + 3 < px.size(); i += 4) {
    s_probe_px++;
    float mx = 0.f;
    for (int c = 0; c < 3; c++) {
      const float v = px[i + c];
      if (!(v == v)) {
        continue;  // NaN : ne compte ni comme marge ni comme ecart
      }
      if (v > mx) {
        mx = v;
      }
    }
    for (int c = 0; c < 3; c++) {
      const float v = px[i + c];
      if (!std::isfinite(v)) {
        continue;
      }
      const float clamped = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
      const float d = std::fabs(shoulder(std::max(v, 0.f), k) - clamped);
      const uint64_t d255 = (uint64_t)(d * 255.f + 0.5f);
      if (d255 > s_ldr_ref_delta) {
        s_ldr_ref_delta = d255;
      }
    }
    if (mx > 1.f) {
      s_probe_overbright++;
    }
    const uint64_t mx1000 = (uint64_t)(mx * 1000.f + 0.5f);
    if (mx1000 > s_probe_max_x1000) {
      s_probe_max_x1000 = mx1000;
    }
  }
}

void frame_end(GLenum scene_format) {
  s_frames++;
  const bool on = chain_active();
  if (on) {
    s_chain_frames++;
  }
  if (!autoport_proof::armed_for(kItemId)) {
    s_drew_this_frame = false;
    return;  // bras desarme : AUCUNE cle `hdr_*` / `tonemap_*`, comme lighting-unify
  }

  // ── verdict 5 : le recensement PAR IMAGE et PAR CONFIGURATION ────────────────────────────
  // Un recensement CUMULE sur toute la course melangerait les trois configurations et rendrait
  // 1 alors qu'une des trois en porte 0 ou 2. On compte donc l'image courante, dans la
  // configuration figee au debut du render — les getters des maitres gardent ce regime,
  // et scene_format vient du FBO effectivement retenu, apres repli eventuel.
  // Le compte d'une image vaut : le tone map a-t-il ete tire (0 ou 1) + le tampon de scene
  // ecrete-t-il par son format (RGBA8 = oui, flottant = non) + les programmes dont le texte
  // porte une compression de plage. Sous ORIGINE-TOTAL et ORIGINE-LUMIERE, l'unique site est
  // l'ecretage 8 bits du chemin d'origine ; sous RECHARGED, c'est le programme `tonemap`.
  {
    uint64_t sh = 0;
    for (const auto& [name, info] : s_progs) {
      if (info.has_compression) {
        sh++;
      }
    }
    const int cfg = !Gfx::recharged_master_active() ? 1
                                                    : (Gfx::recharged_lighting_active() ? 2 : 3);
    const uint64_t sites = (s_drew_this_frame ? 1ull : 0ull) +
                           (format_is_float(scene_format) ? 0ull : 1ull) + sh;
    s_cfg_frames[cfg]++;
    if (sites != 1) {
      s_cfg_bad[cfg]++;
      // LA PREMIERE image fautive, nommee. Un compte de 1 sur 1263 ne dit pas SI c'est une image
      // de transition de configuration ou un defaut permanent, et les deux se corrigent
      // differemment. On retient donc l'image, sa configuration, son compte de sites et le
      // detail des trois termes — jamais un simple total.
      if (!s_bad_first_frame) {
        s_bad_first_frame = s_frames;
        s_bad_first_cfg = (uint64_t)cfg;
        s_bad_first_sites = sites;
        s_bad_first_draw = s_drew_this_frame ? 1 : 0;
        s_bad_first_fmt8 = format_is_float(scene_format) ? 0 : 1;
        s_bad_first_shader = sh;
      }
    }
    s_sites_now = sites;
    s_cfg_now = cfg;
  }
  s_drew_this_frame = false;

  if ((s_frames % 30) != 0) {
    return;
  }

  uint64_t shader_sites = 0, oetf_progs = 0, oetf_total = 0;
  for (const auto& [name, info] : s_progs) {
    if (info.has_compression) {
      shader_sites++;
    }
    if (info.oetf_occurrences) {
      oetf_progs++;
      oetf_total += info.oetf_occurrences;
    }
  }
  uint64_t implicit_sites = 0;
  for (const auto& [name, e] : s_display_sites) {
    if (e.narrowed) {
      implicit_sites++;
    }
  }
  uint64_t aux_clamped = 0;
  std::string aux_names;
  for (const auto& [name, e] : s_aux_sites) {
    if (e.narrowed) {
      aux_clamped++;
      // Nommer les sites : un compte d'exclus sans leur nom n'est pas actionnable, et le §7.4
      // point 2 demande que le seau « exclu » soit publie a cote du seau « correct ».
      if (!aux_names.empty()) {
        aux_names += ",";
      }
      aux_names += name;
    }
  }
  const uint64_t explicit_sites = s_explicit_sites.size();

  // lighting-hdr : `tonemap_sites` est le compte de LA CONFIGURATION COURANTE, par image — le
  // meme nombre que juge le verdict 5. Le cumul des trois configurations rendrait 2 dans les
  // phases d'origine d'une course qui a aussi visite RECHARGED, parce que `explicit_sites` est
  // un ensemble qui ne se vide jamais. Les trois termes cumules restent publies en dessous.
  autoport_proof::publish("tonemap_sites", s_sites_now);
  autoport_proof::publish("tonemap_sites_cumulative",
                          explicit_sites + shader_sites + implicit_sites);
  autoport_proof::publish("tonemap_sites_config", (uint64_t)s_cfg_now);
  autoport_proof::publish("tonemap_sites_explicit", explicit_sites);
  autoport_proof::publish("tonemap_sites_shader", shader_sites);
  autoport_proof::publish("tonemap_sites_implicit", implicit_sites);
  autoport_proof::publish("tonemap_draws", s_tonemap_draws);
  autoport_proof::publish("hdr_progs_scanned", s_progs.size());
  autoport_proof::publish("hdr_display_guards", s_display_sites.size());
  autoport_proof::publish("hdr_aux_guards", s_aux_sites.size());
  autoport_proof::publish("hdr_aux_clamped_reads", aux_clamped);
  autoport_proof::publish_text("hdr_aux_clamped_sites",
                               aux_names.empty() ? "aucun" : aux_names.c_str());
  autoport_proof::publish("hdr_oetf_progs", oetf_progs);
  autoport_proof::publish("hdr_oetf_occurrences", oetf_total);
  autoport_proof::publish_text("hdr_format", format_name(scene_format));
  // QUEL BINAIRE A PRODUIT CETTE COURSE. `ablate` est le temoin du verdict 4 (voir
  // `chain_active`) : il ne doit JAMAIS apparaitre dans un proof.txt qui passe une porte.
#if defined(AUTOPORT_ABLATE_LIGHTING_HDR)
  autoport_proof::publish_text("hdr_build_flavour", "ablate");
#else
  autoport_proof::publish_text("hdr_build_flavour", "normal");
#endif
  autoport_proof::publish("hdr_fallback_used", (uint64_t)s_ladder_step);
  autoport_proof::publish("hdr_chain_frames", s_chain_frames);
  autoport_proof::publish("hdr_frames", s_frames);
  autoport_proof::publish("hdr_master_on", Gfx::recharged_master_active() ? 1 : 0);
  autoport_proof::publish("hdr_overbright_px", s_probe_overbright);
  autoport_proof::publish("hdr_probe_px", s_probe_px);
  autoport_proof::publish("hdr_probe_frames", s_probe_frames);
  autoport_proof::publish("hdr_probe_max_x1000", s_probe_max_x1000);
  autoport_proof::publish("hdr_probe_state", (uint64_t)(s_probe_state + 1));  // 0 KO, 1 jamais, 2 OK
  autoport_proof::publish("ldr_ref_delta", s_ldr_ref_delta);
  autoport_proof::publish("hdr_knee_x1000",
                          (uint64_t)(Gfx::g_global_settings.recharged_hdr_knee * 1000.f + 0.5f));

  // ── LA GRANDEUR DE PORTE ─────────────────────────────────────────────────────────────────
  // `hdr_tonemap_defects` est la SOMME de SIX verdicts, chacun publie A COTE : une somme sans
  // ses termes ne dit pas quoi corriger, et un zero sans son denominateur ne prouve rien.
  // Convention unique : 0 = tenu, 1 = defaut. « Pas mesurable » vaut 1 — une course qui n'irait
  // pas au bout doit etre ROUGE, jamais muette.
  // Les verdicts 1, 2 et 4 se lisent sur le jeu de references (trois configurations,
  // ORIGINE-LUMIERE comprise) ; 3 et 5 se mesurent ici, 6 relit les transferts observes.
  // L'IDENTITE AU BIT MAITRE ETEINT N'EST PLUS DE CET ITEM. Elle a ete sortie le 2026-09-07 dans
  // `lighting-origin-bitexact` : calibrer une courbe et garantir une purete sont deux natures
  // differentes, et groupees elles se bloquaient l'une l'autre. La mesure ne disparait pas pour
  // autant — elle est publiee sous le nom de porte de CET AUTRE item, `origin_bitexact_defects`,
  // pour qu'il la trouve deja instrumentee et qu'aucune course ne soit refaite pour elle.
  const int v1 = refset::verdict_saturation();
  const int v2 = refset::verdict_highlight_contrast();
  const int v3 = verdict_curve();
  const int v4 = refset::verdict_origine_lumiere_set();
  const int v5 = verdict_sites_three_configs();
  // La distorsion recompose sa copie couleur dans la scene : son retrecissement est une
  // perte prematuree, contrairement aux lectures auxiliaires de profondeur ou de masque.
  // Reutiliser les transferts observes ; l'absence de site n'est pas un test d'identite GPU.
  const auto distort = s_aux_sites.find("Sprite3_Distort:scene-copy");
  const int v6 = implicit_sites > 0 ||
                         (distort != s_aux_sites.end() && distort->second.narrowed)
                     ? 1
                     : 0;
  const int bitexact = refset::verdict_master_off_bitexact();
  autoport_proof::publish("hdr_defect_1_saturation", (uint64_t)v1);
  autoport_proof::publish("hdr_defect_2_hl_contrast", (uint64_t)v2);
  autoport_proof::publish("hdr_defect_3_curve", (uint64_t)v3);
  autoport_proof::publish("hdr_defect_4_origine_lumiere_set", (uint64_t)v4);
  autoport_proof::publish("hdr_defect_5_sites_three_configs", (uint64_t)v5);
  autoport_proof::publish("hdr_defect_6_intermediate_narrowing", (uint64_t)v6);
  if (autoport_proof::feature_is(kItemId)) {
    autoport_proof::publish("hdr_defect_5_sites_two_configs", (uint64_t)v5);
  }
  autoport_proof::publish("origin_bitexact_defects", (uint64_t)bitexact);
  // LES DIAGNOSTICS MIPMAP/POLICE DE `origin_bitexact_defects`, ET POURQUOI ILS SONT ICI.
  // Un zero de porte ne dit rien sans les grandeurs qui prouvent que les gardes ont TIRE et que
  // la couverture est celle qu'on annonce. `origin_mipmap_suppressed` compte le site mipmap
  // que l'essai 2 a ramene sous le maitre : a zero, la porte serait verte parce que la
  // condition est absente, pas parce que le defaut est corrige.
  // `origin_font_master_bypass` compte l'inverse — la page de police
  // resolue MAITRE ETEINT — et il est NON NUL par decision : le banc de texte et les chasses
  // Urbanist vivent dans la donnee partagee par les deux binaires, la police n'est donc pas
  // gatable et n'est PAS couverte par cette porte (voir `is_font_atlas` et `origin_ablate.h`).
  autoport_proof::publish("origin_mipmap_suppressed", direct_renderer_origin_mipmap_suppressed());
  autoport_proof::publish("origin_font_master_bypass", custom_tex::font_master_bypass_count());
  autoport_proof::publish("hdr_tonemap_defects", (uint64_t)(v1 + v2 + v3 + v4 + v5 + v6));
  // Les denominateurs des verdicts 3 et 5, sans lesquels leur zero est une fausse constante.
  autoport_proof::publish("hdr_curve_samples", s_curve_samples);
  autoport_proof::publish("hdr_curve_kink_max_x1000", s_curve_kink_max_x1000);
  autoport_proof::publish("hdr_curve_monotone_bad", (uint64_t)s_curve_mono_bad);
  autoport_proof::publish("hdr_curve_unbounded_bad", (uint64_t)s_curve_bound_bad);
  autoport_proof::publish("hdr_curve_mode", (uint64_t)Gfx::g_global_settings.recharged_hdr_curve);
  autoport_proof::publish("hdr_cfg_frames_origine_total", s_cfg_frames[1]);
  autoport_proof::publish("hdr_cfg_frames_recharged", s_cfg_frames[2]);
  autoport_proof::publish("hdr_cfg_frames_origine_lumiere", s_cfg_frames[3]);
  autoport_proof::publish("hdr_cfg_bad_origine_total", s_cfg_bad[1]);
  autoport_proof::publish("hdr_cfg_bad_recharged", s_cfg_bad[2]);
  autoport_proof::publish("hdr_cfg_bad_origine_lumiere", s_cfg_bad[3]);
  autoport_proof::publish("hdr_cfg_bad_first_frame", s_bad_first_frame);
  autoport_proof::publish("hdr_cfg_bad_first_cfg", s_bad_first_cfg);
  autoport_proof::publish("hdr_cfg_bad_first_sites", s_bad_first_sites);
  autoport_proof::publish("hdr_cfg_bad_first_draw", s_bad_first_draw);
  autoport_proof::publish("hdr_cfg_bad_first_fmt8", s_bad_first_fmt8);
  autoport_proof::publish("hdr_cfg_bad_first_shader", s_bad_first_shader);
  autoport_proof::publish("hdr_lighting_on", Gfx::recharged_lighting_active() ? 1 : 0);
}

}  // namespace hdr
