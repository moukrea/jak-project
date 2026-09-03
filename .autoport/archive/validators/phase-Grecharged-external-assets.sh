#!/usr/bin/env bash
# Validator — Grecharged-external-assets: binary/assets split + external layout + prompt + custom-assets toggle.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gextassets FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gextassets ok] $*"; }
R=.autoport/reports/Grecharged-external-assets/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*EXTERNAL ASSETS' "$R" || fail "no RESULT: EXTERNAL ASSETS <before>-><after>"
grep -qiE 'prompt|picker|choose|chosen|SAF' "$R" || fail "must implement the first-boot asset-location prompt"
grep -qiE 'permission|SAF|MANAGE_EXTERNAL|READ_EXTERNAL|scoped' "$R" || fail "must handle Android storage permissions"
grep -qiE 'jak_1/assets' "$R" && grep -qiE 'jak_1/saves' "$R" || fail "must implement the jak_N/assets + jak_N/saves layout"
grep -qiE 'custom_assets' "$R" || fail "must wire jak_N/custom_assets"
grep -qiE 'load custom assets|custom.*toggle|toggle.*custom' "$R" || fail "must add the LOAD CUSTOM ASSETS toggle in Recharged Settings"
grep -qiE 'save.*(created|verified|lands|written)|sauvegarde' "$R" || fail "must verify a save lands in jak_1/saves on device"
grep -qiE 'migrat|existing|compat' "$R" || fail "must handle migration of existing installs (device saves preserved)"
grep -qiE 'link finish: logo' "$R" || fail "x86 flow must be shown too"
ok "report covers split+prompt+permissions+layout+custom toggle+migration+x86"
# PHYSICAL: APK must be dramatically smaller (no embedded iso assets) + an asset archive artifact exists
APK=$(ls -t android/app/build/outputs/apk/jak1/*/app-jak1-*.apk 2>/dev/null | head -1)
[ -n "$APK" ] || fail "no built APK"
SZ=$(stat -c %s "$APK"); [ "$SZ" -lt 400000000 ] || fail "APK still huge ($((SZ/1048576))MB) — assets not split out"
ok "APK slim: $((SZ/1048576))MB"
ARC=$(find android out build* -maxdepth 3 -type f \( -name '*asset*.zip' -o -name '*assets*.tar*' -o -name 'jak1-assets*' \) -size +200M 2>/dev/null | head -1)
[ -n "$ARC" ] || grep -qiE 'archive.*(path|produced|artifact)' "$R" || fail "no separate asset archive artifact found/reported"
ok "asset archive present/reported"
grep -qiE 'READ_EXTERNAL|MANAGE_EXTERNAL|permission' android/app/src/main/AndroidManifest.xml 2>/dev/null || grep -qiE 'SAF|ACTION_OPEN_DOCUMENT_TREE' -r android/app/src 2>/dev/null || fail "no storage permission/SAF in the Android app"
ok "storage permission/SAF wired"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gextassets PASS]"
