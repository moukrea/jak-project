#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gbt FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-bundled-textures/report.txt
D=.autoport/reports/Grecharged-bundled-textures/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
# assets are committed (already true) and referenced by the packaging
git ls-files custom_assets/jak1/recharged_textures | grep -q '.png' || fail "bundled recharged_textures not tracked"
grep -qiE 'recharged.?textures' "$R" || fail "no Recharged Textures toggle evidence"
grep -qiE 'bundle|embed|apk|LoaderActivity|recharged_assets.*extract|install-?only' "$R" || fail "no APK-bundled evidence (must ship in the APK, not side-load)"
grep -qiE 'nested.*(user|layout).*(win|won|beat)|texture_replacements.*(user|win|layout)|user.*(nested|subdir|tpage).*(win|won|prior)' "$R" || fail "no NESTED-layout user-precedence device proof (owner real scenario: internet pack in subdirs must win — the flat magenta test is insufficient)"
grep -qiE '(height|normal|roughness).*(pbr|map)|pbr.*(maps?|height|normal|roughness)' "$R" || fail "no PBR-maps consumption evidence"
grep -qiE 'off ?== ?stock|byte-identical|toggle off.*stock' "$R" || fail "no OFF==stock evidence"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not updated (standing rule)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gbt PASS]"
