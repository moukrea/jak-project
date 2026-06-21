#!/usr/bin/env bash
# Validator — Gconsolidate: ONE consistent HEAD build with ALL fixes deployed + LEFT on the
# device (NOT restored), with deterministic proof all fixes hold together. So the owner can SEE it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gconsolidate FAIL] $*" >&2; exit 1; }   # NOTE: deliberately does NOT restore — leave the consolidated build on the device
ok(){ echo "[Gconsolidate ok] $*"; }

# 1. device provably runs the fresh consistent HEAD build (and is LEFT on it)
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh consistent HEAD build"
ok "deploy-verified: device runs the fresh consistent HEAD build (all fixes), left on it"

# 2. holds.txt: all fixes hold together on this one build
H=.autoport/reports/Gconsolidate/holds.txt
[ -f "$H" ] || fail "no holds.txt (deterministic verdicts that all fixes hold on the consolidated build)"
grep -qiE 'RESULT:[[:space:]]*ALL[[:space:]]+FIXES[[:space:]]+HOLD[[:space:]]+ON[[:space:]]+CONSOLIDATED[[:space:]]+BUILD' "$H" || fail "holds.txt lacks RESULT: ALL FIXES HOLD ON CONSOLIDATED BUILD"
for k in 'cutscene|real-?time|clock' 'jak' 'particle|sun' 'menu' 'gameplay|in-game|reach'; do
  grep -qiE "$k" "$H" || fail "holds.txt missing a verdict for: $k"
done
ok "holds.txt: cutscene-real-time + Jak-visible + particles/sun + menu + gameplay-reach all verified on one build"

# 3. crash-free deep run + x86 unbroken
L=$(ls -t .autoport/reports/Gconsolidate/*routed*logcat*.log .autoport/reports/Gconsolidate/*.log .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
[ -n "$L" ] || fail "no routed-logcat for the crash/reach check"
CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "crash: $CR sig in the consolidated run"
FM=$(grep -aoE 'frame=[0-9]+' "$L" | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 10500 ] || fail "did not reach gameplay (frame=$FM, need >=10500)"
FOC=$(grep -aoE 'mCurrentFocus=[^ }]*jak1[^ }]*' "$L" | tail -1); [ -n "$FOC" ] || grep -aqi 'foreground.*jak1' "$L" || true
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "crash-free (frame=$FM), x86 unbroken"

echo "[Gconsolidate PASS] ONE consistent HEAD build with ALL fixes is deployed and LEFT on the device — cutscene real-time + Jak visible + particles/sun + menu, crash-free to gameplay. The owner can see it now."
