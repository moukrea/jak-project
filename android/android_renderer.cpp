// SDL3 + GLES context bring-up + the A35 game-content render loop.
//
// Phase A35 (autoport): this TU previously maintained an honest clear/swap
// stub ("NO GAME CONTENT RENDERER WIRED"). It now drives the real ported
// renderer: after the GLES 3.2 context is current, android_gfx builds the
// TexturePool + Loader + AndroidOpenGLRenderer (DirectRenderer +
// TextureUploadHandler + EyeRenderer buckets), and every loop iteration
// consumes one DMA chain from the GOAL kernel via the same mutex/cv
// handshake the desktop pipeline uses. When the kernel hasn't produced a
// chain (boot, or kernel death) the loop falls back to the dark-blue clear
// so "no content" stays visibly distinct from "black frame".
//
// Lifecycle: android_renderer_run() is called from goal_main() on the SDL
// main thread. It blocks until MasterExit transitions out of RUNNING or
// until SDL_EVENT_QUIT / SDL_EVENT_TERMINATING arrives.

#include "android_renderer.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <android/log.h>

#include <SDL3/SDL.h>

#include <sys/system_properties.h>

#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

#include "common/common_types.h"
#include "common/versions/versions.h"

#include "game/graphics/gfx.h"
#include "game/graphics/render_pace.h"
#include "game/graphics/uncap.h"
#include "game/graphics/opengl_renderer/AmbientOcclusion.h"
#include "game/graphics/opengl_renderer/hdr_output.h"
#include "game/kernel/common/kboot.h"
#include "game/system/sched_affinity.h"

#include "android_gfx.h"
#include "android_input_audio.h"

#include "game/graphics/gl_query_census.h"
#include "third-party/glad/include/glad/glad.h"

namespace {
constexpr const char* kLogTag = "opengoal-gk";

// Swap-loop heartbeat (phase D3) — JNI readers poll this via
// android_renderer_frame_count().
std::atomic<uint64_t> g_renderer_frame_count{0};
}  // namespace

uint64_t android_renderer_frame_count() {
  return g_renderer_frame_count.load(std::memory_order_relaxed);
}

// ============================================================================
// hdr-display-output : la SURFACE EGL, 8 bits lineaire par defaut, 10 bits BT.2020 PQ quand
// le joueur le demande ET que l'ecran + EGL l'annoncent. La bascule detruit et recree la
// surface sur la meme fenetre native et le meme contexte (patch SDL D1 :
// SDL_Android_RecreateEGLSurface) ; le contexte est cree sans config (patch SDL D2, hint
// SDL_EGL_NO_CONFIG_CONTEXT) pour accepter les deux profondeurs.
// ============================================================================

// Valeurs officielles (eglext.h du NDK r27c) : definies ici seulement si l'en-tete les tait.
#ifndef EGL_GL_COLORSPACE_KHR
#define EGL_GL_COLORSPACE_KHR 0x309D
#endif
#ifndef EGL_GL_COLORSPACE_LINEAR_KHR
#define EGL_GL_COLORSPACE_LINEAR_KHR 0x308A
#endif
#ifndef EGL_GL_COLORSPACE_BT2020_PQ_EXT
#define EGL_GL_COLORSPACE_BT2020_PQ_EXT 0x3340
#endif
#ifndef EGL_GL_COLORSPACE_SCRGB_LINEAR_EXT
#define EGL_GL_COLORSPACE_SCRGB_LINEAR_EXT 0x3350
#endif
#ifndef EGL_COLOR_COMPONENT_TYPE_EXT
#define EGL_COLOR_COMPONENT_TYPE_EXT 0x3339
#define EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT 0x333B
#endif
#ifndef EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT
#define EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT 0x3341
#define EGL_SMPTE2086_DISPLAY_PRIMARY_RY_EXT 0x3342
#define EGL_SMPTE2086_DISPLAY_PRIMARY_GX_EXT 0x3343
#define EGL_SMPTE2086_DISPLAY_PRIMARY_GY_EXT 0x3344
#define EGL_SMPTE2086_DISPLAY_PRIMARY_BX_EXT 0x3345
#define EGL_SMPTE2086_DISPLAY_PRIMARY_BY_EXT 0x3346
#define EGL_SMPTE2086_WHITE_POINT_X_EXT 0x3347
#define EGL_SMPTE2086_WHITE_POINT_Y_EXT 0x3348
#define EGL_SMPTE2086_MAX_LUMINANCE_EXT 0x3349
#define EGL_SMPTE2086_MIN_LUMINANCE_EXT 0x334A
#endif
#ifndef EGL_METADATA_SCALING_EXT
#define EGL_METADATA_SCALING_EXT 50000
#endif
#ifndef EGL_GL_COLORSPACE_BT2020_HLG_EXT
#define EGL_GL_COLORSPACE_BT2020_HLG_EXT 0x3540
#endif
#ifndef EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT
#define EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT 0x3360
#define EGL_CTA861_3_MAX_FRAME_AVERAGE_LEVEL_EXT 0x3361
#endif

// Luminances de l'ecran annoncees par le systeme (Java -> NativeGk.setDisplayHdrCaps).
int g_hdr_out_max_lum_nits = 0;
int g_hdr_out_min_lum_x10000 = 0;
// Moyenne annoncee par l'ecran (HdrCapabilities.getDesiredMaxAverageLuminance) : MaxFALL des
// metadonnees CTA861.3. 0 = indisponible, et 0 est aussi ce que la spec demande d'ecrire dans
// ce cas (un decodeur le lit comme « non renseigne »).
int g_hdr_out_max_avg_lum_nits = 0;

// Patch SDL D1 (third-party/SDL/src/video/android/SDL_androidwindow.c).
extern "C" bool SDL_Android_RecreateEGLSurface(SDL_Window* window);

namespace {
SDL_Window* s_window = nullptr;
uint32_t s_want_surface_mode = hdr_output::kModeNone;
hdr_output::PlatformCaps s_platform_caps;
// framerate-uncap : intervalle de swap applique ; -2 = jamais/echec. Static de fichier (et
// plus local a la boucle) pour que la bascule de surface force sa re-application.
int s_applied_interval = -2;

// Attributs de surface EGL poses par SDL_EGL_CreateSurface (SDL_HINT_OPENGL_FORCE_SRGB_FRAMEBUFFER
// = "skip" : SDL ne pose plus lui-meme EGL_GL_COLORSPACE ; LINEAR par defaut = identique a avant).
SDL_EGLint* SDLCALL hdr_surface_attribs_cb(void*, SDL_EGLDisplay, SDL_EGLConfig) {
  SDL_EGLint* a = (SDL_EGLint*)SDL_malloc(sizeof(SDL_EGLint) * 3);
  if (!a) {
    return nullptr;
  }
  a[0] = EGL_GL_COLORSPACE_KHR;
  a[1] = s_want_surface_mode == hdr_output::kModeScrgbLinear ? EGL_GL_COLORSPACE_SCRGB_LINEAR_EXT
         : s_want_surface_mode == hdr_output::kModeHdr10Pq   ? EGL_GL_COLORSPACE_BT2020_PQ_EXT
         : s_want_surface_mode == hdr_output::kModeHlg       ? EGL_GL_COLORSPACE_BT2020_HLG_EXT
                                                             : EGL_GL_COLORSPACE_LINEAR_KHR;
  a[2] = EGL_NONE;
  return a;
}

// L'etat de la surface tel que la plateforme le LIT (pas tel qu'on l'a demande).
hdr_output::SurfaceState query_surface_state() {
  // perf-gl-waits : `GL_RED_BITS` decrit le tampon LIE, pas une constante du contexte — on ne
  // peut pas le cacher. C'est une lecture DELIBEREE de hdr-display-output, appelee a l'init et a
  // chaque bascule de surface : elle est declaree et nommee, jamais anonyme.
  gl_query_census::Armed _ap("hdr-surface-state");
  hdr_output::SurfaceState st;
  GLint r = 0;
  if (glad_glBindFramebuffer && glad_glGetIntegerv) {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glGetIntegerv(GL_RED_BITS, &r);
  }
  st.red_bits = r;
  EGLDisplay dpy = eglGetCurrentDisplay();
  EGLSurface surf = eglGetCurrentSurface(EGL_DRAW);
  EGLint cs = 0;
  if (dpy != EGL_NO_DISPLAY && surf != EGL_NO_SURFACE &&
      eglQuerySurface(dpy, surf, EGL_GL_COLORSPACE_KHR, &cs)) {
    st.colorspace = cs;
  } else {
    st.colorspace = 0;
    __android_log_print(ANDROID_LOG_WARN, kLogTag,
                        "HDROUT eglQuerySurface(EGL_GL_COLORSPACE_KHR) failed: egl error 0x%x",
                        (unsigned)eglGetError());
  }
  st.mode = (st.colorspace == EGL_GL_COLORSPACE_BT2020_PQ_EXT && r == 10) ? hdr_output::kModeHdr10Pq
            : (st.colorspace == EGL_GL_COLORSPACE_BT2020_HLG_EXT && r == 10) ? hdr_output::kModeHlg
            : (st.colorspace == EGL_GL_COLORSPACE_SCRGB_LINEAR_EXT && r == 16)
                ? hdr_output::kModeScrgbLinear
                : hdr_output::kModeNone;
  st.hdr = st.mode != hdr_output::kModeNone;
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "HDROUT surface red_bits=%d colorspace=0x%x mode=%u", r,
                      (unsigned)st.colorspace, (unsigned)st.mode);
  return st;
}

// Ce que l'EGL de CE display annonce. Appelable sans contexte courant (sonde precoce).
hdr_output::PlatformCaps probe_platform_caps(EGLDisplay dpy) {
  const char* ext = dpy != EGL_NO_DISPLAY ? eglQueryString(dpy, EGL_EXTENSIONS) : nullptr;
  hdr_output::PlatformCaps caps;
  auto has = [&](const char* n) { return ext && strstr(ext, n) != nullptr; };
  caps.egl_bt2020_pq = has("EGL_EXT_gl_colorspace_bt2020_pq");
  caps.egl_scrgb_linear = has("EGL_EXT_gl_colorspace_scrgb_linear");
  caps.egl_fp16 = has("EGL_EXT_pixel_format_float");
  caps.egl_no_config_ctx = has("EGL_KHR_no_config_context");
  caps.egl_smpte2086 = has("EGL_EXT_surface_SMPTE2086_metadata");
  caps.egl_bt2020_hlg = has("EGL_EXT_gl_colorspace_bt2020_hlg");
  caps.egl_cta861_3 = has("EGL_EXT_surface_CTA861_3_metadata");
  // existe-t-il une config 10 bits fenetre ES3 ?
  EGLint attribs[] = {EGL_RED_SIZE,        10, EGL_GREEN_SIZE,   10, EGL_BLUE_SIZE, 10,
                      EGL_ALPHA_SIZE,      2,  EGL_DEPTH_SIZE,   24, EGL_STENCIL_SIZE, 8,
                      EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
                      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                      EGL_NONE};
  EGLint n = 0;
  EGLConfig cfgs[8];
  caps.config_10bit =
      dpy != EGL_NO_DISPLAY && eglChooseConfig(dpy, attribs, cfgs, 8, &n) && n > 0;
  // existe-t-il une config RGBA 16F (composantes flottantes) fenetre ES3 ? Sondee SEULEMENT si
  // EGL_EXT_pixel_format_float est annoncee : sans l'extension, l'attribut peut etre refuse.
  caps.config_fp16 = false;
  if (caps.egl_fp16 && dpy != EGL_NO_DISPLAY) {
    EGLint attribs16[] = {EGL_RED_SIZE,        16, EGL_GREEN_SIZE, 16, EGL_BLUE_SIZE, 16,
                          EGL_ALPHA_SIZE,      16,
                          EGL_COLOR_COMPONENT_TYPE_EXT, EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT,
                          EGL_DEPTH_SIZE,      24, EGL_STENCIL_SIZE, 8,
                          EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
                          EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                          EGL_NONE};
    EGLint n16 = 0;
    EGLConfig cfgs16[8];
    caps.config_fp16 = eglChooseConfig(dpy, attribs16, cfgs16, 8, &n16) && n16 > 0;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "HDROUT egl caps bt2020_pq=%d scrgb=%d fp16=%d no_config_ctx=%d "
                      "smpte2086=%d bt2020_hlg=%d cta861_3=%d config_10bit=%d config_fp16=%d",
                      caps.egl_bt2020_pq, caps.egl_scrgb_linear, caps.egl_fp16,
                      caps.egl_no_config_ctx, caps.egl_smpte2086, caps.egl_bt2020_hlg,
                      caps.egl_cta861_3, caps.config_10bit, caps.config_fp16);
  return caps;
}

// Le basculeur installe dans hdr_output : fil GL, entre deux images, aucun FBO lie.
bool switch_surface(uint32_t want_mode, hdr_output::SurfaceState* out) {
  s_want_surface_mode = want_mode;
  const bool scrgb = want_mode == hdr_output::kModeScrgbLinear;
  const bool pq = want_mode == hdr_output::kModeHdr10Pq;
  // HLG (BT.2100) transporte dans le MEME conteneur 10 bits que PQ : seule l'OETF differe.
  const bool hlg = want_mode == hdr_output::kModeHlg;
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, scrgb ? 16 : (pq || hlg) ? 10 : 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, scrgb ? 16 : (pq || hlg) ? 10 : 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, scrgb ? 16 : (pq || hlg) ? 10 : 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, scrgb ? 16 : (pq || hlg) ? 2 : 8);
  SDL_GL_SetAttribute(SDL_GL_FLOATBUFFERS, scrgb ? 1 : 0);
  const bool ok = SDL_Android_RecreateEGLSurface(s_window);
  __android_log_print(ok ? ANDROID_LOG_INFO : ANDROID_LOG_ERROR, kLogTag,
                      "HDROUT recreate surface want_mode=%u: %s", (unsigned)want_mode,
                      ok ? "ok" : SDL_GetError());
  if (ok && pq && s_platform_caps.egl_smpte2086) {
    // Metadonnees HDR10 : primaires BT.2020, blanc D65, luminances annoncees par l'ecran.
    EGLDisplay d = eglGetCurrentDisplay();
    EGLSurface s = eglGetCurrentSurface(EGL_DRAW);
    const double k = (double)EGL_METADATA_SCALING_EXT;
    struct {
      EGLint attr;
      double v;
    } md[] = {
        {EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT, 0.708},
        {EGL_SMPTE2086_DISPLAY_PRIMARY_RY_EXT, 0.292},
        {EGL_SMPTE2086_DISPLAY_PRIMARY_GX_EXT, 0.170},
        {EGL_SMPTE2086_DISPLAY_PRIMARY_GY_EXT, 0.797},
        {EGL_SMPTE2086_DISPLAY_PRIMARY_BX_EXT, 0.131},
        {EGL_SMPTE2086_DISPLAY_PRIMARY_BY_EXT, 0.046},
        {EGL_SMPTE2086_WHITE_POINT_X_EXT, 0.3127},
        {EGL_SMPTE2086_WHITE_POINT_Y_EXT, 0.3290},
        {EGL_SMPTE2086_MAX_LUMINANCE_EXT, (double)g_hdr_out_max_lum_nits},
        {EGL_SMPTE2086_MIN_LUMINANCE_EXT, g_hdr_out_min_lum_x10000 / 10000.0},
    };
    for (const auto& m : md) {
      if (!eglSurfaceAttrib(d, s, m.attr, (EGLint)(m.v * k))) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "HDROUT eglSurfaceAttrib(0x%x) failed: egl error 0x%x",
                            (unsigned)m.attr, (unsigned)eglGetError());
      }
    }
  }
  if (ok && pq && s_platform_caps.egl_cta861_3) {
    // HDR10 se decrit par DEUX metadonnees statiques : la maitrise (SMPTE2086, au-dessus) et la
    // lumiere du CONTENU (CTA861.3, ici) ; sans la seconde, un decodeur suppose le pire cas et
    // attenue l'image. MaxCLL = pic annonce par l'ecran, MaxFALL = moyenne annoncee (0 si
    // indisponible). HLG n'en porte aucune : son OETF est relative, il n'y a rien a decrire.
    EGLDisplay d = eglGetCurrentDisplay();
    EGLSurface s = eglGetCurrentSurface(EGL_DRAW);
    const double k = (double)EGL_METADATA_SCALING_EXT;
    struct {
      EGLint attr;
      double v;
    } md[] = {
        {EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT, (double)g_hdr_out_max_lum_nits},
        {EGL_CTA861_3_MAX_FRAME_AVERAGE_LEVEL_EXT, (double)g_hdr_out_max_avg_lum_nits},
    };
    for (const auto& m : md) {
      if (!eglSurfaceAttrib(d, s, m.attr, (EGLint)(m.v * k))) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "HDROUT eglSurfaceAttrib(0x%x) failed: egl error 0x%x",
                            (unsigned)m.attr, (unsigned)eglGetError());
      }
    }
  }
  // scRGB : la marge au-dessus du blanc SDR (setExtendedRangeBrightness) est demandee par
  // hdr_output::take_headroom_request, transmise par la boucle a l'image suivante — ici la
  // surface n'est pas encore comptee active, la valeur serait 1,0.
  s_applied_interval = -2;  // la surface est neuve : re-appliquer l'intervalle de swap
  *out = query_surface_state();
  return ok;
}
}  // namespace

// SONDE PRECOCE (appelee par NativeGk.setDisplayHdrCaps, fil Java, avant le demarrage de GOAL).
// POURQUOI : GOAL cree *pc-settings* et lit `pc-get-hdr-output-modes` dans reset-misc, des le
// boot du noyau — une course contre le fil GL qui sonde EGL apres la creation du contexte. Sans
// cette sonde, le premier demarrage pourrait retenir « aucun mode » sur un ecran HDR. Le
// display par defaut d'Android est initialisable plusieurs fois (compte de references) : on
// n'y laisse rien.
void android_hdr_out_probe_early() {
  EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (dpy == EGL_NO_DISPLAY) {
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "HDROUT early probe: no default display");
    return;
  }
  EGLint major = 0, minor = 0;
  if (!eglInitialize(dpy, &major, &minor)) {
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "HDROUT early probe: eglInitialize failed 0x%x",
                        (unsigned)eglGetError());
    return;
  }
  hdr_output::PlatformCaps caps = probe_platform_caps(dpy);
  s_platform_caps = caps;
  hdr_output::set_platform_caps(caps);
  eglTerminate(dpy);
}

int android_renderer_run() {
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: entered");

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_Init(SDL_INIT_VIDEO) failed: %s",
                        SDL_GetError());
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_Init: video subsystem OK");

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
                      SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

  // hdr-display-output : SDL ne pose plus EGL_GL_COLORSPACE lui-meme, notre callback le pose
  // (LINEAR par defaut, BT2020_PQ a la bascule) ; contexte sans config pour accepter 8 puis
  // 10 bits.
  SDL_SetHint(SDL_HINT_OPENGL_FORCE_SRGB_FRAMEBUFFER, "skip");
  SDL_SetHint("SDL_EGL_NO_CONFIG_CONTEXT", "1");
  SDL_EGL_SetAttributeCallbacks(nullptr, hdr_surface_attribs_cb, nullptr, nullptr);

  // recharged-naming : meme sur un plein ecran sans barre de titre, la fenetre porte un nom
  // (le gestionnaire de fenetres et les outils systeme le lisent). Il disait « OpenGOAL ».
  SDL_Window* window = SDL_CreateWindow(
      external_product_name(), 0, 0,
      SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
  if (window) {
    note_product_name_use("window_title", SDL_GetWindowTitle(window));
  }
  if (!window) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_CreateWindow failed: %s", SDL_GetError());
    SDL_Quit();
    return 1;
  }
  int win_w = 0, win_h = 0;
  SDL_GetWindowSize(window, &win_w, &win_h);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_CreateWindow: %dx%d created", win_w, win_h);
  s_window = window;

  SDL_GLContext glctx = SDL_GL_CreateContext(window);
  if (!glctx) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_GL_CreateContext failed: %s",
                        SDL_GetError());
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_GL_CreateContext: ok");

  if (!SDL_GL_MakeCurrent(window, glctx)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_GL_MakeCurrent failed: %s", SDL_GetError());
    SDL_GL_DestroyContext(glctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "eglMakeCurrent: success");

  // A35: real GL entry points + the ported renderer. On failure we keep
  // the clear/swap loop below and say so — never silently.
  const bool renderer_up = android_gfx::init_renderer_on_gl_thread(win_w, win_h);
  if (!renderer_up) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "android_renderer_run: A35 renderer bring-up FAILED — "
                        "maintaining clear/swap loop only (no game content "
                        "possible this run)");
  } else {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "android_renderer_run: A35 game-content renderer wired "
                        "(DirectRenderer + TextureUploadHandler + EyeRenderer "
                        "buckets; unported buckets skip with named logs)");
  }

  // hdr-display-output : ce que la couche de presentation (EGL) annonce — relu sur le VRAI
  // display courant (la sonde precoce de android_hdr_out_probe_early a deja parle, avant que
  // GOAL ne cree *pc-settings*) —, l'etat initial de la surface, et le basculeur. Apres
  // init_renderer_on_gl_thread : c'est lui qui charge glad, et query_surface_state lit
  // GL_RED_BITS par glad.
  {
    hdr_output::PlatformCaps caps = probe_platform_caps(eglGetCurrentDisplay());
    s_platform_caps = caps;
    hdr_output::set_platform_caps(caps);
    hdr_output::note_surface_state(query_surface_state());
    hdr_output::install_switcher(switch_surface);
  }

  const GLubyte* gl_renderer = glGetString(GL_RENDERER);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "GL_RENDERER: %s",
                      gl_renderer ? reinterpret_cast<const char*>(gl_renderer)
                                  : "(null)");
  const GLubyte* gl_version = glGetString(GL_VERSION);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "GL_VERSION: %s",
                      gl_version ? reinterpret_cast<const char*>(gl_version)
                                 : "(null)");

  glViewport(0, 0, win_w, win_h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);

  // framerate-uncap essai 2 (b) : L'INTERVALLE DE SWAP SUIT LE PLAFOND, ET IL EST RELU.
  // Cette ligne valait `SDL_GL_SetSwapInterval(1)`, appelee ICI et plus jamais : un swap en
  // FIFO rend le rafraichissement du PANNEAU quoi qu'on demande au limiteur — c'est le
  // « cap a 90FPS » que l'owner mesure avec la consigne a 240 sur un panneau 90 Hz. Et
  // `Gfx::g_global_settings.vsync`, que le menu pousse, n'etait relu par PERSONNE sur
  // l'appareil : son seul pousseur est pipelines/opengl.cpp, absent d'android/CMakeLists.txt.
  // La decision vit dans `uncap::desired_swap_interval()` et nulle part ailleurs ; elle est
  // re-appliquee dans la boucle des que le plafond change depuis le menu.
  // `swap_paced` : la presentation nous CADENCE-t-elle ? C'etait `vsync_ok`, le simple succes
  // de l'appel. Un intervalle 0 CHOISI (plafond au-dessus du panneau) est un succes qui ne
  // cadence rien : la boucle doit alors dormir sur une iteration sans chaine, exactement comme
  // quand la synchro etait indisponible. Le predicat est donc « intervalle >= 1 et applique ».
  bool swap_paced = false;
  {
    const int want = uncap::desired_swap_interval();
    const bool ok = SDL_GL_SetSwapInterval(want);
    swap_paced = ok && want >= 1;
    uncap::note_swap_interval_applied(ok ? want : -1);
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A38-UNCAP SDL_GL_SetSwapInterval(%d): %s",
                        want,
                        ok ? "ok" : SDL_GetError());
  }

  g_renderer_frame_count.store(0, std::memory_order_relaxed);

  // A37: register this thread with the hang watchdog (gk_android_main)
  // so a frame-counter stall dumps the GL stack alongside the GOAL one.
  extern pthread_t g_a37_gl_thread;
  extern std::atomic<bool> g_a37_gl_thread_set;
  g_a37_gl_thread = pthread_self();
  g_a37_gl_thread_set.store(true);

  // perf-thread-build : le fil GL suit le fil GOAL sur les gros coeurs. Java lui avait deja
  // donne THREAD_PRIORITY_DISPLAY (SDLActivity.java:2158) mais aucune affinite : EAS pouvait
  // le poser sur un A55 pendant que GOAL tournait sur un A76, et le recouvrement des deux
  // (perf-goal-gl-overlap) n'avait plus de sens.
  sched_affinity::pin_current_thread(sched_affinity::Role::Gl);

  // === Phase F3: per-frame render cadence measurement (prop-armed) =========
  // When debug.opengoal.f3.measure=1, record the swap-to-swap delta of every
  // loop iteration (SDL_GetPerformanceCounter) to $HOME/F3-frame-times.csv and
  // report a WINDOW-scoped "sustained swap" counter so the F3 validator's swap
  // count reflects frames-in-the-measured-window (= real render FPS), not the
  // cumulative-since-boot count. The simulation rate is unaffected: the Gd1
  // wall-clock 60 Hz IOP/overlord vblank pacer (android_gfx.cpp) advances the
  // game clock at 60 Hz regardless of this render cadence. OFF by default →
  // zero cost (one cached property read every 15 frames) for all other runs,
  // and the existing cumulative "sustained swap" log (D3/D4) is untouched.
  const uint64_t f3_perf_freq = SDL_GetPerformanceFrequency();
  uint64_t f3_prev_ctr = 0;
  bool f3_have_prev = false;
  bool f3_armed = false;
  uint64_t f3_window_swaps = 0;
  FILE* f3_csv = nullptr;
  unsigned f3_poll = 0;

  bool running = true;
  while (running && MasterExit == RuntimeExitStatus::RUNNING) {
    // perf-thread-build : le coeur du fil GL, une fois par tour de boucle de rendu.
    sched_affinity::gl_frame();
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      // Phase E1: route SDL gamepad events into the GOAL pad path.
      if (android_input_audio::process_sdl_event(event)) {
        continue;
      }
      if (event.type == SDL_EVENT_QUIT ||
          event.type == SDL_EVENT_TERMINATING) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "android_renderer_run: quit event received");
        running = false;
      }
    }

    SDL_GetWindowSize(window, &win_w, &win_h);

    bool drew_game = false;
    if (renderer_up) {
      // hdr-display-output : une bascule de surface demandee (menu ou auto-test) s'applique
      // ICI, sur le fil GL, entre deux images, aucun FBO lie pour dessiner.
      hdr_output::apply_pending_on_gl_thread();
      {
        // scRGB : la marge souhaitee a change -> SurfaceControl.setExtendedRangeBrightness (Java).
        float current = 1.f, desired = 1.f;
        if (hdr_output::take_headroom_request(&current, &desired)) {
          android_hdr_out_request_extended_range(current, desired);
        }
      }
      {
        // Les deux autres leviers du systeme : mode couleur HDR de la fenetre et
        // Window.setDesiredHdrHeadroom (API 35+). setExtendedRangeBrightness seul laisse le Honor
        // a un ratio de 1,0 (essai 6, 10/09).
        bool lever_on = false;
        float lever_desired = 1.f;
        float lever_brightness = -1.f;
        if (hdr_output::take_window_lever_request(&lever_on, &lever_desired, &lever_brightness)) {
          android_hdr_out_request_window_levers(lever_on, lever_desired, lever_brightness);
        }
      }
      drew_game = android_gfx::render_frame_on_gl_thread(win_w, win_h);
    }

    // A36 canary v2: glad_glClearDepthf went NULL at enter-title with the
    // bucket canary silent and render() never entered — the smash comes from
    // outside the renderer. Check every loop iteration; on flip, dump the
    // neighborhood and KEEP RUNNING (skip the clear) so the run keeps
    // producing evidence instead of dying at the BLR.
    {
      static void* s_canary2 = nullptr;
      static bool s_canary2_init = false;
      static bool s_flipped_logged = false;
      if (!s_canary2_init) {
        s_canary2 = (void*)glad_glClearDepthf;
        s_canary2_init = true;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A36-CANARY2 armed &glad_glClearDepthf=%p val=%p",
                            (void*)&glad_glClearDepthf, s_canary2);
      }
      if ((void*)glad_glClearDepthf != s_canary2 && !s_flipped_logged) {
        s_flipped_logged = true;
        const uint64_t* nb = (const uint64_t*)((uintptr_t)&glad_glClearDepthf & ~15ull);
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A36-CANARY2 FLIPPED val=%p (was %p) — neighborhood:",
                            (void*)glad_glClearDepthf, s_canary2);
        for (int r = -2; r <= 2; r++) {
          __android_log_print(ANDROID_LOG_FATAL, kLogTag, "A36-CANARY2 %p: %016llx %016llx",
                              (const void*)(nb + r * 2), (unsigned long long)nb[r * 2],
                              (unsigned long long)nb[r * 2 + 1]);
        }
      }
    }
    // Gspeed-flicker fix: NEVER present a buffer the game did not draw this
    // cycle. The vblank-locked pacing below runs the engine at a stable
    // sub-60 rate, so some GL iterations get no fresh chain (render_frame_on_
    // gl_thread times out, or we spin while the engine is mid-frame). The old
    // code unconditionally cleared-to-blue + swapped on every chainless
    // iteration, flashing an undrawn frame between good frames -> the owner's
    // "clignotte noir/bleu" regression. Instead:
    //   * boot, before the FIRST real game frame: keep the dark-blue clear+swap
    //     (the intended boot indicator) so the screen isn't a frozen garbage
    //     buffer while the renderer/level loads.
    //   * once a real game frame has been presented: on a chainless iteration,
    //     do NOT clear and do NOT swap -- the compositor holds the last good
    //     front buffer, so the screen stays on the last drawn frame (no flash).
    // This keeps the constant-speed behavior (clock + pacing still advance only
    // on real drawn frames, below) while eliminating the black/blue flicker.
    static bool s_ever_drew = false;
    bool present_this_cycle;
    if (drew_game) {
      s_ever_drew = true;
      present_this_cycle = true;
    } else if (!s_ever_drew && glad_glClearDepthf) {
      // Boot only: dark-blue clear so a chainless pre-title frame is a clean
      // boot color, not a stale/garbage buffer.
      glViewport(0, 0, win_w, win_h);
      glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
      glClearDepthf(1.0f);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
      present_this_cycle = true;
    } else {
      // Mid-game chainless iteration: hold the last good frame (no swap).
      present_this_cycle = false;
    }

    // framerate-uncap essai 2 (b) : le plafond change depuis le menu PENDANT que le jeu
    // tourne. On relit la decision a chaque image et on ne parle a SDL que sur transition.
    {
      // `s_applied_interval` : static de fichier (voir hdr-display-output plus haut).
      const int want = uncap::desired_swap_interval();
      if (want != s_applied_interval) {
        const bool ok = SDL_GL_SetSwapInterval(want);
        s_applied_interval = ok ? want : -2;
        swap_paced = ok && want >= 1;
        uncap::note_swap_interval_applied(ok ? want : -1);
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A38-UNCAP swap interval -> %d: %s",
                            want,
                            ok ? "ok" : SDL_GetError());
      }
    }

    if (present_this_cycle) {
      SDL_GL_SwapWindow(window);
      android_gfx::post_swap_tick();
      // framerate-uncap essai 2 (b) : `uncap_ceiling_hz` est une cadence de PRESENTATION.
      // Elle se compte ici, au swap, et pas dans la boucle EE : le mode `overlap`
      // d'android_gfx decouple les deux.
      uncap::note_present();
      // anim-interp-low-fps — LA CADENCE QUE L'OEIL VOIT. `render_pace` chronometre la
      // boucle EE ; l'ecran, lui, ne change qu'ici. Si les deux divergeaient, tout ce
      // module corrigerait une horloge que personne ne regarde. Un compteur, pas une
      // correction : rien du rendu n'en depend.
      render_pace::note_present();
      // Gcamera-smooth: TRUE present-interval probe (debug.opengoal.pace.measure).
      // Raw wall-clock dt between successive SwapWindow calls = the actual on-screen
      // cadence. Compared against the EE-loop "PACE-EE" dt: if the game camera
      // advances a constant delta per frame but this present dt jitters, that is the
      // pan judder ("the view doesn't follow the framerate"). Diagnostic only.
      {
        static unsigned s_pace_poll = 0;
        static bool s_pace = false;
        if ((s_pace_poll++ & 15) == 0) {
          char pv[8] = {0};
          s_pace = __system_property_get("debug.opengoal.pace.measure", pv) > 0 && pv[0] == '1';
        }
        if (s_pace) {
          using namespace std::chrono;
          static steady_clock::time_point s_last{};
          static unsigned s_pn = 0;
          auto now = steady_clock::now();
          if (s_last.time_since_epoch().count() != 0) {
            double dt = duration_cast<duration<double, std::milli>>(now - s_last).count();
            __android_log_print(ANDROID_LOG_INFO, kLogTag, "PACE-SWAP n=%u dt_ms=%.3f",
                                s_pn++, dt);
          }
          s_last = now;
        }
      }
      // Publish the REAL measured render rate for the GOAL on-screen FPS counter
      // (pc-get-fps). Measured here on actual presented frames, so it reflects the
      // true free-running Adreno cadence (e.g. ~30 at Geyser, ~60 light) -- the
      // real fluctuating fps. Smoothed with the same 0.9/0.1 EMA as the desktop.
      {
        using namespace std::chrono;
        static steady_clock::time_point s_fps_last{};
        static bool s_fps_have_last = false;
        static float s_fps_smoothed_dt = 1.f / 60.f;
        auto fps_now = steady_clock::now();
        if (s_fps_have_last) {
          float dt = duration_cast<duration<float>>(fps_now - s_fps_last).count();
          if (dt > 0.f && dt < 1.f) {
            s_fps_smoothed_dt = (0.9f * s_fps_smoothed_dt) + (0.1f * dt);
          }
        }
        s_fps_last = fps_now;
        s_fps_have_last = true;
        Gfx::g_global_settings.measured_fps =
            (s_fps_smoothed_dt > 0.f) ? (1.f / s_fps_smoothed_dt) : 0.f;
        // Grecharged-ambient-occlusion: fps-matrix harvest line (mirrors the desktop
        // AOPERF line in pipelines/opengl.cpp, which is not compiled on Android). Every
        // 120 presented frames, emit the RESOLVED AO mode/quality (settings or the
        // debug.opengoal.ao.force_* prop override) + measured fps + render busy-ms so
        // the per-combo cost curve can be harvested from logcat.
        {
          static unsigned s_aoperf_n = 0;
          if ((s_aoperf_n++ % 120) == 0) {
            __android_log_print(ANDROID_LOG_INFO, kLogTag,
                                "AOPERF mode=%d quality=%d strength=%d fps=%.1f busy_ms=%.2f",
                                AmbientOcclusionPass::effective_mode(),
                                AmbientOcclusionPass::effective_quality(),
                                AmbientOcclusionPass::effective_strength(),
                                Gfx::g_global_settings.measured_fps,
                                Gfx::g_global_settings.measured_frame_busy_ms);
          }
        }
      }
    }

    // ===== Gframerate-variable: framerate cap lives in vsync() (EE thread) ====
    // The old vblank cadence-LOCK lived here (phase Gframerate-variable removed
    // it: no more whole-vblank-step forcing, no fake stable-grid clock). The
    // present-rate cap can NOT live here: the GOAL game loop (EE thread) is not
    // 1:1-gated by this GL present (vsync()'s frame_idx barrier returns early when
    // the EE is faster than the GL picks up a new chain), so a GL-thread cap would
    // throttle the screen but the EE would still spin ahead and over-advance the
    // game clock. The framerate cap therefore lives in android_gfx::vsync() (EE
    // thread) so the game clock itself is bounded to target-fps; see the comment
    // there. Here we only avoid busy-spinning on a chainless cycle.
    if (!drew_game) {
      // Chainless cycle (no fresh game frame): held the last good front buffer
      // above (no swap), so sleep briefly to avoid busy-spinning while we wait
      // for the next chain. Advances no game clock.
      std::this_thread::sleep_for(std::chrono::microseconds(1500));
    }
    // =========================================================================

    // === Phase F3 measurement (prop-armed; see block above the loop) =======
    if ((f3_poll++ % 15) == 0) {
      char pv[8] = {0};
      const bool want =
          __system_property_get("debug.opengoal.f3.measure", pv) > 0 && pv[0] == '1';
      if (want && !f3_armed) {
        f3_armed = true;
        f3_window_swaps = 0;
        f3_have_prev = false;
        const char* home = getenv("HOME");
        std::string p = (home && *home)
                            ? std::string(home) + "/F3-frame-times.csv"
                            : std::string("/data/local/tmp/F3-frame-times.csv");
        if (f3_csv) {
          fclose(f3_csv);
        }
        f3_csv = fopen(p.c_str(), "w");
        if (f3_csv) {
          fprintf(f3_csv, "frame_time_us\n");
        }
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "F3-MEASURE armed: per-frame swap cadence -> %s "
                            "(simulation stays 60 Hz via vblank pacer)",
                            p.c_str());
      } else if (!want && f3_armed) {
        f3_armed = false;
        if (f3_csv) {
          fflush(f3_csv);
          fclose(f3_csv);
          f3_csv = nullptr;
        }
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "F3-MEASURE disarmed: CSV flushed (%" PRIu64
                            " frames in window)",
                            f3_window_swaps);
      }
    }
    const uint64_t f3_now = SDL_GetPerformanceCounter();
    if (f3_armed) {
      if (f3_have_prev && f3_perf_freq) {
        const uint64_t us =
            (uint64_t)((f3_now - f3_prev_ctr) * 1000000ull / f3_perf_freq);
        if (f3_csv) {
          fprintf(f3_csv, "%llu\n", (unsigned long long)us);
          if ((f3_window_swaps % 60) == 0) {
            fflush(f3_csv);
          }
        }
      }
      f3_window_swaps++;
    }
    f3_prev_ctr = f3_now;
    f3_have_prev = true;

    // Keep the global counter monotonic (A37 watchdog heartbeat); report the
    // window-scoped count while F3 is armed so the validator measures FPS in
    // the gameplay window, not the cumulative since-boot total.
    const uint64_t n =
        g_renderer_frame_count.fetch_add(1, std::memory_order_relaxed) + 1;
    const uint64_t report = f3_armed ? f3_window_swaps : n;
    if ((report % 60) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "android_renderer: sustained swap %" PRIu64
                          " (game_frames=%s)",
                          report, drew_game ? "flowing" : "none");
    }

    if (!drew_game && !swap_paced) {
      SDL_Delay(16);
    }
  }

  if (f3_csv) {
    fflush(f3_csv);
    fclose(f3_csv);
    f3_csv = nullptr;
  }

  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: exiting");
  return 0;
}
