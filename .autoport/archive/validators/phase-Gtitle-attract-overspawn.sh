#!/usr/bin/env bash
# Phase Gtitle validator — remove the spurious "Press CIRCLE to use" over-spawn
# in the title attract. Gates: crash-free, attract markers, regression; whether
# the prompt is actually gone = supervisor eyes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GSPRITE_CLOSE=$(git log --format=%H --all --grep='Gsprite-arm64-sparticle-mips2c-unnoop' | head -1)
ANCHOR=${GSPRITE_CLOSE:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gtitle validator (attract over-spawn / use-prompt removal) =="

# 1. Forbidden edits
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ modified since Gref (read-only)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat — no blanket prompt suppression
SUPPRESS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.gc' 2>/dev/null | grep -ciE '^\+.*(disable.*all.*prompt|never.*draw.*prompt|skip.*button-prompt|hide.*hud.*always)' || true)
[ "$SUPPRESS" -eq 0 ] || fail "blanket prompt-suppression hack ($SUPPRESS) — fix the root over-spawn, not a global mute"
ok "anti-cheat clean (no blanket suppression)"

# 3. Report — names the spurious process + pristine diff
[ -f .autoport/reports/Gtitle-fix-summary.md ] || fail "no Gtitle-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gtitle-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gtitle-fix-summary.md too short ($LINES)"
grep -qiE 'attract|over.spawn|use|prompt|interactable|process|pristine' .autoport/reports/Gtitle-fix-summary.md || fail "summary doesn't engage the attract over-spawn"
ok "Gtitle fix-summary present ($LINES lines)"

# 4. x86 smoke + qemu
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gtitle-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gtitle-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 5. Device screencap
SHOT=$(ls .autoport/reports/Gtitle-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gtitle-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 6. THE GATE — crash-free, attract reached, title still flies
NEWLOG=$(ls -t .autoport/reports/Gtitle-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gtitle routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (regression)"
grep -aqiE 'logo-loop|target-title|logo-intro' "$NEWLOG" || fail "no attract markers — boot didn't reach the title attract"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
ok "crash-free, attract reached, frame=$FM"

# 7. Focus held
NF=$(ls -t .autoport/reports/Gtitle-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gtitle-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gtitle — attract crash-free (frame=$FM), title flies. Supervisor pixel-judges the 'Press CIRCLE to use' prompt is gone across the attract."
