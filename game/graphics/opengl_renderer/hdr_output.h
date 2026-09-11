#pragma once

// hdr_output — LA SORTIE HDR VERS L'ECRAN (item `hdr-display-output`).
//
// Deux sujets distincts, et ce fichier ne porte que le second :
//   * le CALCUL HDR interne (item `lighting-hdr`, hdr.h) : tampon de scene RGBA16F et un seul
//     tone map vers du SDR bien compresse. C'est la sortie PAR DEFAUT, validee par l'owner.
//   * la SORTIE HDR vers l'ecran (ici) : quand l'ecran ANNONCE un mode HDR, le joueur peut
//     demander que le jeu presente son image dans cet espace. Le tone map n'ecrase alors plus
//     les hautes lumieres a 1,0 : il les laisse monter jusqu'a la MARGE que le systeme accorde
//     au-dessus de son blanc SDR, et le quad final ENCODE sans comprimer.
//
// LE BLANC DE REFERENCE — la lecon du refus owner du 09/09 (essai 2).
//   L'essai 2 encodait le blanc du jeu (UI, sous-titres, sprites, scene a 1,0) a 203 nits PQ
//   absolus (BT.2408). Or ce que l'ecran montre comme « blanc SDR » n'est pas 203 nits : c'est
//   ce que le compositeur du systeme decide, et il ne le publie pas en nits. Resultat : tout
//   sortait sous le blanc SDR, l'UI grise. Regle desormais : le blanc du jeu (1,0) sort AU BLANC
//   SDR DU SYSTEME, jamais en dessous ; seules les valeurs au-dessus de 1,0 (hautes lumieres
//   laissees par le tone map) montent dans la marge. Deux profils, selon ce que le systeme sait
//   dire :
//   * scRGB lineaire (Android 14+, API 34) : surface RGBA16F, colorspace
//     EGL_EXT_gl_colorspace_scrgb_linear. Par CONTRAT du compositeur, 1,0 = le blanc SDR courant
//     de l'ecran (quelle que soit la luminosite reglee par le joueur) et la marge au-dessus est
//     `Display.getHdrSdrRatio()`, accordee par le systeme via
//     SurfaceControl.Transaction.setExtendedRangeBrightness. Aucun nits dans la chaine. Le plafond
//     du tone map SUIT le ratio LU (pas le ratio demande) : tant que le systeme rend 1,0, la
//     sortie est identique au SDR.
//   * HDR10 PQ (API < 34) : le compositeur ne publie ni blanc SDR ni ratio. Mesure sur le Redmi
//     Note 9 Pro (Android 12) le 09/09 : notre surface PQ ne change ni la luminosite du systeme
//     (`debug.tracing.screen_brightness` 0,4969 avant/pendant) ni le mode couleur de l'ecran
//     (NATIVE, « HDR Panel:false ») — le PQ est DECODE puis recompose en SDR, et le blanc SDR y
//     est la luminance maximale annoncee (HdrCapabilities.maxLuminance). Donc paper white =
//     maxLuminance, marge = 1,0 : l'image est celle du SDR, dans un conteneur 10 bits BT.2020.
//     Aucune haute lumiere ne peut y gagner : c'est la physique de ces ecrans, pas un choix.
//
// CE QUI EST VRAI DANS LES DEUX ETATS :
//   * OFF (defaut hors auto-configuration) : rien de ce fichier ne touche l'image. Le tampon UI
//     reste RGBA8, le plafond du tone map reste 1,0, le quad final reste une recopie, la surface
//     reste celle d'avant l'item (8 bits, colorspace lineaire). Identique au bit a lighting-hdr.
//   * ON n'existe que si un mode est ANNONCE par le systeme ET par la couche de presentation
//     (`modes_available() != 0`), ET que l'eclairage Recharged est actif : la sortie HDR est une
//     sous-option de « Recharged Lighting » (refus owner 09/09 : l'interrupteur vivait hors des
//     reglages Recharged alors qu'il depend de la refonte de l'eclairage).
//   * L'interrupteur est celui du JOUEUR : la capacite de l'ecran ne force jamais ON
//     (`hdr_out_forced_on` compte les images ou la surface serait HDR sans que le reglage le
//     demande — il doit rester a zero).
//
// PREUVE (`lib/proof_run.sh hdr-display-output device`) : quand le harnais mesure cet item,
// `frame_end` deroule un auto-test en CINQ phases — etat charge, ON, OFF, ON a ecran presentant
// SIMULE, ON sur l'autre chemin annonce — en passant par le
// MEME chemin que le menu (`request`). La phase ON n'est lancee qu'une fois qu'une SCENE est
// dessinee (sonde de contenu : tons moyens dans l'image tone-mappee ; x86 essai 3 : les phases
// tournaient pendant l'intro noire, 10 s avant le titre), avec un plafond de 120 s publie.
// Il publie des grandeurs lues sur la SURFACE (colorspace
// rendu par eglQuerySurface, bits rouges rendus par glGetIntegerv), dans settings.ini relu du
// disque, et sur l'IMAGE DESSINEE : un blanc UI passe par le vrai quad final et relu
// (`hdr_out_ui_white_*`), et la scene reelle tone-mappee deux fois par le vrai programme
// `tonemap` (plafond 1,0 contre plafond HDR) pour la luminance des tons moyens
// (`hdr_out_darkening_pct`), puis une quatrieme phase ON avec un pic d'ecran SIMULE (1000 nits,
// par le meme chemin que `debug.opengoal.hdr.out.peak`) pour prouver que la courbe s'adapte au
// pic annonce (`hdr_out_peak_adaptive`, verdict 10 : blanc SDR ancre, plafond et hautes lumieres
// plus hauts en scRGB ; blanc de reference qui suit le pic en PQ recompose), puis une CINQUIEME
// phase qui rebascule sur l'AUTRE chemin annonce par les caps (PQ quand scRGB a ete retenu, et
// inversement) pour que la preuve porte CHAQUE chemin, jamais un seul. `hdr_out_defects` est la
// somme de QUATORZE verdicts publies un par un (`hdr_out_defect_1_*` a `hdr_out_defect_14_*`) ;
// le onzieme est l'EFFET MESURE, et il lit `hl_ext_levels` — la fenetre [15/16, kFixedTop], la ou
// une courbe a plafond > 1 ecrit ses codes neufs — et non `hl_levels`, borne a 1,0.

#include <cstdint>
#include <functional>

#include "game/graphics/pipelines/opengl.h"

class Shader;

namespace hdr_output {

constexpr const char* kItemId = "hdr-display-output";

// Modes de sortie, en masque. `modes_available()` n'en retient qu'UN (le meilleur que la
// plateforme sait tenir) : scRGB si l'API le contractualise, sinon HDR10 PQ.
enum Mode : uint32_t {
  kModeNone = 0,
  kModeHdr10Pq = 1,
  kModeScrgbLinear = 2,
  kModeHlg = 4,  // BT.2020 HLG (ARIB STD-B67), EGL_EXT_gl_colorspace_bt2020_hlg
};

// Verdict 13 (refus owner du 11/09 : « Si ca supporte HDR10+ (variable) faut exploiter, si ca
// supporte seulement HDR10 on utilise en repli, si ca supporte uniquement HLG on utilise en
// repli »). LE FORMAT, c'est-a-dire ce que l'ECRAN annonce savoir decoder, par ordre de
// preference decroissant. Distinct de `Mode`, qui est le TRANSPORT que la couche de
// presentation sait creer : HDR10+ et HDR10 partagent le meme transport PQ. Aucun appareil
// n'est nomme nulle part — le rang vient du masque annonce et de ce que la plateforme sait
// produire, rien d'autre.
enum Format : int {
  kFmtNone = 0,
  kFmtScrgb = 1,        // hors classement : seul transport a marge CONTRACTUELLE (API 34+)
  kFmtHdr10Plus = 2,    // PQ + metadonnees DYNAMIQUES
  kFmtHdr10 = 3,        // PQ + metadonnees statiques (SMPTE2086 + CTA861.3)
  kFmtHlg = 4,          // OETF HLG, aucune metadonnee
  kFmtDolbyVision = 5,  // hors perimetre : licence
  kFmtCount = 6,
};

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
// Le niveau d'API de la plateforme et si le systeme sait publier son ratio HDR/SDR
// (Android 14+ : Display.isHdrSdrRatioAvailable). Bureau : (0, false).
void set_platform_info(int sdk_int, bool hdr_sdr_ratio_available);
// Le ratio HDR/SDR courant LU dans le systeme (Display.getHdrSdrRatio, 1,0 = aucune marge).
// Pousse par Java a chaque changement ; fil quelconque.
void set_hdr_sdr_ratio(float ratio);

// Ce que la COUCHE DE PRESENTATION annonce (EGL sur Android, SDL sur bureau). Fil GL.
struct PlatformCaps {
  bool probed = false;
  bool egl_bt2020_pq = false;      // EGL_EXT_gl_colorspace_bt2020_pq
  bool egl_scrgb_linear = false;   // EGL_EXT_gl_colorspace_scrgb_linear
  bool egl_fp16 = false;           // EGL_EXT_pixel_format_float
  bool egl_no_config_ctx = false;  // EGL_KHR_no_config_context
  bool egl_smpte2086 = false;      // EGL_EXT_surface_SMPTE2086_metadata
  bool egl_bt2020_hlg = false;     // EGL_EXT_gl_colorspace_bt2020_hlg
  bool egl_cta861_3 = false;       // EGL_EXT_surface_CTA861_3_metadata (MaxCLL / MaxFALL)
  bool config_10bit = false;       // un EGLConfig RGB 10/10/10 + fenetre + ES3 existe
  bool config_fp16 = false;        // un EGLConfig RGBA 16F (composantes flottantes) + fenetre + ES3 existe
  bool sdl_display_hdr = false;    // bureau : SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN
  bool sdl_window_hdr = false;     // bureau : SDL_PROP_WINDOW_HDR_ENABLED_BOOLEAN
  int sdl_headroom_x100 = 0;       // bureau : SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT x100
};
void set_platform_caps(const PlatformCaps& caps);

// Masque du mode REELLEMENT retenu : systeme ET presentation d'accord. 0 = l'option
// n'existe pas pour ce joueur (rangee cachee).
uint32_t modes_available();
const char* mode_name(uint32_t mode);
// Verdict 13 : le FORMAT retenu, choisi seul parmi ceux que l'ecran annonce et que la
// plateforme sait produire. kFmtNone = aucun.
int format_chosen();
const char* format_name(int fmt);
// Le transport que ce format exige (kModeHdr10Pq pour HDR10 et HDR10+, kModeHlg pour HLG,
// kModeScrgbLinear pour scRGB). kModeNone si le format n'est pas productible ici.
uint32_t format_transport(int fmt);
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
// `mode` : kModeNone (SDR), kModeHdr10Pq (PQ + 10 bits), kModeHlg (HLG + 10 bits),
// kModeScrgbLinear (scRGB + 16 bits).
struct SurfaceState {
  bool hdr = false;
  int red_bits = 0;
  int colorspace = 0;
  uint32_t mode = kModeNone;
};
// Installe par le renderer qui SAIT recreer sa surface (Android). `want_mode` est kModeNone pour
// revenir au SDR, sinon le mode retenu. Rend vrai si la surface est maintenant dans l'etat
// demande, et remplit `out`. Sans switcher installe (bureau), aucun mode.
using Switcher = std::function<bool(uint32_t want_mode, SurfaceState* out)>;
void install_switcher(Switcher fn);
// L'etat initial de la surface, avant toute bascule.
void note_surface_state(const SurfaceState& st);
// Fil GL, avant de dessiner une image : applique une demande en attente (menu ou auto-test).
void apply_pending_on_gl_thread();
// Fil GL : une demande de marge a transmettre a SurfaceControl.setExtendedRangeBrightness
// (scRGB seulement). CONTRAT (AOSP SurfaceControl.java, OutputLayer.cpp, ViewRootImpl) :
//   * `current` = le ratio HDR/SDR auquel CE tampon est encode (1,0 = blanc SDR ; nos valeurs
//     montent jusqu'au ratio LU, jamais plus). SurfaceFlinger en deduit l'attenuation de la
//     couche : declarer 4,0 quand on n'a rendu que jusqu'a 2,0 (et que l'ecran n'accorde que
//     2,0) reporte le blanc SDR deux fois trop bas — TOUT plus sombre, le refus owner du 09/09.
//   * `desired` = la marge souhaitee (kDesiredHeadroom) : c'est elle qui promeut la couche en
//     HDR et borne ce que le DisplayManager accorde ; Display.getHdrSdrRatio() ne depasse 1,0
//     qu'APRES cette promotion (attendre le ratio avant de demander = interblocage).
// Sequence : a la bascule scRGB, (1,0 ; desired) ; a chaque changement du ratio LU, (ratio ;
// desired) ; au retour SDR, (1,0 ; 1,0). Rend vrai une fois par changement.
bool take_headroom_request(float* current, float* desired);
// Fil GL : les DEUX AUTRES leviers du systeme, a poser quand la surface devient (in)active.
// Essai 6 (Honor, 10/09) : `setExtendedRangeBrightness` seul laisse `Display.getHdrSdrRatio()`
// a 1,0 — le systeme n'accorde aucune marge et l'owner ne voit aucune difference on/off. Ces
// deux-la n'avaient jamais ete tentes : `Window.setColorMode(COLOR_MODE_HDR)` (API 26+, dit au
// WindowManager que la fenetre veut le mode HDR de l'ecran) et `Window.setDesiredHdrHeadroom`
// (API 35+, la demande de marge moderne, cote fenetre et non cote SurfaceControl). Rend vrai
// une fois par changement d'etat.
// `brightness_target` : la consigne de retro-eclairage ABSOLUE demandee a NOTRE fenetre
// (WindowManager.LayoutParams.screenBrightness, API 1+), ou < 0 pour la rendre au systeme.
// C'est le QUATRIEME levier, et le seul qui existe sous l'API 34 : les trois autres sont des
// no-op la. La marge n'est pas ce qu'on demande ici, c'est ce que le systeme pose ensuite et
// que `debug.tracing.screen_brightness` publie — relu par le natif, jamais suppose.
bool take_window_lever_request(bool* on, float* desired, float* brightness_target);

// ---------------------------------------------------------------- ce que le rendu lit ----

// LES PARAMETRES EFFECTIFS DE LA COURBE pour l'image en cours. Trois d'entre eux sont pilotes
// par le CONTENU de la scene (analyse par `analyze_scene`, lissee dans le temps) : c'est
// l'adaptation « facon Dolby Vision » que le refus owner du 10/09 reclame (« c'est statique non ?
// le HDR s'ajuste pas constamment »). En sortie SDR, ou pendant l'auto-test, ils prennent un
// point de fonctionnement FIGE : les verdicts de phase comparent des etats, ils ne peuvent pas
// le faire si la courbe bouge sous eux.
struct CurveParams {
  float ceiling = 1.f;  // u_hdr_ceiling — plafond, dans l'espace d'affichage du tampon
  float anchor = 2.f;   // u_hdr_anchor  — >= 1 : aucune expansion, chemin SDR strict
  float top = 2.f;      // u_hdr_top     — la valeur de scene qui sort AU plafond ; <= ceiling
  float toe = 0.f;      // u_hdr_toe     — relevement du pied
};
CurveParams curve_params();
// Fil GL : pousse les quatre uniformes de la courbe sur le programme `tonemap`.
void push_tonemap_uniforms(Shader& shader);
// Fil GL, dans hdr::tonemap_draw APRES le vrai dessin (programme, texture de scene et VAO encore
// lies) : rejoue `tonemap` dans une cible 16x16 avec un plafond assez haut pour ne rien
// comprimer — donc une image de la SCENE, pas de sa version tone-mappee — et lit le resultat
// par un anneau de PBO (lecture ASYNCHRONE : le tampon consomme a ete rempli huit images plus
// tot, la carte ne bloque pas). En sort la luminance log-moyenne et le haut de scene, lisses
// dans le temps. Tourne en PRODUCTION des que la sortie HDR est active, une image sur huit.
void analyze_scene(Shader& shader, GLuint dst_fbo, int dst_w, int dst_h);

GLenum ui_buffer_format();      // GL_RGBA16F quand active(), sinon GL_RGBA8
GLenum window_target_format();  // GL_RGB10_A2 (PQ) / GL_RGBA16F (scRGB) quand active(), sinon GL_RGBA8
// Le blanc SDR de l'ecran tel que le SYSTEME le donne, en nits : PQ = HdrCapabilities.maxLuminance
// (le compositeur des API < 34 recompose le PQ en SDR a cette echelle) ; scRGB = 0 (le contrat
// est relatif : 1,0, pas un nits). Voir `sdr_white_source()`.
float sdr_white_nits();
const char* sdr_white_source();
// Blanc de reference pousse au quad final : nits en PQ (= sdr_white_nits), 1,0 en scRGB.
float paper_white();
// La marge LINEAIRE accordee au-dessus du blanc SDR : 1,0 hors HDR et en PQ ; le ratio HDR/SDR
// lu dans le systeme en scRGB.
float headroom_linear();
// Le plafond du tone map, dans l'ESPACE D'AFFICHAGE du tampon (gamma ~2,2) : headroom^(1/2,2),
// 1,0 hors HDR. C'est ce que `u_hdr_ceiling` recoit.
float tonemap_ceiling();
// Le quad final : `u_out_mode` (0 recopie, 1 PQ, 2 scRGB lineaire, 3 HLG), `u_out_paper_white`,
// `u_out_max_nits` (POUSSE mais lu par aucune ligne du shader — voir FINDINGS).
void push_present_uniforms(Shader& shader);

// -------------------------------------------------------------------- sondes de preuve ----
// Les deux sondes ne tournent QUE sous mesure de cet item (harnais arme, phase ON de
// l'auto-test), une image sur cinq, hors ecran, et ne changent rien a l'image presentee.
//
// Sonde de BLANC UI : appelee juste apres le dessin du quad final (programme et VAO encore
// lies) ; rejoue ce meme programme, memes uniformes, sur un texel blanc (1,1,1,1) dans un FBO
// 4x4 flottant et relit le resultat. PQ : decode -> nits (`hdr_out_ui_white_nits`) ; scRGB :
// valeur lineaire x1000 (`hdr_out_ui_white_rel_x1000`). Remet framebuffer 0 et le viewport.
void probe_present(Shader& shader);
// La MEME sonde porte aussi les RAMPES du verdict 11 (refus owner du 10/09 : « on/off j'ai
// aucun changement a l'ecran »). Deux rampes de 128 marches, l'une dans les ombres
// ([0 ; 1/16] de l'espace d'affichage du jeu), l'autre dans les hautes lumieres ([15/16 ; 1]),
// passees par le VRAI quad final vers un FBO au FORMAT REEL DE LA FENETRE (RGBA8 en SDR,
// RGB10_A2 en PQ, RGBA16F en scRGB) : on compte les NIVEAUX DISTINCTS que la sortie sait
// encore separer. C'est la seule facon de mesurer « plus de detail aux deux bouts » sans
// regarder une image. Elles tournent AUSSI en phase OFF, sinon il n'y a rien a comparer.
// Sonde d'ASSOMBRISSEMENT : appelee dans hdr::tonemap_draw apres le vrai dessin (programme,
// texture source et VAO encore lies) ; rejoue `tonemap` deux fois dans deux FBO 32x32 flottants
// (u_hdr_ceiling = 1,0 puis le plafond HDR courant) sur la MEME scene et cumule la luminance
// lineaire des tons moyens. Restaure `dst_fbo` + viewport (dst_w, dst_h) et le plafond courant.
void probe_tonemap(Shader& shader, GLuint dst_fbo, int dst_w, int dst_h);

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
// OU vit la rangee, rapporte par GOAL en scrutant ses tableaux : 1 = dans RECHARGED SETTINGS,
// immediatement apres le bloc RECHARGED LIGHTING (la place exigee), 0 = ailleurs.
void note_menu_parent(int parent);

// Relecture de settings.ini sur le disque : 1/0 = valeur de `hdr-output?`, -1 = cle absente,
// -2 = fichier absent ou illisible.
int read_persisted_setting();

}  // namespace hdr_output
