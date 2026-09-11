#pragma once

// hdr_desktop — LA SORTIE HDR SUR BUREAU, Windows comme Linux (item `hdr-desktop-output`).
//
// CE QUE CE FICHIER EST. Le pendant exact de la section HDR de `android/android_renderer.cpp` :
// le FOURNISSEUR DE SURFACE. `hdr_output.cpp` — les capacites, le choix du format, la courbe,
// le blanc de reference, l'encodage du quad final — est deja compile dans le binaire de bureau
// et n'a jamais rien eu d'Android. Ce qui manquait au bureau, ce sont les quatre gestes que
// seule la plateforme peut faire :
//   * LIRE ce que l'ecran annonce (SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN et la marge que le
//     compositeur publie pour NOTRE fenetre) et ce que la couche de presentation sait produire
//     (les extensions EGL de colorspace, quand un EGL existe) ;
//   * DEMANDER la surface dans l'espace retenu, et RELIRE ce qu'on a obtenu ;
//   * POSER les metadonnees statiques HDR10 (SMPTE2086 + CTA861.3) ;
//   * appeler `hdr_output::apply_pending_on_gl_thread()` une fois par image.
//
// CE QU'IL N'EST PAS. Il ne recopie aucune ligne de courbe. Tout ce qui decide de l'image passe
// par `hdr_output::present_params_for()` — LA meme fonction que l'appareil appelle — et la
// preuve NOMME le symbole par `dladdr` plutot que de l'affirmer.
//
// LES DEUX TRANSPORTS, ET POURQUOI ILS DIFFERENT PAR PLATEFORME.
//   * Linux : la couche de presentation est EGL des que SDL y passe (Wayland toujours, X11 sur
//     `SDL_VIDEO_FORCE_EGL`). On demande alors `EGL_GL_COLORSPACE_BT2020_PQ_EXT` (HDR10) ou
//     `EGL_GL_COLORSPACE_SCRGB_LINEAR_EXT`, par le MEME callback SDL que l'appareil
//     (`SDL_EGL_SetAttributeCallbacks`). Quand le pilote n'annonce pas l'extension, il n'y a
//     aucun chemin : c'est publie avec sa raison, jamais contourne.
//   * Windows : il n'existe AUCUNE extension WGL de colorspace — ce n'est pas un oubli de SDL,
//     c'est qu'elle n'existe pas. Le seul transport HDR atteignable en OpenGL y est un tampon de
//     fenetre a composantes flottantes (`SDL_GL_FLOATBUFFERS`), que le compositeur interprete en
//     scRGB lineaire des que l'ecran est en mode HDR — et c'est ce meme compositeur qui publie
//     la marge dans `SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT`. C'est exactement le contrat scRGB que
//     `hdr_output` tient deja pour Android 14+ : 1,0 = blanc SDR, au-dessus = la marge accordee.
//
// LA CONTRAINTE DURE DU BUREAU : ON NE RECREE PAS LA SURFACE A CHAUD. Ni SDL3 ni GLX ni WGL
// n'offrent de quoi rechanger le colorspace ou la profondeur d'un framebuffer de fenetre deja
// cree ; le seul point d'injection est AVANT `SDL_CreateWindow`. Le reglage du joueur est donc
// lu sur le disque au demarrage, et un changement dans le menu prend effet au lancement suivant.
// Le basculeur installe ici rend VRAI pour le mode avec lequel la fenetre a ete creee, et FAUX
// avec une raison nommee pour tout autre : on ne pretend jamais avoir bascule.
//
// OFF EST L'ABSENCE, PAS UN DRAPEAU A ZERO. Quand le reglage est eteint et que le harnais ne
// mesure pas cet item, `before_window()` ne pose AUCUN hint, ne sonde AUCUN EGL, ne touche AUCUN
// attribut GL : la fenetre est creee par exactement le meme chemin qu'avant cet item.
//
// PREUVE (`lib/proof_run.sh hdr-desktop-output x86`). Sans ecran HDR sur le banc, rien de ce qui
// se passe DANS LA DALLE n'est mesurable — et on ne conclut rien dessus. Ce qui est mesure est
// produit par le code : ce que les deux couches annoncent, le format retenu et la raison NOMMEE
// de chaque rejet, la reponse du PILOTE a une demande de colorspace reellement emise, les
// metadonnees calculees, l'encodage du quad final relu dans le format REEL de la cible, et la
// courbe exercee a DEUX pics d'ecran simules. `hdr_desktop_defects` est la somme de HUIT
// verdicts publies un par un.

#include <cstdint>

struct SDL_Window;
class Shader;

namespace hdr_desktop {

constexpr const char* kItemId = "hdr-desktop-output";

// Avant `SDL_Init(SDL_INIT_VIDEO)` (fil principal). Lit le reglage persiste, sonde la couche EGL
// (chargee a la demande, jamais liee), et pose le seul hint qui doive etre en place AVANT que SDL
// choisisse son pilote GL : sous X11, SDL prend GLX par defaut et GLX n'a AUCUNE extension de
// colorspace — `SDL_HINT_VIDEO_FORCE_EGL` est le seul moyen d'y avoir un chemin HDR. Il n'est pose
// que si la sortie HDR est demandee ET que le pilote EGL annonce vraiment un espace HDR : sur une
// machine sans, rien ne change, et le repli GLX est celui d'avant cet item.
void before_sdl_init();

// Avant `SDL_CreateWindow` (fil principal). Lit ce que SDL annonce de l'ecran, retient un
// transport, et pose les attributs de framebuffer qu'il exige — le seul levier du bureau, ou le
// colorspace se choisit A LA CREATION. Ne fait STRICTEMENT rien si la sortie HDR n'est ni demandee
// par le reglage persiste ni par le knob, et que le harnais ne mesure pas cet item.
void before_window();

// Apres `SDL_GL_MakeCurrent` et le chargement de glad (fil GL). Relit ce qui a ete REELLEMENT
// obtenu, publie l'ecart avec ce qui a ete demande, pose les metadonnees HDR10 et installe le
// basculeur dans `hdr_output`.
void after_window(SDL_Window* window);

// Debut d'image, fil GL. Applique une demande en attente (menu), suit la marge publiee par le
// compositeur, et compte la prise de la feature.
void frame_begin();

// Apres le dessin du quad final (programme, VAO et VBO encore lies), fil GL. Ne tourne que sous
// mesure de cet item : la repetition d'encodage et les verdicts. Restaure framebuffer 0, le
// viewport et la texture liee.
void probe_present(Shader& shader);

}  // namespace hdr_desktop
