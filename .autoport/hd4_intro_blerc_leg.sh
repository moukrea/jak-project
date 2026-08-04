#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models4 CYCLE-2 leg 3 — REAL intro cutscene on device (class B faces +
# class A eyes, owner-facing visual evidence). Derived from hd3_defect6_intro_device.sh.
#
# Trigger: prop debug.opengoal.echo.intro=1 (kmachine.cpp echo-intro path) replays
# (initialize! *game-info* 'game #f "intro-start") -> sequenceA-village1 plays spool
# "sage-intro-sequence-a": Samos TALKS (sage driver blerc channels live), Jak is cloned
# into the scene. In-memory new game; the owner's save is NOT touched.
#
# What this leg evidences for cycle 2:
#   - class B: the samos-hd/jak-hd companions hold a blerc override slot (NO
#     "[HD-COMP] no free blerc override slot" line) while a real talking scene plays;
#     the ported blend-targets deform = owner judges the captures.
#   - class A: eye draws remapped to the driver's eye slots render in-scene (captures).
#   - carried: fr3-select ENHANCED, [HD-COMP] spawned, merc-load, SUBMITTED found=1,
#     per-actor suppress, foreground, no new native crash.
# Cleanup ALWAYS: echo.intro cleared, owner's toggles restored, force-stop.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models4
LOG="$OUT/leg3-intro-run.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[leg3 FAIL] $*"; exit 1; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

set_enhanced(){ # $1 = enhanced '#t'|'#f', $2 = master '#t'|'#f' (app must be stopped)
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

say "===== cycle-2 leg3 intro-cutscene (class B faces / class A eyes) — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_ENH=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
ORIG_MASTER=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-master?' | grep -q '#t' && echo '#t' || echo '#f')
say "pre-run values: enhanced=$ORIG_ENH master=$ORIG_MASTER (both restored at exit)"
set_enhanced '#t' '#t'

cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.echo.intro 0 >/dev/null 2>&1 || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_enhanced "$ORIG_ENH" "$ORIG_MASTER" && say "cleanup: toggles restored (enh=$ORIG_ENH master=$ORIG_MASTER) + force-stop + echo.intro cleared" \
    || say "cleanup WARNING: could not restore owner's toggles"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/leg3.exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/leg3.exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')

$ADB -s "$S" shell setprop debug.opengoal.echo.intro 1
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/leg3-intro.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
say "launching $PKG/$ACT with echo.intro=1"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

# wait: warp armed -> intro scene reached (target cloned into the spool)
T0=$(date +%s); WARP=0; CLONE=0
while [ $(( $(date +%s)-T0 )) -lt 420 ]; do
  [ "$WARP" = 0 ] && grep -aq 'ECHO-INTRO-WARP' "$LC" && { WARP=1; say "echo-intro warp armed/fired at t+$(( $(date +%s)-T0 ))s"; }
  grep -aq 'JAK-HD-TGT\] st=target-clone-anim' "$LC" && { CLONE=1; break; }
  kill -0 "$LCP" 2>/dev/null || die "logcat died"
  sleep 5
done
[ "$WARP" = 1 ] || die "ECHO-INTRO-WARP never armed (prop not read?)"
[ "$CLONE" = 1 ] || die "never saw [JAK-HD-TGT] st=target-clone-anim in 420s (last states: $(grep -a 'JAK-HD-TGT' "$LC" | tail -3 | tr '\n' ' '))"
say "REAL CUTSCENE RUNNING: $(grep -a -m1 'st=target-clone-anim' "$LC" | tr -d '\r')"

# captures during the talking scene (Samos speaks over ~60s; space them across it)
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
say "mCurrentFocus: $FOCUS"
[[ "$FOCUS" == *jak1* ]] || die "game not foreground during cutscene ($FOCUS)"
for i in 1 2 3; do
  $ADB -s "$S" exec-out screencap -p > "$OUT/leg3-intro-$i.png" 2>/dev/null
  say "captured leg3-intro-$i.png ($(stat -c%s "$OUT/leg3-intro-$i.png") bytes)"
  sleep 9
done

# harvest
sleep 2
FRSEL=$(grep -a -m1 'HD-MODELS fr3-select' "$LC" | tr -d '\r')
NCOMP=$(grep -ac '\[HD-COMP\] spawned' "$LC"); NCOMP=${NCOMP:-0}
MLOADS=$(grep -a 'merc-load' "$LC" | grep -oE '[a-z]+-hd-lod0' | sort -u | tr '\n' ' ')
SUBM=$(grep -a 'SUBMITTED' "$LC" | grep -oE "name='[a-z]+-hd-lod0' found=1" | sort -u | tr '\n' ' ')
NOSLOT=$(grep -ac 'no free blerc override slot' "$LC"); NOSLOT=${NOSLOT:-0}
PID=$(pidof_app)
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/leg3.exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/leg3.exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEWCRASH=no; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEWCRASH=YES
say ""
say "===== LEG3 HARVEST ====="
say "fr3-select: ${FRSEL:-MISSING}"
say "companions spawned: $NCOMP"
say "merc-loads: ${MLOADS:-NONE}"
say "submits found=1: ${SUBM:-NONE}"
say "blerc slot exhaustion lines: $NOSLOT (0 = every companion holds a face-anim slot)"
say "pid at end: '$PID'  new native crash: $NEWCRASH"
OK=1
[[ "$FRSEL" == *ENHANCED* ]] || { say "FAIL: enhanced fr3 not selected"; OK=0; }
[ "$NCOMP" -ge 1 ] || { say "FAIL: no companion spawned"; OK=0; }
[[ "$SUBM" == *found=1* ]] || { say "FAIL: no SUBMITTED found=1"; OK=0; }
[ "$NOSLOT" -eq 0 ] || { say "FAIL: blerc slot exhausted"; OK=0; }
[ -n "$PID" ] || { say "FAIL: app died"; OK=0; }
[ "$NEWCRASH" = no ] || { say "FAIL: new native crash"; OK=0; }
[ "$OK" -eq 1 ] && say "[leg3 PASS] real intro cutscene with HD companions holding blerc slots; captures banked." \
               || say "[leg3 FAIL] see above"
exit $(( 1 - OK ))
