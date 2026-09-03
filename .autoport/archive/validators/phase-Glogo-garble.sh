#!/usr/bin/env bash
# Validator — Glogo-garble: the title logo geometry must be INTACT on device (no garble), proven by
# eliminating the GND-OOB-WRITE that stomps it (400 -> 0) + logo data integrity (NEVER pixels),
# our-x86==original. See [[a38-blind-to-dma-content-canary]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Glogo-g FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Glogo-g ok] $*"; }

R=.autoport/reports/Glogo-garble/garble.txt
[ -f "$R" ] || fail "no garble.txt (GND-OOB-WRITE writer/target + BEFORE/AFTER, 3-way)"
grep -qiE 'RESULT:[[:space:]]*LOGO[[:space:]]+GEOMETRY[[:space:]]+INTACT.*OOB[[:space:]]+WRITE[[:space:]]+ELIMINATED' "$R" \
  || fail "garble.txt lacks RESULT: LOGO GEOMETRY INTACT — OOB WRITE ELIMINATED (device)"
grep -qiE 'oob-?write|out.?of.?bounds|writer|target|stomp|corrupt' "$R" || fail "garble.txt must characterize the OOB writer/target/corrupted-data"
# calibrated BEFORE ~400 -> AFTER 0
grep -qiE 'before|baseline' "$R" || fail "garble.txt must document the calibrated BEFORE (device GND-OOB-WRITE ~400 / logo stomped)"
grep -qiE 'after' "$R" || fail "garble.txt must document the AFTER (device GND-OOB-WRITE = 0 / logo intact)"
grep -qiE '= ?0|-> ?0|to ?0|zero|eliminat' "$R" || fail "garble.txt must show the OOB write count goes to 0 on device"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical|x86.*no.*oob|not.*on.*x86' "$R" || fail "garble.txt must show our-x86 == original-x86 / no OOB on x86 (1-to-1)"
ok "OOB writer characterized; device GND-OOB-WRITE 400->0; logo geometry intact; x86 1-to-1"

# === real translation-layer change; goal_src only as pristine revert ===
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no real translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|restore.*original' "$R" || fail "goal_src edited but not a documented pristine revert: $SRC"; fi
S=.autoport/reports/Glogo-garble-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "real translation-layer fix; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Glogo-g PASS] logo geometry intact — GND-OOB-WRITE eliminated (400->0) on device; x86 1-to-1."
