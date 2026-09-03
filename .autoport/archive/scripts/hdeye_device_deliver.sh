#!/usr/bin/env bash
# hdeye_device_deliver.sh — Grecharged-hd-eye-scale: install the fresh pair on the Redmi, make
# LoaderActivity re-unpack the custom pack, prove the delivery with deploy_verify, then harvest the
# [eyegap] counters from the device itself.  CODE-LEVEL ONLY — no image of any kind is taken.
#
# The device proof answers exactly one question the x86 legs cannot: did this code path RUN on
# arm64.  Quality is the owner's call, never this script's.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SER="${SER:-eae4df44}"
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-hd-eye-scale
R="$OUT/device_eyegap.txt"; : > "$R"
say(){ echo "$*" | tee -a "$R"; }
say "===== Grecharged-hd-eye-scale device leg — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)  APK=$(stat -c %y "$APK" 2>/dev/null)"

WANT_C=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
WANT_G=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
say "pack versions wanted: custom=$WANT_C cgo=$WANT_G"

say "--- install (this replaces the whole 585 MB APK, it takes minutes) ---"
if ! timeout 1800 "$ADB" -s "$SER" install -r "$APK" 2>&1 | tee -a "$R" | tail -3; then
  say "FAIL: adb install returned nonzero — literal output above"
fi

say "--- unpack via the RESOLVED activity (LoaderActivity; MainActivity would install without ever unpacking) ---"
COMP=$("$ADB" -s "$SER" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="${PKG}/org.opengoal.gk.LoaderActivity"
say "activity: $COMP"
"$ADB" -s "$SER" shell am force-stop "$PKG" >/dev/null 2>&1
"$ADB" -s "$SER" logcat -c >/dev/null 2>&1
"$ADB" -s "$SER" shell am start -n "$COMP" >/dev/null 2>&1
GOT_C=""; GOT_G=""
for i in $(seq 1 60); do
  sleep 10
  GOT_C=$("$ADB" -s "$SER" exec-out run-as "$PKG" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  GOT_G=$("$ADB" -s "$SER" exec-out run-as "$PKG" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
  [ "$GOT_C" = "$WANT_C" ] && [ "$GOT_G" = "$WANT_G" ] && break
done
# run-as lies about its exit code — judge on the CONTENT read back, never on $?.
say "stamps read back ON THE PHONE: custom='$GOT_C' cgo='$GOT_G'"
if [ "$GOT_C" = "$WANT_C" ] && [ "$GOT_G" = "$WANT_G" ]; then
  say "unpack: OK (both stamps match what was built)"
else
  say "unpack: NOT COMPLETE (custom '$GOT_C' vs '$WANT_C', cgo '$GOT_G' vs '$WANT_G')"
fi

say "--- the app keeps running so Daxter's face actually animates; harvesting ${WATCH:=240}s of counters ---"
"$ADB" -s "$SER" logcat -v time > "$OUT/.device_logcat.log" 2>/dev/null &
LOGPID=$!
t=0; while [ "$t" -lt "$WATCH" ]; do sleep 10; t=$((t+10)); done
kill "$LOGPID" 2>/dev/null
"$ADB" -s "$SER" shell am force-stop "$PKG" >/dev/null 2>&1
say "app force-stopped (never left running after a measurement)"

# -a is mandatory: the routed logcat carries binary bytes and grep would otherwise call it binary
# and print nothing but "Binary file matches".
grep -a "eyegap\|eyescale" "$OUT/.device_logcat.log" > "$OUT/device_eyegap_lines.txt" 2>/dev/null
say "--- [eyescale] params the ENGINE actually read on the phone ---"
grep -a 'PARAMSRC=' "$OUT/device_eyegap_lines.txt" | tail -2 | while read -r l; do say "  ${l#*\[eyescale\] }"; done
say "--- [eyegap] geometry seen on the phone ---"
grep -a '\[eyegap\] geom' "$OUT/device_eyegap_lines.txt" | sed 's/.*\[eyegap\] //' | sort -u | while read -r l; do say "  $l"; done
say "--- [eyegap] heartbeats on the phone ---"
grep -a '\[eyegap\] model=' "$OUT/device_eyegap_lines.txt" \
  | awk '{for(i=1;i<=NF;i++) if($i ~ /^model=/) m=$i; L[m]=$0} END{for(k in L) print L[k]}' \
  | sed 's/.*\[eyegap\] //' | sort | while read -r l; do say "  $l"; done
say "lines harvested: $(wc -l < "$OUT/device_eyegap_lines.txt" 2>/dev/null || echo 0)"
say "[device leg COMPLETE]"
