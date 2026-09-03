#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glogo FAIL] $*" >&2; exit 1; }
ok(){ echo "[Glogo ok] $*"; }
R=.autoport/reports/Grecharged-title-logo-fullres/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:' "$R" || fail "no RESULT line"
grep -qiE 'RESULT:.*(IN-PROGRESS|in progress|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE 'toggle|recharged settings|réglages' "$R" || fail "must be a Recharged Settings toggle"
grep -qiE 'off.*(stock|identical|unchanged|byte)|stock.*off' "$R" || fail "OFF must == stock pipeline"
grep -qiE 'render.?scale|renderscale' "$R" || fail "must test at a LOW render scale"
grep -qiE '(logo).*(full|native|crisp|net)|(full|native).*(res|resolution).*logo' "$R" || fail "logo must render at native res while world is scaled"
grep -qiE 'title.*(scale 1|no regression)|regression' "$R" || fail "must prove no title regression at scale 1.0"
F=$(find .autoport/reports/Grecharged-title-logo-fullres -type f -name '*.png' -newermt '-2 days' 2>/dev/null | grep -v '/x86/' | grep -icE 'device|jak1focus' || true)
[ "${F:-0}" -ge 2 ] || fail "need OFF(pixelated) and ON(crisp) device captures at low render scale (found $F)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "report + gated + OFF/ON low-scale evidence + no-regression"
echo "[Glogo PASS] crisp title logo gated + evidenced. (owner play-test next)"
