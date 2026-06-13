#!/usr/bin/env bash
# Phase Gintro validator — pre-title intro (SCE static screen + ND/Daxter logo)
# must RENDER. The states already execute (gold-standard boot diff confirmed);
# this phase fixes the GLES draw path. Hard gates: title-regression + intro
# markers + evidence. Render correctness is supervisor-eye-judged.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

G1_CLOSE=$(git log --format=%H --all --grep='G1-arm64-go-enterstate-oracle-correct' | head -1)
ANCHOR=${G1_CLOSE:-HEAD}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gintro validator (SCE + ND/Daxter logo render) =="

# 1. Forbidden edits — state chain is correct; fix the renderer, not goal_src/oracle.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (the title state chain is pristine-correct — fix the renderer)"
# Gold reference is immutable SINCE IT WAS CREATED (by Gref, after G1). Anchor on
# Gref's close, not G1's — else the whole .autoport/gold/ dir reads as "added"
# and always false-fails (supervisor fix 2026-06-13, flagged by Gintro attempt 1).
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1)
GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ (gold reference) modified since Gref — it is read-only ground truth"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat — no painted/hardcoded intro screens
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true); [ "$WEAK" -eq 0 ] || fail "weak symbol additions"
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|test_pattern|sce_screen_png|nd_logo_png)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious hardcoded/painted intro image ($FAKE) — the SCE/ND screens must render from the real draws"
ok "anti-cheat clean"

# 3. Required report — must engage the intro render path + the oracle/3-tier diff
[ -f .autoport/reports/Gintro-fix-summary.md ] || fail "no Gintro-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gintro-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gintro-fix-summary.md too short ($LINES)"
grep -qiE 'static-screen|ndi|ndi-cam|sce' .autoport/reports/Gintro-fix-summary.md || fail "summary doesn't engage the SCE/ndi intro render path"
grep -qiE 'tier|oracle|pristine|compare-3tier|render.*diff|bucket|camera|texture' .autoport/reports/Gintro-fix-summary.md || fail "summary shows no render-path diff vs the working logo path / gold"
ok "Gintro fix-summary present ($LINES lines)"

# 4. x86 smoke + qemu (no regression)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gintro-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gintro-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N (>=675)"; fi

# 5. Renderer present
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1); [ -n "$LIBGK" ] || fail "no libgk.so"
NMF=$(mktemp); nm -C "$LIBGK" > "$NMF" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NMF" 2>/dev/null || true
[ "$(grep -c DirectRenderer "$NMF")" -ge 5 ] || { rm -f "$NMF"; fail "DirectRenderer missing"; }; rm -f "$NMF"
ok "renderer present"

# 6. Device screencap
SHOT=$(ls .autoport/reports/Gintro-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gintro-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 7. TITLE-REGRESSION GATE + intro markers in newest boot
NEWLOG=$(ls -t .autoport/reports/Gintro-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gintro routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true)
[ "${CR:-0}" -eq 0 ] || fail "title/boot CRASHES: $CR sig=11 (regression — G1's stable title must hold)"
grep -aqiE 'ndi-intro|ndi\b' "$NEWLOG" || fail "no ndi (ND logo) markers in boot — the intro state must run"
grep -aqiE 'logo-intro|logo-loop' "$NEWLOG" || fail "no logo markers in boot"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
ok "boot crash-free, intro markers present, frame=$FM"

# 8. Focus held
NF=$(ls -t .autoport/reports/Gintro-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gintro-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gintro — boot crash-free with intro states running (frame=$FM). Supervisor judges whether the SCE screen + ND/Daxter logo actually RENDER, in order, on the early/mid frames."
