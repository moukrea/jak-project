#version 410 core

// Grecharged-ambient-occlusion: composite pass. Samples the final (blurred) AO factor
// and outputs a per-pixel grey MULTIPLIER (<=1); the C++ side binds
// GL_ZERO / GL_ONE_MINUS_SRC_COLOR (out = dst * (1 - src)) so the opaque scene can ONLY be
// darkened by the occlusion term — never lit, never hue-shifted. Direct-lit (bright) pixels
// are masked out via the SCALAR scene luminance (owner GOLDEN-RULE semantic preserved: pros
// keep AO out of directly-lit zones). Transparents are untouched (pass runs pre-alpha).
precision highp float;

in vec2 tex_coord;
out vec4 color;

uniform highp sampler2D u_ao;
uniform highp sampler2D u_scene;
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
    // GOLDEN RULE kept, BURN fixed (owner reopen 2026-07-21 "elle brule ce qu'elle ombre"):
    // the old per-channel (1-dst) reverse-subtract crushed a warm pixel's dark channels far
    // harder than its bright ones ((0.8,0.5,0.25) lost 6%/22%/67% R/G/B) — every crease
    // shifted toward saturated warm = the burn. The direct-lit mask is now the SCALAR scene
    // luminance (same owner semantic: bright/direct-lit pixels get ~zero AO) and the blend is
    // a pure per-pixel MULTIPLY <= 1 (C++ binds GL_ZERO / GL_ONE_MINUS_SRC_COLOR, i.e.
    // out = dst * (1 - src)): AO can ONLY DARKEN — never add light, never shift hue.
    float lum = clamp(dot(texture(u_scene, tex_coord).rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
    color = vec4(vec3(clamp(u_strength * (1.0 - ao) * (1.0 - lum), 0.0, 1.0)), 1.0);
  }
}
