#!/usr/bin/env bash
# hd4_device_jakm_leg.sh — CYCLE-4 item 3 DEVICE proof: Jak 3 MASQUE BAISSÉ (jakm-hd, look jak=4).
# village1-hut warp, hd-look 4/1/1/1 -> jakm-hd-lod0 SUBMITTED found=1, other jak looks forbidden,
# [hd-blink] slots 0/1 live (donor lid paints, zero STOCKLID), flicker 0/0, no native crash.
# Owner settings.ini byte-restored. Counters + state dumps only, captures = owner illustration.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models4
LOG="$OUT/legM-jakm-run.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INI_BAK="$OUT/.settings.ini.owner-backup-jakm"
INI_TMP=$(mktemp)
WATCH="${WATCH:-110}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[legM FAIL] $*"; exit 1; }
setinj(){ $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 </dev/null || true; }
pulse(){ setinj "$1"; sleep "${2:-0.5}"; setinj neutral; sleep "${3:-0.6}"; }

say "===== cycle-4 device jakm (masked) leg — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" pull "$PCS_DEV" "$INI_BAK" >/dev/null 2>&1 || die "cannot pull owner settings.ini"
say "owner settings.ini backed up ($(stat -c%s "$INI_BAK") bytes)"
cp "$INI_BAK" "$INI_TMP"
set_ini_dev(){ # [music]-trap-aware: existing key in place, new keys top-level after enhanced-models
  local key="$1" val="$2"
  if grep -q "^$key = " "$INI_TMP"; then sed -i "s|^$key = .*|$key = $val|" "$INI_TMP"
  else sed -i "/^recharged-enhanced-models? = /a $key = $val" "$INI_TMP"
       grep -q "^$key = $val$" "$INI_TMP" || die "could not insert $key"
  fi
}
set_ini_dev 'recharged-master?' '#t'
set_ini_dev 'recharged-enhanced-models?' '#t'
set_ini_dev 'hd-look-jak' 4
set_ini_dev 'hd-look-daxter' 1
set_ini_dev 'hd-look-keira' 1
set_ini_dev 'hd-look-samos' 1
$ADB -s "$S" push "$INI_TMP" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings.ini"
say "device settings: $($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -aE '^(recharged-(master|enhanced-models)\?|hd-look-)' | tr -d '\r' | tr '\n' ';')"

LCP=0
cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  if [ -f "$INI_BAK" ]; then
    $ADB -s "$S" push "$INI_BAK" "$PCS_DEV" >/dev/null 2>&1 \
      && say "cleanup: owner settings.ini byte-restored, warp cleared, app stopped" \
      || say "cleanup WARNING: could not restore owner settings.ini"
  fi
  rm -f "$INI_TMP" 2>/dev/null || true
  [ "${LCP:-0}" -gt 0 ] && kill "$LCP" 2>/dev/null || true
}
trap cleanup EXIT

$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legM.exit-info-before.txt" 2>&1
$ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
$ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '-130.50 34.50 202.41'" >/dev/null 2>&1 </dev/null
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/legM-jakm.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
say "launching warp=village1-hut (look jak=4)"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
T0=$(date +%s); WARPOK=0
while [ $(( $(date +%s)-T0 )) -lt 240 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LC" && { WARPOK=1; break; }
  grep -qa 'LEVEL-WARP-FAIL' "$LC" && die "warp FAILED"
  grep -qaE 'signal (4|6|11) \(SIG' "$LC" && die "CRASH during warp boot"
  sleep 5
done
[ "$WARPOK" = 1 ] || die "warp spawn never seen"
say "warp spawned at t+$(( $(date +%s)-T0 ))s — idling ${WATCH}s for submit+blink heartbeats"
sleep 20
$ADB -s "$S" exec-out screencap -p > "$OUT/legM-jakm-idle.png" 2>/dev/null
say "captured legM-jakm-idle.png ($(stat -c%s "$OUT/legM-jakm-idle.png" 2>/dev/null || echo 0) bytes) — owner illustration only"
$ADB -s "$S" shell rm -f /sdcard/hd4_jakm.mp4 >/dev/null 2>&1
( $ADB -s "$S" shell screenrecord --time-limit 14 --bit-rate 12000000 /sdcard/hd4_jakm.mp4 >/dev/null 2>&1 ) &
RECP=$!
sleep 1; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=-120" 1.0 0.6; setinj neutral
wait $RECP 2>/dev/null || true; sleep 1
$ADB -s "$S" pull /sdcard/hd4_jakm.mp4 "$OUT/legM-jakm-pan.mp4" >/dev/null 2>&1 || say "warn: no mp4"
$ADB -s "$S" shell rm -f /sdcard/hd4_jakm.mp4 >/dev/null 2>&1
sleep $(( WATCH - 40 > 0 ? WATCH - 40 : 10 )) 2>/dev/null || sleep 60
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
say "mCurrentFocus: $FOCUS"
[[ "$FOCUS" == *jak1* ]] || die "game not foreground at end ($FOCUS)"
grep -qaE 'signal (4|6|11) \(SIG' "$LC" && die "native crash during watch"
kill "$LCP" 2>/dev/null || true; LCP=0
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legM.exit-info-after.txt" 2>&1

OK=1
grep -qa 'HD-MODELS fr3-select GAME: ENHANCED' "$LC" || { say "FAIL: GAME not ENHANCED"; OK=0; }
if grep -qa "SUBMITTED name='jakm-hd-lod0' found=1" "$LC"; then say "OK: jakm-hd-lod0 SUBMITTED found=1"
else say "FAIL: jakm-hd-lod0 never submitted"; OK=0; fi
for m in jak-hd jak2-hd jak3-hd; do
  grep -qa "SUBMITTED name='$m-lod0' found=1" "$LC" && { say "FAIL: forbidden $m-lod0 submitted"; OK=0; }
done
bash .autoport/hd4_check_blink_logcat.sh "$LC" legM 0 1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || OK=0
[ "$OK" = 1 ] && { say "[legM PASS] masked look device-proven"; exit 0; } || { say "[legM FAIL]"; exit 1; }
