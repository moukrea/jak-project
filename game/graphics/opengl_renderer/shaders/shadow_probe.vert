#version 410 core
// lighting-shadows (A7) : triangle plein ecran, sans VBO (gl_VertexID). Le VAO est vide mais
// DOIT exister (GLES l'exige pour tout draw sans attribut lie).
void main() {
  vec2 pos = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
}
