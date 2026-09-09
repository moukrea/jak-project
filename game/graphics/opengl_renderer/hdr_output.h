#pragma once

// hdr_output — LA SORTIE HDR VERS L'ECRAN (item `hdr-display-output`).
//
// Deux sujets distincts, et ce fichier ne porte que le second :
//   * le CALCUL HDR interne (item `lighting-hdr`, hdr.h) : tampon de scene RGBA16F et un seul
//     tone map vers du SDR bien compresse. C'est la sortie PAR DEFAUT, validee par l'owner.
//   * la SORTIE HDR vers l'ecran (ici) : quand l'ecran ANNONCE un mode HDR, le joueur peut
//     demander que le jeu presente son image dans cet espace (HDR10 : BT.2020 + PQ, 10 bits).
//     Le tone map n'ecrase alors plus les hautes lumieres a 1,0 : il les laisse monter jusqu'a
//     la marge de l'ecran (`tonemap_ceiling`), et le quad final ENCODE (OETF PQ) sans
//     comprimer. Une seule compression de plage sur le chemin, la meme qu'en SDR, avec un
//     plafond plus haut.
//
// CE QUI EST VRAI DANS LES DEUX ETATS :
//   * OFF (defaut hors auto-configuration) : rien de ce fichier ne touche l'image. Le tampon UI
//     reste RGBA8, le plafond du tone map reste 1,0, le quad final reste une recopie, la surface
//     reste celle d'avant l'item (8 bits, colorspace lineaire). Identique au bit a lighting-hdr.
//   * ON n'existe que si un mode est ANNONCE par le systeme ET par la couche de presentation
//     (`modes_available() != 0`). Sans mode, `set_enabled(true)` ne fait rien et le dit.
//   * L'interrupteur est celui du JOUEUR : la capacite de l'ecran ne force jamais ON
//     (`hdr_out_forced_on` compte les images ou la surface serait HDR sans que le reglage le
//     demande — il doit rester a zero).
//
// PREUVE (`lib/proof_run.sh hdr-display-output device`) : quand le harnais mesure cet item,
// `frame_end` deroule un auto-test en trois phases — etat charge, ON, OFF — en passant par le
// MEME chemin que le menu (`request`), et publie des grandeurs lues sur la SURFACE (colorspace
// rendu par eglQuerySurface, bits rouges rendus par glGetIntegerv) et dans settings.ini relu
// du disque. `hdr_out_defects` est la somme de six verdicts publies un par un.

#include <cstdint>
#include <functional>

#include "game/graphics/pipelines/opengl.h"

class Shader;

namespace hdr_output {

constexpr const char* kItemId = "hdr-display-output";

// Modes de sortie, en masque. Un seul est livre : HDR10 (BT.2020, PQ, RGB10_A2).
enum Mode : uint32_t { kModeNone = 0, kModeHdr10Pq = 1 };

// Types HDR annonces par le systeme (Android `Display.HdrCapabilities`), en masque `1 << type`.
enum SysType : uint32_t {
  kSysDolbyVision = 1u << 1,
  kSysHdr10 = 1u << 2,
  kSysHlg = 1u << 3,
  kSysHdr10Plus = 1u << 4,
  kSysSdl = 1u << 8,  // bureau : SDL annonce `SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN`
};

// ---------------------------------------------------------------------------- capacites ----

// Ce que le SYSTEME annonce pour l'ecran. Android : depuis Java (Display.getHdrCapabilities),
// avant le demarrage du rendu. Bureau : depuis SDL, apres creation de la fenetre.
void set_system_caps(uint32_t sys_types_mask,
                     int max_lum_nits,
                     int max_avg_lum_nits,
                     int min_lum_x10000,
                     bool wide_gamut);

// Ce que la COUCHE DE PRESENTATION annonce (EGL sur Android, SDL sur bureau). Fil GL.
struct PlatformCaps {
  bool probed = false;
  bool egl_bt2020_pq = false;      // EGL_EXT_gl_colorspace_bt2020_pq
  bool egl_scrgb_linear = false;   // EGL_EXT_gl_colorspace_scrgb_linear
  bool egl_fp16 = false;           // EGL_EXT_pixel_format_float
  bool egl_no_config_ctx = false;  // EGL_KHR_no_config_context
  bool egl_smpte2086 = false;      // EGL_EXT_surface_SMPTE2086_metadata
  bool config_10bit = false;       // un EGLConfig RGB 10/10/10 + fenetre + ES3 existe
  bool sdl_display_hdr = false;    // bureau : SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN
  bool sdl_window_hdr = false;     // bureau : SDL_PROP_WINDOW_HDR_ENABLED_BOOLEAN
  int sdl_headroom_x100 = 0;       // bureau : SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT x100
};
void set_platform_caps(const PlatformCaps& caps);

// Masque des modes REELLEMENT disponibles : systeme ET presentation d'accord. 0 = l'option
// n'existe pas pour ce joueur (rangee cachee).
uint32_t modes_available();
const char* mode_name(uint32_t mode);
// Texte des capacites, sans espace, publie sous `hdr_out_display_caps`.
const char* caps_string();

// ------------------------------------------------------------------- l'interrupteur ----

// LE REGLAGE DU JOUEUR, pousse par GOAL (fil EE) au chargement des reglages et a chaque
// changement dans le menu — jamais par image. Prend effet a l'image suivante, sur le fil GL.
void set_enabled(bool on);
bool enabled();  // le reglage
bool active();   // la surface est HDR EN CE MOMENT (apres bascule reussie)

// L'etat de la surface tel que la PLATEFORME le lit apres (re)creation. `colorspace` est la
// valeur EGL brute rendue par eglQuerySurface(EGL_GL_COLORSPACE_KHR), 0 si non interrogeable.
struct SurfaceState {
  bool hdr = false;
  int red_bits = 0;
  int colorspace = 0;
};
// Installe par le renderer qui SAIT recreer sa surface (Android). Rend vrai si la surface est
// maintenant dans l'etat demande, et remplit `out`. Sans switcher installe (bureau), aucun mode.
using Switcher = std::function<bool(bool want_hdr, SurfaceState* out)>;
void install_switcher(Switcher fn);
// L'etat initial de la surface, avant toute bascule.
void note_surface_state(const SurfaceState& st);
// Fil GL, avant de dessiner une image : applique une demande en attente (menu ou auto-test).
void apply_pending_on_gl_thread();

// ---------------------------------------------------------------- ce que le rendu lit ----

GLenum ui_buffer_format();      // GL_RGBA16F quand active(), sinon GL_RGBA8
GLenum window_target_format();  // GL_RGB10_A2 quand active(), sinon GL_RGBA8
float paper_white_nits();       // blanc de reference (SDR 1,0) en nits
float tonemap_ceiling();        // 1,0 hors HDR ; max_lum / blanc de reference en HDR
// Le quad final : `u_out_mode` (0 recopie, 1 PQ), `u_out_paper_white`, `u_out_max_nits`.
void push_present_uniforms(Shader& shader);

// Fin d'image, fil GL, APRES hdr::frame_end. `sites` = compressions de plage de cette image
// telles que hdr.cpp les recense (`hdr::last_frame_sites()`) ; `ui_fmt` = le format du tampon
// UI REELLEMENT utilise par ce renderer pour cette image (GL_RGBA8 si pas de passe UI).
void frame_end(uint64_t sites, GLenum ui_fmt);

// ----------------------------------------------------------------- rapports de GOAL ----

// La rangee « HDR Output » est-elle dans le menu (1) ou cachee (0) ? Rapporte par GOAL au
// demarrage (meme regle que le menu) et a chaque ouverture du menu (decision reelle).
void note_option_visible(int visible);
// Le reglage vient d'etre etabli : `source` 0 = lu dans settings.ini, 1 = auto-configuration
// (premier demarrage ou cle absente). `value` 0/1.
void note_setting_loaded(int value, int source);

// Relecture de settings.ini sur le disque : 1/0 = valeur de `hdr-output?`, -1 = cle absente,
// -2 = fichier absent ou illisible.
int read_persisted_setting();

}  // namespace hdr_output
