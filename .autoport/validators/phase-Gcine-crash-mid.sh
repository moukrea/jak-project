#!/usr/bin/env bash
# Validator — Gcine-crash-mid: the FULL new-game intro cinematic must complete crash-free to gameplay
# repeatably (>=8 runs) — the non-deterministic mid-cinematic merc/DMA stomp fixed at the root.
# Calibrated: BEFORE must reproduce the owner crash (or an honest >=20-run non-repro statement).
# See [[a38-blind-to-dma-content-canary]], [[cross-thread-stomp-repair-resume]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcine-mid FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcine-mid ok] $*"; }

R=.autoport/reports/Gcine-crash-mid/runs.txt
[ -f "$R" ] || fail "no runs.txt (full owner cinematic driven >=8x with crash results)"
grep -qiE 'RESULT:[[:space:]]*FULL[[:space:]]+CINEMATIC[[:space:]]+COMPLETES[[:space:]]+CRASH-?FREE[[:space:]]*\(8/8\)' "$R" \
  || fail "runs.txt lacks RESULT: FULL CINEMATIC COMPLETES CRASH-FREE (8/8)"
# >= 8 gameplay-reaching runs
N=$(grep -acE 'frame=1[0-9]{4}|reach.*gameplay|REACH' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 8 ] || fail "fewer than 8 crash-free gameplay-reaching runs documented (got $N)"
# calibration: a reproduced BEFORE crash with writer+victim, OR an honest >=20-run non-repro
if grep -qiE 'could not reproduce|not reproduc|no repro' "$R"; then
  grep -qiE '2[0-9]|[3-9][0-9]|runs' "$R" || fail "non-repro claim must cite >=20 runs"
  ok "honest non-reproduction documented (>=20 runs)"
else
  grep -qiE 'before|reproduc|sig=(4|6|11)|fatal' "$R" || fail "runs.txt must document the reproduced BEFORE crash (sig + writer + victim)"
  grep -qiE 'writer|victim|stomp|canary|merc|envmap|blend' "$R" || fail "runs.txt must name the stomp writer/victim"
  ok "owner mid-cinematic crash reproduced + characterized (writer/victim/stomp)"
fi
ok "full cinematic completes crash-free >=8/8"

# real libgk change + fix-summary + 1-to-1 source
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/' || fail "no real libgk code change addressing the stomp"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gcine-crash-mid-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "real libgk fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcine-mid PASS] full new-game intro cinematic completes crash-free to gameplay 8/8; mid-cinematic stomp fixed at the root; x86 1-to-1."
