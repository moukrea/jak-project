#version 410 core

// water-ocean-mesh (verdict C du 17/09 « LES VAGUES RESTENT DES VAGUES », reprise du 19/09) —
// CE QUE LA SURFACE LIVREE DEPLACE VRAIMENT, RELU DU GPU.
//
// CE QUE CETTE PASSE MESURE, ET CE QU'ELLE NE MESURE PAS. Elle rend, pour une grille de points
// monde, le deplacement vertical que la clipmap donne a sa surface : la houle de Naughty Dog
// (`ocean_layer_a()`, captee au DMA du bucket 63) bornee par `max(attenuation ND, rampe de
// rivage)`, plus la couche B. Les quatre chunks sont ceux-la memes qu'utilise
// `ocean_recharged.vert` pour deplacer ses sommets — une seule transcription, deux lecteurs.
// L'hote compare ce releve a la surface de Naughty Dog calculee CPU (`layer_a_cpu` x
// `nd_atten_factor`), qui est ce que le jeu d'origine dessine. Elle ne juge PAS les lois
// elles-memes, qui sont le contrat de l'item ; elle juge que la surface livree porte vraiment le
// relief qu'on lui prete, et ou.
//
// LE PAS DE L'ANNEAU EST CALCULE PAR POINT. La couche B s'eteint quand l'anneau qui la dessine ne
// peut plus la resoudre ; mesurer un point de l'anneau 1 avec le pas de l'anneau 0 decrirait donc
// une surface que personne ne dessine. Les bornes sont les TROUS des anneaux 1 et 2 (+-42 m,
// +-144 m), c'est-a-dire l'anneau qui couvre reellement le point.
//
// L'ENCODAGE est celui de `ocean_probe.frag` : 1/256 d'unite GOAL biaise de 2^23 sur trois octets
// d'un RGBA8 — le seul format dont `glReadPixels` est garanti sur GLES 3.2. L'alpha vaut 1, le
// temoin qu'un fragment a bien tourne : une cible restee noire se lirait sinon « deplacement
// nul » au lieu de « rien n'a ete mesure ».

#include "ocean_layer_a.glsl"
#include "ocean_atten.glsl"
#include "ocean_shore.glsl"
#include "ocean_layer_b.glsl"

uniform vec2 u_wave_origin;  // monde xz du texel (0, 0)
uniform float u_wave_step;   // unites GOAL entre deux texels
uniform vec4 u_wave_cam;     // xyz = camera monde, w = (-> *ocean-map* start-corner) y
uniform vec4 u_wave_rings;   // xyz = pas des trois anneaux ; w = l'horloge de la couche B
uniform vec2 u_wave_center;  // centre monde xz de l'anneau 0 (la camera, snappee)

out vec4 color;

void main() {
  vec2 world_xz = u_wave_origin + floor(gl_FragCoord.xy) * u_wave_step;
  float a = ocean_layer_a(world_xz);
  // Le sommet porte sa hauteur AVANT attenuation : c'est la circularite de Naughty Dog,
  // reproduite telle quelle par `ocean_recharged.vert` et donc reproduite ici.
  float d = ocean_nd_dist(vec3(world_xz.x, u_wave_cam.w + a, world_xz.y), u_wave_cam.xyz);
  float f = ocean_nd_atten(d);
  float shore = ocean_shore_atten(world_xz);

  vec2 off = abs(world_xz - u_wave_center);
  float cheb = max(off.x, off.y);
  float ring_step = (cheb <= 172032.0) ? u_wave_rings.x        // trou de l'anneau 1 : +-42 m
                                       : ((cheb <= 589824.0) ? u_wave_rings.y   // +-144 m
                                                             : u_wave_rings.z);

  // Le DEPLACEMENT, sans le plan d'eau : c'est la houle que l'owner voit, pas l'altitude de la
  // mer. Ajouter `u_wave_cam.w` (qui descend a -98304) mangerait la precision du flottant.
  float y = a * max(f, shore) + ocean_layer_b(world_xz, u_wave_rings.w, ring_step) * shore;
  int q = int(round(y * 256.0)) + 8388608;
  color = vec4(float(q & 255) / 255.0, float((q >> 8) & 255) / 255.0,
               float((q >> 16) & 255) / 255.0, 1.0);
}
