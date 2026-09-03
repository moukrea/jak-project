#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-buildsys-flags/report.txt
[ -f "$R" ] || { echo "[buildsys-flags FAIL] no report"; exit 1; }
grep -qE '^RESULT:' "$R" || { echo "[buildsys-flags FAIL] no RESULT line"; exit 1; }
grep -qiE 'IN-PROGRESS|not final|skeleton' "$R" && { echo "[buildsys-flags FAIL] living-skeleton RESULT"; exit 1; }
grep -qiE 'yolo' "$R" || { echo "[buildsys-flags FAIL] no --yolo proof"; exit 1; }
grep -qiE 'flag.?set hash|flag-set' "$R" || { echo "[buildsys-flags FAIL] no flag-set-hash keying proof"; exit 1; }
[ -x build.sh ] || { echo "[buildsys-flags FAIL] no executable build.sh at repo root"; exit 1; }
echo "[buildsys-flags] validator PASS"
