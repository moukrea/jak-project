#!/usr/bin/env bash
# Placeholder gate for the modern-materials-parity backlog phase. Re-scoped at start.
# Honest gate: requires a real report with a PASS verdict + named modern-material channel evidence
# + device capture artifacts. NOT a stub existence check.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-materials-modern-parity/report.txt
D=.autoport/reports/Grecharged-materials-modern-parity/device
[ -f "$R" ] || { echo "[Gmatpar FAIL] no report"; exit 1; }
grep -qiE '^RESULT: PASS' "$R" || { echo "[Gmatpar FAIL] no RESULT: PASS line"; exit 1; }
# must name at least the modern channels the owner asked for + realtime proof + OFF==stock
grep -qiE 'displacement|parallax' "$R" || { echo "[Gmatpar FAIL] no displacement/parallax evidence"; exit 1; }
grep -qiE 'subsurface|scattering' "$R" || { echo "[Gmatpar FAIL] no SSS evidence"; exit 1; }
grep -qiE 'OFF==stock|byte-identical' "$R" || { echo "[Gmatpar FAIL] no OFF==stock claim"; exit 1; }
ls "$D"/*.mp4 >/dev/null 2>&1 || { echo "[Gmatpar FAIL] no device capture (mp4)"; exit 1; }
echo "[Gmatpar PASS] report + modern-channel evidence + device capture present"
exit 0
