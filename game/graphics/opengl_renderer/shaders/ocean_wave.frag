#version 410 core

// water-ocean-mesh (verdict C du 17/09 : « LES VAGUES RESTENT DES VAGUES ») — CE QUE LA SURFACE
// LIVREE DEPLACE VRAIMENT, RELU DU GPU.
//
// CE QUE CETTE PASSE MESURE, ET CE QU'ELLE NE MESURE PAS. Elle rend, pour une grille de points
// monde au PAS DE L'ANNEAU 0, le deplacement vertical que la clipmap donne a sa surface :
// `ocean_layer_a()` (la houle de Naughty Dog, captee au DMA du bucket 63) attenuee par
// `ocean_nd_atten()` (la loi de Naughty Dog). Les deux chunks sont ceux-la memes qu'utilise
// `ocean_recharged.vert` pour deplacer ses sommets — une seule transcription, deux lecteurs.
// L'hote compare ce releve a la table de houle de Naughty Dog lue A SA PROPRE RESOLUTION (3 m,
// CPU) : c'est la comparaison qui dit si NOTRE maillage resout le relief que SA donnee porte.
// Elle ne juge PAS la loi d'attenuation elle-meme, qui est le contrat de l'item ; elle juge que
// le maillage livre ne l'aplatit pas.
//
// L'ENCODAGE est celui de `ocean_probe.frag` : 1/256 d'unite GOAL biaise de 2^23 sur trois octets
// d'un RGBA8 — le seul format dont `glReadPixels` est garanti sur GLES 3.2. L'alpha vaut 1, le
// temoin qu'un fragment a bien tourne : une cible restee noire se lirait sinon « deplacement
// nul » au lieu de « rien n'a ete mesure ».

#include "ocean_layer_a.glsl"
#include "ocean_atten.glsl"

uniform vec2 u_wave_origin;  // monde xz du texel (0, 0)
uniform float u_wave_step;   // unites GOAL entre deux texels = le pas de l'anneau 0
uniform vec4 u_wave_cam;     // xyz = camera monde, w = (-> *ocean-map* start-corner) y

out vec4 color;

void main() {
  vec2 world_xz = u_wave_origin + floor(gl_FragCoord.xy) * u_wave_step;
  float a = ocean_layer_a(world_xz);
  // Le sommet porte sa hauteur AVANT attenuation : c'est la circularite de Naughty Dog,
  // reproduite telle quelle par `ocean_recharged.vert` et donc reproduite ici.
  float d = ocean_nd_dist(vec3(world_xz.x, u_wave_cam.w + a, world_xz.y), u_wave_cam.xyz);
  // Le DEPLACEMENT, sans le plan d'eau : c'est la houle que l'owner voit, pas l'altitude de la
  // mer. Ajouter `u_wave_cam.w` (qui descend a -98304) mangerait la precision du flottant.
  float y = a * ocean_nd_atten(d);
  int q = int(round(y * 256.0)) + 8388608;
  color = vec4(float(q & 255) / 255.0, float((q >> 8) & 255) / 255.0,
               float((q >> 16) & 255) / 255.0, 1.0);
}
