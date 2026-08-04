#!/usr/bin/env bash
# hd4_deploy_fresh.sh — install the freshly built jak1 APK on the Honor, run the
# LoaderActivity extraction once (MainActivity bypasses pack extraction — the post-
# install boot MUST go through LoaderActivity), then PROVE the new GAME.CGO landed.
#
# Why the extra CGO proof: deploy_verify pairs device CGO <-> libgk by the ogflags
# MARKER only. A rebuild with the SAME flag set (this one: hd-models,pbr) produces the
# same marker, so deploy_verify would PASS with a STALE device GAME.CGO. md5 the device
# file against the built arm64 stage — the marker cannot catch this class, bytes can.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-hd-models4
LOG="$OUT/deploy_fresh.log"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[deploy FAIL] $*"; exit 1; }

APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "no APK"
say "APK: $APK ($(stat -c%s "$APK") bytes, $(date -d @$(stat -c%Y "$APK") +%H:%M:%S))"
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
say "installing (this can take ~2min)..."
$ADB -s "$S" install -r -d "$APK" >> "$LOG" 2>&1 || die "adb install failed (see $LOG)"
say "install ok"

# LoaderActivity boot -> extraction (CGO content changed => bundle re-extraction) -> title
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/deploy_fresh.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
trap 'kill $LCP 2>/dev/null || true' EXIT
$ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
T0=$(date +%s); RF=0
while [ $(( $(date +%s)-T0 )) -lt 600 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && break; sleep 8
done
[ "$RF" -gt 600 ] || die "title never reached after install (render-frame=$RF at t+$(( $(date +%s)-T0 ))s) — extraction stuck?"
say "post-install boot ok: render-frame=$RF at t+$(( $(date +%s)-T0 ))s"
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2

# CGO landing proof (byte-level, marker-immune)
LOCAL_CGO=$(md5sum out/jak1-arm64-full/iso/GAME.CGO | cut -d' ' -f1)
DEV_CGO=$($ADB -s "$S" shell run-as $PKG md5sum files/cgo/jak1/GAME.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
say "GAME.CGO md5: built=$LOCAL_CGO device=$DEV_CGO"
[ "$LOCAL_CGO" = "$DEV_CGO" ] || die "device GAME.CGO is STALE (extraction did not refresh it)"

bash .autoport/lib/deploy_verify.sh "$S" jak1 >> "$LOG" 2>&1 || { tail -4 "$LOG"; die "deploy_verify FAILED"; }
say "$(tail -1 "$LOG")"
say "[deploy PASS] device runs the fresh build incl. the new GAME.CGO"
