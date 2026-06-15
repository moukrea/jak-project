#!/usr/bin/env bash
# Phase Gmenu validator — diagnose-first (prove the aspect theory) + fix the menu.
# Gates the AUTONOMOUSLY-verifiable core: original menu golden captured, the x86
# menu matches the original (true whether the bug was shared-code [fix made it
# match] or Android-specific [x86 was always correct]), the aspect-test verdict
# documented, and intro->title regression on a FRESH device boot. The DEVICE menu
# pixel-match is supervisor+OWNER verified (owner presses START) — not gated here.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
FC="python3 .autoport/lib/frame_compare.py"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gmenu validator (menu pixel-match; diagnose-first) =="

[ -f .autoport/lib/frame_compare.py ] || fail "frame_compare.py missing"

# 1. Forbidden edits.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|fake_menu)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded menu ($FAKE)"
ok "no forbidden/faked edits"

# 2. Original menu golden captured (2400x1080).
GM=.autoport/gold/pristine-frames-2400/main-menu.png
[ -f "$GM" ] || fail "missing original menu golden: $GM"
[ "$(identify -format '%wx%h' "$GM" 2>/dev/null)" = "2400x1080" ] || fail "$GM not 2400x1080"
ok "original menu golden present (2400x1080)"

# 3. fix-summary documents the owner's x86-reproduction verdict + cause + fix + device status.
SUM=.autoport/reports/Gmenu-fix-summary.md
[ -f "$SUM" ] || fail "no Gmenu-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 80 ] || fail "fix-summary too short"
grep -qiE 'x86.*(reproduc|menu)|aspect|verdict' "$SUM" || fail "summary lacks the x86-reproduction (aspect) verdict"
grep -qiE 'root cause|because|mechanism' "$SUM" || fail "summary lacks a root-cause diagnosis"
grep -qiE 'device.*(owner|start|pending|verif)' "$SUM" || fail "summary must state the device-menu verification status (owner START)"
ok "fix-summary documents verdict + cause + device status"

# 4. The x86 menu matches the original golden (autonomous, holds in both cases).
XM=.autoport/reports/Gmenu/x86-menu.png
[ -f "$XM" ] || fail "no .autoport/reports/Gmenu/x86-menu.png (the owner's empirical-test capture)"
MARGS=""; [ -f .autoport/reports/Gmenu/mask.txt ] && MARGS=$(grep -vE '^\s*#' .autoport/reports/Gmenu/mask.txt | tr '\n' ' ')
$FC "$XM" "$GM" $MARGS; R=$?; echo "  x86-menu vs original -> exit $R"; [ "$R" -eq 0 ] || fail "x86 menu does NOT match the original (fix incomplete, or x86 reproduces the garble unfixed)"
ok "x86 menu matches the original (shared-code path correct)"

# 5. x86 smoke.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 6. NO REGRESSION on a FRESH device boot: intro->title beats still match goldens.
RN=.autoport/reports/Gmenu/regress-ndlogo-full.png; RT=.autoport/reports/Gmenu/regress-title.png
NGF=.autoport/gold/pristine-frames-2400/intro-ndlogo-full.png; TGF=.autoport/gold/pristine-frames-2400/title-pressstart.png
NMASK=.autoport/reports/Gndlogo/mask.txt; TMASK=.autoport/reports/Gtitle/mask.txt
[ -f "$RN" ] || fail "no fresh device regress-ndlogo-full.png (must re-verify intro after the menu fix)"
[ -f "$RT" ] || fail "no fresh device regress-title.png"
$FC "$RN" "$NGF" $(grep -vE '^\s*#' "$NMASK" 2>/dev/null|tr '\n' ' ') >/dev/null 2>&1 || fail "REGRESSION: ND-logo beat no longer matches after the menu fix"
$FC "$RT" "$TGF" $(grep -vE '^\s*#' "$TMASK" 2>/dev/null|tr '\n' ' ') >/dev/null 2>&1 || fail "REGRESSION: title beat no longer matches after the menu fix"
ok "intro->title still pixel-match on fresh device boot (no regression)"

# 7. Device boot health + oracle pristine.
NEWLOG=$(ls -t .autoport/reports/Gmenu-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gmenu routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
[ -z "$(git -C /home/emeric/code/jak-original-v033 status --porcelain 2>/dev/null | head -3)" ] || fail "oracle repo left modified"
ok "device boot healthy (frame=$FM), oracle pristine"

echo ""
echo "PASS(autonomous core): Gmenu — original menu golden captured, x86 menu matches original, aspect-verdict documented, intro->title no regression. SUPERVISOR+OWNER must verify the DEVICE menu (owner presses START)."
