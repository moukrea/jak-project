#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models3 — PROOF13 RESUME (Honor AREE026206000788)
#
# Context: HEAD d4fddfd245 (driver-hide moved to Merc2 TTL suppression — Daxter restored
# by construction) was deployed + deploy_verify PASS at 2026-08-04 01:19 (proof13b), but
# the phone dropped off the USB bus at 01:27 (re-enumerated WITHOUT an adb interface —
# reboot/charge-only lockout) before the run evidence was harvested. This script finishes
# the harvest in ONE command once adb is back. It does NOT rebuild or reinstall anything:
# the device already provably runs fresh HEAD.
#
# Harvest targets (validator + honesty):
#   - routed logcat: [JAK-HD] spawned skel-bones=76, HD-MODELS merc-load jak-hd-lod0,
#     [jak-hd-render] SUBMITTED found=1, [jak-hd-render] suppressing stock eichar-lod0,
#     [JAK-HD] bone3 hd==ei world lines moving across frames (anim-follow)
#   - captures: proof13b-idle.png (Jak + DAXTER on shoulder = the d4fddfd245 point),
#     proof13b-running.png (ly=0 held)
#   - dumpsys window mCurrentFocus (jak1 foreground)
#   - exit-info: no new reason=5
#   - cleanup discipline: enhanced OFF in external pc-settings + force-stop (ALWAYS, trap)
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-AREE026206000788}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models3
LOG="$OUT/proof13b-run.log"; : > "$LOG"
# the ONE live settings file on this build (pc-settings.gc layout is gone; Loader.cpp
# read_persisted_enhanced_models() reads <user settings dir>/settings.ini)
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[proof13b FAIL] $*"; exit 1; }
setinj(){ $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 || true; }
press(){ setinj "$1"; sleep 0.32; setinj release; sleep 0.28; say "  inject press: $1"; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

set_enhanced(){ # set_enhanced '#t'|'#f' — app MUST be stopped (it rewrites the file on exit)
  local want="$1" tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  grep -q 'recharged-enhanced-models?' "$tmp" || die "no recharged-enhanced-models? key in pc-settings"
  sed -i "s/recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = $want/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push pc-settings"
  rm -f "$tmp"
  local now; now=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-enhanced-models?' | tr -d '\r')
  say "pc-settings on device now: '$now' (wanted $want)"
  [[ "$now" == *"$want"* ]] || die "enhanced toggle write did not stick"
}

say "===== Grecharged-hd-models3 PROOF13 resume — $(date -Is) ====="

# 0. presence + unlocked -----------------------------------------------------------------
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb (owner replug/unlock needed; phone lost its adb interface at 01:27)"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
# lock check on the CURRENT user only: the Honor's secondary profile ("Espace parallèle",
# id=100) reports deviceLocked=1 permanently and must not trip the gate.
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi
say "device present: $($ADB -s "$S" shell getprop ro.product.model | tr -d '\r') serial=$S"

# 1. deploy_verify (fresh, at harvest time) ------------------------------------------------
bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/proof13b.deploy_verify.log" 2>&1 \
  || { tail -6 "$OUT/proof13b.deploy_verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; }
say "deploy_verify: $(tail -1 "$OUT/proof13b.deploy_verify.log")"

# 2. enhanced ON (app stopped) — snapshot the OWNER'S pre-run value first: he play-tested
# tonight and left the toggle ON deliberately (post-integrity-gate); tests must not stomp
# his choice. Cleanup restores exactly what he had.
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_ENH=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
say "owner's pre-run enhanced value: $ORIG_ENH (will be restored after the run)"
set_enhanced '#t'
$ADB -s "$S" shell run-as $PKG rm -f files/cpad_inject >/dev/null 2>&1 || true
setinj release

# cleanup discipline: ALWAYS restore the owner's pre-run toggle + kill app, whatever happens
cleanup(){
  setinj release
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_enhanced "$ORIG_ENH" && say "cleanup: enhanced toggle restored to owner's pre-run value ($ORIG_ENH) + app force-stopped after the run" \
    || say "cleanup WARNING: could not restore the owner's toggle value — DO NOT leave the device like this"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

# 3. exit-info snapshot BEFORE ---------------------------------------------------------------
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/proof13b.exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/proof13b.exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info BEFORE: newest native-crash ts='${PREV_R5_TS:-none}'"

# 4. launch + logcat ----------------------------------------------------------------------
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/proof13b.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
say "launching $PKG/$ACT (no reinstall — device already runs fresh HEAD)"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

# 5. wait title (render frames advancing) ---------------------------------------------------
T0=$(date +%s); RF=0
while [ $(( $(date +%s)-T0 )) -lt 180 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && break; sleep 5
done
[ "$RF" -gt 600 ] || die "title never reached (render-frame=$RF at t+$(( $(date +%s)-T0 ))s)"
say "title reached: render-frame=$RF pid=$(pidof_app)"
sleep 3

# 6. into gameplay: START opens menu, X on row 0 = Continue (device save exists) -------------
press start; sleep 2
press x
say "waiting for gameplay (bone3 world-coordinate lines)..."
ingame=0
while [ $(( $(date +%s)-T0 )) -lt 400 ]; do
  B=$(grep -a '\[JAK-HD\] bone3' "$LC" | tail -1)
  X=$(echo "$B" | grep -oE 'hd=\(-?[0-9]+' | grep -oE '\-?[0-9]+' | head -1); X=${X:-0}
  [ "${X#-}" -gt 10000 ] 2>/dev/null && { ingame=1; break; }
  sleep 5
done
[ "$ingame" -eq 1 ] || die "never saw in-game bone3 world coords (last: $(grep -a 'bone3' "$LC" | tail -1))"
say "IN-GAME: $(grep -a 'bone3' "$LC" | tail -1)"
sleep 60   # settle (longer: collect >=8 throttled bone3 world samples): Daxter spawn + idle anim

# 7. captures --------------------------------------------------------------------------------
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
say "mCurrentFocus: $FOCUS"
[[ "$FOCUS" == *jak1* ]] || die "game not foreground at capture time ($FOCUS)"
$ADB -s "$S" exec-out screencap -p > "$OUT/proof13b-idle.png" 2>/dev/null
say "captured proof13b-idle.png ($(stat -c%s "$OUT/proof13b-idle.png") bytes)"
setinj "ly=0"; sleep 2.5
$ADB -s "$S" exec-out screencap -p > "$OUT/proof13b-running.png" 2>/dev/null
setinj release
say "captured proof13b-running.png ($(stat -c%s "$OUT/proof13b-running.png") bytes)"
sleep 30   # more bone3 samples while idle again

# 8. harvest verdicts -------------------------------------------------------------------------
sleep 2
SPAWN=$(grep -a -m1 '\[JAK-HD\] spawned skel-bones=76' "$LC")
MLOAD=$(grep -a -m1 'merc-load .*jak-hd-lod0' "$LC")
SUBM=$(grep -a -m1 'jak-hd-render.*SUBMITTED.*found=1' "$LC")
SUPP=$(grep -a -m1 'suppressing stock eichar-lod0' "$LC")
NB=$(grep -a -c 'bone3 hd=(-' "$LC")
PID=$(pidof_app)
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/proof13b.exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/proof13b.exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEWCRASH=no; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEWCRASH=YES
say ""
say "===== HARVEST ====="
say "spawn:    ${SPAWN:-MISSING}"
say "merc-load:${MLOAD:-MISSING}"
say "submit:   ${SUBM:-MISSING}"
say "suppress: ${SUPP:-MISSING}"
say "bone3 world lines: $NB"
say "pid at end: '$PID'   new reason=5: $NEWCRASH (ts='${NEW_R5_TS:-none}')"
say "bone3 follow samples (last 4):"
grep -a 'bone3 hd=(-' "$LC" | tail -4 | tee -a "$LOG"
OK=1
[ -n "$SPAWN" ] || { say "FAIL: no spawn line"; OK=0; }
[ -n "$MLOAD" ] || { say "FAIL: no jak-hd-lod0 merc-load"; OK=0; }
[ -n "$SUBM" ]  || { say "FAIL: no SUBMITTED found=1"; OK=0; }
[ -n "$SUPP" ]  || { say "FAIL: no eichar-lod0 suppression (Daxter fix not active?)"; OK=0; }
# the GOAL-side dump fires at companion frames 60 & 150 ONLY (jak-hd.gc dbg-frames) —
# exactly 2 world samples per in-game spawn BY DESIGN; 2 == full instrument output.
[ "$NB" -ge 2 ] || { say "FAIL: <2 bone3 world samples (instrument emits exactly 2/spawn)"; OK=0; }
[ -n "$PID" ]   || { say "FAIL: app died"; OK=0; }
[ "$NEWCRASH" = no ] || { say "FAIL: new native crash"; OK=0; }
[ "$OK" -eq 1 ] && say "[proof13b PASS] all discriminators harvested on $S (HEAD build) — captures + logcat banked." \
               || say "[proof13b FAIL] see above"
exit $(( 1 - OK ))
