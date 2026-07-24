#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpbrf FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-pbr-realtime-fusion/report.txt
D=.autoport/reports/Grecharged-pbr-realtime-fusion/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"

# --- SOURCE-LEVEL (un-stubbable) ---
# specular + emissive must be WIRED in the loader (currently only _normal/_roughness/_metallic/_ao/_height).
grep -qE '"_specular"' game/graphics/opengl_renderer/loader/LoaderStages.cpp || fail "loader does not load _specular map (owner: wire specular)"
grep -qE '"_emissive"' game/graphics/opengl_renderer/loader/LoaderStages.cpp || fail "loader does not load _emissive map (owner: wire emissive)"
# PbrMaterialMaps must carry the two new maps.
grep -qiE 'spec(ular)?_tex' game/graphics/opengl_renderer/loader/CustomTextureReplacements.h game/graphics/opengl_renderer/loader/*.h 2>/dev/null || fail "PbrMaterialMaps has no specular tex field"
grep -qiE 'emissive_tex|emiss_tex' game/graphics/opengl_renderer/loader/CustomTextureReplacements.h game/graphics/opengl_renderer/loader/*.h 2>/dev/null || fail "PbrMaterialMaps has no emissive tex field"
# The FUSION: the realtime-lighting branch (u_rt_light_on) must consume PBR maps — the shader must reference
# a pbr material sampler/uniform INSIDE the rt path (not only the standalone u_pbr_mode branch).
for S in tfrag3 shrub tie_wind etie_base; do
  F="game/graphics/opengl_renderer/shaders/$S.frag"
  [ -f "$F" ] || continue
  grep -qiE 'u_rt_light_on' "$F" || fail "$S.frag lost the rt branch"
  grep -qiE 'pbr|roughness|metallic|specular|emissive|u_.*rough|u_.*metal|u_.*emiss' "$F" || fail "$S.frag rt path does not reference PBR material maps (fusion missing)"
done
grep -qiE 'emissive|emiss' game/graphics/opengl_renderer/shaders/tfrag3.frag || fail "tfrag3.frag does not sample emissive"

# --- REPORT EVIDENCE ---
grep -qiE 'rt (on|ON).*pbr (on|ON)|realtime.*(and|\+).*pbr|fuse|fusion|pbr.*(lit by|under).*realtime|physically.?based.*realtime' "$R" || fail "no rt-ON+pbr-ON fusion evidence"
grep -qiE 'normal map.*(detail|perturb|move|realtime sun)|roughness.*(specular|GGX|response)|metallic.*(specular|reflect)|GGX.*(sun|green.?sun)' "$R" || fail "no evidence the maps drive the realtime-lit result (normal/roughness/metallic under the rt lights)"
grep -qiE 'emissive.*(glow|self.?(lit|illum)|shadow|night|unlit)|glow.*emissive' "$R" || fail "no emissive-glows-in-shadow/night evidence"
grep -qiE 'specular map|_specular|F0|spec(ular)?.workflow' "$R" || fail "no specular-map usage evidence"
grep -qiE 'bidon|fallback|rt (off|OFF).*pbr (on|ON)|standalone pbr.*(intact|unchanged|still)' "$R" || fail "no bidon-fallback (rt OFF + pbr ON) preserved evidence"
grep -qiE 'off ?== ?stock|byte-identical|rt off.*pbr off.*stock' "$R" || fail "no golden-rule OFF==stock evidence"
grep -qiE 'no regression|rt on.*pbr off.*(unchanged|same|accepted)|directional-ambient.*(unchanged|intact)' "$R" || fail "no no-regression (rt-on+pbr-off unchanged) evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
# OWNER REOPEN (2026-07-23): plastic-shine fix — industry BRDF.
grep -qiE 'smith|visibility term|geometr(y|ic) term' "$R" || fail "no Smith/visibility-term evidence (plastic grazing sheen = missing G term)"
grep -qiE 'roughness.?aware.*fresnel|fresnel.*(attenuat|rough)|F0 ?\+ ?\(max' "$R" || fail "no roughness-aware Fresnel evidence (grazing-angle blowout)"
grep -qiE 'F0.*0\.04|dielectric|metallic.*(absent|0|zero|missing)' "$R" || fail "no dielectric-F0 evidence (stone/dirt are not metal)"
grep -qiE 'roughness.*(squar|alpha|perceptual|linear|srgb|channel)' "$R" || fail "no roughness mapping/convention audit evidence"
grep -qiE 'specular occlusion|baked.*(detail|ao).*(specular|atten)|energy conserv' "$R" || fail "no specular-occlusion/energy-conservation evidence"
grep -qiE 'roughness mip|blurry mip|prefiltered.*(mip|rough)|mip.*rough' "$R" || fail "no roughness-mip IBL evidence (rough ground must sample blurry mip)"
grep -qiE 'baked.*(modulation|relief|influence).*(intact|kept|unchanged|base)' "$R" || fail "no baked-base-intact evidence (owner: never lose the object relief)"
# OWNER #2: path-active proof, missing-map defaults, same-source pairing, menu sliders.
grep -qiE 'killswitch|path.?active|new path.*(A/B|visible|obvious)|fused.*(executes|active).*(device|proof)' "$R" || fail "no new-path-ACTIVE device proof (owner sees barely any change)"
grep -qiE 'missing.*(roughness|map).*(rough|0\.8|0\.9|1\.0|default)|default.*rough(ness)?.*(rough|high)|assume rough' "$R" || fail "no missing-roughness=ROUGH default evidence (internet-pack textures have no maps => smooth default = plastic)"
grep -qiE 'same.?source|pairing|provenance|user base.*user maps|never mixed' "$R" || fail "no same-source map-pairing evidence (user base + bundled maps = wrong)"
grep -qiE '(texture relief|specular intensity).*(slider|menu|row)|menu.*(relief|specular).*(slider|row)' "$R" || fail "no menu sliders evidence (owner: tunables in SETTINGS, not adb props)"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not updated"
grep -qiE 'side.?by.?side|obvious.*(difference|change)|old.?vs.?new.*(capture|vantage)' "$R" || fail "no obvious-difference side-by-side proof"
# OWNER #3: bisection-first (sheen survives specular=0), shimmer fix, real displacement + tessellation toggle.
grep -qiE 'bisect.*(matrix|mask|term)|mask.*(sheen|culprit)|culprit.*(term|identified)' "$R" || fail "no TERM-BISECTION matrix (the sheen survives specular=0 — identify the culprit term BEFORE fixing)"
grep -qiE 'sheen.*(gone|disappear|absent).*(mask|term|fix)|culprit.*(fixed|zeroed)' "$R" || fail "no culprit-identified-and-fixed evidence"
grep -qiE 'mip.*(normal|pbr map)|LINEAR_MIPMAP|toksvig|variance.*rough|min.*roughness.*clamp' "$R" || fail "no shimmer fix evidence (mips + specular AA effective)"
grep -qiE 'steep.*(pom|parallax)|pom.*(16|24|32|step)|tessellat' "$R" || fail "no real-displacement evidence (steep POM + tessellation)"
grep -qiE 'displacement.*(off|parallax|tessellation).*(menu|toggle|carousel)|tessellation.*(toggle|menu)' "$R" || fail "no displacement menu toggle evidence"
grep -qiE 'menu-tree' "$R" || fail "menu-tree not synced"
grep -qiE 'preset.*(row|carousel|menu)|all.?in.*(preset|mode)|test preset' "$R" || fail "no PBR TEST PRESET menu row evidence (owner: one-click intended-config presets, removable later)"
grep -qiE 'capabilit.*(check|query)|EXT_tessellation.*(check|absent|fallback)|link.*(fail|check).*fallback|fall.?back.*parallax' "$R" || fail "no tessellation capability-check+fallback evidence (owner: instant crash on SD8EG5, must never crash)"
grep -qiE 'crash.?loop guard|boot sentinel|auto.?reset.*(setting|displacement|preset)' "$R" || fail "no crash-loop guard evidence (persisted setting bricked the game until manual reset)"
grep -qiE 'perturbed normal|Nm.*(specular|env|reflect|fresnel)|normal.?mapped.*(reflect|specular|NdV|NdH)|glass.*(pane|sheet|fixed|gone)' "$R" || fail "no glass-pane fix evidence (spec/env terms must use the normal-mapped+POM normal, not the flat geometric normal)"
grep -qiE 'contrast.*(rebalanc|match|reduced).*(baked|fused)|double.*(contrast|appli).*(fixed|removed)' "$R" || fail "no fused-contrast rebalance evidence (owner: fusion modes over-contrasted)"
grep -qiE 'preset.*(audit|verif|wire|fixed)|two.*(preset|mode).*(nothing|audit|fixed)' "$R" || fail "no dead-presets audit evidence (two presets show nothing)"
# OWNER: probe grid DELETED (not archived) + dynamic follow-probe as env source.
git ls-files custom_assets/jak1/probes 2>/dev/null | grep -q . && fail "probe asset still tracked (owner: delete, not archive)"
[ -f game/graphics/opengl_renderer/LightProbeGrid.cpp ] && fail "LightProbeGrid still present (owner: delete the grid system)"
grep -qiE 'follow.?probe|dynamic.*(cubemap|probe).*(camera|amortiz)|camera.*(cubemap|probe).*(render|refresh)' "$R" || fail "no dynamic follow-probe evidence (one low-res camera cubemap, amortized faces, tiered)"
grep -qiE 'menu-tree' "$R" || fail "menu-tree not synced (probe rows removed)"
# OWNER #4: matte-dielectric default (glass = specular on matte; keep normal-mapped diffuse relief).
grep -qiE 'matte|rough.*(dielectric|reflect.*(nothing|near.?zero|~0))|specular.*(near.?(zero|invisible)|->? ?0).*(rough|matte|default)|roughness.*(kill|drive|suppress).*specular' "$R" || fail "no matte-default evidence (rough dielectrics must show ~0 specular; glass = specular on matte surfaces)"
grep -qiE 'diffuse relief|normal.?map.*(diffuse|depth).*(kept|relief)|depth without.*(gloss|specular)|relief.*(minus|without).*(gloss|sheen)' "$R" || fail "no diffuse-relief-kept evidence (keep depth, kill gloss)"
grep -qiE 'pbr.?on ?== ?lighting.?only|equal.*lighting only.*(plus|depth)|A/B.*lighting.?only.*(no|zero).*(sheen|glass|gloss)' "$R" || fail "no PBR-on==Lighting-only+depth acceptance evidence"
grep -qiE 'specular intensity.*default.*(0\.[12]|low)|default.*specular.*(low|0\.[12])' "$R" || fail "no low-default-specular evidence (matte is the norm)"
# OWNER #5: the bug is PARALLAX/POM depth (epoxy/floating), NOT specular. Relief from normal-map SHADING.
grep -qiE 'epoxy|floating.*(texture|10cm)|parallax.*(incoherent|float|depth scale|too (large|strong)|disabl)|pom.*(disabl|depth scale|miscalibrat|too (large|strong))' "$R" || fail "no parallax/POM-depth root-cause evidence (owner: epoxy/floating texture = broken POM, NOT specular)"
grep -qiE 'relief.*(from|via).*(normal.?map|shading)|normal.?map shading|surface.?locked|shading.*(not|instead).*(uv|displacement|parallax)' "$R" || fail "no normal-map-shading-relief evidence (relief must be surface-locked shading, not UV displacement)"
grep -qiE 'depth scale.*(calibrat|reduc|mm|millimet|sane|/ ?100|100x)|parallax.*(calibrat|surface.?locked|coherent)|displacement.*(kept|calibrat|correct)' "$R" || fail "no displacement-calibration evidence (owner: KEEP displacement, fix the ~10cm float to surface-locked)"
grep -qiE 'tessellat.*(works|render|displac.*geometry|glPatchParameter|GL_PATCHES|compil.*(ok|success)|on device|honor)' "$R" || fail "no tessellation-actually-works evidence (owner: make tessellation function on the Honor, not just fallback)"
# OWNER #7: TANGENT BASIS is the root cause (weak relief + contrast cracks scaling with relief).
grep -qiE 'tangent.*(basis|per.?vertex|attribute|mikktspace|orthonormal|handedness)|TBN.*(per.?vertex|vertex attribute|proper)|per.?vertex tangent' "$R" || fail "no per-vertex tangent-basis evidence (root cause: screen-space TBN discontinuous => cracks + weak relief)"
grep -qiE 'not.*(screen.?space|dFdx)|replace.*(screen.?space|derivative).*(tbn|tangent)|interpolated.*(tbn|tangent)' "$R" || fail "no shader-uses-vertex-TBN evidence (was screen-space derivatives)"
grep -qiE 'no (contrast )?crack|crack.*(gone|fixed|eliminated)|relief.*>?0.*no.*(crack|break)' "$R" || fail "no cracks-fixed-at-relief>0 evidence (hard gate)"
grep -qiE 'visible displacement|relief.*(visible|clearly)|displacement.*(restored|visible)' "$R" || fail "no visible-displacement-restored evidence (last round neutered it)"
grep -qiE 'tessellat.*(runs|actually|glGetProgramInfoLog|glGetError|patch.*(link|compil)|real.*(displac|geometry))|tess.*(GL error|infolog)' "$R" || fail "no real-tessellation-root-cause evidence (owner: it still falls back, don't claim it works)"
# OWNER #8: faceted shading = base normal is per-face; use SMOOTH per-vertex normal + tess diagnostics.
grep -qiE 'smooth.*(per.?vertex|vertex).*normal|per.?vertex normal.*(base|smooth|interpolat)|base normal.*(smooth|per.?vertex)|barycentric.*normal' "$R" || fail "no smooth-per-vertex-base-normal evidence (faceted triangular patches = per-face normal; use smooth N)"
grep -qiE 'no (facet|triangular)|facet.*(gone|fixed|eliminated)|no.*triangular.*(patch|crack)|smooth.*(lighting|shading).*(faces|grass)' "$R" || fail "no facets-eliminated evidence"
grep -qiE 'pbr-tess|tess.*(log|diagnostic|infolog|GK_STDOUT)|tessellat.*(capability.*log|log.*reason|greppable)' "$R" || fail "no tessellation-diagnostics evidence (renderer must log why it falls back)"
# OWNER #9: facets = degenerate per-vertex tangent -> screen-deriv TBN fallback. Fix tangent coverage, device-proven.
grep -qiE 'tangent.*(fallback|degenerate|coverage|fraction).*(fil|device|prov|diag)|fallback fraction|frisvad|duff|branchless.*(basis|tangent)|continuous.*tangent.*(from|derived).*normal' "$R" || fail "no tangent-fallback-coverage device proof or continuous-fallback-tangent evidence (facets = degenerate v_tangent -> screen-deriv TBN)"
grep -qiE 'facet.*(gone|fixed|eliminated).*(relief|normal.?map)|no facet.*relief|tangent.*(valid|non.?degenerate).*(ground|tfrag|grass)' "$R" || fail "no facets-fixed-via-tangent evidence"
grep -qiE 'pbr_tan_diag|pbr_tess_diag|files/.*diag' "$R" || fail "no file-based diag evidence (Honor logcat obscured)"
# OWNER #10: in-menu PBR-isolate bisection + parallax facet investigation.
grep -qiE 'pbr isolate|in.?menu.*bisect|menu.*(normal.?map only|parallax only|isolate).*(carousel|row)|carousel.*(both|normal.?map|parallax|neither)' "$R" || fail "no in-menu PBR-isolate bisection carousel evidence (owner must isolate the facet term himself)"
grep -qiE 'parallax.*(facet|per.?triangle|clip|chart|discontinu|off.*remove)|POM.*(facet|per.?triangle|edge|silhouette)' "$R" || fail "no parallax-facet investigation evidence (prime suspect after continuous tangent)"
grep -qiE 'menu-tree' "$R" || fail "menu-tree not synced"
# OWNER #11: menu Unknown-ID + wiring fix, verified.
grep -qiE 'pbr-iso.*label|option.*(global string|runtime string|format.*label)|register.*(0x172|option string)|carousel option.*(string|format)' "$R" || fail "no carousel-OPTION-string registration (must be runtime global strings like displacement, NOT bare text-ids — Unknown ID 5924-5927)"
grep -qE 'define \*pbr-iso.*-label\*|pbr-iso.*label.*format|carousell-pbr-isolate.*label' goal_src/jak1/pc/progress-pc.gc || fail "isolate carousel options still use bare text-ids (no runtime global label strings in progress-pc.gc) => Unknown-ID persists"
grep -qiE 'isolate.*(applies|wired|writes|changes).*(bisect|mask|shader)|flip.*(change|apply).*(bisect|mask)|bisect mask.*(diag|file|logged)' "$R" || fail "no isolate-actually-applies evidence (flipping did nothing)"
grep -qiE 'supervisor.*(verif|navigate|cpad).*(menu|redmi|isolate)|menu.*verified.*(before|redmi)|cpad_inject.*isolate' "$R" || fail "no supervisor-pre-ship-verification note"
# OWNER BREAKTHROUGH: unwelded mesh. Vertex welding is the fix.
grep -qiE 'weld|coincident vert|shared vert|consolidat.*(mesh|vert)|merge.*vert.*(position|texture)|duplicate vert.*(merg|weld)' "$R" || fail "no vertex-welding evidence (root cause: unwelded duplicate vertices at seams => facets + tessellation holes)"
grep -qiE 'average.*(across|welded|shared).*(seam|normal)|normal.*(cross|across).*seam|smooth.*normal.*welded' "$R" || fail "no smooth-normal-across-welded-seams evidence"
grep -qiE 'tessellat.*(no hole|closed edge|welded|shared edge|no tear)|no (hole|tear|gap).*(tessellat|displac)|edge.*(closed|welded).*tessellat' "$R" || fail "no tessellation-no-holes-via-welding evidence"
echo "[Gpbrf PASS]"
