#!/usr/bin/env bash
# gmenu_textures_device_capture.sh — wait for the Redmi (eae4df44) to be UNLOCKED,
# then capture the title 'progress' menu: harvest the GTEX (MENU/OFF/ICON/PART/DSTR)
# read-only dumps from logcat AND take a few screencaps so the bunched layer is
# visible. Assumes the instrumented consistent arm64 HEAD set is already deployed.
# Token-free wait: polls deviceLocked every 30s up to WAIT_MAX iterations.
# Env: WAIT_MAX (default 360 = ~3h), HOLD_S (menu sampling secs, default 45)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
HOLD_S="${HOLD_S:-45}"; WAIT_MAX="${WAIT_MAX:-360}"
OUT=".autoport/reports/Gmenu-textures"
LOG="$OUT/device-capture.log"
SUM="$OUT/device-gtex.txt"
GREP='GMENU-AS|GMENU-ALLOC |GMENU-DBG |GK-SPR3 mode=|GTEX (MENU|OFF|ICON|PART|DSTR|SMTX) |A35-RENDER frame=|link finish: logo|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:'
mkdir -p "$OUT"
device_locked(){ "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
read_focus(){ "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
max_frame(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs(){ local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }
inject(){ printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject(){ inject ""; }
shot(){ "$ADB" shell screencap -p /sdcard/gtex-$1.png >/dev/null 2>&1 || true; "$ADB" pull /sdcard/gtex-$1.png "$OUT/device-menu-$1.png" >/dev/null 2>&1 || true; }
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

echo "== waiting for device unlock (poll 30s, up to $WAIT_MAX) =="
i=0
while :; do
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  if ! device_locked; then echo "   UNLOCKED at iter $i ($(date -Is))"; break; fi
  i=$((i+1)); [ "$i" -ge "$WAIT_MAX" ] && { echo "   STILL LOCKED after $WAIT_MAX iters — giving up"; exit 2; }
  sleep 30
done

echo "== device unlocked — capturing title menu =="
command -v device_stayon_on >/dev/null 2>&1 && device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; clear_inject; "$ADB" shell am force-stop $PKG 2>/dev/null; command -v device_stayon_restore >/dev/null 2>&1 && device_stayon_restore 2>/dev/null; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true' EXIT
bash .autoport/lib/deploy_verify.sh eae4df44 || echo "  (deploy_verify nonzero — flag)"
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
clear_inject
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== boot to title (up to 150s) =="
for ((i=1;i<=50;i++)); do
  sleep 3; FM=$(max_frame); FM=${FM:-0}; CS=$(crash_sigs)
  (( i % 5 == 0 )) && echo "   [${i}] frame=${FM} crashsig=${CS} focus=$(read_focus)"
  [ "${CS:-0}" -gt 0 ] && { echo "   crash sig=$CS during boot"; break; }
  [ "${FM:-0}" -ge 1500 ] && { echo "   title attract (frame ${FM})"; break; }
done
echo "== open menu via START, navigate to generate frames, screencap =="
inject "start"; sleep 2; clear_inject; sleep 1; shot 01
for ((s=0;s<HOLD_S;s+=5)); do
  sleep 5
  CS=$(crash_sigs); [ "${CS:-0}" -gt 0 ] && { echo "   crash during menu sig=$CS"; break; }
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  GN=$(grep -acE 'GK-SPR3 mode=2' "$LOG" 2>/dev/null); GN=${GN:-0}; GN=${GN//[!0-9]/}
  echo "   [+${s}s] spr3_hud_lines=${GN} frame=$(max_frame) focus=$(read_focus)"
  # nudge the menu (down/up) so it redraws; re-press start if nothing yet
  inject "down"; sleep 0.4; inject "up"; sleep 0.4; clear_inject
  [ "$s" -eq 10 ] && shot 02
  [ "$s" -eq 25 ] && shot 03
  [ "$s" -ge 15 ] && [ "${GN:-0}" -eq 0 ] && { echo "   (no menu sprites — re-press START)"; inject "start"; sleep 1.2; clear_inject; }
done
shot 04
pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
{
echo "# Gmenu-textures DEVICE GTEX dump $(date -Is)"
echo "reached_frame=$FINAL crash_sigs=$FCS focus_end=$ENDFOC"
echo; echo "## GMENU-AS adjust-sprites matrix-index + control-state probe (distinct)"
grep -aoE 'GMENU-AS2? .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GMENU-ALLOC sprite-allocate-user-hvdf return probe (distinct)"
grep -aoE 'GMENU-ALLOC .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GMENU-DBG launch matrix-index decision probe (distinct)"
grep -aoE 'GMENU-DBG .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GK-SPR3 menu HUD/2D sprite vertex dump (distinct, mode=2 HUD / mode=0 2D)"
grep -aoE 'GK-SPR3 mode=.*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GTEX MENU / OFF / ICON / SMTX (distinct)"
grep -aoE 'GTEX (MENU|OFF|ICON|SMTX) .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GTEX PART (distinct, active)"
grep -aoE 'GTEX PART .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## GTEX DSTR (distinct text strings)"
grep -aoE 'GTEX DSTR .*' "$LOG" 2>/dev/null | sort -u
echo; echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -8
} | tee "$SUM"
GN=$(grep -acE 'GK-SPR3 mode=2' "$LOG" 2>/dev/null); GN=${GN:-0}; GN=${GN//[!0-9]/}
echo "[gmenu-tex-dev] spr3_hud lines=$GN  log=$LOG  summary=$SUM  shots=$OUT/device-menu-0*.png"
[ "${GN:-0}" -gt 0 ]
