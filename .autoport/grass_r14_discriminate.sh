#!/usr/bin/env bash
# grass_r14_discriminate.sh — ROUND#14 floating-mechanism DISCRIMINATOR on device eae4df44.
# Renderer-only debug build: prop debug.opengoal.grass_dbg pins u_debug in grass.vert
#   0 = normal   1 = bases-only MAGENTA stubs (blades)   2 = blades only CYAN   3 = cards only YELLOW
# At each waypoint (walking toward the terraces / island edge, camera pitched down) we capture the
# SAME viewpoint in all 4 pinned modes. Whatever step lands at a real platform rim, its quad tells us:
#   * MAGENTA base-stubs float over the void  => H-B (bases past the silhouette) — fix BASE PLACEMENT
#   * only CYAN tall blades float (stubs hug)  => H-A (blade geometry) — tighten the clamp
#   * only YELLOW cards float                  => H-C (cards) — clamp/exclude cards
# Force-stops at the end (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r14disc FAIL] $*" >&2; exit 1; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }
dbg(){ $ADB shell setprop debug.opengoal.grass_dbg "$1"; sleep 1.4; }
# capture the 4 pinned modes at the current held viewpoint
quad(){ # $1 = tag
  dbg 0; cap "${1}_m0_normal"
  dbg 1; cap "${1}_m1_bases"
  dbg 2; cap "${1}_m2_blades"
  dbg 3; cap "${1}_m3_cards"
  dbg 0
}

set_grass(){ # $1 = t|f
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs14.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs14.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs14.gc
    $ADB push /tmp/pcs14.gc /data/local/tmp/pcs14.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs14.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs14.gc >/dev/null 2>&1
  fi
  echo "  setting now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"
}

load_geyser(){
  local LOG="$1"
  $ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
  $ADB logcat -c >/dev/null 2>&1
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr14_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting for title..."
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 160 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
  sleep 4
  pulse "start" 0.4 2.0; pulse "down" 0.35 0.8; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0
  echo "  waiting for training gameplay..."
  local got=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 160 ]; do
    mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1); [ "$mm" = "master-mode=game" ] && { got=1; break; }; sleep 3
  done
  sleep 5; echo "  got_game=$got"
}

say "0. assemble APK (fresh discriminator libgk) + install -r + deploy_verify"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "no built libgk.so"
GH=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'recharged.?grass|grass.?blade|g_grass')
echo "  libgk grass strings: ${GH:-0}"; [ "${GH:-0}" -gt 0 ] || die "libgk has no grass strings"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB shell pm trim-caches 999G 2>/dev/null || true
$ADB install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify FAIL"
echo "  deploy_verify PASS"

say "1. load Geyser Rock (grass ON)"
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
set_grass t
load_geyser /tmp/gr14_on.log
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge CLAMP' /tmp/gr14_on.log | tail -1
grep -aE 'recharged-grass\] ROUND#13 OVERHANG-LIP' /tmp/gr14_on.log | tail -1

say "2. discriminator quads walking toward the terraces / island edge (camera pitched down)"
# waypoint 0: at spawn, camera pitched down a little
stick "ry=245"; sleep 1.4; stick "neutral"; sleep 0.4
quad p14_disc_w0
# then step forward toward the raised terraces, quad each step; some step lands at a rim/edge
for i in 1 2 3 4 5 6; do
  pulse "ly=0" 0.42 0.7           # forward step (a bit larger to cover ground)
  stick "ry=245"; sleep 0.6; stick "neutral"; sleep 0.4   # keep camera pitched down
  quad "p14_disc_w${i}"
done

say "3. orbit + look for a side-on rim (distant raised platform silhouette)"
for yw in "rx=200" "rx=200" "rx=160"; do
  stick "$yw"; sleep 1.1; stick "neutral"; sleep 0.3
  quad "p14_disc_${yw/=/_}"
done

FOCUS=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus=$FOCUS"

say "4. restore normal grass + FORCE-STOP (device hygiene)"
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr14_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r14disc] DONE — quads in $F/p14_disc_*"
