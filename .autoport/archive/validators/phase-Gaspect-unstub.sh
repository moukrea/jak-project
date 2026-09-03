#!/usr/bin/env bash
# Phase Gaspect-unstub validator — GLOBAL Android aspect-enum fix.
# DATA-GATED (no screenshot/video grind — that filled the disk + wasted tokens):
# the gate is the on-device aspect ENUM resolving widescreen + no-crash + x86
# smoke. The menu/title VISUAL is OWNER-verified by eye on single static frames.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gaspect-unstub validator (DATA-gated global aspect fix) =="

# 1. Forbidden edits + ANTI-GRIND (no video recording / frame-pool intermediates).
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
BIGV=$(find .autoport/reports -name '*.mp4' -size +20M 2>/dev/null | wc -l)
[ "$BIGV" -eq 0 ] || fail "ANTI-GRIND: $BIGV large .mp4 recordings present — screenshot/video grind is FORBIDDEN (it filled the disk). Use data gates."
DFREE=$(df --output=avail -BG . 2>/dev/null | tail -1 | tr -dc '0-9'); [ "${DFREE:-99}" -ge 5 ] || fail "disk nearly full (${DFREE}G free) — clean intermediates"
ok "no forbidden edits; no video-grind; disk ok (${DFREE}G free)"

# 2. fix-summary documents the GLOBAL fix (must touch the aspect SOURCE, not just title-obs.gc).
SUM=.autoport/reports/Gaspect-unstub-fix-summary.md
[ -f "$SUM" ] || fail "no Gaspect-unstub-fix-summary.md"
[ "$(wc -l < "$SUM")" -ge 60 ] || fail "fix-summary too short"
grep -qiE 'scf-get-aspect|sceScfGetAspect|settings|aspect-ratio|aspect16x9' "$SUM" || fail "summary doesn't engage the global aspect source"
# The global fix must change more than title-obs.gc (the per-screen patch alone is NOT the global fix).
NONTITLE=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 'game/**' 2>/dev/null | grep -vE 'levels/title/title-obs.gc' | wc -l)
[ "$NONTITLE" -ge 1 ] || fail "only title-obs.gc changed — the GLOBAL aspect source fix (settings/scf-get-aspect) is missing"
ok "fix-summary + global aspect-source change present"

# 3. THE DATA GATE — on-device aspect enum resolves WIDESCREEN (not 4:3).
# The phase must add a boot log marker, e.g. printf the aspect-ratio enum so the
# validator can read it from the routed logcat. Accept 16x9/widescreen markers.
NEWLOG=$(ls -t .autoport/reports/Gaspect-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gaspect routed logcat"
grep -aqiE 'aspect.?ratio.*(16x9|16:9|widescreen)|GASPECT-DIAG.*aspect=16x9|set-aspect-ratio.*aspect16x9' "$NEWLOG" || fail "device aspect enum NOT confirmed widescreen in logcat (add a boot marker logging the enum; it must read aspect16x9)"
grep -aqiE 'aspect.?ratio.*aspect4x3|GASPECT-DIAG.*aspect=4x3' "$NEWLOG" && fail "device still resolves aspect4x3 — the global fix did not take" || true
ok "on-device aspect enum = widescreen (data-confirmed)"

# 4. No crash, boot sustained (the fix must not break boot).
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}; [ "$TR" -gt 0 ] || fail "renderer draws nothing"
ok "no crash, boot sustained (frame=$FM, tris=$TR)"

# 5. x86 unbroken.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 6. Static evidence frames for the OWNER's eye (single screencaps, NOT phase-matched grind).
NM=$(ls .autoport/reports/Gaspect/menu-*.png 2>/dev/null | head -1); [ -n "$NM" ] || fail "no static menu screencap for owner eye-verify (.autoport/reports/Gaspect/menu-*.png)"
ok "static menu evidence frame present: $(basename "$NM")"

echo ""
echo "PASS(data-gated): Gaspect-unstub — on-device aspect enum = widescreen, no crash, x86 OK. OWNER eye-verifies the menu/title look correct (no 4:3 garble) on the deployed build."
