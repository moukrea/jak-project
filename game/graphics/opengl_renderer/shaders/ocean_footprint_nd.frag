#version 410 core

// « Il y a de l'eau d'origine ici. » Une seule valeur, ecrite dans le seul canal que le
// recensement laisse ouvert par `glColorMask`. `ocean_common.frag` n'a AUCUN `discard` : la
// couverture de Naughty Dog est exactement sa geometrie rasterisee, et c'est cela qu'on compte.

out vec4 color;

void main() {
  color = vec4(1.0);
}
