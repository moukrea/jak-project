#version 410 core

layout(location = 0) out vec4 color;

in vec3 tex_coord;
uniform sampler2D tex_T0;

// hdr-sky-gpu-alpha — L'ACCUMULATION DES COUCHES DE CIEL SE FAIT ICI, PLUS DANS LE MELANGE.
// -----------------------------------------------------------------------------------------
// Le ciel est compose par ADDITION de couches. Tant que la cible etait `GL_RGBA8`, le melange a
// fonction fixe `glBlendFunc(GL_ONE, GL_ONE)` saturait TOUT a 1,0, alpha compris. Depuis que
// `hdr-source-range` a ouvert la cible en flottant, le RGB a le droit de depasser 1,0 — c'est le
// chantier — mais l'ALPHA l'a pris aussi, et lui n'est pas une couleur : c'est le POIDS DE
// MELANGE que le DirectRenderer du ciel consomme. Aucun facteur de melange a fonction fixe ne
// borne une SOMME sans changer sa valeur la ou elle ne saturait pas (`GL_SRC_ALPHA_SATURATE`
// rend 1 sur le canal alpha : il ne borne rien).
//
// L'addition est donc faite dans ce shader, melange GL ETEINT : `tex_prev` porte l'etat de la
// cible AVANT ce tirage (copie par `glBlitFramebuffer`, meme format, meme taille, GL_NEAREST —
// le quad couvre la cible exactement une fois, texel pour texel). La borne s'applique au POIDS
// LUI-MEME, a l'endroit ou il est produit, et pas a un ecretage en aval.
//
// `alpha_limit` vaut 1,0 pour l'etat LIVRE. Le temoin de mesure le porte a l'infini et refait la
// MEME accumulation dans sa propre cible : c'est ce qui donne, dans UNE SEULE course, la valeur
// d'AVANT a cote de celle d'APRES. Le RGB, lui, n'est borne par rien — le relire des deux cotes
// est le temoin que ce correctif n'a pas repris la plage que le chantier A avait ouverte.
uniform sampler2D tex_prev;
uniform float alpha_limit;

void main() {
  vec4 T0 = texture(tex_T0, tex_coord.xy);
  vec4 src = T0 * tex_coord.z;
  vec4 prev = texture(tex_prev, tex_coord.xy);
  color = vec4(prev.rgb + src.rgb, min(prev.a + src.a, alpha_limit));
}
