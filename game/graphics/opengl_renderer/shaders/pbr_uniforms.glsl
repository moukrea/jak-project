uniform int u_pbr_mode;        // 0=legacy; bit1 normal, bit2 rough, bit4 metal, bit8 ao, bit16 height/POM,
                               // bit32 specular (F0 workflow), bit64 emissive (unlit add) — fusion phase
                               // bit128 (Grecharged-managed-assets): the bound normal map stores only
                               // X/Y (BC5 / EAC RG11 / ASTC two-channel — the GPU-compressed pack
                               // formats have no third channel), so Z is reconstructed here.
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
// (u_pbr_uv_tile is GONE. ★ OWNER CHECKER VERDICT, BUG A, 2026-07-26: every map — height, normal,
//  roughness, AO, specular, emissive — must sample at EXACTLY the base colour's uv, with no
//  separate multiplier anywhere. The world-scale reasoning belongs to the displacement AMPLITUDE
//  only, and lives in pom_depth_uv() below.)
// ROUND 20: THIS material's MEASURED authored UV density, in texture tiles per world metre
// (measured at level load, see background_common.cpp measure_uv_density_tfrag/_tie). Converts the
// parallax depth from metres into the UV units the offset lives in.
uniform float u_pbr_uv_per_m;
// ROUND 20 correction: this height MAP's characteristic feature wavelength, in TILES (measured at
// load from the map's own mip-energy spectrum). The parallax depth follows the FEATURE size, the
// same law tfrag3_tess.tese displaces real vertices by — so Parallax and Tessellation show the
// same depth, produced two different ways.
uniform float u_pbr_height_lambda;
// ★ OWNER CHECKER VERDICT, BUG B (2026-07-26): "des chunks entiers (LA PLUPART) sont juste PLATS".
// 1 only on the TFRAG3_TESS program, i.e. only where the tessellation stages actually displaced
// real vertices. The POM used to be suppressed by the GLOBAL u_pbr_displacement == 2 setting, which
// silently killed the parallax on every draw the tess program does not cover — all TIE walls and
// props, shrubs, hfrag, and every patch past the tesc's 30 m gate — leaving them with NO
// displacement at all. Suppression is per-PROGRAM now, so nothing is ever left flat.
uniform int u_pbr_tess_active;
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
// ROUND 22 PER-PIXEL SCREEN-COVERAGE modes (owner defect A step 1 — measure before porting).
// Unlike every mode above these are WHOLE-SCREEN: they are applied at the very end of main() in
// tfrag3/etie_base/tie_wind/shrub/hfrag/merc2/generic/emerc, after the alpha discard and the fog,
// and they only ever write color.rgb (alpha and therefore the discard set are untouched).
// 30=PROGRAM TAG. Which program drew this pixel; tags are >=127 apart so H.264 screenrecord
//    cannot confuse them. tfrag3 yellow (tessellated) / red (plain tfrag3 + TIE non-envmap),
//    etie_base green, tie_wind cyan, shrub blue, hfrag orange, merc2 magenta, generic violet,
//    emerc lime.
// 31=DISPLACEMENT TAG. White where the fragment actually received displacement (tessellated
//    geometry, or a POM march that actually ran, with the displacement setting on), black
//    otherwise. Every shader without a PBR path reports 0 by construction — that is the
//    measurement.
uniform int u_pbr_debug;
uniform sampler2D tex_PBR_N;
uniform sampler2D tex_PBR_R;
uniform sampler2D tex_PBR_M;
uniform sampler2D tex_PBR_AO;
uniform sampler2D tex_PBR_H;
// Grecharged-pbr-realtime-fusion (owner: "faut câbler specular et emissive aussi"):
// _specular = F0/specular color (specular workflow, overrides metallic-derived F0),
// _emissive = unlit self-illumination added on top (glows in shadow/night). Units 16/17.
uniform sampler2D tex_PBR_S;
uniform sampler2D tex_PBR_E;
uniform float u_pbr_emissive_str;  // emissive intensity (prop debug.opengoal.pbr.emissive)
uniform float u_pbr_spec_intensity;  // menu SPECULAR INTENSITY slider (0..2, default 1)
// Gpbr-per-texture-materials (owner 2026-08-28: "un tissu n'a pas les mêmes propriétés qu'un mur en
// pierres taillées ou que du sable"). THIS material's own surface constants, pushed per DRAW by
// PbrDrawBinder from its surfaces.json record. The identity values below — (0.9, 0.0, 0.04, +1) and
// (1, 1) — are LITERALLY the constants this shader used to carry in-line at the roughness, metallic
// and F0 sites, so a material the file does not name is unchanged bit for bit.
uniform vec4 u_pbr_mat;   // x = roughness quand aucune _roughness n'est liee (0.9), y = metallic
                          // sans map (0.0), z = F0 dielectrique (0.04), w = signe du canal VERT
                          // de la normal map (+1 OpenGL / -1 DirectX)
uniform vec2 u_pbr_mat2;  // x = facteur sur la _roughness liee, y = facteur sur la _metallic liee
// This material's MEAN tangent-space surface gradient (n.xy/n.z, clamped +-4), measured over
// every texel of <tex>_normal.png when the map is loaded (LoaderStages.cpp) and pushed per
// draw by PbrDrawBinder. Subtracting it makes the normal-map perturbation ZERO-MEAN — see the
// long comment at the sample site: a non-zero mean is a CONSTANT TILT of the whole material,
// and that tilt is what turned into the owner's hard brightness plates.
uniform vec2 u_pbr_normal_dc;
// PBR POLISH (owner playtest #17: "ça fait toujours juste bump map glorifié"). This material's
// HEIGHT-MAP statistics, measured over every texel of <tex>_height.png when it is decoded
// (LoaderStages.cpp) and pushed per draw by PbrDrawBinder: .x = the map's MEAN, .y = 0.5 / its
// robust (p2..p98) half-range. Every height consumer below reads the map through hnorm().
// The shipped maps are neither mean-centred nor normalised — leafyground spans 0.063..0.463
// (mean 0.322), wallplaster means 0.807, strawroof spans only 0.298..0.478 — so the naive
// (h - 0.5) the code used before both OFFSET whole materials (leafyground displaced net-INWARD by
// ~4.7 cm, wallplaster net-OUTWARD; a constant offset is not relief, and it steps against the
// unmapped neighbour exactly like the normal-map DC did) and threw away most of the amplitude
// (only 18-75% of the nominal range was ever reached). (0.5, 1.0) = identity, so a draw without a
// height map is bit-for-bit unchanged.
uniform vec2 u_pbr_height_stat;
// REOPEN #3 TERM BISECTION (owner: the plastic sheen SURVIVES specular-intensity = 0, so
// it is NOT in the slider-scaled specular sum — identify the culprit by zeroing ONE term
// at a time on device). Prop debug.opengoal.pbr.bisect, default 0 = full path unchanged.
// Set bit => that term is ZEROED/DISABLED in the fused rt+pbr branch:
//    1 = yellow-sun GGX specular          2 = green-sun GGX specular
//    4 = ambient/IBL specular (famb_spec) 8 = Fresnel-on-diffuse (the line-651 kd darkening)
//   16 = _specular-map F0 (fall back to metallic-derived)   32 = emissive
//   64 = normal-map perturbation (Nm = smooth N)           128 = parallax/POM
//  256 = detail-relight ratio fdetail     512 = baked-modulation lit/shadow fmod
// 1024 = C1 shoulder tone map (linear clamp instead)  2048 = fused-contrast fmod compress off
// 4096 = REOPEN #6 matte-dielectric ENVELOPE off (restores the old glossy sheen for A/B: the
//        default matte look vs the pre-#6 glass — the owner's "path active?" killswitch)
// ---- SUPERVISOR LIVE A/B FIX (2026-07-24): relief=0 smooth vs relief=2.5 HARD PLATES. The
// three bits below are the A/B killswitches for the three halves of that root cause; all
// three default to 0 == the NEW (fixed) behaviour, set the bit to get the old one back.
// 8192 = normal-map DC removal OFF (legacy: apply the map with its raw mean tilt)
// 16384 = macro lit/shadow terminator back on the normal-MAPPED Nm (legacy) instead of N
// 32768 = normal-map tangent frame back on the per-chunk UV tangent (legacy) instead of the
//         seam-stable world frame
// REOPEN #10: the IN-MENU "PBR ISOLATE" carousell (Recharged Settings) seeds this mask via the
// recharged_pbr_isolate setting so the OWNER can bisect the residual grass-facet term at his own
// vantage with NO adb (BOTH=0, NORMAL-MAP ONLY=128 [POM off], PARALLAX ONLY=64 [nm off], NEITHER=192).
// Prime suspect now (tangent frame proven continuous @ REOPEN#9, base normal smooth): the PARALLAX/
// POM at bit 128 — the steep march (below) samples the height map at a data-dependent iteration count;
// where it clips at UV-chart/triangle boundaries it can read a per-triangle offset that reads as a
// facet at high relief. The owner's PARALLAX-ONLY vs NORMAL-MAP-ONLY flip names it; the debug prop/env
// still override the mask for the supervisor's full-term headless A/B.
// ---- PBR POLISH, OWNER PLAYTEST #17 (2026-07-25). Same convention: 0 == the NEW behaviour,
// set the bit to get the previous build back, so every one of this round's fixes is a live A/B
// at the owner's own vantage with one setprop and no rebuild.
// 2097152 = height-field CAVITY / micro-AO off (the "flat in shadow" fix — the direction-
//           INDEPENDENT relief term that replaces the ~1.0 ambient RATIO)
// 4194304 = tess-eval displacement back to the ALIASED textureLod(...,0.0) height fetch
//           (legacy) instead of the mip matched to the tessellated vertex spacing
// 8388608 = direct N.L detail ratio back to its legacy wide [0.45, 1.9] clamp (the
//           "très contrasté à la lumière" half of the rebalance)
// ---- PBR POLISH, OWNER PLAYTEST #18 (2026-07-25) — GROUND relief. Same convention.
// 16777216 = tessellation level law back to the legacy DISTANCE-ONLY 128/d (read by
//            tfrag3_tess.tesc and .tese) instead of the world-space-edge-length law, so the
//            ground-density fix is a live same-vantage A/B.
// 33554432 = parallax GRAZING FADE + world-cm offset cap OFF, i.e. the legacy un-attenuated
//            0.08 UV offset back (the owner's "au sol le displacement est HORIZONTAL, ça s'étale
//            à plat" — see the POM march). Applies to BOTH POM branches.
//            This bit is 33554432 and NOT the next free-LOOKING 262144: 262144 was already taken
//            by round #17's ambient-relief A/B (the fdt_amb site below). The first device A/B run
//            of this round used the overloaded bit and measured the side effect at the SAME ORDER
//            OF MAGNITUDE as the parallax signal itself — it silently confounded both A/Bs. Always
//            scan ALL of *.frag/*.tesc/*.tese for a bit before claiming it is free.
// 67108864 = ROUND 20 tess-eval displacement AMPLITUDE law back to the hardcoded constant
//            WORLD_TILES_PER_M instead of THIS material's MEASURED authored UV density
//            (u_pbr_uv_per_m). Read in tfrag3_tess.tese:220-221 as `legacy_uv_law`.
//            ⚠ THIS ENTRY WAS MISSING from the list until round 23, and round 23 very nearly
//            re-used the bit for the shrub normal flip below — which would have confounded a
//            shrub-polarity A/B with a ground-displacement change in the very same frame: the
//            EXACT trap the 33554432 note above was written to prevent. The scan rule is only as
//            good as this list, so when you take a bit, document it HERE in the same edit.
// 134217728 = ROUND 23 shrub two-sided normal flip back to LEGACY unconditional (owner defect C,
//            "the polarity FLIPS surface to surface"). Default 0 = the flip applies ONLY to the
//            screen-space derivative fallback normal, whose cross(dFdx, dFdy) sign is arbitrary; a
//            consolidated per-vertex normal is then left exactly as the mesh data authored it, so
//            the displacement/POM frame it feeds can no longer depend on which side the CAMERA is
//            on. Read in shrub.frag (the u_rt_light_on branch).
uniform int u_pbr_bisect;
// Gpbr-per-texture-materials — BISECT BANK 2. Bank 1 above is FULL: bits 1 .. 1073741824 are all
// taken (scanned over every *.glsl/*.frag/*.vert/*.tesc/*.tese before this line was written, per
// the scan rule at bit 33554432), and 2147483648 does not fit a GLSL ES signed int. So the next
// A/B killswitch opens a second bank rather than overloading a used bit — the exact trap the
// 33554432 note describes, which once confounded two A/Bs in the same frame.
// Same convention as bank 1: 0 == the NEW (fixed) behaviour, set the bit to get the old one back.
// Prop debug.opengoal.pbr.bisect2 / env OG_PBR_BISECT2, default 0.
//    1 = per-FACE tangent HANDEDNESS off, i.e. back to the baked per-VERTEX v_tangent.w.
//        Handedness is a property of a FACE (the sign of the UV Jacobian) and .w is one sign per
//        VERTEX; on village1, 45.9% of triangles carry a mirrored UV chart and 33484 face corners
//        of the seven PBR materials sit on a vertex whose incident faces MIX handedness, so
//        whichever sign ships, the other side renders its relief inverted in V. Read in
//        pbr_fused.glsl, tfrag3.frag and tfrag3_tess.tese.
//    2 = per-FACE tangent DIRECTION off, i.e. back to the baked per-VERTEX tangent even where it
//        points AGAINST its own face's dP/du. Same defect class as bit 1 and measured the same way:
//        1052 face corners of the seven PBR materials (0.111%) run their normal-map X perturbation
//        and their POM U march backwards. The fix only ever flips an ALREADY-reversed tangent, so a
//        corner the census scores correct is left bit-identical. Read at the same three sites.
uniform int u_pbr_bisect2;
// REOPEN #3 DISPLACEMENT carousel: 0 = Off (height_scale forced 0 C++-side), 1 = Parallax
// (steep POM below, the default = pre-carousel behaviour), 2 = Tessellation (displacement
// happens in the tess evaluation stage; the frag POM must then stand down).
uniform int u_pbr_displacement;
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
