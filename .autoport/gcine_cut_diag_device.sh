#!/usr/bin/env bash
# gcine_cut_diag_device.sh — DIAGNOSTIC device capture for the cutscene CUT bug.
# Pushes the freshly-built INSTRUMENTED arm64 CGO/DGO set (out/jak1-arm64-full/iso,
# built by build_arm64_full_consistent.sh with the GCINE-CUT-DIAG dumps in
# loader.gc / process-taskable.gc / load-boundary.gc), then drives the NEW-GAME
# intro cinematic via cpad_inject and harvests a LEAN EE-thread log:
#   GCINE-SP  ct=.. strpos=.. af=.. part=..        (spool anim-frame timeline)
#   GCINE-OC  ct=.. cji=.. s1=.. wx/wy/wz=..        (othercam joint idx + world pos)
#   GCINE-JC  ct=.. joint=.. movie?=..              (each joint-switch command FIRED)
# NO GCINE-CAM camera flood (that crashed the prior capture at frame ~6990).
# Device eae4df44 ONLY. libgk stays the installed HEAD APK (GOAL-only change).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CGO_SRC=out/jak1-arm64-full/iso
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Gcine-cut
LOG="$OUT/device-diag.log"
FG="$OUT/device-diag-foreground.txt"
WATCH_MIN="${WATCH_MIN:-14}"
mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[diag FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
cur_af(){ grep -a 'GCINE-SP ' "$LOG" 2>/dev/null | tail -1 | grep -aoE 'af=[0-9.]+' | grep -oE '[0-9.]+' | head -1; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
[ -f "$APK" ] || die "APK missing: $APK"
[ -d "$CGO_SRC" ] || die "instrumented CGO set missing: $CGO_SRC (run build_arm64_full_consistent.sh)"
ncgo=$(ls "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO 2>/dev/null | wc -l)
[ "$ncgo" -eq 28 ] || die "expected 28 CGO/DGO in $CGO_SRC, got $ncgo"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done
trap 'for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; kill ${LOGCAT_PID:-0} 2>/dev/null||true; adb shell am force-stop $PKG 2>/dev/null||true' EXIT

echo "== 1. install HEAD APK (libgk unchanged) =="
adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
adb shell pm trim-caches 999G 2>/dev/null || true
adb install -r -d -t -i com.android.vending "$APK" || die "apk install failed"

echo "== 2. push 28 INSTRUMENTED CGO/DGO -> files/iso_data/jak1 (sha-verify) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0
for f in "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO; do
  n=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  adb push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || { echo "  PUSH-FAIL $n"; fail=1; continue; }
  adb shell run-as $PKG cp "/data/local/tmp/$n" "files/iso_data/jak1/$n" || { echo "  CP-FAIL $n"; fail=1; }
  adb shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "files/iso_data/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $n"; fail=1; }
done
[ "$fail" -eq 0 ] || die "instrumented CGO push failed"
echo "  pushed + verified all 28 instrumented files"

echo "== 3. logcat (LEAN: GCINE- markers + crash sigs only) =="
adb shell setprop debug.opengoal.gcine.cam 0 2>/dev/null || true
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -G 64M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
( adb logcat -v threadtime opengoal-gk:I libc:F DEBUG:V '*:S' \
   | grep --line-buffered -aE 'GCINE-SP |GCINE-OC |GCINE-JC |GCINE-GUARD |GCINE-ABORT|loader stall|Fatal signal|signal [0-9]+ \(SIG|backtrace:|has died' \
   > "$LOG" ) &
LOGCAT_PID=$!

echo "== 4. launch + drive NEW GAME =="
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  warmup 40s"; sleep 40
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

echo "== 5. watch (poll 3s; finish when sequenceB camera joints cji 43/44 appear) =="
CRASHED=""; GONE=0; ITERS=$(( WATCH_MIN * 60 / 3 ))
for ((i=1;i<=ITERS;i++)); do
  sleep 3
  PART=$(grep -a 'GCINE-SP ' "$LOG" 2>/dev/null | tail -1 | grep -aoE 'part=[0-9]+' | grep -oE '[0-9]+')
  SEQB=$(grep -acE 'GCINE-OC ct=[0-9]+ cji=(43|44) ' "$LOG" 2>/dev/null)
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  FG_OK=0; is_fg && FG_OK=1
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] part=${PART:-?} seqB_cji=${SEQB} fg=${FG_OK} pid='${PID:-gone}' SP=$(grep -ac 'GCINE-SP ' "$LOG") JC=$(grep -ac 'GCINE-JC ' "$LOG") GUARD=$(grep -ac 'GCINE-GUARD ' "$LOG")"; fi
  if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "   >>> CRASH SIG"; CRASHED="sig"; break; fi
  if [ -z "$PID" ] && [ "$FG_OK" = "0" ]; then GONE=$((GONE+1)); else GONE=0; fi
  if [ "$GONE" -ge 4 ]; then echo "   >>> app GONE x4"; CRASHED="procgone"; break; fi
  if [ "${SEQB:-0}" -ge 30 ]; then echo "   >>> sequenceB (cji 43/44) reached — full sequenceA cut set captured"; sleep 4; break; fi
done

sleep 1; ENDFOC=$(read_focus); ENDPID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
{ echo "# Gcine-cut device DIAG end ($(date -Is))"; echo "focus: $ENDFOC"; echo "pid: ${ENDPID:-gone}"; echo "crashed: ${CRASHED:-no}"; echo "max_af: $(grep -aoE 'af=[0-9.]+' "$LOG" | grep -oE '[0-9.]+' | sort -n | tail -1)"; } > "$FG"

echo "== scoreboard =="
echo "  GCINE-SP : $(grep -ac 'GCINE-SP ' "$LOG")"
echo "  GCINE-OC : $(grep -ac 'GCINE-OC ' "$LOG")"
echo "  GCINE-JC : $(grep -ac 'GCINE-JC ' "$LOG")"
echo "  max af   : $(grep -aoE 'af=[0-9.]+' "$LOG" | grep -oE '[0-9.]+' | sort -n | tail -1)"
echo "  crashed  : ${CRASHED:-no}   focus=$ENDFOC"
echo "  --- all GCINE-JC (joint commands fired) ---"
grep -a 'GCINE-JC ' "$LOG" | sed -E 's/^.*(GCINE-JC.*)$/\1/'
echo "  log: $LOG"
