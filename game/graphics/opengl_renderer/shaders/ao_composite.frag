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
  if (u_debug == 3) {
    // defect #7 water pixels: excluded from the composite by the stencil tag, so the
    // effective AO term is exactly 1.0 — the debug views show them white.
    color = vec4(1.0);
  } else if (u_debug != 0) {
    color = vec4(vec3(ao), 1.0);  // raw AO term view
  } else {
    // GOLDEN-RULE composite (owner-sourced 2026-07-16): the C++ side binds
    // GL_FUNC_REVERSE_SUBTRACT with (GL_ONE_MINUS_DST_COLOR, GL_ONE), i.e.
    // out = dst - (1-dst) * src. We output the OCCLUSION src = k*(1-ao): direct-lit
    // (bright) pixels are masked out by the (1-dst) ambient-fraction proxy, shadowed
    // pixels read the AO fully. Sky stays untouched because the estimators output 1.0
    // at far depth (src = 0).
    color = vec4(vec3(u_strength * (1.0 - ao)), 1.0);
  }
}
