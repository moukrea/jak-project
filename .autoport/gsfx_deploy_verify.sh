#!/usr/bin/env bash
# gsfx_deploy_verify.sh — deploy the FIXED arm64 set (already staged in
# out/jak1-arm64-full/iso) + probe libgk to device eae4df44, boot, and capture
# the in-game SFX to confirm garbage names -> correct names (the fix landed).
# The arm64 CGOs were built with the fixed goalc (128-bit sound-name arg classing).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
INJ="/data/data/$PKG/files/cpad_inject"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gsfx-deploy FAIL] $*" >&2; exit 1; }
A(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJ'" >/dev/null 2>&1 || true; }

[ -d out/jak1-arm64-full/iso ] || die "fixed arm64 set missing (run build first)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 arm64 files, got $n"

say "1. build android libgk (probe ON) + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -5
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
[ -f "$APK" ] || die "APK missing"

say "2. install APK + restore known-good (gives .extracted_v1) + deploy_verify"
A shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
A shell pm trim-caches 999G 2>/dev/null || true
A install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore_knowngood failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "3. overlay the FIXED consistent arm64 CGO/DGO set"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -4 || die "CGO deploy failed"

say "4. boot + capture in-game SFX (warp to training, drive+spin, 90s)"
A shell setprop debug.opengoal.sfx.probe 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp 1   >/dev/null 2>&1 || true
A shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
OUTDIR=.autoport/reports/Gsfx-actions; mkdir -p "$OUTDIR"
LOG="$OUTDIR/device-AFTER-logcat.log"; OUT="$OUTDIR/device-AFTER-sfxprobe.txt"
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( "$ADB" -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 ) &
LCP=$!
cleanup(){ kill "$LCP" 2>/dev/null||true; inject ""; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  warming to title..."; for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
echo "  waiting for spawn..."; for i in $(seq 1 90); do grep -qa "F1-SPAWN" "$LOG" && { echo "  spawn ~${i}s"; break; }; sleep 1; done
echo "  waiting for training load..."; for ((i=1;i<=96;i++)); do sleep 5; grep -qaE "link finish: training|F1-SPAWN" "$LOG" && break; grep -qaE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" && { echo "  CRASH before training"; break; }; done
sleep 6
# drive forward + spin a few times to try to break a crate / collect eco
for r in 1 2 3 4 5; do
  inject "ly=40"; sleep 1.6; inject ""        # walk forward (ly<127)
  inject "circle"; sleep 1.2; inject ""        # spin attack
  inject "ly=40 lx=80"; sleep 1.2; inject ""   # forward+turn
  inject "x"; sleep 0.6; inject ""             # jump
done
sleep 4
kill "$LCP" 2>/dev/null || true

FOCUS=$(A shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
CRASH=$(grep -acE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" 2>/dev/null || echo 0)
LF=$(grep -ac "link finish: logo" "$LOG" 2>/dev/null || echo 0)
grep -a "SFX-PROBE" "$LOG" > "$OUT" 2>/dev/null || true
say "RESULTS (AFTER fix)"
echo "  focus: $FOCUS"
echo "  link_finish_logo=$LF  crash_lines=$CRASH"
echo "  total SFX-PROBE play lines: $(grep -ac 'SFX-PROBE] play' "$OUT" 2>/dev/null || echo 0)"
echo "== distinct device sound NAMES + hex (AFTER) — garbage should be GONE =="
grep -a "SFX-PROBE] play" "$OUT" 2>/dev/null | sed -E "s/.*play name=('[^']*' hex=[0-9a-f]+).*/\1/" | sort | uniq -c | sort -rn | head -40
echo "== lookup idx distribution (AFTER) — fewer -1 = names now resolve =="
grep -a "lookup idx=" "$OUT" 2>/dev/null | sed -E "s/.*lookup idx=(-?[0-9]+).*/\1/" | sort | uniq -c | sort -rn | head
echo "== any crate/orb/eco action sounds captured? =="
grep -aE "name='wcrate-break|name='icrate-break|name='scrate-break|name='dcrate-break|name='buzzer-pickup|name='cell-prize|name='.-eco-pickup|name='money" "$OUT" 2>/dev/null | head -20
echo "[gsfx-deploy] wrote $OUT and $LOG"
