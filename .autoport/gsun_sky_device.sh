#!/usr/bin/env bash
# gsun_sky_device.sh — Gsun-halo DEVICE measurement of the composited SKY texture
# brightness (the sky-baked sun) on arm64 eae4df44. The arm64 SkyBlendCPU blend
# kernels were stubbed (#ifndef __arm64__) -> the sky/cloud texture was never
# composited -> no sky sun -> the additive corona reads as a ~20% glow. This script
# captures the SKYBLEND texsum/bright dump (game/graphics/.../SkyBlendCPU.cpp) at the
# title attract, with the fix EITHER reproduced-OFF (TAG=before, debug.opengoal.sky_noblend=1)
# OR ON (TAG=after, sky_noblend=0), so we get an apples-to-apples device BEFORE/AFTER from
# one binary. Exits 2 if the device is PIN-locked.
#
# Env: TAG (before|after, default before), SAMPLE_S (default 90)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
TAG="${TAG:-before}"
SAMPLE_S="${SAMPLE_S:-90}"
NOBLEND=0; [ "$TAG" = "before" ] && NOBLEND=1
OUT=".autoport/reports/Gsun-halo"
LOG="$OUT/device-sky-$TAG.log"
SUM="$OUT/device-sky-$TAG.summary.txt"
GREP='SKYBLEND |A35-RENDER frame=|link finish:|GK-DIAG |Fatal signal|signal [0-9]+ \(SIG|backtrace:'
mkdir -p "$OUT"

device_locked() { "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs() { local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}" | head -1; }

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
echo "== gsun SKY device dump TAG=$TAG (sky_noblend=$NOBLEND) =="
device_require_attached
device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell setprop debug.opengoal.sky_dump 0 >/dev/null 2>&1; "$ADB" shell setprop debug.opengoal.sky_noblend 0 >/dev/null 2>&1; "$ADB" shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT

# Arm the dump + the noblend toggle BEFORE the app static-init reads them.
"$ADB" shell setprop debug.opengoal.sky_dump 1 >/dev/null 2>&1 || true
"$ADB" shell setprop debug.opengoal.sky_noblend $NOBLEND >/dev/null 2>&1 || true
echo "  sky_dump=$("$ADB" shell getprop debug.opengoal.sky_dump | tr -d '\r') sky_noblend=$("$ADB" shell getprop debug.opengoal.sky_noblend | tr -d '\r')"

# Install fresh APK (only needed once; harmless to repeat) + restore known-good CGOs.
device_install_and_launch "$PKG" "$ACT" "$APK"
echo "== restore_knowngood (f1c CGOs + Ghalo TIT.DGO) =="
bash .autoport/restore_knowngood_device.sh || echo "  restore returned nonzero (continuing)"
echo "== deploy_verify =="
if bash .autoport/lib/deploy_verify.sh eae4df44; then echo "DEPLOY_VERIFY=0"; else echo "DEPLOY_VERIFY=NONZERO (continuing, will flag)"; fi

# Re-arm props (force-stop in install may have happened) then fresh logcat.
"$ADB" shell setprop debug.opengoal.sky_dump 1 >/dev/null 2>&1 || true
"$ADB" shell setprop debug.opengoal.sky_noblend $NOBLEND >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDERR:I GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== boot to title + sample ${SAMPLE_S}s (sky composited during the village flythrough) =="
for ((i=1;i<=60;i++)); do
  sleep 3
  CS=$(crash_sigs); SB=$(grep -ac 'SKYBLEND ' "$LOG" 2>/dev/null | head -1); SB=${SB:-0}
  if (( i % 4 == 0 )); then echo "   [${i}] frame=$(max_frame) crashsig=${CS} skyblend=${SB} focus=$(read_focus)"; fi
  [ "${CS:-0}" -gt 0 ] && { echo "   >>> crash sig=$CS"; break; }
  "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  [ "$i" -ge $((SAMPLE_S/3)) ] && [ "${SB:-0}" -ge 20 ] && { echo "   >>> enough SKYBLEND samples (${SB})"; break; }
done

pkill -f "logcat -v threadtime GK_STDERR" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FCS=$(crash_sigs)
"$ADB" shell setprop debug.opengoal.sky_dump 0 >/dev/null 2>&1 || true
"$ADB" shell setprop debug.opengoal.sky_noblend 0 >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
device_stayon_restore 2>/dev/null || true

SBN=$(grep -ac 'SKYBLEND ' "$LOG" 2>/dev/null | head -1)
{
echo "# Gsun-halo DEVICE sky-blend dump [$TAG sky_noblend=$NOBLEND] $(date -Is)"
echo "reached_frame=${FINAL:-0} crash_sigs=$FCS focus_end=$ENDFOC skyblend_lines=${SBN:-0}"
echo
echo "## SKYBLEND per-buffer texsum (buf 0=sky 32x32, buf 1=clouds 64x64) — distinct, top"
echo "### buf=0 (sky) texsum distinct:"; grep -aE 'SKYBLEND buf=0' "$LOG" 2>/dev/null | grep -aoE 'texsum=[0-9]+ bright=[0-9]+' | sort | uniq -c | sort -rn | head
echo "### buf=1 (clouds) texsum distinct:"; grep -aE 'SKYBLEND buf=1' "$LOG" 2>/dev/null | grep -aoE 'texsum=[0-9]+ bright=[0-9]+' | sort | uniq -c | sort -rn | head
echo "max texsum any buffer: $(grep -aE 'SKYBLEND ' "$LOG" 2>/dev/null | grep -aoE 'texsum=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)"
echo
echo "## first 6 SKYBLEND lines"; grep -aE 'SKYBLEND ' "$LOG" 2>/dev/null | sed -E 's/^.*SKYBLEND/SKYBLEND/' | head -6
echo "## last 6 SKYBLEND lines"; grep -aE 'SKYBLEND ' "$LOG" 2>/dev/null | sed -E 's/^.*SKYBLEND/SKYBLEND/' | tail -6
echo
echo "## crash signatures"; grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -8
} | tee "$SUM"
echo
echo "[gsun-sky] log: $LOG  summary: $SUM"
[ "${SBN:-0}" -gt 0 ]
