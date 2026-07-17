#!/usr/bin/env bash
# grass_r14_verify.sh — ROUND#14 fix verification via SCREENRECORD (screencap returns black for the
# game's GL SurfaceView; screenrecord is the reliable live-renderer path). Warps Jak onto the raised
# outcrop (RIMCAND 0 = solid landing), then ORBITS the camera pitched down while recording, so some
# frames frame the outcrop EDGE dropping to the meadow. Records: ON normal, ON base-stubs, OFF stock.
# ffmpeg extracts dense frames. Supervisor eyeballs the ON edge frames for floating. Force-stops.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
WARP_POS="-1296.8 55.0 987.2"   # RIMCAND 0 — solid landing (the hi session stood here, no fall)
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r14v FAIL] $*" >&2; exit 1; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
dbg(){ $ADB shell setprop debug.opengoal.grass_dbg "$1"; sleep 1.0; }

set_grass(){ # $1=t|f
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs14v.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs14v.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs14v.gc
    $ADB push /tmp/pcs14v.gc /data/local/tmp/pcs14v.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs14v.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs14v.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"
}

boot_warp(){ # $1=logfile
  local LOG="$1"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr14v_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 160 ]; do grep -qa 'link finish: logo' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qa 'LEVEL-WARP-FAIL' "$LOG" && break; sleep 3
  done
  sleep 6; echo "  warp_ok=$ok"
}

# record an orbit sweep (camera pitched down, continuous yaw) to /sdcard then pull + extract frames
record_orbit(){ # $1 = tag (mp4 + frame prefix)
  local TAG="$1"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit 16 --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1
  stick "ry=240"; sleep 1.2                 # pitch camera down toward the ground/edge
  stick "rx=200"; sleep 12                    # continuous slow orbit -> all sides of the outcrop
  stick "neutral"
  wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1 && echo "  pulled ${TAG}.mp4 = $(stat -c %s "$OUT/${TAG}.mp4" 2>/dev/null)B"
  if command -v ffmpeg >/dev/null 2>&1 && [ -s "$OUT/${TAG}.mp4" ]; then
    ffmpeg -y -loglevel error -i "$OUT/${TAG}.mp4" -vf fps=3 "$F/${TAG}_%03d.png" 2>/dev/null
    echo "  extracted $(ls $F/${TAG}_*.png 2>/dev/null | wc -l) frames for ${TAG}"
  fi
}

say "0. assemble APK (fix libgk) + install + deploy_verify"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
$ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB shell pm trim-caches 999G 2>/dev/null || true
$ADB install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"

say "1. ON (fixed) — warp to outcrop, record orbit (normal) then base-stubs"
set_grass t
boot_warp /tmp/gr14v_on.log
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge CLAMP' /tmp/gr14v_on.log | tail -1
dbg 0; record_orbit p14_edge_on
dbg 1; record_orbit p14_edge_on_bases
dbg 0
FOCUS_ON=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "  focus_on=$FOCUS_ON"

say "2. OFF (stock) — same warp, grass #f, same orbit (OFF==stock proof)"
set_grass f
boot_warp /tmp/gr14v_off.log
gl=$(grep -acaE 'recharged-grass\] training STATIC place' /tmp/gr14v_off.log); echo "  grass_place_lines_OFF=$gl (0 == OFF==stock)"
record_orbit p14_edge_off
FOCUS_OFF=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "  focus_off=$FOCUS_OFF"

say "3. restore default ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr14v_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r14v] DONE — p14_edge_on_* / _bases_* / _off_* frames in $F"
