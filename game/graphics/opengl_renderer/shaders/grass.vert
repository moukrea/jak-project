#version 410 core

// Grecharged-grass-poc: procedural 3D grass for the TRAINING level (jak1).
// One instanced draw stream, two passes selected by u_mode:
//   u_mode == 0  NEAR blades  (GL_TRIANGLE_STRIP, 10 verts, curved tapered blade)
//   u_mode == 1  MID   cards  (GL_TRIANGLES,      12 verts, X-cross of two quads)
// Geometry is generated from gl_VertexID; only per-instance data comes from the VBO.
// World->clip transform is copied verbatim from collision.vert so grass lands on the
// exact same screen pixels as the scene it sits on. Flat color (no texture) per the PoC.

// per-instance data (glVertexAttribDivisor == 1)
layout (location = 0) in vec4 inst_pos;   // xyz = world base position (GOAL units, 4096 = 1 m), w = blade height
layout (location = 1) in vec4 inst_par;   // x = yaw(rad), y = tint(0..1), z = curve(0..1), w = breeze phase(0..1)

// scene camera (same uniforms/semantics as collision.vert)
uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform vec4 camera_position;
uniform float fog_constant;

// grass controls
uniform float u_time;      // seconds, drives the breeze
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform int   u_mode;      // 0 = blade pass, 1 = card pass

out vec3 v_color;
out float v_alpha;
out vec2 v_uv;            // card-local coords: x in [-1,1] across width, y in [0,1] up
flat out int v_is_card;   // 0 = near blade, 1 = mid card (frag cuts the card into a tuft)
out float v_seed;         // per-instance random, seeds the card tuft sub-blades

const int   SEGMENTS = 4;            // blade strip segments -> 2*(SEGMENTS+1) = 10 verts
const float TWO_PI   = 6.28318530718;

// LOD distance bands, world units (4096 = 1 m).
// OWNER POLISH 2026-07-10: pushed OUT so the player stands INSIDE the real 3D
// blades (was 10->18 m; Jak ended up in the cards). Blades now hold to 18 m and
// fade to 28 m; cards only take over from 22 m out.
const float B_FULL  = 18.0 * 4096.0; // blades fully opaque within this radius
const float B_END   = 28.0 * 4096.0; // blades fully faded out beyond this
const float C_IN0   = 22.0 * 4096.0; // cards start fading in
const float C_IN1   = 32.0 * 4096.0; // cards fully in
const float C_OUT0  = 46.0 * 4096.0; // cards start fading out
const float C_OUT1  = 62.0 * 4096.0; // cards gone

const float TRAMPLE_R = 2.2 * 4096.0; // grass flattens within this radius of Jak

// X-cross card corners (two triangles per quad), (u = width -1..1, v = height 0..1)
const vec2 CARD[6] = vec2[6](
  vec2(-1.0, 0.0), vec2(1.0, 0.0), vec2(-1.0, 1.0),
  vec2(-1.0, 1.0), vec2(1.0, 0.0), vec2( 1.0, 1.0));

vec4 world_to_clip(vec3 pos) {
  vec4 transformed = -camera[3].xyzw;
  transformed += -camera[0] * pos.x;
  transformed += -camera[1] * pos.y;
  transformed += -camera[2] * pos.z;
  float Q = fog_constant / transformed[3];
  transformed.xyz *= Q;
  transformed.xyz += hvdf_offset.xyz;
  transformed.xy -= (2048.);
  transformed.z /= (8388608.0);
  transformed.z -= 1.0;
  transformed.x /= (256.0);
  transformed.y /= -(128.0);
  transformed.xyz *= transformed.w;
  vec4 p = transformed;
  p.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  return p;
}

void main() {
  vec3 base = inst_pos.xyz;
  float H = inst_pos.w;
  float yaw = inst_par.x;
  float tint = inst_par.y;
  float curve = inst_par.z;
  float phase = inst_par.w;

  float c = cos(yaw);
  float s = sin(yaw);
  vec3 rightv = vec3(c, 0.0, -s);   // width axis
  vec3 fwdv   = vec3(s, 0.0,  c);   // bend/curve axis

  // --- LOD fade (per-instance, from camera distance to the blade base) ---
  float cam_dist = distance(base, camera_position.xyz);
  float alpha;
  if (u_mode == 0) {
    alpha = 1.0 - smoothstep(B_FULL, B_END, cam_dist);
  } else {
    alpha = smoothstep(C_IN0, C_IN1, cam_dist) * (1.0 - smoothstep(C_OUT0, C_OUT1, cam_dist));
  }
  if (alpha <= 0.004) {
    // fully culled by LOD: collapse offscreen so no fragments are shaded
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    v_color = vec3(0.0);
    v_alpha = 0.0;
    v_uv = vec2(0.0);
    v_is_card = u_mode;
    v_seed = 0.0;
    return;
  }

  // shared breeze: a gust travelling across the field (spatial phase) plus a
  // per-instance offset, so the whole lawn reads as ONE wind but no two blades
  // move in lockstep.
  float gust = u_time * 1.7 + phase * TWO_PI + (base.x + base.z) * 0.00035;

  // --- trample: flatten + push away from Jak within TRAMPLE_R ---
  float heightMul = 1.0;
  vec3 trample = vec3(0.0);
  if (u_jak_pos.w > 0.5) {
    vec2 d = base.xz - u_jak_pos.xz;
    float dist = length(d);
    if (dist < TRAMPLE_R) {
      float k = 1.0 - dist / TRAMPLE_R;            // 0 at edge -> 1 at Jak
      vec2 away = dist > 1.0 ? d / dist : vec2(0.0, 1.0);
      trample = vec3(away.x, 0.0, away.y) * (k * k) * H * 1.3;
      heightMul = 1.0 - k * 0.8;                   // press the blade down
    }
  }

  vec3 pos;
  float t_col;
  if (u_mode == 0) {
    // ---------- NEAR: curved, tapered blade ----------
    int seg = gl_VertexID / 2;
    int side = gl_VertexID - seg * 2;              // 0 or 1
    float t = float(seg) / float(SEGMENTS);        // 0 base -> 1 tip
    // OWNER POLISH: wider, fuller blades (was 0.062/0.82) so the SAME instance
    // count reads as a denser, lusher lawn — more ground coverage per blade.
    float hw = H * 0.078 * (1.0 - 0.70 * t);       // half width, tapering to the tip

    // breeze: shared gust, grows toward the tip
    float sway = sin(gust) * t * t;
    float bend = curve * t * t;                    // static curvature
    float fwd_amt = (bend + sway * 0.38) * H;

    pos = base
        + rightv * ((float(side) * 2.0 - 1.0) * hw)
        + vec3(0.0, t * H * heightMul, 0.0)
        + fwdv * fwd_amt
        + trample * t;
    t_col = t;
    v_uv = vec2(0.0);
    v_is_card = 0;
  } else {
    // ---------- MID: X-cross grass card ----------
    int quad = gl_VertexID / 6;                    // 0 or 1
    int li = gl_VertexID - quad * 6;
    vec2 uv = CARD[li];
    vec3 axis = (quad == 0) ? rightv : fwdv;       // two crossed quads
    float cardH = H * 1.25;                          // match near heights, a touch taller
    float cardHW = H * 0.46;                          // clump width

    // card wind sway: SAME gust as the blades but gentler and lower frequency,
    // growing toward the top (owner polish: cards were static rectangles).
    float csway = sin(gust * 0.7) * uv.y * uv.y;

    pos = base
        + axis * (uv.x * cardHW)
        + vec3(0.0, uv.y * cardH * heightMul, 0.0)
        + fwdv * (csway * H * 0.30)
        + rightv * (csway * H * 0.10)
        + trample * uv.y;
    t_col = uv.y;
    v_uv = uv;
    v_is_card = 1;
  }

  // --- flat color: vertical gradient (dark base -> bright tip) + per-blade tint ---
  // OWNER POLISH: more tint variation (wider brightness + a hue jitter so some
  // blades are warmer / cooler green).
  float tint2 = fract(tint * 7.919 + 0.371);       // decorrelated secondary random
  vec3 base_dark  = vec3(0.075, 0.185, 0.040);
  vec3 base_light = vec3(0.40, 0.66, 0.20);
  vec3 col = mix(base_dark, base_light, t_col);
  col *= (0.62 + 0.72 * tint);      // wider brightness variation per blade
  float hue = tint2 - 0.5;          // -0.5 .. 0.5
  col.r *= (1.0 + 0.50 * hue);      // warmer <-> cooler green
  col.b *= (1.0 - 0.35 * hue);
  col.g *= (0.88 + 0.22 * tint);
  v_color = col;
  v_alpha = alpha;
  v_seed = tint * 331.0 + phase * 71.0;   // per-instance tuft seed

  gl_Position = world_to_clip(pos);
}
