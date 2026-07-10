#!/usr/bin/env bash
# grass_off_test.sh — clean OFF test: force-stop FIRST (so nothing rewrites the
# settings file), set recharged-grass? #f, boot, LOAD Geyser Rock, confirm grass
# builds ZERO instances (gating works / OFF==stock), capture stock frame + fps.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
F=.autoport/reports/Grecharged-grass-poc/frames; mkdir -p "$F"
LOG=/tmp/grass_off.log
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

echo "== force-stop FIRST, then edit settings (no live rewrite) =="
$ADB shell am force-stop $PKG >/dev/null 2>&1
sleep 1
$ADB shell run-as $PKG cat "$PCS" > /tmp/pcs_off.gc 2>/dev/null
sed -i 's/(recharged-grass? #[tf])/(recharged-grass? #f)/' /tmp/pcs_off.gc
$ADB push /tmp/pcs_off.gc /data/local/tmp/pcs_off.gc >/dev/null 2>&1
$ADB shell run-as $PKG cp /data/local/tmp/pcs_off.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs_off.gc >/dev/null 2>&1
echo "  file now: $($ADB shell run-as $PKG cat "$PCS" | grep recharged-grass | tr -d '\r')"

echo "== boot =="
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
$ADB logcat -c >/dev/null 2>&1
( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/grass_off_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 90 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
sleep 4
echo "== confirm the setting was READ as #f (pc-set-recharged-grass path) — load Geyser =="
pulse "start" 0.4 2.0
pulse "down" 0.35 0.8      # -> Load Game
pulse "x" 0.4 2.0
pulse "x" 0.4 2.0          # select top save
pulse "x" 0.4 2.0
echo "== wait for gameplay (master-mode=game), check grass lines (want 0) =="
t0=$(date +%s); got_game=0
while [ $(( $(date +%s)-t0 )) -lt 100 ]; do
  mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1)
  if [ "$mm" = "master-mode=game" ]; then got_game=1; break; fi
  sleep 3
done
sleep 3
gl=$(grep -acaE 'recharged-grass' "$LOG")
echo "  got_game=$got_game grass_instance_lines=$gl (0 == grass OFF / gating works)"
cap OFF_geyser_clean
echo "== fps OFF (gameplay) =="
stick "neutral"; sleep 5
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG" | tail -30 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f)+0;
         if(NR==1){s0=sec; f0=f} sN=sec; fN=f }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }'
echo "== focus =="; $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'
