#include "game/graphics/opengl_renderer/hdr_output.h"

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/graphics/opengl_renderer/Shader.h"
#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace hdr_output {
namespace {

// Valeurs EGL brutes (EGL_KHR_gl_colorspace / EGL_EXT_gl_colorspace_bt2020_pq), reprises ici
// pour que la publication ne depende pas des en-tetes EGL sur le bureau.
constexpr int kEglColorspaceSrgb = 0x3089;
constexpr int kEglColorspaceLinear = 0x308A;
constexpr int kEglColorspaceBt2020Pq = 0x3340;

// ITU-R BT.2408 : blanc de reference des graphismes SDR dans un signal HDR = 203 cd/m2.
constexpr float kDefaultPaperWhiteNits = 203.f;
// Quand l'ecran n'annonce pas sa luminance maximale : le plafond HDR10 courant.
constexpr float kDefaultMaxNits = 1000.f;

// ------------------------------------------------------------------------------ capacites --
struct SysCaps {
  bool reported = false;
  uint32_t types = 0;
  int max_lum = 0;
  int max_avg = 0;
  int min_lum_x10000 = 0;
  bool wide_gamut = false;
};
std::mutex s_mu;  // garde s_sys, s_plat, s_caps_text (ecrits depuis Java/EE, lus sur GL)
SysCaps s_sys;
PlatformCaps s_plat;
std::string s_caps_text = "sys:unreported;platform:unprobed";

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
  if (!s_sys.reported || !s_plat.probed) {
    return kModeNone;
  }
  const bool sys_hdr = (s_sys.types & (kSysHdr10 | kSysHlg | kSysHdr10Plus | kSysDolbyVision)) != 0;
  if (sys_hdr && s_plat.egl_bt2020_pq && s_plat.config_10bit) {
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
int s_last_want = -1;                 // fil GL : derniere demande tentee
uint64_t s_switch_ok = 0, s_switch_fail = 0;
float s_paper_white = 0.f;            // 0 = pas encore lu

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

// ------------------------------------------------------------------------------- la preuve --
// Trois phases, par image : 0 = etat charge, 1 = ON impose, 2 = OFF impose, 3 = termine.
constexpr uint64_t kPhaseFrames = 150;
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
PhaseStats s_ph[3];
int s_last_present_mode = 0;   // ce que push_present_uniforms a pousse pour cette image
float s_last_ceiling = 1.f;    // ce que tonemap_ceiling() a rendu pour cette image
int s_visible_reported = -1;   // GOAL : -1 jamais, 0/1
int s_loaded_value = -1;       // GOAL : -1 jamais, 0/1
int s_loaded_source = -1;      // GOAL : 0 fichier, 1 auto-configuration
int s_persisted = -3;          // relecture disque : -3 pas encore lue
int s_defects = -1;
int s_d[7] = {0, 0, 0, 0, 0, 0, 0};

bool measuring() {
  return autoport_proof::feature_is(kItemId) && autoport_proof::armed_for(kItemId);
}

void publish_all() {
  std::lock_guard<std::mutex> lk(s_mu);
  autoport_proof::publish_text("hdr_out_display_caps", s_caps_text.c_str());
  autoport_proof::publish("hdr_out_sys_reported", s_sys.reported ? 1 : 0);
  autoport_proof::publish("hdr_out_sys_types_mask", s_sys.types);
  autoport_proof::publish("hdr_out_platform_probed", s_plat.probed ? 1 : 0);
  const uint32_t modes = modes_locked();
  autoport_proof::publish("hdr_out_modes_available", modes);
  autoport_proof::publish_text("hdr_out_mode_retained", mode_name(modes));
  autoport_proof::publish("hdr_out_autoconfig_mode", modes ? 1 : 0);
  autoport_proof::publish("hdr_out_setting", s_setting.load() != 0 ? 1 : 0);
  autoport_proof::publish("hdr_out_effective", effective_setting() ? 1 : 0);
  autoport_proof::publish("hdr_out_active", s_active.load() ? 1 : 0);
  autoport_proof::publish("hdr_out_surface_red_bits", (uint64_t)(s_surface.red_bits < 0 ? 0 : s_surface.red_bits));
  autoport_proof::publish("hdr_out_surface_colorspace", (uint64_t)(s_surface.colorspace < 0 ? 0 : s_surface.colorspace));
  autoport_proof::publish("hdr_out_switch_ok", s_switch_ok);
  autoport_proof::publish("hdr_out_switch_fail", s_switch_fail);
  autoport_proof::publish("hdr_out_forced_on", s_forced_on_frames);
  autoport_proof::publish("hdr_out_frames", s_frames);
  autoport_proof::publish("hdr_out_hdr_frames", s_hits);
  autoport_proof::publish("hdr_out_paper_white_nits", (uint64_t)std::lround(paper_white_nits()));
  autoport_proof::publish("hdr_out_ceiling_x100", (uint64_t)std::lround(s_last_ceiling * 100.f));
  autoport_proof::publish("hdr_out_present_mode", (uint64_t)s_last_present_mode);
  autoport_proof::publish("hdr_out_option_visible", (uint64_t)(s_visible_reported < 0 ? 2 : s_visible_reported));
  autoport_proof::publish("hdr_out_setting_loaded", (uint64_t)(s_loaded_value < 0 ? 2 : s_loaded_value));
  autoport_proof::publish("hdr_out_setting_source", (uint64_t)(s_loaded_source < 0 ? 2 : s_loaded_source));
  autoport_proof::publish("hdr_out_persisted", (uint64_t)(s_persisted + 3));  // 0 pas lu, 1 fichier absent, 2 cle absente, 3 = #f, 4 = #t
  autoport_proof::publish("hdr_out_selftest_phase", (uint64_t)s_phase);
  autoport_proof::publish("hdr_out_selftest_done", s_selftest_done ? 1 : 0);
  const char* names[3] = {"loaded", "on", "off"};
  for (int p = 0; p < 3; p++) {
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
  }
  // Les phases ON et OFF ne comptent leurs images bonnes qu'a partir de l'application effective
  // de la bascule : `tonemaps_applied` est le recensement de la DERNIERE image ON.
  autoport_proof::publish("hdr_out_tonemaps_applied", s_phase >= 2 && s_ph[1].frames ? (s_ph[1].sites_bad ? 0 : 1) : 0);
  // La grandeur de porte : somme de six verdicts, chacun publie a cote. « Pas mesurable » = 1.
  if (s_defects >= 0) {
    autoport_proof::publish("hdr_out_defect_1_caps_detected", (uint64_t)s_d[1]);
    autoport_proof::publish("hdr_out_defect_2_option_visibility", (uint64_t)s_d[2]);
    autoport_proof::publish("hdr_out_defect_3_real_switch", (uint64_t)s_d[3]);
    autoport_proof::publish("hdr_out_defect_4_on_single_compression", (uint64_t)s_d[4]);
    autoport_proof::publish("hdr_out_defect_5_off_identical", (uint64_t)s_d[5]);
    autoport_proof::publish("hdr_out_defect_6_autoconfig_persist", (uint64_t)s_d[6]);
    autoport_proof::publish("hdr_out_defects", (uint64_t)s_defects);
  } else {
    autoport_proof::publish("hdr_out_defects", 6);  // auto-test pas au bout : ROUGE, jamais muet
  }
}

void compute_verdicts() {
  std::unique_lock<std::mutex> lk(s_mu);
  const uint32_t modes = modes_locked();
  const bool sys_ok = s_sys.reported, plat_ok = s_plat.probed;
  lk.unlock();
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
  // 4 : ON => surface dans l'espace annonce (PQ, 10 bits), UI flottant, quad final en PQ, et
  //     UNE seule compression de plage par image. Sans ecran HDR, rien de ceci n'est mesurable.
  const bool on_ok = modes != 0 && on.frames > 0 && on.last_colorspace == kEglColorspaceBt2020Pq &&
                     on.last_red_bits == 10 && on.sites_bad == 0 && on.ui_bad == 0 &&
                     on.present_bad == 0 && on.ceiling_bad == 0;
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
  s_defects = s_d[1] + s_d[2] + s_d[3] + s_d[4] + s_d[5] + s_d[6];
  lg::info("[hdr-display-output] auto-test termine : defauts={} ({},{},{},{},{},{}) persisted={} mem={}",
           s_defects, s_d[1], s_d[2], s_d[3], s_d[4], s_d[5], s_d[6], s_persisted, mem);
}

void selftest_step() {
  // Le sequenceur, une fois par image, AVANT le comptage de l'image courante.
  if (s_selftest_done) {
    return;
  }
  if (s_frames == kPhaseFrames) {
    s_phase = 1;
    s_skip_frames = 1;
    s_test_force.store(1);
    lg::info("[hdr-display-output] auto-test : phase ON imposee");
  } else if (s_frames == 2 * kPhaseFrames) {
    s_phase = 2;
    s_skip_frames = 1;
    s_test_force.store(0);
    lg::info("[hdr-display-output] auto-test : phase OFF imposee");
  } else if (s_frames == 3 * kPhaseFrames) {
    s_phase = 3;
    s_test_force.store(-1);  // le reglage du joueur reprend
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
  const uint32_t modes = modes_available();
  const bool want = effective_setting() && modes != 0 && autoport_proof::armed_for(kItemId);
  const int want_i = want ? 1 : 0;
  if (want_i == s_last_want) {
    return;  // rien de nouveau : on ne re-tente pas une bascule refusee a chaque image
  }
  s_last_want = want_i;
  if (want == s_active.load()) {
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
  if (ok && st.hdr == want) {
    s_switch_ok++;
    lg::info("[hdr-display-output] surface {} : red_bits={} colorspace=0x{:x}",
             want ? "HDR10/PQ" : "SDR", st.red_bits, (unsigned)st.colorspace);
  } else {
    s_switch_fail++;
    lg::error("[hdr-display-output] bascule vers {} REFUSEE : red_bits={} colorspace=0x{:x}",
              want ? "HDR" : "SDR", st.red_bits, (unsigned)st.colorspace);
  }
}

// ------------------------------------------------------------------------ ce que le rendu lit --

GLenum ui_buffer_format() {
  return s_active.load() ? GL_RGBA16F : GL_RGBA8;
}

GLenum window_target_format() {
  return s_active.load() ? GL_RGB10_A2 : GL_RGBA8;
}

float paper_white_nits() {
  if (s_paper_white <= 0.f) {
    const int v = read_int_knob("debug.opengoal.hdr.out.white", "OG_HDR_OUT_WHITE", 0);
    s_paper_white = (v >= 80 && v <= 1000) ? (float)v : kDefaultPaperWhiteNits;
  }
  return s_paper_white;
}

float tonemap_ceiling() {
  float c = 1.f;
  if (s_active.load()) {
    int max_lum = 0;
    {
      std::lock_guard<std::mutex> lk(s_mu);
      max_lum = s_sys.max_lum;
    }
    const float nits = max_lum > 0 ? (float)max_lum : kDefaultMaxNits;
    c = nits / paper_white_nits();
    if (c < 1.f) {
      c = 1.f;
    }
  }
  s_last_ceiling = c;
  return c;
}

void push_present_uniforms(Shader& shader) {
  const bool on = s_active.load();
  int max_lum = 0;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    max_lum = s_sys.max_lum;
  }
  s_last_present_mode = on ? 1 : 0;
  glUniform1i(glGetUniformLocation(shader.id(), "u_out_mode"), s_last_present_mode);
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_paper_white"), paper_white_nits());
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_max_nits"),
              max_lum > 0 ? (float)max_lum : kDefaultMaxNits);
}

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
  } else if (s_phase < 3) {
    PhaseStats& ph = s_ph[s_phase];
    ph.frames++;
    ph.active_frames += on ? 1 : 0;
    ph.surface_hdr_frames += s_surface.hdr ? 1 : 0;
    ph.last_red_bits = s_surface.red_bits;
    ph.last_colorspace = s_surface.colorspace;
    const bool expect_on = (s_phase == 1);
    const bool expect_off = (s_phase == 2);
    if (expect_on) {
      ph.sites_bad += (sites == 1) ? 0 : 1;
      ph.ui_bad += (ui_fmt == GL_RGBA16F) ? 0 : 1;
      ph.present_bad += (s_last_present_mode == 1) ? 0 : 1;
      ph.ceiling_bad += (s_last_ceiling > 1.f) ? 0 : 1;
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
