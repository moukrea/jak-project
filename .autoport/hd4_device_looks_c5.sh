#!/usr/bin/env bash
# hd4_device_looks_c5.sh — Grecharged-hd-models4 DEFECT CYCLE 5, DEVICE proof of the look carousel
# additions/fixes plus the Keira strap x collision work, on the real Redmi.
#
# FIVE sub-legs, each a FRESH app launch warped to village1-hut (-130.50 34.50 202.41):
#   M   hd-look-jak=4                      -> jakm-hd-lod0   (JAK 3 MASQUE BAISSE, bare face)
#   P   hd-look-jak=5                      -> jakp-hd-lod0   (JAK II PRISON, new)
#   F   hd-look-jak=6                      -> jakf-hd-lod0   (JAK 3 BAREFOOT, new)
#   K1  hd-look-keira=1 + physics?=#t q=1  -> keira-hd-lod0  (+ strap x collision counters)
#   K3  hd-look-keira=2 + physics?=#t q=1  -> keira3-hd-lod0 (+ strap x collision counters)
# Every sub-leg forces recharged-master?=#t, recharged-enhanced-models?=#t and pins the other three
# look keys to 1, so exactly one HD Jak look is live. M/P/F leave the owner's physics settings alone.
#
# Instrument = RENDERER/PHYSICS COUNTERS ONLY. No screenshot, no screenrecord: the owner banned
# captures as a validation instrument (2026-08-04, "pour toujours").
# Owner settings.ini is pulled once, byte-restored in the EXIT trap even on failure; warp setprops
# cleared; app force-stopped.
# Failures ACCUMULATE (set -uo pipefail, never set -e) — one verdict per line so report greps stay
# line-based.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
LOG="$OUT/legLOOKS-c5.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INI_BAK="$OUT/.settings.ini.owner-backup-looksc5"
INI_TMP=$(mktemp)
WATCH="${WATCH:-90}"
WARP=village1-hut; WPOS='-130.50 34.50 202.41'
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[legLOOKS-c5 FAIL] $*"; exit 1; }

say "===== cycle-5 device LOOKS leg (jakm/jakp/jakf + keira straps) — $(date -Is) ====="
say "watch=${WATCH}s warp=$WARP pos=$WPOS serial=$S"
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" pull "$PCS_DEV" "$INI_BAK" >/dev/null 2>&1 || die "cannot pull owner settings.ini"
say "owner settings.ini backed up ($(stat -c%s "$INI_BAK") bytes) -> $INI_BAK"

set_ini_dev(){ # [music]-trap-aware: existing key in place, new keys top-level after enhanced-models
  local key="$1" val="$2"
  if grep -q "^$key = " "$INI_TMP"; then sed -i "s|^$key = .*|$key = $val|" "$INI_TMP"
  else sed -i "/^recharged-enhanced-models? = /a $key = $val" "$INI_TMP"
       grep -q "^$key = $val$" "$INI_TMP" || die "could not insert $key"
  fi
}

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

OK=1

# run_leg <tag> <hd-look-jak> <hd-look-keira> <physics?|-> <physics-quality|-> <expected-model>
#         <expected-ag|-> <forbid-other-jak-looks 0|1>
run_leg(){
  local TAG="$1" JLOOK="$2" KLOOK="$3" PHY="$4" QUAL="$5" WANT="$6" AG="$7" FORBID="$8"
  local LC="$OUT/legLOOKS-$TAG.logcat.log"; : > "$LC"
  local LEGOK=1
  say ""
  say "=== SUB-LEG $TAG: hd-look-jak=$JLOOK hd-look-keira=$KLOOK physics?=$PHY quality=$QUAL expect ${WANT}-lod0 ag=$AG ==="

  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  cp "$INI_BAK" "$INI_TMP"   # every sub-leg starts from the OWNER file: no key leaks between legs
  set_ini_dev 'recharged-master?' '#t'
  set_ini_dev 'recharged-enhanced-models?' '#t'
  set_ini_dev 'hd-look-jak' "$JLOOK"
  set_ini_dev 'hd-look-daxter' 1
  set_ini_dev 'hd-look-keira' "$KLOOK"
  set_ini_dev 'hd-look-samos' 1
  if [ "$PHY" != '-' ]; then
    set_ini_dev 'physics?' "$PHY"
    set_ini_dev 'physics-quality' "$QUAL"
  fi
  $ADB -s "$S" push "$INI_TMP" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings.ini ($TAG)"
  say "$TAG device settings: $($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -aE '^(recharged-(master|enhanced-models)\?|hd-look-|physics)' | tr -d '\r' | tr '\n' ';')"

  $ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legLOOKS-$TAG.exit-info-before.txt" 2>&1
  $ADB -s "$S" shell setprop debug.opengoal.level.warp "$WARP" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WPOS'" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
  LCP=$!
  say "$TAG launching $PKG/$ACT (warp=$WARP)"
  $ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

  local T0 WARPOK=0 BOOTBAD=0 n
  T0=$(date +%s)
  while [ $(( $(date +%s)-T0 )) -lt 240 ]; do
    n=$(grep -ac "LEVEL-WARP-SPAWN name=$WARP" "$LC" || true)
    [ "$n" -gt 0 ] && { WARPOK=1; break; }
    n=$(grep -ac 'LEVEL-WARP-FAIL' "$LC" || true)
    [ "$n" -gt 0 ] && { say "FAIL($TAG): LEVEL-WARP-FAIL during boot"; BOOTBAD=1; break; }
    n=$(grep -acE 'signal (4|6|11) \(SIG' "$LC" || true)
    [ "$n" -gt 0 ] && { say "FAIL($TAG): native crash during warp boot"; BOOTBAD=1; break; }
    sleep 5
  done
  if [ "$WARPOK" != 1 ]; then
    [ "$BOOTBAD" = 1 ] || say "FAIL($TAG): warp spawn never seen within 240s"
    kill "$LCP" 2>/dev/null || true; LCP=0
    $ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legLOOKS-$TAG.exit-info-after.txt" 2>&1
    $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
    say "[legLOOKS-c5 SUB $TAG FAIL]"
    OK=0
    return
  fi
  say "$TAG warp spawned at t+$(( $(date +%s)-T0 ))s — idling ${WATCH}s for submit/blink/flicker/physics counters"
  sleep "$WATCH"

  local FOCUS
  FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
  kill "$LCP" 2>/dev/null || true; LCP=0
  $ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/legLOOKS-$TAG.exit-info-after.txt" 2>&1
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2

  # ---------------- per-sub-leg gates: one verdict per LINE, all failures accumulate -------------
  local ENH SUB STOCKLID EVB EVG CRASH s hb donor m mn stack
  ENH=$(grep -ac 'HD-MODELS fr3-select GAME: ENHANCED' "$LC" || true)
  if [ "$ENH" -gt 0 ]; then say "OK($TAG): HD-MODELS fr3-select GAME: ENHANCED (x$ENH)"
  else say "FAIL($TAG): GAME not ENHANCED (no fr3-select line)"; LEGOK=0; fi

  SUB=$(grep -ac "SUBMITTED name='${WANT}-lod0' found=1" "$LC" || true)
  if [ "$SUB" -gt 0 ]; then say "OK($TAG): ${WANT}-lod0 SUBMITTED found=1"
  else say "FAIL($TAG): ${WANT}-lod0 never SUBMITTED found=1"; LEGOK=0; fi

  if [ "$FORBID" = 1 ]; then
    stack=0
    for m in jak-hd jak2-hd jak3-hd jakm-hd jakp-hd jakf-hd; do
      [ "$m" = "$WANT" ] && continue
      mn=$(grep -ac "SUBMITTED name='${m}-lod0' found=1" "$LC" || true)
      [ "$mn" -gt 0 ] && { say "FAIL($TAG): forbidden ${m}-lod0 also SUBMITTED (look did not REPLACE)"; stack=$((stack+1)); }
    done
    if [ "$stack" = 0 ]; then say "OK($TAG): no other jak look submitted — the look REPLACES, it does not stack"
    else LEGOK=0; fi
  fi

  STOCKLID=$(grep -ac '\[hd-blink\] STOCKLID' "$LC" || true)
  if [ "$STOCKLID" = 0 ]; then say "OK($TAG): [hd-blink] STOCKLID=0"
  else say "FAIL($TAG): [hd-blink] STOCKLID=$STOCKLID (stock lid painted over the HD face)"; LEGOK=0; fi
  for s in 0 1; do
    hb=$(grep -ac "\[hd-blink\] slot=$s .*donor_paints" "$LC" || true)
    donor=$(grep -a "\[hd-blink\] slot=$s " "$LC" | grep -oE 'donor_paints=[0-9]+' | grep -cv 'donor_paints=0$' || true)
    if [ "$hb" -gt 0 ] && [ "$donor" -ge 1 ]; then
      say "OK($TAG): blink slot=$s heartbeats=$hb donor-painted-windows=$donor"
    else
      say "FAIL($TAG): blink slot=$s heartbeats=$hb donor-painted-windows=$donor (need >=1 heartbeat with donor_paints>0)"; LEGOK=0
    fi
  done

  EVB=$(grep -ac '\[hd-flicker\] BLACKOUT' "$LC" || true)
  EVG=$(grep -ac '\[hd-flicker\] GAP' "$LC" || true)
  if [ "$EVB" = 0 ] && [ "$EVG" = 0 ]; then say "OK($TAG): flicker BLACKOUT=0 GAP=0"
  else say "FAIL($TAG): flicker BLACKOUT=$EVB GAP=$EVG"; LEGOK=0; fi

  CRASH=$(grep -acE 'signal (4|6|11) \(SIG' "$LC" || true)
  if [ "$CRASH" = 0 ]; then say "OK($TAG): no native crash signal in logcat"
  else say "FAIL($TAG): $CRASH native crash signal line(s) in logcat"; LEGOK=0; fi
  if [[ "$FOCUS" == *jak1* ]]; then say "OK($TAG): app still foreground at end ($FOCUS)"
  else say "FAIL($TAG): game not foreground at end ($FOCUS)"; LEGOK=0; fi

  # ---------------- cycle-5 Keira strap x physics-collision gates (K1/K3 only) -------------------
  if [ "$AG" != '-' ]; then
    local PHYSOK=1 NCOL UNK WIN NNAN NBIG PUSH MAXPEN WITHPUSH
    NCOL=$(grep -a "\[HD-PHYS\] init ag=$AG " "$LC" | grep -oE 'colliders=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
    NCOL=${NCOL:-0}
    if [ "$NCOL" -ge 3 ]; then
      say "OK($TAG): [HD-PHYS] init ag=$AG colliders=$NCOL (>=3: base chest sphere + strap-only chest sphere + hips sphere resolved)"
    else
      say "FAIL($TAG): [HD-PHYS] init ag=$AG colliders=$NCOL (<3: the per-chain 'chains=' collider filters did not resolve)"; PHYSOK=0
    fi
    UNK=$(grep -ac 'chains= references unknown chain\|resolved to zero chains' "$LC" || true)
    if [ "$UNK" = 0 ]; then say "OK($TAG): zero collider chain-filter resolution warnings"
    else say "FAIL($TAG): $UNK collider chain-filter resolution warning(s)"; PHYSOK=0; fi
    WIN=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -ac 'window: chains=' || true)
    if [ "$WIN" -ge 1 ]; then say "OK($TAG): $AG [HD-PHYS] window lines=$WIN"
    else say "FAIL($TAG): no [HD-PHYS] window line for ag=$AG"; PHYSOK=0; fi
    NNAN=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -oE 'nan-resets=[0-9]+' | grep -cv 'nan-resets=0$' || true)
    if [ "$NNAN" = 0 ]; then say "OK($TAG): $AG nan-resets=0 on every window"
    else say "FAIL($TAG): $AG has $NNAN window(s) with nan-resets>0"; PHYSOK=0; fi
    NBIG=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -oE 'maxdev=[0-9.]+' | cut -d= -f2 | awk '{ if ($1+0>=5000) n++ } END{ print n+0 }' || true)
    if [ "${NBIG:-0}" = 0 ]; then say "OK($TAG): $AG bounded — zero windows with maxdev>=5000"
    else say "FAIL($TAG): $AG has $NBIG unbounded window(s) (maxdev>=5000)"; PHYSOK=0; fi
    # INSTRUMENT GATE (cycle-5 measurement bug): every `format 0` is its OWN logcat line on Android,
    # so a multi-call window used to split across 3 lines and the line-based parse below silently
    # read push=/maxpen= as ABSENT -> "pushes=0", which reads like "collision never fired" when it
    # actually fired thousands of times. The emitter now builds the window in one string and prints
    # it once; assert that here so a regression of the emitter FAILS LOUDLY instead of reporting 0.
    WITHPUSH=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -ac 'window: chains=.*push=' || true)
    if [ "$WIN" -ge 1 ] && [ "$WITHPUSH" -lt "$WIN" ]; then
      say "FAIL($TAG): $AG has $WIN window lines but only $WITHPUSH carry push= — the [HD-PHYS] window is SPLIT across logcat lines (emitter regression); push/maxpen are NOT measurable, refusing to report 0"
      PHYSOK=0
    fi
    PUSH=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -oE 'push=[0-9]+' | cut -d= -f2 | awk '{ s+=$1 } END{ print s+0 }' || true)
    MAXPEN=$(grep -a "\[HD-PHYS\] ag=$AG " "$LC" | grep -oE 'maxpen=[0-9.]+' | cut -d= -f2 | sort -g | tail -1)
    if [ "$PHYSOK" = 1 ]; then
      say "OK($TAG): $AG windows=$WIN colliders=$NCOL pushes=${PUSH:-0} maxpen=${MAXPEN:-0} nan=0 bounded"
    else
      say "HARVEST($TAG): $AG windows=$WIN colliders=$NCOL pushes=${PUSH:-0} maxpen=${MAXPEN:-0} nan-nonzero-windows=$NNAN unbounded-windows=${NBIG:-0}"
      LEGOK=0
    fi
  fi

  if [ "$LEGOK" = 1 ]; then say "[legLOOKS-c5 SUB $TAG PASS]"
  else say "[legLOOKS-c5 SUB $TAG FAIL]"; OK=0; fi
}

run_leg M  4 1 '-'  '-' jakm-hd   '-'        1
run_leg P  5 1 '-'  '-' jakp-hd   '-'        1
run_leg F  6 1 '-'  '-' jakf-hd   '-'        1
run_leg K1 1 1 '#t' 1   keira-hd  keira-hd   0
run_leg K3 1 2 '#t' 1   keira3-hd keira3-hd  0

say ""
if [ "$OK" = 1 ]; then
  say "[legLOOKS-c5 PASS] jakm/jakp/jakf looks submit and replace, blink live, flicker 0/0, keira+keira3 strap colliders resolved and bounded on device"
  exit 0
else
  say "[legLOOKS-c5 FAIL]"
  exit 1
fi
