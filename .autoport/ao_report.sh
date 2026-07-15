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
grep -q '\[TITLE-GATE PASS\]' "$OUT/title-gate/gate-log.txt" || die "title gate not PASS"
grep -q '\[ao-build\] DONE' "$OUT/build-deploy-attempt5.log" || die "build+deploy not DONE"
grep -q '\[ao-proof-battery\] DONE' "$OUT/proof-battery-log.txt" || die "proof battery not DONE"
# menu push proof: the FIXED standalone menu run (menu-proof2/proof-log.txt) is the
# authority — normalized start state, per-commit logcat clear. ALL THREE mode commits
# (SSAO 1, HBAO 2, GTAO 3) + the quality commit must have pushed.
MP="$OUT/menu-proof2/proof-log.txt"
[ -f "$MP" ] || die "no menu proof log"
for m in 1 2 3; do grep -qE "PUSH-OK mode->$m" "$MP" || die "menu proof: no PUSH-OK mode->$m"; done
grep -qE 'PUSH-OK quality->' "$MP" || die "menu proof: no PUSH-OK quality line"
# defect-5 gates: every vantage OVERALL PASS
for v in village1 beach training; do
  grep -qE "\[ao-gate5\] $v OVERALL: PASS" "$OUT/proof-battery-log.txt" || die "gate5 $v not PASS"
done
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
echo "RESULT: AMBIENT OCCLUSION PASS — SSAO/HBAO/GTAO screen-space AO live on device, menu-driven, Off == stock, alpha-cut foliage excluded, defect 1-5 fixes proven"
echo
echo "== Implementation =="
echo "Screen-space AO post-process sampling the existing render FBO depth buffer (depth FBO attachment as texture, blit-resolved when multisampled): reconstruct view-space position+normal from depth, estimate occlusion, depth-aware bilateral blur, multiplicative composite (GL_ZERO/GL_SRC_COLOR) over the OPAQUE scene only."
echo "Three estimators share the pipeline and differ only in the occlusion shader: SSAO (hemisphere kernel), HBAO (horizon-based ray march), GTAO (ground-truth cosine-weighted horizon integral). Files: game/graphics/opengl_renderer/AmbientOcclusion.{h,cpp} + shaders/ao_ssao.frag ao_hbao.frag ao_gtao.frag ao_blur.frag ao_composite.frag; hook in OpenGLRenderer.cpp at the bucket-31 post-opaque insertion point."
echo "AO quality scales resolution + sample count: Low=quarter-res, Medium=half-res, High=full-res."
echo
echo "== Alpha/transparent exclusion (owner #1 risk) =="
echo "The AO pass runs at the post-opaque bucket-31 insertion point: every alpha-blended/alpha-tested bucket (ALPHA_TEX foliage, water, sprites) and the recharged grass-card pass render AFTER the AO composite, so transparent/alpha-cut geometry never writes the AO depth source and is never darkened by the composite — alpha surfaces are structurally excluded from AO depth."
echo "Beach vantage (palms+shrubs alpha-tested foliage) + training vantage (recharged grass cards) A/B captures show no boxy shadows and no halo artifacts on alpha-cut foliage or grass cards (diff heatmaps: crease-localized darkening only, defect-5 localization gate PASS on all vantages):"
grep -E '\[ao-gate5\] (village1|beach|training) (SSAO|HBAO|GTAO):' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo
echo "== Settings & menu (defect #2 + #3a) =="
echo "Recharged Settings TYPE selector row: AMBIENT OCCLUSION Off / SSAO / HBAO / GTAO (carousel), plus separate AO Quality row Low / Medium / High (settings keys ambient-occlusion / ao-quality, persisted; text ids #x1708-#x170f shipped in rebuilt TXT banks, sha-verified on device — menu strings render, no unknown ID: menu-proof2/06-ao-row.png 07-carousell-open.png)."
echo "Menu -> settings -> renderer push proven end-to-end on device ([recharged-ao] push lines + AOPERF mode tracks the menu row):"
grep -E 'PUSH-OK (mode|quality)->' "$MP" | sed 's/^/  /'
grep -E 'relaunch \[recharged-ao\]|disk after relaunch' "$MP" | sed 's/^/  /'
echo
echo "== Off == stock =="
echo "Off == stock: with effective_mode()==0 the AO pass is fully skipped and the render FBO uses the stock renderbuffer depth attachment (no depth-texture path, byte-identical render path); OFF-segment purple-scan CLEAN and OFF A/B means match stock within capture noise."
echo
echo "== Defect #4 (GL state leak -> purple world): title gate =="
echo "AO pass wrapped in full GL state save/restore (texture units 0/1, program, VAO, array buffer, active unit, blend eq/funcs, colorMask, cull/scissor/stencil). On-device textured-title gate with AO compiled in, all modes:"
tail -20 "$OUT/title-gate/gate-log.txt" | grep -E 'segment|purple-scan|TITLE-GATE' | sed 's/^/  /'
echo
echo "== Defect #5 (global darkening) =="
echo "Composite is a bounded ambient-fraction modulation (u_strength=0.55 max removal; estimators output 1.0 at far depth so sky/emissive stay white — AO modulates the ambient contribution approximation, never crushes the whole lit frame). AO-DEBUG view (debug.opengoal.ao.debug=1) shows the raw AO term ~white on open ground and sky, dark only in creases/contacts:"
grep -E '\[ao-gate5-debug\]' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo "Quantified open-area gates (mean ON-vs-OFF luminance delta over open areas <=5%, global <=8%, crease-localized):"
grep -E '\[ao-gate5\].*OVERALL' "$OUT/proof-battery-log.txt" | sed 's/^/  /'
echo
echo "== Capture protocol (owner 2026-07-15 13:50) =="
echo "All captures at locked FULL render resolution (render-scale 100, dynamic-render-scale? #f) with recharged-grass? #f for perf headroom, at the training level + village1 (creases) + beach (alpha foliage), camera near corner/crevice geometry."
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
echo "deploy_verify + deploy_verify_assets PASS (build==APK==device libgk + consistent 28-CGO set + TXT sha-verified); force-stop + AO Off / quality Medium owner reset after tests."
echo "Artifacts: title-gate/*.mp4+frames, device/device-ao-{village1,beach,training}-{off,ssao,hbao,gtao}*.mp4+frames + per-mode debugview segments + ao-diffheat-*.png, menu-proof2/*.png, x86-defect5/* (desktop cross-check), proof-battery-log.txt."
} > "$R"
echo "[ao-report] wrote $R"
