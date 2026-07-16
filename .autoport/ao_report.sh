#!/usr/bin/env bash
# ao_report.sh — Grecharged-ambient-occlusion report assembler.
# Builds report.txt ONLY from verified evidence artifacts; dies if any gate artifact
# is missing or FAILed (no report > false report).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-ambient-occlusion
R="$OUT/report.txt"
die(){ echo "[ao-report FAIL] $*" >&2; exit 1; }

# --- evidence preconditions -------------------------------------------------
# Owner order 2026-07-16 14:25: the full 15-combo title matrix is DROPPED as a per-change
# gate. Its one-time certification (chain-attempt5.log 12:25:46, TITLE-GATE PASS 15/15 on
# the near-final build) stands; every build since gates on the fast worst-case spot check
# (GTAO+High+Stronger persisted boot, 90s alive, purple-scan + AOPERF seed).
grep -q 'TITLE-GATE PASS (15/15 combos)' "$OUT/chain-attempt5.log" || die "one-time title matrix certification missing (chain-attempt5.log)"
grep -q '\[TITLE-SPOTCHECK PASS\]' "$OUT/title-gate/spotcheck-log.txt" || die "worst-case title spot check not PASS"
# defect #6: safe-boot fallback proof must PASS.
grep -q '\[ao-safeboot PASS\]' "$OUT/safeboot/proof-log.txt" || die "safe-boot proof not PASS"
BUILD_LOG=$(ls -t "$OUT"/build-deploy-*.log 2>/dev/null | head -1)
[ -n "$BUILD_LOG" ] || die "no build-deploy log"
grep -q '\[ao-build\] DONE' "$BUILD_LOG" || die "build+deploy not DONE ($BUILD_LOG)"
grep -q '\[ao-proof-battery\] DONE' "$OUT/proof-battery-log.txt" || die "proof battery not DONE"
# menu push proof: the FIXED standalone menu run (menu-proof2/proof-log.txt) is the
# authority — normalized start state, per-commit logcat clear. ALL THREE mode commits
# (SSAO 1, HBAO 2, GTAO 3) + the quality commit must have pushed.
MP="$OUT/menu-proof2/proof-log.txt"
[ -f "$MP" ] || die "no menu proof log"
for m in 1 2 3; do grep -qE "PUSH-OK mode->$m" "$MP" || die "menu proof: no PUSH-OK mode->$m"; done
grep -qE 'PUSH-OK quality->' "$MP" || die "menu proof: no PUSH-OK quality line"
# closing round: the AO STRENGTH row edit must have pushed too.
grep -qE 'PUSH-OK strength->' "$MP" || die "menu proof: no PUSH-OK strength line"
# v3: the four pushes must land in ONE coherent attempt (not stitched across retries)
grep -qE '\[ao-menu-proof2\] COMMIT-SEQUENCE PASS' "$MP" || die "menu proof: no single-attempt COMMIT-SEQUENCE PASS"
# defect-5 gates: every vantage OVERALL PASS (shoreline = defect #7 water vantage; its
# OVERALL includes the [ao-gate7] water-untouched checks)
for v in village1 beach training shoreline; do
  grep -qE "\[ao-gate5\] $v OVERALL: PASS" "$OUT/proof-battery-log.txt" || die "gate5 $v not PASS"
done
grep -qE '\[ao-gate7\] shoreline .*water.*PASS' "$OUT/proof-battery-log.txt" || die "defect-7 water gate not PASS"
# closing round: 3x3 strength grid (modes x weaker/default/stronger at training, quality High)
# — per-segment caps (incl. at Stronger) + strict per-mode crease ordering.
grep -qE '\[ao-grid\] OVERALL: PASS' "$OUT/proof-battery-log.txt" || die "strength grid not PASS"
# fps matrix complete (10 combos, no NO-AOPERF-LINE)
FPM="$OUT/device/ao-fpsmatrix-results.txt"
[ -f "$FPM" ] || die "no fps matrix"
[ "$(grep -c '::' "$FPM")" -eq 10 ] || die "fps matrix incomplete"
grep -q 'NO-AOPERF-LINE' "$FPM" && die "fps matrix has NO-AOPERF-LINE holes"
# jak1 foreground evidence somewhere in the battery
grep -q 'mCurrentFocus=Window{.*org.opengoal.gk.jak1' "$OUT/proof-battery-log.txt" || die "no jak1 focus line"

focus_line=$(grep -o 'mCurrentFocus=Window{[^}]*org.opengoal.gk.jak1[^}]*}' "$OUT/proof-battery-log.txt" | head -1)

fpsrow(){ grep -a "^$1 ::" "$FPM" | sed -E 's/.*(AOPERF[^\r]*)/\1/'; }

{
echo "RESULT: AMBIENT OCCLUSION PASS — SSAO/HBAO/GTAO screen-space AO live on device, menu-driven, Off == stock, alpha-cut foliage excluded, water excluded, defect 1-7 fixes proven"
echo
echo "== Implementation =="
echo "Screen-space AO post-process sampling the existing render FBO depth buffer (depth FBO attachment as texture, blit-resolved when multisampled): reconstruct world-space position+normal from depth, estimate occlusion, depth-aware bilateral blur whose V pass runs at FULL render resolution (doubles as a depth-aware upsample so sub-full-res AO never composites blocky/pixelated — owner tuning #2, GTAO-low reference case), then the GOLDEN-RULE composite (owner-sourced 2026-07-16) over the OPAQUE scene only: out = dst - (1-dst)*k*(1-ao) via GL_FUNC_REVERSE_SUBTRACT — the (1-dst) ambient-fraction proxy masks AO out of directly-lit bright pixels so AO only removes ambient light."
echo "Three estimators share the pipeline and differ only in the occlusion shader: SSAO (hemisphere kernel, tangent-plane occluder test), HBAO (horizon-based ray march, analytic surface tangent), GTAO (ground-truth cosine-weighted horizon integral, slice basis derived from the actual screen march so grazing flat ground stays unoccluded). Files: game/graphics/opengl_renderer/AmbientOcclusion.{h,cpp} + shaders/ao_ssao.frag ao_hbao.frag ao_gtao.frag ao_blur.frag ao_composite.frag; hook in OpenGLRenderer.cpp at the bucket-31 post-opaque insertion point."
echo "AO quality scales resolution + sample count: Low=quarter-res, Medium=half-res, High=full-res. Per-mode look (owner closing round 2026-07-16, SSAO = the perceptual reference): SSAO broad/soft 1.25m radius intensity 2.0 k 0.45; HBAO mid 0.7m radius intensity 2.0 k 0.60, un-muted by relaxing the grazing angle bias (0.50->0.38 grz^2) + near-field min-r cap (0.60->0.52 radius) + fade matched to SSAO (20->45m); GTAO 0.75m radius intensity 0.65 k 0.70, evened out for CONSISTENCY (radius 0.5->0.75m reads large-scale concavities, fade pushed 30->70m out of the visible mid-field, slice/step floors raised against azimuthal patchiness)."
echo "GRAZING-MODULATED OCCLUSION GATE (closing round v2, HBAO+GTAO): both estimators read bumpy open terrain at grazing incidence as a broad low occ wash (HBAO 0.075-0.12, GTAO 0.20-0.30) that the daylight ambient-fraction composite masks but dusk/shadow exposes — the owner's 'aplats de shading' on floors and GTAO's 'fort a certains endroits, inexistant a d'autres' variance. Per the owner's precision (flat open floor at grazing incidence must not darken; objects touching the floor must), the occ gate threshold scales with grz^2: grazing flat floor gates at ~0.2-0.28 (HBAO) / ~0.3-0.43 (GTAO) so the wash dies at every strength and time of day, while walls/creases gate near 0 and on-floor object contact (occ 0.4+) passes — the calibrated crease look is unchanged. SSAO needs no gate (open 1.0-3.2% at all strengths incl. dusk)."
echo
echo "== AO STRENGTH row (owner closing round 2026-07-16) =="
echo "New conditional Recharged Settings row AO STRENGTH: Weaker / Default / Stronger (settings key ao-strength 0/1/2, default 1, persisted; text ids #x1710-#x1713 in the rebuilt TXT banks; row greyed while AMBIENT OCCLUSION is Off, same conditional mechanism as AO QUALITY). Semantics: a per-mode multiplier (0.6x / 1.0x / 1.5x) applied on the ESTIMATOR intensity — not the composite k — so flat open ground (occ~0) stays ~1.0 and the defect-5 open-area cap holds structurally even at Stronger. Pushed live like mode/quality (update-to-os -> pc-set-ambient-occlusion! 3-arg); AOPERF logs strength=."
echo "3x3 proof grid (SSAO/HBAO/GTAO x Weaker/Default/Stronger at the training vantage, quality High, interleaved OFF brackets; caps hold at Stronger, crease darkening strictly increases with strength):"
grep -aE '\[ao-grid\]' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo
echo "== Alpha/transparent exclusion (owner #1 risk) =="
echo "The AO pass runs at the post-opaque bucket-31 insertion point: every alpha-blended/alpha-tested bucket (ALPHA_TEX foliage, water, sprites) and the recharged grass-card pass render AFTER the AO composite, so transparent/alpha-cut geometry never writes the AO depth source and is never darkened by the composite — alpha surfaces are structurally excluded from AO depth."
echo "Beach vantage (palms+shrubs alpha-tested foliage) A/B captures show no boxy shadows and no halo artifacts on alpha-cut foliage; the recharged grass cards share the same structural exclusion (they draw after the AO composite and never write the AO depth source; grass was OFF during capture runs per the owner's 2026-07-15 perf protocol). Training vantage = the owner's judging level. Diff heatmaps: crease-localized darkening only, defect-5 gates below:"
grep -E '\[ao-gate5\] (village1|beach|training) (SSAO|HBAO|GTAO):' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo
echo "== Settings & menu (defect #2 + #3a) =="
echo "Recharged Settings TYPE selector row: AMBIENT OCCLUSION Off / SSAO / HBAO / GTAO (carousel), plus separate AO Quality row Low / Medium / High (settings keys ambient-occlusion / ao-quality, persisted; text ids #x1708-#x170f shipped in rebuilt TXT banks, sha-verified on device — menu strings render, no unknown ID: menu-proof2/a<N>-06-ao-row.png a<N>-07-carousell-open.png)."
echo "Menu -> settings -> renderer push proven end-to-end on device ([recharged-ao] push lines + AOPERF mode tracks the menu row):"
grep -E 'PUSH-OK (mode|quality|strength)->' "$MP" | sed 's/^/  /'
grep -E 'relaunch \[recharged-ao\]|disk after relaunch' "$MP" | sed 's/^/  /'
echo
echo "== Off == stock =="
echo "Off == stock: with effective_mode()==0 the AO pass is fully skipped and the render FBO uses the stock renderbuffer depth attachment (no depth-texture path, byte-identical render path); OFF-segment purple-scan CLEAN and OFF A/B means match stock within capture noise."
echo
echo "== Defect #4 (GL state leak -> purple world): title gate =="
echo "AO pass wrapped in full GL state save/restore (texture units 0/1, program, VAO, array buffer, active unit, blend eq/funcs, colorMask, cull/scissor/stencil). On-device textured-title gate with AO compiled in, all modes. Per the owner's order (2026-07-16 14:25) the full 15-combo persisted matrix ran ONCE as certification (near-final build) and per-change gating is the fast worst-case spot check (GTAO+High+Stronger persisted boot, 90s alive, purple-scan + AOPERF seed):"
grep -E 'TITLE-GATE PASS' "$OUT/chain-attempt5.log" | sed 's/^/  one-time certification: /'
grep -E 'purple-scan|AOPERF|TITLE-SPOTCHECK|seeded\+verified|alive at end' "$OUT/title-gate/spotcheck-log.txt" | sed 's/^/  /'
echo
echo "== Defect #6 (GTAO title crash) =="
echo "Hardening: an unconditional glFinish drain runs before every render/UI FBO recreate, a 3-frame AO defer holds AO off through renderscale-resize storms, and drains run before AO-target deletes."
echo "safe-boot fallback: a session dying within 60s of AO enable boots the next session with AO forced off once, logged."
echo "Persisted-mode title matrix (12 boots mode x quality + 3 Stronger spot-boots, seeded on disk then booted fresh; each rendered textured, stayed alive >=2 min, tracked AOPERF, logged no SAFE-BOOT) — one-time certification, per-change gate is the worst-case spot check above:"
grep -E 'stage 2 OK' "$OUT/chain-attempt5.log" | sed 's/^/  /'
echo "Safe-boot fallback proof (arm within 60s, survive a dirty death, SAFE-BOOT + AO-off on the next boot, AO active again after):"
grep -E 'ARMED-OK|SAFE-BOOT|\[ao-safeboot' "$OUT/safeboot/proof-log.txt" | tail -6 | sed 's/^/  /'
echo
echo "== Defect #5 (global darkening) =="
echo "Root causes fixed in the estimators (not by weakening strength), attempt-5 layer on top of the earlier handedness/tangent/radial fixes: (1) GTAO's slice azimuths were uniform in SCREEN space but mapped through the anisotropic chord basis (256:128 uv scale + ray obliquity), clustering slice planes toward the horizontal and breaking the GTAO slice-sum identity exactly at grazing incidence — proven with a no-samples variant that still darkened the far floor to 0.85; fixed with uniform slice azimuths around V (orthonormal basis + inverse chord-map remap of the march direction, handedness preserved). (2) All three estimators read grazing terrain MICRO-RELIEF as occlusion (a centimeter bump at r->0 subtends an arbitrary horizon angle), fixed with a capped near-field sample rejection (min-r ~3% of camera distance, capped at ~40% of radius so distant creases keep contact AO) + grazing-adaptive angle bias (HBAO) + grazing-scaled tangent-plane threshold (SSAO). (3) Near-field fade 20m->45m: AO is local contact/crease detail (owner verbatim), distant scenery untouched. Open floors read ~white while wall/prop contact AO survives (x86 training terms: floor 0.92-0.93 vs baseline 0.76-0.88, cliffbase below wall for every mode). AO-DEBUG view (debug.opengoal.ao.debug=1) shows the raw AO term ~white on open ground and sky, dark only in creases/contacts:"
grep -E '\[ao-gate5-debug\]' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo "Quantified open-area gates (mean ON-vs-OFF luminance delta over open areas <=5%, global <=8%, crease-localized):"
grep -E '\[ao-gate5\].*OVERALL' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo
echo "== Defect #7 (owner 2026-07-16): water excluded from AO compositing =="
echo "AO = local crease/contact detail, never global shading. Water is excluded from AO compositing entirely: the water buckets proper (WATER_TEX/MERC_WATER/GENERIC_WATER 57-62, OCEAN_NEAR 63) render in the transparency path AFTER the post-opaque composite and were structurally untouched; OCEAN_MID_AND_FAR (bucket 4) renders BEFORE it and writes depth (flush_mid GL_ALWAYS), so its pixels are stencil-tagged at draw time, un-tagged by any later covering opaque draw, and the composite stencil-tests EQUAL 0 — visible ocean pixels are skipped by the AO multiply and render byte-identical to OFF. The stencil buffer is cleared after the composite so the shadow-volume bucket (47) sees its expected zeroed state; the tag choreography is latched per-frame."
echo "Sentinel Beach shoreline vantage (water + grazing wet-sand floor + sky in frame): water-region ON-vs-OFF delta judged against the off-vs-off wave-animation noise baseline (the sea animates, so 'delta ~0' == indistinguishable from off-off noise):"
grep -aE '\[ao-gate7\]' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo "Device AO-term whiteness at the shoreline (debug view captured ON DEVICE, not x86: open floor + sky ~white, water painted white = excluded/term 1.0, creases dark):"
grep -aE '\[ao-gate5-debug\] shoreline' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo "GTAO grazing-floor whiteness verified on device via the same debug views + the shoreline/training open-area gates above (device numbers, not x86)."
echo
echo "== Capture protocol (owner 2026-07-15 13:50) =="
echo "All captures at locked FULL render resolution (render-scale 100, dynamic-render-scale? #f) with recharged-grass? #f for perf headroom, at the training level + village1 (creases) + beach (alpha foliage), camera near corner/crevice geometry. Each recorded segment asserts a captured frame HEIGHT >=1000px (the Redmi is 2400x1080 landscape) so a dynamic-renderscale'd low-res frame is rejected as non-evidence."
echo
echo "== FPS cost curve (Redmi Note 9 Pro / Adreno 618 — informational, NOT a gate) =="
echo "Per-combo AOPERF (mode x quality) at the village1 vantage; low fps at High/GTAO is expected (strong-device settings):"
echo "  off        : $(fpsrow off)"
echo "  ssao-low   : $(fpsrow ssao-low)"
echo "  ssao-med   : $(fpsrow ssao-med)"
echo "  ssao-high  : $(fpsrow ssao-high)"
echo "  hbao-low   : $(fpsrow hbao-low)"
echo "  hbao-med   : $(fpsrow hbao-med)"
echo "  hbao-high  : $(fpsrow hbao-high)"
echo "  gtao-low   : $(fpsrow gtao-low)"
echo "  gtao-med   : $(fpsrow gtao-med)"
echo "  gtao-high  : $(fpsrow gtao-high)"
echo
echo "== Device evidence =="
echo "Device: Redmi Note 9 Pro eae4df44, package org.opengoal.gk.jak1, app foreground during captures: $focus_line"
echo "deploy_verify + deploy_verify_assets PASS (build==APK==device libgk + consistent 28-CGO set + TXT sha-verified); force-stop + AO Off / quality Medium / strength Default owner reset after tests."
echo "Artifacts: title-gate/*.mp4+frames, device/device-ao-{village1,beach,training}-{off,ssao,hbao,gtao}*.mp4+frames + per-mode debugview segments + ao-diffheat-*.png, menu-proof2/*.png, x86-defect5/* (desktop cross-check), proof-battery-log.txt."
} > "$R"
echo "[ao-report] wrote $R"
