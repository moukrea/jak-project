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
// (u_pbr_uv_tile is GONE from every map lookup — owner 2026-07-26: the maps must use exactly the
//  base colour's UV, with no separate multiplier anywhere. World scale lives in the amplitude.)
// ROUND 20: THIS material's MEASURED authored UV density, in texture tiles per world metre,
// measured at level load from the level's own geometry (background_common.cpp
// measure_uv_density_tfrag / measure_uv_density_tie). 0.5 = what WORLD_TILES_PER_M assumed.
uniform float u_pbr_uv_per_m;
// ROUND 20 correction: this height MAP's characteristic feature wavelength, in TILES (1 tile = the
// whole texture), measured at load from the map's own mip-energy spectrum. The displacement
// AMPLITUDE follows this, not the tile — a tile is 2.3-7.9 m wide and holds many features.
uniform float u_pbr_height_lambda;
uniform sampler2D tex_PBR_H;       // height map, unit 15 (.r = height, 0.5 = neutral mid)

// REOPEN #3/#6 TESS DISPLACEMENT MAGNITUDE. u_pbr_height_scale is the POM's UV-space depth scale;
// TESS_DISP_K converts that to WORLD (game) units so the geometric displacement is REAL. Because
// this is genuine vertex displacement it can NEVER float like POM does — so tessellation keeps a
// deeper, convincing relief (~5 cm peak-to-trough) even though REOPEN #6 dropped the POM base
// depth 3.5x (0.07 -> 0.02) to surface-lock the parallax. K is bumped 3.5x to compensate and keep
// the real-geometry displacement calibrated: 0.02 (base) * 1.5 (relief) * 14336 * 0.5 ~= 215 game
// units ~= 5.25 cm. 1 game unit = 1/4096 m. Single knob — tune if the relief reads too deep/shallow.
#define TESS_DISP_K 14336.0
// ROUND 20: game units per metre. u_pbr_height_scale is a depth in UV units (tiles), so multiplying
// it by the material's tile size in metres and by this gives the displacement in game units.
#define TESS_DISP_UNITS_PER_M 4096.0
// ROUND 20 correction: depth-per-wavelength constant. A real surface feature of width w is roughly
// w/4 deep, and u_pbr_height_scale is 0.05 * relief, so 5.0 puts the depth at 0.25 * lambda_world
// at relief 1.0.
#define TESS_DEPTH_K 5.0
// ROUND 20 correction, second half: the two PHYSICAL caps on that depth. They matter because the
// measured lambdas span 40x (wallplaster's features are 4.2 cm of world, vil-beach-01's are 167 cm)
// and one of the shipped maps (vil-beach-01) is almost a pure DC swell, which the depth-per-
// wavelength rule alone would turn into 84 cm of moving ground.
//  * TESS_DEPTH_MAX_RATIO: the displacement may never exceed half the feature's own width. This is
//    the invariant the LEGACY law violated most brutally, and the reason it read as noise rather
//    than relief: with the old world projection leafyground's features are 4.8 cm across and the old
//    constant displaced them 35 cm, a depth/width of 7.3 -- a spike field, not a surface.
//  * TESS_DEPTH_MAX_M: a walkable surface must not disagree with its (flat) collision by more than
//    a step.
// ROUND 22 (owner defect B: "curseur au maximum 3.0, c'est pas si obvious"). Both caps above were
// slider-INDEPENDENT (or half-rate), so TESS_DEPTH_MAX_RATIO froze the displacement at relief >= 2
// and the top third of the slider did nothing. The drive becomes non-linear and the rails open:
//   drive = pow(rel, PBR_DRIVE_EXP)   with PBR_DRIVE_EXP = 1.4
// The exponent is chosen so drive(1.0) == 1.0 EXACTLY — relief 1.0 is the owner-accepted,
// physically-correct calibration point (depth = 0.25 * lambda_world) and must not move.
// drive(1.5) = 1.7641, drive(2.0) = 2.6390, drive(3.0) = 4.6555.
// tfrag3.frag's POM tier carries the IDENTICAL constants (PBR_DRIVE_EXP, POM_DEPTH_K,
// POM_DEPTH_MAX_RATIO, POM_DEPTH_MAX_M) so the two displacement tiers show the same depth by
// construction. Change one, change both.
//  * TESS_DEPTH_MAX_RATIO 0.5 -> 1.25: the base term reaches 1.164*lambda at relief 3, under 1.25,
//    so this rail does not bite anywhere in the slider range (it first binds at relief 3.157).
//  * TESS_DEPTH_MAX_M is now scaled by the SAME drive instead of the old (0.5 + 0.5*rel) half-rate
//    ramp: 15 cm at relief 1 (bit-identical to today), 69.8 cm at relief 3. Only a huge-lambda
//    material (vil-beach-01, lambda 1.92 m) ever reaches it.
#define PBR_DRIVE_EXP 1.4
#define TESS_DEPTH_MAX_RATIO 1.25
#define TESS_DEPTH_MAX_M 0.15

// Fallback authored UV density, in tiles per metre (0.5 = one tile every 2 m, about where tfrag's
// authored ground UVs sit). Used only when the per-material measured density is unavailable, and —
// under bisect bit 65536 — as the rate of the legacy world-space height lookup.
#define WORLD_TILES_PER_M 0.5

// The same bisect word tfrag3.frag declares. The tess pipeline uses tfrag3.frag as its fragment
// stage, so this uniform already exists on this program and is already pushed by the C++ setup —
// declaring it here costs nothing. 65536 = legacy per-chunk UV height lookup (the one that tears),
// 131072 = ignore the per-vertex seam weights. Both exist purely for live A/B.
uniform int u_pbr_bisect;
// PBR POLISH #17 — the same two uniforms tfrag3.frag uses, for the same reasons.
// u_pbr_height_stat = (this material's height-map MEAN, 0.5 / its robust half-range), measured at
// load. The shipped maps are neither mean-centred nor normalised, so the old raw (h - 0.5) pushed
// whole materials net-inward or net-outward (leafyground, mean 0.322, sank its entire surface
// ~4.7 cm) and only ever used 18-75% of the nominal amplitude depending on the material. hnorm()
// below fixes both, which is the "material-scaled displacement amplitude" half of the mandate.
// u_pbr_tess_max is the level ceiling the tesc law uses; the tese needs it to know, from position
// alone, how finely this patch will have been subdivided (see the band-limit block).
uniform vec2 u_pbr_height_stat;
uniform float u_pbr_tess_max;
// PBR POLISH #18 — the tesc's target segment size (see tfrag3_tess.tesc). The tese needs it because
// the height-map band-limit below is derived from the distance between generated vertices, which
// under the new law IS this target.
uniform float u_pbr_tess_seg;

float hnorm(float h) {
  return clamp((h - u_pbr_height_stat.x) * u_pbr_height_stat.y + 0.5, 0.0, 1.0);
}

// PBR POLISH #18 — the tesc's WORLD-SPACE-EDGE-LENGTH law targets a segment size directly, so the
// distance between generated vertices is now KNOWN from the camera distance alone instead of being
// inferred from a reference patch edge. This copy MUST stay identical to tfrag3_tess.tesc's: it has
// to be a pure function of the camera distance, which is what keeps the band-limit below
// bit-identical on both sides of a welded seam (a differing height fetch across the seam is exactly
// what re-opened the see-through slits the mesh-consolidation phase closed).
#define TESS_SEG_NEAR_M 0.06
#define TESS_SEG_D0_M 5.0
#define TESS_SEG_FAR_M 0.60
// Long-tail safety on the patches whose level SATURATES at the ceiling: there the real spacing is
// (edge / cap), coarser than the target. Measured at the owner's vantage (tools/tess_audit): the
// GROUND p90 edge within 5 m is 4.64 m, which at cap 64 gives 7.25 cm against the 6 cm target, i.e.
// 1.21x. Rounding the band-limit COARSER is the safe direction (blurrier, never aliased), so 1.25
// covers the tail without costing the ordinary patches a whole mip.
#define TESS_SPACING_SAFETY 1.25
// Legacy distance-only law + its measured median patch edge — bisect bit 16777216 only.
#define TESS_K 128.0
#define TESS_REF_EDGE_M 2.18
// Half-mip safety margin on the band-limit (see the block that uses it).
#define TESS_LOD_BIAS 0.5
// ROUND #19: the LOD ramp past D0 is SUPERLINEAR. With the pre-subdivided ground the near-field
// target drops to ~2.5 cm, and a LINEAR ramp then holds the 10-20 m band at ~6 cm -- still
// sub-Nyquist for a 5 cm feature, so it buys no relief, while generating more triangles than the
// entire near field does. Apparent feature size falls as 1/d and so does what the height mip can
// carry, so the target is allowed to grow faster than distance. Measured at the owner's vantage,
// exponent 1.5 cuts the 5-20 m generated-triangle count ~3x and leaves the <5 m band untouched.
// Compile-time on purpose: it MUST be the same number in the .tesc and the .tese, and it is not a
// knob the player has any use for (the tier knob is u_pbr_tess_seg).
#define TESS_SEG_EXP 1.5

float tess_seg_target_m(float d) {
  float near_m = TESS_SEG_NEAR_M;
  if (u_pbr_tess_seg > 0.0) {
    near_m = u_pbr_tess_seg;
  }
  return clamp(near_m * pow(max(d, TESS_SEG_D0_M) * (1.0 / TESS_SEG_D0_M), TESS_SEG_EXP), near_m,
               max(TESS_SEG_FAR_M, near_m));
}

// The distance between generated vertices, in metres, as a pure function of the camera distance.
// Both the band-limited height fetch and the gradient-normal tap step use it, so geometry and
// shading describe the same band-limited surface.
float tess_spacing_m(float dist_m) {
  if ((u_pbr_bisect & 16777216) != 0) {
    // legacy distance-only law: spacing had to be estimated as (median edge / level).
    float lvl_est = clamp(TESS_K / max(dist_m, 0.5), 1.0, max(u_pbr_tess_max, 1.0));
    return clamp(TESS_REF_EDGE_M / lvl_est, 0.005, 8.0);
  }
  return clamp(tess_seg_target_m(dist_m) * TESS_SPACING_SAFETY, 0.005, 8.0);
}
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
    // (1) ★★ OWNER CHECKER VERDICT, BUG A (2026-07-26): "le displacement ne correspond pas du tout
    //     à la texture, comme si c'était pas aligné." It did not, and THIS is where it came from.
    //     The height used to be looked up through a WORLD-PLANE PROJECTION of the vertex position,
    //     while the fragment stage samples the albedo — and the normal/roughness maps — at the
    //     AUTHORED texcoord this shader forwards as `tex_coord = uv3`. Two uncorrelated coordinate
    //     systems: the geometry rose and fell to a height field that had nothing to do with the
    //     checker squares the owner was looking at, which is exactly what a checkerboard is built
    //     to expose. The projection was adopted to stop tessellation slits at chunk seams (the
    //     tessellator generates new vertices ALL ALONG a shared edge and each patch interpolates
    //     ITS OWN texcoords for them, so UV-split sides sample different texels down the whole
    //     edge) — but that job is already done, and done better, by the seam weights in item (2):
    //     mesh_consolidate() zeroes seam_w on precisely the vertices whose two sides cannot agree,
    //     so the displacement is EXACTLY zero along those edges from BOTH patches whatever domain
    //     the lookup lives in. The height therefore goes back into the SAME uv the base colour
    //     uses — no projection, no extra multiplier — which is the owner's hard requirement:
    //     "s'assurer que les maps (height, normal, roughness) utilisent exactement le même
    //     alignement que la base color". The world-scale reasoning survives only where it belongs,
    //     in the AMPLITUDE (amp_m, in metres) below. Legacy projection = bisect bit 65536.
    vec2 huv;
    // ROUND 20: the displacement AMPLITUDE is derived from THIS material's measured authored UV
    // density (u_pbr_uv_per_m, tiles per world metre) instead of the hardcoded WORLD_TILES_PER_M,
    // so the displaced feature depth matches the texture the fragment stage normal-maps.
    // Legacy constant law kept under bisect bit 67108864.
    bool legacy_uv_law = (u_pbr_bisect & 67108864) != 0;
    float upm = (!legacy_uv_law && u_pbr_uv_per_m > 0.0) ? u_pbr_uv_per_m : WORLD_TILES_PER_M;
    float tile_m = 1.0 / max(upm, 1e-3);
    // The two WORLD directions +U and +V point along, and the huv-units-per-METRE scale: the
    // displaced surface's own normal is derived from this very height field (gradient block after
    // the displacement), so it has to know where a step in huv goes in world space.
    vec3 hax_u, hax_v;
    float huv_per_m = upm;
    if ((u_pbr_bisect & 65536) != 0) {
      // LEGACY A/B: the world-plane projection this round replaced. Projects onto the world plane
      // most face-on to the surface — seam-stable, but misaligned with the albedo (owner bug A).
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
      huv = pw * ((1.0 / 4096.0) * upm);
    } else {
      // THE ALIGNED PATH: the authored texcoord, bit-identical to what tfrag3.frag samples the base
      // colour with (this shader forwards the very same `uv3` as tex_coord). A raised block now
      // sits on the checker square that drew it.
      huv = uv3.xy;
      // +U/+V in world space come from the per-vertex TANGENT basis — the one the mesh bake
      // computes MikkTSpace-style from these very UVs — so the gradient normal stays consistent
      // with the lookup. A degenerate tangent falls back to the face-on world plane for the FRAME
      // ONLY; the lookup itself never leaves UV space.
      vec3 Tw = bary3(tc_tangent[0].xyz, tc_tangent[1].xyz, tc_tangent[2].xyz);
      vec3 Tp = Tw - N * dot(N, Tw);
      if (dot(Tp, Tp) > 1e-6) {
        hax_u = normalize(Tp);
        hax_v = cross(N, hax_u) * (tc_tangent[0].w < 0.0 ? -1.0 : 1.0);
      } else {
        vec3 an = abs(N);
        if (an.y >= an.x && an.y >= an.z) {
          hax_u = vec3(1.0, 0.0, 0.0);
          hax_v = vec3(0.0, 0.0, 1.0);
        } else if (an.x >= an.z) {
          hax_u = vec3(0.0, 0.0, 1.0);
          hax_v = vec3(0.0, 1.0, 0.0);
        } else {
          hax_u = vec3(1.0, 0.0, 0.0);
          hax_v = vec3(0.0, 1.0, 0.0);
        }
      }
    }
    // camera distance in meters (same convention as v_fringe_rel below). Hoisted above the height
    // fetch because the BAND-LIMIT below needs it. Uses the UNDISPLACED `world`, which
    // mesh_consolidate() has made bit-identical across a welded edge.
    float dist_m = length((world - cam_trans.xyz) * (1.0 / 4096.0));

    // ===============================================================================================
    // PBR POLISH — OWNER PLAYTEST #17: "la tessellation manque de détail et ne donne pas vraiment de
    // profondeur... ça fait toujours juste bump map glorifié".
    //
    // THE ROOT CAUSE, and it is not the amplitude. This stage fetched the height at
    // textureLod(..., 0.0) — MIP 0 — while the vertices it displaces are metres apart. Do the
    // arithmetic on the shipped data: WORLD_TILES_PER_M is 0.5, so one tile of the height map spans
    // 2 m of world; the maps are 2048x2048; therefore ONE MIP-0 TEXEL IS 0.98 MILLIMETRES. Measured
    // on village1's real geometry (tools/tess_audit), the shipped level law generates vertices
    // ~19 cm apart within 10 m of the camera. Every generated vertex was therefore taking a single
    // ~1 mm point sample of the field, ~195 texels away from its neighbour's: consecutive samples
    // are completely decorrelated. That is not relief, it is white noise at the vertex frequency —
    // textbook aliasing — and it is exactly why raising the tessellation level never helped before
    // and why the result read as "a glorified bump map": the GEOMETRY carried no coherent shape at
    // all, so all the visible relief was coming from the fragment-stage normal map.
    //
    // THE FIX is the standard LOD-matched displacement rule: sample the height at the mip whose
    // texel size matches the distance between generated vertices. The field is then band-limited to
    // what the tessellation can actually represent, neighbouring vertices sample overlapping
    // footprints, and the displaced surface has real, coherent macro shape — and NOW every extra
    // tessellation level buys genuinely more detail instead of re-rolling the dice finer.
    //
    // SEAM-SAFE BY CONSTRUCTION, which is why the spacing comes from POSITION rather than from
    // gl_TessLevelOuter[] and the patch's own edges: those DIFFER between the two patches sharing a
    // welded edge, so a per-patch spacing would give the two sides different mips, different
    // heights and different displacements — the see-through slits the mesh-consolidation phase
    // closed would come straight back. tess_spacing_m() is a pure function of dist_m, so like
    // `world`, `N`, `huv`, `falloff` and `seam` it is bit-identical on both sides.
    // PBR POLISH #18: it is also no longer an ESTIMATE. The #18 level law solves for a target
    // segment size, so the target IS the spacing wherever the level does not saturate at the
    // ceiling (TESS_SPACING_SAFETY covers the saturated long tail, coarser = safe).
    // Bisect bit 4194304 = the legacy lod-0 fetch back, so the owner can A/B the aliasing itself.
    // ===============================================================================================
    float spacing_m = tess_spacing_m(dist_m);
    float hlod = 0.0;
    if ((u_pbr_bisect & 4194304) == 0 && huv_per_m > 0.0) {
      vec2 hts = vec2(textureSize(tex_PBR_H, 0));
      float texels = spacing_m * huv_per_m * max(hts.x, hts.y);
      // log2(texels) is the theoretically exact match (that mip's Nyquist wavelength is exactly
      // twice the vertex spacing). TESS_LOD_BIAS is the standard half-mip safety margin: a mip
      // chain is a 2x2 BOX filter, whose stopband is poor, so the exact mip still leaks enough
      // above-Nyquist energy to shimmer at the vertex frequency under motion. Measured over the 7
      // shipped maps (.autoport/gpbrf_r17_offline.py), half a mip raises the neighbour-sample
      // correlation at 0-5 m by 20-135% (leafyground 0.285 -> 0.482, strawroof 0.266 -> 0.456,
      // beachrock 0.116 -> 0.272) for a uniform ~15% amplitude cost, while a full mip costs up to
      // 36% of the amplitude for much less coherence in return.
      hlod = clamp(log2(max(texels, 1.0)) + TESS_LOD_BIAS, 0.0, 12.0);
    }
    // hnorm(): mean-centred and amplitude-refilled per material, so 0.5 is now genuinely THIS
    // material's neutral surface instead of a constant the shipped maps do not honour.
    float h = hnorm(textureLod(tex_PBR_H, huv, hlod).r);   // 0.5 = neutral surface

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

    // fade 20 -> 30 m to 0 so far patches (which are passthrough anyway) never pop, and mid
    // patches ease in smoothly. Uses the UNDISPLACED `world`, shared across the edge, so the fade
    // matches too. (dist_m is computed above, before the band-limited height fetch.)
    float falloff = 1.0 - smoothstep(20.0, 30.0, dist_m);
    // ROUND 20: the amplitude follows the material's MEASURED FEATURE SIZE, not a constant and not
    // the tile. u_pbr_height_lambda is the height map's characteristic feature wavelength in TILES
    // (measured at load from the map's own mip-energy spectrum); x tile_m makes it METRES. A real
    // surface feature of width w is roughly w/4 deep; u_pbr_height_scale is 0.05 * relief, so
    // TESS_DEPTH_K = 5.0 puts the depth at 0.25 * lambda_world at relief 1.0. The clamp keeps a
    // pathological lambda from either flattening the surface or growing hills: 0.5 cm .. 30 cm per
    // unit of relief. Measured on village1: leafyground tile 7.90 m, beachrock 6.39 m, sand 3.94 m --
    // the old law's constant 14336 (35 cm at relief 2) was blind to all of it.
    float rel = u_pbr_height_scale * 20.0;   // the relief slider (height_scale = 0.05 * relief)
    // ROUND 22: non-linear drive, drive(1) == 1 so relief 1.0 is bit-identical to before.
    float drive = pow(max(rel, 0.0), PBR_DRIVE_EXP);
    float hs = 0.05 * drive;                 // effective height scale (== u_pbr_height_scale at rel 1)
    float lambda_world_m = clamp(u_pbr_height_lambda, 0.002, 1.0) * tile_m;
    float amp_m = hs * TESS_DEPTH_K * lambda_world_m;
    amp_m = min(amp_m, TESS_DEPTH_MAX_RATIO * lambda_world_m);  // never a spike field again
    amp_m = min(amp_m, TESS_DEPTH_MAX_M * drive);               // never deeper than a step
    amp_m = max(amp_m, 0.005 * rel);
    float amp = amp_m * TESS_DISP_UNITS_PER_M * falloff * seam;
    if (legacy_uv_law) {
      amp = u_pbr_height_scale * TESS_DISP_K * falloff * seam;
    }
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
      // PBR POLISH #17: the step is no longer a fixed 0.25 m guess and the taps are no longer at
      // mip 0. Both now follow the SAME band-limited spacing the displacement itself used, so the
      // normal describes exactly the surface the vertices actually form. A fixed 0.25 m step
      // against a ~1 mm-texel lod-0 fetch was measuring the slope of the aliasing noise, not of the
      // geometry — which is the other half of why real displaced vertices still shaded flat.
      // PBR POLISH #18: literally the same spacing value the height fetch used (it was a duplicated
      // expression before), so the two can no longer drift apart. Still position-only => still
      // bit-identical across a welded seam.
      float MS_M = spacing_m;
      float e = MS_M * huv_per_m;         // ...expressed in huv units
      float hu1 = hnorm(textureLod(tex_PBR_H, huv + vec2(e, 0.0), hlod).r);
      float hu0 = hnorm(textureLod(tex_PBR_H, huv - vec2(e, 0.0), hlod).r);
      float hv1 = hnorm(textureLod(tex_PBR_H, huv + vec2(0.0, e), hlod).r);
      float hv0 = hnorm(textureLod(tex_PBR_H, huv - vec2(0.0, e), hlod).r);
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
