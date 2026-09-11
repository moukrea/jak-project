#version 410 core

// hdr_max_reduce.frag — LA REDUCTION PAR MAXIMUM (item `hdr-curve-input`, chantier B du
// plan HDR, §1.5).
//
// Ce que ce programme corrige. La statistique qui pilote la courbe de sortie HDR etait obtenue
// en DESSINANT la scene dans une cible 16x16 par un quad texture : un sous-echantillonnage
// bilineaire, qui MOYENNE quatre texels autour du centre de chaque tuile et ignore les 1196
// autres. Mesure de l'etude (`hdr-study`, appareil eae4df44) : pic de scene vu par la
// statistique 1,617 quand la sonde de pixels voyait 15,094 sur les memes images — facteur 9,3.
// La courbe se reglait donc sur une image qu'elle ne voyait qu'au neuvieme.
//
// Ce que ce programme fait, et RIEN d'autre : pour chaque texel de sortie, le MAXIMUM par canal
// des `u_block` texels de source qu'il recouvre, lus par `texelFetch` (donc sans aucun filtrage :
// une moyenne de pilote diluerait exactement ce qu'on cherche). Aucune exposition, aucune courbe,
// aucune compression de plage — c'est `tonemap` qui applique la courbe, UNE fois, sur le resultat
// 16x16. La compression de plage est monotone par canal, donc max(f(v)) = f(max(v)) : appliquer
// la courbe apres la reduction donne EXACTEMENT le meme nombre qu'avant, et c'est ce qui rend la
// correction limitee a la reduction.
//
// COUVERTURE. L'appelant choisit `u_block = ceil(src / out)` : les indices balayes vont de 0 a
// out*block-1 >= src-1 sans trou, et le `min` borne le depassement sur le dernier texel. Aucun
// pixel de la source n'est hors de la reduction — c'est la propriete que « par maximum » exige.
//
// La borne 64 des deux boucles est CONSTANTE (le `break` fait le vrai travail) : un pilote GLES
// qui refuse une borne de boucle dependante d'un uniforme compile quand meme. L'appelant garantit
// u_block <= 64 par sa taille d'etage intermediaire.

uniform sampler2D tex_T0;
uniform ivec2 u_src_size;  // dimensions de la source, en texels
uniform ivec2 u_block;     // texels de source par texel de sortie (>= 1, <= 64)

out vec4 color;
in vec2 tex_coord;

void main() {
  ivec2 base = ivec2(gl_FragCoord.xy) * u_block;
  ivec2 last = u_src_size - ivec2(1);
  vec3 m = vec3(0.0);
  for (int j = 0; j < 64; j++) {
    if (j >= u_block.y) {
      break;
    }
    int sy = min(base.y + j, last.y);
    for (int i = 0; i < 64; i++) {
      if (i >= u_block.x) {
        break;
      }
      int sx = min(base.x + i, last.x);
      vec3 v = texelFetch(tex_T0, ivec2(sx, sy), 0).rgb;
      m = max(m, max(v, vec3(0.0)));
    }
  }
  color = vec4(m, 1.0);
}
