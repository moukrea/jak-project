// water-ocean-mesh (reprise du 19/09) — LE MASQUE DE PLAN D'EAU, LU COMME UNE DISTANCE AU RIVAGE.
//
// POURQUOI CE CHUNK EXISTE. L'owner a refuse DEUX choses opposees. Le 10/09 : « la riviere de
// forbidden jungle sort litteralement de son lit avec les vagues ». Le 17/09 puis le 19/09 :
// « la nouvelle mer ressemble trait pour trait a l'ancienne » / « les vagues ressemblaient plus a
// des vagues [avant] ». La reprise du 17/09 avait tenu le premier refus en recopiant
// l'EXTINCTION DE NAUGHTY DOG — la houle s'eteint a 24 m de la CAMERA (ocean_atten.glsl) — ce qui
// rend la mer entiere plate des qu'on la regarde, et c'est le second refus.
//
// Les deux se tiennent ensemble si la houle est bornee par le RIVAGE et non par la camera : une
// riviere est etroite, donc toute son eau est proche d'une berge et reste a plat ; la mer est
// large, donc elle porte son relief a n'importe quelle distance de l'oeil. C'est la cible de la
// SPEC (§1.3 decision 2) : « le lit de la riviere reste tenu par le masque de plan d'eau, pas par
// l'extinction a 24 m ».
//
// LA DONNEE. `tex_shore` est la transformee en distance du MEME masque near que
// `ocean_recharged.frag` utilise pour ses `discard` : 1536 x 1536 cellules de 3 m, valeur =
// distance a la cellule de terre la plus proche, en 1/32 de cellule, saturee a 255 (7,97
// cellules). Hors carte vaut terre : on n'invente pas d'eau la ou Naughty Dog n'en dessine pas.
// Elle est construite UNE fois par carte, dans `OceanRecharged::rebuild_mask_texture`.
//
// LA RAMPE EST CUBIQUE, PAS LINEAIRE. C'est ce qui fait tenir la porte « l'eau ne monte pas sur
// la berge » : a une cellule du bord (3 m) la houle vaut 1/125 de son amplitude, soit moins d'un
// centimetre, et elle n'atteint son plein relief qu'a 15 m du rivage. Une rampe lineaire y
// laisserait 180 mm, et l'eau grimperait visiblement le talus.
//
// CONTRAT. L'hote doit avoir inclus `ocean_layer_a.glsl` AVANT : `u_ocean_origin` y est declare,
// et le redeclarer ne compilerait pas.

uniform sampler2D tex_shore;  // R8 1536x1536 : distance a la terre, en 1/32 de cellule de 3 m

const float OCEAN_SHORE_CELLS = 5.0;  // 15 m : la largeur de la rampe de rivage

// La distance au rivage, en cellules near de 3 m. Hors carte : zero, c'est-a-dire « terre ».
float ocean_shore_dist_cells(vec2 world_xz) {
  vec2 cell = (world_xz - u_ocean_origin.xz) * (1.0 / 12288.0);
  vec2 size = vec2(textureSize(tex_shore, 0));
  if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= size.x || cell.y >= size.y) {
    return 0.0;
  }
  // `cell / size` et non `(cell + 0.5) / size` : le centre de la cellule c est a c + 0,5, donc
  // a (c + 0,5) / size, qui EST le centre du texel c. Le filtrage lineaire interpole alors entre
  // centres de cellules, et la rampe de rivage ne se lit pas en marches de 3 m.
  return texture(tex_shore, cell / size).r * (255.0 / 32.0);
}

float ocean_shore_atten(vec2 world_xz) {
  float t = clamp(ocean_shore_dist_cells(world_xz) / OCEAN_SHORE_CELLS, 0.0, 1.0);
  return t * t * t;
}
