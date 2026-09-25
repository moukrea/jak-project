#pragma once
// flip_census — tournee des niveaux de Jak 1, recensement des pixels dont la normale source
// est a l'envers et qui tombent au noir sous l'eclairage recharge. Voir le contrat de
// l'item `lighting-flipped-faces-everywhere`. Modele repris de floor_probe.{h,cpp} sans le
// factoriser (floor_probe appartient a un autre item valide).
#include <cstddef>
#include <cstdint>
#include <string>

namespace flip_census {

enum Family {
  TFRAG = 0,
  TIE = 1,
  TIE_WIND = 2,
  SHRUB = 3,
  GRASS = 4,
  OCEAN = 5,
  MERC = 6,
  kFamilies = 7
};

// Vrai si la tournee de recensement doit tourner (bureau uniquement, OG_FLIP_TOUR=1 et item
// arme). Lu une fois, mis en cache.
bool active();

// Une fois par image, fil GL, AVANT tout tirage de l'image.
void frame_tick(uint64_t frame_idx);

// Juste avant / apres chaque tirage couleur des familles suivies.
void before_draw(Family f,
                  unsigned program,
                  uint64_t frame_idx,
                  const std::string& level_name,
                  const char* label = nullptr);
void after_draw();

// Fil GOAL : rend vrai une fois par demande de teleport posee par la tournee.
bool take_warp_request(char* name, size_t cap);

// Vrai pendant la fenetre de mesure : le fil GOAL pousse le stick droit a fond pour balayer
// 360 degres. Toujours faux sur Android.
bool spin_active();

}  // namespace flip_census
