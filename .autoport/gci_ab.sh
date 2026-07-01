#!/usr/bin/env bash
# Gcamera-interp A/B: same binary, toggle debug.opengoal.caminterp off vs on,
# capture a Geyser right-stick pan each, on the FRESH-CGO device. Sub-60 regime
# (dynamic scale, owner condition) so the integer time-ratio k dithers -> the
# judder the fix targets. Waits for the fresh arm64 ENGINE.CGO before touching the
# app (so it never interrupts the re-extraction).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="/home/emeric/Android/platform-tools/adb -s eae4df44"
FRESH=71d4fc2730f87ee9a72e53e74c50c6d3623e55f1272d8713a4e9e08555ae818f
PAN="${PAN:-18}"

echo "=== wait for FRESH ENGINE.CGO on device (extraction complete) ==="
ok=0
for i in $(seq 1 60); do
  H=$($ADB shell run-as org.opengoal.gk.jak1 sha256sum files/iso_data/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  if [ "$H" = "$FRESH" ]; then echo "  fresh CGO present (t~$((i*5))s)"; ok=1; break; fi
  sleep 5
done
[ "$ok" = 1 ] || { echo "FAIL: fresh CGO never appeared (last=$H)"; exit 1; }

run_side(){
  local val="$1" label="$2"
  echo "=== side: caminterp=$val -> $label ==="
  $ADB shell setprop debug.opengoal.caminterp "$val" >/dev/null 2>&1 || true
  # RSCALE default 100 (full-res) => clearly sub-60 at Geyser => integer k dithers
  # 2<->3 => the strong judder the fix targets. Same scale both sides => clean A/B.
  RSCALE="${RSCALE:-100}" SETTLE=12 bash .autoport/gcam_pace.sh run "$label" "$PAN" 2>&1 | tail -20
  echo "--- analyzer ($label) ---"
  python3 .autoport/gci_analyze.py ".autoport/reports/Gcamera-smooth/evidence/$label.log" pan 2>&1 | tail -12
}

run_side 0 gci3_before
run_side 1 gci3_after

echo "=== DONE. logs: .autoport/reports/Gcamera-smooth/evidence/gci3_{before,after}.log ==="
