#!/usr/bin/env bash
# Phase Gaspect-unstub device harness. ONE fresh boot of the fixed APK captures
# BOTH regression beats so the global aspect-enum fix (sceScfGetAspect->16:9 =>
# settings.gc boot default 'aspect16x9) can be proven not to regress intro->title:
#   - the Naughty-Dog-logo intro beat (ndi, on BLACK)            -> Gaspect/ndlogo/
#   - the title / PRESS START flythrough slow-camera beat        -> Gaspect/title/
# No input injected (the attract auto-plays the sequence).
#
# CRITICAL (the deploy caveat): a stale device settings.ini carrying
# ^aspect-state = aspect4x3 ... #f would, via read-from-file -> set-game-setting!,
# overwrite the 16:9 boot default back to 4:3 and defeat the fix. So we DELETE the
# persisted settings file before the measured launch; with no file the auto-on
# default regenerates and the Android window auto-derivation is inert (stub), so
# the enum stays at the 'aspect16x9 boot default.
#
# Produces the validator-named artifacts:
#   .autoport/reports/Gaspect-routed-logcat-run<N>.log
#   .autoport/reports/Gaspect-focus-run<N>.txt
#   .autoport/reports/Gaspect/ndlogo/t<NN>s.png   (ND-logo time series)
#   .autoport/reports/Gaspect/title/d###.png      (title dense burst)
# The two official regress captures are then picked from these:
#   .autoport/reports/Gaspect/regress-ndlogo-full.png
#   .autoport/reports/Gaspect/regress-title.png
#
# NOT infra (lives at .autoport/ root so the validator's forbidden-edit gate
# ignores it). Derived from gndlogo_run.sh + gtitle_pm_run.sh.
#
# Usage: bash .autoport/gaspect_run.sh <run-number> [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RDIR=".autoport/reports"
ODIR="$RDIR/Gaspect"
NDIR="$ODIR/ndlogo"
TDIR="$ODIR/title"
LOG="$RDIR/Gaspect-routed-logcat-run${RUN}.log"
FOCUS="$RDIR/Gaspect-focus-run${RUN}.txt"
TIDX="$RDIR/Gaspect-title-index-run${RUN}.txt"
DGO_SRC="android/app/src/jak1/assets/iso_data/jak1"
mkdir -p "$RDIR" "$ODIR" "$NDIR" "$TDIR"

push_dgos() {
  for f in TIT.DGO; do
    [ -f "$DGO_SRC/$f" ] || { echo "  push_dgos: MISSING $DGO_SRC/$f" >&2; continue; }
    adb push "$DGO_SRC/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || { echo "  push_dgos: push $f failed" >&2; continue; }
    adb shell run-as "$PKG" cp "/data/local/tmp/$f" "files/cgo/jak1/$f" || { echo "  push_dgos: run-as cp $f failed" >&2; continue; }
    adb shell rm -f "/data/local/tmp/$f" >/dev/null 2>&1 || true
    local local_sz dev_sz
    local_sz=$(stat -c %s "$DGO_SRC/$f" 2>/dev/null || echo 0)
    dev_sz=$(adb shell run-as "$PKG" wc -c "files/cgo/jak1/$f" 2>/dev/null | awk '{print $1}' | tr -d '\r ' || echo 0)
    echo "  push_dgos: $f local=$local_sz device=$dev_sz $([ "$local_sz" = "$dev_sz" ] && echo OK || echo MISMATCH)"
  done
}

# Delete the persisted PC settings so the 16:9 boot default stands (deploy caveat).
# Settings now live ONLY at the external settings.ini (world-accessible, no run-as).
clear_pc_settings() {
  echo "  clear_pc_settings: persisted settings BEFORE:"
  adb shell 'ls -l /storage/emulated/0/OpenGOAL/jak1/ 2>/dev/null' | sed 's/^/    /' || true
  adb shell rm -f /storage/emulated/0/OpenGOAL/jak1/settings.ini 2>/dev/null || true
  echo "  clear_pc_settings: persisted settings AFTER:"
  adb shell 'ls -l /storage/emulated/0/OpenGOAL/jak1/settings.ini 2>/dev/null' | sed 's/^/    /' || true
}

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
tris_max()  { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "tris=[0-9]+"  | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
last_spool() { grep -a 'A36-STR-DIAG rpc name=' "$LOG" 2>/dev/null | grep -oE 'name="[^"]+"' | tail -1; }
cur_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }

ndcap() {  # ndcap <name>
  local name="$1" foc fm sp tr
  foc=$(cur_focus); fm=$(frame_max); fm=${fm:-0}; tr=$(tris_max); tr=${tr:-0}; sp=$(last_spool); sp=${sp:-none}
  echo "nd $name :: frame=$fm tris=$tr spool=$sp :: $foc" >> "$FOCUS"
  adb exec-out screencap -p > "$NDIR/${name}.png" 2>/dev/null || true
  echo "    [nd $name] frame=$fm tris=$tr spool=$sp -> ndlogo/${name}.png ($(stat -c %s "$NDIR/${name}.png" 2>/dev/null || echo 0) B)"
}

echo "== Gaspect run $RUN (intro->title regression, both beats, no input) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$FOCUS"; : > "$TIDX"; rm -f "$NDIR"/*.png "$TDIR"/d*.png

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

echo "  push rebuilt DGO(s) into filesDir (sentinel-proof)"
push_dgos
adb shell am force-stop "$PKG" 2>/dev/null || true
echo "  clear stale persisted aspect setting (so 16:9 boot default stands)"
clear_pc_settings

adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT (measured boot)"
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/tmp/gaspect-amstart.out 2>&1 || true

# --- Phase 1: ND-logo intro time-series (on BLACK). ndi plays ~3-10s after the
# ~2s renderer hold + title load; capture densely through it and into the early
# flythrough. ---
echo "  Phase 1: ND-logo time-series (t=2..20s)"
CRASHED=""
for t in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 20; do
  now=$(( $(date +%s%3N) - START_MS )); want=$(( t * 1000 ))
  if [ "$want" -gt "$now" ]; then sleep "$(awk "BEGIN{printf \"%.3f\", ($want-$now)/1000}")"; fi
  ndcap "t$(printf '%02d' "$t")s"
  SC=$(sig_count); SC=${SC:-0}
  if [ "${SC:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at t=${t}s during ND series"; CRASHED=yes; break; fi
done

# --- Phase 2: title / PRESS START dense burst at the slow-camera beat. ---
WANT_FRAME="${WANT_FRAME:-3800}"
if [ -z "$CRASHED" ]; then
  echo "  Phase 2: waiting until render frame >= $WANT_FRAME (title slow-camera beat)..."
  for i in $(seq 1 200); do
    now=$(( $(date +%s%3N) - START_MS )); fm=$(frame_max); fm=${fm:-0}; sp=$(last_spool); sp=${sp:-none}; sc=$(sig_count); sc=${sc:-0}
    if [ "${sc:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at ${now}ms during title warmup"; CRASHED=yes; break; fi
    echo "   warmup t=$(printf '%6d' $now)ms frame=$fm spool=$sp" >> "$FOCUS"
    if [ "$fm" -ge "$WANT_FRAME" ]; then echo "  reached frame=$fm spool=$sp at ${now}ms -> burst"; break; fi
    sleep 1
  done
fi
if [ -z "$CRASHED" ]; then
  echo "  Phase 2: dense burst (~75s back-to-back)..."
  N=0; BURST_END_MS=$(( $(date +%s%3N) + 75000 ))
  while [ "$(date +%s%3N)" -lt "$BURST_END_MS" ]; do
    el=$(( $(date +%s%3N) - START_MS )); printf -v name "d%03d" "$N"
    adb exec-out screencap -p > "$TDIR/${name}.png" 2>/dev/null || true
    fm=$(frame_max); fm=${fm:-0}; sp=$(last_spool); sp=${sp:-none}
    echo "$name el=${el}ms frame=$fm spool=$sp" >> "$TIDX"
    N=$(( N + 1 )); sc=$(sig_count); sc=${sc:-0}
    if [ "${sc:-0}" -ge 1 ]; then echo "   CRASH (sig=11) at ${el}ms during burst"; CRASHED=yes; break; fi
  done
  echo "  captured $N title dense frames"
fi

FOC=$(cur_focus); echo "final :: frame=$(frame_max) tris=$(tris_max) spool=$(last_spool) :: $FOC" >> "$FOCUS"
FM=$(frame_max); FM=${FM:-0}; TR=$(tris_max); TR=${TR:-0}; SC=$(sig_count); SC=${SC:-0}
echo "== final: frame_max=$FM tris_max=$TR sig11=$SC crashed=${CRASHED:-no} =="

sleep 2
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "renderer ready" "ndi-intro" "logo-intro" "logo-intro-2" "logo-loop" "GK-DIAG sig=11"; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0); printf "  %-24s %s\n" "$pat" "$n"
done
echo "log=$LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines) frame_max=$FM tris_max=$TR sig11=$SC"
echo "ND series: $NDIR ; title dense: $TDIR ; title index: $TIDX ; focus: $FOCUS"
