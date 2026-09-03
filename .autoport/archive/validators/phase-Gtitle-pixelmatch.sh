#!/usr/bin/env bash
# Phase Gtitle validator — the device title ("PRESS START") beat must PIXEL-MATCH
# the original golden (2400x1080, overlay-masked, cross-GPU-calibrated threshold).
# OBJECTIVE: the validator runs frame_compare itself. Includes a Gndlogo
# no-regression re-check. Supervisor still scrutinizes the diff image + threshold.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
FC="python3 .autoport/lib/frame_compare.py"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
echo "== Phase Gtitle validator (objective pixel-match of the title beat) =="

[ -f .autoport/lib/frame_compare.py ] || fail "frame_compare.py missing"

# 1. Forbidden edits.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 edited"
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|fake_)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded title ($FAKE)"
ok "no forbidden/faked edits"

# 2. 2400x1080 golden.
GT=.autoport/gold/pristine-frames-2400/title-pressstart.png
[ -f "$GT" ] || fail "missing 2400 golden: $GT"
[ "$(identify -format '%wx%h' "$GT" 2>/dev/null)" = "2400x1080" ] || fail "$GT not 2400x1080"
ok "2400x1080 title golden present"

# 3. Mask/threshold as DATA + anti-cheat (mask must not hide content).
MASK=.autoport/reports/Gtitle/mask.txt
[ -f "$MASK" ] || fail "no .autoport/reports/Gtitle/mask.txt"
MARGS=$(grep -vE '^\s*#' "$MASK" | tr '\n' ' ')
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
D=$(identify -format '%wx%h' "$GT"); magick -size "$D" xc:black "$TMP/black.png" 2>/dev/null || fail "imagemagick missing"
$FC "$GT" "$GT" $MARGS >/dev/null 2>&1 || fail "masked self-test: golden-vs-itself MISMATCH (broken)"
if $FC "$GT" "$TMP/black.png" $MARGS >/dev/null 2>&1; then fail "mask/threshold hides content (golden-vs-black MATCHES) — gamed"; fi
ok "masked compare self-tests correctly (content not hidden)"

# 4. OBJECTIVE GATE — device title beat matches golden (masked).
DT=.autoport/reports/Gtitle/device-title.png
[ -f "$DT" ] || fail "missing device capture: $DT"
[ "$(stat -c %s "$DT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "$DT empty"
$FC "$DT" "$GT" $MARGS; R=$?; echo "  device-title vs golden -> exit $R"; [ "$R" -eq 0 ] || fail "title beat does NOT match original (MISMATCH)"
ok "device title beat PIXEL-MATCHES the original (masked, 2400x1080)"

# 5. NO REGRESSION on Gndlogo (the ND-logo beat must still match its golden).
NDF=.autoport/reports/Gndlogo/device-ndlogo-full.png; NGF=.autoport/gold/pristine-frames-2400/intro-ndlogo-full.png; NMASK=.autoport/reports/Gndlogo/mask.txt
if [ -f "$NDF" ] && [ -f "$NGF" ] && [ -f "$NMASK" ]; then NMARGS=$(grep -vE '^\s*#' "$NMASK" | tr '\n' ' '); $FC "$NDF" "$NGF" $NMARGS >/dev/null 2>&1 || fail "REGRESSION: Gndlogo ND-logo beat no longer matches its golden"; ok "Gndlogo ND-logo beat still matches (no regression)"; else echo "  warn: Gndlogo artifacts absent — cannot re-check"; fi

# 6. x86 smoke.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 7. Device run regression.
NEWLOG=$(ls -t .autoport/reports/Gtitle-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gtitle routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}; [ "$TR" -ge 200000 ] || fail "village not rendering (tris=$TR)"
NF=$(ls -t .autoport/reports/Gtitle-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gtitle-focus-*.txt"; grep -a . "$NF" | tail -1 | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "no regression (frame=$FM, tris=$TR, focus held)"

# 8. Oracle pristine + summary.
[ -z "$(git -C /home/emeric/code/jak-original-v033 status --porcelain 2>/dev/null | head -3)" ] || fail "oracle repo left modified"
[ -f .autoport/reports/Gtitle-fix-summary.md ] || fail "no Gtitle-fix-summary.md"
[ "$(wc -l < .autoport/reports/Gtitle-fix-summary.md)" -ge 80 ] || fail "fix-summary too short"
ok "oracle pristine + summary present"

echo ""
echo "PASS: Phase Gtitle — device title beat OBJECTIVELY pixel-matches the original (masked, 2400x1080), no regression. Supervisor scrutinizes diff image + threshold."
