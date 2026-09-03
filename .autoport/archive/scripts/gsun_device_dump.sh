#!/usr/bin/env bash
# gsun_device_dump.sh — Gsun-halo DEVICE dump of the title-screen sun sprite SIZE
# (arm64 eae4df44). Installs the current APK (must be assembled fresh with the
# env/prop-gated SUNDUMP instrumentation in Sprite3::do_block_common), restores
# the known-good f1c CGOs + Ghalo TIT.DGO, boots to the title attract, and captures
# the per-sun-sprite SUNDUMP lines (disc=middot / corona=starflash2) so we can compare
# device corona/disc SIZE + alpha vs the our-x86 (== original-x86) baseline. No cpad:
# the title attract auto-plays the village flythrough with the sun up.
# Exits 2 if the device is PIN-locked.
#
# Env: TAG (before|after, default before), SAMPLE_S (attract sampling secs, default 120)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
TAG="${TAG:-before}"
SAMPLE_S="${SAMPLE_S:-120}"
OUT=".autoport/reports/Gsun-halo"
LOG="$OUT/device-sundump-$TAG.log"
SUM="$OUT/device-sundump-$TAG.summary.txt"
GREP='SUNDUMP |A35-RENDER frame=|link finish:|GK-DIAG |Fatal signal|signal [0-9]+ \(SIG|backtrace:'
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
echo "== gsun device dump TAG=$TAG (device unlocked) =="
device_require_attached
device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell setprop debug.opengoal.sun_dump 0 >/dev/null 2>&1; "$ADB" shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT

# Arm the SUNDUMP BEFORE the app reads it (static-init on first Mode3D sprite).
"$ADB" shell setprop debug.opengoal.sun_dump 1 >/dev/null 2>&1 || true
echo "  sun_dump property = $("$ADB" shell getprop debug.opengoal.sun_dump | tr -d '\r')"

# Install fresh APK + prove device runs it.
device_install_and_launch "$PKG" "$ACT" "$APK"

# Ensure the known-good f1c boot CGOs + Ghalo TIT.DGO are in place (pm install -r
# preserves app data, but restore makes the CGO set explicit + sha-verified).
echo "== restore_knowngood (f1c CGOs + Ghalo TIT.DGO) =="
bash .autoport/restore_knowngood_device.sh || echo "  restore returned nonzero (continuing)"

echo "== deploy_verify =="
if bash .autoport/lib/deploy_verify.sh eae4df44; then echo "DEPLOY_VERIFY=0"; else echo "DEPLOY_VERIFY=NONZERO (continuing, will flag)"; fi
"$ADB" shell setprop debug.opengoal.sun_dump 1 >/dev/null 2>&1 || true

# Fresh logcat capture (GK_STDERR carries fprintf(stderr) SUNDUMP lines).
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDERR:I GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== boot to title (waiting up to 150s for link finish: logo / first render) =="
for ((i=1;i<=50;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}; CS=$(crash_sigs); CS=${CS:-0}
  SD=$(grep -ac 'SUNDUMP ' "$LOG" 2>/dev/null || echo 0)
  if (( i % 4 == 0 )); then echo "   [${i}] frame=${FM} crashsig=${CS} sundump=${SD} focus=$(read_focus)"; fi
  [ "${CS:-0}" -gt 0 ] && { echo "   >>> crash sig=$CS during boot"; break; }
  [ "${SD:-0}" -ge 50 ] && { echo "   >>> SUNDUMP flowing (${SD}) — sun is up"; break; }
done

echo "== sample the title attract ${SAMPLE_S}s (sun up in the village flythrough) =="
for ((s=0;s<SAMPLE_S;s+=10)); do
  sleep 10
  CS=$(crash_sigs); [ "${CS:-0}" -gt 0 ] && { echo "   crash during sampling sig=$CS"; break; }
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  SD=$(grep -ac 'SUNDUMP ' "$LOG" 2>/dev/null || echo 0)
  echo "   [+${s}s] sundump=${SD} frame=$(max_frame) focus=$(read_focus)"
done

pkill -f "logcat -v threadtime GK_STDERR" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
"$ADB" shell setprop debug.opengoal.sun_dump 0 >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
device_stayon_restore 2>/dev/null || true

# ---- aggregate ----
SUNN=$(grep -ac 'SUNDUMP ' "$LOG" 2>/dev/null || echo 0)
DISC=$(grep -aE 'SUNDUMP .*middot' "$LOG" 2>/dev/null | wc -l | tr -d ' ')
CORO=$(grep -aE 'SUNDUMP .*starflash' "$LOG" 2>/dev/null | wc -l | tr -d ' ')
{
echo "# Gsun-halo DEVICE sundump [$TAG] $(date -Is)"
echo "reached_frame=$FINAL crash_sigs=$FCS focus_end=$ENDFOC sundump_total=$SUNN disc(middot)=$DISC corona(starflash2)=$CORO"
echo
echo "## DISC (middot) — distinct sx/sy/alpha (sort|uniq -c)"
grep -aE 'SUNDUMP .*middot' "$LOG" 2>/dev/null | grep -aoE 'sx=[0-9.]+ sy=[0-9.]+' | sort | uniq -c | sort -rn | head
echo "disc alpha range:"; grep -aE 'SUNDUMP .*middot' "$LOG" 2>/dev/null | grep -aoE 'a=[0-9.]+' | sort -t= -k2 -n | (head -1; tail -1)
echo
echo "## CORONA (starflash2) — distinct sx/sy (sort|uniq -c, top)"
grep -aE 'SUNDUMP .*starflash' "$LOG" 2>/dev/null | grep -aoE 'sx=[0-9.]+ sy=[0-9.]+' | sort | uniq -c | sort -rn | head
echo "corona alpha range:"; grep -aE 'SUNDUMP .*starflash' "$LOG" 2>/dev/null | grep -aoE 'a=[0-9.]+' | sort -t= -k2 -n | (head -1; tail -1)
echo "corona alpha distinct (top):"; grep -aE 'SUNDUMP .*starflash' "$LOG" 2>/dev/null | grep -aoE 'a=[0-9.]+' | sort | uniq -c | sort -rn | head
echo
echo "## first 6 SUNDUMP lines"
grep -aE 'SUNDUMP ' "$LOG" 2>/dev/null | sed -E 's/^.*SUNDUMP/SUNDUMP/' | head -6
echo "## last 6 SUNDUMP lines"
grep -aE 'SUNDUMP ' "$LOG" 2>/dev/null | sed -E 's/^.*SUNDUMP/SUNDUMP/' | tail -6
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -10
} | tee "$SUM"
echo
echo "[gsun] dump log: $LOG  summary: $SUM"
[ "$SUNN" -gt 0 ]
