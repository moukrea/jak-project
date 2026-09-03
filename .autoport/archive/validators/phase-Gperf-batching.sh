#!/usr/bin/env bash
# Validator — Gperf-batching: draw-call batching with a NUMERIC fps gain + visual parity.
# Objective markers + numeric before/after + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpb FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpb ok] $*"; }

R=.autoport/reports/Gperf-batching/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*DRAW[[:space:]]+BATCHING[[:space:]]+FPS' "$R" || fail "report lacks RESULT: DRAW BATCHING FPS <before>-><after>"
grep -qiE 'profil|per-?family|draws.*ms|buckets_ms' "$R" || fail "must include the per-family profile table"
grep -qiE 'batch|merge|multidraw|state.*(sort|cache|redundant)|instanc|ubo' "$R" || fail "must describe the batching technique(s)"
# NUMERIC gain: extract before->after fps and require a real improvement (>= +5 fps)
python3 - "$R" <<'PY' || fail "no numeric fps improvement (need >= +5 fps, honest numbers)"
import re,sys
t=open(sys.argv[1],errors='replace').read()
m=re.search(r'RESULT:\s*DRAW\s+BATCHING\s+FPS\s*([\d.]+)\s*(?:->|→)\s*([\d.]+)',t,re.I)
if not m: print("FAIL: RESULT line must carry numeric before->after fps",file=sys.stderr); sys.exit(1)
b,a=float(m.group(1)),float(m.group(2))
if a < b+5: print(f"FAIL: fps {b}->{a} (<+5) — not a meaningful gain",file=sys.stderr); sys.exit(1)
print(f"OK: fps {b}->{a}")
PY
grep -qiE 'visual.*(parity|identical|no.*regress)|screencap.*(identical|match)|before/after.*(identical|match)' "$R" || fail "must prove visual parity (screencap before/after identical)"
grep -qiE 'flicker|0.*black|screenrecord' "$R" || fail "must confirm 0 flicker (screenrecord)"
grep -qiE 'collision|blueeco|blue.?eco|speed|camera|dynamic' "$R" || fail "must confirm prior fixes intact"
ok "report: profile + technique + numeric gain + visual parity + fixes intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gperf-batching\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ 2>/dev/null; git status --porcelain -- android/ game/graphics/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|graphics/' || fail "no renderer change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — batching is renderer-side"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer-side change; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"

echo "[Gpb PASS] batching markers + numeric gain present; x86 ok. (close-gate next)"
