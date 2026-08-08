// ===================================================================================================
// Grecharged-materials-modern-parity — MODERN MATERIAL STACK, shading block.
//
// COMPANION CHUNK, appended verbatim right after "pbr_fused.glsl" by Shader.cpp's include expander,
// so it runs INSIDE the same `if (u_pbr_mode != 0) { ... }` block in all four world programs
// (tfrag3, etie_base, tie_wind, shrub) and every local the fused chunk built is still in scope.
//
// ---- CONTRACT (what this chunk reads out of pbr_fused.glsl's scope) --------------------------------
//   N Nm Vv L Mn            smooth normal, normal-mapped normal, view, sun, moon (all unit, world)
//   uv                      the PARALLAX-CORRECTED texture coordinate (so every map below lines up
//                           with the displacement the owner already validated)
//   albedo rough metal ao   linear base colour and the three scalar channels
//   F0 NdV fa fa2 Fceil     Fresnel base, N.V, GGX alpha and alpha^2, roughness-aware Fresnel ceiling
//   Rf                      reflect(-Vv, Nm), the env-specular direction
//   fTn fBn                 the tangent frame the normal map is decoded in (anisotropy needs it)
//   sun_occ moon_occ        cast-shadow visibility per sun
//   fw_y fw_g fms_y fms_g   per-sun energy weight and height-field self-shadow
//   fdirw                   this fragment's DIRECT share of lighting (1 - it = the ambient share)
//   matte_gate fspecocc     the accepted matte-dielectric envelope and the baked specular occlusion
//   fbase_lin fspec_direct  the composed diffuse base and the direct GGX sum, LINEAR, pre-tone-map
//   famb_spec famb_env      the split-sum environment specular and the environment radiance it used
//   famb_base               view-independent ambient irradiance at Nm
//   emissive                the unlit additive term
//   fbaked ffar_t           the far-distance crossfade target and its weight
//   color                   the fragment output this chunk may rewrite
//
// ---- OFF == STOCK, STRUCTURALLY -------------------------------------------------------------------
// The whole body sits under `if (u_mm_flags != 0 && u_pbr_debug == 0)`. u_mm_flags is
// (this material's authored capability bits) AND (the global master), resolved C++-side, so:
//   * master off                       -> 0 -> nothing below executes, `color` keeps the value the
//                                              accepted fused path wrote. Not "close to stock": the
//                                              same instruction wrote it.
//   * master on, material not opted in -> 0 -> same, per material. Opt-in is per material by design.
//   * a --pbr-less build               -> OG_PBR undefined -> the fused chunk itself is not compiled
//                                              and this text is never even spliced in (Shader.cpp
//                                              guards the companion table with OG_FEAT_PBR).
// The `u_pbr_debug == 0` half of the gate keeps the fused chunk's own viz modes (2..23) intact — a
// debug view must show the term it names, not that term plus a new layer.
// ===================================================================================================
        if (u_mm_flags != 0 && u_pbr_debug == 0) {
          float mm_specint = max(u_pbr_spec_intensity, 0.0);

          // ---- SUBSURFACE THICKNESS -----------------------------------------------------------
          // 1 = thin (light gets through), 0 = optically thick. From <tex>_thickness.png when the
          // material ships one (bit 32), else the per-material scalar. Read at the parallax-corrected
          // uv like every other map, so a backlit leaf glows through the same texel the relief carved.
          float mm_th = ((u_mm_flags & 32) != 0) ? texture(tex_PBR_TH, uv).r
                                                 : clamp(u_mm_sss2.x, 0.0, 1.0);

          // ---- ANISOTROPY: the two lobe widths and the rotated tangent frame --------------------
          bool mm_aniso_on = (u_mm_flags & 4) != 0 && abs(u_mm_aniso.x) > 1e-3;
          float mm_at = fa, mm_ab = fa;
          vec3 mm_Ta = fTn, mm_Ba = fBn;
          if (mm_aniso_on) {
            float an = clamp(u_mm_aniso.x, -0.95, 0.95);
            float aspect = sqrt(1.0 - 0.9 * abs(an));
            float wide = max(fa / max(aspect, 1e-3), 1e-4);
            float narrow = max(fa * aspect, 1e-4);
            // Positive = the highlight stretches ACROSS the tangent (brushed metal turned on a lathe);
            // negative stretches along it. Swapping the pair is the whole difference.
            mm_at = (an >= 0.0) ? wide : narrow;
            mm_ab = (an >= 0.0) ? narrow : wide;
            float ca = cos(u_mm_aniso.y), sa = sin(u_mm_aniso.y);
            vec3 t_rot = fTn * ca + fBn * sa;
            mm_Ta = normalize(t_rot - Nm * dot(Nm, t_rot));  // re-orthonormalise against the shading normal
            mm_Ba = cross(Nm, mm_Ta);
          }

          // ---- CLEARCOAT: lobe width -----------------------------------------------------------
          bool mm_coat_on = (u_mm_flags & 2) != 0 && u_mm_coat.x > 1e-3;
          float mm_ccw = clamp(u_mm_coat.x, 0.0, 1.0);
          // Floor 0.05, not 0.03: the coat lobe's peak D goes as 1/alpha^2, so a mirror-smooth coat
          // concentrates its energy into a sub-pixel highlight that aliases into sparkle under
          // motion. 0.05 keeps the lobe tight enough to read as lacquer and wide enough to survive
          // a 30 fps handheld pan.
          float mm_ccr = clamp(u_mm_coat.y, 0.05, 1.0);
          float mm_cca2 = (mm_ccr * mm_ccr) * (mm_ccr * mm_ccr);

          bool mm_sss_on = (u_mm_flags & 1) != 0 && u_mm_sss.a > 1e-4;
          vec3 mm_sc = max(u_mm_sss.rgb, vec3(0.0));  // scattering colour, linear
          float mm_ss = max(u_mm_sss.a, 0.0);
          float mm_sp = max(u_mm_sss2.y, 1.0);
          float mm_sd = clamp(u_mm_sss2.z, 0.0, 1.0);
          float mm_sw = clamp(u_mm_sss2.w, 0.0, 1.0);

          vec3 mm_aniso_delta = vec3(0.0);  // anisotropic lobe MINUS the isotropic one it replaces
          vec3 mm_coat_spec = vec3(0.0);
          vec3 mm_trans = vec3(0.0);  // subsurface: transmission + terminator wrap, always additive

          // ---- THE TWO ANALYTIC SUNS -----------------------------------------------------------
          // Same pair, same colours, same visibilities and the same bisect killswitches as the fused
          // chunk's Cook-Torrance loop — anything else and the new lobes would be lit by a different
          // sun than the one the owner sees.
          for (int i = 0; i < 2; i++) {
            if ((u_pbr_bisect & (i == 0 ? 1 : 2)) != 0) {
              continue;
            }
            vec3 Li = (i == 0) ? L : Mn;
            vec3 lc = (i == 0) ? u_rt_sun_color * fw_y : u_rt_moon_color;
            float vis_i = (i == 0) ? (sun_occ * fms_y) : (moon_occ * fms_g);
            if (dot(lc, vec3(1.0)) <= 1e-5 || vis_i <= 1e-4) {
              continue;
            }
            vec3 Hh = normalize(Li + Vv);
            float NdL = max(dot(Nm, Li), 0.0);
            float NdH = max(dot(Nm, Hh), 0.0);
            float VdH = max(dot(Vv, Hh), 0.0);

            // ---- SUBSURFACE SCATTERING (the owner's headline channel) --------------------------
            // TRANSMISSION, the DICE/Frostbite fast model: light that entered the far side of a thin
            // surface leaves toward the viewer. The transmission vector is -L bent by the surface
            // normal (mm_sd), which is what makes the glow follow the relief instead of being a flat
            // view-vs-light dot; the power controls how tight the back-light halo is. This is the term
            // that makes straw, leaves and wax read as translucent when the sun is BEHIND them, and it
            // exists in no other part of this pipeline: everything else here is reflection.
            if (mm_sss_on) {
              vec3 Lt = normalize(-(Li + Nm * mm_sd));
              float tdot = pow(clamp(dot(Vv, Lt), 0.0, 1.0), mm_sp);
              mm_trans += lc * mm_sc * (tdot * mm_th * mm_ss * vis_i);
              // WRAP: light bleeding a little past the geometric terminator, because scattering
              // carries energy sideways under the surface. Kept ADDITIVE and bounded by (wrap - clamped
              // N.L) so it can only ever soften the terminator, never darken the accepted baked base.
              if (mm_sw > 1e-4) {
                float ndl_raw = dot(Nm, Li);
                float wrapped = clamp((ndl_raw + mm_sw) / (1.0 + mm_sw), 0.0, 1.0);
                float direct = clamp(ndl_raw, 0.0, 1.0);
                mm_trans += lc * mm_sc * albedo *
                            (max(wrapped - direct, 0.0) * mm_ss * 0.5 * mm_th * vis_i);
              }
            }

            if (NdL <= 0.0) {
              continue;  // the two reflective lobes below need a front-facing light; SSS does not.
            }

            // ---- ANISOTROPIC GGX (delta against the isotropic lobe the fused chunk already added) --
            if (mm_aniso_on) {
              float ToH = dot(mm_Ta, Hh), BoH = dot(mm_Ba, Hh);
              float ToV = dot(mm_Ta, Vv), BoV = dot(mm_Ba, Vv);
              float ToL = dot(mm_Ta, Li), BoL = dot(mm_Ba, Li);
              float Da = mm_ggx_d_aniso(NdH, ToH, BoH, mm_at, mm_ab);
              float Va = mm_ggx_vis_aniso(NdL, NdV, ToV, BoV, ToL, BoL, mm_at, mm_ab);
              float iso = mm_ggx_dvis_iso(NdH, NdL, NdV, fa2);
              vec3 F = F0 + (Fceil - F0) * pow(1.0 - VdH, 5.0);
              mm_aniso_delta += ((Da * Va - iso) * F) * lc * NdL * vis_i;
            }

            // ---- CLEARCOAT LOBE ------------------------------------------------------------------
            // Evaluated on the SMOOTH normal N, not on Nm: a coat is a film lying over the micro
            // relief, so it does not inherit the normal map's grain — that difference is exactly what
            // makes a coated surface read as "wet/lacquered" rather than "shinier".
            if (mm_coat_on) {
              float cNdL = max(dot(N, Li), 0.0);
              if (cNdL > 0.0) {
                float cNdH = max(dot(N, Hh), 0.0);
                float LdH = max(dot(Li, Hh), 0.0);
                float Fc = mm_coat_fresnel(LdH);
                mm_coat_spec += vec3(mm_coat_dvis(cNdH, LdH, mm_cca2) * Fc * mm_ccw) * lc * cNdL * vis_i;
              }
            }
          }

          // ---- AMBIENT TRANSMISSION -------------------------------------------------------------
          // A leaf glows in open shade too: skylight enters the far side just like sunlight does. This
          // is the term that keeps SSS from being a sun-only trick — it has the same strength in a cast
          // shadow, which is precisely the failure mode earlier PBR rounds kept hitting.
          if (mm_sss_on) {
            mm_trans += famb_base * mm_sc * (mm_th * mm_ss * clamp(u_mm_coat.z, 0.0, 1.0));
          }

          // ---- SPECULAR + HORIZON OCCLUSION on the environment term ------------------------------
          vec3 mm_env = famb_spec;
          float mm_so = 1.0;
          if ((u_mm_flags & 16) != 0) {
            mm_so = mm_spec_occlusion(NdV, ao, rough, Rf, N);
            mm_env *= mm_so;
          }

          // ---- ENERGY COMPENSATION (Kulla-Conty multiple scatter) ---------------------------------
          // A single-scatter GGX loses the energy of every microfacet bounce after the first; the loss
          // grows with roughness and is most visible on metal, which reads dark and dead. kAB is the
          // split-sum DFG the fused chunk already computed, so Ess = kAB.x + kAB.y is this lobe's
          // directional albedo and the compensation is exact in the same approximation.
          vec3 mm_Fms = vec3(1.0);
          if ((u_mm_flags & 8) != 0) {
            // Ess floored at 0.05 and the whole factor capped at 2x. The uncapped form is 1 + F0
            // (1/Ess - 1), and the split-sum Ess collapses toward 0 at grazing incidence on a very
            // rough surface — exactly where a metal's F0 ~ 1 would turn a legitimate correction into
            // a 20x multiplier on a specular lobe, i.e. a firefly. Energy compensation should give
            // back the bounce energy single-scatter GGX drops (at most ~2x for real materials),
            // never manufacture more.
            float Ess = clamp(kAB.x + kAB.y, 0.05, 1.0);
            mm_Fms = min(vec3(1.0) + F0 * (1.0 / Ess - 1.0), vec3(2.0));
          }

          // ---- RECOMPOSE -------------------------------------------------------------------------
          // Same gating chain the fused chunk applies to its own specular sum, so the accepted
          // matte-dielectric envelope and the baked specular occlusion still govern everything that
          // rides the base layer. The CLEARCOAT deliberately bypasses matte_gate: the envelope exists
          // to stop a ROUGH surface acting glossy, and a coat is by definition a smooth layer with its
          // own roughness. It still respects fspecocc (a crevice the baked lighting calls dark cannot
          // host a highlight) and the owner's SPECULAR INTENSITY slider.
          vec3 mm_spec_sum =
              (fspec_direct + mm_aniso_delta + mm_env) * mm_Fms * fspecocc * matte_gate * mm_specint;
          vec3 mm_coat_sum = mm_coat_spec * fspecocc * mm_specint;
          // Energy the coat reflects is energy the base layer never receives.
          float mm_coat_atten = mm_coat_on ? (1.0 - mm_ccw * mm_coat_fresnel(NdV)) : 1.0;

          vec3 mm_lin = fbase_lin * mm_coat_atten + mm_spec_sum + mm_coat_sum + emissive + mm_trans;
          mm_lin *= max(u_mm_exposure, 0.0);

          // Tone map. The DEFAULT branch is the accepted C1 soft shoulder, transcribed from the fused
          // chunk verbatim so the composite lands on the same curve the owner's look was judged
          // against; the filmic curve is opt-in only (bit 64).
          if ((u_mm_flags & 64) != 0) {
            mm_lin = mm_tonemap_aces(mm_lin);
          } else if ((u_pbr_bisect & 1024) == 0) {
            const float MM_KNEE = 0.8;
            vec3 me = exp(-max(mm_lin - vec3(MM_KNEE), vec3(0.0)) / (1.0 - MM_KNEE));
            mm_lin = mix(mm_lin, vec3(1.0) - (1.0 - MM_KNEE) * me, step(vec3(MM_KNEE), mm_lin));
          } else {
            mm_lin = min(mm_lin, vec3(1.0));
          }
          color.rgb = mix(pow(max(mm_lin, vec3(0.0)), vec3(1.0 / 2.2)), fbaked, ffar_t);

          // ---- PER-CHANNEL ISOLATION VIZ ----------------------------------------------------------
          // One mode per new channel, same idiom as the fused chunk's 2..23: each shows ONLY the term
          // it names, so "is this channel doing anything" is answerable without a measurement campaign.
          if (u_mm_debug == 1) {
            color.rgb = pow(max(mm_trans, vec3(0.0)), vec3(1.0 / 2.2));
          } else if (u_mm_debug == 2) {
            color.rgb = pow(max(mm_coat_sum, vec3(0.0)), vec3(1.0 / 2.2));
          } else if (u_mm_debug == 3) {
            color.rgb = pow(abs(mm_aniso_delta), vec3(1.0 / 2.2));
          } else if (u_mm_debug == 4) {
            color.rgb = clamp(mm_Fms - vec3(1.0), 0.0, 1.0) * 4.0;
          } else if (u_mm_debug == 5) {
            color.rgb = vec3(mm_so);
          } else if (u_mm_debug == 6) {
            color.rgb = vec3(mm_th);
          } else if (u_mm_debug == 7) {
            color.rgb = vec3(((u_mm_flags & 1) != 0) ? 1.0 : 0.0, ((u_mm_flags & 2) != 0) ? 1.0 : 0.0,
                             ((u_mm_flags & 4) != 0) ? 1.0 : 0.0);
            if ((u_mm_flags & 128) != 0) {
              color.rgb = mix(color.rgb, vec3(1.0), 0.35);  // ORM-packed materials read washed out
            }
          }
        }
