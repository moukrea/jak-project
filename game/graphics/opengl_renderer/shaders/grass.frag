#version 410 core

// Grecharged-grass-poc: flat-color grass (no texture yet, per the PoC spec).
// Color + LOD alpha come from the vertex stage.

in vec3 v_color;
in float v_alpha;

out vec4 color;

void main() {
  if (v_alpha < 0.02) {
    discard;
  }
  color = vec4(v_color, v_alpha);
}
