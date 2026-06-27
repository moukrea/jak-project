#!/usr/bin/env bash
# Validator — Gdeath-crash: dying must be crash-free on arm64 (was: death -> app killed to home).
# x86-first; the arm64 death/respawn divergence named + fixed in translation. goal_src 1-to-1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gdeath FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gdeath ok] $*"; }

R=.autoport/reports/Gdeath-crash/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*DEATH[[:space:]]+CRASH-?FREE[[:space:]]*\(5/5\)' "$R" || fail "report lacks RESULT: DEATH CRASH-FREE (5/5)"
grep -qiE 'death|respawn|die|mort' "$R" || fail "must cover the death/respawn path"
grep -qiE 'before|reproduc' "$R" || fail "must document the reproduced BEFORE crash"
grep -qiE 'sig|SIGSEGV|SIGABRT|SIGILL|writer|victim|stomp|pc|lr|fp-?walk|canary' "$R" || fail "must name the crash signature + writer/victim"
grep -qiE 'x86' "$R" || fail "must be x86-first (x86 does not crash on death)"
grep -qiE 'diverg|nan|denorm|ftz|#f|modulo|ldp|merc|dma|pointer|float|codegen|mips2c' "$R" || fail "must name the arm64 divergence"
N=$(grep -acE 'death.*[0-9]|run [0-9]|[0-9].*crash-?free|respawn' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 5 ] || fail "fewer than 5 crash-free deaths documented (got $N)"
grep -qiE 'foreground|render.*advanc|0[[:space:]]*sig|sig=0|crash-?free' "$R" || fail "must assert app foreground + 0 sig after fix"
ok "death crash reproduced + named; AFTER >=5 deaths crash-free, app foreground"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no real code fix"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Gdeath-crash-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "real fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gdeath PASS] dying is crash-free (5/5); arm64 death/respawn divergence fixed in translation; goal_src 1-to-1."
