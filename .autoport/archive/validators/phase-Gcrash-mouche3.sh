#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${ANCHOR:-HEAD}
fail(){ echo "[Gmouche3 FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
R=.autoport/reports/Gcrash-mouche3/runs.txt
[ -f "$R" ] || fail "no runs.txt"
A=0; B=0
if grep -qiE 'RESULT:[[:space:]]*REAL[[:space:]]+SCOUT-?FLY[[:space:]]+COLLECT[[:space:]]+CRASH-?FREE[[:space:]]*\(5/5\)' "$R"; then
  A=1
  grep -qiE 'crate.?break|break.*crate|real.*crate|crate.*fly' "$R" || fail "Route A must exercise the REAL crate-break path (not a spawn shortcut)"
  grep -qiE 'before|reproduc' "$R" || fail "Route A must reproduce the crash on the real path BEFORE"
  grep -qiE 'writer|victim|stomp|sig' "$R" || fail "Route A must name the crash"
  N=$(grep -acE 'collect.*[0-9]|run [0-9]|REACH' "$R" 2>/dev/null||true); [ "${N:-0}" -ge 5 ] || fail "Route A needs >=5 real crash-free collects (got $N)"
elif grep -qiE 'RESULT:[[:space:]]*REAL[[:space:]]+CRASH[[:space:]]+CAPTURED[[:space:]]*\+?[[:space:]]*FIXED.*OWNER[[:space:]]+RE-?VERIFY' "$R"; then
  B=1
  [ -f .autoport/reports/Gcrash-mouche3/owner-capture.md ] || fail "Route B: owner-capture.md missing"
  grep -qiE 'collect.*fly|collect.*scout|collect.*mouche' .autoport/reports/Gcrash-mouche3/owner-capture.md || fail "owner-capture.md must instruct the owner to collect a fly"
  grep -qiE 'captured|real crash|sig|pc=|lr=' "$R" || fail "Route B must show the owner's real crash was captured"
else
  fail "runs.txt lacks a valid RESULT (Route A 'REAL SCOUT-FLY COLLECT CRASH-FREE (5/5)' or Route B 'REAL CRASH CAPTURED + FIXED — OWNER RE-VERIFY')"
fi
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited: $SRC"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 2>/dev/null | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code change"
S=.autoport/reports/Gcrash-mouche3-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary <60 lines"
grep -qiE 'remov|deleted|no leftover' "$S" || fail "fix-summary must confirm instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified"
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
[ "$A" = 1 ] && echo "[Gmouche3 PASS] real crate->fly->collect crash-free 5/5; goal_src 1-to-1."
[ "$B" = 1 ] && echo "[Gmouche3 PASS-owner-loop] real crash captured+fixed; OWNER must re-verify a real collect. See owner-capture.md."
