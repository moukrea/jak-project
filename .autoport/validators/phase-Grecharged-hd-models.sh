#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ghdmodels FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*HD MODELS [0-9]/4' "$R" || fail "no RESULT: HD MODELS <landed>/4"
grep -qiE 'jak' "$R" && grep -qiE 'daxter' "$R" && grep -qiE 'samos' "$R" && grep -qiE 'keira|fille' "$R" || fail "must give a per-character verdict (Jak/Daxter/Samos/Keira)"
grep -qiE 'skeleton|bone|rig|weight|skin' "$R" || fail "must document the rig/bone mapping work"
grep -qiE 'conditional|jak2.*(present|available|dispo)|build flag' "$R" || fail "must implement the jak2-availability conditional build"
grep -qiE 'enhanced models|toggle|on/off' "$R" || fail "must add the ENHANCED MODELS toggle in Recharged Settings"
grep -qiE 'hidden|absent|without jak2' "$R" || fail "must prove the option hides on a no-jak2 build"
grep -qiE 'off.*(stock|identical|unchanged)' "$R" || fail "must prove OFF == stock"
grep -qiE 'deform|anim.*(play|drive|ok)|walk|idle' "$R" || fail "must show jak1 anims drive the new meshes without broken deformation"
FRAME=$(find .autoport/reports/Grecharged-hd-models -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no ON/OFF visual evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "must assert jak1 foreground at capture"
grep -qiE 'link finish: logo' "$R" || fail "x86 smoke missing"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Ghdmodels PASS]"
