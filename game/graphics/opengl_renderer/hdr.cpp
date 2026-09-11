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
#include "game/graphics/gl_query_census.h"
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
// L'ETUDE (`hdr-study`). Elle ne change RIEN au rendu : elle a besoin des memes INSTRUMENTS.
// La sonde de marge ci-dessous ne tournait que sous `lighting-hdr` ; sous tout autre item elle
// rendait `hdr_probe_px=0 / hdr_overbright_px=0 / hdr_probe_state=1`, c'est-a-dire « la scene ne
// depasse jamais 1,0 » et « la sonde n'a jamais tourne » AU MEME ENDROIT DU PROOF. Les seize
// preuves appareil de `hdr-display-output` portent ce zero ambigu : aucune ne mesure la plage du
// tampon de calcul, qui est precisement la question de l'etude.
constexpr const char* kStudyId = "hdr-study";

// Le harnais mesure-t-il un item qui a besoin de ces instruments ? JAMAIS consulte pour decider
// de ce que le jeu DESSINE : seulement pour allumer une sonde ou publier une grandeur.
// LE PLAN (`hdr-plan`). Meme raison que l'etude : il ne change RIEN au rendu, il a besoin des
// memes INSTRUMENTS. Sans cette branche, la sonde de marge ci-dessous ne tourne pas sous cet
// item et son proof porterait `hdr_probe_state=1` — « la sonde n'a jamais tourne » — a la place
// de la seule mesure qui etablit que le tampon de calcul contient vraiment de la marge.
constexpr const char* kPlanId = "hdr-plan";

// LE CHANTIER A (`hdr-source-range`). Contrairement aux trois ci-dessus, celui-ci CHANGE le
// rendu : il eleve le ciel et le halo en flottant. Son regime est donc epingle deux fois — le
// maitre Recharged allume (sous maitre eteint le rendu d'origine doit rester identique au bit)
// et le bras arme (c'est lui que `proof_run.sh --off` renverse pour donner le AVANT).
constexpr const char* kSourceRangeId = "hdr-source-range";

bool instrumented() {
  return autoport_proof::feature_is(kItemId) || autoport_proof::feature_is(kStudyId) ||
         autoport_proof::feature_is(kPlanId);
}

// Le harnais mesure-t-il le chantier A ? Ne decide QUE de la publication du bloc `hdr_src_*`
// et du `hits=` de cet item — jamais de ce que le jeu dessine (ca, c'est `source_range_active`).
bool source_range_measuring() {
  return autoport_proof::feature_is(kSourceRangeId);
}

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

// ------------------------------------------------- recensement des ENTREES (chantier hdr-plan) --
// Une entree = une cible que NOUS creons et qui alimente le chemin de scene. On retient son
// format DEMANDE, sa taille, et le nombre de cibles identiques. La cle est le nom : un
// redimensionnement REMPLACE l'entree, il n'en ajoute pas une seconde.
struct InputSource {
  GLenum fmt = 0;
  int w = 0, h = 0, count = 0;
  int bits = 0;             // bits par canal, 0 = format hors table (defaut d'instrument)
  uint64_t bytes = 0;
  // chantier A : cette entree est-elle un ETAGE (une cible dont le CONTENU est compose par le
  // moteur, et dont le format decide si la composition a le droit de depasser 1,0) ?
  bool stage = false;
};
std::map<std::string, InputSource> s_inputs;
std::string s_input_list_cache;

// Bits par canal et octets par texel du format DEMANDE. La table est explicite et courte : un
// format absent rend 0 bit, ce qui fait monter `sources_unknown` au lieu de se faire passer pour
// du 8 bits. Un recensement qui devine est un recensement qui ment.
void format_depth(GLenum fmt, int* bits, int* bytes_per_texel) {
  switch (fmt) {
    case GL_R8:
    case GL_RED:            *bits = 8;  *bytes_per_texel = 1; return;
    case GL_RG8:            *bits = 8;  *bytes_per_texel = 2; return;
    case GL_RGB:
    case GL_RGB8:           *bits = 8;  *bytes_per_texel = 3; return;
    case GL_RGBA:
    case GL_RGBA8:          *bits = 8;  *bytes_per_texel = 4; return;
    case GL_R16F:           *bits = 16; *bytes_per_texel = 2; return;
    case GL_RG16F:          *bits = 16; *bytes_per_texel = 4; return;
    case GL_RGBA16F:        *bits = 16; *bytes_per_texel = 8; return;
    case GL_RGB10_A2:       *bits = 10; *bytes_per_texel = 4; return;
    case GL_R11F_G11F_B10F: *bits = 11; *bytes_per_texel = 4; return;
    default:                *bits = 0;  *bytes_per_texel = 0; return;
  }
}

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
    // Les formats des ENTREES du chemin de scene (recensement `hdr-plan`). Sans eux la liste
    // publiee rendait « autre » pour le ciel comme pour l'occlusion ambiante : un lecteur ne
    // pouvait pas dire laquelle des deux est en 8 bits.
    case GL_R8:
      return "R8";
    case GL_RED:
      return "RED";
    case GL_RG8:
      return "RG8";
    case GL_RGB:
      return "RGB";
    case GL_RGB8:
      return "RGB8";
    case GL_RGBA:
      return "RGBA";
    case GL_R16F:
      return "R16F";
    case GL_RG16F:
      return "RG16F";
    case GL_RGB10_A2:
      return "RGB10_A2";
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
  if (instrumented() && s_frames % 30 == 0) {
    autoport_proof::publish_text("hdr_exposure_x1000",
                                 std::to_string(std::llround(effective_exposure * 1000.f)).c_str());
  }
  glUniform1f(glGetUniformLocation(shader.id(), "u_hdr_knee"),
              Gfx::g_global_settings.recharged_hdr_knee);
  glUniform1i(glGetUniformLocation(shader.id(), "u_hdr_curve"),
              Gfx::g_global_settings.recharged_hdr_curve);
  // hdr-display-output : les QUATRE parametres de la courbe. Plafond 1,0 et aucune expansion
  // tant que la surface est SDR (identite stricte avec ce qui precede) ; quand la sortie HDR est
  // ACTIVE, le plafond vient de la marge de l'ecran et les trois autres du CONTENU de la scene.
  hdr_output::push_tonemap_uniforms(shader);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  // hdr-display-output : l'analyse de scene (PRODUCTION, une image sur huit, lecture asynchrone)
  // — c'est elle qui fait suivre la courbe a la scene. Restaure dst_fbo + viewport.
  hdr_output::analyze_scene(shader, dst_fbo, dst_w, dst_h);
  // hdr-display-output : sondes de preuve seulement — rejouent CE programme hors ecran (bras SDR
  // / bras HDR, et sur du jeu reel le bras REFUSE du 10/09) ; restaurent dst_fbo + viewport.
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

void note_input_source(const char* name, GLenum internal_fmt, int w, int h, int count) {
  if (!name || !name[0] || w <= 0 || h <= 0 || count <= 0) {
    return;  // un appel degenere ne doit pas creer une entree qui ment sur sa taille
  }
  InputSource e;
  e.fmt = internal_fmt;
  e.w = w;
  e.h = h;
  e.count = count;
  int bpt = 0;
  format_depth(internal_fmt, &e.bits, &bpt);
  e.bytes = (uint64_t)w * (uint64_t)h * (uint64_t)count * (uint64_t)bpt;
  s_inputs[name] = e;
}

void note_input_source_indexed(const char* name, int index, GLenum internal_fmt, int w, int h) {
  if (!name || !name[0]) {
    return;
  }
  const std::string key = std::string(name) + "-" + std::to_string(index);
  note_input_source(key.c_str(), internal_fmt, w, h, 1);
}

InputCensus input_census() {
  InputCensus c;
  for (const auto& [name, e] : s_inputs) {
    (void)name;
    c.sources_seen++;
    c.bytes_total += e.bytes;
    if (e.bits == 0) {
      c.sources_unknown++;
    } else if (e.bits == 8) {
      c.sources_8bit++;
      c.bytes_8bit += e.bytes;
    }
  }
  return c;
}

bool input_source_seen(const char* name) {
  return name && name[0] && s_inputs.count(name) != 0;
}

const char* input_census_list() {
  s_input_list_cache.clear();
  for (const auto& [name, e] : s_inputs) {
    if (!s_input_list_cache.empty()) {
      s_input_list_cache += ",";
    }
    s_input_list_cache += name;
    s_input_list_cache += "=";
    s_input_list_cache += format_name(e.fmt);
    s_input_list_cache += ":";
    s_input_list_cache += std::to_string(e.bytes);
  }
  if (s_input_list_cache.empty()) {
    s_input_list_cache = "-";  // publish_text garde la derniere valeur si on lui passe du vide
  }
  return s_input_list_cache.c_str();
}

// ============================ CHANTIER A — `hdr-source-range` ================================
// Le ciel et le halo cessent d'ecreter a 1,0. Tout ce qui suit est de ce chantier.

namespace {
// Le halo, relu au dernier etage de reduction. Ce sont des compteurs, pas des verdicts.
uint64_t s_glow_px = 0, s_glow_overbright = 0, s_glow_max_x1000 = 0, s_glow_frames = 0;
// Publie decale de +2 sous `hdr_src_glow_state` : 0 = cible 8 bits (rien a compter),
// 1 = relecture refusee par le pilote, 2 = jamais tente, 3 = a tourne.
int s_glow_state = 0;
// Le ciel CPU, compte AU SITE DE L'ADDITION — la ou `_mm_adds_epu8` saturait.
uint64_t s_sky_px = 0, s_sky_overbright = 0, s_sky_max_x1000 = 0;
uint64_t s_sky_differs = 0, s_sky_max_diff_x1000 = 0;
uint64_t s_stage_fallbacks = 0;
std::string s_stage_list_cache, s_clamped_list_cache, s_excluded_list_cache;
uint64_t s_src_frames = 0;
}  // namespace

bool source_range_active() {
  // DEUX termes, MEME branche : le regime (maitre Recharged) et le bras (ablation). Le second
  // seul laisserait le bras desarme indistinguable d'une course a maitre eteint.
  return Gfx::recharged_master_active() && autoport_proof::armed_for(kSourceRangeId);
}

StageFormat source_stage_format(GLenum legacy_internal, GLenum legacy_ext, GLenum legacy_type) {
  StageFormat f;
  if (source_range_active()) {
    // RGBA16F est le SEUL candidat sur GLES 3.2 : il y est color-renderable de droit, alors que
    // RGBA32F exige EXT_color_buffer_float et que R11F_G11F_B10F n'a pas d'alpha (six sites du
    // moteur utilisent GL_DST_ALPHA — voir l'echelle de repli du tampon de scene plus haut).
    // Un format DIMENSIONNE est obligatoire : GLES refuse un flottant non dimensionne.
    f.internal_fmt = GL_RGBA16F;
    f.ext_fmt = GL_RGBA;
    f.type = GL_HALF_FLOAT;
    f.is_float = true;
    return f;
  }
  f.internal_fmt = legacy_internal;
  f.ext_fmt = legacy_ext;
  f.type = legacy_type;
  f.is_float = false;
  return f;
}

void note_scene_stage(const char* name, GLenum internal_fmt, int w, int h, int count) {
  note_input_source(name, internal_fmt, w, h, count);
  auto it = s_inputs.find(name ? name : "");
  if (it != s_inputs.end()) {
    it->second.stage = true;
  }
}

void note_scene_stage_indexed(const char* name, int index, GLenum internal_fmt, int w, int h) {
  if (!name || !name[0]) {
    return;
  }
  const std::string key = std::string(name) + "-" + std::to_string(index);
  note_scene_stage(key.c_str(), internal_fmt, w, h, 1);
}

void note_stage_fallback(const char* name) {
  // Le nom sert au journal : l'appelant replie AVANT de recenser, donc l'entree n'existe pas
  // encore. C'est le COMPTE qui est publie, et le format effectif recense juste apres le dira.
  lg::warn("[hdr-source-range] flottant refuse par le pilote pour {}", name ? name : "?");
  s_stage_fallbacks++;
}

void note_sky_wide(uint64_t over_px,
                   uint64_t differs_px,
                   uint64_t seen_px,
                   uint64_t max_x1000,
                   uint64_t max_diff_x1000) {
  s_sky_px += seen_px;
  s_sky_overbright += over_px;
  s_sky_differs += differs_px;
  if (max_x1000 > s_sky_max_x1000) {
    s_sky_max_x1000 = max_x1000;
  }
  if (max_diff_x1000 > s_sky_max_diff_x1000) {
    s_sky_max_diff_x1000 = max_diff_x1000;
  }
}

void probe_glow(GLuint fbo, int w, int h, GLenum fmt) {
  // Relecture DIRECTE du dernier etage (40x40 par defaut) : pas de blit, pas de passe ajoutee.
  // Hors flottant il n'y a rien a mesurer — la cible ne peut pas porter plus de 1,0 — et on le
  // dit par `hdr_src_glow_state`, jamais par un zero muet.
  if (!source_range_measuring() || w <= 0 || h <= 0 || (size_t)w * h > 65536u) {
    return;
  }
  if (!format_is_float(fmt)) {
    s_glow_state = -2;  // cible 8 bits : l'instrument a tourne, il n'y avait rien a compter
    return;
  }
  if ((s_frames % kProbeEvery) != 0) {
    return;
  }
  gl_query_census::Armed _ap("hdr-src-glow-probe");
  // On RESTAURE la liaison : cette sonde s'insere au milieu d'une passe de rendu, et une cible
  // laissee liee rend une image noire dont la cause ne ressemble pas a sa cause.
  GLint old_read = 0, old_draw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &old_draw);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
  GLint read_fmt = 0, read_type = 0;
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &read_fmt);
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &read_type);
  const size_t n = (size_t)w * (size_t)h * 4;
  std::vector<float> px;
  bool ok = false;
  if (read_fmt == GL_RGBA && read_type == GL_HALF_FLOAT) {
    std::vector<uint16_t> raw(n);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_HALF_FLOAT, raw.data());
    ok = (glGetError() == GL_NO_ERROR);
    px.resize(n);
    for (size_t i = 0; i < n; i++) {
      px[i] = half_to_float(raw[i]);
    }
  } else {
    px.resize(n);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_FLOAT, px.data());
    ok = (glGetError() == GL_NO_ERROR);
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)old_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)old_draw);
  if (!ok) {
    s_glow_state = -1;
    return;
  }
  s_glow_state = 1;
  s_glow_frames++;
  for (size_t i = 0; i + 3 < px.size(); i += 4) {
    s_glow_px++;
    float mx = 0.f;
    for (int c = 0; c < 3; c++) {
      const float v = px[i + c];
      if (std::isfinite(v) && v > mx) {
        mx = v;
      }
    }
    if (mx > 1.f) {
      s_glow_overbright++;
    }
    const uint64_t mx1000 = (uint64_t)(mx * 1000.f + 0.5f);
    if (mx1000 > s_glow_max_x1000) {
      s_glow_max_x1000 = mx1000;
    }
  }
}

namespace {
// LA PORTE. Elle compte les ETAGES qui ecretent, et publie DANS LE MEME SOUFFLE le denominateur
// (`hdr_src_stages_seen`), la liste des etages, celle des coupables, et le seau EXCLU nomme.
// Un zero sur un denominateur nul n'est pas « aucun ecretage » : c'est « rien inspecte », et
// c'est la faute que cette publication rend impossible a commettre en silence.
void publish_source_range() {
  if (!source_range_measuring()) {
    return;  // instrument : muet hors de la mesure de CET item
  }
  s_src_frames++;
  if ((s_src_frames % 30) != 1) {
    return;
  }
  uint64_t stages_seen = 0, stages_clamped = 0, stages_float = 0, excluded = 0;
  uint64_t stage_bytes = 0;
  s_stage_list_cache.clear();
  s_clamped_list_cache.clear();
  s_excluded_list_cache.clear();
  for (const auto& [name, e] : s_inputs) {
    std::string entry = name + "=" + format_name(e.fmt);
    if (!e.stage) {
      excluded++;
      if (!s_excluded_list_cache.empty()) {
        s_excluded_list_cache += ",";
      }
      s_excluded_list_cache += entry;
      continue;
    }
    stages_seen++;
    stage_bytes += e.bytes;
    if (!s_stage_list_cache.empty()) {
      s_stage_list_cache += ",";
    }
    s_stage_list_cache += entry;
    if (format_is_float(e.fmt)) {
      stages_float++;
    } else {
      stages_clamped++;
      if (!s_clamped_list_cache.empty()) {
        s_clamped_list_cache += ",";
      }
      s_clamped_list_cache += entry;
    }
  }
  // LE GESTE DE CE CHANTIER : `note_hit` ne compte que sous le bras ARME, c'est ce qui rend
  // l'ablation lisible (`armed=0 hits=0`). `hits` est partage par tout le binaire : on ne
  // l'incremente que sous notre propre item.
  autoport_proof::note_hit();

  autoport_proof::publish("hdr_src_clamped_stages", stages_clamped);
  autoport_proof::publish("hdr_src_stages_seen", stages_seen);
  autoport_proof::publish("hdr_src_stages_float", stages_float);
  autoport_proof::publish("hdr_src_stage_bytes", stage_bytes);
  autoport_proof::publish("hdr_src_stage_fallbacks", s_stage_fallbacks);
  autoport_proof::publish_text("hdr_src_stages_list",
                               s_stage_list_cache.empty() ? "-" : s_stage_list_cache.c_str());
  autoport_proof::publish_text("hdr_src_clamped_list",
                               s_clamped_list_cache.empty() ? "-" : s_clamped_list_cache.c_str());
  autoport_proof::publish("hdr_src_excluded", excluded);
  autoport_proof::publish_text("hdr_src_excluded_list",
                               s_excluded_list_cache.empty() ? "-" : s_excluded_list_cache.c_str());

  // LE REGIME, PUBLIE A COTE DU VERDICT. Un `clamped_stages=0` obtenu maitre ETEINT serait
  // obtenu par INACTION (rien n'est converti, mais rien n'est recense non plus).
  autoport_proof::publish("hdr_src_master_on", Gfx::recharged_master_active() ? 1 : 0);
  autoport_proof::publish("hdr_src_armed", autoport_proof::armed_for(kSourceRangeId) ? 1 : 0);
  autoport_proof::publish("hdr_src_active", source_range_active() ? 1 : 0);
  autoport_proof::publish_text("hdr_src_scene_fmt", format_name(scene_color_format()));

  // LE DENOMINATEUR QUE L'ITEM EXIGE. Sous cet item `planning()` est faux, donc hdr_output ne
  // publie AUCUNE cle `hdr_plan_*` : ce bloc est le seul ecrivain, il n'y a pas de course.
  const InputCensus ic = input_census();
  autoport_proof::publish("hdr_plan_s2_sources_seen", ic.sources_seen);
  autoport_proof::publish("hdr_plan_s2_sources_8bit", ic.sources_8bit);
  autoport_proof::publish("hdr_plan_s2_sources_unknown", ic.sources_unknown);
  autoport_proof::publish("hdr_plan_s2_bytes_total", ic.bytes_total);
  autoport_proof::publish("hdr_plan_s2_bytes_8bit", ic.bytes_8bit);
  autoport_proof::publish_text("hdr_plan_s2_list", input_census_list());

  // LA PLAGE REELLEMENT GAGNEE, mesuree des DEUX cotes du chantier, publiee separement. Le ciel
  // est compte au site de l'addition CPU ; le halo est relu sur son dernier etage.
  autoport_proof::publish("hdr_src_sky_px", s_sky_px);
  autoport_proof::publish("hdr_src_sky_overbright_px", s_sky_overbright);
  autoport_proof::publish("hdr_src_sky_max_x1000", s_sky_max_x1000);
  // LE TEMOIN D'EFFET. `overbright` peut valoir zero parce que la scene n'a rien au-dessus du
  // blanc ; `differs` ne peut valoir zero que si le conteneur ne change RIEN. Les deux sont
  // publies avec le meme denominateur `hdr_src_sky_px`.
  autoport_proof::publish("hdr_src_sky_differs_px", s_sky_differs);
  autoport_proof::publish("hdr_src_sky_max_diff_x1000", s_sky_max_diff_x1000);
  autoport_proof::publish("hdr_src_glow_px", s_glow_px);
  autoport_proof::publish("hdr_src_glow_overbright_px", s_glow_overbright);
  autoport_proof::publish("hdr_src_glow_max_x1000", s_glow_max_x1000);
  autoport_proof::publish("hdr_src_glow_frames", s_glow_frames);
  autoport_proof::publish("hdr_src_glow_state", (uint64_t)(s_glow_state + 2));
  // `hdr_overbright_px` que l'item reclame : le HALO, et rien d'autre. Sous cet item la sonde de
  // scene de `lighting-hdr` ne tourne pas (`instrumented()` ne nomme pas cet item), donc la
  // valeur qu'elle publierait plus bas serait un zero d'INACTION. Un seul ecrivain par cle.
  autoport_proof::publish("hdr_overbright_px", s_glow_overbright);
}
}  // namespace

ChainCensus chain_census() {
  ChainCensus c;
  c.progs_scanned = s_progs.size();
  for (const auto& [name, info] : s_progs) {
    (void)name;
    if (info.oetf_occurrences > 0) {
      c.oetf_progs++;
    }
  }
  c.tonemap_draws = s_tonemap_draws;
  c.frames = s_frames;
  c.chain_frames = s_chain_frames;
  c.probe_px = s_probe_px;
  c.overbright_px = s_probe_overbright;
  c.probe_max_x1000 = s_probe_max_x1000;
  c.probe_state = s_probe_state;
  c.ladder_step = s_ladder_step;
  return c;
}

void note_aux_scene_read(const char* site, GLenum src_fmt, GLenum dst_fmt) {
  auto& e = s_aux_sites[site ? site : "?"];
  e.count++;
  if (format_is_float(src_fmt) && !format_is_float(dst_fmt)) {
    e.narrowed = true;
  }
}

void probe_scene(GLuint scene_fbo, int w, int h, GLenum fmt) {
  if (!instrumented() || !format_is_float(fmt)) {
    return;  // instrument : ne tourne que sous mesure, et seulement sur un tampon flottant
  }
  if ((s_frames % kProbeEvery) != 0) {
    return;
  }
  gl_query_census::Armed _ap("hdr-overbright-probe");
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
  // AVANT le repli de `lighting-hdr` : ce bloc-ci a son propre item, son propre bras, et il doit
  // publier meme quand l'autre est desarme.
  publish_source_range();
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
  // UN SEUL ECRIVAIN PAR CLE. Sous `hdr-source-range`, cette sonde-ci ne tourne pas
  // (`instrumented()` ne nomme pas cet item) : elle publierait un zero d'INACTION a la place de
  // la mesure du halo. C'est le bloc du chantier A qui ecrit la cle dans ce regime-la.
  if (!source_range_measuring()) {
    autoport_proof::publish("hdr_overbright_px", s_probe_overbright);
  }
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
