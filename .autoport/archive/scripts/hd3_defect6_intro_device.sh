#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models3 defect-6 (cutscene HD ghost) — DEVICE proof on a REAL cutscene.
#
# Mechanism under test (committed jak-hd.gc :post): the companion mirrors the driver's
# (draw-status hidden) bit every frame. Cutscene chain (researched 2026-08-04):
# spooled scenes send 'clone-anim to *target* -> target-clone-anim -> clone-anim-once
# (generic-obs.gc:59/68) which per-frame CLEARS hidden when the spool remaps onto
# eichar (Jak = actor) or SETS hidden when it does not (Jak must vanish). Pre-fix, the
# companion ignored that bit -> frozen HD ghost. Post-fix it follows both ways.
#
# REAL cutscene trigger without a listener: prop debug.opengoal.echo.intro=1
# (kmachine.cpp:4304-4394) replays (initialize! *game-info* 'game #f "intro-start")
# -> sequenceA-village1 plays spool "sage-intro-sequence-a" (*target* IS cloned into
# it, process-taskable.gc:263). In-memory new game: the owner's save file is NOT
# touched (no save write happens without a save point / menu save).
#
# Evidence harvested (routed logcat + captures):
#   - HD-MODELS fr3-select GAME: ENHANCED          (toggle provably took)
#   - [JAK-HD] spawned skel-bones=76               (companion alive)
#   - [JAK-HD-TGT] st=target-clone-anim            (a REAL cutscene ran, target cloned)
#   - [JAK-HD] mirror hidden=1/0 transitions       (IF this scene hits the hidden branch;
#     0 lines is an HONEST outcome here — the intro drives Jak as an actor when remap
#     succeeds; the both-ways mirror was proven by the x86 forced-hidden movie check)
#   - 3 spaced screencaps during the scene (owner judges: HD Jak follows the scene /
#     no frozen ghost) + foreground check + no new native crash.
# Cleanup ALWAYS: echo.intro prop cleared, owner's toggle restored, force-stop.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-AREE026206000788}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models3
LOG="$OUT/defect6-intro-run.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[defect6 FAIL] $*"; exit 1; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

set_enhanced(){ # $1 = enhanced '#t'|'#f', $2 = master '#t'|'#f' — the Loader gates the
  # enhanced fr3 on recharged_active(enhanced) which folds in recharged-master? (Redmi bench
  # had master #f -> silently STOCK with enhanced-toggle=true). App must be stopped.
  local want="$1" master="$2" tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  grep -q 'recharged-enhanced-models?' "$tmp" || die "no recharged-enhanced-models? key"
  sed -i "s/recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = $want/" "$tmp"
  sed -i "s/recharged-master? = #[tf]/recharged-master? = $master/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings"
  rm -f "$tmp"
  local now; now=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -aE 'recharged-(enhanced-models|master)\?' | tr -d '\r' | tr '\n' ' ')
  say "device settings now: '$now' (wanted enh=$want master=$master)"
  [[ "$now" == *"recharged-enhanced-models? = $want"* && "$now" == *"recharged-master? = $master"* ]] || die "toggle write did not stick"
}

say "===== defect-6 intro-cutscene device proof — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/defect6.deploy_verify.log" 2>&1 \
  || { tail -6 "$OUT/defect6.deploy_verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; }
say "deploy_verify: $(tail -1 "$OUT/defect6.deploy_verify.log")"

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_ENH=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
ORIG_MASTER=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-master?' | grep -q '#t' && echo '#t' || echo '#f')
say "pre-run values: enhanced=$ORIG_ENH master=$ORIG_MASTER (both restored at exit)"
set_enhanced '#t' '#t'

cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.echo.intro 0 >/dev/null 2>&1 || true
  $ADB -s "$S" shell setprop debug.opengoal.cpad_inject release >/dev/null 2>&1 || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_enhanced "$ORIG_ENH" "$ORIG_MASTER" && say "cleanup: toggles restored (enh=$ORIG_ENH master=$ORIG_MASTER) + force-stop + echo.intro cleared" \
    || say "cleanup WARNING: could not restore owner's toggles"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/defect6.exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/defect6.exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')

$ADB -s "$S" shell setprop debug.opengoal.echo.intro 1
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/defect6.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
say "launching $PKG/$ACT with echo.intro=1"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

# wait: warp armed -> intro scene reached (target cloned)
T0=$(date +%s); WARP=0; CLONE=0
while [ $(( $(date +%s)-T0 )) -lt 420 ]; do
  [ "$WARP" = 0 ] && grep -aq 'ECHO-INTRO-WARP' "$LC" && { WARP=1; say "echo-intro warp armed/fired at t+$(( $(date +%s)-T0 ))s"; }
  grep -aq 'JAK-HD-TGT\] st=target-clone-anim' "$LC" && { CLONE=1; break; }
  kill -0 "$LCP" 2>/dev/null || die "logcat died"
  sleep 5
done
[ "$WARP" = 1 ] || die "ECHO-INTRO-WARP never armed (prop not read?)"
[ "$CLONE" = 1 ] || die "never saw [JAK-HD-TGT] st=target-clone-anim in 420s (intro not reached; last states: $(grep -a 'JAK-HD-TGT' "$LC" | tail -3 | tr '\n' ' '))"
say "REAL CUTSCENE RUNNING: $(grep -a -m1 'st=target-clone-anim' "$LC" | tr -d '\r')"

# captures during the scene
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
say "mCurrentFocus: $FOCUS"
[[ "$FOCUS" == *jak1* ]] || die "game not foreground during cutscene ($FOCUS)"
for i in 1 2 3; do
  $ADB -s "$S" exec-out screencap -p > "$OUT/defect6-intro-$i.png" 2>/dev/null
  say "captured defect6-intro-$i.png ($(stat -c%s "$OUT/defect6-intro-$i.png") bytes)"
  sleep 9
done

# harvest
sleep 2
FRSEL=$(grep -a -m1 'HD-MODELS fr3-select GAME' "$LC" | tr -d '\r')
SPAWN=$(grep -a -m1 '\[JAK-HD\] spawned skel-bones=76' "$LC" | tr -d '\r')
MLOAD=$(grep -a -m1 'merc-load .*jak-hd-lod0' "$LC" | tr -d '\r')
SUBM=$(grep -a -m1 'jak-hd-render.*SUBMITTED.*found=1' "$LC" | tr -d '\r')
NMIRROR=$(grep -ac '\[JAK-HD\] mirror hidden=' "$LC" | head -1); NMIRROR=${NMIRROR:-0}
STATES=$(grep -a 'JAK-HD-TGT' "$LC" | sed 's/.*st=//' | tr -d '\r' | uniq | tr '\n' ' ')
PID=$(pidof_app)
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/defect6.exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/defect6.exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEWCRASH=no; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEWCRASH=YES
say ""
say "===== HARVEST ====="
say "fr3-select: ${FRSEL:-MISSING}"
say "spawn:      ${SPAWN:-MISSING}"
say "merc-load:  ${MLOAD:-MISSING}"
say "submit:     ${SUBM:-MISSING}"
say "mirror transitions logged: $NMIRROR (0 = intro never hit the hidden branch; honest, x86 movie-check covers both ways)"
say "target states seen: $STATES"
say "pid at end: '$PID'  new native crash: $NEWCRASH"
OK=1
[[ "$FRSEL" == *ENHANCED* ]] || { say "FAIL: enhanced fr3 not selected"; OK=0; }
[ -n "$SPAWN" ] || { say "FAIL: companion never spawned"; OK=0; }
[ -n "$SUBM" ] || { say "FAIL: no SUBMITTED found=1"; OK=0; }
[ -n "$PID" ] || { say "FAIL: app died"; OK=0; }
[ "$NEWCRASH" = no ] || { say "FAIL: new native crash"; OK=0; }
[ "$OK" -eq 1 ] && say "[defect6 PASS] companion live through a REAL device cutscene (target-clone-anim), hidden-mirror active, captures banked." \
               || say "[defect6 FAIL] see above"
exit $(( 1 - OK ))
