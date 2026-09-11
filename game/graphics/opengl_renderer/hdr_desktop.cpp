#include "game/graphics/opengl_renderer/hdr_desktop.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/graphics/opengl_renderer/hdr_output.h"
#include "game/graphics/pipelines/opengl.h"
#include "game/system/autoport_proof.h"

#include "third-party/SDL/include/SDL3/SDL.h"

#if defined(__linux__) || defined(__APPLE__)
#include <dlfcn.h>
#endif

namespace hdr_desktop {
namespace {

// ------------------------------------------------------------------------------ EGL a nu --
// Les valeurs et les signatures EGL sont reprises ici plutot qu'incluses : le binaire de bureau
// ne lie PAS libEGL (il peut tourner sur GLX ou WGL, ou aucune n'existe), et un en-tete qui
// declare des symboles avec `__declspec(dllimport)` ferait echouer le lien sous Windows. On
// charge la bibliotheque a la demande, et son absence est un resultat publie, pas une panne.
using EGLDisplayT = void*;
using EGLSurfaceT = void*;
using EGLConfigT = void*;
using EGLint32 = int32_t;

constexpr int kEglNone = 0x3038;
constexpr int kEglExtensions = 0x3055;
constexpr int kEglWindowBit = 0x0004;
constexpr int kEglPbufferBit = 0x0001;
constexpr int kEglSurfaceType = 0x3033;
constexpr int kEglRedSize = 0x3024;
constexpr int kEglGreenSize = 0x3023;
constexpr int kEglBlueSize = 0x3022;
constexpr int kEglAlphaSize = 0x3021;
constexpr int kEglRenderableType = 0x3040;
constexpr int kEglOpenglBit = 0x0008;
constexpr int kEglOpenglEs2Bit = 0x0004;
constexpr int kEglWidth = 0x3057;
constexpr int kEglHeight = 0x3056;
constexpr int kEglSuccess = 0x3000;
// EGL_KHR_gl_colorspace et les trois espaces HDR (memes valeurs que android_renderer.cpp).
constexpr int kEglColorspace = 0x309D;
constexpr int kEglColorspaceLinear = 0x308A;
constexpr int kEglColorspaceSrgb = 0x3089;
constexpr int kEglColorspaceBt2020Pq = 0x3340;
constexpr int kEglColorspaceScrgbLinear = 0x3350;
constexpr int kEglColorspaceBt2020Hlg = 0x3540;
// EGL_EXT_pixel_format_float
constexpr int kEglColorComponentType = 0x3339;
constexpr int kEglColorComponentTypeFloat = 0x333B;
// EGL_EXT_surface_SMPTE2086_metadata / EGL_EXT_surface_CTA861_3_metadata
constexpr int kEglMetadataScaling = 50000;
constexpr int kEglSmpte2086Rx = 0x3341;
constexpr int kEglSmpte2086Ry = 0x3342;
constexpr int kEglSmpte2086Gx = 0x3343;
constexpr int kEglSmpte2086Gy = 0x3344;
constexpr int kEglSmpte2086Bx = 0x3345;
constexpr int kEglSmpte2086By = 0x3346;
constexpr int kEglSmpte2086Wx = 0x3347;
constexpr int kEglSmpte2086Wy = 0x3348;
constexpr int kEglSmpte2086MaxLum = 0x3349;
constexpr int kEglSmpte2086MinLum = 0x334A;
constexpr int kEglCta861MaxCll = 0x3360;
constexpr int kEglCta861MaxFall = 0x3361;

struct EglApi {
  bool loaded = false;
  SDL_SharedObject* lib = nullptr;
  EGLDisplayT (*GetDisplay)(void*) = nullptr;
  unsigned (*Initialize)(EGLDisplayT, EGLint32*, EGLint32*) = nullptr;
  const char* (*QueryString)(EGLDisplayT, EGLint32) = nullptr;
  unsigned (*ChooseConfig)(EGLDisplayT, const EGLint32*, EGLConfigT*, EGLint32, EGLint32*) =
      nullptr;
  EGLSurfaceT (*CreatePbufferSurface)(EGLDisplayT, EGLConfigT, const EGLint32*) = nullptr;
  unsigned (*DestroySurface)(EGLDisplayT, EGLSurfaceT) = nullptr;
  unsigned (*QuerySurface)(EGLDisplayT, EGLSurfaceT, EGLint32, EGLint32*) = nullptr;
  unsigned (*SurfaceAttrib)(EGLDisplayT, EGLSurfaceT, EGLint32, EGLint32) = nullptr;
  EGLint32 (*GetError)() = nullptr;
};

EglApi s_egl;

bool load_egl() {
  if (s_egl.loaded) {
    return s_egl.lib != nullptr;
  }
  s_egl.loaded = true;
#if defined(_WIN32)
  const char* names[] = {"libEGL.dll", "EGL.dll"};
#elif defined(__APPLE__)
  const char* names[] = {"libEGL.dylib"};
#else
  const char* names[] = {"libEGL.so.1", "libEGL.so"};
#endif
  for (const char* n : names) {
    s_egl.lib = SDL_LoadObject(n);
    if (s_egl.lib) {
      break;
    }
  }
  if (!s_egl.lib) {
    return false;
  }
  auto sym = [](const char* n) { return (void*)SDL_LoadFunction(s_egl.lib, n); };

  s_egl.GetDisplay = (decltype(s_egl.GetDisplay))sym("eglGetDisplay");
  s_egl.Initialize = (decltype(s_egl.Initialize))sym("eglInitialize");
  s_egl.QueryString = (decltype(s_egl.QueryString))sym("eglQueryString");
  s_egl.ChooseConfig = (decltype(s_egl.ChooseConfig))sym("eglChooseConfig");
  s_egl.CreatePbufferSurface = (decltype(s_egl.CreatePbufferSurface))sym("eglCreatePbufferSurface");
  s_egl.DestroySurface = (decltype(s_egl.DestroySurface))sym("eglDestroySurface");
  s_egl.QuerySurface = (decltype(s_egl.QuerySurface))sym("eglQuerySurface");
  s_egl.SurfaceAttrib = (decltype(s_egl.SurfaceAttrib))sym("eglSurfaceAttrib");
  s_egl.GetError = (decltype(s_egl.GetError))sym("eglGetError");
  const bool ok = s_egl.GetDisplay && s_egl.Initialize && s_egl.QueryString;
  if (!ok) {
    s_egl.lib = nullptr;
  }
  return ok;
}

// ------------------------------------------------------------------------------- l'etat --

bool s_measuring_cache_valid = false;
bool s_measuring_cache = false;

bool measuring() {
  if (!s_measuring_cache_valid) {
    s_measuring_cache_valid = true;
    s_measuring_cache =
        autoport_proof::feature_is(kItemId) && autoport_proof::armed_for(kItemId);
  }
  return s_measuring_cache;
}

SDL_Window* s_window = nullptr;
EGLDisplayT s_probe_dpy = nullptr;   // le display sonde AVANT la fenetre (extensions, configs)
bool s_egl_probed = false;
bool s_sdl_probed = false;
bool s_platform_info_set = false;
bool s_want_hdr = false;             // le reglage persiste / le knob
bool s_forced_egl = false;
uint32_t s_planned_mode = hdr_output::kModeNone;   // ce qu'on a DEMANDE a la creation
uint32_t s_created_mode = hdr_output::kModeNone;   // ce qu'on a OBTENU, relu sur la surface
int s_requested_colorspace = 0;
int s_obtained_colorspace = 0;
hdr_output::PlatformCaps s_caps;
std::string s_egl_exts_text = "non_sonde";
std::string s_gl_backend = "inconnu";
std::string s_switch_reason = "aucune_demande";

// Ce que le PILOTE a repondu a une demande de colorspace reellement emise. -1 = pas demande.
int s_req_pq = -1, s_req_pq_err = 0;
int s_req_scrgb = -1, s_req_scrgb_err = 0;
uint64_t s_requests_issued = 0;
std::string s_req_pq_reason = "pas_demande", s_req_scrgb_reason = "pas_demande";

// Metadonnees statiques HDR10.
int s_md_maxcll = 0, s_md_maxfall = 0, s_md_maxlum = 0, s_md_minlum_x10000 = 0;
uint64_t s_md_calls = 0, s_md_posted = 0;
std::string s_md_reason = "pas_de_transport_pq";

// Compteurs de vie.
uint64_t s_frames = 0, s_active_frames = 0, s_forced_on = 0;
uint64_t s_sdr_frames_bad = 0, s_fmt_bad = 0, s_gl_errors = 0;
uint64_t s_present_calls = 0, s_curve_calls = 0;
std::string s_curve_symbol = "non_resolu";
std::string s_curve_module = "non_resolu";
// VERDICT 5, AU POINT DE LECTURE. On relit sur le PROGRAMME, apres le vrai quad final de l'image,
// les trois uniformes que `hdr_output::push_present_uniforms()` vient d'y poser — c'est le chemin
// que l'appareil emprunte aussi — et on les compare a ce que `present_params_for()` rend ici. Un
// chemin de presentation recopie cote bureau divergerait ; le meme code ne peut pas. C'est une
// lecture de ce que le GPU a RECU, pas de nos propres variables.
uint64_t s_uniform_match = 0, s_uniform_mismatch = 0;
int s_live_out_mode = -1;

// ------------------------------------------------------------------- la repetition d'encodage --
// « la courbe exercee a deux pics SIMULES » : on rejoue le VRAI quad final, avec les VRAIS
// parametres que `hdr_output::present_params_for()` rend, sur une rampe connue, vers une cible au
// format REEL du transport (RGB10_A2 en PQ, RGBA16F en scRGB) — et on relit ce qui en sort. Rien
// ici ne regarde l'ecran : ce qui est mesure, c'est NOTRE encodage.
constexpr int kRampN = 128;
constexpr int kTexN = kRampN + 2;     // texel 0 = noir, texel 1 = blanc (l'ancre), puis la rampe
constexpr float kRampLow = 15.f / 16.f;
constexpr int kSimWhiteNits = 203;    // BT.2408 : le blanc graphique du PQ
constexpr int kSimPeakLo = 500;
constexpr int kSimPeakHi = 2000;

struct Leg {
  bool done = false;
  int peak = 0;
  int levels = 0;          // niveaux DISTINCTS que la sortie sait encore separer dans la rampe
  int white_x1000 = 0;     // le blanc du jeu, en MILLIEMES du blanc SDR de l'ecran
  int hl_x1000 = 0;        // la plus haute lumiere encodee, en milliemes du blanc SDR
  int ceiling_x1000 = 0;   // le plafond que la courbe a retenu pour ce pic
  int paper_white = 0;     // ce que le quad a recu (nits en PQ, x1000 en scRGB)
};
Leg s_pq_lo, s_pq_hi, s_scrgb;
int s_off_mismatch = 0, s_off_px = 0;
int s_reh_step = 0;        // 0 = OFF, 1 = PQ bas, 2 = PQ haut, 3 = scRGB, 4 = fini
bool s_reh_failed = false;

GLuint s_src_tex = 0;
GLuint s_fbo = 0, s_fbo_tex = 0;
GLenum s_fbo_fmt = 0;

// Les huit verdicts, et la somme.
int s_d[9] = {0};
int s_defects = 8;
bool s_verdicts_done = false;

double pq_eotf_nits(double e) {
  const double m1 = 0.1593017578125, m2 = 78.84375;
  const double c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
  const double ep = std::pow(std::max(e, 0.0), 1.0 / m2);
  const double num = std::max(ep - c1, 0.0);
  const double den = c2 - c3 * ep;
  if (!(den > 0.0)) {
    return 0.0;
  }
  return 10000.0 * std::pow(num / den, 1.0 / m1);
}

// ------------------------------------------------------------------------ sonde des couches --

void probe_egl_layer() {
  s_egl_probed = true;
  if (!load_egl()) {
    s_egl_exts_text = "aucune_libegl_sur_cette_plateforme";
    return;
  }
  s_probe_dpy = s_egl.GetDisplay(nullptr);  // EGL_DEFAULT_DISPLAY
  if (!s_probe_dpy) {
    s_egl_exts_text = "eglGetDisplay=EGL_NO_DISPLAY";
    return;
  }
  EGLint32 maj = 0, min_ = 0;
  if (!s_egl.Initialize(s_probe_dpy, &maj, &min_)) {
    s_egl_exts_text = "eglInitialize_refuse";
    s_probe_dpy = nullptr;
    return;
  }
  // On ne fait PAS `eglTerminate` : le display par defaut est celui que SDL reprendra, et le
  // compte de references n'est pas garanti identique d'un pilote a l'autre. Un display initialise
  // de plus ne coute rien ; un display termine sous les pieds de SDL coute la fenetre.
  const char* e = s_egl.QueryString(s_probe_dpy, kEglExtensions);
  const std::string exts = e ? e : "";
  auto has = [&](const char* n) { return exts.find(n) != std::string::npos; };
  s_caps.egl_bt2020_pq = has("EGL_EXT_gl_colorspace_bt2020_pq");
  s_caps.egl_scrgb_linear = has("EGL_EXT_gl_colorspace_scrgb_linear");
  s_caps.egl_fp16 = has("EGL_EXT_pixel_format_float");
  s_caps.egl_no_config_ctx = has("EGL_KHR_no_config_context");
  s_caps.egl_smpte2086 = has("EGL_EXT_surface_SMPTE2086_metadata");
  s_caps.egl_bt2020_hlg = has("EGL_EXT_gl_colorspace_bt2020_hlg");
  s_caps.egl_cta861_3 = has("EGL_EXT_surface_CTA861_3_metadata");

  // Les CONFIGS. Annoncer une extension ne sert a rien si aucun format de fenetre ne peut la
  // porter : c'est l'erreur que `format_reason_locked` distingue deja (`pas_de_config_10bit`).
  auto count_cfg = [&](const EGLint32* attrs) {
    EGLConfigT cfg = nullptr;
    EGLint32 n = 0;
    if (!s_egl.ChooseConfig) {
      return 0;
    }
    if (!s_egl.ChooseConfig(s_probe_dpy, attrs, &cfg, 1, &n)) {
      return 0;
    }
    return (int)n;
  };
  const EGLint32 a10[] = {kEglSurfaceType,     kEglWindowBit,  kEglRedSize,        10,
                          kEglGreenSize,       10,             kEglBlueSize,       10,
                          kEglAlphaSize,       2,              kEglRenderableType, kEglOpenglBit,
                          kEglNone};
  const EGLint32 a16[] = {kEglSurfaceType,       kEglWindowBit,
                          kEglRedSize,           16,
                          kEglGreenSize,         16,
                          kEglBlueSize,          16,
                          kEglAlphaSize,         16,
                          kEglColorComponentType, kEglColorComponentTypeFloat,
                          kEglRenderableType,    kEglOpenglBit,
                          kEglNone};
  s_caps.config_10bit = count_cfg(a10) > 0;
  s_caps.config_fp16 = s_caps.egl_fp16 && count_cfg(a16) > 0;

  std::string t;
  auto add = [&](bool on, const char* n) {
    if (on) {
      if (!t.empty()) {
        t += ",";
      }
      t += n;
    }
  };
  add(s_caps.egl_bt2020_pq, "bt2020_pq");
  add(s_caps.egl_scrgb_linear, "scrgb_linear");
  add(s_caps.egl_fp16, "fp16");
  add(s_caps.egl_no_config_ctx, "no_config_ctx");
  add(s_caps.egl_smpte2086, "smpte2086");
  add(s_caps.egl_bt2020_hlg, "bt2020_hlg");
  add(s_caps.egl_cta861_3, "cta861_3");
  s_egl_exts_text = t.empty() ? "aucune_extension_hdr" : t;
  lg::info("[hdr-desktop-output] EGL {}.{} : {} ; cfg10={} cfg16f={}", (int)maj, (int)min_,
           s_egl_exts_text, s_caps.config_10bit ? 1 : 0, s_caps.config_fp16 ? 1 : 0);
}

// DEMANDER POUR DE VRAI, ET ECRIRE LA REPONSE DU PILOTE. Une extension absente de la chaine
// d'extensions est deja une reponse, mais c'est LA NOTRE : on la confronte a celle du pilote en
// lui soumettant une surface dans l'espace vise. Sur un pilote qui sait, elle est creee ; sur un
// pilote qui ne sait pas, il rend son code d'erreur, et c'est LUI qui l'a dit.
int issue_colorspace_request(int colorspace, int* egl_error, std::string* reason) {
  *egl_error = 0;
  if (!s_probe_dpy || !s_egl.ChooseConfig || !s_egl.CreatePbufferSurface) {
    *reason = "aucune_couche_egl_sur_cette_plateforme";
    return -1;
  }
  s_requests_issued++;
  const bool want_float = colorspace == kEglColorspaceScrgbLinear;
  const EGLint32 bits = want_float ? 16 : 10;
  std::vector<EGLint32> cfga = {kEglSurfaceType, kEglPbufferBit, kEglRedSize,   bits,
                                kEglGreenSize,   bits,           kEglBlueSize,  bits,
                                kEglAlphaSize,   want_float ? 16 : 2};
  if (want_float) {
    cfga.push_back(kEglColorComponentType);
    cfga.push_back(kEglColorComponentTypeFloat);
  }
  cfga.push_back(kEglNone);
  EGLConfigT cfg = nullptr;
  EGLint32 n = 0;
  if (!s_egl.ChooseConfig(s_probe_dpy, cfga.data(), &cfg, 1, &n) || n <= 0) {
    *egl_error = s_egl.GetError ? (int)s_egl.GetError() : 0;
    *reason = "le_pilote_n_a_aucune_config_a_cette_profondeur";
    return 0;
  }
  const EGLint32 surfa[] = {kEglWidth, 4, kEglHeight, 4, kEglColorspace, colorspace, kEglNone};
  EGLSurfaceT surf = s_egl.CreatePbufferSurface(s_probe_dpy, cfg, surfa);
  if (!surf) {
    *egl_error = s_egl.GetError ? (int)s_egl.GetError() : 0;
    *reason = "le_pilote_a_refuse_la_surface_dans_cet_espace";
    return 0;
  }
  int got = 0;
  if (s_egl.QuerySurface) {
    EGLint32 cs = 0;
    if (s_egl.QuerySurface(s_probe_dpy, surf, kEglColorspace, &cs)) {
      got = (int)cs;
    }
  }
  if (s_egl.DestroySurface) {
    s_egl.DestroySurface(s_probe_dpy, surf);
  }
  *egl_error = kEglSuccess;
  *reason = got == colorspace ? "-" : "surface_creee_mais_colorspace_relu_different";
  return got == colorspace ? 1 : 0;
}

// L'attribut de surface pose par SDL_EGL_CreateSurface. MEME mecanisme que l'appareil : le hint
// `SDL_HINT_OPENGL_FORCE_SRGB_FRAMEBUFFER="skip"` empeche SDL de poser lui-meme EGL_GL_COLORSPACE.
SDL_EGLint* SDLCALL surface_attribs_cb(void*, SDL_EGLDisplay, SDL_EGLConfig) {
  SDL_EGLint* a = (SDL_EGLint*)SDL_malloc(sizeof(SDL_EGLint) * 3);
  if (!a) {
    return nullptr;
  }
  a[0] = kEglColorspace;
  a[1] = s_planned_mode == hdr_output::kModeScrgbLinear ? kEglColorspaceScrgbLinear
         : s_planned_mode == hdr_output::kModeHdr10Pq   ? kEglColorspaceBt2020Pq
         : s_planned_mode == hdr_output::kModeHlg       ? kEglColorspaceBt2020Hlg
                                                        : kEglColorspaceLinear;
  a[2] = kEglNone;
  return a;
}

// ------------------------------------------------------------------------------ basculeur --
// La contrainte de bureau, honnete : le colorspace et la profondeur d'un framebuffer de fenetre
// se choisissent A LA CREATION. Le basculeur rend donc VRAI pour le mode avec lequel la fenetre
// a ete creee, et FAUX — avec une raison nommee — pour tout autre. On ne pretend jamais avoir
// bascule : `hdr_output` compte alors un `switch_fail`, et la rangee de menu dit ce qu'il faut.
bool desktop_switch(uint32_t want_mode, hdr_output::SurfaceState* out) {
  hdr_output::SurfaceState st;
  st.mode = s_created_mode;
  st.colorspace = s_obtained_colorspace;
  st.hdr = s_created_mode != hdr_output::kModeNone;
  {
    gl_query_census::Armed _ap("hdr-desktop-surface-bits");
    GLint r = 0;
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_BACK_LEFT,
                                          GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, &r);
    st.red_bits = (int)r;
  }
  *out = st;
  if (want_mode == s_created_mode) {
    s_switch_reason = "-";
    return true;
  }
  s_switch_reason = want_mode == hdr_output::kModeNone
                        ? "retour_sdr_impossible_a_chaud:redemarrage_requis"
                        : "aucune_recreation_de_surface_sur_bureau:redemarrage_requis";
  lg::warn("[hdr-desktop-output] bascule refusee vers mode={} : {}", (unsigned)want_mode,
           s_switch_reason);
  return false;
}

// ------------------------------------------------------------------------- metadonnees HDR10 --
void post_static_metadata() {
  const hdr_output::PresentParams pq = hdr_output::present_params_for(hdr_output::kModeHdr10Pq);
  // MaxCLL : la lumiere maximale que NOTRE sortie peut contenir — le blanc de reference multiplie
  // par la marge que la courbe s'autorise. C'est la grandeur que la norme demande (la lumiere du
  // CONTENU), pas le pic de la dalle : annoncer le pic de la dalle revient a dire au decodeur
  // « ne compresse rien », quelle que soit l'image.
  s_md_maxcll = (int)std::lround((double)pq.paper_white * (double)pq.headroom);
  s_md_maxfall = 0;  // aucune moyenne d'image mesuree sur ce chemin : 0 = « non renseigne »
  // SMPTE2086 decrit l'ECRAN DE MAITRISE, pas le contenu : c'est le pic annonce, celui que
  // `peak_nits()` rend. Les deux grandeurs sont distinctes et le restent.
  s_md_maxlum = (int)std::lround((double)pq.max_nits);
  s_md_minlum_x10000 = 0;
  if (s_created_mode != hdr_output::kModeHdr10Pq) {
    s_md_reason = "pas_de_transport_pq_obtenu";
    return;
  }
  if (!s_caps.egl_smpte2086 && !s_caps.egl_cta861_3) {
    s_md_reason = "egl_sans_smpte2086_ni_cta861_3";
    return;
  }
  EGLDisplayT dpy = (EGLDisplayT)SDL_EGL_GetCurrentDisplay();
  EGLSurfaceT surf = s_window ? (EGLSurfaceT)SDL_EGL_GetWindowSurface(s_window) : nullptr;
  if (!dpy || !surf || !s_egl.SurfaceAttrib) {
    s_md_reason = "pas_de_surface_egl_a_annoter";
    return;
  }
  const double k = (double)kEglMetadataScaling;
  struct Md {
    int attr;
    double v;
  };
  std::vector<Md> md;
  if (s_caps.egl_smpte2086) {
    // Primaires BT.2020, blanc D65 — les memes que le chemin appareil, a la decimale.
    md.insert(md.end(), {{kEglSmpte2086Rx, 0.708},
                         {kEglSmpte2086Ry, 0.292},
                         {kEglSmpte2086Gx, 0.170},
                         {kEglSmpte2086Gy, 0.797},
                         {kEglSmpte2086Bx, 0.131},
                         {kEglSmpte2086By, 0.046},
                         {kEglSmpte2086Wx, 0.3127},
                         {kEglSmpte2086Wy, 0.3290},
                         {kEglSmpte2086MaxLum, (double)s_md_maxlum},
                         {kEglSmpte2086MinLum, s_md_minlum_x10000 / 10000.0}});
  }
  if (s_caps.egl_cta861_3) {
    md.push_back({kEglCta861MaxCll, (double)s_md_maxcll});
    md.push_back({kEglCta861MaxFall, (double)s_md_maxfall});
  }
  for (const Md& m : md) {
    s_md_calls++;
    if (s_egl.SurfaceAttrib(dpy, surf, m.attr, (EGLint32)(m.v * k))) {
      s_md_posted++;
    } else {
      lg::warn("[hdr-desktop-output] eglSurfaceAttrib(0x{:x}) refuse : 0x{:x}", (unsigned)m.attr,
               (unsigned)(s_egl.GetError ? s_egl.GetError() : 0));
    }
  }
  s_md_reason = s_md_posted == s_md_calls ? "-" : "au_moins_un_eglSurfaceAttrib_refuse";
}

// --------------------------------------------------------------------------- la repetition --

bool make_ramp_tex(GLuint* tex, float lo, float hi) {
  std::vector<float> px((size_t)kTexN * 4, 0.f);
  px[4] = px[5] = px[6] = 1.f;  // texel 1 : le blanc du jeu, l'ancre
  px[7] = 1.f;
  px[3] = 1.f;
  for (int i = 0; i < kRampN; i++) {
    const float v = lo + (hi - lo) * ((float)i / (float)(kRampN - 1));
    const size_t o = (size_t)(i + 2) * 4;
    px[o] = px[o + 1] = px[o + 2] = v;
    px[o + 3] = 1.f;
  }
  if (!*tex) {
    glGenTextures(1, tex);
  }
  glBindTexture(GL_TEXTURE_2D, *tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, kTexN, 1, 0, GL_RGBA, GL_FLOAT, px.data());
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  return *tex != 0;
}

bool make_fbo(GLenum fmt) {
  if (s_fbo && s_fbo_fmt == fmt) {
    return true;
  }
  if (s_fbo) {
    glDeleteFramebuffers(1, &s_fbo);
    s_fbo = 0;
  }
  if (s_fbo_tex) {
    glDeleteTextures(1, &s_fbo_tex);
    s_fbo_tex = 0;
  }
  glGenTextures(1, &s_fbo_tex);
  glBindTexture(GL_TEXTURE_2D, s_fbo_tex);
  const GLenum type = fmt == GL_RGBA16F          ? GL_FLOAT
                      : fmt == GL_RGB10_A2       ? GL_UNSIGNED_INT_2_10_10_10_REV
                                                 : GL_UNSIGNED_BYTE;
  glTexImage2D(GL_TEXTURE_2D, 0, (GLint)fmt, kTexN, 1, 0, GL_RGBA, type, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glGenFramebuffers(1, &s_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, s_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s_fbo_tex, 0);
  bool ok = false;
  {
    gl_query_census::Armed _ap("hdr-desktop-fbo-status");
    ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  }
  s_fbo_fmt = ok ? fmt : 0;
  return ok;
}

// UNE jambe : rendre la rampe par le VRAI quad final aux parametres du transport demande, puis
// relire. `mode` kModeNone = la recopie d'origine, dont on verifie qu'elle est au BIT.
bool run_leg(Shader& shader, uint32_t mode, int sim_peak, Leg* leg) {
  const GLenum fmt = mode == hdr_output::kModeScrgbLinear  ? GL_RGBA16F
                     : mode == hdr_output::kModeHdr10Pq    ? GL_RGB10_A2
                                                           : GL_RGBA8;
  hdr_output::set_sim_regime(sim_peak, mode == hdr_output::kModeHdr10Pq ? kSimWhiteNits : 0);
  const hdr_output::PresentParams pp = hdr_output::present_params_for(mode);
  s_curve_calls++;
  // La rampe couvre la fenetre ou une courbe a plafond > 1 ecrit ses codes neufs : de 15/16 au
  // PLAFOND que la courbe vient de retenir pour ce pic. En recopie (mode 0) elle couvre [0, 1],
  // puisqu'il n'y a rien au-dessus de 1 a encoder.
  const float hi = mode == hdr_output::kModeNone ? 1.f : std::max(1.f, pp.ceiling);
  const float lo = mode == hdr_output::kModeNone ? 0.f : kRampLow;
  if (!make_ramp_tex(&s_src_tex, lo, hi) || !make_fbo(fmt)) {
    hdr_output::set_sim_regime(0, 0);
    return false;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, s_fbo);
  glViewport(0, 0, kTexN, 1);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, s_src_tex);
  glUniform1i(glGetUniformLocation(shader.id(), "tex_T0"), 0);
  glUniform4f(glGetUniformLocation(shader.id(), "color_mult"), 1.f, 1.f, 1.f, 1.f);
  glUniform4f(glGetUniformLocation(shader.id(), "color_add"), 0.f, 0.f, 0.f, 0.f);
  hdr_output::push_present_uniforms_to(shader, pp);
  s_present_calls++;
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  leg->peak = sim_peak;
  leg->ceiling_x1000 = (int)std::lround(pp.ceiling * 1000.f);
  leg->paper_white = (int)std::lround(pp.paper_white * (mode == hdr_output::kModeHdr10Pq ? 1.f : 1000.f));
  bool ok = true;
  if (fmt == GL_RGB10_A2) {
    // Relecture en FLOTTANT : c'est le seul couple format/type qu'une cible normalisee accepte
    // partout. Le CODE 10 bits se reconstruit exactement, la valeur stockee valant k/1023.
    std::vector<float> buf((size_t)kTexN * 4, 0.f);
    glReadPixels(0, 0, kTexN, 1, GL_RGBA, GL_FLOAT, buf.data());
    auto chan = [&](size_t i) -> uint32_t {
      const float m = std::min(buf[i * 4], std::min(buf[i * 4 + 1], buf[i * 4 + 2]));
      return (uint32_t)std::lround((double)std::max(0.f, std::min(1.f, m)) * 1023.0);
    };
    const double white_nits = pq_eotf_nits((double)chan(1) / 1023.0);
    const double sdr = (double)pp.paper_white > 0.0 ? (double)pp.paper_white : 1.0;
    leg->white_x1000 = (int)std::lround(white_nits / sdr * 1000.0);
    std::set<uint32_t> distinct;
    uint32_t top = 0;
    for (int i = 0; i < kRampN; i++) {
      const uint32_t c = chan((size_t)i + 2);
      distinct.insert(c);
      top = std::max(top, c);
    }
    leg->levels = (int)distinct.size();
    leg->hl_x1000 = (int)std::lround(pq_eotf_nits((double)top / 1023.0) / sdr * 1000.0);
  } else if (fmt == GL_RGBA16F) {
    std::vector<float> buf((size_t)kTexN * 4, 0.f);
    glReadPixels(0, 0, kTexN, 1, GL_RGBA, GL_FLOAT, buf.data());
    auto chan = [&](size_t i) {
      return std::min(buf[i * 4], std::min(buf[i * 4 + 1], buf[i * 4 + 2]));
    };
    leg->white_x1000 = (int)std::lround((double)chan(1) * 1000.0);
    std::set<int> distinct;
    float top = 0.f;
    for (int i = 0; i < kRampN; i++) {
      const float c = chan((size_t)i + 2);
      distinct.insert((int)std::lround((double)c * 100000.0));
      top = std::max(top, c);
    }
    leg->levels = (int)distinct.size();
    leg->hl_x1000 = (int)std::lround((double)top * 1000.0);
  } else {
    // RECOPIE : la sortie doit rendre l'entree, au BIT. C'est la mesure de « OFF = identique a
    // la sortie SDR actuelle » : pas un drapeau a zero, une comparaison d'octets.
    std::vector<uint8_t> buf((size_t)kTexN * 4, 0);
    glReadPixels(0, 0, kTexN, 1, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
    s_off_px = 0;
    s_off_mismatch = 0;
    for (int i = 0; i < kRampN; i++) {
      const float v = lo + (hi - lo) * ((float)i / (float)(kRampN - 1));
      const int want = (int)std::lround((double)v * 255.0);
      for (int c = 0; c < 3; c++) {
        s_off_px++;
        if ((int)buf[(size_t)(i + 2) * 4 + (size_t)c] != want) {
          s_off_mismatch++;
        }
      }
    }
    leg->levels = kRampN;
    leg->white_x1000 = 1000;
    leg->hl_x1000 = 1000;
  }
  hdr_output::set_sim_regime(0, 0);
  leg->done = ok;
  return ok;
}

// ------------------------------------------------------------------------------- verdicts --

void compute_verdicts() {
  const uint32_t modes = hdr_output::modes_available();
  const int fmt = hdr_output::format_chosen();

  // 1. LES DEUX COUCHES ONT PARLE, sur CETTE plateforme.
  s_d[1] = (s_sdl_probed && s_egl_probed && s_platform_info_set && !s_gl_backend.empty() &&
            s_gl_backend != "inconnu" && hdr_output::caps_string() &&
            std::strlen(hdr_output::caps_string()) > 0)
               ? 0
               : 1;

  // 2. LA DECISION EST NOMMEE. Chaque format mieux classe que celui retenu — et tous, si aucun
  //    n'est retenu — porte une raison qui n'est pas « - ». Et le transport du format retenu est
  //    bien le mode retenu : le format et le transport ne peuvent pas diverger.
  int bad = 0;
  const int order[4] = {hdr_output::kFmtScrgb, hdr_output::kFmtHdr10Plus, hdr_output::kFmtHdr10,
                        hdr_output::kFmtHlg};
  for (int i = 0; i < 4; i++) {
    if (order[i] == fmt) {
      break;
    }
    const char* r = hdr_output::format_reason(order[i]);
    if (!r || !r[0] || std::strcmp(r, "-") == 0) {
      bad++;
    }
  }
  if (fmt != hdr_output::kFmtNone && hdr_output::format_transport(fmt) != modes) {
    bad++;
  }
  if (fmt == hdr_output::kFmtNone && modes != hdr_output::kModeNone) {
    bad++;
  }
  s_d[2] = bad ? 1 : 0;

  // 3. LA DEMANDE A ETE EMISE ET LA REPONSE EST CELLE DU PILOTE. Les deux transports HDR sont
  //    soumis a la couche de presentation, et ce qu'elle rend est consigne — obtenu, ou refuse
  //    avec SON code d'erreur. Quand aucune couche EGL n'existe (Windows/WGL), la raison le dit
  //    et l'etat de la surface obtenue tient lieu de reponse.
  const bool egl_layer = s_probe_dpy != nullptr;
  if (egl_layer) {
    s_d[3] = (s_requests_issued >= 2 && s_req_pq >= 0 && s_req_scrgb >= 0) ? 0 : 1;
  } else {
    s_d[3] = (s_egl_probed && s_obtained_colorspace >= 0 && s_created_mode == s_planned_mode) ? 0 : 1;
  }

  // 4. LES METADONNEES EXISTENT ET SONT NON DEGENEREES, et quand la plateforme sait les poser,
  //    chaque pose a reussi.
  const bool values_ok = s_md_maxcll > 0 && s_md_maxlum > 0;
  const bool posted_ok =
      (s_md_calls == 0) ? (s_md_reason != "-" && !s_md_reason.empty()) : (s_md_posted == s_md_calls);
  s_d[4] = (values_ok && posted_ok) ? 0 : 1;

  // 5. LA COURBE EST LE CODE COMMUN. Pas une affirmation : les uniformes que le VRAI quad final
  //    a recus pour les images presentees — ceux que `push_present_uniforms()` pose, le chemin
  //    que l'appareil emprunte aussi — sont relus SUR LE PROGRAMME et confrontes a ce que
  //    `present_params_for()` rend ici. Un chemin de presentation recopie cote bureau divergerait.
  //    (Le nom du symbole est publie a cote, mais il n'entre pas dans le verdict : `gk` n'exporte
  //    pas sa table dynamique, donc `dladdr` ne peut nommer que le MODULE.)
  s_d[5] = (s_curve_calls > 0 && s_present_calls > 0 && s_uniform_match > 0 &&
            s_uniform_mismatch == 0)
               ? 0
               : 1;

  // 6. L'EFFET MESURE : la courbe exercee a DEUX pics simules, par le vrai quad final, vers le
  //    format reel du transport. Le blanc du jeu ne BOUGE pas quand le pic change (il est ancre
  //    au blanc SDR) ; la haute lumiere, elle, MONTE. C'est le seul verdict de ce lot qu'un
  //    encodage inerte ne peut pas satisfaire.
  int e6 = 0;
  if (!s_pq_lo.done || !s_pq_hi.done) {
    e6 = 1;
  } else {
    const double wl = (double)s_pq_lo.white_x1000, wh = (double)s_pq_hi.white_x1000;
    if (!(wl > 0.0) || std::fabs(wh - wl) > 0.01 * wl) {
      e6 = 1;  // l'ancre a bouge
    }
    if (!(s_pq_hi.hl_x1000 > (int)std::lround(1.01 * (double)s_pq_lo.hl_x1000))) {
      e6 = 1;  // la haute lumiere n'a pas suivi le pic
    }
    if (s_pq_lo.levels < 2 || s_pq_hi.levels < 2) {
      e6 = 1;  // rien a separer : la sortie n'encode pas de plage etendue
    }
    if (!(s_pq_hi.ceiling_x1000 > s_pq_lo.ceiling_x1000)) {
      e6 = 1;
    }
  }
  s_d[6] = e6;

  // 7. OFF EST LA RECOPIE, AU BIT. Et la capacite de l'ecran n'a jamais force ce que le reglage
  //    n'a pas demande.
  s_d[7] = (s_off_px > 0 && s_off_mismatch == 0 && s_forced_on == 0) ? 0 : 1;

  // 8. AUCUNE REGRESSION DU RENDU SDR. Tant que la surface n'est pas HDR, le quad final est la
  //    recopie et les tampons restent RGBA8 ; et le chemin bureau n'a leve aucune erreur GL.
  s_d[8] = (s_sdr_frames_bad == 0 && s_fmt_bad == 0 && s_gl_errors == 0 && s_frames > 0) ? 0 : 1;

  s_defects = 0;
  for (int i = 1; i <= 8; i++) {
    s_defects += s_d[i];
  }
  s_verdicts_done = true;
}

void publish_leg(const char* prefix, const Leg& l) {
  const std::string base = std::string("hdr_desktop_") + prefix;
  auto k = [&](const char* suffix) { return (base + suffix); };
  autoport_proof::publish(k("_done").c_str(), l.done ? 1 : 0);
  autoport_proof::publish(k("_peak_nits").c_str(), (uint64_t)std::max(0, l.peak));
  autoport_proof::publish(k("_levels").c_str(), (uint64_t)std::max(0, l.levels));
  autoport_proof::publish(k("_white_x1000").c_str(), (uint64_t)std::max(0, l.white_x1000));
  autoport_proof::publish(k("_hl_x1000").c_str(), (uint64_t)std::max(0, l.hl_x1000));
  autoport_proof::publish(k("_ceiling_x1000").c_str(), (uint64_t)std::max(0, l.ceiling_x1000));
  autoport_proof::publish(k("_paper_white").c_str(), (uint64_t)std::max(0, l.paper_white));
}

void publish_all() {
  autoport_proof::publish_text("hdr_desktop_os",
#if defined(_WIN32)
                               "windows"
#elif defined(__APPLE__)
                               "macos"
#elif defined(__linux__)
                               "linux"
#else
                               "autre"
#endif
  );
  const char* drv = SDL_GetCurrentVideoDriver();
  autoport_proof::publish_text("hdr_desktop_sdl_video_driver", drv ? drv : "-");
  autoport_proof::publish_text("hdr_desktop_gl_backend", s_gl_backend.c_str());
  autoport_proof::publish("hdr_desktop_sdl_probed", s_sdl_probed ? 1 : 0);
  autoport_proof::publish("hdr_desktop_egl_probed", s_egl_probed ? 1 : 0);
  autoport_proof::publish("hdr_desktop_platform_info_set", s_platform_info_set ? 1 : 0);
  autoport_proof::publish("hdr_desktop_forced_egl", s_forced_egl ? 1 : 0);
  autoport_proof::publish("hdr_desktop_want_hdr", s_want_hdr ? 1 : 0);
  autoport_proof::publish_text("hdr_desktop_egl_exts", s_egl_exts_text.c_str());
  autoport_proof::publish("hdr_desktop_display_hdr", s_caps.sdl_display_hdr ? 1 : 0);
  autoport_proof::publish("hdr_desktop_window_hdr", s_caps.sdl_window_hdr ? 1 : 0);
  autoport_proof::publish("hdr_desktop_headroom_x100", (uint64_t)std::max(0, s_caps.sdl_headroom_x100));
  autoport_proof::publish("hdr_desktop_config_10bit", s_caps.config_10bit ? 1 : 0);
  autoport_proof::publish("hdr_desktop_config_fp16", s_caps.config_fp16 ? 1 : 0);
  autoport_proof::publish_text("hdr_desktop_caps", hdr_output::caps_string());

  const int fmt = hdr_output::format_chosen();
  autoport_proof::publish_text("hdr_desktop_format_chosen", hdr_output::format_name(fmt));
  autoport_proof::publish("hdr_desktop_format_chosen_id", (uint64_t)std::max(0, fmt));
  {
    std::string reasons;
    const int order[4] = {hdr_output::kFmtScrgb, hdr_output::kFmtHdr10Plus, hdr_output::kFmtHdr10,
                          hdr_output::kFmtHlg};
    for (int i = 0; i < 4; i++) {
      if (!reasons.empty()) {
        reasons += ";";
      }
      reasons += hdr_output::format_name(order[i]);
      reasons += "=";
      const char* r = hdr_output::format_reason(order[i]);
      reasons += (r && r[0]) ? r : "?";
    }
    autoport_proof::publish_text("hdr_desktop_format_reasons", reasons.c_str());
  }
  autoport_proof::publish("hdr_desktop_modes_available", (uint64_t)hdr_output::modes_available());
  autoport_proof::publish("hdr_desktop_mode_planned", (uint64_t)s_planned_mode);
  autoport_proof::publish("hdr_desktop_mode_obtained", (uint64_t)s_created_mode);
  autoport_proof::publish_text("hdr_desktop_mode_obtained_name",
                               hdr_output::mode_name(s_created_mode));
  autoport_proof::publish("hdr_desktop_colorspace_requested",
                          (uint64_t)std::max(0, s_requested_colorspace));
  autoport_proof::publish("hdr_desktop_colorspace_obtained",
                          (uint64_t)std::max(0, s_obtained_colorspace));
  autoport_proof::publish_text("hdr_desktop_switch_reason", s_switch_reason.c_str());

  autoport_proof::publish("hdr_desktop_requests_issued", s_requests_issued);
  autoport_proof::publish("hdr_desktop_req_pq_obtained", (uint64_t)std::max(0, s_req_pq));
  autoport_proof::publish("hdr_desktop_req_pq_egl_error", (uint64_t)(unsigned)s_req_pq_err);
  autoport_proof::publish("hdr_desktop_req_scrgb_obtained", (uint64_t)std::max(0, s_req_scrgb));
  autoport_proof::publish("hdr_desktop_req_scrgb_egl_error", (uint64_t)(unsigned)s_req_scrgb_err);
  autoport_proof::publish_text("hdr_desktop_req_pq_reason", s_req_pq_reason.c_str());
  autoport_proof::publish_text("hdr_desktop_req_scrgb_reason", s_req_scrgb_reason.c_str());

  autoport_proof::publish("hdr_desktop_md_maxcll_nits", (uint64_t)std::max(0, s_md_maxcll));
  autoport_proof::publish("hdr_desktop_md_maxfall_nits", (uint64_t)std::max(0, s_md_maxfall));
  autoport_proof::publish("hdr_desktop_md_maxlum_nits", (uint64_t)std::max(0, s_md_maxlum));
  autoport_proof::publish("hdr_desktop_md_minlum_x10000", (uint64_t)std::max(0, s_md_minlum_x10000));
  autoport_proof::publish("hdr_desktop_md_calls", s_md_calls);
  autoport_proof::publish("hdr_desktop_md_posted", s_md_posted);
  autoport_proof::publish_text("hdr_desktop_md_primaries",
                               "bt2020:rx0.708,ry0.292,gx0.170,gy0.797,bx0.131,by0.046;d65:0.3127,0.3290");
  autoport_proof::publish_text("hdr_desktop_md_reason", s_md_reason.c_str());

  autoport_proof::publish_text("hdr_desktop_curve_symbol", s_curve_symbol.c_str());
  autoport_proof::publish_text("hdr_desktop_curve_module", s_curve_module.c_str());
  autoport_proof::publish("hdr_desktop_curve_calls", s_curve_calls);
  autoport_proof::publish("hdr_desktop_present_calls", s_present_calls);
  autoport_proof::publish("hdr_desktop_uniform_match_frames", s_uniform_match);
  autoport_proof::publish("hdr_desktop_uniform_mismatch_frames", s_uniform_mismatch);
  autoport_proof::publish("hdr_desktop_live_out_mode", (uint64_t)std::max(0, s_live_out_mode));

  publish_leg("pq_lo", s_pq_lo);
  publish_leg("pq_hi", s_pq_hi);
  publish_leg("scrgb", s_scrgb);
  autoport_proof::publish("hdr_desktop_off_px", (uint64_t)std::max(0, s_off_px));
  autoport_proof::publish("hdr_desktop_off_mismatch_px", (uint64_t)std::max(0, s_off_mismatch));
  autoport_proof::publish("hdr_desktop_rehearsal_step", (uint64_t)s_reh_step);
  autoport_proof::publish("hdr_desktop_rehearsal_failed", s_reh_failed ? 1 : 0);

  autoport_proof::publish("hdr_desktop_frames", s_frames);
  autoport_proof::publish("hdr_desktop_active_frames", s_active_frames);
  autoport_proof::publish("hdr_desktop_forced_on", s_forced_on);
  autoport_proof::publish("hdr_desktop_sdr_frames_bad", s_sdr_frames_bad);
  autoport_proof::publish("hdr_desktop_fmt_bad", s_fmt_bad);
  autoport_proof::publish("hdr_desktop_gl_errors", s_gl_errors);

  for (int i = 1; i <= 8; i++) {
    static const char* names[9] = {"",
                                   "hdr_desktop_defect_1_caps_read",
                                   "hdr_desktop_defect_2_decision_named",
                                   "hdr_desktop_defect_3_request_answered",
                                   "hdr_desktop_defect_4_static_metadata",
                                   "hdr_desktop_defect_5_common_curve",
                                   "hdr_desktop_defect_6_two_simulated_peaks",
                                   "hdr_desktop_defect_7_off_is_a_bit_copy",
                                   "hdr_desktop_defect_8_no_sdr_regression"};
    autoport_proof::publish(names[i], (uint64_t)s_d[i]);
  }
  // ROUGE, JAMAIS MUET : tant que la repetition n'est pas allee au bout, les huit sont comptes
  // en defaut. Une preuve qui se tait sur un verdict non calcule se lit comme un verdict tenu.
  autoport_proof::publish("hdr_desktop_defects", (uint64_t)(s_verdicts_done ? s_defects : 8));
}

void resolve_curve_symbol() {
  const void* p = hdr_output::common_curve_symbol();
#if defined(__linux__) || defined(__APPLE__)
  Dl_info info;
  if (p && dladdr(p, &info)) {
    s_curve_module = info.dli_fname ? info.dli_fname : "module_sans_nom";
    if (info.dli_sname) {
      s_curve_symbol = info.dli_sname;
      return;
    }
  }
  // Binaire non exporte (lien statique, -fvisibility=hidden) : le chargeur ne peut pas nommer le
  // symbole. On publie alors l'ADRESSE et le module, ce qui reste falsifiable, et le verdict 5
  // le dira. Jamais un nom invente.
  char buf[64];
  std::snprintf(buf, sizeof(buf), "adresse_%p_non_nommee_par_dladdr", p);
  s_curve_symbol = buf;
#else
  char buf[64];
  std::snprintf(buf, sizeof(buf), "adresse_%p_pas_de_dladdr_sur_cette_plateforme", p);
  s_curve_symbol = buf;
#endif
}

}  // namespace

// ============================================================================================
void before_sdl_init() {
  // OFF EST L'ABSENCE. Sans demande du joueur et sans mesure, on ne sonde rien, on ne pose aucun
  // hint, on ne touche aucun attribut : la fenetre est creee par le chemin d'avant cet item.
  const int persisted = hdr_output::read_persisted_setting();
  // Le knob du harnais vaut reglage : c'est par lui qu'une course de preuve epingle le REGIME de
  // sa propre feature, au lieu d'heriter de ce qu'un autre a laisse dans settings.ini.
  const char* knob = std::getenv("OG_HDR_OUT");
  const bool knob_on = knob && knob[0] == '1';
  s_want_hdr = persisted == 1 || knob_on;
  if (!s_want_hdr && !measuring()) {
    return;
  }
  probe_egl_layer();
  // Le pilote GL de SDL se choisit DANS `SDL_Init` (SDL_x11video.c, X11_CreateDevice) : un hint
  // pose apres la fenetre ne servirait a rien. On ne le pose que si le pilote EGL annonce
  // vraiment un espace HDR — sans quoi on echangerait GLX contre EGL pour rien.
  if (s_want_hdr && (s_caps.egl_bt2020_pq || s_caps.egl_scrgb_linear || s_caps.egl_bt2020_hlg)) {
    SDL_SetHint(SDL_HINT_VIDEO_FORCE_EGL, "1");
    s_forced_egl = true;
    lg::info("[hdr-desktop-output] EGL force : GLX n'a aucune extension de colorspace");
  }
}

void before_window() {
  if (!s_want_hdr && !measuring()) {
    return;
  }
  if (!s_egl_probed) {
    probe_egl_layer();
  }

  // Les capacites de l'ECRAN, telles que SDL les publie. Sur Windows elles viennent de DXGI
  // (MaxLuminance, blanc SDR) ; sur Wayland du protocole de gestion de couleur ; sur X11 il n'y
  // en a aucune, et c'est publie tel quel.
  const SDL_DisplayID did = SDL_GetPrimaryDisplay();
  if (did) {
    s_caps.sdl_display_hdr =
        SDL_GetBooleanProperty(SDL_GetDisplayProperties(did), SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN,
                               false);
    s_sdl_probed = true;
  }
  s_caps.probed = true;
  hdr_output::set_platform_caps(s_caps);
  hdr_output::set_system_caps(s_caps.sdl_display_hdr ? (uint32_t)hdr_output::kSysSdl : 0u, 0, 0, 0,
                              s_caps.sdl_display_hdr);
  // Le bureau n'a pas de niveau d'API Android. La marge, quand il en publie une, est celle du
  // compositeur pour NOTRE fenetre : c'est un contrat lisible, donc `ratio_available` est vrai.
  hdr_output::set_platform_info(0, s_caps.sdl_display_hdr);
  s_platform_info_set = true;

  s_planned_mode = hdr_output::modes_available();
  if (!s_want_hdr) {
    s_planned_mode = hdr_output::kModeNone;  // la mesure sonde, elle ne decide pas de l'image
  }
  if (s_planned_mode == hdr_output::kModeNone) {
    return;
  }
  // Le transport retenu exige un framebuffer de fenetre particulier. Ces attributs sont le SEUL
  // levier du bureau : ni SDL3, ni GLX, ni WGL ne rechangent le format d'une fenetre existante.
  const bool scrgb = s_planned_mode == hdr_output::kModeScrgbLinear;
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, scrgb ? 16 : 10);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, scrgb ? 16 : 10);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, scrgb ? 16 : 10);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, scrgb ? 16 : 2);
  SDL_GL_SetAttribute(SDL_GL_FLOATBUFFERS, scrgb ? 1 : 0);
  if (s_probe_dpy) {
    // Chemin EGL : SDL ne pose plus EGL_GL_COLORSPACE lui-meme, notre callback le pose.
    SDL_SetHint(SDL_HINT_OPENGL_FORCE_SRGB_FRAMEBUFFER, "skip");
    SDL_EGL_SetAttributeCallbacks(nullptr, surface_attribs_cb, nullptr, nullptr);
    s_requested_colorspace = scrgb ? kEglColorspaceScrgbLinear : kEglColorspaceBt2020Pq;
  }
  lg::info("[hdr-desktop-output] transport demande a la creation : {} (format {})",
           hdr_output::mode_name(s_planned_mode),
           hdr_output::format_name(hdr_output::format_chosen()));
}

void after_window(SDL_Window* window) {
  s_window = window;
  // CE QUE LE BUREAU FAISAIT DEJA AVANT CET ITEM, et qui doit continuer quoi qu'il arrive : les
  // capacites annoncees par SDL et l'etat initial de la surface. C'est une LECTURE, elle ne
  // touche aucune image ; la retirer ferait perdre `hdr_out_platform_probed` et les bits rouges
  // sur toute course x86, sans rien gagner.
  {
    const SDL_DisplayID did = SDL_GetDisplayForWindow(window);
    if (did) {
      s_caps.sdl_display_hdr = SDL_GetBooleanProperty(
          SDL_GetDisplayProperties(did), SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN, false);
      s_sdl_probed = true;
    }
    SDL_PropertiesID wp0 = SDL_GetWindowProperties(window);
    s_caps.sdl_window_hdr = SDL_GetBooleanProperty(wp0, SDL_PROP_WINDOW_HDR_ENABLED_BOOLEAN, false);
    s_caps.sdl_headroom_x100 =
        (int)(SDL_GetFloatProperty(wp0, SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT, 0.f) * 100.f);
    s_caps.probed = true;
    hdr_output::set_platform_caps(s_caps);
    hdr_output::set_system_caps(s_caps.sdl_display_hdr ? (uint32_t)hdr_output::kSysSdl : 0u, 0, 0,
                                0, s_caps.sdl_display_hdr);
  }
  if (!s_want_hdr && !measuring()) {
    // Etat initial de la surface : bits rouges lus sur le framebuffer par defaut. Aucun
    // colorspace a relire — sans demande de sortie HDR, aucune couche EGL n'a ete sondee.
    hdr_output::SurfaceState st0;
    {
      gl_query_census::Armed _ap("hdr-desktop-surface-state");
      GLint r = 0;
      glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_BACK_LEFT,
                                            GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, &r);
      st0.red_bits = r > 0 ? (int)r : 8;
    }
    hdr_output::note_surface_state(st0);
    return;
  }
  resolve_curve_symbol();

  // QUELLE COUCHE DE PRESENTATION a REELLEMENT ete retenue par SDL. C'est elle, pas notre
  // intention, qui dit si une demande de colorspace etait seulement possible.
  const bool on_egl = SDL_EGL_GetCurrentDisplay() != nullptr;
#if defined(_WIN32)
  s_gl_backend = on_egl ? "egl" : "wgl";
#else
  s_gl_backend = on_egl ? "egl" : "glx";
#endif

  // Ce que le compositeur publie pour NOTRE fenetre, une fois qu'elle existe.
  SDL_PropertiesID wp = SDL_GetWindowProperties(window);
  s_caps.sdl_window_hdr = SDL_GetBooleanProperty(wp, SDL_PROP_WINDOW_HDR_ENABLED_BOOLEAN, false);
  s_caps.sdl_headroom_x100 =
      (int)(SDL_GetFloatProperty(wp, SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT, 0.f) * 100.f);

  // L'ETAT REELLEMENT OBTENU, relu sur la surface — jamais ce qu'on a demande.
  hdr_output::SurfaceState st;
  {
    gl_query_census::Armed _ap("hdr-desktop-surface-state");
    GLint r = 0;
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_BACK_LEFT,
                                          GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, &r);
    st.red_bits = (int)r;
  }
  int floatbuf = 0;
  SDL_GL_GetAttribute(SDL_GL_FLOATBUFFERS, &floatbuf);
  s_obtained_colorspace = 0;
  if (on_egl && s_egl.QuerySurface) {
    EGLDisplayT dpy = (EGLDisplayT)SDL_EGL_GetCurrentDisplay();
    EGLSurfaceT surf = (EGLSurfaceT)SDL_EGL_GetWindowSurface(window);
    EGLint32 cs = 0;
    if (dpy && surf && s_egl.QuerySurface(dpy, surf, kEglColorspace, &cs)) {
      s_obtained_colorspace = (int)cs;
    }
  }
  // La regle est la MEME que sur l'appareil : un transport n'est obtenu que si le colorspace ET
  // la profondeur sont ceux qu'il exige. Un colorspace accepte sur un tampon 8 bits n'est pas du
  // HDR10 ; un tampon flottant sans contrat de marge n'est pas du scRGB.
  if (s_obtained_colorspace == kEglColorspaceBt2020Pq && st.red_bits >= 10) {
    s_created_mode = hdr_output::kModeHdr10Pq;
  } else if (s_obtained_colorspace == kEglColorspaceScrgbLinear && floatbuf) {
    s_created_mode = hdr_output::kModeScrgbLinear;
  } else if (s_obtained_colorspace == kEglColorspaceBt2020Hlg && st.red_bits >= 10) {
    s_created_mode = hdr_output::kModeHlg;
  } else if (!on_egl && floatbuf && s_caps.sdl_window_hdr &&
             s_planned_mode == hdr_output::kModeScrgbLinear) {
    // Le seul chemin HDR d'OpenGL sous Windows : un tampon de fenetre flottant, que le
    // compositeur interprete en scRGB lineaire quand l'ecran est en mode HDR. Il n'y a aucun
    // colorspace a relire — c'est la propriete HDR de la fenetre qui tient lieu de reponse.
    s_created_mode = hdr_output::kModeScrgbLinear;
  } else {
    s_created_mode = hdr_output::kModeNone;
  }
  s_caps.config_fp16 = floatbuf != 0;
  s_caps.config_10bit = s_caps.config_10bit || st.red_bits >= 10;
  hdr_output::set_platform_caps(s_caps);
  // LE PIC ANNONCE, en nits, DERIVE de ce que le compositeur publie pour notre fenetre : le blanc
  // SDR (en nits) multiplie par la marge. C'est la seule facon d'obtenir des nits sur bureau —
  // il n'y a pas de HdrCapabilities. Quand le compositeur ne publie rien, on n'invente aucun
  // nombre : 0, et `announced_peak_nits()` retombe sur son defaut, avec la raison publiee.
  const float sdr_white = SDL_GetFloatProperty(wp, SDL_PROP_WINDOW_SDR_WHITE_LEVEL_FLOAT, 0.f);
  const float headroom = (float)s_caps.sdl_headroom_x100 / 100.f;
  const int max_lum =
      (sdr_white > 0.f && headroom > 1.f) ? (int)std::lround(sdr_white * headroom) : 0;
  hdr_output::set_system_caps(s_caps.sdl_display_hdr ? (uint32_t)hdr_output::kSysSdl : 0u, max_lum,
                              0, 0, s_caps.sdl_display_hdr);
  hdr_output::set_platform_info(0, s_caps.sdl_window_hdr && s_caps.sdl_headroom_x100 > 100);
  autoport_proof::publish("hdr_desktop_sdr_white_x100",
                          (uint64_t)std::max(0, (int)std::lround(sdr_white * 100.f)));
  autoport_proof::publish("hdr_desktop_announced_peak_nits", (uint64_t)std::max(0, max_lum));
  if (s_caps.sdl_headroom_x100 > 100) {
    hdr_output::set_hdr_sdr_ratio(headroom);
  }

  st.mode = s_created_mode;
  st.colorspace = s_obtained_colorspace;
  st.hdr = s_created_mode != hdr_output::kModeNone;
  hdr_output::note_surface_state(st);
  hdr_output::install_switcher(desktop_switch);
  post_static_metadata();

  if (measuring()) {
    // LA DEMANDE, EMISE POUR DE VRAI. Une extension absente de la chaine est deja une reponse,
    // mais c'est la NOTRE : on soumet les deux espaces au pilote et on consigne CE QU'IL REND.
    s_req_pq = issue_colorspace_request(kEglColorspaceBt2020Pq, &s_req_pq_err, &s_req_pq_reason);
    s_req_scrgb =
        issue_colorspace_request(kEglColorspaceScrgbLinear, &s_req_scrgb_err, &s_req_scrgb_reason);
  }
  lg::info(
      "[hdr-desktop-output] couche={} demande=0x{:x} obtenu=0x{:x} bits_rouges={} flottant={} "
      "mode={} ; caps={}",
      s_gl_backend, (unsigned)s_requested_colorspace, (unsigned)s_obtained_colorspace, st.red_bits,
      floatbuf, hdr_output::mode_name(s_created_mode), hdr_output::caps_string());
}

void frame_begin() {
  if (!s_want_hdr && !measuring()) {
    return;
  }
  // Le geste qui n'existait pas sur bureau : appliquer une demande en attente (menu, reglage
  // charge) sur le fil GL, entre deux images. Sans lui, un basculeur installe ne serait appele
  // par personne.
  hdr_output::apply_pending_on_gl_thread();
  // Les deux demandes que `hdr_output` peut emettre sont sans objet sur bureau : aucune API n'y
  // prend une marge ni un mode couleur de fenetre. On les DRAINE quand meme, pour qu'elles ne
  // s'accumulent pas, et la raison est publiee.
  float cur = 0.f, des = 0.f;
  hdr_output::take_headroom_request(&cur, &des);
  bool on = false;
  float d2 = 0.f, b = 0.f;
  hdr_output::take_window_lever_request(&on, &d2, &b);

  s_frames++;
  const bool active = hdr_output::active();
  s_active_frames += active ? 1 : 0;
  if (active && s_created_mode == hdr_output::kModeNone) {
    s_forced_on++;
  }
  if (!active) {
    // AUCUNE REGRESSION SDR : hors HDR, les tampons sont ceux d'avant l'item.
    if (hdr_output::ui_buffer_format() != GL_RGBA8 ||
        hdr_output::window_target_format() != GL_RGBA8) {
      s_fmt_bad++;
    }
  }
  // Le compteur de l'item, AU SITE DU GESTE : une image ou le chemin de sortie HDR bureau a
  // tourne. Desarme (`--off`), `note_hit` ne compte rien et la sonde ne tourne pas.
  autoport_proof::note_hit();
  // ROUGE, JAMAIS MUET. La cle de porte doit exister des la premiere image : si le quad final
  // n'etait jamais atteint (ecran de chargement, renderer coupe), une preuve SANS
  // `hdr_desktop_defects` se lirait « le moteur n'emet pas cette grandeur » au lieu de « les
  // verdicts n'ont pas pu etre calcules ». Ce n'est pas la meme phrase.
  if (measuring() && (s_frames == 1 || (s_frames % 120) == 0)) {
    publish_all();
  }
}

void probe_present(Shader& shader) {
  if (!measuring()) {
    return;
  }
  // AU POINT DE LECTURE, ET AVANT TOUTE SONDE : ce que le GPU vient de recevoir pour l'image
  // REELLEMENT presentee. Le programme est encore actif et ses uniformes sont ceux que
  // `hdr_output::push_present_uniforms()` a poses — le chemin commun aux deux plateformes.
  {
    gl_query_census::Armed _ap("hdr-desktop-live-uniforms");
    GLint mode = -1;
    GLfloat white = 0.f, nits = 0.f;
    const GLint l_mode = glGetUniformLocation(shader.id(), "u_out_mode");
    const GLint l_white = glGetUniformLocation(shader.id(), "u_out_paper_white");
    const GLint l_nits = glGetUniformLocation(shader.id(), "u_out_max_nits");
    if (l_mode >= 0) {
      glGetUniformiv(shader.id(), l_mode, &mode);
    }
    if (l_white >= 0) {
      glGetUniformfv(shader.id(), l_white, &white);
    }
    if (l_nits >= 0) {
      glGetUniformfv(shader.id(), l_nits, &nits);
    }
    s_live_out_mode = (int)mode;
    const bool active = hdr_output::active();
    const hdr_output::PresentParams want =
        hdr_output::present_params_for(active ? s_created_mode : hdr_output::kModeNone);
    s_curve_calls++;
    const bool same = mode == (GLint)want.out_mode &&
                      std::fabs(white - want.paper_white) <= 1e-3f * std::max(1.f, want.paper_white) &&
                      std::fabs(nits - want.max_nits) <= 1e-3f * std::max(1.f, want.max_nits);
    if (same) {
      s_uniform_match++;
    } else {
      s_uniform_mismatch++;
    }
    // AUCUNE REGRESSION SDR, mesuree sur ce que le GPU a recu : hors HDR, le quad final est la
    // recopie d'origine, mode 0. Un compteur sans site d'ecriture ne prouverait rien.
    if (!active && mode != 0) {
      s_sdr_frames_bad++;
    }
  }
  if (s_reh_step > 3) {
    // Les verdicts 5, 7 et 8 lisent des compteurs qui MONTENT encore apres la repetition : un
    // verdict fige a l'image 4 ne decrirait pas la course. On les recalcule, comme le chemin
    // appareil le fait pour les siens.
    if ((s_frames % 60) == 0) {
      compute_verdicts();
      publish_all();
    }
    return;
  }
  // Une jambe par image : chacune fait un dessin et une relecture synchrone, et il n'y en a que
  // quatre dans toute la course.
  gl_query_census::Armed _ap("hdr-desktop-rehearsal");
  GLint vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_VIEWPORT, vp);
  GLint saved_tex = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  while (glGetError() != GL_NO_ERROR) {
  }

  bool ok = true;
  switch (s_reh_step) {
    case 0: {
      Leg off;
      ok = run_leg(shader, hdr_output::kModeNone, 0, &off);
      break;
    }
    case 1:
      ok = run_leg(shader, hdr_output::kModeHdr10Pq, kSimPeakLo, &s_pq_lo);
      break;
    case 2:
      ok = run_leg(shader, hdr_output::kModeHdr10Pq, kSimPeakHi, &s_pq_hi);
      break;
    default:
      ok = run_leg(shader, hdr_output::kModeScrgbLinear, kSimPeakHi, &s_scrgb);
      break;
  }
  if (!ok) {
    s_reh_failed = true;
  }
  GLenum e = GL_NO_ERROR;
  while ((e = glGetError()) != GL_NO_ERROR) {
    s_gl_errors++;
  }
  s_reh_step++;

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(vp[0], vp[1], vp[2], vp[3]);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (s_reh_step > 3) {
    compute_verdicts();
    publish_all();
    autoport_proof::flush();
    lg::info("[hdr-desktop-output] repetition terminee : defauts={} (1..8 = {} {} {} {} {} {} {} {})",
             s_defects, s_d[1], s_d[2], s_d[3], s_d[4], s_d[5], s_d[6], s_d[7], s_d[8]);
  } else {
    publish_all();
  }
}

}  // namespace hdr_desktop
