#version 410 core

// Grecharged-ambient-occlusion: composite pass. Samples the final (blurred) AO factor
// and outputs it as a grey color; the C++ side binds GL_ZERO/GL_SRC_COLOR multiplicative
// blend so the opaque scene is darkened by (1 - occlusion) with no touch to transparents.
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_ao;
uniform int u_debug;
uniform float u_strength;

void main() {
  float ao = texture(u_ao, tex_coord).r;
  if (u_debug != 0) {
    color = vec4(vec3(ao), 1.0);  // raw AO term view
  } else {
    // bounded ambient-fraction modulation: AO may remove at most u_strength of the
    // lit color (approximates ambient-only AO in a pipeline with no separate ambient
    // buffer); sky stays white because the estimators output 1.0 at far depth.
    float m = 1.0 - u_strength * (1.0 - ao);
    color = vec4(vec3(m), 1.0);
  }
}
