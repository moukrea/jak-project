#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models5 — M3 BONUS LOOKS device proof (Redmi eae4df44).
#
# Three legs on a deploy_verify-proven fresh HEAD build, driven by the hd-look-* ints in
# settings.ini (the exact values the new menu carousells write):
#   LEG A "bonus"  (jak=2 dax=2 keira=2 samos=2): warp village1-hut, two positions
#       (Samos upper deck / Keira workshop). Expect SUBMITTED found=1 for jak2-hd + daxp-hd
#       (both positions), ysamos-hd (samos pos), keira3-hd (keira pos). The M1/M2 models and
#       jak3-hd must NOT submit — a look REPLACES, never stacks.
#   LEG B "jak3"   (jak=3 dax=1 keira=1 samos=1): Keira workshop position. Expect jak3-hd +
#       dax-hd + keira-hd (the look=1 path must still drive the M2 primaries through the new
#       code). jak-hd/jak2-hd/daxp-hd/keira3-hd/ysamos-hd must NOT submit.
#   LEG C "intro"  (bonus config): REAL intro cutscene via debug.opengoal.echo.intro=1 —
#       the face-anim (blerc) device evidence: Samos TALKS with the ysamos-hd companion
#       holding a blerc override slot; Jak is cloned with jak2-hd covering. 80s talking-scene
#       screenrecord + full-intro crash watch + [hd-flicker] BLACKOUT/GAP=0 gates carried
#       from M2 cycle-3.
#
# Settings discipline: the WHOLE settings.ini is pulled once and byte-restored in cleanup
# (app force-stopped around both operations); recharged-master?/enhanced forced #t for the
# legs (feedback_recharged_master_gates_enhanced). Warp + echo.intro props cleared in cleanup.
# Visual quality stays the owner's call — this harness banks code-level markers + captures.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models5; mkdir -p "$OUT"
LOG="$OUT/proof-bonus.log"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INI_BAK="$OUT/.settings.ini.owner-backup"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[hd5-proof FAIL] $*"; exit 1; }
setinj(){ $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 </dev/null || true; }
pulse(){ setinj "$1"; sleep "${2:-0.5}"; setinj neutral; sleep "${3:-0.6}"; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

set_ini_dev(){ # set_ini_dev <key> <value> — app MUST be stopped; edits the pulled temp copy
  # NEVER append at EOF: the ini ends inside the [music] section and an extra key there poisons
  # the parser (tail of file dropped, looks silently default — bit the x86 smoke 2026-08-05).
  # New keys go TOP LEVEL, right after the recharged-enhanced-models? line.
  local key="$1" val="$2"
  if grep -q "^$key = " "$INI_TMP"; then sed -i "s|^$key = .*|$key = $val|" "$INI_TMP"
  else sed -i "/^recharged-enhanced-models? = /a $key = $val" "$INI_TMP"
       grep -q "^$key = $val$" "$INI_TMP" || die "could not insert $key (no enhanced-models anchor in device ini?)"
  fi
}
push_ini(){ # apply INI_TMP to device + verify the keys we care about
  $ADB -s "$S" push "$INI_TMP" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings.ini"
  local now; now=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -aE '^(recharged-(master|enhanced-models)\?|hd-look-)' | tr -d '\r' | tr '\n' ';')
  say "  device settings: $now"
}
config_looks(){ # config_looks <jak> <dax> <keira> <samos>
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  cp "$INI_BAK" "$INI_TMP"
  set_ini_dev 'recharged-master?' '#t'
  set_ini_dev 'recharged-enhanced-models?' '#t'
  set_ini_dev 'hd-look-jak' "$1"; set_ini_dev 'hd-look-daxter' "$2"
  set_ini_dev 'hd-look-keira' "$3"; set_ini_dev 'hd-look-samos' "$4"
  push_ini
}

say "===== Grecharged-hd-models5 M3 bonus-looks proof — $(date -Is) ====="

# 0. presence + unlocked ----------------------------------------------------------------
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi
say "device present: $($ADB -s "$S" shell getprop ro.product.model | tr -d '\r') serial=$S"

# 1. deploy_verify at proof time ---------------------------------------------------------
bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/proof.deploy_verify.log" 2>&1 \
  || { tail -6 "$OUT/proof.deploy_verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; }
say "deploy_verify: $(tail -1 "$OUT/proof.deploy_verify.log")"

# 1b. HD pack presence: all 9 ag.go on the device external pack --------------------------
NAG=$($ADB -s "$S" shell ls /storage/emulated/0/OpenGOAL/jak1/assets/hd/ 2>/dev/null | grep -ac 'ag.go' || true)
say "device HD pack: $NAG ag.go files (need 9)"
[ "$NAG" -ge 9 ] || die "device HD pack incomplete ($NAG/9 ag.go) — push the new jak1_hd_assets.zip content first"

# 2. snapshot owner settings (WHOLE FILE) -------------------------------------------------
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" pull "$PCS_DEV" "$INI_BAK" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
say "owner settings.ini backed up ($(stat -c%s "$INI_BAK") bytes) — byte-restored at exit"
INI_TMP=$(mktemp)
$ADB -s "$S" shell run-as $PKG rm -f files/cpad_inject >/dev/null 2>&1 || true
setinj release

cleanup(){
  setinj release
  $ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.echo.intro 0 >/dev/null 2>&1 </dev/null || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  if $ADB -s "$S" push "$INI_BAK" "$PCS_DEV" >/dev/null 2>&1; then
    say "cleanup: owner settings.ini byte-restored, props cleared, app force-stopped"
  else
    say "cleanup WARNING: could not restore owner settings.ini — DO NOT leave the device like this"
  fi
  rm -f "$INI_TMP" 2>/dev/null || true
  [ "${LCP:-0}" -gt 0 ] && kill "$LCP" 2>/dev/null || true
}
trap cleanup EXIT

# 3. exit-info BEFORE ---------------------------------------------------------------------
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info BEFORE: newest native-crash ts='${PREV_R5_TS:-none}'"

# ==========================================================================================
# hut leg driver (adapted from hd4_proof_primaries.sh — positions from village1-actors.json)
# ==========================================================================================
hut_leg(){ # hut_leg <tag> <pos "X Y Z" meters>
  local TAG="$1" POS="$2"
  local LCX="$OUT/leg${TAG}.logcat.log"; : > "$LCX"
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3
  $ADB -s "$S" shell setprop debug.opengoal.level.warp 'village1-hut' >/dev/null 2>&1 </dev/null
  $ADB -s "$S" shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LCX" ) 2>/dev/null &
  LCP=$!
  say "LEG$TAG: launching warp=village1-hut pos='$POS'"
  $ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local T0=$(date +%s) WARPOK=0
  while [ $(( $(date +%s)-T0 )) -lt 240 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LCX" && { WARPOK=1; break; }
    grep -qa 'LEVEL-WARP-FAIL' "$LCX" && die "LEG$TAG: warp FAILED ($(grep -a 'LEVEL-WARP-FAIL' "$LCX" | tail -1))"
    grep -qaE 'signal (4|6|11) \(SIG' "$LCX" && die "LEG$TAG: CRASH during warp boot"
    sleep 5
  done
  [ "$WARPOK" = 1 ] || die "LEG$TAG: warp spawn never seen (t+$(( $(date +%s)-T0 ))s)"
  say "LEG$TAG: warp spawned at t+$(( $(date +%s)-T0 ))s — settling"
  sleep 12
  local FOCUS; FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
  say "LEG$TAG mCurrentFocus: $FOCUS"
  [[ "$FOCUS" == *jak1* ]] || die "LEG$TAG: game not foreground ($FOCUS)"
  $ADB -s "$S" exec-out screencap -p > "$OUT/leg${TAG}-idle.png" 2>/dev/null
  say "LEG$TAG: captured leg${TAG}-idle.png ($(stat -c%s "$OUT/leg${TAG}-idle.png") bytes)"
  $ADB -s "$S" shell rm -f /sdcard/hd5_hut.mp4 >/dev/null 2>&1
  ( $ADB -s "$S" shell screenrecord --time-limit 14 --bit-rate 12000000 /sdcard/hd5_hut.mp4 >/dev/null 2>&1 ) &
  local RECP=$!
  sleep 1; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=110" 1.2 0.8; pulse "rx=-120" 1.0 0.6; setinj neutral
  wait $RECP 2>/dev/null || true; sleep 1
  $ADB -s "$S" pull /sdcard/hd5_hut.mp4 "$OUT/leg${TAG}-pan.mp4" >/dev/null 2>&1 || say "LEG$TAG warn: no mp4"
  $ADB -s "$S" shell rm -f /sdcard/hd5_hut.mp4 >/dev/null 2>&1
  sleep 6
  kill $LCP 2>/dev/null || true
}

expect_sub(){ # expect_sub <log> <legname> <model>
  if grep -qa "SUBMITTED name='$3-lod0' found=1" "$1"; then say "OK($2): $3-lod0 SUBMITTED found=1"
  else say "FAIL($2): $3-lod0 never submitted"; OK=0; fi
}
forbid_sub(){ # forbid_sub <log> <legname> <model>
  if grep -qa "SUBMITTED name='$3-lod0' found=1" "$1"; then say "FAIL($2): forbidden $3-lod0 submitted (look did not replace)"; OK=0; fi
}

OK=1
# ==========================================================================================
# LEG A — bonus config, two hut positions
# ==========================================================================================
config_looks 2 2 2 2
hut_leg "A1-samos" "-128.70 46.20 213.47"
hut_leg "A2-keira" "-130.50 34.50 202.41"
LCA="$OUT/legA-merged.logcat.log"
cat "$OUT/legA1-samos.logcat.log" "$OUT/legA2-keira.logcat.log" > "$LCA"
say ""; say "===== LEG A HARVEST (bonus 2/2/2/2) ====="
grep -qa 'HD-MODELS fr3-select GAME: ENHANCED' "$LCA" || { say "FAIL(A): GAME not ENHANCED"; OK=0; }
expect_sub "$LCA" A jak2-hd
expect_sub "$LCA" A daxp-hd
expect_sub "$OUT/legA1-samos.logcat.log" A1 ysamos-hd
expect_sub "$OUT/legA2-keira.logcat.log" A2 keira3-hd
for m in jak-hd dax-hd keira-hd samos-hd jak3-hd; do forbid_sub "$LCA" A "$m"; done
say "LEG A spawns:"; grep -a '\[HD-COMP\] spawned' "$LCA" | head -8 | tee -a "$LOG"
NOSLOT_A=$(grep -ac 'no free blerc override slot' "$LCA" || true)
say "LEG A blerc-slot exhaustion: $NOSLOT_A"; [ "$NOSLOT_A" = 0 ] || OK=0

# ==========================================================================================
# LEG B — jak3 + look=1 regression, one hut position
# ==========================================================================================
config_looks 3 1 1 1
hut_leg "B-keira" "-130.50 34.50 202.41"
LCB="$OUT/legB-keira.logcat.log"
say ""; say "===== LEG B HARVEST (jak=3, others HD) ====="
grep -qa 'HD-MODELS fr3-select GAME: ENHANCED' "$LCB" || { say "FAIL(B): GAME not ENHANCED"; OK=0; }
expect_sub "$LCB" B jak3-hd
expect_sub "$LCB" B dax-hd
expect_sub "$LCB" B keira-hd
for m in jak-hd jak2-hd daxp-hd keira3-hd ysamos-hd; do forbid_sub "$LCB" B "$m"; done

# ==========================================================================================
# LEG C — intro cutscene, bonus config (face-anim/blerc device evidence + flicker gates)
# ==========================================================================================
config_looks 2 2 2 2
$ADB -s "$S" shell setprop debug.opengoal.level.warp '' >/dev/null 2>&1 </dev/null || true
$ADB -s "$S" shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1 </dev/null || true
$ADB -s "$S" shell setprop debug.opengoal.echo.intro 1
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LCC="$OUT/legC-intro.logcat.log"; : > "$LCC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LCC" ) 2>/dev/null &
LCP=$!
say ""; say "LEG C: launching with echo.intro=1 (real intro, in-memory new game)"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
T0=$(date +%s); WARP=0; CLONE=0
while [ $(( $(date +%s)-T0 )) -lt 420 ]; do
  [ "$WARP" = 0 ] && grep -aq 'ECHO-INTRO-WARP' "$LCC" && { WARP=1; say "echo-intro armed at t+$(( $(date +%s)-T0 ))s"; }
  grep -aq 'JAK-HD-TGT\] st=target-clone-anim' "$LCC" && { CLONE=1; break; }
  kill -0 "$LCP" 2>/dev/null || die "LEG C: logcat died"
  sleep 5
done
[ "$WARP" = 1 ] || die "LEG C: ECHO-INTRO-WARP never armed"
[ "$CLONE" = 1 ] || die "LEG C: clone never seen in 420s"
say "LEG C: cutscene running — waiting out the vortex (30s), then 80s talking-scene record"
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r' | sed 's/^ *//')
[[ "$FOCUS" == *jak1* ]] || die "LEG C: game not foreground ($FOCUS)"
sleep 30
( $ADB -s "$S" shell screenrecord --time-limit 80 /sdcard/hd5_talk.mp4 ) &
RECP=$!
for i in 1 2 3; do
  sleep 18
  $ADB -s "$S" exec-out screencap -p > "$OUT/legC-intro-$i.png" 2>/dev/null
  say "captured legC-intro-$i.png ($(stat -c%s "$OUT/legC-intro-$i.png") bytes)"
done
wait "$RECP" 2>/dev/null || true; sleep 2
$ADB -s "$S" pull /sdcard/hd5_talk.mp4 "$OUT/legC-talk.mp4" >/dev/null 2>&1 \
  && $ADB -s "$S" shell rm -f /sdcard/hd5_talk.mp4 >/dev/null 2>&1 \
  && say "recorded legC-talk.mp4 ($(stat -c%s "$OUT/legC-talk.mp4") bytes)" \
  || say "WARN: talk mp4 pull failed"
INTRO_CAP=${INTRO_CAP:-420}; FULLOK=alive; TF0=$(date +%s)
say "LEG C: full-intro crash watch (up to ${INTRO_CAP}s more)"
while [ $(( $(date +%s)-TF0 )) -lt "$INTRO_CAP" ]; do
  P=$(pidof_app); [ -z "$P" ] && { FULLOK=died; break; }
  sleep 10
done
if [ "$FULLOK" = died ]; then
  say "LEG C: APP DIED during full-intro watch — forensics"
  $ADB -s "$S" shell run-as $PKG cat files/gk_crash.txt > "$OUT/legC-gk_crash.txt" 2>&1 || true
  OK=0
else
  say "LEG C: app ALIVE through the full intro"
  $ADB -s "$S" exec-out screencap -p > "$OUT/legC-intro-end.png" 2>/dev/null || true
fi
kill $LCP 2>/dev/null || true
say ""; say "===== LEG C HARVEST ====="
grep -qa 'HD-MODELS fr3-select GAME: ENHANCED' "$LCC" || { say "FAIL(C): GAME not ENHANCED"; OK=0; }
expect_sub "$LCC" C jak2-hd
expect_sub "$LCC" C daxp-hd
expect_sub "$LCC" C ysamos-hd
for m in jak-hd dax-hd samos-hd jak3-hd; do forbid_sub "$LCC" C "$m"; done
NOSLOT_C=$(grep -ac 'no free blerc override slot' "$LCC" || true)
FLK_BLACK=$(grep -ac '\[hd-flicker\] BLACKOUT' "$LCC" || true)
FLK_GAP=$(grep -ac '\[hd-flicker\] GAP' "$LCC" || true)
FLK_HB=$(grep -a '\[hd-flicker\] calls=' "$LCC" | tail -1 | tr -d '\r')
say "LEG C blerc-slot exhaustion: $NOSLOT_C (0 = every companion holds a face-anim slot)"
say "LEG C flicker: BLACKOUT=$FLK_BLACK GAP=$FLK_GAP heartbeat: ${FLK_HB:-NONE}"
[ "$NOSLOT_C" = 0 ] || OK=0
[ "$FLK_BLACK" = 0 ] || { say "FAIL(C): flicker BLACKOUT"; OK=0; }
[ "$FLK_GAP" = 0 ] || { say "FAIL(C): flicker GAP"; OK=0; }
[ -n "$FLK_HB" ] || { say "FAIL(C): no flicker heartbeat"; OK=0; }

# ==========================================================================================
# GLOBAL: crash check
# ==========================================================================================
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEWCRASH=no; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEWCRASH=YES
say ""; say "new native crash during proof: $NEWCRASH (ts='${NEW_R5_TS:-none}')"
[ "$NEWCRASH" = no ] || { say "FAIL: new native crash"; OK=0; }
[ "$OK" -eq 1 ] && say "[hd5-proof PASS] all 5 bonus looks device-proven (visible+animated markers), look-matrix respected, no crash — captures banked for the owner." \
               || say "[hd5-proof FAIL] see above"
exit $(( 1 - OK ))
