#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-buildsys-cidocs/report.txt
[ -f "$R" ] || { echo "[buildsys-cidocs FAIL] no report"; exit 1; }
grep -qE '^RESULT:' "$R" || { echo "[buildsys-cidocs FAIL] no RESULT line"; exit 1; }
grep -qiE 'IN-PROGRESS|not final|skeleton' "$R" && { echo "[buildsys-cidocs FAIL] living-skeleton RESULT"; exit 1; }
grep -qiE 'README' "$R" || { echo "[buildsys-cidocs FAIL] no README rewrite proof"; exit 1; }
grep -qiE 'workflow|actions|CI' "$R" || { echo "[buildsys-cidocs FAIL] no CI proof"; exit 1; }
echo "[buildsys-cidocs] validator PASS"
