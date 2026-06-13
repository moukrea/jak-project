#!/usr/bin/env bash
# Phase Gsce validator — restore the SCE "presents" screen in the first frames.
# Intentional content restoration (un-gate static-screen for all regions); the
# two title/static-screen goal_src files MAY change, the rest is locked.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GND_CLOSE=$(git log --format=%H --all --grep='Gnd-arm64-blendshape-dma-stomp' | head -1)
ANCHOR=${GND_CLOSE:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gsce validator (SCE 'presents' screen in first frames) =="

# 1. Locked set. IMPORTANT: this phase MAY edit goal_src title-obs.gc +
#    static-screen.gc (the SCE-gate restoration); the REST of goal_src is locked.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
OTHER_GOALSRC=$(git diff --name-only "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | grep -vE 'levels/title/title-obs\.gc$|levels/demo/static-screen\.gc$' || true)
[ -z "$OTHER_GOALSRC" ] || fail "goal_src edited beyond the allowed SCE files: $OTHER_GOALSRC"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ modified since Gref (read-only)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "locks ok (only title-obs.gc / static-screen.gc allowed in goal_src)"

# 2. Anti-cheat — no painted/hardcoded SCE image
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|sce_png|sony_png|presents_png)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded SCE image ($FAKE) — must render from the real static-screen asset"
ok "anti-cheat clean"

# 3. Report
[ -f .autoport/reports/Gsce-fix-summary.md ] || fail "no Gsce-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gsce-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gsce-fix-summary.md too short ($LINES)"
grep -qiE 'static-screen|sce|presents|territory|first.?boot' .autoport/reports/Gsce-fix-summary.md || fail "summary doesn't engage the SCE screen / static-screen restore"
ok "Gsce fix-summary present ($LINES lines)"

# 4. x86 smoke — must still boot (it may now ALSO show SCE; that's fine)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed (no longer reaches link finish: logo)"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gsce-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gsce-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 5. Device screencap
SHOT=$(ls .autoport/reports/Gsce-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gsce-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 6. THE GATE — static-screen now SPAWNS (not just links) on our territory, crash-free
NEWLOG=$(ls -t .autoport/reports/Gsce-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gsce routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (regression)"
# A spawn marker beyond the mere 'link finish: static-screen' that pristine also shows.
grep -aqiE 'static-screen.*spawn|spawn.*static-screen|static-screen-spawn|SCE.*spawn|presents.*spawn|GSCE-SCE-SPAWN' "$NEWLOG" || fail "no static-screen SPAWN marker — the SCE screen still only links, never spawns on our territory (un-gate not effective)"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
ok "static-screen SPAWNS, crash-free, frame=$FM"

# 7. Focus held
NF=$(ls -t .autoport/reports/Gsce-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gsce-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gsce — SCE static-screen spawns on our territory, crash-free (frame=$FM). Supervisor pixel-judges the 'Sony Computer Entertainment' screen in the first frames."
