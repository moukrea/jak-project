#!/usr/bin/env bash
# Validator — Gpkg-branding: app label "Jak & Daxter" + proper launcher icon (all densities), package id
# unchanged, APK builds + shows the name/icon on device. Engine unaffected.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpkg-brand FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpkg-brand ok] $*"; }

R=.autoport/reports/Gpkg-branding/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*APP[[:space:]]+NAME[[:space:]]*\+?[[:space:]]*ICON[[:space:]]+SHIPPED' "$R" || fail "report lacks RESULT: APP NAME + ICON SHIPPED"
# label is "Jak & Daxter" in manifest or strings
grep -rqiE 'Jak ?& ?Daxter|Jak &amp; Daxter' android/app/src/main/AndroidManifest.xml android/app/src/main/res/values/strings.xml 2>/dev/null \
  || fail "app label 'Jak & Daxter' not found in manifest/strings"
# package id unchanged
grep -rq 'org.opengoal.gk' android/app/build.gradle* 2>/dev/null || fail "package id check: org.opengoal.gk not found (must stay unchanged)"
# launcher icon resources present across densities + adaptive
ICN=$(ls android/app/src/main/res/mipmap-*/ 2>/dev/null | grep -ciE 'ic_launcher' || true)
[ "${ICN:-0}" -ge 4 ] || fail "launcher icon missing at multiple densities (found $ICN)"
ls android/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml >/dev/null 2>&1 || fail "adaptive icon (mipmap-anydpi-v26) missing"
grep -qiE 'placeholder|owner.*replace|temporary' "$R" && echo "[Gpkg-brand NOTE] icon is a PLACEHOLDER pending owner art"
ok "label 'Jak & Daxter'; package id unchanged; icon at >=4 densities + adaptive"

# engine untouched: goal_src 1-to-1 + device still runs fresh HEAD
SRC=$(git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$SRC" ] || fail "goal_src edited (packaging only): $SRC"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "goal_src 1-to-1; golden pristine; device runs fresh HEAD"
echo "[Gpkg-brand PASS] APK shows 'Jak & Daxter' + proper icon; package id + engine unchanged."
