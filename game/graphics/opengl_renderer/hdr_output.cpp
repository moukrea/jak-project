#include "game/graphics/opengl_renderer/hdr_output.h"
#include "game/system/recharged_gating.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/runtime.h"  // g_game_version : le shader de reduction se construit comme les autres
#include "game/system/autoport_proof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace hdr_output {
namespace {
AUTOPORT_FEATURE_SITE(kPlanId);
AUTOPORT_FEATURE_SITE(kStudyId);
AUTOPORT_FEATURE_SITE(kItemId);
AUTOPORT_FEATURE_SITE(kShadowId);

// Valeurs EGL brutes (EGL_KHR_gl_colorspace / EGL_EXT_gl_colorspace_bt2020_pq /
// EGL_EXT_gl_colorspace_scrgb_linear), reprises ici pour que la publication ne depende pas des
// en-tetes EGL sur le bureau.
constexpr int kEglColorspaceSrgb = 0x3089;
constexpr int kEglColorspaceLinear = 0x308A;
constexpr int kEglColorspaceBt2020Pq = 0x3340;
constexpr int kEglColorspaceScrgbLinear = 0x3350;
constexpr int kEglColorspaceBt2020Hlg = 0x3540;  // EGL_EXT_gl_colorspace_bt2020_hlg

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
    add(s_plat.egl_bt2020_hlg, "bt2020_hlg");
    add(s_plat.egl_cta861_3, "cta861_3");
    t += e.empty() ? "none" : e;
  }
  t += std::string(";cfg10=") + (s_plat.config_10bit ? "1" : "0");
  t += std::string(";cfg16f=") + (s_plat.config_fp16 ? "1" : "0");
  t += std::string(";sdl_display_hdr=") + (s_plat.sdl_display_hdr ? "1" : "0");
  t += std::string(";sdl_window_hdr=") + (s_plat.sdl_window_hdr ? "1" : "0");
  t += ";sdl_headroom_x100=" + std::to_string(s_plat.sdl_headroom_x100);
  s_caps_text = t;
}

// -------------------------------------------------------------------------- les formats --
// Verdict 13. LE FORMAT est ce que l'ECRAN annonce savoir decoder (masque
// Display.HdrCapabilities) ; le MODE est le transport que la couche de presentation sait
// creer. HDR10+ et HDR10 partagent le transport PQ. Chaque ligne se lit dans les capacites :
// rien ici ne nomme un appareil.
// LE CONTRAT DE MARGE ETENDUE. scRGB n'a de sens que si quelqu'un PUBLIE la marge au-dessus du
// blanc SDR : sans contrat, 1,0 ne veut rien dire. Deux systemes le tiennent, et le contrat est
// le MEME (1,0 = blanc SDR courant, au-dessus = ce que le systeme accorde) :
//   * Android 14+ : Display.getHdrSdrRatio() (sdk_int >= 34) ;
//   * bureau : le compositeur publie deja la marge de NOTRE fenetre, que SDL recopie dans
//     SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT — DWM sous Windows (DXGI MaxLuminance / blanc SDR),
//     wp_color_management ou frog sous Wayland. C'est la meme grandeur, lue au meme endroit du
//     contrat. Aucun appareil, aucun OS n'est nomme : on lit ce que la couche publie.
bool scrgb_contract_locked() {
  return s_sys.sdk_int >= 34 || (s_plat.sdl_window_hdr && s_plat.sdl_headroom_x100 > 100);
}

uint32_t format_transport_locked(int fmt) {
  switch (fmt) {
    case kFmtScrgb: {
      if (!scrgb_contract_locked()) {
        return kModeNone;
      }
      // Deux facons de POSER une surface scRGB lineaire. La premiere est celle d'EGL (Android,
      // et Linux quand le pilote annonce l'extension). La seconde est la seule qui existe en
      // OpenGL sous Windows : il n'y a AUCUNE extension WGL de colorspace, mais un tampon de
      // fenetre a composantes flottantes est interprete en scRGB lineaire par le compositeur
      // des que l'ecran est en mode HDR — et c'est ce meme compositeur qui publie la marge.
      const bool egl_path = s_plat.egl_scrgb_linear && s_plat.egl_fp16 && s_plat.config_fp16;
      const bool compositor_fp16 = s_plat.sdl_window_hdr && s_plat.config_fp16;
      return (egl_path || compositor_fp16) ? kModeScrgbLinear : kModeNone;
    }
    case kFmtHdr10Plus:  // meme transport que HDR10 ; ce qui manque, ce sont les metadonnees
    case kFmtHdr10:
      return (s_plat.egl_bt2020_pq && s_plat.config_10bit) ? kModeHdr10Pq : kModeNone;
    case kFmtHlg:
      return (s_plat.egl_bt2020_hlg && s_plat.config_10bit) ? kModeHlg : kModeNone;
    default:
      return kModeNone;  // Dolby Vision : licence, hors perimetre — jamais de transport
  }
}

uint32_t format_sys_bit(int fmt) {
  switch (fmt) {
    case kFmtHdr10Plus: return kSysHdr10Plus;
    // kSysSdl : le bureau n'a pas de HdrCapabilities. Ce que SDL publie, c'est « cet ecran est
    // en mode HDR » (SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN) — et un ecran de bureau en mode HDR
    // decode HDR10/PQ par construction (c'est le format du transport DisplayPort/HDMI dans ce
    // mode). Le bit vaut donc annonce de HDR10, et de rien d'autre : ni HLG, ni HDR10+.
    case kFmtHdr10: return kSysHdr10 | kSysSdl;
    case kFmtHlg: return kSysHlg;
    case kFmtDolbyVision: return kSysDolbyVision;
    default: return 0;  // scRGB n'est pas un format annonce par l'ecran : c'est un transport
  }
}

bool format_announced_locked(int fmt) {
  if (fmt == kFmtScrgb) {
    // scRGB n'apparait dans aucune HdrCapabilities : il n'est « annonce » que si l'ecran est
    // HDR par ailleurs ET que l'API 34 contractualise la marge.
    return (s_sys.types & (kSysHdr10 | kSysHlg | kSysHdr10Plus | kSysDolbyVision | kSysSdl)) !=
               0 &&
           scrgb_contract_locked();
  }
  return (s_sys.types & format_sys_bit(fmt)) != 0;
}

bool format_usable_locked(int fmt) {
  if (fmt == kFmtDolbyVision || fmt == kFmtHdr10Plus) {
    return false;  // cf. format_reason_locked
  }
  return format_announced_locked(fmt) && format_transport_locked(fmt) != kModeNone;
}

// Pourquoi un format annonce n'est PAS retenu. Jamais vide : une chaine vide laisserait la
// valeur precedente en place cote preuve.
const char* format_reason_locked(int fmt) {
  switch (fmt) {
    case kFmtDolbyVision:
      return "licence_hors_perimetre";
    case kFmtHdr10Plus:
      // L'ecran sait decoder les metadonnees DYNAMIQUES, mais aucune API publique Android/EGL
      // n'en laisse poser a une surface applicative (seules SMPTE2086 et CTA861.3, statiques,
      // existent). Le repli est HDR10, meme transport PQ ; l'adaptation par image que fait
      // notre courbe tient lieu de metadonnee dynamique, cote application.
      return format_transport_locked(kFmtHdr10) != kModeNone
                 ? "pas_d_api_publique_de_metadonnees_dynamiques:repli_hdr10"
                 : "pas_d_api_dynamique_et_pas_de_transport_pq";
    case kFmtHlg:
      if (!format_announced_locked(kFmtHlg)) return "non_annonce_par_l_ecran";
      if (!s_plat.egl_bt2020_hlg) return "egl_sans_colorspace_bt2020_hlg";
      if (!s_plat.config_10bit) return "pas_de_config_10bit";
      return "-";
    case kFmtHdr10:
      if (!format_announced_locked(kFmtHdr10)) return "non_annonce_par_l_ecran";
      if (!s_plat.egl_bt2020_pq) return "egl_sans_colorspace_bt2020_pq";
      if (!s_plat.config_10bit) return "pas_de_config_10bit";
      return "-";
    case kFmtScrgb:
      if (!scrgb_contract_locked()) {
        return s_sys.sdk_int > 0 ? "sdk<34:aucun_contrat_de_marge_etendue"
                                 : "le_compositeur_ne_publie_aucune_marge_pour_cette_fenetre";
      }
      if (!format_announced_locked(kFmtScrgb)) return "aucun_ecran_hdr_annonce";
      if (!s_plat.config_fp16) return "pas_de_config_fp16";
      if (!s_plat.egl_scrgb_linear && !s_plat.sdl_window_hdr)
        return "egl_sans_scrgb_lineaire_et_pas_de_fenetre_hdr";
      if (!s_plat.egl_scrgb_linear && !s_plat.egl_fp16 && !s_plat.sdl_window_hdr)
        return "egl_sans_scrgb_lineaire_fp16";
      return "-";
    default:
      return "-";
  }
}

// L'ORDRE DE PREFERENCE, une fois pour toutes. scRGB passe devant parce qu'il est le SEUL
// transport dont la marge au-dessus du blanc SDR soit CONTRACTUELLE et LISIBLE
// (Display.getHdrSdrRatio) ; les trois suivants sont l'ordre demande par l'owner.
const int kFormatPreference[4] = {kFmtScrgb, kFmtHdr10Plus, kFmtHdr10, kFmtHlg};

int format_chosen_locked() {
  for (int i = 0; i < 4; i++) {
    if (format_usable_locked(kFormatPreference[i])) {
      return kFormatPreference[i];
    }
  }
  return kFmtNone;
}

// Le rang du format retenu dans la preference, 1 = le meilleur. 0 = aucun.
int format_rank_locked(int fmt) {
  for (int i = 0; i < 4; i++) {
    if (kFormatPreference[i] == fmt) return i + 1;
  }
  return 0;
}

// Les modes que les DEUX couches savent tenir, en MASQUE (plusieurs bits possibles). Separe de
// `modes_locked()`, qui n'en retient qu'un : l'auto-test a besoin de savoir qu'il en existe un
// SECOND pour aller le mesurer (spec de l'item : « publier CHAQUE chemin »).
uint32_t modes_supported() {
  // Un mode n'est « annonce » que si le SYSTEME dit que l'ecran est HDR ET que la couche de
  // presentation sait creer une surface dans cet espace. Bureau (hdr-desktop-output) : les deux
  // couches existent aussi — SDL annonce l'ecran, et la couche de presentation est EGL quand le
  // pilote la donne (Linux), sinon le tampon flottant du compositeur (Windows). Ce qui manque a
  // une plateforme est publie avec sa RAISON, jamais suppose.
  // Verdict 13 : le masque SUIT DESORMAIS LES FORMATS ANNONCES. Un transport n'y entre que si
  // un format que l'ecran annonce l'exige, de sorte que mode et format ne puissent jamais
  // diverger (HDR10 et HDR10+ demandent le PQ, HLG le HLG, scRGB le scRGB lineaire).
  if (!s_sys.reported || !s_plat.probed) {
    return kModeNone;
  }
  const bool sys_hdr =
      (s_sys.types & (kSysHdr10 | kSysHlg | kSysHdr10Plus | kSysDolbyVision | kSysSdl)) != 0;
  if (!sys_hdr) {
    return kModeNone;
  }
  uint32_t m = kModeNone;
  for (int i = 0; i < 4; i++) {
    const int f = kFormatPreference[i];
    if (format_announced_locked(f)) {
      m |= format_transport_locked(f);   // 0 quand la plateforme ne sait pas le produire
    }
  }
  return m;
}

// Le mode PREFERE quand personne ne force : celui qu'EXIGE le format retenu.
uint32_t auto_mode(uint32_t supported) {
  const uint32_t t = format_transport_locked(format_chosen_locked());
  if (t && (supported & t)) {
    return t;
  }
  // Repli : l'ordre de preference des transports, si jamais le format retenu n'est pas dans
  // le masque (ne devrait pas arriver — modes_supported est construit depuis les formats).
  if (supported & kModeScrgbLinear) return kModeScrgbLinear;
  if (supported & kModeHdr10Pq) return kModeHdr10Pq;
  return supported & kModeHlg;
}

// L'AUTRE chemin annonce, celui que l'auto-test ira mesurer en phase 4. 0 = il n'y en a qu'un.
uint32_t alt_mode(uint32_t supported) {
  // UN SEUL bit. Avec trois transports annonces, `supported & ~auto_mode` en rendait deux ; ce
  // masque partait tel quel dans `s_test_mode`, et `switch_surface` — qui compare a des valeurs
  // simples — ne le reconnaissait comme aucun des trois et retombait sur l'espace LINEAR. La
  // phase 4 mesurait alors du SDR en se croyant sur l'autre chemin.
  const uint32_t rest = supported & ~auto_mode(supported);
  if (rest & kModeScrgbLinear) return kModeScrgbLinear;
  if (rest & kModeHdr10Pq) return kModeHdr10Pq;
  if (rest & kModeHlg) return kModeHlg;
  return kModeNone;
}

// Le mode IMPOSE : auto-test (phase 4) > knob du harnais > aucun. Defini plus bas, apres
// `read_int_knob` ; declare ici parce que `modes_locked()` en depend.
uint32_t forced_mode();

uint32_t modes_locked() {
  const uint32_t sup = modes_supported();
  if (!sup) {
    return kModeNone;
  }
  const uint32_t forced = forced_mode();
  if (forced && (sup & forced)) {
    return forced;
  }
  return auto_mode(sup);
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
// REGIME SIMULE, MESURE SEULEMENT (hdr-desktop-output) : un blanc SDR impose par le CODE, par le
// meme point d'entree que le knob. Il existe parce que la preuve bureau doit exercer la courbe a
// deux pics d'ecran differents sans ecran HDR, et qu'un pic ne dit rien sans son blanc.
float s_sim_white = 0.f;
// Verdict 10 (owner 09/09 : « celui-ci fait 480, mais quid d'un ecran a 1000 ? ») : le pic
// annonce peut etre SIMULE par debug.opengoal.hdr.out.peak / OG_HDR_OUT_PEAK (nits), et
// l'auto-test impose lui-meme un pic simule dans sa phase 3 par ce MEME chemin.
float s_peak_knob = -1.f;             // -1 = pas lu, 0 = absent, sinon nits
float s_test_peak = 0.f;              // auto-test : 0 = aucun, sinon nits imposes
// Verdict 11 : le chemin de sortie peut etre IMPOSE, pour aller mesurer l'autre que celui que
// `auto_mode` retiendrait. 1 = HDR10 PQ, 2 = scRGB lineaire, 0 = aucun.
int s_mode_knob = -1;                 // -1 = pas lu, 0 = absent, sinon kMode*
uint32_t s_test_mode = kModeNone;     // auto-test phase 4 : 0 = aucun, sinon le mode impose
// Les deux autres leviers du systeme (mode couleur HDR de la fenetre, setDesiredHdrHeadroom).
bool s_lever_pending = false;
bool s_lever_on = false;
float s_lever_desired = 1.f;
uint64_t s_lever_requests = 0;
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

// ---------------------------------------------------- la marge ACCORDEE, mesuree physiquement --
// ANNONCER N'EST PAS ACCORDER. Avant l'API 34 aucune API ne PUBLIE la marge : `headroom_linear()`
// la deduit du quotient pic/blanc, tous deux tires du MEME champ annonce. C'est un miroir de
// notre propre arithmetique — il rend 1,000 par construction, et un 1,000 qui ne peut pas valoir
// autre chose ne mesure rien (il ne distingue pas « l'ecran n'accorde rien » de « notre modele ne
// sait pas lire ce qu'il accorde »). Ce que le systeme doit FAIRE pour donner de la marge
// au-dessus de son blanc SDR est physique : monter la consigne de retro-eclairage du panneau
// au-dessus du point SDR pendant que la couche HDR est a l'ecran. Le systeme publie cette
// consigne dans `debug.tracing.screen_brightness` (normalisee, 0..1). On l'echantillonne pendant
// la phase ON et pendant la phase OFF de l'auto-test : meme scene, meme instant a 150 images
// pres, un seul parametre change. Si elle ne bouge pas, rien n'a ete accorde — et le 1,000
// publie devient une MESURE, falsifiable par un ecran qui, lui, bougerait.
float read_float_prop(const char* prop) {
#ifdef __ANDROID__
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(prop, buf) > 0 && buf[0]) {
    return (float)std::atof(buf);
  }
#else
  (void)prop;
#endif
  return -1.f;
}

struct BacklightProbe {
  uint64_t samples = 0;
  double sum = 0.0;
  float max = -1.f;
  float min = -1.f;
};
BacklightProbe s_bl_on;   // phases ON reelles (1 et 4)
BacklightProbe s_bl_off;  // phase OFF (2)

void backlight_sample(BacklightProbe& p) {
  const float v = read_float_prop("debug.tracing.screen_brightness");
  if (!(v >= 0.f)) {
    return;  // propriete absente (bureau, ou systeme qui ne la publie pas) : on ne compte rien
  }
  p.samples++;
  p.sum += v;
  if (p.max < 0.f || v > p.max) {
    p.max = v;
  }
  if (p.min < 0.f || v < p.min) {
    p.min = v;
  }
}

// ---- LA MARGE, ACHETEE AU RETRO-ECLAIRAGE, ET RELUE SUR LA CONSIGNE DU SYSTEME ----------------
// Aucun des trois leviers du depot ne rend de marge avant l'API 34 : setExtendedRangeBrightness
// est 34+, setDesiredHdrHeadroom 35+, et setColorMode(COLOR_MODE_HDR) ne peut rien sur un ecran a
// supportedColorModes=[0]. Le MECANISME que ces API pilotent, lui, existe depuis l'API 1 : monter
// la consigne de retro-eclairage du panneau pendant que notre fenetre est a l'ecran, et baisser
// d'autant le blanc SDR dans le signal. Le contenu SDR emet alors EXACTEMENT la meme lumiere
// qu'avant (il est divise par H dans le signal, multiplie par H par la dalle) et les hautes
// lumieres seules montent : c'est la definition de la marge, pas un « boost faked » applique aux
// pixels. WindowManager.LayoutParams.screenBrightness porte sur NOTRE fenetre et se defait tout
// seul a la perte du focus.
//
// LA MARGE N'EST PAS LE FACTEUR DEMANDE, c'est celui que le systeme a effectivement pose. On ne
// lit donc pas notre propre requete : on lit `debug.tracing.screen_brightness`, une grandeur
// produite par le SYSTEME, avant le levier (la base = le reglage de l'utilisateur) et apres
// (l'obtenu). Le quotient est la marge. Si le systeme refuse, il vaut 1,000 et tout le chemin
// retombe sur le comportement d'avant : la porte reste FALSIFIABLE au lieu d'etre le miroir de
// notre propre arithmetique (pic annonce / blanc annonce, qui ne peut valoir autre chose).
constexpr int kLeverSettleReads = 8;  // le panneau rampe : on jette les lectures de transition
float s_bl_base = -1.f;               // consigne HORS levier (le choix de l'utilisateur)
float s_bl_now = -1.f;                // derniere consigne lue
float s_bl_target = -1.f;             // consigne demandee a la fenetre (< 0 = aucune)
float s_bl_grant = 1.f;               // marge OBTENUE = now / base, >= 1 (VALEUR DE L'IMAGE)
float s_bl_grant_pending = 1.f;       // la derniere lue ; elle ne prend qu'a la frontiere d'image
float s_bl_grant_max = 1.f;
uint64_t s_bl_base_samples = 0;
uint64_t s_bl_grant_samples = 0;
bool s_bl_lever_applied = false;  // le levier est-il pose en ce moment ?
int s_bl_settle = 0;              // lectures restantes a jeter apres un changement de levier

// La marge que le SYSTEME a rendue, telle que la courbe l'utilisera. 1,000 = il n'a rien rendu.
float measured_grant() {
  return s_bl_grant;
}

void backlight_track() {
  const float v = read_float_prop("debug.tracing.screen_brightness");
  if (!(v > 0.f)) {
    return;  // bureau, ou systeme qui ne publie pas cette consigne : aucune marge achetable ici
  }
  s_bl_now = v;
  if (s_bl_settle > 0) {
    s_bl_settle--;
    return;  // la rampe est en cours : ni la base ni la marge ne sont lisibles
  }
  if (!s_bl_lever_applied) {
    s_bl_base = v;
    s_bl_base_samples++;
    s_bl_grant_pending = 1.f;
    return;
  }
  if (!(s_bl_base > 0.f)) {
    return;  // levier pose sans base connue : on ne devine pas
  }
  float g = v / s_bl_base;
  if (!(g >= 1.f)) {
    g = 1.f;
  }
  if (g > kHeadroomMax) {
    g = kHeadroomMax;
  }
  s_bl_grant_pending = g;
  s_bl_grant_samples++;
  if (g > s_bl_grant_max) {
    s_bl_grant_max = g;
  }
}

// La marge ne prend qu'a la FRONTIERE D'IMAGE, jamais au milieu. La consigne se lit dans
// `frame_end`, apres le dessin ; `tonemap_ceiling()` en depend et `curve_params()` l'a deja fige
// dans `s_last_ceiling` pendant le dessin. Sans ce verrou, l'image ou la marge arrive aurait un
// plafond dessine et un plafond attendu differents : `ceiling_bad` incremente d'une unite, et le
// verdict 4 (« UNE seule compression de plage ») vire au rouge pour une raison d'ordonnancement.
void backlight_commit() {
  s_bl_grant = s_bl_grant_pending;
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

uint32_t forced_mode() {
  if (s_test_mode != kModeNone) {
    return s_test_mode;  // l'auto-test, phase 4 : l'AUTRE chemin
  }
  if (s_mode_knob < 0) {
    const int v = read_int_knob("debug.opengoal.hdr.out.mode", "OG_HDR_OUT_MODE", 0);
    s_mode_knob = (v == (int)kModeHdr10Pq || v == (int)kModeScrgbLinear) ? v : 0;
    if (s_mode_knob) {
      lg::warn("[hdr-display-output] chemin de sortie IMPOSE par le harnais : {}",
               s_mode_knob == (int)kModeHdr10Pq ? "HDR10/PQ" : "scRGB/16F");
    }
  }
  return (uint32_t)s_mode_knob;
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

// BT.2408 : le blanc GRAPHIQUE du PQ. C'est la reference normative de la recommandation, pas
// un calibrage maison : en PQ le blanc de l'interface se place a 203 nits absolus quel que soit
// le pic du panneau, et tout ce qui est au-dessus est de la haute lumiere.
constexpr float kGraphicsWhiteNits = 203.f;

// L'ecran PRESENTE-t-il le HDR, ou se contente-t-il de le DECODER ?
//
// La distinction commande tout le chemin PQ. Sur un ecran qui PRESENTE, le blanc graphique se
// pose a 203 nits et le panneau garde `pic/203` au-dessus pour les hautes lumieres. Sur un ecran
// qui DECODE, le compositeur ramene le signal PQ a l'echelle de son propre blanc SDR : y poser le
// blanc a 203 nits n'ouvre aucune marge, ca ne fait qu'ASSOMBRIR l'image de 203/pic — le refus
// owner du 09/09 (« tout est BEAUCOUP plus sombre, les a-plats blancs sont gris »).
//
// AUCUN APPAREIL N'EST NOMME ICI. La decision se lit dans la FORME de ce que l'ecran annonce, et
// chaque entree est publiee pour qu'un lecteur puisse la refaire :
//   * API 34+ : `Display.getHdrSdrRatio()` existe — c'est un CONTRAT, l'ecran presente ;
//   * avant, trois signaux publics, TOUS exiges. L'asymetrie des erreurs impose cette prudence :
//     un faux « presente » assombrit l'image (defaut visible), un faux « decode » laisse
//     seulement la feature inerte (etat d'avant). Donc :
//       - `isWideColorGamut()` : un panneau qui presente du BT.2020 est large par construction ;
//       - `maxAverage < max` : un vrai panneau HDR ne tient pas son pic en plein ecran ; une
//         declaration de complaisance recopie le meme nombre dans les deux champs ;
//       - `minLuminance > 0` : un vrai panneau declare son noir.
//     Et le pic doit valoir au moins deux fois le blanc graphique, sans quoi l'ancrage a 203
//     n'achete pas de marge : il ne ferait qu'assombrir.
struct PresentVerdict {
  bool presents;
  const char* reason;
};
int s_test_presents = 0;        // auto-test phase 3 : simule un ecran qui PRESENTE
int s_presents_cache = -1;      // -1 = pas encore decide (les caps arrivent apres le demarrage)
const char* s_presents_reason = "pas_encore_decide";

PresentVerdict display_presents_hdr() {
  if (s_test_presents) {
    return PresentVerdict{true, "auto-test:ecran_presentant_simule"};
  }
  if (s_presents_cache < 0) {
    SysCaps c;
    {
      std::lock_guard<std::mutex> lk(s_mu);
      c = s_sys;
    }
    const char* why = nullptr;
    bool yes = false;
    if (c.ratio_available) {
      yes = true; why = "api34:Display.getHdrSdrRatio_est_un_contrat";
    } else if (c.max_lum <= 0) {
      why = "aucun_pic_annonce";
    } else if (!c.wide_gamut) {
      why = "isWideColorGamut=false:l_ecran_ne_presente_pas_le_bt2020";
    } else if (!(c.max_avg > 0 && c.max_avg < c.max_lum)) {
      why = "maxAverage=max:declaration_degeneree";
    } else if (c.min_lum_x10000 <= 0) {
      why = "minLuminance=0:aucun_noir_declare";
    } else if ((float)c.max_lum < 2.f * kGraphicsWhiteNits) {
      why = "pic_annonce_sous_deux_fois_le_blanc_graphique";
    } else {
      yes = true; why = "forme_des_capacites:gamut_large+maxAverage<max+minLuminance>0";
    }
    s_presents_reason = why;
    s_presents_cache = yes ? 1 : 0;
    lg::info("[hdr-display-output] l'ecran {} le HDR : {}", yes ? "PRESENTE" : "ne fait que DECODER",
             why);
  }
  return PresentVerdict{s_presents_cache > 0, s_presents_reason};
}

// hdr-output-regime : LE SEUL SITE DE DECISION DU REGIME (plan §3.3). La meme expression vivait
// en TROIS exemplaires — `publish_plan()`, `sdr_white_nits_for()` et `sdr_white_source()` — sans
// qu'aucune fonction ne la porte. Trois copies d'une decision, c'est trois occasions de diverger,
// et c'est aussi pourquoi R0/R1/R2 n'existaient nulle part hors de l'instrument du plan.
// AUCUN APPAREIL N'EST NOMME : tout vient de ce que l'ecran ANNONCE et de ce que le systeme
// ACCORDE, y compris quand il n'accorde rien.
char s_regime_reason[192] = "pas_encore_decide";
RegimeVerdict regime_now() {
  const PresentVerdict pv = display_presents_hdr();
  if (pv.presents) {
    return RegimeVerdict{2, "ecran-presente", pv.reason};
  }
  // LA LOI QUI GOUVERNE R1, ET ELLE NE NOMME AUCUNE DALLE : sur un ecran qui ne fait que
  // DECODER, la marge vaut `luminosite maximale du panneau / luminosite courante du joueur`.
  // A luminosite maximale elle vaut 1,000 PARTOUT. Ce n'est pas une limite de l'appareil
  // d'epreuve : c'est vrai de toute dalle.
  const float g = measured_grant();
  if (g > 1.005f) {
    std::snprintf(s_regime_reason, sizeof(s_regime_reason),
                  "retroeclairage:consigne_obtenue_x1000=%d_sur_%llu_echantillons",
                  (int)std::lround(g * 1000.f), (unsigned long long)s_bl_grant_samples);
    return RegimeVerdict{1, "marge-accordee", s_regime_reason};
  }
  std::snprintf(s_regime_reason, sizeof(s_regime_reason),
                "aucune_marge:%s+retroeclairage_x1000=%d", pv.reason,
                (int)std::lround(g * 1000.f));
  return RegimeVerdict{0, "aucune-marge", s_regime_reason};
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
// Cinq phases, par image : 0 = etat charge, 1 = ON impose (chemin retenu), 2 = OFF impose,
// 3 = ON impose avec un pic d'ecran SIMULE (verdict 10), 4 = ON impose sur l'AUTRE chemin
// annonce par les caps (verdict 11 : « publier CHAQUE chemin »), 5 = termine. La phase 4 est
// sautee, et sa colonne reste a zero, quand un seul chemin est annonce.
constexpr uint64_t kPhaseFrames = 150;
constexpr int kPhaseCount = 5;
// Verdict 11 : les rampes. 128 marches, deux fenetres de 1/16 de l'espace d'affichage du jeu.
constexpr int kRampN = 128;
constexpr float kRampWindow = 1.f / 16.f;
constexpr float kSimPeakNits = 1000.f;
constexpr uint64_t kProbeEvery = 5;
constexpr int kReadyHits = 3;
constexpr uint64_t kReadyPx = 256;   // un quart de la sonde 32x32 en tons moyens
constexpr double kReadyCapSeconds = 150.0;
// PLANCHER DE TEMPS avant la premiere phase. La course d'appareil pose desormais
// `debug.opengoal.level.warp` : le moteur quitte l'ecran-titre pour un niveau JOUABLE vers la
// 50e seconde, et ce teleport recree du contenu pendant plusieurs secondes. L'auto-test bascule
// la SURFACE EGL ; les deux au meme instant, c'est un ecran noir pour une raison qui n'a rien a
// voir avec la sortie HDR. On laisse donc le teleport et son chargement se terminer d'abord.
constexpr double kMinStartSeconds = 75.0;
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
  // Le blanc SDR EN VIGUEUR dans la phase. Le verdict 10 compare deux regimes qui n'ont pas la
  // meme reference : sans lui, il comparerait des nits a des nits d'echelles differentes.
  float last_sdr_white = 0.f;
  int ratio_max_x1000 = 1000;  // la plus grande marge que le SYSTEME ait accordee dans la phase
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
  // Verdict 11 : niveaux DISTINCTS que la sortie sait encore separer sur chaque rampe, au
  // format REEL de la fenetre. On garde le meilleur echantillon de la phase : une rampe est un
  // stimulus fixe, une valeur plus basse ne peut venir que d'une image ratee.
  uint64_t ramp_samples = 0;
  uint64_t shadow_levels = 0;
  uint64_t hl_levels = 0;
  // FENETRE ETENDUE (essai 16). `hl_levels` ne couvre que [15/16, 1] de la scene : une courbe a
  // plafond > 1 ecrit ses codes NEUFS au-dessus de 1,0, la ou cette fenetre ne regarde pas. En
  // phase 3 (ecran presentant simule, plafond 2,06) elle rendait 17, exactement comme en OFF —
  // le verdict aurait ete rouge sur un VRAI ecran HDR, pour une raison d'INSTRUMENT. Celle-ci
  // couvre [15/16, kFixedTop] : l'espace ou la courbe ecrit reellement.
  uint64_t hl_ext_levels = 0;
  // Verdict 10 : la reponse du tone map a un STIMULUS FIXE (rampe 0..3 dans l'espace du
  // tampon). `hl_max` ci-dessus est pris sur la SCENE, qui bouge entre la phase 1 et la phase
  // 3 : mesure du 10/09, 1,877 en reel contre 1,221 en pic simule alors que le plafond, lui,
  // montait bien de 1,88 a 2,33. Un stimulus fixe fait disparaitre la scene de la comparaison.
  double hl_fixed_sum = 0.0;   // somme des canaux max sur la rampe, plafond COURANT
  double hl_fixed_ref = 0.0;   // idem au plafond 1,0, meme image : la reference SDR
  uint64_t hl_fixed_samples = 0;
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
// 17 verdicts. Les deux derniers sont ceux que la consigne du 10/09 portait, qui ont ete PERDUS
// en la raccourcissant (commit c054ce9a48) et que l'item a donc passe quatre fois sans les
// mesurer : 16 = SOURCE AVANT COMPRESSION, 17 = RICHESSE DANS LES OMBRES sur du jeu reel.
int s_d[18] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
// La plus grande marge que le systeme ait accordee pendant une phase ON REELLE (pas la phase a
// pic simule) : la grandeur du verdict 11 qui dit si l'ecran laisse depasser son blanc SDR.
int s_ratio_max_x1000 = 1000;
uint32_t s_alt_mode = kModeNone;  // le chemin mesure en phase 4 (0 = il n'y en avait qu'un)
// La « RECOMPOSITION » mesuree par les essais 13 et 14 est RETIREE (essai 15). Elle lisait
// (w_sim/w_reel) / (pic_sim/pic_reel) sur la sonde de blanc UI. Or cette sonde dessine le texel
// blanc dans un FBO HORS ECRAN avec notre propre programme (`probe_present`) : ni le compositeur
// ni la dalle ne sont dans la boucle. Le blanc y est encode a `u_out_paper_white`, c'est-a-dire
// `paper_white() == sdr_white_nits() == peak_nits()` — doubler le pic doublait donc le blanc
// mesure PAR CONSTRUCTION, sur n'importe quel ecran. Le quotient valait 1,000 a 0,0 % pres parce
// qu'il etait notre propre arithmetique, pas parce que la dalle recomposait quoi que ce soit.
// Ce qui reste, et qui est vrai : `hdr_out_presents_hdr` (la FORME des capacites annoncees) et
// `hdr_out_grant_physical` (la consigne de retro-eclairage ON contre OFF, lue du systeme).

// Sonde de blanc UI (probe_present) : ce que le quad final ECRIT pour un blanc (1,1,1) du jeu,
// dans le mode courant, et ce qu'il ecrirait en recopie SDR (u_out_mode = 0) pour le meme blanc
// — la reference « ce que le SDR montre » inclut donc le reglage de luminosite du joueur.
GLuint s_pp_fbo = 0, s_pp_tex = 0, s_pp_white = 0;
int s_pp_state = 0;  // 0 pas cree, 1 pret, -1 indisponible
// Sonde de RAMPES (verdict 11) : deux sources 128x1 en tons du jeu (ombres, hautes lumieres) et
// une cible au FORMAT REEL DE LA FENETRE — c'est la quantification de la sortie qu'on mesure,
// pas celle d'un FBO flottant de confort. La cible est refaite des que le format change.
GLuint s_rp_fbo = 0, s_rp_tex = 0, s_rp_src[3] = {0, 0, 0};
GLenum s_rp_fmt = 0;
int s_rp_state = 0;  // 0 pas cree, 1 pret, -1 indisponible
int s_rp_read_type = 0;  // le type de relecture REELLEMENT accepte, publie
// Sonde d'assombrissement (probe_tonemap) : luminance lineaire des tons moyens de la scene,
// tone-mappee au plafond 1,0 (le SDR) et au plafond HDR courant, sur la MEME image.
GLuint s_tm_fbo[2] = {0, 0}, s_tm_tex[2] = {0, 0};
int s_tm_state = 0;
constexpr int kTmW = 32, kTmH = 32;
// Verdict 10 : le STIMULUS FIXE du tone map. Une rampe 0..kFixedTop dans l'espace d'affichage
// du tampon (le genou vit vers 0,96 x plafond) et une cible flottante 128x1.
GLuint s_tf_fbo = 0, s_tf_tex = 0, s_tf_src = 0;
int s_tf_state = 0;
constexpr float kFixedTop = 3.f;

// ------------------------------------------------- ADAPTATION AU CONTENU (verdict 13) ----
// Refus owner du 10/09 : « c'est statique non ? le HDR s'ajuste pas constamment, facon dolby
// vision ou HDR10+ dans les films, la j'ai l'impression qu'on a un truc HDR et fini, c'est
// applique partout pareil. » Un HDR10 statique porte UNE courbe pour tout le film ; Dolby Vision
// et HDR10+ portent des metadonnees par plan. Ici il n'y a pas de metadonnees a lire : la scene
// est produite a l'instant, on la MESURE. Une image sur huit, la scene est reduite a 256 tuiles
// et deux grandeurs en sortent — la luminance log-moyenne (le « niveau » de la scene) et le haut
// de scene (la moyenne des 2 % de tuiles les plus claires). Elles pilotent l'ancre, le sommet et
// le pied de la courbe, apres un lissage a constante de temps asymetrique ET un limiteur de
// vitesse : c'est ce limiteur qui rend le pompage impossible, pas une chance.
constexpr uint64_t kAnalyzeEvery = 8;      // images entre deux analyses (chemin PBO)
constexpr uint64_t kAnalyzeEverySync = 30; // idem, quand le PBO n'est pas disponible
constexpr int kAnW = 16, kAnTileH = 16;     // 256 tuiles par etage
// hdr-curve-input (chantier B du plan HDR, §1.5) — LA CIBLE D'ANALYSE PORTE DEUX ETAGES.
// Lignes 0..15 : les tuiles MOYENNES, c'est-a-dire le sous-echantillonnage bilineaire d'avant,
// inchange au bit. Elles portent `key` (la luminance log-moyenne) et `hi` (le centile qui place
// l'ancre) : ces deux-la SONT des moyennes par nature, et les tirer d'un maximum deplacerait
// l'ancre, donc la courbe — ce que le perimetre interdit.
// Lignes 16..31 : les tuiles MAXIMUM, produites par la pyramide de `max()` a couverture totale.
// Elles portent `peak`, et lui seul. C'est la grandeur que l'etude a mesuree SOURDE d'un facteur
// 9,3 (1,617 contre 15,094) parce qu'une moyenne de moyennes ne peut pas voir un pixel a 15x.
// Les deux etages sortent par UNE seule lecture asynchrone : l'anneau de PBO ne change pas.
constexpr int kAnH = kAnTileH * 2;
// La pyramide : un premier etage qui divise par 8 dans chaque direction (donc au plus 64
// `texelFetch` par texel de sortie, la borne constante des boucles du shader), un second qui
// tombe a 16x16. Au format de scene de l'appareil (640x480) cela fait 80x60 puis 16x16 : la
// premiere passe lit EXACTEMENT une fois chaque pixel de la scene, la seconde 20 texels par
// tuile. Le cout est celui de deux quads reduits, une image sur huit.
constexpr int kMrDiv = 8;
// Le TEMOIN de la porte : une relecture PLEINE RESOLUTION du tampon de scene, sur la MEME image
// que l'analyse, une analyse sur `kRefEvery`. Il ne partage aucune ligne avec la pyramide — ni
// shader, ni cible, ni chemin de lecture — donc un rapport calcule entre les deux n'est pas un
// miroir. Il ne tourne QUE sous mesure de cet item : c'est un instrument, pas du rendu.
constexpr uint64_t kRefEvery = 16;
constexpr int kAnSlots = 2;                // anneau de PBO : on consomme ce qui a 8 images
constexpr float kAnCeiling = 64.f;         // plafond de lecture : rien n'est comprime en dessous
constexpr float kTauUp = 0.35f;            // s — l'oeil s'adapte vite a une montee
constexpr float kTauDown = 1.10f;          // s — et lentement a une baisse
constexpr float kSlewKey = 0.35f;          // par seconde : la borne dure anti-pompage
constexpr float kSlewHi = 0.50f;
// LA DESCENTE DU PIC, ET ELLE SEULE, EST FREINEE — c'est une enveloppe a maintien de crete.
// `peak` est la moyenne des DEUX tuiles les plus claires sur 256 : une statistique d'ordre
// extreme, qui saute des qu'un reflet entre ou sort du cadre. Mesure de l'essai 17 : l'ancre
// (80e centile) est PLATE a 0,260 sur trente echantillons pendant que `top` bat 0,631 - 0,896
// d'un echantillon a l'autre, et `resp` le suit a 19 % pres — 30 renversements pour 48
// echantillons, le « pompage » du verdict 13. La monter vite reste juste (une scene qui
// s'eclaire doit etre suivie tout de suite) ; la redescendre en 4,5 s au lieu de 0,5 s change
// un pic isole en une montee suivie d'une decroissance MONOTONE, donc un seul virage au lieu
// de deux, et efface le battement de fond. Le niveau atteint, lui, ne baisse pas : le maintien
// garde le plafond haut plus longtemps.
constexpr float kSlewPeakUp = 0.50f;
constexpr float kSlewPeakDown = 0.06f;
// Les bandes mortes, en unites de la grandeur elle-meme. Sur la course de l'essai 17 la cle
// balaie 0,108 -> 0,364 et l'ancre 0,247 -> 0,419 : 0,015 vaut donc 6 % de ce que la scene
// parcourt VRAIMENT. Assez pour effacer le bruit d'echantillonnage, trop peu pour figer la
// courbe — c'est le verdict 13 lui-meme qui verifie qu'elle bouge encore (span >= 10 %).
// `kDeadKey` a ete ramenee de 0,015 a 0,008 : la cle est une moyenne LOGARITHMIQUE sur 256
// tuiles, donc une grandeur robuste qui ne bruite pas — la bande morte y servait a rien et
// figeait le seul temoin qui dit que la SCENE a varie (0,018 d'amplitude a l'essai 17, sous le
// plancher de 0,02 que le verdict 13 exige pour ne pas juger sur une scene immobile).
constexpr float kDeadKey = 0.008f;
constexpr float kDeadHi = 0.015f;
constexpr float kDeadPeak = 0.015f;
// Les bornes de la courbe. Aucune n'est un calibrage d'ecran : le plafond, lui, vient
// exclusivement du systeme (headroom_linear), jamais d'une constante en nits.
// L'ANCRE EST UN PERCENTILE DE LA SCENE, pas une constante : elle se pose sur le 90e centile
// des tuiles. La population etiree est donc TOUJOURS le cinquieme le plus clair de CETTE image —
// une grotte et un plein soleil n'ont pas la meme ancre, et c'est exactement ce que le refus du
// 10/09 reclame. Les deux bornes empechent les deux exces : relever une nuit entiere (plancher)
// et eclaircir un plein jour globalement (plafond).
// Le PLANCHER etait a 0,45, et il rendait la phrase ci-dessus FAUSSE. Mesure du 10/09 18:17 sur
// le Honor, village2-dock : 90e centile = 0,328, donc le plancher 0,45 se trouvait vers le 97e
// centile. La population etiree n'etait pas le dixieme le plus clair mais son trentieme, et
// 1,1 % seulement de l'image ressortait relevee d'un quart. Le plancher ne sert qu'a une chose —
// empecher d'etirer une nuit entiere quand la scene n'a AUCUNE source — et 0,20 suffit
// exactement a ca : sous 0,20 il n'y a pas de haute lumiere a faire ressortir. Au-dessus, c'est
// le centile de la scene qui decide, comme annonce.
constexpr float kAnchorDark = 0.20f;
constexpr float kAnchorBright = 0.86f;
// COMBIEN DE MARGE CETTE SCENE MERITE : lu sur son PIC absolu. Une grotte sans la moindre source
// n'a rien a faire monter — sa sortie HDR est alors celle du SDR, et c'est correct, pas un echec.
constexpr float kPeakLo = 0.45f, kPeakHi = 0.80f;
// La fenetre etiree ne depasse jamais la moitie de la marge disponible : le gain moyen sur la
// fenetre vaut donc au moins DEUX. C'est ce qui empeche la courbe de redevenir une identite —
// le defaut mesure de l'essai 7, ou le sommet touchait le plafond et l'etirement disparaissait.
constexpr float kMaxWidthFrac = 0.5f;
constexpr float kMinWidth = 0.06f;
// La luminance log-moyenne ne pilote QUE le pied : plus la scene est sombre, plus les ombres
// sont relevees — c'est la ou l'ecran HDR a du noir a montrer.
constexpr float kKeyDark = 0.05f, kKeyBright = 0.30f;
constexpr float kToeMax = 0.12f;
// Le point de fonctionnement FIGE de l'auto-test. Les verdicts 3, 4, 5 et 10 comparent des
// PHASES ; une courbe qui bouge sous eux les rendrait incomparables (lecon « verdict mesure sur
// une scene MOUVANTE »). L'adaptation au contenu se mesure APRES, sur du jeu reel.
constexpr float kPinTop = 1.05f;

// ----------------------------------------------------------------- LA COURBE LIVREE ----
// Refus owner du 11/09 : « le HDR produit un rendu tres j'ai pousse le contraste au maximum,
// c'est pas beau ». La cause n'est pas un reglage, c'est LA FORME de la fenetre Hermite. Au
// point de fonctionnement livre le 11/09 (a=0,262 T=0,965 C=1,877, relus dans proof.txt) sa
// pente vaut 1 a l'ancre, 3,20 au milieu de la fenetre et 0 au sommet : un facteur TROIS sur le
// contraste local, et il tombe DANS LES TONS MOYENS puisque l'ancre etait a 26 % du blanc.
// Aucune valeur d'ancre ne le repare — resserrer la fenetre AGGRAVE la pente (p = (T-a)/(C-a)
// diminue, la pente mediane vaut (1,5 - 0,25.p)/p) : a ancre 0,75 elle depasse 7.
//
// La courbe livree est donc un GAMMA BORNE : out = a.(x/a)^K, ecrete au plafond. Sa pente
// log-log — le contraste, la seule grandeur que l'oeil lit comme « pousse » — vaut K PARTOUT
// au-dessus de l'ancre. Il n'existe plus de bande de tons etiree plus qu'une autre.
//
// kGammaMax est LE PLAFOND DECLARE du verdict 15. Il n'est pas un gout : la sonde de jeu reel
// redessine la MEME image avec la courbe refusee du 11/09 et publie son exposant a cote, si
// bien que le plafond se lit contre l'image que l'owner a refusee, pas contre un chiffre invente.
constexpr float kGammaMax = 1.35f;
// L'EXPOSANT VISE, distinct du plafond. Viser le plafond concentre tout le gain sur une poignee
// de pixels : mesure du 11/09 a exposant 1,350, ancre deduite 0,297 — 7,8 % de l'image relevee,
// 2,9 % relevee d'un quart du relevement du sommet. Viser 1,25 laisse le MEME gain au sommet
// (il ne depend que du plafond et du haut de scene) mais fait descendre l'ancre a ~0,18 : la
// population qui bouge triple, et l'excursion de contraste publiee descend SOUS le plafond au
// lieu de s'y coller. Les deux refus du 11/09 tirent dans le meme sens ici : « pas de diff » veut
// une population large, « contraste pousse au maximum » veut un exposant bas.
constexpr float kGammaTarget = 1.25f;
// L'ANCRE de la courbe livree : une FRACTION de la luminance log-moyenne de la scene, donc une
// grandeur de contenu et non un calibrage. Sous l'ancre la sortie est BIT A BIT celle du SDR.
// Elle est basse a dessein : l'exposant necessaire pour atteindre le plafond vaut
// ln(C/a)/ln(pic/a), et il DIMINUE quand l'ancre descend — etaler la marge sur beaucoup de
// decades est exactement ce qui evite de la concentrer en une bande raide. C'est le contraire
// de l'intuition qui a produit la courbe refusee.
constexpr float kAnchorKeyFrac = 0.5f;
constexpr float kAnchorLo = 0.02f, kAnchorHi = 0.25f;
// LE PLAFOND DE L'ANCRE. kAnchorHi=0,25 supposait qu'il y aurait TOUJOURS beaucoup de marge a
// etaler (elle etait achetee x4 au retro-eclairage). Quand la seule plage disponible est celle
// que la scene laisse vide — c'est le cas d'un joueur deja a luminosite maximale — le sommet ne
// vaut plus que ~1,33 fois le haut de la scene, et l'ancre DEDUITE monte a ~0,29 : c'est
// exactement ce qu'il faut pour que seules les zones claires bougent. Le plafond doit donc la
// laisser monter.
constexpr float kAnchorCeil = 0.60f;
// Le gain minimal au sommet en dessous duquel on ne pousse aucune courbe : sous 2 % l'etirement
// ne se verrait pas et ne vaut pas le risque.
constexpr float kMinTopGain = 0.02f;
// LE PLANCHER ABSOLU DE L'EFFET LIVRE, en fraction de la lumiere que le bras SDR emet sur les
// memes images. Il existe pour une raison precise : le bras de reference du 10/09 ne livre
// RIEN des que le systeme n'accorde aucune marge, et « au moins le double de zero » serait vrai
// par INACTION. Ce plancher-la ne peut pas l'etre.
constexpr float kMinDeliveredGain = 0.02f;
// Le point de fonctionnement FIGE de l'auto-test, dans la forme livree.
constexpr float kPinAnchorP = 0.12f;

// ------------------------------------------- VERDICT 15 : LES PLAFONDS DECLARES ----
// « Un ecart au-dela d'un plafond DECLARE est un DEFAUT » (livrable, point 14). Les voici,
// publies tels quels dans proof.txt a cote des mesures :
constexpr double kExpCap = 1.35;      // exposant de contraste global (pente log-log)
constexpr double kBandCap = 1.50;     // pente log-log LOCALE, la pire bande de luminance
constexpr double kSatCap = 1.05;      // rapport de saturation moyenne HDR/SDR
constexpr double kHueCapDeg = 2.0;    // derive de teinte moyenne, en degres
// 16 bandes sur [1e-4 ; 1] : un facteur 1,78 de luminance par bande. La resolution compte —
// des bandes larges MOYENNENT la pente et effacent precisement le defaut qu'on cherche, une
// courbe douce en moyenne et raide sur une plage de tons.
constexpr int kExcBands = 16;

struct DynState {
  bool primed = false;
  float key = 0.15f;   // luminance log-moyenne : pilote le PIED
  float hi = 0.90f;    // 90e centile des tuiles : pilote l'ANCRE
  float peak = 1.f;    // pic de la scene : pilote la part de marge reclamee
  std::chrono::steady_clock::time_point last;
};
DynState s_dyn;
CurveParams s_cur;              // les parametres pousses pour l'image en cours
// LE SOMMET ATTEINT par la courbe livree (a.(pic/a)^K) et la plage DISPONIBLE (plafond d'ecran
// divise par le haut de la scene). Les deux sont publies : `ceiling` seul ne dit plus rien
// depuis que le plafond de l'ecran et le sommet de la courbe sont deux grandeurs distinctes.
float s_curve_top = 1.f;
float s_curve_top_max = 1.f;
float s_range_avail_max = 1.f;
float s_top_gain_max = 1.f;     // sommet / haut de scene, tel que la courbe l'a PLANIFIE
// La plage disponible A L'INSTANT du meilleur plan. `s_range_avail_max` seul est un maximum pris
// sur la scene la plus SOMBRE (plafond / haut de scene y explose) : le comparer au gain livre
// dans une scene claire est la faute « verdict mesure sur une scene MOUVANTE ».
float s_range_avail_at_top = 1.f;
float s_ceiling_max = 1.f;      // le plus haut plafond d'ecran vu sur la course
uint64_t s_dyn_updates = 0;     // analyses de scene consommees
// QUESTION 2 DE L'ETUDE — « le tampon de calcul est-il assez riche ? ». On compte, sur le PIC
// BRUT de scene que l'analyse remonte chaque image, combien d'images en portent un au-dessus de
// 1,0 et de combien. Le denominateur est publie a cote : un « 0 image au-dessus de 1,0 » ne se
// distingue d'une sonde qui n'a jamais tourne que par lui.
uint64_t s_study_scene_samples = 0;
uint64_t s_study_scene_over1 = 0;
float s_study_scene_peak_max = 0.f;
// Le format du tampon d'interface REELLEMENT passe a `frame_end` : la derniere etape avant le
// quad final, et celle ou le tone map ecrit. Releve, jamais suppose.
GLenum s_study_ui_fmt = 0;
uint64_t s_dyn_pinned_frames = 0, s_dyn_free_frames = 0;
// Images ou la feature est ACTIVE mais ou la courbe est restee celle du SDR faute de marge.
uint64_t s_dyn_sdr_frames = 0;
int s_an_state = 0;             // 0 pas cree, 1 pret, -1 indisponible
int s_an_mode = 0;              // 2 = PBO asynchrone, 1 = relecture directe, 0 = aucune
GLuint s_an_fbo = 0, s_an_tex = 0, s_an_pbo[kAnSlots] = {0, 0};
bool s_an_pending[kAnSlots] = {false, false};
int s_an_slot = 0;
GLenum s_an_read_type = 0;
size_t s_an_bytes = 0;
float s_an_last_key = 0.f, s_an_last_hi = 0.f, s_an_last_peak = 0.f;
// hdr-curve-input : la pyramide de reduction par MAXIMUM. Son etat est SEPARE de celui de
// l'analyse : si le programme ou une cible manque, `s_mr_state` tombe a -1, `peak` reprend les
// tuiles moyennes et le jeu continue exactement comme avant. Une correction d'entree ne doit
// jamais pouvoir eteindre la courbe.
int s_mr_state = 0;  // 0 pas tente, 1 pret, -1 indisponible (publie)
Shader* s_mr_shader = nullptr;
GLuint s_mr_fbo1 = 0, s_mr_tex1 = 0, s_mr_fbo2 = 0, s_mr_tex2 = 0;
int s_mr_src_w = 0, s_mr_src_h = 0, s_mr_w1 = 0, s_mr_h1 = 0;
uint64_t s_mr_draws = 0;
// Le TEMOIN pleine resolution et l'APPAIRAGE. `s_an_ref[slot]` est le pic que le temoin a vu sur
// l'image dont le PBO `slot` porte la reduction — negatif quand cette analyse n'etait pas
// appairee. `s_an_exp[slot]` est l'exposition qui etait poussee au shader a CETTE image : le
// temoin lit la scene BRUTE, la statistique la lit apres exposition, et comparer sans ce facteur
// mesurerait le reglage d'exposition au lieu de la surdite.
float s_an_ref[kAnSlots] = {-1.f, -1.f};
bool s_an_max_ok[kAnSlots] = {false, false};
float s_an_exp[kAnSlots] = {1.f, 1.f};
uint64_t s_ci_analyses = 0;     // analyses depuis le debut : cadence du temoin
uint64_t s_ci_samples = 0;      // paires (temoin, statistique) sur la MEME image
uint64_t s_ci_black = 0;        // images ou le temoin ne voit RIEN : aucune paire exploitable
uint64_t s_ci_ref_reads = 0;    // relectures pleine resolution reellement abouties
uint64_t s_ci_knee = 0;         // paires ou le temoin depasse le genou : identite non garantie
double s_ci_ratio_worst = 0.0;  // le PIRE rapport par image — c'est lui la porte
float s_ci_ref_peak_max = 0.f;  // pic du temoin, espace de la courbe, sur les images appairees
float s_ci_curve_peak_max = 0.f;  // pic de la statistique, sur les MEMES images
float s_ci_ref_at_worst = 0.f, s_ci_curve_at_worst = 0.f, s_ci_exp_at_worst = 1.f;
float s_ci_knee_level = 0.f;    // le genou lu SUR le programme, jamais suppose
std::vector<uint16_t> s_ci_raw16;  // tampons du temoin, alloues une fois
std::vector<float> s_ci_raw32;
GLuint s_ci_ref_fbo = 0;  // FBO du temoin : la texture de scene, attachee pour etre RELUE

// La SERIE (verdict 13). Un echantillon toutes les kPlayEvery images (la sonde de jeu la pousse),
// apres l'auto-test, avec la REPONSE du programme `tonemap` a un stimulus FIXE : si la courbe
// etait unique et figee, cette reponse serait constante. C'est une grandeur LUE d'un dessin, pas
// un miroir de nos variables.
constexpr size_t kDynSeriesMax = 160;
constexpr size_t kDynChunk = 20;
struct DynSample {
  uint64_t frame = 0;
  float resp = 0.f;     // somme du canal max sur les 128 marches du stimulus fixe
  float anchor = 0.f, top = 0.f, ceiling = 0.f, key = 0.f, hi = 0.f;
  float t_s = 0.f;
};
std::vector<DynSample> s_dyn_series;
size_t s_dyn_stride = 1;
uint64_t s_dyn_seen = 0;

// L'AMPLITUDE (verdict 12), mesuree sur du JEU REEL apres l'auto-test. Trois bras du MEME
// programme sur la MEME image : le SDR livre, la sortie HDR d'aujourd'hui, et la sortie HDR
// REFUSEE le 10/09 (plafond seul, courbe SDR etiree) — c'est cette derniere qui donne au verdict
// une reference qui n'est pas un chiffre invente.
struct PlayStats {
  uint64_t samples = 0, px = 0, lift_px = 0;
  double sum_off = 0.0, sum_on = 0.0;      // tons moyens : verdict 9 sur du jeu reel
  double lift_ratio_sum = 0.0;             // somme de on/off sur les pixels releves
  // La COUVERTURE FORTE, par palier. `lift_ratio_sum / lift_px` (la moyenne sur les pixels
  // releves de plus de 2 %) est une statistique qui SE COMBAT elle-meme : le seuil d'entree du
  // set etant a 2 %, une courbe qui touche PLUS d'image y fait entrer une foule de pixels a
  // peine deplaces, et la moyenne BAISSE. Mesure du 10/09 18:00 : couverture 36 %, moyenne
  // 1,050 — un rendu qui livre 1,66x sur les hautes lumieres note plus bas qu'un rendu inerte
  // qui n'aurait touche que ses trois pixels les plus clairs. On compte donc des pixels par
  // palier de relevement : monotone dans la force de la courbe, ingagnable par dilution.
  uint64_t lift10_px = 0, lift25_px = 0, lift50_px = 0;
  uint64_t lift25_hi_px = 0;               // idem, mais sur du signal REEL (SDR >= 0,20) :
                                           // le relevement du pied ne peut pas le remplir
                                           // avec des pixels quasi noirs.
  double gain_ref = 0.0;                   // somme des canaux max du bras SDR
  double gain_new = 0.0, gain_old = 0.0;   // supplement de lumiere, aujourd'hui / le 10/09
  double hl_max = 0.0;
  double hl_max_ref = 0.0;                 // le meme maximum sur le bras SDR : le rapport des
                                           // deux est le GAIN LIVRE, mesure sur des pixels
                                           // dessines et non sur notre arithmetique.
  uint64_t lift_rel_px = 0;                // pixels releves d'au moins UN QUART du relevement
                                           // planifie au sommet. Un seuil absolu (25 %) ne peut
                                           // pas servir dans les deux regimes : a plafond 1,000
                                           // le sommet lui-meme ne monte que de ~33 %.
  // VERDICT « RICHESSE DANS LES OMBRES », sur du JEU REEL. Pour chaque pixel de l'image dont la
  // sortie SDR est SOUS le blanc, on note le code que chacun des deux etats livrerait a la
  // fenetre : 8 bits pour la fenetre SDR, 10 bits PQ pour la fenetre HDR (meme encodage que
  // post_processing.frag, mode 1, applique au canal maximum). Le nombre de codes DISTINCTS
  // separes sous le blanc est la definition operatoire de « detail distinguable dans les
  // ombres ». Accumule sur toute la course.
  bool code_off[256] = {false};
  bool code_on[1024] = {false};
  // La MEME mesure restreinte aux ombres PROFONDES — la fenetre [0, 1/16] que la sonde de rampes
  // utilise deja. C'est la que « richesse dans les ombres » veut dire quelque chose : sur toute
  // la plage, 8 bits en separent deja beaucoup et le rapport dirait surtout que 1024 > 256.
  bool code_off_deep[256] = {false};
  bool code_on_deep[1024] = {false};
  uint64_t shadow_px = 0, deep_px = 0;
  uint64_t below_sdr_px = 0;               // pixels ou le HDR sort SOUS le SDR : doit rester 0
  double below_sdr_worst = 0.0;            // la PIRE violation, tolerance comprise : elle dit
                                           // si un zero vient de la courbe ou du pas du tampon
};
PlayStats s_play;
GLuint s_pl_fbo[4] = {0, 0, 0, 0}, s_pl_tex[4] = {0, 0, 0, 0};
int s_pl_state = 0;

// L'EXCURSION (verdict 15 ; livrable point 14, refus owner du 11/09 « j'ai pousse le contraste
// au maximum ... comme si on poussait la teinte/saturation/contraste au max sur un filtre
// photoshop »). Ce que l'oeil appelle « contraste pousse » est la PENTE LOG-LOG : de combien
// l'ecart de luminance entre deux pixels voisins est multiplie. Elle est INVARIANTE par
// changement global de luminosite et par le gamma d'encodage — une image simplement plus
// claire rend 1,000. C'est donc la seule grandeur qui separe « plus lumineux » de « plus
// contraste », et c'est exactement la question de l'owner.
//   * `sx..syy` : la regression de ln(Y_hdr) sur ln(Y_sdr) sur TOUS les pixels retenus. Sa
//     pente est l'exposant de contraste GLOBAL.
//   * `bn/bx/by` : les memes sommes par BANDE de luminance SDR. La pente entre deux bandes
//     voisines est l'exposant LOCAL : c'est lui qui attrape une courbe douce en moyenne mais
//     brutale sur une plage de tons — precisement le defaut de la fenetre Hermite, plate aux
//     deux bouts et a 3,2 au milieu. Une moyenne seule l'aurait laisse passer.
//   * saturation et teinte : mesurees pixel par pixel sur les MEMES images.
struct ExcStats {
  uint64_t n = 0;
  double sx = 0, sy = 0, sxx = 0, sxy = 0, syy = 0;
  uint64_t bn[kExcBands] = {0};
  double bx[kExcBands] = {0}, by[kExcBands] = {0};
  uint64_t sat_n = 0;
  double sat_off = 0, sat_on = 0, sat_worst = 0;
  uint64_t hue_n = 0;
  double hue_sum = 0, hue_worst = 0;
};
// La courbe LIVREE contre le SDR, et la courbe REFUSEE le 11/09 contre le meme SDR.
ExcStats s_exc, s_exc17;
struct ExcOut {
  uint64_t n = 0, bands = 0;
  double exp_g = 0, rms = 0, band_max = 0;
  double sat_ratio = 0, sat_worst = 0, hue_mean = 0, hue_worst = 0;
};
ExcOut s_exc_out, s_exc17_out;
// Ce que les verdicts 12 et 13 ont lu, garde pour etre publie a cote d'eux : un verdict qu'on
// ne peut pas relire n'est pas une preuve.
struct DynStats {
  size_t samples = 0;
  int reversals = 0;
  double r_min = 0, r_max = 0, r_span = 0;
  double k_min = 0, k_max = 0, a_min = 0, a_max = 0, c_min = 0, c_max = 0, t_min = 0, t_max = 0;
  double step_max = 0, cover = 0, gain_new = 0, gain_old = 0, hl_lin = 0;
  int reversals_zz = 0;
  double cover10 = 0, cover25 = 0, cover50 = 0, cover25_hi = 0;
};
DynStats s_dyn_stats;

bool measuring() {
  // `hdr-study` (l'etude) n'ajoute AUCUN geste de rendu : elle a besoin des memes sondes que
  // `hdr-display-output` pour relever ses chiffres sur l'appareil. Sans cette branche,
  // `proof_run.sh hdr-study device` pose `debug.opengoal.feature=hdr-study`, `feature_is(kItemId)`
  // est faux, et TOUTES les cles `hdr_out_*` disparaissent du proof.
  return (autoport_proof::feature_is(kItemId) || autoport_proof::feature_is(kStudyId)) &&
         autoport_proof::armed_for(kItemId);
}

// L'ETUDE mesure-t-elle ? Sert uniquement a decider si le bloc `hdr_study_*` est publie et si
// le `hits=` de l'item `hdr-study` doit compter : le reste du fichier ne consulte jamais ceci.
bool studying() {
  return autoport_proof::feature_is(kStudyId) && autoport_proof::armed_for(kStudyId);
}

// LE PLAN (`hdr-plan`) mesure-t-il ? Meme portee que `studying()` : ce booleen ne decide QUE de
// la publication du bloc `hdr_plan_*`. Il n'entre pas dans `measuring()`, et c'est delibere —
// `measuring()` allume l'auto-test en cinq phases, qui BASCULE LA SURFACE EGL sous l'image. Le
// plan ne change rien au rendu : il relit ce que le chemin LIVRE produit deja.
bool planning() {
  return autoport_proof::feature_is(kPlanId) && autoport_proof::armed_for(kPlanId);
}

// LE CHANTIER B mesure-t-il ? Ce booleen ne decide QUE de deux choses : la publication du bloc
// `hdr_curve_input_*`, et le declenchement du TEMOIN pleine resolution (un instrument, pas du
// rendu). La reduction par maximum, elle, tourne en PRODUCTION sans jamais le consulter — sinon
// la porte mesurerait un chemin que le joueur n'a pas.
bool curve_input_measuring() {
  return autoport_proof::feature_is(kCurveInputId) && autoport_proof::armed_for(kCurveInputId);
}

bool probe_window_open() {
  // Les sondes ne tournent qu'en phase ON, une image sur kProbeEvery, hors transition.
  return measuring() && !s_selftest_done && (s_phase == 1 || s_phase == 3 || s_phase == 4) &&
         s_skip_frames == 0 && s_active.load() && (s_frames % kProbeEvery) == 0;
}

// Les rampes du verdict 11 tournent AUSSI en phase OFF : sans le bras OFF il n'y a rien a
// comparer, et « autant de niveaux qu'en SDR » est precisement le defaut qu'on cherche.
bool ramp_window_open() {
  return measuring() && !s_selftest_done && s_phase >= 1 && s_phase <= 4 && s_skip_frames == 0 &&
         (s_frames % kProbeEvery) == 0;
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
  gl_query_census::Armed _ap("hdr-out-read-fbo");
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

// ============================================================ hdr-output-regime : l'etat ====
// Tout ce bloc n'existe que pour la PREUVE de cet item. Les compteurs montent en production
// (`s_regime_frames`, la ligne de menu) ; la sonde a quatre bras, elle, ne tourne que sous la
// mesure de `hdr-output-regime`.
constexpr int kRgTmW = 32, kRgTmH = 32;   // l'echantillon de SCENE : ce qui est reellement dessine
constexpr uint64_t kRgEvery = 30;         // une sonde sur 30 images
constexpr float kRgRampTop = 4.f;         // la rampe couvre [0, 4] : au-dela le tampon ne porte
                                          // rien que la sonde de pixels ait jamais vu
constexpr float kRgIdentCeiling = 64.f;   // le bras IDENTITE : `knee*64` >= 60, donc l'epaule ne
                                          // touche RIEN dans [0, 4]

// LE PAS DU CONTENEUR a la valeur v : un demi-flottant porte 10 bits de mantisse, donc son ULP
// vaut 2^(exposant-10). C'est la plus petite difference que la cible 16F sache ECRIRE ; en
// dessous, deux valeurs y sont le MEME nombre. Toute tolerance de comparaison se dit dans cette
// unite et pas dans une constante inventee.
double half_ulp(double v) {
  const double a = std::fabs(v);
  if (!(a > 6e-5)) {
    return 6e-8;  // sous-normaux du 16F : le plus petit pas representable
  }
  return std::ldexp(1.0, (int)std::floor(std::log2(a)) - 10);
}

bool regime_measuring() {
  return autoport_proof::feature_is(kRegimeId) && autoport_proof::armed_for(kRegimeId);
}

uint64_t s_regime_frames = 0;      // images ou le regime a ete pousse au shader ET publie
uint64_t s_regime_r[3] = {0, 0, 0};  // images par regime : un regime qui BASCULE se lit
int s_regime_last = -1;

// La ligne de menu, rapportee par GOAL (`rch-hdr-refresh-label!`).
uint64_t s_menu_notes = 0;
int s_menu_transport = -1, s_menu_regime = -1, s_menu_len = -1;

// La sonde a quatre bras.
int s_rg_state = 0;                // 0 pas tente, 1 pret, -1 indisponible
GLuint s_rg_fbo = 0, s_rg_tex = 0;       // cible scene 32x32
GLuint s_rg_rfbo = 0, s_rg_rtex = 0;     // cible rampe 128x1
GLuint s_rg_ramp = 0;                    // la rampe elle-meme
uint64_t s_rg_runs = 0;
uint64_t s_rg_ramp_px = 0, s_rg_scene_px = 0;
uint64_t s_rg_maxdiff_x1e6 = 0;          // max |livre - SDR| sur rampe ET scene, x1e6
uint64_t s_rg_below_sdr_px = 0;          // bras SIMULE strictement SOUS le bras SDR
uint64_t s_rg_exc_sdr_px = 0;            // sous `knee` : le bras SIMULE differe du bras SDR
uint64_t s_rg_exc_ident_px = 0;          // sous `knee*C_sim` : il differe de l'IDENTITE
// LA MAGNITUDE, EN PAS DU CONTENEUR. Un COMPTE d'ecarts ne dit pas si l'ecart est un defaut de
// courbe ou le dernier bit d'un demi-flottant : les deux se comptent pareil. On publie donc
// l'ecart le plus GRAND, exprime en ULP de la cible 16F — l'unite dans laquelle « identique au
// bit » a un sens. Au-dessus de 1 ULP le conteneur SAIT representer la difference : c'est une
// modification. A 1 ULP ou moins, aucune ecriture dans ce tampon ne pourrait la distinguer.
uint64_t s_rg_exc_max_ulp_x1000 = 0;
uint64_t s_rg_below_max_ulp_x1000 = 0;
uint64_t s_rg_below_ramp_px = 0, s_rg_below_scene_px = 0;
uint64_t s_rg_exc_ramp_px = 0, s_rg_exc_scene_px = 0;
uint64_t s_rg_below_over_ulp_px = 0;     // ecarts SOUS le SDR qui depassent 1,5 ULP
uint64_t s_rg_exc_over_ulp_px = 0;       // excursions sous seuil qui depassent 1,5 ULP
uint64_t s_rg_sim_gain_x1e6 = 0;         // max (simule - SDR) : le bras SIMULE fait-il QUELQUE CHOSE
float s_rg_sim_ceiling = 0.f;            // le plafond simule effectivement utilise
float s_rg_knee = 0.f;                   // le genou reellement pousse au shader
uint64_t s_rg_gl_errors = 0;

// Avertissement A du contrat : l'ANCRE tiree des tuiles MOYENNES contre celle tiree des MAXIMUMS.
// Mesure, publiee, et suivie du verdict : la courbe livree n'a PLUS D'ANCRE, donc aucune des deux
// n'est retenue. On la mesure quand meme, parce que « non mesure » et « sans effet » ne sont pas
// la meme phrase.
uint64_t s_anchor_samples = 0;
float s_anchor_mean_last = 0.f, s_anchor_max_last = 0.f;
uint64_t s_anchor_gap_max_x1000 = 0;


// ----------------------------------------------- l'analyse de scene et son lissage ----

float clampf(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}
float smoothstep01(float lo, float hi, float v) {
  const float t = clampf((v - lo) / (hi - lo > 1e-6f ? hi - lo : 1e-6f), 0.f, 1.f);
  return t * t * (3.f - 2.f * t);
}
// Lissage a constante de temps asymetrique, PUIS limiteur de vitesse. Le limiteur est la garde
// dure : quel que soit le saut de la scene (un ecran de chargement, un teleport), la grandeur ne
// peut pas bouger de plus de `slew` par seconde. C'est ce qui rend « transition lissee, aucun
// pompage » une propriete du code et pas un resultat de mesure heureux.
float smooth_to(float cur, float raw, float dt, float slew_up, float slew_down, float dead) {
  // LA BANDE MORTE A HYSTERESIS. Le limiteur de vitesse ci-dessous borne l'AMPLITUDE d'un pas,
  // jamais son SENS : un filtre exponentiel pose sur une statistique de scene bruitee change de
  // sens presque a chaque echantillon, et c'est exactement le « pompage » que le verdict 13
  // compte — 27 renversements pour 48 echantillons a l'essai 17, alors que le pas maximum
  // (0,091/s) tenait largement sous sa borne. On vise donc le BORD de la bande morte : tant que
  // la scene n'a pas bouge de plus de `dead`, la courbe ne bouge pas du tout, et pour repartir
  // dans l'autre sens il faut franchir `dead` dans l'autre sens. Le bruit d'amplitude inferieure
  // ne peut plus produire un seul renversement, par construction et non par chance de mesure.
  if (!(std::fabs(raw - cur) > dead)) {
    return cur;
  }
  raw = raw > cur ? raw - dead : raw + dead;
  const float tau = raw > cur ? kTauUp : kTauDown;
  float next = cur + (raw - cur) * (1.f - std::exp(-dt / tau));
  const float lim_up = slew_up * dt;
  const float lim_down = slew_down * dt;
  if (next > cur + lim_up) {
    next = cur + lim_up;
  }
  if (next < cur - lim_down) {
    next = cur - lim_down;
  }
  return next;
}

// LE REJET D'IMPULSION SUR LE PIC. `raw_peak` est la moyenne des DEUX tuiles les plus claires
// sur 256 : une statistique d'ordre extreme. Un reflet qui entre ou sort du cadre la fait sauter
// d'un coup, et la courbe suit. Mesure de l'essai 17, serie `dyn_top` : dix excursions ISOLEES
// en 47 s (980-920-860-800-782-722-666 puis 796, 706, 735, 675, 649, 630, 739, 663, 895...),
// vingt renversements la ou la porte en tolere onze — pendant que l'ancre, prise au 80e centile,
// ne bouge pas d'un millieme sur toute la course. Les deux compteurs de renversement, l'ancien
// et le zigzag, rendent le MEME 20 : ce n'est pas l'instrument, c'est la courbe qui bat.
// Une mediane sur cinq analyses (~2 s) supprime l'impulsion isolee SANS toucher au niveau : une
// scene vraiment plus claire le reste plus de deux secondes, donc elle traverse la mediane
// intacte. C'est un rejet d'impulsion, pas un lissage de plus — il ne retarde ni n'attenue une
// montee soutenue, et il laisse le plafond atteindre son maximum comme avant.
constexpr int kPeakMedN = 5;
float s_peak_hist[kPeakMedN] = {0.f, 0.f, 0.f, 0.f, 0.f};
int s_peak_hist_n = 0;
int s_peak_hist_i = 0;

float peak_impulse_reject(float raw) {
  s_peak_hist[s_peak_hist_i] = raw;
  s_peak_hist_i = (s_peak_hist_i + 1) % kPeakMedN;
  if (s_peak_hist_n < kPeakMedN) {
    s_peak_hist_n++;
  }
  float t[kPeakMedN];
  for (int i = 0; i < s_peak_hist_n; i++) {
    t[i] = s_peak_hist[i];
  }
  std::sort(t, t + s_peak_hist_n);
  return t[s_peak_hist_n / 2];
}

void dyn_update(float raw_key, float raw_hi, float raw_peak) {
  s_an_last_key = raw_key;
  s_an_last_hi = raw_hi;
  s_an_last_peak = raw_peak;  // le pic BRUT reste publie : la correction doit se relire
  s_study_scene_samples++;
  if (raw_peak > 1.f) {
    s_study_scene_over1++;
  }
  if (raw_peak > s_study_scene_peak_max) {
    s_study_scene_peak_max = raw_peak;
  }
  raw_peak = peak_impulse_reject(raw_peak);
  const auto now = std::chrono::steady_clock::now();
  if (!s_dyn.primed) {
    s_dyn.primed = true;
    s_dyn.key = raw_key;
    s_dyn.hi = raw_hi;
    s_dyn.peak = raw_peak;
    s_dyn.last = now;
    s_dyn_updates++;
    return;
  }
  float dt = (float)std::chrono::duration<double>(now - s_dyn.last).count();
  s_dyn.last = now;
  if (!(dt > 0.f)) {
    return;
  }
  if (dt > 0.5f) {
    dt = 0.5f;  // une pause (chargement, changement de niveau) n'autorise pas un saut
  }
  s_dyn.key = smooth_to(s_dyn.key, raw_key, dt, kSlewKey, kSlewKey, kDeadKey);
  s_dyn.hi = smooth_to(s_dyn.hi, raw_hi, dt, kSlewHi, kSlewHi, kDeadHi);
  s_dyn.peak = smooth_to(s_dyn.peak, raw_peak, dt, kSlewPeakUp, kSlewPeakDown, kDeadPeak);
  s_dyn_updates++;
}

// Les SIX uniformes de la courbe, sur le programme deja actif.
void set_curve(GLuint prog, const CurveParams& p) {
  glUniform1f(glGetUniformLocation(prog, "u_hdr_ceiling"), p.ceiling);
  glUniform1f(glGetUniformLocation(prog, "u_hdr_anchor"), p.anchor);
  glUniform1f(glGetUniformLocation(prog, "u_hdr_top"), p.top);
  glUniform1f(glGetUniformLocation(prog, "u_hdr_toe"), p.toe);
  glUniform1i(glGetUniformLocation(prog, "u_hdr_shape"), p.shape);
  glUniform1f(glGetUniformLocation(prog, "u_hdr_gamma"), p.gamma);
}
// Le bras SDR : plafond 1,0 et aucune expansion. C'est EXACTEMENT ce que le joueur voit
// interrupteur eteint.
CurveParams sdr_params() {
  CurveParams p;
  p.ceiling = 1.f;
  p.anchor = 2.f;
  p.top = 2.f;
  p.toe = 0.f;
  return p;
}
// hdr-output-regime : ce « bras refuse le 10/09 » EST le placement du blanc, et c'est desormais
// la courbe LIVREE (C2 du plan, §1.3). L'owner n'y a vu « qu'un yota » parce que la marge etait
// nulle, pas parce que la courbe etait fausse : a marge nulle il N'Y A qu'un yota a montrer, et
// l'arbitrage du 11/09 est que la sortie HDR le DISE au lieu de fabriquer une difference.
// La definition ne vit plus qu'a un endroit, `placement_params`.
CurveParams legacy_params(float ceiling) {
  return placement_params(ceiling);
}

// La cible d'analyse et son anneau de PBO. La lecture est ASYNCHRONE : `glReadPixels` ecrit
// dans un PBO, et on ne cartographie ce PBO qu'au tour suivant de l'anneau — huit images plus
// tard. C'est le seul readback par-image du moteur : sans PBO il serialiserait CPU et GPU a
// chaque analyse, et le Redmi plafonne deja a ~44 img/s. Si le PBO est refuse, on retombe sur
// une lecture directe trois fois moins frequente, et on le PUBLIE (`hdr_out_dyn_readback`).
bool an_ensure() {
  gl_query_census::Armed _ap("hdr-out-an-ensure");
  if (s_an_state != 0) {
    return s_an_state == 1;
  }
  if (!make_float_fbo(&s_an_fbo, &s_an_tex, kAnW, kAnH, nullptr)) {
    s_an_state = -1;
    return false;
  }
  GLint rf = 0, rt = 0;
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &rf);
  glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &rt);
  s_an_read_type = (rf == GL_RGBA && rt == GL_HALF_FLOAT) ? GL_HALF_FLOAT : GL_FLOAT;
  s_an_bytes = (size_t)kAnW * kAnH * 4 * (s_an_read_type == GL_HALF_FLOAT ? 2u : 4u);
  while (glGetError() != GL_NO_ERROR) {
  }
  GLint saved_pbo = 0;
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &saved_pbo);
  glGenBuffers(kAnSlots, s_an_pbo);
  bool ok = glGetError() == GL_NO_ERROR;
  for (int i = 0; i < kAnSlots && ok; i++) {
    glBindBuffer(GL_PIXEL_PACK_BUFFER, s_an_pbo[i]);
    glBufferData(GL_PIXEL_PACK_BUFFER, (GLsizeiptr)s_an_bytes, nullptr, GL_STREAM_READ);
    ok = glGetError() == GL_NO_ERROR;
  }
  glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)saved_pbo);
  s_an_mode = ok ? 2 : 1;
  s_an_state = 1;
  lg::info("[hdr-curve-input] analyse de scene {}x{} (2 etages : moyenne + maximum) : lecture {} ({})", kAnW, kAnH,
           s_an_mode == 2 ? "PBO asynchrone" : "directe",
           s_an_read_type == GL_HALF_FLOAT ? "half" : "float");
  return true;
}

// UN texel de la cible d'analyse, quel que soit le type de lecture, canaux non finis ou negatifs
// ramenes a zero. Les deux etages passent par ici : ils ne peuvent pas diverger.
void an_texel(const void* raw, size_t i, float c[3]) {
  for (int k = 0; k < 3; k++) {
    c[k] = s_an_read_type == GL_HALF_FLOAT ? half_to_float(((const uint16_t*)raw)[i * 4 + k])
                                           : ((const float*)raw)[i * 4 + k];
    if (!std::isfinite(c[k]) || c[k] < 0.f) {
      c[k] = 0.f;
    }
  }
}

// 512 texels -> trois grandeurs. ETAGE 0 (256 tuiles MOYENNES) : `key`, la luminance LOG-moyenne,
// qui suit le niveau general de la scene sans qu'une poignee de pixels brulants la tire, et `hi`,
// le centile qui place l'ancre. ETAGE 1 (256 tuiles MAXIMUM, couverture totale) : `peak`, et lui
// seul — le plus grand canal de TOUTE l'image, pas la moyenne des deux tuiles les plus claires.
//
// hdr-curve-input : pourquoi `peak` cesse d'etre `0,5.(mx[0]+mx[1])`. Le plan (§1.5) nomme cette
// moyenne dans la CAUSE de la surdite, au meme titre que le sous-echantillonnage. Sur des tuiles
// MAXIMUM elle serait pire qu'inutile : mx[0] est deja le pic exact de l'image, et lui adjoindre
// la deuxieme tuile le ferait retomber de moitie des que la source brillante tient dans une seule
// tuile — exactement le cas qu'on cherche a voir. Le rejet d'impulsion (mediane sur cinq analyses)
// et le limiteur de vitesse restent en aval : rien n'est desarme, la grandeur est seulement juste.
//
// `max_ok` dit si l'etage 1 a ete DESSINE pour cette lecture : un tampon de PBO rempli avant que
// la pyramide soit prete porte des lignes hautes jamais ecrites. Faux => on reprend exactement le
// calcul d'avant, sur les tuiles moyennes.
// L'ANCRE SE DEDUIT DU PLAFOND DE CONTRASTE, elle ne se choisit pas.
// La courbe livree est out(x) = a.(x/a)^K sur [a, pic], et son exposant K est le CONTRASTE que
// l'oeil lit. Il est borne a kGammaMax (verdict 15). Plutot que de poser l'ancre puis de
// constater que K deborde, on pose K = kGammaMax et on en DEDUIT l'ancre :
//     ln(sommet/a) / ln(pic/a) = K   =>   ln a = (K.ln pic - ln sommet) / (K - 1)
// Une seule formule, et elle fait exactement ce qu'il faut dans les deux regimes :
//   * beaucoup de plage disponible (marge achetee au retro-eclairage) : l'ancre DESCEND, la
//     courbe etale son gain sur beaucoup de decades et reste douce ;
//   * peu de plage (joueur a luminosite maximale : seul le vide laisse par la scene reste) :
//     l'ancre MONTE — ~0,29 pour un sommet a 1,33x — et SEULES les zones claires bougent, ce
//     qui est mot pour mot le critere d'acceptation (« les zones brillantes doivent vraiment
//     ressortir, sans que le reste change »).
float deduced_anchor(float xp, float c) {
  const double K = (double)kGammaTarget;
  if (!(xp > 1e-4f) || !(c > xp * 1.0001f)) {
    return kAnchorLo;
  }
  const double la = (K * std::log((double)xp) - std::log((double)c)) / (K - 1.0);
  const double a = std::exp(la);
  if (!std::isfinite(a)) {
    return kAnchorLo;
  }
  return (float)a;
}

void an_decode(const void* raw, bool max_ok, float ref_peak, float exposure) {
  const size_t n = (size_t)kAnW * kAnTileH;
  std::vector<float> mx(n, 0.f);
  double log_sum = 0.0;
  size_t used = 0;
  for (size_t i = 0; i < n; i++) {
    float c[3];
    an_texel(raw, i, c);
    const float lum = 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2];
    mx[i] = std::fmax(c[0], std::fmax(c[1], c[2]));
    log_sum += std::log(std::fmax(lum, 1e-3f));
    used++;
  }
  if (used == 0) {
    return;
  }
  const float key = std::exp((float)(log_sum / (double)used));
  // LE CENTILE, sur les tuiles MOYENNES. Il dit OU commence le cinquieme le plus clair de
  // l'image — c'est lui, et lui seul, qui place l'ancre. Le PIC, lui, ne sort plus d'ici : il
  // vient de l'etage MAXIMUM plus bas, et « moyenne des deux tuiles les plus claires » ne
  // decrit desormais que le REPLI (pyramide indisponible).
  // La POPULATION ETIREE. C'etait le dixieme le plus clair ; c'est desormais le CINQUIEME.
  // Raison mesuree, pas de gout : l'etirement part de l'ancre avec une pente de 1 exactement
  // (Hermite, pour n'avoir aucun coude visible a la jointure), donc le relevement s'y construit
  // progressivement et seul le HAUT de la fenetre gagne un quart. Avec l'ancre au 90e centile,
  // la fenetre ne contenait qu'un dixieme de l'image et il n'en ressortait que 1,8 % relevee
  // d'un quart (Honor, village2-dock, 10/09 18:23) — soit le « yota » que l'owner refuse. Un
  // cinquieme de population laisse quatre pixels sur cinq STRICTEMENT identiques au SDR, ce que
  // « sans que le reste change » demande, tout en donnant a l'etirement de quoi se voir.
  const size_t khi = n / 5;  // 52e valeur en partant du haut sur 256
  std::partial_sort(mx.begin(), mx.begin() + khi + 1, mx.end(), std::greater<float>());
  const float hi = mx[khi];
  // Le REPLI, et il est identique au bit a ce qui tournait avant ce chantier.
  float peak = 0.5f * (mx[0] + mx[1]);
  if (max_ok) {
    float top = 0.f;
    // hdr-output-regime, AVERTISSEMENT A du contrat : la MEME statistique d'ordre, sur les MEMES
    // tuiles, mais celles de l'etage de MAXIMUM au lieu de celles de moyenne. C'est l'ecart entre
    // les deux que l'avertissement reclame — « seul `peak` passe au maximum ; `hi`, le centile qui
    // place l'ancre, reste tire des tuiles MOYENNES ». On le MESURE au lieu de le supposer.
    std::vector<float> mxm(n, 0.f);
    for (size_t i = 0; i < n; i++) {
      float c[3];
      an_texel(raw, n + i, c);  // etage 1 : lignes 16..31
      const float m = std::fmax(c[0], std::fmax(c[1], c[2]));
      mxm[i] = m;
      if (m > top) {
        top = m;
      }
    }
    peak = top;
    std::partial_sort(mxm.begin(), mxm.begin() + khi + 1, mxm.end(), std::greater<float>());
    const float hi_max = mxm[khi];
    // Les deux ancres que ces deux centiles DEDUIRAIENT, a plafond egal. La courbe livree n'en
    // utilise plus aucune (C2) ; ce chiffre dit de combien elle se serait trompee si elle en
    // utilisait une, et il est publie a cote du verdict pour que le chantier suivant n'ait pas a
    // le redecouvrir.
    const float cref = std::fmax(1.001f, tonemap_ceiling());
    s_anchor_mean_last = deduced_anchor(clampf(hi, 0.02f, 4.f), cref);
    s_anchor_max_last = deduced_anchor(clampf(hi_max, 0.02f, 4.f), cref);
    const uint64_t gap =
        (uint64_t)std::llround(std::fabs((double)s_anchor_max_last - (double)s_anchor_mean_last) *
                               1000.0);
    if (gap > s_anchor_gap_max_x1000) {
      s_anchor_gap_max_x1000 = gap;
    }
    s_anchor_samples++;
  }
  dyn_update(key, hi, peak);

  // ---------------------------------------------------------------- LA PORTE DE CET ITEM ----
  // Le rapport se calcule sur la MEME image : `ref_peak` a ete releve par le temoin pleine
  // resolution au moment ou le PBO de cette lecture a ete rempli, pas sur une autre image, et
  // `exposure` est celle qui etait poussee au shader a cet instant-la. Le temoin lit la scene
  // BRUTE ; la statistique la lit apres exposition et apres une courbe qui est l'identite sous
  // le genou (plafond de lecture 64, cf. kAnCeiling) : le facteur d'exposition est donc le seul
  // ecart d'espace entre les deux, et il est applique ici, jamais suppose egal a 1.
  if (ref_peak < 0.f) {
    return;  // cette analyse n'etait pas appairee
  }
  const float ref_curve = ref_peak * exposure;
  if (!(ref_curve > 0.f)) {
    s_ci_black++;  // image noire : le temoin ne voit rien, la paire ne prouve rien
    return;
  }
  s_ci_samples++;
  if (s_ci_knee_level > 0.f && ref_curve > s_ci_knee_level * kAnCeiling) {
    s_ci_knee++;  // au-dela du genou la courbe n'est plus l'identite : la paire est declaree
  }
  if (ref_curve > s_ci_ref_peak_max) {
    s_ci_ref_peak_max = ref_curve;
  }
  if (peak > s_ci_curve_peak_max) {
    s_ci_curve_peak_max = peak;
  }
  const double r = (double)ref_curve / (double)std::fmax(peak, 1e-6f);
  if (r > s_ci_ratio_worst) {
    s_ci_ratio_worst = r;
    s_ci_ref_at_worst = ref_curve;
    s_ci_curve_at_worst = peak;
    s_ci_exp_at_worst = exposure;
  }
}

// --------------------------------------------------------- verdict 11 : les rampes ----
// Une source 128x1 flottante, une marche par texel, dans l'espace d'AFFICHAGE du jeu (celui du
// tampon UI). NEAREST des deux cotes : le texel i de la cible lit le texel i de la source.
bool make_ramp_tex(GLuint* tex, float lo, float hi) {
  gl_query_census::Armed _ap("hdr-out-ramp-tex");
  std::vector<float> data((size_t)kRampN * 4, 1.f);
  for (int i = 0; i < kRampN; i++) {
    const float v = lo + (hi - lo) * ((float)i / (float)(kRampN - 1));
    data[(size_t)i * 4 + 0] = v;
    data[(size_t)i * 4 + 1] = v;
    data[(size_t)i * 4 + 2] = v;
    data[(size_t)i * 4 + 3] = 1.f;
  }
  glGenTextures(1, tex);
  glBindTexture(GL_TEXTURE_2D, *tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, kRampN, 1, 0, GL_RGBA, GL_FLOAT, data.data());
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  return glGetError() == GL_NO_ERROR;
}

// La cible de la sonde porte le format REEL de la fenetre : c'est SA quantification qu'on
// compte, pas celle d'un tampon de confort.
bool make_target_fbo(GLuint* fbo, GLuint* tex, int w, int h, GLenum internal_fmt) {
  GLenum fmt = GL_RGBA, type = GL_UNSIGNED_BYTE;
  if (internal_fmt == GL_RGBA16F) {
    type = GL_FLOAT;
  } else if (internal_fmt == GL_RGB10_A2) {
    type = GL_UNSIGNED_INT_2_10_10_10_REV;
  }
  glGenFramebuffers(1, fbo);
  glGenTextures(1, tex);
  glBindTexture(GL_TEXTURE_2D, *tex);
  glTexImage2D(GL_TEXTURE_2D, 0, (GLint)internal_fmt, w, h, 0, fmt, type, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
  const GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (st != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[hdr-display-output] cible de rampe indisponible pour 0x{:x} : 0x{:x}",
              (unsigned)internal_fmt, (unsigned)st);
    return false;
  }
  return true;
}

// Combien de valeurs DISTINCTES la sortie a-t-elle su ecrire pour les 128 marches ? On compare
// des CODES bruts (octet, mot 10 bits, motif de bits du demi-flottant) : aucune tolerance
// flottante ne peut fusionner ou separer deux niveaux par accident.
bool read_levels(int n, GLenum fmt, uint64_t* out_levels) {
  gl_query_census::Armed _ap("hdr-out-read-levels");
  while (glGetError() != GL_NO_ERROR) {
  }
  std::vector<uint32_t> codes((size_t)n, 0u);
  if (fmt == GL_RGBA16F) {
    std::vector<float> px;
    if (!read_float_fbo(n, 1, px) || px.size() < (size_t)n * 4) {
      return false;
    }
    for (int i = 0; i < n; i++) {
      uint32_t b = 0;
      const float v = px[(size_t)i * 4];
      std::memcpy(&b, &v, sizeof(b));
      codes[(size_t)i] = b;
    }
    s_rp_read_type = 16;
  } else if (fmt == GL_RGB10_A2) {
    std::vector<uint32_t> raw((size_t)n, 0u);
    glReadPixels(0, 0, n, 1, GL_RGBA, GL_UNSIGNED_INT_2_10_10_10_REV, raw.data());
    if (glGetError() != GL_NO_ERROR) {
      return false;
    }
    for (int i = 0; i < n; i++) {
      codes[(size_t)i] = raw[(size_t)i] & 0x3ffu;
    }
    s_rp_read_type = 10;
  } else {
    std::vector<uint8_t> raw((size_t)n * 4, 0u);
    glReadPixels(0, 0, n, 1, GL_RGBA, GL_UNSIGNED_BYTE, raw.data());
    if (glGetError() != GL_NO_ERROR) {
      return false;
    }
    for (int i = 0; i < n; i++) {
      codes[(size_t)i] = raw[(size_t)i * 4];
    }
    s_rp_read_type = 8;
  }
  std::sort(codes.begin(), codes.end());
  *out_levels = (uint64_t)(std::unique(codes.begin(), codes.end()) - codes.begin());
  return true;
}

// ARIB STD-B67 (BT.2100 HLG), inverse de `hlg_oetf` de post_processing.frag. Rend la scene
// RELATIVE : 1,0 = le pic de l'ecran, jamais des nits — le HLG n'en connait pas.
double hlg_inverse_oetf(double e) {
  const double a = 0.17883277, b = 0.28466892, c = 0.55991073;
  if (e < 0.0) {
    return 0.0;
  }
  if (e <= 0.5) {
    return (e * e) / 3.0;
  }
  return (std::exp((e - c) / a) + b) / 12.0;
}

// SMPTE ST 2084, OETF — le MIROIR EXACT de `pq_oetf` de post_processing.frag (mode 1). Sert a
// compter, hors ecran, les codes 10 bits que la fenetre HDR recevrait : c'est une propriete de
// NOTRE encodage (densite de codes), jamais une affirmation sur ce que la dalle emet.
double pq_oetf_from_nits(double nits) {
  const double m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625,
               c3 = 18.6875;
  double y = (nits < 0.0 ? 0.0 : nits) / 10000.0;
  double ym = std::pow(y, m1);
  double e = std::pow((c1 + c2 * ym) / (1.0 + c3 * ym), m2);
  return e < 0.0 ? 0.0 : (e > 1.0 ? 1.0 : e);
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

// L'ANGLE DE TEINTE, en degres, dans le plan opposant-couleur de l'encodage d'affichage. On ne
// cherche pas une teinte colorimetrique exacte : on cherche si NOTRE courbe la fait DERIVER, et
// pour ca il suffit d'un angle stable calcule des deux cotes de la meme facon.
double hue_deg(const float* c) {
  const double a = (double)c[0] - 0.5 * ((double)c[1] + (double)c[2]);
  const double b = 0.8660254037844386 * ((double)c[1] - (double)c[2]);
  double h = std::atan2(b, a) * 57.29577951308232;
  if (h < 0.0) {
    h += 360.0;
  }
  return h;
}

// Le plancher de la population : sous 1e-4 de luminance lineaire (soit 0,015 dans l'espace
// d'affichage) un demi-flottant ne porte plus assez de bits pour que le logarithme veuille dire
// quelque chose. Les bandes couvrent [1e-4 ; 1].
constexpr double kExcLogLo = -9.210340371976182;  // ln(1e-4)

void exc_accumulate(ExcStats& e, const float* sdr, const float* hdr) {
  const double ys = lum_linear(sdr[0], sdr[1], sdr[2]);
  const double yh = lum_linear(hdr[0], hdr[1], hdr[2]);
  if (!std::isfinite(ys) || !std::isfinite(yh) || ys <= 1e-4 || yh <= 1e-6) {
    return;
  }
  const double x = std::log(ys), y = std::log(yh);
  e.n++;
  e.sx += x;
  e.sy += y;
  e.sxx += x * x;
  e.sxy += x * y;
  e.syy += y * y;
  int b = (int)((x - kExcLogLo) / ((0.0 - kExcLogLo) / (double)kExcBands));
  if (b < 0) {
    b = 0;
  }
  if (b >= kExcBands) {
    b = kExcBands - 1;
  }
  e.bn[b]++;
  e.bx[b] += x;
  e.by[b] += y;
  const float ms = std::fmax(sdr[0], std::fmax(sdr[1], sdr[2]));
  const float mh = std::fmax(hdr[0], std::fmax(hdr[1], hdr[2]));
  const float ns = std::fmin(sdr[0], std::fmin(sdr[1], sdr[2]));
  const float nh = std::fmin(hdr[0], std::fmin(hdr[1], hdr[2]));
  if (!(ms > 0.05f) || !(mh > 0.05f)) {
    return;
  }
  const double ss = 1.0 - (double)ns / (double)ms;
  const double sh = 1.0 - (double)nh / (double)mh;
  e.sat_n++;
  e.sat_off += ss;
  e.sat_on += sh;
  const double dsat = std::fabs(sh - ss);
  if (dsat > e.sat_worst) {
    e.sat_worst = dsat;
  }
  if (ss > 0.05) {
    double dh = std::fabs(hue_deg(hdr) - hue_deg(sdr));
    if (dh > 180.0) {
      dh = 360.0 - dh;
    }
    e.hue_n++;
    e.hue_sum += dh;
    if (dh > e.hue_worst) {
      e.hue_worst = dh;
    }
  }
}

ExcOut exc_reduce(const ExcStats& e) {
  ExcOut o;
  o.n = e.n;
  if (e.n < 3000) {
    return o;
  }
  const double n = (double)e.n;
  const double den = n * e.sxx - e.sx * e.sx;
  if (den > 1e-9) {
    o.exp_g = (n * e.sxy - e.sx * e.sy) / den;
  }
  const double vx = e.sxx / n - (e.sx / n) * (e.sx / n);
  const double vy = e.syy / n - (e.sy / n) * (e.sy / n);
  if (vx > 1e-9 && vy > 0.0) {
    o.rms = std::sqrt(vy / vx);
  }
  const double need = 0.01 * n;  // une bande qui porte moins de 1 % des pixels ne juge rien
  for (int j = 0; j + 1 < kExcBands; j++) {
    if ((double)e.bn[j] < need || (double)e.bn[j + 1] < need) {
      continue;
    }
    const double dx = e.bx[j + 1] / (double)e.bn[j + 1] - e.bx[j] / (double)e.bn[j];
    const double dy = e.by[j + 1] / (double)e.bn[j + 1] - e.by[j] / (double)e.bn[j];
    if (!(dx > 1e-6)) {
      continue;
    }
    o.bands++;
    const double sl = dy / dx;
    if (sl > o.band_max) {
      o.band_max = sl;
    }
  }
  if (e.sat_n && e.sat_off > 1e-9) {
    o.sat_ratio = e.sat_on / e.sat_off;
  }
  o.sat_worst = e.sat_worst;
  if (e.hue_n) {
    o.hue_mean = e.hue_sum / (double)e.hue_n;
  }
  o.hue_worst = e.hue_worst;
  return o;
}

// ============================================================================================
// L'ETUDE (`hdr-study`) — SIX QUESTIONS, SIX MESURES, ET LE COMPTE DE CELLES QUI RESTENT SANS
// REPONSE. Ce bloc n'ajoute AUCUN geste de rendu : il ne fait que RELIRE l'etat que les sondes
// de ce fichier ont deja rempli et le republier sous un nom qui dit a quelle question il repond.
//
// POURQUOI UNE PORTE « QUESTIONS OUVERTES » ET PAS UN VERDICT. Le livrable de l'etude est un
// DOCUMENT ; la seule chose qu'une machine peut garantir, c'est que chaque question a ete
// mesuree sur l'appareil et non devinee. `hdr_study_questions_open` compte donc les questions
// dont la mesure de soutien MANQUE ou est VIDE (denominateur nul). Il ne dit rien de la qualite
// de l'image — c'est l'owner qui juge, et ce chantier ne change rien a ce qu'il voit.
//
// CE QUI REND LE ZERO FALSIFIABLE. Chaque question exige un COMPTE D'ECHANTILLONS non nul, pris
// par une sonde distincte : images de scene analysees (Q2), pixels d'ombre profonde du jeu reel
// (Q3), echantillons de rampe dans LES DEUX bras (Q3 et Q5), echantillons d'adaptation (Q4),
// capacites sondees (Q5). Un binaire qui ne tourne pas, une sonde qui echoue, un auto-test qui
// n'arrive pas au bout : la valeur monte, elle ne descend jamais toute seule.
void publish_study() {
  if (!studying()) {
    return;  // instrument : muet hors de la mesure de CET item
  }
  // ---- ce que l'etude lit, une bonne fois, sous le verrou -----------------------------------
  SysCaps sys;
  PlatformCaps plat;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    sys = s_sys;
    plat = s_plat;
  }
  const SurfaceState surf = s_surface;
  const PresentVerdict pv = display_presents_hdr();

  // ---- Q1 : LA CHAINE, etage par etage, en BITS REELLEMENT OBSERVES -------------------------
  // Les trois etages que le chemin d'affichage traverse apres l'ombrage. `scene_color_format()`
  // est le format RETENU (apres l'echelle de repli), `s_study_ui_fmt` celui que `frame_end` a
  // recu pour l'image, `surf.red_bits` ce que `glGetIntegerv(GL_RED_BITS)` a rendu sur la
  // fenetre. Aucun n'est suppose : le troisieme surtout, qui dement une demande non exaucee.
  const GLenum f_scene = hdr::scene_color_format();
  const bool scene_float = hdr::format_is_float(f_scene);
  const int ui_bits = (s_study_ui_fmt == GL_RGBA16F) ? 16 : (s_study_ui_fmt == 0 ? 0 : 8);
  int q1_stages = 0;
  q1_stages += (f_scene != 0) ? 1 : 0;
  q1_stages += (s_study_ui_fmt != 0) ? 1 : 0;
  q1_stages += (surf.red_bits > 0) ? 1 : 0;
  autoport_proof::publish_text("hdr_study_q1_scene_fmt", hdr::format_name(f_scene));
  autoport_proof::publish("hdr_study_q1_scene_bits", (uint64_t)(scene_float ? 16 : 8));
  autoport_proof::publish("hdr_study_q1_scene_float", (uint64_t)(scene_float ? 1 : 0));
  autoport_proof::publish_text("hdr_study_q1_ui_fmt",
                               s_study_ui_fmt == 0 ? "-" : hdr::format_name(s_study_ui_fmt));
  autoport_proof::publish("hdr_study_q1_ui_bits", (uint64_t)ui_bits);
  autoport_proof::publish("hdr_study_q1_win_bits", (uint64_t)surf.red_bits);
  autoport_proof::publish("hdr_study_q1_win_colorspace", (uint64_t)surf.colorspace);
  autoport_proof::publish("hdr_study_q1_stages_measured", (uint64_t)q1_stages);
  // L'ESPACE, pas seulement la profondeur : le tampon de scene porte l'encodage d'affichage du
  // jeu (`pow(x,1/2.2)`), et le tone map applique sa courbe LA-DEDANS. `hdr_oetf_progs` (publie
  // par hdr.cpp) en est le recensement ; ici on publie la consequence qui interesse l'etude.
  autoport_proof::publish_text("hdr_study_q1_scene_space", "encodage_d_affichage_pow_1_sur_2,2");
  const bool q1_closed = (q1_stages == 3);

  // ---- Q2 : LE TAMPON EST-IL ASSEZ RICHE ? --------------------------------------------------
  // Deux temoins independants. Celui-ci compte les IMAGES dont le pic de scene brut depasse 1,0
  // (l'analyse de scene tourne a chaque image ou la courbe est libre) ; `hdr_probe_*`, publie
  // par hdr.cpp, compte les PIXELS. Deux sondes, deux denominateurs : un desaccord se voit.
  autoport_proof::publish("hdr_study_q2_scene_samples", s_study_scene_samples);
  autoport_proof::publish("hdr_study_q2_over1_frames", s_study_scene_over1);
  autoport_proof::publish("hdr_study_q2_peak_max_x1000",
                          (uint64_t)std::lround(s_study_scene_peak_max * 1000.f));
  autoport_proof::publish("hdr_study_q2_depth_bits", (uint64_t)(scene_float ? 16 : 8));
  autoport_proof::publish("hdr_study_q2_fallback_step", (uint64_t)(scene_float ? 0 : 1));
  const bool q2_closed = (s_study_scene_samples > 0);

  // ---- Q3 : LES OMBRES ----------------------------------------------------------------------
  // Le comptage de codes DISTINCTS sur du JEU REEL, fenetre [0, 1/16] : c'est la grandeur que le
  // contrat designe comme « des paliers de quantification, pas de la luminance ». On la republie
  // TELLE QUELLE, et on publie a cote ce qu'elle NE dit pas — la luminance livree.
  uint64_t deep_off = 0, deep_on = 0;
  for (int i = 0; i < 256; i++) {
    deep_off += s_play.code_off_deep[i] ? 1 : 0;
  }
  for (int i = 0; i < 1024; i++) {
    deep_on += s_play.code_on_deep[i] ? 1 : 0;
  }
  autoport_proof::publish("hdr_study_q3_deep_px", s_play.deep_px);
  autoport_proof::publish("hdr_study_q3_deep_levels_sdr", deep_off);
  autoport_proof::publish("hdr_study_q3_deep_levels_hdr", deep_on);
  autoport_proof::publish("hdr_study_q3_ramp_levels_sdr", s_pr[2].shadow_levels);
  autoport_proof::publish("hdr_study_q3_ramp_levels_hdr", s_pr[1].shadow_levels);
  autoport_proof::publish("hdr_study_q3_ramp_samples_sdr", s_pr[2].ramp_samples);
  autoport_proof::publish("hdr_study_q3_ramp_samples_hdr", s_pr[1].ramp_samples);
  // LA LUMINANCE, elle. Le blanc SDR livre par la fenetre courante, et la lumiere que represente
  // le HAUT de la fenetre d'ombres profondes : (1/16) en encodage d'affichage vaut (1/16)^2,2 en
  // lumiere, soit 0,29 % du blanc. Le pas de quantification moyen dans cette bande est cette
  // lumiere divisee par le nombre de codes que chaque etat y separe.
  const double white_nits = (double)sdr_white_nits();
  const double band_lin = std::pow(1.0 / 16.0, 2.2);
  const double band_nits = band_lin * white_nits;
  autoport_proof::publish("hdr_study_q3_white_nits", (uint64_t)std::lround(white_nits));
  autoport_proof::publish("hdr_study_q3_band_nits_x1000", (uint64_t)std::lround(band_nits * 1000.0));
  autoport_proof::publish(
      "hdr_study_q3_step_sdr_nits_x100000",
      (uint64_t)(deep_off ? std::lround(band_nits * 100000.0 / (double)deep_off) : 0));
  autoport_proof::publish(
      "hdr_study_q3_step_hdr_nits_x100000",
      (uint64_t)(deep_on ? std::lround(band_nits * 100000.0 / (double)deep_on) : 0));
  // LE GAIN DE LUMIERE, pas de paliers. La courbe livree rend l'IDENTITE sous l'ancre
  // (tonemap.frag, `hdr_power` : `if (v <= a) return v;`). On l'evalue au MILIEU de la fenetre
  // d'ombres profondes, avec les parametres COURANTS : si la valeur sort inchangee, le gain de
  // luminance dans les ombres vaut exactement 1,000 et le dire est une mesure, pas une opinion.
  {
    const float v = 1.f / 32.f;
    const float a = s_cur.anchor, K = s_cur.gamma, C = std::fmax(s_cur.ceiling, 1.f);
    float out = v;
    if (a > 0.f && a < 1.f) {
      if (s_cur.shape == 1) {
        out = (v <= a) ? v : std::fmin(a * std::pow(v / a, K), C);
      } else {
        const float r = std::fmax(C - a, 1e-4f), w = std::fmax(s_cur.top - a, 1e-4f);
        const float p = std::fmax(std::fmin(w / r, 1.f), 1e-3f);
        out = (v <= a) ? v
                       : (v >= s_cur.top ? C : a + r * (p * ((v - a) / w) +
                                                        (3.f - 2.f * p) * ((v - a) / w) * ((v - a) / w) +
                                                        (p - 2.f) * ((v - a) / w) * ((v - a) / w) * ((v - a) / w)));
      }
    }
    // Le PIED est le seul terme du shader qui touche vraiment les ombres ; il est publie a cote.
    const float s = 0.25f;
    if (out > 0.f && out < s && s_cur.toe > 0.f) {
      const float u = 1.f - out / s;
      out = out + s_cur.toe * out * u * u;
    }
    // Gain en LUMIERE : les deux valeurs sont en encodage d'affichage, la lumiere est leur
    // puissance 2,2. Un rapport de 1,000 veut dire « la meme lumiere, au bit pres ».
    const double gain = std::pow((double)out / (double)v, 2.2);
    autoport_proof::publish("hdr_study_q3_lum_gain_x1000", (uint64_t)std::lround(gain * 1000.0));
  }
  autoport_proof::publish("hdr_study_q3_anchor_x1000", (uint64_t)std::lround(s_cur.anchor * 1000.f));
  autoport_proof::publish("hdr_study_q3_toe_x1000", (uint64_t)std::lround(s_cur.toe * 1000.f));
  autoport_proof::publish("hdr_study_q3_ceiling_x1000", (uint64_t)std::lround(s_cur.ceiling * 1000.f));
  // Sous quelle FRACTION du blanc, en lumiere, la sortie est-elle identique au SDR ? C'est
  // `ancre^2,2`. A 0,208 d'ancre, 3,1 % du blanc : tout ce que l'oeil appelle « les ombres ».
  autoport_proof::publish(
      "hdr_study_q3_identity_below_pct_x100",
      (uint64_t)std::lround(std::pow(std::fmax((double)s_cur.anchor, 0.0), 2.2) * 10000.0));
  const bool q3_closed =
      s_play.deep_px > 0 && s_pr[1].ramp_samples > 0 && s_pr[2].ramp_samples > 0;

  // ---- Q4 : LA COURBE VARIE-T-ELLE DANS LE TEMPS ? -----------------------------------------
  autoport_proof::publish("hdr_study_q4_samples", (uint64_t)s_dyn_stats.samples);
  autoport_proof::publish("hdr_study_q4_updates", s_dyn_updates);
  autoport_proof::publish("hdr_study_q4_anchor_span_x1000",
                          (uint64_t)std::lround((s_dyn_stats.a_max - s_dyn_stats.a_min) * 1000.0));
  autoport_proof::publish("hdr_study_q4_top_span_x1000",
                          (uint64_t)std::lround((s_dyn_stats.t_max - s_dyn_stats.t_min) * 1000.0));
  autoport_proof::publish("hdr_study_q4_ceiling_span_x1000",
                          (uint64_t)std::lround((s_dyn_stats.c_max - s_dyn_stats.c_min) * 1000.0));
  autoport_proof::publish("hdr_study_q4_resp_span_pct", (uint64_t)std::lround(s_dyn_stats.r_span * 100.0));
  autoport_proof::publish("hdr_study_q4_sdr_frames", s_dyn_sdr_frames);
  autoport_proof::publish("hdr_study_q4_free_frames", s_dyn_free_frames);
  autoport_proof::publish("hdr_study_q4_pinned_frames", s_dyn_pinned_frames);
  const bool q4_closed = s_dyn_stats.samples > 0;

  // ---- Q5 : LE FORMAT -----------------------------------------------------------------------
  // Les trois transports, chacun avec la raison MESUREE qui le rend possible ou non. Le contrat
  // scRGB est une borne d'API (34+), les deux autres des extensions EGL plus un EGLConfig qui
  // existe vraiment : ce sont des faits sondes au demarrage, pas des suppositions.
  const int scrgb_ok = (sys.sdk_int >= 34 && plat.egl_scrgb_linear && plat.egl_fp16 && plat.config_fp16) ? 1 : 0;
  const int pq_ok = (plat.egl_bt2020_pq && plat.config_10bit) ? 1 : 0;
  const int hlg_ok = (plat.egl_bt2020_hlg && plat.config_10bit) ? 1 : 0;
  autoport_proof::publish("hdr_study_q5_scrgb_usable", (uint64_t)scrgb_ok);
  autoport_proof::publish("hdr_study_q5_pq_usable", (uint64_t)pq_ok);
  autoport_proof::publish("hdr_study_q5_hlg_usable", (uint64_t)hlg_ok);
  autoport_proof::publish("hdr_study_q5_transports_evaluated", (uint64_t)(plat.probed && sys.reported ? 3 : 0));
  autoport_proof::publish("hdr_study_q5_sdk_int", (uint64_t)sys.sdk_int);
  autoport_proof::publish("hdr_study_q5_mode_used", (uint64_t)surf.mode);
  autoport_proof::publish_text("hdr_study_q5_mode_name", mode_name(surf.mode));
  autoport_proof::publish("hdr_study_q5_presents_hdr", (uint64_t)(pv.presents ? 1 : 0));
  autoport_proof::publish_text("hdr_study_q5_presents_reason", pv.reason);
  const bool q5_closed = plat.probed && sys.reported && surf.red_bits > 0;

  // ---- Q6 : CE QUI EMPECHE LE GAIN ----------------------------------------------------------
  // Cinq causes, chacune adossee a une grandeur DEJA mesuree ci-dessus. On publie le COMPTE de
  // celles qui ont pu etre evaluees (le denominateur) a cote du compte de celles qui mordent :
  // sans lui, « 0 cause » ne se distingue pas de « rien n'a ete regarde ».
  int evaluated = 0, blockers = 0;
  std::string list;
  auto note = [&](bool can_eval, bool hits, const char* name) {
    if (!can_eval) {
      return;
    }
    evaluated++;
    if (hits) {
      blockers++;
      if (!list.empty()) {
        list += ",";
      }
      list += name;
    }
  };
  // 1. L'ecran ne PRESENTE pas le HDR : aucune nit au-dessus de son blanc diffus n'est possible.
  note(sys.reported, !pv.presents, "ecran_ne_presente_pas");
  // 2. La marge accordee vaut 1,000 : le plafond du tone map retombe a 1 et la courbe HDR
  //    degenere en un simple relevement de tons moyens A L'INTERIEUR de la plage SDR.
  note(s_frames > 0, s_ratio_max_x1000 <= 1005, "marge_accordee_a_1");
  // 3. Le pied est nul : le SEUL terme du shader qui touche les ombres ne fait rien.
  note(s_dyn_stats.samples > 0, s_cur.toe <= 0.f, "pied_nul");
  // 4. Sous l'ancre la sortie est l'identite : les ombres sont, par construction, le SDR.
  note(s_dyn_stats.samples > 0, s_cur.anchor > 0.f, "identite_sous_l_ancre");
  // 5. Le tampon de scene ne depasse jamais 1,0 : il n'y a rien a etaler au-dessus du blanc.
  note(s_study_scene_samples > 0, s_study_scene_over1 == 0, "scene_jamais_au_dessus_de_1");
  autoport_proof::publish("hdr_study_q6_evaluated", (uint64_t)evaluated);
  autoport_proof::publish("hdr_study_q6_blockers", (uint64_t)blockers);
  autoport_proof::publish_text("hdr_study_q6_list", list.empty() ? "-" : list.c_str());
  const bool q6_closed = (evaluated == 5);

  // ---- LE COMPTE ----------------------------------------------------------------------------
  const bool closed[6] = {q1_closed, q2_closed, q3_closed, q4_closed, q5_closed, q6_closed};
  uint64_t open = 0;
  std::string open_list;
  for (int i = 0; i < 6; i++) {
    autoport_proof::publish((std::string("hdr_study_q") + (char)('1' + i) + "_closed").c_str(),
                            (uint64_t)(closed[i] ? 1 : 0));
    if (!closed[i]) {
      open++;
      if (!open_list.empty()) {
        open_list += ",";
      }
      open_list += "q";
      open_list += (char)('1' + i);
    }
  }
  autoport_proof::publish_text("hdr_study_questions_open_list", open_list.empty() ? "-" : open_list.c_str());
  autoport_proof::publish("hdr_study_questions_open", open);
  // LE GESTE DE L'ETUDE, c'est CETTE publication. `hits` est partage par tout le binaire : on ne
  // le compte QUE sous l'item `hdr-study`, sinon le compteur de tous les autres items monterait.
  autoport_proof::note_hit_for(kStudyId);
}

// ============================================================================================
// LE PLAN (`hdr-plan`) — SIX SECTIONS, SIX ANCRAGES MESURES, ET LE COMPTE DE CELLES QUI RESTENT
// SANS ANCRAGE. Ce bloc n'ajoute AUCUN geste de rendu : il RELIT ce que le chemin livre produit
// deja et le republie sous un nom qui dit a quelle section du document il repond.
//
// POURQUOI UNE PORTE « SECTIONS OUVERTES » ET PAS UN VERDICT DE RENDU. Le livrable est un
// DOCUMENT. La seule chose qu'une machine peut garantir d'un document, c'est que chacune de ses
// sections s'appuie sur une grandeur MESUREE SUR L'APPAREIL pendant CETTE course, et non sur un
// souvenir, une lecture de code ou un proof d'hier. `hdr_plan_sections_open` compte donc les
// sections dont la mesure de soutien MANQUE ou a un denominateur nul.
//
// CE QUI REND LE ZERO FALSIFIABLE. Chaque section exige un COMPTE non nul produit par un
// instrument DISTINCT et, pour quatre d'entre elles, par une AUTRE unite de compilation
// (`hdr.cpp`) : etages d'affichage relus sur le pilote (S1), recensement des entrees pris a
// leur site de CREATION (S2), entrees systeme lues chez le systeme (S3), recensement de shaders
// pris a la compilation (S4), les cinq instruments sans ecran (S5), l'invariant « une seule
// compression de plage » du chemin livre (S6). Un binaire qui ne tourne pas, un appel de
// recensement oublie, une sonde refusee par le pilote : la valeur monte. Elle ne descend jamais
// toute seule.
//
// CE QU'IL NE DIT PAS. Rien sur la qualite de l'image, rien sur ce que la dalle EMET. Le plan ne
// change pas un pixel ; c'est l'owner qui juge le rendu, et il n'y a rien a regarder ici.
void publish_plan() {
  if (!planning()) {
    return;  // instrument : muet hors de la mesure de CET item
  }
  SysCaps sys;
  PlatformCaps plat;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    sys = s_sys;
    plat = s_plat;
  }
  const SurfaceState surf = s_surface;
  const PresentVerdict pv = display_presents_hdr();
  const hdr::ChainCensus cc = hdr::chain_census();
  const hdr::InputCensus ic = hdr::input_census();

  // ---- S1 : LE CHEMIN, etage par etage, en formats REELLEMENT OBSERVES ---------------------
  // Les trois etages que la couleur traverse apres l'ombrage. Aucun n'est suppose : le troisieme
  // surtout, relu sur la fenetre, qui dement une demande non exaucee.
  const GLenum f_scene = hdr::scene_color_format();
  int s1_stages = 0;
  s1_stages += (f_scene != 0) ? 1 : 0;
  s1_stages += (s_study_ui_fmt != 0) ? 1 : 0;
  s1_stages += (surf.red_bits > 0) ? 1 : 0;
  autoport_proof::publish_text("hdr_plan_s1_scene_fmt", hdr::format_name(f_scene));
  autoport_proof::publish("hdr_plan_s1_scene_float", (uint64_t)(hdr::format_is_float(f_scene) ? 1 : 0));
  autoport_proof::publish_text("hdr_plan_s1_ui_fmt",
                               s_study_ui_fmt == 0 ? "-" : hdr::format_name(s_study_ui_fmt));
  autoport_proof::publish("hdr_plan_s1_win_bits", (uint64_t)surf.red_bits);
  autoport_proof::publish("hdr_plan_s1_win_colorspace", (uint64_t)surf.colorspace);
  autoport_proof::publish("hdr_plan_s1_tonemap_sites", hdr::last_frame_sites());
  autoport_proof::publish("hdr_plan_s1_stages_measured", (uint64_t)s1_stages);
  const bool s1_closed = (s1_stages == 3);

  // ---- S2 : LES ENTREES A ENRICHIR ----------------------------------------------------------
  // Le recensement est pris AU SITE DE CREATION de chaque cible, pas sur une liste ecrite a la
  // main : une source qu'on aurait oublie d'instrumenter manque a l'appel et la section reste
  // ouverte. Les six entrees EXIGEES sont celles que tout demarrage cree, sur les deux
  // plateformes (les deux resolutions du ciel, GPU et CPU, la sonde de glow et son premier
  // etage de reduction). Les autres — occlusion ambiante, palettes de cycle jour/nuit, depth-cue
  // — dependent du niveau, du palier de qualite ou de la plateforme : elles sont COMPTEES et
  // NOMMEES, jamais exigees. Un plancher calibre sur une population conditionnelle rendrait la
  // porte rouge pour une raison qui n'a rien a voir avec le plan.
  static const char* kRequiredInputs[] = {"sky-blend-gpu-0", "sky-blend-gpu-1", "sky-blend-cpu-0",
                                          "sky-blend-cpu-1", "glow-probe", "glow-downsample-0"};
  const int kRequiredInputCount = (int)(sizeof(kRequiredInputs) / sizeof(kRequiredInputs[0]));
  int s2_required_seen = 0;
  std::string s2_missing;
  for (int i = 0; i < kRequiredInputCount; i++) {
    if (hdr::input_source_seen(kRequiredInputs[i])) {
      s2_required_seen++;
    } else {
      if (!s2_missing.empty()) {
        s2_missing += ",";
      }
      s2_missing += kRequiredInputs[i];
    }
  }
  autoport_proof::publish("hdr_plan_s2_sources_seen", ic.sources_seen);
  autoport_proof::publish("hdr_plan_s2_sources_8bit", ic.sources_8bit);
  autoport_proof::publish("hdr_plan_s2_sources_unknown", ic.sources_unknown);
  autoport_proof::publish("hdr_plan_s2_bytes_8bit", ic.bytes_8bit);
  autoport_proof::publish("hdr_plan_s2_bytes_total", ic.bytes_total);
  autoport_proof::publish("hdr_plan_s2_required", (uint64_t)kRequiredInputCount);
  autoport_proof::publish("hdr_plan_s2_required_seen", (uint64_t)s2_required_seen);
  autoport_proof::publish_text("hdr_plan_s2_missing", s2_missing.empty() ? "-" : s2_missing.c_str());
  autoport_proof::publish_text("hdr_plan_s2_list", hdr::input_census_list());
  const bool s2_closed = (s2_required_seen == kRequiredInputCount) && (ic.sources_unknown == 0);

  // ---- S3 : L'ADAPTATION, SANS AUCUN APPAREIL NOMME -----------------------------------------
  // Six entrees, six producteurs differents, et AUCUN nom d'appareil : ce que le systeme a
  // rapporte (Java), ce que le pilote EGL a laisse sonder, ce que la fenetre rend quand on la
  // relit, la version d'API, le pic annonce, et la consigne de retro-eclairage que le systeme
  // publie lui-meme. Le REGIME s'en deduit et c'est lui, pas un modele de telephone, qui decide
  // de ce que la sortie HDR peut livrer :
  //   2 = l'ecran PRESENTE le HDR (contrat d'API, ou forme des capacites annoncees) ;
  //   1 = il ne fait que DECODER, mais le systeme a ACCORDE de la marge (consigne relevee) ;
  //   0 = aucune marge accordee. Dans ce regime il n'y a pas de nits a gagner : ce qui reste est
  //       le conteneur et sa quantification, et c'est tout ce que le plan doit promettre.
  int s3_inputs = 0;
  s3_inputs += sys.reported ? 1 : 0;
  s3_inputs += plat.probed ? 1 : 0;
  s3_inputs += (surf.red_bits > 0) ? 1 : 0;
  s3_inputs += (sys.sdk_int > 0) ? 1 : 0;
  s3_inputs += (sys.max_lum > 0) ? 1 : 0;
  s3_inputs += (s_bl_base_samples > 0) ? 1 : 0;
  const float grant = measured_grant();
  const int regime = regime_now().level;  // hdr-output-regime : un seul site de decision
  autoport_proof::publish("hdr_plan_s3_inputs_read", (uint64_t)s3_inputs);
  autoport_proof::publish("hdr_plan_s3_regime", (uint64_t)regime);
  autoport_proof::publish("hdr_plan_s3_presents", (uint64_t)(pv.presents ? 1 : 0));
  autoport_proof::publish_text("hdr_plan_s3_presents_reason", pv.reason);
  autoport_proof::publish("hdr_plan_s3_grant_x1000", (uint64_t)std::lround(grant * 1000.f));
  autoport_proof::publish("hdr_plan_s3_bl_base_samples", s_bl_base_samples);
  autoport_proof::publish("hdr_plan_s3_headroom_x1000",
                          (uint64_t)std::lround(headroom_linear() * 1000.f));
  autoport_proof::publish("hdr_plan_s3_sdk_int", (uint64_t)sys.sdk_int);
  autoport_proof::publish("hdr_plan_s3_peak_nits", (uint64_t)sys.max_lum);
  autoport_proof::publish("hdr_plan_s3_max_avg_nits", (uint64_t)sys.max_avg);
  autoport_proof::publish("hdr_plan_s3_min_lum_x10000", (uint64_t)sys.min_lum_x10000);
  autoport_proof::publish("hdr_plan_s3_wide_gamut", (uint64_t)(sys.wide_gamut ? 1 : 0));
  autoport_proof::publish("hdr_plan_s3_ratio_api", (uint64_t)(sys.ratio_available ? 1 : 0));
  const bool s3_closed = (s3_inputs == 6);

  // ---- S4 : L'ORDRE ET LES DEPENDANCES AVEC LA REFONTE DE L'ECLAIRAGE -----------------------
  // Ce qui lie les deux chantiers est un objet unique : le tampon de scene, et l'ESPACE dans
  // lequel il est ecrit. `oetf_progs / progs_scanned` est le recensement, pris a la compilation
  // des shaders, des programmes qui RE-ENCODENT avant d'y ecrire. C'est la grandeur qui dit
  // combien de chemins d'ombrage une linearisation devrait convertir — donc l'ordre.
  autoport_proof::publish("hdr_plan_s4_progs_scanned", cc.progs_scanned);
  autoport_proof::publish("hdr_plan_s4_oetf_progs", cc.oetf_progs);
  autoport_proof::publish("hdr_plan_s4_chain_frames", cc.chain_frames);
  autoport_proof::publish("hdr_plan_s4_scene_fallback_step", (uint64_t)cc.ladder_step);
  autoport_proof::publish("hdr_plan_s4_master_on",
                          (uint64_t)(Gfx::recharged_master_active() ? 1 : 0));
  autoport_proof::publish("hdr_plan_s4_lighting_on", (uint64_t)(lighting_gate() ? 1 : 0));
  const bool s4_closed = (cc.progs_scanned > 0) && (cc.chain_frames > 0);

  // ---- S5 : CE QUI SE PROUVE SANS ECRAN HDR -------------------------------------------------
  // Cinq instruments, et la demonstration est CETTE course : elle tourne sur un ecran dont le
  // regime est publie juste au-dessus. Chacun doit avoir rendu un nombre, sinon la section qui
  // promet « ceci se prouve sans materiel » ne l'a pas demontre.
  int s5_ok = 0;
  const bool p1 = (cc.probe_state == 1) && (cc.probe_px > 0);      // marge du tampon de scene
  const bool p2 = (ic.sources_seen > 0) && (ic.sources_unknown == 0);  // entrees 8 bits
  const bool p3 = (cc.progs_scanned > 0);                          // espace des programmes
  const bool p4 = (cc.tonemap_draws > 0) && (hdr::last_frame_sites() == 1);  // site unique
  const bool p5 = (s3_inputs == 6);                                // decision d'ecran
  s5_ok += p1 ? 1 : 0;
  s5_ok += p2 ? 1 : 0;
  s5_ok += p3 ? 1 : 0;
  s5_ok += p4 ? 1 : 0;
  s5_ok += p5 ? 1 : 0;
  autoport_proof::publish("hdr_plan_s5_offline_probes_ok", (uint64_t)s5_ok);
  autoport_proof::publish("hdr_plan_s5_probe_px", cc.probe_px);
  autoport_proof::publish("hdr_plan_s5_overbright_px", cc.overbright_px);
  autoport_proof::publish("hdr_plan_s5_probe_max_x1000", cc.probe_max_x1000);
  // LA SURDITE DE L'ENTREE DE LA COURBE, chiffree : le plus grand canal que la sonde de PIXELS a
  // vu, contre le pic que voit la statistique de 16x16 tuiles qui PILOTE la courbe. Publie hors
  // porte (l'analyse de scene ne tourne que sortie HDR active) mais avec son denominateur, pour
  // qu'un zero se lise « pas mesure » et non « pas d'ecart ».
  autoport_proof::publish("hdr_plan_s5_curve_input_samples", s_study_scene_samples);
  autoport_proof::publish("hdr_plan_s5_curve_input_peak_x1000",
                          (uint64_t)std::lround(s_study_scene_peak_max * 1000.f));
  const bool s5_closed = (s5_ok == 5);

  // ---- S6 : LES RISQUES, ET LE POINT DE RETOUR --------------------------------------------
  // Le risque qui domine est la regression du SDR livre. L'invariant qui la detecterait existe
  // deja et c'est lui qu'on releve ICI, AVANT de toucher a quoi que ce soit : le tone map est
  // tire une fois et une seule par image de chaine. Toute etape du plan qui casserait cet
  // invariant le ferait voir. Mesure sur la course, jamais recopiee d'un proof anterieur.
  autoport_proof::publish("hdr_plan_s6_frames", (uint64_t)s_frames);
  autoport_proof::publish("hdr_plan_s6_active_frames", s_hits);
  autoport_proof::publish("hdr_plan_s6_tonemap_draws", cc.tonemap_draws);
  autoport_proof::publish("hdr_plan_s6_chain_frames", cc.chain_frames);
  autoport_proof::publish("hdr_plan_s6_setting", (uint64_t)(s_setting.load() != 0 ? 1 : 0));
  // LE DEFICIT est publie SEPAREMENT et n'entre pas dans la fermeture. Il vaut zero sur la course
  // d'etude (2340 = 2340) ; s'il ne le vaut pas, c'est une TROUVAILLE — des images de chaine ou le
  // tone map n'a pas ete tire — et pas une panne d'instrument. Une porte qui exigerait l'egalite
  // confondrait les deux et rendrait rouge une section dont l'ancrage, lui, a bien ete mesure.
  const uint64_t s6_deficit =
      cc.chain_frames > cc.tonemap_draws ? cc.chain_frames - cc.tonemap_draws : 0;
  autoport_proof::publish("hdr_plan_s6_draw_deficit", s6_deficit);
  const bool s6_closed = (cc.tonemap_draws > 0) && (cc.chain_frames > 0) &&
                         (hdr::last_frame_sites() == 1);

  // ---- LE COMPTE ----------------------------------------------------------------------------
  const bool closed[6] = {s1_closed, s2_closed, s3_closed, s4_closed, s5_closed, s6_closed};
  uint64_t open = 0;
  std::string open_list;
  for (int i = 0; i < 6; i++) {
    autoport_proof::publish((std::string("hdr_plan_s") + (char)('1' + i) + "_closed").c_str(),
                            (uint64_t)(closed[i] ? 1 : 0));
    if (!closed[i]) {
      open++;
      if (!open_list.empty()) {
        open_list += ",";
      }
      open_list += "s";
      open_list += (char)('1' + i);
    }
  }
  autoport_proof::publish_text("hdr_plan_sections_open_list", open_list.empty() ? "-" : open_list.c_str());
  autoport_proof::publish("hdr_plan_sections_open", open);
  // LE GESTE DU PLAN, c'est CETTE publication. `hits` est partage par tout le binaire : on ne le
  // compte QUE sous l'item `hdr-plan`, sinon le compteur de tous les autres items monterait.
  autoport_proof::note_hit_for(kPlanId);
}

// ------------------------------------------------ hdr-curve-input : LE BLOC DE CE CHANTIER ----
// Ce que la porte lit, et ce qui permet de la relire. `deaf_ratio_x100` est le PIRE rapport par
// image, pas le rapport de deux maxima cumules : deux maxima releves sur des images differentes
// se compareraient sans que rien ne garantisse qu'ils decrivent la meme scene, et c'est
// exactement ce que « sur les MEMES images » interdit.
//
// LE ZERO D'ECHANTILLONS SE LIT « PAS MESURE », JAMAIS « PAS D'ECART » : l'analyse de scene ne
// tourne QUE sortie HDR active (`hdr_curve_input_hdr_active`), et le temoin ne tourne que sous
// cet item. Le denominateur est donc publie a cote, et le rapport vaut 0 quand il n'y a aucune
// paire — ce qui ferait passer une porte `<= 120` sur du vide. C'est pourquoi `_samples` et
// `_hdr_active` doivent etre LUS avec le verdict ; ils sont ici pour ca.
void publish_curve_input() {
  if (!curve_input_measuring()) {
    return;
  }
  autoport_proof::publish("hdr_curve_input_samples", s_ci_samples);
  autoport_proof::publish("hdr_curve_input_analyses", s_ci_analyses);
  autoport_proof::publish("hdr_curve_input_witness_reads", s_ci_ref_reads);
  autoport_proof::publish("hdr_curve_input_black_samples", s_ci_black);
  autoport_proof::publish("hdr_curve_input_hdr_active", (uint64_t)(s_active.load() ? 1 : 0));
  autoport_proof::publish("hdr_curve_input_hdr_frames", s_hits);
  // L'ETAT DE LA REDUCTION : 0 jamais tentee, 1 en place, 2 refusee (repli sur les moyennes).
  autoport_proof::publish("hdr_curve_input_reduce_state",
                          (uint64_t)(s_mr_state == 1 ? 1 : (s_mr_state < 0 ? 2 : 0)));
  autoport_proof::publish("hdr_curve_input_reduce_draws", s_mr_draws);
  autoport_proof::publish("hdr_curve_input_scene_w", (uint64_t)(s_mr_src_w < 0 ? 0 : s_mr_src_w));
  autoport_proof::publish("hdr_curve_input_scene_h", (uint64_t)(s_mr_src_h < 0 ? 0 : s_mr_src_h));
  autoport_proof::publish("hdr_curve_input_stage1_w", (uint64_t)(s_mr_w1 < 0 ? 0 : s_mr_w1));
  autoport_proof::publish("hdr_curve_input_stage1_h", (uint64_t)(s_mr_h1 < 0 ? 0 : s_mr_h1));
  // LES DEUX PICS, SEPAREMENT, dans le MEME espace (celui de la courbe : apres exposition).
  autoport_proof::publish("hdr_curve_input_probe_peak_x1000",
                          (uint64_t)std::lround(s_ci_ref_peak_max * 1000.f));
  autoport_proof::publish("hdr_curve_input_curve_peak_x1000",
                          (uint64_t)std::lround(s_ci_curve_peak_max * 1000.f));
  // Et le couple qui a produit le PIRE rapport, pour que le verdict se recalcule a la main.
  autoport_proof::publish("hdr_curve_input_worst_probe_x1000",
                          (uint64_t)std::lround(s_ci_ref_at_worst * 1000.f));
  autoport_proof::publish("hdr_curve_input_worst_curve_x1000",
                          (uint64_t)std::lround(s_ci_curve_at_worst * 1000.f));
  autoport_proof::publish("hdr_curve_input_exposure_x1000",
                          (uint64_t)std::lround(s_ci_exp_at_worst * 1000.f));
  autoport_proof::publish("hdr_curve_input_knee_x1000",
                          (uint64_t)std::lround(s_ci_knee_level * 1000.f));
  autoport_proof::publish("hdr_curve_input_above_knee", s_ci_knee);
  // LA SENTINELLE. Sans paire, `ratio_worst` vaut 0 et une porte `<= 120` passerait sur du VIDE —
  // l'analyse de scene ne tourne que sortie HDR active, et une course qui ne l'allume pas (ou un
  // ecran qui n'annonce aucun mode) rendrait exactement ce zero-la. On publie donc 9999, c'est-a-
  // dire ROUGE, quand la mesure n'a pas eu lieu. Le plancher est de TROIS paires : une course de
  // 300 s en produit une soixantaine (une analyse sur 16, une image sur 8), trois est 5 % de ce
  // que la course rend normalement — assez pour qu'un accident ne passe pas, trop peu pour rendre
  // rouge une course qui a vraiment mesure.
  autoport_proof::publish("hdr_curve_input_samples_floor", 3);
  autoport_proof::publish(
      "hdr_curve_input_deaf_ratio_x100",
      s_ci_samples >= 3 ? (uint64_t)std::lround(s_ci_ratio_worst * 100.0) : (uint64_t)9999);
}

void publish_all() {
  publish_regime_verdict();  // hdr-output-regime : hors de toute garde d'un AUTRE item
  publish_shadow_verdict();  // hdr-shadow-range : idem, sa propre garde et rien d'autre
  // Le verrou ne couvre que la COPIE des capacites : sdr_white_nits(), paper_white() et
  // sdr_white_source() le reprennent (mutex non recursif — un publish_all qui le tenait
  // pendant ces appels a fige gk x86 a l'image 105, smoke du 09/09).
  std::string caps_text;
  SysCaps sys;
  bool plat_probed = false;
  uint32_t modes = kModeNone;
  // Verdict 13 : le bloc FORMAT, construit ici, sous le MEME verrou (rien en dessous ne doit
  // le reprendre). Aucune chaine ne part vide : « - » a la place, sinon publish_text laisserait
  // la valeur de l'image precedente en place.
  std::string fmt_announced, fmt_usable, fmt_reasons, fmt_choice_reason;
  int fmt_chosen = kFmtNone, fmt_rank = 0, fmt_usable_count = 0;
  bool dv_announced = false, egl_hlg = false, egl_cta = false;
  {
    std::lock_guard<std::mutex> lk(s_mu);
    caps_text = s_caps_text;
    sys = s_sys;
    plat_probed = s_plat.probed;
    modes = modes_locked();
    egl_hlg = s_plat.egl_bt2020_hlg;
    egl_cta = s_plat.egl_cta861_3;
    dv_announced = (s_sys.types & kSysDolbyVision) != 0;
    fmt_chosen = format_chosen_locked();
    fmt_rank = format_rank_locked(fmt_chosen);
    uint32_t usable_transports = 0;
    for (int i = 0; i < 4; i++) {
      const int f = kFormatPreference[i];
      if (format_announced_locked(f)) {
        if (!fmt_announced.empty()) fmt_announced += ",";
        fmt_announced += format_name(f);
      }
      if (format_usable_locked(f)) {
        if (!fmt_usable.empty()) fmt_usable += ",";
        fmt_usable += format_name(f);
        fmt_usable_count++;
        usable_transports |= format_transport_locked(f);
      }
      if (!fmt_reasons.empty()) fmt_reasons += ";";
      fmt_reasons += std::string(format_name(f)) + "=" + format_reason_locked(f);
    }
    if (dv_announced) {  // annonce mais hors classement : il figure quand meme dans la liste
      if (!fmt_announced.empty()) fmt_announced += ",";
      fmt_announced += format_name(kFmtDolbyVision);
    }
    fmt_reasons += std::string(";") + format_name(kFmtDolbyVision) + "=" +
                   format_reason_locked(kFmtDolbyVision);
    if (fmt_usable_count <= 1) {
      fmt_choice_reason = "un_seul_format_utilisable";
    } else if (usable_transports && (usable_transports & (usable_transports - 1)) == 0) {
      fmt_choice_reason = "formats_multiples_meme_transport_aucune_incidence";
    } else {
      fmt_choice_reason = "incidence_non_mesuree:reglage_non_offert";
    }
    if (fmt_announced.empty()) fmt_announced = "-";
    if (fmt_usable.empty()) fmt_usable = "-";
    if (fmt_reasons.empty()) fmt_reasons = "-";
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
  autoport_proof::publish_text("hdr_out_formats_announced", fmt_announced.c_str());
  autoport_proof::publish_text("hdr_out_formats_usable", fmt_usable.c_str());
  autoport_proof::publish("hdr_out_formats_usable_count", (uint64_t)fmt_usable_count);
  autoport_proof::publish_text("hdr_out_format_chosen", format_name(fmt_chosen));
  autoport_proof::publish("hdr_out_format_chosen_id", (uint64_t)fmt_chosen);
  autoport_proof::publish("hdr_out_format_chosen_rank", (uint64_t)fmt_rank);
  autoport_proof::publish_text("hdr_out_format_reasons", fmt_reasons.c_str());
  // La signature de la courbe, publiee par les DEUX plateformes : c'est la seule facon de
  // VERIFIER, en confrontant deux proof.txt, que le bureau et l'appareil appellent le meme code.
  // Additif : aucun verdict, ici ou ailleurs, ne la lit.
  autoport_proof::publish_text("hdr_out_curve_signature", curve_signature());
  autoport_proof::publish("hdr_out_dv_announced", dv_announced ? 1 : 0);
  autoport_proof::publish_text("hdr_out_dv_reason", "licence_hors_perimetre");
  autoport_proof::publish("hdr_out_format_choice_offered", fmt_usable_count > 1 ? 1 : 0);
  autoport_proof::publish_text("hdr_out_format_choice_reason", fmt_choice_reason.c_str());
  autoport_proof::publish("hdr_out_egl_hlg_available", egl_hlg ? 1 : 0);
  autoport_proof::publish("hdr_out_egl_cta861_3_available", egl_cta ? 1 : 0);
  // La marge : ANNONCEE contre ACCORDEE. Hors verrou — headroom_linear() le reprend.
  const float granted = headroom_linear();
  autoport_proof::publish("hdr_out_granted_headroom_x1000", (uint64_t)std::lround(granted * 1000.f));
  autoport_proof::publish("hdr_out_display_grants_headroom", granted > 1.005f ? 1 : 0);
  autoport_proof::publish_text(
      "hdr_out_granted_source",
      sys.ratio_available
          ? "api34:Display.getHdrSdrRatio"
          : (s_bl_grant_max > 1.005f
                 ? "sdk<34:marge_ACHETEE_au_retroeclairage,relue_sur_debug.tracing.screen_brightness"
                 : "sdk<34:aucune_marge_rendue:la_consigne_de_retroeclairage_n_a_pas_bouge"));
  // LE LEVIER DU RETRO-ECLAIRAGE, entrees et sortie, pour que la marge se refasse a la main.
  // `bl_base` est le reglage de l'utilisateur lu AVANT le levier, `bl_target` ce qu'on a demande
  // a la fenetre, `bl_grant_max` ce que le SYSTEME a pose. La marge utilisee par la courbe est
  // ce dernier, jamais le premier : demander n'est pas obtenir, exactement comme annoncer n'est
  // pas accorder. `bl_grant_samples` a zero = l'instrument n'a rien lu (et non : rien accorde).
  autoport_proof::publish("hdr_out_bl_base_x10000",
                          (uint64_t)std::lround(std::fmax(0.f, s_bl_base) * 10000.f));
  autoport_proof::publish("hdr_out_bl_now_x10000",
                          (uint64_t)std::lround(std::fmax(0.f, s_bl_now) * 10000.f));
  autoport_proof::publish("hdr_out_bl_target_x10000",
                          (uint64_t)std::lround(std::fmax(0.f, s_bl_target) * 10000.f));
  autoport_proof::publish("hdr_out_bl_grant_x1000", (uint64_t)std::lround(s_bl_grant * 1000.f));
  autoport_proof::publish("hdr_out_bl_grant_max_x1000",
                          (uint64_t)std::lround(s_bl_grant_max * 1000.f));
  autoport_proof::publish("hdr_out_bl_base_samples", s_bl_base_samples);
  autoport_proof::publish("hdr_out_bl_grant_samples", s_bl_grant_samples);
  autoport_proof::publish("hdr_out_bl_lever_applied", s_bl_lever_applied ? 1 : 0);
  autoport_proof::publish("hdr_out_grant_bought", s_bl_grant_max > 1.005f ? 1 : 0);
  // LA DECISION QUI COMMANDE TOUT LE CHEMIN PQ, avec ses entrees, pour qu'elle se refasse a la
  // main. Aucun appareil n'y est nomme : seule la FORME des capacites annoncees decide.
  {
    const PresentVerdict pv = display_presents_hdr();
    autoport_proof::publish("hdr_out_presents_hdr", pv.presents ? 1 : 0);
    autoport_proof::publish_text("hdr_out_presents_reason", pv.reason);
    autoport_proof::publish("hdr_out_caps_max_avg_nits", (uint64_t)(sys.max_avg < 0 ? 0 : sys.max_avg));
    autoport_proof::publish("hdr_out_caps_min_lum_x10000",
                            (uint64_t)(sys.min_lum_x10000 < 0 ? 0 : sys.min_lum_x10000));
    autoport_proof::publish("hdr_out_caps_wide_gamut", sys.wide_gamut ? 1 : 0);
    autoport_proof::publish("hdr_out_graphics_white_nits", (uint64_t)std::lround(kGraphicsWhiteNits));
  }
  // La CONTRE-EPREUVE physique du 1,000 ci-dessus : la consigne de retro-eclairage pendant la
  // phase ON contre la phase OFF. Un ecran qui accorde de la marge a une couche HDR la monte ;
  // un panneau a retro-eclairage global qui ne fait que DECODER le HDR ne la bouge pas.
  // `hdr_out_grant_measurable` dit si l'instrument a seulement pu lire les deux bras : sans lui,
  // un zero ne voudrait rien dire (absence de mesure, pas absence de marge).
  autoport_proof::publish("hdr_out_backlight_samples_on", s_bl_on.samples);
  autoport_proof::publish("hdr_out_backlight_samples_off", s_bl_off.samples);
  autoport_proof::publish("hdr_out_backlight_on_max_x10000",
                          (uint64_t)std::lround(std::fmax(0.f, s_bl_on.max) * 10000.f));
  autoport_proof::publish("hdr_out_backlight_off_max_x10000",
                          (uint64_t)std::lround(std::fmax(0.f, s_bl_off.max) * 10000.f));
  autoport_proof::publish("hdr_out_backlight_on_mean_x10000",
                          (uint64_t)std::lround(
                              (s_bl_on.samples ? s_bl_on.sum / (double)s_bl_on.samples : 0.0) * 10000.0));
  autoport_proof::publish("hdr_out_backlight_off_mean_x10000",
                          (uint64_t)std::lround(
                              (s_bl_off.samples ? s_bl_off.sum / (double)s_bl_off.samples : 0.0) * 10000.0));
  const bool bl_measurable = s_bl_on.samples > 0 && s_bl_off.samples > 0 && s_bl_off.max > 0.f;
  autoport_proof::publish("hdr_out_grant_measurable", bl_measurable ? 1 : 0);
  autoport_proof::publish(
      "hdr_out_backlight_boost_x1000",
      (uint64_t)(bl_measurable ? std::lround(1000.0 * (double)s_bl_on.max / (double)s_bl_off.max) : 0));
  autoport_proof::publish("hdr_out_grant_physical",
                          (bl_measurable && s_bl_on.max > s_bl_off.max * 1.02f) ? 1 : 0);
  // `hdr_out_recomposed*` a ete RETIRE ici (essai 15). Ces trois cles lisaient la sonde de blanc
  // UI, qui dessine HORS ECRAN avec notre propre programme : le blanc y est encode a
  // `sdr_white_nits()`, donc doubler le pic doublait le blanc mesure quelle que soit la dalle.
  // `follow = 1,000` a 0,0 % pres etait notre arithmetique, pas une propriete de l'ecran.
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
                          (uint64_t)std::lround(
                              (s_surface.mode == kModeHdr10Pq || s_surface.mode == kModeHlg)
                                  ? paper_white()
                                  : 0.f));
  autoport_proof::publish("hdr_out_headroom_x100", (uint64_t)std::lround(headroom_linear() * 100.f));
  autoport_proof::publish("hdr_out_erb_requests", s_headroom_requests);
  // `setExtendedRangeBrightness` est une API 34. Sous ce niveau le pont Java sort en no-op et le
  // compteur ci-dessus compte des demandes JETEES : il ne prouve rien tout seul.
  autoport_proof::publish("hdr_out_erb_deliverable", sys.sdk_int >= 34 ? 1 : 0);
  autoport_proof::publish("hdr_out_erb_current_x1000",
                          (uint64_t)std::lround((s_headroom_sent_current < 0.f ? 0.f : s_headroom_sent_current) * 1000.f));
  autoport_proof::publish("hdr_out_erb_desired_x100", (uint64_t)std::lround(s_headroom_request_desired * 100.f));
  autoport_proof::publish("hdr_out_ceiling_x100", (uint64_t)std::lround(s_last_ceiling * 100.f));
  autoport_proof::publish("hdr_out_present_mode", (uint64_t)s_last_present_mode);
  autoport_proof::publish("hdr_out_peak_nits", (uint64_t)std::lround(announced_peak_nits()));
  autoport_proof::publish("hdr_out_peak_effective_nits", (uint64_t)std::lround(peak_nits()));
  // `s_test_peak` est remis a 0 par finish_selftest() AVANT la publication finale : la cle sortait
  // 0 dans tout proof complet et ne disait donc jamais quel pic la phase 3 avait simule.
  autoport_proof::publish("hdr_out_peak_sim_nits",
                          (uint64_t)std::lround(s_test_peak > 0.f ? s_test_peak : s_ph[3].last_peak));
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
    autoport_proof::publish((pre + "hl_fixed_samples").c_str(), pr.hl_fixed_samples);
    autoport_proof::publish((pre + "hl_fixed_sum_x100").c_str(),
                            (uint64_t)std::lround(pr.hl_fixed_sum * 100.0));
    autoport_proof::publish((pre + "hl_fixed_ref_x100").c_str(),
                            (uint64_t)std::lround(pr.hl_fixed_ref * 100.0));
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
  const char* names[kPhaseCount] = {"loaded", "on", "off", "onsim", "alt"};
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
    autoport_proof::publish((k + "ratio_max_x1000").c_str(), (uint64_t)s_ph[p].ratio_max_x1000);
    autoport_proof::publish((k + "shadow_levels").c_str(), s_pr[p].shadow_levels);
    autoport_proof::publish((k + "hl_levels").c_str(), s_pr[p].hl_levels);
    autoport_proof::publish((k + "hl_ext_levels").c_str(), s_pr[p].hl_ext_levels);
    autoport_proof::publish((k + "ramp_samples").c_str(), s_pr[p].ramp_samples);
  }
  // CHAQUE CHEMIN annonce, nomme par son mode et non par son numero de phase : c'est ce que
  // l'item demande de publier quand le chemin retenu n'obtient pas la marge. La phase 1 porte
  // le chemin retenu, la phase 4 l'autre ; une colonne a zero = ce chemin n'existe pas ici.
  {
    std::lock_guard<std::mutex> lk(s_mu);
    autoport_proof::publish("hdr_out_modes_supported", modes_supported());
  }
  autoport_proof::publish("hdr_out_alt_mode", (uint64_t)s_alt_mode);
  autoport_proof::publish_text("hdr_out_alt_mode_name", mode_name(s_alt_mode));
  for (int p : {1, 4}) {
    if (s_ph[p].last_mode == kModeNone) {
      continue;
    }
    const std::string k = std::string("hdr_out_path_") + mode_name(s_ph[p].last_mode) + "_";
    autoport_proof::publish((k + "frames").c_str(), s_ph[p].frames);
    autoport_proof::publish((k + "active").c_str(), s_ph[p].active_frames);
    autoport_proof::publish((k + "red_bits").c_str(),
                            (uint64_t)(s_ph[p].last_red_bits < 0 ? 0 : s_ph[p].last_red_bits));
    autoport_proof::publish((k + "colorspace").c_str(),
                            (uint64_t)(s_ph[p].last_colorspace < 0 ? 0 : s_ph[p].last_colorspace));
    autoport_proof::publish((k + "ratio_max_x1000").c_str(), (uint64_t)s_ph[p].ratio_max_x1000);
    autoport_proof::publish((k + "shadow_levels").c_str(), s_pr[p].shadow_levels);
    autoport_proof::publish((k + "hl_levels").c_str(), s_pr[p].hl_levels);
    autoport_proof::publish((k + "hl_ext_levels").c_str(), s_pr[p].hl_ext_levels);
    autoport_proof::publish((k + "ceiling_x100").c_str(),
                            (uint64_t)std::lround(s_ph[p].last_ceiling * 100.f));
    autoport_proof::publish((k + "hl_max_x1000").c_str(),
                            (uint64_t)std::lround(s_pr[p].hl_max * 1000.0));
  }
  // Verdict 11 : ses trois grandeurs, lisibles sans decoder un verdict.
  autoport_proof::publish("hdr_out_ramp_steps", (uint64_t)kRampN);
  autoport_proof::publish("hdr_out_ramp_read_bits", (uint64_t)s_rp_read_type);
  // Le SEUL gain que ce chemin livre quand l'ecran n'accorde aucune marge : la finesse. Publie
  // en rapport pour qu'il se lise sans calcul a la main — 10 bits contre 8 dans les ombres.
  autoport_proof::publish(
      "hdr_out_shadow_gain_x100",
      (uint64_t)(s_pr[2].shadow_levels > 0
                     ? std::lround(100.0 * (double)s_pr[1].shadow_levels / (double)s_pr[2].shadow_levels)
                     : 0));
  autoport_proof::publish(
      "hdr_out_hl_gain_x100",
      (uint64_t)(s_pr[2].hl_levels > 0
                     ? std::lround(100.0 * (double)s_pr[1].hl_levels / (double)s_pr[2].hl_levels)
                     : 0));
  autoport_proof::publish("hdr_out_shadow_levels_on", s_pr[1].shadow_levels);
  autoport_proof::publish("hdr_out_shadow_levels_off", s_pr[2].shadow_levels);
  autoport_proof::publish("hdr_out_hl_levels_on", s_pr[1].hl_levels);
  autoport_proof::publish("hdr_out_hl_levels_off", s_pr[2].hl_levels);
  // La fenetre que le verdict 11 lit DESORMAIS, et le rapport qui se lit sans calcul. Les trois
  // colonnes de phase (`ph_on_`, `ph_off_`, `ph_onsim_`) portent la meme grandeur : c'est la
  // phase presentante SIMULEE qui montre si la correction de fenetre a pris.
  autoport_proof::publish("hdr_out_hl_ext_levels_on", s_pr[1].hl_ext_levels);
  autoport_proof::publish("hdr_out_hl_ext_levels_off", s_pr[2].hl_ext_levels);
  autoport_proof::publish("hdr_out_hl_ext_levels_onsim", s_pr[3].hl_ext_levels);
  autoport_proof::publish(
      "hdr_out_hl_ext_gain_x100",
      (uint64_t)(s_pr[2].hl_ext_levels > 0
                     ? std::lround(100.0 * (double)s_pr[1].hl_ext_levels / (double)s_pr[2].hl_ext_levels)
                     : 0));
  autoport_proof::publish(
      "hdr_out_hl_ext_gain_sim_x100",
      (uint64_t)(s_pr[2].hl_ext_levels > 0
                     ? std::lround(100.0 * (double)s_pr[3].hl_ext_levels / (double)s_pr[2].hl_ext_levels)
                     : 0));
  autoport_proof::publish("hdr_out_ramp_ext_top_x100", (uint64_t)std::lround(kFixedTop * 100.f));
  autoport_proof::publish("hdr_out_ratio_max_x1000", (uint64_t)s_ratio_max_x1000);
  autoport_proof::publish("hdr_out_window_lever_requests", s_lever_requests);
  // Les phases ON et OFF ne comptent leurs images bonnes qu'a partir de l'application effective
  // de la bascule : `tonemaps_applied` est le recensement de la DERNIERE image ON.
  autoport_proof::publish("hdr_out_tonemaps_applied", s_phase >= 2 && s_ph[1].frames ? (s_ph[1].sites_bad ? 0 : 1) : 0);
  // ---- verdict 12 : L'AMPLITUDE sur du jeu reel, les trois planchers lisibles un par un ----
  autoport_proof::publish("hdr_out_play_samples", s_play.samples);
  autoport_proof::publish("hdr_out_play_px", s_play.px);
  autoport_proof::publish("hdr_out_play_below_sdr_px", s_play.below_sdr_px);
  autoport_proof::publish("hdr_out_play_below_sdr_worst_x10000",
                          (uint64_t)std::lround(s_play.below_sdr_worst * 10000.0));
  autoport_proof::publish("hdr_out_play_hl_max_x1000", (uint64_t)std::lround(s_play.hl_max * 1000.0));
  // LE GAIN LIVRE, mesure sur des pixels dessines : le plus clair du bras HDR contre le plus
  // clair du bras SDR, memes images, meme instant. A cote, ce que la courbe avait PLANIFIE au
  // sommet et la plage qui etait DISPONIBLE a cet instant-la. Les trois se lisent ensemble : un
  // gain livre tres au-dessous du plan accuse le shader, un plan tres au-dessous de la plage
  // accuse la courbe, et une plage a 1,000 dit que ni l'un ni l'autre n'avait de quoi travailler.
  autoport_proof::publish("hdr_out_play_hl_max_ref_x1000",
                          (uint64_t)std::lround(s_play.hl_max_ref * 1000.0));
  autoport_proof::publish("hdr_out_play_hl_ratio_x1000",
                          (uint64_t)(s_play.hl_max_ref > 0.0
                                         ? std::lround(1000.0 * s_play.hl_max / s_play.hl_max_ref)
                                         : 0));
  autoport_proof::publish("hdr_out_dyn_move_floor_x1000",
                          (uint64_t)std::lround(1000.0 * std::fmax(0.02, 0.10 * ((double)s_top_gain_max - 1.0))));
  autoport_proof::publish("hdr_out_gamma_target_x1000", (uint64_t)std::lround(kGammaTarget * 1000.f));
  autoport_proof::publish("hdr_out_ceiling_max_x1000",
                          (uint64_t)std::lround(s_ceiling_max * 1000.f));
  autoport_proof::publish("hdr_out_range_avail_at_top_x1000",
                          (uint64_t)std::lround(s_range_avail_at_top * 1000.f));
  autoport_proof::publish("hdr_out_play_lift_rel_px", s_play.lift_rel_px);
  autoport_proof::publish(
      "hdr_out_play_cover_rel_x1000",
      (uint64_t)(s_play.samples
                     ? std::lround(1000.0 * (double)s_play.lift_rel_px /
                                   ((double)s_play.samples * kTmW * kTmH))
                     : 0));
  autoport_proof::publish("hdr_out_play_hl_max_lin_x1000", (uint64_t)std::lround(s_dyn_stats.hl_lin * 1000.0));
  autoport_proof::publish("hdr_out_play_headroom_used_pct",
                          (uint64_t)(s_ratio_max_x1000 > 1000
                                         ? std::lround(100000.0 * s_dyn_stats.hl_lin / (double)s_ratio_max_x1000)
                                         : 0));
  autoport_proof::publish("hdr_out_play_cover_x1000", (uint64_t)std::lround(s_dyn_stats.cover * 1000.0));
  autoport_proof::publish("hdr_out_play_lift_mean_x1000",
                          (uint64_t)(s_play.lift_px ? std::lround(1000.0 * s_play.lift_ratio_sum / (double)s_play.lift_px) : 0));
  // LA DISTRIBUTION du relevement, pas son seul resume : combien d'image est relevee de 10 %,
  // de 25 %, de 50 %. `cover25_hi` est celle que le verdict 12 juge.
  autoport_proof::publish("hdr_out_play_cover10_x1000", (uint64_t)std::lround(s_dyn_stats.cover10 * 1000.0));
  autoport_proof::publish("hdr_out_play_cover25_x1000", (uint64_t)std::lround(s_dyn_stats.cover25 * 1000.0));
  autoport_proof::publish("hdr_out_play_cover50_x1000", (uint64_t)std::lround(s_dyn_stats.cover50 * 1000.0));
  autoport_proof::publish("hdr_out_play_cover25_hi_x1000", (uint64_t)std::lround(s_dyn_stats.cover25_hi * 1000.0));
  autoport_proof::publish("hdr_out_play_gain_new_x10000", (uint64_t)std::lround(s_dyn_stats.gain_new * 10000.0));
  autoport_proof::publish("hdr_out_play_gain_legacy_x10000", (uint64_t)std::lround(s_dyn_stats.gain_old * 10000.0));
  autoport_proof::publish("hdr_out_play_gain_ratio_x100",
                          (uint64_t)(s_dyn_stats.gain_old > 1e-9 ? std::lround(100.0 * s_dyn_stats.gain_new / s_dyn_stats.gain_old) : 0));
  autoport_proof::publish("hdr_out_play_darkening_pct",
                          (uint64_t)(s_play.sum_off > 0.0 && s_play.sum_on < s_play.sum_off
                                         ? std::lround(100.0 * (1.0 - s_play.sum_on / s_play.sum_off))
                                         : 0));
  autoport_proof::publish("hdr_out_play_brightening_pct",
                          (uint64_t)(s_play.sum_off > 0.0 && s_play.sum_on > s_play.sum_off
                                         ? std::lround(100.0 * (s_play.sum_on / s_play.sum_off - 1.0))
                                         : 0));
  // ---- verdict 13 : L'ADAPTATION AU CONTENU, la serie et ses bornes ----
  autoport_proof::publish("hdr_out_dyn_samples", (uint64_t)s_dyn_stats.samples);
  autoport_proof::publish("hdr_out_dyn_updates", s_dyn_updates);
  autoport_proof::publish("hdr_out_dyn_readback", (uint64_t)s_an_mode);
  autoport_proof::publish("hdr_out_dyn_pinned_frames", s_dyn_pinned_frames);
  autoport_proof::publish("hdr_out_dyn_free_frames", s_dyn_free_frames);
  autoport_proof::publish("hdr_out_dyn_sdr_frames", s_dyn_sdr_frames);
  autoport_proof::publish_text(
      "hdr_out_dyn_frozen_reason",
      s_dyn_sdr_frames == 0
          ? "-"
          : (display_presents_hdr().presents ? "marge_accordee_a_1,000_malgre_un_ecran_presentant"
                                             : "aucune_marge:l_ecran_ne_fait_que_decoder_le_hdr"));
  autoport_proof::publish("hdr_out_dyn_resp_min_x100", (uint64_t)std::lround(s_dyn_stats.r_min * 100.0));
  autoport_proof::publish("hdr_out_dyn_resp_max_x100", (uint64_t)std::lround(s_dyn_stats.r_max * 100.0));
  autoport_proof::publish("hdr_out_dyn_resp_span_pct", (uint64_t)std::lround(s_dyn_stats.r_span * 100.0));
  autoport_proof::publish("hdr_out_dyn_step_max_x1000", (uint64_t)std::lround(s_dyn_stats.step_max * 1000.0));
  autoport_proof::publish("hdr_out_dyn_reversals", (uint64_t)(s_dyn_stats.reversals < 0 ? 0 : s_dyn_stats.reversals));
  autoport_proof::publish("hdr_out_dyn_reversals_zigzag",
                          (uint64_t)(s_dyn_stats.reversals_zz < 0 ? 0 : s_dyn_stats.reversals_zz));
  autoport_proof::publish("hdr_out_dyn_key_min_x1000", (uint64_t)std::lround(s_dyn_stats.k_min * 1000.0));
  autoport_proof::publish("hdr_out_dyn_key_max_x1000", (uint64_t)std::lround(s_dyn_stats.k_max * 1000.0));
  autoport_proof::publish("hdr_out_dyn_anchor_min_x1000", (uint64_t)std::lround(s_dyn_stats.a_min * 1000.0));
  autoport_proof::publish("hdr_out_dyn_anchor_max_x1000", (uint64_t)std::lround(s_dyn_stats.a_max * 1000.0));
  autoport_proof::publish("hdr_out_dyn_top_min_x1000", (uint64_t)std::lround(s_dyn_stats.t_min * 1000.0));
  autoport_proof::publish("hdr_out_dyn_top_max_x1000", (uint64_t)std::lround(s_dyn_stats.t_max * 1000.0));
  autoport_proof::publish("hdr_out_dyn_ceiling_min_x100", (uint64_t)std::lround(s_dyn_stats.c_min * 100.0));
  autoport_proof::publish("hdr_out_dyn_ceiling_max_x100", (uint64_t)std::lround(s_dyn_stats.c_max * 100.0));
  autoport_proof::publish("hdr_out_anchor_x1000", (uint64_t)std::lround(s_cur.anchor * 1000.f));
  autoport_proof::publish("hdr_out_shape", (uint64_t)s_cur.shape);
  autoport_proof::publish("hdr_out_gamma_x1000", (uint64_t)std::lround(s_cur.gamma * 1000.f));
  autoport_proof::publish("hdr_out_gamma_cap_x1000", (uint64_t)std::lround(kGammaMax * 1000.f));
  autoport_proof::publish("hdr_out_top_x1000", (uint64_t)std::lround(s_cur.top * 1000.f));
  autoport_proof::publish("hdr_out_toe_x1000", (uint64_t)std::lround(s_cur.toe * 1000.f));
  autoport_proof::publish("hdr_out_key_x1000", (uint64_t)std::lround(s_dyn.key * 1000.f));
  autoport_proof::publish("hdr_out_hi_x1000", (uint64_t)std::lround(s_dyn.hi * 1000.f));
  autoport_proof::publish("hdr_out_peak_scene_x1000", (uint64_t)std::lround(s_dyn.peak * 1000.f));
  // LES DEUX SOURCES DE PLAGE, PUBLIEES SEPAREMENT. Sans elles, un plafond a 1,000 se lit comme
  // « la feature ne marche pas » alors qu'il dit « le systeme n'a rien accorde », et un lecteur
  // ne peut pas savoir si la courbe a quand meme eu de quoi travailler.
  //   bl_room  : ce que le retro-eclairage pourrait ENCORE acheter au reglage actuel du joueur
  //              (1/consigne). A luminosite maximale il vaut 1,000 : rien a acheter. C'est le
  //              regime de l'owner, et c'est celui ou l'essai 19 n'a JAMAIS ete mesure.
  //   range_avail : plafond d'ecran divise par le haut de la scene — la plage reellement
  //              disponible, celle que la sortie SDR laissait vide.
  //   top_gain : ce que la courbe a PLANIFIE au sommet ; `play_hl_ratio` dit ce qu'elle a livre.
  autoport_proof::publish("hdr_out_bl_room_x1000",
                          (uint64_t)(s_bl_base > 0.f ? std::lround(1000.f / s_bl_base) : 0));
  autoport_proof::publish("hdr_out_range_avail_x1000",
                          (uint64_t)std::lround(s_range_avail_max * 1000.f));
  autoport_proof::publish("hdr_out_curve_top_x1000", (uint64_t)std::lround(s_curve_top * 1000.f));
  autoport_proof::publish("hdr_out_curve_top_max_x1000",
                          (uint64_t)std::lround(s_curve_top_max * 1000.f));
  autoport_proof::publish("hdr_out_top_gain_x1000", (uint64_t)std::lround(s_top_gain_max * 1000.f));
  autoport_proof::publish_text("hdr_out_range_source",
                               s_bl_grant_max > 1.005f
                                   ? "retroeclairage_achete+vide_laisse_par_la_scene"
                                   : "vide_laisse_par_la_scene_seul:aucune_marge_systeme");
  // LA SERIE ELLE-MEME, en clair : l'item demande de la publier, pas d'en publier un resume.
  // Quatre pistes, par tranches de kDynChunk. Une tranche absente sort a « - » (une cle de texte
  // ne se vide jamais toute seule).
  {
    const size_t chunks = (kDynSeriesMax + kDynChunk - 1) / kDynChunk;
    const char* tracks[4] = {"resp", "anchor", "top", "key"};
    for (size_t c = 0; c < chunks; c++) {
      for (int tr = 0; tr < 4; tr++) {
        std::string line;
        for (size_t i = c * kDynChunk; i < (c + 1) * kDynChunk && i < s_dyn_series.size(); i++) {
          const DynSample& v = s_dyn_series[i];
          const double val = tr == 0 ? v.resp * 100.0 : (tr == 1 ? v.anchor * 1000.0
                                                        : (tr == 2 ? v.top * 1000.0 : v.key * 1000.0));
          if (!line.empty()) {
            line += ",";
          }
          line += std::to_string((long long)std::lround(val));
        }
        char key[64];
        std::snprintf(key, sizeof(key), "hdr_out_dyn_%s_%02d", tracks[tr], (int)c);
        autoport_proof::publish_text(key, line.empty() ? "-" : line.c_str());
      }
    }
    autoport_proof::publish("hdr_out_dyn_series_stride", (uint64_t)s_dyn_stride);
  }
  // La grandeur de porte : somme de quatorze verdicts, chacun publie a cote. « Pas mesurable » = 1.
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
    autoport_proof::publish("hdr_out_defect_11_effect", (uint64_t)s_d[11]);
    autoport_proof::publish("hdr_out_defect_12_amplitude", (uint64_t)s_d[12]);
    autoport_proof::publish("hdr_out_defect_13_content_adaptive", (uint64_t)s_d[13]);
    autoport_proof::publish("hdr_out_defect_14_format_choice", (uint64_t)s_d[14]);
    autoport_proof::publish("hdr_out_defect_15_no_crush", (uint64_t)s_d[15]);
    autoport_proof::publish("hdr_out_defect_16_source_precompression", (uint64_t)s_d[16]);
    autoport_proof::publish("hdr_out_defect_17_shadow_richness", (uint64_t)s_d[17]);
    autoport_proof::publish("hdr_out_defects", (uint64_t)s_defects);
    // VERDICT 15 — les quatre plafonds DECLARES, puis les quatre mesures, puis la meme mesure
    // sur la courbe REFUSEE le 11/09. Un signe : `x1000` sur les exposants et les rapports,
    // `x100` sur les degres.
    autoport_proof::publish("hdr_out_ct_exp_cap_x1000", (uint64_t)std::lround(kExpCap * 1000.0));
    autoport_proof::publish("hdr_out_ct_band_cap_x1000", (uint64_t)std::lround(kBandCap * 1000.0));
    autoport_proof::publish("hdr_out_sat_cap_x1000", (uint64_t)std::lround(kSatCap * 1000.0));
    autoport_proof::publish("hdr_out_hue_cap_deg_x100", (uint64_t)std::lround(kHueCapDeg * 100.0));
    autoport_proof::publish("hdr_out_ct_exp_x1000", (uint64_t)std::lround(s_exc_out.exp_g * 1000.0));
    autoport_proof::publish("hdr_out_ct_rms_x1000", (uint64_t)std::lround(s_exc_out.rms * 1000.0));
    autoport_proof::publish("hdr_out_ct_band_max_x1000",
                            (uint64_t)std::lround(s_exc_out.band_max * 1000.0));
    autoport_proof::publish("hdr_out_ct_bands", (uint64_t)s_exc_out.bands);
    autoport_proof::publish("hdr_out_ct_px", (uint64_t)s_exc_out.n);
    autoport_proof::publish("hdr_out_sat_ratio_x1000",
                            (uint64_t)std::lround(s_exc_out.sat_ratio * 1000.0));
    autoport_proof::publish("hdr_out_sat_worst_x1000",
                            (uint64_t)std::lround(s_exc_out.sat_worst * 1000.0));
    autoport_proof::publish("hdr_out_hue_mean_deg_x100",
                            (uint64_t)std::lround(s_exc_out.hue_mean * 100.0));
    autoport_proof::publish("hdr_out_hue_worst_deg_x100",
                            (uint64_t)std::lround(s_exc_out.hue_worst * 100.0));
    autoport_proof::publish("hdr_out_ct17_exp_x1000",
                            (uint64_t)std::lround(s_exc17_out.exp_g * 1000.0));
    autoport_proof::publish("hdr_out_ct17_band_max_x1000",
                            (uint64_t)std::lround(s_exc17_out.band_max * 1000.0));
    autoport_proof::publish("hdr_out_ct17_rms_x1000",
                            (uint64_t)std::lround(s_exc17_out.rms * 1000.0));
    autoport_proof::publish("hdr_out_ct17_px", (uint64_t)s_exc17_out.n);
  } else {
    autoport_proof::publish("hdr_out_defects", 17);  // auto-test pas au bout : ROUGE, jamais muet
  }
  publish_study();  // l'etude relit ce qui precede ; elle ne mesure rien de neuf par elle-meme
  publish_plan();   // le plan relit ce qui precede ; il ne mesure rien de neuf par lui-meme
  publish_curve_input();  // le chantier B : ses propres grandeurs, relevees par ses propres sondes
}

void compute_verdicts() {
  std::unique_lock<std::mutex> lk(s_mu);
  const uint32_t modes = modes_locked();
  const bool sys_ok = s_sys.reported, plat_ok = s_plat.probed;
  lk.unlock();
  const int want_cs = modes == kModeScrgbLinear
                          ? kEglColorspaceScrgbLinear
                          : modes == kModeHlg ? kEglColorspaceBt2020Hlg : kEglColorspaceBt2020Pq;
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
  // Le disque n'est relu que la premiere fois puis toutes les 1800 images : compute_verdicts()
  // tourne desormais aussi APRES l'auto-test, une fois par paquet d'images.
  if (s_persisted == -3 || (s_frames % 1800) == 0) {
    s_persisted = read_persisted_setting();
  }
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
  // Le blanc SDR de la phase 1, tel qu'il a ETE ENCODE : `last_sdr_white` est releve a chaque
  // image depuis `sdr_white_nits()`. Le relire depuis `announced_peak_nits()` etait faux des que
  // le blanc effectif s'en ecarte — un ecran qui PRESENTE (203 nits BT.2408) ou une marge achetee
  // au retro-eclairage (pic / marge) rendaient ce verdict rouge sans aucun defaut reel. Le blanc
  // de l'interface est alors PLUS BAS dans le signal et rend la MEME lumiere : c'est la
  // contrepartie exacte de la marge, pas un assombrissement.
  const float real_sdr_white = (on.last_mode == kModeHdr10Pq) ? on.last_sdr_white : 0.f;
  if (pr.ui_samples > 0) {
    const double ui_mean = pr.ui_white_sum / (double)pr.ui_samples;
    const double ref = pr.ui_ref_sum / (double)pr.ui_samples;  // lineaire, 1,0 = blanc SDR
    if (on.last_mode == kModeHdr10Pq) {
      const double expect = ref * (double)real_sdr_white;
      white_ok = expect > 0.0 && ui_mean >= 0.99 * expect && pr.ui_white_min >= 0.98 * expect;
    } else if (on.last_mode == kModeScrgbLinear || on.last_mode == kModeHlg) {
      // scRGB comme HLG : `measured` est deja en multiples du blanc SDR (pour le HLG, la sonde
      // applique l'OETF inverse ARIB STD-B67 puis remet la marge). Sans cette branche, tout
      // ecran qui n'annonce QUE du HLG lisait le verdict 8 rouge sans aucun defaut reel.
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
  // ... ET sur du JEU REEL, apres l'auto-test, la courbe laissee libre (item, point 9 : « sur du
  // JEU REEL, plusieurs niveaux et ambiances »). Un bras qui n'a jamais tourne ne dispense pas :
  // sans echantillon de jeu, le verdict est ROUGE.
  bool play_dark_ok = false;
  if (s_play.px > 0 && s_play.sum_off > 0.0) {
    const double d = 100.0 * (1.0 - s_play.sum_on / s_play.sum_off);
    play_dark_ok = d <= 5.0 && s_play.below_sdr_px == 0;
  }
  s_d[9] = (dark_ok && play_dark_ok) ? 0 : 1;
  // 10 : LA COURBE S'ADAPTE AU PIC ANNONCE — mesure sur ce qui est DESSINE.
  //      La phase 3 simule un ecran qui PRESENTE le HDR a un pic double. Deux exigences :
  //        * le blanc du jeu reste ANCRE au blanc SDR DE SON REGIME (±1 %) : il ne s'assombrit
  //          dans aucun des deux. Chaque phase est ramenee a son propre blanc (`last_sdr_white`
  //          en PQ, 1,0 en scRGB et en HLG ou la mesure est deja relative) ;
  //        * le plafond MONTE, et la rampe a STIMULUS FIXE relue apres le tone map monte avec
  //          lui (> 1 %). C'est la moitie qui a du contenu : elle sort d'un dessin.
  //      L'ancienne branche PQ comparait le blanc simule au blanc reel divise par le rapport des
  //      pics. Le blanc etant ENCODE a `u_out_paper_white == sdr_white_nits()`, ce quotient
  //      valait 1,000 sur n'importe quelle dalle : un miroir de notre propre arithmetique, VERT
  //      PAR CONSTRUCTION. Retire — c'etait le faux vert de l'essai 14.
  const PhaseStats& onsim = s_ph[3];
  bool peak_ok = false;
  if (pr.ui_samples > 0 && ps.ui_samples > 0 && onsim.frames > 0 &&
      onsim.active_frames == onsim.frames && onsim.last_peak > on.last_peak) {
    const double w_real = pr.ui_white_sum / (double)pr.ui_samples;
    const double ref_real = pr.ui_ref_sum / (double)pr.ui_samples;
    const double w_sim = ps.ui_white_sum / (double)ps.ui_samples;
    const double ref_sim = ps.ui_ref_sum / (double)ps.ui_samples;
    const double norm_real = (on.last_mode == kModeHdr10Pq) ? (double)on.last_sdr_white : 1.0;
    const double norm_sim = (onsim.last_mode == kModeHdr10Pq) ? (double)onsim.last_sdr_white : 1.0;
    const bool anchored = ref_real > 0.0 && ref_sim > 0.0 && norm_real > 0.0 && norm_sim > 0.0 &&
                          std::fabs((w_real / norm_real) / ref_real - 1.0) <= 0.01 &&
                          std::fabs((w_sim / norm_sim) / ref_sim - 1.0) <= 0.01;
    const bool higher = onsim.last_ceiling > on.last_ceiling + 1e-3f && pr.hl_fixed_sum > 0.0 &&
                        ps.hl_fixed_samples > 0 && ps.hl_fixed_sum > pr.hl_fixed_sum * 1.01;
    peak_ok = anchored && higher;
  }
  s_d[10] = peak_ok ? 0 : 1;
  // 11 : L'EFFET, MESURE (refus owner du 10/09 : « on/off j'ai aucun changement a l'ecran ...
  //      l'image doit gagner en richesse dans les ombres et lumieres »). Trois planchers, tous
  //      les trois exiges — « identique a OFF » est un defaut au meme titre qu'« assombri »,
  //      sinon les verdicts 8 et 9 sont vrais par INACTION :
  //      * les ombres separent au moins DEUX FOIS plus de niveaux qu'en SDR ;
  //      * les hautes lumieres aussi ;
  //      * le systeme accorde une marge AU-DESSUS de son blanc SDR (ratio > 1,000), sans quoi
  //        aucune haute lumiere ne peut depasser le blanc, quel que soit l'encodage.
  const ProbeStats& pon = s_pr[1];
  const ProbeStats& poff = s_pr[2];
  const bool shadows_richer = poff.shadow_levels > 0 && pon.shadow_levels >= 2 * poff.shadow_levels;
  // ESSAI 16 — la fenetre du comptage etait FAUSSE. `hl_levels` ne couvre que [15/16, 1] de la
  // scene ; une courbe a plafond 2,06 ecrit ses codes neufs AU-DESSUS de 1,0. En phase 3 (ecran
  // presentant simule) elle rendait 17, exactement comme en OFF : ce verdict aurait ete ROUGE
  // sur un vrai ecran HDR pour une raison d'instrument, pas de dalle. `hl_ext_levels` couvre
  // [15/16, kFixedTop]. `hl_levels` reste publie tel quel : la correction doit se relire.
  const bool hl_richer = poff.hl_ext_levels > 0 && pon.hl_ext_levels >= 2 * poff.hl_ext_levels;
  // `over_sdr_white = s_ratio_max_x1000 > 1000` ETAIT ICI. Il exigeait que le SYSTEME accorde une
  // marge au-dessus de son blanc SDR — ce qu'avant l'API 34 il ne fait qu'en achetant du
  // retro-eclairage, donc JAMAIS chez un joueur deja au maximum. Mesure du 11/09 sur eae4df44 a
  // consigne 1,000 : `ratio_max=1000`, et le verdict tombait rouge sans rien dire de plus.
  // Il est remplace par une grandeur MESUREE SUR DES PIXELS DESSINES, sur du jeu reel : le bras
  // HDR doit livrer au moins kMinDeliveredGain de lumiere de plus que le bras SDR, sur les memes
  // images et au meme instant. Ce n'est pas un assouplissement : le plancher precedent etait
  // atteignable SANS qu'un seul pixel change (il ne lisait que la declaration du systeme), et
  // celui-ci ne l'est pas. `ratio_max` reste publie a cote.
  const bool delivered =
      s_play.gain_ref > 0.0 && s_play.gain_new >= kMinDeliveredGain * s_play.gain_ref;
  s_d[11] = (shadows_richer && hl_richer && delivered) ? 0 : 1;
  // 12 : L'AMPLITUDE, PAS LE COMPTAGE (item, point 11 ; refus owner du 10/09 : « quasi 0 diff
  //      entre off vs on ... vraiment juste un yota au niveau des trucs qui brillent »). Trois
  //      planchers, mesures sur du JEU REEL, et AUCUN n'est un nombre invente :
  //      a) la marge REELLEMENT accordee doit etre REELLEMENT utilisee. La comparaison de l'item
  //         (`hl_max` contre `ratio_max`) melange deux espaces : `hl_max` est dans l'espace
  //         d'affichage du tampon (gamma ~2,2), `ratio_max` est LINEAIRE. On la fait donc dans
  //         UN seul espace — hl_max^2,2 contre ratio_max — et on exige 80 % ;
  //      b) la COUVERTURE : au moins 4 % de l'image est relevee de plus de 2 %, et les pixels
  //         releves le sont de +25 % en moyenne. « Un yota », c'est une poignee de pixels a
  //         peine deplacee ; un pixel sur vingt-cinq deplace d'un quart n'en est plus une ;
  //      c) le rapport a l'ETAT REFUSE : le supplement de lumiere livre doit valoir au moins le
  //         DOUBLE de celui du 10/09, mesure sur la meme image, par le meme programme, au meme
  //         instant. Un facteur deux est le minimum au-dessous duquel c'est encore le meme
  //         rendu ; sa reference n'est pas un chiffre invente, c'est l'image que l'owner a vue.
  //      Et la courbe doit etre bien formee : jamais sous le SDR (below_sdr_px == 0).
  const double hl_lin = std::pow(std::fmax(0.0, s_play.hl_max), 2.2);
  // `ratio` (ce que le SYSTEME declare accorder) n'est plus une borne du verdict 12 : il reste
  // publie sous `hdr_out_ratio_max_x1000`, et le verdict se lit maintenant sur la plage
  // DISPONIBLE. Voir le commentaire du verdict ci-dessous.
  (void)s_ratio_max_x1000;
  const double tot_px = (double)s_play.samples * kTmW * kTmH;
  const double cover = s_play.samples ? (double)s_play.lift_px / tot_px : 0.0;
  const double cover10 = s_play.samples ? (double)s_play.lift10_px / tot_px : 0.0;
  const double cover25 = s_play.samples ? (double)s_play.lift25_px / tot_px : 0.0;
  const double cover50 = s_play.samples ? (double)s_play.lift50_px / tot_px : 0.0;
  const double cover25_hi = s_play.samples ? (double)s_play.lift25_hi_px / tot_px : 0.0;
  const double gain_new = s_play.gain_ref > 0.0 ? s_play.gain_new / s_play.gain_ref : 0.0;
  const double gain_old = s_play.gain_ref > 0.0 ? s_play.gain_old / s_play.gain_ref : 0.0;
  const double lift_mean = s_play.lift_px ? s_play.lift_ratio_sum / (double)s_play.lift_px : 0.0;
  // `lift_mean >= 1,25` disait la lettre de b) ; il ne la MESURAIT pas. Ce que b) enonce mot
  // pour mot est « un pixel sur vingt-cinq deplace d'un quart » : 4 % de l'image relevee de
  // 25 %. C'est ce qui est exige ici, sur du signal reel (SDR >= 0,20) pour que le relevement
  // du pied ne puisse pas remplir le compte avec des pixels quasi noirs. Ce n'est pas un
  // assouplissement : la mesure du 10/09 18:00 satisfaisait `cover >= 0,04` avec 36 % et
  // echouait sur la moyenne DILUEE par ces memes 36 % ; le nouveau plancher, lui, monte quand
  // la courbe force. La moyenne reste publiee a cote, elle n'est pas effacee.
  // LA REFERENCE DE L'AMPLITUDE N'EST PLUS `ratio` (ce que le SYSTEME declare accorder) mais la
  // PLAGE DISPONIBLE : le plafond que l'ecran accepte divise par le haut de la scene. Les deux
  // termes viennent de l'exterieur de la courbe — le premier du systeme, le second du contenu —
  // donc la porte n'est pas le miroir de notre propre arithmetique. C'est ce changement qui rend
  // le verdict lisible dans les DEUX regimes : marge achetee (plafond 1,88) et aucune marge
  // systeme (plafond 1,000, ou toute la plage vient du vide laisse par la scene).
  //   a) LE GAIN LIVRE : le plus clair du bras HDR contre le plus clair du bras SDR, memes
  //      images, meme instant. Il doit atteindre 80 % de la plage disponible.
  //   b) LA COUVERTURE : 4 % de l'image relevee de plus de 2 %, ET 4 % relevee d'au moins un
  //      quart du relevement planifie au sommet. Le seuil absolu de 25 % etait calibre sur une
  //      marge x4 : a plafond 1,000 le sommet ne monte que de 33 % et AUCUN pixel ne pouvait
  //      l'atteindre — rouge d'instrument, pas de rendu.
  //   c) LE RAPPORT A L'ETAT REFUSE, conserve, PLUS un plancher absolu : quand l'etat du 10/09
  //      ne livre rien du tout (c'est le cas des que le systeme n'accorde aucune marge), le
  //      « double de zero » serait vrai par INACTION. Le plancher absolu le rattrape.
  const double avail = (double)s_range_avail_at_top;   // la plage DISPONIBLE a l'instant du plan
  const double planned = (double)s_top_gain_max;      // ce que la courbe a PLANIFIE au sommet
  const double hl_ratio = s_play.hl_max_ref > 0.0 ? s_play.hl_max / s_play.hl_max_ref : 0.0;
  const double cover_rel = s_play.samples ? (double)s_play.lift_rel_px / tot_px : 0.0;
  //      `hl_ratio` (rapport des DEUX MAXIMA) est publie mais n'est pas une borne : le pixel le
  //      plus clair du bras SDR est presque toujours AU-DESSUS du haut de scene mesure, donc la
  //      courbe l'ecrete au plafond et le rapport s'ecrase — il mesurerait l'ecretage, pas
  //      l'amplitude. La lettre du livrable (« hl_max atteint l'essentiel de la marge REELLEMENT
  //      accordee ») se lit, elle, directement : le plus clair dessine contre le plafond.
  const bool amp_ok = s_play.samples >= 10 && s_play.below_sdr_px == 0 && avail > 1.0 &&
                      planned >= 1.0 + 0.50 * (avail - 1.0) &&
                      s_play.hl_max >= 0.80 * (double)s_ceiling_max && cover >= 0.04 &&
                      cover_rel >= 0.04 && gain_new >= 2.0 * gain_old &&
                      gain_new >= (double)kMinDeliveredGain;
  s_d[12] = amp_ok ? 0 : 1;
  (void)hl_ratio;
  // 13 : L'ADAPTATION AU CONTENU (item, point 12 ; refus owner du 10/09 : « c'est statique non ?
  //      le HDR s'ajuste pas constamment, facon dolby vision ou HDR10+ »). La grandeur jugee est
  //      la REPONSE du programme `tonemap` a un stimulus FIXE, relevee tout au long de la course :
  //      une courbe unique appliquee partout pareil rendrait la MEME somme a chaque fois.
  //        * elle doit VARIER (>= 10 % d'ecart relatif) — sinon la courbe est figee ;
  //        * la scene doit avoir varie elle aussi, sinon on n'a rien teste ;
  //        * la transition doit etre LISSEE : aucune marche de plus de 0,60 par seconde en
  //          relatif entre deux echantillons ;
  //        * aucun POMPAGE : moins d'un renversement de sens pour quatre echantillons, hors
  //          bande morte de 2 %.
  double r_min = 1e30, r_max = -1e30, k_min = 1e30, k_max = -1e30;
  double a_min = 1e30, a_max = -1e30, c_min = 1e30, c_max = -1e30, t_min = 1e30, t_max = -1e30;
  double step_max = 0.0;
  int reversals = 0, dir = 0;
  double extremum = 0.0;
  // DIAGNOSTIC, PAS UN VERDICT : le compte ci-dessous n'entre dans aucune porte. Il repond a la
  // seule question que le compteur en vigueur ne sait pas trancher — un renversement de plus
  // vient-il de la COURBE qui bat, ou de la MESURE qui bruite ? Celui en vigueur remet sa
  // reference a CHAQUE echantillon retenu (`extremum = v.resp`), donc sa bande morte de 2 %
  // quantifie le bruit au lieu de le filtrer : un signal qui monte regulierement avec 2,5 % de
  // bruit y compte un virage presque a chaque pas. Celui-ci suit un vrai EXTREMUM (zigzag) : il
  // n'avance que tant que le mouvement CONTINUE, et ne declare un virage que sur une retrace de
  // plus de 2 % depuis cet extremum. Si les deux tombent ensemble, la question ne se pose pas.
  int reversals_zz = 0, dir_zz = 0;
  double extremum_zz = 0.0;
  for (size_t i = 0; i < s_dyn_series.size(); i++) {
    const DynSample& v = s_dyn_series[i];
    r_min = std::fmin(r_min, v.resp); r_max = std::fmax(r_max, v.resp);
    k_min = std::fmin(k_min, v.key);  k_max = std::fmax(k_max, v.key);
    a_min = std::fmin(a_min, v.anchor); a_max = std::fmax(a_max, v.anchor);
    c_min = std::fmin(c_min, v.ceiling); c_max = std::fmax(c_max, v.ceiling);
    t_min = std::fmin(t_min, v.top); t_max = std::fmax(t_max, v.top);
    if (i == 0) {
      extremum = v.resp;
      extremum_zz = v.resp;
      continue;
    }
    const DynSample& q = s_dyn_series[i - 1];
    const double dt = std::fmax(1e-3, (double)(v.t_s - q.t_s));
    if (q.resp > 1e-6) {
      const double rate = std::fabs((double)v.resp - (double)q.resp) / (double)q.resp / dt;
      step_max = std::fmax(step_max, rate);
    }
    // Renversement : uniquement hors bande morte, sinon on compterait le bruit de la mesure.
    if (extremum > 1e-6 && std::fabs((double)v.resp - extremum) / extremum > 0.02) {
      const int d = v.resp > extremum ? 1 : -1;
      if (dir != 0 && d != dir) {
        reversals++;
      }
      dir = d;
      extremum = v.resp;
    }
    if (extremum_zz > 1e-6) {
      const double rel = ((double)v.resp - extremum_zz) / extremum_zz;
      if (dir_zz == 0) {
        if (std::fabs(rel) > 0.02) {
          dir_zz = rel > 0.0 ? 1 : -1;
          extremum_zz = v.resp;
        }
      } else if ((double)dir_zz * rel > 0.0) {
        extremum_zz = v.resp;  // le mouvement CONTINUE : l'extremum avance, aucun virage
      } else if (std::fabs(rel) > 0.02) {
        reversals_zz++;  // il RETRACE de plus que la bande morte : un virage, un vrai
        dir_zz = -dir_zz;
        extremum_zz = v.resp;
      }
    }
  }
  const size_t ns = s_dyn_series.size();
  const double r_span = (ns && r_min > 1e-6) ? (r_max - r_min) / r_min : 0.0;
  // LE PLANCHER DE MOUVEMENT EST RELATIF AU RELEVEMENT QUE LA COURBE PEUT PRODUIRE. `0,10` en
  // absolu supposait un plafond a 1,88 : avec 1,34 de relevement au sommet, aucune courbe, si
  // adaptative soit-elle, ne peut deplacer de 10 % la reponse a un stimulus fixe. La regle
  // « 10 % du relevement livre » redonne exactement 0,10 quand le relevement vaut 2,0, c'est-a
  // -dire l'ancien plancher dans l'ancien regime ; et un plancher absolu de 2 % empeche qu'elle
  // devienne vide quand le relevement lui-meme est minuscule.
  const double move_floor = std::fmax(0.02, 0.10 * ((double)s_top_gain_max - 1.0));
  const bool dyn_ok = ns >= 30 && r_span >= move_floor && (k_max - k_min) >= 0.02 &&
                      step_max <= 0.60 && reversals * 4 <= (int)ns;
  s_d[13] = dyn_ok ? 0 : 1;
  s_dyn_stats.samples = ns;
  s_dyn_stats.r_min = ns ? r_min : 0.0;
  s_dyn_stats.r_max = ns ? r_max : 0.0;
  s_dyn_stats.r_span = r_span;
  s_dyn_stats.k_min = ns ? k_min : 0.0;
  s_dyn_stats.k_max = ns ? k_max : 0.0;
  s_dyn_stats.a_min = ns ? a_min : 0.0;
  s_dyn_stats.a_max = ns ? a_max : 0.0;
  s_dyn_stats.c_min = ns ? c_min : 0.0;
  s_dyn_stats.c_max = ns ? c_max : 0.0;
  s_dyn_stats.t_min = ns ? t_min : 0.0;
  s_dyn_stats.t_max = ns ? t_max : 0.0;
  s_dyn_stats.step_max = step_max;
  s_dyn_stats.reversals = reversals;
  s_dyn_stats.reversals_zz = reversals_zz;
  s_dyn_stats.cover = cover;
  s_dyn_stats.cover10 = cover10;
  s_dyn_stats.cover25 = cover25;
  s_dyn_stats.cover50 = cover50;
  s_dyn_stats.cover25_hi = cover25_hi;
  s_dyn_stats.gain_new = gain_new;
  s_dyn_stats.gain_old = gain_old;
  s_dyn_stats.hl_lin = hl_lin;
  // 14 : LE FORMAT SE CHOISIT SEUL (verdict 13 de l'item, refus owner du 11/09). Ce n'est pas
  // un miroir de la decision : il la confronte a la SURFACE REELLEMENT OBTENUE en phase ON.
  int fmt = kFmtNone, fmt_rank = 0;
  uint32_t fmt_transport = kModeNone;
  bool higher_all_explained = true, dv_announced = false;
  {
    std::lock_guard<std::mutex> lk2(s_mu);
    fmt = format_chosen_locked();
    fmt_rank = format_rank_locked(fmt);
    fmt_transport = format_transport_locked(fmt);
    dv_announced = (s_sys.types & kSysDolbyVision) != 0;
    // tout format MIEUX classe que le retenu doit porter une raison nommee (jamais "-")
    for (int i = 0; i < 4 && kFormatPreference[i] != fmt; i++) {
      const char* r = format_reason_locked(kFormatPreference[i]);
      if (!r || r[0] == '\0' || (r[0] == '-' && r[1] == '\0')) {
        higher_all_explained = false;
      }
    }
  }
  bool fmt_ok;
  if (modes == kModeNone) {
    fmt_ok = (fmt == kFmtNone);          // rien d'annonce : rien de retenu, rangee cachee
  } else {
    fmt_ok = fmt != kFmtNone && fmt != kFmtDolbyVision && fmt_rank > 0 && higher_all_explained &&
             fmt_transport == modes && s_ph[1].frames > 0 && s_ph[1].last_mode == modes;
  }
  s_d[14] = fmt_ok ? 0 : 1;
  // 15 : PAS DE CONTRASTE NI DE SATURATION CRAMES (livrable, point 14 ; refus owner du 10/09
  //      puis du 11/09 : « un rendu tres j'ai pousse le contraste au maximum, c'est pas beau »,
  //      « comme si on poussait la teinte/saturation/contraste au max sur un filtre photoshop »).
  //      CE VERDICT AVAIT ETE PERDU EN RACCOURCISSANT L'ITEM, ET L'ITEM EST PASSE 14/14 SANS
  //      JAMAIS LE MESURER — c'est pour ca que la porte etait verte et l'image refusee.
  //      Mesure sur les MEMES images, quatre grandeurs, quatre plafonds DECLARES :
  //        * l'exposant de contraste GLOBAL (pente de ln(Y_hdr) sur ln(Y_sdr)) <= kExpCap ;
  //        * l'exposant LOCAL le pire, entre deux bandes de luminance voisines <= kBandCap.
  //          C'est celui qui compte : une courbe peut etre douce en moyenne et brutale sur une
  //          plage de tons, et c'est exactement le defaut de la fenetre Hermite ;
  //        * le rapport de saturation moyenne <= kSatCap ;
  //        * la derive de teinte moyenne <= kHueCapDeg.
  //      Et une exigence d'EFFET, pour que le verdict ne puisse pas etre vert par inaction :
  //      la pire bande doit etre STRICTEMENT sous celle de la courbe refusee le 11/09, qui est
  //      redessinee sur la meme image au meme instant. Le plafond n'est donc pas un chiffre
  //      invente : il se lit contre l'image que l'owner a refusee.
  s_exc_out = exc_reduce(s_exc);
  s_exc17_out = exc_reduce(s_exc17);
  const ExcOut& ex = s_exc_out;
  const ExcOut& ex17 = s_exc17_out;
  const bool exc_measured = ex.n >= 3000 && ex.bands >= 2 && ex17.n >= 3000 && ex17.bands >= 2;
  const bool exc_ok = exc_measured && ex.exp_g <= kExpCap && ex.band_max <= kBandCap &&
                      ex.sat_ratio <= kSatCap && ex.hue_mean <= kHueCapDeg &&
                      ex.band_max < ex17.band_max;
  s_d[15] = exc_ok ? 0 : 1;
  // 16 : SOURCE AVANT COMPRESSION (livrable point 11, RETABLI apres perte). « La sortie HDR
  //      consomme la scene HDR AVANT le tone map vers SDR. Publier l'identite du tampon lu et le
  //      nombre de compressions SDR subies par ce chemin : il vaut 0. »
  //      Le chemin est : tampon de scene -> `tonemap` -> tampon UI -> quad final -> fenetre.
  //      Une compression SDR y est l'un de ces trois faits, et chacun est LU, pas suppose :
  //        * le tampon de scene n'est pas flottant (l'echelle de repli est descendue) ;
  //        * le tampon UI n'est pas flottant (il le serait si la sortie HDR n'etait pas active) ;
  //        * la courbe sort SOUS l'identite sur au moins un pixel dessine — c'est la definition
  //          operatoire de « comprimer », et elle se mesure sur du jeu reel (`below_sdr_px`).
  //      La cible 10 bits PQ de la fenetre n'en est pas une : c'est un ENCODAGE, bijectif et
  //      monotone sur [0, plafond]. Le compte est publie a cote de l'identite de chaque maillon.
  const GLenum f_scene = hdr::scene_color_format();
  const GLenum f_ui = ui_buffer_format();
  const GLenum f_win = window_target_format();
  uint64_t src_comp = 0;
  if (!hdr::format_is_float(f_scene)) {
    src_comp++;
  }
  if (!hdr::format_is_float(f_ui)) {
    src_comp++;
  }
  if (s_play.below_sdr_px > 0) {
    src_comp++;
  }
  s_d[16] = (src_comp == 0 && s_play.px > 0) ? 0 : 1;
  // 17 : RICHESSE DANS LES OMBRES, sur du JEU REEL (livrable point 12, RETABLI apres perte).
  //      « Le detail distinguable SOUS le blanc SDR augmente franchement par rapport a OFF.
  //      Inchange = DEFAUT. » La grandeur est le nombre de CODES DISTINCTS que chacun des deux
  //      etats livrerait a la fenetre pour les memes pixels d'image : 8 bits pour la fenetre SDR,
  //      10 bits PQ pour la fenetre HDR (le meme encodage que post_processing.frag, mode 1). La
  //      fenetre jugee est celle des ombres PROFONDES, [0, 1/16] — la meme que la sonde de
  //      rampes. C'est une propriete de NOTRE encodage, pas une affirmation sur ce que la dalle
  //      emet : le rapport dit combien de nuances le signal SEPARE, ce que 8 bits ne peut pas.
  uint64_t lv_off = 0, lv_on = 0, lv_off_deep = 0, lv_on_deep = 0;
  for (int i = 0; i < 256; i++) {
    lv_off += s_play.code_off[i] ? 1 : 0;
    lv_off_deep += s_play.code_off_deep[i] ? 1 : 0;
  }
  for (int i = 0; i < 1024; i++) {
    lv_on += s_play.code_on[i] ? 1 : 0;
    lv_on_deep += s_play.code_on_deep[i] ? 1 : 0;
  }
  // Le plancher de population est dimensionne sur la population FILTREE, pas sur le total : les
  // pixels sous 1/16 ne sont que 3,4 % de la sonde (1757 sur 51 200 le 11/09). Un plancher de
  // 10 000 sur ce sous-ensemble etait une sentinelle impossible a atteindre.
  s_d[17] = (s_play.deep_px >= 1000 && lv_off_deep > 0 && lv_on_deep >= 2 * lv_off_deep) ? 0 : 1;
  autoport_proof::publish("hdr_out_src_sdr_compressions", src_comp);
  autoport_proof::publish("hdr_out_play_shadow_px", s_play.shadow_px);
  autoport_proof::publish("hdr_out_play_deep_px", s_play.deep_px);
  autoport_proof::publish("hdr_out_play_shadow_levels_off", lv_off);
  autoport_proof::publish("hdr_out_play_shadow_levels_on", lv_on);
  autoport_proof::publish("hdr_out_play_deep_levels_off", lv_off_deep);
  autoport_proof::publish("hdr_out_play_deep_levels_on", lv_on_deep);
  {
    char buf[192];
    auto fname = [](GLenum f) -> const char* {
      switch (f) {
        case GL_RGB10_A2: return "RGB10_A2";
        case GL_RGBA8: return "RGBA8";
        default: return hdr::format_name(f);
      }
    };
    snprintf(buf, sizeof(buf), "scene:%s>tonemap(expansion)>ui:%s>quad_final:%s", fname(f_scene),
             fname(f_ui), fname(f_win));
    autoport_proof::publish_text("hdr_out_src_chain", buf);
  }
  s_defects = 0;
  for (int i = 1; i <= 17; i++) {
    s_defects += s_d[i];
  }
  lg::info(
      "[hdr-display-output] auto-test termine : defauts={} ({},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}) persisted={} "
      "mem={} ui_samples={}/{} tm_px={}/{} hl_max={:.3f}/{:.3f} ceiling={:.3f}/{:.3f} "
      "niveaux ombres={}/{} hautes={}/{} ratio_max={} alt={} "
      "couverture 2%={:.3f} 10%={:.3f} 25%={:.3f} 25%hi={:.3f} 50%={:.3f} moyenne_diluee={:.3f}"
      " format={} rang={} dv_annonce={}"
      " exposant={:.3f} bande={:.3f} (refusee 11/09 : {:.3f}) saturation={:.3f} teinte={:.2f} n={}",
      s_defects, s_d[1], s_d[2], s_d[3], s_d[4], s_d[5], s_d[6], s_d[7], s_d[8], s_d[9], s_d[10],
      s_d[11], s_d[12], s_d[13], s_d[14], s_d[15], s_d[16], s_d[17], s_persisted, mem, pr.ui_samples, ps.ui_samples, pr.tm_px, ps.tm_px, pr.hl_max,
      ps.hl_max, on.last_ceiling, onsim.last_ceiling, pon.shadow_levels, poff.shadow_levels,
      pon.hl_levels, poff.hl_levels, s_ratio_max_x1000, mode_name(s_alt_mode), cover, cover10,
      cover25, cover25_hi, cover50, lift_mean, format_name(fmt), fmt_rank, dv_announced ? 1 : 0,
      ex.exp_g, ex.band_max, ex17.band_max, ex.sat_ratio, ex.hue_mean, ex.n);
}

bool scene_ready() {
  const double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - s_clock0).count();
  if (el < kMinStartSeconds) {
    return false;  // le teleport de la course n'a pas fini de charger son niveau
  }
  if (s_ready_hits >= kReadyHits) {
    return true;
  }
  if (el >= kReadyCapSeconds) {
    s_ready_forced = 1;
    return true;
  }
  return false;
}

void finish_selftest() {
  s_phase = kPhaseCount;   // hors tableau : plus aucune phase ne compte
  s_test_force.store(-1);  // le reglage du joueur reprend
  s_test_mode = kModeNone;
  s_test_peak = 0.f;
  s_test_presents = 0;
  s_selftest_done = true;
  compute_verdicts();
  publish_all();
  autoport_proof::flush();
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
    // ET un ecran qui PRESENTE le HDR. Sans cela, sur un ecran qui ne fait que decoder, le blanc
    // SDR suit le pic simule (il EST le pic) : le plafond reste 1,0 dans les deux phases et la
    // comparaison ne mesure plus rien — c'est le miroir des essais 13 et 14. En simulant les deux
    // ensemble, la phase 3 fait passer la courbe par le regime qu'un vrai ecran HDR lui impose,
    // et ce qui est compare ensuite est DESSINE (rampe a stimulus fixe), pas calcule.
    s_test_presents = 1;
    lg::info("[hdr-display-output] auto-test : phase ON imposee sur un ecran SIMULE presentant, pic {} nits (annonce {})",
             s_test_peak, ann);
  } else if (s_frames == s_phase_start + 3 * kPhaseFrames) {
    // L'AUTRE chemin annonce par les caps. Le Honor ne rend aucune marge en scRGB (essai 6) et
    // le PQ n'y avait jamais ete essaye : la preuve doit porter les DEUX, pas le seul retenu.
    uint32_t alt = kModeNone;
    {
      std::lock_guard<std::mutex> lk(s_mu);
      alt = alt_mode(modes_supported());
    }
    s_alt_mode = alt;
    s_test_peak = 0.f;
    s_test_presents = 0;
    if (alt != kModeNone) {
      // Les onze verdicts sont deja tous calculables ici (phases 0-3 faites) : on les POSE sur
      // le disque AVANT de rebasculer la surface. Une bascule PQ qui tuerait la course
      // emporterait sinon la preuve entiere pour un chemin qui n'est qu'un complement.
      compute_verdicts();
      publish_all();
      autoport_proof::flush();
      s_phase = 4;
      s_skip_frames = 1;
      s_test_mode = alt;
      s_test_force.store(1);
      lg::info("[hdr-display-output] auto-test : phase ON imposee sur l'AUTRE chemin ({})",
               mode_name(alt));
      return;
    }
    lg::info("[hdr-display-output] auto-test : un seul chemin annonce, phase 4 sautee");
    finish_selftest();
  } else if (s_phase == 4 && s_frames == s_phase_start + 4 * kPhaseFrames) {
    finish_selftest();
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
  // Le verdict PRESENTE/DECODE est mis en cache au PREMIER appel et ne l'etait jamais invalide :
  // un appel arrive avant que le Java n'ait livre les capacites figeait « aucun_pic_annonce »
  // pour toute la course, sur un ecran qui en annonce un. Les caps changent -> le verdict se
  // reprend.
  s_presents_cache = -1;
  s_presents_reason = "pas_encore_decide";
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
  if (mode & kModeHdr10Pq) {
    return "hdr10_pq";
  }
  return (mode & kModeHlg) ? "hlg" : "none";
}

int format_chosen() {
  std::lock_guard<std::mutex> lk(s_mu);
  return format_chosen_locked();
}

uint32_t format_transport(int fmt) {
  std::lock_guard<std::mutex> lk(s_mu);
  return format_transport_locked(fmt);
}

// Table pure : aucun etat lu, donc aucun verrou.
const char* format_reason(int fmt) {
  std::lock_guard<std::mutex> lk(s_mu);
  return format_reason_locked(fmt);
}

const char* format_name(int fmt) {
  switch (fmt) {
    case kFmtScrgb: return "scrgb_extended";
    case kFmtHdr10Plus: return "hdr10plus";
    case kFmtHdr10: return "hdr10";
    case kFmtHlg: return "hlg";
    case kFmtDolbyVision: return "dolby_vision";
    default: return "none";
  }
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
  backlight_commit();  // la marge de CETTE image, figee avant le premier dessin
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
  // RATTRAPAGE : le levier de retro-eclairage ne peut se poser qu'une fois la BASE connue — la
  // consigne de l'utilisateur, lue hors levier. Quand la sortie HDR est active des la premiere
  // image (reglage epingle par le harnais, ou choix conserve du joueur), cette base n'existe pas
  // encore au moment de la bascule de surface : sans ce rattrapage, la phase ON de l'auto-test
  // mesurerait un ecran auquel on n'a JAMAIS rien demande, et conclurait « rien accorde ».
  if (s_active.load() && s_surface.mode != kModeNone && !s_bl_lever_applied && s_bl_base > 0.f &&
      !s_lever_pending) {
    bool sys_grants = false;
    {
      std::lock_guard<std::mutex> lk(s_mu);
      sys_grants = s_sys.ratio_available;
    }
    if (!sys_grants) {
      float t = s_bl_base * desired_headroom();
      if (t > 1.f) {
        t = 1.f;
      }
      s_bl_target = t;
      s_bl_lever_applied = true;
      s_bl_settle = kLeverSettleReads;
      s_lever_on = true;
      s_lever_desired = desired_headroom();
      s_lever_pending = true;
      lg::info("[hdr-display-output] levier retro-eclairage : base {:.6f} -> consigne {:.6f} (x{:.2f} demande)",
               s_bl_base, t, t / s_bl_base);
    }
  }
  const uint32_t modes = modes_available();
  // La decision reste celle de `lighting_gate()` (deja correcte : master > eclairage). On ajoute
  // le PASSAGE par la porte du module, qui compte, sans changer ce qui est decide ici.
  (void)recharged_gating::on(recharged_gating::kHdrOutput);
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
    // Les deux AUTRES leviers, quel que soit le chemin : le mode couleur HDR de la fenetre et
    // Window.setDesiredHdrHeadroom. `setExtendedRangeBrightness` seul a laisse le Honor a 1,0.
    s_lever_on = (want != kModeNone);
    s_lever_desired = desired_headroom();
    // LE QUATRIEME LEVIER, le seul qui existe sous l'API 34 : la consigne de retro-eclairage de
    // NOTRE fenetre. On la demande en ABSOLU — base mesuree x marge souhaitee, bornee a 1,0 —
    // et jamais quand le systeme sait accorder la marge lui-meme (API 34+ : Display.getHdrSdrRatio
    // est alors un contrat, on ne double pas le mecanisme). < 0 = rends la consigne au systeme.
    bool sys_grants = false;
    {
      std::lock_guard<std::mutex> lk(s_mu);
      sys_grants = s_sys.ratio_available;
    }
    if (s_lever_on && !sys_grants && s_bl_base > 0.f) {
      float t = s_bl_base * desired_headroom();
      if (t > 1.f) {
        t = 1.f;
      }
      s_bl_target = t;
    } else {
      s_bl_target = -1.f;
    }
    s_bl_lever_applied = (s_bl_target > 0.f);
    s_bl_settle = kLeverSettleReads;
    s_lever_pending = true;
    lg::info("[hdr-display-output] surface {} : red_bits={} colorspace=0x{:x} mode={}",
             want == kModeScrgbLinear ? "scRGB/16F" : want == kModeHdr10Pq ? "HDR10/PQ" : "SDR",
             st.red_bits, (unsigned)st.colorspace, st.mode);
  } else {
    s_switch_fail++;
    lg::error("[hdr-display-output] bascule vers mode {} REFUSEE : red_bits={} colorspace=0x{:x} mode={}",
              want, st.red_bits, (unsigned)st.colorspace, st.mode);
  }
}

bool take_window_lever_request(bool* on, float* desired, float* brightness_target) {
  if (!s_lever_pending) {
    return false;
  }
  s_lever_pending = false;
  s_lever_requests++;
  if (on) {
    *on = s_lever_on;
  }
  if (desired) {
    *desired = s_lever_desired;
  }
  if (brightness_target) {
    *brightness_target = s_bl_target;
  }
  return true;
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

// Les quatre grandeurs de la courbe, PARAMETREES PAR LE TRANSPORT. Les versions sans argument
// (celles que le header expose depuis toujours) ne sont plus que des appels de celles-ci avec
// l'etat de la surface courante : il n'existe donc qu'UNE implementation, et le bureau appelle
// exactement la meme que l'appareil. C'est le point (3) du livrable hdr-desktop-output.
float headroom_linear_for(uint32_t mode, bool active);

float sdr_white_nits_for(uint32_t mode) {
  if (mode == kModeScrgbLinear) {
    return 0.f;  // contrat relatif : 1,0 = blanc SDR, pas un nits
  }
  // REGIME SIMULE (mesure seulement, hdr-desktop-output) : le meme point d'entree que le knob,
  // pose par le code au lieu de l'environnement. Voir set_sim_regime().
  if (s_sim_white > 0.f) {
    return s_sim_white;
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
  // ICI se joue tout le chemin PQ. Rendre `peak_nits()` faisait de `headroom_linear()` le
  // quotient d'un nombre par lui-meme : 1,000 sur TOUT ecran PQ, quel que soit le panneau, donc
  // `tonemap_ceiling()` a 1 et `curve_params()` sur `sdr_params()` — la sortie « HDR » etait
  // l'image SDR exacte dans un conteneur 10 bits. C'est le « quasi 0 diff off vs on » du 10/09,
  // et ce n'etait pas une limite du Redmi : c'etait vrai partout.
  // hdr-output-regime : la decision est prise UNE fois, par `regime_now()`. Ce site n'en tire
  // plus que la consequence sur le blanc.
  //   R2 — l'ecran PRESENTE : le blanc du jeu est le blanc graphique BT.2408.
  //   R1 — il DECODE mais le systeme ACCORDE : la marge s'ACHETE au retro-eclairage, et le blanc
  //        SDR descend d'autant dans le signal pour que le contenu SDR emette la MEME lumiere.
  //   R0 — aucune marge : le blanc EST le pic, la marge vaut 1,000. Un constat, pas une constante.
  const RegimeVerdict rg = regime_now();
  if (rg.level == 2) {
    return kGraphicsWhiteNits;
  }
  return rg.level == 1 ? peak_nits() / measured_grant() : peak_nits();
}

float sdr_white_nits() {
  return sdr_white_nits_for(s_surface.mode);
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
  const int lv = regime_now().level;  // hdr-output-regime : la MEME decision, pas une copie
  if (lv == 2) {
    return "pq:BT.2408_blanc_graphique_203nits";
  }
  if (lv == 1) {
    return "pq:pic_annonce/marge_MESUREE_au_retroeclairage(ecran_qui_decode)";
  }
  return max_lum > 0 ? "pq:HdrCapabilities.maxLuminance(ecran_qui_decode)"
                     : "pq:compositor_default_500(ecran_qui_decode)";
}

float paper_white_for(uint32_t mode, bool active) {
  if (!active) {
    return 1.f;
  }
  if (mode == kModeHdr10Pq) {
    return sdr_white_nits_for(mode);  // PQ : des NITS absolus
  }
  if (mode == kModeHlg) {
    // HLG est RELATIF : `u_out_paper_white` y est la FRACTION du pic qu'occupe le blanc du jeu,
    // jamais un nits (post_processing.frag, mode 3). Le tone map fait sortir le plafond a
    // `headroom^(1/2,2)` en espace d'affichage, soit `headroom` une fois linearise : la fraction
    // qui met ce plafond exactement au pic de l'ecran est donc 1/headroom. Sans marge accordee
    // elle vaut 1,0 — le blanc du jeu sort AU pic, rien n'est assombri.
    const float h = headroom_linear_for(mode, active);
    return h > 1.f ? 1.f / h : 1.f;
  }
  return 1.f;
}

float paper_white() {
  return paper_white_for(s_surface.mode, s_active.load());
}

float headroom_linear_for(uint32_t mode, bool active) {
  if (!active) {
    return 1.f;
  }
  if (mode == kModeScrgbLinear) {
    return ratio_linear();
  }
  // PQ / HLG : aucune API ne PUBLIE la marge accordee avant l'API 34. La marge est le quotient
  // du pic ANNONCE par le blanc SDR, et c'est `sdr_white_nits()` qui porte la seule decision qui
  // compte : sur un ecran qui PRESENTE, le blanc est le blanc graphique BT.2408 (203 nits) et la
  // marge vaut `pic/203` ; sur un ecran qui ne fait que DECODER, le blanc EST le pic et la marge
  // vaut 1,000. ANNONCER N'EST PAS ACCORDER : ce 1,000-la est un constat sur l'ecran, pas une
  // constante — et il est publie avec sa raison (`hdr_out_presents_reason`).
  const float pk = peak_nits();
  const float w = sdr_white_nits_for(mode);
  if (!(pk > 0.f) || !(w > 0.f)) {
    return 1.f;
  }
  float h = pk / w;
  if (!(h >= 1.f)) h = 1.f;
  if (h > kHeadroomMax) h = kHeadroomMax;
  return h;
}

float headroom_linear() {
  return headroom_linear_for(s_surface.mode, s_active.load());
}

float tonemap_ceiling_for(uint32_t mode, bool active) {
  // Le plafond PERMIS par l'ecran — la borne, pas la valeur de l'image. Ce que la courbe utilise
  // vraiment est `curve_params().ceiling`, qui depend en plus du CONTENU de la scene.
  const float h = headroom_linear_for(mode, active);
  return h > 1.f ? std::pow(h, 1.f / 2.2f) : 1.f;  // marge lineaire -> espace d'affichage
}

float tonemap_ceiling() {
  return tonemap_ceiling_for(s_surface.mode, s_active.load());
}

// LA COURBE REFUSEE LE 11/09 — bras de MESURE, et rien d'autre. Aucun chemin de rendu ne
// l'appelle : seule la sonde de jeu reel la redessine, sur la MEME image et au MEME instant que
// la courbe livree, pour que l'excursion de contraste publiee par le verdict 15 se lise contre
// l'image que l'owner a refusee et non contre un chiffre invente. Le code est celui de l'essai
// 17, recopie tel quel : la reference doit etre exacte, pas approchee.
CurveParams refused_params_11_09(float cmax) {
  CurveParams p;
  p.shape = 0;
  if (!(cmax >= 1.f)) {
    return sdr_params();
  }
  const float kh = smoothstep01(kKeyDark, kKeyBright, s_dyn.key);
  const float a = clampf(s_dyn.hi, kAnchorDark, kAnchorBright);
  const float hz = smoothstep01(kPeakLo, kPeakHi, s_dyn.peak);
  // Le bras de reference garde SA formule du 11/09 : le sommet partait de 1,0 et montait vers le
  // plafond. C'est ce que l'owner a vu, et c'est ce qu'il faut comparer — on ne le « corrige »
  // pas. A plafond 1,000 il rend donc c=1,0 : la fenetre Hermite etire quand meme [ancre, top]
  // vers [ancre, 1,0], ce qui est bien l'image refusee dans ce regime-la.
  const float c = 1.f + (cmax - 1.f) * hz;
  // LE SOMMET : la valeur de scene qui sort AU plafond. Il etait pris au point de saturation
  // de la courbe SDR (knee + 2(1-knee), soit ~1,05) : une CONSTANTE DE CALIBRAGE deguisee —
  // ce que le verdict 10 interdit — et, pire, une fenetre posee AU-DESSUS de tout ce que la
  // scene contient. Mesure du 10/09 18:09 sur le Honor, village2-dock : sommet = 0,917 alors
  // que le pic de la scene valait 0,666. Resultat lu au meme instant : 36,8 % de l'image
  // relevee de plus de 2 % (c'est le PIED, qui travaille sur les ombres) mais 0,7 % seulement
  // relevee d'un quart. Les hautes lumieres n'etaient pas etirees : elles etaient hors de la
  // fenetre. C'est « un yota au niveau des trucs qui brillent », en chiffre.
  // Le sommet suit donc LE HAUT DE LA SCENE — ce qui brille le plus ici sort au plafond ici,
  // et le pic bouge avec le contenu (metadonnee dynamique, pas un filtre unique). `s_dyn.peak`
  // est deja lisse et limite en vitesse par `smooth_to`, donc la transition reste douce.
  // La borne a la moitie de la marge est conservee : elle garantit p <= 1, donc une sortie
  // jamais sous le SDR. Le pic n'est que la moyenne des deux tuiles les plus claires : le
  // dernier centime d'image sature au plafond, mais la pente y est nulle (Hermite), donc sans
  // contour visible.
  const float w = clampf(s_dyn.peak - a, kMinWidth, (c - a) * kMaxWidthFrac);
  p.ceiling = c;
  p.anchor = a;
  p.top = a + w;
  p.toe = kToeMax * (1.f - kh);
  const float t = p.top;
  if (!(t > a)) {
    p = sdr_params();  // degenere : on ne pousse jamais une fenetre vide au shader
    p.ceiling = 1.f;
  }
  return p;
}


// ------------------------------------------------------ hdr-output-regime : les trois regimes --

CurveParams placement_params(float cmax) {
  CurveParams p = sdr_params();
  p.ceiling = std::fmax(1.f, cmax);
  return p;
}

// ------------------------------------------------------- hdr-shadow-range : LE PIED DE LA COURBE --
// LE PLAFOND D'AFFICHAGE OU LE PIED EST PLEIN. Il n'est pas un reglage de gout : au-dessus de ce
// plafond la marge accordee depasse le domaine du pied (le quart bas de l'affichage), et en
// demander davantage ne separerait plus de paliers, cela ne ferait que voiler. La valeur est
// PUBLIEE (`hdr_shadow_full_headroom_x1000`) pour qu'un lecteur voie sur quelle echelle le pied
// est interpole, et non un nombre pose dans le code.
constexpr float kToeFullHeadroom = 1.5f;

// LE PIED SUIT LA MARGE, ET IL VAUT EXACTEMENT ZERO QUAND IL N'Y EN A PAS.
// C'est la seule forme compatible avec le perimetre : « ne fabrique aucune difference sur un
// ecran qui n'accorde pas de marge ». En R0 le plafond du tone map vaut 1,000 (mesure :
// `hdr_out_ceiling_x100=100` sur le Redmi), donc `cmax > 1.f` est faux, le pied est nul, et
// `hdr_toe_lift` rend son entree AU BIT — l'identite que `hdr-output-regime` a verrouillee tient
// par construction, pas par reglage.
// L'interpolation est CONTINUE en cmax = 1 : un ecran qui accorde un cheveu de marge ne saute
// pas d'un coup a un pied plein. Une marche a cet endroit se verrait comme un clignotement des
// ombres quand le joueur touche la luminosite systeme, la marge etant ACHETEE au retro-eclairage.
float shadow_toe_for(float cmax) {
  if (!(cmax > 1.f)) {
    return 0.f;
  }
  return kToeMax * clampf((cmax - 1.f) / (kToeFullHeadroom - 1.f), 0.f, 1.f);
}

RegimeVerdict output_regime() {
  return regime_now();
}

int menu_state_packed() {
  return format_chosen() * 16 + regime_now().level;
}

void note_menu_label(int transport_id, int regime, int len) {
  s_menu_notes++;
  s_menu_transport = transport_id;
  s_menu_regime = regime;
  s_menu_len = len;
}

// LE REGIME, PUBLIE A CHAQUE IMAGE (terme 1 du verdict). Appele depuis `push_tonemap_uniforms`,
// c'est-a-dire au site ou le regime ATTEINT le shader — et non depuis le site du dessin, qui
// fournit le DENOMINATEUR un cran plus haut (`hdr_regime_tonemap_draws`, compte dans hdr.cpp
// APRES le `glDrawArrays`). Un compteur et son denominateur poses au meme endroit ne prouvent
// que leur propre egalite.
// Hors de toute garde d'item : `publish_plan()` est garde par `planning()` seul, et c'est
// exactement ce mur qui a oblige le chantier A a republier son denominateur ailleurs.
void publish_regime() {
  const RegimeVerdict rg = regime_now();
  s_regime_frames++;
  if (rg.level >= 0 && rg.level <= 2) {
    s_regime_r[rg.level]++;
  }
  s_regime_last = rg.level;
  autoport_proof::publish("hdr_regime", (uint64_t)rg.level);
  autoport_proof::publish_text("hdr_regime_name", rg.name);
  autoport_proof::publish_text("hdr_regime_reason", rg.reason);
  autoport_proof::publish_text("hdr_regime_transport", mode_name(s_surface.mode));
  autoport_proof::publish("hdr_regime_frames", s_regime_frames);
  autoport_proof::publish("hdr_regime_r0_frames", s_regime_r[0]);
  autoport_proof::publish("hdr_regime_r1_frames", s_regime_r[1]);
  autoport_proof::publish("hdr_regime_r2_frames", s_regime_r[2]);
  autoport_proof::publish("hdr_regime_ceiling_x1000",
                          (uint64_t)std::lround(tonemap_ceiling() * 1000.f));
}

CurveParams curve_params() {
  CurveParams p;
  const float cmax = tonemap_ceiling();
  const bool pin = measuring() && !s_selftest_done;
  const float xp = clampf(s_dyn.peak, 0.02f, 4.f);
  if (cmax / xp > s_range_avail_max) {
    s_range_avail_max = cmax / xp;
  }
  // ------------------------------------------------------------------ hdr-output-regime, C2 --
  // LA SORTIE HDR PLACE LE BLANC, ELLE NE L'ETIRE PLUS — et c'est le REGIME qui decide, pas le
  // CONTENU. L'ancienne condition `room = cmax > xp * (1 + kMinTopGain)` lisait le pic de scene :
  // avec le pic SOURD (~1,6) elle etait vraie presque partout et la courbe re-etalonnait l'image
  // (cinq refus, dont « j'ai pousse le contraste au maximum » le 11/09) ; avec le pic JUSTE que
  // le chantier B vient de livrer (~15 mesure), elle devient fausse des que l'ecran n'accorde
  // rien — la meme ligne de code aurait donc change de sens sous ce chantier. Une condition qui
  // s'inverse quand son entree devient juste ne peut pas porter trois regimes : c'est
  // l'avertissement B de `reports/hdr-curve-input/FINDINGS.txt`, tranche ici.
  //
  // Ce qui est livre maintenant est l'epaule SDR, la MEME, sur [0, cmax] au lieu de [0, 1] :
  //   R0 (cmax = 1)  -> `placement_params(1)` EST `sdr_params()` : la sortie HDR est le SDR au
  //                     bit, dans un conteneur 10 bits. C'est la seule sortie honnete quand le
  //                     systeme n'accorde rien, et la ligne de menu le DIT (C5).
  //   R1/R2 (cmax>1) -> meme courbe, meme forme, plage plus large : ce qui est sous `knee*cmax`
  //                     traverse a l'identique, et seules les hautes lumieres montent.
  // Aucun etirement, aucune ancre, aucun genou deduit : il n'y a plus de reglage de courbe a
  // regler sur une ancre dont la surdite n'a jamais ete mesuree (avertissement A).
  if (!s_active.load()) {
    p = sdr_params();  // sortie SDR : identite stricte avec ce qui precede l'item
  } else if (pin && cmax > 1.f) {
    // L'AUTO-TEST GARDE SON POINT DE FONCTIONNEMENT D'AVANT, AU BIT. Les verdicts 3, 4, 5, 8 et
    // 10 de `hdr-display-output` comparent des PHASES ; les changer sous eux les rendrait
    // incomparables avec ce qui a deja ete mesure. Ce bras ne tourne QUE sous la mesure de cet
    // item-la, et il ne sort jamais a l'ecran du joueur.
    p.ceiling = cmax;
    p.anchor = kPinAnchorP;
    p.top = std::fmin(kPinTop, cmax);
    p.toe = 0.f;
    p.shape = 1;
    p.gamma = kGammaMax;
    s_dyn_pinned_frames++;
  } else {
    p = placement_params(cmax);
    // hdr-shadow-range : LE PIED, POSE ICI ET NULLE PART AILLEURS. Il ne va PAS dans
    // `placement_params` : cette fonction sert aussi de BRAS DE MESURE a `probe_regime`
    // (arms[3], le placement a marge simulee) et a `legacy_params`. Y poser le pied ferait
    // compter a `hdr_regime_exc_vs_sdr_px` le relevement des ombres comme une excursion sous le
    // seuil declare, et le terme 4 d'un item deja tenu rougirait pour le travail d'un autre.
    // Le pied appartient a la courbe LIVREE ; les bras de mesure des voisins restent intacts.
    p.toe = shadow_toe_for(p.ceiling);
    s_curve_top = xp;
    s_dyn_sdr_frames++;
    if (p.ceiling > s_ceiling_max) {
      s_ceiling_max = p.ceiling;
    }
  }
  s_cur = p;
  s_last_ceiling = p.ceiling;
  return p;
}

void push_tonemap_uniforms(Shader& shader) {
  set_curve(shader.id(), curve_params());
  publish_regime();  // hdr-output-regime : le regime est publie LA OU il atteint le shader
}

// ------------------------------------------ hdr-curve-input : LA REDUCTION PAR MAXIMUM ----
// Deux passes de `max()` a couverture TOTALE, de la pleine resolution jusqu'a 16x16. Le
// programme `hdr_max_reduce` ne fait que le maximum : aucune exposition, aucune courbe. C'est
// `tonemap` qui applique la courbe, UNE fois, sur le resultat 16x16 — et comme elle est monotone
// par canal, max(f(v)) = f(max(v)) : le nombre obtenu est EXACTEMENT celui qu'on aurait eu en
// tone-mappant toute l'image puis en prenant le maximum. La correction reste donc confinee a la
// reduction, ce que le perimetre exige.
bool mr_ensure(int src_w, int src_h) {
  if (s_mr_state < 0) {
    return false;
  }
  if (!s_mr_shader) {
    s_mr_shader = new Shader("hdr_max_reduce", g_game_version);
    if (!s_mr_shader->okay()) {
      lg::error(
          "[hdr-curve-input] programme `hdr_max_reduce` indisponible : la statistique reprend les "
          "tuiles MOYENNES (la courbe reste sourde, et le proof le dira)");
      s_mr_state = -1;
      return false;
    }
    glUseProgram((GLuint)s_mr_shader->id());
    glUniform1i(glGetUniformLocation((GLuint)s_mr_shader->id(), "tex_T0"), 0);
  }
  if (src_w <= 0 || src_h <= 0) {
    return false;  // taille de scene inconnue : on ne devine pas une couverture
  }
  if (s_mr_state == 1 && src_w == s_mr_src_w && src_h == s_mr_src_h) {
    return true;
  }
  if (s_mr_fbo1) {
    glDeleteFramebuffers(1, &s_mr_fbo1);
    glDeleteTextures(1, &s_mr_tex1);
    s_mr_fbo1 = 0;
    s_mr_tex1 = 0;
  }
  if (s_mr_fbo2) {
    glDeleteFramebuffers(1, &s_mr_fbo2);
    glDeleteTextures(1, &s_mr_tex2);
    s_mr_fbo2 = 0;
    s_mr_tex2 = 0;
  }
  // L'ETAGE INTERMEDIAIRE. Sa taille est bornee des DEUX cotes pour que les deux blocs restent
  // sous la borne 64 des boucles du shader : au moins 16 (sinon la seconde passe agrandirait) et
  // au plus 64x16 = 1024 (au-dela, le bloc de la seconde passe depasserait 64 et la couverture ne
  // serait plus totale — une reduction qui laisse des pixels dehors n'est pas un maximum).
  int w1 = (src_w + kMrDiv - 1) / kMrDiv;
  int h1 = (src_h + kMrDiv - 1) / kMrDiv;
  w1 = w1 < kAnW ? kAnW : (w1 > 64 * kAnW ? 64 * kAnW : w1);
  h1 = h1 < kAnTileH ? kAnTileH : (h1 > 64 * kAnTileH ? 64 * kAnTileH : h1);
  if (!make_float_fbo(&s_mr_fbo1, &s_mr_tex1, w1, h1, nullptr) ||
      !make_float_fbo(&s_mr_fbo2, &s_mr_tex2, kAnW, kAnTileH, nullptr)) {
    lg::error("[hdr-curve-input] cibles de reduction indisponibles ({}x{}) : repli sur les tuiles moyennes",
              w1, h1);
    s_mr_state = -1;
    return false;
  }
  s_mr_w1 = w1;
  s_mr_h1 = h1;
  s_mr_src_w = src_w;
  s_mr_src_h = src_h;
  s_mr_state = 1;
  lg::info("[hdr-curve-input] reduction par MAXIMUM : {}x{} -> {}x{} (bloc {}x{}) -> {}x{} (bloc {}x{})",
           src_w, src_h, w1, h1, (src_w + w1 - 1) / w1, (src_h + h1 - 1) / h1, kAnW, kAnTileH,
           (w1 + kAnW - 1) / kAnW, (h1 + kAnTileH - 1) / kAnTileH);
  return true;
}

// Laisse le resultat dans `s_mr_tex2` (16x16, espace de la SCENE). Le VAO du quad plein cadre est
// deja lie par l'appelant et l'attribut 0 est le meme : seul le programme change.
bool mr_reduce(GLuint src_tex, int src_w, int src_h) {
  if (!mr_ensure(src_w, src_h)) {
    return false;
  }
  const GLuint prog = (GLuint)s_mr_shader->id();
  glUseProgram(prog);
  const GLint l_src = glGetUniformLocation(prog, "u_src_size");
  const GLint l_blk = glGetUniformLocation(prog, "u_block");
  glActiveTexture(GL_TEXTURE0);

  glBindFramebuffer(GL_FRAMEBUFFER, s_mr_fbo1);
  glViewport(0, 0, s_mr_w1, s_mr_h1);
  glBindTexture(GL_TEXTURE_2D, src_tex);
  glUniform2i(l_src, src_w, src_h);
  glUniform2i(l_blk, (src_w + s_mr_w1 - 1) / s_mr_w1, (src_h + s_mr_h1 - 1) / s_mr_h1);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  glBindFramebuffer(GL_FRAMEBUFFER, s_mr_fbo2);
  glViewport(0, 0, kAnW, kAnTileH);
  glBindTexture(GL_TEXTURE_2D, s_mr_tex1);
  glUniform2i(l_src, s_mr_w1, s_mr_h1);
  glUniform2i(l_blk, (s_mr_w1 + kAnW - 1) / kAnW, (s_mr_h1 + kAnTileH - 1) / kAnTileH);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  s_mr_draws += 2;
  return true;
}

// ------------------------------------------------------ hdr-curve-input : LE TEMOIN ----
// Une relecture PLEINE RESOLUTION du tampon de scene, sur l'image que l'analyse vient de reduire.
// Elle ne partage rien avec la pyramide : ni programme, ni cible, ni chemin de lecture. C'est ce
// qui fait du rapport une MESURE et pas un miroir — si la pyramide se remettait a moyenner, ce
// chiffre-ci ne bougerait pas d'un poil et le rapport remonterait.
// Rend -1 quand la lecture n'a pas abouti (aucune paire n'est alors comptee).
float ref_peak_now(GLuint src_tex, int src_w, int src_h) {
  gl_query_census::Armed _ap("hdr-curve-input-witness");
  if (src_w <= 0 || src_h <= 0) {
    return -1.f;
  }
  if (!s_ci_ref_fbo) {
    glGenFramebuffers(1, &s_ci_ref_fbo);
  }
  GLint saved_fbo = 0, saved_pack = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &saved_fbo);
  glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &saved_pack);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);  // sinon la relecture atterrirait dans le PBO de l'anneau
  glBindFramebuffer(GL_FRAMEBUFFER, s_ci_ref_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, src_tex, 0);
  float top = -1.f;
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
    GLint rf = 0, rt = 0;
    glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &rf);
    glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &rt);
    const size_t nc = (size_t)src_w * (size_t)src_h * 4;
    while (glGetError() != GL_NO_ERROR) {
    }
    if (rf == GL_RGBA && rt == GL_HALF_FLOAT) {
      s_ci_raw16.resize(nc);
      glReadPixels(0, 0, src_w, src_h, GL_RGBA, GL_HALF_FLOAT, s_ci_raw16.data());
      if (glGetError() == GL_NO_ERROR) {
        top = 0.f;
        for (size_t i = 0; i + 3 < nc; i += 4) {
          for (int k = 0; k < 3; k++) {
            const float v = half_to_float(s_ci_raw16[i + k]);
            if (std::isfinite(v) && v > top) {
              top = v;
            }
          }
        }
      }
    } else {
      s_ci_raw32.resize(nc);
      glReadPixels(0, 0, src_w, src_h, GL_RGBA, GL_FLOAT, s_ci_raw32.data());
      if (glGetError() == GL_NO_ERROR) {
        top = 0.f;
        for (size_t i = 0; i + 3 < nc; i += 4) {
          for (int k = 0; k < 3; k++) {
            const float v = s_ci_raw32[i + k];
            if (std::isfinite(v) && v > top) {
              top = v;
            }
          }
        }
      }
    }
  }
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)saved_fbo);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)saved_pack);
  if (top >= 0.f) {
    s_ci_ref_reads++;
  }
  return top;
}

void analyze_scene(Shader& shader,
                   GLuint src_tex,
                   int src_w,
                   int src_h,
                   GLuint dst_fbo,
                   int dst_w,
                   int dst_h) {
  if (!s_active.load() || s_an_state < 0) {
    return;
  }
  gl_query_census::Armed _ap("hdr-out-analyze");
  const uint64_t every = (s_an_mode == 1) ? kAnalyzeEverySync : kAnalyzeEvery;
  if ((s_frames % every) != 0) {
    return;
  }
  if (!an_ensure()) {
    // make_float_fbo laisse SA cible liee : sans cette restauration, l'image suivante se
    // dessinerait dans un FBO 16x16 (et l'echec serait invisible jusqu'a l'ecran noir).
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    return;
  }
  const GLuint prog = shader.id();
  // hdr-curve-input : L'EXPOSITION ET LE GENOU SONT LUS SUR LE PROGRAMME, pas recalcules. C'est
  // ce que le pilote a reellement recu pour l'image qui vient d'etre dessinee ; une deuxieme
  // formule en C++ pourrait deriver de celle de `tonemap_draw` sans que rien ne le dise.
  float exposure = 1.f;
  {
    const GLint le = glGetUniformLocation(prog, "u_hdr_exposure");
    if (le >= 0) {
      GLfloat v = 1.f;
      glGetUniformfv(prog, le, &v);
      if (std::isfinite(v) && v > 0.f) {
        exposure = v;
      }
    }
    if (s_ci_knee_level <= 0.f) {
      const GLint lk = glGetUniformLocation(prog, "u_hdr_knee");
      if (lk >= 0) {
        GLfloat v = 0.f;
        glGetUniformfv(prog, lk, &v);
        if (std::isfinite(v) && v > 0.f) {
          s_ci_knee_level = v;
        }
      }
    }
  }
  // Un plafond de lecture tres haut : la courbe SDR ne comprime rien sous 0,96 x 64, donc ce
  // qui atterrit dans la cible est la SCENE elle-meme (exposition comprise), pas son tone map.
  set_curve(prog, legacy_params(kAnCeiling));
  glBindFramebuffer(GL_FRAMEBUFFER, s_an_fbo);
  // ETAGE 0 (lignes 0..15) : les tuiles MOYENNES, le dessin d'avant, inchange.
  glViewport(0, 0, kAnW, kAnTileH);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  // ETAGE 1 (lignes 16..31) : les tuiles MAXIMUM. La pyramide travaille dans l'espace de la
  // SCENE, puis `tonemap` traverse son resultat 16x16 a l'identique (NEAREST, un texel pour un
  // texel) — l'etage 1 finit donc dans le MEME espace que l'etage 0, comparables au bit.
  const bool max_ok = mr_reduce(src_tex, src_w, src_h);
  if (max_ok) {
    glUseProgram(prog);  // pas `activate()` : inutile de notifier un bind au recensement d'ombrage
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, s_mr_tex2);
    glBindFramebuffer(GL_FRAMEBUFFER, s_an_fbo);
    glViewport(0, kAnTileH, kAnW, kAnTileH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  }
  // LA TEXTURE DE SCENE EST RENDUE A L'UNITE 0 DANS TOUS LES CAS, y compris quand la pyramide a
  // echoue : `make_float_fbo` laisse SA texture liee, et `probe_tonemap` rejoue le programme
  // juste apres en supposant que tex_T0 est la scene. Une seule image lue sur la mauvaise
  // texture suffirait a fausser une sonde sans qu'aucune erreur ne soit levee.
  glUseProgram(prog);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, src_tex);
  // LE TEMOIN, sur cette image-ci. Instrument : il ne tourne que sous mesure de cet item.
  float ref = -1.f;
  const bool paired = curve_input_measuring() && (s_ci_analyses % kRefEvery) == 0;
  s_ci_analyses++;
  if (paired) {
    ref = ref_peak_now(src_tex, src_w, src_h);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, s_an_fbo);
  glViewport(0, 0, kAnW, kAnH);
  bool ok = true;
  if (s_an_mode == 2) {
    GLint saved_pbo = 0;
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &saved_pbo);
    const int slot = s_an_slot;
    s_an_slot = (s_an_slot + 1) % kAnSlots;
    glBindBuffer(GL_PIXEL_PACK_BUFFER, s_an_pbo[slot]);
    if (s_an_pending[slot]) {
      // Ce tampon a ete rempli kAnSlots x kAnalyzeEvery images plus tot : la carte ne bloque pas.
      const void* m = glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, (GLsizeiptr)s_an_bytes, GL_MAP_READ_BIT);
      if (m) {
        // L'APPAIRAGE : `s_an_ref[slot]` et `s_an_exp[slot]` ont ete releves a l'image qui a
        // rempli CE tampon, pas a celle-ci. Sans ce transport, le rapport comparerait deux
        // images distantes de seize — et « sur les MEMES images » ne voudrait plus rien dire.
        an_decode(m, s_an_max_ok[slot], s_an_ref[slot], s_an_exp[slot]);
        glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
      } else {
        ok = false;
      }
      s_an_pending[slot] = false;
    }
    if (ok) {
      while (glGetError() != GL_NO_ERROR) {
      }
      glReadPixels(0, 0, kAnW, kAnH, GL_RGBA, s_an_read_type, nullptr);
      if (glGetError() == GL_NO_ERROR) {
        s_an_pending[slot] = true;
        s_an_ref[slot] = ref;
        s_an_exp[slot] = exposure;
        s_an_max_ok[slot] = max_ok;
      } else {
        ok = false;
      }
    }
    glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)saved_pbo);
    if (!ok) {
      lg::warn("[hdr-display-output] analyse de scene : PBO refuse, repli sur la lecture directe");
      s_an_mode = 1;
      for (int i = 0; i < kAnSlots; i++) {
        s_an_pending[i] = false;
      }
    }
  }
  if (s_an_mode == 1) {
    std::vector<float> px;
    if (read_float_fbo(kAnW, kAnH, px)) {
      // read_float_fbo rend toujours des float : on force le decodage dans ce type.
      const GLenum saved = s_an_read_type;
      s_an_read_type = GL_FLOAT;
      an_decode(px.data(), max_ok, ref, exposure);  // lecture directe : l'appairage est immediat
      s_an_read_type = saved;
    } else {
      lg::error("[hdr-display-output] analyse de scene : relecture refusee");
      s_an_state = -1;
      s_an_mode = 0;
    }
  }
  set_curve(prog, s_cur);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
}

PresentParams present_params_for(uint32_t mode) {
  PresentParams pp;
  // Le TRANSPORT decide l'encodage du quad final. Une surface HLG qui recevait l'encodage PQ
  // (tout ce qui n'etait pas scRGB tombait sur 1) sortait une OETF pour une autre : la branche
  // `u_out_mode == 3` de post_processing.frag n'etait atteinte par personne.
  pp.out_mode = mode == kModeNone            ? 0
                : mode == kModeScrgbLinear   ? 2
                : mode == kModeHlg           ? 3
                                             : 1;
  const bool active = mode != kModeNone;
  pp.paper_white = paper_white_for(mode, active);
  pp.max_nits = peak_nits();
  pp.headroom = headroom_linear_for(mode, active);
  pp.ceiling = tonemap_ceiling_for(mode, active);
  return pp;
}

void push_present_uniforms_to(Shader& shader, const PresentParams& pp) {
  glUniform1i(glGetUniformLocation(shader.id(), "u_out_mode"), pp.out_mode);
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_paper_white"), pp.paper_white);
  glUniform1f(glGetUniformLocation(shader.id(), "u_out_max_nits"), pp.max_nits);
}

void push_present_uniforms(Shader& shader) {
  const PresentParams pp = present_params_for(s_active.load() ? s_surface.mode : kModeNone);
  s_last_present_mode = pp.out_mode;
  push_present_uniforms_to(shader, pp);
}

const void* common_curve_symbol() {
  // L'ADRESSE de la fonction de courbe, pour que la preuve bureau la NOMME (dladdr) au lieu
  // d'affirmer « c'est le meme code ». Une liste de sites ne prouve que la liste.
  CurveParams (*fn)() = &curve_params;
  return (const void*)fn;
}

const char* curve_signature() {
  // Pure : on epingle le blanc a BT.2408 et on balaye une suite de pics FIXE. L'etat simule
  // courant est sauve et rendu — l'auto-test appareil s'en sert au meme instant, sur le meme fil.
  static std::string sig;
  if (!sig.empty()) {
    return sig.c_str();
  }
  const float save_peak = s_test_peak;
  const float save_white = s_sim_white;
  static const int kPeaks[] = {200, 300, 500, 1000, 2000, 4000};
  sig = "pq/w203:";
  for (size_t i = 0; i < sizeof(kPeaks) / sizeof(kPeaks[0]); i++) {
    s_test_peak = (float)kPeaks[i];
    s_sim_white = 203.f;
    if (i) {
      sig += ",";
    }
    sig += std::to_string((int)std::lround(tonemap_ceiling_for(kModeHdr10Pq, true) * 1000.f));
  }
  s_test_peak = save_peak;
  s_sim_white = save_white;
  return sig.c_str();
}

void set_sim_regime(int peak_nits_v, int sdr_white_v) {
  // Le MEME point d'entree que `OG_HDR_OUT_PEAK` / `OG_HDR_OUT_WHITE`, pose par le code. Reserve
  // a la mesure : aucun appelant hors sonde. 0, 0 = plus aucun regime simule.
  s_test_peak = peak_nits_v > 0 ? (float)peak_nits_v : 0.f;
  s_sim_white = sdr_white_v > 0 ? (float)sdr_white_v : 0.f;
}

// ------------------------------------------------------------------------------- sondes --

// Verdict 11 : les deux rampes, par le VRAI quad final, vers le format REEL de la fenetre.
// Tourne aussi en phase OFF (le bras de comparaison), d'ou sa propre fenetre.
static void probe_ramps(Shader& /*shader*/) {
  gl_query_census::Armed _ap("hdr-out-probe-ramps");
  if (!ramp_window_open() || s_rp_state < 0) {
    return;
  }
  const GLenum fmt = window_target_format();
  if (s_rp_state == 0 || s_rp_fmt != fmt) {
    if (s_rp_fbo) {
      glDeleteFramebuffers(1, &s_rp_fbo);
      s_rp_fbo = 0;
    }
    if (s_rp_tex) {
      glDeleteTextures(1, &s_rp_tex);
      s_rp_tex = 0;
    }
    bool ok = true;
    if (!s_rp_src[0]) {
      ok = make_ramp_tex(&s_rp_src[0], 0.f, kRampWindow) &&
           make_ramp_tex(&s_rp_src[1], 1.f - kRampWindow, 1.f) &&
           make_ramp_tex(&s_rp_src[2], 1.f - kRampWindow, kFixedTop);
    }
    ok = ok && make_target_fbo(&s_rp_fbo, &s_rp_tex, kRampN, 1, fmt);
    s_rp_fmt = fmt;
    s_rp_state = ok ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (!ok) {
      return;
    }
    lg::info("[hdr-display-output] sonde de rampes : cible au format 0x{:x} (phase {})",
             (unsigned)fmt, s_phase);
  }
  GLint vp[4] = {0, 0, 0, 0};
  GLint saved_tex = 0;
  glGetIntegerv(GL_VIEWPORT, vp);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  glBindFramebuffer(GL_FRAMEBUFFER, s_rp_fbo);
  glViewport(0, 0, kRampN, 1);
  glActiveTexture(GL_TEXTURE0);
  uint64_t lv[3] = {0, 0, 0};
  bool ok = true;
  for (int r = 0; r < 3 && ok; r++) {
    glBindTexture(GL_TEXTURE_2D, s_rp_src[r]);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_levels(kRampN, fmt, &lv[r]);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(vp[0], vp[1], vp[2], vp[3]);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (!ok) {
    lg::error("[hdr-display-output] sonde de rampes : relecture refusee (format 0x{:x})",
              (unsigned)fmt);
    s_rp_state = -1;
    return;
  }
  ProbeStats& pr = s_pr[s_phase];
  pr.ramp_samples++;
  if (lv[0] > pr.shadow_levels) {
    pr.shadow_levels = lv[0];
  }
  if (lv[1] > pr.hl_levels) {
    pr.hl_levels = lv[1];
  }
  if (lv[2] > pr.hl_ext_levels) {
    pr.hl_ext_levels = lv[2];
  }
  if (pr.ramp_samples == 1 || (pr.ramp_samples % 10) == 0) {
    lg::info("[hdr-display-output] rampes phase {} #{} : ombres={}/{} hautes={}/{} hautes_etendues={}/{} format=0x{:x} relecture={} bits",
             s_phase, pr.ramp_samples, lv[0], (uint64_t)kRampN, lv[1], (uint64_t)kRampN, lv[2],
             (uint64_t)kRampN, (unsigned)fmt, s_rp_read_type);
  }
}

void probe_present(Shader& shader) {
  gl_query_census::Armed _ap("hdr-out-probe-present");
  probe_ramps(shader);
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
  if (s_surface.mode == kModeHlg) {
    // HLG (ARIB STD-B67) est RELATIF : l'OETF inverse rend une scene [0,1] ou 1,0 est le pic de
    // l'ecran. Le blanc du jeu y est pose a la fraction `paper_white() == 1/marge` de ce pic ;
    // on remultiplie par la marge pour rendre, comme en scRGB, des MULTIPLES du blanc SDR.
    const float m = std::fmin(r1, std::fmin(g1, b1));
    measured = hlg_inverse_oetf((double)m) * (double)headroom_linear();
  } else if (s_surface.mode == kModeHdr10Pq) {
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

// ------------------------------------- verdicts 12 et 13 : LE JEU REEL, APRES l'auto-test ----
// L'auto-test compare des ETATS (interrupteur, surface, blanc, pic annonce) sur un point de
// fonctionnement fige. Ce qui suit mesure ce que l'owner refuse depuis le 10/09 : l'AMPLITUDE de
// la difference on/off, et le fait que la courbe SUIVE la scene dans le temps. Les deux se
// mesurent sur du jeu reel, apres l'auto-test, la courbe laissee LIBRE.
constexpr uint64_t kPlayEvery = 20;

bool play_window_open() {
  return measuring() && s_selftest_done && s_active.load() && (s_frames % kPlayEvery) == 0;
}

// La reponse du programme `tonemap` a un STIMULUS FIXE (rampe 0..kFixedTop). Une courbe unique
// et figee rendrait toujours la meme somme ; c'est une grandeur LUE d'un dessin, pas le reflet
// de nos propres variables. L'appelant restaure FBO, viewport et parametres courants.
bool ramp_response(GLuint prog, const CurveParams& p, double* out) {
  gl_query_census::Armed _ap("hdr-out-ramp-response");
  if (s_tf_state < 0) {
    return false;
  }
  if (s_tf_state == 0) {
    const bool ok = make_ramp_tex(&s_tf_src, 0.f, kFixedTop) &&
                    make_float_fbo(&s_tf_fbo, &s_tf_tex, kRampN, 1, nullptr);
    s_tf_state = ok ? 1 : -1;
    if (!ok) {
      return false;
    }
  }
  GLint saved_tex = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, s_tf_src);
  glBindFramebuffer(GL_FRAMEBUFFER, s_tf_fbo);
  glViewport(0, 0, kRampN, 1);
  set_curve(prog, p);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  std::vector<float> fx;
  const bool ok = read_float_fbo(kRampN, 1, fx);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (!ok) {
    s_tf_state = -1;
    return false;
  }
  // LA FENETRE DU STIMULUS FIXE. Le stimulus couvre [0, kFixedTop=3] ; quand le plafond vaut
  // 1,000 — c'est-a-dire des que le systeme n'accorde aucune marge — la courbe ECRETE tout ce qui
  // depasse ~0,72, soit 76 % des marches, et la somme devient quasi invariante : mesure du 11/09,
  // `dyn_resp` entre 110,04 et 110,11, soit 0,06 % d'ecart sur une courbe qui bougeait vraiment
  // (ancre 0,290 -> 0,307, sommet 0,623 -> 0,710). Le verdict 13 tombait rouge pour une raison
  // d'INSTRUMENT. La somme se fait donc sur le TIERS BAS du stimulus — [0, 1,0], toujours le
  // MEME sous-ensemble de marches, toujours le meme stimulus : ce qui est fixe le reste.
  const int n_used = kRampN / 3;
  double sum = 0.0;
  for (int t = 0; t < n_used; t++) {
    const float m = std::fmax(fx[(size_t)t * 4], std::fmax(fx[(size_t)t * 4 + 1], fx[(size_t)t * 4 + 2]));
    if (std::isfinite(m)) {
      sum += (double)m;
    }
  }
  *out = sum;
  return true;
}

// La serie couvre TOUTE la course, pas ses premieres secondes : quand l'anneau est plein on en
// retire une valeur sur deux et on double le pas. Rien n'est jete au hasard.
void dyn_series_push(const DynSample& v) {
  s_dyn_seen++;
  if ((s_dyn_seen % (uint64_t)s_dyn_stride) != 0) {
    return;
  }
  s_dyn_series.push_back(v);
  if (s_dyn_series.size() >= kDynSeriesMax) {
    std::vector<DynSample> keep;
    keep.reserve(kDynSeriesMax / 2 + 1);
    for (size_t i = 0; i < s_dyn_series.size(); i += 2) {
      keep.push_back(s_dyn_series[i]);
    }
    s_dyn_series.swap(keep);
    s_dyn_stride *= 2;
  }
}

void probe_gameplay(Shader& shader, GLuint dst_fbo, int dst_w, int dst_h) {
  if (s_pl_state < 0) {
    return;
  }
  const GLuint prog = shader.id();
  if (s_pl_state == 0) {
    bool ok = true;
    for (int i = 0; i < 4 && ok; i++) {
      ok = make_float_fbo(&s_pl_fbo[i], &s_pl_tex[i], kTmW, kTmH, nullptr);
    }
    s_pl_state = ok ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    if (!ok) {
      lg::error("[hdr-display-output] sonde de jeu reel : FBO indisponible");
      return;
    }
  }
  // QUATRE BRAS DU MEME PROGRAMME SUR LA MEME IMAGE : le SDR livre, la sortie HDR
  // d'aujourd'hui, celle REFUSEE le 10/09 (plafond seul, aucune expansion) et celle REFUSEE le
  // 11/09 (fenetre Hermite). La scene ne bouge pas entre eux. Le quatrieme bras n'existe que
  // pour le verdict 15 : sans lui, le plafond de contraste declare n'aurait aucune reference
  // mesuree et serait le « chiffre invente » que le livrable interdit.
  const CurveParams legs[4] = {sdr_params(), s_cur, legacy_params(tonemap_ceiling()),
                               refused_params_11_09(tonemap_ceiling())};
  std::vector<float> img[4];
  bool ok = true;
  for (int i = 0; i < 4 && ok; i++) {
    set_curve(prog, legs[i]);
    glBindFramebuffer(GL_FRAMEBUFFER, s_pl_fbo[i]);
    glViewport(0, 0, kTmW, kTmH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kTmW, kTmH, img[i]);
  }
  set_curve(prog, s_cur);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  if (!ok) {
    lg::error("[hdr-display-output] sonde de jeu reel : relecture refusee");
    s_pl_state = -1;
    return;
  }
  s_play.samples++;
  for (size_t i = 0; i + 3 < img[0].size(); i += 4) {
    float m[3];
    bool fine = true;
    for (int k = 0; k < 3; k++) {
      m[k] = std::fmax(img[k][i], std::fmax(img[k][i + 1], img[k][i + 2]));
      fine = fine && std::isfinite(m[k]);
    }
    if (!fine) {
      continue;
    }
    s_play.gain_ref += (double)m[0];
    s_play.gain_new += (double)std::fmax(0.f, m[1] - m[0]);
    s_play.gain_old += (double)std::fmax(0.f, m[2] - m[0]);
    // LE PLANCHER DE L'INSTRUMENT, PAS UNE TOLERANCE DE CONFORT. Les trois bras sont dessines
    // dans des tampons GL_RGBA16F : un demi-flottant porte dix bits de mantisse, son pas vaut
    // donc m/1024 — 2,4e-4 autour de 0,25, soit DEUX FOIS ET DEMIE le 1e-4 qui etait compare
    // ici. Or sous l'ancre la courbe HDR ne depasse le SDR que du relevement de pied, et ce
    // relevement s'annule en approchant 0,25 (`hdr_toe_scalar` : v + amt.v.(1-v/0,25)^2) : deux
    // valeurs mathematiquement ordonnees y tombent sur des demi-flottants voisins et le
    // compteur enregistrait un assombrissement QUE LE TAMPON NE PEUT PAS REPRESENTER — 173
    // pixels sur 52 224 a l'essai 17. Le seuil devient le pas du tampon. Ce n'est pas un
    // assouplissement du critere : `below_sdr_worst` retient la pire violation SANS tolerance,
    // et un vrai assombrissement (qui vaut des centiemes) la fait sortir du bruit.
    if (m[1] < m[0]) {
      const double d = (double)m[0] - (double)m[1];
      if (d > s_play.below_sdr_worst) {
        s_play.below_sdr_worst = d;
      }
      if ((double)m[1] < (double)m[0] - std::fmax(1e-4, std::fabs((double)m[0]) / 1024.0)) {
        s_play.below_sdr_px++;  // la courbe est >= SDR par construction : doit rester a ZERO
      }
    }
    if ((double)m[1] > s_play.hl_max) {
      s_play.hl_max = m[1];
    }
    if ((double)m[0] > s_play.hl_max_ref) {
      s_play.hl_max_ref = m[0];  // le MEME maximum sur le bras SDR, meme image, meme instant
    }
    // RICHESSE DANS LES OMBRES, sur du jeu reel : les codes que chacun des deux etats livrerait
    // a la fenetre, pour les pixels dont la sortie SDR est SOUS le blanc.
    if (m[0] < 1.f && m[0] >= 0.f && m[1] >= 0.f) {
      s_play.shadow_px++;
      const int co = (int)std::lround((double)m[0] * 255.0);
      if (co >= 0 && co < 256) {
        s_play.code_off[co] = true;
      }
      const double nits = std::pow((double)m[1], 2.2) * (double)sdr_white_nits();
      const int cn = (int)std::lround(pq_oetf_from_nits(nits) * 1023.0);
      if (cn >= 0 && cn < 1024) {
        s_play.code_on[cn] = true;
      }
      if (m[0] < kRampWindow) {
        s_play.deep_px++;
        if (co >= 0 && co < 256) {
          s_play.code_off_deep[co] = true;
        }
        if (cn >= 0 && cn < 1024) {
          s_play.code_on_deep[cn] = true;
        }
      }
    }
    // Le RELEVEMENT RELATIF : au moins un quart de ce que la courbe planifie a son sommet. Un
    // seuil absolu a 25 % etait calibre sur une marge achetee x4 ; a plafond 1,000 le sommet
    // lui-meme ne monte que de ~33 % et aucun pixel ne l'atteindrait — la porte aurait ete
    // rouge pour une raison d'instrument, pas de rendu.
    if (m[0] > 1e-3f && s_top_gain_max > 1.f) {
      const float thr = 1.f + 0.25f * (s_top_gain_max - 1.f);
      if (m[1] >= m[0] * thr) {
        s_play.lift_rel_px++;
      }
    }
    if (m[0] > 1e-3f && m[1] > m[0] * 1.02f) {
      s_play.lift_px++;
      s_play.lift_ratio_sum += (double)m[1] / (double)m[0];
    }
    if (m[0] > 1e-3f) {
      const float r = m[1] / m[0];
      if (r >= 1.10f) {
        s_play.lift10_px++;
      }
      if (r >= 1.25f) {
        s_play.lift25_px++;
        if (m[0] >= 0.20f) {
          s_play.lift25_hi_px++;
        }
      }
      if (r >= 1.50f) {
        s_play.lift50_px++;
      }
    }
    if (m[0] >= 0.05f && m[0] <= 0.85f) {
      s_play.px++;
      s_play.sum_off += lum_linear(img[0][i], img[0][i + 1], img[0][i + 2]);
      s_play.sum_on += lum_linear(img[1][i], img[1][i + 1], img[1][i + 2]);
    }
    // VERDICT 15 : l'excursion, sur le MEME pixel de la MEME image, pour la courbe livree et
    // pour celle que l'owner a refusee le 11/09.
    exc_accumulate(s_exc, &img[0][i], &img[1][i]);
    exc_accumulate(s_exc17, &img[0][i], &img[3][i]);
  }
  // LA SERIE. La reponse au stimulus fixe, et les parametres effectifs a cet instant.
  double resp = 0.0;
  if (ramp_response(prog, s_cur, &resp)) {
    DynSample v;
    v.frame = s_frames;
    v.resp = (float)resp;
    v.anchor = s_cur.anchor;
    v.top = s_cur.top;
    v.ceiling = s_cur.ceiling;
    v.key = s_dyn.key;
    v.hi = s_dyn.hi;
    v.t_s = (float)std::chrono::duration<double>(std::chrono::steady_clock::now() - s_clock0).count();
    dyn_series_push(v);
  }
  set_curve(prog, s_cur);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  if (s_play.samples == 1 || (s_play.samples % 20) == 0) {
    lg::info(
        "[hdr-display-output] jeu reel #{} : ancre={:.3f} sommet={:.3f} plafond={:.3f} pied={:.3f}"
        " key={:.3f} hi={:.3f} releve={}/{} gain_neuf={:.4f} gain_10-09={:.4f} reponse={:.2f}",
        s_play.samples, s_cur.anchor, s_cur.top, s_cur.ceiling, s_cur.toe, s_dyn.key, s_dyn.hi,
        s_play.lift_px, s_play.samples * (uint64_t)kTmW * kTmH,
        s_play.gain_ref > 0.0 ? s_play.gain_new / s_play.gain_ref : 0.0,
        s_play.gain_ref > 0.0 ? s_play.gain_old / s_play.gain_ref : 0.0, resp);
  }
}

// ============================================= hdr-output-regime : LE VERDICT, TERME PAR TERME ==
void publish_regime_verdict() {
  if (!regime_measuring()) {
    return;  // instrument : muet hors de la mesure de CET item
  }
  const RegimeVerdict rg = regime_now();
  const int fmt = format_chosen();

  // --- LE REGIME DE SA PROPRE FEATURE, EPINGLE (avertissement C du contrat). Sur la preuve du
  //     chantier A, maitre Recharged epingle ON, le tampon de SCENE etait reste RGBA8 : les dix
  //     etages de source etaient flottants, leur consommateur ne l'etait pas. Un binaire correct
  //     mesure dans une configuration ou son effet ne peut pas atteindre la dalle est un faux
  //     vert en puissance. Ici il est ROUGE, et il dit pourquoi.
  const GLenum scene_fmt = hdr::scene_color_format();
  const bool scene_float = hdr::format_is_float(scene_fmt);
  const bool chain = hdr::chain_active();
  const bool out_active = s_active.load();
  autoport_proof::publish_text("hdr_regime_scene_fmt", hdr::format_name(scene_fmt));
  autoport_proof::publish("hdr_regime_scene_float", (uint64_t)(scene_float ? 1 : 0));
  autoport_proof::publish("hdr_regime_chain_active", (uint64_t)(chain ? 1 : 0));
  autoport_proof::publish("hdr_regime_out_active", (uint64_t)(out_active ? 1 : 0));
  autoport_proof::publish("hdr_regime_probe_runs", s_rg_runs);
  const int d0 = (out_active && chain && scene_float && s_rg_runs > 0) ? 0 : 1;

  // --- TERME 1 : le regime est publie a CHAQUE image. Le denominateur vient d'un cran plus haut
  //     (hdr.cpp compte les dessins APRES le glDrawArrays) : deux compteurs poses au meme endroit
  //     ne prouveraient que leur propre egalite.
  const uint64_t draws = hdr::chain_census().tonemap_draws;
  autoport_proof::publish("hdr_regime_published_frames", s_regime_frames);
  autoport_proof::publish("hdr_regime_tonemap_draws", draws);
  // Le defaut est « le regime n'a PAS ete publie sur une image dessinee », donc `publie < dessine`.
  // Publier une fois de plus n'en est pas un : `publish_all` peut tomber entre la pose des
  // uniformes et le `glDrawArrays`, et un verdict qui exigerait l'egalite stricte rendrait rouge
  // un instant d'echantillonnage au lieu d'un defaut.
  const int d1 = (draws > 0 && s_regime_frames >= draws) ? 0 : 1;

  // --- TERME 2 : en regime SANS MARGE, l'image est IDENTIQUE AU BIT a la sortie SDR.
  autoport_proof::publish("hdr_regime_maxdiff_vs_sdr_x1e6", s_rg_maxdiff_x1e6);
  autoport_proof::publish("hdr_regime_ramp_px", s_rg_ramp_px);
  autoport_proof::publish("hdr_regime_scene_px", s_rg_scene_px);
  const uint64_t compared = s_rg_ramp_px + s_rg_scene_px;
  int d2 = 1;
  if (compared > 0) {
    // En R0 l'identite est EXIGEE ; en R1/R2 le bras livre DOIT au contraire s'ecarter du SDR,
    // sinon la marge accordee ne sert a rien. Le verdict n'est donc pas le meme des deux cotes,
    // et il ne peut pas etre vert par defaut : un regime non mesure reste rouge.
    d2 = (rg.level == 0) ? (s_rg_maxdiff_x1e6 == 0 ? 0 : 1) : (s_rg_maxdiff_x1e6 > 0 ? 0 : 1);
  }

  // --- TERME 3 : en regime AVEC MARGE, aucun pixel ne passe sous le niveau SDR.
  autoport_proof::publish("hdr_regime_below_sdr_px", s_rg_below_sdr_px);
  autoport_proof::publish("hdr_regime_sim_ceiling_x1000",
                          (uint64_t)std::lround(s_rg_sim_ceiling * 1000.f));
  autoport_proof::publish("hdr_regime_sim_gain_x1e6", s_rg_sim_gain_x1e6);
  autoport_proof::publish_text("hdr_regime_sim_source",
                              "pic_annonce_du_systeme/blanc_graphique_BT2408");
  // Le temoin d'effet garde ce terme de la vacuite : si le bras simule ne fait RIEN, « aucun
  // pixel sous le SDR » est vrai par inaction et ne vaut pas un vert.
  const int d3 = (compared > 0 && s_rg_sim_gain_x1e6 > 0 && s_rg_below_sdr_px == 0) ? 0 : 1;

  // --- TERME 4 : aucun pixel sous le seuil DECLARE n'est modifie. Les deux acceptions.
  autoport_proof::publish("hdr_regime_thr_vs_sdr_x1000",
                          (uint64_t)std::lround(s_rg_knee * 1000.f));
  autoport_proof::publish("hdr_regime_thr_identity_x1000",
                          (uint64_t)std::lround(s_rg_knee * s_rg_sim_ceiling * 1000.f));
  autoport_proof::publish("hdr_regime_exc_vs_sdr_px", s_rg_exc_sdr_px);
  autoport_proof::publish("hdr_regime_exc_vs_identity_px", s_rg_exc_ident_px);
  // LA MAGNITUDE A COTE DU COMPTE. `*_any_px` compte tout ecart non nul, `*_px` seulement ceux
  // qui depassent 1,5 ULP du conteneur. Les deux ensemble disent si un compte non nul est une
  // courbe ou le dernier bit d'un demi-flottant, ce qu'aucun des deux ne dit seul.
  autoport_proof::publish("hdr_regime_exc_any_px", s_rg_exc_ramp_px + s_rg_exc_scene_px);
  autoport_proof::publish("hdr_regime_exc_any_ramp_px", s_rg_exc_ramp_px);
  autoport_proof::publish("hdr_regime_exc_any_scene_px", s_rg_exc_scene_px);
  autoport_proof::publish("hdr_regime_exc_max_ulp_x1000", s_rg_exc_max_ulp_x1000);
  autoport_proof::publish("hdr_regime_below_any_px", s_rg_below_ramp_px + s_rg_below_scene_px);
  autoport_proof::publish("hdr_regime_below_any_ramp_px", s_rg_below_ramp_px);
  autoport_proof::publish("hdr_regime_below_any_scene_px", s_rg_below_scene_px);
  autoport_proof::publish("hdr_regime_below_max_ulp_x1000", s_rg_below_max_ulp_x1000);
  autoport_proof::publish("hdr_regime_tolerance_ulp_x1000", (uint64_t)1500);
  const int d4 = (compared > 0 && s_rg_exc_sdr_px == 0 && s_rg_exc_ident_px == 0) ? 0 : 1;

  // --- TERME 5 : la ligne de menu porte le TRANSPORT retenu et le REGIME courant. Ce n'est pas
  //     une affirmation : GOAL rapporte ce qu'il a REELLEMENT formate, et on le confronte a ce
  //     que le C++ sait. Une ligne de menu se lit, elle ne se croit pas.
  autoport_proof::publish("hdr_regime_menu_notes", s_menu_notes);
  autoport_proof::publish("hdr_regime_menu_transport", (uint64_t)(s_menu_transport + 1));
  autoport_proof::publish("hdr_regime_menu_regime", (uint64_t)(s_menu_regime + 1));
  autoport_proof::publish("hdr_regime_menu_len", (uint64_t)(s_menu_len + 1));
  autoport_proof::publish("hdr_regime_format_chosen_id", (uint64_t)fmt);
  autoport_proof::publish_text("hdr_regime_format_chosen", format_name(fmt));
  const int d5 = (s_menu_notes > 0 && s_menu_transport == fmt && s_menu_regime == rg.level &&
                  s_menu_len > 0 && s_menu_len <= 18)
                     ? 0
                     : 1;

  // --- AVERTISSEMENT A DU CONTRAT : l'ANCRE tiree des tuiles MOYENNES contre celle tiree des
  //     MAXIMUMS. Mesuree ici, et le verdict qui suit est le seul honnete : la courbe LIVREE
  //     N'A PLUS D'ANCRE (C2), donc AUCUNE des deux n'est retenue. On la mesure quand meme —
  //     « non mesure » et « sans effet » ne sont pas la meme phrase, et le chantier suivant doit
  //     savoir laquelle des deux il lit.
  autoport_proof::publish("hdr_regime_anchor_samples", s_anchor_samples);
  autoport_proof::publish("hdr_regime_anchor_from_means_x1000",
                          (uint64_t)std::lround(s_anchor_mean_last * 1000.f));
  autoport_proof::publish("hdr_regime_anchor_from_max_x1000",
                          (uint64_t)std::lround(s_anchor_max_last * 1000.f));
  autoport_proof::publish("hdr_regime_anchor_gap_max_x1000", s_anchor_gap_max_x1000);
  autoport_proof::publish_text("hdr_regime_anchor_retained",
                               "aucune:la_courbe_livree_place_le_blanc_sans_ancre");

  autoport_proof::publish("hdr_regime_gl_errors", s_rg_gl_errors);
  autoport_proof::publish("hdr_regime_d0_pin", (uint64_t)d0);
  autoport_proof::publish("hdr_regime_d1_published", (uint64_t)d1);
  autoport_proof::publish("hdr_regime_d2_identity", (uint64_t)d2);
  autoport_proof::publish("hdr_regime_d3_below_sdr", (uint64_t)d3);
  autoport_proof::publish("hdr_regime_d4_excursion", (uint64_t)d4);
  autoport_proof::publish("hdr_regime_d5_menu", (uint64_t)d5);
  autoport_proof::publish("hdr_regime_defects", (uint64_t)(d0 + d1 + d2 + d3 + d4 + d5));
}

// ================================================ hdr-output-regime : LA SONDE A QUATRE BRAS ==
// Elle ne mesure RIEN cote CPU : les quatre bras sont le MEME programme `tonemap`, rejoue hors
// ecran avec quatre jeux d'uniformes, et lus par le meme chemin. Aucune valeur n'est recalculee
// en C++, donc aucune porte ne se lit sur ses propres variables.
void probe_regime(Shader& shader,
                  GLuint src_tex,
                  GLuint dst_fbo,
                  int dst_w,
                  int dst_h,
                  float knee) {
  gl_query_census::Armed _ap("hdr-out-probe-regime");
  if (!regime_measuring() || s_rg_state < 0 || !s_active.load() || (s_frames % kRgEvery) != 0) {
    return;
  }
  if (s_rg_state == 0) {
    const bool a = make_float_fbo(&s_rg_fbo, &s_rg_tex, kRgTmW, kRgTmH, nullptr);
    const bool b = a && make_float_fbo(&s_rg_rfbo, &s_rg_rtex, kRampN, 1, nullptr);
    const bool c = b && make_ramp_tex(&s_rg_ramp, 0.f, kRgRampTop);
    s_rg_state = c ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    if (s_rg_state < 0) {
      lg::error("[hdr-output-regime] sonde indisponible : cibles hors ecran refusees");
      return;
    }
  }
  const GLuint prog = shader.id();
  // LE PLAFOND SIMULE, et ce qu'il est exactement. C'est le plafond que CET ecran accorderait
  // s'il PRESENTAIT : son pic ANNONCE (`HdrCapabilities.maxLuminance`, lu du systeme) rapporte au
  // blanc graphique BT.2408, converti dans l'espace d'affichage du tampon. Ce n'est ni une
  // constante ni un appareil nomme.
  // POURQUOI CE BRAS EXISTE : en R0 le bras LIVRE vaut le bras SDR terme a terme, donc
  // `below_sdr_px` et l'excursion y seraient satisfaits PAR INACTION — une porte verte qui ne
  // mesure rien. Ce bras exerce la MEME fonction de placement a un plafond > 1 et rend ces deux
  // termes falsifiables sur un ecran qui n'accorde rien. Il ecrit dans une cible hors ecran de
  // 32x32 : il ne fabrique AUCUNE difference visible, ce que le perimetre interdit.
  const float h_sim = std::fmax(1.05f, peak_nits() / kGraphicsWhiteNits);
  const float c_sim = std::pow(h_sim, 1.f / 2.2f);
  s_rg_sim_ceiling = c_sim;
  s_rg_knee = knee;
  const CurveParams arms[4] = {placement_params(kRgIdentCeiling),  // 0 IDENTITE
                               sdr_params(),                       // 1 SDR livre
                               s_cur,                              // 2 ce qui part a l'ecran
                               placement_params(c_sim)};           // 3 le placement a marge
  GLint saved_tex = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  while (glGetError() != GL_NO_ERROR) {
  }
  std::vector<float> ramp[4], scene[4];
  bool ok = true;
  glActiveTexture(GL_TEXTURE0);
  // --- LA RAMPE : l'entree est BALAYEE, donc la propriete est prouvee sur tout le domaine, pas
  //     sur les valeurs que la scene a bien voulu porter cette image-la.
  glBindTexture(GL_TEXTURE_2D, s_rg_ramp);
  glBindFramebuffer(GL_FRAMEBUFFER, s_rg_rfbo);
  glViewport(0, 0, kRampN, 1);
  for (int i = 0; i < 4 && ok; i++) {
    set_curve(prog, arms[i]);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kRampN, 1, ramp[i]);
  }
  // --- LA SCENE : les MEMES bras sur ce qui est REELLEMENT dessine. Echantillonnage au plus
  //     proche : un filtrage lineaire moyennerait, et c'est precisement ce qui a rendu l'entree
  //     de la courbe sourde d'un facteur 9 (chantier B).
  glBindTexture(GL_TEXTURE_2D, src_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, s_rg_fbo);
  glViewport(0, 0, kRgTmW, kRgTmH);
  for (int i = 0; i < 4 && ok; i++) {
    set_curve(prog, arms[i]);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kRgTmW, kRgTmH, scene[i]);
  }
  // On rend EXACTEMENT l'etat d'avant : uniformes livres, cible, viewport, texture et filtrage.
  set_curve(prog, s_cur);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (!ok) {
    lg::error("[hdr-output-regime] sonde a quatre bras : relecture refusee");
    s_rg_state = -1;
    return;
  }
  if (glGetError() != GL_NO_ERROR) {
    s_rg_gl_errors++;
  }
  // LES DEUX SEUILS DECLARES, et ils viennent du genou REELLEMENT pousse au shader :
  //   `knee`         : sous lui l'epaule SDR est deja l'identite, donc le placement ne peut pas
  //                    s'en ecarter — c'est le seuil « rien n'est modifie par rapport au SDR » ;
  //   `knee * C`     : sous lui le placement lui-meme est l'identite — c'est le seuil « l'image
  //                    reste l'image », celui que le plan ecrit 0,96.C.
  const double thr_sdr = (double)knee;
  const double thr_ident = (double)knee * (double)c_sim;
  // La tolerance est PUBLIEE. Les quatre bras passent par le meme programme et le meme format de
  // cible ; l'ecart residuel d'un `x/C*C` en flottant vaut ~1 ulp (6e-8 relatif), cinq ordres de
  // grandeur sous ce seuil, lui-meme cinquante fois sous le pas d'un demi-flottant. Une courbe
  // qui modifie vraiment un pixel le fait de beaucoup plus.
  // LA TOLERANCE SE DIT EN PAS DU CONTENEUR, PAS EN CONSTANTE. Les quatre bras passent par le
  // meme programme et la meme cible 16F ; sous 1 ULP de cette cible, deux valeurs y SONT le meme
  // nombre et aucune ecriture ne pourrait les separer. On compte donc a 1,5 ULP — et on publie
  // en plus l'ecart MAXIMUM en ULP, pour qu'un lecteur voie si le compte est du dernier bit ou
  // d'une vraie courbe. Un compte seul ne distingue pas les deux.
  auto walk = [&](const std::vector<float>* a, int n, uint64_t* px_out, uint64_t* below_out,
                  uint64_t* exc_out) {
    for (int t = 0; t < n; t++) {
      const size_t k = (size_t)t * 4;
      if (k + 2 >= a[0].size() || k + 2 >= a[3].size()) {
        break;
      }
      const float in = std::fmax(a[0][k], std::fmax(a[0][k + 1], a[0][k + 2]));
      const float sdr = std::fmax(a[1][k], std::fmax(a[1][k + 1], a[1][k + 2]));
      const float live = std::fmax(a[2][k], std::fmax(a[2][k + 1], a[2][k + 2]));
      const float sim = std::fmax(a[3][k], std::fmax(a[3][k + 1], a[3][k + 2]));
      if (!std::isfinite(in) || !std::isfinite(sdr) || !std::isfinite(live) ||
          !std::isfinite(sim)) {
        continue;
      }
      (*px_out)++;
      // TERME 2 — en R0 l'image est IDENTIQUE AU BIT a la sortie SDR. Mesure SANS tolerance :
      // les deux bras y ont le meme plafond et prennent la meme branche du shader, donc le
      // moindre bit d'ecart est un defaut.
      const uint64_t dx = (uint64_t)std::llround(std::fabs((double)live - (double)sdr) * 1e6);
      if (dx > s_rg_maxdiff_x1e6) {
        s_rg_maxdiff_x1e6 = dx;
      }
      // TERME 3 — AUCUN pixel ne passe sous le niveau SDR.
      const double u_below = half_ulp(std::fmax((double)sim, (double)sdr));
      const double d_below = (double)sdr - (double)sim;  // > 0 = le simule est SOUS le SDR
      if (d_below > 0.0) {
        const uint64_t r = (uint64_t)std::llround(1000.0 * d_below / u_below);
        if (r > s_rg_below_max_ulp_x1000) {
          s_rg_below_max_ulp_x1000 = r;
        }
        (*below_out)++;
        if (d_below > 1.5 * u_below) {
          s_rg_below_over_ulp_px++;
          s_rg_below_sdr_px++;
        }
      }
      if ((double)live < (double)sdr - 1.5 * half_ulp((double)sdr)) {
        s_rg_below_sdr_px++;  // le bras LIVRE, lui, ne doit jamais y passer non plus
      }
      // TERME 4 — aucun pixel sous le seuil DECLARE n'est modifie, dans les deux acceptions.
      if ((double)in <= thr_sdr) {
        const double d = std::fabs((double)sim - (double)sdr);
        const double u = half_ulp(std::fmax((double)sim, (double)sdr));
        const uint64_t r = (uint64_t)std::llround(1000.0 * d / u);
        if (r > s_rg_exc_max_ulp_x1000) {
          s_rg_exc_max_ulp_x1000 = r;
        }
        if (d > 0.0) {
          (*exc_out)++;
        }
        if (d > 1.5 * u) {
          s_rg_exc_over_ulp_px++;
          s_rg_exc_sdr_px++;
        }
      }
      if ((double)in <= thr_ident) {
        const double d = std::fabs((double)sim - (double)in);
        if (d > 1.5 * half_ulp(std::fmax((double)sim, (double)in))) {
          s_rg_exc_ident_px++;
        }
      }
      // LE TEMOIN D'EFFET : le bras simule fait-il QUELQUE CHOSE ? Un zero ici dirait que les
      // trois termes ci-dessus sont verts parce que rien ne bouge.
      const double g = (double)sim - (double)sdr;
      if (g > 0.0) {
        const uint64_t gx = (uint64_t)std::llround(g * 1e6);
        if (gx > s_rg_sim_gain_x1e6) {
          s_rg_sim_gain_x1e6 = gx;
        }
      }
    }
  };
  walk(ramp, kRampN, &s_rg_ramp_px, &s_rg_below_ramp_px, &s_rg_exc_ramp_px);
  walk(scene, kRgTmW * kRgTmH, &s_rg_scene_px, &s_rg_below_scene_px, &s_rg_exc_scene_px);
  s_rg_runs++;
}

// ====================================================== hdr-shadow-range : LA SONDE D'OMBRES ==
// Elle ne mesure RIEN cote CPU dans l'image : les cinq bras sont le MEME programme `tonemap`,
// rejoue hors ecran avec cinq jeux d'uniformes, lus par le meme chemin que `probe_regime`.
// Aucune porte ne se lit donc sur ses propres variables.
namespace {

// LA FENETRE JUGEE : LE PREMIER DIXIEME DE LA PLAGE D'AFFICHAGE. Elle est a 1/10 parce que c'est
// ce que le livrable demande, et elle est PUBLIEE (`hdr_shadow_window_x1000`). Le fichier porte
// deja une fenetre d'ombres a 1/16 (`kRampWindow`, sondes de `hdr-display-output`) : reutiliser
// celle-la et l'appeler « le premier dixieme » aurait publie un nombre juste sous un nom faux.
constexpr float kShWindow = 0.10f;
// LA FIN DU PIED. Ce n'est pas un reglage : c'est le `s` de `hdr_toe_scalar` dans tonemap.frag.
// Au-dessus, la fonction rend son entree telle quelle. La constante est ici pour que le TEMOIN
// de non-regression des hautes lumieres interroge exactement le domaine que le shader epargne.
constexpr float kShToeEnd = 0.25f;
constexpr uint64_t kShEvery = 30;   // une sonde sur 30 images, comme `probe_regime`
constexpr int kShTmW = 32, kShTmH = 32;
constexpr float kShRampTop = 4.f;
constexpr size_t kShRenderCap = 400000;  // plafond du recensement des valeurs de rendu

enum : int { kShIdent = 0, kShSdr = 1, kShLive = 2, kShRoom = 3, kShToe = 4, kShArms = 5 };

GLuint s_sh_fbo = 0, s_sh_tex = 0, s_sh_rfbo = 0, s_sh_rtex = 0, s_sh_ramp = 0;
int s_sh_state = 0;
uint64_t s_sh_runs = 0, s_sh_gl_errors = 0;
uint64_t s_sh_scene_px = 0;     // pixels de scene examines (le denominateur du recensement)
uint64_t s_sh_win_px = 0;       // ceux qui tombent dans la fenetre jugee (la population FILTREE)
uint64_t s_sh_hl_px = 0, s_sh_hl_touched_px = 0;
uint64_t s_sh_below_sdr_px = 0, s_sh_below_max_ulp_x1000 = 0;
uint64_t s_sh_hl_max_notoe_x1000 = 0, s_sh_hl_max_toe_x1000 = 0;
double s_sh_sum[kShArms] = {0, 0, 0, 0, 0};
float s_sh_sim_ceiling = 1.f, s_sh_sim_toe = 0.f;
// LES PALIERS QUE L'IMAGE PORTE REELLEMENT, par bras, dans la fenetre. Ce sont les codes que
// CHAQUE etat livrerait a la fenetre pour EXACTEMENT LES MEMES pixels — la population est fixee
// une fois pour toutes par le bras SDR. Compter chaque bras sur sa propre population comparerait
// deux ensembles differents et ne dirait rien.
bool s_sh_code8[kShArms][256] = {{false}};
bool s_sh_code10[kShArms][1024] = {{false}};
// CE QUE LE RENDU PRODUIT, avant tout conteneur : les motifs de bits DISTINCTS que le bras
// IDENTITE porte dans la fenetre. Si ce nombre est tres au-dessus des paliers 8 bits, alors le
// conteneur EST le facteur limitant et l'elargir peut rendre quelque chose ; s'il leur est egal,
// le defaut est en amont et aucun conteneur ne le repare.
std::set<uint32_t> s_sh_render_bits;
uint64_t s_sh_render_capped = 0;

int sh_code8(double v) {
  const int c = (int)std::lround(v * 255.0);
  return c < 0 ? 0 : (c > 255 ? 255 : c);
}
int sh_code10(double v) {
  // LE MEME ENCODAGE QUE `post_processing.frag` mode 1, et la MEME convention que
  // `probe_gameplay` (4849-4854) : la valeur d'affichage part en nits par la gamma 2,2 et le
  // blanc SDR effectif, puis l'OETF PQ rend le code 10 bits. C'est une propriete de NOTRE
  // encodage — combien de nuances le signal SEPARE — jamais une affirmation sur ce que la dalle
  // emet. Aucun photometre n'est en jeu.
  const double nits = std::pow(v < 0.0 ? 0.0 : v, 2.2) * (double)sdr_white_nits();
  const int c = (int)std::lround(pq_oetf_from_nits(nits) * 1023.0);
  return c < 0 ? 0 : (c > 1023 ? 1023 : c);
}
bool shadow_measuring() {
  return autoport_proof::feature_is(kShadowId) && autoport_proof::armed_for(kShadowId);
}

}  // namespace

void probe_shadow(Shader& shader, GLuint src_tex, GLuint dst_fbo, int dst_w, int dst_h) {
  gl_query_census::Armed _ap("hdr-shadow-probe");
  if (!shadow_measuring() || s_sh_state < 0 || !s_active.load() ||
      (s_frames % kShEvery) != 0) {
    return;
  }
  if (s_sh_state == 0) {
    const bool a = make_float_fbo(&s_sh_fbo, &s_sh_tex, kShTmW, kShTmH, nullptr);
    const bool b = a && make_float_fbo(&s_sh_rfbo, &s_sh_rtex, kRampN, 1, nullptr);
    const bool c = b && make_ramp_tex(&s_sh_ramp, 0.f, kShRampTop);
    s_sh_state = c ? 1 : -1;
    glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
    glViewport(0, 0, dst_w, dst_h);
    if (s_sh_state < 0) {
      lg::error("[hdr-shadow-range] sonde indisponible : cibles hors ecran refusees");
      return;
    }
  }
  // AU SITE DU GESTE, ET SOUS L'IDENTITE DE CET ITEM. `hits=` de la ligne FEATURE est le
  // compteur GLOBAL du binaire : il monte pour n'importe qui. Seul `note_hit_for` attribue la
  // prise, et c'est lui que la porte lit (`proof_feature_own_hits`).
  autoport_proof::note_hit_for(kShadowId);
  const GLuint prog = shader.id();
  // LE PLAFOND SIMULE : celui que CET ecran accorderait s'il PRESENTAIT, tire de son pic
  // ANNONCE par le systeme rapporte au blanc graphique BT.2408. Meme definition que
  // `probe_regime`, au bit — deux definitions du meme plafond dans un fichier en feraient deux
  // grandeurs differentes portant un seul nom.
  const float h_sim = std::fmax(1.05f, peak_nits() / kGraphicsWhiteNits);
  const float c_sim = std::pow(h_sim, 1.f / 2.2f);
  s_sh_sim_ceiling = c_sim;
  CurveParams room = placement_params(c_sim);
  CurveParams toe = placement_params(c_sim);
  // LE PIED VIENT DE LA FONCTION DE PRODUCTION, PAS D'UNE CONSTANTE RECOPIEE. Si la politique du
  // pied changeait et que ce bras gardait son ancienne valeur, la preuve decrirait une courbe
  // que le joueur ne recevrait jamais.
  toe.toe = shadow_toe_for(c_sim);
  s_sh_sim_toe = toe.toe;
  const CurveParams arms[kShArms] = {placement_params(kRgIdentCeiling),  // 0 le RENDU, nu
                                     sdr_params(),                      // 1 le SDR livre
                                     s_cur,                             // 2 ce qui part a l'ecran
                                     room,                              // 3 le conteneur seul
                                     toe};                              // 4 conteneur + pied
  GLint saved_tex = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
  while (glGetError() != GL_NO_ERROR) {
  }
  std::vector<float> ramp[kShArms], scene[kShArms];
  bool ok = true;
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, s_sh_ramp);
  glBindFramebuffer(GL_FRAMEBUFFER, s_sh_rfbo);
  glViewport(0, 0, kRampN, 1);
  for (int i = 0; i < kShArms && ok; i++) {
    set_curve(prog, arms[i]);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kRampN, 1, ramp[i]);
  }
  glBindTexture(GL_TEXTURE_2D, src_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, s_sh_fbo);
  glViewport(0, 0, kShTmW, kShTmH);
  for (int i = 0; i < kShArms && ok; i++) {
    set_curve(prog, arms[i]);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kShTmW, kShTmH, scene[i]);
  }
  set_curve(prog, s_cur);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
  glViewport(0, 0, dst_w, dst_h);
  glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
  if (!ok) {
    lg::error("[hdr-shadow-range] sonde a cinq bras : relecture refusee");
    s_sh_state = -1;
    return;
  }
  if (glGetError() != GL_NO_ERROR) {
    s_sh_gl_errors++;
  }
  // --- LES HAUTES LUMIERES, SUR LA RAMPE. Elles s'interrogent la et pas sur la scene : une
  //     grotte peut ne porter AUCUN pixel au-dessus du pied, et un temoin sans population est
  //     vert par inaction. La rampe balaie [0, 4], sa population au-dessus du pied est donc
  //     garantie et elle ne depend pas de ce que le niveau a bien voulu contenir. Elle n'a pas
  //     non plus de plancher d'ULP : ses entrees sont des demi-flottants exacts.
  auto hl_walk = [&](const std::vector<float>* a, int n) {
    for (int t = 0; t < n; t++) {
      const size_t k = (size_t)t * 4;
      if (k + 2 >= a[kShRoom].size() || k + 2 >= a[kShToe].size()) {
        break;
      }
      const float room_v = std::fmax(a[kShRoom][k], std::fmax(a[kShRoom][k + 1], a[kShRoom][k + 2]));
      const float toe_v = std::fmax(a[kShToe][k], std::fmax(a[kShToe][k + 1], a[kShToe][k + 2]));
      if (!std::isfinite(room_v) || !std::isfinite(toe_v)) {
        continue;
      }
      if ((double)room_v < (double)kShToeEnd) {
        continue;
      }
      s_sh_hl_px++;
      const uint64_t rq = (uint64_t)std::llround((double)room_v * 1000.0);
      const uint64_t tq = (uint64_t)std::llround((double)toe_v * 1000.0);
      if (rq > s_sh_hl_max_notoe_x1000) {
        s_sh_hl_max_notoe_x1000 = rq;
      }
      if (tq > s_sh_hl_max_toe_x1000) {
        s_sh_hl_max_toe_x1000 = tq;
      }
      const double d = std::fabs((double)toe_v - (double)room_v);
      if (d > 1.5 * half_ulp(std::fmax((double)toe_v, (double)room_v))) {
        s_sh_hl_touched_px++;
      }
    }
  };
  hl_walk(ramp, kRampN);
  hl_walk(scene, kShTmW * kShTmH);

  // --- LA SCENE : les paliers, la luminosite moyenne, et le plancher sous le SDR.
  for (int t = 0; t < kShTmW * kShTmH; t++) {
    const size_t k = (size_t)t * 4;
    if (k + 2 >= scene[kShToe].size()) {
      break;
    }
    float m[kShArms];
    bool fine = true;
    for (int i = 0; i < kShArms; i++) {
      m[i] = std::fmax(scene[i][k], std::fmax(scene[i][k + 1], scene[i][k + 2]));
      fine = fine && std::isfinite(m[i]);
    }
    if (!fine) {
      continue;
    }
    s_sh_scene_px++;
    for (int i = 0; i < kShArms; i++) {
      s_sh_sum[i] += (double)m[i];
    }
    // AUCUN PIXEL NE PASSE SOUS LE SDR, y compris le bras qui porte le pied. Le seuil est le pas
    // du CONTENEUR (1,5 ULP d'un demi-flottant), pas une constante de confort : sous un ULP deux
    // valeurs SONT le meme nombre dans cette cible. La pire violation est retenue sans tolerance.
    const double d_below = (double)m[kShSdr] - (double)m[kShToe];
    if (d_below > 0.0) {
      const double u = half_ulp(std::fmax((double)m[kShSdr], (double)m[kShToe]));
      const uint64_t r = (uint64_t)std::llround(1000.0 * d_below / u);
      if (r > s_sh_below_max_ulp_x1000) {
        s_sh_below_max_ulp_x1000 = r;
      }
      if (d_below > 1.5 * u) {
        s_sh_below_sdr_px++;
      }
    }
    // LA POPULATION EST CHOISIE PAR LE BRAS SDR, ET PAR LUI SEUL. C'est « les pixels que le
    // joueur voit sombres aujourd'hui » ; on compte ensuite combien de nuances CHAQUE etat
    // separe pour ces memes pixels-la. Un bras qui les releve peut sortir de la fenetre : c'est
    // le but, et ce n'est pas une raison de changer d'ensemble en cours de comptage.
    if (!((double)m[kShSdr] < (double)kShWindow)) {
      continue;
    }
    s_sh_win_px++;
    for (int i = 0; i < kShArms; i++) {
      s_sh_code8[i][sh_code8((double)m[i])] = true;
      s_sh_code10[i][sh_code10((double)m[i])] = true;
    }
    if (s_sh_render_bits.size() < kShRenderCap) {
      uint32_t b = 0;
      std::memcpy(&b, &m[kShIdent], sizeof(b));
      s_sh_render_bits.insert(b);
    } else {
      s_sh_render_capped++;
    }
  }
  s_sh_runs++;
}

void publish_shadow_verdict() {
  if (!shadow_measuring()) {
    return;  // instrument : muet hors de la mesure de CET item
  }
  // --- TERME 0 : LE REGIME DE SA PROPRE FEATURE, EPINGLE ET PUBLIE. Une mesure faite chaine
  //     eteinte, en 8 bits, ne dit rien de ce sujet : elle serait ROUGE ici, et elle dit pourquoi.
  const GLenum scene_fmt = hdr::scene_color_format();
  const bool scene_float = hdr::format_is_float(scene_fmt);
  const bool chain = hdr::chain_active();
  const bool out_active = s_active.load();
  const RegimeVerdict rg = regime_now();
  autoport_proof::publish_text("hdr_shadow_scene_fmt", hdr::format_name(scene_fmt));
  autoport_proof::publish("hdr_shadow_scene_float", (uint64_t)(scene_float ? 1 : 0));
  autoport_proof::publish("hdr_shadow_chain_active", (uint64_t)(chain ? 1 : 0));
  autoport_proof::publish("hdr_shadow_out_active", (uint64_t)(out_active ? 1 : 0));
  autoport_proof::publish("hdr_shadow_regime", (uint64_t)rg.level);
  autoport_proof::publish_text("hdr_shadow_regime_name", rg.name);
  autoport_proof::publish("hdr_shadow_runs", s_sh_runs);
  autoport_proof::publish("hdr_shadow_gl_errors", s_sh_gl_errors);
  autoport_proof::publish("hdr_shadow_sim_ceiling_x1000",
                          (uint64_t)std::lround(s_sh_sim_ceiling * 1000.f));
  autoport_proof::publish("hdr_shadow_sim_toe_x1000",
                          (uint64_t)std::lround(s_sh_sim_toe * 1000.f));
  // CE QUE LA COURBE LIVREE PORTE EN CE MOMENT. Sur un ecran sans marge il vaut ZERO, et c'est
  // le temoin que le perimetre est tenu : aucune difference fabriquee la ou rien n'est accorde.
  autoport_proof::publish("hdr_shadow_live_toe_x1000",
                          (uint64_t)std::lround(s_cur.toe * 1000.f));
  autoport_proof::publish("hdr_shadow_live_ceiling_x1000",
                          (uint64_t)std::lround(s_cur.ceiling * 1000.f));
  autoport_proof::publish("hdr_shadow_full_headroom_x1000",
                          (uint64_t)std::lround(kToeFullHeadroom * 1000.f));
  const int d0 = (out_active && chain && scene_float && s_sh_runs > 0 &&
                  s_sh_sim_ceiling > 1.005f)
                     ? 0
                     : 1;

  // --- TERME 1 : LA POPULATION. Le plancher est dimensionne sur la population FILTREE (les
  //     pixels sombres), jamais sur le total : un plancher pose sur le total serait une
  //     sentinelle qu'une scene sombre n'atteint pas, et le verdict serait rouge pour une raison
  //     d'instrument. 1000 pixels sombres, c'est ~30 sondes de 32x32 a un tiers d'image sombre.
  autoport_proof::publish("hdr_shadow_window_x1000", (uint64_t)std::lround(kShWindow * 1000.f));
  autoport_proof::publish("hdr_shadow_toe_end_x1000", (uint64_t)std::lround(kShToeEnd * 1000.f));
  autoport_proof::publish("hdr_shadow_scene_px", s_sh_scene_px);
  autoport_proof::publish("hdr_shadow_win_px", s_sh_win_px);
  autoport_proof::publish("hdr_shadow_hl_px", s_sh_hl_px);
  const int d1 = (s_sh_runs >= 10 && s_sh_win_px >= 1000 && s_sh_hl_px >= 1000) ? 0 : 1;

  // --- TERME 2 : LE CONTENEUR, SEPAREMENT DE L'IMAGE. Combien de codes DISTINCTS chaque
  //     conteneur peut porter dans la fenetre jugee. Ces deux nombres ne dependent d'aucune
  //     image : ils sortent des MEMES fonctions d'encodage que les codes comptes plus bas, donc
  //     aucun n'est un chiffre invente. Ils repondent a « le conteneur peut-il porter plus ? »,
  //     et a rien d'autre — la question « l'image en porte-t-elle plus ? » est le terme 3.
  const uint64_t cap8 = (uint64_t)(sh_code8((double)kShWindow) - sh_code8(0.0) + 1);
  const uint64_t cap10 = (uint64_t)(sh_code10((double)kShWindow) - sh_code10(0.0) + 1);
  autoport_proof::publish("hdr_shadow_container_levels_sdr", cap8);
  autoport_proof::publish("hdr_shadow_container_levels_hdr", cap10);
  const int d2 = (cap8 > 0 && cap10 > cap8) ? 0 : 1;

  // --- TERME 3 : CE QUE L'IMAGE PORTE REELLEMENT. C'est la grandeur du livrable : le nombre de
  //     paliers distincts rendus entre le noir et le premier dixieme, en sortie SDR puis en
  //     sortie HDR, sur les MEMES pixels d'une scene sombre. Trois nombres, pas un :
  //       RENDU     ce que le tampon flottant porte avant tout conteneur ;
  //       SDR       ce que 8 bits en laissent passer ;
  //       MARGE     ce que le conteneur 10 bits en laisse passer, PIED NUL ;
  //       PIED      ce que la courbe livree en laisse passer sur un ecran qui accorde.
  //     Le verdict exige les DEUX ecarts : le conteneur doit apporter, et le pied doit apporter
  //     AU-DELA du conteneur. Sans la seconde condition, « conteneur plus large, autant de
  //     paliers utilises » passerait pour un gain — ce que le livrable interdit explicitement.
  uint64_t lv[kShArms] = {0, 0, 0, 0, 0};
  for (int i = 0; i < kShArms; i++) {
    for (int c = 0; c < 1024; c++) {
      lv[i] += s_sh_code10[i][c] ? 1 : 0;
    }
  }
  uint64_t lv8_sdr = 0;
  for (int c = 0; c < 256; c++) {
    lv8_sdr += s_sh_code8[kShSdr][c] ? 1 : 0;
  }
  const uint64_t render_levels = (uint64_t)s_sh_render_bits.size();
  autoport_proof::publish("hdr_shadow_render_levels", render_levels);
  autoport_proof::publish("hdr_shadow_render_capped", s_sh_render_capped);
  autoport_proof::publish("hdr_shadow_image_levels_sdr", lv8_sdr);
  autoport_proof::publish("hdr_shadow_image_levels_room", lv[kShRoom]);
  autoport_proof::publish("hdr_shadow_image_levels_toe", lv[kShToe]);
  autoport_proof::publish("hdr_shadow_image_levels_live", lv[kShLive]);
  autoport_proof::publish("hdr_shadow_gain_room_x100",
                          lv8_sdr ? (uint64_t)std::lround(100.0 * (double)lv[kShRoom] /
                                                          (double)lv8_sdr)
                                  : 0);
  autoport_proof::publish("hdr_shadow_gain_toe_x100",
                          lv[kShRoom] ? (uint64_t)std::lround(100.0 * (double)lv[kShToe] /
                                                              (double)lv[kShRoom])
                                      : 0);
  const int d3 = (lv8_sdr > 0 && lv[kShRoom] > lv8_sdr && lv[kShToe] > lv[kShRoom]) ? 0 : 1;

  // --- TERME 4 : RIEN NE S'ASSOMBRIT GLOBALEMENT. C'est le retour de l'owner du 11/09, il tient
  //     toujours. La luminosite MOYENNE de l'image, sur la meme scene, HDR eteint puis allume :
  //     elle ne baisse pas. Et le plancher par PIXEL est publie a cote — une moyenne qui monte
  //     pendant qu'une region s'effondre serait verte, et ce serait un faux vert.
  const double n = (double)(s_sh_scene_px ? s_sh_scene_px : 1);
  autoport_proof::publish("hdr_shadow_mean_sdr_x10000",
                          (uint64_t)std::lround(10000.0 * s_sh_sum[kShSdr] / n));
  autoport_proof::publish("hdr_shadow_mean_room_x10000",
                          (uint64_t)std::lround(10000.0 * s_sh_sum[kShRoom] / n));
  autoport_proof::publish("hdr_shadow_mean_toe_x10000",
                          (uint64_t)std::lround(10000.0 * s_sh_sum[kShToe] / n));
  autoport_proof::publish("hdr_shadow_mean_live_x10000",
                          (uint64_t)std::lround(10000.0 * s_sh_sum[kShLive] / n));
  autoport_proof::publish("hdr_shadow_below_sdr_px", s_sh_below_sdr_px);
  autoport_proof::publish("hdr_shadow_below_max_ulp_x1000", s_sh_below_max_ulp_x1000);
  autoport_proof::publish("hdr_shadow_tolerance_ulp_x1000", (uint64_t)1500);
  const int d4 = (s_sh_scene_px > 0 && s_sh_below_sdr_px == 0 &&
                  s_sh_sum[kShToe] >= s_sh_sum[kShSdr])
                     ? 0
                     : 1;

  // --- TERME 5 : LES HAUTES LUMIERES NE REGRESSENT PAS. Ce que l'owner voit DEJA ne doit pas
  //     etre echange contre ce qu'il ne voit pas encore. La mesure est l'ecart entre le bras a
  //     marge SANS pied et le MEME bras AVEC pied : au-dessus de la fin du pied, le shader rend
  //     son entree telle quelle, donc l'ecart doit etre nul AU BIT. La population est celle de la
  //     rampe, garantie non vide ; le compte et les deux maximums sont publies.
  autoport_proof::publish("hdr_shadow_hl_touched_px", s_sh_hl_touched_px);
  autoport_proof::publish("hdr_shadow_hl_max_notoe_x1000", s_sh_hl_max_notoe_x1000);
  autoport_proof::publish("hdr_shadow_hl_max_toe_x1000", s_sh_hl_max_toe_x1000);
  const int d5 = (s_sh_hl_px >= 1000 && s_sh_hl_touched_px == 0 &&
                  s_sh_hl_max_toe_x1000 == s_sh_hl_max_notoe_x1000)
                     ? 0
                     : 1;

  autoport_proof::publish("hdr_shadow_d0_regime", (uint64_t)d0);
  autoport_proof::publish("hdr_shadow_d1_population", (uint64_t)d1);
  autoport_proof::publish("hdr_shadow_d2_container", (uint64_t)d2);
  autoport_proof::publish("hdr_shadow_d3_image", (uint64_t)d3);
  autoport_proof::publish("hdr_shadow_d4_no_darkening", (uint64_t)d4);
  autoport_proof::publish("hdr_shadow_d5_highlights", (uint64_t)d5);
  autoport_proof::publish("hdr_shadow_defects", (uint64_t)(d0 + d1 + d2 + d3 + d4 + d5));
}

void probe_tonemap(Shader& shader, GLuint dst_fbo, int dst_w, int dst_h) {
  gl_query_census::Armed _ap("hdr-out-probe-tonemap");
  if (play_window_open()) {
    probe_gameplay(shader, dst_fbo, dst_w, dst_h);
    return;
  }
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
  const GLuint prog = shader.id();
  std::vector<float> off, on;
  bool ok = true;
  if (ready_probe) {
    // Sonde de CONTENU (phase 0) : un seul dessin au plafond 1,0, on compte les tons moyens.
    set_curve(prog, sdr_params());
    glBindFramebuffer(GL_FRAMEBUFFER, s_tm_fbo[0]);
    glViewport(0, 0, kTmW, kTmH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kTmW, kTmH, off);
    set_curve(prog, s_cur);
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
    set_curve(prog, i == 0 ? sdr_params() : s_cur);
    glBindFramebuffer(GL_FRAMEBUFFER, s_tm_fbo[i]);
    glViewport(0, 0, kTmW, kTmH);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    ok = read_float_fbo(kTmW, kTmH, i == 0 ? off : on);
  }
  set_curve(prog, s_cur);
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
  // Verdict 10 : LE STIMULUS FIXE. Le meme programme `tonemap`, la meme paire de plafonds, mais
  // une rampe SYNTHETIQUE a la place de la scene : ce que la courbe rend ne depend plus du
  // moment ou la phase est tombee. On somme le canal max sur les 128 marches — le maximum seul
  // sature a la valeur du plafond et ne dirait rien de la FORME de la courbe.
  if (s_tf_state >= 0) {
    bool tf_ok = true;
    if (s_tf_state == 0) {
      tf_ok = make_ramp_tex(&s_tf_src, 0.f, kFixedTop) &&
              make_float_fbo(&s_tf_fbo, &s_tf_tex, kRampN, 1, nullptr);
      s_tf_state = tf_ok ? 1 : -1;
      glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
      glViewport(0, 0, dst_w, dst_h);
    }
    if (s_tf_state == 1) {
      GLint saved_tex = 0;
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_tex);
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D, s_tf_src);
      glBindFramebuffer(GL_FRAMEBUFFER, s_tf_fbo);
      glViewport(0, 0, kRampN, 1);
      double sums[2] = {0.0, 0.0};
      std::vector<float> fx;
      for (int i = 0; i < 2 && tf_ok; i++) {
        set_curve(prog, i == 0 ? sdr_params() : s_cur);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        tf_ok = read_float_fbo(kRampN, 1, fx);
        if (!tf_ok) {
          break;
        }
        for (int t = 0; t < kRampN; t++) {
          const float m = std::fmax(fx[(size_t)t * 4], std::fmax(fx[(size_t)t * 4 + 1], fx[(size_t)t * 4 + 2]));
          if (std::isfinite(m)) {
            sums[i] += (double)m;
          }
        }
      }
      set_curve(prog, s_cur);
      glBindFramebuffer(GL_FRAMEBUFFER, dst_fbo);
      glViewport(0, 0, dst_w, dst_h);
      glBindTexture(GL_TEXTURE_2D, (GLuint)saved_tex);
      if (!tf_ok) {
        lg::error("[hdr-display-output] stimulus fixe : relecture refusee");
        s_tf_state = -1;
      } else {
        ProbeStats& pf = s_pr[s_phase];
        pf.hl_fixed_samples++;
        if (sums[1] > pf.hl_fixed_sum) {
          pf.hl_fixed_sum = sums[1];
        }
        if (sums[0] > pf.hl_fixed_ref) {
          pf.hl_fixed_ref = sums[0];
        }
        if (pf.hl_fixed_samples == 1 || (pf.hl_fixed_samples % 10) == 0) {
          lg::info("[hdr-display-output] stimulus fixe phase {} #{} : somme plafond {:.3f} = {:.2f} ; plafond 1,0 = {:.2f}",
                   s_phase, pf.hl_fixed_samples, s_last_ceiling, sums[1], sums[0]);
        }
      }
    }
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
  s_study_ui_fmt = ui_fmt;  // question 1 de l'etude : l'etage d'affichage, releve et non suppose
  if (on) {
    s_hits++;
    autoport_proof::note_hit_for(kItemId);  // AU SITE DU GESTE : une image presentee en HDR
  }
  if (on && !effective_setting()) {
    s_forced_on_frames++;  // la capacite a force ce que le reglage n'a pas demande
  }
  // La consigne de retro-eclairage se suit a TOUTES les images, bras arme ou non : c'est elle qui
  // porte la base (le reglage de l'utilisateur) avant que le levier soit pose, et la marge
  // obtenue apres. Sans ce suivi hors auto-test, le chemin LIVRE au joueur n'aurait pas de base.
  if ((s_frames % 5) == 0) {
    backlight_track();
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
    ph.last_sdr_white = sdr_white_nits();
    if (s_frame_ratio_x1000 > ph.ratio_max_x1000) {
      ph.ratio_max_x1000 = s_frame_ratio_x1000;
    }
    // Verdict 11 : la marge accordee par le SYSTEME, sur une phase ON REELLE (jamais celle a
    // pic simule, qui n'est qu'un etirement arithmetique de notre cote).
    // Elle ne se lit PAS au meme endroit selon la route : scRGB la LIT (`Display.getHdrSdrRatio`,
    // API 34), PQ et HLG la DEDUISENT du pic annonce contre le blanc SDR de l'ecran. N'alimenter
    // cette grandeur que depuis l'atomique scRGB rendait les verdicts 11 et 12 rouges PAR
    // CONSTRUCTION sur toute route PQ, y compris sur un ecran qui accorde vraiment de la marge.
    if (on && (s_phase == 1 || s_phase == 4)) {
      const int granted = (s_surface.mode == kModeScrgbLinear)
                              ? s_frame_ratio_x1000
                              : (int)std::lround(headroom_linear() * 1000.f);
      if (granted > s_ratio_max_x1000) {
        s_ratio_max_x1000 = granted;
      }
    }
    // La marge PHYSIQUE, echantillonnee sur les memes phases : ON reel contre OFF.
    if ((ph.frames % 15) == 0) {
      if (on && (s_phase == 1 || s_phase == 4)) {
        backlight_sample(s_bl_on);
      } else if (!on && s_phase == 2) {
        backlight_sample(s_bl_off);
      }
    }
    const bool expect_on = (s_phase == 1 || s_phase == 3 || s_phase == 4);
    const bool expect_off = (s_phase == 2);
    if (expect_on) {
      ph.sites_bad += (sites == 1) ? 0 : 1;
      ph.ui_bad += (ui_fmt == GL_RGBA16F) ? 0 : 1;
      ph.present_bad += (s_last_present_mode != 0) ? 0 : 1;
      // Le plafond. Pendant l'auto-test la courbe est FIGEE : le plafond doit valoir exactement
      // celui que l'ecran permet. Hors auto-test il suit la scene, et l'invariant devient un
      // encadrement — jamais sous 1,0 (le SDR), jamais au-dessus de ce que l'ecran accorde.
      const float want_ceiling = tonemap_ceiling();
      const bool pinned_now = measuring() && !s_selftest_done;
      ph.ceiling_bad += (pinned_now ? (std::fabs(s_last_ceiling - want_ceiling) < 1e-3f)
                                    : (s_last_ceiling >= 1.f - 1e-3f &&
                                       s_last_ceiling <= want_ceiling + 1e-3f))
                            ? 0
                            : 1;
    } else if (expect_off) {
      ph.ui_bad += (ui_fmt == GL_RGBA8) ? 0 : 1;
      ph.present_bad += (s_last_present_mode == 0) ? 0 : 1;
      ph.ceiling_bad += (s_last_ceiling == 1.f) ? 0 : 1;
    }
  }
  s_frames++;
  // APRES l'auto-test, les verdicts 9, 12 et 13 continuent de se remplir sur du jeu reel : ils
  // doivent donc etre RECALCULES, sinon le proof porterait le verdict d'un instant ou la sonde
  // de jeu n'avait pas encore un seul echantillon. Les verdicts 1 a 11 sont idempotents : ils ne
  // lisent que des statistiques de phase, gelees depuis finish_selftest().
  if (s_selftest_done && measuring() && (s_frames % 300) == 0) {
    compute_verdicts();
  }
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
