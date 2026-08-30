#pragma once

// Ggrass-density-presets (owner 2026-08-30) — CINQ PALIERS NOMMES, PLUS DE CURSEUR CONTINU.
//
// Mot pour mot : « on s'en fiche de changer la densite au poil de cul, on veut juste plus ou moins
// dense donc very low density, low density, medium density, high density et very high density c'est
// assez, pas besoin de plus, donc on peut pre-calculer le tout et eviter le chemin lourd ».
//
// POURQUOI CE FICHIER EXISTE, ET POURQUOI IL EST SEUL. La densite etait un flottant continu, ecrit
// par un curseur, compare a la densite du bake par `density > bake_density_pct` — la condition qui
// basculait le placement sur le chemin EN DIRECT. Avec cinq paliers, chacun ayant SON bake, la
// densite demandee est TOUJOURS exactement celle du bake charge : la comparaison n'a plus de valeur
// intermediaire a rencontrer, et elle disparait du code au lieu d'etre simplement inatteignable.
//
// Ce fichier est la SEULE table. Le moteur, l'outil de cuisson hors-ligne et l'empaqueteur la lisent
// tous ici : un palier ajoute ou deplace ne peut pas diverger entre le bake et ce qui le charge.
// Aucune inclusion GL / loader (`GrassBakeCore.h` est aussi compile dans un outil de bureau).

namespace grass_bake {

struct DensityPreset {
  const char* slug;   // nom de fichier livre : <niveau>.<slug>.grassbake
  const char* label;  // libelle affiche dans le menu
  float pct;          // densite passee a scan_level() a la cuisson ET a expand() au chargement
};

// L'echelle couvre exactement la plage que le curseur autorisait (`dens_scale` etait borne a
// [0,5 ; 2,5], soit 50 % a 250 %), donc aucun palier ne demande plus que ce que le moteur savait
// deja produire, et MEDIUM = 150 % est la valeur livree jusqu'ici : le defaut ne bouge pas.
inline constexpr DensityPreset kDensityPresets[] = {
    {"very-low", "VERY LOW", 50.f},
    {"low", "LOW", 100.f},
    {"medium", "MEDIUM", 150.f},
    {"high", "HIGH", 200.f},
    {"very-high", "VERY HIGH", 250.f},
};
inline constexpr int kDensityPresetCount = 5;
inline constexpr int kDensityPresetDefault = 2;  // MEDIUM

inline constexpr int clamp_density_preset(int i) {
  return i < 0 ? 0 : (i >= kDensityPresetCount ? kDensityPresetCount - 1 : i);
}
inline constexpr float density_preset_pct(int i) {
  return kDensityPresets[clamp_density_preset(i)].pct;
}
inline constexpr const char* density_preset_slug(int i) {
  return kDensityPresets[clamp_density_preset(i)].slug;
}
inline constexpr const char* density_preset_label(int i) {
  return kDensityPresets[clamp_density_preset(i)].label;
}

// Un reglage ECRIT PAR UNE VERSION ANTERIEURE porte un pourcentage libre (« 137,0 »). On le ramene
// au palier le plus proche PAR DEFAUT (jamais au-dessus : un palier plus haut demanderait un bake
// qu'on ne livre pas, et c'est exactement la bascule qu'on supprime).
inline constexpr int density_preset_from_pct(float pct) {
  int best = 0;
  for (int i = 0; i < kDensityPresetCount; ++i) {
    if (kDensityPresets[i].pct <= pct + 0.01f) {
      best = i;
    }
  }
  return best;
}

}  // namespace grass_bake
