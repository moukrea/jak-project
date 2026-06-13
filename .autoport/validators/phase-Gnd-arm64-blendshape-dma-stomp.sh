#!/usr/bin/env bash
# Phase Gnd validator — fix the arm64 blend-shape/joint OOB stomp (bucket-NEXT
# -> 0x1a50) so the ND/Daxter logo renders. Hard gates: title-regression,
# corruption-absence on ndi frames, render signal. ND-logo visibility = my eyes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GINTRO_CLOSE=$(git log --format=%H --all --grep='Gintro-sce-nd-logo-render' | head -1)
ANCHOR=${GINTRO_CLOSE:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gnd validator (arm64 blend-shape/joint OOB stomp -> ND logo renders) =="

# 1. Forbidden edits
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (pristine-correct — fix arm64 codegen/runtime)"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ (gold reference) modified since Gref — read-only"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat — no buffer-widening masks, no painted ND logo
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true); [ "$WEAK" -eq 0 ] || fail "weak symbol additions"
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|nd_logo|ndi_png)' || true); [ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded ND logo ($FAKE)"
ok "anti-cheat clean"

# 3. Required report — must engage the exact stomp + the OOB writer
[ -f .autoport/reports/Gnd-fix-summary.md ] || fail "no Gnd-fix-summary.md"
LINES=$(wc -l < .autoport/reports/Gnd-fix-summary.md); [ "$LINES" -ge 80 ] || fail "Gnd-fix-summary.md too short ($LINES)"
grep -qiE '0x1a50|bucket.?next|0x501a50|default-regs-buffer' .autoport/reports/Gnd-fix-summary.md || fail "summary doesn't engage the bucket-NEXT/0x1a50 stomp"
grep -qiE 'blend.shape|joint|decompress|oob|out.of.bound|overrun' .autoport/reports/Gnd-fix-summary.md || fail "summary doesn't identify the OOB writer"
ok "Gnd fix-summary present ($LINES lines)"

# 4. x86 smoke + qemu
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gnd-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gnd-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 5. Renderer present
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1); [ -n "$LIBGK" ] || fail "no libgk.so"
NMF=$(mktemp); nm -C "$LIBGK" > "$NMF" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NMF" 2>/dev/null || true
[ "$(grep -ciE 'MercRenderer|Merc2' "$NMF")" -ge 5 ] || { rm -f "$NMF"; fail "Merc renderer missing"; }; rm -f "$NMF"
ok "renderer present"

# 6. Device screencap
SHOT=$(ls .autoport/reports/Gnd-device-*.png 2>/dev/null | head -1); [ -n "$SHOT" ] || fail "no Gnd-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null||echo 0)" -gt 1000 ] || fail "screencap empty"
ok "device screencap present: $(basename "$SHOT")"

# 7. THE GATE — crash-free, ndi runs, and the stomp is GONE
NEWLOG=$(ls -t .autoport/reports/Gnd-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gnd routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (title-regression)"
grep -aqiE 'ndi-intro|ndi\b' "$NEWLOG" || fail "no ndi markers — the ND logo state must run"
# Corruption-absence: the fix must eliminate the 0x1a50 bucket-NEXT stomp.
STOMP=$(grep -acE '0x1a50|=0x1a50|next.*0x1a50|low-addr.*0x1a50|bucket.*0x1a50' "$NEWLOG" 2>/dev/null || true)
[ "${STOMP:-0}" -eq 0 ] || fail "the bucket-NEXT stomp PERSISTS ($STOMP x 0x1a50 lines) — ND logo still won't draw"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}
[ "$TR" -gt 0 ] || fail "renderer draws nothing (tris=$TR)"
ok "crash-free, ndi runs, NO 0x1a50 stomp, frame=$FM tris=$TR"

# 8. Focus held
NF=$(ls -t .autoport/reports/Gnd-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gnd-focus-*.txt"
echo "$(grep -a . "$NF" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "final focus org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase Gnd — bucket-NEXT stomp gone, ndi runs crash-free (frame=$FM, tris=$TR). Supervisor pixel-judges whether the ND logo + Daxter actually render."
