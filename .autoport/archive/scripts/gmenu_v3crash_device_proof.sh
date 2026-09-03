#!/usr/bin/env bash
# =====================================================================================
# Grecharged-menu-overhaul V3-CRASH — REAL DEVICE BOOT PROOF (Redmi eae4df44)
#
# The V3 build crashed NATIVELY at boot on the Redmi (dumpsys exit-info reason=5, pid
# dead <45s, before the title). Root cause (fixed at HEAD): engine adjust-sprites
# (per-frame, from boot) called menu-porthole-hidden? — a defun in the PC file
# progress-pc.gc — across the engine->PC boundary. An unbound symbol-function there is
# a fn-ptr=0 SIGILL native crash on arm64. The fix moved the porthole predicate
# ENGINE-side (progress-porthole-hidden? / progress-holo-screen? in progress.gc); the
# only remaining engine->PC call is init-game-options, the established upstream pattern.
#
# This script PROVES the fixed build boots crash-free on the real device:
#   1. install the freshly-built FULL APK (fresh libgk.so + fresh CGO pack)
#   2. deploy_verify        — libgk build==APK==device (sha chain)
#   3. boot1                — force re-extraction of the fresh CGO pack
#   4. deploy_verify_assets — device CGO/DGO BYTE-IDENTICAL to the fresh HEAD build
#   5. boot2 (OFFICIAL)     — launch, wait 150s, then:
#                               pidof non-empty (pid ALIVE at t+150s), AND
#                               dumpsys exit-info: NO NEW reason=5 since the launch.
#   6. force-stop (kill-app-after-test rule).
# Any native crash signal in logcat during boot2 is captured with forensics.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Grecharged-menu-overhaul/v3crash-device; mkdir -p "$OUT"
LOG="$OUT/proof-log.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[v3crash-device FAIL] $*"; exit 1; }

say "===== Grecharged-menu-overhaul V3-CRASH device boot proof — $(date -Is) ====="

# 0. presence + not-locked -------------------------------------------------------------
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected (adb: $($ADB devices | tr '\n' ' '))"
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "device LOCKED — needs owner unlock"; fi
say "device: $($ADB -s "$S" shell getprop ro.product.model | tr -d '\r'), serial $S"

# 1. install fresh full APK ------------------------------------------------------------
[ -f "$APK" ] || die "no APK at $APK (build first)"
say "APK: $APK ($(stat -c '%s bytes, mtime %y' "$APK"))"
$ADB -s "$S" shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
$ADB -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
$ADB -s "$S" push "$APK" "$STAGE" >/dev/null 2>&1 || die "apk push to device failed"
$ADB -s "$S" shell pm install -r -d -t -i com.android.vending "$STAGE" > "$OUT/pm-install.log" 2>&1
grep -q Success "$OUT/pm-install.log" || { cat "$OUT/pm-install.log" | tee -a "$LOG"; die "pm install failed"; }
$ADB -s "$S" shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "installed fresh APK: $(cat "$OUT/pm-install.log" | tr -d '\r')"

# 2. boot1: force re-extraction of the fresh CGO + custom packs ------------------------
# LoaderActivity re-unpacks the CGO pack AND the custom pack on launch when their
# content-derived versions differ from the on-device stamps. deploy_verify checks the
# EXTRACTED on-device state, so it must run AFTER this boot, not before (an install
# alone does not unpack — the previous ordering false-failed on the stale custom stamp).
CGO_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
CUS_MAN="android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties"
CUS_VER=$([ -f "$CUS_MAN" ] && grep '^version=' "$CUS_MAN" | cut -d= -f2 || echo "")
say "fresh pack versions: CGO=$CGO_VER custom=${CUS_VER:-<none>}"
cgo_count(){ $ADB -s "$S" shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$'; }
dev_cgo_stamp(){ $ADB -s "$S" shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r'; }
dev_cus_stamp(){ $ADB -s "$S" shell run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r'; }
extract_done(){
  [ "$(dev_cgo_stamp)" = "$CGO_VER" ] || return 1
  [ "$(cgo_count)" -ge 28 ] || return 1
  [ -z "$CUS_VER" ] || [ "$(dev_cus_stamp)" = "$CUS_VER" ] || return 1
  return 0
}
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
say "boot1 (extraction): launching $PKG/$ACT ..."
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s)-t0 )) -lt 900 ]; do extract_done && break; sleep 10; done
extract_done || die "extraction never completed in 900s (cgo-stamp=$(dev_cgo_stamp) want $CGO_VER; custom-stamp=$(dev_cus_stamp) want ${CUS_VER:-<none>}; cgo-count=$(cgo_count))"
say "boot1: extraction complete ($(cgo_count) CGO/DGO; cgo-stamp==$CGO_VER; custom-stamp==$(dev_cus_stamp))"
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3

# 3. freshness: libgk sha-chain + custom pack (now extracted) --------------------------
if bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/deploy-verify.log" 2>&1; then
  say "deploy_verify (libgk build==APK==device sha chain + custom pack landed): PASS"
  grep -E '^  ok:' "$OUT/deploy-verify.log" | sed 's/^/    /' | tee -a "$LOG" >/dev/null
else
  tail -6 "$OUT/deploy-verify.log" | tee -a "$LOG"; die "deploy_verify (libgk chain) FAILED"
fi

# 4. content freshness: device CGO/DGO byte-identical to the fresh HEAD build -----------
if bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 > "$OUT/deploy-verify-assets.log" 2>&1; then
  say "deploy_verify_assets (device GOAL byte-identical to fresh HEAD build): PASS"
  grep -E 'DEPLOY-ASSETS PASS' "$OUT/deploy-verify-assets.log" | sed 's/^/    /' | tee -a "$LOG" >/dev/null
else
  tail -8 "$OUT/deploy-verify-assets.log" | tee -a "$LOG"; die "deploy_verify_assets FAILED (device runs stale GOAL)"
fi
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3

# 5. OFFICIAL boot proof: 150s, pid alive + no NEW reason=5 ----------------------------
# Snapshot exit-info BEFORE launch so we can detect any NEW native-crash entry.
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B4 'reason=5' "$OUT/exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info BEFORE launch: newest reason=5 (native crash) entry timestamp = '${PREV_R5_TS:-none}'"

$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
CRASHLOG="$OUT/boot2-logcat.log"; : > "$CRASHLOG"
( $ADB -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=|master-mode=|abort message' >> "$CRASHLOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT

T0=$(date +%s)
say ""
say "===== boot2 OFFICIAL PROOF: launch + wait 150s ====="
say "boot2 launch host-epoch=$T0 ($(date -Is))"
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
crashed=0
while [ $(( $(date +%s)-T0 )) -lt 150 ]; do
  if grep -aqE 'Fatal signal|signal (4|6|11) \(SIG|GK-DIAG sig=(4|6|11)|abort message' "$CRASHLOG" 2>/dev/null; then crashed=1; break; fi
  sleep 5
done
ELAPSED=$(( $(date +%s)-T0 ))
sleep 1
PID=$($ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r')
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')
RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$CRASHLOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
say "boot2: elapsed=${ELAPSED}s  pidof='$PID'  render-frame=$RF  crash-sig-in-logcat=$crashed"
say "boot2 focus: $FOCUS"

# exit-info AFTER: detect a NEW reason=5 entry (timestamp newer than the pre-launch snapshot).
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B4 'reason=5' "$OUT/exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info AFTER 150s: newest reason=5 entry timestamp = '${NEW_R5_TS:-none}'"

NEW_CRASH=0
if [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ]; then NEW_CRASH=1; fi

# verdict
say ""
say "===== VERDICT ====="
OK=1
[ -n "$PID" ] || { say "FAIL: pidof empty at t+${ELAPSED}s — the process is DEAD (native crash)"; OK=0; }
[ "$NEW_CRASH" -eq 0 ] || { say "FAIL: a NEW reason=5 native-crash exit-info entry appeared at '$NEW_R5_TS' (was '$PREV_R5_TS')"; OK=0; }
[ "$crashed" -eq 0 ] || { say "FAIL: a native crash signal was seen in logcat during boot2"; OK=0; }

if [ "$OK" -eq 1 ]; then
  say "PASS: fresh V3 build BOOTS CRASH-FREE on Redmi $S."
  say "  pid ALIVE at t+${ELAPSED}s: pidof org.opengoal.gk.jak1 = $PID"
  say "  exit-info: NO new reason=5 since launch (newest reason=5 '${NEW_R5_TS:-none}' predates the boot2 launch at $(date -d @$T0 '+%Y-%m-%d %H:%M:%S'))"
  say "  render-thread advanced to frame $RF (engine live, past the adjust-sprites per-frame path that used to crash)"
else
  say "===== CRASH FORENSICS ====="
  say "--- last 40 logcat lines (boot2) ---"; tail -40 "$CRASHLOG" | tee -a "$LOG"
  say "--- exit-info AFTER (top entry) ---"; sed -n '1,30p' "$OUT/exit-info-after.txt" | tee -a "$LOG"
  # dump tombstone list for the addr2line follow-up
  $ADB -s "$S" shell ls -t /data/tombstones/ 2>/dev/null | head -3 | tee -a "$LOG" || true
fi

# 6. kill the app (standing rule)
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
kill ${LCP:-0} 2>/dev/null || true
[ "$OK" -eq 1 ] || exit 1
say ""
say "[v3crash-device PASS] boot-crash-free proof captured for the report."
