#!/usr/bin/env bash
# gjak2polish_deploy.sh — Gjak2-polish deploy: fresh arm64 libgk (items 1 mips2c
# method-17 + 5 GlowRenderer) via a SLIM APK, plus the fresh consistent arm64
# jak2 CGO/DGO set (items 2 aspect + 3 menu + 4 fps) pushed to files/cgo/jak2.
# The device already has the full jak2 bundle extracted (.extracted_v1), so the slim
# APK only delivers libgk and the push overrides the CGOs (no 1.8GB re-extract).
# deploy_verify (libgk build==device) + deploy_verify_assets (CGO md5 match) gate it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak2; ACT=org.opengoal.gk.LoaderActivity
SRC=out/jak2-arm64-full/iso
SO=build-android/lib/arm64-v8a/libgk.so
APK=android/app/build/outputs/apk/jak2/debug/app-jak2-debug.apk
OUT=.autoport/reports/Gjak2-polish/evidence; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gj2polish-deploy FAIL] $*" >&2; exit 1; }

[ -f "$SO" ] || die "no arm64 libgk at $SO — build it first (cmake --build build-android --target gk)"
n=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l); [ "$n" -ge 150 ] || die "consistent CGO set short ($n) at $SRC"
$ADB -s $S get-state >/dev/null 2>&1 || die "device $S not attached"

say "0. device wake + not-locked"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true
$ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
# Real extraction marker read by LoaderActivity.java:444 (.asset_bundle_stamp_jak2, content "11").
$ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp_jak2 >/dev/null 2>&1 \
  || die "jak2 asset bundle NOT extracted on device (.asset_bundle_stamp_jak2 missing) — need a FULL APK install first, not slim"

say "1. build SLIM jak2 APK (fresh libgk, no 1.8GB bundle)"
BUILT_SHA=$(sha256sum "$SO" | cut -d' ' -f1); echo "  built libgk sha: $BUILT_SHA"
( cd android && ./gradlew assembleJak2Debug -PslimIso=true 2>&1 | tail -6 ) || die "gradle slim assemble failed"
[ -f "$APK" ] || die "no APK at $APK after assemble"
APK_SHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "  apk libgk sha:  $APK_SHA"
[ "$BUILT_SHA" = "$APK_SHA" ] || die "APK libgk sha != freshly built libgk (gradle didn't pick up build-android) — run cmake --build build-android --target gk then retry"

say "2. MIUI install-unblock + install slim APK (-r update, keeps files/)"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
$ADB -s $S shell pm list packages | grep -q "$PKG" || die "jak2 not installed"

say "3. push $n fresh consistent arm64 CGO/DGO -> files/cgo/jak2 (sha256-verified)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp_jak2 >/dev/null 2>&1 \
  || die "asset bundle stamp gone after install (re-extract triggered) — CGO push would be clobbered"
fail=0; cnt=0
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
  $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$bn" "files/cgo/jak2/$bn" || { echo "  CP-FAIL $bn"; fail=1; }
  $ADB -s $S shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/cgo/jak2/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] && cnt=$((cnt+1)) || { echo "  VERIFY-FAIL $bn want=$want got=$got"; fail=1; }
done
[ "$fail" -eq 0 ] || die "one or more CGO/DGO failed to push/verify ($cnt/$n ok)"
echo "  pushed + sha256-verified all $cnt/$n files; asset bundle stamp kept"

# Gjak2-polish: also push the language TEXT banks. The arm64 iso stage holds only
# CGO/DGO; the menu labels (#x1333 ADVANCED SETTINGS, #x1365 FPS COUNTER) live in the
# *.TXT banks, which are platform-independent and come from the x86 iso (out/jak2/iso).
# Without this the menu ORDER updates but the LABELS stay stale ("PS2 Options" / "UNKNOWN ID").
TSRC=out/jak2/iso; tfail=0; tcnt=0; tn=0
for f in "$TSRC"/*COMMON.TXT "$TSRC"/*SUBTI2.TXT; do
  [ -f "$f" ] || continue
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}'); tn=$((tn+1))
  $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  TXT-PUSH-FAIL $bn"; tfail=1; continue; }
  $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$bn" "files/cgo/jak2/$bn" || { echo "  TXT-CP-FAIL $bn"; tfail=1; }
  $ADB -s $S shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/cgo/jak2/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] && tcnt=$((tcnt+1)) || { echo "  TXT-VERIFY-FAIL $bn"; tfail=1; }
done
[ "$tfail" -eq 0 ] || die "one or more text banks failed to push/verify ($tcnt/$tn ok)"
echo "  pushed + sha256-verified $tcnt/$tn text banks (menu labels)"

say "4. boot sanity (method 17 must NOT crash at 0x1fc2864; reach jak2 focus)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell setprop debug.opengoal.jak2.noop_names '""' >/dev/null 2>&1 || true
$ADB -s $S shell setprop debug.opengoal.jak2.enable_names '""' >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/deploy-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' >> "$LOG" 2>&1 ) &
LP=$!; trap 'kill ${LP:-0} 2>/dev/null || true; $ADB -s $S shell svc power stayon false >/dev/null 2>&1 || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); crash=0
while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
  if grep -aqE 'GK-DIAG sig=(11|6|4)|Fatal signal (11|6|4)|0x1fc2864' "$LOG" 2>/dev/null; then crash=1; break; fi
  sleep 3
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
PID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
echo "  crash=$crash pid=[$PID] focus=$FOCUS"
[ "$crash" = 1 ] && die "BOOT CRASH (method-17? check $LOG for 0x1fc2864)"
case "$FOCUS" in *org.opengoal.gk.jak2*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ -n "$PID" ] || die "app not running after boot"
echo "  boot clean: jak2 foreground, pid=$PID, no crash"

say "5. deploy_verify (libgk build==device) + deploy_verify_assets (final CGO md5, POST-boot)"
# Runs AFTER the boot launch: if the slim install/launch had re-extracted and clobbered the
# CGO push, deploy_verify_assets FAILS here — so a PASS proves the running device state.
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
bash .autoport/lib/deploy_verify.sh "$S" jak2 2>&1 | tail -4 || die "deploy_verify (libgk) FAILED"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak2 2>&1 | tail -4 || die "deploy_verify_assets FAILED (boot re-extraction clobbered the CGO push?)"
echo "[gj2polish-deploy] DONE — fresh libgk + CGOs on device (verified POST-boot), boots clean, jak2 focus."
