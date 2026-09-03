#!/usr/bin/env bash
# deploy_gmatch_test.sh — deploy the Gmatch-original CANDIDATE build to the
# device and smoke-boot it, WITHOUT mutating the known-good backup (so the undo
# button is preserved until the candidate is proven).
#
# Candidate build (the sanctioned mix for this phase):
#   * libgk.so  = HEAD (app-jak1-debug.apk) — has the new-game crash fixes
#                 6a8035ae4 + 3deef6bf3 that the device's 93f639155 lacks.
#   * boot CGOs = f1c known-good set (KERNEL/GAME/ENGINE.CGO + 24 level DGOs) —
#                 the ONLY boot set that survives past frame 180.
#   * TIT.DGO   = Gndlogo-fixed arm64 (out/jak1-arm64-full/iso/TIT.DGO) — adds the
#                 village+sun-glow suppression behind the intro logo (the halo).
#
# Smoke: launch + watch for the frame-180 sparticle SIGILL. If the fixed TIT.DGO
# is NOT link-compatible with the f1c boot CGOs it SIGILLs at ~frame 180; we
# detect that (crash sig before render>=900) and AUTO-RESTORE known-good.
#
# Device serial eae4df44 ONLY. Real measurements only. Leaves the app RUNNING on
# smoke PASS so the graphics harness can drive it next.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
FIXED_TIT=out/jak1-arm64-full/iso/TIT.DGO
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[deploy FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
[ -f "$APK" ] || die "APK missing: $APK"
[ -f "$FIXED_TIT" ] || die "fixed TIT.DGO missing: $FIXED_TIT"

echo "== 1. MIUI install-unblock + install HEAD libgk APK =="
adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
adb shell pm trim-caches 999G 2>/dev/null || true
adb install -r -d -t -i com.android.vending "$APK" || die "apk install failed (space? MIUI dialog?)"
echo "  installed: $(adb shell dumpsys package $PKG | grep -m1 versionCode | tr -d '\r')"

echo "== 2. restore known-good f1c CGO set (deterministic CGO baseline) =="
bash .autoport/restore_knowngood_device.sh || die "restore_knowngood failed"

if [ "${SKIP_TIT_SWAP:-0}" = "1" ]; then
  echo "== 3. SKIP_TIT_SWAP=1 — keeping the f1c TIT.DGO (libgk-only test) =="
else
  echo "== 3. overlay the Gndlogo-fixed arm64 TIT.DGO =="
  want=$(sha256sum "$FIXED_TIT" | awk '{print $1}')
  adb push "$FIXED_TIT" /data/local/tmp/TIT.DGO >/dev/null || die "push TIT.DGO failed"
  adb shell run-as $PKG cp /data/local/tmp/TIT.DGO files/cgo/jak1/TIT.DGO || die "cp TIT.DGO failed"
  adb shell rm -f /data/local/tmp/TIT.DGO >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum files/cgo/jak1/TIT.DGO 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || die "TIT.DGO sha mismatch (want $want got $got)"
  echo "  fixed TIT.DGO in place (sha ${got:0:12}…)"
fi

echo "== 4. smoke boot: launch + watch 100s for frame-180 SIGILL vs reaching title =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/gmatch-smoke-logcat.log; : > "$LOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'A35-RENDER frame=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0; crash=0
while [ $(( $(date +%s) - t0 )) -lt 100 ]; do
  if grep -aqE 'GK-DIAG sig=(4|6|11)|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then crash=1; break; fi
  fr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); fr=${fr:-0}
  [ "$fr" -ge 900 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
kill ${LCP:-0} 2>/dev/null || true
maxfr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); maxfr=${maxfr:-0}
echo "  smoke: crash=$crash maxframe=$maxfr reached_render900=$ok"
[ "$crash" = 1 ] && die "SMOKE CRASH (frame-180 SIGILL? maxframe=$maxfr) — fixed TIT.DGO INCOMPATIBLE with f1c boot CGOs"
[ "$ok" = 1 ] || die "smoke: did not reach render>=900 in 100s (maxframe=$maxfr) — boot stalled"
echo "[deploy] SMOKE PASS: booted past frame 180 to render=$maxfr; fixed TIT.DGO is f1c-compatible."
echo "[deploy] device left RUNNING — next: bash .autoport/lib/verify_device_graphics.sh"
