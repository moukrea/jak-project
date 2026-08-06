#!/usr/bin/env bash
# Grecharged-secondary-motion validator — phase-specific (generated 2026-08-05; never borrow another phase's validator).
set -uo pipefail
fail(){ echo "[Grecharged-secondary-motion FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-secondary-motion/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-secondary-motion/report.txt)"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    import datetime
    v=s.get('phase_started_at',0)
    print(int(datetime.datetime.fromisoformat(v).timestamp()) if isinstance(v,str) else int(v))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"

grep -qiE "(chain|spring|verlet).{0,60}(state|dump|bounded|rest|converge)" "$R" || fail "no chain state-dump evidence (bounded, returns to rest, no NaN)"
grep -qiE "FLAG_PHYSICS|--physics" "$R" || fail "no --physics flag evidence"
grep -qiE "(precision|niveau).{0,60}(level|menu|selector|toggle)" "$R" || fail "no precision-levels + menu toggle evidence"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"

# ---- CYCLE 3 (owner verdict 2026-08-06) — each gate = one owner complaint, code/counter-level only ----
# A. authored-anim priority: suspension must ENGAGE and RELEASE, with a blend (no snap)
grep -qiE "authored.{0,30}(priority|hold|suspend).{0,80}[0-9]+" "$R" || fail "A: no authored-anim-priority counter (engage/release) in report"
grep -qiE "(blend|ramp).{0,50}(in|out|resume).{0,40}(physics|chain)" "$R" || fail "A: no blend-back evidence (physics must resume progressively, not snap)"
grep -qiE "(goggles|lunettes).{0,80}(suspend|hold|authored)" "$R" || fail "A: Keira goggles grab-animation suspension not proven"
# B. spawn / big transition burst must be zero
grep -qiE "(spawn|transition).{0,50}burst.{0,20}=.{0,6}0\b" "$R" || fail "B: no spawn/big-transition burst=0 counter"
# C. tapered colliders (flared trousers, shoulders)
grep -qiE "(taper|cone|conic|r0.{0,10}r1|two.{0,10}radi)" "$R" || fail "C: no tapered/two-radius collider evidence (flared trousers)"
grep -qiE "resid.{0,20}=.{0,6}0\b" "$R" || fail "C: no penetration resid=0"
# D. gradient adapted to chain length: NO declared chain may be frozen
grep -qiE "(stiff|frozen|dead).{0,30}chains?.{0,20}=.{0,6}0\b" "$R" || fail "D: no proof that zero declared chains are frozen (Keira back hair was stiff)"
grep -qiE "(jak).{0,40}(hair|coiffe).{0,60}(link|maillon|span).{0,30}[0-9]" "$R" || fail "D: no per-link motion span for Jak hair (only the tip moved)"
# E. chains that were missing
grep -qiE "(ring|anneau).{0,40}(plastron|chest|breastplate)" "$R" || fail "E: Jak chest-plate metal ring chain missing"
grep -qiE "(ear|oreille)" "$R" || fail "E: Jak ears chain missing"
# F. Keira straps regression: fixed OR reverted — must be stated explicitly
grep -qiE "(strap|bretelle).{0,90}(fixed|follows|suivi|surface|REVERTED|retir)" "$R" || fail "F: Keira straps regression neither fixed nor explicitly reverted"
# G. chest amplitude must be clearly ABOVE the cycle-2 baseline (max was 272.4)
python3 - "$R" <<'PYG' || fail "G: chest jiggle amplitude not proven above the cycle-2 baseline (272.4)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
m=[float(x) for x in re.findall(r'(?:chest|poitrine)[^\n]{0,120}?(?:max|amp)[^0-9\n]{0,12}([0-9]+\.?[0-9]*)',t,re.I)]
sys.exit(0 if m and max(m)>400 else 1)
PYG

echo "[Grecharged-secondary-motion PASS]"
