#!/usr/bin/env bash
# gd3_device_census.sh — Gd3-jak-cinematic DEVICE census (arm64 eae4df44).
# Installs the current APK (must be assembled fresh), reaches the NEW-GAME intro
# cinematic via cpad_inject (same sequence as gcine_cut_reach.sh), and captures
# the merc-triangle census (GD3-CENSUS, gated by property debug.opengoal.gd3.census)
# plus the GOAL spool/art-error strings, so we can see whether Jak (model eichar)
# draws >0 tris in the cinematic. Exits 2 if the device is PIN-locked.
#
# Env: TAG (before|after, default before), TARGET (reach frame, default 9000),
#      SAMPLE_S (cinematic sampling seconds after reach, default 110), MAX_MIN (15)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
TAG="${TAG:-before}"
TARGET="${TARGET:-9000}"
SAMPLE_S="${SAMPLE_S:-110}"
MAX_MIN="${MAX_MIN:-15}"
OUT=".autoport/reports/Gd3-jak"
LOG="$OUT/device-census-$TAG.log"
SUM="$OUT/device-census-$TAG.summary.txt"
GREP='GD3-CENSUS|GD3-BONES|could not find a master slot|art error for|dummy-19 bad|process-drawable-art-error|A35-RENDER frame=|link finish:|GK-DIAG |A36-SYMBOLIZE|DBLEE-REPAIR|Fatal signal|signal [0-9]+ \(SIG|backtrace:|#[0-9][0-9] pc '
mkdir -p "$OUT"

device_locked() { "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
inject() { printf '%s' "$1" | "$ADB" shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }
read_focus() { "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
crash_sigs() { local n; n=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null); echo "${n:-0}"; }

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do "$ADB" shell am force-stop "$p" >/dev/null 2>&1 || true; "$ADB" shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
echo "== gd3 device census TAG=$TAG (device unlocked) =="
device_require_attached
device_stayon_on || true
disable_interlopers
trap 'reenable_interlopers; pkill -f "logcat -v threadtime" 2>/dev/null; "$ADB" shell setprop debug.opengoal.gd3.census 0 >/dev/null 2>&1; "$ADB" shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT

# Arm the census BEFORE the app reads it (static-init on first merc render).
"$ADB" shell setprop debug.opengoal.gd3.census 1 >/dev/null 2>&1 || true
echo "  census property = $("$ADB" shell getprop debug.opengoal.gd3.census | tr -d '\r')"

# Install fresh APK + prove device runs it.
device_install_and_launch "$PKG" "$ACT" "$APK"
echo "== deploy_verify =="
if bash .autoport/lib/deploy_verify.sh eae4df44; then echo "DEPLOY_VERIFY=0"; else echo "DEPLOY_VERIFY=NONZERO (continuing, will flag)"; fi
"$ADB" shell setprop debug.opengoal.gd3.census 1 >/dev/null 2>&1 || true

# Fresh logcat capture.
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
clear_inject
"$ADB" logcat -G 64M >/dev/null 2>&1 || true
"$ADB" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" logcat -v threadtime GK_STDOUT:I opengoal-gk:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE "$GREP" >> "$LOG" ) &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
"$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== warmup (title settle) =="; sleep 40
echo "== START -> NEW GAME -> CONTINUE WITHOUT SAVING =="
inject "start"; sleep 1.2; clear_inject; sleep 4
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

echo "== watch for cinematic reach (frame>=$TARGET, max ${MAX_MIN}min) =="
ITERS=$(( MAX_MIN * 60 / 3 )); LAST=0; NOPROG=0; REACHED=""; CRASHED=""
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  FM=$(max_frame); FM=${FM:-0}; CS=$(crash_sigs); CS=${CS:-0}
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] frame=${FM} crashsig=${CS} eichar_census=$(grep -ac 'GD3-CENSUS.*eichar' "$LOG" 2>/dev/null||echo 0)"; fi
  [ "${CS:-0}" -gt 0 ] && { echo "   >>> crash sig=$CS"; CRASHED="sig"; break; }
  [ "${FM:-0}" -ge "$TARGET" ] && { echo "   >>> reached frame=$FM — sampling cinematic ${SAMPLE_S}s"; REACHED="y"; break; }
  if [ "${FM:-0}" -le "$LAST" ]; then NOPROG=$((NOPROG+1)); else NOPROG=0; fi
  LAST=$FM
  [ "$NOPROG" -ge 30 ] && { echo "   >>> no progress 90s — abort"; CRASHED="stuck"; break; }
done

# Sample the cinematic window for census (Jak/eichar should be drawing here).
if [ "$REACHED" = "y" ]; then
  for ((s=0;s<SAMPLE_S;s+=5)); do
    sleep 5
    CS=$(crash_sigs); [ "${CS:-0}" -gt 0 ] && { echo "   crash during sampling sig=$CS"; break; }
  done
fi

# Freeze the capture before any deep post-cinematic gameplay crash pollutes it.
pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
kill ${LOGCAT_PID:-0} 2>/dev/null || true
ENDFOC=$(read_focus); FINAL=$(max_frame); FINAL=${FINAL:-0}; FCS=$(crash_sigs)
"$ADB" shell setprop debug.opengoal.gd3.census 0 >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT
reenable_interlopers
device_stayon_restore 2>/dev/null || true

# ---- aggregate ----
{
echo "# Gd3-jak DEVICE census [$TAG] $(date -Is)"
echo "reached_frame=$FINAL target=$TARGET crash_sigs=$FCS focus_end=$ENDFOC verdict=${REACHED:+reached}${CRASHED:+$CRASHED}"
echo
echo "## merc bucket census (GD3-CENSUS) — distinct lines, top by count"
grep -aE 'GD3-CENSUS' "$LOG" 2>/dev/null | sed -E 's/.*(GD3-CENSUS)/\1/' | sort | uniq -c | sort -rn | head -20
echo
echo "## JAK (eichar) merc draws in cinematic"
echo "eichar census lines: $(grep -ac 'GD3-CENSUS.*eichar' "$LOG" 2>/dev/null || echo 0)"
echo "max eichar tris seen:"
grep -aoE 'eichar-lod0:[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1
echo "## sidekick (Daxter) merc draws"
echo "sidekick census lines: $(grep -acE 'GD3-CENSUS.*sidekick' "$LOG" 2>/dev/null || echo 0)"
echo
echo "## common-pris-merc + l0-pris-merc samples (where Jak/Daxter draw)"
grep -aE 'GD3-CENSUS bucket=(common-pris-merc|l0-pris-merc)' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -15
echo
echo "## SPOOL / ART-ERROR signals (the suspected arm64 root)"
grep -aiE 'could not find a master slot|art error for|dummy-19 bad|process-drawable-art-error' "$LOG" 2>/dev/null | sed -E 's/^[0-9:. -]+//' | sort | uniq -c | sort -rn | head -30
echo
echo "## crash signatures"
grep -aiE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|backtrace:' "$LOG" 2>/dev/null | tail -10
} | tee "$SUM"
echo
echo "[gd3] census log: $LOG  summary: $SUM"
