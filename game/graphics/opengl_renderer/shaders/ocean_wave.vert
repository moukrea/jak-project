#version 410 core

// water-ocean-mesh (verdict C du 17/09) — LA SONDE DE HOULE.
// Un triangle plein cadre, sans attribut : la cible fait 65 x 65 texels, donc 4225 fragments,
// donc 64 cellules de l'anneau 0 dans chaque direction — exactement les +-24 m ou l'attenuation
// de Naughty Dog laisse encore de la houle.

void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
