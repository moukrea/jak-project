// water-ocean-mesh (SPEC-refonte-eau §5.2 couche A) — LA HAUTEUR DE JEU, LUE PAR LE GPU.
//
// POURQUOI CE CHUNK EXISTE. La regle 2 de la SPEC dit que la hauteur que le GAMEPLAY lit ne
// bouge pas d'un millimetre, et que le visuel s'ajoute PAR-DESSUS. La seule facon de le PROUVER
// est que la clipmap et la sonde de controle lisent la couche A par LA MEME fonction : deux
// transcriptions independantes de `ocean-get-height` derivent, et la porte deviendrait un miroir
// de l'une des deux. Ce fichier est donc l'unique transcription, incluse par
// `ocean_recharged.vert` (ce qui est DESSINE) et par `ocean_probe.frag` (ce qui est MESURE).
//
// CONTRAT. L'hote doit declarer, avant l'include : rien. Ce chunk declare lui-meme ses deux
// uniformes (`tex_layer_a`, `u_ocean_origin`) ; un hote qui les redeclarerait ne compilerait pas,
// ce qui est le comportement voulu.
//
// LA SOURCE. `ocean-get-height` (goal_src/jak1/engine/gfx/ocean/ocean.gc:16-35) lit
// `*ocean-heights*`, 1024 flottants (32x32, row-major, la ligne est z) que `ocean-interp-wave`
// remplit chaque image en interpolant DEUX des 64 frames cuites. Ce meme tampon part au DMA du
// bucket 63 par `ocean-near-add-heights` (2 x 2048 octets) : c'est LA qu'il est capte, donc les
// texels de `tex_layer_a` sont les octets memes que le gameplay lit, pas une copie recalculee.
//
// LES QUATRE PIEGES RECOPIES A L'IDENTIQUE :
//   * la cellule vaut 12288 unites GOAL (3 m) : 0.00008138021 == 1/12288 ;
//   * `(the int f)` TRONQUE vers zero, donc la fraction est NEGATIVE a gauche de l'origine de la
//     carte — extrapolation, quirk de Naughty Dog, reproduit tel quel ;
//   * `(logand ... 31)` est un ET sur un entier signe : `int(-1) & 31 == 31`, meme complement
//     a deux qu'en GOAL ;
//   * l'index est `iz * 32 + ix`, jamais l'inverse.
//
// `texelFetch` et non `texture()` : le filtrage bilineaire du materiel arrondirait les poids en
// 8 bits de sous-texel sur GLES, et la porte `water_gameplay_height_maxdelta_mm == 0` ne
// survivrait pas a cet arrondi. Le bilerp est fait a la main, dans l'ordre exact du GOAL.

uniform sampler2D tex_layer_a;  // R32F 32x32 : texel (ix, iz) = *ocean-heights*[iz * 32 + ix]
uniform vec4 u_ocean_origin;    // xyz = (-> *ocean-map* start-corner), unites GOAL

// Rend la couche A SANS le `+ start-corner.y` : l'appelant l'ajoute. La porte compare des couches
// A, et un offset commun aux deux cotes ne prouverait rien de plus tout en mangeant la precision
// du flottant 32 bits (start-corner.y descend a -98304).
float ocean_layer_a(vec2 world_xz) {
  float u = (world_xz.x - u_ocean_origin.x) * 0.00008138021;
  float w = (world_xz.y - u_ocean_origin.z) * 0.00008138021;
  int iu = int(u);
  int iw = int(w);
  float fx = u - float(iu);
  float fz = w - float(iw);
  int ix0 = iu & 31;
  int iz0 = iw & 31;
  int ix1 = (ix0 + 1) & 31;
  int iz1 = (iz0 + 1) & 31;
  float h00 = texelFetch(tex_layer_a, ivec2(ix0, iz0), 0).r;
  float h10 = texelFetch(tex_layer_a, ivec2(ix1, iz0), 0).r;
  float h01 = texelFetch(tex_layer_a, ivec2(ix0, iz1), 0).r;
  float h11 = texelFetch(tex_layer_a, ivec2(ix1, iz1), 0).r;
  float row0 = h10 * fx + h00 * (1.0 - fx);
  float row1 = h11 * fx + h01 * (1.0 - fx);
  return row1 * fz + row0 * (1.0 - fz);
}
