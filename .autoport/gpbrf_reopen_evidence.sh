#!/usr/bin/env bash
# gpbrf_reopen_evidence.sh — REOPEN 2026-07-23 (plastic-shine / industry-BRDF) device evidence.
# Thin resumable driver over gpbrf_evidence.sh: each capture is skipped when its png already
# exists AND is newer than the deploy stamp (build-deploy-reopen.log), so a died run resumes.
# Order: fused set (default / n0 / glossy / matte / night / night-noemis) -> rtonly -> bidon
# -> stock -> restore owner-ready fused state.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
EV=.autoport/gpbrf_evidence.sh
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
STAMP=.autoport/reports/Grecharged-pbr-realtime-fusion/build-deploy-reopen.log
die(){ echo "[gpbrf-reopen FAIL] $*" >&2; exit 1; }
[ -f "$STAMP" ] || die "no deploy stamp $STAMP — run gpbrf_build_deploy.sh first"

fresh(){ [ -f "$OUT/$1.png" ] && [ "$OUT/$1.png" -nt "$STAMP" ]; }
step(){ echo; echo "======== [reopen-ev] $* ========"; }

step "config fused + normalize the full user map set"
bash "$EV" abset fused || die "abset fused"
bash "$EV" push full || die "push full"
bash "$EV" push roughback || die "push roughback"   # drop any stale user roughness
bash "$EV" push emisback || die "push emisback"

if ! fresh fused_h8; then step "cap fused_h8 (default render, keep mp4)"; bash "$EV" cap fused_h8 8 '' 1 || die "cap fused_h8"; fi
if ! fresh fused_n0_h8; then step "cap fused_n0_h8 (nstrength 0)"; bash "$EV" cap fused_n0_h8 8 0 || die "cap fused_n0_h8"; fi

if ! fresh fused_glossy_h8; then
  step "roughness GLOSSY(40) A"; bash "$EV" push glossy || die "push glossy"
  bash "$EV" cap fused_glossy_h8 8 || die "cap glossy"
fi
if ! fresh fused_matte_h8; then
  step "roughness MATTE(230) B"; bash "$EV" push matte || die "push matte"
  bash "$EV" cap fused_matte_h8 8 || die "cap matte"
fi
step "roughness back to bundled"
bash "$EV" push roughback || die "push roughback2"

if ! fresh fused_night; then step "cap fused_night (TOD 0, keep mp4)"; bash "$EV" cap fused_night 0 '' 1 || die "cap night"; fi
if ! fresh fused_night_noemis; then
  step "night control without _emissive"
  bash "$EV" push noemis || die "push noemis"
  bash "$EV" cap fused_night_noemis 0 || die "cap night noemis"
  bash "$EV" push emisback || die "push emisback2"
fi

if ! fresh rtonly_h8; then
  step "rtonly (rt ON + pbr OFF — accepted baked-modulation, no-regression + baked-base reference)"
  bash "$EV" abset rtonly || die "abset rtonly"
  bash "$EV" cap rtonly_h8 8 || die "cap rtonly"
fi
if ! fresh bidon_h8; then
  step "bidon (rt OFF + pbr ON — standalone fallback intact)"
  bash "$EV" abset bidon || die "abset bidon"
  bash "$EV" cap bidon_h8 8 || die "cap bidon"
fi
if ! fresh stock_h8; then
  step "stock (rt OFF + pbr OFF — golden rule)"
  bash "$EV" abset stock || die "abset stock"
  bash "$EV" cap stock_h8 8 || die "cap stock"
fi

step "loadcheck on the fused boot log"
bash "$EV" loadcheck fused_h8 || die "loadcheck"

step "restore owner-ready fused state + clear pin props"
bash "$EV" abset fused || die "abset fused final"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44
for p in level.warp level.warp.pos tod.hour tod.fast renderscale.native pbr.nstrength pbr.debug rt.light rt.sunelev pbr.shadowmap; do
  "$ADB" -s "$S" shell "setprop debug.opengoal.$p ''" || true
done
echo "[gpbrf-reopen] ALL CAPTURES DONE"
