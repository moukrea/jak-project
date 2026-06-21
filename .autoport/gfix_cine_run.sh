#!/usr/bin/env bash
# gfix_cine_run.sh — drive the OWNER's EXACT new-game path on the real device and
# watch the WHOLE intro cinematic through to gameplay for a crash.
#
#   main menu -> NEW GAME -> select save SLOT 0 (has data) -> OVERWRITE -> YES
#   -> real auto-save write (kmemcard.cpp) -> intro cinematic -> gameplay
#
# This is the path the prior gates DODGED (they picked "continue without saving",
# which skips the save write). cpad tokens per android/android_input_audio.cpp:
#   start | down/up/left/right | x(=cross,confirm) | square/triangle(=cancel)
# yes-no overwrite dialog: default NO; LEFT sets YES (progress.gc:895); x confirms.
#
# Robust crash detection over a window covering the whole cinematic to gameplay:
#   GK-DIAG sig=(4|6|11) | Fatal signal | signal N (SIG | app-not-foreground.
# Reach = A35-RENDER frame >= GAMEPLAY_FRAME (10500) with foreground == jak1.
#
# Usage: bash .autoport/gfix_cine_run.sh <run-number> [BEFORE|AFTER] [skip-install]
# Device serial eae4df44 ONLY. Does NOT rebuild/redeploy. Leaves device as-is.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh

SERIAL="eae4df44"
export ANDROID_SERIAL="$SERIAL"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PKG/files/cpad_inject"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
RUN="${1:-1}"
PHASE="${2:-AFTER}"        # BEFORE = calibration (expect crash); AFTER = expect crash-free
SKIP_INSTALL="${3:-}"
GAMEPLAY_FRAME=10500
CINE_WINDOW=480           # seconds to watch the cinematic->gameplay window

OUT=".autoport/reports/Gfix-cinematic-crash"
mkdir -p "$OUT"
FULL="$OUT/full-logcat-${PHASE}-run${RUN}.log"
RESULTS="$OUT/run-results.txt"

adb(){ "$ADB" -s "$SERIAL" "$@"; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }
app_pid(){ adb shell pidof "$PKG" 2>/dev/null | tr -d '\r'; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clear_inject(){ inject ""; }
cur_frame(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$FULL" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }
crash_hit(){ grep -aqE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal [0-9]+ \(SIG' "$FULL" 2>/dev/null; }

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

[ "$(adb get-state 2>/dev/null)" = "device" ] || { echo "device $SERIAL not attached"; exit 2; }

echo "== gfix-cine run $RUN ($PHASE): owner-exact NEW GAME -> SAVE SLOT -> OVERWRITE -> YES =="
disable_interlopers
adb shell svc power stayon true >/dev/null 2>&1 || true
trap 'kill ${LCP:-0} 2>/dev/null; clear_inject 2>/dev/null; reenable_interlopers; adb shell svc power stayon false >/dev/null 2>&1 || true' EXIT

if [ "$SKIP_INSTALL" = "install" ]; then
  echo "  installing $APK"
  adb install -r -d "$APK" >/dev/null 2>&1 || adb install -r "$APK" >/dev/null 2>&1 || echo "  WARN install failed"
fi

adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb logcat -G 64M >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$FULL"
( adb logcat -v threadtime opengoal-gk:* DEBUG:* libc:* AndroidRuntime:* '*:S' > "$FULL" ) &
LCP=$!

clear_inject
echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "== wait fg==jak1 (120s) =="
dl=$(( $(date +%s) + 120 )); while [ "$(date +%s)" -lt "$dl" ]; do is_fg && break; sleep 2; done
is_fg && echo "  fg=jak1" || echo "  WARN fg!=jak1"

echo "== let attract settle (frame>=1500, up to 60s) =="
t=$(( $(date +%s) + 60 )); while [ "$(date +%s)" -lt "$t" ]; do
  fr=$(cur_frame); fr=${fr:-0}; [ "$fr" -ge 1500 ] 2>/dev/null && { echo "  attract render=$fr"; break; }
  crash_hit && { echo "  CRASH during attract"; break; }
  sleep 3
done
sleep 4

echo "== START -> progress menu =="
inject "start"; sleep 1.2; clear_inject; sleep 5

echo "== ensure cursor on NEW GAME =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5

echo "== X: select NEW GAME -> save-game-title (slot list) =="
inject "x";    sleep 0.6; clear_inject; sleep 3

if [ "${FLOW:-overwrite}" = "continue" ]; then
  echo "== SHORTCUT PATH (control): DOWN x4 -> CONTINUE WITHOUT SAVING -> X (no save write) =="
  inject "down"; sleep 0.4; clear_inject; sleep 0.9
  inject "down"; sleep 0.4; clear_inject; sleep 0.9
  inject "down"; sleep 0.4; clear_inject; sleep 0.9
  inject "down"; sleep 0.4; clear_inject; sleep 0.9
  inject "x";    sleep 0.6; clear_inject
else
  echo "== OWNER PATH: X on SLOT 0 (has data) -> OVERWRITE prompt =="
  inject "x";    sleep 0.6; clear_inject; sleep 3
  echo "== LEFT: set YES on the overwrite yes-no dialog =="
  inject "left"; sleep 0.4; clear_inject; sleep 1.5
  echo "== X: confirm OVERWRITE=YES -> memcard-saving (real save write) -> cinematic =="
  inject "x";    sleep 0.6; clear_inject
fi
CONFIRM_OFS=$(wc -l < "$FULL" 2>/dev/null || echo 0)
echo "  post-confirm log offset: $CONFIRM_OFS"
sleep 8

echo "== watch cinematic -> gameplay up to ${CINE_WINDOW}s for crash or frame>=${GAMEPLAY_FRAME} =="
t0=$(date +%s); VERDICT="TIMEOUT"; REACHED=""
while :; do
  el=$(( $(date +%s) - t0 ))
  [ "$el" -ge "$CINE_WINDOW" ] && { echo "  wall cap ${el}s"; break; }
  if crash_hit; then VERDICT="CRASH"; echo "  CRASH detected at ${el}s"; sleep 3; break; fi
  PID=$(app_pid)
  if [ -z "$PID" ]; then VERDICT="APP-GONE"; echo "  app process gone at ${el}s"; sleep 2; break; fi
  FM=$(cur_frame); FM=${FM:-0}
  if [ "$FM" -ge "$GAMEPLAY_FRAME" ] 2>/dev/null && is_fg; then
    VERDICT="REACH"; REACHED="$FM"; echo "  GAMEPLAY reached: frame=$FM fg=jak1 at ${el}s"; break
  fi
  (( el % 20 < 5 )) && echo "   [${el}s] render=$FM fg=$(is_fg && echo jak1 || echo other)"
  sleep 4
done

ENDFOC="$(read_focus)"; ENDPID="$(app_pid)"; MAXF="$(cur_frame)"; MAXF="${MAXF:-0}"
ELAPSED=$(( $(date +%s) - t0 ))
# final crash sweep over whole log (catch a sig that landed after the loop break)
crash_hit && VERDICT="CRASH"
case "$ENDFOC" in *"$PKG"*) ENDFG="jak1";; *) ENDFG="${ENDPID:+other}"; ENDFG="${ENDFG:-gone}";; esac

kill ${LCP:-0} 2>/dev/null || true
clear_inject 2>/dev/null || true

SIGLINE="$(grep -aE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' "$FULL" | head -1 | sed 's/  */ /g')"
DBLEE=$(grep -ac 'DBLEE-REPAIR' "$FULL" 2>/dev/null || echo 0)
RFTD=$(grep -ac 'RFTD-STOMP-REPAIR\|RFTD-STOMP' "$FULL" 2>/dev/null || echo 0)
TGT=$(grep -ac 'TARGET-TRANS-REPAIR\|GD3-TARGET' "$FULL" 2>/dev/null || echo 0)

echo ""
echo "== SUMMARY run $RUN ($PHASE) =="
echo "  verdict=$VERDICT  maxframe=$MAXF  endfg=$ENDFG  pid=${ENDPID:-gone}  elapsed=${ELAPSED}s"
echo "  crash-sig: ${SIGLINE:-none}"
echo "  repair counters: DBLEE=$DBLEE RFTD=$RFTD TGT=$TGT"
echo "  full logcat: $FULL ($(wc -l < "$FULL") lines)"
echo ""
echo "== crash dump (if any) =="
grep -aE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' "$FULL" | head -6
grep -aE 'A36-SYMBOLIZE' "$FULL" | head -6
grep -aoE 'GK-DIAG x[0-9]+=0x[0-9a-f]+' "$FULL" | head -32
echo "== last link finishes / level displays =="
grep -aE 'link finish:|Displaying level|set-master-mode|GAMEPLAY' "$FULL" | tail -8

# structured machine-readable verdict line
printf 'RUN %s PHASE=%s verdict=%s maxframe=%s endfg=%s elapsed=%ss sig=[%s] DBLEE=%s RFTD=%s TGT=%s newgame-save-overwrite-yes %s\n' \
  "$RUN" "$PHASE" "$VERDICT" "$MAXF" "$ENDFG" "$ELAPSED" "${SIGLINE:-none}" "$DBLEE" "$RFTD" "$TGT" "$(date -Is)" >> "$RESULTS"
echo "  -> appended verdict to $RESULTS"

trap - EXIT
reenable_interlopers
adb shell svc power stayon false >/dev/null 2>&1 || true
[ "$VERDICT" = "REACH" ] && exit 0 || exit 1
