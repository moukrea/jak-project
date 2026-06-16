#!/usr/bin/env bash
# Phase Gmenu-ui-placement validator — open diagnosis+fix of the menu UI bunching
# center on the device's ultrawide panel. NO assumed cause. Gates MECHANICS +
# evidence (no crash, x86 OK, real placement change, open-diagnosis summary, a
# static menu frame). The UI placement itself is OWNER-verified by eye.
# Hard ANTI-GRIND: no video/frame-pool intermediates (they filled the disk).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gmenu-ui-placement validator (open UI-placement fix; owner eye-verifies) =="

# 1. Forbidden edits + anti-grind + disk.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l); [ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4 present (screenshot/video grind forbidden — it filled the disk)"
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk nearly full (${DFREE}G)"
ok "no forbidden edits; no video-grind; disk ok (${DFREE}G)"

# 2. Open-diagnosis fix-summary (documents the cause, NOT presuming aspect-enum) + a real placement change.
SUM=.autoport/reports/Gmenu-ui-placement-fix-summary.md
[ -f "$SUM" ] || fail "no Gmenu-ui-placement-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'adjust-ratios|placement|ultrawide|20:9|21:9|aspect|center|layout' "$SUM" || fail "summary doesn't engage the UI placement diagnosis"
grep -qiE 'x86|original|pristine|20:9|2400x1080|same window|wide' "$SUM" || fail "summary lacks the decisive x86/original-at-20:9 comparison (does the original center it too?)"
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | wc -l); [ "$CHG" -ge 1 ] || fail "no UI/placement code change landed"
ok "open-diagnosis summary (+ x86@20:9 comparison) + a real placement change"

# 3. No crash / boot sustained / x86 unbroken.
NEWLOG=$(ls -t .autoport/reports/Gmenu-ui-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gmenu-ui routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}; [ "$TR" -gt 0 ] || fail "renderer draws nothing"
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "no crash (frame=$FM, tris=$TR), x86 smoke passes"

# 4. Static menu evidence frame for the owner's eye.
NM=$(ls .autoport/reports/Gmenu-ui/menu-*.png 2>/dev/null | head -1); [ -n "$NM" ] || fail "no static menu screencap (.autoport/reports/Gmenu-ui/menu-*.png) for owner eye-verify"
ok "static menu evidence frame present: $(basename "$NM")"

# 5. DEPLOY-LANDING GUARD (mandatory) — the device must provably run the fresh
# HEAD libgk.so, so a stale/incremental build can NEVER silently pass again.
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device is NOT running the fresh HEAD libgk.so (stale/un-landed build); rebuild CLEAN + reinstall"
ok "deploy-landing verified (device runs fresh HEAD build)"

echo ""
echo "PASS(mechanics): Gmenu-ui-placement — open diagnosis + real placement fix, no crash, x86 OK, no grind. OWNER eye-verifies the menu UI is placed correctly (not bunched center) on the deployed build."
