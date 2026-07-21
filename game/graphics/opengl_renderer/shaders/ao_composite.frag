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
    // REOPEN #3 (owner: burnt -> then invisible; calibrate the VISIBLE-SOFT MIDDLE): the
    // linear (1-lum) mask throttled AO ~2x exactly in the mid tones where crevices/contacts
    // live => "quasi pas remarquable". Soft-knee mask instead: FULL occlusion up to mid
    // luminance, fading to zero only across genuinely sun-bright pixels (golden rule kept:
    // direct-lit still gets ~zero AO — sunlit lum~0.75 keeps the old ~0.25 weight; lum 0.5
    // doubles from 0.5 to ~0.97). Max darkening stays bounded by u_strength (never full
    // black) and the multiply is hue-preserving => soft but clearly noticeable, not burnt.
    float mask = 1.0 - smoothstep(0.45, 0.90, lum);
    color = vec4(vec3(clamp(u_strength * (1.0 - ao) * mask, 0.0, 1.0)), 1.0);
  }
}
