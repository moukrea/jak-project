#!/usr/bin/env bash
# Validator — Gledge-glitch: arm64 ledge/edge grab+fall collision-response must match x86 (no
# glitch/"projection"/eject). Regression check vs recent collision fixes first. goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gledge FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gledge ok] $*"; }

R=.autoport/reports/Gledge-glitch/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ARM[[:space:]]+LEDGE/?EDGE[[:space:]]+RESPONSE[[:space:]]+MATCHES[[:space:]]+X86' "$R" \
  || fail "report lacks RESULT: ARM LEDGE/EDGE RESPONSE MATCHES X86"
grep -qiE 'regress' "$R" || fail "must document the regression check vs recent collision fixes (collide_cache/collide_edge_grab/FMA)"
grep -qiE 'ledge|edge|border|grab|hang|wall|bordure|accroch' "$R" || fail "must cover the ledge/edge grab+fall"
grep -qiE 'project|eject|launch|glitch|propuls' "$R" || fail "must address the projection/eject glitch"
grep -qiE 'x86' "$R" || fail "must be x86-first"
grep -qiE 'device|eae4df44|arm64' "$R" || fail "must include the device dump"
grep -qiE 'normal|veloc|impulse|penetrat|prim|plane|float|dot|nan|denorm|ftz|#f|modulo|ldp|fma' "$R" || fail "must dump+name the diverging collision-response value"
grep -qiE 'before|baseline' "$R" || fail "must document the BEFORE (device ejects/glitches)"
grep -qiE 'after' "$R" || fail "must document the AFTER (device == x86, clean)"
grep -qiE 'device.*(==|=|match).*x86|1-?to-?1|identical' "$R" || fail "must show device edge-response == x86 after fix"
ok "x86-first edge-response diff: regression-checked, divergence named, device BEFORE->AFTER(==x86)"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gledge-glitch-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gledge PASS] arm64 ledge/edge collision-response matches x86 (no projection/eject); goal_src 1-to-1."
