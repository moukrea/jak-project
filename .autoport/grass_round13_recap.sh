#!/usr/bin/env bash
# grass_round13_recap.sh — ON-only re-capture after the non-grass-TIE occluder fix (grass platforms
# no longer self-occlude). Reassemble APK + install + deploy_verify (HARD GATE), load Geyser (ON),
# harvest the ROUND#13 STATIC place (new occ_culled %) + OVERHANG-LIP lines, capture WIDE spawn stills,
# restore ON + force-stop. OFF==stock already proven in the prior run (OFF path unchanged).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc
F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r13r FAIL] $*" >&2; exit 1; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs13r.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs13r.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs13r.gc
    $ADB push /tmp/pcs13r.gc /data/local/tmp/pcs13r.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs13r.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs13r.gc >/dev/null 2>&1
  fi
  echo "  setting now: $($ADB shell cat "$PCS" 2>/dev/null | grep 'recharged-grass?' | tr -d '\r')"; }

load_geyser(){ local LOG="$1"
  $ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
  $ADB logcat -c >/dev/null 2>&1
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr13r_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting for title..."; local t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
  sleep 4
  pulse "start" 0.4 2.0; pulse "down" 0.35 0.8; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0
  echo "  waiting for training gameplay..."; local got=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do
    mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1); [ "$mm" = "master-mode=game" ] && { got=1; break; }; sleep 3
  done
  sleep 5; echo "  got_game=$got"; }

say "0. assemble APK (fresh libgk, non-grass-TIE occluder) + install -r + deploy_verify"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -4 ) || die "gradle assemble failed"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"
echo "  deploy_verify PASS"

say "1. ON RUN — load Geyser, harvest ROUND#13 lines"
LOG_ON=/tmp/gr13r_on.log
set_grass t
load_geyser "$LOG_ON"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -1 | tee "$OUT/p13_static_place.txt"
grep -aE 'recharged-grass\] ROUND#13 OVERHANG-LIP' "$LOG_ON" | tail -1 | tee "$OUT/p13_overhang_lip.txt"
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge CLAMP' "$LOG_ON" | tail -1 | tee -a "$OUT/p13_overhang_lip.txt"

say "WIDE spawn stills — several angles"
stick "neutral"; sleep 1; cap p13_wide_on_spawn
pulse "ry=70" 1.0 0.6; cap p13_wide_on_pitchup
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw1
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw2
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw3
pulse "ry=45" 1.2 0.6; cap p13_wide_on_high
FOCUS=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "  focus=$FOCUS"

say "fps ON"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f)+0; if(NR==1){s0=sec; f0=f} sN=sec; fN=f }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p13_fps_on.txt"

say "2. restore ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill "$(cat /tmp/gr13r_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r13r] DONE"
