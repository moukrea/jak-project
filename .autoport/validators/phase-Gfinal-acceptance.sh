#!/usr/bin/env bash
# Validator — Gfinal-acceptance: one device session must verify ALL owner-reported defects fixed on
# current HEAD (deterministic metrics, no pixels), no regression, goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gaccept FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gaccept ok] $*"; }

R=.autoport/reports/Gfinal-acceptance/acceptance.txt
[ -f "$R" ] || fail "no acceptance.txt (one device session covering all 7 checks)"
grep -qiE 'RESULT:[[:space:]]*ALL[[:space:]]+OWNER[[:space:]]+DEFECTS[[:space:]]+VERIFIED[[:space:]]+FIXED' "$R" \
  || fail "acceptance.txt lacks RESULT: ALL OWNER DEFECTS VERIFIED FIXED ON CURRENT HEAD (no regression)"
# each of the 7 deterministic checks must be cited
grep -qiE 'frame[= ]*1[0-9]{4}|gameplay' "$R" || fail "missing boot->gameplay frame >= 10500"
grep -qiE '0[[:space:]]*(sig|crash)|no[[:space:]]+(sig|crash)|crash-?free|sig\(4/6/11\)=0|sig=0' "$R" || fail "missing 0-crash assertion"
grep -qiE '24576|corona' "$R" || fail "missing sun corona check"
grep -qiE 'vproc3d|particle' "$R" || fail "missing particle check"
grep -qiE 'star' "$R" || fail "missing night-star check"
grep -qiE 'bird|bob' "$R" || fail "missing bird-anim check"
grep -qiE 'menu|PART0|spread' "$R" || fail "missing menu placement check"
grep -qiE 'water|ocean|near.*vert' "$R" || fail "missing near-water check"
grep -qiE 'cinematic|new.?game|overwrite' "$R" || fail "missing cinematic-completes check"
ok "all 7 deterministic owner-defect checks cited; boot->gameplay crash-free"

# verification only: no goal_src edits, golden pristine
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (acceptance is verification-only): $SRC"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
S=.autoport/reports/Gfinal-acceptance-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "summary must confirm temp instrumentation removed"
ok "verification-only (goal_src 1-to-1); golden pristine; summary present"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gaccept PASS] all 9 owner-reported defects verified fixed on the current HEAD device build, no regression, crash-free to gameplay."
