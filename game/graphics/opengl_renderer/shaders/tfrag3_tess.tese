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
in vec4 tc_tangent[];
in float tc_seam[];

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

// Grecharged-mesh-consolidation: tiling of the WORLD-SPACE height lookup, in tiles per metre
// (0.5 = one tile every 2 m, about the density tfrag's authored ground UVs sit at). Multiplied by
// u_pbr_uv_tile so debug.opengoal.pbr.uvtile still tunes it live.
#define WORLD_TILES_PER_M 0.5

// The same bisect word tfrag3.frag declares. The tess pipeline uses tfrag3.frag as its fragment
// stage, so this uniform already exists on this program and is already pushed by the C++ setup —
// declaring it here costs nothing. 65536 = legacy per-chunk UV height lookup (the one that tears),
// 131072 = ignore the per-vertex seam weights. Both exist purely for live A/B.
uniform int u_pbr_bisect;
#endif

// frag-consumed varyings (exact names/types from tfrag3.frag / tfrag3.vert).
out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
out vec3 v_normal;
out vec3 v_fringe_rel;
out vec3 v_world;
out vec4 v_tangent;  // REOPEN#7: emit the interpolated per-vertex tangent for tfrag3.frag

vec3 bary3(vec3 a, vec3 b, vec3 c) {
  return gl_TessCoord.x * a + gl_TessCoord.y * b + gl_TessCoord.z * c;
}
vec4 bary4(vec4 a, vec4 b, vec4 c) {
  return gl_TessCoord.x * a + gl_TessCoord.y * b + gl_TessCoord.z * c;
}
float bary1(float a, float b, float c) {
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
    // ---- Grecharged-mesh-consolidation: SEAM-CONSISTENT DISPLACEMENT (the see-through slits) ----
    //
    // (1) The height must be a function of WORLD POSITION, not of the per-chunk texcoord. The
    //     tessellator generates NEW vertices all ALONG a shared edge, and each patch interpolates
    //     ITS OWN texcoords for them — so two chunks meeting at that edge sample different texels
    //     down its entire length, not merely at the two corners. No amount of per-vertex data can
    //     fix that: only a height FIELD that is a function of position agrees on both sides. (The
    //     previous phase already measured why a common UV frame does not exist — 40% of cross-chunk
    //     seams have tangent frames rotated >30 deg and ~27% are mirrored — and adopted the same
    //     world-derived-frame answer for the normal map's tangent basis in stable_frame().)
    //     `world` and `N` are now bit-identical across a welded edge: mesh_consolidate() snaps
    //     coincident positions to one value and gives the group one shared normal. So this whole
    //     expression is bit-identical on both sides, and the two surfaces displace together.
    vec2 huv;
    // Grecharged-pbr-realtime-fusion PBR POLISH: the two WORLD axes the projection above uses, and
    // the huv-units-per-METRE scale, kept so the displaced surface's own normal can be derived
    // from the very same height field (see the gradient block after the displacement).
    vec3 hax_u = vec3(1.0, 0.0, 0.0);
    vec3 hax_v = vec3(0.0, 0.0, 1.0);
    float huv_per_m = WORLD_TILES_PER_M * u_pbr_uv_tile;
    if ((u_pbr_bisect & 65536) != 0) {
      huv = uv3.xy * u_pbr_uv_tile;  // legacy per-chunk lookup — kept ONLY as the A/B that tears
      huv_per_m = 0.0;               // no world mapping on the legacy path => no gradient normal
    } else {
      // project onto the world plane most face-on to the surface, so walls do not smear
      vec3 an = abs(N);
      vec2 pw;
      if (an.y >= an.x && an.y >= an.z) {
        pw = world.xz;
        hax_u = vec3(1.0, 0.0, 0.0);
        hax_v = vec3(0.0, 0.0, 1.0);
      } else if (an.x >= an.z) {
        pw = world.zy;
        hax_u = vec3(0.0, 0.0, 1.0);
        hax_v = vec3(0.0, 1.0, 0.0);
      } else {
        pw = world.xy;
        hax_u = vec3(1.0, 0.0, 0.0);
        hax_v = vec3(0.0, 1.0, 0.0);
      }
      huv = pw * ((1.0 / 4096.0) * WORLD_TILES_PER_M * u_pbr_uv_tile);
    }
    float h = textureLod(tex_PBR_H, huv, 0.0).r;   // 0.5 = neutral surface

    // (2) Where the two sides CANNOT displace alike at all, displace neither. The height map is
    //     bound PER DRAW, so a material boundary has one side with a map and one without; tie and
    //     shrub are never tessellated; an open boundary has nothing on the other side; and a hard
    //     crease has a different normal each side. mesh_consolidate() zeroes seam_w on exactly
    //     those vertices, and barycentric interpolation of a zeroed corner pair makes `seam` — and
    //     therefore the displacement — EXACTLY zero along the shared edge, from both patches.
    float seam = clamp(bary1(tc_seam[0], tc_seam[1], tc_seam[2]), 0.0, 1.0);
    if ((u_pbr_bisect & 131072) != 0) {
      seam = 1.0;  // A/B: ignore the seam weights
    }

    // camera distance in meters (same convention as v_fringe_rel below), fade 20 -> 30 m to 0 so
    // far patches (which are passthrough anyway) never pop, and mid patches ease in smoothly.
    // Uses the UNDISPLACED `world`, which is shared across the edge, so the fade matches too.
    float dist_m = length((world - cam_trans.xyz) * (1.0 / 4096.0));
    float falloff = 1.0 - smoothstep(20.0, 30.0, dist_m);
    float amp = u_pbr_height_scale * TESS_DISP_K * falloff * seam;
    float disp = (h - 0.5) * amp;
    world += N * disp;   // world normal is in game-unit space; displacement is in game units

    // ---- PBR POLISH (owner playtest #16 defect 3: the displacement "reads FLAT ... un bump map
    //      glorifie avec un peu de normales") ----
    // The tessellator MOVED real vertices but kept emitting the UNDISPLACED interpolated normal
    // `N` below, so every lighting term downstream shaded the displaced surface AS IF IT WERE
    // STILL FLAT. Real geometry lit by a flat normal looks exactly like a bump map — which is
    // precisely what the owner reported, and it is why raising TESS_DISP_K never helped: the
    // silhouette moved, the shading never did. Derive the surface normal from the SAME world
    // height field that produced the displacement (central differences along the projection axes),
    // so geometry and shading finally agree and the relief reads as depth. The authored normal map
    // then rides on top of this macro normal in the fragment stage — macro from the geometry,
    // micro from the map, which is the standard displacement-mapping split.
    // SEAM-SAFE by construction: world, N, huv, falloff and seam are all bit-identical across a
    // welded edge, so this normal is too; and where seam fades to 0 the amplitude fades with it,
    // so the normal eases back to the geometric one instead of stepping.
    // bisect bit 1048576 = emit the UNDISPLACED normal, i.e. exactly the pre-polish behaviour.
    // This is the live A/B killswitch for this fix: same boot, same vantage, same displaced
    // vertices, only the shading normal changes — so the capture pair isolates "real geometry lit
    // as if flat" from "real geometry lit as displaced".
    if (huv_per_m > 0.0 && amp > 0.0 && (u_pbr_bisect & 1048576) == 0) {
      const float MS_M = 0.25;            // finite-difference step in metres (~ a tessellated edge)
      float e = MS_M * huv_per_m;         // ...expressed in huv units
      float hu1 = textureLod(tex_PBR_H, huv + vec2(e, 0.0), 0.0).r;
      float hu0 = textureLod(tex_PBR_H, huv - vec2(e, 0.0), 0.0).r;
      float hv1 = textureLod(tex_PBR_H, huv + vec2(0.0, e), 0.0).r;
      float hv0 = textureLod(tex_PBR_H, huv - vec2(0.0, e), 0.0).r;
      // slope = (height units per metre) * (game units of displacement per height unit) / 4096,
      // i.e. dimensionless rise-over-run in the surface's own tangent plane.
      float k = amp * (1.0 / (2.0 * MS_M * 4096.0));
      float su = (hu1 - hu0) * k;
      float sv = (hv1 - hv0) * k;
      vec3 Tu = hax_u - N * dot(N, hax_u);
      vec3 Tv = hax_v - N * dot(N, hax_v);
      float lu = length(Tu);
      float lv = length(Tv);
      if (lu > 1e-5 && lv > 1e-5) {
        N = normalize(N - (Tu / lu) * su - (Tv / lv) * sv);
      }
    }
  }
#endif

  // ---- tfrag3.vert's EXACT camera transform (world -> clip) ----
  vec3 vert = world - cam_trans.xyz;
  v_fringe_rel = vert * (1.0 / 4096.0);
  v_world = world;
  v_normal = N;
  // REOPEN#7: barycentric-interpolate the tangent xyz; take vertex-0 handedness (uniform within a
  // patch) to avoid interpolating the +/-1 sign. tfrag3.frag re-orthonormalizes against v_normal.
  v_tangent = vec4(bary3(tc_tangent[0].xyz, tc_tangent[1].xyz, tc_tangent[2].xyz), tc_tangent[0].w);
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
