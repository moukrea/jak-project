#!/usr/bin/env bash
# Phase Gwater validator — fix ocean/water rendering. Gates: crash-free, ocean
# renderer present/active, regression; water correctness = supervisor eyes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GTITLE_CLOSE=$(git log --format=%H --all --grep='Gtitle-attract-overspawn' | head -1)
ANCHOR=${GTITLE_CLOSE:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gwater validator (ocean/water render) =="

# 1. Forbidden edits
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (ocean .gc is pristine-correct)"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ modified since Gref (read-only)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat — no painted/faked water
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|water_png|fake_reflection)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded water ($FAKE)"
ok "anti-cheat clean"

# 3. Report
[ -f .autoport/reports/Gwater-fix-summary.md ] || fail "no Gwater-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gwater-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gwater-fix-summary.md too short ($LINES)"
grep -qiE 'ocean|water|OceanTexture|OceanMid|OceanNear|OceanFar|CommonOcean' .autoport/reports/Gwater-fix-summary.md || fail "summary doesn't engage the ocean renderer"
grep -qiE 'tier|oracle|pristine|render.*to.*texture|bucket|blend|mips2c|gold' .autoport/reports/Gwater-fix-summary.md || fail "summary shows no render-path diff vs gold"
ok "Gwater fix-summary present ($LINES lines)"

# 4. x86 smoke + qemu
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gwater-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gwater-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 5. Ocean renderer physically present in libgk.so
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1); [ -n "$LIBGK" ] || fail "no libgk.so"
NMF=$(mktemp); nm -C "$LIBGK" > "$NMF" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NMF" 2>/dev/null || true
OCEAN=$(grep -ciE 'Ocean(Texture|Mid|Near|Far)|CommonOcean' "$NMF" || true); rm -f "$NMF"
[ "${OCEAN:-0}" -ge 3 ] || fail "ocean renderer not compiled into libgk.so ($OCEAN syms) — the ocean path is the phase"
ok "ocean renderer present ($OCEAN syms)"

# 6. Device screencap
SHOT=$(ls .autoport/reports/Gwater-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gwater-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 7. THE GATE — crash-free, sustained, title still flies
NEWLOG=$(ls -t .autoport/reports/Gwater-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gwater routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (regression)"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}
[ "$TR" -gt 0 ] || fail "renderer draws nothing"
ok "crash-free, frame=$FM, tris=$TR"

# 8. Focus held
NF=$(ls -t .autoport/reports/Gwater-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gwater-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gwater — crash-free (frame=$FM), ocean renderer active. Supervisor pixel-judges the water vs the original."
