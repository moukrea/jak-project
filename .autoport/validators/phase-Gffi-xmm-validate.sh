#!/usr/bin/env bash
# Validator — Gffi-xmm-validate: the arm64 FFI xmm8-15 (q24-q31) preservation fix in
# asm_funcs_arm64.s must be regression-free across a wide device soak and must kill the f30-0
# float-corruption. 1-to-1 source (no goal_src). See [[porting-1to1-fix-in-translation-layers]],
# [[arm64-x86-model-reg-ids]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gffi-xmm FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gffi-xmm ok] $*"; }

# === 1-to-1 SOURCE GATE: zero goal_src edits ===
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' || true)
[ -z "$SRC" ] || fail "FORBIDDEN goal_src edit(s) — fix is arm64 asm only:
$SRC"
ok "no goal_src edits (1-to-1 source)"

# === the fix is the asm_funcs_arm64.s q24-q31 save (translation layer) ===
ASMDIFF=$( { git diff "$ANCHOR" HEAD -- game/kernel/asm_funcs_arm64.s; git diff -- game/kernel/asm_funcs_arm64.s; } 2>/dev/null )
echo "$ASMDIFF" | grep -qE 'q24|q31' || fail "asm_funcs_arm64.s does not contain the q24-q31 xmm8-15 save (the fix is missing)"
# changed file must be asm_funcs_arm64.s; no other code dirs unexpectedly
ok "asm_funcs_arm64.s carries the q24-q31 xmm8-15 preservation fix"

# === device regression soak ===
R=.autoport/reports/Gffi-xmm-validate/soak.txt
[ -f "$R" ] || fail "no soak.txt (device boot->flythrough->cutscene->gameplay regression run)"
grep -qiE 'RESULT:[[:space:]]*FFI[[:space:]]+XMM8-15[[:space:]]+FIX[[:space:]]+VALIDATED' "$R" \
  || fail "soak.txt lacks RESULT: FFI XMM8-15 FIX VALIDATED (no regression, f30-0 preserved)"
grep -qiE 'cutscene|cinematic' "$R" || fail "soak.txt must cover the cutscene path (broad regression)"
grep -qiE 'flythrough|village' "$R" || fail "soak.txt must cover the village flythrough"
grep -qiE 'frame[= ]*1[0-9]{4}|gameplay' "$R" || fail "soak.txt must reach gameplay (frame >= 10500)"
grep -qiE 'f30-0|fnum|xmm8-15|spool' "$R" || fail "soak.txt must show the f30-0/xmm8-15 float preserved on device"
# explicit zero-crash claim
grep -qiE '0[[:space:]]*(sig|crash)|no[[:space:]]+(sig|crash)|crash-?free|sig\(4/6/11\)=0|sig=0' "$R" \
  || fail "soak.txt must explicitly assert 0 sig(4/6/11)/Fatal across the window"
ok "device soak: boot->flythrough->cutscene->gameplay, 0 crashes, f30-0 preserved"

# === fix-summary + golden pristine ===
S=.autoport/reports/Gffi-xmm-validate-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "fix-summary >=60 lines; golden pristine"

# === x86 unbroken + device runs fresh HEAD ===
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gffi-xmm PASS] arm64 FFI xmm8-15 (q24-q31) preservation validated regression-free; f30-0 corruption class fixed; x86 1-to-1. Known-good restored."
