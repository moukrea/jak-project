#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models4 — M2 PRIMARIES device proof (Redmi eae4df44).
#
# Two legs on the deploy_verify-proven fresh HEAD build:
#   LEG 1 "boot": plain LoaderActivity boot -> ND logo -> title. Proves the M4 per-actor
#     coverage carry-over: the logo/title Jak actor (eichar-lod0 mgeo, NOT *target*) is
#     either covered by its own companion (HD visible) or keeps its stock draw — never
#     suppressed into invisibility (the M1 defect). Screenrecord of the whole boot.
#   LEG 2 "hut": warp continue 'village1-hut' -> Samos's hut = ALL FOUR primaries in one
#     scene (Jak + Daxter-on-shoulder from GAME.fr3, Keira + Samos from village1.fr3).
#     Harvest per-character: [HD-COMP] spawned drv=..., HD-MODELS merc-load <char>-hd-lod0,
#     [hd-render] SUBMITTED name='<char>-hd-lod0' found=1, [JAK-HD] bone3 follow lines,
#     fr3-select ENHANCED for GAME + village1. Screenrecord with camera pan + screencaps.
#
# Settings discipline (feedback_recharged_master_gates_enhanced): recharged-master? #f
# silently forces STOCK even with enhanced #t — set BOTH #t for the run, assert the
# fr3-select line per level, and restore the owner's EXACT pre-run values afterwards.
# Warp props are debug properties that persist until reboot — cleared in cleanup so the
# owner's next boot does not warp.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
LOG="$OUT/proof-primaries.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[proof FAIL] $*"; exit 1; }
setinj(){ $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 </dev/null || true; }
pulse(){ setinj "$1"; sleep "${2:-0.5}"; setinj neutral; sleep "${3:-0.6}"; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

get_key(){ $ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a "^$1 " | tr -d '\r'; }
set_key(){ # set_key <key-regex-safe> '#t'|'#f'  (app MUST be stopped)
  local key="$1" want="$2" tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  grep -q "^$key " "$tmp" || die "no '$key' key in pc-settings"
  sed -i "s/^$key = #[tf]/$key = $want/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push pc-settings"
  rm -f "$tmp"
  local now; now=$(get_key "$key")
  say "  pc-settings: '$now' (wanted $want)"
  [[ "$now" == *"$want"* ]] || die "$key write did not stick"
}

say "===== Grecharged-hd-models4 M2 primaries proof — $(date -Is) ====="

# 0. presence + unlocked --------------------------------------------------------------
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi
say "device present: $($ADB -s "$S" shell getprop ro.product.model | tr -d '\r') serial=$S"

# 1. deploy_verify at proof time -------------------------------------------------------
bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/proof.deploy_verify.log" 2>&1 \
  || { tail -6 "$OUT/proof.deploy_verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; }
say "deploy_verify: $(tail -1 "$OUT/proof.deploy_verify.log")"

# 2. snapshot owner values, set master+enhanced ON (app stopped) -----------------------
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_MASTER=$(get_key 'recharged-master?'          | grep -q '#t' && echo '#t' || echo '#f')
ORIG_ENH=$(   get_key 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
say "owner pre-run: recharged-master?=$ORIG_MASTER enhanced-models?=$ORIG_ENH (both restored after)"
set_key 'recharged-master?' '#t'
set_key 'recharged-enhanced-models?' '#t'
$ADB -s "$S" shell run-as $PKG rm -f files/cpad_inject >/dev/null 2>&1 || true
setinj release

cleanup(){
  setinj release
  $ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_key 'recharged-master?' "$ORIG_MASTER" && set_key 'recharged-enhanced-models?' "$ORIG_ENH" \
    && say "cleanup: owner settings restored (master=$ORIG_MASTER enhanced=$ORIG_ENH), warp props cleared, app force-stopped" \
    || say "cleanup WARNING: could not restore owner settings — DO NOT leave the device like this"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

# 3. exit-info BEFORE ------------------------------------------------------------------
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info BEFORE: newest native-crash ts='${PREV_R5_TS:-none}'"

# ======================================================================================
# LEG 1 — plain boot: logo/title per-actor coverage
# ======================================================================================
$ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
$ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC1="$OUT/leg1-boot.logcat.log"; : > "$LC1"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC1" ) 2>/dev/null &
LCP=$!
say "LEG1: launching $PKG/$ACT (plain boot, screenrecording the logo)"
$ADB -s "$S" shell rm -f /sdcard/hd4_boot.mp4 >/dev/null 2>&1
( $ADB -s "$S" shell screenrecord --time-limit 45 --bit-rate 8000000 /sdcard/hd4_boot.mp4 >/dev/null 2>&1 ) &
RECP=$!
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
T0=$(date +%s); RF=0
while [ $(( $(date +%s)-T0 )) -lt 180 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 900 ] && break; sleep 5
done
[ "$RF" -gt 600 ] || die "LEG1: title never reached (render-frame=$RF)"
say "LEG1: title reached render-frame=$RF pid=$(pidof_app)"
sleep 4
$ADB -s "$S" exec-out screencap -p > "$OUT/leg1-title.png" 2>/dev/null
say "LEG1: captured leg1-title.png ($(stat -c%s "$OUT/leg1-title.png") bytes)"
wait $RECP 2>/dev/null || true; sleep 1
$ADB -s "$S" pull /sdcard/hd4_boot.mp4 "$OUT/leg1-boot.mp4" >/dev/null 2>&1 || say "LEG1 warn: no boot mp4"
$ADB -s "$S" shell rm -f /sdcard/hd4_boot.mp4 >/dev/null 2>&1
# coverage evidence: companions spawned for boot-scene actors and/or zero unreplaced suppression
L1_SPAWN=$(grep -a '\[HD-COMP\] spawned' "$LC1" | head -5)
L1_SUPP=$(grep -ac 'hd-render.*suppress pid=' "$LC1" || true)
L1_SUBM=$(grep -ac 'hd-render.*SUBMITTED.*found=1' "$LC1" || true)
say "LEG1 coverage: spawn-lines: $(grep -ac '\[HD-COMP\] spawned' "$LC1" || true), suppress-lines=$L1_SUPP, hd-submits(found=1)=$L1_SUBM"
[ -n "$L1_SPAWN" ] && say "$L1_SPAWN"
kill $LCP 2>/dev/null || true

# ======================================================================================
# LEG 2 — warp village1-hut, two positions (Samos upper deck y=46.2 / Keira lower
# workshop y=34.2 — 12 m of vertical separation, one camera point cannot frame both;
# positions from decompiler_out/jak1/entities/village1-actors.json, trans already meters).
# ======================================================================================
hut_leg(){ # hut_leg <tag> <pos "X Y Z" meters>
  local TAG="$1" POS="$2"
  local LCX="$OUT/leg2${TAG}.logcat.log"; : > "$LCX"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3
  $ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LCX" ) 2>/dev/null &
  LCP=$!
  say "LEG2$TAG: launching warp=village1-hut pos='$POS'"
  $ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local T0=$(date +%s) WARPOK=0
  while [ $(( $(date +%s)-T0 )) -lt 240 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LCX" && { WARPOK=1; break; }
    grep -qa 'LEVEL-WARP-FAIL' "$LCX" && die "LEG2$TAG: warp FAILED ($(grep -a 'LEVEL-WARP-FAIL' "$LCX" | tail -1))"
    grep -qaE 'signal (4|6|11) \(SIG' "$LCX" && die "LEG2$TAG: CRASH during warp boot"
    sleep 5
  done
  [ "$WARPOK" = 1 ] || die "LEG2$TAG: warp spawn never seen (t+$(( $(date +%s)-T0 ))s)"
  say "LEG2$TAG: warp spawned at t+$(( $(date +%s)-T0 ))s — settling"
  sleep 12   # companion spawns + first submissions + bone3 frame-60 dump
  local FOCUS; FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
  say "LEG2$TAG mCurrentFocus: $FOCUS"
  [[ "$FOCUS" == *jak1* ]] || die "LEG2$TAG: game not foreground ($FOCUS)"
  $ADB -s "$S" exec-out screencap -p > "$OUT/leg2${TAG}-idle.png" 2>/dev/null
  say "LEG2$TAG: captured leg2${TAG}-idle.png ($(stat -c%s "$OUT/leg2${TAG}-idle.png") bytes)"
  # screenrecord with a slow camera yaw sweep so the nearby NPC crosses the frustum
  $ADB -s "$S" shell rm -f /sdcard/hd4_hut.mp4 >/dev/null 2>&1
  ( $ADB -s "$S" shell screenrecord --time-limit 14 --bit-rate 12000000 /sdcard/hd4_hut.mp4 >/dev/null 2>&1 ) &
  local RECP=$!
  sleep 1; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=-120" 1.0 0.6; setinj neutral
  wait $RECP 2>/dev/null || true; sleep 1
  $ADB -s "$S" pull /sdcard/hd4_hut.mp4 "$OUT/leg2${TAG}-pan.mp4" >/dev/null 2>&1 || say "LEG2$TAG warn: no mp4"
  $ADB -s "$S" shell rm -f /sdcard/hd4_hut.mp4 >/dev/null 2>&1
  sleep 6    # a few more submits after the pan
  kill $LCP 2>/dev/null || true
}
hut_leg "a-samos" "-128.70 46.20 213.47"
hut_leg "b-keira" "-130.50 34.50 202.41"
# merged view for the harvest greps
LC2="$OUT/leg2-merged.logcat.log"
cat "$OUT/leg2a-samos.logcat.log" "$OUT/leg2b-keira.logcat.log" > "$LC2"

# ======================================================================================
# HARVEST
# ======================================================================================
sleep 2
PID=$(pidof_app)
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEWCRASH=no; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEWCRASH=YES
say ""
say "===== HARVEST ====="
OK=1
for lv in GAME village1; do
  FSEL=$(grep -a -m1 "fr3-select ${lv}: ENHANCED" "$LC2")
  say "fr3-select $lv: ${FSEL:-MISSING}"
  [ -n "$FSEL" ] || { say "FAIL: $lv not loaded from ENHANCED external fr3"; OK=0; }
done
for c in jak dax keira samos; do
  SP=$(grep -a '\[HD-COMP\] spawned' "$LC2" | grep -a -m1 -iE "drv=.*(${c}|eichar|sidekick|assistant|sage)" )
  ML=$(grep -a -m1 "merc-load .*${c}-hd-lod0" "$LC2")
  SB=$(grep -a -m1 "SUBMITTED name='${c}-hd-lod0' found=1" "$LC2")
  say "[$c] merc-load: ${ML:-MISSING}"
  say "[$c] submit:    ${SB:-MISSING}"
  [ -n "$SB" ] || { say "FAIL: ${c}-hd-lod0 never submitted with model found"; OK=0; }
done
say "spawn lines (leg2):"; grep -a '\[HD-COMP\] spawned' "$LC2" | head -8 | tee -a "$LOG"
say "suppress lines (leg2, per-actor):"; grep -a 'hd-render.*suppress pid=' "$LC2" | head -6 | tee -a "$LOG"
NB=$(grep -ac 'bone3 ' "$LC2" || true)
say "bone3 follow dump lines (leg2): $NB"
say "asset-missing lines: $(grep -ac 'asset missing' "$LC2" || true)"
say "pid at end: '$PID'  new native crash: $NEWCRASH (ts='${NEW_R5_TS:-none}')"
[ -n "$PID" ] || { say "FAIL: app died"; OK=0; }
[ "$NEWCRASH" = no ] || { say "FAIL: new native crash during proof"; OK=0; }
[ "$OK" -eq 1 ] && say "[proof PASS] M2 primaries device-proven on $S — captures + logcat banked." \
               || say "[proof FAIL] see above"
exit $(( 1 - OK ))
