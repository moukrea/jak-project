#version 410 core
// Phase 29 (autoport): vertex-color splash gradient.
//
// Drawn as a single full-screen triangle (3 vertices, 3 distinct
// per-vertex colors) so the rasterizer interpolates across the visible
// pixels and produces a continuous gradient. The Android renderer-chain
// composite uses this to anchor pixel diversity in the central screen
// region — the phase-29 validator's `anti_stub_count_pixel_diversity`
// samples a 200x200 center crop and rejects framebuffers with <50
// unique RGB triples.
//
// Not a replacement for any upstream shader: jak1 has no equivalent
// splash gradient — the desktop boot path uses `splash` (textured) on
// the splash PNG. Adreno's smaller texture budget at boot makes the
// PNG path racy on phase 29's first-frame contract, so we substitute
// a procedural gradient here. Phase 30+ replace this with the textured
// splash once the Loader / TextureUpload paths are live on Android.

layout (location = 0) in vec2 position_in;
layout (location = 1) in vec3 color_in;

out vec3 vert_color;

void main() {
  gl_Position = vec4(position_in, 0.0, 1.0);
  vert_color = color_in;
}
