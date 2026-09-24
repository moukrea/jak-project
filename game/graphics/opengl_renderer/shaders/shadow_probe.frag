#version 410 core
out vec4 frag_color;
// lighting-shadows (A7) : noircit tout pixel qu'il touche (les pixels MONDE, via le stencil
// EQUAL 0 pose par l'appelant). Le vert/magenta de `shade()` (u_shadow_proof) ne survit que la
// ou ce triangle n'a pas touche — jamais l'inverse.
void main() {
  frag_color = vec4(0.0);
}
