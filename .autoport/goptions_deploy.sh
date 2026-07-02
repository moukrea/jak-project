#!/usr/bin/env bash
# goptions_deploy.sh — Goptions-reorder: deploy the CONSISTENT current-source arm64
# build (28 CGO/DGO, includes the menu reorder + new defaults) alongside the unchanged
# HEAD libgk, boot crash-free, and PROVE the new graphics defaults are written to the
# settings file (load-settings commits reset-gfx defaults when pc-settings.gc is absent).
# Device eae4df44 ONLY. Real measurements only. Leaves app running on PASS.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CGO_SRC=out/jak1-arm64-full/iso
OUT=.autoport/reports/Goptions-reorder; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gopt FAIL] $*" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
[ -f "$APK" ] || die "APK missing: $APK"
[ -d "$CGO_SRC" ] || die "consistent CGO set missing: $CGO_SRC"
n=$(ls "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 CGO/DGO in $CGO_SRC, got $n"

echo "== 1. ensure device libgk == built libgk (this phase changes NO C++; reinstall only if needed) =="
BUILTSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | awk '{print $1}')
DEVSO=$(adb shell run-as $PKG sh -c 'find / -name libgk.so 2>/dev/null | head -1' | tr -d '\r')
DEVSHA=$(adb shell run-as $PKG sha256sum "$DEVSO" 2>/dev/null | awk '{print $1}' | tr -d '\r')
echo "  built libgk : $BUILTSHA"
echo "  device libgk: ${DEVSHA:-<none>} ($DEVSO)"
if [ "$BUILTSHA" != "$DEVSHA" ]; then
  echo "  -> mismatch/absent: MIUI unblock + reinstall HEAD APK (1.3GB)"
  adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  adb shell pm trim-caches 999G 2>/dev/null || true
  adb install -r -d -t -i com.android.vending "$APK" || die "apk install failed"
else
  echo "  -> device already runs the HEAD libgk; skip reinstall"
fi
echo "  installed versionCode: $(adb shell dumpsys package $PKG | grep -m1 versionCode | tr -d '\r')"

echo "== 2. push 28 consistent arm64 CGO/DGO -> files/iso_data/jak1 (sha-verified) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0
for f in "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  adb push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
  adb shell run-as $PKG cp "/data/local/tmp/$bn" "files/iso_data/jak1/$bn" || { echo "  CP-FAIL $bn"; fail=1; }
  adb shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "files/iso_data/jak1/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $bn ($want != $got)"; fail=1; }
done
[ "$fail" -eq 0 ] || die "consistent CGO push failed"
echo "  pushed + sha256-verified all 28 files"

echo "== 3. WIPE pc-settings.gc (fresh state so boot writes the NEW defaults) =="
SETF=$(adb shell run-as $PKG sh -c 'find files -name pc-settings.gc 2>/dev/null' | tr -d '\r' | head -1)
echo "  device settings path: ${SETF:-<none-yet>}"
[ -n "$SETF" ] && adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true
# also clear any stray copies
adb shell run-as $PKG sh -c 'find files -name pc-settings.gc -delete 2>/dev/null' || true

echo "== 4. boot smoke: launch + watch 130s for link-finish progress, no fatal signal, fg=jak1 =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/gopt-boot-logcat.log; : > "$LOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'link finish:|PC Settings|pc settings file|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); crash=0; logo=0
while [ $(( $(date +%s) - t0 )) -lt 130 ]; do
  if grep -aqE 'GK-DIAG sig=(11|6|4)|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then crash=1; break; fi
  grep -aqE 'link finish: logo$' "$LOG" 2>/dev/null && { logo=1; break; }
  sleep 3
done
sleep 4
FG=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
kill ${LCP:-0} 2>/dev/null || true
echo "  boot: crash=$crash reached_link_logo=$logo"
echo "  foreground: $FG"
grep -aE 'GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' "$LOG" 2>/dev/null | head -4
[ "$crash" = 1 ] && die "BOOT CRASH (fatal signal in logcat)"

echo "== 5. DEFAULTS proof: pull the boot-written pc-settings.gc, check the new graphics defaults =="
sleep 3
SETF=$(adb shell run-as $PKG sh -c 'find files -name pc-settings.gc 2>/dev/null' | tr -d '\r' | head -1)
[ -n "$SETF" ] || die "pc-settings.gc not created at boot (load-settings should have committed defaults)"
adb shell run-as $PKG cat "$SETF" > "$OUT/device-pc-settings-defaults.gc" 2>/dev/null || die "could not read $SETF"
echo "  pulled: $OUT/device-pc-settings-defaults.gc ($(wc -l < "$OUT/device-pc-settings-defaults.gc") lines)"
echo "  --- graphics-relevant keys on device (fresh defaults) ---"
grep -nE 'dynamic-render-scale\?|min-render-scale|dyn-target-fps|render-scale|fps-counter\?|vsync|msaa|aspect-state|game-size' "$OUT/device-pc-settings-defaults.gc"
echo "  --- default assertions ---"
grep -qE '\(dynamic-render-scale\? #t\)' "$OUT/device-pc-settings-defaults.gc" && echo "  OK dynamic-render-scale? = #t (ON)" || echo "  FAIL dynamic-render-scale? not #t"
grep -qE '\(min-render-scale 40' "$OUT/device-pc-settings-defaults.gc" && echo "  OK min-render-scale = 40" || echo "  FAIL min-render-scale not 40"
grep -qE '\(dyn-target-fps 60' "$OUT/device-pc-settings-defaults.gc" && echo "  OK dyn-target-fps = 60" || echo "  FAIL dyn-target-fps not 60"
echo "[gopt] deploy+boot+defaults DONE — app left RUNNING at title."
