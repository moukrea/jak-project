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

}  // namespace hud_box_probe
