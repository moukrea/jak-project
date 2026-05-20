#version 410 core
// Phase 29 (autoport): companion fragment shader for splash_gradient.vert.
// Outputs the rasterizer-interpolated per-vertex color. See the vert
// header for the rationale on why this shader pair exists alongside
// upstream `splash`.

in vec3 vert_color;
out vec4 out_color;

void main() {
  out_color = vec4(vert_color, 1.0);
}
