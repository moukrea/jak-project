#!/usr/bin/env bash
# hd4_device_blink_keira_leg.sh — CYCLE-4 device blink proof for KEIRA (slots 6/7; jak 0/1 also
# live since target spawns). Warp village1-hut at the Keira workshop position, idle 120s, harvest
# [hd-blink] heartbeats from logcat (counters, never captures). Owner settings byte-restored.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models4
LOG="$OUT/legK-blink-run.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
WATCH="${WATCH:-120}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[legK FAIL] $*"; exit 1; }

get_key(){ $ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a "$1" | tr -d '\r'; }
set_key(){ # key value
  local tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  grep -q "$1" "$tmp" || die "no $1 key"
  sed -i "s/$1 = #[tf]/$1 = $2/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings"
  rm -f "$tmp"
  local now; now=$(get_key "$1")
  [[ "$now" == *"$1 = $2"* ]] || die "$1 write did not stick"
}

say "===== cycle-4 device blink leg KEIRA — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_MASTER=$(get_key 'recharged-master?'          | grep -q '#t' && echo '#t' || echo '#f')
ORIG_ENH=$(   get_key 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
say "owner pre-run: master=$ORIG_MASTER enhanced=$ORIG_ENH (both restored after)"
set_key 'recharged-master?' '#t'
set_key 'recharged-enhanced-models?' '#t'

cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_key 'recharged-master?' "$ORIG_MASTER" && set_key 'recharged-enhanced-models?' "$ORIG_ENH" \
    && say "cleanup: owner settings restored, warp cleared, app stopped" \
    || say "cleanup WARNING: could not restore owner settings"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legK.exit-info-before.txt" 2>&1
$ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
$ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '-130.50 34.50 202.41'" >/dev/null 2>&1 </dev/null
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/legK-blink.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
say "launching warp=village1-hut keira pos"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
T0=$(date +%s); WARPOK=0
while [ $(( $(date +%s)-T0 )) -lt 240 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LC" && { WARPOK=1; break; }
  grep -qa 'LEVEL-WARP-FAIL' "$LC" && die "warp FAILED"
  grep -qaE 'signal (4|6|11) \(SIG' "$LC" && die "CRASH during warp boot"
  sleep 5
done
[ "$WARPOK" = 1 ] || die "warp spawn never seen"
say "warp spawned at t+$(( $(date +%s)-T0 ))s — idling ${WATCH}s for blink heartbeats"
sleep "$WATCH"
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
say "mCurrentFocus: $FOCUS"
[[ "$FOCUS" == *jak1* ]] || die "game not foreground at end ($FOCUS)"
grep -qaE 'signal (4|6|11) \(SIG' "$LC" && die "native crash during watch"
kill "$LCP" 2>/dev/null || true; LCP=0
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legK.exit-info-after.txt" 2>&1
say "watch done — checking [hd-blink] slots 6 7 (keira) + 0 1 (jak)"
bash .autoport/hd4_check_blink_logcat.sh "$LC" legK 6 7 0 1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
exit "$rc"
