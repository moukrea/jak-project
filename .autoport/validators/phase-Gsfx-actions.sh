#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${ANCHOR:-HEAD}
fail(){ echo "[Gsfx-actions FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
R=.autoport/reports/Gsfx-actions/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*crate|orb|eco; rms|sound|snd-?play|silent' "$R" || fail "report.txt lacks RESULT: crate|orb|eco; rms|sound|snd-?play|silent"
for g in ; do grep -qiE "$g" "$R" || fail "report.txt must cover: $g"; done
grep -qiE 'before|baseline' "$R" || fail "must document BEFORE (device diverges)"
grep -qiE 'after' "$R" || fail "must document AFTER (device == x86)"
grep -qiE 'x86|gold|==|diverg' "$R" || fail "must be an x86-first diff"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited: $SRC"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v IGenX86_64 | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code change"
S=.autoport/reports/Gsfx-actions-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary <60 lines"
grep -qiE 'remov|deleted|no leftover' "$S" || fail "fix-summary must confirm instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified"
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gsfx-actions PASS] crate|orb|eco; rms|sound|snd-?play|silent — arm64==x86; goal_src 1-to-1. Owner eye/ear final."
