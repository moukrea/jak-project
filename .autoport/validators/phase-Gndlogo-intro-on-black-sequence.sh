#!/usr/bin/env bash
# Phase Gndlogo validator — the ND-logo intro must play ON BLACK, in order,
# before the title. Gates MECHANICS + REGRESSION (esp. anti-deadlock: the
# flythrough must NOT be black). The FINAL visual judgment (ND logo + Jak push
# + stamp on black, correct order) is the SUPERVISOR's by eye.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
GREF_CLOSE=$(git log --format=%H --all --grep='autoport/Gref-pristine' | head -1); GREF_CLOSE=${GREF_CLOSE:-$ANCHOR}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase Gndlogo validator (ND-logo intro on black, in order) =="

# 1. Forbidden edits — x86 oracle locked; no CGO regen via (mi); gold read-only.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$GREF_CLOSE" HEAD -- '.autoport/gold/' 2>/dev/null | wc -l)" -eq 0 ] || fail ".autoport/gold/ modified since Gref (read-only)"
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited"
ok "no forbidden edits"

# 2. Anti-cheat — no painted/faked intro / hardcoded frame.
FAKE=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|nd_logo_png|fake_intro)' || true)
[ "$FAKE" -eq 0 ] || fail "suspicious painted/hardcoded intro ($FAKE)"
ok "anti-cheat clean"

# 3. Report engages the state machine + oracle-diff (not just "renders").
SUM=.autoport/reports/Gndlogo-fix-summary.md
[ -f "$SUM" ] || fail "no Gndlogo-fix-summary.md"
LINES=$(wc -l < "$SUM"); [ "$LINES" -ge 80 ] || fail "Gndlogo-fix-summary.md too short ($LINES)"
grep -qiE 'ndi|naughty|logo|bg-a|display-self|enter-state|trans' "$SUM" || fail "summary doesn't engage the ndi/logo state machine"
grep -qiE 'oracle|x86|arm64|tier|loaded|loading|display.*level' "$SUM" || fail "summary shows no arm64-vs-x86 timing oracle-diff"
ok "fix-summary present + engages ndi timing ($LINES lines)"

# 4. Full-sequence frames for supervisor pixel-judgment.
NSEQ=$(ls .autoport/reports/Gndlogo/device-seq-*.png 2>/dev/null | wc -l)
[ "$NSEQ" -ge 8 ] || fail "only $NSEQ Gndlogo/device-seq-*.png (need >=8 spanning intro->title for supervisor eye)"
BIG=$(find .autoport/reports/Gndlogo -name 'device-seq-*.png' -size +20k 2>/dev/null | wc -l)
[ "$BIG" -ge 4 ] || fail "sequence frames look empty/trivial ($BIG non-trivial)"
ok "intro sequence captured ($NSEQ frames, $BIG non-trivial)"

# 5. x86 oracle still boots.
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "x86 smoke regressed"; }
ok "x86 smoke passes"
if [ -x .autoport/lib/qemu_repro.sh ]; then bash .autoport/lib/qemu_repro.sh > /tmp/gndlogo-qemu.log 2>&1 || true; N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/gndlogo-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0); [ "$N" -ge 675 ] || fail "qemu regressed: $N"; ok "qemu $N"; fi

# 6. Device run: crash-free + sustained + focus held.
NEWLOG=$(ls -t .autoport/reports/Gndlogo-routed-logcat-*.log 2>/dev/null | head -1); [ -n "$NEWLOG" ] || fail "no Gndlogo routed logcat"
CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true); [ "${CR:-0}" -eq 0 ] || fail "CRASH: $CR sig=11 (regression)"
FM=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
[ "$FM" -ge 300 ] || fail "boot not sustained: frame=$FM"
NF=$(ls -t .autoport/reports/Gndlogo-focus-*.txt 2>/dev/null | head -1); [ -n "$NF" ] || fail "no Gndlogo-focus-*.txt"
grep -a . "$NF" | tail -1 | grep -q "org.opengoal.gk.jak1" || fail "final focus not the app"
ok "crash-free, frame=$FM, focus held"

# 7. ANTI-DEADLOCK REGRESSION — the flythrough must NOT be black.
# The black/deadlocked title pins at ~132 tris / ~29KB chain. Require a late
# frame with village-scale geometry to prove the village actually renders.
TR=$(grep -a 'A35-RENDER frame=' "$NEWLOG" | grep -oE 'tris=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); TR=${TR:-0}
[ "$TR" -ge 200000 ] || fail "flythrough looks BLACK/deadlocked: max tris=$TR (<200k) — village not rendering"
ok "village renders in flythrough (max tris=$TR)"

echo ""
echo "PASS(mechanics): Phase Gndlogo — no regression, village renders (tris=$TR), $NSEQ sequence frames captured."
echo "SUPERVISOR must now verify BY EYE: ND animated logo + Jak push + stamp ON BLACK, correct order, BEFORE the J&D title; shrub/TIE detail intact."
