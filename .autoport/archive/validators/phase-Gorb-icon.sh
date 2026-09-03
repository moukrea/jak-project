#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${ANCHOR:-HEAD}
fail(){ echo "[Gorb FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
R=.autoport/reports/Gorb-icon/orb.txt
[ -f "$R" ] || fail "no orb.txt"
grep -qiE 'RESULT:[[:space:]]*ORB[[:space:]]+ICON[[:space:]]+TEXTURE[[:space:]]+LOADS[[:space:]]+ON[[:space:]]+DEVICE' "$R" || fail "orb.txt lacks RESULT: ORB ICON TEXTURE LOADS ON DEVICE (HUD + menu)"
grep -qiE 'tex.?id|handle|tpage|texture|clut|bound' "$R" || fail "orb.txt must dump the orb sprite bound texture handle/tex-id"
grep -qiE 'hud' "$R" || fail "orb.txt must cover the HUD orb icon"
grep -qiE 'menu' "$R" || fail "orb.txt must cover the menu orb icon"
grep -qiE 'before|baseline|white|default|missing|0' "$R" || fail "orb.txt must document the BEFORE (white/default/missing texture)"
grep -qiE 'after' "$R" || fail "orb.txt must document the AFTER (real orb texture bound)"
grep -qiE 'x86|gold|==' "$R" || fail "orb.txt must compare to x86 (the working reference)"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited: $SRC"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v IGenX86_64 | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code change"
S=.autoport/reports/Gorb-icon-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary <60 lines"
grep -qiE 'remov|deleted|no leftover' "$S" || fail "fix-summary must confirm instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified"
bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gorb PASS] orb icon texture loads on device (HUD+menu); goal_src 1-to-1. Owner eye final."
