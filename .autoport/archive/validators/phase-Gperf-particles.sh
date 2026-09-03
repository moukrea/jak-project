#!/usr/bin/env bash
# Validator — Gperf-particles: particle-heavy scene fps measurably improved, numeric A/B, no
# visual regression (eco bursts + orbs re-verified). Objective markers + x86 smoke; device+owner
# via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpp FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpp ok] $*"; }

R=.autoport/reports/Gperf-particles/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*PARTICLE[[:space:]]+PERF[[:space:]]+[0-9.]+[[:space:]]*->[[:space:]]*[0-9.]+[[:space:]]*FPS' "$R" \
  || fail "report lacks numeric RESULT: PARTICLE PERF <before>-><after> FPS"
python3 - "$R" <<'EOF' || exit 1
import re,sys
t=open(sys.argv[1]).read()
m=re.search(r'RESULT:\s*PARTICLE\s+PERF\s+([0-9.]+)\s*->\s*([0-9.]+)\s*FPS',t,re.I)
b,a=float(m.group(1)),float(m.group(2))
need=max(b*1.20, b+5.0)
if a+1e-9 < need:
    print(f"[Gpp FAIL] gain too small: {b}->{a} (need >= {need:.1f} = max(+20%, +5fps))",file=sys.stderr); sys.exit(1)
print(f"[Gpp ok] numeric gain {b}->{a} fps")
EOF
grep -qiE 'fire|feu|torch|bonfire|misty|particle.?heav' "$R" || fail "must profile a particle-heavy (fire) scene"
grep -qiE 'A35-PERF|buckets_ms|per.?famil|profile' "$R" || fail "must include the per-family profile"
grep -qiE 'sparticle|sprite|generic' "$R" || fail "must name the particle family cost"
grep -qiE 'cpu|kernel|mips2c|dma.?chain|submission' "$R" || fail "must split CPU vs submission cost"
grep -qiE 'draws?.*[0-9]+|draw.?count' "$R" || fail "must report draw counts"
grep -qiE 'pose.?held|in.?session|A/B|same boot' "$R" || fail "must use a pose-held in-session A/B"
grep -qiE 'eco.*(burst|pickup|intact|unregress)|regress.*eco' "$R" || fail "must re-verify eco bursts (same family — regression risk)"
grep -qiE 'orb.*(hud|intact|unregress)' "$R" || fail "must re-verify orb HUD"
grep -qiE 'kill.?switch|nobatch|prop.*restore' "$R" || fail "must ship a kill switch per change"
grep -qiE 'flicker' "$R" || fail "must confirm 0 flicker"
grep -qiE 'night|nuit|time.?of.?day|tod|day.?vs.?night|night.?vs.?day' "$R" || fail "owner clue: night is worse than day — must profile NIGHT vs DAY and address the night-specific cost, not just a day scene"
ok "report: numeric A/B + profile + family + CPU/submission split + night regime + regressions re-verified"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gperf-particles\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ game/ 2>/dev/null; git status --porcelain -- android/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/' || fail "no renderer/runtime perf change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
# Anchor-staleness escape hatch (matches the newer sibling phase-Gcrash-swamp-load.sh):
# the pinned ANCHOR predates completed prior-phase OWNER fixes (Gndskip's
# title-obs.gc landed between the anchor and HEAD), so their goal_src changes leak
# into this diff even though THIS phase's perf work touches no goal_src. Allow a
# DOCUMENTED prior-phase / pristine state; still HARD-FAIL an undocumented change.
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented|prior.?phase' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer/runtime fix; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gpp PASS] particle-perf markers present; x86 ok. (close-gate next)"
