#!/usr/bin/env bash
# Validator — Gcollision-nanroot: DIRECT fix of the arm64 collision NaN root (the op that produces a NaN
# where x86 is finite, cascading to clip/eject/under-map). No input-replay. Objective gate = NaN-root
# named+fixed (x86==arm64); FINAL gate = owner play-test (supervisor coordinates). goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gnan FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gnan ok] $*"; }

R=.autoport/reports/Gcollision-nanroot/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ARM[[:space:]]+COLLISION[[:space:]]+NAN[[:space:]]+ROOT[[:space:]]+FIXED' "$R" \
  || fail "report lacks RESULT: ARM COLLISION NAN ROOT FIXED"
# the FIRST NaN/divergence + its ORIGIN op named, x86 finite vs arm64 NaN BEFORE
grep -qiE 'nan|exp=0xff|0x7f[c8]0000|first.*diverg|origin|root op|smoking gun' "$R" || fail "must name the first NaN/divergence + origin"
grep -qiE 'normalize|divide|rsqrt|sqrt|vu0|vftoi|degenerate|0/0|uninit|reflect' "$R" || fail "must name the op that produces the NaN"
grep -qiE 'x86.*finite|finite.*x86|x86.*[0-9].*arm64.*nan|before' "$R" || fail "must show x86 finite vs arm64 NaN BEFORE"
grep -qiE 'after' "$R" || fail "must show AFTER (arm64 op finite == x86, no NaN)"
grep -qiE 'arm64.*(==|=|match).*x86|0[[:space:]]*nan|no.*nan|finite.*both' "$R" || fail "must show arm64 collision == x86 / 0 NaN after the fix"
grep -qiE 'fcvtzs|gcollision-systemic|re-?examin|kept|narrow|revert' "$R" || fail "must document the FCVTZS re-examination (kept/narrowed/reverted)"
grep -qiE 'owner.*(play|test|eye|verif)|final gate' "$R" || fail "must note the owner play-test is the final gate"
ok "NaN root named+fixed (x86 finite -> arm64 NaN BEFORE -> ==x86 AFTER); FCVTZS re-examined; owner-gate noted"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gcollision-nanroot-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "translation-layer fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gnan PASS] arm64 collision NaN root fixed (x86==arm64). AWAITING OWNER PLAY-TEST (final gate)."
