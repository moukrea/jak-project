#version 410 core

// REOPEN #3 TESSELLATION displacement — tessellation EVALUATION stage.
// Runs per generated vertex. Barycentric-interpolates the tc_* varyings from tfrag3.tesc,
// displaces the world position along the (interpolated, normalized) normal by the PBR height
// map, then reproduces tfrag3.vert's EXACT camera transform + fog + scissor adjust and emits the
// varyings the (unchanged) tfrag3.frag consumes.

layout (triangles, fractional_odd_spacing, ccw) in;

in vec3 tc_world[];
in vec3 tc_texcoord[];
in vec3 tc_normal[];
in vec4 tc_color[];

// same uniforms tfrag3.vert uses for the camera transform / fog / scissor.
uniform vec4 hvdf_offset;
uniform vec4 cam_trans;
uniform mat4 pc_camera;
uniform float fog_min;
uniform float fog_max;

#ifdef OG_PBR
uniform int u_pbr_mode;            // bit16 => a height map is bound
uniform int u_pbr_displacement;    // 2 => Tessellation displacement active
uniform float u_pbr_height_scale;  // POM's native-UV depth scale (also drives displacement amount)
uniform float u_pbr_uv_tile;       // extra UV tiling on the PBR path
uniform sampler2D tex_PBR_H;       // height map, unit 15 (.r = height, 0.5 = neutral mid)

// REOPEN #3/#6 TESS DISPLACEMENT MAGNITUDE. u_pbr_height_scale is the POM's UV-space depth scale;
// TESS_DISP_K converts that to WORLD (game) units so the geometric displacement is REAL. Because
// this is genuine vertex displacement it can NEVER float like POM does — so tessellation keeps a
// deeper, convincing relief (~5 cm peak-to-trough) even though REOPEN #6 dropped the POM base
// depth 3.5x (0.07 -> 0.02) to surface-lock the parallax. K is bumped 3.5x to compensate and keep
// the real-geometry displacement calibrated: 0.02 (base) * 1.5 (relief) * 14336 * 0.5 ~= 215 game
// units ~= 5.25 cm. 1 game unit = 1/4096 m. Single knob — tune if the relief reads too deep/shallow.
#define TESS_DISP_K 14336.0
#endif

// frag-consumed varyings (exact names/types from tfrag3.frag / tfrag3.vert).
out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
out vec3 v_normal;
out vec3 v_fringe_rel;
out vec3 v_world;

vec3 bary3(vec3 a, vec3 b, vec3 c) {
  return gl_TessCoord.x * a + gl_TessCoord.y * b + gl_TessCoord.z * c;
}
vec4 bary4(vec4 a, vec4 b, vec4 c) {
  return gl_TessCoord.x * a + gl_TessCoord.y * b + gl_TessCoord.z * c;
}

void main() {
  vec3 world = bary3(tc_world[0], tc_world[1], tc_world[2]);
  vec3 uv3 = bary3(tc_texcoord[0], tc_texcoord[1], tc_texcoord[2]);
  vec4 col = bary4(tc_color[0], tc_color[1], tc_color[2]);
  vec3 nrm = bary3(tc_normal[0], tc_normal[1], tc_normal[2]);
  float nlen2 = dot(nrm, nrm);
  vec3 N = nlen2 > 1e-8 ? nrm * inversesqrt(nlen2) : vec3(0.0, 1.0, 0.0);

#ifdef OG_PBR
  // Height displacement: only when a height map is bound AND Tessellation mode is selected.
  if ((u_pbr_mode & 16) != 0 && u_pbr_displacement == 2 && u_pbr_height_scale > 0.0) {
    vec2 huv = uv3.xy * u_pbr_uv_tile;
    float h = textureLod(tex_PBR_H, huv, 0.0).r;   // 0.5 = neutral surface
    // camera distance in meters (same convention as v_fringe_rel below), fade 20 -> 30 m to 0 so
    // far patches (which are passthrough anyway) never pop, and mid patches ease in smoothly.
    float dist_m = length((world - cam_trans.xyz) * (1.0 / 4096.0));
    float falloff = 1.0 - smoothstep(20.0, 30.0, dist_m);
    float disp = (h - 0.5) * u_pbr_height_scale * TESS_DISP_K * falloff;
    world += N * disp;   // world normal is in game-unit space; displacement is in game units
  }
#endif

  // ---- tfrag3.vert's EXACT camera transform (world -> clip) ----
  vec3 vert = world - cam_trans.xyz;
  v_fringe_rel = vert * (1.0 / 4096.0);
  v_world = world;
  v_normal = N;
  vec4 transformed = -pc_camera[3];
  transformed.w = 0.0;
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;

  // fog (identical to tfrag3.vert)
  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

  // scissoring area adjust (identical to tfrag3.vert)
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;

  fragment_color = col;
  tex_coord = uv3;
}
