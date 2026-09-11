uniform int u_pbr_mode;        // 0=legacy; bit1 normal, bit2 rough, bit4 metal, bit8 ao, bit16 height/POM,
                               // bit32 specular (F0 workflow), bit64 emissive (unlit add) — fusion phase
                               // bit128 (Grecharged-managed-assets): the bound normal map stores only
                               // X/Y (BC5 / EAC RG11 / ASTC two-channel — the GPU-compressed pack
                               // formats have no third channel), so Z is reconstructed here.
                               // bit256 (Gpbr-props-reach-draw) : MATIERE AUTHOREE SANS AUCUNE
                               // CARTE. Aucune branche ne le teste : il sert uniquement a ouvrir la
                               // porte `u_pbr_mode != 0`, apres quoi chaque lecture retombe sur la
                               // constante authoree (u_pbr_mat.x rugosite, .y metallicite,
                               // .z reflectance, .w sens du vert de la normale). Sans lui, les
                               // champs nommes pm_rough_NOMAP / pm_metal_NOMAP etaient
                               // inatteignables : leur seul lecteur vit derriere une porte qui
                               // exigeait une carte.
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
// meme loi que celle par laquelle l'etage de tessellation deplacait de vrais sommets : les deux
// paliers montraient la meme profondeur, produite de deux facons. lighting-legacy-purge
// (2026-09-11) : cet etage est retire, le PARALLAX est seul.
uniform float u_pbr_height_lambda;
// `u_pbr_tess_active` est SUPPRIME le 2026-09-11 par lighting-legacy-purge, avec l'etage
// TESSELLATION : il ne valait 1 que sur le programme de tessellation, lui-meme retire.
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
// lighting-legacy-purge (2026-09-11) : u_pbr_bisect RETIRE, valeur livree figee a 0 (chemin complet ; outil de mise au point).
// lighting-legacy-purge (2026-09-11) : u_pbr_bisect2 RETIRE, valeur livree figee a 0 (chemin complet ; outil de mise au point).
// lighting-legacy-purge (2026-09-11) : u_pbr_displacement RETIRE, valeur livree figee a 1 (PARALLAX ; le mode TESSELLATION n'a jamais ete livre).
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
