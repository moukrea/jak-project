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

// LE REGIME DESSINE, ET SON BRAS DE TEMOIN.
// 0 = le regime LIVRE (rampe de rivage + couche B) ; 1 = LE MEME, rivage force a 1, c'est-a-dire
// la houle entiere partout : le regime du build du 10/09, celui dont l'owner a dit que la
// riviere sortait de son lit. Les deux sont dessines dans la MEME image par le recensement
// d'emprise, qui chiffre alors ce que la rampe de rivage retire a l'ecran. Le drapeau est pose a
// CHAQUE draw : une valeur laissee par un autre appel ferait mesurer l'autre regime sans rien
// montrer.
uniform int u_regime;
uniform float u_time;  // secondes, l'horloge de la couche B

#include "ocean_layer_a.glsl"
#include "ocean_atten.glsl"
#include "ocean_shore.glsl"
#include "ocean_layer_b.glsl"

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

  // LA HAUTEUR VISUELLE. A est evaluee aux sommets ; la couche B s'y ajoute ; la couche C (RT de
  // rides) n'existe pas encore. La borne de l'excedent visuel entre sommets reste non mesuree.
  float a = ocean_layer_a(world_xz);

  // LA DISTANCE ET L'ATTENUATION DE NAUGHTY DOG. Les deux sont dans `ocean_atten.glsl`, seule
  // transcription du microcode (OceanNear_PS2.cpp:1181-1216 pour la distance, :1224-1250 pour
  // l'attenuation) ; la sonde de houle lit LE MEME texte, sans quoi la grandeur publiee
  // decrirait une autre surface que celle-ci. Le sommet porte sa hauteur AVANT attenuation —
  // c'est la circularite de ND, reproduite telle quelle et non corrigee.
  float y_raw = u_water_y + a;
  float d = ocean_nd_dist(vec3(world_xz.x, y_raw, world_xz.y), camera_position.xyz);
  float f = ocean_nd_atten(d);

  // CE QUI BORNE LA HOULE : LE RIVAGE, ET NON PLUS LA CAMERA (reprise du 19/09).
  // `max(f, rivage)` et non `rivage` seul : la houle livree est donc, EN TOUT POINT, au moins
  // celle que Naughty Dog dessine. Sous les 24 m ou ND a du relief, f domine et la surface est
  // la SIENNE, au bit pres ; au-dela, ou ND est plat, c'est la rampe de rivage qui decide. Cette
  // borne inferieure est ce qui interdit structurellement une regression du verdict C (« les
  // vagues restent des vagues ») et ce qui garde l'eau des berges a la hauteur EXACTE de
  // l'original la ou la rampe vaut zero.
  float shore = (u_regime == 1) ? 1.0 : ocean_shore_atten(world_xz);
  // La couche B ne suit QUE le rivage : une riviere n'a pas de clapot de haute mer, et un
  // deplacement de 23 cm au ras d'une berge se verrait monter dessus.
  float b = ocean_layer_b(world_xz, u_time, u_ring_step) * shore;
  float y = u_water_y + a * max(f, shore) + b;

  vs_world_xz = world_xz;
  vs_dist = d;
  // Une periode de houle (32 cellules de 3 m = 96 m) couvre exactement une fois la texture
  // d'ocean de Naughty Dog : c'est le meme modulo 32 que la couche A, pas un tuilage invente.
  vs_uv = (world_xz - u_ocean_origin.xz) * (0.00008138021 / 32.0);

  gl_Position = world_to_clip(vec3(world_xz.x, y, world_xz.y));
}
