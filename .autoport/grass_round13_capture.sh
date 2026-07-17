#!/usr/bin/env bash
# grass_round13_capture.sh — ROUND#13 proof on device eae4df44.
# Two targeted fixes (renderer-only, no GOAL change -> NO 28-CGO rebuild):
#   (1) per-INSTANCE object-hide (no 0.5m cell nuke, no 3x3 dilation) -> occ_culled ~0 on the OPEN
#       platform = no block-shaped bald holes;
#   (2) TRANSITIVE overhang-lip exclusion reaching TIE platform tris -> no floating grass on distant
#       raised platforms.
# Harness: assemble APK (fresh libgk) + install -r + deploy_verify (HARD GATE), then an ON run that
# harvests the ROUND#13 STATIC place (occ_culled %) + OVERHANG-LIP transitive (TIE split) log lines and
# captures WIDE spawn stills (near platform + distant platforms), then an OFF A/B, then restore ON +
# force-stop (device hygiene).
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
die(){ echo "[r13 FAIL] $*" >&2; exit 1; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

set_grass(){ # $1 = t|f  (force-stop first so nothing rewrites the file)
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs13.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs13.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs13.gc
    $ADB push /tmp/pcs13.gc /data/local/tmp/pcs13.gc >/dev/null 2>&1
    $ADB shell cp /tmp/pcs13.gc "$PCS" 2>/dev/null || \
      $ADB shell cp /data/local/tmp/pcs13.gc "$PCS"
    $ADB shell rm -f /data/local/tmp/pcs13.gc >/dev/null 2>&1
  fi
  echo "  setting now: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"
}

load_geyser(){ # $1 = logfile
  local LOG="$1"
  $ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
  $ADB logcat -c >/dev/null 2>&1
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr13_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting for title..."
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
  sleep 4
  pulse "start" 0.4 2.0     # title -> main menu
  pulse "down" 0.35 0.8     # New Game -> Load Game
  pulse "x" 0.4 2.0         # enter Load
  pulse "x" 0.4 2.0         # select top save (ROCHER DU GEYSER)
  pulse "x" 0.4 2.0         # confirm
  echo "  waiting for training gameplay (master-mode=game)..."
  local got=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do
    mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1)
    [ "$mm" = "master-mode=game" ] && { got=1; break; }
    sleep 3
  done
  sleep 5; echo "  got_game=$got"
}

# ============================ BUILD + DEPLOY (HARD GATE) ============================
say "0. assemble APK (bundles the fresh ROUND#13 libgk) + install -r + deploy_verify"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "no built libgk.so — build first"
GH=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'recharged.?grass|grass.?blade|g_grass')
echo "  libgk grass strings: ${GH:-0}"; [ "${GH:-0}" -gt 0 ] || die "libgk has no grass strings"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify FAIL — device not running fresh libgk"
echo "  deploy_verify PASS"

# ============================ ON RUN ============================
say "1. ON RUN — load Geyser Rock (grass ON), harvest ROUND#13 log lines"
LOG_ON=/tmp/gr13_on.log
set_grass t
load_geyser "$LOG_ON"

say "ROUND#13 STATIC place (occ_culled %) + OVERHANG-LIP transitive (TIE split)"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -1 | tee "$OUT/p13_static_place.txt"
grep -aE 'recharged-grass\] ROUND#13 OVERHANG-LIP' "$LOG_ON" | tail -1 | tee "$OUT/p13_overhang_lip.txt"
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge CLAMP' "$LOG_ON" | tail -1 | tee -a "$OUT/p13_overhang_lip.txt"

say "WIDE spawn stills (near platform + distant platforms) — several camera angles"
stick "neutral"; sleep 1; cap p13_wide_on_spawn
# pitch camera up a touch to reveal the surrounding distant raised platforms
pulse "ry=70" 1.0 0.6; cap p13_wide_on_pitchup
# yaw sweep to bring distant platforms into frame
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw1
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw2
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw3
pulse "rx=210" 1.0 0.6; cap p13_wide_on_yaw4
# a slightly higher pitch for a broad overview
pulse "ry=55" 1.2 0.6; cap p13_wide_on_high
FOCUS_ON=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus_on=$FOCUS_ON"

say "fps ON (gameplay)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f)+0;
         if(NR==1){s0=sec; f0=f} sN=sec; fN=f }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p13_fps_on.txt"

# ============================ OFF RUN (A/B, OFF==stock) ============================
say "2. OFF RUN — grass #f, load Geyser, confirm 0 grass lines, matching wide still"
LOG_OFF=/tmp/gr13_off.log
set_grass f
load_geyser "$LOG_OFF"
gl=$(grep -acaE 'recharged-grass\] training STATIC place' "$LOG_OFF")
echo "  grass_static_place_lines_OFF=$gl (0 == grass OFF / gating works / OFF==stock)"
stick "neutral"; sleep 1; cap p13_wide_off_spawn
pulse "ry=70" 1.0 0.6; cap p13_wide_off_pitchup
pulse "rx=210" 1.0 0.6; cap p13_wide_off_yaw1
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_OFF" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f)+0;
         if(NR==1){s0=sec; f0=f} sN=sec; fN=f }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p13_fps_off.txt"
FOCUS_OFF=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus_off=$FOCUS_OFF"

# ============================ RESTORE + HYGIENE ============================
say "3. restore default ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill "$(cat /tmp/gr13_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r13] DONE — captures in $F, log lines in $OUT/p13_*.txt"
