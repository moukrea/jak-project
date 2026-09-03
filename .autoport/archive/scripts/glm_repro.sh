#!/usr/bin/env bash
# glm_repro.sh — Glang-mixed repro driver.
# Plants a settings.ini with a chosen audio/text/subtitle language mix, warps Jak
# next to a talkable NPC (default: village1 farmer), and screencaps the interaction
# prompt so its language can be checked against the TEXT-language setting.
# Usage: glm_repro.sh <tag> [audio_lang] [text_lang] [cont] [pos_m]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-mixA}"
AUD="${2:-0}"          # game-language (audio): 0=en 1=fr
TXT="${3:-1}"          # text-language + subtitle-language: 0=en 1=fr
CONT="${4:-village1-hut}"
POSM="${5:--4.16 2.0 -63.4}"   # ~2.7m north of the farmer (-4.16 1.63 -66.1)
OUT=.autoport/reports/Glang-mixed
mkdir -p "$OUT"
PACKAGE=org.opengoal.gk.jak1
ACTIVITY=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"
RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > /data/data/$PACKAGE/files/cpad_inject'" >/dev/null 2>&1 || true; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
crash_seen(){ grep -qaE 'Fatal signal|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: needs owner unlock" | tee "$RES"; exit 2
fi

# --- plant settings: template from the desktop build, languages overridden (INI form) ---
TMP=$(mktemp)
sed -E \
  -e "s/^game-language = [0-9]+/game-language = $AUD/" \
  -e "s/^text-language = [0-9]+/text-language = $TXT/" \
  -e "s/^subtitle-language = [0-9]+/subtitle-language = $TXT/" \
  /home/emeric/.config/OpenGOAL/jak1/settings/settings.ini > "$TMP"
A shell "mkdir -p /storage/emulated/0/OpenGOAL/jak1" >/dev/null 2>&1
A push "$TMP" /storage/emulated/0/OpenGOAL/jak1/settings.ini >/dev/null
echo "  planted settings: audio=$AUD text=$TXT subtitle=$TXT"
A shell "grep -E 'language' /storage/emulated/0/OpenGOAL/jak1/settings.ini"
rm -f "$TMP"

# --- warp props ---
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
for p in task.close want.levels want.display want.vis; do
  A shell "setprop debug.opengoal.$p ''" >/dev/null 2>&1 || true; done
A shell setprop debug.opengoal.mouche.buzz 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.eco.spawn 0 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true
  A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true; }
trap cleanup EXIT
A shell am start -W -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1

echo "  waiting title..."
for i in $(seq 1 150); do grep -qa 'link finish: logo' "$LOG" && break; crash_seen && break; sleep 1; done
echo "  waiting LEVEL-WARP-SPAWN..."
WARP_OK=0
for i in $(seq 1 120); do
  grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { WARP_OK=1; echo "  warp fired ~${i}s"; break; }
  grep -qa "LEVEL-WARP-FAIL name=$CONT" "$LOG" && { echo "  warp FAILED"; break; }
  crash_seen && { echo "  crash before warp"; break; }
  sleep 1
done
grep -a 'LEVEL-WARP-POS' "$LOG" | tail -1

# settle, then capture a series (prompt draws when close + camera settles)
sleep 12
for n in 1 2 3 4; do
  A exec-out screencap -p > "$OUT/$TAG-cap$n.png" 2>/dev/null || true
  sleep 4
done
FOC="no"; focus_is_app && FOC="yes"
CR=0; crash_seen && CR=1
LASTPOS=$(grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9. ]+)\).*/\1/p')
{
  echo "=== glm_repro $TAG (audio=$AUD text=$TXT cont=$CONT posm=$POSM) $(date -Is) ==="
  echo "RESULT tag=$TAG warp_ok=$WARP_OK crashed=$CR focus_app=$FOC last-pos=($LASTPOS)"
  echo "  text-load lines:"
  grep -aE 'TXT|text' "$LOG" | grep -aiE 'load|link' | tail -12
} | tee "$RES"
trap - EXIT
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
A shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
if [ "${KEEP:-0}" = 1 ]; then
  echo "  KEEP=1: app left running, logcat pid $LOGPID still writing $LOG"
else
  kill "$LOGPID" 2>/dev/null || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
fi
echo "== $TAG done =="
