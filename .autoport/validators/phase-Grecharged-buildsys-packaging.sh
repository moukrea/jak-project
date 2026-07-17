#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-buildsys-packaging/report.txt
[ -f "$R" ] || { echo "[buildsys-packaging FAIL] no report"; exit 1; }
grep -qE '^RESULT:' "$R" || { echo "[buildsys-packaging FAIL] no RESULT line"; exit 1; }
grep -qiE 'IN-PROGRESS|not final|skeleton' "$R" && { echo "[buildsys-packaging FAIL] living-skeleton RESULT"; exit 1; }
grep -qiE 'assets\.zip|_assets\.zip' "$R" || { echo "[buildsys-packaging FAIL] no assets.zip proof"; exit 1; }
grep -qiE 'manifest' "$R" || { echo "[buildsys-packaging FAIL] no content-manifest review"; exit 1; }
echo "[buildsys-packaging] validator PASS"
