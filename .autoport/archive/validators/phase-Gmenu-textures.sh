#!/usr/bin/env bash
# Validator — Gmenu-textures: EVERY main-menu 2D element must be placed correctly on device (not
# bunched to center), proven by a FULL per-element X/Y dump (NEVER pixels), our-x86==original. Must
# name the previously-missed bunched element class. See [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gmenu-tex FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gmenu-tex ok] $*"; }

R=.autoport/reports/Gmenu-textures/menu.txt
[ -f "$R" ] || fail "no menu.txt (FULL menu draw list X/Y dump, 3-way)"
grep -qiE 'RESULT:[[:space:]]*ALL[[:space:]]+MENU[[:space:]]+ELEMENTS[[:space:]]+PLACED[[:space:]]+CORRECTLY' "$R" \
  || fail "menu.txt lacks RESULT: ALL MENU ELEMENTS PLACED CORRECTLY (device, full draw list matches original)"
grep -qiE 'original.?x86|gold' "$R" || fail "menu.txt must include the original-x86 baseline"
grep -qiE 'our.?x86|build.?x86' "$R" || fail "menu.txt must include the our-x86 dump"
grep -qiE 'device|eae4df44' "$R" || fail "menu.txt must include the device dump"
grep -qiE '2400|1080|ultrawide|aspect' "$R" || fail "menu.txt must record the 2400x1080 measurement"
grep -qiE 'x=|y=|pos|coord' "$R" || fail "menu.txt must dump per-element X/Y positions"
# must cover MORE than the PART panels the prior false-green measured
grep -qiE 'icon|texture|sprite|string|draw-string|hud|all|every|full.*list|element' "$R" || fail "menu.txt must enumerate the full menu draw list (icons/textures/strings), not just PART panels"
grep -qiE 'bunch|cluster|center|missed|previously' "$R" || fail "menu.txt must name the previously-missed bunched element class"
grep -qiE 'matrix|user-hvdf|lc_matrix|part.matrix' "$R" || fail "menu.txt must show the user-hvdf/part-matrix evidence (the converged root cause)"
grep -qiE 'our.?x86 *(==|=|matches|identical).*orig|1-?to-?1|identical' "$R" || fail "menu.txt must show our-x86 == original-x86 (1-to-1)"
grep -qiE 'before|baseline' "$R" || fail "menu.txt must document the calibrated BEFORE (matrix=0 / element bunched)"
grep -qiE 'after' "$R" || fail "menu.txt must document the AFTER (matrix>0 / element matches original spread)"
ok "FULL menu draw list dumped; part-matrix root cause shown; device BEFORE->AFTER matches original"

# === ZERO goal_src edits (menu source is 1-to-1; fix is in the translation layer) ===
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
SRC=$(echo "$SRC" | grep -vE '^\s*$' | sort -u || true)
[ -z "$SRC" ] || fail "FORBIDDEN goal_src edit(s) — menu source is byte-identical to original; fix in goalc/game/mips2c/android: $SRC"
ok "no goal_src edits (menu source 1-to-1; fix in translation layer)"
# the fix must be a real translation-layer change
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no translation-layer code change (the matrix fix)"

# === fix-summary + golden pristine ===
S=.autoport/reports/Gmenu-textures-fix-summary.md
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
echo "[Gmenu-tex PASS] every device menu element placed correctly (full-draw-list verified, no pixels); our-x86==original."
