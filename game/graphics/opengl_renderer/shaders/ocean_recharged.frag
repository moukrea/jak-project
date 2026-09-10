#version 410 core

// water-ocean-mesh (SPEC-refonte-eau §5.3) — OMBRAGE PROVISOIRE DE LA CLIPMAP.
//
// « Shading provisoire = l'actuel » : ce fragment ne cree AUCUN modele de lumiere. Il echantillonne
// la texture d'ocean que Naughty Dog produit deja chaque image (`draw-ocean-texture`, 128 x 128,
// la surface animee) et la fond vers `far-color` de la carte avec la distance. Le vrai materiau —
// normales a deux cartes, Fresnel plafonne, absorption, `shade()` + SURF_WATER — est l'item 2
// `water-surface-material`, et rien ici ne doit lui ressembler.
//
// LA DECOUPE ND. `ocean-mid-add-upload` (ocean-mid.gc:452) uploade, par tuile de 768 m, un masque
// de 8 x 8 bits dont le commentaire de Naughty Dog dit : « using 0 will draw, using 1 will skip ».
// Les 36 tuiles forment donc une grille de 48 x 48 sous-cellules de 96 m, et c'est cette grille
// qu'on reconstruit en texture. HORS de la carte, `ocean-mid-mask-ptrs-bit?` rend #t (skip) : on
// fait pareil, sinon l'eau deborderait la ou l'original n'en met pas.

in vec2  vs_world_xz;
in float vs_dist;
in vec2  vs_uv;

uniform sampler2D tex_ocean;  // la texture d'ocean ND de cette image (RGBA8 128x128)
uniform sampler2D tex_mask;   // R8 48x48 : 0 = dessiner, 255 = sauter
uniform vec4 u_far_color;     // (-> *ocean-map* far-color), composantes 0..255
uniform vec4 u_ocean_origin;  // redeclare par ocean_layer_a.glsl cote vertex ; ici c'est le notre

out vec4 color;

void main() {
  // sous-cellule de 96 m : 393216 unites GOAL
  vec2 cell = (vs_world_xz - u_ocean_origin.xz) * (1.0 / 393216.0);
  ivec2 mi = ivec2(floor(cell));
  if (mi.x < 0 || mi.x >= 48 || mi.y < 0 || mi.y >= 48) {
    discard;  // hors carte : Naughty Dog n'y dessine pas d'ocean non plus
  }
  if (texelFetch(tex_mask, mi, 0).r > 0.5) {
    discard;  // bit a 1 = sous-cellule sautee par l'original (terre)
  }

  vec3 far_rgb = u_far_color.rgb * (1.0 / 255.0);
  vec3 near_rgb = texture(tex_ocean, vs_uv).rgb;
  // 40 m : au-dela, la texture d'ocean ND s'aliase de toute facon (ses mips passent en alpha 0
  // des le mip 2, OceanTexture.cpp:427-431). On fond vers far-color plutot que vers du bruit.
  float t = clamp((vs_dist - 163840.0) / 2457600.0, 0.0, 1.0);
  color = vec4(mix(mix(far_rgb, near_rgb, 0.65), far_rgb, t), 1.0);
}
