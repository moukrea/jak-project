// water-ocean-mesh — LA TRANSFORMATION D'ECRAN DE L'OCEAN DE NAUGHTY DOG, EN UN SEUL EXEMPLAIRE.
//
// Le chemin d'ocean de ND n'a aucune matrice camera : ses sommets arrivent deja en coordonnees
// ecran PS2, produits par l'emulation VU sur le CPU. Ces trois lignes sont tout ce qui les amene
// en clip space. Le recensement d'emprise rasterise EXACTEMENT la meme geometrie pour en faire
// l'oracle de la clipmap : s'il en gardait sa propre copie, les deux transcriptions deriveraient
// et l'oracle mesurerait sa propre derive au lieu de l'ocean d'origine.

vec4 ocean_common_clip(vec3 position_in) {
  vec4 p = vec4((position_in.x - 0.5) * 16., -(position_in.y - 0.5) * 32.0,
                position_in.z * 2.0 - 1., 1.0);
  // scissoring area adjust
  p.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  return p;
}
