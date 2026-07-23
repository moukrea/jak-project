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
echo "[Gpbrf PASS]"
