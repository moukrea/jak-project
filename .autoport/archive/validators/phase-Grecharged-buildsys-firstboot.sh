#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-buildsys-firstboot/report.txt
[ -f "$R" ] || { echo "[buildsys-firstboot FAIL] no report"; exit 1; }
grep -qE '^RESULT:' "$R" || { echo "[buildsys-firstboot FAIL] no RESULT line"; exit 1; }
grep -qiE 'IN-PROGRESS|not final|skeleton' "$R" && { echo "[buildsys-firstboot FAIL] living-skeleton RESULT"; exit 1; }
grep -qiE 'settings\.ini' "$R" || { echo "[buildsys-firstboot FAIL] no settings.ini proof"; exit 1; }
grep -qiE 'custom_assets' "$R" || { echo "[buildsys-firstboot FAIL] no custom_assets proof"; exit 1; }
grep -qiE 'picker|SAF|browser' "$R" || { echo "[buildsys-firstboot FAIL] no native-picker proof"; exit 1; }
echo "[buildsys-firstboot] validator PASS"
