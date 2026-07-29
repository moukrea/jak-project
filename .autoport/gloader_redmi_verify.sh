#!/usr/bin/env bash
# Grecharged-loader-packfix — install the FIXED build on the Redmi and prove, on
# the device, that it boots through the REAL entry point, unpacks both packs, and
# survives. The owner unplugged his Honor at 07:36 on 2026-07-29 (where this fix
# was first proven) and re-attached the Redmi; this re-establishes the same proof
# on the device that is actually present.
#
# Launch MUST go through LoaderActivity: MainActivity bypasses it, and
# LoaderActivity is the sole writer of the pack stamps — a MainActivity launch
# unpacks NOTHING and then deploy_verify's custom-pack check fails for the wrong
# reason. (`cmd package resolve-activity` confirms LoaderActivity is the entry.)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SER="${1:-eae4df44}"
PKG="org.opengoal.gk.jak1"
APK="${2:-.autoport/dist/app-jak1-NORMAL-recharged.apk}"
OUT=".autoport/reports/Grecharged-loader-packfix/device-redmi"
mkdir -p "$OUT"

a() { "$ADB" -s "$SER" "$@"; }
ra() { "$ADB" -s "$SER" exec-out run-as "$PKG" "$@"; }

# The USB link to this phone flaps (kernel error -71 on 2026-07-29). Every check
# below is only meaningful while the device is actually attached, so guard them:
# a vanished phone must abort LOUDLY, never read as "absent file" / "clean run".
require_device() {
  for _i in $(seq 1 30); do
    if "$ADB" devices | grep -qE "^${SER}[[:space:]]+device$"; then return 0; fi
    [ "$_i" = 1 ] && { echo "   ... device $SER off the link, waiting/rebinding"; "$ADB" kill-server >/dev/null 2>&1; "$ADB" start-server >/dev/null 2>&1; }
    sleep 5
  done
  echo "FATAL: device $SER never came back — results below would be meaningless. Aborting." >&2
  exit 2
}

echo "===== Grecharged-loader-packfix — Redmi verify ====="
echo "device : $SER   apk: $APK ($(stat -c %s "$APK") bytes, sha256 $(sha256sum "$APK" | cut -c1-16))"
echo "libgk  : $(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)"

echo
echo "-- 1. install (push + pm install: MIUI's AdbInstallActivity silently cancels"
echo "      'adb install' whenever the keyguard is up) --"
require_device
a shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1
a shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1
a shell settings put global package_verifier_enable 0 >/dev/null 2>&1
a shell settings put global adb_install_need_confirm 0 >/dev/null 2>&1
a push "$APK" /data/local/tmp/gloader.apk 2>&1 | tail -1
a shell pm install -r -i com.android.vending /data/local/tmp/gloader.apk 2>&1 | tail -2
a shell rm -f /data/local/tmp/gloader.apk

DP=$(a shell pm path "$PKG" | sed 's/package://' | tr -d '\r' | head -1)
echo "   device apk : $DP"
echo "   device size: $(a shell stat -c %s "$DP" | tr -d '\r')  (expect $(stat -c %s "$APK"))"

echo
echo "-- 2. clear crash record, launch through the RESOLVED entry point --"
require_device
a shell am force-stop "$PKG"
ra rm -f files/gk_crash.txt >/dev/null 2>&1
COMP=$(a shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')
echo "   entry point: $COMP"
T0=$(a shell date +%s | tr -d '\r')
a shell logcat -c >/dev/null 2>&1
a shell am start -n "$COMP" 2>&1 | head -2

echo
echo "-- 3. liveness + extraction --"
DIED=0; LAST=0
for i in $(seq 1 30); do
  sleep 10
  PID=$(a shell pidof "$PKG" | tr -d '\r')
  CGO=$(ra sh -c 'ls files/cgo/jak1 2>/dev/null | wc -l' | tr -d '\r')
  CUS=$(ra sh -c 'ls files/custom/jak1 2>/dev/null | wc -l' | tr -d '\r')
  echo "   t=$((i*10))s pid=${PID:-DEAD} cgo=${CGO:-0} customdirs=${CUS:-0}"
  if [ -z "$PID" ]; then DIED=1; break; fi
  LAST=$((i*10))
done
echo "   last-alive=${LAST}s died=$DIED"

echo
echo "-- 4. extraction result + crash record --"
echo "CGO_FILE_COUNT=$(ra sh -c 'ls files/cgo/jak1 2>/dev/null | wc -l' | tr -d '\r')"
echo "CUSTOM_FR3=$(ra sh -c 'ls files/custom/jak1/fr3 2>/dev/null | wc -l' | tr -d '\r')"
echo "CUSTOM_MESH_INDEX=$(ra sh -c 'ls files/custom/jak1/mesh_index 2>/dev/null | wc -l' | tr -d '\r')"
echo "CUSTOM_KB=$(ra sh -c 'du -sk files/custom/jak1 2>/dev/null | cut -f1' | tr -d '\r')"
echo "CGO_STAMP=$(ra cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "CUSTOM_STAMP=$(ra cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
# NB: `run-as ls` exits 0 even for a MISSING file — test the OUTPUT, never $?.
require_device
CRASH=$(ra sh -c 'stat -c "%Y %n" files/*.txt 2>/dev/null')
if [ -z "$(printf '%s' "$CRASH" | tr -d '[:space:]')" ]; then
  # No output at all means run-as itself failed (device gone, CE storage locked,
  # app not debuggable) — that is NOT evidence of a clean run. Say so.
  echo "FATAL: run-as returned NOTHING for files/*.txt — cannot tell a clean run from a crash. Aborting." >&2
  exit 2
fi
if printf '%s' "$CRASH" | grep -q gk_crash.txt; then
  echo "   gk_crash.txt PRESENT — a fatal signal reached the handler:"
  ra cat files/gk_crash.txt | head -20
else
  echo "   gk_crash.txt ABSENT — no fatal signal reached the handler"
fi
echo "   native diagnostics refreshed since launch (T0=$T0):"
printf '%s\n' "$CRASH" | while read -r M N; do
  [ -n "${M:-}" ] || continue
  [ "$M" -ge "$T0" ] 2>/dev/null && echo "     FRESH $N ($((M-T0))s after launch)" || echo "     old   $N"
done
echo "   exit-info: $(a shell dumpsys activity exit-info "$PKG" 2>/dev/null | grep -E 'reason=' | head -1 | tr -d '\r')"
echo "   focus: $(a shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')"

echo
echo "===== done ====="
