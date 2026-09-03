#!/usr/bin/env bash
# Validator — Gcrash-mouche2: collecting a buzzer must be crash-free AND free of the render blue-lock
# (>=5x), the residual SP-relative stomp named + fixed. See [[a38-blind-to-dma-content-canary]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gmouche2 FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gmouche2 ok] $*"; }

R=.autoport/reports/Gcrash-mouche2/runs.txt
[ -f "$R" ] || fail "no runs.txt"
grep -qiE 'RESULT:[[:space:]]*BUZZER[[:space:]]+COLLECT[[:space:]]+CRASH-?FREE[[:space:]]*\+?[[:space:]]*NO[[:space:]]+BLUE-?LOCK[[:space:]]*\(5/5\)' "$R" \
  || fail "runs.txt lacks RESULT: BUZZER COLLECT CRASH-FREE + NO BLUE-LOCK (5/5)"
grep -qiE 'buzzer|scout.?fly|mouche' "$R" || fail "must cover the buzzer collect"
# the BLUE-LOCK (render hang) reproduced BEFORE
grep -qiE 'blue|render.?lock|frame.*stop|hang|stuck' "$R" || fail "must reproduce/address the BLUE-LOCK render-hang"
grep -qiE 'before|reproduc' "$R" || fail "must document the reproduced BEFORE blue-lock"
grep -qiE 'writer|victim|stomp|sp-?relative|canary|watchpoint' "$R" || fail "must name the SP-relative stomp writer/victim"
# AFTER: >=5 collects with render advancing + 0 sig
N=$(grep -acE 'collect.*[0-9]|REACH|frame.*advanc|run [0-9]' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 5 ] || fail "fewer than 5 crash-free buzzer collects documented (got $N)"
grep -qiE 'frame.*advanc|monoton|render.*progress|no.*lock' "$R" || fail "must show render frames keep advancing after the fix (no blue-lock)"
grep -qiE '0[[:space:]]*sig|sig=0|crash-?free' "$R" || fail "must assert 0 sig"
ok "buzzer collect: blue-lock reproduced + writer named; AFTER >=5x render-advancing crash-free"

CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code fix"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gcrash-mouche2-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "real fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gmouche2 PASS] buzzer collect crash-free + no render blue-lock (5/5); residual SP-relative stomp fixed; goal_src 1-to-1."
