#!/usr/bin/env bash
# grass_r14_offedge.sh — ROUND#14 OFF==stock edge shot: same warp+walk traversal as the ON walkedge,
# but grass OFF (#f), so the matching over-water platform-edge frame shows STOCK (no grass) — the A/B
# partner for p14_rim_closeup_over_water_on. Retries the boot once if it hits the ~1-in-6 SIGILL flake.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
WARP_POS="-1296.8 55.0 987.2"
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs14o.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs14o.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs14o.gc
    $ADB push /tmp/pcs14o.gc /data/local/tmp/pcs14o.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs14o.gc "$PCS" 2>/dev/null || true; $ADB shell rm -f /data/local/tmp/pcs14o.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }
boot_warp(){ local LOG="$1"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr14o_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 160 ]; do grep -qa 'link finish: logo' "$LOG" && break; grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }; grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break; sleep 3; done
  sleep 6; echo "  warp_ok=$ok"; return $((1-ok)); }
record_walk(){ local TAG="$1"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit 26 --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1; stick "ry=238"; sleep 1.0
  for turn in "" "rx=170" "rx=170" "rx=170" "rx=170"; do
    [ -n "$turn" ] && { stick "$turn"; sleep 0.8; }
    stick "ly=0"; sleep 2.2; stick "neutral"; sleep 0.9; stick "ry=236"; sleep 0.4
  done
  stick "neutral"; wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1 && echo "  pulled ${TAG}.mp4=$(stat -c %s "$OUT/${TAG}.mp4" 2>/dev/null)B"
  command -v ffmpeg >/dev/null 2>&1 && [ -s "$OUT/${TAG}.mp4" ] && { ffmpeg -y -loglevel error -i "$OUT/${TAG}.mp4" -vf fps=4 "$F/${TAG}_%03d.png" 2>/dev/null; echo "  frames=$(ls $F/${TAG}_*.png 2>/dev/null|wc -l)"; }
}
echo "######## OFF==stock edge (grass #f) ########"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -2
set_grass f
boot_warp /tmp/gr14o_off.log || { echo "  boot flaked, retry"; boot_warp /tmp/gr14o_off2.log || echo "  second boot also flaked"; }
gl=$(grep -acaE 'recharged-grass\] training STATIC place' /tmp/gr14o_off.log /tmp/gr14o_off2.log 2>/dev/null); echo "  grass_place_lines_OFF=$gl"
record_walk p14_offedge
echo "######## restore ON + force-stop ########"
set_grass t
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr14o_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r14off] DONE"
