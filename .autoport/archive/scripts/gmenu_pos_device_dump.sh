#!/usr/bin/env bash
# gmenu_pos_device_dump.sh — DEVICE per-element menu POSITION dump (arm64 eae4df44).
# Assumes the instrumented consistent arm64 set (GAME.CGO with the GMENU-DUMP block
# in progress.gc::adjust-sprites) is already built+deployed. Boots to the title
# attract, opens the progress 'title' menu via cpad_inject "start", and harvests the
# GMENU CAM/AUX/PART/ICON lines from logcat (GK_STDOUT). NO pixels. Exits 2 if PIN-locked.
#
# Env: TAG (before|after, default before), HOLD_S (menu-open sampling secs, default 40)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
TAG="${TAG:-before}"; HOLD_S="${HOLD_S:-40}"
OUT=".autoport/reports/Gmenu-placement"
LOG="$OUT/device-gmenu-$TAG.log"
SUM="$OUT/device-gmenu-$TAG.txt"
GREP='GMENU (CAM|AUX|PART|ICON) |A35-RENDER frame=|link finish: logo|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:'
mkdir -p "$OUT"

device_locked(){ "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
read_focus(){ "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
max_frame(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs(){ local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }
inject(){ printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
echo "== gmenu device dump TAG=$TAG =="
command -v device_require_attached >/dev/null 2>&1 && device_require_attached || "$ADB" get-state >/dev/null
command -v device_stayon_on >/dev/null 2>&1 && device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; clear_inject; "$ADB" shell am force-stop $PKG 2>/dev/null; command -v device_stayon_restore >/dev/null 2>&1 && device_stayon_restore 2>/dev/null' EXIT

echo "== deploy_verify (device runs fresh HEAD libgk) =="
bash .autoport/lib/deploy_verify.sh eae4df44 || echo "  (deploy_verify nonzero — continuing, will flag)"

"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
clear_inject
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== boot to title attract (up to 150s) =="
for ((i=1;i<=50;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}; CS=$(crash_sigs)
  (( i % 5 == 0 )) && echo "   [${i}] frame=${FM} crashsig=${CS} focus=$(read_focus)"
  [ "${CS:-0}" -gt 0 ] && { echo "   >>> crash sig=$CS during boot"; break; }
  [ "${FM:-0}" -ge 1500 ] && { echo "   >>> title attract rendering (frame ${FM})"; break; }
done

echo "== open progress 'title' menu via START =="
inject "start"; sleep 1.5; clear_inject
echo "== hold menu open ${HOLD_S}s, harvesting GMENU =="
for ((s=0;s<HOLD_S;s+=5)); do
  sleep 5
  CS=$(crash_sigs); [ "${CS:-0}" -gt 0 ] && { echo "   crash during menu sig=$CS"; break; }
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  GN=$(grep -acE '^[0-9].*GMENU PART ' "$LOG" 2>/dev/null || echo 0)
  echo "   [+${s}s] gmenu_part_lines=${GN} frame=$(max_frame) focus=$(read_focus)"
  # if no GMENU yet after 15s, re-press START (menu may not have opened)
  [ "$s" -ge 15 ] && [ "${GN:-0}" -eq 0 ] && { echo "   (no GMENU yet — re-press START)"; inject "start"; sleep 1.2; clear_inject; }
done

pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
command -v device_stayon_restore >/dev/null 2>&1 && device_stayon_restore 2>/dev/null || true

# ---- aggregate: strip logcat prefix to bare GMENU lines, dedup ----
{
echo "# Gmenu-placement DEVICE gmenu dump [$TAG] $(date -Is)"
echo "reached_frame=$FINAL crash_sigs=$FCS focus_end=$ENDFOC"
echo
echo "## CAM / AUX (distinct)"
grep -aoE 'GMENU (CAM|AUX) .*' "$LOG" 2>/dev/null | sort -u
echo
echo "## active PART (posx != -576) (distinct)"
grep -aoE 'GMENU PART .*' "$LOG" 2>/dev/null | grep -v 'posx=-576' | sort -u
echo
echo "## ICON (distinct)"
grep -aoE 'GMENU ICON .*' "$LOG" 2>/dev/null | sort -u
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -8
} | tee "$SUM"
GN=$(grep -acE 'GMENU PART ' "$LOG" 2>/dev/null || echo 0)
echo "[gmenu-dev] gmenu PART lines=$GN  log=$LOG  summary=$SUM"
[ "$GN" -gt 0 ]
