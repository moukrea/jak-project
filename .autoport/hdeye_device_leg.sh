#!/usr/bin/env bash
# hdeye_device_leg.sh — Grecharged-hd-eye-scale DEVICE proof (Redmi eae4df44). Counters only, no
# image is taken anywhere; quality stays the owner's call.
#
# Two legs, in this order so the device is left holding the SHIPPED params (deploy_verify checks
# the external override byte-for-byte against the built one):
#   legARMED  : an eye-scale params file with every per-slot rest pushed to 0.0 is pushed to the
#               EXTERNAL override path — no rebuild, that is the whole point of the params being
#               DATA. The resting value is then above the anchor, so the rewrite MUST fire and MUST
#               shrink. Positive control: it is what stops the shipped leg's changed=0 from being
#               a vacuous zero.
#   legSHIP   : the shipped params restored. The HD eye path must be LIVE (covered>0) and each
#               character's anchor must equal the authored rest the scene actually shows, so no
#               base look is shifted. changed=0 is CORRECT here — with the right anchors the curve
#               is an exact identity at rest, and jak1 only moves this channel inside spooled
#               cutscenes (measured exhaustively offline by .autoport/hdeye_anim_scan.py).
# Scene: village1-hut at the Keira workshop -> Jak (eye_id 0/1), Daxter (2/3) and Keira (6/7).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-eye-scale; mkdir -p "$OUT"
LOG="$OUT/device-eyescale.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
EXT_PARAMS="/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets/physics_chains.txt"
PARAMS=recharged_assets/physics_chains.txt
WATCH="${WATCH:-120}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[hdeye-device FAIL] $*"; exit 1; }

get_key(){ $ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a "$1" | tr -d '\r'; }
set_key(){ # key value — app MUST be stopped; edits an existing key in place, never appends
  local tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  grep -q "$1" "$tmp" || die "no $1 key"
  sed -i "s/$1 = #[tf]/$1 = $2/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings"
  rm -f "$tmp"
  local now; now=$(get_key "$1")
  [[ "$now" == *"$1 = $2"* ]] || die "$1 write did not stick"
}
push_params(){ # $1 = local file to place at the external override path, md5-verified
  $ADB -s "$S" push "$1" "$EXT_PARAMS" >/dev/null 2>&1 || die "cannot push $EXT_PARAMS"
  local l d; l=$(md5sum "$1" | cut -d' ' -f1)
  d=$($ADB -s "$S" shell md5sum "$EXT_PARAMS" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  [ "$l" = "$d" ] || die "external params push did not land (local=$l device=$d)"
  say "external params on device: md5 $d ($(basename "$1"))"
}

say "===== Grecharged-hd-eye-scale device leg — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)"
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — wait for owner"
fi

ARMED="$OUT/.physics_chains.armed.txt"
sed -E 's/^(slot [0-7]) rest_iris=[0-9.]+ +rest_pupil=[0-9.]+/\1 rest_iris=0.0 rest_pupil=0.0/' \
  "$PARAMS" > "$ARMED"
NARM=$(grep -cE '^slot [0-7] rest_iris=0\.0 rest_pupil=0\.0$' "$ARMED")
[ "$NARM" = 8 ] || die "arming rewrote $NARM/8 slot lines"
say "armed params built: 8/8 slot rests pushed to 0.0"

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
  # the SHIPPED params must be what stays on the device: deploy_verify compares them byte for byte
  $ADB -s "$S" push "$PARAMS" "$EXT_PARAMS" >/dev/null 2>&1 || say "cleanup WARNING: params restore failed"
  set_key 'recharged-master?' "$ORIG_MASTER" && set_key 'recharged-enhanced-models?' "$ORIG_ENH" \
    && say "cleanup: owner settings + shipped params restored, warp cleared, app stopped" \
    || say "cleanup WARNING: could not restore owner settings"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

# Sets LC_OUT to the harvested logcat path. NOT via stdout: `say` writes to stdout too, so a
# command substitution would swallow the whole progress trace into the "path".
run_leg(){ # $1 tag  $2 params-file
  local tag="$1" pfile="$2"
  LC_OUT=""
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  push_params "$pfile"
  $ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '-130.50 34.50 202.41'" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  LC="$OUT/device-eyescale-$tag.logcat.log"; : > "$LC"
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
  LCP=$!
  say "[$tag] launching warp=village1-hut (keira workshop)"
  $ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0 warpok; t0=$(date +%s); warpok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LC" && { warpok=1; break; }
    grep -qa 'LEVEL-WARP-FAIL' "$LC" && { say "[$tag] warp FAILED"; kill "$LCP" 2>/dev/null; return 1; }
    grep -qaE 'signal (4|6|11) \(SIG' "$LC" && { say "[$tag] CRASH during warp boot"; kill "$LCP" 2>/dev/null; return 1; }
    sleep 5
  done
  [ "$warpok" = 1 ] || { say "[$tag] warp spawn never seen"; kill "$LCP" 2>/dev/null; return 1; }
  say "[$tag] warp spawned at t+$(( $(date +%s)-t0 ))s — idling ${WATCH}s for [eyescale] heartbeats"
  sleep "$WATCH"
  local focus; focus=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
  say "[$tag] mCurrentFocus: $focus"
  kill "$LCP" 2>/dev/null || true; LCP=0
  [[ "$focus" == *jak1* ]] || { say "[$tag] game not foreground at end"; return 1; }
  grep -qaE 'signal (4|6|11) \(SIG' "$LC" && { say "[$tag] native crash during watch"; return 1; }
  say "[$tag] $(grep -a -m1 'HD-MODELS fr3-select GAME' "$LC" | tr -d '\r')"
  say "[$tag] $(grep -a -m1 '\[eyescale\] PARAMSRC=' "$LC" | tr -d '\r')"
  grep -a '\[eyescale\] anchor slot=' "$LC" | head -8 | sed 's/.*\[eyescale\]/[eyescale]/' | tr -d '\r' \
    | sed "s/^/[$tag] /" | tee -a "$LOG" >/dev/null
  grep -a -m1 'HD-MODELS fr3-select GAME' "$LC" | grep -q ENHANCED || { say "[$tag] enhanced GAME.fr3 not selected"; return 1; }
  LC_OUT="$LC"
  return 0
}

PASS=1
LC_ARMED=""; LC_SHIP=""
run_leg armed   "$ARMED"  && LC_ARMED="$LC_OUT" || PASS=0
run_leg shipped "$PARAMS" && LC_SHIP="$LC_OUT"  || PASS=0

grade(){ say ""; say "---- $1 ----"; python3 .autoport/hdeye_parse.py "$2" "$1" $3 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
[ -n "${LC_ARMED:-}" ] && { grade device-armed   "$LC_ARMED" "--armed" || PASS=0; } || PASS=0
[ -n "${LC_SHIP:-}"  ] && { grade device-shipped "$LC_SHIP"  ""        || PASS=0; } || PASS=0

say ""
if [ "$PASS" = 1 ]; then
  say "[eyescale-device PASS] HD eye path live on the phone with the authored anchors; armed control"
  say "                       fires and shrinks; no crash; device left on the shipped params"
  exit 0
fi
say "[eyescale-device FAIL]"
exit 1
