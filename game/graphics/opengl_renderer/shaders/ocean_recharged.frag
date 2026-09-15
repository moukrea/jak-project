#version 410 core

// water-ocean-mesh (SPEC-refonte-eau §5.3) — OMBRAGE PROVISOIRE DE LA CLIPMAP.
//
// « Shading provisoire = l'actuel » : ce fragment ne cree AUCUN modele de lumiere. Il echantillonne
// la texture d'ocean que Naughty Dog produit deja chaque image (`draw-ocean-texture`, 128 x 128,
// la surface animee) et la fond vers `far-color` de la carte avec la distance. Le vrai materiau —
// normales a deux cartes, Fresnel plafonne, absorption, `shade()` + SURF_WATER — est l'item 2
// `water-surface-material`, et rien ici ne doit lui ressembler.
//
// LA DECOUPE ND. La hierarchie mid/trans/near est reconstruite en cellules de 3 m.
// Chaque texel reprend un bit near : 0 dessine, 1 saute. Hors carte, on saute comme ND.

in vec2  vs_world_xz;
in float vs_dist;
in vec2  vs_uv;

uniform sampler2D tex_ocean;  // la texture d'ocean ND de cette image (RGBA8 128x128)
uniform sampler2D tex_mask;   // R8 1536x1536 : 0 = dessiner, 255 = sauter
uniform vec4 u_far_color;     // (-> *ocean-map* far-color), composantes 0..255
uniform vec4 u_ocean_origin;  // redeclare par ocean_layer_a.glsl cote vertex ; ici c'est le notre

out vec4 color;

void main() {
  // cellule near de 3 m : 12288 unites GOAL
  vec2 cell = (vs_world_xz - u_ocean_origin.xz) * (1.0 / 12288.0);
  ivec2 mi = ivec2(floor(cell));
  ivec2 mask_size = textureSize(tex_mask, 0);
  if (mi.x < 0 || mi.x >= mask_size.x || mi.y < 0 || mi.y >= mask_size.y) {
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
