#!/usr/bin/env bash
# rhud2_deploy_finish.sh — stages 5-6 of the RHUD deploy, REORDERED: the
# Gconsolidate CGO push needs LoaderActivity's .extracted_v1 marker, which only
# a first boot (v12 bundle unpack) creates. So: boot->unpack->verify assets ->
# force-stop -> CGO push -> relaunch -> attract gate.
# Precondition (already PASS): APK v12 installed, deploy_verify green.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hud-jak1; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[rhud2-finish FAIL] $*" >&2; exit 1; }

$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi

say "5a. first boot: LoaderActivity v12 re-unpack (358 files — can take minutes)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); EXTRACTED=0
while [ $(( $(date +%s) - t0 )) -lt 600 ]; do
  if $ADB -s $S shell run-as $PKG ls files/cgo/jak1/.extracted_v1 >/dev/null 2>&1; then EXTRACTED=1; break; fi
  sleep 10
done
[ "$EXTRACTED" = 1 ] || { $ADB -s $S shell run-as $PKG cat files/.asset_bundle_stamp 2>/dev/null; die "extraction marker never appeared in 600s"; }
STAMP=$($ADB -s $S shell run-as $PKG cat files/.asset_bundle_stamp 2>/dev/null | tr -d '\r')
echo "  extracted (stamp=$STAMP)"
[ "$STAMP" = "12" ] || die "asset bundle stamp is '$STAMP', expected 12"

say "5b. recharged PNGs on device"
$ADB -s $S shell run-as $PKG ls files/recharged_assets 2>/dev/null | tr -d '\r' | tee "$OUT/device-recharged-ls.txt"
NPNG=$(grep -ac png "$OUT/device-recharged-ls.txt" || true)
[ "$NPNG" -ge 11 ] || die "recharged PNGs missing on device (got $NPNG)"

say "5c. push the consistent arm64 CGO/DGO set (marker now exists)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -6 || die "CGO deploy failed"

say "6. relaunch: attract render gate + recharged loader lines"
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/rhud2-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'recharged-hud|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; echo "  attract rendering"; break; }
  sleep 3
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_attract=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not in foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach attract"
echo "  recharged loader lines:"
grep -a "recharged-hud" "$LOG" | head -13 || echo "  (none captured)"
echo "[rhud2-finish] DONE — v12 assets on device, consistent CGOs pushed, attract boots."
