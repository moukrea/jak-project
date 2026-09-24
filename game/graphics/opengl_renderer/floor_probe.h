#pragma once
#include <cstdint>
#include <string>
namespace floor_probe {
// Appele juste AVANT chaque tirage de couleur tfrag3 (tous les glDraw* de TFragment.cpp).
// program : le programme shader tfrag3 actif. frame_idx : compteur d'images du render_state.
// level_name : niveau du dessin en cours.
void before_tfrag_draw(unsigned program, uint64_t frame_idx, const std::string& level_name);
// Appele juste APRES le meme tirage.
void after_tfrag_draw();
}  // namespace floor_probe
