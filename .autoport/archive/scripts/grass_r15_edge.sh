#!/usr/bin/env bash
# grass_r15_edge.sh — ROUND#15: prove the topology-INDEPENDENT coverage distance-field stops grass at
# the rim on MULTIPLE previously-overflowing platform edges. Warp Jak to RIMCAND coords, pitch the camera
# DOWN at the rim, capture ON vs OFF (A/B). Also harvest the COVFIELD/RIMDIST instrumentation and refresh
# the generic device artifacts (now.png + a moving mp4). Force-stops at the end (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r15 FAIL] $*" >&2; exit 1; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject neutral; sleep "${3:-1.0}"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs15.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs15.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs15.gc
    $ADB push /tmp/pcs15.gc /data/local/tmp/pcs15.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs15.gc "$PCS" 2>/dev/null || true; $ADB shell rm -f /data/local/tmp/pcs15.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }

boot_warp(){ # $1 = pos ("" none); $2 = logfile
  local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr15_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 170 ]; do grep -qa 'link finish: logo' "$LOG" && break; grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }; grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break; sleep 3; done
  sleep 6; echo "  warp_ok=$ok"; return $((1-ok)); }

record_walk(){ local TAG="$1"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit 20 --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1; stick "ry=238"; sleep 1.0
  for turn in "" "rx=170" "rx=170" "rx=170"; do
    [ -n "$turn" ] && { stick "$turn"; sleep 0.8; }
    stick "ly=0"; sleep 2.0; stick "neutral"; sleep 0.8; stick "ry=236"; sleep 0.4
  done
  stick "neutral"; wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1 && echo "  pulled ${TAG}.mp4=$(stat -c %s "$OUT/${TAG}.mp4" 2>/dev/null)B"; }

# frame an edge: pitch down, capture; small orbit, capture; step to the rim, capture
edge_shots(){ local TAG="$1"
  stick "ry=245"; sleep 1.4; stick "neutral"; sleep 0.4; cap "${TAG}_a"
  pulse "rx=200" 1.0 0.5; stick "ry=235"; sleep 0.9; stick "neutral"; sleep 0.4; cap "${TAG}_b"
  stick "ly=0"; sleep 1.3; stick "neutral"; sleep 0.6; stick "ry=242"; sleep 0.8; stick "neutral"; sleep 0.4; cap "${TAG}_c"
  echo "  focus=$(focus)"; }

# ===== 0. assemble + install + deploy_verify =====
say "0. assemble APK (round#15 coverage-field libgk) + install + deploy_verify"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "no libgk.so — build first"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle failed"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
$ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB shell pm trim-caches 999G 2>/dev/null || true
$ADB install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"

# ===== 1. harvest RIMCAND + COVFIELD + RIMDIST (grass ON) + generic artifacts =====
say "1. boot warp training-start (no pos) -> harvest instrumentation + fresh now.png/mp4"
set_grass t
boot_warp "" /tmp/gr15_harvest.log
: > "$OUT/p15_covfield.txt"
grep -aE 'recharged-grass\] COVFIELD' /tmp/gr15_harvest.log | tail -3 | tee -a "$OUT/p15_covfield.txt"
grep -aE 'recharged-grass\] RIMDIST'  /tmp/gr15_harvest.log | tail -3 | tee -a "$OUT/p15_covfield.txt"
grep -aE 'recharged-grass\] RIMCAND'  /tmp/gr15_harvest.log | tail -20 | tee "$OUT/p15_rimcand.txt"
echo "  focus=$(focus)"
cap now
record_walk grass_p15_move
command -v ffmpeg >/dev/null 2>&1 && [ -s "$OUT/grass_p15_move.mp4" ] && ffmpeg -y -loglevel error -i "$OUT/grass_p15_move.mp4" -vf fps=2 "$F/grass_p15_move_%03d.png" 2>/dev/null

# distinct high platform coords (RIMCAND is sorted highest-first; sample 0 / 3 / 6)
mapfile -t COORDS < <(grep -aoE 'pos="[^"]+"' /tmp/gr15_harvest.log | sed 's/pos=//;s/"//g')
P0="${COORDS[0]:-}"; P1="${COORDS[3]:-}"; P2="${COORDS[6]:-}"
echo "  P0=[$P0] P1=[$P1] P2=[$P2]"

# ===== 2. multi-edge ON captures =====
say "2. warp to multiple platform edges, grass ON, edge close-ups"
i=0
for P in "$P0" "$P1" "$P2"; do
  [ -n "$P" ] || { echo "  (no coord $i)"; i=$((i+1)); continue; }
  say "  ON edge $i pos='$P'"
  boot_warp "$P" "/tmp/gr15_on_$i.log" || echo "  boot flaked edge $i"
  edge_shots "p15_edge_${i}_on"
  i=$((i+1))
done

# ===== 3. OFF==stock A/B at the top edge =====
say "3. grass OFF, same top edge -> A/B stock proof"
set_grass f
boot_warp "$P0" /tmp/gr15_off0.log || echo "  off boot flaked"
edge_shots "p15_edge_0_off"
cap p15_off_stock
echo "  focus=$(focus)"

# ===== 4. restore ON + force-stop =====
say "4. restore grass ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr15_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r15] DONE — p15_edge_*_on/off + p15_covfield.txt + p15_rimcand.txt in $OUT"
