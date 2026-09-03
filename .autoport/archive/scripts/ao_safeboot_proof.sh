#!/usr/bin/env bash
# ao_safeboot_proof.sh — Grecharged-ambient-occlusion DEFECT #6 safe-boot fallback proof.
#
# Proves the C++ safe-boot sentinel (commit b057c73d6) works end to end (~6 min):
#   - the game ARMS $SENTINEL when the persisted AO setting first becomes >0 in a session,
#   - it DELETES it after 60s of healthy frames or on a clean AO-off,
#   - if a session DIES within 60s of AO enable the sentinel SURVIVES, and the NEXT boot
#     logs "[recharged-ao] SAFE-BOOT" (lg::warn) + pins AO OFF for that one boot only.
#
# Sequence:
#   boot1: seed GTAO/High, arm-check, then force-stop WITHIN 60s (simulated dirty death) ->
#          sentinel must survive.
#   boot2: must SAFE-BOOT (AO forced off once) -> AOPERF mode=0, sentinel consumed within 20s.
#   boot3: sentinel gone -> AO active again (GTAO), re-arms + clears after 60s of health.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
SENTINEL="/storage/emulated/0/OpenGOAL/jak1/ao-boot-guard"
OUT=.autoport/reports/Grecharged-ambient-occlusion/safeboot; mkdir -p "$OUT"
LOGF="$OUT/proof-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
focus(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
fg_ok(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }

ALL_OK=1
fail(){ say "  CHECK FAIL: $*"; ALL_OK=0; }

# Seed disk with a persisted AO mode+quality, read back, die on mismatch. Args: MODE QUALITY.
seed_ao(){ local M="$1" Q="$2"
  $ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_sb.gc 2>/dev/null
  if ! grep -qa 'ambient-occlusion' /tmp/pcs_ao_sb.gc; then
    say "  SEED FAIL: no ambient-occlusion key on device settings"; return 1; fi
  sed -i "s/^ambient-occlusion = [0-9]*/ambient-occlusion = $M/; s/^ao-quality = [0-9]*/ao-quality = $Q/" /tmp/pcs_ao_sb.gc
  $ADB -s $S push /tmp/pcs_ao_sb.gc "$SETTINGS_DEV" >/dev/null 2>&1
  local BACK; BACK=$($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(ambient-occlusion|ao-quality) = [0-9]+" | tr '\n' ' ')
  case "$BACK" in *"ambient-occlusion = $M"*) : ;; *) say "  SEED READBACK FAIL: wanted ambient-occlusion = $M, got: $BACK"; return 1 ;; esac
  case "$BACK" in *"ao-quality = $Q"*) : ;; *) say "  SEED READBACK FAIL: wanted ao-quality = $Q, got: $BACK"; return 1 ;; esac
  say "  seeded+verified: $BACK"; return 0; }

sentinel_exists(){ $ADB -s $S shell "ls $SENTINEL" 2>/dev/null | grep -q "$SENTINEL"; }

clear_props(){
  $ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
  $ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
  $ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
  $ADB -s $S shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
  $ADB -s $S shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1; }

start_logcat(){ # $1 = logfile
  kill "$(cat /tmp/ao_sb_lc.pid 2>/dev/null)" 2>/dev/null || true
  $ADB -s $S logcat -c 2>/dev/null || true
  ( $ADB -s $S logcat -v threadtime opengoal-gk:* '*:S' > "$1" 2>/dev/null & echo $! > /tmp/ao_sb_lc.pid ); }

kill_logcat(){ kill "$(cat /tmp/ao_sb_lc.pid 2>/dev/null)" 2>/dev/null || true; }

# ---- boot 1: arm, dirty death within 60s ----------------------------------
say "== boot1: seed GTAO/High, arm the sentinel, dirty-death within 60s =="
$ADB -s $S shell am force-stop $PKG; sleep 2
seed_ao 3 2 || fail "boot1 seed"
$ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1
clear_props
start_logcat "$OUT/boot1.log"
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
# wait up to 180s for a fresh AO-enable line
t0=$(date +%s); saw=0
while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
  if grep -aqE '\[recharged-ao\] mode -> 3|AOPERF mode=3' "$OUT/boot1.log" 2>/dev/null; then saw=1; break; fi
  sleep 3
done
[ "$saw" = 1 ] && say "  boot1 AO-enable line seen ($(( $(date +%s)-t0 ))s)" || fail "boot1 no AO-enable line in 180s"
# arm-check: sentinel must exist now
if sentinel_exists; then say "  ARMED-OK (sentinel exists)"; else say "  ARMED-MISSING"; fail "boot1 sentinel not armed"; fi
# force-stop WITHIN 60s of the AO-enable line (unclean from the app's perspective)
if [ "$saw" = 1 ]; then
  el=$(( $(date +%s)-t0 ))
  if [ "$el" -lt 55 ]; then sleep $(( 5 )); fi   # ensure we're mid-window but still <60s
fi
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
say "  boot1 force-stopped (dirty, within 60s)"
kill_logcat
# sentinel must STILL exist (death within 60s -> survives)
if sentinel_exists; then say "  sentinel SURVIVES the dirty death (OK)"; else fail "boot1 sentinel deleted despite <60s death"; fi

# ---- boot 2: SAFE-BOOT once, AO off, sentinel consumed --------------------
say "== boot2: expect SAFE-BOOT (AO forced off once), sentinel consumed =="
start_logcat "$OUT/boot2.log"
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
# wait up to 120s for SAFE-BOOT + AOPERF mode=0 lines
t0=$(date +%s); sb=0; ap0=0
while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
  grep -aq "SAFE-BOOT" "$OUT/boot2.log" 2>/dev/null && sb=1
  ap0=$(grep -ac "AOPERF mode=0" "$OUT/boot2.log" 2>/dev/null); ap0=${ap0:-0}
  [ "$sb" = 1 ] && [ "$ap0" -ge 2 ] && break
  sleep 3
done
[ "$sb" = 1 ] && say "  SAFE-BOOT line present (OK)" || fail "boot2 no SAFE-BOOT line"
say "  AOPERF mode=0 count: $ap0 (need >=2)"
[ "$ap0" -ge 2 ] || fail "boot2 AOPERF mode=0 < 2 (AO not forced off)"
# after 20s the sentinel must be GONE (consumed by the safe boot)
sleep 20
if sentinel_exists; then fail "boot2 sentinel still present after 20s (not consumed)"; else say "  sentinel CONSUMED (gone after 20s) (OK)"; fi
# game alive + foreground jak1
if fg_ok; then say "  boot2 alive + foreground jak1 (OK)"; else fail "boot2 not foreground jak1: $(focus)"; fi
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
kill_logcat

# ---- boot 3: AO active again (latch was one boot only) --------------------
say "== boot3: sentinel consumed -> AO active (GTAO) again; re-arm + clear after 60s health =="
start_logcat "$OUT/boot3.log"
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
# wait for >=3 AOPERF mode=3 lines (latch was one boot only)
t0=$(date +%s); ap3=0
while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
  ap3=$(grep -ac "AOPERF mode=3" "$OUT/boot3.log" 2>/dev/null); ap3=${ap3:-0}
  [ "$ap3" -ge 3 ] && break
  sleep 3
done
say "  AOPERF mode=3 count: $ap3 (need >=3)"
[ "$ap3" -ge 3 ] || fail "boot3 AO not active again (AOPERF mode=3 < 3)"
# The C++ 60s-healthy window starts at the AO-ENABLE push (mid-boot), NOT at am start —
# wait 75s AFTER the mode=3 lines appeared so the clear deadline has provably passed.
sleep 75
if sentinel_exists; then fail "boot3 sentinel still present after 70s health (not cleared)"; else say "  sentinel CLEARED after healthy run (OK)"; fi
if fg_ok; then say "  boot3 alive + foreground jak1 (OK)"; else fail "boot3 not foreground jak1: $(focus)"; fi
kill_logcat

# ---- restore ---------------------------------------------------------------
say "== restore: AO Off / quality Medium, clear sentinel, force-stop =="
seed_ao 0 1 || fail "restore seed"
$ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1

if [ "$ALL_OK" = 1 ]; then
  say "[ao-safeboot PASS] arm within 60s, survive dirty death, SAFE-BOOT+AO-off next boot, re-active after"
  exit 0
else
  say "[ao-safeboot FAIL] one or more safe-boot checks failed"
  exit 1
fi
