// frame_ubo.glsl — LE BLOC D'IMAGE `ub_frame` (SPEC-refonte-lumiere §4.3, item
// lighting-ao-indirect). Inclus par les vertex ET fragment shaders des cinq hotes du decor
// (tfrag3, etie_base/etie, tie_wind, shrub, hfrag) et par les etages de tessellation, A LA PLACE
// des `uniform` de camera et de brouillard qu'ils declaraient : les noms sont les MEMES, le corps
// des shaders ne change pas. Miroir C++ : game/graphics/opengl_renderer/frame_ubo.cpp (224 o).
// Point de liaison 2, pose par Shader.cpp a l'edition de liens.
layout(std140) uniform ub_frame {
  mat4 pc_camera;
  mat4 camera;
  vec4 hvdf_offset;
  vec4 cam_trans;
  vec4 fog_color;
  float fog_constant;
  float fog_min;
  float fog_max;
  float u_frame_exposure;  // reserve (SPEC §4.5), 1.0
  vec4 u_frame_screen;     // w, h, 1/w, 1/h du FBO de rendu
  vec4 u_frame_misc;       // x = temps (s), y = palier, zw = 0
};
