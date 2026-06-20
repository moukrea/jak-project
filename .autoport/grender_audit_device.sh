#!/usr/bin/env bash
# Grender-audit DEVICE capture (arm64 eae4df44). Installs the CURRENT HEAD APK
# (which must already contain the freshly-built instrumented libgk.so), arms the
# GRA clock + per-bucket census via system properties, launches to the TITLE
# screen, holds at the title attract (Sandover vista + sun + village flythrough),
# and harvests the GRA-CLOCK / GRA-CENSUS / A35-RENDER / sustained-swap lines.
#
# Output: .autoport/reports/Grender-audit/device-clock-census.log
#         .autoport/reports/Grender-audit/device-foreground.txt
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=".autoport/reports/Grender-audit"
LOG="$OUT/device-clock-census.log"
FG="$OUT/device-foreground.txt"
HOLD_S="${HOLD_S:-75}"
mkdir -p "$OUT"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

echo "== Grender-audit DEVICE capture (title attract, hold ${HOLD_S}s) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell setprop debug.opengoal.gra.clock 0 2>/dev/null; adb shell setprop debug.opengoal.gra.census 0 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space
device_install_and_launch "$PKG" "$ACT" "$APK"
adb shell am force-stop "$PKG" 2>/dev/null || true

adb shell setprop debug.opengoal.gra.clock 1 2>/dev/null || true
adb shell setprop debug.opengoal.gra.census 1 2>/dev/null || true
echo "  armed gra.clock=$(adb shell getprop debug.opengoal.gra.clock | tr -d '\r') gra.census=$(adb shell getprop debug.opengoal.gra.census | tr -d '\r')"

adb logcat -G 64M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
( adb logcat -v threadtime opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'GRA-CLOCK|GRA-CENSUS|A35-RENDER frame=|sustained swap|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died' \
    > "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/gra-amstart.out 2>&1 || true

echo "== wait for title (poll up to 120s for A35-RENDER frame=) =="
for i in $(seq 1 120); do
  sleep 1
  grep -aq 'A35-RENDER frame=' "$LOG" 2>/dev/null && { echo "  rendering at ~${i}s"; break; }
done

echo "== hold at title attract ${HOLD_S}s =="
sleep "$HOLD_S"

sleep 1; ENDFOC=$(read_focus); ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{ echo "# Grender-audit device end-of-run ($(date -Is))"; echo "mCurrentFocus_at_end: $ENDFOC"; echo "app_pid_at_end: ${ENDPID:-gone}"; } > "$FG"

echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell setprop debug.opengoal.gra.clock 0 2>/dev/null || true
adb shell setprop debug.opengoal.gra.census 0 2>/dev/null || true
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== scoreboard =="
echo "  GRA-CLOCK lines : $(grep -ac 'GRA-CLOCK' "$LOG" 2>/dev/null || echo 0)"
echo "  GRA-CENSUS lines: $(grep -ac 'GRA-CENSUS' "$LOG" 2>/dev/null || echo 0)"
echo "  A35-RENDER lines: $(grep -ac 'A35-RENDER frame=' "$LOG" 2>/dev/null || echo 0)"
echo "  first GRA-CLOCK : $(grep -a 'GRA-CLOCK' "$LOG" | head -1)"
echo "  last  GRA-CLOCK : $(grep -a 'GRA-CLOCK' "$LOG" | tail -1)"
echo "  foreground end  : $ENDFOC pid=${ENDPID:-gone}"
echo "  crash sigs      : $(grep -acE 'Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null || echo 0)"
