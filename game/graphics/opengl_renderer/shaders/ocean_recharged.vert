#version 410 core

// water-ocean-mesh (SPEC-refonte-eau §5.3) — LA CLIPMAP D'OCEAN.
//
// UN SEUL maillage de sommets (129 x 129 coordonnees de grille entieres, de -64 a +64) sert aux
// TROIS anneaux : seuls le pas, le centre et l'etendue changent, par uniforme. Trois plages
// d'indices decoupent le trou central de chaque anneau. C'est pourquoi le VBO fait 16 641
// sommets et non les ~47 000 d'une clipmap a maillages separes — meme geometrie a l'ecran, un
// tiers du bus.
//
// LE MONDE, PAS L'ECRAN. Le chemin d'ocean de Naughty Dog n'a AUCUNE matrice camera : les
// sommets arrivent deja en coordonnees ecran PS2, transformes par l'emulation VU sur le CPU
// (`ocean_common.vert:15`). Une clipmap en espace monde doit donc faire sa propre
// transformation ; celle-ci est recopiee VERBATIM de `collision.vert` / `grass.vert`, pour que
// l'eau tombe exactement sur les memes pixels que le sable qu'elle recouvre.

layout (location = 0) in vec2 in_grid;  // coordonnees de grille entieres, -64 .. +64

// camera de scene (memes uniformes et memes semantiques que collision.vert / grass.vert)
uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform vec4 camera_position;
uniform float fog_constant;

// l'anneau en cours
uniform vec2  u_ring_center;  // centre monde xz de l'anneau, DEJA snappe au pas
uniform float u_ring_step;    // unites GOAL par cellule
uniform float u_water_y;      // (-> *ocean-map* start-corner y), unites GOAL

// L'ATTENUATION DE NAUGHTY DOG, ET SON BRAS D'ABLATION.
// 1.0 = le regime LIVRE (la houle s'eteint comme chez ND) ; 0.0 = le regime de l'essai 6 (A
// entiere a toute distance). Les deux sont dessines dans la MEME image par le recensement
// d'emprise, qui chiffre ce que l'attenuation retire a l'ecran. Le drapeau est pose a CHAQUE
// draw : une valeur laissee par un autre appel ferait mesurer l'autre regime sans rien montrer.
uniform float u_atten_on;

#include "ocean_layer_a.glsl"
#include "ocean_atten.glsl"

out vec2  vs_world_xz;
out float vs_dist;
out vec2  vs_uv;

vec4 world_to_clip(vec3 pos) {
  vec4 transformed = -camera[3].xyzw;
  transformed += -camera[0] * pos.x;
  transformed += -camera[1] * pos.y;
  transformed += -camera[2] * pos.z;
  float Q = fog_constant / transformed[3];
  transformed.xyz *= Q;
  transformed.xyz += hvdf_offset.xyz;
  transformed.xy -= (2048.);
  transformed.z /= (8388608.0);
  transformed.z -= 1.0;
  transformed.x /= (256.0);
  transformed.y /= -(128.0);
  transformed.xyz *= transformed.w;
  vec4 p = transformed;
  p.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  return p;
}

void main() {
  vec2 world_xz = u_ring_center + in_grid * u_ring_step;

  // LA HAUTEUR VISUELLE. A est evaluee aux sommets ; les couches B (Gerstner) et C (RT de rides)
  // n'existent pas encore. La borne de l'excedent visuel entre sommets reste non mesuree.
  float a = ocean_layer_a(world_xz);

  // LA DISTANCE ET L'ATTENUATION DE NAUGHTY DOG. Les deux sont dans `ocean_atten.glsl`, seule
  // transcription du microcode (OceanNear_PS2.cpp:1181-1216 pour la distance, :1224-1250 pour
  // l'attenuation) ; la sonde de houle du verdict C lit LE MEME texte, sans quoi la grandeur
  // publiee decrirait une autre surface que celle-ci. Le sommet porte sa hauteur AVANT
  // attenuation — c'est la circularite de ND, reproduite telle quelle et non corrigee.
  // Au-dela de 24 m de la camera, l'ocean de Naughty Dog est PLAT : le mid et la transition le
  // sont par construction (ocean-transition.gc:500-504). La clipmap gardait A entiere jusqu'a
  // 2304 m : c'est la houle qui montait sur les berges.
  float y_raw = u_water_y + a;
  float d = ocean_nd_dist(vec3(world_xz.x, y_raw, world_xz.y), camera_position.xyz);
  float f = ocean_nd_atten(d);
  float y = u_water_y + a * mix(1.0, f, u_atten_on);

  vs_world_xz = world_xz;
  vs_dist = d;
  // Une periode de houle (32 cellules de 3 m = 96 m) couvre exactement une fois la texture
  // d'ocean de Naughty Dog : c'est le meme modulo 32 que la couche A, pas un tuilage invente.
  vs_uv = (world_xz - u_ocean_origin.xz) * (0.00008138021 / 32.0);

  gl_Position = world_to_clip(vec3(world_xz.x, y, world_xz.y));
}
