#!/usr/bin/env bash
# physics_device_leg.sh — Grecharged-secondary-motion DEVICE proof (Redmi eae4df44), title screen:
#   LEG D-MAX: physics?=#t quality=2, looks 1111 -> [hd-phys] params loaded (>=8 models),
#              [HD-PHYS] init chains>0, window state dumps: nan-resets=0 everywhere, maxdev<5000
#              (bounded), no native crash.
#   LEG D-OFF: physics?=#f -> ZERO [HD-PHYS] window lines (full in-game disable; init-only OK).
# Counters + state dumps only (renderer-counter-gates rule) — no capture campaigns.
# Owner settings.ini byte-restored; app killed after the test.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/device_leg.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INI_BAK="$OUT/.settings.ini.owner-backup-phys"
INI_TMP=$(mktemp)
WATCH="${WATCH:-150}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[device-leg FAIL] $*"; exit 1; }

say "===== secondary-motion device leg — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" pull "$PCS_DEV" "$INI_BAK" >/dev/null 2>&1 || die "cannot pull owner settings.ini"
say "owner settings.ini backed up ($(stat -c%s "$INI_BAK") bytes)"

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
      && say "cleanup: owner settings.ini byte-restored, app stopped" \
      || say "cleanup WARNING: could not restore owner settings.ini"
  fi
  rm -f "$INI_TMP" 2>/dev/null || true
  [ "${LCP:-0}" -gt 0 ] && kill "$LCP" 2>/dev/null || true
}
trap cleanup EXIT

run_leg(){ # run_leg <tag> <physics #t/#f> <quality> <mode expect-phys|expect-off>
  local TAG="$1" PHY="$2" QUAL="$3" MODE="$4"
  local LC="$OUT/device_leg_$TAG.logcat.log"; : > "$LC"
  cp "$INI_BAK" "$INI_TMP"
  set_ini_dev 'recharged-master?' '#t'
  set_ini_dev 'recharged-enhanced-models?' '#t'
  set_ini_dev 'hd-look-jak' 1
  set_ini_dev 'hd-look-daxter' 1
  set_ini_dev 'hd-look-keira' 1
  set_ini_dev 'hd-look-samos' 1
  set_ini_dev 'physics?' "$PHY"
  set_ini_dev 'physics-quality' "$QUAL"
  $ADB -s "$S" push "$INI_TMP" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings.ini"
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL (village1-hut warp, watch ${WATCH}s) ==="
  $ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '-130.50 34.50 202.41'" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I ActivityManager:W '*:S' >> "$LC" ) 2>/dev/null &
  LCP=$!
  $ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  local T0 W=0
  T0=$(date +%s)
  while [ $(( $(date +%s)-T0 )) -lt 420 ]; do
    grep -aq 'LEVEL-WARP-SPAWN' "$LC" 2>/dev/null && { W=1; break; }; sleep 8
  done
  [ "$W" = 1 ] || { say "FAIL($TAG): warp never landed"; return 1; }
  say "warp landed (village1-hut) — watching ${WATCH}s"
  sleep "$WATCH"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  kill "$LCP" 2>/dev/null || true; LCP=0
  local OK=1
  # native crash scan (grep -a: logcat routed through the harness can carry binary).
  # NO bare 'SIGILL' pattern: the jak2 bind-hook INFO line contains the word ("...doesn't
  # SIGILL...") = false positive. 'Fatal signal N (SIGILL)' is still caught by 'Fatal signal'.
  local CRASH; CRASH=$(grep -acE 'Fatal signal|SIGSEGV|SIGBUS' "$LC" || true)
  local NLOAD NINIT NWIN NNAN NREST NCH
  NLOAD=$(grep -ac 'params loaded' "$LC" || true)
  NINIT=$(grep -ac '\[HD-PHYS\] init ag=' "$LC" || true)
  NCH=$(grep -a '\[HD-PHYS\] init ag=' "$LC" | grep -vc 'chains=0 ' || true)
  NWIN=$(grep -ac '\[HD-PHYS\].*window: chains=' "$LC" || true)
  NNAN=$(grep -a 'nan-resets=' "$LC" | grep -cv 'nan-resets=0 ' || true)
  NREST=$(grep -ac 'rest-converged' "$LC" || true)
  say "leg $TAG: params-loaded=$NLOAD init=$NINIT chains-resolving=$NCH windows=$NWIN nan-bad=$NNAN rest=$NREST crash=$CRASH"
  [ "$CRASH" = 0 ] || { say "FAIL($TAG): native crash markers in logcat"; OK=0; }

  # ---- (E) MENU BINDING, on the artifact that actually shipped to the phone ---------------------
  if grep -aq '\[PHYS-MENU\] FATAL' "$LC"; then
    say "FAIL($TAG): [PHYS-MENU] FATAL on device — physics rows not found / mis-ordered"; OK=0
  fi
  local NMENU; NMENU=$(grep -ac '\[PHYS-MENU\].*next-is-meshbrowser=1' "$LC" || true)
  [ "${NMENU:-0}" -ge 1 ] \
    || { say "FAIL($TAG): device log has no '[PHYS-MENU] rows wired ... next-is-meshbrowser=1'"; OK=0; }

  # ---- CYCLE-2 STRUCTURAL GATES ----------------------------------------------------------------
  # These read fields that live on the SAME logcat line as the rest of the window (the window is
  # assembled in a string buffer and emitted with ONE format call — see jak-hd-physics.gc; a
  # multi-call dump splits on device and every one of these greps would silently read as absent).
  if [ "$NWIN" -gt 0 ]; then
    local NROOT NRES NREG
    NROOT=$(grep -a 'rootdev=' "$LC" | grep -cv 'rootdev=0\.0000 ' || true)
    [ "${NROOT:-0}" = 0 ] || { say "FAIL($TAG): $NROOT window(s) with rootdev!=0 — a locked hair root moved"; OK=0; }
    NRES=$(grep -a 'resid=' "$LC" | grep -cv 'resid=0 ' || true)
    [ "${NRES:-0}" = 0 ] || { say "FAIL($TAG): $NRES window(s) with residual penetrations"; OK=0; }
    NREG=$(grep -a 'reglue=' "$LC" | awk '{if (match($0,/reglue=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 0) n++} END {print n+0}')
    [ "${NREG:-0}" -ge 1 ] || { say "FAIL($TAG): no window reports reglue>0 — fake-wind neutralization never ran on device"; OK=0; }
    say "leg $TAG: rootdev-bad=$NROOT resid-bad=$NRES reglue-windows=$NREG"
  fi
  case "$MODE" in
    expect-phys)
      [ "$NLOAD" -ge 1 ] || { say "FAIL($TAG): no '[hd-phys] params loaded' line"; OK=0; }
      [ "$NCH" -ge 1 ] || { say "FAIL($TAG): no companion resolved any chain"; OK=0; }
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window state dump"; OK=0; }
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan-resets nonzero — sim exploded"; OK=0; }
      local NBIG; NBIG=$(grep -a 'maxdev=' "$LC" | awk -F'maxdev=' '{print $2}' | awk '{if ($1+0 >= 5000.0) n++} END {print n+0}')
      [ "$NBIG" = 0 ] || { say "FAIL($TAG): $NBIG window(s) with maxdev>=5000 — not bounded"; OK=0; }
      # at least one MOVING bounded window (anchor animated + sim deviating) — real-gameplay proof;
      # parked windows (anchmove=0) legitimately read maxdev=0 (self-tracking rest).
      # grep on 'anchmove=' NOT 'window: chains=': the dump is TWO GOAL format calls (8-arg cap)
      # and the device logcat flushes them as TWO lines — maxdev/anchmove live on the second half.
      local NMOVDEV; NMOVDEV=$(grep -a 'anchmove=' "$LC" | awk '{
        am=0; md=0;
        if (match($0, /anchmove=[0-9.]+/)) am=substr($0, RSTART+9, RLENGTH-9)+0;
        if (match($0, /maxdev=[0-9.]+/))   md=substr($0, RSTART+7, RLENGTH-7)+0;
        if (am > 1.0 && md > 0.5 && md < 5000.0) n++ } END {print n+0}')
      [ "$NMOVDEV" -ge 1 ] || { say "FAIL($TAG): no MOVING bounded window"; OK=0; }
      say "leg $TAG: bounded-windows=yes moving-bounded-windows=$NMOVDEV"
      ;;
    expect-off)
      [ "$NWIN" = 0 ] || { say "FAIL($TAG): $NWIN window lines with physics?=#f — OFF is not off"; OK=0; }
      ;;
  esac
  [ "$OK" = 1 ]
}

FAILED=0
run_leg "D-MAX" '#t' 2 expect-phys || FAILED=1
run_leg "D-OFF" '#f' 1 expect-off  || FAILED=1

say ""
if [ "$FAILED" = 0 ]; then say "[physics device leg PASS] D-MAX + D-OFF green"; else say "[physics device leg FAIL] see legs above"; fi
exit "$FAILED"
