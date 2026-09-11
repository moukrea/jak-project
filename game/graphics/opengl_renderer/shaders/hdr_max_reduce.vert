#version 410 core

// hdr_max_reduce.vert — le quad plein cadre de la reduction par MAXIMUM (hdr-curve-input).
// Identique a tonemap.vert : le meme VAO (attribut 0 = position NDC) sert les deux programmes,
// donc `analyze_scene` n'a qu'a changer de programme, jamais de liaison de sommets.

layout (location = 0) in vec2 position_in;

out vec2 tex_coord;

void main() {
  gl_Position = vec4(position_in, 0, 1.0);
  tex_coord = (position_in + vec2(1.0, 1.0)) * 0.5;
}
