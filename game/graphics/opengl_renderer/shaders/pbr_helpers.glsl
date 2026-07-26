// Grecharged-pbr-realtime-fusion REOPEN#9 (owner playtest #9): a CONTINUOUS orthonormal tangent basis
// derived purely from the surface normal, used when the per-vertex tangent v_tangent is degenerate or
// unbound. Duff et al. 2017 "Building an Orthonormal Basis, Revisited" — branchless and numerically
// stable for EVERY normal (the denominator magnitude stays in [1,2]). Because it is a smooth function of
// the (already smooth, interpolated) per-vertex normal, the frame is CONTINUOUS across triangle edges —
// unlike the screen-space derivative frame (dFdx/dFdy), which is CONSTANT within a triangle and JUMPS at
// every edge and is the exact source of the hard triangular FACETS the owner sees scaling with relief.
// The tangent DIRECTION is arbitrary (no UV reference) but per-fragment continuity is what kills the
// facets — exactly the owner's mandate ("an arbitrary but CONTINUOUS per-vertex tangent kills the facets").
// SEAM-STABLE tangent frame for the NORMAL MAP (supervisor live A/B + offline weld measurement,
// 2026-07-24). Every tfrag/tie chunk owns its own UV layout, so the per-vertex UV-derived tangent
// frame is DISCONTINUOUS at chunk boundaries: measured over the welded cross-chunk vertex groups,
// 40.2% of village1 pairs (41.1% jungle) carry frames rotated more than 30 deg and 27% are outright
// MIRRORED (.w handedness disagrees) — i.e. the same physical surface decodes the normal map in a
// different, sometimes flipped, orientation on each side of the seam. This frame is derived ONLY
// from the (position-smoothed, seam-continuous) normal, so it is IDENTICAL on both sides of every
// chunk boundary by construction — the standard chunked-terrain fix. R is a deliberately skew axis:
// the unavoidable hairy-ball singularity then sits on a direction no level surface squarely faces
// (never up, never a cardinal wall), and the guard below keeps even that ~1 deg cone finite.
void stable_frame(vec3 n, out vec3 t, out vec3 b) {
  const vec3 R1 = vec3(0.3113, 0.1504, 0.9382);
  const vec3 R2 = vec3(0.9382, 0.3113, 0.1504);
  vec3 tt = cross(n, R1);
  float l = length(tt);
  t = (l > 0.02) ? (tt / l) : normalize(cross(n, R2));
  b = cross(n, t);
}

void frisvad_basis(vec3 n, out vec3 t, out vec3 b) {
  float s = n.z >= 0.0 ? 1.0 : -1.0;
  float a = -1.0 / (s + n.z);
  float d = n.x * n.y * a;
  t = normalize(vec3(1.0 + s * n.x * n.x * a, s * d, -s * n.x));
  b = normalize(vec3(d, s + n.y * n.y * a, -n.y));
}

#ifdef OG_PBR
// PBR POLISH (owner playtest #17) — MATERIAL-SCALED HEIGHT. Recentre the height map on ITS OWN
// mean and refill the 0..1 range, using the statistics measured per material at load time (see
// u_pbr_height_stat). EVERY height consumer in the pipeline goes through this: the POM march, the
// self-shadow, the cavity term and (with the same expression, same uniform) the tess-eval
// displacement. Consequences, all of them the owner's report:
//   - "material-scaled displacement amplitude": a map that only spans 0.30..0.48 (strawroof) no
//     longer displaces at a fifth of the amplitude a map spanning 0.00..0.75 (stonewall) gets.
//     Every material now reaches the full authored displacement, so one relief slider means the
//     same physical depth everywhere.
//   - the net inward/outward OFFSET disappears: a material whose mean is 0.32 was pushing its
//     whole surface ~4.7 cm INTO the ground (and stepping against its unmapped neighbour at the
//     material border — the same class of defect the normal-map DC removal already fixed).
// Identity when the material has no measured statistics (0.5, 1.0) => unchanged.
float hnorm(float h) {
  return clamp((h - u_pbr_height_stat.x) * u_pbr_height_stat.y + 0.5, 0.0, 1.0);
}

// ---- PARALLAX (POM) DEPTH LAW — rebuilt, OWNER 2026-07-26 ----
// Shared by BOTH POM marches (the fused rt+pbr path and the rt-OFF standalone fallback), because
// every symptom the owner reported is a property of the formula, not of one branch.
//
// OWNER: "le parallax rend complètement plat" ... "AUTANT SUR LES MURS QUE LE SOL". The second half
// is the diagnostic one: on a wall viewed head-on the grazing fade is ~1, so the fade could not be
// the cause. The cause was the ABSOLUTE world cap I had stacked on top of it:
//     pom_cap = min(POM_MAX_TAN * height_scale, POM_MAX_WORLD_M * uv_per_m)     [old]
// with POM_MAX_WORLD_M = 0.03 m flat. Plugging in the measured village materials, the second term
// ALWAYS won: wallplaster uv_per_m 0.439 -> cap 0.0132 UV, leafyground 0.127 -> cap 0.0038 UV,
// against a marched vector of 0.075 UV. The offset was clipped to 5-17 % of its length on every
// shipped material, at every view angle, walls included. 3 cm is not a small depth cue for these
// materials — leafyground's height features are ~2 m across, so 3 cm of lateral shift is nothing.
//
// THE FIX is to stop expressing the depth as an arbitrary absolute and derive it from the MATERIAL,
// exactly like the tessellation tier already does: depth = f(this map's feature wavelength), in
// metres, converted to UV with this material's measured density. Parallax and Tessellation then
// show the SAME depth by construction — they differ only in how it is produced (UV march vs real
// vertices), which is what makes flipping DISPLACEMENT between them read as a quality change and
// not as a depth change.
//
// tan(theta) = |Vt.xy| / Vt.z, so gating on Vt.z gates on the view angle: 0.15 ~= 81 deg off the
// surface normal, 0.50 = 60 deg.
#define POM_GRAZE_LO 0.15
#define POM_GRAZE_HI 0.50
// OWNER 2026-07-26: the grazing attenuation is a gentle FLOOR now, never a kill. At the most
// extreme grazing the offset keeps this fraction of its strength — enough that the relief still
// reads at ordinary gameplay camera angles (which ARE grazing on a floor), while the sideways-smear
// regime the earlier "ça s'étale à plat" report described is still damped. The steep march below
// (16-32 layers with occlusion + secant refine) is what actually keeps grazing views honest.
#define POM_GRAZE_FLOOR 0.35
// ROUND 22 (owner defect B: "curseur au maximum 3.0, c'est pas si obvious"). The 0..3 slider was
// ARITHMETICALLY DEAD above ~1.4 because every cap below was independent of it: POM_MAX_FEATURE_FRAC
// froze the parallax offset at rel >= 1.4 and POM_DEPTH_MAX_RATIO froze the depth at rel >= 2.0, so
// the top half of the slider changed nothing at all. Both rails are opened wide enough that NONE of
// them binds inside 0..3 (for the shipped village materials), and the drive itself becomes
// non-linear so the top of the slider is unmistakably extreme.
// ---- THE DRIVE ----
//   drive = pow(rel, PBR_DRIVE_EXP)   with PBR_DRIVE_EXP = 1.4
// The exponent is chosen so that drive(1.0) == 1.0 EXACTLY: rel = 1.0 is the owner-accepted,
// physically-correct calibration point (depth = 0.25 * lambda_world) and it must not move by a
// single ULP. drive(1.5) = 1.7641, drive(2.0) = 2.6390, drive(3.0) = 4.6555 — a 4.66x deeper field
// at the top of the slider instead of the old 1.0x (frozen).
// tfrag3_tess.tese carries the IDENTICAL law and the identical constant, so the two displacement
// tiers still show the same depth by construction. Change one, change both.
#define PBR_DRIVE_EXP 1.4
// The lateral shift may never exceed the feature depth itself (tan(theta) <= 1)...
// ROUND 22: 1.0 -> 2.0. With the deeper field this term must not become the new freeze point.
#define POM_MAX_TAN 2.0
// ...nor this fraction of ONE HEIGHT FEATURE of apparent sliding. Relative, so it scales with the
// material the way the depth does, instead of clipping every material to the same absolute.
// ROUND 22: 0.35 -> 1.5. At 0.35 this cap was lambda-proportional but drive-INDEPENDENT, so it
// clamped the marched vector to the same length for every slider position above ~1.4 — the single
// term that made the top half of the slider a no-op for parallax.
#define POM_MAX_FEATURE_FRAC 1.5
// The amplitude law itself, kept numerically IDENTICAL to tfrag3_tess.tese's (TESS_DEPTH_K,
// TESS_DEPTH_MAX_RATIO, TESS_DEPTH_MAX_M and its 0.005*relief floor) so the two displacement tiers
// cannot drift apart. Change one, change both.
#define POM_DEPTH_K 5.0
// ROUND 22: 0.5 -> 1.25. The base term is 0.25*drive*lambda, which reaches 1.164*lambda at rel 3 —
// below 1.25, so this rail does not bite anywhere inside the slider (it first binds at rel 3.157,
// just past the maximum). It is still there as the "never a spike field" backstop.
#define POM_DEPTH_MAX_RATIO 1.25
// ROUND 22: the absolute "never deeper than a step" rail now follows the SAME drive instead of the
// old half-rate (0.5 + 0.5*rel) ramp: 0.15 * drive == 0.15 m at rel 1 (bit-identical to today) and
// 0.698 m at rel 3. Only a huge-lambda material (vil-beach-01, lambda 1.92 m) ever reaches it.
#define POM_DEPTH_MAX_M 0.15

// This material's parallax depth, in UV units, plus its feature wavelength in metres (out param,
// used for the relative offset cap). uv_per_m converts metres -> UV: one metre of world spans
// uv_per_m tiles of texture, and the parallax offset is a UV offset.
// ROUND 22: also returns the non-linear slider `drive` (out param) — the march step count is scaled
// by sqrt(drive) so a 4.66x deeper field is not under-sampled.
float pom_depth_uv(out float lambda_world_m, out float drive) {
  float upm = max(u_pbr_uv_per_m, 0.02);
  float tile_m = 1.0 / upm;
  lambda_world_m = clamp(u_pbr_height_lambda, 0.002, 1.0) * tile_m;
  float rel = u_pbr_height_scale * 20.0;  // the relief slider (height_scale = 0.05 * relief)
  drive = pow(max(rel, 0.0), PBR_DRIVE_EXP);  // drive(1) == 1 => rel 1 unchanged
  float hs = 0.05 * drive;                    // effective height scale (== u_pbr_height_scale at rel 1)
  float amp_m = hs * POM_DEPTH_K * lambda_world_m;
  amp_m = min(amp_m, POM_DEPTH_MAX_RATIO * lambda_world_m);  // never a spike field
  amp_m = min(amp_m, POM_DEPTH_MAX_M * drive);               // never deeper than a step
  amp_m = max(amp_m, 0.005 * rel);
  return amp_m * upm;
}

// Grecharged-pbr-realtime-fusion PBR POLISH (owner playtest #16, defect 2 "completely FLAT in
// shadow"). The realtime AMBIENT IRRADIANCE for an arbitrary direction — the same selector the
// fused branch already used for its ambient-specular source, lifted into a function so the
// INDIRECT DIFFUSE can be evaluated twice (smooth normal vs normal-mapped normal) and the relief
// therefore survives where no sun reaches. Identical expressions => the ambient-specular term it
// replaces is bit-for-bit unchanged.
vec3 rt_amb_eval(vec3 n) {
  if (u_rt_ambient_on == 0) {
    return vec3(clamp(u_rt_shadow_residual, 0.0, 1.0));
  } else if (u_rt_ambient_model == 1) {
    return rt_sh_ambient(n);
  } else if (u_rt_ambient_model == 2) {
    return rt_ibl_ambient(n);
  }
  return mix(u_rt_ground_color, u_rt_sky_color, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
}

// Grecharged-pbr-realtime-fusion PBR POLISH (owner playtest #16, defect 3: the displacement
// "reads FLAT ... un bump map glorifie avec un peu de normales").
// HEIGHT-FIELD SELF-SHADOWING. What separates real surface depth from a shaded bump is that a
// raised texel CASTS A SHADOW on the texels behind it. Neither tier produced any: an audit of
// every tex_PBR_H fetch in this shader found the height map driving a UV offset (POM) and a
// vertex offset (tess-eval) and NOTHING ELSE — it never occluded a light, so the relief had no
// contact shadow and read as shading, not as geometry.
// This is the standard relief-mapping soft shadow (Policarpo/Kaneko): march the height field from
// the shading point toward the light in TANGENT-UV space and keep the largest amount by which an
// occluder rises ABOVE the ray. The (1 - t) weight makes distant occluders soften into a penumbra
// instead of a hard aliased edge, which also keeps it stable under motion.
//   uv0   = the (parallax-corrected) UV of the shading point
//   h0    = height at uv0
//   Ltuv  = light direction in the SAME tangent-UV frame the POM marches in (xy = uv plane)
//   hs_uv = the UV distance that corresponds to one full height unit (the POM's depth scale)
// Returns a visibility multiplier in [PBR_MS_FLOOR, 1].
float pbr_micro_shadow(vec2 uv0, float h0, vec3 Ltuv, float hs_uv) {
  const int PBR_MS_STEPS = 6;
  const float PBR_MS_K = 3.0;       // occluder-height -> darkness gain
  const float PBR_MS_FLOOR = 0.35;  // never fully black: ambient still reaches a crevice
  // Light at/below the surface horizon: the macro terminator already handles that face — do not
  // double-darken it (and the march direction would be degenerate).
  float lz = Ltuv.z;
  if (lz < 0.08) {
    return 1.0;
  }
  vec2 sd = (Ltuv.xy / lz) * hs_uv;
  // Same surface-lock bound as the POM march: the shadow ray may never wander a whole tile away
  // from the shading point, or the "shadow" stops belonging to this piece of surface.
  float sl = length(sd);
  if (sl > 0.08) {
    sd *= 0.08 / sl;
  }
  float occ = 0.0;
  for (int i = 1; i <= PBR_MS_STEPS; i++) {
    float t = float(i) / float(PBR_MS_STEPS);
    float hs = hnorm(textureLod(tex_PBR_H, uv0 + sd * t, 0.0).r);
    // ray height above the shading point, rising to the top of the height range at t = 1
    float ray = h0 + t * (1.0 - h0);
    occ = max(occ, (hs - ray) * (1.0 - t));
  }
  return clamp(1.0 - occ * PBR_MS_K, PBR_MS_FLOOR, 1.0);
}

// ===================================================================================================
// PBR POLISH — OWNER PLAYTEST #17: "à l'ombre c'est toujours plat" (still completely flat in shade).
//
// THE MATH ROOT CAUSE, found by reading the term that was supposed to do this job. Round #16 added
// an ambient relief term expressed as the RATIO rt_amb_eval(Nm) / rt_amb_eval(N) — the irradiance
// at the normal-mapped normal over the irradiance at the smooth one. That is only ever as strong
// as the ambient's DIRECTIONAL VARIATION, and ours (the accepted baked-modulation composite, plus
// a hemisphere/SH ambient that is deliberately soft) is very nearly direction-INVARIANT. Measured
// shader-exact over all 7 shipped materials, that ratio has mean 0.960..0.996 — i.e. between 0.4%
// and 4% away from exactly 1.0. You cannot extract relief from a function that does not vary with
// the normal. In cast shadow every other normal-dependent term is already zero (sun_occ = 0 kills
// both direct N.L cues, matte_gate kills the env specular on any rough dielectric), so a shadowed
// fragment really was baked x constant x _ao. Flat, by arithmetic.
//
// THE FIX is the one modern games use, and it is the one thing that cannot fail this way: a term
// with NO direction dependence at all. Read the relief straight out of the HEIGHT FIELD as a
// CAVITY / micro-ambient-occlusion factor — a texel that sits BELOW its local neighbourhood is in
// a crevice and receives less skylight; one that sits ABOVE is a ridge and receives more. That is
// physically the ambient-occlusion of the micro-relief, it is defined at every fragment, and it is
// exactly as strong at midnight in a cast shadow as it is in full sun.
//
// MEAN-PRESERVING BY CONSTRUCTION, not by tuning: the driving signal is a HIGH-PASS of the height
// field (the texel minus its own local mean), so its mean over any surface patch is zero, hence
// the multiplier's mean is 1.0 and the accepted overall brightness cannot drift. A material with
// no height map gets no cavity at all and stays bit-for-bit as it was.
//
// BAND-LIMITED BY CONSTRUCTION: the fine tap is taken at the mip the hardware would fit for this
// fragment's own UV footprint (never a lod-0 fetch of a ~1 mm texel from 20 m away, which is the
// aliasing that produced earlier rounds' shimmer), and the blur tap is PBR_CAV_SPAN mips coarser.
// Far away the two taps converge and the term fades to exactly 1.0 — correct, because relief finer
// than a pixel has no business modulating that pixel.
// ===================================================================================================
#define PBR_CAV_SPAN 3.0   // mips between the fine and the local-mean tap (a ~8x8 texel neighbourhood)
#define PBR_CAV_GAIN 1.6   // normalised-height high-pass -> darkness/brightness gain
#define PBR_CAV_MIN 0.55   // a crevice is dark, never black: skylight still reaches into it
#define PBR_CAV_MAX 1.45
float pbr_cavity(vec2 uv0) {
  vec2 ts = vec2(textureSize(tex_PBR_H, 0));
  vec2 dx = dFdx(uv0) * ts;
  vec2 dy = dFdy(uv0) * ts;
  float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-12)), 0.0, 11.0);
  float hf = hnorm(textureLod(tex_PBR_H, uv0, lod).r);
  float hb = hnorm(textureLod(tex_PBR_H, uv0, min(lod + PBR_CAV_SPAN, 12.0)).r);
  return clamp(1.0 + PBR_CAV_GAIN * (hf - hb), PBR_CAV_MIN, PBR_CAV_MAX);
}
#endif
