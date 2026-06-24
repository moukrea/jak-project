#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${ANCHOR:-HEAD}
fail(){ echo "[Gecho FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
R=.autoport/reports/Gecho-pool/pool.txt
[ -f "$R" ] || fail "no pool.txt"
grep -qiE 'RESULT:[[:space:]]*DARK-?ECO[[:space:]]+POOL[[:space:]]+RENDERS[[:space:]]+IN[[:space:]]+CINEMATIC' "$R" || fail "pool.txt lacks RESULT: DARK-ECO POOL RENDERS IN CINEMATIC (device occludes the ottsel)"
grep -qiE 'eco|pool|liquid|surface' "$R" || fail "pool.txt must cover the dark-eco pool element"
grep -qiE 'tris|verts|bucket|draw|submit' "$R" || fail "pool.txt must dump the pool draw presence (tris/verts/bucket)"
grep -qiE 'before|baseline|absent|0|missing|noop' "$R" || fail "pool.txt must document the BEFORE (pool draw absent/0 on device)"
grep -qiE 'after' "$R" || fail "pool.txt must document the AFTER (pool renders)"
grep -qiE 'x86|gold|==' "$R" || fail "pool.txt must compare to x86"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited: $SRC"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v IGenX86_64 | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code change"
S=.autoport/reports/Gecho-pool-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary <60 lines"
grep -qiE 'remov|deleted|no leftover' "$S" || fail "fix-summary must confirm instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified"
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gecho PASS] dark-eco pool renders in the intro cinematic on device; goal_src 1-to-1. Owner eye final."
