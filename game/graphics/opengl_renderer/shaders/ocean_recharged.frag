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

// RECENSEMENT D'EMPRISE. A 0 ce shader ombre normalement. A 1 il ne rend plus qu'un « il y a de
// l'eau ici » — APRES les memes `discard` que le rendu livre, jamais avant. C'est ce qui interdit
// au recensement de mesurer une decoupe qui ne serait pas celle du jeu : une seconde copie du
// masque deriverait du rendu des la premiere retouche, et l'emprise mesuree ne serait plus la
// sienne. A 2 il publie l'ALPHA qu'il vient de calculer, encode dans le canal A : c'est LA MEME
// expression `alpha` que le rendu livre, jamais une seconde transcription — une porte qui lirait
// sa propre copie serait un miroir.
uniform int u_footprint;

#ifdef OG_FLIP_PROBE
layout(location = 0) out vec4 color;
uniform int u_floor_probe;
layout(location = 4) out vec4 floor_probe_out;
#else
out vec4 color;
#endif

void main() {
#ifdef OG_FLIP_PROBE
  floor_probe_out = vec4(0.0);
#endif
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

  // L'ALPHA DE NAUGHTY DOG, MOT POUR MOT. Le microcode near calcule sa transparence a partir de
  // LA MEME distance `d` que l'attenuation de houle (`eleng.xyz P, vf26` puis `mfp.w vf20`,
  // OceanNear_PS2.cpp:1205-1216, transcrite en `ocean_recharged.vert:76`), mais avec un PLANCHER
  // qui n'appartient qu'a l'alpha :
  //   `mulw.w  vf22, vf20, vf05` (:1225)  t = d * 0.000010172526          (1/98304 = 1/24 m)
  //   `miniw.w vf22, vf22, vf00` (:1234)  t = min(t, 1)
  //   `maxx.w  vf22, vf22, vf05` (:1244)  t = max(t, 0.5)   <- le plancher, propre a l'alpha
  //   `mulw.w  vf22, vf22, vf06` (:1274)  a_u8 = 128 * t
  // puis `ocean_common.vert:18` double l'alpha du sommet et `ocean_common.frag:51` le borne a 1 :
  // a = min(2 * 128 * t / 255, 1) = min(t * 256/255, 1).
  // L'eau d'origine est donc a MOITIE transparente sous la camera et opaque au-dela de 24 m :
  // c'est exactement ce que l'owner decrit le 10/09 (« on voit pas les orbes sous l'eau ») et le
  // 17/09 (« elle est opaque »). La clipmap ecrivait 1.0 en dur.
  float t = clamp(vs_dist * 0.000010172526, 0.5, 1.0);
  float alpha = min(t * (256.0 / 255.0), 1.0);
  // `mulaz.w ACC, vf00, vf07` puis `msubx.w vf07, vf22, vf07` (:1248-1252) : la couleur du sommet
  // est multipliee par (3 - 2t), de 2 sous la camera a 1 au-dela de 24 m. Sans ce gain, rendre
  // l'eau transparente la DELAVE ; avec lui, l'eau garde sa teinte et le fond se voit dessous —
  // c'est la compensation de Naughty Dog, pas une retouche d'artiste.
  float gain = 3.0 - 2.0 * t;

  if (u_footprint == 1) {
    color = vec4(1.0);
    return;
  }
  if (u_footprint == 2) {
    // 0 ne veut RIEN dire ici : c'est « pas d'eau sur cette cellule ». L'alpha part donc sur
    // 1..255, et l'hote relit a = (v - 1) / 254. Un alpha nul et une cellule vide se
    // confondraient sur un encodage 0..255, et la porte lirait un plancher qui n'existe pas.
    color = vec4(0.0, 0.0, 0.0, (1.0 + floor(alpha * 254.0 + 0.5)) * (1.0 / 255.0));
    return;
  }

  vec3 far_rgb = u_far_color.rgb * (1.0 / 255.0);
  vec3 near_rgb = texture(tex_ocean, vs_uv).rgb;
  // 40 m : au-dela, la texture d'ocean ND s'aliase de toute facon (ses mips passent en alpha 0
  // des le mip 2, OceanTexture.cpp:427-431). On fond vers far-color plutot que vers du bruit.
  float far_t = clamp((vs_dist - 163840.0) / 2457600.0, 0.0, 1.0);
  color = vec4(mix(mix(far_rgb, near_rgb, 0.65), far_rgb, far_t) * gain, alpha);
#ifdef OG_FLIP_PROBE
  // lighting-flipped-faces-everywhere : aucune normale n'entre dans cet ombrage provisoire.
  if (u_floor_probe >= 2) {
    float fc_l = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    floor_probe_out = vec4(1.0, 1.0, fc_l, 1.0 + 4.0 * float(u_floor_probe));
  }
#endif
}
