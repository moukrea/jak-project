#!/usr/bin/env bash
# gpbrf_resume_evidence.sh — attempt-3 resume of gpbrf_run_evidence.sh from step 9.
# Steps 1-8 completed in attempt 2 (captures + loadcheck already in the device dir);
# the run died mid `cap fused_night`. Device is still config=fused with the full user
# map set (metal0 restored). Only the night pair, metrics and owner-ready state remain.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
EV=.autoport/gpbrf_evidence.sh
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
MET="$OUT/metrics.txt"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf-run FAIL] $*" >&2; exit 1; }
[ -f /tmp/gpbrf_maps/vil1-sages-stonewall-01_emissive.png ] || die "synthesized maps missing in /tmp/gpbrf_maps"
[ -f "$OUT/fused_h8.png" ] || die "attempt-2 captures missing; run the full gpbrf_run_evidence.sh instead"

say "9. NIGHT emissive glow (tod 0) + no-emissive control — keep mp4 (RESUME)"
bash $EV push emisback          || die emisback-pre   # ensure emissive present regardless of died-run state
bash $EV cap fused_night 0 '' 1 || die night-cap
bash $EV push noemis            || die push-noemis
bash $EV cap fused_night_noemis 0 || die noemis-cap
bash $EV push emisback          || die emisback

say "10. metrics"
: > "$MET"
{
  echo "== normal-map drive (nstrength 3 default vs 0, same vantage h8, DEFAULT render) =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_h8.png" "$OUT/fused_n0_h8.png"
  echo "== TOD sweep (h8 vs h16, fused) — shading follows the realtime sun =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_h8.png" "$OUT/fused_h16.png"
  echo "== roughness A/B (glossy 40 vs matte 230) — GGX specular response =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_glossy_h8.png" "$OUT/fused_matte_h8.png"
  echo "== metallic A/B (black vs white) — diffuse kill + spec tint =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_h8.png" "$OUT/fused_metal1_h8.png"
  echo "== emissive night glow vs no-emissive control =="
  python3 .autoport/gpbrf_measure.py glow "$OUT/fused_night.png" "$OUT/fused_night_noemis.png"
  echo "== fused vs bidon (two distinct paths) =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_h8.png" "$OUT/bidon_h8.png"
  echo "== fused vs rt-only (maps drive the rt-lit result) =="
  python3 .autoport/gpbrf_measure.py pair "$OUT/fused_h8.png" "$OUT/rtonly_h8.png"
  echo "== sanity stats =="
  python3 .autoport/gpbrf_measure.py stats "$OUT/stock_h8.png"
  python3 .autoport/gpbrf_measure.py stats "$OUT/rtonly_h8.png"
  python3 .autoport/gpbrf_measure.py stats "$OUT/bidon_h8.png"
} | tee -a "$MET"

say "11. leave OWNER-READY state (fused settings + full user set; clear pin props only)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
for p in level.warp level.warp.pos tod.hour tod.fast renderscale.native pbr.nstrength pbr.debug pbr.shadowmap; do
  "$ADB" -s eae4df44 shell "setprop debug.opengoal.$p ''"; done
echo "[gpbrf-run] DONE — captures + metrics in $OUT"
