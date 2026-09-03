#!/usr/bin/env bash
# deploy_gmatch_loadfix.sh — deploy the double-EE-base LOAD-repair candidate:
#   libgk.so = current source (HEAD + the classify_load / load-emulate fix in
#              gk_android_main.cpp), packaged by `assembleJak1Debug -PslimIso`.
#   boot CGOs = f1c known-good set (restore_knowngood_device.sh) — unchanged.
#   No TIT swap (the halo gate already passes at 0.0 with the f1c TIT.DGO).
#
# Smoke-boots and leaves the app RUNNING on PASS so the graphics harness can
# drive it next. Auto-restores known-good on any smoke failure.
# Device serial eae4df44 ONLY. Real measurements only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
LIBGK=build-android/lib/arm64-v8a/libgk.so
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[deploy FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
[ -f "$APK" ] || die "APK missing: $APK (build it first)"
[ -f "$LIBGK" ] || die "libgk missing: $LIBGK"

# deploy-landing guard: the packaged libgk must be NEWER than every edited source.
for SRC in android/gk_android_main.cpp android/android_gfx.cpp; do
  if [ "$SRC" -nt "$LIBGK" ]; then
    die "STALE libgk: $SRC is newer than $LIBGK — rebuild libgk before deploy"
  fi
done
echo "  libgk: $(stat -c '%y' "$LIBGK" | cut -d. -f1)  apk: $(stat -c '%y' "$APK" | cut -d. -f1)"

echo "== 1. MIUI install-unblock + install load-fix libgk APK =="
adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
adb shell pm trim-caches 999G 2>/dev/null || true
adb install -r -d -t -i com.android.vending "$APK" || die "apk install failed (space? MIUI dialog?)"
echo "  installed: $(adb shell dumpsys package $PKG | grep -m1 versionCode | tr -d '\r')"

echo "== 2. restore known-good f1c CGO set (deterministic baseline, no TIT swap) =="
bash .autoport/restore_knowngood_device.sh || die "restore_knowngood failed"

echo "== 3. smoke boot: launch + watch 100s for frame-180 SIGILL vs reaching title =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/gmatch-loadfix-smoke.log; : > "$LOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'A35-RENDER frame=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0; crash=0
while [ $(( $(date +%s) - t0 )) -lt 100 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then crash=1; break; fi
  fr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); fr=${fr:-0}
  [ "$fr" -ge 900 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
kill ${LCP:-0} 2>/dev/null || true
maxfr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); maxfr=${maxfr:-0}
echo "  smoke: crash=$crash maxframe=$maxfr reached_render900=$ok"
[ "$crash" = 1 ] && die "SMOKE CRASH (frame-180? maxframe=$maxfr)"
[ "$ok" = 1 ] || die "smoke: did not reach render>=900 in 100s (maxframe=$maxfr) — boot stalled"
echo "[deploy] SMOKE PASS: load-fix libgk booted past frame 180 to render=$maxfr."
echo "[deploy] device left RUNNING — next: bash .autoport/lib/verify_device_graphics.sh"
