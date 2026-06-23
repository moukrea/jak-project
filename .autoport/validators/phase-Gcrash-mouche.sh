#!/usr/bin/env bash
# Validator — Gcrash-mouche: collecting a scout-fly (buzzer) must be crash-free. Either a VERIFIED
# programmatic buzzer-pickup repro+fix, OR an honest >=6-attempt non-repro + real manipy/HUD-merc fix
# + an owner-verification request. Must NOT false-green on orb-collect.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gmouche FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gmouche ok] $*"; }

R=.autoport/reports/Gcrash-mouche/runs.txt
[ -f "$R" ] || fail "no runs.txt"
# the buzzer pickup FX must be specifically exercised/named (NOT orb-collect)
grep -qiE 'buzzer|scout.?fly|mouche' "$R" || fail "runs.txt must cover the BUZZER/scout-fly (not orbs)"
grep -qiE 'manipy|fly-?to-?hud|hud.?merc|pickup.?fx' "$R" || fail "runs.txt must name the buzzer pickup FX path (manipy/HUD-merc)"

VERIFIED=0; OWNER=0
if grep -qiE 'RESULT:[[:space:]]*BUZZER[[:space:]]+COLLECT[[:space:]]+CRASH-?FREE[[:space:]]*\(verified\)' "$R"; then
  VERIFIED=1
  grep -qiE 'before|reproduc' "$R" || fail "verified path: must document the reproduced BEFORE crash"
  grep -qiE 'sig=(4|6|11)|fatal' "$R" || fail "verified path: must show the captured crash signal"
  grep -qiE 'writer|victim|stomp|canary' "$R" || fail "verified path: must name writer/victim"
  N=$(grep -acE 'crash-?free|reach|0 sig|sig=0' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 5 ] || fail "verified path: need >=5 crash-free buzzer collects (got $N)"
  ok "verified path: buzzer pickup-FX crash reproduced + fixed, crash-free >=5x"
elif grep -qiE 'RESULT:[[:space:]]*BUZZER[[:space:]]+FIX[[:space:]]+APPLIED.*OWNER[[:space:]]+VERIFICATION[[:space:]]+REQUIRED' "$R"; then
  OWNER=1
  A=$(grep -aciE 'attempt|tried|method' "$R" 2>/dev/null || true); [ "${A:-0}" -ge 6 ] || fail "owner-verify path: must document >=6 distinct failed programmatic trigger attempts (got $A)"
  [ -f .autoport/reports/Gcrash-mouche/owner-verify.md ] || fail "owner-verify path: owner-verify.md missing"
  grep -qiE 'collect.*scout|collect.*buzzer|collect.*fly' .autoport/reports/Gcrash-mouche/owner-verify.md || fail "owner-verify.md must give the collect-a-fly verification step"
  ok "owner-verify path: exhaustive non-repro documented + manipy fix applied + owner-verify.md present"
else
  fail "runs.txt lacks a valid RESULT (either 'BUZZER COLLECT CRASH-FREE (verified)' or 'BUZZER FIX APPLIED — OWNER VERIFICATION REQUIRED')"
fi

# real fix + goal_src 1-to-1 + summary + golden
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real code fix to the manipy/merc path"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gcrash-mouche-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "real fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
[ "$VERIFIED" = 1 ] && echo "[Gmouche PASS] buzzer collect crash reproduced + fixed at the manipy/merc root, crash-free; x86 1-to-1."
[ "$OWNER" = 1 ] && echo "[Gmouche PASS-pending-owner] manipy/HUD-merc fix applied; programmatic buzzer-collect unreproducible (>=6 attempts) — OWNER must collect a scout fly to confirm. See owner-verify.md."
