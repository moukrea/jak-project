#!/usr/bin/env bash
# =====================================================================================
# Grecharged-menu-overhaul V4-CRASH — REAL DEVICE MENU-OPEN PROOF (Redmi eae4df44)
#
# The V4 build BOOTS to the title but CRASHES (SIGSEGV, fault=ee_base-4) the instant the
# owner presses START to OPEN the menu (both Honor and Redmi). Root cause (fixed at HEAD):
# *menu-drone-handle* was initialised (the-as handle 0); a 0-handle's `process` field is
# integer 0, which is TRUTHY in GOAL, so handle->process returned 0 (not #f) and the very
# next (-> 0 type) in update-and-draw-menu-projector! read ee_base-4 => SIGSEGV. Fixed to
# (the-as handle #f) + defensive nonzero guards.
#
# A boot-to-title proof is NO LONGER SUFFICIENT (V3-CRASH gate). This PRESSES START to open
# the menu and NAVIGATES OPTIONS -> GRAPHISMES, then proves the app stays ALIVE:
#   1. install fresh APK + re-extract fresh CGO pack + deploy_verify(_assets)
#   2. DELETE any stale files/gk_crash.txt (so a NEW one = a NEW crash)
#   3. boot to title (render frame advancing)
#   4. inject START (open the title menu — the exact V4-CRASH point: the drone spawns here)
#   5. navigate up x3 -> Options (Options/Secrets/Quit are the last 3 rows in BOTH save
#      states) -> X (enter OPTIONS hub) -> down -> X (enter GRAPHISMES) -> scroll rows
#   6. PROVE: pidof ALIVE after, NO crash sig in logcat, NO new reason=5 exit-info, AND
#      files/gk_crash.txt STILL ABSENT (no new SIGSEGV on menu-open/navigate).
#   7. force-stop (kill-app-after-test rule).
# Input injection: debug.opengoal.cpad_inject property (run-as/CWD-independent), tokens
# start/up/down/x/circle (android/android_input_audio.cpp apply_inject_token).
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Grecharged-menu-overhaul/v4crash-device; mkdir -p "$OUT"
LOG="$OUT/proof-log.txt"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[v4crash-device FAIL] $*"; exit 1; }

# --- input injection helpers (property channel; hold ~300ms = one press edge) ----------
# Release uses the ignored token "release" (not in apply_inject_token's switch) -> all
# buttons 0, analog neutral. Unambiguous vs an empty setprop arg. The file channel is
# cleared at test start (rm below) so only the property drives input.
setinj(){ $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1 || true; }
press(){ # press <token> — one clean press+release edge
  setinj "$1"; sleep 0.32; setinj release; sleep 0.28
  say "  inject press: $1"
}
crash_seen(){ grep -aqE 'Fatal signal|signal (4|6|11) \(SIG|GK-DIAG sig=(4|6|11)|SIGSEGV|abort message' "$CRASHLOG" 2>/dev/null; }
gkcrash_present(){ $ADB -s "$S" shell run-as $PKG sh -c 'test -f files/gk_crash.txt && echo YES || echo NO' 2>/dev/null | tr -d '\r'; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

say "===== Grecharged-menu-overhaul V4-CRASH device MENU-OPEN proof — $(date -Is) ====="

# 0. presence + not-locked -------------------------------------------------------------
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected (adb: $($ADB devices | tr '\n' ' '))"
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "device LOCKED — needs owner unlock"; fi
say "device: $($ADB -s "$S" shell getprop ro.product.model | tr -d '\r'), serial $S"

# 1. install fresh full APK ------------------------------------------------------------
[ -f "$APK" ] || die "no APK at $APK (build first: ./build.sh android-arm64 --pbr --debug)"
say "APK: $APK ($(stat -c '%s bytes, mtime %y' "$APK"))"
$ADB -s "$S" shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
$ADB -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
$ADB -s "$S" push "$APK" "$STAGE" >/dev/null 2>&1 || die "apk push failed"
$ADB -s "$S" shell pm install -r -d -t -i com.android.vending "$STAGE" > "$OUT/pm-install.log" 2>&1
grep -q Success "$OUT/pm-install.log" || { cat "$OUT/pm-install.log" | tee -a "$LOG"; die "pm install failed"; }
$ADB -s "$S" shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "installed fresh APK: $(cat "$OUT/pm-install.log" | tr -d '\r')"

# 2. boot1: force re-extraction of the fresh CGO pack ----------------------------------
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
extract_done || die "extraction never completed in 900s (cgo-stamp=$(dev_cgo_stamp) want $CGO_VER; cgo-count=$(cgo_count))"
say "boot1: extraction complete ($(cgo_count) CGO/DGO; cgo-stamp==$CGO_VER; custom-stamp==$(dev_cus_stamp))"
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3

# 3. freshness gates -------------------------------------------------------------------
if bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/deploy-verify.log" 2>&1; then
  say "deploy_verify (libgk build==APK==device sha chain): PASS"
else tail -6 "$OUT/deploy-verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; fi
if bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 > "$OUT/deploy-verify-assets.log" 2>&1; then
  say "deploy_verify_assets (device GOAL byte-identical to fresh HEAD build): PASS"
else tail -8 "$OUT/deploy-verify-assets.log" | tee -a "$LOG"; die "deploy_verify_assets FAILED (device runs stale GOAL)"; fi
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 3

# 4. DELETE stale gk_crash.txt (so a NEW one = a NEW crash) + clear the inject FILE -----
$ADB -s "$S" shell run-as $PKG rm -f files/gk_crash.txt >/dev/null 2>&1 || true
$ADB -s "$S" shell run-as $PKG rm -f files/cpad_inject >/dev/null 2>&1 || true   # only the property drives input
say "pre-test gk_crash.txt present? $(gkcrash_present)  (deleted any stale copy + inject file)"
setinj release

# 5. exit-info snapshot BEFORE ---------------------------------------------------------
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-before.txt" 2>&1
PREV_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-before.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
say "exit-info BEFORE: newest native-crash timestamp = '${PREV_R5_TS:-none}'"

# 6. boot to title + logcat watcher ----------------------------------------------------
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
CRASHLOG="$OUT/menu-logcat.log"; : > "$CRASHLOG"
( $ADB -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=|SIGSEGV|abort message|Gmenu' >> "$CRASHLOG" ) 2>/dev/null &
LCP=$!
trap '$ADB -s "$S" shell setprop debug.opengoal.cpad_inject release >/dev/null 2>&1 || true; kill ${LCP:-0} 2>/dev/null || true; $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true' EXIT

T0=$(date +%s)
say ""
say "===== boot to title ====="
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
# wait until the render thread is advancing (title reached)
got_title=0
while [ $(( $(date +%s)-T0 )) -lt 150 ]; do
  crash_seen && { say "CRASH during boot (before menu)!"; break; }
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$CRASHLOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && { got_title=1; break; }
  sleep 5
done
PID_TITLE=$(pidof_app)
say "title: render-frame=${RF:-0}  pidof='$PID_TITLE'  (got_title=$got_title)"
[ -n "$PID_TITLE" ] || die "app DIED before menu open (pidof empty at title)"
sleep 3

# 7. THE V4-CRASH POINT: press START to OPEN the menu ---------------------------------
say ""
say "===== OPEN MENU (press START) — the V4-CRASH point (drone spawns here) ====="
press start
sleep 3
say "after START: pidof='$(pidof_app)'  crash_sig=$(crash_seen && echo YES || echo no)  gk_crash=$(gkcrash_present)"
[ -n "$(pidof_app)" ] || die "app DIED on menu OPEN (the exact V4-CRASH) — pidof empty after START"
crash_seen && die "crash signal in logcat on menu OPEN"
[ "$(gkcrash_present)" = "NO" ] || { $ADB -s "$S" shell run-as $PKG cat files/gk_crash.txt 2>/dev/null | head -12 | tee -a "$LOG"; die "gk_crash.txt appeared on menu OPEN (new SIGSEGV)"; }

# 8. NAVIGATE Options -> OPTIONS hub -> GRAPHISMES -> scroll ---------------------------
say ""
say "===== navigate: down -> Options -> X (hub) -> down -> X (GRAPHISMES) -> scroll ====="
# Device has NO save -> title is *title-pc*: New Game(0)/Options(1)/Secrets/Quit/Back, so
# from the top cursor, down x1 lands on Options. (With a save it lands on Load — still a
# holo/menu screen, no crash; the crash gate holds either way.) Never press X on row 0
# (New Game / Continue) so we never leave the menu into gameplay.
press down        # New Game -> Options (row 1)
press x           # enter OPTIONS hub (settings-title, a holo screen)
sleep 2
say "in OPTIONS hub: pidof='$(pidof_app)'  gk_crash=$(gkcrash_present)  crash_sig=$(crash_seen && echo YES || echo no)"
[ -n "$(pidof_app)" ] || die "app DIED entering OPTIONS hub"
[ "$(gkcrash_present)" = "NO" ] || die "gk_crash.txt appeared entering OPTIONS hub"
press down        # JOUABILITE(0) -> GRAPHISMES(1)
press x           # enter GRAPHISMES (graphic-settings, the unified holo page)
sleep 2
say "in GRAPHISMES: pidof='$(pidof_app)'  gk_crash=$(gkcrash_present)  crash_sig=$(crash_seen && echo YES || echo no)"
# scroll the GRAPHISMES rows (exercises draw-options across many rows + holo/drone per frame)
press down; press down; press down; press down; press up; press up
sleep 2
press circle; press circle; press circle   # back out
sleep 2
say "after GRAPHISMES scroll+back: pidof='$(pidof_app)'  gk_crash=$(gkcrash_present)  crash_sig=$(crash_seen && echo YES || echo no)"

# 9. FINAL VERDICT --------------------------------------------------------------------
ELAPSED=$(( $(date +%s)-T0 ))
sleep 1
PID=$(pidof_app)
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -m1 -i mCurrentFocus | tr -d '\r')
RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$CRASHLOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
GKCRASH=$(gkcrash_present)
$ADB -s "$S" shell dumpsys activity exit-info $PKG > "$OUT/exit-info-after.txt" 2>&1
NEW_R5_TS=$(grep -B12 'reason=REASON_CRASH_NATIVE\|reason=5' "$OUT/exit-info-after.txt" | grep -oE 'timestamp=[0-9: .-]+' | head -1 | cut -d= -f2- | tr -d '\r')
NEW_CRASH=0; [ -n "$NEW_R5_TS" ] && [ "$NEW_R5_TS" != "$PREV_R5_TS" ] && NEW_CRASH=1

say ""
say "===== VERDICT ====="
say "elapsed=${ELAPSED}s  pidof='$PID'  render-frame=$RF  focus=$FOCUS"
say "gk_crash.txt after menu-open+navigate: $GKCRASH"
say "exit-info AFTER: newest native-crash timestamp = '${NEW_R5_TS:-none}'"
OK=1
[ -n "$PID" ] || { say "FAIL: pidof empty — app DIED during menu"; OK=0; }
crash_seen && { say "FAIL: native crash signal in logcat"; OK=0; }
[ "$GKCRASH" = "NO" ] || { say "FAIL: gk_crash.txt appeared (new SIGSEGV)"; $ADB -s "$S" shell run-as $PKG cat files/gk_crash.txt 2>/dev/null | head -16 | tee -a "$LOG"; OK=0; }
[ "$NEW_CRASH" -eq 0 ] || { say "FAIL: NEW reason=5 exit-info at '$NEW_R5_TS'"; OK=0; }

if [ "$OK" -eq 1 ]; then
  say ""
  say "PASS: fresh V4 build OPENS THE MENU + navigates OPTIONS/GRAPHISMES CRASH-FREE on Redmi $S."
  say "  serial=$S  pid ALIVE at t+${ELAPSED}s = $PID  (survived START + down + X[hub] + down + X[GRAPHISMES] + scroll + circle-back)"
  say "  gk_crash.txt ABSENT after menu-open+navigate (no new SIGSEGV; the ee_base-4 null-type read is gone)"
  say "  exit-info: no new native-crash entry since launch"
else
  say "===== CRASH FORENSICS ====="
  tail -40 "$CRASHLOG" | tee -a "$LOG"
  sed -n '1,30p' "$OUT/exit-info-after.txt" | tee -a "$LOG"
fi
setinj release
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
kill ${LCP:-0} 2>/dev/null || true
[ "$OK" -eq 1 ] || exit 1
say "[v4crash-device PASS] menu-open crash-free proof captured for the report."
