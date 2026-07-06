#!/usr/bin/env bash
# jak2_deploy_boot.sh — Gjak2-boot. Install app-jak2-debug.apk on the device,
# let LoaderActivity unpack the 1.55GB jak2 bundle, boot jak2, and capture the
# boot/link milestone + foreground + render + crash-window evidence.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
APK=android/app/build/outputs/apk/jak2/debug/app-jak2-debug.apk
OUT=.autoport/reports/Gjak2-boot; mkdir -p "$OUT"
LOG="$OUT/jak2-device-boot-logcat.log"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[jak2-boot FAIL] $*" >&2; exit 1; }

[ -f "$APK" ] || die "no APK at $APK"

say "0. device wake + not-locked"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi

say "1. MIUI install-unblock + install jak2 APK (1.65GB, may take a few min)"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
$ADB -s $S shell pm list packages | grep -q "$PKG" || die "jak2 package not installed"
echo "  installed: $PKG"

say "2. deploy_verify (build==APK==device libgk) for jak2"
SO_REL=lib/arm64-v8a/libgk.so
BUILT_SHA=$(sha256sum build-android/$SO_REL | cut -d' ' -f1)
DEV_APK_PATH=$($ADB -s $S shell pm path $PKG 2>/dev/null | sed 's/package://; s/\r//' | head -1)
echo "  device apk: $DEV_APK_PATH"
TMPD=$(mktemp -d)
$ADB -s $S pull "$DEV_APK_PATH" "$TMPD/dev.apk" >/dev/null 2>&1 || true
if [ -f "$TMPD/dev.apk" ]; then
  DEV_SHA=$(unzip -p "$TMPD/dev.apk" "$SO_REL" 2>/dev/null | sha256sum | cut -d' ' -f1)
  echo "  built libgk sha: $BUILT_SHA"
  echo "  device libgk sha: $DEV_SHA"
  [ "$BUILT_SHA" = "$DEV_SHA" ] && echo "  DEPLOY_VERIFY OK (build==device libgk)" || echo "  DEPLOY_VERIFY WARN: mismatch"
fi
rm -rf "$TMPD"

say "3. launch jak2 (LoaderActivity unpacks 1.55GB bundle first — patient)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
: > "$LOG"
# route the app's stdout/stderr + native logs
( $ADB -s $S logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' \
    >> "$LOG" 2>&1 ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true; $ADB -s $S shell svc power stayon false >/dev/null 2>&1 || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

say "4. watch for jak2 boot milestone / render / crash (up to 8 min incl unpack)"
t0=$(date +%s)
milestone=0; crash=0; unpacked=0
while [ $(( $(date +%s) - t0 )) -lt 480 ]; do
  if grep -aqE 'Fatal signal|signal (11|6|4|7) \(SIG|GK-DIAG sig=(11|6|4|7)' "$LOG" 2>/dev/null; then crash=1; echo "  CRASH marker seen"; fi
  grep -aqiE 'selected game=jak2|unpack.*complete|iso_data/jak2' "$LOG" 2>/dev/null && { [ "$unpacked" = 0 ] && echo "  [t=$(( $(date +%s)-t0 ))s] app started / unpack progressing"; unpacked=1; }
  if grep -aqiE 'kernel: machine started|link finish|InitIOP OK|jak2::InitMachine|master-mode' "$LOG" 2>/dev/null; then
    milestone=1; echo "  [t=$(( $(date +%s)-t0 ))s] BOOT MILESTONE marker seen"; break
  fi
  sleep 5
done

say "5. evidence snapshot"
sleep 5
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
PID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
$ADB -s $S exec-out screencap -p > "$OUT/jak2-device-frame.png" 2>/dev/null || true
FRAME_SZ=$(stat -c %s "$OUT/jak2-device-frame.png" 2>/dev/null || echo 0)
echo "  focus: $FOCUS"
echo "  app pid: ${PID:-<none>}"
echo "  screencap bytes: $FRAME_SZ"
echo "  boot milestone lines:"
grep -aiE 'selected game=jak2|jak2::InitMachine|InitIOP OK|link finish|kernel: machine started|master-mode' "$LOG" 2>/dev/null | tail -12 | sed 's/^/    /'
echo "  crash lines (if any):"
grep -aiE 'Fatal signal|signal (11|6|4|7) \(SIG|GK-DIAG sig=' "$LOG" 2>/dev/null | tail -5 | sed 's/^/    /' || echo "    (none)"
echo
echo "  RESULT: milestone=$milestone crash=$crash focus_ok=$(case "$FOCUS" in *org.opengoal.gk.jak2*) echo yes;; *) echo no;; esac) pid=${PID:-none}"
echo "[jak2-boot] log: $LOG  frame: $OUT/jak2-device-frame.png"
