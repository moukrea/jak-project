#!/usr/bin/env bash
# Validator — Gconsolidate-deploy: the device must persistently run a fresh CONSISTENT HEAD build
# (28-file arm64 CGO/DGO set + libgk), booting crash-free to gameplay with data-resident fixes
# rendering, and the known-good backup updated to that fresh set (June-11 kept as fallback).
# See [[device-ground-truth-no-mixing]], [[game-cgo-rebuild-unsafe]], [[gmenu-ui-placement-state]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gconsolidate FAIL] $*" >&2; exit 1; }   # NOTE: do NOT auto-restore here; the phase manages device state
ok(){ echo "[Gconsolidate ok] $*"; }

R=.autoport/reports/Gconsolidate-deploy/consolidate.txt
[ -f "$R" ] || fail "no consolidate.txt (full HEAD set built+deployed, device boot->gameplay run)"
grep -qiE 'RESULT:[[:space:]]*DEVICE[[:space:]]+RUNS[[:space:]]+FRESH[[:space:]]+CONSISTENT[[:space:]]+HEAD' "$R" \
  || fail "consolidate.txt lacks RESULT: DEVICE RUNS FRESH CONSISTENT HEAD (boots, gameplay, data-fixes render)"
grep -qiE 'frame[= ]*1[0-9]{4}|gameplay' "$R" || fail "consolidate.txt must show gameplay reached (frame >= 10500)"
grep -qiE '0[[:space:]]*(sig|crash)|no[[:space:]]+(sig|crash)|crash-?free|sig\(4/6/11\)=0|sig=0' "$R" || fail "consolidate.txt must assert 0 sig(4/6/11)/Fatal across the boot->gameplay window"
grep -qiE 'menu|PART0|spread' "$R" || fail "consolidate.txt must cite the menu placement render on the fresh set"
grep -qiE 'sun|corona|24576' "$R" || fail "consolidate.txt must cite the sun render on the fresh set"
grep -qiE 'particle|vproc3d|star' "$R" || fail "consolidate.txt must cite particles/stars render on the fresh set"
ok "fresh consistent HEAD set boots->gameplay crash-free; menu/sun/particles render"

# === new known-good backup exists, consistent, June-11 kept, restore points to it ===
NEWBK=.autoport/backups/device-knowngood-cgos-20260622
[ -d "$NEWBK" ] || fail "new known-good backup dir $NEWBK missing"
N=$(ls "$NEWBK"/*.CGO "$NEWBK"/*.DGO 2>/dev/null | wc -l); [ "$N" -ge 28 ] || fail "new backup has $N CGO/DGO (expected >= 28 consistent set)"
[ -d .autoport/backups/device-knowngood-cgos-20260618 ] || fail "June-11 fallback backup was deleted (must be kept)"
grep -qE "^SRC=.*device-knowngood-cgos-20260622" .autoport/restore_knowngood_device.sh || fail "restore_knowngood_device.sh SRC does not point to the new 20260622 backup"
ok "new known-good backup (28 files) in place; June-11 fallback kept; restore points to fresh set"

# === fix-summary + golden + 1-to-1 source ===
S=.autoport/reports/Gconsolidate-deploy-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
ok "fix-summary >=60 lines; golden pristine; goal_src 1-to-1"

# === x86 unbroken + device runs fresh HEAD libgk ===
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD libgk"
ok "x86 unbroken; device runs fresh HEAD libgk"

echo "[Gconsolidate PASS] device persistently runs a fresh CONSISTENT HEAD build (28-file CGO/DGO + libgk); known-good backup refreshed (June-11 kept as fallback); menu/sun/particles render; x86 1-to-1."
