#!/usr/bin/env bash
# gmatch_crash_forensics.sh — drive NEW GAME -> sage-intro cinematic on the
# CURRENT device build and capture the FULL logcat (no grep filter) so the
# complete gk_sigsegv_diag dump survives: GK-DIAG sig=, A36-SYMBOLIZE pc/lr,
# x0-x31, F1A-MERC-DRAW, and the GK-DIAG DBLEE-REPAIR counter. Does NOT rebuild
# or redeploy. Restores nothing (leave device as-is for re-run); caller restores.
#
# Device serial eae4df44 ONLY. Real measurements only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SERIAL="eae4df44"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=".autoport/reports/gmatch-forensics"
mkdir -p "$OUT"
FULL="$OUT/full-logcat-$(date +%s).log"
adb(){ "$ADB" -s "$SERIAL" "$@"; }
read_focus(){ adb shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
is_fg(){ case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clear_inject(){ inject ""; }
cur_frame(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$FULL" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }

[ "$(adb get-state 2>/dev/null)" = "device" ] || { echo "device not attached"; exit 2; }

echo "== forensics: full-logcat crash capture =="
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb logcat -G 32M >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$FULL"
# FULL logcat (only restrict to our tag + crash tags to keep size sane, but keep
# ALL GK-DIAG lines incl. registers/symbolize).
( adb logcat -v threadtime opengoal-gk:* DEBUG:* libc:* AndroidRuntime:* '*:S' > "$FULL" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null; clear_inject 2>/dev/null' EXIT

clear_inject
echo "  launch"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "== wait fg==jak1 (90s) =="
dl=$(( $(date +%s) + 90 )); while [ "$(date +%s)" -lt "$dl" ]; do is_fg && break; sleep 2; done
is_fg && echo "  fg=jak1" || echo "  WARN fg!=jak1"

echo "== let attract settle (40s) =="
t=$(( $(date +%s) + 40 )); while [ "$(date +%s)" -lt "$t" ]; do
  fr=$(cur_frame); fr=${fr:-0}; [ "$fr" -ge 1500 ] 2>/dev/null && { echo "  attract render=$fr"; break; }; sleep 2
done
sleep 4

echo "== START -> menu =="
inject "start"; sleep 1.2; clear_inject; sleep 5
echo "== NEW GAME nav + X =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
echo "== continue-without-saving =="
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "x";    sleep 0.6; clear_inject; sleep 6

echo "== watch cinematic up to 260s for crash or in-game =="
t0=$(date +%s)
while :; do
  el=$(( $(date +%s) - t0 )); [ "$el" -ge 260 ] && { echo "  wall cap ${el}s"; break; }
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  [ -z "$PID" ] && { echo "  app gone at ${el}s"; break; }
  if grep -aqE 'GK-DIAG sig=|Fatal signal' "$FULL" 2>/dev/null; then echo "  CRASH at ${el}s"; sleep 2; break; fi
  FM=$(cur_frame); FM=${FM:-0}
  (( el % 20 < 4 )) && echo "   [${el}s] render=$FM fg=$(is_fg && echo jak1 || echo other)"
  sleep 4
done

ENDFOC="$(read_focus)"; ENDPID="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
kill ${LCP:-0} 2>/dev/null || true
clear_inject 2>/dev/null || true
trap - EXIT

echo ""
echo "== SUMMARY =="
echo "  end fg: $ENDFOC  pid=${ENDPID:-gone}"
echo "  max render frame: $(cur_frame)"
echo "  full logcat: $FULL  ($(wc -l < "$FULL") lines)"
echo ""
echo "== crash signature =="
grep -aE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' "$FULL" | head -5
echo "== DBLEE-REPAIR count =="
grep -ac 'DBLEE-REPAIR' "$FULL"
grep -aE 'DBLEE-REPAIR' "$FULL" | head -3
echo "== A36-SYMBOLIZE (pc/lr module) =="
grep -aE 'A36-SYMBOLIZE' "$FULL" | head -6
echo "== F1A-MERC-DRAW / F1A-BUCKET =="
grep -aE 'F1A-BUCKET|F1A-MERC-DRAW|F1E-MERC-TEX' "$FULL" | head -6
echo "== last 8 link finishes before end =="
grep -aE 'link finish:' "$FULL" | tail -8
echo "== registers x0-x31 (if dumped) =="
grep -aoE 'GK-DIAG x[0-9]+=0x[0-9a-f]+' "$FULL" | head -32
