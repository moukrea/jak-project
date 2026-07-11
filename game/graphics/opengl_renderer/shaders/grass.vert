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
layout (location = 2) in vec4 inst_gcol;  // POLISH#4: xyz = avg colour of the ground texture under this blade (0..1)
layout (location = 3) in vec4 inst_light; // POLISH#9: rgb = ground's DYNAMIC baked light under this blade (0..1; *2 = ground factor)

// scene camera (same uniforms/semantics as collision.vert)
uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform vec4 camera_position;
uniform float fog_constant;

// grass controls
uniform float u_time;      // seconds, drives the breeze
uniform vec4  u_jak_pos;   // xyz = Jak world pos, w = 1 when valid (trample origin)
uniform int   u_mode;      // 0 = blade pass, 1 = card pass
// POLISH#4: adjustable LOD reach (world units) from the two Recharged Settings sliders.
uniform float u_near_dist; // near-blade fade-out radius (world units)
uniform float u_card_dist; // grass-card fade-out radius (world units)
uniform vec4  u_jak_ledge; // xyz = ledge-grab point, w = 1 while Jak hangs (ledge-parting trample)

out vec3 v_color;
out float v_alpha;
out vec2 v_uv;            // card-local coords: x in [-1,1] across width, y in [0,1] up
flat out int v_is_card;   // 0 = near blade, 1 = mid card (frag cuts the card into a tuft)
out float v_seed;         // per-instance random, seeds the card tuft sub-blades

const int   SEGMENTS = 4;            // blade strip segments -> 2*(SEGMENTS+1) = 10 verts
const float TWO_PI   = 6.28318530718;

// LOD distance bands are ADJUSTABLE (POLISH#4): derived from u_near_dist / u_card_dist
// inside main() (uniforms can't initialise globals in GLSL). B_END = u_near_dist (blade
// fade-out), C_OUT1 = u_card_dist (card fade-out, pushed further out); the intermediate
// bands scale off them so the near->card->far crossfade stays seamless at any slider value.

const float TRAMPLE_R = 2.2 * 4096.0; // grass flattens within this radius of Jak
// OWNER POLISH#3: only trample when Jak is near THIS grass's ground height — not
// airborne. vgap = Jak-root-Y minus blade-base-Y; outside this band => no trample.
const float TRAMPLE_Y_LO = -1.5 * 4096.0; // up to 1.5 m below the grass -> still trample
const float TRAMPLE_Y_HI =  2.0 * 4096.0; // more than 2 m above the grass = airborne -> none

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

  // POLISH#4/#6: adjustable LOD bands, derived from the two slider distances (world units).
  // OWNER POLISH#6: a WIDE crossfade OVERLAP so near blades fade out and cards fade in over the
  // SAME band. Combined with the card colour now unified to the blade gradient (t_col below), the
  // two tiers are the same colour through the overlap -> the near->card transition reads seamless
  // (owner: "la transition entre les deux est bizarre").
  float B_FULL = u_near_dist * 0.55;  // blades fully opaque within this radius
  float B_END  = u_near_dist;         // blades fully faded out beyond this
  float C_IN0  = u_near_dist * 0.45;  // cards start fading in WELL before the blades are gone
  float C_IN1  = u_near_dist * 0.85;  // cards fully in (inside the blade fade-out band -> crossfade)
  float C_OUT1 = u_card_dist;         // cards gone (pushed further out)
  float C_OUT0 = u_card_dist * 0.78;  // cards start fading out

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
  // OWNER POLISH#3: gate by Jak's ALTITUDE so the grass only bends when he is on/
  // near the ground, not while airborne (jumping) above it.
  float heightMul = 1.0;
  vec3 trample = vec3(0.0);
  float vgap = u_jak_pos.y - base.y;
  if (u_jak_pos.w > 0.5 && vgap > TRAMPLE_Y_LO && vgap < TRAMPLE_Y_HI) {
    vec2 d = base.xz - u_jak_pos.xz;
    float dist = length(d);
    if (dist < TRAMPLE_R) {
      float k = 1.0 - dist / TRAMPLE_R;            // 0 at edge -> 1 at Jak
      vec2 away = dist > 1.0 ? d / dist : vec2(0.0, 1.0);
      trample = vec3(away.x, 0.0, away.y) * (k * k) * H * 1.3;
      heightMul = 1.0 - k * 0.8;                   // press the blade down
    }
  }

  // OWNER POLISH#4: LEDGE-GRAB parting — while Jak hangs on a ledge with his hands
  // (u_jak_ledge = the grab point, world units), the ledge-top grass parts around his
  // hands just like walk-trample on the ground. Gated by the grab point being near THIS
  // grass's height (NOT Jak's root altitude — he hangs BELOW the ledge, so the walk gate
  // above would never fire for the ledge grass).
  if (u_jak_ledge.w > 0.5) {
    float lgap = abs(u_jak_ledge.y - base.y);
    if (lgap < 1.5 * 4096.0) {
      vec2 dl = base.xz - u_jak_ledge.xz;
      float distl = length(dl);
      if (distl < TRAMPLE_R) {
        float kl = 1.0 - distl / TRAMPLE_R;
        vec2 awayl = distl > 1.0 ? dl / distl : vec2(1.0, 0.0);
        trample += vec3(awayl.x, 0.0, awayl.y) * (kl * kl) * H * 1.3;
        heightMul = min(heightMul, 1.0 - kl * 0.8);
      }
    }
  }

  vec3 pos;
  float t_col;
  if (u_mode == 0) {
    // ---------- NEAR: curved, tapered blade ----------
    int seg = gl_VertexID / 2;
    int side = gl_VertexID - seg * 2;              // 0 or 1
    float t = float(seg) / float(SEGMENTS);        // 0 base -> 1 tip
    // OWNER POLISH#3: wider, fuller blades so the lawn reads DENSER (more ground
    // coverage per blade) on top of the higher instance budget (density++ #1 ask).
    float hw = H * 0.092 * (1.0 - 0.66 * t);       // half width, tapering to the tip

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
    // OWNER POLISH#6: the cards read "trop denses ... beaucoup plus touffue que la vraie herbe".
    // Thin the card field — skip ~30% of card instances by a deterministic per-instance hash (STABLE,
    // so no pop-in) and make each card narrower with fewer sub-blades (frag NB 5->3). The near blades
    // keep the full density, so the cards are now clearly LIGHTER than the foreground grass.
    if (fract(phase * 13.17 + tint * 7.51) > 0.70) {
      gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
      v_color = vec3(0.0);
      v_alpha = 0.0;
      v_uv = vec2(0.0);
      v_is_card = 1;
      v_seed = 0.0;
      return;
    }
    int quad = gl_VertexID / 6;                    // 0 or 1
    int li = gl_VertexID - quad * 6;
    vec2 uv = CARD[li];
    vec3 axis = (quad == 0) ? rightv : fwdv;       // two crossed quads
    float cardH = H * 1.25;                          // match near heights, a touch taller
    float cardHW = H * 0.38;                          // POLISH#6: narrower clump (was 0.46) -> lighter

    // card wind sway: SAME gust as the blades but MUCH GENTLER than the near blades
    // (owner polish#3: cards swayed "beaucoup plus à fond que devant"). Near-blade
    // fwd sway peaks ~0.38*H; cards now peak ~0.12*H — clearly under the foreground.
    float csway = sin(gust * 0.7) * uv.y * uv.y;

    pos = base
        + axis * (uv.x * cardHW)
        + vec3(0.0, uv.y * cardH * heightMul, 0.0)
        + fwdv * (csway * H * 0.12)
        + rightv * (csway * H * 0.04)
        + trample * uv.y;
    // OWNER POLISH#6: use the EXACT same vertical gradient as the near blade (t_col = local
    // height). With the identical tint / ground-harmonisation / baked-light pipeline below applied
    // to both tiers, a card and a blade at the same height are the SAME colour by construction — so
    // the grass no longer "change de couleur quand on avance" and the crossfade band blends cleanly.
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

  // OWNER POLISH#4: sample/match the GROUND TEXTURE colour. inst_gcol.rgb is the average
  // colour of the tfrag/tie ground texture UNDER this blade (computed at placement). Shift
  // the canonical grass-green toward that ground tone and let a little of the literal ground
  // colour bleed in, so the grass never clashes with the texture showing through (a bright
  // green blade over sandy/mossy ground would "faire tâche"). Per-location — grass over
  // tra-grass, tra-beachrock and the beach fringes each takes its own matching green. The
  // CARDS use the same per-instance ground colour, so near->far stays one seamless colour.
  vec3 gcol = inst_gcol.rgb;
  vec3 groundRef = vec3(0.24, 0.34, 0.14);   // a canonical grassy-ground average
  vec3 harmon = col * clamp(gcol / max(groundRef, vec3(0.04)), vec3(0.55), vec3(1.9));
  col = mix(col, harmon, 0.55);              // shift the green toward the ground's tone
  col = mix(col, gcol, 0.16);                // a touch of the literal ground colour blends in

  // OWNER POLISH#7: match the grass LUMINANCE to the ground albedo so blades are not brighter than
  // the ground they grow from (owner: grass "bien plus lumineuse que la texture du sol de partout,
  // même aux endroits les plus éclairés"). Pull the grass brightness toward the ground-texture
  // brightness while keeping some per-blade variation (hue is preserved — only magnitude is scaled).
  float glum  = dot(col,  vec3(0.299, 0.587, 0.114));
  float grlum = dot(gcol, vec3(0.299, 0.587, 0.114));
  if (glum > 0.001) {
    float lm = clamp(grlum / glum, 0.45, 1.15);
    col *= mix(1.0, lm, 0.6);
  }

  // OWNER POLISH#9 (#1 owner priority): apply the GROUND's ACTUAL baked light — per-channel + DYNAMIC.
  // inst_light.rgb is the ground vertex's interpolated baked colour UNDER this blade at the CURRENT
  // time of day (normalized [0,1]; re-uploaded by update_light() as the day/night cycle advances).
  // *2.0 recovers the EXACT factor tfrag/TIE multiply the ground texture by (fragment_color =
  // (palette/255)*2), so the grass darkens/brightens EXACTLY like the ground beneath it — per LOCATION
  // and per TIME OF DAY. Where the baked light darkens the ground the grass darkens with it (owner:
  // grass "fait tâche quand le baked lighting rend le sol plus sombre"). The old build multiplied by a
  // FROZEN, level-MEAN-centred luma (inst_gcol.w) sampled once at load -> it never tracked the ground.
  col *= inst_light.rgb * 2.0;
  col = clamp(col, vec3(0.0), vec3(1.5));

  v_color = col;
  v_alpha = alpha;
  v_seed = tint * 331.0 + phase * 71.0;   // per-instance tuft seed

  gl_Position = world_to_clip(pos);
}
