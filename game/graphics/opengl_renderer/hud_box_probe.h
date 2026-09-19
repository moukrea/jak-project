#pragma once

// hud-3d-pickups — LA BOITE ENGLOBANTE D'UN ELEMENT DU HUD, LUE SUR L'IMAGE RENDUE.
//
// POURQUOI CE MODULE EXISTE. L'essai 2 de l'item a publie `hud3d_rect_cell_cx/cy/ext` et rendu
// un ecart de 0 alors que l'owner voyait la pile d'energie « minuscule et squeezee au centre de
// l'ecran ». La raison est dans le code de l'essai 2 : `hud3d-set-regime` POSE
// `icons 1 icon-x = icons 0 icon-x + cell-dx` a chaque image, et la porte comparait ensuite ces
// deux memes entiers ; l'etendue comparait `sc * r1` a `scale0 * r0` avec `sc = scale0 * r0/r1`,
// egalite VRAIE PAR ALGEBRE. La grandeur etait calculee depuis les variables du placement : un
// miroir, pas une mesure (feedback_gate_quantity_computed_from_own_state_is_unfalsifiable).
//
// CE QUE CELUI-CI MESURE, ET EN QUOI IL N'EST PAS UN MIROIR. Il ne lit AUCUNE variable de
// placement. Il lit deux fois la meme FBO de rendu — une image ou l'element est cache, une image
// ou il est dessine — et retient les PIXELS QUI ONT CHANGE. Rien dans la chaine (draw-icons, les
// matrices d'os, la matrice de perspective, le viewport, le renderer merc ou generic) n'est
// suppose : ce qui est mesure est ce que la dalle affiche.
//
// LE BRUIT DE LA SCENE EST LE PIEGE, ET IL EST TRAITE. Une difference entre deux images d'un jeu
// qui tourne change des milliers de pixels partout (Jak respire, l'eau bouge) : une boite
// englobante prise sur UNE paire couvrirait l'ecran. On accumule donc un COMPTEUR PAR PIXEL sur
// K paires : le bruit de scene tombe a des endroits differents a chaque paire, l'element tombe
// toujours au meme. Seuls les pixels qui ont change dans au moins `kAgreeNum/kAgreeDen` des
// paires sont retenus. Le slot de CONTROLE (deux images du meme etat) mesure ce qui survit a ce
// filtre quand il n'y a RIEN a voir : c'est le plancher de l'instrument, publie a cote des
// boites, et une boite de controle non vide invalide la mesure au lieu de la decorer.
//
// LE JOUEUR NE PAIE RIEN. Tout ce fichier est inerte hors `debug.opengoal.costprobe` /
// `AUTOPORT_COST_PROBE` = `hud-3d-pickups` : `armed()` est faux, `request()` et `end_of_frame()`
// rendent la main immediatement, et aucun tampon n'est alloue.

#include <cstdint>

namespace hud_box_probe {

// Les emplacements mesures. 0 est reserve a la capture de REFERENCE (l'element cache).
enum Slot {
  kBase = 0,
  kCellStock = 1,  // l'icone d'origine de la pile : *fuelcell-naked-sg*, icons 0
  kCellOurs = 2,   // la notre : *fuel-cell-sg*, icons 1
  kBuzzer = 3,     // la mecamouche : *buzzer-sg*
  kOrb = 4,        // l'orbe : *money-sg*
  kControl = 5,    // rien n'a change : le plancher de l'instrument
  kSlotCount = 6
};

// Les champs lus par GOAL. Aucun n'est negatif : `pc_autoport_publish` ecrase tout entier
// negatif a zero (FINDINGS de l'essai 2), donc l'ecart se calcule en GOAL a partir des bornes.
enum Field {
  kSamples = 0,   // paires retenues pour ce slot
  kMinX = 1,
  kMinY = 2,
  kMaxX = 3,
  kMaxY = 4,
  kPixels = 5,    // pixels retenus par le filtre d'accord
  kRegionW = 6,
  kRegionH = 7,
  kEmpty = 8,     // paires ou RIEN n'avait change (element absent de l'image)
  // DIAGNOSTIC. Sans eux, un slot a 23 pixels retenus ne dit pas s'il a vu 23 pixels changer 48
  // fois au meme endroit ou 40 000 pixels changer ailleurs a chaque fois : meme chiffre, causes
  // opposees. `kBaseLum` dit si l'image de reference est une VRAIE image (une relecture qui rend
  // du noir laisserait tout l'instrument muet sans le signaler).
  kRawMean = 9,   // pixels changes par paire, AVANT le filtre d'accord, en moyenne
  kRawMax = 10,   // le maximum sur les paires
  kExcluded = 11, // pixels retires parce que le CONTROLE les voit bouger tout seuls
  kBaseLum = 12,  // luminance moyenne de la derniere image de reference (0..255)
  // L'HISTOGRAMME D'ACCORD, PAR PALIER. Un seuil unique ne peut pas separer un element d'un decor
  // sans qu'on ait vu les deux distributions : a 75 % le decor passait (57 pixels de CONTROLE),
  // a 95 % l'element ne passait plus (1 pixel). On publie donc le maximum d'accord et le nombre
  // de pixels a chaque palier, pour l'element ET pour le controle — le seuil se lit sur les
  // chiffres au lieu d'etre devine une troisieme fois.
  kAgreeMax = 13,  // le plus grand nombre de paires d'accord atteint par un pixel
  kP50 = 14,       // pixels d'accord >= 50 % des paires
  kP75 = 15,
  kP90 = 16,
  kP100 = 17,      // pixels d'accord sur TOUTES les paires
  kFieldCount = 18
};

// Vrai seulement sous la sonde de l'item. Lu une fois, mis en cache.
bool armed();

// GOAL demande que CETTE image soit capturee. `slot` = kBase pour la reference, sinon
// l'emplacement dont c'est l'image « dessine ». Sans appel, l'image n'est pas lue.
void request(int slot);

// Appele une fois par image par OpenGLRenderer, APRES le composite.
//
// DEUX SOURCES, ET LA PREMIERE EST LA BONNE. `fbo_id`/`fbo_w`/`fbo_h` designent la cible de rendu
// interne ; `win_*` designent la region de la fenetre ou l'image finale a ete composee. Mesure
// x86 du 17/09 : la cible interne fait 480x216 quand la fenetre en fait 1200x540 — c'est la cible
// a resolution dynamique, ou le MONDE est dessine et ou le HUD n'est PAS composite. Montrer ou
// cacher une icone n'y changeait donc rien, et les quatre boites tombaient sur le meme paquet de
// bruit. La sonde lit la FENETRE en premier — l'image que la dalle recoit, qui est aussi ce que le
// contrat demande — et ne retombe sur la cible interne que si cette lecture echoue, en publiant
// laquelle elle a servie.
void end_of_frame(unsigned fbo_id,
                  int fbo_w,
                  int fbo_h,
                  int win_x,
                  int win_y,
                  int win_w,
                  int win_h);

// Ce que GOAL relit pour fabriquer ses termes de porte. -1 si le champ n'existe pas.
int64_t read(int slot, int field);

// ── ESSAI 7 — LA BOITE DES SOMMETS TRANSFORMES, LUE AU DESSIN DE HUD ────────────────────────
//
// Owner, 18/09 07:15 : « la pile d'energie est un peu etiree en largeur par rapport a celles qu'on
// voit in game… peut-etre une histoire d'aspect ratio ». Arbitrage du meme jour : instrument
// AUTORISE — la boite des sommets transformes au moment du dessin de HUD, pas de lecture d'image,
// pas de seuil statistique, une image suffit ; la grandeur est le rapport largeur/hauteur de cette
// boite, compare au meme rapport pour le ramassable du monde.
//
// CE QUE C'EST. Generic2 recoit les sommets d'un modele de HUD deja passes par les os (unites du
// canevas 512x448, `draw-bones-hud` -> `mercneric-convert`) et les projette dans son nuanceur
// (shaders/generic.vert, branche sans matrice complete). On refait ICI, sur le CPU, exactement ce
// calcul pour chaque sommet de chaque appel de dessin HUD de l'image armee, et on retient DEUX
// boites : AVANT projection (unites du canevas) et APRES (pixels du viewport lu par
// `glGetIntegerv(GL_VIEWPORT)` au moment du dessin, jamais suppose). Le rapport largeur/hauteur de
// la seconde est ce que la dalle montre ; celui de la premiere, ramene a l'echelle du `root`
// (GOAL la releve a l'armement), est celui du MODELE — donc celui du ramassable du monde, dont la
// projection est isotrope (GOAL le mesure a cote : `hud3d_box_world_aniso_milli`).
// Aucun pixel n'est lu : le bruit de l'appareil (2,8 a 3,4 niveaux par pixel entre deux images
// identiques, essai 4) n'existe pas ici, et une image suffit.
//
// QUI DESSINE QUOI. GOAL n'allume qu'UN modele a la fois pendant la sequence (`hud3d-px-drive`) et
// arme le slot correspondant : tout ce que Generic2 dessine en HUD dans l'image qui suit lui
// appartient. `kVbVerts`/`kVbDraws` sont publies pour qu'un intrus se voie — deux slots aux memes
// chiffres, c'est le meme modele.
//
// LE RETARD ENTRE LE FIL GOAL ET LE RENDU. La demande faite a l'image F est vue par le fil de
// rendu quand il dessine une image de [F-3, F] : la phase tient au moins quatre images dans le
// meme etat, donc l'image retenue porte bien l'etat demande. Une image sans dessin HUD ne consomme
// pas la demande ; au-dela de trois fins d'image sans rien, la demande est declaree VIDE et
// comptee (`kVbEmpty`) au lieu d'attendre un dessin qui appartiendrait a la phase suivante.
//
// INERTE HORS SONDE. `vbox_pending()` est un entier atomique a -1 tant que GOAL n'a rien arme, et
// GOAL n'arme que sous `debug.opengoal.costprobe=hud-3d-pickups` : le joueur ne paie qu'une lecture
// atomique par appel de dessin HUD.

enum VboxField {
  kVbSamples = 0,    // images retenues pour ce slot (la derniere ecrase les valeurs)
  kVbVerts = 1,      // sommets vus dans l'image retenue
  kVbDraws = 2,      // appels de dessin HUD dans l'image retenue
  kVbPreW_e3 = 3,    // etendue x AVANT projection, unites du canevas, x1000
  kVbPreH_e3 = 4,    // etendue y AVANT projection, x1000
  kVbPxW_e3 = 5,     // etendue x APRES projection, en pixels du viewport, x1000
  kVbPxH_e3 = 6,     // etendue y, pixels, x1000
  kVbPxCx_e3 = 7,    // centre x en pixels depuis le bord gauche du viewport, x1000
  kVbPxCy_e3 = 8,    // centre y en pixels depuis le bord HAUT du viewport, x1000
  kVbVpW = 9,        // viewport lu au dessin
  kVbVpH = 10,
  kVbPath = 11,      // 0 = dessin direct dans la passe scene, 1 = passe UI native (differe)
  kVbScaleX_e6 = 12, // |x| et |y| de la matrice isometrique telles que Generic2 les recoit, x1e6
  kVbScaleY_e6 = 13,
  kVbEmpty = 14,     // demandes echues sans aucun dessin HUD
  kVbRequests = 15,  // demandes recues pour ce slot
  kVbFieldCount = 16
};
// Dix slots : 1..4 = pile d'origine, notre pile, mecamouche, orbe sous l'aspect du JOUEUR ;
// 6..9 = les memes sous l'aspect NATIF du panneau (GOAL bascule et restaure). 0 et 5 inutilises.
constexpr int kVboxSlots = 10;

// GOAL demande que la PROCHAINE image portant un dessin HUD soit mesuree dans `slot`.
void vbox_request(int slot);
// Vrai tant qu'une demande attend son image. Une lecture atomique, rien d'autre.
bool vbox_pending();
// Appele par Generic2 pour UN appel de dessin HUD : les deux boites de cet appel, le nombre de
// sommets vus, le viewport courant, le chemin (direct/differe) et l'echelle isometrique.
void vbox_note_draw(const float pre_min[2],
                    const float pre_max[2],
                    const float ndc_min[2],
                    const float ndc_max[2],
                    int verts,
                    int vp_w,
                    int vp_h,
                    bool deferred,
                    float iso_sx,
                    float iso_sy);
// Ce que GOAL relit. -1 si le slot ou le champ n'existe pas.
int64_t vbox_read(int slot, int field);

}  // namespace hud_box_probe
