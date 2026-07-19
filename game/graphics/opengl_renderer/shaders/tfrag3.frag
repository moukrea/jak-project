#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
uniform vec4 fog_color;

uniform int gfx_hack_no_tex;

// Grecharged-grass-overhang2: near-fade of the painted grass-fringe alpha strips while the recharged
// 3D droop covers them (owner: the texture showed through the blades). x = enable (set per-draw for
// the two fringe textures only), y/z = fade start/end in METERS. 0 (default) = stock path.
uniform vec4 u_fringe_fade;

#ifdef OG_PBR
uniform int u_pbr_mode;        // 0=legacy; bit1 normal, bit2 rough, bit4 metal, bit8 ao, bit16 height/POM
uniform vec3 u_pbr_sun_dir;    // world-space, surface->sun, normalized (viz/legacy)
uniform vec3 u_pbr_sun_color;
// Round-4 multi-light: 3 direct lights from light-group 0 (soleil + lune verte + fill),
// surface->light dirs + rgb colors. Each color is pre-weighted by its levels.x morph
// weight in C++ so dir0+dir1 sum ~1 across hour transitions (energy conserved).
uniform vec3 u_pbr_light_dir[3];
uniform vec3 u_pbr_light_color[3];
uniform vec3 u_pbr_ambient;
uniform float u_pbr_exposure;
// Owner mandate 2026-07-18: relief must be unmistakable. Normal-map x/y perturbation
// multiplier (>1 deepens), POM depth in native-UV units (0 disables the march even when
// a height map is bound), extra UV tiling on the PBR path only (1.0 = native density).
uniform float u_pbr_normal_strength;
uniform float u_pbr_height_scale;
uniform float u_pbr_uv_tile;
// Owner round-3 mandate 2026-07-18: lighting split calibration. u_pbr_direct scales the
// realtime direct DIFFUSE (the baked vertex color already contains the baked sun's
// diffuse — this is the double-dose control); u_pbr_indirect scales the baked-GI
// indirect term. Specular is deliberately NOT scaled by u_pbr_direct: baked carries no
// specular, and the moving highlight is the realtime tell.
uniform float u_pbr_direct;
uniform float u_pbr_indirect;
// Round-4bis mandate E (owner: "si notre vrai lighting realtime marche vraiment, on n'a
// plus besoin du baked quand activé"): 1.0 = round-3 hybrid (indirect = baked vertex GI),
// 0.0 = FULL REALTIME (indirect = light-group ambient * AO; baked term gone). At low
// weight the u_pbr_direct double-dose damping also fades back to 1.0 — it exists only
// because the baked term carries the baked sun, which is no longer added at w=0.
uniform float u_pbr_baked_weight;
// Per-channel isolation viz on the PBR draws only (legacy neighbours untouched, so the
// patch outline shows in every mode). 0=off, 1=albedo passthrough (what a plain
// photo-swap would look like; POM still offsets it, so this is also the cleanest
// parallax viz), 2=geometric normal, 3=final shading normal (shows the normal map's
// perturbation vs 2), 4=roughness, 5=accumulated specular term (all lights), 6=AO,
// 7=full PBR with the normal map DISABLED (the N on/off A/B pair with 0),
// 8=full PBR with POM DISABLED (the POM on/off A/B pair with 0), 9=height map,
// 10=indirect/baked-GI term only (the round-3 macro-shading reintegration viz),
// 11=direct term only (accumulated diffuse+spec of ALL lights — round-4 multi-light),
// 12=sun shadow-map factor (round-4 mandate B; white=lit, black=shadowed),
// 13=direct contribution of lights 1+2 ONLY (moon/fill isolation, skips the sun).
uniform int u_pbr_debug;
uniform sampler2D tex_PBR_N;
uniform sampler2D tex_PBR_R;
uniform sampler2D tex_PBR_M;
uniform sampler2D tex_PBR_AO;
uniform sampler2D tex_PBR_H;
// Round-4 mandate B: classic sun SHADOW MAPPING. u_pbr_shadow_mvp maps camera-relative
// meters (== v_fringe_rel) to the light's clip space; tex_PBR_SHADOW is the depth-only sun
// map on unit 9, sampled as a HW-PCF compare sampler (LEQUAL). u_pbr_shadow_on gates it.
uniform mat4 u_pbr_shadow_mvp;
uniform int u_pbr_shadow_on;
// Round-5 suspect (d): the read-side map is anchored to the camera position of the frame
// that WROTE it (camera-relative space), but v_fringe_rel uses the CURRENT camera —
// without correction every shadow trails camera motion by one frame (continuous
// displacement during the owner's orbit repro). cam_delta = (cam_now - cam_at_write)/4096.
uniform vec3 u_pbr_shadow_cam_delta;
// Plain sampler2D + manual in-shader compare: the Adreno 618 HW compare path
// (sampler2DShadow + COMPARE_REF_TO_TEXTURE) returns a constant 1.0 on-device
// (proven with a 0.25-cleared map). Depth-as-float sampling is portable.
uniform highp sampler2D tex_PBR_SHADOW;
// Owner clarification 2026-07-18 (WORLD shadows): legacy (non-PBR) fragments in this
// program also receive the sun shadow as a calibrated darkening, so the hut's shadow
// lands on the non-PBR ground. 0 disables; ~0.35 default, prop-tunable so already-baked
// painted shadows don't double-darken into black.
uniform float u_pbr_legacy_shadow;
// Debug-only bias override added to the compare ref (prop debug.opengoal.pbr.shadowbias /
// OG_PBR_SHADOWBIAS, default 0.0 = no effect). +0.5 must black out every in-box receiver
// if the HW depth compare works — the Adreno-driver binary test.
uniform float u_pbr_shadow_bias;
// Round-5 addendum 2, MANDATE F ("light the world like Jak"): world-wide mood-light
// shading for LEGACY (non-PBR-mapped) world fragments. Direct term = per-face geometric
// normal (screen-derivative — camera-independent for planar level tris, so it CANNOT swim
// with the camera) dotted with the light-group lights (sun + fill + moon), times the sun
// shadow factor; indirect stays the baked vertex color. u_pbr_world_relight blends the
// whole effect (0 = old flat legacy darkening path); wr_direct/wr_indirect are the
// anti-double-brightening calibration (the baked color already contains the baked sun).
uniform float u_pbr_world_relight;
uniform float u_pbr_wr_direct;
uniform float u_pbr_wr_indirect;
// Grecharged-realtime-lighting (2026-07-19 REWRITE): a clean SUN-ONLY path that
// REPLACES the round-1..5 accretion (ambient / multi-light / moon / baked-GI /
// baked-weight) when it is ON. u_rt_light_on = master (1 => this path taken,
// every round-1..5 branch below skipped). u_rt_use_baked = sub-option (0 =>
// baked vertex lighting OFF, the dev/default state; 1 => fold baked macro shading
// back in). u_rt_sun_dir = surface->sun, world space, == the vector that places
// the VISIBLE sun sprite (sky-sun dome dir). u_rt_sun_color carries the sun tint
// AND intensity. ONE light, NO ambient — the opposite side is genuinely dark.
uniform int u_rt_light_on;
uniform int u_rt_use_baked;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_sun_color;
#endif


void main() {
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
#ifdef OG_PBR
    // Round-4 mandate B: sun shadow-map factor, shared by the PBR direct term AND the
    // legacy receiver darkening below. Sample position is v_fringe_rel (camera-relative
    // meters), the SAME space the depth pass rendered in. 4 taps, each HW-PCF'd by the
    // LINEAR compare sampler => ~4x4 effective. Slope-scaled bias from the derivative
    // face normal. Fades out toward the 80m ortho box edge so the coverage boundary
    // doesn't show as a hard shadow cutoff.
    float sm_shadow = 1.0;
    vec3 sm_dbg_suv = vec3(-1.0);  // viz mode 14: shadow-space UV + in-box flag
    float sm_dbg_inbox = 0.0;
    if (u_pbr_shadow_on != 0) {
      vec4 sp = u_pbr_shadow_mvp * vec4(v_fringe_rel + u_pbr_shadow_cam_delta, 1.0);
      vec3 suv = sp.xyz / sp.w * 0.5 + 0.5;
      sm_dbg_suv = suv;
      if (suv.x > 0.002 && suv.x < 0.998 && suv.y > 0.002 && suv.y < 0.998 && suv.z < 1.0) {
        sm_dbg_inbox = 1.0;
        vec3 sng = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
        float sngl = length(sng);
        float ndl0 = sngl > 1e-6 ? abs(dot(sng / sngl, u_pbr_light_dir[0])) : 1.0;
        // Grecharged-realtime-lighting: the SUN-ONLY path renders with baked lighting OFF
        // (no ambient), so shadow-map self-shadow ACNE is unmasked — the pbr-materials path's
        // baked indirect term hides it. Use a larger depth+slope bias on the sun-only path
        // (device-tuned at the sage-wall h16 grazing-deck vantage: ~0.03 total kills the
        // acne with no visible peter-panning). The pbr-materials path (u_rt_light_on == 0)
        // keeps its original small bias byte-for-byte.
        float bias = u_rt_light_on != 0 ? max(0.03 * (1.0 - ndl0), 0.025)
                                        : max(0.0035 * (1.0 - ndl0), 0.0012);
        // u_pbr_shadow_bias: debug override (prop ...pbr.shadowbias); +0.5 forces every
        // in-box fragment SHADOWED — a binary compare-path test.
        float ref = suv.z - bias + u_pbr_shadow_bias;
        float texel = 1.0 / 1024.0;
        // Manual 4-tap PCF: each tap samples the raw depth and compares in-shader
        // (see the sampler declaration above for why not HW sampler2DShadow).
        sm_shadow  = ref <= texture(tex_PBR_SHADOW, suv.xy + vec2(-0.5, -0.5) * texel).r ? 1.0 : 0.0;
        sm_shadow += ref <= texture(tex_PBR_SHADOW, suv.xy + vec2( 0.5, -0.5) * texel).r ? 1.0 : 0.0;
        sm_shadow += ref <= texture(tex_PBR_SHADOW, suv.xy + vec2(-0.5,  0.5) * texel).r ? 1.0 : 0.0;
        sm_shadow += ref <= texture(tex_PBR_SHADOW, suv.xy + vec2( 0.5,  0.5) * texel).r ? 1.0 : 0.0;
        sm_shadow *= 0.25;
        float edge_fade = 1.0 - smoothstep(30.0, 39.0, length(v_fringe_rel));
        sm_shadow = mix(1.0, sm_shadow, edge_fade);
      }
    }
    // ===================================================================
    // Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY path.
    // When ON this REPLACES every round-1..5 branch below. ONE light = the
    // visible sun; per-face N.L; NO ambient; baked OFF by default. The whole
    // point: sun-side lit / opposite side genuinely dark, pinned to world
    // geometry under any camera orbit.
    // ===================================================================
    if (u_rt_light_on != 0) {
      // Per-face WORLD normal. v_fringe_rel is the camera-TRANSLATED (not
      // rotated) world position, so its screen-space derivatives give a
      // camera-INDEPENDENT world-space face normal — the lit/dark terminator
      // is pinned to geometry and cannot swim as the camera orbits.
      vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
      float gNl = length(gN);
      vec3 N = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
      vec3 Vv = -normalize(v_fringe_rel);
      if (dot(N, Vv) < 0.0) N = -N;              // double-sided level tris
      // The sun: surface->sun, world space, == the vector that places the
      // visible sun sprite (sky-sun dome dir when above the horizon).
      vec3 L = normalize(u_rt_sun_dir);
      float ndl = max(dot(N, L), 0.0);           // opposite side -> 0 = dark
      // Stage 2: cast-shadow factor from the sun depth map (1.0 when the map
      // is off). NO ambient anywhere, so a cast shadow / dark side is 0 = dark.
      float shadow = u_pbr_shadow_on != 0 ? sm_shadow : 1.0;
      vec3 albedo = pow(T0.rgb, vec3(2.2));
      // baked OFF (dev/default): ignore the baked vertex TOD color entirely so
      // the surface is lit PURELY by the sun. baked ON (sub-option): fold the
      // baked macro shading back in as a multiplier.
      vec3 baked = u_rt_use_baked != 0 ? pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2)) : vec3(1.0);
      vec3 lit = albedo * baked * u_rt_sun_color * (ndl * shadow);
      color.rgb = pow(max(lit, vec3(0.0)), vec3(1.0 / 2.2));
      // Debug viz (shared prop u_pbr_debug): 1=N.L factor, 2=world normal,
      // 12=shadow factor.
      if (u_pbr_debug == 1) {
        color.rgb = vec3(ndl);
      } else if (u_pbr_debug == 2) {
        color.rgb = N * 0.5 + 0.5;
      } else if (u_pbr_debug == 12) {
        color.rgb = vec3(shadow);
      }
    } else if (u_pbr_mode != 0 && gfx_hack_no_tex == 0) {
      // Grecharged-pbr-materials: Cook-Torrance GGX lit by the mood/TOD sun.
      // Owner round-3 mandate: the baked per-vertex TOD color (fragment_color.rgb) is
      // reintegrated as the INDIRECT/GI term — it carries the level's MACRO shading
      // (building curvature, under-roof darkening, doorway occlusion) that a constant
      // ambient flattened. It is NOT a second direct dose: the realtime direct diffuse
      // is scaled down by u_pbr_direct to compensate for the baked sun it contains.
      // Alpha keeps the legacy product for discard.
      vec3 p = v_fringe_rel;
      vec3 dp1 = dFdx(p);
      vec3 dp2 = dFdy(p);
      vec3 V = -normalize(p);
      vec3 Ngeo = normalize(cross(dp1, dp2));
      if (dot(Ngeo, V) < 0.0) Ngeo = -Ngeo;
      // cotangent frame from screen-space derivatives (no vertex tangents in tfrag
      // data) — shared by POM (tangent-space view) and normal mapping.
      vec2 duv1 = dFdx(tex_coord.xy);
      vec2 duv2 = dFdy(tex_coord.xy);
      vec3 dp2perp = cross(dp2, Ngeo);
      vec3 dp1perp = cross(Ngeo, dp1);
      vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
      vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
      float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-10));
      vec3 Tn = T * invmax;
      vec3 Bn = B * invmax;
      vec2 uv = tex_coord.xy * u_pbr_uv_tile;
      if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0) {
        // Parallax occlusion mapping, mobile-tuned: grazing-angle-scaled linear march
        // with early-out + one secant refine. Height convention: 1.0 (white) = surface
        // level, lower = carved in — so a neutral white map yields zero offset and the
        // march depth is (1 - height). textureLod avoids undefined derivatives in the
        // loop; the offsets are small so mip 0 is acceptable at PoC distances.
        vec3 Vt = normalize(vec3(dot(V, Tn), dot(V, Bn), max(dot(V, Ngeo), 0.0)));
        float vz = max(Vt.z, 0.12);  // cap the grazing blow-up (offset <= ~8x scale)
        float n_layers = mix(28.0, 10.0, clamp(Vt.z, 0.0, 1.0));
        vec2 duv_step = (Vt.xy / vz) * u_pbr_height_scale * u_pbr_uv_tile / n_layers;
        float layer_d = 1.0 / n_layers;
        float cur_d = 0.0;
        float map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
        float prev_map_d = map_d;
        for (int i = 0; i < 32; i++) {
          if (cur_d >= map_d || float(i) >= n_layers) {
            break;
          }
          uv -= duv_step;
          prev_map_d = map_d;
          map_d = 1.0 - textureLod(tex_PBR_H, uv, 0.0).r;
          cur_d += layer_d;
        }
        // secant refine between the last two samples for a smooth intersection
        float after = map_d - cur_d;
        float before = prev_map_d - (cur_d - layer_d);
        float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
        uv += duv_step * (1.0 - w);
      }
      vec3 N = Ngeo;
      if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7) {
        vec3 nm = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
        nm.xy *= u_pbr_normal_strength;
        nm = normalize(nm);
        N = normalize(mat3(Tn, Bn, Ngeo) * nm);
        if (dot(N, Ngeo) < 0.0) N = Ngeo;
      }
      // Albedo re-sampled at the (possibly POM-offset, tiled) UV; the initial T0
      // sample keeps supplying alpha for the legacy discard product below.
      vec4 T0p = texture(tex_T0, uv);
      vec3 albedo = pow(T0p.rgb, vec3(2.2));
      float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.7;
      float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
      float ao    = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
      float NdV = max(dot(N, V), 1e-4);
      float a = max(rough * rough, 0.002);
      float a2 = a * a;
      float k = (rough + 1.0) * (rough + 1.0) / 8.0;
      vec3 F0 = mix(vec3(0.04), albedo, metal);
      // Round-4 mandate B: the shared sun shadow-map factor computed above.
      float shadow = sm_shadow;
      // Round-4bis mandate E: baked weight. The u_pbr_direct diffuse damping is the
      // double-dose control against the baked sun; as the baked term fades out the
      // realtime sun must carry the full diffuse load again.
      float bakedw = clamp(u_pbr_baked_weight, 0.0, 1.0);
      float direct_diff_scale = mix(1.0, u_pbr_direct, bakedw);
      // Round-4 multi-light accumulation: sum the Cook-Torrance direct response of every
      // non-black light in light-group 0 (soleil + lune verte + fill). D/G/F math is
      // identical to the old single-sun path; kd/F depend on VdH so they're per-light.
      vec3 direct = vec3(0.0);
      vec3 spec_sum = vec3(0.0);   // for viz mode 5 (accumulated spec)
      vec3 direct12 = vec3(0.0);   // for viz mode 13 (lights 1+2 only = moon/fill isolation)
      for (int i = 0; i < 3; i++) {
        vec3 lc = u_pbr_light_color[i];
        if (dot(lc, vec3(1.0)) <= 1e-5) {
          continue;  // black / disabled light
        }
        vec3 L = u_pbr_light_dir[i];
        vec3 H = normalize(L + V);
        float NdL = max(dot(N, L), 0.0);
        float NdH = max(dot(N, H), 0.0);
        float VdH = max(dot(V, H), 0.0);
        float dd = NdH * NdH * (a2 - 1.0) + 1.0;
        float D = a2 / (3.14159265 * dd * dd);
        float G = (NdV / (NdV * (1.0 - k) + k)) * (NdL / (NdL * (1.0 - k) + k));
        vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdH, 5.0);
        vec3 spec = D * G * F / max(4.0 * NdV * NdL, 1e-4);
        vec3 kd = (vec3(1.0) - F) * (1.0 - metal);
        vec3 contrib = (kd * albedo / 3.14159265 * direct_diff_scale + spec) * lc * NdL;
        direct += contrib;
        spec_sum += spec * lc * NdL;
        if (i > 0) {
          direct12 += contrib;
        }
      }
      // Round-4 mandate B: shadow the ENTIRE direct term (diffuse + spec of all lights).
      // Under a roof there is no direct light at all; the indirect/baked-GI term is
      // deliberately NOT shadowed (baked already carries the level's macro occlusion).
      direct *= shadow;
      spec_sum *= shadow;
      direct12 *= shadow;
      // Indirect = baked vertex TOD color as GI. pow 2.2 linearizes it so a fragment in
      // full baked shadow (no direct term) reproduces the legacy sRGB product
      // fragment_color * T0 by construction — the macro luminance profile of the
      // building matches OFF wherever the sun doesn't add on top. The baked color is
      // TOD-palette-interpolated per frame, so this term still tracks the day cycle.
      vec3 baked_gi = pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2));
      // Round-4bis mandate E: blend the hybrid baked-GI indirect toward the FULL-REALTIME
      // indirect (light-group ambient * AO) as bakedw -> 0. At w=0 the baked vertex color
      // no longer influences the PBR surface at all: sun+moon+fill direct is shadow-mapped
      // realtime, ambient comes from the level light-group, occlusion from the AO map.
      vec3 indirect_baked = albedo * baked_gi * ao * u_pbr_indirect;
      vec3 indirect_rt = albedo * u_pbr_ambient * ao;
      vec3 indirect = mix(indirect_rt, indirect_baked, bakedw);
      vec3 lit = direct + indirect;
      color.rgb = pow(max(lit * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      if (u_pbr_debug == 1) {
        color.rgb = T0p.rgb;
      } else if (u_pbr_debug == 2) {
        color.rgb = Ngeo * 0.5 + 0.5;
      } else if (u_pbr_debug == 3) {
        color.rgb = N * 0.5 + 0.5;
      } else if (u_pbr_debug == 4) {
        color.rgb = vec3(rough);
      } else if (u_pbr_debug == 5) {
        color.rgb = pow(max(spec_sum * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 6) {
        color.rgb = vec3(ao);
      } else if (u_pbr_debug == 9) {
        color.rgb = vec3(texture(tex_PBR_H, uv).r);
      } else if (u_pbr_debug == 10) {
        color.rgb = pow(max(indirect * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 11) {
        color.rgb = pow(max(direct * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 12) {
        // Round-4 mandate B: sun shadow factor viz (1=lit, 0=shadowed).
        color.rgb = vec3(shadow);
      } else if (u_pbr_debug == 13) {
        // Round-4: direct contribution of lights 1+2 ONLY (moon/fill isolation viz).
        color.rgb = pow(max(direct12 * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
      } else if (u_pbr_debug == 14) {
        // Shadow-space debug: R/G = shadow-map UV, B = in-box flag.
        color.rgb = vec3(fract(sm_dbg_suv.x), fract(sm_dbg_suv.y), sm_dbg_inbox);
      } else if (u_pbr_debug == 15) {
        // Shadow-space depth debug: gray = suv.z (light-space depth of this fragment).
        color.rgb = vec3(clamp(sm_dbg_suv.z, 0.0, 1.0));
      } else if (u_pbr_debug == 16) {
        // Raw map depth the receiver reads at this fragment's shadow UV.
        color.rgb = vec3(texture(tex_PBR_SHADOW, clamp(sm_dbg_suv.xy, 0.0, 1.0)).r);
      }
    } else if (u_pbr_shadow_on != 0) {
      // Owner clarification 2026-07-18: LEGACY receivers. The non-PBR world (the ground
      // under the hut) darkens by the calibrated legacy strength where the sun map says
      // shadowed — this is what makes the hut's shadow visible outside the PBR patch.
      // The baked painted shadows survive: a fully-baked-dark texel just gets the same
      // fractional multiply, and strength is tuned so that never crushes to black.
      color.rgb *= 1.0 - u_pbr_legacy_shadow * (1.0 - sm_shadow);
      if (u_pbr_world_relight > 0.0) {
        // MANDATE F (round-5 addendum 2): per-face N.L mood-light relight of the legacy
        // world — the same directional response actors get from the light-group, attached
        // to the geometry (stable under camera orbit by construction). In full shadow /
        // facing away, wr_indirect * baked reproduces (a calibrated fraction of) the
        // legacy product in linear space — the same round-3 trick the PBR indirect uses.
        vec3 wrn = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
        float wrl = length(wrn);
        vec3 wrN = wrl > 1e-6 ? wrn / wrl : vec3(0.0, 1.0, 0.0);
        vec3 wrV = -normalize(v_fringe_rel);
        if (dot(wrN, wrV) < 0.0) wrN = -wrN;
        vec3 wr_direct = vec3(0.0);
        for (int i = 0; i < 3; i++) {
          wr_direct += u_pbr_light_color[i] * max(dot(wrN, u_pbr_light_dir[i]), 0.0);
        }
        wr_direct *= sm_shadow * u_pbr_wr_direct;
        vec3 wr_alb = pow(T0.rgb, vec3(2.2));
        vec3 wr_baked = pow(max(fragment_color.rgb, vec3(0.0)), vec3(2.2));
        vec3 wr_lit = wr_alb * (wr_baked * u_pbr_wr_indirect + wr_direct);
        vec3 wr_srgb = pow(max(wr_lit * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
        color.rgb = mix(color.rgb, wr_srgb, clamp(u_pbr_world_relight, 0.0, 1.0));
        if (u_pbr_debug == 17) {
          // Viz: world-relight DIRECT term only (face contrast must follow the sun).
          color.rgb = pow(max(wr_direct * u_pbr_exposure, vec3(0.0)), vec3(1.0 / 2.2));
        }
      }
      if (u_pbr_debug == 12) {
        color.rgb = vec3(sm_shadow);
      } else if (u_pbr_debug == 14) {
        color.rgb = vec3(fract(sm_dbg_suv.x), fract(sm_dbg_suv.y), sm_dbg_inbox);
      } else if (u_pbr_debug == 15) {
        color.rgb = vec3(clamp(sm_dbg_suv.z, 0.0, 1.0));
      } else if (u_pbr_debug == 16) {
        color.rgb = vec3(texture(tex_PBR_SHADOW, clamp(sm_dbg_suv.xy, 0.0, 1.0)).r);
      }
    }
#endif
  } else {
    color = fragment_color/2.0;
  }

  if (u_fringe_fade.x > 0.5) {
    // Grecharged-grass-overhang2 (owner defect 1): fade the painted fringe ALPHA out near the camera
    // so the 3D droop REPLACES it instead of poking through it; far keeps the stock strip, crossfaded
    // over the SAME band the droop blades fade out in. STEEPNESS-gated via screen-space derivatives
    // (level tris are planar, so this is the exact face normal): only the steep hang faces fade —
    // flat walkable ground sharing the texture keeps its stock texels. The scan's fringe/walkable
    // split is upness 0.35 (GrassBakeCore GROUND_UPNESS); the 0.30..0.40 smooth edge straddles it.
    vec3 fdx = dFdx(v_fringe_rel);
    vec3 fdy = dFdy(v_fringe_rel);
    vec3 fnrm = cross(fdx, fdy);
    float fl = length(fnrm);
    float upness = fl > 1e-6 ? abs(fnrm.y) / fl : 1.0;
    float steep_w = 1.0 - smoothstep(0.30, 0.40, upness);
    float dist_f = smoothstep(u_fringe_fade.y, u_fringe_fade.z, length(v_fringe_rel));
    // Grecharged-grass-overhang7 ROUND 10 forensics (u_fringe_fade.w, prop
    // debug.opengoal.grass.fringe_dbg; 0 = stock): mode 2 paints the gate state instead of fading
    // (magenta = steep/would-fade, cyan = gate-blocked flat-ish) so one close capture names WHY a
    // painted tuft survived the near-fade; mode 1 ignores the steepness gate entirely (A/B).
    if (u_fringe_fade.w > 1.5) {
      color.rgb = mix(color.rgb, mix(vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), steep_w), 0.8);
    } else {
      if (u_fringe_fade.w > 0.5) {
        steep_w = 1.0;
      }
      color.a *= mix(1.0, dist_f, steep_w);
    }
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}
