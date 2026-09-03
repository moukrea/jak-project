#!/usr/bin/env bash
# Phase Gsprite validator — un-noop the arm64 sparticle sprite-DMA builders so
# the SCE 'presents' screen (and screen-space sprites) render. Gate: crash-free,
# SCE markers, sprite bucket non-empty in the SCE window. Visibility = my eyes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GSCE_CLOSE=$(git log --format=%H --all --grep='Gsce-first-frames-presents-screen' | head -1)
ANCHOR=${GSCE_CLOSE:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gsprite validator (un-noop arm64 sparticle sprite-DMA builders) =="

# 1. Forbidden edits
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (pristine-correct)"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ modified since Gref (read-only)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat — no painted SCE, no fake noop
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|sce_png|sony_png)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded SCE image ($FAKE)"
# The fix must ADD to the allowlist (bind real code), not just print a marker.
[ "$(git diff "$ANCHOR" HEAD -- game/mips2c/mips2c_table_jak1_arm64.cpp 2>/dev/null | grep -cE '^\+' || true)" -ge 1 ] || fail "mips2c_table_jak1_arm64.cpp not changed — the un-noop must bind the sparticle builders"
ok "anti-cheat clean; mips2c allowlist changed"

# 3. Report
[ -f .autoport/reports/Gsprite-fix-summary.md ] || fail "no Gsprite-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gsprite-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gsprite-fix-summary.md too short ($LINES)"
grep -qiE 'sparticle|sp-launch-particles|mips2c|allowlist|noop' .autoport/reports/Gsprite-fix-summary.md || fail "summary doesn't engage the sparticle/mips2c-allowlist fix"
ok "Gsprite fix-summary present ($LINES lines)"

# 4. x86 smoke + qemu
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gsprite-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gsprite-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 5. Device screencap
SHOT=$(ls .autoport/reports/Gsprite-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gsprite-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 6. THE GATE — crash-free, SCE markers, sprite bucket non-empty in the SCE window
NEWLOG=$(ls -t .autoport/reports/Gsprite-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gsprite routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (un-noop'd a broken builder, or regression)"
grep -aqiE 'static-screen|GSCE-SCE|SCE.*presents' "$NEWLOG" || fail "no SCE static-screen markers"
# Sprite bucket must now build: tris in the early window must exceed the empty
# baseline (~4). Use the run's max tris as a proxy the renderer drew real sprites.
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}
[ "$TR" -gt 100 ] || fail "sprite bucket still ~empty (max tris=$TR) — the sparticle builders aren't producing sprite DMA"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
ok "crash-free, SCE markers, tris=$TR, frame=$FM"

# 7. Focus held
NF=$(ls -t .autoport/reports/Gsprite-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gsprite-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gsprite — sparticle builders un-noop'd, sprite bucket builds (tris=$TR), crash-free. Supervisor pixel-judges the SCE 'presents' screen in the first frames."
