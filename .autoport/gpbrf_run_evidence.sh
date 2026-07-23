#!/usr/bin/env bash
# gpbrf_run_evidence.sh — full evidence sequence for Grecharged-pbr-realtime-fusion.
# Assumes the fused APK is installed + deploy_verified (gpbrf_build_deploy.sh) and the
# synthesized maps exist in /tmp/gpbrf_maps (built by the manager).
# Final state is OWNER-READY: fused settings + full user map set left on device.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
EV=.autoport/gpbrf_evidence.sh
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
MET="$OUT/metrics.txt"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf-run FAIL] $*" >&2; exit 1; }
[ -f /tmp/gpbrf_maps/vil1-sages-stonewall-01_emissive.png ] || die "synthesized maps missing in /tmp/gpbrf_maps"

say "1. STOCK (rt OFF + pbr OFF) — golden-rule reference"
bash $EV abset stock            || die stock-set
bash $EV cap stock_h8 8         || die stock-cap

say "2. RT-ONLY (rt ON + pbr OFF) — accepted directional-ambient, must be the no-regression look"
bash $EV abset rtonly           || die rtonly-set
bash $EV cap rtonly_h8 8        || die rtonly-cap

say "3. BIDON (rt OFF + pbr ON) — standalone fallback intact"
bash $EV abset bidon            || die bidon-set
bash $EV push full              || die push-full
bash $EV cap bidon_h8 8         || die bidon-cap

say "4. FUSED day (rt ON + pbr ON) — keep mp4"
bash $EV abset fused            || die fused-set
bash $EV cap fused_h8 8 '' 1    || die fused-cap
bash $EV loadcheck fused_h8     || die loadcheck

say "5. FUSED TOD moved (h16) — shading must follow the realtime sun"
bash $EV cap fused_h16 16       || die h16-cap

say "6. FUSED normal-strength 0 (same vantage/hour) — normal-map drive A/B"
bash $EV cap fused_n0_h8 8 0    || die n0-cap

say "7. roughness A/B (user map swap, user>bundled precedence)"
bash $EV push glossy            || die push-glossy
bash $EV cap fused_glossy_h8 8  || die glossy-cap
bash $EV push matte             || die push-matte
bash $EV cap fused_matte_h8 8   || die matte-cap
bash $EV push roughback         || die roughback

say "8. metallic A/B"
bash $EV push metal1            || die push-metal1
bash $EV cap fused_metal1_h8 8  || die metal1-cap
bash $EV push metal0            || die push-metal0

say "9. NIGHT emissive glow (tod 0) + no-emissive control — keep mp4"
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
for p in level.warp level.warp.pos tod.hour tod.fast renderscale.native pbr.nstrength pbr.debug; do
  "$ADB" -s eae4df44 shell "setprop debug.opengoal.$p ''"; done
echo "[gpbrf-run] DONE — captures + metrics in $OUT"
