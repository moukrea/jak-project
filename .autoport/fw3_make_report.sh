#!/usr/bin/env bash
# Assemble .autoport/reports/Grecharged-foliage-wind3/report.txt depuis les sections redigees.
# DIRECTIVES vd9e8b66782
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Grecharged-foliage-wind3
cat "$D/report-draft-head.txt" \
    "$D/report-draft-d1d3.txt" \
    "$D/report-draft-d2.txt" \
    "$D/report-draft-device.txt" \
    "$D/report-draft-tail.txt" \
    "$D/report-draft-owner.txt" \
    "$D/report-draft-markers.txt" > "$D/report.txt" 2>/dev/null
wc -l "$D/report.txt"
echo "--- marqueurs ---"
grep -E "^RESULT:|^WINDNATIVE|^WINDCOVER|^WINDAMP|^DIRECTIVES" "$D/report.txt"
