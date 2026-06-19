#!/usr/bin/env bash
# Validator — Gcine-cut: the cinematic camera must CUT between plans (not interpolate),
# verified by DETERMINISTIC camera-plan transition DUMPS compared x86-FIRST — not screenshots.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcine-cut FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcine-cut ok] $*"; }

[ -z "$(cd /home/emeric/code/jak-original-v033 2>/dev/null && git status --porcelain 2>/dev/null)" ] || fail "original golden (jak-original-v033) was modified — remove temp instrumentation, keep pristine"

# 1. x86-first camera-plan transition dump: our-x86 cut/interp pattern == original
X=.autoport/reports/Gcine-cut/state-dump-x86.txt
[ -f "$X" ] || fail "no state-dump-x86.txt (dump+diff our-x86 camera-plan CUT/INTERP sequence vs original-x86 FIRST)"
grep -qiE 'RESULT:[[:space:]]*X86[[:space:]]+MATCHES[[:space:]]+ORIGINAL' "$X" || fail "our-x86 camera cut/interp pattern does NOT match the original"
grep -qiE 'cut|interp|plan|boundary|camera|jump' "$X" || fail "state-dump-x86.txt lacks the per-boundary cut/interp data"

# 2. device camera-plan transitions match original
D=.autoport/reports/Gcine-cut/state-dump-device.txt
[ -f "$D" ] || fail "no state-dump-device.txt (dump+diff DEVICE camera cut/interp sequence vs original)"
grep -qiE 'RESULT:[[:space:]]*CAMERA[[:space:]]+CUTS[[:space:]]+MATCH[[:space:]]+ORIGINAL' "$D" || fail "device camera cuts do NOT match the original"
grep -qiE 'cut|interp|plan|boundary|camera' "$D" || fail "state-dump-device.txt lacks the device cut/interp data"
ok "camera cut/interp pattern matches the original (x86 + device), deterministic dump"

# 3. fix-summary + real code change + dumps removed
S=.autoport/reports/Gcine-cut-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "Gcine-cut-fix-summary.md missing or <60 lines"
grep -qiE 'remov|deleted|reverted.*dump|dump.*removed|no leftover' "$S" || fail "fix-summary must confirm dump instrumentation REMOVED"
git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | grep -q . || git status --porcelain 2>/dev/null | grep -qE 'goal_src/|game/' || fail "no real code change under goal_src/** or game/**"

# 4. x86 boots + deploy + cinematic still crash-free deep
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
L=$(ls -t .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then
  CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash regression: $CR sig"
  FM=$(grep -aoE 'frame=[0-9]+' "$L" | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 10500 ] || fail "cinematic/gameplay reach regressed: frame=$FM"
fi
ok "x86 boots; device runs fresh HEAD; cinematic crash-free + reaches gameplay"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcine-cut PASS] cinematic camera now CUTS between plans like the original (x86==original, device==original cut/interp pattern), crash-free. Verified by deterministic dumps, not screenshots. Known-good restored."
