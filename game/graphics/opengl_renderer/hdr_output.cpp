#include "game/graphics/opengl_renderer/hdr_output.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace hdr_output {
namespace {

// Valeurs EGL brutes (EGL_KHR_gl_colorspace / EGL_EXT_gl_colorspace_bt2020_pq /
// EGL_EXT_gl_colorspace_scrgb_linear), reprises ici pour que la publication ne depende pas des
// en-tetes EGL sur le bureau.
constexpr int kEglColorspaceSrgb = 0x3089;
constexpr int kEglColorspaceLinear = 0x308A;
constexpr int kEglColorspaceBt2020Pq = 0x3340;
constexpr int kEglColorspaceScrgbLinear = 0x3350;

// Quand l'ecran n'annonce pas sa luminance maximale : la valeur par defaut du compositeur
// Android (SurfaceFlinger, `sDefaultMaxLumiance`), pas le plafond HDR10 de 1000 nits.
constexpr float kDefaultMaxNits = 500.f;
// scRGB : la marge DEMANDEE au systeme (SurfaceControl.setExtendedRangeBrightness). Le
// systeme accorde ce qu'il peut et le dit par Display.getHdrSdrRatio ; le plafond du tone map
// suit ce qui est LU, jamais ce qui est demande.
constexpr float kDesiredHeadroom = 4.f;
constexpr float kHeadroomMax = 8.f;

// ------------------------------------------------------------------------------ capacites --
struct SysCaps {
  bool reported = false;
  uint32_t types = 0;
  int max_lum = 0;
  int max_avg = 0;
  int min_lum_x10000 = 0;
  bool wide_gamut = false;
  int sdk_int = 0;
  bool ratio_available = false;
};
std::mutex s_mu;  // garde s_sys, s_plat, s_caps_text (ecrits depuis Java/EE, lus sur GL)
SysCaps s_sys;
PlatformCaps s_plat;
std::string s_caps_text = "sys:unreported;platform:unprobed";
std::atomic<int> s_ratio_x1000{1000};  // Display.getHdrSdrRatio x1000, 1000 = aucune marge
// INSTANTANE PAR IMAGE du ratio, pose au debut de l'image sur le fil GL (apply_pending_on_gl_thread).
// Le listener Java ecrit s_ratio_x1000 a tout moment ; tonemap_ceiling() (au tone map) et
// frame_end() (au verdict 4, `ceiling_bad`) le liraient a deux instants differents : un changement
// entre les deux comptait une image « mauvaise » qui n'etait qu'une course de lecture. Tout ce que
// l'image lit (plafond, `current` declare au compositeur, verdict) passe par cet instantane.
int s_frame_ratio_x1000 = 1000;

void rebuild_caps_text_locked() {
  std::string t;
  t += "sys:";
  if (!s_sys.reported) {
    t += "unreported";
  } else if (s_sys.types == 0) {
    t += "none";
  } else {
    bool first = true;
    auto add = [&](uint32_t bit, const char* name) {
      if (s_sys.types & bit) {
        if (!first) {
          t += ",";
        }
        t += name;
        first = false;
      }
    };
    add(kSysDolbyVision, "dolby_vision");
    add(kSysHdr10, "hdr10");
    add(kSysHlg, "hlg");
    add(kSysHdr10Plus, "hdr10plus");
    add(kSysSdl, "sdl");
  }
  t += ";maxlum=" + std::to_string(s_sys.max_lum);
  t += ";maxavg=" + std::to_string(s_sys.max_avg);
  t += ";minlum_x10000=" + std::to_string(s_sys.min_lum_x10000);
  t += std::string(";wcg=") + (s_sys.wide_gamut ? "1" : "0");
  t += ";sdk=" + std::to_string(s_sys.sdk_int);
  t += std::string(";ratio_api=") + (s_sys.ratio_available ? "1" : "0");
  t += ";egl:";
  if (!s_plat.probed) {
    t += "unprobed";
  } else {
    std::string e;
    auto add = [&](bool on, const char* name) {
      if (on) {
        if (!e.empty()) {
          e += ",";
        }
        e += name;
      }
    };
    add(s_plat.egl_bt2020_pq, "bt2020_pq");
    add(s_plat.egl_scrgb_linear, "scrgb_linear");
    add(s_plat.egl_fp16, "fp16");
    add(s_plat.egl_no_config_ctx, "no_config_ctx");
    add(s_plat.egl_smpte2086, "smpte2086");
    t += e.empty() ? "none" : e;
  }
  t += std::string(";cfg10=") + (s_plat.config_10bit ? "1" : "0");
  t += std::string(";cfg16f=") + (s_plat.config_fp16 ? "1" : "0");
  t += std::string(";sdl_display_hdr=") + (s_plat.sdl_display_hdr ? "1" : "0");
  t += std::string(";sdl_window_hdr=") + (s_plat.sdl_window_hdr ? "1" : "0");
  t += ";sdl_headroom_x100=" + std::to_string(s_plat.sdl_headroom_x100);
  s_caps_text = t;
}

uint32_t modes_locked() {
  // Un mode n'est « annonce » que si le SYSTEME dit que l'ecran est HDR ET que la couche de
  // presentation sait creer une surface dans cet espace. Bureau : SDL peut annoncer un ecran
  // HDR, mais aucune presentation OpenGL en HDR n'existe par SDL3 — donc aucun mode, et la
  // capacite est publiee telle quelle pour que ce soit lisible, pas suppose.
  // UN SEUL mode est retenu : scRGB des que l'API le contractualise (Android 14+, API 34 :
  // 1,0 = blanc SDR, marge = Display.getHdrSdrRatio), sinon HDR10 PQ.
  if (!s_sys.reported || !s_plat.probed) {
    return kModeNone;
  }
  const bool sys_hdr = (s_sys.types & (kSysHdr10 | kSysHlg | kSysHdr10Plus | kSysDolbyVision)) != 0;
  if (!sys_hdr) {
    return kModeNone;
  }
  if (s_sys.sdk_int >= 34 && s_plat.egl_scrgb_linear && s_plat.egl_fp16 && s_plat.config_fp16) {
    return kModeScrgbLinear;
  }
  if (s_plat.egl_bt2020_pq && s_plat.config_10bit) {
    return kModeHdr10Pq;
  }
  return kModeNone;
}

// ---------------------------------------------------------------------------- interrupteur --
std::atomic<int> s_setting{0};        // le reglage du joueur (GOAL)
std::atomic<int> s_test_force{-1};    // auto-test : -1 = aucun, 0/1 = impose
std::atomic<bool> s_active{false};    // la surface est HDR
std::atomic<int> s_override{-2};      // debug.opengoal.hdr.out / OG_HDR_OUT : -2 pas lu, -1 absent
Switcher s_switcher;
SurfaceState s_surface;               // fil GL
int s_last_want = -1;                 // fil GL : derniere demande tentee (mode)
uint64_t s_switch_ok = 0, s_switch_fail = 0;
float s_white_override = -1.f;        // PQ : debug.opengoal.hdr.out.white (nits), -1 = pas lu, 0 = absent
// Verdict 10 (owner 09/09 : « celui-ci fait 480, mais quid d'un ecran a 1000 ? ») : le pic
// annonce peut etre SIMULE par debug.opengoal.hdr.out.peak / OG_HDR_OUT_PEAK (nits), et
// l'auto-test impose lui-meme un pic simule dans sa phase 3 par ce MEME chemin.
float s_peak_knob = -1.f;             // -1 = pas lu, 0 = absent, sinon nits
float s_test_peak = 0.f;              // auto-test : 0 = aucun, sinon nits imposes
bool s_headroom_pending = false;      // fil GL : une demande de marge a transmettre au systeme
float s_headroom_request_current = 1.f;  // ratio auquel le tampon est encode (= ratio LU)
float s_headroom_request_desired = 1.f;  // marge souhaitee (promotion HDR de la couche)
float s_headroom_sent_current = -1.f;    // dernier `current` transmis (-1 = jamais)
uint64_t s_headroom_requests = 0;

int read_int_knob(const char* prop, const char* env, int absent) {
#ifdef __ANDROID__
  (void)env;
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    return std::atoi(buf);
  }
#else
  (void)prop;
  const char* e = std::getenv(env);
  if (e && e[0]) {
    return std::atoi(e);
  }
#endif
  return absent;
}

int override_setting() {
  int v = s_override.load();
  if (v == -2) {
    v = read_int_knob("debug.opengoal.hdr.out", "OG_HDR_OUT", -1);
    s_override.store(v);
    if (v >= 0) {
      lg::info("[hdr-display-output] reglage epingle par le harnais : hdr.out={}", v);
    }
  }
  return v;
}

// Le reglage EFFECTIF : auto-test > epingle du harnais > reglage du joueur.
bool effective_setting() {
  const int tf = s_test_force.load();
  if (tf >= 0) {
    return tf != 0;
  }
  const int ov = override_setting();
  if (ov >= 0) {
    return ov != 0;
  }
  return s_setting.load() != 0;
}

// La sortie HDR est une SOUS-OPTION de l'eclairage Recharged : sans lui, pas de tone map, donc
// rien a laisser monter. Compose master + eclairage par l'unique helper de gfx.h.
bool lighting_gate() {
  return Gfx::recharged_lighting_active();
}

float desired_headroom() {
  const int k = read_int_knob("debug.opengoal.hdr.out.headroom", "OG_HDR_OUT_HEADROOM", 0);
  float d = (k >= 100 && k <= 800) ? (float)k / 100.f : kDesiredHeadroom;
  return d;
}

// Le pic ANNONCE par l'ecran (HdrCapabilities.maxLuminance), ou le defaut du compositeur.
float announced_peak_nits() {
  int max_lum = 0;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    max_lum = s_sys.max_lum;
  }
  return max_lum > 0 ? (float)max_lum : kDefaultMaxNits;
}

// Le pic EFFECTIF : auto-test > propriete de debug > annonce.
float peak_nits() {
  if (s_test_peak > 0.f) {
    return s_test_peak;
  }
  if (s_peak_knob < 0.f) {
    const int v = read_int_knob("debug.opengoal.hdr.out.peak", "OG_HDR_OUT_PEAK", 0);
    s_peak_knob = (v >= 80 && v <= 10000) ? (float)v : 0.f;
    if (s_peak_knob > 0.f) {
      lg::warn("[hdr-display-output] pic d'ecran SIMULE par le harnais : {} nits", s_peak_knob);
    }
  }
  return s_peak_knob > 0.f ? s_peak_knob : announced_peak_nits();
}

float ratio_linear() {
  float r = (float)s_frame_ratio_x1000 / 1000.f;  // l'instantane de l'image, jamais l'atomique
  if (!(r >= 1.f)) {
    r = 1.f;
  }
  // scRGB : la marge du systeme est celle du pic REEL ; un pic simule l'etire dans la meme
  // proportion (c'est ce qu'un ecran a ce pic, au meme blanc SDR, accorderait).
  const float ann = announced_peak_nits();
  const float pk = peak_nits();
  if (ann > 0.f && pk > 0.f && pk != ann) {
    r *= pk / ann;
  }
  if (r > kHeadroomMax) {
    r = kHeadroomMax;
  }
  return r;
}

// ------------------------------------------------------------------------------- la preuve --
// Quatre phases, par image : 0 = etat charge, 1 = ON impose, 2 = OFF impose, 3 = ON impose avec un
// pic d'ecran SIMULE (verdict 10), 4 = termine.
constexpr uint64_t kPhaseFrames = 150;
constexpr int kPhaseCount = 4;
constexpr float kSimPeakNits = 1000.f;
constexpr uint64_t kProbeEvery = 5;
constexpr int kReadyHits = 3;
constexpr uint64_t kReadyPx = 256;   // un quart de la sonde 32x32 en tons moyens
constexpr double kReadyCapSeconds = 120.0;
struct PhaseStats {
  uint64_t frames = 0;
  uint64_t active_frames = 0;
  uint64_t surface_hdr_frames = 0;
  uint64_t sites_bad = 0;      // images dont le recensement n'a pas rendu 1
  uint64_t ui_bad = 0;         // format UI different de l'attendu
  uint64_t present_bad = 0;    // mode du quad final different de l'attendu
  uint64_t ceiling_bad = 0;    // plafond du tone map different de l'attendu
  int last_red_bits = -1;
  int last_colorspace = -1;
  uint32_t last_mode = 0;
  float last_ceiling = 1.f;
  float last_peak = 0.f;
};
// Les sondes, cumulees PAR PHASE (1 = ON reel, 3 = ON pic simule).
struct ProbeStats {
  uint64_t ui_samples = 0;
  double ui_white_sum = 0.0;   // PQ : nits ; scRGB : lineaire (1,0 = blanc SDR)
  double ui_white_min = 1e30;
  double ui_ref_sum = 0.0;     // valeur SDR du meme blanc, LINEAIRE (display^2,2)
  uint64_t tm_samples = 0, tm_px = 0;
  double tm_sum_off = 0.0, tm_sum_on = 0.0;
  double hl_max = 0.0;         // plus haute valeur (canal max) ecrite par le tone map ON
};
uint64_t s_frames = 0;
uint64_t s_forced_on_frames = 0;
uint64_t s_hits = 0;
int s_phase = 0;
// L'image de TRANSITION : une demande posee a la fin de l'image N est appliquee au debut de
// l'image N+1 (apply_pending_on_gl_thread, meme fil). L'image N elle-meme a ete dessinee dans
// l'ancien etat — la compter dans la nouvelle phase mesurerait la latence d'une image, pas
// l'interrupteur. Course 1 sur le Honor : exactement 1 image « mauvaise » par phase OFF, la
// premiere. On saute donc UNE image apres chaque transition, jamais plus.
int s_skip_frames = 0;
bool s_selftest_done = false;
// LE DEPART DE L'AUTO-TEST ATTEND UNE SCENE. Mesure x86 du 09/09 (essai 3) : phases ON/OFF
// deroulees de 01:08 a 01:17, scene du titre affichee a 01:27 — les sondes de tons moyens et de
// hautes lumieres (verdicts 9 et 10) mesuraient l'intro NOIRE, tm_px=0. Regle : la phase ON ne
// commence qu'apres kReadyHits sondes consecutives ou la scene tone-mappee porte au moins
// kReadyPx tons moyens (sur kTmW*kTmH), ou a defaut apres kReadyCapSeconds de mur (le proof
// finit toujours ; le forcage est publie, jamais tu).
uint64_t s_phase_start = 0;          // image ou la phase 1 a commence (0 = pas encore)
int s_ready_hits = 0;                // sondes consecutives avec assez de tons moyens
uint64_t s_ready_last_px = 0;        // derniere sonde de contenu : tons moyens comptes
uint64_t s_ready_probes = 0;
int s_ready_forced = 0;              // 1 = plafond de temps atteint sans scene
bool s_clock_started = false;
std::chrono::steady_clock::time_point s_clock0;
PhaseStats s_ph[kPhaseCount];
ProbeStats s_pr[kPhaseCount];
int s_last_present_mode = 0;   // ce que push_present_uniforms a pousse pour cette image
float s_last_ceiling = 1.f;    // ce que tonemap_ceiling() a rendu pour cette image
int s_visible_reported = -1;   // GOAL : -1 jamais, 0/1
int s_loaded_value = -1;       // GOAL : -1 jamais, 0/1
int s_loaded_source = -1;      // GOAL : 0 fichier, 1 auto-configuration
int s_menu_parent = -1;        // GOAL : -1 jamais, 1 = sous RECHARGED LIGHTING, 0 = ailleurs
int s_persisted = -3;          // relecture disque : -3 pas encore lue
int s_defects = -1;
int s_d[11] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

// Sonde de blanc UI (probe_present) : ce que le quad final ECRIT pour un blanc (1,1,1) du jeu,
// dans le mode courant, et ce qu'il ecrirait en recopie SDR (u_out_mode = 0) pour le meme blanc
// — la reference « ce que le SDR montre » inclut donc le reglage de luminosite du joueur.
GLuint s_pp_fbo = 0, s_pp_tex = 0, s_pp_white = 0;
int s_pp_state = 0;  // 0 pas cree, 1 pret, -1 indisponible
// Sonde d'assombrissement (probe_tonemap) : luminance lineaire des tons moyens de la scene,
// tone-mappee au plafond 1,0 (le SDR) et au plafond HDR courant, sur la MEME image.
GLuint s_tm_fbo[2] = {0, 0}, s_tm_tex[2] = {0, 0};
int s_tm_state = 0;
constexpr int kTmW = 32, kTmH = 32;

bool measuring() {
  return autoport_proof::feature_is(kItemId) && autoport_proof::armed_for(kItemId);
}

bool probe_window_open() {
  // Les sondes ne tournent qu'en phase ON, une image sur kProbeEvery, hors transition.
  return measuring() && !s_selftest_done && (s_phase == 1 || s_phase == 3) &&
         s_skip_frames == 0 && s_active.load() && (s_frames % kProbeEvery) == 0;
}

float half_to_float(uint16_t h) {
  const uint32_t sign = (uint32_t)(h >> 15) << 31;
  uint32_t exp = (h >> 10) & 0x1f;
  uint32_t man = h & 0x3ff;
  uint32_t bits;
  if (exp == 0) {
    if (man == 0) {
      bits = sign;
    } else {
      exp = 127 - 15 + 1;
      while ((man & 0x400) == 0) {
        man <<= 1;
        exp--;
      }
      man &= 0x3ff;
      bits = sign | (exp << 23) | (man << 13);
    }
  } else if (exp == 0x1f) {
    bits = sign | 0x7f800000u | (man << 13);
  } else {
    bits = sign | ((exp + 127 - 15) << 23) | (man << 13);
  }
  float f;
  std::memcpy(&f, &bits, sizeof(f));
  return f;
}

// Relit un FBO flottant lie en lecture. Rend faux si l'implementation refuse.
bool read_float_fbo(int w, int h, std::vector<float>& px) {
  GLint read_fmt = 0, read_type = 0;
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &read_fmt);
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &read_type);
  px.assign((size_t)w * h * 4, 0.f);
  while (glGetError() != GL_NO_ERROR) {
  }
  if (read_fmt == GL_RGBA && read_type == GL_HALF_FLOAT) {
    std::vector<uint16_t> raw((size_t)w * h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_HALF_FLOAT, raw.data());
    if (glGetError() != GL_NO_ERROR) {
      return false;
    }
    for (size_t i = 0; i < raw.size(); i++) {
      px[i] = half_to_float(raw[i]);
    }
    return true;
  }
  glReadPixels(0, 0, w, h, GL_RGBA, GL_FLOAT, px.data());
  return glGetError() == GL_NO_ERROR;
}

bool make_float_fbo(GLuint* fbo, GLuint* tex, int w, int h, const float* fill) {
  glGenFramebuffers(1, fbo);
  glGenTextures(1, tex);
  glBindTexture(GL_TEXTURE_2D, *tex);
  std::vector<float> data;
  if (fill) {
    data.assign((size_t)w * h * 4, 0.f);
    for (size_t i = 0; i < data.size(); i += 4) {
      data[i] = fill[0];
      data[i + 1] = fill[1];
      data[i + 2] = fill[2];
      data[i + 3] = fill[3];
    }
  }
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, w, h, 0, GL_RGBA, GL_FLOAT,
               fill ? data.data() : nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
  const GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (st != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[hdr-display-output] FBO de sonde indisponible : 0x{:x}", (unsigned)st);
    return false;
  }
  return true;
}

float pq_eotf_nits(float v) {
  // SMPTE ST 2084, inverse de l'OETF de post_processing.frag.
  const double m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625,
               c3 = 18.6875;
  double e = v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
  double ep = std::pow(e, 1.0 / m2);
  double num = ep - c1;
  if (num < 0.0) {
    num = 0.0;
  }
  double den = c2 - c3 * ep;
  if (den <= 0.0) {
    return 10000.f;
  }
  return (float)(std::pow(num / den, 1.0 / m1) * 10000.0);
}

double lum_linear(float r, float g, float b) {
  auto lin = [](float x) { return std::pow((double)(x < 0.f ? 0.f : x), 2.2); };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

void publish_all() {
  // Le verrou ne couvre que la COPIE des capacites : sdr_white_nits(), paper_white() et
  // sdr_white_source() le reprennent (mutex non recursif — un publish_all qui le tenait
  // pendant ces appels a fige gk x86 a l'image 105, smoke du 09/09).
  std::string caps_text;
  SysCaps sys;
  bool plat_probed = false;
  uint32_t modes = kModeNone;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    caps_text = s_caps_text;
    sys = s_sys;
    plat_probed = s_plat.probed;
    modes = modes_locked();
  }
  autoport_proof::publish_text("hdr_out_display_caps", caps_text.c_str());
  autoport_proof::publish("hdr_out_sys_reported", sys.reported ? 1 : 0);
  autoport_proof::publish("hdr_out_sys_types_mask", sys.types);
  autoport_proof::publish("hdr_out_platform_probed", plat_probed ? 1 : 0);
  autoport_proof::publish("hdr_out_sdk_int", (uint64_t)(sys.sdk_int < 0 ? 0 : sys.sdk_int));
  autoport_proof::publish("hdr_out_ratio_available", sys.ratio_available ? 1 : 0);
  autoport_proof::publish("hdr_out_hdr_sdr_ratio_x1000", (uint64_t)s_ratio_x1000.load());
  autoport_proof::publish("hdr_out_modes_available", modes);
  autoport_proof::publish_text("hdr_out_mode_retained", mode_name(modes));
  autoport_proof::publish("hdr_out_autoconfig_mode", modes ? 1 : 0);
  autoport_proof::publish("hdr_out_setting", s_setting.load() != 0 ? 1 : 0);
  autoport_proof::publish("hdr_out_effective", effective_setting() ? 1 : 0);
  autoport_proof::publish("hdr_out_lighting_gate", lighting_gate() ? 1 : 0);
  autoport_proof::publish("hdr_out_active", s_active.load() ? 1 : 0);
  autoport_proof::publish("hdr_out_surface_red_bits", (uint64_t)(s_surface.red_bits < 0 ? 0 : s_surface.red_bits));
  autoport_proof::publish("hdr_out_surface_colorspace", (uint64_t)(s_surface.colorspace < 0 ? 0 : s_surface.colorspace));
  autoport_proof::publish("hdr_out_surface_mode", (uint64_t)s_surface.mode);
  autoport_proof::publish("hdr_out_switch_ok", s_switch_ok);
  autoport_proof::publish("hdr_out_switch_fail", s_switch_fail);
  autoport_proof::publish("hdr_out_forced_on", s_forced_on_frames);
  autoport_proof::publish("hdr_out_frames", s_frames);
  autoport_proof::publish("hdr_out_hdr_frames", s_hits);
  // Le blanc : ce que le systeme donne, ce que le quad final ecrit, et sa reference SDR.
  const float sdr_white = sdr_white_nits();
  autoport_proof::publish("hdr_out_sdr_white_nits", (uint64_t)std::lround(sdr_white));
  autoport_proof::publish_text("hdr_out_sdr_white_source", sdr_white_source());
  autoport_proof::publish("hdr_out_paper_white_nits",
                          (uint64_t)std::lround(s_surface.mode == kModeHdr10Pq ? paper_white() : 0.f));
  autoport_proof::publish("hdr_out_headroom_x100", (uint64_t)std::lround(headroom_linear() * 100.f));
  autoport_proof::publish("hdr_out_erb_requests", s_headroom_requests);
  autoport_proof::publish("hdr_out_erb_current_x1000",
                          (uint64_t)std::lround((s_headroom_sent_current < 0.f ? 0.f : s_headroom_sent_current) * 1000.f));
  autoport_proof::publish("hdr_out_erb_desired_x100", (uint64_t)std::lround(s_headroom_request_desired * 100.f));
  autoport_proof::publish("hdr_out_ceiling_x100", (uint64_t)std::lround(s_last_ceiling * 100.f));
  autoport_proof::publish("hdr_out_present_mode", (uint64_t)s_last_present_mode);
  autoport_proof::publish("hdr_out_peak_nits", (uint64_t)std::lround(announced_peak_nits()));
  autoport_proof::publish("hdr_out_peak_effective_nits", (uint64_t)std::lround(peak_nits()));
  autoport_proof::publish("hdr_out_peak_sim_nits", (uint64_t)std::lround(s_test_peak));
  const bool pq = s_ph[1].last_mode == kModeHdr10Pq;
  const char* pnames[2] = {"", "sim_"};
  const int pidx[2] = {1, 3};
  for (int k = 0; k < 2; k++) {
    const ProbeStats& pr = s_pr[pidx[k]];
    const std::string pre = std::string("hdr_out_") + pnames[k];
    autoport_proof::publish((pre + "ui_white_samples").c_str(), pr.ui_samples);
    const double ui_mean = pr.ui_samples ? pr.ui_white_sum / (double)pr.ui_samples : 0.0;
    const double ui_ref = pr.ui_samples ? pr.ui_ref_sum / (double)pr.ui_samples : 0.0;
    autoport_proof::publish((pre + "ui_white_nits").c_str(), (uint64_t)std::lround(pq ? ui_mean : 0.0));
    autoport_proof::publish((pre + "ui_white_min_nits").c_str(),
                            (uint64_t)std::lround(pq && pr.ui_samples ? pr.ui_white_min : 0.0));
    autoport_proof::publish((pre + "ui_white_rel_x1000").c_str(),
                            (uint64_t)std::lround(pq ? (sdr_white > 0.f ? ui_mean / sdr_white * 1000.0 : 0.0)
                                                     : ui_mean * 1000.0));
    autoport_proof::publish((pre + "ui_white_ref_rel_x1000").c_str(), (uint64_t)std::lround(ui_ref * 1000.0));
    autoport_proof::publish((pre + "darkening_samples").c_str(), pr.tm_samples);
    autoport_proof::publish((pre + "darkening_px").c_str(), pr.tm_px);
    double dark_signed = 0.0;
    if (pr.tm_px && pr.tm_sum_off > 0.0) {
      dark_signed = 100.0 * (1.0 - pr.tm_sum_on / pr.tm_sum_off);
    }
    autoport_proof::publish((pre + "darkening_signed_x100").c_str(),
                            (uint64_t)(dark_signed < 0.0 ? 0 : std::lround(dark_signed * 100.0)));
    autoport_proof::publish((pre + "brightening_signed_x100").c_str(),
                            (uint64_t)(dark_signed > 0.0 ? 0 : std::lround(-dark_signed * 100.0)));
    autoport_proof::publish((pre + "darkening_pct").c_str(),
                            (uint64_t)(dark_signed < 0.0 ? 0 : std::lround(dark_signed)));
    autoport_proof::publish((pre + "hl_max_x1000").c_str(), (uint64_t)std::lround(pr.hl_max * 1000.0));
    autoport_proof::publish((pre + "ceiling_x100").c_str(),
                            (uint64_t)std::lround(s_ph[pidx[k]].last_ceiling * 100.f));
    autoport_proof::publish((pre + "peak_used_nits").c_str(),
                            (uint64_t)std::lround(s_ph[pidx[k]].last_peak));
  }
  autoport_proof::publish("hdr_out_option_visible", (uint64_t)(s_visible_reported < 0 ? 2 : s_visible_reported));
  autoport_proof::publish("hdr_out_setting_loaded", (uint64_t)(s_loaded_value < 0 ? 2 : s_loaded_value));
  autoport_proof::publish("hdr_out_setting_source", (uint64_t)(s_loaded_source < 0 ? 2 : s_loaded_source));
  autoport_proof::publish("hdr_out_menu_parent", (uint64_t)(s_menu_parent < 0 ? 2 : s_menu_parent));
  autoport_proof::publish("hdr_out_persisted", (uint64_t)(s_persisted + 3));  // 0 pas lu, 1 fichier absent, 2 cle absente, 3 = #f, 4 = #t
  autoport_proof::publish("hdr_out_selftest_phase", (uint64_t)s_phase);
  autoport_proof::publish("hdr_out_scene_ready_frame", s_phase_start);
  autoport_proof::publish("hdr_out_scene_ready_probes", s_ready_probes);
  autoport_proof::publish("hdr_out_scene_ready_px", s_ready_last_px);
  autoport_proof::publish("hdr_out_scene_ready_forced", (uint64_t)s_ready_forced);
  autoport_proof::publish("hdr_out_selftest_done", s_selftest_done ? 1 : 0);
  const char* names[kPhaseCount] = {"loaded", "on", "off", "onsim"};
  for (int p = 0; p < kPhaseCount; p++) {
    std::string k = std::string("hdr_out_ph_") + names[p] + "_";
    autoport_proof::publish((k + "frames").c_str(), s_ph[p].frames);
    autoport_proof::publish((k + "active").c_str(), s_ph[p].active_frames);
    autoport_proof::publish((k + "surface_hdr").c_str(), s_ph[p].surface_hdr_frames);
    autoport_proof::publish((k + "sites_bad").c_str(), s_ph[p].sites_bad);
    autoport_proof::publish((k + "ui_bad").c_str(), s_ph[p].ui_bad);
    autoport_proof::publish((k + "present_bad").c_str(), s_ph[p].present_bad);
    autoport_proof::publish((k + "ceiling_bad").c_str(), s_ph[p].ceiling_bad);
    autoport_proof::publish((k + "red_bits").c_str(), (uint64_t)(s_ph[p].last_red_bits < 0 ? 0 : s_ph[p].last_red_bits));
    autoport_proof::publish((k + "colorspace").c_str(), (uint64_t)(s_ph[p].last_colorspace < 0 ? 0 : s_ph[p].last_colorspace));
    autoport_proof::publish((k + "mode").c_str(), (uint64_t)s_ph[p].last_mode);
  }
  // Les phases ON et OFF ne comptent leurs images bonnes qu'a partir de l'application effective
  // de la bascule : `tonemaps_applied` est le recensement de la DERNIERE image ON.
  autoport_proof::publish("hdr_out_tonemaps_applied", s_phase >= 2 && s_ph[1].frames ? (s_ph[1].sites_bad ? 0 : 1) : 0);
  // La grandeur de porte : somme de neuf verdicts, chacun publie a cote. « Pas mesurable » = 1.
  if (s_defects >= 0) {
    autoport_proof::publish("hdr_out_defect_1_caps_detected", (uint64_t)s_d[1]);
    autoport_proof::publish("hdr_out_defect_2_option_visibility", (uint64_t)s_d[2]);
    autoport_proof::publish("hdr_out_defect_3_real_switch", (uint64_t)s_d[3]);
    autoport_proof::publish("hdr_out_defect_4_on_single_compression", (uint64_t)s_d[4]);
    autoport_proof::publish("hdr_out_defect_5_off_identical", (uint64_t)s_d[5]);
    autoport_proof::publish("hdr_out_defect_6_autoconfig_persist", (uint64_t)s_d[6]);
    autoport_proof::publish("hdr_out_defect_7_menu_parent", (uint64_t)s_d[7]);
    autoport_proof::publish("hdr_out_defect_8_ui_white", (uint64_t)s_d[8]);
    autoport_proof::publish("hdr_out_defect_9_darkening", (uint64_t)s_d[9]);
    autoport_proof::publish("hdr_out_defect_10_peak_adaptive", (uint64_t)s_d[10]);
    autoport_proof::publish("hdr_out_peak_adaptive", (uint64_t)(s_d[10] ? 0 : 1));
    autoport_proof::publish("hdr_out_defects", (uint64_t)s_defects);
  } else {
    autoport_proof::publish("hdr_out_defects", 10);  // auto-test pas au bout : ROUGE, jamais muet
  }
}

void compute_verdicts() {
  std::unique_lock<std::mutex> lk(s_mu);
  const uint32_t modes = modes_locked();
  const bool sys_ok = s_sys.reported, plat_ok = s_plat.probed;
  lk.unlock();
  const int want_cs = modes == kModeScrgbLinear ? kEglColorspaceScrgbLinear : kEglColorspaceBt2020Pq;
  const int want_bits = modes == kModeScrgbLinear ? 16 : 10;
  // 1 : capacite DETECTEE et publiee, par les deux couches.
  s_d[1] = (sys_ok && plat_ok) ? 0 : 1;
  // 2 : la rangee n'apparait que si un mode est annonce — GOAL a rapporte sa decision.
  s_d[2] = (s_visible_reported >= 0 && (s_visible_reported != 0) == (modes != 0)) ? 0 : 1;
  // 3 : un VRAI interrupteur. Jamais force par la capacite ; OFF impose => surface SDR ;
  //     ON impose sur un ecran qui l'annonce => surface HDR.
  const PhaseStats& on = s_ph[1];
  const PhaseStats& off = s_ph[2];
  bool sw_ok = s_forced_on_frames == 0 && off.frames > 0 && off.active_frames == 0 &&
               off.surface_hdr_frames == 0 && off.last_red_bits == 8;
  if (modes) {
    sw_ok = sw_ok && on.frames > 0 && on.active_frames == on.frames;
  }
  s_d[3] = sw_ok ? 0 : 1;
  // 4 : ON => surface dans l'espace du mode retenu (PQ 10 bits, ou scRGB 16 bits), UI flottant,
  //     quad final qui encode, et UNE seule compression de plage par image. Sans ecran HDR, rien
  //     de ceci n'est mesurable.
  const bool on_ok = modes != 0 && on.frames > 0 && on.last_colorspace == want_cs &&
                     on.last_red_bits == want_bits && on.last_mode == modes && on.sites_bad == 0 &&
                     on.ui_bad == 0 && on.present_bad == 0 && on.ceiling_bad == 0;
  s_d[4] = on_ok ? 0 : 1;
  // 5 : OFF => identique a lighting-hdr : UI 8 bits, plafond 1,0, quad recopie, surface 8 bits
  //     lineaire.
  const bool off_ok = off.frames > 0 && off.ui_bad == 0 && off.present_bad == 0 &&
                      off.ceiling_bad == 0 && off.last_red_bits == 8 &&
                      (off.last_colorspace == kEglColorspaceLinear || off.last_colorspace == 0 ||
                       off.last_colorspace == kEglColorspaceSrgb);
  s_d[5] = off_ok ? 0 : 1;
  // 6 : le reglage vient du fichier ou de l'auto-configuration (rapporte), et le fichier relu
  //     du disque porte la valeur en memoire.
  s_persisted = read_persisted_setting();
  const int mem = s_setting.load() != 0 ? 1 : 0;
  s_d[6] = (s_loaded_value >= 0 && s_loaded_source >= 0 && s_persisted == mem) ? 0 : 1;
  // 7 : la rangee vit sous Options > Recharged > Recharged Lighting (GOAL l'a trouvee la, en
  //     scrutant ses tableaux, pas en le supposant).
  s_d[7] = (s_menu_parent == 1) ? 0 : 1;
  // 8 : le blanc du jeu sort AU blanc SDR du systeme, jamais en dessous. Mesure : un blanc
  //     (1,1,1) rejoue par le vrai quad final ; PQ : decode en nits contre sdr_white_nits x la
  //     valeur SDR lineaire du meme blanc ; scRGB : valeur lineaire contre cette meme reference
  //     (1,0 = blanc SDR par contrat). Tolerance 1 %.
  const ProbeStats& pr = s_pr[1];
  const ProbeStats& ps = s_pr[3];
  bool white_ok = false;
  // Le blanc SDR de la phase 1 (pic REEL) : celui que sdr_white_nits() rend hors simulation.
  const float real_sdr_white = (on.last_mode == kModeHdr10Pq) ? (s_white_override > 0.f ? s_white_override : announced_peak_nits()) : 0.f;
  if (pr.ui_samples > 0) {
    const double ui_mean = pr.ui_white_sum / (double)pr.ui_samples;
    const double ref = pr.ui_ref_sum / (double)pr.ui_samples;  // lineaire, 1,0 = blanc SDR
    if (on.last_mode == kModeHdr10Pq) {
      const double expect = ref * (double)real_sdr_white;
      white_ok = expect > 0.0 && ui_mean >= 0.99 * expect && pr.ui_white_min >= 0.98 * expect;
    } else if (on.last_mode == kModeScrgbLinear) {
      white_ok = ref > 0.0 && ui_mean >= 0.99 * ref && pr.ui_white_min >= 0.98 * ref;
    }
  }
  s_d[8] = white_ok ? 0 : 1;
  // 9 : les tons moyens de la scene ne baissent pas par rapport a la sortie SDR (<= 5 %), sur
  //     la MEME image tone-mappee deux fois par le vrai programme.
  bool dark_ok = false;
  if (pr.tm_px > 0 && pr.tm_sum_off > 0.0) {
    const double dark = 100.0 * (1.0 - pr.tm_sum_on / pr.tm_sum_off);
    dark_ok = dark <= 5.0;
  }
  s_d[9] = dark_ok ? 0 : 1;
  // 10 : la courbe s'adapte au pic ANNONCE. Phase 3 = ON avec un pic simule (1000 nits, ou le
  //      double si l'ecran annonce deja >= 900), memes mesures que la phase 1 :
  //      * scRGB : blanc SDR ANCRE (le blanc UI ne bouge pas, +-1 %), plafond plus haut, et les
  //        hautes lumieres ecrites par le tone map montent plus haut ;
  //      * PQ (API < 34, PQ recompose en SDR a l'echelle du pic) : le blanc de reference SUIT le
  //        pic dans la meme proportion (+-3 %) et le plafond reste 1,0 — c'est la seule
  //        adaptation qui existe sur ces ecrans, les hautes lumieres ne peuvent pas s'etendre.
  const PhaseStats& onsim = s_ph[3];
  bool peak_ok = false;
  if (pr.ui_samples > 0 && ps.ui_samples > 0 && onsim.frames > 0 && onsim.active_frames == onsim.frames &&
      onsim.last_peak > 0.f && on.last_peak > 0.f && onsim.last_peak != on.last_peak) {
    const double w_real = pr.ui_white_sum / (double)pr.ui_samples;
    const double w_sim = ps.ui_white_sum / (double)ps.ui_samples;
    if (on.last_mode == kModeScrgbLinear && onsim.last_mode == kModeScrgbLinear) {
      const bool anchored = w_real > 0.0 && std::fabs(w_sim / w_real - 1.0) <= 0.01;
      const bool higher = onsim.last_ceiling > on.last_ceiling + 1e-3f && ps.hl_max > pr.hl_max * 1.01;
      peak_ok = anchored && higher;
    } else if (on.last_mode == kModeHdr10Pq && onsim.last_mode == kModeHdr10Pq) {
      const double want = (double)onsim.last_peak / (double)on.last_peak;
      const bool follows = w_real > 0.0 && std::fabs((w_sim / w_real) / want - 1.0) <= 0.03;
      peak_ok = follows && std::fabs(on.last_ceiling - 1.f) < 1e-3f && std::fabs(onsim.last_ceiling - 1.f) < 1e-3f;
    }
  }
  s_d[10] = peak_ok ? 0 : 1;
  s_defects = 0;
  for (int i = 1; i <= 10; i++) {
    s_defects += s_d[i];
  }
  lg::info(
      "[hdr-display-output] auto-test termine : defauts={} ({},{},{},{},{},{},{},{},{},{}) persisted={} "
      "mem={} ui_samples={}/{} tm_px={}/{} hl_max={:.3f}/{:.3f} ceiling={:.3f}/{:.3f}",
      s_defects, s_d[1], s_d[2], s_d[3], s_d[4], s_d[5], s_d[6], s_d[7], s_d[8], s_d[9], s_d[10],
      s_persisted, mem, pr.ui_samples, ps.ui_samples, pr.tm_px, ps.tm_px, pr.hl_max, ps.hl_max,
      on.last_ceiling, onsim.last_ceiling);
}

bool scene_ready() {
  if (s_ready_hits >= kReadyHits) {
    return true;
  }
  const double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - s_clock0).count();
  if (el >= kReadyCapSeconds) {
    s_ready_forced = 1;
    return true;
  }
  return false;
}

void selftest_step() {
  // Le sequenceur, une fois par image, AVANT le comptage de l'image courante.
  if (s_selftest_done) {
    return;
  }
  if (!s_clock_started) {
    s_clock_started = true;
    s_clock0 = std::chrono::steady_clock::now();
  }
  if (s_phase == 0) {
    if (s_frames >= kPhaseFrames && scene_ready()) {
      s_phase = 1;
      s_phase_start = s_frames;
      s_skip_frames = 1;
      s_test_force.store(1);
      lg::info("[hdr-display-output] auto-test : phase ON imposee a l'image {} (scene {} : {} sondes, {} tons moyens)",
               s_frames, s_ready_forced ? "FORCEE par le plafond de temps" : "prete", s_ready_probes,
               s_ready_last_px);
    }
    return;
  }
  if (s_frames == s_phase_start + kPhaseFrames) {
    s_phase = 2;
    s_skip_frames = 1;
    s_test_force.store(0);
    lg::info("[hdr-display-output] auto-test : phase OFF imposee");
  } else if (s_frames == s_phase_start + 2 * kPhaseFrames) {
    s_phase = 3;
    s_skip_frames = 1;
    s_test_force.store(1);
    const float ann = announced_peak_nits();
    s_test_peak = (ann >= 0.9f * kSimPeakNits) ? 2.f * ann : kSimPeakNits;
    lg::info("[hdr-display-output] auto-test : phase ON imposee avec pic SIMULE {} nits (annonce {})",
             s_test_peak, ann);
  } else if (s_frames == s_phase_start + 3 * kPhaseFrames) {
    s_phase = 4;
    s_test_force.store(-1);  // le reglage du joueur reprend
    s_test_peak = 0.f;
    s_selftest_done = true;
    compute_verdicts();
    publish_all();
    autoport_proof::flush();
  }
}

}  // namespace

// ------------------------------------------------------------------------------ capacites --

void set_system_caps(uint32_t sys_types_mask,
                     int max_lum_nits,
                     int max_avg_lum_nits,
                     int min_lum_x10000,
                     bool wide_gamut) {
  std::lock_guard<std::mutex> lk(s_mu);
  s_sys.reported = true;
  s_sys.types = sys_types_mask;
  s_sys.max_lum = max_lum_nits;
  s_sys.max_avg = max_avg_lum_nits;
  s_sys.min_lum_x10000 = min_lum_x10000;
  s_sys.wide_gamut = wide_gamut;
  rebuild_caps_text_locked();
  lg::info("[hdr-display-output] capacites systeme : {}", s_caps_text);
}

void set_platform_info(int sdk_int, bool hdr_sdr_ratio_available) {
  std::lock_guard<std::mutex> lk(s_mu);
  s_sys.sdk_int = sdk_int;
  s_sys.ratio_available = hdr_sdr_ratio_available;
  rebuild_caps_text_locked();
  lg::info("[hdr-display-output] plateforme : sdk={} ratio_api={} -> modes={}", sdk_int,
           hdr_sdr_ratio_available ? 1 : 0, modes_locked());
}

void set_hdr_sdr_ratio(float ratio) {
  const int v = (ratio >= 1.f && ratio == ratio) ? (int)std::lround(ratio * 1000.f) : 1000;
  const int before = s_ratio_x1000.exchange(v);
  if (before != v) {
    lg::info("[hdr-display-output] ratio HDR/SDR du systeme : {:.3f}", v / 1000.f);
  }
}

void set_platform_caps(const PlatformCaps& caps) {
  std::lock_guard<std::mutex> lk(s_mu);
  s_plat = caps;
  s_plat.probed = true;
  rebuild_caps_text_locked();
  lg::info("[hdr-display-output] capacites de presentation : {} -> modes={}", s_caps_text,
           modes_locked());
}

uint32_t modes_available() {
  std::lock_guard<std::mutex> lk(s_mu);
  return modes_locked();
}

const char* mode_name(uint32_t mode) {
  if (mode & kModeScrgbLinear) {
    return "scrgb_linear";
  }
  return (mode & kModeHdr10Pq) ? "hdr10_pq" : "none";
}

const char* caps_string() {
  // Le texte n'est reconstruit que sous verrou et ne retrecit jamais : le pointeur rendu reste
  // lisible le temps d'un `publish_text`.
  return s_caps_text.c_str();
}

// ---------------------------------------------------------------------------- interrupteur --

void set_enabled(bool on) {
  const int before = s_setting.exchange(on ? 1 : 0);
  if (before != (on ? 1 : 0)) {
    lg::info("[hdr-display-output] reglage du joueur : {} (modes={})", on ? "ON" : "OFF",
             modes_available());
  }
}

bool enabled() {
  return s_setting.load() != 0;
}

bool active() {
  return s_active.load();
}

void install_switcher(Switcher fn) {
  s_switcher = std::move(fn);
}

void note_surface_state(const SurfaceState& st) {
  s_surface = st;
  s_active.store(st.hdr);
}

void apply_pending_on_gl_thread() {
  s_frame_ratio_x1000 = s_ratio_x1000.load();  // une seule lecture du ratio par image
  // scRGB actif : le ratio LU a change (listener Java) -> le tampon de cette image sera encode
  // a ce ratio, on le declare au compositeur (current = ratio rendu, desired inchange).
  if (s_active.load() && s_surface.mode == kModeScrgbLinear && !s_headroom_pending) {
    const float cur = headroom_linear();
    if (s_headroom_sent_current >= 0.f && std::fabs(cur - s_headroom_sent_current) > 0.005f) {
      s_headroom_request_current = cur;
      s_headroom_request_desired = desired_headroom();
      s_headroom_pending = true;
      lg::info("[hdr-display-output] marge : ratio rendu {:.3f} -> re-declaration au compositeur (souhait {:.2f})",
               cur, s_headroom_request_desired);
    }
  }
  const uint32_t modes = modes_available();
  const bool gate = effective_setting() && modes != 0 && autoport_proof::armed_for(kItemId) &&
                    lighting_gate();
  const uint32_t want = gate ? modes : kModeNone;
  if ((int)want == s_last_want) {
    return;  // rien de nouveau : on ne re-tente pas une bascule refusee a chaque image
  }
  s_last_want = (int)want;
  if (want == s_surface.mode && (want != kModeNone) == s_active.load()) {
    return;
  }
  if (!s_switcher) {
    if (want) {
      lg::warn("[hdr-display-output] aucun basculeur de surface sur cette plateforme : ON ignore");
    }
    return;
  }
  SurfaceState st;
  const bool ok = s_switcher(want, &st);
  s_surface = st;
  s_active.store(st.hdr);
  if (ok && st.mode == want) {
    s_switch_ok++;
    // scRGB : demander la marge au systeme ; retour SDR : la rendre (le SurfaceControl survit a
    // la recreation de la surface EGL, donc l'accord aussi).
    // Premiere declaration : le tampon est encode au ratio LU (1,0 tant que le systeme n'a
    // rien accorde), le souhait promeut la couche ; retour SDR : (1,0 ; 1,0).
    s_headroom_request_current = (want == kModeScrgbLinear) ? headroom_linear() : 1.f;
    s_headroom_request_desired = (want == kModeScrgbLinear) ? desired_headroom() : 1.f;
    s_headroom_pending = true;
    lg::info("[hdr-display-output] surface {} : red_bits={} colorspace=0x{:x} mode={}",
             want == kModeScrgbLinear ? "scRGB/16F" : want == kModeHdr10Pq ? "HDR10/PQ" : "SDR",
             st.red_bits, (unsigned)st.colorspace, st.mode);
  } else {
    s_switch_fail++;
    lg::error("[hdr-display-output] bascule vers mode {} REFUSEE : red_bits={} colorspace=0x{:x} mode={}",
              want, st.red_bits, (unsigned)st.colorspace, st.mode);
  }
}

bool take_headroom_request(float* current, float* desired) {
  if (!s_headroom_pending) {
    return false;
  }
  s_headroom_pending = false;
  s_headroom_sent_current = s_headroom_request_current;
  s_headroom_requests++;
  if (current) {
    *current = s_headroom_request_current;
  }
  if (desired) {
    *desired = s_headroom_request_desired;
  }
  return true;
}

// ------------------------------------------------------------------------ ce que le rendu lit --

GLenum ui_buffer_format() {
  return s_active.load() ? GL_RGBA16F : GL_RGBA8;
}

GLenum window_target_format() {
  if (!s_active.load()) {
    return GL_RGBA8;
  }
  return s_surface.mode == kModeScrgbLinear ? GL_RGBA16F : GL_RGB10_A2;
}

float sdr_white_nits() {
  if (s_surface.mode == kModeScrgbLinear) {
    return 0.f;  // contrat relatif : 1,0 = blanc SDR, pas un nits
  }
  if (s_white_override < 0.f) {
    const int v = read_int_knob("debug.opengoal.hdr.out.white", "OG_HDR_OUT_WHITE", 0);
    s_white_override = (v >= 80 && v <= 10000) ? (float)v : 0.f;
    if (s_white_override > 0.f) {
      lg::warn("[hdr-display-output] blanc SDR PQ force par le harnais : {} nits", s_white_override);
    }
  }
  if (s_white_override > 0.f) {
    return s_white_override;
  }
  return peak_nits();
}

const char* sdr_white_source() {
  if (s_surface.mode == kModeScrgbLinear) {
    return "scrgb:1.0=sdr_white(contract)";
  }
  if (s_white_override > 0.f) {
    return "pq:override_knob";
  }
  if (s_test_peak > 0.f) {
    return "pq:selftest_simulated_peak";
  }
  if (s_peak_knob > 0.f) {
    return "pq:debug_simulated_peak";
  }
  int max_lum = 0;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    max_lum = s_sys.max_lum;
  }
  return max_lum > 0 ? "pq:HdrCapabilities.maxLuminance" : "pq:compositor_default_500";
}

float paper_white() {
  if (s_surface.mode == kModeHdr10Pq && s_active.load()) {
    return sdr_white_nits();
  }
  return 1.f;
}

float headroom_linear() {
  if (!s_active.load()) {
    return 1.f;
  }
  if (s_surface.mode == kModeScrgbLinear) {
    return ratio_linear();
  }
  // PQ (API < 34) : le compositeur recompose en SDR a l'echelle de maxLuminance ; le blanc SDR
  // EST ce maximum, il n'y a aucune marge au-dessus (mesure Redmi du 09/09, voir l'en-tete).
  return 1.f;
}

float tonemap_ceiling() {
  float c = 1.f;
  const float h = headroom_linear();
  if (h > 1.f) {
    c = std::pow(h, 1.f / 2.2f);  // marge lineaire -> espace d'affichage du tampon
  }
  s_last_ceiling = c;
  return c;
}

void push_present_uniforms(Shader& shader) {
  const bool on = s_active.load();
  s_last_present_mode = on ? (s_surface.mode == kModeScrgbLinear ? 2 : 1) : 0;
  glUniform1i(glGetUniformLocation(shader.id(), "u_out_mode"), s_last_present_mode);
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_paper_white"), paper_white());
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_max_nits"), peak_nits());
}

// ------------------------------------------------------------------------------- sondes --

void probe_present(Shader& shader) {
  if (!probe_window_open() || s_pp_state < 0) {
    return;
  }
  if (s_pp_state == 0) {
    const float white[4] = {1.f, 1.f, 1.f, 1.f};
    GLuint wfbo = 0;
    const bool a = make_float_fbo(&wfbo, &s_pp_white, 1, 1, white);
    glDeleteFramebuffers(1, &wfbo);  // le texel blanc ne sert que de SOURCE
    const bool b = a && make_float_fbo(&s_pp_fbo, &s_pp_tex, 4, 4, nullptr);
    s_pp_state = (a && b) ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (s_pp_state < 0) {
      return;
    }
  }
  GLint vp[4] = {0, 0, 0, 0};
  GLint saved_tex = 0;
  glGetIntegerv(GL_VIEWPORT, vp);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  const GLint loc_mode = glGetUniformLocation(shader.id(), "u_out_mode");
  glBindFramebuffer(GL_FRAMEBUFFER, s_pp_fbo);
  glViewport(0, 0, 4, 4);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, s_pp_white);
  std::vector<float> px;
  // 1 : le mode courant (PQ ou scRGB), tel que pousse pour cette image.
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  const bool ok1 = read_float_fbo(4, 4, px);
  const float r1 = px.size() >= 3 ? px[0] : 0.f, g1 = px.size() >= 3 ? px[1] : 0.f,
              b1 = px.size() >= 3 ? px[2] : 0.f;
  // 2 : la recopie SDR (u_out_mode = 0) du MEME blanc : la reference « ce que le SDR montre »,
  //     luminosite du joueur comprise.
  glUniform1i(loc_mode, 0);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  const bool ok2 = read_float_fbo(4, 4, px);
  const float rr = px.size() >= 3 ? px[0] : 0.f, rg = px.size() >= 3 ? px[1] : 0.f,
              rb = px.size() >= 3 ? px[2] : 0.f;
  glUniform1i(loc_mode, s_last_present_mode);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(vp[0], vp[1], vp[2], vp[3]);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (!ok1 || !ok2) {
    lg::error("[hdr-display-output] sonde de blanc UI : relecture refusee");
    s_pp_state = -1;
    return;
  }
  double measured = 0.0;
  if (s_surface.mode == kModeHdr10Pq) {
    // Blanc D65 : les trois canaux PQ sont egaux (la matrice 709->2020 conserve le blanc) ; on
    // prend le plus faible pour ne jamais flatter la mesure.
    const float m = std::fmin(r1, std::fmin(g1, b1));
    measured = pq_eotf_nits(m);
  } else {
    measured = std::fmin(r1, std::fmin(g1, b1));
  }
  const double ref_lin = std::pow((double)std::fmax(0.f, std::fmin(rr, std::fmin(rg, rb))), 2.2);
  ProbeStats& pr = s_pr[s_phase];
  pr.ui_samples++;
  pr.ui_white_sum += measured;
  pr.ui_ref_sum += ref_lin;
  if (measured < pr.ui_white_min) {
    pr.ui_white_min = measured;
  }
  if (pr.ui_samples == 1 || (pr.ui_samples % 10) == 0) {
    lg::info("[hdr-display-output] sonde blanc UI phase {} #{} : mode={} mesure={:.3f} ref_sdr_lin={:.3f} sdr_white={:.0f} pic={:.0f}",
             s_phase, pr.ui_samples, s_surface.mode, measured, ref_lin, sdr_white_nits(), peak_nits());
  }
}

static bool ready_window_open() {
  return measuring() && !s_selftest_done && s_phase == 0 && s_frames >= kPhaseFrames / 2 &&
         (s_frames % kProbeEvery) == 0;
}

void probe_tonemap(Shader& shader, GLuint dst_fbo, int dst_w, int dst_h) {
  const bool ready_probe = ready_window_open();
  if ((!probe_window_open() && !ready_probe) || s_tm_state < 0) {
    return;
  }
  if (s_tm_state == 0) {
    const bool a = make_float_fbo(&s_tm_fbo[0], &s_tm_tex[0], kTmW, kTmH, nullptr);
    const bool b = a && make_float_fbo(&s_tm_fbo[1], &s_tm_tex[1], kTmW, kTmH, nullptr);
    s_tm_state = (a && b) ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    if (s_tm_state < 0) {
      return;
    }
  }
  const GLint loc = glGetUniformLocation(shader.id(), "u_hdr_ceiling");
  std::vector<float> off, on;
  bool ok = true;
  if (ready_probe) {
    // Sonde de CONTENU (phase 0) : un seul dessin au plafond 1,0, on compte les tons moyens.
    glUniform1f(loc, 1.f);
    glBindFramebuffer(GL_FRAMEBUFFER, s_tm_fbo[0]);
    glViewport(0, 0, kTmW, kTmH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kTmW, kTmH, off);
    glUniform1f(loc, s_last_ceiling);
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    if (!ok) {
      lg::error("[hdr-display-output] sonde de contenu : relecture refusee");
      s_tm_state = -1;
      return;
    }
    uint64_t px = 0;
    for (size_t i = 0; i + 3 < off.size(); i += 4) {
      const float mx = std::fmax(off[i], std::fmax(off[i + 1], off[i + 2]));
      if (mx == mx && mx >= 0.05f && mx <= 0.85f) {
        px++;
      }
    }
    s_ready_probes++;
    s_ready_last_px = px;
    s_ready_hits = (px >= kReadyPx) ? s_ready_hits + 1 : 0;
    if (s_ready_probes == 1 || (s_ready_probes % 20) == 0 || s_ready_hits == kReadyHits) {
      lg::info("[hdr-display-output] sonde de contenu #{} image {} : tons moyens={}/{} hits={}",
               s_ready_probes, s_frames, px, (uint64_t)kTmW * kTmH, s_ready_hits);
    }
    return;
  }
  for (int i = 0; i < 2 && ok; i++) {
    glUniform1f(loc, i == 0 ? 1.f : s_last_ceiling);
    glBindFramebuffer(GL_FRAMEBUFFER, s_tm_fbo[i]);
    glViewport(0, 0, kTmW, kTmH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kTmW, kTmH, i == 0 ? off : on);
  }
  glUniform1f(loc, s_last_ceiling);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  if (!ok) {
    lg::error("[hdr-display-output] sonde d'assombrissement : relecture refusee");
    s_tm_state = -1;
    return;
  }
  uint64_t px = 0;
  double sum_off = 0.0, sum_on = 0.0, hl = 0.0;
  for (size_t i = 0; i + 3 < off.size() && i + 3 < on.size(); i += 4) {
    if (!std::isfinite(on[i]) || !std::isfinite(on[i + 1]) || !std::isfinite(on[i + 2])) {
      continue;
    }
    const float mon = std::fmax(on[i], std::fmax(on[i + 1], on[i + 2]));
    if (mon > hl) {
      hl = mon;  // jusqu'ou le tone map ON laisse monter les hautes lumieres
    }
    const float mx = std::fmax(off[i], std::fmax(off[i + 1], off[i + 2]));
    if (!(mx == mx) || mx < 0.05f || mx > 0.85f) {
      continue;  // tons moyens seulement : ni le noir ni l'epaule
    }
    px++;
    sum_off += lum_linear(off[i], off[i + 1], off[i + 2]);
    sum_on += lum_linear(on[i], on[i + 1], on[i + 2]);
  }
  ProbeStats& pr = s_pr[s_phase];
  pr.tm_samples++;
  pr.tm_px += px;
  pr.tm_sum_off += sum_off;
  pr.tm_sum_on += sum_on;
  if (hl > pr.hl_max) {
    pr.hl_max = hl;
  }
  if (pr.tm_samples == 1 || (pr.tm_samples % 10) == 0) {
    lg::info("[hdr-display-output] sonde tons moyens phase {} #{} : px={} off={:.4f} on={:.4f} hl={:.3f} plafond={:.3f}",
             s_phase, pr.tm_samples, px, sum_off, sum_on, hl, s_last_ceiling);
  }
}

// ------------------------------------------------------------------------------ fin d'image --

void frame_end(uint64_t sites, GLenum ui_fmt) {
  const bool on = s_active.load();
  if (on) {
    s_hits++;
    autoport_proof::note_hit();  // AU SITE DU GESTE : une image presentee en HDR
  }
  if (on && !effective_setting()) {
    s_forced_on_frames++;  // la capacite a force ce que le reglage n'a pas demande
  }
  if (!autoport_proof::armed_for(kItemId)) {
    s_frames++;
    return;  // bras desarme : aucune cle `hdr_out_*`
  }
  if (measuring()) {
    selftest_step();
  }
  // Comptage de l'image courante dans sa phase (sauf l'image de transition, voir s_skip_frames).
  if (s_skip_frames > 0) {
    s_skip_frames--;
  } else if (s_phase < kPhaseCount) {
    PhaseStats& ph = s_ph[s_phase];
    ph.frames++;
    ph.active_frames += on ? 1 : 0;
    ph.surface_hdr_frames += s_surface.hdr ? 1 : 0;
    ph.last_red_bits = s_surface.red_bits;
    ph.last_colorspace = s_surface.colorspace;
    ph.last_mode = s_surface.mode;
    ph.last_ceiling = s_last_ceiling;
    ph.last_peak = peak_nits();
    const bool expect_on = (s_phase == 1 || s_phase == 3);
    const bool expect_off = (s_phase == 2);
    if (expect_on) {
      ph.sites_bad += (sites == 1) ? 0 : 1;
      ph.ui_bad += (ui_fmt == GL_RGBA16F) ? 0 : 1;
      ph.present_bad += (s_last_present_mode != 0) ? 0 : 1;
      // Le plafond : > 1,0 quand une marge existe, exactement 1,0 sinon (PQ sans marge).
      const float want_ceiling = headroom_linear() > 1.f ? std::pow(headroom_linear(), 1.f / 2.2f) : 1.f;
      ph.ceiling_bad += (std::fabs(s_last_ceiling - want_ceiling) < 1e-3f) ? 0 : 1;
    } else if (expect_off) {
      ph.ui_bad += (ui_fmt == GL_RGBA8) ? 0 : 1;
      ph.present_bad += (s_last_present_mode == 0) ? 0 : 1;
      ph.ceiling_bad += (s_last_ceiling == 1.f) ? 0 : 1;
    }
  }
  s_frames++;
  if ((s_frames % 30) == 0) {
    publish_all();
  }
}

// --------------------------------------------------------------------- rapports de GOAL --

void note_option_visible(int visible) {
  s_visible_reported = visible ? 1 : 0;
  lg::info("[hdr-display-output] GOAL : rangee HDR Output {} (modes={})",
           visible ? "VISIBLE" : "cachee", modes_available());
}

void note_setting_loaded(int value, int source) {
  s_loaded_value = value ? 1 : 0;
  s_loaded_source = source ? 1 : 0;
  lg::info("[hdr-display-output] GOAL : reglage {} ({})", value ? "ON" : "OFF",
           source ? "auto-configuration" : "settings.ini");
}

void note_menu_parent(int parent) {
  s_menu_parent = parent ? 1 : 0;
  lg::info("[hdr-display-output] GOAL : rangee HDR Output {}",
           parent ? "sous RECHARGED > RECHARGED LIGHTING" : "HORS du bloc RECHARGED LIGHTING");
}

int read_persisted_setting() {
  std::string txt;
  try {
    const auto p = file_util::get_user_settings_dir(GameVersion::Jak1) / "settings.ini";
    if (!fs::exists(p)) {
      return -2;
    }
    txt = file_util::read_text_file(p);
  } catch (...) {
    return -2;
  }
  const char* key = "hdr-output? = ";
  const auto pos = txt.find(key);
  if (pos == std::string::npos) {
    return -1;
  }
  const char* v = txt.c_str() + pos + std::strlen(key);
  if (v[0] == '#' && v[1] == 't') {
    return 1;
  }
  if (v[0] == '#' && v[1] == 'f') {
    return 0;
  }
  return -1;
}

}  // namespace hdr_output
