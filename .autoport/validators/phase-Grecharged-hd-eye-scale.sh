#!/usr/bin/env bash
# Validator — Grecharged-hd-eye-scale (owner 2026-08-06)
set -uo pipefail
fail(){ echo "[Grecharged-hd-eye-scale FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-eye-scale/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-hd-eye-scale/report.txt)"
PSTART=$(python3 -c "
import json,datetime
try:
    v=json.load(open('.autoport/state.json')).get('phase_started_at',0)
    if isinstance(v,dict): v=v.get('Grecharged-hd-eye-scale',0)
    print(int(datetime.datetime.fromisoformat(v).timestamp()) if isinstance(v,str) and v else int(v or 0))
except Exception: print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"
grep -qiE "phase-NEW|Grecharged-hd-eye-scale" "$R" || fail "no phase-NEW marker (borrowed report?)"
# root cause must be named, not just 'reduced a constant'
grep -qiE "(why|pourquoi|root.?cause|because).{0,120}(HD|bind|absolute|relatif|relative|base)" "$R" \
  || fail "no root cause for why the cartoon eye-scale hits HD eyes harder than stock"
# measured scale factors, code-level, stock vs HD, min AND max
python3 - "$R" <<'PYG' || fail "no measured eye-scale min/max for BOTH stock and HD showing HD <= stock"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
def grab(tag):
    m=re.findall(tag+r'[^\n]{0,140}?(?:max)[^0-9\n-]{0,12}(-?[0-9]+\.?[0-9]*)',t,re.I)
    return [float(x) for x in m]
hd,stock=grab(r'\bHD\b'),grab(r'\bstock\b')
sys.exit(0 if hd and stock and max(hd)<=max(stock)*1.02 else 1)
PYG
grep -qiE "(effect|effet).{0,60}(kept|conserv|still|preserved|non nul|nonzero)" "$R" \
  || fail "must prove the cartoon effect is REDUCED, not removed"
grep -qiE "(jak|keira|samos|variant|look).{0,80}(same channel|même canal|checked|verif)" "$R" \
  || fail "other HD characters sharing the channel not checked"
grep -qiE "capture|screenshot|screencap|visual" "$R" && fail "visual proof present — permanently banned by the owner"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"

# OWNER-REJECT 2026-08-08: the compressed channel was not the one that makes the eye look big.
# The symptom is measurable: the two eyes TOUCH. Gate on that, not on the iris zoom.
python3 - "$R" <<'PYEYE' || fail "EYE-GAP: no edge-to-edge distance between Daxter's two eyes, stock vs HD, on an exaggerated animation — the owner's symptom is that they TOUCH, and that is the number that cannot lie"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
sys.exit(0 if re.search(r'(gap|edge[- ]to[- ]edge|inter[- ]?eye|entre les deux yeux)[^\n]{0,60}[0-9]',t,re.I) else 1)
PYEYE
grep -qiE "(quad|blerc|blend target|eye bone|scale)[^\n]{0,90}(ruled out|elimin|not the|excluded|is the)" "$R" \
  || fail "EYE-CHAN: the report must name which channel actually drives the on-screen size and explicitly rule out the others (iris zoom, eye quad scale, blend target, bone scale, eye table)"

echo "[Grecharged-hd-eye-scale PASS]"
