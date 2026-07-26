        // REOPEN#7 FOUNDATION FIX: build the TBN from the per-vertex MikkTSpace tangent v_tangent
        // (interpolated => CONTINUOUS across triangle edges / UV seams) instead of screen-space
        // derivatives, which were discontinuous there => the owner's incoherent relief + the hard
        // CONTRAST CRACKS that grew with relief. N is the reconstructed smooth normal; Gram-Schmidt
        // re-orthonormalizes the interpolated tangent against it per fragment; .w carries handedness.
        // A degenerate/unbound tangent (len~0 => (0,0,0,1) default) falls back to the derivative frame.
        // fTuv/fBuv = the UV-derived frame. It is the ONLY frame that can drive a UV OFFSET, so
        // the POM march below MUST keep using it (a world-derived frame would shift the height
        // march in a direction unrelated to the texture = the "floating/epoxy" parallax of
        // owner playtest #5). fTn/fBn = the frame the NORMAL MAP is decoded in — that one is
        // swapped for the seam-stable world frame further down.
        vec3 fTuv, fBuv;
        // REOPEN#9 (owner playtest #9) tangent-fallback coverage flag (for the u_pbr_debug==20 viz + the
        // pbr_tan_diag.txt CPU proof): 1.0 = this fragment took the degenerate-tangent fallback.
        float f_tan_fb = (dot(v_tangent.xyz, v_tangent.xyz) > 0.04) ? 0.0 : 1.0;
        if (dot(v_tangent.xyz, v_tangent.xyz) > 0.04) {
          fTuv = normalize(v_tangent.xyz - N * dot(N, v_tangent.xyz));
          // OWNER PLAYTEST #8: use the SIGN of the interpolated handedness, not its raw magnitude.
          // The interpolated .w can pass through 0 across a strip whose vertices carry opposite
          // handedness, which would SHRINK the bitangent mid-triangle (a per-triangle discontinuity
          // that reads as a facet). sign() keeps a full-length, continuous bitangent.
          fBuv = cross(N, fTuv) * (v_tangent.w < 0.0 ? -1.0 : 1.0);
        } else {
          // REOPEN#9 (owner playtest #9): v_tangent is degenerate/unbound here. The OLD code rebuilt the
          // TBN from screen-space derivatives (dFdx/dFdy) — a per-triangle-CONSTANT frame that JUMPS at
          // every edge => the hard triangular FACETS the owner saw scaling with relief. Derive a
          // CONTINUOUS basis from the smooth interpolated normal N instead (NEVER a screen derivative).
          frisvad_basis(N, fTuv, fBuv);
        }
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #16 DEFECT 1: "displacement in the WRONG DIRECTION in
        // places on the SAME texture".
        // stable_frame() is a function of the surface NORMAL and of nothing else, so its U axis
        // ROTATES as the surface tilts. The same material therefore decodes its height field
        // turned by an arbitrary, orientation-dependent angle from one patch to the next: over a
        // hill the relief's lighting direction sweeps with the slope, and between surfaces facing
        // opposite ways it flips outright — wherever that rotation passes ~90 deg the perceived
        // relief INVERTS and bumps read as pits. That is exactly the owner's defect, and it is
        // structural: a height field authored in TEXTURE space can only be lit correctly in the
        // frame its own UVs define. No parameter tune can fix a frame that ignores the texture.
        // The world frame was adopted to kill the per-chunk brightness plates — but the plates
        // were MEASURED to come from the map's DC TILT (chunk-to-chunk spread 61.4% -> 3.0% once
        // u_pbr_normal_dc is subtracted), and that fix is FRAME-INVARIANT: rotating a zero-mean
        // gradient leaves it zero-mean, so it cannot produce a brightness step in any frame. The
        // normal map goes back into the UV frame it was authored in, where the relief direction is
        // right by construction and the grain finally lines up with the albedo it belongs to.
        // Bonus: the POM march below already had to use the UV frame (it is the only frame a UV
        // OFFSET can be expressed in), so the parallax shift and the normal-map shading were
        // pointing in DIFFERENT directions — they now agree, which is the other half of the
        // "displacement direction" defect.
        // stable_frame survives as (a) the fallback where no per-vertex tangent exists — there is
        // no UV reference to use there, and a continuous arbitrary frame still beats a
        // per-triangle one — and (b) bisect bit 32768, the live A/B killswitch (SET = the old
        // world frame, so the owner's previous build is one prop away).
        // ===================================================================================
        vec3 fTn = fTuv, fBn = fBuv;
        if ((u_pbr_bisect & 32768) != 0 || f_tan_fb > 0.5) {
          stable_frame(N, fTn, fBn);
        }
        // ★ OWNER CHECKER VERDICT, BUG A: the SAME uv the base colour is sampled with (line ~600,
        // `texture(tex_T0, tex_coord.xy)`), no multiplier. Every map below — height, normal,
        // roughness, metallic, AO, specular, emissive — rides this one variable, so the relief can
        // only ever line up with the pattern that drew it.
        vec2 uv = tex_coord.xy;
        // ROUND 22 COVERAGE INSTRUMENTATION (owner defect A, "la plupart des endroits n'ont aucun
        // displacement"): u_pbr_debug 31 paints, per pixel, whether this fragment actually received
        // displacement. The tessellation tier moved this fragment's REAL geometry upstream, so it
        // counts as covered even though the POM march below is (correctly) skipped for it.
        if ((u_pbr_mode & 16) != 0 && u_pbr_height_scale > 0.0 && u_pbr_displacement != 0 &&
            u_pbr_tess_active != 0) {
          f_disp_cover = 1.0;
        }
        // Height map (bit 16): the same mobile-tuned POM march as the standalone path
        // (already proven on Adreno 618 there — same cost class, so it ships here too).
        // ★ BUG B: gated on u_pbr_tess_active, NOT on the global u_pbr_displacement. A draw only
        // skips the march when THIS program actually tessellated it; every draw the tess program
        // does not cover (TIE walls and props, shrubs, hfrag, non-opaque trees, anything past the
        // 30 m tesc gate) keeps its parallax instead of going flat.
        if ((u_pbr_mode & 16) != 0 && u_pbr_debug != 8 && u_pbr_height_scale > 0.0 &&
            (u_pbr_bisect & 128) == 0 && u_pbr_tess_active == 0) {
          vec3 Vt = normalize(vec3(dot(Vv, fTuv), dot(Vv, fBuv), max(dot(Vv, N), 0.0)));
          float vz = max(Vt.z, 0.20);
          // ===========================================================================
          // PBR POLISH — OWNER PLAYTEST #18: "le displacement du parallax est HORIZONTAL
          // au sol, comme si au lieu de s'élever, ça s'étale à plat."
          // He is describing the formula's own failure mode, exactly. The offset is
          //     P = (Vt.xy / Vt.z) * depth        i.e.  |P| = depth * tan(theta)
          // so on a near-horizontal FLOOR viewed by the ordinary gameplay camera — which
          // looks ALONG the ground, theta -> 90 deg — the amplifier blows up and P
          // degenerates into a large HORIZONTAL UV TRANSLATION. The texture slides
          // sideways instead of reading as depth: "ça s'étale à plat". The old 0.08 UV
          // clamp bounded the magnitude but not the NATURE of the artifact, and 0.08 UV is
          // ~16 cm of world sliding at the authored ground UV density — enormous.
          // THE FIX (industry-standard POM attenuation, two parts):
          //  (1) GRAZING FADE, and
          //  (2) an absolute POM_MAX_WORLD_M = 3 cm world cap.
          // ★ BOTH WERE OVER-CORRECTIONS, and (2) was the fatal one — OWNER 2026-07-26:
          // "le parallax rend complètement plat ... AUTANT SUR LES MURS QUE LE SOL". A wall
          // seen head-on has pom_graze ~= 1, so the fade could not explain it; the flat
          // 3 cm cap could, and did. Measured on the shipped materials it clipped the
          // marched vector to 5-17 % of its length at EVERY angle (see the constants block
          // for the numbers). Both parts are rebuilt:
          //  (1') the fade is now a gentle FLOOR (POM_GRAZE_FLOOR) — damped at extreme
          //       grazing, never killed, because the ordinary gameplay camera IS grazing
          //       on a floor and that is precisely where the owner needs to see depth;
          //  (2') the cap is RELATIVE to the material: the feature depth itself
          //       (POM_MAX_TAN, tan(theta) <= 1) and a fraction of one feature wavelength
          //       (POM_MAX_FEATURE_FRAC). No absolute constant clips a whole material any
          //       more, and the depth itself now comes from pom_depth_uv() — the same
          //       feature-scaled law tfrag3_tess.tese displaces real vertices by.
          // Bisect bit 33554432 = the legacy un-faded 0.08 UV offset, so this is still a
          // live same-vantage A/B with one setprop.
          // ===========================================================================
          float pom_graze =
              mix(POM_GRAZE_FLOOR, 1.0, smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z));
          float lambda_world_m;
          float pom_drive;
          float depth_uv = pom_depth_uv(lambda_world_m, pom_drive);
          float pom_cap = min(POM_MAX_TAN * depth_uv,
                              POM_MAX_FEATURE_FRAC * lambda_world_m * max(u_pbr_uv_per_m, 0.02));
          // Bisect bit 33554432 restores the ROUND-20 law EXACTLY — the build the owner played and
          // called "complètement plat", not some older variant — so before/after is one setprop
          // apart at the same vantage in the same boot. (It used to restore a pre-round-20 cell,
          // which made the A/B measure the wrong pair: round 20's 3 cm world cap is the term that
          // actually flattened it, and that cell never exercised it.)
          if ((u_pbr_bisect & 33554432) != 0) {
            pom_graze = smoothstep(POM_GRAZE_LO, POM_GRAZE_HI, Vt.z);  // r20: fade to ZERO
            depth_uv = u_pbr_height_scale;                             // r20: raw UV depth scale
            pom_cap = min(POM_MAX_TAN * u_pbr_height_scale,
                          0.03 * max(u_pbr_uv_per_m, 0.02));           // r20: flat 3 cm world cap
            pom_drive = 1.0;  // r20: linear drive => the r20 step counts too (see n_layers below)
          }
          // REOPEN #3: STEEP POM tier — 16 steps head-on to 32 at grazing (was 10-28);
          // the loop bound below already allows 32. Occlusion test + secant interpolation
          // (the industry steep-parallax + refinement) were already in place.
          // ROUND 22: a drive(3) = 4.66x deeper field marched with the same 16-32 layers is
          // under-sampled — the intersection lands a whole layer early and the relief degenerates
          // into stair-stepped mush exactly where the owner is looking for "extreme". Scale by
          // sqrt(drive): 1.0x at rel 1 (UNCHANGED), 1.33x at 1.5, 2.16x at 3. The static loop bound
          // is raised to 64 to let the count through (the `>= n_layers` early break still runs).
          float n_layers = clamp(mix(32.0, 16.0, clamp(Vt.z, 0.0, 1.0)) * sqrt(pom_drive), 8.0, 64.0);
          // REOPEN #6 SURFACE-LOCK (owner playtest #5: the "10cm epoxy float, texture moves
          // differently than the model"). Build the TOTAL parallax vector P and CLAMP its
          // length so the offset can never exceed a small, surface-locked bound: the depth
          // reads from the surface itself, never from clear epoxy floating in front of it.
          // duv_step marches P/n_layers.
          vec2 P = (Vt.xy / vz) * depth_uv * pom_graze;
          float Plen = length(P);
          if (Plen > pom_cap) P *= pom_cap / Plen;
          // Degenerate (head-on, or a zero-depth material) => skip the march and its taps.
          if (Plen > 1e-6) {
            vec2 duv_step = P / n_layers;
            float layer_d = 1.0 / n_layers;
            float cur_d = 0.0;
            float map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
            float prev_map_d = map_d;
            for (int i = 0; i < 64; i++) {  // ROUND 22: bound raised for the sqrt(drive) step count
              if (cur_d >= map_d || float(i) >= n_layers) {
                break;
              }
              uv -= duv_step;
              prev_map_d = map_d;
              map_d = 1.0 - hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
              cur_d += layer_d;
            }
            float after = map_d - cur_d;
            float before = prev_map_d - (cur_d - layer_d);
            float w = clamp(before / max(before - after, 1e-5), 0.0, 1.0);
            uv += duv_step * (1.0 - w);
            // ROUND 22 COVERAGE: the march ACTUALLY ran on this fragment (non-degenerate offset),
            // so the parallax tier displaced it. Gated on the global displacement setting too, so
            // "displacement OFF" reads as zero coverage.
            if (u_pbr_displacement != 0) {
              f_disp_cover = 1.0;
            }
          }
        }
        // PBR POLISH — inputs for the HEIGHT-FIELD SELF-SHADOW (owner defect 3: the relief reads
        // as "un bump map glorifie"). Sampled at the FINAL (parallax-corrected) uv so the shadow
        // belongs to the texel actually being shaded, and computed for BOTH displacement tiers:
        // tessellation moves the macro geometry but the map's micro relief still has to shadow
        // itself, otherwise the fine detail stays as flat as it was in the parallax tier.
        // fh_ms_uv is the POM's own depth scale = the UV distance a full height unit spans, so the
        // shadow ray has exactly the same slope the parallax offset assumes. Distance-gated: the
        // 6 taps only run near the camera, where relief is resolvable at all.
        float fh0 = 1.0;
        float fh_ms_uv = 0.0;
        if ((u_pbr_mode & 16) != 0 && u_pbr_height_scale > 0.0 && (u_pbr_bisect & 524288) == 0 &&
            length(v_fringe_rel) < 35.0) {
          // PBR POLISH #17: normalised, so the shadow ray and the occluder heights it compares
          // against live in the SAME material-scaled space the march assumes. On the shipped maps
          // this alone strengthens the contact shadow a lot: a map that only spanned 0.18 of the
          // range could never raise an occluder far enough above the ray to darken anything.
          fh0 = hnorm(textureLod(tex_PBR_H, uv, 0.0).r);
          // Same feature-scaled depth the march uses, so the shadow ray's slope matches the relief
          // it is casting from (it used to be the raw UV height scale, a different depth entirely).
          float fh_lambda_m;
          float fh_drive;
          fh_ms_uv = pom_depth_uv(fh_lambda_m, fh_drive);
        }
        // Normal map (bit 1) perturbs the SMOOTH normal => surface detail that shades
        // correctly as the realtime suns move (the fusion's whole point).
        vec3 Nm = N;
        // REOPEN #3 SHIMMER FIX: Toksvig widening FROM THE FITTED MIP. texture() samples
        // the normal map at the hardware-fitted mip (maps upload with glGenerateMipmap +
        // LINEAR_MIPMAP_LINEAR); mip-averaged normals SHORTEN, and that lost length IS the
        // sub-pixel normal variance the renormalize below would otherwise throw away —
        // exactly the high-relief sparkle. Captured (strength-scaled, so the relief slider
        // widens it too) into fnmip_var and added to the GGX alpha at the spec-AA site.
        float fnmip_var = 0.0;
        // Scaled, DC-REMOVED tangent-space surface gradient of this fragment (0 where no normal
        // map): reused below for the mean-preserving detail term.
        vec2 fg = vec2(0.0);
        if ((u_pbr_mode & 1) != 0 && u_pbr_debug != 7 && (u_pbr_bisect & 64) == 0) {
          vec3 nraw = texture(tex_PBR_N, uv).xyz * 2.0 - 1.0;
          // Toksvig variance is measured on the RAW sample. (It used to be measured AFTER the
          // strength scale, where length() saturates the 1.0 clamp for any relief above ~0.4 and
          // the whole spec-AA term silently died — exactly where shimmer is worst.)
          float fnlen = clamp(length(nraw), 1e-4, 1.0);
          // ROUND 22: the clamp was 0..3 while C++ feeds 3.0 * relief = 0..9, so the slider's grip
          // on the normal-map term died at relief 1.0. Raised to 12 so the whole 0..3 slider drives it.
          fnmip_var = ((1.0 - fnlen) / max(fnlen, 0.5)) * clamp(u_pbr_normal_strength, 0.0, 12.0);
          // ================= THE PLATE FIX (owner A/B relief 0 vs 2.5, 2026-07-24) =============
          // Work in SURFACE GRADIENT space (g = n.xy/n.z, the height-field slope) rather than
          // scaling n.xy and renormalising: scaling a gradient IS scaling the height field, the
          // physically meaningful "relief strength", and it makes the DC removal below exact at
          // any strength.
          // u_pbr_normal_dc is this material's MEAN gradient over the whole map. It is NOT zero:
          // measured on the shipped set, every map carries a systematic tilt (leafyground DC =
          // (+0.076, -0.227) in normal space => 61 deg of CONSTANT tilt once the relief slider
          // multiplies it by 7.5 at relief 2.5). A constant tilt of an entire material is not
          // relief — it re-aims the whole surface at/away from the sun, so the material reads
          // ~35-48% darker than the neighbouring surfaces that have no normal map, and it reads
          // DIFFERENTLY in each chunk because each chunk decodes it in its own UV frame. That is
          // precisely the owner's hard dark/light plates, and precisely why they scale with relief
          // and vanish at relief 0. Subtracting the DC makes the perturbation ZERO-MEAN: pure
          // relief, no net re-aim. Offline (shader-exact) on the grass at relief 2.5: chunk-to-
          // chunk brightness spread 61.4% -> 3.0%. Bit 8192 restores the raw map for the A/B.
          vec2 g = clamp(nraw.xy / max(nraw.z, 0.05), vec2(-4.0), vec2(4.0));
          if ((u_pbr_bisect & 8192) == 0) {
            g -= u_pbr_normal_dc;
          }
          // ROUND 22: +/-8 -> +/-24, the companion of the 0..12 strength clamp above (8 saturated
          // at relief ~1 for any gradient of interest, freezing the top of the slider).
          fg = clamp(g * u_pbr_normal_strength, vec2(-24.0), vec2(24.0));
          vec3 nmt = normalize(vec3(fg, 1.0));
          Nm = normalize(mat3(fTn, fBn, N) * nmt);
          // GLASS-PANE fix (owner preset report 2026-07-23): the old hard snap back to
          // the SMOOTH normal (`if (dot(Nm,gN)<0) Nm = N`) wiped the map grain over
          // whole grazing-angle patches — relief >1 tips many texels past the face
          // plane, and every highlight/reflection term there (NdH/NdV/Rf/Fresnel)
          // followed the flat polygon = the "glass sheet over the material". SLIDE the
          // perturbed normal back to just above the horizon instead: the below-horizon
          // component is removed but the tangential GRAIN survives.
          // OWNER PLAYTEST #8 (faceted grass): the horizon reference here was the PER-FACE
          // screen-space normal gN = cross(dFdx,dFdy), which is CONSTANT within a triangle and
          // JUMPS across edges — so this clamp injected a per-triangle discontinuity into Nm =>
          // exactly the hard triangular patches the owner saw (the base v_normal is otherwise
          // ~96% smooth per the offline [gda-facet] measurement). Clamp against the SMOOTH,
          // interpolated base normal N instead: continuous across faces => no facets, while
          // still keeping the perturbed normal out of the surface backside.
          float fnd = dot(Nm, N);
          if (fnd < 0.04) Nm = normalize(Nm + N * (0.04 - fnd));
        }
        vec4 T0p = texture(tex_T0, uv);
        vec3 albedo = pow(T0p.rgb, vec3(2.2));
        // REOPEN 2026-07-23 roughness CONVENTION AUDIT: the loader uploads _roughness as
        // plain linear GL_RGBA (LoaderStages make_map — no GL_SRGB internal format, no
        // hardware decode), so .r IS the authored PERCEPTUAL roughness; the GGX lobe uses
        // alpha = roughness^2 (industry squaring) below. Perceptual floor 0.045 doubles as
        // the specular-AA minimum (no mirror-edge fireflies).
        // REOPEN #2 MISSING-ROUGHNESS=ROUGH (industry rule): an absent _roughness map now
        // reads 0.9 — internet-pack bases without maps must NEVER get a smooth plastic sheen.
        float rough = (u_pbr_mode & 2) != 0 ? texture(tex_PBR_R, uv).r : 0.9;
        // REOPEN dielectric rule: most owner sets are height/normal/roughness only — a
        // MISSING _metallic map means metal = 0.0 (stone/straw/dirt are dielectrics,
        // constant F0 = 0.04; never assume metalness).
        float metal = (u_pbr_mode & 4) != 0 ? texture(tex_PBR_M, uv).r : 0.0;
        float ao = (u_pbr_mode & 8) != 0 ? texture(tex_PBR_AO, uv).r : 1.0;
        // REOPEN #3 BISECT VERDICT (mask 16): _specular read as RAW F0 (the test map's
        // linear mean is 0.217, p95 0.426 — 5-10x the 0.04 dielectric norm) inflated
        // Fresnel on every texel and the ambient-specular term turned that into the
        // plastic film. Industry (UE) convention: on a DIELECTRIC a "specular" map only
        // tunes F0 within [0, 0.08]; the raw map survives as a true specular COLOR only
        // where _metallic declares metalness.
        vec3 F0;
        if ((u_pbr_mode & 32) != 0 && (u_pbr_bisect & 16) == 0) {
          vec3 spec_raw = pow(texture(tex_PBR_S, uv).rgb, vec3(2.2));
          F0 = mix(min(spec_raw, vec3(0.08)), spec_raw, metal);
        } else {
          F0 = mix(vec3(0.04), albedo, metal);
        }
        float NdV = max(dot(Nm, Vv), 1e-4);
        // REOPEN geometric SPECULAR AA: widen the GGX alpha by the normal-map's screen-
        // space variance (Toksvig-style) so normal-mapped ground never sparkles. One-way:
        // only ever widens the lobe.
        rough = clamp(rough, 0.045, 1.0);
        float fa = rough * rough;  // alpha = perceptual roughness squared (industry)
        vec3 fnddx = dFdx(Nm);
        vec3 fnddy = dFdy(Nm);
        float fnvar = 0.25 * (dot(fnddx, fnddx) + dot(fnddy, fnddy));
        // REOPEN #3: screen-derivative variance (geometric edges) + Toksvig-from-mip
        // variance (sub-texel normal detail at the fitted mip) both widen the lobe;
        // perceptual min-rough 0.045 above stays the floor. One-way: only ever rougher.
        fa = clamp(fa + min(fnvar, 0.18) + min(fnmip_var, 0.35), 0.002, 1.0);
        float fa2 = fa * fa;
        // REOPEN roughness-aware FRESNEL ceiling (Fdez-Aguera): the grazing-angle limit is
        // max(1-roughness, F0), NOT 1.0 — a rough floor seen edge-on can no longer blow out
        // into the white mirror-edge sheen (the owner's "surcouche plastique" at ground +
        // extreme angles).
        vec3 Fceil = max(vec3(1.0 - rough), F0);
        // ===============================================================================
        // REOPEN #6 MATTE-DIELECTRIC DEFAULT (owner playtest #4 + 5-screenshot decomposition:
        // "Lighting-only" is GOOD, the glass appears ONLY when PBR is on => the glass IS the
        // specular / env-reflection term made VISIBLE on MATTE materials where it must not be).
        // Industry truth: a rough dielectric (stone/sand/grass/wood = all of village1) reflects
        // almost NOTHING — its microfacet lobe is so broad the peak radiance is negligible and
        // view-STABLE. So the ENTIRE specular contribution (direct GGX of both suns + the
        // ambient/env reflection) is driven toward ~0 as roughness rises: at rough >= ~0.60 the
        // surface is fully MATTE (no sheen, no camera-dependent highlight). Only genuinely SMOOTH
        // (rough < 0.30) or METALLIC texels keep a visible highlight. This is the visible-highlight
        // ENVELOPE riding ON TOP of the physical BRDF, NOT a replacement — the normal-mapped
        // DIFFUSE relief the owner LIKES (fdetail below) is untouched, so PBR-ON = Lighting-only
        // + depth, MINUS the gloss. Bisect bit 4096 = envelope OFF (device A/B killswitch proving
        // the matte path is active: the old glassy sheen returns when set).
        float matte_gate = max(1.0 - smoothstep(0.30, 0.60, rough), metal);
        if ((u_pbr_bisect & 4096) != 0) matte_gate = 1.0;
        // ===============================================================================
        // REOPEN OWNER ARCHITECTURE: BASE = the validated BAKED-MODULATION composite (the
        // fought-for object relief) — the baked influence ALWAYS remains; the PBR layer
        // only rides on top. Identical formula to the accepted pbr-OFF branch below, but
        // evaluated with the normal-MAP-perturbed Nm so material detail shades under the
        // realtime suns, plus a bounded micro/macro detail-relight ratio so the relief
        // stays alive inside fully-lit zones where the terminator smoothstep saturates.
        // ===============================================================================
        vec3 Mn = normalize(u_rt_moon_dir);
        // MACRO LIGHTING = GEOMETRY, MICRO DETAIL = THE MAP (owner A/B root cause, 2026-07-24).
        // This terminator drives fmod, the baked lit/shadow multiply, through a near-binary
        // smoothstep(0, 0.35) — feeding it the normal-MAPPED Nm let the map decide whether a
        // whole material region counts as LIT or as SHADOWED, so any systematic tilt in the map
        // (see the DC comment above) flipped entire regions between the lit and the shadow
        // multiplier: a hard plate with no geometric cause. The map's contribution belongs in the
        // bounded fdetail ratio below, not in the macro gate. Taking the terminator from the
        // smooth normal N also makes fmod the SAME expression as the accepted pbr-OFF branch,
        // which is the owner's acceptance criterion made structural: PBR ON == Lighting-only,
        // PLUS depth. Bit 16384 = legacy (terminator from Nm) for the device A/B.
        vec3 fNterm = ((u_pbr_bisect & 16384) != 0) ? Nm : N;
        float fterm_y = smoothstep(0.0, 0.35, dot(fNterm, L));
        float fterm_g = smoothstep(0.0, 0.35, dot(fNterm, Mn));
        float flit_y = fterm_y * sun_occ;
        float flit_g = fterm_g * moon_occ;
        float fw_y = clamp(u_rt_sun_elev, 0.0, 1.0);
        float fw_g = clamp(dot(u_rt_moon_color, vec3(1.0)), 0.0, 1.0) * clamp(u_rt_green_amp, 0.0, 2.0);
        // PBR POLISH: the DIRECT share of this fragment's lighting. Hoisted up from the _ao site
        // below (same expression, same value) so the new INDIRECT relief term can weight itself by
        // the complementary ambient share (1 - fdirw) — full effect exactly where the suns are not.
        float fdirw = clamp(flit_y * fw_y + flit_g * fw_g, 0.0, 1.0);
        // PBR POLISH — HEIGHT-FIELD SELF-SHADOW, one march per analytic sun (owner defect 3).
        // The light directions go into the SAME tangent-UV frame the POM marches in, so the
        // shadow the relief casts lies along the same axis the parallax already shifts.
        float fms_y = 1.0;
        float fms_g = 1.0;
        if (fh_ms_uv > 0.0) {
          fms_y = pbr_micro_shadow(uv, fh0, vec3(dot(L, fTuv), dot(L, fBuv), dot(L, N)), fh_ms_uv);
          fms_g =
              pbr_micro_shadow(uv, fh0, vec3(dot(Mn, fTuv), dot(Mn, fBuv), dot(Mn, N)), fh_ms_uv);
        }
        vec3 fsun_ch = u_rt_sun_color / max(dot(u_rt_sun_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        vec3 fmoon_ch = u_rt_moon_color / max(dot(u_rt_moon_color, vec3(0.299, 0.587, 0.114)), 1e-3);
        const vec3 FUS_COOL = vec3(0.896, 1.001, 1.265);
        vec3 flit_mul_y = u_rt_lit_boost * mix(vec3(1.0), fsun_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 flit_mul_g = u_rt_lit_boost * mix(vec3(1.0), fmoon_ch, clamp(u_rt_tint_lit, 0.0, 1.0));
        vec3 fshd_mul = u_rt_shadow_mul * mix(vec3(1.0), FUS_COOL, clamp(u_rt_tint_shadow, 0.0, 1.0));
        vec3 fmod = mix(vec3(1.0), mix(fshd_mul, flit_mul_y, flit_y), fw_y) *
                    mix(vec3(1.0), mix(fshd_mul, flit_mul_g, flit_g), fw_g);
        // FUSED-CONTRAST REBALANCE (owner preset report 2026-07-23: Fusion modes read
        // "très contrasté"). The baked colour already carries the TOD contrast; fmod
        // multiplies the realtime lit/shadow spread on top AND the GGX sun specular then
        // adds sparkle on the lit side — a double contrast apply vs the accepted pbr-OFF
        // baked-modulation look (which applies fmod exactly once with no added spec).
        // Compress fmod toward 1 (gamma 0.70) in the FUSED branch only, so the fused
        // overall contrast matches the accepted look and the specular ADDS sparkle
        // instead of stacking another lit/shadow multiply. Bisect 2048 = compress off
        // (device A/B measurement of exactly this rebalance).
        if ((u_pbr_bisect & 2048) == 0) fmod = pow(max(fmod, vec3(0.0)), vec3(0.70));
        if ((u_pbr_bisect & 512) != 0) fmod = vec3(1.0);  // bisect: baked-modulation off
        // Bounded perturbed/smooth N.L ratio (=1 for a flat map => map-free pixels match
        // the accepted baked-modulation look exactly).
        // MEAN-PRESERVING detail. dot(N,L) + g.(T.L, B.L) is the UN-normalised (bump) response of
        // the perturbed surface — identical to dot(Nm,L)/nmt.z, i.e. the same relief WITHOUT the
        // 1/sqrt(1+|g|^2) renormalisation. That renormalisation is what made a normal-mapped
        // surface systematically DARKER than its unmapped neighbour (Jensen: the average of the
        // normalised cosine is below the cosine of the average), which is the second half of the
        // plates — the material BORDER step, visible wherever a mapped ground texture meets an
        // unmapped one (vil1-jng-leafyground vs -hitweak, vil-beach-01 vs -01path: only 8 of 716
        // village1 texture bindings carry maps at all). Because fg is zero-mean, the mean of this
        // term is EXACTLY the smooth-normal response, for any light direction and any frame:
        // relief with no brightness step. Offline (shader-exact) on the grass at relief 1.0:
        // material-border delta -19.5% -> +1.4%, and the detail amplitude RISES 21.5% -> 32.0%.
        // fg == 0 on map-free pixels => fdt == 1 exactly => pbr-OFF look preserved bit for bit.
        float fndl_y = ((u_pbr_bisect & 16384) != 0)
                           ? dot(Nm, L)
                           : (dot(N, L) + fg.x * dot(fTn, L) + fg.y * dot(fBn, L));
        float fndl_g = ((u_pbr_bisect & 16384) != 0)
                           ? dot(Nm, Mn)
                           : (dot(N, Mn) + fg.x * dot(fTn, Mn) + fg.y * dot(fBn, Mn));
        // PBR POLISH — OWNER PLAYTEST #17 REBALANCE: "TRÈS CONTRASTÉ À LA LUMIÈRE (mais quand même
        // plat), TRÈS PLAT À L'OMBRE." Both halves of that sentence are one imbalance. The DIRECT
        // N.L detail ratio was allowed a [0.45, 1.9] swing — a factor of 4.2 between the darkest
        // and brightest texel of the SAME material under the SAME sun — while every actual DEPTH
        // cue was ~0 (cavity did not exist, the ambient ratio measured 0.960..0.996, the
        // self-shadow reached >5% on only 0-17% of texels). High-contrast N.L noise is not depth:
        // it is the same flat surface lit harder. So the direct term gives budget back — a [0.60,
        // 1.55] swing with a larger softening constant — and the budget goes into the cues that
        // actually read as geometry (the cavity below, the now material-scaled self-shadow, and
        // the band-limited real displacement in the tess stage). fg == 0 on map-free pixels still
        // makes this EXACTLY 1.0, so the accepted pbr-OFF look is untouched either way.
        // Bisect 8388608 = the legacy wide clamp back, for the live A/B.
        float fdt_lo = ((u_pbr_bisect & 8388608) != 0) ? 0.45 : 0.60;
        float fdt_hi = ((u_pbr_bisect & 8388608) != 0) ? 1.9 : 1.55;
        float fdt_soft = ((u_pbr_bisect & 8388608) != 0) ? 0.30 : 0.38;
        float fdt_y =
            clamp((max(fndl_y, 0.0) + fdt_soft) / (max(dot(N, L), 0.0) + fdt_soft), fdt_lo, fdt_hi);
        float fdt_g = clamp((max(fndl_g, 0.0) + fdt_soft) / (max(dot(N, Mn), 0.0) + fdt_soft),
                            fdt_lo, fdt_hi);
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #16 DEFECT 2: "completement PLAT dans l'ombre / la ou le
        // soleil ne tape pas". Traced to the exact line: in cast shadow sun_occ = moon_occ = 0, so
        // BOTH mix() weights below collapse to zero and fdetail becomes EXACTLY 1.0 — the normal
        // map stops contributing at all — while the only other normal-dependent term (famb_spec)
        // is driven to zero by matte_gate on every rough dielectric. A shadowed fragment was
        // literally baked x constant x _ao: no normal dependence anywhere in the expression, hence
        // no depth. Relief that only exists in direct sun is not relief.
        // The industry answer is the one the owner named: the INDIRECT term must see the perturbed
        // surface too — irradiance E(n) evaluated with the normal-mapped normal (SH / IBL /
        // hemisphere, whichever ambient model is live) instead of a direction-free constant, with
        // _ao as the contact term (fao_mul below already weights _ao onto exactly this share).
        // Expressed as the same bounded RATIO fdt_y/fdt_g use — E(Nm) / E(N) — so it multiplies the
        // baked composite instead of replacing it (the owner's standing rule: the baked influence
        // always remains) and a map-free fragment gets exactly 1.0, i.e. the accepted
        // Lighting-only look survives bit for bit. E varies slowly and smoothly with direction, so
        // the ratio stays near 1 and carries no brightness step against an unmapped neighbour.
        // Weighted by the AMBIENT SHARE (1 - fdirw): full strength in shadow and at night, fading
        // out where a sun already carries the relief, so full-sun pixels are untouched.
        // Bisect bit 262144 = ambient relief off (the device A/B for this term).
        float fdt_amb = 1.0;
        if ((u_pbr_bisect & 262144) == 0 && dot(fg, fg) > 0.0) {
          const vec3 FUS_LUMA = vec3(0.299, 0.587, 0.114);
          float famb_ls = dot(rt_amb_eval(N), FUS_LUMA);
          float famb_lb = dot(rt_amb_eval(Nm), FUS_LUMA);
          fdt_amb = clamp((max(famb_lb, 0.0) + 0.02) / (max(famb_ls, 0.0) + 0.02), 0.45, 1.9);
        }
        // ===================================================================================
        // PBR POLISH — OWNER PLAYTEST #17, THE "FLAT IN SHADOW" FIX. The ratio above is the term
        // that was SUPPOSED to do this and provably cannot (see pbr_cavity()'s header: our ambient
        // is near direction-invariant, so the ratio measures 0.960..0.996 across every shipped
        // material). This is the direction-INDEPENDENT replacement: a cavity / micro-AO read
        // straight out of the height field, which has exactly the same strength in a cast shadow,
        // in the dark, and at noon.
        // WEIGHTING: full strength on the AMBIENT share (1 - fdirw) — that share IS the whole of a
        // shadowed fragment, which is where the owner sees the flatness — and PBR_CAV_DIR of it in
        // direct sun, because a crevice occludes bounce light there too but the sun's own N.L and
        // self-shadow already carry the relief. So the sunlit look barely moves while the shaded
        // look gains the depth it never had.
        // The _ao MAP, when a material ships one, is the same physical quantity at a coarser scale
        // and already rides this same ambient share through fao_mul below; the cavity is the
        // per-texel detail term that every shipped material can produce from its height map (none
        // of the 7 bundled materials ships an _ao map, which is precisely why an _ao-only ambient
        // occlusion left them flat).
        // Bisect bit 2097152 = cavity off (the live A/B for exactly this fix).
        // ===================================================================================
        float fcav = 1.0;
        if ((u_pbr_mode & 16) != 0 && (u_pbr_bisect & 2097152) == 0) {
          fcav = pbr_cavity(uv);
        }
        const float PBR_CAV_DIR = 0.35;  // how much of the cavity survives in full direct sun
        float fcav_mul = mix(1.0, fcav, mix(PBR_CAV_DIR, 1.0, 1.0 - fdirw));
        // fms_* (height-field self-shadow) rides on each sun's share: a crevice the relief itself
        // occludes cannot receive that sun. It is deliberately NOT applied to the ambient share —
        // skylight reaches into a crevice from every direction, and the cavity above is that term.
        float fdetail = mix(1.0, fdt_y * fms_y, fw_y * sun_occ) *
                        mix(1.0, fdt_g * fms_g, clamp(fw_g, 0.0, 1.0) * moon_occ) *
                        mix(1.0, fdt_amb, 1.0 - fdirw) * fcav_mul;
        if ((u_pbr_bisect & 256) != 0) fdetail = 1.0;  // bisect: detail-relight ratio off
        // _ao = material micro-occlusion: full strength on the ambient/shadowed share,
        // relaxed where the direct sun dominates (AO never occludes the suns).
        float fao_mul = mix(ao, 1.0, 0.55 * fdirw);
        vec3 fbase_disp = max(fragment_color.rgb * T0p.rgb, vec3(0.0)) * fmod * fdetail * fao_mul;
        vec3 fbase_lin = pow(fbase_disp, vec3(2.2));
        // REOPEN ENERGY CONSERVATION + SPECULAR OCCLUSION: kd = (1-F)(1-metal) on the baked
        // diffuse so the specular never ADDS free energy on top of the full baked; and the
        // BAKED-DETAIL luminance gates the specular — a crevice the baked lighting says is
        // dark cannot host a bright highlight (shiny pits read as plastic). _ao joins in.
        // fragment_color is the TOD LUT x2 (lit ~0.5-1.0, crevices < ~0.2).
        float fbklum = dot(fragment_color.rgb, vec3(0.299, 0.587, 0.114));
        float fspecocc = ao * smoothstep(0.05, 0.45, fbklum);
        // REOPEN #3 fix: kd is the INDUSTRY constant (1 - F0)(1 - metal) (UE/Frostbite
        // diffuse). The old view-dependent (1 - Fenv) grayed rough surfaces seen edge-on
        // (the ground at grazing) — a film NOT scaled by the specular slider, which is
        // exactly the owner's "sheen survives specular=0" datapoint.
        fbase_lin *= ((u_pbr_bisect & 8) != 0 ? vec3(1.0) : (vec3(1.0) - F0 * fspecocc)) *
                     (1.0 - metal);
        // BOTH analytic suns, Cook-Torrance with the HEIGHT-CORRELATED SMITH VISIBILITY
        // term (REOPEN: the old separable Schlick G + naive F was exactly the grazing-
        // sheen bug; Vis contains the 1/(4 NdV NdL) denominator). Cast shadows kill each
        // sun's specular via its own occ; the yellow sun also night-fades (fw_y).
        vec3 fspec_direct = vec3(0.0);
        for (int i = 0; i < 2; i++) {
          if ((u_pbr_bisect & (i == 0 ? 1 : 2)) != 0) {
            continue;  // bisect: this sun's GGX specular zeroed
          }
          vec3 Li = (i == 0) ? L : Mn;
          vec3 lc = (i == 0) ? u_rt_sun_color * fw_y : u_rt_moon_color;
          // PBR POLISH: the height-field self-shadow gates the highlight too — a texel the relief
          // occludes cannot host a specular lobe from that sun (a lit highlight sitting inside a
          // crevice is the classic tell that "depth" is only a shaded bump).
          float vis_i = (i == 0) ? (sun_occ * fms_y) : (moon_occ * fms_g);
          if (dot(lc, vec3(1.0)) <= 1e-5 || vis_i <= 1e-4) {
            continue;
          }
          vec3 Hh = normalize(Li + Vv);
          float NdL = max(dot(Nm, Li), 0.0);
          if (NdL <= 0.0) {
            continue;
          }
          float NdH = max(dot(Nm, Hh), 0.0);
          float VdH = max(dot(Vv, Hh), 0.0);
          float dd = NdH * NdH * (fa2 - 1.0) + 1.0;
          float D = fa2 / (3.14159265 * dd * dd);
          float gv = NdL * sqrt(NdV * NdV * (1.0 - fa2) + fa2);
          float gl = NdV * sqrt(NdL * NdL * (1.0 - fa2) + fa2);
          float Vis = 0.5 / max(gv + gl, 1e-4);
          vec3 F = F0 + (Fceil - F0) * pow(1.0 - VdH, 5.0);
          fspec_direct += (D * Vis * F) * lc * NdL * vis_i;
        }
        // AMBIENT SPECULAR — PROBES = the coherence source (REOPEN): the prefiltered local
        // probe cube sampled at the ROUGHNESS MIP (8x8 cube => 4-level chain; lod = rough*3
        // lands roughness 1.0 on the blurriest 1x1 mip), analytic SH/IBL env as the
        // no-probe fallback. Either way the sample CONVERGES to the ambient IRRADIANCE as
        // roughness rises — a rough ground reflects a blurry env, never the sharp sun-glow
        // lobe (the old sharp-Rf eval was the other half of the ground sheen).
        // PBR POLISH: same selector as before, now via the shared rt_amb_eval() the new indirect
        // relief term also uses — one definition of "the ambient irradiance in direction n", so
        // the diffuse and the specular can never drift apart. Value here is unchanged.
        vec3 famb_base = clamp(rt_amb_eval(Nm), 0.0, 1.0);
        vec3 Rf = reflect(-Vv, Nm);
        vec3 fenv_sharp;
        if (u_rt_probe_on != 0 && u_rt_probe_reflections != 0) {
          fenv_sharp = textureLod(u_rt_probe_cube, Rf, rough * 3.0).rgb *
                       clamp(u_rt_probe_strength, 0.0, 1.0);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 1) {
          fenv_sharp = rt_sh_ambient(Rf);
        } else if (u_rt_ambient_on != 0 && u_rt_ambient_model == 2) {
          fenv_sharp = rt_ibl_ambient(Rf);
        } else {
          fenv_sharp = famb_base;
        }
        // REOPEN #6 VIEW-STABILITY: collapse the sharp view-dependent reflection (Rf, the
        // camera-dependent "highlight shifts with the camera" the owner saw on rock/sand) to the
        // view-INDEPENDENT irradiance (famb_base, from the perturbed Nm) by rough ~0.50 — well
        // before the matte_gate finishes at 0.60 — so no camera-dependent env sheen survives on
        // any rough surface, even inside the 0.30-0.60 transition band.
        vec3 famb_env = mix(fenv_sharp, famb_base, smoothstep(0.12, 0.50, rough));
        // REOPEN #3 fix — THE bisect-identified culprit (mask 4: zeroing this term halved
        // the wall luma; the plastic film lived here). The raw Fresnel multiply (famb_env *
        // Fenv, grazing ceiling max(1-rough, F0)) is replaced by the industry SPLIT-SUM env
        // BRDF (Karis mobile approximation): famb_spec = env * (F0*A + B), A/B folding the
        // GGX lobe energy over (roughness, NdV). Rough ground at grazing now reflects ~5%
        // of the ambient instead of 30-45% — bounded by construction, no mirror-edge film.
        vec4 kr = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
        float ka004 = min(kr.x * kr.x, exp2(-9.28 * NdV)) * kr.x + kr.y;
        vec2 kAB = vec2(-1.04, 1.04) * ka004 + vec2(kr.z, kr.w);
        vec3 famb_spec = famb_env * (F0 * kAB.x + kAB.y);
        if ((u_pbr_bisect & 4) != 0) famb_spec = vec3(0.0);  // bisect: ambient/IBL specular off
        // EMISSIVE (bit 64): unlit, added on top — glows in full shadow / at night.
        vec3 emissive = ((u_pbr_mode & 64) != 0 && (u_pbr_bisect & 32) == 0)
                            ? pow(texture(tex_PBR_E, uv).rgb, vec3(2.2)) *
                                  max(u_pbr_emissive_str, 0.0)
                            : vec3(0.0);
        // REOPEN #6: matte_gate drives the WHOLE specular (direct GGX + env reflection) to ~0 on
        // rough dielectrics (independent of the slider — a rough surface is matte even at spec=1),
        // then the low-default slider trims what remains on genuinely smooth/metal texels.
        vec3 fspec_sum = (fspec_direct + famb_spec) * fspecocc * matte_gate * max(u_pbr_spec_intensity, 0.0);
        vec3 flit = fbase_lin + fspec_sum + emissive;
        // Same C1 soft-shoulder tone map + far crossfade to baked as the rt composite —
        // the added specular can never clip the baked base to white.
        if ((u_pbr_bisect & 1024) == 0) {
          const float RT_KNEE = 0.8;
          vec3 fe = exp(-max(flit - vec3(RT_KNEE), vec3(0.0)) / (1.0 - RT_KNEE));
          flit = mix(flit, vec3(1.0) - (1.0 - RT_KNEE) * fe, step(vec3(RT_KNEE), flit));
        } else {
          flit = min(flit, vec3(1.0));  // bisect: shoulder off, hard clamp
        }
        vec3 fdisp = pow(max(flit, vec3(0.0)), vec3(1.0 / 2.2));
        float ffar_rng = u_rt_shadow_range > 1.0 ? u_rt_shadow_range : 150.0;
        float ffar_t = smoothstep(ffar_rng * 0.82, ffar_rng * 1.05, length(v_fringe_rel));
        vec3 fbaked = max(fragment_color.rgb * T0.rgb, vec3(0.0));
        color.rgb = mix(fdisp, fbaked, ffar_t);
        // Debug viz (default colored render untouched at u_pbr_debug==0).
        if (u_pbr_debug == 2) {
          color.rgb = N * 0.5 + 0.5;
        } else if (u_pbr_debug == 3) {
          color.rgb = Nm * 0.5 + 0.5;
        } else if (u_pbr_debug == 4) {
          color.rgb = vec3(rough);
        } else if (u_pbr_debug == 5) {
          color.rgb = pow(max(fspec_sum, vec3(0.0)), vec3(1.0 / 2.2));
        } else if (u_pbr_debug == 6) {
          color.rgb = vec3(ao);
        } else if (u_pbr_debug == 18) {
          color.rgb = pow(max(emissive, vec3(0.0)), vec3(1.0 / 2.2));
        } else if (u_pbr_debug == 20) {
          // REOPEN#9 tangent-fallback coverage viz: RED = fragment fell back to a normal-derived
          // continuous basis (v_tangent degenerate/unbound), GREEN = per-vertex MikkTSpace tangent.
          // The screen-space-derivative FACET source is gone in BOTH branches; this measures how much
          // of the visible ground actually carries a valid uploaded per-vertex tangent on THIS device
          // (offline grass_bake can't see a GL upload/bind gap — this can). Screenshot + red-fraction.
          color.rgb = vec3(f_tan_fb, 1.0 - f_tan_fb, 0.0);
        } else if (u_pbr_debug == 21) {
          // PBR POLISH viz: HEIGHT-FIELD SELF-SHADOW (owner defect 3). White = fully lit relief,
          // dark = a texel the surface's own height field occludes from the yellow sun. A flat
          // white screen here means the relief casts nothing = "glorified bump map".
          color.rgb = vec3(fms_y);
        } else if (u_pbr_debug == 22) {
          // PBR POLISH viz: INDIRECT (ambient) RELIEF ratio (owner defect 2), remapped around
          // 0.5 = 1.0. A flat grey screen in shadow means the shadowed surface is FLAT.
          color.rgb = vec3(clamp(fdt_amb * 0.5, 0.0, 1.0));
        } else if (u_pbr_debug == 23) {
          // PBR POLISH #17 viz: the HEIGHT-FIELD CAVITY / micro-AO (the flat-in-shadow fix),
          // remapped so 0.5 = 1.0 (no change), darker = crevice, brighter = ridge. Unlike viz 22
          // this one must show STRUCTURE even on a fragment in full cast shadow — a flat grey
          // screen there is the defect, and this is the term that fixes it.
          color.rgb = vec3(clamp(fcav * 0.5, 0.0, 1.0));
        }
