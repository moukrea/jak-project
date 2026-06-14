#!/usr/bin/env bash
# Phase Gndlogo validator — the device ND-logo beat must PIXEL-MATCH the original
# golden (2400x1080, touch-overlay masked). OBJECTIVE: the validator runs
# frame_compare itself. No eyeballing. Anti-cheat: the mask must NOT hide the
# logo region (golden-vs-black WITH the mask must still MISMATCH).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
FC="python3 .autoport/lib/frame_compare.py"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gndlogo validator (objective pixel-match of the ND-logo beat) =="

# 0. Gate tool present (Pcompare built it).
[ -f .autoport/lib/frame_compare.py ] || fail "frame_compare.py missing (Pcompare gate gone)"

# 1. Forbidden edits.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|nd_logo_png|fake_intro)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded intro ($FAKE)"
ok "no forbidden/faked edits"

# 2. 2400x1080 goldens exist.
GF=.autoport/gold/pristine-frames-2400/intro-ndlogo-full.png
GE=.autoport/gold/pristine-frames-2400/intro-ndlogo-enter.png
for g in "$GF" "$GE"; do [ -f "$g" ] || fail "missing 2400 golden: $g"; [ "$(identify -format '%wx%h' "$g" 2>/dev/null)" = "2400x1080" ] || fail "$g not 2400x1080 (got $(identify -format '%wx%h' "$g" 2>/dev/null))"; done
ok "2400x1080 ndlogo goldens present"

# 3. Mask supplied as DATA (not code) + anti-cheat: mask must not hide the content.
MASK=.autoport/reports/Gndlogo/mask.txt
[ -f "$MASK" ] || fail "no .autoport/reports/Gndlogo/mask.txt (overlay-mask args for frame_compare)"
MARGS=$(grep -vE '^\s*#' "$MASK" | tr '\n' ' ')
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
D=$(identify -format '%wx%h' "$GF"); magick -size "$D" xc:black "$TMP/black.png" 2>/dev/null || fail "imagemagick missing"
# self-test WITH mask: identical -> MATCH
$FC "$GF" "$GF" $MARGS >/dev/null 2>&1 || fail "masked self-test: golden-vs-itself reported MISMATCH (broken)"
# anti-cheat: golden-vs-black WITH mask must still MISMATCH (mask doesn't cover the logo)
if $FC "$GF" "$TMP/black.png" $MARGS >/dev/null 2>&1; then fail "mask hides the content region (golden-vs-black MATCHES with mask) — mask too aggressive / gamed"; fi
ok "masked compare self-tests correctly (mask leaves logo region visible)"

# 4. THE OBJECTIVE GATE — device ND-logo beats must MATCH the goldens (masked).
DF=.autoport/reports/Gndlogo/device-ndlogo-full.png
DE=.autoport/reports/Gndlogo/device-ndlogo-enter.png
for d in "$DF" "$DE"; do [ -f "$d" ] || fail "missing device capture: $d"; [ "$(stat -c %s "$d" 2>/dev/null||echo 0)" -gt 1000 ] || fail "$d empty"; done
$FC "$DF" "$GF" $MARGS; R=$?; echo "  device-full vs golden -> exit $R"; [ "$R" -eq 0 ] || fail "ND-logo FULL beat does NOT match original (MISMATCH)"
$FC "$DE" "$GE" $MARGS; R=$?; echo "  device-enter vs golden -> exit $R"; [ "$R" -eq 0 ] || fail "ND-logo ENTER beat does NOT match original (MISMATCH)"
ok "device ND-logo beats PIXEL-MATCH the original (masked, 2400x1080)"

# 5. x86 oracle still boots.
SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 smoke passes"

# 6. Device run regression: no crash, sustained, focus, village renders (anti-deadlock).
NEWLOG=$(ls -t .autoport/reports/Gndlogo-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gndlogo routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}; [ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}; [ "$TR" -ge 200000 ] || fail "village not rendering (max tris=$TR <200k) — deadlock regression"
NF=$(ls -t .autoport/reports/Gndlogo-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gndlogo-focus-*.txt"; grep -a . "$NF" | tail -1 | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "no regression (frame=$FM, tris=$TR, focus held)"

# 7. Oracle left pristine + summary.
[ -z "$(git -C /home/emeric/code/jak-original-v033 status --porcelain 2>/dev/null | head -3)" ] || fail "oracle repo left modified"
[ -f .autoport/reports/Gndlogo-fix-summary.md ] || fail "no Gndlogo-fix-summary.md"
[ "$(wc -l < .autoport/reports/Gndlogo-fix-summary.md)" -ge 80 ] || fail "fix-summary too short"
ok "oracle pristine + summary present"

echo ""
echo "PASS: Phase Gndlogo — the device ND-logo beat OBJECTIVELY pixel-matches the original on black (masked, 2400x1080), no regression."
