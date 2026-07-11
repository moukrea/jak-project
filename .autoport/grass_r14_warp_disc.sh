#!/usr/bin/env bash
# grass_r14_warp_disc.sh — ROUND#14: warp Jak EXACTLY onto raised platform-edge coords (dumped by the
# placement as RIMCAND) and capture the discriminator quad there, so we finally see a REAL platform rim
# over a drop and discriminate the floating (H-A geometry / H-B base-past-silhouette / H-C cards).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r14warp FAIL] $*" >&2; exit 1; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }
dbg(){ $ADB shell setprop debug.opengoal.grass_dbg "$1"; sleep 1.4; }
quad(){ dbg 0; cap "${1}_m0_normal"; dbg 1; cap "${1}_m1_bases"; dbg 2; cap "${1}_m2_blades"; dbg 3; cap "${1}_m3_cards"; dbg 0; }

boot_warp(){ # $1 = pos-string ("" for none) ; $2 = logfile
  local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr14w_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  warming to title..."
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 160 ]; do grep -qa 'link finish: logo' "$LOG" && break; sleep 2; done
  echo "  waiting LEVEL-WARP-SPAWN training-start..."
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qa 'LEVEL-WARP-FAIL' "$LOG" && { echo "  LEVEL-WARP-FAIL"; break; }
    sleep 3
  done
  sleep 6; echo "  warp_ok=$ok"
}

# ================= build/install =================
say "0. assemble APK (coord-dump + discriminator libgk) + install + deploy_verify"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "no libgk.so"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
$ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB shell pm trim-caches 999G 2>/dev/null || true
$ADB install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"

# ================= boot 1: harvest RIMCAND coords =================
say "1. boot warp training-start (no pos) -> harvest RIMCAND platform-edge coords"
boot_warp "" /tmp/gr14w_harvest.log
grep -aE 'recharged-grass\] RIMCAND' /tmp/gr14w_harvest.log | tail -20 | tee "$OUT/p14_rimcand.txt"
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge CLAMP' /tmp/gr14w_harvest.log | tail -1
# pick the top tfrag coord and the top TIE coord
TFRAG_POS=$(grep -aE 'RIMCAND .* tfrag ' /tmp/gr14w_harvest.log | head -1 | grep -aoE 'pos="[^"]+"' | head -1 | sed 's/pos=//;s/"//g')
TIE_POS=$(grep -aE 'RIMCAND .* TIE ' /tmp/gr14w_harvest.log | head -1 | grep -aoE 'pos="[^"]+"' | head -1 | sed 's/pos=//;s/"//g')
HI_POS=$(grep -aE 'RIMCAND 0 ' /tmp/gr14w_harvest.log | head -1 | grep -aoE 'pos="[^"]+"' | head -1 | sed 's/pos=//;s/"//g')
echo "  TFRAG_POS=[$TFRAG_POS]  TIE_POS=[$TIE_POS]  HI_POS=[$HI_POS]"

capture_at(){ # $1=tag  $2=pos
  local TAG="$1" POS="$2"
  [ -n "$POS" ] || { echo "  (no coord for $TAG, skip)"; return; }
  say "warp Jak to $TAG pos='$POS' and capture edge quad"
  boot_warp "$POS" "/tmp/gr14w_${TAG}.log"
  # frame the edge: pitch camera down, quad; then orbit and quad again
  stick "ry=245"; sleep 1.4; stick "neutral"; sleep 0.4
  quad "p14_rim_${TAG}_a"
  pulse "rx=200" 1.0 0.5
  stick "ry=235"; sleep 0.9; stick "neutral"; sleep 0.4
  quad "p14_rim_${TAG}_b"
  FOCUS=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "  focus=$FOCUS"
}

capture_at "hi"    "$HI_POS"
capture_at "tie"   "$TIE_POS"

say "restore + FORCE-STOP (device hygiene)"
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr14w_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r14warp] DONE — quads p14_rim_hi_* / p14_rim_tie_* in $F"
