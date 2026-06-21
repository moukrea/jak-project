#!/usr/bin/env bash
# gparts_device_dump.sh — Gparticles-stars DEVICE dump of ACTUAL particle + night-star
# counts (arm64 eae4df44). The APK must be freshly assembled with the prop-gated
# gparts instrumentation (Sprite3::gparts_dump_frame + sp_process_block_3d noop3d
# toggle). Restores the known-good f1c CGOs + TIT.DGO, boots to the title attract
# (which sets time-ratio 18000 -> the day/night cycle runs fast: sun corona by day,
# stars by night), and captures the per-frame PARTS lines so we can compare device
# alive3d / star-count / submit3d vs the our-x86 (== original-x86) baseline.
#   TAG=after  -> real builder (AFTER): particles + stars should render.
#   TAG=before -> sets debug.opengoal.gparts.noop3d=1 (BEFORE): 3D builder noop'd,
#                 device 3D particles/stars/sun must drop to ~0 (reproduces the defect).
# Exits 2 if the device is PIN-locked.
#
# Env: TAG (after|before, default after), SAMPLE_S (attract sampling secs, default 150)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
TAG="${TAG:-after}"
SAMPLE_S="${SAMPLE_S:-150}"
OUT=".autoport/reports/Gparticles-stars"
LOG="$OUT/device-parts-$TAG.log"
SUM="$OUT/device-parts-$TAG.summary.txt"
GREP='PARTS |A35-RENDER frame=|link finish:|GK-DIAG |Fatal signal|signal [0-9]+ \(SIG|backtrace:'
mkdir -p "$OUT"

device_locked() { "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs() { local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
echo "== gparts device dump TAG=$TAG (device unlocked) =="
device_require_attached
device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell setprop debug.opengoal.gparts.dump 0 >/dev/null 2>&1; "$ADB" shell setprop debug.opengoal.gparts.noop3d 0 >/dev/null 2>&1; "$ADB" shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT

# Arm the dump BEFORE the app reads it.
"$ADB" shell setprop debug.opengoal.gparts.dump 1 >/dev/null 2>&1 || true
if [ "$TAG" = "before" ]; then
  "$ADB" shell setprop debug.opengoal.gparts.noop3d 1 >/dev/null 2>&1 || true
else
  "$ADB" shell setprop debug.opengoal.gparts.noop3d 0 >/dev/null 2>&1 || true
fi
echo "  gparts.dump=$("$ADB" shell getprop debug.opengoal.gparts.dump | tr -d '\r')  noop3d=$("$ADB" shell getprop debug.opengoal.gparts.noop3d | tr -d '\r')"

# Install fresh APK + prove device runs it.
device_install_and_launch "$PKG" "$ACT" "$APK"

echo "== restore_knowngood (f1c CGOs + TIT.DGO) =="
bash .autoport/restore_knowngood_device.sh || echo "  restore returned nonzero (continuing)"

echo "== deploy_verify =="
if bash .autoport/lib/deploy_verify.sh eae4df44; then echo "DEPLOY_VERIFY=0"; else echo "DEPLOY_VERIFY=NONZERO (continuing, will flag)"; fi
# Re-arm props (install/restore may have force-stopped).
"$ADB" shell setprop debug.opengoal.gparts.dump 1 >/dev/null 2>&1 || true
[ "$TAG" = "before" ] && "$ADB" shell setprop debug.opengoal.gparts.noop3d 1 >/dev/null 2>&1 || "$ADB" shell setprop debug.opengoal.gparts.noop3d 0 >/dev/null 2>&1 || true

# Fresh logcat capture (GK_STDERR carries fprintf(stderr) PARTS lines).
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDERR:I GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== boot to title (waiting up to 150s for first PARTS / render) =="
for ((i=1;i<=50;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}; CS=$(crash_sigs); CS=${CS:-0}
  PD=$(grep -ac 'PARTS ' "$LOG" 2>/dev/null || echo 0)
  if (( i % 4 == 0 )); then echo "   [${i}] frame=${FM} crashsig=${CS} parts=${PD} focus=$(read_focus)"; fi
  [ "${CS:-0}" -gt 0 ] && { echo "   >>> crash sig=$CS during boot"; break; }
  [ "${PD:-0}" -ge 60 ] && { echo "   >>> PARTS flowing (${PD})"; break; }
done

echo "== sample the title attract ${SAMPLE_S}s (day/night cycle: sun by day, stars by night) =="
for ((s=0;s<SAMPLE_S;s+=10)); do
  sleep 10
  CS=$(crash_sigs); [ "${CS:-0}" -gt 0 ] && { echo "   crash during sampling sig=$CS"; break; }
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  PD=$(grep -ac 'PARTS ' "$LOG" 2>/dev/null || echo 0)
  echo "   [+${s}s] parts=${PD} frame=$(max_frame) focus=$(read_focus)"
done

pkill -f "logcat -v threadtime GK_STDERR" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
"$ADB" shell setprop debug.opengoal.gparts.dump 0 >/dev/null 2>&1 || true
"$ADB" shell setprop debug.opengoal.gparts.noop3d 0 >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
device_stayon_restore 2>/dev/null || true

# ---- aggregate ----
PN=$(grep -ac 'PARTS ' "$LOG" 2>/dev/null || echo 0)
{
echo "# Gparticles-stars DEVICE parts dump [$TAG] $(date -Is)"
echo "reached_frame=$FINAL crash_sigs=$FCS focus_end=$ENDFOC parts_total=$PN"
echo
echo "## NIGHT (hr>=19 or hr<=5): star-count + alive3d + sub3d distribution"
grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=19||h<=5) print "starc="v["starc"]" a3d="v["a3d"]" sub3d="v["sub3d"]}' | sort | uniq -c | sort -rn | head
echo "  night star-count MAX:"; grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=19||h<=5) print v["starc"]+0}' | sort -n | tail -1
echo "  night alive3d MAX:"; grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=19||h<=5) print v["a3d"]+0}' | sort -n | tail -1
echo "  night sub3d MAX:"; grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=19||h<=5) print v["sub3d"]+0}' | sort -n | tail -1
echo
echo "## DAY (6<=hr<=18): sun-count + alive3d + sub3d distribution"
grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=6&&h<=18) print "sunc="v["sunc"]" a3d="v["a3d"]" sub3d="v["sub3d"]" sub2d="v["sub2d"]}' | sort | uniq -c | sort -rn | head
echo "  day sub3d MAX:"; grep -aoE 'PARTS .*' "$LOG" 2>/dev/null | awk '{for(i=1;i<=NF;i++){split($i,a,"=");v[a[1]]=a[2]} h=v["hr"]+0; if(h>=6&&h<=18) print v["sub3d"]+0}' | sort -n | tail -1
echo
echo "## hour coverage (did the cycle reach night?)"
grep -aoE 'hr=[0-9-]+' "$LOG" 2>/dev/null | sort -t= -k2 -n | uniq -c | head -30
echo
echo "## first 6 / last 6 PARTS lines"
grep -aE 'PARTS ' "$LOG" 2>/dev/null | sed -E 's/^.*PARTS/PARTS/' | head -6
echo "..."
grep -aE 'PARTS ' "$LOG" 2>/dev/null | sed -E 's/^.*PARTS/PARTS/' | tail -6
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -10
} | tee "$SUM"
echo
echo "[gparts] dump log: $LOG  summary: $SUM"
[ "$PN" -gt 0 ]
