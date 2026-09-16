#pragma once

#include <cstdint>

namespace Mips2C::vu_simd {
// LES TROIS EMPLACEMENTS SONT DES NOYAUX REELLEMENT EXECUTES DANS LE REGIME LIVRE.
// `Bones` a ete retire le 16/09 : `bones.gc` arme `*use-new-bones*` et appelle
// `new-bones-mtx-calc-asm`, donc `bones-mtx-calc` comparait ZERO operation et la fenetre de
// parite (qui exige les TROIS noyaux dans la MEME image) ne pouvait jamais se remplir.
// `Collide` le remplace : `(method 32 collide-cache)` et `(method 29 collide-cache)`, 32,6 et
// 28,2 appels par image sur l'appareil de preuve.
enum class Kernel { Collide, Joints, Particles };
struct Settings {
  bool vector_enabled;
  bool verify;
};
Settings settings(Kernel kernel);
void record(Kernel kernel, uint64_t compared, uint64_t defects);
// Called on the GOAL thread, once per simulated frame.
void frame_boundary();
// LA FENETRE DE COUT. Apres les 600 images de parite, l'oracle s'eteint et le regime
// alterne par blocs : `cost_slot()` rend 0 pendant un bloc SCALAIRE, 1 pendant un bloc
// VECTORIEL, -1 quand l'image ne doit etre comptee par personne (phase de parite, image de
// transition, ou course qui ne mesure pas). Le recensement mips2c s'en sert pour attribuer
// le temps des noyaux raccordes au regime qui l'a produit.
int cost_slot();
// Le nombre d'images deja comptees dans un bras (0 = scalaire, 1 = vectoriel).
uint64_t cost_frames_in(int slot);
}  // namespace Mips2C::vu_simd
